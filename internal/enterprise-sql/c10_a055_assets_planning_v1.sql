-- C10-A055 Enterprise Assets & Maintenance (4/7): PLANNING = checklist templates, maintenance plans & plan targets,
-- on-demand due suggestions, calendar, human-triggered work-order generation, deferral, plus the two cross-file internals
-- ami_create_wo / ami_complete_target (called by the work-orders file). DISPOSABLE c10_demo ONLY. Load after core (+registry).
--
-- Design notes (rules are POLICY, never hardcoded: schedule.* / sla.* / wo.overlap_policy / meter.stale_days via ami_cfg_*):
--  * Suggestions are computed ON DEMAND by reads (no background job, no cron). Generation is HUMAN-triggered (cap 'assign').
--  * Recurrence can never create duplicate tasks: per-business lock (ami_begin) + unique index am_wo_target_open_uq + explicit checks.
--  * Targets (am_plan_targets) are materialised per (plan, live asset). Triggers keep them in sync when assets are created / moved /
--    retired and when meters appear, so category-scoped plans automatically cover assets registered later.
--  * Due state per target (time plans):  effective_due = max(next_due_on, deferred_until);
--        has_open_wo > deferred (deferred_until > today) > overdue (today > effective_due) > due (within lead days) > upcoming.
--    escalation_level (overdue only): 0 within schedule.grace_days, 1 after grace, 2 after grace + schedule.escalation_days.
--    Usage plans: due when current meter >= next_due_reading; no meter / no baseline / stale-and-not-yet-due => meter_missing.
--  * Re-anchoring on completion (ami_complete_target): from_completion => done_on + interval; from_due_date => previous due + interval,
--    advanced (by whole intervals) until strictly after max(previous due, done_on); month-end is clamped (Jan 31 + 1 month = Feb 28/29)
--    and, because repeated clamping drifts, a series that starts on the 31st will settle on the clamped day (documented, deliberate).
--    Usage plans: next_due_reading = reading at completion + usage_interval.

-- ===================== pure schedule arithmetic (also used by the policy file's simulation) =====================
-- daily / weekly / monthly / yearly step with month-end clamping (31 Jan + 1 month = 28/29 Feb; 29 Feb + 1 year = 28 Feb). usage => NULL.
CREATE FUNCTION c10_demo.ami_next_due(p_from date,p_kind text,p_n int) RETURNS date LANGUAGE sql IMMUTABLE AS $$
 SELECT CASE WHEN p_from IS NULL OR p_kind IS NULL OR p_n IS NULL OR p_n<1 THEN NULL
  WHEN p_kind='daily' THEN p_from+p_n
  WHEN p_kind='weekly' THEN p_from+7*p_n
  WHEN p_kind='monthly' THEN (p_from+make_interval(months=>p_n))::date
  WHEN p_kind='yearly' THEN (p_from+make_interval(years=>p_n))::date
  ELSE NULL END $$;

-- ===================== PRIORITY 0: cross-file internals =====================
-- Inserts a work order. Caller authorises (NO capability check here). Returns the new work-order id.
CREATE FUNCTION c10_demo.ami_create_wo(c c10_demo.am_ctx_t,p_request text,p_asset bigint,p_kind text,p_title text,
 p_description text,p_priority text,p_source text,p_target bigint,p_due date,p_checklist_code text,p_extra jsonb)
RETURNS bigint LANGUAGE plpgsql SET search_path=c10_demo,pg_catalog AS $$
DECLARE a c10_demo.am_assets; pri text:=COALESCE(p_priority,'medium'); src text:=COALESCE(p_source,'manual'); ex jsonb:=COALESCE(p_extra,'{}'::jsonb);
 title text:=btrim(COALESCE(p_title,'')); svc text; safety boolean:=false; wid bigint; tpl bigint; st text:='DRAFT';
 t c10_demo.am_plan_targets; submit boolean; v_resp timestamptz; v_res timestamptz; wno text; n int;
BEGIN
 IF c.business_id IS NULL OR c.user_id IS NULL THEN RAISE EXCEPTION 'am_denied'; END IF;
 IF jsonb_typeof(ex)<>'object' THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 SELECT * INTO a FROM c10_demo.am_assets WHERE id=p_asset AND business_id=c.business_id AND tenant_id=c.tenant_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'am_denied'; END IF;
 IF a.status IN('retired','disposed') THEN RAISE EXCEPTION 'am_asset_retired'; END IF;
 IF p_kind IS NULL OR p_kind NOT IN('preventive','corrective','breakdown','inspection','calibration') THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 IF pri NOT IN('low','medium','high','critical') OR src NOT IN('manual','plan','breakdown_report') THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 IF length(title) NOT BETWEEN 3 AND 160 THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 IF p_description IS NOT NULL AND length(p_description)>2000 THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 IF p_target IS NOT NULL THEN
  SELECT * INTO t FROM c10_demo.am_plan_targets WHERE id=p_target AND business_id=c.business_id AND tenant_id=c.tenant_id;
  IF NOT FOUND OR t.asset_id<>a.id THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 END IF;
 -- extra keys (all optional): submit, service_category, est_labor_hours, est_labor_cost, est_spares_cost, team_ref
 submit:=COALESCE(ex->>'submit','false')='true';
 svc:=NULLIF(ex->>'service_category','');
 IF svc IS NOT NULL THEN
  IF NOT EXISTS(SELECT 1 FROM c10_demo.am_codes WHERE business_id=c.business_id AND kind='service_category' AND code=svc AND active) THEN
   RAISE EXCEPTION 'am_invalid_input'; END IF;
 END IF;
 SELECT safety_critical INTO safety FROM c10_demo.am_categories WHERE id=a.category_id;
 -- overlap policy (block | allow), resolved for the asset's site + category
 IF c10_demo.ami_cfg_text(c.business_id,a.site_id,a.category_id,'wo.overlap_policy')='block' THEN
  IF EXISTS(SELECT 1 FROM c10_demo.am_work_orders w WHERE w.asset_id=a.id AND w.kind=p_kind AND w.status NOT IN('CLOSED','CANCELLED')) THEN
   RAISE EXCEPTION 'am_overlapping_work_order'; END IF;
 END IF;
 -- checklist template (ACTIVE version) is snapshotted so later template edits never rewrite history
 IF p_checklist_code IS NOT NULL THEN
  SELECT id INTO tpl FROM c10_demo.am_checklist_templates WHERE business_id=c.business_id AND code=p_checklist_code AND active;
  IF NOT FOUND THEN RAISE EXCEPTION 'am_checklist_not_found'; END IF;
 END IF;
 v_resp:=now()+make_interval(hours=>c10_demo.ami_cfg_int(c.business_id,a.site_id,a.category_id,'sla.response_hours.'||pri));
 v_res:=now()+make_interval(hours=>c10_demo.ami_cfg_int(c.business_id,a.site_id,a.category_id,'sla.resolve_hours.'||pri));
 wno:=c10_demo.ami_next_no(c.business_id,'wo');
 INSERT INTO c10_demo.am_work_orders(tenant_id,business_id,wo_no,kind,status,source,asset_id,site_id,plan_target_id,title,description,priority,
   service_category,safety_critical,requested_by,due_on,sla_response_due_at,sla_resolve_due_at,team_ref,est_labor_hours,est_labor_cost,est_spares_cost)
 VALUES(c.tenant_id,c.business_id,wno,p_kind,'DRAFT',src,a.id,a.site_id,p_target,title,NULLIF(btrim(COALESCE(p_description,'')),''),pri,
   svc,COALESCE(safety,false),c.user_id,p_due,v_resp,v_res,NULLIF(ex->>'team_ref',''),
   NULLIF(ex->>'est_labor_hours','')::numeric,NULLIF(ex->>'est_labor_cost','')::numeric,NULLIF(ex->>'est_spares_cost','')::numeric)
 RETURNING id INTO wid;
 IF tpl IS NOT NULL THEN
  INSERT INTO c10_demo.am_wo_checklist(tenant_id,business_id,work_order_id,seq,text,kind,required,min_value,max_value,unit)
  SELECT c.tenant_id,c.business_id,wid,i.seq,i.text,i.kind,i.required,i.min_value,i.max_value,i.unit
   FROM c10_demo.am_checklist_items i WHERE i.template_id=tpl ORDER BY i.seq;
 END IF;
 INSERT INTO c10_demo.am_wo_history(tenant_id,business_id,work_order_id,from_status,to_status,action,reason,actor_uid,request_key)
 VALUES(c.tenant_id,c.business_id,wid,NULL,'DRAFT','create',NULL,c.user_id,COALESCE(p_request,'-'));
 IF submit THEN
  UPDATE c10_demo.am_work_orders SET status='SUBMITTED',submitted_at=now(),updated_at=now() WHERE id=wid;
  INSERT INTO c10_demo.am_wo_history(tenant_id,business_id,work_order_id,from_status,to_status,action,reason,actor_uid,request_key)
  VALUES(c.tenant_id,c.business_id,wid,'DRAFT','SUBMITTED','submit',NULL,c.user_id,COALESCE(p_request,'-'));
 END IF;
 RETURN wid;
END$$;

-- Re-anchors a plan target after a plan-sourced work order completed (see header for the rules). Atomic with the caller.
CREATE FUNCTION c10_demo.ami_complete_target(p_target bigint,p_done_on date,p_reading numeric) RETURNS void
LANGUAGE plpgsql SET search_path=c10_demo,pg_catalog AS $$
DECLARE t c10_demo.am_plan_targets; p c10_demo.am_plans; a c10_demo.am_assets; anc text; done date; nxt date; rd numeric; guard int:=0;
 bef jsonb; aft jsonb;
BEGIN
 IF p_target IS NULL OR p_done_on IS NULL THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 SELECT * INTO t FROM c10_demo.am_plan_targets WHERE id=p_target FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'am_denied'; END IF;
 SELECT * INTO p FROM c10_demo.am_plans WHERE id=t.plan_id;
 SELECT * INTO a FROM c10_demo.am_assets WHERE id=t.asset_id;
 anc:=COALESCE(p.anchor,c10_demo.ami_cfg_text(t.business_id,a.site_id,a.category_id,'schedule.anchor'));
 done:=GREATEST(p_done_on,COALESCE(t.last_done_on,p_done_on));
 bef:=jsonb_build_object('next_due_on',t.next_due_on,'next_due_reading',t.next_due_reading,'last_done_on',t.last_done_on,
   'last_done_reading',t.last_done_reading,'deferred_until',t.deferred_until);
 IF p.frequency_kind='usage' THEN
  rd:=p_reading;
  IF rd IS NULL THEN
   SELECT m.current_reading INTO rd FROM c10_demo.am_meters m WHERE m.asset_id=t.asset_id AND m.code=p.meter_code AND m.active;
  END IF;
  UPDATE c10_demo.am_plan_targets SET last_done_on=done,last_done_reading=rd,next_due_on=NULL,
   next_due_reading=CASE WHEN rd IS NULL THEN NULL ELSE rd+p.usage_interval END,
   deferred_until=NULL,defer_reason=NULL,version=version+1 WHERE id=t.id;
 ELSE
  IF anc='from_completion' OR t.next_due_on IS NULL THEN
   nxt:=c10_demo.ami_next_due(done,p.frequency_kind,p.interval_n);
  ELSE
   nxt:=t.next_due_on;
   LOOP
    nxt:=c10_demo.ami_next_due(nxt,p.frequency_kind,p.interval_n); guard:=guard+1;
    EXIT WHEN nxt>GREATEST(t.next_due_on,done) OR guard>5000;
   END LOOP;
   IF guard>5000 THEN nxt:=c10_demo.ami_next_due(done,p.frequency_kind,p.interval_n); END IF;
  END IF;
  UPDATE c10_demo.am_plan_targets SET last_done_on=done,last_done_reading=COALESCE(p_reading,last_done_reading),next_due_on=nxt,
   next_due_reading=NULL,deferred_until=NULL,defer_reason=NULL,version=version+1 WHERE id=t.id;
 END IF;
 SELECT jsonb_build_object('next_due_on',x.next_due_on,'next_due_reading',x.next_due_reading,'last_done_on',x.last_done_on,
   'last_done_reading',x.last_done_reading,'deferred_until',x.deferred_until,'anchor',anc) INTO aft FROM c10_demo.am_plan_targets x WHERE x.id=t.id;
 IF c10_demo.actor_uid() IS NOT NULL THEN
  PERFORM c10_demo.ami_log(t.tenant_id,t.business_id,'plan_target',t.id::text,'reanchor',bef,aft,NULL,'sys-complete-target');
 END IF;
END$$;

-- ===================== strict JSON field readers (type / range validated; absent or JSON null => NULL) =====================
CREATE FUNCTION c10_demo.ami_pln_keys(o jsonb,allowed text[]) RETURNS void LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
 IF o IS NULL OR jsonb_typeof(o)<>'object' THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_object_keys(o) k WHERE k<>ALL(allowed)) THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
