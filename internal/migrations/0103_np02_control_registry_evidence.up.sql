-- NP02 / B-010 / 0103: an RPC may be "enforced" in the Control registry only with evidence.
-- Evidence = its current definition calls core10.control_check_v1 with exactly its mapped feature key,
-- and a named test file proves the switch-off denial (checked in CI by control-registry-evidence.sh).
-- NP01 migrations 0013-0099 run before the registry exists (0100), so they cannot update it themselves;
-- promotion of their bound RPCs happens here, after 0102, and only where the evidence holds.

ALTER TABLE core10.control_rpc_map_v1
 ADD COLUMN test_ref text CHECK (test_ref ~ '^tests/[A-Za-z0-9_./-]{3,200}$');
ALTER TABLE core10.control_rpc_map_v1
 ADD CONSTRAINT control_rpc_map_enforced_needs_test CHECK (status <> 'enforced' OR test_ref IS NOT NULL);

CREATE FUNCTION core10._control_rpc_calls_check_v1(p_rpc text, p_feature text) RETURNS boolean
LANGUAGE sql STABLE SET search_path=pg_catalog,core10 AS $$
 SELECT EXISTS (SELECT 1 FROM pg_proc p
  WHERE p.pronamespace = 'core10'::regnamespace AND p.proname = p_rpc
    AND pg_get_functiondef(p.oid) ~ ('control_check_v1\(\s*[^,()]+,\s*''' || replace(p_feature, '.', '\.') || ''''))
$$;
REVOKE EXECUTE ON FUNCTION core10._control_rpc_calls_check_v1(text, text) FROM PUBLIC, authenticated;

-- Promote one pending row when the evidence holds; otherwise leave it pending and say why.
CREATE FUNCTION core10._control_registry_promote_v1(p_rpc text, p_test_ref text) RETURNS text
LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog,core10 AS $$
DECLARE m core10.control_rpc_map_v1%ROWTYPE;
BEGIN
 SELECT * INTO m FROM core10.control_rpc_map_v1 WHERE rpc_name = p_rpc FOR UPDATE;
 IF NOT FOUND THEN RETURN 'not_registered'; END IF;
 IF m.status <> 'pending' THEN RETURN m.status; END IF;
 IF NOT core10._control_rpc_calls_check_v1(p_rpc, m.feature_key) THEN
  RETURN 'pending: the RPC does not call control_check_v1 for ' || m.feature_key;
 END IF;
 UPDATE core10.control_rpc_map_v1
  SET status = 'enforced', test_ref = p_test_ref,
      reason = 'Calls control_check_v1 for ' || m.feature_key || '; switch-off denial proven by ' || p_test_ref
  WHERE rpc_name = p_rpc;
 RETURN 'enforced';
END $$;
REVOKE EXECUTE ON FUNCTION core10._control_registry_promote_v1(text, text) FROM PUBLIC, authenticated;

DO $$
BEGIN
 -- NP01 B-020 (ChatGPT, 0018): Owner switch for publishing approval policies.
 RAISE NOTICE 'registry publish_approval_policy_v1: %',
  core10._control_registry_promote_v1('publish_approval_policy_v1', 'tests/migrations/np01-control-publish-e2e.sql');
END $$;
