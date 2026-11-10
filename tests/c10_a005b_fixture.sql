-- SYNTHETIC fixture mirroring live shapes/ACLs of the 13 A005b functions (all SECURITY DEFINER, owner = current superuser).
CREATE TABLE public.a005b_t  (id int PRIMARY KEY, v text);
CREATE TABLE public.a005b_t2 (id int PRIMARY KEY, v text);   -- definer trigger that calls a revoked helper
CREATE TABLE public.a005b_t3 (id int PRIMARY KEY, v text);   -- INVOKER trigger that calls a revoked helper (negative control)
CREATE TABLE public.a005b_t4 (id int PRIMARY KEY, v text);   -- INVOKER trigger that calls nothing restricted
CREATE FUNCTION public._costx_item_costs() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $f$ BEGIN RETURN NEW; END $f$;
CREATE TRIGGER trg__costx_item_costs BEFORE INSERT ON public.a005b_t FOR EACH ROW EXECUTE FUNCTION public._costx_item_costs();
CREATE FUNCTION public._costx_rules() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $f$ BEGIN RETURN NEW; END $f$;
CREATE TRIGGER trg__costx_rules BEFORE INSERT ON public.a005b_t FOR EACH ROW EXECUTE FUNCTION public._costx_rules();
CREATE FUNCTION public._costx_snap() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $f$ BEGIN RETURN NEW; END $f$;
CREATE TRIGGER trg__costx_snap BEFORE INSERT ON public.a005b_t FOR EACH ROW EXECUTE FUNCTION public._costx_snap();
CREATE FUNCTION public._costx_required() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $f$ BEGIN RETURN NEW; END $f$;
CREATE TRIGGER trg__costx_required BEFORE INSERT ON public.a005b_t FOR EACH ROW EXECUTE FUNCTION public._costx_required();
CREATE FUNCTION public.handle_new_user() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $f$ BEGIN RETURN NEW; END $f$;
CREATE TRIGGER trg_handle_new_user BEFORE INSERT ON public.a005b_t FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
CREATE FUNCTION public.entries_lock() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $f$ BEGIN RETURN NEW; END $f$;
CREATE TRIGGER trg_entries_lock BEFORE INSERT ON public.a005b_t FOR EACH ROW EXECUTE FUNCTION public.entries_lock();
CREATE FUNCTION public.sales_lock() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $f$ BEGIN RETURN NEW; END $f$;
CREATE TRIGGER trg_sales_lock BEFORE INSERT ON public.a005b_t FOR EACH ROW EXECUTE FUNCTION public.sales_lock();
CREATE FUNCTION public._web_hold_sync91() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $f$ BEGIN RETURN NEW; END $f$;
CREATE TRIGGER trg__web_hold_sync91 BEFORE INSERT ON public.a005b_t FOR EACH ROW EXECUTE FUNCTION public._web_hold_sync91();
CREATE FUNCTION public._xc_outlet_day(p_day date, p_loc integer) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path TO 'public' AS $f$ SELECT '{"sales":42}'::jsonb $f$;
CREATE FUNCTION public._xc_sold_day(p_loc integer, p_day date) RETURNS TABLE(item_id uuid, qty numeric) LANGUAGE sql SECURITY DEFINER SET search_path TO 'public' AS $f$ SELECT 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid, 3::numeric $f$;
CREATE FUNCTION public._xc_rates90() RETURNS TABLE(item_id uuid, supplier text, dt date, rate numeric, qty numeric, ord text) LANGUAGE sql SECURITY DEFINER SET search_path TO 'public' AS $f$ SELECT 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid,'s',current_date,9::numeric,1::numeric,'o' $f$;
CREATE FUNCTION public.web_holds_expire() RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $f$ BEGIN RETURN 0; END $f$;
CREATE FUNCTION public._web_rate91(p_key text) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $f$ BEGIN RETURN true; END $f$;
-- pre-patch ACLs as read live
GRANT EXECUTE ON FUNCTION public._costx_item_costs() TO PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public._costx_rules() TO PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public._costx_snap() TO PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public._costx_required() TO PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.handle_new_user() TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.entries_lock() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.entries_lock() TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.sales_lock() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.sales_lock() TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public._web_hold_sync91() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._web_hold_sync91() TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public._xc_outlet_day(date,integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._xc_outlet_day(date,integer) TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public._xc_sold_day(integer,date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._xc_sold_day(integer,date) TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public._xc_rates90() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._xc_rates90() TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.web_holds_expire() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.web_holds_expire() TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public._web_rate91(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._web_rate91(text) TO authenticated, service_role;

-- callers
CREATE FUNCTION public.a005b_caller_definer() RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $f$
BEGIN PERFORM public._xc_outlet_day(current_date,1); PERFORM * FROM public._xc_sold_day(1,current_date); PERFORM * FROM public._xc_rates90();
 PERFORM public._web_rate91('k'); RETURN public.web_holds_expire(); END $f$;
CREATE FUNCTION public.a005b_caller_invoker() RETURNS integer LANGUAGE plpgsql SECURITY INVOKER SET search_path TO 'public' AS $f$
BEGIN RETURN public.web_holds_expire(); END $f$;
CREATE FUNCTION public.a005b_t2_trg() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $f$
BEGIN PERFORM public.a005b_caller_definer(); PERFORM * FROM public._xc_rates90(); RETURN NEW; END $f$;
CREATE TRIGGER trg2 BEFORE INSERT ON public.a005b_t2 FOR EACH ROW EXECUTE FUNCTION public.a005b_t2_trg();
CREATE FUNCTION public.a005b_t3_trg() RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path TO 'public' AS $f$
BEGIN PERFORM public.web_holds_expire(); RETURN NEW; END $f$;
CREATE TRIGGER trg3 BEFORE INSERT ON public.a005b_t3 FOR EACH ROW EXECUTE FUNCTION public.a005b_t3_trg();
CREATE FUNCTION public.a005b_t4_trg() RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path TO 'public' AS $f$ BEGIN RETURN NEW; END $f$;
CREATE TRIGGER trg4 BEFORE INSERT ON public.a005b_t4 FOR EACH ROW EXECUTE FUNCTION public.a005b_t4_trg();
REVOKE EXECUTE ON FUNCTION public.a005b_caller_definer(), public.a005b_caller_invoker(), public.a005b_t2_trg(), public.a005b_t3_trg(), public.a005b_t4_trg() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.a005b_caller_definer(), public.a005b_caller_invoker() TO authenticated;
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
GRANT INSERT, SELECT ON public.a005b_t, public.a005b_t2, public.a005b_t3, public.a005b_t4 TO authenticated;
-- snapshot of pre-patch ACLs for the rollback check
CREATE TABLE public.a005b_acl_snapshot AS SELECT p.oid::regprocedure::text AS sig, p.proacl::text AS acl FROM pg_proc p WHERE p.pronamespace='public'::regnamespace AND p.proname IN ('_costx_item_costs','_costx_rules','_costx_snap','_costx_required','handle_new_user','entries_lock','sales_lock','_web_hold_sync91','_xc_outlet_day','_xc_sold_day','_xc_rates90','web_holds_expire','_web_rate91');
