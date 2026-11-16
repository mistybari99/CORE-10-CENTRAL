-- B-020 / 0110, disposable PG17: submit/delegate/revoke direct Control proof.
-- 4 synthetic roles across 2 tenants. Entire fixture rolled back.
\set ON_ERROR_STOP on
BEGIN;
INSERT INTO core10.tenants(id,slug) VALUES
 (99801,'np01-0110-a'),(99802,'np01-0110-b');
INSERT INTO core10.legal_entities(id,tenant_id,label) VALUES
 (99811,99801,'NP01 B020 0110 A'),(99812,99802,'NP01 B020 0110 B');
INSERT INTO core10.businesses(id,tenant_id,legal_entity_id,slug,template_code,request_key) VALUES
 (99821,99801,99811,'b020-0110-a','sweets_bakery','np01_0110_biz_a_01'),
 (99822,99802,99812,'b020-0110-b','sweets_bakery','np01_0110_biz_b_01');
INSERT INTO core10.tenant_members(tenant_id,user_id,role) VALUES
 (99801,'99811111-1111-4111-8111-111111111111','tenant_owner'),
 (99802,'99855555-5555-4555-8555-555555555555','tenant_owner');
INSERT INTO core10.business_members(tenant_id,business_id,user_id,role) VALUES
 (99801,99821,'99822222-2222-4222-8222-222222222222','business_owner'),
 (99801,99821,'99833333-3333-4333-8333-333333333333','manager'),
 (99801,99821,'99844444-4444-4444-8444-444444444444','manager');
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims','{"sub":"99811111-1111-4111-8111-111111111111"}',true);
SELECT set_config('request.jwt.claim.sub','99811111-1111-4111-8111-111111111111',true);
DO $t$
DECLARE pol bigint;
BEGIN
 pol:=core10.publish_approval_policy_v1(99821,'inventory','adjust',120,'np01_0110_policy_01');
 PERFORM core10.configure_approval_route_v1(pol,
   ARRAY['business_owner','tenant_owner']::text[],'np01_0110_route_01');
END $t$;
-- Maker submits distinct requests, one for delegation and one for revoke.
SELECT set_config('request.jwt.claims','{"sub":"99833333-3333-4333-8333-333333333333"}',true);
SELECT set_config('request.jwt.claim.sub','99833333-3333-4333-8333-333333333333',true);
DO $t$
DECLARE q1 bigint;q2 bigint;
BEGIN
 q1:=core10.submit_typed_approval_v1(99821,'inventory','adjust','np01-0110-src1',1,
  '{"quantity":7}'::jsonb,'np01_0110_submit_01');
 q2:=core10.submit_typed_approval_v1(99821,'inventory','adjust','np01-0110-src2',1,
  '{"quantity":8}'::jsonb,'np01_0110_submit_02');
 PERFORM set_config('np01.b020_q1',q1::text,true);
 PERFORM set_config('np01.b020_q2',q2::text,true);
 IF core10.submit_typed_approval_v1(99821,'inventory','adjust','np01-0110-src1',1,
  '{"quantity":7}'::jsonb,'np01_0110_submit_01')<>q1
 THEN RAISE EXCEPTION 'NP01_0110_SUBMIT_REPLAY_CHANGED'; END IF;
END $t$;
-- Business owner legitimately delegates q2 while the Control switch is on.
SELECT set_config('request.jwt.claims','{"sub":"99822222-2222-4222-8222-222222222222"}',true);
SELECT set_config('request.jwt.claim.sub','99822222-2222-4222-8222-222222222222',true);
DO $t$
DECLARE ev bigint;
BEGIN
 ev:=core10.delegate_approval_stage_v1(current_setting('np01.b020_q2')::bigint,
   '99844444-4444-4444-8444-444444444444',30,'np01_0110_delegate_02');
 IF ev IS NULL THEN RAISE EXCEPTION 'NP01_0110_DELEGATE_MISSING'; END IF;
