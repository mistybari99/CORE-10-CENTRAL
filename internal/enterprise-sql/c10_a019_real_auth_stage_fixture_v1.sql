-- C10-A019 / REV-009 — DISPOSABLE STAGING ONLY: six REAL Auth users -> canonical tenant/site fixture.
-- NOT an IMG-ERP-SG migration. DO NOT RUN against production or imported business data.
-- Operator must create a separate Supabase staging project, deploy REVIEWED c10_demo
-- schema, create six Auth users in GoTrue, verify their /auth/v1/user IDs, backup
-- disposable DB, and explicitly authorize seed. This SQL NEVER creates Auth users.
-- psql -X -v ON_ERROR_STOP=1 -v stage_ref=... -v stage_ack=I_CONFIRM_DISPOSABLE_STAGING \
--  -v tenantOwnerA=uuid -v tenantOwnerB=uuid -v siteStaffA=uuid \
--  -v investorA=uuid -v revokedA=uuid -v platformOperator=uuid \
--  -f internal/enterprise-sql/c10_a019_real_auth_stage_fixture_v1.sql
-- PSQL variables are UUIDs, NOT passwords or secret keys; do not record actual stage UUIDs in git.
\set ON_ERROR_STOP on
BEGIN;
CREATE TEMP TABLE c10_stage_fixture_gate_v1(
 stage_ref text NOT NULL,
 acknowledged text NOT NULL
) ON COMMIT DROP;
INSERT INTO c10_stage_fixture_gate_v1 VALUES
 (:'stage_ref', :'stage_ack');

CREATE TEMP TABLE c10_stage_fixture_principals_v1(
 role_name text PRIMARY KEY,
 auth_uid uuid NOT NULL UNIQUE
) ON COMMIT DROP;
INSERT INTO c10_stage_fixture_principals_v1(role_name,auth_uid)
VALUES
 ('tenantOwnerA', :'tenantOwnerA'::uuid),
 ('tenantOwnerB', :'tenantOwnerB'::uuid),
 ('siteStaffA', :'siteStaffA'::uuid),
 ('investorA', :'investorA'::uuid),
 ('revokedA', :'revokedA'::uuid),
 ('platformOperator', :'platformOperator'::uuid);

-- The guard runs BEFORE any persistent insert. A failed guard rolls back
-- all temporary constructs and cannot leave a partial role mapping.
DO $guard$
DECLARE g record;
BEGIN
 SELECT * INTO g FROM c10_stage_fixture_gate_v1;
 IF g.acknowledged IS DISTINCT FROM 'I_CONFIRM_DISPOSABLE_STAGING'
   OR g.stage_ref IS NULL OR g.stage_ref !~ '^[a-z0-9]{20}$'
   OR g.stage_ref='kbuhnpqooycqbzrfejcs' THEN
    RAISE EXCEPTION 'C10_STAGE_DISPOSABLE_PROJECT_AND_ACK_REQUIRED';
 END IF;
 IF to_regclass('auth.users') IS NULL THEN
    RAISE EXCEPTION 'C10_STAGE_REAL_AUTH_USERS_REQUIRED';
 END IF;
 IF to_regclass('c10_demo.tenants') IS NULL OR
    to_regclass('c10_demo.business_members') IS NULL OR
    to_regclass('c10_demo.site_grants') IS NULL OR
    to_regclass('c10_demo.sites') IS NULL THEN
    RAISE EXCEPTION 'C10_STAGE_CANONICAL_SCHEMA_NOT_INSTALLED';
 END IF;
 IF (SELECT count(*) FROM c10_stage_fixture_principals_v1)<>6
    OR (SELECT count(*) FROM auth.users u
        JOIN c10_stage_fixture_principals_v1 p ON p.auth_uid=u.id)<>6 THEN
    RAISE EXCEPTION 'C10_STAGE_SIX_EXISTING_GOTRUE_IDENTITIES_REQUIRED';
 END IF;
 IF EXISTS (SELECT 1 FROM c10_demo.tenants)
   OR EXISTS (SELECT 1 FROM c10_demo.businesses)
   OR EXISTS (SELECT 1 FROM c10_demo.sites)
   OR EXISTS (SELECT 1 FROM c10_demo.tenant_members)
   OR EXISTS (SELECT 1 FROM c10_demo.business_members)
   OR EXISTS (SELECT 1 FROM c10_demo.site_grants) THEN
    RAISE EXCEPTION 'C10_STAGE_REQUIRES_EMPTY_DISPOSABLE_SCHEMA';
 END IF;
