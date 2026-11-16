-- NP01 B-020 / 0018: bind canonical policy publishing to the Owner Control port.
-- Executes after the caller's Auth check, before policy replay or mutation.
-- The Control port is created by 0100-0102 later in the ordered migration set;
-- this replacement function is not invoked until all migrations have been applied.
-- Its existing signature and GRANTs are preserved by CREATE OR REPLACE.
CREATE OR REPLACE FUNCTION core10.publish_approval_policy_v1(
  p_business bigint, p_domain text, p_action text, p_ttl_minutes integer, p_key text
) RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path = core10, pg_catalog AS $fn$
DECLARE
  v_tenant bigint;
  v_actor uuid := core10.actor_uid();
  v_version integer;
  v_id bigint;
  v_control jsonb;
  v_effective_ttl integer;
  v_old core10.approval_policy_versions_v1%ROWTYPE;
BEGIN
  IF v_actor IS NULL OR p_business IS NULL
    OR p_domain IS NULL OR p_domain !~ '^[a-z][a-z0-9_]{1,63}$'
    OR p_action IS NULL OR p_action !~ '^[a-z][a-z0-9_]{1,63}$'
    OR (p_ttl_minutes IS NOT NULL AND p_ttl_minutes NOT BETWEEN 5 AND 43200)
    OR p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{8,128}$'
  THEN RAISE EXCEPTION 'invalid_approval_policy'; END IF;

  -- Serialize version allocation for this business, including concurrent owners.
  SELECT tenant_id INTO v_tenant
    FROM core10.businesses WHERE id = p_business FOR UPDATE;
  IF NOT FOUND OR NOT core10.can_manage(v_tenant, p_business)
  THEN RAISE EXCEPTION 'approval_policy_denied'; END IF;

  -- After the Auth port passes, enforce the Owner's per-business switch.
  -- The Owner-configured TTL is the default; an explicit policy TTL remains
  -- subject to the existing canonical 5..43200 minute validation.
  v_control := core10.control_check_v1(p_business,'gov002.approval_policy',NULL);
  v_effective_ttl := coalesce(p_ttl_minutes,(v_control->'params'->>'ttl_minutes')::integer);
  IF v_effective_ttl IS NULL OR v_effective_ttl NOT BETWEEN 5 AND 43200
  THEN RAISE EXCEPTION 'invalid_approval_policy'; END IF;

  SELECT * INTO v_old FROM core10.approval_policy_versions_v1
    WHERE business_id = p_business AND request_key = p_key;
  IF FOUND THEN
    IF v_old.created_by <> v_actor OR v_old.domain <> p_domain
      OR v_old.action_code <> p_action OR v_old.ttl_minutes <> v_effective_ttl
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
          v_effective_ttl, p_key, v_actor)
  RETURNING id INTO v_id;
  RETURN v_id;
END $fn$;
