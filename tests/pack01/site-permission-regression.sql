\set ON_ERROR_STOP on
\echo PACK-01 canonical location to site grant reconciliation, disposable PostgreSQL only
DO $prereq$ BEGIN
 IF to_regprocedure('c10_demo.build01_set_access_v1(bigint,uuid,text,text,bigint,text[],text[],timestamptz,text,bigint)') IS NULL
 OR to_regprocedure('c10_demo.can_approval_action_v1(bigint,bigint,text)') IS NULL
 OR to_regprocedure('c10_demo.create_operation_order_v1(bigint,bigint,bigint,text,numeric,numeric,text,text)') IS NULL
 OR to_regprocedure('c10_demo.inventory_action_authorized_v1(bigint,bigint,bigint,text)') IS NULL
 THEN RAISE EXCEPTION 'PACK01_DEPENDENCY_REQUIRED'; END IF;
 IF has_function_privilege('authenticated',
  'c10_demo.inventory_action_authorized_v1(bigint,bigint,bigint,text)','EXECUTE')
 THEN RAISE EXCEPTION 'PACK01_INTERNAL_HELPER_PUBLICLY_EXECUTABLE'; END IF;
END $prereq$;

-- Baseline: original A048 operations remain possible for signed fixture owner.
-- Create an unposted draft, then deny this site before confirmation.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
DO $baseline$ DECLARE receipt jsonb;
BEGIN
 IF NOT c10_demo.can_site(1,101,1001,'stock.post')
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
    c10_demo.can_site(1,101,1001,'stock.post') OR
    c10_demo.can_site(1,101,1001,'stock.read')
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
 IF NOT c10_demo.can_business(1,101) OR c10_demo.can_site(1,101,1001,'stock.post')
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
 IF c10_demo.can_site(1,101,1001,'stock.post')
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
 IF c10_demo.can_manage(1,101) OR c10_demo.can_site(1,101,1001,'stock.post')
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
 IF c10_demo.can_site(1,101,1001,'stock.post')
 OR c10_demo.can_site(2,201,1001,'stock.read')
 OR c10_demo.can_site(1,101,1001,'approval.decide')
 THEN RAISE EXCEPTION 'PACK01_CROSS_TENANT_OR_ACTION_LEAK'; END IF;
 BEGIN
  PERFORM c10_demo.create_inventory_command_v1(101,'receive',NULL,5001,8001,1,'pack01-foreign-tenant');
  RAISE EXCEPTION 'PACK01_FOREIGN_TENANT_CREATED';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'A048_PERMISSION_DENIED' THEN RAISE; END IF;
 END;
END $tenant$;
ROLLBACK;


-- PACK-01 continuation: A049 operation orders must obey the SAME A048/Build01
-- site guard at draft, confirm and stock-post. All fixtures are rolled back.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
DO $a049_baseline$
DECLARE o jsonb; id1 bigint; id2 bigint;
BEGIN
 o:=c10_demo.create_operation_order_v1(101,5001,8001,'purchase_receive',7,15,'pack01-draft','pack01-a049-draft');
 id1:=(o->>'order_id')::bigint;
 o:=c10_demo.create_operation_order_v1(101,5001,8001,'purchase_receive',8,15,'pack01-confirmed','pack01-a049-confirmed');
 id2:=(o->>'order_id')::bigint;
 IF id1 IS NULL OR id2 IS NULL OR id1=id2 THEN RAISE EXCEPTION 'PACK01_A049_SETUP_INVALID'; END IF;
 -- Save only returned IDs as transaction-local test values, never expose the
 -- private operation_orders table to the authenticated role.
 PERFORM set_config('pack01.a049_draft_id',id1::text,true);
 PERFORM set_config('pack01.a049_confirmed_id',id2::text,true);
 PERFORM c10_demo.advance_operation_order_v1(id2,'confirm',1,'pack01-a049-confirm-before-deny');
