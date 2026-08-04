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
- `schema_rules.py` — owns the `TARGET_DATABASES` registry (`CaseWorthy` → `../reference/target_schema_full.json`; `ServTracker` → no schema yet) and flags violations against whichever one is active: missing required fields, unmapped FK-dependent tables, duplicate target assignments, and format mismatches — decode/list value mismatches, boolean fields described with more than two options, and text fields whose stated length exceeds the target's max. This is the "prevent a customer from breaking the rules" requirement from the phase plan. All of these are heuristic checks against the customer's typed-in field description, never against real data.
- `sql_export.py` — Advanced-mode SQL export. Turns confirmed mappings (source table + source field → target table.field) into one SELECT statement per (target table, source table) pair, aliased to the exact target field names, for a technical data person to run against the customer's live source system. See "Advanced mode" below for scope and limits.
- `static/` — the frontend (vanilla HTML/CSS/JS), same 4-step interview flow as the original artifact POC (source system → fields → suggestions → summary), now calling this backend instead of `window.storage` / the Anthropic API directly from the browser. Step 1 now also asks which **Target Database** to map against, and has an **Advanced options** toggle (see below).
- `static/assets/logos/` — CaseWorthy and ServTracker logos (originally bundled from the `caseworthy-brand-visual-identity` skill's snapshot, reprocessed into real transparent PNGs — see Branding below; see the skill for canonical/print versions), swapped in the header based on the selected target database.
- `start.bat` / `stop.bat` — double-clickable launcher (starts the server + opens it in a Chrome app window for demos) and a matching stop script.
- `data/mappings.db` — created on first run, gitignored.

## Target database (CaseWorthy / ServTracker)

Step 1 of the interview now asks which target database this migration is for:
- **CaseWorthy** — fully supported. Uses the 28-table schema extracted from and spot-checked against `00_Staging_EXCEL_Validation_Script_v3.sql`.
- **ServTracker** — listed because it's a real, separate CaseWorthy application with its own validation rules and data templates, but **no ServTracker schema has been extracted yet**. Selecting it shows an honest "not loaded yet" notice and disables proceeding, rather than guessing at rules that haven't been sourced from an authoritative ServTracker validation script. Building this out means repeating the same extraction-and-spot-check process used for CaseWorthy (see `docs/PHASE_PLAN.md`), against ServTracker's own validation script, once one is provided.

To add a second real target database: add its schema file path to `schema_rules.TARGET_DATABASES` and a logo entry to `TARGET_DB_META` in `static/app.js`. Everything else (matching, rule-checking, storage scoping) is already generic per target database.

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
- ServTracker has no schema yet — see above.
- The Google Fonts import requires internet access at demo time; falls back gracefully to system fonts if unavailable.
- Reprocessing the logos (if new source files are provided) needs Pillow installed one-off — not part of the running app's dependencies.
- ~~Extracted schema rules haven't had a human spot-check yet~~ — spot-checked and confirmed correct by Russ (validation script owner) on 2026-08-04.
