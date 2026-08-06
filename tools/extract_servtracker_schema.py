"""
Extract the ServTracker target ETL schema from its two authoritative sources
and emit reference/servtracker_schema_full.json plus a disagreement report.

Run:
    python tools/extract_servtracker_schema.py \
        --templates "<...>/12. ServTracker/ExcelTemplates/Master Templates" \
        --validation "<...>/12. ServTracker/Master Scripts/1 - Master Validation.sql"

Both source paths default to the OneDrive locations they were first extracted
from (see reference/SERVTRACKER_SOURCES.md). Those sources are *live,
maintained documents* and are deliberately NOT copied into this repo -- doing
so would fork a source of truth that someone else is still editing. Instead
this script records each source's SHA-256 in the output, so drift between the
committed schema and the current sources is detectable by re-running it.

Why two sources, and why a disagreement report instead of a single answer:

  * The Excel templates define what columns a customer is actually handed --
    the authoritative *field list*, in order, per sheet.
  * The validation script defines the *rules* those columns must satisfy
    (required, max length, uniqueness, type, allowed values, FK existence).

Neither alone is sufficient, and where they disagree that is a real finding
about the sources -- template/script drift -- not something this script should
paper over by guessing. Every disagreement is reported for human adjudication
(Alex Button owns ServTracker schema sign-off) and nothing is invented to fill
a gap. This mirrors the rule in docs/PHASE_PLAN.md section 2: we never
fabricate a target rule we haven't sourced.

Pure standard library, including the .xlsx reader -- consistent with the POC's
no-pip-install constraint, so this stays runnable as a maintenance task.
"""

import argparse
import collections
import hashlib
import json
import os
import re
import sys
import zipfile
import xml.etree.ElementTree as ET

NS = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"
RELID = "{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id"

DEFAULT_ST_ROOT = os.path.join(
    os.path.expanduser("~"), "OneDrive - CaseWorthy", "ETL Team", "12. ServTracker"
)
DEFAULT_TEMPLATES = os.path.join(DEFAULT_ST_ROOT, "ExcelTemplates", "Master Templates")
DEFAULT_VALIDATION = os.path.join(DEFAULT_ST_ROOT, "Master Scripts", "1 - Master Validation.sql")

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_SCHEMA = os.path.join(REPO_ROOT, "reference", "servtracker_schema_full.json")
OUT_REPORT = os.path.join(REPO_ROOT, "reference", "servtracker_extraction_report.md")

# Templates carry a scratch column for whoever fills the sheet in to leave
# themselves notes. It is not validated, not imported, and not migrated.
#
# The two spellings were rationalised across every template and both scripts by
# Alex Button on 2026-08-05, so the distinction is now carried by the name alone:
#
#   Comments (plural)   -- scratch space, never migrated
#   Comment  (singular)  -- a real field, validated and imported
#
# Verified against all three sources before adopting: 34 of 35 sheets put the
# scratch column first, every `Comment` is validated, and the import script
# reads `i.Comment`. Position is no longer the rule but is still cross-checked,
# because a sheet that puts the *migrated* column first is a trap for anyone
# used to the other 34 -- see the report's column-order section.
#
# Flagged rather than dropped, so the sheet listing can say what the column is
# for; excluded as a mapping candidate, since offering a destination that is
# never migrated would quietly lose the customer's data.
NOTES_COLUMN_NAME = "comments"
NOTES_COLUMN_NOTE = (
    "Free space for your own notes while filling in this template — not validated, "
    "tracked, or migrated into ServTracker."
)

NON_FIELD_COLUMNS = {""}

# Templates whose scripting is out of date and must not be offered. Adjudicated
# by Alex Button (ServTracker schema owner) on 2026-08-05. Listed explicitly
# rather than silently dropped so the exclusion is reviewable, and reported in
# the output so it can never look like an extraction gap.
EXCLUDED_TEMPLATES = {
    "ServTracker - Adult DayCare.xlsx":
        "Scripting badly out of date; the module should not be offered. The script's "
        "'Day Care Intake'/'Day Care Schedule' renames no longer match the template's "
        "'ADC Service Schedules'/'ADC Notes' sheets.",
    "ServTracker - Home Delivered Meal Choice - optional.xlsx":
        "Template and validation scripting out of date. Only the base "
        "'ServTracker - Home Delivered.xlsx' should be used.",
}

# The key the import uses to link a client across every sheet, and the column
# that only applies when updating clients who already exist in ServTracker.
# See `2 - Master Import.sql` (the #STConfiguration OverwriteClient block).
LINK_KEY_FIELD = "ClientImportId"
MERGE_ONLY_FIELD = "ServTrackerClientId"

# Words that appear where an allowed value would sit but describe a *type*, not
# a value ("must be numeric or left blank"). Never treat these as decode values.
NON_VALUE_WORDS = {
    "numeric", "number", "left blank", "blank", "a number", "a date", "date",
    "null", "empty", "a day of week", "required",
}


# --------------------------------------------------------------------------
# .xlsx reading (stdlib: an xlsx is a zip of XML)
# --------------------------------------------------------------------------

def _col_index(ref):
    m = re.match(r"([A-Z]+)", ref or "")
    if not m:
        return 0
    n = 0
    for ch in m.group(1):
        n = n * 26 + (ord(ch) - 64)
    return n - 1


