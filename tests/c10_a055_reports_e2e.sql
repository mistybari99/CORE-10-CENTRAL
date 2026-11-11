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
SELECT c10_test.plan('T1','CHL-1','Chiller monthly','monthly',true,c10_test.today()+3);
SELECT c10_test.plan('T2','POS-1','POS check','monthly',true,c10_test.today()+30);
SELECT c10_test.plan('T3','CRN-1','Crane service','monthly',true,c10_test.today()-5);
SELECT c10_test.plan('T4','CNV-1','Conveyor service','monthly',true,c10_test.today()-10);
SELECT c10_test.plan('T5','CHL-1','Chiller quarterly','monthly',true,c10_test.today()-2);
SELECT c10_test.plan('T6','POS-1','Closed plan','monthly',false,c10_test.today()+1);
SELECT c10_test.plan('T7','CHL-1','Chiller by hours','usage',true,NULL,jsonb_build_object('meter_code','HRS','usage_interval',100),jsonb_build_object('next_due_reading',25));
SELECT c10_test.plan('T8','CNV-1','Conveyor by hours','usage',true,NULL,jsonb_build_object('meter_code','HRS','usage_interval',100),jsonb_build_object('next_due_reading',100));
SELECT c10_test.plan('T9','POS-1','POS weekly','weekly',true,c10_test.today()+1);
SELECT c10_test.plan('T10','CRN-1','Crane deferred','monthly',true,c10_test.today()-20,'{}',jsonb_build_object('deferred_until',c10_test.dt(-5)));
-- open WOs
SELECT c10_test.wo('O1','corrective','DRAFT','CHL-1',1001,jsonb_build_object('priority','low','due_on',c10_test.dt(5),'requested_at',c10_test.ts(10)));
SELECT c10_test.wo('O2','corrective','SUBMITTED','POS-1',1001,jsonb_build_object('priority','medium','due_on',c10_test.dt(-3),'plan_target_id',c10_test.k('T9')));
SELECT c10_test.wo('O4','breakdown','IN_PROGRESS','OVN-1',1001,jsonb_build_object('priority','critical','requested_at',c10_test.ts(0),'started_at',c10_test.ts(0),
  'responded_at',c10_test.ts(0),'sla_resolve_due_at',(now()-interval '1 hour')::text,'sla_response_due_at',(now()-interval '4 hours')::text));
SELECT c10_test.wo('O5','corrective','IN_PROGRESS','CRN-1',1002,jsonb_build_object('priority','high','due_on',c10_test.dt(0),'requested_at',(now()-interval '23 hours')::text,
  'started_at',(now()-interval '22 hours')::text,'sla_resolve_due_at',(now()+interval '1 hour')::text));
SELECT c10_test.wo('O6','corrective','SUBMITTED','CRN-1',1002,jsonb_build_object('priority','high','due_on',c10_test.dt(40),'requested_at',(now()-interval '45 days')::text,
  'sla_resolve_due_at',(now()-interval '30 days')::text,'sla_response_due_at',(now()-interval '44 days')::text));
SELECT c10_test.wo('O7','corrective','SUBMITTED','PRJ-1',1004,jsonb_build_object('priority','medium','requested_at',c10_test.ts(10)));
SELECT c10_test.wo('O8','corrective','APPROVED','CNV-1',1005,jsonb_build_object('priority','medium','due_on',c10_test.dt(-10)));
SELECT c10_test.wo('O10','breakdown','IN_PROGRESS','OLD-1',1004,jsonb_build_object('priority','critical','requested_at',c10_test.ts(40),'started_at',c10_test.ts(40,1)));
-- downtime
SELECT c10_test.dtw('CNV-1',1002,'other',c10_test.ts(10,2),c10_test.ts(10,6),NULL,'DW1');
SELECT c10_test.dtw('CNV-1',1002,'other',c10_test.ts(10,4),c10_test.ts(10,8),NULL,'DW2');
SELECT c10_test.dtw('CNV-1',1002,'other',c10_test.ts(5),c10_test.ts(5,1),NULL,'DW3');
SELECT c10_test.dtw('CNV-1',1002,'other',c10_test.ts(3),(c10_test.t0()-interval '3 days'+interval '3 minutes')::text,NULL,'DW4');
SELECT c10_test.dtw('CNV-1',1002,'planned',c10_test.ts(7),c10_test.ts(7,10),NULL,'DW5');
SELECT c10_test.dtw('CNV-1',1002,'other',c10_test.ts(21,20),c10_test.ts(20,4),NULL,'DW6');
SELECT c10_test.dtw('CRN-1',1002,'breakdown',c10_test.ts(15),c10_test.ts(15,2),'BD1');
SELECT c10_test.dtw('CRN-1',1002,'breakdown',c10_test.ts(12),c10_test.ts(12,4),'BD2');
SELECT c10_test.dtw('CRN-1',1002,'breakdown',c10_test.ts(9),c10_test.ts(9,6),'BD3');
SELECT c10_test.dtw('CHL-1',1001,'breakdown',c10_test.ts(8),c10_test.ts(8,3),'BD5');
SELECT c10_test.dtw('POS-1',1001,'breakdown',c10_test.ts(5),c10_test.ts(5,1),NULL,'DT-POS');
SELECT c10_test.dtw('OLD-1',1004,'breakdown',c10_test.ts(40),NULL,'O10',NULL);
SELECT c10_test.dtw('OVN-1',1001,'breakdown',c10_test.ts(0),NULL,'O4',NULL);
SELECT c10_test.dtw('GEN-X',1001,'planned',c10_test.ts(0),NULL,NULL,'DT-GEN');
-- warranties + claims
SELECT c10_test.ins('am_warranties',jsonb_build_object('tenant_id',1,'business_id',101,'asset_id',c10_test.k('CHL-1'),'supplier_name','Chill Co','starts_on',c10_test.dt(345),'expires_on',c10_test.dt(-20),'created_by',c10_test.u('bo101')))
 \gset
INSERT INTO c10_test.ids VALUES('W1',:ins);
SELECT c10_test.ins('am_warranties',jsonb_build_object('tenant_id',1,'business_id',101,'asset_id',c10_test.k('POS-1'),'supplier_name','Pos Co','starts_on',c10_test.dt(10),'expires_on',c10_test.dt(-200),'created_by',c10_test.u('bo101'))) \gset
INSERT INTO c10_test.ids VALUES('W2',:ins);
SELECT c10_test.ins('am_warranties',jsonb_build_object('tenant_id',1,'business_id',101,'asset_id',c10_test.k('CNV-1'),'supplier_name','Belt Co','starts_on',c10_test.dt(395),'expires_on',c10_test.dt(30),'created_by',c10_test.u('bo101'))) \gset
INSERT INTO c10_test.ids VALUES('W3',:ins);
SELECT c10_test.ins('am_warranties',jsonb_build_object('tenant_id',1,'business_id',101,'asset_id',c10_test.k('CRN-1'),'supplier_name','Crane Co','starts_on',c10_test.dt(25),'expires_on',c10_test.dt(-100),'created_by',c10_test.u('bo101'))) \gset
INSERT INTO c10_test.ids VALUES('W4',:ins);
SELECT c10_test.ins('am_warranties',jsonb_build_object('tenant_id',1,'business_id',101,'asset_id',c10_test.k('OVN-1'),'supplier_name','Oven Co','starts_on',c10_test.dt(100),'expires_on',c10_test.dt(-100),'status','void','created_by',c10_test.u('bo101'))) \gset
INSERT INTO c10_test.ids VALUES('W5',:ins);
SELECT c10_test.ins('am_warranty_claims',jsonb_build_object('tenant_id',1,'business_id',101,'claim_no','CLM-T1','warranty_id',c10_test.k('W4'),'asset_id',c10_test.k('CRN-1'),'failure_on',c10_test.dt(15),'description','Claim one','status','draft','created_by',c10_test.u('bo101')));
SELECT c10_test.ins('am_warranty_claims',jsonb_build_object('tenant_id',1,'business_id',101,'claim_no','CLM-T2','warranty_id',c10_test.k('W4'),'asset_id',c10_test.k('CRN-1'),'failure_on',c10_test.dt(12),'description','Claim two','status','submitted','created_by',c10_test.u('bo101')));
SELECT c10_test.ins('am_warranty_claims',jsonb_build_object('tenant_id',1,'business_id',101,'claim_no','CLM-T3','warranty_id',c10_test.k('W4'),'asset_id',c10_test.k('CRN-1'),'failure_on',c10_test.dt(9),'description','Claim three','status','settled','amount_claimed',1000,'amount_settled',500,'created_by',c10_test.u('bo101')));
SELECT c10_test.ins('am_warranty_claims',jsonb_build_object('tenant_id',1,'business_id',101,'claim_no','CLM-T4','warranty_id',c10_test.k('W1'),'asset_id',c10_test.k('CHL-1'),'failure_on',c10_test.dt(8),'description','Claim four','status','rejected','amount_claimed',200,'created_by',c10_test.u('bo101')));
-- business 102: CLEAN
SELECT c10_test.asset(102,'GEN-102','Generator 102','GENERAL',1003,'active',3);
SELECT c10_test.asset(102,'PMP-102','Pump 102','COLD',1003,'active',4);
SELECT c10_test.ins('am_meters',jsonb_build_object('tenant_id',1,'business_id',102,'asset_id',c10_test.k('GEN-102'),'code','HRS','unit','hours','current_reading',30,'last_reading_at',c10_test.ts(1))) \gset
INSERT INTO c10_test.ids VALUES('M-102',:ins);
SELECT c10_test.ins('am_meter_readings',jsonb_build_object('tenant_id',1,'business_id',102,'meter_id',c10_test.k('M-102'),'asset_id',c10_test.k('GEN-102'),'reading',v.r,'kind','reading',
  'read_at',c10_test.ts(v.d),'recorded_by',c10_test.u('bo102'),'request_key','seed102-'||v.d)) FROM (VALUES(10,9),(20,5),(30,1)) v(r,d);
