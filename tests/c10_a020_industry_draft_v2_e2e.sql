\set ON_ERROR_STOP on
\echo CORE10 A020 v2 - ten-industry draft provisioning, signed-role fixture and isolation
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
DO $$
DECLARE v RECORD;v_id bigint;v_retry bigint;v_count integer:=0;v_first_mod text;
BEGIN
 FOR v IN SELECT id FROM c10_demo.industry_catalog_v2 ORDER BY id LOOP
  SELECT module_code INTO v_first_mod FROM c10_demo.industry_module_catalog_v2
    WHERE industry_id=v.id ORDER BY module_code LIMIT 1;
  v_id:=c10_demo.setup_industry_draft_v2(11,'industry-'||replace(v.id,'_','-'),
    v.id,'New '||v.id,'quick',NULL,to_jsonb(ARRAY[v_first_mod]),
    'request-'||v.id,'#7C263A');
  v_retry:=c10_demo.setup_industry_draft_v2(11,'industry-'||replace(v.id,'_','-'),
    v.id,'New '||v.id,'quick','[]'::jsonb,to_jsonb(ARRAY[v_first_mod]),
    'request-'||v.id,'#7C263A');
  IF v_id<>v_retry THEN RAISE EXCEPTION 'non-idempotent setup for %',v.id; END IF;
  IF (SELECT status FROM c10_demo.businesses WHERE id=v_id)<>'draft' OR
     (SELECT setup_status FROM c10_demo.business_configuration_v1 WHERE business_id=v_id)<>'draft' OR
     (SELECT count(*) FROM c10_demo.sites WHERE business_id=v_id)<>1 OR
     (SELECT count(*) FROM c10_demo.business_module_settings_v1 WHERE business_id=v_id)<>1 OR
     (SELECT count(*) FROM c10_demo.business_module_settings_v1 WHERE business_id=v_id AND
        visibility='locked' AND operational_enabled=false)<>1 THEN
   RAISE EXCEPTION 'draft-only invariant failed for %',v.id;
  END IF;
  v_count:=v_count+1;
 END LOOP;
 IF v_count<>10 THEN RAISE EXCEPTION 'expected all ten canonical template drafts'; END IF;
 BEGIN
  PERFORM c10_demo.setup_industry_draft_v2(11,'industry-construction','construction',
    'Changed Name','quick',NULL,'[]'::jsonb,'request-construction','#7C263A');
  RAISE EXCEPTION 'accepted mutated retry key';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'idempotency_key_payload_conflict' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM c10_demo.setup_industry_draft_v2(11,'unlisted','surprise_unknown',
    'Unknown','quick',NULL,'[]'::jsonb,'unknown-request','#7C263A');
  RAISE EXCEPTION 'accepted unknown industry';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'unknown_industry_template' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM c10_demo.setup_industry_draft_v2(11,'bad-module','restaurant',
    'Wrong module','quick',NULL,'["role_admin"]'::jsonb,'module-unknown','#7C263A');
  RAISE EXCEPTION 'accepted undeclared module';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'invalid_module_manifest' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM c10_demo.setup_industry_draft_v2(11,'duplicated-module','restaurant',
    'Duplicate module','quick',NULL,'["restaurant_pos","restaurant_pos"]'::jsonb,
    'module-duplicate','#7C263A');
  RAISE EXCEPTION 'accepted duplicate modules';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'invalid_module_manifest' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM c10_demo.setup_industry_draft_v2(11,'duplicate-site','construction',
    'Bad site','advanced',
    '[{"kind":"showroom","label":"A"},{"kind":"showroom","label":"a"}]'::jsonb,
    '[]'::jsonb,'site-duplicate','#7C263A');
  RAISE EXCEPTION 'accepted duplicate site';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'duplicate_industry_site' THEN RAISE; END IF;
 END;
 IF EXISTS(SELECT 1 FROM c10_demo.businesses WHERE slug IN
 ('unlisted','bad-module','duplicated-module','duplicate-site')) THEN
  RAISE EXCEPTION 'invalid calls inserted a partial business';
 END IF;
END $$;
COMMIT;
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','77777777-7777-4777-8777-777777777777',true);
DO $$
DECLARE v_business bigint;
BEGIN
 IF EXISTS(SELECT 1 FROM c10_demo.business_setup_overview_v1 WHERE slug LIKE 'industry-%')
    OR EXISTS(SELECT 1 FROM c10_demo.business_module_settings_v1 WHERE tenant_id=1)
    OR EXISTS(SELECT 1 FROM c10_demo.business_configuration_v1 WHERE tenant_id=1)
 THEN RAISE EXCEPTION 'cross-tenant industry settings leaked'; END IF;
 BEGIN
  PERFORM c10_demo.setup_industry_draft_v2(11,'wrong-tenant','services',
     'Wrong tenant','quick',NULL,'[]'::jsonb,'cross-tenant-key','#7C263A');
  RAISE EXCEPTION 'foreign tenant setup was allowed';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'industry_setup_not_authorized' THEN RAISE; END IF;
 END;
 v_business:=c10_demo.setup_industry_draft_v2(21,'own-tenant-service','services',
  'My Service','quick',NULL,'["service_orders"]'::jsonb,'own-service','#112233');
 IF (SELECT tenant_id FROM c10_demo.businesses WHERE id=v_business)<>2 THEN
  RAISE EXCEPTION 'customer setup wrong tenant';
 END IF;
END $$;
COMMIT;
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',true);
DO $$
BEGIN
 BEGIN
  PERFORM c10_demo.setup_industry_draft_v2(11,'manager-forgery','restaurant',
     'Manager attempt','quick',NULL,'[]'::jsonb,'manager-forgery','#7C263A');
  RAISE EXCEPTION 'manager created another business';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'industry_setup_not_authorized' THEN RAISE; END IF;
 END;
END $$;
ROLLBACK;
BEGIN;
SET LOCAL ROLE anon;
DO $$
BEGIN
 BEGIN
  PERFORM c10_demo.setup_industry_draft_v2(11,'anon-forgery','ecommerce',
    'Anon attempt','quick',NULL,'[]'::jsonb,'anon-key','#7C263A');
  RAISE EXCEPTION 'anonymous called privileged provisioning';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
ROLLBACK;
\echo PASS: 10 industry draft setups, idempotency, locked modules, tenant and role boundaries.
