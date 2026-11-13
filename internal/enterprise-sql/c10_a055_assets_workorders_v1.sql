-- C10-A055 Enterprise Assets & Maintenance (5/7): WORK ORDERS, breakdown reporting, downtime windows, merge, SLA, reads.
-- DISPOSABLE c10_demo ONLY. Load after core + planning (needs ami_create_wo / ami_complete_target from planning; plpgsql => late bound).
-- Lifecycle DRAFT>SUBMITTED>APPROVED>IN_PROGRESS>COMPLETED>VERIFIED>CLOSED (+cancel/reopen). DB trigger am_wo_guard enforces edges;
-- every RPC additionally re-derives authority from DB state at action time (revoked grants cannot act).
-- Business rules are POLICY (ami_cfg_*). No stock/ledger/payroll/purchase side effects; money fields advisory; spares lines never move stock.
-- Internal helpers are ami_wk_* (not executable by authenticated, see lockdown). Public API: am_*_v1.
-- Error codes (in addition to contract conventions): am_self_approval_denied, am_self_verification_denied, am_wo_illegal_transition,
-- am_wo_cancelled_is_final, am_wo_not_editable, am_safety_ack_required, am_checklist_incomplete, am_evidence_required, am_cause_required,
-- am_labor_required, am_calibration_required, am_invalid_code, am_measure_out_of_range, am_verification_required, am_reopen_window_expired,
-- am_assignee_not_authorized, am_breakdown_already_open (DETAIL = {"work_order_id":n}), am_downtime_open_exists, am_downtime_overlap,
-- am_downtime_end_invalid, am_downtime_already_ended, am_asset_retired, am_use_breakdown_report, am_target_has_open_wo, am_duplicate_attachment.

-- ===================== input validators (pure) =====================
CREATE FUNCTION c10_demo.ami_wk_keys(p jsonb,p_allowed text[]) RETURNS void LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE k text;
BEGIN
 IF p IS NULL OR jsonb_typeof(p)<>'object' THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 FOR k IN SELECT jsonb_object_keys(p) LOOP
  IF NOT k=ANY(p_allowed) THEN RAISE EXCEPTION 'am_invalid_input'; END IF; END LOOP;
END$$;
CREATE FUNCTION c10_demo.ami_wk_txt(p jsonb,k text,p_min int,p_max int,p_req boolean) RETURNS text LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE v text;
BEGIN
 IF p->k IS NULL OR jsonb_typeof(p->k)='null' THEN
  IF p_req THEN RAISE EXCEPTION 'am_invalid_input'; END IF; RETURN NULL; END IF;
 IF jsonb_typeof(p->k)<>'string' THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 v:=btrim(p->>k);
 IF v='' AND NOT p_req THEN RETURN NULL; END IF;
 IF length(v)<p_min OR length(v)>p_max THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 RETURN v;
END$$;
CREATE FUNCTION c10_demo.ami_wk_re(p jsonb,k text,p_regex text,p_req boolean) RETURNS text LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE v text:=c10_demo.ami_wk_txt(p,k,1,200,p_req);
BEGIN
 IF v IS NOT NULL AND v !~ p_regex THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 RETURN v;
END$$;
CREATE FUNCTION c10_demo.ami_wk_num(p jsonb,k text,p_min numeric,p_max numeric,p_req boolean) RETURNS numeric LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE v numeric;
BEGIN
 IF p->k IS NULL OR jsonb_typeof(p->k)='null' THEN
  IF p_req THEN RAISE EXCEPTION 'am_invalid_input'; END IF; RETURN NULL; END IF;
 IF jsonb_typeof(p->k)<>'number' THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 v:=(p->>k)::numeric;
 IF v<p_min OR v>p_max THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 RETURN v;
END$$;
CREATE FUNCTION c10_demo.ami_wk_bool(p jsonb,k text,p_default boolean) RETURNS boolean LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
 IF p->k IS NULL OR jsonb_typeof(p->k)='null' THEN RETURN p_default; END IF;
 IF jsonb_typeof(p->k)<>'boolean' THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 RETURN (p->>k)::boolean;
END$$;
CREATE FUNCTION c10_demo.ami_wk_date(p jsonb,k text,p_req boolean) RETURNS date LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE v text:=c10_demo.ami_wk_txt(p,k,10,10,p_req);
BEGIN
 IF v IS NULL THEN RETURN NULL; END IF;
 IF v !~ '^\d{4}-\d{2}-\d{2}$' THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 BEGIN RETURN v::date; EXCEPTION WHEN others THEN RAISE EXCEPTION 'am_invalid_input'; END;
END$$;
CREATE FUNCTION c10_demo.ami_wk_tsv(v text) RETURNS timestamptz LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
 IF v IS NULL THEN RETURN NULL; END IF;
 IF v !~ '^\d{4}-\d{2}-\d{2}([T ]\d{2}:\d{2}(:\d{2}(\.\d{1,6})?)?)?(Z|[+-]\d{2}(:?\d{2})?)?$' THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 BEGIN RETURN v::timestamptz; EXCEPTION WHEN others THEN RAISE EXCEPTION 'am_invalid_input'; END;
END$$;
CREATE FUNCTION c10_demo.ami_wk_ts(p jsonb,k text,p_req boolean) RETURNS timestamptz LANGUAGE sql IMMUTABLE AS
$$ SELECT c10_demo.ami_wk_tsv(c10_demo.ami_wk_txt(p,k,10,40,p_req)) $$;
-- Future timestamps: within a 5-minute clock skew they are clamped to now(); beyond that rejected.
CREATE FUNCTION c10_demo.ami_wk_clamp(p_ts timestamptz,p_code text) RETURNS timestamptz LANGUAGE plpgsql STABLE AS $$
BEGIN
 IF p_ts IS NULL THEN RETURN now(); END IF;
 IF p_ts>now()+interval '5 minutes' THEN RAISE EXCEPTION '%',p_code; END IF;
 RETURN LEAST(p_ts,now());
END$$;
CREATE FUNCTION c10_demo.ami_wk_reason(p text,p_req boolean) RETURNS text LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE v text:=NULLIF(btrim(COALESCE(p,'')),'');
BEGIN
 IF v IS NULL THEN IF p_req THEN RAISE EXCEPTION 'am_invalid_input'; END IF; RETURN NULL; END IF;
 IF length(v)>500 OR (p_req AND length(v)<3) THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 RETURN v;
END$$;
CREATE FUNCTION c10_demo.ami_wk_rank(p text) RETURNS int LANGUAGE sql IMMUTABLE AS
$$ SELECT CASE p WHEN 'never' THEN 99 WHEN 'low' THEN 1 WHEN 'medium' THEN 2 WHEN 'high' THEN 3 WHEN 'critical' THEN 4 ELSE 0 END $$;

-- ===================== policy / authority helpers =====================
CREATE FUNCTION c10_demo.ami_wk_cat(p_asset bigint) RETURNS bigint LANGUAGE sql STABLE SET search_path=c10_demo,pg_catalog AS
$$ SELECT category_id FROM am_assets WHERE id=p_asset $$;
CREATE FUNCTION c10_demo.ami_wk_pb(w c10_demo.am_work_orders,k text) RETURNS boolean LANGUAGE sql STABLE SET search_path=c10_demo,pg_catalog AS
$$ SELECT ami_cfg_bool(w.business_id,w.site_id,ami_wk_cat(w.asset_id),k) $$;
CREATE FUNCTION c10_demo.ami_wk_pt(w c10_demo.am_work_orders,k text) RETURNS text LANGUAGE sql STABLE SET search_path=c10_demo,pg_catalog AS
$$ SELECT ami_cfg_text(w.business_id,w.site_id,ami_wk_cat(w.asset_id),k) $$;
CREATE FUNCTION c10_demo.ami_wk_pi(w c10_demo.am_work_orders,k text) RETURNS int LANGUAGE sql STABLE SET search_path=c10_demo,pg_catalog AS
$$ SELECT ami_cfg_int(w.business_id,w.site_id,ami_wk_cat(w.asset_id),k) $$;
CREATE FUNCTION c10_demo.ami_wk_pn(w c10_demo.am_work_orders,k text) RETURNS numeric LANGUAGE sql STABLE SET search_path=c10_demo,pg_catalog AS
$$ SELECT ami_cfg_num(w.business_id,w.site_id,ami_wk_cat(w.asset_id),k) $$;
CREATE FUNCTION c10_demo.ami_wk_maker_checker(p_business bigint) RETURNS boolean LANGUAGE sql STABLE SET search_path=c10_demo,pg_catalog AS
$$ SELECT ami_cfg_bool(p_business,NULL,NULL,'wo.maker_checker') $$;

-- Can this user be an assignee for work at p_site? (active technician/supervisor grant covering the site, or an owner)
CREATE FUNCTION c10_demo.ami_wk_assignee_ok(p_business bigint,p_site bigint,p_uid uuid) RETURNS boolean
LANGUAGE plpgsql STABLE SET search_path=c10_demo,pg_catalog AS $$
DECLARE t bigint;
BEGIN
 IF p_uid IS NULL THEN RETURN false; END IF;
 SELECT tenant_id INTO t FROM businesses WHERE id=p_business;
 IF t IS NULL THEN RETURN false; END IF;
 RETURN EXISTS(SELECT 1 FROM tenant_members m WHERE m.user_id=p_uid AND m.tenant_id=t AND m.role='tenant_owner' AND m.active)
  OR EXISTS(SELECT 1 FROM business_members m WHERE m.user_id=p_uid AND m.tenant_id=t AND m.business_id=p_business AND m.active AND m.role='business_owner')
  OR EXISTS(SELECT 1 FROM am_grants g WHERE g.business_id=p_business AND g.user_id=p_uid AND g.active
      AND g.role IN('technician','supervisor') AND (g.site_id IS NULL OR g.site_id=p_site))
  OR (EXISTS(SELECT 1 FROM business_members m WHERE m.user_id=p_uid AND m.tenant_id=t AND m.business_id=p_business AND m.active AND m.role='manager')
      AND ami_cfg_bool(p_business,NULL,NULL,'access.manager_acts_as_supervisor'));
END$$;

-- Site gate: no 'view' at the site => am_denied (existence hidden); view but lacking cap => am_not_permitted.
CREATE FUNCTION c10_demo.ami_wk_gate(c c10_demo.am_ctx_t,p_site bigint,p_cap text) RETURNS void
LANGUAGE plpgsql STABLE SET search_path=c10_demo,pg_catalog AS $$
BEGIN
 IF NOT ami_has(c,p_site,'view') THEN RAISE EXCEPTION 'am_denied'; END IF;
 IF NOT ami_has(c,p_site,p_cap) THEN RAISE EXCEPTION 'am_not_permitted'; END IF;
END$$;

-- Row visibility: supervisors/owners/auditors see all WOs at their sites, technicians assigned-to-self + unassigned, reporters their own.
CREATE FUNCTION c10_demo.ami_wk_visible(c c10_demo.am_ctx_t,w c10_demo.am_work_orders) RETURNS boolean
LANGUAGE plpgsql STABLE SET search_path=c10_demo,pg_catalog AS $$
DECLARE caps text[]:=ami_caps(c,w.site_id);
BEGIN
 IF NOT ('view'=ANY(caps)) THEN RETURN false; END IF;
 IF 'assign'=ANY(caps) OR 'reports'=ANY(caps) THEN RETURN true; END IF;
 IF w.requested_by=c.user_id THEN RETURN true; END IF;
 RETURN 'execute'=ANY(caps) AND (w.assigned_to=c.user_id OR w.assigned_to IS NULL);
END$$;

-- Authority for one action on one WO (NULL = allowed, else the error code). State legality is checked separately.
-- Actions: submit approve return start complete verify close cancel reopen + work(edit-in-progress) edit assign merge attachment.
CREATE FUNCTION c10_demo.ami_wk_auth(c c10_demo.am_ctx_t,w c10_demo.am_work_orders,p_action text) RETURNS text
LANGUAGE plpgsql STABLE SET search_path=c10_demo,pg_catalog AS $$
DECLARE caps text[]:=ami_caps(c,w.site_id); me uuid:=c.user_id; mine boolean; work boolean;
BEGIN
 IF NOT ('view'=ANY(caps)) THEN RETURN 'am_denied'; END IF;
 mine:=(w.assigned_to=me OR (w.assigned_to IS NULL AND w.started_by=me));
 work:='execute'=ANY(caps) AND (mine OR 'assign'=ANY(caps));
 IF p_action='submit' THEN
  IF ('report'=ANY(caps) AND w.requested_by=me) OR 'assign'=ANY(caps) THEN RETURN NULL; END IF;
 ELSIF p_action IN('approve','return') THEN IF 'approve'=ANY(caps) THEN RETURN NULL; END IF;
 ELSIF p_action='start' THEN
  IF 'execute'=ANY(caps) AND (w.assigned_to=me OR 'assign'=ANY(caps)
     OR (w.assigned_to IS NULL AND ami_cfg_bool(w.business_id,w.site_id,ami_wk_cat(w.asset_id),'wo.technician_can_claim_unassigned'))) THEN RETURN NULL; END IF;
 ELSIF p_action IN('complete','work') THEN IF work THEN RETURN NULL; END IF;
 ELSIF p_action IN('verify','close') THEN IF 'verify'=ANY(caps) THEN RETURN NULL; END IF;
 ELSIF p_action='cancel' THEN
  IF 'cancel'=ANY(caps) OR (w.requested_by=me AND 'report'=ANY(caps) AND w.status IN('DRAFT','SUBMITTED','APPROVED')) THEN RETURN NULL; END IF;
 ELSIF p_action='reopen' THEN IF 'reopen'=ANY(caps) THEN RETURN NULL; END IF;
 ELSIF p_action='edit' THEN
  IF 'assign'=ANY(caps) OR (w.status='DRAFT' AND w.requested_by=me AND 'report'=ANY(caps)) THEN RETURN NULL; END IF;
 ELSIF p_action IN('assign','merge') THEN IF 'assign'=ANY(caps) THEN RETURN NULL; END IF;
 ELSIF p_action='attachment' THEN IF 'report'=ANY(caps) THEN RETURN NULL; END IF;
 END IF;
 RETURN 'am_not_permitted';
END$$;