END $a049_baseline$;
RESET ROLE;
INSERT INTO c10_demo.site_grants(tenant_id,business_id,site_id,user_id,actions,active,denied_actions)
VALUES(1,101,1001,'11111111-1111-4111-8111-111111111111','{}'::text[],true,ARRAY['stock.read','stock.post'])
ON CONFLICT(site_id,user_id) DO UPDATE SET active=true,denied_actions=EXCLUDED.denied_actions,valid_until=NULL;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
DO $a049_deny$
DECLARE draft_id bigint; confirmed_id bigint;
BEGIN
 draft_id:=current_setting('pack01.a049_draft_id')::bigint;
 confirmed_id:=current_setting('pack01.a049_confirmed_id')::bigint;
 IF c10_demo.can_site(1,101,1001,'stock.read') OR c10_demo.can_site(1,101,1001,'stock.post')
 THEN RAISE EXCEPTION 'PACK01_A049_OWNER_DENY_NOT_EFFECTIVE'; END IF;
 BEGIN
   PERFORM c10_demo.create_operation_order_v1(101,5001,8001,'purchase_receive',1,5,'blocked','pack01-a049-denied-create');
   RAISE EXCEPTION 'PACK01_A049_DENIED_ORDER_CREATED';
 EXCEPTION WHEN raise_exception THEN
   IF SQLERRM<>'A049_ORDER_DENIED' THEN RAISE; END IF;
 END;
 BEGIN
   PERFORM c10_demo.advance_operation_order_v1(draft_id,'confirm',1,'pack01-a049-denied-confirm');
   RAISE EXCEPTION 'PACK01_A049_DENIED_ORDER_CONFIRMED';
 EXCEPTION WHEN raise_exception THEN
   IF SQLERRM<>'A049_ACTION_DENIED' THEN RAISE; END IF;
 END;
 BEGIN
   PERFORM c10_demo.advance_operation_order_v1(confirmed_id,'post',2,'pack01-a049-denied-post');
   RAISE EXCEPTION 'PACK01_A049_DENIED_ORDER_POSTED';
 EXCEPTION WHEN raise_exception THEN
   IF SQLERRM<>'A049_ACTION_DENIED' THEN RAISE; END IF;
 END;
 IF jsonb_array_length(c10_demo.read_operation_overview_v1(101)->'items')<>0
 THEN RAISE EXCEPTION 'PACK01_A049_DENIED_ORDER_READ_LEAK'; END IF;
END $a049_deny$;
RESET ROLE;
DO $a049_no_write$ BEGIN
 IF EXISTS(SELECT 1 FROM c10_demo.operation_orders_v1 WHERE request_key='pack01-a049-denied-create')
 OR EXISTS(SELECT 1 FROM c10_demo.operation_orders_v1 WHERE request_key='pack01-a049-draft' AND status<>'draft')
 OR EXISTS(SELECT 1 FROM c10_demo.operation_orders_v1 WHERE request_key='pack01-a049-confirmed' AND status<>'confirmed')
 OR EXISTS(SELECT 1 FROM c10_demo.stock_movements WHERE location_id=5001)
 THEN RAISE EXCEPTION 'PACK01_A049_DENIAL_CHANGED_ORDER_OR_STOCK'; END IF;
END $a049_no_write$;
ROLLBACK;

-- Manager inherited business access, expired site grant and revoked owner
-- cannot create A049 orders, regardless of the staff operation policy.
BEGIN;
INSERT INTO c10_demo.site_grants(tenant_id,business_id,site_id,user_id,actions,active,denied_actions)
VALUES(1,101,1001,'33333333-3333-4333-8333-333333333333','{}'::text[],true,ARRAY['stock.post'])
ON CONFLICT(site_id,user_id) DO UPDATE SET active=true,denied_actions=EXCLUDED.denied_actions;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',true);
DO $a049_manager$ BEGIN
 BEGIN
  PERFORM c10_demo.create_operation_order_v1(101,5001,8001,'purchase_receive',1,5,'manager-denied','pack01-a049-manager-deny');
  RAISE EXCEPTION 'PACK01_A049_MANAGER_DENY_BYPASSED';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'A049_ORDER_DENIED' THEN RAISE; END IF;
 END;
