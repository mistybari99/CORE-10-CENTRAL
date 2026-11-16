-- S1-c GOV002 2/3/5-stage, delegated checker, revoked delegation,
-- maker withdrawal, actual DB membership, scoped reviewer tasks and negative RLS.
-- Entirely synthetic disposable PG17, inside ROLLBACK.
\set ON_ERROR_STOP on
BEGIN;
INSERT INTO core10.tenants(id,slug) VALUES (901,'route-fixture-a'),(902,'route-fixture-b');
INSERT INTO core10.legal_entities(id,tenant_id,label)
 VALUES (9001,901,'Route A'),(9002,902,'Route B');
INSERT INTO core10.businesses(id,tenant_id,legal_entity_id,slug,template_code,request_key)
 VALUES (9101,901,9001,'route-a','sweets_bakery','route-business-a-01'),
        (9201,902,9002,'route-b','restaurant','route-business-b-01');
INSERT INTO core10.tenant_members(tenant_id,user_id,role) VALUES
 (901,'91111111-1111-4111-8111-111111111111','tenant_owner'),
 (902,'97777777-7777-4777-8777-777777777777','tenant_owner');
INSERT INTO core10.business_members(tenant_id,business_id,user_id,role) VALUES
 (901,9101,'92222222-2222-4222-8222-222222222222','business_owner'),
 (901,9101,'93333333-3333-4333-8333-333333333333','manager'),
 (901,9101,'94444444-4444-4444-8444-444444444444','manager'),
 (901,9101,'95555555-5555-4555-8555-555555555555','manager'),
 (901,9101,'96666666-6666-4666-8666-666666666666','manager');
-- Build02A canonical permission grants: 3 reviewing managers have explicit decide.
UPDATE core10.business_members SET approval_actions=ARRAY['approval.decide']
 WHERE tenant_id=901 AND business_id=9101 AND user_id IN (
 '94444444-4444-4444-8444-444444444444',
 '95555555-5555-4555-8555-555555555555',
 '96666666-6666-4666-8666-666666666666'
 );
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims','{"sub":"91111111-1111-4111-8111-111111111111"}',true);
SELECT set_config('request.jwt.claim.sub','91111111-1111-4111-8111-111111111111',true);
DO $t$
DECLARE p5 bigint;p3 bigint;p2 bigint;
BEGIN
 p5:=core10.publish_approval_policy_v1(9101,'inventory','adjust',120,'route-policy-five');
 p3:=core10.publish_approval_policy_v1(9101,'inventory','transfer',120,'route-policy-three');
 p2:=core10.publish_approval_policy_v1(9101,'inventory','count',120,'route-policy-two');
 PERFORM core10.configure_approval_route_v1(p5,
  ARRAY['business_owner','manager','manager','manager','tenant_owner'],'route-five-stages');
 PERFORM core10.configure_approval_route_v1(p3,
  ARRAY['business_owner','manager','tenant_owner'],'route-three-stage');
 PERFORM core10.configure_approval_route_v1(p2,
  ARRAY['business_owner','tenant_owner'],'route-two-stage');
 IF (SELECT cardinality(stages) FROM core10.approval_routes_v1 WHERE policy_id=p5)<>5
 THEN RAISE EXCEPTION 'S1C_FIVE_STAGE_NOT_INSTALLED'; END IF;
 IF core10.configure_approval_route_v1(p5,
  ARRAY['business_owner','manager','manager','manager','tenant_owner'],'route-five-stages')<>p5
 THEN RAISE EXCEPTION 'S1C_ROUTE_IDEMPOTENCY'; END IF;
 PERFORM set_config('core10.route_p3',p3::text,true);
END $t$;

-- Manager/maker: no custom/forged JWT role can approve own request.
SELECT set_config('request.jwt.claims',
 '{"sub":"93333333-3333-4333-8333-333333333333","app_metadata":{"is_owner":true,"role":"tenant_owner"}}',true);
