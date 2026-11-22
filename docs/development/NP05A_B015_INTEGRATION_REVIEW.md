# B-015 / PR #112 — independent integration review package

2026-11-19 (Asia/Dhaka). Branch `build/codex-np05a-sweets`; target `ccr-15ed11dd-n3hw5h`. Owner accepted production code at **86851dc4a09bb71c051e3fb82b8fddc9d0b4ec1b** as CODED + TESTED. This preparation changes only tests, own CI and evidence/documentation. It does not recreate Master integration or introduce 0505.

**INDEPENDENT REVIEW NOT REQUESTED YET — required CI gate is blocked.** This is the author's review preparation, not an independent approval. PR remains Draft/BLOCKED; no merge without separate Owner GO. Exact current pushed SHA/check links and review status are maintained in PR #112 and Board B-015; restart from those live records rather than assuming an old green checkpoint is current.

## Verified base, checksums and shared-owner gates

Actual fetched integration trunk: **a82ae993b93c1460898b9022bb56b7a995d96437**, already an ancestor of accepted HEAD. Master0151–0153, Stock0200 and Finance0400–0401 present. There is no additional approved trunk commit to merge at this checkpoint.

All **ten** up/down files for0500–0504 match the Owner-accepted86851dc bytes. Baseline: `tests/np05a/0500-0504.sha256`, checked by own Manufacturing CI. The historical0500–0503 manifest remains preserved. No migration content/filename/checksum was altered and no0505 exists. Migration reservation remains0500–0599; B-015 is still our own branch/scope. `OUT_OF_ORDER` and persistent apply-order restrictions remain in force.

Finance's correction is **Draft PR #118**, not integrated into the approved trunk when checked (head `d54ca632278467fe01cb5f5444d5791c6e232a65`). Its moving review/CI status is not a passed Manufacturing integration gate. Live NP01 PR111 head was `69143ffb82667b6f81b3667288af54a86b597698`; shared Finance workflow still pins `c858084d0d5a80b752637c30fd7c9199dc8455a5`. Shared workflow also still calls generic highest-version rollback for its Finance0401 history assertion. Owner assigned **both** corrections to Finance lane.

No Finance workflow, migration runner, upstream migrations or other builder branch is edited here. Do not merge/cherry-pick the draft correction, weaken its reviewed-SHA guard, rerun until a random green result, or make Manufacturing down raise a fake Finance error. Once an approved correction reaches trunk, merge trunk into **this branch**, recheck all ten checksums and run all exact-head workflows before requesting independent review.

## Focused reviewer matrix

Read the **last definition** of an RPC in numbered migration order; earlier forward definitions are intentionally preserved. Final approval/release definitions are in0504, create/plan/output/cancel/handoff in0501, source envelope in0503.

