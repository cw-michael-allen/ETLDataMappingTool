"""
Turns a real CaseWorthy Form XML export (<Ecm><Forms>/<Tables>/<Lists>...,
the "Export Form" feature in CaseWorthy admin) into the rows for a Field
Definition sheet -- ColumnName/TableName/FieldLabel/DataType/FormElementType/
Required/ListID/CharacterMaxLength/Comments -- matching the layout of the
custom-form sheets (WFDEmployment, WFDCheckIn) in the reference examples
Michael provided. See poc/form_xml.py for the generic structural preview
this builds on top of; that module still runs first and independently, so
an export this can't confidently interpret still gets *some* useful preview.

extract_form_templates() does the parsing; build_field_definition_workbook()
and build_staging_excel_workbook() (bottom of this file) turn its output into
the two downloadable .xlsx deliverables themselves, one sheet per form found.

Design decisions below are Michael's calls (2026-08-11), made reviewing a
real sample export (CaseWorthy_Export_Form_1000000013..., "Kiosk Intake
Review", Delaware People in Need) rather than guessed at:

- Column selection is FormElements-only: only fields actually placed on an
  exported form, not every column of the custom table backing it (a table
  can have far more columns than any one form exposes -- this sample's
  XKioskIntake table has ~50 columns, only 9 are on this form). <Tables> is
  used purely to enrich a matching column with its real SQL data type/length.
- A FormElement whose table isn't described in this export's own <Tables>
  section (a field pointing at an already-existing base table, e.g. a
  Service or Entity lookup) gets no DataType -- an honest gap, not a guess.
  Falling back to this repo's own base schema_rules schema for those isn't
  built yet.
- System/audit columns (CreatedBy, CreatedDate, etc.) are NOT filtered out
  by name -- tried that first, but the sample export disproved it: its
  CreatedDate field is Usage="3" (a normal, visible field with its own
  "Created Date" label), deliberately placed on the review form for a human
  to see, not a throwaway system column. FormElements-only selection already
  means a human curated this list; a name-based filter on top of that would
  second-guess a deliberate choice. The reference examples agree -- WFDCheckIn's
  own Hidden Field rows (XCheckInID, ClientID) are kept as real rows too, just
  labeled Hidden Field, never dropped. So the only exclusion is DataInput="None"
  (a button/link/search box -- never real data at all).
- FormElementType comes from reference/cw_element_types.json, the real,
  complete ElementTypeID -> control-type lookup Michael provided directly
  (2026-08-11) -- not a guess. The one piece that IS inferred from the
  sample export rather than sourced: Usage="4" was observed marking a field
  "Hidden Field" even when its own ElementTypeID was "1" (Text Box) --
  CaseWorthy's Form Designer apparently lets a normal control be flagged
  hidden without switching its ElementTypeID. See HIDDEN_USAGE below.
- Decode values (the Comments column, for a ListID-backed field) come from
  this export's own embedded <Lists> block, not the baseline
  reference/cw_list_values.json registry -- an export's <Lists> section is
  self-contained and covers org-specific custom lists (the 1,000,000+ range)
  the baseline registry can't resolve at all.
"""

import json
import os
import re
import xml.etree.ElementTree as ET

import form_xml

REFERENCE_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "reference")
ELEMENT_TYPES_PATH = os.path.join(REFERENCE_DIR, "cw_element_types.json")
_ELEMENT_TYPES_CACHE = None


def load_element_types():
    global _ELEMENT_TYPES_CACHE
    if _ELEMENT_TYPES_CACHE is None:
        if os.path.exists(ELEMENT_TYPES_PATH):
            with open(ELEMENT_TYPES_PATH, encoding="utf-8") as f:
                _ELEMENT_TYPES_CACHE = json.load(f)
        else:
            _ELEMENT_TYPES_CACHE = {}
    return _ELEMENT_TYPES_CACHE

