"""
Deterministic value-formatting rules baked directly into the Advanced-mode SQL
export's SELECT expressions (see sql_export.py), for the small set of target-
field patterns whose correct shape is a fact about CaseWorthy's own target
schema and its own production migration scripts -- never a guess about a
customer's data. The SSN dashing, phone/fax cleanup, zip default, and name
truncation/null-fallback patterns below are lifted directly from CaseWorthy's
own CWL ETL scripts (reference/MASTER_02_Organization_Provider_Users_Client.sql
and friends), the same way transform_draft.py's CASE WHEN drafting is built
only from facts already on record for a given migration.

CaseWorthy-only, deliberately: these patterns were never sourced against
ServTracker's own validation script, so applying them there would be exactly
the kind of fabricated target-schema rule the product boundary in CLAUDE.md
rules out. Callers must check target_database == "CaseWorthy" before calling
anything in this module -- it does not check for itself, so a caller mistake
fails loud (KeyError/None) rather than silently reusing CaseWorthy's rules for
another application.

Two shapes, mirroring how the source script itself is structured:
- Column rules (`column_rule`): reformat the SAME source value already mapped
  to a target field -- SSN dashing, phone/fax digit cleanup, zip default and
  truncation, and first/last/middle name truncation with the exact
  ISNULL(...,'FirstName') null-fallback the source script uses.
- Companion rules (`companion_rule`): when an anchor field is mapped (SSN,
  BirthDate) and its paired quality-flag field (SSNDataQuality,
  DOBDataQuality) is a real column on the same target table with no mapping
  of its own, synthesize that second column from the SAME source value --
  exactly how the sourced script derives it, because a customer's source
  system rarely has a separate "how good is this SSN" field of its own. Never
  synthesized when the companion is already separately mapped -- that
  mapping's own value always wins.
"""

import re

_TEXT_MAX = re.compile(r"^Text \(max (\d+)\)$")
_TEXT_DIGITS = re.compile(r"^Text \(\d+ digits\)$")

# char(10) per the ZipCode/ClientAddress comment in MASTER_02 -- Client.Zip
# itself is typed as plain "Text" with no max in the extracted schema.
_DEFAULT_ZIP_MAX = 10


def _clean_digits_expr(quoted_source):
    return (
        f"REPLACE(REPLACE(REPLACE(REPLACE({quoted_source}, '-', ''), '(', ''), ')', ''), ' ', '')"
    )


def _phone_dashed_expr(quoted_source):
    cleaned = _clean_digits_expr(quoted_source)
    return (
        "CASE\n"
        f"        WHEN LEN({cleaned}) = 10 THEN SUBSTRING({cleaned}, 1, 3) + '-' + SUBSTRING({cleaned}, 4, 3) + '-' + SUBSTRING({cleaned}, 7, 4)\n"
        f"        WHEN LEN({cleaned}) = 7 THEN '000-' + SUBSTRING({cleaned}, 1, 3) + '-' + SUBSTRING({cleaned}, 4, 4)\n"
        "        ELSE NULL\n"
        "    END"
    )


def _ssn_expr(quoted_source):
    cleaned = f"REPLACE(REPLACE({quoted_source}, '-', ''), ' ', '')"
    return (
        "CASE\n"
        f"        WHEN {cleaned} = '' OR {cleaned} IS NULL THEN NULL\n"
        f"        WHEN LEN({cleaned}) = 9 THEN SUBSTRING({cleaned}, 1, 3) + '-' + SUBSTRING({cleaned}, 4, 2) + '-' + SUBSTRING({cleaned}, 6, 4)\n"
        f"        WHEN LEN({cleaned}) = 4 THEN 'XXX-XX-' + {cleaned}\n"
        "        ELSE NULL\n"
        "    END"
    )


def _ssn_quality_expr(quoted_source):
    """Mirrors MASTER_02's SSNDataQuality CASE WHEN, minus the two branches
    that read SSNDataQuality itself (there's no separate source column for
    it here -- this is a companion synthesized from the SSN value alone)."""
    cleaned = f"REPLACE(REPLACE({quoted_source}, '-', ''), ' ', '')"
    return (
        "CASE\n"
        f"        WHEN {cleaned} = '' OR {cleaned} IS NULL THEN 99\n"
        f"        WHEN {cleaned} LIKE '%X%' THEN 2\n"
        f"        WHEN LEN({cleaned}) = 9 THEN 1\n"
        f"        WHEN LEN({cleaned}) = 4 THEN 2\n"
        "        ELSE NULL\n"
        "    END"
    )


