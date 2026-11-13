-- C10-A051 Workforce (3/3): pay policy, salary structure, components, advances, payroll runs, payslips.
-- DISPOSABLE c10_demo ONLY. Apply AFTER core + attendance_leave. NO payout, bank file, ledger or stock effect.
-- "Approved/Frozen" never means "Paid". Statutory/ambiguous rules ship OFF (pending_owner_approval) and
-- no Bangladesh-specific statutory rate is asserted: every multiplier/divisor is business configuration.
CREATE TABLE c10_demo.wf_pay_policies(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL, business_id bigint NOT NULL,
 code text NOT NULL CHECK(code ~ '^[A-Za-z0-9][A-Za-z0-9_-]{0,23}$'),
 name text NOT NULL CHECK(length(btrim(name)) BETWEEN 2 AND 80),
 pay_basis text NOT NULL CHECK(pay_basis IN('monthly','daily','hourly')),
 standard_hours_per_day numeric(4,2) NOT NULL DEFAULT 8 CHECK(standard_hours_per_day BETWEEN 1 AND 24),
 monthly_divisor int CHECK(monthly_divisor IS NULL OR monthly_divisor BETWEEN 20 AND 31),
 ot_multiplier_weekday numeric(4,2) NOT NULL DEFAULT 1.00 CHECK(ot_multiplier_weekday BETWEEN 0 AND 5),
 ot_multiplier_offday numeric(4,2) NOT NULL DEFAULT 1.00 CHECK(ot_multiplier_offday BETWEEN 0 AND 5),
 late_to_absent_days int CHECK(late_to_absent_days IS NULL OR late_to_absent_days BETWEEN 1 AND 31),
 paid_holidays_non_monthly boolean NOT NULL DEFAULT false,
 paid_leave_non_monthly boolean NOT NULL DEFAULT true,
 rounding_mode text NOT NULL DEFAULT 'half_up' CHECK(rounding_mode IN('half_up','down')),
 active boolean NOT NULL DEFAULT true,
 version bigint NOT NULL DEFAULT 1,
 UNIQUE(business_id,code), UNIQUE(id,tenant_id,business_id),
 FOREIGN KEY(business_id,tenant_id) REFERENCES c10_demo.businesses(id,tenant_id)
);
CREATE TABLE c10_demo.wf_salary_structures(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL, business_id bigint NOT NULL, employee_id bigint NOT NULL, policy_id bigint NOT NULL,
 base_amount numeric(14,2) NOT NULL CHECK(base_amount>=0 AND base_amount<=99999999999.99),
 effective_from date NOT NULL,
 reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 3 AND 500),
 changed_by uuid NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(employee_id,tenant_id,business_id) REFERENCES c10_demo.wf_employees(id,tenant_id,business_id),
 FOREIGN KEY(policy_id,tenant_id,business_id) REFERENCES c10_demo.wf_pay_policies(id,tenant_id,business_id)
);
CREATE INDEX wf_salary_emp_ix ON c10_demo.wf_salary_structures(employee_id,effective_from DESC,id DESC);
CREATE TRIGGER wf_salary_no_mutation BEFORE UPDATE OR DELETE ON c10_demo.wf_salary_structures FOR EACH ROW EXECUTE FUNCTION c10_demo.wfi_immutable();
CREATE TABLE c10_demo.wf_pay_components(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL, business_id bigint NOT NULL,
 code text NOT NULL CHECK(code ~ '^[A-Za-z0-9][A-Za-z0-9_-]{0,23}$'),
 name text NOT NULL CHECK(length(btrim(name)) BETWEEN 2 AND 80),
 kind text NOT NULL CHECK(kind IN('allowance','deduction')),
 calc_type text NOT NULL CHECK(calc_type IN('fixed','percent_of_base')),
 amount numeric(14,4) NOT NULL CHECK(amount>=0 AND amount<=99999999999.9999),
 prorate_partial_month boolean NOT NULL DEFAULT true,
 apply_to_all boolean NOT NULL DEFAULT false,
 statutory boolean NOT NULL DEFAULT false,
 approval_status text NOT NULL DEFAULT 'active' CHECK(approval_status IN('active','pending_owner_approval','disabled')),
 version bigint NOT NULL DEFAULT 1,
 CHECK(calc_type<>'percent_of_base' OR amount<=100),
 UNIQUE(business_id,code), UNIQUE(id,tenant_id,business_id),
 FOREIGN KEY(business_id,tenant_id) REFERENCES c10_demo.businesses(id,tenant_id)
);
CREATE TABLE c10_demo.wf_employee_components(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL, business_id bigint NOT NULL, employee_id bigint NOT NULL, component_id bigint NOT NULL,
 enabled boolean NOT NULL DEFAULT true,
 override_amount numeric(14,4) CHECK(override_amount IS NULL OR (override_amount>=0 AND override_amount<=99999999999.9999)),
 effective_from date NOT NULL,
 reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 3 AND 500),
 changed_by uuid NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(employee_id,tenant_id,business_id) REFERENCES c10_demo.wf_employees(id,tenant_id,business_id),
 FOREIGN KEY(component_id,tenant_id,business_id) REFERENCES c10_demo.wf_pay_components(id,tenant_id,business_id)
);
CREATE TRIGGER wf_empcomp_no_mutation BEFORE UPDATE OR DELETE ON c10_demo.wf_employee_components FOR EACH ROW EXECUTE FUNCTION c10_demo.wfi_immutable();
CREATE TABLE c10_demo.wf_advances(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL, business_id bigint NOT NULL, employee_id bigint NOT NULL,
 amount numeric(14,2) NOT NULL CHECK(amount>0 AND amount<=99999999999.99),
 installment_amount numeric(14,2) NOT NULL CHECK(installment_amount>0),
 start_period date NOT NULL CHECK(extract(day FROM start_period)=1),
 status text NOT NULL DEFAULT 'requested' CHECK(status IN('requested','approved','rejected','cancelled','closed')),
 reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 3 AND 500),
 requested_by uuid NOT NULL, decided_by uuid, decided_at timestamptz, decision_note text,
 request_key text NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
 CHECK(installment_amount<=amount), UNIQUE(business_id,request_key),
 FOREIGN KEY(employee_id,tenant_id,business_id) REFERENCES c10_demo.wf_employees(id,tenant_id,business_id)
);
CREATE TABLE c10_demo.wf_payroll_runs(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL, business_id bigint NOT NULL,
 period_start date NOT NULL CHECK(extract(day FROM period_start)=1),
 period_end date NOT NULL,
 version int NOT NULL DEFAULT 1,
 status text NOT NULL DEFAULT 'draft' CHECK(status IN('draft','reviewed','approved','frozen','superseded','voided')),
 amends_run_id bigint, amendment_reason text,
 config_snapshot jsonb NOT NULL DEFAULT '{}', calc_hash text NOT NULL DEFAULT '',
 employee_count int NOT NULL DEFAULT 0, blocking_count int NOT NULL DEFAULT 0, warning_count int NOT NULL DEFAULT 0,
 total_gross numeric(18,2) NOT NULL DEFAULT 0, total_deductions numeric(18,2) NOT NULL DEFAULT 0, total_net numeric(18,2) NOT NULL DEFAULT 0,
 prepared_by uuid NOT NULL, reviewed_by uuid, approved_by uuid, frozen_by uuid,
 reviewed_at timestamptz, approved_at timestamptz, frozen_at timestamptz, note text,
 request_key text NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(business_id,period_start,version), UNIQUE(business_id,request_key), UNIQUE(id,tenant_id,business_id),
 CHECK(period_end=(period_start+interval '1 month')::date-1),
 FOREIGN KEY(business_id,tenant_id) REFERENCES c10_demo.businesses(id,tenant_id)
);
CREATE UNIQUE INDEX wf_runs_inprogress_uq ON c10_demo.wf_payroll_runs(business_id,period_start) WHERE status IN('draft','reviewed','approved');
CREATE UNIQUE INDEX wf_runs_frozen_uq ON c10_demo.wf_payroll_runs(business_id,period_start) WHERE status='frozen';
CREATE FUNCTION c10_demo.wfi_run_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'wf_payroll_run_not_deletable'; END IF;
 IF OLD.status IN('frozen','superseded','voided') THEN
  IF OLD.status='frozen' AND NEW.status='superseded'
   AND (NEW.total_net,NEW.total_gross,NEW.total_deductions,NEW.calc_hash,NEW.period_start,NEW.employee_count)
     IS NOT DISTINCT FROM (OLD.total_net,OLD.total_gross,OLD.total_deductions,OLD.calc_hash,OLD.period_start,OLD.employee_count)
  THEN RETURN NEW; END IF;
  RAISE EXCEPTION 'wf_frozen_payroll_immutable';
 END IF;
 RETURN NEW;