def read_sheet_headers(path):
    """{sheet name: [column names in order]} for one workbook, from row 1."""
    z = zipfile.ZipFile(path)
    names = z.namelist()

    shared = []
    if "xl/sharedStrings.xml" in names:
        for si in ET.fromstring(z.read("xl/sharedStrings.xml")).findall(NS + "si"):
            shared.append("".join(t.text or "" for t in si.iter(NS + "t")))

    wb = ET.fromstring(z.read("xl/workbook.xml"))
    rel_map = {
        r.get("Id"): r.get("Target")
        for r in ET.fromstring(z.read("xl/_rels/workbook.xml.rels"))
    }

    out = collections.OrderedDict()
    for sh in wb.find(NS + "sheets"):
        target = rel_map.get(sh.get(RELID), "") or ""
        target = target if target.startswith("xl/") else "xl/" + target.lstrip("/")
        if target not in names:
            continue
        data = ET.fromstring(z.read(target)).find(NS + "sheetData")
        if data is None or len(data) == 0:
            out[sh.get("name")] = []
            continue

        cells = {}
        for c in data[0].findall(NS + "c"):
            v = c.find(NS + "v")
            inline = c.find(NS + "is")
            if c.get("t") == "s" and v is not None and v.text is not None:
                idx = int(v.text)
                val = shared[idx] if idx < len(shared) else ""
            elif inline is not None:
                val = "".join(t.text or "" for t in inline.iter(NS + "t"))
            else:
                val = (v.text if v is not None else "") or ""
            if val.strip():
                cells[_col_index(c.get("r"))] = val.strip()

        ordered = [cells[i] for i in sorted(cells)]
        out[sh.get("name")] = [c for c in ordered if c.lower() not in NON_FIELD_COLUMNS]
    return out


def load_templates(templates_dir):
    """{sheet: {"columns": [...], "workbooks": [...]}} across every template."""
    sheets = collections.OrderedDict()
    conflicts = []
    all_files = sorted(f for f in os.listdir(templates_dir) if f.lower().endswith(".xlsx"))
    files = [f for f in all_files if f not in EXCLUDED_TEMPLATES]
    excluded = [f for f in all_files if f in EXCLUDED_TEMPLATES]
    for fname in files:
        for sheet, cols in read_sheet_headers(os.path.join(templates_dir, fname)).items():
            if sheet in sheets:
                # Same sheet in two workbooks (e.g. HDM Main ships in both the
                # base and the Meal-Choice template). Identical is fine and
                # expected; differing structure is a genuine conflict.
                if sheets[sheet]["columns"] != cols:
                    conflicts.append(
                        {
                            "sheet": sheet,
                            "workbookA": sheets[sheet]["workbooks"][0],
                            "columnsA": sheets[sheet]["columns"],
                            "workbookB": fname,
                            "columnsB": cols,
                        }
                    )
                sheets[sheet]["workbooks"].append(fname)
            else:
                sheets[sheet] = {"columns": cols, "workbooks": [fname]}
    return sheets, files, conflicts, excluded


# --------------------------------------------------------------------------
# Validation-script parsing
# --------------------------------------------------------------------------

RENAME_RE = re.compile(r"sp_rename\s*'([^']+)'\s*,\s*'([^']+)'", re.I)
CHECK_SPLIT_RE = re.compile(r"insert\s+into\s+dbo\.\[?ErrorLog\]?", re.I)
FROM_RE = re.compile(r"\bfrom\s+(?:dbo\.)?\[?(\w+)\]?", re.I)
NOT_IN_RE = re.compile(r"\bnot\s+in\s*\(([^)]*)\)", re.I)
# Alias is optional: value lookups are written `left join Race r on ...` but FK
# existence checks are written `LEFT JOIN CliMas ON ...` with no alias at all.
LOOKUP_JOIN_RE = re.compile(r"\bjoin\s+(?:dbo\.)?\[?(\w+)\]?(?:\s+(?!on\b)\w+)?\s+on\b", re.I)
QUOTED_RE = re.compile(r"'((?:[^']|'')*)'")


def strip_sql_comments(text):
    """Blank out `--` line comments and `/* */` blocks, preserving length.

    Retired checks are left in the script as commented-out code rather than
    deleted -- the whole `CaseManagersImport` block, for one. Parsing those
    yields rules for tables that no longer exist, invents rename ambiguities
    where only one live rename remains, and lets a commented-out entry inside a
    live `NOT IN (...)` list look like a rejected value. Dead code is not a
    source of truth, so it goes before anything else reads the script.

    Offsets and newlines are preserved so downstream slicing stays valid.
    Quote state is tracked so a `--` inside an error message survives, and
    block-comment nesting is counted the way T-SQL allows.
    """
    out = list(text)
    i, n = 0, len(text)
    in_str = False
    depth = 0
    while i < n:
        ch = text[i]
        nxt = text[i + 1] if i + 1 < n else ""
        if depth:
            if ch == "/" and nxt == "*":
                depth += 1
                out[i] = out[i + 1] = " "
                i += 2
                continue
            if ch == "*" and nxt == "/":
                depth -= 1
                out[i] = out[i + 1] = " "
                i += 2
                continue
            if ch != "\n":
                out[i] = " "
        elif in_str:
            if ch == "'":
                in_str = False
        elif ch == "'":
            in_str = True
        elif ch == "-" and nxt == "-":
            while i < n and text[i] != "\n":
                out[i] = " "
                i += 1
            continue
        elif ch == "/" and nxt == "*":
            depth = 1
            out[i] = out[i + 1] = " "
            i += 2
            continue
        i += 1
    return "".join(out)


def _norm(s):
    return re.sub(r"[^a-z0-9]", "", (s or "").lower())


def parse_renames(sql):
    """Sheet name -> import table name(s). 1:many is a real ambiguity, kept."""
    mapping = collections.OrderedDict()
    for sheet, table in RENAME_RE.findall(sql):
        mapping.setdefault(sheet, [])
        if table not in mapping[sheet]:
            mapping[sheet].append(table)
    return mapping


