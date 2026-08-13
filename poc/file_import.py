"""
Bulk import of source field names for Step 2 (poc/static/app.js) from an
uploaded CSV or .xlsx file, so a customer doesn't have to type each field
name in by hand.

Only ever reads the header row. Data rows are never parsed into memory or
returned to the caller -- this tool's product boundary (see CLAUDE.md) is
"where does field X go," not "is the data in field X valid," and it must
never ingest real client data even if a customer uploads a file that has
some. For .xlsx this is enforced structurally: `read_xlsx_header` streams
the worksheet XML with `ElementTree.iterparse` and returns as soon as the
first `<row>` closes, before the parser ever reads row 2 off disk.

Pure standard library, matching app.py's "no pip install needed to run the
app" rule. .xlsx support is hand-rolled against the OOXML zip/XML format
(zipfile + xml.etree.ElementTree) rather than depending on openpyxl.

Every XML part read out of an uploaded .xlsx (workbook.xml, its rels,
sharedStrings.xml, the first worksheet) goes through _read_zip_xml, which
rejects a DOCTYPE outright before any parsing happens -- same mitigation
create_template.py/form_xml.py use for the same reason: stdlib ElementTree's
entity-expansion protections against XXE/"billion laughs" aren't guaranteed
across Python versions, and none of these parts has a legitimate reason to
declare one.
"""

import csv
import io
import re
import xml.etree.ElementTree as ET
import zipfile
from email import message_from_bytes

MAX_UPLOAD_BYTES = 5 * 1024 * 1024  # a header row is tiny; a bigger file usually means real data snuck in

_OOXML_REL_NS = "{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id"
_TABLE_COLUMN_RE = re.compile(r"^\s*([^.]+?)\s*\.\s*(.+?)\s*$")


class FileImportError(Exception):
    """Raised for any problem with an uploaded file; message is user-facing."""


def parse_multipart(content_type, body):
    """Return {field_name: (filename_or_None, bytes)} for a multipart/form-data body.

    Hand-rolled via the stdlib `email` parser rather than the (now-removed)
    `cgi` module: prepending a Content-Type header to the raw body and letting
    `email` do the boundary/header parsing is more robust than hand-splitting
    on the boundary string.
    """
    if not content_type or "boundary=" not in content_type:
        raise FileImportError("Missing multipart boundary in request.")
    header = ("Content-Type: %s\r\n\r\n" % content_type).encode("utf-8")
    msg = message_from_bytes(header + body)
    if not msg.is_multipart():
        raise FileImportError("Expected a multipart/form-data upload.")
    fields = {}
    for part in msg.get_payload():
        disposition = part.get("Content-Disposition", "")
        name_match = re.search(r'name="([^"]*)"', disposition)
        if not name_match:
            continue
        filename_match = re.search(r'filename="([^"]*)"', disposition)
        filename = filename_match.group(1) if filename_match else None
        payload = part.get_payload(decode=True)
        if payload is None:
            payload = (part.get_payload() or "").encode("utf-8")
        fields[name_match.group(1)] = (filename, payload)
    return fields


def _decode_text(raw):
    for enc in ("utf-8-sig", "utf-8", "cp1252", "latin-1"):
        try:
            return raw.decode(enc)
        except UnicodeDecodeError:
            continue
    return raw.decode("utf-8", errors="replace")


def read_csv_header(raw_bytes):
    """First non-blank row only -- every row after it is never read."""
    text = _decode_text(raw_bytes)
    reader = csv.reader(io.StringIO(text))
    for row in reader:
        if any(cell.strip() for cell in row):
            return row
    return []


def _local(tag):
    return tag.rsplit("}", 1)[-1] if "}" in tag else tag


def _col_index(cell_ref):
    """'C7' -> 3 (1-based column index), used to preserve gaps from empty cells."""
    letters = re.match(r"([A-Za-z]+)", cell_ref or "")
    if not letters:
        return None
    idx = 0
    for ch in letters.group(1).upper():
        idx = idx * 26 + (ord(ch) - ord("A") + 1)
    return idx


