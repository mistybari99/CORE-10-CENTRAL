# Integration Ports - Live Parity Audit (P0, read-only)

Date: 2026-11-10. Scope: compare the LIVE Islamia ERP integration objects (project IMG-ERP-SG) with the new central engine (`scripts/c10_a038_integration_core_v1.sql`, `c10_a039_payments_v1.sql`, `c10_a040_delivery_ai_v1.sql`, schema `c10_demo`, DISPOSABLE/CI only).

Method: SELECT-only catalog queries (`pg_get_functiondef`, `pg_policies`, `pg_constraint`, `pg_index`, `information_schema`, `pg_class`), the config flags in `rules`, and row counts. No table rows containing personal data were read. No secret values were read or are recorded here; a regex scan of all `notify_*`, `payment_*`, `integration_*`, `ai_*`, `_ai_*`, `webhook_*`, `x1_*`, `social_*`, `_x500*`, `_crmb_*` function bodies for secret-like literals found none. Nothing was applied, no SQL for applying is produced by this task.

Labels: **READ FROM LIVE** = observed directly in the live database today. **INFERRED** = deduced from names/structure, not observed. **NOT CHECKED** = not examined.

Status words: only READ FROM LIVE claims are made about live; nothing here is STAGING VERIFIED.

## 1. Headline answers

1. Does live `notify_enqueue` enforce consent? **YES (READ FROM LIVE).** It requires a `notify_optin` row with status `in` for (customer, channel), and calls `_crmb_enqueue_guard`, which rejects do-not-contact (`crm_contact_prefs.dnc`), linked-duplicate DNC and opted-out customers.
2. Does it enforce quiet hours? **NO (READ FROM LIVE).** `notify_enqueue`, `notify_outbox_claim` and `notify_outbox_report` never call a quiet-hours function. Quiet-hours logic exists (`_crmb_in_quiet`, rule keys `crm_quiet_from/to`; `_x500_inquiet`, rule keys `social_quiet_from/to`) and is used by `_crmb_send_allowed`, which is called only by `social_wa_enqueue` and `social_publish_claim`. In addition all four quiet-hours rule values are currently null, which the functions treat as "no quiet hours" (READ FROM LIVE).
3. Rate limits on messaging: **NONE per recipient/day/account (READ FROM LIVE).** Only a global on/off rule (`notify_sms_on`, currently `false`) and `notify_sms_max_tries` (5, attempts per row).
4. Is anything business-scoped? **Only weakly and currently inert (READ FROM LIVE).** There is no `business_id`/`org_unit_id` column on `integration_registry`, `notify_outbox`, `payment_webhook_log`, `ai_providers`, `ai_calls`, `delivery_jobs`, `inbound_messages`. Scoping exists only indirectly: `notify_enqueue` filters the customer through `_m132_own(org_unit_id)`, `notify_optin` has an `org_unit_id` column plus a RESTRICTIVE policy, `payment_intents` has a RESTRICTIVE `_loc_vis123(location_id)` policy. All of these are gated by rule `org_scope_on`, which is `false` today, so they are no-ops (READ FROM LIVE). The registry, AI provider settings and webhook log are global (one set per whole install).
5. Owner-only? **Config surfaces yes, messaging/payments no.** `integration_set`, `ai_pause_all`, registry/versions/rotations/ai_* reads use `is_owner()`. But `notify_enqueue`, `notify_optin_set` and reads of `notify_outbox`/`notify_optin`/`notify_templates` use `_i62_ok()` = owner OR `customer_manage` grant (any location); payment reads/creates use `_acct_manage()`; claim/report/webhook use owner OR an active `ops_accounts` row with purpose `notify` (READ FROM LIVE).
6. Live state: everything is OFF and empty. `integration_registry` 13 rows, all `enabled=false, status=not_connected, read_only=true, dry_run=true`, config `{}`, no env names. Rules `notify_sms_on`, `pay_gateway_on`, `ai_on`, `ai_pause_all` all `false`. Row counts 0 for notify_outbox, notify_optin(+log), payment_intents, payment_webhook_log, ai_calls, delivery_jobs, inbound_messages. Seed data: notify_templates 5, ai_providers 5 (only `local_rules` enabled), ai_redaction_rules 6, ai_agents 10 (READ FROM LIVE).
7. Business model reality: businesses appear to be `org_units` (4 rows) and `legal_entities` (2 rows); `business_profiles` 1 row; `_my_biz123()` and `_business_of_loc123()` resolve a user's businesses via locations (READ FROM LIVE that these exist and are used; their full semantics NOT CHECKED).

