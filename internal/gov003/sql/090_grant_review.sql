-- 09 grant-and-policy-review: READ-ONLY catalog inventory of schema c10_gov003_demo -> normalized,
-- versioned, canonical snapshot (jsonb + sha256) -> diff against an OWNER-APPROVED STORED baseline.
-- DEMO / NOT LIVE. Requires 080 (the diff raises a risk signal through 080's emitter).
--
-- HARD FENCE (proven in tests):
--   * Nothing in this file executes GRANT, REVOKE, ALTER, CREATE/DROP POLICY or any dynamic SQL. The
--     functions only READ pg_catalog and INSERT rows into their own append-only tables.
--   * The baseline is never taken from the caller. record_baseline() stores a server-side inventory (or a
--     previously stored snapshot of the same business); approved_by is derived server-side. There is no
--     parameter anywhere through which a caller can supply "the baseline" or "the diff".
--   * Findings are labelled ADVISORY. A finding is a prompt for human review, not a verdict.
-- LIMITATION: the inventory is only as truthful as the catalog the database role can read; a superuser
-- can change the catalog and the stored rows. This is tamper-EVIDENT for ordinary principals only.
-- Error codes: G3A01 forged actor | G3A02 scope denied | G3A03 invalid input | G3A05 unauthenticated |
--              G3C01 idempotency conflict | G3C03 baseline missing
\set ON_ERROR_STOP on
set role c10g3_owner;
set search_path = pg_catalog, c10_gov003_demo, pg_temp;

-- ---------------------------------------------------------------------------------------------------
-- Catalog inventory (owner-only internal). Deterministic: every array is sorted bytewise.
-- ---------------------------------------------------------------------------------------------------
create function c10_gov003_demo._catalog_inventory() returns jsonb
language sql stable security definer
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
  select jsonb_build_object(
    'format', 'g3cat-v1',
    'schema', 'c10_gov003_demo',
    'schema_privileges', (
      select coalesce(jsonb_agg(jsonb_build_object('grantee', q.g, 'privilege', q.p, 'grantable', q.gr)
                                order by q.g collate "C", q.p collate "C"), '[]'::jsonb)
        from (select case when x.grantee = 0 then 'PUBLIC' else pg_get_userbyid(x.grantee)::text end as g,
                     x.privilege_type::text as p, x.is_grantable as gr
                from pg_namespace n
                cross join lateral aclexplode(coalesce(n.nspacl, acldefault('n', n.nspowner))) x
               where n.oid = 'c10_gov003_demo'::regnamespace) q),
    'functions', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'signature', f.sig, 'owner', f.own, 'security_definer', f.def, 'config', f.cfg,
               'grants', f.grants) order by f.sig collate "C"), '[]'::jsonb)
        from (select p.proname::text || '(' || pg_get_function_identity_arguments(p.oid) || ')' as sig,
                     pg_get_userbyid(p.proowner)::text as own, p.prosecdef as def,
                     coalesce(to_jsonb(p.proconfig), '[]'::jsonb) as cfg,
                     (select coalesce(jsonb_agg(jsonb_build_object(
                               'grantee', case when x.grantee = 0 then 'PUBLIC' else pg_get_userbyid(x.grantee)::text end,
                               'privilege', x.privilege_type::text, 'grantable', x.is_grantable)
                             order by (case when x.grantee = 0 then 'PUBLIC' else pg_get_userbyid(x.grantee)::text end) collate "C",
                                      x.privilege_type::text collate "C"), '[]'::jsonb)
                        from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) x) as grants
                from pg_proc p
               where p.pronamespace = 'c10_gov003_demo'::regnamespace and p.prokind in ('f','p')
                 and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')) f),
    'relations', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'name', r.nm, 'kind', r.kind, 'owner', r.own, 'rls_enabled', r.rls, 'rls_forced', r.frc,
               'options', r.opts, 'grants', r.grants, 'column_grants', r.cgrants, 'triggers', r.trgs)
             order by r.nm collate "C"), '[]'::jsonb)
        from (select c.relname::text as nm, c.relkind::text as kind, pg_get_userbyid(c.relowner)::text as own,
                     c.relrowsecurity as rls, c.relforcerowsecurity as frc,
                     coalesce(to_jsonb(c.reloptions), '[]'::jsonb) as opts,
                     (select coalesce(jsonb_agg(jsonb_build_object(
                               'grantee', case when x.grantee = 0 then 'PUBLIC' else pg_get_userbyid(x.grantee)::text end,
                               'privilege', x.privilege_type::text, 'grantable', x.is_grantable)
                             order by (case when x.grantee = 0 then 'PUBLIC' else pg_get_userbyid(x.grantee)::text end) collate "C",
                                      x.privilege_type::text collate "C"), '[]'::jsonb)
                        from aclexplode(coalesce(c.relacl,
                               acldefault(case when c.relkind = 'S' then 's'::"char" else 'r'::"char" end, c.relowner))) x) as grants,
                     (select coalesce(jsonb_agg(jsonb_build_object(
                               'column', a.attname::text,
                               'grantee', case when x.grantee = 0 then 'PUBLIC' else pg_get_userbyid(x.grantee)::text end,
                               'privilege', x.privilege_type::text, 'grantable', x.is_grantable)
                             order by a.attname::text collate "C",
                                      (case when x.grantee = 0 then 'PUBLIC' else pg_get_userbyid(x.grantee)::text end) collate "C",
                                      x.privilege_type::text collate "C"), '[]'::jsonb)
                        from pg_attribute a cross join lateral aclexplode(a.attacl) x
                       where a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped and a.attacl is not null) as cgrants,
                     (select coalesce(jsonb_agg(jsonb_build_object(
                               'name', t.tgname::text, 'enabled', t.tgenabled::text,
                               'function', (select pr.proname::text from pg_proc pr where pr.oid = t.tgfoid))
                             order by t.tgname::text collate "C"), '[]'::jsonb)
                        from pg_trigger t where t.tgrelid = c.oid and not t.tgisinternal) as trgs
                from pg_class c
               where c.relnamespace = 'c10_gov003_demo'::regnamespace and c.relkind in ('r','p','v','m','S','f')) r),
    'policies', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'table', q.tbl, 'name', q.nm, 'command', q.cmd, 'permissive', q.perm, 'roles', q.roles,
               'using', q.qual, 'check', q.wc) order by q.tbl collate "C", q.nm collate "C"), '[]'::jsonb)
        from (select c.relname::text as tbl, pol.polname::text as nm, pol.polcmd::text as cmd,
                     pol.polpermissive as perm,
                     (select coalesce(jsonb_agg(z.rn order by z.rn collate "C"), '[]'::jsonb)
                        from (select case when ro = 0 then 'PUBLIC' else pg_get_userbyid(ro)::text end as rn
                                from unnest(pol.polroles) ro) z) as roles,
                     pg_get_expr(pol.polqual, pol.polrelid) as qual,
                     pg_get_expr(pol.polwithcheck, pol.polrelid) as wc
                from pg_policy pol join pg_class c on c.oid = pol.polrelid
               where c.relnamespace = 'c10_gov003_demo'::regnamespace) q)
  );
