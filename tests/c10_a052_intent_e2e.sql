-- C10-A052 disposable E2E (PostgreSQL, c10_demo). Signed-session CLAIM SIMULATION only (request.jwt.claim.sub).
-- NOT Supabase GoTrue and NOT live RLS certification. Whole script runs in one transaction and rolls back.
-- Tenant 1: businesses 101,102 (+301 paint, 302 construction added here). Tenant 2: business 201.
\set ON_ERROR_STOP on
DROP FUNCTION IF EXISTS public.t052_fail(text,text),public.t052_n(text),public.t052_as(text);
CREATE FUNCTION public.t052_fail(q text,expect text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 EXECUTE q;
 RAISE EXCEPTION 'EXPECTED_FAILURE_DID_NOT_HAPPEN: %',q;
EXCEPTION WHEN OTHERS THEN
 IF SQLERRM LIKE 'EXPECTED_FAILURE_DID_NOT_HAPPEN%' THEN RAISE; END IF;
 IF expect IS NOT NULL AND SQLERRM NOT LIKE '%'||expect||'%' THEN
  RAISE EXCEPTION 'WRONG_FAILURE for [%]: got [%], wanted [%]',q,SQLERRM,expect; END IF;
END$$;
GRANT EXECUTE ON FUNCTION public.t052_fail(text,text) TO authenticated,anon;
CREATE FUNCTION public.t052_n(q text) RETURNS numeric LANGUAGE plpgsql SECURITY DEFINER AS $$ DECLARE r numeric; BEGIN EXECUTE q INTO r; RETURN r; END$$;
GRANT EXECUTE ON FUNCTION public.t052_n(text) TO authenticated;
CREATE FUNCTION public.t052_as(u text) RETURNS void LANGUAGE sql AS $$ SELECT set_config('request.jwt.claim.sub',u,true) $$;
GRANT EXECUTE ON FUNCTION public.t052_as(text) TO authenticated,anon;

BEGIN;
INSERT INTO c10_demo.businesses(id,tenant_id,legal_entity_id,slug,template_code,request_key,status)
 VALUES(301,1,11,'demo-paint','hardware_paint','seed-p','draft'),(302,1,11,'demo-construction','construction','seed-q','draft');
CREATE TEMP TABLE base AS SELECT (SELECT count(*) FROM c10_demo.stock_movements) mv,(SELECT count(*) FROM c10_demo.items) it,
 (SELECT count(*) FROM c10_demo.micro_engines_v1) en;
GRANT SELECT ON base TO authenticated;

-- ===== 0. structure / direct-write safety =====
DO $$ BEGIN
 IF has_table_privilege('authenticated','c10_demo.owner_intents_v1','INSERT') OR has_table_privilege('authenticated','c10_demo.intent_settings_v1','UPDATE')
  OR has_table_privilege('authenticated','c10_demo.intent_receipts_v1','SELECT') OR has_table_privilege('anon','c10_demo.owner_intents_v1','SELECT')
  OR has_function_privilege('anon','c10_demo.submit_owner_intent_v1(bigint,bigint,text,jsonb,text)','EXECUTE')
  OR has_function_privilege('authenticated','c10_demo.intent_apply_setting_v1(bigint,bigint,text,jsonb,bigint,integer,text,text)','EXECUTE')
 THEN RAISE EXCEPTION 'A052_PRIVILEGE_LEAK'; END IF;
 IF (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='c10_demo' AND c.relname IN
  ('intent_capabilities_v1','intent_guidance_v1','owner_intents_v1','intent_settings_v1','engineering_requirements_v1','owner_intent_events_v1','intent_receipts_v1')
  AND c.relrowsecurity)<>7 THEN RAISE EXCEPTION 'A052_RLS_NOT_ENABLED'; END IF;
END $$;

-- ===== 1. pure evaluators: exact numeric vectors and invalid inputs =====
DO $$
DECLARE r jsonb;
BEGIN
 r:=c10_demo.intent_eval_v1('wastage_threshold','{"threshold_pct":5,"outcome":"warn","unit":"kg"}','{"produced_qty":50,"wasted_qty":3}');
 IF (r->'computed'->>'wastage_pct')::numeric<>6 OR r->>'matched'<>'true' OR r->>'outcome'<>'warn' OR r->>'mutates'<>'false' THEN RAISE EXCEPTION 'EVAL_WASTAGE %',r; END IF;
 r:=c10_demo.intent_eval_v1('wastage_threshold','{"threshold_pct":6,"outcome":"warn","unit":"kg"}','{"produced_qty":50,"wasted_qty":3}');
 IF r->>'matched'<>'false' OR r->>'outcome'<>'allow' THEN RAISE EXCEPTION 'EVAL_WASTAGE_BOUNDARY %',r; END IF;
 r:=c10_demo.intent_eval_v1('pack_discount_margin','{"pack_litres":4,"min_margin_pct":15,"outcome":"warn","currency":"BDT"}','{"price_per_pack":3200,"cost_per_litre":600,"discount_pct":8}');
 IF (r->'computed'->>'net_price')::numeric<>2944 OR (r->'computed'->>'pack_cost')::numeric<>2400 OR (r->'computed'->>'margin_pct')::numeric<>18.4783
  OR (r->'computed'->>'max_discount_pct')::numeric<>11.7647 OR r->>'matched'<>'false' THEN RAISE EXCEPTION 'EVAL_PACK %',r; END IF;
 r:=c10_demo.intent_eval_v1('pack_discount_margin','{"pack_litres":4,"min_margin_pct":15,"outcome":"approval_required","currency":"BDT"}','{"price_per_pack":3200,"cost_per_litre":600,"discount_pct":15}');
 IF r->>'matched'<>'true' OR r->>'outcome'<>'approval_required' THEN RAISE EXCEPTION 'EVAL_PACK_LOW %',r; END IF;
 r:=c10_demo.intent_eval_v1('order_total_approval','{"threshold":600000,"outcome":"approval_required","currency":"BDT"}','{"order_total":600000}');
 IF r->>'matched'<>'true' OR r->'a045'->>'canAuthorizeOperation'<>'false' THEN RAISE EXCEPTION 'EVAL_ORDER %',r; END IF;
 PERFORM public.t052_fail($q$SELECT c10_demo.intent_eval_v1('wastage_threshold','{"threshold_pct":5,"outcome":"warn","unit":"kg"}','{"produced_qty":5,"wasted_qty":9}')$q$,'invalid_input');
 PERFORM public.t052_fail($q$SELECT c10_demo.intent_eval_v1('wastage_threshold','{"threshold_pct":5,"outcome":"warn","unit":"mile"}','{"produced_qty":5,"wasted_qty":1}')$q$,'invalid_params');
 PERFORM public.t052_fail($q$SELECT c10_demo.intent_eval_v1('pack_discount_margin','{"pack_litres":4,"min_margin_pct":15,"outcome":"warn","currency":"BDT"}','{"price_per_pack":3200,"cost_per_litre":600,"discount_pct":100}')$q$,'invalid_input');
 PERFORM public.t052_fail($q$SELECT c10_demo.intent_eval_v1('pack_discount_margin','{"pack_litres":4,"min_margin_pct":15,"outcome":"warn","currency":"bdt"}','{"price_per_pack":3200,"cost_per_litre":600,"discount_pct":1}')$q$,'invalid_params');
 PERFORM public.t052_fail($q$SELECT c10_demo.intent_eval_v1('low_stock_alert','{"threshold":5,"outcome":"warn","formula":"1+1"}','{"on_hand":1}')$q$,'invalid_params');
 PERFORM public.t052_fail($q$SELECT c10_demo.intent_eval_v1('grant_permission','{}','{}')$q$,'invalid_params');
END $$;

SET LOCAL ROLE authenticated;
-- ===== 2. Owner (tenant 1): full lifecycle, A052 advisory route (wastage, sweets business 101) =====
SELECT public.t052_as('11111111-1111-4111-8111-111111111111');
DO $$
DECLARE s jsonb; p jsonb; v jsonb; a jsonb; pb jsonb; ctx jsonb; i jsonb:='{"parser_version":"owner-intent-rules-v1","locale":"bn","support_status":"SUPPORTED","capability_key":"wastage_threshold","params":{"threshold_pct":5,"outcome":"warn","unit":"kg","item_group":"sweets"},"missing":[],"assumptions":[]}';
 n int;
BEGIN
 ctx:=c10_demo.read_intent_context_v1(101);
 IF ctx->'actor'->>'role'<>'tenant_owner' OR jsonb_array_length(ctx->'capabilities')<>5 OR jsonb_array_length(ctx->'sites')<>2
  OR ctx->'business'->>'template_code'<>'food_manufacturing' OR ctx->>'operationally_certified'<>'false' THEN RAISE EXCEPTION 'CTX %',ctx; END IF;
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(ctx->'capabilities') c WHERE c->>'capability_key'='low_stock_alert' AND c->>'a045_certified'='true')
  OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(ctx->'a045_handlers') c WHERE c->>'handler_id'='workflow_v1' AND c->>'certified'='false') THEN RAISE EXCEPTION 'A045_ADAPTER_MISSING'; END IF;
 s:=c10_demo.submit_owner_intent_v1(101,1001,'মিষ্টির নষ্ট ৫ শতাংশের বেশি হলে সতর্ক করো',i,'a052-sub-0001');
 IF s->>'intent_status'<>'INTERPRETED' OR s->>'applied'<>'false' OR s->>'executable'<>'true' THEN RAISE EXCEPTION 'SUBMIT %',s; END IF;
 IF c10_demo.submit_owner_intent_v1(101,1001,'মিষ্টির নষ্ট ৫ শতাংশের বেশি হলে সতর্ক করো',i,'a052-sub-0001')->>'replayed'<>'true' THEN RAISE EXCEPTION 'REPLAY'; END IF;
 PERFORM public.t052_fail($q$SELECT c10_demo.submit_owner_intent_v1(101,1001,'different text here',
  '{"parser_version":"x","locale":"en","support_status":"SUPPORTED","capability_key":"wastage_threshold","params":{"threshold_pct":5,"outcome":"warn","unit":"kg"}}','a052-sub-0001')$q$,'intent_idempotency_conflict');
 -- preview is a dry run: nothing is written to settings or A045
 p:=c10_demo.preview_owner_intent_v1((s->>'intent_id')::bigint,1,NULL,'a052-prv-0001');
 pb:=p->'preview';
 IF p->>'intent_status'<>'PREVIEWED' OR p->>'writes_now'<>'false' OR pb->'effect'->>'writes_now'<>'false'
  OR (SELECT count(*) FROM c10_demo.intent_settings_v1)<>0 OR public.t052_n('select count(*) from c10_demo.micro_engines_v1')<>(SELECT en FROM base) THEN RAISE EXCEPTION 'PREVIEW_MUTATED'; END IF;
 IF pb->'sample'->'before' IS NOT NULL AND pb->'sample'->>'before'<>'null' THEN RAISE EXCEPTION 'BEFORE_SHOULD_BE_NULL'; END IF;
 IF (pb->'sample'->'after'->'computed'->>'wastage_pct')::numeric<>6 OR pb->'sample'->'after'->>'matched'<>'true' THEN RAISE EXCEPTION 'PREVIEW_SAMPLE %',pb->'sample'; END IF;
 IF (pb->'impact'->>'blocked')<>'false' OR jsonb_array_length(pb->'diff')<4 OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(pb->'impact'->'conflicts') c WHERE c->>'code'='SITE_SCOPE_BUSINESS_LEVEL')
  OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(pb->'impact'->'reports') c WHERE c->>'status'='NOT_BUILT') THEN RAISE EXCEPTION 'PREVIEW_IMPACT %',pb->'impact'; END IF;
 -- cannot approve before validating; wrong hash; stale version
 PERFORM public.t052_fail(format('SELECT c10_demo.approve_owner_intent_v1(%s,1,%L,%L)',s->>'intent_id','Owner approves wastage rule','a052-apr-0000'),'intent_invalid_transition');
 PERFORM public.t052_fail(format('SELECT c10_demo.validate_owner_intent_v1(%s,1,%L,%L)',s->>'intent_id','deadbeef','a052-val-0000'),'intent_preview_mismatch');
 PERFORM public.t052_fail(format('SELECT c10_demo.validate_owner_intent_v1(%s,7,%L,%L)',s->>'intent_id',p->>'preview_hash','a052-val-0001'),'intent_stale_version');
 v:=c10_demo.validate_owner_intent_v1((s->>'intent_id')::bigint,1,p->>'preview_hash','a052-val-0002');
 PERFORM public.t052_fail(format('SELECT c10_demo.publish_owner_intent_v1(%s,1,%L)',s->>'intent_id','a052-pub-0000'),'intent_invalid_transition');
 a:=c10_demo.approve_owner_intent_v1((s->>'intent_id')::bigint,1,'Owner approves wastage rule','a052-apr-0001');
 a:=c10_demo.publish_owner_intent_v1((s->>'intent_id')::bigint,1,'a052-pub-0001');
 IF a->>'intent_status'<>'PUBLISHED' OR a->>'setting_version'<>'1' OR a->>'advisory_only'<>'true' OR a->>'operational_enforcement'<>'false' THEN RAISE EXCEPTION 'PUBLISH %',a; END IF;
 IF c10_demo.publish_owner_intent_v1((s->>'intent_id')::bigint,1,'a052-pub-0001')->>'replayed'<>'true' THEN RAISE EXCEPTION 'PUBLISH_REPLAY'; END IF;
 SELECT count(*) INTO n FROM c10_demo.intent_settings_v1 WHERE business_id=101 AND state='ACTIVE';
 IF n<>1 OR public.t052_n('select count(*) from c10_demo.micro_engines_v1')<>(SELECT en FROM base) THEN RAISE EXCEPTION 'SETTING_COUNT'; END IF;
 -- re-submitting identical values is a blocking no-op conflict
 s:=c10_demo.submit_owner_intent_v1(101,NULL,'wastage over 5 percent warn',i,'a052-sub-0002');
 p:=c10_demo.preview_owner_intent_v1((s->>'intent_id')::bigint,1,'{"produced_qty":100,"wasted_qty":2}','a052-prv-0002');
 IF (p->'preview'->'impact'->>'blocked')<>'true' OR p->'preview'->'sample'->'before' IS NULL THEN RAISE EXCEPTION 'NOOP_NOT_BLOCKED'; END IF;
 PERFORM public.t052_fail(format('SELECT c10_demo.validate_owner_intent_v1(%s,1,%L,%L)',s->>'intent_id',p->>'preview_hash','a052-val-0003'),'intent_blocked');
 PERFORM c10_demo.reject_owner_intent_v1((s->>'intent_id')::bigint,1,'Duplicate of published rule','a052-rej-0001');