## 2. Object-by-object parity matrix

Legend: Y = enforced in DB (READ FROM LIVE), N = not enforced (READ FROM LIVE), P = partial, n/a = not applicable.

| Live object | Consent | Quiet hrs | Rate/caps | Idempotency | Business scope | Owner-only | Secrets |
|---|---|---|---|---|---|---|---|
| `notify_enqueue` | Y (opt-in + DNC + group DNC/out) | N | N (only max_tries) | P (`client_id` UNIQUE; `(source_type,source_id,template_code)` partial unique) | P (customer via `_m132_own`; inert while `org_scope_on=false`; owner bypass) | N (owner or `customer_manage`) | n/a |
| `notify_outbox_claim` | N (no re-check at send time) | N | N | P (lease: `sending` rows reclaimed after 15 min; `FOR UPDATE SKIP LOCKED`) | N | N (owner or ops `notify`) | n/a |
| `notify_outbox_report` | n/a | n/a | n/a | P (ignores non-`sending` rows) | N | N (owner or ops `notify`) | n/a |
| `notify_optin_set` | records consent; opt-out cancels queued rows | n/a | n/a | upsert on `(customer_id,channel)` | P (`_m132_own`) | N (owner or `customer_manage`) | n/a |
| `payment_webhook_receive` | n/a | n/a | N | Y (`UNIQUE(provider,event_id)`, monotonic status rank, stale events ignored) | N (no business column; intent has `location_id`) | N (owner or ops `notify`) | strips secret-like keys from payload |
| `payment_intent_create` | n/a | n/a | N | Y (`client_id` UNIQUE, `(provider,provider_ref)` partial unique) | P (location check `can_loc`; RESTRICTIVE `_loc_vis123` read policy) | N (`_acct_manage` or ops `notify`) | n/a |
| `integration_set` | n/a | n/a | sets `rate_per_min`, `monthly_call_cap` fields but nothing reads/enforces them (NOT CHECKED outside the functions listed) | n/a | N (global by `code`) | Y (`is_owner`) | P (see 3.5) |
| `integration_test_record` | n/a | n/a | n/a | n/a | N | owner or bot (`_x1_job_ok`) | redacts detail via `x1_redact` |
| `ai_check` | n/a | n/a | Y (monthly token and money budget, provider and agent) | n/a | N (global) | P (`_ai_can_use` = owner or `assistant_use` grant) | n/a |
| `ai_pause_all` | n/a | n/a | n/a | n/a | N (global rule) | Y (`is_owner`) | n/a |

### 2.1 Messaging: `notify_outbox`, `notify_optin`, `notify_templates` (READ FROM LIVE)

- `notify_outbox` columns: id, client_id, customer_id, channel (`sms`|`whatsapp` only), to_phone (E.164 CHECK), template_code, body (<=480), status (`queued|sending|sent|failed|cancelled`), attempts, max_attempts (1..20), next_try_at, last_error, provider_ref, source_type, source_id, created_by, created_at, claimed_at, sent_at. No account, business, org, idempotency-key-per-account, lease column (uses `claimed_at`), consent timestamp, or scheduled_for.
- The body is fully rendered and stored in the outbox with the phone number in clear (`to_phone`, `body`); readable by anyone passing `_i62_ok()`.
- Retry: `notify_outbox_report` retries with exponential backoff 2,4,8,16... minutes (no jitter), no transient/permanent distinction: every failure retries until `max_attempts`.
- Opt-out handling: `notify_optin_set(p_in=false)` cancels still-`queued` rows, but a row already `sending` (claimed) is not cancelled, and `notify_outbox_claim` does not re-check consent (INFERRED risk window: opt-out between claim and provider call).
- No block states (`blocked_no_consent` etc.): disallowed enqueues RAISE an exception and write nothing, so there is no record of blocked attempts (engine writes a blocked row).
- Channels: consent and outbox support only `sms` and `whatsapp`. Email and Facebook are not covered (the engine consent table lists whatsapp/facebook/sms/email).
- Consent evidence: `notify_optin_log` (append-style log, written by `notify_optin_set`) plus the CRM evidence function `_crmb_legacy_evidence`; richer CRM consent RPCs (`_crmb_consent_apply/_set/_import/_history`) and `crm_consent_events` exist (0 rows). Their bodies were listed but only `_crmb_consent_ok`, `_crmb_block_reason`, `_crmb_send_allowed`, `_crmb_enqueue_guard` were read in full.
- Consent here is keyed by `customer_id` (a customer record); the engine keys by a hashed/opaque `contact_ref` per business. Different identity model.

