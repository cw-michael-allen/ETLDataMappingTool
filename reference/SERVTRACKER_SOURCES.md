# ServTracker schema sources

`servtracker_schema_full.json` is generated, never hand-edited. It comes from
two authoritative sources, both owned by the CaseWorthy ETL team.

## Sources

| Source | Path |
|---|---|
| Master validation script | `~/OneDrive - CaseWorthy/ETL Team/12. ServTracker/Master Scripts/1 - Master Validation.sql` |
| Master Excel templates (20 workbooks) | `~/OneDrive - CaseWorthy/ETL Team/12. ServTracker/ExcelTemplates/Master Templates/` |

`2 - Master Import.sql` (6,834 lines) is **not** used. It moves validated
staging rows into live ServTracker tables — useful for understanding where data
lands, but it defines no constraints on what the customer submits, which is all
this tool needs.

## Why these aren't copied into the repo

CaseWorthy's own `00_Staging_EXCEL_Validation_Script_v3.sql` *is* committed here
because it's a frozen v3 snapshot. The ServTracker sources are the opposite:
actively maintained, with recent edits across both the script and the templates.
Copying them in would fork a source of truth someone else is still editing, and
the copy would silently rot.

Instead the extractor records a SHA-256 of each source in
`servtracker_extraction_report.md`. Re-running it against the live sources shows
whether the committed schema still matches them.

## Regenerating

```bash
python tools/extract_servtracker_schema.py
```

Both paths default to the locations above; override with `--templates` and
`--validation`. Outputs `reference/servtracker_schema_full.json` and
`reference/servtracker_extraction_report.md`.

## Adjudication log

Decisions by Alex Button (ServTracker schema owner), 2026-08-05. Recorded here so
they aren't re-litigated and so the extractor's exclusions are traceable.

| Question | Decision |
|---|---|
| `Case Managers` renamed to two tables | Only `CaseManagerImport` is correct; `CaseManagersImport` is commented-out legacy. Fixed by stripping SQL comments before parsing. |
| Adult DayCare module | Scripting badly out of date — **do not offer the module.** Template excluded. |
| Home Delivered Meal Choice template | Out of date — only the base `ServTracker - Home Delivered.xlsx` is used. Template excluded. |
| Rules for columns no template offers | **Templates are the primary source** of what we offer to migrate; these rules are excluded (still listed in the report for visibility). |
| Client link key | `ClientImportId` is the key customers use to link a client across sheets. `ServTrackerClientId` is only for merging/updating clients already in the database — see `2 - Master Import.sql`'s `#STConfiguration OverwriteClient` block. |
| `N0` in `MedicalReleaseFormSigned` | Typo; fixed at source to `No`. |
| `NoteService` allowed-value check | Not currently needed. |
| Mixed-case allowed values (`YES`/`Yes`) | Non-issue — SQL Server compares case-insensitively. Extractor collapses them to one value. |
| `CaseManagerId` max length 15 vs 20 | Fixed at source to 20 universally. |
| `ClientImportId` max 50 | Should be 20. Traced to a copy-paste bug at line 4332 — a `Site` length check mislabelled `ClientImportId`. Handled by trusting the tested column over the label. |

## Open findings for the source script

Not blockers for the schema, but each is a real defect worth fixing upstream:

- **21 checks never run.** `ClientMembershipDetailImport` (15) and `DestinationsImport` (6) are never created by any `sp_rename` — the real tables are `ClientMembershipImport` and `DestinationImport` (singular). Their `IF EXISTS` guards never fire.
- **8 checks report against the wrong field.** The `FieldName` label disagrees with the column actually tested, so a customer's error report names the wrong column.
- **18 checks state no machine-readable constraint**, including typos like `"Monthly units most be a number"` and `"must be number or left blank"`. Normalising the wording is the cheapest fix.

All three are enumerated with locations in `servtracker_extraction_report.md`.

## Sign-off

**Alex Button** owns ServTracker schema correctness — the counterpart to Russ
for CaseWorthy (who confirmed `target_schema_full.json` on 2026-08-04).

The extraction is mechanical: rules come from the plain-English error messages
the validation script already writes into its `ErrorLog` table, cross-checked
against the template column lists. Where the two sources disagree, the report
records the disagreement rather than guessing — see its "Needs adjudication"
section. Nothing in the schema is inferred beyond what one of the two sources
states.

**Status: not yet signed off.** The report's adjudication items are open.
