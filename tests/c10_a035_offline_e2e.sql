\set ON_ERROR_STOP on
\echo C10-A035: ledger version, offline conflict isolation and RLS
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',true);
DO $$
DECLARE r bigint;v bigint;
BEGIN
 r:=c10_demo.replay_offline_stock_v1(5001,8001,10,0,'device-stock-a');
 IF r<>c10_demo.replay_offline_stock_v1(5001,8001,10,0,'device-stock-a') THEN
  RAISE EXCEPTION 'offline applied replay not idempotent'; END IF;
 IF (SELECT status FROM c10_demo.offline_stock_receipts_v1 WHERE id=r)<>'applied' OR
    (SELECT ledger_version FROM c10_demo.offline_stock_snapshot_v1
      WHERE location_id=5001 AND item_id=8001)<>1 OR
    (SELECT on_hand FROM c10_demo.stock_balances_v1 WHERE location_id=5001 AND item_id=8001)<>10
 THEN RAISE EXCEPTION 'first offline event or snapshot incorrect'; END IF;
 v:=c10_demo.replay_offline_stock_v1(5001,8001,2,0,'device-stale');
 IF (SELECT status FROM c10_demo.offline_stock_receipts_v1 WHERE id=v)<>'conflict'
  OR (SELECT conflict_reason FROM c10_demo.offline_stock_receipts_v1 WHERE id=v)<>'stale_ledger_version'
 THEN RAISE EXCEPTION 'stale device write was not quarantined'; END IF;
 v:=c10_demo.replay_offline_stock_v1(5001,8001,-11,1,'device-negative');
 IF (SELECT conflict_reason FROM c10_demo.offline_stock_receipts_v1 WHERE id=v)<>'insufficient_stock'
 THEN RAISE EXCEPTION 'negative replay was not quarantined'; END IF;
 IF (SELECT on_hand FROM c10_demo.stock_balances_v1 WHERE location_id=5001 AND item_id=8001)<>10
 THEN RAISE EXCEPTION 'conflict unexpectedly changed real stock'; END IF;
 BEGIN
  PERFORM c10_demo.replay_offline_stock_v1(5001,8001,11,0,'device-stock-a');
  RAISE EXCEPTION 'device mutated recorded request with same key';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'offline_replay_payload_conflict' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM c10_demo.replay_offline_stock_v1(6001,9001,1,0,'foreign-tenant-event');
  RAISE EXCEPTION 'staff wrote another tenant offline';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'offline_stock_not_authorized' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM c10_demo.replay_offline_stock_v1(5001,9001,1,1,'foreign-item-event');
  RAISE EXCEPTION 'foreign tenant SKU accepted';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'offline_item_scope_mismatch' THEN RAISE; END IF;
 END;
 IF EXISTS(SELECT 1 FROM c10_demo.offline_stock_inbox_v1) THEN
  RAISE EXCEPTION 'staff read owner-only reconciliation dashboard'; END IF;
END $$;
COMMIT;

-- Another actor with broader privilege may move the stock while device is disconnected.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
SELECT c10_demo.post_stock_event(5001,8001,-2,'owner-direct-move');
COMMIT;
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',true);
DO $$
DECLARE a bigint; r bigint;
BEGIN
 a:=c10_demo.replay_offline_stock_v1(5001,8001,-3,2,'device-base2');
 IF (SELECT status FROM c10_demo.offline_stock_receipts_v1 WHERE id=a)<>'applied' OR
   (SELECT on_hand FROM c10_demo.stock_balances_v1 WHERE location_id=5001 AND item_id=8001)<>5
 THEN RAISE EXCEPTION 'matching revision replay not applied'; END IF;
 r:=c10_demo.replay_offline_stock_v1(5001,8001,2,3,'device-rebased-conflict');
 IF (SELECT status FROM c10_demo.offline_stock_receipts_v1 WHERE id=r)<>'applied' OR
   (SELECT on_hand FROM c10_demo.stock_balances_v1 WHERE location_id=5001 AND item_id=8001)<>7
 THEN RAISE EXCEPTION 'manually rebased device event did not post'; END IF;
 IF (SELECT count(*) FROM c10_demo.stock_movements WHERE location_id=5001)<>4 OR
   (SELECT count(*) FROM c10_demo.inventory_reconciliation_v1 WHERE NOT reconciled)<>0 THEN
  RAISE EXCEPTION 'replay idempotence or ledger mismatch'; END IF;
 IF (SELECT count(*) FROM c10_demo.offline_stock_receipts_v1 WHERE status='conflict')<>2 OR
   (SELECT count(*) FROM c10_demo.offline_stock_receipts_v1 WHERE status='applied')<>3 THEN
  RAISE EXCEPTION 'offline receipts statuses inconsistent'; END IF;
END $$;
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
DO $$
BEGIN
 IF (SELECT applied FROM c10_demo.offline_stock_inbox_v1 WHERE location_id=5001)<>3 OR
    (SELECT conflicts FROM c10_demo.offline_stock_inbox_v1 WHERE location_id=5001)<>2 OR
    EXISTS(SELECT 1 FROM c10_demo.offline_stock_inbox_v1 WHERE offline_operationally_certified)
 THEN RAISE EXCEPTION 'owner offline reconciliation report mismatch'; END IF;
 BEGIN
  UPDATE c10_demo.offline_stock_receipts_v1 SET status='applied';
  RAISE EXCEPTION 'owner bypassed immutable receipt status';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
COMMIT;

-- Revocation: even original device actor with prior receipts cannot read/replay.
-- Administrator-only fixture simulates a server-side access revocation; never
-- grant authenticated clients direct UPDATE on memberships or site_grants.
BEGIN;
UPDATE c10_demo.site_grants SET active=false
 WHERE site_id=1001 AND user_id='44444444-4444-4444-8444-444444444444';
COMMIT;
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',true);
DO $$
BEGIN
 IF EXISTS(SELECT 1 FROM c10_demo.offline_stock_receipts_v1) OR
    EXISTS(SELECT 1 FROM c10_demo.offline_stock_snapshot_v1) THEN
  RAISE EXCEPTION 'revoked user retained offline data visibility'; END IF;
 BEGIN
  PERFORM c10_demo.replay_offline_stock_v1(5001,8001,3,4,'revoked-new');
  RAISE EXCEPTION 'revoked user replayed stale device queue';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'offline_stock_not_authorized' THEN RAISE; END IF;
 END;
END $$;
COMMIT;
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','77777777-7777-4777-8777-777777777777',true);
DO $$
BEGIN
 IF EXISTS(SELECT 1 FROM c10_demo.offline_stock_receipts_v1 WHERE business_id=101) THEN
  RAISE EXCEPTION 'different tenant viewed device receipts'; END IF;
 BEGIN
  PERFORM c10_demo.replay_offline_stock_v1(5001,8001,1,4,'customer-spoof');
  RAISE EXCEPTION 'other tenant replayed stock';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'offline_stock_not_authorized' THEN RAISE; END IF;
 END;
END $$;
COMMIT;
BEGIN;
SET LOCAL ROLE anon;
DO $$
BEGIN
 BEGIN
  PERFORM 1 FROM c10_demo.offline_stock_receipts_v1;
  RAISE EXCEPTION 'anon saw receipts';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM c10_demo.replay_offline_stock_v1(5001,8001,1,4,'anon-replay');
  RAISE EXCEPTION 'anon replayed stock';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
ROLLBACK;
\echo PASS C10-A035 replay 5 records: 3 applied, 2 quarantined; exact retry, signed-role revocation, ledger/snapshot scope, tenant and atomic stock validation.
