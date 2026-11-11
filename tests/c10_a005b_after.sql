\set ON_ERROR_STOP on
-- Direct calls denied for anon/authenticated; definer chains and service_role intact.
DO $t$ DECLARE r text; s text; BEGIN
 FOREACH r IN ARRAY ARRAY['anon','authenticated'] LOOP
  FOREACH s IN ARRAY ARRAY['public._xc_outlet_day(current_date,1)','public._xc_sold_day(1,current_date)','public._xc_rates90()','public.web_holds_expire()','public._web_rate91(''k'')'] LOOP
   EXECUTE format('SET LOCAL ROLE %I',r);
   BEGIN EXECUTE 'SELECT * FROM '||s; RAISE EXCEPTION 'LEAK_%_%',r,s;
   EXCEPTION WHEN insufficient_privilege THEN NULL; END;
   RESET ROLE;
  END LOOP;
 END LOOP;
END $t$;
-- Trigger functions: cannot be called directly anyway; ACL must be closed for roles.
DO $t$ DECLARE s text; BEGIN
 FOREACH s IN ARRAY ARRAY['_costx_item_costs','_costx_rules','_costx_snap','_costx_required','handle_new_user','entries_lock','sales_lock','_web_hold_sync91'] LOOP
  IF has_function_privilege('anon',('public.'||s||'()')::regprocedure,'EXECUTE') OR has_function_privilege('authenticated',('public.'||s||'()')::regprocedure,'EXECUTE')
   THEN RAISE EXCEPTION 'TRIGGER_FN_EXPOSED_%',s; END IF;
 END LOOP;
END $t$;
-- SECURITY DEFINER trigger chain fired by an authenticated INSERT still works.
SET ROLE authenticated;
INSERT INTO public.a005b_t  VALUES (1,'x');   -- 8 definer trigger fns fire with EXECUTE revoked
INSERT INTO public.a005b_t2 VALUES (1,'x');   -- definer trigger -> definer caller -> revoked helpers
INSERT INTO public.a005b_t4 VALUES (1,'x');   -- invoker trigger fn with no restricted dependency still fires
DO $t$ BEGIN IF public.a005b_caller_definer() IS DISTINCT FROM 0 THEN RAISE EXCEPTION 'DEFINER_CALLER_BROKEN'; END IF; END $t$;
-- NEGATIVE CONTROL: an INVOKER function (trigger or plain) depending on a revoked helper MUST fail.
DO $t$ BEGIN
 BEGIN INSERT INTO public.a005b_t3 VALUES (1,'x'); RAISE EXCEPTION 'NEGATIVE_CONTROL_TRIGGER_DID_NOT_FAIL';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM public.a005b_caller_invoker(); RAISE EXCEPTION 'NEGATIVE_CONTROL_CALLER_DID_NOT_FAIL';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $t$;
RESET ROLE;
SET ROLE service_role;
SELECT public.web_holds_expire(); SELECT public._xc_outlet_day(current_date,1); SELECT * FROM public._xc_rates90();
RESET ROLE;
\echo PASS: A005b direct anon/authenticated denied; definer trigger chain, definer callers and service_role intact; invoker negative control fails as expected
