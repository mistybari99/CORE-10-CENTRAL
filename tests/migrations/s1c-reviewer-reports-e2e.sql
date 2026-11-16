-- Synthetic signed-claim SQL harness: canonical GOV-002 scoped report and
-- linked canonical audit. No separate c10_demo, no live data.
\set ON_ERROR_STOP on
BEGIN;
INSERT INTO core10.tenants(id,slug) VALUES (1301,'np01-report-tenant-a'),(1302,'np01-report-tenant-b');
INSERT INTO core10.legal_entities(id,tenant_id,label)
 VALUES (13001,1301,'report A'),(13002,1302,'report B');
INSERT INTO core10.businesses(id,tenant_id,legal_entity_id,slug,template_code,request_key)
 VALUES (13101,1301,13001,'review-a','sweets_bakery','report-biz-a'),
        (13201,1302,13002,'review-b','restaurant','report-biz-b');
INSERT INTO core10.tenant_members(tenant_id,user_id,role) VALUES
 (1301,'a1111111-1111-4111-8111-111111111111','tenant_owner'),
 (1302,'b1111111-1111-4111-8111-111111111111','tenant_owner');
INSERT INTO core10.business_members(tenant_id,business_id,user_id,role) VALUES
 (1301,13101,'a2222222-2222-4222-8222-222222222222','business_owner'),
 (1301,13101,'a3333333-3333-4333-8333-333333333333','manager'),
 (1301,13101,'a4444444-4444-4444-8444-444444444444','manager');
UPDATE core10.business_members
 SET approval_actions=ARRAY['approval.decide','approval.export']
 WHERE user_id='a4444444-4444-4444-8444-444444444444' AND business_id=13101;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims','{"sub":"a1111111-1111-4111-8111-111111111111"}',true);
SELECT set_config('request.jwt.claim.sub','a1111111-1111-4111-8111-111111111111',true);
DO $t$
DECLARE p bigint;
BEGIN
 p:=core10.publish_approval_policy_v1(13101,'inventory','adjust',60,'report-policy-one');
 PERFORM core10.configure_approval_route_v1(p,ARRAY['business_owner','manager','tenant_owner'],'report-route-one');
 p:=core10.publish_approval_policy_v1(13101,'inventory','count',60,'report-policy-two');
 PERFORM core10.configure_approval_route_v1(p,ARRAY['business_owner','tenant_owner'],'report-route-two');
END $t$;

-- Maker sees own requests but no other request; not a reviewer despite forged role metadata.
SELECT set_config('request.jwt.claims',
 '{"sub":"a3333333-3333-4333-8333-333333333333","app_metadata":{"role":"tenant_owner","is_owner":true}}',true);
SELECT set_config('request.jwt.claim.sub','a3333333-3333-4333-8333-333333333333',true);
DO $t$
DECLARE q1 bigint;q2 bigint;
BEGIN
 q1:=core10.submit_typed_approval_v1(13101,'inventory','adjust','a-stock-1',1,
 '{"quantity_milli":"5000"}'::jsonb,'report-submit-one');
 q2:=core10.submit_typed_approval_v1(13101,'inventory','count','a-stock-2',1,
 '{"quantity_milli":"7000"}'::jsonb,'report-submit-two');
 PERFORM set_config('core10.report_q1',q1::text,true);
 PERFORM set_config('core10.report_q2',q2::text,true);
 IF (SELECT count(*) FROM core10.my_approval_status_v1(13101,100))<>2 THEN
  RAISE EXCEPTION 'REPORT_MAKER_OWN_STATUS_MISSING'; END IF;
 IF (SELECT count(*) FROM core10.my_approval_status_v1(13101,100)
   WHERE can_review_now)<>0 THEN RAISE EXCEPTION 'REPORT_MAKER_REVIEW_PROMOTION'; END IF;
 BEGIN
  PERFORM core10.my_approval_status_v1(13101,101);
  RAISE EXCEPTION 'REPORT_OUT_OF_BOUND_LIMIT_ALLOWED';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'approval_report_denied' THEN RAISE; END IF;
 END;
 IF (SELECT count(*) FROM core10.my_approval_activity_v1(13101,10))<>0 THEN
  RAISE EXCEPTION 'REPORT_PREMATURE_ACTIVITY'; END IF;
END $t$;

-- Business owner sees current stage 1 and audits are canonical only.
SELECT set_config('request.jwt.claims','{"sub":"a2222222-2222-4222-8222-222222222222"}',true);
SELECT set_config('request.jwt.claim.sub','a2222222-2222-4222-8222-222222222222',true);
DO $t$
DECLARE q1 bigint:=current_setting('core10.report_q1')::bigint;
BEGIN
 IF (SELECT count(*) FROM core10.my_approval_status_v1(13101,100)
   WHERE can_review_now AND required_checks=3 AND completed_checks=0)<>1 THEN
  RAISE EXCEPTION 'REPORT_REVIEW_STAGE_SCOPE'; END IF;
 PERFORM core10.decide_approval(q1,'approve','report-owner-vote-one');
 IF (SELECT count(*) FROM core10.my_approval_activity_v1(13101,100) a
  WHERE a.request_id=q1 AND a.action='approve' AND a.stage_no=1 AND a.audit_event_id>0)<>1
 THEN RAISE EXCEPTION 'REPORT_ACTIVITY_MISSING_AUDIT_PROOF'; END IF;
 IF (SELECT count(*) FROM core10.my_approval_status_v1(13101,100)
  WHERE request_id=q1 AND display_status='awaiting_stage_2'
     AND completed_checks=1 AND can_review_now=false)<>1
 THEN RAISE EXCEPTION 'REPORT_INTERMEDIATE_FINALITY'; END IF;