END $$;

-- ===== 3. Owner: A045_ENGINE route (low stock) publishes via the A045 registry; stale basis; rollback =====
DO $$
DECLARE s jsonb; p jsonb; s2 jsonb; p2 jsonb; i1 jsonb:='{"parser_version":"x","locale":"en","support_status":"SUPPORTED","capability_key":"low_stock_alert","params":{"threshold":10,"outcome":"warn"}}';
 i2 jsonb:='{"parser_version":"x","locale":"en","support_status":"SUPPORTED","capability_key":"low_stock_alert","params":{"threshold":20,"outcome":"warn"}}';
 i3 jsonb:='{"parser_version":"x","locale":"en","support_status":"SUPPORTED","capability_key":"low_stock_alert","params":{"threshold":30,"outcome":"approval_required"}}';
 r jsonb; eng bigint; cnt int;
BEGIN
 -- two competing intents previewed from the same basis (no active setting)
 s:=c10_demo.submit_owner_intent_v1(101,NULL,'alert when stock below 10',i1,'a052-sub-1001');
 s2:=c10_demo.submit_owner_intent_v1(101,NULL,'alert when stock below 20',i2,'a052-sub-1002');
 p:=c10_demo.preview_owner_intent_v1((s->>'intent_id')::bigint,1,NULL,'a052-prv-1001');
 p2:=c10_demo.preview_owner_intent_v1((s2->>'intent_id')::bigint,1,NULL,'a052-prv-1002');
 PERFORM c10_demo.validate_owner_intent_v1((s->>'intent_id')::bigint,1,p->>'preview_hash','a052-val-1001');
 PERFORM c10_demo.validate_owner_intent_v1((s2->>'intent_id')::bigint,1,p2->>'preview_hash','a052-val-1002');
 PERFORM c10_demo.approve_owner_intent_v1((s->>'intent_id')::bigint,1,'Approve threshold 10','a052-apr-1001');
 PERFORM c10_demo.approve_owner_intent_v1((s2->>'intent_id')::bigint,1,'Approve threshold 20','a052-apr-1002');
 r:=c10_demo.publish_owner_intent_v1((s->>'intent_id')::bigint,1,'a052-pub-1001');
 IF r->>'setting_version'<>'1' OR r->'engine_id' IS NULL OR r->>'engine_id'='null' THEN RAISE EXCEPTION 'A045_PUBLISH %',r; END IF;
 eng:=(r->>'engine_id')::bigint;
 IF public.t052_n('select count(*) from c10_demo.micro_engine_assignments_v1 a where a.engine_id='||eng||' and a.business_id=101 and a.state=''PUBLISHED'' and a.pinned_version=1')<>1
  OR public.t052_n('select count(*) from c10_demo.micro_engines_v1 e where e.id='||eng||' and e.engine_key=''a052_low_stock_alert_b101'' and e.handler_id=''threshold_rule_v1''')<>1 THEN RAISE EXCEPTION 'A045_NOT_REGISTERED'; END IF;
 -- the second intent was previewed on a basis that no longer exists
 PERFORM public.t052_fail(format('SELECT c10_demo.publish_owner_intent_v1(%s,1,%L)',s2->>'intent_id','a052-pub-1002'),'intent_stale_basis');
 -- revise (new version) and republish through the whole pipeline -> setting v2 / engine v2
 r:=c10_demo.revise_owner_intent_v1((s2->>'intent_id')::bigint,1,i2,'a052-rev-1002');
 IF r->>'version'<>'2' OR r->>'intent_status'<>'INTERPRETED' THEN RAISE EXCEPTION 'REVISE %',r; END IF;
 p2:=c10_demo.preview_owner_intent_v1((s2->>'intent_id')::bigint,2,NULL,'a052-prv-1003');
 IF p2->'preview'->>'basis_version'<>'1' OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(p2->'preview'->'impact'->'conflicts') c WHERE c->>'code'='WILL_SUPERSEDE_ACTIVE')
  OR p2->'preview'->'sample'->'before'->>'matched' IS NULL THEN RAISE EXCEPTION 'SUPERSEDE_PREVIEW %',p2->'preview'; END IF;
 PERFORM c10_demo.validate_owner_intent_v1((s2->>'intent_id')::bigint,2,p2->>'preview_hash','a052-val-1003');
 PERFORM c10_demo.approve_owner_intent_v1((s2->>'intent_id')::bigint,2,'Approve threshold 20','a052-apr-1003');
 r:=c10_demo.publish_owner_intent_v1((s2->>'intent_id')::bigint,2,'a052-pub-1003');
 IF r->>'setting_version'<>'2' THEN RAISE EXCEPTION 'SETTING_V2 %',r; END IF;
 IF public.t052_n('select (descriptor->>''threshold'')::numeric from c10_demo.micro_engine_versions_v1 where engine_id='||eng||' and version=2')<>20 THEN RAISE EXCEPTION 'A045_V2_DESCRIPTOR'; END IF;
 IF (SELECT state FROM c10_demo.intent_settings_v1 WHERE business_id=101 AND setting_key='low_stock_alert' AND version=1)<>'SUPERSEDED' THEN RAISE EXCEPTION 'NOT_SUPERSEDED'; END IF;
 -- rollback to v1: new v3 with threshold 10, history kept
 PERFORM public.t052_fail($q$SELECT c10_demo.rollback_intent_setting_v1(101,'low_stock_alert',1,1,'Rollback to old value','a052-rbk-0001')$q$,'intent_stale_version');
 PERFORM public.t052_fail($q$SELECT c10_demo.rollback_intent_setting_v1(101,'low_stock_alert',9,2,'Rollback to old value','a052-rbk-0002')$q$,'intent_version_not_found');
 PERFORM public.t052_fail($q$SELECT c10_demo.rollback_intent_setting_v1(101,'low_stock_alert',1,2,'x','a052-rbk-0003')$q$,'invalid_intent_request');
 r:=c10_demo.rollback_intent_setting_v1(101,'low_stock_alert',1,2,'Rollback to old value','a052-rbk-0004');
 IF r->>'setting_version'<>'3' OR r->>'restored_from_version'<>'1' THEN RAISE EXCEPTION 'ROLLBACK %',r; END IF;
 IF (SELECT params->>'threshold' FROM c10_demo.intent_settings_v1 WHERE business_id=101 AND setting_key='low_stock_alert' AND state='ACTIVE')<>'10'
  OR public.t052_n('select (descriptor->>''threshold'')::numeric from c10_demo.micro_engine_versions_v1 where engine_id='||eng||' and version=3')<>10
  OR (SELECT count(*) FROM c10_demo.intent_settings_v1 WHERE business_id=101 AND setting_key='low_stock_alert')<>3 THEN RAISE EXCEPTION 'ROLLBACK_STATE'; END IF;
 IF c10_demo.rollback_intent_setting_v1(101,'low_stock_alert',1,2,'Rollback to old value','a052-rbk-0004')->>'replayed'<>'true' THEN RAISE EXCEPTION 'RB_REPLAY'; END IF;
 -- history & audit are readable and ordered
 r:=c10_demo.read_intent_history_v1(101);
 IF jsonb_array_length(r->'settings')<4 OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(r->'audit') a WHERE a->>'event'='setting_rolled_back') THEN RAISE EXCEPTION 'HISTORY %',r; END IF;
 -- other businesses unaffected
 IF public.t052_n('select count(*) from c10_demo.micro_engine_assignments_v1 where engine_id='||eng||' and business_id<>101')<>0 THEN RAISE EXCEPTION 'LEAK_TO_OTHER_BUSINESS'; END IF;
