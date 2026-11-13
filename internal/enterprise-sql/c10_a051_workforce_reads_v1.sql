-- C10-A051 Workforce (4/4): role-projected reads, reports, CSV export, integrity, integration contract, grants.
-- DISPOSABLE c10_demo ONLY. Apply AFTER payroll v1. Every read is a SECURITY DEFINER RPC that re-derives the
-- caller's authority from DB memberships; no table is directly readable. Salary/PII never leave owner-gated RPCs.
CREATE FUNCTION c10_demo.wfi_level(c c10_demo.wf_ctx_t) RETURNS text LANGUAGE sql IMMUTABLE AS $$
 SELECT CASE WHEN c.is_tenant_owner THEN 'tenant_owner' WHEN c.is_business_owner THEN 'business_owner' WHEN c.is_manager THEN 'manager'
  WHEN cardinality(c.supervised_sites)>0 THEN 'supervisor' ELSE 'employee' END $$;

CREATE FUNCTION c10_demo.wf_read_overview_v1(p_business bigint) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE c wf_ctx_t; cfg wf_business_settings; own boolean; mgr boolean;
BEGIN
 c:=wfi_ctx(p_business); cfg:=wfi_cfg(p_business); own:=wfi_is_owner(c); mgr:=wfi_is_manager_plus(c);
 RETURN jsonb_build_object('server_authorized',true,'business_id',p_business,'tenant_id',c.tenant_id,'level',wfi_level(c),
  'self_employee_id',c.employee_id,'supervised_sites',to_jsonb(c.supervised_sites),'timezone','Asia/Dhaka','today',wfi_today(),
  'capabilities',jsonb_build_object('view_directory',mgr OR cardinality(c.supervised_sites)>0,
   'edit_employees',own OR (c.is_manager AND cfg.manager_can_edit_employees),'manage_structure',own,
   'assign_shifts',mgr,'import_punches',mgr OR cardinality(c.supervised_sites)>0,
   'request_correction',mgr OR cardinality(c.supervised_sites)>0,'decide_correction',own OR (c.is_manager AND cfg.manager_can_approve_corrections),
   'decide_overtime',mgr,'review_leave',own OR (c.is_manager AND cfg.leave_review_level='manager'),
   'request_leave',true,'payroll',own,'own_payslips',c.employee_id IS NOT NULL,'reports',mgr OR cardinality(c.supervised_sites)>0,
   'export_attendance',mgr,'export_payroll',own,'integrity',own),
  'settings',CASE WHEN mgr THEN to_jsonb(cfg)-'updated_by' ELSE NULL END);
END$$;

-- Businesses where the caller has ANY workforce authority (owner/manager/active employee link). Derived server-side.
CREATE FUNCTION c10_demo.wf_my_businesses_v1() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE uid uuid:=actor_uid();
BEGIN
 IF uid IS NULL THEN RAISE EXCEPTION 'wf_denied'; END IF;
 RETURN jsonb_build_object('server_authorized',true,'items',(SELECT COALESCE(jsonb_agg(jsonb_build_object('id',b.id,'tenant_id',b.tenant_id,
  'slug',b.slug) ORDER BY b.id),'[]') FROM businesses b WHERE
   can_tenant(b.tenant_id)
   OR EXISTS(SELECT 1 FROM business_members m WHERE m.user_id=uid AND m.business_id=b.id AND m.tenant_id=b.tenant_id AND m.active AND m.role IN('business_owner','manager'))
   OR EXISTS(SELECT 1 FROM wf_employees e WHERE e.user_id=uid AND e.business_id=b.id AND e.status='active')));
END$$;

CREATE FUNCTION c10_demo.wf_list_employees_v1(p_business bigint,p_search text,p_status text,p_site bigint,p_limit int,p_offset int)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE c wf_ctx_t; own boolean; mgr boolean; v_total int; items jsonb; v_lim int:=LEAST(GREATEST(COALESCE(p_limit,50),1),200);
 v_off int:=GREATEST(COALESCE(p_offset,0),0); today date:=wfi_today(); q text:=NULLIF(btrim(COALESCE(p_search,'')),'');
BEGIN
 c:=wfi_ctx(p_business); own:=wfi_is_owner(c); mgr:=wfi_is_manager_plus(c);
 IF p_status IS NOT NULL AND p_status NOT IN('active','inactive','terminated') THEN RAISE EXCEPTION 'wf_invalid_input'; END IF;
 RETURN (
  WITH base AS(
   SELECT e.*,a.site_id AS a_site,a.department_id,a.designation,a.is_supervisor
   FROM wf_employees e
   LEFT JOIN LATERAL(SELECT * FROM wf_assignments x WHERE x.employee_id=e.id AND x.effective_from<=today
     ORDER BY x.effective_from DESC,x.id DESC LIMIT 1) a ON true
   WHERE e.business_id=p_business
    AND (mgr OR e.id=c.employee_id OR a.site_id=ANY(c.supervised_sites))
    AND (p_status IS NULL OR e.status=p_status) AND (p_site IS NULL OR a.site_id=p_site)
    AND (q IS NULL OR e.full_name ILIKE '%'||replace(replace(q,'%','\%'),'_','\_')||'%' OR e.employee_no ILIKE '%'||replace(replace(q,'%','\%'),'_','\_')||'%')),
  cnt AS(SELECT count(*) n FROM base),
  pg AS(SELECT * FROM base ORDER BY employee_no LIMIT v_lim OFFSET v_off)
  SELECT jsonb_build_object('server_authorized',true,'total',(SELECT n FROM cnt),'limit',v_lim,'offset',v_off,'items',
   COALESCE(jsonb_agg(jsonb_build_object('id',p.id,'employee_no',p.employee_no,'full_name',p.full_name,'status',p.status,
    'contract_type',p.contract_type,'joined_on',p.joined_on,'version',p.version,'site_id',p.a_site,
    'site_label',(SELECT label FROM sites WHERE id=p.a_site),'department',(SELECT name FROM wf_departments WHERE id=p.department_id),
    'designation',p.designation,'is_supervisor',p.is_supervisor,
    'contact_phone',CASE WHEN own THEN p.contact_phone END,'national_id_last4',CASE WHEN own THEN p.national_id_last4 END,
    'login_linked',CASE WHEN own THEN p.user_id IS NOT NULL END) ORDER BY p.employee_no),'[]'::jsonb))
  FROM pg p);
