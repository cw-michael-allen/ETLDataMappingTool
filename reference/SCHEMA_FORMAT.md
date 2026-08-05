# Target-schema JSON format

Every target database's schema file (`target_schema_full.json` for CaseWorthy,
`servtracker_schema_full.json` for ServTracker) is a flat JSON array of field
objects. `poc/schema_rules.py` and `poc/field_matcher.py` read these files
directly.

**The `type` string is a contract, not free text.** `poc/schema_rules.py`
regex-matches it, and an unrecognised value doesn't raise — it silently skips
the check. A schema written with the wrong type vocabulary therefore produces
*zero* rule warnings, which the UI renders as a green
"✓ No rule violations detected" — indistinguishable from "everything is fine."
That failure mode is the reason this file exists.

`poc/schema_rules.load_schema` checks every row's `type` against the vocabulary
below and records anything it doesn't recognise in `SCHEMA_WARNINGS`;
`poc/app.py` prints those at startup. It deliberately **warns rather than
raises** — CaseWorthy's schema is human-signed-off and already contains five
such fields, so failing hard would break a working demo over pre-existing data:

| Field | `type` | Enforces |
|---|---|---|
| `Client.Pronouns` | `Free text / list` | nothing (not `List`) |
| `Client.StateCode` | `2-letter state code` | nothing (no length check) |
| `Provider.Phone` | `Text (10 digits)` | nothing (not `Text (max 10)`) |
| `Provider.Fax` | `Text (10 digits)` | nothing |
| `EntityContact.EntityContextType` | `Fixed Code (11 or 84)` | nothing |

These are flagged rather than silently corrected: the CaseWorthy schema was
verified by its owner, so changing its contents is their call, not this tool's.

## Required keys

| Key | Type | Meaning |
|---|---|---|
| `table` | string | Target table (CaseWorthy) or import table (ServTracker). |
| `field` | string | Target column name, exactly as the import expects it. |
| `required` | bool | Import rejects the row if this is blank. |
| `type` | string | One of the recognised forms below. |

## Recognised `type` forms

| Form | Parsed by | Effect |
|---|---|---|
| `Text` | — | No format check. |
| `Text (max N)` | `_text_length_mismatch` | Warns if the customer's note claims a longer length. Must match `Text \(max (\d+)\)` exactly. |
| `List` | `_decode_mismatch` | Warns if the customer's note names values outside the allowed set. Needs `decode` and/or `decodeValues`. |
| `Boolean` (or `Boolean …`) | `_boolean_arity_mismatch` | Warns if the note lists more than two options. |
| `Date` | — | No format check yet. |
| `Time` | — | No format check yet. |
| `Numeric` | — | No format check yet. |
| `Unique ID` | — | Informational. |
| `FK → <Table>` | `fk_target_table` | Warns if the referenced table isn't also being mapped. **Uses U+2192 `→`, not `->`.** |
| `Self-reference to <Field>` | — | Informational (CaseWorthy `HoHClientID`). |

## Optional keys

| Key | Type | Meaning |
|---|---|---|
| `note` | string | Free-text guidance surfaced in the UI. |
| `listId` | int | CaseWorthy list ID. |
| `decode` | string | Human-readable allowed values. CaseWorthy uses code pairs (`1=Yes, 2=No`); ServTracker uses bare labels (`Yes, No`). |
| `decodeValues` | string[] | Machine-readable allowed values. **Preferred** — `_decode_mismatch` uses it when present, which is what makes label-style decodes work. |
| `lookupTable` | string | Allowed values live in this database table, not the script, so they can't be listed. Type is still `List`. |
| `unique` | bool | Must be unique across rows. |
| `sheet` | string | ServTracker: the Excel sheet the customer actually fills in. |
| `modules` | string[] | ServTracker: which template workbooks carry this field. Drives module scoping. |
| `validated` | bool | ServTracker: whether any validation rule was found. `false` means no rule was found, **not** that the field is unconstrained. |
| `ruleSourceTable` | string | ServTracker: rules came from a differently-named import table (dual `sp_rename`). |
| `maxLengthConflict` | int[] | The script states two different max lengths; the stricter one is in `type`. Needs adjudication. |
| `linkKey` | bool | ServTracker: this is `ClientImportId`, the key the import uses to link a client across every sheet. Present on 32 of 35 sheets. **Not a name collision to suppress** — the UI should teach customers to use one consistent value per client. |
| `mergeOnly` | bool | ServTracker: `ServTrackerClientId` — only needed when updating clients who already exist in the database, blank for new clients. |

## Why the two decode styles differ

CaseWorthy's validation script encodes lists as numeric codes with labels
(`1=Self, 2=Spouse`), so `decode` alone is parseable. ServTracker validates
against bare label strings (`not in ('Monthly', 'One-Time')`) or against a
lookup table. `_decode_mismatch`'s original digit-matching branch finds no
codes in a ServTracker decode and would quietly do nothing — hence
`decodeValues`, which both styles populate.

## Adding a target database

1. Produce the schema JSON. For ServTracker, re-run
   `tools/extract_servtracker_schema.py`; don't hand-edit the output.
2. Register it in `poc/schema_rules.TARGET_DATABASES`.
3. Add branding/label metadata for the UI.

Nothing else needs changing — matching, rule-checking, and storage are already
generic per target database.
