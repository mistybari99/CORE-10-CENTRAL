# CORE-10 PaperOps — owner-origin forms, field controls and paper minimization

**Status:** DRAFT implementation on isolated PaperOps branch; not an ERP module release.  
**Baseline:** 22 Nov 2026, canonical trunk `ccr-15ed11dd-n3hw5h`.  
**Goal:** Owner's ten-plus businesses must each work both with signed ERP and, in a documented fallback, with complete paper records. The first business the Owner designed on paper was sweets.

## 1. Evidence and what has actually been inspected

Five frozen Islamia sweet-business files were read from the canonical trunk: `forms.js` (5 definitions), `forms_cash.js` (7), `forms_stock.js` (8), `forms_sales.js` (7), and `forms_factory.js` (5). **Total: 32 distinct legacy form codes.** Their IDs, Bangla/English names, source files, original Git blob SHA1 and planned quarantine paths are committed in `legacy-inventory.json`. A test computes their original blob SHAs byte-for-byte from either original root paths or future `legacy/islamia-erp/` paths. The original files are NEVER loaded by PaperOps and must not be edited or deleted.

The original source includes nontrivial controls: independent preparer/checker/approver roles, item-and-location stock continuity, issue-slip and GRN references, opening/closing measures, expected-vs-actual production yield, signed money handover, amount-limit approval, physical count adjustment evidence, refunds and returned/uncollected goods. **These controls are business requirements; copying their current UI is not the requirement.**

**Additional source-control extraction (not a parity audit):** `legacy-field-index.json` captures **1,246 distinct candidate field keys across the 32 form definitions**, plus syntactic counts of conditional-display, required-rule, reviewer and reconciliation references. The original R-01 daily showroom form alone has **153 extracted field keys and 17 conditional-display syntax mentions**; R-02 has 61, Sales S-01 has 60, and factory F-05 has 60. These are candidate extraction counts from minified code, not validated mandatory input counts, and not proof that every field or formula was recovered. This finding directly changed the printable Daily Close and Factory Batch drafts to retain opening hygiene/safety, cold-chain/expiry where relevant, and machine/scale checks; GRN now retains ordered quantities per line as well as delivered/accepted/rejected quantities. The remaining old blockers/formula mapping still requires P1 extraction and human/Owner acceptance.

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

## 4a. High-risk legacy control traceability (the important part)

`control-obligations.json` identifies **20 source-backed high-risk obligations** (with the exact old field keys), of which **9 are only partially represented** in the first printable drafts and **11 remain explicit gaps**. Among the latter: independent Jalebi weight/yield and unsold product disposition; continuous stock and supplier ledgers; bill-PO-GRN matching; discount and refund audit; channel settlement reconciliation; customer receivables ageing; and source-controlled grading/shelf life. Nothing is labelled `complete`. The test suite refuses unknown legacy source keys and target templates, preventing these risks from being silently marked as covered.

This is why an eight-template demo must **never** be substituted for the 32 original forms in real sweets operations. The next builder must resolve the gap matrix, prove each calculation/conditional blocker, then field-test the smallest practical paper set before any release.

## 5. Next executable build slices, with gates

**P1 — Legacy source/control extraction.** Create a machine-readable matrix for every one of the 32 forms: each input name and unit, conditional required rule, validation, formula, tolerance, flag/blocker, roles, signatures, ledger/source links, frequency, where the item originates and who corrects it. Every removed or merged field needs a replacement-location/evidence link and a test. Cover actual Owner pain points before extending to other businesses.

**P2 — User-approved paper burden audit.** Run realistic scenarios: normal sweet showroom day, Jalebi production and sales, factory-to-site transfer with damage, supplier partial delivery, digital mismatch, refund, stock variance, cash handover, discount, payroll and month close. Measure form count and field-writing effort; use exceptions rather than an unconditional full catalog. Approve the minimal *workflow-dependent* form pack.

**P3 — Business packs.** Enumerate actual ten industry IDs from signed Setup catalog; separate common purchase, stock, sales, money, workforce and management forms from industry-specific unit/lot/quality/calculation overlays. Paint is initially a hypothesis until field-verified; do not invent paint process authority. All form names, headings and theme/logo overrides must support business-wide or a specified permitted site.

**P4 — Canonical ERP integration.** Only after signed current modules and their security gates are approved: add Paper Form Instance + version + serial number + tenant/business/site scope + event/source reference + maker/checker/approver + original paper scan status + reconciliation outcomes. Use forward-only numbered migrations in Board-reserved range; enforce signed context, RLS, idempotent replay, audit and segregation-of-duties. Never make print preview perform a hidden post. Sales 030x must reach staging before Finance 040x/Manufacturing 050x.

