\set ON_ERROR_STOP on
BEGIN;
\ir seed.sql
INSERT INTO core10.stock_locations(id,tenant_id,business_id,site_id,code)
 VALUES(9533,951,9511,9521,'OTHER-WAREHOUSE'),(9534,951,9511,9524,'OTHER-SITE');
INSERT INTO core10.master_parties_v1(id,tenant_id,business_id,code,party_kind,name_en,status)
 VALUES(9591,951,9511,'FLOUR-SUPPLIER','supplier','Fictional Flour Supplier','active');
SELECT EXISTS(SELECT 1 FROM core10.schema_migrations WHERE version=203) AS grn_provider \gset
CREATE FUNCTION pg_temp.ok(v boolean,msg text) RETURNS void LANGUAGE plpgsql AS $$
 BEGIN IF v IS DISTINCT FROM true THEN RAISE EXCEPTION 'GRN_ASSERT:%',msg; END IF; END $$;
CREATE FUNCTION pg_temp.expect(q text,e text) RETURNS void LANGUAGE plpgsql AS $$
 BEGIN BEGIN EXECUTE q; EXCEPTION WHEN OTHERS THEN IF SQLERRM=e THEN RETURN; END IF;
 RAISE EXCEPTION 'WRONG_ERROR expected % got %',e,SQLERRM;
 END; RAISE EXCEPTION 'EXPECTED_ERROR:%',e; END $$;
SET LOCAL ROLE authenticated;
\ir canonical-master-seed.sql
\set grn_reviewer '95222222-2222-4222-8222-222222222222'
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',:'grn_reviewer')::text,false);
SELECT core10.control_set_v1(9511,NULL,'mfg.recipe_approve',true,0::smallint,'{}',NULL,false,0,
 'Synthetic zero-stage test','grn_recipe_control');
SELECT core10.mfg_approve_recipe_v1(9511,9521,:mr,'2020-01-01T00:00:00Z','grn_recipe_approved');
SELECT (core10.mfg_plan_batch_v1(9511,9521,:mr,9531,1,'grn_batch_planned')->>'batch_id')::bigint AS batch_id \gset
SELECT (core10.mfg_plan_batch_v1(9511,9521,:mr,9533,1,'grn_batch_other_location')->>'batch_id')::bigint AS other_batch \gset
SELECT pg_temp.expect('SELECT core10.mfg_verify_grn_source_v1(9511,9521,9999999,1,1,1)','MFG_GRN_BATCH_SCOPE');
SELECT pg_temp.expect(format('SELECT core10.mfg_verify_grn_source_v1(9511,9521,%s,1,201,1)',:batch_id),'MFG_GRN_INVALID_REFERENCE');

