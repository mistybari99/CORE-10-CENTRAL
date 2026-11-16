# NP05A / B-015 — manufacturing increment, 2026-11-16

Status: **CODED / locally TESTED**, isolated domain foundation. **BLOCKED for full S6 integration**, not VERIFIED_COMPLETE. Branch `build/codex-np05a-sweets`, Draft into `ccr-15ed11dd-n3hw5h`; migration block 0500–0599. No hosted mutation or deployment authorization is used.

## Reuse and dependency audit

Mandatory Google sources inspected live: Final Decisions DEC-01..06, Master Decision Book through D062, Board B-015 (located by ID; was OPEN), all twelve MFG Detail rows A246:I257, Code Gap Audit and Change Register CHG-060/061. Latest explicit Owner build instruction overrides historical BUILD PAUSED text and old AGENTS preview-only task. D056 retires the old fixture-schema wording: all engine objects use `core10`.

Historical PR diffs #50, #49, #21, #73 and #108 were downloaded and examined; none cherry-picked or merged. Repository contracts and migration runner read before implementation. Initial trunk `48d7895` advanced to `5598795` during this increment; latest trunk merged into this branch before delivery.

| Source | Finding and disposition |
| --- | --- |
| A027 `internal/enterprise-sql/c10_a027_bom_production_v1.sql` | Present on trunk, absent from numbered installation. Reused its `bom_recipes_v1`, `bom_ingredients_v1`, `production_batches_v1` model/names, per-line quantity scaling, planning cost formula and payload-bound replay intent. Ported into 0500 with version/site scope, six-decimal validation, immutable versions, canonical Control/Audit and new versioned RPC names. Historical direct posting and same-user approval paths are not installed. |
| PR #50 / A049 | On trunk, superseded historical PR. Guarded `production_plan` correctly refuses posting without A027. Preserved; do not create a competing operational order or stock workflow. |
| PR #49 / A048 | On trunk, superseded historical PR. Command lifecycle and keyed atomicity are reusable by B-012. Not yet a numbered source/lot/reversal manufacturing port; no call from this migration. |
| PR #21 / A037 | Side draft. Reused non-posting cost/variance intent and the rule that manual planning rates never certify valuation/COGS. Its `cost_events_v1` / valuation projection belong to NP06 and were not copied. |
| PR #73 / A058 | Side draft; traceability concepts useful, independent quality balances/movements unsafe under current single-ledger contract. Store only explicit unverified lot references in manufacturing evidence; lot validation/expiry/QC remains B-012. |
| PR #108 / NP06 | Examined `83e5f17` diff: source-linked Finance foundation and explicit approval gate. Not on this trunk; manufacturing valuation/COGS adapter unavailable. No finance tables or journals duplicated. |
| Canonical Master | Existing item/business/site IDs are reused with composite FKs. UOM, conversions, substitutes and active item revision validation not implemented upstream. Recipe draft accepts proposed UOM references; approval/release calls a private fail-closed adapter. |

**Installation boundary:** use numbered migrations only. A database already initialized by the historical A027 enterprise installer will deliberately fail on existing tables; do not drop them or load both installers. Reconciliation of that legacy installation is a separate integration task, not an implicit destructive conversion.

## Delivered behavior

`internal/migrations/0500_np05a_manufacturing.up.sql` and matching `.down.sql`:

