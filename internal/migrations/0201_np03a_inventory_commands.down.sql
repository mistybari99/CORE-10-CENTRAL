-- Rollback of 0201: fail closed on any persisted stock command, inventory audit or inventory Control history.
-- Full up/down/up is safe only on an EMPTY disposable test database.
DO $guard$ BEGIN
 IF EXISTS(SELECT 1 FROM core10.inventory_commands_v1) OR
    EXISTS(SELECT 1 FROM core10.canonical_audit_events_v1 WHERE source_domain='inventory') OR
    EXISTS(SELECT 1 FROM core10.control_setting_versions_v1
      WHERE feature_key IN ('inventory.receive','inventory.issue','inventory.transfer','inventory.adjust')) OR
    EXISTS(SELECT 1 FROM core10.control_overrides_v1
      WHERE feature_key IN ('inventory.receive','inventory.issue','inventory.transfer','inventory.adjust'))
 THEN RAISE EXCEPTION 'INV_ROLLBACK_DENIED_PERSISTED_HISTORY'; END IF;
END $guard$;

DELETE FROM core10.control_rpc_map_v1 WHERE lane='Claude' AND board_row='B-012'
 AND rpc_name IN ('create_inventory_command_v1','advance_inventory_command_v1');

DROP FUNCTION core10.inventory_list_balances_v1(bigint,bigint,bigint,bigint,integer);
DROP FUNCTION core10.inventory_list_commands_v1(bigint,bigint,text,bigint,integer);
DROP FUNCTION core10.advance_inventory_command_v1(bigint,text,integer,text);
DROP FUNCTION core10.create_inventory_command_v1(bigint,text,bigint,bigint,bigint,numeric,text,text);
DROP FUNCTION core10._inventory_command_json_v1(core10.inventory_commands_v1,boolean);
DROP FUNCTION core10._inventory_may_act_v1(bigint,bigint,bigint,bigint);
DROP FUNCTION core10._inventory_controls_v1(bigint,text,bigint[],jsonb);
DROP FUNCTION core10._inventory_kind_feature_v1(text);
DROP FUNCTION core10.inventory_action_authorized_v1(bigint,bigint,bigint,text);
DROP TABLE core10.inventory_command_requests_v1;
DROP TABLE core10.inventory_commands_v1;

DELETE FROM core10.control_catalog_v1
 WHERE feature_key IN ('inventory.receive','inventory.issue','inventory.transfer','inventory.adjust');
