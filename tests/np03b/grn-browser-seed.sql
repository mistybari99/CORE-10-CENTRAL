-- Run after central-ui-seed.sql on a fresh combined disposable database only.
\set ON_ERROR_STOP on
DO $$ BEGIN
 IF current_database() !~ '^core10_np03b_(ci|local)' OR to_regclass('auth.users') IS NOT NULL
 THEN RAISE EXCEPTION 'NP03B_DISPOSABLE_ONLY'; END IF;
END $$;
\set grn_reviewer 'abababab-abab-4bab-8bab-abababababab'
\set grn_business 101
\set grn_site 1002
\set grn_location 5002
\set grn_supplier 7002
\set grn_item 8102
\set grn_key 'GRN-CENTRAL-QA'
-- Central's Manager fixture is denied Factory access. Use its Business Owner as the PO maker.
\set grn_buyer '22222222-2222-4222-8222-222222222222'
\ir ../np05a/post-grn-fixture.sql
