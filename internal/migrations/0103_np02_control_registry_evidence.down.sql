-- Rollback of 0103: rows promoted here return to pending; evidence column and helpers are removed.
UPDATE core10.control_rpc_map_v1
 SET status = 'pending', reason = 'Binding to the Control port was rolled back; to be re-proven'
 WHERE status = 'enforced';
ALTER TABLE core10.control_rpc_map_v1 DROP CONSTRAINT control_rpc_map_enforced_needs_test;
ALTER TABLE core10.control_rpc_map_v1 DROP COLUMN test_ref;
DROP FUNCTION core10._control_registry_promote_v1(text, text);
DROP FUNCTION core10._control_rpc_calls_check_v1(text, text);
