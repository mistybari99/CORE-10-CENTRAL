-- Disposable PostgreSQL only. No production or SG execution.
-- Negative assertions require the exact expected authorization/transition error;
-- unrelated SQL failures must fail the test, not count as a denied request.
\set ON_ERROR_STOP on
INSERT INTO c10_demo.approval_requests(tenant_id,business_id,created_by)
VALUES (1,101,'33333333-3333-4333-8333-333333333333'),
       (1,102,'33333333-3333-4333-8333-333333333333'),
       (2,201,'88888888-8888-4888-8888-888888888888');
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
DO $test$
DECLARE e bigint; replay bigint;
BEGIN
 e:=c10_demo.decide_approval(1,'approve','positive_0001');
 replay:=c10_demo.decide_approval(1,'approve','positive_0001');
 IF e IS DISTINCT FROM replay THEN RAISE EXCEPTION 'FAIL: idempotent replay'; END IF;
 BEGIN
  PERFORM c10_demo.decide_approval(1,'reject','positive_0001');
  RAISE EXCEPTION 'FAIL: changed action accepted';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM IS DISTINCT FROM 'approval_idempotency_conflict' THEN RAISE EXCEPTION 'FAIL: changed action accepted (unexpected error: %)', SQLERRM; END IF;
 END;
 BEGIN
  PERFORM c10_demo.decide_approval(2,'approve','crossbiz_0001');
  RAISE EXCEPTION 'FAIL: cross-business accepted';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM IS DISTINCT FROM 'approval_not_authorized' THEN RAISE EXCEPTION 'FAIL: cross-business accepted (unexpected error: %)', SQLERRM; END IF;
 END;
 BEGIN
  PERFORM c10_demo.decide_approval(3,'approve','tenantb_0001');
  RAISE EXCEPTION 'FAIL: cross-tenant accepted';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM IS DISTINCT FROM 'approval_not_authorized' THEN RAISE EXCEPTION 'FAIL: cross-tenant accepted (unexpected error: %)', SQLERRM; END IF;
 END;
END $test$;
SELECT set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',false);
DO $test$
BEGIN
 BEGIN
  PERFORM c10_demo.decide_approval(2,'approve','selfmade_0001');
  RAISE EXCEPTION 'FAIL: maker self approval accepted';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM IS DISTINCT FROM 'approval_not_authorized' THEN RAISE EXCEPTION 'FAIL: maker self approval accepted (unexpected error: %)', SQLERRM; END IF;
 END;
END $test$;
SELECT set_config('request.jwt.claim.sub','66666666-6666-4666-8666-666666666666',false);
DO $test$
BEGIN
 BEGIN
  PERFORM c10_demo.decide_approval(2,'approve','revoked_0001');
  RAISE EXCEPTION 'FAIL: revoked manager accepted';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM IS DISTINCT FROM 'approval_not_authorized' THEN RAISE EXCEPTION 'FAIL: revoked manager accepted (unexpected error: %)', SQLERRM; END IF;
 END;
END $test$;
-- Deny direct mutations even when the caller has authenticated role.
SET ROLE authenticated;
DO $acl$
DECLARE v_sql text;
BEGIN
 FOREACH v_sql IN ARRAY ARRAY[
  'UPDATE c10_demo.approval_requests SET status = ''rejected'' WHERE id = 1',
  'DELETE FROM c10_demo.approval_requests WHERE id = 2',
  'UPDATE c10_demo.approval_events SET action = ''reject'' WHERE request_id = 1',
  'DELETE FROM c10_demo.approval_events WHERE request_id = 1'
 ] LOOP
  BEGIN
   EXECUTE v_sql;
   RAISE EXCEPTION 'FAIL: direct approval write accepted: %', v_sql;
  EXCEPTION WHEN insufficient_privilege THEN
   NULL; -- Only SQLSTATE 42501 is an expected denial.
  END;
 END LOOP;
END $acl$;
RESET ROLE;
DO $acl$
BEGIN
 IF has_function_privilege('anon','c10_demo.decide_approval(bigint,text,text)','EXECUTE')
 THEN RAISE EXCEPTION 'FAIL: anon approval RPC execute grant'; END IF;
 IF has_table_privilege('authenticated','c10_demo.approval_events','INSERT,UPDATE,DELETE')
 THEN RAISE EXCEPTION 'FAIL: authenticated audit write grant'; END IF;
 RAISE NOTICE 'PASS: authenticated direct-write and anon RPC ACL';
END $acl$;
RESET ROLE;
DO $test$
BEGIN
 IF (SELECT count(*) FROM c10_demo.approval_events)<>1 THEN RAISE EXCEPTION 'FAIL: audit event count'; END IF;
 IF (SELECT status FROM c10_demo.approval_requests WHERE id=1)<>'approved' THEN RAISE EXCEPTION 'FAIL: approved state'; END IF;
 IF (SELECT count(*) FROM c10_demo.approval_requests WHERE status='pending')<>2 THEN RAISE EXCEPTION 'FAIL: unauthorized mutation'; END IF;
 RAISE NOTICE 'PASS: approval transaction, replay, cross-business, cross-tenant, self-maker, revoked and audit';
END $test$;
