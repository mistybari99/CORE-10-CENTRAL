\set ON_ERROR_STOP on
-- Characterize the CURRENT fail-closed policy; does not ratify historical pricing.
BEGIN;
\ir fixtures.sql
CREATE SCHEMA np03b_history;
CREATE FUNCTION np03b_history.doc() RETURNS jsonb LANGUAGE sql AS $$ SELECT
 '{"customer_id":7001,"price_list_id":7101,"currency":"BDT","lines":[{"item_id":8101,"variant_id":7301,"uom_id":7201,"quantity":2,"unit_price":300,"discount_percent":0,"tax_percent":0}]}'::jsonb $$;
CREATE FUNCTION np03b_history.expect(q text) RETURNS void LANGUAGE plpgsql AS $$ BEGIN
 BEGIN EXECUTE q;
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM IN('SALES_MASTER_REJECTED','SALES_CURRENCY_MISMATCH','SALES_UOM_PRECISION') THEN RETURN; END IF;
  RAISE;
 END;
 RAISE EXCEPTION 'CHANGED_MASTER_WAS_ACCEPTED';
END $$;
GRANT USAGE ON SCHEMA np03b_history TO authenticated;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA np03b_history TO authenticated;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
SELECT core10.control_set_v1(101,NULL,'sales.order_draft',true,0::smallint,'{}',NULL,false,0,'Synthetic historical policy test','history_draft_enabled');
SELECT core10.control_set_v1(101,NULL,'sales.order_transition',true,0::smallint,'{}',NULL,false,0,'Synthetic historical policy test','history_confirm_enabled');
SELECT core10.control_set_v1(101,NULL,'sales.invoice_draft',true,0::smallint,'{}',NULL,false,0,'Synthetic historical policy test','history_invoice_enabled');
SELECT core10.control_set_v1(101,NULL,'sales.invoice_validate',true,0::smallint,'{}',NULL,false,0,'Synthetic historical policy test','history_validate_enabled');
SELECT core10.save_sales_order_v1(101,1001,NULL,0,np03b_history.doc(),'history_source_order') AS r \gset
SELECT (:'r'::jsonb->>'order_id')::bigint AS source \gset
SELECT core10.transition_sales_order_v1(101,1001,:source,'confirm',1,NULL,'history_source_confirm');
SELECT core10.save_sales_invoice_draft_v1(101,1001,NULL,0,:source,2,NULL,'Synthetic','history_invoice_saved') AS i \gset
SELECT (:'i'::jsonb->>'invoice_id')::bigint AS invoice \gset
RESET ROLE;
-- Each change is subtransactional. Source/read snapshots remain readable and
-- unchanged even though creation/validation against changed Master must deny.
CREATE FUNCTION np03b_history.changed(q text,o bigint,i bigint) RETURNS void LANGUAGE plpgsql AS $$
DECLARE before_source jsonb; after_source jsonb; before_invoice jsonb; after_invoice jsonb;
BEGIN
 before_source:=core10.read_sales_orders_v1(101,1001,o);
 before_invoice:=core10.read_sales_invoice_drafts_v1(101,1001,i)->'invoices';
 BEGIN
  EXECUTE q;
  SET LOCAL ROLE authenticated;
  PERFORM np03b_history.expect(format('SELECT core10.validate_sales_invoice_draft_v1(101,1001,%s,1,NULL,''history_changed_validate'')',i));
  after_source:=core10.read_sales_orders_v1(101,1001,o);
  after_invoice:=core10.read_sales_invoice_drafts_v1(101,1001,i)->'invoices';
  RESET ROLE;
  IF after_source IS DISTINCT FROM before_source OR after_invoice IS DISTINCT FROM before_invoice
  THEN RAISE EXCEPTION 'HISTORICAL_SOURCE_REWRITTEN'; END IF;
  RAISE EXCEPTION 'RESTORE_CATALOG';
 EXCEPTION WHEN SQLSTATE 'P0001' THEN IF SQLERRM<>'RESTORE_CATALOG' THEN RAISE; END IF; END;
END $$;
SELECT np03b_history.changed(change,:source,:invoice) FROM (VALUES
 ('UPDATE core10.master_parties_v1 SET status=''inactive'' WHERE id=7001'),
 ('UPDATE core10.items SET status=''inactive'' WHERE id=8101'),
 ('UPDATE core10.master_item_variants_v1 SET status=''inactive'' WHERE id=7301'),
 ('UPDATE core10.master_uoms_v1 SET active=false WHERE id=7201'),
 ('UPDATE core10.master_price_lists_v1 SET status=''inactive'' WHERE id=7101'),
 ('UPDATE core10.master_price_list_items_v1 SET unit_price=301 WHERE price_list_id=7101'),
 ('UPDATE core10.master_price_lists_v1 SET currency=''USD'' WHERE id=7101'),
 ('UPDATE core10.master_price_list_items_v1 SET uom_id=7202 WHERE price_list_id=7101')
) changes(change);
-- A referenced party can be retired. Its canonical identity remains protected.
DO $$ BEGIN
 BEGIN
  DELETE FROM core10.master_parties_v1 WHERE id=7001;
  RAISE EXCEPTION 'HISTORICAL_MASTER_DELETE_ACCEPTED';
 EXCEPTION WHEN foreign_key_violation THEN NULL; END;
END $$;
DO $$ BEGIN
 IF EXISTS(SELECT FROM core10.sales_invoice_commands_v1 WHERE request_key='history_changed_validate')
 THEN RAISE EXCEPTION 'FAILED_VALIDATION_RECEIPT_LEAK'; END IF;
END $$;
ROLLBACK;
\echo NP03B_CURRENT_MASTER_FAIL_CLOSED_8_CASES_AND_UNCHANGED_SNAPSHOTS_OK
\echo NP03B_REFERENCED_MASTER_PARTY_DELETE_DENIED
