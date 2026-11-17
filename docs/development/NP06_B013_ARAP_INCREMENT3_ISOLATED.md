# NP06 / B-013 — AR/AP increment F3 (0402–0403), isolated stacked development

**Status: independent review candidate, disposable PostgreSQL 17 tests passed; NOT INTEGRATION-AUTHORIZED.**
**Dedicated branch:** `build/chatgpt-np06-arap` (intentionally separated from PR #115).
**Stack dependency:** Draft PR #117 targets the **Finance F2 branch** at `6945fc2`, never Claude trunk. F3 includes 0402 + 0403, depends on 0401 and NP02 Master 0150–0153. **Do not merge #117** until F2 PR #115 obtains independent Owner GO and is integrated; GO-2/GO-3 remain unauthorized.

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


## F3 extra safeguards from 0403

- Read-only `finance_arap_trace_v1(link_id)` returns the existing posted document source/domain/ref, canonical Money posting audit ID, NP02 Master party, allocation IDs/amounts, payment source refs and Audit receipts. Provenance explicitly states `manual_posted_journal_not_external_invoice_attested`; it does not invent a real invoice or bill provider.
- A trigger rejects `sales_invoice`, `purchase_bill` or other externally named source domains if an actual canonical attestation adapter has not been connected. Linked AR/AP items therefore remain manual-Owner-governed evidence, NOT genuine automated Sales/Procurement invoice integration.
- A settlement trigger requires an already-posted `manual` payment journal with a matching **asset-account-side** counterpart supporting its control-account amount. It explicitly labels the payment as `manual_asset_counterpart_not_bank_attested`; actual bank/receipt authenticity remains NOT_CONNECTED.
- A transactionally evaluated guard blocks reversing an **allocated** document or settlement payment. The existing 0401 posting/reversal work and its Audit roll back together when there are historical allocations. This restriction remains until a canonical deallocation/reconciliation adapter exists.
- F3's 0403 down migration refuses recorded F3 history; when only 0401 historical reversal receipts exist, it preserves the existing `FIN_REVERSAL_ROLLBACK_DENIED_HISTORY` fail-closed semantics without editing 0401.
- Independent concurrency tests now include (1) exact-key allocation replay, (2) competing over-cap payments and (3) **allocated payment vs reversal of the same posted source**—one commit only.
- Stacked Draft PR #117: https://github.com/mistybari99/CORE-10-CENTRAL/pull/117 . The earlier isolated 0402–0403 code/test checkpoint `884a9562` passed disposable PG17: https://github.com/mistybari99/CORE-10-CENTRAL/actions/runs/44171329414 . Check PR #117 exact-head shared CI separately before final integration review.

**Hard integration rule:** No 0402 application/PR merge until PR #115's 0401 has separate Claude/Owner integration approval and is integrated. F3 can continue receiving isolated code/review/testing without touching PR #115.

**Deployment fence:** GO-2 hosted staging and GO-3 preview/deploy still UNAUTHORIZED. Never write to hosted Supabase, Cloudflare, main, production or IMG-ERP-SG from this branch.