### 2.2 Payments: `payment_intents`, `payment_webhook_log` (READ FROM LIVE)

- `payment_intents` columns: id, client_id, provider, provider_ref, sale_id, customer_id, location_id, amount, currency, status (`created|pending|succeeded|failed|cancelled|refunded`), paid_amount, sale_payment_id, created_by, created_at, updated_at. No account id, no idempotency key besides `client_id`, no expiry, no refunded_amount, no reconciliation state, no `needs_review` state.
- `payment_webhook_receive` takes `p_signature_ok boolean` as an argument from the caller. The database performs no signature verification; a caller with owner or ops `notify` rights can assert `true`. The engine has the same trust model (READ FROM the A038/A039 files): `integration_webhook_receive_v1` and `payment_apply_event_v1` take a caller-supplied `p_signature` of `ok|bad|missing`, and are granted to `authenticated` with a `can_manage` (owner) check, not to a service role. So neither side verifies a signature in SQL; verification must happen in the server function (P2/P3), and the engine's webhook RPCs would need a service-role/ops caller rather than an owner JWT (see Q8).
- The function does NOT compare `p_amount` with the intent amount. On `succeeded` it sets `paid_amount := p_amount` and `status='succeeded'` even when the amounts differ. The engine's `payment_apply_event_v1` has a `needs_review` path for mismatch (per A039 design), so this is a real gap in live.
- The function does NOT write to the ledger/`sale_payments`; linking is a separate manual step (`payment_intent_link`). The engine writes a `payment_ledger_v1` row transactionally on paid (per A039).
- Status ranking is monotonic (no backward moves), duplicates are a no-op, stale events are logged with note `stale_event`, bad signature logged and not applied, payload scrubbed of `authorization|signature|secret|token|password|api_key|apikey|card|card_number|cvv` keys. Good properties the engine should preserve.
- A `refunded` status exists but there is no refund amount/partial refund, no approval, no `payment_refund` object (`order_refunds` has 0 rows; NOT CHECKED in detail).
- Gate: rule `pay_gateway_on` (false) returns `{off:true}` / raises `gateway_off`.

### 2.3 Registry: `integration_registry` / `integration_config_versions` / `webhook_rotations` (READ FROM LIVE)

- Registry columns: code (PK, global), kind (CHECK list: website, hosting, facebook_page, instagram, whatsapp_business, sms_gateway, email_smtp, payment, ai_provider, vision_provider, analytics, other), label_bn/en, status (`not_connected|configured|connected|error|disabled`), enabled, read_only, dry_run, config jsonb, env_names text[], rate_per_min, monthly_call_cap, config_version, last_* test fields, updated_*.
- No `business_id`, no `mode` enum (three booleans instead), no `secret_ref` column (`env_names` plays that role).
- `integration_set` allows setting `enabled=true` with no CHECK tying it to `status='connected'` or a passed test; `dry_run`/`read_only` are independent booleans. The engine's CHECKs (`mode<>'off'` requires connected; `live` requires a test) are strictly stronger.
- Secret exposure risk: `integration_set` accepts an arbitrary `config` jsonb with no check for secret-like keys, and copies the whole config into `integration_config_versions` (readable by owner). If an owner pasted a key into `config`, it would sit in two tables. The engine adds a CHECK rejecting secret-like keys in `public_config`. Config is currently empty on all 13 rows (READ FROM LIVE), so nothing is leaking today.
- `kind` CHECK has no `courier`, `rocket`, `messenger`, `card`, `payment_gateway`, `email`; adding providers would need an ALTER of the CHECK (or mapping to `payment`/`other`).
- No kill switch for the registry as a whole (AI has `ai_pause_all`; messaging has `notify_sms_on`; payments have `pay_gateway_on`: three separate global rules, no per-business kill, no audit row for kill).
- Audit: `integration_config_versions` records config changes (who/when) but there is no audit of connect/enable/disable/test actions beyond `last_test_*` and `updated_by`. `webhook_rotation_record` writes only an env name (no value).

