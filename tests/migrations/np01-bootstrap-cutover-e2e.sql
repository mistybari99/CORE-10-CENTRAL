\set ON_ERROR_STOP on
BEGIN;

INSERT INTO core10.tenants (id,slug) VALUES (9631,'bootstrap-cutover'),(9632,'bootstrap-foreign');
INSERT INTO core10.tenants (id,slug,bootstrap_policy_initialized) VALUES (9633,'bootstrap-existing',false);
INSERT INTO core10.tenant_members (tenant_id,user_id,role) VALUES
 (9631,'00009631-0000-4000-8000-000000000001','tenant_owner'),
 (9632,'00009632-0000-4000-8000-000000000001','tenant_owner'),
 (9633,'00009633-0000-4000-8000-000000000001','tenant_owner');
INSERT INTO core10.legal_entities (id,tenant_id,label) VALUES
 (9631,9631,'Fixture A'),(9632,9632,'Fixture B'),(9633,9633,'Fixture existing');

-- Numbered migrations use the canonical industry codes. Seed the older
-- compatible template only to exercise the separate v1 writer fixture.
INSERT INTO core10.templates (code,source_status,demo_allowed)
 VALUES ('bootstrap_legacy_fixture','available',true);

CREATE FUNCTION pg_temp.expect_error(call text, expected text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 EXECUTE call;
 RAISE EXCEPTION 'Expected % from %',expected,call;
EXCEPTION WHEN OTHERS THEN
 IF SQLERRM <> expected THEN RAISE; END IF;
END $$;

DO $test$
BEGIN
 IF EXISTS (SELECT 1 FROM pg_proc p WHERE p.pronamespace='core10'::regnamespace
   AND p.proname IN ('provision_business','_setup_business_write_v1','_setup_industry_write_v2')
   AND (has_function_privilege('authenticated',p.oid,'execute') OR has_function_privilege('public',p.oid,'execute'))) THEN
  RAISE EXCEPTION 'public setup writer bypass remains';
 END IF;
END
$test$;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims','{"sub":"00009631-0000-4000-8000-000000000001"}',true);
SELECT pg_temp.expect_error(
 $$SELECT core10.build01_setup_v1(9631,'cutover-build','sweets_bakery','Draft','quick',NULL,'cutover-build01','#112233')$$,
 'CONTROL_DISABLED:setup001.provision');
SELECT pg_temp.expect_error(
 $$SELECT core10.setup_business_v1(9631,'cutover-legacy','bootstrap_legacy_fixture','Draft','quick',NULL,'cutover-legacy01','#112233')$$,
 'CONTROL_DISABLED:setup001.provision');
SELECT pg_temp.expect_error(
 $$SELECT core10.setup_industry_draft_v2(9631,'cutover-industry','paint_hardware','Draft','quick','[]','[]','cutover-industry01','#112233')$$,
 'CONTROL_DISABLED:setup001.provision');
DO $test$
BEGIN
 IF core10.control_read_bootstrap_policy_v1(9631)->>'enabled' IS DISTINCT FROM 'false'
 OR core10.read_bootstrap_setup_receipt_v1(9631,'industry-v2:cutover-build01') IS NOT NULL THEN
  RAISE EXCEPTION 'Unexpected initial policy or receipt';
 END IF;
END
$test$;

SELECT core10.control_set_bootstrap_policy_v1(9631,true,NULL,0,'Enable fixture bootstrap','cutover-policy-on');
SELECT core10.build01_setup_v1(9631,'cutover-build','sweets_bakery','Draft','quick',NULL,'cutover-build01','#112233');
SELECT core10.setup_business_v1(9631,'cutover-legacy','bootstrap_legacy_fixture','Draft','quick',NULL,'cutover-legacy01','#112233');
SELECT core10.setup_industry_draft_v2(9631,'cutover-industry','paint_hardware','Draft','quick','[]','[]','cutover-industry01','#112233');

DO $test$
DECLARE receipt jsonb; replay jsonb;
BEGIN
 receipt:=core10.read_bootstrap_setup_receipt_v1(9631,'industry-v2:cutover-build01');
 replay:=core10.build01_setup_v1(9631,'cutover-build','sweets_bakery','Draft','quick',NULL,'cutover-build01','#112233');
 IF receipt->>'business_id' IS DISTINCT FROM replay->>'business_id'
 OR receipt->'decision'->>'version' IS DISTINCT FROM '1'
 OR receipt->'decision'->>'enabled' IS DISTINCT FROM 'true' THEN
  RAISE EXCEPTION 'Scope or replay mismatch: %, %',receipt,replay;
 END IF;
END
$test$;

SELECT core10.control_set_bootstrap_policy_v1(9631,false,NULL,1,'Disable fixture bootstrap','cutover-policy-off');
SELECT pg_temp.expect_error(
 $$SELECT core10.build01_setup_v1(9631,'cutover-build','sweets_bakery','Draft','quick',NULL,'cutover-build01','#112233')$$,
 'CONTROL_DISABLED:setup001.provision');
SELECT pg_temp.expect_error(
 $$SELECT core10.setup_business_v1(9631,'cutover-legacy','bootstrap_legacy_fixture','Draft','quick',NULL,'cutover-legacy01','#112233')$$,
 'CONTROL_DISABLED:setup001.provision');
SELECT pg_temp.expect_error(
 $$SELECT core10.setup_industry_draft_v2(9631,'cutover-industry','paint_hardware','Draft','quick','[]','[]','cutover-industry01','#112233')$$,
 'CONTROL_DISABLED:setup001.provision');

DO $test$
BEGIN
 IF core10.read_bootstrap_setup_receipt_v1(9631,'industry-v2:cutover-industry01')->'decision'->>'version'
    IS DISTINCT FROM '1'
 OR (SELECT count(*) FROM core10.canonical_audit_events_v1 WHERE tenant_id=9631 AND source_domain='bootstrap_setup')<>3 THEN
  RAISE EXCEPTION 'Read-only receipt or one canonical audit per setup failed';
 END IF;
END
$test$;

SELECT set_config('request.jwt.claims','{"sub":"00009632-0000-4000-8000-000000000001"}',true);
SELECT pg_temp.expect_error(
 $$SELECT core10.read_bootstrap_setup_receipt_v1(9631,'industry-v2:cutover-build01')$$,'BOOTSTRAP_RECEIPT_DENIED');
SELECT pg_temp.expect_error(
 $$SELECT core10.control_set_bootstrap_policy_v1(9631,true,NULL,2,'Foreign policy write','foreign-cutover')$$,'BOOTSTRAP_POLICY_DENIED');
SELECT pg_temp.expect_error(
 $$SELECT core10.build01_setup_v1(9631,'cutover-build','sweets_bakery','Draft','quick',NULL,'cutover-build01','#112233')$$,
 'BUILD01_SETUP_DENIED');

SELECT set_config('request.jwt.claims','{"sub":"00009633-0000-4000-8000-000000000001"}',true);
SELECT pg_temp.expect_error(
 $$SELECT core10.build01_setup_v1(9633,'legacy-blocked','sweets_bakery','Draft','quick',NULL,'cutover-existing01','#112233')$$,
 'BOOTSTRAP_POLICY_UNINITIALIZED');
SELECT core10.control_set_bootstrap_policy_v1(9633,true,NULL,0,'Existing owner explicitly enables','existing-opt-in');
SELECT core10.build01_setup_v1(9633,'legacy-verified','sweets_bakery','Draft','quick',NULL,'cutover-existing01','#112233');

RESET ROLE;
ROLLBACK;
\echo NP01_BOOTSTRAP_PROVISIONING_CUTOVER_PASS