def _rule_from_message(msg, where, joins=""):
    """Turn one ErrorLog message (+ its WHERE clause and joins) into schema facts.

    The script states each rule in plain English in the message itself, which
    is what makes this mechanical rather than interpretive. Allowed-value sets
    come from the message when it enumerates them, otherwise from a NOT IN
    list, otherwise from a named lookup table we can only point at by name.
    """
    facts = {}
    low = msg.lower()

    if "is required" in low or "is missing" in low:
        facts["required"] = True
    if "must be unique" in low:
        facts["unique"] = True

    # Length is phrased four different ways across the script, and 16 checks
    # only say "is too long" without a number at all -- for those the limit is
    # in the WHERE clause's `len(col) > N`. Missing any of these variants drops
    # a real constraint silently, so all of them are handled.
    for pat in (
        r"max length is (\d+) (?:character|digit)s?",
        r"max(?:imum)? (\d+) characters?",
        r"(\d+) characters? max",
        r"is (\d+) characters? long",
    ):
        m = re.search(pat, low)
        if m:
            facts["maxLength"] = int(m.group(1))
            break
    else:
        if "too long" in low:
            m = re.search(r"len\s*\(\s*\[?\w+\]?\s*\)\s*>\s*(\d+)", where or "", re.I)
            if m:
                facts["maxLength"] = int(m.group(1))

    if (
        "must be numeric" in low
        or "must be a number" in low
        or "is not numeric" in low
        or "numeric values only" in low
        or "not a valid integer" in low
        or "must be greater than" in low
        or "must be number" in low
        or "must be a valid number" in low
    ):
        facts["numeric"] = True
    if "not a valid date" in low or "is not a date" in low or "must be a date" in low \
            or "must be a valid date" in low:
        facts["date"] = True
    if "not a valid time" in low or "must be a valid time" in low:
        facts["time"] = True

    # Allowed values enumerated in the message itself. Skipped entirely for
    # numeric/date rules: "must be numeric or left blank" is a type rule, and
    # reading it as an allowed-value list of {numeric, left blank} would invent
    # a constraint the script never states.
    if not (facts.get("numeric") or facts.get("date") or facts.get("time")):
        m = re.search(r"allowed values:\s*(.+?)\.?$", msg, re.I) or re.search(
            r"must be\s+((?:[A-Za-z][\w\- ]*)(?:\s*,\s*[\w\- ]+)*(?:\s+or\s+[\w\- ]+)?)\.?$", msg, re.I
        )
        if m:
            vals = [v for v in _split_values(m.group(1)) if v.lower() not in NON_VALUE_WORDS]
            vals = _dedupe_values(vals)
            if len(vals) > 1:
                facts["decodeValues"] = vals

    # Otherwise a NOT IN (...) list in the WHERE clause is the allowed set --
    # unless it's a subquery, in which case the values are rows in another table
    # (e.g. `NOT IN (SELECT [CDESC] FROM [dbo].[Can] WHERE [ENABLED] = 1)`) and
    # only the table can be named here, not the values.
    # Structural, not phrase-gated. These checks insert an error *when the WHERE
    # clause is true*, so `col NOT IN (<literals>)` means exactly "error unless
    # the value is one of these" -- an allowed-value list, whatever the message
    # happens to say. Gating on wording ("not a valid value" / "is invalid")
    # dropped real lists whose message was phrased differently: PercentOfPoverty
    # states 12 allowed ranges but its message reads "Invalid Percent of Poverty
    # Range", which contains neither phrase.
    if "decodeValues" not in facts:
        m = NOT_IN_RE.search(where or "")
        if m:
            inner = m.group(1)
            if re.search(r"\bselect\b", inner, re.I):
                sub = re.search(r"\bfrom\s+(?:\[?dbo\]?\.)?\[?(\w+)\]?", inner, re.I)
                if sub:
                    facts["lookupTable"] = sub.group(1)
            else:
                vals = [v.strip().strip("'").strip() for v in inner.split(",")]
                vals = _dedupe_values([v for v in vals if v])
                if vals:
                    facts["decodeValues"] = vals

    # Otherwise it's validated against a ServTracker lookup table -- we can
    # name the table but the values live in the database, not the script.
    # The join sits in the FROM clause, ahead of WHERE, so search both.
    # Same reasoning, one step weaker: a join to a lookup table plus an
    # `<alias>.<col> IS NULL` test in the WHERE is the "no matching row" idiom,
    # i.e. the value must exist in that table. Still requires some hint that the
    # check is about validity, since joins are also used for plain FK existence.
    if "decodeValues" not in facts and (
        "not a valid" in low or "invalid" in low or "not in database" in low
    ):
        m = LOOKUP_JOIN_RE.search(joins or "") or LOOKUP_JOIN_RE.search(where or "")
        if m:
            facts["lookupTable"] = m.group(1)

    # "... is not in Client Master sheet" is a cross-*sheet* dependency, not a
    # database FK: the client must already appear on the client sheet. Kept
    # separate so it can be resolved to an import table name in merge() --
    # schema_rules.fk_target_table only warns when the FK target matches a table
    # that's actually in the schema, and a sheet name never would.
    m = re.search(r"is not in (?:the )?([A-Za-z ]+?) sheet", msg, re.I)
    if m:
        facts["crossSheetRef"] = m.group(1).strip()

    if "could not be found in database" in low or "does not exist" in low:
        m = LOOKUP_JOIN_RE.search(joins or "") or LOOKUP_JOIN_RE.search(where or "")
        facts["fkLookup"] = m.group(1) if m else True

    return facts


def _dedupe_values(vals):
    """Collapse values that differ only by case, keeping the first spelling.

    SQL Server compares these case-insensitively under the default collation, so
    a list of YES/NO/Yes/No enforces exactly two values, not four. Confirmed as
    a non-issue by Alex Button on 2026-08-05; collapsing keeps the UI honest
    about how many options a customer really has.
    """
    out, seen = [], set()
    for v in vals:
        if v.lower() not in seen:
            seen.add(v.lower())
            out.append(v)
    return out


def _split_values(blob):
    blob = re.sub(r"\bor\b", ",", blob, flags=re.I)
    return [v.strip(" .\"'") for v in blob.split(",") if v.strip(" .\"'")]


