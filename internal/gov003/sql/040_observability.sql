-- 04 scope-safe-observability: allowlisted structured errors + tenant-safe view + support grants.
\set ON_ERROR_STOP on
set role c10g3_owner;
set search_path = pg_catalog, c10_gov003_demo, pg_temp;

create table c10_gov003_demo.error_catalog (
  error_code     text primary key check (error_code ~ '^[A-Z0-9_]{3,40}$'),
  public_message text not null,
  severity       text not null check (severity in ('info','warning','error','critical'))
);
insert into c10_gov003_demo.error_catalog values
  ('SOURCE_STALE',    'The source feed is stale.', 'warning'),
  ('COMMAND_REJECTED','A command was rejected.', 'error'),
  ('SCOPE_DENIED',    'Access outside the permitted scope was denied.', 'warning'),
  ('RECEIPT_MISMATCH','A receipt did not match the recorded evidence.', 'error'),
  ('EXPORT_FAILED',   'A report export failed.', 'error'),
  ('INTERNAL',        'An internal error occurred.', 'error');
alter table c10_gov003_demo.error_catalog enable row level security;
revoke all on c10_gov003_demo.error_catalog from public;

-- Removes tokens, JWTs, credentials, connection strings, emails, phones, card-like numbers and stack frames.
create function c10_gov003_demo.scrub_text(p text) returns text
language plpgsql immutable
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
declare s text := coalesce(p, '');
begin
  s := split_part(s, E'\n', 1);                                                        -- never keep stack frames
  s := regexp_replace(s, 'eyJ[A-Za-z0-9_-]{8,}(\.[A-Za-z0-9_-]+){0,2}', '[redacted-jwt]', 'g');
  s := regexp_replace(s, '(?i)bearer[[:space:]]+[A-Za-z0-9._~+/=-]+', 'bearer [redacted]', 'g');
  s := regexp_replace(s, '(?i)(postgres(ql)?|mysql|mongodb|redis|https?)://[^[:space:]]+', '[redacted-url]', 'g');
  s := regexp_replace(s, '(?i)(password|passwd|secret|api[_-]?key|token|service[_-]?role|authorization)[[:space:]]*[=:][[:space:]]*[^[:space:],;]+', '\1=[redacted]', 'g');
  s := regexp_replace(s, '[^[:space:]@]+@[^[:space:]@]+\.[A-Za-z]{2,}', '[redacted-email]', 'g');
  s := regexp_replace(s, '\+?[0-9][0-9 -]{7,}[0-9]', '[redacted-number]', 'g');
  s := regexp_replace(s, '(?i)\mat [A-Za-z0-9_.$<>]+ \([^)]*\)', '[frame]', 'g');
  return left(s, 300);
end $$;

create table c10_gov003_demo.safe_errors (
  error_id        uuid primary key default gen_random_uuid(),
  tenant_id       uuid not null,
  business_id     uuid not null,
  site_id         uuid,
  error_code      text not null references c10_gov003_demo.error_catalog,
  public_message  text not null,
  scrubbed_detail text not null,
  context         jsonb not null default '{}'::jsonb,
  correlation_id  text not null check (correlation_id ~ '^[A-Za-z0-9_.:-]{1,128}$'),
  actor_id        uuid not null references c10_gov003_demo.identities,
  occurred_at     timestamptz not null default clock_timestamp(),
  foreign key (tenant_id, business_id) references c10_gov003_demo.businesses,
  foreign key (tenant_id, business_id, site_id) references c10_gov003_demo.sites
);
select c10_gov003_demo.protect_table('c10_gov003_demo.safe_errors');

create table c10_gov003_demo.support_grants (
  grant_id         bigint generated always as identity primary key,
  support_identity uuid not null references c10_gov003_demo.identities,
  tenant_id        uuid not null,
  business_id      uuid not null,
  granted_by       uuid not null references c10_gov003_demo.identities,
  granted_at       timestamptz not null default clock_timestamp(),
  expires_at       timestamptz not null,
  revoked_at       timestamptz,
  foreign key (tenant_id, business_id) references c10_gov003_demo.businesses,
  check (expires_at > granted_at and expires_at <= granted_at + interval '7 days')
);
alter table c10_gov003_demo.support_grants enable row level security;

create function c10_gov003_demo.has_support_grant(p_tenant uuid, p_business uuid) returns boolean
language sql stable security definer
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
  select c10_gov003_demo.actor_id() is not null
     and c10_gov003_demo.has_scope_role(c10_gov003_demo.actor_id(), p_tenant, null, null, array['support_operator'])
     and exists (select 1 from c10_gov003_demo.support_grants g
                  where g.support_identity = c10_gov003_demo.actor_id()
                    and g.tenant_id = p_tenant and g.business_id = p_business
                    and g.revoked_at is null and g.expires_at > clock_timestamp());
$$;

