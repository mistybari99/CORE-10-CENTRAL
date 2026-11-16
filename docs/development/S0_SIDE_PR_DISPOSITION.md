# S0 — Draft PR disposition

Baseline for all further work: `preview/c10-integrated-20261111-v1` + PR #104 + PR #105
(they merge without conflict; #104 first because #105 lacks its A048/A049 permission changes).
Nothing below is closed or deleted by this record.

## Carry forward (real code not yet on the integrated line)

| PR | Content | Action | Step | Condition |
| --- | --- | --- | --- | --- |
| #78–#99 | GOV-002 typed approval chain | Reconcile | S1 | Rebase on Build02a resolver; drop `approval_demo_stock_*` |
| #85 | GOV-003 audit, readiness, risk | Reconcile | S1 | Drop own tenancy; consume canonical events |
| #94 | Setup profiles and preflight | Reconcile | S1 | Call Build01 context/receipt |
| #73 | QC, lot/expiry, quarantine, recall | Reconcile | S3 | On A048 ledger; drop own balances/movements |
| #97 | Procurement kernel (in-memory JS) | Rewrite as SQL | S3 | Kernel is the specification |
| #21 | Costing, COGS, valuation | Reconcile | S5 | Together with the journal |
| #96 | Journal boundary (in-memory JS) | Rewrite as SQL | S5 | JS is the contract |
| #95 | Paint/hardware tint, QC, dealer quotes | Reconcile | T4 | After Stock and Money ports are verified |
| #27 | Integration ports, payments, delivery | Reconcile | S8 | Move from `scripts/` to migrations |
| #23 | Offline outbox and replay | Reconcile | with each step | On A048 commands |
| #103 | Bangla-first three-mode language | Reconcile | with each step | Wire into the shell |
| #77 | Simulation engine | Park | S10 | After finance |

## Superseded or documentation-only

Already contained in the integrated line, or older candidates replaced by it:
#7, #42, #43, #44, #45, #49, #50, #51, #54, #55, #59, #60 (content present), and
#1–#6, #8, #12, #14–#17, #19, #20, #22, #24, #28, #29, #40, #65, #67, #69, #71, #75
(older candidates, security notes for the legacy app, or documents). Proposed handling: add a
`superseded` label and a pointer to the PR that carries the content. Not applied yet.
