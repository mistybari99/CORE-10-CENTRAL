\set ON_ERROR_STOP on
-- One database, one A018 identity, one canonical stock ledger. Real RPC calls
-- under authenticated role; synthetic claims are explicitly not GoTrue sessions.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
DO $chain$
DECLARE purchase jsonb; sale jsonb; response jsonb; portfolio jsonb; workforce jsonb;
 order_id bigint; movements_before bigint; row jsonb;
BEGIN
 purchase:=core10.create_operation_order_v1(101,5001,8001,'purchase_receive',60,70,'PREVIEW-PO-001','preview-buy-0001');
 order_id:=(purchase->>'order_id')::bigint;
 PERFORM core10.advance_operation_order_v1(order_id,'confirm',1,'preview-buy-confirm');
 response:=core10.advance_operation_order_v1(order_id,'post',2,'preview-buy-post');
 IF response->>'financial_posted' IS DISTINCT FROM 'false' OR response->>'certified_cogs' IS DISTINCT FROM 'false'
 THEN RAISE EXCEPTION 'preview misrepresented financial certification'; END IF;
 PERFORM core10.advance_operation_order_v1(order_id,'post',2,'preview-buy-post');
 IF (SELECT on_hand FROM core10.stock_balances_v1 WHERE location_id=5001 AND item_id=8001) IS DISTINCT FROM 60::numeric
 THEN RAISE EXCEPTION 'A049 purchase did not reach A018/A048 canonical stock exactly once'; END IF;
 sale:=core10.create_operation_order_v1(101,5001,8001,'sale_issue',12,125,'PREVIEW-SO-001','preview-sale-0001');
 order_id:=(sale->>'order_id')::bigint;
 PERFORM core10.advance_operation_order_v1(order_id,'confirm',1,'preview-sale-confirm');
 PERFORM core10.advance_operation_order_v1(order_id,'post',2,'preview-sale-post');
 IF (SELECT on_hand FROM core10.stock_balances_v1 WHERE location_id=5001 AND item_id=8001) IS DISTINCT FROM 48::numeric
 THEN RAISE EXCEPTION 'canonical receipt minus sale failed'; END IF;
 portfolio:=core10.read_portfolio_workspace_v1();
 SELECT x INTO row FROM jsonb_array_elements(portfolio->'businesses') x WHERE x->>'business_id'='101';
 IF row IS NULL OR row->>'operations_count' IS DISTINCT FROM '2' OR
    jsonb_array_length(portfolio->'businesses')<>2
 THEN RAISE EXCEPTION 'A050 portfolio lost A049 operations or tenant boundary'; END IF;
 SELECT count(*) INTO movements_before FROM core10.stock_movements;
 workforce:=core10.a053_read_portfolio_workforce_v1('2026-11-01');
 IF workforce->>'state' IS DISTINCT FROM 'CONNECTED' OR
    workforce->'contracts'->>'A050_portfolio' IS DISTINCT FROM 'CONNECTED' OR
    workforce->'contracts'->>'A051_workforce' IS DISTINCT FROM 'CONNECTED' OR
    workforce->'contracts'->>'A054_payment_tracking' IS DISTINCT FROM 'CONNECTED' OR
    workforce->>'money_movement' IS DISTINCT FROM 'false' OR
    workforce->>'ledger_posted' IS DISTINCT FROM 'false'
 THEN RAISE EXCEPTION 'A050/A051/A053/A054 contract failed: %',workforce; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(workforce->'businesses') x WHERE x->>'state'<>'OK')
 THEN RAISE EXCEPTION 'workforce adapter hid a combined-schema failure: %',workforce; END IF;
 PERFORM core10.a056_set_settings_v1(101,true,NULL,0,'preview-crm-enable','Synthetic preview CRM integration');
 response:=core10.a056_create_customer_v1(101,1001,'person','Synthetic Preview Customer',NULL,'preview@example.test',NULL,NULL,'preview-customer-01');
 IF response->>'customer_id' IS NULL THEN RAISE EXCEPTION 'CRM did not reuse canonical business/site identity'; END IF;
 IF (SELECT count(*) FROM core10.stock_movements)<>movements_before
 THEN RAISE EXCEPTION 'workforce/CRM read and customer creation unexpectedly changed stock'; END IF;
END $chain$;
-- The same foreign-tenant actor must be excluded by every adapter after all
-- migrations (including permission lockdown/hooks) have been applied together.
SELECT set_config('request.jwt.claim.sub','77777777-7777-4777-8777-777777777777',true);
DO $foreign$
DECLARE r jsonb;
BEGIN
 r:=core10.read_portfolio_workspace_v1();
 IF jsonb_array_length(r->'businesses')<>1 OR r->'businesses'->0->>'business_id'<>'201'
 THEN RAISE EXCEPTION 'portfolio foreign tenant leak'; END IF;
 r:=core10.a053_read_portfolio_workforce_v1('2026-11-01');
 IF jsonb_array_length(r->'businesses')<>1 OR r->'businesses'->0->>'business_id'<>'201'
 THEN RAISE EXCEPTION 'workforce foreign tenant leak'; END IF;
 IF EXISTS(SELECT 1 FROM core10.a056_customers WHERE business_id=101)
 THEN RAISE EXCEPTION 'CRM direct RLS read leaked foreign customer'; END IF;
 BEGIN
  PERFORM core10.read_operation_overview_v1(101);
  RAISE EXCEPTION 'foreign operations accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'A049_READ_DENIED' THEN RAISE; END IF; END;
 BEGIN
  PERFORM core10.a056_list_customers_v1(101);
  RAISE EXCEPTION 'foreign CRM accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'A056_DENIED' THEN RAISE; END IF; END;
 BEGIN
  PERFORM core10.am_list_catalog_v1(101);
  RAISE EXCEPTION 'foreign asset catalogue accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM NOT LIKE 'am_%denied%' THEN RAISE; END IF; END;
END $foreign$;
ROLLBACK;
-- Introspect persistent grants as postgres, outside the role simulation.
DO $grants$
BEGIN
 IF has_table_privilege('authenticated','core10.operation_orders_v1','INSERT') OR
    has_table_privilege('authenticated','core10.wf_employees','UPDATE') OR
    has_table_privilege('authenticated','core10.a056_customers','INSERT') OR
    has_function_privilege('authenticated','core10.a056_convert_core(bigint,integer,bigint,text,boolean)','EXECUTE')
 THEN RAISE EXCEPTION 'combined migrations widened direct table/helper authority'; END IF;
END $grants$;
\echo PASS actual A049 purchase/sale -> A048/A018 stock -> A050 portfolio -> A053/A051/A054 workforce; CRM identity; tenant isolation; immutable authority
