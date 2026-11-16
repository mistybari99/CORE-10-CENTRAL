-- Run AFTER canonical migrations 0001..0013 on a disposable PostgreSQL database.
-- Negative test: every TRUNCATE must reach our trigger and be refused (even for table owner).
-- No data is inserted or modified by this test. Run as the migration/schema owner.
DO $test$
DECLARE
  v_table text;
  v_blocked boolean;
  v_error text;
BEGIN
  FOREACH v_table IN ARRAY ARRAY['audit_chain_heads_v1','canonical_audit_events_v1','access_change_events_v1','approval_requests','approval_events','approval_policy_versions_v1','approval_routes_v1','approval_stage_receipts_v1','approval_delegations_v1'] LOOP
    v_blocked := false;
    BEGIN
      EXECUTE format('TRUNCATE TABLE core10.%I',v_table);
    EXCEPTION WHEN SQLSTATE '42501' THEN
      GET STACKED DIAGNOSTICS v_error = MESSAGE_TEXT;
      IF v_error NOT LIKE 'core10_journal_truncate_denied:%' THEN
        RAISE EXCEPTION 'B-005 did not reach expected guard on %: %', v_table, v_error;
      END IF;
      v_blocked := true;
    END;
    IF NOT v_blocked THEN
      RAISE EXCEPTION 'B-005 FAIL: TRUNCATE unexpectedly succeeded on %',v_table;
    END IF;
  END LOOP;
  RAISE NOTICE 'B-005 PASS: all protected journals reject TRUNCATE';
END
$test$;
