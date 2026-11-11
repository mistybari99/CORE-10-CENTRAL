-- C10-A054 disposable PostgreSQL e2e: delegation, policy versions, OT/rules trace, approval-vs-payment, leave carry-forward, retention, privacy.
-- Signed-claim SIMULATION (NOT GoTrue). Run on the full stack (tests/c10_a053_stack.sh full). Business 102 (tenant 1) is the demo business.
\set ON_ERROR_STOP on
\ir c10_a053_a054_helpers.sql

-- ===== S0 fixture (business owner aaaa configures; manager b1111 imports punches) =====
BEGIN; SET LOCAL ROLE authenticated;
DO $$ DECLARE rows jsonb:='[]'; d date; BEGIN
 PERFORM c10_test.as_user('boB');
 PERFORM c10_demo.wf_save_shift_v1(102,'a054-shift-0001',0,'{"code":"DAY","name":"Day 9-6","start_time":"09:00","end_time":"18:00","break_minutes":60,"grace_late_minutes":10,"min_overtime_minutes":30}'::jsonb,'day shift');
 PERFORM c10_demo.wf_save_leave_type_v1(102,'a054-lt-000001',0,'{"code":"ANNUAL","name":"Annual","paid":true,"annual_quota_days":10}'::jsonb,'annual');
 PERFORM c10_demo.wf_save_leave_type_v1(102,'a054-lt-000002',0,'{"code":"CASUAL","name":"Casual","paid":true,"annual_quota_days":12}'::jsonb,'casual');
 PERFORM c10_demo.wf_save_leave_type_v1(102,'a054-lt-000003',0,'{"code":"SICK","name":"Sick","paid":true,"annual_quota_days":14}'::jsonb,'sick');
 PERFORM c10_demo.wf_save_pay_policy_v1(102,'a054-pp-000001',0,'{"code":"MONTHLY","name":"Monthly","pay_basis":"monthly","ot_multiplier_weekday":2.0,"ot_multiplier_offday":2.0}'::jsonb,'monthly policy');
 PERFORM c10_demo.wf_save_employee_v1(102,'a054-emp-00001',NULL,NULL,'{"employee_no":"B1","full_name":"Bela Branch","joined_on":"2026-01-01","contract_type":"permanent","site_id":1003}'::jsonb,'hire');
 PERFORM c10_demo.wf_save_employee_v1(102,'a054-emp-00002',NULL,NULL,'{"employee_no":"B2","full_name":"Babul Branch","joined_on":"2026-01-01","contract_type":"permanent","site_id":1003}'::jsonb,'hire');
 PERFORM c10_demo.wf_assign_shift_v1(102,'a054-shf-00001',c10_test.eid(102,'B1'),'DAY','2026-01-01','roster');
 PERFORM c10_demo.wf_assign_shift_v1(102,'a054-shf-00002',c10_test.eid(102,'B2'),'DAY','2026-01-01','roster');
 PERFORM c10_demo.wf_set_salary_structure_v1(102,'a054-sal-00001',c10_test.eid(102,'B1'),'MONTHLY',30000,'2026-01-01','offer');
 PERFORM c10_demo.wf_set_salary_structure_v1(102,'a054-sal-00002',c10_test.eid(102,'B2'),'MONTHLY',24000,'2026-01-01','offer');
 -- A053 staff identity link (registry alias, never a raw UUID)
 PERFORM c10_demo.a053_link_staff_identity_v1(102,'a054-lnk-00001',c10_test.eid(102,'B1'),'BRANCH_STAFF_B','link staff login');
 -- October 2026: every non-Friday present 09:00-18:00 for B1 and B2
 PERFORM c10_test.as_user('mgrB2');
 FOR d IN SELECT generate_series('2026-10-01'::date,'2026-10-31'::date,interval '1 day')::date LOOP
  IF extract(isodow FROM d)<>5 THEN
   rows:=rows||jsonb_build_array(
    jsonb_build_object('employee_no','B1','at',d||'T09:00:00+06:00','direction','in'),
    jsonb_build_object('employee_no','B1','at',d||CASE WHEN d='2026-10-14' THEN 'T20:00:00+06:00' ELSE 'T18:00:00+06:00' END,'direction','out'),
    jsonb_build_object('employee_no','B2','at',d||'T09:00:00+06:00','direction','in'),
    jsonb_build_object('employee_no','B2','at',d||'T18:00:00+06:00','direction','out'));
  END IF;
 END LOOP;
 rows:=rows||jsonb_build_array(jsonb_build_object('employee_no','B1','at','2026-10-16T09:00:00+06:00','direction','in'),
  jsonb_build_object('employee_no','B1','at','2026-10-16T14:00:00+06:00','direction','out'));
 PERFORM c10_test.eq(c10_demo.wf_import_punches_v1(102,'a054-imp-00001',1003,'device',rows)->>'rejected','0','punches imported');
 PERFORM c10_demo.wf_decide_overtime_v1(102,'a054-ot-000001',c10_test.eid(102,'B1'),'2026-10-14',120,'weekday OT approved');
 PERFORM c10_demo.wf_decide_overtime_v1(102,'a054-ot-000002',c10_test.eid(102,'B1'),'2026-10-16',240,'off-day OT approved');
END $$; COMMIT;

