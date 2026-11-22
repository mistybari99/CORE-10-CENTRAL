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

## 5f. BUILT — Two more exact 50-field source batches (002 + 003)

The Owner requested executing the next **two small 50-source-field steps at once**, preserving the no-false-approval rule. The branch now includes three audited blocks (001, 002, 003), **150 distinct formerly-untraced source-field IDs** with exact BN/EN source labels in actual print fields. **1,010 of the original 1,160** await the same first-pass print-field review. The original 86 high-risk keys and the 11 GAP + 9 PARTIAL business obligations remain separately tracked and unapproved.

| Batch | Original source | Newly mapped source fields | Printable destination | Check status |
|---|---|---:|---|---|
| 002 | W-02 goods transfer | 33 | Additional **TRANSFER-DETAIL** event-only proof (goods/grade, crates/trays outstanding, damaged goods, source documents and payment) | Source flag checks reuse B001 transfer calculator |
| 002 | W-03 independent physical count | 9 | Existing **STK-COUNT**, with start/end, counter vs keeper, frozen stock movement and item/unit | New W-03 tolerance/role candidate calculator |
| 002 | R-01 showroom opening | 8 | Existing **OPS-DAILY** closing, with opening duty manager, approved float and imprest references | New source-informed R-01 calculator |
| 003 | R-01 further showroom evidence | 50 | Additional **SWEETS-SHOP-CHECK** (food-safety, fridge/freezer, expiry, receiving, cleaning, voucher references), only on applicable operation/event | Same R-01 calculator, focused synthetic negative tests |

**Why add-on forms?** 83 source-derived details are not blindly attached to every shop's routine sales close or every transfer. The paper kit can include `transfer_detail` and `shop_open_controls` events, which print dedicated **DRAFT supplements only when relevant**. This is a workload-minimization *proposal*, not a license to skip statutory, original required, food-safety or signed records. The ordinary daily form is still produced for a showroom. Whether each evidence item is required on every opening must be decided against Owner process and approved local policy, not by this draft.

**Source-informed checkers, not parity certification:** `field-batch-002-003-checks.js` has read-only/zero-backend prototype functions:

- W-03 count line book-vs-physical variance, independently counted/witnessed stock, no goods movement during count, approved quantity percent and/or financial tolerance. Small vs outside variance are both reported for review, and a count never posts an adjustment. Undefined tolerance causes an explicit missing-policy requirement.
- R-01 independent opening and closing cash float, imprest cash+receipts, received vs written goods and cleaning checkers, category sales vs total, first/second cash counts, expiry losses, independent wastage approval and signers; fridge thresholds are external and may be signed/negative for freezers. No acceptable fridge temperature is invented.
- Extracted original source warning families W-02 **5**, W-03 **4** and R-01 **11** are mapped to candidate program blocker names and deliberately-triggered negative tests. Across all three batches there are **27 distinct historical warning families** (43 listed references when repeated original forms appear in multiple batches). The repository still indexes all 163 historical warnings; 27 is *not* whole-form rule parity.

**Hard gates:** `field-review/batch-002.json` and `field-review/batch-003.json` contain **exactly 50** immutable source IDs each with real destinations, required/conditional/role candidate metadata and `parity_certified:false`. `field-batch-audit.cjs` now checks batch order 001→002→003, forbids duplicate source IDs, verifies original source flags against executable candidate maps, and refuses false approval. The new `tests/field-batch-002-003.test.cjs` uses fake stock counts, money, fridge/freezer readings and tampered source-field mappings.

Reproduce and identify the next 50 distinct source fields:

```bash
node modules/paperops/field-batch-audit.cjs --check
node modules/paperops/field-batch-audit.cjs --next
node --test modules/paperops/tests/field-batch-002-003.test.cjs
```

**Current form registry = 32 bilingual printable DRAFT/HYPOTHESIS templates.** Tests are code/synthetic-input evidence only: no scanned signed paper, accounting mutation, RLS integration, legal acceptance, complete source branch parity or permission to merge. The existing source preservation and live/module guards remain mandatory.

## 5g. Clarified Owner intent — semantic rule recovery, not merely generating mock data

The Owner clarified that the **1,160** originally unlinked candidate field keys are *not 1,160 mandatory text boxes to copy to an ERP*. They were not yet included individually in the 20 highest-risk control traces; they may be source inputs, calculated outputs, ledger/master references, conditional evidence, signatories or repeated displays. The two added 50-field review batches (002 + 003) are source-to-print prototypes, **not** a complete business-rule audit or permission to expand daily paperwork.

**New source-semantics layer:** `field-semantic-triage.cjs` deterministically constructs `field-review/semantic-triage-001-003.json` from the original extracted constructor/required/visibility/role metadata and the first three exact 50-field batches; CI executes `--check`. All **150** original keys now have an explicit **proposed** semantic class, data origin, risk level, source requirement evidence and named next proof action. This helps distinguish computed references from genuinely required human evidence without claiming source execution or proven ERP parity.

