\set ON_ERROR_STOP on
\echo CORE10 A027+A028 disposable BOM/Batch + returns + recovery-integrity E2E
-- CI-only initial inventory items: production finished cake, secondary ingredient.
INSERT INTO core10.items(id,tenant_id,business_id,sku)
 VALUES(8003,1,101,'FLOUR'),(8004,1,101,'CAKE'),(9002,2,201,'CUSTOMER-CAKE');

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',true);
DO $$
BEGIN
 BEGIN
  PERFORM core10.create_bom_v1(101,8004,'CAKE',5,
   '[{"item":8001,"qty":2,"estimated_unit_cost":40},
     {"item":8003,"qty":1,"estimated_unit_cost":20}]'::jsonb,10,'manager-bom');
  RAISE EXCEPTION 'manager created certified BOM';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'bom_owner_permission_denied' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM core10.create_return_v1(999,'[{"line":1,"quantity":1}]',
   'Invalid original document','manager-invalid-return');
  RAISE EXCEPTION 'manager created return without posted original';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'return_scope_denied' THEN RAISE; END IF;
 END;
END $$;
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
DO $$
DECLARE bom bigint;draft_bom bigint;batch bigint;
 a bigint;b bigint;c bigint;ret bigint;second_ret bigint;remainder bigint;raw bigint;
