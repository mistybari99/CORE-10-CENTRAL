-- NP02 / B-010 / 0101: Owner Control port, server-side enforcement and Owner RPCs (DEC-08).
-- Resolution order for one feature: site setting, else business setting, else catalog default.
-- The effective version of a scope is the one with the latest effective_from not in the future
-- (ties: higher version). A scheduled change therefore takes over when its date arrives.
-- Owners (tenant owner or business owner, current and unexpired) write. Members read.
-- Feature RPCs of every pack call core10.control_check_v1 before they change anything.

CREATE FUNCTION core10._control_validate_params_v1(p_schema jsonb, p_values jsonb) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path=pg_catalog,core10 AS $$
DECLARE k text; d jsonb; v jsonb; t text; n numeric; res jsonb := '{}'::jsonb;
BEGIN
 IF p_values IS NULL THEN p_values := '{}'::jsonb; END IF;
 IF jsonb_typeof(p_values) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'CONTROL_PARAMS_SHAPE'; END IF;
 FOR k IN SELECT jsonb_object_keys(p_values) LOOP
  IF NOT (p_schema ? k) THEN RAISE EXCEPTION 'CONTROL_PARAM_UNKNOWN:%', k; END IF;
 END LOOP;
 FOR k, d IN SELECT key, value FROM jsonb_each(p_schema) ORDER BY key LOOP
  t := d->>'type';
  v := CASE WHEN p_values ? k THEN p_values->k ELSE d->'default' END;
  IF t = 'bool' THEN
   IF jsonb_typeof(v) IS DISTINCT FROM 'boolean' THEN RAISE EXCEPTION 'CONTROL_PARAM_TYPE:%', k; END IF;
  ELSIF t IN ('int','numeric') THEN
   IF jsonb_typeof(v) IS DISTINCT FROM 'number' THEN RAISE EXCEPTION 'CONTROL_PARAM_TYPE:%', k; END IF;
   n := (v #>> '{}')::numeric;
   IF t = 'int' AND n <> trunc(n) THEN RAISE EXCEPTION 'CONTROL_PARAM_TYPE:%', k; END IF;
   IF n < (d->>'min')::numeric OR n > (d->>'max')::numeric THEN RAISE EXCEPTION 'CONTROL_PARAM_RANGE:%', k; END IF;
  ELSIF t = 'text' THEN
   IF jsonb_typeof(v) IS DISTINCT FROM 'string' THEN RAISE EXCEPTION 'CONTROL_PARAM_TYPE:%', k; END IF;
   IF length(v #>> '{}') > coalesce((d->>'maxlen')::int, 200) THEN RAISE EXCEPTION 'CONTROL_PARAM_RANGE:%', k; END IF;
  ELSE
   IF jsonb_typeof(v) IS DISTINCT FROM 'string' THEN RAISE EXCEPTION 'CONTROL_PARAM_TYPE:%', k; END IF;
   IF NOT ((d->'values') @> jsonb_build_array(v)) THEN RAISE EXCEPTION 'CONTROL_PARAM_ENUM:%', k; END IF;
  END IF;
  res := res || jsonb_build_object(k, v);
 END LOOP;
 RETURN res;
END $$;
REVOKE EXECUTE ON FUNCTION core10._control_validate_params_v1(jsonb, jsonb) FROM PUBLIC, authenticated;

-- Internal: effective setting of one feature. No authorization; callers check scope first.
CREATE FUNCTION core10._control_resolve_v1(p_business bigint, p_feature text, p_site bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE c core10.control_catalog_v1%ROWTYPE; r core10.control_setting_versions_v1%ROWTYPE; src text;
BEGIN
 SELECT * INTO c FROM core10.control_catalog_v1 WHERE feature_key = p_feature AND status = 'active';
 IF NOT FOUND THEN RAISE EXCEPTION 'CONTROL_UNKNOWN_FEATURE'; END IF;
 IF NOT c.invariant THEN
  IF p_site IS NOT NULL THEN
   SELECT * INTO r FROM core10.control_setting_versions_v1
    WHERE business_id = p_business AND site_id = p_site AND feature_key = p_feature
      AND effective_from <= statement_timestamp()
    ORDER BY effective_from DESC, version DESC LIMIT 1;
   IF FOUND AND NOT r.inherit THEN src := 'site'; END IF;
  END IF;
  IF src IS NULL THEN
   SELECT * INTO r FROM core10.control_setting_versions_v1
    WHERE business_id = p_business AND site_id IS NULL AND feature_key = p_feature
      AND effective_from <= statement_timestamp()
    ORDER BY effective_from DESC, version DESC LIMIT 1;
   IF FOUND THEN src := 'business'; END IF;
  END IF;
 END IF;
 IF src IS NULL THEN
  RETURN jsonb_build_object('feature_key', c.feature_key, 'invariant', c.invariant,
   'enabled', c.default_enabled, 'stages', c.default_stages,
   'params', core10._control_validate_params_v1(c.params, '{}'::jsonb),
   'version', 0, 'source', 'default', 'effective_from', NULL);
 END IF;
 RETURN jsonb_build_object('feature_key', c.feature_key, 'invariant', c.invariant,
  'enabled', r.enabled, 'stages', r.stages, 'params', r.params,
  'version', r.version, 'source', src, 'effective_from', r.effective_from);
END $$;
REVOKE EXECUTE ON FUNCTION core10._control_resolve_v1(bigint, text, bigint) FROM PUBLIC, authenticated;

-- Enforcement point. Called by the state-changing RPCs of every pack, after their own Auth checks.
-- Raises CONTROL_DISABLED:<feature> when the Owner has switched the feature off, unless the Owner
-- granted a one-time exception, which this call consumes. Not executable by API roles.
CREATE FUNCTION core10.control_check_v1(p_business bigint, p_feature text, p_site bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE v_actor uuid := core10.actor_uid(); v_tenant bigint; r jsonb; o core10.control_overrides_v1%ROWTYPE;
BEGIN
 IF v_actor IS NULL THEN RAISE EXCEPTION 'CONTROL_UNAUTHENTICATED'; END IF;
 SELECT tenant_id INTO v_tenant FROM core10.businesses WHERE id = p_business;
 IF v_tenant IS NULL OR NOT core10.can_see_business(v_tenant, p_business) THEN RAISE EXCEPTION 'CONTROL_SCOPE'; END IF;
 IF p_site IS NOT NULL AND NOT EXISTS (SELECT 1 FROM core10.sites s
    WHERE s.id = p_site AND s.business_id = p_business AND s.tenant_id = v_tenant) THEN
  RAISE EXCEPTION 'CONTROL_SCOPE';
 END IF;
 r := core10._control_resolve_v1(p_business, p_feature, p_site);
 IF (r->>'enabled')::boolean THEN RETURN r || jsonb_build_object('override_used', false); END IF;
 SELECT * INTO o FROM core10.control_overrides_v1
  WHERE business_id = p_business AND feature_key = p_feature
    AND (site_id IS NULL OR site_id = p_site)
    AND consumed_at IS NULL AND revoked_at IS NULL AND expires_at > statement_timestamp()
  ORDER BY (site_id IS NULL), id LIMIT 1 FOR UPDATE SKIP LOCKED;
 IF NOT FOUND THEN RAISE EXCEPTION 'CONTROL_DISABLED:%', p_feature; END IF;
 UPDATE core10.control_overrides_v1 SET consumed_at = statement_timestamp(), consumed_by = v_actor WHERE id = o.id;
 PERFORM core10._append_canonical_audit_v1(v_tenant, p_business, 'control',
  'override:' || o.id || ':consumed', 'control.override_consumed', v_actor,
  'control:ovr:' || o.id || ':consumed',
  jsonb_build_object('feature_key', p_feature, 'site_id', p_site, 'override_id', o.id));
 RETURN r || jsonb_build_object('override_used', true, 'override_id', o.id);
END $$;
REVOKE EXECUTE ON FUNCTION core10.control_check_v1(bigint, text, bigint) FROM PUBLIC, authenticated;

CREATE FUNCTION core10._control_row_json_v1(r core10.control_setting_versions_v1, p_replayed boolean) RETURNS jsonb
LANGUAGE sql IMMUTABLE SET search_path=pg_catalog,core10 AS $$
 SELECT jsonb_build_object('ok', true, 'feature_key', r.feature_key, 'site_id', r.site_id,
  'version', r.version, 'enabled', r.enabled, 'stages', r.stages, 'params', r.params,
  'inherit', r.inherit, 'effective_from', r.effective_from, 'reverted_from', r.reverted_from,
  'audit_event_id', r.audit_event_id, 'replayed', p_replayed)
$$;
REVOKE EXECUTE ON FUNCTION core10._control_row_json_v1(core10.control_setting_versions_v1, boolean) FROM PUBLIC, authenticated;

-- Internal single writer for set and revert. Callers have already proven the Owner role.
CREATE FUNCTION core10._control_write_v1(
 p_tenant bigint, p_business bigint, p_site bigint, p_feature text, p_enabled boolean,
 p_stages smallint, p_params jsonb, p_effective timestamptz, p_inherit boolean,
 p_expected integer, p_reason text, p_key text, p_reverted integer
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE v_actor uuid := core10.actor_uid(); c core10.control_catalog_v1%ROWTYPE;
 old core10.control_setting_versions_v1%ROWTYPE; v_cur integer; v_ver integer; v_norm jsonb;
 v_eff timestamptz; v_hash text; v_audit bigint; v_row core10.control_setting_versions_v1%ROWTYPE;
 v_inherit boolean := coalesce(p_inherit, false); v_enabled boolean; v_stages smallint;
BEGIN
 IF v_actor IS NULL THEN RAISE EXCEPTION 'CONTROL_UNAUTHENTICATED'; END IF;
 IF p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{8,128}$' THEN RAISE EXCEPTION 'CONTROL_BAD_KEY'; END IF;
 IF p_reason IS NULL OR length(btrim(p_reason)) NOT BETWEEN 5 AND 500 THEN RAISE EXCEPTION 'CONTROL_BAD_REASON'; END IF;
 SELECT * INTO c FROM core10.control_catalog_v1 WHERE feature_key = p_feature AND status = 'active';
 IF NOT FOUND THEN RAISE EXCEPTION 'CONTROL_UNKNOWN_FEATURE'; END IF;
 IF c.invariant THEN RAISE EXCEPTION 'CONTROL_INVARIANT'; END IF;
 IF p_site IS NOT NULL AND (NOT c.allow_site_scope OR NOT EXISTS (SELECT 1 FROM core10.sites s
    WHERE s.id = p_site AND s.business_id = p_business AND s.tenant_id = p_tenant)) THEN
  RAISE EXCEPTION 'CONTROL_SCOPE';
 END IF;
 IF v_inherit AND p_site IS NULL THEN RAISE EXCEPTION 'CONTROL_INHERIT_SCOPE'; END IF;
 v_enabled := CASE WHEN v_inherit THEN true ELSE p_enabled END;
 v_stages := CASE WHEN v_inherit THEN 0 ELSE p_stages END;
 IF v_enabled IS NULL OR v_stages IS NULL THEN RAISE EXCEPTION 'CONTROL_BAD_INPUT'; END IF;
 IF v_stages < 0 OR v_stages > c.max_stages THEN RAISE EXCEPTION 'CONTROL_STAGES'; END IF;
 v_eff := coalesce(p_effective, statement_timestamp());
 IF v_eff < statement_timestamp() - interval '5 minutes' THEN RAISE EXCEPTION 'CONTROL_EFFECTIVE_PAST'; END IF;
 IF v_eff > statement_timestamp() + interval '366 days' THEN RAISE EXCEPTION 'CONTROL_EFFECTIVE_FUTURE'; END IF;
 v_norm := CASE WHEN v_inherit THEN '{}'::jsonb ELSE core10._control_validate_params_v1(c.params, p_params) END;
 PERFORM pg_advisory_xact_lock(hashtextextended('c10ctl:' || p_business || ':' || coalesce(p_site, 0) || ':' || p_feature, 0));
 v_hash := encode(sha256(convert_to(jsonb_build_object('f', p_feature, 's', p_site, 'e', v_enabled,
  'g', v_stages, 'p', v_norm, 'i', v_inherit, 'ef', p_effective, 'r', p_reverted,
  'why', btrim(p_reason))::text, 'UTF8')), 'hex');
 SELECT * INTO old FROM core10.control_setting_versions_v1 WHERE business_id = p_business AND request_key = p_key;
 IF FOUND THEN
  IF old.payload_sha256 = v_hash AND old.feature_key = p_feature AND old.site_id IS NOT DISTINCT FROM p_site THEN
   RETURN core10._control_row_json_v1(old, true);
  END IF;
  RAISE EXCEPTION 'CONTROL_REPLAY_CONFLICT';
 END IF;
 SELECT coalesce(max(version), 0) INTO v_cur FROM core10.control_setting_versions_v1
  WHERE business_id = p_business AND site_id IS NOT DISTINCT FROM p_site AND feature_key = p_feature;
 IF p_expected IS DISTINCT FROM v_cur THEN RAISE EXCEPTION 'CONTROL_STALE_VERSION:%', v_cur; END IF;
 v_ver := v_cur + 1;
 v_audit := core10._append_canonical_audit_v1(p_tenant, p_business, 'control',
  p_feature || ':' || coalesce(p_site::text, 'all') || ':v' || v_ver, 'control.setting_changed',
  v_actor, 'control:' || p_key,
  jsonb_build_object('feature_key', p_feature, 'site_id', p_site, 'version', v_ver, 'enabled', v_enabled,
   'stages', v_stages, 'params', v_norm, 'inherit', v_inherit, 'effective_from', v_eff,
   'reverted_from', p_reverted, 'reason', btrim(p_reason)));
 INSERT INTO core10.control_setting_versions_v1(tenant_id, business_id, site_id, feature_key, version,
  enabled, stages, params, inherit, effective_from, reverted_from, reason, request_key, payload_sha256,
  created_by, audit_event_id)
 VALUES (p_tenant, p_business, p_site, p_feature, v_ver, v_enabled, v_stages, v_norm, v_inherit, v_eff,
  p_reverted, btrim(p_reason), p_key, v_hash, v_actor, v_audit)
 RETURNING * INTO v_row;
 RETURN core10._control_row_json_v1(v_row, false);
END $$;
REVOKE EXECUTE ON FUNCTION core10._control_write_v1(bigint, bigint, bigint, text, boolean, smallint,
 jsonb, timestamptz, boolean, integer, text, text, integer) FROM PUBLIC, authenticated;

-- Owner: set a feature on or off, its approval stages (0 to 5), parameters and effective date.
CREATE FUNCTION core10.control_set_v1(
 p_business bigint, p_site bigint, p_feature text, p_enabled boolean, p_stages smallint,
 p_params jsonb, p_effective_from timestamptz, p_inherit boolean, p_expected_version integer,
 p_reason text, p_request_key text
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE v_tenant bigint;
BEGIN
 SELECT tenant_id INTO v_tenant FROM core10.businesses WHERE id = p_business;
 IF v_tenant IS NULL OR core10.actor_uid() IS NULL OR NOT core10.can_see_business(v_tenant, p_business) THEN
  RAISE EXCEPTION 'CONTROL_SCOPE';
 END IF;
 IF NOT core10.can_manage(v_tenant, p_business) THEN RAISE EXCEPTION 'CONTROL_FORBIDDEN'; END IF;
 RETURN core10._control_write_v1(v_tenant, p_business, p_site, p_feature, p_enabled, p_stages,
  p_params, p_effective_from, p_inherit, p_expected_version, p_reason, p_request_key, NULL);
END $$;

-- Owner: restore an earlier version as a new version. History is never rewritten.
CREATE FUNCTION core10.control_revert_v1(
 p_business bigint, p_site bigint, p_feature text, p_to_version integer, p_expected_version integer,
 p_reason text, p_request_key text
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE v_tenant bigint; src core10.control_setting_versions_v1%ROWTYPE;
BEGIN
 SELECT tenant_id INTO v_tenant FROM core10.businesses WHERE id = p_business;
 IF v_tenant IS NULL OR core10.actor_uid() IS NULL OR NOT core10.can_see_business(v_tenant, p_business) THEN
  RAISE EXCEPTION 'CONTROL_SCOPE';
 END IF;
 IF NOT core10.can_manage(v_tenant, p_business) THEN RAISE EXCEPTION 'CONTROL_FORBIDDEN'; END IF;
 SELECT * INTO src FROM core10.control_setting_versions_v1
  WHERE business_id = p_business AND site_id IS NOT DISTINCT FROM p_site
    AND feature_key = p_feature AND version = p_to_version;
 IF NOT FOUND THEN RAISE EXCEPTION 'CONTROL_NO_SUCH_VERSION'; END IF;
 RETURN core10._control_write_v1(v_tenant, p_business, p_site, p_feature, src.enabled, src.stages,
  src.params, NULL, src.inherit, p_expected_version, p_reason, p_request_key, p_to_version);
END $$;

-- Owner: allow one use of a switched-off feature, with a reason and an expiry (1 to 168 hours).
CREATE FUNCTION core10.control_grant_override_v1(
 p_business bigint, p_site bigint, p_feature text, p_hours integer, p_reason text, p_request_key text
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE v_tenant bigint; v_actor uuid := core10.actor_uid(); c core10.control_catalog_v1%ROWTYPE;
 old core10.control_overrides_v1%ROWTYPE; o core10.control_overrides_v1%ROWTYPE;
BEGIN
 SELECT tenant_id INTO v_tenant FROM core10.businesses WHERE id = p_business;
 IF v_tenant IS NULL OR v_actor IS NULL OR NOT core10.can_see_business(v_tenant, p_business) THEN
  RAISE EXCEPTION 'CONTROL_SCOPE';
 END IF;
 IF NOT core10.can_manage(v_tenant, p_business) THEN RAISE EXCEPTION 'CONTROL_FORBIDDEN'; END IF;
 IF p_request_key IS NULL OR p_request_key !~ '^[A-Za-z0-9_-]{8,128}$' THEN RAISE EXCEPTION 'CONTROL_BAD_KEY'; END IF;
 IF p_reason IS NULL OR length(btrim(p_reason)) NOT BETWEEN 5 AND 500 THEN RAISE EXCEPTION 'CONTROL_BAD_REASON'; END IF;
 IF p_hours IS NULL OR p_hours NOT BETWEEN 1 AND 168 THEN RAISE EXCEPTION 'CONTROL_BAD_HOURS'; END IF;
 SELECT * INTO c FROM core10.control_catalog_v1 WHERE feature_key = p_feature AND status = 'active';
 IF NOT FOUND THEN RAISE EXCEPTION 'CONTROL_UNKNOWN_FEATURE'; END IF;
 IF c.invariant THEN RAISE EXCEPTION 'CONTROL_INVARIANT'; END IF;
 IF p_site IS NOT NULL AND (NOT c.allow_site_scope OR NOT EXISTS (SELECT 1 FROM core10.sites s
    WHERE s.id = p_site AND s.business_id = p_business AND s.tenant_id = v_tenant)) THEN
  RAISE EXCEPTION 'CONTROL_SCOPE';
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('c10ovr:' || p_business || ':' || p_request_key, 0));
 SELECT * INTO old FROM core10.control_overrides_v1 WHERE business_id = p_business AND request_key = p_request_key;
 IF FOUND THEN
  IF old.feature_key = p_feature AND old.site_id IS NOT DISTINCT FROM p_site AND old.reason = btrim(p_reason)
     AND old.granted_by = v_actor THEN
   RETURN jsonb_build_object('ok', true, 'override_id', old.id, 'expires_at', old.expires_at, 'replayed', true);
  END IF;
  RAISE EXCEPTION 'CONTROL_REPLAY_CONFLICT';
 END IF;
 INSERT INTO core10.control_overrides_v1(tenant_id, business_id, site_id, feature_key, reason, request_key,
  granted_by, expires_at)
 VALUES (v_tenant, p_business, p_site, p_feature, btrim(p_reason), p_request_key, v_actor,
  clock_timestamp() + make_interval(hours => p_hours))
 RETURNING * INTO o;
 PERFORM core10._append_canonical_audit_v1(v_tenant, p_business, 'control', 'override:' || o.id || ':granted',
  'control.override_granted', v_actor, 'control:ovr:' || o.id || ':granted',
  jsonb_build_object('feature_key', p_feature, 'site_id', p_site, 'override_id', o.id,
   'expires_at', o.expires_at, 'reason', o.reason));
 RETURN jsonb_build_object('ok', true, 'override_id', o.id, 'expires_at', o.expires_at, 'replayed', false);
END $$;

CREATE FUNCTION core10.control_revoke_override_v1(
 p_business bigint, p_override_id bigint, p_reason text, p_request_key text
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE v_tenant bigint; v_actor uuid := core10.actor_uid(); o core10.control_overrides_v1%ROWTYPE;
BEGIN
 SELECT tenant_id INTO v_tenant FROM core10.businesses WHERE id = p_business;
 IF v_tenant IS NULL OR v_actor IS NULL OR NOT core10.can_see_business(v_tenant, p_business) THEN
  RAISE EXCEPTION 'CONTROL_SCOPE';
 END IF;
 IF NOT core10.can_manage(v_tenant, p_business) THEN RAISE EXCEPTION 'CONTROL_FORBIDDEN'; END IF;
 IF p_request_key IS NULL OR p_request_key !~ '^[A-Za-z0-9_-]{8,128}$' THEN RAISE EXCEPTION 'CONTROL_BAD_KEY'; END IF;
 IF p_reason IS NULL OR length(btrim(p_reason)) NOT BETWEEN 5 AND 500 THEN RAISE EXCEPTION 'CONTROL_BAD_REASON'; END IF;
 SELECT * INTO o FROM core10.control_overrides_v1
  WHERE id = p_override_id AND business_id = p_business FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'CONTROL_SCOPE'; END IF;
 IF o.revoked_at IS NOT NULL THEN
  IF o.revoke_request_key = p_request_key THEN
   RETURN jsonb_build_object('ok', true, 'override_id', o.id, 'replayed', true);
  END IF;
  RAISE EXCEPTION 'CONTROL_OVERRIDE_CLOSED';
 END IF;
 IF o.consumed_at IS NOT NULL THEN RAISE EXCEPTION 'CONTROL_OVERRIDE_CLOSED'; END IF;
 UPDATE core10.control_overrides_v1
  SET revoked_at = clock_timestamp(), revoked_by = v_actor, revoke_request_key = p_request_key
  WHERE id = o.id;
 PERFORM core10._append_canonical_audit_v1(v_tenant, p_business, 'control', 'override:' || o.id || ':revoked',
  'control.override_revoked', v_actor, 'control:ovr:' || o.id || ':revoked',
  jsonb_build_object('feature_key', o.feature_key, 'override_id', o.id, 'reason', btrim(p_reason)));
 RETURN jsonb_build_object('ok', true, 'override_id', o.id, 'replayed', false);
END $$;

-- Members: every active feature with its effective setting at business or site scope.
CREATE FUNCTION core10.control_read_v1(p_business bigint, p_site bigint DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE v_tenant bigint; res jsonb;
BEGIN
 SELECT tenant_id INTO v_tenant FROM core10.businesses WHERE id = p_business;
 IF v_tenant IS NULL OR core10.actor_uid() IS NULL OR NOT core10.can_see_business(v_tenant, p_business) THEN
  RAISE EXCEPTION 'CONTROL_SCOPE';
 END IF;
 IF p_site IS NOT NULL AND NOT EXISTS (SELECT 1 FROM core10.sites s
    WHERE s.id = p_site AND s.business_id = p_business AND s.tenant_id = v_tenant) THEN
  RAISE EXCEPTION 'CONTROL_SCOPE';
 END IF;
 SELECT coalesce(jsonb_agg(
   jsonb_build_object('title_en', c.title_en, 'title_bn', c.title_bn, 'pack', c.pack,
    'max_stages', c.max_stages, 'allow_site_scope', c.allow_site_scope,
    'approval_domain', c.approval_domain, 'approval_action', c.approval_action,
    'param_schema', c.params)
   || core10._control_resolve_v1(p_business, c.feature_key, p_site)
   || jsonb_build_object('scheduled', (SELECT jsonb_build_object('version', v.version,
        'effective_from', v.effective_from, 'enabled', v.enabled, 'stages', v.stages)
       FROM core10.control_setting_versions_v1 v
       WHERE v.business_id = p_business AND v.site_id IS NOT DISTINCT FROM p_site
         AND v.feature_key = c.feature_key AND v.effective_from > statement_timestamp()
       ORDER BY v.effective_from LIMIT 1))
   ORDER BY c.pack, c.feature_key), '[]'::jsonb)
 INTO res FROM core10.control_catalog_v1 c WHERE c.status = 'active';
 RETURN res;
END $$;

-- Owner: full change history, newest first, bounded.
CREATE FUNCTION core10.control_history_v1(p_business bigint, p_feature text DEFAULT NULL, p_limit integer DEFAULT 100)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE v_tenant bigint; res jsonb;
BEGIN
 SELECT tenant_id INTO v_tenant FROM core10.businesses WHERE id = p_business;
 IF v_tenant IS NULL OR core10.actor_uid() IS NULL OR NOT core10.can_see_business(v_tenant, p_business) THEN
  RAISE EXCEPTION 'CONTROL_SCOPE';
 END IF;
 IF NOT core10.can_manage(v_tenant, p_business) THEN RAISE EXCEPTION 'CONTROL_FORBIDDEN'; END IF;
 SELECT coalesce(jsonb_agg(x ORDER BY (x->>'id')::bigint DESC), '[]'::jsonb) INTO res FROM (
  SELECT jsonb_build_object('id', v.id, 'feature_key', v.feature_key, 'site_id', v.site_id, 'version', v.version,
   'enabled', v.enabled, 'stages', v.stages, 'params', v.params, 'inherit', v.inherit,
   'effective_from', v.effective_from, 'reverted_from', v.reverted_from, 'reason', v.reason,
   'changed_by', v.created_by, 'changed_at', v.created_at, 'audit_event_id', v.audit_event_id) AS x
  FROM core10.control_setting_versions_v1 v
  WHERE v.business_id = p_business AND (p_feature IS NULL OR v.feature_key = p_feature)
  ORDER BY v.id DESC LIMIT greatest(1, least(coalesce(p_limit, 100), 200))) q;
 RETURN res;
END $$;

CREATE FUNCTION core10.control_overrides_v1(p_business bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE v_tenant bigint; res jsonb;
BEGIN
 SELECT tenant_id INTO v_tenant FROM core10.businesses WHERE id = p_business;
 IF v_tenant IS NULL OR core10.actor_uid() IS NULL OR NOT core10.can_see_business(v_tenant, p_business) THEN
  RAISE EXCEPTION 'CONTROL_SCOPE';
 END IF;
 IF NOT core10.can_manage(v_tenant, p_business) THEN RAISE EXCEPTION 'CONTROL_FORBIDDEN'; END IF;
 SELECT coalesce(jsonb_agg(x ORDER BY (x->>'id')::bigint DESC), '[]'::jsonb) INTO res FROM (
  SELECT jsonb_build_object('id', o.id, 'feature_key', o.feature_key, 'site_id', o.site_id, 'reason', o.reason,
   'granted_by', o.granted_by, 'granted_at', o.granted_at, 'expires_at', o.expires_at,
   'status', CASE WHEN o.consumed_at IS NOT NULL THEN 'consumed' WHEN o.revoked_at IS NOT NULL THEN 'revoked'
              WHEN o.expires_at <= statement_timestamp() THEN 'expired' ELSE 'open' END) AS x
  FROM core10.control_overrides_v1 o WHERE o.business_id = p_business ORDER BY o.id DESC LIMIT 100) q;
 RETURN res;
END $$;

-- Members: how many approval stages the Owner requires for a feature, and which approval policy
-- key it maps to. The approval engine consults this when it opens a route.
CREATE FUNCTION core10.control_approval_binding_v1(p_business bigint, p_feature text, p_site bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE v_tenant bigint; r jsonb; c core10.control_catalog_v1%ROWTYPE;
BEGIN
 SELECT tenant_id INTO v_tenant FROM core10.businesses WHERE id = p_business;
 IF v_tenant IS NULL OR core10.actor_uid() IS NULL OR NOT core10.can_see_business(v_tenant, p_business) THEN
  RAISE EXCEPTION 'CONTROL_SCOPE';
 END IF;
 IF p_site IS NOT NULL AND NOT EXISTS (SELECT 1 FROM core10.sites s
    WHERE s.id = p_site AND s.business_id = p_business AND s.tenant_id = v_tenant) THEN
  RAISE EXCEPTION 'CONTROL_SCOPE';
 END IF;
 r := core10._control_resolve_v1(p_business, p_feature, p_site);
 SELECT * INTO c FROM core10.control_catalog_v1 WHERE feature_key = p_feature;
 RETURN jsonb_build_object('feature_key', p_feature, 'enabled', (r->>'enabled')::boolean,
  'required', (r->>'stages')::int > 0, 'stages', (r->>'stages')::int,
  'approval_domain', c.approval_domain, 'approval_action', c.approval_action, 'version', (r->>'version')::int);
END $$;

REVOKE EXECUTE ON FUNCTION
 core10.control_set_v1(bigint, bigint, text, boolean, smallint, jsonb, timestamptz, boolean, integer, text, text),
 core10.control_revert_v1(bigint, bigint, text, integer, integer, text, text),
 core10.control_grant_override_v1(bigint, bigint, text, integer, text, text),
 core10.control_revoke_override_v1(bigint, bigint, text, text),
 core10.control_read_v1(bigint, bigint),
 core10.control_history_v1(bigint, text, integer),
 core10.control_overrides_v1(bigint),
 core10.control_approval_binding_v1(bigint, text, bigint)
 FROM PUBLIC;
GRANT EXECUTE ON FUNCTION
 core10.control_set_v1(bigint, bigint, text, boolean, smallint, jsonb, timestamptz, boolean, integer, text, text),
 core10.control_revert_v1(bigint, bigint, text, integer, integer, text, text),
 core10.control_grant_override_v1(bigint, bigint, text, integer, text, text),
 core10.control_revoke_override_v1(bigint, bigint, text, text),
 core10.control_read_v1(bigint, bigint),
 core10.control_history_v1(bigint, text, integer),
 core10.control_overrides_v1(bigint),
 core10.control_approval_binding_v1(bigint, text, bigint)
 TO authenticated;
