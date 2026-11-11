-- C10-A051 disposable PostgreSQL end-to-end test. Signed-claim SIMULATION only (NOT Supabase GoTrue).
-- Run after A018 + seed + A051 sql + tests/c10_a051_workforce_seed.sql. Synthetic data only.
\set ON_ERROR_STOP on
CREATE SCHEMA c10_test;
GRANT USAGE ON SCHEMA c10_test TO authenticated,anon;
CREATE FUNCTION c10_test.u(p text) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT (CASE p
 WHEN 'owner' THEN '11111111-1111-4111-8111-111111111111' WHEN 'bo101' THEN '22222222-2222-4222-8222-222222222222'
 WHEN 'mgr101' THEN '33333333-3333-4333-8333-333333333333' WHEN 'e4' THEN '44444444-4444-4444-8444-444444444444'
 WHEN 'investor' THEN '55555555-5555-4555-8555-555555555555' WHEN 'revoked' THEN '66666666-6666-4666-8666-666666666666'
 WHEN 'owner2' THEN '77777777-7777-4777-8777-777777777777' WHEN 'staff2' THEN '88888888-8888-4888-8888-888888888888'
 WHEN 'operator' THEN '99999999-9999-4999-8999-999999999999' WHEN 'sup' THEN 'a1111111-1111-4111-8111-111111111111'
 WHEN 'e1' THEN 'a2222222-2222-4222-8222-222222222222' WHEN 'e3' THEN 'a3333333-3333-4333-8333-333333333333'
 WHEN 'e5' THEN 'a5555555-5555-4555-8555-555555555555' WHEN 'e6' THEN 'a6666666-6666-4666-8666-666666666666'
 WHEN 'mgr102' THEN 'b1111111-1111-4111-8111-111111111111' WHEN 'bo102' THEN 'b2222222-2222-4222-8222-222222222222'
 WHEN 'bo201' THEN 'c1111111-1111-4111-8111-111111111111' WHEN 'emp201' THEN 'c2222222-2222-4222-8222-222222222222' END)::uuid $$;
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
CREATE FUNCTION c10_test.eid(p_business bigint,p_no text) RETURNS bigint LANGUAGE sql SECURITY DEFINER AS
$$ SELECT id FROM c10_demo.wf_employees WHERE business_id=p_business AND employee_no=p_no $$;
CREATE FUNCTION c10_test.line(p_run bigint,p_no text,p_col text) RETURNS text LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v text; BEGIN EXECUTE format('SELECT %I::text FROM c10_demo.wf_payroll_lines WHERE run_id=$1 AND employee_no=$2',p_col) INTO v USING p_run,p_no; RETURN v; END$$;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA c10_test TO authenticated,anon;

-- ===== S1 authority matrix BEFORE any workforce data: stock/site grants never imply workforce access =====
BEGIN; SET LOCAL ROLE authenticated;
DO $$ BEGIN
 PERFORM c10_test.as_user('e4'); -- site staff with stock.read/post only
 PERFORM c10_test.denied('SELECT c10_demo.wf_read_overview_v1(101)','wf_denied');
 PERFORM c10_test.denied('SELECT c10_demo.wf_list_employees_v1(101,NULL,NULL,NULL,10,0)','wf_denied');
 PERFORM c10_test.as_user('investor'); PERFORM c10_test.denied('SELECT c10_demo.wf_read_overview_v1(101)','wf_denied');
 PERFORM c10_test.as_user('revoked');  PERFORM c10_test.denied('SELECT c10_demo.wf_read_overview_v1(101)','wf_denied');
 PERFORM c10_test.as_user('owner2');   PERFORM c10_test.denied('SELECT c10_demo.wf_read_overview_v1(101)','wf_denied');
 PERFORM c10_test.as_user('staff2');   PERFORM c10_test.denied('SELECT c10_demo.wf_read_overview_v1(101)','wf_denied');
 PERFORM c10_test.as_user('operator'); PERFORM c10_test.denied('SELECT c10_demo.wf_read_overview_v1(101)','wf_denied');
 PERFORM c10_test.as_user('mgr102');   PERFORM c10_test.denied('SELECT c10_demo.wf_read_overview_v1(101)','wf_denied');
 PERFORM c10_test.as_user('bo102');    PERFORM c10_test.denied('SELECT c10_demo.wf_read_overview_v1(101)','wf_denied');
 PERFORM c10_test.as_user('mgr101');
 PERFORM c10_test.eq(c10_demo.wf_read_overview_v1(101)->>'level','manager','manager level');
 PERFORM c10_test.eq(c10_demo.wf_read_overview_v1(101)->'capabilities'->>'payroll','false','manager no payroll');
 PERFORM c10_test.as_user('owner'); PERFORM c10_test.eq(c10_demo.wf_read_overview_v1(101)->>'level','tenant_owner','owner level');
 PERFORM c10_test.eq(c10_demo.wf_read_overview_v1(102)->>'level','tenant_owner','owner sees second business');
 PERFORM c10_test.as_user('bo101'); PERFORM c10_test.eq(c10_demo.wf_read_overview_v1(101)->>'level','business_owner','bo level');
 PERFORM c10_test.denied('SELECT c10_demo.wf_read_overview_v1(102)','wf_denied');
 PERFORM c10_test.denied('SELECT c10_demo.wf_read_overview_v1(NULL)','wf_denied');
 -- direct table access is closed even for owners
 PERFORM c10_test.denied('SELECT count(*) FROM c10_demo.wf_employees','permission denied');
 PERFORM c10_test.denied('SELECT count(*) FROM c10_demo.wf_payslips','permission denied');
 PERFORM c10_test.denied('INSERT INTO c10_demo.wf_employees(tenant_id,business_id,employee_no,full_name,joined_on,status,contract_type,created_by) VALUES(1,101,''X1'',''Hack'',now(),''active'',''permanent'',c10_demo.actor_uid())','permission denied');
 PERFORM c10_test.denied('SELECT c10_demo.wfi_ctx(101)','permission denied');
END $$; COMMIT;
BEGIN; SET LOCAL ROLE anon;
DO $$ BEGIN
 PERFORM c10_test.denied('SELECT c10_demo.wf_read_overview_v1(101)','permission denied');
 PERFORM c10_test.denied('SELECT c10_demo.read_workforce_business_summary_v1(101,NULL)','permission denied');
END $$; COMMIT;
-- unauthenticated claim (no sub) fails closed
BEGIN; SET LOCAL ROLE authenticated;
DO $$ BEGIN PERFORM set_config('request.jwt.claim.sub','',true);
 PERFORM c10_test.denied('SELECT c10_demo.wf_read_overview_v1(101)','wf_denied'); END $$; COMMIT;

-- ===== S2 owner configuration (business owner 2222 / tenant owner) =====
BEGIN; SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb; BEGIN
 PERFORM c10_test.as_user('mgr101');
 PERFORM c10_test.denied($q$SELECT c10_demo.wf_save_department_v1(101,'dept-req-0001','OPS','Operations',true,'manager attempt')$q$,'wf_owner_required');
 PERFORM c10_test.denied($q$SELECT c10_demo.wf_save_shift_v1(101,'shift-req-0001',0,'{"code":"DAY","name":"Day","start_time":"09:00","end_time":"18:00"}'::jsonb,'manager attempt')$q$,'wf_owner_required');
 PERFORM c10_test.as_user('bo101');
 PERFORM c10_demo.wf_save_settings_v1(101,'cfg-req-00001',1,'{"overtime_requires_approval":true}'::jsonb,'confirm defaults explicit');
 r:=c10_demo.wf_save_settings_v1(101,'cfg-req-00001',1,'{"overtime_requires_approval":true}'::jsonb,'confirm defaults explicit');
 PERFORM c10_test.eq(r->>'version','2','settings replay returns same receipt');
 PERFORM c10_test.denied($q$SELECT c10_demo.wf_save_settings_v1(101,'cfg-req-00001',1,'{"overtime_requires_approval":false}'::jsonb,'confirm defaults explicit')$q$,'wf_idempotency_conflict');
 PERFORM c10_test.denied($q$SELECT c10_demo.wf_save_settings_v1(101,'cfg-req-00002',1,'{"half_day_ratio":0.5}'::jsonb,'stale write')$q$,'wf_stale_version');
 PERFORM c10_test.denied($q$SELECT c10_demo.wf_save_settings_v1(101,'cfg-req-00003',2,'{"unknown_key":1}'::jsonb,'bad key')$q$,'wf_unknown_setting');
 PERFORM c10_test.denied($q$SELECT c10_demo.wf_save_settings_v1(101,'cfg-req-00004',2,'{"half_day_ratio":7}'::jsonb,'bad value')$q$,'wf_invalid_setting_value');
 PERFORM c10_test.denied($q$SELECT c10_demo.wf_save_settings_v1(101,'cfg-req-00005',2,'{"require_maker_checker":false}'::jsonb,'loosen control')$q$,'wf_tenant_owner_required');
 PERFORM c10_test.denied($q$SELECT c10_demo.wf_save_settings_v1(101,'short',2,'{}'::jsonb,'bad key shape')$q$,'wf_invalid_request_key');
 PERFORM c10_demo.wf_save_department_v1(101,'dept-req-0002','OPS','Operations',true,'create department');
 PERFORM c10_demo.wf_save_department_v1(101,'dept-req-0003','SALES','Sales',true,'create department');
 PERFORM c10_demo.wf_save_shift_v1(101,'shift-req-0002',0,'{"code":"DAY","name":"Day 9-6","start_time":"09:00","end_time":"18:00","break_minutes":60,"grace_late_minutes":10,"min_overtime_minutes":30}'::jsonb,'day shift');
 PERFORM c10_demo.wf_save_shift_v1(101,'shift-req-0003',0,'{"code":"NIGHT","name":"Night 22-06","start_time":"22:00","end_time":"06:00","break_minutes":30,"grace_late_minutes":10,"min_overtime_minutes":30}'::jsonb,'overnight shift');
 PERFORM c10_test.denied($q$SELECT c10_demo.wf_save_shift_v1(101,'shift-req-0004',0,'{"code":"BAD","name":"Bad","start_time":"09:00","end_time":"09:00"}'::jsonb,'zero length')$q$,'wf_invalid_shift_length');
 PERFORM c10_test.denied($q$SELECT c10_demo.wf_save_shift_v1(101,'shift-req-0005',0,'{"code":"DAY","name":"Dup","start_time":"09:00","end_time":"18:00"}'::jsonb,'stale create of existing')$q$,'wf_stale_version');
 PERFORM c10_demo.wf_save_leave_type_v1(101,'lt-req-000001',0,'{"code":"ANNUAL","name":"Annual","paid":true,"annual_quota_days":10}'::jsonb,'annual leave');
 PERFORM c10_demo.wf_save_leave_type_v1(101,'lt-req-000002',0,'{"code":"SICK","name":"Sick","paid":true,"annual_quota_days":14}'::jsonb,'sick leave');
 PERFORM c10_demo.wf_save_leave_type_v1(101,'lt-req-000003',0,'{"code":"UNPAID","name":"Unpaid","paid":false}'::jsonb,'unpaid leave');
 PERFORM c10_demo.wf_save_pay_policy_v1(101,'pp-req-000001',0,'{"code":"MONTHLY","name":"Monthly","pay_basis":"monthly","ot_multiplier_weekday":2.0,"ot_multiplier_offday":2.0,"late_to_absent_days":3}'::jsonb,'monthly policy');
 PERFORM c10_demo.wf_save_pay_policy_v1(101,'pp-req-000002',0,'{"code":"MONTHLY20","name":"Monthly /20","pay_basis":"monthly","monthly_divisor":20}'::jsonb,'divisor policy');
 PERFORM c10_demo.wf_save_pay_policy_v1(101,'pp-req-000003',0,'{"code":"DAILY","name":"Daily wage","pay_basis":"daily"}'::jsonb,'daily policy');
 PERFORM c10_demo.wf_save_pay_policy_v1(101,'pp-req-000004',0,'{"code":"HOURLY","name":"Hourly","pay_basis":"hourly","ot_multiplier_weekday":2.0}'::jsonb,'hourly policy');
 PERFORM c10_test.denied($q$SELECT c10_demo.wf_save_pay_policy_v1(101,'pp-req-000005',1,'{"code":"MONTHLY","name":"x","pay_basis":"daily"}'::jsonb,'basis change')$q$,'wf_pay_basis_immutable');
 PERFORM c10_demo.wf_save_component_v1(101,'pc-req-000001',0,'{"code":"TRANSPORT","name":"Transport allowance","kind":"allowance","calc_type":"fixed","amount":1000}'::jsonb,'allowance');
 PERFORM c10_demo.wf_save_component_v1(101,'pc-req-000002',0,'{"code":"MEDICAL","name":"Medical allowance","kind":"allowance","calc_type":"percent_of_base","amount":10}'::jsonb,'allowance pct');
 PERFORM c10_demo.wf_save_component_v1(101,'pc-req-000003',0,'{"code":"UNIFORM","name":"Uniform deduction","kind":"deduction","calc_type":"fixed","amount":200}'::jsonb,'deduction');
 r:=c10_demo.wf_save_component_v1(101,'pc-req-000004',0,'{"code":"PF","name":"Provident fund (policy unverified)","kind":"deduction","calc_type":"percent_of_base","amount":5,"statutory":true,"apply_to_all":true}'::jsonb,'statutory stays OFF');
 PERFORM c10_test.eq(r->>'approval_status','pending_owner_approval','statutory component defaults OFF');
 PERFORM c10_test.denied($q$SELECT c10_demo.wf_save_component_v1(101,'pc-req-000005',1,'{"code":"PF","name":"PF","kind":"deduction","calc_type":"percent_of_base","amount":5,"statutory":true,"approval_status":"active"}'::jsonb,'bo cannot activate')$q$,'wf_statutory_requires_tenant_owner');
 PERFORM c10_test.denied($q$SELECT c10_demo.wf_save_component_v1(101,'pc-req-000006',0,'{"code":"BADPCT","name":"x","kind":"allowance","calc_type":"percent_of_base","amount":150}'::jsonb,'over 100 pct')$q$,'wf_invalid_input');
 PERFORM c10_test.as_user('owner'); -- tenant owner may relax maker-checker but we keep the safe default
 PERFORM c10_demo.wf_save_settings_v1(101,'cfg-req-00006',2,'{"leave_review_level":"manager","manager_can_approve_corrections":false}'::jsonb,'explicit safe defaults');
