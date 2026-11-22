\set ON_ERROR_STOP on
BEGIN;
\ir seed.sql
CREATE SCHEMA mfg_test;
GRANT USAGE ON SCHEMA mfg_test TO authenticated;
CREATE FUNCTION mfg_test.as_user(p text) RETURNS void LANGUAGE sql AS $$
 SELECT set_config('request.jwt.claims',jsonb_build_object('sub',p)::text,true), set_config('request.jwt.claim.sub','',true) $$;
CREATE FUNCTION mfg_test.ok(p boolean,msg text) RETURNS void LANGUAGE plpgsql AS $$
 BEGIN IF p IS NOT TRUE THEN RAISE EXCEPTION 'ASSERT_FAILED:%',msg; END IF; END $$;
CREATE FUNCTION mfg_test.expect(q text,e text) RETURNS void LANGUAGE plpgsql AS $$
 BEGIN
  BEGIN EXECUTE q; EXCEPTION WHEN OTHERS THEN
   IF SQLERRM LIKE e||'%' THEN RETURN; END IF; RAISE EXCEPTION 'WRONG_ERROR expected % got %',e,SQLERRM;
  END; RAISE EXCEPTION 'MISSING_ERROR:%',e;
 END $$;
CREATE FUNCTION mfg_test.lines() RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$ SELECT
 '[{"item":9542,"qty":10,"uom_ref":"fixture:kg","kind":"ingredient","waste_pct":2,"estimated_unit_cost":80},
 {"item":9543,"qty":2,"uom_ref":"fixture:kg","kind":"ingredient","waste_pct":1,"estimated_unit_cost":100},
 {"item":9544,"qty":10,"uom_ref":"fixture:piece","kind":"packaging","waste_pct":0,"estimated_unit_cost":5}]'::jsonb $$;
CREATE FUNCTION mfg_test.output() RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$ SELECT
 '{"good":95,"rejected":2,"rework":1,"loss":2,"reason":"PROCESS_LOSS","lot_ref":"FICTIONAL-SANDESH-001",
 "consumption":[{"line":1,"qty":10.5,"lot_ref":"FICTIONAL-MILK"},{"line":2,"qty":2,"lot_ref":"FICTIONAL-SUGAR"},
 {"line":3,"qty":10,"lot_ref":"FICTIONAL-BOX"}]}'::jsonb $$;
CREATE SEQUENCE mfg_test.keys;
CREATE FUNCTION mfg_test.cset(f text,onoff boolean,stages int,params jsonb DEFAULT '{}') RETURNS void LANGUAGE sql AS $$
 SELECT core10.control_set_v1(9511,NULL,f,onoff,stages::smallint,params,NULL,false,
 coalesce((SELECT (x->>'version')::int FROM jsonb_array_elements(core10.control_read_v1(9511)) x WHERE x->>'feature_key'=f),0),
 'Synthetic manufacturing test', 'mfg_ctl_'||nextval('mfg_test.keys')::text) $$;