-- ===== S1 delegation: authority, scope, negative =====
BEGIN; SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb; BEGIN
 -- only owners grant; nobody delegates to self / ineligible / other tenant
 PERFORM c10_test.as_user('mgrB');
 PERFORM c10_test.denied($q$SELECT c10_demo.a054_grant_delegation_v1(102,'a054-dg-neg-001',c10_test.u('mgrB2'),'payroll_reviewer','allow',NULL,NULL,NULL,NULL,'manager tries')$q$,'a054_owner_required');
 PERFORM c10_test.as_user('branch');
 PERFORM c10_test.denied($q$SELECT c10_demo.a054_grant_delegation_v1(102,'a054-dg-neg-002',c10_test.u('mgrB2'),'payroll_reviewer','allow',NULL,NULL,NULL,NULL,'staff tries')$q$,'a054_owner_required');
 PERFORM c10_test.as_user('investor');
 PERFORM c10_test.denied($q$SELECT c10_demo.a054_grant_delegation_v1(101,'a054-dg-neg-003',c10_test.u('mgr101'),'payroll_reviewer','allow',NULL,NULL,NULL,NULL,'investor tries')$q$,'wf_denied');
 PERFORM c10_test.as_user('ownerB');
 PERFORM c10_test.denied($q$SELECT c10_demo.a054_grant_delegation_v1(102,'a054-dg-neg-004',c10_test.u('mgrB2'),'payroll_reviewer','allow',NULL,NULL,NULL,NULL,'other tenant')$q$,'wf_denied');
 PERFORM c10_test.as_user('boB');
 PERFORM c10_test.denied($q$SELECT c10_demo.a054_grant_delegation_v1(102,'a054-dg-neg-005',c10_test.u('boB'),'payroll_reviewer','allow',NULL,NULL,NULL,NULL,'self')$q$,'a054_self_delegation_denied');
 PERFORM c10_test.denied($q$SELECT c10_demo.a054_grant_delegation_v1(102,'a054-dg-neg-006',c10_test.u('unassigned'),'payroll_reviewer','allow',NULL,NULL,NULL,NULL,'not staff')$q$,'a054_delegate_not_eligible');
 PERFORM c10_test.denied($q$SELECT c10_demo.a054_grant_delegation_v1(102,'a054-dg-neg-007',c10_test.u('investor'),'payroll_reviewer','allow',NULL,NULL,NULL,NULL,'investor')$q$,'a054_delegate_not_eligible');
 PERFORM c10_test.denied($q$SELECT c10_demo.a054_grant_delegation_v1(102,'a054-dg-neg-008',c10_test.u('mgrB2'),'god_mode','allow',NULL,NULL,NULL,NULL,'bad role')$q$,'a054_invalid_delegation');
 PERFORM c10_test.denied($q$SELECT c10_demo.a054_grant_delegation_v1(102,'a054-dg-neg-009',c10_test.u('mgrB2'),'payroll_reviewer','allow',1003,NULL,NULL,NULL,'site scoped payroll')$q$,'a054_invalid_delegation');
 PERFORM c10_test.denied($q$SELECT c10_demo.a054_grant_delegation_v1(102,'a054-dg-neg-010',c10_test.u('mgrB2'),'hr','allow',1001,NULL,NULL,NULL,'site of another business')$q$,'a054_invalid_delegation');
 PERFORM c10_test.denied($q$SELECT c10_demo.a054_grant_delegation_v1(102,'a054-dg-neg-011',c10_test.u('mgrB2'),'payroll_reviewer','allow',NULL,'2026-10-15',NULL,NULL,'mid-month')$q$,'a054_invalid_delegation');
 -- before any grant a manager has no payroll at all
 PERFORM c10_test.as_user('mgrB');
 PERFORM c10_test.denied($q$SELECT c10_demo.wf_payroll_preview_v1(102,'2026-10-01')$q$,'wf_payroll_access_denied');
 PERFORM c10_test.denied($q$SELECT c10_demo.wf_list_payroll_runs_v1(102)$q$,'wf_payroll_access_denied');
 -- grants
 PERFORM c10_test.as_user('boB');
 r:=c10_demo.a054_grant_delegation_v1(102,'a054-dg-000001',c10_test.u('mgrB'),'payroll_preparer','allow',NULL,'2026-10-01','2026-10-01',NULL,'Oct preparer');
 PERFORM c10_test.eq(r->>'status','granted','grant');
 PERFORM c10_test.eq(c10_demo.a054_grant_delegation_v1(102,'a054-dg-000001',c10_test.u('mgrB'),'payroll_preparer','allow',NULL,'2026-10-01','2026-10-01',NULL,'Oct preparer')::text,r::text,'idempotent replay');
 PERFORM c10_test.denied($q$SELECT c10_demo.a054_grant_delegation_v1(102,'a054-dg-000001',c10_test.u('mgrB2'),'payroll_preparer','allow',NULL,'2026-10-01','2026-10-01',NULL,'Oct preparer')$q$,'wf_idempotency_conflict');
 PERFORM c10_demo.a054_grant_delegation_v1(102,'a054-dg-000002',c10_test.u('mgrB2'),'payroll_reviewer','allow',NULL,'2026-10-01','2026-10-01',NULL,'Oct reviewer');
 PERFORM c10_test.eq(jsonb_array_length(c10_demo.a054_list_delegations_v1(102)->'items')::text,'2','owner lists delegations');
 PERFORM c10_test.eq(jsonb_array_length(c10_demo.a054_eligible_delegates_v1(102)->'items')::text,'4','eligible: mgrB mgrB2 boB2 branch');
 PERFORM c10_test.as_user('mgrB'); PERFORM c10_test.denied($q$SELECT c10_demo.a054_list_delegations_v1(102)$q$,'a054_owner_required');
 PERFORM c10_test.eq((c10_demo.a054_my_access_v1(102)->'delegated_roles')::text,'["payroll_preparer"]','my access shows own delegated role only');
 -- period scope: October allowed, September not
 PERFORM c10_test.eq(c10_demo.wf_payroll_preview_v1(102,'2026-10-01')->>'paid','false','preparer previews October');
 PERFORM c10_test.denied($q$SELECT c10_demo.wf_payroll_preview_v1(102,'2026-09-01')$q$,'a054_delegation_denied');
 PERFORM c10_test.denied($q$SELECT c10_demo.wf_payroll_transition_v1(102,'a054-tr-neg-001',1,'approve',NULL)$q$,'wf_payroll_access_denied');
 PERFORM c10_test.denied($q$SELECT c10_demo.a054_save_policy_v1(102,'a054-pol-neg-01','overtime','DEFAULT','2026-10-01','{"mode":"on","weekday_multiplier":1.5,"offday_multiplier":2}'::jsonb,'manager tries',NULL)$q$,'a054_owner_required');
END $$; COMMIT;