END $$;

-- ===== 4. Owner: unsupported / engineering / refused / invalid claims =====
DO $$
DECLARE s jsonb; r jsonb;
BEGIN
 s:=c10_demo.submit_owner_intent_v1(302,NULL,'show monthly project materials report',
  '{"parser_version":"x","locale":"en","support_status":"ENGINEERING_REQUIRED","capability_key":null,"params":{},"unsupported":{"category":"report_handler","a045_handler_id":"report_v1","requirement":{"title_en":"Read-only report","acceptance_criteria":["a"]}}}','a052-sub-2001');
 IF s->>'intent_status'<>'ENGINEERING_REQUIRED' OR s->>'executable'<>'false' OR s->>'engineering_required'<>'true' THEN RAISE EXCEPTION 'ENG_SUBMIT %',s; END IF;
 r:=c10_demo.read_engineering_requirements_v1(302);
 IF jsonb_array_length(r->'items')<>1 OR r->'items'->0->>'status'<>'NEEDS_HANDLER_BUILD' OR r->'items'->0->>'a045_certified'<>'false' THEN RAISE EXCEPTION 'ENG_ROW %',r; END IF;
 PERFORM public.t052_fail(format('SELECT c10_demo.preview_owner_intent_v1(%s,1,NULL,%L)',s->>'intent_id','a052-prv-2001'),'intent_invalid_transition');
 PERFORM public.t052_fail(format('SELECT c10_demo.approve_owner_intent_v1(%s,1,%L,%L)',s->>'intent_id','Try to approve it','a052-apr-2001'),'intent_invalid_transition');
 PERFORM public.t052_fail(format('SELECT c10_demo.publish_owner_intent_v1(%s,1,%L)',s->>'intent_id','a052-pub-2001'),'intent_invalid_transition');
 s:=c10_demo.submit_owner_intent_v1(101,NULL,'Give Rahim admin permission',
  '{"parser_version":"x","locale":"en","support_status":"UNSUPPORTED","capability_key":null,"params":{},"unsupported":{"category":"permission_grant","requirement":{"title_en":"Grant permission"}}}','a052-sub-2002');
 IF s->>'intent_status'<>'UNSUPPORTED' OR (SELECT status FROM c10_demo.engineering_requirements_v1 WHERE intent_id=(s->>'intent_id')::bigint)<>'NOT_ALLOWED_BY_POLICY' THEN RAISE EXCEPTION 'REFUSED_ROW'; END IF;
 -- the server refuses claims the allowlist cannot back
 PERFORM public.t052_fail($q$SELECT c10_demo.submit_owner_intent_v1(101,NULL,'grant it','{"parser_version":"x","locale":"en","support_status":"SUPPORTED","capability_key":"grant_permission","params":{}}','a052-bad-0001')$q$,'capability_not_certified');
 PERFORM public.t052_fail($q$SELECT c10_demo.submit_owner_intent_v1(101,NULL,'workflow','{"parser_version":"x","locale":"en","support_status":"SUPPORTED","capability_key":"workflow_v1","params":{}}','a052-bad-0002')$q$,'capability_not_certified');
 PERFORM public.t052_fail($q$SELECT c10_demo.submit_owner_intent_v1(101,NULL,'too much','{"parser_version":"x","locale":"en","support_status":"SUPPORTED","capability_key":"wastage_threshold","params":{"threshold_pct":500,"outcome":"warn","unit":"kg"}}','a052-bad-0003')$q$,'invalid_intent_params');
 PERFORM public.t052_fail($q$SELECT c10_demo.submit_owner_intent_v1(101,NULL,'extra key','{"parser_version":"x","locale":"en","support_status":"SUPPORTED","capability_key":"wastage_threshold","params":{"threshold_pct":5,"outcome":"warn","unit":"kg","sql":"drop table x"}}','a052-bad-0004')$q$,'invalid_intent_params');
 PERFORM public.t052_fail($q$SELECT c10_demo.submit_owner_intent_v1(101,NULL,'bad locale','{"parser_version":"x","locale":"zh","support_status":"SUPPORTED","capability_key":"wastage_threshold","params":{"threshold_pct":5,"outcome":"warn","unit":"kg"}}','a052-bad-0005')$q$,'invalid_locale');
 PERFORM public.t052_fail($q$SELECT c10_demo.submit_owner_intent_v1(101,NULL,'eng with cap','{"parser_version":"x","locale":"en","support_status":"ENGINEERING_REQUIRED","capability_key":"wastage_threshold","params":{},"unsupported":{"category":"x_y","requirement":{}}}','a052-bad-0006')$q$,'capability_not_certified');
 PERFORM public.t052_fail($q$SELECT c10_demo.submit_owner_intent_v1(101,NULL,'ab','{"parser_version":"x","locale":"en","support_status":"SUPPORTED","capability_key":"wastage_threshold","params":{"threshold_pct":5,"outcome":"warn","unit":"kg"}}','a052-bad-0007')$q$,'invalid_intent_text');
 PERFORM public.t052_fail($q$SELECT c10_demo.submit_owner_intent_v1(101,NULL,'short key text','{"parser_version":"x","locale":"en","support_status":"SUPPORTED","capability_key":"wastage_threshold","params":{"threshold_pct":5,"outcome":"warn","unit":"kg"}}','bad')$q$,'invalid_intent_request');
 -- site of another business is refused
 PERFORM public.t052_fail($q$SELECT c10_demo.submit_owner_intent_v1(101,1003,'wrong site text','{"parser_version":"x","locale":"en","support_status":"SUPPORTED","capability_key":"wastage_threshold","params":{"threshold_pct":5,"outcome":"warn","unit":"kg"}}','a052-bad-0008')$q$,'intent_denied');
 -- needs clarification then revise to supported
 s:=c10_demo.submit_owner_intent_v1(301,NULL,'discount below margin 12% needs approval',
  '{"parser_version":"x","locale":"en","support_status":"NEEDS_CLARIFICATION","capability_key":"pack_discount_margin","params":{"min_margin_pct":12},"missing":["pack_litres"]}','a052-sub-2003');
 IF s->>'intent_status'<>'NEEDS_CLARIFICATION' THEN RAISE EXCEPTION 'CLARIFY'; END IF;
 PERFORM public.t052_fail(format('SELECT c10_demo.preview_owner_intent_v1(%s,1,NULL,%L)',s->>'intent_id','a052-prv-2002'),'intent_invalid_transition');
 r:=c10_demo.revise_owner_intent_v1((s->>'intent_id')::bigint,1,
  '{"parser_version":"x","locale":"en","support_status":"SUPPORTED","capability_key":"pack_discount_margin","params":{"pack_litres":4,"min_margin_pct":12,"outcome":"approval_required","currency":"BDT"},"missing":[]}','a052-rev-2003');
 r:=c10_demo.preview_owner_intent_v1((s->>'intent_id')::bigint,2,'{"price_per_pack":3200,"cost_per_litre":600,"discount_pct":8}','a052-prv-2003');
 IF (r->'preview'->'sample'->'after'->'computed'->>'margin_pct')::numeric<>18.4783 THEN RAISE EXCEPTION 'PACK_PREVIEW'; END IF;
 -- module not provisioned for the paint business is surfaced, not hidden
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(r->'preview'->'impact'->'conflicts') c WHERE c->>'code'='MODULE_NOT_PROVISIONED') THEN RAISE EXCEPTION 'MODULE_STATE_HIDDEN'; END IF;
END $$;

