-- C10-A004 ROLLBACK for security/c10_a004_cost_rpc_acl_candidate.sql
-- Restores the EXACT pre-patch ACL observed read-only on IMG-ERP-SG, 2026-11-10:
--   {=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}
-- ACL-only; no function body, data or schema change. Safe to run repeatedly.
BEGIN;
GRANT EXECUTE ON FUNCTION public._cost_actual(uuid)
  TO PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public._costx_recompute()
  TO PUBLIC, anon, authenticated, service_role;
COMMIT;
