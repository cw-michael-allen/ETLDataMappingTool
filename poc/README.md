# CW-ETL-FIELDMAP — Phase 0 local POC

Local web app version of the Field Mapping Assistant, per `docs/PHASE_PLAN.md`. Pure Python standard library — no `pip install` required to run the app itself — plus a local SQLite datastore. No authentication (by design, see phase plan). LLM calls go through `cw_services_toolkit.anthropic_ai` (see "Mapping suggestions (LLM fallback)" below), isolated behind `llm_gateway.py` so a future org-level change to how Claude gets called is a one-file change here.

## Run it

```
python app.py
```

Then open http://127.0.0.1:8000 in a browser, or double-click `start.bat` (see below). No setup is required to start the app — most common field names resolve to a real confidence match from the rule-based matcher on their own; the LLM fallback (see below) is optional and only ever consulted for names the rules can't confidently resolve.

Optional env vars:
- `PORT` — defaults to 8000.
- `CW_ETL_DB_PATH` — points the learned-mappings SQLite file at a shared location instead of the
  local `data/` folder; see "Shared learned-mappings library" below.
- `CW_ETL_SHARED_XLSX` — path to a shared Excel append-log that the matching logic also reads
  from and writes to; see "Shared mapping log (Excel)" below. Independent of `CW_ETL_DB_PATH` —
  either, both, or neither can be set.

## Mapping suggestions (LLM fallback)

Only needed if you want the LLM fallback active — everything else in this app runs with zero setup. Without it, `llm_gateway.py` degrades gracefully to "no confident match" for whatever the rule-based matcher can't resolve, same as before this was wired up.

1. Install [Claude Code](https://nodejs.org) (needs Node 18+): `npm install -g @anthropic-ai/claude-code`, then run `claude` once and log in with your work Claude account — this draws from the org's Claude Team/Enterprise subscription usage, not a separate API key or charge.
2. Install `cw_services_toolkit`, which lives alongside this project in the same repo. From this `poc/` directory:
   ```
   pip install -e "..\..\..\..\ServicesSharedUtilities\cw_services_toolkit"
   ```
   (that's `poc/` → `CW-ETL-FieldMap/` → `TeamExpressWay/` → `Teams/` → repo root → `ServicesSharedUtilities/cw_services_toolkit/` — four levels up, then down. Running from a different directory needs a different relative path, or use the toolkit's absolute path instead.)
3. **Check your Python version first**: the toolkit's own `pyproject.toml` requires **3.13.14+, excluding 3.14.0–3.14.5** (the fix for CVE-2026-7210, a hash-flooding weakness in `xml.parsers.expat`/`ElementTree`). `pip install` refuses outright on an excluded version — run `python --version` before assuming step 2 will work. This is stricter than this app's own "any Python 3.x anyone would realistically still have installed" floor (see below) — the LLM fallback is genuinely optional specifically so this narrower requirement doesn't become everyone's problem.

Nothing above touches Windows Credential Manager or any credential-storage step — `anthropic_ai` authenticates entirely through Claude Code's own login, so there's no secret for this app (or `system_utility`) to hold.

## Python version compatibility

The running app (everything except the one-off `_make_transparent.py` asset-prep script, which needs Pillow) uses only long-stable standard-library features — no walrus operator, no `match`/`case`, no PEP 604 `X | Y` type hints, no `str.removeprefix`/`removesuffix`, nothing that depends on the 3.12+ f-string parser. Checked directly with a project-wide grep, not just by memory.

Two spots were tightened further for broader version support, both verified working (server responds, confirm/stats round-trip correctly, 5 concurrent requests handled) after the change:
- `app.py` no longer imports `http.server.ThreadingHTTPServer` (only exists from Python 3.7 onward) — it's built by hand from `socketserver.ThreadingMixIn` + `http.server.HTTPServer`, both available in every Python 3 release.
- `db.py` uses `datetime.datetime.now(datetime.timezone.utc)` instead of the deprecated (since 3.12, slated for eventual removal) `datetime.datetime.utcnow()`.

Practical floor: any Python 3.x anyone would realistically still have installed today. This doesn't extend to Python 2 (f-strings alone rule that out, and there'd be no real reason to support it in 2026).

