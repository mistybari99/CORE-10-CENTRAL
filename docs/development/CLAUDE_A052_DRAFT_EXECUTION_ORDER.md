# CLAUDE-2 — C10-A052 Universal Owner Intent Runtime BUILD ORDER
**Status:** ASSIGNMENT ONLY, NOT IMPLEMENTED. Owner requests actual code + tests, Draft PR only.
**Canonical full three-package instructions:** [CLAUDE_THREE_BUILD_ASSIGNMENTS_2026-11-11.md](CLAUDE_THREE_BUILD_ASSIGNMENTS_2026-11-11.md) — Package CLAUDE-2.
**Existing specification:** https://github.com/mistybari99/CORE-10-CENTRAL/issues/53 ; D049/R128, A042–A045 canonical registry/Workshop.
**Branch:** \`claude/c10-a052-owner-intent-runtime-v1\` based on Preview V1 integration; Draft PR base \`preview/c10-integrated-20261111-v1\`; don't touch \`main\`.

## Immediately produce real source
1. Build *bounded* Owner intent intake with tenant/business/site scope, safe text→typed request, interpreted dependencies, recommended defaults and clear missing-data statuses. Two languages. No freeform code execution.
2. Reuse A042–A045 canonical handler and permission contracts via adapters; do not create shadow ledger, ACL, engine registry or new platform.
3. Implement versioned user request → impact & conflict preview → validated config recommendation → existing certified handler execution *only when the handler really exists* → audit; unsupported handler correctly displayed \`NEEDS_HANDLER_BUILD\`.
4. Explanations: what/why/when/default/exception/before→after/report-data lineage/formula+units/scope. Actual responsive UI and safe in-memory walkthrough.
5. Working sample: sweets low-stock/wastage advisory; paint unit discount margin calculation; construction site material approval advisory. Distinguish advisory from transactional posting.
6. SQL/JS/Chromium security tests with 2 tenants, multiple sites, revoked/anon, stale/replay, unit/currency errors, explanation completeness and 390/1440 UI. Test source-only on disposable PostgreSQL17, NO SG production.
7. Ship Draft PR with exact source SHA, CI URLs, screenshots and explicit unbuilt features. Keep committed files namespaced \`c10_a052_intent_*\` and \`core10-owner-intent-*\`; no shared \`preview/\`, A051/A055, Owner Studio replacements.

**NOT DONE by this placeholder:** No A052 runtime, no handler, no new CI result. Claude must execute the build; this file is a work order.