$$;

-- Flatten a snapshot into comparable facts (one key per grant / object / policy / trigger).
create function c10_gov003_demo._catalog_facts(d jsonb)
returns table (fkey text, ftype text, fval jsonb)
language sql immutable
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
  select 'schema_grant|' || (g ->> 'grantee') || '|' || (g ->> 'privilege'), 'schema_grant'::text,
         jsonb_build_object('grantable', g -> 'grantable')
    from jsonb_array_elements(d -> 'schema_privileges') g
  union all
  select 'function|' || (f ->> 'signature'), 'function',
         jsonb_build_object('owner', f -> 'owner', 'security_definer', f -> 'security_definer', 'config', f -> 'config')
    from jsonb_array_elements(d -> 'functions') f
  union all
  select 'function_grant|' || (f ->> 'signature') || '|' || (g ->> 'grantee') || '|' || (g ->> 'privilege'),
         'function_grant', jsonb_build_object('grantable', g -> 'grantable')
    from jsonb_array_elements(d -> 'functions') f cross join lateral jsonb_array_elements(f -> 'grants') g
  union all
  select 'relation|' || (r ->> 'name'), 'relation',
         jsonb_build_object('kind', r -> 'kind', 'owner', r -> 'owner', 'rls_enabled', r -> 'rls_enabled',
                            'rls_forced', r -> 'rls_forced', 'options', r -> 'options')
    from jsonb_array_elements(d -> 'relations') r
  union all
  select 'relation_grant|' || (r ->> 'name') || '|' || (g ->> 'grantee') || '|' || (g ->> 'privilege'),
         'relation_grant', jsonb_build_object('grantable', g -> 'grantable')
    from jsonb_array_elements(d -> 'relations') r cross join lateral jsonb_array_elements(r -> 'grants') g
  union all
  select 'column_grant|' || (r ->> 'name') || '|' || (g ->> 'column') || '|' || (g ->> 'grantee') || '|' || (g ->> 'privilege'),
         'column_grant', jsonb_build_object('grantable', g -> 'grantable')
    from jsonb_array_elements(d -> 'relations') r cross join lateral jsonb_array_elements(r -> 'column_grants') g
  union all
  select 'trigger|' || (r ->> 'name') || '|' || (t ->> 'name'), 'trigger',
         jsonb_build_object('enabled', t -> 'enabled', 'function', t -> 'function')
    from jsonb_array_elements(d -> 'relations') r cross join lateral jsonb_array_elements(r -> 'triggers') t
  union all
  select 'policy|' || (p ->> 'table') || '|' || (p ->> 'name'), 'policy',
         jsonb_build_object('command', p -> 'command', 'permissive', p -> 'permissive', 'roles', p -> 'roles',
                            'using', p -> 'using', 'check', p -> 'check')
    from jsonb_array_elements(d -> 'policies') p;
$$;

-- Advisory classification. Mirrored 1:1 by classifyFinding() in internal/gov003/server/grant-diff.mjs.
create function c10_gov003_demo._finding_class(
  ftype text, change text, fkey text, bval jsonb, cval jsonb, is_definer boolean)
returns text[]
language plpgsql immutable
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
declare
  grantee text; priv text;
