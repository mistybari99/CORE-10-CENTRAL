\set ON_ERROR_STOP on
\echo A004: after ACL candidate, test anon/auth denials, service, owner-only wrapper
DO $test$
BEGIN
 IF has_function_privilege('anon','public._cost_actual(uuid)','EXECUTE') OR
    has_function_privilege('anon','public._costx_recompute()','EXECUTE') OR
    has_function_privilege('authenticated','public._cost_actual(uuid)','EXECUTE') OR
    has_function_privilege('authenticated','public._costx_recompute()','EXECUTE') THEN
   RAISE EXCEPTION 'untrusted direct execution still granted';
 END IF;
 IF NOT has_function_privilege('service_role','public._cost_actual(uuid)','EXECUTE') OR
    NOT has_function_privilege('service_role','public._costx_recompute()','EXECUTE') THEN
   RAISE EXCEPTION 'service role execution lost';
 END IF;
END
$test$;

BEGIN;
SET LOCAL ROLE anon;
DO $test$
DECLARE accepted boolean;
BEGIN
 accepted:=false;
 BEGIN
  PERFORM cost FROM public._cost_actual('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
  accepted:=true;
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
 IF accepted THEN RAISE EXCEPTION 'ANON_COST_READ_ALLOWED'; END IF;
 accepted:=false;
 BEGIN
  PERFORM public._costx_recompute();
  accepted:=true;
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
 IF accepted THEN RAISE EXCEPTION 'ANON_COST_WRITE_ALLOWED'; END IF;
END
$test$;
ROLLBACK;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',true);
DO $test$
DECLARE accepted boolean;
BEGIN
 accepted:=false;
 BEGIN
  PERFORM cost FROM public._cost_actual('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
  accepted:=true;
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
 IF accepted THEN RAISE EXCEPTION 'AUTH_COST_READ_ALLOWED'; END IF;
 accepted:=false;
 BEGIN
  PERFORM public._costx_recompute();
  accepted:=true;
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
 IF accepted THEN RAISE EXCEPTION 'AUTH_COST_WRITE_ALLOWED'; END IF;
 accepted:=false;
 BEGIN
  PERFORM public._a004_owner_cost_reprice();
  accepted:=true;
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'not_allowed' THEN RAISE; END IF;
 END;
 IF accepted THEN RAISE EXCEPTION 'NON_OWNER_WRAPPER_ALLOWED'; END IF;
END
$test$;
ROLLBACK;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
SELECT (public._a004_owner_cost_reprice() = 1) AS authorized_wrapper_ok \gset
\if :authorized_wrapper_ok
 \echo PASS: authorized synthetic business wrapper still calls protected internal helper
\else
 \quit 1
\endif
ROLLBACK;

-- Trigger-path compatibility: ordinary authenticated writes must still drive the
-- SECURITY DEFINER trigger chain into the (now direct-EXECUTE-restricted) helpers.
BEGIN;
SET LOCAL ROLE authenticated;
INSERT INTO public._a004_settings(key,value) VALUES('cost_extra_on','true');
INSERT INTO public._a004_sales(id,item_id)
  VALUES(1,'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
DO $test$
BEGIN
 IF (SELECT snap_cost FROM public._a004_sales WHERE id=1) IS DISTINCT FROM 25 THEN
   RAISE EXCEPTION 'TRIGGER_PATH_COST_ACTUAL_BROKEN';
 END IF;
END
$test$;
RESET ROLE;
DO $test$
BEGIN
 IF (SELECT recomputes FROM public._a004_cost_fixture
      WHERE item_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')<>1 THEN
   RAISE EXCEPTION 'TRIGGER_PATH_RECOMPUTE_BROKEN';
 END IF;
END
$test$;
ROLLBACK;
\echo PASS: authenticated trigger-driven definer chain still reaches restricted helpers

BEGIN;
SET LOCAL ROLE service_role;
DO $test$
DECLARE v numeric;
BEGIN
 SELECT cost INTO v FROM public._cost_actual(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
 IF v<>25 THEN RAISE EXCEPTION 'service read broken'; END IF;
 IF public._costx_recompute()<>1 THEN
   RAISE EXCEPTION 'service recompute broken';
 END IF;
END
$test$;
ROLLBACK;

DO $test$
BEGIN
 IF (SELECT recomputes FROM public._a004_cost_fixture
   WHERE item_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')<>0 THEN
  RAISE EXCEPTION 'test transaction left business data modified';
 END IF;
END
$test$;

\echo PASS: direct anon/auth access denied, owner-only wrapper and service-role access preserved
\echo LIMIT: synthetic fixture, NOT live API, actual SQL caller/trigger compatibility or a go-live approval