Source-level observations for the first 150 (counts can overlap): **30** explicitly always-required syntax candidates, **6** conditionally-required candidates, **16** conditionally-visible candidates, and **80** conservative high-risk review flags. The proposed data origins include **16 calculated/display** candidates, **7 continuing-ledger** candidates, **39 reference** candidates, **30 human control-attestation** candidates, **9 actor/role** candidates, **1 document attachment**, **1 line collection** and **47 general input/conditional evidence** candidates. These are *heuristic classification*, never validated authority for dropping a document. The final source formula, branch trigger, posting ledger, Owner rule, legal source and operational signoff remain open. Signed field parity count remains **zero**.

**Examples of the intended destination after actual process verification:**

- Original C-02 `total`, `sum_cr`, `imprest_text` and C-01 `handover`: **recompute from referenced money lines and approved float policy**; do not demand a second manual re-entry of the total.
- W-02 `crates_due` and `trays_due`: candidate **returnable-packaging liability ledger**, not an additional daily full form; must still reconcile signatures and returns.
- R-01 `vouchers` / `v_no` / `v_amt`: proposed **links and summaries from independent expense source vouchers**, not payment authority in the retail close.
- R-01 `temp`, `expired_shown`, `expired_informed`, `clean` and W-03 `movement`: preserve real **food-safety, independent checking and stock-count freeze evidence** even if the print burden is reduced.
- R-01 `t2_1` / `t2_2`, C-02 `approved_by`, W-02 `cash_amount`: **explicitly preserve conditional trigger verification**; static `show` syntax does not prove the business rule is implemented.

**Correct continuation per 50:** (1) read each original source declaration/conditional/role/calculation and relevant warning branch; (2) decide input vs derived vs reference vs linked ledger vs control attestation, cross-referencing real owner process; (3) implement the **smallest event-driven normalized flow** rather than reproducing every old paper column; (4) test positive, negative, boundary, role separation and ledger continuity with synthetic items/accounts; (5) record exact gaps and never mark Owner accepted without field evidence. Tests protect the code, but do not substitute for source semantics, signed business workflow or Owner approval.

Reproduce:

```bash
node modules/paperops/field-semantic-triage.cjs --check
node --test modules/paperops/tests/field-semantic-triage.test.cjs
```

No live ERP branch, worker or real database is modified by the classification or its tests.

## 5h. Real source-rule investigation found missing historical warnings (not a demo-only check)

A direct read of the **frozen old R-01 `calc(e)` body** revealed a **material shortcoming in the baseline source extractor**. The first 163 historical warning candidates were found by a regex requiring a **literal flag ID and literal severity**. It silently missed original rules whose `severity` was computed at runtime and warning identifiers assembled from a numbered fridge. The exact source is retained, unexecuted, at `legacy/islamia-erp/forms.js`.

**Five additional runtime warning codes in R-01** were recovered that were absent from the R-01's initial 11 static-warning list:

| Old dynamic warning | Source rule now evidenced | Candidate code and boundary tests |
|---|---|---|
| `goods_money_gap` | Goods-based BDT vs retail BDT (total sale less party cash); **OR** of percentage/absolute BDT tolerance determines yellow/red warning | `r01-hidden-warning-checks.js` `goodsMoneyGap` |
| `cash_short_over` | Expected cash includes opening float, sale and digital amounts, dues, new/prior advances, refunds, credit, hub deposit and signed rounding; count mismatch uses approved `cash_tol` for severity | `cashShortOver` |
| `temp_out_1`, `temp_out_2`, `temp_out_3` | One dynamically constructed warning ID per fridge; each checked against independently configured min/max, including negative/freezer temperatures | `temperatureFlagFromChecker` maps the existing R-01 candidate temperature check blockers |

**Proof and fail-closed tests:** `r01-hidden-source-audit.cjs` reads the preserved original `forms.js` as text, verifies the exact dynamic-warning source expressions exist, verifies the five warning IDs were not included in the original R-01 11-flag snapshot and that the candidate gates exist; `field-review/r01-hidden-source-flags.json` preserves the predicates, source policy names, caution and test status. `tests/r01-hidden-source-audit.test.cjs` runs valid, over-tolerance and under-tolerance cash/goods demos; missing policies; money precision rejection; and distinct fridge-1/2/3 out-of-range cases. No original legacy app code executes.

**Important accounting rule:** `163` is the count of the *original static-regex warning candidates*, **NOT the entire old warning inventory**. These **five additional runtime warning codes have been found in one form only**; do not silently revise the whole 32-form total to 168 or assert exhaustive warning parity. Remaining original source calculations and dynamic warning patterns must undergo the same independent inspection, before any ERP release or Owner signoff. Tests confirm candidate formulas, **not** the complete historic R-01 cashbook parity. No real account, live data, signed ledger or staged payment is changed.

```bash
node modules/paperops/r01-hidden-source-audit.cjs
node --test modules/paperops/tests/r01-hidden-source-audit.test.cjs
```