END$$;

CREATE FUNCTION c10_demo.wf_get_employee_v1(p_business bigint,p_employee bigint) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE c wf_ctx_t; own boolean; mgr boolean; e wf_employees;
BEGIN
 c:=wfi_ctx(p_business); own:=wfi_is_owner(c); mgr:=wfi_is_manager_plus(c);
 SELECT * INTO e FROM wf_employees WHERE id=p_employee AND business_id=p_business;
 IF NOT FOUND OR NOT wfi_can_see(c,p_employee) THEN RAISE EXCEPTION 'wf_employee_not_found'; END IF;
 RETURN jsonb_build_object('server_authorized',true,'id',e.id,'employee_no',e.employee_no,'full_name',e.full_name,'status',e.status,
  'contract_type',e.contract_type,'joined_on',e.joined_on,'version',e.version,
  'contact_phone',CASE WHEN own THEN e.contact_phone END,'national_id_last4',CASE WHEN own THEN e.national_id_last4 END,
  'login_linked',CASE WHEN own THEN e.user_id IS NOT NULL END,
  'employment_history',CASE WHEN mgr OR c.employee_id=e.id THEN (SELECT COALESCE(jsonb_agg(jsonb_build_object('effective_from',h.effective_from,
    'status',h.status,'contract_type',h.contract_type,'reason',h.reason) ORDER BY h.effective_from DESC,h.id DESC),'[]') FROM wf_employment_history h WHERE h.employee_id=e.id) END,
  'assignments',(SELECT COALESCE(jsonb_agg(jsonb_build_object('effective_from',a.effective_from,'site_id',a.site_id,
    'site_label',s.label,'department',d.name,'designation',a.designation,'is_supervisor',a.is_supervisor) ORDER BY a.effective_from DESC,a.id DESC),'[]')
    FROM wf_assignments a JOIN sites s ON s.id=a.site_id LEFT JOIN wf_departments d ON d.id=a.department_id WHERE a.employee_id=e.id),
  'shift_assignments',(SELECT COALESCE(jsonb_agg(jsonb_build_object('effective_from',sa.effective_from,'shift_code',sh.code,'shift_name',sh.name)
    ORDER BY sa.effective_from DESC,sa.id DESC),'[]') FROM wf_shift_assignments sa JOIN wf_shifts sh ON sh.id=sa.shift_id WHERE sa.employee_id=e.id),
  'salary_structures',CASE WHEN own THEN (SELECT COALESCE(jsonb_agg(jsonb_build_object('effective_from',s.effective_from,'policy',p.code,
    'pay_basis',p.pay_basis,'base_amount',s.base_amount) ORDER BY s.effective_from DESC,s.id DESC),'[]')
    FROM wf_salary_structures s JOIN wf_pay_policies p ON p.id=s.policy_id WHERE s.employee_id=e.id) END);
END$$;

CREATE FUNCTION c10_demo.wf_read_catalog_v1(p_business bigint,p_year int) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE c wf_ctx_t; own boolean; mgr boolean; y int:=COALESCE(p_year,extract(year FROM wfi_today())::int);
BEGIN
 c:=wfi_ctx(p_business); own:=wfi_is_owner(c); mgr:=wfi_is_manager_plus(c);
 RETURN jsonb_build_object('server_authorized',true,'year',y,
  'sites',(SELECT COALESCE(jsonb_agg(jsonb_build_object('id',s.id,'label',s.label,'kind',s.kind) ORDER BY s.id),'[]') FROM sites s WHERE s.business_id=p_business AND (mgr OR s.id=ANY(c.supervised_sites) OR s.id=wfi_site_of(c.employee_id,wfi_today()))),
  'departments',(SELECT COALESCE(jsonb_agg(jsonb_build_object('code',d.code,'name',d.name,'active',d.active,'version',d.version) ORDER BY d.code),'[]') FROM wf_departments d WHERE d.business_id=p_business),
  'shifts',(SELECT COALESCE(jsonb_agg(jsonb_build_object('id',s.id,'code',s.code,'name',s.name,'start_time',s.start_time,'end_time',s.end_time,
    'crosses_midnight',s.end_time<=s.start_time,'break_minutes',s.break_minutes,'grace_late_minutes',s.grace_late_minutes,
    'grace_early_minutes',s.grace_early_minutes,'min_overtime_minutes',s.min_overtime_minutes,'weekly_off_days',s.weekly_off_days,
    'active',s.active,'version',s.version) ORDER BY s.code),'[]') FROM wf_shifts s WHERE s.business_id=p_business),
  'holidays',(SELECT COALESCE(jsonb_agg(jsonb_build_object('id',h.id,'date',h.holiday_date,'name',h.name,'kind',h.kind,'paid',h.paid,
    'site_id',h.site_id,'active',h.active) ORDER BY h.holiday_date),'[]') FROM wf_holidays h WHERE h.business_id=p_business AND extract(year FROM h.holiday_date)=y),
  'leave_types',(SELECT COALESCE(jsonb_agg(jsonb_build_object('id',t.id,'code',t.code,'name',t.name,'paid',t.paid,'annual_quota_days',t.annual_quota_days,
    'requires_approval',t.requires_approval,'max_days_per_request',t.max_days_per_request,'allow_backdated',t.allow_backdated,'active',t.active,
    'version',t.version) ORDER BY t.code),'[]') FROM wf_leave_types t WHERE t.business_id=p_business),
  'pay_policies',CASE WHEN own THEN (SELECT COALESCE(jsonb_agg(to_jsonb(p)-'tenant_id'-'business_id' ORDER BY p.code),'[]') FROM wf_pay_policies p WHERE p.business_id=p_business) END,
  'components',CASE WHEN own THEN (SELECT COALESCE(jsonb_agg(to_jsonb(k)-'tenant_id'-'business_id' ORDER BY k.code),'[]') FROM wf_pay_components k WHERE k.business_id=p_business) END);
