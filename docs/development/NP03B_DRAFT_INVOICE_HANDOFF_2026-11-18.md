# B-014 / NP03B — restartable draft-invoice handoff

Date: 2026-11-18. This increment adds one non-issued invoice draft per confirmed canonical Sales order. It is a SQL/API increment; the existing Sales UI is preserved. It does not supply legal numbering, issuance, Stock/Money posting, POS or collection.

Integration lead reports latest trunk `a82ae99` safely merged into own `a63b40b`, including Stock `0200` and Finance `0401`. These are integration checkpoints, not a final delivery SHA or exact-head CI conclusion. Do not reuse an older branch's CI as evidence for this diff.

## Files and reuse boundary

Own new source: `internal/migrations/0304_np03b_draft_invoices.up.sql` / `.down.sql`, `tests/np03b/invoice-drafts.sql`, `tests/np03b/invoice-concurrency.sh`; NP03B workflow adds both test paths. Earlier `0300–0303` migration checksums are preserved.

| Reused source | Concrete boundary |
| --- | --- |
| `0300–0301` Sales orders / Auth scope / Control / command receipts | Invoice source must be a scoped confirmed order at its exact version. Existing `_sales_scope_v1` owner authorization and explicit site fence remain authoritative. Auth and live Control are rechecked after lock waits and before replay/mutation. |
| `0302` and canonical Audit | Reuses canonical atomic audit append and receipt linkage, not another audit engine. Invoice read joins its command receipts to canonical events in domain `sales_invoice`. |
| `0303`, NP02 `0151–0153` | Current Master references, tier prices, currency, UOM precision and zero-tax fences remain authoritative. No Sales replacement of Master or historical versioned-price engine. |
| Canonical GOV-002 / Control approval bindings | Validates exact source/version/payload and current required stage count, maker/checker and effective approval. No invoice-specific approval store. |
| Stock `0200` | One existing stock ledger/internal engine is present; no accepted Sales fulfilment/reservation command is invoked by this increment. |
| Finance `0400–0401` | Existing journal/period/reversal foundation remains separate. No invoice-to-Money adapter, receivable, settlement or reversal call is wired here. |

All three new tables have RLS enabled with no authenticated table/sequence privileges. Public RPC execution is revoked; authenticated callers use scoped SECURITY DEFINER RPCs with pinned search paths. Internal helpers remain closed to authenticated. No new role or permission engine is introduced.

## Concrete APIs

All functions are in schema `core10` and return JSONB.

| RPC | Usage |
| --- | --- |
| `save_sales_invoice_draft_v1(p_business bigint,p_site bigint,p_invoice bigint,p_expected bigint,p_order bigint,p_order_version bigint,p_lines jsonb,p_memo text,p_key text)` | Create with `p_invoice=NULL,p_expected=0`, exact confirmed order/version, nonnull memo and request key. `p_lines=NULL` on creation selects all source lines at full quantities. Edit with existing invoice/current expected version and explicit selection. |
| `validate_sales_invoice_draft_v1(p_business bigint,p_site bigint,p_invoice bigint,p_expected bigint,p_approval bigint,p_key text)` | Rechecks current source, Master, policy and exact approval; advances version and records validation while status stays `draft`. A zero-stage policy permits null approval; positive stages require the actual canonical binding. |
| `read_sales_invoice_drafts_v1(p_business bigint,p_site bigint,p_invoice bigint DEFAULT NULL)` | At most latest 100 scoped drafts. Includes receipt fields, document/selection/memo, fixed snapshot/hash/scale, materialized lines, maker/validation metadata, current approval payload and canonical audit. Top-level `validation_control` comes from `control_approval_binding_v1`. |

Receipts disclose invoice/source IDs and versions, draft status, validation flag, total, currency and source hash. They always return `issued:false`, `stock_posted:false`, `financial_posted:false`, with `connections:{issuance:'NOT_CONNECTED',stock:'NOT_CONNECTED',money:'NOT_CONNECTED',tax:'ZERO_ONLY'}`. A validated draft is not a legally issued invoice.

Business/request-key serialization plus locked source/invoice rows prevent duplicate creation and lost updates. Repeating an actor-bound exact input/key returns its original receipt; changed actor/payload raises `SALES_INVOICE_REPLAY_CONFLICT`. Authorization and current enabled Control still apply to retries. Every successful new command has one canonical audit event in its transaction; exact replay adds none.

## Confirmed snapshot and editable limits

Creation records the confirmed order ID/version, business/site, document, confirmed total, ordered line totals, confirmation audit-event ID and invoice `money_scale`. `source_sha256` is SHA-256 of the PostgreSQL JSONB snapshot text encoded as UTF-8; a table check verifies it. It is an integrity binding, not an external signature or historical Master price certificate.

