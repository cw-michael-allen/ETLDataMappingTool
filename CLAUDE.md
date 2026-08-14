# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

`CW-ETL-FIELDMAP` — an AI-assisted tool that interviews a customer migrating into a CaseWorthy
application about their source system's field names and tells them where each one lives in the
target application's ETL schema, learning mappings over time. Currently in Phase 0 (local POC).
Full context: root `README.md`, `docs/PHASE_PLAN.md`, `poc/README.md`.

**Product boundary, never blur this:** this tool answers "where does field X go," not "is the
data in field X valid." Never ingests real client data — only field names/formats. Never
fabricates a target-schema rule, ListID, decode value, or ServTracker/CaseWorthy fact that isn't
sourced from that application's own validation script/templates and (for anything customer-facing)
signed off by the field's owner (Russ for CaseWorthy, Alex Button for ServTracker). If a schema
doesn't exist yet for a target, the UI says so honestly rather than guessing — see
`schema_rules.TARGET_DATABASES`.

## Running it

```
cd poc
python app.py                 # pure stdlib, no pip install needed to run the app itself
```
Then open `http://127.0.0.1:8000`, or double-click `poc/start.bat` (also opens a Chrome app
window for demos). The LLM fallback (`cw_services_toolkit.anthropic_ai`, see
`poc/README.md`'s "Mapping suggestions (LLM fallback)") is optional and lazily imported — the
rule-based matcher resolves most common field names without it. No test suite, linter, or build
step exists in this repo.

Regenerating a target schema (don't hand-edit the generated JSON):
```
python tools/extract_servtracker_schema.py [--no-data-dictionary]   # -> reference/servtracker_schema_full.json + extraction_report.md
python tools/build_signoff_page.py                                  # -> reference/servtracker_schema_review.html
```
Reprocessing the logo assets (needs Pillow, one-off, not an app runtime dependency):
```
pip install pillow
python poc/static/assets/logos/_make_transparent.py
```

## Architecture

**Everything in `poc/` is pure standard-library Python (server) + vanilla JS (frontend, no
build step, no framework).** `app.py` is a hand-rolled `http.server` app (see the file's own
docstring for *why* it avoids `http.server.ThreadingHTTPServer` and `datetime.utcnow()` — both
are Python-version-compatibility fixes, not style choices). It serves `static/` and a small JSON
API, backed by SQLite (`db.py`).

**Multi-target-database design.** The whole app is generic over "which application's schema am I
mapping to" — today that's CaseWorthy and ServTracker, but nothing should assume there are only
two. `schema_rules.py` owns:
- `TARGET_DATABASES` — name → schema JSON file path (`reference/target_schema_full.json` /
  `reference/servtracker_schema_full.json`). A database with no schema file loaded is reported
  as unavailable to the frontend, not hidden or faked.
- `TARGET_DB_META` — per-database presentation/scoping metadata (label, logo, module-picker
  copy, whether it defaults to everything selected). Read this dict's comments before changing
  scoping behavior; CaseWorthy and ServTracker default oppositely on purpose (see below).
- `reference/SCHEMA_FORMAT.md` — the schema JSON contract. **Read this before touching any
  schema file or `schema_rules.py`'s parsing.** The `type` string is load-bearing: an
  unrecognized value silently skips all format checks for that field (not an error), which is
  why `app.py` prints `SCHEMA_WARNINGS` at startup.

**Module/tab scoping (both databases, different reasons).** ServTracker ships as ~18 program-area
workbooks with heavy cross-sheet name collisions (`Site`, `Funding`, etc. repeat everywhere), so
scoping to the modules a customer actually runs is what makes suggestions confident — it defaults
to *nothing extra selected* beyond the required "Client Master with Demographics" base module.
CaseWorthy has 28 tables with no collisions, so its "modules" are just its tables (one tab each,
`modules: [table]` tagged onto every schema row) — purely a convenience, defaulting to
*everything selected*. `schema_rules.scope_schema` / `list_modules` implement both from the same
code path; don't special-case one database in the frontend when a `TARGET_DB_META` flag will do.

**Suggestion pipeline (`app.py: _handle_suggest`), in order:**
1. `db.get_mapping` — an exact-match learned mapping for this source system, scoped per
   target database (`db.py`'s tables have a `target_db` column specifically so CaseWorthy and
   ServTracker mappings never collide).
2. `shared_mappings.SHARED.get_exact` — only reached when step 1 finds nothing locally. Same
   exact-match shape, sourced from the shared Excel log instead of local SQLite, so a mapping only
   ever confirmed by someone *else* (via their own `CW_ETL_SHARED_XLSX`) still short-circuits here
   — reasoning explicitly says "from the shared mapping library" so it reads differently from a
   locally-confirmed one. See `poc/README.md`'s "Shared mapping log (Excel)".
3. `field_matcher.match` — rule-based, deterministic, no network call. Exact name match → alias
   table (common ETL abbreviations) → exact substring/token match → generic similarity, all
   against the source **field name**. Only when the name alone matches nothing does the
   customer's typed **description** get a turn, as a separate, deliberately conservative fallback
   pass (exact token/alias hits, no fuzzy ratio) — this is what resolves a cryptically-named field
   ("F23") when its description says "date of birth." Description-only matches are always
   `source: "rule-desc"` and capped at `low` confidence, and the description is also used to break
   an otherwise-tied same-named-on-multiple-tables match (e.g. "notes about the provider" prefers
   `Provider.Notes` over `Client.Notes`) — never to raise confidence past what the name earned. A
   `high`-confidence rule match short-circuits the LLM entirely.
4. `llm_gateway.suggest_mapping` — only reached when the rule matcher isn't confident. Takes the
   target application's label as a parameter (never hardcode which application it's mapping to
   in the prompt — that was a real bug, fixed, see git history). Calls Claude via
   `cw_services_toolkit.anthropic_ai` (lazily imported, degrades to a "no confident match"
   response if the toolkit isn't installed — see git history for the direct-Anthropic-API
   implementation this replaced), never a raw API call of its own.
5. `app.combined_field_index` — cross-source-system boosting ("also mapped this way N times"),
   summing `db.get_field_index` (local) and `shared_mappings.SHARED.get_field_index` (shared) —
   two independent evidence pools, added together rather than one overriding the other.

**`db.py`'s learned-mapping library is local-per-machine by default** (`data/mappings.db`,
gitignored) but can be pointed at a shared file via the `CW_ETL_DB_PATH` env var — e.g. a
OneDrive-synced SharePoint folder — so confirmed mappings and the cross-system field index
accumulate across everyone running the tool instead of resetting per machine. See
`poc/README.md`'s "Shared learned-mappings library" for the setup and its one real caveat:
OneDrive/SharePoint sync isn't true shared-network file locking, so two people confirming a
mapping in the same sync window can produce a conflicted-copy file instead of a clean merge —
low risk for how this tool is actually used (sequential, occasional), not zero.