**P5 — All-paper business continuity kit.** Fully linked books for sales, stock, purchasing, receivables/payables, cash/bank, payroll, production and close, including opening/closing carry-forward instructions and a printed index. Test complete paper-only days plus later ERP back-entry and discrepancy resolution before claiming business-complete offline operation.

## 5a. BUILT: reproducible rules extraction + Smart Paper Kit (22 Nov 2026 continuation)

**Legacy rule candidates:** `legacy-rule-extractor.cjs` reads the five preserved historical sources from `legacy/islamia-erp/` (with original-root fallback for an older branch), **without evaluating/initializing the old application**. The committed `legacy-rule-candidates.json` retains 32 form identities, 1,246 labeled field candidates, an initial 270 always-required and 115 conditional-required candidates, 181 conditional-visibility candidates, 30 first-calculator-block candidates, and 163 explicit warning-flag candidates. These counts are **static source-pattern observations**, not verified operational/financial rules; the two definitions without matching local calculator blocks must be inspected manually. The CI runs `node modules/paperops/legacy-rule-extractor.cjs --check` and fails if the report disagrees with preserved source. The old `window.BOS` logic is never executed.

**Daily operational minimization:** `paper-kit.js` implements a controlled planner. Per operating *showroom* it issues one daily sales/stock close. A cash handover, inter-site stock movement, supplier delivery, physical count, production batch, paint-tint trial or exception generates a separate paper form **only for that event**. Factory, warehouse, office and project sites do **not** receive a fake retail close; their actual event records and continuing books must cover their operations. Event references are required and duplicate references for the same site/type are rejected. The renderer selects business- or site-specific heading/color/logo, escapes untrusted text, supports BN/EN, and makes A4 documents. The planner can model up to 400 sites; print is explicitly capped at 100 sheets per batch to avoid silently omitted or unmanageably large jobs.

**UI:** `kit.html` adds an offline, no-server Smart Paper Kit interface for site types, custom branch headings/themes and event-based multi-form printing. The existing `index.html` single-template studio now links to it. The factory/paint workflows remain unverified drafts; additional permanent ledgers for stock, cash/bank, suppliers, receivables, digital settlement, invoice matching, and statutory records are listed as **not yet printable** rather than claimed complete.

**Quality gates:** `node --test modules/paperops/tests/*.test.cjs` checks source field traceability, event selection, duplicate prevention, different site types, a 100-sheet cap and HTML escaping. This is implementation evidence for an isolated prototype, not business signoff, an ERP write path, an approved complete offline mode or permission to merge to trunk.

## 5b. BUILT: 30 draft templates and traceable calculation checks

The printable registry now has **30 draft definitions**: 8 original first-slice templates plus **22** added in `form-packs.js`, including an independently printable source-derived C-02 expense voucher in first 50-field review. New source-traced sweets/shared forms include:

| Source-backed controls (draft, not release) | Printable form |
|---|---|
| R-02 independent measurement + Jalebi yield, oil/syrup and unsold handling | `SWT-JALEBI` |
| W-04 continuous stock movement, balance and variance | `STK-LEDGER` |
| P-05 PO–GRN–invoice match / hold | `PUR-BILL-MATCH` |
| P-02 competitive quotation / single-source exception | `PUR-COMPARE` |
| S-01 customer order, advance and handoff | `SLS-ORDER` |
| S-03 return, quarantine, refund and root-cause decision | `SLS-RETURN` |
| C-04 digital PSP settlement vs statement vs bank | `FIN-SETTLEMENT` |
| C-05 ageing and credit-stop / advances | `FIN-AR-AGING` |
| F-02/03 approved spec, grade, rejection, shelf-life/version | `MFG-SPEC` |
| A-02 monthly COGS/gross/net/AR/AP summary | `FIN-MONTHLY` |
| C-01/02 continuing cash/bank evidence | `FIN-CASHBOOK` |
| P-06 supplier payables and bill ledger | `FIN-AP-LEDGER` |
| S-06 customer receivables and advance ledger | `FIN-AR-LEDGER` |

The previously **11 unmapped** obligations in `control-obligations.json` now **all have printable draft targets**. Their status remains **GAP**, not complete; the other nine remain **PARTIAL**, until every old field, every blocker/role and each conditional formula is proven equivalent and accepted through realistic Owner-run paper scenarios.