An update trigger fixes the source snapshot/hash, customer/price-list/currency references, source order/version, money scale and creation identity. Callers cannot submit replacement item/variant/UOM identities, unit prices, discounts or taxes. The projected document derives those fields from confirmed source lines. The selected scale must reproduce the confirmed source line totals and total; conflicting source rounding is rejected. A later configured scale change refuses edits/validation rather than changing the fixed snapshot.

There is a unique source-order constraint: **one invoice draft per order**, including partial selections. This is not multiple instalment invoices or a remaining-quantity ledger.

`p_lines` accepts only entries like `{order_line_no:1,quantity:2}`. Each source line appears at most once; quantities are positive, respect canonical precision and never exceed that confirmed source line's cap. Default `allow_partial_quantities:false` requires all lines at full confirmed quantities. Owner may explicitly enable `allow_partial_quantities:true` to permit a nonempty subset and reduced quantities within those caps. It never permits a subsequent second invoice for the omitted balance. Updates must send explicit selection; null on update is invalid.

Memo length follows current Owner limits. Every saved edit advances version and clears `validated_at`/`validated_by`; an earlier approval cannot validate a changed revision. Validation also advances version, preserves status `draft`, and retains the last editor as maker (`changed_by`) rather than replacing maker with validator.

Current Master revalidation can reject an unchanged confirmed quote if prices, date eligibility, active references, currency or tier selection have changed. Reducing quantity may move the applicable Master tier and reject the fixed source price. Neither save nor validation silently reprices. The stored invoice snapshot is immutable, but a historical Master-version acceptance guarantee remains **NOT_CONNECTED** as a dependency contract; snapshotting does not remove current-date validation. Nonzero tax remains refused even if Owner enables the tax switch.

## Owner Control and exact approval

Both new features default **OFF**:

- `sales.invoice_draft`: save gate; inherits Sales numeric/rounding limits, adds `allow_partial_quantities` default false and `max_memo_length` default 500 (allowed 0–4000). No approval stages on this save feature.
- `sales.invoice_validate`: validate gate; default one required stage, maximum five, canonical domain `sales`, action `invoice_validate`. Validation also checks the draft feature and its current parameters. Owner may explicitly configure zero stages for a disposable test; that is not the default release policy.

For positive stages, `gov002.review` must also be enabled. Use the current read result's `approval_payload` and `validation_control`, not a client-reconstructed payload. Canonical submission binds:

```text
domain: sales
action: invoice_validate
source_key: sales-invoice-draft:<invoice_id>
source_version: current invoice version before validation
payload: {
  invoice_id, site_id, version, source_order_id, source_order_version,
  source_sha256, document, memo, total, money_scale,
  required_stages, action: "invoice_validate"
}
```

The verifier requires exact binding/effectiveness and current stage count; approval request maker must equal the invoice's last editor. Route cardinality must equal configured stages. Wrong source, changed memo/document/version/stage count, pending/expired approval or unauthorized self-review must not validate. After edits or policy changes, reread and submit a fresh canonical request as needed. There is no integrated invoice approval UI in this increment.

## Verification checkpoint — restart here

Local disposable PostgreSQL17 checks **PASS** for the final source:

- All38 migrations up → down → up + idempotent up, including integrated Stock0200 and Finance0401.
- Existing Sales, canonical Master integration and scoped Audit SQL suites; new `invoice-drafts.sql` lifecycle/security suite.
- New invoice race: same-key audit-once, different-key one-source uniqueness, competing edit/validation CAS, cross-business held-row denial under300ms lock timeout, both feature switches changing during waits, membership revocation and exact0304 populated-history rollback guard. Old Sales race also PASS.
- Canonical Finance0400/0401 and Stock0200 regressions PASS. Registry/evidence PASS:23 enforced,7 exempt,10 inherited pending; both new writers actually enforce their mapped switches.
- Existing13 Sales client +14 Master catalog +2 mount lifecycle tests PASS. Existing43 browser checks rerun successfully at390px Bangla/1440px English against final migrated SQL. They test the preserved Sales workspace, not an invoice screen.

Invoice SQL tests executed real create/confirm source RPCs and checked immutable full snapshot/hash/trigger, one-source uniqueness, default-full and Owner-partial caps, four-place prices and fixed rounding, stale versions and exact receipts, zero-stage validation and real one-stage maker/checker, wrong approved source/hash/stage cardinality, validation reset after memo edits, changed Master rejection, canonical Audit failure atomicity,16 persona aliases/anonymous/expiry/revocation/site denial, default-deny RLS and absence of stock or financial postings.