END$$;
CREATE TRIGGER wf_runs_guard BEFORE UPDATE OR DELETE ON c10_demo.wf_payroll_runs FOR EACH ROW EXECUTE FUNCTION c10_demo.wfi_run_guard();
CREATE TABLE c10_demo.wf_payroll_lines(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL, business_id bigint NOT NULL, run_id bigint NOT NULL, employee_id bigint NOT NULL,
 employee_no text NOT NULL, employee_name text NOT NULL, site_id bigint, department text, pay_basis text,
 base_amount numeric(14,2) NOT NULL DEFAULT 0,
 calendar_days int NOT NULL, employed_days int NOT NULL,
 present_days int NOT NULL DEFAULT 0, half_days int NOT NULL DEFAULT 0, absent_days int NOT NULL DEFAULT 0,
 paid_leave_days int NOT NULL DEFAULT 0, unpaid_leave_days int NOT NULL DEFAULT 0, holiday_days int NOT NULL DEFAULT 0,
 late_days int NOT NULL DEFAULT 0, worked_minutes int NOT NULL DEFAULT 0, overtime_minutes_approved int NOT NULL DEFAULT 0,
 basic_earned numeric(16,2) NOT NULL DEFAULT 0, overtime_pay numeric(16,2) NOT NULL DEFAULT 0, allowances_total numeric(16,2) NOT NULL DEFAULT 0,
 gross numeric(16,2) NOT NULL DEFAULT 0, absence_deduction numeric(16,2) NOT NULL DEFAULT 0,
 other_deductions_total numeric(16,2) NOT NULL DEFAULT 0, advance_recovery numeric(16,2) NOT NULL DEFAULT 0,
 total_deductions numeric(16,2) NOT NULL DEFAULT 0, net numeric(16,2) NOT NULL DEFAULT 0,
 components jsonb NOT NULL DEFAULT '[]', advances jsonb NOT NULL DEFAULT '[]', warnings jsonb NOT NULL DEFAULT '[]',
 UNIQUE(run_id,employee_id), CHECK(net>=0), CHECK(net=gross-total_deductions),
 FOREIGN KEY(run_id,tenant_id,business_id) REFERENCES c10_demo.wf_payroll_runs(id,tenant_id,business_id),
 FOREIGN KEY(employee_id,tenant_id,business_id) REFERENCES c10_demo.wf_employees(id,tenant_id,business_id)
);
CREATE FUNCTION c10_demo.wfi_line_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_status text; v_run bigint:=COALESCE(NEW.run_id,OLD.run_id);
BEGIN
 SELECT status INTO v_status FROM c10_demo.wf_payroll_runs WHERE id=v_run;
 IF v_status IS DISTINCT FROM 'draft' THEN RAISE EXCEPTION 'wf_frozen_payroll_immutable'; END IF;
 RETURN COALESCE(NEW,OLD);
END$$;
CREATE TRIGGER wf_lines_guard BEFORE INSERT OR UPDATE OR DELETE ON c10_demo.wf_payroll_lines FOR EACH ROW EXECUTE FUNCTION c10_demo.wfi_line_guard();
CREATE TABLE c10_demo.wf_payslips(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL, business_id bigint NOT NULL, run_id bigint NOT NULL, employee_id bigint NOT NULL,
 period_start date NOT NULL, period_end date NOT NULL, snapshot jsonb NOT NULL,
 net numeric(16,2) NOT NULL, issued_at timestamptz NOT NULL DEFAULT now(), issued_by uuid NOT NULL,
 UNIQUE(run_id,employee_id),
 FOREIGN KEY(run_id,tenant_id,business_id) REFERENCES c10_demo.wf_payroll_runs(id,tenant_id,business_id),
 FOREIGN KEY(employee_id,tenant_id,business_id) REFERENCES c10_demo.wf_employees(id,tenant_id,business_id)
);
CREATE INDEX wf_payslips_emp_ix ON c10_demo.wf_payslips(employee_id,period_start DESC);
CREATE TRIGGER wf_payslips_no_mutation BEFORE UPDATE OR DELETE ON c10_demo.wf_payslips FOR EACH ROW EXECUTE FUNCTION c10_demo.wfi_immutable();
CREATE TABLE c10_demo.wf_advance_recoveries(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL, business_id bigint NOT NULL, advance_id bigint NOT NULL, run_id bigint NOT NULL,
 amount numeric(14,2) NOT NULL CHECK(amount>0), created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(advance_id,run_id),
 FOREIGN KEY(advance_id) REFERENCES c10_demo.wf_advances(id),
 FOREIGN KEY(run_id,tenant_id,business_id) REFERENCES c10_demo.wf_payroll_runs(id,tenant_id,business_id)
);
CREATE TRIGGER wf_recov_no_mutation BEFORE UPDATE OR DELETE ON c10_demo.wf_advance_recoveries FOR EACH ROW EXECUTE FUNCTION c10_demo.wfi_immutable();

CREATE FUNCTION c10_demo.wfi_rnd(p numeric,p_mode text) RETURNS numeric LANGUAGE sql IMMUTABLE AS
$$ SELECT CASE WHEN p_mode='down' THEN trunc(p,2) ELSE round(p,2) END $$;
CREATE FUNCTION c10_demo.wfi_advance_remaining(p_advance bigint,p_exclude_run bigint) RETURNS numeric LANGUAGE sql STABLE AS
$$ SELECT a.amount-COALESCE((SELECT sum(r.amount) FROM c10_demo.wf_advance_recoveries r JOIN c10_demo.wf_payroll_runs u ON u.id=r.run_id
    WHERE r.advance_id=a.id AND u.status='frozen' AND u.id<>COALESCE(p_exclude_run,-1)),0)
   FROM c10_demo.wf_advances a WHERE a.id=p_advance $$;

-- ===== Deterministic per-employee calculation (pure) =====
CREATE FUNCTION c10_demo.wfi_calc_line(p_business bigint,p_employee bigint,p_start date,p_end date,p_exclude_run bigint) RETURNS jsonb
LANGUAGE plpgsql AS $$
DECLARE e c10_demo.wf_employees; ss c10_demo.wf_salary_structures; pol c10_demo.wf_pay_policies; d date; dj jsonb; st text;
 cal int:=p_end-p_start+1; emp int:=0; pres int:=0; half int:=0; absn int:=0; pl int:=0; ul int:=0; hol int:=0; hol_paid int:=0; late int:=0;
 inc int:=0; fut int:=0; pend_ot int:=0; wmin int:=0; rmin int:=0; otw int:=0; oto int:=0; otun int:=0;
 w jsonb:='[]'; basic numeric:=0; otpay numeric:=0; allow numeric:=0; absd numeric:=0; odr numeric:=0; od numeric:=0; adv numeric:=0;
 hourly numeric:=0; daily numeric:=0; divisor numeric; eq numeric; paid numeric; room numeric; gross numeric; comps jsonb:='[]'; advs jsonb:='[]';
 c record; v numeric; amt numeric; av record; rem numeric; take numeric; site bigint; dept text; mode text; pend int; v_name text;
