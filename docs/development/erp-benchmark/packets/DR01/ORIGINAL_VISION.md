# DR01 — Original vision of CORE-10-CENTRAL (reconstructed from sources)

Packet DR01/A01 · Board `ERP-BENCH-DR01` · Snapshot 2026-11-24 · Trunk `9510e19826654e50ae87158aa4dcdfd968a058aa` · Research base `a8e271e09339efc9fc91bbd7edf71bb687e611f0`
Research only. NO PRODUCT CODE. CI NOT RUN.

## 1. Authoritative sources read (all accessible in this session)

| Source | ID / link | What it fixes |
|---|---|---|
| Master Decision Book (22 sheets) | `1IYzGBtUVNjah31cPVSFHkzgO7P093jTfZS0CopWrDxs` | D001–D063 (57 rows + 6 archived by REV-001), R001–R130 (+R124-IMPL-NOTE-01), 520 MODULE BUILD DETAIL rows, 32 CAP, 61 C10-A actions, 93 evidence rows, 128 change-log rows, 16 revisions, 37 discussion rows |
| 520-row Code Gap Sheet | `1C8yAMHvbyj8-5DkWUuR2FNB8DwmvdKr35SyJLIzgkho` | 5-state code status per Detail ID as of 2026-11-16 |
| Final Decisions DEC-01…07 | `1o1gOFULxTDMJIiE-jGzy_1ripZ1ciQz79DvmbW9yszs` | schema, pack split, 5 engine ports, template order, build order S0–S10 |
| Code Gap Audit AUD-D01…D12 | `1-wDR0B7_FMNMRworUhLZyAS0DGwAtlRMObF6ybj0aIM` | baseline, evidence standard, side-PR dispositions |
| Change Register CHG-001…111 | `1VJHncLoLvBTLaFZ0AtxujEkbYTkuHgUgdRkOlcDU3JI` | 61 numbered changes (gaps in numbering are by design) |
| Re-alignment plan 2026-11-21 | `1gqWHIDdB81H2-VZqce2E5VbRSZOTOgGraszGt5yeDjc` | "one running path first", P1–P8 |
| Repo: AGENTS.md, AGENT_HANDOVER_CURRENT.md, WORK_SPLIT_AND_PROTOCOL.md (DEC-08/09/10), HANDOFF_S1, PR_STATUS_2026-11-23, S0_SIDE_PR_DISPOSITION, internal/migrations/README.md | trunk `9510e198` | current build order and gates |

Not yet read: D049 guide doc `1VNB-ub0V49fg1QAPqyALk-1P79eqgbHJZwAdbq5-mCg`; the RESEARCH ARCHIVE sheet (16 documents in 52 chunks) was captured but not analysed. Both are queued for batch 2 (see DR01_PROGRESS.md).

## 2. The Owner's destination, in the Owner's own decision IDs

**Goal 1 — the Owner's own group (NOW).** One platform for about 10 different businesses (sweets/bakery, paint/hardware, and others). Each can have 100–400 branches, factories, showrooms and warehouses (D030, R041–R045). The Owner runs one central Owner Control Centre and can enter each business to manage staff, permissions and pending decisions (D001–D003, D033, R001–R003).
- Every business has its own full Owner Board, brand, theme and staff app. Staff never see the Central layer or sister businesses (D004–D006, D027, R013).
- Legal entity, tenant, business, brand, operating site and physical stock location are separate layers (D008, R004–R006). New sites come from one server-validated service (D007, D009, R007).
- Consolidated reports, plus drill-down into each business. Internal transfers are not sales. Missing inputs show as incomplete, not as invented profit (D025, D035, R046–R051).
- Quick Setup is not a "lite ERP": quick and advanced setup use the same full engine (D030, D032, R027–R032).
- Ten starter templates are the baseline, not the limit: Sweets/Bakery, Restaurant, Paint/Hardware, Retail/Wholesale, General Manufacturing, Construction, Import/Export, E-commerce, Services, Technology/Digital (D031, R033–R040, DEC-05). Sweets is the first pilot, not the whole app (re-alignment plan §1).
- Bangla first, English supported, mobile and desktop (390/1440 px gates). Contextual guidance and formula explanation in BN/EN (R128, D049).
- DEC-08/D057/D061: the Owner can switch any feature on or off per business and site, require 0–5 approval stages with thresholds, allow or deny people and roles with expiry, set typed limits with effective dates and scope, grant one-off exceptions with a reason, and see history and undo. Nothing configurable is hard-coded. One Control Centre. When an option is missing, the Owner can state the need in plain language (owner intent, A052) and it is filed as a numbered requirement.

**Goal 2 — commercial SaaS (LATER; A024 deferred).** External customers become independent tenants with full isolation (D036, R062–R068). The operator does not get automatic data access. Support access must be consented, scoped, revocable, audited and disclosed to the customer (R063–R064). The platform layer covers plans, modules and licensing. A tenant-safe foundation is built now; commercial rollout comes last (R068). As of today no platform role exists (handover §1).

