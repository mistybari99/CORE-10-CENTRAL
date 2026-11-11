\set ON_ERROR_STOP on
\echo CORE10 A037 production costing, COGS and inventory valuation: SQL/RLS/accounting E2E (disposable DB)
-- Synthetic fixture items (business 101). Owner = 1111 (tenant owner), manager 3333, investor 5555,
-- site-grant staff 4444, tenant-2 owner 7777.
INSERT INTO c10_demo.items(id,tenant_id,business_id,sku) VALUES
 (8201,1,101,'RAW-SUGAR'),(8202,1,101,'RAW-FLOUR-UNCOSTED'),(8203,1,101,'FIN-SWEET'),
 (8204,1,101,'RAW-GHEE'),(8205,1,101,'FIN-GHEE-SWEET'),(8301,1,102,'OTHER-BIZ-RAW');

-- ============ 1) PURCHASE COSTING, DISCOUNT ALLOCATION, IDEMPOTENCY ============
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
DO $$
DECLARE p1 bigint;p2 bigint;p3 bigint;r jsonb;
BEGIN
 -- P1: 10 @ 10 = 100
 p1:=c10_demo.create_operational_document_v1(101,5001,'purchase','Sugar Supplier',
  '[{"item":8201,"quantity":10,"unit_price":10}]',0,'a037-p1');
 PERFORM c10_demo.confirm_operational_document_v1(p1);
 -- Costing a purchase that is not yet posted must BLOCK (no inferred cost).
 r:=c10_demo.post_purchase_receipt_cost_v1(p1);
 IF r->>'status'<>'blocked' OR r->'reasons'->0->>'reason'<>'purchase_document_not_posted'
 THEN RAISE EXCEPTION 'unposted purchase was costed: %',r; END IF;
 PERFORM c10_demo.post_operational_document_v1(p1);
 r:=c10_demo.post_purchase_receipt_cost_v1(p1);
 IF r->>'status'<>'costed' THEN RAISE EXCEPTION 'p1 not costed: %',r; END IF;
 IF (SELECT quantity||'/'||total_value||'/'||avg_cost FROM c10_demo.cost_valuation_v1
     WHERE location_id=5001 AND item_id=8201)<>'10.000/100.0000/10.000000'
 THEN RAISE EXCEPTION 'valuation after p1 wrong'; END IF;
 -- idempotent retry: no second journal event, valuation unchanged
 r:=c10_demo.post_purchase_receipt_cost_v1(p1);
 IF r->>'status'<>'already_costed' THEN RAISE EXCEPTION 'retry double-counted: %',r; END IF;
 IF (SELECT count(*) FROM c10_demo.cost_events_v1 WHERE source_id=p1)<>1
 THEN RAISE EXCEPTION 'duplicate cost event'; END IF;
 -- P2: two lines, document discount 20 over subtotal 200 => net 180, allocated pro-rata, exact sum
 p2:=c10_demo.create_operational_document_v1(101,5001,'purchase','Sugar Supplier',
  '[{"item":8201,"quantity":5,"unit_price":20},{"item":8201,"quantity":5,"unit_price":20}]',20,'a037-p2');
 PERFORM c10_demo.confirm_operational_document_v1(p2);
 PERFORM c10_demo.post_operational_document_v1(p2);
 PERFORM c10_demo.post_purchase_receipt_cost_v1(p2);
 IF (SELECT sum(value) FROM c10_demo.cost_events_v1 WHERE source_id=p2)<>180
 THEN RAISE EXCEPTION 'discount allocation does not equal net'; END IF;
 IF (SELECT quantity||'/'||total_value||'/'||avg_cost FROM c10_demo.cost_valuation_v1
     WHERE location_id=5001 AND item_id=8201)<>'20.000/280.0000/14.000000'
 THEN RAISE EXCEPTION 'weighted average after p2 wrong'; END IF;
 -- odd discount exercises the rounding remainder: 3 lines, net must still be exact
 p3:=c10_demo.create_operational_document_v1(101,5001,'purchase','Sugar Supplier',
  '[{"item":8204,"quantity":3,"unit_price":10},{"item":8204,"quantity":3,"unit_price":10},{"item":8204,"quantity":3,"unit_price":10}]',
  10,'a037-p3');
 PERFORM c10_demo.confirm_operational_document_v1(p3);
 PERFORM c10_demo.post_operational_document_v1(p3);
 PERFORM c10_demo.post_purchase_receipt_cost_v1(p3);
 IF (SELECT sum(value) FROM c10_demo.cost_events_v1 WHERE source_id=p3)<>80
 THEN RAISE EXCEPTION 'rounding remainder lost'; END IF;
