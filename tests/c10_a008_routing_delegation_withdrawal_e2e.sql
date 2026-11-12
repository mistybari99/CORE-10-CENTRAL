-- GOV-002 real disposable PG17 E2E. Run AFTER existing typed + inbox suites.
-- All identities are inert fixture UUIDs; no signed GoTrue certification.
\set ON_ERROR_STOP on

-- Add second non-maker manager for bounded stage-one delegation; cannot act
-- without explicit per-request delegation or after its own membership revoke.
INSERT INTO c10_demo.business_members(tenant_id,business_id,user_id,role,active)
 VALUES (1,101,'99999999-9999-4999-8999-999999999999','manager',true);

SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);

DO $t$
DECLARE v_pol bigint;
BEGIN
 v_pol := c10_demo.publish_approval_policy_v1(
     101,'demo_inventory','adjustment_review',60,'policy_two_stage_03');
 IF v_pol<>3 THEN RAISE EXCEPTION 'FAIL: policy fixture sequence'; END IF;
 IF c10_demo.configure_approval_route_v1(v_pol,'route_two_step_03')<>v_pol
    OR c10_demo.configure_approval_route_v1(v_pol,'route_two_step_03')<>v_pol
 THEN RAISE EXCEPTION 'FAIL: route idempotent configuration'; END IF;
 BEGIN
  PERFORM c10_demo.configure_approval_route_v1(v_pol,'route_changed_03');
  RAISE EXCEPTION 'FAIL: route mutation accepted';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'route_replay_conflict' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM c10_demo.configure_approval_route_v1(2,'route_late_02');
  RAISE EXCEPTION 'FAIL: route installed after request already exists';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'route_already_in_use' THEN RAISE; END IF;
 END;
END $t$;

-- Two routed requests, one for final approval and one for delegation revoke.
SELECT set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',false);
SELECT c10_demo.submit_typed_approval_v1(
 101,'demo_inventory','adjustment_review','two-stage-doc-1',1,
 '{"amount":120,"unit":"kg"}'::jsonb,'two_stage_submit_01');
SELECT c10_demo.submit_typed_approval_v1(
 101,'demo_inventory','adjustment_review','two-stage-doc-2',1,
 '{"amount":200,"unit":"kg"}'::jsonb,'two_stage_submit_02');

-- Site-only user cannot access a routed request via an untrusted id.
SELECT set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',false);
DO $t$ BEGIN
 BEGIN
  PERFORM c10_demo.decide_approval(4,'approve','site_only_approve');
  RAISE EXCEPTION 'FAIL: site-only checker accepted';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'approval_not_authorized' THEN RAISE; END IF;
 END;
END $t$;

-- Manager with a business membership is NOT inherently an approver.
SELECT set_config('request.jwt.claim.sub','99999999-9999-4999-8999-999999999999',false);
DO $t$ BEGIN
 BEGIN
  PERFORM c10_demo.decide_approval(4,'approve','before_grant_01');
  RAISE EXCEPTION 'FAIL: delegated manager acted before grant';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'approval_not_authorized' THEN RAISE; END IF;
 END;
END $t$;

-- Grantor must be actual active business owner, not tenant owner or maker.
SELECT set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',false);
DO $t$ BEGIN
 BEGIN
  PERFORM c10_demo.delegate_approval_stage_v1(
   4,'99999999-9999-4999-8999-999999999999',15,'maker_delegate_01');
  RAISE EXCEPTION 'FAIL: maker delegated reviewer';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'delegation_not_authorized' THEN RAISE; END IF;
 END;
