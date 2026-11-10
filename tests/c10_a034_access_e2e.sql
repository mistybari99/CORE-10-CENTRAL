\set ON_ERROR_STOP on
\echo C10-A034: real PG17 audited grant/revoke with database RLS
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
DO $$
DECLARE x bigint;y bigint; z bigint;
BEGIN
 x:=c10_demo.change_access_v1(
   101,'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
   'business_member.grant','manager',NULL,NULL,'grant-manager-new');
 IF x<>c10_demo.change_access_v1(
   101,'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
   'business_member.grant','manager',NULL,NULL,'grant-manager-new')
 THEN RAISE EXCEPTION 'manager grant retry was not idempotent'; END IF;
 IF (SELECT role FROM c10_demo.business_members
    WHERE business_id=101 AND user_id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')<>'manager' OR
    (SELECT count(*) FROM c10_demo.access_change_events_v1
    WHERE request_key='grant-manager-new')<>1 THEN
  RAISE EXCEPTION 'manager grant audit missing'; END IF;
 BEGIN
  PERFORM c10_demo.change_access_v1(101,'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
   'business_member.grant','investor',NULL,NULL,'grant-manager-new');
  RAISE EXCEPTION 'replay accepted role change';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'access_request_idempotency_conflict' THEN RAISE; END IF;
 END;
 -- Manager cannot be silently upgraded to business owner except by tenant owner.
 y:=c10_demo.change_access_v1(101,'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
  'business_member.grant','business_owner',NULL,NULL,'new-business-owner');
 IF y<1 THEN RAISE EXCEPTION 'tenant owner business-owner grant'; END IF;
 z:=c10_demo.change_access_v1(101,'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  'business_member.grant','investor',NULL,NULL,'grant-investor');
 IF z<1 THEN RAISE EXCEPTION 'investor grant'; END IF;
 BEGIN
  PERFORM c10_demo.change_access_v1(101,'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
   'site_grant.grant',NULL,1001,ARRAY['stock.post'],'investor-site');
  RAISE EXCEPTION 'investor received stock rights';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'investor_cannot_receive_stock_grant' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM c10_demo.change_access_v1(101,'ffffffff-ffff-4fff-8fff-ffffffffffff',
   'site_grant.grant',NULL,2001,ARRAY['stock.read'],'cross-tenant-site');
  RAISE EXCEPTION 'foreign tenant site assigned';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'site_business_scope_mismatch' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM c10_demo.change_access_v1(101,'ffffffff-ffff-4fff-8fff-ffffffffffff',
   'site_grant.grant',NULL,1001,ARRAY['stock.read','stock.read'],'duplicate-action');
  RAISE EXCEPTION 'duplicate stock grant action accepted';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'invalid_site_actions' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM c10_demo.change_access_v1(101,'11111111-1111-4111-8111-111111111111',
   'business_member.grant','manager',NULL,NULL,'self-role-mutation');
  RAISE EXCEPTION 'tenant owner changed self role';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'self_access_change_forbidden' THEN RAISE; END IF;
 END;
 IF (SELECT count(*) FROM c10_demo.access_governance_overview_v1
    WHERE business_id=101 AND audited_access_changes=3
     AND active_business_owners=2 AND active_managers=2
     AND active_investors=2 AND NOT real_auth_account_verified)<>1 THEN
  RAISE EXCEPTION 'audited access overview incorrect: %', (SELECT row_to_json(g) FROM c10_demo.access_governance_overview_v1 g WHERE business_id=101); END IF;
END $$;
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',true);
DO $$
DECLARE g bigint;
BEGIN
 g:=c10_demo.change_access_v1(101,'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
  'site_grant.grant',NULL,1001,ARRAY['stock.read','stock.post'],'site-staff-grant');
 IF NOT EXISTS(SELECT 1 FROM c10_demo.site_grants
    WHERE site_id=1001 AND user_id='eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'
     AND active AND 'stock.post'=ANY(actions)) THEN
  RAISE EXCEPTION 'business owner site access grant failed'; END IF;
 BEGIN
  PERFORM c10_demo.change_access_v1(101,'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
   'business_member.grant','business_owner',NULL,NULL,'owner-privilege-escalate');
  RAISE EXCEPTION 'business owner created another business owner';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'tenant_owner_required_for_business_owner_role' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM c10_demo.change_access_v1(101,'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
   'business_member.revoke',NULL,NULL,NULL,'owner-revoke-owner');
  RAISE EXCEPTION 'business owner revoked peer owner';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'business_owner_membership_protected' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM c10_demo.change_access_v1(102,'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
   'site_grant.grant',NULL,1003,ARRAY['stock.read'],'sibling-access');
  RAISE EXCEPTION 'business owner modified sibling business';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'access_change_not_authorized' THEN RAISE; END IF;
 END;
END $$;
COMMIT;

-- Revocation is effective immediately for subsequent queries with the SAME JWT:
-- never authorize by stale JWT role/app_metadata.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',true);
DO $$
BEGIN
 IF (SELECT count(*) FROM c10_demo.stock_locations)<>1 OR
    (SELECT count(*) FROM c10_demo.businesses)<>1 THEN
  RAISE EXCEPTION 'new site staff read scope wrong'; END IF;
 IF EXISTS(SELECT 1 FROM c10_demo.access_change_events_v1) THEN
  RAISE EXCEPTION 'staff saw access audit'; END IF;
END $$;
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
SELECT c10_demo.change_access_v1(
 101,'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
 'business_member.revoke',NULL,NULL,NULL,'revoke-manager-new');
SELECT c10_demo.change_access_v1(
 101,'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
 'site_grant.revoke',NULL,1001,NULL,'revoke-staff-new');
SELECT c10_demo.change_access_v1(
 101,'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
 'business_member.revoke',NULL,NULL,NULL,'revoke-business-owner-new');
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',true);
DO $$
BEGIN
 IF EXISTS(SELECT 1 FROM c10_demo.businesses)
  OR EXISTS(SELECT 1 FROM c10_demo.stock_locations) THEN
  RAISE EXCEPTION 'revoked staff still reads a location'; END IF;
 BEGIN
  PERFORM c10_demo.post_stock_event(5001,8001,1,'revoked-staff-stock');
  RAISE EXCEPTION 'revoked staff posted stock';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'stock_post_not_authorized' THEN RAISE; END IF;
 END;
END $$;
COMMIT;
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',true);
DO $$
BEGIN
 IF EXISTS(SELECT 1 FROM c10_demo.businesses) THEN
   RAISE EXCEPTION 'revoked business manager still has access'; END IF;
END $$;
COMMIT;
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','dddddddd-dddd-4ddd-8ddd-dddddddddddd',true);
DO $$
BEGIN
 IF EXISTS(SELECT 1 FROM c10_demo.access_governance_overview_v1) THEN
  RAISE EXCEPTION 'revoked business owner sees board'; END IF;
END $$;
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',true);
DO $$
BEGIN
 BEGIN
  PERFORM c10_demo.change_access_v1(101,'abababab-abab-4bab-8bab-abababababab',
   'site_grant.grant',NULL,1001,ARRAY['stock.read'],'manager-cannot-grant');
  RAISE EXCEPTION 'manager granted staff access';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'access_change_not_authorized' THEN RAISE; END IF;
 END;
 IF EXISTS(SELECT 1 FROM c10_demo.access_change_events_v1) THEN
  RAISE EXCEPTION 'manager read owner-only audit log'; END IF;
END $$;
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','77777777-7777-4777-8777-777777777777',true);
DO $$
BEGIN
 IF EXISTS(SELECT 1 FROM c10_demo.access_change_events_v1 WHERE tenant_id=1) THEN
  RAISE EXCEPTION 'independent tenant saw portfolio audit'; END IF;
 BEGIN
  PERFORM c10_demo.change_access_v1(101,'abababab-abab-4bab-8bab-abababababab',
   'business_member.grant','manager',NULL,NULL,'customer-forge-1');
  RAISE EXCEPTION 'customer forged portfolio membership';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'access_change_not_authorized' THEN RAISE; END IF;
 END;
END $$;
COMMIT;
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
DO $$
BEGIN
 BEGIN
  INSERT INTO c10_demo.business_members(tenant_id,business_id,user_id,role)
   VALUES(1,101,'11111111-1111-4111-8111-111111111112','business_owner');
  RAISE EXCEPTION 'direct role escalation was allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  UPDATE c10_demo.site_grants SET active=true WHERE site_id=1001;
  RAISE EXCEPTION 'direct revocation bypass was allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
ROLLBACK;
BEGIN;
SET LOCAL ROLE anon;
DO $$
BEGIN
 BEGIN
  PERFORM 1 FROM c10_demo.access_change_events_v1;
  RAISE EXCEPTION 'anonymous read owner access history';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM c10_demo.change_access_v1(101,'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'business_member.grant','manager',NULL,NULL,'anon-forge');
  RAISE EXCEPTION 'anonymous access grant';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
ROLLBACK;
\echo PASS C10-A034 owner role, site grants, audit, exact replay, revoked JWT RLS, cross-company, anon and no direct mutations.
