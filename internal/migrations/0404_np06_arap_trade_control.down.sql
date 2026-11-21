-- NP06/0404: never remove the trade-control fence where financial,
-- Approval/Owner Control or account-designation history already exists.
DO $guard$ BEGIN
 IF EXISTS(SELECT 1 FROM core10.finance_arap_links_v1)
 OR EXISTS(SELECT 1 FROM core10.finance_arap_allocations_v1)
 OR EXISTS(SELECT 1 FROM core10.finance_arap_control_accounts_v1)
 OR EXISTS(SELECT 1 FROM core10.canonical_audit_events_v1
   WHERE action IN('finance.arap_link','finance.arap_allocate','finance.arap_control_account'))
 OR EXISTS(SELECT 1 FROM core10.control_setting_versions_v1
   WHERE feature_key IN('finance.arap_link','finance.arap_allocate','finance.arap_control_account'))
 OR EXISTS(SELECT 1 FROM core10.control_overrides_v1
   WHERE feature_key IN('finance.arap_link','finance.arap_allocate','finance.arap_control_account'))
 THEN RAISE EXCEPTION 'FIN_ARAP_INTEGRITY_ROLLBACK_DENIED_HISTORY'; END IF;
END $guard$;
DROP TRIGGER finance_arap_trade_control_guard_v1 ON core10.finance_arap_links_v1;
DROP FUNCTION core10._finance_arap_trade_control_guard_v1();
REVOKE EXECUTE ON FUNCTION core10.finance_register_arap_control_account_v1(bigint,text,text)
 FROM PUBLIC,authenticated;
DROP FUNCTION core10.finance_register_arap_control_account_v1(bigint,text,text);
DROP TABLE core10.finance_arap_control_accounts_v1;
DELETE FROM core10.control_rpc_map_v1 WHERE lane='ChatGPT' AND board_row='B-013'
 AND rpc_name='finance_register_arap_control_account_v1';
DELETE FROM core10.control_catalog_v1 WHERE pack='NP06'
 AND feature_key='finance.arap_control_account';
