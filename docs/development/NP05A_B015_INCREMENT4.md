# B-015 / NP05A — immutable substitution proposals and planning preview

2026-11-16. Own branch `build/codex-np05a-sweets`, Draft PR #112. Reservation used: **0503**, inside 0500–0599. Latest integration trunk incorporated: **e450010** (NP06 Finance GO-F1 integration). Migrations 0500–0502 are unchanged.

## Working domain scope

`0503_np05a_recipe_substitution.up.sql` / matching `.down.sql` add recipe-version-specific alternative ingredient/packaging proposals. They reuse canonical item IDs, existing recipe/component scope, Auth, Control, command receipts and Audit. No additional item/UOM/permission/approval/Stock/Money engine.

- `mfg_define_substitution_v1(...)`: scoped Owner defines an immutable alternative only while the recipe is draft. The source line, alternative item, quantity for full replacement, declared UOM reference, estimated unit cost, expected waste, maximum percentage, reason/note, actor and canonical Audit are recorded. Quantity/cost/percentage precision and ranges are checked; cross-business items, finished item and items already in that BOM are rejected. A recipe/line/alternative pair can be defined once; corrections require a new recipe version.
- `mfg_recipe_substitutions_v1(business,site,recipe)`: scoped read of source components, proposal history and effective policy.
- `mfg_preview_substitution_v1(business,site,rule,multiplier,replacement_pct)`: pure non-posting preview of original remainder, proposed alternative quantity, unchanged components, output plan and manual-rate cost variance. Quantities must fit six decimals without silent rounding. No batch selection, UOM conversion, availability/shortage calculation or stock issue is implied.

For an illustrative recipe containing 10 kg milk plus 10 boxes, an Owner proposal can declare 2.5 kg powder for full replacement, capped at 50%. At two batches and 50% replacement: 10 kg original milk remains, 2.5 kg powder is proposed, and 20 boxes remain unchanged. With fictional manual rates, baseline 1800 BDT becomes 1500 BDT. This is declared recipe math, not a certified conversion or recognized cost.

Control feature **mfg.recipe_substitution** is in the existing bilingual catalog. Editable defaults: enabled, zero stages, max replacement 100%, packaging allowed. The immutable rule can impose a tighter percentage cap; preview also respects the current Owner cap and packaging switch. Nonzero configured stages refuse with `NOT_CONNECTED:APPROVAL_COMPLETION`. The writer is registered `enforced`, with CI-run disabled-feature proof. Canonical one-use exceptions are consumed once, not bypassed or duplicated.

## Approval and historical safety

The recipe approval RPC retains its existing signature and exact canonical Auth/Control path. Maker/checker now excludes both the original recipe creator and any substitution-rule author when that policy is enabled. A rule author cannot approve merely because someone else created the recipe.

A new private `_mfg_substitution_check_v1(recipe)` refuses approval with `NOT_CONNECTED:MASTER_SUBSTITUTION` whenever proposals exist, until a verified canonical Master adapter is bound. The original `_mfg_master_check_v1` still fails closed first when original item/UOM validation is absent. Nothing treats a function/table name being present as an accepted provider.

The public editor locks the recipe, rechecks scope and effective Control after waiting, then validates replay/state before writing. Approved recipes cannot receive new alternatives; insert/update/delete/truncate guards enforce immutability. All failures roll back domain and canonical Audit/receipt together.

The handoff source includes `recipe_substitution_rules` with Audit references and **substitution_selected=false**. Original BOM item/quantities and batch planning cost remain unchanged. Receivers must never interpret proposals as actual material consumption or receipts. Rollback restores the prior approval/handoff definitions only when no proposal, Control or new source history exists.

## Bangla/English inspection

Recipe → **বিকল্প উপকরণ / Substitutions** opens a normal proposal form and version/Audit history. **পরিমাণ ও খরচের preview** shows declared quantities and estimate changes, with explicit Master and batch-selection limits. Existing Central shell/navigation untouched.

The form retains its command key across lost responses. The browser test lets real SQL save a proposal, deliberately drops its response, retries identical inputs and proves the same key returns one proposal. Successful saves refresh the rule history; a refresh error preserves the saved Audit acknowledgement. Existing waste and context-disposal retry behavior is retained.

## Actual verification