begin
  if ftype = 'function_grant' then
    grantee := split_part(fkey, '|', 3); priv := split_part(fkey, '|', 4);
    if change = 'added' then
      if grantee in ('PUBLIC','c10g3_app') then return array['high','GP01_EXEC_PUBLIC_OR_APP']; end if;
      if coalesce(is_definer, false) then return array['high','GP02_EXEC_DEFINER_WIDENED']; end if;
      return array['medium','GP03_EXEC_GRANT_ADDED'];
    elsif change = 'removed' then return array['low','GP04_GRANT_REMOVED'];
    else return array['medium','GP03_EXEC_GRANT_ADDED'];
    end if;
  elsif ftype = 'relation_grant' then
    grantee := split_part(fkey, '|', 3); priv := split_part(fkey, '|', 4);
    if change = 'added' then
      if priv in ('INSERT','UPDATE','DELETE','TRUNCATE') then return array['high','GP05_WRITE_GRANT_ADDED']; end if;
      if grantee in ('PUBLIC','c10g3_app') then return array['high','GP06_READ_GRANT_WIDENED']; end if;
      return array['medium','GP07_TABLE_GRANT_ADDED'];
    elsif change = 'removed' then return array['low','GP04_GRANT_REMOVED'];
    else return array['medium','GP07_TABLE_GRANT_ADDED'];
    end if;
  elsif ftype = 'column_grant' then
    priv := split_part(fkey, '|', 5);
    if change = 'added' then
      if priv in ('INSERT','UPDATE') then return array['high','GP05_WRITE_GRANT_ADDED']; end if;
      return array['medium','GP07_TABLE_GRANT_ADDED'];
    elsif change = 'removed' then return array['low','GP04_GRANT_REMOVED'];
    else return array['medium','GP07_TABLE_GRANT_ADDED'];
    end if;
  elsif ftype = 'schema_grant' then
    grantee := split_part(fkey, '|', 2); priv := split_part(fkey, '|', 3);
    if change = 'added' then
      if priv = 'CREATE' or grantee = 'PUBLIC' then return array['high','GP08_SCHEMA_PRIVILEGE_WIDENED']; end if;
      return array['medium','GP09_SCHEMA_GRANT_ADDED'];
    elsif change = 'removed' then return array['low','GP04_GRANT_REMOVED'];
    else return array['medium','GP09_SCHEMA_GRANT_ADDED'];
    end if;
  elsif ftype = 'function' then
    if change = 'added' then
      if coalesce((cval ->> 'security_definer')::boolean, false) then return array['medium','GP15_DEFINER_FUNCTION_ADDED']; end if;
      return array['low','GP16_FUNCTION_ADDED_OR_REMOVED'];
    elsif change = 'removed' then return array['low','GP16_FUNCTION_ADDED_OR_REMOVED'];
    else return array['high','GP17_FUNCTION_ATTRIBUTE_CHANGED'];
    end if;
  elsif ftype = 'relation' then
    if change = 'added' then return array['medium','GP10_RELATION_ADDED'];
    elsif change = 'removed' then return array['low','GP11_RELATION_REMOVED'];
    else
      if coalesce((bval ->> 'rls_enabled')::boolean, false) and not coalesce((cval ->> 'rls_enabled')::boolean, false) then
        return array['high','GP12_RLS_DISABLED'];
      end if;
      if (bval -> 'options') ? 'security_invoker=true' and not ((cval -> 'options') ? 'security_invoker=true') then
        return array['high','GP14_VIEW_INVOKER_LOST'];
      end if;
      return array['medium','GP13_RELATION_ATTRIBUTE_CHANGED'];
    end if;
  elsif ftype = 'policy' then
    if change = 'added' then
      if coalesce((cval ->> 'permissive')::boolean, false) then return array['high','GP20_PERMISSIVE_POLICY_ADDED']; end if;
      return array['low','GP21_RESTRICTIVE_POLICY_ADDED'];
    elsif change = 'removed' then
      if not coalesce((bval ->> 'permissive')::boolean, true) then return array['high','GP22_RESTRICTIVE_POLICY_REMOVED']; end if;
      return array['low','GP23_POLICY_REMOVED'];
    else
      if not coalesce((bval ->> 'permissive')::boolean, false) and coalesce((cval ->> 'permissive')::boolean, false) then
        return array['high','GP25_POLICY_MADE_PERMISSIVE'];
      end if;
      return array['medium','GP24_POLICY_CHANGED'];
    end if;
  elsif ftype = 'trigger' then
    if change = 'removed' then return array['high','GP30_TRIGGER_REMOVED']; end if;
    if change = 'changed' and (cval ->> 'enabled') <> 'O' then return array['high','GP31_TRIGGER_DISABLED']; end if;
    return array['low','GP32_TRIGGER_ADDED_OR_RESTORED'];
  end if;
  return array['medium','GP99_UNCLASSIFIED'];
end $$;

-- Pure comparator over two snapshot documents. Owner-only: it is NOT granted to any other role, so a
-- caller cannot use it to obtain an authoritative-looking comparison against a baseline of their choosing.
create function c10_gov003_demo.catalog_diff(p_baseline jsonb, p_current jsonb) returns jsonb
language plpgsql stable
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
declare
  fnd jsonb; n int; hi int; me int; lo int; mx text;
