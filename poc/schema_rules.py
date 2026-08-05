"""
Rule engine that knows a target application's schema constraints (required
fields, FK relationships, decode values) extracted from that application's
validation script, and flags a customer's proposed mappings that would
violate them — without ever validating real data values. See
docs/PHASE_PLAN.md section 2.
"""

import json
import os
import re
from collections import defaultdict

REFERENCE_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "reference")

# Registry of target applications this tool can map against. CaseWorthy is
# the only one with a real, spot-checked schema today (see
# reference/target_schema_full.json, extracted from and confirmed against
# 00_Staging_EXCEL_Validation_Script_v3.sql). ServTracker is a distinct
# CaseWorthy application with its own validation rules and data templates —
# listed here so the UI can offer it, but its schema hasn't been extracted
# yet. We do not fabricate ServTracker rules; None means "not yet available."
TARGET_DATABASES = {
    "CaseWorthy": os.path.join(REFERENCE_DIR, "target_schema_full.json"),
    "ServTracker": os.path.join(REFERENCE_DIR, "servtracker_schema_full.json"),
}

DEFAULT_TARGET_DATABASE = "CaseWorthy"

# The `type` string is a contract: the format checks below regex-match it and an
# unrecognised value doesn't error, it just skips every check -- which the UI
# then renders as "no rule violations detected", indistinguishable from a clean
# result. These are the forms that actually drive a check or are knowingly
# informational. See reference/SCHEMA_FORMAT.md.
KNOWN_TYPE_PATTERNS = (
    r"^Text$",
    r"^Text \(max \d+\)$",
    r"^List$",
    r"^Boolean",
    r"^Date$",
    r"^Time$",
    r"^Numeric$",
    r"^Integer$",
    r"^Decimal$",
    r"^Float$",
    r"^Unique ID",
    r"^ID$",
    r"^FK → .+$",
    r"^Self-reference to .+$",
)

# Type strings that only *look* like a checked form. Called out separately
# because they read as though a constraint is enforced when none is: e.g.
# "Text (10 digits)" is not "Text (max 10)", so no length check runs on it.
_MISLEADING_HINT = re.compile(r"\((?:max )?\d+|digits|code|list", re.I)

SCHEMA_WARNINGS = {}


def _validate_types(target_database, schema):
    """Collect fields whose `type` no format check recognises.

    Deliberately does not raise: CaseWorthy's schema is human-signed-off and
    already contains a handful of these, so failing hard would break a working
    demo over pre-existing data. It records them instead, and app.py prints
    them at startup so the gap is visible rather than silent.
    """
    unknown = []
    for row in schema:
        t = (row.get("type") or "").strip()
        if not any(re.match(p, t) for p in KNOWN_TYPE_PATTERNS):
            unknown.append(
                {
                    "table": row.get("table"),
                    "field": row.get("field"),
                    "type": t,
                    "misleading": bool(_MISLEADING_HINT.search(t)),
                }
            )
    SCHEMA_WARNINGS[target_database] = unknown
    return unknown


def load_schema(target_database=DEFAULT_TARGET_DATABASE):
    path = TARGET_DATABASES.get(target_database)
    if not path or not os.path.exists(path):
        return []
    with open(path, encoding="utf-8") as f:
        schema = json.load(f)
    _validate_types(target_database, schema)
    return schema


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


def parse_decode(decode_str):
    """'1=Yes, 2=No' -> [("1","Yes"), ("2","No")]. Tolerates missing '=' entries."""
    pairs = []
    for part in decode_str.split(","):
        part = part.strip()
        if "=" in part:
            k, v = part.split("=", 1)
            pairs.append((k.strip(), v.strip()))
    return pairs


