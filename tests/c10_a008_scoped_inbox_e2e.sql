-- C10-GOV-002 inbox source/role privacy. Run after typed approval E2E suite.
\set ON_ERROR_STOP on
SET ROLE authenticated;

-- Local business owner sees all requests in their business, not foreign tenants.
SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
DO $t$
BEGIN
 IF (SELECT count(*) FROM c10_demo.approval_inbox_v1) <> 3
   OR (SELECT count(*) FROM c10_demo.approval_events) <> 1
   OR (SELECT count(*) FROM c10_demo.approval_policy_versions_v1) <> 2
 THEN RAISE EXCEPTION 'FAIL: scoped business approver inbox'; END IF;
END $t$;

-- Manager can read THEIR two requests, but not Owner's separate request or policy.
SELECT set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',false);
DO $t$
BEGIN
 IF (SELECT count(*) FROM c10_demo.approval_inbox_v1) <> 2
   OR (SELECT count(*) FROM c10_demo.approval_requests) <> 2
   OR (SELECT count(*) FROM c10_demo.approval_events) <> 1
   OR (SELECT count(*) FROM c10_demo.approval_policy_versions_v1) <> 0
   OR (SELECT count(*) FROM c10_demo.approval_inbox_v1
       WHERE display_status = 'expired') <> 1
 THEN RAISE EXCEPTION 'FAIL: manager own-only inbox/expiry'; END IF;
END $t$;

-- Active site-only user can see their stock site but ZERO approval rows/counts.
SELECT set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',false);
DO $t$
BEGIN
 IF NOT c10_demo.can_see_business(1,101)
 THEN RAISE EXCEPTION 'FAIL: site-grant fixture missing'; END IF;
 IF (SELECT count(*) FROM c10_demo.approval_inbox_v1) <> 0
   OR (SELECT count(*) FROM c10_demo.approval_requests) <> 0
   OR (SELECT count(*) FROM c10_demo.approval_events) <> 0
 THEN RAISE EXCEPTION 'FAIL: site-only approval count leaked'; END IF;
END $t$;

SELECT set_config('request.jwt.claim.sub','55555555-5555-4555-8555-555555555555',false);
DO $t$
BEGIN
 IF (SELECT count(*) FROM c10_demo.approval_inbox_v1) <> 0
 THEN RAISE EXCEPTION 'FAIL: investor inbox exposed'; END IF;
END $t$;

SELECT set_config('request.jwt.claim.sub','66666666-6666-4666-8666-666666666666',false);
DO $t$
BEGIN
 IF (SELECT count(*) FROM c10_demo.approval_inbox_v1) <> 0
 THEN RAISE EXCEPTION 'FAIL: revoked member inbox exposed'; END IF;
END $t$;

SELECT set_config('request.jwt.claim.sub','77777777-7777-4777-8777-777777777777',false);
DO $t$
BEGIN
 IF (SELECT count(*) FROM c10_demo.approval_inbox_v1) <> 0
 THEN RAISE EXCEPTION 'FAIL: foreign tenant inbox exposed'; END IF;
END $t$;

SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
DO $t$
BEGIN
 IF (SELECT count(*) FROM c10_demo.approval_inbox_v1) <> 3
 THEN RAISE EXCEPTION 'FAIL: tenant owner own portfolio inbox'; END IF;
END $t$;
RESET ROLE;
DO $t$
BEGIN
 IF has_table_privilege('anon','c10_demo.approval_inbox_v1','SELECT')
 THEN RAISE EXCEPTION 'FAIL: anon can enumerate approval count'; END IF;
 IF has_table_privilege('authenticated','c10_demo.approval_inbox_v1','UPDATE')
 THEN RAISE EXCEPTION 'FAIL: inbox is writable'; END IF;
 RAISE NOTICE 'PASS: approval inbox RLS, requester/approver privacy, foreign/site/revoked/anon count negatives';
END $t$;