### 2.4 AI: `ai_providers`, `ai_calls`, `ai_check`, `ai_log` (READ FROM LIVE)

- `ai_check` is a STABLE (read-only) gate: owner or `assistant_use` grant, rule `ai_on` (false), `ai_pause_all`, provider enabled, agent enabled and bound to provider, data-sharing level vs provider level, monthly token and money budgets (provider and per agent). Returns structured reason codes. This is richer than the engine's `ai_request_v1` in some respects (data-sharing level, per-agent budget) and weaker in others (global, not per business).
- Budget usage is computed from `ai_calls` via `_ai_month_use` and depends on callers invoking `ai_log` after the call; check-then-call is not atomic (INFERRED: concurrent calls could jointly exceed the budget). The engine reserves a call row in `ai_request_v1` (per A040).
- `ai_providers.key_location` exists (value `supabase_secret` per AUDIT; not re-read) - a location name, not a secret.
- Redaction: 6 `ai_redaction_rules` rows exist, but no server gateway applies them (AUDIT: no gateway in repo). Engine has `ai_redact_v1` (SQL function) - only a stub-level redaction, see risks.
- `ai_calls` 0 rows; per-provider and per-agent global; no business column.

### 2.5 Delivery and inbound (READ FROM LIVE)

- `delivery_jobs`: id uuid, order_id (UNIQUE), location_id, rider_id, zone_code, fee, attempts (<=10), map_link, cod_amount, state (`unassigned|assigned|out|delivered|failed|returned`), handed_at, delivered_at, failed_reason, cod_collected, created_by, created_at, state_at. Location-scoped (`can_loc`) read policy for owner or POS viewers. No courier account, consignment id, courier state, COD remittance. One job per order (UNIQUE(order_id)), so a re-dispatch to another courier needs a design decision.
- `inbound_messages`: channel_id, location_id, external_id with `UNIQUE(channel_id, external_id)` (idempotent per channel; good), no signature status, no processed state beyond `status new|seen|converted|ignored`. Table has NO grant to `anon` or `authenticated` at all while a SELECT policy exists, so direct reads are blocked and access must go through RPCs (INFERRED which ones; NOT CHECKED).

### 2.6 RLS and grants (READ FROM LIVE)

All 12 inspected tables have RLS enabled, none FORCE RLS. `authenticated` has only SELECT on 11 of them (no INSERT/UPDATE/DELETE grants), `anon` has no grants. So writes are only possible through SECURITY DEFINER RPCs (all have `search_path=public`). Read policies:

| Table | SELECT policy |
|---|---|
| integration_registry, integration_config_versions, webhook_rotations, ai_providers, ai_calls | `is_owner()` |
| notify_outbox, notify_optin_log, notify_templates | `_i62_ok()` (owner or `customer_manage`) |
| notify_optin | `_i62_ok()` AND RESTRICTIVE org-scope policy (inert while `org_scope_on=false`) |
| payment_intents | `_i62_pay_ok()` (= `_acct_manage()`) AND RESTRICTIVE `_loc_vis123(location_id)` |
| payment_webhook_log | `_i62_pay_ok()` |
| delivery_jobs | active AND (owner OR POS view) AND `can_loc(location_id)` |
| inbound_messages / inbound_message_events | POS view AND `can_loc(location_id)` (but no table grant, see 2.5) |

Observation: the engine's policies are all `can_manage(tenant, business)` reads with writes only through RPC, the same pattern (RPC-only writes), but tenant+business based instead of location/grant based.

