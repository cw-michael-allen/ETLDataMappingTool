"""
Advanced-mode SQL export: turns confirmed mappings (source table + source
field -> target table.field) into a SELECT statement per target table that a
technical data person can run against the customer's live source database.

Scope, deliberately (see docs/PHASE_PLAN.md and chat record for why):
- One source table per target table, no JOINs. If a target table's mapped
  fields name more than one distinct source table, that's reported as a
  conflict instead of guessing at a join.
- No automatic value-transformation logic (e.g. guessing that source "Y"/"N"
  means target 1/2) — this tool never fabricates rules about the customer's
  actual data. Required/decode constraints are surfaced as SQL comments for
  the data person to handle, not as generated CASE WHEN logic.
- Column aliases match the target field name exactly, so the result set can
  be dropped directly into that target table's staging data.
"""

from collections import defaultdict

DIALECTS = {
    "SQL Server": {"quote": lambda ident: f"[{ident}]"},
    "MySQL": {"quote": lambda ident: f"`{ident}`"},
    "PostgreSQL": {"quote": lambda ident: f'"{ident}"'},
    "Oracle": {"quote": lambda ident: f'"{ident}"'},
}

DEFAULT_DIALECT = "SQL Server"


def _quote_qualified(dialect, name):
    """'dbo.ClientExport' -> quote each dot-separated part separately,
    so a schema-qualified source table name doesn't get quoted as one
    (invalid) identifier."""
    quote = DIALECTS[dialect]["quote"]
    return ".".join(quote(part) for part in name.split(".") if part)


def build_export(mappings, schema, dialect=DEFAULT_DIALECT):
    """
    mappings: list of {"sourceTable":str, "sourceField":str, "desc":str,
                        "table":str|None, "field":str|None}
    Only entries with a non-empty sourceTable AND a confirmed target
    table/field are usable; others are reported as skipped.

    Returns {"statements": [{"targetTable", "sourceTable", "sql"}],
             "conflicts": [{"targetTable", "sourceTables": [...]}],
             "skipped": [{"sourceField", "reason"}]}
    """
    if dialect not in DIALECTS:
        dialect = DEFAULT_DIALECT

    by_table_field = {(f["table"], f["field"]): f for f in schema}

    usable = defaultdict(list)  # target table -> [mapping,...]
    skipped = []
    for m in mappings:
        if not (m.get("table") and m.get("field")):
            skipped.append({"sourceField": m.get("sourceField", ""), "reason": "not mapped to a target field"})
            continue
        if not (m.get("sourceTable") or "").strip():
            skipped.append({"sourceField": m.get("sourceField", ""), "reason": "no source table specified"})
            continue
        usable[m["table"]].append(m)

    statements = []
    conflicts = []
    for target_table, entries in usable.items():
        source_tables = sorted({e["sourceTable"].strip() for e in entries})
        if len(source_tables) > 1:
            conflicts.append({"targetTable": target_table, "sourceTables": source_tables})
            continue

        source_table = source_tables[0]
        lines = [f"-- Target table: {target_table}  (source: {source_table})"]
        select_parts = []
        for e in entries:
            meta = by_table_field.get((target_table, e["field"]))
            if meta:
                notes = []
                if meta.get("required"):
                    notes.append("required")
                if meta.get("decode"):
                    notes.append(f"expects: {meta['decode']}")
                elif meta.get("type"):
                    notes.append(meta["type"])
                if notes:
                    lines.append(f"--   {target_table}.{e['field']}: {'; '.join(notes)} — verify source values match.")
            select_parts.append(
                f"    {_quote_qualified(dialect, e['sourceField'])} AS {DIALECTS[dialect]['quote'](e['field'])}"
            )

        lines.append("SELECT")
        lines.append(",\n".join(select_parts))
        lines.append(f"FROM {_quote_qualified(dialect, source_table)};")

        statements.append({"targetTable": target_table, "sourceTable": source_table, "sql": "\n".join(lines)})

    statements.sort(key=lambda s: s["targetTable"])
    conflicts.sort(key=lambda c: c["targetTable"])
    return {"statements": statements, "conflicts": conflicts, "skipped": skipped}
