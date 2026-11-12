\set ON_ERROR_STOP on
\echo C10-A019 | Isolated stage-fixture PostgreSQL RLS tests: NOT GoTrue
-- Values are synthetic UUIDs passed via psql -v, not live Auth credentials.
DO $data$
BEGIN
 IF (SELECT count(*) FROM c10_demo.tenants)<>2
   OR (SELECT count(*) FROM c10_demo.businesses)<>2
   OR (SELECT count(*) FROM c10_demo.sites)<>3
   OR (SELECT count(*) FROM c10_demo.stock_locations)<>3
   OR (SELECT count(*) FROM c10_demo.business_members WHERE role='investor' AND active)<>1
   OR (SELECT count(*) FROM c10_demo.business_members WHERE role='manager' AND NOT active)<>1
   OR (SELECT count(*) FROM c10_demo.business_members)<>2 THEN
  RAISE EXCEPTION 'C10_STAGE_STRUCTURAL_FIXTURE_INVALID';
 END IF;
 IF has_schema_privilege('anon','c10_demo','USAGE') OR
    has_table_privilege('anon','c10_demo.businesses','SELECT') THEN
  RAISE EXCEPTION 'C10_STAGE_ANON_READ_GRANT_LEAK';
 END IF;
END $data$;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',:'tenantOwnerA',true);
DO $a$
BEGIN
 IF (SELECT count(*) FROM c10_demo.businesses)<>1 OR
    (SELECT count(*) FROM c10_demo.sites)<>2 OR
    (SELECT count(*) FROM c10_demo.stock_locations)<>2 OR
    (SELECT count(*) FROM c10_demo.tenants)<>1 OR
    (SELECT count(*) FROM c10_demo.businesses WHERE id=92201)<>0 THEN
  RAISE EXCEPTION 'C10_STAGE_OWNER_A_SCOPE_VIOLATION';
 END IF;
END $a$;
ROLLBACK;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',:'tenantOwnerB',true);
DO $b$
BEGIN
 IF (SELECT count(*) FROM c10_demo.businesses)<>1 OR
    (SELECT count(*) FROM c10_demo.sites)<>1 OR
    (SELECT count(*) FROM c10_demo.stock_locations)<>1 OR
    (SELECT count(*) FROM c10_demo.tenants)<>1 OR
    (SELECT count(*) FROM c10_demo.businesses WHERE id=91101)<>0 THEN
  RAISE EXCEPTION 'C10_STAGE_OWNER_B_SCOPE_VIOLATION';
 END IF;
END $b$;
ROLLBACK;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',:'siteStaffA',true);
DO $staff$
BEGIN
 IF (SELECT count(*) FROM c10_demo.businesses)<>1 OR
    (SELECT count(*) FROM c10_demo.sites)<>1 OR
    (SELECT count(*) FROM c10_demo.stock_locations)<>1 OR
    (SELECT count(*) FROM c10_demo.tenants)<>0 OR
    (SELECT count(*) FROM c10_demo.businesses WHERE id=92201)<>0 OR
    (SELECT count(*) FROM c10_demo.sites WHERE id=911002)<>0 THEN
   RAISE EXCEPTION 'C10_STAGE_STAFF_OVERGRANT_OR_MISSING_ACCESS';
 END IF;
END $staff$;
ROLLBACK;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',:'investorA',true);
DO $inv$
BEGIN
 IF (SELECT count(*) FROM c10_demo.businesses)<>0 OR
    (SELECT count(*) FROM c10_demo.sites)<>0 OR
    (SELECT count(*) FROM c10_demo.stock_locations)<>0 THEN
  RAISE EXCEPTION 'C10_STAGE_INVESTOR_OPERATIONAL_DATA_EXPOSED';
 END IF;
END $inv$;
ROLLBACK;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',:'revokedA',true);
DO $rev$
BEGIN
 IF (SELECT count(*) FROM c10_demo.businesses)<>0 OR
    (SELECT count(*) FROM c10_demo.sites)<>0 OR
    (SELECT count(*) FROM c10_demo.stock_locations)<>0 THEN
  RAISE EXCEPTION 'C10_STAGE_REVOKED_MEMBER_OPERATIONAL_DATA_EXPOSED';
 END IF;
END $rev$;
ROLLBACK;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',:'platformOperator',true);
DO $op$
BEGIN
 IF (SELECT count(*) FROM c10_demo.businesses)<>0 OR
    (SELECT count(*) FROM c10_demo.sites)<>0 OR
    (SELECT count(*) FROM c10_demo.stock_locations)<>0 THEN
  RAISE EXCEPTION 'C10_STAGE_OPERATOR_OPERATIONAL_DATA_EXPOSED';
 END IF;
END $op$;
ROLLBACK;

\echo PASS C10-A019 synthetic six-identity stage structural + role-isolation contract. NO real GoTrue signed token test.