-- cset reads closed version storage: use a test-only definer owned by disposable postgres.
ALTER FUNCTION mfg_test.cset(text,boolean,int,jsonb) SECURITY DEFINER;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA mfg_test TO authenticated;
SET LOCAL ROLE authenticated;
SELECT mfg_test.as_user('95111111-1111-4111-8111-111111111111');
SELECT core10.mfg_create_recipe_v1(9511,9521,9541,'SANDESH',100,'fixture:piece',mfg_test.lines(),50,'recipe_0001') AS recipe \gset
SELECT (:'recipe'::jsonb->>'recipe_id')::bigint AS recipe_id \gset
SELECT mfg_test.ok((core10.mfg_create_recipe_v1(9511,9521,9541,'SANDESH',100,'fixture:piece',mfg_test.lines(),50,'recipe_0001')->>'replayed')::boolean,'exact replay');
SELECT mfg_test.expect($q$SELECT core10.mfg_create_recipe_v1(9511,9521,9541,'OTHER',100,'fixture:piece',mfg_test.lines(),50,'recipe_0001')$q$,'MFG_REPLAY_CONFLICT');
SELECT mfg_test.expect(format('SELECT core10.mfg_approve_recipe_v1(9511,9521,%s,now(),%L)',:recipe_id,'approve_maker'),'MFG_MAKER_CHECKER');
SELECT mfg_test.as_user('95222222-2222-4222-8222-222222222222');
SELECT mfg_test.expect(format('SELECT core10.mfg_approve_recipe_v1(9511,9521,%s,now(),%L)',:recipe_id,'approve_stages'),'NOT_CONNECTED:APPROVAL_COMPLETION');
SELECT mfg_test.cset('mfg.recipe_approve',true,0);
SELECT mfg_test.expect(format('SELECT core10.mfg_approve_recipe_v1(9511,9521,%s,now(),%L)',:recipe_id,'approve_master'),'NOT_CONNECTED:MASTER_UOM');
SELECT mfg_test.ok((core10.mfg_inspect_v1(9511,9521)->'recipes'->0->>'status')='draft','failed approval is atomic');
-- Production adapter remains fail closed above. The remaining lifecycle is explicitly isolated domain proof.
RESET ROLE;
\ir master-fixture.sql
SET LOCAL ROLE authenticated;
SELECT core10.mfg_approve_recipe_v1(9511,9521,:recipe_id,now(),'approve_real_01');
SELECT mfg_test.as_user('95111111-1111-4111-8111-111111111111');
SELECT core10.mfg_plan_batch_v1(9511,9521,:recipe_id,9531,1,'batch_plan_01') AS batch \gset
SELECT (:'batch'::jsonb->>'batch_id')::bigint AS batch_id \gset
SELECT mfg_test.ok((:'batch'::jsonb->>'estimated_total_cost')::numeric=1100,'A027 non-posting cost math');
SELECT mfg_test.expect(format('SELECT core10.mfg_release_batch_v1(9511,9521,%s,%L)',:batch_id,'release_maker'),'MFG_MAKER_CHECKER');
SELECT mfg_test.as_user('95222222-2222-4222-8222-222222222222');
SELECT mfg_test.expect(format('SELECT core10.mfg_release_batch_v1(9511,9521,%s,%L)',:batch_id,'release_stage'),'NOT_CONNECTED:APPROVAL_COMPLETION');
SELECT mfg_test.cset('mfg.batch_release',true,0);
SELECT core10.mfg_release_batch_v1(9511,9521,:batch_id,'release_0001');
SELECT mfg_test.ok(core10.mfg_request_handoff_v1(9511,9521,:batch_id,'ingredients','issue_req_01')->>'status'='NOT_CONNECTED','Stock handoff fails closed');
SELECT mfg_test.expect(format('SELECT core10.mfg_record_output_v1(9511,9521,%s,%L::jsonb,%L)',:batch_id,
 jsonb_set(mfg_test.output(),'{good}','94'),'output_bad_01'),'MFG_YIELD_RECONCILIATION');
SELECT mfg_test.expect(format('SELECT core10.mfg_record_output_v1(9511,9521,%s,%L::jsonb,%L)',:batch_id,
 jsonb_set(mfg_test.output(),'{reason}','"unknown"'),'output_bad_02'),'MFG_WASTE_REASON');
SELECT mfg_test.expect(format('SELECT core10.mfg_record_output_v1(9511,9521,%s,%L::jsonb,%L)',:batch_id,
 jsonb_set(mfg_test.output(),'{consumption,0,qty}','100'),'output_bad_03'),'CONTROL_LIMIT:max_consumption_variance_pct');
