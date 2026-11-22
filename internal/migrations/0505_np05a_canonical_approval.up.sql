-- B-015. Canonical typed Approval consumption for recipe approval and batch release.
CREATE FUNCTION core10.mfg_approval_packet_v1(
 p_business bigint,p_site bigint,p_operation text,p_source bigint,p_effective timestamptz
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 SET TimeZone='UTC' AS $$
DECLARE t bigint; feature text; setting jsonb; recipe core10.bom_recipes_v1%ROWTYPE;
 batch core10.production_batches_v1%ROWTYPE; source_body jsonb; source_key text;
 source_version bigint; maker uuid;
BEGIN
 t:=core10._mfg_scope_v1(p_business,p_site);
 CASE p_operation
 WHEN 'recipe_approve' THEN
  feature:='mfg.recipe_approve';
  IF p_effective IS NULL OR NOT isfinite(p_effective) THEN RAISE EXCEPTION 'MFG_EFFECTIVE_REQUIRED'; END IF;
  SELECT * INTO recipe FROM core10.bom_recipes_v1
   WHERE id=p_source AND tenant_id=t AND business_id=p_business AND site_id=p_site;
  IF NOT FOUND THEN RAISE EXCEPTION 'MFG_SCOPE_DENIED'; END IF;
  IF recipe.status<>'draft' THEN RAISE EXCEPTION 'MFG_RECIPE_STATE'; END IF;
  source_key:='mfg-recipe:'||recipe.id;
  source_version:=recipe.version;
  maker:=recipe.created_by;
  source_body:=jsonb_build_object('recipe',to_jsonb(recipe),'effective_from',p_effective,
   'ingredients',(SELECT jsonb_agg(to_jsonb(l) ORDER BY l.line_no)
                  FROM core10.bom_ingredients_v1 l WHERE l.bom_id=recipe.id),
   'substitutions',coalesce((SELECT jsonb_agg(to_jsonb(s) ORDER BY s.id)
                            FROM core10.bom_substitution_rules_v1 s WHERE s.bom_id=recipe.id),'[]'::jsonb));
 WHEN 'batch_release' THEN
  feature:='mfg.batch_release';
  IF p_effective IS NOT NULL THEN RAISE EXCEPTION 'MFG_BATCH_EFFECTIVE_UNEXPECTED'; END IF;
  SELECT * INTO batch FROM core10.production_batches_v1
   WHERE id=p_source AND tenant_id=t AND business_id=p_business AND site_id=p_site;
  IF NOT FOUND THEN RAISE EXCEPTION 'MFG_SCOPE_DENIED'; END IF;
  IF batch.status<>'planned' THEN RAISE EXCEPTION 'MFG_BATCH_STATE'; END IF;
  SELECT * INTO recipe FROM core10.bom_recipes_v1 WHERE id=batch.bom_id;
  IF recipe.status IS DISTINCT FROM 'approved' THEN RAISE EXCEPTION 'MFG_RECIPE_STATE'; END IF;
  source_key:='mfg-batch:'||batch.id;
  -- A batch has one planned revision; its full row and immutable BOM pin are part of the digest.
  source_version:=1;
  maker:=batch.created_by;
  source_body:=jsonb_build_object('batch',to_jsonb(batch),'approved_recipe_version',recipe.version);
 ELSE RAISE EXCEPTION 'MFG_APPROVAL_OPERATION';
 END CASE;

 setting:=core10._control_resolve_v1(p_business,feature,p_site);
 IF NOT (setting->>'enabled')::boolean THEN RAISE EXCEPTION 'CONTROL_DISABLED:%',feature; END IF;
 IF (setting->>'stages')::int<1 THEN RAISE EXCEPTION 'MFG_APPROVAL_NOT_REQUIRED'; END IF;
 RETURN jsonb_build_object('domain','manufacturing','action',p_operation,
  'source_key',source_key,'source_version',source_version,'maker_user_id',maker,
  'required_stages',setting->'stages','payload',jsonb_build_object(
   'contract','C10_MFG_APPROVAL_V1','tenant_id',t,'business_id',p_business,'site_id',p_site,
   'operation',p_operation,'control_source',setting->'source','control_version',setting->'version',
   'required_stages',setting->'stages','source',source_body));
END $$;

CREATE FUNCTION core10.mfg_submit_approval_v1(
 p_business bigint,p_site bigint,p_operation text,p_source bigint,p_effective timestamptz,p_key text
) RETURNS bigint
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE packet jsonb; request_id bigint; actual_stages integer;
BEGIN
 PERFORM core10._mfg_scope_v1(p_business,p_site);
 PERFORM pg_advisory_xact_lock(hashtextextended('c10ctl:'||p_business||':0:gov002.review',0));
 packet:=core10.mfg_approval_packet_v1(p_business,p_site,p_operation,p_source,p_effective);
 IF (packet->>'maker_user_id')::uuid IS DISTINCT FROM core10.actor_uid()
 THEN RAISE EXCEPTION 'MFG_APPROVAL_WRONG_MAKER'; END IF;
 IF NOT (core10._control_resolve_at_v1(p_business,'gov002.review',NULL,clock_timestamp())->>'enabled')::boolean
 THEN RAISE EXCEPTION 'CONTROL_DISABLED:gov002.review'; END IF;
 PERFORM core10.control_check_v1(p_business,'gov002.review',NULL);
 request_id:=core10.submit_typed_approval_v1(p_business,packet->>'domain',packet->>'action',
  packet->>'source_key',(packet->>'source_version')::bigint,packet->'payload',p_key);
 SELECT coalesce(q.route_stages_pinned_v1,1) INTO STRICT actual_stages
  FROM core10.approval_requests q WHERE q.id=request_id;
 IF actual_stages<>(packet->>'required_stages')::int THEN RAISE EXCEPTION 'MFG_APPROVAL_STAGES'; END IF;
 IF packet IS DISTINCT FROM core10.mfg_approval_packet_v1(p_business,p_site,p_operation,p_source,p_effective)
 THEN RAISE EXCEPTION 'MFG_APPROVAL_SOURCE_CHANGED'; END IF;
 PERFORM core10._mfg_control_fresh_v1(p_business,p_site,'mfg.'||p_operation);
 RETURN request_id;
END $$;

CREATE FUNCTION core10._mfg_completed_approval_v1(
 p_approval bigint,p_tenant bigint,p_business bigint,p_site bigint,p_operation text,
 p_source bigint,p_effective timestamptz
) RETURNS bigint
LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog,core10 AS $$
DECLARE q core10.approval_requests%ROWTYPE; packet jsonb; expected integer;
 route_count integer; legacy_event bigint; final_event bigint; completed integer;
 setting jsonb; feature text:='mfg.'||p_operation;
BEGIN
 SELECT * INTO q FROM core10.approval_requests
 WHERE id=p_approval AND tenant_id=p_tenant AND business_id=p_business FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'approval_not_effective'; END IF;

 -- This lock can wait. Reread the source, current role and current policy after acquiring it.
 packet:=core10.mfg_approval_packet_v1(p_business,p_site,p_operation,p_source,p_effective);
 setting:=core10._control_resolve_at_v1(p_business,feature,p_site,clock_timestamp());
 IF NOT (setting->>'enabled')::boolean THEN RAISE EXCEPTION 'CONTROL_DISABLED:%',feature; END IF;
 IF (setting->>'version') IS DISTINCT FROM (packet->'payload'->>'control_version')
    OR (setting->>'source') IS DISTINCT FROM (packet->'payload'->>'control_source')
 THEN RAISE EXCEPTION 'MFG_APPROVAL_CONTROL_CHANGED'; END IF;
 IF NOT (core10._control_resolve_at_v1(p_business,'gov002.review',NULL,clock_timestamp())->>'enabled')::boolean
 THEN RAISE EXCEPTION 'CONTROL_DISABLED:gov002.review'; END IF;

 IF q.created_by IS DISTINCT FROM (packet->>'maker_user_id')::uuid
 THEN RAISE EXCEPTION 'MFG_APPROVAL_WRONG_MAKER'; END IF;
 legacy_event:=core10.verify_approval_binding_v1(p_approval,p_business,packet->>'domain',
  packet->>'action',packet->>'source_key',(packet->>'source_version')::bigint,packet->'payload');

 expected:=(packet->>'required_stages')::integer;
 SELECT cardinality(stages) INTO route_count FROM core10.approval_routes_v1
  WHERE policy_id=q.policy_id_v1 AND tenant_id=p_tenant AND business_id=p_business;
 IF coalesce(route_count,1)<>expected
    OR (q.route_stages_pinned_v1 IS NOT NULL AND q.route_stages_pinned_v1 IS DISTINCT FROM route_count)
 THEN RAISE EXCEPTION 'MFG_APPROVAL_STAGES'; END IF;

 IF route_count IS NULL THEN
  final_event:=legacy_event;
 ELSE
  SELECT count(*),max(e.id) FILTER (WHERE s.stage_no=expected AND e.actor_id=q.decided_by)
  INTO completed,final_event
  FROM core10.approval_stage_receipts_v1 s
  JOIN core10.approval_events e ON e.id=s.event_id AND e.request_id=s.request_id
    AND e.business_id=s.business_id AND e.tenant_id=s.tenant_id AND e.actor_id=s.actor_id
  WHERE s.request_id=p_approval AND s.tenant_id=p_tenant AND s.business_id=p_business
   AND s.stage_no BETWEEN 1 AND expected AND e.action='approve';
  IF completed<>expected OR final_event IS NULL THEN RAISE EXCEPTION 'MFG_APPROVAL_STAGES'; END IF;
 END IF;
 IF (setting->'params'->>'maker_checker')::boolean AND p_operation='recipe_approve' AND EXISTS(
  SELECT 1 FROM core10.bom_substitution_rules_v1 s JOIN core10.approval_events e ON e.actor_id=s.created_by
   WHERE s.bom_id=p_source AND e.request_id=p_approval AND e.action='approve'
 ) THEN RAISE EXCEPTION 'MFG_MAKER_CHECKER'; END IF;
 RETURN final_event;
END $$;

CREATE FUNCTION core10.mfg_approve_recipe_with_approval_v1(p_business bigint,p_site bigint,p_recipe bigint,p_effective timestamptz,p_approval bigint,p_key text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 SET TimeZone='UTC' AS $$
DECLARE t bigint; c jsonb; p jsonb; r jsonb; event_id bigint; b core10.bom_recipes_v1%ROWTYPE;
BEGIN
 t:=core10._mfg_scope_v1(p_business,p_site);
 p:=jsonb_build_object('op','recipe_approve','site',p_site,'recipe',p_recipe,'effective',p_effective,'approval_request_id',p_approval);
 PERFORM core10._mfg_lock_command_v1(p_business,p_key);

 SELECT * INTO b FROM core10.bom_recipes_v1 WHERE id=p_recipe AND business_id=p_business AND site_id=p_site FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'MFG_SCOPE_DENIED'; END IF;
 t:=core10._mfg_scope_v1(p_business,p_site);
 PERFORM core10._mfg_control_fresh_v1(p_business,p_site,'mfg.recipe_approve');
 c:=core10.control_check_v1(p_business,'mfg.recipe_approve',p_site);
 r:=core10._mfg_replay_v1(p_business,p_key,p);
 IF r IS NOT NULL THEN RETURN r; END IF;
 IF b.status<>'draft' THEN RAISE EXCEPTION 'MFG_RECIPE_STATE'; END IF;
 IF (c->'params'->>'maker_checker')::boolean AND b.created_by=core10.actor_uid() THEN RAISE EXCEPTION 'MFG_MAKER_CHECKER'; END IF;
 IF (c->'params'->>'maker_checker')::boolean AND EXISTS(SELECT 1 FROM core10.bom_substitution_rules_v1
  WHERE bom_id=p_recipe AND created_by=core10.actor_uid()) THEN RAISE EXCEPTION 'MFG_MAKER_CHECKER'; END IF;
 IF p_effective IS NULL OR NOT isfinite(p_effective) THEN RAISE EXCEPTION 'MFG_EFFECTIVE_REQUIRED'; END IF;
 PERFORM core10._mfg_master_check_v1(p_recipe);
 PERFORM core10._mfg_substitution_check_v1(p_recipe);
 t:=core10._mfg_scope_v1(p_business,p_site);
 PERFORM core10._mfg_control_fresh_v1(p_business,p_site,'mfg.recipe_approve');
 event_id:=core10._mfg_completed_approval_v1(p_approval,t,p_business,p_site,'recipe_approve',p_recipe,p_effective);
 UPDATE core10.bom_recipes_v1 SET status='approved',approved_by=core10.actor_uid(),effective_from=p_effective WHERE id=p_recipe;
 r:=jsonb_build_object('recipe_id',p_recipe,'status','approved','effective_from',p_effective);

 RETURN core10._mfg_receipt_v1(t,p_business,p_site,p_key,p,
  r||jsonb_build_object('approval_request_id',p_approval,'approval_event_id',event_id));
END $$;

CREATE FUNCTION core10.mfg_release_batch_with_approval_v1(p_business bigint,p_site bigint,p_batch bigint,p_approval bigint,p_key text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 SET TimeZone='UTC' AS $$
DECLARE t bigint; c jsonb; p jsonb; r jsonb; event_id bigint; b core10.production_batches_v1%ROWTYPE;
BEGIN
 t:=core10._mfg_scope_v1(p_business,p_site);
 p:=jsonb_build_object('op','batch_release','site',p_site,'batch',p_batch,'approval_request_id',p_approval);
 PERFORM core10._mfg_lock_command_v1(p_business,p_key);

 SELECT * INTO b FROM core10.production_batches_v1 WHERE id=p_batch AND business_id=p_business AND site_id=p_site FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'MFG_SCOPE_DENIED'; END IF;
 t:=core10._mfg_scope_v1(p_business,p_site);
 PERFORM core10._mfg_control_fresh_v1(p_business,p_site,'mfg.batch_release');
 c:=core10.control_check_v1(p_business,'mfg.batch_release',p_site);
 r:=core10._mfg_replay_v1(p_business,p_key,p);
 IF r IS NOT NULL THEN RETURN r; END IF;
 IF b.status<>'planned' THEN RAISE EXCEPTION 'MFG_BATCH_STATE'; END IF;
 IF (c->'params'->>'maker_checker')::boolean AND b.created_by=core10.actor_uid() THEN RAISE EXCEPTION 'MFG_MAKER_CHECKER'; END IF;
 PERFORM core10._mfg_master_check_v1(b.bom_id);
 t:=core10._mfg_scope_v1(p_business,p_site);
 PERFORM core10._mfg_control_fresh_v1(p_business,p_site,'mfg.batch_release');
 event_id:=core10._mfg_completed_approval_v1(p_approval,t,p_business,p_site,'batch_release',p_batch,NULL);
 UPDATE core10.production_batches_v1 SET status='released',released_by=core10.actor_uid() WHERE id=p_batch;
 r:=jsonb_build_object('batch_id',p_batch,'status','released','stock','NOT_CONNECTED','stock_issued',false);

 RETURN core10._mfg_receipt_v1(t,p_business,p_site,p_key,p,
  r||jsonb_build_object('approval_request_id',p_approval,'approval_event_id',event_id));
END $$;

REVOKE ALL ON FUNCTION core10._mfg_completed_approval_v1(bigint,bigint,bigint,bigint,text,bigint,timestamptz)
 FROM PUBLIC,authenticated;
REVOKE ALL ON FUNCTION core10.mfg_approval_packet_v1(bigint,bigint,text,bigint,timestamptz),
 core10.mfg_submit_approval_v1(bigint,bigint,text,bigint,timestamptz,text),
 core10.mfg_approve_recipe_with_approval_v1(bigint,bigint,bigint,timestamptz,bigint,text),
 core10.mfg_release_batch_with_approval_v1(bigint,bigint,bigint,bigint,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION core10.mfg_approval_packet_v1(bigint,bigint,text,bigint,timestamptz),
 core10.mfg_submit_approval_v1(bigint,bigint,text,bigint,timestamptz,text),
 core10.mfg_approve_recipe_with_approval_v1(bigint,bigint,bigint,timestamptz,bigint,text),
 core10.mfg_release_batch_with_approval_v1(bigint,bigint,bigint,bigint,text) TO authenticated;

INSERT INTO core10.control_rpc_map_v1(rpc_name,status,feature_key,reason,lane,board_row,test_ref) VALUES
 ('mfg_submit_approval_v1','enforced','gov002.review',
  'Canonical maker submits a scoped Manufacturing packet to GOV002','Codex Build 4','B-015','tests/np05a/staged-approval-e2e.sql'),
 ('mfg_approve_recipe_with_approval_v1','enforced','mfg.recipe_approve',
  'Canonical Control and typed Approval receipts for an exact recipe draft','Codex Build 4','B-015','tests/np05a/staged-approval-e2e.sql'),
 ('mfg_release_batch_with_approval_v1','enforced','mfg.batch_release',
  'Canonical Control and typed Approval receipts for an exact planned batch','Codex Build 4','B-015','tests/np05a/staged-approval-e2e.sql');
