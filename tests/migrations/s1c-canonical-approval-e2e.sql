-- S1-c: GOV-002 typed non-posting approvals + GOV-003 canonical audit port.
-- All identities, businesses and transactions are synthetic; no live Supabase.
\set ON_ERROR_STOP on
BEGIN;
INSERT INTO core10.tenants(id,slug) VALUES (801,'s1c-demo-a'),(802,'s1c-demo-b');
INSERT INTO core10.legal_entities(id,tenant_id,label)
 VALUES (8001,801,'Demo A'),(8002,802,'Demo B');
INSERT INTO core10.businesses(id,tenant_id,legal_entity_id,slug,template_code,request_key)
 VALUES (8101,801,8001,'s1c-a','sweets_bakery','seed-s1c-a'),
        (8201,802,8002,'s1c-b','restaurant','seed-s1c-b');
INSERT INTO core10.tenant_members(tenant_id,user_id,role)
 VALUES (801,'81111111-1111-4111-8111-111111111111','tenant_owner'),
        (802,'83333333-3333-4333-8333-333333333333','tenant_owner');
INSERT INTO core10.business_members(tenant_id,business_id,user_id,role)
 VALUES (801,8101,'82222222-2222-4222-8222-222222222222','manager');
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims',
 '{"sub":"81111111-1111-4111-8111-111111111111"}',true);
SELECT set_config('request.jwt.claim.sub','81111111-1111-4111-8111-111111111111',true);
DO $test$
DECLARE v_policy bigint;v_event bigint;
BEGIN
 IF NOT core10.can_tenant(801) THEN RAISE EXCEPTION 'S1C_OWNER_SCOPE'; END IF;
 v_policy:=core10.publish_approval_policy_v1(8101,'inventory','adjust',60,'s1c_policy_0001');
 IF v_policy<>core10.publish_approval_policy_v1(8101,'inventory','adjust',60,'s1c_policy_0001')
 THEN RAISE EXCEPTION 'S1C_POLICY_REPLAY'; END IF;
 PERFORM set_config('core10.s1c_policy_id',v_policy::text,true);
 v_event:=core10.change_access_v1(
   8101,'84444444-4444-4444-8444-444444444444','business_member.grant',
   'manager',NULL,ARRAY[]::text[],'s1c_access_0001');
 IF v_event IS NULL THEN RAISE EXCEPTION 'S1C_ACCESS_EVENT_NULL'; END IF;
 IF (SELECT count(*) FROM core10.canonical_audit_events_v1
     WHERE business_id=8101 AND source_domain='access')<>1
 THEN RAISE EXCEPTION 'S1C_ACCESS_AUDIT_NOT_CANONICAL'; END IF;
END $test$;

SELECT set_config('request.jwt.claims',
 '{"sub":"82222222-2222-4222-8222-222222222222","app_metadata":{"role":"tenant_owner"}}',true);
SELECT set_config('request.jwt.claim.sub','82222222-2222-4222-8222-222222222222',true);
DO $test$
DECLARE v_request bigint;
BEGIN
 IF core10.can_manage(801,8101) THEN RAISE EXCEPTION 'S1C_FORGED_ROLE_ESCALATION'; END IF;
 v_request:=core10.submit_typed_approval_v1(
   8101,'inventory','adjust','stocktest-1',1,'{"quantity_milli":"3000"}'::jsonb,'s1c_submit_0001');
 IF v_request<>core10.submit_typed_approval_v1(
   8101,'inventory','adjust','stocktest-1',1,'{"quantity_milli":"3000"}'::jsonb,'s1c_submit_0001')
 THEN RAISE EXCEPTION 'S1C_SUBMIT_REPLAY'; END IF;
 PERFORM set_config('core10.s1c_request_id',v_request::text,true);
 BEGIN
  PERFORM core10.decide_approval(v_request,'approve','s1c_maker_approve_01');
  RAISE EXCEPTION 'S1C_MAKER_APPROVED';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'approval_not_authorized' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM core10.submit_typed_approval_v1(
   8101,'inventory','adjust','stocktest-1',1,'{"quantity_milli":"4000"}'::jsonb,'s1c_submit_0001');
  RAISE EXCEPTION 'S1C_PAYLOAD_REPLAY_ACCEPTED';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'approval_submit_replay_conflict' THEN RAISE; END IF;
 END;
 IF (SELECT count(*) FROM core10.canonical_audit_events_v1 WHERE business_id=8101)<>0
 THEN RAISE EXCEPTION 'S1C_MANAGER_AUDIT_READ_LEAK'; END IF;