SELECT c10_test.wo('CB1','breakdown','COMPLETED','GEN-102',1003,jsonb_build_object('requested_at',c10_test.ts(6),'started_at',c10_test.ts(6,0.5),'completed_at',c10_test.ts(6,2),'failure_code','MECH'));
SELECT c10_test.dtw('GEN-102',1003,'breakdown',c10_test.ts(6),c10_test.ts(6,2),'CB1');
SELECT c10_test.wo('CP1','preventive','CLOSED','PMP-102',1003,jsonb_build_object('requested_at',c10_test.ts(12),'due_on',c10_test.dt(8),'completed_at',c10_test.ts(8,5)));
SELECT c10_test.wo('O102','corrective','SUBMITTED','PMP-102',1003,jsonb_build_object('due_on',c10_test.dt(-5)));
SELECT c10_test.plan('T102','GEN-102','Gen monthly','monthly',true,c10_test.today()+10);
SELECT c10_test.ins('am_warranties',jsonb_build_object('tenant_id',1,'business_id',102,'asset_id',c10_test.k('PMP-102'),'supplier_name','Pump Co','starts_on',c10_test.dt(30),'expires_on',c10_test.dt(-300),'created_by',c10_test.u('bo102')));
-- tenant 2 / business 201 (injection-heavy names, not bootstrapped)
SELECT c10_test.asset(201,'INJ-1','=cmd|calc','T2-CAT',2001,'active',3);
SELECT c10_test.asset(201,'INJ-2','+1','T2-CAT',2001,'active',3);
SELECT c10_test.asset(201,'INJ-3','-2','T2-CAT',2001,'active',3);
SELECT c10_test.asset(201,'INJ-4','@x','T2-CAT',2001,'active',3);
SELECT c10_test.asset(201,'INJ-5','  =SUM(A1)','T2-CAT',2001,'active',3);
SELECT c10_test.asset(201,'INJ-6','He said "hi", ok','T2-CAT',2001,'active',3);
SELECT c10_test.asset(201,'INJ-7',E'line1\nline2','T2-CAT',2001,'active',3);
SELECT c10_test.asset(201,'INJ-8',E'\tTab','T2-CAT',2001,'active',3);
SELECT c10_test.asset(201,'OK-201','Plain asset','T2-CAT',2001,'active',3);
SELECT c10_test.wo('O201','corrective','SUBMITTED','OK-201',2001);
-- audit seed (hash chained through the real trigger)
SELECT c10_demo.ami_log(1,101,'asset',c10_test.k('CHL-1')::text,'create',NULL,'{"name":"Chiller 1"}','seed','seed-audit-101-a');
SELECT c10_demo.ami_log(1,101,'asset',c10_test.k('CHL-1')::text,'update','{"name":"Chiller 1"}','{"name":"Chiller One"}','rename','seed-audit-101-b');
SELECT c10_demo.ami_log(1,101,'work_order',c10_test.k('BD1')::text,'complete',NULL,'{"status":"COMPLETED"}','done','seed-audit-101-c');
SELECT c10_demo.ami_log(1,101,'asset',c10_test.k('CRN-1')::text,'create',NULL,'{"name":"Crane 1"}','seed','seed-audit-101-d');
SELECT c10_demo.ami_log(1,101,'work_order',c10_test.k('O4')::text,'create',NULL,'{"status":"IN_PROGRESS"}','seed','seed-audit-101-e');
SELECT set_config('request.jwt.claim.sub',c10_test.u('bo102')::text,true);
SELECT c10_demo.ami_log(1,102,'asset',c10_test.k('GEN-102')::text,'create',NULL,'{"name":"Generator 102"}','seed','seed-audit-102-a');
SELECT c10_demo.ami_log(1,102,'asset',c10_test.k('PMP-102')::text,'create',NULL,'{"name":"Pump 102"}','seed','seed-audit-102-b');
SELECT set_config('request.jwt.claim.sub',c10_test.u('owner2')::text,true);
SELECT c10_demo.ami_log(2,201,'asset',c10_test.k('OK-201')::text,'create',NULL,'{"name":"Plain asset"}','seed','seed-audit-201-a');
CREATE TEMP TABLE c10_cnt AS SELECT (SELECT count(*) FROM c10_demo.am_audit) AS aud,(SELECT count(*) FROM c10_demo.am_receipts) AS rec,
 (SELECT count(*) FROM c10_demo.am_settings) AS setn,(SELECT count(*) FROM c10_demo.am_codes) AS cod;
GRANT SELECT ON c10_cnt TO PUBLIC;

-- ===================================================== S1 authority matrix =====================================================
SET LOCAL ROLE authenticated;
DO $$
DECLARE rp text[]:=ARRAY[
  'SELECT c10_demo.am_overview_v1(101)','SELECT c10_demo.am_downtime_report_v1(101)','SELECT c10_demo.am_kpi_report_v1(101)',
  'SELECT c10_demo.am_asset_health_report_v1(101)','SELECT c10_demo.am_warranty_report_v1(101)','SELECT c10_demo.am_reconciliation_v1(101)',
  $q$SELECT c10_demo.am_export_csv_v1(101,'rq-authz-0001','assets','{}')$q$];
 own text[]:=ARRAY['SELECT c10_demo.am_integrity_report_v1(101)','SELECT c10_demo.am_audit_log_v1(101)'];
 s text; p text;
