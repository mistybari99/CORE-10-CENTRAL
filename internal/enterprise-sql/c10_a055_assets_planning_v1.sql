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
