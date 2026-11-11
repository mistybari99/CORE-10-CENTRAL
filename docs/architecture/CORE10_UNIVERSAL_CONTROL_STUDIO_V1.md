# C10-A042 — Universal Owner Control Studio

**Scope:** CORE 10 CENTRAL, shared across every tenant, business model and operating site.
**Status:** brand-neutral design and pure JavaScript contract. **NOT live authorization**, and not a second ERP.
**Existing approved authority:** C10-D033, C10-D037, C10-D041, R014–R026, R035–R036, R079.
**Owner clarification:** Provide one independent, expandable place from which an authorized Owner can configure ON/OFF/SHOW/LOCKED/HIDDEN, rules, role/user permissions, approvals and new reusable small feature-engine definitions for any supported business.

## Core user experience — planned Control Studio navigation

1. **Capability Switchboard** — ON/OFF for supported modules per tenant, business or site; installed readiness, dependency impact and who may operate it.
2. **Roles & Access Matrix** — named roles and individual grants/denials; business/site/operation scope; expiry, revoked sessions, delegated access and effective permission preview.
3. **Visibility & Workspace Designer** — Show, Locked, Hidden and role favorites. These affect menus, not actual RLS/API permissions.
4. **Rule Builder** — Allow, Warn, Block, Request Approval; numeric/percentage threshold, time-window, condition, legal/policy dependencies and before/after rule previews.
5. **Approval & Exception Center** — required approvers, request queue, self-approval ban, multiple sequential reviewers, temporary delegation and emergency requests; no auto bypass.
6. **Configuration Center** — optional invoice/document, numbering, localization, unit, reporting, stock warning, notification, fiscal and other feature settings (when implementation exists).
7. **Micro-Engine Workshop** — draft reusable workflows, calculators, reports, validation policies, notifications, automations or integrations by choosing registered controls and operations.
8. **Version, Change & Audit Center** — proposal/review/approve/activate/revert lifecycle, effective date, dependency matrix, explain-why, audit and export of authorized configuration.
9. **Operational Safety Desk** — degraded mode, provider kill switches, offline draft safety and readiness; protected invariants cannot be disabled by business config.

## Two separate control types

**Configurable switches:** operational modules, supported UI visibility, workflow preferences, reminders, optional integrations, approval routing, local business rules and limits. Owner may change supported settings with appropriate authority, including overrides by role/user and scoped exceptions.

**Non-negotiable invariants:** tenant/business/site data isolation, verified identity, backend authorization, revocation, immutable audit, atomic stock/payment/ledger writes, accounting balance and production release readiness. These are *not* optional feature switches. If a requested setting conflicts, reject the request and explain why rather than silently weakening the safety rule.

## Effective control resolution

- Platform → Tenant → Business → Site determines feature availability. Missing overrides inherit the registered default.
- An explicit OFF at any matching ancestor is a hard barrier: a Site ON cannot override Tenant OFF.
- Role and User settings do NOT independently activate a disabled module; they affect approved access grants and visibility only.
- For permission, No explicit grant = DENY; explicit DENY wins; expired/revoked grants are not effective. Source scope and identity are verified by the server, not by a browser-provided role.
- Show / Locked / Hidden are optional presentation choices. Show without signed server authorization stays locked for execution.
- Every capability must have a registered unique key, supported scopes, required dependent capabilities, supported readiness and action keys. Unknown keys and duplicate/contradictory writes fail closed.
- Every policy should support a what-would-change preview and an effective-permission explanation. Actual runtime permission is the server's decision.

## New micro-engine contract — declarative, no arbitrary code execution

A proposed micro-engine descriptor contains identity, kind, required controls, action keys, input/output schema, scopes, approver policy, error behaviour, idempotency, audit events, reporting needs, test fixtures and release evidence. On declaration, status is DRAFT / NOT IMPLEMENTED and canExecute=false. The Workshop must NEVER interpret an arbitrary formula or JavaScript supplied by a user as executable server code.

A feature becomes usable only when a reviewed server handler exists, dependencies are deployed, real authenticated RLS and RPC tests pass, negative user/business/site tests pass, rollback and audit are verified, and the Owner authorizes the release. The capability catalog entry alone is insufficient.

## Planned server architecture (not installed)

Authoritative tables or equivalent backend entities:
- control_definitions, scope_control_values, permission_role_templates, subject_grants, subject_denials
- visibility_preferences, approval_policies, delegation_records, policy_exceptions
- control_change_requests, control_policy_versions, immutable_control_audit
- micro_engine_descriptors, micro_engine_handlers, release_evidence

Each record must carry tenant and applicable business/site keys, authenticated actor, revision, request key, timestamps and the audited decision basis. Untrusted client role fields cannot be used as security claims. Sensitive operations need explicit server guards and appropriate RLS, with separate permissions for personal report exports, financial data and approval.

### Future server mutation sequence

Draft → Proposed → Reviewed → Approved/Rejected → Applied → Monitored → Reverted/Closed.

A valid change includes immutable proposal ID, affected object, before/after diff, explicit scope, dependency analysis, permission test, approval or segregation of duty, scheduled activation when supported, idempotent atomic persistence, event audit, and cache invalidation. Reverting a setting NEVER silently reverses historic posted stock or accounting entries.

## Existing implementation evidence, not an authority to activate

The earlier Settings/Access Manager patterns include fiscal rules, optional tax display, barcode modes, Show/Lock/Hide, stock warning or block, discounts, unit conversion, role favorites, person/role grants with location and expiry, sensitive report/export controls and emergency access requests. These are *patterns* to generalize, NOT code to copy unreviewed into the neutral control plane.

The separately developed existing Owner Control and Role/Revocation modules remain in place. This Studio must *reuse* their authoritative storage and server guards after compatibility review, rather than creating parallel grant or approval tables that diverge.

### Exact boundaries of this first commit

- Internal catalog: internal/universal-control-studio/control-catalog-v1.json
- Deterministic preview: internal/universal-control-studio/control-studio-v1.js
- Contract tests: tests/c10_a042_universal_control_studio.test.js
- CI: core10-a042-universal-control-studio-ci.yml

**Current implementation proves only** safe pure configuration and permission previews and draft micro-engine specification. The engine always reports canExecute=false. No settings are saved, no module is enabled, no business stock, sales, finance or legacy data changes, and no live Supabase security decision is made.

**Next development slice:** integrate signed Owner control service, dedicated UI, real server scope and mutation API/RLS, audit/revision persistence, and 2-tenant negative tests; reconcile existing Owner Controls/Revocation without duplicating them. Operational use remains pending readiness checks, not indefinitely deferred by the Owner.
