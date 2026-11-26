\set ON_ERROR_STOP on
-- PACK-02 slice 1: real PostgreSQL effects under SYNTHETIC claim fixtures.
-- Not GoTrue/hosted proof. Personas from tests/c10_a018_demo_seed.sql:
--  1111 tenant owner T1 | 7777 tenant owner T2 | 2222 business owner B101
--  3333 manager B101 | 4444 staff site 1001 | 5555 investor B101
--  6666 inactive manager | 8888 staff T2 site 2001 | 9999 unrelated operator

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE sql AS
 $$ SELECT set_config('request.jwt.claim.sub',COALESCE(p::text,''),false) $$;
CREATE FUNCTION pg_temp.expect(p_sql text,p_code text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 EXECUTE p_sql;
 RAISE EXCEPTION 'EXPECTED % BUT SUCCEEDED: %',p_code,p_sql;
EXCEPTION WHEN OTHERS THEN
 IF SQLERRM LIKE 'EXPECTED %' THEN RAISE; END IF;
 IF SQLERRM<>p_code THEN RAISE EXCEPTION 'EXPECTED % GOT % FOR %',p_code,SQLERRM,p_sql; END IF;
END $$;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA pg_temp TO authenticated;
CREATE TEMP TABLE baseline AS SELECT (SELECT count(*) FROM core10.stock_movements) AS movements,
 (SELECT count(*) FROM core10.site_grants) AS grants,(SELECT count(*) FROM core10.business_members) AS members;
GRANT SELECT ON baseline TO authenticated;

SET ROLE authenticated;

-- 1. Setup through the existing canonical engine: Quick and Advanced, replay, conflict, readback.
SELECT pg_temp.as_user('11111111-1111-4111-8111-111111111111');
DO $t$
DECLARE q jsonb; q2 jsonb; a jsonb; a2 jsonb; i jsonb;
BEGIN
 q:=core10.pack02_setup_business_v1(11,'pack02-quick','food_manufacturing','মিষ্টি ঘর ডেমো','quick','[]','pack02-quick-0001','#AA2233');
 IF q->'readback'->>'integrity_ok'<>'true' THEN RAISE EXCEPTION 'quick integrity %',q->'readback'->'checks'; END IF;
 IF jsonb_array_length(q->'readback'->'sites')<>1 OR q->'readback'->'sites'->0->'location_codes'<>'["MAIN"]' THEN RAISE EXCEPTION 'quick site/location'; END IF;
 IF q->'readback'->'brand'->>'brand_hex'<>'#AA2233' OR q->'readback'->'brand'->>'display_name'<>'মিষ্টি ঘর ডেমো' THEN RAISE EXCEPTION 'quick brand persisted wrong'; END IF;
 q2:=core10.pack02_setup_business_v1(11,'pack02-quick','food_manufacturing','মিষ্টি ঘর ডেমো','quick','[]','pack02-quick-0001','#AA2233');
 IF q2<>q THEN RAISE EXCEPTION 'quick replay differs'; END IF;
 a:=core10.pack02_setup_business_v1(11,'pack02-advanced','paint_hardware','Paint Demo','advanced',
  '[{"kind":"showroom","label":"Dhanmondi"},{"kind":"warehouse","label":"Tejgaon"},{"kind":"factory","label":"Gazipur"}]','pack02-adv-0001','#0055AA');
 IF a->'readback'->>'integrity_ok'<>'true' OR jsonb_array_length(a->'readback'->'sites')<>3 THEN RAISE EXCEPTION 'advanced readback %',a; END IF;
 a2:=core10.pack02_setup_business_v1(11,'pack02-advanced','paint_hardware','Paint Demo','advanced',
  '[{"kind":"showroom","label":"Dhanmondi"},{"kind":"warehouse","label":"Tejgaon"},{"kind":"factory","label":"Gazipur"}]','pack02-adv-0001','#0055AA');
 IF a2<>a THEN RAISE EXCEPTION 'advanced replay differs'; END IF;
 IF (SELECT count(*) FROM core10.businesses WHERE slug IN('pack02-quick','pack02-advanced'))<>2 THEN RAISE EXCEPTION 'duplicate business on replay'; END IF;
 IF (SELECT count(*) FROM core10.sites WHERE business_id=(a->'receipt'->>'business_id')::bigint)<>3 THEN RAISE EXCEPTION 'duplicate sites on replay'; END IF;
 IF (SELECT count(*) FROM core10.business_setup_runs_v1 WHERE business_id IN((q->'receipt'->>'business_id')::bigint,(a->'receipt'->>'business_id')::bigint))<>2 THEN RAISE EXCEPTION 'receipt duplicated'; END IF;
 -- Readback is idempotent and matches persisted state.
 i:=core10.pack02_setup_readback_v1((a->'receipt'->>'business_id')::bigint);
 IF i<>a->'readback' THEN RAISE EXCEPTION 'readback not stable'; END IF;
 IF i->'checks'->>'modules_locked'<>'true' OR i->'checks'->>'not_activated'<>'true' OR i->>'production_certified'<>'false' THEN RAISE EXCEPTION 'setup activated something'; END IF;
END $t$;
-- Same request key with a changed payload is refused and leaves no orphan.
SELECT pg_temp.expect($$SELECT core10.pack02_setup_business_v1(11,'pack02-quick','food_manufacturing','Changed','quick','[]','pack02-quick-0001','#AA2233')$$,'idempotency_key_payload_conflict');
SELECT pg_temp.expect($$SELECT core10.pack02_setup_business_v1(11,'pack02-dup','paint_hardware','Dup','advanced','[{"kind":"showroom","label":"Main"},{"kind":"showroom","label":" main "}]','pack02-dup-0001','#112233')$$,'duplicate_industry_site');
SELECT pg_temp.expect($$SELECT core10.pack02_setup_business_v1(11,'pack02-qs','paint_hardware','QS','quick','[{"kind":"showroom","label":"X"}]','pack02-qs-0001','#112233')$$,'quick_custom_sites_denied');
DO $t$ BEGIN
 IF EXISTS(SELECT 1 FROM core10.businesses WHERE slug IN('pack02-dup','pack02-qs')) THEN RAISE EXCEPTION 'orphan business after refused setup'; END IF;
END $t$;
-- Cross-tenant setup refused: T1 owner cannot use T2 legal entity.
SELECT pg_temp.expect($$SELECT core10.pack02_setup_business_v1(21,'pack02-x','paint_hardware','X','quick','[]','pack02-x-00001','#112233')$$,'BUILD01_SETUP_DENIED');

-- 2. Setup authority negatives.
SELECT pg_temp.as_user('22222222-2222-4222-8222-222222222222');
SELECT pg_temp.expect($$SELECT core10.pack02_setup_business_v1(11,'pack02-bo','paint_hardware','BO','quick','[]','pack02-bo-00001','#112233')$$,'BUILD01_SETUP_DENIED');
SELECT pg_temp.as_user('44444444-4444-4444-8444-444444444444');
SELECT pg_temp.expect($$SELECT core10.pack02_setup_business_v1(11,'pack02-st','paint_hardware','ST','quick','[]','pack02-st-00001','#112233')$$,'BUILD01_SETUP_DENIED');
SELECT pg_temp.expect($$SELECT core10.pack02_setup_readback_v1(101)$$,'PACK02_READBACK_DENIED');
SELECT pg_temp.as_user(NULL);
SELECT pg_temp.expect($$SELECT core10.pack02_setup_readback_v1(101)$$,'PACK02_READBACK_DENIED');
SELECT pg_temp.expect($$SELECT core10.pack02_workspace_v1('universal_owner')$$,'PACK02_SIGNED_SESSION_REQUIRED');

-- 3. Universal Owner workspace: only own tenants, umbrella visible.
SELECT pg_temp.as_user('11111111-1111-4111-8111-111111111111');
DO $t$ DECLARE w jsonb; BEGIN
 w:=core10.pack02_workspace_v1('universal_owner');
 IF w->'umbrella'->>'visible'<>'true' OR jsonb_array_length(w->'tenants')<>1 THEN RAISE EXCEPTION 'universal tenants %',w->'tenants'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(w->'businesses') b WHERE (b->>'tenant_id')::bigint<>1) THEN RAISE EXCEPTION 'foreign tenant business leaked'; END IF;
 IF jsonb_array_length(w->'businesses')<>4 THEN RAISE EXCEPTION 'universal business count %',jsonb_array_length(w->'businesses'); END IF;
 IF w::text LIKE '%customer-business%' THEN RAISE EXCEPTION 'independent tenant leaked'; END IF;
 IF NOT (w->'nav') ? 'owner.setup' THEN RAISE EXCEPTION 'owner nav'; END IF;
 PERFORM pg_temp.expect($$SELECT core10.pack02_workspace_v1('universal_owner',101)$$,'PACK02_MODE_INVALID');
 PERFORM pg_temp.expect($$SELECT core10.pack02_workspace_v1('root')$$,'PACK02_MODE_INVALID');
 PERFORM pg_temp.expect($$SELECT core10.pack02_workspace_v1(NULL)$$,'PACK02_MODE_INVALID');
 -- Tenant owner can open any own business as Business Owner, with umbrella link.
 w:=core10.pack02_workspace_v1('business_owner',102);
 IF w->'umbrella'->>'visible'<>'true' OR jsonb_array_length(w->'sites')<>1 THEN RAISE EXCEPTION 'tenant owner business view'; END IF;
 PERFORM pg_temp.expect($$SELECT core10.pack02_workspace_v1('business_owner',201)$$,'PACK02_WORKSPACE_DENIED');
 PERFORM pg_temp.expect($$SELECT core10.pack02_workspace_v1('business_owner',999999)$$,'PACK02_WORKSPACE_DENIED');