# Same "Table.Column" convention file_import.py already parses for Advanced-
# mode headers -- duplicated rather than imported, matching this repo's own
# precedent (see transform_draft.py's _list_id_suffix) of not reaching across
# module boundaries for an underscore-prefixed helper.
_TABLE_COLUMN_RE = re.compile(r"^\s*([^.]+?)\s*\.\s*(.+?)\s*$")

# Usage="4" was observed on both of this sample's passthrough ID fields
# (XKioskIntakeID, X_ClientID) -- both otherwise ElementTypeID="1", same as
# ordinary visible text boxes -- so Usage, not ElementTypeID, is what marks a
# field "Hidden Field" and overrides whatever reference/cw_element_types.json
# would otherwise say for that ElementTypeID.
HIDDEN_USAGE = {"4"}

STRING_TYPES = {"nvarchar", "varchar", "char", "nchar"}


class CreateTemplateError(Exception):
    """Raised for any problem turning a Form export into template rows; message is user-facing."""


def _local(tag):
    return tag.rsplit("}", 1)[-1] if isinstance(tag, str) and "}" in tag else tag


def _parse_lists(root):
    """ListID (str) -> {"name": str|None, "values": [[code,label],...]},
    scoped to this export only -- see module docstring for why this is
    preferred over the baseline registry."""
    lists = {}
    for list_el in root.iter():
        if _local(list_el.tag) != "List":
            continue
        list_id = list_el.get("ListID")
        if not list_id:
            continue
        name_el = next((c for c in list_el if _local(c.tag) == "ListName"), None)
        items_el = next((c for c in list_el if _local(c.tag) == "ListItems"), None)
        values = []
        if items_el is not None:
            for item in items_el:
                if _local(item.tag) != "ListItem":
                    continue
                label_el = next((c for c in item if _local(c.tag) == "ListLabel"), None)
                code = item.get("ListValue")
                label = label_el.text if label_el is not None else None
                if code is not None and label is not None:
                    values.append([code, label])
        lists[list_id] = {"name": name_el.text if name_el is not None else None, "values": values}
    return lists


def _parse_table_columns(root):
    """(table_lower, column_lower) -> {dataType, length, isNullable,
    isPrimaryKey, isIdentity, foreignKeyTable}, from this export's own
    <Tables> section -- the real physical schema for whatever custom
    table(s) this export's form(s) are backed by."""
    columns = {}
    for table_el in root.iter():
        if _local(table_el.tag) != "Table":
            continue
        table_name = table_el.get("TableName")
        cols_el = next((c for c in table_el if _local(c.tag) == "Columns"), None)
        if not table_name or cols_el is None:
            continue
        for col in cols_el:
            if _local(col.tag) != "Column":
                continue
            col_name = col.get("ColumnName")
            if not col_name:
                continue
            fk_el = next((c for c in col if _local(c.tag) == "ForeignKey"), None)
            columns[(table_name.lower(), col_name.lower())] = {
                "dataType": col.get("DataType"),
                "length": col.get("Length"),
                "isNullable": col.get("IsNullable") == "1",
                "isPrimaryKey": col.get("IsPrimaryKey") == "1",
                "isIdentity": col.get("IsIdentity") == "1",
                "foreignKeyTable": fk_el.get("TableName") if fk_el is not None else None,
            }
    return columns


def _character_max_length(data_type, length):
    if not data_type or data_type.lower() not in STRING_TYPES or not length:
        return None
    try:
        n = int(length)
    except ValueError:
        return None
    if n < 0:
        return "MAX"  # SQL Server's nvarchar(MAX)/varchar(MAX) convention
    return n


def _form_element_type(usage, element_type_id):
    if usage in HIDDEN_USAGE:
        return "Hidden Field"
    entry = load_element_types().get(element_type_id)
    return entry["description"] if entry else f"Unknown (ElementTypeID={element_type_id})"


def _comments_for_list(list_id, lists):
    entry = lists.get(list_id) if list_id else None
    if not entry or not entry.get("values"):
        return None
    # "{code} - {label}" newline-joined matches the reference Field
    # Definition examples' own Comments convention exactly (e.g. WFDEmployment's
    # "1 - Full Time\n5 - Part Time") -- deliberately not schema_rules.py's
    # "code=label, code=label" SQL-export decode format, a different
    # convention for a different document.
    return "\n".join(f"{code} - {label}" for code, label in entry["values"])


