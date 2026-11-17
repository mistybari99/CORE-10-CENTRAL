# NP06 / B-013 — AR/AP increment F3 (0402), isolated development branch

**Status: preliminary implementation, CI validation required. NOT INTEGRATION-READY.**
**Dedicated branch:** `build/chatgpt-np06-arap` (intentionally separated from PR #115).
**Stack dependency:** branch starts at Finance PR #115 checkpoint `bb424623`; 0402 depends on the 0401 reversal and NP02 Master 0150–0153. This is a **stacked development branch only** and must NOT be merged to trunk while 0401 remains unintegrated.

## Canonical reuse and no duplicates

1. **Customer and supplier**: `core10.master_parties_v1`, from Claude/NP02. AR only accepts active `customer`/`both`; AP only active `supplier`/`both`. No Finance party master.
2. **Money ledger**: existing `finance_journals_v1` / `finance_journal_lines_v1`. Every AR/AP link points to an **already posted journal**; every allocation points to a separate **already posted payment journal**. This increment never drafts, posts, adjusts or invents money balances.
3. **AR/AP item**: `finance_arap_links_v1` is one immutable pointer to a posted journal, one Master party, one canonical account and due date. It is not a new invoice/payable engine; original amount is **derived** from the journal lines and its asset or liability control account.
4. **Allocation**: `finance_arap_allocations_v1` stores an immutable link/amount between the original document and payment journals. This **allocates** canonical postings, but does not write a new cash entry or a second subledger balance.
5. **Aging**: `finance_arap_aging_v1(business,as_of,kind)` derives outstanding and buckets from posted lines and dated payment allocation. Original reversal links are flagged, and outstanding is shown as zero only on/after the posted reversal date. There is **no mutable balance cache**.

## Security and posting boundaries

- Only canonical signed Owner `can_manage` can create links and allocations; other roles must wait for NP01 Finance/Auth policy. Authenticated RLS reads follow `can_see_business`. No authenticated direct DML or anon function execution.
- State-changing `finance_link_open_item_v1` and `finance_allocate_payment_v1` are in the existing Owner Control registry as `enforced`. Their switches are **OFF by default**. Both call `control_check_v1` and canonical append-only audit. Immutable link and allocation tables reject UPDATE/DELETE/TRUNCATE.
- Row locks on both posted journals, acquired in ID order, serialize competing allocation spending and reversal; budget checks bound payment and document net amounts and stop over-allocation. Idempotent same-actor/same-key retries return one link/event, conflicting payload is denied.
- Journal period, approval and posted status are **not bypassed**: this increment cannot make an unposted payment seem posted. Existing Finance `finance.journal_post` remains approval-fail-closed unless the Owner explicitly configures zero-stage manual posting. Synthetic fixtures configure zero-stage only inside disposable PostgreSQL 17.
- **Not an invoice posting adapter.** Journals in tests carry `source_domain=manual`. Future NP03B Sales/NP03A Procurement source-attestation and GOV-002 completion adapters must be added before reporting actual automated invoices/collections/purchases as connected. No implicit invoicing, no tax, no FX, no valuation/COGS, no settlement certification.

## Tests

- `0402_np06_arap_links_allocations.up.sql`, `.down.sql` with data/Audit/Control history rollback guard.
- `tests/migrations/np06-finance-arap-e2e.sql`: Master parties, AR/AP category, source account control-line checks, disabled controls, idempotency, over-allocation, as-of/aging, reversal state, tenant isolation, immutable history, Auth/Audit.
- `tests/migrations/np06-finance-arap-race.sh` and seed: two real PostgreSQL sessions, exact-key replay once, distinct-key over-cap race (one success, one denial), exact audit count.
- `.github/workflows/core10-np06-arap-ci.yml`: disposable PG17, full migration Up→Down→Up, Master and 0400/0401 regressions, 0402 negative tests, race, rollback refusal.

**Hard integration rule:** No 0402 application/PR merge until PR #115's 0401 has separate Claude/Owner integration approval and is integrated. F3 can continue receiving isolated code/review/testing without touching PR #115.

**Deployment fence:** GO-2 hosted staging and GO-3 preview/deploy still UNAUTHORIZED. Never write to hosted Supabase, Cloudflare, main, production or IMG-ERP-SG from this branch.
