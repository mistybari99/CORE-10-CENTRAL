\set ON_ERROR_STOP on
\echo C10-A047: isolated PG17 grouped site topology and owner/staff/tenant E2E.
DO $initial$
BEGIN
 IF (SELECT count(*) FROM c10_demo.sites)<>4 OR
  (SELECT count(*) FROM c10_demo.stock_locations)<>4 OR
  has_table_privilege('authenticated','c10_demo.site_groups_v1','SELECT') OR
  has_table_privilege('authenticated','c10_demo.site_group_members_v1','INSERT') OR
  has_table_privilege('authenticated','c10_demo.site_group_audit_v1','UPDATE') THEN
  RAISE EXCEPTION 'A047_INITIAL_SCOPE_OR_DIRECT_DML_LEAK';
 END IF;
END $initial$;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
DO $owner$
DECLARE g bigint; sid bigint; v jsonb; one jsonb; two jsonb; location_before bigint; location_after bigint;
BEGIN
 IF (c10_demo.bootstrap_site_groups_v1(101,'boot-101-001')->>'initialized')<>'true' THEN
  RAISE EXCEPTION 'A047_BOOTSTRAP_FAILED'; END IF;
 IF (c10_demo.bootstrap_site_groups_v1(101,'boot-101-001')->>'new_members')<>'0' THEN
  RAISE EXCEPTION 'A047_BOOTSTRAP_NOT_IDEMPOTENT'; END IF;
 IF (SELECT count(*) FROM c10_demo.site_group_members_v1 WHERE business_id=101)<>2 THEN
  RAISE EXCEPTION 'A047_ORIGINAL_SITE_MEMBERS_LOST'; END IF;
 PERFORM c10_demo.bootstrap_site_groups_v1(102,'boot-102-001');
 IF (SELECT count(*) FROM c10_demo.site_group_members_v1 WHERE business_id=102)<>1 THEN
  RAISE EXCEPTION 'A047_SECOND_BUSINESS_NOT_GROUPED'; END IF;
 one:=c10_demo.create_site_group_v1(101,'showroom','north_showrooms','North Showrooms','group-north-001');
 two:=c10_demo.create_site_group_v1(101,'showroom','north_showrooms','North Showrooms','group-north-001');
 IF one<>two THEN RAISE EXCEPTION 'A047_GROUP_REPLAY_CHANGED_ID'; END IF;
 g:=(one->>'group_id')::bigint;
 SELECT id INTO location_before FROM c10_demo.stock_locations WHERE site_id=1001;
 v:=c10_demo.move_site_group_v1(1001,g,1,'move-original-01','Reorganize existing shop');
 IF v->>'version'<>'2' OR v->>'replayed'<>'false' THEN
  RAISE EXCEPTION 'A047_MOVE_NOT_VERSIONED'; END IF;
 v:=c10_demo.move_site_group_v1(1001,g,1,'move-original-01','Reorganize existing shop');
 IF v->>'version'<>'2' OR v->>'replayed'<>'true' THEN
  RAISE EXCEPTION 'A047_MOVE_NOT_IDEMPOTENT'; END IF;
 SELECT id INTO location_after FROM c10_demo.stock_locations WHERE site_id=1001;
 IF location_before<>location_after OR location_after<>5001 THEN
  RAISE EXCEPTION 'A047_STOCK_LOCATION_ID_CHANGED'; END IF;
 BEGIN
  PERFORM c10_demo.move_site_group_v1(1001,g,1,'move-old-001','Old version mutation');
  RAISE EXCEPTION 'A047_STALE_ACCEPTED';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'topology_stale_version' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM c10_demo.move_site_group_v1(1001,g,1,'move-original-01','Changed after replay');
  RAISE EXCEPTION 'A047_REPLAY_TAMPER_ACCEPTED';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'topology_move_replay_conflict' THEN RAISE; END IF;
 END;
 one:=c10_demo.create_site_in_group_v1(101,g,'North Test Showroom','create-shop-01');
 two:=c10_demo.create_site_in_group_v1(101,g,'North Test Showroom','create-shop-01');
 IF one<>two THEN RAISE EXCEPTION 'A047_SITE_IDEMPOTENCY_FAILED'; END IF;
 sid:=(one->>'site_id')::bigint;
 IF (SELECT count(*) FROM c10_demo.sites WHERE id=sid AND business_id=101 AND kind='showroom')<>1 OR
  (SELECT count(*) FROM c10_demo.stock_locations WHERE site_id=sid)<>1 OR
  (SELECT group_id FROM c10_demo.site_group_members_v1 WHERE site_id=sid)<>g THEN
  RAISE EXCEPTION 'A047_CANONICAL_SITE_AND_LOCATION_NOT_CREATED'; END IF;
 v:=c10_demo.read_site_topology_v1(101);
 IF v->>'server_authorized'<>'true' OR v->>'can_manage'<>'true' OR
  jsonb_array_length(v->'groups')<>6 OR jsonb_array_length(v->'ungrouped')<>0 THEN
  RAISE EXCEPTION 'A047_OWNER_GROUPED_READ_INVALID'; END IF;
 IF (c10_demo.read_site_topology_audit_v1(101,50)->'items')='[]'::jsonb OR
  (SELECT count(*) FROM c10_demo.site_group_audit_v1 WHERE business_id=101 AND event_kind='site_moved')<>1 THEN
  RAISE EXCEPTION 'A047_AUDIT_MISSING'; END IF;
 BEGIN
  PERFORM c10_demo.create_site_group_v1(101,'factory','north_showrooms','Kind mismatch','group-north-001');
  RAISE EXCEPTION 'A047_MUTATED_IDEMPOTENCY';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'topology_group_idempotency_conflict' THEN RAISE; END IF;
 END;