def _read_zip_xml(zf, name):
    """Reads one XML part out of an .xlsx zip whole, raising FileImportError
    if it declares a DOCTYPE -- see this module's own docstring. Only used
    for parts this module already reads via ET.parse/fromstring (workbook.xml,
    its .rels), which consume the whole part into a tree regardless -- no
    streaming guarantee to preserve there. NOT used for sharedStrings.xml or
    a worksheet, where reading the whole part upfront would defeat the whole
    reason those two use iterparse in the first place (see _open_checked_xml
    below)."""
    data = zf.read(name)
    if b"<!DOCTYPE" in data[:1024].lstrip().upper():
        raise FileImportError("That workbook has a part that declares a DOCTYPE, which isn't accepted here.")
    return data


class _PrefixedStream:
    """A read()-only file-like wrapping `stream`, having already consumed
    `prefix` bytes from it -- replays `prefix` first, then falls through to
    `stream`. Lets _open_checked_xml peek at a stream's start (to reject a
    DOCTYPE) without losing true incremental reading for anything past the
    peek -- unlike reading the whole part into memory upfront would."""

    def __init__(self, prefix, stream):
        self._prefix = prefix
        self._stream = stream

    def read(self, size=-1):
        if not self._prefix:
            return self._stream.read(size)
        if size is None or size < 0:
            chunk, self._prefix = self._prefix, b""
            return chunk + self._stream.read()
        if size <= len(self._prefix):
            chunk, self._prefix = self._prefix[:size], self._prefix[size:]
            return chunk
        chunk, self._prefix = self._prefix, b""
        return chunk + self._stream.read(size - len(chunk))

    def close(self):
        self._stream.close()


def _open_checked_xml(zf, name, peek_size=2048):
    """Opens one XML part from an .xlsx zip as a stream for ET.iterparse,
    having already peeked at (and rejected a DOCTYPE in) its first bytes --
    true incremental reading is preserved for everything past the peek. Used
    for sharedStrings.xml and a worksheet, where read_xlsx_header's whole
    point is to never read row 2 off disk once it has row 1 (see this
    module's own docstring) -- reading the whole part upfront (_read_zip_xml
    above) would defeat that."""
    stream = zf.open(name)
    head = stream.read(peek_size)
    if b"<!DOCTYPE" in head.lstrip().upper():
        stream.close()
        raise FileImportError("That workbook has a part that declares a DOCTYPE, which isn't accepted here.")
    return _PrefixedStream(head, stream)


def _cell_value(c_elem, shared_strings):
    cell_type = c_elem.get("t")
    if cell_type == "inlineStr":
        is_elem = next((ch for ch in c_elem if _local(ch.tag) == "is"), None)
        if is_elem is None:
            return ""
        return "".join(t.text or "" for t in is_elem.iter() if _local(t.tag) == "t")
    v_elem = next((ch for ch in c_elem if _local(ch.tag) == "v"), None)
    if v_elem is None or v_elem.text is None:
        return ""
    if cell_type == "s":
        idx = int(v_elem.text)
        return shared_strings[idx] if 0 <= idx < len(shared_strings) else ""
    return v_elem.text


def _read_shared_strings(zf):
    if "xl/sharedStrings.xml" not in zf.namelist():
        return []
    strings = []
    # ET.iterparse only auto-closes a source it opened itself (from a path
    # string) -- since _open_checked_xml hands it an already-open stream,
    # closing it is on us.
    stream = _open_checked_xml(zf, "xl/sharedStrings.xml")
    try:
        for _event, elem in ET.iterparse(stream, events=("end",)):
            if _local(elem.tag) == "si":
                strings.append("".join(t.text or "" for t in elem.iter() if _local(t.tag) == "t"))
                elem.clear()
    finally:
        stream.close()
    return strings


