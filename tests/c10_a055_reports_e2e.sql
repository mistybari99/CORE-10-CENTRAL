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
