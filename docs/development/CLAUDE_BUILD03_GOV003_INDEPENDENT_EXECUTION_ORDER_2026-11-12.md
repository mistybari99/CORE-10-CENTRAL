# CLAUDE CODE — BUILD 03 / GOV-003 INDEPENDENT EXECUTION ORDER

Date: 2026-11-12. Status: OWNER-REQUESTED ASSIGNMENT — NO EXECUTABLE GOV-003 BUILD CLAIMED YET.
Repo: mistybari99/CORE-10-CENTRAL
Issue: https://github.com/mistybari99/CORE-10-CENTRAL/issues/84
Exclusive assigned branch: claude/build-03-gov003-audit-readiness-20261112
Pinned branch starting commit: c39052910758ca285a7a4d56e9c4f4873cb7d99c (main on assignment date)
Module: C10-CAP-GOV-003 — audit, fraud and readiness truth (Master Build 03).
Source of truth: https://docs.google.com/spreadsheets/d/1IYzGBtUVNjah31cPVSFHkzgO7P093jTfZS0CopWrDxs/edit
Exact Master Detail features: MODULE BUILD DETAIL rows 26–37, 12 P0 atomic checks.
Master Delivery: MODULE DELIVERY row 4. All 12 currently PLANNED_DETAIL_NOT_CERTIFIED.

## 1. MISSION AND MODEL

You are Claude Code, the independent implementation owner for the entire Build 03 audit and readiness module. Recommended model: Claude Opus 5.5, model ID claude-opus-5-5, High effort. If unavailable on the owner's account, Claude Sonnet 5.5 High. You are expected to CODE an independently runnable, production-shaped DRAFT core, not merely plan it or draft interface mockups.

Complete as many of all 12 real features as can be independently implemented in isolated PostgreSQL17 + Node + a small local review preview, with actual positive and adversarial tests, explicit proof and no fake production claims. The purpose is to save Codex Build 01/ChatGPT Build 02 credits by leaving this independent module substantially ready for later shared integration.

IMPORTANT: This assignment is Master Build 03 GOV-003. It is NOT the earlier unrelated Claude A053/A054 assignment referred to as "Claude Build #3" in PR #63. Do not alter or duplicate that work.

## 2. HARD OWNER POLICY AND NON-CONFLICT FENCE

- DO NOT modify main; DO NOT merge; DO NOT deploy to public preview/Cloudflare/GitHub Pages; DO NOT touch production IMG-ERP-SG (Supabase), live customers, keys, identities, or real stock/cash/payroll/finance. No live migrations, service-role secrets or OAuth/provider changes.
- Strictly preserve original Islamiya Misty Ghar ERP under D051/R130, including its original UI/theme/branding, index.html, owner.html, business.html, core.js, app.css, manifest.json, config.js, sw.js, business data, ledger and IDs. Protected archive branch archive/islamia-erp-preserve-20261112 must not be edited.
- Do not change or duplicate Codex Build 01 A018/A020/A021/A034, ChatGPT Build 02 GOV-002 PRs #69/#78/#79/#80/#81/#82/#83, or parallel Claude A052/A053/A054/A055/A057 modules. All integration points must be interfaces, mock adapters and neutral contracts. Do not change the Preview One app.
- No new parallel production audit ledger, auth engine, stock book, approvals service or journal. A disposable c10_gov003_demo schema is a CONTRACT/TEST BED only; its final adoption must be reconciled to the one canonical CORE10 audit service and owner approval.
- Simulated request.jwt.claim.sub identities are allowed only in isolated tests; NOT real signed GoTrue evidence. No forged frontend role/tenant/actor assertions as authority. Real A034 permission parity is pending.
- Fraud flags are REVIEW-ONLY advisory signals, not accusations. No autonomous freeze, firing, debit, transfer, payment, approval, privilege elevation, blocking existing operations, or law-enforcement action.
- Decision Book D041/D042/D043/D044/D047/D049/D051 and R128/R130 remain binding. Owner reserved final live release, destructive migration and integration approvals.
- Keep this Draft branch isolated. The only new files should live under internal/gov003/, tests/gov003/, docs/development/GOV003_* and one dedicated CI workflow; plus this order if updates needed. No original app path edits.

## 3. CREATE REAL INDEPENDENT PACKAGE

