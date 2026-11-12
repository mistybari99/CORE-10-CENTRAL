-- GOV002 exception escalation E2E: real disposable PG17, synthetic users.
-- Requires all parent tests and source concurrency already run; no live ERP.
\set ON_ERROR_STOP on
SELECT set_config('demo.test.movement_baseline',
 (SELECT count(*)::text FROM c10_demo.stock_movements),false);

-- Business owner publishes ONE normal approval policy. Escalation is an
-- optional separate triage journal and can never modify that policy.
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
DO $t$ BEGIN
 IF c10_demo.publish_approval_policy_v1(
  101,'demo_ops','exception_review',60,'exception_review_policy_01') IS NULL
 THEN RAISE EXCEPTION 'FAIL: exception fixture policy'; END IF;
END $t$;

-- Requester submits canonical typed requests, then a bounded exception.
SELECT set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',false);
DO $t$
DECLARE r bigint;e bigint;replay bigint;
BEGIN
 r:=c10_demo.submit_typed_approval_v1(
  101,'demo_ops','exception_review','exception-case-1',1,
  '{"case":"a","amount":5}'::jsonb,'exception_parent_submit_01');
 e:=c10_demo.request_approval_exception_v1(
  r,'Urgent risk triage needed','urgent',20,'exception_create_01');
 replay:=c10_demo.request_approval_exception_v1(
  r,'Urgent risk triage needed','urgent',20,'exception_create_01');
 IF e<>replay OR e IS NULL
 THEN RAISE EXCEPTION 'FAIL: escalation replay not stable'; END IF;
 PERFORM set_config('demo.test.exception_a',e::text,false);
 PERFORM set_config('demo.test.parent_a',r::text,false);
 BEGIN
  PERFORM c10_demo.request_approval_exception_v1(
   r,'Different bypass attempt','urgent',20,'exception_create_01');
  RAISE EXCEPTION 'FAIL: changed reason replay accepted';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'exception_request_replay_conflict' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM c10_demo.request_approval_exception_v1(
   r,'Urgent risk triage needed','urgent',20,'exception_new_key_02');
  RAISE EXCEPTION 'FAIL: duplicate escalation on same request';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'exception_request_replay_conflict' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM c10_demo.request_approval_exception_v1(
   r,'short','urgent',20,'exception_short_reason_03');
  RAISE EXCEPTION 'FAIL: short exception reason';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'invalid_exception_request' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM c10_demo.request_approval_exception_v1(
   r,'Urgent risk triage needed','urgent',1441,'exception_ttl_over_04');
  RAISE EXCEPTION 'FAIL: unbounded >24h request';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'invalid_exception_request' THEN RAISE; END IF;
 END;
 IF NOT EXISTS(SELECT 1 FROM c10_demo.approval_exception_inbox_v1
    WHERE escalation_id=e AND display_status='pending'
      AND parent_approval_status='pending' AND severity='urgent')
 THEN RAISE EXCEPTION 'FAIL: maker cannot see own pending triage'; END IF;
 IF (SELECT count(*) FROM c10_demo.approval_exception_events_v1
     WHERE escalation_id=e)<>1
 THEN RAISE EXCEPTION 'FAIL: submitted event not appended'; END IF;
 BEGIN
  PERFORM c10_demo.decide_approval_exception_v1(
   e,'acknowledged','exception_self_vote_01');
  RAISE EXCEPTION 'FAIL: maker self-acknowledged exception';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'exception_decision_denied' THEN RAISE; END IF;
 END;
END $t$;

-- Owner acknowledgement must never set the canonical approval to approved.
SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
DO $t$
DECLARE e bigint:=current_setting('demo.test.exception_a')::bigint;
        r bigint:=current_setting('demo.test.parent_a')::bigint;
        ev bigint;
