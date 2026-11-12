-- GOV002 dynamic 3-to-5 stage E2E, run in disposable PG17 AFTER existing suite.
\set ON_ERROR_STOP on
BEGIN;
INSERT INTO c10_demo.business_members(tenant_id,business_id,user_id,role,active)
 VALUES (1,101,'99999999-9999-4999-8999-999999999999','manager',true)
 ON CONFLICT DO NOTHING;
INSERT INTO c10_demo.business_members(tenant_id,business_id,user_id,role,active)
 VALUES (1,101,'88888888-8888-4888-8888-888888888888','manager',true),
        (1,101,'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','business_owner',true)
 ON CONFLICT DO NOTHING;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',true);
DO $test$
DECLARE policy bigint;
BEGIN
 policy:=c10_demo.publish_approval_policy_v1(101,'demo_advanced','route_three',60,'dyn3_policy_20261112');
 IF c10_demo.configure_approval_route_dynamic_v2(
    policy,ARRAY['business_owner','manager','tenant_owner'],'dyn3_route_20261112')<>policy
 OR c10_demo.configure_approval_route_dynamic_v2(
    policy,ARRAY['business_owner','manager','tenant_owner'],'dyn3_route_20261112')<>policy
 THEN RAISE EXCEPTION 'DYNAMIC_3_REPLAY_MISSING'; END IF;
 BEGIN
  PERFORM c10_demo.configure_approval_route_dynamic_v2(policy,ARRAY['business_owner','business_owner','tenant_owner'],'dyn3_route_20261112');
  RAISE EXCEPTION 'DYNAMIC_3_CHANGED_ROUTE_ACCEPTED';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'dynamic_route_replay_conflict' THEN RAISE; END IF; END;
 BEGIN
  PERFORM c10_demo.configure_approval_route_dynamic_v2(policy,ARRAY['manager','business_owner','tenant_owner'],'dyn_invalid_20261112');
  RAISE EXCEPTION 'DYNAMIC_3_BAD_START_ACCEPTED';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'invalid_dynamic_approval_route' THEN RAISE; END IF; END;
 BEGIN
  PERFORM c10_demo.configure_approval_route_dynamic_v2(policy,ARRAY['business_owner','manager','manager','manager','manager','tenant_owner'],'dyn_invalid6_20261112');
  RAISE EXCEPTION 'DYNAMIC_6_STAGES_ACCEPTED';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'invalid_dynamic_approval_route' THEN RAISE; END IF; END;
 policy:=c10_demo.publish_approval_policy_v1(101,'demo_advanced','route_five',60,'dyn5_policy_20261112');
 PERFORM c10_demo.configure_approval_route_dynamic_v2(
  policy,ARRAY['business_owner','manager','manager','business_owner','tenant_owner'],'dyn5_route_20261112');
END $test$;
SELECT set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',true);
SELECT c10_demo.submit_typed_approval_v1(101,'demo_advanced','route_three','d3source',1,'{}'::jsonb,'dyn3_submit_20261112');
SELECT c10_demo.submit_typed_approval_v1(101,'demo_advanced','route_five','d5source',1,'{}'::jsonb,'dyn5_submit_20261112');
-- Pin server-created request IDs while the authenticated maker can still read them.
-- Later stage actors are intentionally not allowed to enumerate the owner's inbox.
SELECT set_config('c10.gov002_dyn3_request_id',
 (SELECT id::text FROM c10_demo.approval_requests WHERE submit_key_v1='dyn3_submit_20261112'),true);
SELECT set_config('c10.gov002_dyn5_request_id',
 (SELECT id::text FROM c10_demo.approval_requests WHERE submit_key_v1='dyn5_submit_20261112'),true);
DO $test$
DECLARE req bigint;
BEGIN
 req:=current_setting('c10.gov002_dyn3_request_id',true)::bigint;
 BEGIN
  PERFORM c10_demo.decide_approval(req,'approve','dyn3_self_20261112');
  RAISE EXCEPTION 'DYNAMIC_MAKER_APPROVED';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'approval_not_authorized' THEN RAISE; END IF; END;
