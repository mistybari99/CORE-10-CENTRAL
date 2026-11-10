-- CORE-10-CENTRAL / C10-A004
-- CANDIDATE ONLY: review + isolated CI; do NOT execute against live IMG-ERP-SG
-- without a verified backup/rollback plan, real signed-JWT staging tests and owner release sign-off.
--
-- Goal: deny DIRECT REST/RPC invocation of two unguarded internal costing
-- SECURITY DEFINER functions while leaving the authorized owner-function chain intact.
-- Live read-only finding on 2026-11-10:
--   public._cost_actual(uuid) exposes underlying cost calculations without a caller guard.
--   public._costx_recompute() performs cost-table writes without a caller guard.
-- Both were EXECUTE-accessible by PUBLIC/anon/authenticated/service_role.
--
-- Intentional compatibility constraints:
--   No changing function bodies, definitions, arguments, stock/cost tables,
--   owner roles, recipe logic, IDs, records, current RLS policies or org_scope_on.
--   No broad REVOKE on other ERP functions or public customer-web RPC endpoints.
--   service_role and database-owner execution remains intact.
--
-- Note: This staged ACL closes these two direct invocation paths only.
-- It does not certify all cost-related RPCs, all indirect entry points or tenant isolation.
BEGIN;
DO $verify$
BEGIN
  IF to_regprocedure('public._cost_actual(uuid)') IS NULL OR
     to_regprocedure('public._costx_recompute()') IS NULL THEN
    RAISE EXCEPTION 'C10_A004_TARGET_RPC_NOT_FOUND';
  END IF;
  IF EXISTS(
    SELECT 1 FROM pg_proc p
    WHERE p.oid IN ('public._cost_actual(uuid)'::regprocedure,
                    'public._costx_recompute()'::regprocedure)
      AND NOT p.prosecdef
  ) THEN
    RAISE EXCEPTION 'C10_A004_TARGET_DEFINITION_DRIFT';
  END IF;
END
$verify$;

REVOKE EXECUTE ON FUNCTION public._cost_actual(uuid)
  FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public._costx_recompute()
  FROM PUBLIC, anon, authenticated;

-- Preserve machine-service compatibility, as confirmed by existing live grants.
GRANT EXECUTE ON FUNCTION public._cost_actual(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public._costx_recompute() TO service_role;

DO $verify_acl$
BEGIN
  IF has_function_privilege('anon','public._cost_actual(uuid)','EXECUTE') OR
     has_function_privilege('authenticated','public._cost_actual(uuid)','EXECUTE') OR
     has_function_privilege('anon','public._costx_recompute()','EXECUTE') OR
     has_function_privilege('authenticated','public._costx_recompute()','EXECUTE') THEN
    RAISE EXCEPTION 'C10_A004_UNTRUSTED_DIRECT_EXECUTE_REMAINS';
  END IF;
  IF NOT has_function_privilege('service_role','public._cost_actual(uuid)','EXECUTE') OR
     NOT has_function_privilege('service_role','public._costx_recompute()','EXECUTE') THEN
    RAISE EXCEPTION 'C10_A004_SERVICE_PRIVILEGE_REGRESSION';
  END IF;
END
$verify_acl$;
COMMIT;
