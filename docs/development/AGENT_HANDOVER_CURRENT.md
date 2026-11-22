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
| Staging backup | `docs/development/staging-backups/2026-11-22-pre-go2/`, `2026-11-22-pre-d063/`, `2026-11-22-pre-master-stock/` |
| Board / Decision Book | Google Sheets (links in CLAUDE_TRUNK_HANDOFF.md); update if you have access, else write NOT WRITTEN |

NEVER TOUCH: Supabase `kbuhnpqooycqbzrfejcs` (IMG-ERP-SG, old ERP) and `luoeyyngayxpqecuuijb`. Never bundle
`config.js`, `v2/config.js`, `index.html`/`owner.html`, `core10-stocktake-offline.html`, `core10-stocktake-preview.js`.
No merge to `main` without Owner. No production DB. No secrets in git (publishable key is fine; never service_role/sb_secret).

## 3. Current state (2026-11-22)
- CORE10 staging only `rhrqhbyzrhaafynfhdaf` PG17: **46 applied migration rows**, maximum `0206`:
  0001–0019, 0100–0106, 0110–0118, 0150–0153, 0200–0206. Each hosted file applied sequentially
  with exact source SHA256 in the same committed transaction as its ledger record. Sales 030x,
  Finance 040x and Manufacturing 050x are NOT on staging; never jump over an unhosted smaller number.
- Original 0115–0118 D063 on PR #121 were copied **byte-identical** into scoped PR #127, PG17 CI all 8/8
  SUCCESS; B-009 reviewed four intentional guarded legacy API diffs, PR #127 merged to trunk `8ba066184b696307b08421e030652ebc4ab17a56`.
  Real current staging rows 4-migration BEGIN/ROLLBACK rehearsal PASS; Owner signed policy activation + fresh signed
  business setup rollback PASS. Hosted D063 applied in numeric order with Owner tenant 1 bootstrap policy **enabled atomically
  with 0116**, so existing setup sign-in not stranded. Site capacity defaults to 50 after 0118 (business-specific Owner
  Control can raise it); former pre-0118 400-site smoke is not post-cutover proof.
- Master 0150–0153 and Stock foundation 0200 applied to staging after separate 12-migration
  on-real-staging-rows BEGIN/ROLLBACK PG17 rehearsal and a scoped data snapshot. Signed Owner Master
  RPC creation/read (Bangla search, UOM, item, request replay) PASS, cross-tenant denial PASS.
  Four **synthetic demo items** (Rasgulla, Sandesh, Sugar, Milk), 3 UOMs, 2 categories, 2 parties,
  1 retail price list with 2 test prices persisted through signed RPCs on Owner Business 3. No stock/finance posts.