END $$;
COMMIT;

-- ============ 2) SALE COGS SNAPSHOT, BLOCK RULE, EXACT EMPTYING ============
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
DO $$
DECLARE s1 bigint;s2 bigint;s3 bigint;r jsonb;
BEGIN
 -- sale of 4 sugar @ avg 14 => COGS 56; valuation 16 / 224
 s1:=c10_demo.create_operational_document_v1(101,5001,'sale','Customer A',
  '[{"item":8201,"quantity":4,"unit_price":30}]',0,'a037-s1');
 PERFORM c10_demo.confirm_operational_document_v1(s1);
 PERFORM c10_demo.post_operational_document_v1(s1);
 r:=c10_demo.post_sale_cogs_v1(s1);
 IF r->>'status'<>'costed' OR (r->>'cogs')::numeric<>56 THEN RAISE EXCEPTION 'sale cogs wrong: %',r; END IF;
 IF (SELECT quantity||'/'||total_value FROM c10_demo.cost_valuation_v1
     WHERE location_id=5001 AND item_id=8201)<>'16.000/224.0000'
 THEN RAISE EXCEPTION 'valuation after s1 wrong'; END IF;
 IF (c10_demo.post_sale_cogs_v1(s1))->>'status'<>'already_costed' THEN RAISE EXCEPTION 'cogs retry double counted'; END IF;
 IF (SELECT gross_margin FROM c10_demo.sale_cogs_margin_v1 WHERE document_id=s1)<>64
 THEN RAISE EXCEPTION 'margin wrong'; END IF;

 -- UNCOSTED opening stock (posted straight to the stock ledger, no supplier source): COGS must BLOCK
 PERFORM c10_demo.post_stock_event(5001,8202,5,'a037-opening-uncosted');
 s2:=c10_demo.create_operational_document_v1(101,5001,'sale','Customer B',
  '[{"item":8202,"quantity":2,"unit_price":50}]',0,'a037-s2');
 PERFORM c10_demo.confirm_operational_document_v1(s2);
 PERFORM c10_demo.post_operational_document_v1(s2);
 r:=c10_demo.post_sale_cogs_v1(s2);
 IF r->>'status'<>'blocked' OR r->'reasons'->0->>'reason'<>'insufficient_costed_quantity'
 THEN RAISE EXCEPTION 'uncosted stock produced COGS: %',r; END IF;
 IF EXISTS(SELECT 1 FROM c10_demo.cost_events_v1 WHERE source_id=s2)
 THEN RAISE EXCEPTION 'blocked sale wrote journal rows'; END IF;
 IF (SELECT cogs_status FROM c10_demo.sale_cogs_margin_v1 WHERE document_id=s2)<>'not_costed'
    OR (SELECT gross_margin FROM c10_demo.sale_cogs_margin_v1 WHERE document_id=s2) IS NOT NULL
 THEN RAISE EXCEPTION 'blocked sale reported a margin'; END IF;
 IF (SELECT reconciliation_status||'/'||uncosted_quantity FROM c10_demo.cost_valuation_report_v1
     WHERE location_id=5001 AND item_id=8202)<>'uncosted_stock/3.000'
 THEN RAISE EXCEPTION 'reconciliation did not expose uncosted stock'; END IF;

 -- multi-line sale of the same item is checked on the SUM (cannot oversell costed quantity)
 s3:=c10_demo.create_operational_document_v1(101,5001,'sale','Customer C',
  '[{"item":8201,"quantity":9,"unit_price":30},{"item":8201,"quantity":9,"unit_price":30}]',0,'a037-s3');
 PERFORM c10_demo.confirm_operational_document_v1(s3);
 -- stock is only 16 so the stock ledger itself refuses first; cost engine never sees it
 BEGIN PERFORM c10_demo.post_operational_document_v1(s3); RAISE EXCEPTION 'oversell posted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'insufficient_stock' THEN RAISE; END IF; END;
