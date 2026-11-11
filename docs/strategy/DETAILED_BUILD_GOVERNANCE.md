# Detailed module build and no-loss research preservation

The one authoritative Decision Book remains https://docs.google.com/spreadsheets/d/1IYzGBtUVNjah31cPVSFHkzgO7P093jTfZS0CopWrDxs/edit . This package adds supporting tabs to that same workbook; it creates no competing policy register and approves no new statutory/legal/release policy.

## What changed

Earlier E059/E060 and discussion/change entries recorded research and implementation summaries. The complete research documents and row-level feature planning were not yet embedded in the Book. Six linked supporting tabs now preserve the full available research texts, original capability fields, all 116 candidate identifiers, all 129 locked requirements plus their historical implementation note, and atomic build details for every original capability.

| Tab | Purpose |
|---|---|
| RESEARCH ARCHIVE | Full available source documents stored in ordered chunks with reconstruction hashes, not summaries replacing the originals |
| CAPABILITY REGISTER | All original 32 capability rows and every original field preserved |
| SOURCE TRACE | Every original candidate ID linked to its parent and atomic details; parent mapping is not semantic certification |
| REQUIREMENT TRACE | Original R001-R129 wording/acceptance plus R124 implementation note, live row link and build mapping |
| MODULE BUILD DETAIL | One atomic feature per row, with workflow, expected result, exceptions, evidence, gap, source and completion gates |
| MODULE DELIVERY | Build order, dependencies, current evidence and entry/exit criteria for every parent module |

## Build one coherent module at a time

For the selected module: freeze its supported feature list and upstream contracts; inspect/reuse current code; implement durable schema and signed API; connect guided UI; generate source-linked reports; verify exact calculations and audit; run role/tenant/site denial, stale/replay, concurrent execution, recovery and mobile/desktop tests; run the connected upstream/downstream journey; then record commit/PR, test environment and evidence for each atomic detail. Continue until all in-scope items are evidenced or explicitly blocked; do not silently drop a feature to call the module complete.

The first next core build remains business setup/login/effective-permissions integration. HR is expanded now as a complete planning example and retained as its own implementation workstream; planning HR does not silently replace the agreed dependency order or another agent's ownership.

Every significant action must explain what/when/why, normal recommendation, consequences, approval/exception route, safe example, calculation/source/version where relevant and result/report destination in Bangla/English (R128). Each feature closes only after UI → signed API → canonical storage/event → audit → report evidence. A feature may be supported in code/demo while real GoTrue staging or release remains separately pending.

## Honest source and status boundaries

All atomic rows begin `PLANNED_DETAIL_NOT_CERTIFIED`; an aggregate module test cannot automatically certify every newly expanded detail. Existing code evidence and remaining gaps are separate columns. `proposed-extension` rows are engineering proposals, not newly approved Owner decisions. Jurisdictional rates, purge/payment actions and regulated-sector release retain explicit gates.

The original registry is a dated research snapshot, so it is preserved without rewriting historical claims. Current module evidence reflects PR74 preview integration. The live Book now contains REV-010/R087: **Claude Code only may implement the isolated simulation draft now**, while runtime integration/release stays gated by the original major-package/P0 conditions. A024 commercialization remains deferred. Both scopes are retained explicitly alongside the original 32 capabilities, rather than omitted or wrongly represented as unrestricted Codex work.

The validation proves finite-source preservation: each original research candidate, locked requirement, parent capability and archived character is retained. It does not prove that every possible worldwide ERP feature has been discovered, that parent mappings capture every nuance, or that the system is fully implemented. New discoveries receive a stable detail ID, source, disposition and tests rather than disappearing into prose.

Generate and validate with:

```sh
node internal/build-plan/build.js
node tests/demo-factory/core10-detailed-build-plan.test.js
```

Source input JSON files and generated `DETAILED_BUILD_REGISTER.json` are reproducible implementation/planning artifacts, not an alternative Master Decision Book. Refresh snapshots from the live Book before future planning revisions; preserve history and verify native workbook readback before reporting a successful upload.
