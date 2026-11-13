-- C10-A053: A050 portfolio + A046 personas installed but A051 migration MISSING => NOT CONNECTED, never synthetic payroll.
\set ON_ERROR_STOP on
\ir c10_a053_a054_helpers.sql
BEGIN; SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb; BEGIN
 PERFORM c10_test.as_user('owner');
 r:=c10_demo.a053_read_portfolio_workforce_v1('2026-10-01');
 PERFORM c10_test.eq(r->>'state','NOT_CONNECTED','A051 missing => NOT_CONNECTED');
 PERFORM c10_test.eq(jsonb_array_length(r->'businesses')::text,'0','no business rows invented');
 PERFORM c10_test.eq(r->'contracts'->>'A051_workforce','NOT_CONNECTED','contract status'); PERFORM c10_test.eq(r->'contracts'->>'A050_portfolio','CONNECTED','A050 present');
 PERFORM c10_test.eq((r::text ~ '(headcount|net_|gross)')::text,'false','no figures at all');
 PERFORM c10_test.eq(r->>'paid','false','paid false');
 PERFORM c10_test.eq(c10_demo.a053_my_assignments_v1()->>'state','NOT_CONNECTED','assignments not connected');
 PERFORM c10_test.denied($q$SELECT c10_demo.a053_link_staff_identity_v1(101,'a053-nc-000001',1,'UNASSIGNED_USER','no workforce')$q$,'a053_not_connected');
 PERFORM c10_test.denied($q$SELECT c10_demo.a053_staff_overview_v1(101)$q$,'a053_not_connected');
 PERFORM c10_test.eq(c10_demo.read_portfolio_workspace_v1()->>'server_authorized','true','A050 still works');
 PERFORM c10_test.eq(jsonb_array_length(c10_demo.a053_persona_catalog_v1()->'items')::text,'21','registry works without A051');
END $$; COMMIT;
SELECT 'A053_NOT_CONNECTED_PASS' AS result;
