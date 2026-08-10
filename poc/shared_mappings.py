"""
Append-only shared learned-mappings log, kept in a real .xlsx file so it's
directly readable/reviewable in Excel by anyone -- unlike db.py's SQLite
mappings.db, which is opaque outside this tool. Every confirmation appends a
new timestamped row rather than editing one in place: a same-moment write
from two consultants can at worst produce OneDrive's usual conflicted-copy
fork (see poc/README.md), but it can never silently overwrite someone else's
row the way an update-in-place design could.

db.py is untouched by this file and stays exactly as it is -- a fast,
always-available per-machine cache. This module is a second, independent
read+write path that app.py consults alongside it (see poc/README.md,
"Shared mapping log").

Optional dependency: openpyxl. Only imported if CW_ETL_SHARED_XLSX is set --
an installation that doesn't use this feature never needs it.
"""

import datetime
import getpass
import os

from db import normalize

SHARED_XLSX_PATH = os.environ.get("CW_ETL_SHARED_XLSX")

# (column header written to the sheet, key used in an in-memory row dict).
# Single source of truth for both directions -- reading builds a row dict
# keyed this way, writing emits values in this same header order.
FIELDS = [
    ("TargetDatabase", "targetDatabase"),
    ("SourceSystem", "sourceSystem"),
    ("SourceField", "sourceField"),
    ("TargetTable", "targetTable"),
    ("TargetField", "targetField"),
    ("ConfirmedAt", "confirmedAt"),
    ("ConfirmedBy", "confirmedBy"),
    # Added after the log already had real rows -- always append new fields
    # here at the end, never insert in the middle. Existing rows' cells stay
    # in their original physical columns; inserting a header in the middle
    # would misalign them against a header that no longer matches where
    # their values actually sit.
    ("Description", "desc"),
    # Same append-at-the-end rule. Holds the customer's confirmed source-
    # value -> target-code mapping from the Advanced-mode value-matching
    # step (e.g. "M=1,F=2,U=3"), written by append_value_map -- a distinct
    # confirmation from the field-mapping one above, so most rows leave this
    # blank until/unless that step is confirmed for that field.
    ("ValueMap", "valueMap"),
]
REQUIRED_KEYS = ("targetDatabase", "sourceSystem", "sourceField", "targetTable", "targetField")
SHEET_NAME = "ConfirmedMappings"

_openpyxl = None
_unavailable_reason = None


def _load_openpyxl():
    """Imported lazily and only once -- most installations never touch this
    feature, so most installations never need openpyxl on disk at all."""
    global _openpyxl, _unavailable_reason
    if _openpyxl is not None or _unavailable_reason is not None:
        return _openpyxl
    try:
        import openpyxl
        _openpyxl = openpyxl
    except ImportError:
        _unavailable_reason = "openpyxl isn't installed (run: pip install openpyxl, or see poc/requirements-optional.txt)"
    return _openpyxl


