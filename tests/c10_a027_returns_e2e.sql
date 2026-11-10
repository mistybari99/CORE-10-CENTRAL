\set ON_ERROR_STOP on
\echo CORE10 A027 return lifecycle E2E
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
DO $$
DECLARE buy_id bigint;sale_id bigint; ret1 bigint;ret2 bigint;ret3 bigint;pre numeric;
BEGIN
 buy_id:=c10_demo.create_operational_document_v1(101,5001,'purchase','Supplier One',
  '[{"item":8001,"quantity":20,"unit_price":10}]',0,'ret-buy');
 PERFORM c10_demo.confirm_operational_document_v1(buy_id);
 PERFORM c10_demo.post_operational_document_v1(buy_id);
 sale_id:=c10_demo.create_operational_document_v1(101,5001,'sale','Customer One',
  '[{"item":8001,"quantity":12,"unit_price":20}]',0,'ret-sale');
 PERFORM c10_demo.confirm_operational_document_v1(sale_id);
 PERFORM c10_demo.post_operational_document_v1(sale_id);
 IF (SELECT on_hand FROM c10_demo.stock_balances_v1 WHERE location_id=5001 AND item_id=8001)<>8
 THEN RAISE EXCEPTION 'setup stock incorrect'; END IF;
 ret1:=c10_demo.create_operational_return_v1(sale_id,
  '[{"line_no":1,"quantity":7}]','Customer damaged package','ret-sale-7');
 IF ret1<>c10_demo.create_operational_return_v1(sale_id,
  '[{"line_no":1,"quantity":7}]','Customer damaged package','ret-sale-7')
 THEN RAISE EXCEPTION 'return retry changed ID'; END IF;
 BEGIN
  PERFORM c10_demo.post_operational_return_v1(ret1);
  RAISE EXCEPTION 'draft return posted';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'return_not_approved' THEN RAISE; END IF;
 END;
 PERFORM c10_demo.approve_operational_return_v1(ret1);
 PERFORM c10_demo.post_operational_return_v1(ret1);
 PERFORM c10_demo.post_operational_return_v1(ret1);
 IF (SELECT on_hand FROM c10_demo.stock_balances_v1 WHERE location_id=5001 AND item_id=8001)<>15
 THEN RAISE EXCEPTION 'sales return was not exactly once'; END IF;
 ret2:=c10_demo.create_operational_return_v1(sale_id,
  '[{"line_no":1,"quantity":6}]','Customer later return','ret-sale-6');
 PERFORM c10_demo.approve_operational_return_v1(ret2);
 BEGIN
  PERFORM c10_demo.post_operational_return_v1(ret2);
  RAISE EXCEPTION 'over-return allowed';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'return_exceeds_original_quantity' THEN RAISE; END IF;
 END;
 IF (SELECT on_hand FROM c10_demo.stock_balances_v1 WHERE location_id=5001 AND item_id=8001)<>15 OR
    (SELECT status FROM c10_demo.operational_returns_v1 WHERE id=ret2)<>'approved' THEN
  RAISE EXCEPTION 'over-return changed stock or state'; END IF;
 ret3:=c10_demo.create_operational_return_v1(buy_id,
  '[{"line_no":1,"quantity":10}]','Supplier defective delivery','ret-buy-10');
 PERFORM c10_demo.approve_operational_return_v1(ret3);
 PERFORM c10_demo.post_operational_return_v1(ret3);
 IF (SELECT on_hand FROM c10_demo.stock_balances_v1 WHERE location_id=5001 AND item_id=8001)<>5
 THEN RAISE EXCEPTION 'purchase return stock not deducted'; END IF;
 IF (SELECT count(*) FROM c10_demo.stock_movements WHERE request_key LIKE 'c10-return:%')<>2 OR
    (SELECT count(*) FROM c10_demo.inventory_reconciliation_v1 WHERE NOT reconciled)<>0 THEN
  RAISE EXCEPTION 'return journal or reconciliation failed'; END IF;
 IF (SELECT count(*) FROM c10_demo.operational_return_report_v1 WHERE business_id=101)<>3 OR
    EXISTS(SELECT 1 FROM c10_demo.operational_return_report_v1 WHERE refund_verified) THEN
  RAISE EXCEPTION 'return report or false refund certification'; END IF;
 BEGIN
  PERFORM c10_demo.create_operational_return_v1(sale_id,
   '[{"line_no":1,"quantity":7}]','Customer damaged package','ret-sale-6');
  RAISE EXCEPTION 'altered request key accepted';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'return_idempotency_conflict' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM c10_demo.create_operational_return_v1(sale_id,
   '[{"line_no":1,"quantity":2},{"line_no":1,"quantity":2}]',
   'Duplicated return lines','dup-return');
  RAISE EXCEPTION 'duplicate lines accepted';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'duplicate_return_line' THEN RAISE; END IF;
 END;
END $$;
COMMIT;
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',true);
DO $$
DECLARE ret bigint;doc bigint;
BEGIN
 SELECT id INTO doc FROM c10_demo.operational_documents_v1 WHERE request_key='ret-sale';
 ret:=c10_demo.create_operational_return_v1(doc,
  '[{"line_no":1,"quantity":1}]','Manager return request','manager-ret');
 BEGIN
  PERFORM c10_demo.approve_operational_return_v1(ret);
  RAISE EXCEPTION 'manager approved own return';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'return_approval_denied' THEN RAISE; END IF;
 END;
 IF EXISTS(SELECT 1 FROM c10_demo.operational_return_report_v1) THEN
  RAISE EXCEPTION 'manager read owner return report'; END IF;
END $$;
COMMIT;
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','77777777-7777-4777-8777-777777777777',true);
DO $$
BEGIN
 IF EXISTS(SELECT 1 FROM c10_demo.operational_returns_v1) OR
    EXISTS(SELECT 1 FROM c10_demo.operational_return_report_v1) THEN
  RAISE EXCEPTION 'customer tenant accessed owner returns'; END IF;
 BEGIN
  PERFORM c10_demo.create_operational_return_v1(
   (SELECT id FROM c10_demo.operational_documents_v1 LIMIT 1),
   '[{"line_no":1,"quantity":1}]','Cross tenant return','customer-foreign');
  RAISE EXCEPTION 'customer forged return';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'return_scope_denied' THEN RAISE; END IF;
 END;
END $$;
COMMIT;
\echo PASS C10 A027 atomic returns and owner-only decisions, no refund claims
