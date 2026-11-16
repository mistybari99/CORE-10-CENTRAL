-- B-020 / 0017: unsigned/ungoverned new RPCs must be closed to authenticated callers.
-- Run after all disposable migrations have been applied. Fail before release.
\set ON_ERROR_STOP on
DO $np01$
DECLARE sig text;
BEGIN
 FOR sig IN SELECT unnest(ARRAY[
  'core10.assess_approval_threshold_v1(bigint,jsonb)',
  'core10.assess_current_approval_threshold_v1(bigint,text,text,jsonb)',
  'core10.configure_approval_threshold_v1(bigint,text,text,numeric,integer,text)',
  'core10.request_approval_exception_v1(bigint,text,text,integer,text)',
  'core10.decide_approval_exception_v1(bigint,text,text)',
  'core10.withdraw_approval_exception_v1(bigint,text)'
 ]) LOOP
  IF has_function_privilege('authenticated',sig,'EXECUTE') THEN
   RAISE EXCEPTION 'NP01_UNBOUND_RPC_EXPOSED:%',sig;
  END IF;
 END LOOP;
 IF EXISTS (SELECT 1 FROM core10.control_rpc_map_v1
   WHERE rpc_name IN ('assess_approval_threshold_v1','assess_current_approval_threshold_v1',
    'configure_approval_threshold_v1','request_approval_exception_v1',
    'decide_approval_exception_v1','withdraw_approval_exception_v1')
    AND status='enforced') THEN
    RAISE EXCEPTION 'NP01_UNBOUND_RPC_FALSE_ENFORCEMENT';
 END IF;
 RAISE NOTICE 'NP01_UNBOUND_RPC_FENCE_OK';
END $np01$;
