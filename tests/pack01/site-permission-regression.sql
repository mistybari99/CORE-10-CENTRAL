\set ON_ERROR_STOP on
\echo PACK-01 canonical location to site grant reconciliation, disposable PostgreSQL only
DO $prereq$ BEGIN
 IF to_regprocedure('c10_demo.build01_set_access_v1(bigint,uuid,text,text,bigint,text[],text[],timestamptz,text,bigint)') IS NULL
 OR to_regprocedure('c10_demo.can_approval_action_v1(bigint,bigint,text)') IS NULL
 OR to_regprocedure('c10_demo.inventory_action_authorized_v1(bigint,bigint,bigint,text)') IS NULL
 THEN RAISE EXCEPTION 'PACK01_DEPENDENCY_REQUIRED'; END IF;
END $prereq$;

-- Baseline: original A048 operations remain possible for signed fixture owner.
-- Create an unposted draft, then deny this site before confirmation.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
DO $baseline$ DECLARE receipt jsonb;
BEGIN
 IF NOT c10_demo.inventory_action_authorized_v1(1,101,5001,'stock.post')
 THEN RAISE EXCEPTION 'PACK01_OWNER_BASELINE_DENIED'; END IF;
 receipt:=c10_demo.create_inventory_command_v1(101,'receive',NULL,5001,8001,1,'pack01-owner-draft');
 PERFORM set_config('pack01.command',receipt->>'command_id',true);
 IF receipt->>'status'<>'draft' THEN RAISE EXCEPTION 'PACK01_DRAFT_MISSING'; END IF;
END $baseline$;
RESET ROLE;
INSERT INTO c10_demo.site_grants(tenant_id,business_id,site_id,user_id,actions,active,denied_actions)
VALUES(1,101,1001,'11111111-1111-4111-8111-111111111111','{}'::text[],true,ARRAY['stock.read'])
ON CONFLICT(site_id,user_id) DO UPDATE
 SET active=true,actions='{}'::text[],denied_actions=EXCLUDED.denied_actions,valid_until=NULL;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
DO $deny$ BEGIN
 IF c10_demo.can_site(1,101,1001,'stock.post') OR
    c10_demo.inventory_action_authorized_v1(1,101,5001,'stock.post') OR
    c10_demo.inventory_action_authorized_v1(1,101,5001,'stock.read')
 THEN RAISE EXCEPTION 'PACK01_OWNER_DENY_BYPASSED'; END IF;
 BEGIN
  PERFORM c10_demo.create_inventory_command_v1(101,'receive',NULL,5001,8001,1,'pack01-owner-denied');
  RAISE EXCEPTION 'PACK01_DENIED_OWNER_CREATED_COMMAND';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'A048_PERMISSION_DENIED' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM c10_demo.advance_inventory_command_v1(current_setting('pack01.command')::bigint,'confirm',1,'pack01-denied-confirm');
  RAISE EXCEPTION 'PACK01_DENIED_OWNER_ADVANCED';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'A048_PERMISSION_DENIED' THEN RAISE; END IF;
 END;
 IF jsonb_array_length(c10_demo.read_inventory_commands_v1(101)->'items')<>0
 THEN RAISE EXCEPTION 'PACK01_OWNER_READ_DENY_LEAK'; END IF;
END $deny$;
RESET ROLE;
DO $immutable$ BEGIN
 IF EXISTS(SELECT 1 FROM c10_demo.inventory_commands_v1 WHERE business_id=101 AND request_key='pack01-owner-denied')
 OR EXISTS(SELECT 1 FROM c10_demo.inventory_commands_v1
           WHERE id=current_setting('pack01.command')::bigint AND status<>'draft')
 OR EXISTS(SELECT 1 FROM c10_demo.stock_movements WHERE location_id=5001)
 THEN RAISE EXCEPTION 'PACK01_DENIED_ACTION_CHANGED_STOCK_OR_COMMAND'; END IF;
END $immutable$;
ROLLBACK;