BEGIN
 bom:=core10.create_bom_v1(101,8004,'CAKE-RECIPE-1',5,
 '[{"item":8001,"qty":2,"estimated_unit_cost":40},
   {"item":8003,"qty":1,"estimated_unit_cost":20}]'::jsonb,10,'cake-bom-v1');
 IF bom<>core10.create_bom_v1(101,8004,'CAKE-RECIPE-1',5,
 '[{"item":8001,"qty":2,"estimated_unit_cost":40},
   {"item":8003,"qty":1,"estimated_unit_cost":20}]'::jsonb,10,'cake-bom-v1')
 THEN RAISE EXCEPTION 'BOM retry not idempotent'; END IF;
 BEGIN
  PERFORM core10.create_bom_v1(101,8004,'CAKE-RECIPE-1',6,
   '[{"item":8001,"qty":3,"estimated_unit_cost":40}]'::jsonb,10,'cake-bom-v1');
  RAISE EXCEPTION 'BOM replay accepted changed recipe';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'bom_idempotency_conflict' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM core10.create_production_batch_v1(bom,5001,2,'batch-before-approval');
  RAISE EXCEPTION 'unapproved BOM used in production';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'bom_not_approved' THEN RAISE; END IF;
 END;
 IF core10.approve_bom_v1(bom)<>'approved' OR
   core10.approve_bom_v1(bom)<>'approved'
 THEN RAISE EXCEPTION 'owner BOM approval failed'; END IF;
 draft_bom:=core10.create_bom_v1(101,8004,'CAKE-RECIPE-2',5,
  '[{"item":8001,"qty":2,"estimated_unit_cost":50}]'::jsonb,10,'cake-bom-v2');
 BEGIN
  PERFORM core10.approve_bom_v1(draft_bom);
  RAISE EXCEPTION 'two approved BOMs for same finished SKU';
 EXCEPTION WHEN unique_violation THEN NULL; END;
 IF (SELECT status FROM core10.bom_recipes_v1 WHERE id=draft_bom)<>'draft' THEN
  RAISE EXCEPTION 'failed BOM approval persisted'; END IF;
 BEGIN
  PERFORM core10.create_bom_v1(101,8004,'FOREIGN-INGREDIENT',5,
   '[{"item":9001,"qty":1,"estimated_unit_cost":50}]'::jsonb,0,'foreign-raw');
  RAISE EXCEPTION 'foreign tenant ingredient accepted';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'invalid_bom_ingredient' THEN RAISE; END IF;
 END;
 batch:=core10.create_production_batch_v1(bom,5001,2,'batch-cake-001');
 IF batch<>core10.create_production_batch_v1(bom,5001,2,'batch-cake-001')
 THEN RAISE EXCEPTION 'batch retry changed ID'; END IF;
 IF (SELECT expected_output FROM core10.production_batches_v1 WHERE id=batch)<>10 OR
    (SELECT estimated_total_cost FROM core10.production_batches_v1 WHERE id=batch)<>220 OR
    (SELECT estimated_cost_per_unit FROM core10.production_cost_estimate_v1
     WHERE batch_id=batch)<>22 THEN
  RAISE EXCEPTION 'planning BOM material cost estimate wrong'; END IF;
 BEGIN
  PERFORM core10.post_production_batch_v1(batch);
  RAISE EXCEPTION 'unconfirmed production batch posted';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'batch_not_confirmed' THEN RAISE; END IF;
 END;
 IF core10.confirm_production_batch_v1(batch)<>'confirmed' THEN
  RAISE EXCEPTION 'owner batch confirmation failed'; END IF;
 BEGIN
  PERFORM core10.post_production_batch_v1(batch);
  RAISE EXCEPTION 'batch posted without raw materials';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'insufficient_stock' THEN RAISE; END IF;
 END;
 IF EXISTS(SELECT 1 FROM core10.stock_movements
   WHERE request_key LIKE 'c10-production:%') OR
   (SELECT status FROM core10.production_batches_v1 WHERE id=batch)<>'confirmed' THEN
  RAISE EXCEPTION 'failed batch left partial stock events'; END IF;
 PERFORM core10.post_stock_event(5001,8001,7,'raw-sweets-7');
 PERFORM core10.post_stock_event(5001,8003,4,'raw-flour-4');
 IF core10.post_production_batch_v1(batch)<>'posted' OR
    core10.post_production_batch_v1(batch)<>'posted' THEN
  RAISE EXCEPTION 'batch did not post exactly once'; END IF;
 IF (SELECT on_hand FROM core10.stock_balances_v1
     WHERE location_id=5001 AND item_id=8001)<>3 OR
    (SELECT on_hand FROM core10.stock_balances_v1
     WHERE location_id=5001 AND item_id=8003)<>2 OR
    (SELECT on_hand FROM core10.stock_balances_v1
     WHERE location_id=5001 AND item_id=8004)<>10 OR
    (SELECT count(*) FROM core10.stock_movements
     WHERE request_key LIKE 'c10-production:%')<>3 THEN
  RAISE EXCEPTION 'production material depletion/output math failed'; END IF;

 -- Finished goods sale: 6 cakes at 100, with 60 discount.
 a:=core10.create_operational_document_v1(101,5001,'sale','Buyer Test',
  '[{"item":8004,"quantity":6,"unit_price":100}]'::jsonb,60,'sale-cake-001');
 PERFORM core10.confirm_operational_document_v1(a);
 PERFORM core10.post_operational_document_v1(a);
 -- Supplier purchase: 5 raw-material units at 10.
 b:=core10.create_operational_document_v1(101,5001,'purchase','Raw Supplier',
  '[{"item":8003,"quantity":5,"unit_price":10}]'::jsonb,0,'raw-purchase-001');
 PERFORM core10.confirm_operational_document_v1(b);
 PERFORM core10.post_operational_document_v1(b);
 IF (SELECT on_hand FROM core10.stock_balances_v1
    WHERE location_id=5001 AND item_id=8004)<>4 THEN
  RAISE EXCEPTION 'sale did not deplete finished stock'; END IF;

 ret:=core10.create_return_v1(a,
  '[{"line":1,"quantity":2}]'::jsonb,'Damaged packaging returned','return-cake-001');
 IF ret<>core10.create_return_v1(a,
  '[{"line":1,"quantity":2}]'::jsonb,'Damaged packaging returned','return-cake-001')
 THEN RAISE EXCEPTION 'return draft retry not idempotent'; END IF;
 IF core10.confirm_return_v1(ret)<>'confirmed' OR
    core10.post_return_v1(ret)<>'posted' OR
    core10.post_return_v1(ret)<>'posted' THEN
  RAISE EXCEPTION 'sale return failed one-time post'; END IF;
 IF (SELECT amount_unsettled FROM core10.return_lines_v1 WHERE return_id=ret)<>180 OR
   (SELECT on_hand FROM core10.stock_balances_v1
    WHERE location_id=5001 AND item_id=8004)<>6 THEN
  RAISE EXCEPTION 'discounted return value or restock wrong'; END IF;
 second_ret:=core10.create_return_v1(a,
  '[{"line":1,"quantity":5}]'::jsonb,'Another claimed cake return','return-cake-over');
 PERFORM core10.confirm_return_v1(second_ret);
 BEGIN
  PERFORM core10.post_return_v1(second_ret);
  RAISE EXCEPTION 'returned more units than original sale';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'return_exceeds_remaining_quantity' THEN RAISE; END IF;
 END;
 IF (SELECT status FROM core10.return_documents_v1 WHERE id=second_ret)<>'confirmed'
 THEN RAISE EXCEPTION 'failed over-return was not atomic'; END IF;
 remainder:=core10.create_return_v1(a,
  '[{"line":1,"quantity":4}]'::jsonb,'Remaining cake items returned','return-cake-remaining');
 PERFORM core10.confirm_return_v1(remainder);
 PERFORM core10.post_return_v1(remainder);
 IF (SELECT on_hand FROM core10.stock_balances_v1
    WHERE location_id=5001 AND item_id=8004)<>10 THEN
  RAISE EXCEPTION 'all cakes returned without original cap'; END IF;

 raw:=core10.create_return_v1(b,
  '[{"line":1,"quantity":2}]'::jsonb,'Supplier delivered wrong grade','return-flour-001');
 PERFORM core10.confirm_return_v1(raw);
 PERFORM core10.post_return_v1(raw);
 IF (SELECT on_hand FROM core10.stock_balances_v1
     WHERE location_id=5001 AND item_id=8003)<>5 THEN
  RAISE EXCEPTION 'purchase return failed to reverse stock'; END IF;
 IF (SELECT net_sale_value_unreconciled FROM core10.operational_net_returns_v1
     WHERE business_id=101)<>0 OR
    (SELECT net_purchase_value_unreconciled FROM core10.operational_net_returns_v1
     WHERE business_id=101)<>30 OR
    (SELECT actual_refunds_reconciled FROM core10.operational_net_returns_v1
     WHERE business_id=101) THEN
   RAISE EXCEPTION 'sale/purchase net returns report did not net discounts'; END IF;
 IF EXISTS(SELECT 1 FROM core10.inventory_reconciliation_v1
   WHERE NOT reconciled) THEN
  RAISE EXCEPTION 'BOM, sale and returns broke stock ledger consistency'; END IF;