\if :grn_provider
 \set grn_buyer '95333333-3333-4333-8333-333333333333'
 \set grn_business 9511
 \set grn_site 9521
 \set grn_location 9531
 \set grn_supplier 9591
 \set grn_item :flour
 \set grn_key 'GRN-FLOUR-QA'
 \ir post-grn-fixture.sql
 \set actual_grn :grn_id
 \set actual_lot :lot_id
 \set actual_movement :movement_id
 SELECT (core10.procurement_receive_v1(:po_id,9531,
  '[{"line_no":1,"quantity":10,"lot_code":"GRN-PENDING-QA"}]',NULL,'grn_pending_receive')->>'grn_id')::bigint AS pending_id \gset
 SELECT pg_temp.expect(format('SELECT core10.mfg_verify_grn_source_v1(9511,9521,%s,%s,1,%s)',:batch_id,:pending_id,:actual_lot),'MFG_GRN_SOURCE_UNVERIFIED');

 \set grn_site 9524
 \set grn_location 9534
 \set grn_key 'GRN-OTHER-SITE'
 \ir post-grn-fixture.sql
 SELECT pg_temp.expect(format('SELECT core10.mfg_verify_grn_source_v1(9511,9521,%s,%s,1,%s)',:batch_id,:grn_id,:lot_id),'MFG_GRN_SOURCE_UNVERIFIED');
 SELECT pg_temp.expect(format('SELECT core10.mfg_verify_grn_source_v1(9511,9521,%s,%s,1,%s)',:batch_id,:actual_grn,:lot_id),'MFG_GRN_SOURCE_UNVERIFIED');

 \set other_site_movement :movement_id
 \set grn_site 9521
 \set grn_location 9531
 \set grn_item :alt
 \set grn_key 'GRN-WRONG-ITEM'
 \ir post-grn-fixture.sql
 SELECT pg_temp.expect(format('SELECT core10.mfg_verify_grn_source_v1(9511,9521,%s,%s,1,%s)',:batch_id,:grn_id,:lot_id),'MFG_GRN_SOURCE_UNVERIFIED');
 SELECT pg_temp.expect(format('SELECT core10.mfg_verify_grn_source_v1(9511,9521,%s,%s,1,%s)',:other_batch,:actual_grn,:actual_lot),'MFG_GRN_SOURCE_UNVERIFIED');
 SELECT pg_temp.expect(format('SELECT core10.mfg_verify_grn_source_v1(9511,9521,%s,%s,2,%s)',:batch_id,:actual_grn,:actual_lot),'MFG_GRN_SOURCE_UNVERIFIED');

 RESET ROLE;
 SELECT count(*) AS original_audit_count FROM core10.canonical_audit_events_v1 WHERE business_id=9511 \gset
 SET LOCAL ROLE authenticated;
 SELECT core10.mfg_verify_grn_source_v1(9511,9521,:batch_id,:actual_grn,1,:actual_lot) AS verified \gset
 SELECT pg_temp.ok((:'verified'::jsonb->>'accepted_receipt_qty')::numeric=58
   AND (:'verified'::jsonb->>'lot_id')::bigint=:actual_lot
   AND (:'verified'::jsonb->>'stock_movement_id')::bigint=:actual_movement
   AND (:'verified'::jsonb->>'batch_id')::bigint=:batch_id
   AND (:'verified'::jsonb->>'audit_event_id')::bigint>0,'real GRN, accepted quantity, lot, movement and Audit');
 SELECT pg_temp.ok(core10.mfg_verify_grn_source_v1(9511,9521,:batch_id,:actual_grn,1,:actual_lot)=:'verified'::jsonb,
   'repeat read returns the same provenance');
 SELECT set_config('request.jwt.claims','{"sub":"95333333-3333-4333-8333-333333333333"}',false);
 SELECT pg_temp.expect(format('SELECT core10.mfg_verify_grn_source_v1(9511,9521,%s,%s,1,%s)',:batch_id,:actual_grn,:actual_lot),'MFG_SCOPE_DENIED');
 SELECT set_config('request.jwt.claims','{"sub":"95666666-6666-4666-8666-666666666666"}',false);
 SELECT pg_temp.expect(format('SELECT core10.mfg_verify_grn_source_v1(9511,9521,%s,%s,1,%s)',:batch_id,:actual_grn,:actual_lot),'MFG_SCOPE_DENIED');
 RESET ROLE;
 SELECT pg_temp.ok((SELECT count(*)=3 FROM core10.stock_movements WHERE business_id=9511)
   AND (SELECT count(*)=:original_audit_count FROM core10.canonical_audit_events_v1 WHERE business_id=9511)
   AND NOT EXISTS(SELECT 1 FROM core10.finance_journals_v1 WHERE business_id=9511),'verification produces no Stock, Finance or Audit write');
 -- An owner-only fixture corrupts one reference and then restores it inside this rollback.
 UPDATE core10.goods_receipt_lines_v1 SET stock_movement_id=:other_site_movement
  WHERE grn_id=:actual_grn AND line_no=1;
 SET LOCAL ROLE authenticated;
 SELECT set_config('request.jwt.claims',jsonb_build_object('sub',:'grn_reviewer')::text,false);
 SELECT pg_temp.expect(format('SELECT core10.mfg_verify_grn_source_v1(9511,9521,%s,%s,1,%s)',:batch_id,:actual_grn,:actual_lot),'MFG_GRN_SOURCE_UNVERIFIED');
 RESET ROLE;
 UPDATE core10.goods_receipt_lines_v1 SET stock_movement_id=:actual_movement
  WHERE grn_id=:actual_grn AND line_no=1;
 UPDATE core10.inventory_lots_v1 SET status='held' WHERE id=:actual_lot;
 SET LOCAL ROLE authenticated;
 SELECT set_config('request.jwt.claims',jsonb_build_object('sub',:'grn_reviewer')::text,false);
 SELECT pg_temp.expect(format('SELECT core10.mfg_verify_grn_source_v1(9511,9521,%s,%s,1,%s)',:batch_id,:actual_grn,:actual_lot),'MFG_GRN_SOURCE_UNVERIFIED');
\else
 SELECT pg_temp.expect(format('SELECT core10.mfg_verify_grn_source_v1(9511,9521,%s,1,1,1)',:batch_id),'NOT_CONNECTED:PROCUREMENT_GRN');
\endif
SELECT core10.control_set_v1(9511,NULL,'mfg.material_requirements',false,0::smallint,'{}',NULL,false,0,
 'Synthetic disable material reads','grn_material_disabled');
SELECT pg_temp.expect(format('SELECT core10.mfg_verify_grn_source_v1(9511,9521,%s,1,1,1)',:batch_id),'CONTROL_DISABLED:mfg.material_requirements');
ROLLBACK;
\echo GRN_PROVENANCE_E2E_PASS
