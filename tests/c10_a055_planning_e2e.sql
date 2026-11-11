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

-- ===== T3 checklist templates: versioned, validated, idempotent =====
BEGIN; SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb; r2 jsonb; l jsonb; BEGIN
 PERFORM c10_test.as_user('sup');
 r:=c10_demo.am_save_checklist_template_v1(101,'cl-save-0001','CL-PM','Monthly PM',NULL,
  '[{"text":"Isolate power and lock out","kind":"safety"},{"text":"Check belt tension"},{"text":"Motor temperature","kind":"measure","min_value":20,"max_value":75,"unit":"C","required":false}]'::jsonb,NULL);
 PERFORM c10_test.eq(r->>'status','applied','cl v1 applied'); PERFORM c10_test.eq(r->>'version','1','cl v1');
 -- replay returns the ORIGINAL receipt, creates nothing
 r2:=c10_demo.am_save_checklist_template_v1(101,'cl-save-0001','CL-PM','Monthly PM',NULL,
  '[{"text":"Isolate power and lock out","kind":"safety"},{"text":"Check belt tension"},{"text":"Motor temperature","kind":"measure","min_value":20,"max_value":75,"unit":"C","required":false}]'::jsonb,NULL);
 PERFORM c10_test.eq(r2::text,r::text,'cl replay identical');
 PERFORM c10_test.eq(c10_test.q($s$SELECT count(*) FROM c10_demo.am_checklist_templates WHERE code='CL-PM'$s$),'1','replay created no row');
 PERFORM c10_test.denied($s$SELECT c10_demo.am_save_checklist_template_v1(101,'cl-save-0001','CL-PM','Different name',NULL,'[{"text":"ab cd"}]'::jsonb,NULL)$s$,'am_idempotency_conflict');
 PERFORM c10_test.as_user('bo101');
 PERFORM c10_test.denied($s$SELECT c10_demo.am_save_checklist_template_v1(101,'cl-save-0001','CL-PM','Monthly PM',NULL,'[{"text":"ab cd"}]'::jsonb,NULL)$s$,'am_idempotency_conflict'); -- other actor, same key
 PERFORM c10_test.as_user('sup');
 PERFORM c10_test.denied($s$SELECT c10_demo.am_save_checklist_template_v1(101,'bad key!','CL-PM','Monthly PM',NULL,'[{"text":"ab cd"}]'::jsonb,NULL)$s$,'am_invalid_request_key');
 -- version 2 needs a reason; previous version superseded but kept
 PERFORM c10_test.denied($s$SELECT c10_demo.am_save_checklist_template_v1(101,'cl-save-0002','CL-PM','Monthly PM',NULL,'[{"text":"ab cd"}]'::jsonb,NULL)$s$,'am_invalid_input');
 r:=c10_demo.am_save_checklist_template_v1(101,'cl-save-0003','CL-PM','Monthly PM',NULL,
  '[{"text":"Isolate power and lock out","kind":"safety"},{"text":"Check belt tension and alignment"},{"text":"Motor temperature","kind":"measure","min_value":20,"max_value":80,"unit":"C","required":false}]'::jsonb,'tighten belt step');
 PERFORM c10_test.eq(r->>'version','2','cl v2'); PERFORM c10_test.eq(r->>'previous_version','1','prev v1');
 PERFORM c10_test.eq(c10_test.q($s$SELECT active::text||'/'||(superseded_at IS NOT NULL)::text FROM c10_demo.am_checklist_templates WHERE code='CL-PM' AND version=1$s$),'false/true','v1 superseded');
 PERFORM c10_test.eq(c10_test.q($s$SELECT count(*) FROM c10_demo.am_checklist_items i JOIN c10_demo.am_checklist_templates t ON t.id=i.template_id WHERE t.code='CL-PM' AND t.version=1$s$),'3','v1 items kept (immutable history)');
 l:=c10_demo.am_list_checklists_v1(101,false);
 PERFORM c10_test.eq(l->>'total','1','only active listed'); PERFORM c10_test.eq(l->'items'->0->>'version','2','active is v2');
 PERFORM c10_test.eq(jsonb_array_length(l->'items'->0->'items')::text,'3','items listed');
 l:=c10_demo.am_list_checklists_v1(101,true);
 PERFORM c10_test.eq(l->>'total','2','inactive listed on request'); PERFORM c10_test.eq(l->'items'->0->>'version','2','newest first');
 PERFORM c10_test.eq(c10_test.q($s$SELECT count(*) FROM c10_demo.am_audit WHERE entity='checklist_template' AND entity_id='CL-PM'$s$),'2','checklist audited');
 -- validation
 PERFORM c10_test.denied($s$SELECT c10_demo.am_save_checklist_template_v1(101,'cl-val-0001','cl-pm','n n',NULL,'[{"text":"ab cd"}]'::jsonb,NULL)$s$,'am_invalid_input');   -- code format
 PERFORM c10_test.denied($s$SELECT c10_demo.am_save_checklist_template_v1(101,'cl-val-0002','CL-V','n',NULL,'[{"text":"ab cd"}]'::jsonb,NULL)$s$,'am_invalid_input');     -- name too short
 PERFORM c10_test.denied($s$SELECT c10_demo.am_save_checklist_template_v1(101,'cl-val-0003','CL-V','nn',NULL,'[]'::jsonb,NULL)$s$,'am_invalid_input');                       -- no items
 PERFORM c10_test.denied($s$SELECT c10_demo.am_save_checklist_template_v1(101,'cl-val-0004','CL-V','nn',NULL,'{"text":"ab cd"}'::jsonb,NULL)$s$,'am_invalid_input');       -- not an array
 PERFORM c10_test.denied($s$SELECT c10_demo.am_save_checklist_template_v1(101,'cl-val-0005','CL-V','nn',NULL,'["ab cd"]'::jsonb,NULL)$s$,'am_invalid_input');           -- item not object
 PERFORM c10_test.denied($s$SELECT c10_demo.am_save_checklist_template_v1(101,'cl-val-0006','CL-V','nn',NULL,'[{"text":"ab cd","kind":"bogus"}]'::jsonb,NULL)$s$,'am_invalid_input');
 PERFORM c10_test.denied($s$SELECT c10_demo.am_save_checklist_template_v1(101,'cl-val-0007','CL-V','nn',NULL,'[{"text":"ab cd","kind":"measure","min_value":9,"max_value":3}]'::jsonb,NULL)$s$,'am_invalid_input');
 PERFORM c10_test.denied($s$SELECT c10_demo.am_save_checklist_template_v1(101,'cl-val-0008','CL-V','nn',NULL,'[{"text":"ab cd","min_value":1}]'::jsonb,NULL)$s$,'am_invalid_input');   -- limits only on measure
 PERFORM c10_test.denied($s$SELECT c10_demo.am_save_checklist_template_v1(101,'cl-val-0009','CL-V','nn',NULL,'[{"text":"ab cd","seq":1},{"text":"ef gh","seq":3}]'::jsonb,NULL)$s$,'am_invalid_input'); -- gap
 PERFORM c10_test.denied($s$SELECT c10_demo.am_save_checklist_template_v1(101,'cl-val-0010','CL-V','nn',NULL,'[{"text":"ab cd","seq":1},{"text":"ef gh"}]'::jsonb,NULL)$s$,'am_invalid_input'); -- mixed seq
 PERFORM c10_test.denied($s$SELECT c10_demo.am_save_checklist_template_v1(101,'cl-val-0011','CL-V','nn',NULL,'[{"text":"ab cd","seq":2},{"text":"ef gh","seq":2}]'::jsonb,NULL)$s$,'am_invalid_input'); -- dup
 PERFORM c10_test.denied($s$SELECT c10_demo.am_save_checklist_template_v1(101,'cl-val-0012','CL-V','nn',NULL,'[{"text":"ab cd","evil":1}]'::jsonb,NULL)$s$,'am_invalid_input');   -- unknown key
 PERFORM c10_test.denied($s$SELECT c10_demo.am_save_checklist_template_v1(101,'cl-val-0013','CL-V','nn',NULL,'[{"text":5}]'::jsonb,NULL)$s$,'am_invalid_input');                -- type
 PERFORM c10_test.denied($s$SELECT c10_demo.am_save_checklist_template_v1(101,'cl-val-0014','CL-V','nn',NULL,'[{"text":"a"}]'::jsonb,NULL)$s$,'am_invalid_input');                -- too short
 PERFORM c10_test.denied($s$SELECT c10_demo.am_save_checklist_template_v1(101,'cl-val-0015','CL-V','nn',NULL,'[{"text":"ab cd","required":"yes"}]'::jsonb,NULL)$s$,'am_invalid_input');
 PERFORM c10_test.denied(format($s$SELECT c10_demo.am_save_checklist_template_v1(101,'cl-val-0016','CL-V','nn',%s,'[{"text":"ab cd"}]'::jsonb,NULL)$s$,c10_test.cid(102,'PROD-EQ')),'am_denied'); -- other business category
 PERFORM c10_test.eq(c10_test.q($s$SELECT count(*) FROM c10_demo.am_checklist_templates WHERE code='CL-V'$s$),'0','no partial template after rejected saves');
 PERFORM c10_test.eq((c10_demo.am_save_checklist_template_v1(101,'cl-val-0017','CL-SEQ','Explicit seq',c10_test.cid(101,'PROD-EQ'),'[{"text":"second step","seq":2},{"text":"first step","seq":1}]'::jsonb,NULL))->>'items_count','2','explicit seq accepted');
 PERFORM c10_test.eq(c10_test.q($s$SELECT string_agg(text,'|' ORDER BY seq) FROM c10_demo.am_checklist_items i JOIN c10_demo.am_checklist_templates t ON t.id=i.template_id WHERE t.code='CL-SEQ'$s$),'first step|second step','seq ordering');
