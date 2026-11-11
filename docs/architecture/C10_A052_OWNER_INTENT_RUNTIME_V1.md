# C10-A052 — Owner Intent Runtime v1 (Draft, disposable PostgreSQL only)

Status: **DRAFT source + tests**. Not merged, not applied to any Supabase project, not GoTrue-tested. Implements a real P0 vertical slice of
D049/R128; it is **not** the whole universal engine.

## What it does
An authorized Owner writes a business rule in Bangla or English. A deterministic rule parser (no LLM, no network, no `eval`) proposes a
structured interpretation with editable assumptions. The server re-validates it against a **certified capability allowlist**, stores it
as a versioned intent, produces a **dry-run preview** (before/after, worked sample, formula with units, impact, conflicts), and only after
validate -> approve -> publish writes an **advisory** setting version with audit and rollback.

| Capability (certified) | Route | Example |
|---|---|---|
| `wastage_threshold` | A052 advisory calculator | sweets wastage above 3% of produced kg |
| `pack_discount_margin` | A052 advisory calculator | 4 L paint pack, discount must keep margin >= 15% (exact decimals, max-discount output) |
| `low_stock_alert` | **A045 `threshold_rule_v1`** | stock below 20 |
| `margin_floor_approval` | A045 `threshold_rule_v1` | margin below 10% needs approval |
| `order_total_approval` | A045 `threshold_rule_v1` | project materials order >= 6 lakh needs approval |

Everything else becomes a stored **engineering requirement** (`NEEDS_HANDLER_BUILD`, with the A045 handler it would need and its live
certification state) or, for permission grants / code / ledger posting / destructive asks, `NOT_ALLOWED_BY_POLICY`. These never execute.
The read-only project-materials report, wastage report and margin report are explicitly `NOT_BUILT`.

## Canonical sources reused (no second source of truth)
* Identity/scope: A018 `actor_uid()`, `can_tenant()`, `can_manage()`, `can_see_business()`, `can_site()`.
* Registry: A045 `micro_engine_handlers_v1` (read live for context and requirements) and A045 RPCs `save_engine_draft_v1`,
  `validate_engine_version_v1`, `assign_engine_v1` for the A045 route (engine key `a052_<capability>_b<business>`).
* Modules/template: A020 `business_module_settings_v1`, `templates`. A044/A045/A050 files are untouched (read-only dependencies).

## Lifecycle and roles
`INTERPRETED|NEEDS_CLARIFICATION|UNSUPPORTED|ENGINEERING_REQUIRED -> PREVIEWED -> VALIDATED -> APPROVED -> PUBLISHED` (or `REJECTED`).
* Submit / revise / preview / validate / reject: tenant Owner or Business Owner of that business.
* Approve / publish / rollback: **tenant Owner only** (A045 publishing is tenant-Owner-only).
* Manager, investor, site staff, revoked members, anon and other tenants: denied (guidance read allowed for visible members, no settings values).
* Idempotency receipts per tenant + request key; `expected version` on every transition; a **preview hash** pins what the Owner saw, and
  validate/approve/publish rebuild the preview server-side and fail with `intent_stale_basis` if the world changed.
* Blocking conflicts (`NO_EFFECTIVE_CHANGE`, unmanaged A045 engine key, uncertified handler) stop validation.
* Site named in the request: stored, but v1 handlers apply at business level (shown as a warning, not hidden).

## Data model (`c10_demo`, RLS enabled, direct writes revoked)
`intent_capabilities_v1`, `intent_guidance_v1`, `owner_intents_v1`, `intent_settings_v1` (immutable payload versions, one ACTIVE),
`engineering_requirements_v1`, `owner_intent_events_v1` (append-only, trigger-protected), `intent_receipts_v1`.
Owners/Business Owners get RLS-scoped SELECT only on intents/settings/requirements/events; everything else goes through
`SECURITY DEFINER` RPCs with pinned `search_path`.

## Safety invariants
No eval/dynamic JS/SQL; params are strictly typed and key-allowlisted; no permission grants; publishing never writes stock, money,
payroll, accounts or users (tested: stock movements and items unchanged); outcomes are advisory (`canAuthorizeOperation=false`,
`operational_enforcement=false`). The client parser can only *propose*; invalid claims (unknown capability, out-of-range or extra params,
bad locale, engineering requests carrying a capability) are rejected by the server.

## Guidance
`core10-owner-intent-guidance.js` is the single source (what/why/when/default/exception/consequence/data+formula+units/linked report, Bangla +
English); `tests/c10_a052_gen_guidance.js` generates the SQL seed and CI fails on drift. `read_guidance_v1` adds the caller's effective permission
and, for managers, the live setting.

## Files
SQL `internal/enterprise-sql/c10_a052_intent_{core,guidance_seed,rpc}_v1.sql` · JS `core10-owner-intent-{engine,guidance,client}.js`, `core10-owner-intent.{js,css,html}`
· tests `tests/c10_a052_*`, `tests/e2e/core10-a052-owner-intent-browser.js` · CI `.github/workflows/core10-a052-owner-intent-ci.yml`.

## Tests
PG SQL E2E (two tenants, owner/business-owner/manager/investor/revoked/staff/anon/other-tenant, replay, stale, invalid params/locale/unit, immutability);
Node unit (Bangla/English supported, clarification, unsupported, refused, invalid locale, evaluators); JS/SQL evaluator parity; Playwright at 390 and 1440 against a
real disposable PostgreSQL through a psql bridge.

## Honest limits / blockers
* Identity is a claim simulation; **GoTrue/real Supabase/RLS-on-staging not tested**; no production migration.
* The parser is rules, not language understanding: unknown phrasing falls to `ENGINEERING_REQUIRED/unclassified` or a clarification question.
* The server does not re-parse natural language; it validates the structured result (documented trade-off for determinism without an LLM).
* Published settings are advisory configuration; no module consumes them for enforcement yet (A045 says the same for its engines).
* Site-level overrides, report handlers, workflow/notification/integration handlers, Owner delegation and an AI adapter are future slices.
* Integration with the Owner shell/preview worker is intentionally not done (Codex-owned files untouched); this page is standalone.