END $t$;
-- Disable review; all three RPCs must reject before replay or mutation.
SELECT set_config('request.jwt.claims','{"sub":"99811111-1111-4111-8111-111111111111"}',true);
SELECT set_config('request.jwt.claim.sub','99811111-1111-4111-8111-111111111111',true);
DO $t$
DECLARE c jsonb;
BEGIN
 c:=core10.control_set_v1(99821,NULL,'gov002.review',false,1::smallint,'{}',NULL,
  false,0,'Block B020 0110 review','np01_0110_disable_01');
 IF (c->>'version')::int<>1 THEN RAISE EXCEPTION 'NP01_0110_DISABLE_VERSION'; END IF;
END $t$;
SELECT set_config('request.jwt.claims','{"sub":"99833333-3333-4333-8333-333333333333"}',true);
SELECT set_config('request.jwt.claim.sub','99833333-3333-4333-8333-333333333333',true);
DO $t$
DECLARE requests_before bigint;
BEGIN
 SELECT count(*) INTO requests_before FROM core10.approval_requests WHERE business_id=99821;
 BEGIN
  PERFORM core10.submit_typed_approval_v1(99821,'inventory','adjust',
   'np01-0110-src3',1,'{"quantity":9}'::jsonb,'np01_0110_blocked_new_03');
  RAISE EXCEPTION 'NP01_0110_DISABLED_NEW_SUBMIT_ACCEPTED';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM NOT LIKE 'CONTROL_DISABLED:gov002.review%' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM core10.submit_typed_approval_v1(99821,'inventory','adjust',
   'np01-0110-src1',1,'{"quantity":7}'::jsonb,'np01_0110_submit_01');
  RAISE EXCEPTION 'NP01_0110_DISABLED_REPLAY_ACCEPTED';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM NOT LIKE 'CONTROL_DISABLED:gov002.review%' THEN RAISE; END IF;
 END;
 IF (SELECT count(*) FROM core10.approval_requests WHERE business_id=99821)<>requests_before
 THEN RAISE EXCEPTION 'NP01_0110_DISABLED_SUBMIT_MUTATED'; END IF;
END $t$;
SELECT set_config('request.jwt.claims','{"sub":"99822222-2222-4222-8222-222222222222"}',true);
SELECT set_config('request.jwt.claim.sub','99822222-2222-4222-8222-222222222222',true);
DO $t$
DECLARE event_count bigint;
BEGIN
 SELECT count(*) INTO event_count FROM core10.approval_events WHERE business_id=99821;
 BEGIN
  PERFORM core10.delegate_approval_stage_v1(current_setting('np01.b020_q1')::bigint,
   '99844444-4444-4444-8444-444444444444',30,'np01_0110_blocked_delegate');
  RAISE EXCEPTION 'NP01_0110_DISABLED_DELEGATE_ACCEPTED';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM NOT LIKE 'CONTROL_DISABLED:gov002.review%' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM core10.revoke_approval_delegation_v1(current_setting('np01.b020_q2')::bigint,
   'np01_0110_blocked_revoke');
  RAISE EXCEPTION 'NP01_0110_DISABLED_REVOKE_ACCEPTED';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM NOT LIKE 'CONTROL_DISABLED:gov002.review%' THEN RAISE; END IF;
 END;
 IF (SELECT count(*) FROM core10.approval_events WHERE business_id=99821)<>event_count
 THEN RAISE EXCEPTION 'NP01_0110_DISABLED_DELEGATION_EVENT'; END IF;
 IF (SELECT revoked_at FROM core10.approval_delegations_v1
    WHERE request_id=current_setting('np01.b020_q2')::bigint) IS NOT NULL
 THEN RAISE EXCEPTION 'NP01_0110_DISABLED_REVOKE_MUTATED'; END IF;
