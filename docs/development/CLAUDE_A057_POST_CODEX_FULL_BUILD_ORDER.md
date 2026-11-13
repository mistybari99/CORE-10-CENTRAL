# CLAUDE BUILD #4 — C10-A057 Full Autonomous Implementation Order

**Status:** Owner-assigned substantial NEW build, implementation pending. This file is not evidence Claude Code has run.
**Created:** 2026-11-11 (Asia/Dhaka)
**Issue:** https://github.com/mistybari99/CORE-10-CENTRAL/issues/64
**Branch:** `claude/c10-a057-universal-crm-commerce-v1`
**Target base:** current Preview PR #60 for draft; **final compatibility + integration must be based on verified Codex result AFTER Owner's Codex review**.
**Priority contract:** Owner says “কোনো ডিসিশনের জন্য আমার জন্য ওয়েট না করে, ... পুরো কমপ্লিট করে রাখবে”; engineering is authorized to choose safe, reversible, documented defaults, but this is not authorization for live database/security/stock/finance changes or external commercial messaging.

## Exact code-first delivery instruction

You are the Claude Code engineer assigned **the fourth NEW module**: universal brand-neutral B2C/B2B Customer CRM, service/support, lead→quote→order request, and tenant-configurable online storefront & omnichannel customer intake. Existing `crm_*.js`, `customers.js`, `website.js` and `v2/` are **legacy Islamiya-specific implementations** and must be analyzed/preserved—not presented as a generic new build or copied into all tenants. Existing A049 order and A050 portfolio are canonical integration points.

**Read complete contract and acceptance:** https://github.com/mistybari99/CORE-10-CENTRAL/issues/64, D049/R128, D047/R126, D048/R127, D042/REV-009, canonical Master Decision Book and the repo-root `AGENTS.md`.

### Modules, actions, source-backed scenarios
1. Customer master: canonical tenant/business customer and organization/contact identity, profile, related sites/orders, duplicate candidates, safe merge, permissions, consent, history and audit, privacy/export/redaction.
2. Consent and communication policy: channel-specific consent/revocation/expiry/opt-out and suppression; no real automated messaging without approved provider and verified credentials.
3. Customer enquiry/lead pipeline: source intake → qualified opportunity → priced quote (versioned) → order request → existing A049 canonical order only through guarded signed adapter. Staff task/followup/reminder log; source-linked explanation, status, report lineage.
4. Support desk: ticket intake, priority, SLA, staff assignment, resolution evidence and Customer 360 timeline, warranty/service case, return/refund request boundary. No finance or stock mutations from CRM.
5. Website and e-commerce: branch/product/service/catalog visibility, safe CMS content, cart, quote/order request, customer communication, delivery zone and branch fulfillment routing, consent collection, safe site preview. Integrate existing A048 inventory/A049 operations read data via typed adapter; never invent stock availability or payment success.
6. Owner reports: lead funnel/conversion, retention/cohorts where authentic source exists, pending followups, ticket resolution, consent/campaign metrics, quotation value (advisory); unknown COGS/profit must show `NOT CERTIFIED`.
7. Cross-industry: sweets custom-order; B2B paint quote; construction project enquiry; restaurant service booking enquiry (NOT a real table booking until booking engine certified); technology consulting lead.
8. Settings and explainability: all main actions have Bangla/English what/why/when, default, effects, permissions, report output and alternatives; no extra owner microdecisions.
9. Add matching SQL/RPC and tests: v1 `c10_demo` disposable SQL, signed adapter `core10-crm-enterprise-*.js`, UI `core10-customer-enterprise-*.html/js/css`, `core10-omnichannel-*.html/js/css`, generated data fixtures, one main browser E2E storyboard for each industry, version/audit hooks, safe APIs.
10. Integration: cross-module contract mapped to A018/A019 tenancy, A021/A034 ACL, A045 certified engine registry, A046 personas, A047 sites, A048/A049 order/stock, A050 portfolio. **Never** duplicate their underlying tables or permission grants.

### Autonomous decisions without Owner waiting

