# CW-ETL-FIELDMAP — Phase 0 local POC

Local web app version of the Field Mapping Assistant, per `docs/PHASE_PLAN.md`. Pure Python standard library — no `pip install` required — plus a local SQLite datastore. No authentication (by design, see phase plan). LLM calls go straight to Anthropic for now, isolated behind `llm_gateway.py` so swapping in CaseWorthy's internal gateway later is a one-file change.

## Run it

```
set ANTHROPIC_API_KEY=sk-ant-...   (PowerShell: $env:ANTHROPIC_API_KEY="sk-ant-...")
python app.py
```

Then open http://127.0.0.1:8000 in a browser, or double-click `start.bat` (see below). An API key is optional now — most common field names resolve to a real confidence match from the rule-based matcher without one; the LLM is only a fallback for names the rules can't confidently resolve.

Optional env vars:
- `PORT` — defaults to 8000.
- `ANTHROPIC_MODEL` — defaults to `claude-sonnet-5`.
- `CW_ETL_DB_PATH` — points the learned-mappings SQLite file at a shared location instead of the
  local `data/` folder; see "Shared learned-mappings library" below.

## Python version compatibility

The running app (everything except the one-off `_make_transparent.py` asset-prep script, which needs Pillow) uses only long-stable standard-library features — no walrus operator, no `match`/`case`, no PEP 604 `X | Y` type hints, no `str.removeprefix`/`removesuffix`, nothing that depends on the 3.12+ f-string parser. Checked directly with a project-wide grep, not just by memory.

Two spots were tightened further for broader version support, both verified working (server responds, confirm/stats round-trip correctly, 5 concurrent requests handled) after the change:
- `app.py` no longer imports `http.server.ThreadingHTTPServer` (only exists from Python 3.7 onward) — it's built by hand from `socketserver.ThreadingMixIn` + `http.server.HTTPServer`, both available in every Python 3 release.
- `db.py` uses `datetime.datetime.now(datetime.timezone.utc)` instead of the deprecated (since 3.12, slated for eventual removal) `datetime.datetime.utcnow()`.

Practical floor: any Python 3.x anyone would realistically still have installed today. This doesn't extend to Python 2 (f-strings alone rule that out, and there'd be no real reason to support it in 2026).

## What's here

