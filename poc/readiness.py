"""
Migration Readiness rollup: aggregates mapping coverage/confidence/gaps
across EVERY mapping persisted so far for one source system, not just
whatever's in-memory for the current screen.

Deliberately reuses source_system (normalized) as the migration's identity
-- no new customer/migration entity -- and computes everything on demand
from db.py + schema_rules.py each call, same as every other check in this
app; nothing here is cached or persisted beyond migration_scope's own
saved module list (see db.py).

Required-field source (Michael, 2026-08-17): schema_rules.py's own
`required` flag is extracted from CaseWorthy's Excel-import validation
script and covers every technically-required column across all 28 curated
tables -- broader than what a real migration is actually asked to supply.
The real source of truth for "did this migration supply what it needs to"
is the Master Migration Template itself (reference/cw_master_template.json,
built by tools/build_master_template.py from
reference/Sample_Staging_With_Data.xlsx) -- for its own 5 tables, its own
required-field list wins outright, never schema_rules' broader one. A table
the customer has mapped fields into that ISN'T one of the Master Template's
tables (a custom form/table added outside it) has no Master-Template
guidance at all, so falls back to known PK/FK structural constraints
instead (the same registries create_template.py's own join-column synthesis
uses) -- a field is "required" there only if it's that table's own primary
key, or a foreign key whose referenced table is also in scope. This whole
Master-Template-based scheme is CaseWorthy-only (no equivalent template is
loaded for ServTracker yet); ServTracker keeps the original
schema_rules-required-flag-based check unchanged.
"""

import json
import os

import db
import schema_rules

REFERENCE_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "reference")
MASTER_TEMPLATE_PATH = os.path.join(REFERENCE_DIR, "cw_master_template.json")
FOREIGN_KEYS_PATH = os.path.join(REFERENCE_DIR, "cw_foreign_keys.json")
PRIMARY_KEYS_PATH = os.path.join(REFERENCE_DIR, "cw_primary_keys.json")

_MASTER_TEMPLATE_CACHE = None
_FOREIGN_KEYS_CACHE = None
_PRIMARY_KEYS_CACHE = None
_FOREIGN_KEYS_BY_TABLE_CACHE = None
_PRIMARY_KEYS_BY_TABLE_CACHE = None

# Master Template is a CaseWorthy-specific document (see module docstring) --
# no equivalent has been built for ServTracker, so it's never consulted for it.
MASTER_TEMPLATE_TARGET_DATABASE = "CaseWorthy"


def load_master_template():
    """{"tables": [...], "requiredFields": {table: [field,...]}, "allFields": {table: [field,...]}}
    or None if reference/cw_master_template.json hasn't been built yet (see
    tools/build_master_template.py) -- an honestly-reported gap, not guessed
    at, same as schema_rules.load_schema's own "no file -> []" convention."""
    global _MASTER_TEMPLATE_CACHE
    if _MASTER_TEMPLATE_CACHE is None:
        if os.path.exists(MASTER_TEMPLATE_PATH):
            with open(MASTER_TEMPLATE_PATH, encoding="utf-8") as f:
                _MASTER_TEMPLATE_CACHE = json.load(f)
        else:
            _MASTER_TEMPLATE_CACHE = {}
    return _MASTER_TEMPLATE_CACHE or None


# Loaders for reference/cw_foreign_keys.json / cw_primary_keys.json,
# duplicated rather than imported from create_template.py -- matching this
# repo's own established precedent (create_template.py's own docstring: "not
# reaching across module boundaries for an underscore-prefixed helper") of
# a small duplicated loader per module instead of reaching into another
# feature's private functions.
def _load_foreign_keys():
    global _FOREIGN_KEYS_CACHE
    if _FOREIGN_KEYS_CACHE is None:
        if os.path.exists(FOREIGN_KEYS_PATH):
            with open(FOREIGN_KEYS_PATH, encoding="utf-8") as f:
                _FOREIGN_KEYS_CACHE = json.load(f)
        else:
            _FOREIGN_KEYS_CACHE = {}
    return _FOREIGN_KEYS_CACHE