def _mask_literals(text):
    """Blank out the contents of quoted strings, preserving length and offsets.

    SQL keywords must be located outside string literals: one error message
    reads "Enter an option from the End Reason Option sheet", and matching that
    inner `from` truncates the SELECT list and loses the whole rule. Offsets are
    preserved so a match found in the masked text slices the original correctly.
    """
    out = list(text)
    in_str = False
    for i, ch in enumerate(text):
        if ch == "'":
            in_str = not in_str
        elif in_str:
            out[i] = " "
    return "".join(out)


def parse_checks(sql):
    """[{table, field, message, where, facts}] -- one entry per ErrorLog check."""
    checks = []
    unparsed = []
    for chunk in CHECK_SPLIT_RE.split(sql)[1:]:
        # Trim the chunk at the start of the next statement so a WHERE clause
        # doesn't swallow unrelated SQL that follows it.
        masked_chunk = _mask_literals(chunk)
        stop = re.search(r"\n\s*(?:IF\s+EXISTS|BEGIN\b|END\b|DROP\b|EXEC\b|GO\b|--=)", masked_chunk)
        body = chunk[: stop.start()] if stop else chunk
        masked = masked_chunk[: stop.start()] if stop else masked_chunk

        fm = FROM_RE.search(masked)
        # Literals must come from the SELECT list only. The script puts `from`
        # at the start of its own line, so a plain `" from "` split misses it
        # and drags WHERE-clause values (e.g. `not in ('Y','N')`) into the
        # literal list -- which silently made the last one look like the error
        # message and dropped the rule entirely.
        select_part = body[: fm.start()] if fm else body
        literals = [l.replace("''", "'") for l in QUOTED_RE.findall(select_part)]
        if not fm or len(literals) < 3:
            snippet = " ".join(body.split())[:130]
            if snippet:
                unparsed.append(snippet)
            continue

        wm = re.search(r"\bwhere\b", masked, re.I)
        where = body[wm.end():] if wm else ""
        # FROM..JOIN region, i.e. everything between `from` and `where`.
        joins = body[fm.start(): wm.start()] if wm else body[fm.start():]

        message = literals[-1]
        declared = literals[1]

        # The ErrorLog row carries both a FieldName *label* and the FieldValue
        # *expression* actually being tested. Where they disagree the expression
        # wins: the label is a hand-maintained string that has been copy-pasted
        # wrong in places (e.g. a `Site` length check labelled `ClientImportId`,
        # which otherwise lands a bogus max-50 rule on the link key). Only a
        # plain column reference is trusted; anything else falls back to the
        # label and the disagreement is reported.
        # Start from the *second* literal by position, not by splitting on its
        # text. ImportType and FieldName are sometimes the same string -- the
        # HomecareTasks checks read
        #   select 'HomecareTasks', ClientImportId, 'HomecareTasks', [HomecareTasks], ...
        # -- so splitting on the name matched the ImportType occurrence and read
        # ErrorLog's ClientImportId column as the tested field, reporting a
        # mismatch in a check that is perfectly correct.
        tested = None
        spans = list(QUOTED_RE.finditer(select_part))
        if len(spans) >= 2:
            vm = re.match(
                r"\s*,\s*\[([^\]]+)\]\s*,|\s*,\s*(\w+)\s*,", select_part[spans[1].end():]
            )
            if vm:
                tested = vm.group(1) or vm.group(2)

        # Three signals name the field: the label, the tested expression, and
        # the message text. They disagree in both directions -- a `Site` length
        # check labelled `ClientImportId`, and a `HomecareTasks` check that
        # tests `ClientImportId` -- so neither label nor expression can simply
        # win. The message is the tiebreaker: whichever of the two it actually
        # talks about is the one the rule is for. `merge()` makes the final call
        # using the template column list, the real authority on field names.
        field, alt = (tested or declared), None
        mismatch = None
        if tested and _norm(tested) != _norm(declared):
            # Whole-word, not substring: `Comment` is a substring of `Comments`,
            # so a plain `in` test says the message mentions both and the
            # tiebreaker collapses. Messages spell field names either joined
            # (`ClientImportId`) or spaced (`Client Import Id`), so compare
            # against the message with separators stripped *and* against its
            # individual words.
            words = {_norm(w) for w in re.findall(r"[A-Za-z]+", message)}
            joined = _norm(message)

            def named(cand):
                n = _norm(cand)
                if n in words:
                    return True
                # joined spelling: require the run to not be a prefix of a
                # longer word, which is what made Comment match Comments.
                return bool(re.search(n + r"(?![a-z0-9])", joined))

            in_msg_declared = named(declared)
            in_msg_tested = named(tested)
            if in_msg_declared and not in_msg_tested:
                field, alt = declared, tested
            else:
                field, alt = tested, declared
            mismatch = {
                "declared": declared, "tested": tested, "message": message,
                "table": fm.group(1), "used": field,
            }

        # Fourth signal, used only for length rules: the column inside
        # `len(...)` in the WHERE clause is what the constraint actually applies
        # to. One check has all three of label, value expression and message
        # saying `Comment` while the WHERE tests `len([Comments])` -- and the
        # `--Comments` header above it agrees the WHERE is right. Narrow by
        # design: it fires on exactly this one check out of 785.
        lens = set(re.findall(r"len\s*\(\s*\[?(\w+)\]?\s*\)", where or "", re.I))
        if len(lens) == 1 and "too long" in message.lower():
            len_col = lens.pop()
            if _norm(len_col) != _norm(field):
                mismatch = {
                    "declared": declared, "tested": len_col, "message": message,
                    "table": fm.group(1), "used": len_col,
                }
                field, alt = len_col, field

        checks.append(
            {
                "importType": literals[0],
                "table": fm.group(1),
                "field": field,
                "altField": alt,
                "declaredField": declared,
                "fieldNameMismatch": mismatch,
                "message": message,
                "where": " ".join(where.split()),
                "facts": _rule_from_message(message, where, joins),
            }
        )
    return checks, unparsed