END $t$;
SELECT pg_temp.as_user('77777777-7777-4777-8777-777777777777');
DO $t$ DECLARE w jsonb; BEGIN
 w:=core10.pack02_workspace_v1('universal_owner');
 IF jsonb_array_length(w->'businesses')<>1 OR (w->'businesses'->0->>'id')::bigint<>201 THEN RAISE EXCEPTION 'T2 owner sees %',w->'businesses'; END IF;
 PERFORM pg_temp.expect($$SELECT core10.pack02_workspace_v1('business_owner',101)$$,'PACK02_WORKSPACE_DENIED');
 PERFORM pg_temp.expect($$SELECT core10.pack02_workspace_v1('staff',101)$$,'PACK02_WORKSPACE_DENIED');
END $t$;

-- 4. Business Owner (not tenant owner): own business only, umbrella hidden.
SELECT pg_temp.as_user('22222222-2222-4222-8222-222222222222');
DO $t$ DECLARE w jsonb; BEGIN
 PERFORM pg_temp.expect($$SELECT core10.pack02_workspace_v1('universal_owner')$$,'PACK02_WORKSPACE_DENIED');
 w:=core10.pack02_workspace_v1('business_owner',101);
 IF w->'umbrella'->>'visible'<>'false' THEN RAISE EXCEPTION 'business owner sees umbrella'; END IF;
 IF jsonb_array_length(w->'sites')<>2 THEN RAISE EXCEPTION 'business owner sites'; END IF;
 IF w::text LIKE '%demo-second-business%' OR w::text LIKE '%CORE 10%' OR w ? 'tenants' THEN RAISE EXCEPTION 'business owner leak'; END IF;
 PERFORM pg_temp.expect($$SELECT core10.pack02_workspace_v1('business_owner',102)$$,'PACK02_WORKSPACE_DENIED');
 PERFORM pg_temp.expect($$SELECT core10.pack02_owner_report_v1()$$,'PACK02_REPORT_DENIED');
 IF (core10.pack02_business_report_v1(101)->>'scope')<>'business' THEN RAISE EXCEPTION 'bo report scope'; END IF;
 PERFORM pg_temp.expect($$SELECT core10.pack02_business_report_v1(102)$$,'PACK02_REPORT_DENIED');
 IF (core10.pack02_setup_readback_v1(101)->>'integrity_ok')<>'false' THEN RAISE EXCEPTION 'seed business has no setup receipt; must not claim integrity'; END IF;
