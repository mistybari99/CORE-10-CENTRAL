-- C10-A051 Workforce core (1/3): settings, employees, assignments, shifts, holidays, audit.
-- DISPOSABLE c10_demo ONLY. Apply AFTER A018. NEVER apply to production IMG-ERP-SG.
-- Reuses A018 tenants/businesses/sites + can_tenant/can_manage/can_business. NO new login,
-- NO duplicate site_grants, NO finance/stock ledger. All tables: RLS on, zero direct grants;
-- every read/write goes through guarded SECURITY DEFINER RPCs (public API: wf_*_v1).
-- Internal helpers are wfi_* and are NOT executable by authenticated/anon.
CREATE TABLE c10_demo.wf_business_settings(
 business_id bigint PRIMARY KEY,
 tenant_id bigint NOT NULL,
 timezone text NOT NULL DEFAULT 'Asia/Dhaka' CHECK(timezone='Asia/Dhaka'),
 weekly_off_days smallint[] NOT NULL DEFAULT ARRAY[5]::smallint[]
  CHECK(weekly_off_days <@ ARRAY[1,2,3,4,5,6,7]::smallint[] AND array_length(weekly_off_days,1)<=6),
 duplicate_window_seconds int NOT NULL DEFAULT 120 CHECK(duplicate_window_seconds BETWEEN 0 AND 3600),
 overtime_requires_approval boolean NOT NULL DEFAULT true,
 max_overtime_minutes_per_day int NOT NULL DEFAULT 240 CHECK(max_overtime_minutes_per_day BETWEEN 0 AND 720),
 off_day_work_as_overtime boolean NOT NULL DEFAULT true,
 half_day_ratio numeric(3,2) NOT NULL DEFAULT 0.50 CHECK(half_day_ratio BETWEEN 0.10 AND 0.90),
 manager_can_approve_corrections boolean NOT NULL DEFAULT false,
 manager_can_edit_employees boolean NOT NULL DEFAULT false,
 leave_review_level text NOT NULL DEFAULT 'manager' CHECK(leave_review_level IN('manager','owner')),
 require_maker_checker boolean NOT NULL DEFAULT true,
 punch_retention_months int NOT NULL DEFAULT 36 CHECK(punch_retention_months BETWEEN 12 AND 120),
 version bigint NOT NULL DEFAULT 1,
 updated_by uuid, updated_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(business_id,tenant_id) REFERENCES c10_demo.businesses(id,tenant_id)
);
CREATE TABLE c10_demo.wf_departments(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL, business_id bigint NOT NULL,
 code text NOT NULL CHECK(code ~ '^[A-Za-z0-9][A-Za-z0-9_-]{0,23}$'),
 name text NOT NULL CHECK(length(btrim(name)) BETWEEN 2 AND 80),
 active boolean NOT NULL DEFAULT true,
 version bigint NOT NULL DEFAULT 1,
 UNIQUE(business_id,code), UNIQUE(id,tenant_id,business_id),
 FOREIGN KEY(business_id,tenant_id) REFERENCES c10_demo.businesses(id,tenant_id)
);
CREATE TABLE c10_demo.wf_employees(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL, business_id bigint NOT NULL,
 employee_no text NOT NULL CHECK(employee_no ~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,31}$'),
 full_name text NOT NULL CHECK(length(btrim(full_name)) BETWEEN 2 AND 120),
 contact_phone text CHECK(contact_phone ~ '^[0-9+() -]{6,20}$'),
 national_id_last4 text CHECK(national_id_last4 ~ '^[0-9]{4}$'),
 user_id uuid,
 joined_on date NOT NULL,
 status text NOT NULL CHECK(status IN('active','inactive','terminated')),
 contract_type text NOT NULL CHECK(contract_type IN('permanent','contract','probation','daily','hourly','intern')),
 version bigint NOT NULL DEFAULT 1,
 created_by uuid NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(business_id,employee_no), UNIQUE(id,tenant_id,business_id),
 FOREIGN KEY(business_id,tenant_id) REFERENCES c10_demo.businesses(id,tenant_id)
);
CREATE UNIQUE INDEX wf_employees_user_uq ON c10_demo.wf_employees(business_id,user_id) WHERE user_id IS NOT NULL;
CREATE INDEX wf_employees_user_ix ON c10_demo.wf_employees(user_id) WHERE user_id IS NOT NULL;
-- Append-only effective-dated facts: the state on date D is the row with greatest effective_from<=D (ties: highest id).
CREATE TABLE c10_demo.wf_employment_history(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL, business_id bigint NOT NULL, employee_id bigint NOT NULL,
 effective_from date NOT NULL,
 status text NOT NULL CHECK(status IN('active','inactive','terminated')),
 contract_type text NOT NULL CHECK(contract_type IN('permanent','contract','probation','daily','hourly','intern')),
 reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 3 AND 500),
 changed_by uuid NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(employee_id,tenant_id,business_id) REFERENCES c10_demo.wf_employees(id,tenant_id,business_id)
);
CREATE INDEX wf_hist_emp_ix ON c10_demo.wf_employment_history(employee_id,effective_from DESC,id DESC);
CREATE TABLE c10_demo.wf_assignments(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL, business_id bigint NOT NULL, employee_id bigint NOT NULL,
 effective_from date NOT NULL,
 site_id bigint NOT NULL, department_id bigint,
 designation text CHECK(designation IS NULL OR length(btrim(designation)) BETWEEN 2 AND 80),
 is_supervisor boolean NOT NULL DEFAULT false,
 reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 3 AND 500),
 changed_by uuid NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(employee_id,tenant_id,business_id) REFERENCES c10_demo.wf_employees(id,tenant_id,business_id),
 FOREIGN KEY(site_id,tenant_id,business_id) REFERENCES c10_demo.sites(id,tenant_id,business_id),
 FOREIGN KEY(department_id,tenant_id,business_id) REFERENCES c10_demo.wf_departments(id,tenant_id,business_id)
);
CREATE INDEX wf_assign_emp_ix ON c10_demo.wf_assignments(employee_id,effective_from DESC,id DESC);
CREATE INDEX wf_assign_site_ix ON c10_demo.wf_assignments(site_id);
CREATE TABLE c10_demo.wf_shifts(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL, business_id bigint NOT NULL,
 code text NOT NULL CHECK(code ~ '^[A-Za-z0-9][A-Za-z0-9_-]{0,23}$'),
 name text NOT NULL CHECK(length(btrim(name)) BETWEEN 2 AND 80),
 start_time time NOT NULL, end_time time NOT NULL CHECK(end_time<>start_time),
 break_minutes int NOT NULL DEFAULT 0 CHECK(break_minutes BETWEEN 0 AND 480),
 grace_late_minutes int NOT NULL DEFAULT 10 CHECK(grace_late_minutes BETWEEN 0 AND 120),
 grace_early_minutes int NOT NULL DEFAULT 0 CHECK(grace_early_minutes BETWEEN 0 AND 120),
 min_overtime_minutes int NOT NULL DEFAULT 30 CHECK(min_overtime_minutes BETWEEN 0 AND 240),
 weekly_off_days smallint[] CHECK(weekly_off_days IS NULL OR weekly_off_days <@ ARRAY[1,2,3,4,5,6,7]::smallint[]),
 active boolean NOT NULL DEFAULT true,
 version bigint NOT NULL DEFAULT 1,
 UNIQUE(business_id,code), UNIQUE(id,tenant_id,business_id),
 FOREIGN KEY(business_id,tenant_id) REFERENCES c10_demo.businesses(id,tenant_id)
);
CREATE TABLE c10_demo.wf_shift_assignments(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL, business_id bigint NOT NULL, employee_id bigint NOT NULL,
 shift_id bigint NOT NULL, effective_from date NOT NULL,
 reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 3 AND 500),
 changed_by uuid NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(employee_id,tenant_id,business_id) REFERENCES c10_demo.wf_employees(id,tenant_id,business_id),
 FOREIGN KEY(shift_id,tenant_id,business_id) REFERENCES c10_demo.wf_shifts(id,tenant_id,business_id)
);
CREATE INDEX wf_shiftas_emp_ix ON c10_demo.wf_shift_assignments(employee_id,effective_from DESC,id DESC);
CREATE TABLE c10_demo.wf_holidays(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL, business_id bigint NOT NULL,
 holiday_date date NOT NULL,
 name text NOT NULL CHECK(length(btrim(name)) BETWEEN 2 AND 80),
 kind text NOT NULL DEFAULT 'public' CHECK(kind IN('public','company')),
 paid boolean NOT NULL DEFAULT true,
 site_id bigint, active boolean NOT NULL DEFAULT true,
 version bigint NOT NULL DEFAULT 1,
 FOREIGN KEY(business_id,tenant_id) REFERENCES c10_demo.businesses(id,tenant_id),
 FOREIGN KEY(site_id,tenant_id,business_id) REFERENCES c10_demo.sites(id,tenant_id,business_id)
);
CREATE UNIQUE INDEX wf_holidays_uq ON c10_demo.wf_holidays(business_id,holiday_date,COALESCE(site_id,0));
CREATE TABLE c10_demo.wf_receipts(
 tenant_id bigint NOT NULL, business_id bigint NOT NULL,
 request_key text NOT NULL CHECK(request_key ~ '^[A-Za-z0-9_-]{8,100}$'),
 actor_uid uuid NOT NULL, op text NOT NULL, payload jsonb NOT NULL, result jsonb NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(business_id,request_key),
 FOREIGN KEY(business_id,tenant_id) REFERENCES c10_demo.businesses(id,tenant_id)
);
-- Append-only hash-chained audit stream (per business). Never mutated, even by definer RPCs.
CREATE TABLE c10_demo.wf_audit(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL, business_id bigint NOT NULL,
 entity text NOT NULL, entity_id text NOT NULL, event text NOT NULL,
 before_state jsonb, after_state jsonb, reason text,
 actor_uid uuid NOT NULL, request_key text NOT NULL,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 prev_hash text, row_hash text NOT NULL,
 FOREIGN KEY(business_id,tenant_id) REFERENCES c10_demo.businesses(id,tenant_id)
);
CREATE INDEX wf_audit_biz_ix ON c10_demo.wf_audit(business_id,id);
CREATE FUNCTION c10_demo.wfi_audit_hash(p_prev text,r c10_demo.wf_audit) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
 SELECT encode(sha256(convert_to(concat_ws('|',COALESCE(p_prev,'GENESIS'),r.tenant_id,r.business_id,
  r.entity,r.entity_id,r.event,COALESCE(r.before_state::text,''),COALESCE(r.after_state::text,''),
  COALESCE(r.reason,''),r.actor_uid,r.request_key,r.created_at::text),'UTF8')),'hex') $$;
