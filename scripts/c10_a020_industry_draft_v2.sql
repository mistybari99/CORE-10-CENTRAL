-- CORE10 A020 / 10-industry draft provisioning v2
-- DISPOSABLE PostgreSQL / staging candidate ONLY. DO NOT APPLY TO LIVE IMG-ERP-SG.
-- Requires c10_a018_demo_backend.sql, demo seed, c10_a020_business_setup_v1.sql.
-- All ten families can create DRAFT businesses, never operationally enabled modules.
CREATE TABLE c10_demo.industry_catalog_v2 (
 id text PRIMARY KEY CHECK(id ~ '^[a-z][a-z0-9_]+$'),
 name_en text NOT NULL,
 legacy_code text,
 legacy_status text NOT NULL,
 readiness text NOT NULL,
 enterprise_certified boolean NOT NULL DEFAULT false CHECK(enterprise_certified=false)
);
INSERT INTO c10_demo.industry_catalog_v2(id,name_en,legacy_code,legacy_status,readiness) VALUES
('sweets_bakery','Sweets, Bakery & Food Manufacturing','food_manufacturing','available','implemented_unverified'),
('restaurant','Restaurant, Fast Food & Cloud Kitchen',NULL,'unregistered','not_implemented'),
('paint_hardware','Paint, Hardware & Dealership','hardware_paint','not_implemented','not_implemented'),
('retail_wholesale','Retail, Wholesale & Distribution',NULL,'unregistered','not_implemented'),
('general_manufacturing','General Manufacturing',NULL,'unregistered','not_implemented'),
('construction','Construction & Project Management','construction','not_implemented','not_implemented'),
('import_export','Import, Export & International Trade','import_export','needs_setup','partial'),
('ecommerce','E-commerce & Online Store','online_store','not_implemented','not_implemented'),
('technology_digital','Technology, Software & Digital Products','technology','not_implemented','not_implemented'),
('services','Services, Agency & Professional Services',NULL,'unregistered','not_implemented');
CREATE TABLE c10_demo.industry_module_catalog_v2(
 industry_id text NOT NULL REFERENCES c10_demo.industry_catalog_v2(id),
 module_code text NOT NULL CHECK(module_code ~ '^[a-z][a-z0-9_]+$'),
 readiness text NOT NULL,
 PRIMARY KEY(industry_id,module_code)
);
INSERT INTO c10_demo.industry_module_catalog_v2(industry_id,module_code,readiness) VALUES
('sweets_bakery','pos','implemented_unverified'),
('sweets_bakery','stock','implemented_unverified'),
('sweets_bakery','purchase','implemented_unverified'),
('sweets_bakery','production','implemented_unverified'),
('sweets_bakery','costing','implemented_unverified'),
('sweets_bakery','accounting','implemented_unverified'),
('sweets_bakery','reports','implemented_unverified'),
('restaurant','restaurant_pos','not_implemented'),
('restaurant','kitchen_order','not_implemented'),
('restaurant','menu_recipe','not_implemented'),
('restaurant','food_delivery','not_implemented'),
('paint_hardware','cheque_pdc','implemented_unverified'),
('paint_hardware','principal_schemes','implemented_unverified'),
('paint_hardware','tinting','implemented_unverified'),
('paint_hardware','bulk_item_import','not_implemented'),
('paint_hardware','item_variants','not_implemented'),
('paint_hardware','dealer_pos_screens','not_implemented'),
('paint_hardware','party_scope_per_business','not_implemented'),
('paint_hardware','scheme_books_posting','not_implemented'),
('retail_wholesale','wholesale_pricing','not_implemented'),
('retail_wholesale','distribution_orders','not_implemented'),
('retail_wholesale','customer_credit','not_implemented'),
('general_manufacturing','bill_of_materials','not_implemented'),
('general_manufacturing','work_orders','not_implemented'),
('general_manufacturing','production_routing','not_implemented'),
('general_manufacturing','quality_control','not_implemented'),
('construction','project_boq','not_implemented'),
('construction','project_budget','not_implemented'),
('construction','progress_billing','not_implemented'),
('import_export','shipments','implemented_unverified'),
('import_export','currencies','implemented_unverified'),
('import_export','fx_rates','implemented_unverified'),
('import_export','landed_cost','implemented_unverified'),
('import_export','report_by_currency','implemented_unverified'),
('import_export','letter_of_credit','not_implemented'),
('import_export','customs_automation','not_implemented'),
('import_export','accounting_posting','not_implemented'),
('import_export','stock_link','not_implemented'),
('import_export','bank_payments','not_implemented'),
('ecommerce','online_orders','not_implemented'),
('ecommerce','channel_inventory','not_implemented'),
('ecommerce','returns_portal','not_implemented'),
('technology_digital','software_subscription','not_implemented'),
('technology_digital','digital_delivery','not_implemented'),
('technology_digital','service_tickets','not_implemented'),
('services','service_orders','not_implemented'),
('services','time_tracking','not_implemented'),
('services','contract_billing','not_implemented');
-- Business identity references only canonical template codes in this isolated schema.
-- Never mutate legacy production template rows or existing IDs.
INSERT INTO c10_demo.templates(code,source_status,demo_allowed,enterprise_certified)
 SELECT id,'not_implemented',false,false FROM c10_demo.industry_catalog_v2
 ON CONFLICT(code) DO NOTHING;
