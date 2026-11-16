\set ON_ERROR_STOP on
-- PACK-02 S4: owner-wide report reconciles with the existing A050 portfolio
-- contract on the same canonical rows (same business IDs, names, site counts).
CREATE FUNCTION pg_temp.check_owner(p uuid,p_expected int) RETURNS void LANGUAGE plpgsql AS $$
DECLARE a jsonb; r jsonb;
BEGIN
 PERFORM set_config('request.jwt.claim.sub',p::text,false);
 a:=core10.read_portfolio_workspace_v1(); r:=core10.pack02_owner_report_v1();
 IF jsonb_array_length(r->'businesses')<>p_expected THEN RAISE EXCEPTION 'owner report count % for %',jsonb_array_length(r->'businesses'),p; END IF;
 IF EXISTS(
  (SELECT (x->>'business_id')::bigint,(x->>'tenant_id')::bigint,x->>'display_name',(x->>'sites')::int FROM jsonb_array_elements(r->'businesses') x
   EXCEPT SELECT (y->>'business_id')::bigint,(y->>'tenant_id')::bigint,y->>'name',jsonb_array_length(y->'sites') FROM jsonb_array_elements(a->'businesses') y)
  UNION ALL
  (SELECT (y->>'business_id')::bigint,(y->>'tenant_id')::bigint,y->>'name',jsonb_array_length(y->'sites') FROM jsonb_array_elements(a->'businesses') y
   EXCEPT SELECT (x->>'business_id')::bigint,(x->>'tenant_id')::bigint,x->>'display_name',(x->>'sites')::int FROM jsonb_array_elements(r->'businesses') x))
 THEN RAISE EXCEPTION 'PACK-02 owner report diverges from A050 portfolio for %',p; END IF;
END $$;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA pg_temp TO authenticated;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
SELECT core10.pack02_setup_business_v1(11,'pack02-portfolio','paint_hardware','Portfolio Demo','advanced',
 '[{"kind":"showroom","label":"One"},{"kind":"warehouse","label":"Two"}]','pack02-portfolio-01','#446688') IS NOT NULL;
SELECT pg_temp.check_owner('11111111-1111-4111-8111-111111111111',3);
SELECT pg_temp.check_owner('77777777-7777-4777-8777-777777777777',1);
-- A non-tenant-owner still has an A050 portfolio row for their business but no PACK-02 owner-wide report.
SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
DO $t$ BEGIN
 IF jsonb_array_length(core10.read_portfolio_workspace_v1()->'businesses')<>1 THEN RAISE EXCEPTION 'A050 baseline changed'; END IF;
 BEGIN PERFORM core10.pack02_owner_report_v1(); RAISE EXCEPTION 'business owner got owner-wide report';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'PACK02_REPORT_DENIED' THEN RAISE; END IF; END;
END $t$;
RESET ROLE;
SELECT 'PASS PACK-02 portfolio-e2e' AS result;
