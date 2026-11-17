-- NP01/0112: synthetic PostgreSQL 17 proof, no hosted apply.
\set ON_ERROR_STOP on
BEGIN;
INSERT INTO core10.tenants(id,slug) VALUES(99751,'np01-0112-a'),(99752,'np01-0112-b');
INSERT INTO core10.legal_entities(id,tenant_id,label) VALUES(99761,99751,'NP01 A'),(99762,99752,'NP01 B');
INSERT INTO core10.businesses(id,tenant_id,legal_entity_id,slug,template_code,request_key)
 VALUES(99771,99751,99761,'np01-0112-a','sweets_bakery','np01_0112_a'),
       (99772,99752,99762,'np01-0112-b','restaurant','np01_0112_b');
INSERT INTO core10.tenant_members(tenant_id,user_id,role) VALUES
 (99751,'99751111-1111-4111-8111-111111111111','tenant_owner'),
 (99752,'99752222-2222-4222-8222-222222222222','tenant_owner');
INSERT INTO core10.business_members(tenant_id,business_id,user_id,role)
 VALUES(99751,99771,'99753333-3333-4333-8333-333333333333','manager');
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','99751111-1111-4111-8111-111111111111',true);
DO $t$
DECLARE v jsonb; first_site jsonb; replay jsonb;
BEGIN
 v:=core10.control_set_v1(99771,NULL,'setup001.provision',true,0::smallint,
 '{"max_sites":1}',NULL,false,0,'Owner limits business to one site','np01_0112_cfg_01');
 first_site:=core10.build01_site_v1(99771,'showroom','Primary','np01_0112_site_01');
 replay:=core10.build01_site_v1(99771,'showroom','Primary','np01_0112_site_01');
 IF first_site IS DISTINCT FROM replay THEN RAISE EXCEPTION 'SITE_REPLAY_CHANGED'; END IF;
 BEGIN
  PERFORM core10.build01_site_v1(99771,'factory','Second','np01_0112_site_02');
  RAISE EXCEPTION 'SITE_LIMIT_BYPASSED';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM NOT LIKE 'CONTROL_LIMIT:max_sites%' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM core10.build01_site_v1(99771,'showroom','Changed','np01_0112_site_01');
  RAISE EXCEPTION 'SITE_PAYLOAD_BYPASSED';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'BUILD01_REQUEST_CONFLICT' THEN RAISE; END IF;
 END;
 v:=core10.control_set_v1(99771,NULL,'setup001.provision',false,0::smallint,
 '{"max_sites":1}',NULL,false,1,'Owner disables site creation now','np01_0112_cfg_02');
 BEGIN
  PERFORM core10.build01_site_v1(99771,'showroom','Primary','np01_0112_site_01');
  RAISE EXCEPTION 'DISABLED_REPLAY_BYPASSED';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM NOT LIKE 'CONTROL_DISABLED:setup001.provision%' THEN RAISE; END IF;
 END;
 PERFORM set_config('request.jwt.claim.sub','99753333-3333-4333-8333-333333333333',true);
 BEGIN
  PERFORM core10.build01_site_v1(99771,'factory','Manager','np01_0112_mgr_01');
  RAISE EXCEPTION 'MANAGER_BYPASSED';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'BUILD01_SITE_DENIED' THEN RAISE; END IF;
 END;
 PERFORM set_config('request.jwt.claim.sub','99752222-2222-4222-8222-222222222222',true);
 BEGIN
  PERFORM core10.build01_site_v1(99771,'factory','Foreign','np01_0112_for_01');
  RAISE EXCEPTION 'FOREIGN_BYPASSED';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'BUILD01_SITE_DENIED' THEN RAISE; END IF;
 END;
 -- Per-business Control: tenant B's own business remains usable while A is disabled.
 PERFORM core10.build01_site_v1(99772,'showroom','Independent B','np01_0112_b_own_01');
 IF (SELECT count(*) FROM core10.sites WHERE business_id=99772)<>1
 OR (SELECT count(*) FROM core10.sites WHERE business_id=99771)<>1
 THEN RAISE EXCEPTION 'CROSS_BUSINESS_SITE_CONTROL_LEAK'; END IF;
 PERFORM set_config('request.jwt.claim.sub','99751111-1111-4111-8111-111111111111',true);
 v:=core10.control_set_v1(99771,NULL,'setup001.provision',true,0::smallint,
 '{"max_sites":2}',NULL,false,2,'Owner permits two sites now','np01_0112_cfg_03');
 PERFORM core10.build01_site_v1(99771,'factory','Second','np01_0112_site_02');
 IF (SELECT count(*) FROM core10.sites WHERE business_id=99771)<>2
 OR (SELECT count(*) FROM core10.access_change_events_v1 WHERE business_id=99771 AND event_kind='setup.site')<>2
 THEN RAISE EXCEPTION 'SITE_COUNT_OR_REPLAY_SIDE_EFFECT'; END IF;
 IF (core10.verify_canonical_audit_v1(99771)->>'ok')::boolean IS DISTINCT FROM true
 THEN RAISE EXCEPTION 'SITE_AUDIT_INVALID'; END IF;
 RAISE NOTICE 'NP01_0112_SITE_PROVISION_PASS';
END $t$;
-- The registry is deliberately not readable by authenticated clients.
-- Verify mapping with privileged test-runner context, never grant it to API roles.
RESET ROLE;
DO $registry$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM core10.control_rpc_map_v1
  WHERE rpc_name='build01_site_v1' AND status='enforced'
    AND test_ref='tests/migrations/np01-control-site-provision-e2e.sql')
 THEN RAISE EXCEPTION 'SITE_REGISTRY_NOT_ENFORCED'; END IF;
END $registry$;
ROLLBACK;