def extract_form_templates(raw_bytes):
    """raw_bytes -> list of {"formName", "formDisplayName", "rows": [...],
    "unresolvedColumns": [...]}, one entry per <Form> found.

    rows: [{"columnName", "tableName", "fieldLabel", "dataType",
            "formElementType", "required", "listId", "characterMaxLength",
            "comments"}], in the same order fields appear in the export.

    unresolvedColumns: "Table.Column" strings for fields whose table isn't
    described in this export's own <Tables> section -- included so the field
    still shows up (a real field on the form) but with an honest gap on
    DataType rather than a guess.

    Raises CreateTemplateError if the file isn't a recognizable CaseWorthy
    Form export at all -- reuses form_xml's size/DOCTYPE/malformed-XML
    guards exactly, so both parsers agree on what's safe to even attempt.
    """
    if len(raw_bytes) > form_xml.MAX_UPLOAD_BYTES:
        limit_mb = form_xml.MAX_UPLOAD_BYTES // (1024 * 1024)
        raise CreateTemplateError(f"That file is larger than expected for a form export (limit {limit_mb} MB).")
    head = raw_bytes[:1024].lstrip()
    if b"<!DOCTYPE" in head.upper():
        raise CreateTemplateError("That file declares a DOCTYPE, which isn't accepted here.")
    try:
        root = ET.fromstring(raw_bytes)
    except ET.ParseError as e:
        raise CreateTemplateError(f"That doesn't look like valid XML: {e}")

    if _local(root.tag) != "Ecm":
        raise CreateTemplateError(
            "That doesn't look like a CaseWorthy Form export (expected an <Ecm> root element)."
        )

    lists = _parse_lists(root)
    table_columns = _parse_table_columns(root)

    forms_out = []
    for form_el in root.iter():
        if _local(form_el.tag) != "Form":
            continue
        form_elements_el = next((c for c in form_el if _local(c.tag) == "FormElements"), None)
        rows = []
        unresolved = []
        for fe in (form_elements_el or []):
            if _local(fe.tag) != "FormElement":
                continue
            data_input = fe.get("DataInput")
            if not data_input or data_input == "None":
                continue  # a button/link/search box, not a data field
            m = _TABLE_COLUMN_RE.match(data_input)
            if not m:
                continue
            table_name, column_name = m.group(1), m.group(2)

            label_el = next((c for c in fe if _local(c.tag) == "Label"), None)
            field_label = label_el.text if label_el is not None and label_el.text else column_name

            list_id = fe.get("ListID")
            col_meta = table_columns.get((table_name.lower(), column_name.lower()))
            if col_meta is None:
                unresolved.append(f"{table_name}.{column_name}")
            data_type = col_meta["dataType"] if col_meta else None
            char_max = _character_max_length(data_type, col_meta["length"]) if col_meta else None

            rows.append({
                "columnName": column_name,
                "tableName": table_name,
                "fieldLabel": field_label,
                "dataType": data_type,
                "formElementType": _form_element_type(fe.get("Usage"), fe.get("ElementTypeID")),
                "required": "Required" if fe.get("Required") == "1" else "Optional",
                "listId": list_id,
                "characterMaxLength": char_max,
                "comments": _comments_for_list(list_id, lists),
            })

        forms_out.append({
            "formName": form_el.get("FormName"),
            "formDisplayName": form_el.get("FormDisplayName"),
            "rows": rows,
            "unresolvedColumns": unresolved,
        })

    if not forms_out:
        raise CreateTemplateError("No <Form> definitions found in that export.")
    return forms_out