alter table c10_gov003_demo.safe_errors enable row level security;
create policy safe_errors_read on c10_gov003_demo.safe_errors for select
  to c10g3_reader, c10g3_backend
  using (c10_gov003_demo.can_read_business(tenant_id, business_id)
         or c10_gov003_demo.has_support_grant(tenant_id, business_id));
revoke all on c10_gov003_demo.safe_errors, c10_gov003_demo.support_grants from public;
grant select on c10_gov003_demo.safe_errors to c10g3_reader, c10g3_backend;

create view c10_gov003_demo.v_safe_errors with (security_invoker = true) as
  select error_id, tenant_id, business_id, site_id, error_code, public_message, scrubbed_detail,
         context, correlation_id, occurred_at
    from c10_gov003_demo.safe_errors;
revoke all on c10_gov003_demo.v_safe_errors from public;
grant select on c10_gov003_demo.v_safe_errors to c10g3_reader, c10g3_backend;

create function c10_gov003_demo.record_safe_error(
  p_tenant uuid, p_business uuid, p_site uuid, p_code text, p_detail text,
  p_context jsonb, p_correlation text)
returns table (error_id uuid, error_code text, public_message text, scrubbed_detail text)
language plpgsql security definer
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
declare a uuid := c10_gov003_demo.actor_id(); cat record; v_id uuid := gen_random_uuid(); d text;
begin
  if a is null then raise exception 'actor_unauthenticated' using errcode = 'G3A05'; end if;
  if not c10_gov003_demo.scope_exists(p_tenant, p_business, p_site, null)
     or not c10_gov003_demo.can_write_scope(p_tenant, p_business, p_site) then
    raise exception 'scope_denied' using errcode = 'G3A02';
  end if;
  select c.error_code as code, c.public_message as msg into cat
    from c10_gov003_demo.error_catalog c where c.error_code = p_code;
  if not found then
    raise exception 'error_code_not_allowlisted' using errcode = 'G3A03';
  end if;
  perform c10_gov003_demo.validate_payload(coalesce(p_context, '{}'::jsonb));
  d := c10_gov003_demo.scrub_text(p_detail);
  perform set_config('c10_gov003.writer', 'append_path', true);
  insert into c10_gov003_demo.safe_errors
    (error_id, tenant_id, business_id, site_id, error_code, public_message, scrubbed_detail, context,
     correlation_id, actor_id)
  values (v_id, p_tenant, p_business, p_site, cat.code, cat.msg, d, coalesce(p_context, '{}'::jsonb),
          p_correlation, a);
  perform set_config('c10_gov003.writer', '', true);
  return query select v_id, cat.code, cat.msg, d;
end $$;

-- Business owners grant time-boxed, business-scoped support access. It is audited and never automatic.
create function c10_gov003_demo.grant_support_access(
  p_tenant uuid, p_business uuid, p_support_identity uuid, p_expires_at timestamptz, p_idem text)
returns table (grant_id bigint, receipt_id uuid)
language plpgsql security definer
set search_path = pg_catalog, c10_gov003_demo, pg_temp
as $$
declare a uuid := c10_gov003_demo.actor_id(); g bigint; rc record;
begin
  if a is null then raise exception 'actor_unauthenticated' using errcode = 'G3A05'; end if;
  if not c10_gov003_demo.can_read_business(p_tenant, p_business) then
    raise exception 'scope_denied' using errcode = 'G3A02';
  end if;
  if not c10_gov003_demo.has_scope_role(p_support_identity, p_tenant, null, null, array['support_operator']) then
    raise exception 'scope_denied: target is not an active support operator of this tenant' using errcode = 'G3A02';
  end if;
  insert into c10_gov003_demo.support_grants (support_identity, tenant_id, business_id, granted_by, expires_at)
    values (p_support_identity, p_tenant, p_business, a, p_expires_at)
    returning support_grants.grant_id into g;
  select * into rc from c10_gov003_demo._append_audit(p_tenant, p_business, null, null, 'gov003.support',
    'support-grant-' || g, 'v1', 'support.grant', clock_timestamp(), 'support-grant-' || g, p_idem,
    jsonb_build_object('entity_ref', p_support_identity::text, 'note_code', 'support_access_granted'),
    null, 'access', 1, null, null);
  return query select g, rc.receipt_id;
end $$;

revoke all on function c10_gov003_demo.scrub_text(text), c10_gov003_demo.has_support_grant(uuid,uuid),
  c10_gov003_demo.record_safe_error(uuid,uuid,uuid,text,text,jsonb,text),
  c10_gov003_demo.grant_support_access(uuid,uuid,uuid,timestamptz,text) from public;
grant execute on function c10_gov003_demo.scrub_text(text) to c10g3_backend, c10g3_reader;
grant execute on function c10_gov003_demo.has_support_grant(uuid,uuid) to c10g3_backend, c10g3_reader;
grant execute on function c10_gov003_demo.record_safe_error(uuid,uuid,uuid,text,text,jsonb,text) to c10g3_backend;
grant execute on function c10_gov003_demo.grant_support_access(uuid,uuid,uuid,timestamptz,text) to c10g3_backend;
