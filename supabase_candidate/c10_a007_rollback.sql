-- C10-A007 rollback CANDIDATE for c10_a007_migration.sql. NOT APPLIED.
-- Safe on live: the function is new, read-only and referenced by no table,
-- view, policy or other function. It touches nothing else. Idempotent.
BEGIN;
DO $rb$
BEGIN
  IF to_regprocedure('public.core10_owner_inbox_v1(bigint,integer)') IS NOT NULL THEN
    REVOKE ALL ON FUNCTION public.core10_owner_inbox_v1(bigint,integer)
      FROM PUBLIC, anon, authenticated, service_role;
  END IF;
END
$rb$;
DROP FUNCTION IF EXISTS public.core10_owner_inbox_v1(bigint,integer);
COMMIT;
