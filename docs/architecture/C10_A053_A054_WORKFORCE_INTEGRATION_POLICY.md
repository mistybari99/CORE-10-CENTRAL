# C10-A053 + C10-A054 — Workforce Integration & Payroll/Leave Governance
Status: **BUILT and isolated-CI tested (disposable PostgreSQL, synthetic A046 personas)**. NOT applied to IMG-ERP-SG, **real GoTrue NOT tested**, not released. Draft PR #63, never merged to `main`.
Reuses A018 identity, A046 personas, A050 Portfolio and the **unchanged A051 engine**; adds only `c10_a053_*` / `c10_a054_*` SQL, `core10-workforce-{integration,delegation,policy,liability}.html`, `core10-workforce-policy-{app,client}.js|css` and tests.

## 1. Files
| Layer | Files |
|---|---|
| SQL (apply after A051, in order) | `c10_a054_workforce_policy_v1.sql`, `c10_a054_workforce_bridge_v1.sql`, `c10_a053_workforce_integration_v1.sql` (A053 also loads **without** A051/A054) |
| Client / UI | `core10-workforce-policy-client.js` (strict allow-list of 25 RPCs), 4 pages, `core10-workforce-policy-app.js`, `core10-workforce-policy.css` (English + Bangla, 390px / 1440px) |
| Tests | `tests/c10_a054_policy_e2e.sql`, `c10_a053_integration_e2e.sql`, `c10_a053_not_connected_e2e.sql`, `c10_a054_concurrency.sh`, `c10_a054_regression.sh` (A051 e2e with hooks), `c10_a053_a054_client.test.js`, `tests/api/core10-a053-a054-workforce-rest-e2e.js`, `tests/e2e/core10-a053-a054-workforce-browser.js`, stack builder `c10_a053_stack.sh` |
| CI | `.github/workflows/core10-a053-a054-workforce-policy-ci.yml` |

## 2. Approval is NOT payment (hard rule)
* A051 `approved` / `frozen` only fix the **amount owed**. There is no function that pays, creates a bank file, moves money or posts a ledger entry (a Node test fails the build if such an API name appears).
* `a054_payment_records` holds **records of payments made outside the system** (`external_payment_record` / `reversal`, append-only, external reference required, never more than the outstanding approved amount, per-employee/month). Every response carries `payment_executed:false, money_movement:false, ledger_posted:false`.
* Per employee-month state: `approved_unpaid` → `partially_paid_recorded` → `paid_recorded` (+ `overpaid_recorded` flagged). Draft/reviewed runs are reported only as a *pre-approval estimate*, never as liability.
* `a054_liability_report_v1` shows **approved-unpaid, partly-paid-outstanding, recorded-paid and total outstanding as separate figures**, by site and by employee number (no names), plus a PII-safe, audited CSV. UI buttons are labelled "Approve amount owed (does NOT pay anyone)" and "Record payment made outside…".

## 3. A053 — integration
* **Persona registry** `a053_persona_registry`: the 16 A046 personas (alias == A046 key, UUIDs unchanged; a Node test compares SQL to the manifest) + 9 `A051_FIXTURE_ONLY` aliases for A051-only identities (a1…, b1…, b2…, c1…, c2…). Append-only trigger: an alias can never be re-pointed (no silent UUID reassignment). Unknown alias ⇒ `a053_alias_unmapped` (fail-closed). `a053_a051_alias_map` maps the 18 A051 short names.
* **Staff identity** (owner-only): `a053_link_staff_identity_v1` links an employee to a *registered alias* (never a raw UUID). Refused: unknown alias, platform operator / investor / revoked / partner (not linkable), other tenant, other business scope, employee or login already linked. A link grants **self-service only**; unlink is immediate. `a053_staff_overview_v1` (manager+; aliases owner-only, names masked for managers), `a053_my_assignments_v1` (self).
* **Owner Portfolio → Workforce adapter** `a053_read_portfolio_workforce_v1(period)`: per business visible through A050; **owner-level only** per business. Every figure comes from A051's server guards (`read_workforce_business_summary_v1`, `read_payroll_liability_preview_v1`) and is verified (business id, month, headcount = sum of sites, `paid/ledger_posted/money_movement = false`) — otherwise `CONTRACT_VIOLATION` and no figures. Managers, investors, site staff get `OWNER_ONLY` with no data; other tenants never appear. Missing A051 ⇒ `NOT_CONNECTED`, no numbers invented.

