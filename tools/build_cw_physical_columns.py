"""
Convert a full CaseWorthy database column export (every schema, table, and
column -- SQL type, length/precision/scale, nullability, identity, default;
essentially an INFORMATION_SCHEMA.COLUMNS dump) into
reference/cw_physical_columns.json, a lookup registry create_template.py
resolves a Form export's own (table, column) against as its last-resort
DataType fallback.

Run:
    python tools/build_cw_physical_columns.py [--source PATH]

--source defaults to the path Michael provided directly (2026-08-12), a raw
CSV export with no header row. Unlike reference/CW_Foreign_Keys.csv and
friends, the raw source CSV here is deliberately NOT committed to this repo
(Michael's call, 2026-08-12) -- it's large (23k+ rows) and mostly covers
schemas with no ETL relevance (batchbuilder, cars, commhub, commlink,
claimsexchange, DW, import, powerbi, rpt, sync, temp, test), so only this
script's derived JSON is checked in. Re-running this script requires a fresh
export at the same path (or pass --source to point at wherever it lives).

Source format (no header row, 10 columns):
    SchemaName,TableName,ColumnName,DataType,CharacterMaxLength,
    NumericPrecision,NumericScale,IsNullable,IsIdentity,ColumnDefault

CharacterMaxLength of -1 is SQL Server's own convention for
nvarchar(max)/varchar(max)/varbinary(max) -- preserved as -1 in the JSON
rather than translated, matching create_template.py's own
_character_max_length, which already knows this convention (n < 0 -> "MAX").

Every schema in the source is kept, not just dbo (Michael's call,
2026-08-12) -- same reasoning as build_cw_foreign_keys.py's own "don't
pre-filter, a customer's custom form/table could reference any schema"
rule. create_template.py's own lookup is what scopes to dbo when that's the
relevant schema for a Form export's own physical table names, not this
conversion step.

Registry keys are "table.column", lowercased -- schema is not part of the
key, same convention as cw_foreign_keys.json/cw_primary_keys.json. Checked
across this real export: a handful of (table, column) pairs repeat across
schemas (e.g. a table name reused in both dbo and an internal schema) --
collisions are reported, last-one-wins, same pattern as
build_cw_foreign_keys.py's own report_collisions.

Pure standard library, consistent with the rest of this repo.
"""

import argparse
import csv
import json
import os
import sys

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_SOURCE_CSV = r"C:\Users\MichaelAllen\Desktop\All baseline table and column info CW.csv"
OUT_JSON = os.path.join(REPO_ROOT, "reference", "cw_physical_columns.json")


def _read_csv(path):
    with open(path, encoding="utf-8-sig", newline="") as f:
        return [row for row in csv.reader(f) if row and row[0].strip()]


def _int_or_none(s):
    s = (s or "").strip()
    if not s or s.upper() == "NULL":
        return None
    return int(s)


def _bool01(s):
    return (s or "").strip() == "1"


def build_physical_columns(source_path):
    """(table.column, lowercased) -> {schema, table, column, dataType,
    characterMaxLength, numericPrecision, numericScale, isNullable,
    isIdentity, columnDefault}. Collisions (same table.column key, different
    schema, disagreeing type) are reported, last-one-wins, matching
    build_cw_foreign_keys.py's own convention."""
    registry = {}
    collisions = []
    skipped = 0
    for row in _read_csv(source_path):
        if len(row) < 10:
            skipped += 1
            continue
        schema, table, column, data_type = (c.strip() for c in row[:4])
        char_max_length = _int_or_none(row[4])
        numeric_precision = _int_or_none(row[5])
        numeric_scale = _int_or_none(row[6])
        is_nullable = _bool01(row[7])
        is_identity = _bool01(row[8])
        column_default = row[9].strip() or None
        if column_default and column_default.upper() == "NULL":
            column_default = None

        key = f"{table.lower()}.{column.lower()}"
        entry = {
            "schema": schema,
            "table": table,
            "column": column,
            "dataType": data_type,
            "characterMaxLength": char_max_length,
            "numericPrecision": numeric_precision,
            "numericScale": numeric_scale,
            "isNullable": is_nullable,
            "isIdentity": is_identity,
            "columnDefault": column_default,
        }
        if key in registry and (
            registry[key]["dataType"] != entry["dataType"]
            or registry[key]["schema"] != entry["schema"]
        ):
            collisions.append((key, registry[key], entry))
        registry[key] = entry
    return registry, collisions, skipped


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    ap.add_argument("--source", default=DEFAULT_SOURCE_CSV)
    ap.add_argument("--out", default=OUT_JSON)
    args = ap.parse_args()

    if not os.path.exists(args.source):
        sys.exit(f"Source not found: {args.source}")

    registry, collisions, skipped = build_physical_columns(args.source)
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(registry, f, indent=2, sort_keys=True)
        f.write("\n")

    schemas = sorted({e["schema"] for e in registry.values()})
    print(f"Wrote {args.out}: {len(registry)} columns across {len(schemas)} schemas ({', '.join(schemas)}).")
    if skipped:
        print(f"  {skipped} malformed row(s) skipped (expected 10 columns).")
    if collisions:
        print(f"  {len(collisions)} (table.column) key(s) had disagreeing schema/type across schemas "
              f"(last one wins in the registry):")
        for key, first, second in collisions:
            print(f"    {key}: {first['schema']}.{first['dataType']} vs {second['schema']}.{second['dataType']}")


if __name__ == "__main__":
    main()
