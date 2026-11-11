# C10-A051 — Multi-business Workforce, Attendance, Leave & Payroll Engine
Status: **BUILT and isolated-CI tested (disposable `c10_demo`)**. NOT applied to IMG-ERP-SG, NOT real-GoTrue tested, NOT released.
Owner of this package: Claude (new `c10_a051_*` / `core10-workforce-*` files only). Draft PR, never merged to `main`.

## 1. What exists (real code)
| Layer | Files |
|---|---|
| SQL (apply in order, after A018) | `internal/enterprise-sql/c10_a051_workforce_core_v1.sql`, `..._attendance_leave_v1.sql`, `..._payroll_v1.sql`, `..._reads_v1.sql` |
| Signed API client | `core10-workforce-client.js` (strict allow-list of 49 RPCs, argument typing, `auth.getUser()` each call, `schema('c10_demo').rpc`) |
| UI (390px mobile + 1440px desktop) | `core10-workforce-{directory,attendance,leave,payroll,reports,self}.html`, `core10-workforce-app.js`, `core10-workforce.css` |
| Tests | `tests/c10_a051_workforce_e2e.sql` (PG), `..._concurrency.sh` (parallel sessions), `..._client.test.js`, `tests/api/core10-a051-workforce-rest-e2e.js` (signed HMAC → PostgREST), `tests/e2e/core10-a051-workforce-browser.js` (Chromium) |
| CI | `.github/workflows/core10-a051-workforce-ci.yml` |

Flow for every feature: **UI → signed `auth.getUser()` client → `c10_demo.wf_*_v1` SECURITY DEFINER RPC → business rules + DB-derived authority → deterministic calculation → append-only hash-chained audit → reports/exports.**

## 2. Reuse, not duplication
* Identity/tenancy: only existing `c10_demo.tenants / businesses / sites / tenant_members / business_members` and `can_tenant()`. **No new login, no new site_grants, no new role table.** An optional `wf_employees.user_id` link (owner-created) gives *self-service only*.
* No finance ledger, stock movement, bank file or payout. "Approved/Frozen" ≠ "Paid" (`paid:false`, `money_movement:false`, `ledger_posted:false` in every contract response; payslip says `payment_status: not_tracked_in_this_module`).
* Legacy `employees.js / attendance.js / shifts.js / salary.js / payroll.js / staffreports.js / v2/**` are untouched (git diff shows only new A051 files). No real staff data is read or migrated.

## 3. Authority model (server-derived on every call; claims/JWT metadata are ignored)
| Persona (A018 fixture id) | Workforce authority |
|---|---|
| Tenant owner (1111…) | everything in own tenant incl. payroll; may loosen maker-checker; may activate statutory components; retention purge |
| Business owner (2222…) | everything in own business incl. payroll (cannot loosen maker-checker, cannot activate statutory components, no purge) |
| Manager (3333…) | directory (no PII/salary), shift roster, punch import, OT decisions, leave review (setting `leave_review_level`), reports/exports (masked names). **No payroll, no salary, no employee edit unless owner enables `manager_can_edit_employees`** |
| Supervisor (employee flagged `is_supervisor`, a1…) | own-site staff attendance, punch import for own site (not own punches), correction **requests** (never self, never approve) |
| Employee (linked user a2…/a3…/a6…) | own attendance, own leave (request/cancel), own limited payslip (frozen only), own advance request |
| Stock-only site staff (4444… before link), investor (5555…), revoked manager (6666…), other-tenant owner/staff (7777…/8888…), platform operator (9999…), anon | **denied** (`wf_denied` / permission denied). `stock.read/post` never implies workforce access |

Maker-checker (default ON): payroll preparer cannot review or approve; correction/leave/advance approver ≠ requester; nobody approves their own attendance/leave. Only the tenant owner can turn maker-checker off.

## 4. Data model (all tables RLS-on, zero direct grants)
`wf_business_settings, wf_departments, wf_employees, wf_employment_history*, wf_assignments*, wf_shifts, wf_shift_assignments*, wf_holidays, wf_punches†, wf_attendance_days, wf_attendance_corrections, wf_overtime_approvals*, wf_leave_types, wf_leave_requests, wf_pay_policies, wf_salary_structures*, wf_pay_components, wf_employee_components*, wf_advances, wf_advance_recoveries*, wf_payroll_runs, wf_payroll_lines, wf_payslips*, wf_receipts*, wf_audit*`
`*` append-only (trigger rejects UPDATE/DELETE even for table owner). `†` immutable except the tenant-owner retention purge. Runs/lines freeze after review (`wf_frozen_payroll_immutable`). Effective-dated facts use "latest `effective_from ≤ date`" so history is never rewritten. Audit is a per-business SHA-256 hash chain verified by `wf_integrity_report_v1`.

