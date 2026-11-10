-- C10-A005 step 2: live WRITE scan. One transaction, ALWAYS rolled back by the final RAISE.
-- For each persona and each public base table, tries to UPDATE (no-op value) and DELETE one
-- real row; row_count>0 means that persona can really modify/delete it (RLS+grants).
-- INSERT is reported only as privilege-level (RLS WITH CHECK cannot be probed generically).
-- Persona 'salesperson' = active user with one real role_code; informational (legit writes expected).
DO $w$
DECLARE
  u1 uuid := gen_random_uuid(); u2 uuid := gen_random_uuid(); u3 uuid := gen_random_uuid();
  persona text; uid uuid; r record; col text; n int; upd text; del text; ins text; rep text := ''; note text := '';
BEGIN
  INSERT INTO auth.users(id,email,aud,role,instance_id) VALUES
   (u1,'a005w-pending@invalid.test','authenticated','authenticated','00000000-0000-0000-0000-000000000000'),
   (u2,'a005w-norole@invalid.test','authenticated','authenticated','00000000-0000-0000-0000-000000000000'),
   (u3,'a005w-sales@invalid.test','authenticated','authenticated','00000000-0000-0000-0000-000000000000');
  UPDATE public.profiles SET status='active' WHERE id IN (u2,u3);
  BEGIN INSERT INTO public.user_roles(user_id,role_code) VALUES (u3,'salesperson');
  EXCEPTION WHEN OTHERS THEN note := note || ' [salesperson role insert blocked: '||SQLERRM||']'; END;
  FOREACH persona IN ARRAY ARRAY['anon','pending','active_norole','salesperson'] LOOP
    uid := CASE persona WHEN 'pending' THEN u1 WHEN 'active_norole' THEN u2 WHEN 'salesperson' THEN u3 END;
    upd:=''; del:=''; ins:='';
    EXECUTE format('SET LOCAL ROLE %I', CASE persona WHEN 'anon' THEN 'anon' ELSE 'authenticated' END);
    PERFORM set_config('request.jwt.claims', CASE WHEN uid IS NULL THEN '{"role":"anon"}' ELSE json_build_object('sub',uid,'role','authenticated')::text END, true);
    PERFORM set_config('request.jwt.claim.sub', coalesce(uid::text,''), true);
    FOR r IN SELECT c.oid, c.relname FROM pg_class c WHERE c.relnamespace='public'::regnamespace AND c.relkind IN ('r','p') ORDER BY 2 LOOP
      IF has_table_privilege(current_user, r.oid, 'INSERT') THEN ins := ins || r.relname || ','; END IF;
      IF has_table_privilege(current_user, r.oid, 'UPDATE') THEN
        SELECT a.attname INTO col FROM pg_attribute a WHERE a.attrelid=r.oid AND a.attnum>0 AND NOT a.attisdropped AND a.attgenerated='' AND a.attidentity='' ORDER BY a.attnum LIMIT 1;
        IF col IS NOT NULL THEN BEGIN
          EXECUTE format('UPDATE public.%1$I SET %2$I=%2$I WHERE ctid=(SELECT ctid FROM public.%1$I LIMIT 1)', r.relname, col);
          GET DIAGNOSTICS n = ROW_COUNT; IF n>0 THEN upd := upd || r.relname || ','; END IF;
        EXCEPTION WHEN OTHERS THEN NULL; END; END IF;
      END IF;
      IF has_table_privilege(current_user, r.oid, 'DELETE') THEN BEGIN
        EXECUTE format('DELETE FROM public.%1$I WHERE ctid=(SELECT ctid FROM public.%1$I LIMIT 1)', r.relname);
        GET DIAGNOSTICS n = ROW_COUNT; IF n>0 THEN del := del || r.relname || ','; END IF;
      EXCEPTION WHEN OTHERS THEN NULL; END; END IF;
    END LOOP;
    RESET ROLE;
    rep := rep || E'\n== ' || persona || E' ==\nCAN UPDATE: ' || coalesce(nullif(upd,''),'(none)') || E'\nCAN DELETE: ' || coalesce(nullif(del,''),'(none)') || E'\nINSERT GRANT (RLS not probed): ' || coalesce(nullif(ins,''),'(none)');
  END LOOP;
  RAISE EXCEPTION 'A005_WRITE_REPORT_ROLLED_BACK%', rep || E'\n' || note;
END
$w$;