SELECT set_config('request.jwt.claim.sub','93333333-3333-4333-8333-333333333333',true);
DO $t$
DECLARE q5 bigint;q3 bigint;q2 bigint;qr bigint;
BEGIN
 q5:=core10.submit_typed_approval_v1(9101,'inventory','adjust',
  'five-stage-stock-01',1,'{"quantity_milli":"4000"}'::jsonb,'route-request-five');
 q3:=core10.submit_typed_approval_v1(9101,'inventory','transfer',
  'three-stage-stock-02',1,'{"quantity_milli":"5000"}'::jsonb,'route-request-three');
 q2:=core10.submit_typed_approval_v1(9101,'inventory','count',
  'two-stage-stock-03',1,'{"quantity_milli":"6000"}'::jsonb,'route-request-two');
 qr:=core10.submit_typed_approval_v1(9101,'inventory','transfer',
  'revoke-stage-stock-04',1,'{"quantity_milli":"7000"}'::jsonb,'route-request-revoke');
 PERFORM set_config('core10.route_q5',q5::text,true);
 PERFORM set_config('core10.route_q3',q3::text,true);
 PERFORM set_config('core10.route_q2',q2::text,true);
 PERFORM set_config('core10.route_qr',qr::text,true);
 BEGIN
  PERFORM core10.decide_approval(q5,'approve','route-self-approve');
  RAISE EXCEPTION 'S1C_MAKER_APPROVED';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'approval_not_authorized' THEN RAISE; END IF;
 END;
 IF (SELECT count(*) FROM core10.my_routed_review_tasks_v1(9101))<>0
 THEN RAISE EXCEPTION 'S1C_MAKER_TASK_LEAK'; END IF;
END $t$;

-- Business owner: approve stage 1 on 5-step route and delegate a different
-- stage-one review to one bounded manager; preserve maker/checker separation.
SELECT set_config('request.jwt.claims','{"sub":"92222222-2222-4222-8222-222222222222"}',true);
SELECT set_config('request.jwt.claim.sub','92222222-2222-4222-8222-222222222222',true);
DO $t$
DECLARE q5 bigint:=current_setting('core10.route_q5')::bigint;
 q3 bigint:=current_setting('core10.route_q3')::bigint;
 qr bigint:=current_setting('core10.route_qr')::bigint;
 event_id bigint;
BEGIN
 IF (SELECT count(*) FROM core10.my_routed_review_tasks_v1(9101))<>4
 THEN RAISE EXCEPTION 'S1C_OWNER_STAGE_TASK_COUNT'; END IF;
 event_id:=core10.decide_approval(q5,'approve','route-vote-stage-01');
 IF core10.decide_approval(q5,'approve','route-vote-stage-01')<>event_id
 THEN RAISE EXCEPTION 'S1C_STAGE_REPLAY_CHANGED'; END IF;
 IF (SELECT status FROM core10.approval_requests WHERE id=q5)<>'pending'
 THEN RAISE EXCEPTION 'S1C_STAGE1_PREMATURE_APPROVAL'; END IF;
 PERFORM core10.delegate_approval_stage_v1(q3,
  '95555555-5555-4555-8555-555555555555',60,'route-delegate-three');
 PERFORM core10.delegate_approval_stage_v1(qr,
  '96666666-6666-4666-8666-666666666666',60,'route-delegate-revoke');
 PERFORM core10.revoke_approval_delegation_v1(qr,'route-revoke-original');
 IF (SELECT revoked_at FROM core10.approval_delegations_v1 WHERE request_id=qr) IS NULL
 THEN RAISE EXCEPTION 'S1C_DELEGATE_REVOCATION_MISSING'; END IF;
END $t$;

-- Explicit manager reviewer: 5-step stage 2.
SELECT set_config('request.jwt.claims','{"sub":"94444444-4444-4444-8444-444444444444"}',true);
SELECT set_config('request.jwt.claim.sub','94444444-4444-4444-8444-444444444444',true);
DO $t$
DECLARE q5 bigint:=current_setting('core10.route_q5')::bigint;
 q3 bigint:=current_setting('core10.route_q3')::bigint;
BEGIN
 IF (SELECT count(*) FROM core10.my_routed_review_tasks_v1(9101)
  WHERE request_id=q5 AND stage_no=2)<>1
 THEN RAISE EXCEPTION 'S1C_STAGE2_TASK_MISSING'; END IF;
 IF (SELECT count(*) FROM core10.my_routed_review_tasks_v1(9101)
  WHERE request_id=q3)<>0 THEN RAISE EXCEPTION 'S1C_EARLY_TASK_LEAK'; END IF;
 PERFORM core10.decide_approval(q5,'approve','route-vote-stage-02');
