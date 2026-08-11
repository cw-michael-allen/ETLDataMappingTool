"""
Convert CaseWorthy's FormElement type lookup (reference/cw_element_types.tsv,
provided directly by Michael, 2026-08-11 -- the authoritative ElementTypeID
list, not inferred from sample forms) into reference/cw_element_types.json,
an ElementTypeID -> {className, description} registry that
create_template.py resolves every FormElement's ElementTypeID against.

Run:
    python tools/build_cw_element_types.py

Replaces the earlier best-effort ELEMENT_TYPE_MAP in create_template.py
(inferred from only one sample export's 4 observed ElementTypeIDs) now that
the real, complete list is available -- see create_template.py's own
docstring for why this distinction matters (never guess a CaseWorthy fact
when the real one is available).

Pure standard library, consistent with the rest of this repo.
"""

import csv
import json
import os

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE_TSV = os.path.join(REPO_ROOT, "reference", "cw_element_types.tsv")
OUT_JSON = os.path.join(REPO_ROOT, "reference", "cw_element_types.json")


def build_registry():
    registry = {}
    with open(SOURCE_TSV, encoding="utf-8-sig", newline="") as f:
        reader = csv.reader(f, delimiter="\t")
        header = next(reader)
        assert header[:3] == ["ElementTypeID", "ClassName", "Description"], header
        for row in reader:
            if not row or not row[0].strip():
                continue
            element_type_id, class_name, description = row[0].strip(), row[1].strip(), row[2].strip()
            registry[element_type_id] = {"className": class_name, "description": description}
    return registry


def main():
    registry = build_registry()
    with open(OUT_JSON, "w", encoding="utf-8") as f:
        json.dump(registry, f, indent=2, sort_keys=True)
        f.write("\n")
    print(f"Wrote {OUT_JSON}: {len(registry)} ElementTypeIDs.")


if __name__ == "__main__":
    main()