END$$;
CREATE FUNCTION c10_demo.ami_pln_txt(o jsonb,k text,minl int,maxl int) RETURNS text LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE v text;
BEGIN
 IF NOT (o ? k) OR jsonb_typeof(o->k)='null' THEN RETURN NULL; END IF;
 IF jsonb_typeof(o->k)<>'string' THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 v:=btrim(o->>k);
 IF length(v) NOT BETWEEN minl AND maxl THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 RETURN v;
END$$;
CREATE FUNCTION c10_demo.ami_pln_int(o jsonb,k text,lo bigint,hi bigint) RETURNS bigint LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE n numeric;
BEGIN
 IF NOT (o ? k) OR jsonb_typeof(o->k)='null' THEN RETURN NULL; END IF;
 IF jsonb_typeof(o->k)<>'number' THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 n:=(o->>k)::numeric;
 IF n<>trunc(n) OR n<lo OR n>hi THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 RETURN n::bigint;
END$$;
CREATE FUNCTION c10_demo.ami_pln_num(o jsonb,k text,lo numeric,hi numeric) RETURNS numeric LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE n numeric;
BEGIN
 IF NOT (o ? k) OR jsonb_typeof(o->k)='null' THEN RETURN NULL; END IF;
 IF jsonb_typeof(o->k)<>'number' THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 n:=(o->>k)::numeric;
 IF n<lo OR n>hi THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 RETURN n;
END$$;
CREATE FUNCTION c10_demo.ami_pln_bool(o jsonb,k text) RETURNS boolean LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
 IF NOT (o ? k) OR jsonb_typeof(o->k)='null' THEN RETURN NULL; END IF;
 IF jsonb_typeof(o->k)<>'boolean' THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 RETURN (o->>k)::boolean;
END$$;
CREATE FUNCTION c10_demo.ami_pln_date(o jsonb,k text) RETURNS date LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
 IF NOT (o ? k) OR jsonb_typeof(o->k)='null' THEN RETURN NULL; END IF;
 IF jsonb_typeof(o->k)<>'string' OR (o->>k) !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 RETURN (o->>k)::date;
EXCEPTION WHEN datetime_field_overflow OR invalid_datetime_format THEN RAISE EXCEPTION 'am_invalid_input';
END$$;

-- ===================== plan scope matching & target materialisation =====================
CREATE FUNCTION c10_demo.ami_cat_chain(p_cat bigint) RETURNS bigint[] LANGUAGE sql STABLE AS $$
 WITH RECURSIVE r(id,parent_id,d) AS (
  SELECT id,parent_id,1 FROM c10_demo.am_categories WHERE id=p_cat
  UNION ALL SELECT c.id,c.parent_id,r.d+1 FROM c10_demo.am_categories c JOIN r ON c.id=r.parent_id WHERE r.d<12)
 SELECT COALESCE(array_agg(id),ARRAY[]::bigint[]) FROM r $$;
-- A plan covers an asset when it targets that asset, or its category (or an ancestor category), optionally limited to one site.
CREATE FUNCTION c10_demo.ami_plan_matches(p c10_demo.am_plans,a c10_demo.am_assets) RETURNS boolean LANGUAGE sql STABLE AS $$
 SELECT p.business_id=a.business_id AND (
  (p.asset_id IS NOT NULL AND p.asset_id=a.id) OR
  (p.asset_id IS NULL AND p.category_id=ANY(c10_demo.ami_cat_chain(a.category_id)) AND (p.site_id IS NULL OR p.site_id=a.site_id))) $$;