**`shared_mappings.py`** is a second, independent sharing mechanism on top of (not instead of)
`CW_ETL_DB_PATH` above — a real `.xlsx` append-only log, human-readable in Excel by anyone, that
`app.py` reads from and writes to *in addition to* `db.py`'s local SQLite on every suggest/confirm.
Enabled via `CW_ETL_SHARED_XLSX`; needs `openpyxl` (`poc/requirements-optional.txt`) — the one
deliberate exception to this repo's pure-stdlib rule, because a hand-rolled `.xlsx` writer is a
much bigger, corruption-prone undertaking than `file_import.py`'s read-only header parser, and
this file may also be opened directly in Excel by a human. Never edits a row in place — every
confirmation appends a new row, and `confirm_count`/field-index counts are derived by aggregating
the whole log at read time (`SharedLog._reindex_row`), reproducing `db.py`'s exact semantics
(a changed mind resets the streak; field-index counts every repeat) without ever needing an
in-place edit, which is the one write shape immune to a same-moment two-writer collision short of
true file locking. Degrades gracefully (logs a warning, keeps running) if `openpyxl` isn't
installed or the file can't be reached. See `poc/README.md`'s "Shared mapping log (Excel)".

**`file_import.py`** (Step 2 "Import fields") lets a customer upload a `.csv`/`.xlsx` export
instead of typing each field in by hand. It only ever reads the **header row** — never the data
underneath it, per the product boundary above, even if the uploaded file happens to have real
rows in it. CSV stops at the first non-blank row; `.xlsx` is parsed by hand against the OOXML
zip/XML format (`zipfile` + `xml.etree.ElementTree.iterparse`, not `openpyxl`, to keep the app
pure-stdlib) and the parser returns as soon as the first `<row>` closes, so later rows are never
even read off disk. Advanced mode expects each header as `Table.Column` (e.g. `Client.ClientID`)
and splits on the first `.`; non-advanced mode expects a bare field name. Handled as the one
multipart/form-data POST route in `app.py`, kept separate from the JSON-only routes.

