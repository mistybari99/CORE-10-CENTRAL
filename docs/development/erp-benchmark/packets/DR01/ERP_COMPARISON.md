# DR01 — ERPNext / Frappe / HRMS counterparts and modernization candidates

Snapshot 2026-11-24. CORE10 trunk `9510e198`. Upstream pins, verified with `git ls-remote` and a blobless clone:

| Repo | Ref | Full SHA | Tree entries | Licence |
|---|---|---|---|---|
| frappe/erpnext | v15.126.0 (= `version-15` head today) | `a6f54f9c88dcc24fdf3c59319f24cd9cd9aa91bd` | 5,985 | GPL-3.0 |
| frappe/frappe | `version-15` head | `fd94443a1c5ffe6f1ef0fc02436d62d9ceaa9917` | 4,363 | MIT |
| frappe/hrms | `version-15` head = v15.64.9 | `46b389047bb12fb9c86c1300c3d7bfd5f897f171` | 1,848 | GPL-3.0 |

**Correction (P1 for the coordinator):** the commit recorded in the seed STATE and the mission (`a6f54f9c88dcc24fdf3c59319f24cd9aa91bd`) has 37 hex characters. The real SHA has `cd9` in the middle (see above). This explains the "commit content endpoint 404" noted in STATE.md.
Newer stable lines exist but are **not** used as the baseline: ERPNext v16.60.0 `886ab6ae`, Frappe v16.61.0 `8b19f8c8`, HRMS v16.60.0 `34fbb8a7`. The v15→v16 delta belongs to DR08.

**Licensing:** ERPNext and HRMS are GPL-3.0; Frappe is MIT. CORE10 must study behaviour and implement it independently. No ERPNext/HRMS code may be copied without a licence decision (STRICT_PROTOCOL M02). Frappe (MIT) code may be reused with attribution, but the stack differs (Python/MariaDB vs PostgreSQL RPC/JS), so it is not practical to reuse.

**Scope labels used:** ERPNext core · Frappe Framework · HRMS (a separate app, not ERPNext core) · optional/separate app (agriculture, non-profit, healthcare, education, webshop, POS Awesome) · none found. "None found" means only that DR01 searched the pinned tree paths. It is not proof that the feature does not exist anywhere.

## 1. Capability → counterpart map (all 34 CAP/scope)

Every path below was checked against the pinned tree (`reconciliation.json`: 0 unverified paths). 425/520 Details have at least one verified counterpart.

