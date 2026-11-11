# CORE 10 Unified Master Build Roadmap

**Planning date:** 2026-11-11. Registry trace rule: every feature remains in `UNIVERSAL_CAPABILITY_REGISTER.{json,csv}`; deferred/research-only rows are not dropped. This roadmap does not authorize production, paid services or main merge.

## Ordered execution

| Stage | Scope and reuse | Exact outputs/tests | Gate / registry coverage |
|---|---|---|---|
| B0.1 current slice | deterministic synthetic factory on current preview ancestry; reuse A046 identities | `internal/demo-factory/`, `tests/demo-factory/`, dedicated workflow; determinism, 303 sites, DR=CR expected math, provenance | implemented locally; covers DEMO-001 and fixtures for all rows |
| B0.2 reality repair | fix/reconcile PR #60 current-head public served-set and browser evidence without changing Claude source | exact-head preview/static/browser checks, public runtime smoke, source-status labels | Owner preview/review; no production data |
| B0.3 parity | read actual completed Claude A052–A057 outputs | `POST_CLAUDE_PARITY_REVIEW.md`, overlap/file ownership/test matrix | only after completed tested SHA exists |
| B1 scope/auth | reconcile A018/A019/A021 with PR #22 A034; explicit grant list | disposable PG17 + local PostgREST; then authorized GoTrue role matrix | GOV-001/002; `org_scope_on` remains off until all gates |
| B1 setup/legacy | idempotent Quick/Advanced setup and immutable legacy crosswalk | retry/rollback, 2 tenants, 303-site measured queries, legacy ID parity | SETUP-001/MDM-001; REV-009 |
| B2 inventory/docs | evolve A048/A049 for partial documents, reservation, in-transit, lot/serial/expiry/count | golden chain commands, negative stock/replay, scan/mobile tests | INV-001/002, PROC-001, SALES-001 |
| B2 finance | canonical typed balanced journal, AP/AR/cash, certified COGS/returns/close | per-document DR=CR, source/reversal, missing-cost, closed-period and reconciliation tests | FIN-001; blocks partner/profit claims |
| B2 partner fix | replace all-location business calculation through canonical scoped resolver | caller/grant inventory, regression, business/tenant negatives | PARTNER-001; separate ownership/release review |
| B3 first packs | independent paint/construction or restaurant pack over shared core; preserve Islamia | domain positive/negative and report trace tests | FOOD/PAINT/PROJ; no cloned ledgers |
| B4 people/assets | integrate verified Claude workforce/payroll/assets output | parity adapters and signed role tests | HR-001/ASSET; no duplicate work-order/permission store |
| B5 integrations | merge/reconcile PR #27, then mock Drive export lifecycle | mock timeout/conflict/revoke/quota/secret tests | INTEGRATION/DRIVE; live OAuth separately approved |
| B5 offline | bind PR #23 bounded intents to typed commands | revoked/closed period/two-device conflict and user recovery | OFFLINE-001 |
| B6 hardening | source-linked reports, accessibility, root/`v2` parity, performance, DR | 390/1440 keyboard/BN-EN; 303-site load; encrypted restore drill | REPORT/UX/DR; no capacity claim before metrics |
| B7 deferred | commercialization A024; simulation A025; regulated sectors | separate approved plans and professional review | remains deferred/research-only |

## Build ownership

- Codex Issue #68 owns `docs/strategy/`, `internal/demo-factory/`, `tests/demo-factory/`, and its workflow.
- Claude owns A052–A057 namespaces until completed parity review.
- Shared engine work requires explicit integration ownership; never edit another active branch in place.

## Acceptance per slice

Each slice records Decision/Requirement/Action link, source paths, branch/commit, exact test result, truth level, rollback, data lineage, known gaps, Decision Book row and next gate. Synthetic SQL roles/HMAC JWT, GoTrue stage, deployed preview and operational certification are always reported separately.

## Registry traceability

- P0 shared core/platform: B0–B2 and B6.
- P1 packs/adapters: B3–B5.
- P2 vertical expansion: after shared invariants and a first independent pack.
- Research-only/regulated: retained in registry; requires jurisdiction/legal/professional approval.
- A024/A025: retained and explicitly deferred.

No registry row is silently omitted. Machine validation enforces 116/116 source-candidate reconciliation and `unexplained_omission_count: 0`.
