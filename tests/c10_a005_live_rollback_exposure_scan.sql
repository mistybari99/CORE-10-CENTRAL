-- C10-A005 live exposure scan. Runs INSIDE ONE TRANSACTION that always ROLLS BACK
-- (final RAISE EXCEPTION carries the report). Leaves NO users, rows or audit entries.
-- Creates synthetic login-less auth users (no password) only inside the transaction.
-- For each persona (anon / pending user / active user with zero roles) reports every
-- public table or view where that persona can SEE at least one row.
-- Limits: SQL role+claims switch (same mechanism PostgREST uses), NOT a signed HTTP JWT.
DO $scan$
DECLARE
  u_pending uuid := gen_random_uuid(); u_norole uuid := gen_random_uuid();
  persona text; uid uuid; r record; seen boolean; rep text := ''; hits text;
BEGIN
  INSERT INTO auth.users(id, email, aud, role, instance_id)
    VALUES (u_pending,'a005-pending@invalid.test','authenticated','authenticated','00000000-0000-0000-0000-000000000000'),
           (u_norole ,'a005-norole@invalid.test' ,'authenticated','authenticated','00000000-0000-0000-0000-000000000000');
  UPDATE public.profiles SET status='active' WHERE id=u_norole;      -- active, zero roles/locations
  FOREACH persona IN ARRAY ARRAY['anon','pending','active_norole'] LOOP
    uid := CASE persona WHEN 'pending' THEN u_pending WHEN 'active_norole' THEN u_norole END;
    hits := '';
    EXECUTE format('SET LOCAL ROLE %I', CASE persona WHEN 'anon' THEN 'anon' ELSE 'authenticated' END);
    PERFORM set_config('request.jwt.claims',
      CASE WHEN uid IS NULL THEN '{"role":"anon"}' ELSE json_build_object('sub',uid,'role','authenticated')::text END, true);
    PERFORM set_config('request.jwt.claim.sub', coalesce(uid::text,''), true);
    FOR r IN SELECT c.relname FROM pg_class c WHERE c.relnamespace='public'::regnamespace
              AND c.relkind IN ('r','v','m','p') AND has_table_privilege(current_user, c.oid, 'SELECT') ORDER BY 1 LOOP
      BEGIN
        EXECUTE format('SELECT EXISTS(SELECT 1 FROM public.%I)', r.relname) INTO seen;
        IF seen THEN hits := hits || r.relname || ', '; END IF;
      EXCEPTION WHEN OTHERS THEN NULL; END;
    END LOOP;
    RESET ROLE;
    rep := rep || E'\n' || persona || ' CAN SEE ROWS IN: ' || coalesce(nullif(hits,''),'(none)');
  END LOOP;
  RAISE EXCEPTION 'A005_REPORT_ROLLED_BACK%', rep;
END
$scan$;
