-- C10-A025 DISPOSABLE TEST FIXTURE ONLY. NEVER APPLY TO PRODUCTION. SYNTHETIC IDS. NOT SIGNED AUTH.
-- Stands in for canonical A018 (tenant/business/site) and A021/A034 (grants). In staging the view
-- c10_sim.grant_source / c10_sim.business_source must be re-pointed at the canonical objects (see handover).
create schema if not exists c10_sim_fixture;
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'sim_authenticated') then create role sim_authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'sim_anon') then create role sim_anon nologin; end if;
end $$;
create table c10_sim_fixture.businesses (id text primary key, tenant_id text not null, industry_id text not null);
create table c10_sim_fixture.sites (id text primary key, business_id text not null references c10_sim_fixture.businesses(id));
create table c10_sim_fixture.grants (user_id text not null, tenant_id text, business_id text, site_id text, cap text not null, revoked boolean not null default false);
insert into c10_sim_fixture.businesses values ('B-A1','T-ALPHA','sweets_bakery'),('B-A2','T-ALPHA','paint_hardware'),('B-B1','T-BRAVO','construction');
insert into c10_sim_fixture.sites values ('S-A1-SHOP1','B-A1'),('S-A1-SHOP2','B-A1'),('S-A1-FACTORY','B-A1'),('S-A2-STORE1','B-A2'),('S-A2-STORE2','B-A2'),('S-B1-PROJ1','B-B1'),('S-B1-PROJ2','B-B1');
-- caps by role (mirrors lib/demo-data.js)
create temp table _r(role text, cap text);
insert into _r values
 ('owner','sim.read'),('owner','sim.run'),('owner','sim.write'),('owner','sim.review'),('owner','sim.export'),('owner','sim.export_full'),('owner','sim.propose'),('owner','sim.share'),('owner','sim.comment'),('owner','sim.template_author'),
 ('finance','sim.read'),('finance','sim.run'),('finance','sim.write'),('finance','sim.export'),('finance','sim.export_full'),('finance','sim.comment'),
 ('accountant','sim.read'),('accountant','sim.run'),('accountant','sim.export'),('accountant','sim.comment'),
 ('manager','sim.read'),('manager','sim.run'),('manager','sim.write'),('manager','sim.comment'),
 ('clerk','sim.read'),('investor','sim.read_shared'),('auditor','sim.read'),('auditor','sim.export'),('auditor','sim.export_full'),('auditor','sim.comment');
-- (user, role, tenant, business, site, revoked)
create temp table _g(u text, role text, t text, b text, s text, rev boolean);
insert into _g values
 ('u_owner_a','owner','T-ALPHA',null,null,false),('u_owner_b','owner','T-BRAVO',null,null,false),('u_bizowner_a1','owner','T-ALPHA','B-A1',null,false),
 ('u_fin_a1','finance','T-ALPHA','B-A1',null,false),('u_acct_a1','accountant','T-ALPHA','B-A1',null,false),('u_sales_a1','manager','T-ALPHA','B-A1',null,false),
 ('u_branch_a1s1','manager','T-ALPHA','B-A1','S-A1-SHOP1',false),('u_inv_a1s1','clerk','T-ALPHA','B-A1','S-A1-SHOP1',false),('u_investor_a1','investor','T-ALPHA','B-A1',null,false),
 ('u_audit_a','auditor','T-ALPHA',null,null,false),('u_revoked','manager','T-ALPHA','B-A1',null,true),('u_hr_a1','accountant','T-ALPHA','B-A1',null,false);
insert into c10_sim_fixture.grants select g.u, g.t, g.b, g.s, r.cap, g.rev from _g g join _r r using (role);
-- users with NO grants (platform owner, cashier, site staff) simply have no rows.
-- Sentinels standing in for REAL canonical records: simulations must never change or even be able to touch them.
create table c10_sim_fixture.canonical_stock (sku text primary key, qty numeric);
create table c10_sim_fixture.canonical_sales (id int primary key, total numeric);
create table c10_sim_fixture.canonical_gl (id int primary key, dr numeric, cr numeric);
create table c10_sim_fixture.finance_months (m text primary key, profit numeric, manual_unverified boolean default true);
create table c10_sim_fixture.funding_payments (id int primary key, amount numeric);
create table c10_sim_fixture.payroll_records (id int primary key, amount numeric);
create table c10_sim_fixture.owner_settings (k text primary key, v jsonb);
insert into c10_sim_fixture.canonical_stock values ('X',10),('Y',5); insert into c10_sim_fixture.canonical_sales values (1,100),(2,250);
insert into c10_sim_fixture.canonical_gl values (1,100,0),(2,0,100); insert into c10_sim_fixture.finance_months values ('2026-10',12345,true);
insert into c10_sim_fixture.funding_payments values (1,500); insert into c10_sim_fixture.payroll_records values (1,9000); insert into c10_sim_fixture.owner_settings values ('module_visibility','{"simulation":false}');
