\set ON_ERROR_STOP on
\echo CORE10 A026: atomic purchase + sale stock lifecycle and scope security
-- Fixture seed already loaded; no production data.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',true);
DO $$
DECLARE v_doc bigint;
BEGIN
 v_doc:=c10_demo.create_operational_document_v1(
  101,5001,'sale','Customer A',
  '[{"item":8001,"quantity":10,"unit_price":100}]'::jsonb,0,'sale-first');
 IF v_doc<>c10_demo.create_operational_document_v1(
  101,5001,'sale','Customer A',
  '[{"item":8001,"quantity":10,"unit_price":100}]'::jsonb,0,'sale-first')
 THEN RAISE EXCEPTION 'sale draft idempotency failed'; END IF;
 IF (SELECT status FROM c10_demo.operational_documents_v1 WHERE id=v_doc)<>'draft'
 THEN RAISE EXCEPTION 'new sales document bypassed draft'; END IF;
 BEGIN
  PERFORM c10_demo.confirm_operational_document_v1(v_doc);
  RAISE EXCEPTION 'manager confirmed sale';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'operational_confirm_denied' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM c10_demo.post_operational_document_v1(v_doc);
  RAISE EXCEPTION 'manager posted sale';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'operational_post_denied' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM c10_demo.create_operational_document_v1(
   102,5003,'purchase','Cross Business Supplier',
   '[{"item":8002,"quantity":3,"unit_price":25}]'::jsonb,0,'manager-foreign');
  RAISE EXCEPTION 'manager created document for foreign business';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'operational_scope_denied' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM c10_demo.create_operational_document_v1(
   101,5001,'sale','Customer A',
   '[{"item":8001,"quantity":9,"unit_price":100}]'::jsonb,0,'sale-first');
  RAISE EXCEPTION 'mutated sale request reused key';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'operational_request_idempotency_conflict' THEN RAISE; END IF;
 END;
