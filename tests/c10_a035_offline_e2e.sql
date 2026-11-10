\set ON_ERROR_STOP on
\echo C10-A035: offline STOCK DRAFTS only, conflict quarantine and no posting
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',true);
DO $$
DECLARE a bigint;b bigint;c bigint;
BEGIN
 a:=c10_demo.replay_offline_stock_v1(5001,8001,10,0,'device-suggest-plus10');
 IF a<>c10_demo.replay_offline_stock_v1(5001,8001,10,0,'device-suggest-plus10') OR
  (SELECT status FROM c10_demo.offline_stock_receipts_v1 WHERE id=a)<>'staged'
 THEN RAISE EXCEPTION 'draft idempotence or staging incorrect'; END IF;
 IF (SELECT on_hand FROM c10_demo.stock_balances_v1
   WHERE location_id=5001 AND item_id=8001)<>0 OR
   EXISTS(SELECT 1 FROM c10_demo.stock_movements) THEN
  RAISE EXCEPTION 'OFFLINE DRAFT CHANGED STOCK'; END IF;
 b:=c10_demo.replay_offline_stock_v1(5001,8001,1,9,'device-stale');
 c:=c10_demo.replay_offline_stock_v1(5001,8001,-11,0,'device-negative');
 IF (SELECT conflict_reason FROM c10_demo.offline_stock_receipts_v1 WHERE id=b)
     <>'stale_ledger_version' OR
    (SELECT conflict_reason FROM c10_demo.offline_stock_receipts_v1 WHERE id=c)
     <>'insufficient_stock' OR
    EXISTS(SELECT 1 FROM c10_demo.stock_movements) THEN
  RAISE EXCEPTION 'conflicts failed or changed ledger'; END IF;
 BEGIN
  PERFORM c10_demo.review_offline_stock_draft_v1(a,'review');
  RAISE EXCEPTION 'staff owner-reviewed offline draft';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'offline_review_not_authorized' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM c10_demo.replay_offline_stock_v1(5001,8001,11,0,'device-suggest-plus10');
  RAISE EXCEPTION 'mutated offline request accepted';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'offline_replay_payload_conflict' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM c10_demo.replay_offline_stock_v1(6001,9001,1,0,'foreign-tenant');
  RAISE EXCEPTION 'cross-tenant offline draft accepted';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'offline_stock_not_authorized' THEN RAISE; END IF;
 END;
 IF EXISTS(SELECT 1 FROM c10_demo.offline_stock_inbox_v1) THEN
  RAISE EXCEPTION 'site staff sees owner-only offline inbox'; END IF;
END $$;
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
SELECT c10_demo.post_stock_event(5001,8001,20,'online-verified-receive');
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',true);
DO $$
DECLARE r bigint;
BEGIN
 r:=c10_demo.replay_offline_stock_v1(5001,8001,-3,1,'device-suggest-minus3');
 IF (SELECT status FROM c10_demo.offline_stock_receipts_v1 WHERE id=r)<>'staged'
 THEN RAISE EXCEPTION 'fresh version not staged'; END IF;
 IF (SELECT on_hand FROM c10_demo.stock_balances_v1 WHERE location_id=5001 AND item_id=8001)<>20 OR
    (SELECT count(*) FROM c10_demo.stock_movements)<>1 THEN
  RAISE EXCEPTION 'offline proposal unexpectedly moved live stock'; END IF;
 IF (SELECT ledger_version FROM c10_demo.offline_stock_snapshot_v1
   WHERE location_id=5001 AND item_id=8001)<>1 THEN
  RAISE EXCEPTION 'online-only ledger version incorrect'; END IF;
END $$;
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
DO $$
DECLARE a bigint;b bigint;
BEGIN
 SELECT id INTO a FROM c10_demo.offline_stock_receipts_v1
  WHERE request_key='device-suggest-plus10';
 SELECT id INTO b FROM c10_demo.offline_stock_receipts_v1
  WHERE request_key='device-stale';
 IF c10_demo.review_offline_stock_draft_v1(a,'review')<>'reviewed' OR
    c10_demo.review_offline_stock_draft_v1(a,'review')<>'reviewed' THEN
  RAISE EXCEPTION 'owner review retry failed'; END IF;
 BEGIN
  PERFORM c10_demo.review_offline_stock_draft_v1(b,'review');
  RAISE EXCEPTION 'conflicted offline draft approved';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'conflicted_offline_draft_cannot_be_approved' THEN RAISE; END IF;
 END;
 IF c10_demo.review_offline_stock_draft_v1(b,'reject')<>'rejected' THEN
  RAISE EXCEPTION 'owner conflict reject failed'; END IF;
 IF (SELECT staged FROM c10_demo.offline_stock_inbox_v1 WHERE location_id=5001)<>2 OR
    (SELECT conflicts FROM c10_demo.offline_stock_inbox_v1 WHERE location_id=5001)<>2 OR
    (SELECT owner_reviewed FROM c10_demo.offline_stock_inbox_v1 WHERE location_id=5001)<>1 THEN
  RAISE EXCEPTION 'owner offline inbox reconciliation incorrect'; END IF;
 IF (SELECT on_hand FROM c10_demo.stock_balances_v1 WHERE location_id=5001 AND item_id=8001)<>20 OR
    (SELECT count(*) FROM c10_demo.stock_movements)<>1 THEN
  RAISE EXCEPTION 'owner review posted stock'; END IF;
 BEGIN
  UPDATE c10_demo.offline_stock_receipts_v1 SET status='staged';
  RAISE EXCEPTION 'direct receipt alteration allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
COMMIT;
-- Fixture revokes user at server role, never direct UPDATE by authenticated client.
BEGIN;
UPDATE c10_demo.site_grants SET active=false WHERE site_id=1001
 AND user_id='44444444-4444-4444-8444-444444444444';
COMMIT;
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',true);
DO $$
BEGIN
 IF EXISTS(SELECT 1 FROM c10_demo.offline_stock_receipts_v1) OR
    EXISTS(SELECT 1 FROM c10_demo.offline_stock_snapshot_v1) THEN
  RAISE EXCEPTION 'revoked device retained offline data'; END IF;
 BEGIN
  PERFORM c10_demo.replay_offline_stock_v1(5001,8001,1,1,'revoked-device');
  RAISE EXCEPTION 'revoked device synced stock proposal';
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
 IF EXISTS(SELECT 1 FROM c10_demo.offline_stock_receipts_v1 WHERE tenant_id=1) THEN
  RAISE EXCEPTION 'other tenant saw offline draft'; END IF;
 BEGIN
  PERFORM c10_demo.replay_offline_stock_v1(5001,8001,1,1,'other-tenant');
  RAISE EXCEPTION 'cross-tenant stock proposal';
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
  RAISE EXCEPTION 'anonymous read offline receipts';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM c10_demo.replay_offline_stock_v1(5001,8001,1,1,'anon');
  RAISE EXCEPTION 'anonymous submitted offline draft';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
ROLLBACK;
\echo PASS: offline drafts only; owner review and conflict are NEVER stock postings.
