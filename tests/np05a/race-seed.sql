\set ON_ERROR_STOP on
\ir seed.sql
-- Persistent only within the disposable QA database, so concurrent sessions share fixture records.
SELECT set_config('request.jwt.claims','{"sub":"95111111-1111-4111-8111-111111111111"}',false);
SELECT core10.mfg_create_recipe_v1(9511,9521,9541,'RACE',100,'fixture:piece',
 '[{"item":9542,"qty":10,"uom_ref":"fixture:kg","kind":"ingredient","waste_pct":2,"estimated_unit_cost":80}]',50,'race_recipe_01');
\ir master-fixture.sql
SELECT set_config('request.jwt.claims','{"sub":"95222222-2222-4222-8222-222222222222"}',false);
SELECT core10.control_set_v1(9511,NULL,'mfg.recipe_approve',true,0::smallint,'{}',NULL,false,0,'Synthetic race only','race_control_01');
SELECT core10.control_set_v1(9511,NULL,'mfg.batch_release',true,0::smallint,'{}',NULL,false,0,'Synthetic race only','race_control_02');
SELECT core10.mfg_approve_recipe_v1(9511,9521,(SELECT id FROM core10.bom_recipes_v1 WHERE recipe_code='RACE'),now(),'race_approve_01');
SELECT set_config('request.jwt.claims','{"sub":"95111111-1111-4111-8111-111111111111"}',false);
SELECT core10.mfg_plan_batch_v1(9511,9521,(SELECT id FROM core10.bom_recipes_v1 WHERE recipe_code='RACE'),9531,1,'race_plan_01');
SELECT set_config('request.jwt.claims','{"sub":"95222222-2222-4222-8222-222222222222"}',false);
SELECT core10.mfg_release_batch_v1(9511,9521,(SELECT id FROM core10.production_batches_v1 WHERE business_id=9511),'race_release_01');
