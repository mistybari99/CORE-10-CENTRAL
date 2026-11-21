-- Disposable actual0304 browser records; synthetic identities/catalog/prices.
\set ON_ERROR_STOP on
\ir ui-seed.sql
SELECT core10.control_set_v1(101,NULL,'sales.invoice_draft',true,0::smallint,'{"allow_partial_quantities":true,"max_discount_percent":5}',NULL,false,0,'Synthetic invoice browser fixture','ui_invoice_draft_on');
SELECT core10.control_set_v1(101,NULL,'sales.invoice_validate',true,0::smallint,'{}',NULL,false,0,'Synthetic invoice browser fixture','ui_invoice_validate_on');
DO $$ DECLARE r jsonb; n integer; BEGIN
 FOR n IN 1..3 LOOP
  r:=core10.save_sales_order_v1(101,1001,NULL,0,'{"customer_id":7001,"price_list_id":7101,"currency":"BDT","lines":[{"item_id":8101,"uom_id":7201,"quantity":2,"unit_price":300,"discount_percent":0,"tax_percent":0},{"item_id":8104,"uom_id":7201,"quantity":1,"unit_price":1200,"discount_percent":0,"tax_percent":0}]}','ui_invoice_source_'||n);
  PERFORM core10.transition_sales_order_v1(101,1001,(r->>'order_id')::bigint,'confirm',1,NULL,'ui_invoice_confirm_'||n);
 END LOOP;
END $$;
