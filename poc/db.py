import datetime
import getpass
import os
import re
import sqlite3
import uuid

# Local by default (gitignored, per-machine). Set CW_ETL_DB_PATH to point this
# at a synced shared folder instead (e.g. a OneDrive-synced SharePoint library)
# so every consultant's confirmed mappings and field index accumulate in one
# place rather than starting over on each machine -- see poc/README.md,
# "Shared learned-mappings library".
DB_PATH = os.environ.get("CW_ETL_DB_PATH") or os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "data", "mappings.db"
)

DEFAULT_TARGET_DATABASE = "CaseWorthy"


def normalize(s):
    return re.sub(r"[^a-z0-9]", "", (s or "").strip().lower())


# PRAGMA/DDL statements can't take a placeholder for a table name (SQLite,
# like every SQL engine, only parameterizes values, not identifiers), so
# these two spots build the statement with an f-string. table is never
# user input -- always one of these two literals -- but this allowlist
# makes that a checked fact instead of an assumption a static scanner (or a
# future edit) has to take on faith.
_KNOWN_TABLES = frozenset({"mappings", "field_index"})


def _has_column(conn, table, column):
    if table not in _KNOWN_TABLES:
        raise ValueError(f"not a known table: {table!r}")
    cols = [row["name"] for row in conn.execute(f"PRAGMA table_info({table})").fetchall()]
    return column in cols


def get_conn():
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row

    # Mappings are now scoped per target database (CaseWorthy, ServTracker,
    # ...) so the same source-system field name can map differently for
    # each. Older local databases predate this column — recreate rather than
    # migrate, since this is disposable local demo data (see poc/README.md).
    for table in _KNOWN_TABLES:
        exists = conn.execute(
            "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", (table,)
        ).fetchone()
        if exists and not _has_column(conn, table, "target_db"):
            conn.execute(f"DROP TABLE {table}")  # table is one of _KNOWN_TABLES, see above

    conn.execute(
        """CREATE TABLE IF NOT EXISTS mappings (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            target_db TEXT NOT NULL,
            source_system TEXT NOT NULL,
            source_system_norm TEXT NOT NULL,
            field_name TEXT NOT NULL,
            field_name_norm TEXT NOT NULL,
            target_table TEXT NOT NULL,
            target_field TEXT NOT NULL,
            confirm_count INTEGER NOT NULL DEFAULT 1,
            last_confirmed_at TEXT NOT NULL,
            desc TEXT NOT NULL DEFAULT '',
            UNIQUE(target_db, source_system_norm, field_name_norm)
        )"""
    )
    conn.execute(
        """CREATE TABLE IF NOT EXISTS field_index (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            target_db TEXT NOT NULL,
            field_name_norm TEXT NOT NULL,
            target_table TEXT NOT NULL,
            target_field TEXT NOT NULL,
            count INTEGER NOT NULL DEFAULT 1,
            UNIQUE(target_db, field_name_norm, target_table, target_field)
        )"""
    )
    # A confirmation not yet written to the shared mapping log (see
    # shared_mappings.py's flush_pending) -- queued here instead of writing
    # to the shared file immediately, so a full read-modify-write of that
    # file happens once per batch (a background flush, every few minutes or
    # every few confirmations) rather than once per click. sync_id is this
    # row's identity in BOTH places -- generated here, carried into the
    # shared file's own SyncID column -- so a retried flush can tell "did
    # this exact row already make it in" apart from "is this a new row",
    # and never double-appends on retry. Survives a crash between
    # confirmations (unlike an in-memory queue would) since it's just
    # another table in the same local mappings.db this process already
    # treats as durable.
    conn.execute(
        """CREATE TABLE IF NOT EXISTS pending_sync (
            sync_id TEXT PRIMARY KEY,
            kind TEXT NOT NULL,
            target_db TEXT NOT NULL,
            source_system TEXT NOT NULL,
            field_name TEXT NOT NULL,
            target_table TEXT NOT NULL,
            target_field TEXT NOT NULL,
            desc TEXT NOT NULL DEFAULT '',
            value_map TEXT NOT NULL DEFAULT '',
            confirmed_at TEXT NOT NULL,
            confirmed_by TEXT NOT NULL,
            queued_at TEXT NOT NULL
        )"""
    )
    # Unlike the target_db migration above, this one runs ALTER TABLE instead
    # of drop-and-recreate: real confirmed mappings from actual tool usage
    # exist in local databases now, and losing that history just to add a
    # column isn't worth it the way it was when this table was still empty.
    if not _has_column(conn, "mappings", "desc"):
        conn.execute("ALTER TABLE mappings ADD COLUMN desc TEXT NOT NULL DEFAULT ''")
    # Same non-destructive ALTER pattern as desc above, for the same reason:
    # real confirmed mappings exist now, so dropping the table to add a
    # column isn't an option. Holds the customer's confirmed source-value ->
    # target-code mapping from the Advanced-mode value-matching step (e.g.
    # "M=1,F=2,U=3"), parsed with schema_rules.parse_value_list -- same
    # "code=label" mini-language used everywhere else in this codebase.
    if not _has_column(conn, "mappings", "value_map"):
        conn.execute("ALTER TABLE mappings ADD COLUMN value_map TEXT NOT NULL DEFAULT ''")
    conn.commit()
    return conn


