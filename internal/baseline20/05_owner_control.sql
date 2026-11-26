-- CORE10 baseline20 v1; ordered, lossless consolidation. Fresh empty schema only.
-- CORE10 BASELINE SOURCE 0100_np02_control_tables.up.sql SHA256 eae67a48e947b6f8f4bffefa22ae896c7fd64aacc55fbe90ab45d31e229b1111
-- NP02 / B-010 / 0100: Canonical Owner Control port, storage (DEC-08).
-- One catalog of controllable features, an append-only version history per business/site,
-- one-time Owner exceptions, and a registry that maps every state-changing RPC to a feature.
-- Tables are closed: access is only through the SECURITY DEFINER RPCs of 0101.
-- Integrity invariants (audit immutability, tenant isolation, access expiry/revoke) are catalog
-- rows flagged invariant=true: they are visible to the Owner but can never be switched off.

CREATE TABLE core10.control_catalog_v1 (
 feature_key text PRIMARY KEY
  CHECK (feature_key ~ '^[a-z][a-z0-9_]{1,40}(\.[a-z][a-z0-9_]{1,60}){1,3}$'),
 title_en text NOT NULL CHECK (length(btrim(title_en)) BETWEEN 3 AND 120),
 title_bn text NOT NULL CHECK (length(btrim(title_bn)) BETWEEN 2 AND 160),
 pack text NOT NULL CHECK (pack ~ '^NP[0-9]{2}[A-C]?$'),
 invariant boolean NOT NULL DEFAULT false,
 default_enabled boolean NOT NULL,
 default_stages smallint NOT NULL DEFAULT 0 CHECK (default_stages BETWEEN 0 AND 5),
 max_stages smallint NOT NULL DEFAULT 5 CHECK (max_stages BETWEEN 0 AND 5),
 allow_site_scope boolean NOT NULL DEFAULT true,
 approval_domain text CHECK (approval_domain ~ '^[a-z][a-z0-9_]{1,63}$'),
 approval_action text CHECK (approval_action ~ '^[a-z][a-z0-9_]{1,63}$'),
 params jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(params)='object'),
 status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','retired')),
 created_at timestamptz NOT NULL DEFAULT now(),
 CHECK (default_stages <= max_stages),
 CHECK (NOT invariant OR (default_enabled AND default_stages=0 AND max_stages=0)),
 CHECK ((approval_domain IS NULL) = (approval_action IS NULL))
);

-- Parameter descriptors: {"name":{"type":"int|numeric|text|bool|enum","default":..,"min":..,"max":..,
-- "maxlen":..,"values":[..]}}. Validated when a catalog row is written and when a setting is stored.
CREATE FUNCTION core10._control_schema_ok_v1(p jsonb) RETURNS boolean
LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog,core10 AS $$
DECLARE k text; d jsonb; t text;
BEGIN
 IF p IS NULL OR jsonb_typeof(p) IS DISTINCT FROM 'object' THEN RETURN false; END IF;
 FOR k,d IN SELECT key,value FROM jsonb_each(p) LOOP
  IF k !~ '^[a-z][a-z0-9_]{0,47}$' OR jsonb_typeof(d) IS DISTINCT FROM 'object' THEN RETURN false; END IF;
  t := d->>'type';
  IF t IS NULL OR t NOT IN ('int','numeric','text','bool','enum') OR NOT (d ? 'default') THEN RETURN false; END IF;
  IF t IN ('int','numeric') THEN
   IF jsonb_typeof(d->'default') IS DISTINCT FROM 'number'
    OR jsonb_typeof(d->'min') IS DISTINCT FROM 'number'
    OR jsonb_typeof(d->'max') IS DISTINCT FROM 'number' THEN RETURN false; END IF;
   IF (d->>'min')::numeric > (d->>'max')::numeric
    OR (d->>'default')::numeric < (d->>'min')::numeric
    OR (d->>'default')::numeric > (d->>'max')::numeric THEN RETURN false; END IF;
   IF t='int' AND ((d->>'default')::numeric <> trunc((d->>'default')::numeric)
    OR (d->>'min')::numeric <> trunc((d->>'min')::numeric)
    OR (d->>'max')::numeric <> trunc((d->>'max')::numeric)) THEN RETURN false; END IF;
  ELSIF t='bool' THEN
   IF jsonb_typeof(d->'default') IS DISTINCT FROM 'boolean' THEN RETURN false; END IF;
  ELSIF t='text' THEN
   IF jsonb_typeof(d->'default') IS DISTINCT FROM 'string'
    OR length(d->>'default') > coalesce((d->>'maxlen')::int,200) THEN RETURN false; END IF;
  ELSE
   IF jsonb_typeof(d->'values') IS DISTINCT FROM 'array' OR jsonb_array_length(d->'values') < 1
    OR jsonb_typeof(d->'default') IS DISTINCT FROM 'string'
    OR NOT ((d->'values') @> jsonb_build_array(d->'default')) THEN RETURN false; END IF;
  END IF;
 END LOOP;
 RETURN true;