END $$; COMMIT;

-- ===== S3 employee master =====
BEGIN; SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb; BEGIN
 PERFORM c10_test.as_user('mgr101');
 PERFORM c10_test.denied($q$SELECT c10_demo.wf_save_employee_v1(101,'emp-req-00000',NULL,NULL,'{"employee_no":"EMP-000","full_name":"Nope Nope","joined_on":"2026-01-01","contract_type":"permanent","site_id":1001}'::jsonb,'manager default denied')$q$,'wf_employee_edit_denied');
 PERFORM c10_test.as_user('bo101');
 r:=c10_demo.wf_save_employee_v1(101,'emp-req-00001',NULL,NULL,'{"employee_no":"EMP-001","full_name":"Rahim Ahmed","joined_on":"2026-01-01","contract_type":"permanent","site_id":1001,"department_code":"OPS","designation":"Operator","contact_phone":"+880171000001","national_id_last4":"1234","user_id":"a2222222-2222-4222-8222-222222222222"}'::jsonb,'hire');
 PERFORM c10_test.eq(r->>'status','created','create employee');
 PERFORM c10_test.eq(c10_demo.wf_save_employee_v1(101,'emp-req-00001',NULL,NULL,'{"employee_no":"EMP-001","full_name":"Rahim Ahmed","joined_on":"2026-01-01","contract_type":"permanent","site_id":1001,"department_code":"OPS","designation":"Operator","contact_phone":"+880171000001","national_id_last4":"1234","user_id":"a2222222-2222-4222-8222-222222222222"}'::jsonb,'hire')->>'employee_id',r->>'employee_id','replay returns same employee');
 PERFORM c10_demo.wf_save_employee_v1(101,'emp-req-00002',NULL,NULL,'{"employee_no":"EMP-002","full_name":"Karim Sarker","joined_on":"2026-01-01","contract_type":"permanent","site_id":1001,"designation":"Line Supervisor","is_supervisor":true,"user_id":"a1111111-1111-4111-8111-111111111111"}'::jsonb,'hire supervisor');
 PERFORM c10_demo.wf_save_employee_v1(101,'emp-req-00003',NULL,NULL,'{"employee_no":"EMP-003","full_name":"Salma Begum","joined_on":"2026-02-01","contract_type":"daily","site_id":1002,"user_id":"a3333333-3333-4333-8333-333333333333"}'::jsonb,'hire daily staff other site');
 PERFORM c10_demo.wf_save_employee_v1(101,'emp-req-00004',NULL,NULL,'{"employee_no":"EMP-004","full_name":"Hasan Hossain","joined_on":"2026-02-01","contract_type":"hourly","site_id":1001}'::jsonb,'hire hourly staff (login linked later)');
 PERFORM c10_demo.wf_save_employee_v1(101,'emp-req-00005',NULL,NULL,'{"employee_no":"EMP-005","full_name":"Tania Terminated","joined_on":"2026-01-01","contract_type":"permanent","site_id":1001,"user_id":"a5555555-5555-4555-8555-555555555555"}'::jsonb,'hire to terminate');
 PERFORM c10_demo.wf_save_employee_v1(101,'emp-req-00006',NULL,NULL,'{"employee_no":"EMP-006","full_name":"Nasir Night","joined_on":"2026-01-01","contract_type":"permanent","site_id":1001,"user_id":"a6666666-6666-4666-8666-666666666666"}'::jsonb,'hire night shift');
 PERFORM c10_demo.wf_save_employee_v1(101,'emp-req-00007',NULL,NULL,'{"employee_no":"EMP-007","full_name":"Rina Capped","joined_on":"2026-01-01","contract_type":"permanent","site_id":1001}'::jsonb,'cap case');
 PERFORM c10_demo.wf_save_employee_v1(101,'emp-req-00008',NULL,NULL,'{"employee_no":"EMP-008","full_name":"=HYPERLINK(\"http://x\")","joined_on":"2026-01-01","contract_type":"permanent","site_id":1002}'::jsonb,'formula-like name');
 PERFORM c10_demo.wf_save_employee_v1(101,'emp-req-00009',NULL,NULL,'{"employee_no":"EMP-009","full_name":"Imran Intern","joined_on":"2026-03-01","contract_type":"intern","site_id":1001}'::jsonb,'no salary yet');
 PERFORM c10_test.denied($q$SELECT c10_demo.wf_save_employee_v1(101,'emp-req-00010',NULL,NULL,'{"employee_no":"EMP-001","full_name":"Dup Number","joined_on":"2026-01-01","contract_type":"permanent","site_id":1001}'::jsonb,'dup no')$q$,'wf_employee_no_duplicate');
 PERFORM c10_test.denied($q$SELECT c10_demo.wf_save_employee_v1(101,'emp-req-00011',NULL,NULL,'{"employee_no":"EMP-010","full_name":"Dup Link","joined_on":"2026-01-01","contract_type":"permanent","site_id":1001,"user_id":"a2222222-2222-4222-8222-222222222222"}'::jsonb,'dup link')$q$,'wf_user_already_linked');
 PERFORM c10_test.denied($q$SELECT c10_demo.wf_save_employee_v1(101,'emp-req-00012',NULL,NULL,'{"employee_no":"EMP-011","full_name":"Wrong Site","joined_on":"2026-01-01","contract_type":"permanent","site_id":1003}'::jsonb,'other business site')$q$,'wf_site_not_in_business');
 PERFORM c10_test.denied($q$SELECT c10_demo.wf_save_employee_v1(101,'emp-req-00013',NULL,NULL,'{"employee_no":"EMP-012","full_name":"Future Joiner","joined_on":"2030-01-01","contract_type":"permanent","site_id":1001}'::jsonb,'future')$q$,'wf_invalid_input');
 PERFORM c10_test.denied($q$SELECT c10_demo.wf_save_employee_v1(101,'emp-req-00014',NULL,NULL,'{"employee_no":"EMP-013","full_name":"Bad NID","joined_on":"2026-01-01","contract_type":"permanent","site_id":1001,"national_id_last4":"12345678"}'::jsonb,'full NID rejected')$q$,'wf_invalid_input');
 PERFORM c10_test.denied($q$SELECT c10_demo.wf_save_employee_v1(101,'emp-req-00015',NULL,NULL,'{"employee_no":"EMP-014","full_name":"Bad Contract","joined_on":"2026-01-01","contract_type":"slave","site_id":1001}'::jsonb,'enum')$q$,'wf_invalid_input');
 -- update with optimistic version
 PERFORM c10_demo.wf_save_employee_v1(101,'emp-req-00016',c10_test.eid(101,'EMP-004'),1,'{"full_name":"Hasan Hossain","user_id":"44444444-4444-4444-8444-444444444444"}'::jsonb,'link login');
 PERFORM c10_test.denied(format($q$SELECT c10_demo.wf_save_employee_v1(101,'emp-req-00017',%s,1,'{"full_name":"Stale Edit"}'::jsonb,'stale')$q$,c10_test.eid(101,'EMP-004')),'wf_stale_version');
 PERFORM c10_test.denied(format($q$SELECT c10_demo.wf_save_employee_v1(101,'emp-req-00018',%s,2,'{"employee_no":"EMP-444"}'::jsonb,'renumber')$q$,c10_test.eid(101,'EMP-004')),'wf_employee_no_immutable');
 -- terminate EMP-005 (history kept, never deleted)
 PERFORM c10_demo.wf_set_employment_v1(101,'emp-req-00019',c10_test.eid(101,'EMP-005'),'2026-06-30','terminated','permanent','resigned 30 June');
 PERFORM c10_test.denied(format($q$SELECT c10_demo.wf_set_employment_v1(101,'emp-req-00020',%s,'2030-01-01','inactive','permanent','future')$q$,c10_test.eid(101,'EMP-005')),'wf_invalid_effective_date');
 PERFORM c10_test.as_user('e5'); PERFORM c10_test.denied('SELECT c10_demo.wf_read_overview_v1(101)','wf_denied'); -- terminated login is dead
 -- second business / tenant isolation fixtures
 PERFORM c10_test.as_user('bo102');
 PERFORM c10_demo.wf_save_employee_v1(102,'emp-req-10001',NULL,NULL,'{"employee_no":"EMP-001","full_name":"Other Biz Person","joined_on":"2026-01-01","contract_type":"permanent","site_id":1003}'::jsonb,'same number allowed in another business');
 PERFORM c10_test.as_user('bo201');
 PERFORM c10_demo.wf_save_employee_v1(201,'emp-req-20001',NULL,NULL,'{"employee_no":"EMP-001","full_name":"Customer Tenant Person","joined_on":"2026-01-01","contract_type":"permanent","site_id":2001,"user_id":"c2222222-2222-4222-8222-222222222222"}'::jsonb,'tenant 2 employee');
