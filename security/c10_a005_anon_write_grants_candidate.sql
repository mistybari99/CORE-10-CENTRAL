-- C10-A005 CANDIDATE ONLY (not applied). Remove anon WRITE-class table privileges that RLS cannot protect
-- (notably TRUNCATE, which bypasses RLS) on RLS-enabled public tables that have NO anon/public write policy.
-- Live read-only catalog trace 2026-11-10: 14 tables (customers, doc_template_choice, emergency_requests, entries,
-- exceptions, grant_defs, loc_split_backup_20261103, location_settings, option_lists, release_requests, rule_grants,
-- rules, sale_payments, sales). SELECT grants and all functions are untouched. Public website/login use SECURITY DEFINER
-- RPCs (login_precheck, web_*), not anon table writes; with no anon write policy every anon write is already RLS-denied,
-- so this changes no working behaviour.
BEGIN;
DO $r$
DECLARE t record; p text;
BEGIN
  FOR t IN
    SELECT c.oid, c.relname FROM pg_class c
    WHERE c.relnamespace='public'::regnamespace AND c.relkind IN ('r','p') AND c.relrowsecurity
      AND NOT EXISTS (SELECT 1 FROM pg_policies pl WHERE pl.schemaname='public' AND pl.tablename=c.relname
                      AND pl.cmd IN ('INSERT','UPDATE','DELETE','ALL') AND (pl.roles::text[] && ARRAY['anon','public']))
  LOOP
    FOREACH p IN ARRAY ARRAY['INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'] LOOP
      IF has_table_privilege('anon', t.oid, p) THEN
        EXECUTE format('REVOKE %s ON TABLE public.%I FROM anon', p, t.relname);
      END IF;
    END LOOP;
  END LOOP;
END $r$;
DO $v$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_class c WHERE c.relnamespace='public'::regnamespace AND c.relkind IN ('r','p') AND c.relrowsecurity
      AND NOT EXISTS (SELECT 1 FROM pg_policies pl WHERE pl.schemaname='public' AND pl.tablename=c.relname AND pl.cmd IN ('INSERT','UPDATE','DELETE','ALL') AND (pl.roles::text[] && ARRAY['anon','public']))
      AND (has_table_privilege('anon',c.oid,'INSERT') OR has_table_privilege('anon',c.oid,'UPDATE') OR has_table_privilege('anon',c.oid,'DELETE') OR has_table_privilege('anon',c.oid,'TRUNCATE')))
  THEN RAISE EXCEPTION 'C10_A005_ANON_WRITE_GRANT_REMAINS'; END IF;
END $v$;
COMMIT;
