-- NP01 / B-020 / 0114: all six previously fenced GOV002 RPCs must NOW be
-- direct-Control-bound, evidence promoted, authenticated-only. Also keep the
-- internal assertion and all anon/PUBLIC execution denied.
\set ON_ERROR_STOP on
DO $np01$
DECLARE sig text; name text; f text;
BEGIN
 FOR sig IN SELECT unnest(ARRAY[
 'core10.assess_approval_threshold_v1(bigint,jsonb)',
 'core10.assess_current_approval_threshold_v1(bigint,text,text,jsonb)',
 'core10.configure_approval_threshold_v1(bigint,text,text,numeric,integer,text)',
 'core10.request_approval_exception_v1(bigint,text,text,integer,text)',
 'core10.decide_approval_exception_v1(bigint,text,text)',
 'core10.withdraw_approval_exception_v1(bigint,text)'
 ]) LOOP
  name:=split_part(split_part(sig,'.',2),'(',1);
  f:=CASE WHEN name LIKE '%exception%' THEN 'gov002.review'
           ELSE 'gov002.approval_policy' END;
  IF NOT has_function_privilege('authenticated',sig,'EXECUTE') THEN
   RAISE EXCEPTION 'NP01_0114_AUTHENTICATED_GRANT_MISSING:%',sig; END IF;
  -- Bare disposable PG17 need not create the Supabase anon role. When
  -- present its permission remains strictly denied; PUBLIC is always checked.
  IF has_function_privilege('public',sig,'EXECUTE') THEN
   RAISE EXCEPTION 'NP01_0114_UNSAFE_PUBLIC_EXECUTE:%',sig; END IF;
  IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname='anon') THEN
   IF has_function_privilege('anon',sig,'EXECUTE') THEN
    RAISE EXCEPTION 'NP01_0114_UNSAFE_ANON_EXECUTE:%',sig; END IF;
  END IF;
  IF NOT EXISTS(SELECT 1 FROM core10.control_rpc_map_v1 m
    WHERE m.rpc_name=name AND m.feature_key=f AND m.status='enforced'
      AND m.test_ref='tests/migrations/np01-control-threshold-exception-e2e.sql')
  THEN RAISE EXCEPTION 'NP01_0114_REGISTRY_MISSING:%',name; END IF;
 END LOOP;
 IF has_function_privilege('authenticated','core10.assert_approval_threshold_v1(bigint,jsonb)','EXECUTE')
 THEN RAISE EXCEPTION 'NP01_0114_INTERNAL_ASSERT_EXPOSED'; END IF;
 RAISE NOTICE 'NP01_0114_ALL_6_DIRECT_CONTROL_ENFORCED';
END $np01$;
