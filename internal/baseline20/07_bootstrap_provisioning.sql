-- CORE10 baseline20 v1; ordered, lossless consolidation. Fresh empty schema only.
-- CORE10 BASELINE SOURCE 0115_np01_bootstrap_policy_provider.up.sql SHA256 5885cad794d7eb2d0fb6bea1bf7a8fc6726f15dce8534bfc149a235756f51be0
-- D063 / REV-016: tenant policy and audit provider for the provisioning cutover.
-- The tenant's canonical ID identifies its scope even before a Business exists.
-- A tenant present before this migration requires a separately reviewed backfill.
ALTER TABLE core10.tenants ADD COLUMN bootstrap_policy_initialized boolean NOT NULL DEFAULT false;
ALTER TABLE core10.tenants ALTER COLUMN bootstrap_policy_initialized SET DEFAULT true;

ALTER TABLE core10.audit_chain_heads_v1
 DROP CONSTRAINT audit_chain_heads_v1_pkey,
 ALTER COLUMN business_id DROP NOT NULL,
 ADD CONSTRAINT audit_chain_heads_business_unique_v1 UNIQUE (business_id),
 ADD CONSTRAINT audit_chain_heads_tenant_fk_v1 FOREIGN KEY (tenant_id) REFERENCES core10.tenants(id);
CREATE UNIQUE INDEX audit_chain_heads_tenant_scope_v1
 ON core10.audit_chain_heads_v1 (tenant_id) WHERE business_id IS NULL;

ALTER TABLE core10.canonical_audit_events_v1
 ALTER COLUMN business_id DROP NOT NULL,
 ADD CONSTRAINT canonical_audit_tenant_fk_v1 FOREIGN KEY (tenant_id) REFERENCES core10.tenants(id);
CREATE UNIQUE INDEX canonical_audit_tenant_seq_v1
 ON core10.canonical_audit_events_v1 (tenant_id, stream_seq) WHERE business_id IS NULL;
CREATE UNIQUE INDEX canonical_audit_tenant_source_v1
 ON core10.canonical_audit_events_v1 (tenant_id, source_domain, source_ref) WHERE business_id IS NULL;
CREATE UNIQUE INDEX canonical_audit_tenant_request_v1
 ON core10.canonical_audit_events_v1 (tenant_id, request_key) WHERE business_id IS NULL;
CREATE POLICY canonical_audit_tenant_owner_read_v1 ON core10.canonical_audit_events_v1
 FOR SELECT TO authenticated USING (business_id IS NULL AND core10.can_tenant(tenant_id));

ALTER TABLE core10.control_setting_versions_v1
 ALTER COLUMN business_id DROP NOT NULL,
 ADD CONSTRAINT control_setting_versions_tenant_fk_v1 FOREIGN KEY (tenant_id) REFERENCES core10.tenants(id),
 ADD CONSTRAINT control_setting_versions_bootstrap_scope_v1 CHECK (
  business_id IS NOT NULL OR (
   site_id IS NULL AND feature_key = 'setup001.provision' AND stages = 0
   AND params = '{}'::jsonb AND NOT inherit AND reverted_from IS NULL
  )
 );
CREATE UNIQUE INDEX control_bootstrap_version_v1
 ON core10.control_setting_versions_v1 (tenant_id, feature_key, version) WHERE business_id IS NULL;
CREATE UNIQUE INDEX control_bootstrap_request_v1
 ON core10.control_setting_versions_v1 (tenant_id, request_key) WHERE business_id IS NULL;
CREATE INDEX control_bootstrap_effective_v1
 ON core10.control_setting_versions_v1 (tenant_id, effective_from DESC, version DESC)
 WHERE business_id IS NULL AND feature_key = 'setup001.provision';

-- Every future provisioning consumer must acquire this lock before its receipt,
-- Business/site and audit locks. VOLATILE statements following the wait get a
-- fresh snapshot under READ COMMITTED. Reject isolation with a fixed snapshot.
CREATE FUNCTION core10._lock_bootstrap_policy_v1(p_tenant bigint) RETURNS void
LANGUAGE plpgsql VOLATILE SET search_path = pg_catalog, core10 AS $$
BEGIN
 IF NOT core10.can_tenant(p_tenant) THEN
  RAISE EXCEPTION 'BOOTSTRAP_POLICY_DENIED' USING ERRCODE = '42501';
 END IF;
 IF current_setting('transaction_isolation') <> 'read committed' THEN
  RAISE EXCEPTION 'BOOTSTRAP_READ_COMMITTED_REQUIRED' USING ERRCODE = '25001';
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('core10:bootstrap:' || p_tenant::text, 0));
 IF NOT core10.can_tenant(p_tenant) THEN
  RAISE EXCEPTION 'BOOTSTRAP_POLICY_DENIED' USING ERRCODE = '42501';
 END IF;
 IF NOT EXISTS (SELECT 1 FROM core10.tenants WHERE id = p_tenant AND bootstrap_policy_initialized) THEN
  RAISE EXCEPTION 'BOOTSTRAP_POLICY_UNINITIALIZED' USING ERRCODE = '42501';
 END IF;
END $$;