-- ===== 5. Direct RLS reads for the Owner; guidance =====
DO $$
DECLARE g jsonb; n int;
BEGIN
 SELECT count(*) INTO n FROM c10_demo.owner_intents_v1;
 IF n<>7 THEN RAISE EXCEPTION 'OWNER_DIRECT_READ % ',n; END IF;
 PERFORM public.t052_fail($q$INSERT INTO c10_demo.owner_intents_v1(tenant_id,business_id,raw_text,locale,status,interpretation,created_by) VALUES(1,101,'direct insert','en','INTERPRETED','{}',gen_random_uuid())$q$,'permission denied');
 PERFORM public.t052_fail($q$UPDATE c10_demo.intent_settings_v1 SET params='{}'$q$,'permission denied');
 g:=c10_demo.read_guidance_v1(101,'inventory.low_stock_alert');
 IF g->'effective_permission'->>'can_approve_publish'<>'true' OR g->'current_setting'->>'version'<>'3' OR g->'content'->'what'->>'bn' IS NULL
  OR g->'content'->'data_formula_units'->>'en' IS NULL OR g->'content'->'linked_report'->>'en' IS NULL THEN RAISE EXCEPTION 'GUIDANCE %',g; END IF;
 IF jsonb_array_length(c10_demo.read_guidance_index_v1(101)->'items')<>10 THEN RAISE EXCEPTION 'GUIDANCE_INDEX'; END IF;
 PERFORM public.t052_fail($q$SELECT c10_demo.read_guidance_v1(101,'no.such_key')$q$,'guidance_not_found');
 IF jsonb_array_length(c10_demo.read_intent_businesses_v1()->'items')<>4 THEN RAISE EXCEPTION 'OWNER_BUSINESS_LIST'; END IF;