begin
  if p_baseline ->> 'format' is distinct from 'g3cat-v1' or p_current ->> 'format' is distinct from 'g3cat-v1' then
    raise exception 'invalid_snapshot_format' using errcode = 'G3A03';
  end if;
  with b as (select * from c10_gov003_demo._catalog_facts(p_baseline)),
       c as (select * from c10_gov003_demo._catalog_facts(p_current)),
       j as (
         select coalesce(c.fkey, b.fkey) as fkey, coalesce(c.ftype, b.ftype) as ftype,
                b.fval as bval, c.fval as cval,
                case when b.fkey is null then 'added' when c.fkey is null then 'removed' else 'changed' end as chg
           from b full join c on b.fkey = c.fkey
          where b.fkey is null or c.fkey is null or b.fval is distinct from c.fval),
       k as (
         select j.*, c10_gov003_demo._finding_class(
                  j.ftype, j.chg, j.fkey, j.bval, j.cval,
                  (select (c2.fval ->> 'security_definer')::boolean from c c2
                    where c2.fkey = 'function|' || split_part(j.fkey, '|', 2))) as cls
           from j)
  select coalesce(jsonb_agg(jsonb_build_object(
           'key', k.fkey, 'change', k.chg, 'fact_type', k.ftype, 'severity', k.cls[1], 'rule', k.cls[2],
           'baseline', k.bval, 'current', k.cval) order by k.fkey collate "C"), '[]'::jsonb)
    into fnd from k;
  n := jsonb_array_length(fnd);
  select count(*) filter (where x ->> 'severity' = 'high'), count(*) filter (where x ->> 'severity' = 'medium'),
         count(*) filter (where x ->> 'severity' = 'low')
    into hi, me, lo from jsonb_array_elements(fnd) x;
  mx := case when hi > 0 then 'high' when me > 0 then 'medium' when lo > 0 then 'low' else 'none' end;
  return jsonb_build_object(
    'format', 'g3catdiff-v1',
    'label', 'ADVISORY',
    'baseline_sha256', c10_gov003_demo.g3_sha256(c10_gov003_demo.canonical_json(p_baseline)),
    'current_sha256', c10_gov003_demo.g3_sha256(c10_gov003_demo.canonical_json(p_current)),
    'finding_count', n,
    'max_severity', mx,
    'severity_counts', jsonb_build_object('high', hi, 'medium', me, 'low', lo),
    'findings', fnd);
end $$;

-- ---------------------------------------------------------------------------------------------------
-- Append-only stores. Rows exist only through the SECURITY DEFINER functions below.
-- ---------------------------------------------------------------------------------------------------
create table c10_gov003_demo.catalog_snapshots (
  snapshot_id      uuid primary key,
  tenant_id        uuid not null,
  business_id      uuid not null,
  purpose          text not null check (purpose in ('snapshot','baseline','diff')),
  request_idem     text not null check (request_idem ~ '^[A-Za-z0-9_.:-]{8,128}$'),
  taken_by         uuid not null references c10_gov003_demo.identities,
  taken_at         timestamptz not null default clock_timestamp(),
  format_version   text not null check (format_version = 'g3cat-v1'),
  inventory        jsonb not null,
  inventory_sha256 text not null check (inventory_sha256 ~ '^[0-9a-f]{64}$'),
  item_count       int not null check (item_count >= 0),
  event_id         uuid not null references c10_gov003_demo.audit_events,
  receipt_id       uuid not null references c10_gov003_demo.audit_receipts,
  unique (snapshot_id, tenant_id, business_id),
  unique (tenant_id, business_id, request_idem),
  foreign key (tenant_id, business_id) references c10_gov003_demo.businesses
);
select c10_gov003_demo.protect_table('c10_gov003_demo.catalog_snapshots');

create table c10_gov003_demo.catalog_baselines (
  baseline_id      uuid primary key,
  tenant_id        uuid not null,
  business_id      uuid not null,
  baseline_seq     int not null check (baseline_seq >= 1),
  snapshot_id      uuid not null,
  approved_by      uuid not null references c10_gov003_demo.identities,   -- derived server-side
  approved_at      timestamptz not null default clock_timestamp(),
  inventory        jsonb not null,
  inventory_sha256 text not null check (inventory_sha256 ~ '^[0-9a-f]{64}$'),
  supersedes       uuid references c10_gov003_demo.catalog_baselines,
  event_id         uuid not null references c10_gov003_demo.audit_events,
  receipt_id       uuid not null references c10_gov003_demo.audit_receipts,
  request_idem     text not null check (request_idem ~ '^[A-Za-z0-9_.:-]{8,128}$'),
  unique (baseline_id, tenant_id, business_id),
  unique (tenant_id, business_id, baseline_seq),
  unique (tenant_id, business_id, request_idem),
  foreign key (snapshot_id, tenant_id, business_id)
    references c10_gov003_demo.catalog_snapshots (snapshot_id, tenant_id, business_id)
);
select c10_gov003_demo.protect_table('c10_gov003_demo.catalog_baselines');

