-- C10-A010 rollback: removes only objects created by a010_additive_candidate.sql. Idempotent.
BEGIN;
DROP VIEW IF EXISTS public.c10_hierarchy_violations;
DROP VIEW IF EXISTS public.c10_location_hierarchy;
DROP TABLE IF EXISTS public.c10_location_site_map;
DROP TABLE IF EXISTS public.c10_operating_sites;
DROP FUNCTION IF EXISTS public.c10_map_guard();
DROP FUNCTION IF EXISTS public.c10_site_guard();
DROP FUNCTION IF EXISTS public.c10_business_of_unit(bigint);
COMMIT;
