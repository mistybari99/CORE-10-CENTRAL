# NP06 / B-013 — Increment 2: canonical posted-journal reversal (0401)

**Status:** CODED, CI review pending; draft PR required. **Not production-certified.**
**Working lane:** `build/chatgpt-np06-finance`; base `ccr-15ed11dd-n3hw5h`.
**Prior integration:** 0400 merged under Owner GO-F1 as PR #108, trunk commit `de67402`; 0401 was not included in GO-F1.

## 1. Authority and scope

The existing `core10.finance_journals_v1` + `finance_journal_lines_v1` **remain the single Money ledger**. Migration 0401 adds only `finance_reversals_v1`, a scoped, immutable pointer from a posted original to a new, balanced, opposite posted journal; it stores **no balances or subledger money amounts**.

The authenticated API `core10.finance_reverse_posted_journal_v1(p_original bigint,p_effective_on date,p_reason text,p_key text)`:
1. Locks the original journal and verifies canonical actor + `can_manage` scope.
2. Enforces new Owner Control key `finance.journal_reverse` (disabled by default).
3. Rejects unposted, already-reversed, reversal-of-reversal, backdated, cross-actor replay or conflicting request keys.
4. Builds exact account/amount/opposite-side lines from the posted original, using a new, traceable `finance_reversal` source reference.
5. Calls the **existing** Finance draft, validate and post RPCs in one database transaction, including their Auth, Control, account status, owner-configured max amount, explicit open-period lock and canonical Audit checks.
6. Appends a separate canonical reversal event with reason code and links to both journals, then writes the immutable reversal pointer. An error anywhere rolls back draft, validation and post. The original remains posted and untouched.

An exact same-actor/same-key/same-date/same-reason retry returns the one previous reversal. A second different-key reversal of the same source is denied. Competing sessions serialize on the posted original's row lock.

## 2. Approval, period, role and source boundaries

- **No new approval service.** Existing `finance.journal_post` defaults to one approval stage; without the canonical GOV-002 completion adapter, a reversal still fails `FIN_APPROVAL_NOT_CONNECTED` and does not post. Only an Owner's explicit zero-stage policy on the existing post key permits the synthetic manual path.
- **No implicit period open.** An old closed month can remain closed while an explicitly opened later period receives the reversal. No backdating before the original effective date.
- **No account-archive bypass.** Existing finance posting rejects inactive/nonpostable accounts. Reversals cannot surreptitiously use closed or changed account state.
- **No Accountant/Cashier grant.** This first increment requires canonical Owner `can_manage`. Role extension depends on NP01 canonical Auth and signed 16-persona acceptance.
- **No auto reversal adapters** for Sales, Stock, AP/AR, payroll, tax, FX, valuation or credit notes. This is an Owner-governed journal correction primitive, **not an automated credit note workflow**. Original source authenticity still depends on future domain adapters. Direct owner manual draft API remains separately available in 0400 and is not falsely called fully source-attested.

## 3. Security and verification

New table has tenant/business foreign keys, authenticated SELECT RLS using `can_see_business`, no authenticated/public DML; triggers deny UPDATE/DELETE/TRUNCATE even to accidental privileged SQL. The new RPC has no anon/PUBLIC execute and is `enforced` in the existing `control_rpc_map_v1` with a real test file reference.

Verification sources:
- `tests/migrations/np06-finance-reversal-e2e.sql`: disabled Control, default one-stage posting denial, closed-period failure (no partial draft), cross-tenant/auth denials, exact line mirroring, idempotency conflict, no reversal chains, canonical audit, immutable rows.
- `tests/migrations/np06-finance-reversal-race.sh`: two independent PostgreSQL sessions competing on one posted source, requiring one reversal pointer, one posted reversal, one canonical reversal audit event.
- `.github/workflows/core10-np06-finance-ci.yml`: complete PG17 Up→Down→Up, registry/evidence, 0400 regression, 0401 tests, both independent-session races, data-bearing rollback refusal.
- `0401_np06_journal_reversal.down.sql`: refuses to drop the reversal control/evidence history or a posted reversal, even if a privileged executor attempts the migration.

Do not mark CI green until a run at the **exact submitted head SHA** succeeds. Full B-013 remains IN_PROGRESS (AR/AP allocation and aging, reconciliation, COGS/valuation, proper credit/debit notes, GOV-002 adapter, signed hosted Auth, 16 personas and Finance UI not done).

## 4. Integration and deployment fence

**Draft PR only.** No staging/production migration, no Cloudflare deploy, no IMG-ERP-SG operation, no trunk write or merge from this lane. 0401 requires separate Owner integration approval after four shared CI suites and Claude contract review. Hosted application remains blocked on migration ordering/GO recorded by Claude.
