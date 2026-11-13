-- C10-A051 Workforce (2/3): punches (source facts), derived attendance days (timesheet),
-- corrections, overtime approval, leave. DISPOSABLE c10_demo ONLY. Apply AFTER core v1.
-- All times computed in Asia/Dhaka; overnight shifts supported. Source punches are never edited;
-- approved corrections/leave/overtime are separate records the day calculation consumes.
CREATE TABLE c10_demo.wf_punches(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL, business_id bigint NOT NULL, site_id bigint NOT NULL, employee_id bigint NOT NULL,
 punched_at timestamptz NOT NULL,
 direction text NOT NULL CHECK(direction IN('in','out')),
 source text NOT NULL CHECK(source IN('device','manual','import')),
 source_ref text CHECK(source_ref IS NULL OR length(source_ref) BETWEEN 1 AND 64),
 status text NOT NULL DEFAULT 'accepted' CHECK(status IN('accepted','duplicate')),
 duplicate_of bigint,
 batch_key text NOT NULL, created_by uuid NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(employee_id,tenant_id,business_id) REFERENCES c10_demo.wf_employees(id,tenant_id,business_id),
 FOREIGN KEY(site_id,tenant_id,business_id) REFERENCES c10_demo.sites(id,tenant_id,business_id)
);
CREATE UNIQUE INDEX wf_punches_ref_uq ON c10_demo.wf_punches(business_id,source_ref) WHERE source_ref IS NOT NULL;
CREATE INDEX wf_punches_emp_ix ON c10_demo.wf_punches(employee_id,punched_at);
CREATE FUNCTION c10_demo.wfi_punch_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 -- Source facts are immutable except authorised retention purge (flag set by the purge RPC only).
 IF TG_OP='UPDATE' OR (TG_OP='DELETE' AND COALESCE(current_setting('c10.wf_purge',true),'')<>'1') THEN
  RAISE EXCEPTION 'wf_append_only_record'; END IF;
 RETURN COALESCE(NEW,OLD);
END$$;
CREATE TRIGGER wf_punches_guard BEFORE UPDATE OR DELETE ON c10_demo.wf_punches FOR EACH ROW EXECUTE FUNCTION c10_demo.wfi_punch_guard();

CREATE TABLE c10_demo.wf_leave_types(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL, business_id bigint NOT NULL,
 code text NOT NULL CHECK(code ~ '^[A-Za-z0-9][A-Za-z0-9_-]{0,23}$'),
 name text NOT NULL CHECK(length(btrim(name)) BETWEEN 2 AND 80),
 paid boolean NOT NULL,
 annual_quota_days numeric(5,1) CHECK(annual_quota_days IS NULL OR annual_quota_days BETWEEN 0 AND 366),
 requires_approval boolean NOT NULL DEFAULT true,
 max_days_per_request int NOT NULL DEFAULT 30 CHECK(max_days_per_request BETWEEN 1 AND 60),
 allow_backdated boolean NOT NULL DEFAULT true,
 active boolean NOT NULL DEFAULT true,
 version bigint NOT NULL DEFAULT 1,
 UNIQUE(business_id,code), UNIQUE(id,tenant_id,business_id),
 FOREIGN KEY(business_id,tenant_id) REFERENCES c10_demo.businesses(id,tenant_id)
);
CREATE TABLE c10_demo.wf_leave_requests(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL, business_id bigint NOT NULL, employee_id bigint NOT NULL, leave_type_id bigint NOT NULL,
 from_date date NOT NULL, to_date date NOT NULL CHECK(to_date>=from_date),
 days numeric(5,1) NOT NULL CHECK(days>0),
 reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 3 AND 500),
 status text NOT NULL DEFAULT 'pending' CHECK(status IN('pending','approved','rejected','cancelled','revoked')),
 requested_by uuid NOT NULL, decided_by uuid, decided_at timestamptz, decision_note text,
 request_key text NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(business_id,request_key),
 FOREIGN KEY(employee_id,tenant_id,business_id) REFERENCES c10_demo.wf_employees(id,tenant_id,business_id),
 FOREIGN KEY(leave_type_id,tenant_id,business_id) REFERENCES c10_demo.wf_leave_types(id,tenant_id,business_id)
);
CREATE INDEX wf_leave_emp_ix ON c10_demo.wf_leave_requests(employee_id,from_date,to_date);
CREATE TABLE c10_demo.wf_attendance_corrections(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL, business_id bigint NOT NULL, employee_id bigint NOT NULL, work_date date NOT NULL,
 new_in timestamptz, new_out timestamptz, new_status text CHECK(new_status IN('present','absent')),
 reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 5 AND 500),
 requested_by uuid NOT NULL,
 status text NOT NULL DEFAULT 'pending' CHECK(status IN('pending','approved','rejected')),
 decided_by uuid, decided_at timestamptz, decision_note text,
 created_at timestamptz NOT NULL DEFAULT now(),
 CHECK(new_in IS NOT NULL OR new_out IS NOT NULL OR new_status IS NOT NULL),
 CHECK(new_in IS NULL OR new_out IS NULL OR new_out>new_in),
 FOREIGN KEY(employee_id,tenant_id,business_id) REFERENCES c10_demo.wf_employees(id,tenant_id,business_id)
);
CREATE INDEX wf_corr_emp_ix ON c10_demo.wf_attendance_corrections(employee_id,work_date);
CREATE TABLE c10_demo.wf_overtime_approvals(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL, business_id bigint NOT NULL, employee_id bigint NOT NULL, work_date date NOT NULL,
 minutes int NOT NULL CHECK(minutes BETWEEN 0 AND 720),
 note text, decided_by uuid NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(employee_id,tenant_id,business_id) REFERENCES c10_demo.wf_employees(id,tenant_id,business_id)
);
CREATE INDEX wf_ot_emp_ix ON c10_demo.wf_overtime_approvals(employee_id,work_date,id DESC);
CREATE TRIGGER wf_ot_no_mutation BEFORE UPDATE OR DELETE ON c10_demo.wf_overtime_approvals FOR EACH ROW EXECUTE FUNCTION c10_demo.wfi_immutable();
-- Approved timesheet (derived). Rebuilt on every relevant event, frozen in effect when payroll locks the period.
CREATE TABLE c10_demo.wf_attendance_days(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL, business_id bigint NOT NULL, employee_id bigint NOT NULL, work_date date NOT NULL,
 status text NOT NULL, site_id bigint, shift_id bigint, scheduled_minutes int NOT NULL DEFAULT 0,
 first_in timestamptz, last_out timestamptz, worked_minutes int NOT NULL DEFAULT 0,
 late_minutes int NOT NULL DEFAULT 0, early_leave_minutes int NOT NULL DEFAULT 0,
 overtime_minutes int NOT NULL DEFAULT 0, overtime_kind text, overtime_decided boolean NOT NULL DEFAULT true,
 overtime_approved_minutes int NOT NULL DEFAULT 0, leave_request_id bigint, correction_id bigint,
 flags jsonb NOT NULL DEFAULT '[]', computed_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(employee_id,work_date),
 FOREIGN KEY(employee_id,tenant_id,business_id) REFERENCES c10_demo.wf_employees(id,tenant_id,business_id)
);
CREATE INDEX wf_days_biz_ix ON c10_demo.wf_attendance_days(business_id,work_date);