All listed local checks PASS on disposable PostgreSQL 17, synthetic subject claims only:

- Initial 31 migrations up/down/up on `fe1c6b6`; after the Finance trunk advanced, **32 migrations up → full down → up**, including 0400. Static contract 6/6 and signed-scope client tests 6/6.
- Existing manufacturing, requirements/source, material-waste, canonical Control, NP02 Master-table and canonical NP06 Finance SQL suites.
- New `tests/np05a/substitution-e2e.sql`: real production draft authoring/preview before any Master fixture; rule replay/conflict, duplicate pair, exact quantities/cost delta, no silent rounding, scope/item/line checks, current policy cap, packaging switch, disabled reads/write/replay, one-use exception and approval-stage gate.
- Recipe approval explicitly fails against the unmodified Master hook. Replacing only the original hook with the existing test fixture still fails `MASTER_SUBSTITUTION`. Only the later approval/immutability/source tests install the separate **test-only** `substitution-fixture.sql` inside their rolled-back transaction. It is not canonical UOM/item validation, production equivalence or a hidden production adapter.
- Recipe/rule maker-checker, immutable approved versions, old BOM batch cost and original-item handoff, proposal Audit IDs, no stock mutation, cross-scope and denied/revoked/expired roles.
- Existing replay, Control/revocation waits, waste-cap races and guarded rollback tests.
- New `tests/np05a/substitution-race.sh`: simultaneous same-key calls create one proposal; different keys for the same pair produce one success/one controlled conflict. Actual recipe-row waits observed through pg_stat_activity; Owner disable or revocation refuses the waiting writer without a receipt. History-protected rollback.
- Combined Control registry/evidence: 36 callable mutations, **18 enforced / 7 exempt / 11 upstream pending**; NP05A now contributes nine enforced writers.
- **62 Chromium checks PASS at 390/1440** against the latest combined SQL: rule form, committed-response-loss exact-key retry, one rule/history entry, planning preview, no overflow, existing material/waste flows, language, denied-role and context disposal. Screenshots in `np05a-evidence/substitution-*.png`, results `increment4-results.json`; CI uploads its own exact-HEAD artifacts.

Exact pushed SHA and CI results/URLs are recorded in Draft PR #112 and B-015, never inferred from file existence. No signed GoTrue/16-persona or hosted certification claimed.

## Canonical port status / concrete integration request

Latest checked trunk `e450010` includes NP02 0150 tables and integrated Finance foundation 0400. Source inspection of `NP06_B013_FINANCE_FOUNDATION.md` confirms that its accepted writer is a canonical draft-journal boundary; manufacturing valuation/COGS ingestion is not a verified receiver. NP05A does not choose accounts or turn estimates into a journal. Stock B-012 remains planned; NP02 0151 converter/item validation is absent at this checkpoint.

NP02/NP01 integration request (also recorded on B-015): supply verified active/versioned original and alternative item/UOM validation; NP05A will bind `_mfg_master_check_v1` and `_mfg_substitution_check_v1` in a forward migration. Culinary replacement quantities remain an Owner-approved recipe rule, not a universal kg/pieces conversion. Then source-linked Approval completion, canonical batch substitution selection/Stock issue-return/reversal, Money valuation and Central-shell route must be wired and tested by their respective ports. No shared-source changes are applied here.

**CODED / TESTED planning increment; full S6 BLOCKED / NOT READY_FOR_INTEGRATION / NOT VERIFIED_COMPLETE.** Co-products/over-yield, capacity/routing/WIP/subcontract/downtime and signed end-to-end certification remain unfinished.

Safety: own-branch development, disposable testing and Draft PR/own Board fields only. No hosted Supabase apply, staging seed/users, Cloudflare deployment, PR merge or IMG-ERP-SG access. Decision Book NOT WRITTEN: existing scope implemented, no new Owner policy decision.

Owner QA: রেসিপি → বিকল্প উপকরণ → পরিমাণ/একক/সর্বোচ্চ শতাংশসহ খসড়া নিয়ম দিন → preview-এ গুণক ও শতাংশ দিয়ে মূল/বিকল্প পরিমাণ এবং আনুমানিক খরচ দেখুন। এটি development surface; বাস্তব ব্যাচে বিকল্প বাছাই বা stock issue নয়।