-- Materialise targets of one plan for every matching live asset; reconcile status (suspended when plan inactive / asset retired / out of scope).
CREATE FUNCTION c10_demo.ami_sync_targets(p_plan bigint) RETURNS int LANGUAGE plpgsql SET search_path=c10_demo,pg_catalog AS $$
DECLARE p c10_demo.am_plans; n int:=0;
BEGIN
 SELECT * INTO p FROM c10_demo.am_plans WHERE id=p_plan;
 IF NOT FOUND THEN RETURN 0; END IF;
 IF p.active THEN
  INSERT INTO c10_demo.am_plan_targets(tenant_id,business_id,plan_id,asset_id,next_due_on,next_due_reading)
  SELECT p.tenant_id,p.business_id,p.id,a.id,
   CASE WHEN p.frequency_kind='usage' THEN NULL ELSE p.start_on END,
   CASE WHEN p.frequency_kind='usage' THEN (SELECT m.current_reading+p.usage_interval FROM c10_demo.am_meters m
     WHERE m.asset_id=a.id AND m.code=p.meter_code AND m.active) END
  FROM c10_demo.am_assets a WHERE a.business_id=p.business_id AND a.status NOT IN('retired','disposed') AND c10_demo.ami_plan_matches(p,a)
  ON CONFLICT (plan_id,asset_id) DO NOTHING;
  GET DIAGNOSTICS n=ROW_COUNT;
 END IF;
 UPDATE c10_demo.am_plan_targets t SET status=CASE WHEN p.active AND a.status NOT IN('retired','disposed') AND c10_demo.ami_plan_matches(p,a)
   THEN 'scheduled' ELSE 'suspended' END,version=t.version+1
 FROM c10_demo.am_assets a WHERE t.plan_id=p.id AND a.id=t.asset_id
  AND t.status IS DISTINCT FROM CASE WHEN p.active AND a.status NOT IN('retired','disposed') AND c10_demo.ami_plan_matches(p,a)
   THEN 'scheduled' ELSE 'suspended' END;
 RETURN n;
END$$;
-- Same, from the asset side (new / moved / re-categorised / retired asset).
CREATE FUNCTION c10_demo.ami_sync_asset_targets(p_asset bigint) RETURNS void LANGUAGE plpgsql SET search_path=c10_demo,pg_catalog AS $$
DECLARE a c10_demo.am_assets;
BEGIN
 SELECT * INTO a FROM c10_demo.am_assets WHERE id=p_asset;
 IF NOT FOUND THEN RETURN; END IF;
 IF a.status NOT IN('retired','disposed') THEN
  INSERT INTO c10_demo.am_plan_targets(tenant_id,business_id,plan_id,asset_id,next_due_on,next_due_reading)
  SELECT p.tenant_id,p.business_id,p.id,a.id,
   CASE WHEN p.frequency_kind='usage' THEN NULL ELSE p.start_on END,
   CASE WHEN p.frequency_kind='usage' THEN (SELECT m.current_reading+p.usage_interval FROM c10_demo.am_meters m
     WHERE m.asset_id=a.id AND m.code=p.meter_code AND m.active) END
  FROM c10_demo.am_plans p WHERE p.business_id=a.business_id AND p.active AND c10_demo.ami_plan_matches(p,a)
  ON CONFLICT (plan_id,asset_id) DO NOTHING;
 END IF;
 UPDATE c10_demo.am_plan_targets t SET status=CASE WHEN p.active AND a.status NOT IN('retired','disposed') AND c10_demo.ami_plan_matches(p,a)
   THEN 'scheduled' ELSE 'suspended' END,version=t.version+1
 FROM c10_demo.am_plans p WHERE t.asset_id=a.id AND p.id=t.plan_id
  AND t.status IS DISTINCT FROM CASE WHEN p.active AND a.status NOT IN('retired','disposed') AND c10_demo.ami_plan_matches(p,a)
   THEN 'scheduled' ELSE 'suspended' END;
END$$;
CREATE FUNCTION c10_demo.ami_asset_plan_trg() RETURNS trigger LANGUAGE plpgsql SET search_path=c10_demo,pg_catalog AS $$
BEGIN PERFORM c10_demo.ami_sync_asset_targets(NEW.id); RETURN NULL; END$$;
CREATE TRIGGER am_asset_plan_sync AFTER INSERT OR UPDATE OF status,site_id,category_id ON c10_demo.am_assets
 FOR EACH ROW EXECUTE FUNCTION c10_demo.ami_asset_plan_trg();
-- A meter that appears later initialises the baseline of usage targets that were waiting for it.
CREATE FUNCTION c10_demo.ami_meter_plan_trg() RETURNS trigger LANGUAGE plpgsql SET search_path=c10_demo,pg_catalog AS $$
BEGIN
 UPDATE c10_demo.am_plan_targets t SET next_due_reading=NEW.current_reading+p.usage_interval,version=t.version+1
 FROM c10_demo.am_plans p WHERE t.plan_id=p.id AND t.asset_id=NEW.asset_id AND p.frequency_kind='usage' AND p.meter_code=NEW.code
  AND t.next_due_reading IS NULL AND t.last_done_reading IS NULL;
 RETURN NULL;
END$$;
CREATE TRIGGER am_meter_plan_sync AFTER INSERT ON c10_demo.am_meters FOR EACH ROW EXECUTE FUNCTION c10_demo.ami_meter_plan_trg();

-- Rule-change recompute: targets WITHOUT an open work order restart from last_done (or start_on); each change is audited old -> new.
CREATE FUNCTION c10_demo.ami_recompute_targets(p_plan bigint,p_request text,p_reason text) RETURNS jsonb
LANGUAGE plpgsql SET search_path=c10_demo,pg_catalog AS $$
DECLARE p c10_demo.am_plans; t c10_demo.am_plan_targets; nd date; nr numeric; cur numeric; ch jsonb:='[]'::jsonb; kept int:=0; bef jsonb; aft jsonb;
BEGIN
 SELECT * INTO p FROM c10_demo.am_plans WHERE id=p_plan;
 FOR t IN SELECT * FROM c10_demo.am_plan_targets x WHERE x.plan_id=p_plan ORDER BY x.id FOR UPDATE LOOP
  IF EXISTS(SELECT 1 FROM c10_demo.am_work_orders w WHERE w.plan_target_id=t.id AND w.status NOT IN('CLOSED','CANCELLED')) THEN kept:=kept+1; CONTINUE; END IF;
  IF p.frequency_kind='usage' THEN
   nd:=NULL;
   IF t.last_done_reading IS NOT NULL THEN nr:=t.last_done_reading+p.usage_interval;
   ELSE
    SELECT m.current_reading INTO cur FROM c10_demo.am_meters m WHERE m.asset_id=t.asset_id AND m.code=p.meter_code AND m.active;
    nr:=CASE WHEN cur IS NULL THEN NULL ELSE cur+p.usage_interval END;
   END IF;
  ELSE
   nr:=NULL;
   nd:=CASE WHEN t.last_done_on IS NOT NULL THEN c10_demo.ami_next_due(t.last_done_on,p.frequency_kind,p.interval_n) ELSE p.start_on END;
  END IF;
  IF nd IS DISTINCT FROM t.next_due_on OR nr IS DISTINCT FROM t.next_due_reading THEN
   bef:=jsonb_build_object('next_due_on',t.next_due_on,'next_due_reading',t.next_due_reading);
   aft:=jsonb_build_object('next_due_on',nd,'next_due_reading',nr);
   UPDATE c10_demo.am_plan_targets SET next_due_on=nd,next_due_reading=nr,version=version+1 WHERE id=t.id;
   PERFORM c10_demo.ami_log(t.tenant_id,t.business_id,'plan_target',t.id::text,'recompute',bef,aft,p_reason,p_request);
   ch:=ch||jsonb_build_array(jsonb_build_object('target_id',t.id,'asset_id',t.asset_id,'old_due_on',t.next_due_on,'new_due_on',nd,
     'old_due_reading',t.next_due_reading,'new_due_reading',nr));
  END IF;
 END LOOP;
 RETURN jsonb_build_object('changes',ch,'kept_open_wo',kept);
END$$;

