"""
Convert CaseWorthy's ListItem table export (reference/CW_List_Values_and_Descriptions.csv)
into reference/cw_list_values.json, a listId -> {name, values:[[code,label],...]}
registry that schema_rules.py resolves every CaseWorthy List-type field's
`listId` against at load time.

Run:
    python tools/build_cw_list_values.py

Why this exists: CaseWorthy's validation script (00_Staging_EXCEL_Validation_Script_v3.sql)
validates List fields against a database table ("SELECT ListValue FROM ListItem
WHERE ListID = N") and never spells out the actual codes/labels in script text,
so nothing could be extracted from it -- see reference/target_schema_full.json's
pre-existing List fields with a `listId` but no `decode`/`decodeValues`. This
CSV is a direct export of that ListItem table (approved 2026-08-11), so it's
the first real source for those values.

The source CSV has no header row: ListName, ListID, Code, Value per line. A
handful of labels contain embedded commas (e.g. "Man (Boy, if child)"), which
is exactly why the registry stores structured [code, label] pairs rather than
a comma-joined "code=label" string -- see schema_rules.py's `decodePairs` and
SCHEMA_FORMAT.md.

Pure standard library, consistent with the rest of this repo.
"""

import csv
import json
import os

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE_CSV = os.path.join(REPO_ROOT, "reference", "CW_List_Values_and_Descriptions.csv")
OUT_JSON = os.path.join(REPO_ROOT, "reference", "cw_list_values.json")
SCHEMA_JSON = os.path.join(REPO_ROOT, "reference", "target_schema_full.json")


def build_registry():
    registry = {}
    with open(SOURCE_CSV, encoding="utf-8-sig", newline="") as f:
        for row in csv.reader(f):
            if len(row) < 4:
                continue
            name, list_id, code = row[0].strip(), row[1].strip(), row[2].strip()
            # A label itself may contain commas (csv.reader already handled any
            # quoting), so join back anything past the third column rather than
            # assuming exactly 4 fields.
            value = ",".join(row[3:]).strip()
            entry = registry.setdefault(list_id, {"name": name, "values": []})
            entry["values"].append([code, value])
    return registry


def report_coverage(registry):
    """Cross-check against target_schema_full.json's List fields, same spirit
    as extract_servtracker_schema.py's disagreement report: never silently
    drop a gap, print it for a human to see."""
    if not os.path.exists(SCHEMA_JSON):
        return
    with open(SCHEMA_JSON, encoding="utf-8") as f:
        schema = json.load(f)

    list_fields = [r for r in schema if r.get("type") == "List" and r.get("listId") is not None]
    covered = [r for r in list_fields if str(r["listId"]) in registry]
    not_covered = [r for r in list_fields if str(r["listId"]) not in registry]

    print(f"Registry: {len(registry)} distinct ListIDs, "
          f"{sum(len(e['values']) for e in registry.values())} total values.")
    print(f"Schema List fields with a listId: {len(list_fields)}")
    print(f"  covered by this registry: {len(covered)}")
    print(f"  NOT covered (still a known gap, nothing fabricated): {len(not_covered)}")
    for r in not_covered:
        print(f"    {r['table']}.{r['field']} (listId={r['listId']})")


def main():
    registry = build_registry()
    with open(OUT_JSON, "w", encoding="utf-8") as f:
        json.dump(registry, f, indent=2, sort_keys=True)
        f.write("\n")
    print(f"Wrote {OUT_JSON}")
    report_coverage(registry)


if __name__ == "__main__":
    main()
