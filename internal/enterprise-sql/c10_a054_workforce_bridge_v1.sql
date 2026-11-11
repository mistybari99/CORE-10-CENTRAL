-- C10-A054 Workforce policy governance (2/2): MINIMAL, ASSERTED hooks into the A051 baseline. DISPOSABLE c10_demo ONLY.
-- A051 source files stay untouched. Each hook rewrites ONE exact statement of an installed A051 function via
-- pg_get_functiondef(); the install fails closed (a054_patch_target_not_found) if the statement is missing or ambiguous,
-- and is logged in a054_patch_log (idempotent). With no A054 policy/delegation rows every hook is a behavioural no-op
-- (A051 e2e must still pass: see tests/c10_a054_regression.sh). Apply AFTER c10_a054_workforce_policy_v1.sql.
CREATE TABLE c10_demo.a054_patch_log(fn text NOT NULL, marker text NOT NULL, applied_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(fn,marker));
ALTER TABLE c10_demo.a054_patch_log ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON c10_demo.a054_patch_log FROM PUBLIC,anon,authenticated;
CREATE FUNCTION c10_demo.a054i_patch(p_sig text,p_marker text,p_from text,p_to text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE d text; n text; cnt int; oid_ regprocedure:=p_sig::regprocedure;
BEGIN
 IF EXISTS(SELECT 1 FROM c10_demo.a054_patch_log WHERE fn=p_sig AND marker=p_marker) THEN RETURN; END IF;
 d:=pg_get_functiondef(oid_);
 cnt:=(length(d)-length(replace(d,p_from,'')))/length(p_from);
 IF cnt<>1 THEN RAISE EXCEPTION 'a054_patch_target_not_found % % (%)',p_sig,p_marker,cnt; END IF;
 EXECUTE replace(d,p_from,p_to);
 INSERT INTO c10_demo.a054_patch_log(fn,marker) VALUES(p_sig,p_marker);
END$$;

DO $patch$
DECLARE own text:='PERFORM wfi_need(wfi_is_owner(c),''wf_payroll_access_denied'');';
 nf text:='IF NOT FOUND THEN RAISE EXCEPTION ''wf_payroll_run_not_found''; END IF;';
BEGIN
 -- 1. Payroll calculation: effective-dated overtime policy and rule engine with trace.
 PERFORM c10_demo.a054i_patch('c10_demo.wfi_calc_line(bigint,bigint,date,date,bigint)','ot',
  'otpay:=c10_demo.wfi_rnd(hourly*(otw::numeric/60)*pol.ot_multiplier_weekday+hourly*(oto::numeric/60)*pol.ot_multiplier_offday,mode);',
  'otpay:=c10_demo.a054i_ot_pay(p_business,p_start,hourly,otw,oto,pol.ot_multiplier_weekday,pol.ot_multiplier_offday,mode);');
 PERFORM c10_demo.a054i_patch('c10_demo.wfi_calc_line(bigint,bigint,date,date,bigint)','rules',
  ' gross:=basic+otpay+allow;',
  ' IF ss.id IS NOT NULL THEN SELECT * INTO c FROM c10_demo.a054i_apply_rules(p_business,p_employee,p_start,p_end,ss.base_amount,basic,otpay,allow,emp,cal,mode,pol.pay_basis,site);'
  ||' allow:=allow+c.add_allow; odr:=odr+c.add_ded; comps:=comps||c.comps; END IF;'||E'\n'||' gross:=basic+otpay+allow;');
 -- 2. Payroll lifecycle: delegated preparer / reviewer / approver (owner path unchanged).
 PERFORM c10_demo.a054i_patch('c10_demo.wf_payroll_preview_v1(bigint,date)','access',own,
  'PERFORM wfi_need(wfi_is_owner(c) OR a054i_pay_access(p_business,''prepare''),''wf_payroll_access_denied'');'
  ||' IF NOT wfi_is_owner(c) THEN PERFORM a054i_pay_period_gate(c,p_business,''prepare'',p_period); END IF;');
 PERFORM c10_demo.a054i_patch('c10_demo.wf_create_payroll_draft_v1(bigint,text,date,bigint,text)','access',own,
  'PERFORM wfi_need(wfi_is_owner(c) OR a054i_pay_access(p_business,''prepare''),''wf_payroll_access_denied'');'
  ||' PERFORM a054i_pay_period_gate(c,p_business,''prepare'',p_period);');
 PERFORM c10_demo.a054i_patch('c10_demo.wf_recalculate_payroll_draft_v1(bigint,text,bigint)','access',own,
  'PERFORM wfi_need(wfi_is_owner(c) OR a054i_pay_access(p_business,''prepare''),''wf_payroll_access_denied'');');
 PERFORM c10_demo.a054i_patch('c10_demo.wf_recalculate_payroll_draft_v1(bigint,text,bigint)','period',nf,
  nf||' PERFORM a054i_pay_period_gate(c,p_business,''prepare'',r.period_start);');
 PERFORM c10_demo.a054i_patch('c10_demo.wf_payroll_transition_v1(bigint,text,bigint,text,text)','access',own,
  'PERFORM wfi_need(wfi_is_owner(c) OR a054i_pay_access(p_business,''transition''),''wf_payroll_access_denied'');');
 PERFORM c10_demo.a054i_patch('c10_demo.wf_payroll_transition_v1(bigint,text,bigint,text,text)','gate',nf,
  nf||' PERFORM a054i_transition_gate(c,p_business,p_action,r,cfg);');
 -- 3. Payroll reads for delegated roles (period scoped).
 PERFORM c10_demo.a054i_patch('c10_demo.wf_list_payroll_runs_v1(bigint)','access',own,
  'PERFORM wfi_need(wfi_is_owner(c) OR a054i_pay_access(p_business,''view''),''wf_payroll_access_denied'');');
 PERFORM c10_demo.a054i_patch('c10_demo.wf_list_payroll_runs_v1(bigint)','scope',
  '(SELECT * FROM wf_payroll_runs WHERE business_id=p_business ORDER BY',
  '(SELECT * FROM wf_payroll_runs WHERE business_id=p_business AND (wfi_is_owner(c) OR a054i_period_visible(p_business,period_start)) ORDER BY');
 PERFORM c10_demo.a054i_patch('c10_demo.wf_get_payroll_run_v1(bigint,bigint)','access',own,
  'PERFORM wfi_need(wfi_is_owner(c) OR a054i_pay_access(p_business,''view''),''wf_payroll_access_denied'');');
 PERFORM c10_demo.a054i_patch('c10_demo.wf_get_payroll_run_v1(bigint,bigint)','scope',nf,
  nf||' PERFORM a054i_pay_period_gate(c,p_business,''view'',r.period_start);');
 -- 4. Delegated HR: leave review, attendance corrections, employee edit (business-wide HR grant only).
 PERFORM c10_demo.a054i_patch('c10_demo.wf_decide_leave_v1(bigint,text,bigint,text,text)','access',
  'PERFORM wfi_need(wfi_is_owner(c) OR (c.is_manager AND cfg.leave_review_level=''manager''),''wf_leave_review_denied'');',
  'PERFORM wfi_need(wfi_is_owner(c) OR (c.is_manager AND cfg.leave_review_level=''manager'') OR a054i_deleg(p_business,''hr'',NULL,NULL,''any'')=''allow'',''wf_leave_review_denied'');');
 PERFORM c10_demo.a054i_patch('c10_demo.wf_decide_leave_v1(bigint,text,bigint,text,text)','scope',
  'IF NOT FOUND THEN RAISE EXCEPTION ''wf_leave_not_found''; END IF;',
  'IF NOT FOUND THEN RAISE EXCEPTION ''wf_leave_not_found''; END IF; PERFORM a054i_hr_scope(c,p_business,c.is_manager AND cfg.leave_review_level=''manager'',wfi_site_of(r.employee_id,r.from_date),r.from_date);');
 PERFORM c10_demo.a054i_patch('c10_demo.wf_decide_correction_v1(bigint,text,bigint,text,text)','access',
  'PERFORM wfi_need(wfi_is_owner(c) OR (c.is_manager AND cfg.manager_can_approve_corrections),''wf_correction_approval_denied'');',
  'PERFORM wfi_need(wfi_is_owner(c) OR (c.is_manager AND cfg.manager_can_approve_corrections) OR a054i_deleg(p_business,''hr'',NULL,NULL,''any'')=''allow'',''wf_correction_approval_denied'');');
 PERFORM c10_demo.a054i_patch('c10_demo.wf_decide_correction_v1(bigint,text,bigint,text,text)','scope',
  'IF NOT FOUND THEN RAISE EXCEPTION ''wf_correction_not_found''; END IF;',
  'IF NOT FOUND THEN RAISE EXCEPTION ''wf_correction_not_found''; END IF; PERFORM a054i_hr_scope(c,p_business,c.is_manager AND cfg.manager_can_approve_corrections,wfi_site_of(r.employee_id,r.work_date),r.work_date);');
 PERFORM c10_demo.a054i_patch('c10_demo.wf_save_employee_v1(bigint,text,bigint,bigint,jsonb,text)','access',
  'PERFORM wfi_need(wfi_is_owner(c) OR (c.is_manager AND cfg.manager_can_edit_employees),''wf_employee_edit_denied'');',
  'PERFORM wfi_need(wfi_is_owner(c) OR (c.is_manager AND cfg.manager_can_edit_employees AND a054i_deleg(p_business,''hr'',NULL,NULL,''wide'')<>''deny'') OR a054i_deleg(p_business,''hr'',NULL,NULL,''wide'')=''allow'',''wf_employee_edit_denied'');');
 -- 5. Leave policy: accrual / carry-forward / expiry / cross-year.
 PERFORM c10_demo.a054i_patch('c10_demo.wf_request_leave_v1(bigint,text,bigint,text,date,date,text)','cross',
  'IF extract(year FROM p_from)<>extract(year FROM p_to) THEN',
  'IF extract(year FROM p_from)<>extract(year FROM p_to) AND NOT a054i_leave_cross_year_ok(p_business,p_type_code,p_from) THEN');
 PERFORM c10_demo.a054i_patch('c10_demo.wf_request_leave_v1(bigint,text,bigint,text,date,date,text)','quota',
  'IF lt.annual_quota_days IS NOT NULL AND wfi_leave_used(v_emp,lt.id,extract(year FROM p_from)::int,NULL)+v_days>lt.annual_quota_days',
  'IF NOT a054i_leave_quota_ok(v_emp,lt.id,p_from,p_to,NULL)');
 PERFORM c10_demo.a054i_patch('c10_demo.wf_decide_leave_v1(bigint,text,bigint,text,text)','quota',
  'IF lt.annual_quota_days IS NOT NULL AND wfi_leave_used(r.employee_id,lt.id,extract(year FROM r.from_date)::int,r.id)+r.days>lt.annual_quota_days',
  'IF NOT a054i_leave_quota_ok(r.employee_id,lt.id,r.from_date,r.to_date,r.id)');
 -- 6. Retention: legal holds protect raw punches from purge (dry-run and real).
 PERFORM c10_demo.a054i_patch('c10_demo.wf_purge_expired_punches_v1(bigint,text,boolean)','dry',
  'SELECT count(*) INTO v_n FROM wf_punches p WHERE p.business_id=p_business AND p.punched_at<v_cut;',
  'SELECT count(*) INTO v_n FROM wf_punches p WHERE p.business_id=p_business AND p.punched_at<v_cut AND NOT a054i_punch_held(p_business,p.employee_id,(p.punched_at AT TIME ZONE ''Asia/Dhaka'')::date);');
 PERFORM c10_demo.a054i_patch('c10_demo.wf_purge_expired_punches_v1(bigint,text,boolean)','real',
  'AND NOT wfi_period_locked(p_business,(p.punched_at AT TIME ZONE ''Asia/Dhaka'')::date)',
  'AND NOT a054i_punch_held(p_business,p.employee_id,(p.punched_at AT TIME ZONE ''Asia/Dhaka'')::date) AND NOT wfi_period_locked(p_business,(p.punched_at AT TIME ZONE ''Asia/Dhaka'')::date)');
END $patch$;
REVOKE ALL ON FUNCTION c10_demo.a054i_patch(text,text,text,text) FROM PUBLIC,anon,authenticated;