END $$; COMMIT;

-- ===== S4 shifts assignment, salary structures, components =====
BEGIN; SET LOCAL ROLE authenticated;
DO $$ DECLARE n text; BEGIN
 PERFORM c10_test.as_user('sup');
 PERFORM c10_test.denied(format($q$SELECT c10_demo.wf_assign_shift_v1(101,'shf-req-00000',%s,'DAY','2026-01-01','supervisor cannot schedule')$q$,c10_test.eid(101,'EMP-001')),'wf_manager_required');
 PERFORM c10_test.as_user('mgr101');
 FOREACH n IN ARRAY ARRAY['EMP-001','EMP-002','EMP-007'] LOOP
  PERFORM c10_demo.wf_assign_shift_v1(101,'shf-'||n||'-aaa',c10_test.eid(101,n),'DAY','2026-01-01','day shift roster'); END LOOP;
 PERFORM c10_demo.wf_assign_shift_v1(101,'shf-EMP-004-aaa',c10_test.eid(101,'EMP-004'),'DAY','2026-02-01','day shift roster');
 PERFORM c10_demo.wf_assign_shift_v1(101,'shf-EMP-009-aaa',c10_test.eid(101,'EMP-009'),'DAY','2026-03-01','day shift roster');
 PERFORM c10_demo.wf_assign_shift_v1(101,'shf-EMP-003-aaa',c10_test.eid(101,'EMP-003'),'DAY','2026-02-01','day shift roster');
 PERFORM c10_demo.wf_assign_shift_v1(101,'shf-EMP-008-aaa',c10_test.eid(101,'EMP-008'),'DAY','2026-01-01','day shift roster');
 PERFORM c10_demo.wf_assign_shift_v1(101,'shf-EMP-006-aaa',c10_test.eid(101,'EMP-006'),'NIGHT','2026-01-01','night roster');
 PERFORM c10_test.denied(format($q$SELECT c10_demo.wf_set_salary_structure_v1(101,'sal-req-00000',%s,'MONTHLY',1000,'2026-01-01','manager denied')$q$,c10_test.eid(101,'EMP-001')),'wf_owner_required');
 PERFORM c10_test.as_user('bo101');
 PERFORM c10_demo.wf_set_salary_structure_v1(101,'sal-EMP-001-a',c10_test.eid(101,'EMP-001'),'MONTHLY',31000,'2026-01-01','offer letter');
 PERFORM c10_demo.wf_set_salary_structure_v1(101,'sal-EMP-002-a',c10_test.eid(101,'EMP-002'),'MONTHLY',62000,'2026-01-01','offer letter');
 PERFORM c10_demo.wf_set_salary_structure_v1(101,'sal-EMP-003-a',c10_test.eid(101,'EMP-003'),'DAILY',1200,'2026-02-01','offer letter');
 PERFORM c10_demo.wf_set_salary_structure_v1(101,'sal-EMP-004-a',c10_test.eid(101,'EMP-004'),'HOURLY',150,'2026-02-01','offer letter');
 PERFORM c10_demo.wf_set_salary_structure_v1(101,'sal-EMP-006-a',c10_test.eid(101,'EMP-006'),'MONTHLY',31000,'2026-01-01','offer letter');
 PERFORM c10_demo.wf_set_salary_structure_v1(101,'sal-EMP-007-a',c10_test.eid(101,'EMP-007'),'MONTHLY20',12345.67,'2026-01-01','offer letter');
 PERFORM c10_demo.wf_set_salary_structure_v1(101,'sal-EMP-008-a',c10_test.eid(101,'EMP-008'),'MONTHLY',99999999999.99,'2026-01-01','precision limit fixture');
 PERFORM c10_test.denied(format($q$SELECT c10_demo.wf_set_salary_structure_v1(101,'sal-req-00001',%s,'MONTHLY',100000000000,'2026-01-01','over limit')$q$,c10_test.eid(101,'EMP-001')),'wf_invalid_input');
 PERFORM c10_test.denied(format($q$SELECT c10_demo.wf_set_salary_structure_v1(101,'sal-req-00002',%s,'MONTHLY',100.001,'2026-01-01','sub-cent')$q$,c10_test.eid(101,'EMP-001')),'wf_invalid_input');
 PERFORM c10_test.denied(format($q$SELECT c10_demo.wf_set_salary_structure_v1(101,'sal-req-00003',%s,'MONTHLY',-5,'2026-01-01','negative')$q$,c10_test.eid(101,'EMP-001')),'wf_invalid_input');
 PERFORM c10_demo.wf_assign_component_v1(101,'asg-EMP-001-a',c10_test.eid(101,'EMP-001'),'TRANSPORT',true,NULL,'2026-01-01','allowance entitlement');
 PERFORM c10_demo.wf_assign_component_v1(101,'asg-EMP-001-b',c10_test.eid(101,'EMP-001'),'MEDICAL',true,NULL,'2026-01-01','allowance entitlement');
 PERFORM c10_demo.wf_assign_component_v1(101,'asg-EMP-001-c',c10_test.eid(101,'EMP-001'),'UNIFORM',true,NULL,'2026-01-01','uniform recovery');
 -- salary is owner-only data: manager/employee never see it
 PERFORM c10_test.as_user('mgr101');
 PERFORM c10_test.eq((c10_demo.wf_get_employee_v1(101,c10_test.eid(101,'EMP-001'))->'salary_structures')::text,'null','manager cannot see salary');
 PERFORM c10_test.eq((c10_demo.wf_get_employee_v1(101,c10_test.eid(101,'EMP-001'))->>'contact_phone'),NULL,'manager cannot see phone');
 PERFORM c10_test.eq((c10_demo.wf_get_employee_v1(101,c10_test.eid(101,'EMP-001'))->>'national_id_last4'),NULL,'manager cannot see national id');
 PERFORM c10_test.denied('SELECT c10_demo.wf_list_payroll_runs_v1(101)','wf_payroll_access_denied');
 PERFORM c10_test.denied('SELECT c10_demo.wf_payroll_preview_v1(101,''2026-10-01'')','wf_payroll_access_denied');
 PERFORM c10_test.as_user('bo101');
 PERFORM c10_test.eq(jsonb_array_length(c10_demo.wf_get_employee_v1(101,c10_test.eid(101,'EMP-001'))->'salary_structures')::text,'1','owner sees salary');
 PERFORM c10_test.eq((c10_demo.wf_get_employee_v1(101,c10_test.eid(101,'EMP-001'))->>'contact_phone'),'+880171000001','owner sees phone');
END $$; COMMIT;

