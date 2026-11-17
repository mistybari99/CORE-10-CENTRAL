\set ON_ERROR_STOP on
BEGIN;
\ir seed.sql
CREATE SCHEMA mfg_master_test;
GRANT USAGE ON SCHEMA mfg_master_test TO authenticated;
CREATE FUNCTION mfg_master_test.ok(v boolean,msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF v IS DISTINCT FROM true THEN RAISE EXCEPTION 'MASTER_ASSERT:%',msg; END IF; END $$;
CREATE FUNCTION mfg_master_test.expect(q text,e text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN BEGIN EXECUTE q; EXCEPTION WHEN OTHERS THEN
 IF SQLERRM LIKE e||'%' THEN RETURN; END IF; RAISE EXCEPTION 'WRONG_ERROR expected % got %',e,SQLERRM;
 END; RAISE EXCEPTION 'EXPECTED_ERROR:%',e; END $$;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA mfg_master_test TO authenticated;
SET LOCAL ROLE authenticated;
\ir canonical-master-seed.sql
SELECT core10.mfg_master_validation_v1(9511,9521,:mr,2) AS evidence \gset
SELECT mfg_master_test.ok(:'evidence'::jsonb->>'master'='VERIFIED_CANONICAL','real Master connected');
SELECT mfg_master_test.ok((:'evidence'::jsonb->'lines'->0->>'base_uom_quantity')::numeric=3,'3000 grams ->3kg');
SELECT mfg_master_test.ok((:'evidence'::jsonb->'lines'->1->>'base_uom_quantity')::numeric=20,'2boxes ->20pieces');
SELECT mfg_master_test.ok((:'evidence'::jsonb->'alternatives'->0->>'base_uom_quantity')::numeric=2000,'inverse 2kg ->2000gram');
SELECT mfg_master_test.ok(:'evidence'::jsonb->'lines'->0->>'conversion_direction'='direct' AND :'evidence'::jsonb->'alternatives'->0->>'conversion_direction'='inverse','canonical directions');
SELECT core10.mfg_preview_substitution_v2(9511,9521,:rule,2,50) AS preview \gset
SELECT mfg_master_test.ok((:'preview'::jsonb->'original_master'->>'base_uom_quantity')::numeric=1.5 AND (:'preview'::jsonb->'alternative_master'->>'base_uom_quantity')::numeric=1000,'partial quantity preview');
SELECT mfg_master_test.ok(NOT (:'preview'::jsonb->>'stock_issued')::boolean AND NOT (:'preview'::jsonb->>'financial_posted')::boolean AND NOT (:'preview'::jsonb->>'batch_selected')::boolean,'no fake posting/selection');
SELECT mfg_master_test.expect(format('SELECT core10.mfg_master_validation_v1(9511,9521,%s,0.1)',:mr),'MFG_QUANTITY_PRECISION'); -- fractional output pieces
SELECT mfg_master_test.expect('SELECT core10._mfg_master_material_v1(9511,951,1,''master:1'',1)','permission denied');
SELECT core10.control_set_v1(9511,NULL,'mfg.material_requirements',false,0::smallint,'{}',NULL,false,0,'Synthetic off','mfg_master_report_off');
SELECT mfg_master_test.expect(format('SELECT core10.mfg_master_validation_v1(9511,9521,%s,1)',:mr),'CONTROL_DISABLED');
SELECT core10.control_set_v1(9511,NULL,'mfg.material_requirements',true,0::smallint,'{}',NULL,false,1,'Synthetic on','mfg_master_report_on');
SELECT core10.master_save_item_v1(9511,'MFG-FLOUR','Fictional flour','কাল্পনিক ময়দা','raw_material',NULL,:kg,'inactive',1,'mfg_master_inactive');
SELECT mfg_master_test.expect(format('SELECT core10.mfg_master_validation_v1(9511,9521,%s,1)',:mr),'MFG_MASTER_ITEM_UNUSABLE');
SELECT core10.master_save_item_v1(9511,'MFG-FLOUR','Fictional flour','কাল্পনিক ময়দা','raw_material',NULL,:kg,'active',2,'mfg_master_reactivate');
SELECT mfg_master_test.expect(format('SELECT core10.master_save_item_v1(9511,''MFG-FLOUR'',''Stale'',NULL,''raw_material'',NULL,%s,''active'',1,''mfg_master_stale'')',:kg),'MASTER_STALE_OR_MISSING');
SELECT mfg_master_test.ok((core10.mfg_master_validation_v1(9511,9521,:mr,1)->'lines'->0->>'item_version')::int=3,'current canonical item version');
SELECT core10.master_save_uom_conversion_v1(9511,:gram,:kg,0.001,false,1,'mfg_master_conv_off');
SELECT mfg_master_test.expect(format('SELECT core10.mfg_preview_substitution_v2(9511,9521,%s,2,50)',:rule),'MASTER_UOM_NO_CONVERSION');
SELECT core10.master_save_uom_conversion_v1(9511,:gram,:kg,0.001,true,2,'mfg_master_conv_on');
SELECT core10.master_save_uom_v1(9511,'MFG_G','Gram','গ্রাম','mass',6::smallint,false,1,'mfg_master_uom_off');
SELECT mfg_master_test.expect(format('SELECT core10.mfg_master_validation_v1(9511,9521,%s,1)',:mr),'MASTER_UOM_SCOPE');
SELECT core10.master_save_uom_v1(9511,'MFG_G','Gram','গ্রাম','mass',6::smallint,true,2,'mfg_master_uom_on');
SELECT core10.mfg_create_recipe_v1(9511,9521,:fg,'MASTER-BAD',100,'kg',jsonb_build_array(jsonb_build_object('item',:flour,'qty',1,'uom_ref','master:'||:kg,'kind','ingredient','waste_pct',0,'estimated_unit_cost',1)),0,'mfg_master_badref') AS bad \gset
SELECT mfg_master_test.expect(format('SELECT core10.mfg_master_validation_v1(9511,9521,%s,1)',(:'bad'::jsonb->>'recipe_id')::bigint),'NOT_CONNECTED:MASTER_UOM_REFERENCE');
-- No cross-dimension culinary conversion and no cross-business/tenant item or UOM use.
RESET ROLE;
SELECT mfg_master_test.expect(format('SELECT core10._mfg_master_material_v1(9511,951,%s,%L,1)',:flour,'master:'||:pc),'MASTER_UOM_NO_CONVERSION');
SELECT mfg_master_test.expect(format('SELECT core10._mfg_master_material_v1(9511,951,9545,%L,1)','master:'||:kg),'MFG_MASTER_ITEM_UNUSABLE');
SELECT mfg_master_test.expect(format('SELECT core10._mfg_master_material_v1(9513,951,%s,%L,1)',:flour,'master:'||:kg),'MFG_MASTER_ITEM_UNUSABLE');
SELECT mfg_master_test.expect(format('SELECT core10._mfg_master_material_v1(9511,952,%s,%L,1)',:flour,'master:'||:kg),'MFG_MASTER_ITEM_UNUSABLE');
SELECT mfg_master_test.expect(format('SELECT core10._mfg_master_material_v1(9511,951,%s,%L,1)',:flour,'master:9223372036854775808'),'NOT_CONNECTED:MASTER_UOM_REFERENCE');
SET LOCAL ROLE authenticated;
SELECT set_config('mfg.test.recipe',:mr::text,true);
DO $$ DECLARE a text; BEGIN FOREACH a IN ARRAY ARRAY[
 '95333333-3333-4333-8333-333333333333','95666666-6666-4666-8666-666666666666',
 '95777777-7777-4777-8777-777777777777','95888888-8888-4888-8888-888888888888'] LOOP
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',a)::text,true);
 PERFORM mfg_master_test.expect(format('SELECT core10.mfg_master_validation_v1(9511,9521,%s,1)',current_setting('mfg.test.recipe')),'MFG_SCOPE_DENIED');
 END LOOP; END $$;
SELECT set_config('request.jwt.claims','{"sub":"95222222-2222-4222-8222-222222222222"}',true);
SELECT mfg_master_test.expect(format('SELECT core10.mfg_master_validation_v1(9512,9522,%s,1)',:mr),'MFG_SCOPE_DENIED');
SELECT mfg_master_test.expect(format('SELECT core10.mfg_master_validation_v1(9513,9523,%s,1)',:mr),'MFG_SCOPE_DENIED');
SELECT mfg_master_test.expect(format('SELECT core10.mfg_master_validation_v1(9511,9524,%s,1)',:mr),'MFG_SCOPE_DENIED');
SELECT mfg_master_test.expect(format('SELECT core10.mfg_approve_recipe_v1(9511,9521,%s,now(),''master_stage_denied'')',:mr),'NOT_CONNECTED:APPROVAL_COMPLETION');
SELECT core10.control_set_v1(9511,NULL,'mfg.recipe_approve',true,0::smallint,'{}',NULL,false,0,'Synthetic zero-stage route','mfg_master_approve_control');
SELECT core10.master_save_item_v1(9511,'MFG-ALT','Fictional alternative flour',NULL,'raw_material',NULL,:gram,'inactive',1,'mfg_master_alt_off');
SELECT mfg_master_test.expect(format('SELECT core10.mfg_approve_recipe_v1(9511,9521,%s,now(),''master_alt_invalid'')',:mr),'MFG_MASTER_ITEM_UNUSABLE');
SELECT core10.master_save_item_v1(9511,'MFG-ALT','Fictional alternative flour',NULL,'raw_material',NULL,:gram,'active',2,'mfg_master_alt_on');
RESET ROLE;
ALTER FUNCTION core10.master_item_usable_v1(bigint,bigint) RENAME TO master_item_usable_disconnected_test;
SELECT mfg_master_test.expect(format('SELECT core10.mfg_master_validation_v1(9511,9521,%s,1)',:mr),'NOT_CONNECTED:MASTER_PORT');
ALTER FUNCTION core10.master_item_usable_disconnected_test(bigint,bigint) RENAME TO master_item_usable_v1;
SET LOCAL ROLE authenticated;
SELECT core10.mfg_approve_recipe_v1(9511,9521,:mr,'2026-01-01 UTC','mfg_master_approve') AS approved \gset
SELECT mfg_master_test.ok(core10.mfg_approve_recipe_v1(9511,9521,:mr,'2026-01-01 UTC','mfg_master_approve')->>'replayed'='true','approval exact-key replay');
SELECT mfg_master_test.expect(format('SELECT core10.mfg_approve_recipe_v1(9511,9521,%s,''2026-02-01 UTC'',''mfg_master_approve'')',:mr),'MFG_REPLAY_CONFLICT');
SELECT set_config('request.jwt.claims','{"sub":"95111111-1111-4111-8111-111111111111"}',true);
SELECT core10.mfg_create_recipe_v1(9511,9521,:fg,'MASTER-LIVE',100,'master:'||:pc,
 jsonb_build_array(jsonb_build_object('item',:flour,'qty',1000,'uom_ref','master:'||:gram,'kind','ingredient','waste_pct',0,'estimated_unit_cost',0.08)),20,'mfg_master_version2') AS second \gset
SELECT mfg_master_test.ok((:'second'::jsonb->>'version')::int=2,'new immutable recipe version');
SELECT core10.mfg_plan_batch_v1(9511,9521,:mr,9531,1,'mfg_master_plan') AS batch \gset
SELECT (:'batch'::jsonb->>'batch_id')::bigint AS bid \gset
SELECT set_config('request.jwt.claims','{"sub":"95222222-2222-4222-8222-222222222222"}',true);
SELECT core10.control_set_v1(9511,NULL,'mfg.batch_release',true,0::smallint,'{}',NULL,false,0,'Synthetic release','mfg_master_release_control');
SELECT core10.mfg_release_batch_v1(9511,9521,:bid,'mfg_master_release');
SELECT mfg_master_test.ok(core10.mfg_request_handoff_v1(9511,9521,:bid,'ingredients','mfg_master_stock')->>'status'='NOT_CONNECTED','0200 is not manufacturing Stock receiver');
SELECT mfg_master_test.ok((core10.verify_canonical_audit_v1(9511)->>'ok')::boolean,'canonical Audit linked');
RESET ROLE;
SELECT mfg_master_test.ok((SELECT count(*)=0 FROM core10.stock_movements WHERE business_id=9511),'zero Stock mutations');
SELECT mfg_master_test.ok((SELECT count(*)=0 FROM core10.finance_journals_v1 WHERE business_id=9511),'zero Money mutations');
SELECT mfg_master_test.expect(format('UPDATE core10.bom_recipes_v1 SET yield_quantity=99 WHERE id=%s',:mr),'MFG_RECIPE_IMMUTABLE');
SAVEPOINT before_down;
\ir ../../internal/migrations/0504_np05a_canonical_master.down.sql
SELECT mfg_master_test.expect(format('SELECT core10._mfg_master_check_v1(%s)',:mr),'NOT_CONNECTED:MASTER_UOM');
ROLLBACK TO before_down;
SELECT mfg_master_test.ok(to_regprocedure('core10.mfg_master_validation_v1(bigint,bigint,bigint,numeric)') IS NOT NULL,'atomic rollback reversible without history loss');
ROLLBACK;
\echo NP05A_CANONICAL_MASTER_E2E_OK