def _decode_mismatch(meta, desc):
    """Target is a List with known decode values; flag if the customer's own
    note names specific codes/labels that don't appear in that decode set.

    Two decode styles exist. CaseWorthy encodes code/label pairs
    ("1=Self, 2=Spouse"); ServTracker validates against bare labels
    ("Monthly", "One-Time"). `decodeValues` is the machine-readable list both
    styles populate -- without it the pair parser finds no codes in a
    ServTracker decode and this check quietly does nothing.
    """
    if meta.get("type") != "List" or not desc:
        return None

    values = meta.get("decodeValues")
    if values:
        codes = {v for v in values if v.isdigit()}
        labels = {v.lower() for v in values if not v.isdigit()}
        shown = meta.get("decode") or ", ".join(values)
    else:
        if not meta.get("decode"):
            return None
        pairs = parse_decode(meta["decode"])
        if not pairs:
            return None
        codes = {k for k, _ in pairs}
        labels = {v.lower() for _, v in pairs}
        shown = meta["decode"]

    # Only meaningful when the target actually uses numeric codes. For a
    # label-style list (ServTracker's "Monthly"/"One-Time") a number in the
    # customer's note is not evidence of a mismatch -- treating it as such
    # would fire on every List field whose note happens to contain a digit.
    nums = re.findall(r"\d+", desc)
    if codes and nums and not any(n in codes for n in nums):
        return (
            f"Your note mentions {', '.join(nums)}, but {meta['table']}.{meta['field']} "
            f"expects: {shown}"
        )

    # No numbers named — check whether the note looks like it's enumerating
    # values (has separators typical of an option list) with no overlap at all
    # against the decode labels.
    if re.search(r"[/,]|\bor\b", desc, re.I):
        words = {w.lower() for w in re.findall(r"[A-Za-z]{2,}", desc)}
        if words and not (words & labels) and not any(w in lbl or lbl in w for w in words for lbl in labels):
            return (
                f"Your note ('{desc}') doesn't obviously match any of {meta['table']}.{meta['field']}'s "
                f"expected values: {shown}"
            )
    return None


def _boolean_arity_mismatch(meta, desc):
    """Target only accepts two values (0/1), but the customer's note lists more than two options."""
    if not meta.get("type", "").startswith("Boolean") or not desc:
        return None
    option_pairs = re.findall(r"\d+\s*=\s*[A-Za-z]+", desc)
    slash_options = [p for p in re.split(r"\s*/\s*", desc) if p.strip()]
    if len(option_pairs) > 2 or len(slash_options) > 2:
        return (
            f"{meta['table']}.{meta['field']} only accepts two values (0/1), but your note "
            f"lists more than two options ('{desc}')."
        )
    return None


def _text_length_mismatch(meta, desc):
    """Target has a max character length; flag if the customer's own note claims a longer one."""
    m = re.match(r"Text \(max (\d+)\)", meta.get("type", ""))
    if not m or not desc:
        return None
    max_len = int(m.group(1))
    claim = re.search(r"(\d+)\s*(?:chars?|characters?)\b", desc, re.I) or re.search(
        r"varchar\((\d+)\)", desc, re.I
    )
    if claim and int(claim.group(1)) > max_len:
        return (
            f"Your note suggests up to {claim.group(1)} characters, but "
            f"{meta['table']}.{meta['field']} only allows {max_len}."
        )
    return None


FORMAT_CHECKS = (_decode_mismatch, _boolean_arity_mismatch, _text_length_mismatch)


def check_batch(mappings, schema):
    """
    mappings: list of {"sourceField":str, "desc":str, "table":str|None, "field":str|None}
    Returns {"requiredMissing":[...], "fkWarnings":[...], "duplicates":[...], "formatHints":[...]}

    formatHints are heuristic, best-effort checks of the customer's free-text
    field description against the target field's known constraints (decode
    values, boolean arity, max text length) extracted from the validation
    script. They never touch real data — only the format notes the customer
    typed in during the interview. False negatives are expected; each check
    is written to avoid false positives rather than catch every mismatch.
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

    format_hints = []
    for m in mappings:
        if not (m.get("table") and m.get("field")) or not m.get("desc"):
            continue
        meta = next((f for f in by_table.get(m["table"], []) if f["field"] == m["field"]), None)
        if not meta:
            continue
        meta = dict(meta, table=m["table"], field=m["field"])
        for check in FORMAT_CHECKS:
            hint = check(meta, m["desc"])
            if hint:
                format_hints.append(
                    {"sourceField": m["sourceField"], "table": m["table"], "field": m["field"], "hint": hint}
                )
                break  # one hint per mapping is plenty; avoid piling on

    return {
        "requiredMissing": required_missing,
        "fkWarnings": fk_warnings,
        "duplicates": duplicates,
        "formatHints": format_hints,
    }
