\set ON_ERROR_STOP on
\echo C10-A031 DISPOSABLE STOCKTAKE: count -> submit -> owner approve -> atomic adjustment
-- Fake actor identities from tests/c10_a018_demo_seed.sql; NOT real GoTrue/Auth.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
DO $seed$
BEGIN
 PERFORM c10_demo.post_stock_event(5001,8001,10,'stocktake-seed-main');
 PERFORM c10_demo.post_stock_event(5002,8001,4,'stocktake-seed-factory');
 IF (SELECT sum(on_hand) FROM c10_demo.stock_balances_v1
  WHERE business_id=101 AND item_id=8001)<>14 THEN
  RAISE EXCEPTION 'seed_balance_wrong'; END IF;
END $seed$;
COMMIT;

-- Site staff count the ONLY granted showroom, no direct stock modification yet.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',true);
DO $staff$
DECLARE v_id bigint;v_retry bigint;
BEGIN
 v_id:=c10_demo.create_stocktake_v1(
  5001,'[{"item_id":8001,"counted":7}]'::jsonb,'main-count-001');
 v_retry:=c10_demo.create_stocktake_v1(
  5001,'[{"item_id":8001,"counted":7}]'::jsonb,'main-count-001');
 IF v_id<>v_retry THEN RAISE EXCEPTION 'stocktake_retry_new_doc'; END IF;
 IF (SELECT count(*) FROM c10_demo.stocktake_lines_v1 WHERE stocktake_id=v_id)<>1
  THEN RAISE EXCEPTION 'stocktake_retry_duplicate_line'; END IF;
 BEGIN
  PERFORM c10_demo.create_stocktake_v1(
   5001,'[{"item_id":8001,"counted":8}]'::jsonb,'main-count-001');
  RAISE EXCEPTION 'stocktake_changed_retry_accepted';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'stocktake_idempotency_conflict' THEN RAISE; END IF;
 END;
 FOR v_retry IN SELECT 1 LOOP
  BEGIN
   PERFORM c10_demo.create_stocktake_v1(
    5001,'[{"item_id":8001,"counted":7},{"item_id":8001,"counted":8}]'::jsonb,
    'duplicate-items-denied');
   RAISE EXCEPTION 'duplicate_count_item_accepted';
  EXCEPTION WHEN raise_exception THEN
   IF SQLERRM<>'invalid_stocktake_item' THEN RAISE; END IF;
  END;
  BEGIN
   PERFORM c10_demo.create_stocktake_v1(
    5001,'[{"item_id":9001,"counted":1}]'::jsonb,'foreign-item-denied');
   RAISE EXCEPTION 'other_business_item_accepted';
  EXCEPTION WHEN raise_exception THEN
   IF SQLERRM<>'stocktake_item_business_mismatch' THEN RAISE; END IF;
  END;
  BEGIN
   PERFORM c10_demo.create_stocktake_v1(
    5001,'[{"item_id":8001,"counted":-1}]'::jsonb,'negative-item-denied');
   RAISE EXCEPTION 'negative_count_accepted';
  EXCEPTION WHEN raise_exception THEN
   IF SQLERRM<>'invalid_stocktake_item' THEN RAISE; END IF;
  END;
 END LOOP;
 IF c10_demo.submit_stocktake_v1(v_id)<>'submitted' OR
    c10_demo.submit_stocktake_v1(v_id)<>'submitted' THEN
    RAISE EXCEPTION 'stocktake_submit_not_idempotent'; END IF;
 IF (SELECT expected_quantity FROM c10_demo.stocktake_lines_v1
    WHERE stocktake_id=v_id AND item_id=8001)<>10 THEN
  RAISE EXCEPTION 'server_side_expected_snapshot_missing'; END IF;
 IF (SELECT count(*) FROM c10_demo.stock_movements)<>2 OR
    (SELECT on_hand FROM c10_demo.stock_balances_v1
     WHERE location_id=5001 AND item_id=8001)<>10 THEN
  RAISE EXCEPTION 'unapproved_count_changed_stock'; END IF;
 BEGIN
  PERFORM c10_demo.approve_stocktake_v1(v_id);
  RAISE EXCEPTION 'staff_approved_own_stocktake';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'stocktake_approval_denied' THEN RAISE; END IF;
 END;
 BEGIN
  UPDATE c10_demo.stocktake_lines_v1 SET counted_quantity=99
   WHERE stocktake_id=v_id;
  RAISE EXCEPTION 'staff_direct_count_mutation';
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
END $staff$;
COMMIT;