END $test$;

SELECT set_config('request.jwt.claims',
 '{"sub":"83333333-3333-4333-8333-333333333333"}',true);
SELECT set_config('request.jwt.claim.sub','83333333-3333-4333-8333-333333333333',true);
DO $test$
DECLARE v_request bigint:=current_setting('core10.s1c_request_id')::bigint;
BEGIN
 IF (SELECT count(*) FROM core10.approval_requests WHERE id=v_request)<>0
 THEN RAISE EXCEPTION 'S1C_CROSS_TENANT_REQUEST_LEAK'; END IF;
 BEGIN
  PERFORM core10.decide_approval(v_request,'approve','s1c_foreign_approve_01');
  RAISE EXCEPTION 'S1C_CROSS_TENANT_APPROVED';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'approval_not_authorized' THEN RAISE; END IF;
 END;
END $test$;

SELECT set_config('request.jwt.claims',
 '{"sub":"81111111-1111-4111-8111-111111111111"}',true);
SELECT set_config('request.jwt.claim.sub','81111111-1111-4111-8111-111111111111',true);
DO $test$
DECLARE v_req bigint:=current_setting('core10.s1c_request_id')::bigint;
 v_receipt bigint;v_check jsonb;
BEGIN
 v_receipt:=core10.decide_approval(v_req,'approve','s1c_owner_vote_01');
 IF v_receipt<>core10.decide_approval(v_req,'approve','s1c_owner_vote_01')
 THEN RAISE EXCEPTION 'S1C_DECISION_NOT_IDEMPOTENT'; END IF;
 IF (SELECT status FROM core10.approval_requests WHERE id=v_req)<>'approved'
 THEN RAISE EXCEPTION 'S1C_APPROVAL_STATUS'; END IF;
 IF (SELECT count(*) FROM core10.canonical_audit_events_v1
     WHERE business_id=8101 AND source_domain='approval')<>1
 THEN RAISE EXCEPTION 'S1C_APPROVAL_AUDIT_NOT_CANONICAL'; END IF;
 v_check:=core10.verify_canonical_audit_v1(8101);
 IF v_check->>'ok'<>'true' OR (v_check->>'checked')::int<>2
 THEN RAISE EXCEPTION 'S1C_AUDIT_VERIFY %',v_check; END IF;
 IF has_function_privilege('authenticated',
 'core10.verify_approval_binding_v1(bigint,bigint,text,text,text,bigint,jsonb)','EXECUTE')
 THEN RAISE EXCEPTION 'S1C_UNCERTIFIED_POSTING_HANDLER_EXPOSED'; END IF;
 BEGIN
  UPDATE core10.canonical_audit_events_v1 SET action='tamper'
   WHERE business_id=8101;
  RAISE EXCEPTION 'S1C_AUDIT_MUTATION_PERMITTED';
 EXCEPTION WHEN OTHERS THEN
  IF SQLSTATE<>'42501' THEN RAISE; END IF;
 END;
 BEGIN
  INSERT INTO core10.approval_events(request_id,tenant_id,business_id,actor_id,action,idempotency_key)
   VALUES(v_req,801,8101,'81111111-1111-4111-8111-111111111111','approve','bad-direct');
  RAISE EXCEPTION 'S1C_DIRECT_EVENT_INSERT_PERMITTED';
 EXCEPTION WHEN OTHERS THEN
  IF SQLSTATE<>'42501' THEN RAISE; END IF;
 END;
 IF (SELECT count(*) FROM core10.stock_movements)<>0
 THEN RAISE EXCEPTION 'S1C_APPROVAL_POSTED_STOCK'; END IF;
 RAISE NOTICE 'PASS S1C: canonical access+approval audit, typed review, owner/maker/foreign roles, replay, immutable writes, no posting';
END $test$;
RESET ROLE;
ROLLBACK;