-- Shift definition effective for an employee on a date.
CREATE FUNCTION c10_demo.wfi_shift_on(p_employee bigint,p_date date) RETURNS c10_demo.wf_shifts
LANGUAGE sql STABLE AS $$
 SELECT s.* FROM c10_demo.wf_shift_assignments a JOIN c10_demo.wf_shifts s ON s.id=a.shift_id
 WHERE a.employee_id=p_employee AND a.effective_from<=p_date ORDER BY a.effective_from DESC,a.id DESC LIMIT 1 $$;
CREATE FUNCTION c10_demo.wfi_is_off_day(p_business bigint,p_employee bigint,p_date date) RETURNS boolean
LANGUAGE plpgsql AS $$
DECLARE sh c10_demo.wf_shifts; cfg c10_demo.wf_business_settings; off smallint[];
BEGIN
 sh:=c10_demo.wfi_shift_on(p_employee,p_date); cfg:=c10_demo.wfi_cfg(p_business);
 off:=COALESCE(sh.weekly_off_days,cfg.weekly_off_days);
 RETURN extract(isodow FROM p_date)::smallint=ANY(off);
END$$;
CREATE FUNCTION c10_demo.wfi_holiday_on(p_business bigint,p_employee bigint,p_date date) RETURNS c10_demo.wf_holidays
LANGUAGE sql STABLE AS $$
 SELECT h.* FROM c10_demo.wf_holidays h WHERE h.business_id=p_business AND h.holiday_date=p_date AND h.active
  AND (h.site_id IS NULL OR h.site_id=c10_demo.wfi_site_of(p_employee,p_date))
 ORDER BY (h.site_id IS NULL) LIMIT 1 $$;

-- Pure deterministic day calculation. Does not write.
CREATE FUNCTION c10_demo.wfi_calc_day(p_business bigint,p_employee bigint,p_date date) RETURNS jsonb
LANGUAGE plpgsql AS $$
DECLARE e c10_demo.wf_employees; cfg c10_demo.wf_business_settings; sh c10_demo.wf_shifts; hol c10_demo.wf_holidays;
 corr c10_demo.wf_attendance_corrections; lv record; v_site bigint; today date:=c10_demo.wfi_today();
 st timestamptz; en timestamptz; wf timestamptz; wt timestamptz; fi timestamptz; lo timestamptz;
 is_off boolean; worked boolean; one_side boolean;
 dstat text; sched int:=0; wk int:=0; late int:=0; early int:=0; ot int:=0; otk text; span int;
 otapp int:=0; otdec boolean:=true; flags jsonb:='[]'; aprow record;