SELECT mfg_test.cset('mfg.output',true,0,'{"max_loss_pct":1}');
SELECT mfg_test.expect(format('SELECT core10.mfg_record_output_v1(9511,9521,%s,mfg_test.output(),%L)',:batch_id,'output_bad_04'),'CONTROL_LIMIT:max_loss_pct');
SELECT mfg_test.cset('mfg.output',true,0);
SELECT core10.mfg_record_output_v1(9511,9521,:batch_id,mfg_test.output(),'output_0001');
SELECT mfg_test.ok((core10.mfg_record_output_v1(9511,9521,:batch_id,mfg_test.output(),'output_0001')->>'replayed')::boolean,'record exactly once');
SELECT mfg_test.ok(core10.mfg_request_handoff_v1(9511,9521,:batch_id,'finished_goods','receive_req_01')->>'status'='NOT_CONNECTED','No fake receipt');
SELECT mfg_test.ok(core10.mfg_request_handoff_v1(9511,9521,:batch_id,'finance','finance_req_01')->>'status'='NOT_CONNECTED','No fake finance');
SELECT mfg_test.ok((core10.mfg_inspect_v1(9511,9521)->'batches'->0->>'yield_pct')::numeric=95,'95 percent output yield');
SELECT mfg_test.ok((core10.mfg_inspect_v1(9511,9521)->'batches'->0->>'planning_cost_variance')::numeric=40,'planning variance 40 BDT example');
SELECT mfg_test.expect(format('SELECT core10.mfg_cancel_batch_v1(9511,9521,%s,%L,%L)',:batch_id,'Do not erase history','cancel_bad_01'),'NOT_CONNECTED:CONTROLLED_REVERSAL');
-- Version history: new drafts do not overwrite v1, future approvals are not effective yet.
SELECT mfg_test.as_user('95111111-1111-4111-8111-111111111111');
SELECT core10.mfg_create_recipe_v1(9511,9521,9541,'SANDESH',100,'fixture:piece',mfg_test.lines(),50,'recipe_0002') AS v2 \gset
SELECT (:'v2'::jsonb->>'recipe_id')::bigint AS v2_id \gset
SELECT mfg_test.ok((:'v2'::jsonb->>'version')::int=2,'version increments, historical recipe retained');
SELECT mfg_test.as_user('95222222-2222-4222-8222-222222222222');
SELECT core10.mfg_approve_recipe_v1(9511,9521,:v2_id,now()+interval '1 day','approve_future');
SELECT mfg_test.expect(format('SELECT core10.mfg_plan_batch_v1(9511,9521,%s,9531,1,%L)',:v2_id,'plan_future_1'),'MFG_RECIPE_NOT_EFFECTIVE');
SELECT core10.mfg_plan_batch_v1(9511,9521,:recipe_id,9531,1,'plan_cancel_01') AS cancellable \gset
SELECT core10.mfg_cancel_batch_v1(9511,9521,(:'cancellable'::jsonb->>'batch_id')::bigint,'Synthetic cancelled plan','cancel_safe_01');
SELECT mfg_test.expect(format('SELECT core10.mfg_plan_batch_v1(9511,9521,%s,9531,0.0000001,%L)',:recipe_id,'plan_precision'),'MFG_INVALID_MULTIPLIER');
SELECT mfg_test.expect(format('SELECT core10.mfg_plan_batch_v1(9511,9521,%s,9532,1,%L)',:recipe_id,'plan_foreign_l'),'MFG_LOCATION_SCOPE');
-- Control-off proof for EACH registered RPC, checked after Auth and before replay or state checks.
SELECT mfg_test.cset('mfg.recipe',false,0);
SELECT mfg_test.expect($q$SELECT core10.mfg_create_recipe_v1(9511,9521,9541,'SANDESH',100,'fixture:piece',mfg_test.lines(),50,'recipe_0001')$q$,'CONTROL_DISABLED');
SELECT mfg_test.cset('mfg.recipe',true,0);
SELECT mfg_test.cset('mfg.recipe_approve',false,0);
SELECT mfg_test.expect(format('SELECT core10.mfg_approve_recipe_v1(9511,9521,%s,now(),%L)',:recipe_id,'disabled_appr'),'CONTROL_DISABLED');
SELECT mfg_test.cset('mfg.recipe_approve',true,0);
SELECT mfg_test.cset('mfg.batch',false,0);
SELECT mfg_test.expect(format('SELECT core10.mfg_plan_batch_v1(9511,9521,%s,9531,1,%L)',:recipe_id,'disabled_plan'),'CONTROL_DISABLED');
SELECT mfg_test.expect(format('SELECT core10.mfg_cancel_batch_v1(9511,9521,%s,%L,%L)',:batch_id,'Disabled test','disabled_canc'),'CONTROL_DISABLED');
SELECT mfg_test.cset('mfg.batch',true,0);
SELECT mfg_test.cset('mfg.batch_release',false,0);
SELECT mfg_test.expect(format('SELECT core10.mfg_release_batch_v1(9511,9521,%s,%L)',:batch_id,'disabled_rel'),'CONTROL_DISABLED');
SELECT mfg_test.cset('mfg.output',false,0);
SELECT mfg_test.expect(format('SELECT core10.mfg_record_output_v1(9511,9521,%s,mfg_test.output(),%L)',:batch_id,'output_0001'),'CONTROL_DISABLED');
SELECT mfg_test.cset('mfg.handoff',false,0);
SELECT mfg_test.expect(format('SELECT core10.mfg_request_handoff_v1(9511,9521,%s,%L,%L)',:batch_id,'finance','finance_req_01'),'CONTROL_DISABLED');
-- Wrong site/business/item, precision and direct DML.
SELECT mfg_test.expect($q$SELECT core10.mfg_create_recipe_v1(9511,9521,9545,'FOREIGN',100,'fixture:piece',mfg_test.lines(),50,'foreign_item')$q$,'MFG_ITEM_SCOPE');
SELECT mfg_test.expect($q$SELECT core10.mfg_create_recipe_v1(9511,9521,9541,'BAD',0.0000001,'fixture:piece',mfg_test.lines(),50,'precise_bad_1')$q$,'MFG_INVALID_RECIPE');
SELECT mfg_test.expect($q$UPDATE core10.production_batches_v1 SET status='recorded'$q$,'permission denied');
SELECT mfg_test.expect($q$SELECT core10._mfg_master_check_v1(1)$q$,'permission denied');
SELECT mfg_test.ok((core10.verify_canonical_audit_v1(9511)->>'ok')::boolean,'canonical audit chain');
RESET ROLE;
SELECT mfg_test.expect(format('UPDATE core10.bom_recipes_v1 SET yield_quantity=101 WHERE id=%s',:recipe_id),'MFG_RECIPE_IMMUTABLE');
SELECT mfg_test.expect(format('DELETE FROM core10.bom_ingredients_v1 WHERE bom_id=%s',:recipe_id),'MFG_RECIPE_IMMUTABLE');
SELECT mfg_test.ok((SELECT count(*) FROM core10.stock_movements WHERE business_id=9511)=0,'No direct stock changes');
SELECT mfg_test.ok(NOT EXISTS(SELECT 1 FROM core10.mfg_command_receipts_v1 r LEFT JOIN core10.canonical_audit_events_v1 a ON a.id=r.audit_event_id
 WHERE a.id IS NULL OR a.actor_id<>r.actor_id),'every receipt has canonical evidence');
