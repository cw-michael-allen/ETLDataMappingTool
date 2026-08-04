import datetime
import os
import re
import sqlite3

DB_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data", "mappings.db")

DEFAULT_TARGET_DATABASE = "CaseWorthy"


def normalize(s):
    return re.sub(r"[^a-z0-9]", "", (s or "").strip().lower())


def _has_column(conn, table, column):
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
    for table in ("mappings", "field_index"):
        exists = conn.execute(
            "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", (table,)
        ).fetchone()
        if exists and not _has_column(conn, table, "target_db"):
            conn.execute(f"DROP TABLE {table}")

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


def save_mapping(source_system, field_name, target_table, target_field, target_db=DEFAULT_TARGET_DATABASE):
    conn = get_conn()
    try:
        now = datetime.datetime.now(datetime.timezone.utc).isoformat()
        ss_norm, fn_norm = normalize(source_system), normalize(field_name)
        existing = conn.execute(
            "SELECT * FROM mappings WHERE target_db=? AND source_system_norm=? AND field_name_norm=?",
            (target_db, ss_norm, fn_norm),
        ).fetchone()
        if existing and existing["target_table"] == target_table and existing["target_field"] == target_field:
            conn.execute(
                "UPDATE mappings SET confirm_count = confirm_count + 1, last_confirmed_at=? WHERE id=?",
                (now, existing["id"]),
            )
        elif existing:
            conn.execute(
                """UPDATE mappings SET target_table=?, target_field=?, confirm_count=1,
                   last_confirmed_at=?, source_system=?, field_name=? WHERE id=?""",
                (target_table, target_field, now, source_system, field_name, existing["id"]),
            )
        else:
            conn.execute(
                """INSERT INTO mappings
                   (target_db, source_system, source_system_norm, field_name, field_name_norm,
                    target_table, target_field, confirm_count, last_confirmed_at)
                   VALUES (?,?,?,?,?,?,?,1,?)""",
                (target_db, source_system, ss_norm, field_name, fn_norm, target_table, target_field, now),
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
