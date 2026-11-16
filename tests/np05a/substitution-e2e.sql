\set ON_ERROR_STOP on
BEGIN;
\ir seed.sql
INSERT INTO core10.items(id,tenant_id,business_id,sku) VALUES(9546,951,9511,'QA-MILK-POWDER'),(9547,951,9511,'QA-BOX-ALT');
-- Independent synthetic reviewer: neither original-recipe maker nor rule maker.
INSERT INTO core10.business_members(tenant_id,business_id,user_id,role) VALUES(951,9511,'95aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','business_owner');
CREATE SCHEMA mfg_sub_test;
GRANT USAGE ON SCHEMA mfg_sub_test TO authenticated;
CREATE FUNCTION mfg_sub_test.ok(p boolean,msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p IS NOT TRUE THEN RAISE EXCEPTION 'ASSERT_FAILED:%',msg; END IF; END $$;
CREATE FUNCTION mfg_sub_test.expect(q text,e text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN BEGIN EXECUTE q; EXCEPTION WHEN OTHERS THEN
 IF SQLERRM LIKE e||'%' THEN RETURN; END IF; RAISE EXCEPTION 'WRONG_ERROR expected % got %',e,SQLERRM;
END; RAISE EXCEPTION 'MISSING_ERROR:%',e; END $$;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA mfg_sub_test TO authenticated;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims','{"sub":"95111111-1111-4111-8111-111111111111"}',true);
SELECT core10.mfg_create_recipe_v1(9511,9521,9541,'SUBSTITUTION',100,'fixture:piece',
 '[{"item":9542,"qty":10,"uom_ref":"fixture:kg","kind":"ingredient","waste_pct":2,"estimated_unit_cost":80},
 {"item":9544,"qty":10,"uom_ref":"fixture:piece","kind":"packaging","waste_pct":0,"estimated_unit_cost":5}]',50,'sub_recipe_01') AS recipe \gset
SELECT (:'recipe'::jsonb->>'recipe_id')::bigint AS recipe_id \gset
-- Real draft authoring and planning: no test Master adapter has been loaded.
SELECT core10.mfg_define_substitution_v1(9511,9521,:recipe_id,1,9546,2.5,'fixture:kg',200,1,50,'Fictional milk powder proposal','sub_define_01') AS rule \gset
SELECT (:'rule'::jsonb->>'rule_id')::bigint AS rule_id \gset
SELECT mfg_sub_test.ok((core10.mfg_define_substitution_v1(9511,9521,:recipe_id,1,9546,2.5,'fixture:kg',200,1,50,'Fictional milk powder proposal','sub_define_01')->>'replayed')::boolean,'same rule exactly once');
SELECT mfg_sub_test.expect(format('SELECT core10.mfg_define_substitution_v1(9511,9521,%s,1,9546,3,%L,200,1,50,%L,%L)',:recipe_id,'fixture:kg','Fictional milk powder proposal','sub_define_01'),'MFG_REPLAY_CONFLICT');
SELECT mfg_sub_test.expect(format('SELECT core10.mfg_define_substitution_v1(9511,9521,%s,1,9546,2.5,%L,200,1,50,%L,%L)',:recipe_id,'fixture:kg','Same pair another key','sub_duplicate_02'),'MFG_SUBSTITUTION_EXISTS');
SELECT core10.mfg_preview_substitution_v1(9511,9521,:rule_id,2,50) AS preview \gset
SELECT mfg_sub_test.ok((:'preview'::jsonb->'original_component'->>'remaining_quantity')::numeric=10,'half original input at multiplier two');
SELECT mfg_sub_test.ok((:'preview'::jsonb->'alternative_component'->>'quantity')::numeric=2.5,'declared alternative quantity, not a UOM conversion');
SELECT mfg_sub_test.ok((:'preview'::jsonb->>'estimated_total_cost')::numeric=1500,'non-posting replacement estimate');
SELECT mfg_sub_test.ok((:'preview'::jsonb->>'planning_cost_variance')::numeric=-300,'planning delta from baseline 1800');
SELECT mfg_sub_test.ok((:'preview'::jsonb->'output'->>'quantity')::numeric=200,'output plan retained');
SELECT mfg_sub_test.ok(jsonb_array_length(:'preview'::jsonb->'unchanged_components')=1,'packaging unchanged');
SELECT mfg_sub_test.ok(:'preview'::jsonb->>'master'='NOT_CONNECTED' AND NOT (:'preview'::jsonb->>'batch_selected')::boolean,'proposal is not production selection');
SELECT mfg_sub_test.expect(format('SELECT core10.mfg_preview_substitution_v1(9511,9521,%s,1,50.0001)',:rule_id),'CONTROL_LIMIT:max_replacement_pct');
SELECT mfg_sub_test.expect(format('SELECT core10.mfg_preview_substitution_v1(9511,9521,%s,1,33.3333)',:rule_id),'MFG_QUANTITY_PRECISION');
SELECT mfg_sub_test.expect(format('SELECT core10.mfg_preview_substitution_v1(9511,9521,%s,0.0000001,50)',:rule_id),'MFG_INVALID_MULTIPLIER');
-- Source/foreign item, line, precision and structural limits.
DO $$ DECLARE item bigint; recipe bigint; BEGIN
 SELECT (x->>'id')::bigint INTO recipe FROM jsonb_array_elements(core10.mfg_inspect_v1(9511,9521)->'recipes') x LIMIT 1;
 FOREACH item IN ARRAY ARRAY[9541,9542,9544,9545] LOOP
 PERFORM mfg_sub_test.expect(format('SELECT core10.mfg_define_substitution_v1(9511,9521,%s,1,%s,2.5,%L,200,1,50,%L,%L)',recipe,item,'fixture:kg','Bad alternative must fail','sub_item_bad'),'MFG_ITEM_SCOPE');
 END LOOP;
 PERFORM mfg_sub_test.expect(format('SELECT core10.mfg_define_substitution_v1(9511,9521,%s,999,9546,2.5,%L,200,1,50,%L,%L)',recipe,'fixture:kg','Bad source line','sub_line_bad'),'MFG_CONSUMPTION_LINE');
 PERFORM mfg_sub_test.expect(format('SELECT core10.mfg_define_substitution_v1(9511,9521,%s,1,9547,0.0000001,%L,200,1,50,%L,%L)',recipe,'fixture:kg','Precision must fail','sub_precision_bad'),'MFG_SUBSTITUTION_INPUT');
END $$;
SELECT core10.control_set_v1(9511,NULL,'mfg.recipe_substitution',true,0::smallint,'{"max_replacement_pct":30,"allow_packaging":false}',NULL,false,0,'Owner limits alternative proposals','sub_policy_limit');
SELECT mfg_sub_test.expect(format('SELECT core10.mfg_preview_substitution_v1(9511,9521,%s,1,50)',:rule_id),'CONTROL_LIMIT:max_replacement_pct');
SELECT mfg_sub_test.ok((core10.mfg_preview_substitution_v1(9511,9521,:rule_id,1,20)->>'estimated_total_cost')::numeric=840,'current Owner cap allows smaller preview');
SELECT mfg_sub_test.expect(format('SELECT core10.mfg_define_substitution_v1(9511,9521,%s,2,9547,10,%L,4,0,100,%L,%L)',:recipe_id,'fixture:piece','Packaging disabled by Owner','sub_pack_bad'),'CONTROL_LIMIT:allow_packaging');
-- Every new mutation has real disabled-feature proof, including exact replay; reads also refuse.
SELECT core10.control_set_v1(9511,NULL,'mfg.recipe_substitution',false,0::smallint,'{}',NULL,false,1,'Owner pauses substitution proposals','sub_feature_off');
SELECT mfg_sub_test.expect(format('SELECT core10.mfg_define_substitution_v1(9511,9521,%s,1,9546,2.5,%L,200,1,50,%L,%L)',:recipe_id,'fixture:kg','Fictional milk powder proposal','sub_define_01'),'CONTROL_DISABLED');
SELECT mfg_sub_test.expect(format('SELECT core10.mfg_recipe_substitutions_v1(9511,9521,%s)',:recipe_id),'CONTROL_DISABLED');
SELECT mfg_sub_test.expect(format('SELECT core10.mfg_preview_substitution_v1(9511,9521,%s,1,20)',:rule_id),'CONTROL_DISABLED');
SELECT set_config('request.jwt.claims','{"sub":"95222222-2222-4222-8222-222222222222"}',true);
SELECT core10.control_grant_override_v1(9511,9521,'mfg.recipe_substitution',1,'One fictional packaging proposal','sub_override_01');
SELECT core10.mfg_define_substitution_v1(9511,9521,:recipe_id,2,9547,10,'fixture:piece',4,0,100,'Fictional alternate packaging','sub_pack_01');
SELECT mfg_sub_test.expect(format('SELECT core10.mfg_define_substitution_v1(9511,9521,%s,2,9546,1,%L,4,0,100,%L,%L)',:recipe_id,'fixture:piece','No second exception','sub_override_twice'),'CONTROL_DISABLED');
SELECT core10.control_set_v1(9511,NULL,'mfg.recipe_substitution',true,1::smallint,'{}',NULL,false,2,'Owner requires proposal approval','sub_feature_stages');
SELECT mfg_sub_test.expect(format('SELECT core10.mfg_define_substitution_v1(9511,9521,%s,2,9546,1,%L,4,0,100,%L,%L)',:recipe_id,'fixture:piece','Approval not connected','sub_stage_bad'),'NOT_CONNECTED:APPROVAL_COMPLETION');
SELECT core10.control_set_v1(9511,NULL,'mfg.recipe_substitution',true,0::smallint,'{}',NULL,false,3,'Owner resumes direct draft proposals','sub_feature_resume');
SELECT core10.control_set_v1(9511,NULL,'mfg.recipe_approve',true,0::smallint,'{}',NULL,false,0,'Synthetic direct recipe approval','sub_recipe_approve_control');
-- A rule maker cannot approve even though they did not create the original recipe.
SELECT mfg_sub_test.expect(format('SELECT core10.mfg_approve_recipe_v1(9511,9521,%s,now(),%L)',:recipe_id,'sub_rule_maker_approve'),'MFG_MAKER_CHECKER');
SELECT set_config('request.jwt.claims','{"sub":"95aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"}',true);
SELECT mfg_sub_test.expect(format('SELECT core10.mfg_approve_recipe_v1(9511,9521,%s,now(),%L)',:recipe_id,'sub_missing_master'),'NOT_CONNECTED:MASTER_UOM');
RESET ROLE;
\ir master-fixture.sql
SET LOCAL ROLE authenticated;
SELECT mfg_sub_test.expect(format('SELECT core10.mfg_approve_recipe_v1(9511,9521,%s,now(),%L)',:recipe_id,'sub_missing_alternative_master'),'NOT_CONNECTED:MASTER_SUBSTITUTION');
RESET ROLE;
-- Only approval/immutability/source tests below load an explicitly synthetic alternatives guard.
\ir substitution-fixture.sql
SET LOCAL ROLE authenticated;
SELECT core10.mfg_approve_recipe_v1(9511,9521,:recipe_id,now(),'sub_approve_01');
SELECT mfg_sub_test.expect(format('SELECT core10.mfg_define_substitution_v1(9511,9521,%s,2,9546,1,%L,4,0,100,%L,%L)',:recipe_id,'fixture:piece','Approved recipe cannot change','sub_approved_bad'),'MFG_RECIPE_STATE');
SELECT core10.mfg_plan_batch_v1(9511,9521,:recipe_id,9531,1,'sub_batch_01') AS batch \gset
SELECT (:'batch'::jsonb->>'batch_id')::bigint AS batch_id \gset
SELECT mfg_sub_test.ok((:'batch'::jsonb->>'estimated_total_cost')::numeric=900,'batch still uses original BOM, never preview selection');
SELECT set_config('request.jwt.claims','{"sub":"95222222-2222-4222-8222-222222222222"}',true);
SELECT core10.control_set_v1(9511,NULL,'mfg.batch_release',true,0::smallint,'{}',NULL,false,0,'Synthetic direct release','sub_release_control');
SELECT core10.mfg_release_batch_v1(9511,9521,:batch_id,'sub_release_01');
SELECT core10.mfg_request_handoff_v1(9511,9521,:batch_id,'ingredients','sub_source_01') AS handoff \gset
SELECT mfg_sub_test.ok(jsonb_array_length(:'handoff'::jsonb->'source_envelope'->'recipe_substitution_rules')=2,'source includes immutable rules with Audit IDs');
SELECT mfg_sub_test.ok(NOT (:'handoff'::jsonb->'source_envelope'->>'substitution_selected')::boolean,'no production selection claimed');
SELECT mfg_sub_test.ok((:'handoff'::jsonb->'source_envelope'->'lines'->0->>'item_id')::bigint=9542,'ingredient request remains original item');
SELECT mfg_sub_test.ok((core10.verify_canonical_audit_v1(9511)->>'ok')::boolean,'canonical Audit chain valid');
SELECT mfg_sub_test.expect('SELECT * FROM core10.bom_substitution_rules_v1','permission denied');
SELECT mfg_sub_test.expect('SELECT core10._mfg_substitution_check_v1(1)','permission denied');
DO $$ DECLARE actor text; BEGIN FOREACH actor IN ARRAY ARRAY[
 '95333333-3333-4333-8333-333333333333','95444444-4444-4444-8444-444444444444','95555555-5555-4555-8555-555555555555',
 '95666666-6666-4666-8666-666666666666','95777777-7777-4777-8777-777777777777','95888888-8888-4888-8888-888888888888'] LOOP
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor)::text,true);
 PERFORM mfg_sub_test.expect('SELECT core10.mfg_recipe_substitutions_v1(9511,9521,1)','MFG_SCOPE_DENIED');
 PERFORM mfg_sub_test.expect('SELECT core10.mfg_preview_substitution_v1(9511,9521,1,1,50)','MFG_SCOPE_DENIED');
 PERFORM mfg_sub_test.expect($q$SELECT core10.mfg_define_substitution_v1(9511,9521,1,1,9546,2.5,'fixture:kg',200,1,50,'Unauthorized proposal','sub_denied_role')$q$,'MFG_SCOPE_DENIED');
 END LOOP; END $$;
