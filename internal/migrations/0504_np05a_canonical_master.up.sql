-- B-015 / 0504: bind verified NP02 0151 ports; no Stock/Money adapter.
-- Canonical reference syntax: master:<positive bigint UOM id>. No text/culinary guesses.
CREATE FUNCTION core10._mfg_uom_id_v1(p_ref text) RETURNS bigint
LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog,core10 AS $$
BEGIN
 IF p_ref IS NULL OR p_ref !~ '^master:[1-9][0-9]{0,18}$' THEN
  RAISE EXCEPTION 'NOT_CONNECTED:MASTER_UOM_REFERENCE'; END IF;
 IF substring(p_ref FROM 8)::numeric>9223372036854775807 THEN
  RAISE EXCEPTION 'NOT_CONNECTED:MASTER_UOM_REFERENCE'; END IF;
 RETURN substring(p_ref FROM 8)::bigint;
END $$;

CREATE FUNCTION core10._mfg_master_material_v1(p_business bigint,p_tenant bigint,p_item bigint,p_ref text,p_quantity numeric)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE i core10.items%ROWTYPE; u core10.master_uoms_v1%ROWTYPE; b core10.master_uoms_v1%ROWTYPE;
 cv core10.master_uom_conversions_v1%ROWTYPE; q numeric; uid bigint;
BEGIN
 IF to_regprocedure('core10.master_item_usable_v1(bigint,bigint)') IS NULL
 OR to_regprocedure('core10.master_uom_convert_v1(bigint,bigint,bigint,numeric)') IS NULL
 THEN RAISE EXCEPTION 'NOT_CONNECTED:MASTER_PORT'; END IF;
 IF p_quantity IS NULL OR p_quantity::text IN ('NaN','Infinity','-Infinity') OR p_quantity<0
 THEN RAISE EXCEPTION 'MFG_QUANTITY_PRECISION'; END IF;
 SELECT * INTO i FROM core10.items WHERE id=p_item AND tenant_id=p_tenant AND business_id=p_business;
 IF i.id IS NULL OR core10.master_item_usable_v1(p_business,p_item) IS DISTINCT FROM true OR i.item_kind='service'
 THEN RAISE EXCEPTION 'MFG_MASTER_ITEM_UNUSABLE'; END IF;
 IF i.base_uom_id IS NULL THEN RAISE EXCEPTION 'NOT_CONNECTED:MASTER_ITEM_BASE_UOM'; END IF;
 uid:=core10._mfg_uom_id_v1(p_ref);
 SELECT * INTO u FROM core10.master_uoms_v1 WHERE id=uid AND tenant_id=p_tenant AND business_id=p_business AND active;
 SELECT * INTO b FROM core10.master_uoms_v1 WHERE id=i.base_uom_id AND tenant_id=p_tenant AND business_id=p_business AND active;
 IF u.id IS NULL OR b.id IS NULL THEN RAISE EXCEPTION 'MASTER_UOM_SCOPE'; END IF;
 IF u.dimension<>b.dimension THEN RAISE EXCEPTION 'MASTER_UOM_NO_CONVERSION'; END IF;
 q:=core10.master_uom_convert_v1(p_business,uid,i.base_uom_id,p_quantity);
 IF q IS NULL OR q::text IN ('NaN','Infinity','-Infinity') OR q>100000000
 OR p_quantity<>round(p_quantity,u.decimals) OR q<>round(q,b.decimals)
 THEN RAISE EXCEPTION 'MFG_QUANTITY_PRECISION'; END IF;
 IF uid<>i.base_uom_id THEN
  SELECT * INTO cv FROM core10.master_uom_conversions_v1 WHERE business_id=p_business AND active
   AND from_uom_id=uid AND to_uom_id=i.base_uom_id;
  IF cv.id IS NULL THEN SELECT * INTO cv FROM core10.master_uom_conversions_v1 WHERE business_id=p_business AND active
   AND from_uom_id=i.base_uom_id AND to_uom_id=uid; END IF;
 END IF;
 RETURN jsonb_build_object('item_id',i.id,'item_version',i.version,'uom_id',uid,'uom_code',u.code,'uom_version',u.version,
  'quantity',p_quantity,'base_uom_id',b.id,'base_uom_code',b.code,'base_uom_version',b.version,'base_uom_quantity',q,
  'conversion_id',cv.id,'conversion_version',cv.version,'conversion_factor',cv.factor,
  'conversion_direction',CASE WHEN uid=b.id THEN 'identity' WHEN cv.from_uom_id=uid THEN 'direct' ELSE 'inverse' END,
  'master','VERIFIED_CANONICAL','basis','Current canonical Master versions; not a historical valuation or substitute equivalence');
