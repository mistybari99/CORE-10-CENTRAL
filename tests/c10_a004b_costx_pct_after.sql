DO $t$ DECLARE r text; BEGIN
 FOREACH r IN ARRAY ARRAY['anon','authenticated'] LOOP
  EXECUTE format('SET LOCAL ROLE %I',r);
  BEGIN PERFORM public._costx_pct('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
   RAISE EXCEPTION 'LEAK_%',r;
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  RESET ROLE;
 END LOOP;
 SET LOCAL ROLE authenticated;
 IF public._a004b_gap_wrapper() IS DISTINCT FROM 7.5 THEN RAISE EXCEPTION 'DEFINER_CHAIN_BROKEN'; END IF;
 RESET ROLE; SET LOCAL ROLE service_role;
 IF public._costx_pct('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') IS DISTINCT FROM 7.5 THEN RAISE EXCEPTION 'SERVICE_BROKEN'; END IF;
END $t$;
\echo PASS: A004b _costx_pct direct anon/auth denied, definer chain and service_role intact
