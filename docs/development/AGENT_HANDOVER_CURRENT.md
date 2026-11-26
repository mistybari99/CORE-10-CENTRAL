# CORE-10-CENTRAL — Agent handover (single source of truth)

Any agent (Claude, ChatGPT/Codex, other) starting work: read THIS file first, then the top of
`docs/development/CLAUDE_TRUNK_HANDOFF.md`. When you stop: update §5 and append to §6, commit, push.
Language to the Owner: short, clear Bangla.

## 0. Latest Owner release authorization and execution — 2026-11-26
- **PR #173 RECOVERY COMPLETE / LIVE (2026-11-26):** Codex branch recovered; original location ACL regression retained; bare PG17 CI now provisions NOLOGIN anon before migrations. Exact tested head `2f276c800cf577c1306574e6bd20e5e4a64c31a6`, three CI workflows SUCCESS (45845903104, 45845902893, 45845902922); merged `2d1191ba6408e7fb86a0f3fe8cc4c28786c4abdd`. Downloaded CI artifact 15131922092 and verified archive digest and Worker SHA256 `b17e399a193836c864648a3ae28722ed78596916c13b4631d328cc19f4c091bf`; Cloudflare uploaded v20 `ecc24ac8-7d72-4b46-95c6-65d72a17f1d1` readback exact match; activated 100% deployment `0b4babdc-04e5-4727-b263-1a7e9ba80c05`. Rollback v19 `2ea0fcff-ffa4-49a2-998a-fe4be0971b11`. Actual public mobile Chromium HTML via Cloudflare browser rendering contains selected-site Stock Location panel and site selector. Hosted SQL readback: 71/max0504, authenticated EXECUTE true, anon false. No persistent SQL changes or duplicate migrations. Real signed Owner acceptance remains open; automatic release environment secrets remain unverified. Next: reconcile separate Bakery #171 with canonical trunk, then signed recipe revision, lot/UOM, pack, shelf life and label profile preflight; respect #166 ownership.
- **Current module delivery, 26 Nov 2026.** Start from canonical branch `ccr-15ed11dd-n3hw5h`. [PR 172](https://github.com/mistybari99/CORE-10-CENTRAL/pull/172) merged at `bc5cbf3f213cb46947bce50fb0c3394d6f97ade1`. The signed shell shows site IDs and counts by kind for the selected business using the existing authenticated Supabase RPC. [Exact build and PG17 / browser tests](https://github.com/mistybari99/CORE-10-CENTRAL/actions/runs/45843067133) passed, including 71 migrations up/down/up and 390/1440 px. On CORE10 staging `rhrqhbyzrhaafynfhdaf`, all 71 ledger checksums matched source. [Public preview](https://core10-central.mistybari99.workers.dev/) served Worker v19, deployment `29010746-6f14-4239-b420-9dddd40f8046`. Full readback SHA-256 `66f4ea51bda3b9c7cc33c740c3917a72c585fa2c0a303c4104fc0d6145f6d9ca`. Hosted owner login/business transaction acceptance is open.
- **Next agent.** Use the [v1.0 execution register](https://docs.google.com/spreadsheets/d/100urPYSrm8hYqAqU3xPp1nUORqfZXxXq/edit) and [Coordination Board](https://docs.google.com/spreadsheets/d/1QyBpRr6rybexMwSA1ivLmn_VidrntbcOTRK4qi1c9Mc/edit). [PR 171](https://github.com/mistybari99/CORE-10-CENTRAL/pull/171) contains the Bakery module plan and the draft wizard preview changes on its separate branch. T01.01 code in [PR 173](https://github.com/mistybari99/CORE-10-CENTRAL/pull/173), commit `d9370dd0`, adds signed shell → selected site → Stock locations, backed by the shipped `inventory_list_locations_v1` RPC. Supabase confirmed authenticated EXECUTE and anonymous denial. Local browser fixtures passed for scope switching and invalid response site; 11 local tests passed overall. CI also runs the original PG17 location permission, ordering and truncation fixture. Link the final deployment receipt here when released. Keep #166's Stock workbench assignment separate. The remaining Bakery preflight includes recipe revision, lot/UOM, pack, shelf life, label profile and signed rerun evidence.
- **Repeatable release.** `.github/workflows/core10-module-preview.yml` verifies PRs and releases eligible canonical pushes to CORE10 staging. [First post-merge run](https://github.com/mistybari99/CORE-10-CENTRAL/actions/runs/45843598114). The interactive connectors can read staging and deploy this Worker. The GitHub integration returned HTTP 403 for environment administration and Actions secret listing. The post-merge verification passed; the release job stopped at its missing Worker token before database changes. Repository administrator must configure GitHub environment `core10-staging` secrets `CORE10_STAGING_DB_PASSWORD`, `CORE10_PREVIEW_WORKER_TOKEN` and variable `CORE10_STAGING_POOLER_HOST`. Keep values in environment settings. The first live release used the connected Cloudflare account after CI passed.

- OWNER VISIBILITY GALLERY LIVE (2026-11-26): PR #170 merged `9679fb07e67f707c769b1b670f042fe7e039b7df`, tested head `878947eba7b7806165afd6b3bae95f45cf315796`. Dedicated CI 45838341088 SUCCESS incl. actual Chromium 390/1440, exact canonical source packs, deterministic Worker, old signed assets preserved except navigation; clean release CI 45838341149 SUCCESS. Cloudflare same Worker deployment `e6f76daf-aed2-4b43-adf4-045ebabd38bb`, version `d8cc0fff-2d7d-4ac6-8f07-bac99c1e152a`, 100%, readback SHA256 `50593aad7e211f3e1c91e7713cee6bf5a991b820dbc4204e215e3a9c986d8b89` matched CI. 67 allowlisted routes, 19 gallery entries (6 signed staging, 5 interactive preview entries, 8 explicitly unshipped/partial/backend-only). Actual public mobile gallery HTML verified 19 cards. New live target `node apps/central/build-progress.mjs` -> `dist-progress/worker.mjs`; root Home/desktop/mobile More `#/progress` plus direct `/progress/index.html`. Manufacturing is canonical workbench on historical synthetic read snapshot, no live SQL; PaperOps Print Studio/Smart Kit/Control Checks are canonical offline UI, no posting; CRM is existing synthetic local prototype, no real messaging. All `/progress/` assets CSP connect-src none, original signed route authorization unchanged, removed legacy and old replay paths remain 404. Finance/Approval/advanced Stock/industry operational signed UI still needs build/integration, no false production certification. Supabase unchanged; no reset, migration, auth or data write. Old clean Worker version `7921a519-0242-44d1-b2d7-e747afd9bdd0` retained for rollback. Historic public verifier still targets removed demo routes; do not restore those routes; coordinate #168/#166 public gate changes. Gallery snapshot must be updated when new builds integrate.
- OWNER-AUTHORIZED HOSTED BASELINE20 FRESH REBUILD (2026-11-26 20:05 Asia/Dhaka): Supabase `rhrqhbyzrhaafynfhdaf` retained. GitHub canonical source `c8281e0fce150893722ec8928a3494e552d5c5ed`, merged PR #169, exact passing CI 45834418384. All 20 actual SQL bundles (920436 bytes) verified by exact Git blob SHA1 and SHA256, privately staged; full DROP SCHEMA core10 CASCADE and 20 ordered bundle execution passed rollback rehearsal and was committed atomically. All 71 original version/name/SHA256 ledger entries exactly matched; freshly applied at 2026-11-26T14:05:18.559651Z; max0504. Owner Auth identity retained, one fresh owner group/legal entity, zero businesses/sites/items/stock/orders/journals/production. 10 templates, 10 industry catalog entries, 46 Control definitions seeded. Missing RLS=0, anon definer=0, unpinned definer=0, pending registry=0. Existing valid Owner session server-side context test PASS, no new interactive browser login/first business acceptance. Private staging schema removed in commit, no extra CORE10 schemas. Cloudflare intentionally unchanged per Owner. Existing 71 ledger records are correct evidence of 20-file installation; never replace history with 20 fake versions. New migrations >0504. No other projects touched.
- OWNER-REQUESTED BASELINE20 COMPLETE: PR #169 merged `865e54230f1faa7ace4f1778a3493ba65d81dff7`; tested head `ed8359912789e60deb6064ebe9e05e3ca079f930`, CI 45834418384 SUCCESS. Exactly 20 SQL files under `internal/baseline20/` (920436 bytes), lossless ordered grouping of 71 original migrations through 0504, byte/checksum/source coverage verified 71/71. Two independent PG17 fresh builds: full schema dump including ACL/RLS/function/trigger/index definitions, all seed rows (only known clock columns normalized), sequence parity PASS; 10 selected E2E regressions including Sales-Finance and Manufacturing PASS, existing-schema reapply denied and original runner checksum-compatible. Use `CORE10_BASELINE_ALLOW_EMPTY=YES CORE10_BASELINE_EXPECT_DB=<target-db> bash internal/baseline20/run.sh` for an approved EMPTY target; original numbered up/down migrations preserved for upgrades and history. Existing hosted ledger remains 71 source versions, max0504; no hosted reset/redeploy, no semantic pruning, no live performance claim. New versions remain >0504.
- OWNER-AUTHORIZED IN-PLACE FRESH RESET RECEIPT (2026-11-26): Same Supabase project `rhrqhbyzrhaafynfhdaf` and same live URL retained. Source canonical trunk `5cb7600120ff66fe0e6f146b74e6934d46839fc6`; 71 exact GitHub up.sql bodies checksum-verified against previous ledger before reset. Full DROP SCHEMA core10 CASCADE + ordered recreation + minimal Owner setup + eight confirmed core10-staging.test Auth user deletions passed BEGIN/ROLLBACK rehearsal; original counts verified restored before commit; identical reset committed atomically. All 71 freshly applied migration names/SHA256 matched source, one fresh applied_at timestamp, max0504. Fresh data: 1 existing real Owner Auth account, 1 fresh owner group, 1 fresh legal entity, 0 businesses/sites/items/stock movements/sales orders/draft invoices/journals/production batches/test users. 10 template and 10 industry catalog definitions, 46 Control catalog definitions retained as canonical migration seeds. Security counts: missing RLS=0, anon-executable definer=0, unpinned definer=0, pending registry=0. Owner context SQL role/claims test using existing valid session id passed (one authorized group, can_bootstrap=true, no businesses/sites); not a new interactive login or end-to-end write acceptance. Previous logical backup and temporary reset-source schema removed after verification at Owner request; only core10 application schema remains. Supabase managed Auth/Storage/system schemas preserved, public tables and storage objects/buckets zero. Cloudflare same core10-central Worker reuploaded exact GitHub CI-verified clean artifact SHA256 de9351a3b8104dec7d39405a7406f5a490ce76448b67bd02e207e27f3b82c6c6; deployment `d2f8aa85-3894-4401-9d16-e34397057804`, version `7921a519-0242-44d1-b2d7-e747afd9bdd0`, 100%, readback hash MATCH, 43 signed-only allowlisted routes, 0 bindings; no Worker-owned database to clear. Historical deployment versions/Git history retained, not active. No other projects, legacy IMG ERP, or other builders modified. Real Owner browser login and first business setup acceptance pending; no default posting activation. New hosted migration numbers must be >0504.
- CLEAN LIVE RELEASE RECEIPT (2026-11-26): #167 merged `2e52d7b7339d0ebd6f3606a08ac2951c563477a9`; dedicated CI 45821361773 SUCCESS, deterministic exact worker SHA256 `de9351a3b8104dec7d39405a7406f5a490ce76448b67bd02e207e27f3b82c6c6`. Cloudflare deployed existing core10-central Worker version `24c74031-1c6b-4a6a-85f2-646f1f84363d` at 100%, deployment `8e290b44-ac02-483a-bc14-6a5e425d0c43`; API readback exact CI SHA matched. 43 allowed routes vs 76 prior, 33 removed from active Worker (not erased from Git history); previous version `4bd5642a-dc1b-4543-b0b0-0d691a4d2810` retained for rollback. Cloudflare mobile browser actual root rendered, no old Manufacturing menu; /#/sales rendered data-view=sales, mobile active Sales nav, draft-only status; direct /view/workspace.html returned Not found. Historical 56/56 local passed; old public preview verifier intentionally incompatible with removed demo routes, do not restore demo to satisfy it. #168 exact head `68d33fd3bec5d4c44847f653f59ede96e3462ade` adds dedicated live HTTP and 390/1440 browser tests and switches public-only verifier; CI pending. Build target for actual release `node apps/central/build-clean.mjs`, dist-clean/worker.mjs. Existing #166 Stock UI improvement needs clean public gate and latest trunk sync; do not deploy historic build.mjs anymore. Hosted canonical ledger 71/max0504 confirmed; no real transaction acceptance, no Auth or tenant wipe; keep Finance/Mfg/PaperOps/industry UI out of clean menu until signed operational host ready. General RELEASE HOLD remains withdrawn, technical gates remain.
- 2026-11-26 UTC Owner-directed clean release: #164 merged `42e553ef6c542ab9f8c26bfd6637027e5b9b90bf` after all 8 combined workflows SUCCESS. Stock/PaperOps 0310–0315, Finance 0400–0407, Manufacturing 0500–0504 applied from that canonical source in two guarded atomic transactions (6 then 13), ledger 71/max0504. Independent readback: 9 auth users, 3 tenants/businesses preserved, 0 pending registry, 0 tables without RLS, 0 anon-executable definer, 0 unpinned definer. Pre-release private same-project logical snapshot `core10_release_backup_20261126`: 59 tables / 362 rows / 1585 catalog objects; anon/authenticated access denied, NOT independent PITR backup. No raw row data published. #167 clean signed-only Worker candidate `889e1f6f30850bde86c599842477c78b974fc2ee`: six signed menu surfaces, positive allowlist 43 routes instead of 76, remove 33 sample/preview/draft routes, existing Git/rollback preserved. New dedicated CI 45821361773 PASS (deterministic checksum `de9351a3b8104dec7d39405a7406f5a490ce76448b67bd02e207e27f3b82c6c6` and executable HTTP contract). Cloudflare candidate reconstruction matched exact CI checksum; deployment pending at this checkpoint. Historical preview remains code-only; future live checks must target clean build, not old demo paths. No posting control activation, no Auth/database project wipe. New hosted versions must be >0504; allocate coordinated range. 
- 2026-11-26 subsequent integration: Finance #165 exact corrected head `ea53330b6957883848f1713fd3297bf8ed18bc4c` 8/8 workflows SUCCESS (including AR/AP, Sales bridge, canonical Approval/Audit, Stock Control, Manufacturing); merged code to trunk `ff3bda42cdf1869eab8f553c48ac504ba6753151`. Stock/PaperOps #164 merged latest Sales+Finance trunk into its isolated branch, zero path overlap, two-parent nonforce commit `0c2fe04ce9690a08c9237c7277d06f6527e145af`, exact combined CI pending. Hosted staging rehearsal on max0305: all 19 candidate SQLs 0310–0315,0400–0407,0500–0504 in one BEGIN/ROLLBACK transaction, 350855 query characters; pending registry=0, tables without RLS=0, anon SECURITY DEFINER=0, unpinned SECURITY DEFINER=0, 16 mfg_ functions, Finance collection table and W02 snapshot present. Separate readback verified full rollback: 52 ledger/max0305, finance collection/W02 absent, mfg functions=0. No persistent SQL, feature activation or Worker write this increment. Google Coordination Board rows 55–57 now record Sales live, forward reservation candidate #164 (0310–0315), Finance #165 code integrated. Next: #164 combined exact-head CI and canonical reservation confirmation, fresh private/managed staging backup (repo is public; never upload raw business/auth rows or secrets), then ordered hosted SQL and verify. #166 separate UI owner unchanged. General RELEASE HOLD withdrawn; technical gates remain.
- 2026-11-26 later release receipt: PR #163 merged `affe71cf771d535d158aae9d9353c5ca154d36b5`, exact head CI 2/2 successful. Signed Sales staging interface deployed 100% on existing Worker version `4bd5642a-dc1b-4543-b0b0-0d691a4d2810`, deployment `64f46177-d444-4696-99e1-36a2a9bbee03`, SHA256 `1751153defe14d86b45e29ca612aa8b7603630b651e046be75c892a1d453a4ff` exact CI build and API readback match (76 routes). B01 prior version `17238003-407c-4698-8299-b0858dde59e1` retained for rollback. Post-deploy full public CI rerun requested (45795729004). Route /view/sales-signed.html; no feature activation or posting; hosted successful signed business transaction remains unverified. Stock/PaperOps #164 CI evidence literal-path fix `a582d82dd37c306d92f5c1dd0e2f70c103b80014`; Finance #165 shell quoting fix `ea53330b6957883848f1713fd3297bf8ed18bc4c`; exact-head reruns pending. Stock/PaperOps candidate 0310–0315 all six exact SQL blobs passed hosted BEGIN/ROLLBACK rehearsal with pending registry, missing RLS, anon definer, unpinned definer counts all zero and W02 snapshot present inside transaction. Independent readback verified rollback (52 rows, max0305, W02 absent). No new persistent SQL. Board allocation remains prerequisite; coordinate PR166 owner, no overlap. General release hold remains withdrawn.
- Owner withdrew the general RELEASE HOLD and authorized merge, SQL and live publication of technically ready CORE10 work. This supersedes earlier general release-hold statements; it does not waive technical, security, dependency, isolation or rollback gates. Keep legacy IMG-ERP-SG and other databases untouched; no main merge is needed for the existing Worker.
- B01 PR #160 exact head `36a264e6554250f38e80ba189d03ca8569aaac5c`, 2/2 Actions success including local 56/56, merged to canonical trunk `ea4d4aea6f63e452eb49e95f642efada47bc9f8b`. No SQL needed for B01.
- Sales 0301–0305 applied on CORE10 staging `rhrqhbyzrhaafynfhdaf` in one atomic transaction using the five prepared SQL scripts in `docs/development/staging-backups/2026-11-24-pre-sales-0300-0305/run-in-sql-editor/`, from exact source `3e008e8ec7db896f46a94ab8ca3d91271905d71d`. Source CI green, pre-Sales snapshot from 2026-11-24, hosted all-five BEGIN/ROLLBACK rehearsal PASS, then committed; ledger 52/max0305, all six Sales checksum rows verified. Zero core10 tables without RLS, zero SECURITY DEFINER without pinned search_path, zero anon executable SECURITY DEFINER; sales order count zero, default-enabled Sales controls zero. No signed hosted Sales write acceptance or UI activation yet.
- Existing Cloudflare Worker `core10-central` deployed B01 100%: version `17238003-407c-4698-8299-b0858dde59e1`, deployment `7ff90633-f8d4-4349-ac02-955bed29ce79`, SHA256 `060dae1b385cc58eaba08b3edd75360a5b85c3a3c62ba919ecb6f672e9d14287` (byte-identical to exact CI-tested B01 deterministic build, reconstructed from previous verified Worker and exact seven site blobs; upload and readback SHA matched). Prior active rollback version `1a99371f-2cf2-4546-bc18-321f76224a7e`. Post-deploy public browser workflow rerun requested: run 45714780320, job 139557919640; pending at initial observation. Sales/Manufacturing replay UI unchanged.
- NEXT: complete signed Sales staging acceptance and real Sales UI (do not mark live posting ready); renumber outstanding Stock 0207–0210 and PaperOps 0211–0212 above hosted max 0305 by board allocation before applying; reconcile Finance #120/#122/#117 and stacked tests with current trunk and forward-only 0305; then Manufacturing, Paint and Integration Worker. No uncontrolled posting or unallocated SQL. Keep cross-builder ownership. Update Decision Book/Board separately if available.


- 2026-11-26 integration checkpoint: signed Sales host PR #163 exact head `7ae9f3f4fdd318d9256e740abd1c05f5ee8894ea` passed both Actions (45795728983, 45795729004; full local/public 56/56, Sales lifecycle and exact canonical source). Merged code-only into trunk `affe71cf771d535d158aae9d9353c5ca154d36b5`. Signed hosted business acceptance and Worker release are still outstanding; no posting activation. Stock workbench PR #166 passed dedicated regression and Double Audit at prior head; merged latest Sales trunk into its isolated branch at `ed75b0e6694ce4fbe08d25e7a8d05bc0c086bdb0`, preserving both provenance checks. GitHub mergeable, zero behind; rerun combined exact-head CI before merge. Board B-012-REQ1 updated. Stock/PaperOps PR #164 (0310–0315) and Finance PR #165 (0402–0407) are active integration candidates with failed checks; leave their owners to resolve them, do not duplicate or apply. No SQL/Worker writes in this checkpoint.

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
- **§7b.4 first canonical signed shell context BUILT/MERGED:** PR #142 merged only canonical trunk `d8b69a0c91ba865e38ac08fd79a33d86a9eb0368`, exact head `f9778d3ba161c782e9d56a29739536bc7c056fb8` (Board B-040). Shell sign-in uses existing CORE10 staging Auth; Group ▸ Business ▸ Site list comes from signed `build01_context_v1`, actor-before/after and cross-tenant validation; each context choice revalidates; privacy purge, stale async/result and account-switch guards. Source and real browser synthetic adversarial tests in `tests/core10-central-signed-context.test.cjs`. Exact HEAD shell CI `45049736364` SUCCESS (new scope/security/race tests, older nav, full local **56/56**, old public Worker read-only **56/56**, historical import safety) and Double Audit `45049736374` SUCCESS. **No staging/data/migration, main, protected IMG or Worker deployment.** Important: this is NOT universal SSO; Setup Build01 still uses an independent nonpersisted auth client, and context does not filter embedded modules. NEXT role-aware module homes + per-module signed context propagation, unified token CSS + bn/en; then §7a Sales 030x.
- **§7b.4 first app-navigation BUILD MERGED:** PR #140 merged canonical trunk `d442281cb73e240d016f0ecf530f531941c47db8` (exact head `439032c5fdf6bb8400536003bb59149be2df37b7`): existing 11 routes regrouped into desktop workspaces/operations/admin; mobile 4 tabs + More for all other routes, bn/en, keyboard, active states, browser Back corrected by replacing nested iframe route history. No signed backend, approval, role, migration or Form Engine modification. Exact-head shell CI `45041736695` SUCCESS: original §7b.3 byte-for-byte gate preserved, new Playwright 2/2, current local 56/56 and old public Worker read-only 56/56 PASS; Double Audit `45041736755` SUCCESS. No Worker deployment, staging, `main` or protected Supabase changes. **NEXT:** single signed shell session/context Group ▸ Business ▸ Site, role/entitlement module navigation and shared token CSS + bn/en dictionaries; then §7a Sales 030x.
- **§7b.3 canonical shell source imported:** PR #134 merged trunk `dc9f9c7eef3d5e78403f148e7fc06d03964c62b6`. Existing preview `site/`, `data/`, `build.mjs`, `local-serve.mjs`, `worker-runtime.mjs` imported as *exact* Git tree/blob objects into `apps/central/`; `verify.cjs` copied with sole approved old-IMG config path adjustment following §7c. Import manifest/provenance test and CI added. Exact-head `4345b6e4` **4/4 CI SUCCESS**, deterministic Worker SHA256 `ba530d45179f9ea146bccb0a04899213a3e396adf7fe6030b28eebf938a5f4b2` unchanged, both local **56/56** and public Worker **56/56** PASS. No live deployment, staging/main/Owner data change. Next §7b unified sign-in, Group ▸ Business ▸ Site context, module/nav/roles/mobile, token CSS and bilingual dictionaries; then §7a Sales 030x.
- **§7b.1 classification COMPLETE:** PR #133 merged canonical trunk `ff4c06b1b2ef4a00bda85652e4947e043fde938a`; root exact 132-file inventory (23 LIVE, 108 TRUNK_UNSHIPPED, 1 TOOLING), 463 LEGACY_FROZEN source references, all 37 Worker preview source pins checked at exact historical commits, including nine draft-head Sales/Mfg sources (replay, not staging). `docs/coordination/FILE_CLASSIFICATION.json`, `tests/core10-file-classification.test.js`, own CI workflow. Exact HEAD `399bedc` 3/3 GitHub Actions SUCCESS incl real Control Port browser gate. No Worker deploy, staging SQL or production changes. **NEXT: §7b.3 bring byte-identical preview shell onto trunk at `apps/central/`, then shared sign-in/context/menu, token CSS + bn/en dictionaries.**
- **Owner-approved §7c legacy quarantine COMPLETE:** PR #131 merged only into canonical trunk at `f92072f22e273e379b001de4cfba80bcd7d7f79d` (2026-11-22). All 463 old IMG-ERP blobs (221 root + 242 `v2/`) moved with original Git blob hashes under `legacy/islamia-erp/`; `docs/coordination/LEGACY_MOVE_MANIFEST_20261122.json` and SHA256 + negative mutation test lock them. 25 unshipped CORE10 HTML views disconnected from old `./config.js` loader; shipped CORE10/module denylist test added. Legacy Pages package/test paths moved. 21/21 exact-head PR CI workflows SUCCESS; PostgreSQL 17 and live Worker local/public `verify.cjs` 56/56 each PASS (CI `45010718551`). Old browser suites use checksum-verified **CI-only** frozen fixtures with both protected Supabase hostnames blocked. No staging migration, database changes, live Worker deploy or `main` merge. Next: §7b steps 1,3,4,5, then §7a Sales 030x.
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

## 5. Next build steps (priority order) — see also §7, §7a, §7b, §7c (latest queue)

- Latest priority: PR #173 is merged and live; complete Bakery T01.01 signed preflight (recipe revision, lot/UOM, pack, shelf life, label profile, real signed acceptance); reconcile #171 without merging obsolete base or overlapping #166.
Latest 2026-11-26: Sales host code integrated (#163); complete hosted signed acceptance and deterministic release. #166 Stock workbench combined CI is pending after conflict resolution. Coordinate #164/#165; never apply unverified or unallocated SQL.

**Owner's 2026-11-22 build sequence overrides the historical ordering below:** §7c legacy move completed via PR #131 (`f92072f`); §7b.1 file classification + exact pin CI merged via PR #133 (`ff4c06b`). **§7b.3 completed via PR #134 (`dc9f9c7`)**; **§7b.4 first navigation slice merged via PR #140 (`d442281`)**, 2/2 mobile, 56/56 local + 56/56 public read-only, Double Audit green. **§7b.4 first signed Group ▸ Business ▸ Site shell context MERGED PR #142 (`d8b69a0`, exact 56 local + 56 public read-only + adversarial security PASS), but not universal SSO or module data filtering. NEXT §7b.4/5 remainder:** per-module signed context propagation, role homes/entitlements and shared token CSS + bn/en dictionaries. Then §7a Sales 030x forward-only security patch and staged apply; only after Sales migrate Finance F3 040x and Manufacturing 050x, followed by Paint, Procurement/QC, Payroll, Assets, CRM. The previously numbered steps remain background/acceptance obligations, not permission to skip this order.
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

- 2026-11-22 agent=ChatGPT: completed §7c IMG-ERP 463-blob byte-identical move to `legacy/islamia-erp/`; PR #131 merged canonical trunk `f92072f22e273e379b001de4cfba80bcd7d7f79d` (build HEAD `01f75b0242e2eb124666f9cd95644a8ee55206a8`). GitHub Actions exact-head 21/21 PASS; PG17 full up/down/up, SHA256 negative guard, legacy Pages tests and unchanged Worker local/public 56/56 PASS (`45010718551`). No deployment or staging/main writes; Owner Business #3 and other staging data still synthetic TEST ONLY. NEXT: §7b FILE_CLASSIFICATION + apps/central shell/UX, then §7a Sales 030x.

- 2026-11-22 agent=ChatGPT: built §7b.1 executable root/source classification, merged PR #133 canonical trunk `ff4c06b1b2ef4a00bda85652e4947e043fde938a` (PR HEAD `399bedc53cfa320aae6df20f32f6ed3307fccc0e`); 132 root files classified, 463 legacy frozen referenced, 37 pinned LIVE paths verified including 9 draft sources. Exact-head 3/3 CI PASS (classification, double audit, real Control Port). No staging, protected Supabase, live Worker or main writes; test data unchanged. NEXT: §7b.3 copy live shell to `apps/central/` with byte-identical 56/56 gate, then shared session/UI and Sales 030x.

- 2026-11-22 agent=ChatGPT: §7b.3 imported pinned live shell, data, runtime and builder to `apps/central/` with exact original source Git objects and sole verifier sentinel path update; merged PR #134 canonical trunk `dc9f9c7eef3d5e78403f148e7fc06d03964c62b6` (PR HEAD `4345b6e4aa7ee593a455ee29dceccf55d61ade7f`). 4/4 exact-head CI PASS; original Worker SHA256 `ba530d45179f9ea146bccb0a04899213a3e396adf7fe6030b28eebf938a5f4b2`, local/public 56/56 PASS, PG17/REV009 PASS. No production deploy, main, staging or protected Supabase change. Demo/signed data remains synthetic TEST ONLY. NEXT: §7b single auth/context/nav/mobile, tokens/bn-en, then §7a Sales 030x.
- 2026-11-22 agent=ChatGPT: checked latest Claude and ChatGPT builder PRs; PaperOps PR #132 and Claude 0207 Purchases stayed isolated. Built §7b.4 first bilingual navigation/mobile slice on branch `build/chatgpt-central-mobile-nav-20261122` (Board B-039), original 11 routes unchanged, Android bottom bar+More, three desktop groups, Escape/active/hash/back integration including real nested-iframe history correction. PR #140 exact head `439032c5fdf6bb8400536003bb59149be2df37b7`, CI `45041736695` complete SUCCESS historical import gate + current-scope provenance + new Playwright 2/2 + local 56/56 + public read-only 56/56, Double Audit `45041736755` SUCCESS; merged canonical trunk `d442281cb73e240d016f0ecf530f531941c47db8`. No staging, Worker deploy, main, protected hosts or signed data writes. NEXT: shared sign-in/context, role-aware shell, design tokens and dictionaries, then Sales 030x security.

- 2026-11-22 agent=ChatGPT: Board B-040, PR #142 built standalone signed CORE10 staging shell Group ▸ Business ▸ Site from canonical `build01_context_v1` read RPC (0117), no new roles/SQL. Fail-closed actor/scope/tenant validation, signout/private iframe purge, delayed-response/account-change race tests, Bengali/English, 390/1440; preserved all existing module permissions and routes. Exact PR HEAD `f9778d3ba161c782e9d56a29739536bc7c056fb8` shell CI `45049736364` SUCCESS (new adversarial browser PASS; local 56/56; public read-only 56/56; historical byte-integrity) and Double Audit `45049736374` SUCCESS. Merged PR #142 canonical trunk `d8b69a0c91ba865e38ac08fd79a33d86a9eb0368`. No staging/Worker/main/IMG/Form/Finance/Stock data change. Known gap: Build01 nonpersisted auth means this is NOT complete module SSO, selection is display-only. NEXT role-aware integration and tokens/dictionaries, Sales security.

- 2026-11-26 integration checkpoint: signed Sales host PR #163 exact head `7ae9f3f4fdd318d9256e740abd1c05f5ee8894ea` passed both Actions (45795728983, 45795729004; full local/public 56/56, Sales lifecycle and exact canonical source). Merged code-only into trunk `affe71cf771d535d158aae9d9353c5ca154d36b5`. Signed hosted business acceptance and Worker release are still outstanding; no posting activation. Stock workbench PR #166 passed dedicated regression and Double Audit at prior head; merged latest Sales trunk into its isolated branch at `ed75b0e6694ce4fbe08d25e7a8d05bc0c086bdb0`, preserving both provenance checks. GitHub mergeable, zero behind; rerun combined exact-head CI before merge. Board B-012-REQ1 updated. Stock/PaperOps PR #164 (0310–0315) and Finance PR #165 (0402–0407) are active integration candidates with failed checks; leave their owners to resolve them, do not duplicate or apply. No SQL/Worker writes in this checkpoint.

- 2026-11-26 agent=ChatGPT: PR #173 fixed, exact three CI PASS, merged and Worker v20 deployed 100%; see §0 release receipt. Next Bakery T01.01.

## 7. Open PR audit and integration queue (2026-11-22, Claude; updated by ChatGPT after §7c)
**Build progress:** Owner legacy §7c PR #131 MERGED `f92072f`, 21/21 exact-head CI PASS (incl PG17, checksum preservation, Pages and live Worker 56/56 local/public); §7b.1 classification PR #133 MERGED `ff4c06b`, 3/3 exact-head CI PASS. §7b.3 app shell exact-source import PR #134 MERGED `dc9f9c7`, 4/4 exact-head CI SUCCESS, deterministic Worker unchanged, 56/56 local/public. §7b.4 navigation-first PR #140 MERGED `d442281`, new mobile+Back 2/2, original local 56/56, old public 56/56 and Double Audit PASS; no deploy. **§7b.4 signed-context PR #142 MERGED `d8b69a0`, CI `45049736364` full PASS and Double Audit `45049736374`; NOT universal SSO, no deployment. NEXT §7b role-aware per-module context + i18n/tokens** (role menus, signed module propagation, CSS tokens + bn/en), then §7a Sales security before 040x/050x; never port an old PR wholesale.
Rule: never merge an old PR wholesale. Old branches (based on `main`, `preview/c10-integrated-20261111-v1` or the
A018 catalog) predate the numbered-migration trunk; their logic must be PORTED as new numbered migrations + tests on
trunk (like B-009 did for A018 inventory). After a port is integrated and green, close the old PR with a link (Owner OK).

**A. Trunk-based, integrate next (in this order, each with full PG17 + its lane CI before merge):**
| PR | What | State vs trunk | Action |
|---|---|---|---|
| #117 → #128 → #130 | F3 AR/AP 0402–0403 + ACL + aging tests (stacked) | not in trunk | rollback test must not assume 0403 newest; then merge stack; cross-lane pin now `dc74cde` (1a60e79) |
| #120 | F3 replay 0402–0405 + Money post | not in trunk; overlaps #117 | pick ONE of #117/#120 (same numbers) via Board |
| #122 | Sales invoice→Money→AR (0305/0406/0407) | not in trunk | needs Sales 0300–0304 + correction-security PASS first; 0305 clash with #121 |
| #121 | Codex integration (D063, Sales, Mfg, host) | 105 of 117 files differ | split: its 0115–0118 already on trunk; renumber its 0305; port remaining pieces |
| #123 / #125 | Stock 0201 (Builder B) / CI replay | mostly in trunk (4 / 7 files differ) | diff the remaining files, port or close |
| #124 | old F3 re-pin | superseded by 1a60e79 | close |
| #119 | NP01 bootstrap proposal (docs) | superseded by 0115–0117 on trunk | close after check |
| #116 / #113 / #114 | old preview branches | superseded by #126 | close |

**B. Old module PRs NOT yet in trunk as numbered migrations (port = new build work, Goal 1 relevant first):**
- #55 A051 Workforce/Attendance/Leave/Payroll, #59 A055 Assets & Maintenance, #65 A057 CRM/Service/Commerce,
  #51 A050 Owner portfolio workspace (UI), #73 A058 QC/lot/expiry/recall (NOT in trunk at all),
  #95 Build05 Paint tint/QC/quotes (paint business!), #97 Build08 procurement kernel (compare 0203/0206 first),
  #96 Build11 FIN-001 voucher (compare 0400/0401 first), #94 Build04 setup profiles + 303-site fixture,
  #103 A064 language modes.
- GOV-002 chain #78–#93, #98, #99 and A008 #69/#71, PACK-01/02 #104/#105: logic already ported into 0007–0019
  (NP01) — verify each feature against trunk tests, then close.
- Deferred by Owner: #77/#75 A025 simulation, #67 research docs, #54 D049 docs, #85 work-order doc, #60 preview v1.
Suggested build order for Goal 1: Sales (fix) → Finance F3 → Paint (#95) → Procurement/QC (#97, #73) →
Workforce/Payroll (#55) → Assets (#59) → CRM (#65).

### 7a. Sales (PR #109) security analysis — 2026-11-22 Claude
Reproduced on PG17 (trunk 98384ab + `git revert 6d24ad8`, DB must be named `core10_np03b_ci`): 10 cases open, 11 pass.
Open: P1-02 fabricated approval id accepted at zero stage (order confirm + invoice validate); P1-01 privileged
UPDATE/DELETE/INSERT on CONFIRMED order header/lines accepted; P2-02 DELETE of a referenced master party accepted;
P1-01 invoice draft/validate accept a tampered or audit-mismatched source.
Fix plan (forward migration in Sales range, e.g. `0310_np03b_sales_security_corrections`; never edit 0301/0304):
1. Any non-null approval id must resolve to an approved `approval_requests` row of the same business/domain and
   source key (`sales-order:<id>` / invoice key); otherwise `SALES_APPROVAL_INVALID`.
2. Immutability triggers on `sales_orders_v1`/`sales_order_lines_v1` when status <> draft (allow only status/version
   transitions done by the RPCs) → `SALES_ORDER_IMMUTABLE`.
3. BEFORE DELETE trigger on `master_parties_v1` when referenced by sales docs → `SALES_PARTY_REFERENCED`.
4. Invoice draft/validate recompute a digest of the order (header + lines) and compare with the payload digest stored
   in the order's canonical confirmation Audit event; mismatch → `SALES_SOURCE_AUDIT_MISMATCH`.
CONFLICT TO RESOLVE: after fix 2, the test's own tamper setup (plain UPDATE of a confirmed order inside SAVEPOINT
`tamper`/`line_tamper`) will itself raise and abort the script. The test needs a reviewed adjustment so the tamper
cases are either expected to be blocked by the trigger (stronger) or simulated with the trigger bypassed by the
table owner in a controlled way. Decide with the Sales lane before changing the test; never weaken assertions.

### 7b. App organization review — 2026-11-22
**Step 1 BUILT/MERGED:** `docs/coordination/FILE_CLASSIFICATION.json` + `tests/core10-file-classification.test.js` + CI; PR #133 `ff4c06b`, 3/3 green. §7c step 2 retired-project guard was built with PR #131. Step 3 BUILT/MERGED: PR #134 `dc9f9c7`, byte-identical preview source import in `apps/central/` with only verifier path adjustment; exact-head 4/4 CI, unchanged Worker SHA and 56/56 local+public PASS. Step 4 navigation-first slice **BUILT/MERGED PR #140 (`d442281`)**: grouped desktop modules, 4+More mobile bar, bilingual labels, Escape and correct browser Back; original shell routes preserved. CI `45041736695` current 56/56 local + old public 56/56 + new Playwright 2/2, historical import gates preserved; Double Audit `45041736755` PASS. Step 4 first signed shell context **BUILT/MERGED PR #142 (`d8b69a0`)**, signed canonical RPC, source/security validation, delayed-response/logout adversarial browser; local/public 56/56 and Double Audit PASS. It is NOT universal module SSO; Setup Build01 and module-selection propagation remain separate. Remainder step 4: role/entitlement homes and propagation. Step 5: design tokens + bn/en dictionaries. Deploy only via handover §4.
Full survey + safe reorganization plan: branch `review/app-organization-20261122` @ `2e4f6bc`,
`docs/development/APP_ORGANIZATION_REVIEW.md` (+ 22 screenshots). Read before any UI/shell/file-move work.
Top steps: (1) FILE_CLASSIFICATION.json + test, (2) test blocking legacy config/v2/old Supabase from live code,
(3) move live shell (site/, build.mjs, verify.cjs) onto trunk under apps/central/ (byte-identical build gate),
(4) one sign-in + Group ▸ Business ▸ Site context bar, regrouped menu, role homes, Android bottom bar,
(5) one design-token CSS + bn/en dictionaries. Moving legacy IMG-ERP files to legacy/ needs Owner approval.
NOTE: Sales 030x must reach staging BEFORE Finance 040x / Manufacturing 050x, or later Sales applies are OUT_OF_ORDER.

### 7c. Owner decision 2026-11-22: move legacy IMG-ERP files (COMPLETED)
**Completed and merged via PR #131 / trunk `f92072f`:** 463 original blobs SHA256-identical, frozen historical Pages paths and tests updated, 25 ROOT CORE10 draft legacy loaders disconnected, live/module guard added; 21/21 exact-head CI success. No staging/deploy or protected project access. Historical Owner-approval checklist below retained for traceability:
1. On a branch from trunk, `git mv` the legacy files (root `index.html`, `owner.html`, `business.html`, `sw.js`,
   `config.js`, `v2/`, and the ~201 non-`core10` root JS/HTML/CSS listed as "frozen legacy" in the review §
   FILE_CLASSIFICATION) into `legacy/islamia-erp/` — content byte-identical, history kept. Do NOT delete anything.
   Do NOT touch Supabase `kbuhnpqooycqbzrfejcs`.
2. Same change: update the legacy-preservation tests and the old Pages package required-file list to the new paths
   (never weaken: they must still prove every preserved file exists byte-identical), and repoint any `core10-*.html`
   that loads `./config.js` to nothing legacy (they must load only CORE10 configs).
3. Add the guard test from review step 2 (no `config.js`/`v2/`/`BOS_CONFIG`/`kbuhnpqooycqbzrfejcs` in live/module code).
4. Full CI green on the branch, `build.mjs` + `verify.cjs` all PASS (live bundle unchanged), then merge into trunk.
Then continue with review steps 1, 3, 4, 5 and the §7 build queue.

### 7d. Trunk RED after §7c legacy move — FIXED by Claude 2026-11-22 (2c8b816, 2778597, 0e4701f, this commit); confirm CI green
Trunk head cb4cbe0 had 6 failing checks, all from tests still reading legacy files at the repo root:
- `site-permission` — `tests/pack01/legacy-source-guard.cjs`: FIXED (reads legacy/islamia-erp, 9/9 PASS).
- `legacy-route-visual` — `tests/pack01/legacy-route-visual.cjs`: `candidate` must serve the legacy app from
  `legacy/islamia-erp/` (index.html blob f2f74144 unchanged) while root-level `core10-control-studio-entry.js`
  still resolves (the legacy index loads it) — e.g. serve legacy dir first, fall back to repo root for core10-* files.
- `isolated-demo-artifact` — `tests/core10-a040-pages-parity.test.js` MISSING_PAGES_DEMO_ASSET:owner.html:
  `internal/core10-pages-package.js` file list must copy `legacy/islamia-erp/owner.html` (+other legacy assets) into
  the artifact at the SAME published paths; keep the assertions.
- `Packaged browser safety and module journeys` — fixture 404 where 200 expected: same packaging path issue.
- `Combined schema / assets` and `Combined schema / intent` — inspect logs (A055 assets / D049 intent browser
  journeys load legacy root assets); same fix pattern.
Rule: change paths/packaging only; never delete or relax an assertion. Run each failing step locally, then push.
- 2026-11-23 agent=Claude: Owner GO "live করো". Built from trunk `2e06b75` `apps/central/build.mjs` (worker sha256 2cfc7865…);
  local verify 56/56 + legacy-guard, legacy-move-integrity, shell-provenance, mobile-nav, signed-context PASS. Deployed Worker
  `core10-central` deployment `9aadd95c-a8af-4f90-956c-ccc76deaae5a` / version `1a99371f-2cf2-4546-bc18-321f76224a7e` (100%);
  public verify 56/56 PASS. Rollback: version `65f60417-5b76-4524-830a-c74018b7ff58` (prior live, source bytes backed up).
  Live now includes §7b.4 mobile bottom nav + Group▸Business▸Site signed context (#140, #142). No staging/DB change.
