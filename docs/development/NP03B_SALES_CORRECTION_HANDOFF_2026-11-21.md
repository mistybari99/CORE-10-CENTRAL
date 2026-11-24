# B-014 GO-SALES-CORRECTION — partial correction, NOT integration-ready

## Baseline and ownership

Live PR109 originally `aa45845c4f7310824ae81dacbaff08660e4fc701`, branch
`build/codex-np03b-sales`, OPEN/DRAFT, base `ccr-15ed11dd-n3hw5h`.
Trunk `5efece225a7e6ca5875dd954f9cc0b8298adeeb8` was 15 commits ahead and
Sales 11 ahead. Non-force merge `4344ab3158335e4eccba0d39caff401b1d5f5b88`
preserves both histories; Sales is now zero behind that trunk. The four imported
Finance CI/docs/test files are exactly the trunk changes, not edited lane work.
No shared workflow, other Builder branch, hosted database or deployment was changed.

## Why SQL corrections are blocked

The authorized GO explicitly prohibits modifying possibly applied migrations or
allocating a new migration number. The checked-in reservation ledger records only
staging `0001–0012` on **2026-11-16**. Previous PR109 handoffs and workflow prove
disposable PG17 application, with GO-2/3 HOLD, but do not constitute a current,
complete persistent-database application inventory. Current authoritative
attestation was requested; none was available when this evidence was prepared.
**Do not infer that 0300–0304 are unapplied merely because they are Draft/unmerged.**

All ten existing up/down files remain byte-for-byte identical to the original
Sales HEAD. `tests/np03b/0300-0304.sha256` pins those original bytes; Sales CI
checks the manifest. No new migration number or ad-hoc executable SQL patch is
introduced. Before SQL implementation, obtain authoritative non-application
evidence, or separately authorize a reserved forward migration and dependency
order. Do not work around the checksum guard or use rollback to erase history.

## Disposition

| Finding | Status | Evidence and exact remaining boundary |
| --- | --- | --- |
| P1-01 confirmed source/Audit binding | **BLOCKED** | Privileged header UPDATE, line UPDATE/DELETE/INSERT, self-consistent source tampering before invoice, mismatched real confirmation Audit association, and changed source line before validation are accepted. Canonical Audit verification still returns `ok:true`: an event ID or snapshot hash is not semantic proof. SQL guards/binding are NOT implemented. |
| P1-02 zero-stage approval injection | **BLOCKED** | Authenticated order confirmation and invoice validation both accept fabricated approval `999999` under stages 0. The SQL still writes the unverified reference. No client-side mitigation is claimed as server enforcement. |
| P2-01 cancellation Approval | **POLICY DECISION REQUIRED / SQL BLOCKED** | Stage-0 draft cancellation works. Stages 1–5 deny missing approval and reject a genuine confirmation approval presented for cancellation. Catalog advertises `sales/confirm`; no separately accepted Sales staged-cancellation contract found. A generic GOV002 policy publisher is not Owner ratification of such a contract. The explicit unsupported-positive-stage fence is still required; not claimed complete. |
| P2-02 Master retention | **BLOCKED** | Maintenance DELETE of referenced canonical customer is accepted; historical Sales still contains its numeric ID. Internal Master FKs do not establish Sales retention. Scoped Sales-owned FKs/guards need the migration gate; no Master migration was changed. |
| P2-03 Central host | **BLOCKED, module lifecycle FIXED** | Retained handoff/refresh can no longer remount after destroy or auth invalidation; same-client scope/locale/navigation tests added. Actual `index.html` does not load Sales scripts; no permanent authorized Central route exists. Harness success is not actual host integration. |
| P2-04 historical Master pricing | **POLICY DECISION REQUIRED** | Current fail-closed revalidation preserved and tested in eight catalog-change cases. Source prices/quantities/currency/totals/snapshots are not repriced. No approved historical-price eligibility policy found. |

## Implemented safe module correction

`core10-sales-order-entry.js` guards both retained view callbacks and public
refresh after unmount/sign-out/session replacement. Previously a retained Orders
handoff could mount Invoice after destroy. Added unit tests cover same API,
scope/locale handoff, old-view disposal, SIGNED_OUT, TOKEN_REFRESHED, USER_UPDATED
and post-destroy refresh/navigation. This is a Sales module contract, not proof
that Central attaches it or that hosted signed authentication is certified.