create table c10_gov003_demo.catalog_diffs (
  diff_id         uuid primary key,
  tenant_id       uuid not null,
  business_id     uuid not null,
  baseline_id     uuid not null,
  snapshot_id     uuid not null,
  label           text not null default 'ADVISORY' check (label = 'ADVISORY'),
  diff            jsonb not null,
  diff_sha256     text not null check (diff_sha256 ~ '^[0-9a-f]{64}$'),
  finding_count   int not null check (finding_count >= 0),
  max_severity    text not null check (max_severity in ('none','low','medium','high')),
  requested_by    uuid not null references c10_gov003_demo.identities,
  requested_at    timestamptz not null default clock_timestamp(),
  request_idem    text not null check (request_idem ~ '^[A-Za-z0-9_.:-]{8,128}$'),
  signal_id       uuid,
  event_id        uuid not null references c10_gov003_demo.audit_events,
  receipt_id      uuid not null references c10_gov003_demo.audit_receipts,
  unique (tenant_id, business_id, request_idem),
  foreign key (baseline_id, tenant_id, business_id)
    references c10_gov003_demo.catalog_baselines (baseline_id, tenant_id, business_id),
  foreign key (snapshot_id, tenant_id, business_id)
    references c10_gov003_demo.catalog_snapshots (snapshot_id, tenant_id, business_id)
);
select c10_gov003_demo.protect_table('c10_gov003_demo.catalog_diffs');

alter table c10_gov003_demo.catalog_snapshots enable row level security;
alter table c10_gov003_demo.catalog_baselines enable row level security;
alter table c10_gov003_demo.catalog_diffs enable row level security;
create policy catalog_snapshots_read on c10_gov003_demo.catalog_snapshots for select
  to c10g3_reader, c10g3_backend using (c10_gov003_demo.can_read_business(tenant_id, business_id));
create policy catalog_baselines_read on c10_gov003_demo.catalog_baselines for select
  to c10g3_reader, c10g3_backend using (c10_gov003_demo.can_read_business(tenant_id, business_id));
create policy catalog_diffs_read on c10_gov003_demo.catalog_diffs for select
  to c10g3_reader, c10g3_backend using (c10_gov003_demo.can_read_business(tenant_id, business_id));
revoke all on c10_gov003_demo.catalog_snapshots, c10_gov003_demo.catalog_baselines,
              c10_gov003_demo.catalog_diffs from public;
grant select on c10_gov003_demo.catalog_snapshots, c10_gov003_demo.catalog_baselines,
                c10_gov003_demo.catalog_diffs to c10g3_reader, c10g3_backend;

create view c10_gov003_demo.v_catalog_snapshots with (security_invoker = true) as
  select s.snapshot_id, s.tenant_id, s.business_id, s.purpose, s.taken_by, s.taken_at, s.format_version,
         s.inventory, s.inventory_sha256, s.item_count, s.receipt_id
    from c10_gov003_demo.catalog_snapshots s;
create view c10_gov003_demo.v_catalog_baselines with (security_invoker = true) as
  select b.baseline_id, b.tenant_id, b.business_id, b.baseline_seq, b.snapshot_id, b.approved_by,
         b.approved_at, b.inventory, b.inventory_sha256, b.supersedes, b.receipt_id
    from c10_gov003_demo.catalog_baselines b;
create view c10_gov003_demo.v_catalog_diffs with (security_invoker = true) as
  select d.diff_id, d.tenant_id, d.business_id, d.baseline_id, d.snapshot_id, d.label, d.diff, d.diff_sha256,
         d.finding_count, d.max_severity, d.requested_by, d.requested_at, d.signal_id, d.receipt_id
    from c10_gov003_demo.catalog_diffs d;
revoke all on c10_gov003_demo.v_catalog_snapshots, c10_gov003_demo.v_catalog_baselines,
              c10_gov003_demo.v_catalog_diffs from public;
grant select on c10_gov003_demo.v_catalog_snapshots, c10_gov003_demo.v_catalog_baselines,
                c10_gov003_demo.v_catalog_diffs to c10g3_reader, c10g3_backend;

-- ---------------------------------------------------------------------------------------------------
-- Snapshot (owner of that business only). Read-only against the catalog; records a stored snapshot +
-- the business's audit receipt. Same idempotency key by the same actor returns the stored snapshot.
-- ---------------------------------------------------------------------------------------------------
create function c10_gov003_demo.take_snapshot(
  p_tenant uuid, p_business uuid, p_idem text, p_claimed_actor uuid default null)
returns table (snapshot_id uuid, receipt_id uuid, inventory_sha256 text, item_count int, replayed boolean)
language plpgsql security definer
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
#variable_conflict use_column
declare
  a uuid := c10_gov003_demo.actor_id();
  ex record; inv jsonb; sha text; cnt int; sid uuid := gen_random_uuid(); rc record;
