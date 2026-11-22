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
