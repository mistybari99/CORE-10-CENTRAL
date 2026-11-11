-- C10-A055 (2/7): Configurable business rules. Versioned per Business/Site/Category policy with presets, impact preview
-- (pure simulation: nothing real is changed) and schedule simulator. Owner-only writes; every change audited + historised.
-- DISPOSABLE c10_demo ONLY. Apply after core. Contract: docs/architecture/C10_A055_RPC_CONTRACT.md.

-- Validates one value against the static catalog; returns the normalised jsonb value.
CREATE FUNCTION c10_demo.ami_policy_validate(p_key text,p_value jsonb) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE k c10_demo.am_policy_catalog; n numeric; t text;
BEGIN
 SELECT * INTO k FROM c10_demo.am_policy_catalog WHERE key=p_key;
 IF NOT FOUND THEN RAISE EXCEPTION 'am_unknown_policy_key'; END IF;
 IF p_value IS NULL OR jsonb_typeof(p_value)='null' THEN RAISE EXCEPTION 'am_invalid_policy_value'; END IF;
 IF k.vtype='bool' THEN
  IF jsonb_typeof(p_value)<>'boolean' THEN RAISE EXCEPTION 'am_invalid_policy_value'; END IF;
 ELSIF k.vtype IN('int','num') THEN
  IF jsonb_typeof(p_value)<>'number' THEN RAISE EXCEPTION 'am_invalid_policy_value'; END IF;
  n:=(p_value #>> '{}')::numeric;
  IF (k.vtype='int' AND n<>trunc(n)) OR n<k.min_num OR n>k.max_num THEN RAISE EXCEPTION 'am_invalid_policy_value'; END IF;
 ELSE
  IF jsonb_typeof(p_value)<>'string' THEN RAISE EXCEPTION 'am_invalid_policy_value'; END IF;
  t:=p_value #>> '{}';
  IF k.vtype='enum' AND NOT t=ANY(k.enum_values) THEN RAISE EXCEPTION 'am_invalid_policy_value'; END IF;
  IF k.vtype='text' AND (length(t)>64 OR t !~ k.pattern) THEN RAISE EXCEPTION 'am_invalid_policy_value'; END IF;
  IF p_key='general.timezone' AND NOT EXISTS(SELECT 1 FROM pg_timezone_names WHERE name=t) THEN RAISE EXCEPTION 'am_invalid_policy_value'; END IF;
 END IF;
 RETURN p_value;
END$$;

-- Scope must belong to the business. Returns normalised scope_id.
CREATE FUNCTION c10_demo.ami_policy_scope(p_business bigint,p_scope_type text,p_scope_id bigint) RETURNS bigint LANGUAGE plpgsql STABLE AS $$
BEGIN
 IF p_scope_type='business' THEN
  IF COALESCE(p_scope_id,0)<>0 THEN RAISE EXCEPTION 'am_invalid_input'; END IF; RETURN 0;
 ELSIF p_scope_type='site' THEN
  IF p_scope_id IS NULL OR NOT EXISTS(SELECT 1 FROM c10_demo.sites WHERE id=p_scope_id AND business_id=p_business) THEN RAISE EXCEPTION 'am_denied'; END IF;
 ELSIF p_scope_type='category' THEN
  IF p_scope_id IS NULL OR NOT EXISTS(SELECT 1 FROM c10_demo.am_categories WHERE id=p_scope_id AND business_id=p_business) THEN RAISE EXCEPTION 'am_denied'; END IF;
 ELSE RAISE EXCEPTION 'am_invalid_input'; END IF;
 RETURN p_scope_id;
END$$;

-- Cross-key consistency evaluated on the EFFECTIVE values at a scope (after a change is staged).
CREATE FUNCTION c10_demo.ami_policy_consistent(p_business bigint,p_scope_type text,p_scope_id bigint) RETURNS void LANGUAGE plpgsql STABLE AS $$
DECLARE s bigint:=CASE WHEN p_scope_type='site' THEN p_scope_id END; cat bigint:=CASE WHEN p_scope_type='category' THEN p_scope_id END; pr text;
BEGIN
 FOREACH pr IN ARRAY ARRAY['low','medium','high','critical'] LOOP
  IF c10_demo.ami_cfg_int(p_business,s,cat,'sla.resolve_hours.'||pr) < c10_demo.ami_cfg_int(p_business,s,cat,'sla.response_hours.'||pr) THEN
   RAISE EXCEPTION 'am_policy_inconsistent'; END IF;
 END LOOP;
 IF c10_demo.ami_cfg_int(p_business,NULL,NULL,'risk.critical_threshold') <= c10_demo.ami_cfg_int(p_business,NULL,NULL,'risk.high_threshold') THEN
  RAISE EXCEPTION 'am_policy_inconsistent'; END IF;
END$$;

CREATE FUNCTION c10_demo.am_whoami_v1(p_business bigint) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE c am_ctx_t;
BEGIN
 c:=ami_read_ctx(p_business);
 RETURN jsonb_build_object('business_id',p_business,'user_id',c.user_id,
  'level',CASE WHEN c.is_tenant_owner THEN 'tenant_owner' WHEN c.is_business_owner THEN 'business_owner'
            WHEN c.manager_as_supervisor THEN 'manager_supervisor' ELSE 'staff' END,
  'is_owner',ami_is_owner(c),
  'roles',COALESCE((SELECT jsonb_agg(DISTINCT x->>'role') FROM jsonb_array_elements(c.grants) x),'[]'::jsonb),
  'business_caps',to_jsonb(ami_caps(c,NULL)),
  'bootstrapped',EXISTS(SELECT 1 FROM am_settings WHERE business_id=p_business),
  'policy_rev',COALESCE((SELECT policy_rev FROM am_settings WHERE business_id=p_business),0),
  'sites',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',s.id,'kind',s.kind,'label',s.label,'caps',to_jsonb(ami_caps(c,s.id))) ORDER BY s.id)
     FROM sites s WHERE s.business_id=p_business AND cardinality(ami_caps(c,s.id))>0),'[]'::jsonb));