END $t$;

-- Delegated manager f gets precisely q3 stage 1, and is stage3 for q5.
SELECT set_config('request.jwt.claims','{"sub":"95555555-5555-4555-8555-555555555555"}',true);
SELECT set_config('request.jwt.claim.sub','95555555-5555-4555-8555-555555555555',true);
DO $t$
DECLARE q5 bigint:=current_setting('core10.route_q5')::bigint;
 q3 bigint:=current_setting('core10.route_q3')::bigint;
BEGIN
 IF (SELECT count(*) FROM core10.my_routed_review_tasks_v1(9101)
  WHERE request_id=q3 AND stage_no=1)<>1
 THEN RAISE EXCEPTION 'S1C_DELEGATED_TASK_MISSING'; END IF;
 PERFORM core10.decide_approval(q3,'approve','route-vote-delegate-01');
 PERFORM core10.decide_approval(q5,'approve','route-vote-stage-03');
 IF (SELECT delegated_by FROM core10.approval_stage_receipts_v1
   WHERE request_id=q3 AND stage_no=1)<>'92222222-2222-4222-8222-222222222222'::uuid
 THEN RAISE EXCEPTION 'S1C_DELEGATE_RECEIPT_MISSING'; END IF;
END $t$;

-- Manager d now may review delegated request's stage 2.
SELECT set_config('request.jwt.claims','{"sub":"94444444-4444-4444-8444-444444444444"}',true);
SELECT set_config('request.jwt.claim.sub','94444444-4444-4444-8444-444444444444',true);
DO $t$
DECLARE q3 bigint:=current_setting('core10.route_q3')::bigint;
BEGIN
 IF (SELECT count(*) FROM core10.my_routed_review_tasks_v1(9101)
 WHERE request_id=q3 AND stage_no=2)<>1
 THEN RAISE EXCEPTION 'S1C_ROUTE_THREE_STAGE2_MISSING'; END IF;
 PERFORM core10.decide_approval(q3,'approve','route-vote-three-02');
END $t$;

-- Revoked delegate g cannot review qr stage one, but legitimately owns q5 stage 4.
SELECT set_config('request.jwt.claims','{"sub":"96666666-6666-4666-8666-666666666666"}',true);
SELECT set_config('request.jwt.claim.sub','96666666-6666-4666-8666-666666666666',true);
DO $t$
DECLARE qr bigint:=current_setting('core10.route_qr')::bigint;
 q5 bigint:=current_setting('core10.route_q5')::bigint;
BEGIN
 IF (SELECT count(*) FROM core10.my_routed_review_tasks_v1(9101)
 WHERE request_id=qr)<>0 THEN RAISE EXCEPTION 'S1C_REVOKED_DELEGATE_TASK'; END IF;
 BEGIN
  PERFORM core10.decide_approval(qr,'approve','route-revoked-delegate-vote');
  RAISE EXCEPTION 'S1C_REVOKED_DELEGATE_APPROVED';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'approval_not_authorized' THEN RAISE; END IF;
 END;
 IF (SELECT count(*) FROM core10.my_routed_review_tasks_v1(9101)
 WHERE request_id=q5 AND stage_no=4)<>1
 THEN RAISE EXCEPTION 'S1C_FIVE_STAGE4_TASK_MISSING'; END IF;
 PERFORM core10.decide_approval(q5,'approve','route-vote-stage-04');
END $t$;

-- Cross-tenant forged metadata cannot read or approve any request or route.
SELECT set_config('request.jwt.claims',
 '{"sub":"97777777-7777-4777-8777-777777777777","app_metadata":{"role":"tenant_owner"}}',true);
SELECT set_config('request.jwt.claim.sub','97777777-7777-4777-8777-777777777777',true);
DO $t$
BEGIN
 IF (SELECT count(*) FROM core10.approval_requests WHERE business_id=9101)<>0
  OR (SELECT count(*) FROM core10.approval_events WHERE business_id=9101)<>0
  OR (SELECT count(*) FROM core10.approval_routes_v1 WHERE business_id=9101)<>0
 THEN RAISE EXCEPTION 'S1C_FOREIGN_SCOPE_LEAK'; END IF;
 BEGIN
  PERFORM core10.my_routed_review_tasks_v1(9101);
  RAISE EXCEPTION 'S1C_FOREIGN_TASKS_PERMITTED';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'reviewer_task_access_denied' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM core10.decide_approval(current_setting('core10.route_q5')::bigint,
    'approve','route-foreign-vote');
  RAISE EXCEPTION 'S1C_FOREIGN_DECIDED';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'approval_not_authorized' THEN RAISE; END IF;
 END;