END $$;
COMMIT;
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
DO $$
DECLARE v_sale bigint;v_buy bigint;v_failed bigint;v_second bigint;
BEGIN
 SELECT id INTO v_sale FROM c10_demo.operational_documents_v1
  WHERE business_id=101 AND request_key='sale-first';
 IF c10_demo.confirm_operational_document_v1(v_sale)<>'confirmed' THEN
  RAISE EXCEPTION 'owner did not confirm sales request'; END IF;
 BEGIN
  PERFORM c10_demo.post_operational_document_v1(v_sale);
  RAISE EXCEPTION 'sale allowed negative physical inventory';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'insufficient_stock' THEN RAISE; END IF;
 END;
 IF (SELECT status FROM c10_demo.operational_documents_v1
   WHERE id=v_sale)<>'confirmed' OR
   EXISTS(SELECT 1 FROM c10_demo.stock_movements
    WHERE request_key LIKE 'c10-op:%') THEN
  RAISE EXCEPTION 'failed sale created partial journal'; END IF;
 v_buy:=c10_demo.create_operational_document_v1(101,5001,'purchase',
   'Supplier Sweets','[{"item":8001,"quantity":20,"unit_price":40}]'::jsonb,
   0,'purchase-first');
 IF c10_demo.confirm_operational_document_v1(v_buy)<>'confirmed' OR
   c10_demo.post_operational_document_v1(v_buy)<>'posted' OR
   c10_demo.post_operational_document_v1(v_buy)<>'posted' THEN
  RAISE EXCEPTION 'purchase not exactly once posted'; END IF;
 IF (SELECT on_hand FROM c10_demo.stock_balances_v1
  WHERE location_id=5001 AND item_id=8001)<>20 THEN
  RAISE EXCEPTION 'purchase receipt quantity wrong'; END IF;
 IF c10_demo.post_operational_document_v1(v_sale)<>'posted' OR
   c10_demo.post_operational_document_v1(v_sale)<>'posted' THEN
  RAISE EXCEPTION 'confirmed sale failed to post once'; END IF;
 IF (SELECT on_hand FROM c10_demo.stock_balances_v1
  WHERE location_id=5001 AND item_id=8001)<>10 OR
   (SELECT count(*) FROM c10_demo.stock_movements
    WHERE location_id=5001 AND request_key LIKE 'c10-op:%')<>2 THEN
  RAISE EXCEPTION 'sale deducted twice or was not posted'; END IF;
 v_failed:=c10_demo.create_operational_document_v1(101,5001,'sale',
   'Customer B','[{"item":8001,"quantity":7,"unit_price":100},
                  {"item":8001,"quantity":10,"unit_price":100}]'::jsonb,
   0,'sale-overstock-2-lines');
 PERFORM c10_demo.confirm_operational_document_v1(v_failed);
 BEGIN
  PERFORM c10_demo.post_operational_document_v1(v_failed);
  RAISE EXCEPTION 'multi-line overdraw succeeded';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'insufficient_stock' THEN RAISE; END IF;
 END;
 IF (SELECT on_hand FROM c10_demo.stock_balances_v1
    WHERE location_id=5001 AND item_id=8001)<>10 OR
    (SELECT count(*) FROM c10_demo.stock_movements WHERE request_key LIKE
      'c10-op:'||v_failed||':%')<>0 OR
    (SELECT status FROM c10_demo.operational_documents_v1
     WHERE id=v_failed)<>'confirmed' THEN
   RAISE EXCEPTION 'multi-line rollback did not preserve balance'; END IF;
 v_second:=c10_demo.create_operational_document_v1(102,5003,'purchase',
   'Second Business Supplier',
   '[{"item":8002,"quantity":5,"unit_price":10}]'::jsonb,0,
   'separate-business-purchase');
 PERFORM c10_demo.confirm_operational_document_v1(v_second);
 PERFORM c10_demo.post_operational_document_v1(v_second);
 IF (SELECT posted_sale_docs FROM c10_demo.operational_business_report_v1
   WHERE business_id=101)<>1 OR
   (SELECT posted_sale_value_unreconciled FROM c10_demo.operational_business_report_v1
   WHERE business_id=101)<>1000 OR
   (SELECT received_purchase_value_unreconciled FROM c10_demo.operational_business_report_v1
   WHERE business_id=101)<>800 OR
   (SELECT unposted_documents FROM c10_demo.operational_business_report_v1
    WHERE business_id=101)<>1 OR
   (SELECT posted_sale_docs FROM c10_demo.operational_business_report_v1
    WHERE business_id=102)<>0 THEN
  RAISE EXCEPTION 'posted vs unposted document reporting / double counted transfers'; END IF;
 IF (SELECT count(*) FROM c10_demo.inventory_reconciliation_v1
  WHERE NOT reconciled)<>0 THEN RAISE EXCEPTION 'operation journal reconciliation mismatch'; END IF;
 BEGIN
  PERFORM c10_demo.create_operational_document_v1(
   102,5001,'purchase','Mis-scoped Supplier',
   '[{"item":8001,"quantity":1,"unit_price":1}]'::jsonb,0,'location-biz-mismatch');
  RAISE EXCEPTION 'operation used stock location from a different business';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'operational_scope_denied' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM c10_demo.create_operational_document_v1(
   101,5001,'sale','Customer C',
   '[{"item":8001,"quantity":1,"unit_price":10}]'::jsonb,100,
   'discount-over-subtotal');
  RAISE EXCEPTION 'discount greater than sales total accepted';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'invalid_operational_total' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM c10_demo.create_operational_document_v1(
   101,5001,'sale','Customer C',
   '[{"item":9001,"quantity":1,"unit_price":10}]'::jsonb,0,
   'other-tenant-item');
  RAISE EXCEPTION 'foreign customer item accepted';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'invalid_operational_line' THEN RAISE; END IF;
 END;
END $$;
COMMIT;

-- A physically same SKU transfer must never create purchase or sales revenue.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
SELECT c10_demo.transfer_stock_v1(5001,5002,8001,3,'op-internal-transfer');
DO $$
BEGIN
 IF (SELECT total_units_on_hand FROM c10_demo.business_inventory_report_v1
     WHERE business_id=101)<>10 OR
    (SELECT posted_sale_value_unreconciled FROM c10_demo.operational_business_report_v1
     WHERE business_id=101)<>1000 OR
    (SELECT count(*) FROM c10_demo.inventory_reconciliation_v1
      WHERE NOT reconciled)<>0 THEN
   RAISE EXCEPTION 'internal transfer inflated sale or stock'; END IF;
