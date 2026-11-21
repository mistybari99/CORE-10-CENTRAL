\set ON_ERROR_STOP on
\ir ui-seed.sql

SELECT core10.control_set_v1(101,NULL,'mfg.recipe',true,0::smallint,'{}',NULL,false,0,
 'Disposable Central Manufacturing route fixture','central_mfg_enable');
SELECT core10.mfg_create_recipe_v1(101,1002,8101,'CENTRAL-SITE-RECIPE',20,'master:7201',
 '[{"item":8102,"qty":10,"uom_ref":"master:7201","kind":"ingredient","waste_pct":0,"estimated_unit_cost":5}]',
 0,'central_mfg_recipe');