-- ===== S5 holidays + punches (October 2026; Fridays off; Oct 20 company holiday) =====
BEGIN; SET LOCAL ROLE authenticated;
DO $$ DECLARE rows jsonb; res jsonb; BEGIN
 PERFORM c10_test.as_user('mgr101');
 PERFORM c10_test.denied($q$SELECT c10_demo.wf_save_holiday_v1(101,'hol-req-00000','2026-10-20','Company Day','company',true,NULL,true,'manager denied')$q$,'wf_owner_required');
 PERFORM c10_test.as_user('bo101');
 PERFORM c10_demo.wf_save_holiday_v1(101,'hol-req-00001','2026-10-20','Company Day','company',true,NULL,true,'annual company holiday');
 -- supervisor imports punches for own site staff (EMP-001): bounded import-ready DTO
 PERFORM c10_test.as_user('sup');
 SELECT jsonb_agg(x ORDER BY ord) INTO rows FROM (
  SELECT 1 ord,jsonb_build_array(jsonb_build_object('employee_no','EMP-001','at','2026-10-01T09:00:00+06:00','direction','in','ref','dev1-1'),
   jsonb_build_object('employee_no','EMP-001','at','2026-10-01T09:00:30+06:00','direction','in','ref','dev1-1b'),
   jsonb_build_object('employee_no','EMP-001','at','2026-10-01T18:00:00+06:00','direction','out','ref','dev1-2'),
   jsonb_build_object('employee_no','EMP-001','at','2026-10-01T18:00:00+06:00','direction','out','ref','dev1-2')) x) q;
 res:=c10_demo.wf_import_punches_v1(101,'imp-req-00001',1001,'device',rows->0);
 PERFORM c10_test.eq(res->>'accepted','2','two accepted punches');
 PERFORM c10_test.eq(res->>'duplicates','2','near-duplicate and duplicate ref collapsed');
 PERFORM c10_test.eq(c10_demo.wf_import_punches_v1(101,'imp-req-00001',1001,'device',rows->0)::text,res::text,'batch retry replays exactly');
 -- supervisor cannot import for another site, own punches, or unknown/foreign employees
 PERFORM c10_test.denied($q$SELECT c10_demo.wf_import_punches_v1(101,'imp-req-00002',1002,'device','[{"employee_no":"EMP-003","at":"2026-10-06T09:00:00+06:00","direction":"in"}]'::jsonb)$q$,'wf_punch_import_denied');
 res:=c10_demo.wf_import_punches_v1(101,'imp-req-00003',1001,'device','[{"employee_no":"EMP-002","at":"2026-10-06T09:00:00+06:00","direction":"in"},{"employee_no":"EMP-003","at":"2026-10-06T09:00:00+06:00","direction":"in"},{"employee_no":"NOPE","at":"2026-10-06T09:00:00+06:00","direction":"in"},{"employee_no":"EMP-001","at":"2026-10-06T09:00:00","direction":"in"},{"employee_no":"EMP-001","at":"2030-10-06T09:00:00+06:00","direction":"in"},{"employee_no":"EMP-001","at":"2026-10-06T09:00:00+06:00","direction":"sideways"}]'::jsonb);
 PERFORM c10_test.eq(res->>'accepted','0','nothing accepted from invalid/out-of-scope rows');
 PERFORM c10_test.eq(res->>'rejected','6','six rejected');
 PERFORM c10_test.denied($q$SELECT c10_demo.wf_import_punches_v1(101,'imp-req-00004',1001,'device','[]'::jsonb)$q$,'wf_invalid_input');
 PERFORM c10_test.as_user('e1'); PERFORM c10_test.denied($q$SELECT c10_demo.wf_import_punches_v1(101,'imp-req-00005',1001,'manual','[{"employee_no":"EMP-001","at":"2026-10-06T09:00:00+06:00","direction":"in"}]'::jsonb)$q$,'wf_punch_import_denied');
 -- manager imports full October history. Generate deterministic scenarios with plain SQL.
 PERFORM c10_test.as_user('mgr101');
 -- EMP-001 (monthly): see scenario table in docs/architecture/C10_A051_WORKFORCE_PAYROLL.md
 SELECT jsonb_agg(r ORDER BY (r->>'at')) INTO rows FROM (
  SELECT jsonb_build_object('employee_no','EMP-001','at',to_char(d,'YYYY-MM-DD')||'T'||
    CASE WHEN d IN('2026-10-12') THEN '09:30' WHEN d='2026-10-13' THEN '09:25' WHEN d='2026-10-14' THEN '09:40' ELSE '09:00' END||':00+06:00','direction','in','ref','e1-'||d||'-i') r
   FROM generate_series('2026-10-02'::date,'2026-10-31','1 day') d
   WHERE (extract(isodow FROM d)<>5 OR d='2026-10-09') AND d NOT IN('2026-10-05','2026-10-06','2026-10-07','2026-10-08','2026-10-20')
  UNION ALL
  SELECT jsonb_build_object('employee_no','EMP-001','at',to_char(d,'YYYY-MM-DD')||'T'||
    CASE WHEN d='2026-10-15' THEN '19:30' WHEN d='2026-10-19' THEN '12:00' WHEN d='2026-10-09' THEN '17:00' ELSE '18:00' END||':00+06:00','direction','out','ref','e1-'||d||'-o')
   FROM generate_series('2026-10-02'::date,'2026-10-31','1 day') d
   WHERE (extract(isodow FROM d)<>5 OR d='2026-10-09') AND d NOT IN('2026-10-05','2026-10-06','2026-10-07','2026-10-08','2026-10-20','2026-10-21')) x;
 res:=c10_demo.wf_import_punches_v1(101,'imp-req-00010',1001,'device',rows);
 PERFORM c10_test.eq(res->>'rejected','0','EMP-001 October punches all accepted');
 -- EMP-002 supervisor: perfect attendance on working days
 SELECT jsonb_agg(r) INTO rows FROM (
  SELECT jsonb_build_object('employee_no','EMP-002','at',to_char(d,'YYYY-MM-DD')||'T09:00:00+06:00','direction','in') r FROM generate_series('2026-10-01'::date,'2026-10-31','1 day') d WHERE extract(isodow FROM d)<>5 AND d<>'2026-10-20'
  UNION ALL SELECT jsonb_build_object('employee_no','EMP-002','at',to_char(d,'YYYY-MM-DD')||'T18:00:00+06:00','direction','out') FROM generate_series('2026-10-01'::date,'2026-10-31','1 day') d WHERE extract(isodow FROM d)<>5 AND d<>'2026-10-20') x;
 PERFORM c10_test.eq(c10_demo.wf_import_punches_v1(101,'imp-req-00011',1001,'device',rows)->>'rejected','0','EMP-002 punches accepted (manager imports for supervisor)');
 -- EMP-004 hourly (4 days)
 res:=c10_demo.wf_import_punches_v1(101,'imp-req-00012',1001,'device','[
  {"employee_no":"EMP-004","at":"2026-10-01T09:00:00+06:00","direction":"in"},{"employee_no":"EMP-004","at":"2026-10-01T18:00:00+06:00","direction":"out"},
  {"employee_no":"EMP-004","at":"2026-10-03T09:00:00+06:00","direction":"in"},{"employee_no":"EMP-004","at":"2026-10-03T18:00:00+06:00","direction":"out"},
  {"employee_no":"EMP-004","at":"2026-10-04T09:00:00+06:00","direction":"in"},{"employee_no":"EMP-004","at":"2026-10-04T14:00:00+06:00","direction":"out"},
  {"employee_no":"EMP-004","at":"2026-10-06T09:00:00+06:00","direction":"in"},{"employee_no":"EMP-004","at":"2026-10-06T19:00:00+06:00","direction":"out"}]'::jsonb);
 PERFORM c10_test.eq(res->>'accepted','8','EMP-004 punches');
 -- EMP-006 overnight shift incl. month boundary (Oct 31 22:00 -> Nov 1 06:05)
 res:=c10_demo.wf_import_punches_v1(101,'imp-req-00013',1001,'device','[
  {"employee_no":"EMP-006","at":"2026-10-01T21:55:00+06:00","direction":"in"},{"employee_no":"EMP-006","at":"2026-10-02T06:10:00+06:00","direction":"out"},
  {"employee_no":"EMP-006","at":"2026-10-31T21:58:00+06:00","direction":"in"},{"employee_no":"EMP-006","at":"2026-11-01T06:05:00+06:00","direction":"out"}]'::jsonb);
 PERFORM c10_test.eq(res->>'accepted','4','EMP-006 overnight punches');
 -- EMP-003 (other site 1002, daily): absent Oct 1,3,4,5 only
 SELECT jsonb_agg(r) INTO rows FROM (
  SELECT jsonb_build_object('employee_no','EMP-003','at',to_char(d,'YYYY-MM-DD')||'T09:00:00+06:00','direction','in') r FROM generate_series('2026-10-06'::date,'2026-10-31','1 day') d WHERE extract(isodow FROM d)<>5 AND d<>'2026-10-20'
  UNION ALL SELECT jsonb_build_object('employee_no','EMP-003','at',to_char(d,'YYYY-MM-DD')||'T18:00:00+06:00','direction','out') FROM generate_series('2026-10-06'::date,'2026-10-31','1 day') d WHERE extract(isodow FROM d)<>5 AND d<>'2026-10-20') x;
 PERFORM c10_test.eq(c10_demo.wf_import_punches_v1(101,'imp-req-00014',1002,'device',rows)->>'rejected','0','EMP-003 punches accepted');
 -- EMP-001 Oct 21: IN only -> incomplete (needs correction)
 PERFORM c10_demo.wf_import_punches_v1(101,'imp-req-00015',1001,'device','[{"employee_no":"EMP-001","at":"2026-10-21T09:00:00+06:00","direction":"in"}]'::jsonb);
 -- terminated employee punch rejected
 PERFORM c10_test.eq(c10_demo.wf_import_punches_v1(101,'imp-req-00016',1001,'device','[{"employee_no":"EMP-005","at":"2026-10-06T09:00:00+06:00","direction":"in"}]'::jsonb)->'results'->0->>'outcome','not_employed','terminated employee punch rejected');
END $$; COMMIT;
-- attendance derived values (live, Asia/Dhaka)
BEGIN; SET LOCAL ROLE authenticated;
DO $$ DECLARE a jsonb; BEGIN
 PERFORM c10_test.as_user('mgr101');
 a:=c10_demo.wf_list_attendance_v1(101,'2026-10-01','2026-10-31',c10_test.eid(101,'EMP-001'),NULL);
 PERFORM c10_test.eq((SELECT x->>'status' FROM jsonb_array_elements(a->'items') x WHERE x->>'date'='2026-10-01'),'present','Oct 1 present');
 PERFORM c10_test.eq((SELECT x->>'worked_minutes' FROM jsonb_array_elements(a->'items') x WHERE x->>'date'='2026-10-01'),'480','Oct 1 worked 9h-1h break');
 PERFORM c10_test.eq((SELECT x->>'late_minutes' FROM jsonb_array_elements(a->'items') x WHERE x->>'date'='2026-10-12'),'30','late minutes');
 PERFORM c10_test.eq((SELECT x->>'late_minutes' FROM jsonb_array_elements(a->'items') x WHERE x->>'date'='2026-10-02'),'0','Friday is weekly off, not late');
 PERFORM c10_test.eq((SELECT x->>'status' FROM jsonb_array_elements(a->'items') x WHERE x->>'date'='2026-10-02'),'weekly_off','Friday weekly off');
 PERFORM c10_test.eq((SELECT x->>'status' FROM jsonb_array_elements(a->'items') x WHERE x->>'date'='2026-10-20'),'holiday','company holiday');
 PERFORM c10_test.eq((SELECT x->>'status' FROM jsonb_array_elements(a->'items') x WHERE x->>'date'='2026-10-05'),'absent','Oct 5 absent');
 PERFORM c10_test.eq((SELECT x->>'status' FROM jsonb_array_elements(a->'items') x WHERE x->>'date'='2026-10-19'),'half_day','short day is half day');
 PERFORM c10_test.eq((SELECT x->>'overtime_minutes' FROM jsonb_array_elements(a->'items') x WHERE x->>'date'='2026-10-15'),'90','overtime computed');
 PERFORM c10_test.eq((SELECT x->>'overtime_decided' FROM jsonb_array_elements(a->'items') x WHERE x->>'date'='2026-10-15'),'false','overtime awaiting approval');
 PERFORM c10_test.eq((SELECT x->>'status' FROM jsonb_array_elements(a->'items') x WHERE x->>'date'='2026-10-21'),'incomplete','missing out punch');
 PERFORM c10_test.eq((SELECT x->>'status' FROM jsonb_array_elements(a->'items') x WHERE x->>'date'='2026-10-09'),'present','working a weekly off day');
 PERFORM c10_test.eq((SELECT x->>'overtime_minutes' FROM jsonb_array_elements(a->'items') x WHERE x->>'date'='2026-10-09'),'420','off-day work counts as overtime');
 a:=c10_demo.wf_list_attendance_v1(101,'2026-10-01','2026-11-02',c10_test.eid(101,'EMP-006'),NULL);
 PERFORM c10_test.eq((SELECT x->>'worked_minutes' FROM jsonb_array_elements(a->'items') x WHERE x->>'date'='2026-10-01'),'465','overnight shift worked minutes');
 PERFORM c10_test.eq((SELECT x->>'status' FROM jsonb_array_elements(a->'items') x WHERE x->>'date'='2026-10-01'),'present','overnight work date is shift start date');
 PERFORM c10_test.eq((SELECT x->>'status' FROM jsonb_array_elements(a->'items') x WHERE x->>'date'='2026-10-31'),'present','month-boundary overnight work date Oct 31');
 PERFORM c10_test.eq((SELECT x->>'overtime_minutes' FROM jsonb_array_elements(a->'items') x WHERE x->>'date'='2026-10-31'),'0','5 minutes after shift end below overtime minimum');
 PERFORM c10_test.eq((SELECT count(*) FROM jsonb_array_elements(a->'items') x WHERE x->>'date'='2026-11-01' AND x->>'status'='present')::text,'0','Nov 1 morning out-punch is not a new work day');
 PERFORM c10_test.denied('SELECT c10_demo.wf_list_attendance_v1(101,''2026-01-01'',''2026-12-31'',NULL,NULL)','wf_invalid_range');
 -- staff self-view vs supervisor scope
 PERFORM c10_test.as_user('e1');
 PERFORM c10_test.eq(jsonb_array_length(c10_demo.wf_list_attendance_v1(101,'2026-10-01','2026-10-03',NULL,NULL)->'items')::text,'3','employee sees only own 3 days');
 PERFORM c10_test.eq((SELECT count(DISTINCT x->>'employee_no') FROM jsonb_array_elements(c10_demo.wf_list_attendance_v1(101,'2026-10-01','2026-10-03',NULL,NULL)->'items') x)::text,'1','one employee only');
 PERFORM c10_test.denied(format('SELECT c10_demo.wf_list_punches_v1(101,%s,''2026-10-01'',''2026-10-03'')',c10_test.eid(101,'EMP-003')),'wf_employee_not_found');
 PERFORM c10_test.as_user('e3'); -- other site employee cannot see site-1001 colleague
 PERFORM c10_test.eq((SELECT count(DISTINCT x->>'employee_no') FROM jsonb_array_elements(c10_demo.wf_list_attendance_v1(101,'2026-10-06','2026-10-08',NULL,NULL)->'items') x)::text,'1','other-site employee sees only self');
 PERFORM c10_test.denied(format('SELECT c10_demo.wf_get_employee_v1(101,%s)',c10_test.eid(101,'EMP-001')),'wf_employee_not_found');
 PERFORM c10_test.as_user('sup');
 PERFORM c10_test.eq((SELECT count(DISTINCT x->>'employee_no') FROM jsonb_array_elements(c10_demo.wf_list_attendance_v1(101,'2026-10-06','2026-10-08',NULL,NULL)->'items') x)::text,'6','supervisor sees site-1001 staff (6 incl. self)');
 PERFORM c10_test.denied(format('SELECT c10_demo.wf_get_employee_v1(101,%s)',c10_test.eid(101,'EMP-003')),'wf_employee_not_found');
 PERFORM c10_test.denied('SELECT c10_demo.wf_payroll_preview_v1(101,''2026-10-01'')','wf_payroll_access_denied');
 PERFORM c10_test.eq(c10_demo.wf_list_employees_v1(101,NULL,NULL,NULL,50,0)->>'total','7','supervisor directory = site 1001 only');
 PERFORM c10_test.as_user('mgr101');
 PERFORM c10_test.eq(c10_demo.wf_list_employees_v1(101,NULL,NULL,NULL,50,0)->>'total','9','manager directory = whole business');
 PERFORM c10_test.eq((c10_demo.wf_list_employees_v1(101,'rahim',NULL,NULL,50,0)->'items'->0)->>'contact_phone',NULL,'manager directory hides phone');
 PERFORM c10_test.eq(c10_demo.wf_list_employees_v1(101,'%',NULL,NULL,50,0)->>'total','0','LIKE wildcard is escaped');
