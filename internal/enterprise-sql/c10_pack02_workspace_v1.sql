-- PACK-02 slice 1 (A020/A021/A042-A044; D030/D032/D033/D045/D049/D051/D054).
-- Persisted setup readback, Universal Owner / Business Owner / Staff workspace
-- projections and business-scoped reports for the disposable c10_demo stack.
--
-- Additive ONLY. Loaded after c10_build01_access_integration_v1.sql. It:
--  * creates no table, permission store, grant row, role, or audit store;
--  * derives every decision from the existing canonical predicates
--    c10_demo.actor_uid/can_tenant/can_business/can_manage/can_site/can_see_business
--    (PACK-01 owned; called, never redefined here);
--  * reuses the existing build01_setup_v1 -> setup_business_v1 /
--    setup_industry_draft_v2 engines for Quick/Advanced setup;
--  * performs no stock, money, payroll or customer-data write;
--  * is NOT a hosted/production migration and must never be applied to IMG-ERP-SG.
DO $guard$ BEGIN
 IF current_database() !~ '^core10_(build01|build02a|a[0-9]+|preview|pack02)' OR
    to_regprocedure('c10_demo.build01_setup_v1(bigint,text,text,text,text,jsonb,text,text)') IS NULL OR
    to_regprocedure('c10_demo.can_site(bigint,bigint,bigint,text)') IS NULL OR
    to_regclass('c10_demo.business_configuration_v1') IS NULL THEN
  RAISE EXCEPTION 'PACK02_DISPOSABLE_BUILD01_STACK_REQUIRED';
 END IF;
END $guard$;

-- Workspace navigation keys. Labels (Bangla-first) live in the client; the
-- server only projects keys the actor's canonical authority actually permits.
CREATE FUNCTION c10_demo.pack02_nav_v1(p_mode text,p_actions text[]) RETURNS jsonb
LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $$
 SELECT CASE p_mode
  WHEN 'universal_owner' THEN '["owner.portfolio","owner.businesses","owner.setup","owner.reports","owner.controls"]'::jsonb
  WHEN 'business_owner' THEN '["biz.dashboard","biz.sites","biz.site_create","biz.access","biz.reports","biz.controls"]'::jsonb
  WHEN 'staff' THEN to_jsonb(ARRAY['staff.home']
   ||CASE WHEN 'stock.read'=ANY(p_actions) THEN ARRAY['stock.view','staff.reports'] ELSE '{}'::text[] END
   ||CASE WHEN 'stock.post'=ANY(p_actions) THEN ARRAY['stock.post'] ELSE '{}'::text[] END)
  ELSE NULL END
$$;

-- Brand of ONE business only. Never derives anything from the umbrella or a
-- sister business; a missing A020 configuration yields a neutral palette.
CREATE FUNCTION c10_demo.pack02_brand_v1(p_business bigint) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,c10_demo AS $$
 SELECT jsonb_build_object(
  'display_name',COALESCE(c.display_name,b.slug),
  'brand_hex',COALESCE(c.brand_hex,'#334155'),
  'brand_source',CASE WHEN c.business_id IS NULL THEN 'neutral_default' ELSE 'business_configuration_v1' END,
  'setup_mode',c.setup_mode,'setup_status',COALESCE(c.setup_status,b.status))
 FROM c10_demo.businesses b LEFT JOIN c10_demo.business_configuration_v1 c ON c.business_id=b.id
 WHERE b.id=p_business
$$;
REVOKE ALL ON FUNCTION c10_demo.pack02_brand_v1(bigint) FROM PUBLIC,authenticated;