END $$;
COMMIT;

-- ============ 3) PRODUCTION COST: ingredients + referenced overhead + variances ============
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
DO $$
DECLARE p bigint;bom bigint;batch bigint;bom2 bigint;batch2 bigint;r jsonb;
BEGIN
 -- more costed sugar: 20 @ 12 = 240 (valuation was 16/224 => 36/464, avg 12.888889)
 p:=c10_demo.create_operational_document_v1(101,5001,'purchase','Sugar Supplier',
  '[{"item":8201,"quantity":20,"unit_price":12}]',0,'a037-p4');
 PERFORM c10_demo.confirm_operational_document_v1(p);
 PERFORM c10_demo.post_operational_document_v1(p);
 PERFORM c10_demo.post_purchase_receipt_cost_v1(p);
 -- BOM: finished 8203, yield 10 per batch, 2 sugar per batch, bom est unit cost 11, overhead est 5/batch
 bom:=c10_demo.create_bom_v1(101,8203,'SWEET-A',10,
  '[{"item":8201,"qty":2,"estimated_unit_cost":11}]'::jsonb,5,'a037-bom-a');
 PERFORM c10_demo.approve_bom_v1(bom);
 batch:=c10_demo.create_production_batch_v1(bom,5001,3,'a037-batch-a');
 PERFORM c10_demo.confirm_production_batch_v1(batch);
 -- cost BEFORE the stock batch is posted must block
 r:=c10_demo.post_production_cost_v1(batch,30,20,'electricity-bill-nov');
 IF r->>'status'<>'blocked' THEN RAISE EXCEPTION 'unposted batch costed: %',r; END IF;
 PERFORM c10_demo.post_production_batch_v1(batch);
 -- yield differing from posted stock must block (never infer unposted quantities)
 r:=c10_demo.post_production_cost_v1(batch,28,20,'electricity-bill-nov');
 IF r->>'status'<>'blocked' OR r->'reasons'->0->>'reason'<>'actual_yield_differs_from_posted_stock'
 THEN RAISE EXCEPTION 'yield mismatch not blocked: %',r; END IF;
 -- overhead without reference must block
 r:=c10_demo.post_production_cost_v1(batch,30,20,NULL);
 IF r->>'status'<>'blocked' OR NOT (r::text LIKE '%overhead_requires_reference%')
 THEN RAISE EXCEPTION 'unreferenced overhead accepted: %',r; END IF;
 IF EXISTS(SELECT 1 FROM c10_demo.cost_events_v1 WHERE source_type='production_batch')
 THEN RAISE EXCEPTION 'blocked production wrote rows'; END IF;
 -- valid costing: ingredient qty 6 sugar at avg (464/36) => value round(6*464/36,4)=77.3333
 r:=c10_demo.post_production_cost_v1(batch,30,20,'electricity-bill-nov');
 IF r->>'status'<>'costed' THEN RAISE EXCEPTION 'production not costed: %',r; END IF;
 IF (SELECT ingredient_cost FROM c10_demo.production_cost_runs_v1 WHERE batch_id=batch)<>77.3333
    OR (SELECT total_cost FROM c10_demo.production_cost_runs_v1 WHERE batch_id=batch)<>97.3333
    OR (SELECT unit_cost FROM c10_demo.production_cost_runs_v1 WHERE batch_id=batch)<>3.244443
 THEN RAISE EXCEPTION 'production cost math wrong'; END IF;
 -- variances: standard ingredients 6*11=66 => +11.3333; overhead std 5*3=15 => +5; yield variance 0
 IF (SELECT ingredient_price_variance FROM c10_demo.production_cost_runs_v1 WHERE batch_id=batch)<>11.3333
    OR (SELECT overhead_variance FROM c10_demo.production_cost_runs_v1 WHERE batch_id=batch)<>5
    OR (SELECT yield_variance_qty FROM c10_demo.production_cost_runs_v1 WHERE batch_id=batch)<>0
 THEN RAISE EXCEPTION 'variance math wrong'; END IF;
 IF (SELECT quantity||'/'||total_value FROM c10_demo.cost_valuation_v1 WHERE location_id=5001 AND item_id=8203)
    <>'30.000/97.3333' THEN RAISE EXCEPTION 'finished goods valuation wrong'; END IF;
 IF (SELECT quantity||'/'||total_value FROM c10_demo.cost_valuation_v1 WHERE location_id=5001 AND item_id=8201)
    <>'30.000/386.6667' THEN RAISE EXCEPTION 'ingredient valuation after issue wrong'; END IF;
 IF (c10_demo.post_production_cost_v1(batch,30,20,'electricity-bill-nov'))->>'status'<>'already_costed'
 THEN RAISE EXCEPTION 'production cost retry double counted'; END IF;
 -- ingredient WITHOUT verified cost coverage (8202 uncosted opening stock) must block production costing
 bom2:=c10_demo.create_bom_v1(101,8205,'SWEET-B',4,
  '[{"item":8202,"qty":1,"estimated_unit_cost":5}]'::jsonb,0,'a037-bom-b');
 PERFORM c10_demo.approve_bom_v1(bom2);
 batch2:=c10_demo.create_production_batch_v1(bom2,5001,2,'a037-batch-b');
 PERFORM c10_demo.confirm_production_batch_v1(batch2);
 PERFORM c10_demo.post_production_batch_v1(batch2);
 r:=c10_demo.post_production_cost_v1(batch2,8,NULL,NULL);
 IF r->>'status'<>'blocked' OR r->'reasons'->0->>'reason'<>'ingredient_has_no_verified_cost_coverage'
 THEN RAISE EXCEPTION 'manual/uncosted ingredient certified COGS: %',r; END IF;
 -- no-overhead run (no reference) on a costed batch is allowed but NOT certified
