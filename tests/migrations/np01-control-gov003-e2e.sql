-- NP01 / B-020 / 0113 disposable PG17: GOV003 canonical Owner Control and Audit.
-- No hosted apply. Default-off, Auth-first, RLS, metadata-only, dynamic limits,
-- fail-closed stage requirements, one-time override, and evidence-backed RPC registry.
\set ON_ERROR_STOP on
BEGIN;
INSERT INTO core10.tenants(id,slug) VALUES
 (99801,'np01-0113-a'),(99802,'np01-0113-b');
INSERT INTO core10.legal_entities(id,tenant_id,label) VALUES
 (99811,99801,'GOV003 legal A'),(99812,99802,'GOV003 legal B');
INSERT INTO core10.businesses(id,tenant_id,legal_entity_id,slug,template_code,request_key)
 VALUES(99821,99801,99811,'np01-gov003-a','sweets_bakery','np01_0113_business_a'),
       (99822,99802,99812,'np01-gov003-b','restaurant','np01_0113_business_b');
INSERT INTO core10.tenant_members(tenant_id,user_id,role)
 VALUES(99801,'99811111-1111-4111-8111-111111111111','tenant_owner'),
       (99802,'99822222-2222-4222-8222-222222222222','tenant_owner');
INSERT INTO core10.business_members(tenant_id,business_id,user_id,role)
 VALUES(99801,99821,'99833333-3333-4333-8333-333333333333','manager'),
       (99801,99821,'99844444-4444-4444-8444-444444444444','business_owner');
INSERT INTO core10.business_members(tenant_id,business_id,user_id,role,valid_until)
 VALUES(99801,99821,'99855555-5555-4555-8555-555555555555','business_owner',now()-interval '1 day');
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims','{"sub":"99811111-1111-4111-8111-111111111111"}',true);
SELECT set_config('request.jwt.claim.sub','99811111-1111-4111-8111-111111111111',true);
DO $np01$
DECLARE
 a constant text:='99811111-1111-4111-8111-111111111111';
 b constant text:='99822222-2222-4222-8222-222222222222';
 mgr constant text:='99833333-3333-4333-8333-333333333333';
 bo constant text:='99844444-4444-4444-8444-444444444444';
 exp constant text:='99855555-5555-4555-8555-555555555555';
 v jsonb; rd jsonb; risk jsonb; n bigint; old_events bigint;