-- Domain-separated digest for tenant streams in the canonical audit journal.
-- Existing Business stream hashes, verifier and append API keep their format.
CREATE FUNCTION core10._append_bootstrap_audit_v1(
 p_tenant bigint, p_version integer, p_actor uuid, p_key text, p_payload jsonb
) RETURNS bigint LANGUAGE plpgsql VOLATILE SET search_path = pg_catalog, core10 AS $$
DECLARE
 h core10.audit_chain_heads_v1%ROWTYPE;
 v_sha text;
 v_digest text;
 v_at timestamptz := clock_timestamp();
 v_seq bigint;
 v_event bigint;
BEGIN
 INSERT INTO core10.audit_chain_heads_v1 (tenant_id)
 VALUES (p_tenant) ON CONFLICT (tenant_id) WHERE business_id IS NULL DO NOTHING;
 SELECT * INTO STRICT h FROM core10.audit_chain_heads_v1
 WHERE tenant_id = p_tenant AND business_id IS NULL FOR UPDATE;

 v_seq := h.last_seq + 1;
 v_sha := encode(sha256(convert_to(p_payload::text, 'UTF8')), 'hex');
 v_digest := encode(sha256(convert_to(jsonb_build_array(
  'c10-audit-tenant-v1', h.last_digest, p_tenant, v_seq, 'control', p_version,
  'control.bootstrap_setting_changed', p_actor, p_key, v_sha,
  to_char(v_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
 )::text, 'UTF8')), 'hex');

 INSERT INTO core10.canonical_audit_events_v1 (
  tenant_id, stream_seq, source_domain, source_ref, action, actor_id,
  request_key, payload, payload_sha256, prior_digest, event_digest, event_at
 ) VALUES (
  p_tenant, v_seq, 'control', 'bootstrap:v' || p_version,
  'control.bootstrap_setting_changed', p_actor, p_key, p_payload, v_sha, h.last_digest, v_digest, v_at
 ) RETURNING id INTO v_event;
 UPDATE core10.audit_chain_heads_v1 SET last_seq = v_seq, last_digest = v_digest
 WHERE tenant_id = p_tenant AND business_id IS NULL;
 RETURN v_event;
END $$;

CREATE FUNCTION core10._bootstrap_policy_decision_v1(p_tenant bigint) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SET search_path = pg_catalog, core10 AS $$
DECLARE
 v_now timestamptz;
 v_setting core10.control_setting_versions_v1%ROWTYPE;
BEGIN
 PERFORM core10._lock_bootstrap_policy_v1(p_tenant);
 v_now := clock_timestamp();
 SELECT * INTO v_setting FROM core10.control_setting_versions_v1
 WHERE tenant_id = p_tenant AND business_id IS NULL AND feature_key = 'setup001.provision'
   AND effective_from <= v_now
 ORDER BY effective_from DESC, version DESC LIMIT 1;
 RETURN jsonb_build_object(
  'tenant_id', p_tenant, 'feature_key', 'setup001.provision',
  'enabled', coalesce(v_setting.enabled, false), 'version', coalesce(v_setting.version, 0),
  'decision_at', v_now, 'audit_event_id', v_setting.audit_event_id
 );
END $$;

CREATE FUNCTION core10._set_bootstrap_policy_v1(
 p_tenant bigint, p_enabled boolean, p_effective_at timestamptz,
 p_expected_version integer, p_reason text, p_request_key text
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SET search_path = pg_catalog, core10 AS $$
DECLARE
 v_actor uuid;
 v_now timestamptz;
 v_effective timestamptz;
 v_hash text;
 v_version integer;
 v_audit bigint;
 v_row core10.control_setting_versions_v1%ROWTYPE;
BEGIN
 PERFORM core10._lock_bootstrap_policy_v1(p_tenant);
 v_actor := core10.actor_uid();
 IF p_enabled IS NULL OR p_expected_version IS NULL OR p_expected_version < 0
   OR p_reason IS NULL OR length(btrim(p_reason)) NOT BETWEEN 5 AND 500
   OR p_request_key IS NULL OR p_request_key !~ '^[A-Za-z0-9_-]{8,128}$'
   OR (p_effective_at IS NOT NULL AND NOT isfinite(p_effective_at)) THEN
  RAISE EXCEPTION 'BOOTSTRAP_POLICY_INVALID_INPUT' USING ERRCODE = '22023';
 END IF;
 v_hash := encode(sha256(convert_to(jsonb_build_array(
  v_actor, p_enabled, extract(epoch FROM p_effective_at), p_expected_version, btrim(p_reason)
 )::text, 'UTF8')), 'hex');
 SELECT * INTO v_row FROM core10.control_setting_versions_v1
 WHERE tenant_id = p_tenant AND business_id IS NULL AND request_key = p_request_key;
 IF FOUND THEN
  IF v_row.payload_sha256 <> v_hash THEN
   RAISE EXCEPTION 'CONTROL_REPLAY_CONFLICT';
  END IF;
  RETURN core10._control_row_json_v1(v_row, true);
 END IF;

 v_now := clock_timestamp();
 v_effective := coalesce(p_effective_at, v_now);
 IF v_effective < v_now OR v_effective > v_now + interval '366 days' THEN
  RAISE EXCEPTION 'BOOTSTRAP_POLICY_INVALID_EFFECTIVE_TIME' USING ERRCODE = '22023';
 END IF;
 SELECT coalesce(max(version), 0) INTO v_version FROM core10.control_setting_versions_v1
 WHERE tenant_id = p_tenant AND business_id IS NULL AND feature_key = 'setup001.provision';
 IF p_expected_version <> v_version THEN
  RAISE EXCEPTION 'CONTROL_STALE_VERSION:%', v_version;
 END IF;
 v_version := v_version + 1;
 v_audit := core10._append_bootstrap_audit_v1(
  p_tenant, v_version, v_actor, 'control:' || p_request_key,
  jsonb_build_object('feature_key', 'setup001.provision', 'scope', 'tenant', 'tenant_id', p_tenant,
   'version', v_version, 'enabled', p_enabled, 'effective_from', v_effective,
   'reason', btrim(p_reason), 'authorization', 'tenant_owner', 'operation_sha256', v_hash)
 );
 INSERT INTO core10.control_setting_versions_v1 (
  tenant_id, feature_key, version, enabled, stages, params, effective_from, reason,
  request_key, payload_sha256, created_by, audit_event_id
 ) VALUES (
  p_tenant, 'setup001.provision', v_version, p_enabled, 0, '{}'::jsonb, v_effective, btrim(p_reason),
  p_request_key, v_hash, v_actor, v_audit
 ) RETURNING * INTO v_row;
 RETURN core10._control_row_json_v1(v_row, false);
END $$;

-- The provider is private until the public provisioning RPCs and their registry
-- proofs switch over together. Existing Business Control keeps its own scope.
REVOKE ALL ON FUNCTION core10._lock_bootstrap_policy_v1(bigint),
 core10._append_bootstrap_audit_v1(bigint, integer, uuid, text, jsonb),
 core10._bootstrap_policy_decision_v1(bigint),
 core10._set_bootstrap_policy_v1(bigint, boolean, timestamptz, integer, text, text)
 FROM PUBLIC, authenticated;
INSERT INTO core10.schema_migrations(version,name,checksum) VALUES(115,'0115_np01_bootstrap_policy_provider','5885cad794d7eb2d0fb6bea1bf7a8fc6726f15dce8534bfc149a235756f51be0');

-- CORE10 BASELINE SOURCE 0116_np01_bootstrap_provisioning.up.sql SHA256 84dcb3b2eab734e63f5e5189e63df309f790aee3245351e08c0bb85e0bd0c38d
-- D063: cut over signed Business creation RPCs together. Restore no access
-- through a legacy entrypoint while the canonical setup engines are private.
ALTER FUNCTION core10.setup_business_v1(bigint,text,text,text,text,jsonb,text,text)
 RENAME TO _setup_business_write_v1;
ALTER FUNCTION core10.setup_industry_draft_v2(bigint,text,text,text,text,jsonb,jsonb,text,text)
 RENAME TO _setup_industry_write_v2;

REVOKE ALL ON FUNCTION core10._setup_business_write_v1(bigint,text,text,text,text,jsonb,text,text),
 core10._setup_industry_write_v2(bigint,text,text,text,text,jsonb,jsonb,text,text),
 core10.provision_business(bigint,text,text,text) FROM PUBLIC, authenticated;

-- Use a distinct four-argument signature so existing Business-scoped calls
-- continue resolving to the original canonical Control RPC.
CREATE FUNCTION core10.control_check_v1(p_tenant bigint,p_feature text,p_site bigint,p_scope text)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog,core10 AS $$
DECLARE decision jsonb;
BEGIN
 IF p_feature IS DISTINCT FROM 'setup001.provision' OR p_site IS NOT NULL
    OR p_scope IS DISTINCT FROM 'tenant' THEN
  RAISE EXCEPTION 'CONTROL_SCOPE';
 END IF;
 decision := core10._bootstrap_policy_decision_v1(p_tenant);
 IF decision->>'enabled' IS DISTINCT FROM 'true' THEN
  RAISE EXCEPTION 'CONTROL_DISABLED:setup001.provision' USING ERRCODE='42501';
 END IF;
 RETURN decision;
END $$;

-- Resolve the legal entity server-side, then recheck it after the policy lock.
CREATE FUNCTION core10._bootstrap_legal_tenant_v1(p_legal bigint) RETURNS bigint
LANGUAGE plpgsql STABLE SET search_path=pg_catalog,core10 AS $$
DECLARE tenant bigint;
BEGIN
 SELECT tenant_id INTO tenant FROM core10.legal_entities WHERE id=p_legal;
 IF tenant IS NULL OR NOT core10.can_tenant(tenant) THEN
  RAISE EXCEPTION 'BUILD01_SETUP_DENIED' USING ERRCODE='42501';
 END IF;
 RETURN tenant;
END $$;

CREATE FUNCTION core10._record_bootstrap_setup_v1(
 p_tenant bigint,p_business bigint,p_request text,p_decision jsonb
) RETURNS void LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog,core10 AS $$
DECLARE receipt core10.business_setup_runs_v1%ROWTYPE;
BEGIN
 SELECT * INTO STRICT receipt FROM core10.business_setup_runs_v1
 WHERE tenant_id=p_tenant AND business_id=p_business AND request_key=p_request;
 IF EXISTS (SELECT 1 FROM core10.canonical_audit_events_v1
            WHERE business_id=p_business AND source_domain='bootstrap_setup'
              AND source_ref=receipt.id::text) THEN
  RETURN;
 END IF;
 -- For an older completed run, this records its first checked access after
 -- cutover. The action and decision timestamp do not attest past creation.
 PERFORM core10._append_canonical_audit_v1(p_tenant,p_business,'bootstrap_setup',receipt.id::text,
  'setup.bootstrap_access_checked',core10.actor_uid(),'bootstrap:setup:'||receipt.id,
  jsonb_build_object('tenant_id',p_tenant,'business_id',p_business,'setup_run_id',receipt.id,
   'decision',p_decision,'operation_sha256',encode(sha256(convert_to(receipt.payload::text,'UTF8')),'hex')));
END $$;

CREATE FUNCTION core10.setup_business_v1(
 p_legal bigint,p_slug text,p_template text,p_display_name text,
 p_mode text,p_sites jsonb,p_request text,p_brand_hex text
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE tenant bigint; business bigint; decision jsonb;
BEGIN
 tenant:=core10._bootstrap_legal_tenant_v1(p_legal);
 decision:=core10.control_check_v1(tenant,'setup001.provision',NULL,'tenant');
 IF core10._bootstrap_legal_tenant_v1(p_legal)<>tenant THEN RAISE EXCEPTION 'BUILD01_SETUP_DENIED'; END IF;
 business:=core10._setup_business_write_v1(p_legal,p_slug,p_template,p_display_name,p_mode,p_sites,p_request,p_brand_hex);
 PERFORM core10._record_bootstrap_setup_v1(tenant,business,p_request,decision);
 RETURN business;
END $$;

CREATE FUNCTION core10.setup_industry_draft_v2(
 p_legal bigint,p_slug text,p_template_id text,p_display_name text,p_mode text,
 p_sites jsonb,p_modules jsonb,p_request text,p_brand_hex text
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE tenant bigint; business bigint; decision jsonb;
BEGIN
 tenant:=core10._bootstrap_legal_tenant_v1(p_legal);
 decision:=core10.control_check_v1(tenant,'setup001.provision',NULL,'tenant');
 IF core10._bootstrap_legal_tenant_v1(p_legal)<>tenant THEN RAISE EXCEPTION 'BUILD01_SETUP_DENIED'; END IF;
 business:=core10._setup_industry_write_v2(p_legal,p_slug,p_template_id,p_display_name,p_mode,p_sites,p_modules,p_request,p_brand_hex);
 PERFORM core10._record_bootstrap_setup_v1(tenant,business,'industry-v2:'||p_request,decision);
 RETURN business;
END $$;

CREATE OR REPLACE FUNCTION core10.build01_setup_v1(
 p_legal bigint,p_slug text,p_template text,p_display_name text,p_mode text,p_sites jsonb,p_request text,p_brand_hex text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE business bigint; tenant bigint; actor uuid:=core10.actor_uid(); signature jsonb; previous record; event_id bigint; modules jsonb; decision jsonb;
BEGIN
 tenant:=core10._bootstrap_legal_tenant_v1(p_legal);
 decision:=core10.control_check_v1(tenant,'setup001.provision',NULL,'tenant');
 IF core10._bootstrap_legal_tenant_v1(p_legal)<>tenant THEN RAISE EXCEPTION 'BUILD01_SETUP_DENIED'; END IF;
 -- Reuse the original ten-family draft engine. Module selections come only
 -- from its canonical catalog; that engine keeps every module locked/disabled.
 -- Legacy demo-approved template codes retain the existing A020 v1 contract.
 IF EXISTS(SELECT 1 FROM core10.industry_catalog_v2 WHERE id=p_template) THEN
  SELECT COALESCE(jsonb_agg(module_code ORDER BY module_code),'[]'::jsonb) INTO modules
   FROM core10.industry_module_catalog_v2 WHERE industry_id=p_template;
  business:=core10._setup_industry_write_v2(p_legal,p_slug,p_template,p_display_name,p_mode,p_sites,modules,p_request,p_brand_hex);
  PERFORM core10._record_bootstrap_setup_v1(tenant,business,'industry-v2:'||p_request,decision);
 ELSE
  business:=core10._setup_business_write_v1(p_legal,p_slug,p_template,p_display_name,p_mode,p_sites,p_request,p_brand_hex);
  PERFORM core10._record_bootstrap_setup_v1(tenant,business,p_request,decision);
 END IF;
 signature:=jsonb_build_object('legal',p_legal,'slug',p_slug,'template',p_template,'display_name',p_display_name,'mode',p_mode,'sites',p_sites,'request',p_request,'brand_hex',p_brand_hex);
 SELECT * INTO previous FROM core10.access_change_events_v1 WHERE business_id=business AND request_key=p_request;
 IF FOUND THEN
  IF previous.input_signature<>signature OR previous.actor_uid<>actor OR previous.event_kind<>'setup.business' THEN RAISE EXCEPTION 'BUILD01_REQUEST_CONFLICT'; END IF;
  event_id:=previous.id;
 ELSE
  INSERT INTO core10.access_change_events_v1(tenant_id,business_id,request_key,command,subject_uid,input_signature,before_state,after_state,actor_uid,event_kind)
   VALUES(tenant,business,p_request,'setup.business',actor,signature,'{}',jsonb_build_object('business_id',business,'status','draft'),actor,'setup.business') RETURNING id INTO event_id;
 END IF;
 RETURN jsonb_build_object('business_id',business,'request_key',p_request,'event_id',event_id,'status','draft','production_certified',false);
END $$;


-- An existing tenant can opt in through its active Tenant Owner. This is an
-- explicit, audited transition, with no inferred ON or bulk migration.
CREATE FUNCTION core10.control_set_bootstrap_policy_v1(
 p_tenant bigint,p_enabled boolean,p_effective_at timestamptz,p_expected_version integer,p_reason text,p_request_key text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
BEGIN
 IF NOT core10.can_tenant(p_tenant) THEN RAISE EXCEPTION 'BOOTSTRAP_POLICY_DENIED' USING ERRCODE='42501'; END IF;
 IF current_setting('transaction_isolation')<>'read committed' THEN
  RAISE EXCEPTION 'BOOTSTRAP_READ_COMMITTED_REQUIRED' USING ERRCODE='25001';
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('core10:bootstrap:'||p_tenant::text,0));
 IF NOT core10.can_tenant(p_tenant) THEN RAISE EXCEPTION 'BOOTSTRAP_POLICY_DENIED' USING ERRCODE='42501'; END IF;
 UPDATE core10.tenants SET bootstrap_policy_initialized=true
 WHERE id=p_tenant AND NOT bootstrap_policy_initialized;
 RETURN core10._set_bootstrap_policy_v1(p_tenant,p_enabled,p_effective_at,p_expected_version,p_reason,p_request_key);
END $$;

CREATE FUNCTION core10.control_read_bootstrap_policy_v1(p_tenant bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE setting core10.control_setting_versions_v1%ROWTYPE; latest integer; initialized boolean;
BEGIN
 IF NOT core10.can_tenant(p_tenant) THEN RAISE EXCEPTION 'BOOTSTRAP_POLICY_DENIED' USING ERRCODE='42501'; END IF;
 SELECT bootstrap_policy_initialized INTO initialized FROM core10.tenants WHERE id=p_tenant;
 SELECT * INTO setting FROM core10.control_setting_versions_v1
 WHERE tenant_id=p_tenant AND business_id IS NULL AND feature_key='setup001.provision'
   AND effective_from<=statement_timestamp()
 ORDER BY effective_from DESC,version DESC LIMIT 1;
 SELECT coalesce(max(version),0) INTO latest FROM core10.control_setting_versions_v1
 WHERE tenant_id=p_tenant AND business_id IS NULL AND feature_key='setup001.provision';
 RETURN jsonb_build_object('tenant_id',p_tenant,'initialized',initialized,
  'enabled',coalesce(setting.enabled,false),'effective_version',coalesce(setting.version,0),
  'latest_version',latest,'audit_event_id',setting.audit_event_id);
END $$;

CREATE FUNCTION core10.read_bootstrap_setup_receipt_v1(p_tenant bigint,p_request text) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE result jsonb;
BEGIN
 IF NOT core10.can_tenant(p_tenant) THEN RAISE EXCEPTION 'BOOTSTRAP_RECEIPT_DENIED' USING ERRCODE='42501'; END IF;
 -- Use the canonical setup-run key. Industry setup stores an industry-v2: prefix.
 SELECT jsonb_build_object('tenant_id',r.tenant_id,'business_id',r.business_id,
  'setup_run_id',r.id,'request_key',r.request_key,'created_at',r.created_at,
  'created_by',r.created_by,'audit_event_id',a.id,'decision',a.payload->'decision')
 INTO result FROM core10.business_setup_runs_v1 r
 LEFT JOIN core10.canonical_audit_events_v1 a ON a.business_id=r.business_id
  AND a.tenant_id=r.tenant_id AND a.source_domain='bootstrap_setup' AND a.source_ref=r.id::text
 WHERE r.tenant_id=p_tenant AND r.request_key=p_request;
 RETURN result;
END $$;

REVOKE ALL ON FUNCTION core10.control_check_v1(bigint,text,bigint,text),
 core10._bootstrap_legal_tenant_v1(bigint),core10._record_bootstrap_setup_v1(bigint,bigint,text,jsonb)
 FROM PUBLIC, authenticated;
REVOKE ALL ON FUNCTION core10.setup_business_v1(bigint,text,text,text,text,jsonb,text,text),
 core10.setup_industry_draft_v2(bigint,text,text,text,text,jsonb,jsonb,text,text),
 core10.control_set_bootstrap_policy_v1(bigint,boolean,timestamptz,integer,text,text),
 core10.control_read_bootstrap_policy_v1(bigint),core10.read_bootstrap_setup_receipt_v1(bigint,text)
 FROM PUBLIC;
GRANT EXECUTE ON FUNCTION core10.setup_business_v1(bigint,text,text,text,text,jsonb,text,text),
 core10.setup_industry_draft_v2(bigint,text,text,text,text,jsonb,jsonb,text,text),
 core10.control_set_bootstrap_policy_v1(bigint,boolean,timestamptz,integer,text,text),
 core10.control_read_bootstrap_policy_v1(bigint),core10.read_bootstrap_setup_receipt_v1(bigint,text)
 TO authenticated;

DELETE FROM core10.control_rpc_map_v1 WHERE rpc_name='provision_business';
INSERT INTO core10.control_rpc_map_v1(rpc_name,status,reason,lane,board_row)
 VALUES ('control_set_bootstrap_policy_v1','exempt','Control administration itself; active Tenant Owner authority and canonical Audit required','ChatGPT','B-008');
DO $registry$
DECLARE rpc text;
BEGIN
 FOREACH rpc IN ARRAY ARRAY['build01_setup_v1','setup_business_v1','setup_industry_draft_v2'] LOOP
  IF core10._control_registry_promote_v1(rpc,'tests/migrations/np01-bootstrap-cutover-e2e.sql') <> 'enforced' THEN
   RAISE EXCEPTION 'BOOTSTRAP_REGISTRY_NOT_ENFORCED:%',rpc;
  END IF;
 END LOOP;
END
$registry$;
INSERT INTO core10.schema_migrations(version,name,checksum) VALUES(116,'0116_np01_bootstrap_provisioning','84dcb3b2eab734e63f5e5189e63df309f790aee3245351e08c0bb85e0bd0c38d');

-- CORE10 BASELINE SOURCE 0117_np01_bootstrap_owner_context.up.sql SHA256 6048553f8ef672bdb0e17d6f7535c9338ac8b074ef220fd5ccf1ce263dcd323e
-- Expose the current actor's canonical tenant-owner scope to the existing Central host.
CREATE OR REPLACE FUNCTION core10.build01_context_v1() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE actor uuid:=core10.actor_uid(); response jsonb;
BEGIN
 IF actor IS NULL THEN RAISE EXCEPTION 'BUILD01_SIGNED_SESSION_REQUIRED'; END IF;
 SELECT jsonb_build_object('actor_uid',actor,
 'real_auth_account_verified',to_regclass('auth.sessions') IS NOT NULL,
 'tenants',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',t.id,'slug',t.slug,
   'can_manage_bootstrap',core10.can_tenant(t.id)) ORDER BY t.id)
  FROM core10.tenants t WHERE t.active AND (core10.can_tenant(t.id) OR EXISTS(
   SELECT 1 FROM core10.businesses b WHERE b.tenant_id=t.id AND core10.can_see_business(t.id,b.id)))),'[]'::jsonb),
 'legal_entities',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',l.id,'tenant_id',l.tenant_id,'label',l.label) ORDER BY l.id)
  FROM core10.legal_entities l WHERE core10.can_tenant(l.tenant_id)),'[]'::jsonb),
 'templates',COALESCE((SELECT jsonb_agg(jsonb_build_object('code',t.code,'label',COALESCE(i.name_en,t.code),
   'source_status',t.source_status,'readiness',COALESCE(i.readiness,t.source_status),
   'draft_supported',true,'demo_allowed',t.demo_allowed,'enterprise_certified',t.enterprise_certified) ORDER BY t.code)
  FROM core10.templates t LEFT JOIN core10.industry_catalog_v2 i ON i.id=t.code
  WHERE i.id IS NOT NULL OR t.demo_allowed),'[]'::jsonb),
 'businesses',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',b.id,'tenant_id',b.tenant_id,'slug',b.slug,
   'label',COALESCE(c.display_name,b.slug),'status',b.status,'can_manage',core10.can_manage(b.tenant_id,b.id),
   'role',CASE WHEN core10.can_tenant(b.tenant_id) THEN 'tenant_owner' ELSE COALESCE((
    SELECT m.role FROM core10.business_members m WHERE m.business_id=b.id AND m.user_id=actor AND m.active
     AND (m.valid_until IS NULL OR m.valid_until>statement_timestamp())),'site_staff') END) ORDER BY b.id)
  FROM core10.businesses b LEFT JOIN core10.business_configuration_v1 c ON c.business_id=b.id
  WHERE core10.can_see_business(b.tenant_id,b.id)),'[]'::jsonb),
 'sites',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',s.id,'tenant_id',s.tenant_id,'business_id',s.business_id,
  'kind',s.kind,'label',s.label,'allowed_actions',to_jsonb(ARRAY(SELECT a FROM unnest(ARRAY['stock.read','stock.post']) a
   WHERE core10.can_site(s.tenant_id,s.business_id,s.id,a)))) ORDER BY s.id)
  FROM core10.sites s WHERE core10.can_manage(s.tenant_id,s.business_id)
   OR core10.can_site(s.tenant_id,s.business_id,s.id,'stock.read')),'[]'::jsonb),
 'production_certified',false,'data_mode','disposable-demo') INTO response;
 RETURN response;