-- ===================== checklist templates =====================
CREATE FUNCTION c10_demo.am_save_checklist_template_v1(p_business bigint,p_request text,p_code text,p_name text,p_category_id bigint,
 p_items jsonb,p_reason text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c c10_demo.am_ctx_t; pl jsonb; prev c10_demo.am_checklist_templates; mv int; nid bigint; e record; res jsonb; n int; seqs int[]:=ARRAY[]::int[];
 hasseq int:=0; k text; mn numeric; mx numeric; sq int; txt text; unit text; req boolean; cnt int;
BEGIN
 pl:=jsonb_build_object('code',p_code,'name',p_name,'category_id',p_category_id,'items',p_items,'reason',p_reason);
 SELECT * INTO b FROM c10_demo.ami_begin(p_business,p_request,'save_checklist',pl);
 c:=b.o_ctx;
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 PERFORM c10_demo.ami_need_cap(c,NULL,'plan_write');
 IF p_code IS NULL OR p_code !~ '^[A-Z0-9][A-Z0-9_-]{0,31}$' THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 IF p_name IS NULL OR length(btrim(p_name)) NOT BETWEEN 2 AND 120 THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 IF p_reason IS NOT NULL AND length(btrim(p_reason))>500 THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 IF p_category_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM c10_demo.am_categories WHERE id=p_category_id AND business_id=p_business) THEN
  RAISE EXCEPTION 'am_denied'; END IF;
 IF p_items IS NULL OR jsonb_typeof(p_items)<>'array' THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 n:=jsonb_array_length(p_items);
 IF n NOT BETWEEN 1 AND 200 THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 -- validate every item (types, kind, min<=max, contiguous seq 1..n) before touching data
 FOR e IN SELECT value v,ordinality o FROM jsonb_array_elements(p_items) WITH ORDINALITY LOOP
  PERFORM c10_demo.ami_pln_keys(e.v,ARRAY['seq','text','kind','required','min_value','max_value','unit']);
  txt:=c10_demo.ami_pln_txt(e.v,'text',2,300); IF txt IS NULL THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
  k:=COALESCE(c10_demo.ami_pln_txt(e.v,'kind',1,16),'check'); IF k NOT IN('check','measure','safety') THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
  req:=c10_demo.ami_pln_bool(e.v,'required');
  mn:=c10_demo.ami_pln_num(e.v,'min_value',-1000000000000,1000000000000); mx:=c10_demo.ami_pln_num(e.v,'max_value',-1000000000000,1000000000000);
  unit:=c10_demo.ami_pln_txt(e.v,'unit',1,16);
  IF (mn IS NOT NULL OR mx IS NOT NULL) AND k<>'measure' THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
  IF mn IS NOT NULL AND mx IS NOT NULL AND mn>mx THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
  sq:=c10_demo.ami_pln_int(e.v,'seq',1,200);
  IF sq IS NOT NULL THEN hasseq:=hasseq+1; seqs:=seqs||sq; END IF;
 END LOOP;
 IF hasseq NOT IN(0,n) THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 IF hasseq=n THEN
  SELECT count(DISTINCT s),min(s),max(s) INTO cnt,sq,mv FROM unnest(seqs) s;
  IF cnt<>n OR sq<>1 OR mv<>n THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 END IF;
 SELECT * INTO prev FROM c10_demo.am_checklist_templates WHERE business_id=p_business AND code=p_code AND active FOR UPDATE;
 SELECT COALESCE(max(version),0) INTO mv FROM c10_demo.am_checklist_templates WHERE business_id=p_business AND code=p_code;
 IF mv>0 AND (p_reason IS NULL OR length(btrim(p_reason))<3) THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 IF prev.id IS NOT NULL THEN
  UPDATE c10_demo.am_checklist_templates SET active=false,superseded_at=now() WHERE id=prev.id;
 END IF;
 INSERT INTO c10_demo.am_checklist_templates(tenant_id,business_id,code,version,name,category_id,active,created_by)
 VALUES(c.tenant_id,p_business,p_code,mv+1,btrim(p_name),p_category_id,true,c.user_id) RETURNING id INTO nid;
 FOR e IN SELECT value v,ordinality o FROM jsonb_array_elements(p_items) WITH ORDINALITY LOOP
  INSERT INTO c10_demo.am_checklist_items(tenant_id,business_id,template_id,seq,text,kind,required,min_value,max_value,unit)
  VALUES(c.tenant_id,p_business,nid,COALESCE(c10_demo.ami_pln_int(e.v,'seq',1,200),e.o::int),c10_demo.ami_pln_txt(e.v,'text',2,300),
   COALESCE(c10_demo.ami_pln_txt(e.v,'kind',1,16),'check'),COALESCE(c10_demo.ami_pln_bool(e.v,'required'),true),
   c10_demo.ami_pln_num(e.v,'min_value',-1000000000000,1000000000000),c10_demo.ami_pln_num(e.v,'max_value',-1000000000000,1000000000000),
   c10_demo.ami_pln_txt(e.v,'unit',1,16));
 END LOOP;
 PERFORM c10_demo.ami_log(c.tenant_id,p_business,'checklist_template',p_code,CASE WHEN mv=0 THEN 'create' ELSE 'new_version' END,
  CASE WHEN prev.id IS NULL THEN NULL ELSE jsonb_build_object('id',prev.id,'version',prev.version,'name',prev.name) END,
  jsonb_build_object('id',nid,'version',mv+1,'name',btrim(p_name),'items',n),p_reason,p_request);
 res:=jsonb_build_object('status','applied','id',nid,'code',p_code,'version',mv+1,'items_count',n,'previous_version',CASE WHEN prev.id IS NULL THEN NULL ELSE prev.version END);
 RETURN c10_demo.ami_finish(p_business,c.tenant_id,p_request,'save_checklist',pl,res);
END$$;

CREATE FUNCTION c10_demo.am_list_checklists_v1(p_business bigint,p_include_inactive boolean DEFAULT false) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE c c10_demo.am_ctx_t; r jsonb;
BEGIN
 c:=c10_demo.ami_read_ctx(p_business);
 IF cardinality(c10_demo.ami_sites_with(c,'view'))=0 THEN RAISE EXCEPTION 'am_not_permitted'; END IF;
 SELECT COALESCE(jsonb_agg(jsonb_build_object('id',t.id,'code',t.code,'version',t.version,'name',t.name,'category_id',t.category_id,
   'active',t.active,'superseded_at',t.superseded_at,'created_at',t.created_at,
   'items',(SELECT COALESCE(jsonb_agg(jsonb_build_object('seq',i.seq,'text',i.text,'kind',i.kind,'required',i.required,
      'min_value',i.min_value,'max_value',i.max_value,'unit',i.unit) ORDER BY i.seq),'[]'::jsonb) FROM c10_demo.am_checklist_items i WHERE i.template_id=t.id))
   ORDER BY t.code,t.version DESC),'[]'::jsonb) INTO r
 FROM c10_demo.am_checklist_templates t WHERE t.business_id=p_business AND (COALESCE(p_include_inactive,false) OR t.active);
 RETURN jsonb_build_object('items',r,'total',jsonb_array_length(r));
END$$;

