# Integration Ports — Adapter Contract

## বাংলা সারাংশ (মালিকের জন্য)

- এখন কোনো টাকা খরচ নেই, কোনো অ্যাকাউন্ট বা চাবি (key) লাগবে না।
- প্রতিটি বাইরের সংযোগ (AI, ফেসবুক, ওয়েবসাইট, হোয়াটসঅ্যাপ, এসএমএস, ইমেইল, বিকাশ/নগদ/রকেট, অনলাইন পেমেন্ট ও কার্ড, কুরিয়ার) একটি "পোর্ট" — ডিফল্টে সবই বন্ধ (OFF)।
- পরে আপনি শুধু ফোনে "সেটিংস > সংযোগ" খুলবেন: "কানেক্ট" চাপুন, চাবি পেস্ট করুন, "টেস্ট" চাপুন, ঠিক থাকলে "চালু" করুন। কোড বদলাতে হবে না।
- চাবি কখনো GitHub বা ব্রাউজারে থাকবে না; শুধু সার্ভারের গোপন ভল্টে থাকবে। অ্যাপের ডাটাবেসে শুধু একটি "রেফারেন্স" নাম থাকবে।
- শুধু মালিক সংযোগ চালু/বন্ধ করতে পারবেন। কর্মীরা শুধু অনুমতি পাওয়া কাজ (যেমন বার্তা পাঠানো) করতে পারবে।
- গ্রাহকের সম্মতি ছাড়া বার্তা যাবে না; রাতে (শান্ত সময়ে) যাবে না; দিনে সীমার বেশি যাবে না।
- পেমেন্ট: কার্ড নম্বর আমরা রাখব না। অনলাইন পেমেন্ট প্রোভাইডারের নিজস্ব পেজে হবে। প্রতিটি পেমেন্ট হিসাবের খাতার (ledger) সাথে মেলানো হবে।
- AI: চাবি সার্ভারে, মাসিক খরচের সীমা থাকবে, ফোন নম্বর/নাম ঢেকে (redact) তারপর পাঠানো হবে।
- যেকোনো সময় এক বোতামে সব বন্ধ করা যাবে (kill switch)।
- বাংলাদেশের প্রোভাইডারের নাম নিচে দেওয়া আছে; যেগুলোর শর্ত/ফি/API আমি অফলাইনে যাচাই করতে পারিনি সেগুলো "verify at integration time" চিহ্নিত — সংযোগের সময় যাচাই হবে।

---

# English technical contract

Status: DESIGN ONLY. Nothing here is built, tested or released. Existing live objects are referenced in `AUDIT.md`; new objects below are proposals to be implemented via reviewed PRs and migrations under the high-risk release rules in CLAUDE.md (no live apply without Owner go/no-go).

## 1. Principles

1. Off by default. A port with no connected account, or `enabled=false`, cannot send, receive or charge. The off-state is enforced in the database and in the server function, not only in the UI.
2. Provider-agnostic core, thin adapters. App code talks to the core (`enqueue message`, `create payment intent`, `create parcel`, `ai.complete`); only an adapter knows a provider's wire format.
3. Secrets never in Git, the browser, the database or logs. The DB stores a reference only.
4. Everything idempotent and auditable. Every outbound action has an idempotency key; every inbound event is logged with signature status before it is acted on.
5. Dry-run first. Each account has `mode`: `off` -> `dry_run` (adapter builds the request, logs it, does not call the provider) -> `live`.
6. Extend what exists (`integration_registry`, `notify_outbox`, `payment_intents`, `payment_webhook_log`, `ai_providers`, `delivery_jobs`) instead of replacing it; migration compatibility is a P1 task.

## 2. Channel families and adapter interfaces

Adapters run only inside server functions (Supabase Edge Functions or equivalent). Interfaces are TypeScript-style pseudocode; field names of providers are NOT specified here (verify at integration time).

Common:

```
interface Adapter {
  family: 'messaging'|'payments'|'delivery'|'ai'|'storefront'
  provider: string                      // registry code
  capabilities(): string[]
  validateConfig(cfg): Result           // shape only, no network
  test(account): Result                 // cheapest harmless provider call (auth check)
  health(account): Result
}
```

### 2.1 Messaging (whatsapp, sms, email, facebook/messenger)

```
send(account, msg:{ idempotencyKey, to, templateCode, params, body?, channel }) -> {providerRef, state}
parseInbound(rawBody, headers) -> {verified:boolean, events:[InboundEvent]}
parseStatus(rawBody, headers)  -> {verified, updates:[{providerRef, state, at, error?}]}
```
States: `queued -> claimed -> sent -> delivered -> read` (where provider reports), terminal failures `failed`, `blocked_no_consent`, `blocked_quiet_hours`, `cancelled`, `expired`.

