# Handoff: CaseWorthy ETL Field Mapping Assistant — POC → Engineering Build

**Project keyword: `CW-ETL-FIELDMAP`** — use this as the anchor term if you reference this
work in Jira, Confluence, or future Claude sessions, so it's searchable later.

## Context

CaseWorthy's ETL data migration process for new customers takes 9–12 months against a
90-day target. This project is exploring AI-assisted tooling to close that gap. This
specific artifact is **Tier 0 / Option B** of that broader effort: a no-dev-team,
customer-facing proof of concept that interviews a customer about their source system's
field names and tells them where each one lives in CaseWorthy's target ETL schema.

**Explicit product boundary (do not blur this):** this tool never ingests real client
data — only field names and formats. It answers "where does field X go," not "is the
data in field X valid." Data *validation* against real values is a separate, already-solved
problem owned by Russ's `00_Staging_EXCEL_Validation_Script_v3.sql`. Keep these two jobs
separate in any future build.

## What exists today

**File:** `etl-schema-mapping-poc.html` (single-file HTML/JS artifact, built in Claude's
artifact environment, not yet in a repo)

**Grounded target schema:** ~70 fields across Client, Program, Enrollment, ServiceType,
and Users — extracted directly from `00_Staging_EXCEL_Validation_Script_v3__1_.sql`
(2,921 lines, 28 tables, 328 checks total; this POC covers 5 of those 28 tables as a
representative slice). Every field in the POC's `TARGET_SCHEMA` array carries its real
ListID and decode values pulled straight from the script (e.g., `RelationToHoH` →
ListID 4, `1=Self, 2=Spouse, 3=Child`) — not invented, not from the Data Dictionary
(which was confirmed unreliable vs. the script in an earlier session).

**Sample workbook used for grounding:** `Sample_Staging_With_Data.xlsx` — tabs: Users,
Client, Program, Enrollment, ServiceType, XNewCustomTable. The `XNewCustomTable` tab is
a useful real example of a customer-custom field set with no target-schema match — good
test case for the "flag for review, don't guess" behavior.

**Working mechanics (all functional in the POC, running client-side in the artifact):**
1. Interview flow: source system name → field list (name + optional format note) → review → export.
2. Mapping suggestion: calls the Anthropic API directly (`api.anthropic.com/v1/messages`,
   model `claude-sonnet-4-6`) with the field name/description plus the full candidate
   list, constrained to JSON output, forbidden from inventing target fields not in the
   candidate list.
3. **Learning mechanism (the part that answers "gets smarter over time"):**
   - Exact-match key: `mapping:{normalized source system}:{normalized field name}` →
     `{table, field, confirmCount, lastConfirmedAt}`, using Claude's artifact shared
     persistent storage (`window.storage`, `shared=true`). Next customer on the *same*
     source system gets this mapping instantly, no API call.
   - Cross-system index: `fieldindex:{normalized field name}` → list of
     `{table, field, count}`, so a field name that's mapped consistently across *any*
     customers boosts confidence even on a brand-new source system.
   - A visible "Learned mappings" counter in the UI pulls live from this storage —
     useful for demos, since it visibly increments as mappings get confirmed.
4. Honest refusal: if Claude's suggestion confidence is "none," the UI shows "No
   confident match" and a "Flag for consultant review" button rather than forcing a guess.

## Known limitations (be upfront about these in the Engineering ask)

- No real database — storage is Claude's artifact key-value store, not something
  Engineering can build on directly. A real build needs its own datastore.
- No auth / access control — the shared mapping library is visible to anyone with the
  artifact link. Fine for internal POC use; not fine for un-gated customer access.
- Covers 5 of 28 tables in Russ's script. Full coverage means extracting the remaining
  ~23 table sections the same way (already have the method: grep table markers in the
  script, pull required/ListID/FK rules per field).
- No handling yet for multi-table source ambiguity (e.g., a source field that could
  plausibly map to more than one target table depending on context) — flagged as a
  known gap, not solved.

## What's next

1. Package this as a formal POC demo for leadership (deck or one-pager) — not yet built.
2. Scope the Engineering ask: harden storage/auth, expand to all 28 tables, add proper
   audit trail of who confirmed what mapping and when.
3. Decide whether the "learns across customers" mapping library should be scoped per
   source-system-type only, or also incorporate signals across CaseWorthy's broader
   customer base — a data governance question, not a technical one.

## Source files referenced in this work (re-upload if starting fresh)

- `00_Staging_EXCEL_Validation_Script_v3__1_.sql` — authoritative validation rules
- `Sample_Staging_With_Data.xlsx` — sample target schema with non-real sample data
- `etl-schema-mapping-poc.html` — the working POC itself
