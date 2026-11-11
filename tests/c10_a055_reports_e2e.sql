-- C10-A055 reports e2e. Disposable PostgreSQL only. Loader: AM_FILES="core reports lockdown" tests/c10_a055_load.sh <db>
-- Seeds fixtures with superuser INSERTs (no other file's RPCs), then exercises every reports RPC as signed-claim personas.
-- Runs in ONE transaction and rolls back at the end (re-runnable). Ends with NOTICE A055_REPORTS_E2E_PASS.
\set ON_ERROR_STOP on
BEGIN;
CREATE SCHEMA c10_test;
GRANT USAGE ON SCHEMA c10_test TO authenticated,anon;
CREATE TABLE c10_test.ids(k text PRIMARY KEY,id bigint NOT NULL);
CREATE FUNCTION c10_test.u(p text) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT (CASE p
 WHEN 'owner' THEN '11111111-1111-4111-8111-111111111111' WHEN 'bo101' THEN '22222222-2222-4222-8222-222222222222'
 WHEN 'mgr' THEN '33333333-3333-4333-8333-333333333333' WHEN 'stock' THEN '44444444-4444-4444-8444-444444444444'
 WHEN 'investor' THEN '55555555-5555-4555-8555-555555555555' WHEN 'revoked' THEN '66666666-6666-4666-8666-666666666666'
 WHEN 'owner2' THEN '77777777-7777-4777-8777-777777777777' WHEN 'staff2' THEN '88888888-8888-4888-8888-888888888888'
 WHEN 'operator' THEN '99999999-9999-4999-8999-999999999999' WHEN 'sup' THEN 'd1111111-1111-4111-8111-111111111111'
 WHEN 'sup1001' THEN 'd2222222-2222-4222-8222-222222222222' WHEN 'tech1001' THEN 'd3333333-3333-4333-8333-333333333333'
 WHEN 'tech1002' THEN 'd4444444-4444-4444-8444-444444444444' WHEN 'reporter' THEN 'd5555555-5555-4555-8555-555555555555'
 WHEN 'auditor' THEN 'd6666666-6666-4666-8666-666666666666' WHEN 'revtech' THEN 'd7777777-7777-4777-8777-777777777777'
 WHEN 'sup201' THEN 'd8888888-8888-4888-8888-888888888888' WHEN 'bo102' THEN 'e1111111-1111-4111-8111-111111111111' END)::uuid $$;
CREATE FUNCTION c10_test.as_user(p text) RETURNS void LANGUAGE sql AS $$ SELECT set_config('request.jwt.claim.sub',c10_test.u(p)::text,true); SELECT 1 $$;
CREATE FUNCTION c10_test.chk(p boolean,msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p IS NOT TRUE THEN RAISE EXCEPTION 'ASSERT FAILED: %',msg; END IF; END$$;
CREATE FUNCTION c10_test.eq(a text,b text,msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF a IS DISTINCT FROM b THEN RAISE EXCEPTION 'ASSERT % : got [%] want [%]',msg,a,b; END IF; END$$;
CREATE FUNCTION c10_test.eqn(a text,b numeric,msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF a IS NULL OR a::numeric IS DISTINCT FROM b THEN RAISE EXCEPTION 'ASSERT % : got [%] want [%]',msg,a,b; END IF; END$$;
CREATE FUNCTION c10_test.denied(p_sql text,p_expect text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 BEGIN EXECUTE p_sql; EXCEPTION WHEN OTHERS THEN
  IF SQLERRM NOT LIKE p_expect||'%' THEN RAISE EXCEPTION 'WRONG_ERROR [%] for %: want %',SQLERRM,p_sql,p_expect; END IF; RETURN; END;
 RAISE EXCEPTION 'EXPECTED_DENIAL_DID_NOT_HAPPEN: %',p_sql;
END$$;
CREATE FUNCTION c10_test.t0() RETURNS timestamptz LANGUAGE sql STABLE AS $$ SELECT date_trunc('day',now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC' $$;
CREATE FUNCTION c10_test.today() RETURNS date LANGUAGE sql STABLE AS $$ SELECT (now() AT TIME ZONE 'UTC')::date $$;
CREATE FUNCTION c10_test.ts(k int,h numeric DEFAULT 0) RETURNS text LANGUAGE sql STABLE AS $$ SELECT (c10_test.t0()-k*interval '1 day'+h*interval '1 hour')::text $$;
CREATE FUNCTION c10_test.dt(k int) RETURNS text LANGUAGE sql STABLE AS $$ SELECT (c10_test.today()-k)::text $$;
CREATE FUNCTION c10_test.k(p text) RETURNS bigint LANGUAGE sql STABLE SECURITY DEFINER AS $$ SELECT id FROM c10_test.ids WHERE k=p $$;
CREATE FUNCTION c10_test.catid(b bigint,p text) RETURNS bigint LANGUAGE sql STABLE SECURITY DEFINER AS $$ SELECT id FROM c10_demo.am_categories WHERE business_id=b AND code=p $$;
CREATE FUNCTION c10_test.tid(b bigint) RETURNS bigint LANGUAGE sql STABLE AS $$ SELECT tenant_id FROM c10_demo.businesses WHERE id=b $$;
-- generic typed insert from jsonb (test fixtures only)
CREATE FUNCTION c10_test.ins(p_tbl text,p_j jsonb) RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE cols text; v bigint;
BEGIN
 SELECT string_agg(quote_ident(x),',') INTO cols FROM jsonb_object_keys(p_j) x;
 EXECUTE format('INSERT INTO c10_demo.%I(%s) SELECT %s FROM jsonb_populate_record(NULL::c10_demo.%I,$1) RETURNING id',p_tbl,cols,cols,p_tbl) INTO v USING p_j;
 RETURN v;
END$$;
CREATE FUNCTION c10_test.asset(b bigint,p_no text,p_name text,p_cat text,p_site bigint,p_status text,p_crit int,p_cost numeric DEFAULT NULL,
 p_comm int DEFAULT 400,p_parent text DEFAULT NULL) RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE v bigint;
BEGIN
 v:=c10_test.ins('am_assets',jsonb_build_object('tenant_id',c10_test.tid(b),'business_id',b,'asset_no',p_no,'name',p_name,
   'category_id',c10_test.catid(b,p_cat),'status',p_status,'criticality',p_crit,'site_id',p_site,'acquisition_cost',p_cost,
   'commission_date',c10_test.dt(p_comm),'created_at',c10_test.ts(p_comm),'created_by',c10_test.u('bo101'),
   'parent_asset_id',CASE WHEN p_parent IS NULL THEN NULL ELSE c10_test.k(p_parent) END,
   'retired_at',CASE WHEN p_status='retired' THEN c10_test.ts(5) END));
 INSERT INTO c10_test.ids VALUES(p_no,v); RETURN v;
END$$;
CREATE FUNCTION c10_test.wo(p_no text,p_kind text,p_status text,p_asset text,p_site bigint,p_extra jsonb DEFAULT '{}') RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE v bigint; b bigint;
BEGIN
 SELECT business_id INTO b FROM c10_demo.am_assets WHERE id=c10_test.k(p_asset);
 v:=c10_test.ins('am_work_orders',jsonb_build_object('tenant_id',c10_test.tid(b),'business_id',b,'wo_no',p_no,'kind',p_kind,'status',p_status,
   'asset_id',c10_test.k(p_asset),'site_id',p_site,'title','Task '||p_no,'requested_by',c10_test.u('bo101'))||p_extra);
 INSERT INTO c10_test.ids VALUES(p_no,v); RETURN v;
END$$;
CREATE FUNCTION c10_test.dtw(p_asset text,p_site bigint,p_kind text,p_start text,p_end text,p_wo text DEFAULT NULL,p_key text DEFAULT NULL) RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE v bigint; b bigint;
BEGIN
 SELECT business_id INTO b FROM c10_demo.am_assets WHERE id=c10_test.k(p_asset);
 v:=c10_test.ins('am_downtime',jsonb_build_object('tenant_id',c10_test.tid(b),'business_id',b,'asset_id',c10_test.k(p_asset),'site_id',p_site,
   'kind',p_kind,'started_at',p_start,'ended_at',p_end,'started_by',c10_test.u('bo101'),
   'work_order_id',CASE WHEN p_wo IS NULL THEN NULL ELSE c10_test.k(p_wo) END));
 IF p_key IS NOT NULL THEN INSERT INTO c10_test.ids VALUES(p_key,v); END IF; RETURN v;
END$$;
CREATE FUNCTION c10_test.plan(p_key text,p_asset text,p_name text,p_freq text,p_active boolean,p_next date,p_extra jsonb DEFAULT '{}',p_tgt jsonb DEFAULT '{}') RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE pl bigint; tg bigint; b bigint;
BEGIN
 SELECT business_id INTO b FROM c10_demo.am_assets WHERE id=c10_test.k(p_asset);
 pl:=c10_test.ins('am_plans',jsonb_build_object('tenant_id',c10_test.tid(b),'business_id',b,'name',p_name,'plan_type','preventive','asset_id',c10_test.k(p_asset),
   'frequency_kind',p_freq,'start_on',c10_test.dt(400),'active',p_active,'created_by',c10_test.u('bo101'))||p_extra);
 tg:=c10_test.ins('am_plan_targets',jsonb_build_object('tenant_id',c10_test.tid(b),'business_id',b,'plan_id',pl,'asset_id',c10_test.k(p_asset),
   'next_due_on',p_next)||p_tgt);
 INSERT INTO c10_test.ids VALUES(p_key,tg); RETURN tg;
END$$;
CREATE FUNCTION c10_test.csv_rows(p text) RETURNS SETOF text[] LANGUAGE plpgsql AS $$
DECLARE i int:=1; n int:=length(p); ch text; cell text:=''; rw text[]:='{}'; inq boolean:=false;
BEGIN
 WHILE i<=n LOOP
  ch:=substr(p,i,1);
  IF inq THEN
   IF ch='"' THEN IF substr(p,i+1,1)='"' THEN cell:=cell||'"'; i:=i+1; ELSE inq:=false; END IF; ELSE cell:=cell||ch; END IF;
  ELSIF ch='"' THEN inq:=true;
  ELSIF ch=',' THEN rw:=rw||cell; cell:='';
  ELSIF ch=E'\r' THEN NULL;
  ELSIF ch=E'\n' THEN rw:=rw||cell; RETURN NEXT rw; rw:='{}'; cell:='';
  ELSE cell:=cell||ch; END IF;
  i:=i+1;
 END LOOP;
 IF cell<>'' OR cardinality(rw)>0 THEN rw:=rw||cell; RETURN NEXT rw; END IF;
END$$;
CREATE FUNCTION c10_test.cell(p_csv text,p_key text,p_col int) RETURNS text LANGUAGE sql AS $$ SELECT r[p_col] FROM c10_test.csv_rows(p_csv) r WHERE r[1]=p_key $$;
CREATE FUNCTION c10_test.nrows(p_csv text) RETURNS int LANGUAGE sql AS $$ SELECT count(*)::int-1 FROM c10_test.csv_rows(p_csv) $$;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA c10_test TO authenticated,anon;

-- ===================================================== S0 fixtures (superuser) =====================================================
SELECT set_config('request.jwt.claim.sub',c10_test.u('bo101')::text,true);
INSERT INTO c10_demo.am_policy(business_id,tenant_id,scope_type,scope_id,key,value,updated_by) VALUES
 (101,1,'business',0,'general.timezone','"UTC"',c10_test.u('bo101')),(102,1,'business',0,'general.timezone','"UTC"',c10_test.u('bo101')),
 (201,2,'business',0,'general.timezone','"UTC"',c10_test.u('owner2'));
SELECT c10_demo.ami_ensure_business(101); SELECT c10_demo.ami_ensure_business(102);
-- tenant 2 / business 201 intentionally NOT bootstrapped (reads must work and must not create settings)
INSERT INTO c10_demo.am_categories(tenant_id,business_id,code,name) VALUES (2,201,'T2-CAT','Tenant two category');
SELECT c10_test.asset(101,'CHL-1','Chiller 1','COLD',1001,'active',5,100000);
SELECT c10_test.asset(101,'OVN-1','Oven 1','PROD-EQ',1001,'breakdown',4);
SELECT c10_test.asset(101,'POS-1','POS terminal 1','POS',1001,'active',2,4800,10);
SELECT c10_test.asset(101,'MIX-1','Paint mixer 1','PROD-EQ',1001,'breakdown',3);
SELECT c10_test.asset(101,'GEN-X','Generator X','GENERAL',1001,'active',3);
SELECT c10_test.asset(101,'CNV-1','Conveyor 1','PROD-EQ',1002,'active',3);
SELECT c10_test.asset(101,'CRN-1','Crane 1','LIFT',1002,'active',5);
SELECT c10_test.asset(101,'CNV-1M','Conveyor motor','GENERAL',1005,'active',2,NULL,400,'CNV-1');
SELECT c10_test.asset(101,'PRJ-1','Project tool','GENERAL',1004,'retired',3);
SELECT c10_test.asset(101,'OLD-1','Old plant','GENERAL',1004,'breakdown',3);
-- meters
SELECT c10_test.ins('am_meters',jsonb_build_object('tenant_id',1,'business_id',101,'asset_id',c10_test.k('CHL-1'),'code','HRS','unit','hours','current_reading',30,'last_reading_at',c10_test.ts(2)));
INSERT INTO c10_test.ids SELECT 'M-CHL',max(id) FROM c10_demo.am_meters;
SELECT c10_test.ins('am_meters',jsonb_build_object('tenant_id',1,'business_id',101,'asset_id',c10_test.k('CRN-1'),'code','HRS','unit','hours','current_reading',500,'last_reading_at',c10_test.ts(60)));
SELECT c10_test.ins('am_meter_readings',jsonb_build_object('tenant_id',1,'business_id',101,'meter_id',c10_test.k('M-CHL'),'asset_id',c10_test.k('CHL-1'),
  'reading',v.r,'kind',v.kd,'read_at',c10_test.ts(v.d),'recorded_by',c10_test.u('bo101'),'request_key','seed-read-'||v.d))
 FROM (VALUES(100,'reading',30),(200,'reading',20),(150,'reading',10),(20,'reset',5),(30,'reading',2)) v(r,kd,d);
-- completed breakdown WOs (period P = [today-20, today-1])
SELECT c10_test.wo('BD1','breakdown','COMPLETED','CRN-1',1002,jsonb_build_object('requested_at',c10_test.ts(15),'started_at',c10_test.ts(15,0.5),'completed_at',c10_test.ts(15,2.5),
  'failure_code','MECH','priority','high','sla_resolve_due_at',c10_test.ts(15,8),'est_labor_cost',500,'est_spares_cost',200,'actual_labor_cost',600,'actual_spares_cost',300));
SELECT c10_test.wo('BD2','breakdown','COMPLETED','CRN-1',1002,jsonb_build_object('requested_at',c10_test.ts(12),'started_at',c10_test.ts(12,1),'completed_at',c10_test.ts(12,4.5),
  'failure_code','MECH','priority','high','sla_resolve_due_at',c10_test.ts(12,2),'est_labor_cost',400,'est_spares_cost',0,'actual_labor_cost',450,'actual_spares_cost',100));
SELECT c10_test.wo('BD3','breakdown','COMPLETED','CRN-1',1002,jsonb_build_object('requested_at',c10_test.ts(9),'started_at',c10_test.ts(9,1),'completed_at',c10_test.ts(9,6.5),
  'failure_code','MECH','priority','high','sla_resolve_due_at',c10_test.ts(9,10)));
SELECT c10_test.wo('BD4','breakdown','COMPLETED','CRN-1',1002,jsonb_build_object('requested_at',c10_test.ts(6),'started_at',c10_test.ts(6,1),'completed_at',c10_test.ts(6,4),'failure_code','ELEC'));
SELECT c10_test.wo('BD5','breakdown','COMPLETED','CHL-1',1001,jsonb_build_object('requested_at',c10_test.ts(8),'started_at',c10_test.ts(8,0.5),'completed_at',c10_test.ts(8,3),
  'failure_code','LEAK','priority','high','sla_resolve_due_at',c10_test.ts(8,5)));
-- preventive (PM) WOs
SELECT c10_test.wo('P1','preventive','CLOSED','CHL-1',1001,jsonb_build_object('requested_at',c10_test.ts(18),'due_on',c10_test.dt(15),'completed_at',c10_test.ts(14,12)));
SELECT c10_test.wo('P2','preventive','CLOSED','CHL-1',1001,jsonb_build_object('requested_at',c10_test.ts(18),'due_on',c10_test.dt(12),'completed_at',c10_test.ts(8,6)));
SELECT c10_test.wo('P3','preventive','VERIFIED','POS-1',1001,jsonb_build_object('requested_at',c10_test.ts(18),'due_on',c10_test.dt(10),'completed_at',c10_test.ts(10,6)));
SELECT c10_test.wo('P4','preventive','IN_PROGRESS','CRN-1',1002,jsonb_build_object('requested_at',c10_test.ts(18),'due_on',c10_test.dt(6),'started_at',c10_test.ts(6)));
SELECT c10_test.wo('P5','preventive','CANCELLED','POS-1',1001,jsonb_build_object('requested_at',c10_test.ts(18),'due_on',c10_test.dt(4)));
-- plans + targets (due rules: lead 7, grace 3, escalation 3)
SELECT c10_test.plan('T1','CHL-1','Chiller monthly','monthly',true,current_date+3-current_date+c10_test.today()+0-c10_test.today()+c10_test.today()-current_date+0);