class SharedLog:
    """In-process cache of the shared file's rows, built once by load() and
    kept current in memory as this process appends its own confirmations --
    avoids re-parsing the whole workbook on every suggestion lookup."""

    def __init__(self):
        self.rows = []             # raw row dicts, oldest first
        self.exact = {}            # (target_db, source_system_norm, field_name_norm) -> {target, count, lastConfirmedAt}
        self.field_index = {}      # (target_db, field_name_norm) -> {(table, field): count}
        self.decode_patterns = {}  # (target_db, target_table, target_field) -> {desc: count}
        self.value_maps = {}       # (target_db, source_system_norm, field_name_norm) -> {valueMap, confirmedAt}
        self.path = None
        self.status = "disabled"  # disabled | missing-dependency | not-found | ok | error
        self.detail = ""

    def load(self, path):
        self.path = path
        self.rows = []
        self.exact = {}
        self.field_index = {}
        self.decode_patterns = {}
        self.value_maps = {}
        if not path:
            self.status = "disabled"
            self.detail = "CW_ETL_SHARED_XLSX not set"
            return
        openpyxl = _load_openpyxl()
        if openpyxl is None:
            self.status = "missing-dependency"
            self.detail = _unavailable_reason
            return
        if not os.path.exists(path):
            self.status = "not-found"
            self.detail = f"{path} does not exist yet"
            return
        try:
            wb = openpyxl.load_workbook(path, read_only=True, data_only=True)
            ws = wb.active
            header = None
            for raw_row in ws.iter_rows(values_only=True):
                if header is None:
                    header = [str(c).strip() if c else "" for c in raw_row]
                    continue
                if not any(raw_row):
                    continue
                self._ingest(dict(zip(header, raw_row)))
            wb.close()
            self.status = "ok"
            self.detail = f"{len(self.rows)} row(s) from {path}"
        except Exception as e:  # noqa: BLE001 -- a shared file we don't control must never be able to crash the server
            self.status = "error"
            self.detail = str(e)

    def _ingest(self, record):
        row = {key: (record.get(header) or "") for header, key in FIELDS}
        if not all(row[k] for k in REQUIRED_KEYS):
            return
        self.rows.append(row)
        # Known minor imprecision: a row written by append_value_map (not
        # append) still has a real targetTable/targetField, so a reload
        # counts it as a second confirmation of that same mapping on top of
        # the field-confirm row that already exists -- confirm_count ends up
        # one higher than the number of times the *field mapping itself* was
        # actually reconfirmed. Doesn't affect which table/field/value_map
        # get_exact returns, only that display counter, so left as-is rather
        # than adding a row-type column to distinguish the two append kinds.
        self._reindex_row(row)
        self._reindex_value_map(row)

    def _reindex_value_map(self, row):
        """Tracks the latest confirmed value_map per (target_db, source
        system, field) -- last-write-wins, same as how a changed field-
        mapping decision overwrites the running count in _reindex_row,
        except there's no count here: a value map is either the current
        confirmed one or it isn't."""
        if not row.get("valueMap"):
            return
        key = (row["targetDatabase"], normalize(row["sourceSystem"]), normalize(row["sourceField"]))
        self.value_maps[key] = {"valueMap": row["valueMap"], "confirmedAt": row.get("confirmedAt") or ""}

    def _reindex_row(self, row):
        tdb = row["targetDatabase"]
        ss_norm = normalize(row["sourceSystem"])
        fn_norm = normalize(row["sourceField"])
        target = (row["targetTable"], row["targetField"])

        # Exact match: track the running count for whichever target is most
        # recent, resetting if a later confirmation named a different one --
        # mirrors db.py's confirm_count semantics (changing your mind about a
        # mapping starts its count over rather than piling onto the old one).
        key = (tdb, ss_norm, fn_norm)
        existing = self.exact.get(key)
        if existing and existing["target"] == target:
            existing["count"] += 1
            existing["lastConfirmedAt"] = row["confirmedAt"] or existing["lastConfirmedAt"]
        else:
            self.exact[key] = {"target": target, "count": 1, "lastConfirmedAt": row["confirmedAt"]}

        # Field index: every confirmation counts, including repeats of the
        # same mapping -- matches db.py's unconditional field_index increment.
        idx_key = (tdb, fn_norm)
        bucket = self.field_index.setdefault(idx_key, {})
        bucket[target] = bucket.get(target, 0) + 1

        # Decode patterns: what consultants typed as the source-side format
        # note for this exact target field, across any source system --
        # never anything from a source system's real data, just field-format
        # text a human typed in. Feeds transform_draft.py's "established
        # pattern" signal the same way db.get_decode_patterns does locally.
        if row.get("desc"):
            pattern_key = (tdb, row["targetTable"], row["targetField"])
            pattern_bucket = self.decode_patterns.setdefault(pattern_key, {})
            pattern_bucket[row["desc"]] = pattern_bucket.get(row["desc"], 0) + 1

    def get_decode_patterns(self, target_db, target_table, target_field):
        bucket = self.decode_patterns.get((target_db, target_table, target_field))
        if not bucket:
            return []
        return sorted(
            ({"desc": d, "count": c} for d, c in bucket.items()),
            key=lambda r: r["count"],
            reverse=True,
        )

    def get_exact(self, target_db, source_system, field_name):
        entry = self.exact.get((target_db, normalize(source_system), normalize(field_name)))
        if not entry:
            return None
        table, field = entry["target"]
        return {
            "target_table": table,
            "target_field": field,
            "confirm_count": entry["count"],
            "last_confirmed_at": entry["lastConfirmedAt"],
            "value_map": self.get_value_map(target_db, source_system, field_name) or "",
        }

    def get_value_map(self, target_db, source_system, field_name):
        entry = self.value_maps.get((target_db, normalize(source_system), normalize(field_name)))
        return entry["valueMap"] if entry else None

    def get_field_index(self, target_db, field_name):
        bucket = self.field_index.get((target_db, normalize(field_name)))
        if not bucket:
            return []
        return sorted(
            ({"target_table": t, "target_field": f, "count": c} for (t, f), c in bucket.items()),
            key=lambda r: r["count"],
            reverse=True,
        )

    def append(self, target_db, source_system, field_name, target_table, target_field, desc=""):
        """Appends one confirmation to the shared file, then mirrors it into
        this in-memory cache so this session's own confirmations are visible
        to its own next lookup without re-reading the whole workbook. Raises
        on failure -- callers decide whether that should block anything."""
        row = {
            "targetDatabase": target_db,
            "sourceSystem": source_system,
            "sourceField": field_name,
            "targetTable": target_table,
            "targetField": target_field,
            "confirmedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "confirmedBy": getpass.getuser(),
            "desc": desc or "",
            "valueMap": "",
        }
        self._write_row(row)
        self.rows.append(row)
        self._reindex_row(row)

    def append_value_map(self, target_db, source_system, field_name, target_table, target_field, value_map):
        """Appends a row recording a confirmed value map -- a distinct
        confirmation from append() above (which value goes to which approved
        code, not which target field this source field goes to), so it's
        its own append rather than reusing append()'s field-index/exact-
        count bookkeeping, which shouldn't be bumped just for this. desc is
        left blank on this row; the field-mapping row that already exists
        (from a prior append()) carries whatever desc was confirmed there."""
        row = {
            "targetDatabase": target_db,
            "sourceSystem": source_system,
            "sourceField": field_name,
            "targetTable": target_table,
            "targetField": target_field,
            "confirmedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "confirmedBy": getpass.getuser(),
            "desc": "",
            "valueMap": value_map or "",
        }
        self._write_row(row)
        self.rows.append(row)
        self._reindex_value_map(row)

    def _ensure_header_columns(self, ws):
        """Extends an existing header with any FIELDS columns it predates
        (e.g. Description, added after this log already had real rows) --
        always at the next free column, never touching existing header
        cells or shifting already-written data."""
        existing = [c.value for c in ws[1]]
        next_col = len(existing) + 1
        for header, _ in FIELDS:
            if header not in existing:
                ws.cell(row=1, column=next_col, value=header)
                existing.append(header)
                next_col += 1

    def _write_row(self, row):
        openpyxl = _load_openpyxl()
        if openpyxl is None:
            raise RuntimeError(_unavailable_reason)
        if not self.path:
            raise RuntimeError("no shared file path configured (set CW_ETL_SHARED_XLSX)")
        if os.path.exists(self.path):
            wb = openpyxl.load_workbook(self.path)
        else:
            wb = openpyxl.Workbook()
        ws = wb.active
        if ws.max_row <= 1 and ws.cell(1, 1).value is None:
            # A brand-new (or truly empty, like the shared file starts out)
            # worksheet still reports max_row=1 for a phantom blank row, which
            # makes the *first* append() land on row 2 instead of row 1 --
            # openpyxl quirk, verified directly. delete_rows resets that.
            ws.delete_rows(1, 1)
            ws.title = SHEET_NAME
            ws.append([header for header, _ in FIELDS])
        else:
            self._ensure_header_columns(ws)
        ws.append([row[key] for _, key in FIELDS])
        wb.save(self.path)


SHARED = SharedLog()


def init():
    """Call once at process startup. Safe to call again to force a re-read."""
    SHARED.load(SHARED_XLSX_PATH)
    return SHARED
