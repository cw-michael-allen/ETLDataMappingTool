"""
Rule engine that knows the CaseWorthy target-schema constraints (required
fields, FK relationships, decode values) extracted from the validation
script, and flags a customer's proposed mappings that would violate them —
without ever validating real data values. See docs/PHASE_PLAN.md section 2.
"""

import json
import os
import re
from collections import defaultdict

SCHEMA_PATH = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", "reference", "target_schema_full.json"
)


def load_schema():
    with open(SCHEMA_PATH, encoding="utf-8") as f:
        return json.load(f)


def schema_by_table(schema):
    out = defaultdict(list)
    for row in schema:
        out[row["table"]].append(row)
    return out


def fk_target_table(type_str, known_tables):
    if not type_str or "FK" not in type_str:
        return None
    if "→" not in type_str:
        return None
    part = type_str.split("→", 1)[1].strip()
    # e.g. "Program", "Client or Provider (depends on EntityContextType)"
    candidate = re.split(r"\s+or\s+|\(", part)[0].strip()
    return candidate if candidate in known_tables else None


def check_batch(mappings, schema):
    """
    mappings: list of {"sourceField":str, "desc":str, "table":str|None, "field":str|None}
    Returns {"requiredMissing":[...], "fkWarnings":[...], "duplicates":[...], "decodeHints":[...]}
    """
    by_table = schema_by_table(schema)
    known_tables = set(by_table.keys())
    touched_tables = sorted({m["table"] for m in mappings if m.get("table")})
    mapped_pairs = {(m["table"], m["field"]) for m in mappings if m.get("table") and m.get("field")}

    required_missing = []
    for t in touched_tables:
        for f in by_table.get(t, []):
            if f.get("required") and (t, f["field"]) not in mapped_pairs:
                required_missing.append({"table": t, "field": f["field"]})

    fk_warnings = []
    for t in touched_tables:
        for f in by_table.get(t, []):
            dep = fk_target_table(f.get("type", ""), known_tables)
            if dep and dep not in touched_tables:
                fk_warnings.append({"table": t, "field": f["field"], "dependsOn": dep})

    grouped = defaultdict(list)
    for m in mappings:
        if m.get("table") and m.get("field"):
            grouped[(m["table"], m["field"])].append(m["sourceField"])
    duplicates = [
        {"table": k[0], "field": k[1], "sourceFields": v} for k, v in grouped.items() if len(v) > 1
    ]

    decode_hints = []
    for m in mappings:
        if not (m.get("table") and m.get("field")):
            continue
        meta = next((f for f in by_table.get(m["table"], []) if f["field"] == m["field"]), None)
        if meta and meta.get("decode") and m.get("desc"):
            digits = re.findall(r"\d+", m["desc"])
            decode_keys = re.findall(r"(\d+)\s*=", meta["decode"])
            if digits and decode_keys and not any(d in decode_keys for d in digits):
                decode_hints.append(
                    {
                        "sourceField": m["sourceField"],
                        "table": m["table"],
                        "field": m["field"],
                        "hint": f"Your note mentions {', '.join(digits)}, but "
                        f"{m['table']}.{m['field']} expects: {meta['decode']}",
                    }
                )

    return {
        "requiredMissing": required_missing,
        "fkWarnings": fk_warnings,
        "duplicates": duplicates,
        "decodeHints": decode_hints,
    }
