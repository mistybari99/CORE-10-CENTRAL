\set ON_ERROR_STOP on
BEGIN;
\ir seed.sql
CREATE SCHEMA mfg_material_test;
GRANT USAGE ON SCHEMA mfg_material_test TO authenticated;
CREATE FUNCTION mfg_material_test.ok(p boolean,msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p IS NOT TRUE THEN RAISE EXCEPTION 'ASSERT_FAILED:%',msg; END IF; END $$;
CREATE FUNCTION mfg_material_test.expect(q text,e text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN BEGIN EXECUTE q; EXCEPTION WHEN OTHERS THEN
 IF SQLERRM LIKE e||'%' THEN RETURN; END IF; RAISE EXCEPTION 'WRONG_ERROR expected % got %',e,SQLERRM;
END; RAISE EXCEPTION 'MISSING_ERROR:%',e; END $$;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA mfg_material_test TO authenticated;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims','{"sub":"95111111-1111-4111-8111-111111111111"}',true);
SELECT core10.mfg_create_recipe_v1(9511,9521,9541,'MATERIALS',100,'fixture:piece',
 '[{"item":9542,"qty":10,"uom_ref":"fixture:kg","kind":"ingredient","waste_pct":2,"estimated_unit_cost":80},
 {"item":9543,"qty":2,"uom_ref":"fixture:kg","kind":"ingredient","waste_pct":1,"estimated_unit_cost":100},
 {"item":9544,"qty":10,"uom_ref":"fixture:piece","kind":"packaging","waste_pct":0,"estimated_unit_cost":5}]',50,'material_recipe_01') AS recipe \gset
SELECT (:'recipe'::jsonb->>'recipe_id')::bigint AS recipe_id \gset
-- These assertions run real draft functionality WITHOUT any Master adapter fixture.
SELECT core10.mfg_material_requirements_v1(9511,9521,:recipe_id,2) AS requirements \gset
SELECT mfg_material_test.ok((:'requirements'::jsonb->'lines'->0->>'quantity')::numeric=20,'20 kg milk required');
SELECT mfg_material_test.ok((:'requirements'::jsonb->'lines'->0->>'expected_waste_quantity')::numeric=0.4,'expected milk waste stays in kg');
SELECT mfg_material_test.ok((:'requirements'::jsonb->'lines'->0->>'expected_usable_quantity')::numeric=19.6,'gross input less expected loss');
SELECT mfg_material_test.ok(:'requirements'::jsonb->'lines'->0->>'sku'='QA-MILK','reuse canonical item identity');
SELECT mfg_material_test.ok(:'requirements'::jsonb->'lines'->0->'available_quantity'='null'::jsonb,'unknown stock is NULL not zero');
SELECT mfg_material_test.ok(:'requirements'::jsonb->'lines'->0->'shortage_quantity'='null'::jsonb,'no fabricated shortage');
SELECT mfg_material_test.ok((:'requirements'::jsonb->'lines'->2->>'quantity')::numeric=20,'20 packaging pieces separately');
SELECT mfg_material_test.ok((:'requirements'::jsonb->>'estimated_total_cost')::numeric=2200,'same A027 scaling and overhead');
SELECT mfg_material_test.ok(NOT (:'requirements'::jsonb ? 'total_quantity'),'never add kg to pieces');
SELECT mfg_material_test.expect(format('SELECT core10.mfg_material_requirements_v1(9511,9521,%s,0.0000001)',:recipe_id),'MFG_INVALID_MULTIPLIER');
SELECT mfg_material_test.expect(format('SELECT core10.mfg_material_requirements_v1(9511,9524,%s,1)',:recipe_id),'MFG_SCOPE_DENIED');
SELECT mfg_material_test.expect(format('SELECT core10._mfg_material_plan_v1(9511,9521,%s,1)',:recipe_id),'permission denied');
SELECT core10.control_set_v1(9511,NULL,'mfg.material_requirements',false,0::smallint,'{}',NULL,false,0,'Owner pauses material report','material_ctrl_off');
SELECT mfg_material_test.expect(format('SELECT core10.mfg_material_requirements_v1(9511,9521,%s,1)',:recipe_id),'CONTROL_DISABLED:mfg.material_requirements');
SELECT core10.control_set_v1(9511,NULL,'mfg.material_requirements',true,0::smallint,'{}',NULL,false,1,'Owner resumes material report','material_ctrl_on');
SELECT set_config('request.jwt.claims','{"sub":"95222222-2222-4222-8222-222222222222"}',true);
SELECT core10.control_set_v1(9511,NULL,'mfg.recipe_approve',true,0::smallint,'{}',NULL,false,0,'Synthetic direct approval','material_approve_control');
SELECT mfg_material_test.expect(format('SELECT core10.mfg_approve_recipe_v1(9511,9521,%s,now(),%L)',:recipe_id,'material_approve_bad'),'NOT_CONNECTED:MASTER_UOM');
RESET ROLE;
-- Remaining lifecycle uses the explicitly synthetic adapter, as in increment 1.
\ir master-fixture.sql
SET LOCAL ROLE authenticated;
SELECT core10.mfg_approve_recipe_v1(9511,9521,:recipe_id,now(),'material_approve_01');
SELECT set_config('request.jwt.claims','{"sub":"95111111-1111-4111-8111-111111111111"}',true);
SELECT core10.mfg_plan_batch_v1(9511,9521,:recipe_id,9531,1,'material_batch_01') AS batch \gset
SELECT (:'batch'::jsonb->>'batch_id')::bigint AS batch_id \gset
SELECT set_config('request.jwt.claims','{"sub":"95222222-2222-4222-8222-222222222222"}',true);
SELECT core10.control_set_v1(9511,NULL,'mfg.batch_release',true,0::smallint,'{}',NULL,false,0,'Synthetic direct release','material_release_control');
SELECT core10.mfg_release_batch_v1(9511,9521,:batch_id,'material_release_01');
SELECT core10.mfg_request_handoff_v1(9511,9521,:batch_id,'ingredients','material_issue_01') AS issue \gset
SELECT mfg_material_test.ok(:'issue'::jsonb->>'status'='NOT_CONNECTED','source request is not stock success');
SELECT mfg_material_test.ok(jsonb_array_length(:'issue'::jsonb->'source_envelope'->'lines')=3,'three source lines');
SELECT mfg_material_test.ok((:'issue'::jsonb->'source_envelope'->'lines'->0->>'quantity')::numeric=10,'planned ingredient quantity');
SELECT mfg_material_test.ok(:'issue'::jsonb->'source_envelope'->'lines'->0->'lot_ref'='null'::jsonb,'unallocated lot stays NULL');
SELECT mfg_material_test.ok(:'issue'::jsonb->'source_envelope'->'source'->'recipe_version'='1'::jsonb,'pinned recipe version');
SELECT mfg_material_test.ok(jsonb_array_length(:'issue'::jsonb->'source_envelope'->'source'->'batch_audit_event_ids')=2,'source plan and release Audit IDs');
SELECT mfg_material_test.ok(:'issue'::jsonb->'source_envelope'->>'source_fingerprint'=
 encode(sha256(convert_to(((:'issue'::jsonb->'source_envelope')-'source_fingerprint')::text,'UTF8')),'hex'),'source fingerprint covers every field');
SELECT core10.mfg_request_handoff_v1(9511,9521,:batch_id,'ingredients','material_issue_02') AS issue2 \gset
SELECT mfg_material_test.ok(:'issue'::jsonb->'source_envelope'=:'issue2'::jsonb->'source_envelope','equivalent source yields stable envelope');
SELECT mfg_material_test.ok(core10.mfg_request_handoff_v1(9511,9521,:batch_id,'ingredients','material_issue_01')->'source_envelope'=:'issue'::jsonb->'source_envelope','exact replay returns original source');
SELECT mfg_material_test.expect(format('SELECT core10.mfg_request_handoff_v1(9511,9521,%s,%L,%L)',:batch_id,'finance','material_issue_01'),'MFG_REPLAY_CONFLICT');
SELECT core10.mfg_record_output_v1(9511,9521,:batch_id,
 '{"good":95,"rejected":2,"rework":1,"loss":2,"reason":"PROCESS_LOSS","lot_ref":"FICTIONAL-MATERIAL-OUTPUT",
 "consumption":[{"line":1,"qty":10.5,"lot_ref":"FICTIONAL-MILK"},{"line":2,"qty":2,"lot_ref":"FICTIONAL-SUGAR"},
 {"line":3,"qty":10,"lot_ref":"FICTIONAL-BOX"}]}','material_output_01');
SELECT core10.mfg_request_handoff_v1(9511,9521,:batch_id,'finished_goods','material_receive_01') AS receipt \gset
SELECT mfg_material_test.ok((:'receipt'::jsonb->'source_envelope'->'lines'->0->>'quantity')::numeric=95,'only good output goes to receipt proposal');
SELECT mfg_material_test.ok(:'receipt'::jsonb->'source_envelope'->'lines'->0->>'lot_ref'='FICTIONAL-MATERIAL-OUTPUT','trace output lot');
SELECT mfg_material_test.ok((:'receipt'::jsonb->'source_envelope'->'observations'->>'loss')::numeric=2,'loss remains an observation');
SELECT core10.mfg_request_handoff_v1(9511,9521,:batch_id,'finance','material_finance_01') AS finance \gset
SELECT mfg_material_test.ok(:'finance'::jsonb->'source_envelope'->'planning_cost'->'recognized_value'='null'::jsonb,'no invented valuation');
SELECT mfg_material_test.ok(:'finance'::jsonb->'source_envelope'->'planning_cost'->'journal_entries'='null'::jsonb,'no fabricated GL entries');
SELECT mfg_material_test.ok(NOT (:'finance'::jsonb->>'financial_posted')::boolean,'finance remains disconnected');
-- Report switch does not become a hidden policy controlling otherwise permitted handoffs.
SELECT core10.control_set_v1(9511,NULL,'mfg.material_requirements',false,0::smallint,'{}',NULL,false,2,'Owner report paused again','material_ctrl_off2');
SELECT mfg_material_test.ok(core10.mfg_request_handoff_v1(9511,9521,:batch_id,'finance','material_finance_02')->>'status'='NOT_CONNECTED','independent read-only report switch');
-- A disabled feature's one-use canonical exception must be consumed exactly once, after locks.
SELECT core10.control_set_v1(9511,NULL,'mfg.handoff',false,0::smallint,'{}',NULL,false,0,'Owner pauses handoff','material_handoff_off');
SELECT core10.control_grant_override_v1(9511,9521,'mfg.handoff',1,'One synthetic source request','material_handoff_override');
SELECT mfg_material_test.ok(core10.mfg_request_handoff_v1(9511,9521,:batch_id,'finance','material_override_request')->>'status'='NOT_CONNECTED','one-use exception reaches guarded handoff');
SELECT mfg_material_test.expect(format('SELECT core10.mfg_request_handoff_v1(9511,9521,%s,%L,%L)',:batch_id,'finance','material_override_second'),'CONTROL_DISABLED');
RESET ROLE;
SELECT mfg_material_test.ok((SELECT count(*) FROM core10.control_overrides_v1 WHERE feature_key='mfg.handoff' AND consumed_at IS NOT NULL)=1,'one exception consumed once');
SET LOCAL ROLE authenticated;
SELECT mfg_material_test.ok((core10.verify_canonical_audit_v1(9511)->>'ok')::boolean,'canonical audit valid');
SELECT set_config('request.jwt.claims','{"sub":"95666666-6666-4666-8666-666666666666"}',true);
SELECT mfg_material_test.expect(format('SELECT core10.mfg_material_requirements_v1(9511,9521,%s,1)',:recipe_id),'MFG_SCOPE_DENIED');
RESET ROLE;
SELECT mfg_material_test.ok((SELECT count(*) FROM core10.stock_movements WHERE business_id=9511)=0,'no stock posting');
\echo NP05A_MATERIAL_HANDOFF_OK
ROLLBACK;
