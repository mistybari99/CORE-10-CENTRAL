# Repository, PR and Code Reconciliation

**Observed:** 2026-11-11. No branch was merged, rebased, deployed or production-tested.

## Exact heads

| Source | SHA | Truth |
|---|---|---|
| `main` | `c39052910758ca285a7a4d56e9c4f4873cb7d99c` | legacy root/`v2`, merged preservation/setup/advisory code; no PR #7 foundation |
| PR #7 | `1c55625f36ffff8a54d3dab431ad52e0c484bd6b` | 25/25 current checks pass; disposable/synthetic only |
| PR #20 | `97e854b945441898caee3998df7f9f8d1dd41547` | draft/HOLD hierarchy overlap |
| PR #21 | `6b932e7266de4a143980a7a57bd3bc4b2404c9b1` | costing draft, isolated CI |
| PR #22 | `97e13b92474db2ae847f2786fe6baa1b465412e4` | access governance draft, not live Auth |
| PR #23 | `a077a30b19a5aea6edd5520935b9793d984076e9` | offline proposal/replay draft |
| PR #27 | `9da6403bb1a94bf3acc4738a4b0ef97729a717b6` | provider-neutral integration ports draft |
| PR #54 | `a2ab4009c754b234427a79c16dc18cba6da406d9` | D049 documentation, no intent runtime |
| PR #59 | `2e9c4cf3a62b81f32f798ef1a1096bb0b4c4e62e` | Claude A055 WIP; planning denial test currently fails |
| PR #60 | `a25fcaebff4e897f7e3ff4cb633999f80fef7386` | current preview head; not all-green |
| PR #63 | `6e86511d6e6fe501c1faf02dc8a2e3e37b2a820f` | A053/A054 assignment only |
| PR #65 | `e3b1dcf23c1309365a91a534a4395f978b49f6ef` | A057 assignment only |
| PR #66 | `6efd9630f8083764ebefa5645d9f726a0c4db649` | A056 RPC contract only |
| PR #67 | `7ccf10450be8e6bf33fea77122ae146db337befd` | Issue #68 directive, docs only |

## PR #60 provenance correction

The recorded green checkpoint `42aecebfd460915394c6f1bfbbc69c8b5189981f` is an ancestor, not current head. Current head failures include root `AGENTS.md` rejected by the public served-set check and browser/workforce jobs blocked during runner package/DNS installation. Passing older 10/10 evidence must not be attributed to `a25fcae…`. The Worker remains GET/HEAD only with `connect-src 'none'` and synthetic walkthrough labels; current public runtime was not reverified in this pass.

## Reuse/gap matrix

| Capability | Reuse | Gap / risk |
|---|---|---|
| hierarchy/auth | PR #7 A018/A019 composite scope | real GoTrue/RLS and current live mapping not verified |
| permissions | A021 plus PR #22 A034 | reconcile effective deny/delegation; no module-local authority |
| stock | A018/A048 commands | lot/serial/reservation/valuation and signed stage incomplete |
| operations | A049 first slice | one-item/simple flow; partial states, finance and certified COGS incomplete |
| finance | A022/A023 truth labels; PR #21 costing | A022 is manual-unverified, not canonical GL |
| offline | `core10-offline-drafts.js`, PR #23 | encrypted key provisioning and device/revocation stage evidence |
| integration | PR #27 ports/outbox/secrets/signature | Drive family/OAuth absent; production grant boundary unverified |
| assets/work orders | PR #59 A055 candidate | red test and module-local grants/policies need parity reconciliation |
| workforce | PR #55/A051 | A053/A054 Claude-owned; do not edit |
| CRM | legacy scoped under REV-009; PR #66 contract | A056/A057 Claude-owned, unfinished |
| preview | PR #60 shell | current-head provenance/check failures |
| root/`v2` | selected blobs differ | no full semantic parity contract |

## Security/data findings

- Historical sanitized snapshot records 136 `locations` and 72 `org_units` FK references; current live definitions are **UNKNOWN / NOT VERIFIED**.
- `org_scope_on` stays blocked by signed role matrix, policy/grant diff, staging restore and rollback gates.
- `internal/sqlparts/part04.sql` `partner_calculate()` uses all locations for non-location scope; business-profit use is blocked pending scoped resolver and caller/grant inventory.
- Synthetic SQL roles/local HMAC JWTs are not Supabase-issued GoTrue sessions.
- Pages allowlist tests do not prove repository Pages source configuration; public SQL exposure remains not fully certified.

## Ownership boundary

Do not edit A052 intent, A053/A054 workforce/payroll, A055 asset-maintenance, A056 CRM lifecycle or A057 CRM/commerce namespaces. Reuse A018/A021/A034/A048/A049, PR #23 and PR #27 rather than cloning them. This Issue #68 slice owns only `docs/strategy/`, `internal/demo-factory/`, `tests/demo-factory/` and its dedicated workflow.

## Post-Claude parity status

`POST_CLAUDE_PARITY_REVIEW.md` is intentionally not created yet: the observed Claude outputs are WIP or assignment/contract-only, not completed tested delivery. This is an explicit remaining gate, not an omission.