### 2.2 Payments (bkash, nagad, rocket, gateway, card, cod)

```
createIntent(account, {idempotencyKey, amount, currency, reference, returnUrl}) -> {providerRef, redirectUrl|null}
verifyWebhook(rawBody, headers) -> {verified, event:{eventId, providerRef, type, amount, status}}
queryStatus(account, providerRef) -> {status, paidAmount}     // polling fallback for missed webhooks
refund(account, {providerRef, amount, idempotencyKey, reason}) -> {refundRef, state}
```
`cod` has no provider: it is a payment method whose "settlement" is the rider/courier collecting cash (see delivery).
Intent states: `created -> redirected -> pending -> paid | failed | cancelled | expired`, then `refund_pending -> refunded | partially_refunded`, and `disputed`/`needs_review` for amount mismatch.
Today's manual flow (`xb_paycapture`, `xb_paysms`) stays as the fallback and as a `manual` provider that follows the same states.

### 2.3 Delivery (courier)

```
createParcel(account, {idempotencyKey, deliveryJobId, recipient, address, codAmount, weight?}) -> {consignmentId, trackingUrl?}
track(account, consignmentId) -> {state, events[]}
parseWebhook(rawBody, headers) -> {verified, updates[]}
cancel(account, consignmentId) -> Result
```
Map provider statuses onto the existing `delivery_jobs.state`; COD collected by the courier is recorded as a receivable until the courier remits (reconciled like a payment).

### 2.4 AI

```
complete(account, {agentCode, redactedInput, maxOutputTokens, idempotencyKey}) -> {text, usage:{in,out}, costEstimate}
```
Only reachable through the AI gateway function (section 8). Existing `ai_providers` kinds (anthropic, openai_compatible, gemini, custom_http, local_rules) become adapters; `local_rules` stays the always-on, no-network fallback.

### 2.3b Web storefront

Not a provider adapter but a published surface: `web_site_config`, `web_catalog_v2`, `web_checkout_submit` (public, anonymous, rate limited) produce `online_orders`; payment is created through 2.2; notifications through 2.1. A custom domain is an Owner/hosting task. Storefront port states: `closed` (default) -> `preview` -> `live` (`web_admin_go_live`).

## 3. Real Bangladesh provider options (factual, unverified details flagged)

Names only; endpoints, fields, fees, onboarding requirements and sandbox availability are all "verify at integration time". No endpoint or field is asserted in this repo.

| Channel | Options |
|---|---|
| WhatsApp | Meta WhatsApp Business Platform (Cloud API); BSP resellers exist. Pre-approved message templates and a verified business are generally required for business-initiated messages (verify). |
| Facebook / Messenger / Instagram | Meta Graph API with a Page access token; webhook verification via verify token and app secret signature (verify exact header/algorithm). |
| SMS | A Bangladesh bulk-SMS gateway with BTRC-compliant masking/non-masking sender IDs. Several local vendors exist; choose one at integration time (verify; do not hardcode). |
| Email | Resend, or plain SMTP (any provider), or a transactional service such as Amazon SES; needs a sending domain with SPF/DKIM (verify). |
| bKash | bKash Tokenized Checkout (merchant account required; verify product name/version). |
| Nagad | Nagad merchant payment gateway (merchant onboarding required; verify). |
| Rocket | Dutch-Bangla Bank Rocket merchant payments; integration route unclear offline (verify). Until then Rocket stays a manual capture method. |
| Gateway + cards | SSLCommerz and AamarPay are widely used aggregators that offer hosted checkout covering cards and mobile wallets (verify fees, settlement, IPN/validation flow). |
| Courier | Pathao Courier, Steadfast, RedX (each has a merchant API; verify availability, auth and COD terms). |
| AI | Anthropic, Google Gemini, any OpenAI-compatible endpoint (already modelled in `ai_providers`). |
| Hosting/domain | Current static host plus a custom domain; Owner purchases later. |

## 4. Data model

Reuse names that exist; `+` marks proposed additions (a migration PR must reconcile with live tables, AUDIT section 3).

- `integration_provider` + (registry of supported providers, global, read-only to tenants): `code`, `family`, `label_bn`, `label_en`, `adapter_version`, `capabilities`, `needs_fields` (names of the settings the owner must supply, no values).
  Today's `integration_registry` plays this role plus per-account state; P1 decides whether to split it.
