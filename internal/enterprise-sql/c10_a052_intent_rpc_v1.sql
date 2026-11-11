-- C10-A052 | Owner Intent RPCs: submit -> (revise) -> preview -> validate -> approve -> publish -> rollback.
-- DISPOSABLE c10_demo ONLY. All functions are SECURITY DEFINER with a pinned search_path and re-check the signed
-- actor on every call. Publishing is ADVISORY CONFIGURATION ONLY: nothing here posts stock, money, payroll,
-- accounts, permissions or users. Publishing A045_ENGINE capabilities goes through the A045 RPCs (single registry).

-- ---------------------------------------------------------------- internal helpers (not granted to app roles)
CREATE FUNCTION c10_demo.intent_req_v1(p_request text) RETURNS void LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
 IF p_request IS NULL OR p_request !~ '^[A-Za-z0-9_-]{8,90}$' THEN RAISE EXCEPTION 'invalid_intent_request'; END IF;
END$$;
CREATE FUNCTION c10_demo.intent_reason_v1(p_reason text) RETURNS void LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
 IF p_reason IS NULL OR length(btrim(p_reason)) NOT BETWEEN 5 AND 500 OR p_reason ~ '[\x01-\x08\x0b\x0c\x0e-\x1f\x7f]'
 THEN RAISE EXCEPTION 'invalid_intent_request'; END IF;
END$$;
-- level: 'tenant' (Owner only), 'manage' (Owner or Business Owner), 'see' (any member who can see the business)
CREATE FUNCTION c10_demo.intent_scope_v1(p_business bigint,p_level text) RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE t bigint; ok boolean;
BEGIN
 IF c10_demo.actor_uid() IS NULL OR p_business IS NULL THEN RAISE EXCEPTION 'intent_denied'; END IF;
 SELECT tenant_id INTO t FROM c10_demo.businesses WHERE id=p_business;
 IF t IS NULL THEN RAISE EXCEPTION 'intent_denied'; END IF;
 ok:=CASE p_level WHEN 'tenant' THEN c10_demo.can_tenant(t) WHEN 'manage' THEN c10_demo.can_manage(t,p_business)
      ELSE c10_demo.can_see_business(t,p_business) END;
 IF NOT COALESCE(ok,false) THEN RAISE EXCEPTION 'intent_denied'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('a052:'||p_business::text,0));
 RETURN t;
