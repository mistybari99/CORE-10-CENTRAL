# C10-A038 Integration Ports core (P1) — build note

Status: BUILT + TESTED IN ISOLATION (disposable PostgreSQL). NOT applied to production. NOT integrated into the app.
Implements P1 of `design/integrations/BUILD_PLAN.md` (design is on PR #17). No provider adapters, no network calls, no keys.

## What exists
- `scripts/c10_a038_integration_core_v1.sql` (schema `c10_demo`)
  - Provider catalog: 20 ports in 5 families (messaging: whatsapp, facebook, sms, email; payments: bkash, nagad, rocket, gateway, card, manual_pay, cod; delivery: pathao, steadfast, redx, own_rider; ai: anthropic, gemini, openai_compat, local_rules; storefront). Each lists only the NAMES of fields the Owner must supply.
  - `integration_account_v1`: per business, always created OFF. `mode<>'off'` needs `connected`; `live` needs a passed test (30 days). Stores a secret REFERENCE only; secret-looking keys in `public_config` are rejected by CHECK.
  - Consent-gated, idempotent outbox: blocks when port off / no consent (opt-out wins) / quiet hours (22:00-08:00 Asia/Dhaka default) / daily cap. dry_run rows are flagged and never "sent".
  - Worker functions: lease-based claim (SKIP LOCKED), exponential backoff (30s, 60s, ...), permanent errors fail at once, stale reports cannot change a final state.
  - Webhook log: bad/missing signature or off port is stored but never applied; unique per event.
  - Kill switch (one call turns every port of a business OFF); immutable audit and webhook log.
  - Owner-only (tenant owner / business owner) RLS reads; no DML grants; all writes via functions.
- `tests/c10_a038_integration_core_e2e.sql` - roles: owner, business owner (own vs sibling), manager, investor, staff, revoked, other tenant, platform operator, anon. Mutation-checked locally: removing the consent gate, the live-needs-test rule, or the off-port claim guard makes the test fail.
- `.github/workflows/core10-a038-integration-core-ci.yml` (PG17).

## Evidence
- Local PostgreSQL 16: PASS. CI (PG17): see PR checks.

## Not done (honest limits)
Adapters (P2-P5), settings UI (P6), real Vault/secret storage, real Supabase Auth users, parity with live `integration_registry`/`notify_outbox` (P0 parity read not done), production apply (Class H: Owner go/no-go + rollback required).

## Owner later
Nothing now. When ready: open provider accounts, paste keys in the future settings screen, Test, dry-run, then Go live.
