-- C10-A055 work-orders end-to-end test (disposable PostgreSQL; signed-claim SIMULATION, not GoTrue). Synthetic data only.
-- Load: AM_FILES="core planning workorders lockdown" tests/c10_a055_load.sh <db>   (policy/registry/reports files may be loaded too)
-- Run : psql -X -q -v ON_ERROR_STOP=1 -d <db> -f tests/c10_a055_workorders_e2e.sql   (as superuser; RAISES on any failure)
\set ON_ERROR_STOP on
DROP SCHEMA IF EXISTS c10_test CASCADE;
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
CREATE FUNCTION c10_test.eq(a boolean,b text,msg text) RETURNS void LANGUAGE sql AS $$ SELECT c10_test.eq(a::text,b,msg) $$;
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
 PERFORM c10_test.denied(format('SELECT c10_demo.am_create_work_order_v1(101,%L,jsonb_build_object(''asset_id'',%s,''title'',''Bad tpl'',''kind'',''inspection'',''checklist_code'',''NO-SUCH''))',c10_test.k(),oven),'am_checklist_not_found');
 PERFORM c10_test.denied(format('SELECT c10_demo.am_create_work_order_v1(101,''short'',jsonb_build_object(''asset_id'',%s,''title'',''Valid title'',''kind'',''inspection''))',oven),'am_invalid_request_key');
 PERFORM c10_test.denied(format('SELECT c10_demo.am_create_work_order_v1(101,%L,jsonb_build_object(''asset_id'',%s,''title'',''Overlap same kind''))',c10_test.k(),oven),'am_overlapping_work_order');
 -- scope of creation
 PERFORM c10_test.denied(format('SELECT c10_demo.am_create_work_order_v1(101,%L,jsonb_build_object(''asset_id'',%s,''title'',''Assign other'',''kind'',''inspection'',''assigned_to'',%L))',c10_test.k(),oven,c10_test.u('sup1')),'am_not_permitted');
 PERFORM c10_test.as_user('t2'); PERFORM c10_test.denied(format('SELECT c10_demo.am_create_work_order_v1(101,%L,jsonb_build_object(''asset_id'',%s,''title'',''Wrong site tech''))',c10_test.k(),oven),'am_denied');
 PERFORM c10_test.as_user('aud'); PERFORM c10_test.denied(format('SELECT c10_demo.am_create_work_order_v1(101,%L,jsonb_build_object(''asset_id'',%s,''title'',''Auditor cannot''))',c10_test.k(),oven),'am_not_permitted');
 PERFORM c10_test.as_user('rep');
 PERFORM c10_test.denied(format('SELECT c10_demo.am_create_work_order_v1(101,%L,jsonb_build_object(''asset_id'',%s,''title'',''Reporter prev'',''kind'',''preventive''))',c10_test.k(),oven),'am_not_permitted');
 PERFORM c10_test.denied(format('SELECT c10_demo.am_create_work_order_v1(101,%L,jsonb_build_object(''asset_id'',%s,''title'',''Reporter estimates'',''est_labor_cost'',5))',c10_test.k(),oven),'am_not_permitted');
 PERFORM c10_test.denied(format('SELECT c10_test.cr(%s,''Reporter other site'')',c10_test.id('a_T-CHILL')),'am_denied');
 PERFORM c10_test.put('wo_rep',c10_test.cr(c10_test.id('a_T-ONE'),'Laptop screen flickers'));
 PERFORM c10_test.eq(c10_test.g(c10_test.id('wo_rep'))->>'status','DRAFT','reporter draft');
 PERFORM c10_test.eq(c10_test.g(c10_test.id('wo_rep'))->>'requested_by',c10_test.u('rep')::text,'requester recorded');
END $$; COMMIT;

