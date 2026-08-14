"""
Convert CaseWorthy's consolidated baseline schema+key export (one row per
column, database-wide, with PK/FK flags already attached -- provided
directly by Michael, 2026-08-14) into the three registries
create_template.py resolves every FormElement's (table, column) against:
reference/cw_physical_columns.json, reference/cw_foreign_keys.json, and
reference/cw_primary_keys.json.

Run:
    python tools/build_cw_baseline_schema.py [--source PATH]

Replaces tools/build_cw_physical_columns.py and tools/build_cw_foreign_keys.py
(now removed, along with the reference/CW_Foreign_Keys.csv and
reference/CW_Primary_Keys.csv exports they read) -- this one export is a
superset of what those three older exports covered separately (more FK rows,
more PK rows, same physical-column coverage), so keeping the old pipeline
alongside this one would just be two divergent sources of the same facts.
This is also the fresh export that resolved the open FamilyMember /
EntityContactPreference "*ID column -- real FK or not" question: e.g. this
export shows FamilyMember.OrgGroupID/WriteOrgGroupID/DeletedBy and
EntityContactPreference.DeletedBy/LastModifiedBy/CreatedFormID/
LastModifiedFormID have no FKTable/FKColumn (not real constraints in the
live DB), while FamilyMember.FamilyID -> Family.FamilyID and
EntityContactPreference.CreatedBy -> Users.EntityID etc. are -- read
straight off the export, never inferred from column naming.

--source defaults to the path Michael provided directly (2026-08-14). Not
committed to this repo (same reasoning as the old physical-columns source
it replaces): it's a full database-wide dump (~25k rows across schemas with
no ETL relevance -- batchbuilder, cars, commhub, commlink, claimsexchange,
DW, import, powerbi, rpt, sync, temp, test -- alongside dbo), so only this
script's derived JSON is checked in. Re-running this script requires a
fresh export at the same path (or pass --source to point at wherever it
lives).

Source format (header row, 13 columns):
    SchemaName,TableName,ColumnName,DataType,MaxLength,Precision,Scale,
    IsNullable,IsIdentity,DefaultValue,IsPK,FKTable,FKColumn

MaxLength of -1 is SQL Server's own convention for nvarchar(MAX)/
varchar(MAX)/varbinary(MAX) -- preserved as -1 in the JSON rather than
translated, matching create_template.py's own _character_max_length, which
already knows this convention (n < 0 -> "MAX"). Every schema in the source
is kept, not just dbo (same reasoning as the scripts this replaces: a
customer's custom form/table could reference any schema, and pre-filtering
here would just move that guess somewhere it can silently drop a real fact).

FKTable/FKColumn carry no schema of their own -- referencedSchema is
resolved by looking up which schema(s) that table name appears under
elsewhere in this same export (preferring the FK row's own schema when the
table exists there, since same-schema FKs are the overwhelming majority;
falling back to the table's only other schema if it's unambiguous, else
left blank rather than guessed).

Registry keys are "table.column", lowercased -- schema is not part of the
key, same convention as the registries this replaces. Collisions (same key,
disagreeing target/type across schemas) are reported, last-one-wins,
matching the prior scripts' own pattern.

Pure standard library, consistent with the rest of this repo.
"""

import argparse
import csv
import json
import os
import sys

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_SOURCE_CSV = r"C:\Users\MichaelAllen\Downloads\baseline-schema-fk.csv"
PHYSICAL_COLUMNS_OUT = os.path.join(REPO_ROOT, "reference", "cw_physical_columns.json")
FOREIGN_KEYS_OUT = os.path.join(REPO_ROOT, "reference", "cw_foreign_keys.json")
PRIMARY_KEYS_OUT = os.path.join(REPO_ROOT, "reference", "cw_primary_keys.json")

REQUIRED_COLUMNS = [
    "SchemaName", "TableName", "ColumnName", "DataType", "MaxLength",
    "Precision", "Scale", "IsNullable", "IsIdentity", "DefaultValue",
    "IsPK", "FKTable", "FKColumn",
]


def _read_rows(path):
    with open(path, encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)
        missing = [c for c in REQUIRED_COLUMNS if c not in (reader.fieldnames or [])]
        if missing:
            sys.exit(f"{path}: missing expected column(s) {missing} -- header was {reader.fieldnames}")
        return list(reader)


def _int_or_none(s):
    s = (s or "").strip()
    if not s:
        return None
    return int(float(s))  # source stores e.g. "256.0", "-1.0"


def _bool01(s):
    return (s or "").strip() == "1"