begin
  if a is null then raise exception 'actor_unauthenticated' using errcode = 'G3A05'; end if;
  if p_claimed_actor is not null and p_claimed_actor <> a then
    raise exception 'forged_actor: caller-supplied actor does not match the server-derived actor'
      using errcode = 'G3A01';
  end if;
  if p_tenant is null or p_business is null
     or not c10_gov003_demo.scope_exists(p_tenant, p_business, null, null)
     or not c10_gov003_demo.can_read_business(p_tenant, p_business) then
    raise exception 'scope_denied' using errcode = 'G3A02';
  end if;
  if p_idem is null or p_idem !~ '^[A-Za-z0-9_.:-]{8,120}$' then
    raise exception 'invalid_input: idempotency key' using errcode = 'G3A03';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('g3catalog|' || p_tenant || '|' || p_business, 0));

  select s.snapshot_id as sid, s.receipt_id as rid, s.inventory_sha256 as sha, s.item_count as cnt,
         s.taken_by as who, s.purpose as purpose into ex
    from c10_gov003_demo.catalog_snapshots s
   where s.tenant_id = p_tenant and s.business_id = p_business and s.request_idem = p_idem;
  if found then
    if ex.who = a and ex.purpose = 'snapshot' then
      return query select ex.sid, ex.rid, ex.sha, ex.cnt, true;
      return;
    end if;
    raise exception 'idempotency_conflict: key already used for a different request' using errcode = 'G3C01';
  end if;

  inv := c10_gov003_demo._catalog_inventory();
  sha := c10_gov003_demo.g3_sha256(c10_gov003_demo.canonical_json(inv));
  cnt := jsonb_array_length(inv -> 'functions') + jsonb_array_length(inv -> 'relations')
       + jsonb_array_length(inv -> 'policies');
  select * into rc from c10_gov003_demo._append_audit(p_tenant, p_business, null, null,
    'gov003.grants', 'snapshot-' || sid::text, 'v1', 'grant.snapshot_taken', clock_timestamp(),
    'grant-snapshot-' || sid::text, 'grant-snapshot:' || sid::text,
    jsonb_build_object('entity_ref', sid::text, 'artifact_sha256', sha, 'count', cnt::text,
                       'note_code', 'advisory_only'),
    null, 'security', 1, null, null);
  perform set_config('c10_gov003.writer', 'append_path', true);
  insert into c10_gov003_demo.catalog_snapshots
    (snapshot_id, tenant_id, business_id, purpose, request_idem, taken_by, format_version, inventory,
     inventory_sha256, item_count, event_id, receipt_id)
  values (sid, p_tenant, p_business, 'snapshot', p_idem, a, 'g3cat-v1', inv, sha, cnt, rc.event_id, rc.receipt_id);
  perform set_config('c10_gov003.writer', '', true);
  return query select sid, rc.receipt_id, sha, cnt, false;
end $$;

-- ---------------------------------------------------------------------------------------------------
-- Baseline approval. The baseline is ALWAYS a server-side inventory: either a fresh one, or a snapshot
-- already stored for the same business. approved_by is the server-derived actor. No JSON is accepted.
-- ---------------------------------------------------------------------------------------------------
create function c10_gov003_demo.record_baseline(
  p_tenant uuid, p_business uuid, p_idem text, p_claimed_actor uuid default null, p_snapshot_id uuid default null)
returns table (baseline_id uuid, baseline_seq int, snapshot_id uuid, receipt_id uuid, inventory_sha256 text,
               replayed boolean)
language plpgsql security definer
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
#variable_conflict use_column
declare
  a uuid := c10_gov003_demo.actor_id();
  ex record; sn record; prev record; inv jsonb; sha text; cnt int; sid uuid; bid uuid := gen_random_uuid();
  seq int; rc record;