Auth claims and business/customer/pricing data remain synthetic. Hosted GoTrue validation is NOT_RUN; GO-2/GO-3 remain HOLD. No new invoice UI, visual redesign or public preview is delivered. Exact pushed-head CI is maintained in Draft PR109 and Board B-014 after push; priorc7ad970 green checks are historical only.

### Shared Finance compatibility pin request

`.github/workflows/core10-np06-finance-ci.yml` has a separate `np01-compat-pg17` job which fetches the *live* PR111 head but accepts only reviewed SHA `c858084d0d5a80b752637c30fd7c9199dc8455a5`. Live PR111 is now `d9a1659af5a62940b719fca3b443fe7b6e3c9a52` (adds0113 GOV003). The job intentionally stops with `NP01_REVIEW_HEAD_MOVED_REVERIFY_BEFORE_COMPAT` before migration tests. This is a shared-owner re-review gate, not a draft-invoice posting dependency.

Exact request to Finance/trunk owner: review the new PR111 diff, test the approved exact head in a disposable combination, then update that job's expected SHA and step description to the reviewed0110–0113 baseline. Keep the head-move refusal and all compatibility/security tests. NP03B does **not** edit the shared workflow, weaken/skip its gate or claim latest unmerged NP01 compatibility. This increment's actual target trunka82ae99, including0401, is tested above. Record actual exact-head shared CI outcome in PR/Board.

Restart commands from repository root, using a fresh loopback PostgreSQL17 database matching `core10_np03b_ci*` or `core10_np03b_local*`, no `auth.users`, and disposable API roles as configured in the NP03B workflow:

```sh
export PGHOST=127.0.0.1 PGUSER=postgres PGDATABASE=core10_np03b_ci_invoice
# Supply the disposable server credential through the environment.
createdb "$PGDATABASE"
bash tests/migrations/run-updownup.sh
psql -X -v ON_ERROR_STOP=1 -f tests/np03b/sales-orders.sql
psql -X -v ON_ERROR_STOP=1 -f tests/np03b/master-integration.sql
psql -X -v ON_ERROR_STOP=1 -f tests/np03b/audit-read.sql
psql -X -v ON_ERROR_STOP=1 -f tests/np03b/invoice-drafts.sql
bash tests/np03b/concurrency.sh
bash tests/np03b/invoice-concurrency.sh
psql -X -v ON_ERROR_STOP=1 -f tests/migrations/control-registry-check.sql
bash tests/migrations/control-registry-evidence.sh
```

Fixture-based SQL suites roll their records back; the invoice race script creates/drops its own suffixed database. Review outputs and current workflow diff before recording evidence. Use exact-head CI after final commit/push. Never run these fixtures or migrations against hosted production.

Rollback is deliberately conservative: `0304` down raises `SALES_INVOICE_ROLLBACK_HAS_HISTORY` when any invoice draft exists. Used append-only Control history may also prevent catalog deletion. Persisted business/audit history requires a forward migration plan, not deletion. Do not bypass these guards or alter `0300–0303` checksums to restart.

## Shared-owner requests and remaining work

1. **NP01 Sales Auth:** register accepted invoice/Sales read/save/validate/issue actions and canonical context. Current owner-only scope with explicit site fence remains; stock access or a UI role label does not grant invoice authority.
2. **Central route owner:** retain the existing shared client/login/navigation and register authorized Sales routing with fresh selected scope, destroy/remount on context changes. This SQL increment adds no independent shell or invoice page.
3. **NP02 / tax owner:** supply accepted tax authority and historical price/version acceptance semantics before nonzero-tax or historical invoice claims. Preserve server tier authority and explicit changed-quote rejection.
4. **NP06 Money owner:** accept immutable source ID/version/hash, currency/rounding, posting idempotency and reversal/receivable allocation contracts before connecting invoice issuance, collection or refunds. Presence of `0401` reversal does not supply this adapter.
5. **NP03A Stock owner:** supply an accepted Owner-Control-checked Sales fulfilment/reservation command and source/reversal bindings before any stock effect. `0200` internal posting primitives alone are not that command.

NOT_DONE: legal numbering/issuance, Stock reservation/fulfilment, Money posting/receivables/settlement, POS/collection/refund/returns, canonical tax, historical Master price acceptance, accepted Sales Auth, permanent authorized host navigation and hosted signed testing. No complete Order → Invoice → Collection → Return claim is made. Invoice/race results above are executed; exact pushed-head PR/CI/Board evidence is recorded externally after push; no external write, deployment or merge is authorized by this artifact.