END $$; COMMIT;

-- ===== T4 plans: scope, validation, targets (category + child category + site scope, retired excluded) =====
BEGIN; SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb; cat bigint:=c10_test.cid(101,'PROD-EQ'); BEGIN
 PERFORM c10_test.as_user('sup');
 -- validation edge cases (every one must leave no trace)
 PERFORM c10_test.denied($s$SELECT c10_demo.am_save_plan_v1(101,'pv-0000001',NULL,NULL,'[]'::jsonb,NULL)$s$,'am_invalid_input');
 PERFORM c10_test.denied($s$SELECT c10_demo.am_save_plan_v1(101,'pv-0000002',NULL,NULL,'{"name":"Plan","evil":1}'::jsonb,NULL)$s$,'am_invalid_input');
 PERFORM c10_test.denied(format($s$SELECT c10_demo.am_save_plan_v1(101,'pv-0000003',NULL,NULL,'{"name":"Plan A","plan_type":"bogus","category_id":%s,"frequency_kind":"weekly","start_on":"2030-01-01"}'::jsonb,NULL)$s$,cat),'am_invalid_input');
 PERFORM c10_test.denied(format($s$SELECT c10_demo.am_save_plan_v1(101,'pv-0000004',NULL,NULL,'{"name":"Plan A","plan_type":"preventive","category_id":%s,"frequency_kind":"usage","start_on":"2030-01-01"}'::jsonb,NULL)$s$,cat),'am_invalid_input'); -- usage needs meter
 PERFORM c10_test.denied(format($s$SELECT c10_demo.am_save_plan_v1(101,'pv-0000005',NULL,NULL,'{"name":"Plan A","plan_type":"preventive","category_id":%s,"frequency_kind":"weekly","meter_code":"HRS","start_on":"2030-01-01"}'::jsonb,NULL)$s$,cat),'am_invalid_input'); -- time plan with meter
 PERFORM c10_test.denied(format($s$SELECT c10_demo.am_save_plan_v1(101,'pv-0000006',NULL,NULL,'{"name":"Plan A","plan_type":"preventive","category_id":%s,"frequency_kind":"weekly","start_on":"2030-01-01","end_on":"2029-01-01"}'::jsonb,NULL)$s$,cat),'am_invalid_input');
 PERFORM c10_test.denied(format($s$SELECT c10_demo.am_save_plan_v1(101,'pv-0000007',NULL,NULL,'{"name":"Plan A","plan_type":"preventive","category_id":%s,"frequency_kind":"weekly","start_on":"2030-13-45"}'::jsonb,NULL)$s$,cat),'am_invalid_input');
 PERFORM c10_test.denied(format($s$SELECT c10_demo.am_save_plan_v1(101,'pv-0000008',NULL,NULL,'{"name":"Plan A","plan_type":"preventive","category_id":%s,"frequency_kind":"weekly","start_on":20300101}'::jsonb,NULL)$s$,cat),'am_invalid_input');
 PERFORM c10_test.denied(format($s$SELECT c10_demo.am_save_plan_v1(101,'pv-0000009',NULL,NULL,'{"name":"Plan A","plan_type":"preventive","category_id":%s,"frequency_kind":"weekly","interval_n":0,"start_on":"2030-01-01"}'::jsonb,NULL)$s$,cat),'am_invalid_input');
 PERFORM c10_test.denied(format($s$SELECT c10_demo.am_save_plan_v1(101,'pv-0000010',NULL,NULL,'{"name":"Plan A","plan_type":"preventive","category_id":%s,"frequency_kind":"weekly","interval_n":3651,"start_on":"2030-01-01"}'::jsonb,NULL)$s$,cat),'am_invalid_input');
 PERFORM c10_test.denied(format($s$SELECT c10_demo.am_save_plan_v1(101,'pv-0000011',NULL,NULL,'{"name":"Plan A","plan_type":"preventive","category_id":%s,"frequency_kind":"weekly","interval_n":1.5,"start_on":"2030-01-01"}'::jsonb,NULL)$s$,cat),'am_invalid_input');
 PERFORM c10_test.denied(format($s$SELECT c10_demo.am_save_plan_v1(101,'pv-0000012',NULL,NULL,'{"name":"P","plan_type":"preventive","category_id":%s,"frequency_kind":"weekly","start_on":"2030-01-01"}'::jsonb,NULL)$s$,cat),'am_invalid_input');
 PERFORM c10_test.denied(format($s$SELECT c10_demo.am_save_plan_v1(101,'pv-0000013',NULL,NULL,'{"name":"Plan A","plan_type":"preventive","category_id":%s,"asset_id":%s,"frequency_kind":"weekly","start_on":"2030-01-01"}'::jsonb,NULL)$s$,cat,c10_test.aid('T-OVEN-1')),'am_invalid_input'); -- both scopes
 PERFORM c10_test.denied($s$SELECT c10_demo.am_save_plan_v1(101,'pv-0000014',NULL,NULL,'{"name":"Plan A","plan_type":"preventive","frequency_kind":"weekly","start_on":"2030-01-01"}'::jsonb,NULL)$s$,'am_invalid_input'); -- no scope
 PERFORM c10_test.denied(format($s$SELECT c10_demo.am_save_plan_v1(101,'pv-0000015',NULL,NULL,'{"name":"Plan A","plan_type":"preventive","asset_id":%s,"frequency_kind":"weekly","start_on":"2030-01-01"}'::jsonb,NULL)$s$,c10_test.aid('T-X102')),'am_denied'); -- other business asset
 PERFORM c10_test.denied(format($s$SELECT c10_demo.am_save_plan_v1(101,'pv-0000016',NULL,NULL,'{"name":"Plan A","plan_type":"preventive","asset_id":%s,"frequency_kind":"weekly","start_on":"2030-01-01"}'::jsonb,NULL)$s$,c10_test.aid('T-X201')),'am_denied'); -- other tenant asset
 PERFORM c10_test.denied(format($s$SELECT c10_demo.am_save_plan_v1(101,'pv-0000017',NULL,NULL,'{"name":"Plan A","plan_type":"preventive","category_id":%s,"frequency_kind":"weekly","start_on":"2030-01-01"}'::jsonb,NULL)$s$,c10_test.cid(102,'PROD-EQ')),'am_denied');
 PERFORM c10_test.denied(format($s$SELECT c10_demo.am_save_plan_v1(101,'pv-0000018',NULL,NULL,'{"name":"Plan A","plan_type":"preventive","category_id":%s,"site_id":1003,"frequency_kind":"weekly","start_on":"2030-01-01"}'::jsonb,NULL)$s$,cat),'am_denied'); -- site of other business
 PERFORM c10_test.denied(format($s$SELECT c10_demo.am_save_plan_v1(101,'pv-0000019',NULL,NULL,'{"name":"Plan A","plan_type":"preventive","asset_id":%s,"frequency_kind":"weekly","start_on":"2030-01-01"}'::jsonb,NULL)$s$,c10_test.aid('T-OLD-5')),'am_asset_retired');
 PERFORM c10_test.denied(format($s$SELECT c10_demo.am_save_plan_v1(101,'pv-0000020',NULL,NULL,'{"name":"Plan A","plan_type":"preventive","category_id":%s,"frequency_kind":"weekly","start_on":"2030-01-01","checklist_code":"NOPE"}'::jsonb,NULL)$s$,cat),'am_checklist_not_found');
 PERFORM c10_test.denied(format($s$SELECT c10_demo.am_save_plan_v1(101,'pv-0000021',NULL,NULL,'{"name":"Plan A","plan_type":"preventive","category_id":%s,"frequency_kind":"weekly","start_on":"2030-01-01","priority":"urgent"}'::jsonb,NULL)$s$,cat),'am_invalid_input');
 PERFORM c10_test.denied(format($s$SELECT c10_demo.am_save_plan_v1(101,'pv-0000022',NULL,NULL,'{"name":"Plan A","plan_type":"preventive","category_id":%s,"frequency_kind":"weekly","start_on":"2030-01-01","lead_days":91}'::jsonb,NULL)$s$,cat),'am_invalid_input');
 PERFORM c10_test.denied($s$SELECT c10_demo.am_save_plan_v1(101,'pv-0000023',999999,1,'{"name":"Plan A"}'::jsonb,'edit reason')$s$,'am_denied');
 PERFORM c10_test.eq(c10_test.q($s$SELECT count(*) FROM c10_demo.am_plans$s$),'0','no plan created by rejected saves');
 -- category plan (weekly, due 2 days ago): covers PROD-EQ and its CHILD category on every site; not COLD, not retired, not other business
 r:=c10_demo.am_save_plan_v1(101,'plan-pc-0001',NULL,NULL,format($j${"name":"Weekly PM","plan_type":"preventive","category_id":%s,"frequency_kind":"weekly","interval_n":1,"start_on":"%s","checklist_code":"CL-PM","priority":"medium"}$j$,cat,c10_test.d(-2))::jsonb,'initial rollout');
 PERFORM c10_test.put('pC',r->>'id');
 PERFORM c10_test.eq(r->>'event','create','plan create event'); PERFORM c10_test.eq(r->>'target_count','4','targets: A1 A2 A4 and child-category A7');
 PERFORM c10_test.eq(c10_test.q($s$SELECT string_agg(a.asset_no,',' ORDER BY a.asset_no) FROM c10_demo.am_plan_targets t JOIN c10_demo.am_assets a ON a.id=t.asset_id WHERE t.plan_id=$s$||c10_test.g('pC')),'T-CONV-4,T-MIXER-2,T-OVEN-1,T-OVEN-7','target set');
 PERFORM c10_test.eq(c10_demo.am_save_plan_v1(101,'plan-pc-0001',NULL,NULL,format($j${"name":"Weekly PM","plan_type":"preventive","category_id":%s,"frequency_kind":"weekly","interval_n":1,"start_on":"%s","checklist_code":"CL-PM","priority":"medium"}$j$,cat,c10_test.d(-2))::jsonb,'initial rollout')::text,r::text,'plan replay identical');
 PERFORM c10_test.eq(c10_test.q($s$SELECT count(*) FROM c10_demo.am_plans$s$),'1','replay: still one plan');
 PERFORM c10_test.denied(format($s$SELECT c10_demo.am_save_plan_v1(101,'plan-pc-0001',NULL,NULL,'{"name":"Other","plan_type":"preventive","category_id":%s,"frequency_kind":"weekly","start_on":"2030-01-01"}'::jsonb,NULL)$s$,cat),'am_idempotency_conflict');
 -- category + site scope (only the godown-site machine of that site)
 r:=c10_demo.am_save_plan_v1(101,'plan-ps-0001',NULL,NULL,format($j${"name":"Site 1002 inspection","plan_type":"inspection","category_id":%s,"site_id":1002,"frequency_kind":"monthly","start_on":"%s"}$j$,cat,c10_test.d(30))::jsonb,NULL);
 PERFORM c10_test.put('pS',r->>'id'); PERFORM c10_test.eq(r->>'target_count','1','site-scoped category plan covers one asset');
 PERFORM c10_test.eq(c10_test.q($s$SELECT a.asset_no FROM c10_demo.am_plan_targets t JOIN c10_demo.am_assets a ON a.id=t.asset_id WHERE t.plan_id=$s$||c10_test.g('pS')),'T-MIXER-2','site scope member');
 -- site-limited supervisor may plan for assets of ITS site, with unscoped category/other site refused
 PERFORM c10_test.as_user('sup1001');
 r:=c10_demo.am_save_plan_v1(101,'plan-pa-0001',NULL,NULL,format($j${"name":"Oven 1 daily check","plan_type":"inspection","asset_id":%s,"frequency_kind":"daily","start_on":"%s"}$j$,c10_test.aid('T-OVEN-1'),c10_test.d(20))::jsonb,NULL);
 PERFORM c10_test.put('pA1',r->>'id'); PERFORM c10_test.eq(r->>'target_count','1','asset plan');
 PERFORM c10_test.denied(format($s$SELECT c10_demo.am_save_plan_v1(101,'plan-pa-0002',NULL,NULL,'{"name":"Mixer check","plan_type":"inspection","asset_id":%s,"frequency_kind":"daily","start_on":"2030-01-01"}'::jsonb,NULL)$s$,c10_test.aid('T-MIXER-2')),'am_not_permitted');
 PERFORM c10_test.denied(format($s$SELECT c10_demo.am_save_plan_v1(101,'plan-pa-0003',%s,1,'{"name":"Tamper"}'::jsonb,'edit reason')$s$,c10_test.g('pS')),'am_not_permitted');
 -- plan list is filtered to visible sites
 PERFORM c10_test.eq((SELECT jsonb_agg(i->>'name' ORDER BY i->>'name')::text FROM jsonb_array_elements(c10_demo.am_list_plans_v1(101)->'items') i),'["Oven 1 daily check", "Weekly PM"]','sup1001 sees only its site plans + unscoped category plan');
 PERFORM c10_test.as_user('tech1002');
 PERFORM c10_test.eq((SELECT jsonb_agg(i->>'name' ORDER BY i->>'name')::text FROM jsonb_array_elements(c10_demo.am_list_plans_v1(101)->'items') i),'["Site 1002 inspection", "Weekly PM"]','tech1002 sees site 1002 plans');
 PERFORM c10_test.eq((SELECT bool_or((i->>'can_edit')::boolean)::text FROM jsonb_array_elements(c10_demo.am_list_plans_v1(101)->'items') i),'false','technician cannot edit');
 PERFORM c10_test.denied($s$SELECT c10_demo.am_list_plans_v1(101,'{"bogus":1}'::jsonb)$s$,'am_invalid_input');
 PERFORM c10_test.as_user('auditor');
 PERFORM c10_test.eq(jsonb_array_length(c10_demo.am_list_plans_v1(101)->'items')::text,'3','auditor sees all plans');
 PERFORM c10_test.eq(jsonb_array_length(c10_demo.am_list_plans_v1(101,'{"plan_type":"inspection"}'::jsonb)->'items')::text,'2','filter plan_type');
 PERFORM c10_test.denied(format($s$SELECT c10_demo.am_save_plan_v1(101,'plan-aud-001',%s,1,'{"name":"Tamper"}'::jsonb,'edit reason')$s$,c10_test.g('pC')),'am_not_permitted');
 -- tenant isolation: other business plan
 PERFORM c10_test.as_user('bo102');
 r:=c10_demo.am_save_plan_v1(102,'plan-x102-001',NULL,NULL,format($j${"name":"X102 plan","plan_type":"preventive","asset_id":%s,"frequency_kind":"weekly","start_on":"%s"}$j$,c10_test.aid('T-X102'),c10_test.d(0))::jsonb,NULL);
 PERFORM c10_test.put('pX102',r->>'id');
 PERFORM c10_test.denied(format($s$SELECT c10_demo.am_save_plan_v1(101,'plan-x102-002',%s,1,'{"name":"x"}'::jsonb,'edit reason')$s$,c10_test.g('pX102')),'am_denied'); -- not a member of 101
 PERFORM c10_test.as_user('sup');
 PERFORM c10_test.denied(format($s$SELECT c10_demo.am_save_plan_v1(101,'plan-x102-003',%s,1,'{"name":"x1"}'::jsonb,'edit reason')$s$,c10_test.g('pX102')),'am_denied'); -- id of other business hidden
 PERFORM c10_test.put('tX102',c10_test.q($s$SELECT id FROM c10_demo.am_plan_targets WHERE plan_id=$s$||c10_test.g('pX102')));
