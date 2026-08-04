# CW-ETL-FIELDMAP — Phase 0 local POC

Local web app version of the Field Mapping Assistant, per `docs/PHASE_PLAN.md`. Pure Python standard library — no `pip install` required — plus a local SQLite datastore. No authentication (by design, see phase plan). LLM calls go straight to Anthropic for now, isolated behind `llm_gateway.py` so swapping in CaseWorthy's internal gateway later is a one-file change.

## Run it

```
set ANTHROPIC_API_KEY=sk-ant-...   (PowerShell: $env:ANTHROPIC_API_KEY="sk-ant-...")
python app.py
```

Then open http://127.0.0.1:8000 in a browser. Without an API key set, the app still runs end-to-end — every field just comes back "No confident match," so the flag-for-review path is still exercisable.

Optional env vars:
- `PORT` — defaults to 8000.
- `ANTHROPIC_MODEL` — defaults to `claude-sonnet-5`.

## What's here

- `app.py` — HTTP server (stdlib `http.server`), serves the static frontend and the JSON API.
- `db.py` — SQLite-backed mapping library: per-source-system confirmed mappings, plus a cross-system field index used to boost suggestion confidence.
- `llm_gateway.py` — the one place that calls an LLM. Swap this file's implementation to point at the internal gateway in Phase 2.
- `schema_rules.py` — reads `../reference/target_schema_full.json` and flags rule violations (missing required fields, unmapped FK-dependent tables, duplicate target assignments, and soft decode/format mismatch hints) — this is the "prevent a customer from breaking the rules" requirement from the phase plan.
- `static/` — the frontend (vanilla HTML/CSS/JS), same 4-step interview flow as the original artifact POC (source system → fields → suggestions → summary), now calling this backend instead of `window.storage` / the Anthropic API directly from the browser.
- `data/mappings.db` — created on first run, gitignored.

## Known gaps (tracked in `docs/PHASE_PLAN.md`, not fixed here)

- No auth, no SOC2/HIPAA controls — explicitly deferred to Phase 2.
- Decode/format mismatch detection is a soft heuristic (looks for numbers in the source description that don't appear in the target's decode list) — not a real data validator.
- ~~Extracted schema rules haven't had a human spot-check yet~~ — spot-checked and confirmed correct by Russ (validation script owner) on 2026-08-04.