begin
  if a is null then raise exception 'actor_unauthenticated' using errcode = 'G3A05'; end if;
  if p_claimed_actor is not null and p_claimed_actor <> a then
    raise exception 'forged_actor: caller-supplied actor does not match the server-derived actor'
      using errcode = 'G3A01';
  end if;
  if p_tenant is null or p_business is null
     or not c10_gov003_demo.scope_exists(p_tenant, p_business, null, null)
     or not c10_gov003_demo.can_read_business(p_tenant, p_business) then
    raise exception 'scope_denied' using errcode = 'G3A02';
  end if;
  if p_idem is null or p_idem !~ '^[A-Za-z0-9_.:-]{8,120}$' then
    raise exception 'invalid_input: idempotency key' using errcode = 'G3A03';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('g3catalog|' || p_tenant || '|' || p_business, 0));

  select b.baseline_id as bid, b.baseline_seq as seq, b.snapshot_id as sid, b.receipt_id as rid,
         b.inventory_sha256 as sha, b.approved_by as who into ex
    from c10_gov003_demo.catalog_baselines b
   where b.tenant_id = p_tenant and b.business_id = p_business and b.request_idem = p_idem;
  if found then
    if ex.who = a then
      return query select ex.bid, ex.seq, ex.sid, ex.rid, ex.sha, true;
      return;
    end if;
    raise exception 'idempotency_conflict: key already used for a different request' using errcode = 'G3C01';
  end if;

  if p_snapshot_id is not null then
    select s.snapshot_id as sid, s.inventory as inv, s.inventory_sha256 as sha, s.item_count as cnt into sn
      from c10_gov003_demo.catalog_snapshots s
     where s.snapshot_id = p_snapshot_id and s.tenant_id = p_tenant and s.business_id = p_business;
    if not found then raise exception 'scope_denied' using errcode = 'G3A02'; end if;
    sid := sn.sid; inv := sn.inv; sha := sn.sha; cnt := sn.cnt;
  else
    inv := c10_gov003_demo._catalog_inventory();
    sha := c10_gov003_demo.g3_sha256(c10_gov003_demo.canonical_json(inv));
    cnt := jsonb_array_length(inv -> 'functions') + jsonb_array_length(inv -> 'relations')
         + jsonb_array_length(inv -> 'policies');
    sid := gen_random_uuid();
  end if;

  select b.baseline_id as bid, b.baseline_seq as seq into prev
    from c10_gov003_demo.catalog_baselines b
   where b.tenant_id = p_tenant and b.business_id = p_business order by b.baseline_seq desc limit 1;
  seq := coalesce(prev.seq, 0) + 1;

  select * into rc from c10_gov003_demo._append_audit(p_tenant, p_business, null, null,
    'gov003.grants', 'baseline-' || bid::text, 'v1', 'grant.baseline_approved', clock_timestamp(),
    'grant-baseline-' || bid::text, 'grant-baseline:' || bid::text,
    jsonb_build_object('entity_ref', bid::text, 'artifact_sha256', sha, 'count', cnt::text,
                       'note_code', 'baseline_approved'),
    null, 'security', 1, null, null);
  perform set_config('c10_gov003.writer', 'append_path', true);
  if p_snapshot_id is null then
    insert into c10_gov003_demo.catalog_snapshots
      (snapshot_id, tenant_id, business_id, purpose, request_idem, taken_by, format_version, inventory,
       inventory_sha256, item_count, event_id, receipt_id)
    values (sid, p_tenant, p_business, 'baseline', 'bl-' || p_idem, a, 'g3cat-v1', inv, sha, cnt,
            rc.event_id, rc.receipt_id);
  end if;
  insert into c10_gov003_demo.catalog_baselines
    (baseline_id, tenant_id, business_id, baseline_seq, snapshot_id, approved_by, inventory,
     inventory_sha256, supersedes, event_id, receipt_id, request_idem)
  values (bid, p_tenant, p_business, seq, sid, a, inv, sha, prev.bid, rc.event_id, rc.receipt_id, p_idem);
  perform set_config('c10_gov003.writer', '', true);
  return query select bid, seq, sid, rc.receipt_id, sha, false;
end $$;

-- ---------------------------------------------------------------------------------------------------
-- Diff the LIVE catalog against the stored approved baseline (latest, or a named baseline of the same
-- business). Stores the current snapshot and the diff, appends a receipt, and - only if findings exist -
-- raises one advisory risk signal (rule grant_policy_diff) through 080. Changes NOTHING in the catalog.
-- ---------------------------------------------------------------------------------------------------
create function c10_gov003_demo.diff_against_baseline(
  p_tenant uuid, p_business uuid, p_idem text, p_claimed_actor uuid default null, p_baseline_id uuid default null)
returns table (diff_id uuid, baseline_id uuid, snapshot_id uuid, receipt_id uuid, finding_count int,
               max_severity text, diff_sha256 text, signal_id uuid, replayed boolean)
language plpgsql security definer
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
#variable_conflict use_column
declare
  a uuid := c10_gov003_demo.actor_id();
  ex record; bl record; inv jsonb; sha text; cnt int; sid uuid := gen_random_uuid(); did uuid := gen_random_uuid();
  dif jsonb; dsha text; fc int; mx text; rc record; sg record; sig uuid;
