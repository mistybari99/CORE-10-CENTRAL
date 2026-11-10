-- C10-A005 step 3: privilege-escalation probes as pending / active-no-role / cash_controller users.
-- ONE transaction, ALWAYS rolled back (final RAISE carries the report). No residue.
-- NOTE: UPDATE under RLS returns 0 rows WITHOUT an error, so "no exception" != success for UPDATE;
-- always check ROW_COUNT (see self-activate probe below). INSERT denial shows as SQLSTATE 42501.
DO $i$
DECLARE u1 uuid := gen_random_uuid(); u2 uuid := gen_random_uuid(); persona text; uid uuid; t text; spec text[]; rep text := ''; res text; n int;
 tests text[] := ARRAY[
  'self-grant role OWNER|INSERT INTO public.user_roles(user_id,role_code) VALUES (%L,''owner'')',
  'self-grant role management|INSERT INTO public.user_roles(user_id,role_code) VALUES (%L,''management'')',
  'self-grant location 1|INSERT INTO public.user_locations(user_id,location_id) VALUES (%L,1)'];
BEGIN
  INSERT INTO auth.users(id,email,aud,role,instance_id) VALUES
   (u1,'a005i-pending@invalid.test','authenticated','authenticated','00000000-0000-0000-0000-000000000000'),
   (u2,'a005i-norole@invalid.test','authenticated','authenticated','00000000-0000-0000-0000-000000000000');
  UPDATE public.profiles SET status='active' WHERE id=u2;
  FOREACH persona IN ARRAY ARRAY['pending','active_norole'] LOOP
    uid := CASE persona WHEN 'pending' THEN u1 ELSE u2 END; rep := rep || E'\n== '||persona||' ==';
    FOREACH t IN ARRAY tests LOOP
      spec := string_to_array(t,'|'); SET LOCAL ROLE authenticated;
      PERFORM set_config('request.jwt.claims', json_build_object('sub',uid,'role','authenticated')::text, true);
      PERFORM set_config('request.jwt.claim.sub', uid::text, true);
      BEGIN EXECUTE format(spec[2], uid); res := 'ALLOWED <<< REVIEW';
      EXCEPTION WHEN OTHERS THEN res := 'denied '||SQLSTATE; END;
      RESET ROLE; rep := rep || E'\n  '||spec[1]||' -> '||res;
    END LOOP;
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claims', json_build_object('sub',uid,'role','authenticated')::text, true);
    PERFORM set_config('request.jwt.claim.sub', uid::text, true);
    UPDATE public.profiles SET status='active' WHERE id=uid AND status<>'active'; GET DIAGNOSTICS n = ROW_COUNT;
    RESET ROLE; rep := rep || E'\n  self-activate profile rows_updated='||n;
  END LOOP;
  RAISE EXCEPTION 'A005_ESCALATION_REPORT_ROLLED_BACK%', rep;
END
$i$;