-- Persisted readback + integrity proof for one business (owner/manager-of-record only).
CREATE FUNCTION c10_demo.pack02_setup_readback_v1(p_business bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,c10_demo AS $$
DECLARE actor uuid:=c10_demo.actor_uid(); b record; checks jsonb; sites jsonb; runs bigint; events bigint;
BEGIN
 SELECT * INTO b FROM c10_demo.businesses WHERE id=p_business;
 IF actor IS NULL OR NOT FOUND OR NOT c10_demo.can_manage(b.tenant_id,b.id) THEN
  RAISE EXCEPTION 'PACK02_READBACK_DENIED';
 END IF;
 SELECT COALESCE(jsonb_agg(jsonb_build_object('id',s.id,'kind',s.kind,'label',s.label,
   'location_codes',COALESCE((SELECT jsonb_agg(l.code ORDER BY l.code) FROM c10_demo.stock_locations l
     WHERE l.site_id=s.id AND l.business_id=s.business_id AND l.tenant_id=s.tenant_id),'[]'::jsonb)) ORDER BY s.id),'[]'::jsonb)
  INTO sites FROM c10_demo.sites s WHERE s.business_id=b.id AND s.tenant_id=b.tenant_id;
 SELECT count(*) INTO runs FROM c10_demo.business_setup_runs_v1 WHERE business_id=b.id AND tenant_id=b.tenant_id;
 SELECT count(*) INTO events FROM c10_demo.access_change_events_v1 WHERE business_id=b.id AND event_kind='setup.business';
 checks:=jsonb_build_object(
  'legal_entity_same_tenant',EXISTS(SELECT 1 FROM c10_demo.legal_entities l WHERE l.id=b.legal_entity_id AND l.tenant_id=b.tenant_id),
  'configuration_present',EXISTS(SELECT 1 FROM c10_demo.business_configuration_v1 c WHERE c.business_id=b.id AND c.tenant_id=b.tenant_id),
  'setup_receipt_single',runs=1,
  'has_site',jsonb_array_length(sites)>0,
  'every_site_has_main_location',NOT EXISTS(SELECT 1 FROM c10_demo.sites s WHERE s.business_id=b.id AND NOT EXISTS(
    SELECT 1 FROM c10_demo.stock_locations l WHERE l.site_id=s.id AND l.code='MAIN')),
  'no_orphan_locations',NOT EXISTS(SELECT 1 FROM c10_demo.stock_locations l WHERE l.business_id=b.id AND NOT EXISTS(
    SELECT 1 FROM c10_demo.sites s WHERE s.id=l.site_id AND s.business_id=b.id AND s.tenant_id=b.tenant_id)),
  'no_duplicate_sites',NOT EXISTS(SELECT 1 FROM c10_demo.sites s WHERE s.business_id=b.id
    GROUP BY s.kind,lower(btrim(s.label)) HAVING count(*)>1),
  'modules_locked',NOT EXISTS(SELECT 1 FROM c10_demo.business_module_settings_v1 m WHERE m.business_id=b.id AND m.operational_enabled),
  'not_activated',b.status IN('draft','setup_pending'));
 RETURN jsonb_build_object('contract','C10_PACK02_SETUP_READBACK_V1',
  'business',jsonb_build_object('id',b.id,'tenant_id',b.tenant_id,'legal_entity_id',b.legal_entity_id,
    'slug',b.slug,'template_code',b.template_code,'status',b.status),
  'brand',c10_demo.pack02_brand_v1(b.id),'sites',sites,
  'setup_runs',runs,'setup_events',events,'checks',checks,
  'integrity_ok',NOT EXISTS(SELECT 1 FROM jsonb_each(checks) WHERE value<>'true'::jsonb),
  'production_certified',false,'data_mode','disposable-demo');
END $$;

-- Quick/Advanced setup through the EXISTING canonical engine, returning the
-- engine receipt plus persisted readback. Replay returns an identical result.
CREATE FUNCTION c10_demo.pack02_setup_business_v1(
 p_legal bigint,p_slug text,p_template text,p_display_name text,p_mode text,p_sites jsonb,p_request text,p_brand_hex text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,c10_demo AS $$
DECLARE receipt jsonb; readback jsonb;
BEGIN
 receipt:=c10_demo.build01_setup_v1(p_legal,p_slug,p_template,p_display_name,p_mode,p_sites,p_request,p_brand_hex);
 readback:=c10_demo.pack02_setup_readback_v1((receipt->>'business_id')::bigint);
 IF readback->>'integrity_ok'<>'true' THEN RAISE EXCEPTION 'PACK02_SETUP_INTEGRITY_FAILED'; END IF;
 RETURN jsonb_build_object('receipt',receipt,'readback',readback);
END $$;

-- One resolver, three workspaces. All authority comes from canonical predicates.
CREATE FUNCTION c10_demo.pack02_workspace_v1(p_mode text,p_business bigint DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,c10_demo AS $$
DECLARE actor uuid:=c10_demo.actor_uid(); tenant bigint; sites jsonb; actions text[]; businesses jsonb;
BEGIN
 IF actor IS NULL THEN RAISE EXCEPTION 'PACK02_SIGNED_SESSION_REQUIRED'; END IF;
 IF p_mode IS NULL OR p_mode NOT IN('universal_owner','business_owner','staff') THEN RAISE EXCEPTION 'PACK02_MODE_INVALID'; END IF;

 IF p_mode='universal_owner' THEN
  IF p_business IS NOT NULL THEN RAISE EXCEPTION 'PACK02_MODE_INVALID'; END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('id',b.id,'tenant_id',b.tenant_id,'slug',b.slug,'status',b.status,
    'brand',c10_demo.pack02_brand_v1(b.id),
    'site_count',(SELECT count(*) FROM c10_demo.sites s WHERE s.business_id=b.id AND s.tenant_id=b.tenant_id)) ORDER BY b.tenant_id,b.id),'[]'::jsonb)
   INTO businesses FROM c10_demo.businesses b JOIN c10_demo.tenants t ON t.id=b.tenant_id
   WHERE t.active AND c10_demo.can_tenant(b.tenant_id);
  IF NOT EXISTS(SELECT 1 FROM c10_demo.tenants t WHERE t.active AND c10_demo.can_tenant(t.id)) THEN
   RAISE EXCEPTION 'PACK02_WORKSPACE_DENIED';
  END IF;
  RETURN jsonb_build_object('contract','C10_PACK02_WORKSPACE_V1','mode',p_mode,'actor_uid',actor,
   'umbrella',jsonb_build_object('visible',true,'name','CORE 10'),
   'tenants',(SELECT COALESCE(jsonb_agg(jsonb_build_object('id',t.id,'slug',t.slug) ORDER BY t.id),'[]'::jsonb)
     FROM c10_demo.tenants t WHERE t.active AND c10_demo.can_tenant(t.id)),
   'businesses',businesses,'nav',c10_demo.pack02_nav_v1(p_mode,'{}'),
   'production_certified',false,'data_mode','disposable-demo');
 END IF;

 SELECT b.tenant_id INTO tenant FROM c10_demo.businesses b WHERE b.id=p_business;
 IF tenant IS NULL THEN RAISE EXCEPTION 'PACK02_WORKSPACE_DENIED'; END IF;

 IF p_mode='business_owner' THEN
  IF NOT c10_demo.can_manage(tenant,p_business) THEN RAISE EXCEPTION 'PACK02_WORKSPACE_DENIED'; END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('id',s.id,'kind',s.kind,'label',s.label,
    'allowed_actions',to_jsonb(ARRAY(SELECT a FROM unnest(ARRAY['stock.read','stock.post']) a
      WHERE c10_demo.can_site(tenant,p_business,s.id,a)))) ORDER BY s.id),'[]'::jsonb)
   INTO sites FROM c10_demo.sites s WHERE s.business_id=p_business AND s.tenant_id=tenant;
  RETURN jsonb_build_object('contract','C10_PACK02_WORKSPACE_V1','mode',p_mode,'actor_uid',actor,
   -- Only the tenant owner may navigate back to the umbrella (D033/D036).
   'umbrella',jsonb_build_object('visible',c10_demo.can_tenant(tenant)),
   'business',jsonb_build_object('id',p_business,'brand',c10_demo.pack02_brand_v1(p_business)),
   'sites',sites,'nav',c10_demo.pack02_nav_v1(p_mode,'{}'),
   'production_certified',false,'data_mode','disposable-demo');
 END IF;

 -- Staff: strictly the sites this actor can read; no tenant, legal entity,
 -- umbrella, sister business, member list or audit is projected (D006/D013/D027).
 SELECT COALESCE(jsonb_agg(jsonb_build_object('id',s.id,'kind',s.kind,'label',s.label,
         'allowed_actions',to_jsonb(ARRAY(SELECT a FROM unnest(ARRAY['stock.read','stock.post']) a
          WHERE c10_demo.can_site(tenant,p_business,s.id,a)))) ORDER BY s.id),'[]'::jsonb)
  INTO sites FROM c10_demo.sites s WHERE s.business_id=p_business AND s.tenant_id=tenant
   AND c10_demo.can_site(tenant,p_business,s.id,'stock.read');
 IF jsonb_array_length(sites)=0 THEN RAISE EXCEPTION 'PACK02_WORKSPACE_DENIED'; END IF;
 SELECT COALESCE(array_agg(DISTINCT x.act),'{}') INTO actions
  FROM jsonb_array_elements(sites) e, jsonb_array_elements_text(e->'allowed_actions') x(act);
 RETURN jsonb_build_object('contract','C10_PACK02_WORKSPACE_V1','mode',p_mode,
  'umbrella',jsonb_build_object('visible',false),
  'business',jsonb_build_object('id',p_business,'brand',(c10_demo.pack02_brand_v1(p_business)-'setup_mode'-'brand_source')),
  'sites',sites,'nav',c10_demo.pack02_nav_v1(p_mode,actions),
  'production_certified',false);