CREATE FUNCTION c10_demo.wfi_audit_chain() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 SELECT row_hash INTO NEW.prev_hash FROM c10_demo.wf_audit WHERE business_id=NEW.business_id ORDER BY id DESC LIMIT 1;
 NEW.row_hash:=c10_demo.wfi_audit_hash(NEW.prev_hash,NEW);
 RETURN NEW;
END$$;
CREATE TRIGGER wf_audit_chain BEFORE INSERT ON c10_demo.wf_audit FOR EACH ROW EXECUTE FUNCTION c10_demo.wfi_audit_chain();
CREATE FUNCTION c10_demo.wfi_immutable() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'wf_append_only_record'; END$$;
CREATE TRIGGER wf_audit_no_row_mutation BEFORE UPDATE OR DELETE ON c10_demo.wf_audit FOR EACH ROW EXECUTE FUNCTION c10_demo.wfi_immutable();
CREATE TRIGGER wf_audit_no_truncate BEFORE TRUNCATE ON c10_demo.wf_audit FOR EACH STATEMENT EXECUTE FUNCTION c10_demo.wfi_immutable();
CREATE TRIGGER wf_hist_no_mutation BEFORE UPDATE OR DELETE ON c10_demo.wf_employment_history FOR EACH ROW EXECUTE FUNCTION c10_demo.wfi_immutable();
CREATE TRIGGER wf_assign_no_mutation BEFORE UPDATE OR DELETE ON c10_demo.wf_assignments FOR EACH ROW EXECUTE FUNCTION c10_demo.wfi_immutable();
CREATE TRIGGER wf_shiftas_no_mutation BEFORE UPDATE OR DELETE ON c10_demo.wf_shift_assignments FOR EACH ROW EXECUTE FUNCTION c10_demo.wfi_immutable();
CREATE TRIGGER wf_receipts_no_mutation BEFORE UPDATE OR DELETE ON c10_demo.wf_receipts FOR EACH ROW EXECUTE FUNCTION c10_demo.wfi_immutable();