def build_physical_columns(rows):
    registry = {}
    collisions = []
    for row in rows:
        schema = row["SchemaName"].strip()
        table = row["TableName"].strip()
        column = row["ColumnName"].strip()
        if not table or not column:
            continue
        column_default = (row["DefaultValue"] or "").strip() or None
        entry = {
            "schema": schema,
            "table": table,
            "column": column,
            "dataType": row["DataType"].strip(),
            "characterMaxLength": _int_or_none(row["MaxLength"]),
            "numericPrecision": _int_or_none(row["Precision"]),
            "numericScale": _int_or_none(row["Scale"]),
            "isNullable": _bool01(row["IsNullable"]),
            "isIdentity": _bool01(row["IsIdentity"]),
            "columnDefault": column_default,
        }
        key = f"{table.lower()}.{column.lower()}"
        if key in registry and (
            registry[key]["dataType"] != entry["dataType"]
            or registry[key]["schema"] != entry["schema"]
        ):
            collisions.append((key, registry[key], entry))
        registry[key] = entry
    return registry, collisions


def _table_schema_index(rows):
    """table.lower() -> set of schemas that table appears under in this export."""
    index = {}
    for row in rows:
        table = row["TableName"].strip()
        schema = row["SchemaName"].strip()
        if table:
            index.setdefault(table.lower(), set()).add(schema)
    return index


def build_foreign_keys(rows, table_schemas):
    registry = {}
    collisions = []
    for row in rows:
        fk_table = (row["FKTable"] or "").strip()
        fk_column = (row["FKColumn"] or "").strip()
        if not fk_table or not fk_column:
            continue
        schema = row["SchemaName"].strip()
        table = row["TableName"].strip()
        column = row["ColumnName"].strip()

        candidates = table_schemas.get(fk_table.lower(), set())
        if schema in candidates:
            ref_schema = schema
        elif len(candidates) == 1:
            ref_schema = next(iter(candidates))
        else:
            ref_schema = ""

        entry = {
            "schema": schema,
            "table": table,
            "column": column,
            "referencedSchema": ref_schema,
            "referencedTable": fk_table,
            "referencedColumn": fk_column,
        }
        key = f"{table.lower()}.{column.lower()}"
        if key in registry and (
            registry[key]["referencedTable"] != entry["referencedTable"]
            or registry[key]["referencedColumn"] != entry["referencedColumn"]
        ):
            collisions.append((key, registry[key], entry))
        registry[key] = entry
    return registry, collisions


def build_primary_keys(rows):
    registry = {}
    for row in rows:
        if not _bool01(row["IsPK"]):
            continue
        schema = row["SchemaName"].strip()
        table = row["TableName"].strip()
        column = row["ColumnName"].strip()
        key = f"{table.lower()}.{column.lower()}"
        registry[key] = {"schema": schema, "table": table, "column": column}
    return registry


def _write_json(path, registry):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(registry, f, indent=2, sort_keys=True)
        f.write("\n")


def _report_collisions(label, collisions, describe):
    if not collisions:
        return
    print(f"  {len(collisions)} (table.column) key(s) had disagreeing {label} across schemas "
          f"(last one wins in the registry) -- review before trusting these:")
    for key, first, second in collisions:
        print(f"    {key}: {describe(first)} vs {describe(second)}")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    ap.add_argument("--source", default=DEFAULT_SOURCE_CSV)
    args = ap.parse_args()

    if not os.path.exists(args.source):
        sys.exit(f"Source not found: {args.source}")

    rows = _read_rows(args.source)

    physical_registry, physical_collisions = build_physical_columns(rows)
    _write_json(PHYSICAL_COLUMNS_OUT, physical_registry)
    schemas = sorted({e["schema"] for e in physical_registry.values()})
    print(f"Wrote {PHYSICAL_COLUMNS_OUT}: {len(physical_registry)} columns across {len(schemas)} schemas ({', '.join(schemas)}).")
    _report_collisions("schema/type", physical_collisions, lambda e: f"{e['schema']}.{e['dataType']}")

    table_schemas = _table_schema_index(rows)
    fk_registry, fk_collisions = build_foreign_keys(rows, table_schemas)
    _write_json(FOREIGN_KEYS_OUT, fk_registry)
    print(f"Wrote {FOREIGN_KEYS_OUT}: {len(fk_registry)} foreign keys.")
    _report_collisions("targets", fk_collisions, lambda e: f"{e['referencedTable']}.{e['referencedColumn']}")

    pk_registry = build_primary_keys(rows)
    _write_json(PRIMARY_KEYS_OUT, pk_registry)
    print(f"Wrote {PRIMARY_KEYS_OUT}: {len(pk_registry)} primary keys.")


if __name__ == "__main__":
    main()
