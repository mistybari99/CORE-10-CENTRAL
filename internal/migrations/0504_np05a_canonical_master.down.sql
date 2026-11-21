-- 0504 owns no new tables/history. Restore fail-closed hooks; keep recipe/Audit/receipt history.
DROP FUNCTION core10.mfg_preview_substitution_v2(bigint,bigint,bigint,numeric,numeric);
DROP FUNCTION core10.mfg_master_validation_v1(bigint,bigint,bigint,numeric);
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
 UPDATE core10.production_batches_v1 SET status='released',released_by=core10.actor_uid() WHERE id=p_batch;
 r:=jsonb_build_object('batch_id',p_batch,'status','released','stock','NOT_CONNECTED','stock_issued',false);

 RETURN core10._mfg_receipt_v1(t,p_business,p_site,p_key,p,r);
END $$;
CREATE OR REPLACE FUNCTION core10._mfg_master_check_v1(p_recipe bigint) RETURNS void
LANGUAGE plpgsql SET search_path=pg_catalog,core10 AS $$
BEGIN RAISE EXCEPTION 'NOT_CONNECTED:MASTER_UOM'; END $$;
CREATE OR REPLACE FUNCTION core10._mfg_substitution_check_v1(p_recipe bigint) RETURNS void
LANGUAGE plpgsql SET search_path=pg_catalog,core10 AS $$
BEGIN
 IF EXISTS(SELECT 1 FROM core10.bom_substitution_rules_v1 WHERE bom_id=p_recipe)
 THEN RAISE EXCEPTION 'NOT_CONNECTED:MASTER_SUBSTITUTION'; END IF;
END $$;
DROP FUNCTION core10._mfg_master_lock_v1(bigint);
DROP FUNCTION core10._mfg_master_material_v1(bigint,bigint,bigint,text,numeric);
DROP FUNCTION core10._mfg_uom_id_v1(text);
REVOKE ALL ON FUNCTION core10._mfg_master_check_v1(bigint),core10._mfg_substitution_check_v1(bigint) FROM PUBLIC,authenticated;
