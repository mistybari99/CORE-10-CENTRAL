-- Restore pre-cutover definitions and grants without changing site or Audit rows.
CREATE OR REPLACE FUNCTION core10.provision_site(p_business bigint,p_kind text,p_label text,p_request text)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=core10,pg_catalog AS $$
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

GRANT EXECUTE ON FUNCTION core10.provision_site(bigint,text,text,text) TO authenticated;

CREATE OR REPLACE FUNCTION core10.build01_site_v1(p_business bigint,p_kind text,p_label text,p_request text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE site bigint; tenant bigint; actor uuid:=core10.actor_uid(); signature jsonb; previous record; event_id bigint; v_control jsonb;
BEGIN
 SELECT tenant_id INTO tenant FROM core10.businesses WHERE id=p_business;
 IF actor IS NULL OR tenant IS NULL OR NOT core10.can_manage(tenant,p_business) THEN RAISE EXCEPTION 'BUILD01_SITE_DENIED'; END IF;
 -- Serialize against Owner setting changes and concurrent site writers.
 PERFORM pg_advisory_xact_lock(hashtextextended('c10ctl:'||p_business||':0:setup001.provision',0));
 PERFORM 1 FROM core10.businesses WHERE id=p_business FOR UPDATE;
 IF NOT core10.can_manage(tenant,p_business) THEN RAISE EXCEPTION 'BUILD01_SITE_DENIED'; END IF;
 -- Canonical Auth before Control, Control before replay or writes.
 v_control:=core10.control_check_v1(p_business,'setup001.provision',NULL);
 signature:=jsonb_build_object('business',p_business,'kind',p_kind,'label',p_label,'request',p_request);
 SELECT * INTO previous FROM core10.access_change_events_v1 WHERE business_id=p_business AND request_key=p_request;
 IF FOUND THEN
  IF previous.input_signature<>signature OR previous.actor_uid<>actor OR previous.event_kind<>'setup.site' THEN RAISE EXCEPTION 'BUILD01_REQUEST_CONFLICT'; END IF;
  RETURN previous.after_state||jsonb_build_object('event_id',previous.id,'request_key',p_request);
 END IF;
 -- Limits affect new writes, not idempotent receipts when Owner lowers the cap.
 IF (SELECT count(*) FROM core10.sites s WHERE s.business_id=p_business AND s.tenant_id=tenant)
      >= (v_control->'params'->>'max_sites')::integer THEN
  RAISE EXCEPTION 'CONTROL_LIMIT:max_sites';
 END IF;
 site:=core10.provision_site(p_business,p_kind,p_label,p_request);
 INSERT INTO core10.access_change_events_v1(tenant_id,business_id,request_key,command,subject_uid,site_id,input_signature,before_state,after_state,actor_uid,event_kind)
 VALUES(tenant,p_business,p_request,'setup.site',actor,site,signature,'{}',jsonb_build_object('business_id',p_business,'site_id',site),actor,'setup.site') RETURNING id INTO event_id;
 RETURN jsonb_build_object('business_id',p_business,'site_id',site,'request_key',p_request,'event_id',event_id);
END $$;
CREATE OR REPLACE FUNCTION core10.control_check_v1(p_business bigint, p_feature text, p_site bigint DEFAULT NULL)
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
CREATE OR REPLACE FUNCTION core10._control_resolve_v1(p_business bigint, p_feature text, p_site bigint) RETURNS jsonb
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

DROP FUNCTION core10._provision_site_write_v1(bigint,text,text,text);
DROP FUNCTION core10._control_resolve_at_v1(bigint,text,bigint,timestamptz);
DROP FUNCTION core10._lock_site_provision_v1(bigint);
DROP FUNCTION core10._assert_site_stage_v1(jsonb);
DROP FUNCTION core10._assert_site_capacity_v1(bigint,bigint,jsonb);
INSERT INTO core10.control_rpc_map_v1(rpc_name,status,feature_key,reason,lane,board_row)
 VALUES ('provision_site','pending','setup001.provision','A018 fixture provisioning, superseded by build01_site_v1; retire with the legacy installer','Claude','B-009');
