# NP01 → Owner Control port handoff (DEC-08)
Status: pending B-010 Control port implementation by Claude on trunk.

NP01 publishes no second control store. Every business-configurable rule below must
be registered with Claude's canonical `core10` Control port and tested server-side
before B-005..B-008 can be READY_FOR_INTEGRATION.

| Feature | Proposed key | Scope | Binding | Current readiness |
| --- | --- | --- | --- | --- |
| GOV-002 policy publish & threshold | `gov002.approval_policy` | business/site/action | approval.none for control edit; role=Owner | pending B-010 |
| GOV-002 routed review/exception | `gov002.review` | business/site/action | owner-configured 0..5 stage route | pending B-010 |
| GOV-003 readiness/risk/export | `gov003.review_export` | business/site/role | export approval configurable | pending B-010 |
| SETUP001 profile preview | `setup001.profile_preview` | business type/owner | approval.none (read-only) | pending B-010 |
| SETUP001 create/activate | `setup001.provision` | tenant/business/site | approval policy Owner-configured | NOT CONNECTED |

The `0013` TRUNCATE guard is an unchangeable integrity invariant, not a
business setting. The Owner may review its status but may NOT disable audit
immutability, tenant isolation, or authorization protections.

Until these mappings are executable, the copied PR #94 setup adapter remains an
advisory-only preflight and must not claim business activation, transaction posting,
tax certification or inherited full ERP readiness. Legacy Islamiya D051 is protected.
No hosted apply, preview deploy or sensitive release is authorized by this document.
