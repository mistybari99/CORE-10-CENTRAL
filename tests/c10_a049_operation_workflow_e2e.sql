\set ON_ERROR_STOP on
\echo A049 purchase -> stock -> sale, second-business independence, production remains preview
DO $s$
BEGIN
 IF has_table_privilege('authenticated','c10_demo.operation_orders_v1','INSERT') OR
 has_table_privilege('authenticated','c10_demo.operation_profiles_v1','UPDATE')
 THEN RAISE EXCEPTION 'A049_DIRECT_DML_ALLOWED'; END IF;
END; $s$;
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
DO $owner$
DECLARE c jsonb; id bigint; r jsonb; bs bigint;
BEGIN
 c:=c10_demo.create_operation_order_v1(101,5001,8001,'purchase_receive',60,70,'purchase-order-A','buy-demo-001');
 id:=(c->>'order_id')::bigint;
 IF id IS NULL OR c->>'status'<>'draft' THEN RAISE EXCEPTION 'A049_PURCHASE_DRAFT_FAILED'; END IF;
 r:=c10_demo.advance_operation_order_v1(id,'confirm',1,'confirm-buy-001');
 IF r->>'status'<>'confirmed' THEN RAISE EXCEPTION 'A049_PURCHASE_CONFIRM_FAILED'; END IF;
 r:=c10_demo.advance_operation_order_v1(id,'post',2,'post-buy-001');
 IF r->>'status'<>'posted' OR r->>'financial_posted'<>'false'
 THEN RAISE EXCEPTION 'A049_PURCHASE_POST_FAILED'; END IF;
 IF (SELECT on_hand FROM c10_demo.stock_balances_v1 WHERE location_id=5001 AND item_id=8001)<>60
 THEN RAISE EXCEPTION 'A049_PURCHASE_BALANCE'; END IF;
 r:=c10_demo.advance_operation_order_v1(id,'post',2,'post-buy-001');
 IF r->>'replayed'<>'true' OR (SELECT count(*) FROM c10_demo.stock_movements WHERE location_id=5001)<>1
 THEN RAISE EXCEPTION 'A049_DOUBLE_RECEIVE'; END IF;
 c:=c10_demo.create_operation_order_v1(101,5001,8001,'sale_issue',12,125,'sale-order-A','sale-demo-001');
 id:=(c->>'order_id')::bigint;
 PERFORM c10_demo.advance_operation_order_v1(id,'confirm',1,'confirm-sale-001');
 PERFORM c10_demo.advance_operation_order_v1(id,'post',2,'post-sale-001');
 IF (SELECT on_hand FROM c10_demo.stock_balances_v1 WHERE location_id=5001 AND item_id=8001)<>48
 THEN RAISE EXCEPTION 'A049_SALE_STOCK_BALANCE'; END IF;
 IF jsonb_array_length(c10_demo.read_operation_overview_v1(101)->'items')<>2
 THEN RAISE EXCEPTION 'A049_OWNER_OVERVIEW'; END IF;
 c:=c10_demo.create_operation_order_v1(102,5003,8002,'purchase_receive',20,45,'paint-demo','paint-buy-001');
 bs:=(c->>'order_id')::bigint;
 PERFORM c10_demo.advance_operation_order_v1(bs,'confirm',1,'paint-conf-001');
 PERFORM c10_demo.advance_operation_order_v1(bs,'post',2,'paint-post-001');
 IF (SELECT on_hand FROM c10_demo.stock_balances_v1 WHERE location_id=5003 AND item_id=8002)<>20 OR
    (SELECT on_hand FROM c10_demo.stock_balances_v1 WHERE location_id=5001 AND item_id=8001)<>48
 THEN RAISE EXCEPTION 'A049_BUSINESS_ISOLATION'; END IF;
 c:=c10_demo.create_operation_order_v1(101,5002,8001,'production_plan',1,100,NULL,'prod-plan-001');
 id:=(c->>'order_id')::bigint;
 PERFORM c10_demo.advance_operation_order_v1(id,'confirm',1,'prod-conf-001');
 BEGIN
  PERFORM c10_demo.advance_operation_order_v1(id,'post',2,'prod-post-001');
  RAISE EXCEPTION 'A049_FAKE_PRODUCTION_POST';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'A049_PRODUCTION_REQUIRES_A027_BOM' THEN RAISE; END IF;
 END;
 IF (SELECT count(*) FROM c10_demo.stock_movements WHERE location_id=5002)<>0
 THEN RAISE EXCEPTION 'A049_UNAUTHORIZED_PRODUCTION_STOCK'; END IF;
END $owner$;
COMMIT;
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',true);
DO $staff$
BEGIN
 BEGIN
  PERFORM c10_demo.create_operation_order_v1(101,5001,8001,'sale_issue',1,125,NULL,'staff-sale-001');
  RAISE EXCEPTION 'A049_UNAPPROVED_STAFF_SALE';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'A049_ORDER_DENIED' THEN RAISE; END IF;
 END;
END $staff$;
ROLLBACK;
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','77777777-7777-4777-8777-777777777777',true);
DO $tenant_b$
BEGIN
 BEGIN
  PERFORM c10_demo.read_operation_overview_v1(101);
  RAISE EXCEPTION 'A049_FOREIGN_READ_ALLOWED';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'A049_READ_DENIED' THEN RAISE; END IF;
 END;
END $tenant_b$;
ROLLBACK;
\echo PASS A049 isolated purchase/receive/sale/cost-preview + two-business independence; production & accounting never falsely posted
