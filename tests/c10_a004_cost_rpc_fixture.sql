-- SYNTHETIC DATA ONLY. The fixture mirrors selected function signatures and
-- SECURITY DEFINER semantics, NOT the complete existing Islamia cost engine.
CREATE TABLE public._a004_cost_fixture (
 item_id uuid PRIMARY KEY,
 cost numeric(12,4) NOT NULL,
 recomputes integer NOT NULL DEFAULT 0
);
INSERT INTO public._a004_cost_fixture(item_id,cost)
VALUES('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',25.0000);
REVOKE ALL ON TABLE public._a004_cost_fixture FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public._cost_actual(p_item uuid)
RETURNS TABLE(cost numeric,src text) LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
 SELECT f.cost::numeric, 'fixture'::text
 FROM public._a004_cost_fixture f WHERE f.item_id=p_item
$function$;

CREATE OR REPLACE FUNCTION public._costx_recompute()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE n int;
BEGIN
 UPDATE public._a004_cost_fixture SET recomputes=recomputes+1;
 GET DIAGNOSTICS n=ROW_COUNT;
 RETURN n;
END
$function$;

-- Mimic the legitimate upper-layer SECURITY DEFINER business wrapper; checks
-- authoritative UUID context (synthetic), and internally invokes recompute.
-- This fixture validates nonbreaking SQL privilege chaining, not actual app E2E.
CREATE OR REPLACE FUNCTION public._a004_owner_cost_reprice()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
 IF current_setting('request.jwt.claim.sub',true)
       IS DISTINCT FROM '11111111-1111-4111-8111-111111111111'
 THEN
   RAISE EXCEPTION 'not_allowed';
 END IF;
 RETURN public._costx_recompute();
END
$function$;

REVOKE EXECUTE ON FUNCTION public._a004_owner_cost_reprice()
 FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._a004_owner_cost_reprice()
 TO authenticated;
GRANT EXECUTE ON FUNCTION public._cost_actual(uuid)
 TO PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public._costx_recompute()
 TO PUBLIC, anon, authenticated, service_role;