-- ===================== plans =====================
CREATE FUNCTION c10_demo.am_save_plan_v1(p_business bigint,p_request text,p_id bigint,p_expected_version bigint,p_data jsonb,p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c c10_demo.am_ctx_t; pl jsonb; old c10_demo.am_plans; np c10_demo.am_plans; ast c10_demo.am_assets; cat c10_demo.am_categories;
 is_new boolean:=(p_id IS NULL); ev text; rule_changed boolean:=false; rc jsonb:=NULL; cnt int; capsite bigint; res jsonb;
BEGIN
 pl:=jsonb_build_object('id',p_id,'expected_version',p_expected_version,'data',p_data,'reason',p_reason);
 SELECT * INTO b FROM c10_demo.ami_begin(p_business,p_request,'save_plan',pl);
 c:=b.o_ctx;
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 IF cardinality(c10_demo.ami_sites_with(c,'plan_write'))=0 THEN RAISE EXCEPTION 'am_not_permitted'; END IF;
 PERFORM c10_demo.ami_pln_keys(p_data,ARRAY['name','plan_type','asset_id','category_id','site_id','frequency_kind','interval_n','meter_code',
  'usage_interval','checklist_code','priority','est_labor_hours','est_cost','anchor','start_on','end_on','lead_days','team_ref','active']);
 IF p_reason IS NOT NULL AND length(btrim(p_reason))>500 THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 IF is_new THEN
  np.priority:='medium'; np.interval_n:=1; np.active:=true; np.tenant_id:=c.tenant_id; np.business_id:=p_business;
 ELSE
  SELECT * INTO old FROM c10_demo.am_plans WHERE id=p_id AND business_id=p_business FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'am_denied'; END IF;
  IF old.asset_id IS NOT NULL THEN SELECT site_id INTO capsite FROM c10_demo.am_assets WHERE id=old.asset_id; ELSE capsite:=old.site_id; END IF;
  PERFORM c10_demo.ami_need_cap(c,capsite,'plan_write');
  IF p_expected_version IS NULL THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
  IF old.version<>p_expected_version THEN RAISE EXCEPTION 'am_stale_version'; END IF;
  IF p_reason IS NULL OR length(btrim(p_reason))<3 OR jsonb_typeof(p_data)<>'object' OR p_data='{}'::jsonb THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
  np:=old;
  -- scope is immutable after creation (changing it would silently re-target history)
  IF (p_data ? 'asset_id' AND c10_demo.ami_pln_int(p_data,'asset_id',1,9223372036854775807) IS DISTINCT FROM old.asset_id)
   OR (p_data ? 'category_id' AND c10_demo.ami_pln_int(p_data,'category_id',1,9223372036854775807) IS DISTINCT FROM old.category_id)
   OR (p_data ? 'site_id' AND c10_demo.ami_pln_int(p_data,'site_id',1,9223372036854775807) IS DISTINCT FROM old.site_id) THEN
   RAISE EXCEPTION 'am_invalid_input'; END IF;
 END IF;
 IF p_data ? 'name' THEN np.name:=c10_demo.ami_pln_txt(p_data,'name',2,120); END IF;
 IF p_data ? 'plan_type' THEN np.plan_type:=c10_demo.ami_pln_txt(p_data,'plan_type',1,20); END IF;
 IF p_data ? 'frequency_kind' THEN np.frequency_kind:=c10_demo.ami_pln_txt(p_data,'frequency_kind',1,20); END IF;
 IF p_data ? 'interval_n' THEN np.interval_n:=c10_demo.ami_pln_int(p_data,'interval_n',1,3650); END IF;
 IF p_data ? 'meter_code' THEN np.meter_code:=c10_demo.ami_pln_txt(p_data,'meter_code',1,16); END IF;
 IF p_data ? 'usage_interval' THEN np.usage_interval:=c10_demo.ami_pln_num(p_data,'usage_interval',0.001,1000000000000); END IF;
 IF p_data ? 'checklist_code' THEN np.checklist_code:=c10_demo.ami_pln_txt(p_data,'checklist_code',1,32); END IF;
 IF p_data ? 'priority' THEN np.priority:=c10_demo.ami_pln_txt(p_data,'priority',1,10); END IF;
 IF p_data ? 'est_labor_hours' THEN np.est_labor_hours:=c10_demo.ami_pln_num(p_data,'est_labor_hours',0,100000); END IF;
 IF p_data ? 'est_cost' THEN np.est_cost:=c10_demo.ami_pln_num(p_data,'est_cost',0,1000000000000); END IF;
 IF p_data ? 'anchor' THEN np.anchor:=c10_demo.ami_pln_txt(p_data,'anchor',1,20); END IF;
 IF p_data ? 'start_on' THEN np.start_on:=c10_demo.ami_pln_date(p_data,'start_on'); END IF;
 IF p_data ? 'end_on' THEN np.end_on:=c10_demo.ami_pln_date(p_data,'end_on'); END IF;
 IF p_data ? 'lead_days' THEN np.lead_days:=c10_demo.ami_pln_int(p_data,'lead_days',0,90); END IF;
 IF p_data ? 'team_ref' THEN np.team_ref:=c10_demo.ami_pln_txt(p_data,'team_ref',1,40); END IF;
 IF p_data ? 'active' THEN np.active:=c10_demo.ami_pln_bool(p_data,'active'); END IF;
 IF is_new THEN
  np.asset_id:=c10_demo.ami_pln_int(p_data,'asset_id',1,9223372036854775807);
  np.category_id:=c10_demo.ami_pln_int(p_data,'category_id',1,9223372036854775807);
  np.site_id:=c10_demo.ami_pln_int(p_data,'site_id',1,9223372036854775807);
  IF (np.asset_id IS NULL)=(np.category_id IS NULL) THEN RAISE EXCEPTION 'am_invalid_input'; END IF;   -- exactly one scope
  IF np.asset_id IS NOT NULL THEN
   IF np.site_id IS NOT NULL THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
   SELECT * INTO ast FROM c10_demo.am_assets WHERE id=np.asset_id AND business_id=p_business;
   IF NOT FOUND THEN RAISE EXCEPTION 'am_denied'; END IF;
   PERFORM c10_demo.ami_need_cap(c,ast.site_id,'plan_write');
   IF ast.status IN('retired','disposed') THEN RAISE EXCEPTION 'am_asset_retired'; END IF;
  ELSE
   SELECT * INTO cat FROM c10_demo.am_categories WHERE id=np.category_id AND business_id=p_business;
   IF NOT FOUND THEN RAISE EXCEPTION 'am_denied'; END IF;
   IF np.site_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM c10_demo.sites WHERE id=np.site_id AND business_id=p_business) THEN RAISE EXCEPTION 'am_denied'; END IF;
   PERFORM c10_demo.ami_need_cap(c,np.site_id,'plan_write');
   IF NOT cat.active THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
  END IF;
 END IF;
 -- field rules
 IF np.name IS NULL OR np.plan_type IS NULL OR np.frequency_kind IS NULL OR np.interval_n IS NULL OR np.priority IS NULL OR np.start_on IS NULL OR np.active IS NULL THEN
  RAISE EXCEPTION 'am_invalid_input'; END IF;
 IF np.plan_type NOT IN('preventive','inspection','calibration','certification') OR np.frequency_kind NOT IN('daily','weekly','monthly','yearly','usage')
  OR np.priority NOT IN('low','medium','high','critical') OR (np.anchor IS NOT NULL AND np.anchor NOT IN('from_completion','from_due_date')) THEN
  RAISE EXCEPTION 'am_invalid_input'; END IF;
 IF np.end_on IS NOT NULL AND np.end_on<np.start_on THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 IF np.team_ref IS NOT NULL AND np.team_ref !~ '^[A-Za-z0-9][A-Za-z0-9._/ -]{0,39}$' THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 IF np.frequency_kind='usage' THEN
  np.interval_n:=1;
  IF np.meter_code IS NULL OR np.meter_code !~ '^[A-Z0-9][A-Z0-9_-]{0,15}$' OR np.usage_interval IS NULL THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 ELSE
  IF (p_data ? 'meter_code' AND jsonb_typeof(p_data->'meter_code')<>'null') OR (p_data ? 'usage_interval' AND jsonb_typeof(p_data->'usage_interval')<>'null') THEN
   RAISE EXCEPTION 'am_invalid_input'; END IF;
  np.meter_code:=NULL; np.usage_interval:=NULL;
 END IF;
 IF np.checklist_code IS NOT NULL AND NOT EXISTS(SELECT 1 FROM c10_demo.am_checklist_templates WHERE business_id=p_business AND code=np.checklist_code AND active) THEN
  RAISE EXCEPTION 'am_checklist_not_found'; END IF;
 IF is_new THEN
  INSERT INTO c10_demo.am_plans(tenant_id,business_id,name,plan_type,asset_id,category_id,site_id,frequency_kind,interval_n,meter_code,usage_interval,
   checklist_code,priority,est_labor_hours,est_cost,anchor,start_on,end_on,lead_days,team_ref,active,created_by)
  VALUES(c.tenant_id,p_business,np.name,np.plan_type,np.asset_id,np.category_id,np.site_id,np.frequency_kind,np.interval_n,np.meter_code,np.usage_interval,
   np.checklist_code,np.priority,np.est_labor_hours,np.est_cost,np.anchor,np.start_on,np.end_on,np.lead_days,np.team_ref,np.active,c.user_id)
  RETURNING * INTO np;
  ev:='create';
  cnt:=c10_demo.ami_sync_targets(np.id);
  PERFORM c10_demo.ami_log(c.tenant_id,p_business,'plan',np.id::text,ev,NULL,to_jsonb(np),p_reason,p_request);
 ELSE
  rule_changed:=(np.frequency_kind,np.interval_n,np.start_on,np.meter_code,np.usage_interval)
   IS DISTINCT FROM (old.frequency_kind,old.interval_n,old.start_on,old.meter_code,old.usage_interval);
  UPDATE c10_demo.am_plans SET name=np.name,plan_type=np.plan_type,frequency_kind=np.frequency_kind,interval_n=np.interval_n,meter_code=np.meter_code,
   usage_interval=np.usage_interval,checklist_code=np.checklist_code,priority=np.priority,est_labor_hours=np.est_labor_hours,est_cost=np.est_cost,
   anchor=np.anchor,start_on=np.start_on,end_on=np.end_on,lead_days=np.lead_days,team_ref=np.team_ref,active=np.active,version=version+1,updated_at=now()
  WHERE id=old.id RETURNING * INTO np;
  ev:=CASE WHEN old.active AND NOT np.active THEN 'deactivate' WHEN NOT old.active AND np.active THEN 'activate' ELSE 'update' END;
  IF rule_changed THEN rc:=c10_demo.ami_recompute_targets(np.id,p_request,p_reason); END IF;
  cnt:=c10_demo.ami_sync_targets(np.id);
  PERFORM c10_demo.ami_log(c.tenant_id,p_business,'plan',np.id::text,ev,to_jsonb(old),
   to_jsonb(np)||CASE WHEN rc IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('recomputed',rc) END,p_reason,p_request);
 END IF;
 res:=jsonb_build_object('status','applied','id',np.id,'version',np.version,'event',ev,'targets_added',cnt,'rule_changed',rule_changed,
  'recomputed',COALESCE(rc->'changes','[]'::jsonb),'kept_open_wo',COALESCE((rc->>'kept_open_wo')::int,0),
  'target_count',(SELECT count(*) FROM c10_demo.am_plan_targets WHERE plan_id=np.id AND status='scheduled'));
 RETURN c10_demo.ami_finish(p_business,c.tenant_id,p_request,'save_plan',pl,res);
END$$;

