-- Run via run_a010_tests.sh (fixture + candidate already applied). psql -v negctl=0|1
\set ON_ERROR_STOP on
\pset pager off
CREATE TEMP TABLE _t(n text, ok boolean);
GRANT ALL ON _t TO PUBLIC;
CREATE OR REPLACE FUNCTION pg_temp.expect_fail(p_name text, p_sql text, p_like text) RETURNS void
LANGUAGE plpgsql AS $$ BEGIN
  BEGIN EXECUTE p_sql; INSERT INTO _t VALUES (p_name,false); RETURN;
  EXCEPTION WHEN OTHERS THEN INSERT INTO _t VALUES (p_name, SQLERRM LIKE p_like OR SQLSTATE LIKE p_like); END;
END $$;

-- legacy ids unchanged (exactly 1..7,9)
INSERT INTO _t SELECT 'legacy ids unchanged',
  (SELECT array_agg(id ORDER BY id) FROM public.locations) = ARRAY[1,2,3,4,5,6,7,9]::bigint[]
  AND (SELECT count(*) FROM public.locations WHERE org_unit_id=3)=8;
-- every location -> exactly one site and one business
INSERT INTO _t SELECT 'every location has exactly 1 site + business 3',
  (SELECT count(*) FROM public.c10_location_hierarchy)=8
  AND (SELECT count(*) FROM public.c10_location_hierarchy WHERE site_id IS NOT NULL AND business_id=3 AND derived_business_id=3)=8
  AND (SELECT count(DISTINCT location_id) FROM public.c10_location_site_map)=8;
INSERT INTO _t SELECT 'no violations', NOT EXISTS (SELECT 1 FROM public.c10_hierarchy_violations);
INSERT INTO _t SELECT 'FK child rows intact',
  (SELECT count(*) FROM public.stock_moves)=3 AND (SELECT count(*) FROM public.sales)=2 AND (SELECT count(*) FROM public.user_locations)=2;
INSERT INTO _t SELECT 'single default site for business 3 (idempotent re-apply)',
  (SELECT count(*) FROM public.c10_operating_sites WHERE business_id=3 AND is_legacy_default)=1;

\if :negctl
  -- NEGATIVE CONTROL: sabotage guards so the rejection tests must fail
  DROP TRIGGER c10_map_guard ON public.c10_location_site_map;
  DROP TRIGGER c10_site_guard ON public.c10_operating_sites;
  ALTER TABLE public.c10_location_site_map DROP CONSTRAINT c10_location_site_map_pkey;
\endif

INSERT INTO public.org_units(id,parent_id,kind,name) VALUES (5,4,'business','PAINT'),(6,3,'unit','SubUnit');
INSERT INTO public.locations(id,name,org_unit_id) VALUES (10,'NoUnit',NULL),(12,'Ok',3),(13,'Nested',6);

SELECT pg_temp.expect_fail('orphan: site under non-business unit',
  $$INSERT INTO public.c10_operating_sites(business_id,code,name) VALUES (4,'x','x')$$, '%c10_site_not_under_business%');
SELECT pg_temp.expect_fail('orphan: site under missing business',
  $$INSERT INTO public.c10_operating_sites(business_id,code,name) VALUES (999,'x','x')$$, '23514');
SELECT pg_temp.expect_fail('duplicate site code in business',
  $$INSERT INTO public.c10_operating_sites(business_id,code,name) VALUES (3,'legacy-default','dup')$$, '23505');
SELECT pg_temp.expect_fail('duplicate: location mapped to second site',
  $$INSERT INTO public.c10_operating_sites(business_id,code,name) VALUES (3,'second','s2');
    INSERT INTO public.c10_location_site_map(location_id,site_id,business_id)
      SELECT 1,id,3 FROM public.c10_operating_sites WHERE code='second'$$, '23505');
SELECT pg_temp.expect_fail('orphan: map to missing location',
  $$INSERT INTO public.c10_location_site_map(location_id,site_id,business_id)
     SELECT 998,id,3 FROM public.c10_operating_sites WHERE code='legacy-default' AND business_id=3$$, '23514');
SELECT pg_temp.expect_fail('orphan: location with NULL org_unit',
  $$INSERT INTO public.c10_location_site_map(location_id,site_id,business_id)
     SELECT 10,id,3 FROM public.c10_operating_sites WHERE code='legacy-default'$$, '%c10_location_unmapped_org_unit%');
SELECT pg_temp.expect_fail('cross-business: location of business 3 mapped to site of business 5',
  $$INSERT INTO public.c10_operating_sites(business_id,code,name) VALUES (5,'paint-main','p');
    INSERT INTO public.c10_location_site_map(location_id,site_id,business_id)
      SELECT 12,id,5 FROM public.c10_operating_sites WHERE code='paint-main'$$, '%c10_site_business_mismatch%');
SELECT pg_temp.expect_fail('composite FK: map business differs from site business',
  $$INSERT INTO public.c10_location_site_map(location_id,site_id,business_id)
     SELECT 12,id,5 FROM public.c10_operating_sites WHERE code='legacy-default'$$, '23514');
SELECT pg_temp.expect_fail('deleting mapped site restricted',
  $$DELETE FROM public.c10_operating_sites WHERE code='legacy-default'$$, '23503');
SELECT pg_temp.expect_fail('deleting mapped location restricted',
  $$DELETE FROM public.locations WHERE id=1$$, '23503');

INSERT INTO _t SELECT 'nested org_unit resolves to business 3', public.c10_business_of_unit(6)=3;
INSERT INTO public.c10_location_site_map(location_id,site_id,business_id)
  SELECT 13,id,3 FROM public.c10_operating_sites WHERE code='legacy-default';
INSERT INTO _t SELECT 'valid nested mapping accepted', EXISTS (SELECT 1 FROM public.c10_location_site_map WHERE location_id=13);
INSERT INTO _t SELECT 'unmapped new location flagged no_site',
  EXISTS (SELECT 1 FROM public.c10_hierarchy_violations WHERE location_id=12 AND problem='no_site');
UPDATE public.locations SET org_unit_id=5 WHERE id=13;
INSERT INTO _t SELECT 'drift detected by violations view',
  EXISTS (SELECT 1 FROM public.c10_hierarchy_violations WHERE location_id=13 AND problem='business_drift');
UPDATE public.locations SET org_unit_id=6 WHERE id=13;

SELECT pg_temp.expect_fail('anon cannot read sites',
  $$SET LOCAL ROLE anon; SELECT 1 FROM public.c10_operating_sites$$, '42501');
RESET ROLE;
SELECT pg_temp.expect_fail('authenticated cannot read map',
  $$SET LOCAL ROLE authenticated; SELECT 1 FROM public.c10_location_site_map$$, '42501');
RESET ROLE;
SELECT pg_temp.expect_fail('authenticated cannot read hierarchy view',
  $$SET LOCAL ROLE authenticated; SELECT 1 FROM public.c10_location_hierarchy$$, '42501');
RESET ROLE;

SELECT n, CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END AS result FROM _t;
DO $$ BEGIN IF EXISTS (SELECT 1 FROM _t WHERE NOT ok) THEN RAISE EXCEPTION 'A010 TESTS FAILED'; END IF; END $$;
