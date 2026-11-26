\set ON_ERROR_STOP on
BEGIN;
\ir seed.sql
CREATE FUNCTION pg_temp.ok(condition boolean, message text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF condition IS DISTINCT FROM true THEN RAISE EXCEPTION 'MFG_LOT_ASSERT:%',message; END IF; END $$;
CREATE FUNCTION pg_temp.expect(command text, prefix text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 BEGIN EXECUTE command;
 EXCEPTION WHEN OTHERS THEN
  IF starts_with(SQLERRM,prefix) THEN RETURN; END IF;
  RAISE;
 END;
 RAISE EXCEPTION 'MFG_LOT_EXPECTED_DENIAL:%',prefix;
END $$;

SET LOCAL ROLE authenticated;
\ir canonical-master-seed.sql
SELECT set_config('request.jwt.claims','{"sub":"95222222-2222-4222-8222-222222222222"}',true);
SELECT core10.control_set_v1(9511,NULL,'mfg.recipe_approve',true,0::smallint,'{}',NULL,false,0,'QA recipe approval','qa_finished_recipe_ctl');
SELECT core10.control_set_v1(9511,NULL,'mfg.batch_release',true,0::smallint,'{}',NULL,false,0,'QA batch release','qa_finished_release_ctl');
SELECT core10.mfg_approve_recipe_v1(9511,9521,:mr,now(),'qa_finished_approve');
SELECT set_config('request.jwt.claims','{"sub":"95111111-1111-4111-8111-111111111111"}',true);
SELECT (core10.mfg_plan_batch_v1(9511,9521,:mr,9531,1,'qa_finished_plan')->>'batch_id')::bigint AS batch \gset
SELECT set_config('request.jwt.claims','{"sub":"95222222-2222-4222-8222-222222222222"}',true);
SELECT core10.mfg_release_batch_v1(9511,9521,:batch,'qa_finished_release');

-- Fixture lot identities only. All movements use existing named Inventory commands.
RESET ROLE;
INSERT INTO core10.inventory_lots_v1(tenant_id,business_id,item_id,lot_code,source_kind,source_ref,created_by)
VALUES (951,9511,:flour,'QA-FLOUR','purchase','qa-seed-flour',core10.actor_uid()) RETURNING id AS flour_lot \gset
INSERT INTO core10.inventory_lots_v1(tenant_id,business_id,item_id,lot_code,source_kind,source_ref,created_by)
VALUES (951,9511,:pack,'QA-PACK','purchase','qa-seed-pack',core10.actor_uid()) RETURNING id AS pack_lot \gset
INSERT INTO core10.sites(id,tenant_id,business_id,kind,label,request_key)
 VALUES(9525,951,9511,'showroom','QA showroom','mfg-site-storefront');
INSERT INTO core10.stock_locations(id,tenant_id,business_id,site_id,code) VALUES(9535,951,9511,9525,'QA-SHOWROOM');

SET LOCAL ROLE authenticated;
SELECT (core10.inventory_create_lot_command_v1(9511,'receive',NULL,9531,:flour,2,:flour_lot,'Fixture received flour','qa_finished_flour_receive')->>'command_id')::bigint AS receive_flour \gset
SELECT (core10.inventory_create_lot_command_v1(9511,'receive',NULL,9531,:pack,11,:pack_lot,'Fixture received packaging','qa_finished_pack_receive')->>'command_id')::bigint AS receive_pack \gset
SELECT core10.advance_inventory_command_v1(:receive_flour,'confirm',1,'qa_finished_flour_receive_confirm');
SELECT core10.advance_inventory_command_v1(:receive_pack,'confirm',1,'qa_finished_pack_receive_confirm');
SELECT core10.advance_inventory_command_v1(:receive_flour,'post',2,'qa_finished_flour_receive_post');
SELECT core10.advance_inventory_command_v1(:receive_pack,'post',2,'qa_finished_pack_receive_post');
SELECT (core10.inventory_create_lot_command_v1(9511,'issue',9531,NULL,:flour,1.5,:flour_lot,
 'Manufacturing batch '||:batch||' line 1','qa_finished_flour_issue')->>'command_id')::bigint AS issue_flour \gset
SELECT (core10.inventory_create_lot_command_v1(9511,'issue',9531,NULL,:pack,10,:pack_lot,
 'Manufacturing batch '||:batch||' line 2','qa_finished_pack_issue')->>'command_id')::bigint AS issue_pack \gset
SELECT core10.advance_inventory_command_v1(:issue_flour,'confirm',1,'qa_finished_flour_issue_confirm');
SELECT core10.advance_inventory_command_v1(:issue_pack,'confirm',1,'qa_finished_pack_issue_confirm');
SELECT core10.advance_inventory_command_v1(:issue_flour,'post',2,'qa_finished_flour_issue_post');
SELECT core10.mfg_record_output_v1(9511,9521,:batch,
 '{"good":95,"rejected":2,"rework":1,"loss":2,"reason":"PROCESS_LOSS","lot_ref":"QA-FINISHED",
 "consumption":[{"line":1,"qty":1500,"lot_ref":"QA-FLOUR"},{"line":2,"qty":1,"lot_ref":"QA-PACK"}]}','qa_finished_output');
SELECT jsonb_build_object('1',:issue_flour,'2',:issue_pack) AS issues \gset
SELECT pg_temp.expect(format('SELECT core10.mfg_prepare_finished_lot_v1(9511,9521,%s,%L,current_date+10,%L)',
 :batch,:'issues','qa_finished_prepare'),'CONTROL_DISABLED:mfg.finished_lot_prepare');
SELECT core10.control_set_v1(9511,NULL,'mfg.finished_lot_prepare',true,0::smallint,'{}',NULL,false,0,'QA finished lot','qa_finished_ctl_on');
SELECT pg_temp.expect(format('SELECT core10.mfg_prepare_finished_lot_v1(9511,9521,%s,%L,current_date+10,%L)',
 :batch,:'issues','qa_finished_prepare'),'MFG_FINISHED_LOT_ISSUE_MISMATCH');
SELECT core10.advance_inventory_command_v1(:issue_pack,'post',2,'qa_finished_pack_issue_post');
SELECT core10.mfg_prepare_finished_lot_v1(9511,9521,:batch,:'issues',current_date+10,'qa_finished_prepare') AS draft \gset
SELECT (:'draft'::jsonb->>'inventory_command_id')::bigint AS command_id,
 (:'draft'::jsonb->>'lot_id')::bigint AS finished_lot \gset
SELECT pg_temp.ok(:'draft'::jsonb->>'status'='draft'
 AND (:'draft'::jsonb->>'stock_received')::boolean IS FALSE,
 'manufacturing prepares a receipt draft only');
SELECT pg_temp.ok(core10.mfg_prepare_finished_lot_v1(9511,9521,:batch,:'issues',current_date+10,'qa_finished_prepare')
  = :'draft'::jsonb||'{"replayed":true}'::jsonb,'exact replay returns the same draft');
SELECT pg_temp.expect(format('SELECT core10.mfg_prepare_finished_lot_v1(9511,9521,%s,%L,current_date+10,%L)',
 :batch,:'issues','qa_finished_prepare_alt'),'MFG_FINISHED_LOT_ALREADY_PREPARED');
RESET ROLE;
SELECT pg_temp.ok(NOT EXISTS(SELECT 1 FROM core10.stock_movement_lots_v1 WHERE lot_id=:finished_lot),
 'draft has no stock effect');
SELECT pg_temp.ok((SELECT count(*)=2 FROM core10.inventory_lot_links_v1
 WHERE child_lot_id=:finished_lot AND parent_lot_id IN (:flour_lot,:pack_lot)), 'both raw lot parents recorded');

SET LOCAL ROLE authenticated;
SELECT core10.control_set_v1(9511,NULL,'inventory.receive',true,0::smallint,
 '{"separate_confirmer":true}',NULL,false,0,'QA distinct receipt confirmer','qa_finished_receive_ctl');
SELECT pg_temp.expect(format('SELECT core10.advance_inventory_command_v1(%s,%L,1,%L)',
 :command_id,'confirm','qa_finished_lot_confirm'),'INV_SAME_ACTOR');
SELECT set_config('request.jwt.claims','{"sub":"95666666-6666-4666-8666-666666666666"}',true);
SELECT pg_temp.expect(format('SELECT core10.mfg_prepare_finished_lot_v1(9511,9521,%s,%L,current_date+10,%L)',
 :batch,:'issues','qa_finished_prepare'),'MFG_SCOPE_DENIED');
SELECT set_config('request.jwt.claims','{"sub":"95111111-1111-4111-8111-111111111111"}',true);
SELECT core10.advance_inventory_command_v1(:command_id,'confirm',1,'qa_finished_lot_confirm');
SELECT core10.advance_inventory_command_v1(:command_id,'post',2,'qa_finished_lot_post');
SELECT core10.advance_inventory_command_v1(:command_id,'post',2,'qa_finished_lot_post');
SELECT (core10.inventory_create_lot_command_v1(9511,'transfer',9531,9535,:fg,20,:finished_lot,
 'Dispatch production to showroom','qa_finished_dispatch')->>'command_id')::bigint AS dispatch \gset
SELECT core10.advance_inventory_command_v1(:dispatch,'confirm',1,'qa_finished_dispatch_confirm');
SELECT core10.advance_inventory_command_v1(:dispatch,'post',2,'qa_finished_dispatch_post');
RESET ROLE;
SELECT pg_temp.ok((SELECT count(*)=3
 AND sum(quantity) FILTER (WHERE location_id=9531)=75
 AND sum(quantity) FILTER (WHERE location_id=9535)=20
 FROM core10.stock_movement_lots_v1 WHERE lot_id=:finished_lot),
 'one receipt of 95 and one transfer of 20 leave 75 factory and 20 showroom');
SELECT pg_temp.ok(NOT EXISTS(SELECT 1 FROM core10.finance_journals_v1 WHERE business_id=9511),
 'no finance journal from the production stock workflow');
\echo 'PASS Bakery raw issues to finished lot and showroom transfer'
ROLLBACK;
