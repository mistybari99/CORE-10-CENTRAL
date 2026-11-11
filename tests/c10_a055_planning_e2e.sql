-- C10-A055 planning end-to-end test (disposable PostgreSQL, signed-claim SIMULATION only). Synthetic data only.
-- Run after: AM_FILES="core planning lockdown" tests/c10_a055_load.sh <db>  (registry/workorders files optional; assets are seeded here by superuser).
\set ON_ERROR_STOP on
CREATE SCHEMA c10_test;
GRANT USAGE ON SCHEMA c10_test TO authenticated,anon;
CREATE TABLE c10_test.kv(k text PRIMARY KEY,v text);
CREATE FUNCTION c10_test.u(p text) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT (CASE p
 WHEN 'owner' THEN '11111111-1111-4111-8111-111111111111' WHEN 'bo101' THEN '22222222-2222-4222-8222-222222222222'
 WHEN 'mgr101' THEN '33333333-3333-4333-8333-333333333333' WHEN 'e4' THEN '44444444-4444-4444-8444-444444444444'
 WHEN 'investor' THEN '55555555-5555-4555-8555-555555555555' WHEN 'revoked' THEN '66666666-6666-4666-8666-666666666666'
 WHEN 'owner2' THEN '77777777-7777-4777-8777-777777777777' WHEN 'staff2' THEN '88888888-8888-4888-8888-888888888888'
 WHEN 'operator' THEN '99999999-9999-4999-8999-999999999999' WHEN 'sup' THEN 'd1111111-1111-4111-8111-111111111111'
 WHEN 'sup1001' THEN 'd2222222-2222-4222-8222-222222222222' WHEN 'tech1001' THEN 'd3333333-3333-4333-8333-333333333333'
 WHEN 'tech1002' THEN 'd4444444-4444-4444-8444-444444444444' WHEN 'reporter' THEN 'd5555555-5555-4555-8555-555555555555'
 WHEN 'auditor' THEN 'd6666666-6666-4666-8666-666666666666' WHEN 'revtech' THEN 'd7777777-7777-4777-8777-777777777777'
 WHEN 'sup2' THEN 'd8888888-8888-4888-8888-888888888888' WHEN 'bo102' THEN 'e1111111-1111-4111-8111-111111111111' END)::uuid $$;
