-- C10-A054 Workforce policy governance (1/2): delegation, effective-dated policy versions, leave carry-forward,
-- legal holds, external-payment RECORDS and liability report. DISPOSABLE c10_demo ONLY. Apply AFTER A051 (4 files).
-- Additive: new a054_* tables/functions only. A051 behaviour is hooked by c10_a054_workforce_bridge_v1.sql.
-- "Approved" is NEVER "Paid": this module executes no payment, bank file, ledger or money movement.
DO $gate$ BEGIN
 IF current_database() !~ '^core10_a0(46|48|53)_(ci|local)' THEN RAISE EXCEPTION 'A054_DISPOSABLE_DB_REQUIRED'; END IF;
 IF to_regprocedure('c10_demo.wf_payroll_transition_v1(bigint,text,bigint,text,text)') IS NULL THEN RAISE EXCEPTION 'A054_REQUIRES_A051'; END IF;
END $gate$;

CREATE TABLE c10_demo.a054_delegations(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL, business_id bigint NOT NULL, delegate_uid uuid NOT NULL,
 role text NOT NULL CHECK(role IN('hr','payroll_preparer','payroll_reviewer','payroll_approver','payment_recorder')),
 effect text NOT NULL DEFAULT 'allow' CHECK(effect IN('allow','deny')),
 site_id bigint, period_from date, period_to date,
 effective_from timestamptz NOT NULL DEFAULT clock_timestamp(), expires_at timestamptz,
 revoked_at timestamptz, revoked_by uuid, revoke_note text,
 granted_by uuid NOT NULL, reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 3 AND 500),
 request_key text NOT NULL, version bigint NOT NULL DEFAULT 1, created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 CHECK(period_from IS NULL OR extract(day FROM period_from)=1), CHECK(period_to IS NULL OR extract(day FROM period_to)=1),
 CHECK(period_to IS NULL OR period_from IS NULL OR period_to>=period_from),
 CHECK(expires_at IS NULL OR expires_at>effective_from), CHECK(role='hr' OR site_id IS NULL),
 UNIQUE(business_id,request_key),
 FOREIGN KEY(business_id,tenant_id) REFERENCES c10_demo.businesses(id,tenant_id),
 FOREIGN KEY(site_id,tenant_id,business_id) REFERENCES c10_demo.sites(id,tenant_id,business_id)
);
CREATE INDEX a054_deleg_lookup_ix ON c10_demo.a054_delegations(business_id,delegate_uid,role);
CREATE FUNCTION c10_demo.a054i_deleg_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'wf_append_only_record'; END IF;
 IF OLD.revoked_at IS NULL AND NEW.revoked_at IS NOT NULL AND NEW.version=OLD.version+1
  AND (to_jsonb(NEW)-'revoked_at'-'revoked_by'-'revoke_note'-'version')=(to_jsonb(OLD)-'revoked_at'-'revoked_by'-'revoke_note'-'version')
 THEN RETURN NEW; END IF;
 RAISE EXCEPTION 'wf_append_only_record';
END$$;
CREATE TRIGGER a054_deleg_guard BEFORE UPDATE OR DELETE ON c10_demo.a054_delegations FOR EACH ROW EXECUTE FUNCTION c10_demo.a054i_deleg_guard();

CREATE TABLE c10_demo.a054_policy_versions(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL, business_id bigint NOT NULL,
 kind text NOT NULL CHECK(kind IN('overtime','pay_rule','leave')),
 subject text NOT NULL CHECK(subject ~ '^[A-Za-z0-9][A-Za-z0-9_-]{0,23}$'),
 version int NOT NULL, effective_from date NOT NULL, params jsonb NOT NULL,
 reason text NOT NULL, legal_ref text, created_by uuid NOT NULL, request_key text NOT NULL,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 CHECK(kind='leave' OR extract(day FROM effective_from)=1),
 CHECK(kind<>'leave' OR (extract(day FROM effective_from)=1 AND extract(month FROM effective_from)=1)),
 UNIQUE(business_id,kind,subject,version), UNIQUE(business_id,request_key),
 FOREIGN KEY(business_id,tenant_id) REFERENCES c10_demo.businesses(id,tenant_id)
);
CREATE INDEX a054_policy_lookup_ix ON c10_demo.a054_policy_versions(business_id,kind,subject,effective_from DESC,version DESC);
CREATE TRIGGER a054_policy_immutable BEFORE UPDATE OR DELETE ON c10_demo.a054_policy_versions FOR EACH ROW EXECUTE FUNCTION c10_demo.wfi_immutable();

CREATE TABLE c10_demo.a054_legal_holds(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL, business_id bigint NOT NULL, employee_id bigint,
 hold_from date NOT NULL, hold_to date NOT NULL CHECK(hold_to>=hold_from),
 reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 5 AND 500),
 placed_by uuid NOT NULL, placed_at timestamptz NOT NULL DEFAULT clock_timestamp(), request_key text NOT NULL,
 released_at timestamptz, released_by uuid, release_note text,
 UNIQUE(business_id,request_key),
 FOREIGN KEY(business_id,tenant_id) REFERENCES c10_demo.businesses(id,tenant_id),
 FOREIGN KEY(employee_id,tenant_id,business_id) REFERENCES c10_demo.wf_employees(id,tenant_id,business_id)
);
CREATE FUNCTION c10_demo.a054i_hold_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF TG_OP='UPDATE' AND OLD.released_at IS NULL AND NEW.released_at IS NOT NULL
  AND (to_jsonb(NEW)-'released_at'-'released_by'-'release_note')=(to_jsonb(OLD)-'released_at'-'released_by'-'release_note') THEN RETURN NEW; END IF;
 RAISE EXCEPTION 'wf_append_only_record';
END$$;
CREATE TRIGGER a054_hold_guard BEFORE UPDATE OR DELETE ON c10_demo.a054_legal_holds FOR EACH ROW EXECUTE FUNCTION c10_demo.a054i_hold_guard();

-- Records of payments made OUTSIDE this system. Not a payment instruction. Append-only.
CREATE TABLE c10_demo.a054_payment_records(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL, business_id bigint NOT NULL, period_start date NOT NULL CHECK(extract(day FROM period_start)=1),
 employee_id bigint NOT NULL, run_id bigint NOT NULL,
 record_kind text NOT NULL CHECK(record_kind IN('external_payment_record','reversal')),
 amount numeric(14,2) NOT NULL CHECK(amount>0),
 method text NOT NULL CHECK(method IN('cash','bank_transfer','mobile_wallet','other')),
 external_reference text NOT NULL CHECK(length(btrim(external_reference)) BETWEEN 3 AND 80),
 paid_on date NOT NULL, note text, reverses_id bigint,
 recorded_by uuid NOT NULL, request_key text NOT NULL, created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 CHECK((record_kind='reversal')=(reverses_id IS NOT NULL)),
 UNIQUE(business_id,request_key),
 FOREIGN KEY(business_id,tenant_id) REFERENCES c10_demo.businesses(id,tenant_id),
 FOREIGN KEY(employee_id,tenant_id,business_id) REFERENCES c10_demo.wf_employees(id,tenant_id,business_id)
);
CREATE UNIQUE INDEX a054_pay_reversal_once_ux ON c10_demo.a054_payment_records(reverses_id) WHERE reverses_id IS NOT NULL;
CREATE TRIGGER a054_pay_immutable BEFORE UPDATE OR DELETE ON c10_demo.a054_payment_records FOR EACH ROW EXECUTE FUNCTION c10_demo.wfi_immutable();

-- ===== Delegation evaluation (live on every call: revocation/expiry are immediate) =====
-- mode any: coarse; wide: business-wide grants only; exact: site/period scoped. DENY beats ALLOW.
CREATE FUNCTION c10_demo.a054i_deleg(p_business bigint,p_role text,p_site bigint,p_period date,p_mode text) RETURNS text
LANGUAGE sql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
 WITH m AS(
  SELECT d.effect,
   CASE p_mode WHEN 'any' THEN true WHEN 'wide' THEN d.site_id IS NULL
    ELSE (d.site_id IS NULL OR d.site_id=p_site) AND (p_period IS NULL OR
     ((d.period_from IS NULL OR date_trunc('month',p_period)::date>=d.period_from)
      AND (d.period_to IS NULL OR date_trunc('month',p_period)::date<=d.period_to))) END AS hit,
   (d.site_id IS NULL AND d.period_from IS NULL AND d.period_to IS NULL) AS unscoped
  FROM a054_delegations d
  WHERE d.business_id=p_business AND d.delegate_uid=actor_uid() AND d.role=p_role AND d.revoked_at IS NULL
   AND d.effective_from<=clock_timestamp() AND (d.expires_at IS NULL OR d.expires_at>clock_timestamp())
   AND (EXISTS(SELECT 1 FROM business_members bm WHERE bm.user_id=d.delegate_uid AND bm.business_id=d.business_id AND bm.active
         AND bm.role IN('manager','business_owner'))
        OR EXISTS(SELECT 1 FROM wf_employees e WHERE e.user_id=d.delegate_uid AND e.business_id=d.business_id AND e.status='active')))
 SELECT CASE WHEN EXISTS(SELECT 1 FROM m WHERE effect='deny' AND hit AND (p_mode<>'any' OR unscoped)) THEN 'deny'
  WHEN EXISTS(SELECT 1 FROM m WHERE effect='allow' AND hit) THEN 'allow' ELSE 'none' END $$;

