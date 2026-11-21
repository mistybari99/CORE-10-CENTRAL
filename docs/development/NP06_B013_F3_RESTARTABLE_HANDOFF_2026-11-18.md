# NP06 / B-013 — F3 AR/AP and Payment Allocation restartable handoff
Date: 2026-11-18. **Review candidate only; do not integrate or deploy.**

## Explicit Owner fences

- Dedicated work branch: `build/chatgpt-np06-arap`; all F3 code is isolated from `build/chatgpt-np06-finance` and its Draft PR #115.
- **Stacked Draft PR #117**: https://github.com/mistybari99/CORE-10-CENTRAL/pull/117; base `build/chatgpt-np06-finance`, not Claude trunk. The later F2 head `6945fc2` was merged to F3 by normal non-force two-parent commit `79482f6b` with **zero file overlap**. PR #115 remains separate; only F3 branch has 0402/0403.
- Claude integration trunk: `ccr-15ed11dd-n3hw5h`; latest verified initial base `ba1ef9fbec8b46b1f28bfee30d5bc6ffde3e4c3e` with NP02 Master migrations 0150–0153 and the Master UI.
- Finance 0400 is already integrated by Claude/Owner GO-F1. Finance **0401 is pending independent review and separate Owner GO** in Draft PR #115 (last seen F2 head `6945fc2`, all four shared CI success). F3 `0402–0403` is STACKED ON 0401; **must not merge/apply to trunk before 0401 integration**.
- GO-2 staging migrations and GO-3 deploy remain **UNAUTHORIZED**. No Supabase hosted writes, Cloudflare/Worker operations, main, production, SG or IMG-ERP-SG changes.

## Existing single canonical source of truth

- NP02 `master_parties_v1` is the sole customer/supplier store: active `customer/both` for AR and `supplier/both` for AP, business/tenant-matched IDs and foreign keys. Finance does **not** create a party engine.
- `finance_journals_v1`, `finance_journal_lines_v1`, `finance_accounts_v1`, `finance_periods_v1` in migration 0400 remain the **single posted Money ledger**.
- F3 `finance_arap_links_v1` is an immutable pointer to **one already-posted** Money journal plus one NP02 Master party and control account, with due date; **not an invoice/payable engine or balance store**. Nominal original amount is derived from the canonical journal's signed account lines.
- `finance_arap_allocations_v1` is an immutable relation linking the AR/AP source to an **already-posted** Money settlement journal with an allocation amount. It posts **no** cash or journal of its own; a payment may be partially allocated but never spent past the control-account movement.
- `finance_arap_aging_v1(business,as_of,kind)` derives original, allocated, outstanding, and current/1–30/31–60/61–90/90+ aging from posted journals, source effective dates, due date and allocation movements. No mutable balance or shadow ledger.

## 0402 baseline and 0403 integrity extension

`0402_np06_arap_links_allocations.up/down.sql` (preserved unmodified from the initial isolated checkpoint `ff1c02c`):
- Canonical Owner `actor_uid/can_manage`, default-disabled Owner Control `finance.arap_link` and `finance.arap_allocate`, canonical append-only Audit, business-scoped RLS `can_see_business`, no authenticated table DML/anon RPC.
- Scope and currency/legal entity/account category restrictions, source **posted** enforcement, same-actor exact-key replay, mismatched-key denial, independent-session row locks on original/payment journal to prevent over-allocation.
- Immovable state: UPDATE/DELETE/TRUNCATE guards and rollback refuses historical AR/AP/Audit/Control evidence.

`0403_np06_arap_trace_integrity.up/down.sql` (adds **no tables or money balances**):
- `_finance_arap_source_integrity_v1`: a posted `manual` Money journal may be linked, with provenance explicitly **not invoice/bill attested**; unverified `sales_invoice`, `purchase_bill` or other claimed external domains are REFUSED. Actual NP03 Sales invoice and Procurement bill source adapters do **not** exist here and may not be faked.
- `_finance_arap_settlement_integrity_v1`: settlement must be an already-posted `manual` journal with an asset-side counterpart supporting the full AR/AP control account settlement movement. This is structural account evidence, **not verified bank or cash receipt**. Unverified external collection/payout source domains or expense-only contra movements are denied.
- `_finance_arap_reversal_allocation_guard_v1`: 0401 reversal of an **allocated source or allocated settlement payment** is blocked at the reversal pointer INSERT. Failure rolls back the newly drafted/validated/posted opposite journal and its canonical Audit **as one transaction**. This fail-closed boundary remains until a sanctioned deallocation/reconciliation adapter exists; an **unallocated** source can still reverse.
- `finance_arap_trace_v1(link_id)` is a signed scoped, read-only current-state projection of canonical source domain/ref, post audit ID, NP02 party ID/code, currency/due date, manual provenance, allocation amounts, payment source refs and canonical allocation audit receipt IDs. No duplicated source register.

## Test matrix and real independent sessions

