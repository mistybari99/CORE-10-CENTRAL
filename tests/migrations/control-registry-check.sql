-- NP02 / B-010: DEC-08 registry gate. Run after all migrations are applied.
-- A function that changes state is VOLATILE (PostgreSQL refuses writes inside a STABLE function),
-- so "VOLATILE and executable by authenticated" is a rule a pack cannot bypass by naming.
-- Every such RPC must be registered in core10.control_rpc_map_v1 as enforced, exempt or pending.
\set ON_ERROR_STOP on
DO $chk$
DECLARE bad text; n_all int; n_enf int; n_ex int; n_pen int;
BEGIN
 SELECT string_agg(DISTINCT p.proname, ', ' ORDER BY p.proname) INTO bad
 FROM pg_proc p WHERE p.pronamespace='core10'::regnamespace AND p.proname !~ '^_'
  AND p.provolatile='v' AND has_function_privilege('authenticated', p.oid, 'execute')
  AND NOT EXISTS (SELECT 1 FROM core10.control_rpc_map_v1 m WHERE m.rpc_name=p.proname);
 IF bad IS NOT NULL THEN
  RAISE EXCEPTION 'UNMAPPED_STATE_CHANGING_RPC (register in core10.control_rpc_map_v1 with a catalog feature): %', bad;
 END IF;

 SELECT string_agg(m.rpc_name, ', ' ORDER BY m.rpc_name) INTO bad FROM core10.control_rpc_map_v1 m
 WHERE NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.pronamespace='core10'::regnamespace AND p.proname=m.rpc_name
                   AND p.provolatile='v' AND has_function_privilege('authenticated', p.oid, 'execute'));
 IF bad IS NOT NULL THEN RAISE EXCEPTION 'STALE_RPC_MAP_ROW (no such state-changing RPC): %', bad; END IF;

 -- enforced = the RPC calls control_check_v1 with exactly its mapped feature key, and names its proof test
 SELECT string_agg(m.rpc_name, ', ' ORDER BY m.rpc_name) INTO bad FROM core10.control_rpc_map_v1 m
 WHERE m.status='enforced' AND (m.test_ref IS NULL OR NOT core10._control_rpc_calls_check_v1(m.rpc_name, m.feature_key));
 IF bad IS NOT NULL THEN RAISE EXCEPTION 'ENFORCED_RPC_DOES_NOT_CALL_CONTROL_CHECK: %', bad; END IF;

 -- pending rows that already carry the evidence are reported (promote them in a post-0102 migration)
 SELECT string_agg(m.rpc_name, ', ' ORDER BY m.rpc_name) INTO bad FROM core10.control_rpc_map_v1 m
 WHERE m.status='pending' AND core10._control_rpc_calls_check_v1(m.rpc_name, m.feature_key);
 IF bad IS NOT NULL THEN RAISE NOTICE 'PROMOTE_READY (calls the check; add the proof test and promote): %', bad; END IF;

 -- no callable core10 function for anon or PUBLIC
 SELECT string_agg(DISTINCT p.proname, ', ') INTO bad FROM pg_proc p
 WHERE p.pronamespace='core10'::regnamespace
  AND (has_function_privilege('anon', p.oid, 'execute') OR has_function_privilege('public', p.oid, 'execute'));
 IF bad IS NOT NULL THEN RAISE EXCEPTION 'FUNCTION_EXECUTABLE_BY_ANON_OR_PUBLIC: %', bad; END IF;

 -- internal Control functions stay internal
 IF has_function_privilege('authenticated','core10.control_check_v1(bigint,text,bigint)','execute') THEN
  RAISE EXCEPTION 'CONTROL_CHECK_MUST_BE_INTERNAL';
 END IF;

 -- invariants are never switchable; every non-invariant feature has bilingual titles
 IF EXISTS (SELECT 1 FROM core10.control_catalog_v1 WHERE invariant AND (max_stages<>0 OR NOT default_enabled)) THEN
  RAISE EXCEPTION 'INVARIANT_CATALOG_ROW_SWITCHABLE';
 END IF;
 IF NOT EXISTS (SELECT 1 FROM core10.control_catalog_v1 WHERE invariant AND feature_key='audit.immutability') THEN
  RAISE EXCEPTION 'AUDIT_INVARIANT_MISSING';
 END IF;

 SELECT count(*) INTO n_all FROM core10.control_rpc_map_v1;
 SELECT count(*) FILTER (WHERE status='enforced'), count(*) FILTER (WHERE status='exempt'),
        count(*) FILTER (WHERE status='pending') INTO n_enf, n_ex, n_pen FROM core10.control_rpc_map_v1;
 RAISE NOTICE 'PASS CONTROL REGISTRY: % state-changing RPCs registered: % enforced, % exempt, % pending (pending is tracked debt with a board row)', n_all, n_enf, n_ex, n_pen;
END $chk$;