BEGIN
 SELECT * INTO e FROM c10_demo.wf_employees WHERE id=p_employee AND business_id=p_business;
 SELECT * INTO ss FROM c10_demo.wf_salary_structures WHERE employee_id=p_employee AND effective_from<=p_end ORDER BY effective_from DESC,id DESC LIMIT 1;
 IF ss.id IS NOT NULL THEN SELECT * INTO pol FROM c10_demo.wf_pay_policies WHERE id=ss.policy_id; END IF;
 mode:=COALESCE(pol.rounding_mode,'half_up');
 FOR d IN SELECT generate_series(p_start,p_end,interval '1 day')::date LOOP
  dj:=c10_demo.wfi_calc_day(p_business,p_employee,d); st:=dj->>'status';
  IF st='not_employed' THEN CONTINUE; END IF;
  emp:=emp+1;
  IF st IN('present','half_day') THEN
   IF st='present' THEN pres:=pres+1; ELSE half:=half+1; END IF;
   IF (dj->>'late_minutes')::int>0 THEN late:=late+1; END IF;
   wmin:=wmin+(dj->>'worked_minutes')::int; rmin:=rmin+(dj->>'worked_minutes')::int-(dj->>'overtime_minutes')::int;
   IF (dj->>'overtime_minutes')::int>0 THEN
    IF dj->>'overtime_kind'='off_day' THEN oto:=oto+(dj->>'overtime_approved_minutes')::int; ELSE otw:=otw+(dj->>'overtime_approved_minutes')::int; END IF;
    otun:=otun+(dj->>'overtime_minutes')::int-(dj->>'overtime_approved_minutes')::int;
    IF NOT (dj->>'overtime_decided')::boolean THEN pend_ot:=pend_ot+1; END IF;
   END IF;
  ELSIF st='absent' THEN absn:=absn+1;
  ELSIF st='paid_leave' THEN pl:=pl+1;
  ELSIF st='unpaid_leave' THEN ul:=ul+1;
  ELSIF st='holiday' THEN hol:=hol+1; IF COALESCE((dj->>'holiday_paid')::boolean,true) THEN hol_paid:=hol_paid+1; END IF;
  ELSIF st='incomplete' THEN inc:=inc+1;
  ELSIF st='future' THEN fut:=fut+1; END IF;
 END LOOP;
 site:=c10_demo.wfi_site_of(p_employee,p_end);
 SELECT dep.name INTO dept FROM c10_demo.wf_assignments a LEFT JOIN c10_demo.wf_departments dep ON dep.id=a.department_id
  WHERE a.employee_id=p_employee AND a.effective_from<=p_end ORDER BY a.effective_from DESC,a.id DESC LIMIT 1;
 IF emp=0 THEN RETURN jsonb_build_object('employed_days',0); END IF;
 IF ss.id IS NULL THEN w:=w||jsonb_build_array(jsonb_build_object('code','no_salary_structure','blocking',true));
 ELSE
  IF pol.pay_basis='monthly' THEN
   divisor:=COALESCE(pol.monthly_divisor,cal);
   basic:=c10_demo.wfi_rnd(ss.base_amount*emp/cal,mode);
   daily:=ss.base_amount/divisor; hourly:=ss.base_amount/(divisor*pol.standard_hours_per_day);
   eq:=absn+ul+0.5*half+CASE WHEN pol.late_to_absent_days IS NOT NULL THEN floor(late::numeric/pol.late_to_absent_days) ELSE 0 END;
   absd:=LEAST(c10_demo.wfi_rnd(daily*eq,mode),basic);
  ELSIF pol.pay_basis='daily' THEN
   paid:=pres+0.5*half+CASE WHEN pol.paid_leave_non_monthly THEN pl ELSE 0 END+CASE WHEN pol.paid_holidays_non_monthly THEN hol_paid ELSE 0 END;
   basic:=c10_demo.wfi_rnd(ss.base_amount*paid,mode); hourly:=ss.base_amount/pol.standard_hours_per_day;
  ELSE
   paid:=(rmin::numeric/60)+pol.standard_hours_per_day*(CASE WHEN pol.paid_leave_non_monthly THEN pl ELSE 0 END+CASE WHEN pol.paid_holidays_non_monthly THEN hol_paid ELSE 0 END);
   basic:=c10_demo.wfi_rnd(ss.base_amount*paid,mode); hourly:=ss.base_amount;
  END IF;
  otpay:=c10_demo.wfi_rnd(hourly*(otw::numeric/60)*pol.ot_multiplier_weekday+hourly*(oto::numeric/60)*pol.ot_multiplier_offday,mode);
  FOR c IN SELECT pc.*,ea.id AS ea_id,ea.enabled AS ea_enabled,ea.override_amount AS ea_amt
    FROM c10_demo.wf_pay_components pc
    LEFT JOIN LATERAL(SELECT * FROM c10_demo.wf_employee_components x WHERE x.employee_id=p_employee AND x.component_id=pc.id
      AND x.effective_from<=p_end ORDER BY x.effective_from DESC,x.id DESC LIMIT 1) ea ON true
    WHERE pc.business_id=p_business AND pc.approval_status='active'
     AND CASE WHEN ea.id IS NOT NULL THEN ea.enabled ELSE pc.apply_to_all END ORDER BY pc.code LOOP
   amt:=COALESCE(c.ea_amt,c.amount);
   IF c.calc_type='fixed' THEN
    v:=amt; IF pol.pay_basis='monthly' AND c.prorate_partial_month AND emp<cal THEN v:=amt*emp/cal; END IF;
    v:=c10_demo.wfi_rnd(v,mode);
   ELSE v:=c10_demo.wfi_rnd(basic*amt/100,mode); END IF;
   IF c.kind='allowance' THEN allow:=allow+v; ELSE odr:=odr+v; END IF;
   comps:=comps||jsonb_build_array(jsonb_build_object('code',c.code,'name',c.name,'kind',c.kind,'amount',v));
  END LOOP;
 END IF;
 gross:=basic+otpay+allow;
 room:=gross-absd;
 od:=LEAST(odr,room);
 IF od<odr THEN w:=w||jsonb_build_array(jsonb_build_object('code','deduction_capped','blocking',false,'wanted',odr,'applied',od)); END IF;
 room:=room-od;
 IF ss.id IS NOT NULL THEN
  FOR av IN SELECT * FROM c10_demo.wf_advances WHERE employee_id=p_employee AND business_id=p_business AND status='approved'
    AND start_period<=p_start ORDER BY id LOOP
   rem:=c10_demo.wfi_advance_remaining(av.id,p_exclude_run);
   IF rem<=0 THEN CONTINUE; END IF;
   take:=LEAST(av.installment_amount,rem,room);
   IF take<LEAST(av.installment_amount,rem) THEN
    w:=w||jsonb_build_array(jsonb_build_object('code','advance_recovery_limited','blocking',false,'advance_id',av.id)); END IF;
   IF take>0 THEN adv:=adv+take; room:=room-take; advs:=advs||jsonb_build_array(jsonb_build_object('advance_id',av.id,'amount',take)); END IF;
  END LOOP;
 END IF;
 IF inc>0 THEN w:=w||jsonb_build_array(jsonb_build_object('code','incomplete_attendance','blocking',true,'days',inc)); END IF;
 IF fut>0 THEN w:=w||jsonb_build_array(jsonb_build_object('code','period_not_ended','blocking',true,'days',fut)); END IF;
 IF pend_ot>0 THEN w:=w||jsonb_build_array(jsonb_build_object('code','overtime_decision_pending','blocking',true,'days',pend_ot)); END IF;
 SELECT count(*) INTO pend FROM c10_demo.wf_leave_requests WHERE employee_id=p_employee AND status='pending' AND from_date<=p_end AND to_date>=p_start;
 IF pend>0 THEN w:=w||jsonb_build_array(jsonb_build_object('code','leave_decision_pending','blocking',true,'count',pend)); END IF;
 SELECT count(*) INTO pend FROM c10_demo.wf_attendance_corrections WHERE employee_id=p_employee AND status='pending' AND work_date BETWEEN p_start AND p_end;
 IF pend>0 THEN w:=w||jsonb_build_array(jsonb_build_object('code','correction_decision_pending','blocking',true,'count',pend)); END IF;
 IF otun>0 THEN w:=w||jsonb_build_array(jsonb_build_object('code','overtime_unapproved_not_paid','blocking',false,'minutes',otun)); END IF;
 RETURN jsonb_build_object('employee_id',p_employee,'employee_no',e.employee_no,'employee_name',e.full_name,'site_id',site,'department',dept,
  'pay_basis',pol.pay_basis,'base_amount',COALESCE(ss.base_amount,0),'calendar_days',cal,'employed_days',emp,'present_days',pres,
  'half_days',half,'absent_days',absn,'paid_leave_days',pl,'unpaid_leave_days',ul,'holiday_days',hol,'late_days',late,
  'worked_minutes',wmin,'overtime_minutes_approved',otw+oto,'basic_earned',basic,'overtime_pay',otpay,'allowances_total',allow,
  'gross',gross,'absence_deduction',absd,'other_deductions_total',od,'advance_recovery',adv,
  'total_deductions',absd+od+adv,'net',gross-absd-od-adv,'components',comps,'advances',advs,'warnings',w);