END$$;

CREATE FUNCTION c10_demo.am_policy_catalog_v1(p_business bigint) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE c am_ctx_t;
BEGIN
 c:=ami_read_ctx(p_business);
 RETURN jsonb_build_object('items',COALESCE((SELECT jsonb_agg(jsonb_build_object('key',key,'group',grp,'vtype',vtype,'default',default_value,
   'min',min_num,'max',max_num,'enum',to_jsonb(enum_values),'pattern',pattern,'scopes',to_jsonb(scopes),'level',level,'sort',sort) ORDER BY sort,key)
   FROM am_policy_catalog),'[]'::jsonb),
  'presets',COALESCE((SELECT jsonb_agg(DISTINCT preset) FROM am_policy_presets),'[]'::jsonb));
END$$;

CREATE FUNCTION c10_demo.am_get_policy_v1(p_business bigint,p_site bigint,p_category bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE c am_ctx_t; vals jsonb:='{}'::jsonb; k record; src text; v jsonb;
BEGIN
 c:=ami_read_ctx(p_business);
 IF p_site IS NOT NULL AND NOT EXISTS(SELECT 1 FROM sites WHERE id=p_site AND business_id=p_business) THEN RAISE EXCEPTION 'am_denied'; END IF;
 IF p_category IS NOT NULL AND NOT EXISTS(SELECT 1 FROM am_categories WHERE id=p_category AND business_id=p_business) THEN RAISE EXCEPTION 'am_denied'; END IF;
 FOR k IN SELECT key,default_value FROM am_policy_catalog ORDER BY sort,key LOOP
  src:='default'; v:=k.default_value;
  IF EXISTS(SELECT 1 FROM am_policy WHERE business_id=p_business AND scope_type='business' AND key=k.key) THEN
   src:='business'; SELECT value INTO v FROM am_policy WHERE business_id=p_business AND scope_type='business' AND scope_id=0 AND key=k.key; END IF;
  IF p_site IS NOT NULL AND EXISTS(SELECT 1 FROM am_policy WHERE business_id=p_business AND scope_type='site' AND scope_id=p_site AND key=k.key) THEN
   src:='site'; SELECT value INTO v FROM am_policy WHERE business_id=p_business AND scope_type='site' AND scope_id=p_site AND key=k.key; END IF;
  IF p_category IS NOT NULL AND EXISTS(SELECT 1 FROM am_policy WHERE business_id=p_business AND scope_type='category' AND scope_id=p_category AND key=k.key) THEN
   src:='category'; SELECT value INTO v FROM am_policy WHERE business_id=p_business AND scope_type='category' AND scope_id=p_category AND key=k.key; END IF;
  vals:=vals||jsonb_build_object(k.key,jsonb_build_object('value',v,'source',src,'default',k.default_value,'is_default',v=k.default_value));
 END LOOP;
 RETURN jsonb_build_object('policy_rev',COALESCE((SELECT policy_rev FROM am_settings WHERE business_id=p_business),0),'values',vals,
  'overrides',COALESCE((SELECT jsonb_agg(jsonb_build_object('scope_type',scope_type,'scope_id',scope_id,'key',key,'value',value) ORDER BY scope_type,scope_id,key)
     FROM am_policy WHERE business_id=p_business AND scope_type<>'business'),'[]'::jsonb));
END$$;

-- Shared by save / preset: validates + stages one key at one scope. Returns true when the stored value changed.
CREATE FUNCTION c10_demo.ami_policy_put(c c10_demo.am_ctx_t,p_scope_type text,p_scope_id bigint,p_key text,p_value jsonb,
 p_rev bigint,p_reason text,p_request text) RETURNS boolean LANGUAGE plpgsql SET search_path=c10_demo,pg_catalog AS $$
DECLARE k am_policy_catalog; old jsonb;
BEGIN
 SELECT * INTO k FROM am_policy_catalog WHERE key=p_key;
 IF NOT FOUND THEN RAISE EXCEPTION 'am_unknown_policy_key'; END IF;
 IF NOT p_scope_type=ANY(k.scopes) THEN RAISE EXCEPTION 'am_policy_scope_not_allowed'; END IF;
 IF k.level='tenant_owner' AND NOT c.is_tenant_owner THEN RAISE EXCEPTION 'am_tenant_owner_required'; END IF;
 PERFORM ami_policy_validate(p_key,p_value);
 SELECT value INTO old FROM am_policy WHERE business_id=c.business_id AND scope_type=p_scope_type AND scope_id=p_scope_id AND key=p_key;
 IF FOUND AND old=p_value THEN RETURN false; END IF;
 IF NOT FOUND AND p_scope_type='business' AND p_value=k.default_value THEN RETURN false; END IF;
 INSERT INTO am_policy(business_id,tenant_id,scope_type,scope_id,key,value,updated_by) VALUES(c.business_id,c.tenant_id,p_scope_type,p_scope_id,p_key,p_value,c.user_id)
  ON CONFLICT(business_id,scope_type,scope_id,key) DO UPDATE SET value=EXCLUDED.value,updated_by=EXCLUDED.updated_by,updated_at=now();
 INSERT INTO am_policy_history(business_id,tenant_id,scope_type,scope_id,key,old_value,new_value,rev,reason,actor_uid,request_key)
  VALUES(c.business_id,c.tenant_id,p_scope_type,p_scope_id,p_key,old,p_value,p_rev,p_reason,c.user_id,p_request);
 RETURN true;
END$$;

CREATE FUNCTION c10_demo.am_save_policy_v1(p_business bigint,p_request text,p_expected_rev bigint,p_scope_type text,p_scope_id bigint,
 p_changes jsonb,p_reason text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c am_ctx_t; pay jsonb; sid bigint; cur bigint; k text; n int:=0; res jsonb;
BEGIN
 IF p_changes IS NULL OR jsonb_typeof(p_changes)<>'object' OR p_changes='{}'::jsonb OR (SELECT count(*) FROM jsonb_object_keys(p_changes))>80
  OR p_reason IS NULL OR length(btrim(p_reason)) NOT BETWEEN 5 AND 500 OR p_expected_rev IS NULL THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 pay:=jsonb_build_object('rev',p_expected_rev,'st',p_scope_type,'sid',COALESCE(p_scope_id,0),'c',p_changes,'r',btrim(p_reason));
 SELECT * INTO b FROM ami_begin(p_business,p_request,'save_policy',pay);
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 c:=b.o_ctx; PERFORM ami_need_owner(c);
 sid:=ami_policy_scope(p_business,p_scope_type,p_scope_id);
 SELECT policy_rev INTO cur FROM am_settings WHERE business_id=p_business FOR UPDATE;
 IF cur<>p_expected_rev THEN RAISE EXCEPTION 'am_stale_version'; END IF;
 FOR k IN SELECT jsonb_object_keys(p_changes) LOOP
  IF ami_policy_put(c,p_scope_type,sid,k,p_changes->k,cur+1,btrim(p_reason),p_request) THEN n:=n+1; END IF;
 END LOOP;
 IF n>0 THEN
  PERFORM ami_policy_consistent(p_business,p_scope_type,sid);
  UPDATE am_settings SET policy_rev=policy_rev+1,version=version+1,updated_by=c.user_id,updated_at=now() WHERE business_id=p_business;
  PERFORM ami_log(c.tenant_id,p_business,'policy',p_scope_type||':'||sid,'saved',NULL,p_changes,btrim(p_reason),p_request);
 END IF;
 res:=jsonb_build_object('status','applied','changed',n,'policy_rev',cur+(n>0)::int);
 RETURN ami_finish(p_business,c.tenant_id,p_request,'save_policy',pay,res);
END$$;

CREATE FUNCTION c10_demo.am_reset_policy_v1(p_business bigint,p_request text,p_expected_rev bigint,p_scope_type text,p_scope_id bigint,
 p_keys text[],p_reason text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c am_ctx_t; pay jsonb; sid bigint; cur bigint; k text; n int:=0; old jsonb; res jsonb; lvl text;
BEGIN
 IF p_keys IS NULL OR cardinality(p_keys)=0 OR cardinality(p_keys)>80 OR p_reason IS NULL OR length(btrim(p_reason)) NOT BETWEEN 5 AND 500
  OR p_expected_rev IS NULL THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 pay:=jsonb_build_object('rev',p_expected_rev,'st',p_scope_type,'sid',COALESCE(p_scope_id,0),'k',to_jsonb(p_keys),'r',btrim(p_reason));
 SELECT * INTO b FROM ami_begin(p_business,p_request,'reset_policy',pay);
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 c:=b.o_ctx; PERFORM ami_need_owner(c);
 sid:=ami_policy_scope(p_business,p_scope_type,p_scope_id);
 SELECT policy_rev INTO cur FROM am_settings WHERE business_id=p_business FOR UPDATE;
 IF cur<>p_expected_rev THEN RAISE EXCEPTION 'am_stale_version'; END IF;
 FOREACH k IN ARRAY p_keys LOOP
  SELECT level INTO lvl FROM am_policy_catalog WHERE key=k;
  IF NOT FOUND THEN RAISE EXCEPTION 'am_unknown_policy_key'; END IF;
  IF lvl='tenant_owner' AND NOT c.is_tenant_owner THEN RAISE EXCEPTION 'am_tenant_owner_required'; END IF;
  DELETE FROM am_policy WHERE business_id=p_business AND scope_type=p_scope_type AND scope_id=sid AND key=k RETURNING value INTO old;
  IF FOUND THEN
   n:=n+1;
   INSERT INTO am_policy_history(business_id,tenant_id,scope_type,scope_id,key,old_value,new_value,rev,reason,actor_uid,request_key)
    VALUES(p_business,c.tenant_id,p_scope_type,sid,k,old,NULL,cur+1,btrim(p_reason),c.user_id,p_request);
  END IF;
 END LOOP;
 IF n>0 THEN
  PERFORM ami_policy_consistent(p_business,p_scope_type,sid);
  UPDATE am_settings SET policy_rev=policy_rev+1,version=version+1,updated_by=c.user_id,updated_at=now() WHERE business_id=p_business;
  PERFORM ami_log(c.tenant_id,p_business,'policy',p_scope_type||':'||sid,'reset',NULL,to_jsonb(p_keys),btrim(p_reason),p_request);
 END IF;
 res:=jsonb_build_object('status','applied','removed',n,'policy_rev',cur+(n>0)::int);
 RETURN ami_finish(p_business,c.tenant_id,p_request,'reset_policy',pay,res);
END$$;

CREATE FUNCTION c10_demo.am_apply_preset_v1(p_business bigint,p_request text,p_expected_rev bigint,p_preset text,p_scope_type text,
 p_scope_id bigint,p_reason text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c am_ctx_t; pay jsonb; sid bigint; cur bigint; r record; n int:=0; skipped jsonb:='[]'::jsonb; res jsonb; k am_policy_catalog;
BEGIN
 IF p_preset IS NULL OR p_expected_rev IS NULL OR p_reason IS NULL OR length(btrim(p_reason)) NOT BETWEEN 5 AND 500 THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 IF NOT EXISTS(SELECT 1 FROM am_policy_presets WHERE preset=p_preset) THEN RAISE EXCEPTION 'am_unknown_preset'; END IF;
 pay:=jsonb_build_object('rev',p_expected_rev,'p',p_preset,'st',p_scope_type,'sid',COALESCE(p_scope_id,0),'r',btrim(p_reason));
 SELECT * INTO b FROM ami_begin(p_business,p_request,'apply_preset',pay);
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 c:=b.o_ctx; PERFORM ami_need_owner(c);
 sid:=ami_policy_scope(p_business,p_scope_type,p_scope_id);
 SELECT policy_rev INTO cur FROM am_settings WHERE business_id=p_business FOR UPDATE;
 IF cur<>p_expected_rev THEN RAISE EXCEPTION 'am_stale_version'; END IF;
 FOR r IN SELECT key,value FROM am_policy_presets WHERE preset=p_preset ORDER BY key LOOP
  SELECT * INTO k FROM am_policy_catalog WHERE key=r.key;
  IF NOT p_scope_type=ANY(k.scopes) OR (k.level='tenant_owner' AND NOT c.is_tenant_owner) THEN
   skipped:=skipped||to_jsonb(r.key); CONTINUE; END IF;
  IF ami_policy_put(c,p_scope_type,sid,r.key,r.value,cur+1,'preset '||p_preset||': '||btrim(p_reason),p_request) THEN n:=n+1; END IF;
 END LOOP;
 IF n>0 THEN
  PERFORM ami_policy_consistent(p_business,p_scope_type,sid);
  UPDATE am_settings SET policy_rev=policy_rev+1,version=version+1,updated_by=c.user_id,updated_at=now() WHERE business_id=p_business;
  PERFORM ami_log(c.tenant_id,p_business,'policy',p_scope_type||':'||sid,'preset_applied',NULL,jsonb_build_object('preset',p_preset,'changed',n),btrim(p_reason),p_request);
 END IF;
 res:=jsonb_build_object('status','applied','preset',p_preset,'changed',n,'skipped',skipped,'policy_rev',cur+(n>0)::int);
 RETURN ami_finish(p_business,c.tenant_id,p_request,'apply_preset',pay,res);
END$$;

-- Impact preview: pure SIMULATION. Reads current operational data and reports what WOULD change. Writes nothing.
CREATE FUNCTION c10_demo.am_preview_policy_v1(p_business bigint,p_scope_type text,p_scope_id bigint,p_changes jsonb) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE c am_ctx_t; sid bigint; k text; v jsonb; kd am_policy_catalog; old jsonb; items jsonb:='[]'::jsonb; imp jsonb; today date; s bigint; cat bigint;
 a int; b2 int; oldn numeric; newn numeric; pr text; nowts timestamptz:=now();
BEGIN
 c:=ami_read_ctx(p_business); PERFORM ami_need_owner(c);
 IF p_changes IS NULL OR jsonb_typeof(p_changes)<>'object' OR p_changes='{}'::jsonb OR (SELECT count(*) FROM jsonb_object_keys(p_changes))>80 THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 sid:=ami_policy_scope(p_business,p_scope_type,p_scope_id);
 s:=CASE WHEN p_scope_type='site' THEN sid END; cat:=CASE WHEN p_scope_type='category' THEN sid END;
 today:=ami_today(p_business);
 FOR k IN SELECT jsonb_object_keys(p_changes) ORDER BY 1 LOOP
  v:=p_changes->k;
  SELECT * INTO kd FROM am_policy_catalog WHERE key=k;
  IF NOT FOUND THEN RAISE EXCEPTION 'am_unknown_policy_key'; END IF;
  IF NOT p_scope_type=ANY(kd.scopes) THEN RAISE EXCEPTION 'am_policy_scope_not_allowed'; END IF;
  PERFORM ami_policy_validate(k,v);
  old:=ami_cfg(p_business,s,cat,k); imp:='{}'::jsonb;
  IF k LIKE 'sla.resolve_hours.%' THEN
   pr:=split_part(k,'.',3); newn:=(v #>> '{}')::numeric; oldn:=(old #>> '{}')::numeric;
   SELECT count(*) FILTER (WHERE sla_resolve_due_at<nowts),
          count(*) FILTER (WHERE requested_at+make_interval(hours=>newn::int)<nowts)
     INTO a,b2 FROM am_work_orders w WHERE w.business_id=p_business AND w.priority=pr AND w.status NOT IN('COMPLETED','VERIFIED','CLOSED','CANCELLED')
      AND (s IS NULL OR w.site_id=s);
   imp:=jsonb_build_object('open_work_orders_in_priority',(SELECT count(*) FROM am_work_orders w WHERE w.business_id=p_business AND w.priority=pr
        AND w.status NOT IN('COMPLETED','VERIFIED','CLOSED','CANCELLED') AND (s IS NULL OR w.site_id=s)),'breached_now_before',a,'breached_now_after',b2);
  ELSIF k LIKE 'sla.response_hours.%' THEN
   pr:=split_part(k,'.',3); newn:=(v #>> '{}')::numeric;
   SELECT count(*) FILTER (WHERE sla_response_due_at<nowts),count(*) FILTER (WHERE requested_at+make_interval(hours=>newn::int)<nowts)
     INTO a,b2 FROM am_work_orders w WHERE w.business_id=p_business AND w.priority=pr AND w.responded_at IS NULL
      AND w.status NOT IN('IN_PROGRESS','COMPLETED','VERIFIED','CLOSED','CANCELLED') AND (s IS NULL OR w.site_id=s);
   imp:=jsonb_build_object('unanswered_breached_before',a,'unanswered_breached_after',b2);
  ELSIF k IN('schedule.due_lead_days','schedule.grace_days') THEN
   newn:=(v #>> '{}')::numeric; oldn:=(old #>> '{}')::numeric;
   IF k='schedule.due_lead_days' THEN
    SELECT count(*) FILTER (WHERE t.next_due_on<=today+oldn::int),count(*) FILTER (WHERE t.next_due_on<=today+newn::int) INTO a,b2
     FROM am_plan_targets t JOIN am_assets x ON x.id=t.asset_id WHERE t.business_id=p_business AND t.status='scheduled' AND t.next_due_on IS NOT NULL
      AND (s IS NULL OR x.site_id=s) AND (cat IS NULL OR x.category_id=cat);
    imp:=jsonb_build_object('suggested_now_before',a,'suggested_now_after',b2);
   ELSE
    SELECT count(*) FILTER (WHERE t.next_due_on+oldn::int<today),count(*) FILTER (WHERE t.next_due_on+newn::int<today) INTO a,b2
     FROM am_plan_targets t JOIN am_assets x ON x.id=t.asset_id WHERE t.business_id=p_business AND t.status='scheduled' AND t.next_due_on IS NOT NULL
      AND (s IS NULL OR x.site_id=s) AND (cat IS NULL OR x.category_id=cat);
    imp:=jsonb_build_object('escalated_overdue_before',a,'escalated_overdue_after',b2);
   END IF;
  ELSIF k IN('wo.approval_min_priority','wo.approval_cost_threshold') THEN
   SELECT count(*) INTO a FROM am_work_orders w WHERE w.business_id=p_business AND w.status IN('DRAFT','SUBMITTED') AND (s IS NULL OR w.site_id=s);
   imp:=jsonb_build_object('open_draft_or_submitted_work_orders',a,
     'note','Already-approved work orders are never re-opened by a policy change; the new rule applies to future submissions.');
  ELSIF k='wo.verify_required' THEN
   SELECT count(*) INTO a FROM am_work_orders w WHERE w.business_id=p_business AND w.status='COMPLETED' AND (s IS NULL OR w.site_id=s);
   imp:=jsonb_build_object('completed_awaiting_verification',a);
  ELSIF k='downtime.max_open_hours' THEN
   newn:=(v #>> '{}')::numeric; oldn:=(old #>> '{}')::numeric;
   SELECT count(*) FILTER (WHERE d.started_at<nowts-make_interval(hours=>oldn::int)),count(*) FILTER (WHERE d.started_at<nowts-make_interval(hours=>newn::int)) INTO a,b2
    FROM am_downtime d WHERE d.business_id=p_business AND d.ended_at IS NULL AND (s IS NULL OR d.site_id=s);
   imp:=jsonb_build_object('open_windows_flagged_before',a,'open_windows_flagged_after',b2);
  ELSIF k='meter.stale_days' THEN
   newn:=(v #>> '{}')::numeric; oldn:=(old #>> '{}')::numeric;
   SELECT count(*) FILTER (WHERE m.last_reading_at IS NULL OR m.last_reading_at<nowts-make_interval(days=>oldn::int)),
          count(*) FILTER (WHERE m.last_reading_at IS NULL OR m.last_reading_at<nowts-make_interval(days=>newn::int)) INTO a,b2
    FROM am_meters m JOIN am_assets x ON x.id=m.asset_id WHERE m.business_id=p_business AND m.active AND x.status NOT IN('retired','disposed')
     AND (s IS NULL OR x.site_id=s) AND (cat IS NULL OR x.category_id=cat);
   imp:=jsonb_build_object('stale_meters_before',a,'stale_meters_after',b2);
  ELSIF k='asset.warranty_warn_days' THEN
   newn:=(v #>> '{}')::numeric; oldn:=(old #>> '{}')::numeric;
   SELECT count(*) FILTER (WHERE w.expires_on BETWEEN today AND today+oldn::int),count(*) FILTER (WHERE w.expires_on BETWEEN today AND today+newn::int) INTO a,b2
    FROM am_warranties w JOIN am_assets x ON x.id=w.asset_id WHERE w.business_id=p_business AND w.status='active' AND (s IS NULL OR x.site_id=s) AND (cat IS NULL OR x.category_id=cat);
   imp:=jsonb_build_object('expiring_before',a,'expiring_after',b2);
  ELSIF k='wo.maker_checker' THEN
   imp:=jsonb_build_object('warning','Turning maker-checker OFF lets the same person request, approve and verify. Tenant-owner decision; audited.');
  ELSIF k LIKE 'finance.%' THEN
   imp:=jsonb_build_object('advisory_only',true,'posted',false,'note','Depreciation/valuation figures are advisory and never posted to a ledger.');
  ELSE
   imp:=jsonb_build_object('note','Applies to future actions; no existing record is altered.');
  END IF;
  items:=items||jsonb_build_object('key',k,'scope_type',p_scope_type,'scope_id',sid,'old',old,'new',v,'changed',old<>v,'impact',imp,'level',kd.level);
 END LOOP;
 RETURN jsonb_build_object('simulation',true,'applied',false,'writes',0,'message','SIMULATION — no real asset, work order or schedule is changed.',
  'items',items,'policy_rev',COALESCE((SELECT policy_rev FROM am_settings WHERE business_id=p_business),0),
  'requires_tenant_owner',EXISTS(SELECT 1 FROM jsonb_object_keys(p_changes) q JOIN am_policy_catalog g ON g.key=q WHERE g.level='tenant_owner'));
END$$;

-- Pure schedule simulator (no tables touched): "if I create a plan like this, when would it fall due?"
CREATE FUNCTION c10_demo.ami_sim_step(p_from date,p_kind text,p_n int) RETURNS date LANGUAGE sql IMMUTABLE AS $$
 SELECT CASE p_kind WHEN 'daily' THEN p_from+p_n WHEN 'weekly' THEN p_from+7*p_n
  WHEN 'monthly' THEN (p_from+make_interval(months=>p_n))::date WHEN 'yearly' THEN (p_from+make_interval(years=>p_n))::date END $$;
CREATE FUNCTION c10_demo.am_simulate_schedule_v1(p_business bigint,p_params jsonb) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE c am_ctx_t; kind text; n int; start date; cnt int; delay int; anchor text; per int; out jsonb:='[]'::jsonb; due date:=NULL; i int; prev date; uint numeric; daily numeric; cur numeric; k text;
BEGIN
 c:=ami_read_ctx(p_business);
 IF p_params IS NULL OR jsonb_typeof(p_params)<>'object' THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 FOR k IN SELECT jsonb_object_keys(p_params) LOOP
  IF NOT k=ANY(ARRAY['frequency_kind','interval_n','start_on','count','typical_delay_days','anchor','usage_interval','avg_daily_usage','current_reading']) THEN RAISE EXCEPTION 'am_invalid_input'; END IF; END LOOP;
 BEGIN
  kind:=p_params->>'frequency_kind'; n:=COALESCE((p_params->>'interval_n')::int,1); cnt:=LEAST(COALESCE((p_params->>'count')::int,6),24);
  start:=COALESCE((p_params->>'start_on')::date,ami_today(p_business)); delay:=COALESCE((p_params->>'typical_delay_days')::int,0);
  anchor:=COALESCE(p_params->>'anchor',ami_cfg_text(p_business,NULL,NULL,'schedule.anchor'));
 EXCEPTION WHEN others THEN RAISE EXCEPTION 'am_invalid_input'; END;
 IF kind NOT IN('daily','weekly','monthly','yearly','usage') OR n NOT BETWEEN 1 AND 3650 OR cnt<1 OR delay NOT BETWEEN 0 AND 365
  OR anchor NOT IN('from_completion','from_due_date') THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
 IF kind='usage' THEN
  BEGIN uint:=(p_params->>'usage_interval')::numeric; daily:=(p_params->>'avg_daily_usage')::numeric; cur:=COALESCE((p_params->>'current_reading')::numeric,0);
  EXCEPTION WHEN others THEN RAISE EXCEPTION 'am_invalid_input'; END;
  IF uint IS NULL OR uint<=0 OR daily IS NULL OR daily<=0 THEN RAISE EXCEPTION 'am_invalid_input'; END IF;
  FOR i IN 1..cnt LOOP
   out:=out||jsonb_build_object('n',i,'due_reading',cur+uint*i,'estimated_due_on',ami_today(p_business)+ceil((uint*i)/daily)::int);
  END LOOP;
 ELSE
  prev:=start;
  FOR i IN 1..cnt LOOP
   IF anchor='from_due_date' THEN due:=ami_sim_step(start,kind,n*i); ELSE due:=ami_sim_step(prev,kind,n); END IF;
   out:=out||jsonb_build_object('n',i,'due_on',due,'weekday',to_char(due,'Dy'));
   prev:=due+delay;
  END LOOP;
 END IF;
 RETURN jsonb_build_object('simulation',true,'writes',0,'anchor',anchor,'items',out,
  'message','SIMULATION — no plan, work order or asset is created. Nothing runs automatically.');
END$$;

CREATE FUNCTION c10_demo.am_policy_history_v1(p_business bigint,p_limit int) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE c am_ctx_t;
BEGIN
 c:=ami_read_ctx(p_business);
 IF NOT (ami_is_owner(c) OR 'audit_read'=ANY(ami_caps(c,NULL))) THEN RAISE EXCEPTION 'am_not_permitted'; END IF;
 RETURN jsonb_build_object('items',COALESCE((SELECT jsonb_agg(to_jsonb(h)-'tenant_id' ORDER BY h.id DESC) FROM
   (SELECT * FROM am_policy_history WHERE business_id=p_business ORDER BY id DESC LIMIT LEAST(GREATEST(COALESCE(p_limit,50),1),200)) h),'[]'::jsonb));
END$$;

CREATE FUNCTION c10_demo.am_bootstrap_v1(p_business bigint,p_request text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c am_ctx_t; pay jsonb:='{}'::jsonb; res jsonb;
BEGIN
 SELECT * INTO b FROM ami_begin(p_business,p_request,'bootstrap',pay);
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 c:=b.o_ctx; PERFORM ami_need_owner(c);
 res:=jsonb_build_object('status','applied','categories',(SELECT count(*) FROM am_categories WHERE business_id=p_business),
  'codes',(SELECT count(*) FROM am_codes WHERE business_id=p_business),'policy_rev',(SELECT policy_rev FROM am_settings WHERE business_id=p_business));
 PERFORM ami_log(c.tenant_id,p_business,'settings',p_business::text,'bootstrapped',NULL,res,'bootstrap',p_request);
 RETURN ami_finish(p_business,c.tenant_id,p_request,'bootstrap',pay,res);
END$$;
