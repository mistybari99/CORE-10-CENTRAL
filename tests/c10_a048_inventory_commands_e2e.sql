\set ON_ERROR_STOP on
\echo C10-A048 direct inventory RPCs denied, guarded command workflow tested
DO $initial$
BEGIN
 IF has_function_privilege('authenticated','c10_demo.post_stock_event(bigint,bigint,numeric,text)','EXECUTE')
 OR has_function_privilege('authenticated','c10_demo.transfer_stock_v1(bigint,bigint,bigint,numeric,text)','EXECUTE')
 OR has_table_privilege('authenticated','c10_demo.inventory_commands_v1','INSERT')
 THEN RAISE EXCEPTION 'A048_DIRECT_WRITE_LEAK'; END IF;
END $initial$;
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
DO $owner$
DECLARE c jsonb; v jsonb; id bigint;
BEGIN
 c:=c10_demo.create_inventory_command_v1(101,'receive',NULL,5001,8001,30,'receive-owner-001');
 IF c->>'status'<>'draft' THEN RAISE EXCEPTION 'A048_CREATE_FAILED'; END IF;
 id:=(c->>'command_id')::bigint;
 IF (c10_demo.create_inventory_command_v1(101,'receive',NULL,5001,8001,30,'receive-owner-001')->>'command_id')::bigint<>id THEN
  RAISE EXCEPTION 'A048_CREATE_REPLAY_FAIL'; END IF;
 v:=c10_demo.advance_inventory_command_v1(id,'confirm',1,'confirm-owner-001');
 IF v->>'status'<>'confirmed' THEN RAISE EXCEPTION 'A048_CONFIRM_FAILED'; END IF;
 v:=c10_demo.advance_inventory_command_v1(id,'post',2,'post-owner-001');
 IF v->>'status'<>'posted' THEN RAISE EXCEPTION 'A048_POST_FAILED'; END IF;
 IF (SELECT on_hand FROM c10_demo.stock_balances_v1 WHERE location_id=5001 AND item_id=8001)<>30
 THEN RAISE EXCEPTION 'A048_BALANCE_INCORRECT'; END IF;
 IF (SELECT count(*) FROM c10_demo.stock_movements WHERE location_id=5001)<>1
 THEN RAISE EXCEPTION 'A048_DOUBLE_POST'; END IF;
 v:=c10_demo.advance_inventory_command_v1(id,'post',2,'post-owner-001');
 IF v->>'replayed'<>'true' OR (SELECT count(*) FROM c10_demo.stock_movements WHERE location_id=5001)<>1
 THEN RAISE EXCEPTION 'A048_POST_REPLAY_FAIL'; END IF;
 BEGIN
  PERFORM c10_demo.create_inventory_command_v1(101,'receive',NULL,5001,8001,40,'receive-owner-001');
  RAISE EXCEPTION 'A048_PAYLOAD_TAMPER_ALLOWED';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'A048_REPLAY_CONFLICT' THEN RAISE; END IF;
 END;
 c:=c10_demo.create_inventory_command_v1(101,'issue',5001,NULL,8001,3,'issue-owner-001');
 id:=(c->>'command_id')::bigint;
 PERFORM c10_demo.advance_inventory_command_v1(id,'confirm',1,'confirm-issue-001');
 PERFORM c10_demo.advance_inventory_command_v1(id,'post',2,'post-issue-001');
 IF (SELECT on_hand FROM c10_demo.stock_balances_v1 WHERE location_id=5001 AND item_id=8001)<>27
 THEN RAISE EXCEPTION 'A048_ISSUE_INCORRECT'; END IF;
 c:=c10_demo.create_inventory_command_v1(101,'transfer',5001,5002,8001,5,'transfer-own-001');
 id:=(c->>'command_id')::bigint;
 PERFORM c10_demo.advance_inventory_command_v1(id,'confirm',1,'confirm-transfer-01');
 PERFORM c10_demo.advance_inventory_command_v1(id,'post',2,'post-transfer-001');
 IF (SELECT on_hand FROM c10_demo.stock_balances_v1 WHERE location_id=5001 AND item_id=8001)<>22
 OR (SELECT on_hand FROM c10_demo.stock_balances_v1 WHERE location_id=5002 AND item_id=8001)<>5
 THEN RAISE EXCEPTION 'A048_TRANSFER_MISMATCH'; END IF;
 BEGIN
  PERFORM c10_demo.create_inventory_command_v1(101,'transfer',5001,5003,8001,1,'bad-foreign-001');
  RAISE EXCEPTION 'A048_CROSS_BUSINESS_ALLOWED';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'A048_CROSS_SCOPE_LOCATION' THEN RAISE; END IF;
 END;
 IF (SELECT count(*) FROM c10_demo.stock_movements WHERE location_id=5001)<>3
 THEN RAISE EXCEPTION 'A048_UNEXPECTED_LEDGER_COUNT'; END IF;
END $owner$;
COMMIT;
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',true);
DO $manager$
BEGIN
 BEGIN
  PERFORM c10_demo.create_inventory_command_v1(101,'adjust_in',NULL,5001,8001,1,'mgr-adjust-001');
  RAISE EXCEPTION 'A048_MANAGER_ADJUSTMENT_ALLOWED';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'A048_PERMISSION_DENIED' THEN RAISE; END IF;
 END;
END $manager$;
ROLLBACK;
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',true);
DO $staff$
DECLARE c jsonb; id bigint;
BEGIN
 c:=c10_demo.create_inventory_command_v1(101,'receive',NULL,5001,8001,1,'staff-receive-01');
 id:=(c->>'command_id')::bigint;
 PERFORM c10_demo.advance_inventory_command_v1(id,'confirm',1,'staff-confirm-01');
 PERFORM c10_demo.advance_inventory_command_v1(id,'post',2,'staff-post-001');
 BEGIN
  PERFORM c10_demo.create_inventory_command_v1(101,'issue',5001,NULL,8001,1,'staff-issue-001');
  RAISE EXCEPTION 'A048_DEFAULT_STAFF_ISSUE_ALLOWED';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'A048_PERMISSION_DENIED' THEN RAISE; END IF;
 END;
END $staff$;
ROLLBACK;
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','77777777-7777-4777-8777-777777777777',true);
DO $other$
BEGIN
 BEGIN
  PERFORM c10_demo.create_inventory_command_v1(101,'receive',NULL,5001,8001,1,'other-tenant-001');
  RAISE EXCEPTION 'A048_CROSS_TENANT_ALLOWED';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'A048_PERMISSION_DENIED' THEN RAISE; END IF;
 END;
END $other$;
ROLLBACK;
\echo PASS A048 canonical stock events, command confirm/post, version/replay, staff scope, foreign tenant, no direct RPC bypass