END $t$;
SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
DO $t$
DECLARE a bigint;b bigint;
BEGIN
 a:=c10_demo.delegate_approval_stage_v1(
   4,'99999999-9999-4999-8999-999999999999',30,'grant_stage_one_01');
 b:=c10_demo.delegate_approval_stage_v1(
   4,'99999999-9999-4999-8999-999999999999',30,'grant_stage_one_01');
 IF a<>b THEN RAISE EXCEPTION 'FAIL: delegation idempotency'; END IF;
 BEGIN
  PERFORM c10_demo.delegate_approval_stage_v1(
   4,'99999999-9999-4999-8999-999999999999',30,'grant_changed_01');
  RAISE EXCEPTION 'FAIL: delegation key overwrite';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'delegation_replay_conflict' THEN RAISE; END IF;
 END;
 -- Grant on second request and revoke before any vote.
 PERFORM c10_demo.delegate_approval_stage_v1(
   5,'99999999-9999-4999-8999-999999999999',30,'grant_for_revoke_02');
 IF NOT c10_demo.revoke_approval_delegation_v1(5)
    OR c10_demo.revoke_approval_delegation_v1(5)
 THEN RAISE EXCEPTION 'FAIL: delegation revocation/idempotency'; END IF;
END $t$;

SELECT set_config('request.jwt.claim.sub','99999999-9999-4999-8999-999999999999',false);
DO $t$ BEGIN
 BEGIN
  PERFORM c10_demo.decide_approval(5,'approve','after_revoke_02');
  RAISE EXCEPTION 'FAIL: revoked delegate approved';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'approval_not_authorized' THEN RAISE; END IF;
 END;
END $t$;

-- Stage 1 approval only advances the route. Status remains PENDING and
-- service binding must not accept it.
DO $t$ BEGIN
 PERFORM c10_demo.decide_approval(4,'approve','delegated_stage_one_01');
 IF (SELECT status FROM c10_demo.approval_requests WHERE id=4)<>'pending'
 THEN RAISE EXCEPTION 'FAIL: intermediate stage became final approval'; END IF;
END $t$;

-- Same reviewer cannot take stage two; business owner can't take tenant stage.
SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
DO $t$ BEGIN
 BEGIN
  PERFORM c10_demo.decide_approval(4,'approve','wrong_stage_two_01');
  RAISE EXCEPTION 'FAIL: business owner bypassed tenant-owner stage';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'approval_not_authorized' THEN RAISE; END IF;
 END;
END $t$;

SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
DO $t$
DECLARE v bigint; retry bigint;
BEGIN
 v:=c10_demo.decide_approval(4,'approve','tenant_stage_two_01');
 retry:=c10_demo.decide_approval(4,'approve','tenant_stage_two_01');
 IF v<>retry OR (SELECT status FROM c10_demo.approval_requests WHERE id=4)<>'approved'
 THEN RAISE EXCEPTION 'FAIL: second stage final approval/idempotency'; END IF;
 IF (SELECT count(*) FROM c10_demo.approval_stage_receipts_v1 WHERE request_id=4)<>2
 THEN RAISE EXCEPTION 'FAIL: route receipts'; END IF;
END $t$;

SELECT set_config('request.jwt.claim.sub','99999999-9999-4999-8999-999999999999',false);
DO $t$ BEGIN
 IF c10_demo.decide_approval(4,'approve','delegated_stage_one_01') IS NULL
 THEN RAISE EXCEPTION 'FAIL: stage-one decision replay'; END IF;
END $t$;

RESET ROLE;
-- Trusted service only; no stock posting, but final route is a valid review.
SET ROLE service_role;
SELECT c10_demo.verify_approval_binding_v1(
  4,101,'demo_inventory','adjustment_review','two-stage-doc-1',1,
  '{"unit":"kg","amount":120}'::jsonb);
DO $t$ BEGIN
 BEGIN
  PERFORM c10_demo.verify_approval_binding_v1(
   5,101,'demo_inventory','adjustment_review','two-stage-doc-2',1,
   '{"amount":200,"unit":"kg"}'::jsonb);
  RAISE EXCEPTION 'FAIL: missing stage approvals accepted';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'approval_not_effective' THEN RAISE; END IF;
 END;
END $t$;
RESET ROLE;

