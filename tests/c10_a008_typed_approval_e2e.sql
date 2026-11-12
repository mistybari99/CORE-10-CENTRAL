-- C10-CAP-GOV-002 isolated PG17 executable E2E. Synthetic JWT claims only.
-- Test setup: A018 demo backend + seed + A008 prototype + typed extension.
\set ON_ERROR_STOP on

-- PUBLISH: business owner can append policies; idempotency pins first version.
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
DO $t$
DECLARE a bigint; b bigint; retry bigint;
BEGIN
 a := c10_demo.publish_approval_policy_v1(101,'demo_inventory','adjustment_review',30,'policy_version_01');
 retry := c10_demo.publish_approval_policy_v1(101,'demo_inventory','adjustment_review',30,'policy_version_01');
 b := c10_demo.publish_approval_policy_v1(101,'demo_inventory','adjustment_review',60,'policy_version_02');
 IF a IS DISTINCT FROM retry OR a IS NULL OR b IS NULL OR a=b THEN
   RAISE EXCEPTION 'FAIL: policy idempotency/append version'; END IF;
 BEGIN
   PERFORM c10_demo.publish_approval_policy_v1(101,'demo_inventory','adjustment_review',40,'policy_version_01');
   RAISE EXCEPTION 'FAIL: changed policy key accepted';
 EXCEPTION WHEN OTHERS THEN
   IF SQLERRM <> 'approval_policy_replay_conflict' THEN RAISE; END IF;
 END;
 BEGIN
   PERFORM c10_demo.publish_approval_policy_v1(201,'demo_inventory','adjustment_review',30,'policy_foreign_01');
   RAISE EXCEPTION 'FAIL: foreign business policy accepted';
 EXCEPTION WHEN OTHERS THEN
   IF SQLERRM <> 'approval_policy_denied' THEN RAISE; END IF;
 END;
END $t$;

-- CREATE: manager has scoped business access but cannot publish policy.
SELECT set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',false);
DO $t$
DECLARE v bigint; again bigint;
BEGIN
 BEGIN
   PERFORM c10_demo.publish_approval_policy_v1(101,'demo_inventory','adjustment_review',30,'policy_manager_01');
   RAISE EXCEPTION 'FAIL: manager published approval policy';
 EXCEPTION WHEN OTHERS THEN
   IF SQLERRM <> 'approval_policy_denied' THEN RAISE; END IF;
 END;
 v := c10_demo.submit_typed_approval_v1(
   101,'demo_inventory','adjustment_review','fixture-doc-1',3,
   '{"amount":10,"unit":"kg"}'::jsonb,'request_first_01');
 again := c10_demo.submit_typed_approval_v1(
   101,'demo_inventory','adjustment_review','fixture-doc-1',3,
   '{"unit":"kg","amount":10}'::jsonb,'request_first_01');
 IF v IS DISTINCT FROM again THEN RAISE EXCEPTION 'FAIL: normalized JSONB retry'; END IF;
 BEGIN
   PERFORM c10_demo.submit_typed_approval_v1(
     101,'demo_inventory','adjustment_review','fixture-doc-1',4,
     '{"amount":10,"unit":"kg"}'::jsonb,'request_first_01');
   RAISE EXCEPTION 'FAIL: source version replay changed';
 EXCEPTION WHEN OTHERS THEN
   IF SQLERRM <> 'approval_submit_replay_conflict' THEN RAISE; END IF;
 END;
 BEGIN
   PERFORM c10_demo.submit_typed_approval_v1(
     101,'demo_inventory','adjustment_review','fixture-doc-1',3,
     '{"amount":11,"unit":"kg"}'::jsonb,'request_first_01');
   RAISE EXCEPTION 'FAIL: payload changed under same key';
 EXCEPTION WHEN OTHERS THEN
   IF SQLERRM <> 'approval_submit_replay_conflict' THEN RAISE; END IF;
 END;
 BEGIN
   PERFORM c10_demo.submit_typed_approval_v1(
     102,'demo_inventory','adjustment_review','fixture-doc-foreign',1,
     '{}'::jsonb,'request_other_01');
   RAISE EXCEPTION 'FAIL: foreign business request accepted';
 EXCEPTION WHEN OTHERS THEN
   IF SQLERRM <> 'approval_submit_denied' THEN RAISE; END IF;
 END;
