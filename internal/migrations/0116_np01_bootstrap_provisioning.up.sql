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
