# CORE-10-CENTRAL — Owner Inbox Release / Rollback Gate

**Scope:** C10-A006/A007, read-only Owner Inbox. **State:** approval-required candidate; never auto-install or auto-merge.

## Step 09: verified live conditions (2026-11-10)

Read-only Supabase checks found: 12 relevant public tables with RLS enabled, matching source columns, owner / mapping helper permission boundaries, 1 active business, organization mode OFF, and **no** installed `core10_owner_inbox_v1` RPC. An isolated two-business JWT test is not a substitute for a live signed-in multi-business test. Live user JWT tests have NOT been completed.

Run `CORE10_OWNER_INBOX_RELEASE_PREFLIGHT.sql` read-only. Its last two lines are intentionally non-automatable: `08_real_signed_sessions,MANUAL_REQUIRED` and `09_release_decision,STOP_UNTIL_OWNER_APPROVAL`. Treat any `BLOCK` as NO-GO; **never** enable organization mode or create a second business simply to force a green result.

## Step 10: release preparation (no live changes)

1. Preserve the validated GitHub PR dependencies: PR #4 maps authoritative approval sources; PR #5 is a stacked draft on PR #4 and includes the strict frontend scope guard. PR #3 carries an overlapping standalone frontend fix. Review overlapping changes and avoid duplicate cherry-picks or unreviewed merges.
2. Before an owner-approved deployment, capture a timestamped database backup and **verify that it can be restored** in an isolated environment. Snapshot current function signatures, grants, source table RLS policies, organizational rules and GitHub commit SHA. Run preflight and retain its raw output with the release PR, not the master Decision Book.
3. Verify a separate *staging* environment with two active businesses and real Supabase-issued signed-in Owner, Staff, revoked/inactive, and anonymous sessions. Call the actual Data API (not synthetic SQL `SET ROLE` alone) and assert 3 positive scopes, all negative denials, non-active business exclusion, canonical IDs, no cross-business rows, and no privileged grants to anon. Test a fallback with the RPC absent.
4. Do not change live `org_scope_on` until the wider organization's RLS, roles, assignments, and dependent apps have independently passed their own migration/security plan. The current live preflight will correctly remain blocked.
5. Generate a proper migration using the installed Supabase CLI (`supabase migration new`), after checking `supabase --help` / migration help. This release plan is **not** itself a migration. Have the owner review SQL DDL and the exact reversible rollback before applying.
6. Once separately authorized, deploy only to staging first, rerun all CI + real-session API tests, inspect function owner and `EXECUTE` grants, then request an explicit production go/no-go decision. Only after approval: production canary, authenticated read-only smoke, monitor errors, and follow the rollback decision below. Do not expose Approve / Reject yet.

## Emergency rollback — owner-authorized DBA action ONLY

If this release added the function for the first time and the new RPC exposes data incorrectly: immediately stop frontend routing to it, and have an authorized DBA revoke `EXECUTE` from `authenticated` (the kill switch), then **only when dependency and backup review permit**, drop exactly the newly added `public.core10_owner_inbox_v1(bigint,integer)` signature. The existing fallback frontend shows a warning and does **not** read old approval data. If the function existed before deployment, restore the captured earlier definition/owner/grants instead of blindly dropping it. Do not modify legacy approvals or organizational flags as part of this rollback.

**No production DDL or DB writes are authorized by this document.** This plan protects both live data and the prior Islamia ERP workflow.