END $$;
REVOKE EXECUTE ON FUNCTION core10._control_schema_ok_v1(jsonb) FROM PUBLIC, authenticated;

ALTER TABLE core10.control_catalog_v1
 ADD CONSTRAINT control_catalog_params_ok CHECK (core10._control_schema_ok_v1(params));

CREATE TABLE core10.control_setting_versions_v1 (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL,
 business_id bigint NOT NULL,
 site_id bigint,
 feature_key text NOT NULL REFERENCES core10.control_catalog_v1(feature_key),
 version integer NOT NULL CHECK (version > 0),
 enabled boolean NOT NULL,
 stages smallint NOT NULL CHECK (stages BETWEEN 0 AND 5),
 params jsonb NOT NULL CHECK (jsonb_typeof(params)='object'),
 inherit boolean NOT NULL DEFAULT false,
 effective_from timestamptz NOT NULL,
 reverted_from integer CHECK (reverted_from IS NULL OR reverted_from > 0),
 reason text NOT NULL CHECK (length(btrim(reason)) BETWEEN 5 AND 500),
 request_key text NOT NULL CHECK (request_key ~ '^[A-Za-z0-9_-]{8,128}$'),
 payload_sha256 text NOT NULL CHECK (payload_sha256 ~ '^[0-9a-f]{64}$'),
 created_by uuid NOT NULL,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 audit_event_id bigint NOT NULL REFERENCES core10.canonical_audit_events_v1(id),
 CHECK (NOT inherit OR site_id IS NOT NULL),
 UNIQUE (business_id, request_key),
 FOREIGN KEY (business_id, tenant_id) REFERENCES core10.businesses(id, tenant_id),
 FOREIGN KEY (site_id, tenant_id, business_id) REFERENCES core10.sites(id, tenant_id, business_id)
);
CREATE UNIQUE INDEX control_versions_scope_ux
 ON core10.control_setting_versions_v1 (business_id, COALESCE(site_id, 0), feature_key, version);
CREATE INDEX control_versions_resolve_ix
 ON core10.control_setting_versions_v1 (business_id, feature_key, site_id, effective_from DESC, version DESC);

CREATE TABLE core10.control_overrides_v1 (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL,
 business_id bigint NOT NULL,
 site_id bigint,
 feature_key text NOT NULL REFERENCES core10.control_catalog_v1(feature_key),
 reason text NOT NULL CHECK (length(btrim(reason)) BETWEEN 5 AND 500),
 request_key text NOT NULL CHECK (request_key ~ '^[A-Za-z0-9_-]{8,128}$'),
 granted_by uuid NOT NULL,
 granted_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 expires_at timestamptz NOT NULL,
 consumed_at timestamptz,
 consumed_by uuid,
 revoked_at timestamptz,
 revoked_by uuid,
 revoke_request_key text CHECK (revoke_request_key ~ '^[A-Za-z0-9_-]{8,128}$'),
 CHECK (expires_at > granted_at),
 CHECK ((consumed_at IS NULL) = (consumed_by IS NULL)),
 CHECK ((revoked_at IS NULL) = (revoked_by IS NULL)),
 CHECK (consumed_at IS NULL OR revoked_at IS NULL),
 UNIQUE (business_id, request_key),
 FOREIGN KEY (business_id, tenant_id) REFERENCES core10.businesses(id, tenant_id),
 FOREIGN KEY (site_id, tenant_id, business_id) REFERENCES core10.sites(id, tenant_id, business_id)
);
CREATE INDEX control_overrides_open_ix
 ON core10.control_overrides_v1 (business_id, feature_key) WHERE consumed_at IS NULL AND revoked_at IS NULL;

