# Integration Ports — Build Plan

Goal: every external connection exists as an OFF-by-default port; the Owner later only connects an account and pastes a key. No cost and no keys now.

Rules for all packages: one implementer per branch; each package its own branch and PR; touch only the files it owns (listed); never edit `CURRENT_HANDOFF.md` outside the handoff process; any live Supabase change (schema, RLS, RPC) is high-risk under CLAUDE.md: SQL is committed to Git first, tested in isolation, then staging/real-auth verification, backup/rollback plan and an explicit Owner go/no-go before live apply. Frontend modules ship as lazy modules and are inert until a port is enabled. Record status honestly (BUILT / TESTED IN ISOLATION / INTEGRATED / STAGING VERIFIED / RELEASED).

## Dependency order

```
P0 (read-only prep) -> P1 core -> P2 messaging ┐
                          ├────> P3 payments   ├-> P6 owner settings UI (can start with mock data after P1 contract)
                          ├────> P4 delivery   │
                          └────> P5 AI gateway ┘
```
P2, P3, P4, P5 are independent of each other once P1's interfaces are merged. P6 builds against the P1 RPC signatures (stubbed) so it can start in parallel and wire up as packages land.

## P0 — Parity read (small, first)

Read live RPC bodies and RLS policies read-only (`notify_enqueue`, `notify_outbox_claim/report`, `payment_webhook_receive`, `integration_set`, `ai_check`, consent RPCs) and write `design/integrations/PARITY.md`. Resolves AUDIT section 3 (consent enforcement, business scoping, registry per business). Files owned: `design/integrations/PARITY.md`. Tests: none (evidence only). Owner later: nothing.

## P1 — Core tables, registry, outbox/inbox, webhook log, audit

Files owned: `supabase/migrations/*_integration_core.sql` (new; or the repo's established SQL location, decide in P0), `tests/sql/integration_core_*.sql`, `design/integrations/P1_NOTES.md`.
Scope: `integration_account` (secret reference only), `integration_audit`, generalised `webhook_event`, outbox/inbox extensions with `idempotency_key`, retry/backoff and lease columns, limits/usage counters, seed `courier`, `rocket`, `payment_gateway`, `card`, `email`, `messenger` provider rows; all default `mode=off`; RLS owner-only management; RPCs for connect/test-record/enable/disable/kill-switch; backward compatible with existing `integration_registry`, `notify_outbox`, `payment_intents`.
Tests required: isolated SQL fixtures for constraints (live requires connected+tested), idempotency uniqueness, owner-only RLS, cross-business denial, kill switch; later signed-JWT tests on staging.
Owner later: approve migration go/no-go; nothing else.

## P2 — Messaging adapters (WhatsApp, SMS, email, Facebook/Messenger)

Files owned: `server/integrations/messaging/**` (adapter interface, `whatsapp.*`, `sms.*`, `email.*`, `facebook.*`, `dryrun.*`), `server/functions/outbox-worker/**`, `server/functions/webhook-messaging/**`, `tests/integrations/messaging/**`.
Scope: sender worker claiming from outbox with lease, backoff, consent/quiet-hours/rate-limit gates; webhook receiver with signature check; dry-run adapter default; reuse `notify_templates`/`tpl_registry`.
Tests: adapter contract tests against recorded fake responses (no network), retry/backoff unit tests, consent-block tests, signature-verification tests, idempotent redelivery.
Owner later: choose and open accounts (Meta business/WhatsApp number, a BD SMS gateway account with sender ID, a sending domain for email, Facebook Page), paste keys in settings.

## P3 — Payments state machine

Files owned: `server/integrations/payments/**` (intent state machine, `bkash.*`, `nagad.*`, `rocket.*`, `gateway.*`, `manual.*`), `server/functions/payments-webhook/**`, `server/functions/payments-poll/**`, `supabase/migrations/*_payments_ledger_link.sql`, `tests/integrations/payments/**`.
Scope: intent states, amount-match rules, verified-event-only paid transition, ledger link in one transaction, refunds, reconciliation hooks into `payment_recon`/`xb_pay_tieout`, manual provider mirroring today's capture flow.
Tests: state-machine property tests (no backwards moves, duplicate events no-op), mismatch -> needs_review, bad signature ignored, refund bounds. Ledger/finance changes are high-risk: Owner go/no-go required.
Owner later: merchant accounts (bKash, Nagad, gateway such as SSLCommerz/AamarPay), paste credentials, approve fee/settlement accounting treatment.

## P4 — Delivery / courier

Files owned: `server/integrations/delivery/**` (`pathao.*`, `steadfast.*`, `redx.*`, `ownrider.*`), `server/functions/delivery-webhook/**`, `server/functions/delivery-poll/**`, `supabase/migrations/*_delivery_courier.sql`, `tests/integrations/delivery/**`.
Scope: create parcel, track, status mapping to `delivery_jobs.state`, COD remittance receivable, own-rider provider as the default that keeps today's flow.
Tests: status-mapping tables, COD reconciliation, idempotent create.
Owner later: courier merchant account(s) and keys; confirm COD terms.

## P5 — AI gateway

Files owned: `server/functions/ai-gateway/**`, `server/integrations/ai/**` (`anthropic.*`, `gemini.*`, `openai_compat.*`, `local_rules.*`), `tests/integrations/ai/**`.
Scope: kill switch, agent grant, budget cap, PII redaction from `ai_redaction_rules`, timeout/max tokens, `ai_calls` logging, fallback to `local_rules`; no client-side provider calls.
Tests: redaction golden tests (phone/name/address), budget exhaustion fallback, no secret in logs, provider failure fallback.
Owner later: choose provider, set monthly budget, paste key, opt in to `data_sharing`.

## P6 — Owner settings UI (lazy modules, Bangla first)

Files owned: new files only, e.g. `integrations_ui/ports_list.js`, `ports_connect.js`, `ports_test.js`, `ports_audit.js`, matching CSS and `tests/ui/ports_*`; one-line registration is the only touch of shared files and is done last by a single agent (`lazy.js`/`ia.js` entry), coordinated outside the package. Does not edit `connect.js` or `integrations.js` until the final cut-over PR.
Scope: port list with state badges, connect form driven by provider `needs_fields`, write-only secret fields posting to a server function, test, enable/dry-run/live, disconnect/rotate, kill switch, audit view; owner-only, phone-first, large touch targets.
Tests: render/interaction tests with mock RPCs, role gating (non-owner sees nothing), no secret echoed into DOM/storage, Bangla copy review.
Owner later: test each screen on his phone.

## What the Owner must do later (summary)

Per channel when ready: open the provider account, complete provider verification (business/merchant onboarding, sender-ID registration, domain DNS), paste credentials in the owner settings screen, press Test, start in dry-run, then Go live. Pay provider fees only then.

## Biggest risks

1. Money/ledger coupling (P3): wrong "paid" transitions or double posting; mitigated by verified-event-only, idempotency, reconciliation, Owner go/no-go.
2. Tenant/RLS leakage and secret exposure: current registry has no business column; mitigated by P0 parity read, signed-JWT tests, secret references only.
3. Unverified provider facts and onboarding lead time (BTRC sender registration, Meta template approval, merchant KYC); mitigated by flagging "verify at integration time" and keeping dry-run/manual fallbacks.
4. Live DB drift: historical migrations missing from Git; mitigated by P0 and read-only parity before any migration.
5. Spam/abuse and consent violations when messaging goes live; mitigated by DB-enforced consent, quiet hours, rate limits, owner approval for blasts.
6. Agent file collisions; mitigated by the file-ownership split above and a single final registration step.