**`schema_rules.check_batch`** flags rule violations (missing required fields, unmapped FK
dependencies, duplicate target assignments, decode/boolean/length format mismatches) against
whatever the customer has mapped so far — heuristic checks against the typed-in description,
never against real data. A mapping's Advanced-mode `sourceValues` (a structured per-field list the
customer deliberately types, e.g. `M, F, U` or `1=Yes, 2=No` — see `schema_rules.parse_value_list`,
which unlike `parse_decode` never drops a bare entry, self-pairing it instead) takes priority over
`desc`'s free-text heuristics when present: `SOURCE_VALUE_CHECKS` (`_source_values_mismatch` for
decode/list exact-set, `_source_values_boolean_mismatch` for Boolean arity,
`_source_values_length_mismatch` for max length — the same three shapes `FORMAT_CHECKS` covers for
`desc`, just against a deliberate list instead of a sentence being pattern-matched) run first, one
hit wins. `desc`'s checks still run afterward as a secondary pass. Still never real data — a
customer-typed enumeration of the field's own encoding, same category as `desc`, just structured.

**`sql_export.py`** (Advanced mode) turns confirmed mappings into SELECT statements a technical
data person runs against the live source system. Deliberately never generates a JOIN — a target
table sourced from multiple source tables just gets one SELECT per source table instead of one
overall (flagged informationally, not blocked). Value-transform `CASE WHEN` logic is never
*guessed* — that would be fabricating a fact about data the tool has never seen — but see
`transform_draft.py` below for the one narrow, deliberate exception. Required/decode constraints
that don't clear that bar still just surface as SQL comments. Source table names are matched
case-insensitively (only casing — nothing else — is treated as "the same table").

**`transform_draft.py`** drafts a `CASE WHEN` only when two facts already on record for *this*
migration agree: what the customer told us about the source, and the target schema's own signed-
off decode/`decodeValues` (`schema_rules.target_value_pairs`, shared with `check_batch` above so
there's one definition of "what the target accepts"), with every source label matching a target
label exactly — case-insensitive, no fuzzy/synonym guessing ("Yes" is never assumed to mean
"True"). "What the customer told us" prefers Advanced mode's structured `sourceValues` list over
the free-text Step 2 description when both are present (`_source_pairs`, using
`schema_rules.parse_value_list`) — a deliberate list outranks a sentence being pattern-matched;
falls back to `schema_rules.parse_decode` on `desc` otherwise, unchanged from before this field
existed. That's a mechanical join of two things we were already told, not an inference about the
customer's actual data, which is why it doesn't cross the line the rest of this file draws.
Anything short of an exact match on *every* source pair aborts the whole draft (never a partial
CASE WHEN silently missing a branch) and becomes a `"failed"`-kind explanation instead. A third
input — **historical patterns**: descriptions *other* confirmed mappings to this same target field
have used, from `db.get_decode_patterns` / `shared_mappings.SHARED.get_decode_patterns`, merged by
`app.combined_decode_patterns` — is used only to *suggest* a pattern in the TODO header text when
this field's own description isn't usable. It never becomes generated SQL: there's no
confirmation behind it for *this* migration, only precedent from others, so a human has to read
it and decide, not code that runs unreviewed. All three outcomes (`"drafted"`, `"failed"`,
`"suggested"`) get their own TODO section in `build_export`'s header — the point (a direct request,
not an assumption) is that mismatches surface as errors to fix, not silent gaps.
`sourceValues` itself is never persisted (unlike `desc`, which `db.py`/the shared Excel log both
keep) — it's session-scoped, re-entered per migration, so historical patterns above are always
sourced from `desc` alone. A fifth, highest-priority input — `confirmed_value_map`, the customer's
own explicit source-value → target-code choices from the value-matching step below — outranks
everything else in this function: it was already built *from* `target_pairs` in that step, so
there's nothing left to reconcile; `draft_or_explain` uses it outright rather than re-verifying it.
Unlike `sourceValues`, a confirmed value map *is* persisted — see below.

