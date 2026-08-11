"""
Generic, bounded XML structure parser for the "Create Template" feature (see
poc/static/app.js's renderCreateTemplateStep).

This is deliberately the first slice of that feature, not the whole thing.
The end goal -- turning a CaseWorthy Form export into the two Excel
deliverables shown in the reference examples (a Field Definition sheet and a
Staging Excel header row) -- needs to know which XML elements/attributes mean
"field name," "data type," "list ID," "required," etc. Nothing about that
mapping has been confirmed yet, and per this repo's product boundary (see
CLAUDE.md), that mapping must come from an actual sample export, never
guessed at. So for now this module only exposes the *structure* of whatever
XML gets uploaded -- tag names, attributes, text, nesting -- so a human can
look at it and say what each part means before any field-extraction logic
gets written.

Unlike file_import.py's CSV/xlsx header-only reads, a form *definition*
export describes form structure, not client data, so it's fine to parse the
whole document -- there's no per-row data boundary to enforce here.

Pure standard library (xml.etree.ElementTree), consistent with the rest of
this repo.
"""

import xml.etree.ElementTree as ET

MAX_UPLOAD_BYTES = 2 * 1024 * 1024  # a form definition is metadata, not data -- this is generous
MAX_ELEMENTS = 20_000  # guards against a pathologically large/deeply-nested upload
MAX_TEXT_CHARS = 500  # a form export shouldn't carry paragraphs of text in one node
MAX_TREE_DEPTH_SHOWN = 12  # deeper nesting than this is truncated in the preview, not the counts


class FormXmlError(Exception):
    """Raised for any problem with an uploaded form XML file; message is user-facing."""


def _local(tag):
    return tag.rsplit("}", 1)[-1] if isinstance(tag, str) and "}" in tag else tag


def _to_node(elem, tag_counts, budget, depth):
    budget[0] -= 1
    if budget[0] < 0:
        raise FormXmlError(
            f"That file has more than {MAX_ELEMENTS:,} XML elements -- too large for this preview. "
            "Confirm it's a form definition export, not a data export."
        )
    tag = _local(elem.tag)
    tag_counts[tag] = tag_counts.get(tag, 0) + 1

    node = {"tag": tag}
    if elem.attrib:
        node["attrib"] = dict(elem.attrib)
    text = (elem.text or "").strip()
    if text:
        node["text"] = text[:MAX_TEXT_CHARS] + ("…" if len(text) > MAX_TEXT_CHARS else "")

    if depth >= MAX_TREE_DEPTH_SHOWN:
        if len(elem):
            node["truncated"] = f"{len(elem)} child element(s) not shown past depth {MAX_TREE_DEPTH_SHOWN}"
        return node

    children = [_to_node(child, tag_counts, budget, depth + 1) for child in elem]
    if children:
        node["children"] = children
    return node


def parse_form_xml(raw_bytes):
    """raw_bytes -> {"tree": {...}, "tagCounts": {tag: count}, "elementCount": int}

    Rejects a DOCTYPE outright rather than trying to safely support one: a
    real form-definition export has no legitimate need for an internal DTD,
    and stdlib ElementTree's entity-expansion protections against something
    like a "billion laughs" payload are not guaranteed across versions --
    simplest safe answer is to refuse any file that declares one.
    """
    if len(raw_bytes) > MAX_UPLOAD_BYTES:
        limit_mb = MAX_UPLOAD_BYTES // (1024 * 1024)
        raise FormXmlError(f"That file is larger than expected for a form definition (limit {limit_mb} MB).")

    head = raw_bytes[:1024].lstrip()
    if b"<!DOCTYPE" in head.upper():
        raise FormXmlError("That file declares a DOCTYPE, which this preview doesn't accept -- "
                            "a form definition export shouldn't need one.")

    try:
        root = ET.fromstring(raw_bytes)
    except ET.ParseError as e:
        raise FormXmlError(f"That doesn't look like valid XML: {e}")

    tag_counts = {}
    budget = [MAX_ELEMENTS]
    tree = _to_node(root, tag_counts, budget, depth=0)
    element_count = MAX_ELEMENTS - budget[0]
    return {"tree": tree, "tagCounts": tag_counts, "elementCount": element_count}
