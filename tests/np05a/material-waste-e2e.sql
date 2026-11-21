\set ON_ERROR_STOP on
BEGIN;
\ir seed.sql
CREATE SCHEMA mfg_waste_test;
GRANT USAGE ON SCHEMA mfg_waste_test TO authenticated;
CREATE FUNCTION mfg_waste_test.ok(p boolean,msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p IS NOT TRUE THEN RAISE EXCEPTION 'ASSERT_FAILED:%',msg; END IF; END $$;
CREATE FUNCTION mfg_waste_test.expect(q text,e text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN BEGIN EXECUTE q; EXCEPTION WHEN OTHERS THEN
 IF SQLERRM LIKE e||'%' THEN RETURN; END IF; RAISE EXCEPTION 'WRONG_ERROR expected % got %',e,SQLERRM;
END; RAISE EXCEPTION 'MISSING_ERROR:%',e; END $$;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA mfg_waste_test TO authenticated;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims','{"sub":"95111111-1111-4111-8111-111111111111"}',true);
SELECT core10.mfg_create_recipe_v1(9511,9521,9541,'WASTE-OBSERVATION',100,'fixture:piece',
 '[{"item":9542,"qty":10,"uom_ref":"fixture:kg","kind":"ingredient","waste_pct":2,"estimated_unit_cost":80},
 {"item":9543,"qty":2,"uom_ref":"fixture:kg","kind":"ingredient","waste_pct":1,"estimated_unit_cost":100},
 {"item":9544,"qty":10,"uom_ref":"fixture:piece","kind":"packaging","waste_pct":0,"estimated_unit_cost":5}]',50,'waste_recipe_01') AS recipe \gset
SELECT (:'recipe'::jsonb->>'recipe_id')::bigint AS recipe_id \gset
SELECT set_config('request.jwt.claims','{"sub":"95222222-2222-4222-8222-222222222222"}',true);
SELECT core10.control_set_v1(9511,NULL,'mfg.recipe_approve',true,0::smallint,'{}',NULL,false,0,'Synthetic direct approval','waste_approve_control');
SELECT mfg_waste_test.expect(format('SELECT core10.mfg_approve_recipe_v1(9511,9521,%s,now(),%L)',:recipe_id,'waste_approve_missing'),'NOT_CONNECTED:MASTER_UOM');
RESET ROLE;
-- Only the precondition lifecycle uses the known test-only Master adapter. Never a migration/provider.
\ir master-fixture.sql
SET LOCAL ROLE authenticated;
SELECT core10.mfg_approve_recipe_v1(9511,9521,:recipe_id,now(),'waste_approve_01');
SELECT set_config('request.jwt.claims','{"sub":"95111111-1111-4111-8111-111111111111"}',true);
SELECT core10.mfg_plan_batch_v1(9511,9521,:recipe_id,9531,1,'waste_batch_01') AS batch \gset
SELECT (:'batch'::jsonb->>'batch_id')::bigint AS batch_id \gset
SELECT set_config('request.jwt.claims','{"sub":"95222222-2222-4222-8222-222222222222"}',true);
SELECT core10.control_set_v1(9511,NULL,'mfg.batch_release',true,0::smallint,'{}',NULL,false,0,'Synthetic direct release','waste_release_control');
SELECT core10.mfg_release_batch_v1(9511,9521,:batch_id,'waste_release_01');
SELECT mfg_waste_test.expect(format('SELECT core10.mfg_record_material_waste_v1(9511,9521,%s,1,0.1,%L,%L,%L,%L)',:batch_id,'SPILLAGE','FICTIONAL-MILK','Released but not measured','waste_early_01'),'MFG_WASTE_REQUIRES_RECORDED_OUTPUT');
SELECT core10.mfg_record_output_v1(9511,9521,:batch_id,
 '{"good":95,"rejected":2,"rework":1,"loss":2,"reason":"PROCESS_LOSS","lot_ref":"FICTIONAL-WASTE-OUTPUT",
 "consumption":[{"line":1,"qty":10,"lot_ref":"FICTIONAL-MILK"},{"line":2,"qty":2,"lot_ref":"FICTIONAL-SUGAR"},
 {"line":3,"qty":10,"lot_ref":"FICTIONAL-BOX"}]}','waste_output_01');
SELECT core10.mfg_request_handoff_v1(9511,9521,:batch_id,'finance','waste_source_before') AS before_source \gset
SELECT mfg_waste_test.ok(jsonb_array_length(:'before_source'::jsonb->'source_envelope'->'material_waste_events')=0,'initial source has no waste observations');
-- Positive units and reasons, policy thresholds and exact actor/payload replay.
SELECT core10.control_set_v1(9511,NULL,'mfg.material_waste',true,0::smallint,'{"max_waste_pct":10,"reason_codes":"CUSTOM_SPILL"}',NULL,false,0,'Owner custom waste policy','waste_policy_custom');
SELECT mfg_waste_test.expect(format('SELECT core10.mfg_record_material_waste_v1(9511,9521,%s,1,0.5,%L,%L,%L,%L)',:batch_id,'SPILLAGE','FICTIONAL-MILK','Reason not enabled','waste_reason_bad'),'MFG_WASTE_REASON');
SELECT core10.mfg_record_material_waste_v1(9511,9521,:batch_id,1,0.5,'CUSTOM_SPILL','FICTIONAL-MILK','Fictional spill during transfer','waste_custom_01') AS first_waste \gset
SELECT mfg_waste_test.ok((core10.mfg_record_material_waste_v1(9511,9521,:batch_id,1,0.5,'CUSTOM_SPILL','FICTIONAL-MILK','Fictional spill during transfer','waste_custom_01')->>'replayed')::boolean,'same event exactly once');
SELECT mfg_waste_test.expect(format('SELECT core10.mfg_record_material_waste_v1(9511,9521,%s,1,0.6,%L,%L,%L,%L)',:batch_id,'CUSTOM_SPILL','FICTIONAL-MILK','Fictional spill during transfer','waste_custom_01'),'MFG_REPLAY_CONFLICT');
SELECT mfg_waste_test.expect(format('SELECT core10.mfg_record_material_waste_v1(9511,9521,%s,1,0.6,%L,%L,%L,%L)',:batch_id,'CUSTOM_SPILL','FICTIONAL-MILK','Exceeds ten percent cap','waste_limit_bad'),'CONTROL_LIMIT:max_waste_pct');
SELECT core10.mfg_record_material_waste_v1(9511,9521,:batch_id,1,0.5,'CUSTOM_SPILL','FICTIONAL-MILK','Exactly ten percent cumulative','waste_exact_limit');
SELECT core10.control_set_v1(9511,NULL,'mfg.material_waste',true,0::smallint,'{}',NULL,false,1,'Owner resumes standard reasons','waste_policy_standard');
SELECT core10.mfg_record_material_waste_v1(9511,9521,:batch_id,1,0.4,'SPILLAGE','FICTIONAL-MILK','Second fictional handling spill','waste_standard_01');
SELECT core10.mfg_record_material_waste_v1(9511,9521,:batch_id,3,2,'PACKAGING_DAMAGE','FICTIONAL-BOX','Two fictional damaged boxes','waste_boxes_01');
SELECT core10.mfg_material_waste_report_v1(9511,9521,:batch_id) AS report \gset
SELECT mfg_waste_test.ok((:'report'::jsonb->'lines'->0->>'recorded_waste')::numeric=1.4,'cumulative milk waste 1.4 kg');
SELECT mfg_waste_test.ok((:'report'::jsonb->'lines'->0->>'unclassified_consumption')::numeric=8.6,'remaining use is unclassified, not certified good');
SELECT mfg_waste_test.ok((:'report'::jsonb->'lines'->0->>'expected_waste_quantity')::numeric=0.2,'expected waste stays a separate planning measure');
SELECT mfg_waste_test.ok((:'report'::jsonb->'lines'->2->>'recorded_waste')::numeric=2,'packaging in pieces');
SELECT mfg_waste_test.ok(NOT (:'report'::jsonb ? 'total_waste_quantity'),'no kg plus pieces grand total');
SELECT mfg_waste_test.ok(NOT (:'report'::jsonb->>'additional_stock_movement')::boolean,'observation is included in consumption');
-- Invalid quantities, reason, lot, note and material line leave no partial receipt/event.
DO $$ DECLARE q text; BEGIN FOREACH q IN ARRAY ARRAY['0','-1','0.0000001','100000001','''NaN''::numeric','''Infinity''::numeric'] LOOP
 PERFORM mfg_waste_test.expect(format('SELECT core10.mfg_record_material_waste_v1(9511,9521,%s,1,%s,%L,%L,%L,%L)',
  (SELECT (x->>'id')::bigint FROM jsonb_array_elements(core10.mfg_inspect_v1(9511,9521)->'batches') x WHERE x->>'status'='recorded'),q,
  'SPILLAGE','FICTIONAL-MILK','Invalid quantity must be denied','waste_quantity_bad'),'MFG_WASTE_QUANTITY');
END LOOP; END $$;
SELECT mfg_waste_test.expect(format('SELECT core10.mfg_record_material_waste_v1(9511,9521,%s,1,10,%L,%L,%L,%L)',:batch_id,'SPILLAGE','FICTIONAL-MILK','More waste than consumption','waste_overconsumption'),'MFG_WASTE_EXCEEDS_CONSUMPTION');
SELECT mfg_waste_test.expect(format('SELECT core10.mfg_record_material_waste_v1(9511,9521,%s,1,0.1,%L,%L,%L,%L)',:batch_id,'SPILLAGE','FOREIGN-LOT','Wrong lot must fail','waste_lot_bad'),'MFG_WASTE_LOT_MISMATCH');
SELECT mfg_waste_test.expect(format('SELECT core10.mfg_record_material_waste_v1(9511,9521,%s,999,0.1,%L,%L,%L,%L)',:batch_id,'SPILLAGE','FICTIONAL-MILK','Invalid line must fail','waste_line_bad'),'MFG_CONSUMPTION_LINE');
SELECT mfg_waste_test.expect(format('SELECT core10.mfg_record_material_waste_v1(9511,9521,%s,1,0.1,%L,%L,%L,%L)',:batch_id,'SPILLAGE','FICTIONAL-MILK','bad','waste_note_bad'),'MFG_REASON_REQUIRED');
-- Registry proof: disabled Control denies this mutation AND its read report, including replays.
SELECT core10.control_set_v1(9511,NULL,'mfg.material_waste',false,0::smallint,'{}',NULL,false,2,'Owner pauses material waste','waste_feature_off');
SELECT mfg_waste_test.expect(format('SELECT core10.mfg_record_material_waste_v1(9511,9521,%s,1,0.5,%L,%L,%L,%L)',:batch_id,'CUSTOM_SPILL','FICTIONAL-MILK','Fictional spill during transfer','waste_custom_01'),'CONTROL_DISABLED');
SELECT mfg_waste_test.expect(format('SELECT core10.mfg_material_waste_report_v1(9511,9521,%s)',:batch_id),'CONTROL_DISABLED');
SELECT core10.control_grant_override_v1(9511,9521,'mfg.material_waste',1,'One fictional spill observation','waste_override_01');
SELECT core10.mfg_record_material_waste_v1(9511,9521,:batch_id,1,0.1,'SPILLAGE','FICTIONAL-MILK','One-time authorized observation','waste_override_event');
SELECT mfg_waste_test.expect(format('SELECT core10.mfg_record_material_waste_v1(9511,9521,%s,1,0.1,%L,%L,%L,%L)',:batch_id,'SPILLAGE','FICTIONAL-MILK','No second exception available','waste_override_twice'),'CONTROL_DISABLED');
SELECT core10.control_set_v1(9511,NULL,'mfg.material_waste',true,1::smallint,'{}',NULL,false,3,'Owner requires approval for waste','waste_feature_stage');
SELECT mfg_waste_test.expect(format('SELECT core10.mfg_record_material_waste_v1(9511,9521,%s,1,0.1,%L,%L,%L,%L)',:batch_id,'SPILLAGE','FICTIONAL-MILK','Approval must not be fabricated','waste_approval_bad'),'NOT_CONNECTED:APPROVAL_COMPLETION');
SELECT core10.control_set_v1(9511,NULL,'mfg.material_waste',true,0::smallint,'{}',NULL,false,4,'Owner allows direct observations','waste_feature_resume');
SELECT core10.mfg_request_handoff_v1(9511,9521,:batch_id,'finance','waste_source_after') AS after_source \gset
SELECT mfg_waste_test.ok(jsonb_array_length(:'after_source'::jsonb->'source_envelope'->'material_waste_events')=5,'handoff includes five immutable observation sources');
SELECT mfg_waste_test.ok(:'after_source'::jsonb->'source_envelope'->>'source_fingerprint'<>:'before_source'::jsonb->'source_envelope'->>'source_fingerprint','new source snapshot fingerprint');
SELECT mfg_waste_test.ok(jsonb_array_length(core10.mfg_request_handoff_v1(9511,9521,:batch_id,'finance','waste_source_before')->'source_envelope'->'material_waste_events')=0,'old receipt retains original source snapshot');
SELECT mfg_waste_test.ok((:'after_source'::jsonb->'source_envelope'->'planning_cost'->>'estimated_total_cost')::numeric=1100,'waste does not add cost twice');
SELECT mfg_waste_test.ok((core10.verify_canonical_audit_v1(9511)->>'ok')::boolean,'canonical audit intact');
SELECT mfg_waste_test.expect('SELECT * FROM core10.mfg_material_waste_v1','permission denied');
SELECT mfg_waste_test.expect('SELECT core10._mfg_waste_events_v1(1)','permission denied');
-- All denied personas use the canonical authorization predicates; no new manufacturing grants.
DO $$ DECLARE actor text; BEGIN FOREACH actor IN ARRAY ARRAY[
 '95333333-3333-4333-8333-333333333333','95444444-4444-4444-8444-444444444444','95555555-5555-4555-8555-555555555555',
 '95666666-6666-4666-8666-666666666666','95777777-7777-4777-8777-777777777777','95888888-8888-4888-8888-888888888888'] LOOP
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',actor)::text,true);
 PERFORM mfg_waste_test.expect('SELECT core10.mfg_material_waste_report_v1(9511,9521,1)','MFG_SCOPE_DENIED');
 PERFORM mfg_waste_test.expect($q$SELECT core10.mfg_record_material_waste_v1(9511,9521,1,1,0.1,'SPILLAGE','FICTIONAL-MILK','Unauthorized waste entry','waste_denied_role')$q$,'MFG_SCOPE_DENIED');
END LOOP; END $$;
SELECT set_config('request.jwt.claims','{"sub":"95111111-1111-4111-8111-111111111111"}',true);
SELECT mfg_waste_test.expect(format('SELECT core10.mfg_material_waste_report_v1(9511,9524,%s)',:batch_id),'MFG_SCOPE_DENIED');
SELECT mfg_waste_test.expect(format('SELECT core10.mfg_material_waste_report_v1(9513,9523,%s)',:batch_id),'MFG_SCOPE_DENIED');
RESET ROLE;
SELECT mfg_waste_test.ok((SELECT count(*) FROM core10.mfg_material_waste_v1)=5,'no event duplicates or partial failures');
SELECT mfg_waste_test.ok((SELECT count(*) FROM core10.stock_movements WHERE business_id=9511)=0,'zero new stock movements');
SELECT mfg_waste_test.ok(NOT EXISTS(SELECT 1 FROM core10.mfg_material_waste_v1 w LEFT JOIN core10.canonical_audit_events_v1 a ON a.id=w.audit_event_id WHERE a.id IS NULL OR a.actor_id<>w.actor_id),'every observation has canonical evidence');
SELECT mfg_waste_test.expect('UPDATE core10.mfg_material_waste_v1 SET quantity=0.1','MFG_WASTE_IMMUTABLE');
SELECT mfg_waste_test.expect('DELETE FROM core10.mfg_material_waste_v1','MFG_WASTE_IMMUTABLE');
SELECT mfg_waste_test.expect('TRUNCATE core10.mfg_material_waste_v1','MFG_WASTE_IMMUTABLE');
\echo NP05A_MATERIAL_WASTE_OK
ROLLBACK;
