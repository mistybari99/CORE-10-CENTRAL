-- C10-A005b ROLLBACK: restores the exact pre-ACL read from live proacl (SELECT-only, 2026-11-10).
-- Group 1 (4 _costx_* trigger fns): {=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}
-- Group 2 (other 9):                {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
BEGIN;
GRANT EXECUTE ON FUNCTION public._costx_item_costs() TO PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public._costx_rules() TO PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public._costx_snap() TO PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public._costx_required() TO PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.handle_new_user() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.entries_lock() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.sales_lock() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public._web_hold_sync91() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public._xc_outlet_day(date,integer) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public._xc_sold_day(integer,date) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public._xc_rates90() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.web_holds_expire() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public._web_rate91(text) TO authenticated, service_role;
COMMIT;