# --------------------------------------------------------------------------
# Merge into schema rows
# --------------------------------------------------------------------------

def build_type(facts):
    """Render a type string in the exact vocabulary poc/schema_rules.py parses.

    This is a contract, not a free-text field: the rule engine regex-matches
    "Text (max N)" / "List" / "FK -> X" and silently no-ops on anything it
    doesn't recognise. See reference/SCHEMA_FORMAT.md.
    """
    if facts.get("fkLookup"):
        tgt = facts["fkLookup"]
        return "FK → %s" % tgt if isinstance(tgt, str) else "FK"
    if facts.get("decodeValues") or facts.get("lookupTable"):
        return "List"
    if facts.get("date"):
        return "Date"
    if facts.get("time"):
        return "Time"
    if facts.get("numeric"):
        return "Numeric"
    if facts.get("maxLength"):
        return "Text (max %d)" % facts["maxLength"]
    if facts.get("unique"):
        return "Unique ID"
    return "Text"


def merge(templates, renames, checks):
    """Fold per-check facts onto the template-defined column list."""
    sheet_for_table = {}
    for sheet, tables in renames.items():
        for t in tables:
            sheet_for_table.setdefault(t.lower(), []).append(sheet)

    # Accumulate facts per (import table, normalised field name).
    facts_by = collections.defaultdict(dict)
    alt_by = collections.defaultdict(dict)
    msgs_by = collections.defaultdict(list)
    length_conflicts = collections.defaultdict(set)
    for c in checks:
        key = (c["table"].lower(), re.sub(r"[^a-z0-9]", "", c["field"].lower()))
        for k, v in c["facts"].items():
            if k == "maxLength":
                prev = facts_by[key].get(k)
                # Two different stated max lengths for one field is a conflict in
                # the script, not something to average away. Keep the stricter
                # value so the tool never under-warns, but record both so it can
                # be adjudicated rather than silently hidden.
                if prev and prev != v:
                    length_conflicts[key].update([prev, v])
                facts_by[key][k] = min(prev, v) if prev else v
            elif k == "decodeValues":
                merged = facts_by[key].get(k) or []
                for val in v:
                    if val not in merged:
                        merged.append(val)
                facts_by[key][k] = merged
            else:
                facts_by[key][k] = v
        msgs_by[key].append(c["message"])
        # Secondary index under the rejected candidate name, so a template column
        # that matches only that spelling can still find its rule.
        if c.get("altField"):
            alt_by[(c["table"].lower(), _norm(c["altField"]))].update(c["facts"])

    # Sheet name (and workbook name) -> import table, for resolving cross-sheet
    # references like "is not in Client Master sheet" onto a real table name.
    sheet_to_table = {}
    for sheet, tables in renames.items():
        if tables:
            sheet_to_table[_norm(sheet)] = tables[0]
    for sheet, info in templates.items():
        for wb in info["workbooks"]:
            stem = _norm(os.path.splitext(wb)[0].replace("ServTracker - ", ""))
            sheet_to_table.setdefault(stem, (renames.get(sheet) or [sheet])[0])

    def _resolve_sheet_ref(ref):
        n = _norm(ref)
        if n in sheet_to_table:
            return sheet_to_table[n]
        for key, tbl in sheet_to_table.items():
            if n and (n in key or key in n):
                return tbl
        return None

    rows = []
    matched_keys = set()
    cross_conflicts = {}
    notes_with_rules = []
    notes_misplaced = []
    unresolved_refs = set()
    for sheet, info in templates.items():
        tables = renames.get(sheet) or []
        for col_index, col in enumerate(info["columns"]):
            norm = re.sub(r"[^a-z0-9]", "", col.lower())
            facts, used_table = {}, None
            seen_lengths = set()
            for t in tables:
                k = (t.lower(), norm)
                if k not in facts_by and k in alt_by:
                    facts = dict(alt_by[k], **facts) if facts else dict(alt_by[k])
                    used_table = t
                    continue
                if k in facts_by:
                    if facts_by[k].get("maxLength"):
                        seen_lengths.add(facts_by[k]["maxLength"])
                    facts = dict(facts_by[k], **facts) if facts else dict(facts_by[k])
                    used_table = t
                    matched_keys.add(k)
            # A sheet renamed to two import tables can carry a different stated
            # length in each -- a conflict that isn't visible per-table.
            if len(seen_lengths) > 1:
                facts["maxLength"] = min(seen_lengths)
            if facts.get("crossSheetRef") and not facts.get("fkLookup"):
                tgt = _resolve_sheet_ref(facts["crossSheetRef"])
                if tgt:
                    facts["fkLookup"] = tgt
                else:
                    unresolved_refs.add(facts["crossSheetRef"])

            row = {
                "sheet": sheet,
                "table": tables[0] if tables else sheet,
                "field": col,
                "required": bool(facts.get("required", False)),
                "type": build_type(facts),
                "modules": sorted(
                    os.path.splitext(w)[0].replace("ServTracker - ", "")
                    for w in info["workbooks"]
                ),
                "validated": bool(facts),
            }
            if facts.get("decodeValues"):
                row["decodeValues"] = facts["decodeValues"]
                row["decode"] = ", ".join(facts["decodeValues"])
            if facts.get("lookupTable"):
                row["lookupTable"] = facts["lookupTable"]
            if facts.get("crossSheetRef"):
                row["crossSheetRef"] = facts["crossSheetRef"]
            if facts.get("unique"):
                row["unique"] = True
            # `Comments` (plural) is the template's scratch column by the
            # rationalised naming convention. A rule found on one would mean the
            # convention has drifted, so that is reported rather than assumed.
            if norm == NOTES_COLUMN_NAME:
                row["notesColumn"] = True
                row["notMigrated"] = True
                row["note"] = NOTES_COLUMN_NOTE
                if facts:
                    notes_with_rules.append({"sheet": sheet, "field": col})
                if col_index != 0:
                    notes_misplaced.append({"sheet": sheet, "field": col, "index": col_index})
            elif norm == "comment" and col_index == 0:
                # Inverse trap: the *migrated* column sitting where every other
                # sheet puts scratch space.
                notes_misplaced.append({"sheet": sheet, "field": col, "index": col_index,
                                        "migratedFirst": True})

            if col == LINK_KEY_FIELD:
                row["linkKey"] = True
                row["note"] = (
                    "The key the import uses to link this client across every sheet. Use the "
                    "same value for a client in all sheets you submit."
                )
            elif col == MERGE_ONLY_FIELD:
                row["mergeOnly"] = True
                row["note"] = (
                    "Only needed when updating clients who already exist in the ServTracker "
                    "database. Leave blank for new clients — use %s to link instead."
                    % LINK_KEY_FIELD
                )
            if used_table and used_table != row["table"]:
                row["ruleSourceTable"] = used_table
            conf = set(seen_lengths) if len(seen_lengths) > 1 else set()
            for t in tables:
                conf |= length_conflicts.get((t.lower(), norm)) or set()
            if conf:
                row["maxLengthConflict"] = sorted(conf)
                cross_conflicts[(sheet, col)] = sorted(conf)
            rows.append(row)

    orphans = [
        {"table": t, "field": f, "messages": sorted(set(msgs_by[(t, f)]))[:3]}
        for (t, f) in sorted(facts_by)
        if (t, f) not in matched_keys
    ]
    return rows, orphans, sheet_for_table, cross_conflicts, notes_with_rules, notes_misplaced