END $$;
INSERT INTO core10.schema_migrations(version,name,checksum) VALUES(117,'0117_np01_bootstrap_owner_context','6048553f8ef672bdb0e17d6f7535c9338ac8b074ef220fd5ccf1ce263dcd323e');

-- CORE10 BASELINE SOURCE 0118_np01_site_provisioning_guard.up.sql SHA256 42571d32443c79e88d1de17a9842c64da54d2102f4fbfcd3285e104ee814dd86
-- D063 site cutover. Both the initial setup engines and the later site RPC
-- pass through the same serialized Business policy and cap before writing.
CREATE FUNCTION core10._provision_site_write_v1(p_business bigint,p_kind text,p_label text,p_request text)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE v_tenant bigint;v_id bigint;v_prev record;
BEGIN
 IF p_kind NOT IN ('showroom','factory','godown','warehouse','project') OR
  p_label IS NULL OR btrim(p_label)='' OR p_request IS NULL OR btrim(p_request)='' THEN
  RAISE EXCEPTION 'invalid_site_request';
 END IF;
 SELECT tenant_id INTO v_tenant FROM businesses WHERE id=p_business;
 IF v_tenant IS NULL OR NOT can_manage(v_tenant,p_business) THEN RAISE EXCEPTION 'site_provision_not_authorized'; END IF;
 INSERT INTO sites(tenant_id,business_id,kind,label,request_key)
 VALUES(v_tenant,p_business,p_kind,p_label,p_request)
 ON CONFLICT(business_id,request_key) DO NOTHING RETURNING id INTO v_id;
 IF v_id IS NULL THEN
  SELECT id,kind,label INTO v_prev FROM sites WHERE business_id=p_business AND request_key=p_request;
  IF NOT FOUND OR v_prev.kind<>p_kind OR v_prev.label<>p_label THEN RAISE EXCEPTION 'idempotency_key_payload_conflict'; END IF;
  v_id:=v_prev.id;
 END IF;
 INSERT INTO stock_locations(tenant_id,business_id,site_id,code)
 VALUES(v_tenant,p_business,v_id,'MAIN')
 ON CONFLICT(site_id,code) DO NOTHING;
 RETURN v_id;