-- Maker withdraws a pending routed request; idempotent event, no later vote.
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',false);
DO $t$
DECLARE v bigint;retry bigint;
BEGIN
 v:=c10_demo.withdraw_typed_approval_v1(5,'withdraw_route_02');
 retry:=c10_demo.withdraw_typed_approval_v1(5,'withdraw_route_02');
 IF v<>retry OR (SELECT status FROM c10_demo.approval_requests WHERE id=5)<>'withdrawn'
 THEN RAISE EXCEPTION 'FAIL: routed withdrawal/replay'; END IF;
 BEGIN
  PERFORM c10_demo.withdraw_typed_approval_v1(4,'withdraw_approved_01');
  RAISE EXCEPTION 'FAIL: approved request withdrawn';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'withdraw_invalid_transition' THEN RAISE; END IF;
 END;
END $t$;

SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
DO $t$ BEGIN
 BEGIN
  PERFORM c10_demo.decide_approval(5,'approve','after_withdraw_01');
  RAISE EXCEPTION 'FAIL: withdrawn request approved';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'approval_invalid_transition' THEN RAISE; END IF;
 END;
END $t$;
-- Foreign tenant cannot withdraw, configure, delegate, or inspect business 101.
SELECT set_config('request.jwt.claim.sub','77777777-7777-4777-8777-777777777777',false);
DO $t$ BEGIN
 BEGIN
  PERFORM c10_demo.withdraw_typed_approval_v1(5,'foreign_withdraw_01');
  RAISE EXCEPTION 'FAIL: foreign actor withdrawal';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'withdraw_not_authorized' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM c10_demo.configure_approval_route_v1(3,'foreign_route_01');
  RAISE EXCEPTION 'FAIL: foreign actor route configure';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'route_not_authorized' THEN RAISE; END IF;
 END;
 IF (SELECT count(*) FROM c10_demo.approval_stage_receipts_v1)<>0
 THEN RAISE EXCEPTION 'FAIL: foreign tenant sees approval receipts'; END IF;
END $t$;
RESET ROLE;

-- DB-level invariants: app roles cannot mutate stage, route or delegation records.
DO $t$ BEGIN
 IF has_table_privilege('authenticated','c10_demo.approval_routes_v1','UPDATE')
 OR has_table_privilege('authenticated','c10_demo.approval_delegations_v1','INSERT')
 OR has_table_privilege('authenticated','c10_demo.approval_stage_receipts_v1','DELETE')
 OR has_function_privilege('anon','c10_demo.withdraw_typed_approval_v1(bigint,text)','EXECUTE')
 THEN RAISE EXCEPTION 'FAIL: route/delegation ACL breach'; END IF;
 IF (SELECT count(*) FROM c10_demo.stock_movements)<>0
 THEN RAISE EXCEPTION 'FAIL: route system posted inventory'; END IF;
 IF (SELECT count(*) FROM c10_demo.approval_stage_receipts_v1 WHERE request_id=4)<>2
 THEN RAISE EXCEPTION 'FAIL: append-only stage history'; END IF;
 RAISE NOTICE 'PASS: two-stage routed approval, bounded delegation/revoke, maker withdrawal, role/tenant/stage negatives, idempotency, zero posting';
END $t$;


-- Extra safeguards: current role, revocation race, expiry and withdrawal AFTER
-- an intermediate stage. No trusted identity is ever supplied by the client.
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',false);
SELECT c10_demo.submit_typed_approval_v1(
 101,'demo_inventory','adjustment_review','two-stage-doc-6',1,
 '{"amount":610,"unit":"kg"}'::jsonb,'two_stage_submit_06');
SELECT c10_demo.submit_typed_approval_v1(
 101,'demo_inventory','adjustment_review','two-stage-doc-7',1,
 '{"amount":720,"unit":"kg"}'::jsonb,'two_stage_submit_07');

SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
DO $t$ BEGIN
 BEGIN
  PERFORM c10_demo.decide_approval(7,'approve','tenant_skips_stage_01');
  RAISE EXCEPTION 'FAIL: tenant-level owner hijacked business-owner stage';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'approval_not_authorized' THEN RAISE; END IF;
 END;