CREATE FUNCTION c10_demo.ami_wk_state_ok(w c10_demo.am_work_orders,p_action text,p_verify_required boolean) RETURNS boolean
LANGUAGE sql IMMUTABLE AS $$ SELECT CASE p_action
 WHEN 'submit' THEN w.status='DRAFT' WHEN 'approve' THEN w.status='SUBMITTED' WHEN 'return' THEN w.status='SUBMITTED'
 WHEN 'start' THEN w.status='APPROVED' WHEN 'complete' THEN w.status='IN_PROGRESS' WHEN 'verify' THEN w.status='COMPLETED'
 WHEN 'close' THEN w.status='VERIFIED' OR (w.status='COMPLETED' AND NOT p_verify_required)
 WHEN 'cancel' THEN w.status IN('DRAFT','SUBMITTED','APPROVED','IN_PROGRESS')
 WHEN 'reopen' THEN w.status IN('COMPLETED','VERIFIED','CLOSED') ELSE false END $$;

CREATE FUNCTION c10_demo.ami_wk_finished_at(w c10_demo.am_work_orders) RETURNS timestamptz LANGUAGE sql IMMUTABLE AS
$$ SELECT COALESCE(GREATEST(w.completed_at,w.verified_at,w.closed_at),w.updated_at) $$;
CREATE FUNCTION c10_demo.ami_wk_reopen_ok(w c10_demo.am_work_orders) RETURNS boolean LANGUAGE plpgsql STABLE SET search_path=c10_demo,pg_catalog AS $$
DECLARE d int:=ami_wk_pi(w,'wo.reopen_window_days');
BEGIN RETURN d>0 AND now()<=ami_wk_finished_at(w)+make_interval(days=>d); END$$;

-- Computed per-caller action list (the UI never guesses).
CREATE FUNCTION c10_demo.ami_wk_actions(c c10_demo.am_ctx_t,w c10_demo.am_work_orders) RETURNS text[]
LANGUAGE plpgsql STABLE SET search_path=c10_demo,pg_catalog AS $$
DECLARE a text; o text[]:=ARRAY[]::text[]; vr boolean; mc boolean; open boolean;
BEGIN
 IF NOT ami_wk_visible(c,w) THEN RETURN o; END IF;
 vr:=ami_wk_pb(w,'wo.verify_required'); mc:=ami_wk_maker_checker(w.business_id);
 FOREACH a IN ARRAY ARRAY['submit','approve','return','start','complete','verify','close','cancel','reopen'] LOOP
  IF ami_wk_auth(c,w,a) IS NOT NULL OR NOT ami_wk_state_ok(w,a,vr) THEN CONTINUE; END IF;
  IF a='approve' AND mc AND w.requested_by=c.user_id THEN CONTINUE; END IF;
  IF a='verify' AND mc AND w.completed_by=c.user_id THEN CONTINUE; END IF;
  IF a='reopen' AND NOT ami_wk_reopen_ok(w) THEN CONTINUE; END IF;
  o:=array_append(o,a);
 END LOOP;
 open:=w.status IN('DRAFT','SUBMITTED','APPROVED','IN_PROGRESS');
 IF ami_wk_auth(c,w,'edit') IS NULL AND w.status IN('DRAFT','SUBMITTED','APPROVED') THEN o:=array_append(o,'edit'::text);
 ELSIF ami_wk_auth(c,w,'work') IS NULL AND open THEN o:=array_append(o,'edit_estimates'::text); END IF;
 IF open AND ami_wk_auth(c,w,'assign') IS NULL THEN o:=array_append(o,'assign'::text); o:=array_append(o,'merge'::text); END IF;
 IF w.status IN('APPROVED','IN_PROGRESS') AND w.safety_ack_at IS NULL AND ami_wk_auth(c,w,'work') IS NULL
    AND (w.safety_critical OR COALESCE((SELECT k.safety_critical FROM am_assets a JOIN am_categories k ON k.id=a.category_id WHERE a.id=w.asset_id),false)) THEN
  o:=array_append(o,'acknowledge_safety'::text); END IF;
 IF w.status='IN_PROGRESS' AND ami_wk_auth(c,w,'work') IS NULL THEN o:=array_append(o,'checklist'::text); END IF;
 IF open AND (ami_wk_auth(c,w,'work') IS NULL OR (ami_wk_auth(c,w,'edit') IS NULL AND w.status IN('DRAFT','SUBMITTED','APPROVED'))) THEN
  o:=array_append(o,'labor'::text); o:=array_append(o,'spares'::text); END IF;
 IF w.status IN('DRAFT','SUBMITTED','APPROVED','IN_PROGRESS','COMPLETED','VERIFIED') AND ami_wk_auth(c,w,'attachment') IS NULL THEN o:=array_append(o,'attachment'::text); END IF;
 RETURN o;
END$$;

-- ===================== SLA / JSON builders =====================
-- ok / at_risk (last 20% of the window) / breached. NULL when no SLA or WO cancelled.
CREATE FUNCTION c10_demo.ami_wk_sla(p_due timestamptz,p_from timestamptz,p_done timestamptz,p_status text) RETURNS text
LANGUAGE plpgsql STABLE AS $$
BEGIN
 IF p_due IS NULL OR p_status='CANCELLED' THEN RETURN NULL; END IF;
 IF p_done IS NOT NULL THEN RETURN CASE WHEN p_done<=p_due THEN 'ok' ELSE 'breached' END; END IF;
 IF now()>p_due THEN RETURN 'breached'; END IF;
 IF now()>=p_due-(p_due-p_from)*0.2 THEN RETURN 'at_risk'; END IF;
 RETURN 'ok';
END$$;
CREATE FUNCTION c10_demo.ami_wk_needs_re(w c10_demo.am_work_orders) RETURNS boolean LANGUAGE sql STABLE SET search_path=c10_demo,pg_catalog AS
$$ SELECT w.assigned_to IS NOT NULL AND w.status IN('DRAFT','SUBMITTED','APPROVED','IN_PROGRESS')
   AND NOT ami_wk_assignee_ok(w.business_id,w.site_id,w.assigned_to) $$;
CREATE FUNCTION c10_demo.ami_wk_json(c c10_demo.am_ctx_t,w c10_demo.am_work_orders) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path=c10_demo,pg_catalog AS $$
DECLARE a record; ok boolean; open boolean:=w.status IN('DRAFT','SUBMITTED','APPROVED','IN_PROGRESS'); done boolean:=w.status IN('COMPLETED','VERIFIED','CLOSED');
BEGIN
 SELECT asset_no,name INTO a FROM am_assets WHERE id=w.asset_id;
 ok:=CASE WHEN w.assigned_to IS NULL THEN NULL ELSE ami_wk_assignee_ok(w.business_id,w.site_id,w.assigned_to) END;
 RETURN to_jsonb(w)-'needs_reassignment' || jsonb_build_object('asset_no',a.asset_no,'asset_name',a.name,
  'assignee_authorized',ok,'needs_reassignment',(open AND w.assigned_to IS NOT NULL AND NOT ok),
  'response_state',ami_wk_sla(w.sla_response_due_at,w.requested_at,w.responded_at,w.status),
  'resolve_state',ami_wk_sla(w.sla_resolve_due_at,w.requested_at,CASE WHEN done THEN w.completed_at END,w.status),
  'overdue',(open AND ((w.due_on IS NOT NULL AND w.due_on<ami_today(w.business_id)) OR (w.sla_resolve_due_at IS NOT NULL AND w.sla_resolve_due_at<now()))),
  'auto_approved',(w.approved_at IS NOT NULL AND w.approved_by IS NULL));
END$$;
CREATE FUNCTION c10_demo.ami_wk_state(w c10_demo.am_work_orders) RETURNS jsonb LANGUAGE sql IMMUTABLE AS
$$ SELECT jsonb_build_object('status',w.status,'version',w.version,'priority',w.priority,'assigned_to',w.assigned_to,'approved_by',w.approved_by,
   'started_at',w.started_at,'completed_at',w.completed_at,'verified_at',w.verified_at,'closed_at',w.closed_at,'reopen_count',w.reopen_count) $$;
CREATE FUNCTION c10_demo.ami_wk_dt_json(d c10_demo.am_downtime) RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path=c10_demo,pg_catalog AS $$
DECLARE a record; cap int; raw numeric; eff numeric; isopen boolean:=d.ended_at IS NULL; minc int;
BEGIN
 SELECT asset_no,name,category_id INTO a FROM am_assets WHERE id=d.asset_id;
 cap:=ami_cfg_int(d.business_id,d.site_id,a.category_id,'downtime.max_open_hours');
 minc:=ami_cfg_int(d.business_id,d.site_id,a.category_id,'downtime.min_counted_minutes');
 raw:=extract(epoch FROM (COALESCE(d.ended_at,now())-d.started_at))/60.0;
 eff:=CASE WHEN isopen THEN LEAST(raw,cap*60.0) ELSE raw END;
 RETURN to_jsonb(d) || jsonb_build_object('asset_no',a.asset_no,'asset_name',a.name,'open',isopen,'duration_minutes',round(eff,2),
  'exceeds_max_open',(isopen AND raw>cap*60.0),'max_open_hours',cap,
  'counted',(eff>=minc AND (d.kind<>'planned' OR ami_cfg_bool(d.business_id,d.site_id,a.category_id,'downtime.planned_counts'))));
END$$;

-- ===================== write-side helpers =====================
CREATE FUNCTION c10_demo.ami_wk_hist(w c10_demo.am_work_orders,p_from text,p_to text,p_action text,p_reason text,p_request text) RETURNS void
LANGUAGE sql AS $$
 INSERT INTO c10_demo.am_wo_history(tenant_id,business_id,work_order_id,from_status,to_status,action,reason,actor_uid,request_key)
 VALUES(w.tenant_id,w.business_id,w.id,p_from,p_to,p_action,p_reason,c10_demo.actor_uid(),p_request) $$;

-- Move the asset between maintenance statuses only from the listed current statuses (audited).
CREATE FUNCTION c10_demo.ami_wk_set_asset(p_asset bigint,p_to text,p_from text[],p_request text) RETURNS void
LANGUAGE plpgsql SET search_path=c10_demo,pg_catalog AS $$
DECLARE a am_assets;
BEGIN
 SELECT * INTO a FROM am_assets WHERE id=p_asset FOR UPDATE;
 IF NOT FOUND OR a.status=p_to OR NOT a.status=ANY(p_from) THEN RETURN; END IF;
 UPDATE am_assets SET status=p_to,version=version+1,updated_at=now() WHERE id=p_asset;
 PERFORM ami_log(a.tenant_id,a.business_id,'asset',a.id::text,'asset.status_auto',jsonb_build_object('status',a.status,'version',a.version),
   jsonb_build_object('status',p_to,'version',a.version+1),'work order lifecycle',p_request);
END$$;
-- After a WO / downtime change: breakdown (open breakdown window) > under_maintenance (a WO in progress) > active.
CREATE FUNCTION c10_demo.ami_wk_restore_asset(p_asset bigint,p_request text) RETURNS void
LANGUAGE plpgsql SET search_path=c10_demo,pg_catalog AS $$
DECLARE a am_assets; ns text;
BEGIN
 SELECT * INTO a FROM am_assets WHERE id=p_asset FOR UPDATE;
 IF NOT FOUND OR a.status NOT IN('breakdown','under_maintenance') THEN RETURN; END IF;
 ns:=CASE WHEN EXISTS(SELECT 1 FROM am_downtime d WHERE d.asset_id=p_asset AND d.ended_at IS NULL AND d.kind='breakdown') THEN 'breakdown'
          WHEN EXISTS(SELECT 1 FROM am_work_orders w WHERE w.asset_id=p_asset AND w.status='IN_PROGRESS') THEN 'under_maintenance'
          ELSE 'active' END;
 PERFORM ami_wk_set_asset(p_asset,ns,ARRAY['breakdown','under_maintenance'],p_request);
END$$;
-- Close open windows linked to a WO (kinds filter) at p_at (never before their start). Returns count closed.
CREATE FUNCTION c10_demo.ami_wk_close_windows(p_wo bigint,p_kinds text[],p_at timestamptz,p_request text) RETURNS int
LANGUAGE plpgsql SET search_path=c10_demo,pg_catalog AS $$
DECLARE d am_downtime; n int:=0; e timestamptz;
BEGIN
 FOR d IN SELECT * FROM am_downtime WHERE work_order_id=p_wo AND ended_at IS NULL AND kind=ANY(p_kinds) ORDER BY id FOR UPDATE LOOP
  e:=GREATEST(p_at,d.started_at);
  UPDATE am_downtime SET ended_at=e,ended_by=actor_uid() WHERE id=d.id;
  PERFORM ami_log(d.tenant_id,d.business_id,'downtime',d.id::text,'downtime.end',jsonb_build_object('ended_at',NULL),
    jsonb_build_object('ended_at',e,'kind',d.kind,'work_order_id',p_wo),'closed by work order lifecycle',p_request);
  n:=n+1;
 END LOOP;
 RETURN n;
END$$;
CREATE FUNCTION c10_demo.ami_wk_dt_overlap(p_asset bigint,p_start timestamptz,p_end timestamptz,p_except bigint) RETURNS boolean
LANGUAGE sql STABLE SET search_path=c10_demo,pg_catalog AS $$
 SELECT EXISTS(SELECT 1 FROM am_downtime d WHERE d.asset_id=p_asset AND d.id IS DISTINCT FROM p_except
  AND d.started_at<COALESCE(p_end,'infinity'::timestamptz) AND COALESCE(d.ended_at,'infinity'::timestamptz)>p_start) $$;
CREATE FUNCTION c10_demo.ami_wk_dt_code(p_business bigint,p_code text) RETURNS text LANGUAGE plpgsql STABLE SET search_path=c10_demo,pg_catalog AS $$
BEGIN
 IF p_code IS NULL THEN RETURN NULL; END IF;
 IF NOT EXISTS(SELECT 1 FROM am_codes WHERE business_id=p_business AND kind='downtime_reason' AND code=upper(p_code) AND active) THEN RAISE EXCEPTION 'am_invalid_code'; END IF;
 RETURN upper(p_code);
END$$;
CREATE FUNCTION c10_demo.ami_wk_code(p_business bigint,p_kind text,p_code text) RETURNS text LANGUAGE plpgsql STABLE SET search_path=c10_demo,pg_catalog AS $$
BEGIN
 IF p_code IS NULL THEN RETURN NULL; END IF;
 IF NOT EXISTS(SELECT 1 FROM am_codes WHERE business_id=p_business AND kind=p_kind AND code=upper(p_code) AND active) THEN RAISE EXCEPTION 'am_invalid_code'; END IF;
 RETURN upper(p_code);