## 3. Gaps vs A038-A040 rules

Engine rules (A038 header): (1) off by default, live needs connected + passed test <=30 days; (2) no secrets, secret_ref only, secret-key CHECK; (3) owner/business-owner only to manage; (4) outbox idempotent per (account,key), blocked unless on + consent + outside quiet hours + under daily cap, dry-run flagged; (5) webhook events stored always, never applied when unverified, unique per provider event; (6) audit and webhook logs immutable.

| Engine rule | Live status | Gap |
|---|---|---|
| Off by default | Y in practice (all flags off, rules false) but by convention, not constraint | live can set `enabled=true` with no connected/tested precondition |
| connected + tested to go live | N | no CHECK; `dry_run` boolean vs `mode` enum |
| No secrets / secret_ref | P | `env_names` only; config jsonb unchecked for secret-like keys, copied to versions |
| Business scoping | N / inert | no business column anywhere on integration tables; org scope rule off |
| Owner-only management | Y for registry and AI config | messaging enqueue/consent use `customer_manage`; payments use `_acct_manage`; engine is owner-only (`can_manage`) for enqueue too, which would be stricter than live (see Q5) |
| Consent before send | Y at enqueue | not re-checked at claim/send; keyed by customer not contact; no email/facebook |
| Quiet hours | N for `notify_enqueue` | exists only for social/CRM-promo paths; rules unset |
| Daily/per-account caps | N | `rate_per_min`/`monthly_call_cap` fields exist but unused by messaging RPCs (NOT CHECKED elsewhere) |
| Idempotency (account,key) | P | `client_id` and source key; no per-account key |
| Blocked rows recorded | N | live raises exceptions; no `blocked_*` audit trail |
| Dry-run row flag | N | no per-row dry-run flag |
| Webhook stored always, unique per event | Y for payments (`UNIQUE(provider,event_id)`) | no generic log for messaging/courier |
| Unverified never applied | P | flag is caller-asserted in live |
| Amount match, needs_review | N | live marks succeeded without comparing amounts |
| Ledger link in one transaction | N | live does not write ledger on paid |
| Audit immutable | N | live audit tables are not guarded by immutability triggers (INFERRED: not checked for triggers on `payment_webhook_log`, `integration_config_versions`) |
| Kill switch per business | N | three global rules; none per business and none audited |

Things live already does that the engine should keep or verify it does: status monotonicity and stale-event handling; payload key scrubbing in webhook log; DNC and linked-duplicate guard (`_crmb_group_ids`); opt-out cancelling queued rows; do-not-contact via `crm_contact_prefs`; unique `(channel_id, external_id)` for inbound; per-agent AI budgets and data-sharing level; `search_path` pinned on all SECURITY DEFINER functions; location scoping of intents and delivery.

## 4. Recommended migration mapping

Principle: the engine lives in `c10_demo` (disposable) and mirrors the design in CONTRACT.md. Live has working RPC contracts the UI (`connect.js`, `integrations.js`, `tpl_*`, `crm_consent.js`, `xb_*`) already calls. Recommendation: **hybrid - extend live tables in place for messaging, payments and delivery; adopt the new engine's account/audit/limits model as additive tables; do not replace or rename any live table or RPC in P1.** Final choice needs Owner answers (Section 5).

