# PACK-01 first implementation slice — canonical A048 site permissions

**Scope:** C10-D033/D036/D037/D051/D054; C10-A018/A019/A034/A048; Build01 & Build02A. Owner GO: 2026-11-15, **code and disposable testing only**. This branch is a Draft PR candidate against `preview/c10-integrated-20261111-v1`, not a main merge or release.

## Current patch
- Inventory actions resolve the stock location to its canonical tenant/business/site; they call the existing `c10_demo.can_site` resolver rather than independently reading active-only `site_grants`.
- Owner, business owner, manager, and staff cannot create, confirm, or post a source/destination command if the effective site permission is denied, expired, or revoked. A previously created draft is re-authorized at transition.
- Inventory command readback filters denied locations even for inherited owner permissions. No second permission storage or accounting/stock ledger is introduced.
- Existing `can_manage` still controls business-wide policy changes and inventory adjustment eligibility, **but never bypasses site denies**.
- The disposable Preview One loader can run PACK-01 security checks after loading original A048 plus Build01 plus Build02A, using two unrelated tenant fixtures. All test updates roll back.

## Run in disposable PostgreSQL 17
```sh
CORE10_PREVIEW_DISPOSABLE_ACK=I_CONFIRM_DISPOSABLE_PREVIEW CORE10_PREVIEW_BUILD01=1 \
PGHOST=127.0.0.1 PGPORT=5432 PGUSER=postgres \
bash tests/preview-one/run-combined.sh pack01-security
```

## Still open — not a major package completion
Hosted signed GoTrue A/B sessions, A049 and other module adapter parity, direct HTTP/RLS/Storage/CSV permission negatives, real worker/browser proof, independent backup/restore, compatibility and approval release review. No SG migrations, production transactions, deploy, old Islamia source edits, or main merge. No operational release from CI alone.

## Checkpoint 03 — A049 purchase/sale order permission parity (2026-11-15)
- `create_operation_order_v1` and `advance_operation_order_v1` now ALWAYS invoke A048 effective location/site `stock.post` authorization before owner or staff policy checks. Site DENY, expiry and revocation override Owner/Manager inherited rights. Existing role-based sale/receiving/production configuration remains unchanged.
- Added isolated PACK-01 SQL regression: business owner draft/confirmed orders then site-denied; new order/confirmation/post blocked and no stock movements; site read denies hidden records; manager deny, expired staff site grant, revoked business owner, unrelated tenant all denied.
- Same 2-tenant disposable PG17 stack, A048, Build01/02A; unchanged legacy and actual live SG. No new production purchase/sale functionality approved. CI outcome and exact SHA must be appended only after observed success.

## Checkpoint 04 — Workforce effective authority
A051 `wfi_ctx` now rejects inactive tenants and ignores expired Build01 business owner/manager membership. A051 `wf_my_businesses_v1` matches effective membership expiry and tenant.active. Because Build01 is loaded after A051, `to_jsonb(m)->>'valid_until'` is used so the original isolated A051 installs without a non-existent column. A distinct active employee login still has its own workforce access after stock grant removal. Added transaction-rollback tests for manager/owner expiry, inactive tenant, employee independence and cross-tenant discovery/read. This is PACK-01 scope only, not hosted GoTrue or production approval.

## Checkpoint 05 — A054 delegated HR/Payroll eligibility expiry
- A054 `a054i_deleg`, grant RPC and eligible-list now reject expired business manager/owner membership, while preserving separately active employee authorization and explicit delegation records. No permission store added or helper GRANT widened.
- `business_members.valid_until` is conditionally read through `to_jsonb(m)` to preserve original A054 installs before Build01 adds the validity column.
- New transactional synthetic PG17 tests cover granted manager before/after expiry, denied renewal and eligible list, revoked membership, foreign tenant, and employee-only authorized delegation.
- No production Supabase, original Islamia, live money/stock, deploy or main merge. Exact-head CI outcome must be confirmed before marking the slice tested.

## Checkpoint 06 — A055 Asset root authority
A055 `ami_ctx` now rejects inactive tenants and expired Build01 business owner/manager membership while retaining separately granted active Asset technician permissions. When Build01 validity column is absent in original pre-Build01 PG17 CI, `to_jsonb(m)->>'valid_until'` permits the original baseline; after Build01, expiry is enforced. PACK01 suite loads disposable A055 synthetic seed and rolls back owner expiry, stock-only denial, independent technician positive, inactive tenant and foreign tenant negatives. No live asset/stock changes. All CI must be verified for exact SHA.

## Checkpoint 07 — signed JWT two-unrelated-tenant API negative harness
Dedicated `pack01-signed` disposable CI job runs exact combined A018..A056 SQL, Build01 + Build02A and test A055 seed inside ephemeral PostgreSQL17. Starts loopback PostgREST v12.2.12 with a fresh CI-only HMAC signing secret, sends independently signed synthetic tenant A/B, business-owner, revoked/stock-only, stuffed-claim and invalid/expired tokens. Exercises authentic REST calls to A048/A049/A051/A054/A055, direct private-table denials, CSV export denial and internal-helper not exposed. This is signed HMAC transport, NOT Supabase GoTrue-issued session or hosted E2E; storage, production and signed session revocation-race still unverified. No general public API permission widened.