- Append-only recipe drafts allocate versions atomically by business/site/code; ingredients and packaging retain item and UOM references, quantities, expected waste and planning rates. Approval changes only approval metadata; future-effective and superseded recipes cannot plan new batches.
- Batch plan stores immutable recipe reference, location, multiplier, expected yield and non-posting estimated cost. Release requires a separate scoped Owner by default. Safe cancellation accepts planned batches only. Released/recorded corrections explicitly require `NOT_CONNECTED:CONTROLLED_REVERSAL`.
- One immutable measured output per batch: good, rejected, rework, process loss, reason, output lot reference and complete ingredient/packaging consumption with source lot references. Categories reconcile to expected output in the recipe yield UOM. Never add kg ingredients to pieces output. Current reconciliation does not support over-yield, co-products or multi-operation WIP.
- Owner-configured loss and consumption variance thresholds, maker/checker and 0–5 stages use the canonical Control port. Nonzero stages fail closed with `NOT_CONNECTED:APPROVAL_COMPLETION`; no approval journal invented.
- Seven state-changing RPCs registered as enforced with CI-run disabled-feature proof. Closed tables have RLS, no direct API rights; helpers are private; SECURITY DEFINER paths pin search_path. Every successful domain command has a receipt linked to canonical Audit. Auth and Control run again before replay is returned.
- Idempotency keys bind actor + business + site + command payload. Advisory and row locks prevent duplicate records under simultaneous requests. Rollback refuses domain or Control history and never deletes canonical Audit.

RPCs: `mfg_create_recipe_v1`, `mfg_approve_recipe_v1`, `mfg_plan_batch_v1`, `mfg_release_batch_v1`, `mfg_record_output_v1`, `mfg_cancel_batch_v1`, `mfg_request_handoff_v1`; read RPC `mfg_inspect_v1`.

Control keys: `mfg.recipe`, `mfg.recipe_approve`, `mfg.batch`, `mfg.batch_release`, `mfg.output`, `mfg.handoff`. These map to BOM versions, work-order approval, issue handoff, yield, waste/rework and planning costing Detail IDs. MRP/routing/capacity/subcontract/downtime are not falsely registered as completed features.

## Integration requests for the existing owners

No shared-source edits requested in this increment are applied here. These requests are recorded in B-015 notes.

1. **NP02 Master:** implement and verify adapter contract `_mfg_master_check_v1(recipe bigint) RETURNS void`. It must validate active scoped items, canonical versioned UOM identities, yield and per-line units, same-dimension conversions (kg/gram), item-specific weight/pieces conversion and exact precision. It must reject unsupported conversion, stale Master revision or inactive item. Current private implementation always raises `NOT_CONNECTED:MASTER_UOM`; test-only replacement never enters migrations.
2. **NP01 Auth:** add manufacturing-specific action names/allow/deny into canonical access resolver. Until then all mutations and reads here require `can_manage` plus `can_site(...,'stock.read')` to respect explicit site denies. Managers/operators/inventory staff/auditors are tested as denied, not advertised as supported manufacturing roles. Do not use `stock.post` as an invented manufacturing grant.
3. **NP01 Approval:** source-linked terminal approval adapter must verify exact recipe/batch payload and configured route length, current Control revision, maker/checker, decision expiry/revocation and scope before execution. Current stage>0 gates refuse execution. Zero-stage domain tests are an explicit Owner Control choice in a disposable fixture only.
4. **B-012 Stock/QC:** source-linked ingredient issue, unused-material return, FG/by-product receipt and bounded reversal contract on A048. Validate lots/expiry/QC and quantities with canonical UOM. `mfg_request_handoff_v1` currently audits only an attempted request and returns NOT_CONNECTED with stock_issued/stock_received=false. It never changes batch posting state or stock balances.
5. **B-013 Money:** manufacturing output/consumption source adapter for recognized valuation and cost variance. `mfg_inspect_v1` reports manual-rate planning math only, not actual cost/COGS. Finance handoff always NOT_CONNECTED, financial_posted=false.
6. **Shell owner:** mount `mountManufacturing(root,{rpc,context})` from `modules/manufacturing/workbench.mjs`, injecting signed `{tenant_id,business_id,site_id}` and signed rpc. Menu must be gated by server context/catalog. Call returned disposal function on business/site switch or sign-out. No shell/nav files altered. Standalone `modules/manufacturing/index.html` is intentionally disconnected without injected context. No hosted config/key is used.

Numeric order / OUT_OF_ORDER remains unchanged. 0500 may not reach persistent databases or merge before required lower blocks. In particular absent S2–S5 numbered engines and adapter proof are integration blockers.

## Deterministic demo and actual verification