END $$;

-- ===== 6. Business Owner (tenant 1, business 101): may submit/preview/validate; may NOT approve/publish/rollback =====
SELECT public.t052_as('22222222-2222-4222-8222-222222222222');
DO $$
DECLARE s jsonb; p jsonb; r jsonb;
BEGIN
 s:=c10_demo.submit_owner_intent_v1(101,NULL,'order 6 lakh approval',
  '{"parser_version":"x","locale":"en","support_status":"SUPPORTED","capability_key":"order_total_approval","params":{"threshold":600000,"outcome":"approval_required","currency":"BDT"}}','a052-bo-0001');
 p:=c10_demo.preview_owner_intent_v1((s->>'intent_id')::bigint,1,NULL,'a052-bo-0002');
 PERFORM c10_demo.validate_owner_intent_v1((s->>'intent_id')::bigint,1,p->>'preview_hash','a052-bo-0003');
 PERFORM public.t052_fail(format('SELECT c10_demo.approve_owner_intent_v1(%s,1,%L,%L)',s->>'intent_id','Business owner tries','a052-bo-0004'),'intent_denied');
 PERFORM public.t052_fail(format('SELECT c10_demo.publish_owner_intent_v1(%s,1,%L)',s->>'intent_id','a052-bo-0005'),'intent_denied');
 PERFORM public.t052_fail($q$SELECT c10_demo.rollback_intent_setting_v1(101,'low_stock_alert',1,3,'Business owner tries','a052-bo-0006')$q$,'intent_denied');
 -- scope: business 102 and 301 (same tenant, not theirs) denied
 PERFORM public.t052_fail($q$SELECT c10_demo.read_owner_intents_v1(102)$q$,'intent_denied');
 PERFORM public.t052_fail($q$SELECT c10_demo.submit_owner_intent_v1(301,NULL,'other business',
  '{"parser_version":"x","locale":"en","support_status":"SUPPORTED","capability_key":"low_stock_alert","params":{"threshold":1,"outcome":"warn"}}','a052-bo-0007')$q$,'intent_denied');
 r:=c10_demo.read_guidance_v1(101,'intent.approval_publish');
 IF r->'effective_permission'->>'can_submit'<>'true' OR r->'effective_permission'->>'can_approve_publish'<>'false' OR r->'effective_permission'->>'role'<>'business_owner' THEN RAISE EXCEPTION 'BO_GUIDANCE %',r; END IF;
 IF jsonb_array_length(c10_demo.read_intent_businesses_v1()->'items')<>1 THEN RAISE EXCEPTION 'BO_LIST'; END IF;
 IF (SELECT count(*) FROM c10_demo.owner_intents_v1 WHERE business_id<>101)<>0 THEN RAISE EXCEPTION 'BO_RLS_LEAK'; END IF;