## Checkpoint 08: PACK-02 PR105 S2 Build01-owned adapter contract
Owner requested read-only review PR #105 S2 against PACK-01 and authorized BUILD01 adapter code/tests; PR105 HEAD 2dcb4133b3751987faf04e443b1f776445c0bd11, PR104 baseline 5103730576a57a21149b077f514cb6d7309ba61d. PACK-02 explicitly delegates S2 page/gateway integration to PACK-01 owner; PR105 owns workspace SQL/renderers and is NOT modified.
Build01 page gains a read-only hidden S2 workspace section and a separate adapter script, which activates ONLY when isolated loopback gateway verifies PACK02 assets exist in the packaged app. Gateway allowlists one additional exact signed `pack02_workspace_v1` RPC only when ready, never exposes other APIs; browser client always calls fresh GoTrue getUser before server RPC, checks actor, scope, mode, contract, staff payload. On logout/business switch revoked/expired context, private view is cleared. PACK02 authored renderer handles branded views and nav buttons remain disabled until separately wired. Build01 pre-PACK02 standalone behavior unchanged. CI checks out pinned PR105 head separately and copies only its three S2-owned contract files into a disposable test worktree (NO git merge) for real local GoTrue browser integration. No actual GitHub merge or PR105 source changes; no production deploy, legacy Islamia changes or live money/stock.

## CHECKPOINT 08 — PR105 S2 contract drift reconciliation
PR105 HEAD advanced during PACK01 coding to 7afe9ea9106286bea6391a58bbf7c52e9def67f9; Claude added PACK02-owned signed adapter, app host, controls and report gates plus a six-file Build01 patch proposal. PACK01 revised the first experimental single-RPC bridge to consume PR105-owned signed client and app, while Build01 exports only five READ projection RPCs. PACK02 setup write RPC is NOT allowed. Gateway activates only when five PR105 assets are packaged. Local CI composes pinned PR105 files in disposable checkout; no git merge, no remote merge, no production or D051 change. Verify new exact-head jobs before claiming S2 tested.

## CHECKPOINT S2: PR105 contract reconciliation (2026-11-15)
Contract+patch actually reviewed from PR105 exact 7afe9ea9106286bea6391a58bbf7c52e9def67f9; patch targets six Build01 files from an old PR104 SHA (5103730). Current PR104 eb829a6601c0b7e5bb02306541eddb7413ddce47 ALREADY has a more restrictive Build01 `api.pack02` signed read-only allowlist, gateway gated on packaged files, dynamic fail-closed host and sign-out reset, plus local GoTrue optional S2 hook. Blindly applying the proposal would overwrite those protections. No PACK02-owned source is committed here.
New PACK01-owned CI bridge pins PR105 HEAD in a second read-only checkout and stages only its 5 assets + 2 SQL files + test tree into temporary PACK01 checkout. It runs original Build01 SQL, PACK02 SQL including projection/A048 agreement, PACK01 security in combined schema, and actual LOCAL GoTrue / Chromium S2 journey. Neither PR merged, no staging/production. Preview combined runner only loads PR105 SQL when both files exist and Build01 disposable mode is active.

## CHECKPOINT 09 — GOV002 prerequisite: Build02A effective approval permissions
Only PACK01-owned canonical Build02A resolver `can_approval_action_v1` / policy writer `build02a_set_approval_policy_v1` are exercised. No financial GOV002 workflow or production posting code. New transaction-rolled-back PG17 negative matrix: tenant/business owner, manager default submit/withdraw but no decide/exception, explicit per-member allow vs DENY (DENY wins), policy expiry restores role baseline but removes explicit grants, membership expiry and revoke deny even baseline, stock-only and investor cannot become approval role, cross-business/tenant and inactive tenant refuse. New signed-HMAC loopback PostgREST negative matrix includes owner/manager/foreign roles, owner-scoped synthetic policy grant and removal, explicit denial of manager/foreign policy writer, and continued cross-tenant protection. No production Supabase, hosted GoTrue or Storage tested; exact-head CI required.

## CHECKPOINT 10 — Local GoTrue Approval Role Test + D051 Protected Source Guard
The Build01 disposable GoTrue runner now loads EXISTING canonical Build02A approval resolver and calls a new actual GoTrue-issued session/PostgREST test (not hand-signed HMAC for user claims). Tests cover owner/business-owner, manager/staff/investor/foreign role scope, forged user metadata ineffective, owner policy writer idempotency, explicit DENY outranking manager baseline, short TTL expiration while access token remains live, independently refreshed delegated rights, canonical business membership revoke immediately removing manager+delegation rights, and logout invalidating the previous JWT. All SQL/GoTrue identities exist only in auto-dropped local PostgreSQL17.
D051 CI guard checks SHA-1 Git blobs of 9 legacy files against the VERIFIED Preview base e76cf8a3; original existing 193-report, 7-module, item dictionary loss regression also runs. **Known pre-existing discrepancy**: Preview index.html blob f2f74144 differs from protected main/archive index.html blob fa1856ba; this is NOT newly introduced by PACK01 but remains a D051 pre-integration visual/route parity gap, not a certified acceptance. No legacy path touched, no production/hosted/merge. Exact-head CI outcome pending until GitHub green.