END $$; COMMIT;

-- ===== S6 leave & approval =====
BEGIN; SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb; l1 bigint; l2 bigint; l3 bigint; BEGIN
 PERFORM c10_test.as_user('e1');
 r:=c10_demo.wf_request_leave_v1(101,'lv-req-000001',NULL,'UNPAID','2026-10-06','2026-10-06','family matter');
 PERFORM c10_test.eq(r->>'status','pending','unpaid leave pending'); l1:=(r->>'leave_id')::bigint;
 r:=c10_demo.wf_request_leave_v1(101,'lv-req-000002',NULL,'ANNUAL','2026-10-07','2026-10-08','annual rest');
 PERFORM c10_test.eq(r->>'days','2','two leave days'); l2:=(r->>'leave_id')::bigint;
 PERFORM c10_test.denied($q$SELECT c10_demo.wf_request_leave_v1(101,'lv-req-000003',NULL,'SICK','2026-10-08','2026-10-09','overlap')$q$,'wf_leave_overlap');
 PERFORM c10_test.denied($q$SELECT c10_demo.wf_request_leave_v1(101,'lv-req-000004',NULL,'ANNUAL','2026-11-01','2026-11-30','too long vs quota')$q$,'wf_leave_quota_exceeded');
 PERFORM c10_test.denied($q$SELECT c10_demo.wf_request_leave_v1(101,'lv-req-000005',NULL,'ANNUAL','2026-12-30','2027-01-02','cross-year')$q$,'wf_leave_cross_year');
 PERFORM c10_test.denied($q$SELECT c10_demo.wf_request_leave_v1(101,'lv-req-000006',NULL,'ANNUAL','2026-10-02','2026-10-02','only a Friday')$q$,'wf_leave_no_working_days');
 PERFORM c10_test.denied($q$SELECT c10_demo.wf_request_leave_v1(101,'lv-req-000007',NULL,'NOPE','2026-11-23','2026-11-24','missing type')$q$,'wf_leave_type_not_found');
 PERFORM c10_test.denied(format($q$SELECT c10_demo.wf_request_leave_v1(101,'lv-req-000008',%s,'ANNUAL','2026-11-23','2026-11-24','for someone else')$q$,c10_test.eid(101,'EMP-003')),'wf_leave_request_denied');
 PERFORM c10_test.denied(format('SELECT c10_demo.wf_decide_leave_v1(101,''lv-req-000009'',%s,''approve'',''self approve'')',l1),'wf_leave_review_denied');
 PERFORM c10_test.as_user('sup');
 PERFORM c10_test.denied(format('SELECT c10_demo.wf_decide_leave_v1(101,''lv-req-000010'',%s,''approve'',''supervisor cannot approve'')',l1),'wf_leave_review_denied');
 PERFORM c10_test.as_user('mgr101');
 PERFORM c10_test.eq(c10_demo.wf_decide_leave_v1(101,'lv-req-000011',l1,'approve','approved by manager')->>'status','approved','manager approves');
 PERFORM c10_test.eq(c10_demo.wf_decide_leave_v1(101,'lv-req-000011',l1,'approve','approved by manager')->>'status','approved','decision replay');
 PERFORM c10_test.denied(format('SELECT c10_demo.wf_decide_leave_v1(101,''lv-req-000012'',%s,''approve'',''again'')',l1),'wf_leave_state_invalid');
 PERFORM c10_demo.wf_decide_leave_v1(101,'lv-req-000013',l2,'approve','approved by manager');
 PERFORM c10_test.eq(jsonb_array_length(c10_demo.wf_leave_balance_v1(101,c10_test.eid(101,'EMP-001'),2026)->'items')::text,'3','balance rows');
 PERFORM c10_test.eq((SELECT x->>'approved' FROM jsonb_array_elements(c10_demo.wf_leave_balance_v1(101,c10_test.eid(101,'EMP-001'),2026)->'items') x WHERE x->>'leave_type'='ANNUAL'),'2.0','annual used');
 -- future leave: reject / cancel / revoke paths
 PERFORM c10_test.as_user('e1');
 r:=c10_demo.wf_request_leave_v1(101,'lv-req-000014',NULL,'SICK','2026-11-23','2026-11-24','medical'); l3:=(r->>'leave_id')::bigint;
 PERFORM c10_test.as_user('mgr101');
 PERFORM c10_test.eq(c10_demo.wf_decide_leave_v1(101,'lv-req-000015',l3,'reject','insufficient notice')->>'status','rejected','rejected');
 PERFORM c10_test.as_user('e1');
 r:=c10_demo.wf_request_leave_v1(101,'lv-req-000016',NULL,'SICK','2026-11-25','2026-11-26','medical again'); l3:=(r->>'leave_id')::bigint;
 PERFORM c10_test.eq(c10_demo.wf_cancel_leave_v1(101,'lv-req-000017',l3,'plans changed')->>'status','cancelled','employee cancels own pending');
 PERFORM c10_test.as_user('e3'); PERFORM c10_test.denied(format('SELECT c10_demo.wf_cancel_leave_v1(101,''lv-req-000018'',%s,''not mine'')',l2),'wf_leave_cancel_denied');
 PERFORM c10_test.eq(jsonb_array_length(c10_demo.wf_list_leave_v1(101,NULL,NULL)->'items')::text,'0','other-site employee sees no foreign leave');
 PERFORM c10_test.as_user('e1');
 r:=c10_demo.wf_request_leave_v1(101,'lv-req-000019',NULL,'ANNUAL','2026-11-23','2026-11-25','planned rest'); l3:=(r->>'leave_id')::bigint;
 PERFORM c10_test.as_user('mgr101'); PERFORM c10_demo.wf_decide_leave_v1(101,'lv-req-000020',l3,'approve','ok approved');
 PERFORM c10_test.eq(c10_demo.wf_decide_leave_v1(101,'lv-req-000021',l3,'revoke','operational need')->>'status','revoked','revocation');
 -- leave type approval policy: strict owner-only review
 PERFORM c10_test.as_user('bo101');
 PERFORM c10_demo.wf_save_settings_v1(101,'cfg-req-00007',(SELECT (c10_demo.wf_read_overview_v1(101)->'settings'->>'version')::bigint),'{"leave_review_level":"owner"}'::jsonb,'owner-only leave review');
 PERFORM c10_test.as_user('e1');
 r:=c10_demo.wf_request_leave_v1(101,'lv-req-000022',NULL,'SICK','2026-11-23','2026-11-23','medical'); l3:=(r->>'leave_id')::bigint;
 PERFORM c10_test.as_user('mgr101'); PERFORM c10_test.denied(format('SELECT c10_demo.wf_decide_leave_v1(101,''lv-req-000023'',%s,''approve'',''manager blocked'')',l3),'wf_leave_review_denied');
 PERFORM c10_test.as_user('bo101'); PERFORM c10_test.eq(c10_demo.wf_decide_leave_v1(101,'lv-req-000024',l3,'reject','plan check')->>'status','rejected','owner decides');
 PERFORM c10_demo.wf_save_settings_v1(101,'cfg-req-00008',(SELECT (c10_demo.wf_read_overview_v1(101)->'settings'->>'version')::bigint),'{"leave_review_level":"manager"}'::jsonb,'restore default');
END $$; COMMIT;
-- leave: unpaid/paid attendance effects
BEGIN; SET LOCAL ROLE authenticated;
DO $$ DECLARE a jsonb; BEGIN
 PERFORM c10_test.as_user('mgr101');
 a:=c10_demo.wf_list_attendance_v1(101,'2026-10-05','2026-10-08',c10_test.eid(101,'EMP-001'),NULL);
 PERFORM c10_test.eq((SELECT x->>'status' FROM jsonb_array_elements(a->'items') x WHERE x->>'date'='2026-10-06'),'unpaid_leave','unpaid leave');
 PERFORM c10_test.eq((SELECT x->>'status' FROM jsonb_array_elements(a->'items') x WHERE x->>'date'='2026-10-07'),'paid_leave','paid leave');
END $$; COMMIT;

