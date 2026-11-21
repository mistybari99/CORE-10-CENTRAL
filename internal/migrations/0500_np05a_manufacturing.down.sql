-- Only an empty, unapplied-to-business increment may roll back. Audit and Control history are preserved.
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM core10.bom_recipes_v1) OR EXISTS(SELECT 1 FROM core10.production_batches_v1)
 OR EXISTS(SELECT 1 FROM core10.mfg_command_receipts_v1)
 OR EXISTS(SELECT 1 FROM core10.control_setting_versions_v1 WHERE feature_key LIKE 'mfg.%')
 OR EXISTS(SELECT 1 FROM core10.control_overrides_v1 WHERE feature_key LIKE 'mfg.%')
 THEN RAISE EXCEPTION 'MFG_ROLLBACK_HAS_HISTORY'; END IF;
END $$;
DELETE FROM core10.control_rpc_map_v1 WHERE lane='Codex Build 4' AND board_row='B-015';
DELETE FROM core10.control_catalog_v1 WHERE feature_key LIKE 'mfg.%';
DO $$ DECLARE f record; BEGIN FOR f IN SELECT oid::regprocedure AS signature FROM pg_proc WHERE pronamespace='core10'::regnamespace AND proname='mfg_create_recipe_v1' LOOP EXECUTE format('DROP FUNCTION %s',f.signature); END LOOP; END $$;
DO $$ DECLARE f record; BEGIN FOR f IN SELECT oid::regprocedure AS signature FROM pg_proc WHERE pronamespace='core10'::regnamespace AND proname='mfg_approve_recipe_v1' LOOP EXECUTE format('DROP FUNCTION %s',f.signature); END LOOP; END $$;
DO $$ DECLARE f record; BEGIN FOR f IN SELECT oid::regprocedure AS signature FROM pg_proc WHERE pronamespace='core10'::regnamespace AND proname='mfg_plan_batch_v1' LOOP EXECUTE format('DROP FUNCTION %s',f.signature); END LOOP; END $$;
DO $$ DECLARE f record; BEGIN FOR f IN SELECT oid::regprocedure AS signature FROM pg_proc WHERE pronamespace='core10'::regnamespace AND proname='mfg_release_batch_v1' LOOP EXECUTE format('DROP FUNCTION %s',f.signature); END LOOP; END $$;
DO $$ DECLARE f record; BEGIN FOR f IN SELECT oid::regprocedure AS signature FROM pg_proc WHERE pronamespace='core10'::regnamespace AND proname='mfg_record_output_v1' LOOP EXECUTE format('DROP FUNCTION %s',f.signature); END LOOP; END $$;
DO $$ DECLARE f record; BEGIN FOR f IN SELECT oid::regprocedure AS signature FROM pg_proc WHERE pronamespace='core10'::regnamespace AND proname='mfg_cancel_batch_v1' LOOP EXECUTE format('DROP FUNCTION %s',f.signature); END LOOP; END $$;
DO $$ DECLARE f record; BEGIN FOR f IN SELECT oid::regprocedure AS signature FROM pg_proc WHERE pronamespace='core10'::regnamespace AND proname='mfg_request_handoff_v1' LOOP EXECUTE format('DROP FUNCTION %s',f.signature); END LOOP; END $$;
DO $$ DECLARE f record; BEGIN FOR f IN SELECT oid::regprocedure AS signature FROM pg_proc WHERE pronamespace='core10'::regnamespace AND proname='mfg_inspect_v1' LOOP EXECUTE format('DROP FUNCTION %s',f.signature); END LOOP; END $$;
DO $$ DECLARE f record; BEGIN FOR f IN SELECT oid::regprocedure AS signature FROM pg_proc WHERE pronamespace='core10'::regnamespace AND proname='_mfg_receipt_v1' LOOP EXECUTE format('DROP FUNCTION %s',f.signature); END LOOP; END $$;
DO $$ DECLARE f record; BEGIN FOR f IN SELECT oid::regprocedure AS signature FROM pg_proc WHERE pronamespace='core10'::regnamespace AND proname='_mfg_replay_v1' LOOP EXECUTE format('DROP FUNCTION %s',f.signature); END LOOP; END $$;
DO $$ DECLARE f record; BEGIN FOR f IN SELECT oid::regprocedure AS signature FROM pg_proc WHERE pronamespace='core10'::regnamespace AND proname='_mfg_scope_v1' LOOP EXECUTE format('DROP FUNCTION %s',f.signature); END LOOP; END $$;
DO $$ DECLARE f record; BEGIN FOR f IN SELECT oid::regprocedure AS signature FROM pg_proc WHERE pronamespace='core10'::regnamespace AND proname='_mfg_master_check_v1' LOOP EXECUTE format('DROP FUNCTION %s',f.signature); END LOOP; END $$;
DROP TABLE core10.mfg_command_receipts_v1;
DROP TABLE core10.production_batches_v1;
DROP TABLE core10.bom_ingredients_v1;
DROP TABLE core10.bom_recipes_v1;
DROP FUNCTION core10._mfg_line_insert_guard_v1();
DROP FUNCTION core10._mfg_line_guard_v1();
DROP FUNCTION core10._mfg_recipe_guard_v1();