END$$;
CREATE FUNCTION c10_demo.intent_replay_v1(p_tenant bigint,p_request text,p_payload jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE r c10_demo.intent_receipts_v1%ROWTYPE;
BEGIN
 SELECT * INTO r FROM c10_demo.intent_receipts_v1 WHERE tenant_id=p_tenant AND request_key=p_request;
 IF NOT FOUND THEN RETURN NULL; END IF;
 IF r.actor_uid<>c10_demo.actor_uid() OR r.payload<>p_payload THEN RAISE EXCEPTION 'intent_idempotency_conflict'; END IF;
 RETURN r.result;
END$$;
CREATE FUNCTION c10_demo.intent_store_v1(p_tenant bigint,p_request text,p_payload jsonb,p_result jsonb) RETURNS void LANGUAGE sql AS $$
 INSERT INTO c10_demo.intent_receipts_v1(tenant_id,request_key,actor_uid,payload,result)
 VALUES(p_tenant,p_request,c10_demo.actor_uid(),p_payload,p_result)
$$;
CREATE FUNCTION c10_demo.intent_event_v1(p_tenant bigint,p_business bigint,p_intent bigint,p_key text,p_event text,
 p_before jsonb,p_after jsonb,p_request text) RETURNS void LANGUAGE sql AS $$
 INSERT INTO c10_demo.owner_intent_events_v1(tenant_id,business_id,intent_id,setting_key,event,before_state,after_state,actor_uid,request_key)
 VALUES(p_tenant,p_business,p_intent,p_key,p_event,p_before,p_after,c10_demo.actor_uid(),p_request)
$$;

-- Validates the structured interpretation produced by the client rule-parser. Returns the derived support status.
CREATE FUNCTION c10_demo.intent_check_interpretation_v1(i jsonb) RETURNS text LANGUAGE plpgsql STABLE AS $$
DECLARE ss text; cap text; prm jsonb;
BEGIN
 IF i IS NULL OR jsonb_typeof(i)<>'object' OR length(i::text)>12000 THEN RAISE EXCEPTION 'invalid_interpretation'; END IF;
 IF jsonb_typeof(i->'locale')<>'string' OR i->>'locale' NOT IN('bn','en','mixed') THEN RAISE EXCEPTION 'invalid_locale'; END IF;
 IF jsonb_typeof(i->'parser_version')<>'string' OR length(i->>'parser_version')>40 THEN RAISE EXCEPTION 'invalid_interpretation'; END IF;
 IF jsonb_typeof(i->'support_status')<>'string' THEN RAISE EXCEPTION 'invalid_interpretation'; END IF;
 ss:=i->>'support_status';
 IF ss NOT IN('SUPPORTED','NEEDS_CLARIFICATION','ENGINEERING_REQUIRED','UNSUPPORTED') THEN RAISE EXCEPTION 'invalid_interpretation'; END IF;
 IF i?'assumptions' AND (jsonb_typeof(i->'assumptions')<>'array' OR jsonb_array_length(i->'assumptions')>20) THEN RAISE EXCEPTION 'invalid_interpretation'; END IF;
 IF i?'missing' AND jsonb_typeof(i->'missing')<>'array' THEN RAISE EXCEPTION 'invalid_interpretation'; END IF;
 cap:=CASE WHEN jsonb_typeof(i->'capability_key')='string' THEN i->>'capability_key' END;
 prm:=COALESCE(i->'params','{}'::jsonb);
 IF ss='SUPPORTED' THEN
  IF cap IS NULL OR NOT EXISTS(SELECT 1 FROM c10_demo.intent_capabilities_v1 WHERE capability_key=cap AND certified) THEN
   RAISE EXCEPTION 'capability_not_certified'; END IF;
  IF NOT c10_demo.intent_params_valid_v1(cap,prm) THEN RAISE EXCEPTION 'invalid_intent_params'; END IF;
  IF COALESCE(jsonb_array_length(i->'missing'),0)>0 THEN RAISE EXCEPTION 'invalid_interpretation'; END IF;
 ELSIF ss='NEEDS_CLARIFICATION' THEN
  IF cap IS NOT NULL AND NOT EXISTS(SELECT 1 FROM c10_demo.intent_capabilities_v1 WHERE capability_key=cap AND certified) THEN
   RAISE EXCEPTION 'capability_not_certified'; END IF;
  IF jsonb_typeof(prm)<>'object' THEN RAISE EXCEPTION 'invalid_interpretation'; END IF;
 ELSE
  IF cap IS NOT NULL THEN RAISE EXCEPTION 'capability_not_certified'; END IF;
  IF jsonb_typeof(i->'unsupported')<>'object' OR jsonb_typeof(i->'unsupported'->'category')<>'string'
     OR i->'unsupported'->>'category' !~ '^[a-z][a-z0-9_]{2,40}$' OR jsonb_typeof(i->'unsupported'->'requirement')<>'object'
  THEN RAISE EXCEPTION 'invalid_interpretation'; END IF;
 END IF;
 RETURN ss;
END$$;

-- The one place that builds a preview. STABLE, no writes: used by preview, validate, approve and publish so the
-- server can detect a changed world (stale basis) instead of trusting what the client saw.
CREATE FUNCTION c10_demo.intent_build_preview_v1(p_intent bigint) RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE i c10_demo.owner_intents_v1%ROWTYPE; c c10_demo.intent_capabilities_v1%ROWTYPE; cur c10_demo.intent_settings_v1%ROWTYPE;
 sample jsonb; after_eval jsonb; before_eval jsonb; diff jsonb:='[]'::jsonb; conflicts jsonb:='[]'::jsonb; mods jsonb:='[]'::jsonb;
 k text; m jsonb; ms c10_demo.business_module_settings_v1%ROWTYPE; ekey text; blocked boolean; core jsonb; have_cur boolean;
BEGIN
 SELECT * INTO i FROM c10_demo.owner_intents_v1 WHERE id=p_intent;
 SELECT * INTO c FROM c10_demo.intent_capabilities_v1 WHERE capability_key=i.capability_key;
 IF NOT FOUND OR NOT c.certified THEN RAISE EXCEPTION 'capability_not_certified'; END IF;
 sample:=COALESCE(i.sample,c.sample_inputs);
 after_eval:=c10_demo.intent_eval_v1(c.capability_key,i.params,sample);
 SELECT * INTO cur FROM c10_demo.intent_settings_v1 WHERE business_id=i.business_id AND setting_key=c.capability_key AND state='ACTIVE';
 have_cur:=FOUND;
 IF have_cur THEN before_eval:=c10_demo.intent_eval_v1(c.capability_key,cur.params,sample); END IF;
 -- dry-run diff (what WOULD change on publish)
 FOR k IN SELECT x FROM (SELECT jsonb_object_keys(i.params) x UNION SELECT jsonb_object_keys(CASE WHEN have_cur THEN cur.params ELSE '{}'::jsonb END)) s ORDER BY 1 LOOP
  IF NOT have_cur OR (cur.params->k) IS DISTINCT FROM (i.params->k) THEN
   diff:=diff||jsonb_build_array(jsonb_build_object('path','params.'||k,'before',CASE WHEN have_cur THEN cur.params->k END,'after',i.params->k));
  END IF;
 END LOOP;
 diff:=diff||jsonb_build_array(jsonb_build_object('path','setting.state',
   'before',CASE WHEN have_cur THEN 'ACTIVE v'||cur.version ELSE 'none' END,
   'after','ACTIVE v'||(COALESCE((SELECT max(version) FROM c10_demo.intent_settings_v1 WHERE business_id=i.business_id AND setting_key=c.capability_key),0)+1)));
 -- conflicts / blockers
 IF have_cur AND cur.params=i.params THEN
  conflicts:=conflicts||jsonb_build_array(jsonb_build_object('code','NO_EFFECTIVE_CHANGE','severity','blocking',
   'message_en','The active setting already has exactly these values.','message_bn','সক্রিয় সেটিংয়ে ঠিক এই মানই আছে।'));
 ELSIF have_cur THEN
  conflicts:=conflicts||jsonb_build_array(jsonb_build_object('code','WILL_SUPERSEDE_ACTIVE','severity','warning',
   'message_en','Publishing creates version '||(cur.version+1)||' and supersedes version '||cur.version||'; the old version stays in history.',
   'message_bn','প্রকাশ করলে সংস্করণ '||(cur.version+1)||' তৈরি হবে এবং সংস্করণ '||cur.version||' বাতিল-তালিকায় যাবে; পুরোনোটি ইতিহাসে থাকবে।'));
 END IF;
 IF c.route='A045_ENGINE' THEN
  ekey:='a052_'||c.capability_key||'_b'||i.business_id;
  IF NOT have_cur AND EXISTS(SELECT 1 FROM c10_demo.micro_engines_v1 WHERE tenant_id=i.tenant_id AND engine_key=ekey) THEN
   conflicts:=conflicts||jsonb_build_array(jsonb_build_object('code','A045_ENGINE_UNMANAGED','severity','blocking',
    'message_en','An A045 engine with this key already exists outside A052 history; resolve it in the Workshop first.',
    'message_bn','এই কী-র একটি A045 ইঞ্জিন A052 ইতিহাসের বাইরে আছে; আগে ওয়ার্কশপে মেটান।'));
  END IF;
  IF NOT EXISTS(SELECT 1 FROM c10_demo.micro_engine_handlers_v1 WHERE handler_id=c.a045_handler_id AND certified AND can_execute) THEN
   conflicts:=conflicts||jsonb_build_array(jsonb_build_object('code','A045_HANDLER_NOT_CERTIFIED','severity','blocking',
    'message_en','The A045 handler is not certified/executable.','message_bn','A045 হ্যান্ডলার সার্টিফাইড/চালনাযোগ্য নয়।'));
  END IF;
 END IF;
 IF i.site_id IS NOT NULL THEN
  conflicts:=conflicts||jsonb_build_array(jsonb_build_object('code','SITE_SCOPE_BUSINESS_LEVEL','severity','warning',
   'message_en','You named a site; v1 handlers store business-level settings, so this applies to the whole business, not only that site.',
   'message_bn','আপনি সাইট উল্লেখ করেছেন; v1 হ্যান্ডলার ব্যবসা-স্তরে সংরক্ষণ করে, তাই এটি শুধু ঐ সাইটে নয়, পুরো ব্যবসায় প্রযোজ্য।'));
 END IF;
 FOR m IN SELECT jsonb_array_elements(c.impact->'downstream_modules') LOOP
  SELECT * INTO ms FROM c10_demo.business_module_settings_v1 WHERE business_id=i.business_id AND module_code=m->>'module_code';
  mods:=mods||jsonb_build_array(m||jsonb_build_object('state',CASE WHEN FOUND THEN ms.visibility ELSE 'not_provisioned' END,'operational_enabled',false));
  IF NOT FOUND THEN
   conflicts:=conflicts||jsonb_build_array(jsonb_build_object('code','MODULE_NOT_PROVISIONED','severity','info','module_code',m->>'module_code',
    'message_en','Module '||(m->>'module_code')||' is not provisioned for this business; the setting is stored but nothing consumes it yet.',
    'message_bn','মডিউল '||(m->>'module_code')||' এই ব্যবসায় চালু নয়; সেটিং সংরক্ষিত হবে কিন্তু এখনো কেউ ব্যবহার করবে না।'));
  ELSIF ms.visibility='hidden' THEN
   conflicts:=conflicts||jsonb_build_array(jsonb_build_object('code','MODULE_HIDDEN','severity','warning','module_code',m->>'module_code',
    'message_en','Module '||(m->>'module_code')||' is hidden for this business.','message_bn','মডিউল '||(m->>'module_code')||' এই ব্যবসায় লুকানো।'));
  END IF;
 END LOOP;
 conflicts:=conflicts||jsonb_build_array(jsonb_build_object('code','OTHER_BUSINESSES_UNCHANGED','severity','info',
  'message_en','Only this business is affected. Other businesses and tenants are unchanged.','message_bn','শুধু এই ব্যবসা প্রভাবিত হবে। অন্য ব্যবসা ও টেন্যান্ট অপরিবর্তিত।'));
 blocked:=EXISTS(SELECT 1 FROM jsonb_array_elements(conflicts) x WHERE x->>'severity'='blocking');
 core:=jsonb_build_object(
  'intent_id',i.id,'intent_version',i.version,'capability_key',c.capability_key,'route',c.route,
  'business_id',i.business_id,'tenant_id',i.tenant_id,'site_id',i.site_id,
  'proposed',jsonb_build_object('params',i.params),
  'current',CASE WHEN have_cur THEN jsonb_build_object('version',cur.version,'params',cur.params) END,
  'basis_version',COALESCE(cur.version,0),
  'diff',diff,
  'sample',jsonb_build_object('inputs',sample,'before',before_eval,'after',after_eval),
  'formula',after_eval->'formula',
  'impact',jsonb_build_object('entities',c.impact->'entities','formulas',c.impact->'formulas','reports',c.impact->'reports',
    'permissions',c.impact->'permissions','approvals',c.impact->'approvals','downstream_modules',mods,
    'conflicts',conflicts,'blocked',blocked,'unsafe','[]'::jsonb,'missing','[]'::jsonb),
  'effect',jsonb_build_object('writes_now',false,'applies_on_publish',true,'advisory_only',true,'operational_enforcement',false,
    'a045_engine_key',ekey,'engine_route',c.route));
 RETURN core;
END$$;
CREATE FUNCTION c10_demo.intent_preview_hash_v1(p jsonb) RETURNS text LANGUAGE sql IMMUTABLE AS $$ SELECT md5(p::text) $$;

-- ---------------------------------------------------------------- Owner / Business Owner: submit
CREATE FUNCTION c10_demo.submit_owner_intent_v1(p_business bigint,p_site bigint,p_text text,p_interpretation jsonb,p_request text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $fn$
DECLARE t bigint; pay jsonb; res jsonb; ss text; st text; nid bigint; cap text; req jsonb; cat text; hid text;
BEGIN
 PERFORM c10_demo.intent_req_v1(p_request);
 t:=c10_demo.intent_scope_v1(p_business,'manage');
 IF p_text IS NULL OR length(btrim(p_text)) NOT BETWEEN 3 AND 1000 OR p_text ~ '[\x01-\x08\x0b\x0c\x0e-\x1f\x7f]'
 THEN RAISE EXCEPTION 'invalid_intent_text'; END IF;
 pay:=jsonb_build_object('op','submit','business',p_business,'site',p_site,'text',btrim(p_text),'interp',p_interpretation);
 res:=c10_demo.intent_replay_v1(t,p_request,pay);
 IF res IS NOT NULL THEN RETURN res||jsonb_build_object('replayed',true); END IF;
 IF p_site IS NOT NULL AND NOT EXISTS(SELECT 1 FROM c10_demo.sites WHERE id=p_site AND business_id=p_business AND tenant_id=t)
 THEN RAISE EXCEPTION 'intent_denied'; END IF;
 ss:=c10_demo.intent_check_interpretation_v1(p_interpretation);
 cap:=CASE WHEN jsonb_typeof(p_interpretation->'capability_key')='string' THEN p_interpretation->>'capability_key' END;
 st:=CASE ss WHEN 'SUPPORTED' THEN 'INTERPRETED' ELSE ss END;
 INSERT INTO c10_demo.owner_intents_v1(tenant_id,business_id,site_id,raw_text,locale,capability_key,status,params,interpretation,created_by)
 VALUES(t,p_business,p_site,btrim(p_text),p_interpretation->>'locale',cap,st,COALESCE(p_interpretation->'params','{}'::jsonb),
        p_interpretation,c10_demo.actor_uid()) RETURNING id INTO nid;
 IF ss IN('ENGINEERING_REQUIRED','UNSUPPORTED') THEN
  req:=p_interpretation->'unsupported'->'requirement';
  cat:=p_interpretation->'unsupported'->>'category';
  hid:=CASE WHEN jsonb_typeof(p_interpretation->'unsupported'->'a045_handler_id')='string' THEN p_interpretation->'unsupported'->>'a045_handler_id' END;
  IF hid IS NOT NULL AND NOT EXISTS(SELECT 1 FROM c10_demo.micro_engine_handlers_v1 WHERE handler_id=hid) THEN hid:=NULL; END IF;
  INSERT INTO c10_demo.engineering_requirements_v1(tenant_id,business_id,intent_id,status,category,a045_handler_id,requirement,created_by)
  VALUES(t,p_business,nid,CASE ss WHEN 'UNSUPPORTED' THEN 'NOT_ALLOWED_BY_POLICY' ELSE 'NEEDS_HANDLER_BUILD' END,cat,hid,req,c10_demo.actor_uid());
 END IF;
 PERFORM c10_demo.intent_event_v1(t,p_business,nid,cap,'intent_submitted',NULL,jsonb_build_object('status',st,'locale',p_interpretation->>'locale',
   'parser_version',p_interpretation->>'parser_version'),p_request);
 res:=jsonb_build_object('status','submitted','intent_id',nid,'intent_status',st,'version',1,'capability_key',cap,
   'executable',ss='SUPPORTED','engineering_required',ss IN('ENGINEERING_REQUIRED','UNSUPPORTED'),'applied',false);
 PERFORM c10_demo.intent_store_v1(t,p_request,pay,res);
 RETURN res;
END$fn$;

-- ---------------------------------------------------------------- revise (edit assumptions/params; version+1)
CREATE FUNCTION c10_demo.revise_owner_intent_v1(p_intent bigint,p_expected int,p_interpretation jsonb,p_request text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $fn$
DECLARE i c10_demo.owner_intents_v1%ROWTYPE; t bigint; pay jsonb; res jsonb; ss text; st text; cap text;
BEGIN
 PERFORM c10_demo.intent_req_v1(p_request);
 SELECT * INTO i FROM c10_demo.owner_intents_v1 WHERE id=p_intent;
 IF NOT FOUND THEN RAISE EXCEPTION 'intent_denied'; END IF;
 t:=c10_demo.intent_scope_v1(i.business_id,'manage');
 pay:=jsonb_build_object('op','revise','intent',p_intent,'expected',p_expected,'interp',p_interpretation);
 res:=c10_demo.intent_replay_v1(t,p_request,pay);
 IF res IS NOT NULL THEN RETURN res||jsonb_build_object('replayed',true); END IF;
 SELECT * INTO i FROM c10_demo.owner_intents_v1 WHERE id=p_intent FOR UPDATE;
 IF i.version<>p_expected THEN RAISE EXCEPTION 'intent_stale_version'; END IF;
 IF i.status NOT IN('INTERPRETED','NEEDS_CLARIFICATION','PREVIEWED','VALIDATED','APPROVED') THEN RAISE EXCEPTION 'intent_invalid_transition'; END IF;
 ss:=c10_demo.intent_check_interpretation_v1(p_interpretation);
 IF ss NOT IN('SUPPORTED','NEEDS_CLARIFICATION') THEN RAISE EXCEPTION 'intent_invalid_transition'; END IF;
 cap:=CASE WHEN jsonb_typeof(p_interpretation->'capability_key')='string' THEN p_interpretation->>'capability_key' END;
 IF i.capability_key IS NOT NULL AND cap IS DISTINCT FROM i.capability_key THEN RAISE EXCEPTION 'intent_invalid_transition'; END IF;
 st:=CASE ss WHEN 'SUPPORTED' THEN 'INTERPRETED' ELSE ss END;
 UPDATE c10_demo.owner_intents_v1 SET capability_key=cap,status=st,params=COALESCE(p_interpretation->'params','{}'::jsonb),
   interpretation=p_interpretation,locale=p_interpretation->>'locale',preview=NULL,preview_hash=NULL,basis_version=NULL,sample=NULL,
   version=i.version+1,updated_at=now() WHERE id=p_intent;
 PERFORM c10_demo.intent_event_v1(t,i.business_id,p_intent,cap,'intent_revised',jsonb_build_object('status',i.status,'params',i.params,'version',i.version),
   jsonb_build_object('status',st,'params',COALESCE(p_interpretation->'params','{}'::jsonb),'version',i.version+1),p_request);
 res:=jsonb_build_object('status','revised','intent_id',p_intent,'intent_status',st,'version',i.version+1,'applied',false);
 PERFORM c10_demo.intent_store_v1(t,p_request,pay,res);
 RETURN res;
END$fn$;

-- ---------------------------------------------------------------- SAFE PREVIEW (dry run; no setting/engine write)
CREATE FUNCTION c10_demo.preview_owner_intent_v1(p_intent bigint,p_expected int,p_sample jsonb,p_request text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $fn$
DECLARE i c10_demo.owner_intents_v1%ROWTYPE; t bigint; pay jsonb; res jsonb; pv jsonb; h text; c c10_demo.intent_capabilities_v1%ROWTYPE;
BEGIN
 PERFORM c10_demo.intent_req_v1(p_request);
 SELECT * INTO i FROM c10_demo.owner_intents_v1 WHERE id=p_intent;
 IF NOT FOUND THEN RAISE EXCEPTION 'intent_denied'; END IF;
 t:=c10_demo.intent_scope_v1(i.business_id,'manage');
 pay:=jsonb_build_object('op','preview','intent',p_intent,'expected',p_expected,'sample',p_sample);
 res:=c10_demo.intent_replay_v1(t,p_request,pay);
 IF res IS NOT NULL THEN RETURN res||jsonb_build_object('replayed',true); END IF;
 SELECT * INTO i FROM c10_demo.owner_intents_v1 WHERE id=p_intent FOR UPDATE;
 IF i.version<>p_expected THEN RAISE EXCEPTION 'intent_stale_version'; END IF;
 IF i.status NOT IN('INTERPRETED','PREVIEWED') THEN RAISE EXCEPTION 'intent_invalid_transition'; END IF;
 SELECT * INTO c FROM c10_demo.intent_capabilities_v1 WHERE capability_key=i.capability_key;
 UPDATE c10_demo.owner_intents_v1 SET sample=COALESCE(p_sample,c.sample_inputs) WHERE id=p_intent;
 pv:=c10_demo.intent_build_preview_v1(p_intent); -- raises invalid_input for bad sample
 h:=c10_demo.intent_preview_hash_v1(pv);
 UPDATE c10_demo.owner_intents_v1 SET status='PREVIEWED',preview=pv,preview_hash=h,basis_version=(pv->>'basis_version')::bigint,updated_at=now()
  WHERE id=p_intent;
 PERFORM c10_demo.intent_event_v1(t,i.business_id,p_intent,i.capability_key,'intent_previewed',jsonb_build_object('status',i.status),
   jsonb_build_object('status','PREVIEWED','preview_hash',h,'blocked',pv->'impact'->'blocked'),p_request);
 res:=jsonb_build_object('status','previewed','intent_id',p_intent,'intent_status','PREVIEWED','version',i.version,'preview_hash',h,
   'preview',pv,'applied',false,'writes_now',false);
 PERFORM c10_demo.intent_store_v1(t,p_request,pay,res);
 RETURN res;
END$fn$;

-- ---------------------------------------------------------------- validate (client acknowledges the exact preview)
CREATE FUNCTION c10_demo.validate_owner_intent_v1(p_intent bigint,p_expected int,p_preview_hash text,p_request text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $fn$
DECLARE i c10_demo.owner_intents_v1%ROWTYPE; t bigint; pay jsonb; res jsonb; pv jsonb;
BEGIN
 PERFORM c10_demo.intent_req_v1(p_request);
 SELECT * INTO i FROM c10_demo.owner_intents_v1 WHERE id=p_intent;
 IF NOT FOUND THEN RAISE EXCEPTION 'intent_denied'; END IF;
 t:=c10_demo.intent_scope_v1(i.business_id,'manage');
 pay:=jsonb_build_object('op','validate','intent',p_intent,'expected',p_expected,'hash',p_preview_hash);
 res:=c10_demo.intent_replay_v1(t,p_request,pay);
 IF res IS NOT NULL THEN RETURN res||jsonb_build_object('replayed',true); END IF;
 SELECT * INTO i FROM c10_demo.owner_intents_v1 WHERE id=p_intent FOR UPDATE;
 IF i.version<>p_expected THEN RAISE EXCEPTION 'intent_stale_version'; END IF;
 IF i.status<>'PREVIEWED' THEN RAISE EXCEPTION 'intent_invalid_transition'; END IF;
 IF p_preview_hash IS DISTINCT FROM i.preview_hash THEN RAISE EXCEPTION 'intent_preview_mismatch'; END IF;
 pv:=c10_demo.intent_build_preview_v1(p_intent);
 IF c10_demo.intent_preview_hash_v1(pv)<>i.preview_hash THEN RAISE EXCEPTION 'intent_stale_basis'; END IF;
 IF (pv->'impact'->>'blocked')::boolean THEN RAISE EXCEPTION 'intent_blocked'; END IF;
 UPDATE c10_demo.owner_intents_v1 SET status='VALIDATED',updated_at=now() WHERE id=p_intent;
 PERFORM c10_demo.intent_event_v1(t,i.business_id,p_intent,i.capability_key,'intent_validated',jsonb_build_object('status','PREVIEWED'),
   jsonb_build_object('status','VALIDATED','preview_hash',i.preview_hash),p_request);
 res:=jsonb_build_object('status','validated','intent_id',p_intent,'intent_status','VALIDATED','version',i.version,'applied',false);
 PERFORM c10_demo.intent_store_v1(t,p_request,pay,res);
 RETURN res;
END$fn$;

-- ---------------------------------------------------------------- approve (tenant Owner only)
CREATE FUNCTION c10_demo.approve_owner_intent_v1(p_intent bigint,p_expected int,p_reason text,p_request text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $fn$
DECLARE i c10_demo.owner_intents_v1%ROWTYPE; t bigint; pay jsonb; res jsonb; pv jsonb;
BEGIN
 PERFORM c10_demo.intent_req_v1(p_request); PERFORM c10_demo.intent_reason_v1(p_reason);
 SELECT * INTO i FROM c10_demo.owner_intents_v1 WHERE id=p_intent;
 IF NOT FOUND THEN RAISE EXCEPTION 'intent_denied'; END IF;
 t:=c10_demo.intent_scope_v1(i.business_id,'tenant');
 pay:=jsonb_build_object('op','approve','intent',p_intent,'expected',p_expected,'reason',btrim(p_reason));
 res:=c10_demo.intent_replay_v1(t,p_request,pay);
 IF res IS NOT NULL THEN RETURN res||jsonb_build_object('replayed',true); END IF;
 SELECT * INTO i FROM c10_demo.owner_intents_v1 WHERE id=p_intent FOR UPDATE;
 IF i.version<>p_expected THEN RAISE EXCEPTION 'intent_stale_version'; END IF;
 IF i.status<>'VALIDATED' THEN RAISE EXCEPTION 'intent_invalid_transition'; END IF;
 pv:=c10_demo.intent_build_preview_v1(p_intent);
 IF c10_demo.intent_preview_hash_v1(pv)<>i.preview_hash THEN RAISE EXCEPTION 'intent_stale_basis'; END IF;
 UPDATE c10_demo.owner_intents_v1 SET status='APPROVED',updated_at=now() WHERE id=p_intent;
 PERFORM c10_demo.intent_event_v1(t,i.business_id,p_intent,i.capability_key,'intent_approved',jsonb_build_object('status','VALIDATED'),
   jsonb_build_object('status','APPROVED','reason',btrim(p_reason)),p_request);
 res:=jsonb_build_object('status','approved','intent_id',p_intent,'intent_status','APPROVED','version',i.version,'applied',false);
 PERFORM c10_demo.intent_store_v1(t,p_request,pay,res);
 RETURN res;
END$fn$;

CREATE FUNCTION c10_demo.reject_owner_intent_v1(p_intent bigint,p_expected int,p_reason text,p_request text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $fn$
DECLARE i c10_demo.owner_intents_v1%ROWTYPE; t bigint; pay jsonb; res jsonb;
BEGIN
 PERFORM c10_demo.intent_req_v1(p_request); PERFORM c10_demo.intent_reason_v1(p_reason);
 SELECT * INTO i FROM c10_demo.owner_intents_v1 WHERE id=p_intent;
 IF NOT FOUND THEN RAISE EXCEPTION 'intent_denied'; END IF;
 t:=c10_demo.intent_scope_v1(i.business_id,'manage');
 pay:=jsonb_build_object('op','reject','intent',p_intent,'expected',p_expected,'reason',btrim(p_reason));
 res:=c10_demo.intent_replay_v1(t,p_request,pay);
 IF res IS NOT NULL THEN RETURN res||jsonb_build_object('replayed',true); END IF;
 SELECT * INTO i FROM c10_demo.owner_intents_v1 WHERE id=p_intent FOR UPDATE;
 IF i.version<>p_expected THEN RAISE EXCEPTION 'intent_stale_version'; END IF;
 IF i.status NOT IN('INTERPRETED','NEEDS_CLARIFICATION','PREVIEWED','VALIDATED','APPROVED') THEN RAISE EXCEPTION 'intent_invalid_transition'; END IF;
 UPDATE c10_demo.owner_intents_v1 SET status='REJECTED',capability_key=capability_key,updated_at=now() WHERE id=p_intent;
 PERFORM c10_demo.intent_event_v1(t,i.business_id,p_intent,i.capability_key,'intent_rejected',jsonb_build_object('status',i.status),
   jsonb_build_object('status','REJECTED','reason',btrim(p_reason)),p_request);
 res:=jsonb_build_object('status','rejected','intent_id',p_intent,'intent_status','REJECTED','version',i.version,'applied',false);
 PERFORM c10_demo.intent_store_v1(t,p_request,pay,res);
 RETURN res;
END$fn$;

-- ---------------------------------------------------------------- apply a setting version (publish + rollback share this)
CREATE FUNCTION c10_demo.intent_apply_setting_v1(p_tenant bigint,p_business bigint,p_cap text,p_params jsonb,p_intent bigint,
 p_rollback_of int,p_reason text,p_request text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $fn$
DECLARE c c10_demo.intent_capabilities_v1%ROWTYPE; cur c10_demo.intent_settings_v1%ROWTYPE; nv int; sid bigint; ekey text; e c10_demo.micro_engines_v1%ROWTYPE;
 d jsonb; r1 jsonb; r2 jsonb; eng_id bigint; eng_ver int; aexp bigint; rk text; before jsonb;
BEGIN
 SELECT * INTO c FROM c10_demo.intent_capabilities_v1 WHERE capability_key=p_cap;
 IF NOT FOUND OR NOT c.certified THEN RAISE EXCEPTION 'capability_not_certified'; END IF;
 IF NOT c10_demo.intent_params_valid_v1(p_cap,p_params) THEN RAISE EXCEPTION 'invalid_intent_params'; END IF;
 IF c.route='A045_ENGINE' THEN
  ekey:='a052_'||p_cap||'_b'||p_business;
  d:=c10_demo.intent_descriptor_v1(p_cap,p_params);
  rk:='a052'||md5(p_request);
  SELECT * INTO e FROM c10_demo.micro_engines_v1 WHERE tenant_id=p_tenant AND engine_key=ekey;
  r1:=c10_demo.save_engine_draft_v1(p_tenant,ekey,left('A052 '||(c.title->>'en')||' b'||p_business,80),c.a045_handler_id,d,
      COALESCE(e.current_version,0),rk||'s',p_reason);
  eng_id:=(r1->>'engine_id')::bigint; eng_ver:=(r1->>'version')::int;
  PERFORM c10_demo.validate_engine_version_v1(eng_id,eng_ver,rk||'v',p_reason);
  SELECT COALESCE((SELECT version FROM c10_demo.micro_engine_assignments_v1 WHERE engine_id=eng_id AND business_id=p_business),0) INTO aexp;
  PERFORM c10_demo.assign_engine_v1(eng_id,p_business,eng_ver,'PUBLISHED','{}'::jsonb,'both','central_only',aexp,rk||'a',p_reason);
 END IF;
 SELECT * INTO cur FROM c10_demo.intent_settings_v1 WHERE business_id=p_business AND setting_key=p_cap AND state='ACTIVE' FOR UPDATE;
 before:=CASE WHEN cur.id IS NULL THEN NULL ELSE jsonb_build_object('version',cur.version,'params',cur.params) END;
 IF cur.id IS NOT NULL THEN UPDATE c10_demo.intent_settings_v1 SET state='SUPERSEDED',superseded_at=now() WHERE id=cur.id; END IF;
 SELECT COALESCE(max(version),0)+1 INTO nv FROM c10_demo.intent_settings_v1 WHERE business_id=p_business AND setting_key=p_cap;
 INSERT INTO c10_demo.intent_settings_v1(tenant_id,business_id,setting_key,version,state,params,payload_hash,source_intent_id,rollback_of_version,
   engine_id,engine_version,created_by)
 VALUES(p_tenant,p_business,p_cap,nv,'ACTIVE',p_params,md5(p_params::text),p_intent,p_rollback_of,eng_id,eng_ver,c10_demo.actor_uid()) RETURNING id INTO sid;
 PERFORM c10_demo.intent_event_v1(p_tenant,p_business,p_intent,p_cap,CASE WHEN p_rollback_of IS NULL THEN 'setting_published' ELSE 'setting_rolled_back' END,
   before,jsonb_build_object('version',nv,'params',p_params,'rollback_of',p_rollback_of,'engine_id',eng_id,'engine_version',eng_ver,'reason',btrim(p_reason)),p_request);
 RETURN jsonb_build_object('setting_id',sid,'version',nv,'engine_id',eng_id,'engine_version',eng_ver);
END$fn$;

-- ---------------------------------------------------------------- publish (tenant Owner only; certified capability only)
CREATE FUNCTION c10_demo.publish_owner_intent_v1(p_intent bigint,p_expected int,p_request text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $fn$
DECLARE i c10_demo.owner_intents_v1%ROWTYPE; t bigint; pay jsonb; res jsonb; pv jsonb; ap jsonb;
BEGIN
 PERFORM c10_demo.intent_req_v1(p_request);
 SELECT * INTO i FROM c10_demo.owner_intents_v1 WHERE id=p_intent;
 IF NOT FOUND THEN RAISE EXCEPTION 'intent_denied'; END IF;
 t:=c10_demo.intent_scope_v1(i.business_id,'tenant');
 pay:=jsonb_build_object('op','publish','intent',p_intent,'expected',p_expected);
 res:=c10_demo.intent_replay_v1(t,p_request,pay);
 IF res IS NOT NULL THEN RETURN res||jsonb_build_object('replayed',true); END IF;
 SELECT * INTO i FROM c10_demo.owner_intents_v1 WHERE id=p_intent FOR UPDATE;
 IF i.version<>p_expected THEN RAISE EXCEPTION 'intent_stale_version'; END IF;
 IF i.status<>'APPROVED' THEN RAISE EXCEPTION 'intent_invalid_transition'; END IF;
 pv:=c10_demo.intent_build_preview_v1(p_intent);
 IF c10_demo.intent_preview_hash_v1(pv)<>i.preview_hash THEN RAISE EXCEPTION 'intent_stale_basis'; END IF;
 IF (pv->'impact'->>'blocked')::boolean THEN RAISE EXCEPTION 'intent_blocked'; END IF;
 ap:=c10_demo.intent_apply_setting_v1(t,i.business_id,i.capability_key,i.params,p_intent,NULL,'Owner approved intent '||p_intent,p_request);
 UPDATE c10_demo.owner_intents_v1 SET status='PUBLISHED',setting_id=(ap->>'setting_id')::bigint,updated_at=now() WHERE id=p_intent;
 PERFORM c10_demo.intent_event_v1(t,i.business_id,p_intent,i.capability_key,'intent_published',jsonb_build_object('status','APPROVED'),
   jsonb_build_object('status','PUBLISHED','setting_version',ap->'version'),p_request);
 res:=jsonb_build_object('status','published','intent_id',p_intent,'intent_status','PUBLISHED','version',i.version,
   'setting_version',(ap->>'version')::int,'setting_id',(ap->>'setting_id')::bigint,'engine_id',ap->'engine_id',
   'advisory_only',true,'operational_enforcement',false,'applied',true);
 PERFORM c10_demo.intent_store_v1(t,p_request,pay,res);
 RETURN res;
END$fn$;

-- ---------------------------------------------------------------- rollback to a previous setting version (new version, history kept)
CREATE FUNCTION c10_demo.rollback_intent_setting_v1(p_business bigint,p_key text,p_to_version int,p_expected_active int,p_reason text,p_request text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $fn$
DECLARE t bigint; pay jsonb; res jsonb; cur c10_demo.intent_settings_v1%ROWTYPE; tgt c10_demo.intent_settings_v1%ROWTYPE; ap jsonb;
BEGIN
 PERFORM c10_demo.intent_req_v1(p_request); PERFORM c10_demo.intent_reason_v1(p_reason);
 t:=c10_demo.intent_scope_v1(p_business,'tenant');
 pay:=jsonb_build_object('op','rollback','business',p_business,'key',p_key,'to',p_to_version,'expected',p_expected_active,'reason',btrim(p_reason));
 res:=c10_demo.intent_replay_v1(t,p_request,pay);
 IF res IS NOT NULL THEN RETURN res||jsonb_build_object('replayed',true); END IF;
 SELECT * INTO cur FROM c10_demo.intent_settings_v1 WHERE business_id=p_business AND setting_key=p_key AND state='ACTIVE' FOR UPDATE;
 IF NOT FOUND OR cur.version<>p_expected_active THEN RAISE EXCEPTION 'intent_stale_version'; END IF;
 SELECT * INTO tgt FROM c10_demo.intent_settings_v1 WHERE business_id=p_business AND setting_key=p_key AND version=p_to_version;
 IF NOT FOUND THEN RAISE EXCEPTION 'intent_version_not_found'; END IF;
 IF tgt.version=cur.version OR tgt.params=cur.params THEN RAISE EXCEPTION 'intent_invalid_transition'; END IF;
 ap:=c10_demo.intent_apply_setting_v1(t,p_business,p_key,tgt.params,NULL,p_to_version,p_reason,p_request);
 res:=jsonb_build_object('status','rolled_back','business_id',p_business,'setting_key',p_key,'setting_version',(ap->>'version')::int,
   'restored_from_version',p_to_version,'advisory_only',true,'applied',true);
 PERFORM c10_demo.intent_store_v1(t,p_request,pay,res);
 RETURN res;
END$fn$;

-- ---------------------------------------------------------------- reads
CREATE FUNCTION c10_demo.read_intent_businesses_v1() RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $fn$
BEGIN
 IF c10_demo.actor_uid() IS NULL THEN RAISE EXCEPTION 'intent_denied'; END IF;
 RETURN jsonb_build_object('server_authorized',true,'items',(SELECT COALESCE(jsonb_agg(jsonb_build_object(
  'business_id',b.id,'tenant_id',b.tenant_id,'name',COALESCE(cfg.display_name,b.slug),'template_code',b.template_code,
  'can_submit',c10_demo.can_manage(b.tenant_id,b.id),'can_publish',c10_demo.can_tenant(b.tenant_id)) ORDER BY b.id),'[]'::jsonb)
  FROM c10_demo.businesses b LEFT JOIN c10_demo.business_configuration_v1 cfg ON cfg.business_id=b.id
  WHERE c10_demo.can_see_business(b.tenant_id,b.id)));
END$fn$;

-- Context detection: business / site / user role / template / module / certified capability registry (A045 joined live).
CREATE FUNCTION c10_demo.read_intent_context_v1(p_business bigint) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $fn$
DECLARE t bigint; b c10_demo.businesses%ROWTYPE; tpl c10_demo.templates%ROWTYPE; mg boolean; tn boolean;
BEGIN
 IF c10_demo.actor_uid() IS NULL OR p_business IS NULL THEN RAISE EXCEPTION 'intent_denied'; END IF;
 SELECT * INTO b FROM c10_demo.businesses WHERE id=p_business;
 IF NOT FOUND OR NOT c10_demo.can_see_business(b.tenant_id,b.id) THEN RAISE EXCEPTION 'intent_denied'; END IF;
 t:=b.tenant_id; mg:=c10_demo.can_manage(t,p_business); tn:=c10_demo.can_tenant(t);
 SELECT * INTO tpl FROM c10_demo.templates WHERE code=b.template_code;
 RETURN jsonb_build_object('server_authorized',true,'operationally_certified',false,
  'tenant_id',t,'business',jsonb_build_object('business_id',b.id,'slug',b.slug,'status',b.status,'template_code',b.template_code,
     'template_source_status',tpl.source_status,'template_demo_allowed',tpl.demo_allowed),
  'actor',jsonb_build_object('is_tenant_owner',tn,'can_manage',mg,'can_submit',mg,'can_publish',tn,
     'role',CASE WHEN tn THEN 'tenant_owner' WHEN mg THEN 'business_owner' ELSE 'limited' END),
  'sites',(SELECT COALESCE(jsonb_agg(jsonb_build_object('site_id',s.id,'kind',s.kind,'label',s.label) ORDER BY s.id),'[]'::jsonb)
     FROM c10_demo.sites s WHERE s.business_id=b.id AND c10_demo.can_site(s.tenant_id,s.business_id,s.id,'stock.read')),
  'modules',(SELECT COALESCE(jsonb_agg(jsonb_build_object('module_code',m.module_code,'visibility',m.visibility,'operational_enabled',m.operational_enabled)
     ORDER BY m.module_code),'[]'::jsonb) FROM c10_demo.business_module_settings_v1 m WHERE m.business_id=b.id),
  'capabilities',(SELECT COALESCE(jsonb_agg(jsonb_build_object('capability_key',c.capability_key,'route',c.route,'module_code',c.module_code,
     'title',c.title,'certified',c.certified,'a045_handler_id',c.a045_handler_id,
     'a045_certified',COALESCE(h.certified,false),'a045_can_execute',COALESCE(h.can_execute,false),'sample_inputs',c.sample_inputs) ORDER BY c.capability_key),'[]'::jsonb)
     FROM c10_demo.intent_capabilities_v1 c LEFT JOIN c10_demo.micro_engine_handlers_v1 h ON h.handler_id=c.a045_handler_id),
  'a045_handlers',(SELECT COALESCE(jsonb_agg(jsonb_build_object('handler_id',handler_id,'kind',kind,'certified',certified,'can_execute',can_execute)
     ORDER BY handler_id),'[]'::jsonb) FROM c10_demo.micro_engine_handlers_v1),
  'active_settings',CASE WHEN mg THEN (SELECT COALESCE(jsonb_agg(jsonb_build_object('setting_key',s.setting_key,'version',s.version,'params',s.params,
     'engine_id',s.engine_id,'created_at',s.created_at) ORDER BY s.setting_key),'[]'::jsonb)
     FROM c10_demo.intent_settings_v1 s WHERE s.business_id=b.id AND s.state='ACTIVE') ELSE '[]'::jsonb END);
END$fn$;

CREATE FUNCTION c10_demo.read_owner_intents_v1(p_business bigint) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $fn$
DECLARE t bigint;
BEGIN
 t:=c10_demo.intent_scope_v1(p_business,'manage');
 RETURN jsonb_build_object('server_authorized',true,'business_id',p_business,
  'items',(SELECT COALESCE(jsonb_agg(jsonb_build_object('intent_id',i.id,'raw_text',i.raw_text,'locale',i.locale,'status',i.status,
    'capability_key',i.capability_key,'params',i.params,'interpretation',i.interpretation,'preview',i.preview,'preview_hash',i.preview_hash,
    'version',i.version,'site_id',i.site_id,'setting_id',i.setting_id,'created_at',i.created_at,
    'requirement',(SELECT to_jsonb(r)-'tenant_id'-'created_by' FROM c10_demo.engineering_requirements_v1 r WHERE r.intent_id=i.id)) ORDER BY i.id DESC),'[]'::jsonb)
    FROM (SELECT * FROM c10_demo.owner_intents_v1 WHERE business_id=p_business ORDER BY id DESC LIMIT 50) i));
END$fn$;

CREATE FUNCTION c10_demo.read_intent_history_v1(p_business bigint) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $fn$
DECLARE t bigint;
BEGIN
 t:=c10_demo.intent_scope_v1(p_business,'manage');
 RETURN jsonb_build_object('server_authorized',true,'business_id',p_business,
  'settings',(SELECT COALESCE(jsonb_agg(jsonb_build_object('setting_id',s.id,'setting_key',s.setting_key,'version',s.version,'state',s.state,
     'params',s.params,'source_intent_id',s.source_intent_id,'rollback_of_version',s.rollback_of_version,'engine_id',s.engine_id,
     'created_at',s.created_at) ORDER BY s.setting_key,s.version DESC),'[]'::jsonb) FROM c10_demo.intent_settings_v1 s WHERE s.business_id=p_business),
  'audit',(SELECT COALESCE(jsonb_agg(jsonb_build_object('audit_id',x.id,'intent_id',x.intent_id,'setting_key',x.setting_key,'event',x.event,
     'before',x.before_state,'after',x.after_state,'created_at',x.created_at) ORDER BY x.id DESC),'[]'::jsonb)
     FROM (SELECT * FROM c10_demo.owner_intent_events_v1 WHERE business_id=p_business ORDER BY id DESC LIMIT 100) x));
END$fn$;

CREATE FUNCTION c10_demo.read_engineering_requirements_v1(p_business bigint) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $fn$
DECLARE t bigint;
BEGIN
 t:=c10_demo.intent_scope_v1(p_business,'manage');
 RETURN jsonb_build_object('server_authorized',true,'business_id',p_business,
  'items',(SELECT COALESCE(jsonb_agg(jsonb_build_object('requirement_id',r.id,'intent_id',r.intent_id,'status',r.status,'category',r.category,
    'a045_handler_id',r.a045_handler_id,'a045_certified',COALESCE(h.certified,false),'requirement',r.requirement,'created_at',r.created_at) ORDER BY r.id DESC),'[]'::jsonb)
    FROM c10_demo.engineering_requirements_v1 r LEFT JOIN c10_demo.micro_engine_handlers_v1 h ON h.handler_id=r.a045_handler_id
    WHERE r.business_id=p_business));
END$fn$;

-- Contextual guidance for a real control, with the caller's effective permission and (for managers) the live value.
CREATE FUNCTION c10_demo.read_guidance_v1(p_business bigint,p_control_key text) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $fn$
DECLARE t bigint; g c10_demo.intent_guidance_v1%ROWTYPE; mg boolean; tn boolean; cur jsonb;
BEGIN
 t:=c10_demo.intent_scope_v1(p_business,'see');
 SELECT * INTO g FROM c10_demo.intent_guidance_v1 WHERE control_key=p_control_key;
 IF NOT FOUND THEN RAISE EXCEPTION 'guidance_not_found'; END IF;
 mg:=c10_demo.can_manage(t,p_business); tn:=c10_demo.can_tenant(t);
 IF mg AND g.capability_key IS NOT NULL THEN
  SELECT jsonb_build_object('version',s.version,'params',s.params) INTO cur FROM c10_demo.intent_settings_v1 s
   WHERE s.business_id=p_business AND s.setting_key=g.capability_key AND s.state='ACTIVE';
 END IF;
 RETURN jsonb_build_object('server_authorized',true,'control_key',g.control_key,'module_code',g.module_code,'capability_key',g.capability_key,
  'content',g.content,'current_setting',cur,
  'effective_permission',jsonb_build_object('can_view',true,'can_submit',mg,'can_approve_publish',tn,
    'role',CASE WHEN tn THEN 'tenant_owner' WHEN mg THEN 'business_owner' ELSE 'limited' END));
END$fn$;
CREATE FUNCTION c10_demo.read_guidance_index_v1(p_business bigint) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $fn$
BEGIN
 PERFORM c10_demo.intent_scope_v1(p_business,'see');
 RETURN jsonb_build_object('server_authorized',true,'items',(SELECT COALESCE(jsonb_agg(jsonb_build_object('control_key',control_key,
  'module_code',module_code,'capability_key',capability_key,'title',content->'title') ORDER BY control_key),'[]'::jsonb) FROM c10_demo.intent_guidance_v1));
END$fn$;

-- ---------------------------------------------------------------- grants: helpers private, RPC to signed users only
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA c10_demo FROM PUBLIC;
DO $g$ DECLARE r record; BEGIN
 FOR r IN SELECT p.oid::regprocedure AS sig FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='c10_demo' AND p.proname ~ '^(submit_owner_intent|revise_owner_intent|preview_owner_intent|validate_owner_intent|approve_owner_intent|reject_owner_intent|publish_owner_intent|rollback_intent_setting|read_intent_businesses|read_intent_context|read_owner_intents|read_intent_history|read_engineering_requirements|read_guidance|read_guidance_index)_v1$'
 LOOP
  EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC,anon',r.sig);
  EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated',r.sig);
 END LOOP;
END $g$;
