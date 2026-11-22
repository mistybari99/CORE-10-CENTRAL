-- Preserve the provisioning gate and audit evidence once it is in use.
DO $guard$
BEGIN
 IF EXISTS (SELECT 1 FROM core10.control_setting_versions_v1 WHERE business_id IS NULL)
 OR EXISTS (SELECT 1 FROM core10.canonical_audit_events_v1 WHERE source_domain='bootstrap_setup') THEN
  RAISE EXCEPTION 'BOOTSTRAP_PROVISIONING_HISTORY_ROLLBACK_REFUSED';
 END IF;
END
$guard$;

DROP FUNCTION core10.control_set_bootstrap_policy_v1(bigint,boolean,timestamptz,integer,text,text);
DROP FUNCTION core10.control_read_bootstrap_policy_v1(bigint);
DROP FUNCTION core10.read_bootstrap_setup_receipt_v1(bigint,text);
DROP FUNCTION core10.setup_business_v1(bigint,text,text,text,text,jsonb,text,text);
DROP FUNCTION core10.setup_industry_draft_v2(bigint,text,text,text,text,jsonb,jsonb,text,text);
ALTER FUNCTION core10._setup_business_write_v1(bigint,text,text,text,text,jsonb,text,text)
 RENAME TO setup_business_v1;
ALTER FUNCTION core10._setup_industry_write_v2(bigint,text,text,text,text,jsonb,jsonb,text,text)
 RENAME TO setup_industry_draft_v2;
GRANT EXECUTE ON FUNCTION core10.setup_business_v1(bigint,text,text,text,text,jsonb,text,text),
 core10.setup_industry_draft_v2(bigint,text,text,text,text,jsonb,jsonb,text,text),
 core10.provision_business(bigint,text,text,text) TO authenticated;

CREATE OR REPLACE FUNCTION core10.build01_setup_v1(
 p_legal bigint,p_slug text,p_template text,p_display_name text,p_mode text,p_sites jsonb,p_request text,p_brand_hex text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE business bigint; tenant bigint; actor uuid:=core10.actor_uid(); signature jsonb; previous record; event_id bigint; modules jsonb;
BEGIN
 SELECT tenant_id INTO tenant FROM core10.legal_entities WHERE id=p_legal;
 IF actor IS NULL OR tenant IS NULL OR NOT core10.can_tenant(tenant) THEN RAISE EXCEPTION 'BUILD01_SETUP_DENIED'; END IF;
 -- Original setup engines perform multiple canonical inserts. Serialize the
 -- same tenant/request before entering either engine so concurrent retries
 -- observe the committed receipt instead of racing the unique slug constraint.
 PERFORM pg_advisory_xact_lock(hashtextextended(jsonb_build_array('build01.setup',tenant,p_request)::text,0));
 IF NOT core10.can_tenant(tenant) THEN RAISE EXCEPTION 'BUILD01_SETUP_DENIED'; END IF;
 -- Reuse the original ten-family draft engine. Module selections come only
 -- from its canonical catalog; that engine keeps every module locked/disabled.
 -- Legacy demo-approved template codes retain the existing A020 v1 contract.
 IF EXISTS(SELECT 1 FROM core10.industry_catalog_v2 WHERE id=p_template) THEN
  SELECT COALESCE(jsonb_agg(module_code ORDER BY module_code),'[]'::jsonb) INTO modules
   FROM core10.industry_module_catalog_v2 WHERE industry_id=p_template;
  business:=core10.setup_industry_draft_v2(p_legal,p_slug,p_template,p_display_name,p_mode,p_sites,modules,p_request,p_brand_hex);
 ELSE
  business:=core10.setup_business_v1(p_legal,p_slug,p_template,p_display_name,p_mode,p_sites,p_request,p_brand_hex);
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

DROP FUNCTION core10.control_check_v1(bigint,text,bigint,text);
DROP FUNCTION core10._bootstrap_legal_tenant_v1(bigint);
DROP FUNCTION core10._record_bootstrap_setup_v1(bigint,bigint,text,jsonb);
DELETE FROM core10.control_rpc_map_v1 WHERE rpc_name='control_set_bootstrap_policy_v1';
INSERT INTO core10.control_rpc_map_v1(rpc_name,status,feature_key,reason,lane,board_row) VALUES
 ('build01_setup_v1','pending','setup001.provision','Setup is not yet bound to the provision control; to be connected by the NP01 lane','ChatGPT','B-008'),
 ('setup_business_v1','pending','setup001.provision','Business setup is not yet bound to the provision control','ChatGPT','B-008'),
 ('setup_industry_draft_v2','pending','setup001.provision','Industry draft setup is not yet bound to the provision control','ChatGPT','B-008'),
 ('provision_business','pending','setup001.provision','A018 fixture provisioning, superseded by build01_setup_v1; retire with the legacy installer','Claude','B-009')
ON CONFLICT (rpc_name) DO UPDATE
 SET status=excluded.status,reason=excluded.reason,test_ref=NULL;
