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
import socketserver
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse, parse_qs

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import db  # noqa: E402
import field_matcher  # noqa: E402
import file_import  # noqa: E402
import llm_gateway  # noqa: E402
import schema_rules  # noqa: E402
import sql_export  # noqa: E402

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
STATIC_DIR = os.path.join(BASE_DIR, "static")

DEFAULT_TARGET_DATABASE = schema_rules.DEFAULT_TARGET_DATABASE
_SCHEMA_CACHE = {}


def get_schema(target_db):
    if target_db not in _SCHEMA_CACHE:
        _SCHEMA_CACHE[target_db] = schema_rules.load_schema(target_db)
    return _SCHEMA_CACHE[target_db]


def scoped_schema(target_db, modules):
    """The active schema for a request, narrowed to the selected modules."""
    return schema_rules.scope_schema(get_schema(target_db), target_db, modules)


def parse_modules(value):
    """Modules arrive as a JSON list (POST) or a repeated/comma query param."""
    if not value:
        return []
    if isinstance(value, str):
        return [m.strip() for m in value.split(",") if m.strip()]
    out = []
    for item in value:
        out.extend(m.strip() for m in str(item).split(",") if m.strip())
    return out


def describe_target_databases():
    """Everything the UI needs to render the target-database picker.

    `available` is derived from whether a schema actually loaded, not from a
    hardcoded name check -- that check was the reason adding a schema file
    wouldn't have been enough to enable a database in the UI.
    """
    out = []
    for name in sorted(schema_rules.TARGET_DATABASES):
        schema = get_schema(name)
        meta = schema_rules.db_meta(name)
        out.append(
            {
                "name": name,
                "label": meta["label"],
                "logo": meta["logo"],
                "available": bool(schema),
                "hasModules": bool(meta.get("modules")),
                "baseModules": meta.get("baseModules") or [],
                "unitNoun": meta.get("unitNoun", "table"),
                "groupNoun": meta.get("groupNoun", "module"),
                "scopingReason": meta.get("scopingReason", ""),
                "defaultSelectAll": bool(meta.get("defaultSelectAll")),
                "fieldCount": len(schema),
                "modules": schema_rules.list_modules(name, schema),
                "linkKey": next(
                    (
                        {"field": r["field"], "note": r.get("note")}
                        for r in schema
                        if r.get("linkKey")
                    ),
                    None,
                ),
            }
        )
    return out


def get_candidates(target_db, modules=None):
    # Same exclusion the rule matcher applies: a column that is never migrated
    # is not a valid destination, so the LLM must not see it as one either.
    schema = [r for r in scoped_schema(target_db, modules or []) if not r.get("notMigrated")]
    return [
        {
            "table": f["table"],
            "field": f["field"],
            "required": f.get("required", False),
            "type": f.get("type"),
            "listId": f.get("listId"),
            "decode": f.get("decode"),
            # ServTracker's allowed values are bare labels rather than
            # code=label pairs, so `decode` alone under-describes them.
            "decodeValues": f.get("decodeValues"),
            # ServTracker: the customer fills in a sheet, not an import table.
            "sheet": f.get("sheet"),
        }
        for f in schema
    ]