-- Every state-changing RPC (VOLATILE and executable by authenticated) must have one row here.
--   enforced : the RPC calls core10.control_check_v1 for the named feature
--   exempt   : not a business feature (for example Auth-port administration); reason required
--   pending  : feature binding still to be connected; lane and board row required
CREATE TABLE core10.control_rpc_map_v1 (
 rpc_name text PRIMARY KEY CHECK (rpc_name ~ '^[a-z][a-z0-9_]{1,80}$'),
 status text NOT NULL CHECK (status IN ('enforced','exempt','pending')),
 feature_key text REFERENCES core10.control_catalog_v1(feature_key),
 reason text NOT NULL CHECK (length(btrim(reason)) BETWEEN 10 AND 300),
 lane text NOT NULL CHECK (length(btrim(lane)) BETWEEN 2 AND 40),
 board_row text CHECK (board_row ~ '^B-[0-9]{3}$'),
 CHECK (status <> 'enforced' OR feature_key IS NOT NULL),
 CHECK (status <> 'pending' OR (board_row IS NOT NULL AND feature_key IS NOT NULL))
);

CREATE FUNCTION core10._control_history_guard_v1() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog,core10 AS $$
BEGIN
 RAISE EXCEPTION 'control_history_immutable' USING ERRCODE='42501';
END $$;
REVOKE EXECUTE ON FUNCTION core10._control_history_guard_v1() FROM PUBLIC, authenticated;

CREATE TRIGGER control_versions_immutable_v1
 BEFORE UPDATE OR DELETE ON core10.control_setting_versions_v1
 FOR EACH ROW EXECUTE FUNCTION core10._control_history_guard_v1();
CREATE TRIGGER control_versions_truncate_guard_v1
 BEFORE TRUNCATE ON core10.control_setting_versions_v1
 FOR EACH STATEMENT EXECUTE FUNCTION core10._control_history_guard_v1();
CREATE TRIGGER control_overrides_truncate_guard_v1
 BEFORE TRUNCATE ON core10.control_overrides_v1
 FOR EACH STATEMENT EXECUTE FUNCTION core10._control_history_guard_v1();

-- An override may only move once from open to consumed, or from open to revoked.
CREATE FUNCTION core10._control_override_guard_v1() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog,core10 AS $$
BEGIN
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'control_history_immutable' USING ERRCODE='42501'; END IF;
 IF (NEW.id,NEW.tenant_id,NEW.business_id,NEW.site_id,NEW.feature_key,NEW.reason,NEW.request_key,
     NEW.granted_by,NEW.granted_at,NEW.expires_at)
    IS DISTINCT FROM
    (OLD.id,OLD.tenant_id,OLD.business_id,OLD.site_id,OLD.feature_key,OLD.reason,OLD.request_key,
     OLD.granted_by,OLD.granted_at,OLD.expires_at)
  OR OLD.consumed_at IS NOT NULL OR OLD.revoked_at IS NOT NULL
 THEN RAISE EXCEPTION 'control_history_immutable' USING ERRCODE='42501'; END IF;
 RETURN NEW;
END $$;
REVOKE EXECUTE ON FUNCTION core10._control_override_guard_v1() FROM PUBLIC, authenticated;
CREATE TRIGGER control_overrides_guard_v1
 BEFORE UPDATE OR DELETE ON core10.control_overrides_v1
 FOR EACH ROW EXECUTE FUNCTION core10._control_override_guard_v1();

ALTER TABLE core10.control_catalog_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE core10.control_setting_versions_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE core10.control_overrides_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE core10.control_rpc_map_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON core10.control_catalog_v1 FROM PUBLIC;
REVOKE ALL ON core10.control_setting_versions_v1 FROM PUBLIC;
REVOKE ALL ON core10.control_overrides_v1 FROM PUBLIC;
REVOKE ALL ON core10.control_rpc_map_v1 FROM PUBLIC;
INSERT INTO core10.schema_migrations(version,name,checksum) VALUES(100,'0100_np02_control_tables','eae67a48e947b6f8f4bffefa22ae896c7fd64aacc55fbe90ab45d31e229b1111');

-- CORE10 BASELINE SOURCE 0101_np02_control_rpc.up.sql SHA256 735eaca151a8889660f6399d1abe9b3a9a7fe60ead0b2daefb6b03dfa4dbba47
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
INSERT INTO core10.schema_migrations(version,name,checksum) VALUES(101,'0101_np02_control_rpc','735eaca151a8889660f6399d1abe9b3a9a7fe60ead0b2daefb6b03dfa4dbba47');

