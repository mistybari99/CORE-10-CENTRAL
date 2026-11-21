\set ON_ERROR_STOP on
BEGIN;
\ir fixtures.sql
CREATE SCHEMA np03b_master_test;
GRANT USAGE ON SCHEMA np03b_master_test TO authenticated;
CREATE FUNCTION np03b_master_test.doc() RETURNS jsonb LANGUAGE sql AS $$ SELECT
 '{"customer_id":7001,"price_list_id":7101,"currency":"BDT","lines":[{"item_id":8101,"uom_id":7201,"quantity":2,"unit_price":300,"discount_percent":0,"tax_percent":0}]}'::jsonb $$;
CREATE FUNCTION np03b_master_test.expect(d jsonb,e text,k text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 BEGIN PERFORM core10.save_sales_order_v1(101,1001,NULL,0,d,k);
 EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE e||'%' THEN RETURN; END IF; RAISE; END;
 RAISE EXCEPTION 'EXPECTED_FAILURE:%',e;
END $$;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA np03b_master_test TO authenticated;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
SELECT core10.control_set_v1(101,NULL,'sales.order_draft',true,0::smallint,'{}',NULL,false,0,'Synthetic Master integration','master_enable_draft');
SELECT core10.control_set_v1(101,NULL,'sales.order_transition',true,0::smallint,'{}',NULL,false,0,'Synthetic Master integration','master_enable_transition');
SELECT core10.save_sales_order_v1(101,1001,NULL,0,np03b_master_test.doc(),'master_valid_01') AS saved \gset
SELECT set_config('np03b.test_order',(:'saved'::jsonb->>'order_id'),true);
SELECT np03b_master_test.expect(jsonb_set(np03b_master_test.doc(),'{currency}','"USD"'),'SALES_CURRENCY_MISMATCH','master_currency_01');
SELECT np03b_master_test.expect(jsonb_set(np03b_master_test.doc(),'{lines,0,quantity}','1.5'),'SALES_UOM_PRECISION','master_precision_01');
SELECT np03b_master_test.expect(jsonb_set(np03b_master_test.doc(),'{customer_id}','7002'),'SALES_MASTER_REJECTED','master_supplier_01');
SELECT np03b_master_test.expect(jsonb_set(np03b_master_test.doc(),'{customer_id}','7003'),'SALES_MASTER_REJECTED','master_foreign_01');
SELECT np03b_master_test.expect(jsonb_set(np03b_master_test.doc(),'{customer_id}','7004'),'SALES_MASTER_REJECTED','master_inactive_01');
SELECT np03b_master_test.expect(jsonb_set(np03b_master_test.doc(),'{lines,0,variant_id}','7302'),'SALES_MASTER_REJECTED','master_variant_01');
-- Actual canonical readers have no unauthenticated/foreign-business access.
DO $$ BEGIN
 IF has_function_privilege('anon','core10.master_list_uoms_v1(bigint)','EXECUTE')
 THEN RAISE EXCEPTION 'ANON_MASTER_READER'; END IF;
 BEGIN PERFORM core10.master_list_uoms_v1(201); RAISE EXCEPTION 'FOREIGN_MASTER_ALLOWED';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'MASTER_SCOPE' THEN RAISE; END IF; END;
END $$;
RESET ROLE;
-- Save -> canonical price changes -> confirm must fail atomically.
UPDATE core10.master_price_list_items_v1 SET unit_price=301 WHERE price_list_id=7101 AND item_id=8101;
SET LOCAL ROLE authenticated;
DO $$ DECLARE o bigint; BEGIN
 o:=current_setting('np03b.test_order')::bigint;
 BEGIN PERFORM core10.transition_sales_order_v1(101,1001,o,'confirm',1,NULL,'master_confirm_changed');
 EXCEPTION WHEN OTHERS THEN IF SQLERRM='SALES_MASTER_REJECTED' THEN RETURN; END IF; RAISE; END;
 RAISE EXCEPTION 'CHANGED_PRICE_CONFIRM_ALLOWED';
END $$;
RESET ROLE;
UPDATE core10.master_price_list_items_v1 SET unit_price=300 WHERE price_list_id=7101 AND item_id=8101;
UPDATE core10.master_price_lists_v1 SET effective_to=current_date-1 WHERE id=7101;
SET LOCAL ROLE authenticated;
SELECT np03b_master_test.expect(np03b_master_test.doc(),'SALES_MASTER_REJECTED','master_expired_01');
RESET ROLE;
UPDATE core10.master_price_lists_v1 SET effective_to=NULL,site_id=1002 WHERE id=7101;
SET LOCAL ROLE authenticated;
SELECT np03b_master_test.expect(np03b_master_test.doc(),'SALES_MASTER_REJECTED','master_wrongsite_01');
RESET ROLE;
UPDATE core10.master_price_lists_v1 SET site_id=NULL WHERE id=7101;
UPDATE core10.items SET status='inactive' WHERE id=8101;
SET LOCAL ROLE authenticated;
SELECT np03b_master_test.expect(np03b_master_test.doc(),'SALES_MASTER_REJECTED','master_itemoff_01');
RESET ROLE;
UPDATE core10.items SET status='active' WHERE id=8101;
UPDATE core10.master_uoms_v1 SET active=false WHERE id=7201;
SET LOCAL ROLE authenticated;
SELECT np03b_master_test.expect(np03b_master_test.doc(),'SALES_MASTER_REJECTED','master_uomoff_01');
RESET ROLE;
UPDATE core10.master_uoms_v1 SET active=true WHERE id=7201;
UPDATE core10.master_price_list_items_v1 SET active=false WHERE price_list_id=7101 AND item_id=8101;
SET LOCAL ROLE authenticated;
SELECT np03b_master_test.expect(np03b_master_test.doc(),'SALES_MASTER_REJECTED','master_priceoff_01');
RESET ROLE;
UPDATE core10.master_price_list_items_v1 SET active=true WHERE price_list_id=7101 AND item_id=8101;
-- Canonical tier selection: no Sales-side duplicate pricing calculation.
INSERT INTO core10.master_price_list_items_v1(tenant_id,business_id,price_list_id,item_id,uom_id,min_quantity,unit_price)
VALUES(1,101,7101,8101,7201,10,280);
SET LOCAL ROLE authenticated;
SELECT np03b_master_test.expect(jsonb_set(np03b_master_test.doc(),'{lines,0,quantity}','10'),'SALES_MASTER_REJECTED','master_wrongtier_01');
SELECT core10.save_sales_order_v1(101,1001,NULL,0,jsonb_set(jsonb_set(np03b_master_test.doc(),'{lines,0,quantity}','10'),'{lines,0,unit_price}','280'),'master_tier_valid');
RESET ROLE;
-- Unit-price precision belongs to Master (4 places); amount rounds separately.
UPDATE core10.master_price_list_items_v1 SET unit_price=300.1234 WHERE price_list_id=7101 AND item_id=8101 AND min_quantity=0;
SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb; BEGIN
 r:=core10.save_sales_order_v1(101,1001,NULL,0,jsonb_set(np03b_master_test.doc(),'{lines,0,unit_price}','300.1234'),'master_price4_valid');
 IF (r->>'total')::numeric<>600.25 THEN RAISE EXCEPTION 'PRICE_AMOUNT_PRECISION'; END IF;
END $$;
SELECT core10.control_set_v1(101,NULL,'sales.order_draft',true,0::smallint,'{"tax_enabled":true}',NULL,false,1,'Synthetic tax contract absent','master_enable_tax');
SELECT np03b_master_test.expect(jsonb_set(jsonb_set(np03b_master_test.doc(),'{lines,0,unit_price}','300.1234'),'{lines,0,tax_percent}','5'),'NOT_CONNECTED:MASTER_SALES_TAX','master_tax_fence_01');
RESET ROLE;
-- Mass quantities follow canonical UOM decimals, rather than a blanket integer rule.
UPDATE core10.items SET base_uom_id=7202 WHERE id=8101;
UPDATE core10.master_price_list_items_v1 SET uom_id=7202,unit_price=300 WHERE price_list_id=7101 AND item_id=8101;
SET LOCAL ROLE authenticated;
SELECT core10.save_sales_order_v1(101,1001,NULL,0,jsonb_set(jsonb_set(np03b_master_test.doc(),'{lines,0,uom_id}','7202'),'{lines,0,quantity}','0.125'),'master_mass_valid');
SELECT np03b_master_test.expect(jsonb_set(jsonb_set(np03b_master_test.doc(),'{lines,0,uom_id}','7202'),'{lines,0,quantity}','0.0001'),'SALES_UOM_PRECISION','master_mass_precision');
RESET ROLE;
DO $$ BEGIN
 IF EXISTS(SELECT FROM core10.sales_orders_v1 o WHERE o.status<>'draft')
 OR EXISTS(SELECT FROM core10.sales_order_commands_v1 WHERE request_key='master_confirm_changed')
 THEN RAISE EXCEPTION 'FAILED_CONFIRM_MUTATED_STATE'; END IF;
 IF has_function_privilege('authenticated','core10._sales_validate_v1(bigint,bigint,jsonb,jsonb)','EXECUTE')
 THEN RAISE EXCEPTION 'INTERNAL_HELPER_EXPOSED'; END IF;
END $$;
-- Missing-reader boundary without replacing or dropping canonical code.
ALTER FUNCTION core10.master_get_price_list_v1(bigint,bigint,integer,bigint) RENAME TO np03b_absent_price_reader;
SET LOCAL ROLE authenticated;
SELECT np03b_master_test.expect(jsonb_set(np03b_master_test.doc(),'{lines,0,uom_id}','7202'),'NOT_CONNECTED:MASTER_SALES_READERS','master_missing_reader');
RESET ROLE;
ROLLBACK;
\echo NP03B_CANONICAL_MASTER_INTEGRATION_OK