BEGIN
 ev:=c10_demo.decide_approval_exception_v1(
  e,'acknowledged','exception_owner_ack_01');
 IF ev<>c10_demo.decide_approval_exception_v1(
  e,'acknowledged','exception_owner_ack_01')
 THEN RAISE EXCEPTION 'FAIL: decision replay not stable'; END IF;
 BEGIN
  PERFORM c10_demo.decide_approval_exception_v1(
   e,'declined','exception_new_terminal_02');
  RAISE EXCEPTION 'FAIL: escalation second terminal decision';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'exception_stale_or_final' THEN RAISE; END IF;
 END;
 IF (SELECT status FROM c10_demo.approval_requests WHERE id=r)<>'pending'
  OR (SELECT status FROM c10_demo.approval_exception_escalations_v1
      WHERE id=e)<>'acknowledged'
  OR (SELECT count(*) FROM c10_demo.approval_exception_events_v1
      WHERE escalation_id=e)<>2
 THEN RAISE EXCEPTION 'FAIL: triage improperly changed main approval or audit'; END IF;
END $t$;

SELECT set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',false);
DO $t$
DECLARE r bigint;e bigint;
BEGIN
 -- Maker cannot withdraw an already owner-reviewed escalation.
 BEGIN
  PERFORM c10_demo.withdraw_approval_exception_v1(
   current_setting('demo.test.exception_a')::bigint,'exception_late_withdraw_01');
  RAISE EXCEPTION 'FAIL: accepted withdrawal after terminal reviewer action';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'exception_stale_or_final' THEN RAISE; END IF;
 END;

 r:=c10_demo.submit_typed_approval_v1(
  101,'demo_ops','exception_review','exception-case-2',1,
  '{"case":"b"}'::jsonb,'exception_parent_submit_02');
 e:=c10_demo.request_approval_exception_v1(
  r,'Investigate unusual request origin','normal',15,'exception_create_02');
 PERFORM set_config('demo.test.exception_b',e::text,false);
 PERFORM c10_demo.withdraw_approval_exception_v1(e,'exception_maker_withdraw_02');
 IF (SELECT status FROM c10_demo.approval_requests WHERE id=r)<>'pending'
 THEN RAISE EXCEPTION 'FAIL: withdraw triage changed parent approval'; END IF;

 r:=c10_demo.submit_typed_approval_v1(
  101,'demo_ops','exception_review','exception-case-3',1,
  '{"case":"c"}'::jsonb,'exception_parent_submit_03');
 e:=c10_demo.request_approval_exception_v1(
  r,'Review unexpected operation timing','urgent',15,'exception_create_03');
 PERFORM set_config('demo.test.exception_c',e::text,false);
 PERFORM set_config('demo.test.parent_c',r::text,false);

 r:=c10_demo.submit_typed_approval_v1(
  101,'demo_ops','exception_review','exception-case-4',1,
  '{"case":"d"}'::jsonb,'exception_parent_submit_04');
 e:=c10_demo.request_approval_exception_v1(
  r,'Expiring review must not authorize','urgent',5,'exception_create_04');
 PERFORM set_config('demo.test.exception_d',e::text,false);
END $t$;

-- Closing the parent request invalidates all outstanding escalation actions.
SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
SELECT c10_demo.decide_approval(
 current_setting('demo.test.parent_c')::bigint,'approve','exception_parent_regular_approve_03');
DO $t$
BEGIN
 BEGIN
  PERFORM c10_demo.decide_approval_exception_v1(
   current_setting('demo.test.exception_b')::bigint,
   'declined','exception_owner_closed_b_01');
  RAISE EXCEPTION 'FAIL: withdrawn triage accepted new decision';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'exception_stale_or_final' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM c10_demo.decide_approval_exception_v1(
   current_setting('demo.test.exception_c')::bigint,
   'acknowledged','exception_owner_closed_c_01');
  RAISE EXCEPTION 'FAIL: owner escalated already approved parent';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'exception_stale_or_final' THEN RAISE; END IF;
 END;
 IF NOT EXISTS(SELECT 1 FROM c10_demo.approval_exception_inbox_v1
     WHERE escalation_id=current_setting('demo.test.exception_c')::bigint
       AND display_status='parent_closed' AND parent_approval_status='approved')
 THEN RAISE EXCEPTION 'FAIL: source closed state not reflected'; END IF;
END $t$;

-- In a throwaway DB only, simulate expiration by moving both timestamps
-- backwards; tests the SERVER clock guard without sleeping five minutes.
RESET ROLE;
UPDATE c10_demo.approval_exception_escalations_v1
 SET created_at=created_at-interval '1 day',
     expires_at=clock_timestamp()-interval '1 second'
 WHERE id=current_setting('demo.test.exception_d')::bigint;

SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
DO $t$ BEGIN
 BEGIN
  PERFORM c10_demo.decide_approval_exception_v1(
    current_setting('demo.test.exception_d')::bigint,
    'acknowledged','exception_owner_expired_d_01');
  RAISE EXCEPTION 'FAIL: expired triage acknowledged';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'exception_stale_or_final' THEN RAISE; END IF;
 END;
 IF NOT EXISTS(SELECT 1 FROM c10_demo.approval_exception_inbox_v1
   WHERE escalation_id=current_setting('demo.test.exception_d')::bigint
    AND display_status='expired')
 THEN RAISE EXCEPTION 'FAIL: expiry view wrong'; END IF;
END $t$;

-- Foreign and low-privilege users cannot read/decide; no leaked badge/count.
SELECT set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',false);
DO $t$ BEGIN
 IF (SELECT count(*) FROM c10_demo.approval_exception_inbox_v1)<>0
 THEN RAISE EXCEPTION 'FAIL: site-only sees escalation'; END IF;
 BEGIN
  PERFORM c10_demo.decide_approval_exception_v1(
   current_setting('demo.test.exception_a')::bigint,
   'acknowledged','site_escalation_attack_01');
  RAISE EXCEPTION 'FAIL: site-only reviewer';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'exception_decision_denied' THEN RAISE; END IF;
 END;
END $t$;
SELECT set_config('request.jwt.claim.sub','55555555-5555-4555-8555-555555555555',false);
DO $t$ BEGIN
 IF (SELECT count(*) FROM c10_demo.approval_exception_inbox_v1)<>0
 THEN RAISE EXCEPTION 'FAIL: investor escalation count leak'; END IF;
END $t$;
SELECT set_config('request.jwt.claim.sub','66666666-6666-4666-8666-666666666666',false);
DO $t$ BEGIN
 IF (SELECT count(*) FROM c10_demo.approval_exception_inbox_v1)<>0
 THEN RAISE EXCEPTION 'FAIL: revoked escalation count leak'; END IF;
END $t$;
SELECT set_config('request.jwt.claim.sub','77777777-7777-4777-8777-777777777777',false);
DO $t$ BEGIN
 IF (SELECT count(*) FROM c10_demo.approval_exception_inbox_v1)<>0
 THEN RAISE EXCEPTION 'FAIL: other-tenant escalation data leak'; END IF;
 BEGIN
  PERFORM c10_demo.decide_approval_exception_v1(
   current_setting('demo.test.exception_a')::bigint,
   'declined','other_tenant_try_01');
  RAISE EXCEPTION 'FAIL: cross-tenant escalation reviewer';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'exception_decision_denied' THEN RAISE; END IF;
 END;
END $t$;
RESET ROLE;
DO $t$ BEGIN
 IF has_table_privilege('authenticated','c10_demo.approval_exception_escalations_v1','INSERT')
 OR has_table_privilege('authenticated','c10_demo.approval_exception_escalations_v1','UPDATE')
 OR has_table_privilege('authenticated','c10_demo.approval_exception_events_v1','DELETE')
 OR has_table_privilege('anon','c10_demo.approval_exception_inbox_v1','SELECT')
 OR has_function_privilege('anon','c10_demo.decide_approval_exception_v1(bigint,text,text)','EXECUTE')
 THEN RAISE EXCEPTION 'FAIL: public escalation mutation/visibility permission'; END IF;
 IF (SELECT count(*) FROM c10_demo.stock_movements)::text<>
   current_setting('demo.test.movement_baseline')
 THEN RAISE EXCEPTION 'FAIL: escalation created stock movement'; END IF;
 IF (SELECT count(*) FROM c10_demo.approval_exception_escalations_v1)<>4
 OR (SELECT count(*) FROM c10_demo.approval_exception_events_v1)<>5
 THEN RAISE EXCEPTION 'FAIL: event chain or duplicate escalation row'; END IF;
 RAISE NOTICE 'PASS: typed exception triage with actor, reason, scoped reviewer, parent/expiry/TTL, idempotency, immutable events, no stock/approval bypass';
END $t$;
