# CORE 10 CENTRAL — CURRENT VERIFIED BUILD HANDOFF
**Checkpoint:** 2026-11-11 (Asia/Dhaka)
**Purpose:** precise continuation of the one existing ERP build, not another Decision Book, duplicate backlog, released app or approval to modify production.
**Authoritative policy:** [single Master Decision Book](https://docs.google.com/spreadsheets/d/1IYzGBtUVNjah31cPVSFHkzgO7P093jTfZS0CopWrDxs/edit). Re-read its nine tabs at each new session; latest Owner clarification and approved policies prevail over old snapshot documents.

## Repository and last tested code
- Repo: https://github.com/mistybari99/CORE-10-CENTRAL
- Active cumulative feature branch: `feature/c10-a018-foundation-catalog-v1`, existing Draft [PR #7](https://github.com/mistybari99/CORE-10-CENTRAL/pull/7), UNMERGED. At handoff verification, build/test HEAD before this documentation commit: `dd62658fe6acf110d817c61d0199c59764f918dd`, mergeable, base main `c39052910758ca285a7a4d56e9c4f4873cb7d99c`.
- At exact pre-handoff tested HEAD: **24/24 GitHub Actions workflow runs SUCCESS**, including two C10-A043 placement CI runs; the earlier unrelated finance PostgREST `503 PGRST002` was rerun successfully. THIS FILE UPDATE creates a NEW branch HEAD; **re-read PR HEAD and run status** before claiming exact latest SHA fully tested.
- Other historical Draft PRs #21 COGS, #22 access, #23 offline, #27 integrations and #20 hierarchy HOLD: inspect their current overlap and merge state; never blindly merge.
- Only PR code and synthetic/disposable CI tests are proved; **no assumption of live Supabase migration, real signed-in cross-tenant E2E, or production activation**.
- Public Pages publishing source remains unverified in available connector; GitHub Actions passing is not a live deployment.

## Owner-approved decisions and newest business-neutral controls
- `D001–D045` (39 approved recorded policies); `R001–R123`; `NEXT ACTIONS` through `C10-A043`; `CHANGE LOG` through `C050`; `AUDIT EVIDENCE` through `E050`; `DISCUSSION LOG` through `DISC-011`. These are in ONE Google Book, not separate documents. Recheck latest rows on resumption.
- **C10-A042:** Universal Owner Control Studio, all industries. 18 universal capability definitions, 10 non-disableable safety invariants, OFF/ON hierarchical previews, role/user explicit DENY and expiry, visibility, change proposal and draft micro-engine descriptors. Source `internal/universal-control-studio/control-catalog-v1.json`, `control-studio-v1.js`; `docs/architecture/CORE10_UNIVERSAL_CONTROL_STUDIO_V1.md`. Pure JS contract, no persistent settings or live UI.
- **C10-D045 / R123 / C10-A043:** Universal Studio remains ALWAYS available; each eligible control is independently placeable per Business in **Central Only / Business Only / Both / Hidden from ordinary menus**. Business-only/hidden controls remain discoverable to authorized Owner via Central registry. Placement changes interface location only; no duplicate control data, grant tables, ledger, audit history or independent engine.
  - Different businesses may have independent effective ON/OFF values and UI placements.
  - Local edit authority separately configurable: `central_only`, `business_owner`, `request_approval`. Actual edits always need signed server checks and one canonical audit/history.
  - Source `internal/universal-control-studio/control-placement-v1.js`, `docs/architecture/CORE10_CONTROL_PLACEMENT_V1.md`, `tests/c10_a043_business_control_placement.test.js`. Dedicated [A043 CI success](https://github.com/mistybari99/CORE-10-CENTRAL/actions/runs/42982369954). Pure contract/proposals only, `canExecute:false`.
- **C10-A038–A041:** Physical Stocktake backend SQL/HTTP tests + Owner/Staff demo UI, read-only bridge and safe downloadable/offline preview. Demo != live stock system.
- **C10-D041/D042/D043/D044:** full real ERP end-to-end build and preservation of historical customized business ERP; GitHub-first schema/source with shared handoff; safe progressive frontend UI release may proceed after verified publishing source, appropriate CI and rollback. Impactful production DB/security/stock/finance changes require real readiness evidence and separate explicit release authority.
- **Critical Owner correction:** Owner deferred *real disposable Supabase staging test*, not **Production Stock Activation**. Do not say or imply Owner postponed production activation. Activation remains **pending readiness verification**, not automatically approved or live. While staging is deferred, continue real code-first ERP integration work in safe isolated branch with documented blockers.
- `REV-009`: preserve customized historical ERP, IDs, 193 report definitions, existing transaction semantics in its own business context. Core reusable modules must be industry-neutral, not a blind copy of any one business.
- `C10-A024` external SaaS and `C10-A025` simulation remain deferred until explicit change.

## Exact next high-value implementation slice
1. **Stop designing demo-only replicas.** Implement the real **Universal / Business Control Studio interface and shared canonical integration**, using existing A042/A043 contract. Use one registry, business context chooser, central/business/both/hidden placement, per-business effective setting and local edit authority, and an Owner-visible before/after impact summary. Business App Settings must project the same control ID and record; do not create a second settings engine.
2. Integrate carefully with existing **A021 Owner Controls**, **A034 Access Governance**, **A031 Enterprise API Bridge** and canonical A018/A019 tenant-business-site mapping. First read existing code to avoid duplicate RPC, table, permission or audit contract.
3. Implement signed authenticated Owner read/write API and versioned placement storage *in code/migrations*, per-business scope, audit, idempotency, approval-request flow and negative tests without applying live SG migrations or sensitive production effects. All preview modes and UI role dropdowns remain advisory; RLS/RPC is the real authority.
4. Continue actual integrated Business Setup → Purchase/Inventory/Production/Sales → Cost/Finance/Reports after the control plane slice, with consistent transaction/report reconciliation. Do not spend entire next session only running an audit/research loop.
5. Verify exact commit/PR, isolated SQL/HTTP/browser tests, GitHub workflow conclusions, risk boundaries and update ONLY the existing Master Book action/change/evidence rows. If Owner provides an approved runtime stage, run real signed negative E2E and restore gates; otherwise mark them NOT RUN (not PASS).
6. Keep business-neutral Studio independent of any industry's defaults. Product Vision includes 10 industry templates, but never equate templates to ten complete production ERPs.

## Required new-session execution protocol
- Read original [read-only research](https://github.com/mistybari99/CORE-10-CENTRAL/pull/7) and historical Project markdown where available, but **live Book, GitHub code and current runtime** outrank old reports.
- Check PR7 and other overlapping draft PRs, main, CI and the **current** SHA, and inspect this handoff and the canonical Decision Book. No competing Master Register or another ERP repository.
- Make one meaningful code-first vertical slice in the existing repo; use permission and integration skills as applicable; don't invent subagent or deployment actions.
- Verify before claiming done: code paths → exact commit SHA → CI tests → actual storage/Auth tests if applicable → deployment truth → Book rows → next task.
- User wants short practical Bengali checkpoints and substantial real builds rather than repeatedly asking for already supplied decisions.

**Current State summary:** A042/A043 **contract-tested only**, no operational Control Studio UI or signed persistence yet; no production stock changes or staff rollout; previous approved decision register and discussion history are retained unchanged. Next release and server readiness are separate from owner's approved product scope.
