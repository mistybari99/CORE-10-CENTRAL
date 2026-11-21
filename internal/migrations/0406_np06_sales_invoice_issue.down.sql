-- NP06 0406: fail closed when Sales issue/Money/AR/Control history exists.
DO $guard$ BEGIN
 IF EXISTS(SELECT 1 FROM core10.finance_sales_issues_v1)
 OR EXISTS(SELECT 1 FROM core10.finance_journals_v1
  WHERE source_domain='sales_invoice')
 OR EXISTS(SELECT 1 FROM core10.canonical_audit_events_v1
  WHERE action='sales.invoice_issued')
 OR EXISTS(SELECT 1 FROM core10.control_setting_versions_v1
  WHERE feature_key='finance.sales_invoice_issue')
 OR EXISTS(SELECT 1 FROM core10.control_overrides_v1
  WHERE feature_key='finance.sales_invoice_issue')
 THEN RAISE EXCEPTION 'FIN_SALES_BRIDGE_ROLLBACK_DENIED_HISTORY'; END IF;
END $guard$;
REVOKE EXECUTE ON FUNCTION core10.finance_issue_sales_invoice_v1(
 bigint,bigint,bigint,date,date,text) FROM PUBLIC,authenticated;
DROP FUNCTION core10.finance_issue_sales_invoice_v1(bigint,bigint,bigint,date,date,text);
DELETE FROM core10.control_rpc_map_v1 WHERE rpc_name='finance_issue_sales_invoice_v1'
 AND lane='ChatGPT' AND board_row='B-013';
-- Restore original Finance F3 0403 manual-source attestation exactly.
CREATE OR REPLACE FUNCTION core10._finance_arap_source_integrity_v1()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,core10 AS $body$
DECLARE j core10.finance_journals_v1%ROWTYPE;
BEGIN
 SELECT * INTO j FROM core10.finance_journals_v1 WHERE id=NEW.journal_id;
 IF NOT FOUND OR j.status<>'posted' OR j.tenant_id<>NEW.tenant_id
  OR j.business_id<>NEW.business_id
 THEN RAISE EXCEPTION 'FIN_ARAP_SOURCE_NOT_POSTED'; END IF;
 IF j.source_domain<>'manual'
 THEN RAISE EXCEPTION 'FIN_ARAP_EXTERNAL_SOURCE_NOT_ATTESTED'; END IF;
 RETURN NEW;
END $body$;
DROP TRIGGER finance_sales_invoice_lines_no_truncate_v1 ON core10.sales_invoice_draft_lines_v1;
DROP TRIGGER finance_sales_invoice_lines_guard_v1 ON core10.sales_invoice_draft_lines_v1;
DROP TRIGGER finance_sales_invoice_source_guard_v1 ON core10.sales_invoice_drafts_v1;
DROP FUNCTION core10._finance_sales_invoice_source_guard_v1();
DROP TRIGGER finance_sales_issue_no_truncate_v1 ON core10.finance_sales_issues_v1;
DROP TRIGGER finance_sales_issue_immutable_v1 ON core10.finance_sales_issues_v1;
DROP FUNCTION core10._finance_sales_issue_immutable_v1();
DROP TABLE core10.finance_sales_issues_v1;
DELETE FROM core10.control_catalog_v1 WHERE feature_key='finance.sales_invoice_issue'
 AND pack='NP06';