Make yourself the **Chief Implementation Architect** for this package. For every ordinary engineering question (schema shape, UX behavior, default SLA, recommended form fields, report formulas, notification policy, conflict resolution), select the safest production-expandable choice based on existing decisions, write its rationale in `docs/architecture/C10_A057_DECISION_AND_TRACE.md`, expose configurable choices in the Owner Studio where supported, and continue implementation. Do not interrupt Owner with “Which design?” questions.

Suggested **reversible, nonlegal technical defaults** for initial demo:
- CRM OFF for new customer tenants until Owner enables; sample fixtures enabled in disposable tests only.
- Tenant-level customer identity, per-business interactions, site-aware access, explicit consent per outreach channel; absent consent = do not send.
- All public customer requests start `DRAFT` or `RECEIVED`, never automatically create stock transfer, confirmed sale, refund or bank settlement.
- Default SLA tiers are Owner-editable **examples**, not contractual promises: urgent 4h, standard 24h, low 72h measured from configurable business hours. Do not auto-publish as company policy.
- Marketing integration disabled; provider-neutral adapter implemented and tested with synthetic no-op, no external outgoing requests in demo.
- Show missing source prices/stock/cost as unavailable/unverified; do not treat null as zero.
- Capability self-serve settings must be versioned, audit, reversible, scoped; prototype choices cannot disable security, consent or financial invariants.

### Demo/test BEFORE claiming completion

Use canonical A046 16 synthetic personas + anonymous, test with 2 tenants, ≥3 businesses and ≥4 sites. Build disposable PG17 seed with synthetic companies, contacts, email/phone and consent—never use actual business customer rows. All tests must run without real GoTrue or production Supabase. PG17 RLS/RPC positive+negative, signed synthetic HMAC PostgREST, Node contract, Chromium actual 390/1440 visual/workflow screenshots, site/customer isolation, role loss while active, replay/idempotency, stale version, concurrent merge/quote/order, HTML injection, CSV injection, opt-out precedence, timezone/business hours, unsupported provider state, mobile offline draft conflicts. Test full realistic create → qualify → quote → website order request → support ticket → owner report **before** claiming complete.

### Full completion, not unfinished scaffolding

**Do not call C10-A057 COMPLETE until all internally buildable acceptance points from Issue #64 are implemented with UI↔RPC↔DB↔report↔permission↔audit and passing tests.** No silent “TODO”, dead buttons, fake payment success, disconnected visual UI, missing CI files or incomplete formulas. Fix defects and retest before closing each internal vertical slice.

**External provider and release gates differ from internal code completeness:** actual live domain/DNS, real SMS/email, bank/payment gateway, true GoTrue staging, main merge and production RLS/migrations require separate verified credentials/Owner risk approval. Build fully functioning **simulation/sandbox adapters** and mark those external activations `NOT ENABLED`, never block all other engineering while waiting. If critical risk cannot be safely resolved, fail closed, explain which external activation remains intentionally gated, continue everything else.

### Codex precedence + isolation

Do not edit Codex `preview/worker.mjs`, the Preview #60 integration files, or other Claude modules while working here. You may build internal A057 source in your dedicated branch NOW. When Codex produces an actual verified Owner-reviewed branch/commit, reconcile A057 with that **new Codex head**, run all integrated tests and adapt signed API shapes; **final integration must sit above Codex**. Do not force rebase/force push another agent's branch, do not merge into main. If Codex has not finished, complete independent A057 functionality and report final integration as pending Codex checkpoint—not as a missing Owner microdecision.

### Deliverables

- Actual code files under exclusive A057 namespace, no legacy overwrites;
- Documented canonical dependencies, migration order, rollback and provider gates;
- Fixed demo seed and fully functional positive/negative browser workflows;
- exact PR branch SHA, required CI success, known limitations, and proof of no production writes;
- Owner-facing succinct Bengali “what works / what is demo only / what needs Codex integration / what external production activation is gated” with links.

**Source is preserved, no autonomous release approval.** This assignment is ready for a Claude Code execution session; writing a GitHub Issue/Draft PR alone does not run Claude.
