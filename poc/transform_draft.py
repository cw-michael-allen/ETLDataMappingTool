"""
Drafts a value-transform (a SQL CASE WHEN) for the Advanced-mode SQL export,
but only when it can be built from two facts already on record for *this*
migration -- never from an assumption about how a source system encodes
values. See sql_export.py's own docstring for the boundary this exists
inside of.

Two facts, both already collected elsewhere, are what a draft is built
from:
1. The target's own decode/list constraint (schema_rules.parse_decode against
   the signed-off target schema) -- what CaseWorthy/ServTracker requires.
2. The customer's own typed description for this field in Step 2 (e.g.
   "1=Yes, 2=No") -- what they told us their source uses.

When both parse into code/label pairs and every source label matches a
target label exactly (case-insensitive, no fuzzy/synonym guessing -- "Yes"
is not assumed to mean "True"), the CASE WHEN is safe to draft: it's a
mechanical join of two things we were already told, not an inference about
data the tool has never seen. Anything short of that -- no description,
an unparseable one, or a label that doesn't match -- returns no SQL, only an
explanation for the TODO header.

A third input, historical patterns (descriptions other confirmed mappings to
this same target field have used, from db.get_decode_patterns /
shared_mappings' equivalent), is used *only* to surface a text suggestion in
the TODO header when this field's own description isn't usable. It never
becomes generated SQL on its own -- there's no confirmation behind it for
*this* migration, just precedent from others, so it stays a suggestion a
human reads and decides on, not code that runs.
"""

from schema_rules import parse_decode


def _normalize_label(label):
    return (label or "").strip().lower()


def _target_pairs(meta):
    """(code, label) pairs the target actually accepts, regardless of which
    of the two decode styles this schema row uses.

    CaseWorthy-style: `decode` is a real "code=label" string -- parse it.
    ServTracker-style: `decodeValues` is bare labels with no separate code at
    all (the label *is* what gets typed into the sheet) -- so each value
    pairs with itself; there's nothing to translate on the target side.
    """
    if meta.get("decode"):
        pairs = parse_decode(meta["decode"])
        if pairs:
            return pairs
    if meta.get("decodeValues"):
        return [(v, v) for v in meta["decodeValues"]]
    return []


def _source_pairs(desc):
    """What the customer told us about their own source encoding. Reuses the
    exact same "code=label, code=label" parser as the target side -- same
    format, same tolerance, no separate guessing logic for either side."""
    return parse_decode(desc) if desc else []


def _reconcile(source_pairs, target_pairs):
    """All-or-nothing: every source label must match a target label exactly,
    or nothing gets drafted. A partial CASE WHEN silently missing a branch
    is worse than no draft at all -- so a single unmatched source value
    aborts the whole thing rather than mapping only the ones that fit.

    Returns (mapping dict {source_code: target_code}, None) on success, or
    (None, reason) on failure.
    """
    target_by_label = {_normalize_label(label): code for code, label in target_pairs}
    mapping = {}
    for src_code, src_label in source_pairs:
        tgt_code = target_by_label.get(_normalize_label(src_label))
        if tgt_code is None:
            return None, (
                f"source value '{src_code}={src_label}' has no exact matching label in the target's "
                f"allowed values ({', '.join(f'{c}={l}' for c, l in target_pairs)})"
            )
        mapping[src_code] = tgt_code
    if not mapping:
        return None, "description didn't contain any parseable code=label pairs"
    return mapping, None


def _quote_value(dialect, value):
    # Values go inside a CASE WHEN as string literals regardless of dialect
    # (the target column may be numeric, but comparing/assigning as text and
    # letting the destination table's own typing coerce it is what every
    # other column in this export already does -- no dialect-specific cast
    # is introduced here that isn't already implied by the column itself).
    escaped = str(value).replace("'", "''")
    return f"'{escaped}'"


def build_case_when(dialect, source_field_quoted, mapping, source_pairs, target_pairs):
    """The actual drafted SQL fragment (no alias -- the caller adds that,
    matching how a plain column alias is built today)."""
    lines = ["CASE " + source_field_quoted]
    for src_code, tgt_code in mapping.items():
        lines.append(f"        WHEN {_quote_value(dialect, src_code)} THEN {_quote_value(dialect, tgt_code)}")
    lines.append("        ELSE NULL")
    lines.append("    END")
    return "\n".join(lines)


def draft_or_explain(dialect, source_field_quoted, target_field, meta, desc, historical_patterns):
    """Returns a dict with an explicit "kind" so callers never need to sniff
    the note text to decide where it belongs:
      kind="drafted"    -- sql is the CASE WHEN fragment to use as the column
      kind="failed"     -- plain alias stands; note explains the mismatch
      kind="suggested"  -- plain alias stands; note is a historical-pattern
                           suggestion, never generated as code
      kind=None         -- nothing to say (target has no decode constraint)
    """
    target_pairs = _target_pairs(meta)
    if not target_pairs:
        return {"sql": None, "note": None, "kind": None}

    # ServTracker-style pairs are (label, label) -- showing "Monthly=Monthly"
    # would just be noise; show the bare label list instead in that case.
    if all(c == l for c, l in target_pairs):
        target_shown = ", ".join(l for _, l in target_pairs)
    else:
        target_shown = ", ".join(f"{c}={l}" for c, l in target_pairs)
    source_pairs = _source_pairs(desc)
    if source_pairs:
        mapping, reason = _reconcile(source_pairs, target_pairs)
        if mapping:
            sql = build_case_when(dialect, source_field_quoted, mapping, source_pairs, target_pairs)
            note = (
                f"Drafted from this session's own note ('{desc}') matched against {target_field}'s "
                f"required values ({target_shown}). This is a draft, not a verified fact about your "
                f"data -- confirm it against real source values before running."
            )
            return {"sql": sql, "note": note, "kind": "drafted"}
        return {
            "sql": None,
            "note": f"Could not auto-draft a value mapping for {target_field}: {reason}.",
            "kind": "failed",
        }

    if historical_patterns:
        top = historical_patterns[0]
        hist_pairs = _source_pairs(top["desc"])
        if hist_pairs:
            mapping, _reason = _reconcile(hist_pairs, target_pairs)
            if mapping:
                return {
                    "sql": None,
                    "note": (
                        f"No description given for this field, but {top['count']} past confirmed mapping(s) "
                        f"to {target_field} described their source encoding as '{top['desc']}'. If your "
                        f"source system matches, consider mapping it the same way -- verify against your "
                        f"own source data first, this was never applied automatically."
                    ),
                    "kind": "suggested",
                }

    return {"sql": None, "note": None, "kind": None}
