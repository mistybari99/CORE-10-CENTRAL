-- f10/f11 injection fixture (SUPERUSER, DISPOSABLE DATABASE ONLY). DEMO / NOT LIVE.
-- Simulates a compromised/legacy writer: removes the source_id CHECK and turns the payload validator into a no-op so
-- formula-looking values can reach the journal. The export must still neutralize them. Never applied to any shared DB.
\set ON_ERROR_STOP on
do $$
declare c text;
begin
  for c in select conname from pg_constraint
            where conrelid = 'c10_gov003_demo.audit_events'::regclass and contype = 'c'
              and pg_get_constraintdef(oid) like '%source_id%' loop
    execute format('alter table c10_gov003_demo.audit_events drop constraint %I', c);
  end loop;
end $$;
create or replace function c10_gov003_demo.validate_payload(p jsonb) returns void
language plpgsql stable set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $f$ begin return; end $f$;
