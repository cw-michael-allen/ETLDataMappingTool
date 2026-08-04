"""
CW-ETL-FIELDMAP Phase 0 POC server.

Pure standard library (no pip installs required). Serves the static frontend
and a small JSON API backed by a local SQLite datastore. Run with:

    python app.py

Then open http://127.0.0.1:8000 . Mapping suggestions come first from a
rule-based matcher grounded in the extracted validation-script schema
(field_matcher.py) and only fall back to the Anthropic API (if
ANTHROPIC_API_KEY is set) for names the rules can't confidently resolve.

Supports multiple target databases (schema_rules.TARGET_DATABASES) — today
that's CaseWorthy (fully populated) and ServTracker (listed for the UI, but
with no schema loaded yet; see schema_rules.py).
"""

import json
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import db  # noqa: E402
import field_matcher  # noqa: E402
import llm_gateway  # noqa: E402
import schema_rules  # noqa: E402

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
STATIC_DIR = os.path.join(BASE_DIR, "static")

DEFAULT_TARGET_DATABASE = schema_rules.DEFAULT_TARGET_DATABASE
_SCHEMA_CACHE = {}


def get_schema(target_db):
    if target_db not in _SCHEMA_CACHE:
        _SCHEMA_CACHE[target_db] = schema_rules.load_schema(target_db)
    return _SCHEMA_CACHE[target_db]


def get_candidates(target_db):
    return [
        {
            "table": f["table"],
            "field": f["field"],
            "required": f.get("required", False),
            "type": f.get("type"),
            "listId": f.get("listId"),
            "decode": f.get("decode"),
        }
        for f in get_schema(target_db)
    ]


CONTENT_TYPES = {
    ".html": "text/html; charset=utf-8",
    ".js": "application/javascript; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".png": "image/png",
    ".svg": "image/svg+xml",
}


class Handler(BaseHTTPRequestHandler):
    def _send_json(self, obj, status=200):
        body = json.dumps(obj).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _read_json(self):
        length = int(self.headers.get("Content-Length", 0) or 0)
        raw = self.rfile.read(length) if length else b"{}"
        return json.loads(raw or b"{}")

    def do_GET(self):
        parsed = urlparse(self.path)
        query = parse_qs(parsed.query)
        target_db = (query.get("targetDatabase") or [DEFAULT_TARGET_DATABASE])[0]

        if parsed.path == "/api/target-databases":
            return self._send_json(
                {"targetDatabases": sorted(schema_rules.TARGET_DATABASES.keys()), "default": DEFAULT_TARGET_DATABASE}
            )
        if parsed.path == "/api/schema":
            return self._send_json(get_schema(target_db))
        if parsed.path == "/api/stats":
            return self._send_json(db.get_stats(target_db))
        self._serve_static(parsed.path)

    def _serve_static(self, path):
        rel = path.lstrip("/") or "index.html"
        file_path = os.path.normpath(os.path.join(STATIC_DIR, rel))
        if not file_path.startswith(os.path.normpath(STATIC_DIR)):
            return self._send_json({"error": "forbidden"}, 403)
        if os.path.isdir(file_path):
            file_path = os.path.join(file_path, "index.html")
        if not os.path.isfile(file_path):
            return self._send_json({"error": "not found"}, 404)
        ext = os.path.splitext(file_path)[1]
        ctype = CONTENT_TYPES.get(ext, "application/octet-stream")
        with open(file_path, "rb") as f:
            body = f.read()
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        path = urlparse(self.path).path
        try:
            payload = self._read_json()
        except json.JSONDecodeError:
            return self._send_json({"error": "invalid JSON body"}, 400)

        target_db = payload.get("targetDatabase") or DEFAULT_TARGET_DATABASE

        if path == "/api/suggest":
            return self._send_json(self._handle_suggest(payload, target_db))
        if path == "/api/confirm":
            try:
                db.save_mapping(
                    payload["sourceSystem"], payload["fieldName"], payload["table"], payload["field"], target_db
                )
            except KeyError as e:
                return self._send_json({"error": f"missing field: {e}"}, 400)
            return self._send_json({"ok": True})
        if path == "/api/rulecheck":
            return self._send_json(schema_rules.check_batch(payload.get("mappings", []), get_schema(target_db)))
        return self._send_json({"error": "not found"}, 404)

    def _handle_suggest(self, payload, target_db):
        source_system = payload.get("sourceSystem", "")
        field_name = payload.get("fieldName", "")
        desc = payload.get("desc", "")
        schema = get_schema(target_db)

        learned = db.get_mapping(source_system, field_name, target_db)
        if learned:
            return {
                "table": learned["target_table"],
                "field": learned["target_field"],
                "confidence": "learned",
                "reasoning": f"Confirmed {learned['confirm_count']} time(s) before for {source_system}.",
            }

        if not schema:
            return {
                "table": None,
                "field": None,
                "confidence": "none",
                "reasoning": f"No target schema loaded for {target_db} yet.",
            }

        # Rule-based match against the validation-script-derived schema comes
        # first: it's free, instant, and doesn't need an API key. A high-
        # confidence rule match is used outright; anything softer still gets
        # a second opinion from the LLM (if configured) before deciding.
        rule_sug = field_matcher.match(field_name, schema)

        if rule_sug and rule_sug["confidence"] == "high":
            sug = rule_sug
        else:
            llm_sug = llm_gateway.suggest_mapping(source_system, field_name, desc, get_candidates(target_db))
            if llm_sug.get("confidence") in (None, "none") and rule_sug:
                sug = rule_sug
            else:
                sug = llm_sug
                if rule_sug and rule_sug["table"] == sug.get("table") and rule_sug["field"] == sug.get("field"):
                    sug["reasoning"] = (sug.get("reasoning") or "") + " Also matches by field-name pattern."

        cross = db.get_field_index(field_name, target_db)
        if cross and sug.get("confidence") not in (None, "none"):
            match = next(
                (c for c in cross if c["target_table"] == sug.get("table") and c["target_field"] == sug.get("field")),
                None,
            )
            if match:
                sug["reasoning"] = (sug.get("reasoning") or "") + (
                    f" Also mapped this way {match['count']} time(s) across other customers."
                )
        return sug

    def log_message(self, format, *args):  # noqa: A002
        sys.stderr.write("%s - %s\n" % (self.address_string(), format % args))


def main():
    port = int(os.environ.get("PORT", "8000"))
    host = os.environ.get("HOST", "127.0.0.1")
    server = ThreadingHTTPServer((host, port), Handler)
    display_host = host if host != "0.0.0.0" else "127.0.0.1 (also reachable on your LAN IP)"
    print(f"CW-ETL-FIELDMAP POC running at http://{display_host}:{port}")
    if host == "0.0.0.0":
        print("WARNING: bound to 0.0.0.0 — reachable by anyone on your network. There is no auth on this POC (by design, see docs/PHASE_PLAN.md) — anyone who can reach it can view and edit the shared mapping library.")
    if not os.environ.get("ANTHROPIC_API_KEY"):
        print("WARNING: ANTHROPIC_API_KEY not set — suggestions will come back as 'no confident match'.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        server.shutdown()


if __name__ == "__main__":
    main()