BEGIN
 -- outsiders / revoked / other tenant / other business / stock-only / manager without grant / platform operator => am_denied on EVERYTHING
 FOREACH p IN ARRAY ARRAY['stock','investor','revoked','revtech','owner2','staff2','operator','mgr','bo102','sup201'] LOOP
  PERFORM c10_test.as_user(p);
  FOREACH s IN ARRAY rp||own||ARRAY['SELECT c10_demo.read_asset_maintenance_business_summary_v1(101,NULL)'] LOOP
   PERFORM c10_test.denied(s,'am_denied'); END LOOP;
 END LOOP;
 -- unauthenticated claim fails closed; NULL business denied
 PERFORM set_config('request.jwt.claim.sub','',true);
 FOREACH s IN ARRAY rp||own LOOP PERFORM c10_test.denied(s,'am_denied'); END LOOP;
 PERFORM c10_test.as_user('bo101');
 PERFORM c10_test.denied('SELECT c10_demo.am_overview_v1(NULL)','am_denied');
 PERFORM c10_test.denied('SELECT c10_demo.am_overview_v1(102)','am_denied');
 PERFORM c10_test.denied('SELECT c10_demo.am_overview_v1(201)','am_denied');
 PERFORM c10_test.denied('SELECT c10_demo.am_overview_v1(999999)','am_denied');
 PERFORM c10_test.as_user('owner');   -- tenant 1 owner cannot see tenant 2
 PERFORM c10_test.denied('SELECT c10_demo.am_overview_v1(201)','am_denied');
 PERFORM c10_test.denied('SELECT c10_demo.am_kpi_report_v1(201)','am_denied');
 PERFORM c10_test.as_user('owner2');
 PERFORM c10_test.denied('SELECT c10_demo.am_downtime_report_v1(101)','am_denied');
 PERFORM c10_test.denied('SELECT c10_demo.am_overview_v1(102)','am_denied');
 -- member without the 'reports' capability: technician / reporter => am_not_permitted (also audit/integrity), summary needs owner
 FOREACH p IN ARRAY ARRAY['tech1001','tech1002','reporter'] LOOP
  PERFORM c10_test.as_user(p);
  FOREACH s IN ARRAY rp||own LOOP PERFORM c10_test.denied(s,'am_not_permitted'); END LOOP;
  PERFORM c10_test.denied('SELECT c10_demo.read_asset_maintenance_business_summary_v1(101,NULL)','am_owner_required');
 END LOOP;
 -- supervisors: reports yes, audit/integrity no, A050 adapter owner-only
 FOREACH p IN ARRAY ARRAY['sup','sup1001','auditor'] LOOP
  PERFORM c10_test.as_user(p);
  PERFORM c10_demo.am_overview_v1(101); PERFORM c10_demo.am_kpi_report_v1(101); PERFORM c10_demo.am_reconciliation_v1(101);
  PERFORM c10_test.denied('SELECT c10_demo.read_asset_maintenance_business_summary_v1(101,NULL)','am_owner_required');
 END LOOP;
 FOREACH p IN ARRAY ARRAY['sup','sup1001'] LOOP
  PERFORM c10_test.as_user(p);
  FOREACH s IN ARRAY own LOOP PERFORM c10_test.denied(s,'am_not_permitted'); END LOOP;
  PERFORM c10_test.denied($q$SELECT c10_demo.am_export_csv_v1(101,'rq-authz-0002','audit','{}')$q$,'am_not_permitted');
 END LOOP;
 PERFORM c10_test.as_user('auditor');
 PERFORM c10_demo.am_integrity_report_v1(101); PERFORM c10_demo.am_audit_log_v1(101);
 -- site filter arguments
 PERFORM c10_test.as_user('sup1001');
 PERFORM c10_test.denied('SELECT c10_demo.am_overview_v1(101,1002)','am_not_permitted');
 PERFORM c10_test.denied('SELECT c10_demo.am_overview_v1(101,1003)','am_denied');       -- site of another business
 PERFORM c10_test.denied('SELECT c10_demo.am_overview_v1(101,987654)','am_denied');
 PERFORM c10_test.denied('SELECT c10_demo.am_kpi_report_v1(101,NULL,NULL,1002)','am_not_permitted');
 PERFORM c10_test.denied('SELECT c10_demo.am_downtime_report_v1(101,NULL,NULL,1002)','am_not_permitted');
 PERFORM c10_test.denied('SELECT c10_demo.am_asset_health_report_v1(101,1002)','am_not_permitted');
 PERFORM c10_demo.am_overview_v1(101,1001);
 -- input validation
 PERFORM c10_test.as_user('bo101');
 PERFORM c10_test.denied('SELECT c10_demo.am_downtime_report_v1(101,current_date,current_date-3)','am_invalid_input');
 PERFORM c10_test.denied('SELECT c10_demo.am_kpi_report_v1(101,DATE ''2000-01-01'',current_date)','am_invalid_input');
 PERFORM c10_test.denied('SELECT c10_demo.am_warranty_report_v1(101,-1)','am_invalid_input');
 PERFORM c10_test.denied('SELECT c10_demo.am_warranty_report_v1(101,4000)','am_invalid_input');
 PERFORM c10_test.denied('SELECT c10_demo.am_reconciliation_v1(101,current_date,current_date-1)','am_invalid_input');
END $$;
RESET ROLE;