END $$;

-- Lock only referenced canonical rows, deterministically. Read-only reports use a statement snapshot.
-- State transitions hold SHARE locks through receipt/Audit; recheck Auth/Control after waits.
CREATE FUNCTION core10._mfg_master_lock_v1(p_recipe bigint) RETURNS void
LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog,core10 AS $$
DECLARE ids bigint[]; units bigint[]; biz bigint;
BEGIN
 SELECT business_id INTO biz FROM core10.bom_recipes_v1 WHERE id=p_recipe;
 SELECT array_agg(item_id ORDER BY item_id) INTO ids FROM (
 SELECT finished_item_id AS item_id FROM core10.bom_recipes_v1 WHERE id=p_recipe
 UNION SELECT ingredient_item_id FROM core10.bom_ingredients_v1 WHERE bom_id=p_recipe
 UNION SELECT alternative_item_id FROM core10.bom_substitution_rules_v1 WHERE bom_id=p_recipe) q;
 PERFORM id FROM core10.items WHERE business_id=biz AND id=ANY(ids) ORDER BY id FOR SHARE;
 SELECT array_agg(id ORDER BY id) INTO units FROM (
 SELECT base_uom_id AS id FROM core10.items WHERE business_id=biz AND id=ANY(ids)
 UNION SELECT core10._mfg_uom_id_v1(yield_uom_ref) FROM core10.bom_recipes_v1 WHERE id=p_recipe
 UNION SELECT core10._mfg_uom_id_v1(uom_ref) FROM core10.bom_ingredients_v1 WHERE bom_id=p_recipe
 UNION SELECT core10._mfg_uom_id_v1(uom_ref) FROM core10.bom_substitution_rules_v1 WHERE bom_id=p_recipe) q;
 PERFORM id FROM core10.master_uoms_v1 WHERE business_id=biz AND id=ANY(units) ORDER BY id FOR SHARE;
 PERFORM id FROM core10.master_uom_conversions_v1 WHERE business_id=biz
  AND from_uom_id=ANY(units) AND to_uom_id=ANY(units) ORDER BY id FOR SHARE;
END $$;

CREATE OR REPLACE FUNCTION core10._mfg_master_check_v1(p_recipe bigint) RETURNS void
LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog,core10 AS $$
DECLARE b core10.bom_recipes_v1%ROWTYPE; l record;
BEGIN
 SELECT * INTO b FROM core10.bom_recipes_v1 WHERE id=p_recipe;
 IF b.id IS NULL THEN RAISE EXCEPTION 'MFG_SCOPE_DENIED'; END IF;
 PERFORM core10._mfg_scope_v1(b.business_id,b.site_id);
 PERFORM core10._mfg_master_lock_v1(p_recipe);
 PERFORM core10._mfg_master_material_v1(b.business_id,b.tenant_id,b.finished_item_id,b.yield_uom_ref,b.yield_quantity);
 FOR l IN SELECT * FROM core10.bom_ingredients_v1 WHERE bom_id=p_recipe ORDER BY line_no LOOP
  PERFORM core10._mfg_master_material_v1(b.business_id,b.tenant_id,l.ingredient_item_id,l.uom_ref,l.qty_per_batch);
 END LOOP;