BEGIN
 SELECT * INTO e FROM c10_demo.wf_employees WHERE id=p_employee AND business_id=p_business;
 IF NOT FOUND OR p_date<e.joined_on OR COALESCE(c10_demo.wfi_status_on(p_employee,p_date),'terminated')<>'active' THEN
  RETURN jsonb_build_object('status','not_employed','scheduled_minutes',0,'worked_minutes',0,'late_minutes',0,
   'early_leave_minutes',0,'overtime_minutes',0,'overtime_approved_minutes',0,'overtime_decided',true,'flags','[]'::jsonb);
 END IF;
 cfg:=c10_demo.wfi_cfg(p_business); sh:=c10_demo.wfi_shift_on(p_employee,p_date); v_site:=c10_demo.wfi_site_of(p_employee,p_date);
 is_off:=c10_demo.wfi_is_off_day(p_business,p_employee,p_date);
 hol:=c10_demo.wfi_holiday_on(p_business,p_employee,p_date);
 IF p_date>today THEN
  RETURN jsonb_build_object('status','future','site_id',v_site,'shift_id',sh.id,'scheduled_minutes',0,'worked_minutes',0,
   'late_minutes',0,'early_leave_minutes',0,'overtime_minutes',0,'overtime_approved_minutes',0,'overtime_decided',true,'flags','[]'::jsonb);
 END IF;
 IF sh.id IS NOT NULL THEN
  st:=c10_demo.wfi_ts(p_date,sh.start_time);
  en:=c10_demo.wfi_ts(p_date+CASE WHEN sh.end_time<=sh.start_time THEN 1 ELSE 0 END,sh.end_time);
  wf:=st-interval '180 minutes'; wt:=en+interval '180 minutes';
  sched:=(extract(epoch FROM (en-st))/60)::int-sh.break_minutes;
 ELSE wf:=c10_demo.wfi_ts(p_date,'00:00'); wt:=c10_demo.wfi_ts(p_date+1,'00:00'); END IF;
 SELECT min(punched_at) FILTER(WHERE direction='in'),max(punched_at) FILTER(WHERE direction='out') INTO fi,lo
  FROM c10_demo.wf_punches WHERE employee_id=p_employee AND status='accepted' AND punched_at>=wf AND punched_at<wt;
 SELECT * INTO corr FROM c10_demo.wf_attendance_corrections WHERE employee_id=p_employee AND work_date=p_date AND status='approved'
  ORDER BY decided_at DESC,id DESC LIMIT 1;
 IF FOUND THEN fi:=COALESCE(corr.new_in,fi); lo:=COALESCE(corr.new_out,lo); flags:=flags||'"corrected"'::jsonb; END IF;
 IF fi IS NOT NULL AND lo IS NOT NULL AND lo<=fi THEN lo:=NULL; flags:=flags||'"out_before_in"'::jsonb; END IF;
 worked:=fi IS NOT NULL AND lo IS NOT NULL; one_side:=(fi IS NULL)<>(lo IS NULL);
 SELECT lr.id,lt.paid INTO lv FROM c10_demo.wf_leave_requests lr JOIN c10_demo.wf_leave_types lt ON lt.id=lr.leave_type_id
  WHERE lr.employee_id=p_employee AND lr.status='approved' AND p_date BETWEEN lr.from_date AND lr.to_date LIMIT 1;
 IF worked THEN
  span:=floor(extract(epoch FROM (lo-fi))/60)::int;
  wk:=GREATEST(0,span-CASE WHEN sh.id IS NOT NULL AND span>sh.break_minutes THEN sh.break_minutes ELSE 0 END);
 END IF;
 IF wfi_corr_absent(corr) THEN dstat:='absent'; wk:=0; sched:=sched;
 ELSIF hol.id IS NOT NULL OR is_off THEN
  IF worked THEN dstat:='present';
   IF cfg.off_day_work_as_overtime THEN ot:=wk; otk:='off_day'; END IF;
  ELSIF one_side THEN dstat:='incomplete';
  ELSE dstat:=CASE WHEN hol.id IS NOT NULL THEN 'holiday' ELSE 'weekly_off' END; END IF;
  IF dstat<>'present' THEN sched:=0; END IF;
 ELSIF lv.id IS NOT NULL THEN
  dstat:=CASE WHEN lv.paid THEN 'paid_leave' ELSE 'unpaid_leave' END;
  IF worked THEN flags:=flags||'"punches_during_leave"'::jsonb; END IF; wk:=0;
 ELSIF corr.id IS NOT NULL AND corr.new_status='present' AND NOT worked THEN
  dstat:='present'; wk:=GREATEST(sched,0); flags:=flags||'"manual_present"'::jsonb;
 ELSIF worked THEN
  dstat:='present';
  IF sh.id IS NOT NULL THEN
   IF fi>st+make_interval(mins=>sh.grace_late_minutes) THEN late:=floor(extract(epoch FROM (fi-st))/60)::int; END IF;
   IF lo<en-make_interval(mins=>sh.grace_early_minutes) THEN early:=floor(extract(epoch FROM (en-lo))/60)::int; END IF;
   IF lo>en THEN ot:=floor(extract(epoch FROM (lo-en))/60)::int; END IF;
   IF ot<sh.min_overtime_minutes OR ot<=0 THEN ot:=0; END IF;
   ot:=LEAST(ot,cfg.max_overtime_minutes_per_day,wk); otk:=CASE WHEN ot>0 THEN 'weekday' END;
   IF sched>0 AND wk<sched*cfg.half_day_ratio THEN dstat:='half_day'; END IF;
  END IF;
 ELSIF one_side THEN dstat:='incomplete';
 ELSIF p_date=today THEN dstat:='future';
 ELSE dstat:='absent'; END IF;
 IF dstat IN('weekly_off','holiday','absent','paid_leave','unpaid_leave','incomplete') THEN
  IF dstat<>'incomplete' THEN wk:=0; END IF; END IF;
 IF ot>0 THEN
  IF cfg.overtime_requires_approval THEN
   SELECT minutes INTO aprow FROM c10_demo.wf_overtime_approvals WHERE employee_id=p_employee AND work_date=p_date ORDER BY id DESC LIMIT 1;
   IF FOUND THEN otapp:=LEAST(aprow.minutes,ot); ELSE otdec:=false; END IF;
  ELSE otapp:=ot; END IF;
 END IF;
 RETURN jsonb_build_object('status',dstat,'site_id',v_site,'shift_id',sh.id,'scheduled_minutes',sched,
  'first_in',fi,'last_out',lo,'worked_minutes',wk,'late_minutes',late,'early_leave_minutes',early,
  'overtime_minutes',ot,'overtime_kind',otk,'overtime_decided',otdec,'overtime_approved_minutes',otapp,
  'leave_request_id',lv.id,'holiday_paid',hol.paid,'correction_id',corr.id,'flags',flags);
END$$;
CREATE FUNCTION c10_demo.wfi_corr_absent(c c10_demo.wf_attendance_corrections) RETURNS boolean
LANGUAGE sql IMMUTABLE AS $$ SELECT c.id IS NOT NULL AND c.new_status='absent' $$;