END $t$;

-- Remaining negative personas: revoked user and investor get no request authority.
SELECT set_config('request.jwt.claim.sub','66666666-6666-4666-8666-666666666666',false);
DO $t$
BEGIN
 BEGIN
   PERFORM c10_demo.submit_typed_approval_v1(
     101,'demo_inventory','adjustment_review','revoked',1,
     '{}'::jsonb,'request_revoked_01');
   RAISE EXCEPTION 'FAIL: revoked staff submission accepted';
 EXCEPTION WHEN OTHERS THEN
   IF SQLERRM <> 'approval_submit_denied' THEN RAISE; END IF;
 END;
END $t$;
SELECT set_config('request.jwt.claim.sub','55555555-5555-4555-8555-555555555555',false);
DO $t$
BEGIN
 BEGIN
   PERFORM c10_demo.submit_typed_approval_v1(
     101,'demo_inventory','adjustment_review','investor',1,
     '{}'::jsonb,'request_investor_01');
   RAISE EXCEPTION 'FAIL: investor submission accepted';
 EXCEPTION WHEN OTHERS THEN
   IF SQLERRM <> 'approval_submit_denied' THEN RAISE; END IF;
 END;
END $t$;

-- Policy pin stays v2 even after further Owner policy update.
SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
DO $t$
DECLARE v bigint; replay bigint;
BEGIN
 IF NOT EXISTS (
    SELECT 1 FROM c10_demo.approval_requests r
    JOIN c10_demo.approval_policy_versions_v1 p ON p.id=r.policy_id_v1
    WHERE r.business_id=101 AND r.created_by='33333333-3333-4333-8333-333333333333'
      AND r.policy_version_v1=2 AND p.version=2
      AND p.ttl_minutes=60 AND r.payload_sha256_v1 ~ '^[0-9a-f]{64}$'
 ) THEN RAISE EXCEPTION 'FAIL: request did not pin latest version'; END IF;

 -- Synthetic test fixture has exactly one request so far, id=1.
 v := c10_demo.decide_approval(1,'approve','decision_approve_01');
 replay := c10_demo.decide_approval(1,'approve','decision_approve_01');
 IF v IS DISTINCT FROM replay THEN RAISE EXCEPTION 'FAIL: replay event identity'; END IF;
 BEGIN
   PERFORM c10_demo.decide_approval(1,'reject','decision_approve_01');
   RAISE EXCEPTION 'FAIL: changed decision replay accepted';
 EXCEPTION WHEN OTHERS THEN
   IF SQLERRM <> 'approval_idempotency_conflict' THEN RAISE; END IF;
 END;
END $t$;

-- Authenticated app role cannot pretend to be the trusted typed executor.
DO $t$
BEGIN
 IF has_function_privilege('authenticated',
    'c10_demo.verify_approval_binding_v1(bigint,bigint,text,text,text,bigint,jsonb)',
    'EXECUTE') THEN
   RAISE EXCEPTION 'FAIL: authenticated can verify service-only binding'; END IF;
END $t$;

-- Trusted adapter binding validation; it does NOT post any stock or finance event.
RESET ROLE;
SET ROLE service_role;
DO $t$
DECLARE receipt bigint;
BEGIN
 receipt := c10_demo.verify_approval_binding_v1(
   1,101,'demo_inventory','adjustment_review','fixture-doc-1',3,
   '{"unit":"kg","amount":10}'::jsonb);
 IF receipt IS NULL THEN RAISE EXCEPTION 'FAIL: approved receipt not returned'; END IF;
 BEGIN
   PERFORM c10_demo.verify_approval_binding_v1(
     1,101,'demo_inventory','adjustment_review','fixture-doc-1',4,
     '{"unit":"kg","amount":10}'::jsonb);
   RAISE EXCEPTION 'FAIL: stale source version accepted';
 EXCEPTION WHEN OTHERS THEN
   IF SQLERRM <> 'approval_stale_or_payload_changed' THEN RAISE; END IF;
 END;
 BEGIN
   PERFORM c10_demo.verify_approval_binding_v1(
     1,101,'demo_inventory','adjustment_review','fixture-doc-1',3,
     '{"unit":"kg","amount":11}'::jsonb);
   RAISE EXCEPTION 'FAIL: altered payload accepted';
 EXCEPTION WHEN OTHERS THEN
   IF SQLERRM <> 'approval_stale_or_payload_changed' THEN RAISE; END IF;
 END;
 BEGIN
   PERFORM c10_demo.verify_approval_binding_v1(
     1,201,'demo_inventory','adjustment_review','fixture-doc-1',3,
     '{"unit":"kg","amount":10}'::jsonb);
   RAISE EXCEPTION 'FAIL: alternate business binding accepted';
 EXCEPTION WHEN OTHERS THEN
   IF SQLERRM <> 'approval_stale_or_payload_changed' THEN RAISE; END IF;
 END;