| Review concern | Source to inspect | Executed proof / expected boundary |
| --- | --- | --- |
| Recipe creation and version allocation |0500 recipe/line tables and guards;0501 `mfg_create_recipe_v1` | `manufacturing-e2e.sql`, `lock-wait.sh`: input/precision validation, same-key replay vs payload conflict, per-code allocation lock, effective/superseded versions; no new item master. |
| Approval and immutable history |0503 alternative maker/checker;0504 `mfg_approve_recipe_v1` | `substitution-e2e.sql`, `canonical-master-e2e.sql`: creator/rule-author separation, current Master checks, nonzero-stage denial, approved recipe/rule immutability, recipe version2 and audit-linked replay. |
| Material requirements and cost |0501 `_mfg_material_plan_v1`, `mfg_material_requirements_v1` | `material-handoff-e2e.sql`: scale each line independently; no adding mass to count; packaging/waste separate; unknown availability/shortage stays NULL; manual-rate cost is UNVERIFIED_PLANNING_ESTIMATE. |
| Alternative rules and preview |0503 immutable rules/define/v1 preview;0504 v2 preview | `substitution-e2e.sql`, `substitution-race.sh`, `canonical-master-e2e.sql`: draft-only, one pair, caps/packaging feature/precision, author/Audit; ratio is declared by recipe, never culinary equivalence or batch selection. |
| Canonical item and unit validation |0504 private helper/check/lock, validation report and preview_v2; upstream0151 ports | Real `master_item_usable_v1(business,item)` and `master_uom_convert_v1(business,from,to,quantity)`; explicit `master:ID`, active/scoped physical item/base unit, dimensions/direct/inverse factors/decimals; inactive/missing/foreign values refuse. No replacement provider in production. |
| Auth and tenant/business/site isolation |Existing `_mfg_scope_v1` in0500; every public caller | SQL negatives and client tests: signed subject required, canonical `can_manage` and `can_site(...,'stock.read')`; cross-tenant/business/site, role, revoked/expired and private/direct access denied. Owner-only manufacturing scope until canonical manufacturing actions exist. Synthetic claims are not hosted GoTrue proof. |
| Owner Control |Canonical `control_check_v1` / resolver and `_mfg_control_fresh_v1` in0501; final callers0504 | Disabled feature checked before replay; typed caps/stages and one-use exception; new immediately-effective Control while waiting forces retry. Nine Manufacturing writers are registered enforced. New Master APIs are STABLE reads behind existing feature controls. No private policy engine. |
| Canonical Approval |Existing Control catalog approval bindings; explicit stage checks | Nonzero-stage operations raise `NOT_CONNECTED:APPROVAL_COMPLETION`. Zero-stage domain authorization is not completion of a GOV-002 workflow. No local approval journal, no implied automatic approval of posting. |
| Canonical Audit |0500 `_mfg_receipt_v1` using `_append_canonical_audit_v1`; immutable domain Audit IDs | SQL suites verify canonical chain, exact actor/payload replay, failed mutation atomicity. Browser handoff verifies receipt's canonical event, every referenced recipe/batch event in scope, recipe/version linkage and PostgreSQL-jsonb fingerprint. Command receipts are replay/source evidence, not an alternate audit chain. |
| Real concurrency |0501 command/recipe/row locks,0504 ordered Master SHARE locks and post-wait checks | `concurrency.sh`, `lock-wait.sh`, `waste-race.sh`, `substitution-race.sh`, `canonical-master-race.sh`: real sessions, observed waits, once-only effects, caps, fresh Auth/Control and committed Master disable. Not simulated promises. |
| Rollback protections |Matching0500–0504 down files | Empty PG17 all38 up/down/up; history-bearing0500–0503 down refuses;0504 owns no new history and restores previous fail-closed bindings without deleting recipe/receipt/Audit. Savepoint test proves read removal/recovery with existing history. |
| Stock/Money/staged-Approval fail closed |0501 `mfg_request_handoff_v1`,0503 source envelope; unchanged internal upstream ports | Original SQL covers ingredients/finished_goods/finance requests, missing valuation/journal, stage denial and controlled-reversal refusal. Browser compares complete canonical Stock/Money rows before/after non-posting previews and guarded Finance requests. No real source receiver success asserted. |

Tests referenced without a directory prefix are under `tests/np05a/`. Shared contract/registry/security/migration suites live under `tests/migrations/`.

## No duplicate canonical engines

The only NP05A-created tables are `bom_recipes_v1`, `bom_ingredients_v1`, `production_batches_v1`, `mfg_command_receipts_v1`, `mfg_material_waste_v1`, `bom_substitution_rules_v1`. They are domain records and replay/source references. They reference existing tenant/business/site/item/location identities. No own grants, item/UOM/party master, inventory balance/movement/lot ledger, finance journal/valuation ledger or approval journal exists.

Manufacturing SQL does not call `post_stock_event`, `transfer_stock_v1`, inventory-command posting, `finance_draft_journal_v1`, `finance_post_journal_v1` or reversal writers. Receiving a domain `released`/`recorded` state or Audit receipt does not imply Stock issue/receipt or recognized valuation. Waste events are observations **inside** recorded consumption; no additional movement, journal or cost is inferred.

Source envelopes retain `PROPOSED_NOT_CONNECTED`, `master_uom=NOT_CONNECTED`, NULL unavailable base/recognized/journal quantities, `substitution_selected=false`, and all posting booleans false. A newer live Master validation report does not retroactively certify an old envelope, lot reference or culinary ratio.

## New readiness evidence and reproducibility

Own CI: `.github/workflows/core10-np05a-manufacturing-ci.yml`. It already runs PG17 full migration roundtrip, static/client contracts, all Manufacturing SQL suites, Control registry/evidence, real races, old browser and real Master browser. This increment extends its checksum check through0504 and expands the existing `master-browser.cjs`; production RPC/UI code is unchanged.