-- ===== S7 corrections & overtime & advances =====
BEGIN; SET LOCAL ROLE authenticated;
DO $$ DECLARE c1 bigint; r jsonb; adv bigint; BEGIN
 PERFORM c10_test.as_user('e1');
 PERFORM c10_test.denied(format($q$SELECT c10_demo.wf_request_correction_v1(101,'cor-req-00000',%s,'2026-10-21',NULL,'2026-10-21T18:00:00+06:00',NULL,'self fix attempt')$q$,c10_test.eid(101,'EMP-001')),'wf_correction_denied');
 PERFORM c10_test.as_user('sup');
 PERFORM c10_test.denied(format($q$SELECT c10_demo.wf_request_correction_v1(101,'cor-req-00001',%s,'2026-10-21',NULL,'2026-10-21T18:00:00+06:00',NULL,'self fix attempt')$q$,c10_test.eid(101,'EMP-002')),'wf_self_correction_denied');
 PERFORM c10_test.denied(format($q$SELECT c10_demo.wf_request_correction_v1(101,'cor-req-00002',%s,'2026-10-21',NULL,'2026-10-21T18:00:00+06:00',NULL,'other site')$q$,c10_test.eid(101,'EMP-003')),'wf_correction_denied');
 PERFORM c10_test.denied(format($q$SELECT c10_demo.wf_request_correction_v1(101,'cor-req-00003',%s,'2026-10-21','2026-10-21T20:00:00+06:00','2026-10-21T18:00:00+06:00',NULL,'out before in')$q$,c10_test.eid(101,'EMP-001')),'wf_invalid_correction_times');
 r:=c10_demo.wf_request_correction_v1(101,'cor-req-00004',c10_test.eid(101,'EMP-001'),'2026-10-21',NULL,'2026-10-21T18:00:00+06:00',NULL,'device missed the exit tap');
 c1:=(r->>'correction_id')::bigint;
 PERFORM c10_test.denied(format('SELECT c10_demo.wf_decide_correction_v1(101,''cor-req-00005'',%s,''approve'',''supervisor cannot approve'')',c1),'wf_correction_approval_denied');
 PERFORM c10_test.as_user('mgr101');
 PERFORM c10_test.denied(format('SELECT c10_demo.wf_decide_correction_v1(101,''cor-req-00006'',%s,''approve'',''manager default no'')',c1),'wf_correction_approval_denied');
 PERFORM c10_test.as_user('bo101');
 PERFORM c10_test.eq(c10_demo.wf_decide_correction_v1(101,'cor-req-00007',c1,'approve','verified against CCTV')->>'status','approved','owner approves correction');
 PERFORM c10_test.eq((SELECT x->>'status' FROM jsonb_array_elements(c10_demo.wf_list_attendance_v1(101,'2026-10-21','2026-10-21',c10_test.eid(101,'EMP-001'),NULL)->'items') x),'present','corrected day present');
 -- approver != requester
 r:=c10_demo.wf_request_correction_v1(101,'cor-req-00008',c10_test.eid(101,'EMP-004'),'2026-10-08','2026-10-08T09:00:00+06:00','2026-10-08T18:00:00+06:00',NULL,'worked but device offline');
 PERFORM c10_test.denied(format('SELECT c10_demo.wf_decide_correction_v1(101,''cor-req-00009'',%s,''approve'',''same person'')',(r->>'correction_id')),'wf_approver_must_differ');
 PERFORM c10_test.as_user('owner'); PERFORM c10_test.eq(c10_demo.wf_decide_correction_v1(101,'cor-req-00010',(r->>'correction_id')::bigint,'reject','no evidence')->>'status','rejected','rejected correction changes nothing');
 PERFORM c10_test.eq((SELECT x->>'status' FROM jsonb_array_elements(c10_demo.wf_list_attendance_v1(101,'2026-10-08','2026-10-08',c10_test.eid(101,'EMP-004'),NULL)->'items') x),'absent','rejected correction leaves absent');
 -- overtime decisions (maker = manager, not the employee)
 PERFORM c10_test.as_user('sup');
 PERFORM c10_test.denied(format($q$SELECT c10_demo.wf_decide_overtime_v1(101,'ot-req-000000',%s,'2026-10-15',60,'supervisor cannot')$q$,c10_test.eid(101,'EMP-001')),'wf_manager_required');
 PERFORM c10_test.as_user('mgr101');
 PERFORM c10_test.denied(format($q$SELECT c10_demo.wf_decide_overtime_v1(101,'ot-req-000001',%s,'2026-10-15',120,'more than worked')$q$,c10_test.eid(101,'EMP-001')),'wf_overtime_exceeds_computed');
 PERFORM c10_test.denied(format($q$SELECT c10_demo.wf_decide_overtime_v1(101,'ot-req-000002',%s,'2026-10-14',30,'no overtime that day')$q$,c10_test.eid(101,'EMP-001')),'wf_no_overtime_on_day');
 PERFORM c10_demo.wf_decide_overtime_v1(101,'ot-req-000003',c10_test.eid(101,'EMP-001'),'2026-10-15',60,'approve one hour');
 PERFORM c10_demo.wf_decide_overtime_v1(101,'ot-req-000004',c10_test.eid(101,'EMP-001'),'2026-10-09',420,'weekly-off work approved');
 PERFORM c10_demo.wf_decide_overtime_v1(101,'ot-req-000005',c10_test.eid(101,'EMP-004'),'2026-10-06',60,'approve one hour');
 -- advances (constrained policy input; never a payout)
 PERFORM c10_test.as_user('e1');
 r:=c10_demo.wf_request_advance_v1(101,'adv-req-000001',NULL,3000,1000,'2026-10-01','festival advance'); adv:=(r->>'advance_id')::bigint;
 PERFORM c10_test.denied($q$SELECT c10_demo.wf_request_advance_v1(101,'adv-req-000002',NULL,1000,2000,'2026-10-01','installment>amount')$q$,'wf_invalid_input');
 PERFORM c10_test.denied($q$SELECT c10_demo.wf_request_advance_v1(101,'adv-req-000003',NULL,1000,100,'2026-10-15','not first of month')$q$,'wf_invalid_input');
 PERFORM c10_test.denied(format('SELECT c10_demo.wf_decide_advance_v1(101,''adv-req-000004'',%s,''approve'',''self'')',adv),'wf_owner_required');
 PERFORM c10_test.as_user('mgr101'); PERFORM c10_test.denied(format('SELECT c10_demo.wf_decide_advance_v1(101,''adv-req-000005'',%s,''approve'',''manager'')',adv),'wf_owner_required');
 PERFORM c10_test.as_user('owner'); PERFORM c10_test.eq(c10_demo.wf_decide_advance_v1(101,'adv-req-000006',adv,'approve','within policy')->>'money_movement','false','advance approval moves no money');
 PERFORM c10_test.eq(jsonb_array_length(c10_demo.wf_list_advances_v1(101)->'items')::text,'1','owner sees advance');
 PERFORM c10_test.as_user('e3'); PERFORM c10_test.eq(jsonb_array_length(c10_demo.wf_list_advances_v1(101)->'items')::text,'0','other employee sees none');
END $$; COMMIT;