END$$;
CREATE FUNCTION c10_demo.ami_wk_asset_open(p_asset bigint) RETURNS boolean LANGUAGE sql STABLE SET search_path=c10_demo,pg_catalog AS
$$ SELECT status NOT IN('retired','disposed') FROM am_assets WHERE id=p_asset $$;
CREATE FUNCTION c10_demo.ami_wk_resla(w c10_demo.am_work_orders) RETURNS c10_demo.am_work_orders LANGUAGE plpgsql SET search_path=c10_demo,pg_catalog AS $$
DECLARE r am_work_orders; cat bigint:=ami_wk_cat(w.asset_id);
BEGIN
 UPDATE am_work_orders SET
  sla_response_due_at=requested_at+make_interval(hours=>ami_cfg_int(business_id,site_id,cat,'sla.response_hours.'||priority)),
  sla_resolve_due_at=requested_at+make_interval(hours=>ami_cfg_int(business_id,site_id,cat,'sla.resolve_hours.'||priority))
 WHERE id=w.id RETURNING * INTO r;
 RETURN r;
END$$;

-- Approval needed? (policy wo.approval_min_priority + wo.approval_cost_threshold; 'never' disables the priority rule, threshold 0 disables the cost rule)
CREATE FUNCTION c10_demo.ami_wk_needs_approval(w c10_demo.am_work_orders) RETURNS boolean LANGUAGE plpgsql STABLE SET search_path=c10_demo,pg_catalog AS $$
DECLARE thr numeric:=ami_wk_pn(w,'wo.approval_cost_threshold');
BEGIN
 IF ami_wk_rank(w.priority)>=ami_wk_rank(ami_wk_pt(w,'wo.approval_min_priority')) THEN RETURN true; END IF;
 RETURN thr>0 AND COALESCE(w.est_labor_cost,0)+COALESCE(w.est_spares_cost,0)>=thr;
END$$;
-- DRAFT -> SUBMITTED, then auto-approval by policy in the same transaction (approved_by stays NULL = approved by policy).
CREATE FUNCTION c10_demo.ami_wk_do_submit(p_w c10_demo.am_work_orders,p_request text,p_breakdown boolean) RETURNS c10_demo.am_work_orders
LANGUAGE plpgsql SET search_path=c10_demo,pg_catalog AS $$
DECLARE w am_work_orders; auto boolean; v text;
BEGIN
 UPDATE am_work_orders SET status='SUBMITTED',submitted_at=now(),version=version+1,updated_at=now() WHERE id=p_w.id RETURNING * INTO w;
 PERFORM ami_wk_hist(w,'DRAFT','SUBMITTED','submit',NULL,p_request);
 IF p_breakdown THEN
  v:=ami_wk_pt(w,'breakdown.auto_approve');
  auto:=CASE v WHEN 'all' THEN true WHEN 'high_and_above' THEN ami_wk_rank(w.priority)>=3 WHEN 'critical' THEN w.priority='critical' ELSE false END;
 ELSE auto:=NOT ami_wk_needs_approval(w); END IF;
 IF auto THEN
  UPDATE am_work_orders SET status='APPROVED',approved_at=now(),approved_by=NULL,last_reason='auto-approved by policy',version=version+1,updated_at=now()
   WHERE id=w.id RETURNING * INTO w;
  PERFORM ami_wk_hist(w,'SUBMITTED','APPROVED','auto_approve','policy',p_request);
 END IF;
 RETURN w;
END$$;