Eight additional **industry-specific hypothesis packs** (`REST-KITCHEN`, `RETAIL-REPLENISH`, `MFG-QC`, `PROJECT-DAILY`, `TRADE-CLEARANCE`, `ECOM-FULFILL`, `TECH-DELIVERY`, `SERVICE-JOB`) cover non-sweets/paint industry distinctions but are not yet field validated. Their IDs and all ten canonical business-type selectors come from the existing `data/core10_capability_catalog_v1.json` on trunk: `sweets_bakery`, `restaurant`, `paint_hardware`, `retail_wholesale`, `general_manufacturing`, `construction`, `import_export`, `ecommerce`, `technology_digital`, `services`. No industry processes are described as verified merely because a draft template exists.

`paper-math.js` provides **offline pure, source-informed calculation prototypes** (zero backend posting): stock roll-forward; cash closing; PO/GRN/bill match and payment hold; digital statement/fee/bank reconciliation; ageing buckets and credit policy; quotation selection; Jalebi dough-to-flour conversion / yield / sell price / unsold / oil / syrup; monthly COGS/gross/net. The Jalebi equation mirrors the explicit `R-02` source formula `flour used = issued flour + (opening dough − closing dough) × 100 ÷ approved conversion %`, with no guessed approved rate, tolerance or selling price. Amounts are input-validated (two decimal monetary precision, four decimal quantity precision), with strict missing-policy warnings and no authorization for accounting posts. Tests include exact synthetic expected values, mismatch, missing inputs, maker/checker separation and negative cases.

### Practical paper saving rules applied to version 2

- One **retail showroom** Daily Close per active day, not one for every factory/warehouse/office.
- Jalebi special yield sheet **only when a Jalebi shift operates**, not every sweet shop on every day.
- Handover, GRN/QC, stock transfer, returns and bill matching require **event-specific proof**.
- Stock, cash/bank, AR/AP and supplier ledgers are **continuing books**, not new independent forms per transaction.
- Approved product specifications, recipe cards and shelf-life settings are **versioned master sheets**; batches reference versions rather than repeatedly copying.
- Industry-specific work items remain draft/hypothesis until real-world samples, missing-field checks, responsibility maps and the Owner's operational controls are accepted.

**Audit caveat:** The printed drafts and test results do NOT prove all-paper business continuity, legal/tax compliance, complete A–Z form parity, printed page fit on every printer, or an authorized ERP workflow. Print-only data is not persisted; QR/serial reservation, signed tenant/site permissions and scan-back entry still require separate implementation.

## 5c. BUILT: old-control field crosswalk, executable control gates and offline operator trial

**Traceability that fails closed:** `control-trace.json` contains **20 critical legacy obligations** with original form code, original field keys, original warning-flag IDs, draft form target, actual printable field keys, candidate control-calculator name and explicitly unresolved work. `paper-parity-audit.cjs` validates all of these identities against the frozen extracted definitions, the actual 29-form registry and the 15 pure control/calculation functions. It hard-blocks any dishonest release-readiness/Owner-acceptance claim. On the initial crosswalk, **86 of 1,246 original candidate form-field keys** are explicitly traced through these 20 *selected* high-risk obligations; **1,160 original keys still need triage and mapping**. The unmapped count does not imply 1,160 distinct business problems, only that their dispositions are not yet source-to-target documented. All 163 extracted legacy warning candidates remain indexed.

**New evidence gates (not certified parity):** `paper-controls.js` contains seven pure checks informed by `C-01, W-02, P-04, F-05, S-02, S-03, S-01`: cash custody and independent receiver; two-sided stock transfer; GRN quantity/QC/held segregation/rate approval; factory raw material issue/yield/QC; discount approval; return/refund and food-health escalation; customer order advance/discount/board checker. Missing relevant safety answers are blockers, not an assumed 'No'. None can post, adjust stock or authorize payment.

**Actual offline use:** `checks.html` is a local Bangla/English **Control Review (Draft)** screen. The user selects one of seven workflows, enters source-reference IDs, quantities, values, role IDs, and relevant Yes/No checks, then gets clear BLOCK versus *review-ready-but-not-approved* results. It can print a report showing amounts and blocker codes. It never persists the entered personal/business information, sends data to a backend, impersonates a signature, or claims compliance or posting authority. `control-workbench.js` holds the typed fields and calculation link. `index.html` and `kit.html` link to this review page.

**Realistic scenarios, honestly labelled synthetic:** `pilot-scenarios.json` / `paper-pilot.cjs` run eight repeatable nonproduction days: quiet sweets shop, sweets Jalebi factory dispatch and handover, supplier mismatch, ecommerce return and settlement, paint tint, construction, restaurant kitchen, and services. The runner enforces exact event-specific paper counts and never claims measured labor-time savings or completed offline ledgers. The worker can model a 400-site business, but print batches are intentionally capped to 100 documents.