END $t$;

-- Granted stage-two reviewer sees only current request's status and linked
-- activity, not the other pending request (stage one for business owner).
SELECT set_config('request.jwt.claims','{"sub":"a4444444-4444-4444-8444-444444444444"}',true);
SELECT set_config('request.jwt.claim.sub','a4444444-4444-4444-8444-444444444444',true);
DO $t$
DECLARE q1 bigint:=current_setting('core10.report_q1')::bigint;
BEGIN
 IF (SELECT count(*) FROM core10.my_approval_status_v1(13101,100))<>1 OR
    (SELECT count(*) FROM core10.my_approval_status_v1(13101,100)
     WHERE request_id=q1 AND can_review_now AND completed_checks=1)<>1
 THEN RAISE EXCEPTION 'REPORT_REVIEWER_STAGE_FILTER'; END IF;
 IF (SELECT count(*) FROM core10.my_approval_activity_v1(13101,100))<>1
 THEN RAISE EXCEPTION 'REPORT_REVIEWER_ACTIVITY_FILTER'; END IF;
 PERFORM core10.decide_approval(q1,'approve','report-manager-vote-two');
END $t$;

-- Foreign tenant cannot see or fetch scoped projections, despite fake metadata.
SELECT set_config('request.jwt.claims',
 '{"sub":"b1111111-1111-4111-8111-111111111111","app_metadata":{"is_owner":true}}',true);
SELECT set_config('request.jwt.claim.sub','b1111111-1111-4111-8111-111111111111',true);
DO $t$
BEGIN
 FOR i IN 1..2 LOOP
  BEGIN
   IF i=1 THEN PERFORM core10.my_approval_status_v1(13101,100);
          ELSE PERFORM core10.my_approval_activity_v1(13101,100); END IF;
   RAISE EXCEPTION 'REPORT_FOREIGN_READ_PERMITTED';
  EXCEPTION WHEN OTHERS THEN
   IF SQLERRM<>'approval_report_denied' THEN RAISE; END IF;
  END;
 END LOOP;
END $t$;

-- Tenant owner returns and finalizes review; canonical audit verifies sequence.
SELECT set_config('request.jwt.claims','{"sub":"a1111111-1111-4111-8111-111111111111"}',true);
SELECT set_config('request.jwt.claim.sub','a1111111-1111-4111-8111-111111111111',true);
DO $t$
DECLARE q1 bigint:=current_setting('core10.report_q1')::bigint;
 v jsonb;
BEGIN
 PERFORM core10.decide_approval(q1,'approve','report-tenant-final-vote');
 IF (SELECT stored_status FROM core10.my_approval_status_v1(13101,100)
   WHERE request_id=q1)<>'approved' THEN RAISE EXCEPTION 'REPORT_NOT_FINAL'; END IF;
 IF (SELECT count(*) FROM core10.my_approval_activity_v1(13101,100) a
  WHERE a.request_id=q1 AND a.audit_event_id>0)<>3
 THEN RAISE EXCEPTION 'REPORT_AUDIT_ACTIVITY_COUNT'; END IF;
 v:=core10.verify_canonical_audit_v1(13101);
 IF v->>'ok'<>'true' OR (v->>'checked')::int<5
 THEN RAISE EXCEPTION 'REPORT_CANONICAL_HASH_DRIFT %',v; END IF;
END $t$;

-- Maker can still inspect own completed activity but never post money/stock.
SELECT set_config('request.jwt.claims','{"sub":"a3333333-3333-4333-8333-333333333333"}',true);
SELECT set_config('request.jwt.claim.sub','a3333333-3333-4333-8333-333333333333',true);
DO $t$
BEGIN
 IF (SELECT count(*) FROM core10.my_approval_activity_v1(13101,100))<>3
 THEN RAISE EXCEPTION 'REPORT_MAKER_AUDIT_NOT_VISIBLE'; END IF;
 IF (SELECT count(*) FROM core10.canonical_audit_events_v1 WHERE business_id=13101)<>0
 THEN RAISE EXCEPTION 'REPORT_DIRECT_AUDIT_RLS_BYPASS'; END IF;
END $t$;
RESET ROLE;
DO $t$
BEGIN
 IF (SELECT count(*) FROM core10.stock_movements)<>0
 THEN RAISE EXCEPTION 'REPORT_CAUSED_STOCK_POSTING'; END IF;
 RAISE NOTICE 'PASS GOV002 canonical scoped status/activity RPC, live-stage reviewer, foreign denial, audit linkage, zero posting';
END $t$;
ROLLBACK;
