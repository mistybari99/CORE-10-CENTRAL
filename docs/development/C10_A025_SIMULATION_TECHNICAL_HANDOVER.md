# C10-A025 Simulation Engine — Technical Handover (DRAFT, isolated, advisory-only)

Everything a future agent needs without the chat. **Scope is APPROVED; isolated draft coding is AUTHORIZED (REV-010); this implementation is NOT merged, NOT deployed, NOT integrated, NOT signed-auth verified, release DEFERRED.**

## 1. Identity
| Item | Value |
|---|---|
| Repo | `mistybari99/CORE-10-CENTRAL` (no new repo/app) |
| Draft PR | **#77** `DRAFT C10-A025 — Enterprise Simulation Engine (isolated, no rollout)` → base `main` |
| Branch | `ccr-527e5d03-bcl99t` (Claude-owned; no other agent's branch touched) |
| Base SHA | `c39052910758ca285a7a4d56e9c4f4873cb7d99c` |
| Code commits | `b478696` (engine/tests), `972d30c` (SQL/UI/CI); final PR head + CI run links are on PR #77 (a file cannot contain its own commit hash) |
| Governing docs | PR #75: mandate, live reconciliation, R081–R114 JSON · Decision Book rows C10-D039/D040, NEXT ACTIONS C10-A025, REV-007/009/010, R081–R114, R123–R129, A046/A048/A049/A050/A054/A022/A023 |
| Live Book read | Drive connector returned tab structure and sample rows only (cell bodies of rows 37/38/26/14 etc. were not exposed). Record contents were therefore taken from the verified PR #75 reconciliation files. **Re-read the live Book on resumption.** |

## 2. Paths added (nothing else is modified)
```
modules/simulation/
  index.js                       entry, registers models
  lib/    decimal.js sha256.js units.js kernel.js analysis.js context.js demo-data.js
          scenario.js decisions.js reports.js quick.js coverage.js
  models/ spec.js core.js(M01-M08) finance.js(M09-M14) ops.js(M15-M20) not_built.js(X01)
  sql/    c10_a025_fixture_v1.sql  c10_a025_scenarios_v1.sql  c10_a025_rollback_v1.sql
  ui/     lab.html lab.js quick.html quick.js ui.js ui.css
  dist/   c10-sim.bundle.js c10-sim-examples.js        (GENERATED)
  data/   registry-lock.json requirements-index.json
  tools/  build-bundle.js registry-lock.js registry-sql.js gen-coverage-doc.js
tests/c10_a025/  *.test.js  golden_reference.py golden.json pg_harness.js run-all.js
.github/workflows/core10-a025-simulation-ci.yml
docs/development/C10_A025_SIMULATION_{DRAFT_DECISION_LOG,TECHNICAL_HANDOVER,MODEL_COVERAGE,EXTENSION_GUIDE}.md
```

## 3. Run it
```bash
node tests/c10_a025/run-all.js               # everything (needs python3, psql+PostgreSQL binaries, Playwright)
node tests/c10_a025/run-all.js --no-pg --no-browser   # pure engine only
# start the UI (static, no build step):
PORT=8099 node tests/e2e/static_server.js    # then open
#   http://127.0.0.1:8099/modules/simulation/ui/lab.html     (Simulation Lab)
#   http://127.0.0.1:8099/modules/simulation/ui/quick.html   (Quick Simulation harness)
# after editing engine/ui sources:
node modules/simulation/tools/build-bundle.js && node modules/simulation/tools/registry-lock.js --write && node modules/simulation/tools/gen-coverage-doc.js
python3 tests/c10_a025/golden_reference.py --write   # only when fixtures/reference formulas change on purpose
```
PostgreSQL tests: set `PGHOST/PGPORT/PGUSER[/PGPASSWORD]` to use an existing **disposable** server (CI uses `postgres:17`); with none set the harness starts a throwaway local cluster (root → `runuser postgres`). The harness only ever creates/drops database `c10_a025_persist`.

## 4. Architecture in one page
`runModel(id, version, rawInputs, ctx)` → normalise (typed, unit-converted, kinds actual/estimate/assumption/scenario/unknown) → pure `calculate` over `Dec` → envelope `{outputs, exact, feasibility, breakdown, warnings, assumptions, limitations, dataQuality, provenance, inputHash, formulaHash, sideEffects:[]}`.
The **Lab** (`ScenarioService.run`) and **Quick** (`createQuickSimulation().run`) both end in that one function; a parity test compares model, version, formula hash, input hash and outputs for 11 contexts, and a browser test compares the rendered tables.
Scope: `MockAuthority.resolveContext` derives tenant from the business, rejects a client-supplied tenant, and only then yields capabilities. Missing/other-tenant/revoked/anonymous/platform-operator ⇒ `FORBIDDEN`/`NOT_FOUND` (no existence leak).
Persistence (`c10_sim`): drafts, immutable runs, append-only decision events/annotations/proposals, hash-chained audit, immutable registry. All writes via 10 `SECURITY DEFINER` RPCs.

## 5. Integration points (what to wire, in order, and what NOT to do)
1. Replace `c10_sim.business_source/site_source/grant_source` views with views over the canonical A018 hierarchy and A021/A034 effective capability service. Keep the capability names or map them. **Do not** create a second role authority.
2. Replace `request.jwt.claims` actor with the real signed claim path only on the separate staging project; run the same matrix there. Synthetic claims prove SQL logic, not GoTrue.
3. Put a trusted recompute step in front of `record_run` (see Known defects #1).
4. Source adapters (read-only, signed scope): A048 inventory, A049 purchase→production→sales, A050 portfolio, A054 payroll policy, A022/A023 finance (**manual_unverified** ⇒ seeds only). Use `InputValue{kind:'actual', sourceReference, observedAt}`; stale sources are flagged by the provider contract.
5. Mount the Quick panel through the owner placement service only where the module is enabled **and** the backend authorises the operation (`quick.available`). No live screen was modified here.
6. Approval: implement a real adapter behind `MockApprovalAdapter` using the canonical request/approval service; never reuse the module-visibility mutation path.

## 6. Test evidence (local session, to be confirmed by CI on PR #77)
| Check | Result |
|---|---|
| Independent python reference vs engine | 46 fixtures, 230 values identical; hand anchors: loan 500k/12 %/12 m = 44 424.39, IRR(−1000,400×3)=9.701026 % |
| Property tests (seeded) | 60 iterations: scale invariance, monotone break-even, loan principal conservation & zero closing balance, cash conservation |
| Scenario/security (JS) | 13-actor matrix, SoD, revision conflict, idempotent retry, immutable runs, audit tamper detection, CSV formula-injection, redaction, no-side-effects hash on 7 canonical sentinels |
| PostgreSQL 16.15 | 15-actor RLS/RPC matrix, direct DML denied, concurrency (exactly one of two same-revision writers wins), immutability, advisory constraints, audit chain, sentinel hashes unchanged, rollback leaves stand-ins intact; 4 mutation checks all killed |
| Chromium | 303 checks × 390/768/1440: a11y names, keyboard, BN/EN, offline, XSS-inert names, empty/unauthorized/error states, no horizontal overflow, Quick == Lab for 5 contexts, no non-local network |
| Bench (measured) | 320-site consolidation 9.7 ms; 12 scenarios 6.5 ms; 99-run optimisation 32.7 ms; 25 DB RPC creates 867 ms incl. process spawn. **300+ site DB scale NOT measured** |
Screenshots: CI artifact `c10-a025-screenshots`; locally `tests/c10_a025/artifacts/` (git-ignored).

## 7. Known defects / limitations (honest)
1. **Trust boundary:** DB checks formula hash + input snapshot but does not recompute results (IMPL-009). Smallest next security step.
2. UI persistence is browser `localStorage` only; not connected to SQL.
3. PostgreSQL **17** is verified by CI only; local runs used 16.15. Functions use no 17-specific features.
4. Accessibility: automated label/keyboard/overflow checks only; **no real screen-reader or Bangla-shaping device review**. Charts are SVG with `role=img` plus the exact table.
5. BN covers UI strings, model titles, explain text and field/output labels; formula text, assumptions and limitations are English.
6. M18 partial (no verified rate source). U14 and U18 not built. U16 is a contract + mock. R086 licensing is design-only.
7. Industry demos are model-example based (sweets/bakery, paint & wholesale, construction, loan/investor, consolidation); the 10 canonical industry packs are not each built.
8. Optimisation is a bounded grid (≤3 variables, ≤5000 runs), not an LP/MIP solver. Reverse goal is single-driver monotone bisection and refuses non-monotone cases.
9. Series ≤120, lists ≤400 rows, sensitivity ≤400 runs — deliberate bounds.
10. The live Decision Book could not be re-read at cell level (see §1).

## 8. Next smallest merge-independent step
Add a trusted recompute function (Node edge function or SQL-callable service) that re-runs `runModel` for `record_run` and rejects mismatching outputs; extend `persistence.test.js` with a forged-result negative. This closes the only known integrity gap without touching any other package.

## 9. Rollback and upgrade
Rollback: `psql -f modules/simulation/sql/c10_a025_rollback_v1.sql` (drops only schema `c10_sim`; the test proves canonical stand-in tables are unchanged). Code rollback = close PR #77 / delete the branch; nothing else references it.
Upgrade protocol: follow `C10_A025_SIMULATION_EXTENSION_GUIDE.md` (new versions, never edit published ones; regenerate lock, bundle, coverage doc, goldens).

## 10. Decision Book / NEXT ACTIONS update — **NOT WRITTEN** (connector cannot edit sheet cells)
Paste-ready text for **NEXT ACTIONS row 26 (C10-A025)**, evidence column. Do **not** change status to Approved/Ready/Built:
> `2026-11-12 CLAUDE DRAFT EVIDENCE: Draft PR #77 (branch ccr-527e5d03-bcl99t, base main c390529). Isolated engine code: M01–M20 registry (19 coded+tested, M18 partial, X01 research_only), 46 golden fixtures verified by independent python reference, scenario lifecycle + advisory-only gateway, c10_sim PostgreSQL schema tested on disposable PG, Lab + Quick UI tested at 390/768/1440. U14/U18 not built; U16 contract-only; signed-auth, A021–A023 canonical wiring, A048–A054 sources, server-side recompute and licensing NOT done. State remains: ENGINE DRAFT ONLY — NOT MERGED / NOT DEPLOYED / NOT INTEGRATED; release DEFERRED pending original Owner gates.`
Also append to DECISION REVISIONS only if the Owner wants a record; **no new D/R/REV/A IDs were created.**
