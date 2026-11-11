\set ON_ERROR_STOP on
\echo CORE10 INVENTORY V1 E2E: bounded balance, atomic transfer, idempotency, tenancy

-- The preceding demo E2E posts A location 5001=15, factory 5002=3,
-- customer location 6001=9. This suite must never touch SG production.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
DO $$
DECLARE v_transfer bigint; v_retry bigint;
BEGIN
 IF (SELECT on_hand FROM c10_demo.stock_balances_v1
     WHERE location_id=5001 AND item_id=8001)<>15 THEN
  RAISE EXCEPTION 'initial balance failed';
 END IF;
 IF (SELECT on_hand FROM c10_demo.stock_balances_v1
     WHERE location_id=5002 AND item_id=8001)<>3 THEN
  RAISE EXCEPTION 'factory balance failed';
 END IF;
 IF EXISTS(SELECT 1 FROM c10_demo.inventory_reconciliation_v1
     WHERE NOT reconciled) THEN RAISE EXCEPTION 'initial ledger mismatch'; END IF;

 v_transfer:=c10_demo.transfer_stock_v1(5001,5002,8001,5,'transfer-main-factory-001');
 v_retry:=c10_demo.transfer_stock_v1(5001,5002,8001,5,'transfer-main-factory-001');
 IF v_transfer<>v_retry THEN RAISE EXCEPTION 'transfer retry new ID'; END IF;
 IF (SELECT count(*) FROM c10_demo.stock_movements
      WHERE transfer_id=v_transfer)<>2 THEN RAISE EXCEPTION 'transfer not double-entry'; END IF;
 IF (SELECT sum(delta) FROM c10_demo.stock_movements
      WHERE transfer_id=v_transfer)<>0 THEN RAISE EXCEPTION 'transfer created/destroyed stock'; END IF;
 IF (SELECT on_hand FROM c10_demo.stock_balances_v1
      WHERE location_id=5001 AND item_id=8001)<>10 OR
    (SELECT on_hand FROM c10_demo.stock_balances_v1
      WHERE location_id=5002 AND item_id=8001)<>8 THEN
  RAISE EXCEPTION 'transfer balance mismatch';
 END IF;
 IF EXISTS(SELECT 1 FROM c10_demo.inventory_reconciliation_v1
      WHERE NOT reconciled) THEN RAISE EXCEPTION 'transfer ledger mismatch'; END IF;
 IF (SELECT sum(on_hand) FROM c10_demo.stock_balances_v1
     WHERE business_id=101 AND item_id=8001)<>18 THEN
  RAISE EXCEPTION 'internal transfer changed business aggregate';
 END IF;
 BEGIN
  PERFORM c10_demo.transfer_stock_v1(5001,5002,8001,6,'transfer-main-factory-001');
  RAISE EXCEPTION 'idempotency conflict transfer accepted';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'idempotency_key_payload_conflict' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM c10_demo.post_stock_event(5001,8001,-100,'oversell-deny-01');
  RAISE EXCEPTION 'negative stock accepted';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'insufficient_stock' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM c10_demo.transfer_stock_v1(5001,5002,8001,100,'transfer-overdraw-01');
  RAISE EXCEPTION 'overdraw transfer accepted';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'insufficient_stock' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM c10_demo.transfer_stock_v1(5001,5003,8001,1,'cross-business-deny-01');
  RAISE EXCEPTION 'cross-business transfer accepted';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'cross_business_transfer_forbidden' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM c10_demo.transfer_stock_v1(5001,6001,8001,1,'cross-tenant-deny-01');
  RAISE EXCEPTION 'cross-tenant transfer accepted';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'cross_business_transfer_forbidden' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM c10_demo.post_stock_event(5001,8001,1.0005,'precision-deny-01');
  RAISE EXCEPTION 'precision silently rounded';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'invalid_stock_event' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM c10_demo.post_stock_event(5001,8001,1,'c10-transfer:forged');
  RAISE EXCEPTION 'reserved transfer key accepted';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'invalid_stock_event' THEN RAISE; END IF;
 END;
 BEGIN
  INSERT INTO c10_demo.stock_movements(
    tenant_id,business_id,site_id,location_id,item_id,delta,request_key)
  VALUES(1,101,1001,5001,8001,999,'bypass-guard');
  RAISE EXCEPTION 'direct stock journal insert succeeded';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  UPDATE c10_demo.stock_balances_v1
    SET on_hand=999999 WHERE location_id=5001 AND item_id=8001;
  RAISE EXCEPTION 'direct balance update succeeded';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 IF EXISTS(SELECT 1 FROM c10_demo.inventory_reconciliation_v1
      WHERE NOT reconciled) THEN RAISE EXCEPTION 'failed request altered ledger'; END IF;
END $$;
COMMIT;

-- Site staff can adjust permitted stock but cannot transfer from another site.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',true);
DO $$
BEGIN
 IF (SELECT count(*) FROM c10_demo.stock_balances_v1)<>1 OR
    (SELECT count(*) FROM c10_demo.inventory_reconciliation_v1)<>1 THEN
  RAISE EXCEPTION 'site staff sees other-site inventory';
 END IF;
 IF (SELECT count(*) FROM c10_demo.stock_transfers_v1)<>0 THEN
  RAISE EXCEPTION 'staff saw two-end transfer data without both site grants';
 END IF;
 BEGIN
  PERFORM c10_demo.transfer_stock_v1(5001,5002,8001,1,'staff-disallowed-transfer');
  RAISE EXCEPTION 'site-only staff transferred to unauthorized site';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'transfer_not_authorized' THEN RAISE; END IF;
 END;
END $$;
COMMIT;

-- Independent tenant sees only customer stock, no transfers from owner business.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','77777777-7777-4777-8777-777777777777',true);
DO $$
BEGIN
 IF (SELECT count(*) FROM c10_demo.stock_balances_v1)<>1 OR
    (SELECT on_hand FROM c10_demo.stock_balances_v1 LIMIT 1)<>9 THEN
  RAISE EXCEPTION 'customer stock isolation';
 END IF;
 IF (SELECT count(*) FROM c10_demo.stock_transfers_v1)<>0 THEN
  RAISE EXCEPTION 'foreign transfer header leaked';
 END IF;
END $$;
COMMIT;

-- Investor must not acquire stock rights through business investment membership.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','55555555-5555-4555-8555-555555555555',true);
DO $$
BEGIN
 IF (SELECT count(*) FROM c10_demo.stock_balances_v1)<>0 THEN
  RAISE EXCEPTION 'investor stock visibility';
 END IF;
 BEGIN
  PERFORM c10_demo.post_stock_event(5001,8001,1,'investor-post-forbidden');
  RAISE EXCEPTION 'investor posted stock';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'stock_post_not_authorized' THEN RAISE; END IF;
 END;
END $$;
ROLLBACK;

-- No anonymous access to views or privileged RPC entry points.
BEGIN;
SET LOCAL ROLE anon;
DO $$
BEGIN
 BEGIN
  PERFORM c10_demo.transfer_stock_v1(5001,5002,8001,1,'anon-transfer');
  RAISE EXCEPTION 'anon executed transfer';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM count(*) FROM c10_demo.stock_balances_v1;
  RAISE EXCEPTION 'anon read stock balance';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
ROLLBACK;
\echo PASS: inventory reconciliation, transfer zero-sum, balance guards, retries, role isolation, direct-write denial.
\echo LIMIT: disposable PG and synthetic identities only. No signed HTTP, cost valuation, actual stock migration or concurrency stress certification.