Suggested layout (adapt to existing repo conventions but preserve the isolation fence):
- internal/gov003/sql/ — ordered PG17 schema, tenant/business/site fixtures, hardened functions, RLS, append-only audit and evidence tables, read-only scoped views.
- internal/gov003/server/ — actual Node source for typed event envelope, canonical SHA256, PII allowlist and error scrubber, risk matching, readiness evaluator, immutable export receipt generation, evidence graph validator, and adapter interfaces.
- internal/gov003/client/ — scoped, read-only UI adapter with no service role, no privileged direct table mutation, no production URL.
- internal/gov003/demo/ — LOCAL-ONLY minimal professional Bangla/English demo using synthetic data; owner audit explorer, signal triage, incident/evidence history, readiness truth matrix and export preview. At 390 and 1440 pixels with keyboard states, help text and DEMO / NOT LIVE labels. Where a button says it works, use actual local test API/DB; never portray static sample as live.
- tests/gov003/ — deterministic seed; SQL/Node/browser negative and positive suites; true two-process PostgreSQL races.
- .github/workflows/c10-gov003-standalone-pg17.yml — dedicated fresh PG17 + Node isolated workflow triggered by changed GOV003 paths; no deploy and no secret access.
- docs/development/GOV003_IMPLEMENTATION_MATRIX.md — 12 exact rows status CODED/ISOLATED_TESTED/INTEGRATION_PENDING/NOT_BUILT, exact tested SHA, CI run, limitation and future Owner gate.

No external paid provider or real SG credential needed. Avoid new dependencies when Node built-ins can do the job. If packages required, pin versions and confine manifests/locks to GOV003.

## 4. DATA AND SECURITY CONTRACT TO IMPLEMENT

Use a versioned structured event envelope: event ID, tenant_id, business_id, optional legal_entity_id/site_id (same-scope FK), source_domain and source_id/version, command/action, event time and ingest time, server-derived actor in future signed integration, correlation_id, idempotency_key, payload_sha256 and prior event digest, redacted allowed fields, reason category, schema version and immutable receipt. Use decimal/time parsing precisely. No authorization based on free-text business names.

Build stable canonical hashing and replay handling. Same key + exact same normalized payload => same receipt; same key + changed payload => conflict. Concurrent independent sessions must produce one stored result. Make app roles unable to UPDATE/DELETE or directly INSERT audit events; backend-scoped functions may append only. Use SECURITY DEFINER only when essential, with tight EXECUTE grants, explicit schema/search_path, actor/scope checks. Use RLS and security_invoker views. A hash chain inside a mutable PG database does NOT give legal WORM protection against a privileged DBA: state this limitation accurately.

PII/secret redaction should allow only approved fields; never output password/token/JWT/service_role/OAuth secret, payroll/health/card data, email/phone, raw customer identity or full stack traces into event/external CSV. A synthetic debugging example MUST prove secret removal and scoped errors. Export report reads must be business-scoped and no cross-tenant badge counts.

Use at least 2 tenants, 3 businesses and 4 operating sites with Business Owner, Tenant Owner, Staff, Investor, Revoked and unrelated tenant test identities. Tests may emulate auth with inert fixture UUIDs. Real signed GoTrue and A034 entitlement parity are EXPLICIT FUTURE BLOCKERS. Local demo must fail closed if signed-session adapter is not available for non-demo operation.

## 5. ALL 12 MASTER DETAIL FEATURES (IMPLEMENT, TEST, DOCUMENT)

All features below are sourced from the existing Master Module Register and must retain the same IDs and acceptance semantics.

### 01 canonical-audit-event
Workflow: command/request -> actor/scope/source/version -> append event.
Build: validated versioned event schema and source-linked immutable receipt. Actor is derived from a trusted server/fixture boundary, not caller role claims.
Acceptance: who, what, when, why, business/site scope, source version and correlation ID.
Negatives: forged client actor and missing/foreign business/site scope.

### 02 append-only-history
Workflow: attempt UPDATE/DELETE of audit/versioned history.
Build: append-only audit table and immutable journal, functional actor/scoped append RPC, grants, version/digest chain where sound.
Acceptance: ordinary app principals cannot rewrite any record; privileged maintenance is separately governed.
Negatives: direct UPDATE, DELETE, INSERT, attempted owner-role bypass; explicit DBA/WORM limitation.

### 03 idempotency-evidence
Workflow: retry same request -> compare receipts/audit.
Build: stable request key + exact canonical payload digest and unique receipt; atomic event append and conflict return.
Acceptance: exact replay returns old receipt, never repeats effect.
Negatives: same key/changed payload, concurrent two-connection duplicate, receipt mismatch.