Shared-host owner requirement (no host files edited): load Sales CSS and
Master catalog/client/Orders/Invoices/entry scripts in the documented order;
register an authorized existing-shell route; pass the incumbent signed client and
validated scope; call `destroy()` before every route/actor/business/site
replacement and remount after canonical session changes. Test real entry loading,
navigation, revocation and late-response cleanup at 390/1440 in BN/EN.

## Executed verification

Only disposable Docker `postgres:17`, synthetic hierarchy/personas/bakery Master
fixtures and inert Auth UUID claims were used. No hosted Supabase/GoTrue access.
Raw failure evidence: `docs/evidence/np03b/correction-security-pg17.txt` and
`correction-concurrency-pg17.txt`. Bounded regression markers, including the
initial combined evidence-file omission and successful corrected run, are in
`correction-verification.txt`. No unexecuted test is called passing.

| Executed check | Result |
| --- | --- |
| Baseline/trunk Sales migration full Up→Down→Up + idempotent up | **PASS: 38** |
| Original ten Sales migration SHA256 checks | **PASS** |
| Existing Sales Orders/Audit/Master/Invoice SQL, RLS, Control registry/evidence | **PASS** |
| Existing Sales and Invoice independent-session duplicate/CAS/Control/revocation/rollback scripts | **PASS** |
| Sales client 13, Invoice client 15, Master catalog 14, entry lifecycle 4 | **PASS: 46** |
| Browser Orders 1440 EN / 390 BN | **PASS: 43** (test harness) |
| Browser Invoice 1440 EN / 390 BN | **PASS: 36** (test harness) |
| Changed customer/item/variant/UOM/list/price/currency/pricing-UOM after confirmation | **PASS: 8 fail-closed validation cases**, readable snapshots unchanged; NOT historical-pricing acceptance |
| Stock0200; Finance0400/0401 SQL, races and exact rollback guards | **PASS** |
| Combined NP01 + Manufacturing migration Up→Down→Up | **PASS: 48** |
| Combined registry/evidence and Sales Orders/Invoice SQL | **PASS** after copying actual dependency evidence tests into temporary snapshot |
| Combined NP010110–0114 and Manufacturing0500–0504 SQL regressions | **PASS: 10 files** |
| New security acceptance | **FAIL: 10 unresolved cases; 11 cancellation baseline checks pass** |
| New barrier races | Competing confirmation and amendment-vs-confirmation **PASS**; tamper-vs-invoice **FAIL: accepted** |
| Actual Central signed-host integration; hosted signed JWT; full stages 2–5 positive/expiry/revocation matrix; validation-vs-source race; OFF starting after creator statement | **NOT VERIFIED / NOT RUN** |

Sales CI now runs the new security tests as a **blocking** final step. The job
must remain red while the findings persist. The script gathers both SQL and race
results and returns nonzero on either failure; it does not suppress the gate.
Other lanes' CI stays untouched. Exact-head CI URLs/results belong in the final
delivery report; older green runs are not evidence for this correction head.

### Reproduction commands

In the disposable PG17 workspace, set PGUSER=postgres and
PGDATABASE=core10_np03b_local_correction (loopback PGHOST/PGPASSWORD for the
Finance boundary script). Run only against this isolated test container/database:

```bash
sha256sum -c tests/np03b/0300-0304.sha256
node --test tests/migrations/migration-contract.test.js
bash tests/migrations/run-updownup.sh
psql -X -v ON_ERROR_STOP=1 -f tests/np03b/sales-orders.sql
psql -X -v ON_ERROR_STOP=1 -f tests/np03b/audit-read.sql
psql -X -v ON_ERROR_STOP=1 -f tests/np03b/master-integration.sql
psql -X -v ON_ERROR_STOP=1 -f tests/np03b/invoice-drafts.sql
psql -X -v ON_ERROR_STOP=1 -f tests/np03b/historical-master.sql
psql -X -v ON_ERROR_STOP=1 -f tests/migrations/control-registry-check.sql
bash tests/migrations/control-registry-evidence.sh
bash tests/np03b/concurrency.sh
bash tests/np03b/invoice-concurrency.sh
psql -X -v ON_ERROR_STOP=1 -f tests/np03b/correction-security.sql # currently nonzero
bash tests/np03b/correction-concurrency.sh # currently nonzero
node tests/np03b/client.test.cjs
node tests/np03b/invoice-client.test.cjs
node tests/np03b/master-catalog.test.cjs
node --test tests/np03b/entry.test.cjs
psql -X -v ON_ERROR_STOP=1 -f tests/migrations/np03a-inventory-e2e.sql
psql -X -v ON_ERROR_STOP=1 -f tests/migrations/np06-finance-e2e.sql
psql -X -v ON_ERROR_STOP=1 -f tests/migrations/np06-finance-reversal-e2e.sql
bash tests/migrations/np06-finance-race.sh
bash tests/migrations/np06-finance-reversal-race.sh
bash tests/migrations/np06-finance-rollback-boundary.sh
```