END $$; COMMIT;

-- ===== T5 due suggestions: states, escalation boundaries with a controlled clock (explicit past start_on), visibility =====
BEGIN; SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb; s jsonb; i jsonb; k int; nm text; off int; lv int; pid bigint; BEGIN
 PERFORM c10_test.as_user('sup');
 -- grace_days=3, escalation_days=3 (defaults): overdue 3 => level 0; 4 => 1; 6 => 1; 7 => 2
 FOREACH off IN ARRAY ARRAY[3,4,6,7] LOOP
  r:=c10_demo.am_save_plan_v1(101,'plan-esc-00'||off,NULL,NULL,format($j${"name":"ESC-%s","plan_type":"preventive","asset_id":%s,"frequency_kind":"daily","start_on":"%s"}$j$,off,c10_test.aid('T-CHILL-3'),c10_test.d(-off))::jsonb,NULL);
  PERFORM c10_test.put('pEsc'||off,r->>'id');
 END LOOP;
 s:=c10_demo.am_due_suggestions_v1(101,NULL,NULL);
 PERFORM c10_test.eq(s->>'total','8','4 weekly PM targets + 4 escalation targets in window');
 FOREACH off IN ARRAY ARRAY[3,4,6,7] LOOP
  i:=c10_test.item(s,'ESC-'||off,'T-CHILL-3');
  PERFORM c10_test.eq(i->>'state','overdue','state overdue '||off); PERFORM c10_test.eq(i->>'days_overdue',off::text,'days overdue '||off);
  PERFORM c10_test.eq(i->>'escalation_level',CASE off WHEN 3 THEN '0' WHEN 4 THEN '1' WHEN 6 THEN '1' ELSE '2' END,'escalation level '||off);
 END LOOP;
 i:=c10_test.item(s,'Weekly PM','T-OVEN-1');
 PERFORM c10_test.eq(i->>'state','overdue','weekly overdue'); PERFORM c10_test.eq(i->>'escalation_level','0','within grace'); PERFORM c10_test.eq(i->>'days_overdue','2','2 days');
 PERFORM c10_test.eq(i->>'can_generate','true','supervisor can generate');
 PERFORM c10_test.eq(s->'items'->0->>'escalation_level','2','most escalated first');
 -- plans starting far ahead are not listed by default but appear (as upcoming) with an explicit horizon
 PERFORM c10_test.eq(c10_test.item(s,'Oven 1 daily check','T-OVEN-1')::text,NULL,'upcoming hidden outside lead window');
 s:=c10_demo.am_due_suggestions_v1(101,NULL,40);
 PERFORM c10_test.eq(s->>'total','10','horizon 40 adds the two upcoming plans');
 PERFORM c10_test.eq(c10_test.item(s,'Oven 1 daily check','T-OVEN-1')->>'state','upcoming','upcoming state');
 PERFORM c10_test.eq(c10_test.item(s,'Site 1002 inspection','T-MIXER-2')->>'days_until_due','30','days until');
 -- lead window: plan due in 5 days with lead 7 is "due", with lead_days=2 it is hidden
 r:=c10_demo.am_save_plan_v1(101,'plan-lead-001',NULL,NULL,format($j${"name":"Lead test","plan_type":"inspection","asset_id":%s,"frequency_kind":"weekly","start_on":"%s"}$j$,c10_test.aid('T-CONV-4'),c10_test.d(5))::jsonb,NULL);
 PERFORM c10_test.put('pLead',r->>'id');
 PERFORM c10_test.eq(c10_test.item(c10_demo.am_due_suggestions_v1(101,NULL,NULL),'Lead test','T-CONV-4')->>'state','due','due within lead');
 r:=c10_demo.am_save_plan_v1(101,'plan-lead-002',c10_test.gi('pLead'),1,'{"lead_days":2}'::jsonb,'narrow lead window');
 PERFORM c10_test.eq(r->>'rule_changed','false','lead_days is not a due-date rule');
 PERFORM c10_test.eq(c10_test.item(c10_demo.am_due_suggestions_v1(101,NULL,NULL),'Lead test','T-CONV-4')::text,NULL,'outside narrowed lead window');
 -- visibility: only sites where the caller has "view"; technicians cannot generate
 PERFORM c10_test.as_user('tech1001'); s:=c10_demo.am_due_suggestions_v1(101,NULL,NULL);
 PERFORM c10_test.eq(s->>'total','6','tech1001: 2 weekly PM (A1,A7) + 4 chiller escalations'); PERFORM c10_test.eq(c10_test.item(s,'Weekly PM','T-OVEN-1')->>'can_generate','false','tech cannot generate');
 PERFORM c10_test.eq(c10_test.item(s,'Weekly PM','T-MIXER-2')::text,NULL,'site 1002 hidden from tech1001');
 PERFORM c10_test.denied($s$SELECT c10_demo.am_due_suggestions_v1(101,1002,NULL)$s$,'am_not_permitted');
 PERFORM c10_test.denied($s$SELECT c10_demo.am_due_suggestions_v1(101,1003,NULL)$s$,'am_denied');   -- site of another business
 PERFORM c10_test.as_user('tech1002'); s:=c10_demo.am_due_suggestions_v1(101,NULL,NULL);
 PERFORM c10_test.eq(s->>'total','1','tech1002 sees only mixer (site 1002)');
 PERFORM c10_test.as_user('auditor'); PERFORM c10_test.eq((c10_demo.am_due_suggestions_v1(101,NULL,NULL))->>'total','8','auditor reads every site');
 PERFORM c10_test.eq((c10_demo.am_due_suggestions_v1(101,1002,NULL))->>'total','1','site filter');
 PERFORM c10_test.denied($s$SELECT c10_demo.am_due_suggestions_v1(101,NULL,400)$s$,'am_invalid_input');
 PERFORM c10_test.denied($s$SELECT c10_demo.am_due_suggestions_v1(101,NULL,-1)$s$,'am_invalid_input');
 -- deactivate the escalation plans: events, suspended targets, gone from suggestions; reactivation brings one back
 PERFORM c10_test.as_user('sup');
 FOREACH off IN ARRAY ARRAY[3,4,6,7] LOOP
  r:=c10_demo.am_save_plan_v1(101,'plan-escoff-0'||off,c10_test.gi('pEsc'||off),1,'{"active":false}'::jsonb,'retire escalation test');
  PERFORM c10_test.eq(r->>'event','deactivate','deactivate event');
 END LOOP;
 PERFORM c10_test.eq(c10_test.q($s$SELECT count(*) FROM c10_demo.am_plan_targets WHERE plan_id IN (SELECT id FROM c10_demo.am_plans WHERE name LIKE 'ESC-%') AND status='suspended'$s$),'4','targets suspended');
 PERFORM c10_test.eq((c10_demo.am_due_suggestions_v1(101,NULL,NULL))->>'total','4','escalation plans no longer suggested');
 r:=c10_demo.am_save_plan_v1(101,'plan-escon-007',c10_test.gi('pEsc7'),2,'{"active":true}'::jsonb,'re-enable');
 PERFORM c10_test.eq(r->>'event','activate','activate event');
 PERFORM c10_test.eq(c10_test.item(c10_demo.am_due_suggestions_v1(101,NULL,NULL),'ESC-7','T-CHILL-3')->>'escalation_level','2','reactivated target escalates');
 r:=c10_demo.am_save_plan_v1(101,'plan-escoff-107',c10_test.gi('pEsc7'),3,'{"active":false}'::jsonb,'retire again');