### 04 scope-safe-observability
Workflow: operational error -> safe support projection.
Build: allowlisted structured errors and tenant-safe view; scrub secrets and personal fields.
Acceptance: business context only if authorized; support-level diagnostics not automatically granted across tenants.
Negatives: foreign tenant row or count leak, token/PII in error or stack, support operator overreach.

### 05 readiness-states
Workflow: register feature evidence -> show proposed/coded/tested/integrated/released.
Build: typed state engine distinguishing proposed, code built, isolated test PASS, authentic signed-stage, integrated verified, deployed and released. Derived from proof, NOT manually set green booleans.
Acceptance: every state links exact code/commit/environment/run, reflects missing proof.
Negatives: synthetic PG17/CI green never marks signed GoTrue, production or release green.

### 06 exact-commit-ci-receipts
Workflow: record test -> bind head SHA -> update delivery truth.
Build: receipt schema, SHA/CI run validation contracts, stale-head validator and immutable evidence reference.
Acceptance: verified commit hash / environment and test evidence.
Negatives: old SHA pass reused for new SHA; caller-supplied fake GitHub URL treated as certification. Offline fixtures are only simulations until remote GitHub verification.

### 07 deployment-provenance
Workflow: build allowed artifact -> deploy -> verify runtime source/health.
Build: typed deployment record, artifact/source hash, runtime probe contract and acknowledgement with real vs simulated distinction.
Acceptance: deployed proof separate from built/source-tested proof.
Negatives: preview branch or queued CI equated to deployed/healthy without runtime smoke.

### 08 risk-advisory-triage
Workflow: configured anomaly -> explainable advisory -> human review.
Build: at least duplicate-idempotency anomaly, unexpected volume/stale-source, unauthorized command or grant policy diff from fake deterministic events. Server-side immutable signal receipt, reason/evidence/confidence and human acknowledgement/dismissal with audit.
Acceptance: advisory only, rational source/date/context and independent reviewer.
Negatives: self-forged actor, foreign scope, repeated review race, autonomous accusation or freeze.

### 09 grant-and-policy-review
Workflow: enumerate effective grants -> compare a reviewed baseline.
Build: read-only PG catalog inventory for function/schema privileges, RLS policies and grants, normalized versioned diff.
Acceptance: detect unexpected GRANT or permissive OR policy and label severity as advisory.
Negatives: unauthorized snapshot, automatic GRANT/REVOKE/ALTER, fabricated policy comparison.

### 10 export-provenance
Workflow: authorized filtered report -> hash exact bytes -> log scope/source/count/params.
Build: scoped CSV export and durable audit receipt keyed to byte hash, normalized report and source version. Guard spreadsheet formula = + - @, CR/LF, Unicode and oversized rows.
Acceptance: row count, business filter, actor, source version, timestamp, SHA256 and receipt.
Negatives: foreign/PII export, missing receipt, content-hash mismatch, formula injection.

### 11 incident-evidence-preservation
Workflow: incident opened -> evidence manifest retained -> scoped investigation.
Build: scoped incident case, immutable evidence manifest and retention/hold field, Owner review status, preservation rule enforced in isolated test service.
Acceptance: evidence integrity, restricted access, configured hold blocks purge.
Negatives: evidence deletion under active hold, foreign investigator, false legal-hold compliance promise.

### 12 decision-and-change-trace
Workflow: requirement -> feature -> source file -> tests -> release.
Build: machine-readable requirement graph validator/importer for safe local source snapshot data, without rewriting Drive history.
Acceptance: all supplied requirement IDs accounted for, correct status/link path, explicit missing/deferred items, test/proof chain.
Negatives: orphan feature/requirement, duplicate IDs, removed hard feature from denominator, passing test without exact SHA.

## 6. END-TO-END DEMO PROOFS (REAL LOCAL CODE)

Story A — Secure event & export:
- Business A, Tenant T1 source produces fixture event in PG17.
- Trusted adapter adds audit receipt; replay same key returns same receipt, changed payload denied; concurrent two sessions create one.
- Owner sees source-linked journal, filtered count and export with logged SHA256/row count.
- Site-only, investor, revoked and T2 cannot see or export A or its counts.

Story B — Anomaly & human triage:
- Deterministic duplicate/stale source event triggers clear advisory signal with links to original evidence.
- Human Owner can review/dismiss with reason and append-only receipt. Two-reviewer race allows one terminal state.
- Neither signal nor dismissal changes stock, money, approval, role nor audit history.