END $t$;

SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
DO $t$ BEGIN
 PERFORM c10_demo.decide_approval(6,'approve','stage_one_then_withdraw');
 IF (SELECT status FROM c10_demo.approval_requests WHERE id=6)<>'pending'
 THEN RAISE EXCEPTION 'FAIL: intermediate approval finalized'; END IF;
 PERFORM c10_demo.delegate_approval_stage_v1(
 7,'99999999-9999-4999-8999-999999999999',30,'grant_revocation_07');
 BEGIN
  PERFORM c10_demo.delegate_approval_stage_v1(
   7,'99999999-9999-4999-8999-999999999999',15,'grant_revocation_07');
  RAISE EXCEPTION 'FAIL: delegation TTL replay conflict accepted';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'delegation_replay_conflict' THEN RAISE; END IF;
 END;
END $t$;

SELECT set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',false);
DO $t$ BEGIN
 PERFORM c10_demo.withdraw_typed_approval_v1(6,'withdraw_after_stage_one');
 IF (SELECT status FROM c10_demo.approval_requests WHERE id=6)<>'withdrawn'
 THEN RAISE EXCEPTION 'FAIL: staged request not withdrawn'; END IF;
END $t$;

SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
DO $t$ BEGIN
 BEGIN
  PERFORM c10_demo.decide_approval(6,'approve','after_midstage_withdraw');
  RAISE EXCEPTION 'FAIL: stage two approved withdrawn request';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'approval_invalid_transition' THEN RAISE; END IF;
 END;
END $t$;
RESET ROLE;

-- Superuser fixture toggles role to model real-time revoke before a vote.
UPDATE c10_demo.business_members SET active=false
 WHERE business_id=101 AND user_id='99999999-9999-4999-8999-999999999999';
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','99999999-9999-4999-8999-999999999999',false);
DO $t$ BEGIN
 BEGIN
  PERFORM c10_demo.decide_approval(7,'approve','revoked_membership_07');
  RAISE EXCEPTION 'FAIL: revoked delegated manager approved';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'approval_not_authorized' THEN RAISE; END IF;
 END;
END $t$;
RESET ROLE;
UPDATE c10_demo.business_members SET active=true
 WHERE business_id=101 AND user_id='99999999-9999-4999-8999-999999999999';
-- Fixture expiry of the explicit grant, without sleeping 30 minutes.
UPDATE c10_demo.approval_delegations_v1 SET valid_until=clock_timestamp()-interval '1 minute'
 WHERE request_id=7;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','99999999-9999-4999-8999-999999999999',false);
DO $t$ BEGIN
 BEGIN
  PERFORM c10_demo.decide_approval(7,'approve','expired_delegation_07');
  RAISE EXCEPTION 'FAIL: expired delegated manager approved';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'approval_not_authorized' THEN RAISE; END IF;
 END;
END $t$;
RESET ROLE;

DO $t$ BEGIN
 IF (SELECT count(*) FROM c10_demo.approval_delegation_events_v1)<>4
 THEN RAISE EXCEPTION 'FAIL: grant/revoke append-only event count'; END IF;
 IF (SELECT count(*) FROM c10_demo.approval_stage_receipts_v1
      WHERE request_id=4 AND delegated_by='22222222-2222-4222-8222-222222222222')<>1
 THEN RAISE EXCEPTION 'FAIL: delegated vote not attributed to grantor'; END IF;
 IF (SELECT count(*) FROM c10_demo.approval_stage_receipts_v1
      WHERE request_id=6 AND stage_no=1)<>1
 THEN RAISE EXCEPTION 'FAIL: midstage withdrawal lost previous evidence'; END IF;
 IF (SELECT count(*) FROM c10_demo.stock_movements)<>0
 THEN RAISE EXCEPTION 'FAIL: approval posted a stock event'; END IF;
 RAISE NOTICE 'PASS: exact-role stage, TTL conflict, midstage withdrawal, membership revoke, expired delegation and append-only grant/revoke audit';
END $t$;
