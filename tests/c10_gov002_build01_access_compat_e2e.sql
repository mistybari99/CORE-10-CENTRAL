-- C10-CAP-GOV-002 cross-Build01 compatibility probe; disposable PostgreSQL 17 ONLY.
-- Requires pinned Codex Build01 A018/A020/A021/A034 + Build01 integration SQL,
-- followed by the existing GOV002 approval stack. Does not alter either engine.
-- Signed GoTrue staging is NOT tested: this test uses synthetic JWT fixture claims.
\set ON_ERROR_STOP on
BEGIN;

-- In a disposable fixture a current business owner is permitted to publish
-- the already-existing non-posting review policy; not a live financial permission.
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"22222222-2222-4222-8222-222222222222"}', true);
SELECT set_config('request.jwt.claim.sub', '22222222-2222-4222-8222-222222222222', true);
DO $b02$
DECLARE policy_id bigint;
BEGIN
 IF NOT c10_demo.can_manage(1,101) THEN
  RAISE EXCEPTION 'COMPAT_OWNER_NOT_RECOGNIZED';
 END IF;
 policy_id:=c10_demo.publish_approval_policy_v1(
  101,'integration_test','compatibility_review',60,'compat_policy_20261112');
 IF policy_id IS NULL OR policy_id<=0 THEN
  RAISE EXCEPTION 'COMPAT_POLICY_MISSING';
 END IF;
END $b02$;

-- A current manager may make a typed request, but may not approve it.
SELECT set_config('request.jwt.claims', '{"sub":"33333333-3333-4333-8333-333333333333"}', true);
SELECT set_config('request.jwt.claim.sub', '33333333-3333-4333-8333-333333333333', true);
DO $b02$
DECLARE req_id bigint;
BEGIN
 IF NOT c10_demo.can_business(1,101) OR c10_demo.can_manage(1,101)
 THEN RAISE EXCEPTION 'COMPAT_MANAGER_SCOPE'; END IF;
 req_id:=c10_demo.submit_typed_approval_v1(101,'integration_test',
  'compatibility_review','compat-source-1',1,'{"review":"non-posting"}'::jsonb,'compat_req_20261112');
 IF req_id IS NULL OR req_id<1 THEN RAISE EXCEPTION 'COMPAT_TYPED_REQUEST_MISSING'; END IF;
 BEGIN
  PERFORM c10_demo.decide_approval(req_id,'approve','compat_maker_try_01');
  RAISE EXCEPTION 'COMPAT_MAKER_SELF_APPROVED';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'approval_not_authorized' THEN RAISE; END IF;
 END;
END $b02$;

-- Business owner can see one scoped source and its immutable policy/version.
SELECT set_config('request.jwt.claims', '{"sub":"22222222-2222-4222-8222-222222222222"}', true);
SELECT set_config('request.jwt.claim.sub', '22222222-2222-4222-8222-222222222222', true);
DO $b02$
BEGIN
 IF (SELECT count(*) FROM c10_demo.approval_status_report_v1 WHERE business_id=101
   AND source_key='compat-source-1')<>1 THEN
  RAISE EXCEPTION 'COMPAT_OWNER_INBOX_NOT_SCOPED'; END IF;
END $b02$;

-- Site-only staff and foreign tenants cannot see or decide a review even when
-- they receive an untrusted client-side role claim (Build01 ignores metadata).
SELECT set_config('request.jwt.claims',
 '{"sub":"44444444-4444-4444-8444-444444444444","user_metadata":{"role":"tenant_owner"},"app_metadata":{"is_owner":true}}',true);
SELECT set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',true);
DO $b02$
BEGIN
 IF (SELECT count(*) FROM c10_demo.approval_status_report_v1 WHERE business_id=101)<>0
 THEN RAISE EXCEPTION 'COMPAT_SITE_APPROVAL_LEAK'; END IF;
 IF c10_demo.can_manage(1,101) THEN RAISE EXCEPTION 'COMPAT_CLAIM_ROLE_PROMOTION'; END IF;
END $b02$;
SELECT set_config('request.jwt.claims','{"sub":"77777777-7777-4777-8777-777777777777"}',true);
SELECT set_config('request.jwt.claim.sub','77777777-7777-4777-8777-777777777777',true);
DO $b02$
BEGIN
 IF (SELECT count(*) FROM c10_demo.approval_status_report_v1 WHERE business_id=101)<>0
 THEN RAISE EXCEPTION 'COMPAT_FOREIGN_TENANT_LEAK'; END IF;
END $b02$;

RESET ROLE;
-- Expiry in the *canonical Build01 membership*, NOT client-side state,
-- immediately revokes the owner's ability to read and decide this request.
UPDATE c10_demo.business_members SET valid_until=clock_timestamp()-interval '1 minute'
 WHERE tenant_id=1 AND business_id=101
 AND user_id='22222222-2222-4222-8222-222222222222';
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims','{"sub":"22222222-2222-4222-8222-222222222222"}',true);
SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',true);
DO $b02$
DECLARE req_id bigint;
BEGIN
 IF c10_demo.can_manage(1,101) OR
    (SELECT count(*) FROM c10_demo.approval_status_report_v1 WHERE business_id=101)<>0
 THEN RAISE EXCEPTION 'COMPAT_EXPIRED_OWNER_RETAINED_INBOX'; END IF;
 SELECT id INTO req_id FROM c10_demo.approval_requests WHERE submit_key_v1='compat_req_20261112';
 BEGIN
  PERFORM c10_demo.decide_approval(req_id,'approve','compat_expired_owner_01');
  RAISE EXCEPTION 'COMPAT_EXPIRED_OWNER_APPROVED';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'approval_not_authorized' THEN RAISE; END IF;
 END;
END $b02$;
RESET ROLE;

-- Canonical Build01 membership revocation must block existing makers and
-- remove their own approval request from the RLS-scoped inbox.
UPDATE c10_demo.business_members SET active=false
 WHERE tenant_id=1 AND business_id=101
 AND user_id='33333333-3333-4333-8333-333333333333';
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims','{"sub":"33333333-3333-4333-8333-333333333333"}',true);
SELECT set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',true);
DO $b02$
BEGIN
 IF c10_demo.can_business(1,101) OR
    (SELECT count(*) FROM c10_demo.approval_status_report_v1 WHERE business_id=101)<>0
 THEN RAISE EXCEPTION 'COMPAT_REVOKED_MAKER_RETAINED_INBOX'; END IF;
 BEGIN
  PERFORM c10_demo.submit_typed_approval_v1(101,'integration_test',
   'compatibility_review','compat-source-2',1,'{}'::jsonb,'compat_revoked_request_01');
  RAISE EXCEPTION 'COMPAT_REVOKED_MAKER_CREATED_APPROVAL';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'approval_submit_denied' THEN RAISE; END IF;
 END;
END $b02$;
RESET ROLE;

-- The approval engine is independent from stock posting. At this point no
-- approved operational execution or domain movement may be observed.
DO $b02$ BEGIN
 IF EXISTS (SELECT 1 FROM c10_demo.approval_demo_execution_receipts_v1)
   OR EXISTS (SELECT 1 FROM c10_demo.approval_events)
   OR (SELECT count(*) FROM c10_demo.stock_movements)<>0
 THEN RAISE EXCEPTION 'COMPAT_APPROVAL_TEST_CREATED_DOMAIN_SIDE_EFFECT'; END IF;
 RAISE NOTICE 'PASS GOV002+Build01 same-database membership expiry/revocation, maker-checker, tenant privacy, forged metadata and zero posting';
END $b02$;
ROLLBACK;