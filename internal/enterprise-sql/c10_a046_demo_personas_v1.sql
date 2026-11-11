-- C10-A046: additional temporary identities; DISPOSABLE PG17 ONLY, not GoTrue.
-- Requires A018 demo backend + tests/c10_a018_demo_seed.sql.
\set ON_ERROR_STOP on
\if :{?c10_demo_ack}
\else
\echo C10_A046_DISPOSABLE_ACK_REQUIRED
\quit 3
\endif
BEGIN;
SELECT set_config('c10.demo_fixture_ack', :'c10_demo_ack', true);
DO $gate$
BEGIN
 IF current_database() !~ '^core10_a046_(ci|local)(_|$)'
    OR current_setting('c10.demo_fixture_ack',true)<>'I_CONFIRM_DISPOSABLE_A046'
    OR to_regclass('auth.users') IS NOT NULL
    OR to_regclass('c10_demo.tenants') IS NULL
 THEN RAISE EXCEPTION 'C10_A046_DISPOSABLE_DATABASE_ONLY'; END IF;
 IF (SELECT count(*) FROM c10_demo.tenants)<>2 OR
    (SELECT count(*) FROM c10_demo.businesses)<>3 OR
    (SELECT count(*) FROM c10_demo.sites)<>4 OR
    (SELECT count(*) FROM c10_demo.stock_movements)<>0 OR
    EXISTS(SELECT 1 FROM c10_demo.tenants WHERE
      (id=1 AND slug<>'demo-owned-portfolio') OR
      (id=2 AND slug<>'demo-independent-customer') OR id NOT IN(1,2)) OR
    EXISTS(SELECT 1 FROM c10_demo.businesses WHERE
      (id=101 AND slug<>'demo-sweets') OR
      (id=102 AND slug<>'demo-second-business') OR
      (id=201 AND slug<>'customer-business') OR id NOT IN(101,102,201))
 THEN RAISE EXCEPTION 'C10_A046_BASELINE_NOT_DISPOSABLE'; END IF;
END $gate$;
INSERT INTO c10_demo.business_members(tenant_id,business_id,user_id,role,active)
VALUES
(1,102,'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','business_owner',true),
(1,102,'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','manager',true)
ON CONFLICT DO NOTHING;
INSERT INTO c10_demo.site_grants(tenant_id,business_id,site_id,user_id,actions,active)
VALUES
(1,101,1002,'cccccccc-cccc-4ccc-8ccc-cccccccccccc',ARRAY['stock.read']::text[],true),
(1,102,1003,'dddddddd-dddd-4ddd-8ddd-dddddddddddd',ARRAY['stock.read']::text[],true)
ON CONFLICT DO NOTHING;
DO $verify$
BEGIN
 IF (SELECT count(*) FROM c10_demo.business_members)<>6 OR
    (SELECT count(*) FROM c10_demo.site_grants)<>4 OR
    NOT EXISTS(SELECT 1 FROM c10_demo.business_members WHERE
      user_id='66666666-6666-4666-8666-666666666666' AND active=false) OR
    EXISTS(SELECT 1 FROM c10_demo.business_members WHERE
      user_id IN('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
                 '99999999-9999-4999-8999-999999999999')) OR
    EXISTS(SELECT 1 FROM c10_demo.businesses WHERE status<>'draft')
 THEN RAISE EXCEPTION 'C10_A046_POSTCONDITION_FAILED'; END IF;
END $verify$;
COMMIT;