ALTER TABLE c10_demo.industry_catalog_v2 ENABLE ROW LEVEL SECURITY;
ALTER TABLE c10_demo.industry_module_catalog_v2 ENABLE ROW LEVEL SECURITY;
CREATE POLICY industry_catalog_authenticated_v2 ON c10_demo.industry_catalog_v2
 FOR SELECT TO authenticated USING(true);
CREATE POLICY industry_module_catalog_authenticated_v2 ON c10_demo.industry_module_catalog_v2
 FOR SELECT TO authenticated USING(true);
REVOKE ALL ON c10_demo.industry_catalog_v2,c10_demo.industry_module_catalog_v2 FROM PUBLIC;
GRANT SELECT ON c10_demo.industry_catalog_v2,c10_demo.industry_module_catalog_v2 TO authenticated;

CREATE FUNCTION c10_demo.setup_industry_draft_v2(
 p_legal bigint,p_slug text,p_template_id text,p_display_name text,p_mode text,
 p_sites jsonb,p_modules jsonb,p_request text,p_brand_hex text)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE
 v_tenant bigint;v_business bigint;v_prev record;v_manifest jsonb;
 v_sites jsonb;v_site jsonb;v_mod text;v_modules text[]:=ARRAY[]::text[];
 v_signatures text[]:=ARRAY[]::text[];v_sig text;v_ix int:=0;v_request text;