**Release gate remains RED:** Original 32-form field-by-field parity and 163 old flags have not all been reimplemented and Owner verified. None of the historical 20 obligations is marked release-complete (11 GAP + 9 PARTIAL). More field mapping, expected-result tests with authentic Owner scenarios, workbooks for continuous ledger carry-forward, actual print/layout trials and independent approval workflows are required before any business reliance. ERP staging, live Worker, legacy copies and production data stay untouched.

## 5d. BUILT: full old-field cadence inventory and synthetic end-to-end accounts (2026-11-22)

**All old fields retained, no silent drop:** `field-routing-policy.json`, `field-routing.cjs` and generated `field-routing-report.json` preserve each of the **1,246 old form/field identities**, with original labels, draft form-level cadence, conditional-required/show candidates, candidate role, old warning flags, critical-control links, and a mandatory `preserve_original:true` / `auto_delete:false` / `owner_accepted:false` marker. The older total of **86 critical-linked fields + 1,160 needing individual mapping** remains accurate. The 1,160 entries **now have provisional form-based routing classification**, but **NOT field-by-field approved replacement mappings**.

| Candidate form cadence | Old candidate field entries | What it implies |
|---|---:|---|
| Showroom daily close | 153 | One active showroom closing scope, not all staff fields daily |
| Active factory batch/shift | 60 | Only batch/shift operations, distinct from retail close |
| Triggered operational records | 322 | Need/order/receipt/return/count etc. only on event |
| Two-party custody/movement | 98 | Signed evidence on handover/transfer/issue |
| Source invoice/voucher | 86 | Cannot remove independent financial source document |
| Continuous ledgers | 195 | Update existing page/book, not new full form daily |
| Policy-triggered controls | 107 | Quote/discount/yield trial/product decisions where rule applies |
| Versioned masters | 71 | Approved specification/recipe, not daily re-entry |
| Periodic reviews | 117 | Cash position, weekly management, monthly P&L |
| Periodic settlement | 37 | Match statement/bank for period, not daily default |

**Remaining source-only forms without a separate corresponding draft:** C-03 marketing spend ledger, C-06 cash position/budget, P-01 purchase request, P-03 approved PO, S-04 online and delivery ledger, S-05 commercial/tax wholesale invoice, F-01 new-product authorization, F-04 controlled yield trial, M-01 maintenance request, A-01 weekly management review. C-02 now has a separate *draft*, but its original supporting receipt/voucher and approval evidence is still mandatory. They remain **source-required** until independent functional equivalence has been built and Owner verified. A shared event template is not evidence of parity with any of these source documents.

**Realistic synthetic business/accounting demonstration:** `demo-fixture.json` is a self-contained fake business `DEMO-SWEETS-01` with **3 synthetic sites**, **4 non-real item/lot IDs**, **3 synthetic payment accounts**, **4 fake employee role IDs**, source-referenced transfers/GRNs/orders and money values. `paper-demo.cjs` reconciles item stock, document-backed goods received, PO × accepted-quantity × rate × invoice, physical counts, independent custody, showroom cash/digital/credit splits, bank net-of-fee settlement, refunds, production batch and Jalebi yield, and monthly COGS/AR/AP. It intentionally marks 60+ receivables for periodic follow-up rather than treating ageing as a cash-book pass. There are **no passwords, logins, real accounts, data writes, hosted database test fixtures or external network requests**. All demo transactions stay ephemeral inside a Node process, and the fixture is committed with an unmistakable `synthetic_only` marker.

**Misposting, mismatches and cross-site errors tested:** The demo tests deliberately mutate invoice totals, received quantities, ledger stock, cash count/handover, digital settlement, refund value, missing independent QC/checker, illness escalation, impossible advances, ageing splits, unknown staff, wrong site, duplicate account/item IDs, and real-account markers. Failures are rejected or returned as `DEMO_BLOCKED`; a clean demo is only `DEMO_CONSISTENT_PROTOTYPE_ONLY` and always `readyForERPPosting:false`.

**400-site print, no sheet loss:** `paper-kit.js` `partitionKit(plan,100)` splits a 400-showroom plan into **four independent 100-sheet print batches** without dropped or duplicated form keys. `kit.html` offers an explicit batch selector and prints only the selected batch. The batch cap remains in place; the interface does not silently truncate the business-wide workload.