| CORE10 capability | Current CORE10 state (trunk) | Main counterpart (pinned) | Functional difference that matters |
|---|---|---|---|
| GOV-001 tenant/business/site access | Hosted 0002/0006; signed shell context live | `frappe/permissions.py`, User Permission, DocPerm, Role Profile, ERPNext Company | Frappe restricts by document link values per user. CORE10 has tenant→business→site grants with explicit deny and expiry built into every RPC. CORE10 is stricter. |
| GOV-002 approvals | Hosted 0009–0015, 0018/0019, 0110/0111/0114 | Frappe Workflow + Workflow Action; ERPNext Authorization Rule | Frappe Workflow is state/transition/role with conditions; Authorization Rule is amount-based approver. CORE10 adds typed policies, 1–5 stages, unit thresholds, bounded delegation and exception escalation. CORE10 is richer; it lacks a visual state designer. |
| GOV-003 audit | Hosted 0008/0013/0016/0113 | Frappe Version (track_changes), Access Log, Activity Log | CORE10 has a hash-chained append-only canonical audit with a TRUNCATE guard. Frappe Version is a per-document diff, not tamper-evident. |
| SETUP-001 | Hosted setup RPCs; PR #94 profiles not wired | Setup Wizard, Data Import | ERPNext sets up one company per wizard. CORE10 provisions group→business→sites atomically with a 50/400 site cap control. |
| MDM-001 | Hosted 0150–0153 | Item, Item Variant Settings/Attribute, UOM Conversion Detail/Factor, Item Barcode, Price List/Item Price, Customer/Supplier/Contact/Address, Item Group, Data Import, rename_doc | Missing in CORE10: data import with validation, master merge (`rename_doc` merge), change impact (`linked_with`), price validity dates (verify). |
| RULE-001 Control + micro-engine + intent | Control hosted 0100–0106; A045/A052 engine files not migrated | Custom Field, Property Setter, Client Script, Server Script, Customize Form | Frappe customization edits metadata and runs arbitrary scripts. CORE10 uses typed, versioned, approval-bound settings with no arbitrary code. Different by design (see COMPETITIVE_ADVANTAGE_CANDIDATES). |
| INV-001 stock | Hosted 0200–0206; `/#/stock` live | Stock Entry, Stock Ledger Entry, `stock_ledger.py`, Bin, Warehouse, Putaway Rule, Item Reorder, Stock Reconciliation, Repost Item Valuation | Missing in CORE10: reservation, in-transit receipt with discrepancy, putaway/bins, reorder, consignment ownership, valuation. |
| INV-002 lot/QC/recall | Lots, expiry and inspection hosted in 0203; FEFO/recall only in PR #73 | Batch, Serial No, Serial and Batch Bundle, Quality Inspection | Missing: serial numbers, inspection parameter templates (numeric min/max and formula), FEFO picking. |
| PROC-001 | PO/GRN/QC/approval hosted (0203/0206) | Material Request, RFQ, Supplier Quotation, Supplier Scorecard, Purchase Order, Purchase Receipt, Purchase Invoice, Landed Cost Voucher | Missing: requisition, RFQ comparison, 3-way match, landed cost, supplier returns (PR #123 0207 pending). |
| SALES-001 | Orders 0300 hosted, 0301–0305 trunk; CRM A056 engine only | Lead, Opportunity, Quotation, Sales Order, Pricing Rule, Delivery Note, Pick List, Sales Invoice, POS Invoice/Opening/Closing, Issue, SLA | Missing: delivery/partial fulfilment, POS session, AR posting (PR #122). CRM depth exists but is unmigrated. |
| FIN-001 | 0400/0401 on trunk, not hosted; AR/AP in competing PRs #117/#120 | Account, Journal Entry, `general_ledger.py`, GL Entry, Payment Ledger Entry, Payment Entry/Reconciliation, Period Closing Voucher, Accounting Period, Bank Transaction/Reconciliation Tool, Budget, Cost Center, Accounting Dimension, Process Deferred Accounting | CORE10 journal is immutable and source-linked, with a reversal table. Missing: dimensions, budget, bank, deferred revenue/expense, statements. |
| FIN-002 tax | A030 preview only | Sales Taxes and Charges Template, Tax Rule, Tax Withholding Category, Exchange Rate Revaluation, Consolidated Financial Statement | ERPNext ships tax templates but not Bangladesh statutory content in core (`erpnext/regional` covers other countries). DEC-07 keeps statutory rules OFF until an official source is verified. |
| MFG-001 | 0500–0504 on trunk, not hosted | BOM, Work Order, Job Card, Routing, Workstation, Production Plan, Downtime Entry, Subcontracting Order | CORE10 recipe batches with substitution rules and waste exceed ERPNext for food. Missing: routing, capacity, WIP, MRP, subcontracting. |
| ASSET-001 | A055 engine files (deep), not migrated, own `am_grants` | Asset, Asset Movement, Asset Maintenance, Asset Repair, Asset Depreciation Schedule | CORE10 is strong on maintenance and work orders. Missing: depreciation/GL boundary. |
| HR-001 | A051/A053/A054 engine files, 76 Details drafted, CI green, not migrated | HRMS Attendance, Shift Assignment, Employee Checkin, Leave Application, Salary Structure, Salary Slip, Payroll Entry, Job Requisition/Applicant/Offer, Appraisal, Training Event, Employee Separation, Full and Final Statement (Employee lives in ERPNext `setup`) | The 4 proposed HR extensions (D083–D086) map 1:1 to HRMS DocTypes. They are ADOPT_CANDIDATE pending Owner scope. |
| PROJ-001 | none | Project, Task, Timesheet | No BOQ, retention or progress billing in ERPNext core |
| TRADE-001 | legacy `landed.js` only | Shipment, Landed Cost Voucher, Exchange Rate Revaluation | No LC, customs or Incoterm documents in core |
| CHANNEL-001 | campaign/consent in A056 engine | Web Page, Subscription, Payment Request, Campaign | Webshop is a separate app since v14 |
| FOOD-001 | none | none found (0 tree paths match "restaurant") | Restaurant module not in v15 core; CORE10 must write its own spec |
| PAINT-001 | PR #95 only | Item Variant Settings, BOM (generic) | No tint/shade/dealer-scheme module in core |
| PARTNER-001 | A022 engine | Shareholder, Share Transfer | ERPNext covers equity shares only; non-equity profit agreements (R054–R057) have no counterpart |
| DR-001, DRIVE-001, INTEGRATION-001 | mostly none / PR #27 | `frappe/utils/backups.py`, Google Drive (backup), Webhook, Integration Request, Email Queue, Connected App | Frappe Drive integration is backup upload, not document provenance |
| OFFLINE-001 | root helper + PR #23 | `selling/page/point_of_sale` (online) | No general offline-draft quarantine found in core |
| AGRI / NGO / REG / FRANCHISE / SAAS / SIMULATION | none / PR #77 | none in core (separate apps or none) | DEFERRED / parked; requirements retained |

## 2. Modernization candidates (MOD-xx), each with an evidence class

No performance number is claimed anywhere. **All latency/throughput items are NOT MEASURED.** Each benchmark spec in §3 is for an authorized builder (DR08/G02 protocol) to run later.

### MOD-01 Quantity and money precision policy — SOURCE-VERIFIED inconsistency (P0)
- **CORE10 now:** stock quantities are `numeric(15,3)` and must equal `round(x,3)` (0200 L16/L34/L81, 0201 L43, 0203 L47). Sales quantities are accepted at `round(q,6)` (0301 L53). Manufacturing yield and qty-per-batch use `round(x,6)` (0500 L9/L25). Money uses `numeric(18,2)` on PO price (0203 L48), `numeric(18,4)` on journal lines (0400 L115), and a per-param `scale` in sales (0301 L58).
- **Risk:** a sales or production quantity with more than 3 decimals cannot post to stock 1:1. The handoff must round, and the rounding policy is not centralised, so stock and documents can drift by up to 0.0005 units per line. Money mismatch between 2 and 4 decimals needs an explicit round-off rule before Sales→Money and GRN→AP posting.
- **ERPNext method:** System Settings `float_precision`/`currency_precision`, a UOM-level `must_be_whole_number`, `conversion_factor` per transaction line, and a Company `round_off_account` used by `general_ledger.py` (L176–L193 `process_gl_map` / round-off).
- **Proposal:** one Control-owned precision policy per UOM and currency (typed, versioned per DEC-08). Store `stock_qty = qty × conversion_factor` at stock precision on every source line. Use an explicit round-off journal line rule. Back-compat: existing rows already satisfy 3 dp, so the change is additive.
- **Tests:** a property test that Sales/Mfg quantity → stock movement conserves to the declared precision; a negative test that rejects a 4-dp stock quantity; a Money test that rounding residue posts to the configured round-off account; decimal-exact report reconciliation.

### MOD-02 Stock reservation with locked allowed-qty — ADOPT + improve (P0, BENCH-003)
- **CORE10 now:** no reservation in any migration. `post_stock_event` locks the balance row (`… FOR UPDATE`, 0200 L105), so posting is serialized per location+item.
- **ERPNext method:** Stock Reservation Entry. `validate_with_allowed_qty` (blob `025671889490`, L429–L470) computes `allowed_qty = min(available_qty, voucher_qty − delivered − reserved)` from reads, without an explicit row lock in that function. Concurrent reservations are therefore a race candidate (source-inferred, not reproduced).
- **Proposal:** a `reserved` column or reservation rows under the same balance-row lock. `available = on_hand − reserved` is enforced by a CHECK. Release on delivery, cancel or expiry. Reservations are Control-gated per business/site.
- **Tests:** 2-session oversell race (`tests/migrations/*race*` pattern already used by 0203); expiry release; cross-site denial; reservation must not allow a negative available quantity.

### MOD-03 AR/AP open-item model — consolidate #117 vs #120 (P0, BENCH-008)
- **CORE10 drafts:** both PRs add `finance_arap_links_v1` + `finance_arap_allocations_v1` with `FOR UPDATE` on the journal and allocation rows (#117 0402 L116/L202; #120 0402 L113/L189). Outstanding is computed on read. #120 is a superset (0404 trade control, 0405 GOV-002 approved post).
- **ERPNext method:** Payment Ledger Entry (`payment_ledger_entry.py`, `against_voucher_*`, `delinked`), `create_payment_ledger_entry` / `update_voucher_outstanding` (`accounts/utils.py` L1959/L1982), and reconciliation with `for_update` (L1622).
- **Proposal:** keep the CORE10 open-item design, which matches PLE semantics. Pick one PR via the Board. Add an explicit "delink on reversal" equivalent and a stale-allocation version check. Measure the outstanding-on-read query at 100k open items before deciding whether to persist outstanding.

### MOD-04 Quality inspection parameters — MODERNIZE_CANDIDATE (P1, BENCH-012)
- **CORE10 now:** `procurement_inspect_v1` and `mfg_inspect_v1` record accepted/rejected quantity and a lot status (0203). There are no parameter readings.
- **ERPNext method:** Quality Inspection Template readings with numeric `min_value`/`max_value` (`quality_inspection.py` L333–L352) and `formula_based_criteria` / `acceptance_formula` (L316–L317), which is evaluated as an expression.
- **Proposal:** parameter templates per item group. Evaluate numeric ranges in SQL. Express any formula through the certified A045 `threshold_rule_v1` handler, never via `eval`. This preserves PaperOps F-02 grade cards, R-01 temperature and GRADE_AND_SHELF_LIFE obligations.

### MOD-05 Period close — ADOPT_CANDIDATE (P1, BENCH-009)
- **CORE10 now:** `finance_periods_v1` and `finance_set_period_v1` (0400) lock posting by period.
- **ERPNext method:** Accounting Period with per-document-type closure (`validate_accounting_period`, `general_ledger.py` L146), Period Closing Voucher, and freezing date (`check_freezing_date` L433).
- **Proposal:** add per-source-domain closure, closing-entry generation, and an audited reopen through GOV-002.

### MOD-06 Backdated postings and valuation repost — INVESTIGATE (P1)
- **ERPNext** reposts future SLEs (`repost_future_sle` L314, `update_entries_after` L686) and runs Repost Item Valuation jobs. This is powerful but heavy and a known source of regressions (DR08 domain).
- **CORE10** has no valuation yet (PR #21 is unported).
- **Decision needed:** either forbid backdated stock postings by Control default (simplest and safest at 400 sites), or design incremental revaluation. Write a policy before porting PR #21.

### MOD-07 Engine files → numbered migrations — process modernization (P0)
155 Details (HR, assets, CRM, micro-engine, intent, partner, tax preview, stocktake, reporting) run only as `internal/enterprise-sql/*.sql`. They are tested in disposable CI (53/53 green at the trunk head) but cannot reach staging under DEC-01. Each port must go through `NNNN_*.up/down.sql` with Auth/Audit dedup (CHG-004/005) first. **This is the single largest preservation lever.**

### MOD-08 Duplicate auth and audit stores — SOURCE-VERIFIED (P0 before port)
A055 `am_grants`, plus module audit tables `wf_/am_/a056_audit`, duplicate the Auth port and the canonical audit (AUD G2/G3, CHG-004/005). ERPNext uses one permission engine and one Version log. CORE10 must converge on Build01 + `canonical_audit_events_v1` before these modules are migrated.

### MOD-09 Optimistic concurrency on every editable record — INVESTIGATE (P1)
Frappe uses `modified` checking (`document.py` L717–L731; `check_if_latest`). CORE10 uses `p_expected_version` in A045 and request-key idempotency elsewhere. Builders should inventory all `save_*`/`set_*` RPCs and require an expected version or a request key. A future CI check should enforce this, like the control registry check.

### MOD-10 Form meta for PaperOps — handed to DR02
Frappe DocField (`docfield.json`) gives `depends_on`, `mandatory_depends_on`, `read_only_depends_on`, `permlevel`, child tables and naming. PaperOps W02-02 ("conditionally visible but not syntactically required") is exactly the `mandatory_depends_on` class of gap. DR02 owns the field-level comparison.

### MOD-11 Stale coordination records — PROCESS (P0, cheap)
`MIGRATION_RESERVATIONS.json` and the handover say staging has 46 rows/max 0206. The live ledger (read-only, 2026-11-24) has **47 rows/max 0300**. Builders planning 0301+ must re-read the ledger. The trunk owner should update both files.

## 3. Benchmark specifications (for later authorized execution; NOT MEASURED)

| ID | Workload (fixed synthetic) | Metrics | Gate |
|---|---|---|---|
| BM-01 site lists | 10 businesses × {10, 100, 400} sites; `build01_context_v1`, `owner_business_sites_v1`, `inventory_list_balances_v1` (0205 keyset) | p50/p95/p99, query count, EXPLAIN (index-only?), bytes to a 390-px client | No sequential scan over all tenants; p95 target set *after* the baseline |
| BM-02 stock contention | 2–32 concurrent `post_stock_event` on the same item+location vs different items | throughput, lock waits, deadlocks, error rate, exact balance = Σ movements | 0 negative balances, 0 lost updates |
| BM-03 reservation race | after MOD-02: N parallel reservations totalling > on_hand | over-reservation count | must be 0 |
| BM-04 AR outstanding | 10k/100k open items; allocate/reverse under 8 sessions | p95 allocate, outstanding-on-read latency | outstanding matches the journal |
| BM-05 approval routing | 5-stage route, 1,000 pending per business | inbox p95, stale-decision rejection | no cross-scope leakage |
| BM-06 mobile steps | PaperOps C-01/W-02/W-03 on 390 px, bn | taps, typed fields, payload bytes | no field lost vs legacy declaration |

Environment rule: PG17 disposable (same image as CI), fixed seed, 5 repetitions, cache state recorded. Never compare CORE10 timings with ERPNext timings across stacks (START_HERE gate).
