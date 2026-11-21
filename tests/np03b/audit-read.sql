\set ON_ERROR_STOP on
BEGIN;
\ir fixtures.sql
CREATE SCHEMA np03b_audit_test;
GRANT USAGE ON SCHEMA np03b_audit_test TO authenticated,anon;
CREATE FUNCTION np03b_audit_test.expect(q text,e text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN BEGIN EXECUTE q; EXCEPTION WHEN OTHERS THEN
 IF SQLERRM LIKE e||'%' THEN RETURN; END IF; RAISE EXCEPTION 'WRONG_ERROR:%',SQLERRM;
END; RAISE EXCEPTION 'NO_ERROR:%',e; END $$;
GRANT EXECUTE ON FUNCTION np03b_audit_test.expect(text,text) TO authenticated,anon;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
SELECT core10.control_set_v1(101,NULL,'sales.order_draft',true,0::smallint,'{}',NULL,false,0,'Synthetic audit test','audit_enable_draft');
SELECT core10.control_set_v1(101,NULL,'sales.order_transition',true,0::smallint,'{}',NULL,false,0,'Synthetic audit test','audit_enable_transition');
DO $$ DECLARE d jsonb; o bigint; a jsonb; BEGIN
 d:='{"customer_id":7001,"price_list_id":7101,"currency":"BDT","lines":[{"item_id":8101,"uom_id":7201,"quantity":1,"unit_price":300,"discount_percent":0,"tax_percent":0}]}';
 o:=(core10.save_sales_order_v1(101,1001,NULL,0,d,'audit_order_01')->>'order_id')::bigint;
 PERFORM core10.transition_sales_order_v1(101,1001,o,'confirm',1,NULL,'audit_confirm_01');
 a:=core10.read_sales_order_audit_v1(101,1001,o);
 IF a->>'order_id'<>o::text OR jsonb_array_length(a->'items')<>2
    OR a->'items'->0->>'action'<>'sales.confirm' OR a->'items'->1->>'action'<>'sales.draft_saved'
    OR EXISTS(SELECT 1 FROM jsonb_array_elements(a->'items') x
      WHERE x->>'business_id'<>'101' OR x->>'site_id'<>'1001' OR x->>'order_id'<>o::text)
 THEN RAISE EXCEPTION 'AUDIT_PROJECTION_INVALID'; END IF;
 PERFORM np03b_audit_test.expect(format('SELECT core10.read_sales_order_audit_v1(101,1002,%s)',o),'SALES_ORDER_NOT_FOUND');
 PERFORM np03b_audit_test.expect(format('SELECT core10.read_sales_order_audit_v1(102,1003,%s)',o),'SALES_ORDER_NOT_FOUND');
 PERFORM np03b_audit_test.expect(format('SELECT core10.read_sales_order_audit_v1(101,2001,%s)',o),'SALES_SCOPE_DENIED');
 PERFORM np03b_audit_test.expect('SELECT core10.read_sales_order_audit_v1(101,1001,NULL)','SALES_ORDER_NOT_FOUND');
 IF (core10.verify_canonical_audit_v1(101)->>'ok')::boolean IS NOT TRUE THEN RAISE EXCEPTION 'AUDIT_INTEGRITY'; END IF;
END $$;
SELECT set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',true);
SELECT np03b_audit_test.expect('SELECT core10.read_sales_order_audit_v1(101,1001,1)','SALES_SCOPE_DENIED');
SELECT set_config('request.jwt.claim.sub','77777777-7777-4777-8777-777777777777',true);
SELECT np03b_audit_test.expect('SELECT core10.read_sales_order_audit_v1(101,1001,1)','SALES_SCOPE_DENIED');
SELECT set_config('request.jwt.claim.sub','66666666-6666-4666-8666-666666666666',true);
SELECT np03b_audit_test.expect('SELECT core10.read_sales_order_audit_v1(101,1001,1)','SALES_SCOPE_DENIED');
SELECT set_config('request.jwt.claim.sub','',true);
SELECT np03b_audit_test.expect('SELECT core10.read_sales_order_audit_v1(101,1001,1)','SALES_SCOPE_DENIED');
SET LOCAL ROLE anon;
SELECT np03b_audit_test.expect('SELECT core10.read_sales_order_audit_v1(101,1001,1)','permission denied');
RESET ROLE;
DO $$ BEGIN IF (SELECT provolatile FROM pg_proc WHERE oid='core10.read_sales_order_audit_v1(bigint,bigint,bigint)'::regprocedure)<>'s'
 THEN RAISE EXCEPTION 'AUDIT_READER_NOT_STABLE'; END IF; END $$;
ROLLBACK;
\echo NP03B_SCOPED_CANONICAL_AUDIT_READ_OK