-- ===================================================== S2 overview =====================================================
SET LOCAL ROLE authenticated;
DO $$
DECLARE r jsonb;
BEGIN
 PERFORM c10_test.as_user('bo101'); r:=c10_demo.am_overview_v1(101);
 PERFORM c10_test.eq(r->'assets_by_status'->>'active','6','ov active'); PERFORM c10_test.eq(r->'assets_by_status'->>'breakdown','3','ov breakdown');
 PERFORM c10_test.eq(r->'assets_by_status'->>'retired','1','ov retired');
 PERFORM c10_test.eq((SELECT e->>'total' FROM jsonb_array_elements(r->'assets_by_site') e WHERE e->>'site_id'='1001'),'5','site 1001 assets');
 PERFORM c10_test.eq((SELECT e->>'total' FROM jsonb_array_elements(r->'assets_by_site') e WHERE e->>'site_id'='1005'),'1','site 1005 assets');
 PERFORM c10_test.eq(r#>>'{open_work_orders,total}','9','open total');
 PERFORM c10_test.eq(r#>>'{open_work_orders,by_status}','{"DRAFT": 1, "APPROVED": 1, "SUBMITTED": 3, "IN_PROGRESS": 4}','open by status');
 PERFORM c10_test.eq(r#>>'{open_work_orders,by_priority}','{"low": 1, "high": 2, "medium": 4, "critical": 2}','open by priority');
 PERFORM c10_test.eq(r#>>'{overdue_work_orders,count}','3','overdue');
 PERFORM c10_test.eq(r#>>'{sla,resolve_breached}','2','sla breached'); PERFORM c10_test.eq(r#>>'{sla,resolve_at_risk}','1','sla at risk');
 PERFORM c10_test.eq(r#>>'{sla,response_breached}','1','sla response');
 PERFORM c10_test.eq(r#>>'{plan_targets,total}','9','targets');
 PERFORM c10_test.eq(r#>>'{plan_targets,by_state}','{"due": 3, "overdue": 2, "deferred": 1, "upcoming": 1, "has_open_wo": 1, "meter_missing": 1}','target states');
 PERFORM c10_test.eq(r#>>'{plan_targets,escalation}','{"level1": 1, "level2": 1}','escalation');
 PERFORM c10_test.eq(r#>>'{open_downtime,count}','3','open downtime');
 PERFORM c10_test.eq(r#>>'{capabilities,is_business_owner}','true','caps bo');
 PERFORM c10_test.chk(r#>'{capabilities,business_wide}' ? 'reports','caps list');
 -- tenant owner sees the same; owner of business 102 sees only 102 data (isolation)
 PERFORM c10_test.as_user('owner'); PERFORM c10_test.eq((c10_demo.am_overview_v1(101))#>>'{open_work_orders,total}','9','tenant owner 101');
 r:=c10_demo.am_overview_v1(102);
 PERFORM c10_test.eq(r->'assets_by_status'->>'active','2','102 assets'); PERFORM c10_test.eq(r#>>'{open_work_orders,total}','1','102 open wo');
 PERFORM c10_test.eq(r#>>'{open_downtime,count}','0','102 open dt'); PERFORM c10_test.eq(r#>>'{plan_targets,total}','1','102 targets');
 PERFORM c10_test.as_user('bo102'); PERFORM c10_test.eq((c10_demo.am_overview_v1(102))#>>'{open_work_orders,total}','1','bo102');
 PERFORM c10_test.as_user('owner2'); r:=c10_demo.am_overview_v1(201);
 PERFORM c10_test.eq(r->'assets_by_status'->>'active','9','201 assets'); PERFORM c10_test.eq(r#>>'{open_work_orders,total}','1','201 open wo');
 PERFORM c10_test.as_user('sup201'); PERFORM c10_test.eq((c10_demo.am_overview_v1(201))#>>'{open_work_orders,total}','1','sup201');
 -- supervisor for all sites == owner view; supervisor(1001) sees only site 1001
 PERFORM c10_test.as_user('sup'); PERFORM c10_test.eq((c10_demo.am_overview_v1(101))#>>'{open_work_orders,total}','9','sup all');
 PERFORM c10_test.as_user('auditor'); PERFORM c10_test.eq((c10_demo.am_overview_v1(101))#>>'{open_work_orders,total}','9','auditor all');
 PERFORM c10_test.as_user('sup1001'); r:=c10_demo.am_overview_v1(101);
 PERFORM c10_test.eq(r->'assets_by_status'->>'active','3','1001 active'); PERFORM c10_test.eq(r->'assets_by_status'->>'breakdown','2','1001 breakdown');
 PERFORM c10_test.eq(r->'assets_by_status'->>'retired',NULL,'1001 no retired');
 PERFORM c10_test.eq(r#>>'{open_work_orders,total}','3','1001 open'); PERFORM c10_test.eq(r#>>'{open_work_orders,by_status}','{"DRAFT": 1, "APPROVED": 0, "SUBMITTED": 1, "IN_PROGRESS": 1}','1001 by status');
 PERFORM c10_test.eq(r#>>'{overdue_work_orders,count}','1','1001 overdue'); PERFORM c10_test.eq(r#>>'{sla,resolve_breached}','1','1001 sla');
 PERFORM c10_test.eq(r#>>'{sla,resolve_at_risk}','0','1001 risk'); PERFORM c10_test.eq(r#>>'{open_downtime,count}','2','1001 open dt');
 PERFORM c10_test.eq(r#>>'{plan_targets,by_state}','{"due": 3, "overdue": 0, "deferred": 0, "upcoming": 1, "has_open_wo": 1, "meter_missing": 0}','1001 targets');
 PERFORM c10_test.eq(jsonb_array_length(r->'assets_by_site')::text,'1','1001 only site');
 PERFORM c10_test.eq((r->'sites')::text,'[1001]','1001 scope'); PERFORM c10_test.chk(NOT (r#>'{capabilities,by_site,1002}' ? 'reports'),'no reports cap at 1002');
 r:=c10_demo.am_overview_v1(101,1001); PERFORM c10_test.eq(r#>>'{open_work_orders,total}','3','explicit site');
 PERFORM c10_test.as_user('bo101'); r:=c10_demo.am_overview_v1(101,1002);
 PERFORM c10_test.eq(r->'assets_by_status'->>'active','2','1002 filter'); PERFORM c10_test.eq(r#>>'{open_work_orders,total}','3','1002 open');  -- O5,O6,P4
END $$;
RESET ROLE;

-- ===================================================== S3 downtime report =====================================================
CREATE FUNCTION c10_test.pa(r jsonb,p_no text,p_f text) RETURNS text LANGUAGE sql IMMUTABLE AS
$$ SELECT e->>p_f FROM jsonb_array_elements(r->'per_asset') e WHERE e->>'asset_no'=p_no $$;
GRANT EXECUTE ON FUNCTION c10_test.pa(jsonb,text,text) TO authenticated;
SET LOCAL ROLE authenticated;
DO $$
DECLARE r jsonb; f text:=c10_test.dt(20); t text:=c10_test.dt(1);
BEGIN
 PERFORM c10_test.as_user('bo101');
 r:=c10_demo.am_downtime_report_v1(101,c10_test.dt(20)::date,c10_test.dt(1)::date);
 -- overlapping windows merged (w1+w2 overlap -> 360 not 480), window straddling period start clipped (240), 3-minute window counted by default, planned excluded
 PERFORM c10_test.eqn(c10_test.pa(r,'CNV-1','downtime_minutes'),663,'CNV-1 merged minutes');
 PERFORM c10_test.eqn(c10_test.pa(r,'CNV-1','windows'),5,'CNV-1 counted windows'); PERFORM c10_test.eqn(c10_test.pa(r,'CNV-1','merged_windows'),4,'CNV-1 islands');
 PERFORM c10_test.eqn(c10_test.pa(r,'CNV-1','period_minutes'),28800,'CNV-1 period');
 PERFORM c10_test.eqn(c10_test.pa(r,'CNV-1','availability_pct'),round(100*(1-663.0/28800),2),'CNV-1 availability');
 PERFORM c10_test.eqn(c10_test.pa(r,'CRN-1','downtime_minutes'),720,'CRN-1'); PERFORM c10_test.eqn(c10_test.pa(r,'CHL-1','downtime_minutes'),180,'CHL-1');
 -- availability period clipped to commission date (POS-1 commissioned 10 days ago)
 PERFORM c10_test.eqn(c10_test.pa(r,'POS-1','period_minutes'),14400,'POS period clipped'); PERFORM c10_test.eqn(c10_test.pa(r,'POS-1','downtime_minutes'),60,'POS downtime');
 PERFORM c10_test.eqn(c10_test.pa(r,'POS-1','availability_pct'),round(100*(1-60.0/14400),2),'POS availability');
 -- open window capped at started + max_open_hours (720h) and flagged
 PERFORM c10_test.eqn(c10_test.pa(r,'OLD-1','downtime_minutes'),14400,'OLD-1 capped open window');
 PERFORM c10_test.eq(c10_test.pa(r,'OLD-1','exceeds_max_open'),'true','OLD-1 exceeds'); PERFORM c10_test.eq(c10_test.pa(r,'CNV-1','exceeds_max_open'),'false','CNV no exceed');
 PERFORM c10_test.eqn(r#>>'{totals,downtime_minutes}',16023,'total minutes'); PERFORM c10_test.eqn(r#>>'{totals,assets_with_downtime}',5,'assets with downtime');
 PERFORM c10_test.eqn(r#>>'{totals,excluded_planned}',1,'excluded planned'); PERFORM c10_test.eqn(r#>>'{totals,excluded_below_min}',0,'excluded short');
 PERFORM c10_test.eqn(r#>>'{totals,counted_windows}',11,'counted windows'); PERFORM c10_test.eqn(r#>>'{totals,merged_windows}',10,'merged windows');
 PERFORM c10_test.eqn(r#>>'{totals,open_windows}',1,'open windows in period'); PERFORM c10_test.eqn(r#>>'{totals,exceeds_max_open}',1,'exceeds count');
 PERFORM c10_test.eqn(r#>>'{totals,assets_considered}',10,'assets considered');
 PERFORM c10_test.eqn(r#>>'{totals,fleet_availability_pct}',round(100*(1-(r#>>'{totals,downtime_minutes}')::numeric/(r#>>'{totals,period_minutes}')::numeric),2),'fleet availability');
 PERFORM c10_test.eq(r#>>'{top_offenders,0,asset_no}','OLD-1','top offender'); PERFORM c10_test.eq(r#>>'{top_offenders,1,asset_no}','CRN-1','second offender');
 PERFORM c10_test.eq(jsonb_array_length(r->'top_offenders')::text,'5','5 offenders');
 PERFORM c10_test.eqn((SELECT e->>'downtime_minutes' FROM jsonb_array_elements(r->'per_site') e WHERE e->>'site_id'='1002'),1383,'site 1002 minutes');
 PERFORM c10_test.eqn((SELECT e->>'downtime_minutes' FROM jsonb_array_elements(r->'per_site') e WHERE e->>'site_id'='1004'),14400,'site 1004 minutes');
 PERFORM c10_test.eq(jsonb_array_length(r->'open_windows')::text,'1','open window list');
 -- per-site filtering: supervisor(1001) never sees other sites; explicit p_site
 PERFORM c10_test.as_user('sup1001'); r:=c10_demo.am_downtime_report_v1(101,c10_test.dt(20)::date,c10_test.dt(1)::date);
 PERFORM c10_test.eqn(r#>>'{totals,downtime_minutes}',240,'1001 total'); PERFORM c10_test.eq(c10_test.pa(r,'CNV-1','downtime_minutes'),NULL,'no 1002 asset');
 PERFORM c10_test.eqn(r#>>'{totals,assets_considered}',5,'1001 assets');
 PERFORM c10_test.as_user('sup'); r:=c10_demo.am_downtime_report_v1(101,c10_test.dt(20)::date,c10_test.dt(1)::date,1002);
 PERFORM c10_test.eqn(r#>>'{totals,downtime_minutes}',1383,'sup site 1002');
 -- isolation: 102 only sees its own window (120 min)
 PERFORM c10_test.as_user('bo102'); r:=c10_demo.am_downtime_report_v1(102,c10_test.dt(20)::date,c10_test.dt(1)::date);
 PERFORM c10_test.eqn(r#>>'{totals,downtime_minutes}',120,'102 minutes'); PERFORM c10_test.eqn(r#>>'{totals,assets_considered}',2,'102 assets');
 PERFORM c10_test.as_user('owner2'); r:=c10_demo.am_downtime_report_v1(201,c10_test.dt(20)::date,c10_test.dt(1)::date);
 PERFORM c10_test.eqn(r#>>'{totals,downtime_minutes}',0,'201 minutes'); PERFORM c10_test.eqn(r#>>'{totals,assets_considered}',9,'201 assets');
END $$;
RESET ROLE;
-- policy: windows shorter than downtime.min_counted_minutes (5) are excluded
INSERT INTO c10_demo.am_policy(business_id,tenant_id,scope_type,scope_id,key,value,updated_by) VALUES(101,1,'business',0,'downtime.min_counted_minutes','5',c10_test.u('bo101'));
SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb; BEGIN PERFORM c10_test.as_user('bo101');
 r:=c10_demo.am_downtime_report_v1(101,c10_test.dt(20)::date,c10_test.dt(1)::date);
 PERFORM c10_test.eqn(c10_test.pa(r,'CNV-1','downtime_minutes'),660,'min minutes excludes 3-minute window'); PERFORM c10_test.eqn(r#>>'{totals,excluded_below_min}',1,'excluded below min');
 PERFORM c10_test.eqn(c10_test.pa(r,'CNV-1','windows'),4,'windows after min'); END $$;
RESET ROLE;
DELETE FROM c10_demo.am_policy WHERE business_id=101 AND key='downtime.min_counted_minutes';
-- policy: planned downtime counted when downtime.planned_counts
INSERT INTO c10_demo.am_policy(business_id,tenant_id,scope_type,scope_id,key,value,updated_by) VALUES(101,1,'business',0,'downtime.planned_counts','true',c10_test.u('bo101'));
SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb; BEGIN PERFORM c10_test.as_user('bo101');
 r:=c10_demo.am_downtime_report_v1(101,c10_test.dt(20)::date,c10_test.dt(1)::date);
 PERFORM c10_test.eqn(c10_test.pa(r,'CNV-1','downtime_minutes'),1263,'planned counted'); PERFORM c10_test.eqn(r#>>'{totals,excluded_planned}',0,'no planned exclusion'); END $$;
RESET ROLE;
DELETE FROM c10_demo.am_policy WHERE business_id=101 AND key='downtime.planned_counts';
-- policy: lower max_open_hours caps the open window earlier (48h => 2880 minutes), scoped by SITE override too
INSERT INTO c10_demo.am_policy(business_id,tenant_id,scope_type,scope_id,key,value,updated_by) VALUES(101,1,'site',1004,'downtime.max_open_hours','48',c10_test.u('bo101'));
SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb; BEGIN PERFORM c10_test.as_user('bo101');
 r:=c10_demo.am_downtime_report_v1(101,c10_test.dt(45)::date,c10_test.dt(1)::date);
 PERFORM c10_test.eqn(c10_test.pa(r,'OLD-1','downtime_minutes'),2880,'site override caps open window'); END $$;
RESET ROLE;
DELETE FROM c10_demo.am_policy WHERE business_id=101 AND key='downtime.max_open_hours';

-- ===================================================== S4 KPI report =====================================================
CREATE FUNCTION c10_test.ka(r jsonb,p_no text,p_f text) RETURNS text LANGUAGE sql IMMUTABLE AS
$$ SELECT e->>p_f FROM jsonb_array_elements(r->'per_asset') e WHERE e->>'asset_no'=p_no $$;
GRANT EXECUTE ON FUNCTION c10_test.ka(jsonb,text,text) TO authenticated;
SET LOCAL ROLE authenticated;
DO $$
DECLARE r jsonb; d jsonb; f date:=c10_test.dt(20)::date; t date:=c10_test.dt(1)::date;
BEGIN
 PERFORM c10_test.as_user('bo101');
 r:=c10_demo.am_kpi_report_v1(101,f,t); d:=c10_demo.am_downtime_report_v1(101,f,t);
 PERFORM c10_test.eqn(r#>>'{mttr,hours}',3.6,'fleet MTTR'); PERFORM c10_test.eqn(r#>>'{mttr,sample_size}',5,'mttr sample'); PERFORM c10_test.eq(r#>>'{mttr,insufficient_sample}','false','mttr sufficient');
 PERFORM c10_test.eqn(r#>>'{mtbf,failures}',5,'failures');
 PERFORM c10_test.eqn(r#>>'{mtbf,operating_hours}',round(((d#>>'{totals,period_minutes}')::numeric-(d#>>'{totals,downtime_minutes}')::numeric)/60,2),'operating hours consistent');
 PERFORM c10_test.eqn(r#>>'{mtbf,hours}',round((r#>>'{mtbf,operating_hours}')::numeric/5,2),'fleet MTBF'); PERFORM c10_test.eq(r#>>'{mtbf,insufficient_sample}','false','mtbf sufficient');
 PERFORM c10_test.eqn(c10_test.ka(r,'CRN-1','failures'),4,'crane failures'); PERFORM c10_test.eqn(c10_test.ka(r,'CRN-1','mttr_hours'),3.75,'crane MTTR');
 PERFORM c10_test.eqn(c10_test.ka(r,'CRN-1','mtbf_hours'),117,'crane MTBF (480h - 12h)/4');
 PERFORM c10_test.eq(c10_test.ka(r,'CHL-1','mttr_hours'),NULL,'chiller MTTR insufficient'); PERFORM c10_test.eq(c10_test.ka(r,'CHL-1','mttr_insufficient_sample'),'true','chiller flag');
 PERFORM c10_test.eq(c10_test.ka(r,'CHL-1','mtbf_hours'),NULL,'chiller MTBF insufficient'); PERFORM c10_test.eq(c10_test.ka(r,'CHL-1','mtbf_insufficient_sample'),'true','chiller mtbf flag');
 -- PM compliance, backlog, SLA, recurring, risk, cost
 PERFORM c10_test.eqn(r#>>'{pm_compliance,due}',4,'pm due'); PERFORM c10_test.eqn(r#>>'{pm_compliance,on_time}',2,'pm on time'); PERFORM c10_test.eqn(r#>>'{pm_compliance,late}',1,'pm late');
 PERFORM c10_test.eqn(r#>>'{pm_compliance,not_done}',1,'pm not done'); PERFORM c10_test.eqn(r#>>'{pm_compliance,compliance_pct}',50,'pm pct');
 PERFORM c10_test.eqn(r#>>'{overdue_backlog,count}',3,'backlog'); PERFORM c10_test.eqn(r#>>'{overdue_backlog,buckets,1_7}',2,'bucket 1-7');
 PERFORM c10_test.eqn(r#>>'{overdue_backlog,buckets,8_30}',0,'bucket 8-30'); PERFORM c10_test.eqn(r#>>'{overdue_backlog,buckets,31_90}',1,'bucket 31-90');
 PERFORM c10_test.eqn(r#>>'{overdue_backlog,buckets,over_90}',0,'bucket 90+'); PERFORM c10_test.eqn(r#>>'{overdue_backlog,oldest_days}',40,'oldest');
 PERFORM c10_test.eqn(r#>>'{sla_compliance,resolve,met}',3,'sla met'); PERFORM c10_test.eqn(r#>>'{sla_compliance,resolve,breached}',1,'sla breached');
 PERFORM c10_test.eqn(r#>>'{sla_compliance,resolve,compliance_pct}',75,'sla pct'); PERFORM c10_test.eq(r#>>'{sla_compliance,response,compliance_pct}',NULL,'no response sla');
 PERFORM c10_test.eq(jsonb_array_length(r#>'{recurring_failures,items}')::text,'1','recurring groups');
 PERFORM c10_test.eq(r#>>'{recurring_failures,items,0,failure_code}','MECH','recurring code'); PERFORM c10_test.eqn(r#>>'{recurring_failures,items,0,count}',3,'recurring count');
 PERFORM c10_test.eq(r#>>'{recurring_failures,items,0,asset_no}','CRN-1','recurring asset');
 PERFORM c10_test.eqn((SELECT e->>'score' FROM jsonb_array_elements(r#>'{risk_matrix,items}') e WHERE e->>'asset_no'='CRN-1'),20,'crane risk score');
 PERFORM c10_test.eq((SELECT e->>'band' FROM jsonb_array_elements(r#>'{risk_matrix,items}') e WHERE e->>'asset_no'='CRN-1'),'critical','crane band');
 PERFORM c10_test.eqn((SELECT e->>'score' FROM jsonb_array_elements(r#>'{risk_matrix,items}') e WHERE e->>'asset_no'='CHL-1'),10,'chiller score (2x5)');
 PERFORM c10_test.eq((SELECT e->>'band' FROM jsonb_array_elements(r#>'{risk_matrix,items}') e WHERE e->>'asset_no'='CHL-1'),'high','chiller band');
 PERFORM c10_test.eqn((SELECT e->>'likelihood' FROM jsonb_array_elements(r#>'{risk_matrix,items}') e WHERE e->>'asset_no'='CRN-1'),4,'4 failures -> likelihood 4');
 PERFORM c10_test.eq(r#>>'{risk_matrix,bands}','{"low": 7, "high": 1, "medium": 0, "critical": 1}','risk bands');
 PERFORM c10_test.eq(r#>>'{cost_rollup,advisory}','true','cost advisory'); PERFORM c10_test.eq(r#>>'{cost_rollup,posted}','false','cost not posted');
 PERFORM c10_test.eqn(r#>>'{cost_rollup,work_orders}',8,'cost wos'); PERFORM c10_test.eqn(r#>>'{cost_rollup,totals,est_labor_cost}',900,'est labor');
 PERFORM c10_test.eqn(r#>>'{cost_rollup,totals,est_spares_cost}',200,'est spares'); PERFORM c10_test.eqn(r#>>'{cost_rollup,totals,actual_labor_cost}',1050,'act labor');
 PERFORM c10_test.eqn(r#>>'{cost_rollup,totals,actual_spares_cost}',400,'act spares'); PERFORM c10_test.eqn(r#>>'{cost_rollup,by_kind,breakdown,actual_total}',1450,'cost by kind');
 PERFORM c10_test.chk(r#>>'{cost_rollup,label}' ILIKE 'ADVISORY%','cost label');
 -- site-limited supervisor: sample of 1 => insufficient (MTTR and MTBF null + flag)
 PERFORM c10_test.as_user('sup1001'); r:=c10_demo.am_kpi_report_v1(101,f,t);
 PERFORM c10_test.eq(r#>>'{mttr,hours}',NULL,'1001 MTTR null'); PERFORM c10_test.eq(r#>>'{mttr,insufficient_sample}','true','1001 mttr flag'); PERFORM c10_test.eqn(r#>>'{mttr,sample_size}',1,'1001 sample');
 PERFORM c10_test.eq(r#>>'{mtbf,hours}',NULL,'1001 MTBF null'); PERFORM c10_test.eq(r#>>'{mtbf,insufficient_sample}','true','1001 mtbf flag');
 PERFORM c10_test.eqn(r#>>'{pm_compliance,due}',3,'1001 pm due'); PERFORM c10_test.eqn(r#>>'{pm_compliance,compliance_pct}',66.67,'1001 pm pct');
 PERFORM c10_test.eqn(r#>>'{overdue_backlog,count}',1,'1001 backlog'); PERFORM c10_test.eqn(r#>>'{cost_rollup,totals,actual_total}',0,'1001 cost');
 PERFORM c10_test.eqn(r#>>'{risk_matrix,items,0,failures}',1,'1001 top risk is chiller');
 -- isolation
 PERFORM c10_test.as_user('bo102'); r:=c10_demo.am_kpi_report_v1(102,f,t);
 PERFORM c10_test.eqn(r#>>'{mtbf,failures}',1,'102 failures'); PERFORM c10_test.eqn(r#>>'{pm_compliance,due}',1,'102 pm'); PERFORM c10_test.eqn(r#>>'{pm_compliance,compliance_pct}',100,'102 pm pct');
 PERFORM c10_test.eq(r#>>'{mttr,insufficient_sample}','true','102 mttr insufficient');
END $$;
RESET ROLE;
-- policy-driven sample sizes: min sample 6 makes the fleet MTTR (5 samples) insufficient; min 1 makes chiller sufficient
INSERT INTO c10_demo.am_policy(business_id,tenant_id,scope_type,scope_id,key,value,updated_by) VALUES
 (101,1,'business',0,'analytics.min_sample_mttr','6',c10_test.u('bo101')),(101,1,'business',0,'analytics.min_sample_mtbf','6',c10_test.u('bo101'));
SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb; BEGIN PERFORM c10_test.as_user('bo101'); r:=c10_demo.am_kpi_report_v1(101,c10_test.dt(20)::date,c10_test.dt(1)::date);
 PERFORM c10_test.eq(r#>>'{mttr,hours}',NULL,'MTTR null below policy sample'); PERFORM c10_test.eq(r#>>'{mttr,insufficient_sample}','true','flag'); PERFORM c10_test.eqn(r#>>'{mttr,min_sample}',6,'min sample echoed');
 PERFORM c10_test.eq(r#>>'{mtbf,hours}',NULL,'MTBF null'); PERFORM c10_test.eq(r#>>'{mtbf,insufficient_sample}','true','mtbf flag'); END $$;
RESET ROLE;
DELETE FROM c10_demo.am_policy WHERE business_id=101 AND key IN('analytics.min_sample_mttr','analytics.min_sample_mtbf');
INSERT INTO c10_demo.am_policy(business_id,tenant_id,scope_type,scope_id,key,value,updated_by) VALUES(101,1,'business',0,'analytics.min_sample_mttr','1',c10_test.u('bo101'));
SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb; BEGIN PERFORM c10_test.as_user('sup1001'); r:=c10_demo.am_kpi_report_v1(101,c10_test.dt(20)::date,c10_test.dt(1)::date);
 PERFORM c10_test.eqn(r#>>'{mttr,hours}',3,'single sample sufficient when policy min is 1 (BD5: 3h)'); PERFORM c10_test.eq(r#>>'{mttr,insufficient_sample}','false','flag cleared'); END $$;
RESET ROLE;
DELETE FROM c10_demo.am_policy WHERE business_id=101 AND key='analytics.min_sample_mttr';
-- policy: risk thresholds
INSERT INTO c10_demo.am_policy(business_id,tenant_id,scope_type,scope_id,key,value,updated_by) VALUES
 (101,1,'business',0,'risk.high_threshold','8',c10_test.u('bo101')),(101,1,'business',0,'risk.critical_threshold','10',c10_test.u('bo101'));
SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb; BEGIN PERFORM c10_test.as_user('bo101'); r:=c10_demo.am_kpi_report_v1(101,c10_test.dt(20)::date,c10_test.dt(1)::date);
 PERFORM c10_test.eq((SELECT e->>'band' FROM jsonb_array_elements(r#>'{risk_matrix,items}') e WHERE e->>'asset_no'='CHL-1'),'critical','chiller critical at threshold 10'); END $$;
RESET ROLE;
DELETE FROM c10_demo.am_policy WHERE business_id=101 AND key LIKE 'risk.%';
-- policy: PM grace (site override 1001: grace 7 makes P2 (4 days late) on time => 3 of 3 at site 1001)
INSERT INTO c10_demo.am_policy(business_id,tenant_id,scope_type,scope_id,key,value,updated_by) VALUES(101,1,'site',1001,'schedule.grace_days','7',c10_test.u('bo101'));
SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb; BEGIN PERFORM c10_test.as_user('bo101'); r:=c10_demo.am_kpi_report_v1(101,c10_test.dt(20)::date,c10_test.dt(1)::date);
 PERFORM c10_test.eqn(r#>>'{pm_compliance,on_time}',3,'grace policy by site'); PERFORM c10_test.eqn(r#>>'{pm_compliance,compliance_pct}',75,'pm pct with grace'); END $$;
RESET ROLE;
DELETE FROM c10_demo.am_policy WHERE business_id=101 AND key='schedule.grace_days';

-- ===================================================== S5 asset health + advisory depreciation =====================================================
CREATE FUNCTION c10_test.hi(r jsonb,p_no text) RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$ SELECT e FROM jsonb_array_elements(r->'items') e WHERE e->>'asset_no'=p_no $$;
CREATE FUNCTION c10_test.comp(h jsonb,p_key text,p_f text) RETURNS text LANGUAGE sql IMMUTABLE AS $$ SELECT c->>p_f FROM jsonb_array_elements(h->'components') c WHERE c->>'key'=p_key $$;
GRANT EXECUTE ON FUNCTION c10_test.hi(jsonb,text),c10_test.comp(jsonb,text,text) TO authenticated;
SET LOCAL ROLE authenticated;
DO $$
DECLARE r jsonb; h jsonb; m int:=(SELECT (extract(year FROM age(c10_test.today()::timestamp,c10_test.dt(400)::timestamp))*12+extract(month FROM age(c10_test.today()::timestamp,c10_test.dt(400)::timestamp)))::int);
BEGIN
 PERFORM c10_test.as_user('bo101'); r:=c10_demo.am_asset_health_report_v1(101);
 PERFORM c10_test.eqn(r->>'total',9,'health total (retired excluded)'); PERFORM c10_test.eq(r->>'advisory','true','health advisory');
 PERFORM c10_test.eq(r#>>'{items,0,asset_no}','CRN-1','worst asset first');
 h:=c10_test.hi(r,'CRN-1'); PERFORM c10_test.eqn(h->>'health_score',50,'crane score');
 PERFORM c10_test.eqn(c10_test.comp(h,'overdue_schedules','penalty'),10,'overdue penalty (deferred target ignored)'); PERFORM c10_test.eqn(c10_test.comp(h,'recent_failures','value'),4,'failures');
 PERFORM c10_test.eqn(c10_test.comp(h,'recent_failures','penalty'),30,'failures capped'); PERFORM c10_test.eqn(c10_test.comp(h,'age_vs_life','penalty'),0,'age ok');
 PERFORM c10_test.eqn(c10_test.comp(h,'warranty','penalty'),0,'active warranty'); PERFORM c10_test.eqn(c10_test.comp(h,'meter_staleness','penalty'),10,'stale meter');
 PERFORM c10_test.eq(h->>'band','poor','crane band'); PERFORM c10_test.eqn(jsonb_array_length(h->'components')::text,5,'5 components');
 h:=c10_test.hi(r,'CNV-1'); PERFORM c10_test.eqn(h->>'health_score',85,'conveyor score'); PERFORM c10_test.eq(c10_test.comp(h,'warranty','value'),'expired','expired warranty');
 PERFORM c10_test.eqn(c10_test.comp(h,'warranty','penalty'),5,'expired penalty'); PERFORM c10_test.eqn(c10_test.comp(h,'overdue_schedules','penalty'),10,'overdue 1');
 h:=c10_test.hi(r,'CHL-1'); PERFORM c10_test.eqn(h->>'health_score',92,'chiller score'); PERFORM c10_test.eq(h->>'band','good','chiller band');
 -- depreciation: advisory, never posted; straight line 100000, salvage 10%, 96 months
 PERFORM c10_test.eq(h#>>'{depreciation,advisory}','true','dep advisory'); PERFORM c10_test.eq(h#>>'{depreciation,posted}','false','dep not posted');
 PERFORM c10_test.eq(h#>>'{depreciation,method}','straight_line','dep method'); PERFORM c10_test.eqn(h#>>'{depreciation,useful_life_months}',96,'life from category');
 PERFORM c10_test.eqn(h#>>'{depreciation,salvage_value}',10000,'salvage'); PERFORM c10_test.eqn(h#>>'{depreciation,months_elapsed}',m,'months');
 PERFORM c10_test.eqn(h#>>'{depreciation,accumulated}',round(90000*m/96.0,2),'SL accumulated'); PERFORM c10_test.eqn(h#>>'{depreciation,book_value}',100000-round(90000*m/96.0,2),'SL book');
 h:=c10_test.hi(r,'CRN-1'); PERFORM c10_test.eq(h#>>'{depreciation,accumulated}',NULL,'no cost => no depreciation'); PERFORM c10_test.eq(h#>>'{depreciation,reason}','no_acquisition_cost','reason');
 PERFORM c10_test.eqn(r#>>'{summary,depreciation_advisory,total_accumulated}',round(90000*m/96.0,2)+0,'summary accumulated (only costed assets)');
 PERFORM c10_test.eq(r#>>'{summary,depreciation_advisory,posted}','false','summary not posted');
 PERFORM c10_test.eqn((r#>>'{summary,bands}')::jsonb->>'poor',1,'poor band count');
 -- site filtered
 PERFORM c10_test.as_user('sup1001'); r:=c10_demo.am_asset_health_report_v1(101); PERFORM c10_test.eqn(r->>'total',5,'1001 total'); PERFORM c10_test.eq(c10_test.hi(r,'CRN-1')::text,NULL,'no crane for 1001');
 PERFORM c10_test.as_user('bo102'); PERFORM c10_test.eqn((c10_demo.am_asset_health_report_v1(102))->>'total',2,'102 total');
END $$;
RESET ROLE;
-- policy: declining balance + category override 'none'
INSERT INTO c10_demo.am_policy(business_id,tenant_id,scope_type,scope_id,key,value,updated_by) VALUES(101,1,'business',0,'finance.depreciation_method','"declining_balance"',c10_test.u('bo101'));
SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb; h jsonb; m int:=(SELECT (extract(year FROM age(c10_test.today()::timestamp,c10_test.dt(400)::timestamp))*12+extract(month FROM age(c10_test.today()::timestamp,c10_test.dt(400)::timestamp)))::int);
BEGIN PERFORM c10_test.as_user('bo101'); r:=c10_demo.am_asset_health_report_v1(101); h:=c10_test.hi(r,'CHL-1');
 PERFORM c10_test.eq(h#>>'{depreciation,method}','declining_balance','DB method');
 PERFORM c10_test.eqn(h#>>'{depreciation,book_value}',round(GREATEST(10000,100000*power(0.8,m/12.0)),2),'DB book value'); END $$;
RESET ROLE;
INSERT INTO c10_demo.am_policy(business_id,tenant_id,scope_type,scope_id,key,value,updated_by) VALUES(101,1,'category',c10_test.catid(101,'COLD'),'finance.depreciation_method','"none"',c10_test.u('bo101'));
SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb; h jsonb; BEGIN PERFORM c10_test.as_user('bo101'); r:=c10_demo.am_asset_health_report_v1(101); h:=c10_test.hi(r,'CHL-1');
 PERFORM c10_test.eqn(h#>>'{depreciation,accumulated}',0,'none => 0'); PERFORM c10_test.eq(h#>>'{depreciation,reason}','method_none','none reason'); END $$;
RESET ROLE;
DELETE FROM c10_demo.am_policy WHERE business_id=101 AND key LIKE 'finance.%';

-- ===================================================== S6 warranty report =====================================================
SET LOCAL ROLE authenticated;
DO $$
DECLARE r jsonb;
BEGIN
 PERFORM c10_test.as_user('bo101'); r:=c10_demo.am_warranty_report_v1(101);
 PERFORM c10_test.eq(r#>>'{warranties,counts}','{"void": 1, "active": 2, "expired": 1, "expiring": 1}','warranty counts (policy horizon 60)');
 PERFORM c10_test.eq(r#>>'{warranties,expiring,0,asset_no}','CHL-1','expiring asset'); PERFORM c10_test.eqn(r#>>'{warranties,expiring,0,days_left}',20,'days left');
 PERFORM c10_test.eq(r#>>'{warranties,expired,0,asset_no}','CNV-1','expired asset');
 PERFORM c10_test.eq(r#>>'{claims,by_status}','{"draft": 1, "closed": 0, "settled": 1, "accepted": 0, "rejected": 1, "submitted": 1}','claims by state');
 PERFORM c10_test.eqn(r#>>'{claims,total}',4,'claims total'); PERFORM c10_test.eqn(r#>>'{claims,amount_settled}',500,'settled'); PERFORM c10_test.eq(r#>>'{claims,advisory}','true','claims advisory');
 PERFORM c10_test.eqn(jsonb_array_length(r#>'{recurring_failures_in_warranty,items}')::text,1,'recurring in warranty');
 PERFORM c10_test.eq(r#>>'{recurring_failures_in_warranty,items,0,failure_code}','MECH','recurring code'); PERFORM c10_test.eqn(r#>>'{recurring_failures_in_warranty,items,0,count}',3,'recurring count');
 -- explicit horizon overrides policy
 PERFORM c10_test.eq((c10_demo.am_warranty_report_v1(101,10))#>>'{warranties,counts}','{"void": 1, "active": 3, "expired": 1, "expiring": 0}','horizon 10');
 PERFORM c10_test.eq((c10_demo.am_warranty_report_v1(101,120))#>>'{warranties,counts}','{"void": 1, "active": 1, "expired": 1, "expiring": 2}','horizon 120');
 -- per-site and isolation
 PERFORM c10_test.as_user('sup1001'); r:=c10_demo.am_warranty_report_v1(101);
 PERFORM c10_test.eq(r#>>'{warranties,counts}','{"void": 1, "active": 1, "expired": 0, "expiring": 1}','1001 counts'); PERFORM c10_test.eqn(r#>>'{claims,total}',1,'1001 claims');
 PERFORM c10_test.eqn(jsonb_array_length(r#>'{recurring_failures_in_warranty,items}')::text,0,'1001 no recurring');
 PERFORM c10_test.as_user('bo102'); r:=c10_demo.am_warranty_report_v1(102); PERFORM c10_test.eq(r#>>'{warranties,counts}','{"void": 0, "active": 1, "expired": 0, "expiring": 0}','102 counts');
 PERFORM c10_test.eqn(r#>>'{claims,total}',0,'102 claims');
 PERFORM c10_test.as_user('owner2'); PERFORM c10_test.eq((c10_demo.am_warranty_report_v1(201))#>>'{warranties,counts}','{"void": 0, "active": 0, "expired": 0, "expiring": 0}','201 counts');
END $$;
RESET ROLE;
-- policy: asset.warranty_warn_days (site/category scoped)
INSERT INTO c10_demo.am_policy(business_id,tenant_id,scope_type,scope_id,key,value,updated_by) VALUES(101,1,'business',0,'asset.warranty_warn_days','10',c10_test.u('bo101'));
SET LOCAL ROLE authenticated;
DO $$ BEGIN PERFORM c10_test.as_user('bo101');
 PERFORM c10_test.eq((c10_demo.am_warranty_report_v1(101))#>>'{warranties,counts}','{"void": 1, "active": 3, "expired": 1, "expiring": 0}','policy warn days 10'); END $$;
RESET ROLE;
DELETE FROM c10_demo.am_policy WHERE business_id=101 AND key='asset.warranty_warn_days';

-- ===================================================== S7 reconciliation =====================================================
CREATE FUNCTION c10_test.cls(r jsonb,p_code text,p_f text) RETURNS text LANGUAGE sql IMMUTABLE AS $$ SELECT c->>p_f FROM jsonb_array_elements(r->'classes') c WHERE c->>'code'=p_code $$;
CREATE FUNCTION c10_test.cls_ids(r jsonb,p_code text) RETURNS text LANGUAGE sql IMMUTABLE AS $$ SELECT (c->'sample_ids')::text FROM jsonb_array_elements(r->'classes') c WHERE c->>'code'=p_code $$;
GRANT EXECUTE ON FUNCTION c10_test.cls(jsonb,text,text),c10_test.cls_ids(jsonb,text) TO authenticated;
SET LOCAL ROLE authenticated;
DO $$
DECLARE r jsonb;
BEGIN
 PERFORM c10_test.as_user('bo101'); r:=c10_demo.am_reconciliation_v1(101);
 PERFORM c10_test.eq(r->>'ok','false','101 is inconsistent'); PERFORM c10_test.eqn(r->>'total_mismatches',9,'9 seeded mismatches'); PERFORM c10_test.eqn(jsonb_array_length(r->'classes')::text,9,'9 classes');
 PERFORM c10_test.eq(c10_test.cls_ids(r,'completed_breakdown_wo_without_ended_downtime'),'['||c10_test.k('BD4')||']','class1');
 PERFORM c10_test.eq(c10_test.cls_ids(r,'breakdown_downtime_without_wo'),'['||c10_test.k('DT-POS')||']','class2');
 PERFORM c10_test.eq(c10_test.cls_ids(r,'asset_breakdown_without_open_downtime'),'['||c10_test.k('MIX-1')||']','class3');
 PERFORM c10_test.eq(c10_test.cls_ids(r,'open_downtime_on_non_breakdown_asset'),'['||c10_test.k('DT-GEN')||']','class4');
 PERFORM c10_test.eq(c10_test.cls_ids(r,'open_wo_on_retired_asset'),'['||c10_test.k('O7')||']','class5');
 PERFORM c10_test.eqn(c10_test.cls(r,'meter_decrease_without_reset','count'),1,'class6 (reset not flagged)');
 PERFORM c10_test.eq(c10_test.cls_ids(r,'plan_target_on_closed_plan'),'['||c10_test.k('T6')||']','class7');
 PERFORM c10_test.eq(c10_test.cls_ids(r,'wo_site_differs_from_asset'),'['||c10_test.k('O8')||']','class8');
 PERFORM c10_test.eq(c10_test.cls_ids(r,'child_site_differs_from_parent'),'['||c10_test.k('CNV-1M')||']','class9');
 -- time scope excludes the old events; state-based classes remain
 r:=c10_demo.am_reconciliation_v1(101,c10_test.dt(3)::date,c10_test.dt(1)::date);
 PERFORM c10_test.eqn(c10_test.cls(r,'completed_breakdown_wo_without_ended_downtime','count'),0,'time scoped 1'); PERFORM c10_test.eqn(c10_test.cls(r,'breakdown_downtime_without_wo','count'),0,'time scoped 2');
 PERFORM c10_test.eqn(c10_test.cls(r,'meter_decrease_without_reset','count'),0,'time scoped 6'); PERFORM c10_test.eqn(c10_test.cls(r,'asset_breakdown_without_open_downtime','count'),1,'state class kept');
 -- site-limited supervisor sees only the 1001 slice
 PERFORM c10_test.as_user('sup1001'); r:=c10_demo.am_reconciliation_v1(101);
 PERFORM c10_test.eqn(r->>'total_mismatches',5,'1001 slice'); PERFORM c10_test.eqn(c10_test.cls(r,'completed_breakdown_wo_without_ended_downtime','count'),0,'1001 class1');
 PERFORM c10_test.eqn(c10_test.cls(r,'open_wo_on_retired_asset','count'),0,'1001 class5'); PERFORM c10_test.eqn(c10_test.cls(r,'child_site_differs_from_parent','count'),0,'1001 class9');
 -- clean business reports ok; other businesses/tenants unaffected
 PERFORM c10_test.as_user('bo102'); r:=c10_demo.am_reconciliation_v1(102); PERFORM c10_test.eq(r->>'ok','true','102 clean'); PERFORM c10_test.eqn(r->>'total_mismatches',0,'102 zero');
 PERFORM c10_test.as_user('owner2'); PERFORM c10_test.eq((c10_demo.am_reconciliation_v1(201))->>'ok','true','201 clean');
END $$;
RESET ROLE;
-- policy downtime.end_on=verified: a merely COMPLETED breakdown WO is not expected to have an ended window yet; allow_decrease silences meter class
INSERT INTO c10_demo.am_policy(business_id,tenant_id,scope_type,scope_id,key,value,updated_by) VALUES
 (101,1,'business',0,'downtime.end_on','"verified"',c10_test.u('bo101')),(101,1,'business',0,'meter.allow_decrease','true',c10_test.u('bo101'));
SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb; BEGIN PERFORM c10_test.as_user('bo101'); r:=c10_demo.am_reconciliation_v1(101);
 PERFORM c10_test.eqn(c10_test.cls(r,'completed_breakdown_wo_without_ended_downtime','count'),0,'end_on verified'); PERFORM c10_test.eqn(c10_test.cls(r,'meter_decrease_without_reset','count'),0,'allow_decrease');
 PERFORM c10_test.eqn(r->>'total_mismatches',7,'7 left'); END $$;
RESET ROLE;
DELETE FROM c10_demo.am_policy WHERE business_id=101 AND key IN('downtime.end_on','meter.allow_decrease');
