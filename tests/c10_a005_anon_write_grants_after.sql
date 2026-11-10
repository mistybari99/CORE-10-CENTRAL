DO $t$ BEGIN
 IF has_table_privilege('anon','public.a5_locked','TRUNCATE') OR has_table_privilege('anon','public.a5_locked','INSERT') OR has_table_privilege('anon','public.a5_locked','DELETE') OR has_table_privilege('anon','public.a5_locked','UPDATE') THEN RAISE EXCEPTION 'LOCKED_STILL_WRITABLE'; END IF;
 IF NOT has_table_privilege('anon','public.a5_locked','SELECT') THEN RAISE EXCEPTION 'SELECT_WRONGLY_REMOVED'; END IF;
 IF NOT has_table_privilege('anon','public.a5_public_form','INSERT') THEN RAISE EXCEPTION 'PUBLIC_FORM_BROKEN'; END IF;
 IF NOT has_table_privilege('authenticated','public.a5_auth','TRUNCATE') OR NOT has_table_privilege('authenticated','public.a5_locked','INSERT') THEN RAISE EXCEPTION 'AUTHENTICATED_AFFECTED'; END IF;
END $t$;
SET ROLE anon; INSERT INTO public.a5_public_form VALUES (1,'x'); RESET ROLE;
\echo PASS: A005 anon write-class grants removed only where no anon write policy exists; public form insert and authenticated access intact
