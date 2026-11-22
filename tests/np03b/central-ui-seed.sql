\set ON_ERROR_STOP on
\ir ui-seed.sql

SELECT core10.control_set_v1(101,NULL,'mfg.recipe',true,0::smallint,'{}',NULL,false,0,
 'Disposable Central Manufacturing route fixture','central_mfg_enable');
SELECT core10.mfg_create_recipe_v1(101,1002,8101,'CENTRAL-SITE-RECIPE',20,'master:7201',
 '[{"item":8102,"qty":10,"uom_ref":"master:7201","kind":"ingredient","waste_pct":0,"estimated_unit_cost":5}]',
 0,'central_mfg_recipe');
SELECT core10.mfg_create_recipe_v1(101,1002,8101,'CENTRAL-WIDE-RECIPE',20,'master:7201',
 '[{"item":8102,"qty":10,"uom_ref":"master:7201","kind":"ingredient","waste_pct":0,"estimated_unit_cost":5}]',
 0,'central_mfg_wide_recipe');
INSERT INTO core10.tenant_members(tenant_id,user_id,role)
 VALUES(1,'abababab-abab-4bab-8bab-abababababab','tenant_owner');

SELECT core10.control_set_v1(101,NULL,'gov002.review',true,1::smallint,'{}',NULL,false,0,
 'Disposable Central approval route fixture','central_mfg_governance');
SELECT core10.publish_approval_policy_v1(101,'manufacturing','recipe_approve',120,
 'central_mfg_approval_policy') AS policy_id \gset
SELECT core10.configure_approval_route_v1(:policy_id,ARRAY['tenant_owner'],'central_mfg_approval_route');

SELECT core10.publish_approval_policy_v1(101,'manufacturing','batch_release',120,
 'central_mfg_release_policy') AS release_policy_id \gset
SELECT core10.configure_approval_route_v1(:release_policy_id,ARRAY['tenant_owner'],'central_mfg_release_route');

-- Inventoried stock at both sites through the existing guarded ledger.
SELECT core10.post_stock_event(5001,8102,90,'central_stock_showroom');
SELECT core10.post_stock_event(5002,8102,12.5,'central_stock_factory');
INSERT INTO core10.site_grants(tenant_id,business_id,site_id,user_id,actions,denied_actions)
 VALUES(1,101,1002,'33333333-3333-4333-8333-333333333333','{}',ARRAY['stock.read']);