# --------------------------------------------------------------------------
# Report
# --------------------------------------------------------------------------

def find_source_anomalies(rows):
    """Flag allowed-value sets that look like defects in the validation script.

    These are findings about the *source*, not extraction problems -- the script
    is the authority, so we report rather than silently correct. Each one would
    cause the live import to reject data a reader would expect it to accept.
    """
    out = []
    seen = set()
    for r in rows:
        vals = r.get("decodeValues")
        if not vals:
            continue
        key = (r["sheet"], r["field"], tuple(vals))
        if key in seen:
            continue
        seen.add(key)
        where = "`%s`.`%s`" % (r["sheet"], r["field"])

        # A SQL comment marker inside a value means a commented-out entry leaked
        # into the NOT IN list, so that value is currently rejected.
        leaked = [v for v in vals if "--" in v or "\t" in v]
        if leaked:
            out.append((where, "commented-out value leaked into the allowed list, so it is currently **rejected**", leaked))

        # Letter/digit confusion: a value carrying a digit while its siblings are
        # pure letters (e.g. 'N0' beside 'Yes' -- N-zero, not N-o).
        alpha = [v for v in vals if v.isalpha()]
        odd = [v for v in vals if re.search(r"[0-9]", v) and re.search(r"[A-Za-z]", v) and len(v) <= 4]
        if odd and alpha:
            out.append((where, "likely letter/digit typo -- would reject the intended value", odd))

        # Same value spelled at two different cases in one list is harmless but
        # signals the list was edited by hand and may be incomplete.
        lowered = collections.Counter(v.lower() for v in vals)
        dupes = [v for v, n in lowered.items() if n > 1]
        if dupes:
            out.append((where, "same value listed at more than one casing", sorted(
                v for v in vals if v.lower() in dupes)))
    return out


def sha256(path):
    """Content hash of a file, or of a directory's *.xlsx set (name + bytes of
    each, in sorted order) so a changed template is detectable either way."""
    h = hashlib.sha256()
    if os.path.isdir(path):
        for name in sorted(f for f in os.listdir(path) if f.lower().endswith(".xlsx")):
            h.update(name.encode("utf-8"))
            with open(os.path.join(path, name), "rb") as f:
                for block in iter(lambda: f.read(65536), b""):
                    h.update(block)
    else:
        with open(path, "rb") as f:
            for block in iter(lambda: f.read(65536), b""):
                h.update(block)
    return h.hexdigest()


