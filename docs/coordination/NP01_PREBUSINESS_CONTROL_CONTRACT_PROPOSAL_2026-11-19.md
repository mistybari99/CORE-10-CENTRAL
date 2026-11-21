# CORE-10-CENTRAL — Tenant Bootstrap Owner Control Contract, Revision 2.1

**OWNER-RATIFIED POLICY — ARCHITECTURAL REVIEW PASS REPORTED (IN-CHAT) — NOT IMPLEMENTATION AUTHORIZATION**

**Date:** 2026-11-21  
**Document scope:** NP01 pre-business provisioning, canonical NP02 tenant/bootstrap Owner Control and canonical Audit prerequisites.  
**Repository:** `mistybari99/CORE-10-CENTRAL`  
**Draft PR:** [#119](https://github.com/mistybari99/CORE-10-CENTRAL/pull/119), branch `review/chatgpt-np01-bootstrap-20261119`, base `ccr-15ed11dd-n3hw5h`.  
**Verified reference trunk before revision:** `5efece225a7e6ca5875dd954f9cc0b8298adeeb8`.  
**Earlier proposal reviewed:** `e832a5e64a285404716b8388b4c8cf69076e5caa`.  
**Original independent review:** [Codex Sales, review 6001784578, 2026-11-21](https://github.com/mistybari99/CORE-10-CENTRAL/pull/119#pullrequestreview-6001784578): technical **REQUEST CHANGES** in a COMMENT review on old HEAD `e832a5e...`; preserved as historical evidence.  
**Subsequent independent re-review:** Codex Sales reported architectural **PASS for Owner ratification** on exact Revision 2.1 HEAD `14f9bf541871a2dda4402f6e4e612215780135f3` in an Owner-provided chat handoff; no newer formal GitHub review submission is claimed. All original P1-A..P1-E/P2 are **design-addressed only**, not implemented or PG17-verified.  
**Owner ratification:** eight Bootstrap policy choices explicitly approved on **2026-11-21**; canonical Decision Book `C10-D063`, revision `REV-016`. Policy approval is not coding/integration/release GO.  
**Related NP01 PR #111 reviewed SHA:** `69143ffb82667b6f81b3667288af54a86b597698`. Finance Shared CI PR #118 is already integrated; do not repeat it.  
**Release status:** GO-2 hosted staging **HOLD**; GO-3 production **HOLD**. No implementation, SQL, migration, merge or deployment GO.

> **Architectural determination.** The Owner's new binding requirement is that a tenant Owner can persist, administer, enforce and audit **Business Creation OFF before the tenant has any Business**. Implement this using the existing canonical NP02 Owner Control and Audit authority, extended with a Business-independent tenant/bootstrap scope. Preserve the approved ERP-wide Universal Intelligent Master Owner Control and contextual guidance obligations in their existing workstream; this PR is *not* a redesign or implementation of those capabilities.

## 1. Policy authority, scope and preserved history

### 1.0 Owner ratification addendum — 21 November 2026 (policy only)

The Owner has **explicitly ratified the following eight policies** after the independent architectural re-review. They are binding requirements for subsequent NP02/NP01 design and acceptance, not completed code or release authorization:

1. Newly initialized tenants start with **Business Creation OFF** until an actively authorized Tenant Owner enables it. This is not an ERP-wide default-OFF policy. Existing tenants require safe inventory and explicit compatibility/backfill; never overwrite their prior behavior by assumption.
2. Tenant/bootstrap policy administration (including ON/OFF, schedules, version revert, tenant-scoped exception grant and exception revocation) belongs to the **active authorized Tenant Owner**. Business-scoped `can_manage` does not grant tenant policy administration; future delegation needs a separate Owner decision.
3. An applicable explicit **tenant OFF is a veto**: Legal Entity and Business restrictions may tighten the result, never enable a narrower scope against parent OFF.
4. **Ordinary Control exceptions cannot bypass explicit tenant OFF**. Emergency *corrections* are separately governed and confer **no authority to create or provision any new Business against an explicit tenant OFF**, regardless of whether the creation is described as emergency, recovery or ordinary setup.
5. Under current tenant OFF, provisioning (including successful-key replay through a provisioning RPC) **denies**; historical operation receipts remain separately readable only through a scoped, non-mutating, independently authorized reader.
6. Site caps are **configurable per Business**; count existing/provisioned and sites that can be reactivated without renewed creation authorization, including applicable suspended/archived states. No unratified tenant-global quota or fixed 50-site ceiling is implied.
7. Pending/in-flight operations **revalidate current effective policy before execution**. Committed documents, stock and journal history remain intact; operational corrections go through separately authorized domain paths rather than silent retroactive deletion.
8. Emergency corrections must be **narrowly scoped, time-bounded, independently authorized/approved and canonically audited**, and cannot bypass tenant isolation, immutable Audit, Auth, financial/stock integrity or other protected invariants.

**Architecture planning accepted:** NP02-A..NP02-E are the canonical shared provider plan (persistent tenant identity, tenant Owner Control, shared locking/time, tenant-scoped canonical Audit and NP01-facing D062-compatible interface). NP01 remains the consumer. The proposed implementation API names/signatures and lock graph require technical acceptance before a separate coding GO. Existing migration reservations and Claude-owned lane records remain unchanged. The ERP-wide D033/D045/D049/D057, A044/A045/A052 and 520-detail workstreams are preserved, not imported as new Bootstrap implementation scope.

**Gate status:** `POLICY_RATIFIED / ARCHITECTURAL_REVIEW_PASS_IN_CHAT / IMPLEMENTATION_NOT_AUTHORIZED / GO-2_HOLD / GO-3_HOLD`. This addendum is documentation-only and is a post-review delta requiring separate exact-HEAD delta confirmation; it does not retroactively alter the reviewed SHA or earlier GitHub review.

### 1.1 What the Owner has actually decided

**New, binding capability requirement (Owner, Revision 2.1):** a tenant with zero Businesses must be capable of holding an explicit, effective Business Creation OFF policy, configurable by an authorized tenant Owner and enforced on all Business-creation paths. The policy exists independently of Business IDs. It must be auditable in the canonical Audit architecture.

The initial default, active Tenant Owner administration, tenant OFF precedence, ordinary override prohibition, separate receipt reads, reactivatable-site counting, pending revalidation and audited emergency corrections were **subsequently Owner-ratified on 2026-11-21** and are recorded in section 1.0, section 11 and `C10-D063` / `REV-016`. Broader tenant delegation, any tenant-wide aggregate site cap, detailed existing-tenant backfill and new domain-specific emergency rights remain separate future policy/engineering gates; no implementation GO follows from ratification.

### 1.2 Decision inheritance and status

| Authority | Status in Revision 2.1 | Preserved/changed contract |
| --- | --- | --- |
| D033 | **PRESERVED — approved** | Central Master and per-Business Owner Control use the *same* authoritative permissions and configuration; server Auth/RLS apply. Show/Locked/Hidden is not permission. |
| D045; R123 | **PRESERVED — approved** | Universal Control Studio remains discoverable to authorized Owners; per-Business Central Only / Business Only / Both / Hidden menu placement is independent of actual feature ON/OFF and delegation. |
| D049; R128 | **PRESERVED — approved** | ERP-wide intelligent Owner Intent, contextual information, recommendation, dependency/impact explanation, formula/source provenance, safe preview and Bangla/English guided UX. No arbitrary execution. |
| D054 | **PRESERVED — approved** | Evidence in the existing Decision Book/Drive, truthful build status, two genuinely verified major builds per mandatory Owner preview, separate release gates. |
| D055 | **PRESERVED — approved** | 520 existing Detail IDs and capability mapping, S0–S10 dependency sequence, canonical Auth/Master/Stock/Money/Approval+Audit engines, no shadow posting engines. |
| D057 | **PRESERVED — approved** | Universal per-feature Control, server ON/OFF, 0–5 approval-stage capability where supported, action grants, typed params, effective schedules, bounded exceptions, history and audit. |
| D061 | **PRESERVED with proposed canonical extension** | Existing business/site setting semantics remain; tenant/bootstrap scope requires forward NP02 extension. Existing business-owner `can_manage` is **not** silently promoted into tenant policy authority. |
| D062 | **PRESERVED — approved** | Public RPC literal Control-call evidence + CI denial test, registry statuses, ordered migrations and protected checksums. |
| R071; R072 | **PRESERVED — approved provenance rules** | Latest explicit Owner correction supersedes conflicting interim suggestions; an agreed proposal does not itself authorize implementation. |
| R124 | **PRESERVED — approved** | A044/A045 reusable certified control/micro-engine configurations, one canonical service, scoped publication and versioned changes; uncertified handler requests remain engineering work. |
| Earlier PR #119 `min(businesses.id)` policy anchor | **SUPERSEDED proposal** | No durable tenant identity and susceptible to permitted lower-ID import/sequence allocation. Not a valid tenant authority. |
| Earlier PR #119 uncommitted candidate first-Business exception | **SUPERSEDED proposal** | May support the old business-only catalog lookup but cannot persist an explicit OFF before any Business. Not the policy mechanism. |
| Earlier PR #119 enabled-by-default catalog-first authority | **SUPERSEDED proposal** | The business-scoped default cannot govern a tenant's first Business against an explicit tenant OFF. |
| Tenant-scope bootstrap OFF capability | **NEW BINDING OWNER REQUIREMENT** | Business-independent canonical tenant policy scope, shared Control evaluation and tenant Audit support. |
| Eight Bootstrap policy choices (initial OFF, tenant administration, parent OFF, ordinary override, receipt read, per-Business cap, pending revalidation, emergency correction) | **OWNER-RATIFIED 2026-11-21 — C10-D063 / REV-016** | Approved policy only; section 11 retains originally suggested alternatives as non-binding historical options. No code/SQL/hosted GO. |

Relevant revisions REV-009 and REV-011–REV-015 preserve original IMG-ERP-SG isolation, brand-neutral industry templates, one future Central App, the original 520-detail mapping, existing pack state, and canonical `core10` migration architecture. Revision 2.1 does not reopen or overwrite this history.

**Sources:** [Master Decision Book](https://docs.google.com/spreadsheets/d/1IYzGBtUVNjah31cPVSFHkzgO7P093jTfZS0CopWrDxs/edit); [Final Code Gap Decisions](https://docs.google.com/document/d/1o1gOFULxTDMJIiE-jGzy_1ripZ1ciQz79DvmbW9yszs/edit); [Change Register](https://docs.google.com/document/d/1VJHncLoLvBTLaFZ0AtxujEkbYTkuHgUgdRkOlcDU3JI/edit); [520-row Detail mapping](https://docs.google.com/spreadsheets/d/1C8yAMHvbyj8-5DkWUuR2FNB8DwmvdKr35SyJLIzgkho/edit).

## 2. Current canonical baseline and why the old proposal failed

The existing `core10.control_check_v1(p_business, feature, site)` resolves a Business ID and `can_see_business` before using `_control_resolve_v1`. Existing Control setting/override persistence and canonical audit events are business-keyed. The catalog's `setup001.provision` baseline is `enabled=true`, `stages=0`, `max_sites=50` and `allow_site_scope=false`. Thus an explicit pre-first-Business OFF cannot currently be represented by this port.

The original oldest/lowest-Business anchor was not persisted or made immutable. Business IDs permit imported/seeded explicit values, and a later lower ID can silently move the resolved policy. A provisional first Business does not solve pre-business administration; catalog-first ON silently permits creation.

The prior review also reproduced: a waited OFF missed because `_control_resolve_v1` filters with `statement_timestamp()`; a business-scoped manager modifying the would-be tenant policy; direct authenticated `provision_business`/`provision_site` bypassing Control and cap; `0112` site creation with stages > 0 and no Approval; and override consumption on repeated Control checks. These are **baseline findings**, not fixes introduced by this document.

The original 2026-11-19 proposal and the 2026-11-21 independent review remain historical evidence. This complete Revision 2.1 **replaces the proposed architecture**, not the review record. None of the six findings is technically fixed by documentation alone.

**Source contracts:** [NP02 Control port](https://github.com/mistybari99/CORE-10-CENTRAL/blob/ccr-15ed11dd-n3hw5h/docs/coordination/CONTROL_PORT_INTEGRATION_CONTRACT.md), [historical 0101](https://github.com/mistybari99/CORE-10-CENTRAL/blob/5efece225a7e6ca5875dd954f9cc0b8298adeeb8/internal/migrations/0101_np02_control_rpc.up.sql), [registry evidence 0103](https://github.com/mistybari99/CORE-10-CENTRAL/blob/5efece225a7e6ca5875dd954f9cc0b8298adeeb8/internal/migrations/0103_np02_control_registry_evidence.up.sql), and [independent PR #119 review](https://github.com/mistybari99/CORE-10-CENTRAL/pull/119#pullrequestreview-6001784578).

## 3. Canonical NP02 tenant/bootstrap policy scope

### 3.1 Identity, persistence and lifecycle

Define **one canonical, durable tenant/bootstrap scope identity** belonging to the existing tenant, separate from every Business ID. The conceptual binding is **`tenant_id -> tenant_bootstrap_policy_scope`**; this is a *contract concept*, not a new table name, SQL implementation or new shadow engine.

Requirements:

1. Canonical tenant identity is immutable and comes from the existing Auth/organization hierarchy, not client-supplied claims or Business ordering.
2. Scope identity is provisioned at tenant bootstrap *before* first Business creation; a zero-Business tenant may persist Control versions, schedules and authorized administrative events.
3. Initialization must be atomic with tenant enrollment or protected by a fail-closed intermediate lifecycle state. Missing/ambiguous required tenant policy never falls back to business catalog ON.
4. Business deletion, status changes, lower-ID import, sequence changes, tenant-legal-entity associations or reactivation must not reanchor tenant policy.
5. Tenant ownership changes, deactivation, restoration and deletion obey existing canonical signed Auth, retention and Audit safeguards. Tenant reassignment must not silently transfer authority or erase history.
6. Extend canonical NP02 Control version/override storage and RLS with tenant/bootstrap scope rather than introducing NP01-owned policy storage. Exactly one authoritative version history per scope/capability.
7. An existing-tenant **forward backfill** must preserve historical Business Control versions and audit history. Do not silently convert business-scoped permissions into tenant-wide permissions. Inventory ambiguous legacy mappings and present a reviewed migration/reconciliation plan.
8. The canonical Control feature registry must identify applicable scopes and reject invalid combinations. A tenant/bootstrap feature may be administrable without a Business ID; ordinary business/site semantics remain backward compatible.

### 3.2 Scope precedence and invariants

**Owner-ratified scope precedence (2026-11-21):** an explicit effective tenant provisioning OFF is an absolute veto on new Business creation; applicable legal-entity or Business rules may be more restrictive but may not re-enable a tenant OFF. Site Control uses existing business/site semantics subject to applicable tenant restrictions. Any **implementation ambiguity** or incomplete current-policy resolution must fail closed, not silently choose a permissive scope.

Preserve all nonconfigurable canonical invariants, including tenant isolation, Auth/revocation, audit immutability, Approval maker-checker, Stock and Money integrity. ON does not grant action permission. A Control override does not bypass protected invariants.

### 3.3 Canonical tenant-level Audit

Extend the **existing** canonical Audit subject model so tenant/bootstrap policy administration and first-Business creation can be audited without an existing Business ID. Do not create a new independent bootstrap audit table/chain or fabricate a business-linked audit subject.

Canonical events bind: tenant and policy scope identity; signed actor; action and effective authorization; feature key; setting/override version and effective interval; final decision time; normalized request/operation fingerprint; receipt/created subject; result or denial; and accepted chain/correlation metadata.

Transactional success audit, override consumption, idempotency receipt and creation commit/rollback together. An aborted transaction cannot leave a false success audit, committed override use or orphan entity. If durable denial evidence is required despite rollback, use a separately accepted canonical security-denial mechanism; do not claim rolled-back rows remain durable. Audit read/RLS must never reveal foreign tenant metadata.

## 4. Auth, policy administration and presentation boundaries

Authenticate first using signed `actor_uid()` and current tenant ownership/membership; resolve tenant/legal entity/server-side scope before mutation, with revalidation after any relevant lock wait. Reject spoofed actor, revoked membership, wrong tenant and unauthorized indirect SECURITY DEFINER access.

**Owner-ratified authorization (2026-11-21):** only an active authorized tenant Owner can administer tenant/bootstrap setting changes, schedules, version revert, tenant-scoped exception grants and exception revocations; no Business Owner gains tenant rights by `can_manage`. D061 `can_manage` remains valid for **business-scoped** Control under its existing contract. Explicit tenant-administrator delegation is **not approved**; any future delegation requires a separate Owner decision. Any administrative delegation must be separately scoped, revocable, auditable and subject to existing maker-checker where applicable.

The authenticated tenant Owner must be able to inspect/operate the tenant policy with **zero Businesses**, including through an authorized Control view. Business Owner privileges, menu placement, a hidden/locked control, AI text or a copied tenant ID cannot confer tenant administrative authority.

## 5. Locking, current evaluation and linearization

### 5.1 Shared Control-write/creation serialization

The creation gate and policy administration writers must participate in a **common canonical NP02 serialization protocol**. The old independent tenant advisory lock is insufficient because existing Control writes use a different per-Business/feature lock.

Proposed global order, subject to formal deadlock review:

1. Validate signed actor and normalize tenant/operation context without trusting caller-supplied scope.
2. Acquire canonical tenant provisioning serialization lock.
3. Acquire applicable tenant, legal-entity (if approved), Business/site Control locks in one deterministic global order, matching the corresponding canonical policy writers.
4. Acquire idempotency/operation and required resource/quota locks in a documented global order. Site and setup writers must follow the same quota serialization boundary.
5. **After waits**, revalidate active Auth/membership, Approval evidence and resolved tenant/scope.
6. Obtain a **fresh committed-policy snapshot and a single canonical decision time**, after all relevant locks have been acquired; evaluate settings/schedules/overrides once.
7. Use the returned decision for typed parameter enforcement and permitted creation. Atomically record receipt, policy identity/version, chosen override consumption and canonical Audit.

The accepted shared lock order must include tenant provisioning, Control setting/override, operation receipt, Business/site quota and audit-chain locking, with an explicit deadlock/concurrency proof. A policy writer must serialize with creation on the same effective-policy scope. Dynamic scopes must have deterministic lock identity and ordering; advisory-lock collisions, deadlocks and concurrent retries fail safely.

### 5.2 Time semantics, waited OFF and scheduled settings

Do **not** edit historical `0101`. Its `statement_timestamp()` use in `_control_resolve_v1` and setting defaults can filter out a later effective OFF, even when the creator correctly waits on a lock. A forward **canonical NP02** Control contract is required; NP01 must not implement a second, independently computing evaluator.

Distinguish request start, statement start, lock acquisition, **post-wait evaluation/linearization time**, setting effective time, override expiry and commit time. A fresh snapshot is necessary as well as an appropriate decision-time clock: changing only the timestamp function while retaining a stale snapshot is not sufficient.

Proposed semantics: at a serialized final decision boundary, evaluate the latest committed applicable versions visible to a new post-wait statement/snapshot (e.g., correctly constructed PostgreSQL READ COMMITTED sequence or verified equivalent), at the decision time captured there. A scheduled version applies only if its effective interval contains that time. Expired settings/overrides do not remain eligible because the command began earlier. Version overlap and equal-effective-time ordering require deterministic canonical resolution.

**Required guarantee:** creator begins its statement at t0 and waits; Owner starts OFF **after t0**, commits OFF at t1 while creator is blocked; creator resumes and obtains final current-policy decision at t2 > t1. Creator **must see OFF and deny**, not evaluate the old version at t0.

If creation linearized before a later OFF, OFF is prospectively ordered after it; committed history is not retroactively erased. A scheduled transition occurring after a valid linearized decision does not undo that creation. Abort/late failure rolls back its transactional effects; on retry the command re-evaluates current Auth/Control.

### 5.3 Conflicts and failure handling

Missing tenant scope, unknown feature, mismatched scope, malformed typed parameters, insufficient Approval, stale version, revoked membership, cap violation, lock failure or unresolvable policy conflicts **deny safely**. Define bounded retry/reconciliation for deadlocks and uncertain transport outcomes using the same logical operation key. Never blind-retry a potentially committed creation as a new operation.

## 6. One effective decision, overrides, replay and quota

### 6.1 Exactly one logical policy decision

"Exactly once" means **one effective canonical Control decision per logical operation** and at most one durable entity creation; it does not claim the network can invoke the physical RPC only once.

Bind stable operation key to tenant, operation type, signed actor/authorization context and normalized immutable payload digest. Same key/same payload converges; same key/different payload or tenant conflicts without disclosing cross-tenant receipt data. Current Auth and policy must be enforced before any replay result is revealed. A failed transaction retry re-evaluates fresh policy; a committed successful retry cannot produce another Business/site or consume a new override.

A reusable private preparation/normalization service may exist, but **each actual public entrypoint must satisfy the accepted registry evidence**. A public wrapper must not call a second gated public RPC. One final canonical Control decision, with its version/scope/override result, is passed into an externally non-callable writer. Revalidating Auth/scope after waits does not mean consuming a second Control override.

**Current OFF after prior success — Owner-ratified 2026-11-21:** the provisioning RPC **MUST DENY**, including a successful-key replay, when the current effective tenant policy is OFF; it cannot create new records, return a provisioning success result or consume another override. Historical receipts remain accessible only through a **separate, tenant-scoped, independently authorized, non-mutating read-only receipt interface**. The receipt reader checks current signed Auth and scope and must not call a consuming provisioning Control check, expose foreign-tenant receipts, or perform a new operation. A reduced quota never retrospectively deletes existing sites or invalidates historical records; it restricts new creation.

### 6.2 One-time override and expiry

An eligible override is scoped, signed-authorized, versioned, effective-time/expiry checked, bounded to a defined logical operation or explicit allowance, and canonically audited. Consumption must be atomic with successful permitted creation and performed no more than once per logical key. If an override-backed operation rolls back, consumption rolls back. A replay of committed success does not consume another override.

**Owner-ratified security policy:** ordinary override cannot bypass explicit tenant-wide OFF. Emergency **correction** is a separately authorized, narrowly bounded, time-limited, independently approved and canonically audited domain workflow. It **never authorizes new Business creation or provisioning against an explicit tenant OFF**, including requests labeled emergency or recovery; an authorized policy change to ON is a separate canonical administration action. No override can replace Auth, protected invariants or genuine Approval completion.

### 6.3 Site count and race safety

Apply the typed `max_sites` parameter to normalized initial setup and all retained site-creation paths; Quick and Advanced setup must agree. Concurrency requires serialized quota check **and insert**, not an unlocked count snapshot.

**Owner-ratified quota interpretation:** configurable per-Business cumulative cap counting provisioned sites and any site that can be reactivated without renewed creation approval. Count pending/archived/soft-deleted states according to an explicitly accepted, bypass-resistant definition. A tenant-wide aggregate cap or legal-entity cap requires a separate explicit Owner decision; neither is implied by an existing per-setup parameter. Test cap 1, 50, 51, custom, concurrent site creators and mixed setup/site requests.

## 7. Approval-stage boundary

The existing [`0112` site Control binding](https://github.com/mistybari99/CORE-10-CENTRAL/blob/69143ffb82667b6f81b3667288af54a86b597698/internal/migrations/0112_np01_site_provision_control.up.sql) checks Control and site limits but does not enforce nonzero stages through a canonical approved-completion adapter.

**Required forward safety contract:** requested stages **greater than zero fail closed** for Business/site creation until a canonical, source-linked Approval completion adapter exists. Stage zero is not permission to evade any independent Approval requirement. A Control override cannot count as approval.

A future adapter must verify current approved status, payload fingerprint, tenant/Business/site/operation binding, route/version, distinct authorized reviewers, expiry, anti-replay and maker-checker. Do not edit `0112`; this is an explicit forward NP01/canonical Approval prerequisite, not a resolved historical implementation.

## 8. Public provisioning contracts and direct-call closure

| Public/related interface | Revision 2.1 enforcement contract |
| --- | --- |
| `build01_setup_v1` | Preserve external request/result compatibility where possible; normalize and execute exactly one effective tenant Control decision; do **not** call another separately gated public setup RPC. |
| `setup_business_v1` | Direct invocation requires signed tenant owner, canonical tenant policy gate, Approval, idempotency and atomic Audit before creation. |
| `setup_industry_draft_v2` | Same canonical gate/receipt semantics while preserving industry draft validation and scope. |
| `build01_site_v1` | Preserve per-Business Control plus applicable tenant restrictions, enforce accepted site cap under contention, stage > 0 fail closed pending approved adapter. |
| `provision_business` | Currently a direct authenticated bypass. Remove external EXECUTE or make every retained external path equivalently canonical-gated before readiness claim. |
| `provision_site` | Same as above, including quota, Approval and tenant/business Auth. |

Inventory **all** overloads, internal callers, triggers, jobs, role inheritance, SECURITY DEFINER entrypoints and EXECUTE grants, including `PUBLIC` and `authenticated`. Recommended closure is to internalize unguarded low-level provisioning writers and retain only narrowly authorized internal callers behind a tested canonical public gate. If compatibility requires a retained public adapter, its Auth/Control/Approval/quota/Audit enforcement must be **equivalent**, not just documented.

Update affected `core10.control_rpc_map_v1` entries and any public registry/privilege evidence in the same coordinated forward change. No registry row should advertise a non-executable public RPC. Do not break the approved B-009 drift contract by quietly changing old installer files; an intentional replacement must be reconciled through separately approved forward compatibility work. A maintenance/import bypass is not an implicit exemption and requires its own explicit authorization and audit.

Creation must remain one atomic transaction; no irreversible external effects are allowed before commit. No provisional Business may be exposed as success or treated as the tenant's policy identity.

## 9. D062 registry evidence and forward migration protections

Existing [`0103`](https://github.com/mistybari99/CORE-10-CENTRAL/blob/5efece225a7e6ca5875dd954f9cc0b8298adeeb8/internal/migrations/0103_np02_control_registry_evidence.up.sql) inspects the **public function's own body** using `_control_rpc_calls_check_v1` for the mapped literal `control_check_v1` call; it does not trace arbitrary private helpers. An internal-only shared check therefore cannot justify marking all wrappers `enforced`.

Preferred compatible design: shared private normalization, a literal accepted canonical Control invocation in the externally called public entrypoint, then an internal private non-executable writer. If tenant/bootstrap Control requires a different function signature or call syntax, **NP02 must coordinate a forward canonical registry/evidence change** with equally strong proof, and tests for every retained public RPC. Never falsify evidence, exempt an unprotected writer, or disable CI to make it green.

Preserve:

- Historical `0101` unchanged.
- NP01 `0110`–`0114` unchanged, including checksums; no new `0115` implementation under this document.
- All other historical migration checksums and accepted migration/rollback ledger semantics.
- `docs/coordination/MIGRATION_RESERVATIONS.json` and `run.sh` numeric apply ordering/`OUT_OF_ORDER` behavior; **allocate no new migration number now**.
- NP02 ownership of canonical shared Control/Audit forward extensions, NP01 ownership of the subsequently approved bootstrap integration, and all existing domain lane boundaries.
- B-009 reviewed source/drift protections and public RPC evidence tests.
- Auth, Approval, Stock and Money integrity boundaries and protected IMG-ERP-SG.

**Dependency ordering, not new assignments:** (1) Owner ratification completed 2026-11-21; shared provider interface approval and allocation remain pending; (2) after separately scoped coding GO, canonical NP02 tenant identity/Control/Audit and fresh evaluation; (3) coordinated registry/EXECUTE legacy closure and forward site-stage safety; (4) future NP01 setup bindings using those canonical contracts; (5) disposable PG17 verification and independent technical review; (6) separate hosted release authorizations if later requested. Check live coordination reservations and branch heads before any future coding proposal. No implementation GO is conveyed.

## 10. Universal Intelligent Owner Control compatibility — OUTSIDE this PR's feature backlog

D033/D045/D049/D057, R123/R124/R128 and existing **A044 Universal Owner Control Studio**, **A045 certified Micro-Engine Workshop** and **A052 Owner Intent** remain approved ERP-wide requirements. See [D049 / R128 companion specification](https://docs.google.com/document/d/1VNB-ub0V49fg1QAPqyALk-1P79eqgbHJZwAdbq5-mCg/edit) and [Control port integration](https://github.com/mistybari99/CORE-10-CENTRAL/blob/ccr-15ed11dd-n3hw5h/docs/coordination/CONTROL_PORT_INTEGRATION_CONTRACT.md).

For the pre-business switch, provide concise Owner-facing explanation of current effective policy, tenant scope, expected result, affected creation paths, recommendation and alternative, risk, scheduling, Approval/authority, change preview, audit history and result location. The UI must operate when Business count is zero. It must read/write only canonical signed services, not a client or NP01 shadow setting.

The following remain independent dimensions across CORE-10:

- **ON/OFF** controls server-side feature availability; **SHOW/HIDE** controls authorized presentation/discoverability.
- **LOCK/UNLOCK** (editing/configuration restrictions) is distinct from signed **ALLOW/DENY** action authorization.
- **Central/Business/Both/Hidden placement** is never backend authority. Authorized Studio discovery is preserved even if hidden from regular menus.
- **Approval stages/maker-checker** are distinct from one-time **Control override**.
- **Tenant/Business/site/action scope**, effective schedules and typed parameters are distinct from each other.
- **Contextual AI information and recommendations** explain dependencies, source calculations, safer defaults, alternatives and before/after impact; they **cannot execute uncertified operational actions**, bypass signed Auth, or invent postings.

The shared canonical Control authority, Audit chain and security invariants apply uniformly. No second universal Control design, duplicate decision registry, AI-generated arbitrary SQL or shadow operational engine is proposed here. ERP-wide Intelligent Control, domain impact maps and full 520-detail execution coverage remain a **separate** existing workstream and outside PR #119's implementation scope.

## 11. Owner-ratified Bootstrap policy register — 21 November 2026

**All eight recommendations in the following table are now explicitly Owner-ratified** under `C10-D063` / `REV-016`. The original alternative choices are preserved for decision provenance **only**, not approved policies. Technical implementation, existing-tenant backfill, new delegation, new legal/tax rules, integration, hosted migration and deployment still need separate review and Owner GO.

| Choice | Owner-ratified baseline | Historical alternatives (NOT ratified) | Business impact | Decision status |
| --- | --- | --- | --- | --- |
| Initial tenant Business Creation state | **OFF** until explicit authorized ON | ON after completed canonical tenant initialization | OFF adds deliberate enablement/onboarding step; ON reduces setup friction but permits creation absent explicit restriction | **OWNER-RATIFIED 2026-11-21 — C10-D063** |
| Tenant-scope administrator delegation | Active tenant Owner only | Explicit, scope/time-limited delegated tenant admin with maker-checker | Limits cross-Business policy escalation but can require Owner involvement | **OWNER-RATIFIED 2026-11-21 — C10-D063** |
| Tenant versus legal-entity restriction precedence | Tenant OFF is non-overridable veto; legal entity may further restrict | Tenant-only control, or reviewed finer-grained legal-entity configuration | Determines which legal entities may provision and guards parent/child privilege inheritance | **OWNER-RATIFIED 2026-11-21 — C10-D063** |
| Ordinary versus emergency OFF override | No ordinary override of explicit tenant OFF | Separately defined emergency override with tenant authority, independent approval and expiry | Preserves emergency recovery options while containing policy bypass risk | **OWNER-RATIFIED 2026-11-21 — C10-D063** |
| Replay under CURRENT OFF | Provisioning RPC denies replay; separately authorized read-only receipt lookup | Auth-filtered non-mutating replay return | Balances present policy enforcement, support reconciliation and historical receipt access | **OWNER-RATIFIED 2026-11-21 — C10-D063** |
| Site quota scope and counting | Per-Business cap; count provisioned and reactivatable sites | Active-only count; separate legal-entity or tenant aggregate quota | Affects costs, site reuse, suspension/reactivation, concurrency and onboarding size | **OWNER-RATIFIED 2026-11-21 — C10-D063** |
| Pending operations when feature becomes OFF | Deny new operations, revalidate queued execution, preserve committed history; corrections through separately controlled routes | Domain-specific grandfathering of approved-but-unposted work after independent safety review | Risks stranded fulfilment, stock in transit, pending approvals and receivable reconciliation; retroactive deletion prohibited | **OWNER-RATIFIED 2026-11-21 — C10-D063** |
| Emergency correction authority | Narrow, tenant-scoped, time-limited independent Approval and canonical Audit; never bypass invariants | No emergency exception; domain-specific correction-only actor grants | Defines recovery path during incidents without turning correction into unrestricted policy bypass | **OWNER-RATIFIED 2026-11-21 — C10-D063** |

Any implementation ambiguity or new policy choice outside the eight ratified decisions must fail closed for affected execution paths and be surfaced for review rather than using an invented permissive interpretation.

## 12. Finding resolution matrix — DESIGN ONLY, NOT IMPLEMENTED

| Review finding / root cause | Proposed correction | Affected canonical contract | Required adversarial verification | Remaining prerequisite / status |
| --- | --- | --- | --- | --- |
| **P1-A — unpersisted minimum-Business anchor.** Legal seed/import ID can undercut existing minimum and move policy; no pre-Business policy record exists. | Persist tenant/bootstrap scope independently of Business IDs; immutable lifecycle and explicit existing-tenant backfill; canonical audit binds policy subject/version. | NP02 tenant identity, Control versions, RLS, Audit; NP01 provisioning. | Zero Businesses with OFF; lower-ID import, sequence manipulation/reset, status/deletion/reassignment and concurrent first creation do not change authority. | **DESIGN ADDRESSED / IMPLEMENTATION NOT DONE.** Shared NP02 forward schema/auth/audit contract and ratified backfill required. |
| **P1-B — stale `statement_timestamp()` after wait.** Original setting resolution uses statement start; Control writers and creator do not share tenant lock. | Shared Control-write/creation lock order; fresh post-lock committed snapshot and decision time; deterministic scheduled/expiry precedence; one final linearization boundary. | NP02 effective Control resolver/writer; NP01 command gate and site writers. | Two independent PG17 sessions: creator starts t0 and waits; OFF starts after t0 and commits t1; creator resumes at t2 and must DENY. Include scheduled activation and override expiry during waits. | **DESIGN ADDRESSED / IMPLEMENTATION NOT DONE.** Accepted NP02 forward timing/lock contract; preserve `0101` checksum. |
| **P1-C — business `can_manage` changes tenant-wide policy.** Business-scoped owner privilege was projected onto tenant policy. | Apply the Owner-ratified active-Tenant-Owner-only administration policy, separate tenant policy grants from business grants, and enforce the same boundary for schedule/override/revert. | Canonical Auth/RLS and NP02 Control administration. | Business owner with `can_tenant=false` cannot ON, OFF, schedule, revert, grant/revoke tenant overrides; revoked and cross-tenant actors deny. | **DESIGN ADDRESSED / IMPLEMENTATION NOT DONE.** Owner-ratified Tenant Owner-only authority; NP02 signed Auth/RLS implementation and evidence still required; no delegated tenant administrator is authorized. |
| **P1-D — direct legacy bypass.** `provision_business` / `provision_site` authenticated EXECUTE and bodies omit Control. | Internalize or equivalently gate every retained callable path; coordinated EXECUTE/registry updates; audit internal callers and compatibility. | NP01 provisioning, canonical Control/registry, B-009 drift contract. | Direct authenticated/role-inherited calls while OFF deny; site cap 1 cannot be exceeded; no stale public registry entry or public unguarded alias. | **DESIGN ADDRESSED / IMPLEMENTATION NOT DONE.** Complete caller/grant inventory and coordinated forward migration. |
| **P1-E — `0112` site stage gap.** Site creation accepts stages > 0 without canonical approval completion. | Forward fail-closed stage > 0 until approved completion adapter; never count override as Approval. | NP01 site provisioning; GOV-002 canonical Approval/Audit. | Stage 1–5 deny without approved completion, both with/without Control override; zero unauthorized durable creation. | **DESIGN ADDRESSED / IMPLEMENTATION NOT DONE.** Separate forward stage fence/adapter acceptance; historical `0112` unchanged. |
| **P2 — double Control check/replay/static registry.** Wrapper delegation can consume 2 overrides; checker reads each public function body; physical request checks do not guarantee logical exactly once. | One effective logical decision after waits, private writer, public literal/equivalent evidence, operation-bound idempotency and atomic override/receipt. | NP02 Control/registry, NP01 wrappers, Auth/Audit/Approval. | One override once; duplicate/conflicting keys, replay after OFF, rollback/retry, differing actors; each retained public RPC's literal evidence and CI denial test. | **DESIGN ADDRESSED / IMPLEMENTATION NOT DONE.** Accepted tenant-aware public port + D062 evidence compatibility and exact-head CI. |

**Exact-HEAD review history:** The original GitHub COMMENT review at `e832a5e64a285404716b8388b4c8cf69076e5caa` reported **REQUEST CHANGES** and remains preserved. Subsequent independent Codex Sales **in-chat architectural PASS** covered Revision 2.1 HEAD `14f9bf541871a2dda4402f6e4e612215780135f3` for Owner ratification. The in-chat ratification-delta review of HEAD `93ecdd4e7fb450ae6dc2ec3da10810760f2fd053` reported **REQUEST CHANGES for four documentation-only P2 wording inconsistencies**, with no new P0/P1 architectural blocker. This follow-up corrects those specific wording defects; the NEW documentation HEAD still requires limited exact-HEAD delta confirmation. No original P1/P2 implementation finding has been technically fixed, and no tests or implementation acceptance are claimed.

## 13. Future disposable PostgreSQL 17 acceptance and cross-lane review gates

**These are required future tests, not passing results of Revision 2.1.** Execute on disposable PG17 using exact current trunk and approved dependency snapshots, with real independent connections and barriers. Do not claim hosted proof or technical acceptance from the previously reviewed reproductions.

| Gate | Minimum acceptance |
| --- | --- |
| Zero-Business OFF | Persist explicit OFF, inspect canonical tenant policy, deny every Business creation entrypoint, prove canonical tenant audit without Business ID. |
| Tenant policy authorization | Non-owner, business-only owner, forged/expired/revoked actor and cross-tenant administration all deny; RLS and SECURITY DEFINER boundaries hold. |
| First-Business concurrency | Two or more independent requests across the three public setup paths serialize correctly; same/different keys never duplicate or orphan Business/site/receipt. |
| Waited OFF | Owner OFF starts after creator statement starts, commits while creator waits; creator observes OFF at fresh decision boundary. |
| Schedule and expiry | Future activation, expired policy/override, equal-time version tie, overlapping schedules, expiry during lock wait; no stale setting. |
| Override and replay | Consumed once per logical operation; double physical call, successful replay, failed/late rollback, conflicting request and current OFF replay safe. |
| Legacy/direct path | `provision_business` and `provision_site` cannot bypass tenant OFF/limits/Approval; privileges, overloads, internal callers and public registry consistent. |
| Stage enforcement | Stages > 0 fail closed without actual canonical approval completion, including an override-plus-stage case; stage 0 retains other requirements. |
| Site quota | Cap 1, 50, 51 and custom; Quick/Advanced parity, reactivatable sites and concurrent direct/site/setup writers; no oversubscription. |
| Cross-tenant and membership race | Foreign tenant, legal entity/site mismatch, revoked membership during wait, stale actor and held-lock contention all deny without information leakage. |
| Canonical Audit and rollback | Tenant and Business events link correctly; no shadow ledger; late-failure rollback leaves no success receipt, audit head or consumed override; integrity checks pass. |
| Registry/evidence and checksum | Every public mutator correctly classified and has exact literal/equivalent Control evidence; CI disable proof; B-009 drift and historical checksum ledger unchanged. |
| Compatibility | Exact-head NP01, Sales (NP03B), Finance (NP06), Manufacturing (NP05A), NP02 Master, Stock, Auth, Approval, Audit; cross-lane source/API/role and rollback tests. |
| End-to-end Owner interface | Authorized zero-Business Owner ON/OFF visibility, help/preview, failure feedback, history and scope; synthetic 16-persona negatives, 390px/1440px, Bangla/English where applicable. |

**Separate hosted gate:** real signed GoTrue/RLS/RPC/Storage and 16-persona staging acceptance require distinct GO-2 authorization. Production requires distinct GO-3. D054 verified-build evidence and Owner preview cadence still apply. No hosted test or production release is authorized by publication of this contract.

## 14. Dependency plan and independent re-review handoff

The correct future order is: **(A)** the eight Bootstrap policy choices are **already Owner-ratified** (`C10-D063` / `REV-016`); finish narrow exact-HEAD documentation-delta confirmation, then independently accept the NP02 provider interface, branch/ownership allocation, migration-order compatibility and executable shared lock/Audit plan **before any coding GO**; **(B)** only under a separate scoped Owner implementation GO, build NP02 canonical tenant/bootstrap identity, Control/administration/RLS, Audit and fresh post-lock evaluation; **(C)** coordinate direct legacy privilege/registry closure and site-stage forward safety; **(D)** under separately scoped authorization, integrate future NP01 Bootstrap public entrypoints without double consumption; **(E)** run disposable PG17 adversarial/cross-lane verification on accepted exact heads; **(F)** obtain independent implementation review and separately authorized integration/hosted-release gates. No new implementation assignment, branch ownership transfer, migration number, merge or deployment is authorized here.

**Independent Codex Sales re-review brief (read-only):** review the actual latest PR #119 HEAD (not the prior `e832a5e...`), compare this document with the full 2026-11-21 review and all six P1/P2 entries above, and confirm:
1. Stable tenant policy identity and businessless Audit do not invent NP01 shadows.
2. Every Control writer and creator shares a deadlock-free lock protocol and *fresh post-wait snapshot plus decision time*.
3. Only appropriate tenant-level principals administer OFF, schedules and overrides.
4. All direct legacy public/internal writers are closed or equivalently gated with registry/EXECUTE compatibility.
5. Site stages > 0 fail closed until genuine canonical Approval completion exists.
6. Public D062 evidence, one logical decision, replay and override semantics are mutually satisfiable.
7. D033/D045/D049/D054/D055/D057/D061/D062 and R071/R072/R123/R124/R128 remain inherited rather than recreated.
8. The eight Owner-ratified Bootstrap policies are correctly marked approved; no extra delegation or unapproved policy is implied, and the A044/A045/A052 Intelligent Control backlog is not imported into PR #119.

Report **PASS / REQUEST CHANGES / BLOCKED** for *architectural sufficiency*, cite exact new head and source evidence, and distinguish design completeness from implemented technical fixes. **Do not** mark Draft PR ready, merge, edit SQL/tests/other docs, dismiss the earlier review, alter already ratified Owner choices, or infer deployment permission.

### Publication and safety notice

This document records **eight already Owner-ratified policies** and the previously independently reviewed **architectural PASS at exact HEAD `14f9bf541871a2dda4402f6e4e612215780135f3` (in-chat evidence)**. Its later ratification delta received a **documentation-only P2 REQUEST CHANGES** at `93ecdd4e7fb450ae6dc2ec3da10810760f2fd053`; the present wording corrections require a fresh, narrow exact-HEAD delta confirmation. The original GitHub review remains historical and unchanged. **Architecture adequacy and Owner policy ratification do not mean implementation, PG17 tests, integration or release acceptance.** This documentation makes no SQL behavior change; coding, migrations, merges, hosted staging and production require distinct explicit scoped Owner authorization. GO-2 and GO-3 remain HOLD. `main`, the canonical trunk and protected IMG-ERP-SG remain untouched.