def _load_primary_keys():
    global _PRIMARY_KEYS_CACHE
    if _PRIMARY_KEYS_CACHE is None:
        if os.path.exists(PRIMARY_KEYS_PATH):
            with open(PRIMARY_KEYS_PATH, encoding="utf-8") as f:
                _PRIMARY_KEYS_CACHE = json.load(f)
        else:
            _PRIMARY_KEYS_CACHE = {}
    return _PRIMARY_KEYS_CACHE


def _foreign_keys_by_table():
    global _FOREIGN_KEYS_BY_TABLE_CACHE
    if _FOREIGN_KEYS_BY_TABLE_CACHE is None:
        by_table = {}
        for entry in _load_foreign_keys().values():
            by_table.setdefault(entry["table"].lower(), []).append(entry)
        _FOREIGN_KEYS_BY_TABLE_CACHE = by_table
    return _FOREIGN_KEYS_BY_TABLE_CACHE


def _primary_keys_by_table():
    global _PRIMARY_KEYS_BY_TABLE_CACHE
    if _PRIMARY_KEYS_BY_TABLE_CACHE is None:
        by_table = {}
        for entry in _load_primary_keys().values():
            by_table.setdefault(entry["table"].lower(), []).append(entry["column"])
        _PRIMARY_KEYS_BY_TABLE_CACHE = by_table
    return _PRIMARY_KEYS_BY_TABLE_CACHE


def _is_pk_or_relevant_fk(table, field, in_scope_tables_lower):
    """True if `field` is `table`'s own primary key (always required -- see
    create_template.py's _pk_addition_row: other tables' links need a real
    row to join back to) or one of `table`'s own foreign keys whose
    referenced table is ALSO in scope (same gate create_template.py's
    _needed_link_columns uses -- an FK to a table the migration was never
    going to touch isn't a gap worth flagging). Self-references (a table
    linking to itself, e.g. CaseNotes.MasterNoteID -> CaseNotes.CaseNoteID)
    are skipped, same as create_template.py's own _needed_link_columns --
    an optional self-relationship, not a structural requirement."""
    field_lower = field.lower()
    table_lower = table.lower()
    if field_lower in {c.lower() for c in _primary_keys_by_table().get(table_lower, [])}:
        return True
    for fk in _foreign_keys_by_table().get(table_lower, []):
        ref_lower = fk["referencedTable"].lower()
        if fk["column"].lower() == field_lower and ref_lower != table_lower and ref_lower in in_scope_tables_lower:
            return True
    return False


def _to_check_input(row):
    """Adapts a persisted mappings row to schema_rules.check_batch's input
    shape. sourceValues (the Advanced-mode structured value list) is never
    persisted -- only the resulting value_map is -- so format-hint checks
    here run off desc alone; a disclosed narrowing versus a live in-session
    check, not a silent gap."""
    return {
        "sourceField": row["field_name"],
        "desc": row["desc"],
        "table": row["target_table"],
        "field": row["target_field"],
    }


def _confidence_bucket(value):
    return value if value in ("high", "medium", "low", "learned", "none") else "unknown"


def _required_fields_master_template(in_scope_schema, master, in_scope_tables_lower):
    """Every {"table","field"} required across in_scope_schema, REGARDLESS
    of whether it's already mapped -- Master Template's own required-field
    list wins outright for its own tables; any other table in scope (a
    custom form/table added outside the Master Template) falls back to
    known PK/FK structural constraints. See module docstring."""
    master_tables = set(master["tables"])
    required_fields = master["requiredFields"]
    out = []
    for f in in_scope_schema:
        table, field = f["table"], f["field"]
        if table in master_tables:
            is_required = field in required_fields.get(table, [])
        else:
            is_required = _is_pk_or_relevant_fk(table, field, in_scope_tables_lower)
        if is_required:
            out.append({"table": table, "field": field})
    return out