def _first_sheet_path(zf):
    """Resolve the workbook's first (leftmost-tab) sheet to its worksheet XML path."""
    wb_root = ET.fromstring(_read_zip_xml(zf, "xl/workbook.xml"))
    sheets = [el for el in wb_root.iter() if _local(el.tag) == "sheet"]
    if not sheets:
        raise FileImportError("That workbook has no sheets.")
    rid = sheets[0].get(_OOXML_REL_NS)
    rels_path = "xl/_rels/workbook.xml.rels"
    if rid and rels_path in zf.namelist():
        rels_root = ET.fromstring(_read_zip_xml(zf, rels_path))
        for rel in rels_root:
            if rel.get("Id") == rid:
                target = (rel.get("Target") or "").lstrip("/")
                if target:
                    return target if target.startswith("xl/") else "xl/" + target
    candidates = sorted(n for n in zf.namelist() if n.startswith("xl/worksheets/sheet") and n.endswith(".xml"))
    if not candidates:
        raise FileImportError("Couldn't find a worksheet inside that workbook.")
    return candidates[0]


def read_xlsx_header(raw_bytes):
    """First row of the first sheet only. Streams the worksheet XML and stops
    reading as soon as that row closes -- rows below it are never parsed."""
    try:
        zf = zipfile.ZipFile(io.BytesIO(raw_bytes))
    except zipfile.BadZipFile:
        raise FileImportError("That doesn't look like a valid .xlsx file.")
    try:
        sheet_path = _first_sheet_path(zf)
        shared_strings = _read_shared_strings(zf)
        sheet_stream = _open_checked_xml(zf, sheet_path)
        try:
            for _event, elem in ET.iterparse(sheet_stream, events=("end",)):
                # "end" events fire bottom-up: a row's <c>/<v> children fire
                # before the <row> itself, so clearing non-row elements here
                # would wipe each cell's value before we ever read it. Just
                # skip them and let the first <row> end event do the reading
                # -- we return immediately after, so nothing downstream ever
                # accumulates enough to need clearing anyway.
                if _local(elem.tag) != "row":
                    continue
                values = {}
                max_idx = 0
                for c in (ch for ch in elem if _local(ch.tag) == "c"):
                    idx = _col_index(c.get("r")) or (max_idx + 1)
                    values[idx] = _cell_value(c, shared_strings)
                    max_idx = max(max_idx, idx)
                elem.clear()
                return [values.get(i, "") for i in range(1, max_idx + 1)]
        finally:
            sheet_stream.close()
    finally:
        zf.close()
    return []


def build_fields(headers, advanced_mode):
    """Header strings -> state.fields-shaped dicts, per column layout.

    Advanced mode expects each header as "Table.Column" (e.g. Client.ClientID),
    split on the first '.'; a header with no dot is imported with an empty
    source table and counted in the warning so the customer can fill it in.
    """
    fields = []
    blank_skipped = 0
    missing_table = 0
    for raw in headers:
        name = (raw or "").strip()
        if not name:
            blank_skipped += 1
            continue
        if advanced_mode:
            m = _TABLE_COLUMN_RE.match(name)
            if m:
                fields.append({"name": m.group(2), "desc": "", "sourceTable": m.group(1)})
            else:
                fields.append({"name": name, "desc": "", "sourceTable": ""})
                missing_table += 1
        else:
            fields.append({"name": name, "desc": "", "sourceTable": ""})

    warnings = []
    if blank_skipped:
        warnings.append(f"Skipped {blank_skipped} blank column header(s).")
    if advanced_mode and missing_table:
        warnings.append(
            f"{missing_table} field(s) had no \"Table.Column\" prefix (example: Client.ClientID) "
            "and were imported without a source table — fill it in before continuing."
        )
    return fields, warnings


def import_fields_from_upload(filename, raw_bytes, advanced_mode):
    if not filename:
        raise FileImportError("No file was uploaded.")
    lower = filename.lower()
    if lower.endswith(".csv"):
        headers = read_csv_header(raw_bytes)
    elif lower.endswith(".xlsx"):
        headers = read_xlsx_header(raw_bytes)
    elif lower.endswith(".xls"):
        raise FileImportError("Legacy .xls isn't supported — please save as .xlsx or .csv and re-upload.")
    else:
        raise FileImportError("Unsupported file type — upload a .csv or .xlsx file.")

    if not headers:
        raise FileImportError("Couldn't find a header row in that file.")

    fields, warnings = build_fields(headers, advanced_mode)
    if not fields:
        raise FileImportError("No usable column names were found in that file's header row.")
    return {"fields": fields, "warnings": warnings, "sourceFile": filename}
