-- SYNTHETIC. Mirrors _costx_pct(uuid) shape (SECURITY DEFINER, numeric) + a definer caller.
CREATE OR REPLACE FUNCTION public._costx_pct(p_item uuid) RETURNS numeric
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $f$ SELECT 7.5::numeric $f$;
GRANT EXECUTE ON FUNCTION public._costx_pct(uuid) TO PUBLIC, anon, authenticated, service_role;
CREATE OR REPLACE FUNCTION public._a004b_gap_wrapper() RETURNS numeric
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $f$ BEGIN RETURN public._costx_pct('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'); END $f$;
REVOKE EXECUTE ON FUNCTION public._a004b_gap_wrapper() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._a004b_gap_wrapper() TO authenticated;