-- ===== S3 main lifecycle (corrective WO by technician) with maker-checker, checklist, policy gates =====
BEGIN; SET LOCAL ROLE authenticated;
DO $$ DECLARE w1 bigint:=c10_test.id('wo1'); oven bigint:=c10_test.id('a_T-OVEN'); r jsonb; g jsonb; n int; BEGIN
 PERFORM c10_test.as_user('t1');
 r:=c10_test.t(w1,'submit'); PERFORM c10_test.eq(r->>'wo_status','SUBMITTED','submitted (approval required by default)');
 PERFORM c10_test.td(w1,'approve','am_not_permitted');
 PERFORM c10_test.as_user('aud'); PERFORM c10_test.td(w1,'approve','am_not_permitted');
 PERFORM c10_test.as_user('rep'); PERFORM c10_test.td(w1,'approve','am_denied');         -- hidden WO: existence not revealed
 PERFORM c10_test.as_user('t2');  PERFORM c10_test.td(w1,'approve','am_denied');
 PERFORM c10_test.as_user('stock'); PERFORM c10_test.td(w1,'approve','am_denied');
 PERFORM c10_test.as_user('sup1');
 PERFORM c10_test.denied(format('SELECT c10_demo.am_wo_transition_v1(101,%L,%s,%s,''approve'')',c10_test.k(),w1,c10_test.v(w1)-1),'am_stale_version');
 PERFORM c10_test.denied(format('SELECT c10_demo.am_wo_transition_v1(101,%L,%s,%s,''explode'')',c10_test.k(),w1,c10_test.v(w1)),'am_invalid_input');
 PERFORM c10_test.denied(format('SELECT c10_demo.am_wo_transition_v1(101,%L,%s,%s,''return'')',c10_test.k(),w1,c10_test.v(w1)),'am_invalid_input'); -- reason required
 PERFORM c10_test.td(w1,'start','am_wo_illegal_transition');
 PERFORM c10_test.eq(jsonb_array_length(c10_test.g(w1)->'available_actions')>0,'true','sup1 has actions');
 PERFORM c10_test.eq(c10_test.has(c10_test.g(w1)->'available_actions','approve'),'true','approve offered to supervisor');
 PERFORM c10_test.as_user('t1'); PERFORM c10_test.eq(c10_test.has(c10_test.g(w1)->'available_actions','approve'),'false','approve not offered to requester-technician');
 PERFORM c10_test.as_user('sup1');
 r:=c10_test.t(w1,'return','needs more detail'); PERFORM c10_test.eq(r->>'wo_status','DRAFT','returned to draft');
 PERFORM c10_test.as_user('t1'); r:=c10_test.t(w1,'submit'); PERFORM c10_test.as_user('sup1');
 r:=c10_test.t(w1,'approve','ok'); PERFORM c10_test.eq(r->>'wo_status','APPROVED','approved');
 PERFORM c10_test.eq(c10_test.val('SELECT responded_at IS NOT NULL FROM c10_demo.am_work_orders WHERE id='||w1),'true','responded_at set');
 -- assignment authority
 PERFORM c10_test.denied(format('SELECT c10_demo.am_assign_work_order_v1(101,%L,%s,%s,%L,NULL,NULL,''assign'')',c10_test.k(),w1,c10_test.v(w1),c10_test.u('t2')),'am_assignee_not_authorized');
 PERFORM c10_test.denied(format('SELECT c10_demo.am_assign_work_order_v1(101,%L,%s,%s,%L,NULL,NULL,''assign'')',c10_test.k(),w1,c10_test.v(w1),c10_test.u('revt')),'am_assignee_not_authorized');
 PERFORM c10_test.denied(format('SELECT c10_demo.am_assign_work_order_v1(101,%L,%s,%s,%L,NULL,NULL,''assign'')',c10_test.k(),w1,c10_test.v(w1),c10_test.u('stock')),'am_assignee_not_authorized');
 PERFORM c10_test.denied(format('SELECT c10_demo.am_assign_work_order_v1(101,%L,%s,%s,%L,NULL,NULL,''assign'')',c10_test.k(),w1,c10_test.v(w1),c10_test.u('sup2')),'am_assignee_not_authorized');
 PERFORM c10_test.denied(format('SELECT c10_demo.am_assign_work_order_v1(101,%L,%s,%s,%L,''bad ref!'',NULL,''assign'')',c10_test.k(),w1,c10_test.v(w1),c10_test.u('t1')),'am_invalid_input');
 r:=c10_demo.am_assign_work_order_v1(101,c10_test.k(),w1,c10_test.v(w1),c10_test.u('t1'),'EMP-T1','Team-A','assign tech');
 PERFORM c10_test.eq(r->>'assigned_to',c10_test.u('t1')::text,'assigned');
 PERFORM c10_test.as_user('t1');
 PERFORM c10_test.denied(format('SELECT c10_demo.am_assign_work_order_v1(101,%L,%s,%s,%L,NULL,NULL,''self'')',c10_test.k(),w1,c10_test.v(w1),c10_test.u('t1')),'am_not_permitted');
 -- who may start
 PERFORM c10_test.as_user('rep'); PERFORM c10_test.td(w1,'start','am_denied');
 PERFORM c10_test.as_user('t2');  PERFORM c10_test.td(w1,'start','am_denied');
 PERFORM c10_test.as_user('aud'); PERFORM c10_test.td(w1,'start','am_not_permitted');
 PERFORM c10_test.as_user('t1');
 r:=c10_test.t(w1,'start'); PERFORM c10_test.eq(r->>'wo_status','IN_PROGRESS','started');
 g:=c10_test.g(w1); PERFORM c10_test.eq(g->>'started_by',c10_test.u('t1')::text,'started_by'); PERFORM c10_test.eq((g->>'meter_reading_at_start')::numeric::text,'100.000','meter at start');
 PERFORM c10_test.eq(c10_test.ast(oven),'under_maintenance','asset under maintenance');
 PERFORM c10_test.eq(g->>'assignee_authorized','true','assignee authorized');
 -- completion gates
 PERFORM c10_test.td(w1,'complete','am_cause_required');
 PERFORM c10_test.td(w1,'complete','am_checklist_incomplete',NULL,'{"cause_code":"AGE"}');
 PERFORM c10_test.td(w1,'complete','am_invalid_code',NULL,'{"cause_code":"NOPE"}');
 PERFORM c10_test.td(w1,'complete','am_invalid_input',NULL,'{"bogus":1}');
 PERFORM c10_test.td(w1,'complete','am_invalid_input',NULL,'{"cause_code":"AGE","restored_at":"2026-01-01T00:00:00Z"}'); -- restored_at only for breakdown
 PERFORM c10_test.as_user('aud');
 PERFORM c10_test.denied(format('SELECT c10_demo.am_wo_checklist_result_v1(101,%L,%s,1,''pass'',NULL,NULL)',c10_test.k(),w1),'am_not_permitted');
 PERFORM c10_test.as_user('t1');
 PERFORM c10_test.denied(format('SELECT c10_demo.am_wo_checklist_result_v1(101,%L,%s,2,''pass'',25,NULL)',c10_test.k(),w1),'am_measure_out_of_range');
 PERFORM c10_test.denied(format('SELECT c10_demo.am_wo_checklist_result_v1(101,%L,%s,2,''pass'',NULL,NULL)',c10_test.k(),w1),'am_invalid_input');
 PERFORM c10_test.denied(format('SELECT c10_demo.am_wo_checklist_result_v1(101,%L,%s,1,''na'',NULL,NULL)',c10_test.k(),w1),'am_invalid_input');
 PERFORM c10_test.denied(format('SELECT c10_demo.am_wo_checklist_result_v1(101,%L,%s,1,''pass'',5,NULL)',c10_test.k(),w1),'am_invalid_input');
 PERFORM c10_test.denied(format('SELECT c10_demo.am_wo_checklist_result_v1(101,%L,%s,9,''pass'',NULL,NULL)',c10_test.k(),w1),'am_invalid_input');
 PERFORM c10_demo.am_wo_checklist_result_v1(101,c10_test.k(),w1,1,'pass',NULL,NULL);
 PERFORM c10_demo.am_wo_checklist_result_v1(101,c10_test.k(),w1,2,'pass',15,'in range');
 PERFORM c10_demo.am_wo_checklist_result_v1(101,c10_test.k(),w1,3,'na',NULL,NULL);
 PERFORM c10_demo.am_wo_checklist_result_v1(101,c10_test.k(),w1,2,'fail',25,NULL);
 PERFORM c10_test.td(w1,'complete','am_checklist_incomplete',NULL,'{"cause_code":"AGE"}');         -- failed required item without note
 PERFORM c10_demo.am_wo_checklist_result_v1(101,c10_test.k(),w1,2,'fail',25,'pressure too high, escalated');
 PERFORM c10_test.eq(c10_test.g(w1)->'completion_requirements'->>'checklist_pending','0','no pending required items');
 r:=c10_test.t(w1,'complete',NULL,'{"failure_code":"mech","cause_code":"age","action_code":"REPAIR","corrective_action":"Replaced fan belt"}');
 PERFORM c10_test.eq(r->>'wo_status','COMPLETED','completed');
 g:=c10_test.g(w1); PERFORM c10_test.eq(g->>'cause_code','AGE','cause stored'); PERFORM c10_test.eq(g->>'failure_code','MECH','failure stored upper');
 PERFORM c10_test.eq(c10_test.ast(oven),'active','asset restored to active after completion');
 PERFORM c10_test.eq((g->>'meter_reading_at_end')::numeric::text,'100.000','meter at end');
 -- checklist cannot change after completion
 PERFORM c10_test.denied(format('SELECT c10_demo.am_wo_checklist_result_v1(101,%L,%s,1,''fail'',NULL,''x'')',c10_test.k(),w1),'am_wo_not_editable');
 -- verify / close
 PERFORM c10_test.td(w1,'verify','am_not_permitted');
 PERFORM c10_test.as_user('sup1'); PERFORM c10_test.td(w1,'close','am_verification_required');
 r:=c10_test.t(w1,'verify'); PERFORM c10_test.eq(r->>'wo_status','VERIFIED','verified');
 r:=c10_test.t(w1,'close'); PERFORM c10_test.eq(r->>'wo_status','CLOSED','closed');
 PERFORM c10_test.td(w1,'start','am_wo_illegal_transition'); PERFORM c10_test.td(w1,'complete','am_wo_illegal_transition');
 PERFORM c10_test.td(w1,'cancel','am_wo_illegal_transition','no longer needed');
 -- history and audit
 g:=c10_test.g(w1);
 PERFORM c10_test.eq(jsonb_array_length(g->'history')::text,'10','history: create,submit,return,submit,approve,assign,start,complete,verify,close');
 PERFORM c10_test.eq((SELECT string_agg(h->>'action',',' ORDER BY (h->>'id')::bigint) FROM jsonb_array_elements(g->'history') h),'create,submit,return,submit,approve,assign,start,complete,verify,close','history order');
 PERFORM c10_test.eq(c10_test.val('SELECT count(*) FROM c10_demo.am_audit WHERE entity=''work_order'' AND entity_id='''||w1||''' AND event IN (''wo.create'',''wo.submit'',''wo.return'',''wo.approve'',''wo.assign'',''wo.start'',''wo.complete'',''wo.verify'',''wo.close'')'),'10','audit row for every transition');
 PERFORM c10_test.eq(c10_test.val('SELECT count(*) FROM c10_demo.am_audit WHERE entity=''work_order'' AND entity_id='''||w1||''' AND event=''wo.checklist'''),'5','checklist audit rows');
 PERFORM c10_test.eq(c10_test.val('SELECT count(*) FROM c10_demo.am_audit WHERE entity=''asset'' AND entity_id='''||oven||''' AND event=''asset.status_auto'''),'2','asset status changes audited');
 PERFORM c10_test.eq(c10_test.val('SELECT bool_and(actor_uid IS NOT NULL AND row_hash IS NOT NULL) FROM c10_demo.am_audit WHERE entity=''work_order'' AND entity_id='''||w1||''''),'true','audit rows hashed');
END $$; COMMIT;

-- ===== S4 maker-checker (self-approval / self-verification), auto-approval policy =====
BEGIN; SET LOCAL ROLE authenticated;
DO $$ DECLARE one bigint:=c10_test.id('a_T-ONE'); press bigint:=c10_test.id('a_T-PRESS'); pos bigint:=c10_test.id('a_T-POS'); r jsonb; wv bigint; wp bigint; wo2 bigint; wo3 bigint; BEGIN
 PERFORM c10_test.as_user('sup1');
 r:=c10_demo.am_create_work_order_v1(101,c10_test.k(),jsonb_build_object('asset_id',one,'kind','inspection','title','Quarterly inspection','submit',true));
 wv:=(r->>'id')::bigint; PERFORM c10_test.put('wo_vc',wv); PERFORM c10_test.eq(r->>'wo_status','SUBMITTED','create+submit');
 PERFORM c10_test.td(wv,'approve','am_self_approval_denied');
 PERFORM c10_test.eq(c10_test.has(c10_test.g(wv)->'available_actions','approve'),'false','self approval not offered');
 PERFORM c10_test.as_user('sup'); r:=c10_test.t(wv,'approve'); PERFORM c10_test.eq(r->>'wo_status','APPROVED','other supervisor approves');
 PERFORM c10_test.as_user('sup1'); r:=c10_test.t(wv,'start'); PERFORM c10_test.eq(c10_test.g(wv)->>'assigned_to',NULL,'supervisor start does not claim');
 r:=c10_test.t(wv,'complete'); PERFORM c10_test.eq(r->>'wo_status','COMPLETED','inspection completes without cause code');
 PERFORM c10_test.td(wv,'verify','am_self_verification_denied');
 PERFORM c10_test.eq(c10_test.has(c10_test.g(wv)->'available_actions','verify'),'false','self verification not offered');
 PERFORM c10_test.as_user('sup'); PERFORM c10_test.eq(c10_test.has(c10_test.g(wv)->'available_actions','verify'),'true','verify offered to other supervisor');
 r:=c10_test.t(wv,'verify'); r:=c10_test.t(wv,'close'); PERFORM c10_test.eq(c10_test.wst(wv),'CLOSED','verified by someone else then closed');
 -- owners get no exception: business owner and tenant owner cannot approve their own requests
 PERFORM c10_test.as_user('bo101');
 r:=c10_demo.am_create_work_order_v1(101,c10_test.k(),jsonb_build_object('asset_id',press,'kind','preventive','title','Press lubrication','submit',true,'priority','low'));
 wp:=(r->>'id')::bigint; PERFORM c10_test.put('wo_prev',wp);
 PERFORM c10_test.td(wp,'approve','am_self_approval_denied');
 PERFORM c10_test.as_user('owner');
 r:=c10_demo.am_create_work_order_v1(101,c10_test.k(),jsonb_build_object('asset_id',press,'kind','corrective','title','Press guard loose','submit',true));
 wo2:=(r->>'id')::bigint; PERFORM c10_test.td(wo2,'approve','am_self_approval_denied');
 PERFORM c10_test.as_user('bo101'); r:=c10_test.t(wo2,'approve'); PERFORM c10_test.eq(r->>'wo_status','APPROVED','business owner may approve tenant owner request');
 PERFORM c10_test.as_user('owner'); r:=c10_test.t(wp,'approve'); PERFORM c10_test.eq(r->>'wo_status','APPROVED','tenant owner approves bo request');
 r:=c10_test.t(wo2,'cancel','duplicate of other work'); PERFORM c10_test.eq(r->>'wo_status','CANCELLED','owner cancels own');
 -- policy off: self approval allowed
 PERFORM c10_test.sd('SELECT c10_test.pol(''wo.maker_checker'',''false''::jsonb)');
 PERFORM c10_test.as_user('sup1');
 r:=c10_demo.am_create_work_order_v1(101,c10_test.k(),jsonb_build_object('asset_id',press,'kind','inspection','title','Self approved by policy','submit',true));
 wo3:=(r->>'id')::bigint; r:=c10_test.t(wo3,'approve'); PERFORM c10_test.eq(r->>'wo_status','APPROVED','self approval allowed when policy off');
 PERFORM c10_test.sd('SELECT c10_test.unpol(''wo.maker_checker'')');
 PERFORM c10_test.td(wo3,'cancel','am_invalid_input'); -- cancel needs a reason
 r:=c10_test.t(wo3,'cancel','test cleanup');
 -- approval policy: priority / cost thresholds auto-approve inside the same transaction
 PERFORM c10_test.sd('SELECT c10_test.pol(''wo.approval_min_priority'',''"high"''::jsonb)');
 PERFORM c10_test.as_user('t1');
 r:=c10_demo.am_create_work_order_v1(101,c10_test.k(),jsonb_build_object('asset_id',pos,'kind','inspection','title','POS routine check','submit',true));
 PERFORM c10_test.eq(r->>'wo_status','APPROVED','medium priority auto-approved'); PERFORM c10_test.eq(r->>'auto_approved','true','flag');
 PERFORM c10_test.eq(c10_test.g((r->>'id')::bigint)->>'auto_approved','true','read flag'); PERFORM c10_test.eq(c10_test.g((r->>'id')::bigint)->>'approved_by',NULL,'no human approver');
 r:=c10_demo.am_create_work_order_v1(101,c10_test.k(),jsonb_build_object('asset_id',pos,'kind','preventive','title','POS high prio','priority','high','submit',true));
 PERFORM c10_test.eq(r->>'wo_status','SUBMITTED','high priority needs approval');
 PERFORM c10_test.sd('SELECT c10_test.pol(''wo.approval_cost_threshold'',''500''::jsonb)');
 r:=c10_demo.am_create_work_order_v1(101,c10_test.k(),jsonb_build_object('asset_id',pos,'kind','corrective','title','POS costly','est_labor_cost',400,'est_spares_cost',200,'submit',true));
 PERFORM c10_test.eq(r->>'wo_status','SUBMITTED','cost above threshold needs approval');
 PERFORM c10_test.put('wo_pos_costly',(r->>'id')::bigint);
 PERFORM c10_test.sd('SELECT c10_test.pol(''wo.approval_min_priority'',''"never"''::jsonb)'); PERFORM c10_test.sd('SELECT c10_test.unpol(''wo.approval_cost_threshold'')');
 PERFORM c10_test.td(c10_test.id('wo_pos_costly'),'cancel','am_invalid_input');
 PERFORM c10_test.as_user('sup1'); r:=c10_test.t(c10_test.id('wo_pos_costly'),'cancel','cleanup');
 PERFORM c10_test.as_user('t1');
 r:=c10_demo.am_create_work_order_v1(101,c10_test.k(),jsonb_build_object('asset_id',pos,'kind','corrective','title','POS never approval','priority','critical','submit',true));
 PERFORM c10_test.eq(r->>'wo_status','APPROVED','never => approval disabled'); PERFORM c10_test.sd('SELECT c10_test.pol(''wo.approval_min_priority'',''"low"''::jsonb)');
 PERFORM c10_test.sd('SELECT c10_test.unpol(''wo.approval_min_priority'')');
END $$; COMMIT;

-- ===== S5 update / execution records (labour, spares, attachments, evidence & labour policy) =====
BEGIN; SET LOCAL ROLE authenticated;
DO $$ DECLARE wp bigint:=c10_test.id('wo_prev'); r jsonb; g jsonb; sla0 text; n int; BEGIN
 PERFORM c10_test.as_user('bo101'); g:=c10_test.g(wp); sla0:=g->>'sla_resolve_due_at';
 PERFORM c10_test.denied(format('SELECT c10_demo.am_update_work_order_v1(101,%L,%s,%s,''{"title":"New title here"}'',NULL)',c10_test.k(),wp,c10_test.v(wp)),'am_invalid_input'); -- reason required
 PERFORM c10_test.denied(format('SELECT c10_demo.am_update_work_order_v1(101,%L,%s,%s,''{"bogus":1}'',''reason ok'')',c10_test.k(),wp,c10_test.v(wp)),'am_invalid_input');
 PERFORM c10_test.denied(format('SELECT c10_demo.am_update_work_order_v1(101,%L,%s,%s,''{}'',''reason ok'')',c10_test.k(),wp,c10_test.v(wp)),'am_invalid_input');
 PERFORM c10_test.denied(format('SELECT c10_demo.am_update_work_order_v1(101,%L,%s,%s,''{"status":"CLOSED"}'',''reason ok'')',c10_test.k(),wp,c10_test.v(wp)),'am_invalid_input'); -- status is not editable
 PERFORM c10_test.denied(format('SELECT c10_demo.am_update_work_order_v1(101,%L,%s,%s,''{"title":"New title here"}'',''reason ok'')',c10_test.k(),wp,c10_test.v(wp)-1),'am_stale_version');
 PERFORM c10_test.denied(format('SELECT c10_demo.am_update_work_order_v1(101,%L,%s,%s,''{"actual_labor_hours":2}'',''reason ok'')',c10_test.k(),wp,c10_test.v(wp)),'am_wo_not_editable');
 PERFORM c10_test.denied(format('SELECT c10_demo.am_update_work_order_v1(101,%L,%s,%s,''{"est_labor_cost":-5}'',''reason ok'')',c10_test.k(),wp,c10_test.v(wp)),'am_invalid_input');
 PERFORM c10_test.denied(format('SELECT c10_demo.am_update_work_order_v1(101,%L,%s,%s,''{"title":123}'',''reason ok'')',c10_test.k(),wp,c10_test.v(wp)),'am_invalid_input');
 r:=c10_demo.am_update_work_order_v1(101,c10_test.k(),wp,c10_test.v(wp),'{"title":"Press lubrication (updated)","priority":"critical","est_labor_cost":50,"due_on":"2030-01-31"}','tighten priority');
 g:=c10_test.g(wp); PERFORM c10_test.eq(g->>'title','Press lubrication (updated)','title updated'); PERFORM c10_test.eq(g->>'priority','critical','priority updated');
 PERFORM c10_test.eq((g->>'sla_resolve_due_at'<>sla0)::text,'true','SLA recomputed on priority change'); PERFORM c10_test.eq(g->>'due_on','2030-01-31','due');
 PERFORM c10_test.as_user('rep'); PERFORM c10_test.denied(format('SELECT c10_demo.am_update_work_order_v1(101,%L,%s,%s,''{"title":"Rep edit here"}'',''reason ok'')',c10_test.k(),wp,c10_test.v(wp)),'am_denied');
 PERFORM c10_test.as_user('t1'); PERFORM c10_test.denied(format('SELECT c10_demo.am_update_work_order_v1(101,%L,%s,%s,''{"title":"Tech edit here"}'',''reason ok'')',c10_test.k(),wp,c10_test.v(wp)),'am_not_permitted');
 PERFORM c10_test.denied(format('SELECT c10_demo.am_update_work_order_v1(101,%L,%s,%s,''{"est_labor_cost":1}'',''reason ok'')',c10_test.k(),wp,c10_test.v(wp)),'am_not_permitted'); -- unassigned
 -- records before start
 PERFORM c10_test.as_user('sup1');
 PERFORM c10_test.denied(format('SELECT c10_demo.am_wo_add_labor_v1(101,%L,%s,''{"hours":1,"phase":"actual"}'')',c10_test.k(),wp),'am_wo_not_editable');
 PERFORM c10_demo.am_wo_add_labor_v1(101,c10_test.k(),wp,'{"hours":2,"rate":25,"phase":"estimate","worker_ref":"EMP-T1"}');
 PERFORM c10_demo.am_wo_add_spares_v1(101,c10_test.k(),wp,'{"description":"Grease cartridge","qty":3,"unit_cost":4.5,"item_ref":"GRS-1"}');
 PERFORM c10_test.denied(format('SELECT c10_demo.am_wo_add_spares_v1(101,%L,%s,''{"description":"Bad","qty":1,"stock_effect":true}'')',c10_test.k(),wp),'am_invalid_input');
 r:=c10_demo.am_assign_work_order_v1(101,c10_test.k(),wp,c10_test.v(wp),c10_test.u('t1'),NULL,NULL,'assign tech');
 PERFORM c10_test.as_user('t1'); r:=c10_test.t(wp,'start'); PERFORM c10_test.eq(r->>'wo_status','IN_PROGRESS','tech starts assigned WO');
 PERFORM c10_test.eq(c10_test.ast(c10_test.id('a_T-PRESS')),'under_maintenance','asset under maintenance');
 -- strict input on records
 PERFORM c10_test.denied(format('SELECT c10_demo.am_wo_add_labor_v1(101,%L,%s,''{"hours":0,"phase":"actual"}'')',c10_test.k(),wp),'am_invalid_input');
 PERFORM c10_test.denied(format('SELECT c10_demo.am_wo_add_labor_v1(101,%L,%s,''{"hours":1.555}'')',c10_test.k(),wp),'am_invalid_input');
 PERFORM c10_test.denied(format('SELECT c10_demo.am_wo_add_labor_v1(101,%L,%s,''{"hours":"2"}'')',c10_test.k(),wp),'am_invalid_input');
 PERFORM c10_test.denied(format('SELECT c10_demo.am_wo_add_labor_v1(101,%L,%s,''{"hours":1,"worker_ref":"bad ref;drop"}'')',c10_test.k(),wp),'am_invalid_input');
 PERFORM c10_test.denied(format('SELECT c10_demo.am_wo_add_labor_v1(101,%L,%s,''{"hours":1,"extra":1}'')',c10_test.k(),wp),'am_invalid_input');
 PERFORM c10_test.as_user('aud'); PERFORM c10_test.denied(format('SELECT c10_demo.am_wo_add_labor_v1(101,%L,%s,''{"hours":1}'')',c10_test.k(),wp),'am_not_permitted');
 PERFORM c10_test.denied(format('SELECT c10_demo.am_wo_add_attachment_v1(101,%L,%s,''{}'')',c10_test.k(),wp),'am_invalid_input');
 PERFORM c10_test.as_user('t1');
 -- policy: evidence for every WO + actual labour required
 PERFORM c10_test.sd('SELECT c10_test.pol(''wo.evidence_required_for'',''"all"''::jsonb)'); PERFORM c10_test.sd('SELECT c10_test.pol(''wo.require_actual_labor'',''true''::jsonb)');
 PERFORM c10_test.eq(c10_test.g(wp)->'completion_requirements'->>'evidence_required','true','requirement exposed');
 PERFORM c10_test.td(wp,'complete','am_evidence_required');
 -- attachments: metadata only, hostile refs rejected
 PERFORM c10_test.denied(format('SELECT c10_demo.am_wo_add_attachment_v1(101,%L,%s,%L::jsonb)',c10_test.k(),wp,jsonb_build_object('file_name','a.jpg','mime','image/jpeg','size_bytes',10,'sha256',repeat('a',64),'storage_ref','../../etc/passwd')),'am_invalid_input');
 PERFORM c10_test.denied(format('SELECT c10_demo.am_wo_add_attachment_v1(101,%L,%s,%L::jsonb)',c10_test.k(),wp,jsonb_build_object('file_name','a.jpg','mime','image/jpeg','size_bytes',10,'sha256',repeat('a',64),'storage_ref','a/../b.jpg')),'am_invalid_input');
 PERFORM c10_test.denied(format('SELECT c10_demo.am_wo_add_attachment_v1(101,%L,%s,%L::jsonb)',c10_test.k(),wp,jsonb_build_object('file_name','a.jpg','mime','image/jpeg','size_bytes',10,'sha256',repeat('a',64),'storage_ref','https://evil.example/x.jpg')),'am_invalid_input');
 PERFORM c10_test.denied(format('SELECT c10_demo.am_wo_add_attachment_v1(101,%L,%s,%L::jsonb)',c10_test.k(),wp,jsonb_build_object('file_name','a.jpg','mime','image/jpeg','size_bytes',10,'sha256',repeat('a',64),'storage_ref','/abs/path.jpg')),'am_invalid_input');
 PERFORM c10_test.denied(format('SELECT c10_demo.am_wo_add_attachment_v1(101,%L,%s,%L::jsonb)',c10_test.k(),wp,jsonb_build_object('file_name','../a.jpg','mime','image/jpeg','size_bytes',10,'sha256',repeat('a',64),'storage_ref','ok/a.jpg')),'am_invalid_input');
 PERFORM c10_test.denied(format('SELECT c10_demo.am_wo_add_attachment_v1(101,%L,%s,%L::jsonb)',c10_test.k(),wp,jsonb_build_object('file_name','a.exe','mime','application/x-msdownload','size_bytes',10,'sha256',repeat('a',64),'storage_ref','ok/a.exe')),'am_invalid_input');
 PERFORM c10_test.denied(format('SELECT c10_demo.am_wo_add_attachment_v1(101,%L,%s,%L::jsonb)',c10_test.k(),wp,jsonb_build_object('file_name','a.jpg','mime','image/jpeg','size_bytes',99999999999,'sha256',repeat('a',64),'storage_ref','ok/a.jpg')),'am_invalid_input');
 PERFORM c10_test.denied(format('SELECT c10_demo.am_wo_add_attachment_v1(101,%L,%s,%L::jsonb)',c10_test.k(),wp,jsonb_build_object('file_name','a.jpg','mime','image/jpeg','size_bytes',10,'sha256','XYZ','storage_ref','ok/a.jpg')),'am_invalid_input');
 r:=c10_demo.am_wo_add_attachment_v1(101,c10_test.k(),wp,jsonb_build_object('file_name','press after.jpg','mime','image/jpeg','size_bytes',2048,'sha256',repeat('b',64),'storage_ref','wo/press/after-1.jpg','kind','photo','caption','after repair'));
 PERFORM c10_test.denied(format('SELECT c10_demo.am_wo_add_attachment_v1(101,%L,%s,%L::jsonb)',c10_test.k(),wp,jsonb_build_object('file_name','copy.jpg','mime','image/jpeg','size_bytes',2048,'sha256',repeat('b',64),'storage_ref','wo/press/copy.jpg')),'am_duplicate_attachment');
 PERFORM c10_test.td(wp,'complete','am_labor_required');
 PERFORM c10_demo.am_wo_add_labor_v1(101,c10_test.k(),wp,'{"hours":1.5,"rate":20,"phase":"actual","worker_ref":"EMP-T1"}');
 PERFORM c10_demo.am_wo_add_labor_v1(101,c10_test.k(),wp,'{"hours":1,"rate":0,"labor_kind":"contractor","note":"vendor help"}');
 PERFORM c10_demo.am_wo_add_spares_v1(101,c10_test.k(),wp,'{"description":"Grease used","qty":2,"unit_cost":10.5,"phase":"actual"}');
 r:=c10_test.t(wp,'complete'); PERFORM c10_test.eq(r->>'wo_status','COMPLETED','completes with evidence+labour');
 g:=c10_test.g(wp);
 PERFORM c10_test.eq((g->>'actual_labor_hours')::numeric::text,'2.50','labour hours aggregated'); PERFORM c10_test.eq((g->>'actual_labor_cost')::numeric::text,'30.00','labour cost aggregated');
 PERFORM c10_test.eq((g->>'actual_spares_cost')::numeric::text,'21.00','spares cost aggregated');
 PERFORM c10_test.eq(c10_test.val('SELECT bool_and(NOT stock_effect) FROM c10_demo.am_wo_spares WHERE work_order_id='||wp),'true','spares never move stock');
 PERFORM c10_test.eq(jsonb_array_length(g->'labor')::text,'3','labour lines'); PERFORM c10_test.eq(jsonb_array_length(g->'spares')::text,'2','spares lines'); PERFORM c10_test.eq(jsonb_array_length(g->'attachments')::text,'1','attachments');
 PERFORM c10_test.sd('SELECT c10_test.unpol(''wo.evidence_required_for'')'); PERFORM c10_test.sd('SELECT c10_test.unpol(''wo.require_actual_labor'')');
 -- attachments still allowed until verified, not after close
 PERFORM c10_demo.am_wo_add_attachment_v1(101,c10_test.k(),wp,jsonb_build_object('file_name','report.pdf','mime','application/pdf','size_bytes',500,'sha256',repeat('c',64),'storage_ref','wo/press/report.pdf','kind','report'));
 PERFORM c10_test.as_user('sup'); r:=c10_test.t(wp,'verify'); r:=c10_test.t(wp,'close');
 PERFORM c10_test.as_user('t1');
 PERFORM c10_test.denied(format('SELECT c10_demo.am_wo_add_attachment_v1(101,%L,%s,%L::jsonb)',c10_test.k(),wp,jsonb_build_object('file_name','late.pdf','mime','application/pdf','size_bytes',500,'sha256',repeat('d',64),'storage_ref','wo/press/late.pdf')),'am_wo_not_editable');
 PERFORM c10_test.eq(c10_test.ast(c10_test.id('a_T-PRESS')),'active','asset active after completion');
END $$; COMMIT;