-- ===== S2 effective-dated policy versions (owner only; validation; legal gate) =====
BEGIN; SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb; BEGIN
 PERFORM c10_test.as_user('boB');
 PERFORM c10_test.denied($q$SELECT c10_demo.a054_save_policy_v1(102,'a054-pol-neg-02','overtime','DEFAULT','2026-10-01','{"mode":"on","weekday_multiplier":0.01,"offday_multiplier":2}'::jsonb,'1 percent confusion',NULL)$q$,'a054_multiplier_below_base_rate');
 PERFORM c10_test.denied($q$SELECT c10_demo.a054_save_policy_v1(102,'a054-pol-neg-03','overtime','DEFAULT','2026-10-01','{"mode":"on","weekday_multiplier":150,"offday_multiplier":2}'::jsonb,'percent not multiplier',NULL)$q$,'a054_multiplier_above_limit_use_x_not_percent');
 PERFORM c10_test.denied($q$SELECT c10_demo.a054_save_policy_v1(102,'a054-pol-neg-04','overtime','DEFAULT','2026-10-01','{"mode":"on","weekday_multiplier":1.555,"offday_multiplier":2}'::jsonb,'scale',NULL)$q$,'a054_invalid_policy');
 PERFORM c10_test.denied($q$SELECT c10_demo.a054_save_policy_v1(102,'a054-pol-neg-05','overtime','DEFAULT','2026-10-01','{"mode":"on","weekday_multiplier":1.5,"offday_multiplier":2,"surprise":1}'::jsonb,'unknown key',NULL)$q$,'a054_invalid_policy');
 PERFORM c10_test.denied($q$SELECT c10_demo.a054_save_policy_v1(102,'a054-pol-neg-06','overtime','DEFAULT','2026-10-15','{"mode":"on","weekday_multiplier":1.5,"offday_multiplier":2}'::jsonb,'mid-month',NULL)$q$,'a054_effective_date_boundary');
 PERFORM c10_test.denied($q$SELECT c10_demo.a054_save_policy_v1(102,'a054-pol-neg-07','overtime','DEFAULT','2026-10-01','{"mode":"off"}'::jsonb,'OT off needs legal gate',NULL)$q$,'a054_legal_gate_tenant_owner_required');
 PERFORM c10_test.denied($q$SELECT c10_demo.a054_save_policy_v1(102,'a054-pol-neg-08','pay_rule','STAT1','2026-10-01','{"name":"Statutory X","kind":"deduction","calc":"percent","amount":5,"base":"basic_earned","statutory":true}'::jsonb,'statutory needs gate',NULL)$q$,'a054_legal_gate_tenant_owner_required');
 PERFORM c10_test.denied($q$SELECT c10_demo.a054_save_policy_v1(102,'a054-pol-neg-09','pay_rule','HOUSE','2026-10-01','{"name":"House","kind":"allowance","calc":"percent","amount":150,"base":"basic_earned"}'::jsonb,'over 100 percent',NULL)$q$,'a054_invalid_policy');
 PERFORM c10_test.denied($q$SELECT c10_demo.a054_save_policy_v1(102,'a054-pol-neg-10','pay_rule','HOUSE','2026-10-01','{"name":"House","kind":"allowance","calc":"percent","amount":10}'::jsonb,'base missing',NULL)$q$,'a054_invalid_policy');
 PERFORM c10_test.denied($q$SELECT c10_demo.a054_save_policy_v1(102,'a054-pol-neg-11','pay_rule','HOUSE','2026-10-01','{"name":"House","kind":"allowance","calc":"fixed","amount":10,"base":"basic_earned"}'::jsonb,'fixed with base',NULL)$q$,'a054_invalid_policy');
 PERFORM c10_test.denied($q$SELECT c10_demo.a054_save_policy_v1(102,'a054-pol-neg-12','pay_rule','HOUSE','2026-10-01','{"name":"House","kind":"allowance","calc":"fixed","amount":10,"cap_amount":5,"min_amount":9}'::jsonb,'min>cap',NULL)$q$,'a054_invalid_policy');
 PERFORM c10_test.denied($q$SELECT c10_demo.a054_save_policy_v1(102,'a054-pol-neg-13','leave','NOSUCH','2026-01-01','{"accrual":"upfront","annual_quota_days":10}'::jsonb,'no type',NULL)$q$,'a054_leave_type_not_found');
 PERFORM c10_test.denied($q$SELECT c10_demo.a054_save_policy_v1(102,'a054-pol-neg-14','leave','ANNUAL','2026-03-01','{"accrual":"upfront","annual_quota_days":10}'::jsonb,'not jan 1',NULL)$q$,'a054_effective_date_boundary');
 PERFORM c10_test.denied($q$SELECT c10_demo.a054_save_policy_v1(102,'a054-pol-neg-15','leave','ANNUAL','2026-01-01','{"accrual":"daily","annual_quota_days":10}'::jsonb,'bad accrual',NULL)$q$,'a054_invalid_policy');
 -- tenant owner may set OT OFF only with a legal reference; stays a normal version that can be superseded
 PERFORM c10_test.as_user('owner');
 PERFORM c10_test.denied($q$SELECT c10_demo.a054_save_policy_v1(102,'a054-pol-neg-16','overtime','DEFAULT','2026-10-01','{"mode":"off"}'::jsonb,'no reference',NULL)$q$,'a054_legal_gate_reference_required');
 PERFORM c10_test.as_user('boB');
 -- valid versions
 r:=c10_demo.a054_save_policy_v1(102,'a054-pol-000001','overtime','DEFAULT','2026-10-01','{"mode":"on","weekday_multiplier":1.5,"offday_multiplier":2}'::jsonb,'OT policy v1',NULL);
 PERFORM c10_test.eq(r->>'version','1','OT v1'); PERFORM c10_test.eq(r->>'state','effective','OT v1 effective');
 PERFORM c10_demo.a054_save_policy_v1(102,'a054-pol-000002','pay_rule','HOUSE','2026-10-01','{"name":"House allowance","kind":"allowance","calc":"percent","amount":10,"base":"basic_earned","cap_amount":2500}'::jsonb,'house cap',NULL);
 PERFORM c10_demo.a054_save_policy_v1(102,'a054-pol-000003','pay_rule','INS','2026-10-01','{"name":"Insurance share","kind":"deduction","calc":"percent","amount":2,"base":"gross_before_rule"}'::jsonb,'insurance',NULL);
 PERFORM c10_demo.a054_save_policy_v1(102,'a054-pol-000004','pay_rule','MEALDED','2026-10-01','{"name":"Meal deduction","kind":"deduction","calc":"fixed","amount":300}'::jsonb,'meal',NULL);
 PERFORM c10_demo.a054_save_policy_v1(102,'a054-pol-000005','pay_rule','TRANSPORT','2026-10-01','{"name":"Transport","kind":"allowance","calc":"fixed","amount":1000,"scope":{"contract_types":["permanent"],"site_ids":[1003]}}'::jsonb,'transport',NULL);
 PERFORM c10_demo.wf_save_component_v1(102,'a054-pc-000001',0,'{"code":"CLASH","name":"Clash","kind":"allowance","calc_type":"fixed","amount":5}'::jsonb,'a051 component');
 PERFORM c10_test.denied($q$SELECT c10_demo.a054_save_policy_v1(102,'a054-pol-neg-17','pay_rule','CLASH','2026-10-01','{"name":"Clash","kind":"allowance","calc":"fixed","amount":5}'::jsonb,'collision',NULL)$q$,'a054_rule_code_collision');
 PERFORM c10_demo.a054_save_policy_v1(102,'a054-pol-000006','leave','ANNUAL','2026-01-01','{"accrual":"upfront","annual_quota_days":10,"carry_forward_cap_days":5,"carry_expiry_months":3,"grace_days":0,"allow_cross_year":true}'::jsonb,'annual carry',NULL);
 PERFORM c10_demo.a054_save_policy_v1(102,'a054-pol-000007','leave','CASUAL','2026-01-01','{"accrual":"monthly","annual_quota_days":12,"carry_forward_cap_days":0}'::jsonb,'casual monthly',NULL);
 PERFORM c10_test.eq(jsonb_array_length(c10_demo.a054_list_policies_v1(102,'pay_rule')->'items')::text,'4','four rule versions listed');
 PERFORM c10_test.as_user('mgrB'); -- preparer may read pay policy; not leave policy admin
 PERFORM c10_test.eq(jsonb_array_length(c10_demo.a054_list_policies_v1(102,'overtime')->'items')::text,'1','preparer reads OT policy');
 PERFORM c10_test.as_user('branch'); PERFORM c10_test.denied($q$SELECT c10_demo.a054_list_policies_v1(102,'overtime')$q$,'a054_policy_view_denied');
 PERFORM c10_test.denied($q$SELECT c10_demo.a054_list_policies_v1(102,'leave')$q$,'a054_policy_view_denied');