-- CORE10 BASELINE SOURCE 0102_np02_control_seed.up.sql SHA256 882a98ac159d80e45f53896cc4b31f0c0fd443f784466fc335cdc4c092a78ea7
-- NP02 / B-010 / 0102: initial Control catalog and the RPC registry (DEC-08).
-- Later packs add their own features in their own migration block with plain INSERTs here;
-- a feature without a catalog row cannot be controlled and so is not finished.

INSERT INTO core10.control_catalog_v1(feature_key,title_en,title_bn,pack,invariant,default_enabled,
 default_stages,max_stages,allow_site_scope,approval_domain,approval_action,params) VALUES
 ('audit.immutability','Audit and approval history cannot be altered','অডিট ও অনুমোদনের ইতিহাস বদলানো যায় না','NP01',true,true,0,0,false,NULL,NULL,'{}'),
 ('tenant.isolation','Each tenant sees only its own data','প্রতিটি প্রতিষ্ঠান শুধু নিজের তথ্য দেখে','NP01',true,true,0,0,false,NULL,NULL,'{}'),
 ('access.expiry_revocation','Expired or revoked access stops at once','মেয়াদ শেষ বা বাতিল অনুমতি সঙ্গে সঙ্গে বন্ধ','NP01',true,true,0,0,false,NULL,NULL,'{}'),
 ('gov002.approval_policy','Publish approval policies','অনুমোদন নীতি প্রকাশ','NP01',false,true,0,0,true,NULL,NULL,
  '{"ttl_minutes":{"type":"int","min":5,"max":43200,"default":1440}}'),
 ('gov002.review','Routed review of approval requests','অনুমোদন আবেদনের ধাপে ধাপে পর্যালোচনা','NP01',false,true,1,5,true,NULL,NULL,
  '{"exception_escalation":{"type":"bool","default":true}}'),
 ('gov003.review_export','Audit readiness, risk review and export','অডিট প্রস্তুতি, ঝুঁকি পর্যালোচনা ও রপ্তানি','NP01',false,false,0,5,true,NULL,NULL,
  '{"max_rows":{"type":"int","min":1,"max":10000,"default":1000},"metadata_only":{"type":"bool","default":true}}'),
 ('setup001.profile_preview','Preview a business setup profile','ব্যবসার সেটআপ প্রোফাইল প্রিভিউ','NP01',false,true,0,0,false,NULL,NULL,'{}'),
 ('setup001.provision','Create and activate a business or site','ব্যবসা বা সাইট তৈরি ও চালু','NP01',false,true,0,5,false,NULL,NULL,
  '{"max_sites":{"type":"int","min":1,"max":1000,"default":50}}'),
 ('inventory.stock_event','Post stock events','স্টক ইভেন্ট পোস্ট','NP03A',false,true,0,5,true,'inventory','adjust',
  '{"allow_negative_stock":{"type":"bool","default":false},"max_adjust_qty":{"type":"numeric","min":0,"max":1000000,"default":1000}}');

