# CORE10 B01 handoff

RELEASE HOLD. The draft branch is `build/codex-b01-core-app-20261126`, based on canonical trunk `ccr-15ed11dd-n3hw5h` at `3e008e8ec7db896f46a94ab8ca3d91271905d71d`. The [publication index](https://docs.google.com/document/d/1uDVVc33jsMvFcg0t1vZ-Et6VvvnSA0Fvk9PBJivQe_k/edit) records the exact pushed head, draft PR and recovery chain.

## Batch A

- The shell and existing workspace view load one stylesheet for light/dark colors, the Bengali-capable font stack and control/panel radii. The workspace view now uses the shell foreground color in light mode.
- One bn/en dictionary supplies shell chrome, route notices and localized accessible landmark and selector names. Desktop and mobile share matching module labels while retaining the existing compact Home and Stock labels.
- The central shell continues to use B-039 grouped desktop and mobile navigation and B-040 signed context. All 11 hashes, iframe destinations, keyboard interactions, module auth and existing staging/replay behavior remain in place.
## Batch B

- Home shows the selected business and known role from the signed `build01_context_v1` response in migration 0117. It offers Setup through `can_manage` for the selected business or `can_manage_bootstrap` for the selected group. It offers Stock through `can_manage`, the existing workbench's business filter.
- Loading and context failure clear the recommendations. The workspace renders explicit signed-out, empty and error messages in both languages. Direct routes and the original desktop and mobile navigation stay available. Each module still checks its own scope and actions.
- Setup identifies its independent sign-in. Approvals identifies the offline sample and Sales and Manufacturing retain their replay banner. No route claims new live capabilities. The shell has no approved action-to-route entitlement contract for other modules.

## Batch C

Master Data consumes the same-user shell business preference at mount through its existing `preferBusiness` option. The preference is in memory and carries no token or permission. The Master client checks its own signed session and the pinned module honours the preference only if its own context includes that business. Native business selection and stand-alone sign-in retain their existing behaviour. Changing shell context leaves an open Master workspace intact. Reopen Master to use a newly selected business. The module's existing reads are business-scoped.

| Route or surface | Remaining dependency |
| --- | --- |
| Master Data site filter | Existing list RPCs have no site selector. |
| Business dashboard | The pinned UI opens the portfolio and drills into business and site with its own actions. Its mount interface does not accept shell context. |
| Owner Control | The pinned UI chooses and validates its own first business. Its mount interface does not accept shell context. |
| Setup & access | The pinned UI has an independent sign-in and private picker. A shared preference requires a supported module entry interface. |
| Stock operations | The workbench owns its business selector and command scope. Workbench changes belong to the B-038/NP03A lane. B-012-REQ1 remains outside this draft. |
| Approvals, Sales and Manufacturing | The shipped views use sample or replay data. A supported signed entry contract is required for propagation. |
| Home, Staff and Feature permissions sample workspaces | The PACK-02 fixtures retain their independent projection. Home recommendations come from the signed shell only. |

## Batch D and integration

The draft preserves the frozen import, runtime, build inputs and full verifier. The checkpoint records the deterministic Worker build, current and historical provenance, legacy and signed-context static guards, targeted browser tests, and the loopback sweep of all 11 routes in both languages at 390 and 1440 px. The full existing verifier contains hosted sign-in probes and was outside direct local execution. GitHub CI results on the exact draft head are recorded in PR #160.

No migration, hosted data changes, Worker deployment, integration merge or owner acceptance occurred under B01. PaperOps, Paint, module engines and protected legacy remain outside this draft.

For canonical handover §5/§6, propose recording Batch A shell foundation, Batch B server-scope recommendations and readiness, and Batch C Master Data business preference as implemented in this draft. Keep other per-module context contracts and a general role-to-route policy open. Resume from the latest verified publication receipt and refresh trunk and coordination claims before review.
