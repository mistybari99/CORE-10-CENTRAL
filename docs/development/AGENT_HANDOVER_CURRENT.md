# CORE-10-CENTRAL — Agent handover (single source of truth)

Any agent (Claude, ChatGPT/Codex, other) starting work: read THIS file first, then the top of
`docs/development/CLAUDE_TRUNK_HANDOFF.md`. When you stop: update §5 and append to §6, commit, push.
Language to the Owner: short, clear Bangla.

## 1. Goal (Owner)
- Goal 1 (NOW): one platform for the Owner's own ~10 businesses (sweets, paint, …), each with 100–400
  branches/factories/warehouses; Owner has full control of the whole group and can enter each business
  to manage staff permissions and pending decisions.
- Goal 2 (LATER, A024 deferred): sell to outside customers (1 to many businesses each), fully isolated
  per customer; Owner keeps a platform layer (create/suspend customers, modules/plans) and an opt-in,
  audited, customer-disclosed option to view customer data. NOT built yet (no platform role exists).
- Work type: BUILD (code + its tests + deploy). No review-only loops.

## 2. Where things are
| What | Where |
|---|---|
| Repo | `mistybari99/CORE-10-CENTRAL` |
| Trunk (integration) | branch `ccr-15ed11dd-n3hw5h`, Draft PR #106. All integrated code lives here. |
| Live preview source | branch `preview/core10-central-level2`, Draft PR #126 (base `preview/core10-central-owner-app`, which is frozen) |
| Live app | https://core10-central.mistybari99.workers.dev/ (Cloudflare Worker `core10-central`, account `382a468cf1bde26b7b3c480acc409732`) |
| Owner sign-in | `/#/control` (Owner Control Centre) and `/#/setup` (business setup from industry templates) |
| Staging DB | Supabase project `rhrqhbyzrhaafynfhdaf` (CORE10 staging). Schema `core10`. |
| Migrations | `internal/migrations/NNNN_*.up.sql` + `.down.sql`; runner `internal/migrations/run.sh` |
| Number ranges | `docs/coordination/MIGRATION_RESERVATIONS.json` (also records what is applied on staging) |
| Work split rules | `docs/coordination/WORK_SPLIT_AND_PROTOCOL.md`, GitHub Issue #110 |
| Staging backup | `docs/development/staging-backups/2026-11-22-pre-go2/` |
| Board / Decision Book | Google Sheets (links in CLAUDE_TRUNK_HANDOFF.md); update if you have access, else write NOT WRITTEN |

NEVER TOUCH: Supabase `kbuhnpqooycqbzrfejcs` (IMG-ERP-SG, old ERP) and `luoeyyngayxpqecuuijb`. Never bundle
`config.js`, `v2/config.js`, `index.html`/`owner.html`, `core10-stocktake-offline.html`, `core10-stocktake-preview.js`.
No merge to `main` without Owner. No production DB. No secrets in git (publishable key is fine; never service_role/sb_secret).

## 3. Current state (2026-11-22)
- Staging ledger: 0001–0019, 0100–0106, 0110–0114 applied (31 rows, max 114). Registry 17 enforced / 7 exempt / 6 pending.
- Staging data: synthetic demo tenants 9801 (stg-a) / 9802 (stg-b) with demo personas `np-*@core10-staging.test`
  (passwords unknown; reset via SQL `extensions.crypt` if you need signed tests). Owner = `mistybari99@gmail.com`,
  `tenant_owner` of tenant 1 `core10-owner-group` (legal entity 1 "CORE10 Owner Group"). Owner set his own password.
- Live Worker version `201008ca-42a7-42cd-a08e-b968da6c4e51` (rollback: `38141fd4…`, base `025cf3a1…`; source in
  `preview/core10-central-owner-app/rollback/`). `#/control` and `#/setup` are signed against staging; master/sales/
  manufacturing pages are still recorded replay (their migrations are not on staging).
- Owner sign-in verified by Owner. Owner's group has 0 businesses; next he creates them in `#/setup`.

## 4. How to do each kind of work
- **Code on trunk**: branch from/commit to `ccr-15ed11dd-n3hw5h` (or a lane branch + PR into it). Small commits.
  Before merge: local PG17 (`bash tests/migrations/run-updownup.sh`, `internal/migrations/run.sh up`, lane SQL tests,
  `psql -f tests/migrations/control-registry-check.sql`), `node --test tests/migrations/migration-contract.test.js`,
  relevant browser tests. Never weaken/skip a test.
- **Apply migrations to staging**: only next numbers in order (> 0114, no gaps that other open PRs hold).
  Per file, one transaction: file text + `insert into core10.schema_migrations(version,name,checksum)` with
  sha256 of the file bytes (exactly like `run.sh`). Rehearse first on PG17 with staging rows. Backup first.
- **Deploy live**: edit `preview/core10-central-owner-app/build.mjs` (pins + LIVE list) on `preview/core10-central-level2`,
  `node build.mjs`, `node verify.cjs` (must be all PASS), then
  `PUT /accounts/<acct>/workers/scripts/core10-central` (multipart: metadata `{"main_module":"worker.mjs","compatibility_date":"2026-11-16","bindings":[]}`
  + `dist/worker.mjs`), then `REVIEW_BASE=https://core10-central.mistybari99.workers.dev node verify.cjs`; if not all PASS,
  roll back (`POST .../deployments` with previous version 100%). Record version in that folder's README.
- **Credentials**: you need your own Cloudflare API token (Workers edit) and Supabase access (Management API token or
  DB connection) from the Owner. Never commit them.

## 5. Next build steps (priority order)
1. Owner creates his businesses in `#/setup`; fix anything that breaks there.
2. Unblock staging for master data/stock/finance: settle numbers 0115–0118 (PR #121, in NP01 range) via the Board,
   then apply 0150–0153 (master), 0200 (stock), 0400–0401 (finance), 0500–0504 (manufacturing) in numeric order,
   then switch those live pages from replay to signed staging (same pattern as `#/control`).
3. Sales (PR #109): fix the 10 open cases in `tests/np03b/correction-security.sql` with FORWARD migrations (never edit 0301/0304), then integrate.
4. Finance F3 (PR #117): rollback test must not assume 0403 is newest; refresh the stale pin in
   `.github/workflows/core10-np06-crosslane-ci.yml` (pinned 3d128dc, PR head c6d6ca4). That check is red on trunk until then.
5. 0305 double claim (PR #121 vs #122): renumber one via the Board.
6. Fix shell banner text "nothing is saved" on signed routes (`preview/.../site/`).
7. Later (Goal 2): platform-operator role design + migration range + cross-tenant negative tests.

## 6. Progress log (append newest at the bottom: date, agent, what, commit/deploy, next)
- 2026-11-22 Claude Session A: GO-2 staging apply (e609b8a); GO-3 live Level 2 (PR #126, v38141fd4);
  Owner account + own tenant; setup page core10-staging mode (a408d7e, 6f058dc) and live v201008ca. Next: §5.1.
