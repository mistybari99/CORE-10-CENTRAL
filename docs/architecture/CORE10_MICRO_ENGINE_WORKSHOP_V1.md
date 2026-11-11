# C10-A045 — Owner Micro-Engine Workshop v1 (architecture & contracts)
Status: BUILT in Draft PR #42 (disposable `c10_demo` only). NOT applied to IMG-ERP-SG. NOT real-GoTrue tested.

## Model
- **Handler registry** `micro_engine_handlers_v1`: `threshold_rule_v1` (certified, executable, advisory, non-mutating) + 8 inert types (`workflow_v1`, `validator_v1`, `calculator_v1`, `report_v1`, `approval_policy_v1`, `notification_v1`, `automation_v1`, `integration_v1`) with `certified=false, can_execute=false` — they can store DRAFT data but can never be validated or published.
- **Engine** `micro_engines_v1`: one canonical id per tenant (`engine_key` unique). **Versions** `micro_engine_versions_v1`: immutable (descriptor + md5 hash CHECK; trigger allows only DRAFT→VALIDATED; no delete/truncate).
- **Assignment** `micro_engine_assignments_v1` (engine × business): `PUBLISHED|PAUSED|REVOKED`, pinned version, per-business `params` (`threshold`, `outcome` only), `placement` (central_only/business_only/both/hidden_from_menus), `local_edit_mode`, optimistic `version`. FK (business,tenant) blocks cross-tenant publishing.
- **Receipts** (idempotency, actor+payload bound), **append-only audit** (before/after), **requests** (approval queue).
- Authority reuses `actor_uid()/can_tenant()/can_manage()`. No role/permission ledger. No direct table grants; all access via SECURITY DEFINER RPCs.

## Rule DSL (data, not code)
`{"field":on_hand|reorder_gap|days_cover|margin_pct|order_total,"op":lt|lte|gt|gte|eq,"threshold":number(±1e9),"outcome":allow|warn|block|approval_required,"message"?:≤200 chars}`. Unknown keys fail closed. No eval/SQL/JS/URL/formula. Evaluation returns `advisory:true, canAuthorizeOperation:false, mutates:false`; `wouldBlock` is advice only.

## RPCs (authenticated only)
Owner (tenant_owner): `save_engine_draft_v1`, `validate_engine_version_v1`, `preview_engine_draft_v1`, `assign_engine_v1` (publish/pause/revoke/placement/params), `rollback_engine_assignment_v1` (config-only), `decide_engine_request_v1`, `read_engines_v1`, `read_engine_audit_v1`, `read_engine_pending_v1`.
Business Owner (delegated): `edit_engine_params_v1` (direct only if `local_edit_mode=business_owner`; queues if `request_approval`; denied if `central_only`), `read_business_engines_v1`, `preview_business_engine_v1`.

## A044 compatibility contract (for the other agent to cherry-pick)
`read_business_engines_v1(p_business)` returns items in the A044 shape (`control_id='engine.<engine_key>'`, `placement`, `local_edit_mode`, `preferred_enabled`, `version`) plus `state/effective/can_execute`. The A044 Business Controls surface can merge `items` into its 18-item list without a shadow settings table or any A044 schema change. A044 files were NOT modified, except one additive nav link in `core10-control-studio.js`.

## UI
`core10-engine-workshop.html` (Owner) and `core10-engine-workshop.html?biz=<id>` (Business). Verified at 390px and 1440px against a SYNTHETIC RPC fixture; server security is proven only by `tests/c10_a045_micro_engine_e2e.sql`.

## Not built
Real Supabase GoTrue/RLS staging proof; SG migration; other handler types; site-level overrides/tenant defaults; A034 permission reconciliation (ChatGPT scope); merge into A044 UI.