**Reproduce on Node 22:**

```bash
node modules/paperops/legacy-rule-extractor.cjs --check
node modules/paperops/field-routing.cjs --check
node modules/paperops/paper-parity-audit.cjs
node modules/paperops/paper-pilot.cjs
node modules/paperops/paper-demo.cjs
node --test modules/paperops/tests/*.test.cjs
```

This is an **isolated offline prototype build**, **not a signed ERP feature, Owner-approved business book set, field-parity release or authorized staging/production test run**. No old source was modified. New code requires full field/approval equivalence and live shell/signed-context integration review before any merge/deployment.

## 5e. 50 at a time — built and independently CI-checked Batch 001

The Owner requested **small incremental field reviews, exactly 50 candidate old keys per batch**, rather than one overwhelming 1,160-key signoff. The new non-networked batch system is:

- `field-review/batch-001.json`: immutable-order record of the **first 50 previously untraced source keys**, including their original BN/EN labels, source form, role and conditional-required/display candidate metadata, exact new print-form/field key, source warning IDs, candidate checker, and explicit approval gaps.
- `field-batch-audit.cjs --check`: source/printed-label integrity checks for **exactly 50**, no repeats, no reordered source, every source flag mapped to a named candidate blocker, no false parity/Owner-signoff claim. Its `--next` command returns the **next distinct 50** names for the following build pass (no automatic approval).
- `field-batch-001-checks.js`: three pure, source-informed proof controls. They do **not** authorize a payment, stock post or business release. Every introduced blocker is covered by positive and deliberate-mismatch tests.
- `tests/field-batch-001.test.cjs` and `tests/field-batch-audit.test.cjs`: exercised with synthetic amount, denomination, cash-count, expense limit/receipt and per-item dispatch/receipt cases. The 12 original warning candidates from these 3 historical forms are each represented in the test cases.

| Original source | First-batch key count | Code now built | Remaining work |
|---|---:|---|---|
| **C-02 Expense Voucher** | 19 | New standalone **EXP-VOUCHER** draft, including 19 source-labeled fields, expense receipts, approval policy/exception, fixed imprest and 'sales drawer untouched' checks | Full UI conditional parity, account-specific payment rules and Owner payment workflow |
| **C-01 Cash Handover** | 16 | Existing **CASH-HANDOVER** enriched with original document/ledger/denomination source fields; independent sender/hub note-by-note totals, float policy and mismatch checks | Full physical count/sign-off flow, seal/timing/date and return-copy policy |
| **W-02 Transfer Challan** | 15 | Existing **STK-TRANSFER** enriched with demand, delivery, vehicle, dates/grade, order reference; line-by-line sender vs receiver and demand excess checks | Full 53-field challan parity, crates/trays liability and Owner issue-vs-transfer rules |

**Batch 001:** 50/50 original field identities and corresponding printable slots verified against source candidate metadata; **12 historical warning categories** have synthetic candidate test cases. This is **source-to-print location + partial logic checking**, **not** 50 fully accepted field implementations. The old static candidate matrix still has 86 previously critical-linked fields plus 1,160 originally requiring individual review; Batch 001 addresses 50 *of those 1,160* at the source/print level, leaving **1,110 for first-pass selection**. All still need full sign-off as relevant; no old form may be discarded solely on a passing unit test.

Running this small-batch review locally:

```bash
node modules/paperops/field-batch-audit.cjs --check
node modules/paperops/field-batch-audit.cjs --next
node --test modules/paperops/tests/field-batch-001.test.cjs modules/paperops/tests/field-batch-audit.test.cjs
```

The `--next` result is the deterministic next 50-source-field build queue; no background work or auto-approval occurs.

## 6. Reproduction, safety and deployment

Open `modules/paperops/index.html` locally in a modern browser, choose form/industry, business-wide or branch-specific scope, apply optional header/logo/colour, preview, then use Print/PDF. Save/import a JSON settings file locally if desired. Do not put confidential identifiers in a file shared publicly.

Run `node modules/paperops/legacy-rule-extractor.cjs --check` and `node --test modules/paperops/tests/*.test.cjs` on Node 22. The isolated GitHub Action executes both, plus the canonical live/module legacy guard when present in the merged trunk checkout. No external dependency or backend credentials are needed. Existing live worker, Supabase staging, canonical migration ledger, legacy JS and the owner's live routes are untouched. To publish under the live app later, use canonical build + verify and rollout/rollback rules in `docs/development/AGENT_HANDOVER_CURRENT.md`. **Do not merge or deploy this branch merely because this independent test passes.**
