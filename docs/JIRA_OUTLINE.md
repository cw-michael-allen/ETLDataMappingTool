# CW-ETL-FIELDMAP — Jira Outline (for manual creation)

Not created in Jira yet, per instruction — this is an outline for manual entry once the phase plan is approved. Suggested label/keyword on every issue: `CW-ETL-FIELDMAP`.

## Epic: CW-ETL-FIELDMAP — Phase 0: 30-Day Local POC

- **Story:** Extract full 28-table target schema from `00_Staging_EXCEL_Validation_Script_v3.sql` into structured data (required/optional, ListID, decode, FK rules).
- **Story:** Build local backend + persistent local datastore (e.g. SQLite) for the mapping interview flow and learned-mapping library.
- **Story:** Port the interview/suggestion/confirm/override/flag UI flow from the original artifact POC to the new local app.
- **Story:** Implement rule-violation warnings at mapping time (required/list/decode/FK mismatches) using the extracted target schema — new scope beyond the original artifact POC.
- **Story:** Implement per-source-system mapping storage with a cross-system boosting index (shared-but-tracked-by-source-system model).
- **Story:** Abstract the LLM call behind a swappable interface/config in place of a hardcoded direct Anthropic call, so Phase 2 can wire in the internal gateway without a rewrite.
- **Story:** Build export/summary flow (carried over from original POC).
- **Story:** Prep leadership demo script/data and known-limitations list.

## Epic: CW-ETL-FIELDMAP — Phase 1: Leadership Approval

- **Story:** Build approval one-pager/deck (business case, demo, limitations, ask).
- **Story:** Run leadership demo and capture approval/feedback.

## Epic: CW-ETL-FIELDMAP — Phase 2: Engineering Build (Company GitHub, SOC2/HIPAA)

- **Story:** Stand up repo on Company GitHub with required CI/compliance scaffolding.
- **Story:** SOC2/HIPAA compliance review — encryption in transit/at rest, secrets management, access controls, data retention/deletion policy for the mapping library.
- **Story:** Build authentication for both internal-consultant and customer-facing modes (customer-facing prioritized).
- **Story:** Integrate with the internal LLM gateway for cost control (blocked on gateway details being identified).
- **Story:** Select and implement production datastore.
- **Story:** Build audit trail — who confirmed which mapping, and when.
- **Story:** Data governance sign-off on cross-customer mapping-suggestion boosting (per source-system-type scope).
- **Story:** Schema-maintenance process for keeping the 28-table target schema in sync with CaseWorthy's evolving product schema.

## Epic: CW-ETL-FIELDMAP — Phase 3: Production Hosting & Operations

- **Story:** Determine and provision hosting environment.
- **Story:** Define ongoing schema-maintenance ownership and cadence.
- **Story:** Define support process for the "flag for consultant review" path.
- **Story:** Monitoring/metrics for mapping-library growth and suggestion quality.