SET LOCAL ROLE authenticated;
DO $$ DECLARE u text; BEGIN
 FOREACH u IN ARRAY ARRAY['95333333-3333-4333-8333-333333333333','95444444-4444-4444-8444-444444444444',
 '95555555-5555-4555-8555-555555555555','95666666-6666-4666-8666-666666666666','95777777-7777-4777-8777-777777777777',
 '95888888-8888-4888-8888-888888888888','95999999-9999-4999-8999-999999999999'] LOOP
  PERFORM mfg_test.as_user(u);
  PERFORM mfg_test.expect('SELECT core10.mfg_inspect_v1(9511,9521)','MFG_SCOPE_DENIED');
  PERFORM mfg_test.expect($q$SELECT core10.mfg_create_recipe_v1(9511,9521,9541,'DENIED',100,'fixture:piece',mfg_test.lines(),50,'denied_0001')$q$,'MFG_SCOPE_DENIED');
 END LOOP;
END $$;
SELECT mfg_test.as_user('95111111-1111-4111-8111-111111111111');
SELECT mfg_test.expect('SELECT core10.mfg_inspect_v1(9511,9524)','MFG_SCOPE_DENIED');
SELECT mfg_test.expect('SELECT core10.mfg_inspect_v1(9513,9523)','MFG_SCOPE_DENIED');
SELECT mfg_test.expect('SELECT core10.mfg_inspect_v1(9511,9522)','MFG_SCOPE_DENIED');
RESET ROLE;
\echo NP05A_DOMAIN_AND_NEGATIVES_OK
ROLLBACK;