- `app.py` — HTTP server (stdlib `http.server`), serves the static frontend and the JSON API. Every endpoint is scoped by `targetDatabase` (see below).
- `db.py` — SQLite-backed mapping library: per-source-system confirmed mappings, plus a cross-system field index used to boost suggestion confidence. Scoped per target database, so CaseWorthy and ServTracker mappings never collide.
- `field_matcher.py` — rule-based confidence matcher, grounded entirely in the target database's extracted schema. Scores a source field name against every candidate field via exact match, a curated table of common ETL abbreviations (DOB, SSN, FName, ZipCode, ...), and exact-substring/token matches (e.g. `Enrollment_Begin_Date` → `Enrollment.BeginDate`), before falling back to generic name-similarity. This is what produces a real "high/medium/low" confidence match with no API key and no network call — the LLM (`llm_gateway.py`) is only consulted when this can't confidently resolve a name.
- `llm_gateway.py` — the one place that calls an LLM. Swap this file's implementation to point at the internal gateway in Phase 2.
- `schema_rules.py` — owns the `TARGET_DATABASES` registry and per-database metadata (`TARGET_DB_META`: label, logo, module/tab-scoping behavior and copy), and flags violations against whichever one is active: missing required fields, unmapped FK-dependent tables, duplicate target assignments, and format mismatches — decode/list value mismatches, boolean fields described with more than two options, and text fields whose stated length exceeds the target's max. This is the "prevent a customer from breaking the rules" requirement from the phase plan. All of these are heuristic checks against the customer's typed-in field description, never against real data.
- `file_import.py` — parses an uploaded CSV/xlsx into Step 2 field rows (see "Import fields from a file" below).
- `sql_export.py` — Advanced-mode SQL export. Turns confirmed mappings (source table + source field → target table.field) into one SELECT statement per (target table, source table) pair, aliased to the exact target field names, for a technical data person to run against the customer's live source system. See "Advanced mode" below for scope and limits.
- `static/` — the frontend (vanilla HTML/CSS/JS), same 4-step interview flow as the original artifact POC (source system → fields → suggestions → summary), now calling this backend instead of `window.storage` / the Anthropic API directly from the browser. Step 1 now also asks which **Target Database** to map against, and has an **Advanced options** toggle (see below).
- `static/assets/logos/` — CaseWorthy and ServTracker logos (originally bundled from the `caseworthy-brand-visual-identity` skill's snapshot, reprocessed into real transparent PNGs — see Branding below; see the skill for canonical/print versions), swapped in the header based on the selected target database.
- `start.bat` / `stop.bat` — double-clickable launcher (starts the server + opens it in a Chrome app window for demos) and a matching stop script.
- `data/mappings.db` — created on first run, gitignored. Local by default; see "Shared
  learned-mappings library" below to point it at a shared location instead.

## Target database (CaseWorthy / ServTracker)

Step 1 of the interview asks which target database this migration is for:
- **CaseWorthy** — 28 tables, 282 fields, extracted from and spot-checked against `00_Staging_EXCEL_Validation_Script_v3.sql` (confirmed by Russ, 2026-08-04).
- **ServTracker** — 35 sheets, 536 migratable fields (plus 34 `Comments` scratch columns), extracted from its own `1 - Master Validation.sql` plus 18 master Excel templates. See `reference/SERVTRACKER_SOURCES.md` for sources, the adjudication log, and sign-off status; regenerate with `tools/extract_servtracker_schema.py`.

Availability is reported by `/api/target-databases`, derived from whether a schema actually loaded. It used to be a hardcoded `targetDatabase !== "CaseWorthy"` check in `static/app.js`, which meant dropping in a schema file could never have enabled a database in the UI.

To add another target database: add its schema path to `schema_rules.TARGET_DATABASES` and an entry to `schema_rules.TARGET_DB_META` (label, logo, whether it has modules). The frontend picks both up automatically. Matching, rule-checking, and storage scoping are already generic per target database.

## Module/tab scoping (both databases)

Both databases show a module picker on Step 1 now, but for different reasons, which is why the picker's copy and defaults differ between them (`groupNoun`, `scopingReason`, `defaultSelectAll` in `TARGET_DB_META`):

**ServTracker** ships as ~18 separate program-area workbooks (Congregate, Homecare, Transportation, …) and a customer migrates only the ones they actually run. Column names repeat heavily across sheets — `Funding` is on 10 sheets, `Site`/`StartDate`/`Provider`/`Mon`–`Sun` on 6 each. Unscoped, `field_matcher` ties across all of them, downgrades to `medium`, and appends an unreadable list of other sheets. Scoped to Congregate, the candidate set drops from 536 fields to 74 and `Site` resolves to an exact high-confidence match. Because narrowing is the entire point, **ServTracker defaults to nothing extra selected** — only the required base module is in scope until the customer picks more.

**CaseWorthy** is one staging workbook with 28 tables and no name collisions across them, so there's no ambiguity problem to fix — its "modules" are just its 28 tables, one tab each (`modules: [table]` on every schema row, added specifically to reuse this same picker rather than build a second UI). Scoping here is a plain convenience for targeting only the tabs a migration needs, so **CaseWorthy defaults to every tab selected**, matching its original always-everything behavior, with "Select all" / "Select none" to adjust. There's no required base tab — nothing is forced.

**Selecting nothing beyond what's required or default never blocks proceeding**, for either database — Step 1's Next button is only disabled when the chosen database's schema itself isn't loaded. (This used to require ServTracker customers to tick at least one optional module even when Client Master with Demographics alone was enough; that requirement is gone.)

Scoping narrows but doesn't eliminate collisions — a ServTracker customer can legitimately pick Congregate + Home Delivered + Case Management, which still share names. So the matcher also caps the "also exists on …" list at four entries instead of listing every sheet.

**`ClientImportId` is deliberately excluded from that ambiguity logic.** It appears on 32 of 35 ServTracker sheets *because* it's the key the import uses to link a client across them, so a tie is expected rather than suspicious. Fields flagged `linkKey` in the schema keep high confidence and get an explanatory note in the suggestion card and on Step 1, rather than a warning. `ServTrackerClientId` is flagged `mergeOnly` and explained as being for updating clients who already exist in the database.

**Client Master with Demographics is ServTracker's required base module** — rendered checked and disabled, and always included in the scope sent to the server regardless of what's ticked, because every ServTracker sheet keys off `ClientImportId` from the client sheet (confirmed by Alex Button, 2026-08-05). CaseWorthy has no equivalent base module.

Display convention: ServTracker schema rows carry both a `sheet` (what the customer fills in) and a `table` (the import table the validation script uses). The UI shows the sheet everywhere — suggestion cards, the override dropdown, rule warnings, and the summary — while `table::field` stays the stored identity for the mapping library and SQL export. CaseWorthy rows have no `sheet`, so they display the table name exactly as before (and CaseWorthy's module name, table name, and "sheet" are always the same string, so the picker shows a plain field count instead of a redundant "1 sheet ·" prefix).

## Learned-mappings counter

Moved from a prominent box next to the H1 to a small line at the very bottom of the footer, on every step (`renderFooter()` in `static/app.js`) — still visible, deliberately not competing with the header for attention. Same live-updating element (`#lib-stat`, refreshed by `refreshLibStat()`), just relocated and shrunk (13px/10px vs. the original 26px/11px).

## Shared learned-mappings library

By default `data/mappings.db` (`db.py`'s confirmed-mappings and cross-system field-index tables)
is local to whoever's running the app — gitignored, starts empty on a fresh checkout, and never
leaves that machine. Set `CW_ETL_DB_PATH` to a file path before running `python app.py` and every
confirmed mapping, on any machine pointed at that same path, accumulates in one shared library
instead — the whole point of "learning mappings over time" per the project's own description,
not just within one consultant's session.

**The shared location for this:** the CaseWorthy Collaboration SharePoint folder —
https://caseworthyinc.sharepoint.com/:f:/s/CWCollaboration/IgCw4PgzxHzASIxq7JGqWQTtAZm6U86ExovJ8aSvWb-E6As?e=OfLMLF
— synced locally via OneDrive ("Add shortcut to OneDrive" on that folder, or open it in the
OneDrive app). Once it's synced, find its local path in File Explorer (typically something like
`C:\Users\<you>\CaseWorthy Inc\CWCollaboration - <folder name>\`) and point the app at a
`mappings.db` file inside it:

```
set CW_ETL_DB_PATH=C:\Users\<you>\CaseWorthy Inc\CWCollaboration - <folder name>\mappings.db
python app.py
```
(PowerShell: `$env:CW_ETL_DB_PATH="C:\Users\<you>\...\mappings.db"`)

The app prints which mode it's in at startup (`Learned-mapping library: SHARED at ...` vs.
`local only at ...`), so it's never silently ambiguous which library a given run is actually
using.

**Known limitation — OneDrive/SharePoint sync is not shared-network file locking.** Each
consultant's copy is a local file that syncs to the cloud after the fact, not a single file
multiple processes lock and share live (the way a real network share or a proper client-server
database would). If two people confirm a mapping within the same sync window, OneDrive resolves
that as a conflict by creating a separate `<name>'s conflicted copy <date>.db` file rather than
merging the two — silently forking the library rather than erroring loudly. For how this tool is
actually used (a handful of consultants, sequentially, not high-frequency concurrent writes) that
risk is low, but it isn't zero: if a conflicted-copy file ever shows up next to `mappings.db`,
that's the signal a collision happened, and there's no automatic merge in Phase 0 — someone has
to look at both and decide (or ask whoever confirmed last) which one to keep going forward.

Not setting `CW_ETL_DB_PATH` keeps today's behavior exactly as-is — a private local library, no
sharing, no risk of the above.

## Advanced mode (SQL export)

Toggling "Advanced options" on Step 1 does two things:
1. Adds a **source table name** input to each field row on Step 2, alongside the existing field name/description.
2. On the Step 4 summary, generates one SQL SELECT statement per **(target table, source table)** pair — e.g. if `Client`'s fields come from two different source tables, you get two separate SELECT statements for `Client`, each producing just the columns sourced from that table — columns aliased to the exact target field names, ready for a technical data person to run against the customer's live source system and produce data shaped like our staging templates.

Deliberate scope limits (see the chat record / commit messages for the reasoning):
- **No JOINs are ever generated.** A target table whose fields come from more than one source table just gets multiple SELECT statements (one per source table) instead of one — the UI flags this ("split across N source tables") as an informational note, not an error. The data person is responsible for merging those result sets themselves; this tool doesn't collect join-key information or guess at how tables relate.
- **No automatic value-transformation logic.** The tool will never generate `CASE WHEN` guesses about how a source system encodes a value (e.g. assuming source "Y"/"N" means target 1/2) — that's fabricating a fact about data it's never seen. Required/decode/type constraints are instead surfaced as SQL comments above each column, so the data person knows what to verify/handle themselves.
- **Dialect-aware quoting only** (SQL Server `[x]`, MySQL `` `x` ``, PostgreSQL/Oracle `"x"`) — chosen per session via a dropdown that appears when Advanced mode is on. No dialect-specific query features beyond identifier quoting.
- Fields with no source table entered, or not mapped to a target field, are silently excluded from the export and called out in a small note (not a rule-engine warning — they're an Advanced-mode-only concern).
- **Source table names are matched case-insensitively, nothing else.** `dbo.ClientExport`, `dbo.clientexport`, and `DBO.CLIENTEXPORT` are treated as the same table and merged into one SELECT statement (using whichever casing was entered first). Any other difference — extra whitespace, a different schema prefix, an actual typo — still counts as a genuinely different table and gets its own statement.

## Import fields from a file

Step 2 has an "Import fields" control (`app.js: renderStep2`) so a customer doesn't have to type each field name in by hand: upload a `.csv` or `.xlsx` export from their source system, and its **header row** becomes the list of fields. `POST /api/import-fields` (multipart/form-data — the one endpoint in `app.py` that isn't JSON, handled separately in `Handler.do_POST` before the JSON routes) does the parsing via `file_import.py` and returns `{fields, warnings, sourceFile}`, which the frontend merges into `state.fields` (skipping anything that already matches an existing field name + source table, case-insensitively).

**Only the header row is ever read — never the data underneath it.** This isn't just a UX choice, it's the product boundary from this file's top section ("never ingests real client data"): even if a customer uploads a file that has real rows of client data below the header, that data must never be parsed, held in memory, or returned. For `.csv` this is a `csv.reader` that returns on the first non-blank row. For `.xlsx` — hand-rolled against the OOXML zip/XML format with `zipfile` + `xml.etree.ElementTree.iterparse` rather than a dependency like `openpyxl`, keeping the running app pure-stdlib — `read_xlsx_header` streams the worksheet XML and returns as soon as the first `<row>` element closes, so row 2 onward is never even parsed off disk, not merely discarded after the fact.

**Format depends on Advanced mode, matching what's typed into Step 2 by hand:**
- **Non-advanced:** each header cell is just the field name (e.g. `ClientID`).
- **Advanced:** each header cell is `Table.Column` (e.g. `Client.ClientID`, `Client.DOB`) — `file_import.build_fields` splits on the first `.` into source table and field name. A header with no `.` still imports (as a field with no source table) but is counted in a warning, since Advanced mode's SQL export needs a source table per field to work. The same instruction ("Advanced options require table and column names, example: Client.ClientID or Client.DOB") is shown on the page next to the import control and in the Step 2 intro text whenever Advanced mode is on.

Legacy `.xls` is explicitly not supported (no stdlib parser for the old binary format, and it would mean either a new runtime dependency or a lot of hand-rolled binary parsing for a legacy format) — the importer returns a clear error asking for `.csv` or `.xlsx` instead. Uploads are capped at `file_import.MAX_UPLOAD_BYTES` (5 MB); a file that big is a signal something other than a column list was uploaded, and the error message says so.

## Branding

Colors and font tokens follow the `caseworthy-brand-visual-identity` skill (canonical source — check there before changing any color/font in `styles.css`). Poppins and Source Sans 3 are now actually loaded via Google Fonts in `index.html` (previously only referenced by name, silently falling back to system fonts — verified via `document.fonts.check(...)` that they load). Headline copy is Title Case per the skill's "never sentence-case headlines" rule.

**The bundled logo files originally came as JPEGs (a solid black background baked into the pixels) mislabeled with a `.png` extension.** JPEG can't have an alpha channel, so this wasn't fixable in CSS. Fixed properly: `static/assets/logos/_make_transparent.py` (a one-off asset-prep script, run once, not a runtime dependency of `app.py`) chroma-keys out the sampled background color and re-saves real transparent PNGs — verified pixel-by-pixel that the wordmark's own colors are bit-for-bit unchanged (only the alpha channel was added), so nothing was recolored or distorted per the brand skill's rules. The logos now sit directly on the card background with no wrapper needed, and genuinely follow light/dark mode since the transparency is real. If the source JPEGs need reprocessing (e.g. a new logo variant from the brand portal), Pillow (`pip install pillow`) is required to rerun that script, but the running app itself stays pure-stdlib.

Logos render at up to 104px tall (`max-height`, `width: auto`), with `max-width: 100%` so a wide logo (ServTracker) scales down instead of overflowing a narrow viewport — verified both logos render at full size on a normal desktop width and shrink proportionally (no distortion) at ~550px.

## Dark / light mode

A "Light Mode" / "Dark Mode" toggle button is fixed to the top-right corner of every step. Defaults to the OS/browser's `prefers-color-scheme`, and the explicit choice persists across reloads via `localStorage` (`cw-etl-fieldmap-theme`). Implemented as a `data-theme="dark"|"light"` attribute on `<html>`, with semantic CSS variables (`--surface-page`, `--surface-card`, `--surface-border`, `--surface-text`, `--surface-heading`, ...) that get remapped per theme in `styles.css` — the underlying brand hex values (`--cw-blue`, `--cw-teal`, etc.) never change between themes, only which of them get used for headings/text on a dark surface, per the brand skill's approved-pairings matrix (e.g. headings switch from `--cw-blue` to white in dark mode, since plain blue-on-dark isn't in the approved pairing list).

Note: don't add `transition` on any property whose value comes from one of these theme-swapped CSS variables (e.g. `background`) — that was tried on `body`/`.card` and reproducibly caused the property to get stuck on its pre-toggle value in this browser, even though the underlying CSS variable updated correctly. Theme switches are instant (no fade) as a result.

## Known gaps (tracked in `docs/PHASE_PLAN.md`, not fixed here)

- No auth, no SOC2/HIPAA controls — explicitly deferred to Phase 2.
- All format-mismatch checks (decode, boolean arity, text length) are soft heuristics run against the customer's typed-in field description — not a real data validator, and they will miss mismatches that aren't spelled out in the description text.
- `field_matcher.py`'s alias table is a curated, non-exhaustive list of common abbreviations — an unusual source-system naming convention it doesn't recognize will still fall through to the LLM (or "no confident match" without a key).
- ServTracker's schema was **signed off by Alex Button on 2026-08-05**. The findings still listed in `reference/servtracker_extraction_report.md` are defects in the source validation script (checks that never run, wording that states no machine-readable rule), not gaps in the schema.
- 44 of ServTracker's 536 migratable fields have no validation rule found. That means no rule was found, **not** that the field is unconstrained — they're recorded with `"validated": false`.
- Five CaseWorthy fields have `type` strings no format check recognises (e.g. `Provider.Phone` is `Text (10 digits)`, which the `Text (max N)` pattern doesn't match), so no length check runs on them. Printed as a warning at startup; not changed, because that schema is signed off. See `reference/SCHEMA_FORMAT.md`.
- The Google Fonts import requires internet access at demo time; falls back gracefully to system fonts if unavailable.
- Reprocessing the logos (if new source files are provided) needs Pillow installed one-off — not part of the running app's dependencies.
- ~~Extracted schema rules haven't had a human spot-check yet~~ — spot-checked and confirmed correct by Russ (validation script owner) on 2026-08-04.