-- ===== S8 payroll October: blocking -> fix -> review -> approve -> freeze =====
BEGIN; SET LOCAL ROLE authenticated;
DO $$ DECLARE pv jsonb; r jsonb; run bigint; BEGIN
 PERFORM c10_test.as_user('e1'); PERFORM c10_test.denied('SELECT c10_demo.wf_payroll_preview_v1(101,''2026-10-01'')','wf_payroll_access_denied');
 PERFORM c10_test.denied('SELECT c10_demo.wf_create_payroll_draft_v1(101,''pay-req-000000'',''2026-10-01'',NULL,NULL)','wf_payroll_access_denied');
 PERFORM c10_test.as_user('bo101');
 PERFORM c10_test.denied('SELECT c10_demo.wf_payroll_preview_v1(101,''2026-10-15'')','wf_invalid_period');
 pv:=c10_demo.wf_payroll_preview_v1(101,'2026-10-01');
 PERFORM c10_test.eq(pv->>'preview_only','true','preview flagged'); PERFORM c10_test.eq(pv->>'paid','false','never paid');
 -- EMP-009 has no salary structure => blocking
 PERFORM c10_test.eq((pv->>'blocking_count')::int>0,'true','blocking exception present (no salary structure)');
 -- future period cannot be finalised
 PERFORM c10_test.eq(((c10_demo.wf_payroll_preview_v1(101,'2030-01-01')->>'blocking_count')::int>0)::text,'true','period not ended blocks');
 r:=c10_demo.wf_create_payroll_draft_v1(101,'pay-req-000001','2026-10-01',NULL,NULL); run:=(r->>'run_id')::bigint;
 PERFORM c10_test.eq(c10_demo.wf_create_payroll_draft_v1(101,'pay-req-000001','2026-10-01',NULL,NULL)::text,r::text,'draft creation replay is identical');
 PERFORM c10_test.denied($q$SELECT c10_demo.wf_create_payroll_draft_v1(101,'pay-req-000002','2026-10-01',NULL,NULL)$q$,'wf_payroll_in_progress');
 PERFORM c10_test.denied($q$SELECT c10_demo.wf_create_payroll_draft_v1(101,'pay-req-000001','2026-09-01',NULL,NULL)$q$,'wf_idempotency_conflict');
 PERFORM c10_test.denied(format('SELECT c10_demo.wf_payroll_transition_v1(101,''pay-req-000003'',%s,''review'',NULL)',run),'wf_maker_checker_violation');
 PERFORM c10_test.as_user('owner');
 PERFORM c10_test.denied(format('SELECT c10_demo.wf_payroll_transition_v1(101,''pay-req-000004'',%s,''review'',NULL)',run),'wf_payroll_blocking_exceptions');
 PERFORM c10_test.denied(format('SELECT c10_demo.wf_payroll_transition_v1(101,''pay-req-000005'',%s,''approve'',NULL)',run),'wf_payroll_state_invalid');
 -- resolve: give EMP-009 a salary structure; draft is now STALE and must not be reviewable
 PERFORM c10_demo.wf_set_salary_structure_v1(101,'sal-EMP-009-a',c10_test.eid(101,'EMP-009'),'MONTHLY',10000,'2026-03-01','offer letter');
 PERFORM c10_test.denied(format('SELECT c10_demo.wf_payroll_transition_v1(101,''pay-req-000006'',%s,''review'',NULL)',run),'wf_payroll_inputs_changed');
 PERFORM c10_demo.wf_recalculate_payroll_draft_v1(101,'pay-req-000007',run);
 PERFORM c10_test.eq(c10_test.line(run,'EMP-001','gross'),'37100.00','E1 gross');
 PERFORM c10_test.eq(c10_test.line(run,'EMP-001','absence_deduction'),'3500.00','E1 absence deduction (absent+unpaid+half+late rule)');
 PERFORM c10_test.eq(c10_test.line(run,'EMP-001','other_deductions_total'),'200.00','E1 uniform');
 PERFORM c10_test.eq(c10_test.line(run,'EMP-001','advance_recovery'),'1000.00','E1 advance installment');
 PERFORM c10_test.eq(c10_test.line(run,'EMP-001','net'),'32400.00','E1 net');
 PERFORM c10_test.eq(c10_test.line(run,'EMP-001','overtime_pay'),'2000.00','E1 overtime pay');
 PERFORM c10_test.eq(c10_test.line(run,'EMP-001','allowances_total'),'4100.00','E1 allowances (statutory PF stays OFF)');
 PERFORM c10_test.eq(c10_test.line(run,'EMP-001','present_days'),'21','E1 present');
 PERFORM c10_test.eq(c10_test.line(run,'EMP-001','late_days'),'3','E1 late days');
 PERFORM c10_test.eq(c10_test.line(run,'EMP-001','paid_leave_days'),'2','E1 paid leave');
 PERFORM c10_test.eq(c10_test.line(run,'EMP-002','net'),'62000.00','supervisor full month');
 PERFORM c10_test.eq(c10_test.line(run,'EMP-003','net'),'25200.00','daily-wage employee');
 PERFORM c10_test.eq(c10_test.line(run,'EMP-004','net'),'4500.00','hourly employee incl. approved overtime');
 PERFORM c10_test.eq(c10_test.line(run,'EMP-006','net'),'8000.00','night-shift employee, two overnight days');
 PERFORM c10_test.eq(c10_test.line(run,'EMP-007','net'),'0.00','deduction capped, net never negative');
 PERFORM c10_test.eq(c10_test.line(run,'EMP-009','net'),'1935.48','rounding to cents');
 PERFORM c10_test.eq(c10_test.line(run,'EMP-008','gross'),'99999999999.99','extreme salary kept exact');
 PERFORM c10_test.eq(c10_test.line(run,'EMP-008','absence_deduction'),round(99999999999.99/31*25,2)::text,'extreme precision deduction');
 PERFORM c10_test.eq((SELECT count(*) FROM jsonb_array_elements(c10_demo.wf_get_payroll_run_v1(101,run)->'lines') x WHERE (x->>'net')::numeric<0)::text,'0','no negative net');
 PERFORM c10_test.eq((SELECT x->>'employee_no' FROM jsonb_array_elements(c10_demo.wf_get_payroll_run_v1(101,run)->'lines') x WHERE x->>'employee_no'='EMP-005'),NULL,'terminated employee excluded');
 PERFORM c10_demo.wf_payroll_transition_v1(101,'pay-req-000008',run,'review','reviewed against timesheet');
 PERFORM c10_test.denied(format('SELECT c10_demo.wf_payroll_transition_v1(101,''pay-req-000009'',%s,''freeze'',NULL)',run),'wf_payroll_state_invalid');
 -- reviewed => inputs locked
 PERFORM c10_test.denied(format($q$SELECT c10_demo.wf_request_correction_v1(101,'cor-req-00020',%s,'2026-10-05','2026-10-05T09:00:00+06:00','2026-10-05T18:00:00+06:00',NULL,'late correction')$q$,c10_test.eid(101,'EMP-001')),'wf_period_locked');
 PERFORM c10_test.eq(c10_demo.wf_import_punches_v1(101,'imp-req-00030',1001,'device','[{"employee_no":"EMP-001","at":"2026-10-05T09:00:00+06:00","direction":"in"}]'::jsonb)->'results'->0->>'outcome','period_locked','punch import into locked period rejected');
 PERFORM c10_test.denied($q$SELECT c10_demo.wf_save_holiday_v1(101,'hol-req-00002','2026-10-26','New Holiday','public',true,NULL,true,'retro holiday')$q$,'wf_period_locked');
 PERFORM c10_test.denied(format($q$SELECT c10_demo.wf_set_employment_v1(101,'emp-req-00030',%s,'2026-10-20','inactive','permanent','retro')$q$,c10_test.eid(101,'EMP-007')),'wf_period_locked');
 PERFORM c10_test.as_user('e1');
 PERFORM c10_test.denied($q$SELECT c10_demo.wf_request_leave_v1(101,'lv-req-000030',NULL,'SICK','2026-10-27','2026-10-28','retro leave into locked month')$q$,'wf_leave_affects_frozen_period');
 PERFORM c10_test.denied($q$SELECT c10_demo.wf_request_leave_v1(101,'lv-req-000031',NULL,'SICK','2026-10-29','2026-11-02','spans boundary')$q$,'wf_leave_affects_frozen_period');
 PERFORM c10_test.as_user('owner');
 PERFORM c10_demo.wf_payroll_transition_v1(101,'pay-req-000010',run,'approve','approved');
 PERFORM c10_demo.wf_payroll_transition_v1(101,'pay-req-000011',run,'freeze','frozen for payslips');
 PERFORM c10_test.eq(c10_demo.wf_payroll_transition_v1(101,'pay-req-000011',run,'freeze','frozen for payslips')->>'status','frozen','freeze replay');
 PERFORM c10_test.eq(c10_demo.wf_payroll_transition_v1(101,'pay-req-000011',run,'freeze','frozen for payslips')->>'paid','false','frozen is not paid');
 PERFORM c10_test.denied(format('SELECT c10_demo.wf_payroll_transition_v1(101,''pay-req-000012'',%s,''void'',''no way'')',run),'wf_payroll_state_invalid');
 PERFORM c10_test.denied($q$SELECT c10_demo.wf_create_payroll_draft_v1(101,'pay-req-000013','2026-10-01',NULL,NULL)$q$,'wf_period_already_frozen_amend_required');
 PERFORM c10_test.denied(format($q$SELECT c10_demo.wf_create_payroll_draft_v1(101,'pay-req-000014','2026-10-01',%s,'short')$q$,run),'wf_amendment_reason_required');
 -- leave cannot silently change a frozen run
 PERFORM c10_test.as_user('mgr101');
 PERFORM c10_test.denied(format($q$SELECT c10_demo.wf_request_leave_v1(101,'lv-req-000032',%s,'SICK','2026-10-26','2026-10-26','retro on behalf')$q$,c10_test.eid(101,'EMP-001')),'wf_leave_affects_frozen_period');
 -- payslip privacy
 PERFORM c10_test.as_user('e1');
 PERFORM c10_test.eq(jsonb_array_length(c10_demo.wf_my_payslips_v1(101)->'items')::text,'1','employee sees only own payslip');
 PERFORM c10_test.eq((c10_demo.wf_get_my_payslip_v1(101,(c10_demo.wf_my_payslips_v1(101)->'items'->0->>'id')::bigint)->'payslip'->>'net'),'32400.00','payslip net');
 PERFORM c10_test.eq(c10_demo.wf_get_my_payslip_v1(101,(c10_demo.wf_my_payslips_v1(101)->'items'->0->>'id')::bigint)->'payslip'->>'payment_status','not_tracked_in_this_module','payslip does not claim payment');
END $$; COMMIT;
BEGIN; SET LOCAL ROLE authenticated;
DO $$ DECLARE foreign_id bigint; BEGIN
 PERFORM c10_test.as_user('bo101');
 SELECT (x->>'payslip_id')::bigint INTO foreign_id FROM jsonb_array_elements(c10_demo.wf_payslip_register_v1(101,'2026-10-01')->'items') x WHERE x->>'employee_no'='EMP-003';
 PERFORM c10_test.eq(jsonb_array_length(c10_demo.wf_payslip_register_v1(101,'2026-10-01')->'items')::text,'8','register has 8 frozen payslips');
 PERFORM c10_test.as_user('e1');
 PERFORM c10_test.denied(format('SELECT c10_demo.wf_get_my_payslip_v1(101,%s)',foreign_id),'wf_payslip_not_found');
 PERFORM c10_test.denied('SELECT c10_demo.wf_payslip_register_v1(101,NULL)','wf_payroll_access_denied');
 PERFORM c10_test.as_user('mgr101'); PERFORM c10_test.denied('SELECT c10_demo.wf_my_payslips_v1(101)','wf_no_employee_record');
 PERFORM c10_test.denied('SELECT c10_demo.wf_payslip_register_v1(101,NULL)','wf_payroll_access_denied');
 PERFORM c10_test.as_user('sup'); PERFORM c10_test.eq(jsonb_array_length(c10_demo.wf_my_payslips_v1(101)->'items')::text,'1','supervisor sees only own payslip');
 PERFORM c10_test.as_user('e3'); PERFORM c10_test.eq(c10_demo.wf_my_payslips_v1(101)->'items'->0->>'net','25200.00','daily employee own payslip');
END $$; COMMIT;

-- ===== S9 immutability even for the table owner =====
DO $$ BEGIN
 PERFORM c10_test.denied('UPDATE c10_demo.wf_payroll_lines SET net=0 WHERE net>0','wf_frozen_payroll_immutable');
 PERFORM c10_test.denied('DELETE FROM c10_demo.wf_payroll_lines','wf_frozen_payroll_immutable');
 PERFORM c10_test.denied('UPDATE c10_demo.wf_payroll_runs SET total_net=1 WHERE status=''frozen''','wf_frozen_payroll_immutable');
 PERFORM c10_test.denied('DELETE FROM c10_demo.wf_payroll_runs','wf_payroll_run_not_deletable');
 PERFORM c10_test.denied('DELETE FROM c10_demo.wf_payslips','wf_append_only_record');
 PERFORM c10_test.denied('UPDATE c10_demo.wf_payslips SET net=1','wf_append_only_record');
 PERFORM c10_test.denied('UPDATE c10_demo.wf_audit SET reason=''x''','wf_append_only_record');
 PERFORM c10_test.denied('DELETE FROM c10_demo.wf_audit','wf_append_only_record');
 PERFORM c10_test.denied('TRUNCATE c10_demo.wf_audit','wf_append_only_record');
 PERFORM c10_test.denied('UPDATE c10_demo.wf_punches SET punched_at=now()','wf_append_only_record');
 PERFORM c10_test.denied('DELETE FROM c10_demo.wf_punches','wf_append_only_record');
 PERFORM c10_test.denied('DELETE FROM c10_demo.wf_employment_history','wf_append_only_record');
 PERFORM c10_test.denied('UPDATE c10_demo.wf_salary_structures SET base_amount=1','wf_append_only_record');
 PERFORM c10_test.denied('INSERT INTO c10_demo.wf_payroll_lines(tenant_id,business_id,run_id,employee_id,employee_no,employee_name,calendar_days,employed_days) SELECT tenant_id,business_id,id,1,''X'',''X'',31,31 FROM c10_demo.wf_payroll_runs LIMIT 1','wf_frozen_payroll_immutable');
END $$;

-- ===== S10 amendment of a frozen period (never silent) =====
BEGIN; SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb; run1 bigint; run2 bigint; c1 bigint; BEGIN
 PERFORM c10_test.as_user('bo101');
 run1:=(SELECT (x->>'id')::bigint FROM jsonb_array_elements(c10_demo.wf_list_payroll_runs_v1(101)->'items') x WHERE x->>'status'='frozen');
 PERFORM c10_test.denied(format($q$SELECT c10_demo.wf_create_payroll_draft_v1(101,'pay-req-000020','2026-10-01',%s,'wrong period/run: %s')$q$,run1+999,'x'),'wf_period_already_frozen_amend_required');
 r:=c10_demo.wf_create_payroll_draft_v1(101,'pay-req-000021','2026-10-01',run1,'EMP-003 wrongly absent on Oct 1 (CCTV evidence)'); run2:=(r->>'run_id')::bigint;
 PERFORM c10_test.eq(r->>'version','2','amendment version 2');
 PERFORM c10_test.eq(c10_test.line(run1,'EMP-003','net'),'25200.00','original frozen line untouched');
 -- amendment unlocks inputs; correction now allowed, via normal approval
 PERFORM c10_test.as_user('mgr101');
 c1:=(c10_demo.wf_request_correction_v1(101,'cor-req-00040',c10_test.eid(101,'EMP-003'),'2026-10-01',NULL,NULL,'present','verified present on CCTV')->>'correction_id')::bigint;
 PERFORM c10_test.as_user('owner'); PERFORM c10_demo.wf_decide_correction_v1(101,'cor-req-00041',c1,'approve','CCTV verified');
 PERFORM c10_demo.wf_recalculate_payroll_draft_v1(101,'pay-req-000022',run2);
 PERFORM c10_test.eq(c10_test.line(run2,'EMP-003','net'),'26400.00','amended daily wage includes Oct 1');
 PERFORM c10_test.eq(c10_test.line(run2,'EMP-001','net'),'32400.00','unrelated employee unchanged, advance not double counted');
 PERFORM c10_demo.wf_payroll_transition_v1(101,'pay-req-000023',run2,'review','amendment reviewed');
 PERFORM c10_demo.wf_payroll_transition_v1(101,'pay-req-000024',run2,'approve','amendment approved');
 PERFORM c10_demo.wf_payroll_transition_v1(101,'pay-req-000025',run2,'freeze','amendment frozen');
 PERFORM c10_test.as_user('bo101');
 PERFORM c10_test.eq((SELECT x->>'status' FROM jsonb_array_elements(c10_demo.wf_list_payroll_runs_v1(101)->'items') x WHERE (x->>'id')::bigint=run1),'superseded','old run superseded, not rewritten');
 PERFORM c10_test.as_user('e3');
 PERFORM c10_test.eq(jsonb_array_length(c10_demo.wf_my_payslips_v1(101)->'items')::text,'2','employee keeps both payslips');
 PERFORM c10_test.eq((SELECT x->>'superseded' FROM jsonb_array_elements(c10_demo.wf_my_payslips_v1(101)->'items') x WHERE x->>'run_version'='1'),'true','v1 flagged superseded');
 PERFORM c10_test.as_user('bo101');
 PERFORM c10_test.eq((SELECT remaining::text FROM (SELECT (x->>'remaining') AS remaining FROM jsonb_array_elements(c10_demo.wf_list_advances_v1(101)->'items') x) y),'2000.00','advance recovered once only (amendment safe)');
 -- audit trail for the amendment
 PERFORM c10_test.eq((SELECT count(*) FROM jsonb_array_elements(c10_demo.wf_audit_list_v1(101,200)->'items') x WHERE x->>'event'='amendment_draft_created')::text,'1','amendment audited');