END $t$;

-- 5. Manager: business visibility but no owner workspace.
SELECT pg_temp.as_user('33333333-3333-4333-8333-333333333333');
DO $t$ DECLARE w jsonb; BEGIN
 PERFORM pg_temp.expect($$SELECT core10.pack02_workspace_v1('business_owner',101)$$,'PACK02_WORKSPACE_DENIED');
 PERFORM pg_temp.expect($$SELECT core10.pack02_setup_readback_v1(101)$$,'PACK02_READBACK_DENIED');
 w:=core10.pack02_workspace_v1('staff',101);
 IF jsonb_array_length(w->'sites')<>2 OR w->'umbrella'->>'visible'<>'false' THEN RAISE EXCEPTION 'manager staff view'; END IF;
END $t$;

-- 6. Staff: only granted site, own brand, no umbrella/sister/tenant data.
SELECT pg_temp.as_user('44444444-4444-4444-8444-444444444444');
DO $t$ DECLARE w jsonb; r jsonb; BEGIN
 PERFORM pg_temp.expect($$SELECT core10.pack02_workspace_v1('universal_owner')$$,'PACK02_WORKSPACE_DENIED');
 PERFORM pg_temp.expect($$SELECT core10.pack02_workspace_v1('business_owner',101)$$,'PACK02_WORKSPACE_DENIED');
 w:=core10.pack02_workspace_v1('staff',101);
 IF jsonb_array_length(w->'sites')<>1 OR (w->'sites'->0->>'id')::bigint<>1001 THEN RAISE EXCEPTION 'staff sites %',w->'sites'; END IF;
 IF w->'nav'<>'["staff.home","stock.view","staff.reports","stock.post"]'::jsonb THEN RAISE EXCEPTION 'staff nav %',w->'nav'; END IF;
 IF w ? 'tenants' OR w ? 'actor_uid' OR w->'business' ? 'tenant_id' OR w::text LIKE '%CORE 10%'
  OR w::text LIKE '%demo-second-business%' OR w::text LIKE '%Owner Legal%' OR w::text LIKE '%A2%' THEN RAISE EXCEPTION 'staff leak %',w; END IF;
 PERFORM pg_temp.expect($$SELECT core10.pack02_workspace_v1('staff',102)$$,'PACK02_WORKSPACE_DENIED');
 PERFORM pg_temp.expect($$SELECT core10.pack02_workspace_v1('staff',201)$$,'PACK02_WORKSPACE_DENIED');
 r:=core10.pack02_business_report_v1(101);
 IF r->>'scope'<>'granted_sites' OR jsonb_array_length(r->'sites')<>1 OR (r->'sites'->0->>'site_id')::bigint<>1001 THEN RAISE EXCEPTION 'staff report scope %',r; END IF;
 PERFORM pg_temp.expect($$SELECT core10.pack02_business_report_v1(201)$$,'PACK02_REPORT_DENIED');
 PERFORM pg_temp.expect($$SELECT core10.pack02_owner_report_v1()$$,'PACK02_REPORT_DENIED');