def _required_fields_physical_only(table, in_scope_tables_lower):
    """Every {"table","field"} required by PK/FK structural constraints for
    a table that isn't part of schema_rules' curated schema at ALL
    (found 2026-08-17 testing form 1000000001: FamilyMember, Family, Entity,
    EntityContactPreference, ClientAddress, and ClientSummaryInfo are real
    physical tables create_template.py already resolves columns for via
    reference/cw_physical_columns.json, but none of them are among
    schema_rules' 28 curated tables -- so they never have a single row in
    in_scope_schema for _required_fields_master_template's own iteration to
    reach, no matter how in-scope they are). Checks the PK/FK registries
    directly instead of going through any schema at all -- same rule as
    _is_pk_or_relevant_fk, just enumerating candidate fields from the
    registries themselves rather than from schema rows that don't exist for
    this table. REGARDLESS of whether already mapped -- see
    required_fields_for_tables."""
    table_lower = table.lower()
    out = []
    seen_lower = set()  # a column can be both the table's own PK and one of
                         # its FKs at once (e.g. EntityContactPreference's
                         # EntityID is both) -- one entry is enough
    for pk_col in _primary_keys_by_table().get(table_lower, []):
        if pk_col.lower() in seen_lower:
            continue
        out.append({"table": table, "field": pk_col})
        seen_lower.add(pk_col.lower())
    for fk in _foreign_keys_by_table().get(table_lower, []):
        if fk["column"].lower() in seen_lower:
            continue
        ref_lower = fk["referencedTable"].lower()
        if ref_lower == table_lower or ref_lower not in in_scope_tables_lower:
            continue
        out.append({"table": table, "field": fk["column"]})
        seen_lower.add(fk["column"].lower())
    return out


def required_fields_for_tables(target_db, scope_tables):
    """Every {"table","field"} required across scope_tables, REGARDLESS of
    whether it's already mapped anywhere -- the full universe
    required_missing_for_pairs filters down from, and what Create Template's
    per-upload check (poc/app.py) uses directly to annotate each required
    field with which uploaded file (if any) covers it -- see
    db.get_create_template_uploads. No db.py involved here, same as
    required_missing_for_pairs."""
    master = load_master_template() if target_db == MASTER_TEMPLATE_TARGET_DATABASE else None
    full_schema = schema_rules.load_schema(target_db)
    in_scope_schema = schema_rules.scope_schema(full_schema, target_db, scope_tables)

    if not master:
        return [{"table": f["table"], "field": f["field"]} for f in in_scope_schema if f.get("required")]

    scope_tables_lower = {t.lower() for t in scope_tables}
    required = _required_fields_master_template(in_scope_schema, master, scope_tables_lower)

    # Tables in scope that schema_rules doesn't know about at all -- see
    # _required_fields_physical_only's own docstring. Skips any table that
    # already got at least one row considered above (has real schema
    # presence, whether or not it's a Master Template table).
    schema_known_tables_lower = {f["table"].lower() for f in full_schema}
    for table in scope_tables:
        if table.lower() in schema_known_tables_lower:
            continue
        required.extend(_required_fields_physical_only(table, scope_tables_lower))
    return required


def required_missing_for_pairs(target_db, mapped_pairs, scope_tables):
    """Given an already-resolved {(table, field)} set and the tables it
    covers -- no db.py involved, unlike compute_readiness -- returns
    [{"table","field"}] for every required field missing from mapped_pairs.
    A thin filter over required_fields_for_tables. Used by the
    persisted-mappings rollup below; Create Template's own per-upload check
    (poc/app.py's _handle_create_template_parse_xml) calls
    required_fields_for_tables directly instead, since it needs the FULL
    list (to show which file covers each one), not just what's missing --
    the latter deliberately never touches db.py at all (Michael's call,
    2026-08-17: keep Create Template decoupled from the mapping flow, same
    as it's always been -- see root CLAUDE.md)."""
    return [
        r for r in required_fields_for_tables(target_db, scope_tables)
        if (r["table"], r["field"]) not in mapped_pairs
    ]


