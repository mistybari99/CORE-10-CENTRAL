-- TEST DATA ONLY: real canonical Master RPCs, synthetic Owner subject, disposable DB.
SELECT set_config('request.jwt.claims','{"sub":"95111111-1111-4111-8111-111111111111"}',false);
SELECT core10.master_save_uom_v1(9511,'MFG_KG','Kilogram','কিলোগ্রাম','mass',6::smallint,true,0,'mfg_master_kg') AS kg \gset
SELECT core10.master_save_uom_v1(9511,'MFG_G','Gram','গ্রাম','mass',6::smallint,true,0,'mfg_master_g') AS gram \gset
SELECT core10.master_save_uom_v1(9511,'MFG_PC','Piece','পিস','count',0::smallint,true,0,'mfg_master_pc') AS pc \gset
SELECT core10.master_save_uom_v1(9511,'MFG_BOX','Box','বক্স','count',0::smallint,true,0,'mfg_master_box') AS box \gset
SELECT core10.master_save_uom_conversion_v1(9511,:gram,:kg,0.001,true,0,'mfg_master_g_kg');
SELECT core10.master_save_uom_conversion_v1(9511,:box,:pc,10,true,0,'mfg_master_box_pc');
SELECT core10.master_save_item_v1(9511,'MFG-FG','Fictional biscuit','কাল্পনিক বিস্কুট','finished_good',NULL,:pc,'active',0,'mfg_master_fg') AS fg \gset
SELECT core10.master_save_item_v1(9511,'MFG-FLOUR','Fictional flour','কাল্পনিক ময়দা','raw_material',NULL,:kg,'active',0,'mfg_master_flour') AS flour \gset
SELECT core10.master_save_item_v1(9511,'MFG-ALT','Fictional alternate flour','কাল্পনিক বিকল্প ময়দা','raw_material',NULL,:gram,'active',0,'mfg_master_alt') AS alt \gset
SELECT core10.master_save_item_v1(9511,'MFG-PACK','Fictional packaging','কাল্পনিক প্যাকেজিং','packaging',NULL,:pc,'active',0,'mfg_master_pack') AS pack \gset
SELECT core10.mfg_create_recipe_v1(9511,9521,:fg,'MASTER-LIVE',100,'master:'||:pc,
 jsonb_build_array(jsonb_build_object('item',:flour,'qty',1500,'uom_ref','master:'||:gram,'kind','ingredient','waste_pct',2,'estimated_unit_cost',0.08),
 jsonb_build_object('item',:pack,'qty',1,'uom_ref','master:'||:box,'kind','packaging','waste_pct',0,'estimated_unit_cost',10)),20,'mfg_master_recipe') AS master_recipe \gset
SELECT (:'master_recipe'::jsonb->>'recipe_id')::bigint AS mr \gset
SELECT core10.mfg_define_substitution_v1(9511,9521,:mr,1,:alt,1,'master:'||:kg,150,1,50,'Fictional alternative quantity; not equivalence','mfg_master_rule') AS master_rule \gset
SELECT (:'master_rule'::jsonb->>'rule_id')::bigint AS rule \gset