-- Separate portfolio owner approves and posts exact physical discrepancy.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
DO $owner$
DECLARE v_id bigint;v_events int;v_movement bigint;
BEGIN
 SELECT id INTO v_id FROM c10_demo.stocktakes_v1 WHERE request_key='main-count-001';
 IF c10_demo.approve_stocktake_v1(v_id)<>'approved' OR
    c10_demo.approve_stocktake_v1(v_id)<>'approved' THEN
  RAISE EXCEPTION 'approval_not_idempotent'; END IF;
 IF (SELECT on_hand FROM c10_demo.stock_balances_v1
  WHERE location_id=5001 AND item_id=8001)<>10 THEN
  RAISE EXCEPTION 'approval_changed_stock'; END IF;
 IF c10_demo.post_stocktake_v1(v_id)<>'posted' OR
    c10_demo.post_stocktake_v1(v_id)<>'posted' THEN
  RAISE EXCEPTION 'post_not_idempotent'; END IF;
 IF (SELECT on_hand FROM c10_demo.stock_balances_v1
  WHERE location_id=5001 AND item_id=8001)<>7 THEN
  RAISE EXCEPTION 'physical_adjustment_wrong'; END IF;
 SELECT adjustment_movement_id INTO v_movement FROM c10_demo.stocktake_lines_v1
  WHERE stocktake_id=v_id AND item_id=8001;
 IF v_movement IS NULL OR
   (SELECT delta FROM c10_demo.stock_movements WHERE id=v_movement)<>-3 THEN
  RAISE EXCEPTION 'stocktake_journal_missing'; END IF;
 IF (SELECT count(*) FROM c10_demo.stock_movements WHERE location_id=5001)<>2 THEN
  RAISE EXCEPTION 'duplicate_stocktake_journal_on_retry'; END IF;
 IF EXISTS(SELECT 1 FROM c10_demo.inventory_reconciliation_v1 WHERE NOT reconciled)
 THEN RAISE EXCEPTION 'stocktake_ledger_not_reconciled'; END IF;
 SELECT count(*) INTO v_events FROM c10_demo.stocktake_audit_v1 WHERE stocktake_id=v_id;
 IF v_events<>4 THEN RAISE EXCEPTION 'stocktake_audit_not_exactly_once'; END IF;
 BEGIN
  PERFORM c10_demo.void_stocktake_v1(v_id,'Cannot erase posted ledger');
  RAISE EXCEPTION 'posted_stocktake_voided';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'posted_stocktake_immutable' THEN RAISE; END IF;
 END;
END $owner$;
COMMIT;

-- A new physical count is stale if a real stock event arrives after submit.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',true);
SELECT c10_demo.submit_stocktake_v1(c10_demo.create_stocktake_v1(
 5001,'[{"item_id":8001,"counted":5}]'::jsonb,'main-count-stale-002'));
COMMIT;
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
DO $stale$
DECLARE v_id bigint;
BEGIN
 SELECT id INTO v_id FROM c10_demo.stocktakes_v1 WHERE request_key='main-count-stale-002';
 PERFORM c10_demo.approve_stocktake_v1(v_id);
 PERFORM c10_demo.post_stock_event(5001,8001,-1,'stocktake-intervening-sale');
 BEGIN
  PERFORM c10_demo.post_stocktake_v1(v_id);
  RAISE EXCEPTION 'stale_count_overwrote_intervening_stock';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'stocktake_stale_recount_required' THEN RAISE; END IF;
 END;
 IF (SELECT status FROM c10_demo.stocktakes_v1 WHERE id=v_id)<>'approved' OR
    (SELECT on_hand FROM c10_demo.stock_balances_v1
     WHERE location_id=5001 AND item_id=8001)<>6 THEN
  RAISE EXCEPTION 'stale_failure_changed_business_data'; END IF;
 IF c10_demo.void_stocktake_v1(v_id,'Movement after count; recount required')<>'voided' OR
    c10_demo.void_stocktake_v1(v_id,'Movement after count; recount required')<>'voided' THEN
  RAISE EXCEPTION 'void_stocktake_not_idempotent'; END IF;
 BEGIN
  PERFORM c10_demo.post_stocktake_v1(v_id);
  RAISE EXCEPTION 'voided_stocktake_posted';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'stocktake_not_approved' THEN RAISE; END IF;
 END;
END $stale$;
COMMIT;

-- Separation of duties applies even when a tenant owner performs the count.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
DO $self$
DECLARE v_id bigint;
BEGIN
 v_id:=c10_demo.create_stocktake_v1(
  5002,'[{"item_id":8001,"counted":4}]'::jsonb,'factory-unchanged-003');
 PERFORM c10_demo.submit_stocktake_v1(v_id);
 BEGIN
  PERFORM c10_demo.approve_stocktake_v1(v_id);
  RAISE EXCEPTION 'owner_self_approved_stocktake';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'stocktake_self_approval_forbidden' THEN RAISE; END IF;
 END;