END$$;

CREATE FUNCTION c10_demo.wf_list_attendance_v1(p_business bigint,p_from date,p_to date,p_employee bigint,p_site bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE c wf_ctx_t; e record; d date; dj jsonb; items jsonb:='[]'; n int:=0; today date:=wfi_today();
BEGIN
 c:=wfi_ctx(p_business);
 IF p_from IS NULL OR p_to IS NULL OR p_to<p_from OR p_to-p_from>34 THEN RAISE EXCEPTION 'wf_invalid_range'; END IF;
 FOR e IN SELECT x.id,x.employee_no,x.full_name FROM wf_employees x
   WHERE x.business_id=p_business AND (p_employee IS NULL OR x.id=p_employee) AND wfi_can_see(c,x.id)
    AND (p_site IS NULL OR wfi_site_of(x.id,p_to)=p_site) ORDER BY x.employee_no LIMIT 100 LOOP
  FOR d IN SELECT generate_series(p_from,p_to,interval '1 day')::date LOOP
   dj:=wfi_calc_day(p_business,e.id,d);
   IF dj->>'status'='not_employed' THEN CONTINUE; END IF;
   n:=n+1; IF n>1500 THEN RAISE EXCEPTION 'wf_range_too_large'; END IF;
   items:=items||jsonb_build_array(jsonb_build_object('employee_id',e.id,'employee_no',e.employee_no,'full_name',e.full_name,'date',d,
    'status',dj->>'status','first_in',dj->'first_in','last_out',dj->'last_out','scheduled_minutes',dj->'scheduled_minutes',
    'worked_minutes',dj->'worked_minutes','late_minutes',dj->'late_minutes','early_leave_minutes',dj->'early_leave_minutes',
    'overtime_minutes',dj->'overtime_minutes','overtime_approved_minutes',dj->'overtime_approved_minutes','overtime_decided',dj->'overtime_decided',
    'flags',dj->'flags','locked',wfi_period_locked(p_business,d)));
  END LOOP;
 END LOOP;
 RETURN jsonb_build_object('server_authorized',true,'from',p_from,'to',p_to,'items',items);
END$$;

CREATE FUNCTION c10_demo.wf_list_punches_v1(p_business bigint,p_employee bigint,p_from date,p_to date) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE c wf_ctx_t;
BEGIN
 c:=wfi_ctx(p_business);
 IF p_employee IS NULL OR p_from IS NULL OR p_to IS NULL OR p_to<p_from OR p_to-p_from>34 THEN RAISE EXCEPTION 'wf_invalid_range'; END IF;
 IF NOT wfi_can_see(c,p_employee) THEN RAISE EXCEPTION 'wf_employee_not_found'; END IF;
 RETURN jsonb_build_object('server_authorized',true,'items',(SELECT COALESCE(jsonb_agg(jsonb_build_object('id',p.id,'punched_at',p.punched_at,
  'direction',p.direction,'source',p.source,'status',p.status,'site_id',p.site_id) ORDER BY p.punched_at),'[]')
  FROM (SELECT * FROM wf_punches WHERE business_id=p_business AND employee_id=p_employee
    AND punched_at>=wfi_ts(p_from,'00:00') AND punched_at<wfi_ts(p_to+1,'00:00') ORDER BY punched_at LIMIT 300) p));
END$$;

CREATE FUNCTION c10_demo.wf_list_corrections_v1(p_business bigint,p_status text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE c wf_ctx_t;
BEGIN
 c:=wfi_ctx(p_business);
 IF p_status IS NOT NULL AND p_status NOT IN('pending','approved','rejected') THEN RAISE EXCEPTION 'wf_invalid_input'; END IF;
 RETURN jsonb_build_object('server_authorized',true,'items',(SELECT COALESCE(jsonb_agg(jsonb_build_object('id',r.id,'employee_id',r.employee_id,
  'employee_no',e.employee_no,'full_name',e.full_name,'work_date',r.work_date,'new_in',r.new_in,'new_out',r.new_out,'new_status',r.new_status,
  'reason',r.reason,'status',r.status,'mine',r.requested_by=c.user_id,'decision_note',r.decision_note) ORDER BY r.id DESC),'[]')
  FROM (SELECT * FROM wf_attendance_corrections WHERE business_id=p_business AND (p_status IS NULL OR status=p_status) ORDER BY id DESC LIMIT 200) r
  JOIN wf_employees e ON e.id=r.employee_id WHERE wfi_can_see(c,r.employee_id) AND (wfi_is_manager_plus(c) OR r.requested_by=c.user_id)));
END$$;

CREATE FUNCTION c10_demo.wf_list_leave_v1(p_business bigint,p_status text,p_employee bigint) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE c wf_ctx_t;
BEGIN
 c:=wfi_ctx(p_business);
 IF p_status IS NOT NULL AND p_status NOT IN('pending','approved','rejected','cancelled','revoked') THEN RAISE EXCEPTION 'wf_invalid_input'; END IF;
 RETURN jsonb_build_object('server_authorized',true,'items',(SELECT COALESCE(jsonb_agg(jsonb_build_object('id',r.id,'employee_id',r.employee_id,
  'employee_no',e.employee_no,'full_name',e.full_name,'leave_type',t.code,'leave_name',t.name,'paid',t.paid,'from_date',r.from_date,'to_date',r.to_date,
  'days',r.days,'reason',r.reason,'status',r.status,'mine',r.requested_by=c.user_id OR r.employee_id=c.employee_id,'decision_note',r.decision_note)
  ORDER BY r.from_date DESC,r.id DESC),'[]')
  FROM (SELECT * FROM wf_leave_requests WHERE business_id=p_business AND (p_status IS NULL OR status=p_status)
    AND (p_employee IS NULL OR employee_id=p_employee) ORDER BY from_date DESC,id DESC LIMIT 300) r
  JOIN wf_employees e ON e.id=r.employee_id JOIN wf_leave_types t ON t.id=r.leave_type_id WHERE wfi_can_see(c,r.employee_id)));
END$$;

CREATE FUNCTION c10_demo.wf_leave_balance_v1(p_business bigint,p_employee bigint,p_year int) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE c wf_ctx_t; v_emp bigint; y int:=COALESCE(p_year,extract(year FROM wfi_today())::int);
BEGIN
 c:=wfi_ctx(p_business); v_emp:=COALESCE(p_employee,c.employee_id);
 IF v_emp IS NULL OR NOT wfi_can_see(c,v_emp) THEN RAISE EXCEPTION 'wf_employee_not_found'; END IF;
 RETURN jsonb_build_object('server_authorized',true,'employee_id',v_emp,'year',y,'items',(SELECT COALESCE(jsonb_agg(jsonb_build_object(
  'leave_type',t.code,'name',t.name,'paid',t.paid,'quota',t.annual_quota_days,
  'approved',COALESCE((SELECT sum(days) FROM wf_leave_requests r WHERE r.employee_id=v_emp AND r.leave_type_id=t.id AND r.status='approved' AND extract(year FROM r.from_date)=y),0),
  'pending',COALESCE((SELECT sum(days) FROM wf_leave_requests r WHERE r.employee_id=v_emp AND r.leave_type_id=t.id AND r.status='pending' AND extract(year FROM r.from_date)=y),0)
  ) ORDER BY t.code),'[]') FROM wf_leave_types t WHERE t.business_id=p_business AND t.active));
END$$;

CREATE FUNCTION c10_demo.wf_list_advances_v1(p_business bigint) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE c wf_ctx_t;
BEGIN
 c:=wfi_ctx(p_business);
 RETURN jsonb_build_object('server_authorized',true,'items',(SELECT COALESCE(jsonb_agg(jsonb_build_object('id',a.id,'employee_id',a.employee_id,
  'employee_no',e.employee_no,'amount',a.amount,'installment_amount',a.installment_amount,'start_period',a.start_period,'status',a.status,
  'remaining',wfi_advance_remaining(a.id,NULL),'reason',a.reason,'money_movement',false) ORDER BY a.id DESC),'[]')
  FROM wf_advances a JOIN wf_employees e ON e.id=a.employee_id
  WHERE a.business_id=p_business AND (wfi_is_owner(c) OR a.employee_id=c.employee_id)));
END$$;

CREATE FUNCTION c10_demo.wf_list_payroll_runs_v1(p_business bigint) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE c wf_ctx_t;
BEGIN
 c:=wfi_ctx(p_business); PERFORM wfi_need(wfi_is_owner(c),'wf_payroll_access_denied');
 RETURN jsonb_build_object('server_authorized',true,'paid',false,'items',(SELECT COALESCE(jsonb_agg(jsonb_build_object('id',r.id,'period_start',r.period_start,
  'period_end',r.period_end,'version',r.version,'status',r.status,'amends_run_id',r.amends_run_id,'employee_count',r.employee_count,
  'blocking_count',r.blocking_count,'warning_count',r.warning_count,'total_gross',r.total_gross,'total_deductions',r.total_deductions,
  'total_net',r.total_net,'prepared_by_me',r.prepared_by=c.user_id,'reviewed_at',r.reviewed_at,'approved_at',r.approved_at,'frozen_at',r.frozen_at)
  ORDER BY r.period_start DESC,r.version DESC),'[]') FROM (SELECT * FROM wf_payroll_runs WHERE business_id=p_business ORDER BY period_start DESC,version DESC LIMIT 60) r));
END$$;

CREATE FUNCTION c10_demo.wf_get_payroll_run_v1(p_business bigint,p_run bigint) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE c wf_ctx_t; r wf_payroll_runs;
BEGIN
 c:=wfi_ctx(p_business); PERFORM wfi_need(wfi_is_owner(c),'wf_payroll_access_denied');
 SELECT * INTO r FROM wf_payroll_runs WHERE id=p_run AND business_id=p_business;
 IF NOT FOUND THEN RAISE EXCEPTION 'wf_payroll_run_not_found'; END IF;
 RETURN jsonb_build_object('server_authorized',true,'paid',false,'run',jsonb_build_object('id',r.id,'period_start',r.period_start,'period_end',r.period_end,
  'version',r.version,'status',r.status,'amends_run_id',r.amends_run_id,'amendment_reason',r.amendment_reason,'employee_count',r.employee_count,
  'blocking_count',r.blocking_count,'total_gross',r.total_gross,'total_deductions',r.total_deductions,'total_net',r.total_net,'note',r.note,
  'prepared_by_me',r.prepared_by=c.user_id,'config',r.config_snapshot),
  'lines',(SELECT COALESCE(jsonb_agg(to_jsonb(l)-'tenant_id'-'business_id' ORDER BY l.employee_no),'[]') FROM wf_payroll_lines l WHERE l.run_id=r.id));
END$$;

CREATE FUNCTION c10_demo.wf_my_payslips_v1(p_business bigint) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE c wf_ctx_t;
BEGIN
 c:=wfi_ctx(p_business);
 IF c.employee_id IS NULL THEN RAISE EXCEPTION 'wf_no_employee_record'; END IF;
 RETURN jsonb_build_object('server_authorized',true,'items',(SELECT COALESCE(jsonb_agg(jsonb_build_object('id',p.id,'period_start',p.period_start,
  'period_end',p.period_end,'net',p.net,'superseded',r.status='superseded','run_version',r.version) ORDER BY p.period_start DESC,r.version DESC),'[]')
  FROM wf_payslips p JOIN wf_payroll_runs r ON r.id=p.run_id WHERE p.employee_id=c.employee_id AND p.business_id=p_business));
END$$;
CREATE FUNCTION c10_demo.wf_get_my_payslip_v1(p_business bigint,p_payslip bigint) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE c wf_ctx_t; p wf_payslips; st text;
BEGIN
 c:=wfi_ctx(p_business);
 IF c.employee_id IS NULL THEN RAISE EXCEPTION 'wf_no_employee_record'; END IF;
 SELECT p2.* INTO p FROM wf_payslips p2 WHERE p2.id=p_payslip AND p2.business_id=p_business AND p2.employee_id=c.employee_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'wf_payslip_not_found'; END IF;
 SELECT status INTO st FROM wf_payroll_runs WHERE id=p.run_id;
 RETURN jsonb_build_object('server_authorized',true,'id',p.id,'superseded',st='superseded','payslip',p.snapshot);
END$$;

-- ===== Reports =====
CREATE FUNCTION c10_demo.wf_report_attendance_v1(p_business bigint,p_from date,p_to date) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE c wf_ctx_t; e record; d date; dj jsonb; agg jsonb:='{}'; k text; st text; cur jsonb; n int:=0;
BEGIN
 c:=wfi_ctx(p_business);
 PERFORM wfi_need(wfi_is_manager_plus(c) OR cardinality(c.supervised_sites)>0,'wf_report_denied');
 IF p_from IS NULL OR p_to IS NULL OR p_to<p_from OR p_to-p_from>91 THEN RAISE EXCEPTION 'wf_invalid_range'; END IF;
 FOR e IN SELECT x.id FROM wf_employees x WHERE x.business_id=p_business AND wfi_can_see(c,x.id) LOOP
  FOR d IN SELECT generate_series(p_from,p_to,interval '1 day')::date LOOP
   n:=n+1; IF n>12000 THEN RAISE EXCEPTION 'wf_range_too_large'; END IF;
   dj:=wfi_calc_day(p_business,e.id,d); st:=dj->>'status';
   IF st IN('not_employed','future') THEN CONTINUE; END IF;
   k:=COALESCE(dj->>'site_id','0');
   cur:=COALESCE(agg->k,jsonb_build_object('site_id',(dj->>'site_id')::bigint,'present',0,'half_day',0,'absent',0,'paid_leave',0,'unpaid_leave',0,
     'holiday',0,'weekly_off',0,'incomplete',0,'late_days',0,'late_minutes',0,'overtime_approved_minutes',0,'worked_minutes',0));
   cur:=jsonb_set(cur,ARRAY[st],to_jsonb(COALESCE((cur->>st)::int,0)+1));
   IF (dj->>'late_minutes')::int>0 THEN
    cur:=jsonb_set(cur,'{late_days}',to_jsonb((cur->>'late_days')::int+1));
    cur:=jsonb_set(cur,'{late_minutes}',to_jsonb((cur->>'late_minutes')::int+(dj->>'late_minutes')::int)); END IF;
   cur:=jsonb_set(cur,'{overtime_approved_minutes}',to_jsonb((cur->>'overtime_approved_minutes')::int+(dj->>'overtime_approved_minutes')::int));
   cur:=jsonb_set(cur,'{worked_minutes}',to_jsonb((cur->>'worked_minutes')::int+(dj->>'worked_minutes')::int));
   agg:=jsonb_set(agg,ARRAY[k],cur);
  END LOOP;
 END LOOP;
 RETURN jsonb_build_object('server_authorized',true,'from',p_from,'to',p_to,'sites',(SELECT COALESCE(jsonb_agg(v||jsonb_build_object('site_label',
  (SELECT label FROM sites WHERE id=(v->>'site_id')::bigint)) ORDER BY (v->>'site_id')::bigint),'[]') FROM jsonb_each(agg) j(k,v)));
END$$;

CREATE FUNCTION c10_demo.wf_report_headcount_v1(p_business bigint) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE c wf_ctx_t; today date:=wfi_today();
BEGIN
 c:=wfi_ctx(p_business);
 PERFORM wfi_need(wfi_is_manager_plus(c) OR cardinality(c.supervised_sites)>0,'wf_report_denied');
 RETURN jsonb_build_object('server_authorized',true,'as_of',today,'rows',(SELECT COALESCE(jsonb_agg(jsonb_build_object('site_id',site_id,
  'site_label',(SELECT label FROM sites WHERE id=site_id),'status',status,'contract_type',contract_type,'headcount',n) ORDER BY site_id,status,contract_type),'[]')
  FROM (SELECT wfi_site_of(e.id,today) AS site_id,e.status,e.contract_type,count(*) n FROM wf_employees e
    WHERE e.business_id=p_business AND wfi_can_see(c,e.id) GROUP BY 1,2,3) x));
END$$;

CREATE FUNCTION c10_demo.wf_report_payroll_v1(p_business bigint,p_period date) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE c wf_ctx_t; r wf_payroll_runs;
BEGIN
 c:=wfi_ctx(p_business); PERFORM wfi_need(wfi_is_owner(c),'wf_payroll_access_denied');
 SELECT * INTO r FROM wf_payroll_runs WHERE business_id=p_business AND period_start=p_period AND status IN('frozen','approved','reviewed','draft')
  ORDER BY CASE status WHEN 'frozen' THEN 0 ELSE 1 END,version DESC LIMIT 1;
 IF NOT FOUND THEN RETURN jsonb_build_object('server_authorized',true,'run',NULL,'sites','[]'::jsonb); END IF;
 RETURN jsonb_build_object('server_authorized',true,'paid',false,'run',jsonb_build_object('id',r.id,'status',r.status,'version',r.version,
  'total_gross',r.total_gross,'total_deductions',r.total_deductions,'total_net',r.total_net),
  'sites',(SELECT COALESCE(jsonb_agg(jsonb_build_object('site_id',site_id,'site_label',(SELECT label FROM sites WHERE id=site_id),'headcount',n,
    'gross',g,'deductions',dd,'net',nt) ORDER BY site_id),'[]') FROM (SELECT site_id,count(*) n,sum(gross) g,sum(total_deductions) dd,sum(net) nt
    FROM wf_payroll_lines WHERE run_id=r.id GROUP BY site_id) x));
END$$;

CREATE FUNCTION c10_demo.wf_payslip_register_v1(p_business bigint,p_period date) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE c wf_ctx_t;
BEGIN
 c:=wfi_ctx(p_business); PERFORM wfi_need(wfi_is_owner(c),'wf_payroll_access_denied');
 RETURN jsonb_build_object('server_authorized',true,'paid',false,'items',(SELECT COALESCE(jsonb_agg(jsonb_build_object('payslip_id',p.id,
  'employee_no',p.snapshot->>'employee_no','employee_name',p.snapshot->>'employee_name','period_start',p.period_start,'gross',(p.snapshot->>'gross')::numeric,
  'total_deductions',(p.snapshot->>'total_deductions')::numeric,'net',p.net,'run_version',r.version,'run_status',r.status) ORDER BY p.period_start DESC,p.snapshot->>'employee_no'),'[]')
  FROM wf_payslips p JOIN wf_payroll_runs r ON r.id=p.run_id WHERE p.business_id=p_business AND (p_period IS NULL OR p.period_start=p_period)));
END$$;

CREATE FUNCTION c10_demo.wf_audit_list_v1(p_business bigint,p_limit int) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE c wf_ctx_t;
BEGIN
 c:=wfi_ctx(p_business); PERFORM wfi_need(wfi_is_owner(c),'wf_owner_required');
 RETURN jsonb_build_object('server_authorized',true,'items',(SELECT COALESCE(jsonb_agg(jsonb_build_object('id',a.id,'entity',a.entity,
  'entity_id',a.entity_id,'event',a.event,'reason',a.reason,'created_at',a.created_at,'hash',left(a.row_hash,12)) ORDER BY a.id DESC),'[]')
  FROM (SELECT * FROM wf_audit WHERE business_id=p_business ORDER BY id DESC LIMIT LEAST(GREATEST(COALESCE(p_limit,50),1),200)) a));
END$$;

CREATE FUNCTION c10_demo.wf_integrity_report_v1(p_business bigint) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE c wf_ctx_t; checks jsonb:='[]'; a wf_audit; prev text:=NULL; ok_chain boolean:=true; bad bigint; v int;
BEGIN
 c:=wfi_ctx(p_business); PERFORM wfi_need(wfi_is_owner(c),'wf_owner_required');
 FOR a IN SELECT * FROM wf_audit WHERE business_id=p_business ORDER BY id LOOP
  IF a.prev_hash IS DISTINCT FROM prev OR a.row_hash<>wfi_audit_hash(a.prev_hash,a) THEN ok_chain:=false; bad:=a.id; EXIT; END IF;
  prev:=a.row_hash;
 END LOOP;
 checks:=checks||jsonb_build_array(jsonb_build_object('name','audit_hash_chain','ok',ok_chain,'first_bad_id',bad));
 SELECT count(*) INTO v FROM wf_payroll_runs r WHERE r.business_id=p_business AND r.status IN('frozen','superseded')
  AND (r.total_net<>COALESCE((SELECT sum(net) FROM wf_payroll_lines WHERE run_id=r.id),0) OR r.employee_count<>(SELECT count(*) FROM wf_payroll_lines WHERE run_id=r.id));
 checks:=checks||jsonb_build_array(jsonb_build_object('name','frozen_totals_match_lines','ok',v=0,'violations',v));
 SELECT count(*) INTO v FROM wf_payroll_runs r WHERE r.business_id=p_business AND r.status IN('frozen','superseded')
  AND (SELECT count(*) FROM wf_payslips WHERE run_id=r.id)<>(SELECT count(*) FROM wf_payroll_lines WHERE run_id=r.id);
 checks:=checks||jsonb_build_array(jsonb_build_object('name','payslip_per_frozen_line','ok',v=0,'violations',v));
 SELECT count(*) INTO v FROM wf_payroll_lines WHERE business_id=p_business AND (net<0 OR net<>gross-total_deductions);
 checks:=checks||jsonb_build_array(jsonb_build_object('name','no_negative_or_inconsistent_net','ok',v=0,'violations',v));
 SELECT count(*) INTO v FROM (SELECT period_start FROM wf_payroll_runs WHERE business_id=p_business AND status='frozen' GROUP BY 1 HAVING count(*)>1) x;
 checks:=checks||jsonb_build_array(jsonb_build_object('name','single_current_frozen_run_per_period','ok',v=0,'violations',v));
 SELECT count(*) INTO v FROM wf_advances a2 WHERE a2.business_id=p_business AND wfi_advance_remaining(a2.id,NULL)<0;
 checks:=checks||jsonb_build_array(jsonb_build_object('name','advance_not_over_recovered','ok',v=0,'violations',v));
 SELECT count(*) INTO v FROM wf_employees e WHERE e.business_id=p_business AND NOT EXISTS(SELECT 1 FROM wf_employment_history h WHERE h.employee_id=e.id);
 checks:=checks||jsonb_build_array(jsonb_build_object('name','employee_has_employment_history','ok',v=0,'violations',v));
 RETURN jsonb_build_object('server_authorized',true,'ok',NOT EXISTS(SELECT 1 FROM jsonb_array_elements(checks) x WHERE NOT (x->>'ok')::boolean),'checks',checks);
END$$;

CREATE FUNCTION c10_demo.wfi_csv(p text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
 SELECT '"'||replace(CASE WHEN p ~ '^[=+@\t\r-]' THEN ''''||p ELSE COALESCE(p,'') END,'"','""')||'"' $$;

CREATE FUNCTION c10_demo.wf_export_csv_v1(p_business bigint,p_request text,p_kind text,p_params jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c wf_ctx_t; pay jsonb; own boolean; out text; n int:=0; e record; d date; dj jsonb; v_from date; v_to date; v_period date; today date:=wfi_today();
BEGIN
 IF p_kind NOT IN('employees','attendance','payslip_register') OR p_kind IS NULL THEN RAISE EXCEPTION 'wf_invalid_input'; END IF;
 pay:=jsonb_build_object('k',p_kind,'p',COALESCE(p_params,'{}'));
 SELECT * INTO b FROM wfi_begin(p_business,p_request,'export_csv',pay);
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 c:=b.o_ctx; own:=wfi_is_owner(c);
 IF p_kind='employees' THEN
  PERFORM wfi_need(wfi_is_manager_plus(c),'wf_export_denied');
  out:='employee_no,name,status,contract_type,site,department,designation,joined_on'||E'\n';
  FOR e IN SELECT x.*,(SELECT label FROM sites WHERE id=wfi_site_of(x.id,today)) site_label,
     (SELECT dep.name FROM wf_assignments a LEFT JOIN wf_departments dep ON dep.id=a.department_id WHERE a.employee_id=x.id AND a.effective_from<=today ORDER BY a.effective_from DESC,a.id DESC LIMIT 1) dept,
     (SELECT designation FROM wf_assignments a WHERE a.employee_id=x.id AND a.effective_from<=today ORDER BY a.effective_from DESC,a.id DESC LIMIT 1) des
    FROM wf_employees x WHERE x.business_id=p_business ORDER BY x.employee_no LOOP
   out:=out||concat_ws(',',wfi_csv(e.employee_no),wfi_csv(CASE WHEN own THEN e.full_name ELSE wfi_mask_name(e.full_name) END),wfi_csv(e.status),
    wfi_csv(e.contract_type),wfi_csv(e.site_label),wfi_csv(e.dept),wfi_csv(e.des),wfi_csv(e.joined_on::text))||E'\n'; n:=n+1;
  END LOOP;
 ELSIF p_kind='attendance' THEN
  PERFORM wfi_need(wfi_is_manager_plus(c),'wf_export_denied');
  v_from:=(p_params->>'from')::date; v_to:=(p_params->>'to')::date;
  IF v_from IS NULL OR v_to IS NULL OR v_to<v_from OR v_to-v_from>34 THEN RAISE EXCEPTION 'wf_invalid_range'; END IF;
  out:='employee_no,name,date,status,worked_minutes,late_minutes,overtime_approved_minutes'||E'\n';
  FOR e IN SELECT x.id,x.employee_no,x.full_name FROM wf_employees x WHERE x.business_id=p_business ORDER BY x.employee_no LIMIT 200 LOOP
   FOR d IN SELECT generate_series(v_from,v_to,interval '1 day')::date LOOP
    dj:=wfi_calc_day(p_business,e.id,d); IF dj->>'status'='not_employed' THEN CONTINUE; END IF;
    n:=n+1; IF n>7000 THEN RAISE EXCEPTION 'wf_range_too_large'; END IF;
    out:=out||concat_ws(',',wfi_csv(e.employee_no),wfi_csv(CASE WHEN own THEN e.full_name ELSE wfi_mask_name(e.full_name) END),wfi_csv(d::text),
     wfi_csv(dj->>'status'),dj->>'worked_minutes',dj->>'late_minutes',dj->>'overtime_approved_minutes')||E'\n';
   END LOOP;
  END LOOP;
 ELSE
  PERFORM wfi_need(own,'wf_payroll_access_denied');
  v_period:=(p_params->>'period')::date;
  out:='employee_no,name,period,run_version,run_status,gross,total_deductions,net'||E'\n';
  FOR e IN SELECT p.*,r.version,r.status AS run_status FROM wf_payslips p JOIN wf_payroll_runs r ON r.id=p.run_id
    WHERE p.business_id=p_business AND (v_period IS NULL OR p.period_start=v_period) ORDER BY p.period_start,p.snapshot->>'employee_no' LOOP
   out:=out||concat_ws(',',wfi_csv(e.snapshot->>'employee_no'),wfi_csv(e.snapshot->>'employee_name'),wfi_csv(e.period_start::text),e.version::text,
    wfi_csv(e.run_status),e.snapshot->>'gross',e.snapshot->>'total_deductions',e.net::text)||E'\n'; n:=n+1;
  END LOOP;
 END IF;
 PERFORM wfi_log(c.tenant_id,p_business,'export',p_kind,'csv_exported',NULL,jsonb_build_object('rows',n,'params',COALESCE(p_params,'{}')),NULL,p_request);
 RETURN wfi_finish(p_business,c.tenant_id,p_request,'export_csv',pay,jsonb_build_object('server_authorized',true,'kind',p_kind,'rows',n,
  'filename','core10-workforce-'||p_kind||'.csv','pii_safe',true,'csv',out));
END$$;

-- ===== Future integration contract (read-only; never money movement) =====
CREATE FUNCTION c10_demo.read_workforce_business_summary_v1(p_business bigint,p_period date) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE c wf_ctx_t; today date:=wfi_today(); v_p date:=COALESCE(p_period,date_trunc('month',wfi_today())::date); r wf_payroll_runs;
BEGIN
 c:=wfi_ctx(p_business); PERFORM wfi_need(wfi_is_owner(c),'wf_summary_denied');
 SELECT * INTO r FROM wf_payroll_runs WHERE business_id=p_business AND period_start=v_p AND status='frozen';
 RETURN jsonb_build_object('contract','read_workforce_business_summary_v1','server_authorized',true,'business_id',p_business,'period',v_p,
  'active_headcount',(SELECT count(*) FROM wf_employees WHERE business_id=p_business AND status='active'),
  'headcount_by_site',(SELECT COALESCE(jsonb_agg(jsonb_build_object('site_id',s,'n',n)),'[]') FROM (SELECT wfi_site_of(e.id,today) s,count(*) n
    FROM wf_employees e WHERE e.business_id=p_business AND e.status='active' GROUP BY 1) x),
  'payroll',CASE WHEN r.id IS NULL THEN jsonb_build_object('status','no_frozen_run') ELSE jsonb_build_object('status','frozen','run_id',r.id,
   'version',r.version,'employee_count',r.employee_count,'total_gross',r.total_gross,'total_deductions',r.total_deductions,'total_net',r.total_net) END,
  'paid',false,'money_movement',false,'ledger_posted',false);
END$$;
CREATE FUNCTION c10_demo.read_payroll_liability_preview_v1(p_business bigint,p_period date) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE c wf_ctx_t; r wf_payroll_runs;
BEGIN
 c:=wfi_ctx(p_business); PERFORM wfi_need(wfi_is_owner(c),'wf_summary_denied');
 IF p_period IS NULL OR extract(day FROM p_period)<>1 THEN RAISE EXCEPTION 'wf_invalid_period'; END IF;
 SELECT * INTO r FROM wf_payroll_runs WHERE business_id=p_business AND period_start=p_period AND status IN('approved','frozen')
  ORDER BY CASE status WHEN 'frozen' THEN 0 ELSE 1 END LIMIT 1;
 RETURN jsonb_build_object('contract','read_payroll_liability_preview_v1','server_authorized',true,'business_id',p_business,'period',p_period,
  'basis',CASE WHEN r.id IS NULL THEN 'none' ELSE 'approved_or_frozen_run' END,
  'state',CASE WHEN r.id IS NULL THEN 'no_approved_run' ELSE 'approved_not_paid' END,
  'run_id',r.id,'gross_payable_preview',r.total_gross,'deductions_preview',r.total_deductions,'net_payable_preview',r.total_net,
  'paid',false,'money_movement',false,'ledger_posted',false,
  'note','Preview only. Payout, bank file and finance recognition are NOT performed by this module.');
END$$;

-- ===== Lock-down: RLS on, zero direct table access, explicit RPC allow-list =====
DO $$
DECLARE t record; f record;
BEGIN
 FOR t IN SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='c10_demo' AND c.relkind='r' AND c.relname LIKE 'wf\_%' LOOP
  EXECUTE format('ALTER TABLE c10_demo.%I ENABLE ROW LEVEL SECURITY',t.relname);
  EXECUTE format('REVOKE ALL ON c10_demo.%I FROM PUBLIC,anon,authenticated',t.relname);
 END LOOP;
 FOR f IN SELECT p.oid::regprocedure AS sig,p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='c10_demo' AND (p.proname LIKE 'wf\_%' OR p.proname LIKE 'wfi\_%' OR p.proname LIKE 'read\_workforce\_%' OR p.proname LIKE 'read\_payroll\_%') LOOP
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated',f.sig);
  IF f.proname ~ '^wf_.*_v1$' OR f.proname IN('read_workforce_business_summary_v1','read_payroll_liability_preview_v1') THEN
   EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated',f.sig); END IF;
 END LOOP;
END$$;
GRANT USAGE ON SCHEMA c10_demo TO authenticated;
