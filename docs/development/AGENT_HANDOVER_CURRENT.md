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
- CORE10 staging only `rhrqhbyzrhaafynfhdaf` PostgreSQL 17.11: **40 applied migrations**, max `0200`:
  0001–0019, 0100–0106, 0110–0118, 0150–0153, 0200; every new file used one transaction
  containing exact upstream file bytes + matching SHA256 ledger row. **No 0400+/0500+ hosted**, nor Sales 030x/Stock 0201+.
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
- Cloudflare Worker `core10-central` active version **`ceeea069-d630-460a-b1f0-5b12e5157da9`**
  deployment `aaa6039c-752e-4645-aaf2-76b0596a732a`, rollback version `201008ca-42a7-42cd-a08e-b968da6c4e51`.
  Shell signed staging save-status fix shipped; deterministic bundle sha256
  `0a97d1a234e0fd39e9c5946698767dc525b8aeeebe652b9d9bcd014cc36b70ee`,
  GitHub full local browser gate run `44989935242` 49/49 PASS, full **LIVE** gate
  `44990275034` 49/49 PASS. `/#/setup` and `/#/control` signed; `/#/sales`, `/#/manufacturing`
  replay/recorded read. `/#/master` signed conversion **on preview branch only** at `35ef4f6ae654f6258c2315fed3d56db3bf7365c0`,
  awaiting full browser CI `44991383787`; not live until build/verify/deploy/live verify all PASS.
- F3 crosslane PR #117 stale SHA pin fixed on trunk `bd5aec72826a5ff0b2fd1827bc1396e3390d9067`, CI
  `44989810303` SUCCESS. Sales PR #109 security cases, 0305 double claim and 0201–0202 Stock remain work.
  **NEVER TOUCH** old IMG-ERP-SG Supabase project `kbuhnpqooycqbzrfejcs` or `luoeyyngayxpqecuuijb`;
  user said both contain only trial data, but that does not remove project-boundary restrictions.

## 4. How to do each kind of work
- **Code on trunk**: branch from/commit to `ccr-15ed11dd-n3hw5h` (or a lane branch + PR into it). Small commits.
  Before merge: local PG17 (`bash tests/migrations/run-updownup.sh`, `internal/migrations/run.sh up`, lane SQL tests,
  `psql -f tests/migrations/control-registry-check.sql`), `node --test tests/migrations/migration-contract.test.js`,
  relevant browser tests. Never weaken/skip a test.
- **Apply migrations to staging**: only next numbers in order (> 0200 as of 2026-11-22; no gaps that other open PRs hold).
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
1. **Finish signed Master UI LIVE**: source `preview/core10-central-level2` at `35ef4f6`, browser gate
   run `44991383787` pending at handover. Inspect full CI; only if ALL PASS, publish exact
   verified `dist/worker.mjs` to existing Worker, then `REVIEW_BASE=...` verify all PASS; on failure
   rollback to `ceeea069-d630-460a-b1f0-5b12e5157da9`. Update preview README and this handover.
   Existing 4 synthetic signed Owner items are ready for display.
2. **Next numeric migrations**: Stock lane 0201/0202 and any outstanding 020x must be settled/tests corrected
   **before** Sales 0300–030x and Finance 0400–040x; do NOT apply higher migrations that strand lower
   unintegrated numbers. Sales PR #109 has 10 open `tests/np03b/correction-security.sql` cases to fix
   via FORWARD migrations; **never edit 0301/0304**. Resolve 0305 double claim PR #121/#122
   on the Board before hosting. Then Finance 0400–0401 and Manufacturing 0500–0504, signed UI
   activation in order, with real staging-row rehearsal, per-file SHA ledger and scoped backup.
3. **Owner acceptance and proper new businesses**: Owner screenshot proved signed demo setup and
   its 4 sites; all data is synthetic. Invite Owner to use `/#/master` **after live signed release**
   to create/read their own demo items. Maintain a clean fresh-instance reset; do not delete
   immutable audit. For Owner Goal1 there are no real businesses besides the temporary TEST ONLY draft.
4. **100–400 site capacity post-0118**: default max 50. Use an audited business-specific signed
   Owner Control setting and stress test 100–400 on a synthetic business, never bypass the cap.
   10/10 industry setup tests and old 400-site simulation PASS before 0118 and rolled back;
   post-D063 400 must be proven separately.
5. **Finance F3 PR #117**: crosslane exact-head pin fixed at `bd5aec` (CI SUCCESS);
   rollback test that assumes 0403 is newest remains held until corrected and re-tested.
6. **Keep live truthfulness**: `/#/setup` and `/#/control` are signed staging and clearly marked;
   `/#/master` pending #1; Sales and Manufacturing replay must never claim real saved data.
   No production certification until every write path passes E2E signed/RLS and operation tests.
7. **Later Goal2**: platform-operator role, migration range, tested cross-tenant support access,
   customer disclosure and audit; still deferred.

- 2026-11-22 agent=ChatGPT: accelerated BUILD under Owner GO (all current data synthetic).
  Signed Owner SQL tests 10/10 industry templates + 400-site setup/workspace/replay PASS inside rollback
  against pre-0118 staging. F3 pinned PR117 exact SHA updated `bd5aec7`, crosslane CI PASS.
  Level2 full Worker build/browser CI run `44989935242` 49/49 PASS; deployed
  `ceeea069-d630-460a-b1f0-5b12e5157da9` (rollback `201008ca`), live URL browser CI
  `44990275034` 49/49 PASS, preview README updated `cd370b9`.
- 2026-11-22 agent=ChatGPT: original D063 0115–0118 PR121 blobs and tests isolated on PR127, fixed
  B009 4 reviewed drift cases, 8/8 PG17 CI SUCCESS, merged into trunk `8ba0661`.
  CORE10 staging backup `3b5e7c8`, applied D063 0115–0118 per-file SHA ledger + signed Owner
  bootstrap policy same 0116 transaction. Staging signed post-D063 Owner setup/replay PASS.
  More backup `3740ea5`; staging Master 0150–0153 and Stock 0200 applied numeric/SHA.
  Ledger now 40 rows, max 0200; 4 synthetic Master items + UOM/category/party/pricelist/price data
  saved using signed Owner RPCs after cross-tenant/negative tests. New signed Master UI candidate
  preview commit `35ef4f6` and negative browser regression; local full CI pending `44991383787`
  at this snapshot. No IMG-ERP-SG, other Supabase project, main merge, or real financial posts.
  Next: #1 signed Master live gate, #2 Stock then Sales/Finance/Manufacturing numeric staged work.