CREATE FUNCTION c10_demo.am_list_plans_v1(p_business bigint,p_filters jsonb DEFAULT '{}'::jsonb) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE c c10_demo.am_ctx_t; f jsonb:=COALESCE(p_filters,'{}'::jsonb); vs bigint[]; r jsonb; act boolean; fa bigint; fc bigint; fs bigint; ft text; q text;
BEGIN
 c:=c10_demo.ami_read_ctx(p_business);
 vs:=c10_demo.ami_sites_with(c,'view');
 IF cardinality(vs)=0 THEN RAISE EXCEPTION 'am_not_permitted'; END IF;
 PERFORM c10_demo.ami_pln_keys(f,ARRAY['active','asset_id','category_id','site_id','plan_type','search']);
 act:=c10_demo.ami_pln_bool(f,'active'); fa:=c10_demo.ami_pln_int(f,'asset_id',1,9223372036854775807);
 fc:=c10_demo.ami_pln_int(f,'category_id',1,9223372036854775807); fs:=c10_demo.ami_pln_int(f,'site_id',1,9223372036854775807);
 ft:=c10_demo.ami_pln_txt(f,'plan_type',1,20); q:=c10_demo.ami_pln_txt(f,'search',1,80);
 SELECT COALESCE(jsonb_agg(x.j ORDER BY x.id),'[]'::jsonb) INTO r FROM (
  SELECT p.id,jsonb_build_object('id',p.id,'name',p.name,'plan_type',p.plan_type,'asset_id',p.asset_id,'asset_no',a.asset_no,'asset_name',a.name,
   'category_id',p.category_id,'category_code',cg.code,'site_id',COALESCE(p.site_id,a.site_id),'frequency_kind',p.frequency_kind,'interval_n',p.interval_n,
   'meter_code',p.meter_code,'usage_interval',p.usage_interval,'checklist_code',p.checklist_code,'priority',p.priority,
   'est_labor_hours',p.est_labor_hours,'est_cost',p.est_cost,'anchor',p.anchor,'start_on',p.start_on,'end_on',p.end_on,'lead_days',p.lead_days,
   'team_ref',p.team_ref,'active',p.active,'version',p.version,
   'target_count',(SELECT count(*) FROM c10_demo.am_plan_targets t WHERE t.plan_id=p.id AND t.status='scheduled'),
   'can_edit',c10_demo.ami_has(c,COALESCE(p.site_id,a.site_id),'plan_write')) j
  FROM c10_demo.am_plans p LEFT JOIN c10_demo.am_assets a ON a.id=p.asset_id LEFT JOIN c10_demo.am_categories cg ON cg.id=p.category_id
  WHERE p.business_id=p_business
   AND (CASE WHEN p.asset_id IS NOT NULL THEN a.site_id=ANY(vs) WHEN p.site_id IS NOT NULL THEN p.site_id=ANY(vs) ELSE true END)
   AND (act IS NULL OR p.active=act) AND (fa IS NULL OR p.asset_id=fa) AND (fc IS NULL OR p.category_id=fc)
   AND (fs IS NULL OR COALESCE(p.site_id,a.site_id)=fs) AND (ft IS NULL OR p.plan_type=ft)
   AND (q IS NULL OR p.name ILIKE '%'||replace(replace(q,'%','\%'),'_','\_')||'%')
  ORDER BY p.id LIMIT 500) x;
 RETURN jsonb_build_object('items',r,'total',jsonb_array_length(r));
END$$;

-- ===================== due computation (single source of truth for suggestions, calendar and generation) =====================
CREATE FUNCTION c10_demo.ami_due_rows(p_business bigint,p_sites bigint[],p_site bigint,p_horizon int,p_ids bigint[])
RETURNS TABLE(target_id bigint,plan_id bigint,plan_name text,plan_type text,frequency_kind text,interval_n int,priority text,
 asset_id bigint,asset_no text,asset_name text,site_id bigint,category_id bigint,next_due_on date,next_due_reading numeric,
 last_done_on date,deferred_until date,defer_reason text,effective_due_on date,meter_code text,current_reading numeric,meter_stale boolean,
 days_until_due int,days_overdue int,lead_days int,grace_days int,escalation_days int,open_wo_id bigint,open_wo_no text,
 state text,escalation_level int,in_window boolean,reason text,target_version bigint,usage_interval numeric)
LANGUAGE sql STABLE SET search_path=c10_demo,pg_catalog AS $$
 WITH b AS (
  SELECT t.id tid,t.plan_id pid,p.name pname,p.plan_type ptype,p.frequency_kind fk,p.interval_n ival,p.priority pri,p.usage_interval ui,p.lead_days plead,
   a.id aid,a.asset_no ano,a.name aname,a.site_id sid,a.category_id cid,t.next_due_on ndo,t.next_due_reading ndr,t.last_done_on ldo,
   t.deferred_until du,t.defer_reason dr,t.version tver,p.meter_code mc,m.current_reading cr,m.last_reading_at lra,ow.id owid,ow.wo_no owno,
   c10_demo.ami_today(p_business) today
  FROM c10_demo.am_plan_targets t
  JOIN c10_demo.am_plans p ON p.id=t.plan_id AND p.business_id=t.business_id
  JOIN c10_demo.am_assets a ON a.id=t.asset_id AND a.business_id=t.business_id
  LEFT JOIN c10_demo.am_meters m ON m.asset_id=a.id AND m.code=p.meter_code AND m.active
  LEFT JOIN LATERAL (SELECT w.id,w.wo_no FROM c10_demo.am_work_orders w WHERE w.plan_target_id=t.id AND w.status NOT IN('CLOSED','CANCELLED')
    ORDER BY w.id LIMIT 1) ow ON true
  WHERE t.business_id=p_business AND p.active AND t.status='scheduled' AND a.status NOT IN('retired','disposed')
   AND a.site_id=ANY(p_sites) AND (p_site IS NULL OR a.site_id=p_site) AND (p_ids IS NULL OR t.id=ANY(p_ids))
   AND (p.end_on IS NULL OR t.next_due_on IS NULL OR t.next_due_on<=p.end_on)
 ), c AS (
  SELECT b.*,
   CASE WHEN fk='usage' OR ndo IS NULL THEN NULL WHEN du IS NOT NULL THEN GREATEST(ndo,du) ELSE ndo END eff,
   COALESCE(plead,c10_demo.ami_cfg_int(p_business,sid,cid,'schedule.due_lead_days')) lead,
   c10_demo.ami_cfg_int(p_business,sid,cid,'schedule.grace_days') grace,
   c10_demo.ami_cfg_int(p_business,sid,cid,'schedule.escalation_days') esc,
   CASE WHEN cr IS NULL THEN NULL ELSE (lra IS NULL OR lra<now()-make_interval(days=>c10_demo.ami_cfg_int(p_business,sid,cid,'meter.stale_days'))) END stale
  FROM b
 ), d AS (
  SELECT c.*,
   CASE WHEN fk='usage' THEN
     CASE WHEN owid IS NOT NULL THEN 'has_open_wo' WHEN cr IS NULL OR ndr IS NULL THEN 'meter_missing' WHEN cr>=ndr THEN 'due'
          WHEN stale THEN 'meter_missing' ELSE 'upcoming' END
    ELSE
     CASE WHEN owid IS NOT NULL THEN 'has_open_wo' WHEN du IS NOT NULL AND du>today THEN 'deferred' WHEN eff IS NULL THEN NULL
          WHEN today>eff THEN 'overdue' WHEN eff-today<=lead THEN 'due' ELSE 'upcoming' END
   END st,
   CASE WHEN fk='usage' THEN (cr IS NOT NULL AND ndr IS NOT NULL AND cr>=ndr)
        ELSE (eff IS NOT NULL AND eff<=today+COALESCE(p_horizon,lead)) END inw
  FROM c
 )
 SELECT d.tid,d.pid,d.pname,d.ptype,d.fk,d.ival,d.pri,d.aid,d.ano,d.aname,d.sid,d.cid,d.ndo,d.ndr,d.ldo,d.du,d.dr,d.eff,d.mc,d.cr,d.stale,
  CASE WHEN d.eff IS NULL THEN NULL ELSE d.eff-d.today END,
  CASE WHEN d.eff IS NOT NULL AND d.today>d.eff THEN d.today-d.eff ELSE 0 END,
  d.lead,d.grace,d.esc,d.owid,d.owno,d.st,
  CASE WHEN d.st='overdue' THEN CASE WHEN d.today-d.eff>d.grace+d.esc THEN 2 WHEN d.today-d.eff>d.grace THEN 1 ELSE 0 END ELSE 0 END,
  d.inw,
  CASE WHEN d.fk<>'usage' OR d.owid IS NOT NULL THEN NULL WHEN d.cr IS NULL THEN 'no_meter' WHEN d.ndr IS NULL THEN 'no_baseline'
       WHEN d.st='meter_missing' THEN 'stale_meter' ELSE NULL END,
  d.tver,d.ui
 FROM d WHERE d.st IS NOT NULL $$;

