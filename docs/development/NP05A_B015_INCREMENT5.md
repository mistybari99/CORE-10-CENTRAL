# B-015 / NP05A — canonical Master binding, restartable increment 5

Owner continuation, 2026-11-18 (Asia/Dhaka). Own branch `build/codex-np05a-sweets`, Draft PR #112 into `ccr-15ed11dd-n3hw5h`. **CODED / locally TESTED; full S6 BLOCKED, NOT READY_FOR_INTEGRATION, NOT VERIFIED_COMPLETE.** Exact delivered SHA and current CI links are kept in PR #112 and B-015. No external release is authorized.

## Source reconciliation and ownership

Starting Owner-verified HEAD: `72f7675a70abc44d8c449cd3e79857b7654833c3`. Fetched trunk `a82ae993b93c1460898b9022bb56b7a995d96437`; merged into this branch without rebase, force-push, conflicts or manual shared-source edits (merge `ba25669af0696b3f08bdedeb4c5d7741af40abb9`). The divergence comprised independent NP05A 0500–0503 work versus trunk Master 0151–0153, Stock 0200 and Finance 0401. No migration-number collision. Existing 0500–0503 up/down bytes remain exactly those at the Owner-verified checkpoint: `tests/np05a/0500-0503.sha256`, checked locally and in own CI.

0504 was absent on the fetched trunk/own branch and was reserved on B-015 within 0500–0599 before implementation. It adds only own-lane RPCs and private bindings; no new item, UOM, Stock, Finance, Auth, Approval or Audit store. Other branches, shared runner, Finance workflow and upstream migrations remain exactly at the merged trunk versions.

## Working Master integration

`internal/migrations/0504_np05a_canonical_master.up.sql` / matching `.down.sql` bind the documented internal NP02 signatures:

- `master_item_usable_v1(bigint business, bigint item) RETURNS boolean`.
- `master_uom_convert_v1(bigint business, bigint from_uom, bigint to_uom, numeric quantity) RETURNS numeric`.

Recipe UOM reference syntax is **`master:<positive bigint UOM ID>`**. Explicit IDs resolve only in the recipe's tenant/business. Strings such as `kg`, `piece`, `fixture:kg`, arbitrary numbers, malformed/overflow IDs are never guessed or rewritten. Existing recipes remain immutable; create a new version with canonical references. Draft storage still allows incomplete references, but validation/approval refuses them.

`_mfg_master_material_v1` reuses the real item-usable and conversion functions. Additional manufacturing checks refuse service items, missing base UOM, wrong tenant/business, inactive item/unit, incompatible dimensions, absent direct/inverse factor, nonfinite quantity, negative quantity and input/base quantity that does not fit the canonical units' decimal precision. No silent rounding and no universal conversion between different ingredients. Kg↔gram and boxes↔pieces require the business's actual canonical factors.

`_mfg_master_check_v1` now validates recipe output and every original ingredient/packaging line. `_mfg_substitution_check_v1` validates each alternative against **its own** base UOM; it does not derive an equivalence between original and alternative. Existing maker/checker, configured stages, feature controls, receipt replay and canonical Audit remain in the original public mutation path. Master row locks are held through the transition; Auth and fresh Control are rechecked after Master waits. Same-key concurrent approval produces one receipt and one linked Audit event.

New read RPCs (signed manufacturing Owner scope; no extra mutation registration needed):

| RPC | Result |
| --- | --- |
| `mfg_master_validation_v1(business,site,recipe,multiplier)` | Current versioned Master evidence for output, original materials/packaging and declared full alternatives, canonical base quantities and direct/inverse/identity conversion metadata. Gated by `mfg.material_requirements`; proposals also require enabled `mfg.recipe_substitution`. |
| `mfg_preview_substitution_v2(business,site,rule,multiplier,replacement_pct)` | Existing recipe-declared replacement/cost math plus strict current Master validation and actual remaining/alternative base quantities. Gated by existing substitution policy/caps. Entire call refuses missing/invalid Master. |

The v1 unvalidated planning preview/read contracts remain unchanged and explicitly NOT_CONNECTED; callers can migrate to v2. Both are non-posting. Estimated manual BDT rates are not canonical recognized valuation. Zero-stage domain approval is tested against real Master; nonzero-stage completion is still NOT_CONNECTED. Existing release revalidates original recipe Master data; future Stock adapters must additionally validate selected and actual scaled quantities/lots at posting time. This increment does not certify that posting path.

Reports represent **current Master versions at a statement snapshot**, not a historical Master snapshot captured at recipe approval. Approved recipe lines/rules, Audit and command receipts remain immutable; changing Master does not silently rewrite them. Consumers must revalidate current Master before new operational effects. Source envelopes remain the immutable proposed v1 envelope with NULL unverified base quantities; they are not retroactively rewritten or promoted to verified Stock commands.

Rollback adds/removes no domain tables or records: it removes the new reads/private helpers, restores exact previous approve/release definitions and fail-closed hooks, preserving recipe/receipt/Audit history. Empty PG17 full roundtrip and transactional rollback with existing recipe history are tested. Rollback cannot grant a disconnected port success.

## Owner inspection

Existing standalone manufacturing development surface, unchanged Central shell/navigation. Per recipe, **Master ও একক যাচাই / Validate Master & units** opens multiplier input and shows current item/UOM/conversion versions and base quantities. The substitution history offers a separate **Master যাচাইসহ preview / Preview with Master validation**. The older unvalidated math preview stays explicitly labelled. Both screens state that Stock/Money/Approval completion remain NOT_CONNECTED.