SELECT set_config('request.jwt.claims','{"sub":"95111111-1111-4111-8111-111111111111"}',true);
SELECT mfg_sub_test.expect(format('SELECT core10.mfg_recipe_substitutions_v1(9511,9524,%s)',:recipe_id),'MFG_SCOPE_DENIED');
SELECT mfg_sub_test.expect(format('SELECT core10.mfg_recipe_substitutions_v1(9513,9523,%s)',:recipe_id),'MFG_SCOPE_DENIED');
RESET ROLE;
SELECT mfg_sub_test.ok((SELECT count(*) FROM core10.bom_substitution_rules_v1)=2,'no duplicates or failed commands persisted');
SELECT mfg_sub_test.ok((SELECT count(*) FROM core10.stock_movements WHERE business_id=9511)=0,'no Stock writes');
SELECT mfg_sub_test.ok(NOT EXISTS(SELECT 1 FROM core10.bom_substitution_rules_v1 s LEFT JOIN core10.canonical_audit_events_v1 a ON a.id=s.audit_event_id WHERE a.id IS NULL OR a.actor_id<>s.created_by),'every rule has canonical evidence');
SELECT mfg_sub_test.expect('UPDATE core10.bom_substitution_rules_v1 SET alternative_qty_per_batch=3','MFG_SUBSTITUTION_IMMUTABLE');
SELECT mfg_sub_test.expect('DELETE FROM core10.bom_substitution_rules_v1','MFG_SUBSTITUTION_IMMUTABLE');
SELECT mfg_sub_test.expect('TRUNCATE core10.bom_substitution_rules_v1','MFG_SUBSTITUTION_IMMUTABLE');
SELECT mfg_sub_test.expect(format('INSERT INTO core10.bom_substitution_rules_v1 SELECT 999,tenant_id,business_id,site_id,bom_id,line_no,alternative_item_id,alternative_qty_per_batch,uom_ref,estimated_unit_cost,expected_waste_pct,max_replacement_pct,note,created_by,created_at,audit_event_id FROM core10.bom_substitution_rules_v1 WHERE id=%s',:rule_id),'MFG_SUBSTITUTION_IMMUTABLE');
\echo NP05A_SUBSTITUTION_RULES_PREVIEW_OK
ROLLBACK;
