-- GOV-003 isolated test bed. DEMO / NOT LIVE. Disposable schema only.
-- Contract/test bed: final adoption must be reconciled to the one canonical CORE10 audit service.
-- Runs as a superuser (bootstrap only); every later file runs as c10g3_owner.
\set ON_ERROR_STOP on

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'c10g3_owner') then
    create role c10g3_owner nologin nobypassrls;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'c10g3_backend') then
    create role c10g3_backend nologin nobypassrls;  -- trusted adapter boundary (append/export/review RPCs only)
  end if;
  if not exists (select 1 from pg_roles where rolname = 'c10g3_reader') then
    create role c10g3_reader nologin nobypassrls;   -- scoped read-only views (RLS)
  end if;
  if not exists (select 1 from pg_roles where rolname = 'c10g3_app') then
    create role c10g3_app nologin nobypassrls;      -- ordinary app principal: no table rights at all
  end if;
end $$;

create schema if not exists c10_gov003_demo authorization c10g3_owner;
revoke all on schema c10_gov003_demo from public;
grant usage on schema c10_gov003_demo to c10g3_backend, c10g3_reader, c10g3_app;
comment on schema c10_gov003_demo is
  'GOV-003 DEMO/NOT LIVE contract and test bed. Not a production audit ledger.';