## What's here

- `app.py` — HTTP server (stdlib `http.server`), serves the static frontend and the JSON API. Every endpoint is scoped by `targetDatabase` (see below).
- `db.py` — SQLite-backed mapping library: per-source-system confirmed mappings (including the field's typed description, used by `transform_draft.py`'s historical-pattern lookups), plus a cross-system field index used to boost suggestion confidence. Scoped per target database, so CaseWorthy and ServTracker mappings never collide.
- `field_matcher.py` — rule-based confidence matcher, grounded entirely in the target database's extracted schema. Scores a source field name against every candidate field via exact match, a curated table of common ETL abbreviations (DOB, SSN, FName, ZipCode, ...), and exact-substring/token matches (e.g. `Enrollment_Begin_Date` → `Enrollment.BeginDate`), before falling back to generic name-similarity. This is what produces a real "high/medium/low" confidence match with no LLM setup and no network call — the LLM (`llm_gateway.py`) is only consulted when this can't confidently resolve a name.
- `llm_gateway.py` — the one place that calls an LLM, via `cw_services_toolkit.anthropic_ai` — see "Mapping suggestions (LLM fallback)" above. Lazily imports the toolkit (same pattern as `create_template.py`'s `_load_openpyxl()`), so an install that never set that up still runs fine.
- `schema_rules.py` — owns the `TARGET_DATABASES` registry and per-database metadata (`TARGET_DB_META`: label, logo, module/tab-scoping behavior and copy), and flags violations against whichever one is active: missing required fields, unmapped FK-dependent tables, duplicate target assignments, and format mismatches — decode/list value mismatches, boolean fields described with more than two options, and text fields whose stated length exceeds the target's max. This is the "prevent a customer from breaking the rules" requirement from the phase plan. All of these are heuristic checks against the customer's typed-in field description, never against real data.
- `file_import.py` — parses an uploaded CSV/xlsx into Step 2 field rows (see "Import fields from a file" below).
- `shared_mappings.py` — reads/writes the shared Excel append-log of confirmed mappings (see "Shared mapping log (Excel)" below). Independent of `db.py`; `app.py` consults both.
- `sql_export.py` — Advanced-mode SQL export. Turns confirmed mappings (source table + source field → target table.field) into one SELECT statement per (target table, source table) pair, aliased to the exact target field names, for a technical data person to run against the customer's live source system. See "Advanced mode" below for scope and limits.
- `transform_draft.py` — drafts a `CASE WHEN` value mapping, but only when the customer's own typed description and the target's own decode reconcile exactly; otherwise explains why in the export's TODO header instead. See "Drafted value mappings" below.
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

**Scoped per target database, and now labeled as such** (e.g. "8 learned mappings · 1 source
system (ServTracker)") — `db.py` keeps CaseWorthy and ServTracker mappings in separate rows, so
confirming mappings under one and then switching (or reopening the tool, which used to always
reset to CaseWorthy) made a real, saved library look empty. `state.targetDatabase` is now
persisted to `localStorage` (`cw-etl-fieldmap-target-db`, same pattern as the theme toggle) so a
fresh page load lands back on whichever database was last used, and the counter always names
which database its number belongs to.

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

## Shared mapping log (Excel)

A second, independent sharing mechanism, on top of (not instead of) the SQLite option above:
`shared_mappings.py` reads from and writes to a real `.xlsx` file — human-readable and directly
reviewable in Excel by anyone, unlike `mappings.db`. `db.py`'s local SQLite cache is untouched and
still handles every request as fast as it always has; this is an *additional* source the matching
logic also checks, and an *additional* place every confirmation also gets written.

**The shared workbook** — `MappingLibShared.xlsx` — lives in the CWCollaboration Team Site's
`ETLSharedMappingLookup - HACKATHON26` document library, the same site used for the SQLite option
above:
https://caseworthyinc.sharepoint.com/:f:/s/CWCollaboration/IgCw4PgzxHzASIxq7JGqWQTtAZm6U86ExovJ8aSvWb-E6As?e=OfLMLF
— sync that folder ("Add shortcut to OneDrive"), and the file is right there inside it. No
separate per-file share link needed (an earlier per-file link to a copy of this workbook in one
person's personal OneDrive has been retired — that copy no longer exists, its data was folded into
this one before it was removed, so nothing was lost).

**Enable it** by setting `CW_ETL_SHARED_XLSX` to wherever that folder actually lands once synced —
find its real local path in File Explorer rather than assuming the one below, which is just this
machine's actual path (the folder segment right after `OneDrive - CaseWorthy\` reflects this
Team Site's library name, not something that varies per person the way a personal OneDrive path
would):
```
set CW_ETL_SHARED_XLSX=C:\Users\<you>\OneDrive - CaseWorthy\CaseWorthy - ETLSharedMappingLookup - HACKATHON26\MappingLibShared.xlsx
python app.py
```
This needs `openpyxl` installed (`pip install openpyxl`, or `pip install -r
requirements-optional.txt`) — the one deliberate exception to this repo's pure-stdlib rule,
because a hand-rolled `.xlsx` *writer* is a much bigger, riskier undertaking than the read-only
header parser in `file_import.py`, and this file may also be opened directly in Excel by a human.
If `CW_ETL_SHARED_XLSX` is set but `openpyxl` isn't installed, or the file can't be reached, the
app logs a clear warning at startup and carries on without it — this feature degrading never
takes the rest of the tool down with it.

**Format — append-only log, one row per confirmation, never edited in place:**

| TargetDatabase | SourceSystem | SourceField | TargetTable | TargetField | ConfirmedAt | ConfirmedBy |
|---|---|---|---|---|---|---|

Confirming the same mapping again adds another row rather than incrementing a counter in place;
confirming a *different* target for a field previously confirmed differently also just adds a new
row. `shared_mappings.SharedLog` derives both a `db.py`-equivalent "confirm_count" (the streak of
consecutive rows, from the end, sharing the same target — i.e., changing your mind starts the
count over, exactly like `db.py`'s incremental counter does) and a `db.py`-equivalent
cross-system field-index count (every row counts, including repeats — also matching `db.py`) by
aggregating over the whole log at read time, so nothing needs to be computed or stored
incrementally. This — not update-in-place — is deliberate: an append is the one write shape that
can't corrupt or silently overwrite an existing row if two consultants write within the same
OneDrive sync window (see the concurrency caveat two sections up, which applies here too, in the
same low-but-nonzero way).

**How the matching logic actually uses it (`app.py`):** on `/api/suggest`, if `db.get_mapping`
(local SQLite) finds nothing, `shared_mappings.SHARED.get_exact(...)` gets a turn before falling
through to the rule matcher/LLM — a mapping only ever confirmed by someone else, via their own
`CW_ETL_SHARED_XLSX`-enabled session, still comes back `confidence: "learned"` here, reasoning
explicitly noting it's *"from the shared mapping library"* so it reads differently from a mapping
this machine confirmed itself. Cross-system field-index boosting (`combined_field_index` in
`app.py`) sums counts from `db.py`'s local index and the shared log's — two independent evidence
pools for "also mapped this way N times," not one overriding the other. On `/api/confirm`, the
shared-log append happens *after* the local SQLite save already succeeded, wrapped so a failure to
reach the shared file (not configured, momentarily locked, OneDrive not syncing right now) can
never fail or roll back the local confirm that already landed.

The shared log is read into memory once at startup (`shared_mappings.init()`, called from
`app.py: main()`) and kept current from there by mirroring this process's own appends straight
into memory — it does not re-read the whole workbook on every suggestion request. A mapping
confirmed by someone else *during* this process's run won't show up here until the app restarts;
for how this tool is actually used (start it, use it, stop it — see `start.bat`/`stop.bat`) that's
a reasonable enough cadence for a Phase 0 POC, not something worth a live-refresh mechanism yet.

**Where the file lives, and why that changed:** `MappingLibShared.xlsx` originally started life in
one person's *personal* OneDrive (confirmed directly from the file's own saved metadata —
`personal/mallen_caseworthy_com`, Microsoft's naming for a personal, not Team Site, location),
shared out via a per-file link. That setup doesn't give other testers a normal "sync it like a
folder" experience the way a Team Site document library does. It's since been moved into the
CWCollaboration Team Site's `ETLSharedMappingLookup - HACKATHON26` library above (a copy of its
data was written there, verified identical, and the personal-OneDrive original was then removed)
— every tester now gets a real synced local path just by syncing that one folder, the same way
`CW_ETL_DB_PATH` already works for the SQLite option.

## Advanced mode (SQL export)

Toggling "Advanced options" on Step 1 does two things:
1. Adds a **source table name** input, and a **known source values** input, to each field row on Step 2, alongside the existing field name/description. The source-values box is for a deliberate, structured list of this field's known values (e.g. `M, F, U` or `1=Yes, 2=No`) — not free text to guess at, and never real per-record data (see "Drafted value mappings" below for how it's used, and the product boundary at the top of this file for why it's never row data). Filling it in for a field mapped to a target with approved values also means a required "Value matching" step (see below) between Mapping Suggestions and Summary — no value conversion ships without the customer explicitly confirming it.
2. On the Step 4 summary, generates one SQL SELECT statement per **(target table, source table)** pair — e.g. if `Client`'s fields come from two different source tables, you get two separate SELECT statements for `Client`, each producing just the columns sourced from that table — columns aliased to the exact target field names, ready for a technical data person to run against the customer's live source system and produce data shaped like our staging templates.

Deliberate scope limits (see the chat record / commit messages for the reasoning):
- **No JOINs are ever generated.** A target table whose fields come from more than one source table just gets multiple SELECT statements (one per source table) instead of one — the UI flags this ("split across N source tables") as an informational note, not an error. The data person is responsible for merging those result sets themselves; this tool doesn't collect join-key information or guess at how tables relate.
- **No automatic value-transformation logic gets *guessed*.** The tool will never generate `CASE WHEN` guesses about how a source system encodes a value (e.g. assuming source "Y"/"N" means target 1/2) — that's fabricating a fact about data it's never seen. Required/decode/type constraints that don't clear the bar described below still just surface as SQL comments above each column, so the data person knows what to verify/handle themselves. See "Drafted value mappings" below for the one deliberate, narrow exception.
- **Dialect-aware quoting only** (SQL Server `[x]`, MySQL `` `x` ``, PostgreSQL/Oracle `"x"`) — chosen per session via a dropdown that appears when Advanced mode is on. No dialect-specific query features beyond identifier quoting.
- Fields with no source table entered, or not mapped to a target field, are excluded from the export and itemized (with a reason) in the header below rather than silently dropped.
- **Source table names are matched case-insensitively, nothing else.** `dbo.ClientExport`, `dbo.clientexport`, and `DBO.CLIENTEXPORT` are treated as the same table and merged into one SELECT statement (using whichever casing was entered first). Any other difference — extra whitespace, a different schema prefix, an actual typo — still counts as a genuinely different table and gets its own statement.

**The export starts with a `-- TODO` header**, generated from the same `schema_rules.check_batch`
results shown in the Step 4 readiness panel — required fields with no mapping, missing FK
dependencies, duplicate target assignments, and description/format mismatches — plus every
skipped field (including which ones were flagged for consultant review, distinct from ones that
just were never mapped). The point is a downloaded `.sql` file that's self-contained: a technical
data person working from just that file, with the web UI closed, still sees everything left to
resolve before running it. Nothing new is inferred here — every line already came from a check
this tool runs anyway; the header just collects them into one place instead of leaving them
scattered across the UI. If nothing's outstanding, the header says so plainly instead of omitting
itself, so "no header content" never gets mistaken for "this wasn't checked."

## Drafted value mappings

The one deliberate, narrow exception to "no automatic value-transformation logic" above:
`transform_draft.py` will draft a real `CASE WHEN` for a column, but only when two facts already
on record for *this* migration agree with each other:

1. **What the customer told us** — either their typed Step 2 description for that field (e.g.
   `1=Yes, 2=No`), or, when Advanced mode's structured **known source values** box for that field
   is filled in (e.g. `M, F, U`), that list instead — it takes priority over the free-text
   description whenever both are present, because a deliberate structured list is a stronger fact
   than a sentence the tool is pattern-matching. Unlike the description parser, a bare entry with
   no `code=label` isn't dropped — it's the customer directly naming one of the field's own values
   (their source already stores `Yes`/`No`, not a numeric code), so it self-pairs.
2. **What the target requires** — the signed-off schema's own decode/allowed-values for that field.

Both get parsed into code/label pairs (the same parser either side, so there's no separate
"guessing" logic for one side vs. the other), and a draft only gets written when *every* source
label matches a target label exactly — case-insensitive, but never a fuzzy or synonym match
("Yes" is never assumed to mean "True", "M" is never assumed to mean "Male" unless the customer's
own note actually says so). That's why this doesn't cross the product's own line: it's a
mechanical join of two things we were already told, not the tool inferring anything about the
customer's actual data. If even one source value doesn't match, **nothing gets drafted at all** —
a partial `CASE WHEN` silently missing a branch would be worse than no draft, so it's all-or-
nothing, and the column falls back to a plain alias plus a comment explaining exactly why — most
likely a real mismatch worth resolving, not a bug in the tool. The point is you find out from the
ToDo list, not from the script silently producing wrong data.

The same structured list, when present, also replaces the free-text heuristics in the Step 4
readiness panel's format-mismatch check (`schema_rules.check_batch` / `_source_values_mismatch`)
with an exact-set comparison against the target's allowed values — more reliable than
pattern-matching a sentence, since every entry was deliberately typed as a value. And regardless
of whether a draft was produced, every field with a known-source-values list gets echoed into the
SQL export's header under its own "for reference" section, so a data person sees exactly what the
customer said this field contains even when nothing could be auto-drafted. **This list itself is
session-scoped only** — unlike the free-text description, it is not persisted into `db.py`'s
learned-mapping library or the shared Excel log, so it has to be re-entered for a repeat migration
on the same source system. (The customer's *confirmed match* against it, from the value-matching
step below, is a different thing and is persisted — see "Value matching.")

There's a second signal, used more cautiously: **patterns from past confirmed mappings.** Every
confirmed mapping's description is now kept (in `db.py`'s local table and the shared Excel log
alike — this is the same "established patterns across past migrations" idea as the shared learned-
mappings library above, just applied to decode notation instead of field names). When *this*
field has no usable description of its own, but other confirmed mappings to that same target
field have — and that historical description would itself reconcile cleanly against the target —
the header surfaces it as a plain-text suggestion: *"no description given, but N past confirmed
mapping(s) described their source as '...' — verify against your own source data first."* That
suggestion is never turned into generated SQL on its own. There's no confirmation behind it for
*this* migration, only precedent from other ones, so it stays something a human reads and decides
on, not code that runs unreviewed.