## 5i. Owner-directed deep recheck of the PREVIOUS 150 (not just mock tests)

Owner explicitly requested that the first **150 old fields be independently rechecked using the intended actual-source business rule method**, rather than simply accepting 150 print slots or synthetic demo PASS results. This is a **re-review of the SAME 150** and **does NOT reduce the remaining first-pass 1,010** count again.

**Built:**

- `field-deep-source-recheck.cjs` reads the untouched `legacy/islamia-erp/forms.js` text and independently extracts **all 150 exact original field calls** in the same three 50-field batches: C-02 **19**, C-01 **16**, W-02 **48**, W-03 **9**, R-01 **58**. It validates constructor aliases, BN/EN field labels, true literal `req` / `show` / `who` attributes, and possible original `calc(e)` references, against prior source and batch indexes. Original call snippets and explicitly unresolved proof state are preserved in `field-review/deep-source-recheck-001-003.json`.
- **30** original always-required syntactic candidates; **6** conditional-required; **16** conditional-visibility; **34** source fields found referenced in the historic calculator text (a conservative reference search, **not 34 proven formulas**). No one marked source formula, workflow or Owner signoff complete.
- `source-conditional-recheck.cjs` cross-checks all **16 exact source expressions** and tests conditional outcomes using fail-closed normalized evidence. All six `req` branches (expense over-limit approver, missing-receipt reason, cash recount difference, transfer outside-demand reason, movement-during-stock-count explanation, showroom safety defect) are explicitly checked true/false/unknown. Source-only show rules including cash-on-transfer, customer order, busy-day extra temperature and expiry reporting also covered.
- **UNPROVEN HELPERS:** the original `O("cash_now")`, `O("open_counted")`, and `n(e.d.imp_cash)` helpers do **NOT** become assumed optional/visible rules. They stay `UNKNOWN_MUST_REVIEW` until genuine old helper semantics and relevant surrounding source behavior are reconstructed.
- `field-review/functional-gaps-001-003.json` records **11 concrete unresolved source-to-prototype control/ledger gaps**, with old field IDs, original source phrase, current prototype, risk and action. `field-functional-gap-audit.cjs` fails if any evidence reference is invented, the gap count drifts, or someone claims Owner/live approval. Example open issues: C-02 old blank=Cash vs stricter explicit-mode prototype; old missing receipt yellow vs current candidate BLOCK; cash custody's independent physical ledger proof; originally entered returnable crates/trays due vs yet-unbuilt candidate ledger; inventory movement/counter independence and authorized adjustments; fridge/expiry evidence; original source visibility helper `O()`; linked expense voucher cashbook; full daily cash including digital, advances, refunds and transfers.

**What the first 150 recheck proves:** The exact old source field declarations and preliminary roles/branch syntax were independently verified; the 16 source conditional patterns are identified and tested against explicit synthetic inputs; proposed destination choices and actual unresolved rules are inspectable with individual source IDs. **It DOES NOT prove that all 150 business behaviors, formulas, permissions, real ledgers, compliance or real Owner workflows are interchangeable.** No old source was run. New stricter fail-closed checks are not asserted to have identical old warning severity.

Reproduce in Node 22:

```bash
node modules/paperops/field-deep-source-recheck.cjs --check
node modules/paperops/source-conditional-recheck.cjs
node modules/paperops/field-functional-gap-audit.cjs
node --test modules/paperops/tests/deep-source-recheck.test.cjs modules/paperops/tests/field-functional-gap-audit.test.cjs
```

**Release boundary:** The first 150 field declarations are now genuinely source-rechecked, but **zero** source business-rule parity approvals and **zero** Owner acceptances are claimed. Do not merge, replace original paper, deploy, or post any ERP transaction on this evidence alone. **1,010** still await first-pass mapping; original additional high-risk obligations remain separately tracked. Subsequent work must resolve the 11 concrete gaps and prove real normalized event/ledger continuity with independent actor, account, site and transaction evidence rather than collecting duplicate paper fields.

## 6. Reproduction, safety and deployment

Open `modules/paperops/index.html` locally in a modern browser, choose form/industry, business-wide or branch-specific scope, apply optional header/logo/colour, preview, then use Print/PDF. Save/import a JSON settings file locally if desired. Do not put confidential identifiers in a file shared publicly.

Run `node modules/paperops/legacy-rule-extractor.cjs --check` and `node --test modules/paperops/tests/*.test.cjs` on Node 22. The isolated GitHub Action executes both, plus the canonical live/module legacy guard when present in the merged trunk checkout. No external dependency or backend credentials are needed. Existing live worker, Supabase staging, canonical migration ledger, legacy JS and the owner's live routes are untouched. To publish under the live app later, use canonical build + verify and rollout/rollback rules in `docs/development/AGENT_HANDOVER_CURRENT.md`. **Do not merge or deploy this branch merely because this independent test passes.**