CREATE FUNCTION c10_demo.wfi_recompute_day(p_business bigint,p_employee bigint,p_date date) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE d jsonb; t bigint;
BEGIN
 IF c10_demo.wfi_period_locked(p_business,p_date) THEN RETURN; END IF;
 d:=c10_demo.wfi_calc_day(p_business,p_employee,p_date);
 SELECT tenant_id INTO t FROM c10_demo.wf_employees WHERE id=p_employee;
 INSERT INTO c10_demo.wf_attendance_days(tenant_id,business_id,employee_id,work_date,status,site_id,shift_id,scheduled_minutes,
  first_in,last_out,worked_minutes,late_minutes,early_leave_minutes,overtime_minutes,overtime_kind,overtime_decided,
  overtime_approved_minutes,leave_request_id,correction_id,flags,computed_at)
 VALUES(t,p_business,p_employee,p_date,d->>'status',(d->>'site_id')::bigint,(d->>'shift_id')::bigint,(d->>'scheduled_minutes')::int,
  (d->>'first_in')::timestamptz,(d->>'last_out')::timestamptz,(d->>'worked_minutes')::int,(d->>'late_minutes')::int,
  (d->>'early_leave_minutes')::int,(d->>'overtime_minutes')::int,d->>'overtime_kind',(d->>'overtime_decided')::boolean,
  (d->>'overtime_approved_minutes')::int,(d->>'leave_request_id')::bigint,(d->>'correction_id')::bigint,d->'flags',now())
 ON CONFLICT(employee_id,work_date) DO UPDATE SET status=excluded.status,site_id=excluded.site_id,shift_id=excluded.shift_id,
  scheduled_minutes=excluded.scheduled_minutes,first_in=excluded.first_in,last_out=excluded.last_out,worked_minutes=excluded.worked_minutes,
  late_minutes=excluded.late_minutes,early_leave_minutes=excluded.early_leave_minutes,overtime_minutes=excluded.overtime_minutes,
  overtime_kind=excluded.overtime_kind,overtime_decided=excluded.overtime_decided,overtime_approved_minutes=excluded.overtime_approved_minutes,
  leave_request_id=excluded.leave_request_id,correction_id=excluded.correction_id,flags=excluded.flags,computed_at=now();
END$$;

-- Map an instant to the work date it belongs to (supports overnight shifts).
CREATE FUNCTION c10_demo.wfi_work_date(p_business bigint,p_employee bigint,p_ts timestamptz) RETURNS date
LANGUAGE plpgsql STABLE AS $$
DECLARE d0 date:=(p_ts AT TIME ZONE 'Asia/Dhaka')::date; d date; sh c10_demo.wf_shifts; st timestamptz; en timestamptz;
BEGIN
 FOREACH d IN ARRAY ARRAY[d0,d0-1] LOOP
  sh:=c10_demo.wfi_shift_on(p_employee,d);
  IF sh.id IS NULL THEN CONTINUE; END IF;
  st:=c10_demo.wfi_ts(d,sh.start_time);
  en:=c10_demo.wfi_ts(d+CASE WHEN sh.end_time<=sh.start_time THEN 1 ELSE 0 END,sh.end_time);
  IF p_ts>=st-interval '180 minutes' AND p_ts<en+interval '180 minutes' THEN RETURN d; END IF;
 END LOOP;
 RETURN d0;
END$$;