END $$;
COMMIT;

-- Customer tenant creates own purchase; no access to owner portfolio documents.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','77777777-7777-4777-8777-777777777777',true);
DO $$
DECLARE v_id bigint;
BEGIN
 IF EXISTS(SELECT 1 FROM c10_demo.operational_documents_v1 WHERE tenant_id=1)
 THEN RAISE EXCEPTION 'customer tenant read owner purchase and sale'; END IF;
 v_id:=c10_demo.create_operational_document_v1(
   201,6001,'purchase','Customer Supplier',
   '[{"item":9001,"quantity":3,"unit_price":15}]'::jsonb,0,'customer-purchase');
 PERFORM c10_demo.confirm_operational_document_v1(v_id);
 PERFORM c10_demo.post_operational_document_v1(v_id);
 IF (SELECT count(*) FROM c10_demo.operational_business_report_v1)<>1 OR
    (SELECT received_purchase_value_unreconciled FROM c10_demo.operational_business_report_v1
     WHERE business_id=201)<>45 THEN
  RAISE EXCEPTION 'customer business purchase report scope'; END IF;
 BEGIN
  PERFORM c10_demo.create_operational_document_v1(
    101,5001,'purchase','Cross Tenant Supplier',
    '[{"item":8001,"quantity":1,"unit_price":20}]'::jsonb,0,'cross-tenant-attempt');
  RAISE EXCEPTION 'customer created foreign tenant purchase';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'operational_scope_denied' THEN RAISE; END IF;
 END;
END $$;
COMMIT;

-- Business owner owns only assigned business, manager may view own drafts,
-- investor/staff/operator/revoked cannot see operational documents or ledger.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',true);
DO $$
BEGIN
 IF (SELECT count(*) FROM c10_demo.operational_business_report_v1)<>1 OR
   (SELECT count(*) FROM c10_demo.operational_documents_v1 WHERE business_id=102)<>0 THEN
  RAISE EXCEPTION 'business owner accessed sibling operations'; END IF;
END $$;
COMMIT;
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',true);
DO $$
BEGIN
 IF (SELECT count(*) FROM c10_demo.operational_documents_v1 WHERE business_id=101)<>3 OR
   EXISTS(SELECT 1 FROM c10_demo.operational_documents_v1 WHERE business_id=102) OR
   EXISTS(SELECT 1 FROM c10_demo.operational_business_report_v1) THEN
  RAISE EXCEPTION 'manager operational scope elevated'; END IF;
END $$;
COMMIT;
DO $block$
DECLARE who uuid;
BEGIN
 FOR who IN SELECT unnest(ARRAY[
  '44444444-4444-4444-8444-444444444444'::uuid,
  '55555555-5555-4555-8555-555555555555'::uuid,
  '66666666-6666-4666-8666-666666666666'::uuid,
  '99999999-9999-4999-8999-999999999999'::uuid]) LOOP
  PERFORM set_config('request.jwt.claim.sub',who::text,false);
  EXECUTE 'SET ROLE authenticated';
  IF EXISTS(SELECT 1 FROM c10_demo.operational_documents_v1) OR
    EXISTS(SELECT 1 FROM c10_demo.operational_business_report_v1) THEN
   RAISE EXCEPTION 'staff/investor/revoked/operator saw operations'; END IF;
  EXECUTE 'RESET ROLE';
 END LOOP;
END $block$;
BEGIN;
SET LOCAL ROLE anon;
DO $$
BEGIN
 BEGIN
  PERFORM 1 FROM c10_demo.operational_business_report_v1;
  RAISE EXCEPTION 'anonymous operational reporting visible';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM c10_demo.post_operational_document_v1(1);
  RAISE EXCEPTION 'anonymous operational posting allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
ROLLBACK;
\echo PASS: draft->confirmed->posted, manager submit/owner confirm, atomic rollback, buy+sale stock and retry, internal transfer no sale, RLS company/tenant/role negative cases.
\echo LIMIT: no real invoices, POS income reconciliation, cash capture, COGS, VAT, returns, Supabase Auth or deployment.
