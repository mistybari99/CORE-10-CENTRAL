-- A draft and its canonical Audit evidence are business history, not disposable
-- migration scaffolding. Never erase persisted invoices or used Control history.
DO $$ BEGIN
 IF EXISTS(SELECT FROM core10.sales_invoice_drafts_v1)
 THEN RAISE EXCEPTION 'SALES_INVOICE_ROLLBACK_HAS_HISTORY'; END IF;
END $$;
DELETE FROM core10.control_rpc_map_v1 WHERE rpc_name IN('save_sales_invoice_draft_v1','validate_sales_invoice_draft_v1');
DELETE FROM core10.control_catalog_v1 WHERE feature_key IN('sales.invoice_draft','sales.invoice_validate');
DROP FUNCTION core10.read_sales_invoice_drafts_v1(bigint,bigint,bigint);
DROP FUNCTION core10.validate_sales_invoice_draft_v1(bigint,bigint,bigint,bigint,bigint,text);
DROP FUNCTION core10.save_sales_invoice_draft_v1(bigint,bigint,bigint,bigint,bigint,bigint,jsonb,text,text);
DROP FUNCTION core10._sales_invoice_approval_payload_v1(core10.sales_invoice_drafts_v1,integer);
DROP FUNCTION core10._sales_invoice_document_v1(jsonb,jsonb,jsonb);
DROP FUNCTION core10._sales_invoice_receipt_v1(core10.sales_invoice_drafts_v1);
DROP TABLE core10.sales_invoice_commands_v1;
DROP TABLE core10.sales_invoice_draft_lines_v1;
DROP TABLE core10.sales_invoice_drafts_v1;
DROP FUNCTION core10._sales_invoice_source_immutable_v1();