-- Bounded import-ready punch DTO: [{employee_no, at, direction, ref}] up to 500 rows.
CREATE FUNCTION c10_demo.wf_import_punches_v1(p_business bigint,p_request text,p_site bigint,p_source text,p_punches jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c wf_ctx_t; cfg wf_business_settings; pay jsonb; el jsonb; i int:=0; emp wf_employees; ts timestamptz;
 dir text; ref text; v_id bigint; v_dup bigint; wd date; outcome text; acc int:=0; dup int:=0; rej int:=0;
 results jsonb:='[]'; touched jsonb:='{}'; k text; res jsonb;
BEGIN
 IF p_site IS NULL OR p_source NOT IN('device','manual','import') OR p_source IS NULL OR p_punches IS NULL
  OR jsonb_typeof(p_punches)<>'array' OR jsonb_array_length(p_punches) NOT BETWEEN 1 AND 500 THEN RAISE EXCEPTION 'wf_invalid_input'; END IF;
 pay:=jsonb_build_object('s',p_site,'src',p_source,'p',p_punches);
 SELECT * INTO b FROM wfi_begin(p_business,p_request,'import_punches',pay);
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 c:=b.o_ctx; cfg:=wfi_cfg(p_business);
 IF NOT EXISTS(SELECT 1 FROM sites WHERE id=p_site AND business_id=p_business) THEN RAISE EXCEPTION 'wf_site_not_in_business'; END IF;
 PERFORM wfi_need(wfi_is_manager_plus(c) OR p_site=ANY(c.supervised_sites),'wf_punch_import_denied');
 FOR el IN SELECT * FROM jsonb_array_elements(p_punches) LOOP
  i:=i+1; outcome:=NULL; v_id:=NULL;
  BEGIN
   dir:=el->>'direction'; ref:=NULLIF(el->>'ref','');
   IF dir IS NULL OR dir NOT IN('in','out') OR el->>'at' IS NULL OR el->>'at' !~ '(Z|[+-][0-9]{2}:?[0-9]{2})$' THEN outcome:='invalid_row';
   ELSE
    ts:=(el->>'at')::timestamptz;
    SELECT * INTO emp FROM wf_employees WHERE business_id=p_business AND employee_no=el->>'employee_no';
    IF NOT FOUND THEN outcome:='employee_not_found';
    ELSIF NOT wfi_can_see(c,emp.id) OR (c.employee_id=emp.id AND NOT wfi_is_manager_plus(c)) THEN outcome:='not_in_scope';
    ELSIF ts>now()+interval '5 minutes' OR ts<now()-interval '400 days' THEN outcome:='time_out_of_range';
    ELSIF COALESCE(wfi_status_on(emp.id,(ts AT TIME ZONE 'Asia/Dhaka')::date),'terminated')<>'active' THEN outcome:='not_employed';
    ELSE
     wd:=wfi_work_date(p_business,emp.id,ts);
     IF wfi_period_locked(p_business,wd) OR wfi_period_locked(p_business,(ts AT TIME ZONE 'Asia/Dhaka')::date) THEN outcome:='period_locked';
     ELSE
      SELECT id INTO v_dup FROM wf_punches WHERE employee_id=emp.id AND direction=dir AND status='accepted'
        AND abs(extract(epoch FROM (punched_at-ts)))<=cfg.duplicate_window_seconds ORDER BY punched_at LIMIT 1;
      INSERT INTO wf_punches(tenant_id,business_id,site_id,employee_id,punched_at,direction,source,source_ref,status,duplicate_of,batch_key,created_by)
      VALUES(c.tenant_id,p_business,p_site,emp.id,ts,dir,p_source,ref,CASE WHEN v_dup IS NULL THEN 'accepted' ELSE 'duplicate' END,v_dup,p_request,c.user_id)
      ON CONFLICT(business_id,source_ref) WHERE source_ref IS NOT NULL DO NOTHING RETURNING id INTO v_id;
      IF v_id IS NULL THEN outcome:='duplicate_ref';
      ELSIF v_dup IS NOT NULL THEN outcome:='duplicate_ignored';
      ELSE outcome:='accepted'; touched:=touched||jsonb_build_object(emp.id::text||'|'||wd::text,jsonb_build_array(emp.id,wd)); END IF;
     END IF;
    END IF;
   END IF;
  EXCEPTION WHEN OTHERS THEN outcome:='invalid_row'; END;
  IF outcome='accepted' THEN acc:=acc+1; ELSIF outcome IN('duplicate_ignored','duplicate_ref') THEN dup:=dup+1; ELSE rej:=rej+1; END IF;
  results:=results||jsonb_build_array(jsonb_build_object('i',i,'outcome',outcome));
 END LOOP;
 FOR k IN SELECT jsonb_object_keys(touched) LOOP
  PERFORM wfi_recompute_day(p_business,(touched->k->>0)::bigint,(touched->k->>1)::date); END LOOP;
 res:=jsonb_build_object('accepted',acc,'duplicates',dup,'rejected',rej,'results',results);
 PERFORM wfi_log(c.tenant_id,p_business,'punch_batch',p_request,'imported',NULL,
  jsonb_build_object('site_id',p_site,'source',p_source,'accepted',acc,'duplicates',dup,'rejected',rej),NULL,p_request);
 RETURN wfi_finish(p_business,c.tenant_id,p_request,'import_punches',pay,res);
END$$;

CREATE FUNCTION c10_demo.wf_request_correction_v1(p_business bigint,p_request text,p_employee bigint,p_work_date date,
 p_new_in timestamptz,p_new_out timestamptz,p_new_status text,p_reason text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c wf_ctx_t; pay jsonb; e wf_employees; v_id bigint; res jsonb;
BEGIN
 IF p_employee IS NULL OR p_work_date IS NULL OR (p_new_in IS NULL AND p_new_out IS NULL AND p_new_status IS NULL)
  OR (p_new_status IS NOT NULL AND p_new_status NOT IN('present','absent'))
  OR p_reason IS NULL OR length(btrim(p_reason)) NOT BETWEEN 5 AND 500 THEN RAISE EXCEPTION 'wf_invalid_input'; END IF;
 pay:=jsonb_build_object('e',p_employee,'d',p_work_date,'i',p_new_in,'o',p_new_out,'s',p_new_status,'r',btrim(p_reason));
 SELECT * INTO b FROM wfi_begin(p_business,p_request,'request_correction',pay);
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 c:=b.o_ctx;
 SELECT * INTO e FROM wf_employees WHERE id=p_employee AND business_id=p_business;
 IF NOT FOUND THEN RAISE EXCEPTION 'wf_employee_not_found'; END IF;
 -- Supervisor/manager/owner only; nobody corrects their own attendance; plain staff cannot request.
 PERFORM wfi_need(wfi_is_manager_plus(c) OR wfi_site_of(p_employee,p_work_date)=ANY(c.supervised_sites),'wf_correction_denied');
 IF c.employee_id IS NOT NULL AND c.employee_id=p_employee THEN RAISE EXCEPTION 'wf_self_correction_denied'; END IF;
 IF p_work_date>wfi_today() OR p_work_date<e.joined_on THEN RAISE EXCEPTION 'wf_invalid_effective_date'; END IF;
 IF wfi_period_locked(p_business,p_work_date) THEN RAISE EXCEPTION 'wf_period_locked'; END IF;
 IF (p_new_in IS NOT NULL AND abs(extract(epoch FROM (p_new_in-wfi_ts(p_work_date,'12:00')))) > 129600)
  OR (p_new_out IS NOT NULL AND abs(extract(epoch FROM (p_new_out-wfi_ts(p_work_date,'12:00')))) > 129600)
  OR (p_new_in IS NOT NULL AND p_new_out IS NOT NULL AND p_new_out<=p_new_in) THEN RAISE EXCEPTION 'wf_invalid_correction_times'; END IF;
 INSERT INTO wf_attendance_corrections(tenant_id,business_id,employee_id,work_date,new_in,new_out,new_status,reason,requested_by)
 VALUES(c.tenant_id,p_business,p_employee,p_work_date,p_new_in,p_new_out,p_new_status,btrim(p_reason),c.user_id) RETURNING id INTO v_id;
 res:=jsonb_build_object('status','pending','correction_id',v_id);
 PERFORM wfi_log(c.tenant_id,p_business,'attendance_correction',v_id::text,'requested',NULL,pay,p_reason,p_request);
 RETURN wfi_finish(p_business,c.tenant_id,p_request,'request_correction',pay,res);
END$$;

CREATE FUNCTION c10_demo.wf_decide_correction_v1(p_business bigint,p_request text,p_correction bigint,p_decision text,p_note text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c wf_ctx_t; cfg wf_business_settings; pay jsonb; r wf_attendance_corrections; res jsonb;
BEGIN
 IF p_correction IS NULL OR p_decision NOT IN('approve','reject') OR p_decision IS NULL OR p_note IS NULL
  OR length(btrim(p_note)) NOT BETWEEN 3 AND 500 THEN RAISE EXCEPTION 'wf_invalid_input'; END IF;
 pay:=jsonb_build_object('c',p_correction,'d',p_decision,'n',btrim(p_note));
 SELECT * INTO b FROM wfi_begin(p_business,p_request,'decide_correction',pay);
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 c:=b.o_ctx; cfg:=wfi_cfg(p_business);
 PERFORM wfi_need(wfi_is_owner(c) OR (c.is_manager AND cfg.manager_can_approve_corrections),'wf_correction_approval_denied');
 SELECT * INTO r FROM wf_attendance_corrections WHERE id=p_correction AND business_id=p_business FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'wf_correction_not_found'; END IF;
 IF r.status<>'pending' THEN RAISE EXCEPTION 'wf_correction_not_pending'; END IF;
 IF r.requested_by=c.user_id THEN RAISE EXCEPTION 'wf_approver_must_differ'; END IF;
 IF c.employee_id IS NOT NULL AND c.employee_id=r.employee_id THEN RAISE EXCEPTION 'wf_self_correction_denied'; END IF;
 IF p_decision='approve' AND wfi_period_locked(p_business,r.work_date) THEN RAISE EXCEPTION 'wf_period_locked'; END IF;
 UPDATE wf_attendance_corrections SET status=CASE p_decision WHEN 'approve' THEN 'approved' ELSE 'rejected' END,
  decided_by=c.user_id,decided_at=now(),decision_note=btrim(p_note) WHERE id=p_correction;
 IF p_decision='approve' THEN PERFORM wfi_recompute_day(p_business,r.employee_id,r.work_date); END IF;
 res:=jsonb_build_object('status',CASE p_decision WHEN 'approve' THEN 'approved' ELSE 'rejected' END);
 PERFORM wfi_log(c.tenant_id,p_business,'attendance_correction',p_correction::text,p_decision,to_jsonb(r),res,p_note,p_request);
 RETURN wfi_finish(p_business,c.tenant_id,p_request,'decide_correction',pay,res);
END$$;

CREATE FUNCTION c10_demo.wf_decide_overtime_v1(p_business bigint,p_request text,p_employee bigint,p_work_date date,
 p_minutes int,p_note text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c wf_ctx_t; pay jsonb; d jsonb; res jsonb;
BEGIN
 IF p_employee IS NULL OR p_work_date IS NULL OR p_minutes IS NULL OR p_minutes NOT BETWEEN 0 AND 720 OR p_note IS NULL
  OR length(btrim(p_note)) NOT BETWEEN 3 AND 500 THEN RAISE EXCEPTION 'wf_invalid_input'; END IF;
 pay:=jsonb_build_object('e',p_employee,'d',p_work_date,'m',p_minutes,'n',btrim(p_note));
 SELECT * INTO b FROM wfi_begin(p_business,p_request,'decide_overtime',pay);
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 c:=b.o_ctx; PERFORM wfi_need(wfi_is_manager_plus(c),'wf_manager_required');
 IF NOT EXISTS(SELECT 1 FROM wf_employees WHERE id=p_employee AND business_id=p_business) THEN RAISE EXCEPTION 'wf_employee_not_found'; END IF;
 IF c.employee_id IS NOT NULL AND c.employee_id=p_employee THEN RAISE EXCEPTION 'wf_self_approval_denied'; END IF;
 IF wfi_period_locked(p_business,p_work_date) THEN RAISE EXCEPTION 'wf_period_locked'; END IF;
 d:=wfi_calc_day(p_business,p_employee,p_work_date);
 IF (d->>'overtime_minutes')::int=0 THEN RAISE EXCEPTION 'wf_no_overtime_on_day'; END IF;
 IF p_minutes>(d->>'overtime_minutes')::int THEN RAISE EXCEPTION 'wf_overtime_exceeds_computed'; END IF;
 INSERT INTO wf_overtime_approvals(tenant_id,business_id,employee_id,work_date,minutes,note,decided_by)
 VALUES(c.tenant_id,p_business,p_employee,p_work_date,p_minutes,btrim(p_note),c.user_id);
 PERFORM wfi_recompute_day(p_business,p_employee,p_work_date);
 res:=jsonb_build_object('status','applied','approved_minutes',p_minutes);
 PERFORM wfi_log(c.tenant_id,p_business,'overtime',p_employee::text||':'||p_work_date::text,'decided',NULL,pay,p_note,p_request);
 RETURN wfi_finish(p_business,c.tenant_id,p_request,'decide_overtime',pay,res);
END$$;

-- ===== Leave =====
CREATE FUNCTION c10_demo.wf_save_leave_type_v1(p_business bigint,p_request text,p_expected_version bigint,p_type jsonb,p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c wf_ctx_t; pay jsonb; lt wf_leave_types; v_id bigint; res jsonb;
BEGIN
 IF p_type IS NULL OR jsonb_typeof(p_type)<>'object' OR p_expected_version IS NULL OR p_reason IS NULL
  OR length(btrim(p_reason)) NOT BETWEEN 3 AND 500 THEN RAISE EXCEPTION 'wf_invalid_input'; END IF;
 pay:=jsonb_build_object('v',p_expected_version,'t',p_type,'r',btrim(p_reason));
 SELECT * INTO b FROM wfi_begin(p_business,p_request,'save_leave_type',pay);
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 c:=b.o_ctx; PERFORM wfi_need(wfi_is_owner(c),'wf_owner_required');
 BEGIN
  SELECT * INTO lt FROM wf_leave_types WHERE business_id=p_business AND code=p_type->>'code' FOR UPDATE;
  IF NOT FOUND THEN
   IF p_expected_version<>0 THEN RAISE EXCEPTION 'wf_stale_version'; END IF;
   INSERT INTO wf_leave_types(tenant_id,business_id,code,name,paid,annual_quota_days,requires_approval,max_days_per_request,allow_backdated,active)
   VALUES(c.tenant_id,p_business,p_type->>'code',btrim(p_type->>'name'),(p_type->>'paid')::boolean,(p_type->>'annual_quota_days')::numeric,
    COALESCE((p_type->>'requires_approval')::boolean,true),COALESCE((p_type->>'max_days_per_request')::int,30),
    COALESCE((p_type->>'allow_backdated')::boolean,true),COALESCE((p_type->>'active')::boolean,true)) RETURNING id INTO v_id;
   res:=jsonb_build_object('status','created','leave_type_id',v_id,'version',1);
  ELSE
   IF lt.version<>p_expected_version THEN RAISE EXCEPTION 'wf_stale_version'; END IF;
   UPDATE wf_leave_types SET name=btrim(p_type->>'name'),paid=(p_type->>'paid')::boolean,annual_quota_days=(p_type->>'annual_quota_days')::numeric,
    requires_approval=COALESCE((p_type->>'requires_approval')::boolean,true),max_days_per_request=COALESCE((p_type->>'max_days_per_request')::int,30),
    allow_backdated=COALESCE((p_type->>'allow_backdated')::boolean,true),active=COALESCE((p_type->>'active')::boolean,true),version=version+1
   WHERE id=lt.id;
   v_id:=lt.id; res:=jsonb_build_object('status','updated','leave_type_id',v_id,'version',lt.version+1);
  END IF;
 EXCEPTION WHEN check_violation OR invalid_text_representation OR not_null_violation OR numeric_value_out_of_range THEN
  RAISE EXCEPTION 'wf_invalid_input'; END;
 PERFORM wfi_log(c.tenant_id,p_business,'leave_type',v_id::text,'saved',CASE WHEN lt.id IS NULL THEN NULL ELSE to_jsonb(lt) END,p_type,p_reason,p_request);
 RETURN wfi_finish(p_business,c.tenant_id,p_request,'save_leave_type',pay,res);
END$$;

CREATE FUNCTION c10_demo.wfi_leave_days(p_business bigint,p_employee bigint,p_from date,p_to date) RETURNS numeric
LANGUAGE plpgsql AS $$
DECLARE d date; n numeric:=0;
BEGIN
 FOR d IN SELECT generate_series(p_from,p_to,interval '1 day')::date LOOP
  IF NOT c10_demo.wfi_is_off_day(p_business,p_employee,d) AND (c10_demo.wfi_holiday_on(p_business,p_employee,d)).id IS NULL THEN n:=n+1; END IF;
 END LOOP;
 RETURN n;
END$$;
CREATE FUNCTION c10_demo.wfi_leave_used(p_employee bigint,p_type bigint,p_year int,p_exclude bigint) RETURNS numeric
LANGUAGE sql STABLE AS $$
 SELECT COALESCE(sum(days),0) FROM c10_demo.wf_leave_requests WHERE employee_id=p_employee AND leave_type_id=p_type
  AND status IN('pending','approved') AND extract(year FROM from_date)=p_year AND id<>COALESCE(p_exclude,-1) $$;
CREATE FUNCTION c10_demo.wfi_leave_locked(p_business bigint,p_from date,p_to date) RETURNS boolean
LANGUAGE sql STABLE AS $$ SELECT c10_demo.wfi_range_locked(p_business,p_from,p_to) $$;

CREATE FUNCTION c10_demo.wf_request_leave_v1(p_business bigint,p_request text,p_employee bigint,p_type_code text,
 p_from date,p_to date,p_reason text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c wf_ctx_t; pay jsonb; v_emp bigint; e wf_employees; lt wf_leave_types; v_days numeric; v_id bigint; res jsonb; v_status text;
BEGIN
 IF p_type_code IS NULL OR p_from IS NULL OR p_to IS NULL OR p_reason IS NULL OR length(btrim(p_reason)) NOT BETWEEN 3 AND 500
  OR p_to<p_from OR p_to-p_from>59 THEN RAISE EXCEPTION 'wf_invalid_input'; END IF;
 pay:=jsonb_build_object('e',p_employee,'t',p_type_code,'f',p_from,'to',p_to,'r',btrim(p_reason));
 SELECT * INTO b FROM wfi_begin(p_business,p_request,'request_leave',pay);
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 c:=b.o_ctx;
 v_emp:=COALESCE(p_employee,c.employee_id);
 IF v_emp IS NULL THEN RAISE EXCEPTION 'wf_employee_required'; END IF;
 -- Staff can only request for themselves; owners/managers may file on behalf.
 PERFORM wfi_need((c.employee_id IS NOT NULL AND c.employee_id=v_emp) OR wfi_is_manager_plus(c),'wf_leave_request_denied');
 SELECT * INTO e FROM wf_employees WHERE id=v_emp AND business_id=p_business;
 IF NOT FOUND THEN RAISE EXCEPTION 'wf_employee_not_found'; END IF;
 IF COALESCE(wfi_status_on(v_emp,p_from),'terminated')<>'active' OR p_from<e.joined_on THEN RAISE EXCEPTION 'wf_employee_not_active'; END IF;
 SELECT * INTO lt FROM wf_leave_types WHERE business_id=p_business AND code=p_type_code AND active;
 IF NOT FOUND THEN RAISE EXCEPTION 'wf_leave_type_not_found'; END IF;
 IF extract(year FROM p_from)<>extract(year FROM p_to) THEN RAISE EXCEPTION 'wf_leave_cross_year'; END IF;
 IF p_from<wfi_today() AND NOT lt.allow_backdated THEN RAISE EXCEPTION 'wf_leave_backdate_denied'; END IF;
 IF wfi_leave_locked(p_business,p_from,p_to) THEN RAISE EXCEPTION 'wf_leave_affects_frozen_period'; END IF;
 IF EXISTS(SELECT 1 FROM wf_leave_requests WHERE employee_id=v_emp AND status IN('pending','approved') AND from_date<=p_to AND to_date>=p_from)
 THEN RAISE EXCEPTION 'wf_leave_overlap'; END IF;
 v_days:=wfi_leave_days(p_business,v_emp,p_from,p_to);
 IF v_days<=0 THEN RAISE EXCEPTION 'wf_leave_no_working_days'; END IF;
 IF v_days>lt.max_days_per_request THEN RAISE EXCEPTION 'wf_leave_too_long'; END IF;
 IF lt.annual_quota_days IS NOT NULL AND wfi_leave_used(v_emp,lt.id,extract(year FROM p_from)::int,NULL)+v_days>lt.annual_quota_days
 THEN RAISE EXCEPTION 'wf_leave_quota_exceeded'; END IF;
 v_status:=CASE WHEN lt.requires_approval THEN 'pending' ELSE 'approved' END;
 INSERT INTO wf_leave_requests(tenant_id,business_id,employee_id,leave_type_id,from_date,to_date,days,reason,status,requested_by,request_key,decided_at,decision_note)
 VALUES(c.tenant_id,p_business,v_emp,lt.id,p_from,p_to,v_days,btrim(p_reason),v_status,c.user_id,p_request,
  CASE WHEN v_status='approved' THEN now() END,CASE WHEN v_status='approved' THEN 'auto-approved by leave type policy' END)
 RETURNING id INTO v_id;
 IF v_status='approved' THEN PERFORM wfi_recompute_day(p_business,v_emp,d::date) FROM generate_series(p_from,p_to,interval '1 day') d; END IF;
 res:=jsonb_build_object('status',v_status,'leave_id',v_id,'days',v_days);
 PERFORM wfi_log(c.tenant_id,p_business,'leave',v_id::text,'requested',NULL,pay||jsonb_build_object('days',v_days),p_reason,p_request);
 RETURN wfi_finish(p_business,c.tenant_id,p_request,'request_leave',pay,res);
END$$;

CREATE FUNCTION c10_demo.wf_decide_leave_v1(p_business bigint,p_request text,p_leave bigint,p_decision text,p_note text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c wf_ctx_t; cfg wf_business_settings; pay jsonb; r wf_leave_requests; lt wf_leave_types; res jsonb; v_to text;
BEGIN
 IF p_leave IS NULL OR p_decision NOT IN('approve','reject','revoke') OR p_decision IS NULL OR p_note IS NULL
  OR length(btrim(p_note)) NOT BETWEEN 3 AND 500 THEN RAISE EXCEPTION 'wf_invalid_input'; END IF;
 pay:=jsonb_build_object('l',p_leave,'d',p_decision,'n',btrim(p_note));
 SELECT * INTO b FROM wfi_begin(p_business,p_request,'decide_leave',pay);
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 c:=b.o_ctx; cfg:=wfi_cfg(p_business);
 PERFORM wfi_need(wfi_is_owner(c) OR (c.is_manager AND cfg.leave_review_level='manager'),'wf_leave_review_denied');
 SELECT * INTO r FROM wf_leave_requests WHERE id=p_leave AND business_id=p_business FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'wf_leave_not_found'; END IF;
 -- Approver separation: never the requester, never the employee on leave.
 IF r.requested_by=c.user_id OR (c.employee_id IS NOT NULL AND c.employee_id=r.employee_id) THEN RAISE EXCEPTION 'wf_approver_must_differ'; END IF;
 IF (p_decision IN('approve','reject') AND r.status<>'pending') OR (p_decision='revoke' AND r.status<>'approved')
 THEN RAISE EXCEPTION 'wf_leave_state_invalid'; END IF;
 IF wfi_leave_locked(p_business,r.from_date,r.to_date) THEN RAISE EXCEPTION 'wf_leave_affects_frozen_period'; END IF;
 IF p_decision='approve' THEN
  SELECT * INTO lt FROM wf_leave_types WHERE id=r.leave_type_id;
  IF EXISTS(SELECT 1 FROM wf_leave_requests WHERE employee_id=r.employee_id AND id<>r.id AND status='approved'
     AND from_date<=r.to_date AND to_date>=r.from_date) THEN RAISE EXCEPTION 'wf_leave_overlap'; END IF;
  IF lt.annual_quota_days IS NOT NULL AND wfi_leave_used(r.employee_id,lt.id,extract(year FROM r.from_date)::int,r.id)+r.days>lt.annual_quota_days
  THEN RAISE EXCEPTION 'wf_leave_quota_exceeded'; END IF;
 END IF;
 v_to:=CASE p_decision WHEN 'approve' THEN 'approved' WHEN 'reject' THEN 'rejected' ELSE 'revoked' END;
 UPDATE wf_leave_requests SET status=v_to,decided_by=c.user_id,decided_at=now(),decision_note=btrim(p_note) WHERE id=r.id;
 PERFORM wfi_recompute_day(p_business,r.employee_id,d::date) FROM generate_series(r.from_date,r.to_date,interval '1 day') d;
 res:=jsonb_build_object('status',v_to);
 PERFORM wfi_log(c.tenant_id,p_business,'leave',p_leave::text,p_decision,jsonb_build_object('status',r.status),res,p_note,p_request);
 RETURN wfi_finish(p_business,c.tenant_id,p_request,'decide_leave',pay,res);
END$$;

CREATE FUNCTION c10_demo.wf_cancel_leave_v1(p_business bigint,p_request text,p_leave bigint,p_note text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c wf_ctx_t; pay jsonb; r wf_leave_requests; res jsonb;
BEGIN
 IF p_leave IS NULL OR p_note IS NULL OR length(btrim(p_note)) NOT BETWEEN 3 AND 500 THEN RAISE EXCEPTION 'wf_invalid_input'; END IF;
 pay:=jsonb_build_object('l',p_leave,'n',btrim(p_note));
 SELECT * INTO b FROM wfi_begin(p_business,p_request,'cancel_leave',pay);
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 c:=b.o_ctx;
 SELECT * INTO r FROM wf_leave_requests WHERE id=p_leave AND business_id=p_business FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'wf_leave_not_found'; END IF;
 PERFORM wfi_need(r.requested_by=c.user_id OR (c.employee_id IS NOT NULL AND c.employee_id=r.employee_id),'wf_leave_cancel_denied');
 IF r.status<>'pending' THEN RAISE EXCEPTION 'wf_leave_state_invalid'; END IF;
 UPDATE wf_leave_requests SET status='cancelled',decided_by=c.user_id,decided_at=now(),decision_note=btrim(p_note) WHERE id=r.id;
 res:=jsonb_build_object('status','cancelled');
 PERFORM wfi_log(c.tenant_id,p_business,'leave',p_leave::text,'cancelled',jsonb_build_object('status',r.status),res,p_note,p_request);
 RETURN wfi_finish(p_business,c.tenant_id,p_request,'cancel_leave',pay,res);
END$$;