INSERT INTO core10.control_rpc_map_v1(rpc_name,status,feature_key,reason,lane,board_row) VALUES
 ('build01_set_access_v1','exempt',NULL,'Auth-port administration: grants and revokes access; Owner authority checked by can_manage and audited','ChatGPT','B-004'),
 ('change_access_v1','exempt',NULL,'Auth-port administration: changes access; Owner authority checked and audited','ChatGPT','B-004'),
 ('build02a_set_approval_policy_v1','exempt',NULL,'Auth-port administration: sets which roles may use approval actions','ChatGPT','B-004'),
 ('control_set_v1','exempt',NULL,'Control-port self-administration: Owner only, versioned and audited; cannot change invariants','Claude','B-010'),
 ('control_revert_v1','exempt',NULL,'Control-port self-administration: Owner only, restores an earlier version as a new version','Claude','B-010'),
 ('control_grant_override_v1','exempt',NULL,'Control-port self-administration: Owner grants a one-time audited exception','Claude','B-010'),
 ('control_revoke_override_v1','exempt',NULL,'Control-port self-administration: Owner withdraws an unused exception','Claude','B-010'),
 ('build01_setup_v1','pending','setup001.provision','Setup is not yet bound to the provision control; to be connected by the NP01 lane','ChatGPT','B-008'),
 ('build01_site_v1','pending','setup001.provision','Site creation is not yet bound to the provision control','ChatGPT','B-008'),
 ('setup_business_v1','pending','setup001.provision','Business setup is not yet bound to the provision control','ChatGPT','B-008'),
 ('setup_industry_draft_v2','pending','setup001.provision','Industry draft setup is not yet bound to the provision control','ChatGPT','B-008'),
 ('provision_business','pending','setup001.provision','A018 fixture provisioning, superseded by build01_setup_v1; retire with the legacy installer','Claude','B-009'),
 ('provision_site','pending','setup001.provision','A018 fixture provisioning, superseded by build01_site_v1; retire with the legacy installer','Claude','B-009'),
 ('post_stock_event','pending','inventory.stock_event','Stock posting is not yet bound to its control; connects with the inventory command ledger','Claude','B-012'),
 ('publish_approval_policy_v1','pending','gov002.approval_policy','Policy publishing is not yet bound to its control','ChatGPT','B-006'),
 ('configure_approval_route_v1','pending','gov002.review','Route configuration is not yet bound to the review control','ChatGPT','B-006'),
 ('submit_typed_approval_v1','pending','gov002.review','Submission is not yet bound to the review control or its stage count','ChatGPT','B-006'),
 ('decide_approval','pending','gov002.review','Decisions are not yet bound to the review control','ChatGPT','B-006'),
 ('delegate_approval_stage_v1','pending','gov002.review','Delegation is not yet bound to the review control','ChatGPT','B-006'),
 ('revoke_approval_delegation_v1','pending','gov002.review','Delegation revoke is not yet bound to the review control','ChatGPT','B-006'),
 ('withdraw_typed_approval_v1','pending','gov002.review','Withdrawal is not yet bound to the review control','ChatGPT','B-006');
INSERT INTO core10.schema_migrations(version,name,checksum) VALUES(102,'0102_np02_control_seed','882a98ac159d80e45f53896cc4b31f0c0fd443f784466fc335cdc4c092a78ea7');

-- CORE10 BASELINE SOURCE 0103_np02_control_registry_evidence.up.sql SHA256 92825e0a4ccb7982bd73b64295d606faca60ef5e5023fdac4323350ad59032f1
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
INSERT INTO core10.schema_migrations(version,name,checksum) VALUES(103,'0103_np02_control_registry_evidence','92825e0a4ccb7982bd73b64295d606faca60ef5e5023fdac4323350ad59032f1');

-- CORE10 BASELINE SOURCE 0104_np02_control_audit_read.up.sql SHA256 dbe33a2fa2513035980dc2e0e17229244a21db2f4bd5d5ce4d2a01313db7febe
-- NP02 / B-021 / 0104: Owner reads the Control part of the one canonical audit stream.
-- Read only (STABLE). Owners only; members get CONTROL_FORBIDDEN, others CONTROL_SCOPE.
CREATE FUNCTION core10.control_audit_v1(p_business bigint, p_limit integer DEFAULT 100) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE v_tenant bigint; v_events jsonb; v_chain jsonb;
BEGIN
 SELECT tenant_id INTO v_tenant FROM core10.businesses WHERE id = p_business;
 IF v_tenant IS NULL OR core10.actor_uid() IS NULL OR NOT core10.can_see_business(v_tenant, p_business) THEN
  RAISE EXCEPTION 'CONTROL_SCOPE';
 END IF;
 IF NOT core10.can_manage(v_tenant, p_business) THEN RAISE EXCEPTION 'CONTROL_FORBIDDEN'; END IF;
 SELECT coalesce(jsonb_agg(x ORDER BY (x->>'stream_seq')::bigint DESC), '[]'::jsonb) INTO v_events FROM (
  SELECT jsonb_build_object('stream_seq', e.stream_seq, 'action', e.action, 'source_ref', e.source_ref,
   'actor_id', e.actor_id, 'event_at', e.event_at, 'payload', e.payload, 'event_digest', e.event_digest) AS x
  FROM core10.canonical_audit_events_v1 e
  WHERE e.business_id = p_business AND e.source_domain = 'control'
  ORDER BY e.stream_seq DESC LIMIT greatest(1, least(coalesce(p_limit, 100), 200))) q;
 BEGIN
  v_chain := core10.verify_canonical_audit_v1(p_business);
 EXCEPTION WHEN OTHERS THEN
  v_chain := jsonb_build_object('ok', NULL, 'reason', 'chain check not available to this role');
 END;
 RETURN jsonb_build_object('events', v_events, 'chain', v_chain);
