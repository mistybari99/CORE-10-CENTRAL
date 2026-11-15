# PACK-01 + PACK-02 integration review, S2 contract and S5 requirements

Reviewed at exact SHAs on 2026-11-15: PR #104 (PACK-01, ChatGPT) `5103730576a57a21149b077f514cb6d7309ba61d`; PR #105 (PACK-02, Claude) base of this review `2dcb4133b3751987faf04e443b1f776445c0bd11`; both branch from Preview `e76cf8a3db1a385726a1637683c972e99a193fec`.

## 1. Review findings

| # | Finding | Result |
|---|---|---|
| R1 | File overlap #104 vs #105 | None. `git merge` is clean. |
| R2 | #104 does not change `c10_build01_access_integration_v1.sql`; the predicates PACK-02 calls (`can_tenant/can_business/can_manage/can_site/can_see_business`, `actor_uid`) are identical on both heads | PACK-02 needs no change to follow PACK-01. |
| R3 | #104 rule "explicit site DENY outranks inherited owner/manager rights". PACK-02 `pack02_business_report_v1` / `pack02_owner_report_v1` used `owner OR can_site` and would still show stock counts for a read-denied site | **Fixed in PACK-02**: figures are withheld (`stock_read=false`, counts NULL) and owner totals exclude read-denied sites. |
| R4 | On the pre-#104 baseline, A048 `inventory_action_authorized_v1` uses an older rule (`can_manage OR raw grant`): stricter than `can_site` for managers, and it ignores owner DENY. PACK-02 projects canonical `can_site`, so projection and A048 enforcement only agree once #104's adapter is merged | New `agreement` suite: 108 actor × site × action checks pass on the merged tree; the matrix is skipped (with a NOTICE) on the baseline. |
| R5 | Build01 browser client is `persistSession:false` and keeps its Supabase client private; the gateway allowlists exactly five Build01 RPCs and seven files | PACK-02 cannot be reached from a signed page without a small Build01 patch (section 3). |
| R6 | #104 `tests/preview-one/run-combined.sh` does not load PACK-02 SQL | Optional follow-up for ChatGPT after S2: add the two PACK-02 SQL files to the Build01 section. Not required for S2. |

## 2. S2 contract (who owns what)

PACK-02 (Claude) provides, already in PR #105:

- `core10-pack02-signed.js` — `CORE10_PACK02_SIGNED.fromRpc(signedRpc)` (preferred) or `.fromClient(supabaseClient)`. Six-name allowlist with fixed argument names, fresh actor check before every call, actor-switch poisoning, error-code sanitising.
- `core10-pack02-app.js` — `CORE10_PACK02_APP.mount(element,{rpc,context})` → `{ready,refresh(context),reset()}`. `context` is the `build01_context_v1` object. Offers are menu entries only; each workspace is decided by `pack02_workspace_v1`. Any denial or malformed projection clears the panel.
- `core10-pack02-workspace.js/.css`, `core10-pack02-controls.js` — renderers.
- SQL `c10_pack02_workspace_v1.sql`, `c10_pack02_controls_v1.sql` (load after Build01; controls after A044).
- `tests/pack02/live-auth-browser.cjs` — the real-auth journey, run by Build01's `run-auth.sh` once patched.

PACK-01/Build01 (ChatGPT) is asked to provide:

1. A signed read path: `api.pack02(name,args)` on the Build01 client, limited to the five read-only RPCs.
2. Gateway allowlist: those five RPCs and five PACK-02 static files. `pack02_setup_business_v1` stays **off** the allowlist (setup keeps going through `build01_setup_v1`).
3. One host element `#b01-pack02`, script/style tags, a mount call after the verified context, and `reset()` inside `clearPrivate()`.
4. Load order and runner hook.

Guarantees PACK-02 relies on from Build01: `getUser` before each RPC, `actor_uid()` session check against `auth.sessions`, CSP `script-src 'self'; style-src 'self'` (PACK-02 uses no inline script, `innerHTML` or `<style>`).

## 3. Exact patch proposal for ChatGPT

`docs/development/PACK02_S2_BUILD01_PATCH_PROPOSAL.patch` (6 Build01-owned files, +20/−8). It applies cleanly to Preview `e76cf8a` and to #104 head `5103730` (the six files are byte-identical on both). **Not applied in PR #105.** Apply with `git apply docs/development/PACK02_S2_BUILD01_PATCH_PROPOSAL.patch` on a branch that also contains PR #105.

## 4. Evidence (local, 2026-11-15; scratch worktree = #105 + #104 merged + the proposed patch)

- `tests/build01/run-auth.sh` with browser, **actual local GoTrue v2.197.0 + PostgREST 12.2.12**: all Build01 lines PASS, plus `PASS PACK-02 S2 ACTUAL local GoTrue` — signed owner/staff API negatives, anonymous, tampered signature, logout revocation, write RPC 404 at the gateway, Build01-hosted panel at 390/1440, panel cleared on sign-out.
- `tests/build01/run-sql.sh all` (patched load order): 6/6 areas PASS. `client.test.cjs` 5/5, `gateway.test.cjs` 2/2, locked browser PASS.
- `tests/preview-one/run-combined.sh pack01-security`: PASS.
- `tests/pack02/run-sql.sh all` + `app`: workspace, regression, controls, scale, portfolio, agreement (108 checks), app journey PASS.
- PostgreSQL 16.15 locally; CI uses 17. None of this is hosted staging or production proof.

## 5. S5 — requirements for real authenticated staging (not available today)

1. A **separate** Supabase project (not IMG-ERP-SG), Owner-approved, with `c10_demo`-equivalent schema applied from Git in the documented load order; explicit Owner GO for that apply.
2. PACK-01 merged contracts on that project: Build01 SQL + #104 adapters, and the S2 patch.
3. Stage-only GoTrue identities per D046 (two unrelated tenants; tenant owner, business owner, manager, staff, investor, revoked, expired, unassigned, operator), credentials stored outside Git, `/auth/v1/user` verified.
4. Hosted URL + publishable key delivered as CI secrets; `core10-build01-config.js` gains a reviewed `staging` mode (today it accepts loopback only) — PACK-01 change.
5. PostgREST exposure limited to the allowlisted RPCs; no service-role key in any browser artifact; CORS/origin pinned.
6. Signed A/B run of `tests/pack02/live-auth-browser.cjs` + Build01/PACK-01 signed suites against the hosted URL: cross-tenant, staff/owner negatives, expiry, revoke, logout, tampered token, direct REST/CSV/Storage negatives.
7. Backup/restore drill and cleanup plan for stage users/data; evidence (run IDs, SHA, screenshots 390/1440) saved to Drive; Orchestrator Sheet readback.

Blocker owner: Owner decision for item 1; PACK-01 for 2, 4, 5.
