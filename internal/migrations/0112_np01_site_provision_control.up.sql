-- NP01/B-020/0112: real Owner Control on existing canonical site RPC.
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
DO $np01$
BEGIN
 IF core10._control_registry_promote_v1('build01_site_v1','tests/migrations/np01-control-site-provision-e2e.sql')<>'enforced'
 THEN RAISE EXCEPTION 'NP01_0112_REGISTRY_NOT_ENFORCED'; END IF;
END $np01$;
