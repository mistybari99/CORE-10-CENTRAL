\set ON_ERROR_STOP on
BEGIN;
INSERT INTO c10_demo.business_members(tenant_id,business_id,user_id,role,active)
 VALUES (1,101,'99999999-9999-4999-8999-999999999999','manager',true)
 ON CONFLICT DO NOTHING;
UPDATE c10_demo.business_members SET active=true,role='manager'
 WHERE business_id=101 AND user_id='99999999-9999-4999-8999-999999999999';
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',true);
DO $t$
DECLARE pol bigint;
BEGIN
 pol:=c10_demo.publish_approval_policy_v1(101,'demo_reviewer','current_task_review',60,'rev_task_policy_20261112');
 PERFORM c10_demo.configure_approval_route_dynamic_v2(
  pol,ARRAY['business_owner','manager','tenant_owner'],'rev_task_route_20261112');
END $t$;
SELECT set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',true);
SELECT c10_demo.submit_typed_approval_v1(
 101,'demo_reviewer','current_task_review','task-source-42',1,'{}'::jsonb,'rev_task_submit_20261112');
SELECT set_config('c10.gov002_rev_task_id',
 (SELECT id::text FROM c10_demo.approval_requests WHERE submit_key_v1='rev_task_submit_20261112'),true);
DO $t$
DECLARE task bigint:=current_setting('c10.gov002_rev_task_id',true)::bigint;
BEGIN
 IF EXISTS(SELECT 1 FROM c10_demo.my_routed_review_tasks_v2(101) WHERE request_id=task)
 THEN RAISE EXCEPTION 'REVIEWER_MAKER_CAN_SEE_OWN_TASK'; END IF;
END $t$;
SELECT set_config('request.jwt.claim.sub','99999999-9999-4999-8999-999999999999',true);
DO $t$
DECLARE task bigint:=current_setting('c10.gov002_rev_task_id',true)::bigint;
BEGIN
 IF EXISTS(SELECT 1 FROM c10_demo.my_routed_review_tasks_v2(101) WHERE request_id=task)
 THEN RAISE EXCEPTION 'REVIEWER_MANAGER_PREMATURE_VISIBILITY'; END IF;
END $t$;
SELECT set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',true);
DO $t$
DECLARE task bigint:=current_setting('c10.gov002_rev_task_id',true)::bigint;
BEGIN
 IF EXISTS(SELECT 1 FROM c10_demo.my_routed_review_tasks_v2(101) WHERE request_id=task)
 THEN RAISE EXCEPTION 'REVIEWER_SITE_STAFF_LEAK'; END IF;
END $t$;
SELECT set_config('request.jwt.claim.sub','77777777-7777-4777-8777-777777777777',true);
DO $t$
BEGIN
 BEGIN
  PERFORM c10_demo.my_routed_review_tasks_v2(101);
  RAISE EXCEPTION 'REVIEWER_FOREIGN_TENANT_ENUMERATED';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'reviewer_task_access_denied' THEN RAISE; END IF; END;
END $t$;
SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',true);
DO $t$
DECLARE task bigint:=current_setting('c10.gov002_rev_task_id',true)::bigint;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM c10_demo.my_routed_review_tasks_v2(101)
  WHERE request_id=task AND stage_no=1 AND stage_total=3 AND source_key='task-source-42')
 THEN RAISE EXCEPTION 'REVIEWER_OWNER_STAGE_1_MISSING'; END IF;
 PERFORM c10_demo.decide_approval(task,'approve','rev_task_stage1_20261112');
 IF EXISTS(SELECT 1 FROM c10_demo.my_routed_review_tasks_v2(101) WHERE request_id=task)
 THEN RAISE EXCEPTION 'REVIEWER_OWNER_STILL_SEES_FINISHED_STAGE'; END IF;
END $t$;
SELECT set_config('request.jwt.claim.sub','99999999-9999-4999-8999-999999999999',true);
DO $t$
DECLARE task bigint:=current_setting('c10.gov002_rev_task_id',true)::bigint;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM c10_demo.my_routed_review_tasks_v2(101)
  WHERE request_id=task AND stage_no=2 AND stage_total=3)
 THEN RAISE EXCEPTION 'REVIEWER_MANAGER_STAGE2_MISSING'; END IF;
END $t$;
RESET ROLE;
UPDATE c10_demo.business_members SET active=false
 WHERE business_id=101 AND user_id='99999999-9999-4999-8999-999999999999';
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','99999999-9999-4999-8999-999999999999',true);
DO $t$
DECLARE task bigint:=current_setting('c10.gov002_rev_task_id',true)::bigint;
BEGIN
 BEGIN
  PERFORM c10_demo.my_routed_review_tasks_v2(101);
  RAISE EXCEPTION 'REVIEWER_REVOKED_MEMBER_RETAINED_ACCESS';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'reviewer_task_access_denied' THEN RAISE; END IF; END;
END $t$;
RESET ROLE;
UPDATE c10_demo.business_members SET active=true
 WHERE business_id=101 AND user_id='99999999-9999-4999-8999-999999999999';
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','99999999-9999-4999-8999-999999999999',true);
DO $t$
DECLARE task bigint:=current_setting('c10.gov002_rev_task_id',true)::bigint;
BEGIN
 PERFORM c10_demo.decide_approval(task,'approve','rev_task_stage2_20261112');
 IF EXISTS(SELECT 1 FROM c10_demo.my_routed_review_tasks_v2(101) WHERE request_id=task)
 THEN RAISE EXCEPTION 'REVIEWER_MANAGER_STILL_SEES_FINISHED_STAGE'; END IF;
END $t$;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
DO $t$
DECLARE task bigint:=current_setting('c10.gov002_rev_task_id',true)::bigint;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM c10_demo.my_routed_review_tasks_v2(101)
  WHERE request_id=task AND stage_no=3 AND stage_total=3)
 THEN RAISE EXCEPTION 'REVIEWER_TENANT_OWNER_STAGE3_MISSING'; END IF;
 PERFORM c10_demo.decide_approval(task,'approve','rev_task_stage3_20261112');
 IF EXISTS(SELECT 1 FROM c10_demo.my_routed_review_tasks_v2(101) WHERE request_id=task)
 THEN RAISE EXCEPTION 'REVIEWER_COMPLETED_STILL_VISIBLE'; END IF;
END $t$;
ROLLBACK;
DO $$BEGIN RAISE NOTICE 'PASS stage-limited reviewer RPC visibility, maker denial, site/foreign/revoked privacy and canonical completion';END$$;