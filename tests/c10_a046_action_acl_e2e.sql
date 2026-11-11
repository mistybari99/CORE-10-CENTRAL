\set ON_ERROR_STOP on
\echo A046 action ACL compatibility checks — synthetic PostgreSQL only
DO $acl$
BEGIN
 IF has_table_privilege('authenticated','c10_demo.stock_movements','INSERT') THEN
  RAISE EXCEPTION 'A046_UNEXPECTED_DIRECT_STOCK_WRITE_PRIVILEGE';
 END IF;
END $acl$;
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','cccccccc-cccc-4ccc-8ccc-cccccccccccc',true);
DO $acl$
BEGIN
 IF NOT c10_demo.can_site(1,101,1002,'stock.read') OR
    c10_demo.can_site(1,101,1002,'stock.post') OR
    c10_demo.can_site(1,101,1001,'stock.read') OR
    c10_demo.can_site(1,102,1003,'stock.read') THEN
  RAISE EXCEPTION 'A046_FACTORY_STAFF_ACTION_SCOPE_FAIL';
 END IF;
END $acl$;
ROLLBACK;
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','66666666-6666-4666-8666-666666666666',true);
DO $acl$
BEGIN
 IF c10_demo.can_manage(1,101) OR c10_demo.can_site(1,101,1001,'stock.read') OR
    c10_demo.can_site(1,101,1001,'stock.post') THEN
  RAISE EXCEPTION 'A046_REVOKED_STOCK_SCOPE_LEAK';
 END IF;
END $acl$;
ROLLBACK;
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',true);
DO $acl$
BEGIN
 IF NOT c10_demo.can_site(1,101,1002,'stock.post') THEN
  RAISE EXCEPTION 'A046_LEGACY_MANAGER_BROAD_ACTION_REGRESSION';
 END IF;
END $acl$;
ROLLBACK;
\echo A046 PASS: sensitive direct INSERT denied, staff read-only enforced, revoked blocked.
\echo Known legacy A018 gap: manager membership inherits stock.post, but direct table INSERT privilege denied.
\echo NOT CERTIFIED: operational post_stock_event execution or real GoTrue Auth.
