"""
Convert CaseWorthy's full database primary/foreign key export
(reference/CW_Foreign_Keys.csv, reference/CW_Primary_Keys.csv -- provided
directly by Michael, 2026-08-13, as the authoritative source after an
earlier attempt to *infer* relationships from a Form export's own Query
Rule operand codes was deliberately not built without that confirmation)
into reference/cw_foreign_keys.json and reference/cw_primary_keys.json,
lookup registries create_template.py resolves every field's (table, column)
against to answer "does this ID link to another sheet."

Run:
    python tools/build_cw_foreign_keys.py

Source format (no header row):
    Foreign keys: SchemaName,TableName,ColumnName,ConstraintName,
                  ReferencedSchemaName,ReferencedTableName,ReferencedColumnName
    Primary keys: SchemaName,TableName,ColumnName,ConstraintName

This is a full CaseWorthy database dump (thousands of tables across many
schemas -- batchbuilder, cars, commhub, dbo, etc.), not scoped to the ~28
ETL-relevant tables. Kept in full rather than pre-filtered: a customer's
custom form can reference any of them, and filtering here would just move
the "is this table relevant" guess from create_template.py (where it's
made per-lookup, safely) to this one-time conversion (where filtering
wrong would silently drop a real fact).

Registry keys are "table.column", lowercased -- schema is not part of the
key. Checked across this real export: no (table, column) pair appears
under two different schemas with two different targets, so schema-less
keying doesn't lose information for this dataset; see report_collisions
below, which would flag it if a future re-export changed that.

Pure standard library, consistent with the rest of this repo.
"""

import csv
import json
import os

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FK_SOURCE_CSV = os.path.join(REPO_ROOT, "reference", "CW_Foreign_Keys.csv")
PK_SOURCE_CSV = os.path.join(REPO_ROOT, "reference", "CW_Primary_Keys.csv")
FK_OUT_JSON = os.path.join(REPO_ROOT, "reference", "cw_foreign_keys.json")
PK_OUT_JSON = os.path.join(REPO_ROOT, "reference", "cw_primary_keys.json")


def _read_csv(path):
    with open(path, encoding="utf-8-sig", newline="") as f:
        return [row for row in csv.reader(f) if row and row[0].strip()]


def build_foreign_keys():
    """(table.column, lowercased) -> {table, column, schema, referencedTable,
    referencedColumn, referencedSchema} -- original casing preserved in the
    values for display; collisions (same table.column key, different
    target) are reported, last-one-wins in the registry, matching the "never
    silently drop a disagreement" pattern used elsewhere in this repo."""
    registry = {}
    collisions = []
    for row in _read_csv(FK_SOURCE_CSV):
        if len(row) < 7:
            continue
        schema, table, column, _constraint, ref_schema, ref_table, ref_column = row[:7]
        key = f"{table.strip().lower()}.{column.strip().lower()}"
        entry = {
            "schema": schema.strip(),
            "table": table.strip(),
            "column": column.strip(),
            "referencedSchema": ref_schema.strip(),
            "referencedTable": ref_table.strip(),
            "referencedColumn": ref_column.strip(),
        }
        if key in registry and (
            registry[key]["referencedTable"] != entry["referencedTable"]
            or registry[key]["referencedColumn"] != entry["referencedColumn"]
        ):
            collisions.append((key, registry[key], entry))
        registry[key] = entry
    return registry, collisions


def build_primary_keys():
    """(table.column, lowercased) -> {table, column, schema} -- a column
    that is its own table's primary key, e.g. Client.EntityID. Secondary to
    the foreign-key registry above; not yet consumed by create_template.py,
    kept alongside it since Michael provided both together."""
    registry = {}
    for row in _read_csv(PK_SOURCE_CSV):
        if len(row) < 3:
            continue
        schema, table, column = row[0].strip(), row[1].strip(), row[2].strip()
        key = f"{table.lower()}.{column.lower()}"
        registry[key] = {"schema": schema, "table": table, "column": column}
    return registry


def main():
    fk_registry, collisions = build_foreign_keys()
    with open(FK_OUT_JSON, "w", encoding="utf-8") as f:
        json.dump(fk_registry, f, indent=2, sort_keys=True)
        f.write("\n")
    print(f"Wrote {FK_OUT_JSON}: {len(fk_registry)} foreign keys.")
    if collisions:
        print(f"  {len(collisions)} (table.column) key(s) had disagreeing targets across schemas "
              f"(last one wins in the registry) -- review before trusting these:")
        for key, first, second in collisions:
            print(f"    {key}: {first['referencedTable']}.{first['referencedColumn']} "
                  f"vs {second['referencedTable']}.{second['referencedColumn']}")

    pk_registry = build_primary_keys()
    with open(PK_OUT_JSON, "w", encoding="utf-8") as f:
        json.dump(pk_registry, f, indent=2, sort_keys=True)
        f.write("\n")
    print(f"Wrote {PK_OUT_JSON}: {len(pk_registry)} primary keys.")


if __name__ == "__main__":
    main()