def get_mapping(source_system, field_name, target_db=DEFAULT_TARGET_DATABASE):
    conn = get_conn()
    try:
        row = conn.execute(
            "SELECT * FROM mappings WHERE target_db=? AND source_system_norm=? AND field_name_norm=?",
            (target_db, normalize(source_system), normalize(field_name)),
        ).fetchone()
        return dict(row) if row else None
    finally:
        conn.close()


def get_field_index(field_name, target_db=DEFAULT_TARGET_DATABASE):
    conn = get_conn()
    try:
        rows = conn.execute(
            """SELECT target_table, target_field, count FROM field_index
               WHERE target_db=? AND field_name_norm=? ORDER BY count DESC""",
            (target_db, normalize(field_name)),
        ).fetchall()
        return [dict(r) for r in rows]
    finally:
        conn.close()


def get_decode_patterns(target_table, target_field, target_db=DEFAULT_TARGET_DATABASE):
    """Descriptions other confirmed mappings (any source system) have used for
    this exact target field, most-common first -- the "established patterns"
    signal for transform_draft.py. Only ever field-name/format text a
    consultant typed in, never anything from a source system's real data."""
    conn = get_conn()
    try:
        rows = conn.execute(
            """SELECT desc, COUNT(*) c FROM mappings
               WHERE target_db=? AND target_table=? AND target_field=? AND desc != ''
               GROUP BY desc ORDER BY c DESC""",
            (target_db, target_table, target_field),
        ).fetchall()
        return [{"desc": r["desc"], "count": r["c"]} for r in rows]
    finally:
        conn.close()


def save_mapping(source_system, field_name, target_table, target_field, target_db=DEFAULT_TARGET_DATABASE, desc=""):
    conn = get_conn()
    try:
        now = datetime.datetime.now(datetime.timezone.utc).isoformat()
        desc = desc or ""
        ss_norm, fn_norm = normalize(source_system), normalize(field_name)
        existing = conn.execute(
            "SELECT * FROM mappings WHERE target_db=? AND source_system_norm=? AND field_name_norm=?",
            (target_db, ss_norm, fn_norm),
        ).fetchone()
        if existing and existing["target_table"] == target_table and existing["target_field"] == target_field:
            conn.execute(
                "UPDATE mappings SET confirm_count = confirm_count + 1, last_confirmed_at=?, desc=? WHERE id=?",
                (now, desc, existing["id"]),
            )
        elif existing:
            conn.execute(
                """UPDATE mappings SET target_table=?, target_field=?, confirm_count=1,
                   last_confirmed_at=?, source_system=?, field_name=?, desc=? WHERE id=?""",
                (target_table, target_field, now, source_system, field_name, desc, existing["id"]),
            )
        else:
            conn.execute(
                """INSERT INTO mappings
                   (target_db, source_system, source_system_norm, field_name, field_name_norm,
                    target_table, target_field, confirm_count, last_confirmed_at, desc)
                   VALUES (?,?,?,?,?,?,?,1,?,?)""",
                (target_db, source_system, ss_norm, field_name, fn_norm, target_table, target_field, now, desc),
            )

        idx_row = conn.execute(
            "SELECT * FROM field_index WHERE target_db=? AND field_name_norm=? AND target_table=? AND target_field=?",
            (target_db, fn_norm, target_table, target_field),
        ).fetchone()
        if idx_row:
            conn.execute("UPDATE field_index SET count = count + 1 WHERE id=?", (idx_row["id"],))
        else:
            conn.execute(
                """INSERT INTO field_index (target_db, field_name_norm, target_table, target_field, count)
                   VALUES (?,?,?,?,1)""",
                (target_db, fn_norm, target_table, target_field),
            )
        conn.commit()
    finally:
        conn.close()


