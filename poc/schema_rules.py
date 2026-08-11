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

# CaseWorthy-specific: a listId -> {"name", "values":[[code,label],...]}
# registry built from a direct export of CaseWorthy's ListItem table (see
# tools/build_cw_list_values.py) -- the actual codes/labels behind a List
# field's `listId`, which the validation script itself never spells out.
# ServTracker has no equivalent list system, so this is never consulted for
# it (see load_schema's target_database gate below).
LIST_VALUES_PATH = os.path.join(REFERENCE_DIR, "cw_list_values.json")
_LIST_VALUES_CACHE = None


def load_list_values():
    global _LIST_VALUES_CACHE
    if _LIST_VALUES_CACHE is None:
        if os.path.exists(LIST_VALUES_PATH):
            with open(LIST_VALUES_PATH, encoding="utf-8") as f:
                _LIST_VALUES_CACHE = json.load(f)
        else:
            _LIST_VALUES_CACHE = {}
    return _LIST_VALUES_CACHE


def _enrich_list_fields(schema):
    """Resolve every List-type row's `listId` against the ListItem registry,
    overwriting whatever `decode` it already had -- the pre-existing
    hand-typed decodes on ~39 fields turned out to be illustrative examples,
    not the full list (two literally ended in "...etc."), so the registry
    (a real export) wins whenever it has that listId. A row whose listId
    isn't in the registry (currently just Provider.ProviderTypeCategoryTypeID)
    is left exactly as it was -- still an honest, reported gap, not guessed at.

    `decodePairs` (a real list of [code, label] pairs) is the new source of
    truth for machine parsing; `decode` is recomputed alongside it purely as
    the human-readable display string, since some labels contain commas that
    would corrupt the old comma-split parser (see SCHEMA_FORMAT.md)."""
    registry = load_list_values()
    if not registry:
        return schema
    for row in schema:
        if row.get("type") != "List" or row.get("listId") is None:
            continue
        entry = registry.get(str(row["listId"]))
        if not entry or not entry.get("values"):
            continue
        pairs = [(code, label) for code, label in entry["values"]]
        row["decodePairs"] = pairs
        row["decode"] = ", ".join(f"{code}={label}" for code, label in pairs)
    return schema

# Per-target-database presentation and scoping metadata, served to the UI so the
# frontend stops hardcoding which databases exist and which are usable.
#
# Both databases are module-scoped now, but for different reasons, which is why
# `groupNoun`, `scopingReason`, and `defaultSelectAll` differ between them:
#
# - ServTracker ships as ~18 separate program-area workbooks and a customer
#   migrates only the ones they run. Column names repeat heavily across sheets
#   (`Site`, `StartDate`, `Funding`), so *narrowing* the selection is the whole
#   point -- defaulting to "everything" would recreate the exact ambiguity
#   scoping exists to fix. Its modules are genuine multi-sheet groupings (each
#   schema row's `modules` list may name a program area with several sheets).
#
# - CaseWorthy is one staging workbook with 28 tables and no name collisions
#   across them, so there's no ambiguity problem to fix. Scoping here is a
#   convenience for targeting only the tabs a migration actually needs -- each
#   "module" is just one table (a schema row's `modules` is always
#   `[table]`), and the sensible default is everything selected, same as its
#   original unscoped behavior, with an explicit way to narrow down.
#
# `baseModules` are always included regardless of what the customer picks: every
# ServTracker sheet keys off ClientImportId from the client sheet, so the client
# module is a base requirement, not an option (confirmed by Alex Button,
# 2026-08-05). CaseWorthy has no equivalent -- nothing is forced.
TARGET_DB_META = {
    "CaseWorthy": {
        "label": "CaseWorthy",
        "logo": "/assets/logos/caseworthy-corporate.png",
        "modules": True,
        "baseModules": [],
        "unitNoun": "table",
        "groupNoun": "tab",
        "scopingReason": "Select which tabs on the staging report this migration actually needs. "
        "All tabs are selected by default -- narrow it down, or leave everything checked.",
        "defaultSelectAll": True,
    },
    "ServTracker": {
        "label": "ServTracker",
        "logo": "/assets/logos/servtracker.png",
        "modules": True,
        "baseModules": ["Client Master with Demographics"],
        "unitNoun": "sheet",
        "groupNoun": "module",
        "scopingReason": "Pick only what this customer actually runs -- narrowing improves suggestion "
        "accuracy, because the same column name (Site, StartDate, Funding) appears on many sheets.",
        "defaultSelectAll": False,
    },
}


def db_meta(target_database):
    return TARGET_DB_META.get(target_database, TARGET_DB_META[DEFAULT_TARGET_DATABASE])


