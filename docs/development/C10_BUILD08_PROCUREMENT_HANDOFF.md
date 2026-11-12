# CORE 10 CENTRAL — Build 08 / PROC-001 Procurement Kernel

**Date:** 2026-11-12 (Asia/Dhaka)
**Source:** Master Decision Book MODULE DELIVERY #8; MODULE BUILD DETAIL rows 210–221; C10-CAP-PROC-001.
**Decision alignment:** D047, D048, R127, R128; REV-009/D051/R130 preserve original Islamia ERP.
**Status:** CODED / ISOLATED TESTS ONLY. Draft, unmerged, not deployed, not SG installed, not signed-auth verified or certified.
**Branch:** feature/c10-build08-procurement-kernel-20261112, from main c39052910758ca285a7a4d56e9c4f4873cb7d99c.
**Ownership boundary:** New internal/enterprise-procurement/build08 and tests/build08 paths only; no edits to Build01–05, A055–58, canonical A018/A049 engine, GOV001/2/3, main, Islamia app, finance, stock or existing policies.

## Delivered source

- internal/enterprise-procurement/build08/procurement-kernel.mjs — in-memory deterministic domain kernel with 17 commands, isolated from network/DB.
- tests/build08/procurement-kernel.test.mjs — Node 22 tests: cross-tenant/site permission denials, maker/checker, idempotent replay, quote/PO revision, receipt/QC, invoice holds, allocation rounding, payment authority, report scope.
- .github/workflows/c10-build08-procurement.yml — Node22 syntax, tests and static no-external-call guard.
- Run command: node --test tests/build08/procurement-kernel.test.mjs
- Only cite CI SUCCESS after checking workflow at exact Git SHA.

## Non-negotiable boundaries

1. AUTH: actor parameter is synthetic fixture input, NOT signed authorization. A canonical GoTrue server adapter must bind user, tenant/business/site and explicit effective permissions from trusted claims and persisted grants. Never expose this code as a public API.
2. STOCK: received, QC-inspected, returns are plans only (stockEffect NONE). Canonical inventory ledger must do actual stock/lot/serial movements after signed authorization, with exact idempotent bridge.
3. ACCOUNTING: invoice MATCHED means draft three-way evidence only; AP effect NONE. Payment AUTHORIZED_PENDING_EXTERNAL_SETTLEMENT is NOT cash transfer, actual bank settlement, AP adjustment, tax posting or journal. No default exchange rate, VAT percent or fabricated zero balances.
4. DURABILITY: copy-on-write and request digest replay are SINGLE-PROCESS deterministic examples, not persisted row locking, restart safety, signed JWT proof or financial concurrency safety.

## Twelve detail trace / remaining integration gate

| Source detail | This isolated draft implements | Cannot yet claim |
| --- | --- | --- |
| 210 Purchase requisitions | Demand ID, site, quantity, UOM, checker and duplicate demand guard | Persistent demand source + signed approval |
| 211 RFQ/supplier comparison | Quote price/freight/tax/lead validity, equal currency/UOM, comparable ranked cost | Full RFQ invitation, version and bid audit |
| 212 Supplier qualification | Block, expiry, related-party hold fail closed | Enterprise party/legal compliance workflow |
| 213 PO revisions | Immutable revision counter, separate maker/approver, stale proof denial | Durable GOV002 approval journal |
| 214 Partial receipt | Quarantine, partial quantity, configured overdelivery tolerance plus permission | Actual receipt and stock ledger |
| 215 Receiving quality | Distinct inspector and evidence token, rejected/quarantined not available | A058 QC/lot/serial integration |
| 216 Supplier invoice | Approved PO + accepted goods + exact price; explicit HOLD discrepancies | Authoritative AP, tax/receipt document match |
| 217 Landed charges | Quantity/value allocation; deterministic cents with conserved totals | Approved valuation / capitalization |
| 218 Supplier returns | Accepted receipt cap and pending return proposal | Credit note and stock reversal |
| 219 Payment maker-checker | Invoice-bound proposal, different approver, immutable bank fingerprint | Due calendar and bank settlement |
| 220 Allocation/reversal | Prevent duplicate proposal overdraw; cancel unapproved request | Real partial payment allocation, verified reversal |
| 221 Procurement close | Requires reconciled accepted qty/approved invoices and zero HOLD; scoped report | Accounting close and real AP reporting |

All authoritative 12 MODULE BUILD DETAIL rows must remain NOT_CERTIFIED_PER_DETAIL. This is an isolated large coding slice, not complete PROC001 operational certification.

## Exact calculation contract

- Monetary input = integer smallest currency unit, quantity = integer milli-UOM.
- Extended amount = ROUND_HALF_UP(unit_price_minor * qty_milli / 1000), once per line. Fee/tax amounts must be explicitly supplied; no invented local rates.
- FX quotes cannot be ranked together without a versioned certified exchange-rate policy, so mixed currencies are denied.
- Landed cost uses largest-remainder apportionment, ordered ties by line ID; sum(allocated) always equals charge.
- Report states and all receipts are synthetic isolated state only.

## Merge/integration sequencing

1. Use current main and cross-check owner-controlled Draft PRs before rebase. Build01 signed GoTrue GOV001 scope, GOV002 approval and GOV003 audit must be established first.
2. Replace memory state with versioned, tenant-scoped PostgreSQL documents, unique keys, row locking and source-linked audit events. Add signed HTTP/PostgREST positive and negative tests, actual two-session races, backup/restore.
3. Connect A049 canonical inventory and A058 Quality; connect Finance-owned balanced AP/settlement journal without duplicate ledger. Verify supplier credit/reversal and source idempotency.
4. Build responsive BN/EN role-filtered UI (390/1440) with guided R128 descriptions; no change to Islamia's existing routes/branding.
5. Obtain separate approved staging migration, signed-user evidence, rollback and Owner release gate before any merge, production activation or live data write.

No main/SG changes; no PR auto-merge. Governance record lives in the existing Decision Book, not a new competing master.