- Owner is `mistybari99@gmail.com`, tenant_owner tenant 1 `core10-owner-group`, legal entity 1.
  Owner's screenshot confirmed real signed Build01 UI, business ID 3 `CORE10 DEMO Sweets (TEST ONLY)`,
  and four sites (original 3 plus Owner's trial `ASIAN Paint` showroom). No real Owner business created yet.
  Synthetic tenant 9801/9802 and their businesses remain isolated. Owner password/other auth data unchanged.
  Fresh-instance script `scripts/staging/create-fresh-owner-demo.mjs` + 5 tests in `8907369`; do NOT hard-delete immutable audit.
- Staging safety snapshots: `docs/development/staging-backups/2026-11-22-pre-go2/`,
  `2026-11-22-pre-d063/` (current 14-table snapshot without auth secrets), and
  `2026-11-22-pre-master-stock/`. Each is a scoped logical backup; full restore still relies on managed backup.
- Cloudflare Worker `core10-central` latest fully verified v`2d9894b8-279d-4772-91f6-be46a54d98e3` (read-only signed Business dashboard), public Chromium verification `44996166820` **50/50 PASS**; previous fully verified fallback v`4b6d179c-e1aa-4066-9fb6-6988dbc32432`. `/#/setup`, `/#/control`, and NOW `/#/master` are signed CORE10 staging, whereas Sales and Manufacturing remain recorded replay. New signed Master UI source `35ef4f6`, verified candidate `f0e8e036`, Worker 903404 bytes SHA256 `3ae944b1cdcb49f4701457d629e99b61f4acff32fff7b77e2713d3f16568fc28`. Full local browser CI `44991383787` 50/50 PASS and full live public URL CI `44991642473` 50/50 PASS; wrong-password refusal checked. Release README preview commit `1fac3aa`. Owner has not yet manually confirmed item editing on new Master mobile page.
- Post-0118 signed Owner **staging capacity** (2026-11-22): verified 50 default succeeds, 51st denied; an audited per-business `max_sites=400` setting allowed 400 sites and 401st denied. All tests `BEGIN/ROLLBACK`, post-test Owner business 3 still exactly 4 sites and no persisted business cap setting; DB ledger remains 40/max0200. Mobile 400-site UX not yet performance-tested.
- Stock/Procurement NP03A integration: original Claude PR #123 at `54bc5889` remains preserved;
  isolated PR #129 merged at trunk `ac86ee809157af13458b5607132f00a3d72caec9`.
  Before merge, a post-row-lock Auth recheck was added to inventory command/PO/GRN writers
  (0201, 0203, 0206), with a real revocation-while-waiting race test.
  All six exact-head CI workflows PASS including PG17, Control registry, multi-session races,
  390/1440 Chromium dashboard; no old 0200 file was changed. Signed staging-row ROLLBACK
  rehearsal and signed Owner stock receive→confirm→post/replay/cross-tenant negatives PASS.
  Pre-hosted scoped 30-table snapshot `docs/development/staging-backups/2026-11-22-pre-stock-0201-0206/`
  was committed `77fd9ad2`. Hosted 0201–0206 with exact SHA/ledger one transaction each, all PASS.
  Staging business #3 now has synthetic (TEST ONLY) six posted inventory commands, eight canonical
  stock movements, six balance rows, zero unreconciled; four original site MAIN locations were
  provisioned earlier and reused, four Master items intact. No Finance journal/real customer posts.
- Owner Stock write workbench `/#/stock` is LIVE on existing Cloudflare Worker
  version `65f60417-5b76-4524-830a-c74018b7ff58` (100% deployment
  `c282ed0c-106d-4cd3-9e7a-504e700e114a`), rollback
  `2d9894b8-279d-4772-91f6-be46a54d98e3`.
  Real canonical signed Stock 0201–0206 RPCs used, no legacy A048 read RPC. Source
  preview `fd917d8321643463201e2c1ed2e5e092840916f9` and verified Worker candidate
  `5e88f8352676b645a86f49d8a4bf115f3eec2003`; bundle 955520 B,
  SHA256 `ba530d45179f9ea146bccb0a04899213a3e396adf7fe6030b28eebf938a5f4b2`.
  Local full Chromium run `44997262303` 56/56 PASS and PUBLIC run `44997571687`
  **56/56 PASS**. Owner signed DB workflow draft→confirm→post→list in BEGIN/ROLLBACK
  PASS; no stock rows persisted from that test. Owner manual mobile input acceptance pending.
- Dashboard Owner `/#/business`: signed read-only real portfolio/site/Stock integration preview source
  `a7b36cfa`, deterministic bundle candidate `27b2e254`, local browser CI `44995895627`
  **50/50 PASS**, Cloudflare existing Worker version `2d9894b8-279d-4772-91f6-be46a54d98e3`
  active after PUT. Exact public-live bundle verification run `44996166820` **50/50 PASS**, same
  SHA256 as local bundle and no unauthorized backend calls.
  Previous stable rollback Worker `4b6d179c-e1aa-4066-9fb6-6988dbc32432`.
- F3 crosslane PR #117 stale SHA pin fixed on trunk `bd5aec72826a5ff0b2fd1827bc1396e3390d9067`, CI
  `44989810303` SUCCESS. Sales PR #109 security cases, 0305 double claim and 0201–0202 Stock remain work.
  **NEVER TOUCH** old IMG-ERP-SG Supabase project `kbuhnpqooycqbzrfejcs` or `luoeyyngayxpqecuuijb`;
  user said both contain only trial data, but that does not remove project-boundary restrictions.

## 4. How to do each kind of work
- **Code on trunk**: branch from/commit to `ccr-15ed11dd-n3hw5h` (or a lane branch + PR into it). Small commits.
  Before merge: local PG17 (`bash tests/migrations/run-updownup.sh`, `internal/migrations/run.sh up`, lane SQL tests,
  `psql -f tests/migrations/control-registry-check.sql`), `node --test tests/migrations/migration-contract.test.js`,
  relevant browser tests. Never weaken/skip a test.
- **Apply migrations to staging**: only next numbers in order (> 0206 as of 2026-11-22; no gaps that other open PRs hold).
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
1. **Owner signed Business, Master and Stock mobile acceptance**: all three are now live.
   Owner Business `/#/business` read-only Worker `2d9894b8` had public 50/50 PASS; signed
   Master `/#/master` accepts canonical items and prices; newly signed `/#/stock` deployed Worker
   `65f60417-5b76-4524-830a-c74018b7ff58`, pre-publish local `44997262303` 56/56 PASS,
   exact public live `44997571687` **56/56 PASS**, bundle SHA256
   `ba530d45179f9ea146bccb0a04899213a3e396adf7fe6030b28eebf938a5f4b2`.
   Signed Owner backend Draft→Confirm→Post→List test in ROLLBACK PASS. Mobile Owner
   password login and manual real button Post still needs Owner acceptance. Keep samples TEST ONLY.
2. **Finish Stock/Procurement adoption**: `/#/stock` now signed staging command UI
   for receive/issue/transfer/adjust Draft, Confirm, Post, and list. Staging 0201–0206,
   four Owner demo items and four locations remain. Owner manual mobile acceptance and
   a guided PO/GRN/QC signed input UI are the next Stock features. The legacy A048 Inventory
   client calls a nonexistent `read_inventory_commands_v1`; never ship it directly; the
   new route uses `inventory_list_commands_v1` and includes `p_reason` on create.
3. **Sales stage 030x first**: reconcile merged Sales PR109 with open 10 security
   correction cases, resolve competing 0305 PR121/PR122 with Board and enforce FORWARD-only
   fixes. Exact-head CI + independent P1 review + scoped backup + signed staging
   rehearsal before hosting. Do NOT skip 030x to Finance 040x or Manufacturing 050x.
4. **Then Finance 0400+ and Manufacturing 0500+**: integrate signed Stock/PO/GRN/Sales
   handoffs with source-linked single Money/Audit ledgers; PR117 rollback test P1
   and trade-account policy still require exact-head readiness; no phantom posting.
   Sales/Manufacturing UI currently recorded replay, not live operational.
5. **Keep cross-builder ownership**: hourly A/B agents work isolated branches only.
   This interactive chat exclusively writes canonical trunk, hosted CORE10 staging
   and existing Cloudflare Worker, after SHA/CI/backup/rollback gates. Never touch
   original PR123, old IMG-ERP-SG or main. Synthetic data still obey immutable audit.
6. **Later Goal2**: platform-operator/customer separation and audited support mode,
   deferred. Owner Goal1 is one ERP for 10+ own businesses and 100–400 sites each.

## 6. Progress log (append newest at the bottom: date, agent, what, commit/deploy, next)
- 2026-11-22 Claude Session A: GO-2 staging apply (e609b8a); GO-3 live Level 2 (PR #126, v38141fd4);
  Owner account + own tenant; setup page core10-staging mode (a408d7e, 6f058dc) and live v201008ca. Next: §5.1.
- 2026-11-22 agent=ChatGPT: signed setup/control staging banner fix + regression test on preview branch
  commit `8d30615ee4648bc2ac38d80d9655eaaf01a80192`; route smoke 4/4 PASS and Preview static CI PASS;
  no staging migration or deploy (Worker still `201008ca-42a7-42cd-a08e-b968da6c4e51`); full build/verify pending.
  Next: Owner opens signed setup, then complete build/verify/live-gated publish; §5.2 remains blocked on Board.
- 2026-11-22 agent=ChatGPT: built actual Owner-group staging DEMO Sweets draft #3 + 3 sites through existing
  `build01_setup_v1`; signed-context SQL tests (replay, workspace, isolation, audit) PASS. Fresh-instance
  runner, tests 5/5 local PASS, reset/audit guide committed `8907369b636e7fff5c408025e8262c9d9ca81342`;
  CI was queued at observation; no migration or Worker deploy, live `201008ca-42a7-42cd-a08e-b968da6c4e51`.
  Next: Owner tests existing sign-in at /live/core10-build01.html; finish browser acceptance, build/verify/live gate,
  decide policy-based archival before any hard deletion, then resolve §5.2 0115-0118 migration reservations.
- 2026-11-22 agent=ChatGPT: Owner acceleration BUILD. Signed setup 10/10 templates and 400-site pre-D063 rollback stress PASS; Finance F3 SHA pin fixed `bd5aec`, CI success. Cloudflare truthful signed banner version `ceeea069` (build/live 49/49 PASS).
- 2026-11-22 agent=ChatGPT: original D063 0115-0118 code and tests integrated via PR127 after 8/8 PG17 CI PASS, merge `8ba0661`. Snapshot pre-D063 `3b5e7c8`; Owner bootstrap policy activated atomically at 0116 hosted. Staging signed setup after D063 PASS. Snapshot pre-Master/Stock `3740ea5`; staged 0150-0153 and 0200 with exact SHA ledger; 40 migrations, max 0200. Signed four dummy Master items and reference data persisted, cross-tenant negative PASS.
- 2026-11-22 agent=ChatGPT: Master staging signed frontend `35ef4f6`, full local Chromium CI `44991383787` 50/50 PASS, exact Worker candidate `f0e8e036`; deployed Worker `4b6d179c-e1aa-4066-9fb6-6988dbc32432` 100%, public LIVE CI `44991642473` 50/50 PASS, previous rollback `ceeea069`, preview README `1fac3aa`. Owner personal Master mobile item-edit acceptance still pending. Next: Stock/Sales numeric backlog then Finance/Manufacturing.
- 2026-11-22 agent=ChatGPT: staging post-D063 Owner capacity regression PASS. Signed 50-site default/51st refusal + audited Control cap400/401st refusal via canonical RPCs, all rolled back. Re-verified unchanged 4 Owner demo sites, 0 business overrides, ledger 40/max0200. Next: exercise actual mobile UI performance at 100–400.
- 2026-11-22 agent=ChatGPT: progressed real NP03A Stock/Procurement. Claude PR123
  `54bc5889` copied into isolated PR129 and security-hardened against post-lock
  permission revocation in 0201/0203/0206; test uses real concurrent tenant-member
  revoke and proves denied post. Exact-head `e6ea21003da828a53db5c464c1f20281f5686b4f`
  6/6 CI PASS incl. PG17 + browser; PR129 merged canonical `ac86ee8`.
  Pre-cutover backup `77fd9ad2`, 30 scoped `core10` tables. Hosted 0201–0206
  each with SHA256 ledger and signed Owner ROLLBACK rehearsal; staging 46/max0206.
  Persisted six TEST ONLY command posts/eight movements/six balances, reconciliation 0,
  other tenant denied. Owner Business signed read-only preview `a7b36cfa`,
  local 50/50 PASS `44995895627`, candidate `27b2e254`, Worker active
  `2d9894b8-279d-4772-91f6-be46a54d98e3`; public gate `44996166820` **50/50 PASS**, live release confirmed. Next: verify public gate + release doc,
  then build signed Stock/Procurement write UI and Sales 030x.
- 2026-11-22 agent=ChatGPT: shipped signed Stock command UI on preview
  source `fd917d8321643463201e2c1ed2e5e092840916f9` (6 edited/added files),
  route `/#/stock` with real signed Owner receive/issue/transfer/adjust draft,
  confirm, post, list. Found legacy `read_inventory_commands_v1` nonexistent;
  uses actual 0201–0206 `inventory_list_commands_v1`, `create_inventory_command_v1`
  with p_reason, `advance_inventory_command_v1`. Signed Owner transaction
  create→confirm→post→list PASS and rolled back; no stored demo stocks changed.
  Local full Chromium run `44997262303` **56/56 PASS**, candidate `5e88f835`;
  Cloudflare existing Worker `65f60417-5b76-4524-830a-c74018b7ff58`
  active 100%, public run `44997571687` **56/56 PASS**;
  rollback `2d9894b8`. Preview release README `e9dd90d`.
  NEXT: Owner manual signed Stock write UI acceptance, add signed PO/GRN/QC
  workflows, then Sales 030x/Finance 040x/Manufacturing 050x numeric integration.
