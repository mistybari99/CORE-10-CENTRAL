\set ON_ERROR_STOP on
\echo CORE10 A020: same transactional Quick/Advanced engine, draft-only, site+brand+module scope

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
DO $$
DECLARE v_quick bigint;v_quick_again bigint;v_advanced bigint;v_large bigint;
 v_sites jsonb;
BEGIN
 v_quick:=c10_demo.setup_business_v1(11,'quick-demo','food_manufacturing',
  'Quick Demo','quick',NULL,'quick-request-001','#6D1D2A');
 v_quick_again:=c10_demo.setup_business_v1(11,'quick-demo','food_manufacturing',
  'Quick Demo','quick','[]'::jsonb,'quick-request-001','#6D1D2A');
 IF v_quick<>v_quick_again THEN RAISE EXCEPTION 'quick setup retry changed business ID'; END IF;
 IF (SELECT count(*) FROM c10_demo.sites WHERE business_id=v_quick)<>1 OR
   (SELECT count(*) FROM c10_demo.stock_locations l
     JOIN c10_demo.sites s ON s.id=l.site_id WHERE s.business_id=v_quick)<>1 THEN
  RAISE EXCEPTION 'quick setup missing canonical site/location';
 END IF;
 IF (SELECT setup_status FROM c10_demo.business_configuration_v1
    WHERE business_id=v_quick)<>'draft' OR
    (SELECT status FROM c10_demo.businesses WHERE id=v_quick)<>'draft' THEN
  RAISE EXCEPTION 'quick setup falsely marked ready';
 END IF;
 IF (SELECT brand_hex FROM c10_demo.business_configuration_v1
     WHERE business_id=v_quick)<>'#6D1D2A' THEN
  RAISE EXCEPTION 'business-specific brand missing';
 END IF;
 IF (SELECT count(*) FROM c10_demo.business_module_settings_v1
     WHERE business_id=v_quick)<>7 OR EXISTS (
    SELECT 1 FROM c10_demo.business_module_settings_v1
      WHERE business_id=v_quick
       AND (visibility<>'locked' OR operational_enabled<>false)) THEN
  RAISE EXCEPTION 'modules falsely enabled or omitted';
 END IF;
 BEGIN
  PERFORM c10_demo.setup_business_v1(11,'quick-demo','food_manufacturing',
   'Different Brand','quick',NULL,'quick-request-001','#6D1D2A');
  RAISE EXCEPTION 'retry accepted mutated profile';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'idempotency_key_payload_conflict' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM c10_demo.setup_business_v1(11,'invalid-quick','food_manufacturing',
   'Quick Invalid','quick','[{"kind":"factory","label":"Factory"}]'::jsonb,
   'invalid-quick-request','#334155');
  RAISE EXCEPTION 'quick accepted custom advanced layout';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'quick_setup_does_not_accept_custom_sites' THEN RAISE; END IF;
 END;
 IF EXISTS(SELECT 1 FROM c10_demo.businesses WHERE slug='invalid-quick') THEN
  RAISE EXCEPTION 'failed quick setup left orphan business';
 END IF;

 v_sites:='[{"kind":"showroom","label":"New Showroom"},
            {"kind":"factory","label":"Main Factory"},
            {"kind":"godown","label":"Raw Material Godown"}]'::jsonb;
 v_advanced:=c10_demo.setup_business_v1(11,'advanced-demo','food_manufacturing',
   'Advanced Demo','advanced',v_sites,'advanced-request-001','#334155');
 IF (SELECT count(*) FROM c10_demo.sites WHERE business_id=v_advanced)<>3 OR
    (SELECT count(*) FROM c10_demo.stock_locations l
      JOIN c10_demo.sites s ON s.id=l.site_id
      WHERE s.business_id=v_advanced)<>3 THEN
  RAISE EXCEPTION 'advanced setup site/location count';
 END IF;
 IF c10_demo.setup_business_v1(11,'advanced-demo','food_manufacturing',
   'Advanced Demo','advanced',v_sites,'advanced-request-001','#334155')<>v_advanced THEN
  RAISE EXCEPTION 'advanced retry differs';
 END IF;
 BEGIN
  PERFORM c10_demo.setup_business_v1(11,'duplicate-site-demo','food_manufacturing',
   'Invalid Advanced','advanced',
   '[{"kind":"showroom","label":"Twin"},{"kind":"showroom","label":"Twin"}]'::jsonb,
   'bad-manifest-001','#334155');
  RAISE EXCEPTION 'accepted duplicate site manifest';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'duplicate_site_manifest' THEN RAISE; END IF;
 END;
 IF EXISTS(SELECT 1 FROM c10_demo.businesses WHERE slug='duplicate-site-demo') THEN
  RAISE EXCEPTION 'failed setup was not atomic';
 END IF;
 BEGIN
  PERFORM c10_demo.setup_business_v1(11,'not-built-paint','hardware_paint',
   'Paint Not Ready','quick',NULL,'not-built-template','#334155');
  RAISE EXCEPTION 'unimplemented template was activated';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'business_template_not_implemented' THEN RAISE; END IF;
 END;
 -- 303 sites: >100 showroom, >100 factory, >100 godown; structural capability
 -- demonstration ONLY, not concurrency/load or 300-site production certification.
 SELECT jsonb_agg(jsonb_build_object('kind',
   CASE WHEN n%3=1 THEN 'showroom' WHEN n%3=2 THEN 'factory' ELSE 'godown' END,
   'label','Unit '||n) ORDER BY n)
 INTO v_sites FROM generate_series(1,303) AS n;
 v_large:=c10_demo.setup_business_v1(11,'enterprise-site-fixture',
  'food_manufacturing','Site Fixture','advanced',v_sites,'large-sites-303','#334155');
 IF (SELECT count(*) FROM c10_demo.sites WHERE business_id=v_large)<>303 THEN
  RAISE EXCEPTION '300+ site provisioning failed';
 END IF;
 IF EXISTS(SELECT 1 FROM (VALUES('showroom'),('factory'),('godown')) AS x(kind)
   WHERE (SELECT count(*) FROM c10_demo.sites s
    WHERE s.business_id=v_large AND s.kind=x.kind)<101) THEN
  RAISE EXCEPTION '100+ type-wise capacity fixture failed';
 END IF;
 IF (SELECT count(*) FROM c10_demo.business_setup_overview_v1
   WHERE business_id=v_large AND visible_sites=303 AND setup_status='draft')<>1 THEN
  RAISE EXCEPTION 'enterprise setup overview failed';
 END IF;
