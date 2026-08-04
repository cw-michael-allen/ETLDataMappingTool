# CW-ETL-FIELDMAP

**Project keyword:** `CW-ETL-FIELDMAP` — use this as the anchor term in Jira, Confluence, or future sessions.

**Status:** Planning phase. No application code has been written yet — this repo currently holds the source reference material and will accumulate phase plans as they're agreed on.

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

## Schema coverage

**Full 28-table coverage extracted.** [`reference/target_schema_full.json`](reference/target_schema_full.json) holds structured metadata (required/optional, type, ListID, decode values, FK relationships) for all 282 fields across all 28 tables in the validation script — the original POC's 5 tables (Client, Program, Enrollment, ServiceType, Users) plus the 23 extracted afterward (Organization, Provider, ClientRace, AddressHistory, EntityVeteranEra, EntityVeteranInfo, EnrollmentServicePlan, CaseManagerAssignment, CaseNotes, EntityContact, Service, Issue, Goal, Credential, ProviderReferral, FileDocument, WorkHistory, Assessment, AssessFinancialItem, AssessEmploymentPlacement, AssessHUDRHY, AssessDVS, Outcome).

This extraction was done by independent passes over the validation script and has not yet had a human spot-check against someone who knows the script well (e.g. Russ) — see the risk noted in the phase plan before treating every ListID/decode value as gospel.

## Planning docs (`/docs`)

- [`PHASE_PLAN.md`](docs/PHASE_PLAN.md) — the phased development plan (POC → leadership approval → engineering build → production hosting), including locked-in decisions, explicit non-goals per phase, and open risks.
- [`JIRA_OUTLINE.md`](docs/JIRA_OUTLINE.md) — epic/story outline per phase, for manual creation in Jira once the plan is approved.

## Next

Human review of the phase plan and the extracted schema, then Phase 0 build (local web app + full mapping/rule-warning flow) per `docs/PHASE_PLAN.md`.
