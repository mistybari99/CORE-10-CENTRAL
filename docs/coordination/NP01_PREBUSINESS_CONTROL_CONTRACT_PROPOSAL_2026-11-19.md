# NP01 / B-020 — Pre-business Owner Control bootstrap contract (REVIEW PROPOSAL)

**Status:** PROPOSED, **not an adopted Owner policy**, not an implementation, and not a deployment authorization.
**Prepared:** 2026-11-19, independent review replacing the unavailable Claude coordination checkpoint.
**Source baseline:** canonical trunk `ccr-15ed11dd-n3hw5h` at `a82ae993b93c1460898b9022bb56b7a995d96437`; NP01 Draft PR #111 at `69143ffb82667b6f81b3667288af54a86b597698`.
**Affected RPCs:** `build01_setup_v1`, `setup_business_v1`, `setup_industry_draft_v2`.
**Reserved future implementation:** NP01 `0115`, only after this contract is accepted and reserved; preserve `0110–0114` and historical `0004–0019` checksums.

## 1. Verified architectural facts

1. `core10.control_check_v1(p_business, 'setup001.provision', NULL)` looks up `core10.businesses.id`; it **cannot** check a business that does not yet exist.
2. `control_setting_versions_v1` and `control_overrides_v1` require a non-null `business_id` referencing a business. `_control_resolve_v1` searches site/business settings, then the catalog default. No tenant-level policy exists.
3. `core10.canonical_audit_events_v1` and `_append_canonical_audit_v1` also require an existing `business_id`. Do **not** invent pre-business audit receipts or a second audit chain.
4. The existing canonical catalog's `setup001.provision` default is **enabled=true**, **stages=0**, `max_sites=50`, `allow_site_scope=false`. It can later be disabled for an *existing* business through ordinary Owner Control.
5. `core10.can_tenant(tenant_id)` checks a signed, active tenant-owner membership. Existing setup functions already require this predicate through the legal entity's tenant.
6. `build01_setup_v1` delegates to one of the two other public setup RPCs. Naively adding checks at all three levels can consume a one-time Control override twice and must be avoided.
7. Original setup modules/sites are created in one PostgreSQL transaction; a failed exception rolls back the changes. This fact must be preserved. Existing real side effects begin **before** any Control check, which is why new code cannot simply wrap the existing call after it returns.

## 2. Recommended immediate contract — one canonical Control engine, no shadow policy

### Common rules

- **Auth first:** verify `actor_uid()`, active tenant-owner membership `can_tenant(tenant)`, requested legal entity/tenant and typed/validated setup payload **before any exclusive lock**. Business owners/managers must not gain a new tenant provisioning right.
- Acquire a **tenant-scoped transaction advisory lock** for business creation (not just a request-key lock), then revalidate tenant-owner membership and all pertinent scope. This serializes the anchor/first-business choice, global first-business race and proposed site-count limits.
- Never allow the caller to choose or spoof a policy business ID. A deterministic anchor is determined server-side, under the tenant lock.
- Control is checked **before replay returns and before any persistent provisioning side effects**. Disabled feature, revoked membership, incompatible stages, missing policy, stale state or exceeded caps are fail-closed. A denial rolls back any provisional records.
- Accept only Control `stages=0` for creation until an actual source-linked setup approval-completion adapter is accepted. Nonzero stages must refuse without inserting a durable business or site.
- Apply actual `params.max_sites` to the normalized **total** of sites created by the request. Both quick and advanced modes are subject to the same cap.
- Immutable idempotency payload/request-key/actor checks remain intact, and a previously successful exact-key replay must still re-evaluate CURRENT canonical Auth and Control before revealing the receipt.

### Tenant already has a business

1. Under tenant lock, choose the **oldest immutable canonical business ID** in the tenant (lowest `businesses.id`, **without** filtering by mutable status). This is the deterministic *provisioning policy anchor*, not a caller-selected target.
2. Check `core10.control_check_v1(anchor_business, 'setup001.provision', NULL)` and the Owner parameters before any new business row, configuration, site or module is created.
3. The anchor must be stable across requests/replays; do not pick another active/enabled business to evade a disabled setting. If the anchor cannot be resolved/reached, fail closed.
4. New business creation remains a single transaction; canonical audit is written against the newly established business only after the permitted creation path is complete.

**Consequence:** the tenant owner can disable future new-business creation by disabling `setup001.provision` on the deterministic anchor business. This is reuse of the existing **business-scoped** Control port, not a tenant policy table or a shadow feature engine. Document this scope to Owners; the anchor rule itself is an Owner policy choice, not yet accepted.