CREATE TYPE c10_demo.wf_ctx_t AS(
 tenant_id bigint, user_id uuid, is_tenant_owner boolean, is_business_owner boolean,
 is_manager boolean, employee_id bigint, supervised_sites bigint[]);

CREATE FUNCTION c10_demo.wfi_today() RETURNS date LANGUAGE sql STABLE AS
$$ SELECT (now() AT TIME ZONE 'Asia/Dhaka')::date $$;
CREATE FUNCTION c10_demo.wfi_ts(p_date date,p_time time) RETURNS timestamptz LANGUAGE sql IMMUTABLE AS
$$ SELECT (p_date+p_time) AT TIME ZONE 'Asia/Dhaka' $$;
CREATE FUNCTION c10_demo.wfi_mask_name(p text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
 SELECT CASE WHEN position(' ' IN btrim(p))=0 THEN btrim(p)
  ELSE split_part(btrim(p),' ',1)||' '||left(regexp_replace(btrim(p),'^\S+\s+',''),1)||'.' END $$;

-- Server-derived authority. Stock grants/site_grants alone NEVER grant any workforce access.
CREATE FUNCTION c10_demo.wfi_ctx(p_business bigint) RETURNS c10_demo.wf_ctx_t
LANGUAGE plpgsql AS $$
DECLARE c c10_demo.wf_ctx_t; uid uuid:=c10_demo.actor_uid(); a record;
BEGIN
 IF uid IS NULL OR p_business IS NULL THEN RAISE EXCEPTION 'wf_denied'; END IF;
 SELECT tenant_id INTO c.tenant_id FROM c10_demo.businesses WHERE id=p_business;
 IF c.tenant_id IS NULL THEN RAISE EXCEPTION 'wf_denied'; END IF;
 c.user_id:=uid;
 c.is_tenant_owner:=c10_demo.can_tenant(c.tenant_id);
 c.is_business_owner:=EXISTS(SELECT 1 FROM c10_demo.business_members m WHERE m.user_id=uid
   AND m.tenant_id=c.tenant_id AND m.business_id=p_business AND m.active AND m.role='business_owner');
 c.is_manager:=EXISTS(SELECT 1 FROM c10_demo.business_members m WHERE m.user_id=uid
   AND m.tenant_id=c.tenant_id AND m.business_id=p_business AND m.active AND m.role='manager');
 SELECT id INTO c.employee_id FROM c10_demo.wf_employees
  WHERE business_id=p_business AND user_id=uid AND status='active';
 c.supervised_sites:='{}';
 IF c.employee_id IS NOT NULL THEN
  SELECT * INTO a FROM c10_demo.wf_assignments WHERE employee_id=c.employee_id AND effective_from<=c10_demo.wfi_today()
   ORDER BY effective_from DESC,id DESC LIMIT 1;
  IF FOUND AND a.is_supervisor THEN c.supervised_sites:=ARRAY[a.site_id]; END IF;
 END IF;
 IF NOT (c.is_tenant_owner OR c.is_business_owner OR c.is_manager OR c.employee_id IS NOT NULL) THEN
  RAISE EXCEPTION 'wf_denied'; END IF;
 RETURN c;
END$$;
CREATE FUNCTION c10_demo.wfi_is_owner(c c10_demo.wf_ctx_t) RETURNS boolean LANGUAGE sql IMMUTABLE AS
$$ SELECT c.is_tenant_owner OR c.is_business_owner $$;
CREATE FUNCTION c10_demo.wfi_is_manager_plus(c c10_demo.wf_ctx_t) RETURNS boolean LANGUAGE sql IMMUTABLE AS
$$ SELECT c.is_tenant_owner OR c.is_business_owner OR c.is_manager $$;
CREATE FUNCTION c10_demo.wfi_site_of(p_employee bigint,p_date date) RETURNS bigint LANGUAGE sql STABLE AS
$$ SELECT site_id FROM c10_demo.wf_assignments WHERE employee_id=p_employee AND effective_from<=p_date
   ORDER BY effective_from DESC,id DESC LIMIT 1 $$;
-- Visibility: owner/manager = whole business; supervisor = employees on supervised site; employee = self.
CREATE FUNCTION c10_demo.wfi_can_see(c c10_demo.wf_ctx_t,p_employee bigint) RETURNS boolean
LANGUAGE plpgsql STABLE AS $$
BEGIN
 IF c10_demo.wfi_is_manager_plus(c) THEN RETURN true; END IF;
 IF c.employee_id IS NOT NULL AND c.employee_id=p_employee THEN RETURN true; END IF;
 RETURN c10_demo.wfi_site_of(p_employee,c10_demo.wfi_today())=ANY(c.supervised_sites);
END$$;
CREATE FUNCTION c10_demo.wfi_cfg(p_business bigint) RETURNS c10_demo.wf_business_settings
LANGUAGE plpgsql AS $$
DECLARE s c10_demo.wf_business_settings;
BEGIN
 INSERT INTO c10_demo.wf_business_settings(business_id,tenant_id)
  SELECT id,tenant_id FROM c10_demo.businesses WHERE id=p_business ON CONFLICT DO NOTHING;
 SELECT * INTO s FROM c10_demo.wf_business_settings WHERE business_id=p_business;
 RETURN s;
END$$;
CREATE FUNCTION c10_demo.wfi_status_on(p_employee bigint,p_date date) RETURNS text LANGUAGE sql STABLE AS
$$ SELECT status FROM c10_demo.wf_employment_history WHERE employee_id=p_employee AND effective_from<=p_date
   ORDER BY effective_from DESC,id DESC LIMIT 1 $$;
CREATE FUNCTION c10_demo.wfi_contract_on(p_employee bigint,p_date date) RETURNS text LANGUAGE sql STABLE AS
$$ SELECT contract_type FROM c10_demo.wf_employment_history WHERE employee_id=p_employee AND effective_from<=p_date
   ORDER BY effective_from DESC,id DESC LIMIT 1 $$;
CREATE FUNCTION c10_demo.wfi_log(p_tenant bigint,p_business bigint,p_entity text,p_entity_id text,
 p_event text,p_before jsonb,p_after jsonb,p_reason text,p_request text) RETURNS void LANGUAGE sql AS
$$ INSERT INTO c10_demo.wf_audit(tenant_id,business_id,entity,entity_id,event,before_state,after_state,reason,actor_uid,request_key)
   VALUES(p_tenant,p_business,p_entity,p_entity_id,p_event,p_before,p_after,p_reason,c10_demo.actor_uid(),p_request) $$;

-- Write envelope: validates key, serialises per business, resolves authority, replays idempotently.
CREATE FUNCTION c10_demo.wfi_begin(p_business bigint,p_request text,p_op text,p_payload jsonb,
 OUT o_ctx c10_demo.wf_ctx_t,OUT o_replay jsonb) LANGUAGE plpgsql AS $$
DECLARE r c10_demo.wf_receipts;
BEGIN
 IF p_request IS NULL OR p_request !~ '^[A-Za-z0-9_-]{8,100}$' THEN RAISE EXCEPTION 'wf_invalid_request_key'; END IF;
 IF c10_demo.actor_uid() IS NULL THEN RAISE EXCEPTION 'wf_denied'; END IF;
 PERFORM 1 FROM c10_demo.businesses WHERE id=p_business FOR NO KEY UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'wf_denied'; END IF;
 o_ctx:=c10_demo.wfi_ctx(p_business);
 PERFORM c10_demo.wfi_cfg(p_business);
 SELECT * INTO r FROM c10_demo.wf_receipts WHERE business_id=p_business AND request_key=p_request;
 IF FOUND THEN
  IF r.actor_uid<>c10_demo.actor_uid() OR r.op<>p_op OR r.payload<>p_payload THEN
   RAISE EXCEPTION 'wf_idempotency_conflict'; END IF;
  o_replay:=r.result;
 END IF;
END$$;
CREATE FUNCTION c10_demo.wfi_finish(p_business bigint,p_tenant bigint,p_request text,p_op text,
 p_payload jsonb,p_result jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
BEGIN
 INSERT INTO c10_demo.wf_receipts(tenant_id,business_id,request_key,actor_uid,op,payload,result)
 VALUES(p_tenant,p_business,p_request,c10_demo.actor_uid(),p_op,p_payload,p_result);
 RETURN p_result;
END$$;
CREATE FUNCTION c10_demo.wfi_need(p_ok boolean,p_code text) RETURNS void LANGUAGE plpgsql IMMUTABLE AS
$$ BEGIN IF p_ok IS NOT TRUE THEN RAISE EXCEPTION '%',p_code; END IF; END$$;
-- A period is locked while a run is reviewed/approved, or frozen with no open amendment draft.
-- Changes to a frozen period therefore require an explicit, audited amendment draft (never silent).
CREATE FUNCTION c10_demo.wfi_range_locked(p_business bigint,p_from date,p_to date) RETURNS boolean LANGUAGE plpgsql STABLE AS
$$ BEGIN
 RETURN EXISTS(SELECT 1 FROM c10_demo.wf_payroll_runs r WHERE r.business_id=p_business
   AND r.period_start<=p_to AND r.period_end>=p_from AND (r.status IN('reviewed','approved')
   OR (r.status='frozen' AND NOT EXISTS(SELECT 1 FROM c10_demo.wf_payroll_runs a WHERE a.business_id=p_business
      AND a.period_start=r.period_start AND a.status='draft' AND a.amends_run_id IS NOT NULL))));
END$$;
CREATE FUNCTION c10_demo.wfi_period_locked(p_business bigint,p_date date) RETURNS boolean LANGUAGE sql STABLE AS
$$ SELECT c10_demo.wfi_range_locked(p_business,p_date,p_date) $$;

-- ===== Settings / departments / employees =====
CREATE FUNCTION c10_demo.wf_save_settings_v1(p_business bigint,p_request text,p_expected_version bigint,
 p_changes jsonb,p_reason text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c wf_ctx_t; s wf_business_settings; k text; pay jsonb; res jsonb;
 allowed text[]:=ARRAY['weekly_off_days','duplicate_window_seconds','overtime_requires_approval',
  'max_overtime_minutes_per_day','off_day_work_as_overtime','half_day_ratio','manager_can_approve_corrections',
  'manager_can_edit_employees','leave_review_level','require_maker_checker','punch_retention_months'];
BEGIN
 IF p_changes IS NULL OR jsonb_typeof(p_changes)<>'object' OR p_reason IS NULL OR length(btrim(p_reason)) NOT BETWEEN 5 AND 500
  OR p_expected_version IS NULL THEN RAISE EXCEPTION 'wf_invalid_input'; END IF;
 pay:=jsonb_build_object('v',p_expected_version,'c',p_changes,'r',btrim(p_reason));
 SELECT * INTO b FROM wfi_begin(p_business,p_request,'save_settings',pay);
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 c:=b.o_ctx; PERFORM wfi_need(wfi_is_owner(c),'wf_owner_required');
 FOR k IN SELECT jsonb_object_keys(p_changes) LOOP
  IF NOT k=ANY(allowed) THEN RAISE EXCEPTION 'wf_unknown_setting'; END IF; END LOOP;
 s:=wfi_cfg(p_business);
 IF s.version<>p_expected_version THEN RAISE EXCEPTION 'wf_stale_version'; END IF;
 -- Loosening maker-checker is a tenant-owner-only decision (safe default stays ON).
 IF p_changes ? 'require_maker_checker' AND (p_changes->>'require_maker_checker')::boolean=false
  AND NOT c.is_tenant_owner THEN RAISE EXCEPTION 'wf_tenant_owner_required'; END IF;
 BEGIN
  UPDATE wf_business_settings SET
   weekly_off_days=COALESCE((SELECT array_agg(x::smallint) FROM jsonb_array_elements_text(p_changes->'weekly_off_days') x),weekly_off_days),
   duplicate_window_seconds=COALESCE((p_changes->>'duplicate_window_seconds')::int,duplicate_window_seconds),
   overtime_requires_approval=COALESCE((p_changes->>'overtime_requires_approval')::boolean,overtime_requires_approval),
   max_overtime_minutes_per_day=COALESCE((p_changes->>'max_overtime_minutes_per_day')::int,max_overtime_minutes_per_day),
   off_day_work_as_overtime=COALESCE((p_changes->>'off_day_work_as_overtime')::boolean,off_day_work_as_overtime),
   half_day_ratio=COALESCE((p_changes->>'half_day_ratio')::numeric,half_day_ratio),
   manager_can_approve_corrections=COALESCE((p_changes->>'manager_can_approve_corrections')::boolean,manager_can_approve_corrections),
   manager_can_edit_employees=COALESCE((p_changes->>'manager_can_edit_employees')::boolean,manager_can_edit_employees),
   leave_review_level=COALESCE(p_changes->>'leave_review_level',leave_review_level),
   require_maker_checker=COALESCE((p_changes->>'require_maker_checker')::boolean,require_maker_checker),
   punch_retention_months=COALESCE((p_changes->>'punch_retention_months')::int,punch_retention_months),
   version=version+1,updated_by=c.user_id,updated_at=now()
  WHERE business_id=p_business;
 EXCEPTION WHEN check_violation OR invalid_text_representation OR numeric_value_out_of_range OR invalid_parameter_value THEN
  RAISE EXCEPTION 'wf_invalid_setting_value'; END;
 res:=jsonb_build_object('status','applied','version',p_expected_version+1);
 PERFORM wfi_log(c.tenant_id,p_business,'settings',p_business::text,'updated',to_jsonb(s),p_changes,p_reason,p_request);
 RETURN wfi_finish(p_business,c.tenant_id,p_request,'save_settings',pay,res);
END$$;

CREATE FUNCTION c10_demo.wf_save_department_v1(p_business bigint,p_request text,p_code text,p_name text,
 p_active boolean,p_reason text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c wf_ctx_t; pay jsonb; v_id bigint; res jsonb;
BEGIN
 IF p_code IS NULL OR p_name IS NULL OR p_active IS NULL OR p_reason IS NULL OR length(btrim(p_reason)) NOT BETWEEN 3 AND 500
 THEN RAISE EXCEPTION 'wf_invalid_input'; END IF;
 pay:=jsonb_build_object('code',p_code,'name',btrim(p_name),'active',p_active,'r',btrim(p_reason));
 SELECT * INTO b FROM wfi_begin(p_business,p_request,'save_department',pay);
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 c:=b.o_ctx; PERFORM wfi_need(wfi_is_owner(c),'wf_owner_required');
 BEGIN
  INSERT INTO wf_departments(tenant_id,business_id,code,name,active) VALUES(c.tenant_id,p_business,p_code,btrim(p_name),p_active)
  ON CONFLICT(business_id,code) DO UPDATE SET name=excluded.name,active=excluded.active,version=wf_departments.version+1
  RETURNING id INTO v_id;
 EXCEPTION WHEN check_violation THEN RAISE EXCEPTION 'wf_invalid_input'; END;
 res:=jsonb_build_object('status','applied','department_id',v_id);
 PERFORM wfi_log(c.tenant_id,p_business,'department',v_id::text,'saved',NULL,pay,p_reason,p_request);
 RETURN wfi_finish(p_business,c.tenant_id,p_request,'save_department',pay,res);
END$$;

-- Create (p_employee_id NULL) or update master data. Employee number is immutable.
CREATE FUNCTION c10_demo.wf_save_employee_v1(p_business bigint,p_request text,p_employee_id bigint,
 p_expected_version bigint,p_data jsonb,p_reason text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c wf_ctx_t; cfg wf_business_settings; pay jsonb; e wf_employees; v_id bigint; res jsonb;
 v_site bigint; v_dept bigint; v_join date; v_contract text; v_name text; v_super boolean;
BEGIN
 IF p_data IS NULL OR jsonb_typeof(p_data)<>'object' OR p_reason IS NULL OR length(btrim(p_reason)) NOT BETWEEN 3 AND 500
 THEN RAISE EXCEPTION 'wf_invalid_input'; END IF;
 pay:=jsonb_build_object('id',p_employee_id,'v',p_expected_version,'d',p_data,'r',btrim(p_reason));
 SELECT * INTO b FROM wfi_begin(p_business,p_request,'save_employee',pay);
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 c:=b.o_ctx; cfg:=wfi_cfg(p_business);
 PERFORM wfi_need(wfi_is_owner(c) OR (c.is_manager AND cfg.manager_can_edit_employees),'wf_employee_edit_denied');
 -- Login-link and supervisor flag are privilege-bearing: owners only.
 IF (p_data ? 'user_id' OR p_data ? 'is_supervisor') AND NOT wfi_is_owner(c) THEN RAISE EXCEPTION 'wf_owner_required'; END IF;
 BEGIN
  IF p_employee_id IS NULL THEN
   v_join:=(p_data->>'joined_on')::date; v_contract:=p_data->>'contract_type'; v_name:=btrim(p_data->>'full_name');
   v_site:=(p_data->>'site_id')::bigint;
   IF v_join IS NULL OR v_contract IS NULL OR v_name IS NULL OR v_site IS NULL OR v_join>wfi_today()
    OR v_join<DATE '2000-01-01' THEN RAISE EXCEPTION 'wf_invalid_input'; END IF;
   IF NOT EXISTS(SELECT 1 FROM sites WHERE id=v_site AND business_id=p_business) THEN RAISE EXCEPTION 'wf_site_not_in_business'; END IF;
   IF p_data ? 'department_code' THEN
    SELECT id INTO v_dept FROM wf_departments WHERE business_id=p_business AND code=p_data->>'department_code' AND active;
    IF v_dept IS NULL THEN RAISE EXCEPTION 'wf_department_not_found'; END IF; END IF;
   INSERT INTO wf_employees(tenant_id,business_id,employee_no,full_name,contact_phone,national_id_last4,user_id,joined_on,status,contract_type,created_by)
   VALUES(c.tenant_id,p_business,p_data->>'employee_no',v_name,p_data->>'contact_phone',p_data->>'national_id_last4',
    (p_data->>'user_id')::uuid,v_join,'active',v_contract,c.user_id) RETURNING id INTO v_id;
   INSERT INTO wf_employment_history(tenant_id,business_id,employee_id,effective_from,status,contract_type,reason,changed_by)
   VALUES(c.tenant_id,p_business,v_id,v_join,'active',v_contract,btrim(p_reason),c.user_id);
   v_super:=COALESCE((p_data->>'is_supervisor')::boolean,false);
   INSERT INTO wf_assignments(tenant_id,business_id,employee_id,effective_from,site_id,department_id,designation,is_supervisor,reason,changed_by)
   VALUES(c.tenant_id,p_business,v_id,v_join,v_site,v_dept,NULLIF(btrim(p_data->>'designation'),''),v_super,btrim(p_reason),c.user_id);
   res:=jsonb_build_object('status','created','employee_id',v_id,'version',1);
   PERFORM wfi_log(c.tenant_id,p_business,'employee',v_id::text,'created',NULL,
    jsonb_build_object('employee_no',p_data->>'employee_no','site_id',v_site,'contract_type',v_contract,'user_linked',p_data ? 'user_id'),p_reason,p_request);
  ELSE
   SELECT * INTO e FROM wf_employees WHERE id=p_employee_id AND business_id=p_business FOR UPDATE;
   IF NOT FOUND THEN RAISE EXCEPTION 'wf_employee_not_found'; END IF;
   IF p_data ? 'employee_no' AND p_data->>'employee_no'<>e.employee_no THEN RAISE EXCEPTION 'wf_employee_no_immutable'; END IF;
   IF e.version<>p_expected_version THEN RAISE EXCEPTION 'wf_stale_version'; END IF;
   UPDATE wf_employees SET
    full_name=COALESCE(btrim(p_data->>'full_name'),full_name),
    contact_phone=CASE WHEN p_data ? 'contact_phone' THEN p_data->>'contact_phone' ELSE contact_phone END,
    national_id_last4=CASE WHEN p_data ? 'national_id_last4' THEN p_data->>'national_id_last4' ELSE national_id_last4 END,
    user_id=CASE WHEN p_data ? 'user_id' THEN (p_data->>'user_id')::uuid ELSE user_id END,
    version=version+1,updated_at=now() WHERE id=p_employee_id;
   v_id:=p_employee_id;
   res:=jsonb_build_object('status','updated','employee_id',v_id,'version',p_expected_version+1);
   PERFORM wfi_log(c.tenant_id,p_business,'employee',v_id::text,'updated',
    jsonb_build_object('full_name',e.full_name,'user_linked',e.user_id IS NOT NULL),
    jsonb_build_object('changed_keys',(SELECT jsonb_agg(k) FROM jsonb_object_keys(p_data) k)),p_reason,p_request);
  END IF;
 EXCEPTION
  WHEN unique_violation THEN
   IF SQLERRM LIKE '%wf_employees_user_uq%' THEN RAISE EXCEPTION 'wf_user_already_linked'; END IF;
   RAISE EXCEPTION 'wf_employee_no_duplicate';
  WHEN check_violation OR invalid_text_representation OR invalid_datetime_format OR datetime_field_overflow THEN
   RAISE EXCEPTION 'wf_invalid_input';
 END;
 RETURN wfi_finish(p_business,c.tenant_id,p_request,'save_employee',pay,res);
END$$;

CREATE FUNCTION c10_demo.wf_set_employment_v1(p_business bigint,p_request text,p_employee bigint,
 p_effective_from date,p_status text,p_contract_type text,p_reason text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c wf_ctx_t; pay jsonb; e wf_employees; res jsonb; h wf_employment_history;
BEGIN
 IF p_employee IS NULL OR p_effective_from IS NULL OR p_status NOT IN('active','inactive','terminated') OR p_status IS NULL
  OR p_contract_type NOT IN('permanent','contract','probation','daily','hourly','intern') OR p_contract_type IS NULL
  OR p_reason IS NULL OR length(btrim(p_reason)) NOT BETWEEN 3 AND 500 THEN RAISE EXCEPTION 'wf_invalid_input'; END IF;
 pay:=jsonb_build_object('e',p_employee,'d',p_effective_from,'s',p_status,'c',p_contract_type,'r',btrim(p_reason));
 SELECT * INTO b FROM wfi_begin(p_business,p_request,'set_employment',pay);
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 c:=b.o_ctx; PERFORM wfi_need(wfi_is_owner(c),'wf_owner_required');
 SELECT * INTO e FROM wf_employees WHERE id=p_employee AND business_id=p_business FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'wf_employee_not_found'; END IF;
 IF p_effective_from<e.joined_on OR p_effective_from>wfi_today() THEN RAISE EXCEPTION 'wf_invalid_effective_date'; END IF;
 IF wfi_period_locked(p_business,p_effective_from) THEN RAISE EXCEPTION 'wf_period_locked'; END IF;
 INSERT INTO wf_employment_history(tenant_id,business_id,employee_id,effective_from,status,contract_type,reason,changed_by)
 VALUES(c.tenant_id,p_business,p_employee,p_effective_from,p_status,p_contract_type,btrim(p_reason),c.user_id);
 SELECT * INTO h FROM wf_employment_history WHERE employee_id=p_employee AND effective_from<=wfi_today()
  ORDER BY effective_from DESC,id DESC LIMIT 1;
 UPDATE wf_employees SET status=h.status,contract_type=h.contract_type,version=version+1,updated_at=now() WHERE id=p_employee;
 res:=jsonb_build_object('status','applied','employee_status',h.status,'contract_type',h.contract_type);
 PERFORM wfi_log(c.tenant_id,p_business,'employee',p_employee::text,'employment_changed',
  jsonb_build_object('status',e.status,'contract_type',e.contract_type),
  jsonb_build_object('effective_from',p_effective_from,'status',p_status,'contract_type',p_contract_type),p_reason,p_request);
 RETURN wfi_finish(p_business,c.tenant_id,p_request,'set_employment',pay,res);
END$$;

CREATE FUNCTION c10_demo.wf_assign_employee_v1(p_business bigint,p_request text,p_employee bigint,
 p_effective_from date,p_site bigint,p_department_code text,p_designation text,p_is_supervisor boolean,p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c wf_ctx_t; pay jsonb; e wf_employees; v_dept bigint; res jsonb;
BEGIN
 IF p_employee IS NULL OR p_effective_from IS NULL OR p_site IS NULL OR p_is_supervisor IS NULL
  OR p_reason IS NULL OR length(btrim(p_reason)) NOT BETWEEN 3 AND 500 THEN RAISE EXCEPTION 'wf_invalid_input'; END IF;
 pay:=jsonb_build_object('e',p_employee,'d',p_effective_from,'s',p_site,'dep',p_department_code,'des',p_designation,'sv',p_is_supervisor,'r',btrim(p_reason));
 SELECT * INTO b FROM wfi_begin(p_business,p_request,'assign_employee',pay);
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 c:=b.o_ctx; PERFORM wfi_need(wfi_is_owner(c),'wf_owner_required');
 SELECT * INTO e FROM wf_employees WHERE id=p_employee AND business_id=p_business FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'wf_employee_not_found'; END IF;
 IF p_effective_from<e.joined_on THEN RAISE EXCEPTION 'wf_invalid_effective_date'; END IF;
 IF wfi_period_locked(p_business,p_effective_from) THEN RAISE EXCEPTION 'wf_period_locked'; END IF;
 IF NOT EXISTS(SELECT 1 FROM sites WHERE id=p_site AND business_id=p_business) THEN RAISE EXCEPTION 'wf_site_not_in_business'; END IF;
 IF p_department_code IS NOT NULL THEN
  SELECT id INTO v_dept FROM wf_departments WHERE business_id=p_business AND code=p_department_code AND active;
  IF v_dept IS NULL THEN RAISE EXCEPTION 'wf_department_not_found'; END IF; END IF;
 BEGIN
  INSERT INTO wf_assignments(tenant_id,business_id,employee_id,effective_from,site_id,department_id,designation,is_supervisor,reason,changed_by)
  VALUES(c.tenant_id,p_business,p_employee,p_effective_from,p_site,v_dept,NULLIF(btrim(p_designation),''),p_is_supervisor,btrim(p_reason),c.user_id);
 EXCEPTION WHEN check_violation THEN RAISE EXCEPTION 'wf_invalid_input'; END;
 res:=jsonb_build_object('status','applied');
 PERFORM wfi_log(c.tenant_id,p_business,'employee',p_employee::text,'assignment_changed',NULL,pay,p_reason,p_request);
 RETURN wfi_finish(p_business,c.tenant_id,p_request,'assign_employee',pay,res);
END$$;

-- ===== Shifts & holidays =====
CREATE FUNCTION c10_demo.wf_save_shift_v1(p_business bigint,p_request text,p_expected_version bigint,p_shift jsonb,p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c wf_ctx_t; pay jsonb; sh wf_shifts; v_id bigint; res jsonb; v_len int; v_off smallint[];
BEGIN
 IF p_shift IS NULL OR jsonb_typeof(p_shift)<>'object' OR p_expected_version IS NULL OR p_reason IS NULL
  OR length(btrim(p_reason)) NOT BETWEEN 3 AND 500 THEN RAISE EXCEPTION 'wf_invalid_input'; END IF;
 pay:=jsonb_build_object('v',p_expected_version,'s',p_shift,'r',btrim(p_reason));
 SELECT * INTO b FROM wfi_begin(p_business,p_request,'save_shift',pay);
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 c:=b.o_ctx; PERFORM wfi_need(wfi_is_owner(c),'wf_owner_required');
 BEGIN
  IF p_shift ? 'weekly_off_days' AND jsonb_typeof(p_shift->'weekly_off_days')='array' THEN
   SELECT array_agg(x::smallint) INTO v_off FROM jsonb_array_elements_text(p_shift->'weekly_off_days') x; END IF;
  v_len:=((extract(epoch FROM ((p_shift->>'end_time')::time-(p_shift->>'start_time')::time))::int/60)+1440)%1440
   -COALESCE((p_shift->>'break_minutes')::int,0);
  IF v_len<=0 THEN RAISE EXCEPTION 'wf_invalid_shift_length'; END IF;
  SELECT * INTO sh FROM wf_shifts WHERE business_id=p_business AND code=p_shift->>'code' FOR UPDATE;
  IF NOT FOUND THEN
   IF p_expected_version<>0 THEN RAISE EXCEPTION 'wf_stale_version'; END IF;
   INSERT INTO wf_shifts(tenant_id,business_id,code,name,start_time,end_time,break_minutes,grace_late_minutes,grace_early_minutes,
    min_overtime_minutes,weekly_off_days,active)
   VALUES(c.tenant_id,p_business,p_shift->>'code',btrim(p_shift->>'name'),(p_shift->>'start_time')::time,(p_shift->>'end_time')::time,
    COALESCE((p_shift->>'break_minutes')::int,0),COALESCE((p_shift->>'grace_late_minutes')::int,10),
    COALESCE((p_shift->>'grace_early_minutes')::int,0),COALESCE((p_shift->>'min_overtime_minutes')::int,30),v_off,
    COALESCE((p_shift->>'active')::boolean,true)) RETURNING id INTO v_id;
   res:=jsonb_build_object('status','created','shift_id',v_id,'version',1);
  ELSE
   IF sh.version<>p_expected_version THEN RAISE EXCEPTION 'wf_stale_version'; END IF;
   UPDATE wf_shifts SET name=btrim(p_shift->>'name'),start_time=(p_shift->>'start_time')::time,end_time=(p_shift->>'end_time')::time,
    break_minutes=COALESCE((p_shift->>'break_minutes')::int,0),grace_late_minutes=COALESCE((p_shift->>'grace_late_minutes')::int,10),
    grace_early_minutes=COALESCE((p_shift->>'grace_early_minutes')::int,0),min_overtime_minutes=COALESCE((p_shift->>'min_overtime_minutes')::int,30),
    weekly_off_days=v_off,active=COALESCE((p_shift->>'active')::boolean,true),version=version+1 WHERE id=sh.id;
   v_id:=sh.id; res:=jsonb_build_object('status','updated','shift_id',v_id,'version',sh.version+1);
  END IF;
 EXCEPTION WHEN check_violation OR invalid_text_representation OR invalid_datetime_format OR not_null_violation OR datetime_field_overflow THEN
  RAISE EXCEPTION 'wf_invalid_input'; END;
 PERFORM wfi_log(c.tenant_id,p_business,'shift',v_id::text,'saved',CASE WHEN sh.id IS NULL THEN NULL ELSE to_jsonb(sh) END,p_shift,p_reason,p_request);
 RETURN wfi_finish(p_business,c.tenant_id,p_request,'save_shift',pay,res);
END$$;

CREATE FUNCTION c10_demo.wf_assign_shift_v1(p_business bigint,p_request text,p_employee bigint,p_shift_code text,
 p_effective_from date,p_reason text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c wf_ctx_t; pay jsonb; e wf_employees; sh wf_shifts; res jsonb;
BEGIN
 IF p_employee IS NULL OR p_shift_code IS NULL OR p_effective_from IS NULL OR p_reason IS NULL
  OR length(btrim(p_reason)) NOT BETWEEN 3 AND 500 THEN RAISE EXCEPTION 'wf_invalid_input'; END IF;
 pay:=jsonb_build_object('e',p_employee,'s',p_shift_code,'d',p_effective_from,'r',btrim(p_reason));
 SELECT * INTO b FROM wfi_begin(p_business,p_request,'assign_shift',pay);
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 c:=b.o_ctx; PERFORM wfi_need(wfi_is_manager_plus(c),'wf_manager_required');
 SELECT * INTO e FROM wf_employees WHERE id=p_employee AND business_id=p_business;
 IF NOT FOUND THEN RAISE EXCEPTION 'wf_employee_not_found'; END IF;
 SELECT * INTO sh FROM wf_shifts WHERE business_id=p_business AND code=p_shift_code AND active;
 IF NOT FOUND THEN RAISE EXCEPTION 'wf_shift_not_found'; END IF;
 IF p_effective_from<e.joined_on THEN RAISE EXCEPTION 'wf_invalid_effective_date'; END IF;
 IF wfi_period_locked(p_business,p_effective_from) THEN RAISE EXCEPTION 'wf_period_locked'; END IF;
 INSERT INTO wf_shift_assignments(tenant_id,business_id,employee_id,shift_id,effective_from,reason,changed_by)
 VALUES(c.tenant_id,p_business,p_employee,sh.id,p_effective_from,btrim(p_reason),c.user_id);
 res:=jsonb_build_object('status','applied');
 PERFORM wfi_log(c.tenant_id,p_business,'shift_assignment',p_employee::text,'assigned',NULL,pay,p_reason,p_request);
 RETURN wfi_finish(p_business,c.tenant_id,p_request,'assign_shift',pay,res);
END$$;

CREATE FUNCTION c10_demo.wf_save_holiday_v1(p_business bigint,p_request text,p_date date,p_name text,p_kind text,
 p_paid boolean,p_site bigint,p_active boolean,p_reason text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c wf_ctx_t; pay jsonb; res jsonb; v_id bigint;
BEGIN
 IF p_date IS NULL OR p_name IS NULL OR p_kind NOT IN('public','company') OR p_kind IS NULL OR p_paid IS NULL
  OR p_active IS NULL OR p_reason IS NULL OR length(btrim(p_reason)) NOT BETWEEN 3 AND 500 THEN RAISE EXCEPTION 'wf_invalid_input'; END IF;
 pay:=jsonb_build_object('d',p_date,'n',btrim(p_name),'k',p_kind,'p',p_paid,'s',p_site,'a',p_active,'r',btrim(p_reason));
 SELECT * INTO b FROM wfi_begin(p_business,p_request,'save_holiday',pay);
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 c:=b.o_ctx; PERFORM wfi_need(wfi_is_owner(c),'wf_owner_required');
 IF wfi_period_locked(p_business,p_date) THEN RAISE EXCEPTION 'wf_period_locked'; END IF;
 IF p_site IS NOT NULL AND NOT EXISTS(SELECT 1 FROM sites WHERE id=p_site AND business_id=p_business) THEN
  RAISE EXCEPTION 'wf_site_not_in_business'; END IF;
 BEGIN
  INSERT INTO wf_holidays(tenant_id,business_id,holiday_date,name,kind,paid,site_id,active)
  VALUES(c.tenant_id,p_business,p_date,btrim(p_name),p_kind,p_paid,p_site,p_active)
  ON CONFLICT(business_id,holiday_date,COALESCE(site_id,0)) DO UPDATE SET name=excluded.name,kind=excluded.kind,
   paid=excluded.paid,active=excluded.active,version=wf_holidays.version+1 RETURNING id INTO v_id;
 EXCEPTION WHEN check_violation THEN RAISE EXCEPTION 'wf_invalid_input'; END;
 res:=jsonb_build_object('status','applied','holiday_id',v_id);
 PERFORM wfi_log(c.tenant_id,p_business,'holiday',v_id::text,'saved',NULL,pay,p_reason,p_request);
 RETURN wfi_finish(p_business,c.tenant_id,p_request,'save_holiday',pay,res);
END$$;