-- On-demand suggestions (no background job). Items: in the lead/horizon window, plus deferred, meter_missing and usage progress rows.
CREATE FUNCTION c10_demo.am_due_suggestions_v1(p_business bigint,p_site bigint DEFAULT NULL,p_horizon_days int DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE c c10_demo.am_ctx_t; vs bigint[]; asg bigint[]; r jsonb;
BEGIN
 c:=c10_demo.ami_read_ctx(p_business);
 vs:=c10_demo.ami_sites_with(c,'view'); asg:=c10_demo.ami_sites_with(c,'assign');
 IF cardinality(vs)=0 THEN RAISE EXCEPTION 'am_not_permitted'; END IF;
 IF p_site IS NOT NULL THEN
  IF NOT EXISTS(SELECT 1 FROM c10_demo.sites WHERE id=p_site AND business_id=p_business) THEN RAISE EXCEPTION 'am_denied'; END IF;
  IF NOT (p_site=ANY(vs)) THEN RAISE EXCEPTION 'am_not_permitted'; END IF;
 END IF;
 IF p_horizon_days IS NOT NULL AND p_horizon_days NOT BETWEEN 0 AND 366 THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 WITH q AS (
  SELECT * FROM c10_demo.ami_due_rows(p_business,vs,p_site,p_horizon_days,NULL) x
  WHERE x.in_window OR x.state IN('meter_missing','deferred') OR (x.frequency_kind='usage' AND x.state='upcoming'))
 SELECT COALESCE(jsonb_agg(jsonb_build_object('target_id',q.target_id,'plan_id',q.plan_id,'plan_name',q.plan_name,'plan_type',q.plan_type,
   'frequency_kind',q.frequency_kind,'interval_n',q.interval_n,'priority',q.priority,'asset_id',q.asset_id,'asset_no',q.asset_no,
   'asset_name',q.asset_name,'site_id',q.site_id,'category_id',q.category_id,'next_due_on',q.next_due_on,'next_due_reading',q.next_due_reading,
   'effective_due_on',q.effective_due_on,'last_done_on',q.last_done_on,'deferred_until',q.deferred_until,'defer_reason',q.defer_reason,
   'meter_code',q.meter_code,'current_reading',q.current_reading,'meter_stale',q.meter_stale,'usage_interval',q.usage_interval,
   'remaining_usage',CASE WHEN q.next_due_reading IS NOT NULL AND q.current_reading IS NOT NULL THEN q.next_due_reading-q.current_reading END,
   'days_until_due',q.days_until_due,'days_overdue',q.days_overdue,'state',q.state,'escalation_level',q.escalation_level,'reason',q.reason,
   'open_wo_id',q.open_wo_id,'open_wo_no',q.open_wo_no,'can_generate',q.site_id=ANY(asg),'version',q.target_version)
   ORDER BY q.escalation_level DESC,q.days_overdue DESC,q.effective_due_on NULLS LAST,q.target_id),'[]'::jsonb) INTO r FROM q;
 RETURN jsonb_build_object('items',r,'total',jsonb_array_length(r),'as_of',c10_demo.ami_today(p_business),'horizon_days',p_horizon_days);
END$$;

-- Calendar: plan targets (time plans, by effective due date; targets that already have an open WO appear as that WO) + work orders by due_on.
CREATE FUNCTION c10_demo.am_calendar_v1(p_business bigint,p_from date,p_to date,p_site bigint DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE c c10_demo.am_ctx_t; vs bigint[]; r jsonb;
BEGIN
 c:=c10_demo.ami_read_ctx(p_business);
 vs:=c10_demo.ami_sites_with(c,'view');
 IF cardinality(vs)=0 THEN RAISE EXCEPTION 'am_not_permitted'; END IF;
 IF p_from IS NULL OR p_to IS NULL OR p_to<p_from OR p_to-p_from>365 THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 IF p_site IS NOT NULL THEN
  IF NOT EXISTS(SELECT 1 FROM c10_demo.sites WHERE id=p_site AND business_id=p_business) THEN RAISE EXCEPTION 'am_denied'; END IF;
  IF NOT (p_site=ANY(vs)) THEN RAISE EXCEPTION 'am_not_permitted'; END IF;
 END IF;
 SELECT COALESCE(jsonb_agg(jsonb_build_object('date',g.d,'items',g.items) ORDER BY g.d),'[]'::jsonb) INTO r FROM (
  SELECT u.d,jsonb_agg(u.item ORDER BY u.ord,u.id) items FROM (
   SELECT x.effective_due_on d,0 ord,x.target_id id,jsonb_build_object('type','plan_target','id',x.target_id,'target_id',x.target_id,'plan_id',x.plan_id,
     'title',x.plan_name,'plan_type',x.plan_type,'asset_id',x.asset_id,'asset_no',x.asset_no,'asset_name',x.asset_name,'site_id',x.site_id,
     'priority',x.priority,'state',x.state,'due_on',x.effective_due_on,'escalation_level',x.escalation_level) item
   FROM c10_demo.ami_due_rows(p_business,vs,p_site,NULL,NULL) x
   WHERE x.state<>'has_open_wo' AND x.effective_due_on BETWEEN p_from AND p_to
   UNION ALL
   SELECT w.due_on,1,w.id,jsonb_build_object('type','work_order','id',w.id,'wo_no',w.wo_no,'plan_target_id',w.plan_target_id,'title',w.title,
     'kind',w.kind,'asset_id',w.asset_id,'asset_no',a.asset_no,'asset_name',a.name,'site_id',w.site_id,'priority',w.priority,'state',w.status,
     'status',w.status,'due_on',w.due_on)
   FROM c10_demo.am_work_orders w JOIN c10_demo.am_assets a ON a.id=w.asset_id
   WHERE w.business_id=p_business AND w.site_id=ANY(vs) AND (p_site IS NULL OR w.site_id=p_site) AND w.status<>'CANCELLED'
    AND w.due_on BETWEEN p_from AND p_to) u
  GROUP BY u.d) g;
 RETURN jsonb_build_object('from',p_from,'to',p_to,'days',r);
END$$;

-- ===================== generation (human-triggered, idempotent, never duplicates) =====================
CREATE FUNCTION c10_demo.am_generate_work_orders_v1(p_business bigint,p_request text,p_target_ids bigint[] DEFAULT NULL,
 p_site bigint DEFAULT NULL,p_horizon_days int DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c c10_demo.am_ctx_t; pl jsonb; vs bigint[]; asg bigint[]; r record; p c10_demo.am_plans; wid bigint; wno text; created jsonb:='[]'::jsonb;
 skipped jsonb:='[]'::jsonb; seen bigint[]:=ARRAY[]::bigint[]; wkind text; svc text; extra jsonb; tid bigint; why text; tr record; res jsonb; today date; due date;
BEGIN
 pl:=jsonb_build_object('target_ids',to_jsonb(p_target_ids),'site',p_site,'horizon_days',p_horizon_days);
 SELECT * INTO b FROM c10_demo.ami_begin(p_business,p_request,'generate_wo',pl);
 c:=b.o_ctx;
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 vs:=c10_demo.ami_sites_with(c,'view'); asg:=c10_demo.ami_sites_with(c,'assign');
 IF cardinality(asg)=0 THEN RAISE EXCEPTION 'am_not_permitted'; END IF;
 IF p_horizon_days IS NOT NULL AND p_horizon_days NOT BETWEEN 0 AND 366 THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 IF p_target_ids IS NOT NULL AND (cardinality(p_target_ids)>200 OR EXISTS(SELECT 1 FROM unnest(p_target_ids) x WHERE x IS NULL)) THEN
  RAISE EXCEPTION 'am_invalid_input'; END IF;
 IF p_site IS NOT NULL THEN
  IF NOT EXISTS(SELECT 1 FROM c10_demo.sites WHERE id=p_site AND business_id=p_business) THEN RAISE EXCEPTION 'am_denied'; END IF;
  IF NOT (p_site=ANY(asg)) THEN RAISE EXCEPTION 'am_not_permitted'; END IF;
 END IF;
 today:=c10_demo.ami_today(p_business);
 FOR r IN SELECT * FROM c10_demo.ami_due_rows(p_business,vs,p_site,p_horizon_days,p_target_ids) x
   ORDER BY x.escalation_level DESC,x.days_overdue DESC,x.effective_due_on NULLS LAST,x.target_id LOOP
  seen:=seen||r.target_id;
  IF p_target_ids IS NULL AND NOT r.in_window AND r.state NOT IN('meter_missing','deferred') THEN CONTINUE; END IF;
  IF NOT (r.site_id=ANY(asg)) THEN skipped:=skipped||jsonb_build_array(jsonb_build_object('target_id',r.target_id,'reason','not_permitted')); CONTINUE; END IF;
  why:=CASE WHEN r.state='has_open_wo' THEN 'has_open_wo' WHEN r.state='deferred' THEN 'deferred' WHEN r.state='meter_missing' THEN 'meter_missing'
            WHEN NOT r.in_window THEN 'not_due' ELSE NULL END;
  IF why IS NOT NULL THEN
   skipped:=skipped||jsonb_build_array(jsonb_build_object('target_id',r.target_id,'reason',why,'detail',r.reason,'asset_id',r.asset_id,'open_wo_id',r.open_wo_id));
   CONTINUE; END IF;
  SELECT * INTO p FROM c10_demo.am_plans WHERE id=r.plan_id;
  wkind:=CASE p.plan_type WHEN 'preventive' THEN 'preventive' WHEN 'calibration' THEN 'calibration' ELSE 'inspection' END;
  svc:=CASE p.plan_type WHEN 'preventive' THEN 'ROUTINE' WHEN 'inspection' THEN 'INSPECT' WHEN 'calibration' THEN 'CALIB' ELSE 'SAFETY' END;
  IF NOT EXISTS(SELECT 1 FROM c10_demo.am_codes WHERE business_id=p_business AND kind='service_category' AND code=svc AND active) THEN svc:=NULL; END IF;
  extra:=jsonb_build_object('submit',c10_demo.ami_cfg_bool(p_business,r.site_id,r.category_id,'schedule.auto_submit_generated'),
   'service_category',svc,'est_labor_hours',p.est_labor_hours,'team_ref',p.team_ref);
  due:=CASE WHEN r.frequency_kind='usage' THEN today ELSE r.effective_due_on END;
  BEGIN
   wid:=c10_demo.ami_create_wo(c,p_request,r.asset_id,wkind,left(p.name||' - '||r.asset_name,160),
    'Generated from maintenance plan "'||p.name||'" ('||CASE WHEN r.frequency_kind='usage' THEN 'usage-based' ELSE 'due '||r.effective_due_on::text END||')',
    p.priority,'plan',r.target_id,due,p.checklist_code,extra);
   UPDATE c10_demo.am_plan_targets SET last_wo_id=wid,version=version+1 WHERE id=r.target_id;
   SELECT w.wo_no INTO wno FROM c10_demo.am_work_orders w WHERE w.id=wid;
   PERFORM c10_demo.ami_log(c.tenant_id,p_business,'work_order',wid::text,'generate',NULL,
    jsonb_build_object('wo_no',wno,'plan_id',r.plan_id,'plan_target_id',r.target_id,'asset_id',r.asset_id,'due_on',due),NULL,p_request);
   created:=created||jsonb_build_array(jsonb_build_object('target_id',r.target_id,'wo_id',wid,'wo_no',wno,'asset_id',r.asset_id,'plan_id',r.plan_id,
    'due_on',due,'status',CASE WHEN (extra->>'submit')='true' THEN 'SUBMITTED' ELSE 'DRAFT' END));
  EXCEPTION
   WHEN unique_violation THEN
    skipped:=skipped||jsonb_build_array(jsonb_build_object('target_id',r.target_id,'reason','has_open_wo','asset_id',r.asset_id));
   WHEN OTHERS THEN
    IF SQLERRM IN('am_overlapping_work_order','am_checklist_not_found','am_asset_retired') THEN
     skipped:=skipped||jsonb_build_array(jsonb_build_object('target_id',r.target_id,'reason',substr(SQLERRM,4),'asset_id',r.asset_id));
    ELSE RAISE; END IF;
  END;
 END LOOP;
 IF p_target_ids IS NOT NULL THEN
  FOREACH tid IN ARRAY p_target_ids LOOP
   IF tid=ANY(seen) THEN CONTINUE; END IF;
   SELECT t.status tstatus,p.active pactive,a.status astatus,a.site_id sid,p.end_on,t.next_due_on INTO tr
    FROM c10_demo.am_plan_targets t JOIN c10_demo.am_plans p ON p.id=t.plan_id JOIN c10_demo.am_assets a ON a.id=t.asset_id
    WHERE t.id=tid AND t.business_id=p_business;
   why:=CASE WHEN NOT FOUND OR NOT (tr.sid=ANY(vs)) THEN 'not_found'
             WHEN p_site IS NOT NULL AND tr.sid<>p_site THEN 'out_of_scope'
             WHEN NOT tr.pactive OR tr.tstatus<>'scheduled' OR tr.astatus IN('retired','disposed') THEN 'inactive'
             WHEN tr.end_on IS NOT NULL AND tr.next_due_on>tr.end_on THEN 'plan_ended'
             ELSE 'not_found' END;
   skipped:=skipped||jsonb_build_array(jsonb_build_object('target_id',tid,'reason',why));
  END LOOP;
 END IF;
 PERFORM c10_demo.ami_log(c.tenant_id,p_business,'generation',p_request,'generate',NULL,
  jsonb_build_object('created',jsonb_array_length(created),'skipped',jsonb_array_length(skipped)),NULL,p_request);
 res:=jsonb_build_object('status','applied','created',created,'skipped',skipped,'created_count',jsonb_array_length(created),
  'skipped_count',jsonb_array_length(skipped),'as_of',today);
 RETURN c10_demo.ami_finish(p_business,c.tenant_id,p_request,'generate_wo',pl,res);
END$$;

-- ===================== deferral =====================
CREATE FUNCTION c10_demo.am_defer_target_v1(p_business bigint,p_request text,p_target bigint,p_until date,p_reason text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c c10_demo.am_ctx_t; pl jsonb; t c10_demo.am_plan_targets; p c10_demo.am_plans; a c10_demo.am_assets; maxd int; today date; res jsonb;
 bef jsonb; ev text;
BEGIN
 pl:=jsonb_build_object('target',p_target,'until',p_until,'reason',p_reason);
 SELECT * INTO b FROM c10_demo.ami_begin(p_business,p_request,'defer_target',pl);
 c:=b.o_ctx;
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 SELECT * INTO t FROM c10_demo.am_plan_targets WHERE id=p_target AND business_id=p_business FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'am_denied'; END IF;
 SELECT * INTO a FROM c10_demo.am_assets WHERE id=t.asset_id;
 PERFORM c10_demo.ami_need_cap(c,a.site_id,'plan_write');
 SELECT * INTO p FROM c10_demo.am_plans WHERE id=t.plan_id;
 IF p_reason IS NULL OR length(btrim(p_reason)) NOT BETWEEN 3 AND 500 THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 IF p.frequency_kind='usage' OR t.next_due_on IS NULL OR t.status<>'scheduled' OR NOT p.active THEN RAISE EXCEPTION 'am_target_not_deferrable'; END IF;
 IF EXISTS(SELECT 1 FROM c10_demo.am_work_orders w WHERE w.plan_target_id=t.id AND w.status NOT IN('CLOSED','CANCELLED')) THEN
  RAISE EXCEPTION 'am_target_has_open_wo'; END IF;
 today:=c10_demo.ami_today(p_business);
 maxd:=c10_demo.ami_cfg_int(p_business,a.site_id,a.category_id,'schedule.max_defer_days');
 IF p_until IS NOT NULL THEN
  IF p_until<=today OR p_until<=t.next_due_on THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
  IF p_until>t.next_due_on+maxd THEN RAISE EXCEPTION 'am_defer_limit_exceeded'; END IF;
 END IF;
 bef:=jsonb_build_object('deferred_until',t.deferred_until,'defer_reason',t.defer_reason,'next_due_on',t.next_due_on);
 UPDATE c10_demo.am_plan_targets SET deferred_until=p_until,defer_reason=CASE WHEN p_until IS NULL THEN NULL ELSE btrim(p_reason) END,version=version+1 WHERE id=t.id;
 ev:=CASE WHEN p_until IS NULL THEN 'undefer' ELSE 'defer' END;
 PERFORM c10_demo.ami_log(c.tenant_id,p_business,'plan_target',t.id::text,ev,bef,
  jsonb_build_object('deferred_until',p_until,'defer_reason',CASE WHEN p_until IS NULL THEN NULL ELSE btrim(p_reason) END,'next_due_on',t.next_due_on),btrim(p_reason),p_request);
 res:=jsonb_build_object('status','applied','target_id',t.id,'deferred_until',p_until,'next_due_on',t.next_due_on,'max_until',t.next_due_on+maxd);
 RETURN c10_demo.ami_finish(p_business,c.tenant_id,p_request,'defer_target',pl,res);
END$$;
