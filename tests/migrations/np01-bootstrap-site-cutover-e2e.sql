\set ON_ERROR_STOP on
BEGIN;

INSERT INTO core10.tenants(id,slug) VALUES (9634,'site-cutover');
INSERT INTO core10.tenant_members(tenant_id,user_id,role)
VALUES (9634,'00009634-0000-4000-8000-000000000001','tenant_owner');
INSERT INTO core10.legal_entities(id,tenant_id,label) VALUES (9634,9634,'Site fixture legal');
INSERT INTO core10.templates(code,source_status,demo_allowed) VALUES ('site_legacy_fixture','available',true);

DO $roles$
BEGIN
 IF EXISTS (SELECT 1 FROM pg_proc p WHERE p.pronamespace='core10'::regnamespace
     AND p.proname IN ('provision_site','_provision_site_write_v1')
     AND (has_function_privilege('authenticated',p.oid,'execute')
       OR has_function_privilege('public',p.oid,'execute'))) THEN
  RAISE EXCEPTION 'private site writer remains callable';
 END IF;
END
$roles$;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims','{"sub":"00009634-0000-4000-8000-000000000001"}',true);
SELECT core10.control_set_bootstrap_policy_v1(9634,true,NULL,0,'Enable Business setup fixture','site-bootstrap-on');

DO $test$
DECLARE
 manifest jsonb;
 full_manifest jsonb;
 business bigint;
 receipt jsonb;
 override_id bigint;
BEGIN
 SELECT jsonb_agg(jsonb_build_object('kind','showroom','label','Shop '||n) ORDER BY n)
 INTO full_manifest FROM generate_series(1,51) n;
 manifest:=full_manifest-50;

 -- Both canonical initial setup engines must roll back an oversized manifest.
 BEGIN
  PERFORM core10.setup_business_v1(9634,'site-legacy-too-many','site_legacy_fixture','Legacy draft',
   'advanced',full_manifest,'site-legacy-too-many','#112233');
  RAISE EXCEPTION 'initial v1 site cap bypass';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'CONTROL_LIMIT:max_sites' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM core10.setup_industry_draft_v2(9634,'site-industry-too-many','sweets_bakery','Industry draft',
   'advanced',full_manifest,'[]','site-industry-too-many','#112233');
  RAISE EXCEPTION 'initial v2 site cap bypass';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'CONTROL_LIMIT:max_sites' THEN RAISE; END IF;
 END;
 IF EXISTS (SELECT 1 FROM core10.businesses WHERE tenant_id=9634) THEN
  RAISE EXCEPTION 'failed setup left rows behind';
 END IF;

 receipt:=core10.build01_setup_v1(9634,'site-cap-demo','sweets_bakery','Sweets sites',
   'advanced',manifest,'site-setup-50','#112233');
 business:=(receipt->>'business_id')::bigint;
 IF (SELECT count(*) FROM core10.sites WHERE tenant_id=9634 AND business_id=business)<>50 THEN
  RAISE EXCEPTION '50-site initial setup did not create exactly 50 sites';
 END IF;
 BEGIN
  PERFORM core10.build01_site_v1(business,'warehouse','Shop 51','site-add-51');
  RAISE EXCEPTION 'later site bypassed the initial cap';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'CONTROL_LIMIT:max_sites' THEN RAISE; END IF;
 END;

 PERFORM core10.control_set_v1(business,NULL,'setup001.provision',false,1::smallint,
  '{"max_sites":51}',NULL,false,0,'Require canonical site approval','site-policy-stage');
 override_id:=(core10.control_grant_override_v1(business,NULL,'setup001.provision',1,
   'Test override is not approval','site-override-01')->>'override_id')::bigint;
 BEGIN
  PERFORM core10.build01_site_v1(business,'warehouse','Shop 51','site-add-51');
  RAISE EXCEPTION 'override bypassed required approval';
 EXCEPTION WHEN insufficient_privilege THEN
  IF SQLERRM<>'CONTROL_APPROVAL_REQUIRED:setup001.provision' THEN RAISE; END IF;
 END;
 IF (SELECT count(*) FROM core10.sites WHERE business_id=business)<>50 THEN
  RAISE EXCEPTION 'approval denial wrote a site';
 END IF;
 IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(core10.control_overrides_v1(business)) AS o
  WHERE (o->>'id')::bigint=override_id AND o->>'status'='open') THEN
  RAISE EXCEPTION 'approval denial consumed the one-time override';
 END IF;

 PERFORM core10.control_set_v1(business,NULL,'setup001.provision',true,0::smallint,
  '{"max_sites":51}',NULL,false,1,'Increase this Business site capacity','site-policy-cap51');
 receipt:=core10.build01_site_v1(business,'warehouse','Shop 51','site-add-51');
 IF core10.build01_site_v1(business,'warehouse','Shop 51','site-add-51') IS DISTINCT FROM receipt
 OR (SELECT count(*) FROM core10.sites WHERE business_id=business)<>51 THEN
  RAISE EXCEPTION 'custom cap or retry regressed';
 END IF;
 PERFORM core10.control_set_v1(business,NULL,'setup001.provision',false,0::smallint,
  '{"max_sites":51}',NULL,false,2,'Pause new site creation and retries','site-policy-off');
 BEGIN
  PERFORM core10.build01_site_v1(business,'warehouse','Shop 51','site-add-51');
  RAISE EXCEPTION 'disabled replay used an override';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'CONTROL_DISABLED:setup001.provision' THEN RAISE; END IF;
 END;
 IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(core10.control_overrides_v1(business)) AS o
  WHERE (o->>'id')::bigint=override_id AND o->>'status'='open') THEN
  RAISE EXCEPTION 'disabled replay consumed the one-time override';
 END IF;
 PERFORM core10.control_set_v1(business,NULL,'setup001.provision',true,0::smallint,
  '{"max_sites":51}',NULL,false,3,'Resume site creation at the same cap','site-policy-resume');
 BEGIN
  PERFORM core10.build01_site_v1(business,'warehouse','Shop 52','site-add-52');
  RAISE EXCEPTION 'custom cap bypass';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'CONTROL_LIMIT:max_sites' THEN RAISE; END IF;
 END;
END
$test$;

RESET ROLE;
ROLLBACK;
\echo NP01_BOOTSTRAP_SITE_PROVISIONING_PASS