END $a049_manager$;
ROLLBACK;

BEGIN;
UPDATE c10_demo.site_grants SET valid_until=statement_timestamp()-interval '1 second'
 WHERE site_id=1001 AND user_id='44444444-4444-4444-8444-444444444444';
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',true);
DO $a049_expiry$ BEGIN
 BEGIN
  PERFORM c10_demo.create_operation_order_v1(101,5001,8001,'purchase_receive',1,5,'expired','pack01-a049-site-expired');
  RAISE EXCEPTION 'PACK01_A049_EXPIRED_SITE_GRANT_BYPASSED';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'A049_ORDER_DENIED' THEN RAISE; END IF;
 END;
END $a049_expiry$;
ROLLBACK;

BEGIN;
UPDATE c10_demo.business_members SET active=false
 WHERE business_id=101 AND user_id='22222222-2222-4222-8222-222222222222';
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',true);
DO $a049_revoked$ BEGIN
 BEGIN
  PERFORM c10_demo.create_operation_order_v1(101,5001,8001,'purchase_receive',1,5,'revoked','pack01-a049-member-revoked');
  RAISE EXCEPTION 'PACK01_A049_REVOKED_BUSINESS_OWNER_BYPASSED';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'A049_ORDER_DENIED' THEN RAISE; END IF;
 END;
END $a049_revoked$;
ROLLBACK;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','77777777-7777-4777-8777-777777777777',true);
DO $a049_cross_tenant$ BEGIN
 BEGIN
  PERFORM c10_demo.create_operation_order_v1(101,5001,8001,'purchase_receive',1,5,'foreign','pack01-a049-cross-tenant');
  RAISE EXCEPTION 'PACK01_A049_FOREIGN_TENANT_BYPASSED';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'A049_ORDER_DENIED' THEN RAISE; END IF;
 END;
END $a049_cross_tenant$;
ROLLBACK;


-- PACK-01 Workforce effective roles. These are disposable synthetic identities.
-- No role/permission is widened; individual employee link stays independent.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',true);
DO $wf_manager_ok$ BEGIN
 IF c10_demo.wf_read_overview_v1(101)->>'level'<>'manager' THEN RAISE EXCEPTION 'PACK01_WF_MANAGER_BASELINE'; END IF;
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(c10_demo.wf_my_businesses_v1()->'items') b WHERE b->>'id'='101')
 THEN RAISE EXCEPTION 'PACK01_WF_MANAGER_DISCOVERY_BASELINE'; END IF;
END $wf_manager_ok$;
RESET ROLE;
UPDATE c10_demo.business_members SET valid_until=statement_timestamp()-interval '1 second'
 WHERE business_id=101 AND user_id='33333333-3333-4333-8333-333333333333';
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',true);
DO $wf_expired_mgr$ BEGIN
 BEGIN
  PERFORM c10_demo.wf_read_overview_v1(101); RAISE EXCEPTION 'PACK01_WF_EXPIRED_MANAGER_ALLOWED';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'wf_denied' THEN RAISE; END IF; END;
 BEGIN
  PERFORM c10_demo.wf_list_employees_v1(101,NULL,NULL,NULL,10,0); RAISE EXCEPTION 'PACK01_WF_EXPIRED_MANAGER_DIRECTORY';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'wf_denied' THEN RAISE; END IF; END;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(c10_demo.wf_my_businesses_v1()->'items') b WHERE b->>'id'='101')
 THEN RAISE EXCEPTION 'PACK01_WF_EXPIRED_MANAGER_DISCOVERY'; END IF;
