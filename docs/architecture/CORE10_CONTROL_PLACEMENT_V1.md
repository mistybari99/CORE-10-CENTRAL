# C10-A043 — Universal Studio and Business App Control Placement

**Owner requirement:** Keep one Universal Owner Control Studio, while letting the Owner place any eligible control inside each Business App, only in Central, or in both. Owner can change the placement later. All businesses use the same canonical control definitions, not separate permission engines.

**Current stage:** pure contract/proposal and tests. Not a live owner interface, configuration database or authorization grant.

## Placement choices

| Choice | Main Universal menu | Selected Business App |
|---|---|---|
| Central only | Normal navigation | Not in local menu |
| Business only | Available to Owner through Universal registry/search | Appears in business controls |
| Both | Appears centrally | Appears locally |
| Hidden from menus | Still discoverable to authorized Owner | Absent from normal menus |

Placement is **per tenant and per business**. A Tenant default applies if there is no business override. Moving a control changes only where its interface appears; it does not move data, modify its enabled setting, remove audit history or duplicate its policy. Central Owner can still find every control through the Universal registry.

## Five distinct owner decisions

1. **Navigation placement:** Central only, Business only, Both, Hidden.
2. **Operational enablement:** ON/OFF for eligible Tenant, Business or Site according to A042 hierarchy and dependency barriers.
3. **Local edit mode:** Central-only; eligible Business Owner may propose a change; or Business Owner must request central approval.
4. **Action authorization:** server-side verified grants, RLS/RPC, session/role/site scope and release readiness — never derived from a visible menu.
5. **Staff visibility:** Show/Locked/Hidden, completely separate from actual permission.

Different businesses can use different values for the SAME control ID. Business A may use an option while Business B disables or hides it; neither overwrites the other.

### Local edit modes

- central_only: Business may view a placed control but ordinary local editing is locked.
- business_owner: eligible Business Owner may submit its business-scoped change; signed backend authority is still mandatory.
- request_approval: local Business Owner submits a change request to the one canonical approvals queue.

A hidden control must remain searchable/manageable through the authorized Universal Studio registry. The Studio itself must never disappear, even when individual controls are shown locally.

## Future operational UI navigation

Universal Studio → Control Library → select a control → Placement → select a Business → choose Central/Business/Both/Hidden → choose Local edit authority → Preview → Approve/Apply → Versioned audit.

Business App → Settings → Business Controls → local projection by group/order → view effective value or request/edit if permitted. Both surfaces point to the same canonical ID and record.

Each control has a configurable menu group and sort order. Local role widgets never grant server authority. Editing requires valid authenticated Owner context, Tenant/Business scope, applicable approved delegation, explicit approval (when required), idempotent backend change and immutable audit.

## Proposed server persistence — NOT installed

One placement preference per tenant+business (nullable tenant baseline)+control:
tenant_id, business_id, control_id, placement, local_edit_mode, menu_group, sort_order, version, updated_by, updated_at.

Uniqueness must handle NULL business_id without collisions. Use the existing A021 Owner controls and A034 Access Governance authoritative security and approval records. Never create a second business-specific copy of the grant tables. Resolve permissions on the backend; do not trust browser-side identity or UI role toggles.

## Files in this increment

- internal/universal-control-studio/control-placement-v1.js — one control registry; tenant default and business-level placement projection; per-business effective setting preview; draft placement/local change proposals.
- tests/c10_a043_business_control_placement.test.js — two businesses, another tenant, placements, inherited flags, deny boundary, delegated settings and cross-business negative tests.
- .github/workflows/core10-a043-control-placement-ci.yml — deterministic CI, no DB or production access.

### Remaining before real use

Build responsive Universal Studio + Business Settings UI, signed Owner API, canonical placement storage/RLS, role delegation and change queue, audit, cross-tenant signed negative E2E and release verification. Current previews and proposals always return canExecute=false.