Every outcome gets its own labeled TODO section in the header — drafted (review before running),
failed (a real mismatch to resolve), or suggested (a pattern worth considering) — so mismatches
surface as errors to fix, exactly like a normal build's warnings, rather than getting silently
smoothed over.

## Value matching (forcing a real decision, not a guess)

Auto-drafting above only fires on an *exact* label match — anything short of that leaves a plain
column alias and an explanation. That's deliberately conservative, but it also means the customer
never gets a chance to just tell the tool what a mismatched value actually means. **Value matching**
closes that gap without crossing the "never guess" line: instead of the tool inferring anything, it
inserts a required step (`app.js: renderValueMatchStep`, between Mapping Suggestions and Summary,
Advanced mode only) where the customer matches each of their own listed source values to one of the
target's approved values themselves, one dropdown at a time.

**When it appears:** `fieldsNeedingValueMatch` gates it on two things — the field is mapped (and not
flagged for review) to a target with real approved values, *and* the customer already typed a known
source values list for it in Step 2. It doesn't matter whether that list would have auto-matched
exactly or not — if a value's list is there, its step shows up, so the customer is always the one
who explicitly decided (even a clean "Yes/No → 1/2" match still gets a visible, confirmed choice
rather than a silent auto-draft). No list, or a target with no approved values to match against, and
there's nothing to show — the field just flows through as before.

