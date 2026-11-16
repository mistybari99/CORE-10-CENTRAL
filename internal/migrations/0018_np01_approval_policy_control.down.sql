-- NP01 B-020 / 0018 rollback: restore the exact 0010 policy function.
-- Note: 0102..0100 are reversed before this rollback; no lingering Control references.
CREATE OR REPLACE FUNCTION core10.publish_approval_policy_v1(
  p_business bigint, p_domain text, p_action text, p_ttl_minutes integer, p_key text
) RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path = core10, pg_catalog AS $fn$
DECLARE
  v_tenant bigint;
  v_actor uuid := core10.actor_uid();
  v_version integer;
  v_id bigint;
  v_old core10.approval_policy_versions_v1%ROWTYPE;
BEGIN
  IF v_actor IS NULL OR p_business IS NULL
    OR p_domain IS NULL OR p_domain !~ '^[a-z][a-z0-9_]{1,63}$'
    OR p_action IS NULL OR p_action !~ '^[a-z][a-z0-9_]{1,63}$'
    OR p_ttl_minutes IS NULL OR p_ttl_minutes NOT BETWEEN 5 AND 43200
    OR p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{8,128}$'
  THEN RAISE EXCEPTION 'invalid_approval_policy'; END IF;

  -- Serialize version allocation for this business, including concurrent owners.
  SELECT tenant_id INTO v_tenant
    FROM core10.businesses WHERE id = p_business FOR UPDATE;
  IF NOT FOUND OR NOT core10.can_manage(v_tenant, p_business)
  THEN RAISE EXCEPTION 'approval_policy_denied'; END IF;

  SELECT * INTO v_old FROM core10.approval_policy_versions_v1
    WHERE business_id = p_business AND request_key = p_key;
  IF FOUND THEN
    IF v_old.created_by <> v_actor OR v_old.domain <> p_domain
      OR v_old.action_code <> p_action OR v_old.ttl_minutes <> p_ttl_minutes
    THEN RAISE EXCEPTION 'approval_policy_replay_conflict'; END IF;
    RETURN v_old.id;
  END IF;

  SELECT COALESCE(max(version), 0) + 1 INTO v_version
    FROM core10.approval_policy_versions_v1
    WHERE business_id = p_business AND domain = p_domain
      AND action_code = p_action;

  INSERT INTO core10.approval_policy_versions_v1
    (tenant_id, business_id, domain, action_code, version,
     ttl_minutes, request_key, created_by)
  VALUES (v_tenant, p_business, p_domain, p_action, v_version,
          p_ttl_minutes, p_key, v_actor)
  RETURNING id INTO v_id;
  RETURN v_id;
END $fn$;