END $$;
CREATE OR REPLACE FUNCTION core10._mfg_substitution_check_v1(p_recipe bigint) RETURNS void
LANGUAGE plpgsql VOLATILE SET search_path=pg_catalog,core10 AS $$
DECLARE b core10.bom_recipes_v1%ROWTYPE; s record;
BEGIN
 SELECT * INTO b FROM core10.bom_recipes_v1 WHERE id=p_recipe;
 IF b.id IS NULL THEN RAISE EXCEPTION 'MFG_SCOPE_DENIED'; END IF;
 PERFORM core10._mfg_scope_v1(b.business_id,b.site_id);
 FOR s IN SELECT * FROM core10.bom_substitution_rules_v1 WHERE bom_id=p_recipe ORDER BY id LOOP
  BEGIN
   PERFORM core10._mfg_master_material_v1(b.business_id,b.tenant_id,s.alternative_item_id,s.uom_ref,s.alternative_qty_per_batch);
  EXCEPTION WHEN raise_exception THEN
   IF SQLERRM LIKE 'NOT_CONNECTED:MASTER_UOM_REFERENCE%' THEN RAISE EXCEPTION 'NOT_CONNECTED:MASTER_SUBSTITUTION_UOM_REFERENCE'; END IF;
   RAISE;
  END;
 END LOOP;
END $$;

CREATE FUNCTION core10.mfg_master_validation_v1(p_business bigint,p_site bigint,p_recipe bigint,p_multiplier numeric)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE t bigint; b core10.bom_recipes_v1%ROWTYPE; c jsonb; l record; s record; lines jsonb:='[]'; alternatives jsonb:='[]'; output jsonb;
BEGIN
 t:=core10._mfg_scope_v1(p_business,p_site);
 c:=core10._control_resolve_v1(p_business,'mfg.material_requirements',p_site);
 IF NOT (c->>'enabled')::boolean THEN RAISE EXCEPTION 'CONTROL_DISABLED:mfg.material_requirements'; END IF;
 SELECT * INTO b FROM core10.bom_recipes_v1 WHERE id=p_recipe AND tenant_id=t AND business_id=p_business AND site_id=p_site;
 IF b.id IS NULL THEN RAISE EXCEPTION 'MFG_SCOPE_DENIED'; END IF;
 IF p_multiplier IS NULL OR p_multiplier<=0 OR p_multiplier>100000 OR p_multiplier<>round(p_multiplier,6)
 THEN RAISE EXCEPTION 'MFG_INVALID_MULTIPLIER'; END IF;
 output:=core10._mfg_master_material_v1(p_business,t,b.finished_item_id,b.yield_uom_ref,b.yield_quantity*p_multiplier);
 FOR l IN SELECT * FROM core10.bom_ingredients_v1 WHERE bom_id=p_recipe ORDER BY line_no LOOP
  lines:=lines||jsonb_build_array(core10._mfg_master_material_v1(p_business,t,l.ingredient_item_id,l.uom_ref,l.qty_per_batch*p_multiplier)
   ||jsonb_build_object('line_no',l.line_no));
 END LOOP;
 IF EXISTS(SELECT 1 FROM core10.bom_substitution_rules_v1 WHERE bom_id=p_recipe) THEN
  c:=core10._control_resolve_v1(p_business,'mfg.recipe_substitution',p_site);
  IF NOT (c->>'enabled')::boolean THEN RAISE EXCEPTION 'CONTROL_DISABLED:mfg.recipe_substitution'; END IF;
 END IF;
 FOR s IN SELECT * FROM core10.bom_substitution_rules_v1 WHERE bom_id=p_recipe ORDER BY id LOOP
  alternatives:=alternatives||jsonb_build_array(core10._mfg_master_material_v1(p_business,t,s.alternative_item_id,s.uom_ref,s.alternative_qty_per_batch*p_multiplier)
   ||jsonb_build_object('rule_id',s.id,'line_no',s.line_no,'quantity_basis','Declared full replacement; not equivalence'));
 END LOOP;
 RETURN jsonb_build_object('recipe_id',b.id,'recipe_version',b.version,'master','VERIFIED_CANONICAL',
  'validation_basis','Current Master versions at statement snapshot','output',output,'lines',lines,'alternatives',alternatives,
  'planning_only',true,'stock','NOT_CONNECTED','money','NOT_CONNECTED','approval_completion','NOT_CONNECTED',
  'stock_issued',false,'financial_posted',false,'substitution_selected',false);
