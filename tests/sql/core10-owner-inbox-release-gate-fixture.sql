-- ISOLATED CI ONLY. Never run on IMG-ERP-SG.
-- Adds production-like RLS flags and grant boundaries to the disposable fixture.
CREATE FUNCTION public._org_on123() RETURNS boolean
 LANGUAGE sql STABLE AS $fn$ SELECT true $fn$;
ALTER FUNCTION public._business_of_loc123(integer) SECURITY DEFINER;
ALTER FUNCTION public._business_of_unit123(bigint) SECURITY DEFINER;
REVOKE ALL ON FUNCTION public._business_of_loc123(integer) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public._business_of_unit123(bigint) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.is_owner() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.is_owner() TO authenticated;
DO $fixture$
DECLARE t text;
BEGIN
 FOREACH t IN ARRAY ARRAY['org_units','profiles','user_roles','locations','entries',
   'release_requests','entry_change_requests','exceptions','emergency_requests',
   'pay_requests','wastage_requests','item_changes']
 LOOP
   EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY',t);
 END LOOP;
END $fixture$;