CREATE FUNCTION c10_demo.a054i_cap_roles(p_cap text) RETURNS text[] LANGUAGE sql IMMUTABLE AS $$
 SELECT CASE p_cap WHEN 'prepare' THEN ARRAY['payroll_preparer'] WHEN 'review' THEN ARRAY['payroll_reviewer']
  WHEN 'approve' THEN ARRAY['payroll_approver'] WHEN 'return' THEN ARRAY['payroll_reviewer','payroll_approver']
  WHEN 'transition' THEN ARRAY['payroll_reviewer','payroll_approver']
  WHEN 'view' THEN ARRAY['payroll_preparer','payroll_reviewer','payroll_approver']
  WHEN 'liability' THEN ARRAY['payroll_preparer','payroll_reviewer','payroll_approver','payment_recorder'] ELSE ARRAY[]::text[] END $$;
CREATE FUNCTION c10_demo.a054i_pay_access(p_business bigint,p_cap text) RETURNS boolean LANGUAGE sql SECURITY DEFINER
SET search_path=c10_demo,pg_catalog AS $$
 SELECT EXISTS(SELECT 1 FROM unnest(a054i_cap_roles(p_cap)) r WHERE a054i_deleg(p_business,r,NULL,NULL,'any')='allow') $$;
CREATE FUNCTION c10_demo.a054i_pay_period_gate(c c10_demo.wf_ctx_t,p_business bigint,p_cap text,p_period date) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
BEGIN
 IF wfi_is_owner(c) THEN RETURN; END IF;
 IF NOT EXISTS(SELECT 1 FROM unnest(a054i_cap_roles(p_cap)) r WHERE a054i_deleg(p_business,r,NULL,p_period,'exact')='allow')
 THEN RAISE EXCEPTION 'a054_delegation_denied'; END IF;
END$$;
CREATE FUNCTION c10_demo.a054i_period_visible(p_business bigint,p_period date) RETURNS boolean LANGUAGE sql SECURITY DEFINER
SET search_path=c10_demo,pg_catalog AS $$
 SELECT EXISTS(SELECT 1 FROM unnest(a054i_cap_roles('view')) r WHERE a054i_deleg(p_business,r,NULL,p_period,'exact')='allow') $$;
CREATE FUNCTION c10_demo.a054i_transition_gate(c c10_demo.wf_ctx_t,p_business bigint,p_action text,r c10_demo.wf_payroll_runs,
 cfg c10_demo.wf_business_settings) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE cp text;
BEGIN
 IF wfi_is_owner(c) THEN RETURN; END IF;
 IF p_action='void' THEN RAISE EXCEPTION 'a054_owner_required'; END IF;
 IF c.employee_id IS NOT NULL AND EXISTS(SELECT 1 FROM wf_payroll_lines l WHERE l.run_id=r.id AND l.employee_id=c.employee_id) THEN RAISE EXCEPTION 'a054_self_in_run_denied'; END IF;
 cp:=CASE p_action WHEN 'review' THEN 'review' WHEN 'approve' THEN 'approve' WHEN 'freeze' THEN 'approve' ELSE 'return' END;
 PERFORM a054i_pay_period_gate(c,p_business,cp,r.period_start);
 IF cfg.require_maker_checker THEN
  IF p_action IN('approve','freeze') AND r.prepared_by=c.user_id THEN RAISE EXCEPTION 'wf_maker_checker_violation'; END IF;
  IF p_action IN('approve','freeze') AND r.reviewed_by=c.user_id THEN RAISE EXCEPTION 'wf_maker_checker_violation'; END IF;
 END IF;
END$$;
-- HR delegation gate (leave/correction decisions). owner always; legacy manager path honoured unless explicitly denied.
CREATE FUNCTION c10_demo.a054i_hr_scope(c c10_demo.wf_ctx_t,p_business bigint,p_manager_path boolean,p_site bigint,p_date date) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE v text;
BEGIN
 IF wfi_is_owner(c) THEN RETURN; END IF;
 v:=a054i_deleg(p_business,'hr',p_site,p_date,'exact');
 IF v='deny' THEN RAISE EXCEPTION 'a054_delegation_denied'; END IF;
 IF v='allow' OR p_manager_path THEN RETURN; END IF;
 RAISE EXCEPTION 'a054_delegation_denied';
END$$;

-- ===== Policy lookup and calculation hooks =====
CREATE FUNCTION c10_demo.a054i_policy_on(p_business bigint,p_kind text,p_subject text,p_date date) RETURNS c10_demo.a054_policy_versions
LANGUAGE sql STABLE AS $$
 SELECT v.* FROM c10_demo.a054_policy_versions v WHERE v.business_id=p_business AND v.kind=p_kind AND v.subject=p_subject
  AND v.effective_from<=p_date ORDER BY v.effective_from DESC,v.version DESC LIMIT 1 $$;

CREATE FUNCTION c10_demo.a054i_ot_pay(p_business bigint,p_start date,p_hourly numeric,p_otw int,p_oto int,p_mw numeric,p_mo numeric,p_mode text)
RETURNS numeric LANGUAGE plpgsql AS $$
DECLARE pv c10_demo.a054_policy_versions;
BEGIN
 pv:=c10_demo.a054i_policy_on(p_business,'overtime','DEFAULT',p_start);
 IF pv.id IS NULL THEN
  RETURN c10_demo.wfi_rnd(p_hourly*(p_otw::numeric/60)*p_mw+p_hourly*(p_oto::numeric/60)*p_mo,p_mode); END IF;
 IF pv.params->>'mode'='off' THEN RETURN 0; END IF;
 RETURN c10_demo.wfi_rnd(p_hourly*(p_otw::numeric/60)*(pv.params->>'weekday_multiplier')::numeric
   +p_hourly*(p_oto::numeric/60)*(pv.params->>'offday_multiplier')::numeric,p_mode);
END$$;

CREATE FUNCTION c10_demo.a054i_apply_rules(p_business bigint,p_employee bigint,p_start date,p_end date,p_contract_base numeric,
 p_basic numeric,p_ot numeric,p_allow numeric,p_emp_days int,p_cal int,p_mode text,p_basis text,p_site bigint,
 OUT add_allow numeric,OUT add_ded numeric,OUT comps jsonb,OUT warns jsonb) RETURNS record LANGUAGE plpgsql AS $$
DECLARE rl record; p jsonb; v numeric; base_v numeric; base_n text; raw numeric; contract text:=c10_demo.wfi_contract_on(p_employee,p_end);
 running numeric:=p_allow; trace jsonb; pv c10_demo.a054_policy_versions;
