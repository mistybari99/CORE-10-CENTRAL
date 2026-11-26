-- NP01 disposable PostgreSQL 17 proof for 0014–0016 (never run on hosted DB).
-- Signed GoTrue parity is NOT implied: actor identity comes from synthetic test claim.
DO $np01$
DECLARE
  owner_uid uuid:='11111111-1111-4111-8111-111111111111';
  maker_uid uuid:='22222222-2222-4222-8222-222222222222';
  foreign_uid uuid:='33333333-3333-4333-8333-333333333333';
  pol bigint; req bigint; esc bigint; ev bigint; readiness jsonb; risk jsonb;
  v_status text; v_count bigint;
BEGIN
 INSERT INTO core10.tenants(id,slug) VALUES
   (99101,'np01-synthetic-tenant-a'),(99102,'np01-synthetic-tenant-b');
 INSERT INTO core10.legal_entities(id,tenant_id,label) VALUES
   (99111,99101,'NP01 synthetic legal A'),(99112,99102,'NP01 synthetic legal B');
 INSERT INTO core10.templates(code,source_status,demo_allowed,enterprise_certified)
 VALUES('np01_synthetic','not_implemented',false,false) ON CONFLICT DO NOTHING;
 INSERT INTO core10.businesses(id,tenant_id,legal_entity_id,slug,template_code,request_key)
 VALUES(99121,99101,99111,'np01-synthetic-business-a','np01_synthetic','np01_business_01'),
       (99122,99102,99112,'np01-synthetic-business-b','np01_synthetic','np01_business_02');
 INSERT INTO core10.tenant_members(tenant_id,user_id,role)
 VALUES(99101,owner_uid,'tenant_owner'),(99102,foreign_uid,'tenant_owner');
 INSERT INTO core10.business_members(tenant_id,business_id,user_id,role)
 VALUES(99101,99121,maker_uid,'manager');

 PERFORM set_config('request.jwt.claims','{}',true);
 PERFORM set_config('request.jwt.claim.sub',owner_uid::text,true);
 pol:=core10.publish_approval_policy_v1(
     99121,'stock','adjust',30,'np01_policy_00001');
 IF pol IS NULL THEN RAISE EXCEPTION 'NP01 policy publish missing'; END IF;
 PERFORM core10.configure_approval_threshold_v1(
    pol,'quantity','KG',4.125,3,'np01_threshold_00001');
 IF (SELECT unit_code FROM core10.approval_thresholds_v1 WHERE policy_id=pol)<>'KG'
 THEN RAISE EXCEPTION 'NP01 threshold unit persisted incorrectly'; END IF;

 PERFORM set_config('request.jwt.claim.sub',maker_uid::text,true);
 v_status:=core10.assess_current_approval_threshold_v1(
     99121,'stock','adjust','{"amount":4.125,"unit":"KG"}'::jsonb);
 IF v_status<>'REVIEW_REQUIRED' THEN RAISE EXCEPTION 'NP01 threshold assessment %',v_status; END IF;
 v_status:=core10.assess_current_approval_threshold_v1(
     99121,'stock','adjust','{"amount":2.000,"unit":"KG"}'::jsonb);
 IF v_status<>'BELOW_THRESHOLD' THEN RAISE EXCEPTION 'NP01 below threshold assessment %',v_status; END IF;
 BEGIN
   PERFORM core10.submit_typed_approval_v1(
     99121,'stock','adjust','np01_bad_unit',1,
     '{"amount":4.125,"unit":"PCS"}'::jsonb,'np01_wrong_unit_01');
   RAISE EXCEPTION 'NP01 FAIL: unit mismatch submitted';
 EXCEPTION WHEN raise_exception THEN
   IF SQLERRM<>'approval_threshold_unit_or_amount_invalid' THEN RAISE; END IF;
 END;
 req:=core10.submit_typed_approval_v1(
    99121,'stock','adjust','np01_candidate',1,
    '{"amount":4.125,"unit":"KG"}'::jsonb,'np01_req_000001');
 IF req IS NULL THEN RAISE EXCEPTION 'NP01 valid typed request missing'; END IF;
 esc:=core10.request_approval_exception_v1(
    req,'Owner review of discrepancy', 'urgent',20,'np01_exception_0001');
 IF esc IS NULL THEN RAISE EXCEPTION 'NP01 exception request missing'; END IF;
 PERFORM set_config('request.jwt.claim.sub',owner_uid::text,true);
 ev:=core10.decide_approval_exception_v1(
    esc,'acknowledged','np01_exception_ack_0001');
 IF ev IS NULL THEN RAISE EXCEPTION 'NP01 exception receipt missing'; END IF;
 IF (SELECT status FROM core10.approval_requests WHERE id=req)<>'pending'
 THEN RAISE EXCEPTION 'NP01 exception acknowledgement wrongly changed approval state'; END IF;
 IF (SELECT count(*) FROM core10.stock_movements WHERE business_id=99121)<>0
 THEN RAISE EXCEPTION 'NP01 exception posted stock'; END IF;
 -- GOV003 is default OFF: this pre-existing positive fixture explicitly enables it
 -- through canonical Owner Control before the GOV003 assertions.
 PERFORM core10.control_set_v1(99121,NULL,'gov003.review_export',
 true,0::smallint,'{"max_rows":100,"metadata_only":true}'::jsonb,
 NULL,false,0,'Owner enables GOV003 integration proof','np01_0113_gov_fixture_01');
 readiness:=core10.gov003_audit_readiness_v1(99121);
 IF readiness->>'release_certified'<>'false'
  OR readiness#>>'{canonical_chain,ok}'<>'true'
 THEN RAISE EXCEPTION 'NP01 GOV003 readiness incorrect: %',readiness; END IF;
 risk:=core10.gov003_audit_risk_v1(99121,now()-INTERVAL '1 day');
 IF risk->>'advisory_only'<>'true' THEN RAISE EXCEPTION 'NP01 risk not advisory'; END IF;
 SELECT count(*) INTO v_count FROM core10.gov003_audit_export_v1(99121,0,100);
 IF v_count<2 THEN RAISE EXCEPTION 'NP01 GOV003 canonical export missing events: %',v_count; END IF;

 PERFORM set_config('request.jwt.claim.sub',maker_uid::text,true);
 BEGIN
   PERFORM core10.gov003_audit_readiness_v1(99121);
   RAISE EXCEPTION 'NP01 FAIL: manager accessed Owner readiness';
 EXCEPTION WHEN insufficient_privilege THEN
   IF SQLERRM<>'gov003_readiness_denied' THEN RAISE; END IF;
 END;
 BEGIN
   PERFORM core10.gov003_audit_export_v1(99121,0,100);
   RAISE EXCEPTION 'NP01 FAIL: manager accessed Owner export';
 EXCEPTION WHEN insufficient_privilege THEN
   IF SQLERRM<>'gov003_export_denied' THEN RAISE; END IF;
 END;
 PERFORM set_config('request.jwt.claim.sub',foreign_uid::text,true);
 BEGIN
   PERFORM core10.gov003_audit_risk_v1(99121,now()-interval '1 day');
   RAISE EXCEPTION 'NP01 FAIL: foreign tenant accessed risk';
 EXCEPTION WHEN insufficient_privilege THEN
   IF SQLERRM<>'gov003_risk_denied' THEN RAISE; END IF;
 END;
 BEGIN
   PERFORM core10.configure_approval_threshold_v1(
     pol,'quantity','KG',4.125,3,'np01_threshold_bad_01');
   RAISE EXCEPTION 'NP01 FAIL: foreign Owner configured threshold';
 EXCEPTION WHEN raise_exception THEN
   IF SQLERRM<>'threshold_not_authorized' THEN RAISE; END IF;
 END;
 RAISE NOTICE 'NP01_POSTGRES_GOVERNANCE_E2E_OK req=% escrow=% audited=%',req,esc,v_count;
END $np01$;
