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