END $wf_expired_mgr$;
ROLLBACK;

BEGIN;
UPDATE c10_demo.business_members SET valid_until=statement_timestamp()-interval '1 second'
 WHERE business_id=101 AND user_id='22222222-2222-4222-8222-222222222222';
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',true);
DO $wf_expired_bo$ BEGIN
 BEGIN
  PERFORM c10_demo.wf_read_overview_v1(101); RAISE EXCEPTION 'PACK01_WF_EXPIRED_OWNER_ALLOWED';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'wf_denied' THEN RAISE; END IF; END;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(c10_demo.wf_my_businesses_v1()->'items') b WHERE b->>'id'='101')
 THEN RAISE EXCEPTION 'PACK01_WF_EXPIRED_OWNER_DISCOVERY'; END IF;
END $wf_expired_bo$;
ROLLBACK;

BEGIN;
UPDATE c10_demo.site_grants SET active=false WHERE site_id=1001 AND user_id='44444444-4444-4444-8444-444444444444';
INSERT INTO c10_demo.wf_employees(tenant_id,business_id,employee_no,full_name,user_id,joined_on,status,contract_type,created_by)
VALUES(1,101,'P01-EMP-01','Synthetic Test Worker','44444444-4444-4444-8444-444444444444',
'2026-01-01','active','permanent','11111111-1111-4111-8111-111111111111');
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',true);
DO $wf_link$ BEGIN
 IF c10_demo.wf_read_overview_v1(101)->>'level'<>'employee'
 OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(c10_demo.wf_my_businesses_v1()->'items') b WHERE b->>'id'='101')
 THEN RAISE EXCEPTION 'PACK01_WF_INDEPENDENT_EMPLOYEE_DENIED'; END IF;
END $wf_link$;
RESET ROLE;
UPDATE c10_demo.tenants SET active=false WHERE id=1;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',true);
DO $wf_inactive$ BEGIN
 BEGIN
  PERFORM c10_demo.wf_read_overview_v1(101); RAISE EXCEPTION 'PACK01_WF_INACTIVE_TENANT_READ';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'wf_denied' THEN RAISE; END IF; END;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(c10_demo.wf_my_businesses_v1()->'items') b WHERE b->>'id'='101')
 THEN RAISE EXCEPTION 'PACK01_WF_INACTIVE_TENANT_DISCOVERY'; END IF;
END $wf_inactive$;
ROLLBACK;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','77777777-7777-4777-8777-777777777777',true);
DO $wf_foreign$ BEGIN
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(c10_demo.wf_my_businesses_v1()->'items') b WHERE b->>'id'='101')
 THEN RAISE EXCEPTION 'PACK01_WF_FOREIGN_DISCOVERY'; END IF;
 BEGIN
  PERFORM c10_demo.wf_read_overview_v1(101); RAISE EXCEPTION 'PACK01_WF_FOREIGN_READ';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'wf_denied' THEN RAISE; END IF; END;
END $wf_foreign$;
ROLLBACK;


-- PACK-01 A054 effective delegate authorization: real RPC grant/read checks
-- plus a privileged WHITE-BOX internal helper negative; no extra helper GRANT.
-- All delegation/membership changes roll back on disposable PostgreSQL.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
DO $a054_owner_grant$
DECLARE res jsonb;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(c10_demo.a054_eligible_delegates_v1(101)->'items') x
    WHERE x->>'uid'='33333333-3333-4333-8333-333333333333')
 THEN RAISE EXCEPTION 'PACK01_A054_ACTIVE_MANAGER_NOT_ELIGIBLE'; END IF;
 res:=c10_demo.a054_grant_delegation_v1(
    101,'pack01-a054-hr-001','33333333-3333-4333-8333-333333333333',
    'hr','allow',NULL,NULL,NULL,NULL,'temporary synthetic HR delegation');
 IF res->>'status'<>'granted' THEN RAISE EXCEPTION 'PACK01_A054_GRANT_BASELINE_FAILED'; END IF;
