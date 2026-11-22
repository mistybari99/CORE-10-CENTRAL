# CORE-10 PaperOps — owner-origin forms, field controls and paper minimization

**Status:** DRAFT implementation on isolated PaperOps branch; not an ERP module release.  
**Baseline:** 22 Nov 2026, canonical trunk `ccr-15ed11dd-n3hw5h`.  
**Goal:** Owner's ten-plus businesses must each work both with signed ERP and, in a documented fallback, with complete paper records. The first business the Owner designed on paper was sweets.

## 1. Evidence and what has actually been inspected

Five frozen Islamia sweet-business files were read from the canonical trunk: `forms.js` (5 definitions), `forms_cash.js` (7), `forms_stock.js` (8), `forms_sales.js` (7), and `forms_factory.js` (5). **Total: 32 distinct legacy form codes.** Their IDs, Bangla/English names, source files, original Git blob SHA1 and planned quarantine paths are committed in `legacy-inventory.json`. A test computes their original blob SHAs byte-for-byte from either original root paths or future `legacy/islamia-erp/` paths. The original files are NEVER loaded by PaperOps and must not be edited or deleted.

The original source includes nontrivial controls: independent preparer/checker/approver roles, item-and-location stock continuity, issue-slip and GRN references, opening/closing measures, expected-vs-actual production yield, signed money handover, amount-limit approval, physical count adjustment evidence, refunds and returned/uncollected goods. **These controls are business requirements; copying their current UI is not the requirement.**

**Evidence qualification:** 32 definitions are indexed, **NOT YET** fully audited field by field or validated in real shops. The initial eight printable templates represent an intentionally scoped draft, NOT 32 faithful replacements. A zero-gap business-coverage or 95–99% recovered-understanding claim would be premature until the field-by-field source/control matrix is completed and tested with the Owner.

## 2. Decision: one engine, reusable core, independent business packs

`modules/paperops/paperops.js` provides a standalone, non-networked, offline print renderer with Bangla/English support. `index.html` provides a draft print studio. Branding can be Group → Business → Site, with form title and header-name overrides; site mode prints the site name while business mode is site-neutral. A user can upload a local image as a temporary logo, select a color and export/import JSON print settings. No tenant data, print setting, transaction or logo is sent to a server, and no operational database is changed.

Eventually PaperOps lives behind the *same* signed Group → Business → Site context and entitlement model as the ERP; print settings must not authorize access to other businesses or sites. Common templates are immutable versioned definitions with permitted industry overlays, not copied bespoke implementations per branch. The standalone version has **no security claims about ERP tenancy** and is intentionally not wired into the Cloudflare live bundle.

### Why not make 32 forms mandatory every day?

Paper burden must be assessed by **daily frequency** and **people/time per transaction**, not raw catalog length. The rules:

1. **Daily summary once:** one ordinary shift/site closing should combine its item balance, sales/payment channels, cash expectation/count and exceptions; do not make the cashier transcribe identical totals to multiple summary sheets.
2. **Trigger-based documents:** create separate evidence when custody of goods/cash changes, an item is received/rejected, an order/expense exceeds policy, a refund or return happens, or an independent approval is needed.
3. **Master records are not daily copies:** a product specification, recipe, standard yield or approved tint formula is maintained by version. Factory shifts reference its version instead of rewriting the formula each day.
4. **Registers are continuing books:** store ledger, supplier ledger, receivables and marketing/online channel registers are rolling records; an entire new form is not printed for each small update unless a distinct transaction requires proof.
5. **Never collapse control separation:** independent signatures, two-sided transport handover, QC release, stock-variance approval, original invoice references, refund proof and statutory records cannot disappear merely to save paper.
6. **Zero invented thresholds:** discount limits, tolerance, expense approval tiers, QC rules, expiry and site parameters must be explicit approved per-business settings. No default numerical threshold is assumed to be authorised.
7. **Carry-forward proof:** every closing references opening/source, with unit, lot/batch and document ID as relevant. A new form must not silently assume that a cash total equals a goods total.
8. **Practical measurement:** field test weekly paper count, average completion time, re-entry time, mismatch rate, missing signatures, and exceptions caught. Simplify only where evidence continuity survives.