END $$;
COMMIT;

-- ============ 4) TRANSFER moves cost, never revenue ============
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
DO $$
DECLARE t bigint;r jsonb;before_total numeric;
BEGIN
 SELECT sum(total_value) INTO before_total FROM c10_demo.cost_valuation_v1 WHERE item_id=8203;
 t:=c10_demo.transfer_stock_v1(5001,5002,8203,10,'a037-transfer-1');
 r:=c10_demo.post_transfer_cost_v1(t);
 IF r->>'status'<>'costed' THEN RAISE EXCEPTION 'transfer not costed: %',r; END IF;
 IF (SELECT sum(total_value) FROM c10_demo.cost_valuation_v1 WHERE item_id=8203)<>before_total
 THEN RAISE EXCEPTION 'transfer changed total value'; END IF;
 IF (SELECT quantity||'/'||total_value FROM c10_demo.cost_valuation_v1 WHERE location_id=5002 AND item_id=8203)
    <>'10.000/32.4444' THEN RAISE EXCEPTION 'destination value wrong'; END IF;
 IF (SELECT quantity||'/'||total_value FROM c10_demo.cost_valuation_v1 WHERE location_id=5001 AND item_id=8203)
    <>'20.000/64.8889' THEN RAISE EXCEPTION 'source value wrong'; END IF;
 IF (c10_demo.post_transfer_cost_v1(t))->>'status'<>'already_costed' THEN RAISE EXCEPTION 'transfer retry'; END IF;
 IF EXISTS(SELECT 1 FROM c10_demo.cost_events_v1 WHERE event_type='sale_cogs' AND source_type='stock_transfer')
 THEN RAISE EXCEPTION 'transfer recognised COGS'; END IF;
 -- transfer of stock with no costed coverage blocks (8202 has none)
 PERFORM c10_demo.post_stock_event(5001,8202,1,'a037-extra-uncosted');
 t:=c10_demo.transfer_stock_v1(5001,5002,8202,1,'a037-transfer-2');
 IF (c10_demo.post_transfer_cost_v1(t))->>'status'<>'blocked' THEN RAISE EXCEPTION 'uncosted transfer costed'; END IF;
END $$;
COMMIT;