BEGIN
 add_allow:=0; add_ded:=0; comps:='[]'; warns:='[]';
 pv:=c10_demo.a054i_policy_on(p_business,'overtime','DEFAULT',p_start);
 IF pv.id IS NOT NULL THEN
  comps:=comps||jsonb_build_array(jsonb_build_object('kind','trace','code','OT_POLICY','policy_version_id',pv.id,'effective_from',pv.effective_from,
   'mode',pv.params->>'mode','weekday_multiplier',pv.params->'weekday_multiplier','offday_multiplier',pv.params->'offday_multiplier',
   'semantics','1.00x = 100% of base hourly rate'));
 END IF;
 FOR rl IN SELECT DISTINCT ON (x.subject) x.* FROM c10_demo.a054_policy_versions x
   WHERE x.business_id=p_business AND x.kind='pay_rule' AND x.effective_from<=p_start
   ORDER BY x.subject,x.effective_from DESC,x.version DESC LOOP
  p:=rl.params;
  IF NOT (p->>'enabled')::boolean THEN CONTINUE; END IF;
  IF p->'scope' ? 'contract_types' AND NOT (p->'scope'->'contract_types') ? contract THEN CONTINUE; END IF;
  IF p->'scope' ? 'site_ids' AND NOT (p->'scope'->'site_ids') @> to_jsonb(p_site) THEN CONTINUE; END IF;
  IF p->>'calc'='fixed' THEN
   raw:=(p->>'amount')::numeric; base_n:=NULL; base_v:=NULL;
   IF (p->>'prorate')::boolean AND p_basis='monthly' AND p_emp_days<p_cal THEN raw:=raw*p_emp_days/p_cal; END IF;
  ELSE
   base_n:=p->>'base';
   base_v:=CASE base_n WHEN 'basic_earned' THEN p_basic WHEN 'contract_base' THEN p_contract_base ELSE p_basic+p_ot+running END;
   raw:=base_v*(p->>'amount')::numeric/100;
  END IF;
  v:=raw;
  IF p->>'cap_amount' IS NOT NULL THEN v:=LEAST(v,(p->>'cap_amount')::numeric); END IF;
  IF p->>'min_amount' IS NOT NULL THEN v:=GREATEST(v,(p->>'min_amount')::numeric); END IF;
  v:=c10_demo.wfi_rnd(v,p_mode);
  trace:=jsonb_build_object('calc',p->>'calc','amount_param',p->'amount','unit',CASE WHEN p->>'calc'='percent' THEN 'percent_of_base' ELSE 'currency' END,
   'base',base_n,'base_value',base_v,'raw',c10_demo.wfi_rnd(raw,p_mode),'cap',p->'cap_amount','min',p->'min_amount',
   'policy_version_id',rl.id,'version',rl.version,'effective_from',rl.effective_from);
  comps:=comps||jsonb_build_array(jsonb_build_object('code',rl.subject,'name',p->>'name','kind',p->>'kind','amount',v,'source','a054_rule','trace',trace));
  IF p->>'kind'='allowance' THEN add_allow:=add_allow+v; running:=running+v; ELSE add_ded:=add_ded+v; END IF;
 END LOOP;
END$$;

-- ===== Leave policy: accrual, carry-forward with cap, expiry/grace, cross-year =====
CREATE FUNCTION c10_demo.a054i_leave_dates(p_business bigint,p_emp bigint,p_from date,p_to date) RETURNS date[]
LANGUAGE plpgsql AS $$
DECLARE d date; r date[]:='{}';
BEGIN
 IF p_to<p_from THEN RETURN r; END IF;
 FOR d IN SELECT generate_series(p_from,p_to,interval '1 day')::date LOOP
  IF NOT c10_demo.wfi_is_off_day(p_business,p_emp,d) AND (c10_demo.wfi_holiday_on(p_business,p_emp,d)).id IS NULL THEN r:=r||d; END IF;
 END LOOP;
 RETURN r;
END$$;
CREATE FUNCTION c10_demo.a054i_year_sim(p_emp bigint,p_type bigint,p_year int,p_extra date[],p_exclude bigint,p_depth int) RETURNS jsonb
LANGUAGE plpgsql AS $$
DECLARE lt c10_demo.wf_leave_types; e c10_demo.wf_employees; pv c10_demo.a054_policy_versions; pol jsonb; ent numeric; accrual text:='upfront';
 cap numeric:=0; carry_in numeric:=0; prior jsonb; days date[]:='{}'; r record; d date; carry_rem numeric; carry_used numeric:=0;
 main_used numeric:=0; expiry date; avail numeric; viol date; y0 date:=make_date(p_year,1,1); y1 date:=make_date(p_year,12,31);
BEGIN
 SELECT * INTO lt FROM c10_demo.wf_leave_types WHERE id=p_type; SELECT * INTO e FROM c10_demo.wf_employees WHERE id=p_emp;
 pv:=c10_demo.a054i_policy_on(lt.business_id,'leave',lt.code,y0);
 IF pv.id IS NOT NULL AND (pv.params->>'enabled')::boolean THEN
  pol:=pv.params; ent:=(pol->>'annual_quota_days')::numeric; accrual:=pol->>'accrual'; cap:=(pol->>'carry_forward_cap_days')::numeric;
 ELSE pol:=NULL; ent:=lt.annual_quota_days; END IF;
 IF pol IS NOT NULL AND cap>0 AND p_depth<10 AND p_year-1>=extract(year FROM e.joined_on)::int THEN
  prior:=c10_demo.a054i_year_sim(p_emp,p_type,p_year-1,'{}',p_exclude,p_depth+1);
  carry_in:=LEAST(cap,(prior->>'remaining_end')::numeric);
 END IF;
 IF pol IS NOT NULL AND pol->>'carry_expiry_months' IS NOT NULL THEN
  expiry:=(y0+make_interval(months=>(pol->>'carry_expiry_months')::int))::date-1+COALESCE((pol->>'grace_days')::int,0); END IF;
 FOR r IN SELECT from_date,to_date FROM c10_demo.wf_leave_requests WHERE employee_id=p_emp AND leave_type_id=p_type
   AND status IN('pending','approved') AND id<>COALESCE(p_exclude,-1) AND from_date<=y1 AND to_date>=y0 LOOP
  days:=days||c10_demo.a054i_leave_dates(lt.business_id,p_emp,GREATEST(r.from_date,y0),LEAST(r.to_date,y1));
 END LOOP;
 days:=days||COALESCE(p_extra,'{}');
 carry_rem:=carry_in;
 FOR d IN SELECT x FROM unnest(days) x ORDER BY x LOOP
  IF carry_rem>0 AND (expiry IS NULL OR d<=expiry) THEN carry_rem:=carry_rem-1; carry_used:=carry_used+1;
  ELSE
   main_used:=main_used+1;
   IF ent IS NOT NULL THEN
    avail:=CASE WHEN accrual='monthly' THEN ent*extract(month FROM d)/12 ELSE ent END;
    IF main_used>avail AND viol IS NULL THEN viol:=d; END IF;
   END IF;
  END IF;
 END LOOP;
 RETURN jsonb_build_object('year',p_year,'policy',pol IS NOT NULL,'policy_version_id',pv.id,'accrual',accrual,'entitlement',ent,
  'carried_in',carry_in,'carry_used',carry_used,'carry_expiry_date',expiry,'carry_expired',CASE WHEN expiry IS NOT NULL THEN carry_rem ELSE 0 END,
  'carry_unused',CASE WHEN expiry IS NULL THEN carry_rem ELSE 0 END,'main_used',main_used,'used_total',carry_used+main_used,
  'remaining_end',GREATEST(0,COALESCE(ent,0)-main_used)+CASE WHEN expiry IS NULL THEN carry_rem ELSE 0 END,
  'violation_date',viol,'ok',viol IS NULL);
END$$;
CREATE FUNCTION c10_demo.a054i_leave_quota_ok(p_emp bigint,p_type bigint,p_from date,p_to date,p_exclude bigint) RETURNS boolean
LANGUAGE plpgsql AS $$
DECLARE y int; biz bigint; sim jsonb;
BEGIN
 SELECT business_id INTO biz FROM c10_demo.wf_leave_types WHERE id=p_type;
 FOR y IN extract(year FROM p_from)::int..extract(year FROM p_to)::int LOOP
  sim:=c10_demo.a054i_year_sim(p_emp,p_type,y,c10_demo.a054i_leave_dates(biz,p_emp,GREATEST(p_from,make_date(y,1,1)),LEAST(p_to,make_date(y,12,31))),p_exclude,0);
  IF NOT (sim->>'ok')::boolean THEN RETURN false; END IF;
 END LOOP;
 RETURN true;
END$$;
CREATE FUNCTION c10_demo.a054i_leave_cross_year_ok(p_business bigint,p_type text,p_from date) RETURNS boolean
LANGUAGE sql STABLE AS $$
 SELECT COALESCE((SELECT (v.params->>'enabled')::boolean AND (v.params->>'allow_cross_year')::boolean
  FROM c10_demo.a054i_policy_on(p_business,'leave',p_type,make_date(extract(year FROM p_from)::int,1,1)) v WHERE v.id IS NOT NULL),false) $$;
CREATE FUNCTION c10_demo.a054i_punch_held(p_business bigint,p_emp bigint,p_date date) RETURNS boolean LANGUAGE sql STABLE AS $$
 SELECT EXISTS(SELECT 1 FROM c10_demo.a054_legal_holds h WHERE h.business_id=p_business AND h.released_at IS NULL
  AND (h.employee_id IS NULL OR h.employee_id=p_emp) AND p_date BETWEEN h.hold_from AND h.hold_to) $$;