def save_value_map(source_system, field_name, target_db, value_map):
    """Records the customer's *confirmed* source-value -> target-code mapping
    from the Advanced-mode value-matching step, separately from save_mapping
    above -- this is a distinct confirmation (which value goes to which
    approved code), not a re-confirmation of the target field itself, so it
    doesn't touch confirm_count or overwrite desc. Requires a mappings row to
    already exist for this (target_db, source_system, field_name); the caller
    (app.py) is responsible for creating one first if it's missing."""
    conn = get_conn()
    try:
        conn.execute(
            "UPDATE mappings SET value_map=? WHERE target_db=? AND source_system_norm=? AND field_name_norm=?",
            (value_map, target_db, normalize(source_system), normalize(field_name)),
        )
        conn.commit()
    finally:
        conn.close()


def queue_pending_sync(kind, target_db, source_system, field_name, target_table, target_field, desc="", value_map=""):
    """Queues one confirmation for the next shared-log flush, instead of
    app.py writing to the shared file immediately -- see this module's own
    pending_sync table comment for why. kind is "mapping" or "value_map",
    mirroring shared_mappings.py's append()/append_value_map() distinction.
    Returns the generated sync_id (not currently used by callers, but handy
    for tests/debugging)."""
    conn = get_conn()
    try:
        sync_id = str(uuid.uuid4())
        now = datetime.datetime.now(datetime.timezone.utc).isoformat()
        conn.execute(
            """INSERT INTO pending_sync
               (sync_id, kind, target_db, source_system, field_name, target_table, target_field,
                desc, value_map, confirmed_at, confirmed_by, queued_at)
               VALUES (?,?,?,?,?,?,?,?,?,?,?,?)""",
            (sync_id, kind, target_db, source_system, field_name, target_table, target_field,
             desc or "", value_map or "", now, getpass.getuser(), now),
        )
        conn.commit()
        return sync_id
    finally:
        conn.close()


def get_pending_sync():
    """Every confirmation not yet confirmed-flushed to the shared log,
    oldest first -- what a flush attempt should try to write."""
    conn = get_conn()
    try:
        rows = conn.execute("SELECT * FROM pending_sync ORDER BY queued_at ASC").fetchall()
        return [dict(r) for r in rows]
    finally:
        conn.close()


def count_pending_sync():
    """Cheap count for the "flush when N have piled up" trigger, without
    pulling every row's full content just to measure how many there are."""
    conn = get_conn()
    try:
        return conn.execute("SELECT COUNT(*) c FROM pending_sync").fetchone()["c"]
    finally:
        conn.close()


def clear_pending_sync(sync_ids):
    """Removes rows a flush has *verified* actually landed in the shared
    file -- never called speculatively just because a write was attempted;
    see shared_mappings.py's flush_pending. A row not in sync_ids stays
    queued for the next attempt."""
    if not sync_ids:
        return
    conn = get_conn()
    try:
        conn.executemany("DELETE FROM pending_sync WHERE sync_id=?", [(sid,) for sid in sync_ids])
        conn.commit()
    finally:
        conn.close()


def get_stats(target_db=DEFAULT_TARGET_DATABASE):
    conn = get_conn()
    try:
        total = conn.execute("SELECT COUNT(*) c FROM mappings WHERE target_db=?", (target_db,)).fetchone()["c"]
        systems = conn.execute(
            "SELECT COUNT(DISTINCT source_system_norm) c FROM mappings WHERE target_db=?", (target_db,)
        ).fetchone()["c"]
        return {"total": total, "systems": systems}
    finally:
        conn.close()