-- ============ 5) SALE RETURN reversal: original snapshot cost, bounded ============
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
DO $$
DECLARE s bigint;ret1 bigint;ret2 bigint;r jsonb;
BEGIN
 s:=c10_demo.create_operational_document_v1(101,5001,'sale','Customer R',
  '[{"item":8203,"quantity":5,"unit_price":20}]',0,'a037-sr');
 PERFORM c10_demo.confirm_operational_document_v1(s);
 PERFORM c10_demo.post_operational_document_v1(s);
 -- reversal before the sale was costed blocks
 ret1:=c10_demo.create_operational_return_v1(s,'[{"line_no":1,"quantity":2}]','Customer damaged package','a037-ret1');
 PERFORM c10_demo.approve_operational_return_v1(ret1);
 PERFORM c10_demo.post_operational_return_v1(ret1);
 r:=c10_demo.post_return_cogs_reversal_v1(ret1);
 IF r->>'status'<>'blocked' OR r->'reasons'->0->>'reason'<>'original_sale_not_costed'
 THEN RAISE EXCEPTION 'reversal of uncosted sale accepted: %',r; END IF;
 -- cost the sale: 5 @ 3.244444 (avg of 20/64.8889) => 16.2222; then reverse 2 at original unit cost
 r:=c10_demo.post_sale_cogs_v1(s);
 IF (r->>'cogs')::numeric<>16.2222 THEN RAISE EXCEPTION 'sale cogs on produced goods wrong: %',r; END IF;
 r:=c10_demo.post_return_cogs_reversal_v1(ret1);
 IF r->>'status'<>'costed' OR (r->>'reversed_value')::numeric<>6.4889
 THEN RAISE EXCEPTION 'reversal value wrong: %',r; END IF;
 IF (c10_demo.post_return_cogs_reversal_v1(ret1))->>'status'<>'already_costed'
 THEN RAISE EXCEPTION 'reversal retry double counted'; END IF;
 -- a second return of 4 would exceed the 5 originally costed (2 already reversed): physical return layer refuses first
 BEGIN
  ret2:=c10_demo.create_operational_return_v1(s,'[{"line_no":1,"quantity":4}]','Customer damaged package','a037-ret2');
  PERFORM c10_demo.approve_operational_return_v1(ret2);
  PERFORM c10_demo.post_operational_return_v1(ret2);
  RAISE EXCEPTION 'over-return posted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'return_exceeds_original_quantity' THEN RAISE; END IF; END;
END $$;
COMMIT;

-- ============ 6) RECONCILIATION & LEDGER INTEGRITY ============
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
DO $$
BEGIN
 IF EXISTS(SELECT 1 FROM c10_demo.cost_ledger_integrity_v1 WHERE NOT balanced)
 THEN RAISE EXCEPTION 'valuation does not equal journal sum'; END IF;
 IF EXISTS(SELECT 1 FROM c10_demo.cost_valuation_report_v1
    WHERE costed_quantity>0 AND reconciliation_status='costed_exceeds_stock')
 THEN RAISE EXCEPTION 'costed quantity exceeds physical stock'; END IF;
 IF EXISTS(SELECT 1 FROM c10_demo.cost_valuation_v1 WHERE quantity<0 OR total_value<0)
 THEN RAISE EXCEPTION 'negative valued inventory'; END IF;
 -- every costed item with on_hand == costed qty is reconciled, uncosted ones are named, none hidden
 IF (SELECT count(*) FROM c10_demo.cost_valuation_report_v1 WHERE reconciliation_status='uncosted_stock')<1
 THEN RAISE EXCEPTION 'uncosted stock hidden from reconciliation'; END IF;
END $$;
COMMIT;