END $t$;
RESET ROLE;

-- Test expiry and maker-checker invariants on two additional requests.
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',false);
SELECT c10_demo.submit_typed_approval_v1(
  101,'demo_inventory','adjustment_review','fixture-doc-expired',1,
  '{"amount":2}'::jsonb,'request_expired_01');
RESET ROLE;
-- PostgreSQL superuser edits a synthetic test fixture to avoid 5-minute sleep.
UPDATE c10_demo.approval_requests
SET created_at = clock_timestamp() - interval '2 hours',
    expires_at_v1 = clock_timestamp() - interval '1 hour'
WHERE id=2;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
DO $t$
BEGIN
 BEGIN
   PERFORM c10_demo.decide_approval(2,'approve','decision_expired_01');
   RAISE EXCEPTION 'FAIL: expired approval accepted';
 EXCEPTION WHEN OTHERS THEN
   IF SQLERRM <> 'approval_expired' THEN RAISE; END IF;
 END;
END $t$;

SELECT c10_demo.submit_typed_approval_v1(
  101,'demo_inventory','adjustment_review','fixture-maker',1,
  '{"amount":7}'::jsonb,'request_selfmade_01');
DO $t$
BEGIN
 BEGIN
   PERFORM c10_demo.decide_approval(3,'approve','decision_selfmade_01');
   RAISE EXCEPTION 'FAIL: self-approval accepted';
 EXCEPTION WHEN OTHERS THEN
   IF SQLERRM <> 'approval_not_authorized' THEN RAISE; END IF;
 END;
END $t$;

-- Explicit table update attempts are privilege-denied, not merely hidden by the UI.
DO $t$
BEGIN
 BEGIN
   UPDATE c10_demo.approval_policy_versions_v1 SET ttl_minutes=5 WHERE id=1;
   RAISE EXCEPTION 'FAIL: authenticated rewrote immutable policy';
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
 BEGIN
   UPDATE c10_demo.approval_requests SET source_version_v1=99 WHERE id=1;
   RAISE EXCEPTION 'FAIL: authenticated rewrote signed request';
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
END $t$;
RESET ROLE;

-- Final independent superuser audit of row effects and ACL.
DO $t$
BEGIN
 IF (SELECT count(*) FROM c10_demo.approval_policy_versions_v1) <> 2
 OR (SELECT count(*) FROM c10_demo.approval_requests) <> 3
 OR (SELECT count(*) FROM c10_demo.approval_events) <> 1
 OR (SELECT count(*) FROM c10_demo.stock_movements) <> 0
 THEN RAISE EXCEPTION 'FAIL: unexpected policy/request/event/stock counts'; END IF;
 IF has_function_privilege('anon',
   'c10_demo.submit_typed_approval_v1(bigint,text,text,text,bigint,jsonb,text)',
   'EXECUTE') OR has_schema_privilege('anon','c10_demo','USAGE')
 THEN RAISE EXCEPTION 'FAIL: anon access leakage'; END IF;
 IF NOT has_function_privilege('service_role',
   'c10_demo.verify_approval_binding_v1(bigint,bigint,text,text,text,bigint,jsonb)',
   'EXECUTE') THEN RAISE EXCEPTION 'FAIL: service binding grant missing'; END IF;
 RAISE NOTICE 'PASS: typed requests, pinned policy, maker/checker, replay, stale, expiry, RLS ACL, zero posting';
END $t$;
