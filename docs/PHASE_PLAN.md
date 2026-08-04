# CW-ETL-FIELDMAP — Phased Development Plan

**Status:** Draft for review. Nothing in this document has been built yet except where explicitly marked.
**Audience:** Leadership (approval) and Product Engineering / Dev team (execution).
**Last updated:** 2026-08-04

## 1. Business case

CaseWorthy's ETL data migration process for new customers takes 9–12 months against a 90-day target. This tool is one piece of AI-assisted tooling aimed at closing that gap: it interviews a customer about their source system's field names and tells them where each one lives in CaseWorthy's target ETL schema, learning from prior mappings over time.

## 2. Product boundary (fixed, not up for revisiting per phase)

- This tool answers **"where does field X go, and does my source field's *shape* look compatible with the target rule?"** — not **"is the data in field X actually valid?"**
- It never ingests real client data — only field names, formats, and structural metadata.
- It does not call `00_Staging_EXCEL_Validation_Script_v3.sql` directly. Instead, the rules that script enforces (required/optional, ListID + decode values, FK relationships, type/length constraints) are extracted once into structured target-schema data, and used to warn a consultant/customer at *mapping time* if a proposed mapping would obviously violate one of those rules (e.g., mapping a field the customer says is optional onto a target field that's required, or a source field's stated format not matching an expected decode list). Real-value validation against actual imported data stays the job of the existing SQL script, permanently.

## 3. Phase 0 — 30-day local POC

**Deadline:** 30 days from kickoff.
**Goal:** A working, demoable local application that proves the full concept — not just the 5-table slice from the prior artifact-based POC — well enough to take to leadership for approval to hand to Engineering.

**Locked-in decisions for this phase:**
- Runs entirely locally (developer machine), not deployed anywhere.
- Small local web app — a lightweight backend plus a real local datastore (e.g. SQLite) — not a browser-only artifact, so the learned-mapping library actually persists across restarts and the build is a closer preview of what Engineering will extend.
- **Full 28-table target schema** extracted from the validation script (up from the prior POC's 5 tables), including required/optional, ListID, decode values, and FK relationships per field. *(Extraction in progress as of this writing — see `reference/target_schema_full.json` once merged.)*
- **No authentication.** Auth is explicitly deferred to Phase 2 as a hard engineering requirement, not something the POC needs to demonstrate.
- LLM calls continue to hit the Anthropic API directly, but behind a small internal interface/config (e.g. a single `suggestMapping()` call site) so swapping in a real internal cost-control gateway later is a contained change — not a rewrite. **No internal gateway exists yet to target for the POC itself.**
- Mapping-rule violations (required/list/decode/FK mismatches detected from the extracted schema) surface as warnings during the interview/mapping flow — this is new scope beyond the original artifact POC, per the "prevent a customer from breaking the rules" requirement.
- Learned-mapping library: tracked per source system (primary key), with a secondary cross-system index that can boost confidence/suggestions using patterns seen across other customers — same design as the original POC, now on real persistent storage.

**Explicit non-goals for Phase 0:**
- No real authentication or role separation (internal vs. customer-facing) — UI can *demonstrate* both perspectives narratively, but doesn't need real access control.
- No SOC2/HIPAA controls — those apply to the Phase 2+ product build, not the local POC.
- No integration with a real internal LLM gateway.
- No decision on final production datastore or hosting — POC's local SQLite choice is not a commitment for production.

**Exit criteria:** Demoable end-to-end flow (source system → field list → mapping suggestions across all 28 tables → rule-violation warnings → confirm/override/flag → summary export) that leadership can approve to hand to Engineering.

## 4. Phase 1 — Leadership approval package

- Package the Phase 0 POC as a demo, plus a one-pager / deck covering: the business case, what the POC proves, known limitations (explicitly including anything still open at the end of Phase 0), and the ask (approval to move to Engineering-owned build).
- Not yet built — to be scheduled once Phase 0 nears completion.

## 5. Phase 2 — Engineering handoff (Company GitHub, SOC2 / HIPAA)

This is where the tool moves from a local proof of concept to a real, compliance-reviewed product, owned and built by the Product Engineering team, hosted on the Company GitHub.

**Hard requirements for this phase (from stakeholder direction, not assumptions):**
- **Compliance:** must meet SOC2 and HIPAA requirements before/through this build — encryption in transit and at rest, secrets management, audit logging, access controls, and a data-retention/deletion policy for the mapping library all need explicit design here, even though the tool itself only stores field names/metadata (no real client data).
- **Auth:** real authentication supporting **both** an internal-consultant mode and a customer-facing mode, with the **customer-facing mode prioritized** as the more important of the two.
- **LLM gateway:** LLM calls must go through CaseWorthy's internal API gateway for cost control (gateway details TBD — to be supplied by whoever owns that infrastructure).
- **Datastore:** production datastore choice is open — pick whatever best fits the hosting environment and the engineering team's standards; no constraint carried over from the POC's SQLite choice.
- **Audit trail:** track who confirmed which mapping and when (flagged as a known gap in the original POC handoff notes).
- **Full 28-table coverage** carried over from Phase 0, plus a maintenance plan for keeping the target schema in sync as CaseWorthy's own schema evolves.
- **Cross-customer learning governance:** the mapping library is tracked per source system, but suggestions can be boosted using patterns from other customers on the same source system — this needs a lightweight data-governance sign-off restating that scope explicitly (already decided; documenting it here so it isn't re-litigated later).

**Open/unknown as of this writing:**
- Where the production tool will actually be hosted.
- Which internal gateway to integrate with, and its interface.
- Final production datastore.

## 6. Phase 3 — Production hosting & operations

- Owned by the Product team once Engineering ships it. Hosting environment currently undetermined — no target date, unlike Phase 0/2.
- Ongoing responsibilities: keeping the 28-table target schema current as CaseWorthy's product schema changes, monitoring the learned-mapping library's growth/quality, and any customer-facing support process for the "flag for consultant review" path.

## 7. Risks / dependencies to track

- Full 28-table rule extraction is a manual/semi-automated read of a 2,921-line SQL script — accuracy of required/list/FK rules directly determines how trustworthy the "prevent rule-breaking" warnings are. Recommend a spot-check pass by someone who knows the validation script well (e.g. Russ) before Phase 1 demo.
- No internal LLM gateway identified yet — Phase 2 cannot fully close out cost-control requirements until that's resolved.
- Final hosting environment for Phase 2/3 is unknown, which limits how specific the compliance design can get until it's picked.