`.github/workflows/core10-np06-arap-ci.yml` runs disposable PostgreSQL 17:
1. Static canonical migration naming/ranges/grants/RLS; migrations **Up→Down→Up**, idempotent reapply, control registry/evidence and data-bearing reversal rollback refusal.
2. NP02 Master table and RPC regression; Finance 0400 source/post baseline; Finance 0401 reversal and Audit regression; Finance 0402+0403 E2E.
3. E2E: active/wrong-kind/blocked/foreign-party scope; Control OFF and OFF-after-replay; no direct DML; income/expense and asset/liability accounts; partial AR/AP allocation, same-key replay, conflicting payload; no past/future journal leakage in dated aging; provenance and canonical Audit trace; unverified invoice/bill, collection and non-asset payment refusal; unsupported allocated reversal denial; unallocated reversal with as-of restoration; tenant RLS/unauthorized Manager; audit integrity.
4. Three actual **independent PostgreSQL session** races: (i) exact-key allocation replay once, (ii) two distinct allocations competing for the last budget (one commit, one over-allocation denial), (iii) reversal versus allocation of the same open item (exactly one commits and both states are never simultaneously true).
5. Data-bearing `0403` rollback must fail-closed while preserving 0402 and canonical Money history. It remains safe to apply Up→Down→Up on an **empty disposable PG17**.

## CI evidence and integration-safety compatibility

- Isolated F3 before latest F2 sync, exact code HEAD `884a956230c95d19c1ab3730614ae610b8a46459`: PG17 **SUCCESS** https://github.com/mistybari99/CORE-10-CENTRAL/actions/runs/44171329414 (0402/0403 + NP02 Master, finance 0400/0401, real 3-session-pair races, rollback history guard).
- Stacked F3 PR #117 triggers **all four shared** PostgreSQL/Owner Control/Approval/Audit regression suites plus F3 PG17. Earlier combined shared Finance CI exposed an assumption that latest migration always equals 0401: with 0403 present, the generic down runner first dropped 0403. F3 fixed this without altering the 0401 migration or F2 PR #115: `0403.down.sql` refuses AR/AP history first, and also refuses standalone historical 0401 reversal receipts using the prior `FIN_REVERSAL_ROLLBACK_DENIED_HISTORY` error. It still permits empty-database Up→Down→Up.
- **Read the actual latest head's checks before claiming PR117 is 5/5 PASS.** No hosted apply. Review `.github/workflows/core10-np06-arap-ci.yml`; F3 adds Master request-key and 0401 posted/reversal independent-session regression tests in its own job.

## Outstanding genuine integration blockers

**NOT_COMPLETE:** No canonical `sales_invoice`, `purchase_bill`, receipt/bank/payout attestation adapter is connected. F3 can link Owner-governed MANUAL posted source and settlement journals only; it must not label them true invoices/bills or certified payment receipts. GOV-002 approval-completion adapter is still **FIN_APPROVAL_NOT_CONNECTED** for Finance post with 1+ stages; only explicit Owner zero-stage policy is used in disposable tests. Missing signed Accountant/Cashier permissions, real 16 personas and hosted Auth, automated invoice/credit-note collection flow, foreign currency/FX, tax, cash/bank reconciliation, valuation/COGS and Finance UI.

## P2-03 retrospective aging: explicit historical time basis

Current `core10.finance_arap_aging_v1(p_business,p_as_of,p_kind)` is a
**restated effective-date aging view**, not a historic knowledge-as-of or
transaction-commit-time snapshot. Source journals enter by `j.effective_on`,
payment allocations are summed when their posted payment journal
`pay.effective_on <= p_as_of`, and reversals enter by `rev.effective_on`.
The immutable allocation record's `created_at` is **not** an as-of filter.

Consequently, a payment effective 2026-11-18 but allocated on a later date
appears in a retrospective 2026-11-18 aging query once the allocation exists.
This accurately describes *restated economic effective date*, not what the
business knew or reported on 2026-11-18. Do not use it as a point-in-time
knowledge, filing, or close-period certification. No original allocation,
journal, payment or Audit timestamp is rewritten by the read.

The F3 PG17 E2E now asserts both the later `created_at` and the restated
historical allocated/outstanding numbers. Supporting an immutable
knowledge-as-of query would require an independently accepted reporting
contract and additional event-time/commit-time evidence; do not silently
invent that policy or claim that future feature is implemented.

## Restart procedure and independent review

1. Fetch live F3 and F2 PR #115 heads/trunk. Verify F3 contains `0402–0403` but PR #115 does **not**, and F2 is not merged.
2. Re-run disposable PG17 F3 CI, existing NP02 Master/Owner Control, S0 migration order, S1-c canonical Approval/Audit and Finance 0400/0401 regressions against latest safe trunk.
3. Compare diffs for 0400/0401 checksum changes (FORBIDDEN); no force-push or rewritten shared history. Preserve all builder-owned source files.
4. Read Board **B-013**, F2 handoff `NP06_B013_FINANCE_HANDOFF_2026-11-18.md`, this F3 handoff and the F3 CI evidence. Request separate Claude independent F3 technical review only after 0401 has its Owner GO; **do not self-merge**.
5. Never apply a hosted migration or deploy on the basis of synthetic passing tests.

This is an honest isolated engineering candidate, **not accounting/banking compliance certification**.
