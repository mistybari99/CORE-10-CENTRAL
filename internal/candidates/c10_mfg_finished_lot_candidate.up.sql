-- T01.04 candidate. Stock is posted later by the existing Inventory lifecycle.
ALTER TABLE core10.inventory_lots_v1 DROP CONSTRAINT inventory_lots_v1_source_kind_check;
ALTER TABLE core10.inventory_lots_v1 ADD CONSTRAINT inventory_lots_v1_source_kind_check
 CHECK (source_kind IN ('purchase','manufacturing'));
INSERT INTO core10.control_catalog_v1
 (feature_key,title_en,title_bn,pack,default_enabled,default_stages,max_stages,
 allow_site_scope,approval_domain,approval_action,params)
VALUES ('mfg.finished_lot_prepare','Prepare a finished production lot receipt',
 'উৎপাদিত পণ্যের লট গ্রহণের খসড়া','NP05A',false,0,0,true,NULL,NULL,'{}');

CREATE FUNCTION core10.mfg_prepare_finished_lot_v1(
 p_business bigint,p_site bigint,p_batch bigint,p_issues jsonb,p_expiry date,p_key text
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE
 tenant bigint;
 batch core10.production_batches_v1%ROWTYPE;
 recipe core10.bom_recipes_v1%ROWTYPE;
 issue core10.inventory_commands_v1%ROWTYPE;
 ingredient core10.bom_ingredients_v1%ROWTYPE;
 material jsonb;
 observation jsonb;
 intent jsonb;
 response jsonb;
 receipt jsonb;
 parents bigint[] := '{}';
 parent bigint;
 line_no integer;
 input_id text;
 output_lot_code text;
 finished_lot bigint;
 good_quantity numeric;
 expected_quantity numeric;
 stock_key text;
BEGIN
 tenant:=core10._mfg_scope_v1(p_business,p_site);
 PERFORM core10.control_check_v1(p_business,'mfg.finished_lot_prepare',p_site);
 IF jsonb_typeof(p_issues) IS DISTINCT FROM 'object' OR p_expiry IS NULL OR NOT isfinite(p_expiry)
 THEN RAISE EXCEPTION 'MFG_FINISHED_LOT_INPUT'; END IF;

 -- Same lock order as Manufacturing output: request, then scoped batch.
 intent:=jsonb_build_object('op','finished_lot_prepare','site',p_site,'batch',p_batch,
  'issues',p_issues,'expiry',p_expiry);
 response:=core10._mfg_replay_v1(p_business,p_key,intent);
 IF response IS NOT NULL THEN RETURN response; END IF;
 SELECT * INTO batch FROM core10.production_batches_v1
 WHERE id=p_batch AND tenant_id=tenant AND business_id=p_business AND site_id=p_site FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'MFG_SCOPE_DENIED'; END IF;
 PERFORM core10._mfg_scope_v1(p_business,p_site);
 PERFORM core10.control_check_v1(p_business,'mfg.finished_lot_prepare',p_site);

 IF batch.status<>'recorded' OR p_expiry<current_date
 THEN RAISE EXCEPTION 'MFG_FINISHED_LOT_STATE'; END IF;
 IF EXISTS (SELECT 1 FROM core10.mfg_command_receipts_v1 r
  WHERE r.business_id=p_business AND r.site_id=p_site AND r.payload->>'op'='finished_lot_prepare'
  AND r.payload->>'batch'=p_batch::text)
 THEN RAISE EXCEPTION 'MFG_FINISHED_LOT_ALREADY_PREPARED'; END IF;

 SELECT * INTO STRICT recipe FROM core10.bom_recipes_v1 WHERE id=batch.bom_id;
 PERFORM core10._mfg_master_lock_v1(recipe.id);
 output_lot_code:=batch.output_payload->>'lot_ref';
 IF output_lot_code IS NULL OR output_lot_code !~ '^[A-Za-z0-9][A-Za-z0-9/_.-]{1,59}$'
 THEN RAISE EXCEPTION 'MFG_FINISHED_LOT_CODE'; END IF;
 material:=core10._mfg_master_material_v1(p_business,tenant,recipe.finished_item_id,recipe.yield_uom_ref,
  (batch.output_payload->>'good')::numeric);
 good_quantity:=(material->>'base_uom_quantity')::numeric;
 IF good_quantity<=0 OR good_quantity<>round(good_quantity,3)
 THEN RAISE EXCEPTION 'MFG_FINISHED_LOT_QUANTITY'; END IF;

 IF (SELECT count(*) FROM jsonb_object_keys(p_issues))<>
    jsonb_array_length(batch.output_payload->'consumption')
 THEN RAISE EXCEPTION 'MFG_FINISHED_LOT_INPUT'; END IF;
 FOR observation IN SELECT value FROM jsonb_array_elements(batch.output_payload->'consumption') LOOP
  line_no:=(observation->>'line')::integer;
  input_id:=p_issues->>line_no::text;
  IF input_id IS NULL OR input_id !~ '^[1-9][0-9]{0,17}$'
  THEN RAISE EXCEPTION 'MFG_FINISHED_LOT_INPUT'; END IF;
  SELECT * INTO STRICT ingredient FROM core10.bom_ingredients_v1 l
   WHERE l.bom_id=recipe.id AND l.line_no=(observation->>'line')::int;
  material:=core10._mfg_master_material_v1(p_business,tenant,ingredient.ingredient_item_id,ingredient.uom_ref,
   (observation->>'qty')::numeric);
  expected_quantity:=(material->>'base_uom_quantity')::numeric;
  SELECT * INTO issue FROM core10.inventory_commands_v1 c
   WHERE c.id=input_id::bigint AND c.kind='issue' AND c.status='posted'
    AND c.tenant_id=tenant AND c.business_id=p_business AND c.source_site_id=p_site
    AND c.source_location=batch.location_id AND c.item_id=ingredient.ingredient_item_id
    AND c.reason='Manufacturing batch '||p_batch||' line '||line_no AND c.quantity=expected_quantity;
  IF NOT FOUND OR NOT EXISTS (
   SELECT 1 FROM core10.stock_movement_lots_v1 m
   JOIN core10.inventory_lots_v1 l ON l.id=m.lot_id AND l.business_id=m.business_id
   WHERE m.movement_id=issue.stock_ref AND m.business_id=p_business AND m.location_id=batch.location_id
    AND m.lot_id=issue.lot_id AND m.item_id=issue.item_id AND m.quantity=-expected_quantity
    AND l.lot_code=observation->>'lot_ref'
  ) THEN RAISE EXCEPTION 'MFG_FINISHED_LOT_ISSUE_MISMATCH'; END IF;
  parents:=array_append(parents,issue.lot_id);
 END LOOP;

 INSERT INTO core10.inventory_lots_v1
  (tenant_id,business_id,item_id,lot_code,expires_on,source_kind,source_ref,created_by)
 VALUES (tenant,p_business,recipe.finished_item_id,output_lot_code,p_expiry,'manufacturing',
  'batch:'||p_batch,core10.actor_uid())
 ON CONFLICT (business_id,item_id,lot_code) DO NOTHING RETURNING id INTO finished_lot;
 IF finished_lot IS NULL THEN RAISE EXCEPTION 'MFG_FINISHED_LOT_EXISTS'; END IF;
 FOR parent IN SELECT DISTINCT unnest(parents) ORDER BY 1 LOOP
  PERFORM core10.inventory_lot_link_v1(parent,finished_lot,'mfg-link-'||finished_lot||'-'||parent);
 END LOOP;

 stock_key:='mfg-finished-lot-'||p_batch;
 receipt:=core10.inventory_create_lot_command_v1(p_business,'receive',NULL,batch.location_id,
  recipe.finished_item_id,good_quantity,finished_lot,'Manufacturing batch '||p_batch,stock_key);
 -- Existing command key collision must roll back the new lot and genealogy.
 IF receipt->>'status'<>'draft' OR (receipt->>'replayed')::boolean
 THEN RAISE EXCEPTION 'MFG_FINISHED_LOT_COMMAND_CONFLICT'; END IF;
 RETURN core10._mfg_receipt_v1(tenant,p_business,p_site,p_key,intent,
   jsonb_build_object('batch_id',p_batch,'recipe_id',recipe.id,'recipe_version',recipe.version,
    'lot_id',finished_lot,'inventory_command_id',receipt->'command_id','base_quantity',good_quantity,
    'status','draft','stock_received',false,'financial_posted',false));
END $$;
REVOKE ALL ON FUNCTION core10.mfg_prepare_finished_lot_v1(bigint,bigint,bigint,jsonb,date,text)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION core10.mfg_prepare_finished_lot_v1(bigint,bigint,bigint,jsonb,date,text)
 TO authenticated;
INSERT INTO core10.control_rpc_map_v1 (rpc_name,status,feature_key,reason,lane,board_row,test_ref)
VALUES ('mfg_prepare_finished_lot_v1','enforced','mfg.finished_lot_prepare',
 'Check scoped manufacturing control and create a Stock draft only after validating all prior lot issues',
 'Codex','B-015','tests/np05a/finished-lot-candidate-e2e.sql');