begin
  if a is null then raise exception 'actor_unauthenticated' using errcode = 'G3A05'; end if;
  if p_claimed_actor is not null and p_claimed_actor <> a then
    raise exception 'forged_actor: caller-supplied actor does not match the server-derived actor'
      using errcode = 'G3A01';
  end if;
  if p_tenant is null or p_business is null
     or not c10_gov003_demo.scope_exists(p_tenant, p_business, null, null)
     or not c10_gov003_demo.can_read_business(p_tenant, p_business) then
    raise exception 'scope_denied' using errcode = 'G3A02';
  end if;
  if p_idem is null or p_idem !~ '^[A-Za-z0-9_.:-]{8,120}$' then
    raise exception 'invalid_input: idempotency key' using errcode = 'G3A03';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('g3catalog|' || p_tenant || '|' || p_business, 0));

  select d.diff_id as did, d.baseline_id as bid, d.snapshot_id as sid, d.receipt_id as rid,
         d.finding_count as fc, d.max_severity as mx, d.diff_sha256 as dsha, d.signal_id as sig,
         d.requested_by as who into ex
    from c10_gov003_demo.catalog_diffs d
   where d.tenant_id = p_tenant and d.business_id = p_business and d.request_idem = p_idem;
  if found then
    if ex.who = a then
      return query select ex.did, ex.bid, ex.sid, ex.rid, ex.fc, ex.mx, ex.dsha, ex.sig, true;
      return;
    end if;
    raise exception 'idempotency_conflict: key already used for a different request' using errcode = 'G3C01';
  end if;

  if p_baseline_id is null then
    select b.baseline_id as bid, b.inventory as inv, b.inventory_sha256 as sha into bl
      from c10_gov003_demo.catalog_baselines b
     where b.tenant_id = p_tenant and b.business_id = p_business order by b.baseline_seq desc limit 1;
    if not found then
      raise exception 'baseline_missing: no owner-approved baseline is stored for this business' using errcode = 'G3C03';
    end if;
  else
    -- A baseline of another business/tenant, or an unknown id, is indistinguishable: scope_denied.
    select b.baseline_id as bid, b.inventory as inv, b.inventory_sha256 as sha into bl
      from c10_gov003_demo.catalog_baselines b
     where b.baseline_id = p_baseline_id and b.tenant_id = p_tenant and b.business_id = p_business;
    if not found then raise exception 'scope_denied' using errcode = 'G3A02'; end if;
  end if;
  -- Integrity of the stored baseline itself (a tampered row is rejected, never trusted).
  if bl.sha <> c10_gov003_demo.g3_sha256(c10_gov003_demo.canonical_json(bl.inv)) then
    raise exception 'baseline_integrity_failed: stored baseline does not match its digest' using errcode = 'G3A04';
  end if;

  inv := c10_gov003_demo._catalog_inventory();
  sha := c10_gov003_demo.g3_sha256(c10_gov003_demo.canonical_json(inv));
  cnt := jsonb_array_length(inv -> 'functions') + jsonb_array_length(inv -> 'relations')
       + jsonb_array_length(inv -> 'policies');
  dif := c10_gov003_demo.catalog_diff(bl.inv, inv);
  dsha := c10_gov003_demo.g3_sha256(c10_gov003_demo.canonical_json(dif));
  fc := (dif ->> 'finding_count')::int;
  mx := dif ->> 'max_severity';

  select * into rc from c10_gov003_demo._append_audit(p_tenant, p_business, null, null,
    'gov003.grants', 'diff-' || did::text, 'v1', 'grant.diff_recorded', clock_timestamp(),
    'grant-diff-' || did::text, 'grant-diff:' || did::text,
    jsonb_build_object('entity_ref', did::text, 'source_ref', bl.bid::text, 'artifact_sha256', dsha,
                       'count', fc::text, 'severity', mx, 'note_code', 'advisory_only'),
    null, 'security', 1, null, null);
  perform set_config('c10_gov003.writer', 'append_path', true);
  insert into c10_gov003_demo.catalog_snapshots
    (snapshot_id, tenant_id, business_id, purpose, request_idem, taken_by, format_version, inventory,
     inventory_sha256, item_count, event_id, receipt_id)
  values (sid, p_tenant, p_business, 'diff', 'df-' || p_idem, a, 'g3cat-v1', inv, sha, cnt, rc.event_id, rc.receipt_id);
  perform set_config('c10_gov003.writer', '', true);

  if fc > 0 then
    select * into sg from c10_gov003_demo._emit_signal(p_tenant, p_business, 'grant_policy_diff',
      'grantdiff:' || bl.bid::text || ':' || dsha, mx, 90,
      format('Advisory only: the live permission catalog differs from the owner-approved baseline in %s item(s), '
             'highest advisory severity %s. The change may be intentional; human review is required. '
             'No permission was changed automatically.', fc, mx),
      'gov003.grants',
      jsonb_build_object('entity_ref', did::text, 'count', fc::text, 'severity', mx,
                         'detail_code', 'catalog_differs'),
      null, null, jsonb_build_array(jsonb_build_object('kind', 'catalog_diff', 'ref', did::text)),
      array[a]);
    sig := sg.signal_id;
  end if;

  perform set_config('c10_gov003.writer', 'append_path', true);
  insert into c10_gov003_demo.catalog_diffs
    (diff_id, tenant_id, business_id, baseline_id, snapshot_id, diff, diff_sha256, finding_count, max_severity,
     requested_by, request_idem, signal_id, event_id, receipt_id)
  values (did, p_tenant, p_business, bl.bid, sid, dif, dsha, fc, mx, a, p_idem, sig, rc.event_id, rc.receipt_id);
  perform set_config('c10_gov003.writer', '', true);
  return query select did, bl.bid, sid, rc.receipt_id, fc, mx, dsha, sig, false;
end $$;

-- ---------------------------------------------------------------------------------------------------
-- Grants: public RPCs -> trusted backend only. Internals (inventory, facts, comparator) -> owner only.
-- ---------------------------------------------------------------------------------------------------
revoke all on function
  c10_gov003_demo._catalog_inventory(),
  c10_gov003_demo._catalog_facts(jsonb),
  c10_gov003_demo._finding_class(text,text,text,jsonb,jsonb,boolean),
  c10_gov003_demo.catalog_diff(jsonb,jsonb),
  c10_gov003_demo.take_snapshot(uuid,uuid,text,uuid),
  c10_gov003_demo.record_baseline(uuid,uuid,text,uuid,uuid),
  c10_gov003_demo.diff_against_baseline(uuid,uuid,text,uuid,uuid)
  from public;
grant execute on function
  c10_gov003_demo.take_snapshot(uuid,uuid,text,uuid),
  c10_gov003_demo.record_baseline(uuid,uuid,text,uuid,uuid),
  c10_gov003_demo.diff_against_baseline(uuid,uuid,text,uuid,uuid)
  to c10g3_backend;
