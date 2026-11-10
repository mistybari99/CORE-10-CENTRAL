-- C10-A004b CANDIDATE ONLY (not applied). Same pattern as the applied A004 pair.
-- public._costx_pct(uuid): unguarded internal cost-markup helper, executable by anon/authenticated.
-- All 5 live callers (_costx_item_costs, cost_base_map, _costx_snap, cost_gap_items, _costx_recompute)
-- are SECURITY DEFINER owned by postgres; no view/policy references it (SELECT-only trace 2026-11-10).
BEGIN;
DO $v$ BEGIN
  IF to_regprocedure('public._costx_pct(uuid)') IS NULL THEN RAISE EXCEPTION 'C10_A004B_TARGET_NOT_FOUND'; END IF;
  IF NOT (SELECT prosecdef FROM pg_proc WHERE oid='public._costx_pct(uuid)'::regprocedure) THEN
    -- invoker helper is still safe to restrict only if callers are definer; verified above, keep guard on drift
    RAISE EXCEPTION 'C10_A004B_TARGET_DEFINITION_DRIFT'; END IF;
END $v$;
REVOKE EXECUTE ON FUNCTION public._costx_pct(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._costx_pct(uuid) TO service_role;
COMMIT;