CREATE FUNCTION c10_test.as_user(p text) RETURNS void LANGUAGE sql AS $$ SELECT set_config('request.jwt.claim.sub',c10_test.u(p)::text,true); SELECT 1 $$;
CREATE FUNCTION c10_test.eq(a text,b text,msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF a IS DISTINCT FROM b THEN RAISE EXCEPTION 'ASSERT % : got [%] want [%]',msg,a,b; END IF; END$$;
CREATE FUNCTION c10_test.denied(p_sql text,p_expect text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 BEGIN EXECUTE p_sql; EXCEPTION WHEN OTHERS THEN
  IF SQLERRM NOT LIKE p_expect||'%' THEN RAISE EXCEPTION 'WRONG_ERROR [%] for %: want %',SQLERRM,p_sql,p_expect; END IF; RETURN; END;
 RAISE EXCEPTION 'EXPECTED_DENIAL_DID_NOT_HAPPEN: %',p_sql;
END$$;
-- superuser-powered probes usable from inside role-switched blocks
CREATE FUNCTION c10_test.q(p_sql text) RETURNS text LANGUAGE plpgsql SECURITY DEFINER AS $$ DECLARE v text; BEGIN EXECUTE p_sql INTO v; RETURN v; END$$;
CREATE FUNCTION c10_test.x(p_sql text) RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$ BEGIN EXECUTE p_sql; END$$;
CREATE FUNCTION c10_test.put(p_k text,p_v text) RETURNS void LANGUAGE sql SECURITY DEFINER AS $$ INSERT INTO c10_test.kv VALUES(p_k,p_v) ON CONFLICT(k) DO UPDATE SET v=excluded.v $$;
CREATE FUNCTION c10_test.g(p_k text) RETURNS text LANGUAGE sql SECURITY DEFINER AS $$ SELECT v FROM c10_test.kv WHERE k=p_k $$;
CREATE FUNCTION c10_test.gi(p_k text) RETURNS bigint LANGUAGE sql SECURITY DEFINER AS $$ SELECT v::bigint FROM c10_test.kv WHERE k=p_k $$;
CREATE FUNCTION c10_test.today() RETURNS date LANGUAGE sql SECURITY DEFINER AS $$ SELECT c10_demo.ami_today(101) $$;
CREATE FUNCTION c10_test.d(n int) RETURNS text LANGUAGE sql SECURITY DEFINER AS $$ SELECT (c10_demo.ami_today(101)+n)::text $$;
CREATE FUNCTION c10_test.aid(p_no text) RETURNS bigint LANGUAGE sql SECURITY DEFINER AS $$ SELECT id FROM c10_demo.am_assets WHERE asset_no=p_no $$;
CREATE FUNCTION c10_test.cid(p_biz bigint,p_code text) RETURNS bigint LANGUAGE sql SECURITY DEFINER AS $$ SELECT id FROM c10_demo.am_categories WHERE business_id=p_biz AND code=p_code $$;
CREATE FUNCTION c10_test.tgt(p_plan text,p_asset text) RETURNS bigint LANGUAGE sql SECURITY DEFINER AS $$
 SELECT t.id FROM c10_demo.am_plan_targets t JOIN c10_demo.am_assets a ON a.id=t.asset_id WHERE t.plan_id=c10_test.gi(p_plan) AND a.asset_no=p_asset $$;
CREATE FUNCTION c10_test.item(j jsonb,p_plan text,p_asset text) RETURNS jsonb LANGUAGE sql AS $$
 SELECT i FROM jsonb_array_elements(j->'items') i WHERE i->>'plan_name'=p_plan AND i->>'asset_no'=p_asset $$;
CREATE FUNCTION c10_test.close_wo(p_id bigint) RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN SET LOCAL session_replication_role=replica; UPDATE c10_demo.am_work_orders SET status='CLOSED' WHERE id=p_id; SET LOCAL session_replication_role=origin; END$$;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA c10_test TO authenticated,anon;

-- ===== S0 fixtures (superuser): businesses bootstrapped, assets / meters seeded WITHOUT registry RPCs =====
SELECT c10_demo.ami_ensure_business(101); SELECT c10_demo.ami_ensure_business(102); SELECT c10_demo.ami_ensure_business(201);
INSERT INTO c10_demo.am_categories(tenant_id,business_id,code,name,parent_id) VALUES
 (1,101,'PROD-OVEN','Ovens (child of production equipment)',(SELECT id FROM c10_demo.am_categories WHERE business_id=101 AND code='PROD-EQ'));
INSERT INTO c10_demo.am_assets(tenant_id,business_id,asset_no,name,category_id,status,site_id,created_by)
SELECT 1,101,v.no,v.nm,(SELECT id FROM c10_demo.am_categories WHERE business_id=101 AND code=v.cat),v.st,v.site,'11111111-1111-4111-8111-111111111111'
FROM (VALUES('T-OVEN-1','Oven 1','PROD-EQ','active',1001),('T-MIXER-2','Paint mixer 2','PROD-EQ','active',1002),('T-CHILL-3','Chiller 3','COLD','active',1001),
 ('T-CONV-4','Conveyor 4','PROD-EQ','active',1005),('T-OLD-5','Old press 5','PROD-EQ','retired',1001),('T-OVEN-7','Oven 7','PROD-OVEN','active',1001),
 ('T-GEN-8','Generator 8','POWER','active',1002)) v(no,nm,cat,st,site);
INSERT INTO c10_demo.am_assets(tenant_id,business_id,asset_no,name,category_id,site_id,created_by)
VALUES(1,102,'T-X102','Other business asset',(SELECT id FROM c10_demo.am_categories WHERE business_id=102 AND code='PROD-EQ'),1003,'11111111-1111-4111-8111-111111111111'),
 (2,201,'T-X201','Other tenant asset',(SELECT id FROM c10_demo.am_categories WHERE business_id=201 AND code='PROD-EQ'),2001,'77777777-7777-4777-8777-777777777777');
INSERT INTO c10_demo.am_meters(tenant_id,business_id,asset_id,code,unit,current_reading,last_reading_at)
VALUES(1,101,c10_test.aid('T-OVEN-1'),'HRS','hours',100,now());
-- site 1005 (project) auto-submits generated work orders (policy override, not code)
INSERT INTO c10_demo.am_policy(business_id,tenant_id,scope_type,scope_id,key,value,updated_by)
VALUES(101,1,'site',1005,'schedule.auto_submit_generated','true','22222222-2222-4222-8222-222222222222');

-- ===== T0 pure schedule arithmetic =====
DO $$ BEGIN
 PERFORM c10_test.eq(c10_demo.ami_next_due('2024-01-31','monthly',1)::text,'2024-02-29','month-end clamp leap');
 PERFORM c10_test.eq(c10_demo.ami_next_due('2025-01-31','monthly',1)::text,'2025-02-28','month-end clamp');
 PERFORM c10_test.eq(c10_demo.ami_next_due('2025-03-31','monthly',1)::text,'2025-04-30','month-end clamp 30');
 PERFORM c10_test.eq(c10_demo.ami_next_due('2024-02-29','yearly',1)::text,'2025-02-28','feb29 yearly');
 PERFORM c10_test.eq(c10_demo.ami_next_due('2024-02-29','yearly',4)::text,'2028-02-29','feb29 yearly x4 stays leap');
 PERFORM c10_test.eq(c10_demo.ami_next_due('2025-12-30','monthly',2)::text,'2026-02-28','monthly x2 across year');
 PERFORM c10_test.eq(c10_demo.ami_next_due('2025-01-01','daily',10)::text,'2025-01-11','daily');
 PERFORM c10_test.eq(c10_demo.ami_next_due('2025-01-01','weekly',2)::text,'2025-01-15','weekly');
 PERFORM c10_test.eq(c10_demo.ami_next_due('2025-01-01','usage',1)::text,NULL,'usage has no date');
 PERFORM c10_test.eq(c10_demo.ami_next_due(NULL,'daily',1)::text,NULL,'null in');
 PERFORM c10_test.eq(c10_demo.ami_next_due('2025-01-01','daily',0)::text,NULL,'n<1');
 PERFORM c10_test.eq((SELECT provolatile::text FROM pg_proc WHERE proname='ami_next_due'),'i','immutable');
END $$;

-- ===== T1 authority: outsiders / revoked / cross-tenant / cross-business / stock-only / anon =====
BEGIN; SET LOCAL ROLE authenticated;
DO $$ DECLARE who text; BEGIN
 FOREACH who IN ARRAY ARRAY['e4','investor','revoked','owner2','staff2','operator','bo102','mgr101','revtech','sup2'] LOOP
  PERFORM c10_test.as_user(who);
  PERFORM c10_test.denied($s$SELECT c10_demo.am_list_plans_v1(101)$s$,'am_denied');
  PERFORM c10_test.denied($s$SELECT c10_demo.am_list_checklists_v1(101,false)$s$,'am_denied');
  PERFORM c10_test.denied($s$SELECT c10_demo.am_due_suggestions_v1(101,NULL,NULL)$s$,'am_denied');
  PERFORM c10_test.denied($s$SELECT c10_demo.am_calendar_v1(101,current_date,current_date+5,NULL)$s$,'am_denied');
  PERFORM c10_test.denied($s$SELECT c10_demo.am_save_checklist_template_v1(101,'neg-key-0001','CL-X','X name',NULL,'[{"text":"a b"}]'::jsonb,NULL)$s$,'am_denied');
  PERFORM c10_test.denied($s$SELECT c10_demo.am_save_plan_v1(101,'neg-key-0002',NULL,NULL,'{"name":"x"}'::jsonb,NULL)$s$,'am_denied');
  PERFORM c10_test.denied($s$SELECT c10_demo.am_generate_work_orders_v1(101,'neg-key-0003',NULL,NULL,NULL)$s$,'am_denied');
  PERFORM c10_test.denied($s$SELECT c10_demo.am_defer_target_v1(101,'neg-key-0004',1,current_date+5,'no reason')$s$,'am_denied');
 END LOOP;
 -- no identity at all
 PERFORM set_config('request.jwt.claim.sub','',true);
 PERFORM c10_test.denied($s$SELECT c10_demo.am_list_plans_v1(101)$s$,'am_denied');
 PERFORM c10_test.denied($s$SELECT c10_demo.am_generate_work_orders_v1(101,'neg-key-0005',NULL,NULL,NULL)$s$,'am_denied');
 PERFORM c10_test.as_user('sup'); PERFORM c10_test.denied($s$SELECT c10_demo.am_list_plans_v1(NULL)$s$,'am_denied');
 PERFORM c10_test.denied($s$SELECT c10_demo.am_list_plans_v1(999999)$s$,'am_denied');
 PERFORM c10_test.denied($s$SELECT c10_demo.am_list_plans_v1(201)$s$,'am_denied');
 PERFORM c10_test.denied($s$SELECT c10_demo.am_list_plans_v1(102)$s$,'am_denied');   -- grant is on business 101 only
 PERFORM c10_test.denied($s$SELECT c10_demo.ami_next_due('2025-01-01','daily',1)$s$,'permission denied');
 PERFORM c10_test.denied($s$SELECT c10_demo.ami_create_wo(NULL,'x',1,'corrective','t t t',NULL,NULL,NULL,NULL,NULL,NULL,NULL)$s$,'permission denied');
 PERFORM c10_test.denied($s$SELECT count(*) FROM c10_demo.am_plans$s$,'permission denied');
 PERFORM c10_test.denied($s$SELECT count(*) FROM c10_demo.am_plan_targets$s$,'permission denied');
END $$; COMMIT;
BEGIN; SET LOCAL ROLE anon;
DO $$ BEGIN
 PERFORM c10_test.denied($s$SELECT c10_demo.am_list_plans_v1(101)$s$,'permission denied');
 PERFORM c10_test.denied($s$SELECT c10_demo.am_generate_work_orders_v1(101,'neg-key-0006',NULL,NULL,NULL)$s$,'permission denied');
END $$; COMMIT;

-- ===== T2 members without the capability: technician / reporter / auditor can read but never write or generate =====
BEGIN; SET LOCAL ROLE authenticated;
DO $$ DECLARE who text; BEGIN
 FOREACH who IN ARRAY ARRAY['tech1001','tech1002','reporter','auditor'] LOOP
  PERFORM c10_test.as_user(who);
  PERFORM c10_test.eq(jsonb_typeof(c10_demo.am_list_plans_v1(101)->'items'),'array','read plans '||who);
  PERFORM c10_test.eq(jsonb_typeof(c10_demo.am_list_checklists_v1(101,false)->'items'),'array','read checklists '||who);
  PERFORM c10_test.eq(jsonb_typeof(c10_demo.am_due_suggestions_v1(101,NULL,NULL)->'items'),'array','read suggestions '||who);
  PERFORM c10_test.eq(jsonb_typeof(c10_demo.am_calendar_v1(101,current_date-3,current_date+30,NULL)->'days'),'array','read calendar '||who);
  PERFORM c10_test.denied($s$SELECT c10_demo.am_save_checklist_template_v1(101,'cap-key-0001','CL-X','X name',NULL,'[{"text":"ab cd"}]'::jsonb,NULL)$s$,'am_not_permitted');
  PERFORM c10_test.denied($s$SELECT c10_demo.am_save_plan_v1(101,'cap-key-0002',NULL,NULL,'{"name":"x"}'::jsonb,NULL)$s$,'am_not_permitted');
  PERFORM c10_test.denied($s$SELECT c10_demo.am_generate_work_orders_v1(101,'cap-key-0003',NULL,NULL,NULL)$s$,'am_not_permitted');
 END LOOP;
 -- site-limited supervisor: no business-wide template authority, no plans outside site 1001
 PERFORM c10_test.as_user('sup1001');
 PERFORM c10_test.denied($s$SELECT c10_demo.am_save_checklist_template_v1(101,'cap-key-0004','CL-X','X name',NULL,'[{"text":"ab cd"}]'::jsonb,NULL)$s$,'am_not_permitted');
 PERFORM c10_test.denied(format($s$SELECT c10_demo.am_save_plan_v1(101,'cap-key-0005',NULL,NULL,'{"name":"Plan X","plan_type":"preventive","category_id":%s,"frequency_kind":"weekly","start_on":"2030-01-01"}'::jsonb,NULL)$s$,c10_test.cid(101,'PROD-EQ')),'am_not_permitted');
 PERFORM c10_test.denied(format($s$SELECT c10_demo.am_save_plan_v1(101,'cap-key-0006',NULL,NULL,'{"name":"Plan X","plan_type":"preventive","asset_id":%s,"frequency_kind":"weekly","start_on":"2030-01-01"}'::jsonb,NULL)$s$,c10_test.aid('T-MIXER-2')),'am_not_permitted');
END $$; COMMIT;
