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

A fourth input, Advanced mode's structured "source values" list (a per-field
box the customer fills in alongside desc, e.g. "M, F, U" or "1=Yes, 2=No"),
takes priority over desc when both are present -- see _source_pairs below.
It's not fabricated either: same rule, a deliberate customer-entered fact,
just entered as a structured list instead of parsed out of a sentence.

A fifth input, and the highest priority of all: a *confirmed* value map from
the Advanced-mode value-matching step (app.js's renderValueMatchStep), where
the customer picked each of their source values' target code from a dropdown
of the target's own approved values one at a time. This isn't reconciled
against target_pairs at all here -- it was already built *from* target_pairs
in that step, so there's nothing left to verify; it's used as-is. That step
is itself only shown for fields with a decode/list-constrained target, so a
confirmed_value_map should never arrive for a field with no target_pairs.
"""

from schema_rules import parse_decode, parse_value_list, target_value_pairs as _target_pairs


def _normalize_label(label):
    return (label or "").strip().lower()


def _source_pairs(desc, source_values):
    """What the customer told us about their own source encoding, preferring
    the structured Advanced-mode list (parse_value_list, which never drops a
    bare entry) over the free-text desc (parse_decode, which does) when both
    are present -- a deliberate structured list is a stronger fact than a
    sentence we're pattern-matching. Returns (pairs, origin_text) so the
    caller's note can say which one actually got used.
    """
    if source_values:
        pairs = parse_value_list(source_values)
        if pairs:
            return pairs, ("your listed source values", source_values)
    if desc:
        pairs = parse_decode(desc)
        if pairs:
            return pairs, ("this session's own note", desc)
    return [], (None, None)


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


def draft_or_explain(
    dialect, source_field_quoted, target_field, meta, desc, historical_patterns, source_values="",
    confirmed_value_map="",
):
    """Returns a dict with an explicit "kind" so callers never need to sniff
    the note text to decide where it belongs:
      kind="drafted"    -- sql is the CASE WHEN fragment to use as the column
      kind="failed"     -- plain alias stands; note explains the mismatch
      kind="suggested"  -- plain alias stands; note is a historical-pattern
                           suggestion, never generated as code
      kind=None         -- nothing to say (target has no decode constraint)

    source_values: Advanced mode's structured per-field list (e.g. "M, F, U"
    or "1=Yes, 2=No") -- takes priority over desc when both are present, see
    _source_pairs.

    confirmed_value_map: the customer's own explicit source-value -> target-
    code choices from the value-matching step (e.g. "M=1,F=2,U=3") -- takes
    priority over everything else below. Not a draft to review; it's already
    a human decision, so it's used outright.
    """
    target_pairs = _target_pairs(meta)
    if not target_pairs:
        return {"sql": None, "note": None, "kind": None}

    if confirmed_value_map:
        mapping = dict(parse_value_list(confirmed_value_map))
        if mapping:
            sql = build_case_when(dialect, source_field_quoted, mapping, None, target_pairs)
            note = (
                f"Built from your confirmed value mapping for {target_field} -- you matched each of your "
                f"source values to one of its approved values yourself, so this isn't a guess to verify, "
                f"just a record of that choice."
            )
            return {"sql": sql, "note": note, "kind": "drafted"}

    # ServTracker-style pairs are (label, label) -- showing "Monthly=Monthly"
    # would just be noise; show the bare label list instead in that case.
    if all(c == l for c, l in target_pairs):
        target_shown = ", ".join(l for _, l in target_pairs)
    else:
        target_shown = ", ".join(f"{c}={l}" for c, l in target_pairs)
    source_pairs, (origin_label, origin_value) = _source_pairs(desc, source_values)
    if source_pairs:
        mapping, reason = _reconcile(source_pairs, target_pairs)
        if mapping:
            sql = build_case_when(dialect, source_field_quoted, mapping, source_pairs, target_pairs)
            note = (
                f"Drafted from {origin_label} ('{origin_value}') matched against {target_field}'s "
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
        hist_pairs, _origin = _source_pairs(top["desc"], "")
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
