CREATE OR REPLACE FUNCTION core10.build01_context_v1() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE actor uuid:=core10.actor_uid(); response jsonb;
BEGIN
 IF actor IS NULL THEN RAISE EXCEPTION 'BUILD01_SIGNED_SESSION_REQUIRED'; END IF;
 SELECT jsonb_build_object('actor_uid',actor,
 'real_auth_account_verified',to_regclass('auth.sessions') IS NOT NULL,
 'tenants',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',t.id,'slug',t.slug) ORDER BY t.id)
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