END $$;
REVOKE EXECUTE ON FUNCTION core10.control_audit_v1(bigint, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION core10.control_audit_v1(bigint, integer) TO authenticated;
INSERT INTO core10.schema_migrations(version,name,checksum) VALUES(104,'0104_np02_control_audit_read','dbe33a2fa2513035980dc2e0e17229244a21db2f4bd5d5ce4d2a01313db7febe');

-- CORE10 BASELINE SOURCE 0105_np02_control_param_labels.up.sql SHA256 3d7c768b50db0e910d237d7fd99281cd69dddfd9b68f722850b0d41d918563fb
-- NP02 / B-021 / 0105: bilingual labels for the seeded control parameters (descriptor keys label_bn, label_en).
-- Descriptor validation ignores extra keys, so existing settings stay valid.
UPDATE core10.control_catalog_v1 SET params = params
 || jsonb_build_object('ttl_minutes', params->'ttl_minutes' || '{"label_bn":"অনুমোদনের মেয়াদ (মিনিট)","label_en":"Approval validity (minutes)"}')
 WHERE feature_key = 'gov002.approval_policy';
UPDATE core10.control_catalog_v1 SET params = params
 || jsonb_build_object('exception_escalation', params->'exception_escalation' || '{"label_bn":"ব্যতিক্রম ঊর্ধ্বতনের কাছে পাঠানো","label_en":"Escalate exceptions"}')
 WHERE feature_key = 'gov002.review';
UPDATE core10.control_catalog_v1 SET params = params
 || jsonb_build_object('max_rows', params->'max_rows' || '{"label_bn":"সর্বোচ্চ সারি","label_en":"Maximum rows"}',
                       'metadata_only', params->'metadata_only' || '{"label_bn":"শুধু মেটাডেটা","label_en":"Metadata only"}')
 WHERE feature_key = 'gov003.review_export';
UPDATE core10.control_catalog_v1 SET params = params
 || jsonb_build_object('max_sites', params->'max_sites' || '{"label_bn":"সর্বোচ্চ সাইট","label_en":"Maximum sites"}')
 WHERE feature_key = 'setup001.provision';
UPDATE core10.control_catalog_v1 SET params = params
 || jsonb_build_object('allow_negative_stock', params->'allow_negative_stock' || '{"label_bn":"ঋণাত্মক স্টক অনুমতি","label_en":"Allow negative stock"}',
                       'max_adjust_qty', params->'max_adjust_qty' || '{"label_bn":"সর্বোচ্চ সমন্বয় পরিমাণ","label_en":"Maximum adjustment quantity"}')
 WHERE feature_key = 'inventory.stock_event';
INSERT INTO core10.schema_migrations(version,name,checksum) VALUES(105,'0105_np02_control_param_labels','3d7c768b50db0e910d237d7fd99281cd69dddfd9b68f722850b0d41d918563fb');

-- CORE10 BASELINE SOURCE 0106_np02_registry_review_promotion.up.sql SHA256 0c4277da0759179a117b85580873d790d18fd92a01a217e42952fedd363f35e3
-- NP02 / B-023 / 0106: evidence-based registry promotion for the NP01 review bindings (ChatGPT 0019).
-- Promotes only where the RPC calls control_check_v1 for gov002.review; otherwise the rows stay pending.
-- Proof test: tests/migrations/np01-control-decision-e2e.sql (CONTROL_DISABLED on decide and withdraw when off).
DO $$
BEGIN
 RAISE NOTICE 'registry decide_approval: %',
  core10._control_registry_promote_v1('decide_approval', 'tests/migrations/np01-control-decision-e2e.sql');
 RAISE NOTICE 'registry withdraw_typed_approval_v1: %',
  core10._control_registry_promote_v1('withdraw_typed_approval_v1', 'tests/migrations/np01-control-decision-e2e.sql');
END $$;
INSERT INTO core10.schema_migrations(version,name,checksum) VALUES(106,'0106_np02_registry_review_promotion','0c4277da0759179a117b85580873d790d18fd92a01a217e42952fedd363f35e3');