def _dob_quality_expr(quoted_source):
    """Mirrors the fallback branch of MASTER_02's DOBDataQuality CASE WHEN --
    the first branch (passing through an existing DOBDataQuality value)
    doesn't apply here since there's no separate source column for it."""
    return f"CASE WHEN TRY_CONVERT(DATE, {quoted_source}) IS NOT NULL THEN 1 ELSE NULL END"


def _zip_expr(quoted_source, max_len):
    return (
        f"CASE WHEN {quoted_source} IS NULL OR {quoted_source} = '' THEN '00000' "
        f"ELSE LEFT({quoted_source}, {max_len}) END"
    )


def column_rule(quoted_source, meta):
    """meta is a target-schema row (table/field/type/...). Returns
    {"sql": str, "note": str} to override the plain column alias, or None to
    leave it alone. CaseWorthy-only -- see module docstring."""
    field = meta.get("field") or ""
    field_lower = field.lower()
    type_str = meta.get("type") or ""

    if field_lower == "ssn":
        return {
            "sql": _ssn_expr(quoted_source),
            "note": f"{field}: reformatted to XXX-XX-XXXX (or partial XXX-XX-#### for a 4-digit value), "
            "the same pattern CaseWorthy's own migration scripts use.",
        }

    if _TEXT_DIGITS.match(type_str):
        return {
            "sql": _clean_digits_expr(quoted_source),
            "note": f"{field}: dashes/parens/spaces stripped to match its required {type_str} format.",
        }

    if type_str == "Text" and ("phone" in field_lower or field_lower == "fax"):
        return {
            "sql": _phone_dashed_expr(quoted_source),
            "note": f"{field}: reformatted to XXX-XXX-XXXX for a 10-digit value, or defaulted to a "
            "000 area code for a 7-digit value.",
        }

    if field_lower in ("zip", "zipcode"):
        if type_str.startswith("Integer"):
            return None  # can't safely reformat a numeric zip without risking leading-zero loss
        m = _TEXT_MAX.match(type_str)
        max_len = int(m.group(1)) if m else _DEFAULT_ZIP_MAX
        return {
            "sql": _zip_expr(quoted_source, max_len),
            "note": f"{field}: blank/null defaulted to '00000', otherwise truncated to {max_len} characters.",
        }

    if field_lower in ("firstname", "lastname"):
        m = _TEXT_MAX.match(type_str)
        if m:
            max_len = m.group(1)
            return {
                "sql": f"ISNULL(LEFT({quoted_source}, {max_len}), '{field}')",
                "note": f"{field}: truncated to {max_len} characters, null-defaulted to '{field}'.",
            }

    if field_lower == "middlename":
        m = _TEXT_MAX.match(type_str)
        if m:
            return {
                "sql": f"LEFT({quoted_source}, {m.group(1)})",
                "note": f"{field}: truncated to {m.group(1)} characters.",
            }

    return None


_COMPANIONS = {
    "ssn": (
        "ssndataquality",
        _ssn_quality_expr,
        "SSNDataQuality derived from the same SSN value (blank/null=99 Unknown, contains 'X'=2 "
        "Partial, 9 digits=1 Full, 4 digits=2 Partial) -- the same logic CaseWorthy's own migration "
        "scripts use when a source system has no separate quality flag.",
    ),
    "birthdate": (
        "dobdataquality",
        _dob_quality_expr,
        "DOBDataQuality derived from the same BirthDate value (1=Actual if it parses as a date, "
        "else left NULL) -- the same fallback CaseWorthy's own migration scripts use when a source "
        "system has no separate quality flag.",
    ),
}


def companion_field_lower(anchor_field_lower):
    """The companion target field name (lowercased) for an anchor field, or
    None if this anchor has no companion. Lets the caller check whether that
    field exists on the target table (and isn't already separately mapped)
    before bothering to build the expression."""
    entry = _COMPANIONS.get((anchor_field_lower or "").lower())
    return entry[0] if entry else None


def companion_rule(anchor_field_lower, quoted_anchor_source):
    """Returns {"sql": str, "note": str} for the companion column synthesized
    from an already-mapped anchor field's own source value, or None."""
    entry = _COMPANIONS.get((anchor_field_lower or "").lower())
    if not entry:
        return None
    _companion_field, builder, note = entry
    return {"sql": builder(quoted_anchor_source), "note": note}
