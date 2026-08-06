"""
Rule-based candidate matcher, grounded entirely in the target schema
extracted from 00_Staging_EXCEL_Validation_Script_v3.sql (see
schema_rules.py / reference/target_schema_full.json) — not an LLM call.

This exists so the tool can produce a real confidence match deterministically
(exact name matches, common ETL abbreviations, and near-matches) without
needing network access or an API key, and so a well-understood match doesn't
cost an LLM call at all. llm_gateway.suggest_mapping is still used as a
fallback for names this can't confidently resolve.
"""

import difflib
import re

# Common abbreviations seen across customer source-system exports, keyed by
# the *normalized target field name* they should resolve to. Deliberately
# conservative — only add an alias here if it's a genuine abbreviation that
# name-similarity scoring alone wouldn't catch.
ALIASES = {
    "birthdate": {"dob", "dateofbirth", "birthdt", "bdate", "dtofbirth"},
    "ssn": {"ssn", "socialsecuritynumber", "socsecno", "social"},
    "firstname": {"fname", "first", "givenname", "firstnm"},
    "lastname": {"lname", "last", "surname", "lastnm", "familyname"},
    "middlename": {"mname", "middle", "middlenm", "mi"},
    "cellphone": {"cell", "mobile", "mobilephone", "cellno"},
    "homephone": {"phone", "phonenumber", "phoneno", "tel", "telephone"},
    "zip": {"zip", "zipcode", "postalcode", "postcode"},
    "address": {"addr", "street", "streetaddress", "address1"},
    "address2": {"addr2", "aptsuite", "unit", "apartment"},
    "gender": {"sex"},
    "clientid": {"clientno", "clientnum", "clientnumber", "recipientid"},
    # ServTracker's client key. Customers almost never call their column
    # "ClientImportId" -- they bring ClientID/ClientNo/MemberID -- and without
    # this a source field named `Client_ID` matched ServTrackerClientId instead,
    # which is only for updating clients that already exist. Harmless for
    # CaseWorthy: it has a literal ClientID field, so an exact match wins there.
    "clientimportid": {
        "clientid", "clientno", "clientnum", "clientnumber", "recipientid",
        "uniqueid", "uniqueclientid", "participantid", "consumerid",
    },
    "enrollmentid": {"enrollid", "enrollno"},
    "programid": {"progid", "progno"},
    "providerid": {"provid", "provno", "agencyid"},
    "organizationid": {"orgid", "orgno"},
    "begindate": {"startdate", "begdt", "startdt", "effectivedate"},
    "enddate": {"stopdate", "enddt", "termdate", "expirationdate"},
    "createddate": {"createdon", "dateadded", "entrydate", "dateentered"},
    "userid": {"staffid", "employeeid", "empid"},
    "username": {"userlogin", "login", "loginname"},
    "isactive": {"active", "activeflag", "isenabled"},
    "veteranstatus": {"isveteran", "vetstatus", "veteran"},
    "maritalstatus": {"marital"},
    "statecode": {"state", "st"},
    "emailaddress": {"email", "emailaddr"},
}


def normalize(s):
    return re.sub(r"[^a-z0-9]", "", (s or "").strip().lower())


def _tokens(raw):
    """'Client_DOB' / 'ClientDOB' -> ['client', 'dob'] so an abbreviation
    embedded in a longer source field name (a very common real-world shape)
    still matches its alias, not just a bare 'DOB' with nothing else."""
    spaced = re.sub(r"(?<=[a-z0-9])(?=[A-Z])", "_", raw or "")
    return [normalize(p) for p in re.split(r"[^a-zA-Z0-9]+", spaced) if p]


def _contiguous_ngrams(tokens):
    """['enrollment','begin','date'] -> {'enrollment','begin','date',
    'enrollmentbegin','begindate','enrollmentbegindate'} — every contiguous
    run of source tokens, concatenated. Lets 'Enrollment_Begin_Date' match
    a target field literally named 'BeginDate' precisely, instead of losing
    to 'EnrollmentID' on raw character overlap from the shared table-name
    prefix."""
    grams = set()
    n = len(tokens)
    for i in range(n):
        for j in range(i + 1, n + 1):
            grams.add("".join(tokens[i:j]))
    return grams