def list_modules(target_database, schema=None):
    """Modules available for a target database, derived from the schema itself.

    Returns [] for a database that isn't module-scoped, which is what tells the
    UI not to render a module picker at all.
    """
    meta = db_meta(target_database)
    if not meta.get("modules"):
        return []
    rows = schema if schema is not None else load_schema(target_database)
    base = set(meta.get("baseModules") or [])
    grouped = {}
    for row in rows:
        for module in row.get("modules") or []:
            entry = grouped.setdefault(
                module, {"name": module, "sheets": set(), "fieldCount": 0, "required": module in base}
            )
            entry["sheets"].add(row.get("sheet") or row.get("table"))
            entry["fieldCount"] += 1
    out = []
    for entry in grouped.values():
        entry["sheets"] = sorted(entry["sheets"])
        out.append(entry)
    # Base modules first, then alphabetical -- the picker should lead with what
    # the customer can't opt out of.
    return sorted(out, key=lambda e: (not e["required"], e["name"]))


def scope_schema(schema, target_database, modules):
    """Narrow a schema to the selected modules, plus any base modules.

    A database without modules, or a request that names none, is returned
    untouched -- CaseWorthy must behave exactly as it did before scoping existed.
    """
    meta = db_meta(target_database)
    if not meta.get("modules") or not modules:
        return schema
    keep = set(modules) | set(meta.get("baseModules") or [])
    return [r for r in schema if not r.get("modules") or (set(r["modules"]) & keep)]

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
    if target_database == "CaseWorthy":
        schema = _enrich_list_fields(schema)
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


def parse_value_list(values_str):
    """'M, F, U' or '1=Yes, 2=No' -> [("M","M"), ("F","F"), ("U","U")] or
    [("1","Yes"), ("2","No")]. Unlike parse_decode, a bare entry with no '='
    is never dropped -- it's the customer directly naming one of the field's
    own values (e.g. their source already stores 'Yes'/'No', not a code), so
    it gets self-paired (code == label) rather than silently discarded. Used
    for the Advanced-mode "source values" list, which is a deliberate,
    customer-entered enumeration -- not free text to guess at."""
    pairs = []
    for part in (values_str or "").split(","):
        part = part.strip()
        if not part:
            continue
        if "=" in part:
            k, v = part.split("=", 1)
            pairs.append((k.strip(), v.strip()))
        else:
            pairs.append((part, part))
    return pairs


def target_value_pairs(meta):
    """(code, label) pairs a target field actually accepts, regardless of
    which of the decode styles this schema row uses.

    CaseWorthy List fields resolved against the ListItem registry (see
    _enrich_list_fields): `decodePairs` is already structured [code, label]
    pairs -- use it directly, never re-parse `decode`'s comma-joined display
    string, since some labels contain their own commas.
    CaseWorthy-style hand-typed: `decode` is a real "code=label" string --
    parse it.
    ServTracker-style: `decodeValues` is bare labels with no separate code at
    all (the label *is* what gets typed into the sheet) -- so each value
    pairs with itself; there's nothing to translate on the target side.

    Shared by transform_draft.py's CASE WHEN drafting and this module's own
    _source_values_mismatch -- one definition of "what does the target
    accept" for both."""
    if meta.get("decodePairs"):
        return [(str(code), str(label)) for code, label in meta["decodePairs"]]
    if meta.get("decode"):
        pairs = parse_decode(meta["decode"])
        if pairs:
            return pairs
    if meta.get("decodeValues"):
        return [(v, v) for v in meta["decodeValues"]]
    return []


def _list_id_suffix(meta):
    """' (List ID: N)' when a List field's decode came from the ListItem
    registry -- lets a data person cross-reference the source ListItem table
    directly instead of just trusting the label text."""
    return f" (List ID: {meta['listId']})" if meta.get("listId") is not None else ""


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

    list_suffix = _list_id_suffix(meta)
    decode_pairs = meta.get("decodePairs")
    values = meta.get("decodeValues")
    if decode_pairs:
        codes = {code for code, _ in decode_pairs}
        labels = {label.lower() for _, label in decode_pairs}
        shown = (meta.get("decode") or ", ".join(f"{c}={l}" for c, l in decode_pairs)) + list_suffix
    elif values:
        codes = {v for v in values if v.isdigit()}
        labels = {v.lower() for v in values if not v.isdigit()}
        shown = (meta.get("decode") or ", ".join(values)) + list_suffix
    else:
        if not meta.get("decode"):
            return None
        pairs = parse_decode(meta["decode"])
        if not pairs:
            return None
        codes = {k for k, _ in pairs}
        labels = {v.lower() for _, v in pairs}
        shown = meta["decode"] + list_suffix

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


