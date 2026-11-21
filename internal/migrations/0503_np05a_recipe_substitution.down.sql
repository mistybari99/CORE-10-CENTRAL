-- No removal of immutable proposal/Audit/Control/source history.
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM core10.bom_substitution_rules_v1)
 OR EXISTS(SELECT 1 FROM core10.control_setting_versions_v1 WHERE feature_key='mfg.recipe_substitution')
 OR EXISTS(SELECT 1 FROM core10.control_overrides_v1 WHERE feature_key='mfg.recipe_substitution')
 OR EXISTS(SELECT 1 FROM core10.mfg_command_receipts_v1 WHERE (response->'source_envelope') ? 'recipe_substitution_rules')
 THEN RAISE EXCEPTION 'MFG_ROLLBACK_HAS_HISTORY'; END IF;
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
CREATE OR REPLACE FUNCTION core10._mfg_handoff_envelope_v1(p_batch bigint,p_kind text) RETURNS jsonb
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
  'material_waste_events',core10._mfg_waste_events_v1(p_batch),
  'lines',lines,'observations',CASE WHEN p_kind='ingredients' THEN NULL ELSE b.output_payload END,
  'planning_cost',CASE WHEN p_kind='finance' THEN jsonb_build_object('estimated_total_cost',b.estimated_total_cost,
   'cost_basis','UNVERIFIED_PLANNING_ESTIMATE','recognized_value',NULL,'journal_entries',NULL) ELSE NULL END,
  'master_uom','NOT_CONNECTED','lot_validation','NOT_CONNECTED','stock_issued',false,
  'stock_received',false,'financial_posted',false);
 RETURN body||jsonb_build_object('source_fingerprint',encode(sha256(convert_to(body::text,'UTF8')),'hex'));
END $$;
DROP FUNCTION core10.mfg_define_substitution_v1(bigint,bigint,bigint,integer,bigint,numeric,text,numeric,numeric,numeric,text,text);
DROP FUNCTION core10.mfg_preview_substitution_v1(bigint,bigint,bigint,numeric,numeric);
DROP FUNCTION core10.mfg_recipe_substitutions_v1(bigint,bigint,bigint);
DROP FUNCTION core10._mfg_substitution_check_v1(bigint);
DROP FUNCTION core10._mfg_substitution_rules_v1(bigint);
DELETE FROM core10.control_rpc_map_v1 WHERE rpc_name='mfg_define_substitution_v1';
DELETE FROM core10.control_catalog_v1 WHERE feature_key='mfg.recipe_substitution';
DROP TABLE core10.bom_substitution_rules_v1;
DROP FUNCTION core10._mfg_substitution_guard_v1();