END $$; COMMIT;

-- ===== T6 generation: human-triggered, per-site authority, idempotent, never duplicates =====
BEGIN; SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb; r2 jsonb; w record; BEGIN
 PERFORM c10_test.as_user('sup1001');
 r:=c10_demo.am_generate_work_orders_v1(101,'gen-sup1001-01',NULL,NULL,NULL);
 PERFORM c10_test.eq(r->>'created_count','2','site supervisor creates for its site only (A1, A7)');
 PERFORM c10_test.eq(r->>'skipped_count','0','targets of other sites are invisible, not even listed as skipped');
 PERFORM c10_test.eq(c10_test.q($s$SELECT count(*) FROM c10_demo.am_work_orders w JOIN c10_demo.am_assets a ON a.id=w.asset_id WHERE a.site_id<>1001$s$),'0','no WO outside the supervisor site');
 PERFORM c10_test.eq(c10_test.q($s$SELECT count(*) FROM c10_demo.am_work_orders$s$),'2','two work orders exist');
 SELECT * INTO w FROM c10_demo.am_work_orders WHERE asset_id=c10_test.aid('T-OVEN-1');
 PERFORM c10_test.eq(w.status,'DRAFT','generated as DRAFT by default'); PERFORM c10_test.eq(w.source,'plan','source plan'); PERFORM c10_test.eq(w.kind,'preventive','kind');
 PERFORM c10_test.eq(w.site_id::text,'1001','site from asset'); PERFORM c10_test.eq(w.plan_target_id::text,c10_test.tgt('pC','T-OVEN-1')::text,'target link');
 PERFORM c10_test.eq(w.due_on::text,c10_test.d(-2),'due_on = target due'); PERFORM c10_test.eq(w.priority,'medium','plan priority');
 PERFORM c10_test.eq(w.service_category,'ROUTINE','service category'); PERFORM c10_test.eq(w.safety_critical::text,'false','category safety flag copied');
 PERFORM c10_test.eq(w.wo_no,'WO-000001','numbered per business'); PERFORM c10_test.eq(w.requested_by::text,c10_test.u('sup1001')::text,'requester is the actor');
 PERFORM c10_test.eq((abs(extract(epoch FROM w.sla_response_due_at-w.created_at)-24*3600)<2)::text,'true','SLA response 24h (medium) from policy');
 PERFORM c10_test.eq((abs(extract(epoch FROM w.sla_resolve_due_at-w.created_at)-120*3600)<2)::text,'true','SLA resolve 120h (medium) from policy');
 PERFORM c10_test.eq(c10_test.q($s$SELECT string_agg(text,'|' ORDER BY seq) FROM c10_demo.am_wo_checklist WHERE work_order_id=$s$||w.id),
  'Isolate power and lock out|Check belt tension and alignment|Motor temperature','active checklist v2 snapshotted');
 PERFORM c10_test.eq(c10_test.q($s$SELECT count(*) FROM c10_demo.am_wo_history WHERE work_order_id=$s$||w.id||$s$ AND action='create'$s$),'1','history row');
 PERFORM c10_test.put('woA1',w.id::text);
 PERFORM c10_test.eq(c10_test.q($s$SELECT count(*) FROM c10_demo.am_audit WHERE entity='work_order' AND event='generate'$s$),'2','generation audited per work order');
 -- replay: identical receipt, nothing new; same key + other params conflicts
 r2:=c10_demo.am_generate_work_orders_v1(101,'gen-sup1001-01',NULL,NULL,NULL);
 PERFORM c10_test.eq(r2::text,r::text,'generation replay identical'); PERFORM c10_test.eq(c10_test.q($s$SELECT count(*) FROM c10_demo.am_work_orders$s$),'2','replay created nothing');
 PERFORM c10_test.denied($s$SELECT c10_demo.am_generate_work_orders_v1(101,'gen-sup1001-01',NULL,1001,NULL)$s$,'am_idempotency_conflict');
 PERFORM c10_test.denied($s$SELECT c10_demo.am_generate_work_orders_v1(101,'gen-sup1001-02',NULL,1002,NULL)$s$,'am_not_permitted');   -- site without assign
 PERFORM c10_test.denied($s$SELECT c10_demo.am_generate_work_orders_v1(101,'gen-sup1001-03',NULL,1003,NULL)$s$,'am_denied');         -- other business site
 -- same sweep again with a NEW key: no duplicate task
 r:=c10_demo.am_generate_work_orders_v1(101,'gen-sup1001-04',NULL,NULL,NULL);
 PERFORM c10_test.eq(r->>'created_count','0','repeat: nothing created'); PERFORM c10_test.eq(c10_test.q($s$SELECT count(*) FROM c10_demo.am_work_orders$s$),'2','still two');
 PERFORM c10_test.eq((SELECT count(*) FROM jsonb_array_elements(r->'skipped') s WHERE s->>'reason'='has_open_wo')::text,'2','open-WO skips');
 -- full-authority supervisor completes the sweep; the godown/project machine auto-submits by site policy
 PERFORM c10_test.as_user('sup');
 r:=c10_demo.am_generate_work_orders_v1(101,'gen-sup-0001',NULL,NULL,NULL);
 PERFORM c10_test.eq(r->>'created_count','2','A2 + A4'); PERFORM c10_test.eq(r->>'skipped_count','2','A1 + A7 already have open WOs');
 PERFORM c10_test.eq(c10_test.q($s$SELECT status FROM c10_demo.am_work_orders WHERE asset_id=$s$||c10_test.aid('T-CONV-4')),'SUBMITTED','site policy schedule.auto_submit_generated=true');
 PERFORM c10_test.eq(c10_test.q($s$SELECT status FROM c10_demo.am_work_orders WHERE asset_id=$s$||c10_test.aid('T-MIXER-2')),'DRAFT','other sites stay DRAFT');
 PERFORM c10_test.eq(c10_test.q($s$SELECT count(*)||'/'||count(submitted_at) FROM c10_demo.am_work_orders WHERE status='SUBMITTED'$s$),'1/1','submitted_at set');
 PERFORM c10_test.eq(c10_test.q($s$SELECT count(*) FROM c10_demo.am_wo_history h JOIN c10_demo.am_work_orders w ON w.id=h.work_order_id WHERE w.asset_id=$s$||c10_test.aid('T-CONV-4')),'2','create+submit history');
 r:=c10_demo.am_generate_work_orders_v1(101,'gen-sup-0002',NULL,NULL,NULL);
 PERFORM c10_test.eq(r->>'created_count','0','third sweep: nothing'); PERFORM c10_test.eq(c10_test.q($s$SELECT count(*) FROM c10_demo.am_work_orders$s$),'4','exactly one open WO per target');
 PERFORM c10_test.eq(c10_test.q($s$SELECT count(*) FROM c10_demo.am_plan_targets WHERE last_wo_id IS NOT NULL$s$),'4','last_wo_id recorded');
 -- explicit ids: unknown / foreign targets reported, not leaked
 r:=c10_demo.am_generate_work_orders_v1(101,'gen-sup-0003',ARRAY[999999,c10_test.gi('tX102'),c10_test.tgt('pC','T-OVEN-1')],NULL,NULL);
 PERFORM c10_test.eq((SELECT string_agg(s->>'target_id'||':'||(s->>'reason'),',' ORDER BY s->>'target_id') FROM jsonb_array_elements(r->'skipped') s),
  least(c10_test.gi('tX102')::text||':not_found',c10_test.tgt('pC','T-OVEN-1')::text||':has_open_wo')||','||greatest(c10_test.gi('tX102')::text||':not_found',c10_test.tgt('pC','T-OVEN-1')::text||':has_open_wo')||',999999:not_found' ,'explicit skip reasons');
 PERFORM c10_test.denied($s$SELECT c10_demo.am_generate_work_orders_v1(101,'gen-sup-0004',ARRAY[NULL]::bigint[],NULL,NULL)$s$,'am_invalid_input');
 PERFORM c10_test.denied($s$SELECT c10_demo.am_generate_work_orders_v1(101,'gen-sup-0005',(SELECT array_agg(g) FROM generate_series(1,201) g),NULL,NULL)$s$,'am_invalid_input');
 PERFORM c10_test.denied($s$SELECT c10_demo.am_generate_work_orders_v1(101,'gen-sup-0006',NULL,NULL,400)$s$,'am_invalid_input');
 -- not due yet: skipped unless the human widens the horizon; certification plans become inspection work orders
 r:=c10_demo.am_save_plan_v1(101,'plan-cert-001',NULL,NULL,format($j${"name":"Chiller certificate","plan_type":"certification","asset_id":%s,"frequency_kind":"yearly","start_on":"%s"}$j$,c10_test.aid('T-CHILL-3'),c10_test.d(20))::jsonb,NULL);
 PERFORM c10_test.put('pCert',r->>'id');
 r:=c10_demo.am_generate_work_orders_v1(101,'gen-sup-0007',ARRAY[c10_test.tgt('pCert','T-CHILL-3')],NULL,NULL);
 PERFORM c10_test.eq(r->'skipped'->0->>'reason','not_due','not due without horizon');
 r:=c10_demo.am_generate_work_orders_v1(101,'gen-sup-0008',ARRAY[c10_test.tgt('pCert','T-CHILL-3')],NULL,30);
 PERFORM c10_test.eq(r->>'created_count','1','horizon widened by a human'); PERFORM c10_test.eq(c10_test.q($s$SELECT kind||'/'||service_category FROM c10_demo.am_work_orders WHERE id=$s$||(r->'created'->0->>'wo_id')),'inspection/SAFETY','certification mapping');
 -- two plans on one asset+kind: the second is blocked by wo.overlap_policy=block (reported, never duplicated)
 r:=c10_demo.am_save_plan_v1(101,'plan-ov-0001',NULL,NULL,format($j${"name":"Second PM plan","plan_type":"preventive","asset_id":%s,"frequency_kind":"daily","start_on":"%s"}$j$,c10_test.aid('T-OVEN-1'),c10_test.d(-1))::jsonb,NULL);
 PERFORM c10_test.put('pOv',r->>'id');
 r:=c10_demo.am_generate_work_orders_v1(101,'gen-sup-0009',ARRAY[c10_test.tgt('pOv','T-OVEN-1')],NULL,NULL);
 PERFORM c10_test.eq(r->'skipped'->0->>'reason','overlapping_work_order','overlap blocked');
 PERFORM c10_test.eq(c10_test.q($s$SELECT count(*) FROM c10_demo.am_work_orders WHERE status NOT IN ('CLOSED','CANCELLED')$s$),'5','no duplicate after overlap');
 -- failed sub-step leaves no partial work order and does not burn the receipt of a valid request
 PERFORM c10_test.eq(c10_test.q($s$SELECT next_val::text FROM c10_demo.am_counters WHERE business_id=101 AND kind='wo'$s$),'6','counter not burnt by skipped overlap');
END $$; COMMIT;
-- DB-level backstop: a second OPEN work order for the same plan target is impossible even for a buggy writer
DO $$ BEGIN
 PERFORM c10_test.denied(format($s$INSERT INTO c10_demo.am_work_orders(tenant_id,business_id,wo_no,kind,asset_id,site_id,plan_target_id,title,requested_by)
  VALUES(1,101,'DUP-1','preventive',%s,1001,%s,'duplicate try','11111111-1111-4111-8111-111111111111')$s$,c10_test.aid('T-OVEN-1'),c10_test.tgt('pC','T-OVEN-1')),'duplicate key');
END $$;
