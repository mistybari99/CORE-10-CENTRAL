# Claude lane — restartable handoff (trunk / NP02 Control)

## SESSION A STATE — 2026-11-22 (GO-2 done; read this first)

New Session A (replaced the 2026-11-21 one). Owner re-confirmed GO-2 and GO-3 (after staging) in this session.

**GO-2 staging (rhrqhbyzrhaafynfhdaf): DONE 2026-11-22.**
- Backup first: `docs/development/staging-backups/2026-11-22-pre-go2/` (core10 functions, ACLs, triggers, policies, views, columns, constraints, all rows; synthetic data only). Supabase daily backup is the second net.
- Rehearsal: disposable PG17.12 with 0001-0012 + the real staging rows loaded, then the exact 19 payloads: 19/19 OK, registry gate PASS (17 enforced / 7 exempt / 6 pending).
- Staging transaction semantics proven first (a failing `begin; create ...; 1/0; commit` left nothing behind).
- Applied 0013-0019, 0100-0106, 0110-0114 in numeric order, one transaction per file = file text + `core10.schema_migrations(version,name,checksum)` row, sha256 of file bytes (run.sh semantics). Order guard checked before every file; ledger checksum re-read after every file. Log: `apply-log.txt`.
- After: ledger 31 rows, max 114. Registry gate PASS on staging (17/7/6, same as rehearsal). Catalog: 0 SECURITY DEFINER without search_path, 0 anon execute, 0 tables without RLS, 0 authenticated direct DML. Data intact (audit 6, members 4, sites 3).
- Supabase advisors: 48 "authenticated can execute SECURITY DEFINER" WARN + 6 "RLS no policy" INFO = intended RPC-only design (each RPC checks scope itself; RPC-only tables deny direct access). **Owner action:** Auth "leaked password protection" is OFF (dashboard setting, Owner's call before real users).
- NOT applied (by design): 0115+ / 0150+ / 0200+ / 0400+ / 0500+. Next hosted version must be > 0114 in numeric order; 0115-0118 (PR #121) must be settled via the Board first.

**GO-3 live: DONE 2026-11-22.** Branch `preview/core10-central-level2` @ `887b395`, Draft PR #126 (base = Preview branch, which was left untouched; the Preview session is idle/completed, so Session A was the single releaser). Worker `core10-central` deployment `84095bdd…` / version `38141fd4-09de-4f90-8f81-e12a850597b4`; rollback version `025cf3a1` (source in `rollback/`). `#/control` = real Owner Control Centre, signed staging sign-in; CSP connect-src only self + staging. Live verify 49/49 (390/1440, bn/en, headers, CSP, staging Auth refuses wrong password). NOT VERIFIED: successful Owner sign-in (Owner's own account). Follow-up: shell banner says "nothing saved" — wrong for signed `#/control`.

**Owner account + ownership model (Owner directive 2026-11-22).**
- Goal 1 (now): Owner's own businesses. Goal 2 (later, A024 deferred): sell to outside customers (single business up to many), each customer fully isolated, Owner keeps platform control.
- Staging: Owner auth user confirmed; new tenant `core10-owner-group` (id 1) + legal entity "CORE10 Owner Group" (id 1); Owner = `tenant_owner` there (removed from sample tenant 9801). No password set yet: Owner sets it in the SQL editor (we never hold it). Everything else on staging stays synthetic demo personas.
- Gap: no platform-level role exists (top role = tenant_owner). Planned design (needs Owner decisions, NOT built): `platform_operator` above tenants: create/suspend tenants, module/plan licensing, usage/health metadata, NO access to customer business data except time-boxed, customer-granted, audited support access; own migration range + cross-tenant negative tests.

Next: integration items (Sales #109 security, F3 #117 rollback test, 0305 double claim, crosslane F3 pin).

## SESSION A STATE — 2026-11-21 (superseded by 2026-11-22 above)

Owner GO (2026-11-21): full build authority incl. GO-2 staging and GO-3 live, "check everything first".
Re-alignment plan (Drive): https://docs.google.com/document/d/1gqWHIDdB81H2-VZqce2E5VbRSZOTOgGraszGt5yeDjc/edit
Goal: one platform, many businesses (10), 100-400 branches/factories/warehouses each, full Owner control; IMG-ERP-SG untouched.
Session split: A = this trunk (integration, staging, live). B = build/claude-np03a-stock (0201-0299, P1/P2/P4/P5), never pushes trunk.

Trunk head 6d24ad8. Integrated (code only, nothing hosted beyond 0001-0012):
- NP01 0110-0114 (@69143ff), Manufacturing 0500-0504 (@7e39b75), Finance 0400-0401, Master 0150-0153, Stock 0200, Control 0100-0106.
- Sales 0300-0304 merged (6fa70ba) then REVERTED (6d24ad8): tests/np03b/correction-security.sql has 10 open security cases (also failing on PR #109's own head). Re-integrate only when it passes; fixes must be forward migrations, never edits to 0301/0304.
- Finance F3 0402-0403 (PR #117 @53ee374) held: its rollback test assumes 0403 is the newest migration (run.sh down = newest). Asked on #117.
- crosslane CI (core10-np06-crosslane-ci) keeps only F3, still pinned 3d128dc (stale): runs only when its own files change.

Staging (rhrqhbyzrhaafynfhdaf) readiness (read-only audit): ledger has 0001-0012, checksums match, 8 auth users, small data.
PLAN: apply ONLY 0013-0019, 0100-0106, 0110-0114 now (19 files). Reason: other branches hold 0115-0118 (PR #121, Codex, in NP01 range - lane violation), 0201-0202 (B), 0305 (two different files: PR #121 and #122), 0402-0407, 0505; applying any higher version would make those OUT_OF_ORDER.
Apply per file in order: file text + insert into core10.schema_migrations(version,name,checksum=sha256 of file bytes) in one transaction (as run.sh). Backup first: read-only snapshot of core10 DDL (functions, triggers, policies, views) + row dumps; Supabase daily backup as second net. 0014/0013 headers say "no hosted apply"/"runner only" - covered by Owner GO-2.
Then update docs/coordination/MIGRATION_RESERVATIONS.json persistent_databases.

Live (GO-3) readiness: worker core10-central serves version 025cf3a1 (rollback target; earlier 9a1c6aaa, b1d80c36), built from preview/core10-central-owner-app @243e137 (replay data, CSP connect-src 'none'). Level 2 needs: staging migrations, publishable key in core10-control-centre-config.js, build.mjs FORBIDDEN list allow config/owner-control/master-data, CSP connect-src 'self' https://rhrqhbyzrhaafynfhdaf.supabase.co, Supabase Auth site/redirect URL = worker URL. Never bundle config.js, v2/config.js, index.html/owner.html, core10-stocktake-offline.html, core10-stocktake-preview.js (IMG-ERP-SG). Coordinate with the Preview session (PR #113 stale) - one releaser.

Coordination debt: 0305 double-claimed (PR #121 vs #122); 0115-0118 in NP01 range by Codex; branch build/chatgpt-laneb-zero-stage-guard edits 0301/0304 in place (checksum drift risk); PR #122 conflicts with trunk; Board rows B-012/B-013/B-014/B-015 stale.


Per Owner directive issue #110. Resume from the last pushed SHA without chat history.

| Item | Value |
|---|---|
| Branch | `ccr-15ed11dd-n3hw5h` (trunk) |
| Draft PR | #106 → `preview/c10-integrated-20261111-v1` |
| Trunk head | `c4205e7` = merge of PR #107 (NP01 @ `32dfb63`) under Owner GO-1; exact-head CI: see Board B-025 |
| Local-only / uncommitted work | none |
| Deployed / hosted | **nothing new.** Staging `rhrqhbyzrhaafynfhdaf` holds 0001–0012 only. No Cloudflare publish, no main/preview merge. IMG-ERP-SG untouched. |

## Done on this branch (CODED + TESTED in disposable PG17 and CI)

- **B-010 Control port**: migrations 0100–0102 (tables, RPCs, seed: 9 features, 21 registry rows).
- **B-023 registry coordination**: 0103 evidence columns + promotion, 0104 `control_audit_v1`, 0106 promotion of `decide_approval` / `withdraw_typed_approval_v1` (only once ChatGPT's 0017–0019 bindings exist; post-0102 promotion; `OUT_OF_ORDER` guard in `internal/migrations/run.sh`).
- **B-021 Owner Control Centre**: 0105 bilingual labels; `core10-owner-control-{client,centre,centre-ui}.js`, `.css`, `.html`, `core10-control-centre-config.js` (anon key empty until Level 2 GO); browser test 19/19 at 390/1440.
- **B-024**: NP02 e2e and browser tests check the 9 baseline feature keys, not catalog size (unblocks NP06 PR #108).
- **CI infra**: A038 and A021–A023 PostgREST readiness loops now wait past the 503 schema-cache warm-up (fixed a race seen on run 43917399474).

- **B-025 GO-1 integration**: PR #107 merged into trunk at `c4205e7` (GitHub marks #107 merged; `build/chatgpt-np01` left intact). Pre-merge gates on disposable PG17.12, combined tree: 27/27 CI-mirror steps; catalog 0 SECURITY DEFINER without search_path, 0 anon/PUBLIC execute, 0 tables without RLS, 0 authenticated direct DML.

Registry state on trunk now: 3 enforced (publish_approval_policy_v1, decide_approval, withdraw_typed_approval_v1 — each calls control_check_v1) / 7 exempt / 11 pending.

Known limitations carried in from NP01 (ChatGPT lane, still theirs to finish): B-006/B-007 signed GoTrue acceptance pending; B-008 five GOV-001 partials, host UI and signed setup activation open; 11 registry RPCs still pending Control binding (0110–0149). Nothing is marked enforced without a real `control_check_v1` call and a passing CONTROL_DISABLED test.

- **B-009 drift gate** (`ee9e85c`, all PR #106 checks green): `tests/migrations/b009-legacy-drift.sh` compares old installer chain vs numbered migrations (tables, columns, constraints, indexes, policies, grants, functions, triggers); reviewed list `tests/migrations/b009-accepted-drift.tsv` = 61: 53 GAP_B012 (A018 inventory engine never ported, NOT_CONNECTED until B-012; remove lines when ported), 7 HARDENED, 1 EXTENDED. CI self-test proves unrecorded drift fails. (Commit message says 62/8; 61/7 is correct.)
- **B-011 master data**: contract `docs/coordination/NP02_B011_MASTER_DATA_CONTRACT.md` (`54607f1`, CI green).

- **B-011 0150** (`fe1c6b6`, CI green): master tables extending `core10.items`; e2e `tests/migrations/np02-master-tables-e2e.sql` (18 negatives).
- **B-026 / GO-F1**: Finance PR #108 (@ `88a2964`, migration 0400) merged into trunk at `de67402` (code only). Combined PG17 trunk + #108 + NP01 #111 (0110/0111) passed before merge. B-013 pack NOT complete (ChatGPT Build 2 owns Increment 2).

- **B-011 0151** (`0c959b7`): 9 Control-enforced master writers (`master_save_*_v1`; can_manage = tenant/business owner only; version 0=create; request-key replay; canonical audit) + internal ports `master_validate_sales_order_v1` (NP03B), `master_uom_convert_v1` / `master_item_usable_v1` (NP05A). Test `tests/migrations/np02-master-rpc-e2e.sql`. Remaining B-011: scoped read RPCs for UI, two-session race script, Master UI.

- **B-011 0152**: scoped read RPCs (`master_list_items_v1`, `master_get_item_v1`, `master_list_categories_v1`, `master_list_uoms_v1`, `master_list_parties_v1`, `master_list_price_lists_v1`, `master_get_price_list_v1`, `master_find_barcode_v1`): STABLE, can_see_business, MASTER_SCOPE for hidden/missing business, keyset pages ≤200, literal search. Tests in `np02-master-rpc-e2e.sql`.

- **B-011 0153 + race**: `tests/migrations/np02-master-race.sh` (real concurrent sessions released together by an advisory-lock barrier; 6 scenarios). It found a same-key replay race in 0151; 0153 adds a per-(business,key) advisory lock. Without 0153 the race test fails (verified).

- **B-011 Master Data UI**: `core10-master-data.html` + `core10-master-data-client.js` / `-ui.js` / `.js` / `.css`, link in the Central shell (`core10-control-studio-entry.js`, Owner only). Tabs items/parties/prices/units, search, paging, detail, create/edit item and party (owner/business owner), stale-version and duplicate errors, manager read-only, NOT_CONNECTED banner (B-012 stock, NP03B, NP05A, NP06 AR/AP). Same CORE10-staging/loopback gate and empty key as the Control Centre (NOT_CONNECTED until GO-3). Browser test `tests/control-centre/master-data-browser.cjs` 9/9 at 390/1440, bn/en.

- **B-012 increment 1** (`6396f54`): `0200_np03a_inventory_engine` ports the A018 inventory engine (balances, paired transfers, reconciliation view); `post_stock_event`/`transfer_stock_v1` internal-only, tables RPC-only, existing movements backfilled. Closes all 53 B-009 GAP_B012 lines. Test `tests/migrations/np03a-inventory-e2e.sql`. Next: 0201 A048 inventory command RPCs with Owner Control (`inventory.*`), registry, race.
- **GO-F2**: Finance PR #115 (0401 reversal @ `1601518`) merged into trunk at `532bd36` (code only); combined trunk + #115 + NP01 #111 (0110–0112) 20/20 PASS before merge. F3 PR #117 (0402–0403) NOT integrated; Finance builder asked to re-sync it.

**Hosted-apply order blocker:** no 0150/0400 on any persistent DB until NP01 0110–0149 are integrated + applied in order or formally closed (`run.sh` refuses OUT_OF_ORDER). NP01 #111 currently holds 0110–0111.

## Tests to rerun

```
node tests/migrations/migration-contract.test.js
bash internal/migrations/run.sh up && psql -f tests/migrations/np02-control-e2e.sql
psql -f tests/migrations/control-registry-check.sql
bash tests/migrations/control-race.sh
node tests/c10_np02_owner_control_client_v1.test.js
node tests/control-centre/owner-control-centre-browser.cjs
```
CI source of truth: `.github/workflows/core10-b010-control-port-ci.yml`.

## Migration ranges (`docs/coordination/MIGRATION_RESERVATIONS.json`)

Claude 0100–0109 (used to 0106), 0150–0199 (used to 0153), 0200–0299 (used to 0200) and 0150–0199 (B-011). ChatGPT NP01 0013–0099 + 0110–0149, NP06 0400–0499. Codex NP03B 0300–0399, NP05A 0500–0599.
Hosted apply order when GO is given: 0013–0019, then 0100–0106.

## Blocked / waiting on Owner GO (GO-2, GO-3 not authorized)

- B-022: hosted staging apply + signed matrix rerun with Control scenarios.
- Level 2 preview (anon key in config, Cloudflare link to staging).

## NOT_CONNECTED

- Master data port (B-011): tables 0150 + writers/ports 0151 CODE_INTEGRATED on trunk (CI green at `0c959b7`); read RPCs, race test and Master UI in progress. NP03B/NP05A must still rebind their placeholders to the 0151 ports in their own lanes.
- Stock port for NP03A (B-012) — planned.
- Control bindings for NP03B/NP05A/NP06 RPCs — their lanes register them as `pending` until bound.

## Next safe step

B-011 UI complete: forms for items, parties, units (+conversions), price lists (+prices), variants, barcodes; developer dependency banner removed (only a one-line stock note in item detail). Browser test 13/13. Shell navigation: owner header link (legacy `is_owner`) plus a per-business link in the business workspace (only for the validated current business in the user's own list), `core10-master-data.html?biz=N`. Both are navigation only: the page derives every permission from signed CORE10 `build01_context_v1`/`can_manage`; `?biz` only pre-selects among businesses CORE10 returns. Tests: `tests/control-centre/shell-nav-browser.cjs` 10/10, master-data browser 17/17 (owner, business owner, manager, other tenant, foreign ?biz). BLOCKED until GO-3: the shell itself still runs on the legacy BOS backend (`config.js`), so link visibility cannot yet use canonical CORE10 roles; this needs a signed CORE10 session in the shell. Next: B-012 stock port (0200+) on Owner direction. Before each increment: re-read the Board and open PRs (#109, #111, #112, #115) for overlaps.