## 3. First-pass disposition of all 32 original sweet-business forms

| Original forms | Initial workflow decision | Print frequency |
|---|---|---|
| R-01 Daily Showroom | Core consolidated Daily Close, with line items and payment split | 1 per operating site/shift as applicable |
| R-02 Jalebi Counter | Product-process add-on only if that counter operates; never all branches | Active Jalebi shift only |
| C-01 Cash Handover | Keep independently signed on custody transfer | On handover |
| C-02 Expense Voucher | Keep original payment evidence; combined close may reference totals | Per qualifying expense |
| C-03 Marketing Expense | Rolling approved spend register | On spend; review periodically |
| C-04 Digital Payment Reconciliation | Settlement/fee/reference reconciliation, cannot be assumed from daily close | Per settlement period |
| C-05 Receivable & Advance | Rolling party balance and due-date checks | Update on transaction, review period |
| C-06 Cash Position & Budget | Management control; not a counter-entry sheet | Weekly/monthly as policy |
| W-01 Material Issue | Keep source/receiver proof; share print family with transfers, not posting semantics | On issue |
| W-02 Transfer Challan | Keep dispatch and receiving quantities and both signatures | On movement |
| W-03 Stock Count | Count + checker + variance approval, not mandatory daily every product | Scheduled/exception |
| W-04 Store Ledger | Rolling item/lot/location register with every GRN/issue ref | Update per event |
| P-01 Purchase Requisition | Controlled request and need-by date | On purchase need |
| P-02 Quotation Comparison | Keep where threshold/policy requires it, may share a purchase packet | Policy-triggered |
| P-03 Purchase Order | Commit to supplier with approved quantity/price | Per purchase order |
| P-04 GRN | Received, inspected, accepted, rejected, batch/expiry proof | Per delivery |
| P-05 Bill Check & Payment | Three-way match + payment authority; not folded into GRN | Per invoice/payment |
| P-06 Supplier Ledger | Rolling supplier account and reconciliation | On transaction/review |
| S-01 Customer Order | Source order and later fulfilment reference | Per customer order |
| S-02 Discount Approval | Only beyond approved rule; decision must be attributable | Exception |
| S-03 Return & Complaint | Exception with quality, goods and payment impacts | Per return/complaint |
| S-04 Online & Delivery Ledger | Rolling settlement, receivable and delivery tracking | On event/settlement |
| S-05 Wholesale Invoice | Commercial/tax source document; do not replace with closing summary | Per invoice |
| S-06 Party & Wholesale Ledger | Rolling customer balance by party | On event/review |
| F-01 New Product Decision | Gate before product introduction | Per new product |
| F-02 Product Spec Card | Approved versioned master | On change |
| F-03 Recipe Card | Approved versioned master, linked from batch | On change |
| F-04 Yield Test | Controlled test to update expected yield, not shift-by-shift duplication | On trial/revalidation |
| F-05 Factory Daily | Batch/shift production, issued raw materials, yield and QC | Per batch/shift |
| M-01 Maintenance Request | Machine hazard, owner, priority and resolution proof | On issue |
| A-01 Weekly Review | Exceptions, reconciliations and corrective actions | Weekly |
| A-02 Monthly P&L and KPI | Aggregated accounting and management review, not daily entry | Monthly |

These are **proposed cadence classifications**, not evidence that all 32 have been redesigned. The exact legacy field/control requirements must be reviewed before replacing each original form.

## 4. First printable slice (eight controlled prototypes)