END $t$;
-- Cross-tenant forged metadata must fail Auth before Control.
SELECT set_config('request.jwt.claims',
 '{"sub":"99855555-5555-4555-8555-555555555555","app_metadata":{"role":"tenant_owner"}}',true);
SELECT set_config('request.jwt.claim.sub','99855555-5555-4555-8555-555555555555',true);
DO $t$
BEGIN
 BEGIN
  PERFORM core10.submit_typed_approval_v1(99821,'inventory','adjust','foreign',1,
   '{"quantity":9}'::jsonb,'np01_0110_foreign_submit');
  RAISE EXCEPTION 'NP01_0110_FOREIGN_SUBMIT_ACCEPTED';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'approval_submit_denied' THEN RAISE; END IF;
 END;
END $t$;
-- Reenable, verify legitimate delegation/revocation and idempotent receipts.
SELECT set_config('request.jwt.claims','{"sub":"99811111-1111-4111-8111-111111111111"}',true);
SELECT set_config('request.jwt.claim.sub','99811111-1111-4111-8111-111111111111',true);
DO $t$
DECLARE c jsonb;
BEGIN
 c:=core10.control_set_v1(99821,NULL,'gov002.review',true,1::smallint,'{}',NULL,
  false,1,'Resume B020 0110 review','np01_0110_enable_02');
 IF (c->>'version')::int<>2 THEN RAISE EXCEPTION 'NP01_0110_ENABLE_VERSION'; END IF;
END $t$;
SELECT set_config('request.jwt.claims','{"sub":"99822222-2222-4222-8222-222222222222"}',true);
SELECT set_config('request.jwt.claim.sub','99822222-2222-4222-8222-222222222222',true);
DO $t$
DECLARE d bigint; r bigint;
BEGIN
 d:=core10.delegate_approval_stage_v1(current_setting('np01.b020_q1')::bigint,
   '99844444-4444-4444-8444-444444444444',30,'np01_0110_delegate_allowed');
 IF core10.delegate_approval_stage_v1(current_setting('np01.b020_q1')::bigint,
   '99844444-4444-4444-8444-444444444444',30,'np01_0110_delegate_allowed')<>d
 THEN RAISE EXCEPTION 'NP01_0110_DELEGATE_REPLAY_DRIFT'; END IF;
 r:=core10.revoke_approval_delegation_v1(current_setting('np01.b020_q2')::bigint,
   'np01_0110_revoke_allowed');
 IF core10.revoke_approval_delegation_v1(current_setting('np01.b020_q2')::bigint,
   'np01_0110_revoke_allowed')<>r THEN RAISE EXCEPTION 'NP01_0110_REVOKE_REPLAY_DRIFT'; END IF;
END $t$;
SELECT set_config('request.jwt.claims','{"sub":"99811111-1111-4111-8111-111111111111"}',true);
SELECT set_config('request.jwt.claim.sub','99811111-1111-4111-8111-111111111111',true);
DO $t$
DECLARE rpc text;
BEGIN
 FOREACH rpc IN ARRAY ARRAY['submit_typed_approval_v1',
   'delegate_approval_stage_v1','revoke_approval_delegation_v1'] LOOP
  IF NOT EXISTS(SELECT 1 FROM core10.control_rpc_map_v1
     WHERE rpc_name=rpc AND status='enforced'
       AND feature_key='gov002.review'
       AND test_ref='tests/migrations/np01-control-submit-delegation-e2e.sql')
  THEN RAISE EXCEPTION 'NP01_0110_REGISTRY_MISSING:%',rpc; END IF;
 END LOOP;
 IF (core10.verify_canonical_audit_v1(99821)->>'ok')<>'true'
 THEN RAISE EXCEPTION 'NP01_0110_AUDIT_CHAIN_BROKEN'; END IF;
 RAISE NOTICE 'NP01_0110_CONTROL_SUBMIT_DELEGATE_REVOKE_OK';
END $t$;
ROLLBACK;
