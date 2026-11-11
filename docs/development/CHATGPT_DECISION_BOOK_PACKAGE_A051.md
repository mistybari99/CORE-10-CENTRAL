# C10-A051 — proposed Master Decision Book rows (for ChatGPT / Owner coordination)
Claude did NOT write the Google Book (Drive tool replaces whole files). These are ACTION/EVIDENCE proposals only — **no new Owner policy is implied**. Re-verify exact SHA/CI before entering.

## NEXT ACTIONS (proposed row)
| ID | Title | Status | Evidence | Next |
|---|---|---|---|---|
| C10-A051 | Multi-business Workforce, Attendance, Leave & Payroll engine (Claude-owned) | **BUILT + isolated CI** (fill exact SHA / run URL from Draft PR) — NOT applied to SG, NOT GoTrue-verified | Issue #52; Draft PR; `docs/architecture/C10_A051_WORKFORCE_PAYROLL.md` | Real GoTrue staging E2E; A046 persona remap; A050 read adapter; Owner decision on delegated HR reviewer + statutory rule approval |

## AUDIT EVIDENCE (proposed row)
Disposable PostgreSQL SQL e2e (authority matrix, calculations, locks, amendments, audit chain), real parallel-session concurrency script, signed-HMAC PostgREST API e2e, Node client contract (49 RPCs == SQL signatures), Chromium 390px/1440px real-DOM UI (synthetic fixture). Boundary: **not Supabase GoTrue, not staging, not production.**

## Safe defaults Claude applied (configurable; none loosens an approved policy)
1. Payroll fails closed to tenant/business owners; managers never inherit salary access from stock/site grants. 2. Maker-checker ON (only tenant owner can switch off). 3. Statutory/ambiguous components default OFF (`pending_owner_approval`). 4. OT/holiday multipliers default 1.00 (no statutory rate asserted); OT paid only when approved. 5. No negative net; deductions capped with warnings. 6. Approved/Frozen ≠ Paid; no payout, bank file, ledger or stock effect. 7. Frozen periods change only via audited amendment. 8. Monthly calendar default; daily/hourly per policy. 9. Weekly off default Friday (configurable). 10. Full NID/bank never stored (last-4 only).

## Open questions for the Owner (do not block the build)
Delegated HR/reviewer permission contract (A021/A034) · approval of any statutory deductions/rates · retention period (default 36 months, 12–120) · Bangladesh-specific overtime multiplier policy · leave carry-forward rules.
