-- Rollback of 0100. Refuses to destroy Owner setting history or exceptions.
DO $$
BEGIN
 IF EXISTS (SELECT 1 FROM core10.control_setting_versions_v1)
    OR EXISTS (SELECT 1 FROM core10.control_overrides_v1) THEN
  RAISE EXCEPTION 'CONTROL_HISTORY_NOT_EMPTY: Owner setting history is never dropped by rollback';
 END IF;
END $$;
DROP TABLE core10.control_rpc_map_v1;
DROP TABLE core10.control_overrides_v1;
DROP TABLE core10.control_setting_versions_v1;
DROP TABLE core10.control_catalog_v1;
DROP FUNCTION core10._control_override_guard_v1();
DROP FUNCTION core10._control_history_guard_v1();
DROP FUNCTION core10._control_schema_ok_v1(jsonb);
