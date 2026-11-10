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

-- ---------------------------------------------------------------------------
-- Trigger-path fixture (mirrors the REAL live shape found by read-only catalog
-- trace on 2026-11-10): the only DB-side callers of the two helpers are
-- SECURITY DEFINER functions owned by the DB owner:
--   _costx_rules()  trigger fn (settings row change) -> _costx_recompute()
--   _costx_snap()   trigger fn (sale insert)         -> _cost_actual()
--   cost_extra_*_set / cost_gap_items public wrappers (guarded by _costx_ok)
-- No view, policy or pg_cron job references either helper.
-- An authenticated user fires these triggers by writing ordinary rows; the
-- definer chain must keep working after authenticated loses direct EXECUTE.
-- ---------------------------------------------------------------------------
CREATE TABLE public._a004_settings(key text PRIMARY KEY, value text);
CREATE TABLE public._a004_sales(id int PRIMARY KEY, item_id uuid, snap_cost numeric);
GRANT SELECT, INSERT, UPDATE ON public._a004_settings TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public._a004_sales TO authenticated;

CREATE OR REPLACE FUNCTION public._a004_rules_trg()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
 IF NEW.key='cost_extra_on' AND (TG_OP='INSERT' OR NEW.value IS DISTINCT FROM OLD.value) THEN
   PERFORM public._costx_recompute();
 END IF;
 RETURN NEW;
END
$function$;
CREATE TRIGGER a004_rules AFTER INSERT OR UPDATE ON public._a004_settings
 FOR EACH ROW EXECUTE FUNCTION public._a004_rules_trg();

CREATE OR REPLACE FUNCTION public._a004_snap_trg()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
 UPDATE public._a004_sales s
    SET snap_cost=(SELECT a.cost FROM public._cost_actual(NEW.item_id) a)
  WHERE s.id=NEW.id;
 RETURN NULL;
END
$function$;
CREATE TRIGGER a004_snap AFTER INSERT ON public._a004_sales
 FOR EACH ROW EXECUTE FUNCTION public._a004_snap_trg();