-- ===================== create / update / assign =====================
CREATE FUNCTION c10_demo.am_create_work_order_v1(p_business bigint,p_request text,p_data jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c am_ctx_t; a am_assets; w am_work_orders; wid bigint; v_kind text; v_title text; v_desc text; v_prio text; v_due date;
 v_chk text; v_svc text; v_asg uuid; v_aref text; v_team text; v_elh numeric; v_elc numeric; v_esc numeric; v_submit boolean; v_asset bigint;
 mgr boolean; safety boolean;
BEGIN
 PERFORM ami_wk_keys(p_data,ARRAY['asset_id','kind','title','description','priority','due_on','checklist_code','service_category',
   'assigned_to','assignee_ref','team_ref','est_labor_hours','est_labor_cost','est_spares_cost','submit']);
 v_asset:=ami_wk_num(p_data,'asset_id',1,9e18,true)::bigint;
 v_kind:=COALESCE(ami_wk_txt(p_data,'kind',1,20,false),'corrective');
 IF v_kind='breakdown' THEN RAISE EXCEPTION 'am_use_breakdown_report'; END IF;
 IF v_kind NOT IN('preventive','corrective','inspection','calibration') THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 v_title:=ami_wk_txt(p_data,'title',3,160,true); v_desc:=ami_wk_txt(p_data,'description',1,2000,false);
 v_prio:=COALESCE(ami_wk_txt(p_data,'priority',1,10,false),'medium');
 IF v_prio NOT IN('low','medium','high','critical') THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 v_due:=ami_wk_date(p_data,'due_on',false); v_chk:=ami_wk_re(p_data,'checklist_code','^[A-Z0-9][A-Z0-9_-]{0,31}$',false);
 v_svc:=ami_wk_re(p_data,'service_category','^[A-Z0-9][A-Z0-9_-]{0,23}$',false);
 v_aref:=ami_wk_re(p_data,'assignee_ref','^[A-Za-z0-9][A-Za-z0-9._/-]{0,39}$',false);
 v_team:=ami_wk_re(p_data,'team_ref','^[A-Za-z0-9][A-Za-z0-9._/ -]{0,39}$',false);
 IF p_data->'assigned_to' IS NOT NULL AND jsonb_typeof(p_data->'assigned_to')='string' THEN
  BEGIN v_asg:=(p_data->>'assigned_to')::uuid; EXCEPTION WHEN others THEN RAISE EXCEPTION 'am_invalid_input'; END;
 ELSIF p_data->'assigned_to' IS NOT NULL AND jsonb_typeof(p_data->'assigned_to')<>'null' THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 v_elh:=ami_wk_num(p_data,'est_labor_hours',0,100000,false); v_elc:=ami_wk_num(p_data,'est_labor_cost',0,1e12,false);
 v_esc:=ami_wk_num(p_data,'est_spares_cost',0,1e12,false); v_submit:=ami_wk_bool(p_data,'submit',false);
 SELECT * INTO b FROM ami_begin(p_business,p_request,'wo_create',p_data);
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 c:=b.o_ctx;
 SELECT * INTO a FROM am_assets WHERE id=v_asset AND business_id=p_business AND tenant_id=c.tenant_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'am_denied'; END IF;
 PERFORM ami_wk_gate(c,a.site_id,'report');
 IF NOT ami_has(c,a.site_id,'assign') THEN
  IF ami_has(c,a.site_id,'execute') THEN
   IF NOT ami_cfg_bool(p_business,a.site_id,a.category_id,'wo.technician_can_create') THEN RAISE EXCEPTION 'am_not_permitted'; END IF;
   IF (v_asg IS NOT NULL AND v_asg<>c.user_id) OR v_aref IS NOT NULL OR v_team IS NOT NULL THEN RAISE EXCEPTION 'am_not_permitted'; END IF;
  ELSE -- reporter: corrective requests only, no assignment / estimates
   IF v_kind<>'corrective' OR v_asg IS NOT NULL OR v_aref IS NOT NULL OR v_team IS NOT NULL OR v_elh IS NOT NULL OR v_elc IS NOT NULL OR v_esc IS NOT NULL THEN
    RAISE EXCEPTION 'am_not_permitted'; END IF;
  END IF;
 END IF;
 IF v_asg IS NOT NULL AND NOT ami_wk_assignee_ok(p_business,a.site_id,v_asg) THEN RAISE EXCEPTION 'am_assignee_not_authorized'; END IF;
 IF v_svc IS NOT NULL AND NOT EXISTS(SELECT 1 FROM am_codes WHERE business_id=p_business AND kind='service_category' AND code=v_svc AND active) THEN
  RAISE EXCEPTION 'am_invalid_code'; END IF;
 IF a.status IN('retired','disposed') THEN RAISE EXCEPTION 'am_asset_retired'; END IF;
 wid:=ami_create_wo(c,p_request,a.id,v_kind,v_title,v_desc,v_prio,'manual',NULL,v_due,v_chk,
   jsonb_strip_nulls(jsonb_build_object('service_category',v_svc,'team_ref',v_team,'est_labor_hours',v_elh,'est_labor_cost',v_elc,'est_spares_cost',v_esc)));
 SELECT safety_critical INTO safety FROM am_categories WHERE id=a.category_id;
 UPDATE am_work_orders SET assigned_to=v_asg,assignee_ref=v_aref,team_ref=COALESCE(team_ref,v_team),due_on=COALESCE(due_on,v_due),
   safety_critical=(safety_critical OR COALESCE(safety,false)) WHERE id=wid RETURNING * INTO w;
 IF v_submit THEN w:=ami_wk_do_submit(w,p_request,false); END IF;
 PERFORM ami_log(c.tenant_id,p_business,'work_order',w.id::text,'wo.create',NULL,ami_wk_state(w)||jsonb_build_object('wo_no',w.wo_no,'kind',w.kind,'asset_id',w.asset_id),NULL,p_request);
 RETURN ami_finish(p_business,c.tenant_id,p_request,'wo_create',p_data,jsonb_build_object('status','applied','id',w.id,'wo_no',w.wo_no,
   'wo_status',w.status,'version',w.version,'auto_approved',(w.approved_at IS NOT NULL AND w.approved_by IS NULL)));
END$$;

CREATE FUNCTION c10_demo.am_update_work_order_v1(p_business bigint,p_request text,p_wo bigint,p_expected_version bigint,p_changes jsonb,p_reason text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c am_ctx_t; w am_work_orders; n am_work_orders; pay jsonb; rsn text; k text; full_keys text[]:=ARRAY['title','description','priority','due_on','service_category','team_ref','assignee_ref'];
 est_keys text[]:=ARRAY['est_labor_hours','est_labor_cost','est_spares_cost','actual_labor_hours','actual_labor_cost','actual_spares_cost'];
 touched_full boolean:=false; touched_act boolean:=false;
 v_title text; v_desc text; v_prio text; v_due date; v_svc text; v_team text; v_aref text; v_elh numeric; v_elc numeric; v_esc numeric; v_alh numeric; v_alc numeric; v_asc numeric;
BEGIN
 IF p_wo IS NULL OR p_expected_version IS NULL THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 PERFORM ami_wk_keys(p_changes,full_keys||est_keys);
 IF p_changes='{}'::jsonb THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 rsn:=ami_wk_reason(p_reason,true);
 IF p_changes ? 'title' THEN v_title:=ami_wk_txt(p_changes,'title',3,160,true); END IF;
 IF p_changes ? 'description' THEN v_desc:=ami_wk_txt(p_changes,'description',1,2000,false); END IF;
 IF p_changes ? 'priority' THEN v_prio:=ami_wk_txt(p_changes,'priority',1,10,true);
  IF v_prio NOT IN('low','medium','high','critical') THEN RAISE EXCEPTION 'am_invalid_input'; END IF; END IF;
 IF p_changes ? 'due_on' THEN v_due:=ami_wk_date(p_changes,'due_on',false); END IF;
 IF p_changes ? 'service_category' THEN v_svc:=ami_wk_re(p_changes,'service_category','^[A-Z0-9][A-Z0-9_-]{0,23}$',false); END IF;
 IF p_changes ? 'team_ref' THEN v_team:=ami_wk_re(p_changes,'team_ref','^[A-Za-z0-9][A-Za-z0-9._/ -]{0,39}$',false); END IF;
 IF p_changes ? 'assignee_ref' THEN v_aref:=ami_wk_re(p_changes,'assignee_ref','^[A-Za-z0-9][A-Za-z0-9._/-]{0,39}$',false); END IF;
 v_elh:=ami_wk_num(p_changes,'est_labor_hours',0,100000,false); v_elc:=ami_wk_num(p_changes,'est_labor_cost',0,1e12,false);
 v_esc:=ami_wk_num(p_changes,'est_spares_cost',0,1e12,false); v_alh:=ami_wk_num(p_changes,'actual_labor_hours',0,100000,false);
 v_alc:=ami_wk_num(p_changes,'actual_labor_cost',0,1e12,false); v_asc:=ami_wk_num(p_changes,'actual_spares_cost',0,1e12,false);
 FOR k IN SELECT jsonb_object_keys(p_changes) LOOP
  IF k=ANY(full_keys) THEN touched_full:=true; END IF;
  IF k LIKE 'actual\_%' THEN touched_act:=true; END IF;
 END LOOP;
 pay:=jsonb_build_object('wo',p_wo,'v',p_expected_version,'c',p_changes,'r',rsn);
 SELECT * INTO b FROM ami_begin(p_business,p_request,'wo_update',pay);
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 c:=b.o_ctx;
 SELECT * INTO w FROM am_work_orders WHERE id=p_wo AND business_id=p_business FOR UPDATE;
 IF NOT FOUND OR NOT ami_wk_visible(c,w) THEN RAISE EXCEPTION 'am_denied'; END IF;
 IF w.status='CANCELLED' THEN RAISE EXCEPTION 'am_wo_cancelled_is_final'; END IF;
 IF touched_full THEN
  IF ami_wk_auth(c,w,'edit') IS NOT NULL THEN RAISE EXCEPTION 'am_not_permitted'; END IF;
 ELSIF NOT (ami_wk_auth(c,w,'edit') IS NULL OR ami_wk_auth(c,w,'work') IS NULL) THEN RAISE EXCEPTION 'am_not_permitted'; END IF;
 IF w.version<>p_expected_version THEN RAISE EXCEPTION 'am_stale_version'; END IF;
 IF w.status IN('DRAFT','SUBMITTED','APPROVED') THEN
  IF touched_act THEN RAISE EXCEPTION 'am_wo_not_editable'; END IF;
 ELSIF w.status='IN_PROGRESS' THEN
  IF touched_full THEN RAISE EXCEPTION 'am_wo_not_editable'; END IF;
 ELSE RAISE EXCEPTION 'am_wo_not_editable'; END IF;
 UPDATE am_work_orders SET
  title=CASE WHEN p_changes ? 'title' THEN v_title ELSE title END,
  description=CASE WHEN p_changes ? 'description' THEN v_desc ELSE description END,
  priority=CASE WHEN p_changes ? 'priority' THEN v_prio ELSE priority END,
  due_on=CASE WHEN p_changes ? 'due_on' THEN v_due ELSE due_on END,
  service_category=CASE WHEN p_changes ? 'service_category' THEN v_svc ELSE service_category END,
  team_ref=CASE WHEN p_changes ? 'team_ref' THEN v_team ELSE team_ref END,
  assignee_ref=CASE WHEN p_changes ? 'assignee_ref' THEN v_aref ELSE assignee_ref END,
  est_labor_hours=CASE WHEN p_changes ? 'est_labor_hours' THEN v_elh ELSE est_labor_hours END,
  est_labor_cost=CASE WHEN p_changes ? 'est_labor_cost' THEN v_elc ELSE est_labor_cost END,
  est_spares_cost=CASE WHEN p_changes ? 'est_spares_cost' THEN v_esc ELSE est_spares_cost END,
  actual_labor_hours=CASE WHEN p_changes ? 'actual_labor_hours' THEN v_alh ELSE actual_labor_hours END,
  actual_labor_cost=CASE WHEN p_changes ? 'actual_labor_cost' THEN v_alc ELSE actual_labor_cost END,
  actual_spares_cost=CASE WHEN p_changes ? 'actual_spares_cost' THEN v_asc ELSE actual_spares_cost END,
  last_reason=rsn,version=version+1,updated_at=now() WHERE id=w.id RETURNING * INTO n;
 IF v_svc IS NOT NULL AND NOT EXISTS(SELECT 1 FROM am_codes WHERE business_id=p_business AND kind='service_category' AND code=v_svc AND active) THEN
  RAISE EXCEPTION 'am_invalid_code'; END IF;
 IF n.priority<>w.priority THEN n:=ami_wk_resla(n); END IF;
 PERFORM ami_wk_hist(n,w.status,n.status,'update',rsn,p_request);
 PERFORM ami_log(c.tenant_id,p_business,'work_order',w.id::text,'wo.update',to_jsonb(w)-'updated_at',to_jsonb(n)-'updated_at',rsn,p_request);
 RETURN ami_finish(p_business,c.tenant_id,p_request,'wo_update',pay,jsonb_build_object('status','applied','id',n.id,'wo_status',n.status,'version',n.version));
END$$;

CREATE FUNCTION c10_demo.am_assign_work_order_v1(p_business bigint,p_request text,p_wo bigint,p_expected_version bigint,p_assigned_to uuid,
 p_assignee_ref text,p_team_ref text,p_reason text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c am_ctx_t; w am_work_orders; n am_work_orders; pay jsonb; rsn text; v_aref text:=NULLIF(btrim(COALESCE(p_assignee_ref,'')),''); v_team text:=NULLIF(btrim(COALESCE(p_team_ref,'')),'');
BEGIN
 IF p_wo IS NULL OR p_expected_version IS NULL THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 rsn:=ami_wk_reason(p_reason,true);
 IF v_aref IS NOT NULL AND v_aref !~ '^[A-Za-z0-9][A-Za-z0-9._/-]{0,39}$' THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 IF v_team IS NOT NULL AND v_team !~ '^[A-Za-z0-9][A-Za-z0-9._/ -]{0,39}$' THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 pay:=jsonb_build_object('wo',p_wo,'v',p_expected_version,'u',p_assigned_to,'ar',v_aref,'t',v_team,'r',rsn);
 SELECT * INTO b FROM ami_begin(p_business,p_request,'wo_assign',pay);
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 c:=b.o_ctx;
 SELECT * INTO w FROM am_work_orders WHERE id=p_wo AND business_id=p_business FOR UPDATE;
 IF NOT FOUND OR NOT ami_wk_visible(c,w) THEN RAISE EXCEPTION 'am_denied'; END IF;
 IF ami_wk_auth(c,w,'assign') IS NOT NULL THEN RAISE EXCEPTION 'am_not_permitted'; END IF;
 IF w.version<>p_expected_version THEN RAISE EXCEPTION 'am_stale_version'; END IF;
 IF w.status='CANCELLED' THEN RAISE EXCEPTION 'am_wo_cancelled_is_final'; END IF;
 IF w.status NOT IN('DRAFT','SUBMITTED','APPROVED','IN_PROGRESS') THEN RAISE EXCEPTION 'am_wo_not_editable'; END IF;
 IF p_assigned_to IS NOT NULL AND NOT ami_wk_assignee_ok(p_business,w.site_id,p_assigned_to) THEN RAISE EXCEPTION 'am_assignee_not_authorized'; END IF;
 UPDATE am_work_orders SET assigned_to=p_assigned_to,assignee_ref=v_aref,team_ref=v_team,needs_reassignment=false,
   safety_ack_by=CASE WHEN assigned_to IS DISTINCT FROM p_assigned_to THEN NULL ELSE safety_ack_by END,
   safety_ack_at=CASE WHEN assigned_to IS DISTINCT FROM p_assigned_to THEN NULL ELSE safety_ack_at END,
   last_reason=rsn,version=version+1,updated_at=now() WHERE id=w.id RETURNING * INTO n;
 PERFORM ami_wk_hist(n,w.status,n.status,'assign',rsn,p_request);
 PERFORM ami_log(c.tenant_id,p_business,'work_order',w.id::text,'wo.assign',
   jsonb_build_object('assigned_to',w.assigned_to,'assignee_ref',w.assignee_ref,'team_ref',w.team_ref,'version',w.version),
   jsonb_build_object('assigned_to',n.assigned_to,'assignee_ref',n.assignee_ref,'team_ref',n.team_ref,'version',n.version),rsn,p_request);
 RETURN ami_finish(p_business,c.tenant_id,p_request,'wo_assign',pay,jsonb_build_object('status','applied','id',n.id,'wo_status',n.status,'version',n.version,'assigned_to',n.assigned_to));
END$$;

-- ===================== lifecycle transitions =====================
CREATE FUNCTION c10_demo.am_wo_transition_v1(p_business bigint,p_request text,p_wo bigint,p_expected_version bigint,p_action text,
 p_reason text DEFAULT NULL,p_data jsonb DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c am_ctx_t; w am_work_orders; n am_work_orders; pay jsonb; rsn text; d jsonb:=COALESCE(p_data,'{}'::jsonb); err text;
 vr boolean; caps text[]; extra jsonb:='{}'::jsonb; a am_assets; cat bigint; meter numeric; need_safety boolean; ev text;
 v_fail text; v_cause text; v_actc text; v_corr text; v_restored timestamptz; v_alh numeric; v_alc numeric; v_asc numeric; v_meter numeric; cal jsonb;
 dw am_downtime; lab_h numeric; lab_c numeric; lab_n int; sp_c numeric; sp_n int; n_ev int; cal_kind text; v_perf date; v_next date; v_res text;
 v_flag boolean; fin timestamptz; ndt bigint; closed int; pt am_plans; ev_at timestamptz;
BEGIN
 IF p_wo IS NULL OR p_expected_version IS NULL OR p_action IS NULL THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 IF p_action NOT IN('submit','approve','return','start','complete','verify','close','cancel','reopen') THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 rsn:=ami_wk_reason(p_reason,p_action IN('return','cancel','reopen'));
 PERFORM ami_wk_keys(d,CASE p_action WHEN 'start' THEN ARRAY['downtime'] WHEN 'cancel' THEN ARRAY['end_downtime'] WHEN 'reopen' THEN ARRAY['restart_downtime']
   WHEN 'complete' THEN ARRAY['failure_code','cause_code','action_code','corrective_action','restored_at','actual_labor_hours','actual_labor_cost',
     'actual_spares_cost','meter_reading','calibration'] ELSE ARRAY[]::text[] END);
 pay:=jsonb_build_object('wo',p_wo,'v',p_expected_version,'a',p_action,'r',rsn,'d',d);
 SELECT * INTO b FROM ami_begin(p_business,p_request,'wo_'||p_action,pay);
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 c:=b.o_ctx;
 SELECT * INTO w FROM am_work_orders WHERE id=p_wo AND business_id=p_business FOR UPDATE;
 IF NOT FOUND OR NOT ami_wk_visible(c,w) THEN RAISE EXCEPTION 'am_denied'; END IF;
 err:=ami_wk_auth(c,w,p_action);
 IF err IS NOT NULL THEN RAISE EXCEPTION '%',err; END IF;
 IF w.version<>p_expected_version THEN RAISE EXCEPTION 'am_stale_version'; END IF;
 IF w.status='CANCELLED' THEN RAISE EXCEPTION 'am_wo_cancelled_is_final'; END IF;
 vr:=ami_wk_pb(w,'wo.verify_required');
 IF p_action='close' AND w.status='COMPLETED' AND vr THEN RAISE EXCEPTION 'am_verification_required'; END IF;
 IF NOT ami_wk_state_ok(w,p_action,vr) THEN RAISE EXCEPTION 'am_wo_illegal_transition'; END IF;
 SELECT * INTO a FROM am_assets WHERE id=w.asset_id FOR UPDATE;
 cat:=a.category_id; caps:=ami_caps(c,w.site_id);

 IF p_action='submit' THEN
  IF a.status IN('retired','disposed') THEN RAISE EXCEPTION 'am_asset_retired'; END IF;
  n:=ami_wk_do_submit(w,p_request,false);

 ELSIF p_action='approve' THEN
  IF ami_wk_maker_checker(p_business) AND w.requested_by=c.user_id THEN RAISE EXCEPTION 'am_self_approval_denied'; END IF;
  UPDATE am_work_orders SET status='APPROVED',approved_by=c.user_id,approved_at=now(),responded_at=COALESCE(responded_at,now()),
    last_reason=rsn,version=version+1,updated_at=now() WHERE id=w.id RETURNING * INTO n;
  PERFORM ami_wk_hist(n,w.status,n.status,'approve',rsn,p_request);

 ELSIF p_action='return' THEN
  UPDATE am_work_orders SET status='DRAFT',submitted_at=NULL,last_reason=rsn,version=version+1,updated_at=now() WHERE id=w.id RETURNING * INTO n;
  PERFORM ami_wk_hist(n,w.status,n.status,'return',rsn,p_request);

 ELSIF p_action='start' THEN
  IF a.status IN('retired','disposed') THEN RAISE EXCEPTION 'am_asset_retired'; END IF;
  need_safety:=w.safety_critical OR COALESCE((SELECT k.safety_critical FROM am_categories k WHERE k.id=cat),false);
  IF need_safety AND ami_cfg_bool(p_business,w.site_id,cat,'wo.require_safety_ack') AND w.safety_ack_at IS NULL THEN RAISE EXCEPTION 'am_safety_ack_required'; END IF;
  v_flag:=ami_wk_bool(d,'downtime',false);
  IF v_flag AND w.kind='breakdown' THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
  SELECT m.current_reading INTO meter FROM am_meters m WHERE m.asset_id=w.asset_id AND m.active ORDER BY m.id LIMIT 1;
  UPDATE am_work_orders SET status='IN_PROGRESS',started_at=now(),started_by=c.user_id,responded_at=COALESCE(responded_at,now()),
    assigned_to=CASE WHEN assigned_to IS NULL AND NOT ('assign'=ANY(caps)) THEN c.user_id ELSE assigned_to END,
    meter_reading_at_start=meter,last_reason=rsn,version=version+1,updated_at=now() WHERE id=w.id RETURNING * INTO n;
  PERFORM ami_wk_hist(n,w.status,n.status,'start',rsn,p_request);
  IF w.kind<>'breakdown' THEN PERFORM ami_wk_set_asset(w.asset_id,'under_maintenance',ARRAY['active','idle','planned'],p_request); END IF;
  IF v_flag THEN
   IF EXISTS(SELECT 1 FROM am_downtime x WHERE x.asset_id=w.asset_id AND x.ended_at IS NULL) THEN RAISE EXCEPTION 'am_downtime_open_exists'; END IF;
   IF ami_wk_dt_overlap(w.asset_id,now(),NULL,NULL) THEN RAISE EXCEPTION 'am_downtime_overlap'; END IF;
   INSERT INTO am_downtime(tenant_id,business_id,asset_id,site_id,work_order_id,kind,reason_code,started_at,started_by)
   VALUES(w.tenant_id,p_business,w.asset_id,w.site_id,w.id,'planned',
     (SELECT code FROM am_codes WHERE business_id=p_business AND kind='downtime_reason' AND code='PM' AND active),now(),c.user_id) RETURNING id INTO ndt;
   PERFORM ami_log(c.tenant_id,p_business,'downtime',ndt::text,'downtime.start',NULL,jsonb_build_object('kind','planned','work_order_id',w.id),'planned work started',p_request);
   extra:=jsonb_build_object('downtime_id',ndt);
  END IF;

 ELSIF p_action='complete' THEN
  v_fail:=ami_wk_code(p_business,'failure',ami_wk_re(d,'failure_code','^[A-Za-z0-9][A-Za-z0-9_-]{0,23}$',false));
  v_cause:=ami_wk_code(p_business,'cause',ami_wk_re(d,'cause_code','^[A-Za-z0-9][A-Za-z0-9_-]{0,23}$',false));
  v_actc:=ami_wk_code(p_business,'action',ami_wk_re(d,'action_code','^[A-Za-z0-9][A-Za-z0-9_-]{0,23}$',false));
  v_corr:=ami_wk_txt(d,'corrective_action',1,2000,false);
  v_alh:=ami_wk_num(d,'actual_labor_hours',0,100000,false); v_alc:=ami_wk_num(d,'actual_labor_cost',0,1e12,false);
  v_asc:=ami_wk_num(d,'actual_spares_cost',0,1e12,false); v_meter:=ami_wk_num(d,'meter_reading',0,1e15,false);
  v_restored:=ami_wk_ts(d,'restored_at',false);
  IF v_restored IS NOT NULL AND w.kind<>'breakdown' THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
  -- cause code for breakdown / corrective work
  IF w.kind IN('breakdown','corrective') AND ami_wk_pb(w,'wo.require_cause_code') AND COALESCE(v_cause,w.cause_code) IS NULL THEN RAISE EXCEPTION 'am_cause_required'; END IF;
  -- checklist
  IF ami_wk_pb(w,'wo.require_checklist_complete') THEN
   IF EXISTS(SELECT 1 FROM am_wo_checklist x WHERE x.work_order_id=w.id AND x.required AND x.result NOT IN('pass','fail')) THEN RAISE EXCEPTION 'am_checklist_incomplete'; END IF;
   IF EXISTS(SELECT 1 FROM am_wo_checklist x WHERE x.work_order_id=w.id AND x.required AND x.result='fail' AND btrim(COALESCE(x.note,''))='') THEN RAISE EXCEPTION 'am_checklist_incomplete'; END IF;
  END IF;
  IF EXISTS(SELECT 1 FROM am_wo_checklist x WHERE x.work_order_id=w.id AND x.kind='measure' AND x.result='pass' AND x.value IS NOT NULL
     AND ((x.min_value IS NOT NULL AND x.value<x.min_value) OR (x.max_value IS NOT NULL AND x.value>x.max_value))) THEN RAISE EXCEPTION 'am_measure_out_of_range'; END IF;
  -- evidence
  ev:=ami_wk_pt(w,'wo.evidence_required_for');
  IF ev='all' OR (ev='breakdown' AND w.kind='breakdown') THEN
   SELECT count(*) INTO n_ev FROM am_wo_attachments x WHERE x.work_order_id=w.id;
   IF n_ev=0 THEN RAISE EXCEPTION 'am_evidence_required'; END IF;
  END IF;
  -- actual labour / spares (explicit > recorded lines > what is already on the WO)
  SELECT COALESCE(sum(hours),0),COALESCE(sum(hours*COALESCE(rate,0)),0),count(*) INTO lab_h,lab_c,lab_n FROM am_wo_labor WHERE work_order_id=w.id AND phase='actual';
  SELECT COALESCE(sum(qty*COALESCE(unit_cost,0)),0),count(*) INTO sp_c,sp_n FROM am_wo_spares WHERE work_order_id=w.id AND phase='actual';
  v_alh:=COALESCE(v_alh,CASE WHEN lab_n>0 THEN lab_h END,w.actual_labor_hours);
  v_alc:=COALESCE(v_alc,CASE WHEN lab_n>0 THEN lab_c END,w.actual_labor_cost);
  v_asc:=COALESCE(v_asc,CASE WHEN sp_n>0 THEN sp_c END,w.actual_spares_cost);
  IF ami_wk_pb(w,'wo.require_actual_labor') AND COALESCE(v_alh,0)<=0 THEN RAISE EXCEPTION 'am_labor_required'; END IF;
  -- calibration payload
  cal:=d->'calibration';
  IF cal IS NOT NULL AND jsonb_typeof(cal)='null' THEN cal:=NULL; END IF;
  IF cal IS NULL AND w.kind='calibration' THEN RAISE EXCEPTION 'am_calibration_required'; END IF;
  IF cal IS NOT NULL THEN
   IF w.kind NOT IN('calibration','inspection') THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
   PERFORM ami_wk_keys(cal,ARRAY['result','next_due_on','certificate_ref','standard_ref','vendor','note','performed_on']);
   v_res:=ami_wk_txt(cal,'result',1,10,true);
   IF v_res NOT IN('pass','fail','adjusted') THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
   v_perf:=COALESCE(ami_wk_date(cal,'performed_on',false),ami_today(p_business));
   IF v_perf>ami_today(p_business) THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
   v_next:=ami_wk_date(cal,'next_due_on',false);
   IF v_next IS NOT NULL AND v_next<v_perf THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
   PERFORM ami_wk_txt(cal,'certificate_ref',1,80,false); PERFORM ami_wk_txt(cal,'standard_ref',1,80,false);
   PERFORM ami_wk_txt(cal,'vendor',1,120,false); PERFORM ami_wk_txt(cal,'note',1,500,false);
  END IF;
  -- breakdown restoration time
  SELECT * INTO dw FROM am_downtime WHERE work_order_id=w.id AND kind='breakdown' AND ended_at IS NULL ORDER BY id LIMIT 1;
  ev_at:=now();
  IF v_restored IS NOT NULL THEN
   ev_at:=ami_wk_clamp(v_restored,'am_downtime_end_invalid');
   IF dw.id IS NOT NULL AND ev_at<dw.started_at THEN RAISE EXCEPTION 'am_downtime_end_invalid'; END IF;
  END IF;
  IF v_meter IS NULL THEN SELECT m.current_reading INTO v_meter FROM am_meters m WHERE m.asset_id=w.asset_id AND m.active ORDER BY m.id LIMIT 1; END IF;
  UPDATE am_work_orders SET status='COMPLETED',completed_at=now(),completed_by=c.user_id,
    failure_code=COALESCE(v_fail,failure_code),cause_code=COALESCE(v_cause,cause_code),action_code=COALESCE(v_actc,action_code),
    corrective_action=COALESCE(v_corr,corrective_action),actual_labor_hours=v_alh,actual_labor_cost=v_alc,actual_spares_cost=v_asc,
    meter_reading_at_end=v_meter,last_reason=rsn,version=version+1,updated_at=now() WHERE id=w.id RETURNING * INTO n;
  PERFORM ami_wk_hist(n,w.status,n.status,'complete',rsn,p_request);
  IF cal IS NOT NULL THEN
   cal_kind:=CASE w.kind WHEN 'calibration' THEN 'calibration' ELSE 'inspection' END;
   IF w.plan_target_id IS NOT NULL THEN
    SELECT p.* INTO pt FROM am_plan_targets t JOIN am_plans p ON p.id=t.plan_id WHERE t.id=w.plan_target_id;
    IF pt.plan_type IN('calibration','inspection','certification') THEN cal_kind:=pt.plan_type; END IF;
   END IF;
   INSERT INTO am_cal_records(tenant_id,business_id,asset_id,work_order_id,plan_kind,performed_on,next_due_on,result,certificate_ref,standard_ref,vendor,note,recorded_by)
   VALUES(w.tenant_id,p_business,w.asset_id,w.id,cal_kind,v_perf,v_next,v_res,ami_wk_txt(cal,'certificate_ref',1,80,false),
     ami_wk_txt(cal,'standard_ref',1,80,false),ami_wk_txt(cal,'vendor',1,120,false),ami_wk_txt(cal,'note',1,500,false),c.user_id);
  END IF;
  closed:=ami_wk_close_windows(w.id,ARRAY['planned'],now(),p_request);
  IF w.kind='breakdown' AND ami_wk_pt(w,'downtime.end_on')='completed' THEN
   closed:=closed+ami_wk_close_windows(w.id,ARRAY['breakdown'],ev_at,p_request); END IF;
  PERFORM ami_wk_restore_asset(w.asset_id,p_request);
  IF w.plan_target_id IS NOT NULL THEN PERFORM ami_complete_target(w.plan_target_id,ami_today(p_business),v_meter); END IF;
  extra:=jsonb_build_object('downtime_windows_closed',closed);

 ELSIF p_action='verify' THEN
  IF ami_wk_maker_checker(p_business) AND w.completed_by=c.user_id THEN RAISE EXCEPTION 'am_self_verification_denied'; END IF;
  UPDATE am_work_orders SET status='VERIFIED',verified_by=c.user_id,verified_at=now(),last_reason=rsn,version=version+1,updated_at=now() WHERE id=w.id RETURNING * INTO n;
  PERFORM ami_wk_hist(n,w.status,n.status,'verify',rsn,p_request);
  IF w.kind='breakdown' AND ami_wk_pt(w,'downtime.end_on')='verified' THEN
   closed:=ami_wk_close_windows(w.id,ARRAY['breakdown'],now(),p_request);
   PERFORM ami_wk_restore_asset(w.asset_id,p_request); extra:=jsonb_build_object('downtime_windows_closed',closed); END IF;

 ELSIF p_action='close' THEN
  UPDATE am_work_orders SET status='CLOSED',closed_by=c.user_id,closed_at=now(),last_reason=rsn,version=version+1,updated_at=now() WHERE id=w.id RETURNING * INTO n;
  PERFORM ami_wk_hist(n,w.status,n.status,'close',rsn,p_request);
  closed:=ami_wk_close_windows(w.id,ARRAY['planned','breakdown'],now(),p_request);
  IF closed>0 THEN PERFORM ami_wk_restore_asset(w.asset_id,p_request); extra:=jsonb_build_object('downtime_windows_closed',closed); END IF;

 ELSIF p_action='cancel' THEN
  v_flag:=ami_wk_bool(d,'end_downtime',false);
  UPDATE am_work_orders SET status='CANCELLED',cancel_reason=rsn,last_reason=rsn,version=version+1,updated_at=now() WHERE id=w.id RETURNING * INTO n;
  PERFORM ami_wk_hist(n,w.status,n.status,'cancel',rsn,p_request);
  -- planned windows always end with the WO; a breakdown outage stays OPEN (it still exists) unless end_downtime=true
  closed:=ami_wk_close_windows(w.id,CASE WHEN v_flag THEN ARRAY['planned','breakdown','other'] ELSE ARRAY['planned'] END,now(),p_request);
  PERFORM ami_wk_restore_asset(w.asset_id,p_request);
  extra:=jsonb_build_object('downtime_windows_closed',closed,'downtime_left_open',EXISTS(SELECT 1 FROM am_downtime x WHERE x.work_order_id=w.id AND x.ended_at IS NULL));

 ELSIF p_action='reopen' THEN
  IF NOT ami_wk_reopen_ok(w) THEN RAISE EXCEPTION 'am_reopen_window_expired'; END IF;
  IF a.status IN('retired','disposed') THEN RAISE EXCEPTION 'am_asset_retired'; END IF;
  v_flag:=ami_wk_bool(d,'restart_downtime',false);
  IF v_flag AND w.kind<>'breakdown' THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
  BEGIN
   UPDATE am_work_orders SET status='IN_PROGRESS',reopen_count=reopen_count+1,verified_by=NULL,verified_at=NULL,closed_by=NULL,closed_at=NULL,
     last_reason=rsn,version=version+1,updated_at=now() WHERE id=w.id RETURNING * INTO n;
  EXCEPTION WHEN unique_violation THEN RAISE EXCEPTION 'am_target_has_open_wo'; END;
  PERFORM ami_wk_hist(n,w.status,n.status,'reopen',rsn,p_request);
  IF v_flag THEN
   IF EXISTS(SELECT 1 FROM am_downtime x WHERE x.asset_id=w.asset_id AND x.ended_at IS NULL) THEN RAISE EXCEPTION 'am_downtime_open_exists'; END IF;
   IF ami_wk_dt_overlap(w.asset_id,now(),NULL,NULL) THEN RAISE EXCEPTION 'am_downtime_overlap'; END IF;
   INSERT INTO am_downtime(tenant_id,business_id,asset_id,site_id,work_order_id,kind,reason_code,started_at,started_by)
   VALUES(w.tenant_id,p_business,w.asset_id,w.site_id,w.id,'breakdown',
     (SELECT code FROM am_codes WHERE business_id=p_business AND kind='downtime_reason' AND code='BREAKDOWN' AND active),now(),c.user_id) RETURNING id INTO ndt;
   PERFORM ami_log(c.tenant_id,p_business,'downtime',ndt::text,'downtime.start',NULL,jsonb_build_object('kind','breakdown','work_order_id',w.id,'reopened',true),rsn,p_request);
   PERFORM ami_wk_set_asset(w.asset_id,'breakdown',ARRAY['active','idle','planned','under_maintenance'],p_request);
   extra:=jsonb_build_object('downtime_id',ndt);
  ELSE
   PERFORM ami_wk_set_asset(w.asset_id,'under_maintenance',ARRAY['active','idle','planned'],p_request);
  END IF;
  PERFORM ami_log(c.tenant_id,p_business,'work_order',w.id::text,'wo.reopen_exception',ami_wk_state(w),ami_wk_state(n),rsn,p_request);
 END IF;

 PERFORM ami_log(c.tenant_id,p_business,'work_order',w.id::text,'wo.'||p_action,ami_wk_state(w),ami_wk_state(n),rsn,p_request);
 RETURN ami_finish(p_business,c.tenant_id,p_request,'wo_'||p_action,pay,jsonb_build_object('status','applied','id',n.id,'wo_no',n.wo_no,
   'wo_status',n.status,'version',n.version,'action',p_action,'auto_approved',(n.approved_at IS NOT NULL AND n.approved_by IS NULL))||extra);
END$$;

-- ===================== execution records: checklist / labour / spares / attachments / safety =====================
CREATE FUNCTION c10_demo.am_wo_checklist_result_v1(p_business bigint,p_request text,p_wo bigint,p_seq int,p_result text,p_value numeric,p_note text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c am_ctx_t; w am_work_orders; i am_wo_checklist; n am_wo_checklist; pay jsonb; v_note text:=NULLIF(btrim(COALESCE(p_note,'')),'');
BEGIN
 IF p_wo IS NULL OR p_seq IS NULL OR p_seq NOT BETWEEN 1 AND 200 OR p_result IS NULL OR p_result NOT IN('pending','pass','fail','na') THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 IF v_note IS NOT NULL AND length(v_note)>500 THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 IF p_value IS NOT NULL AND abs(p_value)>1e12 THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 pay:=jsonb_build_object('wo',p_wo,'seq',p_seq,'res',p_result,'val',p_value,'note',v_note);
 SELECT * INTO b FROM ami_begin(p_business,p_request,'wo_checklist',pay);
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 c:=b.o_ctx;
 SELECT * INTO w FROM am_work_orders WHERE id=p_wo AND business_id=p_business FOR UPDATE;
 IF NOT FOUND OR NOT ami_wk_visible(c,w) THEN RAISE EXCEPTION 'am_denied'; END IF;
 IF ami_wk_auth(c,w,'work') IS NOT NULL THEN RAISE EXCEPTION 'am_not_permitted'; END IF;
 IF w.status='CANCELLED' THEN RAISE EXCEPTION 'am_wo_cancelled_is_final'; END IF;
 IF w.status<>'IN_PROGRESS' THEN RAISE EXCEPTION 'am_wo_not_editable'; END IF;
 SELECT * INTO i FROM am_wo_checklist WHERE work_order_id=w.id AND seq=p_seq FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 IF p_result='na' AND i.required THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 IF i.kind='measure' THEN
  IF p_result IN('pass','fail') AND p_value IS NULL THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
  IF p_result='pass' AND ((i.min_value IS NOT NULL AND p_value<i.min_value) OR (i.max_value IS NOT NULL AND p_value>i.max_value)) THEN RAISE EXCEPTION 'am_measure_out_of_range'; END IF;
 ELSIF p_value IS NOT NULL THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 UPDATE am_wo_checklist SET result=p_result,value=p_value,note=v_note,done_by=CASE WHEN p_result='pending' THEN NULL ELSE c.user_id END,
   done_at=CASE WHEN p_result='pending' THEN NULL ELSE now() END WHERE id=i.id RETURNING * INTO n;
 UPDATE am_work_orders SET updated_at=now() WHERE id=w.id;
 PERFORM ami_log(c.tenant_id,p_business,'work_order',w.id::text,'wo.checklist',jsonb_build_object('seq',i.seq,'result',i.result,'value',i.value,'note',i.note),
   jsonb_build_object('seq',n.seq,'result',n.result,'value',n.value,'note',n.note),NULL,p_request);
 RETURN ami_finish(p_business,c.tenant_id,p_request,'wo_checklist',pay,jsonb_build_object('status','applied','id',w.id,'seq',n.seq,'result',n.result));
END$$;

CREATE FUNCTION c10_demo.am_wo_add_labor_v1(p_business bigint,p_request text,p_wo bigint,p_data jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c am_ctx_t; w am_work_orders; pay jsonb; v_kind text; v_ref text; v_h numeric; v_rate numeric; v_note text; v_phase text; lid bigint;
BEGIN
 IF p_wo IS NULL THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 PERFORM ami_wk_keys(p_data,ARRAY['labor_kind','worker_ref','hours','rate','note','phase']);
 v_kind:=COALESCE(ami_wk_txt(p_data,'labor_kind',1,12,false),'internal'); v_phase:=COALESCE(ami_wk_txt(p_data,'phase',1,10,false),'actual');
 IF v_kind NOT IN('internal','contractor') OR v_phase NOT IN('estimate','actual') THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 v_ref:=ami_wk_re(p_data,'worker_ref','^[A-Za-z0-9][A-Za-z0-9._/ -]{0,39}$',false);
 v_h:=ami_wk_num(p_data,'hours',0.01,1000,true); IF v_h<>round(v_h,2) THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 v_rate:=ami_wk_num(p_data,'rate',0,1e9,false); v_note:=ami_wk_txt(p_data,'note',1,300,false);
 IF v_rate IS NOT NULL AND v_rate<>round(v_rate,2) THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 pay:=jsonb_build_object('wo',p_wo,'d',p_data);
 SELECT * INTO b FROM ami_begin(p_business,p_request,'wo_labor',pay);
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 c:=b.o_ctx;
 SELECT * INTO w FROM am_work_orders WHERE id=p_wo AND business_id=p_business FOR UPDATE;
 IF NOT FOUND OR NOT ami_wk_visible(c,w) THEN RAISE EXCEPTION 'am_denied'; END IF;
 IF NOT (ami_wk_auth(c,w,'work') IS NULL OR (v_phase='estimate' AND ami_wk_auth(c,w,'edit') IS NULL)) THEN RAISE EXCEPTION 'am_not_permitted'; END IF;
 IF w.status='CANCELLED' THEN RAISE EXCEPTION 'am_wo_cancelled_is_final'; END IF;
 IF NOT ((v_phase='actual' AND w.status='IN_PROGRESS') OR (v_phase='estimate' AND w.status IN('DRAFT','SUBMITTED','APPROVED','IN_PROGRESS'))) THEN RAISE EXCEPTION 'am_wo_not_editable'; END IF;
 INSERT INTO am_wo_labor(tenant_id,business_id,work_order_id,labor_kind,worker_ref,hours,rate,note,phase,recorded_by)
 VALUES(w.tenant_id,p_business,w.id,v_kind,v_ref,v_h,v_rate,v_note,v_phase,c.user_id) RETURNING id INTO lid;
 PERFORM ami_log(c.tenant_id,p_business,'work_order',w.id::text,'wo.labor',NULL,jsonb_build_object('labor_id',lid,'hours',v_h,'rate',v_rate,'phase',v_phase,'kind',v_kind),NULL,p_request);
 RETURN ami_finish(p_business,c.tenant_id,p_request,'wo_labor',pay,jsonb_build_object('status','applied','id',lid,'work_order_id',w.id));
END$$;

CREATE FUNCTION c10_demo.am_wo_add_spares_v1(p_business bigint,p_request text,p_wo bigint,p_data jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c am_ctx_t; w am_work_orders; pay jsonb; v_ref text; v_desc text; v_phase text; v_qty numeric; v_cost numeric; sid bigint;
BEGIN
 IF p_wo IS NULL THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 PERFORM ami_wk_keys(p_data,ARRAY['item_ref','description','phase','qty','unit_cost']);   -- stock_effect is NOT accepted: lines are informational
 v_ref:=ami_wk_re(p_data,'item_ref','^[A-Za-z0-9][A-Za-z0-9._/-]{0,39}$',false); v_desc:=ami_wk_txt(p_data,'description',2,200,true);
 v_phase:=COALESCE(ami_wk_txt(p_data,'phase',1,10,false),'estimate');
 IF v_phase NOT IN('estimate','actual') THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 v_qty:=ami_wk_num(p_data,'qty',0.001,1e9,true); IF v_qty<>round(v_qty,3) THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 v_cost:=ami_wk_num(p_data,'unit_cost',0,1e12,false); IF v_cost IS NOT NULL AND v_cost<>round(v_cost,2) THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 pay:=jsonb_build_object('wo',p_wo,'d',p_data);
 SELECT * INTO b FROM ami_begin(p_business,p_request,'wo_spares',pay);
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 c:=b.o_ctx;
 SELECT * INTO w FROM am_work_orders WHERE id=p_wo AND business_id=p_business FOR UPDATE;
 IF NOT FOUND OR NOT ami_wk_visible(c,w) THEN RAISE EXCEPTION 'am_denied'; END IF;
 IF NOT (ami_wk_auth(c,w,'work') IS NULL OR (v_phase='estimate' AND ami_wk_auth(c,w,'edit') IS NULL)) THEN RAISE EXCEPTION 'am_not_permitted'; END IF;
 IF w.status='CANCELLED' THEN RAISE EXCEPTION 'am_wo_cancelled_is_final'; END IF;
 IF NOT ((v_phase='actual' AND w.status='IN_PROGRESS') OR (v_phase='estimate' AND w.status IN('DRAFT','SUBMITTED','APPROVED','IN_PROGRESS'))) THEN RAISE EXCEPTION 'am_wo_not_editable'; END IF;
 INSERT INTO am_wo_spares(tenant_id,business_id,work_order_id,item_ref,description,phase,qty,unit_cost,stock_effect,recorded_by)
 VALUES(w.tenant_id,p_business,w.id,v_ref,v_desc,v_phase,v_qty,v_cost,false,c.user_id) RETURNING id INTO sid;
 PERFORM ami_log(c.tenant_id,p_business,'work_order',w.id::text,'wo.spares',NULL,jsonb_build_object('spares_id',sid,'qty',v_qty,'unit_cost',v_cost,'phase',v_phase,'stock_effect',false),NULL,p_request);
 RETURN ami_finish(p_business,c.tenant_id,p_request,'wo_spares',pay,jsonb_build_object('status','applied','id',sid,'work_order_id',w.id,'stock_effect',false));
END$$;

CREATE FUNCTION c10_demo.am_wo_add_attachment_v1(p_business bigint,p_request text,p_wo bigint,p_data jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c am_ctx_t; w am_work_orders; pay jsonb; v_name text; v_mime text; v_size numeric; v_sha text; v_ref text; v_kind text; v_cap text; aid bigint;
BEGIN
 IF p_wo IS NULL THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 PERFORM ami_wk_keys(p_data,ARRAY['file_name','mime','size_bytes','sha256','storage_ref','kind','caption']);
 v_name:=ami_wk_re(p_data,'file_name','^[A-Za-z0-9][A-Za-z0-9._ -]{0,99}$',true);
 v_mime:=ami_wk_txt(p_data,'mime',1,40,true);
 IF v_mime NOT IN('image/jpeg','image/png','image/webp','application/pdf','text/plain') THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 v_size:=ami_wk_num(p_data,'size_bytes',1,26214400,true); IF v_size<>trunc(v_size) THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 v_sha:=ami_wk_re(p_data,'sha256','^[0-9a-f]{64}$',true);
 v_ref:=ami_wk_re(p_data,'storage_ref','^[A-Za-z0-9][A-Za-z0-9._/-]{0,199}$',true);
 -- metadata only: no traversal, no absolute / URL-like / hidden-segment refs
 IF v_ref ~ '(^|/)\.\.?(/|$)' OR v_ref LIKE '%//%' OR v_ref ~ '(^|/)\.' OR v_ref ~* '^[a-z][a-z0-9+.-]*:' OR v_name LIKE '%..%' THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 v_kind:=COALESCE(ami_wk_txt(p_data,'kind',1,12,false),'photo');
 IF v_kind NOT IN('photo','document','certificate','report') THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 v_cap:=ami_wk_txt(p_data,'caption',1,200,false);
 pay:=jsonb_build_object('wo',p_wo,'d',p_data);
 SELECT * INTO b FROM ami_begin(p_business,p_request,'wo_attach',pay);
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 c:=b.o_ctx;
 SELECT * INTO w FROM am_work_orders WHERE id=p_wo AND business_id=p_business FOR UPDATE;
 IF NOT FOUND OR NOT ami_wk_visible(c,w) THEN RAISE EXCEPTION 'am_denied'; END IF;
 IF ami_wk_auth(c,w,'attachment') IS NOT NULL THEN RAISE EXCEPTION 'am_not_permitted'; END IF;
 IF w.status='CANCELLED' THEN RAISE EXCEPTION 'am_wo_cancelled_is_final'; END IF;
 IF w.status NOT IN('DRAFT','SUBMITTED','APPROVED','IN_PROGRESS','COMPLETED','VERIFIED') THEN RAISE EXCEPTION 'am_wo_not_editable'; END IF;
 BEGIN
  INSERT INTO am_wo_attachments(tenant_id,business_id,work_order_id,file_name,mime,size_bytes,sha256,storage_ref,kind,caption,recorded_by)
  VALUES(w.tenant_id,p_business,w.id,v_name,v_mime,v_size::bigint,v_sha,v_ref,v_kind,v_cap,c.user_id) RETURNING id INTO aid;
 EXCEPTION WHEN unique_violation THEN RAISE EXCEPTION 'am_duplicate_attachment'; END;
 PERFORM ami_log(c.tenant_id,p_business,'work_order',w.id::text,'wo.attachment',NULL,jsonb_build_object('attachment_id',aid,'file_name',v_name,'sha256',v_sha,'kind',v_kind),NULL,p_request);
 RETURN ami_finish(p_business,c.tenant_id,p_request,'wo_attach',pay,jsonb_build_object('status','applied','id',aid,'work_order_id',w.id));
END$$;

CREATE FUNCTION c10_demo.am_acknowledge_safety_v1(p_business bigint,p_request text,p_wo bigint) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c am_ctx_t; w am_work_orders; pay jsonb; fresh boolean:=false;
BEGIN
 IF p_wo IS NULL THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 pay:=jsonb_build_object('wo',p_wo);
 SELECT * INTO b FROM ami_begin(p_business,p_request,'wo_safety',pay);
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 c:=b.o_ctx;
 SELECT * INTO w FROM am_work_orders WHERE id=p_wo AND business_id=p_business FOR UPDATE;
 IF NOT FOUND OR NOT ami_wk_visible(c,w) THEN RAISE EXCEPTION 'am_denied'; END IF;
 IF ami_wk_auth(c,w,'start') IS NOT NULL AND ami_wk_auth(c,w,'work') IS NOT NULL THEN RAISE EXCEPTION 'am_not_permitted'; END IF;
 IF w.status='CANCELLED' THEN RAISE EXCEPTION 'am_wo_cancelled_is_final'; END IF;
 IF w.status NOT IN('APPROVED','IN_PROGRESS') THEN RAISE EXCEPTION 'am_wo_illegal_transition'; END IF;
 IF w.safety_ack_at IS NULL THEN
  UPDATE am_work_orders SET safety_ack_by=c.user_id,safety_ack_at=now(),updated_at=now() WHERE id=w.id RETURNING * INTO w; fresh:=true;
  PERFORM ami_wk_hist(w,w.status,w.status,'safety_ack',NULL,p_request);
  PERFORM ami_log(c.tenant_id,p_business,'work_order',w.id::text,'wo.safety_ack',NULL,jsonb_build_object('safety_ack_by',c.user_id,'safety_ack_at',w.safety_ack_at),NULL,p_request);
 END IF;
 RETURN ami_finish(p_business,c.tenant_id,p_request,'wo_safety',pay,jsonb_build_object('status','applied','id',w.id,'safety_ack_at',w.safety_ack_at,'newly_acknowledged',fresh));
END$$;

-- ===================== merge =====================
CREATE FUNCTION c10_demo.am_merge_work_orders_v1(p_business bigint,p_request text,p_keep bigint,p_merge bigint,p_reason text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c am_ctx_t; k am_work_orders; m am_work_orders; nm am_work_orders; nk am_work_orders; pay jsonb; rsn text; moved int;
BEGIN
 IF p_keep IS NULL OR p_merge IS NULL OR p_keep=p_merge THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 rsn:=ami_wk_reason(p_reason,true);
 pay:=jsonb_build_object('k',p_keep,'m',p_merge,'r',rsn);
 SELECT * INTO b FROM ami_begin(p_business,p_request,'wo_merge',pay);
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 c:=b.o_ctx;
 SELECT * INTO k FROM am_work_orders WHERE id=LEAST(p_keep,p_merge) AND business_id=p_business FOR UPDATE;
 SELECT * INTO m FROM am_work_orders WHERE id=GREATEST(p_keep,p_merge) AND business_id=p_business FOR UPDATE;
 IF p_keep>p_merge THEN SELECT * INTO nk FROM am_work_orders WHERE id=p_keep; k:=nk; SELECT * INTO m FROM am_work_orders WHERE id=p_merge; END IF;
 IF k.id IS NULL OR m.id IS NULL OR k.id<>p_keep OR m.id<>p_merge THEN RAISE EXCEPTION 'am_denied'; END IF;
 IF NOT ami_wk_visible(c,k) OR NOT ami_wk_visible(c,m) THEN RAISE EXCEPTION 'am_denied'; END IF;
 IF ami_wk_auth(c,k,'merge') IS NOT NULL OR ami_wk_auth(c,m,'merge') IS NOT NULL THEN RAISE EXCEPTION 'am_not_permitted'; END IF;
 IF k.status='CANCELLED' OR m.status='CANCELLED' THEN RAISE EXCEPTION 'am_wo_cancelled_is_final'; END IF;
 IF k.asset_id<>m.asset_id THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 IF k.status NOT IN('DRAFT','SUBMITTED','APPROVED','IN_PROGRESS') OR m.status NOT IN('DRAFT','SUBMITTED','APPROVED','IN_PROGRESS') THEN RAISE EXCEPTION 'am_wo_illegal_transition'; END IF;
 UPDATE am_work_orders SET status='CANCELLED',merged_into_id=k.id,cancel_reason='merged into '||k.wo_no||': '||rsn,last_reason=rsn,version=version+1,updated_at=now()
  WHERE id=m.id RETURNING * INTO nm;
 UPDATE am_work_orders SET version=version+1,updated_at=now() WHERE id=k.id RETURNING * INTO nk;
 UPDATE am_downtime SET work_order_id=k.id WHERE work_order_id=m.id; GET DIAGNOSTICS moved=ROW_COUNT;
 PERFORM ami_wk_hist(nm,m.status,'CANCELLED','merge',rsn,p_request);
 PERFORM ami_wk_hist(nk,k.status,k.status,'merge_in','absorbed '||m.wo_no||': '||rsn,p_request);
 PERFORM ami_wk_restore_asset(k.asset_id,p_request);
 PERFORM ami_log(c.tenant_id,p_business,'work_order',m.id::text,'wo.merge',ami_wk_state(m),ami_wk_state(nm)||jsonb_build_object('merged_into_id',k.id),rsn,p_request);
 PERFORM ami_log(c.tenant_id,p_business,'work_order',k.id::text,'wo.merge_in',ami_wk_state(k),ami_wk_state(nk)||jsonb_build_object('absorbed_id',m.id),rsn,p_request);
 RETURN ami_finish(p_business,c.tenant_id,p_request,'wo_merge',pay,jsonb_build_object('status','applied','keep_id',k.id,'merged_id',m.id,'keep_version',nk.version,
   'merged_version',nm.version,'downtime_windows_relinked',moved));
END$$;

-- ===================== breakdown reporting & downtime windows =====================
CREATE FUNCTION c10_demo.am_report_breakdown_v1(p_business bigint,p_request text,p_asset bigint,p_data jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c am_ctx_t; a am_assets; w am_work_orders; dw am_downtime; d jsonb:=COALESCE(p_data,'{}'::jsonb); pay jsonb; wid bigint; ex bigint; ex_st text;
 v_title text; v_desc text; v_prio text; v_occ timestamptz; v_impact text; v_fail text; v_rc text; v_chk text; adopt boolean:=false; did bigint; safety boolean;
BEGIN
 IF p_asset IS NULL THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 PERFORM ami_wk_keys(d,ARRAY['title','description','priority','occurred_at','impact','failure_code','reason_code','checklist_code']);
 v_title:=ami_wk_txt(d,'title',3,160,false); v_desc:=ami_wk_txt(d,'description',1,2000,false);
 v_prio:=COALESCE(ami_wk_txt(d,'priority',1,10,false),'high');
 IF v_prio NOT IN('low','medium','high','critical') THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 v_occ:=ami_wk_ts(d,'occurred_at',false); v_impact:=ami_wk_txt(d,'impact',1,500,false);
 v_fail:=ami_wk_re(d,'failure_code','^[A-Za-z0-9][A-Za-z0-9_-]{0,23}$',false); v_rc:=ami_wk_re(d,'reason_code','^[A-Za-z0-9][A-Za-z0-9_-]{0,23}$',false);
 v_chk:=ami_wk_re(d,'checklist_code','^[A-Z0-9][A-Z0-9_-]{0,31}$',false);
 pay:=jsonb_build_object('asset',p_asset,'d',d);
 SELECT * INTO b FROM ami_begin(p_business,p_request,'breakdown',pay);
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 c:=b.o_ctx;
 SELECT * INTO a FROM am_assets WHERE id=p_asset AND business_id=p_business AND tenant_id=c.tenant_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'am_denied'; END IF;
 PERFORM ami_wk_gate(c,a.site_id,'report');
 IF a.status IN('retired','disposed') THEN RAISE EXCEPTION 'am_asset_retired'; END IF;
 v_occ:=ami_wk_clamp(v_occ,'am_invalid_input');
 v_fail:=ami_wk_code(p_business,'failure',v_fail);
 v_rc:=COALESCE(ami_wk_dt_code(p_business,v_rc),(SELECT code FROM am_codes WHERE business_id=p_business AND kind='downtime_reason' AND code='BREAKDOWN' AND active));
 -- one OPEN breakdown per asset (serialised by the per-business lock + asset row lock + unique open-window index)
 SELECT x.id INTO ex FROM am_work_orders x WHERE x.asset_id=a.id AND x.kind='breakdown' AND x.status IN('DRAFT','SUBMITTED','APPROVED','IN_PROGRESS') ORDER BY x.id LIMIT 1;
 IF ex IS NOT NULL THEN RAISE EXCEPTION 'am_breakdown_already_open' USING DETAIL=jsonb_build_object('work_order_id',ex)::text; END IF;
 SELECT * INTO dw FROM am_downtime WHERE asset_id=a.id AND ended_at IS NULL;
 IF FOUND THEN
  IF dw.kind<>'breakdown' THEN RAISE EXCEPTION 'am_downtime_open_exists'; END IF;
  SELECT x.status INTO ex_st FROM am_work_orders x WHERE x.id=dw.work_order_id;
  IF ex_st IN('COMPLETED','VERIFIED') THEN RAISE EXCEPTION 'am_breakdown_already_open' USING DETAIL=jsonb_build_object('work_order_id',dw.work_order_id)::text; END IF;
  adopt:=true;   -- orphan outage (its WO was cancelled / closed): the new report adopts the still-open window
 ELSIF ami_wk_dt_overlap(a.id,v_occ,NULL,NULL) THEN RAISE EXCEPTION 'am_downtime_overlap'; END IF;
 wid:=ami_create_wo(c,p_request,a.id,'breakdown',COALESCE(v_title,'Breakdown: '||left(a.name,120)),v_desc,v_prio,'breakdown_report',NULL,NULL,v_chk,'{}'::jsonb);
 SELECT safety_critical INTO safety FROM am_categories WHERE id=a.category_id;
 UPDATE am_work_orders SET failure_code=v_fail,safety_critical=(safety_critical OR COALESCE(safety,false)) WHERE id=wid RETURNING * INTO w;
 IF adopt THEN UPDATE am_downtime SET work_order_id=wid WHERE id=dw.id; did:=dw.id;
 ELSE
  BEGIN
   INSERT INTO am_downtime(tenant_id,business_id,asset_id,site_id,work_order_id,kind,reason_code,impact,started_at,started_by)
   VALUES(a.tenant_id,p_business,a.id,a.site_id,wid,'breakdown',v_rc,v_impact,v_occ,c.user_id) RETURNING id INTO did;
  EXCEPTION WHEN unique_violation THEN RAISE EXCEPTION 'am_breakdown_already_open'; END;
 END IF;
 PERFORM ami_wk_set_asset(a.id,'breakdown',ARRAY['active','idle','planned','under_maintenance'],p_request);
 w:=ami_wk_do_submit(w,p_request,true);
 PERFORM ami_log(c.tenant_id,p_business,'downtime',did::text,CASE WHEN adopt THEN 'downtime.adopt' ELSE 'downtime.start' END,NULL,
   jsonb_build_object('kind','breakdown','work_order_id',wid,'started_at',v_occ,'asset_id',a.id),'breakdown reported',p_request);
 PERFORM ami_log(c.tenant_id,p_business,'work_order',w.id::text,'wo.breakdown_reported',NULL,ami_wk_state(w)||jsonb_build_object('wo_no',w.wo_no,'asset_id',a.id,'downtime_id',did),NULL,p_request);
 RETURN ami_finish(p_business,c.tenant_id,p_request,'breakdown',pay,jsonb_build_object('status','applied','id',w.id,'wo_no',w.wo_no,'wo_status',w.status,'version',w.version,
   'downtime_id',did,'auto_approved',(w.approved_at IS NOT NULL AND w.approved_by IS NULL),'adopted_open_window',adopt));
END$$;

CREATE FUNCTION c10_demo.am_start_downtime_v1(p_business bigint,p_request text,p_asset bigint,p_data jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c am_ctx_t; a am_assets; d jsonb:=COALESCE(p_data,'{}'::jsonb); pay jsonb; v_kind text; v_rc text; v_impact text; v_start timestamptz; v_wo bigint; did bigint; w am_work_orders;
BEGIN
 IF p_asset IS NULL THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 PERFORM ami_wk_keys(d,ARRAY['kind','reason_code','impact','started_at','work_order_id']);
 v_kind:=COALESCE(ami_wk_txt(d,'kind',1,10,false),'planned');
 IF v_kind NOT IN('planned','other') THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 v_rc:=ami_wk_re(d,'reason_code','^[A-Za-z0-9][A-Za-z0-9_-]{0,23}$',false); v_impact:=ami_wk_txt(d,'impact',1,500,false);
 v_start:=ami_wk_ts(d,'started_at',false); v_wo:=ami_wk_num(d,'work_order_id',1,9e18,false)::bigint;
 pay:=jsonb_build_object('asset',p_asset,'d',d);
 SELECT * INTO b FROM ami_begin(p_business,p_request,'dt_start',pay);
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 c:=b.o_ctx;
 SELECT * INTO a FROM am_assets WHERE id=p_asset AND business_id=p_business AND tenant_id=c.tenant_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'am_denied'; END IF;
 PERFORM ami_wk_gate(c,a.site_id,'downtime_write');
 IF a.status IN('retired','disposed') THEN RAISE EXCEPTION 'am_asset_retired'; END IF;
 v_start:=ami_wk_clamp(v_start,'am_invalid_input'); v_rc:=ami_wk_dt_code(p_business,v_rc);
 IF v_wo IS NOT NULL THEN
  SELECT * INTO w FROM am_work_orders WHERE id=v_wo AND business_id=p_business AND asset_id=a.id;
  IF NOT FOUND THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
  IF w.status='CANCELLED' THEN RAISE EXCEPTION 'am_wo_cancelled_is_final'; END IF;
 END IF;
 IF EXISTS(SELECT 1 FROM am_downtime x WHERE x.asset_id=a.id AND x.ended_at IS NULL) THEN RAISE EXCEPTION 'am_downtime_open_exists'; END IF;
 IF ami_wk_dt_overlap(a.id,v_start,NULL,NULL) THEN RAISE EXCEPTION 'am_downtime_overlap'; END IF;
 BEGIN
  INSERT INTO am_downtime(tenant_id,business_id,asset_id,site_id,work_order_id,kind,reason_code,impact,started_at,started_by)
  VALUES(a.tenant_id,p_business,a.id,a.site_id,v_wo,v_kind,v_rc,v_impact,v_start,c.user_id) RETURNING id INTO did;
 EXCEPTION WHEN unique_violation THEN RAISE EXCEPTION 'am_downtime_open_exists'; END;
 PERFORM ami_log(c.tenant_id,p_business,'downtime',did::text,'downtime.start',NULL,jsonb_build_object('kind',v_kind,'started_at',v_start,'asset_id',a.id,'work_order_id',v_wo),NULL,p_request);
 RETURN ami_finish(p_business,c.tenant_id,p_request,'dt_start',pay,jsonb_build_object('status','applied','id',did,'started_at',v_start,'kind',v_kind));
END$$;

CREATE FUNCTION c10_demo.am_end_downtime_v1(p_business bigint,p_request text,p_downtime bigint,p_ended_at timestamptz,p_note text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c am_ctx_t; d am_downtime; pay jsonb; v_note text:=NULLIF(btrim(COALESCE(p_note,'')),''); e timestamptz;
BEGIN
 IF p_downtime IS NULL OR (v_note IS NOT NULL AND length(v_note)>300) THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 pay:=jsonb_build_object('dt',p_downtime,'e',p_ended_at,'n',v_note);
 SELECT * INTO b FROM ami_begin(p_business,p_request,'dt_end',pay);
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 c:=b.o_ctx;
 SELECT * INTO d FROM am_downtime WHERE id=p_downtime AND business_id=p_business FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'am_denied'; END IF;
 PERFORM ami_wk_gate(c,d.site_id,'downtime_write');
 IF d.ended_at IS NOT NULL THEN RAISE EXCEPTION 'am_downtime_already_ended'; END IF;
 e:=ami_wk_clamp(p_ended_at,'am_downtime_end_invalid');
 IF e<d.started_at THEN RAISE EXCEPTION 'am_downtime_end_invalid'; END IF;
 PERFORM 1 FROM am_assets WHERE id=d.asset_id FOR UPDATE;
 IF ami_wk_dt_overlap(d.asset_id,d.started_at,e,d.id) THEN RAISE EXCEPTION 'am_downtime_overlap'; END IF;
 UPDATE am_downtime SET ended_at=e,ended_by=c.user_id WHERE id=d.id;
 PERFORM ami_wk_restore_asset(d.asset_id,p_request);
 PERFORM ami_log(c.tenant_id,p_business,'downtime',d.id::text,'downtime.end',jsonb_build_object('ended_at',NULL),
   jsonb_build_object('ended_at',e,'kind',d.kind,'work_order_id',d.work_order_id,'note',v_note),v_note,p_request);
 RETURN ami_finish(p_business,c.tenant_id,p_request,'dt_end',pay,jsonb_build_object('status','applied','id',d.id,'ended_at',e,
   'duration_minutes',round(extract(epoch FROM (e-d.started_at))/60.0,2)));
END$$;

-- ===================== reads =====================
CREATE FUNCTION c10_demo.am_list_work_orders_v1(p_business bigint,p_filters jsonb DEFAULT '{}',p_limit int DEFAULT 50,p_offset int DEFAULT 0) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE c am_ctx_t; f jsonb:=COALESCE(p_filters,'{}'::jsonb); vs bigint[]; fs bigint[]; es bigint[]; ids bigint[]; page bigint[]; items jsonb:='[]'::jsonb; w am_work_orders; woid bigint;
 v_status text[]; v_kind text; v_site bigint; v_asset bigint; v_prio text; v_mine boolean:=false; v_req boolean:=false; v_over boolean; v_re boolean; v_search text; lim int:=COALESCE(p_limit,50); off int:=COALESCE(p_offset,0);
BEGIN
 c:=ami_read_ctx(p_business);
 IF lim NOT BETWEEN 1 AND 200 OR off<0 THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 PERFORM ami_wk_keys(f,ARRAY['status','kind','site_id','asset_id','priority','assigned_to','requested_by','overdue','search','needs_reassignment']);
 IF f ? 'status' THEN
  IF jsonb_typeof(f->'status')<>'array' OR jsonb_array_length(f->'status')>8 THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
  SELECT array_agg(x) INTO v_status FROM jsonb_array_elements_text(f->'status') x;
  IF EXISTS(SELECT 1 FROM unnest(v_status) s WHERE s NOT IN('DRAFT','SUBMITTED','APPROVED','IN_PROGRESS','COMPLETED','VERIFIED','CLOSED','CANCELLED')) THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 END IF;
 v_kind:=ami_wk_txt(f,'kind',1,20,false);
 IF v_kind IS NOT NULL AND v_kind NOT IN('preventive','corrective','breakdown','inspection','calibration') THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 v_site:=ami_wk_num(f,'site_id',1,9e18,false)::bigint; v_asset:=ami_wk_num(f,'asset_id',1,9e18,false)::bigint;
 v_prio:=ami_wk_txt(f,'priority',1,10,false);
 IF v_prio IS NOT NULL AND v_prio NOT IN('low','medium','high','critical') THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 IF ami_wk_txt(f,'assigned_to',1,10,false) IS NOT NULL THEN IF f->>'assigned_to'<>'me' THEN RAISE EXCEPTION 'am_invalid_input'; END IF; v_mine:=true; END IF;
 IF ami_wk_txt(f,'requested_by',1,10,false) IS NOT NULL THEN IF f->>'requested_by'<>'me' THEN RAISE EXCEPTION 'am_invalid_input'; END IF; v_req:=true; END IF;
 IF f ? 'overdue' THEN v_over:=ami_wk_bool(f,'overdue',NULL); END IF;
 IF f ? 'needs_reassignment' THEN v_re:=ami_wk_bool(f,'needs_reassignment',NULL); END IF;
 v_search:=lower(ami_wk_txt(f,'search',1,100,false));
 vs:=ami_sites_with(c,'view'); fs:=ami_sites_with(c,'assign')||ami_sites_with(c,'reports'); es:=ami_sites_with(c,'execute');
 ids:=ARRAY(SELECT x.id FROM am_work_orders x JOIN am_assets a ON a.id=x.asset_id
  WHERE x.business_id=p_business AND x.site_id=ANY(vs)
   AND (x.site_id=ANY(fs) OR x.requested_by=c.user_id OR (x.site_id=ANY(es) AND (x.assigned_to=c.user_id OR x.assigned_to IS NULL)))
   AND (v_status IS NULL OR x.status=ANY(v_status)) AND (v_kind IS NULL OR x.kind=v_kind) AND (v_site IS NULL OR x.site_id=v_site)
   AND (v_asset IS NULL OR x.asset_id=v_asset) AND (v_prio IS NULL OR x.priority=v_prio)
   AND (NOT v_mine OR x.assigned_to=c.user_id) AND (NOT v_req OR x.requested_by=c.user_id)
   AND (v_over IS NULL OR v_over=(x.status IN('DRAFT','SUBMITTED','APPROVED','IN_PROGRESS') AND ((x.due_on IS NOT NULL AND x.due_on<ami_today(p_business)) OR (x.sla_resolve_due_at IS NOT NULL AND x.sla_resolve_due_at<now()))))
   AND (v_re IS NULL OR v_re=ami_wk_needs_re(x))
   AND (v_search IS NULL OR strpos(lower(x.wo_no),v_search)>0 OR strpos(lower(x.title),v_search)>0 OR strpos(lower(a.asset_no),v_search)>0 OR strpos(lower(a.name),v_search)>0)
  ORDER BY x.id DESC);
 page:=ids[off+1:off+lim];
 IF page IS NOT NULL THEN
  FOREACH woid IN ARRAY page LOOP
   SELECT * INTO w FROM am_work_orders WHERE am_work_orders.id=woid;
   items:=items||jsonb_build_array(ami_wk_json(c,w));
  END LOOP;
 END IF;
 RETURN jsonb_build_object('items',items,'total',COALESCE(cardinality(ids),0),'limit',lim,'offset',off);
END$$;

CREATE FUNCTION c10_demo.am_get_work_order_v1(p_business bigint,p_wo bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE c am_ctx_t; w am_work_orders; res jsonb; ev text; need_safety boolean; vr boolean;
BEGIN
 c:=ami_read_ctx(p_business);
 IF p_wo IS NULL THEN RAISE EXCEPTION 'am_denied'; END IF;
 SELECT * INTO w FROM am_work_orders WHERE id=p_wo AND business_id=p_business;
 IF NOT FOUND OR NOT ami_wk_visible(c,w) THEN RAISE EXCEPTION 'am_denied'; END IF;
 ev:=ami_wk_pt(w,'wo.evidence_required_for'); vr:=ami_wk_pb(w,'wo.verify_required');
 need_safety:=(w.safety_critical OR COALESCE((SELECT k.safety_critical FROM am_assets a JOIN am_categories k ON k.id=a.category_id WHERE a.id=w.asset_id),false))
   AND ami_wk_pb(w,'wo.require_safety_ack');
 res:=ami_wk_json(c,w) || jsonb_build_object(
  'checklist',COALESCE((SELECT jsonb_agg(to_jsonb(x)-'tenant_id'-'business_id' ORDER BY x.seq) FROM am_wo_checklist x WHERE x.work_order_id=w.id),'[]'::jsonb),
  'labor',COALESCE((SELECT jsonb_agg(to_jsonb(x)-'tenant_id'-'business_id' ORDER BY x.id) FROM am_wo_labor x WHERE x.work_order_id=w.id),'[]'::jsonb),
  'spares',COALESCE((SELECT jsonb_agg(to_jsonb(x)-'tenant_id'-'business_id' ORDER BY x.id) FROM am_wo_spares x WHERE x.work_order_id=w.id),'[]'::jsonb),
  'attachments',COALESCE((SELECT jsonb_agg(to_jsonb(x)-'tenant_id'-'business_id' ORDER BY x.id) FROM am_wo_attachments x WHERE x.work_order_id=w.id),'[]'::jsonb),
  'history',COALESCE((SELECT jsonb_agg(to_jsonb(x)-'tenant_id'-'business_id' ORDER BY x.id) FROM am_wo_history x WHERE x.work_order_id=w.id),'[]'::jsonb),
  'downtime',COALESCE((SELECT jsonb_agg(ami_wk_dt_json(x) ORDER BY x.id) FROM am_downtime x WHERE x.work_order_id=w.id),'[]'::jsonb),
  'cal_records',COALESCE((SELECT jsonb_agg(to_jsonb(x)-'tenant_id'-'business_id' ORDER BY x.id) FROM am_cal_records x WHERE x.work_order_id=w.id),'[]'::jsonb),
  'merged_from',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',x.id,'wo_no',x.wo_no) ORDER BY x.id) FROM am_work_orders x WHERE x.merged_into_id=w.id),'[]'::jsonb),
  'available_actions',to_jsonb(ami_wk_actions(c,w)),
  'completion_requirements',jsonb_build_object(
    'checklist_pending',(SELECT count(*) FROM am_wo_checklist x WHERE x.work_order_id=w.id AND x.required AND x.result NOT IN('pass','fail')),
    'checklist_required',ami_wk_pb(w,'wo.require_checklist_complete'),
    'evidence_required',(ev='all' OR (ev='breakdown' AND w.kind='breakdown')),
    'evidence_count',(SELECT count(*) FROM am_wo_attachments x WHERE x.work_order_id=w.id),
    'cause_required',(w.kind IN('breakdown','corrective') AND ami_wk_pb(w,'wo.require_cause_code')),
    'labor_required',ami_wk_pb(w,'wo.require_actual_labor'),
    'calibration_required',(w.kind='calibration'),
    'safety_ack_required',need_safety,'safety_ack_done',(w.safety_ack_at IS NOT NULL),
    'verify_required',vr,'maker_checker',ami_wk_maker_checker(w.business_id)));
 RETURN res;
END$$;

CREATE FUNCTION c10_demo.am_my_work_v1(p_business bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE c am_ctx_t; w am_work_orders; vs bigint[]; es bigint[]; aps bigint[]; vfs bigint[]; fs bigint[];
 j_asg jsonb:='[]'; j_un jsonb:='[]'; j_apr jsonb:='[]'; j_ver jsonb:='[]'; j_req jsonb:='[]';
BEGIN
 c:=ami_read_ctx(p_business);
 vs:=ami_sites_with(c,'view'); es:=ami_sites_with(c,'execute'); aps:=ami_sites_with(c,'approve'); vfs:=ami_sites_with(c,'verify'); fs:=ami_sites_with(c,'assign')||ami_sites_with(c,'reports');
 FOR w IN SELECT * FROM am_work_orders x WHERE x.business_id=p_business AND x.site_id=ANY(vs) AND x.assigned_to=c.user_id
   AND x.status IN('APPROVED','IN_PROGRESS') ORDER BY x.id DESC LIMIT 100 LOOP j_asg:=j_asg||jsonb_build_array(ami_wk_json(c,w)); END LOOP;
 FOR w IN SELECT * FROM am_work_orders x WHERE x.business_id=p_business AND x.site_id=ANY(es) AND x.assigned_to IS NULL AND x.status='APPROVED'
    AND ami_wk_auth(c,x,'start') IS NULL ORDER BY x.id DESC LIMIT 100 LOOP j_un:=j_un||jsonb_build_array(ami_wk_json(c,w)); END LOOP;
 FOR w IN SELECT * FROM am_work_orders x WHERE x.business_id=p_business AND x.site_id=ANY(aps) AND x.status='SUBMITTED'
   AND NOT (ami_wk_maker_checker(p_business) AND x.requested_by=c.user_id) ORDER BY x.id DESC LIMIT 100 LOOP j_apr:=j_apr||jsonb_build_array(ami_wk_json(c,w)); END LOOP;
 FOR w IN SELECT * FROM am_work_orders x WHERE x.business_id=p_business AND x.site_id=ANY(vfs) AND x.status='COMPLETED'
   AND NOT (ami_wk_maker_checker(p_business) AND x.completed_by=c.user_id) ORDER BY x.id DESC LIMIT 100 LOOP j_ver:=j_ver||jsonb_build_array(ami_wk_json(c,w)); END LOOP;
 FOR w IN SELECT * FROM am_work_orders x WHERE x.business_id=p_business AND x.site_id=ANY(vs) AND x.requested_by=c.user_id
   AND x.status IN('DRAFT','SUBMITTED','APPROVED','IN_PROGRESS','COMPLETED') ORDER BY x.id DESC LIMIT 100 LOOP j_req:=j_req||jsonb_build_array(ami_wk_json(c,w)); END LOOP;
 RETURN jsonb_build_object('assigned',j_asg,'claimable',j_un,'to_approve',j_apr,'to_verify',j_ver,'my_requests',j_req,
  'counts',jsonb_build_object('assigned',jsonb_array_length(j_asg),'claimable',jsonb_array_length(j_un),'to_approve',jsonb_array_length(j_apr),
    'to_verify',jsonb_array_length(j_ver),'my_requests',jsonb_array_length(j_req)));
END$$;

CREATE FUNCTION c10_demo.am_list_downtime_v1(p_business bigint,p_filters jsonb DEFAULT '{}',p_limit int DEFAULT 50,p_offset int DEFAULT 0) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE c am_ctx_t; f jsonb:=COALESCE(p_filters,'{}'::jsonb); vs bigint[]; ids bigint[]; page bigint[]; items jsonb:='[]'; d am_downtime; dtid bigint;
 v_asset bigint; v_site bigint; v_kind text; v_open boolean; v_wo bigint; v_from date; v_to date; lim int:=COALESCE(p_limit,50); off int:=COALESCE(p_offset,0);
BEGIN
 c:=ami_read_ctx(p_business);
 IF lim NOT BETWEEN 1 AND 200 OR off<0 THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 PERFORM ami_wk_keys(f,ARRAY['asset_id','site_id','kind','open','work_order_id','from','to']);
 v_asset:=ami_wk_num(f,'asset_id',1,9e18,false)::bigint; v_site:=ami_wk_num(f,'site_id',1,9e18,false)::bigint; v_wo:=ami_wk_num(f,'work_order_id',1,9e18,false)::bigint;
 v_kind:=ami_wk_txt(f,'kind',1,10,false); IF v_kind IS NOT NULL AND v_kind NOT IN('breakdown','planned','other') THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 IF f ? 'open' THEN v_open:=ami_wk_bool(f,'open',NULL); END IF;
 v_from:=ami_wk_date(f,'from',false); v_to:=ami_wk_date(f,'to',false);
 vs:=ami_sites_with(c,'view');
 ids:=ARRAY(SELECT x.id FROM am_downtime x WHERE x.business_id=p_business AND x.site_id=ANY(vs)
   AND (v_asset IS NULL OR x.asset_id=v_asset) AND (v_site IS NULL OR x.site_id=v_site) AND (v_kind IS NULL OR x.kind=v_kind)
   AND (v_wo IS NULL OR x.work_order_id=v_wo) AND (v_open IS NULL OR v_open=(x.ended_at IS NULL))
   AND (v_from IS NULL OR COALESCE(x.ended_at,'infinity'::timestamptz)>=v_from::timestamptz) AND (v_to IS NULL OR x.started_at<(v_to+1)::timestamptz)
   ORDER BY x.started_at DESC,x.id DESC);
 page:=ids[off+1:off+lim];
 IF page IS NOT NULL THEN
  FOREACH dtid IN ARRAY page LOOP SELECT * INTO d FROM am_downtime WHERE am_downtime.id=dtid; items:=items||jsonb_build_array(ami_wk_dt_json(d)); END LOOP;
 END IF;
 RETURN jsonb_build_object('items',items,'total',COALESCE(cardinality(ids),0),'limit',lim,'offset',off);
END$$;
