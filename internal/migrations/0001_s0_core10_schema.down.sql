-- Rollback of 0001. Refuses to drop a schema that already holds engine objects.
DO $$
BEGIN
 IF EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
           WHERE n.nspname='core10' AND c.relkind IN('r','p','v','m','S') AND c.relname NOT LIKE 'schema_migrations%')
    OR EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='core10') THEN
  RAISE EXCEPTION 'CORE10_SCHEMA_NOT_EMPTY: roll back later migrations first';
 END IF;
END $$;
DROP TABLE core10.schema_migrations;
DROP SCHEMA core10;
