# Claude lane — restartable handoff (trunk / NP02 Control)

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
- **B-011 master data**: contract `docs/coordination/NP02_B011_MASTER_DATA_CONTRACT.md` (`54607f1`, CI green). Next: 0150 tables extending `core10.items`.

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

Claude 0100–0109 (used to 0106) and 0150–0199 (B-011). ChatGPT NP01 0013–0099 + 0110–0149, NP06 0400–0499. Codex NP03B 0300–0399, NP05A 0500–0599.
Hosted apply order when GO is given: 0013–0019, then 0100–0106.

## Blocked / waiting on Owner GO (GO-2, GO-3 not authorized)

- B-022: hosted staging apply + signed matrix rerun with Control scenarios.
- Level 2 preview (anon key in config, Cloudflare link to staging).

## NOT_CONNECTED

- Master data port (B-011, 0150+) — not started.
- Stock port for NP03A (B-012) — planned.
- Control bindings for NP03B/NP05A/NP06 RPCs — their lanes register them as `pending` until bound.

## Next safe step

B-011 master data in 0150–0199. Before each increment: re-read the Board and open PRs (#107, #108, #109) for overlaps.