# --- .xlsx generation -------------------------------------------------------
# openpyxl is an optional dependency (poc/requirements-optional.txt) -- the
# one deliberate exception to this repo's pure-stdlib rule, same reasoning as
# shared_mappings.py's own lazy import: a hand-rolled .xlsx *writer* is a much
# bigger, corruption-prone undertaking than file_import.py's read-only header
# parser. Mirrors shared_mappings._load_openpyxl's lazy-load pattern exactly
# rather than importing it, per this repo's own precedent (see
# transform_draft.py's _list_id_suffix) of not reaching across module
# boundaries for a private helper.
_openpyxl = None
_openpyxl_unavailable = None

OPENPYXL_UNAVAILABLE_MESSAGE = "openpyxl isn't installed (run: pip install openpyxl, or see poc/requirements-optional.txt)"

FIELD_DEF_ATTRS = [
    ("ColumnName", "columnName"),
    ("TableName", "tableName"),
    ("FieldLabel", "fieldLabel"),
    ("DataType", "dataType"),
    ("FormElementType", "formElementType"),
    ("Required", "required"),
    ("ListID", "listId"),
    ("CharacterMaxLength", "characterMaxLength"),
    ("Comments", "comments"),
]

_INVALID_SHEET_CHARS = set(':\\/?*[]')


def _load_openpyxl():
    global _openpyxl, _openpyxl_unavailable
    if _openpyxl is not None or _openpyxl_unavailable is not None:
        return _openpyxl
    try:
        import openpyxl
        _openpyxl = openpyxl
    except ImportError:
        _openpyxl_unavailable = OPENPYXL_UNAVAILABLE_MESSAGE
    return _openpyxl


def _safe_sheet_name(name, used):
    """Excel sheet names: 31 chars max, none of : \\ / ? * [ ], and unique
    within the workbook -- a second form with the same display name gets a
    "(2)" suffix rather than silently overwriting the first one's sheet."""
    cleaned = "".join(c for c in (name or "Sheet") if c not in _INVALID_SHEET_CHARS).strip() or "Sheet"
    cleaned = cleaned[:31]
    base, n = cleaned, 2
    while cleaned in used:
        suffix = f" ({n})"
        cleaned = base[:31 - len(suffix)] + suffix
        n += 1
    used.add(cleaned)
    return cleaned


def build_field_definition_workbook(form_templates):
    """One sheet per form, transposed (columns=fields, rows=attributes) --
    matching the reference WFDEmployment/WFDCheckIn Field Definition sheets
    exactly. Returns an openpyxl Workbook; raises CreateTemplateError if
    openpyxl isn't installed."""
    openpyxl = _load_openpyxl()
    if openpyxl is None:
        raise CreateTemplateError(_openpyxl_unavailable)
    wb = openpyxl.Workbook()
    wb.remove(wb.active)
    used_names = set()
    for form in form_templates:
        sheet_name = _safe_sheet_name(form.get("formDisplayName") or form.get("formName"), used_names)
        ws = wb.create_sheet(sheet_name)
        for row_idx, (label, key) in enumerate(FIELD_DEF_ATTRS, start=1):
            ws.cell(row=row_idx, column=1, value=label)
            for col_idx, row in enumerate(form["rows"], start=2):
                value = row.get(key)
                ws.cell(row=row_idx, column=col_idx, value=value if value is not None else "")
    if not wb.sheetnames:
        wb.create_sheet("Sheet1")
    return wb


def build_staging_excel_workbook(form_templates):
    """One sheet per form: a single flat header row of ColumnName values --
    matching every other Staging Excel sheet in this app's convention
    (header-row-only, see file_import.py). Returns an openpyxl Workbook;
    raises CreateTemplateError if openpyxl isn't installed."""
    openpyxl = _load_openpyxl()
    if openpyxl is None:
        raise CreateTemplateError(_openpyxl_unavailable)
    wb = openpyxl.Workbook()
    wb.remove(wb.active)
    used_names = set()
    for form in form_templates:
        sheet_name = _safe_sheet_name(form.get("formDisplayName") or form.get("formName"), used_names)
        ws = wb.create_sheet(sheet_name)
        for col_idx, row in enumerate(form["rows"], start=1):
            ws.cell(row=1, column=col_idx, value=row["columnName"])
    if not wb.sheetnames:
        wb.create_sheet("Sheet1")
    return wb