END $$;

-- Business-scoped report: counts only from canonical tables, limited to sites
-- the actor can read. Movement counts are informational, not valuations.
CREATE FUNCTION c10_demo.pack02_business_report_v1(p_business bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,c10_demo AS $$
DECLARE actor uuid:=c10_demo.actor_uid(); tenant bigint; owner boolean; rows jsonb;
BEGIN
 SELECT b.tenant_id INTO tenant FROM c10_demo.businesses b WHERE b.id=p_business;
 IF actor IS NULL OR tenant IS NULL OR NOT c10_demo.can_see_business(tenant,p_business) THEN
  RAISE EXCEPTION 'PACK02_REPORT_DENIED';
 END IF;
 owner:=c10_demo.can_manage(tenant,p_business);
 SELECT COALESCE(jsonb_agg(jsonb_build_object('site_id',s.id,'kind',s.kind,'label',s.label,
   'location_count',(SELECT count(*) FROM c10_demo.stock_locations l WHERE l.site_id=s.id),
   -- PACK-01 rule: an explicit site DENY outranks inherited owner/manager
   -- rights, so stock figures are withheld (NULL) for a read-denied site.
   'stock_read',c10_demo.can_site(tenant,p_business,s.id,'stock.read'),
   'movement_count',CASE WHEN c10_demo.can_site(tenant,p_business,s.id,'stock.read') THEN
     (SELECT count(*) FROM c10_demo.stock_movements m WHERE m.site_id=s.id AND m.business_id=p_business) END,
   'last_movement_at',CASE WHEN c10_demo.can_site(tenant,p_business,s.id,'stock.read') THEN
     (SELECT max(m.created_at) FROM c10_demo.stock_movements m WHERE m.site_id=s.id AND m.business_id=p_business) END) ORDER BY s.id),'[]'::jsonb)
  INTO rows FROM c10_demo.sites s
  WHERE s.business_id=p_business AND s.tenant_id=tenant
   AND (owner OR c10_demo.can_site(tenant,p_business,s.id,'stock.read'));
 RETURN jsonb_build_object('contract','C10_PACK02_BUSINESS_REPORT_V1','business_id',p_business,
  'scope',CASE WHEN owner THEN 'business' ELSE 'granted_sites' END,
  'sites',rows,'totals',jsonb_build_object('sites',jsonb_array_length(rows),
   'movements',(SELECT COALESCE(sum((r->>'movement_count')::bigint),0) FROM jsonb_array_elements(rows) r)),
  'valuation_included',false,'production_certified',false);
END $$;

-- Universal Owner report: one row per business of each tenant the actor owns.
-- No cross-tenant aggregation and no internal-transfer netting is claimed.
CREATE FUNCTION c10_demo.pack02_owner_report_v1() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,c10_demo AS $$
DECLARE actor uuid:=c10_demo.actor_uid(); rows jsonb;
BEGIN
 IF actor IS NULL OR NOT EXISTS(SELECT 1 FROM c10_demo.tenants t WHERE t.active AND c10_demo.can_tenant(t.id)) THEN
  RAISE EXCEPTION 'PACK02_REPORT_DENIED';
 END IF;
 SELECT COALESCE(jsonb_agg(jsonb_build_object('tenant_id',b.tenant_id,'business_id',b.id,
   'display_name',c10_demo.pack02_brand_v1(b.id)->>'display_name',
   'sites',(SELECT count(*) FROM c10_demo.sites s WHERE s.business_id=b.id),
   'locations',(SELECT count(*) FROM c10_demo.stock_locations l WHERE l.business_id=b.id),
   'movements',(SELECT count(*) FROM c10_demo.stock_movements m WHERE m.business_id=b.id AND m.site_id IN(
     SELECT s.id FROM c10_demo.sites s WHERE s.business_id=b.id AND c10_demo.can_site(s.tenant_id,s.business_id,s.id,'stock.read')))) ORDER BY b.tenant_id,b.id),'[]'::jsonb)
  INTO rows FROM c10_demo.businesses b JOIN c10_demo.tenants t ON t.id=b.tenant_id
  WHERE t.active AND c10_demo.can_tenant(b.tenant_id);
 RETURN jsonb_build_object('contract','C10_PACK02_OWNER_REPORT_V1','businesses',rows,
  'consolidation','per_business_rows_only','valuation_included',false,'production_certified',false);
END $$;

REVOKE ALL ON FUNCTION c10_demo.pack02_nav_v1(text,text[]),
 c10_demo.pack02_setup_readback_v1(bigint),
 c10_demo.pack02_setup_business_v1(bigint,text,text,text,text,jsonb,text,text),
 c10_demo.pack02_workspace_v1(text,bigint),c10_demo.pack02_business_report_v1(bigint),
 c10_demo.pack02_owner_report_v1() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION c10_demo.pack02_setup_readback_v1(bigint),
 c10_demo.pack02_setup_business_v1(bigint,text,text,text,text,jsonb,text,text),
 c10_demo.pack02_workspace_v1(text,bigint),c10_demo.pack02_business_report_v1(bigint),
 c10_demo.pack02_owner_report_v1() TO authenticated;
-- anon receives nothing. No direct table grant is added.