def _source_values_mismatch(meta, source_values):
    """Exact-set comparison against the customer's own structured "source
    values" list (Advanced mode) -- every entry there was deliberately typed
    as a value, not inferred from a sentence like the free-text desc checks
    below, so this reports any listed value with no exact matching target
    label rather than the heuristic pattern-matching _decode_mismatch does.
    No-ops (returns None) when the target has no decode/decodeValues to
    compare against, same scope target_value_pairs already has."""
    target_pairs = target_value_pairs(meta)
    if not target_pairs:
        return None
    source_pairs = parse_value_list(source_values)
    if not source_pairs:
        return None
    target_labels = {label.strip().lower() for _, label in target_pairs}
    unmatched = [
        (f"{code}={label}" if code != label else label)
        for code, label in source_pairs
        if label.strip().lower() not in target_labels
    ]
    if unmatched:
        target_shown = ", ".join(l for _, l in target_pairs) if all(c == l for c, l in target_pairs) else (
            ", ".join(f"{c}={l}" for c, l in target_pairs)
        )
        return (
            f"Your listed source value(s) {', '.join(unmatched)} don't exactly match any of "
            f"{meta['table']}.{meta['field']}'s allowed values ({target_shown}){_list_id_suffix(meta)}."
        )
    return None


def _source_values_boolean_mismatch(meta, source_values):
    """Same idea as _source_values_mismatch but for Boolean targets, which
    have no decode/decodeValues to compare against (target_value_pairs
    returns nothing for them) -- so this checks arity directly against the
    structured list instead: a Boolean target only accepts two values, and
    every entry in source_values was deliberately typed as one of this
    field's actual values, not inferred."""
    if not meta.get("type", "").startswith("Boolean"):
        return None
    pairs = parse_value_list(source_values)
    distinct = {label.strip().lower() for _, label in pairs}
    if len(distinct) > 2:
        return (
            f"{meta['table']}.{meta['field']} only accepts two values (0/1), but your listed source "
            f"values ({source_values}) name {len(distinct)} distinct options."
        )
    return None


def _source_values_length_mismatch(meta, source_values):
    """Same idea as _source_values_mismatch but for a max-length constraint:
    flags any listed value whose own text is already longer than the target
    allows, since that's a fact about the value itself, not a guess."""
    m = re.match(r"Text \(max (\d+)\)", meta.get("type", ""))
    if not m:
        return None
    max_len = int(m.group(1))
    pairs = parse_value_list(source_values)
    too_long = [label for _, label in pairs if len(label) > max_len]
    if too_long:
        return (
            f"Your listed source value(s) {', '.join(repr(v) for v in too_long)} are already longer than "
            f"{meta['table']}.{meta['field']}'s max length ({max_len} characters)."
        )
    return None


SOURCE_VALUE_CHECKS = (_source_values_mismatch, _source_values_boolean_mismatch, _source_values_length_mismatch)


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

    A mapping's Advanced-mode `sourceValues` (a structured list the customer
    deliberately typed, e.g. "M, F, U" or "1=Yes, 2=No" -- see
    parse_value_list) takes priority over desc's heuristics when present:
    SOURCE_VALUE_CHECKS (decode/list exact-set, Boolean arity, max length --
    the same three shapes FORMAT_CHECKS covers for desc, just against a
    deliberate list instead of a sentence being pattern-matched) run first;
    desc's own checks still run afterward as a secondary pass -- a clean
    sourceValues match doesn't mean desc has nothing else to flag.
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
        if not (m.get("table") and m.get("field")):
            continue
        if not m.get("desc") and not m.get("sourceValues"):
            continue
        meta = next((f for f in by_table.get(m["table"], []) if f["field"] == m["field"]), None)
        if not meta:
            continue
        meta = dict(meta, table=m["table"], field=m["field"])
        hint = None
        if m.get("sourceValues"):
            for check in SOURCE_VALUE_CHECKS:
                hint = check(meta, m["sourceValues"])
                if hint:
                    break
        if not hint and m.get("desc"):
            for check in FORMAT_CHECKS:
                hint = check(meta, m["desc"])
                if hint:
                    break  # one desc-based hint per mapping is plenty; avoid piling on
        if hint:
            format_hints.append(
                {"sourceField": m["sourceField"], "table": m["table"], "field": m["field"], "hint": hint}
            )

    return {
        "requiredMissing": required_missing,
        "fkWarnings": fk_warnings,
        "duplicates": duplicates,
        "formatHints": format_hints,
    }