-- ===== Policy validation =====
CREATE FUNCTION c10_demo.a054i_keys_ok(p jsonb,allowed text[]) RETURNS void LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
 IF p IS NULL OR jsonb_typeof(p)<>'object' OR EXISTS(SELECT 1 FROM jsonb_object_keys(p) k WHERE k<>ALL(allowed)) THEN RAISE EXCEPTION 'a054_invalid_policy'; END IF;
END$$;
CREATE FUNCTION c10_demo.a054i_num(p jsonb,k text,lo numeric,hi numeric,req boolean,maxscale int DEFAULT 2) RETURNS numeric
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE v numeric;
BEGIN
 IF NOT (p ? k) OR jsonb_typeof(p->k)='null' THEN IF req THEN RAISE EXCEPTION 'a054_invalid_policy'; END IF; RETURN NULL; END IF;
 IF jsonb_typeof(p->k)<>'number' THEN RAISE EXCEPTION 'a054_invalid_policy'; END IF;
 v:=(p->>k)::numeric;
 IF v<lo OR v>hi OR scale(v)>maxscale THEN RAISE EXCEPTION 'a054_invalid_policy'; END IF;
 RETURN v;
END$$;
CREATE FUNCTION c10_demo.a054i_norm_policy(p_business bigint,p_kind text,p_subject text,p jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE m text; wm numeric; om numeric; k text; amt numeric; capv numeric; minv numeric; sc jsonb:=NULL; ct jsonb; out jsonb;
BEGIN
 IF p_kind='overtime' THEN
  PERFORM c10_demo.a054i_keys_ok(p,ARRAY['mode','weekday_multiplier','offday_multiplier']);
  IF p_subject<>'DEFAULT' THEN RAISE EXCEPTION 'a054_invalid_policy'; END IF;
  m:=p->>'mode'; IF m IS NULL OR m NOT IN('on','off') THEN RAISE EXCEPTION 'a054_invalid_policy'; END IF;
  IF m='off' THEN
   IF p ? 'weekday_multiplier' OR p ? 'offday_multiplier' THEN RAISE EXCEPTION 'a054_invalid_policy'; END IF;
   RETURN jsonb_build_object('mode','off');
  END IF;
  FOREACH k IN ARRAY ARRAY['weekday_multiplier','offday_multiplier'] LOOP
   IF NOT (p ? k) OR jsonb_typeof(p->k)<>'number' THEN RAISE EXCEPTION 'a054_invalid_policy'; END IF;
   IF (p->>k)::numeric<1 THEN RAISE EXCEPTION 'a054_multiplier_below_base_rate'; END IF;
   IF (p->>k)::numeric>5 THEN RAISE EXCEPTION 'a054_multiplier_above_limit_use_x_not_percent'; END IF;
   IF scale((p->>k)::numeric)>2 THEN RAISE EXCEPTION 'a054_invalid_policy'; END IF;
  END LOOP;
  RETURN jsonb_build_object('mode','on','weekday_multiplier',(p->>'weekday_multiplier')::numeric,'offday_multiplier',(p->>'offday_multiplier')::numeric);
 ELSIF p_kind='pay_rule' THEN
  PERFORM c10_demo.a054i_keys_ok(p,ARRAY['name','kind','calc','amount','base','cap_amount','min_amount','prorate','enabled','scope','statutory']);
  IF p->>'name' IS NULL OR length(btrim(p->>'name')) NOT BETWEEN 2 AND 80 OR p->>'kind' NOT IN('allowance','deduction')
   OR p->>'calc' NOT IN('fixed','percent') THEN RAISE EXCEPTION 'a054_invalid_policy'; END IF;
  amt:=c10_demo.a054i_num(p,'amount',0,CASE WHEN p->>'calc'='percent' THEN 100 ELSE 99999999999 END,true,4);
  capv:=c10_demo.a054i_num(p,'cap_amount',0,99999999999,false); minv:=c10_demo.a054i_num(p,'min_amount',0,99999999999,false);
  IF capv IS NOT NULL AND minv IS NOT NULL AND minv>capv THEN RAISE EXCEPTION 'a054_invalid_policy'; END IF;
  IF p->>'calc'='percent' AND (p->>'base' IS NULL OR p->>'base' NOT IN('basic_earned','gross_before_rule','contract_base') OR COALESCE((p->>'prorate')::boolean,false))
   THEN RAISE EXCEPTION 'a054_invalid_policy'; END IF;
  IF p->>'calc'='fixed' AND p ? 'base' THEN RAISE EXCEPTION 'a054_invalid_policy'; END IF;
  IF p ? 'scope' THEN
   PERFORM c10_demo.a054i_keys_ok(p->'scope',ARRAY['contract_types','site_ids']); sc:='{}';
   IF p->'scope' ? 'contract_types' THEN
    ct:=p->'scope'->'contract_types';
    IF jsonb_typeof(ct)<>'array' OR jsonb_array_length(ct)=0 OR EXISTS(SELECT 1 FROM jsonb_array_elements_text(ct) x
      WHERE x NOT IN('permanent','contract','probation','daily','hourly','intern')) THEN RAISE EXCEPTION 'a054_invalid_policy'; END IF;
    sc:=sc||jsonb_build_object('contract_types',ct); END IF;
   IF p->'scope' ? 'site_ids' THEN
    ct:=p->'scope'->'site_ids';
    IF jsonb_typeof(ct)<>'array' OR jsonb_array_length(ct)=0 OR EXISTS(SELECT 1 FROM jsonb_array_elements(ct) x
      WHERE jsonb_typeof(x)<>'number' OR NOT EXISTS(SELECT 1 FROM c10_demo.sites s WHERE s.id=(x#>>'{}')::bigint AND s.business_id=p_business))
    THEN RAISE EXCEPTION 'a054_invalid_policy'; END IF;
    sc:=sc||jsonb_build_object('site_ids',ct); END IF;
  END IF;
  out:=jsonb_build_object('name',btrim(p->>'name'),'kind',p->>'kind','calc',p->>'calc','amount',amt,'prorate',COALESCE((p->>'prorate')::boolean,false),
   'enabled',COALESCE((p->>'enabled')::boolean,true),'statutory',COALESCE((p->>'statutory')::boolean,false));
  IF p ? 'base' THEN out:=out||jsonb_build_object('base',p->>'base'); END IF;
  IF capv IS NOT NULL THEN out:=out||jsonb_build_object('cap_amount',capv); END IF;
  IF minv IS NOT NULL THEN out:=out||jsonb_build_object('min_amount',minv); END IF;
  IF sc IS NOT NULL THEN out:=out||jsonb_build_object('scope',sc); END IF;
  RETURN out;
 ELSE
  PERFORM c10_demo.a054i_keys_ok(p,ARRAY['accrual','annual_quota_days','carry_forward_cap_days','carry_expiry_months','grace_days','allow_cross_year','enabled']);
  IF p->>'accrual' IS NULL OR p->>'accrual' NOT IN('upfront','monthly') THEN RAISE EXCEPTION 'a054_invalid_policy'; END IF;
  amt:=c10_demo.a054i_num(p,'annual_quota_days',0,366,true,1); capv:=COALESCE(c10_demo.a054i_num(p,'carry_forward_cap_days',0,366,false,1),0);
  minv:=c10_demo.a054i_num(p,'carry_expiry_months',1,12,false,0); wm:=COALESCE(c10_demo.a054i_num(p,'grace_days',0,90,false,0),0);
  IF minv IS NULL AND wm>0 THEN RAISE EXCEPTION 'a054_invalid_policy'; END IF;
  RETURN jsonb_build_object('accrual',p->>'accrual','annual_quota_days',amt,'carry_forward_cap_days',capv,'carry_expiry_months',minv,
   'grace_days',wm,'allow_cross_year',COALESCE((p->>'allow_cross_year')::boolean,false),'enabled',COALESCE((p->>'enabled')::boolean,true));
 END IF;
EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range OR cannot_coerce OR datatype_mismatch THEN
 RAISE EXCEPTION 'a054_invalid_policy';
END$$;

-- ===== Delegation RPCs =====
CREATE FUNCTION c10_demo.a054_grant_delegation_v1(p_business bigint,p_request text,p_delegate uuid,p_role text,p_effect text,p_site bigint,
 p_period_from date,p_period_to date,p_expires_at timestamptz,p_reason text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c wf_ctx_t; pay jsonb; v_id bigint; res jsonb;
BEGIN
 IF p_delegate IS NULL OR p_role IS NULL OR p_effect IS NULL OR p_reason IS NULL OR length(btrim(p_reason)) NOT BETWEEN 3 AND 500
  THEN RAISE EXCEPTION 'wf_invalid_input'; END IF;
 pay:=jsonb_build_object('u',p_delegate,'r',p_role,'e',p_effect,'s',p_site,'f',p_period_from,'t',p_period_to,'x',p_expires_at,'n',btrim(p_reason));
 SELECT * INTO b FROM wfi_begin(p_business,p_request,'a054_grant_delegation',pay);
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 c:=b.o_ctx; PERFORM wfi_need(wfi_is_owner(c),'a054_owner_required');
 IF p_delegate=c.user_id THEN RAISE EXCEPTION 'a054_self_delegation_denied'; END IF;
 IF NOT (EXISTS(SELECT 1 FROM business_members m WHERE m.user_id=p_delegate AND m.business_id=p_business AND m.active AND m.role IN('manager','business_owner'))
   OR EXISTS(SELECT 1 FROM wf_employees e WHERE e.user_id=p_delegate AND e.business_id=p_business AND e.status='active'))
 THEN RAISE EXCEPTION 'a054_delegate_not_eligible'; END IF;
 BEGIN
  INSERT INTO a054_delegations(tenant_id,business_id,delegate_uid,role,effect,site_id,period_from,period_to,expires_at,granted_by,reason,request_key)
  VALUES(c.tenant_id,p_business,p_delegate,p_role,p_effect,p_site,p_period_from,p_period_to,p_expires_at,c.user_id,btrim(p_reason),p_request) RETURNING id INTO v_id;
 EXCEPTION WHEN check_violation OR foreign_key_violation THEN RAISE EXCEPTION 'a054_invalid_delegation'; END;
 res:=jsonb_build_object('status','granted','delegation_id',v_id,'version',1,'effect',p_effect,'role',p_role);
 PERFORM wfi_log(c.tenant_id,p_business,'a054_delegation',v_id::text,'granted',NULL,res||jsonb_build_object('site',p_site,'period_from',p_period_from,
  'period_to',p_period_to,'expires_at',p_expires_at),p_reason,p_request);
 RETURN wfi_finish(p_business,c.tenant_id,p_request,'a054_grant_delegation',pay,res);
END$$;

CREATE FUNCTION c10_demo.a054_revoke_delegation_v1(p_business bigint,p_request text,p_delegation bigint,p_expected_version bigint,p_note text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c wf_ctx_t; pay jsonb; d a054_delegations; res jsonb;
BEGIN
 IF p_delegation IS NULL OR p_expected_version IS NULL OR p_note IS NULL OR length(btrim(p_note)) NOT BETWEEN 3 AND 500 THEN RAISE EXCEPTION 'wf_invalid_input'; END IF;
 pay:=jsonb_build_object('d',p_delegation,'v',p_expected_version,'n',btrim(p_note));
 SELECT * INTO b FROM wfi_begin(p_business,p_request,'a054_revoke_delegation',pay);
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 c:=b.o_ctx; PERFORM wfi_need(wfi_is_owner(c),'a054_owner_required');
 SELECT * INTO d FROM a054_delegations WHERE id=p_delegation AND business_id=p_business FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'a054_delegation_not_found'; END IF;
 IF d.revoked_at IS NOT NULL THEN RAISE EXCEPTION 'a054_already_revoked'; END IF;
 IF d.version<>p_expected_version THEN RAISE EXCEPTION 'wf_stale_version'; END IF;
 UPDATE a054_delegations SET revoked_at=clock_timestamp(),revoked_by=c.user_id,revoke_note=btrim(p_note),version=version+1 WHERE id=d.id;
 res:=jsonb_build_object('status','revoked','delegation_id',d.id,'version',d.version+1);
 PERFORM wfi_log(c.tenant_id,p_business,'a054_delegation',d.id::text,'revoked',jsonb_build_object('role',d.role,'effect',d.effect),res,p_note,p_request);
 RETURN wfi_finish(p_business,c.tenant_id,p_request,'a054_revoke_delegation',pay,res);
END$$;

CREATE FUNCTION c10_demo.a054_list_delegations_v1(p_business bigint) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE c wf_ctx_t;
BEGIN
 c:=wfi_ctx(p_business); PERFORM wfi_need(wfi_is_owner(c),'a054_owner_required');
 RETURN jsonb_build_object('server_authorized',true,'items',(SELECT COALESCE(jsonb_agg(jsonb_build_object('id',d.id,'delegate_ref',left(d.delegate_uid::text,8),
  'delegate_uid',d.delegate_uid,'role',d.role,'effect',d.effect,'site_id',d.site_id,'period_from',d.period_from,'period_to',d.period_to,
  'effective_from',d.effective_from,'expires_at',d.expires_at,'revoked_at',d.revoked_at,'version',d.version,'reason',d.reason,
  'state',CASE WHEN d.revoked_at IS NOT NULL THEN 'revoked' WHEN d.expires_at IS NOT NULL AND d.expires_at<=clock_timestamp() THEN 'expired'
    WHEN d.effective_from>clock_timestamp() THEN 'scheduled' ELSE 'active' END) ORDER BY d.id DESC),'[]')
  FROM a054_delegations d WHERE d.business_id=p_business));
END$$;
CREATE FUNCTION c10_demo.a054_eligible_delegates_v1(p_business bigint) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE c wf_ctx_t;
BEGIN
 c:=wfi_ctx(p_business); PERFORM wfi_need(wfi_is_owner(c),'a054_owner_required');
 RETURN jsonb_build_object('server_authorized',true,'items',(SELECT COALESCE(jsonb_agg(jsonb_build_object('uid',u,'ref',left(u::text,8),'source',s) ORDER BY s,u),'[]')
  FROM (SELECT m.user_id u,'member_'||m.role s FROM business_members m WHERE m.business_id=p_business AND m.active AND m.role IN('manager','business_owner') AND m.user_id<>c.user_id
   UNION SELECT e.user_id,'employee' FROM wf_employees e WHERE e.business_id=p_business AND e.status='active' AND e.user_id IS NOT NULL AND e.user_id<>c.user_id) x));
END$$;
CREATE FUNCTION c10_demo.a054_my_access_v1(p_business bigint) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE c wf_ctx_t; r text; roles jsonb:='[]';
BEGIN
 c:=wfi_ctx(p_business);
 FOREACH r IN ARRAY ARRAY['hr','payroll_preparer','payroll_reviewer','payroll_approver','payment_recorder'] LOOP
  IF a054i_deleg(p_business,r,NULL,NULL,'any')='allow' THEN roles:=roles||to_jsonb(r); END IF; END LOOP;
 RETURN jsonb_build_object('server_authorized',true,'level',wfi_level(c),'owner',wfi_is_owner(c),'delegated_roles',roles,
  'can_view_liability',wfi_is_owner(c) OR a054i_pay_access(p_business,'liability') OR a054i_deleg(p_business,'payment_recorder',NULL,NULL,'any')='allow');
END$$;

-- ===== Policy RPCs =====
CREATE FUNCTION c10_demo.a054_save_policy_v1(p_business bigint,p_request text,p_kind text,p_subject text,p_effective_from date,p_params jsonb,
 p_reason text,p_legal_ref text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c wf_ctx_t; pay jsonb; norm jsonb; v_ver int; v_id bigint; v_lock date; res jsonb; gated boolean;
BEGIN
 IF p_kind IS NULL OR p_kind NOT IN('overtime','pay_rule','leave') OR p_subject IS NULL OR p_effective_from IS NULL OR p_params IS NULL
  OR p_reason IS NULL OR length(btrim(p_reason)) NOT BETWEEN 3 AND 500 THEN RAISE EXCEPTION 'wf_invalid_input'; END IF;
 pay:=jsonb_build_object('k',p_kind,'s',p_subject,'f',p_effective_from,'p',p_params,'r',btrim(p_reason),'l',p_legal_ref);
 SELECT * INTO b FROM wfi_begin(p_business,p_request,'a054_save_policy',pay);
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 c:=b.o_ctx; PERFORM wfi_need(wfi_is_owner(c),'a054_owner_required');
 IF p_subject !~ '^[A-Za-z0-9][A-Za-z0-9_-]{0,23}$' THEN RAISE EXCEPTION 'wf_invalid_input'; END IF;
 IF p_kind='leave' AND NOT EXISTS(SELECT 1 FROM wf_leave_types WHERE business_id=p_business AND code=p_subject) THEN RAISE EXCEPTION 'a054_leave_type_not_found'; END IF;
 IF p_kind='pay_rule' AND EXISTS(SELECT 1 FROM wf_pay_components WHERE business_id=p_business AND code=p_subject) THEN RAISE EXCEPTION 'a054_rule_code_collision'; END IF;
 IF (p_kind='leave' AND (extract(day FROM p_effective_from)<>1 OR extract(month FROM p_effective_from)<>1))
  OR (p_kind<>'leave' AND extract(day FROM p_effective_from)<>1) THEN RAISE EXCEPTION 'a054_effective_date_boundary'; END IF;
 norm:=a054i_norm_policy(p_business,p_kind,p_subject,p_params);
 gated:=(p_kind='overtime' AND norm->>'mode'='off') OR (p_kind='pay_rule' AND (norm->>'statutory')::boolean);
 IF gated THEN
  PERFORM wfi_need(c.is_tenant_owner,'a054_legal_gate_tenant_owner_required');
  IF p_legal_ref IS NULL OR length(btrim(p_legal_ref))<8 THEN RAISE EXCEPTION 'a054_legal_gate_reference_required'; END IF;
 END IF;
 IF p_kind IN('overtime','pay_rule') THEN
  SELECT max(period_end) INTO v_lock FROM wf_payroll_runs WHERE business_id=p_business AND status IN('reviewed','approved','frozen','superseded');
  IF v_lock IS NOT NULL AND p_effective_from<=v_lock THEN RAISE EXCEPTION 'a054_effective_date_locked'; END IF;
 ELSIF EXISTS(SELECT 1 FROM wf_leave_requests r JOIN wf_leave_types t ON t.id=r.leave_type_id WHERE t.business_id=p_business AND t.code=p_subject
   AND r.status IN('pending','approved') AND r.to_date>=p_effective_from) THEN RAISE EXCEPTION 'a054_effective_date_locked'; END IF;
 SELECT COALESCE(max(version),0)+1 INTO v_ver FROM a054_policy_versions WHERE business_id=p_business AND kind=p_kind AND subject=p_subject;
 INSERT INTO a054_policy_versions(tenant_id,business_id,kind,subject,version,effective_from,params,reason,legal_ref,created_by,request_key)
 VALUES(c.tenant_id,p_business,p_kind,p_subject,v_ver,p_effective_from,norm,btrim(p_reason),NULLIF(btrim(COALESCE(p_legal_ref,'')),''),c.user_id,p_request) RETURNING id INTO v_id;
 res:=jsonb_build_object('status','saved','policy_id',v_id,'version',v_ver,'effective_from',p_effective_from,'params',norm,
  'state',CASE WHEN p_effective_from<=wfi_today() THEN 'effective' ELSE 'scheduled' END);
 PERFORM wfi_log(c.tenant_id,p_business,'a054_policy',v_id::text,'version_saved',NULL,res||jsonb_build_object('kind',p_kind,'subject',p_subject),p_reason,p_request);
 RETURN wfi_finish(p_business,c.tenant_id,p_request,'a054_save_policy',pay,res);
END$$;

CREATE FUNCTION c10_demo.a054_list_policies_v1(p_business bigint,p_kind text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE c wf_ctx_t; own boolean; today date:=wfi_today();
BEGIN
 c:=wfi_ctx(p_business); own:=wfi_is_owner(c);
 IF p_kind IS NULL OR p_kind NOT IN('overtime','pay_rule','leave') THEN RAISE EXCEPTION 'wf_invalid_input'; END IF;
 IF p_kind='leave' THEN PERFORM wfi_need(wfi_is_manager_plus(c),'a054_policy_view_denied');
 ELSE PERFORM wfi_need(own OR a054i_pay_access(p_business,'view'),'a054_policy_view_denied'); END IF;
 RETURN jsonb_build_object('server_authorized',true,'kind',p_kind,'items',(SELECT COALESCE(jsonb_agg(jsonb_build_object('id',v.id,'subject',v.subject,
  'version',v.version,'effective_from',v.effective_from,'params',v.params,'reason',v.reason,'legal_ref',CASE WHEN own THEN v.legal_ref END,
  'state',CASE WHEN v.effective_from>today THEN 'scheduled' WHEN v.id=(SELECT w.id FROM a054_policy_versions w WHERE w.business_id=v.business_id
     AND w.kind=v.kind AND w.subject=v.subject AND w.effective_from<=today ORDER BY w.effective_from DESC,w.version DESC LIMIT 1) THEN 'effective' ELSE 'superseded' END)
  ORDER BY v.subject,v.version DESC),'[]') FROM a054_policy_versions v WHERE v.business_id=p_business AND v.kind=p_kind));
END$$;

CREATE FUNCTION c10_demo.a054_leave_balance_v1(p_business bigint,p_employee bigint,p_year int) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE c wf_ctx_t; v_emp bigint; y int:=COALESCE(p_year,extract(year FROM wfi_today())::int); t record; s jsonb; items jsonb:='[]'; asof date; accr numeric; avail numeric;
BEGIN
 c:=wfi_ctx(p_business); v_emp:=COALESCE(p_employee,c.employee_id);
 IF y NOT BETWEEN 2000 AND 2100 THEN RAISE EXCEPTION 'wf_invalid_input'; END IF;
 IF v_emp IS NULL OR NOT wfi_can_see(c,v_emp) THEN RAISE EXCEPTION 'wf_employee_not_found'; END IF;
 asof:=LEAST(GREATEST(wfi_today(),make_date(y,1,1)),make_date(y,12,31));
 FOR t IN SELECT * FROM wf_leave_types WHERE business_id=p_business AND active ORDER BY code LOOP
  s:=a054i_year_sim(v_emp,t.id,y,'{}',NULL,0);
  accr:=CASE WHEN s->>'entitlement' IS NULL THEN NULL WHEN s->>'accrual'='monthly' THEN (s->>'entitlement')::numeric*extract(month FROM asof)/12 ELSE (s->>'entitlement')::numeric END;
  avail:=CASE WHEN accr IS NULL THEN NULL ELSE GREATEST(0,accr-(s->>'main_used')::numeric)
    +CASE WHEN s->>'carry_expiry_date' IS NULL OR asof<=(s->>'carry_expiry_date')::date THEN (s->>'carried_in')::numeric-(s->>'carry_used')::numeric ELSE 0 END END;
  items:=items||jsonb_build_array(s||jsonb_build_object('leave_type',t.code,'name',t.name,'paid',t.paid,'available_as_of_today',avail,'as_of',asof));
 END LOOP;
 RETURN jsonb_build_object('server_authorized',true,'employee_id',v_emp,'year',y,'items',items);
END$$;

-- ===== Legal holds & retention (raw punches only; payslips and audit are never purged) =====
CREATE FUNCTION c10_demo.a054_place_legal_hold_v1(p_business bigint,p_request text,p_employee bigint,p_from date,p_to date,p_reason text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c wf_ctx_t; pay jsonb; v_id bigint; res jsonb;
BEGIN
 IF p_from IS NULL OR p_to IS NULL OR p_to<p_from OR p_reason IS NULL OR length(btrim(p_reason)) NOT BETWEEN 5 AND 500 THEN RAISE EXCEPTION 'wf_invalid_input'; END IF;
 pay:=jsonb_build_object('e',p_employee,'f',p_from,'t',p_to,'r',btrim(p_reason));
 SELECT * INTO b FROM wfi_begin(p_business,p_request,'a054_place_hold',pay);
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 c:=b.o_ctx; PERFORM wfi_need(wfi_is_owner(c),'a054_owner_required');
 IF p_employee IS NOT NULL AND NOT EXISTS(SELECT 1 FROM wf_employees WHERE id=p_employee AND business_id=p_business) THEN RAISE EXCEPTION 'wf_employee_not_found'; END IF;
 INSERT INTO a054_legal_holds(tenant_id,business_id,employee_id,hold_from,hold_to,reason,placed_by,request_key)
 VALUES(c.tenant_id,p_business,p_employee,p_from,p_to,btrim(p_reason),c.user_id,p_request) RETURNING id INTO v_id;
 res:=jsonb_build_object('status','hold_placed','hold_id',v_id);
 PERFORM wfi_log(c.tenant_id,p_business,'a054_legal_hold',v_id::text,'placed',NULL,pay,p_reason,p_request);
 RETURN wfi_finish(p_business,c.tenant_id,p_request,'a054_place_hold',pay,res);
END$$;
CREATE FUNCTION c10_demo.a054_release_legal_hold_v1(p_business bigint,p_request text,p_hold bigint,p_note text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c wf_ctx_t; pay jsonb; h a054_legal_holds; res jsonb;
BEGIN
 IF p_hold IS NULL OR p_note IS NULL OR length(btrim(p_note)) NOT BETWEEN 3 AND 500 THEN RAISE EXCEPTION 'wf_invalid_input'; END IF;
 pay:=jsonb_build_object('h',p_hold,'n',btrim(p_note));
 SELECT * INTO b FROM wfi_begin(p_business,p_request,'a054_release_hold',pay);
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 c:=b.o_ctx; PERFORM wfi_need(c.is_tenant_owner,'wf_tenant_owner_required');
 SELECT * INTO h FROM a054_legal_holds WHERE id=p_hold AND business_id=p_business FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'a054_hold_not_found'; END IF;
 IF h.released_at IS NOT NULL THEN RAISE EXCEPTION 'a054_hold_already_released'; END IF;
 UPDATE a054_legal_holds SET released_at=clock_timestamp(),released_by=c.user_id,release_note=btrim(p_note) WHERE id=h.id;
 res:=jsonb_build_object('status','hold_released','hold_id',h.id);
 PERFORM wfi_log(c.tenant_id,p_business,'a054_legal_hold',h.id::text,'released',NULL,res,p_note,p_request);
 RETURN wfi_finish(p_business,c.tenant_id,p_request,'a054_release_hold',pay,res);
END$$;
CREATE FUNCTION c10_demo.a054_retention_report_v1(p_business bigint) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE c wf_ctx_t; cfg wf_business_settings; cut timestamptz; n_exp int; n_held int; n_lock int; n_ok int;
BEGIN
 c:=wfi_ctx(p_business); PERFORM wfi_need(wfi_is_owner(c),'a054_owner_required'); cfg:=wfi_cfg(p_business);
 cut:=now()-make_interval(months=>cfg.punch_retention_months);
 SELECT count(*) INTO n_exp FROM wf_punches p WHERE p.business_id=p_business AND p.punched_at<cut;
 SELECT count(*) INTO n_held FROM wf_punches p WHERE p.business_id=p_business AND p.punched_at<cut AND a054i_punch_held(p_business,p.employee_id,(p.punched_at AT TIME ZONE 'Asia/Dhaka')::date);
 SELECT count(*) INTO n_lock FROM wf_punches p WHERE p.business_id=p_business AND p.punched_at<cut
  AND NOT a054i_punch_held(p_business,p.employee_id,(p.punched_at AT TIME ZONE 'Asia/Dhaka')::date)
  AND (wfi_period_locked(p_business,(p.punched_at AT TIME ZONE 'Asia/Dhaka')::date) OR EXISTS(SELECT 1 FROM wf_payroll_runs r WHERE r.business_id=p_business
   AND r.status IN('frozen','superseded') AND (p.punched_at AT TIME ZONE 'Asia/Dhaka')::date BETWEEN r.period_start-1 AND r.period_end+1));
 n_ok:=n_exp-n_held-n_lock;
 RETURN jsonb_build_object('server_authorized',true,'dry_run',true,'scope','raw_punches_only','retention_months',cfg.punch_retention_months,'cutoff',cut,
  'expired_raw_punches',n_exp,'protected_by_legal_hold',n_held,'protected_by_payroll_period',n_lock,'purgeable_now',n_ok,
  'never_purged',jsonb_build_array('payslips','payroll_runs','audit','leave_records'),
  'active_holds',(SELECT COALESCE(jsonb_agg(jsonb_build_object('id',h.id,'employee_id',h.employee_id,'hold_from',h.hold_from,'hold_to',h.hold_to,'reason',h.reason)),'[]')
    FROM a054_legal_holds h WHERE h.business_id=p_business AND h.released_at IS NULL));
END$$;

-- ===== Approval vs payment: external payment RECORDS and liability =====
CREATE FUNCTION c10_demo.a054i_liability_lines(p_business bigint,p_period date) RETURNS TABLE(period_start date,run_id bigint,run_status text,
 employee_id bigint,employee_no text,site_id bigint,net numeric,paid numeric,outstanding numeric,state text) LANGUAGE sql STABLE AS $$
 WITH runs AS(SELECT DISTINCT ON (r.period_start) r.* FROM c10_demo.wf_payroll_runs r WHERE r.business_id=p_business AND r.status IN('frozen','approved')
   AND (p_period IS NULL OR r.period_start=p_period) ORDER BY r.period_start,CASE r.status WHEN 'frozen' THEN 0 ELSE 1 END),
 pay AS(SELECT x.period_start,x.employee_id,sum(CASE x.record_kind WHEN 'external_payment_record' THEN x.amount ELSE -x.amount END) paid
   FROM c10_demo.a054_payment_records x WHERE x.business_id=p_business GROUP BY 1,2)
 SELECT r.period_start,r.id,r.status,l.employee_id,l.employee_no,l.site_id,l.net,COALESCE(p.paid,0),GREATEST(l.net-COALESCE(p.paid,0),0),
  CASE WHEN l.net=0 THEN 'nothing_payable' WHEN COALESCE(p.paid,0)=0 THEN 'approved_unpaid' WHEN COALESCE(p.paid,0)<l.net THEN 'partially_paid_recorded'
   WHEN COALESCE(p.paid,0)=l.net THEN 'paid_recorded' ELSE 'overpaid_recorded' END
 FROM runs r JOIN c10_demo.wf_payroll_lines l ON l.run_id=r.id LEFT JOIN pay p ON p.period_start=r.period_start AND p.employee_id=l.employee_id $$;

CREATE FUNCTION c10_demo.a054_record_external_payment_v1(p_business bigint,p_request text,p_period date,p_employee bigint,p_amount numeric,
 p_method text,p_reference text,p_paid_on date,p_note text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c wf_ctx_t; cfg wf_business_settings; pay jsonb; l record; run wf_payroll_runs; v_id bigint; res jsonb;
BEGIN
 IF p_period IS NULL OR extract(day FROM p_period)<>1 OR p_employee IS NULL OR p_amount IS NULL OR p_amount<=0 OR scale(p_amount)>2
  OR p_method IS NULL OR p_reference IS NULL OR length(btrim(p_reference)) NOT BETWEEN 3 AND 80 OR p_paid_on IS NULL THEN RAISE EXCEPTION 'wf_invalid_input'; END IF;
 pay:=jsonb_build_object('p',p_period,'e',p_employee,'a',p_amount,'m',p_method,'r',btrim(p_reference),'d',p_paid_on,'n',p_note);
 SELECT * INTO b FROM wfi_begin(p_business,p_request,'a054_record_payment',pay);
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 c:=b.o_ctx; cfg:=wfi_cfg(p_business);
 IF NOT wfi_is_owner(c) THEN
  IF a054i_deleg(p_business,'payment_recorder',NULL,p_period,'exact')<>'allow' THEN RAISE EXCEPTION 'a054_delegation_denied'; END IF;
 END IF;
 IF p_paid_on>wfi_today() THEN RAISE EXCEPTION 'a054_payment_date_in_future'; END IF;
 SELECT * INTO l FROM a054i_liability_lines(p_business,p_period) WHERE employee_id=p_employee;
 IF NOT FOUND THEN RAISE EXCEPTION 'a054_no_approved_payable'; END IF;
 SELECT * INTO run FROM wf_payroll_runs WHERE id=l.run_id;
 IF NOT wfi_is_owner(c) AND cfg.require_maker_checker AND (run.approved_by=c.user_id OR run.prepared_by=c.user_id) THEN RAISE EXCEPTION 'wf_maker_checker_violation'; END IF;
 IF p_amount>l.outstanding THEN RAISE EXCEPTION 'a054_payment_exceeds_outstanding'; END IF;
 BEGIN
  INSERT INTO a054_payment_records(tenant_id,business_id,period_start,employee_id,run_id,record_kind,amount,method,external_reference,paid_on,note,recorded_by,request_key)
  VALUES(c.tenant_id,p_business,p_period,p_employee,l.run_id,'external_payment_record',p_amount,p_method,btrim(p_reference),p_paid_on,p_note,c.user_id,p_request) RETURNING id INTO v_id;
 EXCEPTION WHEN check_violation THEN RAISE EXCEPTION 'wf_invalid_input'; END;
 res:=jsonb_build_object('status','recorded','record_id',v_id,'record_kind','external_payment_record','payment_executed',false,'money_movement',false,
  'ledger_posted',false,'note','Records a payment made OUTSIDE this system. This module never pays salary.');
 PERFORM wfi_log(c.tenant_id,p_business,'a054_payment_record',v_id::text,'external_payment_recorded',NULL,
  jsonb_build_object('period',p_period,'employee',p_employee,'amount',p_amount,'method',p_method),p_note,p_request);
 RETURN wfi_finish(p_business,c.tenant_id,p_request,'a054_record_payment',pay,res);
END$$;

CREATE FUNCTION c10_demo.a054_reverse_payment_record_v1(p_business bigint,p_request text,p_record bigint,p_note text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c wf_ctx_t; pay jsonb; o a054_payment_records; v_id bigint; res jsonb;
BEGIN
 IF p_record IS NULL OR p_note IS NULL OR length(btrim(p_note)) NOT BETWEEN 5 AND 500 THEN RAISE EXCEPTION 'wf_invalid_input'; END IF;
 pay:=jsonb_build_object('x',p_record,'n',btrim(p_note));
 SELECT * INTO b FROM wfi_begin(p_business,p_request,'a054_reverse_payment',pay);
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 c:=b.o_ctx; PERFORM wfi_need(wfi_is_owner(c),'a054_owner_required');
 SELECT * INTO o FROM a054_payment_records WHERE id=p_record AND business_id=p_business AND record_kind='external_payment_record';
 IF NOT FOUND THEN RAISE EXCEPTION 'a054_record_not_found'; END IF;
 IF EXISTS(SELECT 1 FROM a054_payment_records WHERE reverses_id=o.id) THEN RAISE EXCEPTION 'a054_already_reversed'; END IF;
 INSERT INTO a054_payment_records(tenant_id,business_id,period_start,employee_id,run_id,record_kind,amount,method,external_reference,paid_on,note,reverses_id,recorded_by,request_key)
 VALUES(o.tenant_id,p_business,o.period_start,o.employee_id,o.run_id,'reversal',o.amount,o.method,o.external_reference,wfi_today(),btrim(p_note),o.id,c.user_id,p_request) RETURNING id INTO v_id;
 res:=jsonb_build_object('status','reversed','record_id',v_id,'reverses',o.id,'payment_executed',false,'money_movement',false);
 PERFORM wfi_log(c.tenant_id,p_business,'a054_payment_record',v_id::text,'reversal_recorded',NULL,res,p_note,p_request);
 RETURN wfi_finish(p_business,c.tenant_id,p_request,'a054_reverse_payment',pay,res);
END$$;

CREATE FUNCTION c10_demo.a054i_liability_access(c c10_demo.wf_ctx_t,p_business bigint) RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path=c10_demo,pg_catalog AS $$
BEGIN
 IF NOT (wfi_is_owner(c) OR a054i_pay_access(p_business,'liability')) THEN RAISE EXCEPTION 'a054_liability_denied'; END IF;
END$$;

CREATE FUNCTION c10_demo.a054_liability_report_v1(p_business bigint,p_period date) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE c wf_ctx_t; own boolean; pre jsonb;
BEGIN
 c:=wfi_ctx(p_business); PERFORM a054i_liability_access(c,p_business); own:=wfi_is_owner(c);
 IF p_period IS NOT NULL AND extract(day FROM p_period)<>1 THEN RAISE EXCEPTION 'wf_invalid_period'; END IF;
 SELECT jsonb_build_object('runs',count(*),'estimated_net',COALESCE(sum(total_net),0)) INTO pre FROM wf_payroll_runs
  WHERE business_id=p_business AND status IN('draft','reviewed') AND (p_period IS NULL OR period_start=p_period)
   AND (own OR a054i_period_visible(p_business,period_start) OR a054i_deleg(p_business,'payment_recorder',NULL,period_start,'exact')='allow');
 RETURN jsonb_build_object('server_authorized',true,'business_id',p_business,'period',p_period,
  'payment_executed',false,'paid',false,'money_movement',false,'ledger_posted',false,'bank_file',false,
  'labels',jsonb_build_object('pre_approval','Not yet approved: estimate only, not a liability','approved_unpaid','Approved by payroll, NO payment recorded',
   'paid_recorded','Payment made outside this system and recorded here; this system moved no money'),
  'pre_approval',pre,
  'totals',(SELECT jsonb_build_object('approved_net_total',COALESCE(sum(x.net),0),
    'approved_unpaid_amount',COALESCE(sum(x.outstanding) FILTER (WHERE x.state='approved_unpaid'),0),
    'approved_unpaid_count',count(*) FILTER (WHERE x.state='approved_unpaid'),
    'partially_paid_outstanding',COALESCE(sum(x.outstanding) FILTER (WHERE x.state='partially_paid_recorded'),0),
    'partially_paid_count',count(*) FILTER (WHERE x.state='partially_paid_recorded'),
    'paid_recorded_amount',COALESCE(sum(LEAST(x.paid,x.net)),0),'paid_recorded_count',count(*) FILTER (WHERE x.state='paid_recorded'),
    'overpaid_recorded_count',count(*) FILTER (WHERE x.state='overpaid_recorded'),
    'overpaid_recorded_excess',COALESCE(sum(GREATEST(x.paid-x.net,0)),0),'total_outstanding',COALESCE(sum(x.outstanding),0))
    FROM a054i_liability_lines(p_business,p_period) x
    WHERE own OR a054i_period_visible(p_business,x.period_start) OR a054i_deleg(p_business,'payment_recorder',NULL,x.period_start,'exact')='allow'),
  'by_site',(SELECT COALESCE(jsonb_agg(jsonb_build_object('site_id',s.site_id,'site_label',(SELECT label FROM sites WHERE id=s.site_id),'outstanding',s.o,'headcount',s.n) ORDER BY s.site_id),'[]')
    FROM (SELECT x.site_id,sum(x.outstanding) o,count(*) n FROM a054i_liability_lines(p_business,p_period) x
     WHERE (own OR a054i_period_visible(p_business,x.period_start) OR a054i_deleg(p_business,'payment_recorder',NULL,x.period_start,'exact')='allow') GROUP BY 1) s),
  'lines',CASE WHEN p_period IS NULL THEN '[]'::jsonb ELSE (SELECT COALESCE(jsonb_agg(jsonb_build_object('employee_id',x.employee_id,'employee_no',x.employee_no,
    'net',x.net,'recorded_paid',x.paid,'outstanding',x.outstanding,'state',x.state,'run_status',x.run_status) ORDER BY x.employee_no),'[]')
    FROM a054i_liability_lines(p_business,p_period) x) END);
END$$;

CREATE FUNCTION c10_demo.a054_export_liability_csv_v1(p_business bigint,p_request text,p_period date) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c wf_ctx_t; pay jsonb; out text:='period,employee_no,site,run_status,net,recorded_paid,outstanding,state'||E'\n'; x record; n int:=0; res jsonb;
BEGIN
 IF p_period IS NULL OR extract(day FROM p_period)<>1 THEN RAISE EXCEPTION 'wf_invalid_period'; END IF;
 pay:=jsonb_build_object('p',p_period);
 SELECT * INTO b FROM wfi_begin(p_business,p_request,'a054_export_liability',pay);
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 c:=b.o_ctx; PERFORM a054i_liability_access(c,p_business);
 IF NOT wfi_is_owner(c) AND NOT (a054i_period_visible(p_business,p_period) OR a054i_deleg(p_business,'payment_recorder',NULL,p_period,'exact')='allow')
  THEN RAISE EXCEPTION 'a054_liability_denied'; END IF;
 FOR x IN SELECT * FROM a054i_liability_lines(p_business,p_period) ORDER BY employee_no LOOP
  n:=n+1;
  out:=out||concat_ws(',',x.period_start,wfi_csv(x.employee_no),wfi_csv((SELECT label FROM sites WHERE id=x.site_id)),x.run_status,x.net,x.paid,x.outstanding,x.state)||E'\n';
 END LOOP;
 res:=jsonb_build_object('server_authorized',true,'kind','liability','rows',n,'filename','core10-workforce-liability.csv','pii_safe',true,
  'payment_executed',false,'csv',out);
 PERFORM wfi_log(c.tenant_id,p_business,'export','a054_liability','csv_exported',NULL,jsonb_build_object('rows',n,'period',p_period),NULL,p_request);
 RETURN wfi_finish(p_business,c.tenant_id,p_request,'a054_export_liability',pay,res);
END$$;

-- ===== Lock-down =====
DO $$
DECLARE t record; f record;
BEGIN
 FOR t IN SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='c10_demo' AND c.relkind='r' AND c.relname LIKE 'a054\_%' LOOP
  EXECUTE format('ALTER TABLE c10_demo.%I ENABLE ROW LEVEL SECURITY',t.relname);
  EXECUTE format('REVOKE ALL ON c10_demo.%I FROM PUBLIC,anon,authenticated',t.relname);
 END LOOP;
 FOR f IN SELECT p.oid::regprocedure AS sig,p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='c10_demo' AND p.proname LIKE 'a054%' LOOP
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated',f.sig);
  IF f.proname ~ '^a054_.*_v1$' THEN EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated',f.sig); END IF;
 END LOOP;
END$$;