**The value-matching step (`app.js: renderValueMatchStep`, inserted between Mapping Suggestions and
Summary in Advanced mode)** is what actually produces `confirmed_value_map` above. Gated by
`fieldsNeedingValueMatch`: a field only lands here if it's mapped (and not flagged for review) to a
target with real approved values (`targetPairsJs(s.targetMeta)` non-empty) *and* the customer typed
a `sourceValues` list for it — a field with no listed values has nothing to match here, and one
whose target has no decode/`decodeValues` has nothing to match *against*. For every distinct source
value, a required `<select>` of the target's own approved values (plus an explicit "Leave unmapped
(NULL)" option — never a silent default) gates the "Continue to Summary" button; nothing moves
forward until every value has a deliberate answer. Pre-selects, in priority order: this render
pass's own edits > a previously-confirmed value map for this *exact* source field (surfaced by
`/api/suggest`'s learned/shared-learned paths, see below) > an exact label match (the same
reconciliation `transform_draft.py` would do automatically) > unselected. Confirmed via
`POST /api/confirm-value-mapping`, which creates the underlying `mappings` row first if the field
was never explicitly confirmed in Step 3 (a high-confidence auto-suggestion can reach this step
without that click) so `db.save_value_map`'s plain `UPDATE` has something to land on, then persists
the map without touching that row's `confirm_count`/`desc` — a value-map confirmation is a distinct
decision from confirming the target field, not a re-confirmation of it.

