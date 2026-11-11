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
  o:=o||a;
 END LOOP;
 open:=w.status IN('DRAFT','SUBMITTED','APPROVED','IN_PROGRESS');
 IF ami_wk_auth(c,w,'edit') IS NULL AND w.status IN('DRAFT','SUBMITTED','APPROVED') THEN o:=o||'edit';
 ELSIF ami_wk_auth(c,w,'work') IS NULL AND open THEN o:=o||'edit_estimates'; END IF;
 IF open AND ami_wk_auth(c,w,'assign') IS NULL THEN o:=o||'assign'; o:=o||'merge'; END IF;
 IF w.status IN('APPROVED','IN_PROGRESS') AND w.safety_ack_at IS NULL AND ami_wk_auth(c,w,'work') IS NULL
    AND (w.safety_critical OR COALESCE((SELECT k.safety_critical FROM am_assets a JOIN am_categories k ON k.id=a.category_id WHERE a.id=w.asset_id),false)) THEN
  o:=o||'acknowledge_safety'; END IF;
 IF w.status='IN_PROGRESS' AND ami_wk_auth(c,w,'work') IS NULL THEN o:=o||'checklist'; END IF;
 IF open AND (ami_wk_auth(c,w,'work') IS NULL OR (ami_wk_auth(c,w,'edit') IS NULL AND w.status IN('DRAFT','SUBMITTED','APPROVED'))) THEN
  o:=o||'labor'; o:=o||'spares'; END IF;
 IF w.status IN('DRAFT','SUBMITTED','APPROVED','IN_PROGRESS','COMPLETED','VERIFIED') AND ami_wk_auth(c,w,'attachment') IS NULL THEN o:=o||'attachment'; END IF;
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
