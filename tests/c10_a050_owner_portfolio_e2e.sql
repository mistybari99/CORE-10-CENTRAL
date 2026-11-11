\set ON_ERROR_STOP on
DO $gate$ BEGIN
 IF has_table_privilege('authenticated','c10_demo.portfolio_layout_v1','INSERT')
 THEN RAISE EXCEPTION 'A050_DIRECT_WRITES_LEAK'; END IF;
END; $gate$;
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
DO $owner$
DECLARE d jsonb;
BEGIN
 d:=c10_demo.read_portfolio_workspace_v1();
 IF jsonb_array_length(d->'businesses')<>2 OR
 jsonb_array_length(d->'businesses'->0->'sites')<>2 OR d->>'production_ready'<>'false'
 THEN RAISE EXCEPTION 'A050_OWNER_PORTFOLIO_FAILED'; END IF;
 d:=c10_demo.set_portfolio_layout_v1(101,'compact',ARRAY['operations','sites'],1,'owner-layout-001');
 IF d->>'version'<>'2' THEN RAISE EXCEPTION 'A050_LAYOUT_FAILED'; END IF;
 d:=c10_demo.set_portfolio_layout_v1(101,'compact',ARRAY['operations','sites'],1,'owner-layout-001');
 IF d->>'replayed'<>'true' THEN RAISE EXCEPTION 'A050_LAYOUT_REPLAY_FAILED'; END IF;
 IF c10_demo.read_portfolio_workspace_v1()->'businesses'->0->'layout'->>'mode'<>'compact'
 THEN RAISE EXCEPTION 'A050_LAYOUT_READ_FAILED'; END IF;
 BEGIN
  PERFORM c10_demo.set_portfolio_layout_v1(101,'compact',ARRAY['sites'],1,'stale-layout-01');
  RAISE EXCEPTION 'A050_STALE_ALLOWED';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'A050_STALE_LAYOUT' THEN RAISE; END IF;
 END;
END $owner$;
ROLLBACK;
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',true);
DO $staff$
DECLARE d jsonb;
BEGIN
 d:=c10_demo.read_portfolio_workspace_v1();
 IF jsonb_array_length(d->'businesses')<>1 OR
 jsonb_array_length(d->'businesses'->0->'sites')<>1 THEN
 RAISE EXCEPTION 'A050_STAFF_SEES_EXTRA_SITES'; END IF;
 BEGIN
  PERFORM c10_demo.set_portfolio_layout_v1(101,'compact',ARRAY['sites'],1,'staff-layout-001');
  RAISE EXCEPTION 'A050_STAFF_EDIT_ALLOWED';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'A050_OWNER_REQUIRED' THEN RAISE; END IF;
 END;
END $staff$;
ROLLBACK;
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','77777777-7777-4777-8777-777777777777',true);
DO $other$
DECLARE d jsonb;
BEGIN
 d:=c10_demo.read_portfolio_workspace_v1();
 IF jsonb_array_length(d->'businesses')<>1 OR
 (d->'businesses'->0->>'business_id')::bigint<>201
 THEN RAISE EXCEPTION 'A050_CROSS_TENANT_LEAK'; END IF;
END $other$;
ROLLBACK;
\echo PASS A050 Owner/Staff/independent-Tenant portfolio and layout test. No GoTrue runtime.
