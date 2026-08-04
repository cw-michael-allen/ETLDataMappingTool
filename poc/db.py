import datetime
import os
import re
import sqlite3

DB_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data", "mappings.db")


def normalize(s):
    return re.sub(r"[^a-z0-9]", "", (s or "").strip().lower())


def get_conn():
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute(
        """CREATE TABLE IF NOT EXISTS mappings (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            source_system TEXT NOT NULL,
            source_system_norm TEXT NOT NULL,
            field_name TEXT NOT NULL,
            field_name_norm TEXT NOT NULL,
            target_table TEXT NOT NULL,
            target_field TEXT NOT NULL,
            confirm_count INTEGER NOT NULL DEFAULT 1,
            last_confirmed_at TEXT NOT NULL,
            UNIQUE(source_system_norm, field_name_norm)
        )"""
    )
    conn.execute(
        """CREATE TABLE IF NOT EXISTS field_index (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            field_name_norm TEXT NOT NULL,
            target_table TEXT NOT NULL,
            target_field TEXT NOT NULL,
            count INTEGER NOT NULL DEFAULT 1,
            UNIQUE(field_name_norm, target_table, target_field)
        )"""
    )
    conn.commit()
    return conn


def get_mapping(source_system, field_name):
    conn = get_conn()
    try:
        row = conn.execute(
            "SELECT * FROM mappings WHERE source_system_norm=? AND field_name_norm=?",
            (normalize(source_system), normalize(field_name)),
        ).fetchone()
        return dict(row) if row else None
    finally:
        conn.close()


def get_field_index(field_name):
    conn = get_conn()
    try:
        rows = conn.execute(
            "SELECT target_table, target_field, count FROM field_index WHERE field_name_norm=? ORDER BY count DESC",
            (normalize(field_name),),
        ).fetchall()
        return [dict(r) for r in rows]
    finally:
        conn.close()


def save_mapping(source_system, field_name, target_table, target_field):
    conn = get_conn()
    try:
        now = datetime.datetime.utcnow().isoformat()
        ss_norm, fn_norm = normalize(source_system), normalize(field_name)
        existing = conn.execute(
            "SELECT * FROM mappings WHERE source_system_norm=? AND field_name_norm=?",
            (ss_norm, fn_norm),
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
                   (source_system, source_system_norm, field_name, field_name_norm,
                    target_table, target_field, confirm_count, last_confirmed_at)
                   VALUES (?,?,?,?,?,?,1,?)""",
                (source_system, ss_norm, field_name, fn_norm, target_table, target_field, now),
            )

        idx_row = conn.execute(
            "SELECT * FROM field_index WHERE field_name_norm=? AND target_table=? AND target_field=?",
            (fn_norm, target_table, target_field),
        ).fetchone()
        if idx_row:
            conn.execute("UPDATE field_index SET count = count + 1 WHERE id=?", (idx_row["id"],))
        else:
            conn.execute(
                "INSERT INTO field_index (field_name_norm, target_table, target_field, count) VALUES (?,?,?,1)",
                (fn_norm, target_table, target_field),
            )
        conn.commit()
    finally:
        conn.close()


def get_stats():
    conn = get_conn()
    try:
        total = conn.execute("SELECT COUNT(*) c FROM mappings").fetchone()["c"]
        systems = conn.execute("SELECT COUNT(DISTINCT source_system_norm) c FROM mappings").fetchone()["c"]
        return {"total": total, "systems": systems}
    finally:
        conn.close()
