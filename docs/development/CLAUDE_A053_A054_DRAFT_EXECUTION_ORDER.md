# CLAUDE-3 — C10-A053+A054 Workforce Integration and Configurable HR/Payroll BUILD ORDER
**Status:** ASSIGNMENT ONLY, NOT IMPLEMENTED. Owner explicitly reassigns this paired future package to Claude; preserve existing source ownership.
**Canonical full instructions:** [CLAUDE_THREE_BUILD_ASSIGNMENTS_2026-11-11.md](CLAUDE_THREE_BUILD_ASSIGNMENTS_2026-11-11.md) — Package CLAUDE-3.
**Existing issues:** https://github.com/mistybari99/CORE-10-CENTRAL/issues/56 (A053) and https://github.com/mistybari99/CORE-10-CENTRAL/issues/57 (A054). Owner-approved D046/R125, D049/R128, D050/R129.
**Source:** A046 PR #44; A050 PR #51; A051 PR #55. Preview branch already assembled their compatible files; **not** production migrations.
**Branch:** \`claude/c10-a053-a054-workforce-integration-policy-v1\`; Draft PR base \`preview/c10-integrated-20261111-v1\`.

## Implement, not only document
**A053 integration:** Canonical synthetic alias reconciliation without rewriting A046 UUIDs or granting extra rights; Owner-only signed A050 → A051 business summary and read-only payroll liability adapter; fail-closed \`paid=false\`, \`money_movement=false\`, \`ledger_posted=false\`, exact business/period scope; truthful \`NOT CONNECTED\`; no non-owner salary disclosure and no PII/card leaks.
**A054 expansion:** audited scoped HR/Reviewer/Preparer/Approver delegation with expiry/revocation and maker-checker; effective-dated fixed/% salary component rates/caps and explicit formula; OT \`1.00×\` is 100% base not 1% and safe OFF; retention raw punch default 36-month edit with legal holds and dry-run; annual accrual, leave carry-forward cap/expiry/grace/year-crossing reconciliation; frozen payroll unchanged except validated audited amendment; statutory defaults OFF without verified jurisdiction rates.
**UX:** Actual responsive Owner HR settings, headcount/business card and leave/payroll policy UI with Bangla/English what/why/effect/linked-report guidance. Never mark APPROVED as PAID.
**Tests:** PG17 and signed-HMAC PostgREST where possible, A046 persona registry cross-tenant negative, owner vs manager/staff/revoked/anon, rates/rounding, amendment/revocation race, leave year-boundary, independent Chromium 390/1440 and no production network.
**Ownership:** new \`c10_a053_*\`/\`c10_a054_*\`, \`core10-workforce-integration-*\`, \`core10-workforce-policy-*\`, separate tests/CI; avoid rewriting existing A046/A050/A051 or A055, A052, \`preview/\`. No duplicate payroll/permissions tables.
**Delivery:** One Draft PR for both dependent IDs; exact SHA, CI URLs, visible working examples; no production SG, main merge, bank payment, real GoTrue staging claim.

**NOT DONE by this placeholder:** No new A053 or A054 source tested. Claude must build it.
