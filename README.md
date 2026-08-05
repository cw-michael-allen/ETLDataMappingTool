# CW-ETL-FIELDMAP

**Project keyword:** `CW-ETL-FIELDMAP` — use this as the anchor term in Jira, Confluence, or future sessions.

**Status:** Phase 0 built. A working local web app lives in [`poc/`](poc/) — see [`poc/README.md`](poc/README.md) to run it. CaseWorthy is fully supported (28 tables, 282 fields, human-verified); ServTracker's schema has been extracted (40 sheets, 612 fields) but is **not yet signed off**, and the app-side module scoping it needs isn't built. See [Target databases](#target-databases) below.

## Background

CaseWorthy's ETL data migration process for new customers takes 9–12 months against a 90-day target. This project explores AI-assisted tooling to close that gap.

A prior session produced **Tier 0 / Option B**: a no-dev-team, customer-facing proof of concept (single-file HTML/JS artifact) that interviews a customer about their source system's field names and suggests where each one lives in CaseWorthy's target ETL schema — using the Anthropic API directly and a simple learned-mapping store. See [`reference/HANDOFF_ETL_Field_Mapping_POC.md`](reference/HANDOFF_ETL_Field_Mapping_POC.md) for the full handoff notes, known limitations, and open questions from that work.

**Explicit product boundary:** this tool answers "where does field X go," not "is the data in field X valid." Data *validation* against real values is a separate, already-solved problem owned by `00_Staging_EXCEL_Validation_Script_v3.sql`. These two jobs stay separate.

## Reference material (`/reference`)

| File | What it is |
|---|---|
| `00_Staging_EXCEL_Validation_Script_v3.sql` | Authoritative SQL validation script (2,921 lines) — 28 source tables, 328 checks. Source of truth for the target ETL schema (field names, required/optional, list IDs, decode values, FK rules). |
| `Sample_Staging_With_Data.xlsx` | Sample staging workbook: `Users`, `Client`, `Program`, `Enrollment`, `ServiceType` tabs (target-schema aligned) plus `XNewCustomTable` (a customer-custom field set with no target match — test case for "flag for review, don't guess"). |
| `HANDOFF_ETL_Field_Mapping_POC.md` | Handoff notes from the POC build: mechanics, learning/storage design, known limitations, next steps. |
| `etl-schema-mapping-poc.html` | The working POC itself (client-side only, calls `api.anthropic.com` directly, uses Claude-artifact `window.storage` for persistence — not reusable as-is by Engineering). |

## Target databases

| | CaseWorthy | ServTracker |
|---|---|---|
| Target tables | 28 | 33 import tables / 35 sheets |
| Fields | 282 | 540 (484 with at least one rule) |
| Source | `00_Staging_EXCEL_Validation_Script_v3.sql` (frozen v3, committed here) | `1 - Master Validation.sql` + 18 Excel templates (live, [not committed](reference/SERVTRACKER_SOURCES.md)) |
| Validation checks | 328 | 785 (all parsed, 0 unreadable) |
| Human sign-off | ✅ Russ, 2026-08-04 | 🟡 findings adjudicated 2026-08-05; final review open |
| Usable in the app | ✅ | ⚠️ schema loads; module scoping not built |

ServTracker's extraction is regenerable via `tools/extract_servtracker_schema.py`
and produces [`reference/servtracker_extraction_report.md`](reference/servtracker_extraction_report.md),
which lists every disagreement between the two sources for adjudication rather
than guessing at a resolution.

**Why ServTracker needs more than a schema drop-in:** it's 18 program-area
workbooks, not one, and column names repeat heavily across sheets —
`ClientImportId` appears on 32 of 35, because it's the key the import uses to
link a client across sheets. Without scoping the candidate set to the modules a
customer is actually migrating, suggestions tie across dozens of sheets. The
link key is flagged (`linkKey`) so the UI can *teach* it rather than treat it as
noise. See [`docs/PHASE_PLAN.md`](docs/PHASE_PLAN.md).

## Schema coverage

**Full 28-table coverage extracted.** [`reference/target_schema_full.json`](reference/target_schema_full.json) holds structured metadata (required/optional, type, ListID, decode values, FK relationships) for all 282 fields across all 28 tables in the validation script — the original POC's 5 tables (Client, Program, Enrollment, ServiceType, Users) plus the 23 extracted afterward (Organization, Provider, ClientRace, AddressHistory, EntityVeteranEra, EntityVeteranInfo, EnrollmentServicePlan, CaseManagerAssignment, CaseNotes, EntityContact, Service, Issue, Goal, Credential, ProviderReferral, FileDocument, WorkHistory, Assessment, AssessFinancialItem, AssessEmploymentPlacement, AssessHUDRHY, AssessDVS, Outcome).

This extraction was done by independent passes over the validation script and was spot-checked and confirmed correct by Russ (owner of the validation script) on 2026-08-04.

## Planning docs (`/docs`)

- [`PHASE_PLAN.md`](docs/PHASE_PLAN.md) — the phased development plan (POC → leadership approval → engineering build → production hosting), including locked-in decisions, explicit non-goals per phase, and open risks.
- [`JIRA_OUTLINE.md`](docs/JIRA_OUTLINE.md) — epic/story outline per phase, for manual creation in Jira once the plan is approved.

## Next

1. **Sign off the ServTracker extraction** — work through the "Needs adjudication" section of [`reference/servtracker_extraction_report.md`](reference/servtracker_extraction_report.md) (Alex Button).
2. **Build ServTracker module scoping** — a program-area multi-select on Step 1, gated so CaseWorthy's flow is unchanged, plus first-class handling of `ClientImportId` as the documented cross-sheet link key.
3. Phase 1 leadership approval package per [`docs/PHASE_PLAN.md`](docs/PHASE_PLAN.md).