END $$;
COMMIT;

-- Separate independent tenant owner: no access to first tenant's brand, modules or setup.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','77777777-7777-4777-8777-777777777777',true);
DO $$
DECLARE v_customer bigint;
BEGIN
 IF EXISTS(SELECT 1 FROM c10_demo.business_configuration_v1 WHERE tenant_id=1)
    OR EXISTS(SELECT 1 FROM c10_demo.business_setup_overview_v1 WHERE tenant_id=1) THEN
  RAISE EXCEPTION 'customer sees portfolio setup';
 END IF;
 BEGIN
  PERFORM c10_demo.setup_business_v1(11,'illegal-cross-setup','food_manufacturing',
   'Cross Tenant','quick',NULL,'cross-setup','#334155');
  RAISE EXCEPTION 'customer provisioned foreign legal entity';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'setup_not_authorized' THEN RAISE; END IF;
 END;
 v_customer:=c10_demo.setup_business_v1(21,'customer-added','food_manufacturing',
  'Customer Added','quick',NULL,'customer-quick-01','#112233');
 IF (SELECT tenant_id FROM c10_demo.businesses WHERE id=v_customer)<>2 THEN
  RAISE EXCEPTION 'independent customer tenant assignment';
 END IF;
 IF (SELECT count(*) FROM c10_demo.business_configuration_v1)<>1 THEN
  RAISE EXCEPTION 'cross-tenant config leak after customer setup';
 END IF;
END $$;
COMMIT;

-- Business manager, investor and other tenant role claims have zero setup privilege.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',true);
SELECT set_config('request.jwt.claim.role','tenant_owner',true);
DO $$
BEGIN
 BEGIN
  PERFORM c10_demo.setup_business_v1(11,'manager-setup','food_manufacturing',
   'Forged Owner','quick',NULL,'manager-try-01','#334155');
  RAISE EXCEPTION 'manager forged setup';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'setup_not_authorized' THEN RAISE; END IF;
 END;
END $$;
ROLLBACK;

BEGIN;
SET LOCAL ROLE anon;
DO $$
BEGIN
 BEGIN
  PERFORM c10_demo.setup_business_v1(11,'anon-setup','food_manufacturing',
   'Anon','quick',NULL,'anon-try','#334155');
  RAISE EXCEPTION 'anon executed setup';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
ROLLBACK;
\echo PASS: Quick/Advanced shared engine, business-local brand/modules, 303 site hierarchy, draft-only and owner/tenant denial.
\echo LIMIT: disposable DB role fixtures; 303 structural nodes not measured enterprise throughput or live UI/SG/HTTP rollout.