Story C — Evidence & release truth:
- Feature has green CI on SHA1, source HEAD is SHA2, no signed GoTrue and no live deployment receipt.
- Readiness engine MUST show "not certified / stale CI / staging missing / deployment unverified".
- Adding valid synthetic fixture proof only improves isolated simulation truth, never real project production status.
- Incident with active hold retains all bound evidence through attempted purge.

## 7. ACCEPTANCE TEST MATRIX AND TEST RUNNER

Require fresh PostgreSQL 17 PG database lifecycle, SQL strict migration order, 2-tenant/3-business/4-site seed, role negative, stale/replay, denial and audit, genuine two independent simultaneous DB connections for duplicates and review. Node unit integration for hash/canonical JSON/redaction/CSP/CSV/signed-proof absence. If browser runner exists, 390px Android and 1440px desktop accessibility and empty/denied/loading states; no visual static-only completion claim.

Run and document SQL+Node tests, exact HEAD SHA, GitHub workflow run status. CI must cover all GOV003 source paths and run only disposable resources. No service_role in browser; no secrets in repository, CI logs or exported fixtures. If test fails: diagnose and fix, never label complete. No insistence on real staff IDs or paid infrastructure.

The following is the required receipt format for each of 12 rows:
- feature_id | implemented source/API/storage/report paths | positive + negative test names
- status: NOT_STARTED / CODED / ISOLATED_TESTED / INTEGRATION_PENDING / RELEASED
- commit SHA | CI run URL and conclusion | missing independent code | integration/release blockers

No feature may be counted as full CORE10 E2E unless actually integrated, tested under real signed GoTrue and released.

## 8. EXECUTION ORDER AND PR RULES

1. Checkout assigned branch; read this work order + exact Master Register rows and existing relevant architecture docs. Check AGENTS.md / CLAUDE.md if present. Read other agents' open PRs only for contracts; do not edit their branches.
2. Create isolated actual SQL/test core, then audit/event, receipts, RLS, reports, risk engine, readiness/provenance, grant diff, export, incident, trace. Each independently runnable milestone must push genuine code and tests, not an assignment summary.
3. Build isolated responsive local reviewer preview only after source logic works; use synthetic data with clearly labeled DEMO/NOT LIVE. Business scoped means no other tenant data.
4. Run new PG17 and Node test suites; inspect CI on the latest head; repair all reproducible failures. Push to the SAME assigned branch, update the single existing Draft PR.
5. Before final result verify git diff paths: only new GOV003 package, its tests, its dedicated CI workflow and docs. No change to any original Islamia ERP file or branch.
6. Produce GOV003_IMPLEMENTATION_MATRIX.md and concise final handoff with exact HEAD/CI, tested features, blockers and unsigned-vs-signed evidence. If Google Drive connector available, update only GOV003 source evidence with confirmed code; otherwise provide a copy-ready Decision Book update, never rewrite other decisions.
7. Do not request Owner micro-confirmation for safe isolated implementation details; no Owner production permission is implied. Never automatically deploy or integrate. If a feature is truly dependent on another module, provide an executable isolated adapter contract with rejection tests and mark external integration unbuilt.
8. Finish the independently buildable scope; do not stop after outlining or researching.

## 9. FINAL HANDOFF FORMAT

Include: Draft PR and branch; exact tested HEAD; GitHub PG17+Node/browser CI URL and confirmed conclusion; full 12-row acceptance evidence matrix; local demo route and which UI actions execute actual local commands; files changed; independent proof original Islamia code/archive unchanged; blocked signed GoTrue/A034/canonical event adapter/real deployment and legal retention decisions; NO main/SG/real staff/production writes. Mark MODULE DELIVERY GOV003 NOT_COMPLETE_PER_DETAIL until true canonical integrated certification.

## 10. ONE-SHOT OWNER COMMAND FOR CLAUDE

Please implement Master Build 03 C10-CAP-GOV-003 in mistybari99/CORE-10-CENTRAL.
Checkout branch claude/build-03-gov003-audit-readiness-20261112 and follow docs/development/CLAUDE_BUILD03_GOV003_INDEPENDENT_EXECUTION_ORDER_2026-11-12.md and Issue #84 exactly.
Use Claude Opus 5.5 High (Sonnet 5.5 High fallback). This is a REAL BUILD task: produce executable PG17 source, server client contracts, all 12 acceptance tests, real concurrency, safe local UI and exact-head CI; push to the existing branch / Draft PR. You own only this isolated GOV003 package. No Work/Codex handoff, no production integration, no edit to Builds 01/02, existing Claude assignments or original Islamiya Misty Ghar ERP. Build everything independently feasible now and finish with exact proof and honest remaining gaps.
