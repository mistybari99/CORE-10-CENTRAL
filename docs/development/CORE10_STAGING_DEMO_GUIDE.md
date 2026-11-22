# CORE10 staging demo — Owner-controlled, reversible-by-fresh-instance

Status 2026-11-22. **Staging only**: `rhrqhbyzrhaafynfhdaf` (`core10` schema). This is not a real operating business or a production database.

## Created fixture

- Owner tenant `core10-owner-group` (`tenant_id=1`), legal entity `1`. Owner's existing signed account manages it.
- `core10-demo-sweets-20261122` (`business_id=3`), display name `CORE10 DEMO Sweets (TEST ONLY)`, template `sweets_bakery`, status `draft`.
- Three canonical sites: Demo Showroom, Demo Factory, Demo Warehouse. One `setup.business` event and one canonical audit event recorded.
- Existing independent demo tenants `stg-a` (9801) and `stg-b` (9802) unchanged. Unrelated Supabase projects untouched.

## How the Owner opens it

1. Open [direct signed setup](https://core10-central.mistybari99.workers.dev/live/core10-build01.html) (or `/#/setup`).
2. Sign in with the Owner's **existing** staging Auth credentials. Never send the password in chat or commit it.
3. Select **CORE10 DEMO Sweets (TEST ONLY)** under Authorized Business. The three sites appear in the workspace.
4. `draft` means setup/data exercise only: no production activation; stock/master/finance migrations are still not hosted on staging.

The direct URL and `/#/setup` loaded over HTTPS (HTTP 200) on 2026-11-22. Successful interactive password sign-in **was not checked** from this session.

## Clear/fresh reset policy

**The reset is a fresh isolated demo draft, not deletion of history.** The access-change and canonical audit tables have immutable triggers and FKs to the business. A hard DELETE would break audit invariants. Do **not** bypass, disable or truncate them.

For a fresh exercise, use `node scripts/staging/create-fresh-owner-demo.mjs --fresh`. It authenticates against the **exact staging host** with the Owner's normal password, checks the signed Owner tenant/legal entity, creates one uniquely named `draft` with the standard three sites through `build01_setup_v1`, then verifies the resulting signed context and workspace. Every invocation produces a different slug; previous demo business and audit remain inspectable. Credentials are read only from the `CORE10_DEMO_EMAIL` and `CORE10_DEMO_PASSWORD` environment variables and never printed or stored by the script. Protect environment variables on shared computers, and unset them afterward.

A simpler manual fresh start is `/#/setup` → create a new business with a fresh `core10-demo-...` slug and `TEST ONLY` label, `sweets_bakery` template, Advanced mode and the three demo sites. This is **not** an erase operation.

A true delete/archival lifecycle requires a later **forward migration**, Owner-approved retention policy, and cross-tenant/immutable-audit tests. None was added or applied here; 0115–0118 migration reservations remain unresolved.

## Evidence and safety

- Staging SQL in a `BEGIN ... ROLLBACK` rehearsal verified setup, idempotent request-key replay, three sites, tenant-scoped context and cross-tenant rejection before the commit.
- After commit, signed-context SQL checks verified Owner read/manage, three sites, one audit event, replay without duplicate audit, and tenant 9801's refusal to see Owner business ID 3.
- `node --test tests/staging/create-fresh-owner-demo.test.mjs`: 5/5 PASS (mocked network only). The networked CLI has **not** been exercised end-to-end with the Owner password.
- No new migration, no Worker deployment, no edit to `main`, no service-role key.

## Live release boundary

The earlier `preview/core10-central-level2` shell wording fix is still **preview code only**. Do not deploy without mandatory `node build.mjs` → all-PASS `node verify.cjs` → multipart Worker PUT → all-PASS live verify; otherwise rollback. The live Worker version stays `201008ca-42a7-42cd-a08e-b968da6c4e51` as of these checks.