Fictional Sandesh QA uses milk, sugar and boxes; synthetic BDT estimates, not tax/valuation/business records. SQL: 100 planned pieces, good=95/rejected=2/rework=1/loss=2; milk consumption 10.5 vs planned 10; planning cost 1100 BDT, variance +40 BDT. No actual financial posting.

`tests/np05a/manufacturing-e2e.sql` first tests **unmodified production** approval/Master fail-closed gates. Only then, within its rolled-back transaction, it loads `master-fixture.sql`. This fixture recognizes only fictional `fixture:kg` / `fixture:piece` recipe references; it is not a conversion engine or genuine Master integration. `concurrency.sh` persists the same fixture solely in a disposable local/CI database for separate sessions and the browser. Auth uses canonical predicates and synthetic database subject claims; no GoTrue, hosted sign-in or real signed-token certification claimed.

Executed locally on PostgreSQL 17:

- All migrations up → full down → up, repeated idempotent up: PASS (27 migrations including latest NP01 trunk at `5598795`; full down and idempotent up).
- `tests/np05a/manufacturing-e2e.sql`: PASS; drafts, immutable versions, future effectivity, planning math/variance, output reconciliation, variance limits, safe cancellation, default maker/checker, approval/Master fail closed, every Control switch-off, direct mutation/helper denial, cross-tenant/business/site, manager/investor/operator/revoked/expired/unassigned negatives, zero stock mutation, canonical audit verification.
- `tests/np05a/concurrency.sh`: PASS; two real sessions same-key output command -> one source receipt/Audit event; competing late key refused; rollback with history refused.
- Canonical registry and evidence scripts: PASS (7 new enforced RPCs; baseline pending debt preserved).
- Static migration and `tests/np05a/client.test.mjs`: PASS; injected scope cannot be overridden, stale in-flight response invalidation and permission errors.
- `tests/np05a/browser.cjs`: PASS, 22 checks at 390/1440; real SQL behind a loopback test gateway; draft creation, maker/checker error, disconnected handoff, report, English toggle, no overflow, disposal and revoked-role error. Screenshots in `np05a-evidence/` and CI artifacts. A hidden-button selector failure was corrected and the browser suite rerun.

Draft PR: https://github.com/mistybari99/CORE-10-CENTRAL/pull/112. Initial CI at `48868f2` failed during container setup because the health command used single quotes; corrected to the established double-quoted Docker option and rerun. No SQL/security test was bypassed.

CI workflow: `.github/workflows/core10-np05a-manufacturing-ci.yml`. Exact-head links/results belong to the PR and Board; do not infer CI success from this document.

Unexecuted/blocked: genuine kg/gram/pieces canonical conversion; real approval completion; ingredient substitution/return; by-products; over-yield; multi-operation WIP/rework routing; QC/lot validity/expiry; recognized costing/COGS; all 16 signed personas; Central-shell traversal; hosted Owner inspection. 12ui generation required sign-in; existing repository CSS reused, with genuine Chromium evidence instead of generated-design claims.

## Owner inspection guide (local QA only)

১. রেসিপি ট্যাবে সংস্করণ ও উপাদান খুলুন; নতুন খসড়া তৈরি করুন।
২. ব্যাচ ট্যাবে পরিকল্পিত/নথিভুক্ত অবস্থা দেখুন; সংযোগ পরীক্ষা করলে NOT_CONNECTED দেখাবে।
৩. ফলন ও অপচয় ট্যাবে ৯৫% ভাল পণ্য, প্রত্যাখ্যান ও পুনঃকাজ দেখুন।
৪. English চাপলে ভাষা বদলাবে। Revoked persona-তে অনুমতি ত্রুটি দেখাবে।

This is a standalone development surface, not integrated ERP certification. Next safe increment: bind the verified NP02 UOM and manufacturing Auth actions, then source-linked Approval/Stock adapters; extend substitution, returns and corrections with negative tests before any real handoff.

Safety: no hosted Supabase migration, no staging seed/accounts, no Cloudflare deployment, no merge/release and no access to IMG-ERP-SG. Only own-branch development, disposable fixtures/tests and Draft PR coordination.
