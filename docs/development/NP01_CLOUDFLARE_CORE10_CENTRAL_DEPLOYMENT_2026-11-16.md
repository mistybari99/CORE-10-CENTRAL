# NP01 — Owner-selected Cloudflare core10-central and Supabase staging target
Date: 2026-11-16
Owner instruction: Supabase project ref `rhrqhbyzrhaafynfhdaf`; create Cloudflare project `core10-central` and deploy there. This supersedes the previous *target-undiscovered* inventory assessment, not the security/release gates.

## Cloudflare: DEPLOYED Level 1 preview (not signed ERP)
- Account: `382a468cf1bde26b7b3c480acc409732` (Cloudflare connection authorized).
- NEW **Workers project/script**: `core10-central` (not Pages). It is a separate Worker from existing `trillionaire-me`; existing Worker untouched.
- Deployment ID: `15084307-6cd9-4956-94c2-5d60f3901465`; version `b34943c8-b29a-417a-b75c-3908041862a9`; account API confirms 100% of traffic routed to this version; deployment source: API; created `2026-11-16T13:03:15.088209Z`.
- Cloudflare `workers.dev` route readback: `enabled: true`, `previews_enabled: false`; account subdomain readback: `mistybari99`. Expected public URL: `https://core10-central.mistybari99.workers.dev/`.
- **HTTP browser smoke NOT independently verified:** URL could not be fetched from current tool/network environment. Successful API deploy/route is not HTTP smoke evidence.
- Published exactly the existing `preview/` Level 1 isolated Worker modules from ChatGPT NP01 source branch `build/chatgpt-np01`:
  - `preview/worker.mjs` — Git blob `ef30389800102fce1365ee049930bb1384a1dada`
  - `preview/operations-snapshot.mjs` — Git blob `d46f724968e6bb69bde19863eeae310b6fe99e8a`
  - `preview/build01-build02a.mjs` — Git blob `a07e4af78c094e6b66576ebccf571f8d78e86e28`
- This is a synthetic **GET/HEAD-only** preview. The Worker CSP has `connect-src 'none'`; no bindings, Supabase keys, write endpoints or real financial/stock operations. It uses pinned GitHub SHA assets for older demo snapshots. It is NOT current trunk signed CORE10 release, nor does it deploy incomplete NP01 schema.
- First verification: Cloudflare API script upload `success: true`, latest deployment 100%, subdomain route `enabled: true`. Browser/public smoke, actual signed GoTrue, controls, owner identity and Level 2 remain outstanding.

## Supabase: correct target identified; this connector cannot access it
- Owner-selected staging ref: `rhrqhbyzrhaafynfhdaf`.
- Shared Coordination Board B-017 (Claude lane) records project `CORE-10-CENTRAL` and staged migrations **0001–0012** from Claude trunk, synthetic/no auth users, no public schema changes. This is **board evidence, NOT independently verified through NP01's Supabase connector**.
- Supabase connector `list_projects` only exposes protected legacy `IMG-ERP-SG` ref `kbuhnpqooycqbzrfejcs`. `get_project(rhrqhbyzrhaafynfhdaf)` returns `You do not have permission to perform this action`.
- Do not create a duplicate Supabase project, guess a credentials path, apply 0013–0016, or mutate legacy. Request user to authorize/reconnect this Supabase project through ChatGPT Settings > Plugins > Supabase to account/org with access. Reverify project ref/schema and migration ledger after connection before applying any new SQL.
- **Coordination:** Board B-018 (Claude) already claims staged signed demo users, API exposure and trunk Cloudflare preview. NP01 must NOT take ownership of B-018 or deploy Claude-trunk migrations; Claude must coordinate before replacing the new `core10-central` Worker or wiring signed staging. Pending Owner Control DEC-08 B-010.
- Distinguish GitHub push, Cloudflare preview publish, and Supabase schema apply as three separate operations; each gets exact evidence and gates.
- Protected legacy project, main branch, and prior preview kept untouched.

## Evidence and next check
- GitHub lane: only `build/chatgpt-np01`; keep one Draft PR #107 into trunk.
- Cloudflare API: new script, deployment, workers.dev enablement read back.
- Next: independent browser smoke of `/health` and `/`, Supabase OAuth project authorization, then handoff to B-018 Claude for trunk/staging integration. Do not call synthetic preview full ERP.
- Canonical Drive Decision Book, Change Log, shared Board must be updated with this exact result and commit SHA; note clearly **HTTP_NOT_VERIFIED**, **SUPABASE_PERMISSION_DENIED**.
