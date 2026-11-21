-- B-015 increment 2: manufacturing material planning and source handoff contracts.
-- Forward-only change to the unpublished candidate; 0500 is never edited.
-- No Stock, Money, Master or Auth implementation is installed by this migration.
INSERT INTO core10.control_catalog_v1(feature_key,title_en,title_bn,pack,default_enabled,default_stages,max_stages,params)
 VALUES('mfg.material_requirements','Material and packaging requirements','উপকরণ ও প্যাকেজিং চাহিদা','NP05A',true,0,0,'{}');

CREATE FUNCTION core10._mfg_material_plan_v1(
 p_business bigint,p_site bigint,p_recipe bigint,p_multiplier numeric
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE t bigint; b core10.bom_recipes_v1%ROWTYPE; c jsonb; lines jsonb; q numeric; cost numeric;
BEGIN
 t:=core10._mfg_scope_v1(p_business,p_site);
 SELECT * INTO b FROM core10.bom_recipes_v1 WHERE id=p_recipe AND business_id=p_business AND site_id=p_site;
 IF NOT FOUND THEN RAISE EXCEPTION 'MFG_SCOPE_DENIED'; END IF;
 IF p_multiplier IS NULL OR p_multiplier<=0 OR p_multiplier>100000 OR p_multiplier<>round(p_multiplier,6)
 THEN RAISE EXCEPTION 'MFG_INVALID_MULTIPLIER'; END IF;
 q:=b.yield_quantity*p_multiplier;
 IF q>100000000 OR q<>round(q,6) OR EXISTS(SELECT 1 FROM core10.bom_ingredients_v1 l WHERE l.bom_id=p_recipe
  AND (l.qty_per_batch*p_multiplier>100000000 OR l.qty_per_batch*p_multiplier<>round(l.qty_per_batch*p_multiplier,6)))
 THEN RAISE EXCEPTION 'MFG_QUANTITY_PRECISION'; END IF;
 SELECT jsonb_agg(jsonb_build_object('line_no',l.line_no,'item_id',l.ingredient_item_id,'sku',i.sku,
  'kind',l.component_kind,'uom_ref',l.uom_ref,'quantity',l.qty_per_batch*p_multiplier,
  'expected_waste_pct',l.expected_waste_pct,
  'expected_waste_quantity',round(l.qty_per_batch*p_multiplier*l.expected_waste_pct/100,6),
  'expected_usable_quantity',l.qty_per_batch*p_multiplier-round(l.qty_per_batch*p_multiplier*l.expected_waste_pct/100,6),
  'estimated_unit_cost',l.estimated_unit_cost,'estimated_line_cost',round(l.qty_per_batch*p_multiplier*l.estimated_unit_cost,2),
  'available_quantity',NULL,'shortage_quantity',NULL,'availability_status','NOT_CONNECTED',
  'base_uom_quantity',NULL,'conversion_status','NOT_CONNECTED') ORDER BY l.line_no),
  round((sum(l.qty_per_batch*l.estimated_unit_cost)+b.overhead_estimate)*p_multiplier,2)
 INTO lines,cost FROM core10.bom_ingredients_v1 l JOIN core10.items i
  ON i.id=l.ingredient_item_id AND i.tenant_id=t AND i.business_id=p_business WHERE l.bom_id=p_recipe;
 RETURN jsonb_build_object('recipe_id',b.id,'recipe_version',b.version,'recipe_status',b.status,
  'recipe_code',b.recipe_code,'multiplier',p_multiplier,'planning_only',true,
  'output',jsonb_build_object('item_id',b.finished_item_id,'quantity',q,'uom_ref',b.yield_uom_ref),
  'lines',lines,'estimated_total_cost',cost,'estimated_overhead',round(b.overhead_estimate*p_multiplier,2),
  'cost_basis','UNVERIFIED_PLANNING_ESTIMATE','stock','NOT_CONNECTED','master_uom','NOT_CONNECTED',
  'waste_basis','Expected share of planned input in each line UOM; no stock movement',
  'rounding','Expected waste display rounded to 6 decimals; no allocation between unlike UOMs');
END $$;
REVOKE ALL ON FUNCTION core10._mfg_material_plan_v1(bigint,bigint,bigint,numeric) FROM PUBLIC,authenticated;
CREATE FUNCTION core10.mfg_material_requirements_v1(p_business bigint,p_site bigint,p_recipe bigint,p_multiplier numeric)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE t bigint; c jsonb;
BEGIN
 t:=core10._mfg_scope_v1(p_business,p_site);
 c:=core10._control_resolve_v1(p_business,'mfg.material_requirements',p_site);
 IF NOT (c->>'enabled')::boolean THEN RAISE EXCEPTION 'CONTROL_DISABLED:mfg.material_requirements'; END IF;
 RETURN core10._mfg_material_plan_v1(p_business,p_site,p_recipe,p_multiplier);
END $$;
REVOKE ALL ON FUNCTION core10.mfg_material_requirements_v1(bigint,bigint,bigint,numeric) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION core10.mfg_material_requirements_v1(bigint,bigint,bigint,numeric) TO authenticated;

-- Private deterministic source envelope. Called only after the batch is locked and Auth/Control rechecked.
-- Quantities retain their recipe UOM. Base-UOM and lot validation are deliberately unverified.
-- No function existence heuristic is treated as a connected/verified provider.
CREATE FUNCTION core10._mfg_handoff_envelope_v1(p_batch bigint,p_kind text) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path=pg_catalog,core10 AS $$
DECLARE b core10.production_batches_v1%ROWTYPE; recipe core10.bom_recipes_v1%ROWTYPE;
 plan jsonb; body jsonb; lines jsonb; batch_audit jsonb; recipe_audit jsonb;
BEGIN
 SELECT * INTO b FROM core10.production_batches_v1 WHERE id=p_batch;
 SELECT * INTO recipe FROM core10.bom_recipes_v1 WHERE id=b.bom_id;
 IF b.id IS NULL OR p_kind IS NULL OR p_kind NOT IN('ingredients','finished_goods','finance')
 THEN RAISE EXCEPTION 'MFG_HANDOFF_KIND'; END IF;
 plan:=core10._mfg_material_plan_v1(b.business_id,b.site_id,b.bom_id,b.multiplier);
 IF p_kind='ingredients' THEN
  SELECT jsonb_agg(jsonb_build_object('source_line',x->'line_no','item_id',x->'item_id',
   'quantity',x->'quantity','uom_ref',x->'uom_ref','component_kind',x->'kind',
   'base_uom_quantity',NULL,'lot_ref',NULL) ORDER BY (x->>'line_no')::int)
  INTO lines FROM jsonb_array_elements(plan->'lines') x;
 ELSIF p_kind='finished_goods' THEN
  IF b.status<>'recorded' THEN RAISE EXCEPTION 'MFG_BATCH_STATE'; END IF;
  -- Good output only. Rejected/rework/loss are observations, never implicit receipts or journals.
  lines:=jsonb_build_array(jsonb_build_object('source_line',0,'item_id',recipe.finished_item_id,
   'quantity',b.output_payload->'good','uom_ref',recipe.yield_uom_ref,'component_kind','finished_goods',
   'base_uom_quantity',NULL,'lot_ref',b.output_payload->'lot_ref'));
 ELSE
  IF b.status<>'recorded' THEN RAISE EXCEPTION 'MFG_BATCH_STATE'; END IF;
  lines:='[]'::jsonb;
 END IF;
 SELECT coalesce(jsonb_agg(audit_event_id ORDER BY audit_event_id),'[]'::jsonb) INTO batch_audit
 FROM core10.mfg_command_receipts_v1 WHERE business_id=b.business_id AND site_id=b.site_id
  AND response->>'batch_id'=p_batch::text AND payload->>'op' IN('batch_plan','batch_release','output_record');
 SELECT coalesce(jsonb_agg(audit_event_id ORDER BY audit_event_id),'[]'::jsonb) INTO recipe_audit
 FROM core10.mfg_command_receipts_v1 WHERE business_id=b.business_id AND site_id=b.site_id
  AND response->>'recipe_id'=recipe.id::text AND payload->>'op' IN('recipe_create','recipe_approve');
 body:=jsonb_build_object('contract','np05a.manufacturing_handoff.v1','contract_status','PROPOSED_NOT_CONNECTED',
  'kind',p_kind,'scope',jsonb_build_object('tenant_id',b.tenant_id,'business_id',b.business_id,'site_id',b.site_id),
  'source',jsonb_build_object('batch_id',b.id,'batch_status',b.status,'recipe_id',recipe.id,
   'recipe_version',recipe.version,'location_id',b.location_id,'batch_audit_event_ids',batch_audit,'recipe_audit_event_ids',recipe_audit),
  'lines',lines,'observations',CASE WHEN p_kind='ingredients' THEN NULL ELSE b.output_payload END,
  'planning_cost',CASE WHEN p_kind='finance' THEN jsonb_build_object('estimated_total_cost',b.estimated_total_cost,
   'cost_basis','UNVERIFIED_PLANNING_ESTIMATE','recognized_value',NULL,'journal_entries',NULL) ELSE NULL END,
  'master_uom','NOT_CONNECTED','lot_validation','NOT_CONNECTED','stock_issued',false,
  'stock_received',false,'financial_posted',false);
 RETURN body||jsonb_build_object('source_fingerprint',encode(sha256(convert_to(body::text,'UTF8')),'hex'));
END $$;
REVOKE ALL ON FUNCTION core10._mfg_handoff_envelope_v1(bigint,text) FROM PUBLIC,authenticated;

-- Acquire the idempotency lock without inspecting/returning another command's payload.
-- Replay validation occurs only after fresh authorization and Control enforcement.
CREATE FUNCTION core10._mfg_lock_command_v1(p_business bigint,p_key text) RETURNS void
LANGUAGE plpgsql SET search_path=pg_catalog,core10 AS $$
BEGIN
 IF p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{8,100}$' THEN RAISE EXCEPTION 'MFG_BAD_KEY'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('mfg:'||p_business||':'||p_key,0));
END $$;
REVOKE ALL ON FUNCTION core10._mfg_lock_command_v1(bigint,text) FROM PUBLIC,authenticated;

-- Canonical Control resolves against statement_timestamp(). A setting or schedule that
-- became effective during a wait cannot safely use that older cutoff. Refuse and ask for
-- a fresh request; never implement a second policy resolver or consume two overrides.
CREATE FUNCTION core10._mfg_control_fresh_v1(p_business bigint,p_site bigint,p_feature text) RETURNS void
LANGUAGE plpgsql SET search_path=pg_catalog,core10 AS $$
BEGIN
 IF EXISTS(SELECT 1 FROM core10.control_setting_versions_v1 WHERE business_id=p_business
  AND feature_key=p_feature AND (site_id IS NULL OR site_id=p_site)
  AND effective_from>statement_timestamp() AND effective_from<=clock_timestamp())
 THEN RAISE EXCEPTION 'MFG_CONTROL_CHANGED_RETRY'; END IF;
END $$;
REVOKE ALL ON FUNCTION core10._mfg_control_fresh_v1(bigint,bigint,text) FROM PUBLIC,authenticated;

-- Fresh Auth/Control after blocking locks, before replay return and every mutation.
CREATE OR REPLACE FUNCTION core10.mfg_create_recipe_v1(p_business bigint,p_site bigint,p_finished_item bigint,p_code text,p_yield numeric,p_uom text,p_lines jsonb,p_overhead numeric,p_key text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE t bigint; c jsonb; p jsonb; r jsonb; v_id bigint; v integer; x jsonb; ix integer:=0; used bigint[]:='{}';
BEGIN
 t:=core10._mfg_scope_v1(p_business,p_site);
 p:=jsonb_build_object('op','recipe_create','site',p_site,'item',p_finished_item,'code',p_code,'yield',p_yield,'uom',p_uom,'lines',p_lines,'overhead',p_overhead);
 PERFORM core10._mfg_lock_command_v1(p_business,p_key);
 PERFORM pg_advisory_xact_lock(hashtextextended('mfg-recipe:'||p_business||':'||p_site||':'||btrim(p_code),0));
 t:=core10._mfg_scope_v1(p_business,p_site);
 PERFORM core10._mfg_control_fresh_v1(p_business,p_site,'mfg.recipe');
 c:=core10.control_check_v1(p_business,'mfg.recipe',p_site);
 r:=core10._mfg_replay_v1(p_business,p_key,p);
 IF r IS NOT NULL THEN RETURN r; END IF;

 IF p_code IS NULL OR length(btrim(p_code)) NOT BETWEEN 2 AND 80 OR p_yield IS NULL OR p_yield<=0
  OR p_yield>100000000 OR p_yield<>round(p_yield,6) OR p_uom IS NULL OR length(p_uom) NOT BETWEEN 1 AND 80
  OR p_overhead IS NULL OR p_overhead<0 OR p_overhead>1000000000 OR p_overhead<>round(p_overhead,2)
  OR jsonb_typeof(p_lines) IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'MFG_INVALID_RECIPE'; END IF;
 IF jsonb_array_length(p_lines) NOT BETWEEN 1 AND 100 THEN RAISE EXCEPTION 'MFG_INVALID_LINES'; END IF;
 IF NOT EXISTS(SELECT 1 FROM core10.items WHERE id=p_finished_item AND business_id=p_business AND tenant_id=t)
  THEN RAISE EXCEPTION 'MFG_ITEM_SCOPE'; END IF;
 -- Serialize version allocation even when command keys differ.
 SELECT coalesce(max(version),0)+1 INTO v FROM core10.bom_recipes_v1
  WHERE business_id=p_business AND site_id=p_site AND recipe_code=btrim(p_code);
 FOR x IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
  IF jsonb_typeof(x) IS DISTINCT FROM 'object' OR NOT (x ?& ARRAY['item','qty','uom_ref','kind','waste_pct','estimated_unit_cost'])
   OR (SELECT count(*) FROM jsonb_object_keys(x))<>6
   OR jsonb_typeof(x->'item') IS DISTINCT FROM 'number' OR (x->>'item')::numeric<>trunc((x->>'item')::numeric)
   OR jsonb_typeof(x->'qty') IS DISTINCT FROM 'number' OR jsonb_typeof(x->'estimated_unit_cost') IS DISTINCT FROM 'number'
   OR jsonb_typeof(x->'waste_pct') IS DISTINCT FROM 'number'
   OR jsonb_typeof(x->'uom_ref') IS DISTINCT FROM 'string' OR jsonb_typeof(x->'kind') IS DISTINCT FROM 'string'
   THEN RAISE EXCEPTION 'MFG_INVALID_LINES'; END IF;
  IF (x->>'item')::bigint=p_finished_item OR (x->>'item')::bigint=ANY(used)
   OR NOT EXISTS(SELECT 1 FROM core10.items WHERE id=(x->>'item')::bigint AND tenant_id=t AND business_id=p_business)
   THEN RAISE EXCEPTION 'MFG_ITEM_SCOPE'; END IF;
  used:=array_append(used,(x->>'item')::bigint);
 END LOOP;
 INSERT INTO core10.bom_recipes_v1(tenant_id,business_id,site_id,finished_item_id,recipe_code,version,
  yield_quantity,yield_uom_ref,overhead_estimate,ingredients_payload,created_by)
 VALUES(t,p_business,p_site,p_finished_item,btrim(p_code),v,p_yield,p_uom,p_overhead,p_lines,core10.actor_uid()) RETURNING bom_recipes_v1.id INTO v_id;
 FOR x IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
  ix:=ix+1;
  INSERT INTO core10.bom_ingredients_v1 VALUES(v_id,t,p_business,p_site,ix,(x->>'item')::bigint,
   (x->>'qty')::numeric,x->>'uom_ref',x->>'kind',(x->>'waste_pct')::numeric,(x->>'estimated_unit_cost')::numeric);
 END LOOP;
 r:=jsonb_build_object('recipe_id',v_id,'version',v,'status','draft','master','NOT_CONNECTED','cost_basis','UNVERIFIED_PLANNING_ESTIMATE');

 RETURN core10._mfg_receipt_v1(t,p_business,p_site,p_key,p,r);
END $$;

CREATE OR REPLACE FUNCTION core10.mfg_approve_recipe_v1(p_business bigint,p_site bigint,p_recipe bigint,p_effective timestamptz,p_key text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE t bigint; c jsonb; p jsonb; r jsonb; b core10.bom_recipes_v1%ROWTYPE;
BEGIN
 t:=core10._mfg_scope_v1(p_business,p_site);
 p:=jsonb_build_object('op','recipe_approve','site',p_site,'recipe',p_recipe,'effective',p_effective);
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
 IF (c->>'stages')::int>0 THEN RAISE EXCEPTION 'NOT_CONNECTED:APPROVAL_COMPLETION'; END IF;
 IF p_effective IS NULL THEN RAISE EXCEPTION 'MFG_EFFECTIVE_REQUIRED'; END IF;
 PERFORM core10._mfg_master_check_v1(p_recipe);
 UPDATE core10.bom_recipes_v1 SET status='approved',approved_by=core10.actor_uid(),effective_from=p_effective WHERE id=p_recipe;
 r:=jsonb_build_object('recipe_id',p_recipe,'status','approved','effective_from',p_effective);

 RETURN core10._mfg_receipt_v1(t,p_business,p_site,p_key,p,r);
END $$;

CREATE OR REPLACE FUNCTION core10.mfg_plan_batch_v1(p_business bigint,p_site bigint,p_recipe bigint,p_location bigint,p_multiplier numeric,p_key text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE t bigint; c jsonb; p jsonb; r jsonb; b core10.bom_recipes_v1%ROWTYPE; v_id bigint; q numeric; cost numeric;
BEGIN
 t:=core10._mfg_scope_v1(p_business,p_site);
 p:=jsonb_build_object('op','batch_plan','site',p_site,'recipe',p_recipe,'location',p_location,'multiplier',p_multiplier);
 PERFORM core10._mfg_lock_command_v1(p_business,p_key);

 SELECT * INTO b FROM core10.bom_recipes_v1 WHERE id=p_recipe AND business_id=p_business AND site_id=p_site;
 IF NOT FOUND THEN RAISE EXCEPTION 'MFG_SCOPE_DENIED'; END IF;
 t:=core10._mfg_scope_v1(p_business,p_site);
 PERFORM core10._mfg_control_fresh_v1(p_business,p_site,'mfg.batch');
 c:=core10.control_check_v1(p_business,'mfg.batch',p_site);
 r:=core10._mfg_replay_v1(p_business,p_key,p);
 IF r IS NOT NULL THEN RETURN r; END IF;
 IF (c->>'stages')::int>0 THEN RAISE EXCEPTION 'NOT_CONNECTED:APPROVAL_COMPLETION'; END IF;
 IF b.status<>'approved' OR b.effective_from>statement_timestamp() THEN RAISE EXCEPTION 'MFG_RECIPE_NOT_EFFECTIVE'; END IF;
 -- Do not silently use a superseded approved version for a new batch. Historical batches retain their version.
 IF EXISTS(SELECT 1 FROM core10.bom_recipes_v1 n WHERE n.business_id=p_business AND n.site_id=p_site
   AND n.recipe_code=b.recipe_code AND n.version>b.version AND n.status='approved' AND n.effective_from<=statement_timestamp())
  THEN RAISE EXCEPTION 'MFG_RECIPE_SUPERSEDED'; END IF;
 IF p_multiplier IS NULL OR p_multiplier<=0 OR p_multiplier>100000 OR p_multiplier<>round(p_multiplier,6)
  THEN RAISE EXCEPTION 'MFG_INVALID_MULTIPLIER'; END IF;
 q:=b.yield_quantity*p_multiplier;
 IF q>100000000 OR q<>round(q,6) OR EXISTS(SELECT 1 FROM core10.bom_ingredients_v1 l WHERE l.bom_id=p_recipe
  AND (l.qty_per_batch*p_multiplier>100000000 OR l.qty_per_batch*p_multiplier<>round(l.qty_per_batch*p_multiplier,6)))
  THEN RAISE EXCEPTION 'MFG_QUANTITY_PRECISION'; END IF;
 IF NOT EXISTS(SELECT 1 FROM core10.stock_locations WHERE id=p_location AND tenant_id=t AND business_id=p_business AND site_id=p_site)
  THEN RAISE EXCEPTION 'MFG_LOCATION_SCOPE'; END IF;
 SELECT round((sum(qty_per_batch*estimated_unit_cost)+b.overhead_estimate)*p_multiplier,2) INTO cost
  FROM core10.bom_ingredients_v1 WHERE bom_id=p_recipe;
 INSERT INTO core10.production_batches_v1(tenant_id,business_id,site_id,location_id,bom_id,multiplier,expected_output,estimated_total_cost,created_by)
 VALUES(t,p_business,p_site,p_location,p_recipe,p_multiplier,q,cost,core10.actor_uid()) RETURNING production_batches_v1.id INTO v_id;
 r:=jsonb_build_object('batch_id',v_id,'status','planned','expected_output',q,'estimated_total_cost',cost,'actual_cogs_certified',false);

 RETURN core10._mfg_receipt_v1(t,p_business,p_site,p_key,p,r);
END $$;

CREATE OR REPLACE FUNCTION core10.mfg_release_batch_v1(p_business bigint,p_site bigint,p_batch bigint,p_key text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE t bigint; c jsonb; p jsonb; r jsonb; b core10.production_batches_v1%ROWTYPE;
BEGIN
 t:=core10._mfg_scope_v1(p_business,p_site);
 p:=jsonb_build_object('op','batch_release','site',p_site,'batch',p_batch);
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
 IF (c->>'stages')::int>0 THEN RAISE EXCEPTION 'NOT_CONNECTED:APPROVAL_COMPLETION'; END IF;
 PERFORM core10._mfg_master_check_v1(b.bom_id);
 UPDATE core10.production_batches_v1 SET status='released',released_by=core10.actor_uid() WHERE id=p_batch;
 r:=jsonb_build_object('batch_id',p_batch,'status','released','stock','NOT_CONNECTED','stock_issued',false);

 RETURN core10._mfg_receipt_v1(t,p_business,p_site,p_key,p,r);
END $$;

CREATE OR REPLACE FUNCTION core10.mfg_record_output_v1(p_business bigint,p_site bigint,p_batch bigint,p_output jsonb,p_key text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE t bigint; c jsonb; p jsonb; r jsonb; b core10.production_batches_v1%ROWTYPE; x jsonb; total numeric:=0; loss numeric; used integer[]:='{}'; l record; ix integer; qty numeric;
BEGIN
 t:=core10._mfg_scope_v1(p_business,p_site);
 p:=jsonb_build_object('op','output_record','site',p_site,'batch',p_batch,'output',p_output);
 PERFORM core10._mfg_lock_command_v1(p_business,p_key);

 SELECT * INTO b FROM core10.production_batches_v1 WHERE id=p_batch AND business_id=p_business AND site_id=p_site FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'MFG_SCOPE_DENIED'; END IF;
 t:=core10._mfg_scope_v1(p_business,p_site);
 PERFORM core10._mfg_control_fresh_v1(p_business,p_site,'mfg.output');
 c:=core10.control_check_v1(p_business,'mfg.output',p_site);
 r:=core10._mfg_replay_v1(p_business,p_key,p);
 IF r IS NOT NULL THEN RETURN r; END IF;
 IF b.status<>'released' THEN RAISE EXCEPTION 'MFG_BATCH_STATE'; END IF;
 IF (c->>'stages')::int>0 THEN RAISE EXCEPTION 'NOT_CONNECTED:APPROVAL_COMPLETION'; END IF;
 IF jsonb_typeof(p_output) IS DISTINCT FROM 'object' OR NOT (p_output ?& ARRAY['good','rejected','rework','loss','reason','lot_ref','consumption'])
  OR (SELECT count(*) FROM jsonb_object_keys(p_output))<>7 THEN RAISE EXCEPTION 'MFG_OUTPUT_SHAPE'; END IF;
 FOREACH x IN ARRAY ARRAY[p_output->'good',p_output->'rejected',p_output->'rework',p_output->'loss'] LOOP
  IF jsonb_typeof(x) IS DISTINCT FROM 'number' OR x::text::numeric<0 OR x::text::numeric>100000000
   OR x::text::numeric<>round(x::text::numeric,6) THEN RAISE EXCEPTION 'MFG_OUTPUT_QUANTITY'; END IF;
  total:=total+x::text::numeric;
 END LOOP;
 -- All output categories use recipe yield UOM; never sum kg ingredient quantities with pieces output.
 IF total<>b.expected_output THEN RAISE EXCEPTION 'MFG_YIELD_RECONCILIATION'; END IF;
 IF jsonb_typeof(p_output->'lot_ref') IS DISTINCT FROM 'string' OR length(btrim(p_output->>'lot_ref')) NOT BETWEEN 1 AND 120
  THEN RAISE EXCEPTION 'MFG_LOT_REQUIRED'; END IF;
 loss:=((p_output->>'loss')::numeric+(p_output->>'rejected')::numeric)*100/b.expected_output;
 IF loss>(c->'params'->>'max_loss_pct')::numeric THEN RAISE EXCEPTION 'CONTROL_LIMIT:max_loss_pct'; END IF;
 IF jsonb_typeof(p_output->'reason') IS DISTINCT FROM 'string' OR (p_output->>'reason') IS DISTINCT FROM (c->'params'->>'waste_reason_codes')
  THEN RAISE EXCEPTION 'MFG_WASTE_REASON'; END IF;
 IF jsonb_typeof(p_output->'consumption') IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'MFG_CONSUMPTION_SHAPE'; END IF;
 FOR x IN SELECT value FROM jsonb_array_elements(p_output->'consumption') LOOP
  IF jsonb_typeof(x) IS DISTINCT FROM 'object' OR NOT (x ?& ARRAY['line','qty','lot_ref']) OR (SELECT count(*) FROM jsonb_object_keys(x))<>3
   OR jsonb_typeof(x->'line') IS DISTINCT FROM 'number' OR (x->>'line')::numeric<>trunc((x->>'line')::numeric)
   OR jsonb_typeof(x->'qty') IS DISTINCT FROM 'number' OR (x->>'qty')::numeric<0 OR (x->>'qty')::numeric>100000000
   OR (x->>'qty')::numeric<>round((x->>'qty')::numeric,6)
   OR jsonb_typeof(x->'lot_ref') IS DISTINCT FROM 'string' OR length(btrim(x->>'lot_ref')) NOT BETWEEN 1 AND 120
   THEN RAISE EXCEPTION 'MFG_CONSUMPTION_SHAPE'; END IF;
  ix:=(x->>'line')::integer; qty:=(x->>'qty')::numeric;
  SELECT * INTO l FROM core10.bom_ingredients_v1 WHERE bom_id=b.bom_id AND line_no=ix;
  IF NOT FOUND OR ix=ANY(used) THEN RAISE EXCEPTION 'MFG_CONSUMPTION_LINE'; END IF;
  IF abs(qty-l.qty_per_batch*b.multiplier)*100/(l.qty_per_batch*b.multiplier)>(c->'params'->>'max_consumption_variance_pct')::numeric
   THEN RAISE EXCEPTION 'CONTROL_LIMIT:max_consumption_variance_pct'; END IF;
  used:=array_append(used,ix);
 END LOOP;
 IF cardinality(used)<>(SELECT count(*) FROM core10.bom_ingredients_v1 WHERE bom_id=b.bom_id)
  THEN RAISE EXCEPTION 'MFG_CONSUMPTION_INCOMPLETE'; END IF;
 UPDATE core10.production_batches_v1 SET status='recorded',recorded_by=core10.actor_uid(),output_payload=p_output WHERE id=p_batch;
 r:=jsonb_build_object('batch_id',p_batch,'status','recorded','yield_pct',(p_output->>'good')::numeric*100/b.expected_output,
  'stock','NOT_CONNECTED','finance','NOT_CONNECTED','stock_received',false,'financial_posted',false);

 RETURN core10._mfg_receipt_v1(t,p_business,p_site,p_key,p,r);
END $$;

CREATE OR REPLACE FUNCTION core10.mfg_cancel_batch_v1(p_business bigint,p_site bigint,p_batch bigint,p_reason text,p_key text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE t bigint; c jsonb; p jsonb; r jsonb; b core10.production_batches_v1%ROWTYPE;
BEGIN
 t:=core10._mfg_scope_v1(p_business,p_site);
 p:=jsonb_build_object('op','batch_cancel','site',p_site,'batch',p_batch,'reason',p_reason);
 PERFORM core10._mfg_lock_command_v1(p_business,p_key);

 SELECT * INTO b FROM core10.production_batches_v1 WHERE id=p_batch AND business_id=p_business AND site_id=p_site FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'MFG_SCOPE_DENIED'; END IF;
 t:=core10._mfg_scope_v1(p_business,p_site);
 PERFORM core10._mfg_control_fresh_v1(p_business,p_site,'mfg.batch');
 c:=core10.control_check_v1(p_business,'mfg.batch',p_site);
 r:=core10._mfg_replay_v1(p_business,p_key,p);
 IF r IS NOT NULL THEN RETURN r; END IF;
 -- Recorded/released production needs a correction and reversal contract, not deletion or cancellation.
 IF b.status<>'planned' THEN RAISE EXCEPTION 'NOT_CONNECTED:CONTROLLED_REVERSAL'; END IF;
 IF p_reason IS NULL OR length(btrim(p_reason)) NOT BETWEEN 5 AND 500 THEN RAISE EXCEPTION 'MFG_REASON_REQUIRED'; END IF;
 IF (c->>'stages')::int>0 THEN RAISE EXCEPTION 'NOT_CONNECTED:APPROVAL_COMPLETION'; END IF;
 UPDATE core10.production_batches_v1 SET status='cancelled' WHERE id=p_batch;
 r:=jsonb_build_object('batch_id',p_batch,'status','cancelled');

 RETURN core10._mfg_receipt_v1(t,p_business,p_site,p_key,p,r);
END $$;

CREATE OR REPLACE FUNCTION core10.mfg_request_handoff_v1(p_business bigint,p_site bigint,p_batch bigint,p_kind text,p_key text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE t bigint; c jsonb; p jsonb; r jsonb; b core10.production_batches_v1%ROWTYPE;
BEGIN
 t:=core10._mfg_scope_v1(p_business,p_site);
 p:=jsonb_build_object('op','handoff_request','site',p_site,'batch',p_batch,'kind',p_kind);
 PERFORM core10._mfg_lock_command_v1(p_business,p_key);

 SELECT * INTO b FROM core10.production_batches_v1 WHERE id=p_batch AND business_id=p_business AND site_id=p_site FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'MFG_SCOPE_DENIED'; END IF;
 t:=core10._mfg_scope_v1(p_business,p_site);
 PERFORM core10._mfg_control_fresh_v1(p_business,p_site,'mfg.handoff');
 c:=core10.control_check_v1(p_business,'mfg.handoff',p_site);
 r:=core10._mfg_replay_v1(p_business,p_key,p);
 IF r IS NOT NULL THEN RETURN r; END IF;
 IF p_kind IS NULL OR p_kind NOT IN('ingredients','finished_goods','finance') THEN RAISE EXCEPTION 'MFG_HANDOFF_KIND'; END IF;
 IF (p_kind='ingredients' AND b.status NOT IN('released','recorded')) OR (p_kind<>'ingredients' AND b.status<>'recorded')
  THEN RAISE EXCEPTION 'MFG_BATCH_STATE'; END IF;
 IF (c->>'stages')::int>0 THEN RAISE EXCEPTION 'NOT_CONNECTED:APPROVAL_COMPLETION'; END IF;
 -- A request receipt is not an issue/receipt/financial success. Do not invoke old unported Stock RPCs.
 r:=jsonb_build_object('batch_id',p_batch,'kind',p_kind,'status','NOT_CONNECTED','stock_issued',false,
  'stock_received',false,'financial_posted',false,'reason','Canonical source/lot/reversal adapter pending',
  'source_envelope',core10._mfg_handoff_envelope_v1(p_batch,p_kind));

 RETURN core10._mfg_receipt_v1(t,p_business,p_site,p_key,p,r);
END $$;
