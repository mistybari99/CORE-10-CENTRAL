# DR01 — Prioritized work orders (recommendations only; no product change made)

Snapshot 2026-11-24, trunk `9510e198`, staging ledger 47 rows / max 0300 (read-only). These work orders do not authorize anything. Each one needs a Board claim by the owning lane, current-head re-verification and the normal release gates (START_HERE). `BUILD_READY` is used only where every preparation item is present.

Migration numbers are **not** reserved here. Ordering facts:
- Staging max is 0300, so Sales 0301–0305 must be hosted before any 04xx or 05xx.
- NP03A 0207–0210 are pending (PR #123, PaperOps waits on them before 0211/0212).

| WO | Pri | Title | Original IDs | Lane (suggested) | Status |
|---|---|---|---|---|---|
| WO-01 | P0 | Refresh stale coordination records | — (process; M01) | Trunk owner + research maintainer | **BUILD_READY** (docs only) |
| WO-02 | P0 | One precision/rounding policy for quantity and money | INV-001/SALES-001/MFG-001/FIN-001 Details; R044, R050 | NP02 Control + NP03A/NP03B/NP05A/NP06 | NOT READY: Owner policy decision |
| WO-03 | P0 | Stock reservation under balance-row lock | INV-001-reservation-and-release-lifecycle, SALES-001-available-to-promise-and-reservation; CHG-034, CHG-040; BENCH-003 | NP03A | NOT READY: migration number after 0207–0210 |
| WO-04 | P0 | Choose one AR/AP stack (#117 or #120) and collapse #128–#147 | FIN-001-ar-…, -ap-…; CHG-051; BENCH-008 | NP06 | BLOCKED: Sales 0301–0305 hosting first |
| WO-05 | P0 | Do-not-close rule for recovery-source PRs | 75 DRAFT-only Details (see DRAFT_RECOVERY_REGISTER) | Owner / trunk owner | Owner decision |
| WO-06 | P1 | Dedup Auth/Audit, then port engine files to numbered migrations | CHG-004, CHG-005, CHG-062, CHG-070, CHG-043, CHG-024/025; 155 Details | NP01 (dedup) → NP07, NP05B, NP03B-CRM, NP02 Control | NOT READY: per-lane claims |
| WO-07 | P1 | QC parameter templates via certified threshold handler | INV-002-quality-sample-and-inspection-record; PaperOps F-02, R-01 temp; obligation GRADE_AND_SHELF_LIFE; BENCH-012 | NP03A + NP02 Control | NOT READY |
| WO-08 | P1 | Selective port of PR #73 genealogy and recall | INV-002-recall-*, -fefo-*, -lot-identity-*; CHG-035; BENCH-005 | NP03A | NOT READY |
| WO-09 | P1 | Valuation policy, then PR #21 costing port | INV-001-valuation-…, FIN-001-weighted-average-…, -cogs-…, MFG-001-production-costing-…; CHG-052/061; BENCH-004 | NP06 + NP03A | NOT READY: Owner policy (backdating) |
| WO-10 | P1 | Period close per source domain plus audited reopen | FIN-001-period-close-locks-and-reopen; CHG-053 | NP06 | NOT READY |
| WO-11 | P1 | Preservation-test convention and certified-detail counter | R073, R074; all 520 Details | Trunk infrastructure | NOT READY: CI change needs trunk owner |
| WO-12 | P2 | Decision Book trace corrections | R130; 7 audit/trunk mismatches; CHG-100 (NP10 rows) | Decision Book maintainer (ChatGPT coordinator) | Proposal |
| WO-13 | P2 | Optimistic concurrency inventory | MOD-09; R044 | Trunk infrastructure | INVESTIGATE |

## WO-01 Refresh stale coordination records — BUILD_READY
- **Evidence:**
  - `docs/coordination/MIGRATION_RESERVATIONS.json` and `AGENT_HANDOVER_CURRENT.md` §3 say "46 ledger rows, max 0206". A read-only SELECT on `rhrqhbyzrhaafynfhdaf core10.schema_migrations` (2026-11-24) returned **47 rows, max 0300, last applied 06:11:25 UTC**.
  - STATE.md pins ERPNext commit `a6f54f9c88dcc24fdf3c59319f24cd9aa91bd` (37 characters). The correct SHA is `a6f54f9c88dcc24fdf3c59319f24cd9cd9aa91bd`.
  - PR count: 100 open of 142 PRs (the search API lists 142 PRs + 15 issues). STATE says "99 on first page"; PR_STATUS says 93.
- **Change:** the trunk owner updates the two coordination files; the research maintainer updates STATE.md.
- **Tests:** none (docs only). **Risk:** none.

## WO-02 Precision policy (MOD-01)
- **Existing:** stock `numeric(15,3)` (0200 L16/L34/L81; 0201 L43; 0203 L47). Sales `round(q,6)` (0301 L53). Mfg `round(x,6)` (0500 L9/L25). Money `numeric(18,2)` PO (0203 L48), `numeric(18,4)` journal (0400 L115), sales `scale` param (0301 L58).
- **Upstream:** System Settings float/currency precision; UOM whole-number flag; line `conversion_factor`; Company `round_off_account` used by `general_ledger.py` `process_gl_map` (L176+).
- **Architecture:** a Control-owned typed parameter per UOM and currency. Every source line stores `stock_qty` at stock precision. One rounding function shared by all lanes. A round-off rule in Money.
- **Locations:** a new Control seed (NP02 range 0107+ needs Board allocation) and `0301`/`0501` successors as forward migrations. Never edit applied files.
- **Preservation:** existing 3-dp stock rows are unchanged. Sales/Mfg quantities that are already 3-dp are unchanged.
- **Tests:** positive — conservation property per lane. Negative — 4-dp stock rejected; residue posts to round-off.
- **Risk / release blocker:** must land before Sales→Stock and Mfg→Stock posting are hosted.

## WO-03 Stock reservation (MOD-02)
- **Upstream:** `stock_reservation_entry.py` blob `025671889490`, `validate_with_allowed_qty` L429–L470 (read-based allowed qty).
- **CORE10:** `post_stock_event` locks the balance `FOR UPDATE` (0200 L105).
- **Architecture:** reservation rows plus a `reserved` sum under the same lock, enforced by `CHECK (on_hand - reserved >= 0)`. Reservation source is a sales order line. Release on issue, cancel or expiry. Control feature key `inventory.reserve` per business/site.
- **Tests:** 2/8/32-session oversell race (BM-03 must give 0); expiry release; cross-tenant/business/site negatives; revocation while waiting (pattern from 0201/0203/0206).
- **Dependencies:** Sales 0301–0305 hosted; NP03A 0207–0210 order.

## WO-04 AR/AP consolidation
- **Evidence:** #117 (0402–0403) and #120 (0402–0405) both create `finance_arap_links_v1` and `finance_arap_allocations_v1` with `FOR UPDATE` (#117 0402 L116/L202; #120 0402 L113/L189). #120 is a superset. #122 must renumber its 0305 because trunk 0305 is the security fix from #153.
- **Upstream reference:** Payment Ledger Entry semantics (`against_voucher_*`, `delinked`); `accounts/utils.py` L1959/L1982.
- **Recommendation:** the Finance lane picks one PR via the Board, folds the 13 stacked test PRs in, and adds a delink-on-reversal test and a stale-allocation version check.

## WO-05 Do-not-close rule for recovery sources
These open PRs are the **only** source of code for 75 Details: #21, #23, #27, #73, #77, #85 (part), #95, #96/#97 (spec), #103. PR_STATUS_2026-11-23 lists several of them under "Close". Recommendation: close a PR only after its port is integrated and green, with a pointer. Retirement of a PR never removes the requirement (START_HERE).

## WO-06 Engine-file porting (MOD-07, MOD-08)
- **Order:**
  1. CHG-004: convert A055 `am_grants` to the Build01 Auth port.
  2. CHG-005: make module audits consume `canonical_audit_events_v1`.
  3. Port HR A051/A053/A054 (86 Details) and Assets A055 (16 Details).
  4. Port CRM A056 (≈15 SALES/CHANNEL Details).
  5. Port Control extensions A045/A052 (RULE-001).
- **Evidence:** 53/53 CI SUCCESS at the trunk head, including A051/A053-A054/A055/A056/A045/A052 suites. Engine files exist only in `internal/enterprise-sql/`.
- **Preservation:** run the same suites against the migrated schema, keep RPC names with `_v1`, and keep the engine files until the migrated equivalents pass.

## WO-07 QC parameters (MOD-04)
- **Upstream:** `quality_inspection.py` L316–L352 (formula-based criteria; numeric min/max).
- **Architecture:** template per item group in the NP03A range; evaluation in SQL; formulas only through A045 `threshold_rule_v1` (no `eval`).
- **Tests:** boundary values (min, max, ±epsilon), non-numeric match, formula injection rejected, lot status becomes held on failure.

## WO-08 PR #73 genealogy/recall
- **Evidence:** PR #73 `quality_genealogy_v1` (child-lot index) plus its own `quality_balances_v1`/`quality_movements_v1`.
- **Architecture:** genealogy edges reference `inventory_lots_v1` and `stock_movements`. Recursive CTE scope with a depth limit. Recall actions go through GOV-002. **No second balance table.**
- **Tests:** multi-level forward and backward trace; cycle guard; cross-business denial; recall cannot move stock outside the canonical ledger.

## WO-09 / WO-10
Both need Owner policy first:
- Backdated stock postings: allow with revaluation, or block by Control default.
- Period reopen authority.

Then port PR #21 (WAC/COGS) and add closing entries modelled on Period Closing Voucher / Accounting Period (`general_ledger.py` L146, L433).

## WO-11 Preservation-test convention
Every test that proves a Detail includes the literal `PRES-<Detail ID>` (see `acceptance_tests.preservation` in the crosswalk). A small CI job counts Details with at least one passing PRES test and publishes `certified_details/520`. Today the count is 0 by the Decision Book's own column. This makes R073/R074 executable. Shared CI changes need the trunk owner (M06).

## WO-12 Decision Book trace corrections (for the coordinator; DR01 did not edit the Decision Book)
- Add R130 to REQUIREMENT TRACE.
- Re-verify the 7 rows where the 2026-11-16 audit says code exists but DR01 found none on trunk. These are flagged `AUDIT_CODE_NOT_FOUND_ON_TRUNK_NEEDS_VERIFICATION` in the crosswalk: SETUP locale, MDM merge crosswalk, DR snapshot/integrity, INTEGRATION retry/DLQ, PROC supplier returns, INV valuation.
- Write the NP10 Detail rows promised by CHG-100. None exist among the 520.