Browser commands executed from the repo with NODE_PATH=/tmp/np03b-ui-tools/node_modules,
NP03B_CHROMIUM=/tmp/np03b-ui-browsers/chromium-1243/chrome-linux64/chrome,
NP03B_TEST_CONTAINER=core10-np03b-correction, PGHOST=127.0.0.1, and screenshots
under `/tmp/np03b-correction-shots`. Each uses a separate fresh database, migrated
with `internal/migrations/run.sh up` and its corresponding seed:

```bash
PGDATABASE=core10_np03b_local_orders_ui node tests/np03b/browser.cjs
PGDATABASE=core10_np03b_local_invoice_ui node tests/np03b/invoice-browser.cjs
# Seeds: tests/np03b/ui-seed.sql and tests/np03b/invoice-ui-seed.sql respectively.
```

### Dependency evidence

Live heads verified before relying on them:

- Trunk/NP02 Master/Stock/Finance0400–0401: `5efece225a7e6ca5875dd954f9cc0b8298adeeb8`.
- NP01 PR111: `69143ffb82667b6f81b3667288af54a86b597698` (0110–0114).
- Manufacturing PR112: `7e39b7517763e24c308b7f8316a3ac7219a84d2d` (0500–0504).
- Finance F3 PR117: `3d128dc4df1b8860ce46a3aaae9960843d382c0f`;
  **NOT RUN**, no independently corrected/verified F3 head supplied.
- Bootstrap PR119: `ee76fd652bc3405e2f1fd808850a1d58d1bd47e6`, docs only;
  no shared Bootstrap implementation imported or authorized.

Combined source lived only in `/tmp/np03b-correction-compat` and container
`/compat`: Sales/trunk snapshot plus exact dependency migrations and their actual
test files. No dependency branch was merged/pushed. The 48-migration proof does
not imply all domain journeys or security fixes pass.

Merged Finance shared CI pins Sales `aa45845...`; this correction moves the head
and legitimately trips its drift guard when the cross-lane workflow runs. The
Finance/Control Room owner must independently review and update that pin; this
GO does not authorize editing it. No green CI is manufactured.

## Next gate and restartable independent review

First settle migration application evidence/forward authorization, not a new
business feature. P1-01 needs genuine DML/TRUNCATE protections for confirmed
headers/lines/receipts and serialization with draft confirmation, plus canonical
Audit semantic binding in create/edit/validate. The true `sales.confirm` audit
contains a **pre-transition** `payload.source.version` and a **post-transition**
`payload.receipt.version`; verify their exact relation, source_ref, tenant,
business/site/order/action, source document/total, actor/request and line evidence.
Compare materialized headers/lines as well as JSON. Do not create a shadow chain.
P1-02 needs server-side non-null approval rejection under zero stages and explicit
zero-stage Audit status. Unsupported positive-stage cancellation must fail closed.

Reviewer prompt: "Review PR109 at the delivery's exact new SHA. Scope:
GO-SALES-CORRECTION only. Verify migrations0300–0304 byte-identical to aa45845,
trunk5efe included without shared edits, lifecycle callback correction and tests.
Run correction-security.sql and correction-concurrency.sh on disposable PG17;
expect unresolved failures, not integration readiness. Challenge confirmed source
and Audit binding, zero-stage approval injection, cancellation policy, Master
retention and historical pricing. Distinguish harness results from real Central
mount/signed Auth. Confirm security CI remains blocking, Finance pin untouched,
PR Draft/unmerged and no hosted actions. Recommend the exact migration evidence
or separately authorized forward dependency needed before SQL corrections."

All legal issuance/numbering, Stock reservation/deduction, Money/revenue/payment,
tax posting and settlement remain NOT_CONNECTED. Validated invoices remain DRAFT.
GO-2 staging and GO-3 production remain HOLD. No integration-ready claim.