def _name_score(field_name, candidate_field):
    source_norm = normalize(field_name)
    cand_norm = normalize(candidate_field)
    if not source_norm or not cand_norm:
        return 0.0, None
    if source_norm == cand_norm:
        return 1.0, "Exact field name match."

    tokens = _tokens(field_name)
    aliases = ALIASES.get(cand_norm, ())
    if source_norm in aliases or cand_norm in tokens or any(t in aliases for t in tokens):
        return 0.95, f"'{candidate_field}' is a recognized abbreviation/alias match."

    if len(cand_norm) >= 4 and len(tokens) > 1 and cand_norm in _contiguous_ngrams(tokens):
        return 0.93, f"'{candidate_field}' matches part of the source field name exactly."

    ratio = difflib.SequenceMatcher(None, source_norm, cand_norm).ratio()
    if len(source_norm) >= 4 and len(cand_norm) >= 4 and (source_norm in cand_norm or cand_norm in source_norm):
        ratio = max(ratio, 0.75)
    return ratio, None


def match(field_name, schema):
    """Score field_name against every candidate field in the schema.
    Returns None if nothing scores decently, else a suggestion dict shaped
    like llm_gateway.suggest_mapping's return value, plus "source": "rule"."""
    scored = []
    for row in schema:
        # Never suggest a column that isn't migrated. ServTracker's `Comments`
        # columns are scratch space for whoever fills the template in; routing a
        # customer's real data there would silently drop it on import.
        if row.get("notMigrated"):
            continue
        score, reason = _name_score(field_name, row["field"])
        if score >= 0.55:
            scored.append((score, reason, row))
    if not scored:
        return None

    scored.sort(key=lambda t: t[0], reverse=True)
    top_score, top_reason, top_row = scored[0]

    # Same field name can legitimately exist on multiple tables (ClientID,
    # CreatedDate, Restriction, ...) — surface that ambiguity instead of
    # silently picking one.
    tied = [r for s, _, r in scored if r["field"] == top_row["field"] and s >= top_score - 0.001]
    tied_tables = sorted({r["table"] for r in tied})

    # If the source name itself names one of the tied tables (e.g.
    # "Enrollment_Begin_Date" vs. BeginDate on Program/Enrollment/...),
    # prefer that one instead of whichever happened to sort first.
    source_tokens = set(_tokens(field_name))
    preferred = next((r for r in tied if normalize(r["table"]) in source_tokens), None)
    if preferred:
        top_row = preferred

    # A link key deliberately appears on every sheet -- that's its whole job, so
    # it is not an ambiguity to warn about. Treating it as one downgraded
    # ServTracker's ClientImportId to "medium" and appended a list of 31 other
    # sheets, which is both wrong and unreadable. Say what it's for instead.
    is_link_key = bool(top_row.get("linkKey"))

    if top_score >= 0.9:
        confidence = "high" if (len(tied_tables) == 1 or is_link_key) else "medium"
    elif top_score >= 0.75:
        confidence = "medium"
    else:
        confidence = "low"

    def label(row):
        return row.get("sheet") or row["table"]

    reasoning = top_reason or f"Field name closely resembles {label(top_row)}.{top_row['field']}."

    if is_link_key:
        reasoning += (
            f" {top_row['field']} is the key the import uses to link a client across every "
            f"sheet — use the same value for the same client everywhere."
        )
    else:
        others = [t for t in tied_tables if t != top_row["table"]]
        if others:
            shown = ", ".join(others[:4])
            more = f" and {len(others) - 4} more" if len(others) > 4 else ""
            reasoning += (
                f" Note: {top_row['field']} also exists on {shown}{more} — verify the right one."
            )

    return {
        "table": top_row["table"],
        "field": top_row["field"],
        "sheet": top_row.get("sheet"),
        "confidence": confidence,
        "reasoning": reasoning,
        "source": "rule",
        "linkKey": is_link_key,
    }