**Nothing is optional.** Every distinct source value gets its own dropdown of the target's approved
values, plus an explicit "Leave unmapped (NULL)" option — never a silent default. "Continue to
Summary" stays disabled until every value across every field on the page has a deliberate answer.

**What gets pre-selected**, in priority order: an edit already made this render pass, then a value
map already confirmed for this *exact* source field in an earlier session (see persistence below),
then an exact label match (the same reconciliation the auto-draft above would do on its own) as a
starting suggestion, then nothing — forcing an explicit look.

**The result outranks everything else in `transform_draft.py`.** Once confirmed, it's sent to
`/api/confirm-value-mapping` and becomes the mapping's `valueMap` (e.g. `"M=1,F=2,U=3"`), which
`draft_or_explain` uses outright as the CASE WHEN — no re-verification against the target's decode,
because it was already built *from* that decode in the dropdown; it's a customer decision on record,
not a draft to double-check.

**Persisted, unlike the source values list itself:** `db.py`'s `mappings` table and the shared Excel
log both gained a `value_map` column, written by a dedicated `save_value_map` / `append_value_map`
(deliberately separate from the functions that confirm the target field mapping itself, so this
doesn't reset that mapping's own confirm streak or description). A repeat migration on the *same*
source system sees its past value-map choices pre-filled instead of being asked to redo them —
`/api/suggest`'s learned/shared-learned paths now return `valueMap` alongside the target
table/field for exactly this reason.

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