| New template | Informed by | Purpose | Known boundary |
|---|---|---|---|
| OPS-DAILY | R-01 | 1 site/shift item-level + payment close | Cash custody still separately evidenced |
| CASH-HANDOVER | C-01 | Two signatures + amount/recount/seal | Generated only on handover |
| STK-TRANSFER | W-01/W-02 | Reusable layout for issue/transfer with dispatch/receipt | Different event types keep different reconciliation |
| PUR-GRN | P-04 | Delivery lines and independent quality decision | No auto-posting into accepted stock |
| STK-COUNT | W-03/W-04 | Physical-vs-ledger count and adjustment authority | Not an automatic adjustment |
| MFG-DAILY | F-05/F-03/F-04 | Factory batch output + reference to master recipe | Needs sweets process-field parity review |
| PAINT-TINT | New, not legacy-derived | Proposed paint color mixing/QC | **Hypothesis** until real paint operations verified |
| EXCEPTION | S-02/C-02 concepts | Exception/threshold approval trail | Not replacement for statutory/payment vouchers |

**Not yet implemented**: full offline cashbook/GL/AR/AP continuity; all 32 field-parity templates; regulatory receipts; signed tenant-validated form settings; automatic serial-number reservation; QR scan; scan/OCR import; ERP entry, RLS, reconciliation or audit posting; business packs for the other 8+ industries. No one should describe the prototype as complete offline business operation.

## 5. Next executable build slices, with gates

**P1 — Legacy source/control extraction.** Create a machine-readable matrix for every one of the 32 forms: each input name and unit, conditional required rule, validation, formula, tolerance, flag/blocker, roles, signatures, ledger/source links, frequency, where the item originates and who corrects it. Every removed or merged field needs a replacement-location/evidence link and a test. Cover actual Owner pain points before extending to other businesses.

**P2 — User-approved paper burden audit.** Run realistic scenarios: normal sweet showroom day, Jalebi production and sales, factory-to-site transfer with damage, supplier partial delivery, digital mismatch, refund, stock variance, cash handover, discount, payroll and month close. Measure form count and field-writing effort; use exceptions rather than an unconditional full catalog. Approve the minimal *workflow-dependent* form pack.

**P3 — Business packs.** Enumerate actual ten industry IDs from signed Setup catalog; separate common purchase, stock, sales, money, workforce and management forms from industry-specific unit/lot/quality/calculation overlays. Paint is initially a hypothesis until field-verified; do not invent paint process authority. All form names, headings and theme/logo overrides must support business-wide or a specified permitted site.

**P4 — Canonical ERP integration.** Only after signed current modules and their security gates are approved: add Paper Form Instance + version + serial number + tenant/business/site scope + event/source reference + maker/checker/approver + original paper scan status + reconciliation outcomes. Use forward-only numbered migrations in Board-reserved range; enforce signed context, RLS, idempotent replay, audit and segregation-of-duties. Never make print preview perform a hidden post. Sales 030x must reach staging before Finance 040x/Manufacturing 050x.

**P5 — All-paper business continuity kit.** Fully linked books for sales, stock, purchasing, receivables/payables, cash/bank, payroll, production and close, including opening/closing carry-forward instructions and a printed index. Test complete paper-only days plus later ERP back-entry and discrepancy resolution before claiming business-complete offline operation.

## 6. Reproduction, safety and deployment

Open `modules/paperops/index.html` locally in a modern browser, choose form/industry, business-wide or branch-specific scope, apply optional header/logo/colour, preview, then use Print/PDF. Save/import a JSON settings file locally if desired. Do not put confidential identifiers in a file shared publicly.

Run `node --test modules/paperops/tests/paperops.test.cjs` on Node 22; the isolated GitHub Action runs these same tests. No external dependency or backend credentials are needed. Existing live worker, Supabase staging, canonical migration ledger, legacy JS and the owner's live routes are untouched. To publish under the live app later, use canonical build + verify and rollout/rollback rules in `docs/development/AGENT_HANDOVER_CURRENT.md`. **Do not merge or deploy this branch merely because this independent test passes.**