END $$; COMMIT;
-- policy rows are immutable even for the table owner
DO $$ BEGIN
 PERFORM c10_test.denied($q$UPDATE c10_demo.a054_policy_versions SET params='{}'$q$,'wf_append_only_record');
 PERFORM c10_test.denied($q$DELETE FROM c10_demo.a054_policy_versions$q$,'wf_append_only_record');
 PERFORM c10_test.denied($q$UPDATE c10_demo.a054_delegations SET effect='deny'$q$,'wf_append_only_record');
 PERFORM c10_test.denied($q$DELETE FROM c10_demo.a054_delegations$q$,'wf_append_only_record');
END $$;

-- ===== S3 payroll: delegated preparer / reviewer, maker-checker, trace =====
CREATE TABLE c10_test.state(k text PRIMARY KEY,v text);
GRANT ALL ON c10_test.state TO authenticated;
BEGIN; SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb; run bigint; BEGIN
 PERFORM c10_test.as_user('mgrB');
 r:=c10_demo.wf_create_payroll_draft_v1(102,'a054-run-000001','2026-10-01',NULL,NULL);
 run:=(r->>'run_id')::bigint; INSERT INTO c10_test.state VALUES('run_oct',run::text);
 PERFORM c10_test.eq(r->>'blocking_count','0','draft has no blocking exceptions');
 -- calculation with effective policy: B1 hourly=30000/(31*8); OT = h*(2h*1.5 + 4h*2.0)
 PERFORM c10_test.eq(c10_test.line(run,'B1','overtime_pay'),'1330.65','OT at 1.5x weekday / 2.0x off-day (multiplier, not percent)');
 PERFORM c10_test.eq(c10_test.line(run,'B1','allowances_total'),'3500.00','HOUSE capped 2500 + TRANSPORT 1000');
 PERFORM c10_test.eq(c10_test.line(run,'B1','total_deductions'),'976.61','INS 2% of gross-before-rule + MEAL 300');
 PERFORM c10_test.eq(c10_test.line(run,'B1','net'),'33854.04','B1 net');
 PERFORM c10_test.eq(c10_test.line(run,'B2','allowances_total'),'3400.00','B2 HOUSE 2400 uncapped + TRANSPORT');
 PERFORM c10_test.eq(c10_test.line(run,'B2','overtime_pay'),'0.00','B2 no OT');
 PERFORM c10_test.eq(c10_test.q($s$SELECT (x->'trace'->>'raw')||'/'||(x->'trace'->>'cap')||'/'||(x#>>'{trace,base_value}') FROM c10_demo.wf_payroll_lines l,jsonb_array_elements(l.components) x WHERE l.run_id=$s$||run||$s$ AND l.employee_no='B1' AND x->>'code'='HOUSE'$s$),'3000.00/2500/30000.00','rule trace shows raw, cap and base');
END $$; COMMIT;

-- ===== S3b reviewer / approver separation, then freeze =====
BEGIN; SET LOCAL ROLE authenticated;
DO $$ DECLARE run bigint:=(SELECT v::bigint FROM c10_test.state WHERE k='run_oct'); r jsonb; BEGIN
 PERFORM c10_test.as_user('mgrB'); -- preparer only
 PERFORM c10_test.denied(format($q$SELECT c10_demo.wf_payroll_transition_v1(102,'a054-tr-neg-002',%s,'review',NULL)$q$,run),'wf_payroll_access_denied');
 PERFORM c10_test.eq(c10_demo.wf_get_payroll_run_v1(102,run)->>'paid','false','preparer reads the October run');
 PERFORM c10_test.as_user('branch'); -- employee in the run, no delegation
 PERFORM c10_test.denied(format($q$SELECT c10_demo.wf_payroll_transition_v1(102,'a054-tr-neg-003',%s,'review',NULL)$q$,run),'wf_payroll_access_denied');
 PERFORM c10_test.as_user('mgrB2');
 PERFORM c10_test.denied(format($q$SELECT c10_demo.wf_payroll_transition_v1(102,'a054-tr-neg-004',%s,'void','nope nope')$q$,run),'a054_owner_required');
 r:=c10_demo.wf_payroll_transition_v1(102,'a054-tr-000001',run,'review','reviewed by delegate');
 PERFORM c10_test.eq(r->>'status','reviewed','delegated reviewer reviews'); PERFORM c10_test.eq(r->>'paid','false','review is not payment');
 PERFORM c10_test.denied(format($q$SELECT c10_demo.wf_payroll_transition_v1(102,'a054-tr-neg-005',%s,'approve',NULL)$q$,run),'a054_delegation_denied');
 PERFORM c10_test.as_user('boB');
 PERFORM c10_demo.a054_grant_delegation_v1(102,'a054-dg-000003',c10_test.u('mgrB2'),'payroll_approver','allow',NULL,'2026-10-01','2026-10-01',NULL,'Oct approver');
 PERFORM c10_test.as_user('mgrB2');
 PERFORM c10_test.denied(format($q$SELECT c10_demo.wf_payroll_transition_v1(102,'a054-tr-neg-006',%s,'approve',NULL)$q$,run),'wf_maker_checker_violation');
 PERFORM c10_test.as_user('mgrB'); -- preparer cannot approve (no role) even though prepared_by differs from nobody
 PERFORM c10_test.denied(format($q$SELECT c10_demo.wf_payroll_transition_v1(102,'a054-tr-neg-007',%s,'approve',NULL)$q$,run),'wf_payroll_access_denied');
 PERFORM c10_test.as_user('boB');
 r:=c10_demo.wf_payroll_transition_v1(102,'a054-tr-000002',run,'approve','owner approves');
 PERFORM c10_test.eq(r->>'status','approved','owner approves'); PERFORM c10_test.eq(r->>'money_movement','false','approval moves no money');
 -- APPROVED != PAID: liability shows approved-unpaid, nothing paid
 r:=c10_demo.a054_liability_report_v1(102,'2026-10-01');
 PERFORM c10_test.eq(r->'totals'->>'approved_unpaid_count','2','two approved-unpaid');
 PERFORM c10_test.eq(r->'totals'->>'approved_unpaid_amount','60426.04','approved unpaid amount');
 PERFORM c10_test.eq(r->'totals'->>'paid_recorded_amount','0','nothing paid');
 PERFORM c10_test.eq(r->>'payment_executed','false','payment_executed false');
 PERFORM c10_test.as_user('mgrB2');
 PERFORM c10_test.denied(format($q$SELECT c10_demo.wf_payroll_transition_v1(102,'a054-tr-neg-008',%s,'freeze',NULL)$q$,run),'wf_maker_checker_violation');
 PERFORM c10_test.as_user('boB');
 PERFORM c10_test.eq(c10_demo.wf_payroll_transition_v1(102,'a054-tr-000003',run,'freeze',NULL)->>'status','frozen','owner freezes');
 -- effective-dated immutability: locked period cannot be re-priced, future month can
 PERFORM c10_test.denied($q$SELECT c10_demo.a054_save_policy_v1(102,'a054-pol-neg-18','overtime','DEFAULT','2026-10-01','{"mode":"on","weekday_multiplier":3,"offday_multiplier":3}'::jsonb,'rewrite history',NULL)$q$,'a054_effective_date_locked');
 r:=c10_demo.a054_save_policy_v1(102,'a054-pol-000008','overtime','DEFAULT','2026-12-01','{"mode":"on","weekday_multiplier":1.75,"offday_multiplier":2.5}'::jsonb,'OT policy v2 from December',NULL);
 PERFORM c10_test.eq(r->>'version','2','OT v2'); PERFORM c10_test.eq(r->>'state','scheduled','future-dated version is scheduled');
END $$; COMMIT;

-- ===== S4 approval is NOT payment: external payment RECORDS, liability states, revoke/expiry/deny =====
BEGIN; SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb; rec bigint; did bigint; BEGIN
 PERFORM c10_test.as_user('mgrB2'); -- reviewer/approver, but NO payment_recorder role yet
 PERFORM c10_test.denied($q$SELECT c10_demo.a054_record_external_payment_v1(102,'a054-pay-neg-01','2026-10-01',c10_test.eid(102,'B2'),100,'cash','VCH-1',current_date,NULL)$q$,'a054_delegation_denied');
 PERFORM c10_test.as_user('boB');
 PERFORM c10_demo.a054_grant_delegation_v1(102,'a054-dg-000004',c10_test.u('mgrB2'),'payment_recorder','allow',NULL,'2026-10-01','2026-10-01',NULL,'Oct payment recorder');
 PERFORM c10_test.denied($q$SELECT c10_demo.a054_record_external_payment_v1(102,'a054-pay-neg-02','2026-09-01',c10_test.eid(102,'B2'),100,'cash','VCH-1',current_date,NULL)$q$,'a054_no_approved_payable');
 PERFORM c10_test.denied($q$SELECT c10_demo.a054_record_external_payment_v1(102,'a054-pay-neg-03','2026-10-01',c10_test.eid(102,'B2'),100,'cash','VCH-1','2099-01-01',NULL)$q$,'a054_payment_date_in_future');
 PERFORM c10_test.denied($q$SELECT c10_demo.a054_record_external_payment_v1(102,'a054-pay-neg-04','2026-10-01',c10_test.eid(102,'B2'),100,'bitcoin','VCH-1',current_date,NULL)$q$,'wf_invalid_input');
 PERFORM c10_test.denied($q$SELECT c10_demo.a054_record_external_payment_v1(102,'a054-pay-neg-05','2026-10-01',c10_test.eid(102,'B2'),0,'cash','VCH-1',current_date,NULL)$q$,'wf_invalid_input');
 PERFORM c10_test.denied($q$SELECT c10_demo.a054_record_external_payment_v1(102,'a054-pay-neg-06','2026-10-01',c10_test.eid(102,'B2'),99999,'cash','VCH-1',current_date,NULL)$q$,'a054_payment_exceeds_outstanding');
 r:=c10_demo.a054_record_external_payment_v1(102,'a054-pay-000001','2026-10-01',c10_test.eid(102,'B1'),10000,'bank_transfer','EXT-BANK-REF-77',current_date,'partial, paid outside the system');
 PERFORM c10_test.eq(r->>'payment_executed','false','record never executes a payment'); PERFORM c10_test.eq(r->>'money_movement','false','no money movement');
 PERFORM c10_test.eq(c10_demo.a054_record_external_payment_v1(102,'a054-pay-000001','2026-10-01',c10_test.eid(102,'B1'),10000,'bank_transfer','EXT-BANK-REF-77',current_date,'partial, paid outside the system')::text,r::text,'idempotent replay');
 PERFORM c10_test.as_user('mgrB2');
 r:=c10_demo.a054_record_external_payment_v1(102,'a054-pay-000002','2026-10-01',c10_test.eid(102,'B2'),26572.00,'cash','EXT-CASH-5',current_date,NULL);
 rec:=(r->>'record_id')::bigint;
 PERFORM c10_test.as_user('mgrB'); -- preparer: may see liability, may NOT record payments
 PERFORM c10_test.denied($q$SELECT c10_demo.a054_record_external_payment_v1(102,'a054-pay-neg-07','2026-10-01',c10_test.eid(102,'B1'),1,'cash','VCH-9',current_date,NULL)$q$,'a054_delegation_denied');
 PERFORM c10_test.as_user('boB');
 r:=c10_demo.a054_liability_report_v1(102,'2026-10-01');
 PERFORM c10_test.eq(r->'totals'->>'partially_paid_count','1','B1 partially paid (recorded)');
 PERFORM c10_test.eq(r->'totals'->>'partially_paid_outstanding','23854.04','B1 outstanding');
 PERFORM c10_test.eq(r->'totals'->>'paid_recorded_count','1','B2 paid (recorded)');
 PERFORM c10_test.eq(r->'totals'->>'approved_unpaid_count','0','no line is wholly unpaid now');
 PERFORM c10_test.eq(r->'totals'->>'paid_recorded_amount','36572.00','recorded paid reported separately');
 PERFORM c10_test.eq(r->'totals'->>'total_outstanding','23854.04','outstanding liability');
 PERFORM c10_test.eq(r->>'paid','false','report never claims salary was paid by the system');
 -- reversal restores liability
 PERFORM c10_test.as_user('mgrB2'); PERFORM c10_test.denied(format($q$SELECT c10_demo.a054_reverse_payment_record_v1(102,'a054-rev-neg-01',%s,'recorder reverses')$q$,rec),'a054_owner_required');
 PERFORM c10_test.as_user('boB');
 PERFORM c10_demo.a054_reverse_payment_record_v1(102,'a054-rev-000001',rec,'wrong employee reference');
 PERFORM c10_test.denied(format($q$SELECT c10_demo.a054_reverse_payment_record_v1(102,'a054-rev-000002',%s,'again again')$q$,rec),'a054_already_reversed');
 r:=c10_demo.a054_liability_report_v1(102,'2026-10-01');
 PERFORM c10_test.eq(r->'totals'->>'approved_unpaid_count','1','B2 is approved-unpaid again');
 PERFORM c10_test.eq(r->'totals'->>'total_outstanding','50426.04','outstanding after reversal');
 -- revocation takes effect immediately (same session, next call)
 did:=(SELECT (x->>'id')::bigint FROM jsonb_array_elements(c10_demo.a054_list_delegations_v1(102)->'items') x WHERE x->>'role'='payment_recorder' AND x->>'state'='active');
 PERFORM c10_test.denied(format($q$SELECT c10_demo.a054_revoke_delegation_v1(102,'a054-rv-neg-001',%s,9,'wrong version')$q$,did),'wf_stale_version');
 PERFORM c10_demo.a054_revoke_delegation_v1(102,'a054-rv-000001',did,1,'recorder role withdrawn');
 PERFORM c10_test.denied(format($q$SELECT c10_demo.a054_revoke_delegation_v1(102,'a054-rv-000002',%s,2,'twice')$q$,did),'a054_already_revoked');
 PERFORM c10_test.as_user('mgrB2');
 PERFORM c10_test.denied($q$SELECT c10_demo.a054_record_external_payment_v1(102,'a054-pay-neg-08','2026-10-01',c10_test.eid(102,'B2'),100,'cash','VCH-2',current_date,NULL)$q$,'a054_delegation_denied');
 PERFORM c10_test.eq(c10_demo.a054_liability_report_v1(102,'2026-10-01')->>'paid','false','reviewer/approver roles still see liability (never as paid)');
END $$; COMMIT;
BEGIN; SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb; BEGIN
 -- expiry: a grant that lapses after one second stops working without any revoke call
 PERFORM c10_test.as_user('boB');
 PERFORM c10_demo.a054_grant_delegation_v1(102,'a054-dg-000005',c10_test.u('mgrB2'),'payment_recorder','allow',NULL,'2026-10-01','2026-10-01',clock_timestamp()+interval '2 seconds','short lived');
 PERFORM c10_test.as_user('mgrB2');
 r:=c10_demo.a054_record_external_payment_v1(102,'a054-pay-000003','2026-10-01',c10_test.eid(102,'B2'),1000,'cash','EXT-CASH-6',current_date,NULL);
 PERFORM c10_test.eq(r->>'status','recorded','within expiry');
 PERFORM pg_sleep(2.5);
 PERFORM c10_test.denied($q$SELECT c10_demo.a054_record_external_payment_v1(102,'a054-pay-neg-09','2026-10-01',c10_test.eid(102,'B2'),1000,'cash','EXT-CASH-7',current_date,NULL)$q$,'a054_delegation_denied');
 -- explicit DENY beats ALLOW
 PERFORM c10_test.as_user('boB');
 PERFORM c10_demo.a054_grant_delegation_v1(102,'a054-dg-000006',c10_test.u('mgrB2'),'payment_recorder','allow',NULL,NULL,NULL,NULL,'broad allow');
 PERFORM c10_test.as_user('mgrB2');
 PERFORM c10_test.eq(c10_demo.a054_record_external_payment_v1(102,'a054-pay-000004','2026-10-01',c10_test.eid(102,'B2'),500,'cash','EXT-CASH-8',current_date,NULL)->>'status','recorded','allowed');
 PERFORM c10_test.as_user('boB');
 PERFORM c10_demo.a054_grant_delegation_v1(102,'a054-dg-000007',c10_test.u('mgrB2'),'payment_recorder','deny',NULL,'2026-10-01','2026-10-01',NULL,'explicit deny for October');
 PERFORM c10_test.as_user('mgrB2');
 PERFORM c10_test.denied($q$SELECT c10_demo.a054_record_external_payment_v1(102,'a054-pay-neg-10','2026-10-01',c10_test.eid(102,'B2'),500,'cash','EXT-CASH-9',current_date,NULL)$q$,'a054_delegation_denied');
 -- CSV export: PII safe, idempotent, audited
 PERFORM c10_test.as_user('boB');
 r:=c10_demo.a054_export_liability_csv_v1(102,'a054-csv-000001','2026-10-01');
 PERFORM c10_test.eq((r->>'csv' LIKE 'period,employee_no,site,run_status,net,recorded_paid,outstanding,state%')::text,'true','csv header');
 PERFORM c10_test.eq((r->>'csv' ~ 'B1' AND r->>'csv' !~ 'Bela' AND r->>'csv' !~ 'Babul')::text,'true','csv has employee numbers, no names');
 PERFORM c10_test.eq(c10_demo.a054_export_liability_csv_v1(102,'a054-csv-000001','2026-10-01')::text,r::text,'csv replay');
 PERFORM c10_test.as_user('branch'); PERFORM c10_test.denied($q$SELECT c10_demo.a054_export_liability_csv_v1(102,'a054-csv-neg-01','2026-10-01')$q$,'a054_liability_denied');
END $$; COMMIT;

-- ===== S5 privacy & isolation =====
BEGIN; SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb; BEGIN
 PERFORM c10_test.as_user('branch'); -- B1 himself (linked via A053)
 r:=c10_demo.wf_my_payslips_v1(102);
 PERFORM c10_test.eq(jsonb_array_length(r->'items')::text,'1','employee sees only own payslip');
 PERFORM c10_test.eq(r->'items'->0->>'net','33854.04','own net');
 PERFORM c10_test.denied($q$SELECT c10_demo.wf_get_payroll_run_v1(102,1)$q$,'wf_payroll_access_denied');
 PERFORM c10_test.denied($q$SELECT c10_demo.wf_payslip_register_v1(102,NULL)$q$,'wf_payroll_access_denied');
 PERFORM c10_test.denied($q$SELECT c10_demo.wf_list_payroll_runs_v1(102)$q$,'wf_payroll_access_denied');
 PERFORM c10_test.denied($q$SELECT c10_demo.a054_liability_report_v1(102,NULL)$q$,'a054_liability_denied');
 PERFORM c10_test.denied($q$SELECT c10_demo.a054_list_delegations_v1(102)$q$,'a054_owner_required');
 PERFORM c10_test.denied($q$SELECT c10_demo.a054_retention_report_v1(102)$q$,'a054_owner_required');
 PERFORM c10_test.denied(format($q$SELECT c10_demo.a054_leave_balance_v1(102,%s,2026)$q$,c10_test.eid(102,'B2')),'wf_employee_not_found');
 PERFORM c10_test.eq(jsonb_array_length(c10_demo.a054_leave_balance_v1(102,NULL,2026)->'items')::text,'3','own leave balances');
 PERFORM c10_test.eq((c10_demo.wf_list_employees_v1(102,NULL,NULL,NULL,50,0)->>'total'),'1','directory shows only self');
 PERFORM c10_test.eq(c10_demo.a054_my_access_v1(102)->>'can_view_liability','false','no liability for staff');
 -- every other principal
 PERFORM c10_test.as_user('mgr101'); PERFORM c10_test.denied($q$SELECT c10_demo.a054_liability_report_v1(102,NULL)$q$,'wf_denied');
 PERFORM c10_test.as_user('investor'); PERFORM c10_test.denied($q$SELECT c10_demo.a054_liability_report_v1(101,NULL)$q$,'wf_denied');
 PERFORM c10_test.as_user('revoked'); PERFORM c10_test.denied($q$SELECT c10_demo.a054_liability_report_v1(101,NULL)$q$,'wf_denied');
 PERFORM c10_test.as_user('ownerB'); PERFORM c10_test.denied($q$SELECT c10_demo.a054_liability_report_v1(102,NULL)$q$,'wf_denied');
 PERFORM c10_test.denied($q$SELECT c10_demo.a054_list_policies_v1(102,'leave')$q$,'wf_denied');
 PERFORM c10_test.as_user('operator'); PERFORM c10_test.denied($q$SELECT c10_demo.a054_liability_report_v1(102,NULL)$q$,'wf_denied');
 PERFORM c10_test.as_user('reviewer_na'); PERFORM c10_test.denied($q$SELECT c10_demo.a054_liability_report_v1(102,NULL)$q$,'wf_denied');
 PERFORM c10_test.as_user('counter'); PERFORM c10_test.denied($q$SELECT c10_demo.a054_my_access_v1(102)$q$,'wf_denied');
 PERFORM c10_test.as_user('boB2'); -- business owner (fixture) of the same business: allowed owner-level
 PERFORM c10_test.eq(c10_demo.a054_liability_report_v1(102,'2026-10-01')->>'paid','false','fixture business owner');
 -- direct table access closed
 PERFORM c10_test.denied($q$SELECT count(*) FROM c10_demo.a054_delegations$q$,'permission denied');
 PERFORM c10_test.denied($q$SELECT count(*) FROM c10_demo.a054_payment_records$q$,'permission denied');
 PERFORM c10_test.denied($q$SELECT count(*) FROM c10_demo.a054_policy_versions$q$,'permission denied');
 PERFORM c10_test.denied($q$INSERT INTO c10_demo.a054_payment_records(tenant_id,business_id,period_start,employee_id,run_id,record_kind,amount,method,external_reference,paid_on,recorded_by,request_key) VALUES(1,102,'2026-10-01',1,1,'external_payment_record',1,'cash','x-x-x',current_date,c10_demo.actor_uid(),'direct-insert')$q$,'permission denied');
 PERFORM c10_test.denied($q$SELECT c10_demo.a054i_deleg(102,'hr',NULL,NULL,'any')$q$,'permission denied');
 PERFORM c10_test.denied($q$SELECT c10_demo.a054i_patch('c10_demo.wf_payroll_transition_v1(bigint,text,bigint,text,text)','x','y','z')$q$,'permission denied');
END $$; COMMIT;
BEGIN; SET LOCAL ROLE anon;
DO $$ BEGIN
 PERFORM c10_test.denied($q$SELECT c10_demo.a054_liability_report_v1(102,NULL)$q$,'permission denied');
 PERFORM c10_test.denied($q$SELECT c10_demo.a053_read_portfolio_workforce_v1(NULL)$q$,'permission denied');
END $$; COMMIT;
BEGIN; SET LOCAL ROLE authenticated;
DO $$ BEGIN PERFORM set_config('request.jwt.claim.sub','',true);
 PERFORM c10_test.denied($q$SELECT c10_demo.a054_liability_report_v1(102,NULL)$q$,'wf_denied');
END $$; COMMIT;

-- ===== S6 leave: accrual, carry-forward with cap and expiry, cross-year, delegated HR =====
BEGIN; SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb; l1 bigint; l2 bigint; b jsonb; BEGIN
 PERFORM c10_test.as_user('boB');
 PERFORM c10_demo.wf_save_settings_v1(102,'a054-cfg-00001',1,'{"leave_review_level":"owner"}'::jsonb,'only owners review leave');
 PERFORM c10_test.as_user('branch');
 l1:=(c10_demo.wf_request_leave_v1(102,'a054-lv-000001',NULL,'ANNUAL','2026-11-16','2026-11-19','family')->>'leave_id')::bigint;
 PERFORM c10_test.as_user('mgrB2');
 PERFORM c10_test.denied(format($q$SELECT c10_demo.wf_decide_leave_v1(102,'a054-lvd-neg-01',%s,'approve','try')$q$,l1),'wf_leave_review_denied');
 PERFORM c10_test.as_user('boB');
 PERFORM c10_demo.a054_grant_delegation_v1(102,'a054-dg-000008',c10_test.u('mgrB2'),'hr','allow',1003,NULL,NULL,NULL,'HR for the branch site');
 PERFORM c10_test.as_user('mgrB2');
 PERFORM c10_test.eq(c10_demo.wf_decide_leave_v1(102,'a054-lvd-000001',l1,'approve','delegated HR approves')->>'status','approved','delegated HR approves leave');
 PERFORM c10_test.denied($q$SELECT c10_demo.wf_save_employee_v1(102,'a054-emp-neg-01',NULL,NULL,'{"employee_no":"B9","full_name":"Site Scoped","joined_on":"2026-01-01","contract_type":"permanent","site_id":1003}'::jsonb,'site scoped hr cannot hire')$q$,'wf_employee_edit_denied');
 -- balances: 2026 used 4 => 6 left, capped carry 5 into 2027, expiry 31 Mar 2027
 PERFORM c10_test.as_user('branch');
 b:=c10_demo.a054_leave_balance_v1(102,NULL,2026)->'items'->0;
 PERFORM c10_test.eq(b->>'leave_type','ANNUAL','annual first'); PERFORM c10_test.eq(b->>'used_total','4','2026 used');
 PERFORM c10_test.eq(b->>'remaining_end','6','2026 remaining at year end');
 b:=c10_demo.a054_leave_balance_v1(102,NULL,2027)->'items'->0;
 PERFORM c10_test.eq(b->>'carried_in','5','carry-forward capped at 5 (not 6)');
 PERFORM c10_test.eq(b->>'carry_expiry_date','2027-03-31','expiry three months after Jan 1');
 -- 2027: three days in March use carried days; April ten days need the full new-year quota (carry expired)
 PERFORM c10_demo.wf_request_leave_v1(102,'a054-lv-000002',NULL,'ANNUAL','2027-03-29','2027-03-31','spring');
 PERFORM c10_demo.wf_request_leave_v1(102,'a054-lv-000003',NULL,'ANNUAL','2027-04-05','2027-04-15','long trip');
 b:=c10_demo.a054_leave_balance_v1(102,NULL,2027)->'items'->0;
 PERFORM c10_test.eq(b->>'carry_used','3','carried days used first'); PERFORM c10_test.eq(b->>'carry_expired','2','unused carry expired'); PERFORM c10_test.eq(b->>'main_used','10','new-year quota used');
 PERFORM c10_test.denied($q$SELECT c10_demo.wf_request_leave_v1(102,'a054-lv-neg-001',NULL,'ANNUAL','2027-04-19','2027-04-19','one more')$q$,'wf_leave_quota_exceeded');
 -- cross-year requests only where the policy allows (ANNUAL yes, SICK no)
 PERFORM c10_test.as_user('mgrB2');
 r:=c10_demo.wf_request_leave_v1(102,'a054-lv-000004',c10_test.eid(102,'B2'),'ANNUAL','2026-12-28','2027-01-05','year end');
 PERFORM c10_test.eq(r->>'days','8','cross-year days counted across both years');
 PERFORM c10_test.denied($q$SELECT c10_demo.wf_request_leave_v1(102,'a054-lv-neg-002',c10_test.eid(102,'B2'),'SICK','2026-12-28','2027-01-05','year end')$q$,'wf_leave_cross_year');
 -- monthly accrual: 12/yr => 2 days available by February
 PERFORM c10_test.as_user('branch');
 PERFORM c10_test.denied($q$SELECT c10_demo.wf_request_leave_v1(102,'a054-lv-neg-003',NULL,'CASUAL','2027-02-01','2027-02-03','too early')$q$,'wf_leave_quota_exceeded');
 PERFORM c10_test.eq(c10_demo.wf_request_leave_v1(102,'a054-lv-000005',NULL,'CASUAL','2027-02-01','2027-02-02','two accrued')->>'status','pending','accrued days allowed');
 -- explicit DENY on HR beats allow
 PERFORM c10_test.as_user('boB');
 PERFORM c10_demo.a054_grant_delegation_v1(102,'a054-dg-000009',c10_test.u('mgrB2'),'hr','deny',1003,NULL,NULL,NULL,'HR withdrawn at site');
 PERFORM c10_test.as_user('branch'); l2:=(c10_demo.wf_request_leave_v1(102,'a054-lv-000006',NULL,'SICK','2026-12-07','2026-12-07','unwell')->>'leave_id')::bigint;
 PERFORM c10_test.as_user('mgrB2');
 PERFORM c10_test.denied(format($q$SELECT c10_demo.wf_decide_leave_v1(102,'a054-lvd-neg-02',%s,'approve','try')$q$,l2),'a054_delegation_denied');
 -- policy changes may not rewrite a leave type that already has requests
 PERFORM c10_test.as_user('boB');
 PERFORM c10_test.denied($q$SELECT c10_demo.a054_save_policy_v1(102,'a054-pol-neg-19','leave','ANNUAL','2027-01-01','{"accrual":"upfront","annual_quota_days":30}'::jsonb,'retro',NULL)$q$,'a054_effective_date_locked');
 -- frozen October still protects leave edits (A051 invariant preserved)
 PERFORM c10_test.as_user('branch');
 PERFORM c10_test.denied($q$SELECT c10_demo.wf_request_leave_v1(102,'a054-lv-neg-004',NULL,'SICK','2026-10-20','2026-10-20','late')$q$,'wf_leave_affects_frozen_period');
END $$; COMMIT;

-- ===== S7 retention: raw punches only, legal holds, dry-run =====
BEGIN; SET LOCAL ROLE authenticated;
DO $$ BEGIN PERFORM c10_test.as_user('boB');
 PERFORM c10_demo.wf_save_settings_v1(102,'a054-cfg-00002',2,'{"punch_retention_months":12}'::jsonb,'12 month raw punch retention'); END $$; COMMIT;
INSERT INTO c10_demo.wf_punches(tenant_id,business_id,site_id,employee_id,punched_at,direction,source,batch_key,created_by)
 SELECT 1,102,1003,c10_test.eid(102,e),'2024-05-06T09:00:00+06'::timestamptz,'in','import','a054-old-'||e,c10_test.u('boB') FROM unnest(ARRAY['B1','B2']) e;
SELECT count(*) AS payslips_before FROM c10_demo.wf_payslips WHERE business_id=102 \gset
BEGIN; SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb; h bigint; BEGIN
 PERFORM c10_test.as_user('mgrB'); PERFORM c10_test.denied($q$SELECT c10_demo.a054_place_legal_hold_v1(102,'a054-hold-neg-01',NULL,'2024-01-01','2024-12-31','manager tries')$q$,'a054_owner_required');
 PERFORM c10_test.as_user('boB');
 h:=(c10_demo.a054_place_legal_hold_v1(102,'a054-hold-00001',c10_test.eid(102,'B1'),'2024-01-01','2024-12-31','labour dispute hold')->>'hold_id')::bigint;
 r:=c10_demo.a054_retention_report_v1(102);
 PERFORM c10_test.eq(r->>'expired_raw_punches','2','two expired punches'); PERFORM c10_test.eq(r->>'protected_by_legal_hold','1','one under legal hold');
 PERFORM c10_test.eq(r->>'purgeable_now','1','one purgeable'); PERFORM c10_test.eq(r->>'scope','raw_punches_only','scope');
 PERFORM c10_test.denied($q$SELECT c10_demo.wf_purge_expired_punches_v1(102,'a054-pg-neg-001',true)$q$,'wf_tenant_owner_required');
 PERFORM c10_test.as_user('owner');
 PERFORM c10_test.eq(c10_demo.wf_purge_expired_punches_v1(102,'a054-pg-000001',true)->>'rows','1','dry-run counts only unheld');
 PERFORM c10_test.eq(c10_demo.wf_purge_expired_punches_v1(102,'a054-pg-000002',false)->>'rows','1','purge deletes only the unheld punch');
 PERFORM c10_test.as_user('boB');
 PERFORM c10_test.denied(format($q$SELECT c10_demo.a054_release_legal_hold_v1(102,'a054-hold-neg-02',%s,'cannot release')$q$,h),'wf_tenant_owner_required');
 PERFORM c10_test.as_user('owner');
 PERFORM c10_demo.a054_release_legal_hold_v1(102,'a054-hold-00002',h,'dispute closed');
 PERFORM c10_test.eq(c10_demo.wf_purge_expired_punches_v1(102,'a054-pg-000003',false)->>'rows','1','released punch now purgeable');
 PERFORM c10_test.eq(c10_test.q($s$SELECT count(*) FROM c10_demo.wf_punches WHERE business_id=102 AND punched_at<'2025-01-01'$s$),'0','no expired raw punches remain');
 PERFORM c10_test.eq(c10_demo.wf_integrity_report_v1(102)->>'ok','true','audit chain intact after all A054 events');
END $$; COMMIT;
SELECT count(*)=:payslips_before AS payslips_untouched FROM c10_demo.wf_payslips WHERE business_id=102 \gset
\if :payslips_untouched
\else
 SELECT 1/0 AS payslips_were_purged;
\endif
SELECT 'A054_SQL_E2E_PASS' AS result;