**That chroma-key script samples one corner as "the background color" — the source JPEGs turned out to have a second, different-colored background region** (a solid opaque white band along the bottom edge of both logos, and along the right edge of CaseWorthy's) that was far enough from the sampled corner color to score as "definitely foreground" and stay fully opaque. Invisible on a light card, but a visible white line/bar in dark mode. Found and fixed by inspecting the actual alpha/RGB data (not just eyeballing it) and cropping both PNGs down to their real visible-content bounding box — verified zero fully-opaque near-white pixels remain along any edge of either file afterward. The source JPEGs no longer exist in the repo, so this was a direct pixel fix on the PNGs rather than a re-run of the script; if new logo source files ever need processing, keep this failure mode in mind (multi-region backgrounds need more than a single corner sample).

Logos render at up to 104px tall (`max-height`, `width: auto`), with `max-width: min(390px, 100%)` — the fixed cap, not just the height, matters here: ServTracker's wordmark is proportionally much wider than CaseWorthy's (aspect ratio ~6.2 vs ~3.75 after the crop above), so height-only sizing let it render far larger overall despite "matching" on height. 390px is CaseWorthy's own natural rendered width at 104px tall, so this caps ServTracker down to match without changing CaseWorthy's size at all. The `100%` half of the `min()` still guards against overflow on a narrow viewport, same as before.

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