END $t$;

-- 7. Canonical explicit deny (PACK-01/Build01) removes stock.post from staff nav; expiry closes workspace.
SELECT pg_temp.as_user('11111111-1111-4111-8111-111111111111');
SELECT core10.build01_set_access_v1(101,'44444444-4444-4444-8444-444444444444','site_grant.grant',NULL,1001,
 ARRAY['stock.read','stock.post'],ARRAY['stock.post'],NULL,'pack02-deny-post-0001',NULL) IS NOT NULL;
SELECT pg_temp.as_user('44444444-4444-4444-8444-444444444444');
DO $t$ BEGIN
 IF core10.pack02_workspace_v1('staff',101)->'nav'<>'["staff.home","stock.view","staff.reports"]'::jsonb THEN RAISE EXCEPTION 'deny not reflected in nav'; END IF;
END $t$;
RESET ROLE;
UPDATE core10.site_grants SET valid_until=now()-interval '1 second' WHERE site_id=1001 AND user_id='44444444-4444-4444-8444-444444444444';
SET ROLE authenticated;
SELECT pg_temp.expect($$SELECT core10.pack02_workspace_v1('staff',101)$$,'PACK02_WORKSPACE_DENIED');
SELECT pg_temp.expect($$SELECT core10.pack02_business_report_v1(101)$$,'PACK02_REPORT_DENIED');
-- Revoked staff (owner revokes) is denied too.
SELECT pg_temp.as_user('11111111-1111-4111-8111-111111111111');
SELECT core10.build01_set_access_v1(101,'44444444-4444-4444-8444-444444444444','site_grant.revoke',NULL,1001,
 NULL,NULL,NULL,'pack02-revoke-0001',NULL) IS NOT NULL;
