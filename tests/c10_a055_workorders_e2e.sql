-- C10-A055 work-orders end-to-end test (disposable PostgreSQL; signed-claim SIMULATION, not GoTrue). Synthetic data only.
-- Load: AM_FILES="core planning workorders lockdown" tests/c10_a055_load.sh <db>   (policy/registry/reports files may be loaded too)
-- Run : psql -X -q -v ON_ERROR_STOP=1 -d <db> -f tests/c10_a055_workorders_e2e.sql   (as superuser; RAISES on any failure)
\set ON_ERROR_STOP on
CREATE SCHEMA c10_test;
GRANT USAGE ON SCHEMA c10_test TO authenticated,anon;
CREATE TABLE c10_test.ids(k text PRIMARY KEY,v bigint);
CREATE SEQUENCE c10_test.seq;
GRANT ALL ON c10_test.ids TO authenticated; GRANT ALL ON SEQUENCE c10_test.seq TO authenticated;
CREATE FUNCTION c10_test.u(p text) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT (CASE p
 WHEN 'owner' THEN '11111111-1111-4111-8111-111111111111' WHEN 'bo101' THEN '22222222-2222-4222-8222-222222222222'
 WHEN 'mgr' THEN '33333333-3333-4333-8333-333333333333' WHEN 'stock' THEN '44444444-4444-4444-8444-444444444444'
 WHEN 'inv' THEN '55555555-5555-4555-8555-555555555555' WHEN 'revmgr' THEN '66666666-6666-4666-8666-666666666666'
 WHEN 'owner2' THEN '77777777-7777-4777-8777-777777777777' WHEN 'staff2' THEN '88888888-8888-4888-8888-888888888888'
 WHEN 'oper' THEN '99999999-9999-4999-8999-999999999999' WHEN 'sup' THEN 'd1111111-1111-4111-8111-111111111111'
 WHEN 'sup1' THEN 'd2222222-2222-4222-8222-222222222222' WHEN 't1' THEN 'd3333333-3333-4333-8333-333333333333'
 WHEN 't2' THEN 'd4444444-4444-4444-8444-444444444444' WHEN 'rep' THEN 'd5555555-5555-4555-8555-555555555555'
 WHEN 'aud' THEN 'd6666666-6666-4666-8666-666666666666' WHEN 'revt' THEN 'd7777777-7777-4777-8777-777777777777'
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
CREATE FUNCTION c10_test.k() RETURNS text LANGUAGE sql AS $$ SELECT 'rq-'||lpad(nextval('c10_test.seq')::text,8,'0') $$;
CREATE FUNCTION c10_test.put(p text,p_v bigint) RETURNS void LANGUAGE sql AS $$ INSERT INTO c10_test.ids VALUES(p,p_v) ON CONFLICT(k) DO UPDATE SET v=EXCLUDED.v $$;
CREATE FUNCTION c10_test.id(p text) RETURNS bigint LANGUAGE sql AS $$ SELECT v FROM c10_test.ids WHERE k=p $$;
-- superuser escape hatches (test fixtures only)
CREATE FUNCTION c10_test.sd(p_sql text) RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$ BEGIN EXECUTE p_sql; END$$;
CREATE FUNCTION c10_test.val(p_sql text) RETURNS text LANGUAGE plpgsql SECURITY DEFINER AS $$ DECLARE v text; BEGIN EXECUTE p_sql INTO v; RETURN v; END$$;
CREATE FUNCTION c10_test.v(p_wo bigint) RETURNS bigint LANGUAGE sql SECURITY DEFINER AS $$ SELECT version FROM c10_demo.am_work_orders WHERE id=p_wo $$;
CREATE FUNCTION c10_test.wst(p_wo bigint) RETURNS text LANGUAGE sql SECURITY DEFINER AS $$ SELECT status FROM c10_demo.am_work_orders WHERE id=p_wo $$;
CREATE FUNCTION c10_test.ast(p_asset bigint) RETURNS text LANGUAGE sql SECURITY DEFINER AS $$ SELECT status FROM c10_demo.am_assets WHERE id=p_asset $$;
CREATE FUNCTION c10_test.pol(p_key text,p_val jsonb,p_scope text DEFAULT 'business',p_scope_id bigint DEFAULT 0) RETURNS void LANGUAGE sql SECURITY DEFINER AS $$
 INSERT INTO c10_demo.am_policy(business_id,tenant_id,scope_type,scope_id,key,value,updated_by) VALUES(101,1,p_scope,p_scope_id,p_key,p_val,'11111111-1111-4111-8111-111111111111')
 ON CONFLICT(business_id,scope_type,scope_id,key) DO UPDATE SET value=EXCLUDED.value $$;
CREATE FUNCTION c10_test.unpol(p_key text) RETURNS void LANGUAGE sql SECURITY DEFINER AS $$ DELETE FROM c10_demo.am_policy WHERE business_id=101 AND key=p_key $$;
CREATE FUNCTION c10_test.t(p_wo bigint,p_action text,p_reason text DEFAULT NULL,p_data jsonb DEFAULT '{}') RETURNS jsonb LANGUAGE sql AS
$$ SELECT c10_demo.am_wo_transition_v1(101,c10_test.k(),p_wo,c10_test.v(p_wo),p_action,p_reason,p_data) $$;
CREATE FUNCTION c10_test.td(p_wo bigint,p_action text,p_expect text,p_reason text DEFAULT NULL,p_data jsonb DEFAULT '{}') RETURNS void LANGUAGE plpgsql AS $$
BEGIN PERFORM c10_test.denied(format('SELECT c10_test.t(%s,%L,%L,%L::jsonb)',p_wo,p_action,p_reason,p_data),p_expect); END$$;
CREATE FUNCTION c10_test.g(p_wo bigint) RETURNS jsonb LANGUAGE sql AS $$ SELECT c10_demo.am_get_work_order_v1(101,p_wo) $$;
CREATE FUNCTION c10_test.has(p_arr jsonb,p text) RETURNS boolean LANGUAGE sql IMMUTABLE AS $$ SELECT p_arr ? p $$;
CREATE FUNCTION c10_test.cr(p_asset bigint,p_title text,p_extra jsonb DEFAULT '{}') RETURNS bigint LANGUAGE sql AS
$$ SELECT (c10_demo.am_create_work_order_v1(101,c10_test.k(),jsonb_build_object('asset_id',p_asset,'title',p_title)||p_extra)->>'id')::bigint $$;
CREATE FUNCTION c10_test.cnt(p_sql text) RETURNS text LANGUAGE sql SECURITY DEFINER AS $$ SELECT c10_test.val(p_sql) $$;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA c10_test TO authenticated,anon;

-- ===== S0 fixtures (superuser): assets, meter, checklist template =====
DO $$
DECLARE mk text; cat bigint;
BEGIN
 PERFORM c10_demo.ami_ensure_business(101); PERFORM c10_demo.ami_ensure_business(102); PERFORM c10_demo.ami_ensure_business(201);
 INSERT INTO c10_demo.am_assets(tenant_id,business_id,asset_no,name,category_id,site_id,created_by)
 SELECT 1,101,x.no,x.nm,(SELECT id FROM c10_demo.am_categories WHERE business_id=101 AND code=x.cat),x.site,c10_test.u('bo101')
 FROM (VALUES('T-OVEN','Oven 1','PROD-EQ',1001),('T-GEN','Generator 1','POWER',1001),('T-CHILL','Chiller 1','COLD',1002),('T-PRESS','Press 1','PROD-EQ',1001),
  ('T-MIXER','Paint mixer','PROD-EQ',1001),('T-LATHE','Lathe 1','PROD-EQ',1001),('T-CAL','Gauge 1','TOOL',1001),('T-MERGE','Conveyor 1','GENERAL',1001),
  ('T-POS','POS 1','POS',1001),('T-RACE','Crane 1','LIFT',1001),('T-ONE','Laptop 1','IT',1001)) AS x(no,nm,cat,site);
 INSERT INTO c10_demo.am_assets(tenant_id,business_id,asset_no,name,category_id,site_id,created_by)
 VALUES(1,102,'T-B102','Other business asset',(SELECT id FROM c10_demo.am_categories WHERE business_id=102 AND code='GENERAL'),1003,c10_test.u('bo102')),
  (2,201,'T-T2','Tenant 2 asset',(SELECT id FROM c10_demo.am_categories WHERE business_id=201 AND code='GENERAL'),2001,c10_test.u('owner2'));
 FOR mk IN SELECT asset_no FROM c10_demo.am_assets WHERE asset_no LIKE 'T-%' LOOP
  PERFORM c10_test.put('a_'||mk,(SELECT id FROM c10_demo.am_assets WHERE asset_no=mk)); END LOOP;
 INSERT INTO c10_demo.am_meters(tenant_id,business_id,asset_id,code,unit,current_reading) VALUES(1,101,c10_test.id('a_T-OVEN'),'HRS','hours',100);
 INSERT INTO c10_demo.am_checklist_templates(tenant_id,business_id,code,version,name,created_by) VALUES(1,101,'T-PM1',1,'Test PM checklist',c10_test.u('bo101'));
 INSERT INTO c10_demo.am_checklist_items(tenant_id,business_id,template_id,seq,text,kind,required,min_value,max_value,unit)
 SELECT 1,101,t.id,i.seq,i.tx,i.kd,i.rq,i.mn,i.mx,i.un FROM c10_demo.am_checklist_templates t,
  (VALUES(1,'Isolate power','check',true,NULL::numeric,NULL::numeric,NULL),(2,'Pressure reading','measure',true,10,20,'bar'),(3,'Wipe down','check',false,NULL,NULL,NULL)) i(seq,tx,kd,rq,mn,mx,un)
 WHERE t.code='T-PM1' AND t.business_id=101;
END $$;

-- ===== S1 authority matrix: outsiders, stock-only staff, investor, revoked, other tenant/business, manager without grant, anon =====
BEGIN; SET LOCAL ROLE authenticated;
DO $$ DECLARE p text; BEGIN
 FOREACH p IN ARRAY ARRAY['stock','inv','revmgr','owner2','staff2','oper','bo102','mgr','revt','sup2'] LOOP
  PERFORM c10_test.as_user(p);
  PERFORM c10_test.denied('SELECT c10_demo.am_list_work_orders_v1(101,''{}'')','am_denied');
  PERFORM c10_test.denied('SELECT c10_demo.am_my_work_v1(101)','am_denied');
  PERFORM c10_test.denied('SELECT c10_demo.am_list_downtime_v1(101,''{}'')','am_denied');
  PERFORM c10_test.denied(format('SELECT c10_demo.am_create_work_order_v1(101,%L,jsonb_build_object(''asset_id'',%s,''title'',''Hack attempt''))',c10_test.k(),c10_test.id('a_T-OVEN')),'am_denied');
  PERFORM c10_test.denied(format('SELECT c10_demo.am_report_breakdown_v1(101,%L,%s,''{}'')',c10_test.k(),c10_test.id('a_T-OVEN')),'am_denied');
 END LOOP;
 PERFORM c10_test.as_user('sup'); PERFORM c10_test.denied('SELECT c10_demo.am_list_work_orders_v1(201,''{}'')','am_denied');
 PERFORM c10_test.denied('SELECT c10_demo.am_list_work_orders_v1(NULL,''{}'')','am_denied');
 PERFORM c10_test.as_user('sup2'); PERFORM c10_test.eq(c10_demo.am_list_work_orders_v1(201,'{}')->>'total','0','tenant2 supervisor sees own tenant');
 PERFORM c10_test.denied(format('SELECT c10_demo.am_create_work_order_v1(201,%L,jsonb_build_object(''asset_id'',%s,''title'',''Cross business''))',c10_test.k(),c10_test.id('a_T-OVEN')),'am_denied');
 -- no claims at all
 PERFORM set_config('request.jwt.claim.sub','',true);
 PERFORM c10_test.denied('SELECT c10_demo.am_list_work_orders_v1(101,''{}'')','am_denied');
 -- direct tables / internal helpers closed even for privileged personas
 PERFORM c10_test.as_user('bo101');
 PERFORM c10_test.denied('SELECT count(*) FROM c10_demo.am_work_orders','permission denied');
 PERFORM c10_test.denied('INSERT INTO c10_demo.am_downtime(tenant_id,business_id,asset_id,site_id,kind,started_at,started_by) VALUES(1,101,1,1001,''other'',now(),c10_demo.actor_uid())','permission denied');
 PERFORM c10_test.denied('SELECT c10_demo.ami_wk_state_ok(NULL,''start'',true)','permission denied');
 PERFORM c10_test.denied('SELECT c10_demo.ami_create_wo(NULL,''xxxxxxxx'',1,''corrective'',''abc'',NULL,NULL,NULL,NULL,NULL,NULL,NULL)','permission denied');
 FOREACH p IN ARRAY ARRAY['owner','bo101','sup','sup1','t1','t2','rep','aud'] LOOP
  PERFORM c10_test.as_user(p); PERFORM c10_test.eq(c10_demo.am_list_work_orders_v1(101,'{}')->>'total','0','empty list for '||p); END LOOP;
END $$; COMMIT;
BEGIN; SET LOCAL ROLE anon;
DO $$ BEGIN
 PERFORM c10_test.denied('SELECT c10_demo.am_list_work_orders_v1(101,''{}'')','permission denied');
 PERFORM c10_test.denied('SELECT c10_demo.am_wo_transition_v1(101,''abcdefgh'',1,1,''approve'')','permission denied');
END $$; COMMIT;

-- ===== S2 create: roles, validation, replay =====
BEGIN; SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb; r2 jsonb; w1 bigint; oven bigint:=c10_test.id('a_T-OVEN'); BEGIN
 PERFORM c10_test.as_user('t1');
 r:=c10_demo.am_create_work_order_v1(101,'wo1-create-0001',jsonb_build_object('asset_id',oven,'kind','corrective','title','Oven fan noisy','checklist_code','T-PM1','priority','medium'));
 w1:=(r->>'id')::bigint; PERFORM c10_test.put('wo1',w1);
 PERFORM c10_test.eq(r->>'status','applied','create applied'); PERFORM c10_test.eq(r->>'wo_status','DRAFT','create draft');
 r2:=c10_demo.am_create_work_order_v1(101,'wo1-create-0001',jsonb_build_object('asset_id',oven,'kind','corrective','title','Oven fan noisy','checklist_code','T-PM1','priority','medium'));
 PERFORM c10_test.eq(r2::text,r::text,'replay returns original receipt');
 PERFORM c10_test.eq(c10_test.val('SELECT count(*) FROM c10_demo.am_work_orders WHERE asset_id='||oven),'1','replay created no duplicate');
 PERFORM c10_test.denied(format('SELECT c10_demo.am_create_work_order_v1(101,''wo1-create-0001'',jsonb_build_object(''asset_id'',%s,''kind'',''corrective'',''title'',''Different''))',oven),'am_idempotency_conflict');
 PERFORM c10_test.as_user('sup1');
 PERFORM c10_test.denied(format('SELECT c10_demo.am_create_work_order_v1(101,''wo1-create-0001'',jsonb_build_object(''asset_id'',%s,''kind'',''corrective'',''title'',''Oven fan noisy'',''checklist_code'',''T-PM1'',''priority'',''medium''))',oven),'am_idempotency_conflict');
 PERFORM c10_test.as_user('t1');
 PERFORM c10_test.eq(c10_test.g(w1)->>'status','DRAFT','get draft'); PERFORM c10_test.eq(jsonb_array_length(c10_test.g(w1)->'checklist')::text,'3','checklist snapshot');
 PERFORM c10_test.eq(c10_test.g(w1)->>'safety_critical','false','oven not safety critical');
 -- validation
 PERFORM c10_test.denied(format('SELECT c10_demo.am_create_work_order_v1(101,%L,jsonb_build_object(''asset_id'',%s,''title'',''abc'',''bogus'',1))',c10_test.k(),oven),'am_invalid_input');
 PERFORM c10_test.denied(format('SELECT c10_demo.am_create_work_order_v1(101,%L,jsonb_build_object(''asset_id'',%s,''kind'',''breakdown'',''title'',''Should use report''))',c10_test.k(),oven),'am_use_breakdown_report');
 PERFORM c10_test.denied(format('SELECT c10_demo.am_create_work_order_v1(101,%L,jsonb_build_object(''asset_id'',%s,''title'',''Bad prio'',''priority'',''urgent''))',c10_test.k(),oven),'am_invalid_input');
 PERFORM c10_test.denied(format('SELECT c10_demo.am_create_work_order_v1(101,%L,jsonb_build_object(''asset_id'',%s,''title'',''ab''))',c10_test.k(),oven),'am_invalid_input');
 PERFORM c10_test.denied(format('SELECT c10_demo.am_create_work_order_v1(101,%L,jsonb_build_object(''asset_id'',''12'',''title'',''String id''))',c10_test.k()),'am_invalid_input');
 PERFORM c10_test.denied(format('SELECT c10_demo.am_create_work_order_v1(101,%L,jsonb_build_object(''asset_id'',%s,''title'',''Bad due'',''due_on'',''2026-13-45''))',c10_test.k(),oven),'am_invalid_input');
 PERFORM c10_test.denied(format('SELECT c10_demo.am_create_work_order_v1(101,%L,jsonb_build_object(''asset_id'',%s,''title'',''Bad code'',''service_category'',''NOPE''))',c10_test.k(),oven),'am_invalid_code');
 PERFORM c10_test.denied(format('SELECT c10_demo.am_create_work_order_v1(101,%L,jsonb_build_object(''asset_id'',%s,''title'',''Bad tpl'',''checklist_code'',''NO-SUCH''))',c10_test.k(),oven),'am_checklist_not_found');
 PERFORM c10_test.denied('SELECT c10_demo.am_create_work_order_v1(101,''short'',''{}'')','am_invalid_request_key');
 PERFORM c10_test.denied(format('SELECT c10_demo.am_create_work_order_v1(101,%L,jsonb_build_object(''asset_id'',%s,''title'',''Overlap same kind''))',c10_test.k(),oven),'am_overlapping_work_order');
 -- scope of creation
 PERFORM c10_test.denied(format('SELECT c10_demo.am_create_work_order_v1(101,%L,jsonb_build_object(''asset_id'',%s,''title'',''Assign other'',''kind'',''inspection'',''assigned_to'',%L))',c10_test.k(),oven,c10_test.u('sup1')),'am_not_permitted');
 PERFORM c10_test.as_user('t2'); PERFORM c10_test.denied(format('SELECT c10_demo.am_create_work_order_v1(101,%L,jsonb_build_object(''asset_id'',%s,''title'',''Wrong site tech''))',c10_test.k(),oven),'am_denied');
 PERFORM c10_test.as_user('aud'); PERFORM c10_test.denied(format('SELECT c10_demo.am_create_work_order_v1(101,%L,jsonb_build_object(''asset_id'',%s,''title'',''Auditor cannot''))',c10_test.k(),oven),'am_not_permitted');
 PERFORM c10_test.as_user('rep');
 PERFORM c10_test.denied(format('SELECT c10_demo.am_create_work_order_v1(101,%L,jsonb_build_object(''asset_id'',%s,''title'',''Reporter prev'',''kind'',''preventive''))',c10_test.k(),oven),'am_not_permitted');
 PERFORM c10_test.denied(format('SELECT c10_demo.am_create_work_order_v1(101,%L,jsonb_build_object(''asset_id'',%s,''title'',''Reporter estimates'',''est_labor_cost'',5))',c10_test.k(),oven),'am_not_permitted');
 PERFORM c10_test.put('wo_rep',c10_test.cr(c10_test.id('a_T-CHILL'),'x') ) ;
END $$; ROLLBACK;