- `integration_account` + (per business): `id`, `business_id`, `provider_code`, `mode` (off/dry_run/live), `status` (not_connected/connected/test_failed/suspended/expired), `secret_ref` (name only, e.g. `ib_<business>_<provider>_<version>`), `public_config` (non-secret: sender name, page id, shop id), `monthly_cap`, `rate_per_min`, `quiet_hours`, `last_test_*`, `config_version`, `created_by`, `updated_by`. Constraint: `mode='live'` requires `status='connected'` and a passed test within N days.
- `integration_audit` + (append-only): `account_id`, `actor`, `action` (connect/test/enable/disable/rotate/secret_ref_changed/kill), `before`/`after` (no secret values), `at`. Extends `integration_config_versions`.
- `outbox` (extends `notify_outbox`): add `account_id`, `business_id`, `idempotency_key` UNIQUE per account, `state`, `attempts`, `max_attempts`, `next_try_at` (exponential backoff with jitter), `lease_until` (claim lease), `last_error_code`, `provider_ref`, `consent_checked_at`, `scheduled_for`.
- `inbox` (extends `inbound_messages`): `account_id`, `provider_event_id` UNIQUE per account, `received_at`, `processed_at`, `state`.
- `webhook_event` + (generalises `payment_webhook_log`): `account_id|provider_code`, `event_id` UNIQUE per provider, `signature_status` (ok/bad/missing/not_applicable), `raw_payload_ref` (payload minus secrets; PII-minimised), `received_at`, `processed_at`, `result`, `error`. Rejected-signature events are stored but never applied.
- `payment_intent` (extends `payment_intents`): add `account_id`, `idempotency_key`, `expires_at`, `refunded_amount`, `ledger_ref` (link to `sale_payments`/ledger entry), `reconciliation_state`.
- `payment_refund` + (extends `order_refunds`): `intent_id`, `amount`, `state`, `provider_ref`, `approved_by`.
- `consent` (existing `notify_optin`, `crm_consent_events`): per customer and channel, with source and timestamp; opt-out wins; STOP keywords on inbound set opt-out.
- `limits` : per account `rate_per_min`, `daily_cap`, `monthly_cap`, `monthly_budget_money` (AI/SMS), counters in a usage table with atomic increment.
- `delivery_job` (existing) + `courier_account_id`, `consignment_id`, `courier_state`.

All tenant tables carry `business_id` (and `org_unit_id` where the repo already uses it).

## 5. Owner settings flow

Owner-only screen (lazy module; Bangla first) per port:

1. List shows each port with state badge: `বন্ধ` / `ডেমো (dry-run)` / `চালু`.
2. "Connect": form shows only `needs_fields` for that provider. Secret fields are write-only inputs.
3. Submit sends the secret directly to a server function over HTTPS; the function stores it in Vault/Edge secret and writes only `secret_ref` to the DB. The browser never receives the secret back (shows only "saved, ends with ****" derived server-side, last 4 characters at most, or nothing).
4. "Test": server calls adapter `test()`; result recorded (`last_test_ok`, redacted detail). Failure shows a plain Bangla message and keeps mode `off`.
5. "Enable": choose `dry_run` first; "go live" requires a passed test, explicit confirm, and for payments/messaging a one-time confirmation of limits and quiet hours. Each step audited.
6. "Disconnect/rotate": deletes or replaces the secret; account returns to `off`.
7. Global kill switch: one action sets all accounts `off` (extends `ai_pause_all`); staff UI sends degrade to manual click-to-chat (existing `wa.me`/`sms:` flow).

## 6. States and failure handling

- Account: `not_connected -> connected -> (test_failed|suspended|expired) ; mode off|dry_run|live`.
- Outbox retry: transient errors (network, 5xx, rate-limited) retry with exponential backoff and jitter up to `max_attempts`, then `failed` and a notification to the owner; permanent errors (invalid number, no consent, template rejected) go straight to `failed`/`blocked_*` with no retry. Claim uses a lease so a crashed worker's rows are retried; provider idempotency key is passed where the provider supports it (verify), otherwise send-then-record is guarded by `idempotency_key` UNIQUE and a "sent but unrecorded" reconciliation.
- Circuit breaker: N consecutive failures flips the account to `suspended` and alerts the owner; auto-recovery only by owner re-test.
- Inbound: verify signature first; store event always; process at most once per (`provider`,`event_id`); out-of-order events must not move a state backwards.
- Missed webhooks: payments and courier have a scheduled `queryStatus`/`track` poll for non-terminal items older than a threshold.
- Degraded mode: when a port is off or failing, the UI falls back to the manual flows that exist today.