END $$;
CREATE FUNCTION core10.mfg_preview_substitution_v2(p_business bigint,p_site bigint,p_rule bigint,p_multiplier numeric,p_replacement_pct numeric)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE p jsonb; evidence jsonb; t bigint;
BEGIN
 t:=core10._mfg_scope_v1(p_business,p_site);
 p:=core10.mfg_preview_substitution_v1(p_business,p_site,p_rule,p_multiplier,p_replacement_pct);
 evidence:=core10.mfg_master_validation_v1(p_business,p_site,(p->>'recipe_id')::bigint,p_multiplier);
 RETURN p||jsonb_build_object('master','VERIFIED_CANONICAL','master_validation',evidence,
  'original_master',core10._mfg_master_material_v1(p_business,t,(p->'original_component'->>'item_id')::bigint,
   p->'original_component'->>'uom_ref',(p->'original_component'->>'remaining_quantity')::numeric),
  'alternative_master',core10._mfg_master_material_v1(p_business,t,(p->'alternative_component'->>'item_id')::bigint,
   p->'alternative_component'->>'uom_ref',(p->'alternative_component'->>'quantity')::numeric),
  'stock','NOT_CONNECTED','money','NOT_CONNECTED','approval_completion','NOT_CONNECTED');
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
 IF (c->'params'->>'maker_checker')::boolean AND EXISTS(SELECT 1 FROM core10.bom_substitution_rules_v1
  WHERE bom_id=p_recipe AND created_by=core10.actor_uid()) THEN RAISE EXCEPTION 'MFG_MAKER_CHECKER'; END IF;
 IF (c->>'stages')::int>0 THEN RAISE EXCEPTION 'NOT_CONNECTED:APPROVAL_COMPLETION'; END IF;
 IF p_effective IS NULL THEN RAISE EXCEPTION 'MFG_EFFECTIVE_REQUIRED'; END IF;
 PERFORM core10._mfg_master_check_v1(p_recipe);
 PERFORM core10._mfg_substitution_check_v1(p_recipe);
 t:=core10._mfg_scope_v1(p_business,p_site);
 PERFORM core10._mfg_control_fresh_v1(p_business,p_site,'mfg.recipe_approve');
 UPDATE core10.bom_recipes_v1 SET status='approved',approved_by=core10.actor_uid(),effective_from=p_effective WHERE id=p_recipe;
 r:=jsonb_build_object('recipe_id',p_recipe,'status','approved','effective_from',p_effective);

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
 t:=core10._mfg_scope_v1(p_business,p_site);
 PERFORM core10._mfg_control_fresh_v1(p_business,p_site,'mfg.batch_release');
 UPDATE core10.production_batches_v1 SET status='released',released_by=core10.actor_uid() WHERE id=p_batch;
 r:=jsonb_build_object('batch_id',p_batch,'status','released','stock','NOT_CONNECTED','stock_issued',false);

 RETURN core10._mfg_receipt_v1(t,p_business,p_site,p_key,p,r);
END $$;

REVOKE ALL ON FUNCTION core10._mfg_uom_id_v1(text) FROM PUBLIC,authenticated;
REVOKE ALL ON FUNCTION core10._mfg_master_material_v1(bigint,bigint,bigint,text,numeric) FROM PUBLIC,authenticated;
REVOKE ALL ON FUNCTION core10._mfg_master_lock_v1(bigint) FROM PUBLIC,authenticated;
REVOKE ALL ON FUNCTION core10._mfg_master_check_v1(bigint) FROM PUBLIC,authenticated;
REVOKE ALL ON FUNCTION core10._mfg_substitution_check_v1(bigint) FROM PUBLIC,authenticated;
REVOKE ALL ON FUNCTION core10.mfg_master_validation_v1(bigint,bigint,bigint,numeric) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION core10.mfg_master_validation_v1(bigint,bigint,bigint,numeric) TO authenticated;
REVOKE ALL ON FUNCTION core10.mfg_preview_substitution_v2(bigint,bigint,bigint,numeric,numeric) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION core10.mfg_preview_substitution_v2(bigint,bigint,bigint,numeric,numeric) TO authenticated;