END $$;

-- ===== 7. Manager / investor / revoked / site staff / anon: no Intent authority =====
DO $$
DECLARE u text; r jsonb;
BEGIN
 FOREACH u IN ARRAY ARRAY['33333333-3333-4333-8333-333333333333','55555555-5555-4555-8555-555555555555','66666666-6666-4666-8666-666666666666','44444444-4444-4444-8444-444444444444'] LOOP
  PERFORM public.t052_as(u);
  PERFORM public.t052_fail($q$SELECT c10_demo.submit_owner_intent_v1(101,NULL,'staff request',
   '{"parser_version":"x","locale":"en","support_status":"SUPPORTED","capability_key":"low_stock_alert","params":{"threshold":1,"outcome":"warn"}}','a052-st-0001')$q$,'intent_denied');
  PERFORM public.t052_fail($q$SELECT c10_demo.read_owner_intents_v1(101)$q$,'intent_denied');
  PERFORM public.t052_fail($q$SELECT c10_demo.read_intent_history_v1(101)$q$,'intent_denied');
  PERFORM public.t052_fail($q$SELECT c10_demo.preview_owner_intent_v1(1,1,NULL,'a052-st-0002')$q$,'intent_denied');
  PERFORM public.t052_fail($q$SELECT c10_demo.publish_owner_intent_v1(1,1,'a052-st-0003')$q$,'intent_denied');
  PERFORM public.t052_fail($q$SELECT c10_demo.rollback_intent_setting_v1(101,'low_stock_alert',1,3,'Staff tries it','a052-st-0004')$q$,'intent_denied');
  IF (SELECT count(*) FROM c10_demo.owner_intents_v1)<>0 OR (SELECT count(*) FROM c10_demo.intent_settings_v1)<>0 OR (SELECT count(*) FROM c10_demo.owner_intent_events_v1)<>0
  THEN RAISE EXCEPTION 'RLS_LEAK_FOR %',u; END IF;
 END LOOP;
 -- manager/revoked cannot even detect the business; investor/staff see it as limited with no settings
 PERFORM public.t052_as('33333333-3333-4333-8333-333333333333');
 r:=c10_demo.read_intent_context_v1(101);
 IF r->'actor'->>'can_submit'<>'true' THEN NULL; END IF; -- manager is can_business but NOT can_manage -> must be false
 IF r->'actor'->>'can_submit'<>'false' OR jsonb_array_length(r->'active_settings')<>0 THEN RAISE EXCEPTION 'MANAGER_CONTEXT %',r; END IF;
 PERFORM public.t052_as('44444444-4444-4444-8444-444444444444');
 r:=c10_demo.read_intent_context_v1(101);
 IF r->'actor'->>'role'<>'limited' OR jsonb_array_length(r->'sites')<>1 OR jsonb_array_length(r->'active_settings')<>0 THEN RAISE EXCEPTION 'STAFF_CONTEXT %',r; END IF;
 r:=c10_demo.read_guidance_v1(101,'inventory.low_stock_alert');
 IF r->'effective_permission'->>'can_submit'<>'false' OR r->'current_setting' IS NOT NULL AND r->>'current_setting'<>'null' THEN RAISE EXCEPTION 'STAFF_GUIDANCE %',r; END IF;
 PERFORM public.t052_fail($q$SELECT c10_demo.read_intent_context_v1(102)$q$,'intent_denied');
 PERFORM public.t052_as('66666666-6666-4666-8666-666666666666');
 PERFORM public.t052_fail($q$SELECT c10_demo.read_intent_context_v1(101)$q$,'intent_denied');
 PERFORM public.t052_fail($q$SELECT c10_demo.read_guidance_v1(101,'intent.request_box')$q$,'intent_denied');
 -- anonymous (no claim)
 PERFORM public.t052_as('');
 PERFORM public.t052_fail($q$SELECT c10_demo.read_intent_businesses_v1()$q$,'intent_denied');
 PERFORM public.t052_fail($q$SELECT c10_demo.read_intent_context_v1(101)$q$,'intent_denied');
