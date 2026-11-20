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