BEGIN
 IF c10_demo.actor_uid() IS NULL OR
   p_legal IS NULL OR p_template_id IS NULL OR
   p_slug IS NULL OR p_slug !~ '^[a-z][a-z0-9-]{0,79}$' OR
   p_display_name IS NULL OR length(btrim(p_display_name)) NOT BETWEEN 1 AND 120 OR
   p_mode IS NULL OR p_mode NOT IN ('quick','advanced') OR
   p_request IS NULL OR length(btrim(p_request)) NOT BETWEEN 1 AND 110 OR
   p_brand_hex IS NULL OR p_brand_hex !~ '^#[0-9A-Fa-f]{6}$' THEN
  RAISE EXCEPTION 'invalid_industry_setup';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM c10_demo.industry_catalog_v2 WHERE id=p_template_id) THEN
  RAISE EXCEPTION 'unknown_industry_template';
 END IF;
 SELECT tenant_id INTO v_tenant FROM c10_demo.legal_entities WHERE id=p_legal;
 IF v_tenant IS NULL OR NOT c10_demo.can_tenant(v_tenant) THEN
  RAISE EXCEPTION 'industry_setup_not_authorized';
 END IF;
 IF p_modules IS NULL OR jsonb_typeof(p_modules)<>'array' OR jsonb_array_length(p_modules)>100 THEN
  RAISE EXCEPTION 'invalid_module_manifest';
 END IF;
 FOR v_mod IN SELECT value FROM jsonb_array_elements_text(p_modules) LOOP
  IF v_mod IS NULL OR v_mod=ANY(v_modules) OR NOT EXISTS(
   SELECT 1 FROM c10_demo.industry_module_catalog_v2
   WHERE industry_id=p_template_id AND module_code=v_mod) THEN
   RAISE EXCEPTION 'invalid_module_manifest';
  END IF;
  v_modules:=array_append(v_modules,v_mod);
 END LOOP;
 IF p_mode='quick' THEN
  IF p_sites IS NOT NULL AND p_sites<>'[]'::jsonb THEN RAISE EXCEPTION 'quick_custom_sites_denied'; END IF;
  v_sites:='[{"kind":"showroom","label":"Main Showroom"}]'::jsonb;
 ELSE
  IF p_sites IS NULL OR jsonb_typeof(p_sites)<>'array' OR
    jsonb_array_length(p_sites) NOT BETWEEN 1 AND 500 THEN
    RAISE EXCEPTION 'invalid_industry_sites';
  END IF;
  v_sites:=p_sites;
 END IF;
 FOR v_site IN SELECT value FROM jsonb_array_elements(v_sites) LOOP
  IF jsonb_typeof(v_site)<>'object' OR
    (SELECT count(*) FROM jsonb_object_keys(v_site))<>2 OR
    v_site->>'kind' NOT IN ('showroom','factory','godown','warehouse','project') OR
    length(btrim(coalesce(v_site->>'label',''))) NOT BETWEEN 1 AND 120 THEN
   RAISE EXCEPTION 'invalid_industry_sites';
  END IF;
  v_sig:=v_site->>'kind'||':'||lower(btrim(v_site->>'label'));
  IF v_sig=ANY(v_signatures) THEN RAISE EXCEPTION 'duplicate_industry_site'; END IF;
  v_signatures:=array_append(v_signatures,v_sig);
 END LOOP;
 v_request:='industry-v2:'||p_request;
 v_manifest:=jsonb_build_object('legal',p_legal,'slug',p_slug,'template',p_template_id,
    'name',p_display_name,'mode',p_mode,'sites',v_sites,'modules',to_jsonb(v_modules),
    'brand',p_brand_hex);
 SELECT business_id,payload,created_by INTO v_prev
 FROM c10_demo.business_setup_runs_v1
 WHERE tenant_id=v_tenant AND request_key=v_request;
 IF FOUND THEN
  IF v_prev.payload<>v_manifest OR v_prev.created_by<>c10_demo.actor_uid() THEN
   RAISE EXCEPTION 'idempotency_key_payload_conflict';
  END IF;
  RETURN v_prev.business_id;
 END IF;
 INSERT INTO c10_demo.businesses(tenant_id,legal_entity_id,slug,template_code,request_key,status)
 VALUES(v_tenant,p_legal,p_slug,p_template_id,v_request,'draft')
 ON CONFLICT(tenant_id,request_key) DO NOTHING RETURNING id INTO v_business;
 IF v_business IS NULL THEN
  SELECT id,legal_entity_id,slug,template_code INTO v_prev FROM c10_demo.businesses
  WHERE tenant_id=v_tenant AND request_key=v_request;
  IF NOT FOUND OR v_prev.legal_entity_id<>p_legal OR v_prev.slug<>p_slug OR
    v_prev.template_code<>p_template_id THEN
   RAISE EXCEPTION 'idempotency_key_payload_conflict';
  END IF;
  v_business:=v_prev.id;
 END IF;
 INSERT INTO c10_demo.business_configuration_v1(
  business_id,tenant_id,display_name,brand_hex,setup_mode,setup_status,created_by)
 VALUES(v_business,v_tenant,p_display_name,p_brand_hex,p_mode,'draft',c10_demo.actor_uid())
 ON CONFLICT(business_id) DO NOTHING;
 SELECT display_name,brand_hex,setup_mode,created_by INTO v_prev FROM c10_demo.business_configuration_v1
 WHERE business_id=v_business;
 IF v_prev.display_name<>p_display_name OR v_prev.brand_hex<>p_brand_hex OR
    v_prev.setup_mode<>p_mode OR v_prev.created_by<>c10_demo.actor_uid() THEN
   RAISE EXCEPTION 'idempotency_key_payload_conflict';
 END IF;
 FOR v_site IN SELECT value FROM jsonb_array_elements(v_sites) LOOP
  v_ix:=v_ix+1;
  PERFORM c10_demo.provision_site(v_business,v_site->>'kind',v_site->>'label',
    v_request||':site:'||lpad(v_ix::text,4,'0'));
 END LOOP;
 INSERT INTO c10_demo.business_module_settings_v1(
   tenant_id,business_id,module_code,visibility,operational_enabled)
 SELECT v_tenant,v_business,mod,'locked',false FROM unnest(v_modules) AS mod
 ON CONFLICT(business_id,module_code) DO NOTHING;
 INSERT INTO c10_demo.business_setup_runs_v1(
   tenant_id,business_id,request_key,payload,created_by)
 VALUES(v_tenant,v_business,v_request,v_manifest,c10_demo.actor_uid())
 ON CONFLICT(tenant_id,request_key) DO NOTHING;
 SELECT business_id,payload,created_by INTO v_prev FROM c10_demo.business_setup_runs_v1
 WHERE tenant_id=v_tenant AND request_key=v_request;
 IF v_prev.business_id<>v_business OR v_prev.payload<>v_manifest OR
    v_prev.created_by<>c10_demo.actor_uid() THEN
   RAISE EXCEPTION 'idempotency_key_payload_conflict';
 END IF;
 RETURN v_business;
END $$;
REVOKE EXECUTE ON FUNCTION c10_demo.setup_industry_draft_v2(
 bigint,text,text,text,text,jsonb,jsonb,text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION c10_demo.setup_industry_draft_v2(
 bigint,text,text,text,text,jsonb,jsonb,text,text) TO authenticated;
-- Release invariant: operational_enabled is always false, setup_status=draft.