## 7. Tenancy and RLS principle

- Every integration row is scoped by `business_id`; a business can never read or use another business's account, outbox, events or secret_ref.
- Management (connect, test, enable, disable, rotate, change limits) = owner role only, enforced in RPCs (security definer, checking role and business) and by RLS; no direct table writes from the client.
- Staff may only invoke permitted actions via RPCs (e.g. `notify_enqueue` for a template they are allowed to use, create a payment intent for a sale in their location). They never read `secret_ref`, raw payloads or other staff's PII beyond existing masking rules.
- Webhook endpoints are unauthenticated by nature: they resolve the account from an unguessable per-account path token plus signature verification, run as a service role in a function that only calls narrowly scoped RPCs.
- Signed-JWT tenant isolation tests are required (protocol: isolated SQL tests do not prove this) before any live enable.

## 8. Secret handling

- Store in Supabase Vault or Edge Function secrets (service-role access only). `integration_account.secret_ref` holds the name.
- Never in Git (CI secret scan on PRs), never in the browser/localStorage, never in logs, errors, `public_config`, audit `before/after`, or AI prompts.
- Write-only from the UI; rotation creates a new version and retires the old; `webhook_rotations` records rotations.
- Per-business keys (each business uses its own provider account) unless the Owner explicitly shares one.
- Webhook shared secrets are separate from API keys.

## 9. Payments rules

- No card numbers, CVV or wallet PINs ever touch our servers, DB or logs: hosted/redirect checkout only (gateway or wallet page); we store `provider_ref`, status, amount, last-4/brand only if the provider returns it.
- Amount, currency and order are fixed server-side when the intent is created; the webhook/validation result must match the intent amount, else `needs_review`, never auto-paid.
- Webhook signature (or provider server-side validation call where the provider has no signature; verify which) is mandatory; bad signature -> logged, ignored.
- Mark paid only from a verified server event or a server-side status query, never from the browser return URL alone.
- On `paid`, write the sale payment/ledger entry in one transaction with the intent update; duplicate events are no-ops (idempotency).
- Daily reconciliation (`payment_recon`, `xb_pay_tieout`, `xb_pay_statement_import`) compares provider statement/settlement to ledger; unmatched items open exceptions (`pay_request_exceptions` pattern). Gateway fees and settlement delays are booked as per Owner accounting rules (finance changes need Owner decision).
- Refunds: owner/approver only, partial allowed up to the paid amount, full audit, asynchronous state; refund via provider API where supported (verify) else manual with recorded reference.
- Existing manual capture (staff-recorded bKash/Nagad payments with approval) remains and uses the same states.

## 10. Messaging rules

- Consent: send only if `consent` for that customer and channel is opted in (transactional order-status messages may follow a documented basis; owner decision); opt-out is immediate and global per channel.
- Templates: reuse `notify_templates`, `tpl_registry.js`, `tpl_msgs.js`; one template code maps to per-provider wording (WhatsApp templates need provider approval: verify). Bangla and Unicode length handled per channel.
- Quiet hours (default e.g. 21:00-08:00 Asia/Dhaka, owner editable) defer non-urgent sends via `scheduled_for`.
- Rate limits: per account per minute/day/month and per recipient (e.g. max N per day); marketing blasts additionally require owner approval per campaign.
- No message body with secrets; log metadata, not full content, beyond the existing outbox body.
- Inbound STOP/unsubscribe keywords (Bangla and English) set opt-out.
- BTRC/Meta policy compliance (sender registration, business verification, opt-in proof): verify at integration time.

## 11. AI rules

- Provider call happens only in the AI gateway function; key lives in secrets; browser never calls a provider.
- Gateway order: kill-switch check -> `_ai_can_use` (agent grant) -> budget check (`monthly_token_budget`, `monthly_money_budget` from `ai_providers`) -> redaction (`ai_redaction_rules`: phone, names, addresses, amounts as policy says) -> call with timeout and `max_output_tokens` -> log to `ai_calls` (hashes/metadata, usage, cost) -> return. Budget exceeded -> fall back to `local_rules`, notify owner.
- `data_sharing` stays `none` until the Owner explicitly opts in per provider.
- AI never executes money, stock or costing writes directly; it produces `ai_suggestions` that a human approves (existing pattern).
- Prompt/response retention and redaction of logs follow `ai_redaction_rules`; no customer data in eval cases.

## 12. Open items (verify before build)

Read live RPC bodies for consent/quiet-hours/RLS behavior; decide single- vs multi-business registry; confirm `rocket` approach; confirm every provider fact in section 3 against current official docs at integration time.