END $owner$;
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','77777777-7777-4777-8777-777777777777',true);
DO $customer$
DECLARE v jsonb;
BEGIN
 v:=c10_demo.bootstrap_site_groups_v1(201,'boot-201-001');
 IF v->>'initialized'<>'true' THEN RAISE EXCEPTION 'A047_INDEPENDENT_TENANT_BOOTSTRAP'; END IF;
 v:=c10_demo.read_site_topology_v1(201);
 IF jsonb_array_length(v->'groups')<>5 THEN RAISE EXCEPTION 'A047_INDEPENDENT_GROUP_COUNT'; END IF;
 BEGIN
  PERFORM c10_demo.read_site_topology_v1(101);
  RAISE EXCEPTION 'A047_CROSS_TENANT_READ_ALLOWED';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'topology_read_denied' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM c10_demo.bootstrap_site_groups_v1(101,'cross-owner-001');
  RAISE EXCEPTION 'A047_CROSS_TENANT_BOOTSTRAP_ALLOWED';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'topology_manage_denied' THEN RAISE; END IF;
 END;
END $customer$;
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',true);
DO $staff$
DECLARE v jsonb; sitecount integer;
BEGIN
 v:=c10_demo.read_site_topology_v1(101);
 IF v->>'can_manage'<>'false' OR jsonb_array_length(v->'groups')<>1 THEN
  RAISE EXCEPTION 'A047_STAFF_GROUP_SCOPE_LEAK'; END IF;
 SELECT count(*) INTO sitecount FROM jsonb_array_elements(v->'groups') gr,
  jsonb_array_elements(gr->'sites') si WHERE (si->>'site_id')::bigint=1001;
 IF sitecount<>1 THEN RAISE EXCEPTION 'A047_STAFF_OWN_SITE_NOT_VISIBLE'; END IF;
 IF v::text LIKE '%1002%' OR v::text LIKE '%102%' OR v::text LIKE '%201%' THEN
  RAISE EXCEPTION 'A047_STAFF_OTHER_SCOPE_LEAK'; END IF;
 BEGIN
  PERFORM c10_demo.create_site_group_v1(101,'showroom','staff_cannot','Bad group','staff-group-001');
  RAISE EXCEPTION 'A047_STAFF_GROUP_WRITE';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'topology_manage_denied' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM c10_demo.read_site_topology_audit_v1(101,10);
  RAISE EXCEPTION 'A047_STAFF_AUDIT_READ';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'topology_audit_denied' THEN RAISE; END IF;
 END;
END $staff$;
ROLLBACK;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',true);
DO $business_owner$
DECLARE v jsonb;
BEGIN
 v:=c10_demo.read_site_topology_v1(101);
 IF v->>'can_manage'<>'true' OR jsonb_array_length(v->'groups')<>6 THEN
  RAISE EXCEPTION 'A047_BUSINESS_OWNER_SCOPE_MISSING'; END IF;
 BEGIN
  PERFORM c10_demo.bootstrap_site_groups_v1(102,'cross-biz-001');
  RAISE EXCEPTION 'A047_FOREIGN_BUSINESS_WRITE';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'topology_manage_denied' THEN RAISE; END IF;
 END;
END $business_owner$;
ROLLBACK;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',true);
DO $manager$
BEGIN
 IF (c10_demo.read_site_topology_v1(101)->>'can_manage')<>'false' THEN
  RAISE EXCEPTION 'A047_MANAGER_ELEVATED'; END IF;
 BEGIN
  PERFORM c10_demo.bootstrap_site_groups_v1(101,'manager-try-001');
  RAISE EXCEPTION 'A047_MANAGER_GROUP_WRITE';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'topology_manage_denied' THEN RAISE; END IF;
 END;
END $manager$;
ROLLBACK;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','66666666-6666-4666-8666-666666666666',true);
DO $revoked$
BEGIN
 BEGIN
  PERFORM c10_demo.read_site_topology_v1(101);
  RAISE EXCEPTION 'A047_REVOKED_READ_ALLOWED';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'topology_read_denied' THEN RAISE; END IF;
 END;
END $revoked$;
ROLLBACK;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','55555555-5555-4555-8555-555555555555',true);
DO $investor$
BEGIN
 BEGIN
  PERFORM c10_demo.read_site_topology_v1(101);
  RAISE EXCEPTION 'A047_INVESTOR_OPERATIONAL_SCOPE_LEAK';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'topology_read_denied' THEN RAISE; END IF;
 END;
END $investor$;
ROLLBACK;

BEGIN;
SET LOCAL ROLE anon;
DO $anon$
BEGIN
 BEGIN
  EXECUTE 'SELECT c10_demo.read_site_topology_v1(101)';
  RAISE EXCEPTION 'A047_ANON_READ_ALLOWED';
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
END $anon$;
ROLLBACK;
\echo PASS A047 groups, canonical site/location invariants, cross-scope read/write, 2 tenants, replay/stale/audit; synthetic PG only.