END $a054_owner_grant$;
SELECT set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',true);
DO $a054_manager_authorized$ BEGIN
 IF NOT c10_demo.a054_my_access_v1(101)->'delegated_roles' ? 'hr'
 THEN RAISE EXCEPTION 'PACK01_A054_VALID_DELEGATION_NOT_VISIBLE'; END IF;
END $a054_manager_authorized$;
RESET ROLE;
UPDATE c10_demo.business_members SET valid_until=statement_timestamp()-interval '1 second'
 WHERE business_id=101 AND user_id='33333333-3333-4333-8333-333333333333';
SELECT set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',true);
DO $a054_internal_after_expiry$ BEGIN
 IF c10_demo.a054i_deleg(101,'hr',NULL,NULL,'any')<>'none'
 THEN RAISE EXCEPTION 'PACK01_A054_EXPIRED_MEMBER_DELEGATION_STILL_EFFECTIVE'; END IF;
END $a054_internal_after_expiry$;
SET LOCAL ROLE authenticated;
DO $a054_manager_after_expiry$ BEGIN
 BEGIN
  PERFORM c10_demo.a054_my_access_v1(101);
  RAISE EXCEPTION 'PACK01_A054_EXPIRED_MANAGER_RPC_ALLOWED';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'wf_denied' THEN RAISE; END IF;
 END;
END $a054_manager_after_expiry$;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
DO $a054_owner_after_expiry$ BEGIN
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(c10_demo.a054_eligible_delegates_v1(101)->'items') x
    WHERE x->>'uid'='33333333-3333-4333-8333-333333333333')
 THEN RAISE EXCEPTION 'PACK01_A054_EXPIRED_MEMBER_STILL_ELIGIBLE'; END IF;
 BEGIN
  PERFORM c10_demo.a054_grant_delegation_v1(
    101,'pack01-a054-grant-denied','33333333-3333-4333-8333-333333333333',
    'payroll_reviewer','allow',NULL,NULL,NULL,NULL,'expired manager ineligible');
  RAISE EXCEPTION 'PACK01_A054_EXPIRED_MANAGER_REGRANTED';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'a054_delegate_not_eligible' THEN RAISE; END IF;
 END;
END $a054_owner_after_expiry$;
ROLLBACK;

-- Revoked manager still ineligible; active employee links are a distinct
-- authorization source and must not be implicitly revoked with a stock grant.
BEGIN;
UPDATE c10_demo.business_members SET active=false WHERE business_id=101
 AND user_id='33333333-3333-4333-8333-333333333333';
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
DO $a054_revoked_mgr$ BEGIN
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(c10_demo.a054_eligible_delegates_v1(101)->'items') x
    WHERE x->>'uid'='33333333-3333-4333-8333-333333333333')
 THEN RAISE EXCEPTION 'PACK01_A054_REVOKED_MANAGER_ELIGIBLE'; END IF;
END $a054_revoked_mgr$;
ROLLBACK;

-- Separate employee link (without business membership) retains intended
-- employee delegation eligibility; unrelated-tenant user stays invisible.
BEGIN;
INSERT INTO c10_demo.wf_employees(tenant_id,business_id,employee_no,full_name,user_id,joined_on,status,contract_type,created_by)
VALUES(1,101,'P01-A054-E01','Synthetic HR Link','44444444-4444-4444-8444-444444444444',
'2026-01-01','active','permanent','11111111-1111-4111-8111-111111111111');
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
DO $a054_linked_employee$
DECLARE res jsonb;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(c10_demo.a054_eligible_delegates_v1(101)->'items') x
    WHERE x->>'uid'='44444444-4444-4444-8444-444444444444' AND x->>'source'='employee')
 THEN RAISE EXCEPTION 'PACK01_A054_EMPLOYEE_ONLY_LINK_LOST'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(c10_demo.a054_eligible_delegates_v1(101)->'items') x
    WHERE x->>'uid'='77777777-7777-4777-8777-777777777777')
 THEN RAISE EXCEPTION 'PACK01_A054_FOREIGN_TENANT_ELIGIBLE'; END IF;
 res:=c10_demo.a054_grant_delegation_v1(101,'pack01-a054-e01',
  '44444444-4444-4444-8444-444444444444','hr','allow',
  NULL,NULL,NULL,NULL,'employee only synthetic delegation');
 IF res->>'status'<>'granted' THEN RAISE EXCEPTION 'PACK01_A054_EMPLOYEE_GRANT_FAILED'; END IF;