END $test$;
SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',true);
DO $test$
DECLARE req bigint;policy bigint;r bigint;
BEGIN
 req:=current_setting('c10.gov002_dyn3_request_id',true)::bigint;
 SELECT policy_id_v1 INTO policy FROM c10_demo.approval_requests WHERE id=req;
 BEGIN
  PERFORM c10_demo.configure_approval_route_dynamic_v2(policy,ARRAY['business_owner','manager','tenant_owner'],'dyn3_route_20261112');
  -- Idempotent same route is valid even after use.
 EXCEPTION WHEN OTHERS THEN RAISE EXCEPTION 'DYNAMIC_REPLAY_AFTER_USE_FAILED %', SQLERRM; END;
 r:=c10_demo.decide_approval(req,'approve','dyn3_s1_20261112');
 IF c10_demo.decide_approval(req,'approve','dyn3_s1_20261112')<>r
 OR (SELECT status FROM c10_demo.approval_requests WHERE id=req)<>'pending'
 OR (SELECT display_status FROM c10_demo.approval_status_report_v1 WHERE request_id=req)<>'awaiting_stage_2'
 THEN RAISE EXCEPTION 'DYNAMIC_3_FIRST_STAGE_FAILED'; END IF;
 req:=current_setting('c10.gov002_dyn5_request_id',true)::bigint;
 PERFORM c10_demo.decide_approval(req,'approve','dyn5_s1_20261112');
 IF (SELECT required_checks FROM c10_demo.approval_status_report_v1 WHERE request_id=req)<>5
 THEN RAISE EXCEPTION 'DYNAMIC_5_REQUIRED_COUNT_WRONG'; END IF;
END $test$;
SELECT set_config('request.jwt.claim.sub','99999999-9999-4999-8999-999999999999',true);
DO $test$
DECLARE req bigint;
BEGIN
 req:=current_setting('c10.gov002_dyn3_request_id',true)::bigint;
 IF c10_demo.decide_approval(req,'approve','dyn3_s2_20261112') IS NULL
 THEN RAISE EXCEPTION 'DYNAMIC_3_SECOND_STAGE_FAILED'; END IF;
 req:=current_setting('c10.gov002_dyn5_request_id',true)::bigint;
 PERFORM c10_demo.decide_approval(req,'approve','dyn5_s2_20261112');
END $test$;
SELECT set_config('request.jwt.claim.sub','88888888-8888-4888-8888-888888888888',true);
DO $test$
DECLARE req bigint;
BEGIN
 req:=current_setting('c10.gov002_dyn5_request_id',true)::bigint;
 IF c10_demo.decide_approval(req,'approve','dyn5_s3_20261112') IS NULL
 THEN RAISE EXCEPTION 'DYNAMIC_5_THIRD_STAGE_MISSING'; END IF;
END $test$;
SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',true);
DO $test$
DECLARE req bigint;
BEGIN
 req:=current_setting('c10.gov002_dyn5_request_id',true)::bigint;
 BEGIN
  PERFORM c10_demo.decide_approval(req,'approve','dyn5_repeat_20261112');
  RAISE EXCEPTION 'DYNAMIC_REPEAT_CHECKER_ACCEPTED';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'approval_repeated_checker' THEN RAISE; END IF; END;
END $test$;
SELECT set_config('request.jwt.claim.sub','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',true);
DO $test$
DECLARE req bigint;
BEGIN
 req:=current_setting('c10.gov002_dyn5_request_id',true)::bigint;
 PERFORM c10_demo.decide_approval(req,'approve','dyn5_s4_20261112');
 IF (SELECT display_status FROM c10_demo.approval_status_report_v1 WHERE request_id=req)<>'awaiting_stage_5'
 THEN RAISE EXCEPTION 'DYNAMIC_5_STAGE5_NOT_VISIBLE'; END IF;
END $test$;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
DO $test$
DECLARE req bigint;
BEGIN
 req:=current_setting('c10.gov002_dyn3_request_id',true)::bigint;
 PERFORM c10_demo.decide_approval(req,'approve','dyn3_s3_20261112');
 IF (SELECT status FROM c10_demo.approval_requests WHERE id=req)<>'approved' THEN
 RAISE EXCEPTION 'DYNAMIC_3_FINAL_MISSING'; END IF;
 req:=current_setting('c10.gov002_dyn5_request_id',true)::bigint;
 PERFORM c10_demo.decide_approval(req,'approve','dyn5_s5_20261112');
 IF (SELECT status FROM c10_demo.approval_requests WHERE id=req)<>'approved'
 OR (SELECT count(*) FROM c10_demo.approval_stage_receipts_v1 WHERE request_id=req)<>5
 THEN RAISE EXCEPTION 'DYNAMIC_5_FINAL_OR_RECEIPTS_MISSING'; END IF;
END $test$;
ROLLBACK;
DO $$BEGIN RAISE NOTICE 'PASS GOV002 3-stage and 5-stage routed approvals, replay, maker/role/actor separation, immutable policy and scoped progress';END$$;