BEGIN
 -- All three GOV003 ports are OFF by default, even for an authorized tenant Owner.
 BEGIN
  PERFORM core10.gov003_audit_readiness_v1(99821);
  RAISE EXCEPTION 'GOV003_DEFAULT_READINESS_BYPASS';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM NOT LIKE 'CONTROL_DISABLED:gov003.review_export%' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM core10.gov003_audit_risk_v1(99821,now()-interval '1 day');
  RAISE EXCEPTION 'GOV003_DEFAULT_RISK_BYPASS';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM NOT LIKE 'CONTROL_DISABLED:gov003.review_export%' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM core10.gov003_audit_export_v1(99821,0,2);
  RAISE EXCEPTION 'GOV003_DEFAULT_EXPORT_BYPASS';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM NOT LIKE 'CONTROL_DISABLED:gov003.review_export%' THEN RAISE; END IF;
 END;

 -- An authenticated manager, an expired business owner and a foreign Owner
 -- must be denied by canonical Auth BEFORE Control (not leak switch state).
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',mgr)::text,true);
 PERFORM set_config('request.jwt.claim.sub',mgr,true);
 BEGIN
  PERFORM core10.gov003_audit_readiness_v1(99821);
  RAISE EXCEPTION 'GOV003_MANAGER_READINESS_BYPASS';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'gov003_readiness_denied' THEN RAISE; END IF; END;
 BEGIN
  PERFORM core10.gov003_audit_risk_v1(99821,now()-interval '1 day');
  RAISE EXCEPTION 'GOV003_MANAGER_RISK_BYPASS';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'gov003_risk_denied' THEN RAISE; END IF; END;
 BEGIN
  PERFORM core10.gov003_audit_export_v1(99821,0,2);
  RAISE EXCEPTION 'GOV003_MANAGER_EXPORT_BYPASS';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'gov003_export_denied' THEN RAISE; END IF; END;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',exp)::text,true);
 PERFORM set_config('request.jwt.claim.sub',exp,true);
 BEGIN
  PERFORM core10.gov003_audit_export_v1(99821,0,2);
  RAISE EXCEPTION 'GOV003_EXPIRED_OWNER_BYPASS';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'gov003_export_denied' THEN RAISE; END IF; END;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',b)::text,true);
 PERFORM set_config('request.jwt.claim.sub',b,true);
 BEGIN
  PERFORM core10.gov003_audit_readiness_v1(99821);
  RAISE EXCEPTION 'GOV003_FOREIGN_READINESS_BYPASS';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'gov003_readiness_denied' THEN RAISE; END IF; END;
 BEGIN
  PERFORM core10.gov003_audit_risk_v1(99821,now()-interval '1 day');
  RAISE EXCEPTION 'GOV003_FOREIGN_RISK_BYPASS';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'gov003_risk_denied' THEN RAISE; END IF; END;
 BEGIN
  PERFORM core10.gov003_audit_export_v1(99821,0,2);
  RAISE EXCEPTION 'GOV003_FOREIGN_EXPORT_BYPASS';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'gov003_export_denied' THEN RAISE; END IF; END;
 -- Tenant B can independently enable its own unrelated business.
 v:=core10.control_set_v1(99822,NULL,'gov003.review_export',true,0::smallint,
 '{"max_rows":1,"metadata_only":true}',NULL,false,0,
 'B enables only its own canonical review','np01_0113_b_enabled_01');
 SELECT count(*) INTO n FROM core10.gov003_audit_export_v1(99822,0,1);
 IF n<>1 THEN RAISE EXCEPTION 'GOV003_OWN_B_EXPORT_MISSING'; END IF;
 -- Under B's RLS, tenant A's audit events remain invisible.
 IF EXISTS(SELECT 1 FROM core10.canonical_audit_events_v1 WHERE business_id=99821)
 THEN RAISE EXCEPTION 'GOV003_CROSS_TENANT_RLS'; END IF;

 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',a)::text,true);
 PERFORM set_config('request.jwt.claim.sub',a,true);
 v:=core10.control_set_v1(99821,NULL,'gov003.review_export',true,0::smallint,
 '{"max_rows":2,"metadata_only":true}',NULL,false,0,
 'A enables limited canonical review','np01_0113_a_enabled_01');
 rd:=core10.gov003_audit_readiness_v1(99821);
 risk:=core10.gov003_audit_risk_v1(99821,now()-interval '1 day');
 IF rd->>'release_certified'<>'false' OR rd#>>'{canonical_chain,ok}'<>'true'
 OR risk->>'advisory_only'<>'true' OR risk->>'release_certified'<>'false'
 THEN RAISE EXCEPTION 'GOV003_CANONICAL_AUDIT_ADVISORY_CONTRACT'; END IF;
 SELECT count(*) INTO n FROM core10.gov003_audit_export_v1(99821,0,2);
 IF n<>1 THEN RAISE EXCEPTION 'GOV003_EXPORT_EXPECTED_ONE_EVENT got %',n; END IF;
 -- Approved repeated reads must not append a parallel audit chain or mutate history.
 SELECT count(*) INTO old_events FROM core10.canonical_audit_events_v1 WHERE business_id=99821;
 PERFORM core10.gov003_audit_readiness_v1(99821);
 PERFORM core10.gov003_audit_risk_v1(99821,now()-interval '1 day');
 PERFORM core10.gov003_audit_export_v1(99821,0,2);
 IF (SELECT count(*) FROM core10.canonical_audit_events_v1 WHERE business_id=99821)<>old_events
 THEN RAISE EXCEPTION 'GOV003_ENABLED_READ_REPLAY_MUTATED_AUDIT'; END IF;
 BEGIN
  PERFORM core10.gov003_audit_export_v1(99821,0,3);
  RAISE EXCEPTION 'GOV003_MAX_ROWS_BYPASS';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'CONTROL_LIMIT:max_rows%' THEN RAISE; END IF; END;
 BEGIN
  PERFORM core10.gov003_audit_export_v1(99821,0,0);
  RAISE EXCEPTION 'GOV003_ZERO_LIMIT_BYPASS';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'gov003_export_denied' THEN RAISE; END IF; END;
 BEGIN
  PERFORM core10.gov003_audit_risk_v1(99821,now()+interval '1 day');
  RAISE EXCEPTION 'GOV003_FUTURE_WINDOW_BYPASS';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'gov003_risk_denied' THEN RAISE; END IF; END;
 -- A current business owner (not merely tenant owner) is still authorized.
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',bo)::text,true);
 PERFORM set_config('request.jwt.claim.sub',bo,true);
 IF (core10.gov003_audit_readiness_v1(99821)->>'release_certified')<>'false'
 THEN RAISE EXCEPTION 'GOV003_BUSINESS_OWNER_COMPAT'; END IF;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',a)::text,true);
 PERFORM set_config('request.jwt.claim.sub',a,true);

 v:=core10.control_set_v1(99821,NULL,'gov003.review_export',false,0::smallint,
 '{"max_rows":2,"metadata_only":true}',NULL,false,1,
 'Owner pauses canonical readiness and exports','np01_0113_a_disabled_02');
 BEGIN
  PERFORM core10.gov003_audit_export_v1(99821,0,1);
  RAISE EXCEPTION 'GOV003_DISABLED_EXPORT_BYPASS';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'CONTROL_DISABLED:gov003.review_export%' THEN RAISE; END IF; END;
 BEGIN
  PERFORM core10.gov003_audit_readiness_v1(99821);
  RAISE EXCEPTION 'GOV003_DISABLED_READINESS_BYPASS';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'CONTROL_DISABLED:gov003.review_export%' THEN RAISE; END IF; END;
 BEGIN
  PERFORM core10.gov003_audit_risk_v1(99821,now()-interval '1 day');
  RAISE EXCEPTION 'GOV003_DISABLED_RISK_BYPASS';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'CONTROL_DISABLED:gov003.review_export%' THEN RAISE; END IF; END;

 -- Owner can request an Approval route, but this read adapter cannot execute it.
 -- Deny rather than silently bypass stages 1..5.
 v:=core10.control_set_v1(99821,NULL,'gov003.review_export',true,1::smallint,
 '{"max_rows":2,"metadata_only":true}',NULL,false,2,
 'Owner requires approval for audit reads','np01_0113_a_stages_03');
 BEGIN
  PERFORM core10.gov003_audit_readiness_v1(99821);
  RAISE EXCEPTION 'GOV003_STAGE_READINESS_BYPASS';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'CONTROL_APPROVAL_REQUIRED:gov003.review_export%' THEN RAISE; END IF; END;
 BEGIN
  PERFORM core10.gov003_audit_risk_v1(99821,now()-interval '1 day');
  RAISE EXCEPTION 'GOV003_STAGE_RISK_BYPASS';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'CONTROL_APPROVAL_REQUIRED:gov003.review_export%' THEN RAISE; END IF; END;
 BEGIN
  PERFORM core10.gov003_audit_export_v1(99821,0,1);
  RAISE EXCEPTION 'GOV003_STAGE_EXPORT_BYPASS';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'CONTROL_APPROVAL_REQUIRED:gov003.review_export%' THEN RAISE; END IF; END;

 -- The catalog allows metadata_only=false, but full payload export is not connected.
 -- Deny it instead of emitting PII or claiming an unsupported mode is implemented.
 v:=core10.control_set_v1(99821,NULL,'gov003.review_export',true,0::smallint,
 '{"max_rows":2,"metadata_only":false}',NULL,false,3,
 'Owner requests unconnected full audit export','np01_0113_a_full_04');
 BEGIN
  PERFORM core10.gov003_audit_export_v1(99821,0,1);
  RAISE EXCEPTION 'GOV003_RAW_PAYLOAD_BYPASS';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'CONTROL_METADATA_ONLY_REQUIRED:gov003.review_export%' THEN RAISE; END IF; END;
 -- More than the former fixed 500 rows may be requested, only within Owner's cap.
 v:=core10.control_set_v1(99821,NULL,'gov003.review_export',true,0::smallint,
 '{"max_rows":600,"metadata_only":true}',NULL,false,4,
 'Owner permits six hundred metadata rows','np01_0113_a_large_05');
 SELECT count(*) INTO n FROM core10.gov003_audit_export_v1(99821,0,501);
 IF n<1 OR n>501 THEN RAISE EXCEPTION 'GOV003_501_ROW_LIMIT_NOT_EFFECTIVE'; END IF;
 BEGIN
  PERFORM core10.gov003_audit_export_v1(99821,0,601);
  RAISE EXCEPTION 'GOV003_CONFIGURED_600_CAP_BYPASS';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'CONTROL_LIMIT:max_rows%' THEN RAISE; END IF; END;

 -- A one-time Owner exception is consumed and canonically audited exactly once.
 v:=core10.control_set_v1(99821,NULL,'gov003.review_export',false,0::smallint,
 '{"max_rows":600,"metadata_only":true}',NULL,false,5,
 'Owner disables audit review again for override proof','np01_0113_a_off_06');
 v:=core10.control_grant_override_v1(99821,NULL,'gov003.review_export',1,
 'Allow one readiness check with reason','np01_0113_override_01');
 rd:=core10.gov003_audit_readiness_v1(99821);
 IF rd#>>'{canonical_chain,ok}'<>'true' THEN RAISE EXCEPTION 'GOV003_OVERRIDE_AUDIT'; END IF;
 BEGIN
  PERFORM core10.gov003_audit_readiness_v1(99821);
  RAISE EXCEPTION 'GOV003_OVERRIDE_REPLAY_BYPASS';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'CONTROL_DISABLED:gov003.review_export%' THEN RAISE; END IF; END;
 RAISE NOTICE 'NP01_0113_GOV003_CONTROL_AUTH_RLS_LIMITS_OK';