SELECT pg_temp.as_user('44444444-4444-4444-8444-444444444444');
SELECT pg_temp.expect($$SELECT core10.pack02_workspace_v1('staff',101)$$,'PACK02_WORKSPACE_DENIED');

-- 8. Investor, inactive manager, other-tenant staff, unrelated operator.
SELECT pg_temp.as_user('55555555-5555-4555-8555-555555555555');
SELECT pg_temp.expect($$SELECT core10.pack02_workspace_v1('staff',101)$$,'PACK02_WORKSPACE_DENIED');
SELECT pg_temp.as_user('66666666-6666-4666-8666-666666666666');
SELECT pg_temp.expect($$SELECT core10.pack02_workspace_v1('staff',101)$$,'PACK02_WORKSPACE_DENIED');
SELECT pg_temp.as_user('88888888-8888-4888-8888-888888888888');
DO $t$ BEGIN
 IF jsonb_array_length(core10.pack02_workspace_v1('staff',201)->'sites')<>1 THEN RAISE EXCEPTION 'T2 staff own site'; END IF;
 PERFORM pg_temp.expect($$SELECT core10.pack02_workspace_v1('staff',101)$$,'PACK02_WORKSPACE_DENIED');
END $t$;
SELECT pg_temp.as_user('99999999-9999-4999-8999-999999999999');
SELECT pg_temp.expect($$SELECT core10.pack02_workspace_v1('universal_owner')$$,'PACK02_WORKSPACE_DENIED');
SELECT pg_temp.expect($$SELECT core10.pack02_workspace_v1('staff',201)$$,'PACK02_WORKSPACE_DENIED');
SELECT pg_temp.expect($$SELECT core10.pack02_owner_report_v1()$$,'PACK02_REPORT_DENIED');

-- 9. Owner-wide report is per-tenant scoped.
SELECT pg_temp.as_user('11111111-1111-4111-8111-111111111111');
DO $t$ DECLARE r jsonb; BEGIN
 r:=core10.pack02_owner_report_v1();
 IF jsonb_array_length(r->'businesses')<>4 OR EXISTS(SELECT 1 FROM jsonb_array_elements(r->'businesses') x WHERE (x->>'tenant_id')::bigint<>1)
 THEN RAISE EXCEPTION 'owner report scope %',r; END IF;
END $t$;

-- 10. Direct helper / table access stays closed; no operational writes happened.
SELECT pg_temp.expect($$SELECT core10.pack02_brand_v1(101)$$,'permission denied for function pack02_brand_v1');
RESET ROLE;
SET ROLE anon;
SELECT pg_temp.expect($$SELECT core10.pack02_workspace_v1('universal_owner')$$,'permission denied for schema core10');
RESET ROLE;
DO $t$ BEGIN
 IF (SELECT count(*) FROM core10.stock_movements)<>(SELECT movements FROM baseline) THEN RAISE EXCEPTION 'stock movement written'; END IF;
 IF (SELECT count(*) FROM core10.business_members)<>(SELECT members FROM baseline) THEN RAISE EXCEPTION 'membership written by PACK-02'; END IF;
END $t$;
SELECT 'PASS PACK-02 workspace-e2e' AS result;