Fictional example: 1500 grams flour per recipe, one box = ten pieces; two batches give 3000g→3kg and 2 boxes→20 pieces. An independently declared 1kg alternative whose own base UOM is gram gives 2kg→2000g for full replacement at two batches. At 50%, original remainder is 1500g→1.5kg and alternative demand is 1kg→1000g. This is recipe math, **not** a universal flour/substitute conversion.

Screenshots: [Bangla 390](np05a-evidence/master-validation-bn-390.png), [English 1440](np05a-evidence/master-validation-en-1440.png), [verified preview 390](np05a-evidence/master-preview-en-390.png), [preview 1440](np05a-evidence/master-preview-en-1440.png), [actual inactive-item error](np05a-evidence/master-error-390.png). Existing styles reused. 12ui skill read/CLI installed; hosted screenshot review was rejected by automatic approval review because it could export a potentially private repository screenshot. No export bypass; local Chromium evidence used. No claim of 12ui-generated/aligned design.

## Actual verification

Disposable PostgreSQL 17 and synthetic subject claims; no GoTrue/hosted certification:

- **38 migrations up → full down → up**, idempotent reapply PASS, including 0151–0153, 0200, 0400–0401 and 0504. Original eight migration checksum comparisons PASS.
- Static contract **6/6**, signed-context client **7/7** PASS.
- Existing manufacturing, material handoff, waste and substitution SQL suites PASS. One legacy alternatives-fixture assertion now expects the real canonical validator's missing-base-UOM refusal; production guard is not replaced to make that assertion pass. Later legacy lifecycle tests remain explicitly fixture-based.
- `canonical-master-e2e.sql` PASS, using **real Master save RPCs** for synthetic items, units and factors: direct/inverse/identity quantities, versions, disabled read feature, inactive original/alternative item and UOM, disabled conversion, incompatible dimensions, missing references/provider, tenant/business/site/role denial, precision, stage denial, maker/checker from existing regressions, approved version immutability, version 2 creation, approval replay/conflict, Audit chain and zero Stock/Money mutation. History-preserving rollback tested in a savepoint.
- Existing replay/lock-wait/waste/substitution races and exact Finance-0400 history-guard regression PASS.
- `canonical-master-race.sh` PASS: concurrent approval once; actual pg_stat_activity waits on canonical Master rows, committed item/converted-unit disable, revocation and immediately-effective Control change all refuse the waiting approval without a receipt. Direct administrator edits here are disposable lock fixtures, not production adapters.
- Shared NP02 Control, Master tables/RPC, Stock 0200 inventory, Finance foundation/reversal SQL suites PASS. Finance uses a **separate fresh database** because its published synthetic tenant IDs overlap Manufacturing fixtures; the initial same-database seed collision was not a product failure or a passed test.
- Combined Control registry/evidence PASS: **45 state-changing RPCs, 28 enforced / 7 exempt / 10 pending**. Manufacturing contributes its existing nine enforced mutations; the new APIs are STABLE reads.
- Existing browser **62/62** and new canonical Master browser **48/48** PASS, at 390/1440, bn/en reports, strict v2 preview, live inactive-item/disabled-feature UI errors, revoked-role denial, no overflow, no JS errors and Audit verification. The old lifecycle uses an explicitly test-only Master hook. Own CI captures exact production hook definitions **before** that fixture and restores them before new canonical tests; new Master tests/browser use no replacement provider.

CI at the eventual pushed HEAD must be observed, not inferred from local tests. Shared Finance workflow still calls generic `run.sh down`, now targeting 0504 instead of intended Finance0401, so its final history test is expected to remain red until its owner fixes it. The historical increment-4 proposal targeted 0400 and is not an instruction to apply it to the now-0401 test. Owner assigned this correction to Finance lane; no shared edits or skips here. That integration gate remains in force.

## Remaining dependencies and next safe increment

- **Master:** real 0151–0153 item/UOM validation verified on disposable PG17; IDs/current versions only. No universal substitution equivalence, historical Master pinning or actual lot validation claimed.
- **Stock:** 0200 internal balances/posting/transfer foundation integrated and regression-tested. B-012 command/Owner Control/lot/QC source receiver is unfinished; NP05A handoffs remain NOT_CONNECTED, stock_issued/stock_received=false. Never call internal posting directly.
- **Money:** Finance 0400 foundation + 0401 reversal integrated and regression-tested. Manufacturing valuation/COGS receiver remains NOT_CONNECTED; no draft-journal/account selection or estimated-to-recognized posting invented.
- **Approval/Auth:** manufacturing action/persona binding, verified staged completion and source-linked approval adapter unfinished. Restricted existing canonical Owner scope retained; managers/operators not silently enabled.
- **Sales/shell:** no new Sales dependency claimed; Central signed manufacturing route/Owner inspection integration request remains with shell owner. Standalone QA is not integrated ERP.

Next: Finance owner integrates its shared test correction; resync own branch and verify all exact-head CI. Then add only a reviewed upstream-ready manufacturing contract, keeping selected quantities, lots, source attestation/reversals and valuation behind their respective canonical receivers. No self-merge or deployment. Decision Book **NOT WRITTEN**; existing Owner instruction implemented, no new policy decision. Only B-015 own fields may be updated; history preserved.

Safety: no hosted migration, hosted/staging seed or demo account, Cloudflare deployment, main/trunk push, PR merge, production or IMG-ERP-SG access. Disposable synthetic rows only.