END $$;
COMMIT;

-- Manager cannot post production or returns; can draft under own authorized business.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',true);
DO $$
DECLARE v_bom bigint;v_batch bigint;
BEGIN
 SELECT id INTO v_bom FROM core10.bom_recipes_v1 WHERE recipe_code='CAKE-RECIPE-1';
 v_batch:=core10.create_production_batch_v1(v_bom,5001,1,'manager-draft-batch');
 BEGIN
  PERFORM core10.confirm_production_batch_v1(v_batch);
  RAISE EXCEPTION 'manager confirmed production';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'batch_confirm_denied' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM core10.post_production_batch_v1(v_batch);
  RAISE EXCEPTION 'manager posted production';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'batch_post_denied' THEN RAISE; END IF;
 END;
 IF (SELECT count(*) FROM core10.bom_recipes_v1 WHERE business_id=101)<>2 OR
    EXISTS(SELECT 1 FROM core10.bom_recipes_v1 WHERE business_id=102) THEN
   RAISE EXCEPTION 'manager BOM scope invalid'; END IF;
END $$;
COMMIT;

-- Cross-tenant confidentiality and negative business ID.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','77777777-7777-4777-8777-777777777777',true);
DO $$
BEGIN
 IF EXISTS(SELECT 1 FROM core10.bom_recipes_v1 WHERE tenant_id=1) OR
    EXISTS(SELECT 1 FROM core10.return_documents_v1 WHERE tenant_id=1) OR
    EXISTS(SELECT 1 FROM core10.production_batches_v1 WHERE tenant_id=1) OR
    EXISTS(SELECT 1 FROM core10.operational_net_returns_v1 WHERE tenant_id=1) THEN
   RAISE EXCEPTION 'independent customer read owner production/returns'; END IF;
 BEGIN
  PERFORM core10.create_production_batch_v1(
    1,6001,1,'customer-cross-bom');
  RAISE EXCEPTION 'customer cross-tenant production permitted';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'production_batch_scope_denied' THEN RAISE; END IF;
 END;
END $$;
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',true);
DO $$
BEGIN
 IF EXISTS(SELECT 1 FROM core10.bom_recipes_v1) OR
    EXISTS(SELECT 1 FROM core10.return_documents_v1) OR
    EXISTS(SELECT 1 FROM core10.production_batches_v1) THEN
  RAISE EXCEPTION 'site staff accessed confidential recipes and returns'; END IF;
END $$;
COMMIT;
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','55555555-5555-4555-8555-555555555555',true);
DO $$
BEGIN
 IF EXISTS(SELECT 1 FROM core10.bom_recipes_v1) OR
    EXISTS(SELECT 1 FROM core10.return_documents_v1) OR
    EXISTS(SELECT 1 FROM core10.production_cost_estimate_v1) THEN
  RAISE EXCEPTION 'investor accessed operations or estimated recipe costing'; END IF;
END $$;
COMMIT;
BEGIN;
SET LOCAL ROLE anon;
DO $$
BEGIN
 BEGIN
  PERFORM 1 FROM core10.bom_recipes_v1;
  RAISE EXCEPTION 'anonymous saw BOM';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM core10.post_production_batch_v1(1);
  RAISE EXCEPTION 'anonymous posted production';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
ROLLBACK;
\echo PASS: Owner recipe approval, manager batch drafts, atomic ingredient consumption/output, estimated costing, sale/purchase return cap/discount, cross-tenant and role RLS.
\echo LIMIT: no production FIFO actual COGS, credit note payouts, VAT, lots/batches, physical stock certification, live Supabase Auth/legacy migration.