END $t$;

-- Final stage belongs to tenant owner and only then becomes approved.
SELECT set_config('request.jwt.claims','{"sub":"91111111-1111-4111-8111-111111111111"}',true);
SELECT set_config('request.jwt.claim.sub','91111111-1111-4111-8111-111111111111',true);
DO $t$
DECLARE q5 bigint:=current_setting('core10.route_q5')::bigint;
 q3 bigint:=current_setting('core10.route_q3')::bigint;
 v_check jsonb;
BEGIN
 IF (SELECT status FROM core10.approval_requests WHERE id=q5)<>'pending'
 THEN RAISE EXCEPTION 'S1C_FIVE_STAGE_EARLY_FINAL'; END IF;
 PERFORM core10.decide_approval(q5,'approve','route-vote-stage-05');
 PERFORM core10.decide_approval(q3,'approve','route-vote-three-03');
 IF (SELECT status FROM core10.approval_requests WHERE id=q5)<>'approved'
 OR (SELECT count(*) FROM core10.approval_stage_receipts_v1 WHERE request_id=q5)<>5
 OR (SELECT count(DISTINCT actor_id) FROM core10.approval_stage_receipts_v1 WHERE request_id=q5)<>5
 OR (SELECT status FROM core10.approval_requests WHERE id=q3)<>'approved'
 OR (SELECT count(*) FROM core10.approval_stage_receipts_v1 WHERE request_id=q3)<>3
 THEN RAISE EXCEPTION 'S1C_ROUTE_FINAL_COUNTS'; END IF;
 v_check:=core10.verify_canonical_audit_v1(9101);
 IF v_check->>'ok'<>'true' OR (v_check->>'checked')::int<12
 THEN RAISE EXCEPTION 'S1C_CANONICAL_AUDIT_NOT_LINKED %',v_check; END IF;
END $t$;

-- Maker withdrawal before first vote is safe; after first stage it is blocked.
SELECT set_config('request.jwt.claims','{"sub":"93333333-3333-4333-8333-333333333333"}',true);
SELECT set_config('request.jwt.claim.sub','93333333-3333-4333-8333-333333333333',true);
DO $t$
DECLARE q2 bigint:=current_setting('core10.route_q2')::bigint;
 q5 bigint:=current_setting('core10.route_q5')::bigint;
 receipt bigint;
BEGIN
 receipt:=core10.withdraw_typed_approval_v1(q2,'route-maker-withdraw-01');
 IF receipt<>core10.withdraw_typed_approval_v1(q2,'route-maker-withdraw-01')
 THEN RAISE EXCEPTION 'S1C_WITHDRAW_REPLAY'; END IF;
 IF (SELECT status FROM core10.approval_requests WHERE id=q2)<>'withdrawn'
 THEN RAISE EXCEPTION 'S1C_WITHDRAW_STATUS'; END IF;
 BEGIN
  PERFORM core10.withdraw_typed_approval_v1(q5,'route-maker-withdraw-after-vote');
  RAISE EXCEPTION 'S1C_APPROVED_REQUEST_WITHDRAWN';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'withdraw_invalid_transition' THEN RAISE; END IF;
 END;
END $t$;

-- Even after delegated grant, no domain Stock or Money ledger is touched.
RESET ROLE;
DO $t$
BEGIN
 IF (SELECT count(*) FROM core10.stock_movements)<>0
 THEN RAISE EXCEPTION 'S1C_ROUTING_POSTED_STOCK'; END IF;
 IF EXISTS(SELECT 1 FROM core10.approval_events WHERE action='approve' AND
   idempotency_key='route-foreign-vote')
 THEN RAISE EXCEPTION 'S1C_FOREIGN_EVENT'; END IF;
 RAISE NOTICE 'PASS S1C routed: 2/3/5 policy, five distinct votes, delegate+revoke, maker withdraw, scoped tasks, cross-tenant and audit, zero posting';
END $t$;
ROLLBACK;
