-- Tenancy fixtures model: tenants, businesses, legal entities, sites, inert identities, memberships.
-- Identities are INERT FIXTURE UUIDs. They are not signed GoTrue evidence (future blocker).
set role c10g3_owner;
set search_path = pg_catalog, c10_gov003_demo, pg_temp;

create table c10_gov003_demo.tenants (
  tenant_id  uuid primary key,
  name       text not null,
  created_at timestamptz not null default now()
);

create table c10_gov003_demo.businesses (
  tenant_id   uuid not null references c10_gov003_demo.tenants,
  business_id uuid not null,
  name        text not null,
  primary key (tenant_id, business_id),
  unique (business_id)
);

create table c10_gov003_demo.legal_entities (
  tenant_id       uuid not null,
  business_id     uuid not null,
  legal_entity_id uuid not null,
  name            text not null,
  primary key (tenant_id, business_id, legal_entity_id),
  foreign key (tenant_id, business_id) references c10_gov003_demo.businesses
);

create table c10_gov003_demo.sites (
  tenant_id   uuid not null,
  business_id uuid not null,
  site_id     uuid not null,
  name        text not null,
  primary key (tenant_id, business_id, site_id),
  unique (site_id),
  foreign key (tenant_id, business_id) references c10_gov003_demo.businesses
);

create table c10_gov003_demo.identities (
  identity_id uuid primary key,
  label       text not null,
  is_fixture  boolean not null default true check (is_fixture)
);

create table c10_gov003_demo.memberships (
  membership_id bigint generated always as identity primary key,
  identity_id   uuid not null references c10_gov003_demo.identities,
  tenant_id     uuid not null references c10_gov003_demo.tenants,
  business_id   uuid,
  site_id       uuid,
  role          text not null check (role in
                  ('tenant_owner','business_owner','staff','investor','support_operator')),
  status        text not null default 'active' check (status in ('active','revoked')),
  granted_at    timestamptz not null default now(),
  revoked_at    timestamptz,
  check (site_id is null or business_id is not null),
  check ((status = 'revoked') = (revoked_at is not null)),
  foreign key (tenant_id, business_id) references c10_gov003_demo.businesses,
  foreign key (tenant_id, business_id, site_id) references c10_gov003_demo.sites
);
create index memberships_identity_idx on c10_gov003_demo.memberships (identity_id, status);

-- The only source of actor identity. Simulated request.jwt.claim.sub is allowed in isolated tests ONLY.
-- Returns NULL (fail closed) if the claim is absent, malformed, or not a known fixture identity.
create function c10_gov003_demo.actor_id() returns uuid
language plpgsql stable security definer
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
declare v text; u uuid;
begin
  v := nullif(current_setting('request.jwt.claim.sub', true), '');
  if v is null then return null; end if;
  begin u := v::uuid; exception when invalid_text_representation then return null; end;
  if not exists (select 1 from c10_gov003_demo.identities i where i.identity_id = u) then
    return null;
  end if;
  return u;
end $$;

-- True when the actor holds an ACTIVE membership with one of the roles that covers the target scope.
-- A site-scoped membership never covers a business-level (site-less) target.
create function c10_gov003_demo.has_scope_role(
  p_identity uuid, p_tenant uuid, p_business uuid, p_site uuid, p_roles text[])
returns boolean
language sql stable security definer
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
  select exists (
    select 1 from c10_gov003_demo.memberships m
    where m.identity_id = p_identity
      and m.status = 'active'
      and m.tenant_id = p_tenant
      and m.role = any (p_roles)
      and (m.business_id is null or m.business_id = p_business)
      and (m.site_id is null or m.site_id = p_site)
  );
$$;

-- Audit/journal read right: tenant_owner or business_owner only (site staff, investor, revoked, support: no).
create function c10_gov003_demo.can_read_business(p_tenant uuid, p_business uuid) returns boolean
language sql stable security definer
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
  select c10_gov003_demo.actor_id() is not null
     and c10_gov003_demo.has_scope_role(c10_gov003_demo.actor_id(), p_tenant, p_business, null,
                                        array['tenant_owner','business_owner']);
$$;

-- Event write right: owners and staff that cover the exact scope. Investors/support/revoked: no.
create function c10_gov003_demo.can_write_scope(p_tenant uuid, p_business uuid, p_site uuid) returns boolean
language sql stable security definer
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
  select c10_gov003_demo.actor_id() is not null
     and c10_gov003_demo.has_scope_role(c10_gov003_demo.actor_id(), p_tenant, p_business, p_site,
                                        array['tenant_owner','business_owner','staff']);
$$;

-- Scope integrity: business belongs to tenant, site belongs to business (same-scope FKs).
create function c10_gov003_demo.scope_exists(p_tenant uuid, p_business uuid, p_site uuid, p_entity uuid)
returns boolean
language sql stable security definer
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
  select exists (select 1 from c10_gov003_demo.businesses b
                  where b.tenant_id = p_tenant and b.business_id = p_business)
     and (p_site is null or exists (select 1 from c10_gov003_demo.sites s
                  where s.tenant_id = p_tenant and s.business_id = p_business and s.site_id = p_site))
     and (p_entity is null or exists (select 1 from c10_gov003_demo.legal_entities l
                  where l.tenant_id = p_tenant and l.business_id = p_business and l.legal_entity_id = p_entity));
$$;

-- Tenancy tables: no access for any non-owner role. Fixtures are read only through definer helpers.
alter table c10_gov003_demo.tenants enable row level security;
alter table c10_gov003_demo.businesses enable row level security;
alter table c10_gov003_demo.legal_entities enable row level security;
alter table c10_gov003_demo.sites enable row level security;
alter table c10_gov003_demo.identities enable row level security;
alter table c10_gov003_demo.memberships enable row level security;
revoke all on all tables in schema c10_gov003_demo from public;

revoke all on function c10_gov003_demo.actor_id() from public;
revoke all on function c10_gov003_demo.has_scope_role(uuid,uuid,uuid,uuid,text[]) from public;
revoke all on function c10_gov003_demo.can_read_business(uuid,uuid) from public;
revoke all on function c10_gov003_demo.can_write_scope(uuid,uuid,uuid) from public;
revoke all on function c10_gov003_demo.scope_exists(uuid,uuid,uuid,uuid) from public;
grant execute on function c10_gov003_demo.actor_id() to c10g3_backend, c10g3_reader, c10g3_app;
grant execute on function c10_gov003_demo.can_read_business(uuid,uuid) to c10g3_backend, c10g3_reader;
grant execute on function c10_gov003_demo.can_write_scope(uuid,uuid,uuid) to c10g3_backend;