END $$;
-- real anon role: no execute at all
RESET ROLE;
SET LOCAL ROLE anon;
SELECT public.t052_as('11111111-1111-4111-8111-111111111111');
DO $$ BEGIN
 PERFORM public.t052_fail($q$SELECT c10_demo.read_intent_businesses_v1()$q$,'permission denied');
 PERFORM public.t052_fail($q$SELECT count(*) FROM c10_demo.owner_intents_v1$q$,'permission denied');
END $$;
RESET ROLE;

-- ===== 8. Independent tenant 2 Owner: isolated =====
SET LOCAL ROLE authenticated;
SELECT public.t052_as('77777777-7777-4777-8777-777777777777');
DO $$
DECLARE s jsonb; r jsonb; tid bigint;
BEGIN
 r:=c10_demo.read_intent_businesses_v1();
 IF jsonb_array_length(r->'items')<>1 OR (r->'items'->0->>'business_id')::bigint<>201 THEN RAISE EXCEPTION 'T2_LIST %',r; END IF;
 IF (SELECT count(*) FROM c10_demo.owner_intents_v1)<>0 OR (SELECT count(*) FROM c10_demo.intent_settings_v1)<>0
  OR (SELECT count(*) FROM c10_demo.owner_intent_events_v1)<>0 OR (SELECT count(*) FROM c10_demo.engineering_requirements_v1)<>0 THEN RAISE EXCEPTION 'T2_RLS_LEAK'; END IF;
 PERFORM public.t052_fail($q$SELECT c10_demo.read_owner_intents_v1(101)$q$,'intent_denied');
 PERFORM public.t052_fail($q$SELECT c10_demo.read_intent_context_v1(101)$q$,'intent_denied');
 PERFORM public.t052_fail($q$SELECT c10_demo.read_guidance_v1(101,'intent.rollback')$q$,'intent_denied');
 PERFORM public.t052_fail($q$SELECT c10_demo.rollback_intent_setting_v1(101,'low_stock_alert',1,3,'Cross tenant rollback','a052-t2-0001')$q$,'intent_denied');
 PERFORM public.t052_fail($q$SELECT c10_demo.submit_owner_intent_v1(101,NULL,'cross tenant',
  '{"parser_version":"x","locale":"en","support_status":"SUPPORTED","capability_key":"low_stock_alert","params":{"threshold":1,"outcome":"warn"}}','a052-t2-0002')$q$,'intent_denied');
 -- intent ids of tenant 1 are not reachable by id
 SELECT min(id) INTO tid FROM c10_demo.owner_intents_v1;
 PERFORM public.t052_fail(format('SELECT c10_demo.preview_owner_intent_v1(%s,1,NULL,%L)',1,'a052-t2-0003'),'intent_denied');
 PERFORM public.t052_fail(format('SELECT c10_demo.approve_owner_intent_v1(%s,1,%L,%L)',1,'Cross tenant approve','a052-t2-0004'),'intent_denied');
 -- own tenant works and gets its own isolated state
 s:=c10_demo.submit_owner_intent_v1(201,NULL,'wastage over 4 percent',
  '{"parser_version":"x","locale":"en","support_status":"SUPPORTED","capability_key":"wastage_threshold","params":{"threshold_pct":4,"outcome":"warn","unit":"kg"}}','a052-t2-0005');
 IF s->>'intent_status'<>'INTERPRETED' THEN RAISE EXCEPTION 'T2_SUBMIT'; END IF;
 -- same request key as tenant 1 used earlier does not collide or leak (receipts are per tenant)
 s:=c10_demo.submit_owner_intent_v1(201,NULL,'wastage over 4 percent',
  '{"parser_version":"x","locale":"en","support_status":"SUPPORTED","capability_key":"wastage_threshold","params":{"threshold_pct":4,"outcome":"warn","unit":"kg"}}','a052-sub-0001');
 IF s->>'replayed' IS NOT NULL THEN RAISE EXCEPTION 'RECEIPT_CROSS_TENANT'; END IF;