END$$;

CREATE FUNCTION c10_demo.wfi_calc_run(p_business bigint,p_start date,p_exclude_run bigint) RETURNS jsonb
LANGUAGE plpgsql AS $$
DECLARE v_end date:=(p_start+interval '1 month')::date-1; e record; l jsonb; lines jsonb:='[]'; g numeric:=0; dd numeric:=0; n numeric:=0;
 blk int:=0; wrn int:=0; h text:=''; cnt int:=0; x jsonb;
BEGIN
 FOR e IN SELECT id FROM c10_demo.wf_employees WHERE business_id=p_business AND joined_on<=v_end ORDER BY id LOOP
  cnt:=cnt+1; IF cnt>1000 THEN RAISE EXCEPTION 'wf_too_many_employees'; END IF;
  l:=c10_demo.wfi_calc_line(p_business,e.id,p_start,v_end,p_exclude_run);
  IF (l->>'employed_days')::int=0 THEN CONTINUE; END IF;
  lines:=lines||jsonb_build_array(l);
  g:=g+(l->>'gross')::numeric; dd:=dd+(l->>'total_deductions')::numeric; n:=n+(l->>'net')::numeric;
  FOR x IN SELECT * FROM jsonb_array_elements(l->'warnings') LOOP
   IF (x->>'blocking')::boolean THEN blk:=blk+1; ELSE wrn:=wrn+1; END IF; END LOOP;
  h:=h||(l->>'employee_id')||':'||(l->>'basic_earned')||':'||(l->>'overtime_pay')||':'||(l->>'allowances_total')||':'||(l->>'gross')||':'
   ||(l->>'total_deductions')||':'||(l->>'net')||':'||(l->>'employed_days')||';';
 END LOOP;
 RETURN jsonb_build_object('period_start',p_start,'period_end',v_end,'lines',lines,'employee_count',jsonb_array_length(lines),
  'total_gross',g,'total_deductions',dd,'total_net',n,'blocking_count',blk,'warning_count',wrn,
  'calc_hash',encode(sha256(convert_to(h,'UTF8')),'hex'));
END$$;