-- Manager inherited business access cannot override an active explicit site DENY.
BEGIN;
INSERT INTO c10_demo.site_grants(tenant_id,business_id,site_id,user_id,actions,active,denied_actions)
VALUES(1,101,1001,'33333333-3333-4333-8333-333333333333','{}'::text[],true,ARRAY['stock.post'])
ON CONFLICT(site_id,user_id) DO UPDATE SET active=true,denied_actions=EXCLUDED.denied_actions;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',true);
DO $manager$ BEGIN
 IF NOT c10_demo.can_business(1,101) OR c10_demo.inventory_action_authorized_v1(1,101,5001,'stock.post')
 THEN RAISE EXCEPTION 'PACK01_MANAGER_DENY_NOT_EFFECTIVE'; END IF;
 BEGIN
  PERFORM c10_demo.create_inventory_command_v1(101,'receive',NULL,5001,8001,1,'pack01-manager-deny');
  RAISE EXCEPTION 'PACK01_MANAGER_CREATED_AFTER_DENY';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'A048_PERMISSION_DENIED' THEN RAISE; END IF;
 END;
END $manager$;
ROLLBACK;

-- Expired grants and revoked memberships are checked at command time, not once at login.
BEGIN;
UPDATE c10_demo.site_grants SET valid_until=statement_timestamp()-interval '1 second'
 WHERE site_id=1001 AND user_id='44444444-4444-4444-8444-444444444444';
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',true);
DO $expired$ BEGIN
 IF c10_demo.inventory_action_authorized_v1(1,101,5001,'stock.post')
 THEN RAISE EXCEPTION 'PACK01_EXPIRED_SITE_GRANT_ALLOWED'; END IF;
 BEGIN
  PERFORM c10_demo.create_inventory_command_v1(101,'receive',NULL,5001,8001,1,'pack01-expired-staff');
  RAISE EXCEPTION 'PACK01_STAFF_CREATED_AFTER_EXPIRY';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'A048_PERMISSION_DENIED' THEN RAISE; END IF;
 END;
END $expired$;
ROLLBACK;

BEGIN;
UPDATE c10_demo.business_members SET active=false
 WHERE business_id=101 AND user_id='22222222-2222-4222-8222-222222222222';
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',true);
DO $revoked$ BEGIN
 IF c10_demo.can_manage(1,101) OR c10_demo.inventory_action_authorized_v1(1,101,5001,'stock.post')
 THEN RAISE EXCEPTION 'PACK01_REVOKED_OWNER_ALLOWED'; END IF;
 BEGIN
  PERFORM c10_demo.create_inventory_command_v1(101,'receive',NULL,5001,8001,1,'pack01-revoked-owner');
  RAISE EXCEPTION 'PACK01_REVOKED_OWNER_CREATED';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'A048_PERMISSION_DENIED' THEN RAISE; END IF;
 END;
END $revoked$;
ROLLBACK;

-- Membership expiry must also stop Build02A approval role baseline.
BEGIN;
UPDATE c10_demo.business_members SET valid_until=statement_timestamp()-interval '1 second'
 WHERE business_id=101 AND user_id='33333333-3333-4333-8333-333333333333';
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',true);
DO $approval$ BEGIN
 IF c10_demo.can_approval_action_v1(1,101,'approval.submit') OR c10_demo.can_site(1,101,1001,'stock.post')
 THEN RAISE EXCEPTION 'PACK01_EXPIRED_MEMBER_RETAINED_PERMISSION'; END IF;
END $approval$;
ROLLBACK;

-- Independent tenant and mismatched source location must stay inaccessible.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','77777777-7777-4777-8777-777777777777',true);
DO $tenant$ BEGIN
 IF c10_demo.inventory_action_authorized_v1(1,101,5001,'stock.post')
 OR c10_demo.inventory_action_authorized_v1(2,201,5001,'stock.read')
 OR c10_demo.inventory_action_authorized_v1(1,101,5001,'approval.decide')
 THEN RAISE EXCEPTION 'PACK01_CROSS_TENANT_OR_ACTION_LEAK'; END IF;
 BEGIN
  PERFORM c10_demo.create_inventory_command_v1(101,'receive',NULL,5001,8001,1,'pack01-foreign-tenant');
  RAISE EXCEPTION 'PACK01_FOREIGN_TENANT_CREATED';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'A048_PERMISSION_DENIED' THEN RAISE; END IF;
 END;
END $tenant$;
ROLLBACK;

\echo PASS PACK-01 scoped integration: owner+manager DENY, read isolation, post-after-deny, expired/revoked, approvals, foreign-tenant; synthetic claims not hosted GoTrue