END $a054_linked_employee$;
SELECT set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',true);
DO $a054_employee_access$ BEGIN
 IF NOT c10_demo.a054_my_access_v1(101)->'delegated_roles' ? 'hr'
 THEN RAISE EXCEPTION 'PACK01_A054_VALID_EMPLOYEE_GRANT_NOT_EFFECTIVE'; END IF;
END $a054_employee_access$;
ROLLBACK;


-- PACK-01 A055: Asset root role membership expiry and inactive-tenant
-- containment, with all fixtures and changes rolled back in disposable PG.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',true);
DO $am_active_owner$ BEGIN
 IF c10_demo.am_whoami_v1(101)->>'level'<>'business_owner' THEN
  RAISE EXCEPTION 'PACK01_A055_OWNER_BASELINE_FAILED'; END IF;
END $am_active_owner$;
RESET ROLE;
UPDATE c10_demo.business_members SET valid_until=statement_timestamp()-interval '1 second'
 WHERE business_id=101 AND user_id='22222222-2222-4222-8222-222222222222';
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',true);
DO $am_expired_owner$ BEGIN
 BEGIN
  PERFORM c10_demo.am_whoami_v1(101);
  RAISE EXCEPTION 'PACK01_A055_EXPIRED_OWNER_VISIBLE';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'am_denied' THEN RAISE; END IF; END;
END $am_expired_owner$;
ROLLBACK;

-- Existing Asset-specific grant remains independent from stock/site rights.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',true);
DO $am_stock_only$ BEGIN
 BEGIN
  PERFORM c10_demo.am_whoami_v1(101);
  RAISE EXCEPTION 'PACK01_A055_STOCK_USER_MAINTENANCE_ESCALATION';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'am_denied' THEN RAISE; END IF; END;
END $am_stock_only$;
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','d3333333-3333-4333-8333-333333333333',true);
DO $am_asset_granted$ BEGIN
 IF c10_demo.am_whoami_v1(101)->>'level'<>'staff'
 THEN RAISE EXCEPTION 'PACK01_A055_ASSET_GRANT_NOT_PRESERVED'; END IF;
END $am_asset_granted$;
RESET ROLE;
UPDATE c10_demo.tenants SET active=false WHERE id=1;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','d3333333-3333-4333-8333-333333333333',true);
DO $am_tenant_inactive$ BEGIN
 BEGIN
  PERFORM c10_demo.am_whoami_v1(101);
  RAISE EXCEPTION 'PACK01_A055_INACTIVE_TENANT_ASSET_GRANT_LEAK';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'am_denied' THEN RAISE; END IF; END;
END $am_tenant_inactive$;
ROLLBACK;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','77777777-7777-4777-8777-777777777777',true);
DO $am_other_tenant$ BEGIN
 BEGIN
  PERFORM c10_demo.am_whoami_v1(101);
  RAISE EXCEPTION 'PACK01_A055_CROSS_TENANT_READ';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'am_denied' THEN RAISE; END IF; END;
END $am_other_tenant$;
ROLLBACK;

\echo PASS PACK-01 A048/A049/A051/A054/A055 negative effective permissions, synthetic PG17 only
