-- C10-A005b CANDIDATE ONLY (NOT APPLIED to production). Owner go/no-go + backup/rollback required.
-- Revokes direct EXECUTE from PUBLIC/anon/authenticated on 13 internal functions; keeps owner (postgres) and service_role.
-- Caller trace (SELECT-only, 2026-11-10): see PR body. Summary:
--  * 8 trigger functions: Postgres checks EXECUTE only at CREATE TRIGGER, never at fire time; no JS/RPC/view/policy use.
--  * _xc_outlet_day/_xc_sold_day/_xc_rates90/_web_rate91/web_holds_expire: only callers are SECURITY DEFINER (owner postgres)
--    functions (xc_*, web_checkout_submit, web_custom_request, web_order_cancel_request) and pg_cron job 1 (user postgres).
--    No browser JS calls them (repo grep: none).
BEGIN;
DO $v$ DECLARE s text; BEGIN
  FOREACH s IN ARRAY ARRAY['public._costx_item_costs()','public._costx_rules()','public._costx_snap()','public._costx_required()','public.handle_new_user()','public.entries_lock()','public.sales_lock()','public._web_hold_sync91()','public._xc_outlet_day(date,integer)','public._xc_sold_day(integer,date)','public._xc_rates90()','public.web_holds_expire()','public._web_rate91(text)'] LOOP
    IF to_regprocedure(s) IS NULL THEN RAISE EXCEPTION 'C10_A005B_TARGET_NOT_FOUND %', s; END IF;
    IF NOT (SELECT prosecdef FROM pg_proc WHERE oid=to_regprocedure(s)) THEN RAISE EXCEPTION 'C10_A005B_TARGET_NOT_DEFINER %', s; END IF;
  END LOOP;
END $v$;
REVOKE EXECUTE ON FUNCTION public._costx_item_costs() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._costx_item_costs() TO service_role;
REVOKE EXECUTE ON FUNCTION public._costx_rules() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._costx_rules() TO service_role;
REVOKE EXECUTE ON FUNCTION public._costx_snap() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._costx_snap() TO service_role;
REVOKE EXECUTE ON FUNCTION public._costx_required() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._costx_required() TO service_role;
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.handle_new_user() TO service_role;
REVOKE EXECUTE ON FUNCTION public.entries_lock() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.entries_lock() TO service_role;
REVOKE EXECUTE ON FUNCTION public.sales_lock() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.sales_lock() TO service_role;
REVOKE EXECUTE ON FUNCTION public._web_hold_sync91() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._web_hold_sync91() TO service_role;
REVOKE EXECUTE ON FUNCTION public._xc_outlet_day(date,integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._xc_outlet_day(date,integer) TO service_role;
REVOKE EXECUTE ON FUNCTION public._xc_sold_day(integer,date) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._xc_sold_day(integer,date) TO service_role;
REVOKE EXECUTE ON FUNCTION public._xc_rates90() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._xc_rates90() TO service_role;
REVOKE EXECUTE ON FUNCTION public.web_holds_expire() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.web_holds_expire() TO service_role;
REVOKE EXECUTE ON FUNCTION public._web_rate91(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._web_rate91(text) TO service_role;
DO $v$ DECLARE s text; BEGIN
  FOREACH s IN ARRAY ARRAY['public._costx_item_costs()','public._costx_rules()','public._costx_snap()','public._costx_required()','public.handle_new_user()','public.entries_lock()','public.sales_lock()','public._web_hold_sync91()','public._xc_outlet_day(date,integer)','public._xc_sold_day(integer,date)','public._xc_rates90()','public.web_holds_expire()','public._web_rate91(text)'] LOOP
    IF has_function_privilege('anon', to_regprocedure(s), 'EXECUTE') OR has_function_privilege('authenticated', to_regprocedure(s), 'EXECUTE')
       OR EXISTS (SELECT 1 FROM pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f',p.proowner))) a WHERE p.oid=to_regprocedure(s) AND a.grantee=0 AND a.privilege_type='EXECUTE')
    THEN RAISE EXCEPTION 'C10_A005B_STILL_EXPOSED %', s; END IF;
    IF NOT has_function_privilege('service_role', to_regprocedure(s), 'EXECUTE') THEN RAISE EXCEPTION 'C10_A005B_SERVICE_LOST %', s; END IF;
    IF NOT has_function_privilege('postgres', to_regprocedure(s), 'EXECUTE') THEN RAISE EXCEPTION 'C10_A005B_OWNER_LOST %', s; END IF;
  END LOOP;
END $v$;
COMMIT;