END $$; COMMIT;

-- ===== S11 reports, export, integrity, integration, retention =====
BEGIN; SET LOCAL ROLE authenticated;
DO $$ DECLARE rep jsonb; csv text; BEGIN
 PERFORM c10_test.as_user('mgr101');
 rep:=c10_demo.wf_report_attendance_v1(101,'2026-10-01','2026-10-31');
 PERFORM c10_test.eq(jsonb_array_length(rep->'sites')::text,'2','attendance summary by site');
 PERFORM c10_test.eq(jsonb_array_length(c10_demo.wf_report_headcount_v1(101)->'rows')>=3,'true','headcount rows');
 PERFORM c10_test.denied('SELECT c10_demo.wf_report_payroll_v1(101,''2026-10-01'')','wf_payroll_access_denied');
 PERFORM c10_test.denied('SELECT c10_demo.read_workforce_business_summary_v1(101,NULL)','wf_summary_denied');
 PERFORM c10_test.denied('SELECT c10_demo.wf_integrity_report_v1(101)','wf_owner_required');
 PERFORM c10_test.denied('SELECT c10_demo.wf_audit_list_v1(101,10)','wf_owner_required');
 csv:=c10_demo.wf_export_csv_v1(101,'exp-req-000001','employees','{}'::jsonb)->>'csv';
 PERFORM c10_test.eq((csv LIKE '%+880171000001%' OR csv LIKE '%1234%')::text,'false','employee CSV has no phone or NID');
 PERFORM c10_test.eq((csv LIKE '%Rahim A.%')::text,'true','manager export masks names');
 PERFORM c10_test.eq((csv LIKE '%''=HYPERLINK%' OR csv LIKE '%"''=HYPERLINK%')::text,'true','formula injection neutralised');
 PERFORM c10_test.denied($q$SELECT c10_demo.wf_export_csv_v1(101,'exp-req-000002','payslip_register','{}'::jsonb)$q$,'wf_payroll_access_denied');
 PERFORM c10_test.eq(c10_demo.wf_export_csv_v1(101,'exp-req-000003','attendance','{"from":"2026-10-01","to":"2026-10-07"}'::jsonb)->>'rows' IS NOT NULL,'true','attendance export');
 PERFORM c10_test.denied($q$SELECT c10_demo.wf_export_csv_v1(101,'exp-req-000004','attendance','{"from":"2026-01-01","to":"2026-12-31"}'::jsonb)$q$,'wf_invalid_range');
 PERFORM c10_test.denied($q$SELECT c10_demo.wf_export_csv_v1(101,'exp-req-000005','everything','{}'::jsonb)$q$,'wf_invalid_input');
 PERFORM c10_test.as_user('sup'); PERFORM c10_test.denied($q$SELECT c10_demo.wf_export_csv_v1(101,'exp-req-000006','employees','{}'::jsonb)$q$,'wf_export_denied');
 PERFORM c10_test.as_user('bo101');
 csv:=c10_demo.wf_export_csv_v1(101,'exp-req-000007','payslip_register','{"period":"2026-10-01"}'::jsonb)->>'csv';
 PERFORM c10_test.eq((csv LIKE '%EMP-001%32400.00%')::text,'true','owner payroll CSV');
 PERFORM c10_test.eq((SELECT x->>'net' FROM jsonb_array_elements(c10_demo.wf_report_payroll_v1(101,'2026-10-01')->'sites') x WHERE (x->>'site_id')='1002'),(26400.00+99999999999.99-round(99999999999.99/31*25,2))::text,'site 1002 payroll net (EMP-003 amended + EMP-008 extreme)');
 PERFORM c10_test.eq(c10_demo.wf_integrity_report_v1(101)->>'ok','true','integrity report clean');
 PERFORM c10_test.eq(c10_demo.read_payroll_liability_preview_v1(101,'2026-10-01')->>'state','approved_not_paid','liability preview is not paid');
 PERFORM c10_test.eq(c10_demo.read_payroll_liability_preview_v1(101,'2026-10-01')->>'money_movement','false','no money movement');
 PERFORM c10_test.eq(c10_demo.read_workforce_business_summary_v1(101,'2026-10-01')->'payroll'->>'status','frozen','summary shows frozen run');
 PERFORM c10_test.eq(c10_demo.read_workforce_business_summary_v1(101,'2026-10-01')->>'ledger_posted','false','no ledger posting');
 PERFORM c10_test.denied($q$SELECT c10_demo.wf_purge_expired_punches_v1(101,'prg-req-000001',true)$q$,'wf_tenant_owner_required');
 PERFORM c10_test.as_user('owner');
 PERFORM c10_test.eq(c10_demo.wf_purge_expired_punches_v1(101,'prg-req-000002',true)->>'rows','0','nothing past retention');
END $$; COMMIT;

-- ===== S12 tenant / business isolation =====
BEGIN; SET LOCAL ROLE authenticated;
DO $$ BEGIN
 PERFORM c10_test.as_user('bo201');
 PERFORM c10_test.eq(c10_demo.wf_list_employees_v1(201,NULL,NULL,NULL,50,0)->>'total','1','tenant 2 has its own directory');
 PERFORM c10_test.denied('SELECT c10_demo.wf_list_employees_v1(101,NULL,NULL,NULL,50,0)','wf_denied');
 PERFORM c10_test.denied($q$SELECT c10_demo.wf_save_employee_v1(101,'emp-req-90001',NULL,NULL,'{"employee_no":"EVIL","full_name":"Evil Person","joined_on":"2026-01-01","contract_type":"permanent","site_id":1001}'::jsonb,'cross tenant')$q$,'wf_denied');
 PERFORM c10_test.denied($q$SELECT c10_demo.wf_save_employee_v1(201,'emp-req-90002',NULL,NULL,'{"employee_no":"EVIL","full_name":"Evil Person","joined_on":"2026-01-01","contract_type":"permanent","site_id":1001}'::jsonb,'cross tenant site')$q$,'wf_site_not_in_business');
 PERFORM c10_test.denied($q$SELECT c10_demo.wf_payroll_preview_v1(101,'2026-10-01')$q$,'wf_denied');
 PERFORM c10_test.as_user('emp201'); PERFORM c10_test.eq(c10_demo.wf_read_overview_v1(201)->>'level','employee','tenant-2 employee');
 PERFORM c10_test.eq(c10_demo.wf_my_businesses_v1()->'items'->0->>'id','201','employee lists only own business');
 PERFORM c10_test.eq(jsonb_array_length(c10_demo.wf_my_businesses_v1()->'items')::text,'1','one business for tenant-2 employee');
 PERFORM c10_test.as_user('owner'); PERFORM c10_test.eq(jsonb_array_length(c10_demo.wf_my_businesses_v1()->'items')::text,'2','tenant owner lists both tenant-1 businesses');
 PERFORM c10_test.as_user('e4'); PERFORM c10_test.eq(jsonb_array_length(c10_demo.wf_my_businesses_v1()->'items')::text,'1','linked employee with stock grant lists workforce business');
 PERFORM c10_test.as_user('investor'); PERFORM c10_test.eq(jsonb_array_length(c10_demo.wf_my_businesses_v1()->'items')::text,'0','investor has no workforce business');
 PERFORM c10_test.as_user('emp201');
 PERFORM c10_test.denied('SELECT c10_demo.wf_read_overview_v1(101)','wf_denied');
 PERFORM c10_test.as_user('owner');
 PERFORM c10_test.denied('SELECT c10_demo.wf_list_employees_v1(201,NULL,NULL,NULL,50,0)','wf_denied');
 PERFORM c10_test.eq(c10_demo.wf_list_employees_v1(102,NULL,NULL,NULL,50,0)->>'total','1','business 102 separate directory');
 PERFORM c10_test.eq(c10_demo.wf_list_employees_v1(101,NULL,NULL,NULL,50,0)->>'total','9','business 101 directory unaffected');
 PERFORM c10_test.as_user('mgr102'); PERFORM c10_test.eq(c10_demo.wf_list_employees_v1(102,NULL,NULL,NULL,50,0)->>'total','1','manager 102 sees only 102');
 PERFORM c10_test.denied($q$SELECT c10_demo.wf_import_punches_v1(101,'imp-req-90001',1001,'manual','[{"employee_no":"EMP-001","at":"2026-10-06T09:00:00+06:00","direction":"in"}]'::jsonb)$q$,'wf_denied');
 PERFORM c10_test.denied($q$SELECT c10_demo.wf_import_punches_v1(102,'imp-req-90002',1001,'manual','[{"employee_no":"EMP-001","at":"2026-10-06T09:00:00+06:00","direction":"in"}]'::jsonb)$q$,'wf_site_not_in_business');
END $$; COMMIT;
-- audit integrity: tampering is detectable (superuser tamper inside rolled-back savepoint)
BEGIN;
DO $$ BEGIN PERFORM c10_test.eq(c10_test.u('owner')::text IS NOT NULL,'true','helper'); END $$;
ALTER TABLE c10_demo.wf_audit DISABLE TRIGGER wf_audit_no_row_mutation;
UPDATE c10_demo.wf_audit SET reason='tampered' WHERE id=(SELECT min(id) FROM c10_demo.wf_audit WHERE business_id=101);
SET LOCAL ROLE authenticated;
DO $$ BEGIN PERFORM c10_test.as_user('owner');
 PERFORM c10_test.eq(c10_demo.wf_integrity_report_v1(101)->>'ok','false','audit tampering detected'); END $$;
ROLLBACK;
SELECT 'A051_SQL_E2E_PASS' AS result;
