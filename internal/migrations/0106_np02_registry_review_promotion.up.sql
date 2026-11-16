-- NP02 / B-023 / 0106: evidence-based registry promotion for the NP01 review bindings (ChatGPT 0019).
-- Promotes only where the RPC calls control_check_v1 for gov002.review; otherwise the rows stay pending.
-- Proof test: tests/migrations/np01-control-decision-e2e.sql (CONTROL_DISABLED on decide and withdraw when off).
DO $$
BEGIN
 RAISE NOTICE 'registry decide_approval: %',
  core10._control_registry_promote_v1('decide_approval', 'tests/migrations/np01-control-decision-e2e.sql');
 RAISE NOTICE 'registry withdraw_typed_approval_v1: %',
  core10._control_registry_promote_v1('withdraw_typed_approval_v1', 'tests/migrations/np01-control-decision-e2e.sql');
END $$;