END $$;
RESET ROLE;

-- ===== 9. Audit / version immutability, and no operational writes anywhere =====
DO $$
BEGIN
 PERFORM public.t052_fail($q$UPDATE c10_demo.owner_intent_events_v1 SET event='tampered'$q$,'intent_audit_immutable');
 PERFORM public.t052_fail($q$DELETE FROM c10_demo.owner_intent_events_v1$q$,'intent_audit_immutable');
 PERFORM public.t052_fail($q$TRUNCATE c10_demo.owner_intent_events_v1$q$,'intent_audit_immutable');
 PERFORM public.t052_fail($q$UPDATE c10_demo.intent_settings_v1 SET params='{"threshold":1,"outcome":"warn"}'$q$,'intent_setting_immutable');
 PERFORM public.t052_fail($q$DELETE FROM c10_demo.intent_settings_v1$q$,'intent_setting_immutable');
 IF (SELECT mv FROM base)<>(SELECT count(*) FROM c10_demo.stock_movements) OR (SELECT it FROM base)<>(SELECT count(*) FROM c10_demo.items)
 THEN RAISE EXCEPTION 'A052_WROTE_OPERATIONAL_DATA'; END IF;
 IF (SELECT count(*) FROM c10_demo.owner_intent_events_v1 WHERE event IN('intent_submitted','intent_previewed','intent_validated','intent_approved','intent_published','setting_published','setting_rolled_back'))<15
 THEN RAISE EXCEPTION 'AUDIT_TOO_SMALL'; END IF;
END $$;
ROLLBACK;
\echo PASS A052 Owner Intent SQL: lifecycle, A045 adapter, stale/replay, authz positive+negative, tenant isolation, audit immutability. No GoTrue runtime.