### Tenant's first business (bootstrap)

No canonical business exists yet, so there is no stored tenant/anchor setting to consult. The only currently representable Owner decision is the **canonical catalog default**. A safe, explicitly limited path is:

1. After tenant-owner Auth and the tenant lock, reserve the smallest necessary **uncommitted draft business identity row** in the same transaction, with no sites, module activation, external calls, payment, token, hosted effect or irreversible side effect.
2. Immediately call the existing `control_check_v1(candidate_business, 'setup001.provision', NULL)`, enforcing its **catalog default** (now `enabled=true, stages=0, max_sites=50`). The provisional row exists solely to satisfy the canonical business-scoped check.
3. On any denial, roll back the *entire* transaction, including the provisional business row and any transactional audit activity. On success, complete the ordinary draft setup and immutable business-scoped audit/receipt within that same transaction.
4. Do not expose the provisional ID, emit external effects, publish a UI success or add a second Control evaluation. Require a final canonical Auth/Control recheck at the documented lock boundary.
5. A successful first business becomes the deterministic anchor for future creation requests.

**Explicit limitation:** this pattern CANNOT give a tenant owner a pre-configured OFF switch for their *very first* business, because Control currently cannot store tenant-scoped settings or a business-specific version before a business exists. Never claim otherwise. If the product requirement mandates that ability, **DO NOT implement this first-business exception**; instead design and separately approve a **canonical NP02 Control-port + canonical Audit extension** for tenant bootstrap. Do not invent NP01-only tables, policy, authorization, alternate event store or shadow Control evaluator.

### Avoiding double-checks and override double-consumption

Refactor entrypoints so the outer `build01_setup_v1` and the two direct functions use **one internal authorized provisioning engine**, with exactly one effective `control_check_v1` per external request. The wrapper must not invoke another separately checking public function. Registry evidence and `_control_rpc_calls_check_v1` static check must pass for every externally executable RPC; adapt the accepted implementation pattern without hiding a public writer or incorrectly declaring it exempt. **If this cannot be shown, keep all three RPCs pending/fail-closed.**

The `0112` `build01_site_v1` behavior stays business-scoped and unchanged; do not use the new-business anchor to bypass an existing site's own Owner setting.

## 3. Required adversarial test matrix before 0115 can be considered

- First-business concurrency: two tenant-owner requests, different keys; deterministic first and later-anchor policy; no committed orphan/candidate row on denied path.
- Existing-business disabled anchor: alternate enabled business **cannot** bypass anchor OFF; test current Control setting changing during a waiting creator.
- No caller-controlled anchor/tenant ID; legal-entity/tenant isolation; forged and expired actor, non-owner/manager, revoked tenant owner, cross-tenant row-lock contention.
- Current Owner Control OFF blocks replay of a prior success; same exact key converges, conflicting payload rejected, maker/actor identity preserved.
- Stage > 0 refuses safely with zero durable business/site/module/Audit success. One-time override is consumed at most once for a logically single call.
- `max_sites` boundary for 1, 50, 51 and Owner-custom caps; both quick/advanced input normalization; simultaneous site and business provision requests.
- Direct calls to *both* legacy public setup RPCs and the wrapper obey the same gate; no alternate unprotected path via `provision_business` or `provision_site`.
- Canonical RLS, audit hash chain, registry evidence, request key atomicity, transaction rollback, exact migration up/down/up and no historical checksum drift.
- Fresh disposable PG17, real independent transactions and latest-trunk NP01/Finance/Stock/Master compatibility. Signed 16-persona hosted checks remain a separate GO-2 gate.

## 4. Decisions and boundaries

**Recommended for Owner ratification:** the deterministic oldest-business anchor and transactional candidate-row first-business bootstrap, with the first-business OFF limitation stated above.

**NOT yet authorized:** changing the business creation policy or applying migration `0115`; no independent tenant Control policy table; no silent setup 1+stage approval; no automated trunk integration, hosted migration, GO-2, GO-3, `main`, production or IMG-ERP-SG change.

**Integration sequencing:** independent PR #118 Finance CI review and separate Owner code GO first; then latest PR111 integration review. Do not include this proposed contract in the CI fix PR or mutate Build 1's existing migrations. A signed accepted contract and tests are prerequisites to a future business-creation migration.

References: `docs/coordination/CONTROL_PORT_INTEGRATION_CONTRACT.md`, `0100_np02_control_tables`, `0101_np02_control_rpc`, `0102_np02_control_seed`, `0004_np01_setup_prerequisite`, `0005_np01_industry_prerequisite`, `0006_np01_build01_access`, `0008_np01_canonical_audit`.