END $$;

REVOKE ALL ON FUNCTION core10._provision_site_write_v1(bigint,text,text,text) FROM PUBLIC, authenticated;

-- Site provisioning captures one decision time after its Business locks. Other
-- Control consumers and read views retain their established time semantics.
CREATE FUNCTION core10._control_resolve_at_v1(p_business bigint, p_feature text, p_site bigint, p_at timestamptz) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE c core10.control_catalog_v1%ROWTYPE; r core10.control_setting_versions_v1%ROWTYPE; src text;
BEGIN
 SELECT * INTO c FROM core10.control_catalog_v1 WHERE feature_key = p_feature AND status = 'active';
 IF NOT FOUND THEN RAISE EXCEPTION 'CONTROL_UNKNOWN_FEATURE'; END IF;
 IF NOT c.invariant THEN
  IF p_site IS NOT NULL THEN
   SELECT * INTO r FROM core10.control_setting_versions_v1
    WHERE business_id = p_business AND site_id = p_site AND feature_key = p_feature
      AND effective_from <= p_at
    ORDER BY effective_from DESC, version DESC LIMIT 1;
   IF FOUND AND NOT r.inherit THEN src := 'site'; END IF;
  END IF;
  IF src IS NULL THEN
   SELECT * INTO r FROM core10.control_setting_versions_v1
    WHERE business_id = p_business AND site_id IS NULL AND feature_key = p_feature
      AND effective_from <= p_at
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
CREATE OR REPLACE FUNCTION core10._control_resolve_v1(p_business bigint, p_feature text, p_site bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
 SELECT core10._control_resolve_at_v1(p_business,p_feature,p_site,statement_timestamp());
$$;
CREATE OR REPLACE FUNCTION core10.control_check_v1(p_business bigint, p_feature text, p_site bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE v_actor uuid := core10.actor_uid(); v_tenant bigint; r jsonb; o core10.control_overrides_v1%ROWTYPE;
 v_at timestamptz := CASE WHEN p_feature = 'setup001.provision' THEN clock_timestamp() ELSE statement_timestamp() END;
BEGIN
 IF v_actor IS NULL THEN RAISE EXCEPTION 'CONTROL_UNAUTHENTICATED'; END IF;
 SELECT tenant_id INTO v_tenant FROM core10.businesses WHERE id = p_business;
 IF v_tenant IS NULL OR NOT core10.can_see_business(v_tenant, p_business) THEN RAISE EXCEPTION 'CONTROL_SCOPE'; END IF;
 IF p_site IS NOT NULL AND NOT EXISTS (SELECT 1 FROM core10.sites s
    WHERE s.id = p_site AND s.business_id = p_business AND s.tenant_id = v_tenant) THEN
  RAISE EXCEPTION 'CONTROL_SCOPE';
 END IF;
 r := core10._control_resolve_at_v1(p_business, p_feature, p_site, v_at);
 IF (r->>'enabled')::boolean THEN RETURN r || jsonb_build_object('override_used', false); END IF;
 SELECT * INTO o FROM core10.control_overrides_v1
  WHERE business_id = p_business AND feature_key = p_feature
    AND (site_id IS NULL OR site_id = p_site)
    AND consumed_at IS NULL AND revoked_at IS NULL AND expires_at > v_at
  ORDER BY (site_id IS NULL), id LIMIT 1 FOR UPDATE SKIP LOCKED;
 IF NOT FOUND THEN RAISE EXCEPTION 'CONTROL_DISABLED:%', p_feature; END IF;
 UPDATE core10.control_overrides_v1 SET consumed_at = v_at, consumed_by = v_actor WHERE id = o.id;
 PERFORM core10._append_canonical_audit_v1(v_tenant, p_business, 'control',
  'override:' || o.id || ':consumed', 'control.override_consumed', v_actor,
  'control:ovr:' || o.id || ':consumed',
  jsonb_build_object('feature_key', p_feature, 'site_id', p_site, 'override_id', o.id));
 RETURN r || jsonb_build_object('override_used', true, 'override_id', o.id);
END $$;

CREATE FUNCTION core10._lock_site_provision_v1(p_business bigint) RETURNS bigint
LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog,core10 AS $$
DECLARE tenant bigint;
BEGIN
 SELECT tenant_id INTO tenant FROM core10.businesses WHERE id=p_business;
 IF tenant IS NULL OR NOT core10.can_manage(tenant,p_business) THEN
  RAISE EXCEPTION 'BUILD01_SITE_DENIED';
 END IF;
 IF current_setting('transaction_isolation') <> 'read committed' THEN
  RAISE EXCEPTION 'BOOTSTRAP_READ_COMMITTED_REQUIRED' USING ERRCODE='25001';
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('c10ctl:'||p_business||':0:setup001.provision',0));
 PERFORM 1 FROM core10.businesses WHERE id=p_business AND tenant_id=tenant FOR UPDATE;
 IF NOT FOUND OR NOT core10.can_manage(tenant,p_business) THEN
  RAISE EXCEPTION 'BUILD01_SITE_DENIED';
 END IF;
 RETURN tenant;
END $$;

CREATE FUNCTION core10._assert_site_stage_v1(p_control jsonb) RETURNS void
LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog,core10 AS $$
BEGIN
 -- Nonzero stages require a source-bound canonical completion adapter.
 -- A one-time Control override cannot stand in for a completed Approval.
 IF (p_control->>'stages')::integer IS DISTINCT FROM 0 THEN
  RAISE EXCEPTION 'CONTROL_APPROVAL_REQUIRED:setup001.provision' USING ERRCODE='42501';
 END IF;
END $$;

CREATE FUNCTION core10._assert_site_capacity_v1(p_tenant bigint,p_business bigint,p_control jsonb)
RETURNS void LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog,core10 AS $$
DECLARE cap integer := (p_control->'params'->>'max_sites')::integer;
BEGIN
 -- Canonical sites have no archival/status column. Count every provisioned row.
 IF cap IS NULL OR cap < 1 OR (
  SELECT count(*) FROM core10.sites WHERE tenant_id=p_tenant AND business_id=p_business
 ) >= cap THEN
  RAISE EXCEPTION 'CONTROL_LIMIT:max_sites';
 END IF;
END $$;

-- Setup engines use this private entrypoint for each initial manifest site.
-- Any denial aborts the entire encompassing setup transaction.
CREATE OR REPLACE FUNCTION core10.provision_site(p_business bigint,p_kind text,p_label text,p_request text)
RETURNS bigint LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog,core10 AS $$
DECLARE tenant bigint; decision jsonb;
BEGIN
 tenant:=core10._lock_site_provision_v1(p_business);
 decision:=core10.control_check_v1(p_business,'setup001.provision',NULL);
 PERFORM core10._assert_site_stage_v1(decision);
 PERFORM core10._assert_site_capacity_v1(tenant,p_business,decision);
 RETURN core10._provision_site_write_v1(p_business,p_kind,p_label,p_request);
END $$;

REVOKE ALL ON FUNCTION core10._control_resolve_at_v1(bigint,text,bigint,timestamptz),
 core10._lock_site_provision_v1(bigint),core10._assert_site_stage_v1(jsonb),
 core10._assert_site_capacity_v1(bigint,bigint,jsonb),core10.provision_site(bigint,text,text,text)
 FROM PUBLIC, authenticated;

CREATE OR REPLACE FUNCTION core10.build01_site_v1(p_business bigint,p_kind text,p_label text,p_request text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE site bigint; tenant bigint; actor uuid:=core10.actor_uid(); signature jsonb; previous record; event_id bigint; v_control jsonb;
BEGIN
 tenant:=core10._lock_site_provision_v1(p_business);
 signature:=jsonb_build_object('business',p_business,'kind',p_kind,'label',p_label,'request',p_request);
 SELECT * INTO previous FROM core10.access_change_events_v1 WHERE business_id=p_business AND request_key=p_request;
 IF FOUND THEN
  -- A replay checks current policy without consuming a new override.
  v_control:=core10._control_resolve_at_v1(p_business,'setup001.provision',NULL,clock_timestamp());
  IF v_control->>'enabled' IS DISTINCT FROM 'true' THEN
   RAISE EXCEPTION 'CONTROL_DISABLED:setup001.provision';
  END IF;
  PERFORM core10._assert_site_stage_v1(v_control);
  IF previous.input_signature<>signature OR previous.actor_uid<>actor OR previous.event_kind<>'setup.site' THEN RAISE EXCEPTION 'BUILD01_REQUEST_CONFLICT'; END IF;
  RETURN previous.after_state||jsonb_build_object('event_id',previous.id,'request_key',p_request);
 END IF;
 v_control:=core10.control_check_v1(p_business,'setup001.provision',NULL);
 PERFORM core10._assert_site_stage_v1(v_control);
 -- Capacity applies to new writes after the receipt path has returned.
 PERFORM core10._assert_site_capacity_v1(tenant,p_business,v_control);
 site:=core10._provision_site_write_v1(p_business,p_kind,p_label,p_request);
 INSERT INTO core10.access_change_events_v1(tenant_id,business_id,request_key,command,subject_uid,site_id,input_signature,before_state,after_state,actor_uid,event_kind)
 VALUES(tenant,p_business,p_request,'setup.site',actor,site,signature,'{}',jsonb_build_object('business_id',p_business,'site_id',site),actor,'setup.site') RETURNING id INTO event_id;
 RETURN jsonb_build_object('business_id',p_business,'site_id',site,'request_key',p_request,'event_id',event_id);
END $$;
DELETE FROM core10.control_rpc_map_v1 WHERE rpc_name='provision_site';
INSERT INTO core10.schema_migrations(version,name,checksum) VALUES(118,'0118_np01_site_provisioning_guard','42571d32443c79e88d1de17a9842c64da54d2102f4fbfcd3285e104ee814dd86');