| Area | Recommendation | Why | Risk |
|---|---|---|---|
| Provider catalog + accounts | ADOPT engine: add `integration_provider` and `integration_account` (business-scoped, mode, secret_ref, caps, quiet hours) as NEW tables; keep `integration_registry` as legacy read model, populated/backfilled from accounts or left as is | live registry is global, three booleans, no business; engine CHECKs stricter | two sources of truth until cut-over; `connect.js` calls `integration_set`, so it must keep working; keep `integration_set` and make it also write the new account row (or deprecate in the final cut-over PR) |
| Audit | ADOPT engine `integration_audit` (immutable) additively; keep `integration_config_versions` | live has no action audit | low |
| Outbox | EXTEND `notify_outbox` in place: add `account_id`, `business_id/org_unit_id`, `idempotency_key`, `state`-compatible blocked statuses, `lease_until`/keep `claimed_at`, `scheduled_for`, `consent_checked_at`, `is_dry_run`; widen status/channel CHECKs; add quiet-hours + cap + consent re-check to `notify_enqueue`/`notify_outbox_claim` | UI and CRM functions (`notify_scan`, `x1_health`, `xc_summary_compose`, `_crmb_*`) read this table; replacing it breaks them | `notify_outbox` has 0 rows so schema change is cheap, but `notify_scan` is an 11.7k-char function that writes it (NOT audited) and must be regression tested; status CHECK change affects `notify_outbox_summary` |
| Consent | EXTEND live consent (`notify_optin` + `crm_contact_prefs` + `crm_consent_events`) rather than adopt `integration_consent_v1` (contact_ref hash); optionally add a view mapping customer to contact_ref; add `email`/`facebook` channels | live consent is richer (DNC, group DNC, evidence log, import) and CRM depends on it | identity mismatch (customer_id vs contact_ref); a second consent store would let the two disagree, so the engine's consent table must NOT be a second source of truth |
| Quiet hours | wire `_crmb_in_quiet` (rule keys) into `notify_enqueue` / claim; default null rules = OFF; owner must set them | function exists | behavior change on sends when rules get set; null defaults mean no effect until the Owner decides |
| Payments | EXTEND `payment_intents` and `payment_webhook_log` (add `account_id`, `idempotency_key`, `expires_at`, `refunded_amount`, `needs_review` state, `ledger_ref`, `signature_status`); port A039 amount-match, ledger link and refund RPC into live RPCs under new names, keep `payment_webhook_receive` signature stable or add `_v2` | tables have 0 rows; `payment_recon`, `xb_pay_tieout`, `integrations.js` read them | HIGH: ledger/finance coupling; Owner go/no-go required per BUILD_PLAN P3; `payment_intents_status_check` change; `refunded` semantics |
| Delivery | EXTEND `delivery_jobs` (courier account, consignment id, courier state) and adopt `delivery_status_map_v1`; A040 `delivery_parcel_v1` would duplicate `delivery_jobs` | `delivery_jobs` is wired to `online_order_deliver`, `xb_riders`, `UNIQUE(order_id)` | one-job-per-order assumption; COD receivable posting is a finance change |
| AI | EXTEND: keep `ai_providers`, `ai_calls`, `ai_check`, `ai_log`, `ai_agent_grants`; ADOPT only the reserve-before-call pattern (atomic budget) and business scoping if multi-business AI budgets are wanted | live AI model is more complete than A040's (`ai_agent_grant_v1`, `ai_budget_v1`, `ai_call_v1`) | do not run two AI gates; `ai_redact_v1` is not a substitute for live `ai_redaction_rules` |
| Webhook log | ADOPT generic `integration_webhook_event_v1` for messaging/courier/inbound; keep `payment_webhook_log` and have it view-unioned or dual-written during transition | payments log already good | duplicate stores |
| Business scoping | DECIDE first (Q1-Q3). Live uses `org_units` + `org_scope_on` + `_my_biz123()` + `_m132_own()`. The engine uses `tenant_id` + `business_id` + `can_manage()` - these helper functions do not exist in live (`c10_demo.can_manage`, `c10_demo.actor_uid` are demo-schema functions) | an engine migrated as-is would not authorize correctly against live roles | HIGH: must be re-mapped to `is_owner()`/`_my_biz123()`, and verified with signed-JWT tests on staging, as CONTRACT section 7 requires |

Cross-cutting migration risks:
- The engine SQL is explicitly `DISPOSABLE ... NEVER execute on IMG-ERP-SG`; it targets schema `c10_demo` with `bigint` tenant/business ids, while live uses `uuid` customers/sales, `integer` location ids and `org_units.id bigint`. Types differ (customers, sales, intents use uuid/integer in live).
- Live drift: `_union_fn_backup`, `_union_fn_expected` and `loc_split_backup_*` tables exist; historical migrations are not in Git (BUILD_PLAN risk 4), so any live DDL must be re-read from catalog immediately before apply.
- `notify_scan` (11.7k chars) and `x1_health` also touch outbox/registry and were NOT audited here.
- Behavior change risk once `notify_sms_on` is turned on: adding blocks for quiet hours/caps changes staff-visible results (exceptions vs blocked rows).

