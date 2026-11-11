-- C10-A055 (7/7): Lock-down. RLS on, zero direct table access, explicit RPC allow-list. Load LAST.
-- Public API = am_*_v1 and read_asset_maintenance_business_summary_v1. Everything else (ami_*) is internal.
DO $$
DECLARE t record; f record;
BEGIN
 FOR t IN SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='c10_demo' AND c.relkind='r' AND c.relname LIKE 'am\_%' LOOP
  EXECUTE format('ALTER TABLE c10_demo.%I ENABLE ROW LEVEL SECURITY',t.relname);
  EXECUTE format('REVOKE ALL ON c10_demo.%I FROM PUBLIC,anon,authenticated',t.relname);
 END LOOP;
 FOR f IN SELECT p.oid::regprocedure AS sig,p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='c10_demo' AND (p.proname LIKE 'am\_%' OR p.proname LIKE 'ami\_%' OR p.proname LIKE 'read\_asset\_maintenance\_%') LOOP
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated',f.sig);
  IF f.proname ~ '^am_.*_v1$' OR f.proname='read_asset_maintenance_business_summary_v1' THEN
   EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated',f.sig); END IF;
 END LOOP;
END$$;
-- A018 granted EXECUTE on all functions at its own load time; A055 functions did not exist then, and trigger
-- functions / helpers must stay private. Sequences for identity columns are used only by definer RPCs.
REVOKE ALL ON ALL SEQUENCES IN SCHEMA c10_demo FROM anon;
GRANT USAGE ON SCHEMA c10_demo TO authenticated;