## 5. Calculation rules (all deterministic `numeric`, Asia/Dhaka)
* **Day (derived from immutable punches + approved corrections/leave/OT):** work date = shift start date (overnight 22:00→06:00 supported; punch window start−3h … end+3h); duplicate punches within `duplicate_window_seconds` or same device ref are ignored; worked = out−in−break; late if in > start+grace; OT only after shift end ≥ `min_overtime_minutes`, capped by `max_overtime_minutes_per_day`; work on weekly-off/holiday = off-day OT; worked < `half_day_ratio`×scheduled ⇒ `half_day`; missing in/out ⇒ `incomplete` (blocks payroll); no punch on a scheduled day ⇒ `absent`.
* **Overtime** is paid only for minutes approved by a manager/owner (default; `overtime_requires_approval`).
* **Monthly:** `basic = base × employed_days / calendar_days`; day rate = `base / (monthly_divisor ∨ calendar_days)`; absence deduction = (absent + unpaid leave + ½ half-days + ⌊late_days / late_to_absent_days⌋) × day rate, **capped at basic**; hourly rate = day rate / standard hours. **Daily:** `base × (present + ½ half + paid leave*)`. **Hourly:** `base × regular hours`. (`*` configurable). OT = hourly rate × approved hours × multiplier (separate weekday / off-day multipliers, **default 1.00 – no statutory rate is asserted**).
* **Components:** allowances/deductions fixed or % of basic, per-employee assignment/override, optional proration. **Statutory components are created `pending_owner_approval` (OFF) and only the tenant owner can activate them.**
* **Advances:** approval creates a *deduction schedule only*; recovery = min(installment, remaining, headroom). Recovery rows are written only at FREEZE (amendment-safe).
* **Net = gross − deductions, never negative** (`CHECK(net>=0 AND net=gross−total_deductions)`; deductions/recoveries are capped with warnings).
* Rounding: `half_up` or `down` to 2 dp per component; money limits ≤ 99,999,999,999.99.
* Worked fixture (October 2026, EMP-001): base 31,000; 21 present, 1 half, 1 absent, 1 unpaid + 2 paid leave, 3 late days (→1 day), OT 60 min weekday + 420 min weekly-off at ×2.00 = 2,000; allowances 1,000 + 10 % = 4,100; gross 37,100; deductions 3,500 + 200 + 1,000 advance; **net 32,400** (asserted in the e2e).

## 6. Payroll lifecycle
`preview (not stored) → DRAFT → REVIEWED → APPROVED → FROZEN` (+ `return_to_draft`, `void`). Blocking exceptions (no salary structure, incomplete attendance, pending OT/leave/correction, period not ended) must be resolved and the draft recalculated; review/approve/freeze re-compute an input hash and refuse stale drafts (`wf_payroll_inputs_changed`). Reviewed/approved/frozen periods lock attendance corrections, punch import, holidays, employment/assignment/shift changes and leave. A frozen period can only change through an **audited amendment draft** (reason ≥ 10 chars) that supersedes (never rewrites) the original; employees keep both payslips and v1 is flagged `superseded`. Freeze issues immutable payslips (employee sees only their own limited payslip).

## 7. Reports / exports / controls
Attendance summary by site, headcount (site/status/contract), payroll gross/net by site, frozen payslip register, CSV exports (`employees`, `attendance`, `payslip_register`) with PII-safe role projection (no phone/NID ever; managers get masked names; formula-injection neutralised; every export audited), integrity report (audit chain, frozen totals vs lines, payslip per line, no negative net, one frozen run per period, advance not over-recovered), audit list, retention preview/purge for expired punches (tenant owner, never inside locked/frozen periods).

## 8. Integration contract (read-only; for A050 Portfolio / future finance)
* `c10_demo.read_workforce_business_summary_v1(p_business bigint, p_period date)` → active headcount, by-site headcount, frozen payroll totals; owner-level only.
* `c10_demo.read_payroll_liability_preview_v1(p_business bigint, p_period date)` → `state: approved_not_paid | no_approved_run`, gross/deductions/net preview; always `paid:false, money_movement:false, ledger_posted:false`.
* Future finance posting must consume the **frozen run id** and own its own ledger/payout; A051 will not write any money movement. Navigation: expose routes `core10-workforce-*.html?biz=<id>`; `owner.html`/`index.html` are intentionally not edited.
* Persona keys: this branch uses the A018 fixture UUIDs plus six inert employee ids (a1…, a2…, a3…, a5…, a6…, c2…). Re-map to A046 persona aliases when PR #44 lands (data-only change in `tests/c10_a051_workforce_seed.sql`).

## 9. Known limitations / NOT VERIFIED
* **Real Supabase GoTrue-issued session verification: NOT RUN** (release gate). CI uses signed-claim simulation + HMAC PostgREST.
* **Live SG migration: NOT APPLIED** (and not authorised). Real staging: not available → NOT VERIFIED.
* Single-day granularity only: no half-day leave, no multi-year leave carry-forward/cross-year requests, no per-employee weekly-off override beyond shift.
* Employee-change effective dates for employment status are limited to ≤ today (documented mirror semantics).
* Live attendance calculation is capped (35-day list, 92-day report, 1000 employees/run); very large tenants need the stored timesheet path + indexing review.
* Taxes, provident fund, bonuses, bank/MFS payout files and statutory rates are **not implemented by design** (components exist but statutory ones stay OFF).
* Browser UI is tested with a synthetic fixture; DB behaviour is tested separately through SQL and HTTP.
* Delegated HR/reviewer role: no existing delegated-permission contract was found on this base → payroll **fails closed to owners**.
