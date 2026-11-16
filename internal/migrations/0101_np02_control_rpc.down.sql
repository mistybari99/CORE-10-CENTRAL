-- Rollback of 0101: drops the Control port functions only; no data is touched.
DROP FUNCTION core10.control_approval_binding_v1(bigint, text, bigint);
DROP FUNCTION core10.control_overrides_v1(bigint);
DROP FUNCTION core10.control_history_v1(bigint, text, integer);
DROP FUNCTION core10.control_read_v1(bigint, bigint);
DROP FUNCTION core10.control_revoke_override_v1(bigint, bigint, text, text);
DROP FUNCTION core10.control_grant_override_v1(bigint, bigint, text, integer, text, text);
DROP FUNCTION core10.control_revert_v1(bigint, bigint, text, integer, integer, text, text);
DROP FUNCTION core10.control_set_v1(bigint, bigint, text, boolean, smallint, jsonb, timestamptz, boolean, integer, text, text);
DROP FUNCTION core10._control_write_v1(bigint, bigint, bigint, text, boolean, smallint, jsonb, timestamptz, boolean, integer, text, text, integer);
DROP FUNCTION core10._control_row_json_v1(core10.control_setting_versions_v1, boolean);
DROP FUNCTION core10.control_check_v1(bigint, text, bigint);
DROP FUNCTION core10._control_resolve_v1(bigint, text, bigint);
DROP FUNCTION core10._control_validate_params_v1(jsonb, jsonb);
