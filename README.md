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

## Schema coverage so far

The POC's `TARGET_SCHEMA` covers 5 of the script's 28 tables: **Client, Program, Enrollment, ServiceType, Users** (~70 fields). The other 23 tables in the validation script (Organization, Provider, Client Race, Address History, Entity Veteran Era/Info, Enrollment Service Plan, Case Manager Assignment, Case Notes, Entity Contact, Service, Issue, Goal, Credential, Provider Referral, File Document, Work History, Assessment + 4 sub-assessment tables, Outcome) are not yet extracted into structured target-schema data.

## Next

Phased development plan — to be defined. See open questions raised in chat before any phase scope is finalized.