END $np01$;
-- The API role intentionally cannot read internal registry or override tables.
RESET ROLE;
DO $registry$
DECLARE name text;
BEGIN
 FOREACH name IN ARRAY ARRAY['gov003_audit_readiness_v1',
    'gov003_audit_risk_v1','gov003_audit_export_v1'] LOOP
  IF NOT EXISTS(SELECT 1 FROM core10.control_rpc_map_v1 m
    WHERE m.rpc_name=name AND m.status='enforced'
     AND m.feature_key='gov003.review_export'
     AND m.test_ref='tests/migrations/np01-control-gov003-e2e.sql')
  THEN RAISE EXCEPTION 'GOV003_REGISTRY_NOT_ENFORCED:%',name; END IF;
 END LOOP;
 IF (SELECT count(*) FROM core10.control_overrides_v1 WHERE business_id=99821
   AND feature_key='gov003.review_export' AND consumed_at IS NOT NULL)<>1
 THEN RAISE EXCEPTION 'GOV003_OVERRIDE_NOT_SINGLE_USE'; END IF;
 IF (SELECT count(*) FROM core10.canonical_audit_events_v1
   WHERE business_id=99821 AND action='control.override_consumed')<>1
 THEN RAISE EXCEPTION 'GOV003_CANONICAL_OVERRIDE_AUDIT_MISSING'; END IF;
 IF (SELECT count(*) FROM core10.canonical_audit_events_v1 WHERE business_id=99822)<1
 THEN RAISE EXCEPTION 'GOV003_FOREIGN_BUSINESS_AUDIT_MISSING'; END IF;
 IF NOT (SELECT (core10.verify_canonical_audit_v1(99821)->>'ok')::boolean)
 THEN RAISE EXCEPTION 'GOV003_AUDIT_CHAIN_DAMAGED'; END IF;
 RAISE NOTICE 'NP01_0113_GOV003_REGISTRY_OVERRIDE_AUDIT_OK';
END $registry$;
ROLLBACK;
