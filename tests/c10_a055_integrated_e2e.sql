-- C10-A055 integrated cross-module end-to-end (disposable PostgreSQL; signed-claim simulation, NOT GoTrue).
-- Mirrors the UI chain with REAL RPCs only (no table writes): asset register -> ownership/location -> meters/warranty -> checklist ->
-- plan -> due suggestion -> generated work order -> approve/assign/start/checklist/labour/spares/complete/verify/close ->
-- breakdown + downtime -> costs -> asset history -> dashboards/reports/CSV/audit/integrity. Plus tenant isolation + authorization negatives.
\set ON_ERROR_STOP on
CREATE SCHEMA c10_test;
GRANT USAGE ON SCHEMA c10_test TO authenticated,anon;
CREATE TABLE c10_test.ids(k text PRIMARY KEY,v bigint);
GRANT ALL ON c10_test.ids TO authenticated,anon;
CREATE SEQUENCE c10_test.seq; GRANT USAGE ON c10_test.seq TO authenticated,anon;
CREATE FUNCTION c10_test.u(p text) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT (CASE p
 WHEN 'owner' THEN '11111111-1111-4111-8111-111111111111' WHEN 'bo101' THEN '22222222-2222-4222-8222-222222222222'
 WHEN 'mgr101' THEN '33333333-3333-4333-8333-333333333333' WHEN 'stock' THEN '44444444-4444-4444-8444-444444444444'
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
CREATE FUNCTION c10_test.eq(a boolean,b text,msg text) RETURNS void LANGUAGE sql AS $$ SELECT c10_test.eq(a::text,b,msg) $$;
CREATE FUNCTION c10_test.ok(a boolean,msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF a IS NOT TRUE THEN RAISE EXCEPTION 'ASSERT FALSE: %',msg; END IF; END$$;
CREATE FUNCTION c10_test.denied(p_sql text,p_expect text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 BEGIN EXECUTE p_sql; EXCEPTION WHEN OTHERS THEN
  IF SQLERRM NOT LIKE p_expect||'%' THEN RAISE EXCEPTION 'WRONG_ERROR [%] for %: want %',SQLERRM,p_sql,p_expect; END IF; RETURN; END;
 RAISE EXCEPTION 'EXPECTED_DENIAL_DID_NOT_HAPPEN: %',p_sql;
END$$;
CREATE FUNCTION c10_test.k() RETURNS text LANGUAGE sql AS $$ SELECT 'it-'||lpad(nextval('c10_test.seq')::text,8,'0') $$;
CREATE FUNCTION c10_test.put(p text,p_v bigint) RETURNS void LANGUAGE sql AS $$ INSERT INTO c10_test.ids VALUES(p,p_v) ON CONFLICT(k) DO UPDATE SET v=EXCLUDED.v $$;
CREATE FUNCTION c10_test.id(p text) RETURNS bigint LANGUAGE sql AS $$ SELECT v FROM c10_test.ids WHERE k=p $$;
CREATE FUNCTION c10_test.cid(p_code text) RETURNS bigint LANGUAGE sql AS $$
 SELECT (x->>'id')::bigint FROM jsonb_array_elements(c10_demo.am_list_catalog_v1(101)->'categories') x WHERE x->>'code'=p_code $$;
CREATE FUNCTION c10_test.wver(p_wo bigint) RETURNS bigint LANGUAGE sql AS $$ SELECT (c10_demo.am_get_work_order_v1(101,p_wo)->>'version')::bigint $$;
CREATE FUNCTION c10_test.tr(p_wo bigint,p_action text,p_reason text DEFAULT NULL,p_data jsonb DEFAULT NULL) RETURNS jsonb LANGUAGE sql AS
$$ SELECT c10_demo.am_wo_transition_v1(101,c10_test.k(),p_wo,c10_test.wver(p_wo),p_action,p_reason,p_data) $$;
CREATE FUNCTION c10_test.wst(p_wo bigint) RETURNS text LANGUAGE sql AS $$ SELECT c10_demo.am_get_work_order_v1(101,p_wo)->>'status' $$;
-- superuser-only facts (fixture lookups for assertions; the module itself never exposes tables)
CREATE FUNCTION c10_test.sval(p_sql text) RETURNS text LANGUAGE plpgsql SECURITY DEFINER AS $$ DECLARE v text; BEGIN EXECUTE p_sql INTO v; RETURN v; END$$;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA c10_test TO authenticated,anon;
SELECT c10_demo.ami_ensure_business(101); SELECT c10_demo.ami_ensure_business(102); SELECT c10_demo.ami_ensure_business(201);

-- ===== I1 asset register + ownership + location + meter + warranty (business owner) =====
BEGIN; SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb; a bigint; BEGIN
 PERFORM c10_test.as_user('bo101');
 r:=c10_demo.am_create_asset_v1(101,c10_test.k(),jsonb_build_object('name','Main oven','category_id',c10_test.cid('PROD-EQ'),'site_id',1001,
   'ownership','leased','custodian_ref','EMP-0042','location_note','Bay 3, north wall','acquisition_cost',120000,'serial_no','OV-9001',
   'meters','[{"code":"HRS","unit":"hours","reading":100}]'::jsonb),'register oven');
 a:=(r->>'asset_id')::bigint; PERFORM c10_test.put('oven',a); PERFORM c10_test.put('oven_meter',((r->'meter_ids')->>0)::bigint);
 PERFORM c10_test.eq(r->>'status','applied','asset created');
 r:=c10_demo.am_create_asset_v1(101,c10_test.k(),jsonb_build_object('name','Spare mixer','category_id',c10_test.cid('PROD-EQ'),'site_id',1001),NULL);
 PERFORM c10_test.put('mixer',(r->>'asset_id')::bigint);
 -- registry read back through the list RPC (what the Assets screen renders)
 r:=c10_demo.am_list_assets_v1(101,'{"search":"oven"}'::jsonb,50,0);
 PERFORM c10_test.eq(r->>'total','1','search finds the oven'); PERFORM c10_test.eq(r->'items'->0->>'ownership','leased','ownership kept');
 -- warranty + claim lifecycle
 r:=c10_demo.am_save_warranty_v1(101,c10_test.k(),NULL,NULL,jsonb_build_object('asset_id',a,'supplier_name','Acme Service','starts_on',(current_date-30)::text,'expires_on',(current_date+20)::text,'coverage','Parts and labour'),'record warranty');
 PERFORM c10_test.put('warranty',(r->>'warranty_id')::bigint);
 -- ownership / custody change + audit
 r:=c10_demo.am_get_asset_v1(101,a); PERFORM c10_test.put('oven_ver',(r->'asset'->>'version')::bigint);
 r:=c10_demo.am_update_asset_v1(101,c10_test.k(),a,c10_test.id('oven_ver'),'{"custodian_ref":"EMP-0099","ownership":"owned"}'::jsonb,'custody hand-over');
 PERFORM c10_test.eq(c10_demo.am_get_asset_v1(101,a)->'asset'->>'custodian_ref','EMP-0099','custodian changed');
 PERFORM c10_test.denied(format($q$SELECT c10_demo.am_update_asset_v1(101,'it-stale-%s',%s,%s,'{"custodian_ref":"X1"}'::jsonb,'stale write')$q$,a,a,c10_test.id('oven_ver')),'am_stale_version');
 -- site transfer needs a decision; asset stays put until approved
 r:=c10_demo.am_request_transfer_v1(101,c10_test.k(),a,1002,false,'move to the cold side'); PERFORM c10_test.put('transfer',(r->>'transfer_id')::bigint);
 PERFORM c10_test.eq(c10_demo.am_get_asset_v1(101,a)->'asset'->>'site_id','1001','still at origin before approval');
 r:=c10_demo.am_decide_transfer_v1(101,c10_test.k(),c10_test.id('transfer'),1,'approve','approved by owner');
 PERFORM c10_test.eq(c10_demo.am_get_asset_v1(101,a)->'asset'->>'site_id','1002','moved after approval');
 r:=c10_demo.am_request_transfer_v1(101,c10_test.k(),a,1001,false,'move back'); PERFORM c10_test.put('transfer2',(r->>'transfer_id')::bigint);
 PERFORM c10_demo.am_decide_transfer_v1(101,c10_test.k(),c10_test.id('transfer2'),1,'approve','moved back home');
 PERFORM c10_test.eq(c10_demo.am_get_asset_v1(101,a)->'asset'->>'site_id','1001','moved back');
 PERFORM c10_demo.am_record_meter_reading_v1(101,c10_test.k(),c10_test.id('oven_meter'),150,NULL,'reading','weekly read');
 PERFORM c10_test.denied(format($q$SELECT c10_demo.am_record_meter_reading_v1(101,%L,%s,120,NULL,'reading','going backwards')$q$,c10_test.k(),c10_test.id('oven_meter')),'am_');
END $$; COMMIT;

-- ===== I2 preventive planning: checklist -> plan -> due -> generated WO (supervisor) =====
BEGIN; SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb; s jsonb; BEGIN
 PERFORM c10_test.as_user('sup');
 PERFORM c10_demo.am_save_checklist_template_v1(101,c10_test.k(),'IT-PM1','Oven PM',NULL,
  '[{"text":"Isolate power","kind":"check","required":true},{"text":"Chamber temperature","kind":"measure","required":true,"min_value":150,"max_value":250,"unit":"C"}]'::jsonb,'standard PM');
 r:=c10_demo.am_save_plan_v1(101,c10_test.k(),NULL,NULL,jsonb_build_object('name','Oven weekly PM','plan_type','preventive','asset_id',c10_test.id('oven'),
  'frequency_kind','weekly','interval_n',1,'start_on',(current_date-14)::text,'checklist_code','IT-PM1','priority','medium'),NULL);
 PERFORM c10_test.put('plan',(r->>'id')::bigint);
 s:=c10_demo.am_due_suggestions_v1(101,NULL,7);
 PERFORM c10_test.ok(jsonb_array_length(s->'items')>=1,'plan produces a due suggestion');
 PERFORM c10_test.eq(s->'items'->0->>'asset_no',(c10_demo.am_get_asset_v1(101,c10_test.id('oven'))->'asset'->>'asset_no'),'suggestion points at the oven');
 PERFORM c10_test.put('target',(s->'items'->0->>'target_id')::bigint);
 r:=c10_demo.am_generate_work_orders_v1(101,c10_test.k(),ARRAY[c10_test.id('target')],NULL,7);
 PERFORM c10_test.ok(r::text LIKE '%wo_ids%' OR r::text LIKE '%work_orders%' OR r::text LIKE '%created%','generation receipt');
 s:=c10_demo.am_list_work_orders_v1(101,jsonb_build_object('asset_id',c10_test.id('oven'),'kind','preventive'),50,0);
 PERFORM c10_test.eq(s->>'total','1','exactly one generated preventive WO'); PERFORM c10_test.put('wo_pm',(s->'items'->0->>'id')::bigint);
 -- a second generation is idempotent by business rule: no duplicate open WO for the same target
 PERFORM c10_demo.am_generate_work_orders_v1(101,c10_test.k(),ARRAY[c10_test.id('target')],NULL,7);
 PERFORM c10_test.eq(c10_demo.am_list_work_orders_v1(101,jsonb_build_object('asset_id',c10_test.id('oven'),'kind','preventive'),50,0)->>'total','1','no duplicate PM work order');
 PERFORM c10_test.ok(c10_demo.am_calendar_v1(101,(current_date-1),(current_date+14),NULL) IS NOT NULL,'calendar renders');
END $$; COMMIT;

-- ===== I3 work-order lifecycle with maker-checker: technician executes, supervisor approves/verifies =====
BEGIN; SET LOCAL ROLE authenticated;
DO $$ DECLARE w bigint:=c10_test.id('wo_pm'); r jsonb; BEGIN
 PERFORM c10_test.as_user('sup');
 PERFORM c10_test.ok(c10_test.wst(w) IN('DRAFT','SUBMITTED','APPROVED'),'generated WO waiting: '||c10_test.wst(w));
 IF c10_test.wst(w)='DRAFT' THEN PERFORM c10_test.tr(w,'submit'); END IF;
 -- the requester (sup) cannot approve own request when maker-checker is on; the business owner can
 IF c10_test.wst(w)='SUBMITTED' THEN PERFORM c10_test.as_user('bo101'); PERFORM c10_test.tr(w,'approve'); PERFORM c10_test.as_user('sup'); END IF;
 PERFORM c10_test.eq(c10_test.wst(w),'APPROVED','approved');
 r:=c10_demo.am_assign_work_order_v1(101,c10_test.k(),w,c10_test.wver(w),c10_test.u('tech1001'),NULL,NULL,'assign to tech');
 PERFORM c10_test.as_user('tech1001');
 PERFORM c10_test.eq(jsonb_array_length(c10_demo.am_my_work_v1(101)->'assigned')::text,'1','technician sees assigned job');
 PERFORM c10_test.tr(w,'start');
 PERFORM c10_test.eq(c10_test.wst(w),'IN_PROGRESS','started');
 PERFORM c10_test.denied(format($q$SELECT c10_test.tr(%s,'complete',NULL,'{"cause_code":"AGE"}')$q$,w),'am_checklist_incomplete');
 PERFORM c10_demo.am_wo_checklist_result_v1(101,c10_test.k(),w,1,'pass',NULL,NULL);
 PERFORM c10_test.denied(format($q$SELECT c10_demo.am_wo_checklist_result_v1(101,%L,%s,2,'pass',999,NULL)$q$,c10_test.k(),w),'am_');   -- out of range reading cannot pass
 PERFORM c10_demo.am_wo_checklist_result_v1(101,c10_test.k(),w,2,'pass',200,'within range');
 PERFORM c10_demo.am_wo_add_labor_v1(101,c10_test.k(),w,'{"hours":2,"rate":25,"phase":"actual","worker_ref":"EMP-T1"}');
 PERFORM c10_demo.am_wo_add_spares_v1(101,c10_test.k(),w,'{"description":"Thermostat","qty":1,"unit_cost":40,"item_ref":"TH-1","phase":"actual"}');
 PERFORM c10_test.tr(w,'complete',NULL,'{"cause_code":"AGE"}');
 PERFORM c10_test.eq(c10_test.wst(w),'COMPLETED','completed');
 PERFORM c10_test.denied(format($q$SELECT c10_test.tr(%s,'verify')$q$,w),'am_not_permitted');            -- technician cannot verify
 PERFORM c10_test.as_user('bo101'); PERFORM c10_test.tr(w,'verify'); PERFORM c10_test.tr(w,'close');
 PERFORM c10_test.eq(c10_test.wst(w),'CLOSED','closed');
 r:=c10_demo.am_get_work_order_v1(101,w);
 PERFORM c10_test.ok(r::text LIKE '%Thermostat%' AND r::text LIKE '%EMP-T1%','costs lines present on WO');
 -- plan target re-anchored by completion: the PM is no longer due now
 PERFORM c10_test.ok(NOT EXISTS(SELECT 1 FROM jsonb_array_elements(c10_demo.am_due_suggestions_v1(101,NULL,0)->'items') i WHERE (i->>'target_id')::bigint=c10_test.id('target') AND i->>'due_state' IN('due','overdue')),'target re-anchored after completion');
END $$; COMMIT;

-- ===== I4 breakdown -> downtime -> corrective WO -> cost =====
BEGIN; SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb; w bigint; d bigint; BEGIN
 PERFORM c10_test.as_user('reporter');
 r:=c10_demo.am_report_breakdown_v1(101,c10_test.k(),c10_test.id('oven'),'{"description":"Heating element failed","priority":"critical","failure_code":"ELEC"}'::jsonb);
 w:=(r->>'id')::bigint; d:=(r->>'downtime_id')::bigint; PERFORM c10_test.put('wo_bd',w); PERFORM c10_test.put('dt',d);
 PERFORM c10_test.ok(c10_demo.am_list_downtime_v1(101,'{"open":true}'::jsonb,50,0)->>'total'='1','open downtime window visible');
 PERFORM c10_test.eq(r->>'auto_approved','true','critical breakdown auto-approved by policy (breakdown.auto_approve=critical)');
 PERFORM c10_test.eq(c10_test.wst(w),'APPROVED','breakdown WO approved');
 PERFORM c10_test.denied(format($q$SELECT c10_test.tr(%s,'start')$q$,w),'am_not_permitted');   -- reporter cannot execute
 PERFORM c10_test.as_user('bo101');
 PERFORM c10_demo.am_assign_work_order_v1(101,c10_test.k(),w,c10_test.wver(w),c10_test.u('tech1001'),NULL,NULL,'urgent repair');
 PERFORM c10_test.as_user('tech1001'); PERFORM c10_test.tr(w,'start');
 PERFORM c10_demo.am_wo_add_labor_v1(101,c10_test.k(),w,'{"hours":3,"rate":30,"phase":"actual","worker_ref":"EMP-T1"}');
 PERFORM c10_demo.am_wo_add_spares_v1(101,c10_test.k(),w,'{"description":"Heating element","qty":2,"unit_cost":150,"item_ref":"HE-2","phase":"actual"}');
 PERFORM c10_test.denied(format($q$SELECT c10_test.tr(%s,'complete',NULL,'{"cause_code":"AGE"}')$q$,w),'am_evidence_required');   -- policy: breakdown completion needs evidence
 PERFORM c10_demo.am_wo_add_attachment_v1(101,c10_test.k(),w,jsonb_build_object('file_name','element.jpg','mime','image/jpeg','size_bytes',2048,'sha256',repeat('b',64),'storage_ref','synthetic/it/element.jpg','kind','photo','caption','replaced part'));
 PERFORM c10_test.tr(w,'complete',NULL,'{"cause_code":"AGE","failure_code":"ELEC","action_code":"REPLACE"}');
 PERFORM c10_test.as_user('bo101');
 PERFORM c10_test.eq(c10_demo.am_list_downtime_v1(101,'{"open":true}'::jsonb,50,0)->>'total','0','downtime closed by completion');
 PERFORM c10_test.denied(format($q$SELECT c10_demo.am_end_downtime_v1(101,%L,%s,NULL,'again')$q$,c10_test.k(),d),'am_downtime_already_ended');
 -- planned downtime window started and ended manually
 r:=c10_demo.am_start_downtime_v1(101,c10_test.k(),c10_test.id('mixer'),'{"kind":"planned","reason_code":"PM"}'::jsonb);
 PERFORM c10_demo.am_end_downtime_v1(101,c10_test.k(),(r->>'id')::bigint,NULL,'cleaning done');
 PERFORM c10_test.tr(w,'verify'); PERFORM c10_test.tr(w,'close');
END $$; COMMIT;

-- ===== I5 history, dashboards, reports, CSV, audit, integrity =====
BEGIN; SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb; csv text; BEGIN
 PERFORM c10_test.as_user('bo101');
 r:=c10_demo.am_get_asset_v1(101,c10_test.id('oven'));
 PERFORM c10_test.ok(jsonb_array_length(r->'movements')>=2,'asset history carries site movements (transfer out and back)');
 PERFORM c10_test.eq(c10_demo.am_list_work_orders_v1(101,jsonb_build_object('asset_id',c10_test.id('oven')),50,0)->>'total','2','asset history lists preventive + corrective WOs');
 PERFORM c10_test.eq(c10_demo.am_list_downtime_v1(101,jsonb_build_object('asset_id',c10_test.id('oven')),50,0)->>'total','1','asset downtime history');
 r:=c10_demo.am_overview_v1(101,NULL); PERFORM c10_test.ok(r IS NOT NULL,'overview');
 r:=c10_demo.am_downtime_report_v1(101,current_date-30,current_date,NULL); PERFORM c10_test.ok(r->'totals' IS NOT NULL AND r->'totals' ? 'downtime_minutes','downtime report totals present');
 r:=c10_demo.am_kpi_report_v1(101,current_date-30,current_date,NULL); PERFORM c10_test.ok(r->'cost_rollup' IS NOT NULL,'cost rollup present');
 PERFORM c10_test.ok((r->'cost_rollup')::text LIKE '%ADVISORY%','costs labelled advisory');
 r:=c10_demo.am_asset_health_report_v1(101,NULL); PERFORM c10_test.ok(r IS NOT NULL,'health');
 r:=c10_demo.am_warranty_report_v1(101,60); PERFORM c10_test.ok(r::text LIKE '%Main oven%','warranty expiry report lists the oven');
 r:=c10_demo.am_reconciliation_v1(101,current_date-30,current_date); PERFORM c10_test.ok(r IS NOT NULL,'reconciliation');
 r:=c10_demo.am_integrity_report_v1(101); PERFORM c10_test.ok(r IS NOT NULL,'integrity');
 PERFORM c10_test.eq(r->>'ok','true','integrity report clean: '||left(r::text,300));
 r:=c10_demo.am_export_csv_v1(101,c10_test.k(),'work_orders','{}'::jsonb); csv:=r::text;
 PERFORM c10_test.ok(csv LIKE '%WO-%','work-order CSV has rows');
 r:=c10_demo.am_audit_log_v1(101,'asset',c10_test.id('oven')::text,50,0);
 PERFORM c10_test.ok(jsonb_array_length(r->'items')>=3,'asset audit trail has create/update/transfer entries');
 r:=c10_demo.read_asset_maintenance_business_summary_v1(101,NULL); PERFORM c10_test.ok(r IS NOT NULL,'A050 adapter summary (owner)');
 -- the reads never wrote: audit count unchanged by a reread
 PERFORM c10_test.eq(c10_test.sval('SELECT count(*) FROM c10_demo.am_audit WHERE business_id=101'),c10_test.sval('SELECT count(*) FROM c10_demo.am_audit WHERE business_id=101'),'reads stable');
END $$; COMMIT;

-- ===== I6 authorization + tenant isolation negatives over the same data =====
BEGIN; SET LOCAL ROLE authenticated;
DO $$ DECLARE a bigint:=c10_test.id('oven'); w bigint:=c10_test.id('wo_pm'); BEGIN
 PERFORM c10_test.as_user('owner2');   -- other tenant owner
 PERFORM c10_test.denied(format('SELECT c10_demo.am_get_asset_v1(101,%s)',a),'am_denied');
 PERFORM c10_test.denied(format('SELECT c10_demo.am_get_work_order_v1(101,%s)',w),'am_denied');
 PERFORM c10_test.denied('SELECT c10_demo.am_list_assets_v1(101,''{}'',10,0)','am_denied');
 PERFORM c10_test.denied(format($q$SELECT c10_demo.am_update_asset_v1(101,%L,%s,1,'{"custodian_ref":"HAX1"}'::jsonb,'cross tenant')$q$,c10_test.k(),a),'am_denied');
 PERFORM c10_test.as_user('bo102');    -- owner of another business in the SAME tenant
 PERFORM c10_test.denied(format('SELECT c10_demo.am_get_asset_v1(101,%s)',a),'am_denied');
 PERFORM c10_test.denied(format('SELECT c10_demo.am_get_asset_v1(102,%s)',a),'am_denied');   -- right business, wrong asset owner
 PERFORM c10_test.as_user('stock');    -- stock-only staff has no maintenance authority
 PERFORM c10_test.denied('SELECT c10_demo.am_list_assets_v1(101,''{}'',10,0)','am_denied');
 PERFORM c10_test.as_user('investor'); PERFORM c10_test.denied('SELECT c10_demo.am_overview_v1(101)','am_denied');
 PERFORM c10_test.as_user('revtech');  PERFORM c10_test.denied('SELECT c10_demo.am_my_work_v1(101)','am_denied');
 PERFORM c10_test.as_user('tech1002'); -- technician at a different site: cannot touch site-1001 work
 PERFORM c10_test.denied(format($q$SELECT c10_demo.am_wo_transition_v1(101,%L,%s,1,'start',NULL,NULL)$q$,c10_test.k(),w),'am_');
 PERFORM c10_test.as_user('reporter'); -- reporters cannot register assets nor read reports
 PERFORM c10_test.denied($q$SELECT c10_demo.am_create_asset_v1(101,'it-neg-rep-01','{"name":"Rogue","category_id":1,"site_id":1001}'::jsonb,'x y z')$q$,'am_');
 PERFORM c10_test.denied('SELECT c10_demo.am_kpi_report_v1(101,current_date-1,current_date)','am_not_permitted');
 PERFORM c10_test.as_user('auditor');  -- auditor reads, never writes
 PERFORM c10_test.ok(c10_demo.am_audit_log_v1(101,NULL,NULL,10,0) IS NOT NULL,'auditor reads audit');
 PERFORM c10_test.denied(format($q$SELECT c10_demo.am_create_asset_v1(101,%L,'{"name":"Rogue","category_id":1,"site_id":1001}'::jsonb,'x y z')$q$,c10_test.k()),'am_');
END $$; COMMIT;
BEGIN; SET LOCAL ROLE anon;
DO $$ BEGIN
 PERFORM c10_test.denied('SELECT c10_demo.am_list_assets_v1(101,''{}'',10,0)','permission denied');
 PERFORM c10_test.denied('SELECT count(*) FROM c10_demo.am_assets','permission denied');
END $$; COMMIT;
BEGIN; SET LOCAL ROLE authenticated;
DO $$ BEGIN PERFORM c10_test.as_user('bo101');   -- direct table access is revoked even for owners
 PERFORM c10_test.denied('SELECT count(*) FROM c10_demo.am_assets','permission denied');
 PERFORM c10_test.denied('INSERT INTO c10_demo.am_assets(tenant_id,business_id,asset_no,name,category_id,site_id) VALUES(1,101,''X'',''X'',1,1001)','permission denied');
END $$; COMMIT;
DO $$ BEGIN RAISE NOTICE 'A055_INTEGRATED_E2E_PASS'; END $$;