def write_report(path, rows, orphans, templates, renames, conflicts, unparsed, checks, sources,
                 length_conflicts, excluded, notes_with_rules, notes_misplaced):
    link_key_sheets = [s for s, i in templates.items() if any(
        re.sub(r"[^a-z0-9]", "", c.lower()) == "clientimportid" for c in i["columns"])]
    unvalidated = [r for r in rows if not r["validated"]]
    no_rename = [s for s in templates if s not in renames]
    rename_only = [s for s in renames if s not in templates]
    multi_table = {s: t for s, t in renames.items() if len(t) > 1}
    collisions = collections.defaultdict(set)
    for r in rows:
        collisions[r["field"]].add(r["sheet"])
    repeated = sorted(((len(v), k) for k, v in collisions.items() if len(v) > 1), reverse=True)

    L = []
    L.append("# ServTracker schema extraction report\n")
    L.append("Generated by `tools/extract_servtracker_schema.py`. **Not yet signed off.**")
    L.append("ServTracker schema sign-off owner: Alex Button (the CaseWorthy equivalent is")
    L.append("Russ, who confirmed `target_schema_full.json` on 2026-08-04).\n")
    L.append("## Sources\n")
    for label, p in sources:
        L.append("- **%s** — `%s`" % (label, p))
        L.append("  - SHA-256 `%s`" % sha256(p))
    L.append("")
    L.append("Sources are live maintained documents, deliberately not copied into this repo.")
    L.append("Re-run the extractor to detect drift against these hashes.\n")

    L.append("## Totals\n")
    L.append("| | Count |")
    L.append("|---|---|")
    L.append("| Templates (workbooks) | %d |" % len({w for i in templates.values() for w in i["workbooks"]}))
    L.append("| Sheets | %d |" % len(templates))
    L.append("| Fields extracted | %d |" % len(rows))
    L.append("| Validation checks parsed | %d |" % len(checks))
    L.append("| Fields with >=1 rule | %d |" % (len(rows) - len(unvalidated)))
    L.append("| Fields with no rule (treated as optional) | %d |" % len(unvalidated))
    L.append("| Required fields | %d |" % sum(1 for r in rows if r["required"]))
    L.append("| Fields with an allowed-value list | %d |" % sum(1 for r in rows if r.get("decodeValues")))
    L.append("| Fields validated against a lookup table | %d |" % sum(1 for r in rows if r.get("lookupTable")))
    L.append("")

    L.append("## Templates deliberately excluded\n")
    if excluded:
        L.append("Not extracted, by decision rather than oversight. Listed here so an")
        L.append("absent module never looks like a coverage gap.\n")
        for f in excluded:
            L.append("- **%s** — %s" % (f, EXCLUDED_TEMPLATES[f]))
    else:
        L.append("_None._")
    L.append("")

    L.append("## Needs adjudication\n")
    L.append("Each item below is a disagreement between the two sources, or an")
    L.append("ambiguity in one of them. Nothing here was guessed at or filled in.\n")

    L.append("### Sheets renamed to more than one import table\n")
    if multi_table:
        L.append("The validation script renames one sheet to two different import tables,")
        L.append("so which is current can't be determined from the script alone.\n")
        for s, t in multi_table.items():
            L.append("- `%s` -> %s" % (s, ", ".join("`%s`" % x for x in t)))
    else:
        L.append("_None._")
    L.append("")

    L.append("### Template sheets with no `sp_rename` in the validation script\n")
    if no_rename:
        L.append("These sheets ship to customers but the script never renames them to an")
        L.append("import table, so no rules were found for their columns.\n")
        for s in no_rename:
            L.append("- `%s` (%d columns) — in %s" % (
                s, len(templates[s]["columns"]), ", ".join(templates[s]["workbooks"])))
    else:
        L.append("_None._")
    L.append("")

    L.append("### `sp_rename` sheet names with no matching template sheet\n")
    if rename_only:
        L.append("The script expects these sheet names, but no master template provides one.")
        L.append("Likely renamed sheets or retired modules.\n")
        for s in rename_only:
            L.append("- `%s` -> %s" % (s, ", ".join("`%s`" % x for x in renames[s])))
    else:
        L.append("_None._")
    L.append("")

    L.append("### Validation rules for fields in no template — excluded by policy\n")
    if orphans:
        L.append("The script validates these columns but no template offers them. **Resolved,")
        L.append("not open:** the templates are the primary source of what data we offer to")
        L.append("migrate (Alex Button, 2026-08-05), so these rules are deliberately excluded")
        L.append("from the schema. Listed for visibility — a column showing up here means the")
        L.append("script still validates something customers are never asked for.\n")
        L.append("| Import table | Field | Example message |")
        L.append("|---|---|---|")
        for o in orphans[:60]:
            L.append("| `%s` | `%s` | %s |" % (o["table"], o["field"], (o["messages"] or [""])[0][:80]))
        if len(orphans) > 60:
            L.append("")
            L.append("_...and %d more._" % (len(orphans) - 60))
    else:
        L.append("_None._")
    L.append("")

    L.append("### Same sheet with differing columns across workbooks\n")
    if conflicts:
        for c in conflicts:
            L.append("- `%s`: `%s` vs `%s`" % (c["sheet"], c["workbookA"], c["workbookB"]))
    else:
        L.append("_None — sheets duplicated across workbooks are structurally identical._")
    L.append("")

    L.append("### Scratch-column convention\n")
    L.append("`Comments` (plural) is scratch space for whoever fills the sheet in and is never")
    L.append("migrated; `Comment` (singular) is a real validated, imported field. Both are kept")
    L.append("in the schema — the scratch column flagged `notesColumn` so the UI can say what")
    L.append("it's for, and excluded as a mapping target so no data is ever routed into it.\n")
    if notes_with_rules:
        L.append("**Convention broken:** these `Comments` columns have validation rules, which")
        L.append("means they are not scratch space after all.\n")
        for n in notes_with_rules:
            L.append("- `%s`.`%s`" % (n["sheet"], n["field"]))
        L.append("")
    else:
        L.append("No `Comments` column carries a validation rule — the convention holds.\n")
    if notes_misplaced:
        L.append("**Column order worth a look.** Every other sheet puts the scratch column")
        L.append("first, so these are a trap for anyone working across sheets — notes typed")
        L.append("into the first column here *would* be migrated:\n")
        L.append("| Sheet | Column | Position | |")
        L.append("|---|---|---|---|")
        for n in notes_misplaced:
            why = ("migrated field sitting in the scratch column's usual place"
                   if n.get("migratedFirst") else "scratch column is not first")
            L.append("| `%s` | `%s` | index %d | %s |" % (n["sheet"], n["field"], n["index"], why))
        L.append("")
    else:
        L.append("Scratch column is first on every sheet.\n")

    L.append("### Checks against import tables that are never created\n")
    live_tables = {t.lower() for ts in renames.values() for t in ts}
    dead = collections.defaultdict(int)
    for c in checks:
        if c["table"].lower() not in live_tables:
            dead[c["table"]] += 1
    if dead:
        L.append("These checks read from a table name that no `sp_rename` ever produces, so the")
        L.append("`IF EXISTS` guard around them never fires — **they don't run in production")
        L.append("either.** Each looks like a near-miss of a real table name.\n")
        L.append("| Table referenced | Checks | Closest renamed table |")
        L.append("|---|---|---|")
        for t, n in sorted(dead.items()):
            near = sorted(live_tables, key=lambda x: -len(os.path.commonprefix([x, t.lower()])))
            L.append("| `%s` | %d | `%s` |" % (t, n, near[0] if near else "—"))
    else:
        L.append("_None._")
    L.append("")

    L.append("### `FieldName` label disagreeing with the column tested\n")
    mismatches = [c["fieldNameMismatch"] for c in checks if c.get("fieldNameMismatch")]
    if mismatches:
        L.append("Every `ErrorLog` row carries a FieldName label *and* the expression actually")
        L.append("tested. Where they disagree the label is wrong, so the live import reports the")
        L.append("error against the wrong column -- a customer chasing a `ClientImportId` error")
        L.append("is really looking at a different field. The tested column was used for the")
        L.append("schema; without that, these land bogus rules on the link key.\n")
        L.append("| Import table | Label says | Actually tests | Used | Message |")
        L.append("|---|---|---|---|---|")
        for m in mismatches:
            L.append("| `%s` | `%s` | `%s` | **`%s`** | %s |" % (
                m["table"], m["declared"], m["tested"], m.get("used", ""), m["message"][:60]))
    else:
        L.append("_None._")
    L.append("")

    L.append("### Fields given two different max lengths\n")
    if length_conflicts:
        L.append("The script states more than one max length for the same field, so the")
        L.append("correct limit can't be determined from it. The **stricter** value was used")
        L.append("so the tool never under-warns; both are recorded on the field as")
        L.append("`maxLengthConflict`.\n")
        L.append("| Sheet | Field | Stated lengths | Used |")
        L.append("|---|---|---|---|")
        for (t, f), vals in sorted(length_conflicts.items()):
            L.append("| `%s` | `%s` | %s | %d |" % (
                t, f, ", ".join(str(v) for v in sorted(vals)), min(vals)))
    else:
        L.append("_None._")
    L.append("")

    L.append("### Checks the parser could not read\n")
    if unparsed:
        L.append("%d ErrorLog statement(s) didn't match the expected shape. Each one is a" % len(unparsed))
        L.append("rule that did **not** make it into the schema.\n")
        for u in unparsed[:15]:
            L.append("- `%s`" % u)
        if len(unparsed) > 15:
            L.append("- _...and %d more._" % (len(unparsed) - 15))
    else:
        L.append("_None — every ErrorLog statement parsed._")
    L.append("")

    L.append("## Suspected defects in the validation script itself\n")
    anomalies = find_source_anomalies(rows)
    if anomalies:
        L.append("Found while reading the allowed-value lists. These are **not** extraction")
        L.append("problems -- the script is the authority and was transcribed faithfully. Each")
        L.append("would make the live import reject data a reader would expect it to accept,")
        L.append("so they are worth fixing at the source.\n")
        L.append("| Field | Issue | Values |")
        L.append("|---|---|---|")
        for where, issue, vals in anomalies:
            L.append("| %s | %s | %s |" % (where, issue, ", ".join("`%s`" % v for v in vals)))
    else:
        L.append("_None detected._")
    L.append("")

    L.append("## Field-name collisions across sheets\n")
    L.append("Relevant to suggestion quality: a customer field matching one of these")
    L.append("names is ambiguous until the target sheet is known. `ClientImportId` is")
    L.append("not a collision to suppress — it is the key the import process uses to")
    L.append("link a client across every sheet, and the UI should teach that.\n")
    L.append("`ClientImportId` appears on %d of %d sheets.\n" % (len(link_key_sheets), len(templates)))
    L.append("| Sheets | Field |")
    L.append("|---|---|")
    for n, name in repeated[:25]:
        L.append("| %d | `%s` |" % (n, name))
    L.append("")

    L.append("## Fields with no validation rule\n")
    L.append("Present in a template but never validated. Recorded as optional")
    L.append("`Text` with `\"validated\": false` — absence of a rule is not evidence")
    L.append("of a rule, so nothing was inferred about them.\n")
    L.append("%d of %d fields.\n" % (len(unvalidated), len(rows)))
    by_sheet = collections.defaultdict(list)
    for r in unvalidated:
        by_sheet[r["sheet"]].append(r["field"])
    for s in sorted(by_sheet):
        L.append("- **%s** (%d): %s" % (s, len(by_sheet[s]), ", ".join("`%s`" % f for f in by_sheet[s][:12])
                                        + (" ..." if len(by_sheet[s]) > 12 else "")))
    L.append("")

    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(L))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    ap.add_argument("--templates", default=DEFAULT_TEMPLATES)
    ap.add_argument("--validation", default=DEFAULT_VALIDATION)
    ap.add_argument("--out", default=OUT_SCHEMA)
    ap.add_argument("--report", default=OUT_REPORT)
    args = ap.parse_args()

    for p in (args.templates, args.validation):
        if not os.path.exists(p):
            sys.exit("Source not found: %s" % p)

    templates, files, conflicts, excluded = load_templates(args.templates)
    with open(args.validation, encoding="utf-8", errors="replace") as f:
        sql = f.read()
    sql = strip_sql_comments(sql)
    renames = parse_renames(sql)
    checks, unparsed = parse_checks(sql)
    rows, orphans, _, length_conflicts, notes_with_rules, notes_misplaced = merge(templates, renames, checks)

    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(rows, f, indent=2, ensure_ascii=False)
        f.write("\n")

    write_report(
        args.report, rows, orphans, templates, renames, conflicts, unparsed, checks,
        [("Templates", args.templates), ("Validation script", args.validation)],
        length_conflicts, excluded, notes_with_rules, notes_misplaced,
    )

    print("Templates: %d workbooks, %d sheets" % (len(files), len(templates)))
    print("Checks parsed: %d (unreadable: %d)" % (len(checks), len(unparsed)))
    print("Fields: %d (%d with rules, %d without)" % (
        len(rows), sum(1 for r in rows if r["validated"]), sum(1 for r in rows if not r["validated"])))
    print("Orphan rules (no template column): %d" % len(orphans))
    print("Wrote %s" % os.path.relpath(args.out, REPO_ROOT))
    print("Wrote %s" % os.path.relpath(args.report, REPO_ROOT))


if __name__ == "__main__":
    main()