def compute_readiness(target_db, source_system):
    mappings = db.get_all_mappings(source_system, target_db)
    scope = db.get_migration_scope(source_system, target_db)
    full_schema = schema_rules.load_schema(target_db)

    master = load_master_template() if target_db == MASTER_TEMPLATE_TARGET_DATABASE else None
    scope_known = bool(scope and scope.get("modules"))

    # Which tables define this rollup's scope, and where that scope came
    # from -- surfaced as scopeSource so the UI can caption accurately
    # instead of implying "full schema" when it's actually "the Master
    # Template's own tables" (2026-08-17: CaseWorthy's default used to be
    # all 28 tables, which is broader than any real migration needs).
    if scope_known:
        scope_tables = scope["modules"]
        scope_source = "saved"
    elif master:
        scope_tables = master["tables"]
        scope_source = "masterTemplateDefault"
    else:
        scope_tables = []
        scope_source = "fullSchema"

    in_scope_schema = schema_rules.scope_schema(full_schema, target_db, scope_tables)
    mapped_pairs = {(r["target_table"], r["target_field"]) for r in mappings}

    check_input = [_to_check_input(r) for r in mappings]
    check = schema_rules.check_batch(check_input, in_scope_schema)

    total_in_scope = len(in_scope_schema)
    mapped_in_scope = sum(1 for f in in_scope_schema if (f["table"], f["field"]) in mapped_pairs)
    coverage_percent = round(100 * mapped_in_scope / total_in_scope, 1) if total_in_scope else None

    # check_batch's own requiredMissing only looks at "touched" tables (ones
    # with at least one mapped field already) and always uses schema_rules'
    # own broader `required` flag -- exactly right for fkWarnings/
    # duplicates/formatHints, which only make sense once a table's been
    # started, but wrong for requiredMissing's own purpose here: this
    # rollup needs to see gaps in tables not yet started AND (2026-08-17)
    # needs the Master Template's own narrower required-field list, not
    # schema_rules' technical one, for the tables it covers. Shared with
    # Create Template's own per-upload check (poc/app.py) via
    # required_missing_for_pairs, which recomputes in_scope_schema/master
    # itself from scope_tables -- a little redundant work here, but keeps
    # that function fully self-contained (no db.py) for its other caller.
    required_missing = required_missing_for_pairs(target_db, mapped_pairs, scope_tables)

    confidence_counts = {"high": 0, "medium": 0, "low": 0, "learned": 0, "none": 0, "unknown": 0}
    for r in mappings:
        confidence_counts[_confidence_bucket(r["confidence"])] += 1

    # Tables in this rollup's scope (saved or the Master Template default)
    # with ZERO mapped fields -- the "haven't started this table at all"
    # signal required_missing above can't fully convey on its own (a
    # customer skimming a long required-fields list could miss that an
    # entire table is behind it).
    unstarted_modules = []
    if scope_tables and schema_rules.db_meta(target_db).get("modules"):
        touched_tables = {t for t, _ in mapped_pairs}
        module_tables = {}
        for row in full_schema:
            for module in row.get("modules") or []:
                module_tables.setdefault(module, set()).add(row["table"])
        for module in scope_tables:
            tables = module_tables.get(module, set())
            if tables and not (tables & touched_tables):
                unstarted_modules.append(module)
        unstarted_modules.sort()

    return {
        "sourceSystem": source_system,
        "targetDatabase": target_db,
        "scopeKnown": scope_known,
        "scopeSource": scope_source,
        "scopeModules": scope_tables,
        "mappedFieldCount": len(mappings),
        "totalInScopeFieldCount": total_in_scope,
        "coveragePercent": coverage_percent,
        "confidenceCounts": confidence_counts,
        "requiredMissing": required_missing,
        "fkWarnings": check["fkWarnings"],
        "duplicates": check["duplicates"],
        "formatHints": check["formatHints"],
        "unstartedModules": unstarted_modules,
    }
