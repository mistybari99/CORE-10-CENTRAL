-- NP06 / 0402 guarded rollback: never erase AR/AP links, allocations or Audit/Control.
DO $guard$ BEGIN
 IF EXISTS(SELECT 1 FROM core10.finance_arap_links_v1)
 OR EXISTS(SELECT 1 FROM core10.finance_arap_allocations_v1)
 OR EXISTS(SELECT 1 FROM core10.canonical_audit_events_v1
           WHERE action IN ('finance.arap_link','finance.arap_allocate'))
 OR EXISTS(SELECT 1 FROM core10.control_setting_versions_v1
           WHERE feature_key IN ('finance.arap_link','finance.arap_allocate'))
 OR EXISTS(SELECT 1 FROM core10.control_overrides_v1
           WHERE feature_key IN ('finance.arap_link','finance.arap_allocate'))
 THEN RAISE EXCEPTION 'FIN_ARAP_ROLLBACK_DENIED_HISTORY'; END IF;
END $guard$;

DROP FUNCTION core10.finance_arap_aging_v1(bigint,date,text);
DROP FUNCTION core10.finance_allocate_payment_v1(bigint,bigint,numeric,text);
DROP FUNCTION core10.finance_link_open_item_v1(bigint,bigint,bigint,text,date,text);
DROP TABLE core10.finance_arap_allocations_v1;
DROP TABLE core10.finance_arap_links_v1;
DROP FUNCTION core10._finance_arap_immutable_v1();
DROP FUNCTION core10._finance_arap_net_v1(bigint,bigint,text);
DELETE FROM core10.control_rpc_map_v1 WHERE lane='ChatGPT' AND board_row='B-013'
 AND rpc_name IN('finance_link_open_item_v1','finance_allocate_payment_v1');
DELETE FROM core10.control_catalog_v1 WHERE pack='NP06'
 AND feature_key IN('finance.arap_link','finance.arap_allocate');
