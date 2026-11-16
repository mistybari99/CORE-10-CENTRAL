# NP01 B-020 — first genuinely enforced RPC (code, not certification)

Added `0018_np01_approval_policy_control` on the NP01 working branch. It replaces the
existing `core10.publish_approval_policy_v1` implementation without changing
its SQL signature, RLS, GRANTs or legacy authorization check. It calls
`core10.control_check_v1(p_business,'gov002.approval_policy',NULL)` after
`core10.can_manage` and before policy versioning, replay or insert.

Feature disabled -> `CONTROL_DISABLED:gov002.approval_policy` and no new version.
Feature enabled -> existing explicit 5–43200 minute TTL supported, or NULL
uses the Owner's validated `params.ttl_minutes`. All versions remain canonical.
No alternate Approval+Audit table or secondary authorizer created.

`tests/migrations/np01-control-publish-e2e.sql` uses synthetic PostgreSQL 17
fixtures, Owner policy disable, denial, reenable and configured TTL default,
then rolls back the fixture transaction. Existing NP01/GOV002 and B010 suites
must stay green at the exact pushed head.

**Important remaining dependency:** Claude's `0102` seed declares the RPC
`pending` even after this code adds an actual Control check. A coordinated
post-0102 registry migration is still required to mark it `enforced`.
NP01's own 0017/0018 migrations apply before 0100 and therefore must never
pretend to update a table that does not exist yet. `0017` separately closes
the six newly exposed functions that have no B010 registration.

No Supabase staging migration, production release, Cloudflare deployment,
or legacy IMG-ERP-SG write. This is B-020 partial integration only.