CONTENT_TYPES = {
    ".html": "text/html; charset=utf-8",
    ".js": "application/javascript; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
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

    def _handle_import_fields(self):
        # Bulk-import of Step 2 field names from a CSV/xlsx upload -- see
        # file_import.py for the header-row-only parsing and why. Handled
        # separately from the JSON POST routes below since the body here is
        # multipart/form-data, not JSON.
        length = int(self.headers.get("Content-Length", 0) or 0)
        if length > file_import.MAX_UPLOAD_BYTES:
            self.close_connection = True
            limit_mb = file_import.MAX_UPLOAD_BYTES // (1024 * 1024)
            return self._send_json(
                {
                    "error": (
                        f"That file is larger than expected for a column list (limit {limit_mb} MB). "
                        "This tool only needs field names, not data -- upload a smaller export."
                    )
                },
                413,
            )
        body = self.rfile.read(length) if length else b""
        try:
            parts = file_import.parse_multipart(self.headers.get("Content-Type", ""), body)
            upload = parts.get("file")
            if not upload:
                return self._send_json({"error": "No file was attached to the upload."}, 400)
            filename, raw_bytes = upload
            mode_field = parts.get("advancedMode")
            advanced_mode = bool(mode_field) and mode_field[1].decode("utf-8", "replace").strip().lower() == "true"
            result = file_import.import_fields_from_upload(filename, raw_bytes, advanced_mode)
        except file_import.FileImportError as e:
            return self._send_json({"error": str(e)}, 400)
        return self._send_json(result)

    def do_GET(self):
        parsed = urlparse(self.path)
        query = parse_qs(parsed.query)
        target_db = (query.get("targetDatabase") or [DEFAULT_TARGET_DATABASE])[0]

        if parsed.path == "/api/target-databases":
            return self._send_json(
                {
                    "targetDatabases": describe_target_databases(),
                    "default": DEFAULT_TARGET_DATABASE,
                }
            )
        if parsed.path == "/api/dialects":
            return self._send_json(
                {"dialects": sorted(sql_export.DIALECTS.keys()), "default": sql_export.DEFAULT_DIALECT}
            )
        if parsed.path == "/api/schema":
            return self._send_json(scoped_schema(target_db, parse_modules(query.get("modules"))))
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

        if path == "/api/import-fields":
            return self._handle_import_fields()

        try:
            payload = self._read_json()
        except json.JSONDecodeError:
            return self._send_json({"error": "invalid JSON body"}, 400)

        target_db = payload.get("targetDatabase") or DEFAULT_TARGET_DATABASE
        modules = parse_modules(payload.get("modules"))

        if path == "/api/suggest":
            return self._send_json(self._handle_suggest(payload, target_db, modules))
        if path == "/api/confirm":
            try:
                db.save_mapping(
                    payload["sourceSystem"], payload["fieldName"], payload["table"], payload["field"], target_db
                )
            except KeyError as e:
                return self._send_json({"error": f"missing field: {e}"}, 400)
            return self._send_json({"ok": True})
        if path == "/api/rulecheck":
            return self._send_json(
                schema_rules.check_batch(payload.get("mappings", []), scoped_schema(target_db, modules))
            )
        if path == "/api/sql-export":
            dialect = payload.get("dialect") or sql_export.DEFAULT_DIALECT
            return self._send_json(
                sql_export.build_export(
                    payload.get("mappings", []), scoped_schema(target_db, modules), dialect
                )
            )
        return self._send_json({"error": "not found"}, 404)

    def _handle_suggest(self, payload, target_db, modules=None):
        source_system = payload.get("sourceSystem", "")
        field_name = payload.get("fieldName", "")
        desc = payload.get("desc", "")
        schema = scoped_schema(target_db, modules or [])

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
        rule_sug = field_matcher.match(field_name, schema, desc)

        if rule_sug and rule_sug["confidence"] == "high":
            sug = rule_sug
        else:
            llm_sug = llm_gateway.suggest_mapping(
                source_system,
                field_name,
                desc,
                get_candidates(target_db, modules),
                target_label=schema_rules.db_meta(target_db)["label"],
            )
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


class ThreadingHTTPServer(socketserver.ThreadingMixIn, HTTPServer):
    """Equivalent to http.server.ThreadingHTTPServer, built by hand instead
    of imported — that class only exists from Python 3.7 onward, while
    ThreadingMixIn and HTTPServer themselves are available in every Python 3
    release, so this runs on older interpreters too."""

    daemon_threads = True


def main():
    port = int(os.environ.get("PORT", "8000"))
    host = os.environ.get("HOST", "127.0.0.1")
    server = ThreadingHTTPServer((host, port), Handler)
    display_host = host if host != "0.0.0.0" else "127.0.0.1 (also reachable on your LAN IP)"
    print(f"CW-ETL-FIELDMAP POC running at http://{display_host}:{port}")
    if host == "0.0.0.0":
        print("WARNING: bound to 0.0.0.0 — reachable by anyone on your network. There is no auth on this POC (by design, see docs/PHASE_PLAN.md) — anyone who can reach it can view and edit the shared mapping library.")
    if os.environ.get("CW_ETL_DB_PATH"):
        print(f"Learned-mapping library: SHARED at {db.DB_PATH}")
    else:
        print(f"Learned-mapping library: local only at {db.DB_PATH} (set CW_ETL_DB_PATH to share it across machines — see poc/README.md, 'Shared learned-mappings library')")
    if not os.environ.get("ANTHROPIC_API_KEY"):
        print("WARNING: ANTHROPIC_API_KEY not set — suggestions will come back as 'no confident match'.")

    # Load every registered schema up front so unrecognised `type` strings are
    # reported at startup. Those fields silently skip all format checks, which
    # the UI would otherwise render as "no rule violations detected" — the one
    # failure mode of this rule engine that looks identical to success.
    for target_db in sorted(schema_rules.TARGET_DATABASES):
        schema = get_schema(target_db)
        if not schema:
            print("NOTE: no schema loaded for %s." % target_db)
            continue
        unknown = schema_rules.SCHEMA_WARNINGS.get(target_db) or []
        if unknown:
            print(
                "WARNING: %s has %d field(s) whose 'type' no format check recognises — "
                "they are NOT rule-checked (see reference/SCHEMA_FORMAT.md):" % (target_db, len(unknown))
            )
            for u in unknown:
                flag = "  <-- reads like a constraint but enforces nothing" if u["misleading"] else ""
                print("         %s.%s = %r%s" % (u["table"], u["field"], u["type"], flag))
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        server.shutdown()


if __name__ == "__main__":
    main()