-- ===== Policies, structures, components, advances =====
CREATE FUNCTION c10_demo.wf_save_pay_policy_v1(p_business bigint,p_request text,p_expected_version bigint,p_policy jsonb,p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c wf_ctx_t; pay jsonb; pp wf_pay_policies; v_id bigint; res jsonb;
BEGIN
 IF p_policy IS NULL OR jsonb_typeof(p_policy)<>'object' OR p_expected_version IS NULL OR p_reason IS NULL
  OR length(btrim(p_reason)) NOT BETWEEN 3 AND 500 THEN RAISE EXCEPTION 'wf_invalid_input'; END IF;
 pay:=jsonb_build_object('v',p_expected_version,'p',p_policy,'r',btrim(p_reason));
 SELECT * INTO b FROM wfi_begin(p_business,p_request,'save_pay_policy',pay);
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 c:=b.o_ctx; PERFORM wfi_need(wfi_is_owner(c),'wf_owner_required');
 BEGIN
  SELECT * INTO pp FROM wf_pay_policies WHERE business_id=p_business AND code=p_policy->>'code' FOR UPDATE;
  IF NOT FOUND THEN
   IF p_expected_version<>0 THEN RAISE EXCEPTION 'wf_stale_version'; END IF;
   INSERT INTO wf_pay_policies(tenant_id,business_id,code,name,pay_basis,standard_hours_per_day,monthly_divisor,ot_multiplier_weekday,
    ot_multiplier_offday,late_to_absent_days,paid_holidays_non_monthly,paid_leave_non_monthly,rounding_mode,active)
   VALUES(c.tenant_id,p_business,p_policy->>'code',btrim(p_policy->>'name'),p_policy->>'pay_basis',
    COALESCE((p_policy->>'standard_hours_per_day')::numeric,8),(p_policy->>'monthly_divisor')::int,
    COALESCE((p_policy->>'ot_multiplier_weekday')::numeric,1),COALESCE((p_policy->>'ot_multiplier_offday')::numeric,1),
    (p_policy->>'late_to_absent_days')::int,COALESCE((p_policy->>'paid_holidays_non_monthly')::boolean,false),
    COALESCE((p_policy->>'paid_leave_non_monthly')::boolean,true),COALESCE(p_policy->>'rounding_mode','half_up'),
    COALESCE((p_policy->>'active')::boolean,true)) RETURNING id INTO v_id;
   res:=jsonb_build_object('status','created','policy_id',v_id,'version',1);
  ELSE
   IF pp.version<>p_expected_version THEN RAISE EXCEPTION 'wf_stale_version'; END IF;
   IF p_policy->>'pay_basis'<>pp.pay_basis THEN RAISE EXCEPTION 'wf_pay_basis_immutable'; END IF;
   UPDATE wf_pay_policies SET name=btrim(p_policy->>'name'),standard_hours_per_day=COALESCE((p_policy->>'standard_hours_per_day')::numeric,8),
    monthly_divisor=(p_policy->>'monthly_divisor')::int,ot_multiplier_weekday=COALESCE((p_policy->>'ot_multiplier_weekday')::numeric,1),
    ot_multiplier_offday=COALESCE((p_policy->>'ot_multiplier_offday')::numeric,1),late_to_absent_days=(p_policy->>'late_to_absent_days')::int,
    paid_holidays_non_monthly=COALESCE((p_policy->>'paid_holidays_non_monthly')::boolean,false),
    paid_leave_non_monthly=COALESCE((p_policy->>'paid_leave_non_monthly')::boolean,true),
    rounding_mode=COALESCE(p_policy->>'rounding_mode','half_up'),active=COALESCE((p_policy->>'active')::boolean,true),version=version+1
   WHERE id=pp.id;
   v_id:=pp.id; res:=jsonb_build_object('status','updated','policy_id',v_id,'version',pp.version+1);
  END IF;
 EXCEPTION WHEN check_violation OR invalid_text_representation OR not_null_violation OR numeric_value_out_of_range THEN
  RAISE EXCEPTION 'wf_invalid_input'; END;
 PERFORM wfi_log(c.tenant_id,p_business,'pay_policy',v_id::text,'saved',CASE WHEN pp.id IS NULL THEN NULL ELSE to_jsonb(pp) END,p_policy,p_reason,p_request);
 RETURN wfi_finish(p_business,c.tenant_id,p_request,'save_pay_policy',pay,res);
END$$;

CREATE FUNCTION c10_demo.wf_set_salary_structure_v1(p_business bigint,p_request text,p_employee bigint,p_policy_code text,
 p_base numeric,p_effective_from date,p_reason text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c wf_ctx_t; pay jsonb; e wf_employees; pp wf_pay_policies; res jsonb;
BEGIN
 IF p_employee IS NULL OR p_policy_code IS NULL OR p_base IS NULL OR p_base<0 OR p_base>99999999999.99
  OR scale(p_base)>2 OR p_effective_from IS NULL OR p_reason IS NULL OR length(btrim(p_reason)) NOT BETWEEN 3 AND 500
 THEN RAISE EXCEPTION 'wf_invalid_input'; END IF;
 pay:=jsonb_build_object('e',p_employee,'p',p_policy_code,'b',p_base,'d',p_effective_from,'r',btrim(p_reason));
 SELECT * INTO b FROM wfi_begin(p_business,p_request,'set_salary',pay);
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 c:=b.o_ctx; PERFORM wfi_need(wfi_is_owner(c),'wf_owner_required');
 SELECT * INTO e FROM wf_employees WHERE id=p_employee AND business_id=p_business;
 IF NOT FOUND THEN RAISE EXCEPTION 'wf_employee_not_found'; END IF;
 SELECT * INTO pp FROM wf_pay_policies WHERE business_id=p_business AND code=p_policy_code AND active;
 IF NOT FOUND THEN RAISE EXCEPTION 'wf_pay_policy_not_found'; END IF;
 IF p_effective_from<e.joined_on THEN RAISE EXCEPTION 'wf_invalid_effective_date'; END IF;
 INSERT INTO wf_salary_structures(tenant_id,business_id,employee_id,policy_id,base_amount,effective_from,reason,changed_by)
 VALUES(c.tenant_id,p_business,p_employee,pp.id,p_base,p_effective_from,btrim(p_reason),c.user_id);
 res:=jsonb_build_object('status','applied');
 -- Audit keeps the fact of the change; the amount itself is only in the owner-gated table.
 PERFORM wfi_log(c.tenant_id,p_business,'salary_structure',p_employee::text,'set',NULL,
  jsonb_build_object('policy',p_policy_code,'effective_from',p_effective_from,'base_changed',true),p_reason,p_request);
 RETURN wfi_finish(p_business,c.tenant_id,p_request,'set_salary',jsonb_build_object('e',p_employee,'p',p_policy_code,'d',p_effective_from),res);
END$$;

CREATE FUNCTION c10_demo.wf_save_component_v1(p_business bigint,p_request text,p_expected_version bigint,p_component jsonb,p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c wf_ctx_t; pay jsonb; pc wf_pay_components; v_id bigint; res jsonb; v_status text; v_stat boolean;
BEGIN
 IF p_component IS NULL OR jsonb_typeof(p_component)<>'object' OR p_expected_version IS NULL OR p_reason IS NULL
  OR length(btrim(p_reason)) NOT BETWEEN 3 AND 500 THEN RAISE EXCEPTION 'wf_invalid_input'; END IF;
 pay:=jsonb_build_object('v',p_expected_version,'c',p_component,'r',btrim(p_reason));
 SELECT * INTO b FROM wfi_begin(p_business,p_request,'save_component',pay);
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 c:=b.o_ctx; PERFORM wfi_need(wfi_is_owner(c),'wf_owner_required');
 v_stat:=COALESCE((p_component->>'statutory')::boolean,false);
 v_status:=COALESCE(p_component->>'approval_status',CASE WHEN v_stat THEN 'pending_owner_approval' ELSE 'active' END);
 -- Statutory / ambiguous rules default OFF; only the tenant owner may switch one ON.
 IF v_stat AND v_status='active' AND NOT c.is_tenant_owner THEN RAISE EXCEPTION 'wf_statutory_requires_tenant_owner'; END IF;
 BEGIN
  SELECT * INTO pc FROM wf_pay_components WHERE business_id=p_business AND code=p_component->>'code' FOR UPDATE;
  IF NOT FOUND THEN
   IF p_expected_version<>0 THEN RAISE EXCEPTION 'wf_stale_version'; END IF;
   INSERT INTO wf_pay_components(tenant_id,business_id,code,name,kind,calc_type,amount,prorate_partial_month,apply_to_all,statutory,approval_status)
   VALUES(c.tenant_id,p_business,p_component->>'code',btrim(p_component->>'name'),p_component->>'kind',p_component->>'calc_type',
    (p_component->>'amount')::numeric,COALESCE((p_component->>'prorate_partial_month')::boolean,true),
    COALESCE((p_component->>'apply_to_all')::boolean,false),v_stat,v_status) RETURNING id INTO v_id;
   res:=jsonb_build_object('status','created','component_id',v_id,'version',1,'approval_status',v_status);
  ELSE
   IF pc.version<>p_expected_version THEN RAISE EXCEPTION 'wf_stale_version'; END IF;
   IF pc.statutory<>v_stat THEN RAISE EXCEPTION 'wf_statutory_flag_immutable'; END IF;
   IF pc.approval_status<>'active' AND v_status='active' AND pc.statutory AND NOT c.is_tenant_owner THEN
    RAISE EXCEPTION 'wf_statutory_requires_tenant_owner'; END IF;
   UPDATE wf_pay_components SET name=btrim(p_component->>'name'),kind=p_component->>'kind',calc_type=p_component->>'calc_type',
    amount=(p_component->>'amount')::numeric,prorate_partial_month=COALESCE((p_component->>'prorate_partial_month')::boolean,true),
    apply_to_all=COALESCE((p_component->>'apply_to_all')::boolean,false),
    approval_status=CASE WHEN pc.statutory AND p_component->>'approval_status' IS NULL THEN pc.approval_status ELSE v_status END,
    version=version+1 WHERE id=pc.id;
   v_id:=pc.id; res:=jsonb_build_object('status','updated','component_id',v_id,'version',pc.version+1);
  END IF;
 EXCEPTION WHEN check_violation OR invalid_text_representation OR not_null_violation OR numeric_value_out_of_range THEN
  RAISE EXCEPTION 'wf_invalid_input'; END;
 PERFORM wfi_log(c.tenant_id,p_business,'pay_component',v_id::text,'saved',CASE WHEN pc.id IS NULL THEN NULL ELSE to_jsonb(pc) END,p_component,p_reason,p_request);
 RETURN wfi_finish(p_business,c.tenant_id,p_request,'save_component',pay,res);
END$$;

CREATE FUNCTION c10_demo.wf_assign_component_v1(p_business bigint,p_request text,p_employee bigint,p_component_code text,
 p_enabled boolean,p_override numeric,p_effective_from date,p_reason text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c wf_ctx_t; pay jsonb; pc wf_pay_components; res jsonb;
BEGIN
 IF p_employee IS NULL OR p_component_code IS NULL OR p_enabled IS NULL OR p_effective_from IS NULL OR p_reason IS NULL
  OR length(btrim(p_reason)) NOT BETWEEN 3 AND 500 THEN RAISE EXCEPTION 'wf_invalid_input'; END IF;
 pay:=jsonb_build_object('e',p_employee,'c',p_component_code,'en',p_enabled,'o',p_override,'d',p_effective_from,'r',btrim(p_reason));
 SELECT * INTO b FROM wfi_begin(p_business,p_request,'assign_component',pay);
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 c:=b.o_ctx; PERFORM wfi_need(wfi_is_owner(c),'wf_owner_required');
 IF NOT EXISTS(SELECT 1 FROM wf_employees WHERE id=p_employee AND business_id=p_business) THEN RAISE EXCEPTION 'wf_employee_not_found'; END IF;
 SELECT * INTO pc FROM wf_pay_components WHERE business_id=p_business AND code=p_component_code;
 IF NOT FOUND THEN RAISE EXCEPTION 'wf_component_not_found'; END IF;
 BEGIN
  INSERT INTO wf_employee_components(tenant_id,business_id,employee_id,component_id,enabled,override_amount,effective_from,reason,changed_by)
  VALUES(c.tenant_id,p_business,p_employee,pc.id,p_enabled,p_override,p_effective_from,btrim(p_reason),c.user_id);
 EXCEPTION WHEN check_violation OR numeric_value_out_of_range THEN RAISE EXCEPTION 'wf_invalid_input'; END;
 res:=jsonb_build_object('status','applied');
 PERFORM wfi_log(c.tenant_id,p_business,'pay_component_assignment',p_employee::text,'assigned',NULL,
  jsonb_build_object('component',p_component_code,'enabled',p_enabled,'effective_from',p_effective_from),p_reason,p_request);
 RETURN wfi_finish(p_business,c.tenant_id,p_request,'assign_component',pay,res);
END$$;

CREATE FUNCTION c10_demo.wf_request_advance_v1(p_business bigint,p_request text,p_employee bigint,p_amount numeric,
 p_installment numeric,p_start_period date,p_reason text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c wf_ctx_t; pay jsonb; v_emp bigint; v_id bigint; res jsonb;
BEGIN
 IF p_amount IS NULL OR p_amount<=0 OR p_amount>99999999999.99 OR scale(p_amount)>2 OR p_installment IS NULL OR p_installment<=0
  OR p_installment>p_amount OR scale(p_installment)>2 OR p_start_period IS NULL OR extract(day FROM p_start_period)<>1
  OR p_reason IS NULL OR length(btrim(p_reason)) NOT BETWEEN 3 AND 500 THEN RAISE EXCEPTION 'wf_invalid_input'; END IF;
 pay:=jsonb_build_object('e',p_employee,'a',p_amount,'i',p_installment,'s',p_start_period,'r',btrim(p_reason));
 SELECT * INTO b FROM wfi_begin(p_business,p_request,'request_advance',pay);
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 c:=b.o_ctx; v_emp:=COALESCE(p_employee,c.employee_id);
 IF v_emp IS NULL THEN RAISE EXCEPTION 'wf_employee_required'; END IF;
 PERFORM wfi_need((c.employee_id IS NOT NULL AND c.employee_id=v_emp) OR wfi_is_manager_plus(c),'wf_advance_request_denied');
 IF NOT EXISTS(SELECT 1 FROM wf_employees WHERE id=v_emp AND business_id=p_business AND status='active') THEN RAISE EXCEPTION 'wf_employee_not_active'; END IF;
 INSERT INTO wf_advances(tenant_id,business_id,employee_id,amount,installment_amount,start_period,reason,requested_by,request_key)
 VALUES(c.tenant_id,p_business,v_emp,p_amount,p_installment,p_start_period,btrim(p_reason),c.user_id,p_request) RETURNING id INTO v_id;
 res:=jsonb_build_object('status','requested','advance_id',v_id);
 PERFORM wfi_log(c.tenant_id,p_business,'advance',v_id::text,'requested',NULL,jsonb_build_object('employee_id',v_emp,'start_period',p_start_period),p_reason,p_request);
 RETURN wfi_finish(p_business,c.tenant_id,p_request,'request_advance',pay,res);
END$$;

CREATE FUNCTION c10_demo.wf_decide_advance_v1(p_business bigint,p_request text,p_advance bigint,p_decision text,p_note text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c wf_ctx_t; cfg wf_business_settings; pay jsonb; a wf_advances; res jsonb; v_to text;
BEGIN
 IF p_advance IS NULL OR p_decision NOT IN('approve','reject','cancel') OR p_decision IS NULL OR p_note IS NULL
  OR length(btrim(p_note)) NOT BETWEEN 3 AND 500 THEN RAISE EXCEPTION 'wf_invalid_input'; END IF;
 pay:=jsonb_build_object('a',p_advance,'d',p_decision,'n',btrim(p_note));
 SELECT * INTO b FROM wfi_begin(p_business,p_request,'decide_advance',pay);
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 c:=b.o_ctx; cfg:=wfi_cfg(p_business); PERFORM wfi_need(wfi_is_owner(c),'wf_owner_required');
 SELECT * INTO a FROM wf_advances WHERE id=p_advance AND business_id=p_business FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'wf_advance_not_found'; END IF;
 IF a.status<>'requested' THEN RAISE EXCEPTION 'wf_advance_state_invalid'; END IF;
 IF p_decision='approve' AND ((cfg.require_maker_checker AND a.requested_by=c.user_id)
    OR (c.employee_id IS NOT NULL AND c.employee_id=a.employee_id)) THEN RAISE EXCEPTION 'wf_approver_must_differ'; END IF;
 v_to:=CASE p_decision WHEN 'approve' THEN 'approved' WHEN 'reject' THEN 'rejected' ELSE 'cancelled' END;
 UPDATE wf_advances SET status=v_to,decided_by=c.user_id,decided_at=now(),decision_note=btrim(p_note) WHERE id=a.id;
 res:=jsonb_build_object('status',v_to,'money_movement',false);
 PERFORM wfi_log(c.tenant_id,p_business,'advance',p_advance::text,p_decision,jsonb_build_object('status',a.status),res,p_note,p_request);
 RETURN wfi_finish(p_business,c.tenant_id,p_request,'decide_advance',pay,res);
END$$;

-- ===== Payroll workflow: preview -> DRAFT -> REVIEWED -> APPROVED -> FROZEN (amend/void/return) =====
CREATE FUNCTION c10_demo.wfi_store_lines(p_run bigint,p_tenant bigint,p_business bigint,p_calc jsonb) RETURNS void LANGUAGE plpgsql AS $$
DECLARE l jsonb;
BEGIN
 DELETE FROM c10_demo.wf_payroll_lines WHERE run_id=p_run;
 FOR l IN SELECT * FROM jsonb_array_elements(p_calc->'lines') LOOP
  INSERT INTO c10_demo.wf_payroll_lines(tenant_id,business_id,run_id,employee_id,employee_no,employee_name,site_id,department,pay_basis,
   base_amount,calendar_days,employed_days,present_days,half_days,absent_days,paid_leave_days,unpaid_leave_days,holiday_days,late_days,
   worked_minutes,overtime_minutes_approved,basic_earned,overtime_pay,allowances_total,gross,absence_deduction,other_deductions_total,
   advance_recovery,total_deductions,net,components,advances,warnings)
  VALUES(p_tenant,p_business,p_run,(l->>'employee_id')::bigint,l->>'employee_no',l->>'employee_name',(l->>'site_id')::bigint,l->>'department',l->>'pay_basis',
   (l->>'base_amount')::numeric,(l->>'calendar_days')::int,(l->>'employed_days')::int,(l->>'present_days')::int,(l->>'half_days')::int,
   (l->>'absent_days')::int,(l->>'paid_leave_days')::int,(l->>'unpaid_leave_days')::int,(l->>'holiday_days')::int,(l->>'late_days')::int,
   (l->>'worked_minutes')::int,(l->>'overtime_minutes_approved')::int,(l->>'basic_earned')::numeric,(l->>'overtime_pay')::numeric,
   (l->>'allowances_total')::numeric,(l->>'gross')::numeric,(l->>'absence_deduction')::numeric,(l->>'other_deductions_total')::numeric,
   (l->>'advance_recovery')::numeric,(l->>'total_deductions')::numeric,(l->>'net')::numeric,l->'components',l->'advances',l->'warnings');
 END LOOP;
END$$;
CREATE FUNCTION c10_demo.wfi_refresh_timesheet(p_business bigint,p_start date) RETURNS void LANGUAGE plpgsql AS $$
DECLARE e record; d date; v_end date:=(p_start+interval '1 month')::date-1;
BEGIN
 FOR e IN SELECT id FROM c10_demo.wf_employees WHERE business_id=p_business AND joined_on<=v_end LOOP
  FOR d IN SELECT generate_series(p_start,LEAST(v_end,c10_demo.wfi_today()),interval '1 day')::date LOOP
   PERFORM c10_demo.wfi_recompute_day(p_business,e.id,d); END LOOP; END LOOP;
END$$;

CREATE FUNCTION c10_demo.wf_payroll_preview_v1(p_business bigint,p_period date) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE c wf_ctx_t; r jsonb;
BEGIN
 c:=wfi_ctx(p_business); PERFORM wfi_need(wfi_is_owner(c),'wf_payroll_access_denied');
 IF p_period IS NULL OR extract(day FROM p_period)<>1 THEN RAISE EXCEPTION 'wf_invalid_period'; END IF;
 r:=wfi_calc_run(p_business,p_period,NULL);
 RETURN r||jsonb_build_object('server_authorized',true,'preview_only',true,'paid',false,'business_id',p_business);
END$$;

CREATE FUNCTION c10_demo.wf_create_payroll_draft_v1(p_business bigint,p_request text,p_period date,p_amends_run bigint,p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c wf_ctx_t; cfg wf_business_settings; pay jsonb; v_id bigint; calc jsonb; res jsonb; old wf_payroll_runs; v_ver int; v_end date;
BEGIN
 IF p_period IS NULL OR extract(day FROM p_period)<>1 THEN RAISE EXCEPTION 'wf_invalid_period'; END IF;
 pay:=jsonb_build_object('p',p_period,'a',p_amends_run,'r',p_reason);
 SELECT * INTO b FROM wfi_begin(p_business,p_request,'create_payroll_draft',pay);
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 c:=b.o_ctx; cfg:=wfi_cfg(p_business); PERFORM wfi_need(wfi_is_owner(c),'wf_payroll_access_denied');
 v_end:=(p_period+interval '1 month')::date-1;
 SELECT * INTO old FROM wf_payroll_runs WHERE business_id=p_business AND period_start=p_period AND status='frozen';
 IF FOUND THEN
  IF p_amends_run IS DISTINCT FROM old.id THEN RAISE EXCEPTION 'wf_period_already_frozen_amend_required'; END IF;
  IF p_reason IS NULL OR length(btrim(p_reason)) NOT BETWEEN 10 AND 500 THEN RAISE EXCEPTION 'wf_amendment_reason_required'; END IF;
 ELSIF p_amends_run IS NOT NULL THEN RAISE EXCEPTION 'wf_amend_target_not_frozen'; END IF;
 IF EXISTS(SELECT 1 FROM wf_payroll_runs WHERE business_id=p_business AND period_start=p_period AND status IN('draft','reviewed','approved'))
 THEN RAISE EXCEPTION 'wf_payroll_in_progress'; END IF;
 SELECT COALESCE(max(version),0)+1 INTO v_ver FROM wf_payroll_runs WHERE business_id=p_business AND period_start=p_period;
 INSERT INTO wf_payroll_runs(tenant_id,business_id,period_start,period_end,version,status,amends_run_id,amendment_reason,prepared_by,request_key,config_snapshot)
 VALUES(c.tenant_id,p_business,p_period,v_end,v_ver,'draft',p_amends_run,CASE WHEN p_amends_run IS NOT NULL THEN btrim(p_reason) END,c.user_id,p_request,
  jsonb_build_object('maker_checker',cfg.require_maker_checker,'overtime_requires_approval',cfg.overtime_requires_approval,
   'weekly_off_days',cfg.weekly_off_days,'half_day_ratio',cfg.half_day_ratio,'timezone',cfg.timezone,'settings_version',cfg.version))
 RETURNING id INTO v_id;
 PERFORM wfi_refresh_timesheet(p_business,p_period);
 calc:=wfi_calc_run(p_business,p_period,p_amends_run);
 PERFORM wfi_store_lines(v_id,c.tenant_id,p_business,calc);
 UPDATE wf_payroll_runs SET calc_hash=calc->>'calc_hash',employee_count=(calc->>'employee_count')::int,blocking_count=(calc->>'blocking_count')::int,
  warning_count=(calc->>'warning_count')::int,total_gross=(calc->>'total_gross')::numeric,total_deductions=(calc->>'total_deductions')::numeric,
  total_net=(calc->>'total_net')::numeric WHERE id=v_id;
 res:=jsonb_build_object('status','draft','run_id',v_id,'version',v_ver,'blocking_count',(calc->>'blocking_count')::int,'employee_count',(calc->>'employee_count')::int);
 PERFORM wfi_log(c.tenant_id,p_business,'payroll_run',v_id::text,CASE WHEN p_amends_run IS NULL THEN 'draft_created' ELSE 'amendment_draft_created' END,
  NULL,jsonb_build_object('period',p_period,'version',v_ver,'amends',p_amends_run),p_reason,p_request);
 RETURN wfi_finish(p_business,c.tenant_id,p_request,'create_payroll_draft',pay,res);
END$$;

CREATE FUNCTION c10_demo.wf_recalculate_payroll_draft_v1(p_business bigint,p_request text,p_run bigint) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c wf_ctx_t; pay jsonb; r wf_payroll_runs; calc jsonb; res jsonb;
BEGIN
 IF p_run IS NULL THEN RAISE EXCEPTION 'wf_invalid_input'; END IF;
 pay:=jsonb_build_object('r',p_run);
 SELECT * INTO b FROM wfi_begin(p_business,p_request,'recalculate_payroll',pay);
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 c:=b.o_ctx; PERFORM wfi_need(wfi_is_owner(c),'wf_payroll_access_denied');
 SELECT * INTO r FROM wf_payroll_runs WHERE id=p_run AND business_id=p_business FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'wf_payroll_run_not_found'; END IF;
 IF r.status<>'draft' THEN RAISE EXCEPTION 'wf_payroll_state_invalid'; END IF;
 PERFORM wfi_refresh_timesheet(p_business,r.period_start);
 calc:=wfi_calc_run(p_business,r.period_start,r.amends_run_id);
 PERFORM wfi_store_lines(p_run,c.tenant_id,p_business,calc);
 UPDATE wf_payroll_runs SET calc_hash=calc->>'calc_hash',employee_count=(calc->>'employee_count')::int,blocking_count=(calc->>'blocking_count')::int,
  warning_count=(calc->>'warning_count')::int,total_gross=(calc->>'total_gross')::numeric,total_deductions=(calc->>'total_deductions')::numeric,
  total_net=(calc->>'total_net')::numeric WHERE id=p_run;
 res:=jsonb_build_object('status','draft','run_id',p_run,'blocking_count',(calc->>'blocking_count')::int);
 PERFORM wfi_log(c.tenant_id,p_business,'payroll_run',p_run::text,'recalculated',NULL,res,NULL,p_request);
 RETURN wfi_finish(p_business,c.tenant_id,p_request,'recalculate_payroll',pay,res);
END$$;

CREATE FUNCTION c10_demo.wf_payroll_transition_v1(p_business bigint,p_request text,p_run bigint,p_action text,p_note text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c wf_ctx_t; cfg wf_business_settings; pay jsonb; r wf_payroll_runs; calc jsonb; res jsonb; l record; v_to text; adv jsonb;
 rem numeric; v_net bigint;
BEGIN
 IF p_run IS NULL OR p_action NOT IN('review','approve','freeze','return_to_draft','void') OR p_action IS NULL
  OR (p_note IS NOT NULL AND length(btrim(p_note))>500) THEN RAISE EXCEPTION 'wf_invalid_input'; END IF;
 pay:=jsonb_build_object('r',p_run,'a',p_action,'n',p_note);
 SELECT * INTO b FROM wfi_begin(p_business,p_request,'payroll_transition',pay);
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 c:=b.o_ctx; cfg:=wfi_cfg(p_business); PERFORM wfi_need(wfi_is_owner(c),'wf_payroll_access_denied');
 SELECT * INTO r FROM wf_payroll_runs WHERE id=p_run AND business_id=p_business FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'wf_payroll_run_not_found'; END IF;
 IF p_action IN('return_to_draft','void') AND (p_note IS NULL OR length(btrim(p_note))<5) THEN RAISE EXCEPTION 'wf_note_required'; END IF;
 IF p_action='review' THEN
  IF r.status<>'draft' THEN RAISE EXCEPTION 'wf_payroll_state_invalid'; END IF;
  IF cfg.require_maker_checker AND r.prepared_by=c.user_id THEN RAISE EXCEPTION 'wf_maker_checker_violation'; END IF;
  PERFORM wfi_refresh_timesheet(p_business,r.period_start);
  calc:=wfi_calc_run(p_business,r.period_start,r.amends_run_id);
  IF calc->>'calc_hash'<>r.calc_hash THEN RAISE EXCEPTION 'wf_payroll_inputs_changed'; END IF;
  IF r.blocking_count>0 THEN RAISE EXCEPTION 'wf_payroll_blocking_exceptions'; END IF;
  IF r.employee_count=0 THEN RAISE EXCEPTION 'wf_payroll_empty'; END IF;
  UPDATE wf_payroll_runs SET status='reviewed',reviewed_by=c.user_id,reviewed_at=now(),note=p_note WHERE id=r.id; v_to:='reviewed';
 ELSIF p_action='approve' THEN
  IF r.status<>'reviewed' THEN RAISE EXCEPTION 'wf_payroll_state_invalid'; END IF;
  IF cfg.require_maker_checker AND r.prepared_by=c.user_id THEN RAISE EXCEPTION 'wf_maker_checker_violation'; END IF;
  calc:=wfi_calc_run(p_business,r.period_start,r.amends_run_id);
  IF calc->>'calc_hash'<>r.calc_hash THEN RAISE EXCEPTION 'wf_payroll_inputs_changed'; END IF;
  UPDATE wf_payroll_runs SET status='approved',approved_by=c.user_id,approved_at=now(),note=COALESCE(p_note,note) WHERE id=r.id; v_to:='approved';
 ELSIF p_action='freeze' THEN
  IF r.status<>'approved' THEN RAISE EXCEPTION 'wf_payroll_state_invalid'; END IF;
  calc:=wfi_calc_run(p_business,r.period_start,r.amends_run_id);
  IF calc->>'calc_hash'<>r.calc_hash THEN RAISE EXCEPTION 'wf_payroll_inputs_changed'; END IF;
  IF r.amends_run_id IS NOT NULL THEN
   UPDATE wf_payroll_runs SET status='superseded' WHERE id=r.amends_run_id AND business_id=p_business AND status='frozen';
   IF NOT FOUND THEN RAISE EXCEPTION 'wf_amend_target_not_frozen'; END IF;
  END IF;
  UPDATE wf_payroll_runs SET status='frozen',frozen_by=c.user_id,frozen_at=now() WHERE id=r.id;
  FOR l IN SELECT * FROM wf_payroll_lines WHERE run_id=r.id ORDER BY employee_id LOOP
   INSERT INTO wf_payslips(tenant_id,business_id,run_id,employee_id,period_start,period_end,net,issued_by,snapshot)
   VALUES(c.tenant_id,p_business,r.id,l.employee_id,r.period_start,r.period_end,l.net,c.user_id,jsonb_build_object(
    'period_start',r.period_start,'period_end',r.period_end,'run_version',r.version,'amendment',r.amends_run_id IS NOT NULL,
    'employee_no',l.employee_no,'employee_name',l.employee_name,'pay_basis',l.pay_basis,
    'attendance',jsonb_build_object('employed_days',l.employed_days,'present_days',l.present_days,'half_days',l.half_days,
      'absent_days',l.absent_days,'paid_leave_days',l.paid_leave_days,'unpaid_leave_days',l.unpaid_leave_days,
      'overtime_minutes_approved',l.overtime_minutes_approved),
    'basic_earned',l.basic_earned,'overtime_pay',l.overtime_pay,'allowances',(SELECT COALESCE(jsonb_agg(x),'[]') FROM jsonb_array_elements(l.components) x WHERE x->>'kind'='allowance'),
    'gross',l.gross,'absence_deduction',l.absence_deduction,'other_deductions',(SELECT COALESCE(jsonb_agg(x),'[]') FROM jsonb_array_elements(l.components) x WHERE x->>'kind'='deduction'),
    'advance_recovery',l.advance_recovery,'total_deductions',l.total_deductions,'net',l.net,'payment_status','not_tracked_in_this_module'));
   FOR adv IN SELECT * FROM jsonb_array_elements(l.advances) LOOP
    INSERT INTO wf_advance_recoveries(tenant_id,business_id,advance_id,run_id,amount)
    VALUES(c.tenant_id,p_business,(adv->>'advance_id')::bigint,r.id,(adv->>'amount')::numeric);
    rem:=wfi_advance_remaining((adv->>'advance_id')::bigint,NULL);
    IF rem<=0 THEN UPDATE wf_advances SET status='closed' WHERE id=(adv->>'advance_id')::bigint; END IF;
   END LOOP;
  END LOOP;
  v_to:='frozen';
 ELSIF p_action='return_to_draft' THEN
  IF r.status NOT IN('reviewed','approved') THEN RAISE EXCEPTION 'wf_payroll_state_invalid'; END IF;
  UPDATE wf_payroll_runs SET status='draft',reviewed_by=NULL,reviewed_at=NULL,approved_by=NULL,approved_at=NULL,note=p_note WHERE id=r.id; v_to:='draft';
 ELSE
  IF r.status NOT IN('draft','reviewed','approved') THEN RAISE EXCEPTION 'wf_payroll_state_invalid'; END IF;
  UPDATE wf_payroll_runs SET status='voided',note=p_note WHERE id=r.id; v_to:='voided';
 END IF;
 res:=jsonb_build_object('status',v_to,'run_id',r.id,'paid',false,'money_movement',false);
 PERFORM wfi_log(c.tenant_id,p_business,'payroll_run',r.id::text,p_action,jsonb_build_object('status',r.status),res,p_note,p_request);
 RETURN wfi_finish(p_business,c.tenant_id,p_request,'payroll_transition',pay,res);
END$$;

-- Retention: expired punch facts only (never inside a locked/frozen period), tenant owner only, audited.
CREATE FUNCTION c10_demo.wf_purge_expired_punches_v1(p_business bigint,p_request text,p_dry_run boolean) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c wf_ctx_t; cfg wf_business_settings; pay jsonb; v_cut timestamptz; v_n int; res jsonb;
BEGIN
 IF p_dry_run IS NULL THEN RAISE EXCEPTION 'wf_invalid_input'; END IF;
 pay:=jsonb_build_object('dry',p_dry_run);
 SELECT * INTO b FROM wfi_begin(p_business,p_request,'purge_punches',pay);
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 c:=b.o_ctx; cfg:=wfi_cfg(p_business); PERFORM wfi_need(c.is_tenant_owner,'wf_tenant_owner_required');
 v_cut:=now()-make_interval(months=>cfg.punch_retention_months);
 IF p_dry_run THEN
  SELECT count(*) INTO v_n FROM wf_punches p WHERE p.business_id=p_business AND p.punched_at<v_cut;
 ELSE
  PERFORM set_config('c10.wf_purge','1',true);
  WITH d AS(DELETE FROM wf_punches p WHERE p.business_id=p_business AND p.punched_at<v_cut
   AND NOT wfi_period_locked(p_business,(p.punched_at AT TIME ZONE 'Asia/Dhaka')::date)
   AND NOT EXISTS(SELECT 1 FROM wf_payroll_runs r WHERE r.business_id=p_business AND r.status IN('frozen','superseded')
     AND (p.punched_at AT TIME ZONE 'Asia/Dhaka')::date BETWEEN r.period_start-1 AND r.period_end+1) RETURNING 1)
  SELECT count(*) INTO v_n FROM d;
  PERFORM set_config('c10.wf_purge','',true);
 END IF;
 res:=jsonb_build_object('dry_run',p_dry_run,'rows',v_n,'cutoff',v_cut);
 PERFORM wfi_log(c.tenant_id,p_business,'retention','punches',CASE WHEN p_dry_run THEN 'purge_previewed' ELSE 'purged' END,NULL,res,NULL,p_request);
 RETURN wfi_finish(p_business,c.tenant_id,p_request,'purge_punches',pay,res);
END$$;
