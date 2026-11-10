\set ON_ERROR_STOP on
\echo A004: verify synthetic pre-patch direct privileges (not a production exploit)
DO $test$
BEGIN
 IF NOT has_function_privilege('anon','public._cost_actual(uuid)','EXECUTE') OR
    NOT has_function_privilege('authenticated','public._costx_recompute()','EXECUTE') THEN
   RAISE EXCEPTION 'synthetic pre-patch ACL mismatch';
 END IF;
 IF has_table_privilege('anon','public._a004_cost_fixture','SELECT') THEN
   RAISE EXCEPTION 'fixture should not have direct table privileges';
 END IF;
END
$test$;
BEGIN;
SET LOCAL ROLE anon;
DO $test$
DECLARE v numeric;
BEGIN
 SELECT cost INTO v FROM public._cost_actual(
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
 IF v<>25 THEN RAISE EXCEPTION 'synthetic pre-patch cost read did not reproduce'; END IF;
 IF public._costx_recompute()<>1 THEN
   RAISE EXCEPTION 'synthetic pre-patch cost write did not reproduce';
 END IF;
END
$test$;
ROLLBACK;
\echo PASS: disposable fixture demonstrates publicly executable direct cost read/write path before candidate ACL