**Hard constraints that shape everything:**
- One engine per concern: Auth, Master, Stock, Money, Approval+Audit, plus Control (DEC-03, DEC-08). No duplicate ledgers.
- GitHub first, with versioned migrations and rollback (D043, DEC-01).
- The legacy Islamia (IMG) ERP stays protected and frozen: 463 blobs, original routes, 8 locations, 193 reports (D042, D051, R118, R130).
- "Approved" means the scope is approved, not that it is built (R074). Every feature must be traceable from decision to requirement to work to test (R073).

## 3. Requirements that go beyond an ordinary ERP (preserve explicitly)

| Theme | Original IDs | Why it is beyond a conventional ERP |
|---|---|---|
| Group → business → site control with per-site toggles, staged approvals, explicit deny and expiry, and versioned parameters | D033, D045, D057, D061, D062, R014–R026, R123–R124 | ERPNext has role and user permissions and workflows. It has no single per-feature control port with on/off + approval + limits + history per business/site. |
| Owner intent → capability, plus explainable ERP | D049, R128, A052 | No counterpart in ERPNext core |
| Owner Micro-Engine Workshop (safe, certified, inert-by-default descriptors) | R124-IMPL-NOTE-01, A045 | Frappe Server Scripts run arbitrary Python. CORE10 deliberately forbids arbitrary execution. |
| Enterprise Business Simulation (U01–U26) | D039, D040, R081–R114 | Not in ERPNext core |
| Partner / investor / non-equity funding with profit-basis agreements | D034, R052–R061 | ERPNext Share Management covers equity transfers only |
| Paper-to-ERP operating knowledge (PaperOps 1,246 fields: cash custody, two-party goods transfer, blind counts, yield tests, showroom safety) | PaperOps PR #151–#156, D051, R130 | Captures the Owner's real operating controls |
| Staff-invisible group structure (white-label per business) | D005, D006, D027, R013 | Uncommon in a multi-company ERP |
| Offline draft with conflict quarantine | PR #23, OFFLINE-001 | ERPNext v15 POS runs online-first; no general offline quarantine |
| 400-site Owner-raised cap with a 50 default | D063, 0118, Board B-036 | Configurable governance limit |

## 4. How the vision evolved (dated)

| Date | Event | Source |
|---|---|---|
| 2026-11-09 | REV-001 archived D016–D020 and D026 (migration audit and old-DB retirement folded into the combined record) | DECISION REVISIONS |
| 2026-11-11 | Preview-first build (A045–A051); Claude given 3 packages A055, A052, A053+A054 | AGENTS.md |
| 2026-11-12 | D051 strict preservation of the Islamia ERP | DECISION BOOK |
| 2026-11-15/16 | D054 audits finalized; C10-AUDIT-CG-01: 520 Details, 32 CAP, 14→19 packs, 5 engine ports; DEC-08/09/10 | Final Decisions, WORK_SPLIT |
| 2026-11-16 | S0/S1-a: one `core10` schema (D056 supersedes the DEC-01 fixture sentence) | HANDOFF_S1 |
| 2026-11-21 | Re-alignment: one running multi-business path first; D063 tenant bootstrap ratified | re-alignment doc, D063 |
| 2026-11-22 | Legacy quarantine (PR #131), shell import/nav/signed context (#134/#140/#142); staging 0001–0206 | handover §3 |
| 2026-11-24 | Sales 0300–0305 re-integrated (#153); staging ledger now max 0300 (DR01 read); ERP benchmark program (#157) | this packet |

## 5. Preservation conclusions

1. All original IDs found have a traceable destination in `PRESERVATION_CROSSWALK.jsonl`: 520 Details, 131 R rows, 57 live D plus 6 archived D, 34 CAP/scope, 61 CHG, 61 A and 1,246 PaperOps. There are no duplicate IDs within any kind.
2. One trace gap: **R130** (LOCKED original Islamia preservation) is in REQUIREMENTS LOCK but missing from REQUIREMENT TRACE, and no Detail row names it. Its purpose is covered by the legacy preservation evidence (463/463 blobs verified), but the trace row should be added by the Decision Book maintainer.
3. **0 of 520 Details are certified per detail.** Decision Book column U says `NOT_CERTIFIED_PER_DETAIL` for every row. Any "100 % preserved" claim is therefore false today. What *is* true: every requirement is retained in the register, and 83 of 520 now have code on hosted staging migrations.
4. **Biggest loss risk:** working engines that sit only in `internal/enterprise-sql` (HR, assets, CRM, micro-engine, intent; 155 Details) or only in open draft PRs (75 Details: costing #21, offline #23, integration #27, QC/recall #73, paint #95, simulation #77, language #103). If those PRs are closed or the engine files are deleted before porting, real behaviour is lost even though the requirement survives on paper.