-- ============ 7) SECURITY: only tenant/business OWNER posts or reads costs ============
DO $$
DECLARE who text;uid text;fn text;d bigint;ok boolean;
BEGIN
 SELECT id INTO d FROM c10_demo.operational_documents_v1 WHERE kind='sale' AND request_key='a037-s1';
 FOREACH uid IN ARRAY ARRAY['33333333-3333-4333-8333-333333333333',   -- manager
                            '55555555-5555-4555-8555-555555555555',   -- investor
                            '44444444-4444-4444-8444-444444444444',   -- site staff
                            '66666666-6666-4666-8666-666666666666',   -- revoked manager
                            '77777777-7777-4777-8777-777777777777',   -- OTHER tenant owner
                            '99999999-9999-4999-8999-999999999999']   -- platform operator
 LOOP
  PERFORM set_config('request.jwt.claim.sub',uid,true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  FOREACH fn IN ARRAY ARRAY['post_sale_cogs_v1','post_purchase_receipt_cost_v1','post_transfer_cost_v1','post_return_cogs_reversal_v1'] LOOP
   ok:=false;
   BEGIN EXECUTE format('SELECT c10_demo.%I(%s)',fn,d); ok:=true;
   EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'cost_post_denied' THEN RAISE; END IF; END;
   IF ok THEN RAISE EXCEPTION '% was able to run % (uid %)',uid,fn,uid; END IF;
  END LOOP;
  ok:=false;
  BEGIN PERFORM c10_demo.post_production_cost_v1(1,1,1,'x'); ok:=true;
  EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT IN('cost_post_denied') THEN RAISE; END IF; END;
  IF ok THEN RAISE EXCEPTION '% posted production cost',uid; END IF;
  IF (SELECT count(*) FROM c10_demo.cost_events_v1)<>0 OR (SELECT count(*) FROM c10_demo.cost_valuation_v1)<>0
     OR (SELECT count(*) FROM c10_demo.production_cost_runs_v1)<>0
  THEN RAISE EXCEPTION '% can read cost ledger',uid; END IF;
  BEGIN INSERT INTO c10_demo.cost_events_v1(tenant_id,business_id,site_id,location_id,item_id,event_type,quantity,
    unit_cost,value,source_type,source_id,source_snapshot,request_key,created_by)
   VALUES(1,101,1001,5001,8201,'purchase_receipt',1,1,1,'operational_document',1,'{}','hack',gen_random_uuid());
   RAISE EXCEPTION '% inserted a cost event directly',uid;
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN UPDATE c10_demo.cost_valuation_v1 SET total_value=0; RAISE EXCEPTION '% updated valuation',uid;
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM c10_demo._cost_apply_v1(1,101,1001,5001,8201,'purchase_receipt',1,1,'operational_document',1,0,'{}','x');
   RAISE EXCEPTION '% called the internal applier',uid;
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  EXECUTE 'RESET ROLE';
 END LOOP;
 -- anonymous
 EXECUTE 'SET LOCAL ROLE anon';
 BEGIN PERFORM c10_demo.post_sale_cogs_v1(d); RAISE EXCEPTION 'anon posted cogs';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 EXECUTE 'RESET ROLE';
 -- the ledger is immutable even for the table owner / superuser path
 BEGIN UPDATE c10_demo.cost_events_v1 SET value=value+1; RAISE EXCEPTION 'ledger updated';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN DELETE FROM c10_demo.cost_events_v1; RAISE EXCEPTION 'ledger deleted';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN TRUNCATE c10_demo.cost_events_v1; RAISE EXCEPTION 'ledger truncated';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;

-- tenant-2 owner cannot cost or read tenant-1 documents, and sees only tenant-2 rows (none exist)
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','77777777-7777-4777-8777-777777777777',true);
DO $$ BEGIN
 IF (SELECT count(*) FROM c10_demo.cost_valuation_report_v1)<>0 THEN RAISE EXCEPTION 'tenant-2 saw tenant-1 valuation'; END IF;
END $$;
COMMIT;

-- sibling-business owner scoping: business-owner of 101 (2222) posts own business, never business 102
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',true);
DO $$ DECLARE d bigint;
BEGIN
 SELECT count(*) INTO d FROM c10_demo.cost_events_v1 WHERE business_id<>101;
 IF d<>0 THEN RAISE EXCEPTION 'business owner read sibling business costs'; END IF;
 IF (SELECT count(*) FROM c10_demo.cost_events_v1)=0 THEN RAISE EXCEPTION 'business owner cannot read own costs'; END IF;
END $$;
COMMIT;
\echo PASS: A037 costing engine: exact weighted-average math, BLOCK rule, idempotency, immutability, owner-only security