END
$guard$;

-- Only isolated, non-operational synthetic business/site rows. None reference
-- Islamia historical tables, stock quantities, money, audit, or live user data.
INSERT INTO c10_demo.templates(code,source_status,demo_allowed,enterprise_certified)
VALUES ('food_manufacturing','available',true,false)
ON CONFLICT(code) DO NOTHING;
DO $guard$
BEGIN
 IF NOT EXISTS (
   SELECT 1 FROM c10_demo.templates
   WHERE code='food_manufacturing' AND demo_allowed=true AND enterprise_certified=false
 ) THEN RAISE EXCEPTION 'C10_STAGE_TEMPLATE_CONTRACT_INVALID'; END IF;
END
$guard$;

INSERT INTO c10_demo.tenants(id,slug)
VALUES (9101,'c10-auth-stage-owner-a'),(9201,'c10-auth-stage-owner-b');
INSERT INTO c10_demo.legal_entities(id,tenant_id,label)
VALUES (9111,9101,'Synthetic A Legal'),(9211,9201,'Synthetic B Legal');
INSERT INTO c10_demo.businesses(id,tenant_id,legal_entity_id,slug,template_code,request_key,status)
VALUES
 (91101,9101,9111,'synthetic-a','food_manufacturing','stage-a','draft'),
 (92201,9201,9211,'synthetic-b','food_manufacturing','stage-b','draft');
INSERT INTO c10_demo.sites(id,tenant_id,business_id,kind,label,request_key)
VALUES
 (911001,9101,91101,'showroom','A showroom','stage-a-site1'),
 (911002,9101,91101,'factory','A factory','stage-a-site2'),
 (922001,9201,92201,'showroom','B showroom','stage-b-site1');
INSERT INTO c10_demo.stock_locations(id,tenant_id,business_id,site_id,code)
VALUES
 (9110001,9101,91101,911001,'MAIN'),
 (9110002,9101,91101,911002,'MAIN'),
 (9220001,9201,92201,922001,'MAIN');

INSERT INTO c10_demo.tenant_members(tenant_id,user_id,role,active)
SELECT x.tenant_id,p.auth_uid,'tenant_owner',true
FROM (VALUES('tenantOwnerA',9101::bigint),('tenantOwnerB',9201::bigint)) x(role_name,tenant_id)
JOIN c10_stage_fixture_principals_v1 p USING(role_name);
INSERT INTO c10_demo.site_grants(tenant_id,business_id,site_id,user_id,actions,active)
SELECT 9101,91101,911001,p.auth_uid,ARRAY['stock.read']::text[],true
FROM c10_stage_fixture_principals_v1 p WHERE p.role_name='siteStaffA';
INSERT INTO c10_demo.business_members(tenant_id,business_id,user_id,role,active)
SELECT 9101,91101,p.auth_uid,x.business_role,x.is_active
FROM (VALUES('investorA','investor',true),('revokedA','manager',false))
 x(role_name,business_role,is_active)
 JOIN c10_stage_fixture_principals_v1 p USING(role_name);
-- platformOperator has a GoTrue login but intentionally NO tenant/business/site grants.

DO $verify$
BEGIN
 IF (SELECT count(*) FROM c10_demo.tenants)<>2
  OR (SELECT count(*) FROM c10_demo.businesses)<>2
  OR (SELECT count(*) FROM c10_demo.sites)<>3
  OR (SELECT count(*) FROM c10_demo.site_grants)<>1
  OR (SELECT count(*) FROM c10_demo.tenant_members)<>2
  OR (SELECT count(*) FROM c10_demo.business_members)<>2
  OR EXISTS(SELECT 1 FROM c10_demo.businesses WHERE status<>'draft')
  OR EXISTS(SELECT 1 FROM c10_demo.templates WHERE enterprise_certified) THEN
  RAISE EXCEPTION 'C10_STAGE_SEED_POSTCONDITION_FAILED';
 END IF;
END $verify$;
COMMIT;
-- NO Auth credentials output. On validated stage, bind the 6 real user emails
-- and passwords to protected Actions environment only and set expected scopes:
-- tenantOwnerA businessIds:[91101], siteIds:[911001,911002]
-- tenantOwnerB businessIds:[92201], siteIds:[922001]
-- siteStaffA businessIds:[91101], siteIds:[911001]
-- investorA/revokedA/platformOperator businessIds:[], siteIds:[]
-- This data setup is a PRECONDITION only. It does not certify signed GoTrue RLS.