END $self$;
COMMIT;
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',true);
DO $business_owner$
DECLARE v_id bigint;
BEGIN
 SELECT id INTO v_id FROM c10_demo.stocktakes_v1 WHERE request_key='factory-unchanged-003';
 PERFORM c10_demo.approve_stocktake_v1(v_id);
 PERFORM c10_demo.post_stocktake_v1(v_id);
 IF (SELECT count(*) FROM c10_demo.stock_movements WHERE location_id=5002)<>1 OR
    (SELECT count(*) FROM c10_demo.stocktake_lines_v1
      WHERE stocktake_id=v_id AND adjustment_movement_id IS NOT NULL)<>0 THEN
  RAISE EXCEPTION 'zero_diff_created_fake_movement'; END IF;
END $business_owner$;
COMMIT;

-- Independent tenant, investors and revoked principals never read A stocktakes.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','77777777-7777-4777-8777-777777777777',true);
DO $tenant_b$
BEGIN
 IF (SELECT count(*) FROM c10_demo.stocktakes_v1)<>0 OR
    (SELECT count(*) FROM c10_demo.stocktake_lines_v1)<>0 OR
    (SELECT count(*) FROM c10_demo.stocktake_audit_v1)<>0 OR
    (SELECT count(*) FROM c10_demo.stocktake_discrepancy_v1)<>0 THEN
  RAISE EXCEPTION 'cross_tenant_stocktake_visible'; END IF;
 BEGIN
  PERFORM c10_demo.post_stocktake_v1(
    (SELECT id FROM c10_demo.stocktakes_v1 WHERE request_key='main-count-001'));
  RAISE EXCEPTION 'tenant_b_posted_tenant_a_stocktake';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'invalid_stocktake_id' THEN RAISE; END IF;
 END;
END $tenant_b$;
COMMIT;
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','55555555-5555-4555-8555-555555555555',true);
DO $investor$
BEGIN
 IF (SELECT count(*) FROM c10_demo.stocktakes_v1)<>0 THEN
  RAISE EXCEPTION 'investor_read_stocktake'; END IF;
 BEGIN
  PERFORM c10_demo.create_stocktake_v1(
    5001,'[{"item_id":8001,"counted":100}]'::jsonb,'investor-forbidden');
  RAISE EXCEPTION 'investor_created_stocktake';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'stocktake_scope_denied' THEN RAISE; END IF;
 END;
END $investor$;
COMMIT;
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','66666666-6666-4666-8666-666666666666',true);
DO $revoked$
BEGIN
 IF (SELECT count(*) FROM c10_demo.stocktakes_v1)<>0 THEN
  RAISE EXCEPTION 'revoked_member_read_stocktake'; END IF;
END $revoked$;
COMMIT;
BEGIN;
SET LOCAL ROLE anon;
DO $anonymous$
BEGIN
 BEGIN
  PERFORM count(*) FROM c10_demo.stocktakes_v1;
  RAISE EXCEPTION 'anon_read_stocktakes';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM c10_demo.create_stocktake_v1(
    5001,'[{"item_id":8001,"counted":1}]'::jsonb,'anon-forbidden');
  RAISE EXCEPTION 'anon_created_stocktake';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $anonymous$;
ROLLBACK;

-- Reconciliation must remain exact after every accepted and rejected operation.
DO $final$
BEGIN
 IF EXISTS(SELECT 1 FROM c10_demo.inventory_reconciliation_v1 WHERE NOT reconciled)
 THEN RAISE EXCEPTION 'final_stock_balance_journal_mismatch'; END IF;
 IF (SELECT count(*) FROM c10_demo.stocktakes_v1)<>3 OR
    (SELECT count(*) FROM c10_demo.stocktakes_v1 WHERE status='posted')<>2 OR
    (SELECT count(*) FROM c10_demo.stocktakes_v1 WHERE status='voided')<>1 OR
    (SELECT count(*) FROM c10_demo.stocktake_audit_v1)<>12 OR
    (SELECT count(*) FROM c10_demo.stock_movements)<>4 THEN
  RAISE EXCEPTION 'stocktake_final_audit_or_journal_count_wrong'; END IF;
END $final$;
\echo PASS A031 physical count/approval/variance adjust, stale/recount, six negative cases, exact journal and audit. DISPOSABLE PG17 only.