New browser evidence compares **complete row snapshots** for `stock_movements`, `stock_balances_v1`, `stock_transfers_v1`, `finance_accounts_v1`, `finance_periods_v1`, `finance_journals_v1`, `finance_journal_lines_v1`, `finance_reversals_v1` before/after the scenario. It verifies four UI handoffs (bn/en at390/1440) retain source fingerprint across distinct request receipts, reference the right batch/recipe version and actual canonical Audit events, and show NOT_CONNECTED without recognized value/journal entries. Test SQL reads are disposable-admin inspection, not API authorization bypass in production.

Local results: static6 + client7 PASS; all ten migration checksums PASS; expanded canonical Master/source browser **95/95 PASS** at390/1440. Prior62-check lifecycle browser remains in CI. Fresh exact-head CI is required for this new coverage; previous86851dc five green checks plus shared Finance red are historical evidence, not certification of the new commit.

Artifacts: `np05a-evidence/readiness-results.json`, `source-handoff-bn-390.png`, `source-handoff-en-1440.png`. Results contain synthetic source/Audit IDs, fingerprint, snapshot digest and checked table names; no hosted records. CI uploads its independent current-run artifacts. Local screenshots/IDs need not match a fresh database's sequences.

To reproduce on a **fresh disposable PG17 only**, follow the own workflow steps in order. In particular:

1. Create local synthetic API roles; verify `sha256sum -c tests/np05a/0500-0504.sha256`; run static/client contracts and full up/down/up.
2. Run transaction-scoped SQL suites and capture production `_mfg_master_check_v1` / `_mfg_substitution_check_v1` definitions as specified in CI **before** persistent legacy race fixtures replace a hook.
3. Run existing concurrency/wait/waste/substitution and Finance boundary proofs; old lifecycle browser uses an explicit test-only Master fixture. Restore exact captured production definitions with `canonical-master-live.sh`; seed real Master RPC fixture and run real Master races.
4. Run expanded `master-browser.cjs` with local gateway and synthetic subject. Canonical Master preview/report uses real0151–0153 functions. Recorded RACE batch used for the unverified Finance envelope came from the explicit legacy lifecycle fixture; it is **not** real canonical lot/production certification. No test adapter is installed by migrations.

Do not rerun seed scripts against an already-seeded database expecting fresh IDs. Use a new disposable database for a full repeat. Finance's published synthetic tenant IDs overlap NP05A's, so its independent shared SQL suites use a separate fresh DB as documented in Increment5. No persistent/hosted environment is part of this package.

## Risks, review gate and restart

Remaining risks/limits are explicit: current Master evidence rather than historical Master pinning; manual-rate estimates rather than recognized inventory value; scaled selected/actual quantities and lot/expiry/reversal/source attestation not certified at a production posting boundary; manager/operator manufacturing actions and signed GoTrue16-persona coverage pending; Central-shell route remains an integration proposal. Drafts may contain incomplete refs but approval/strict v2 preview refuse them. v1 unvalidated previews remain labelled; do not use them as a posting contract.

After the Finance correction is Owner-approved and integrated:

- Fetch trunk, PR112, reservations and B015 again. Confirm no ownership/migration collision and merge only approved trunk into own branch with no force-push. Preserve0500–0504 manifest exactly.
- Push own branch; observe **every required check at that exact HEAD**, including Finance normal and reviewed-NP01 compatibility jobs. Record head SHA, base SHA and complete run URLs in PR/Board. A green subset or a local combination with an unmerged correction does not satisfy this gate.
- **Only after all required gates pass**, request a focused independent review of PR112, directing the reviewer to this matrix and residual risks. Record reviewer identity, exact reviewed SHA, findings/disposition and whether any change invalidated that review. Author self-inspection is not independent review. Do not claim VERIFIED_COMPLETE or mark the entire S6 connected.
- Keep Draft until the separate Owner integration/merge GO. No self-merge, hosted apply, GO-2/GO-3, Cloudflare, production, main or IMG-ERP-SG changes.

Current status: **CODED + TESTED domain; REVIEW_PACKAGE_PREPARED; INDEPENDENT_REVIEW_GATE_BLOCKED; NOT READY_FOR_INTEGRATION.** Decision Book NOT WRITTEN; no new policy decision. PR #112/B-015 are the live exact-SHA evidence and continuation point.
