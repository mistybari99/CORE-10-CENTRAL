# Research checkpoint and continuation queue
Observed 2026-11-24; reverify at session start. Board ERP-BENCH-001, docs-only. No product code, staging, deployment or trunk changes in this research package.

## Pinned sources
- CORE10 canonical trunk 9510e19826654e50ae87158aa4dcdfd968a058aa (PR106; PR153 merged Sales fix, reported 21/21). 1,530 recursive tree entries. Handover last documented 2026-11-23 Worker 1a99371f-2cf2-4546-bc18-321f76224a7e; 56/56 reported. Staging last recorded 46 migrations max0206; not independently queried in this research.
- ERPNext v15.126.0, commit a6f54f9c88dcc24fdf3c59319f24cd9aa91bd, 5,985 tree entries. Tag content fetch works; exact commit content endpoint returned 404 for selected files, so tag source used; verify tag remains pinned and save blob hashes. https://github.com/frappe/erpnext/tree/v15.126.0
- Frappe version-15 fd94443a1c5ffe6f1ef0fc02436d62d9ceaa9917, 4,363 entries. https://github.com/frappe/frappe/tree/fd94443a1c5ffe6f1ef0fc02436d62d9ceaa9917
- HRMS version-15 46b389047bb12fb9c86c1300c3d7bfd5f897f171, 1,848 entries. https://github.com/frappe/hrms/tree/46b389047bb12fb9c86c1300c3d7bfd5f897f171
- Inventory counts are entries, not features. ERPNext accounts179/stock72/manufacturing40/CRM29/assets25/buying19/selling16/QM16/projects15/support11/subcontract8 DocType definitions; HRMS HR111/payroll38. Child tables/settings included. Framework and third-party/new major version coverage incomplete.
- 99 open PRs returned on first GitHub API page; total not independently established. Review current paginated PRs and old closed/superseded sources before declaring missing.

## Done in earlier comparative research (evidence only)
- Tree inventory for all 4 pinned repositories; canonical migrations and existing draft inventory sampled.
- Direct code inspected: Frappe docfield JSON (blob 23594e7948336924b915e6bdf61b6cdd9bd41a98) and document.py (c133aca5ff393fd00d386807b40d4f002b12c83b, _save at 502); ERPNext stock reservation (025671889490923d42f57d4dcdeb82ceea8496cb, allowed qty 429), payment entry (b3913603f12b3cbd0cb3ec0bc9556ebf0602b4d0, latest allocation 397), GL (9498597c5ecd312aaa66d2844ca75bcb2ce76359), quality inspection (dfdbc91157e1fbdf9e7badd3915a8086d75baedc, min/max 343), work order (0fae260eaf126e0729273bcf3eb42dec6c5a6dcf), CORE10 0200/0400/0401/0500 SQL. Read selected code/definitions, not full runtime comparison.
- Reverse comparison candidate evidence: CORE10 PR42 micro-engine one executable handler/eight inert; PR77 simulation 19/20 model families, deferred; PR54 Owner intent docs only; PR95 paint isolated; PR73 recursive recall isolated; PR23 offline draft queue isolated; PR94 setup profile isolated, signed 400-site cap separately documented; PR142 signed shell merged, not universal SSO. No exclusive superiority certified.
- PaperOps PR151 combined 1,246 declarations (1,000/246), 79 Lane B local links, 11 gaps + 20 obligations open, 0 signed field acceptance/Owner acceptance per registry; PR155 exact tree port 8/8 reported CI, PR156 15/15 disposable signed scenarios, all release-held. Pending 0207–0210 before 0211/0212; preserve lane. Signed publisher/key custody, reversal and acceptance open.
- Sales PR153 0300–0305 re-integrated trunk, not applied by PR. Finance 0400–0401 and Manufacturing 0500–0504 on trunk, hosted adoption not proven. F3 competing PR117/120/122, 0305 collision to resolve. Preserve existing PR55 HR,59 assets,65 CRM (docs work order),73 QC,95 paint,97 procurement; port, do not wholesale merge old branches.
- Research package initial seed is deliberately NOT full feature parity, performance benchmark, CI execution or live ERPNext test.

## Next work (ordered research queue, implementation dependency order separate)
| Packet | State | Next concrete deliverable | Acceptance / dependency |
|---|---|---|---|
| A01 Original purpose and option inventory | READY | read Decision Book, 520-detail register, all 1,246 field matrix + legacy/current routes, prior D/R/A decisions, map IDs to registry | no lost IDs; report unavailable sources, duplicate IDs and unmapped counts; don't modify PaperOps |
| A02 Form modernization | SEED | compare each original form behavior with Frappe field/meta/lifecycle/permissions, mobile quick/advanced UX; split BENCH-001 | server validation and exact old field rule parity; coordinate PR155/156 |
| C01 Stock reservation and valuation | SEED | trace all stock and pending PR123 0207–0210 plus historical costing PR21, reservation upstream code/test; produce one reproducible oversell test and benchmark plan | stock lane claim; no new ledger; never apply ahead of lower reservation |
| D01 Sales/Money correctness | SEED | recheck PR153 + F3 competing PRs and payment allocation; reproduce stale/double allocation, overpay, period close and returns | Finance lane claim, migration ordering, exact double-entry |
| B01 Controls/UX | SEED | trace DEC08 each state-changing RPC; old→new menu/option map, role-aware context; 400-site list latency and mobile taps | signed context propagation, no dropped route |
| E01 Manufacturing/QC | SEED | compare BOM/job/capacity, yield/expiry and recall; reconcile PR73/95 | preserve recipes and independent QC, no bypass |
| F01 Remaining domains | SEED | enumerate HR/payroll/asset/CRM/project/commerce/support/automation/integration upstream DocTypes and reports → atomic capabilities | inspect old drafts + documentation before missing claim |
| G01 Release bug mining | READY | enumerate release v15.126.0 bug fixes and changed upstream tests, classify applicable to CORE10, generate prioritized regression work orders | exact release/PR/symbol evidence; not blind copy; expand to history and supported versions |
| G02 Benchmarks | READY | establish reproducible workload fixtures and baseline metrics before upgrades, split per domain | PG17 synthetic environment, fixed scenarios and measurement method |
| H01 Advantages | SEED | independent upstream counterpart search for each candidate; evidence-backed owner report, built vs draft vs plan | no universal exclusivity claim; include optional apps separately |
| Z01 Integration and release | BLOCKED | after packet build, reconcile board/migrations and prove safe integration/release | current trunk owner, separate release authority |
 
## Agent progress log
2026-11-24 ChatGPT: initialized research mandate, seed registry and checkpoint on isolated research branch. Board claim ERP-BENCH-001. Current scope docs only. Next A01 and G01 can be researched independently; existing builders continue their lanes. Record subsequent log as date | agent | packet | before SHA | commit/PR | actual evidence | delivery maturity | blockers | next step | Board row. Do not overwrite history.
