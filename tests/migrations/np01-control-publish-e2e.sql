-- NP01 B-020: disposable business + Owner Control check on real approval policy publishing.
-- Must run on PostgreSQL 17 after 0100-0102, never on hosted/legacy databases.
\set ON_ERROR_STOP on
BEGIN;
INSERT INTO core10.tenants(id,slug) VALUES (99601,'np01-b020-owner-tenant');
INSERT INTO core10.legal_entities(id,tenant_id,label) VALUES (99611,99601,'NP01 B020 Owner Legal');
INSERT INTO core10.businesses(id,tenant_id,legal_entity_id,slug,template_code,request_key)
 VALUES (99621,99601,99611,'np01-b020-business','sweets_bakery','np01_b020_business_01');
INSERT INTO core10.tenant_members(tenant_id,user_id,role)
 VALUES (99601,'99666666-1111-4111-8111-111111111111'::uuid,'tenant_owner');
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims','{"sub":"99666666-1111-4111-8111-111111111111"}',true);
SELECT set_config('request.jwt.claim.sub','99666666-1111-4111-8111-111111111111',true);

DO $np01$
DECLARE pol bigint; cfg jsonb; latest bigint;
BEGIN
 pol:=core10.publish_approval_policy_v1(99621,'stock','adjust',30,'np01_b020_allowed_01');
 IF pol IS NULL THEN RAISE EXCEPTION 'NP01_CONTROL_INITIAL_PUBLISH_MISSING'; END IF;
 cfg:=core10.control_set_v1(99621,NULL,'gov002.approval_policy',false,0::smallint,'{}',NULL,
       false,0,'Owner disables policy publishing now','np01_b020_disable_01');
 IF (cfg->>'version')::int<>1 THEN RAISE EXCEPTION 'NP01_CONTROL_DISABLE_VERSION'; END IF;
 BEGIN
   PERFORM core10.publish_approval_policy_v1(99621,'stock','adjust',30,'np01_b020_denied_01');
   RAISE EXCEPTION 'NP01_CONTROL_DISABLED_PUBLISH_UNEXPECTED_SUCCESS';
 EXCEPTION WHEN OTHERS THEN
   IF SQLERRM NOT LIKE 'CONTROL_DISABLED:gov002.approval_policy%' THEN RAISE; END IF;
 END;
 IF EXISTS (SELECT 1 FROM core10.approval_policy_versions_v1
    WHERE business_id=99621 AND request_key='np01_b020_denied_01') THEN
   RAISE EXCEPTION 'NP01_CONTROL_DISABLED_CREATED_POLICY';
 END IF;
 cfg:=core10.control_set_v1(99621,NULL,'gov002.approval_policy',true,0::smallint,
       '{"ttl_minutes":55}'::jsonb,NULL,false,1,
       'Owner restores publishing with new default','np01_b020_enable_02');
 IF (cfg->>'version')::int<>2 THEN RAISE EXCEPTION 'NP01_CONTROL_ENABLE_VERSION'; END IF;
 latest:=core10.publish_approval_policy_v1(99621,'stock','adjust',NULL,'np01_b020_default_01');
 IF latest IS NULL OR (SELECT ttl_minutes FROM core10.approval_policy_versions_v1
    WHERE id=latest)<>55 THEN RAISE EXCEPTION 'NP01_CONTROL_OWNER_TTL_DEFAULT_IGNORED'; END IF;
 RAISE NOTICE 'NP01_B020_POLICY_CONTROL_OK';
END $np01$;
ROLLBACK;