**Storage for the value map, mirroring `desc`'s pattern:** `db.py`'s `mappings` table gained a
`value_map` column (`ALTER TABLE`, non-destructive, same reasoning as `desc`'s own migration) and a
standalone `save_value_map` (a plain `UPDATE`, deliberately not `save_mapping`, for the reason
above). `shared_mappings.py` gained a `ValueMap` column (appended at the end, same rule as
`Description`) and `append_value_map`, a distinct append from `append` that writes its own row
without bumping `field_index`/exact-match counts. One known imprecision from this split: on a
*reload* of the shared file, `_ingest` still counts every row — including a value-map-only
row — as a confirmation via `_reindex_row`, so `confirm_count` ends up one higher per value-map
confirmation than the number of times the field mapping itself was actually reconfirmed. Doesn't
affect which table/field/value_map `get_exact` returns, only that display counter, so it's left
alone rather than adding a row-type column to distinguish the two append kinds. `_handle_suggest`'s
learned/shared-learned paths both now return `valueMap` alongside `table`/`field`, which is what
lets the value-matching step above pre-fill a repeat migration's choices instead of asking the
customer to redo a decision already on record.

**`format_rules.py`** bakes a second, narrower kind of rule straight into a mapped field's SELECT
expression — no draft/review step, unlike `transform_draft.py` above. SSN dashing, phone/fax
cleanup, zip default+truncation, and first/last/middle name truncation (with the exact
`ISNULL(...,'FirstName')` null-fallback the source script uses) apply outright whenever a source
field is mapped to one of those target fields. Safe to apply without review because they're
sourced from CaseWorthy's own production migration scripts (`reference/MASTER_*.sql`, genericized
from real CW ETL engineer templates — see `reference/00_Staging_EXCEL_Validation_Script_v3.sql`
for the pre-existing companion file), not inferred from this customer's data — and for that same
reason, **CaseWorthy-only**: `sql_export.build_export`'s new `target_database` parameter (passed
from `app.py`'s already-known `target_db`, distinct from `target_label`'s display name) gates
every call into this module, so it's never applied when exporting for ServTracker or any future
target whose own validation script hasn't sourced these patterns. Also synthesizes a second
*companion* column (`SSNDataQuality` from `SSN`, `DOBDataQuality` from `BirthDate`) when the anchor
field is mapped but the companion target field isn't separately mapped — mirroring how the source
script derives both from the same one source column, since a customer's source system rarely
tracks a separate "how good is this SSN" field. An explicit mapping to the companion field, if the
customer has one, always wins over the synthesized version. Every baked rule and synthesized
column gets its own `-- TODO` header line (`build_export`'s new "Formatting rule(s) baked into the
SELECT columns below" section) so a data person sees it was applied without needing the web UI open.

**Storage implication:** `db.py`'s local `mappings` table and the shared Excel log both gained a
`desc`/`Description` column to support this — descriptions weren't being kept anywhere before.
`db.py` migrates via `ALTER TABLE ADD COLUMN` (not the drop-and-recreate pattern used for the
`target_db` column) specifically because real confirmed mappings exist in local databases now;
dropping the table would have destroyed them. The shared log's `_ensure_header_columns` extends an
existing header non-destructively — new columns always append at the end, never inserted mid-list,
since existing rows' cells stay in their original physical columns and a mid-list insert would
misalign a header that no longer matches where their values actually sit.

**`build_export`'s `"header"`** turns the export into a self-contained starter script: a SQL-comment
preamble listing every `schema_rules.check_batch` finding (required-missing, FK gaps, duplicates,
format-hint mismatches) plus every skipped field, as `-- TODO` items — so a data person working from
just the downloaded `.sql` file, with the web UI closed, still sees everything left to resolve.
Still nothing invented: every line is a fact `check_batch` or the skip list already produced
elsewhere: `build_export` only formats them. A flagged-for-review mapping (no confirmed table/field)
reports a distinct skip reason ("flagged for consultant review") instead of the generic "not mapped."

**Frontend (`poc/static/app.js`)** is a single-file, hand-rolled state machine (`state` object +
`renderStepN()` functions that replace `#app`'s `innerHTML` wholesale). No framework, no build
step. Event handlers are rebound after every re-render except the theme toggle, which is
delegated on `document` so it survives re-renders without rewiring.

**Branding/theming:** colors and fonts follow the `caseworthy-brand-visual-identity` skill —
consult it before changing anything in `styles.css`, don't invent a color pairing it doesn't
list. Dark/light mode is a `data-theme` attribute + semantic CSS variables (`--surface-*`) that
get remapped per theme; the underlying brand hex values never change, only which one gets used
where. **Don't add `transition` to any property whose value comes from a theme-swapped CSS
variable** (e.g. `background`) — this reproducibly gets the property stuck on its pre-toggle
value in testing, even though the variable itself updates correctly. See `poc/README.md` for the
theme and logo-transparency details (the bundled logos were JPEGs with a baked-in black
background mislabeled `.png` — fixed via chroma-keying, not CSS).

## Working conventions specific to this repo

- Commit messages here explain *why*, not just *what* — read recent `git log` output before
  assuming you understand a design decision; the reasoning is usually in the commit body, not
  just the diff.
- When extracting or editing a target schema, cross-check against the source validation
  script/templates and report disagreements for human sign-off rather than silently picking a
  winner — this is the pattern both `tools/extract_servtracker_schema.py` and the CaseWorthy
  extraction followed.
- Test UI changes by actually driving them (browser tool, or curl against the running server) —
  computed-style/DOM assertions have caught real bugs (a silently-swallowed `ReferenceError` in
  an `onclick` handler) that a code read-through missed.