## 4. A054 — governance
| Feature | Mechanism |
|---|---|
| Delegated roles | `a054_delegations`: `hr`, `payroll_preparer`, `payroll_reviewer`, `payroll_approver`, `payment_recorder`; business / site (HR only) / month-period scope; explicit **DENY beats ALLOW**; expiry; revoke. Evaluated **live on every call** (clock_timestamp) so revocation/expiry bite on the next call, including calls already queued behind the per-business lock (tested with real parallel sessions). Delegate must be an active manager/owner or linked employee; owners cannot self-delegate; delegates cannot delegate. |
| Maker-checker | preparer ≠ reviewer ≠ approver for delegates; an employee inside a run cannot decide it; owners keep A051 semantics; `void` stays owner-only. |
| Effective-dated policies | `a054_policy_versions` (immutable, versioned): `overtime`, `pay_rule`, `leave`. Payroll policies start on the 1st of a month; leave policies on 1 Jan. A version cannot start inside a period that is reviewed/approved/frozen (or a leave type with requests) → `a054_effective_date_locked`. |
| Overtime | multiplier semantics **1.00× = 100% of base hourly rate (not 1%)**; <1.00 → `a054_multiplier_below_base_rate`, >5.00 → `…_use_x_not_percent`. **OFF mode** needs the *tenant owner* + a legal-review reference. No statutory rate is shipped; with no policy row A051 behaviour is untouched. |
| Allowance / deduction rules | fixed or percent (percent units: 10 = 10%) of `basic_earned` / `gross_before_rule` / `contract_base`, min/cap, scope by contract type / site, proration, **per-line trace** (base, base value, raw, cap, policy version). Statutory rules need tenant owner + legal reference. Codes may not collide with A051 components. |
| Leave | accrual (`upfront` / `monthly`), annual **carry-forward with cap**, **expiry months + grace days** (carried days are consumed first and forfeited after expiry), **cross-year requests** (days counted per year), balance read incl. next-year carry preview. Quota is enforced inside A051 `request_leave` / `decide_leave` (hooked). |
| Retention | raw punches only (36-month default setting kept); **legal holds** (owner places, tenant owner releases) protect punches from A051 purge; dry-run report; payslips, runs, leave and audit are never purged. |
| Audit / idempotency | every write uses A051's request-key receipts and hash-chained `wf_audit` (integrity report stays green). |

### Honest note on the A051 hooks
`c10_a054_workforce_bridge_v1.sql` rewrites **one exact statement** in each of 12 installed A051 functions via `pg_get_functiondef()` (22 hooks; install fails closed if a statement is missing/ambiguous; logged in `a054_patch_log`). A051 source files are untouched. With no A054 data every hook is a no-op: `tests/c10_a054_regression.sh` runs the **unchanged A051 e2e + concurrency** on a database with A054 installed. Hooked: payroll OT + rule engine (`wfi_calc_line`), preview/draft/recalculate/transition, payroll run reads, leave decide/request, correction decide, employee edit, punch purge.

## 5. Privacy / authorization summary
Staff see only their own payslip/leave/assignments; no salary, liability, policy, delegation or retention data. Investors, revoked, platform operator, unassigned/partner users, other-tenant owners and anon are denied (`wf_denied` / permission denied). All new tables are RLS-on with zero grants; helpers `a05[34]i_*` are not executable by `authenticated`.

## 6. Not verified / limits
* **GoTrue NOT tested**; no staging; no production; CI uses signed-claim simulation + HMAC PostgREST + a synthetic browser fixture.
* HR delegation covers leave decisions, correction decisions and employee edits; roster, shifts and attendance import remain A051 manager rules. Site-scoped delegations are HR-only. Policy periods are month/year aligned (no mid-month proration of a policy change).
* Leave simulation is per employee/type/year (bounded recursion ≤10 years); very large tenants need review. Single-day granularity (no half-day leave) is inherited from A051.
* The REST e2e (`tests/api/core10-a053-a054-workforce-rest-e2e.js`) needs Docker/PostgREST and is verified only in GitHub Actions.
* No bank/MFS payout, tax, provident fund, bonus or statutory rate is implemented.