## 5. Questions for the Owner (exact)

1. Is each Islamia "business" the same thing as a row in `org_units` (4 rows), or in `legal_entities` (2 rows), or `business_profiles` (1 row)? Which of these should own an integration account (WhatsApp number, bKash merchant, courier account)?
2. Should integration accounts be per business (each business uses its own provider account) or one shared account for all businesses? (CONTRACT section 8 says per business unless you decide to share.)
3. Is the multi-business scope switch `org_scope_on` going to be turned on before any port goes live? Today it is off, which makes every live business-scope check a no-op.
4. Quiet hours: what hours (Asia/Dhaka) should apply to customer messages, and should order-status (transactional) messages be exempt or also blocked? Today no quiet-hours rule is set (`crm_quiet_from/to` are empty), and the order-message path (`notify_enqueue`) ignores them.
5. Who may queue customer messages and change consent: owner only (the engine rule), or also staff holding the `customer_manage` grant (live today)? Who may read the outbox (it contains customer phone numbers and message text)?
6. Rate limits: what daily cap per channel and per customer (the engine default is 200 per account per day, no per-customer cap), and should marketing blasts need your approval per campaign?
7. Consent basis: is order-status messaging allowed without an explicit opt-in (documented basis), or must every message have a `notify_optin` row as live requires today? Should email and Facebook get opt-in records too (live supports only sms and whatsapp)?
8. Webhook signature: payments webhooks will be verified in a server function (Edge Function) that then passes a `signature_ok` flag to the database. Do you accept that the database trusts that flag from the owner/ops role, or do you want the secret kept for verification inside the database as well?
9. Payments: when a provider reports success with an amount different from the order, do you want it held as `needs_review` for you (engine behavior) rather than marked paid (live behavior today)? Who approves refunds and what limit, if any?
10. Ledger: when an online payment succeeds, should it automatically create the `sale_payments`/ledger entry (engine behavior), or stay a separate manual link as today? Finance changes need your go/no-go.
11. Migration strategy: do you accept "extend the live tables and keep existing RPC names working" (recommended), or do you prefer a clean new set of engine tables with a one-time cut-over? Is there a maintenance window and a backup you want before any live schema change?
12. Registry: may `integration_registry.enabled` be forced to require `connected` and a passed test (today you can flip it on directly)? May we retire the `dry_run`/`read_only` booleans in favor of one `mode` (off, dry_run, live)?
13. Courier: is one delivery job per order still correct if a courier is added (today `delivery_jobs.order_id` is UNIQUE)? Which courier first (Pathao, Steadfast, RedX) and who books COD remittance?
14. AI: global provider budgets are fine, or do you want a monthly AI budget per business? May AI prompts ever include customer names or phone numbers (today `data_sharing` is `none`, redaction rules exist but no gateway applies them)?
15. Rocket: no live registry row exists; keep it as a manual capture method until a provider route is confirmed?

## 6. Not verified (NOT CHECKED)

- Bodies of `notify_scan`, `x1_health`, `xc_summary_compose`, `crma_*`, `social_publish_claim`, `online_order_deliver`, `payment_recon`, `payment_recommendation`, `ai_log`, `ai_provider_save`, `_ai_month_use`, `_crmb_consent_*` (except those listed as read), `_crmb_prefs_set`, `_crmb_group_ids`, `_i62_phone`, `_my_biz123`, `_business_of_loc123`, `_loc_vis123`, `_acct_manage`, `_client_lock`.
- Triggers on integration tables (immutability, audit) and any scheduled jobs (pg_cron) that might call claim/report: not listed.
- Live Edge Functions (only `scan-extract` known from AUDIT); no list queried this time.
- Whether `notify_optin.org_unit_id` is set by a trigger or by the RPC (the RPC `notify_optin_set` does not set it).
- Behavior with `org_scope_on=true`: only the policy and helper definitions were read, not exercised.
- This document makes no claim that anything is STAGING VERIFIED. Engine SQL (A038-A040) was read for structure only and not executed.
