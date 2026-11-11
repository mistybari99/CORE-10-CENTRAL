\set ON_ERROR_STOP on
\echo CORE10 A030 Cost and configurable Tax Preview: real SQL/RLS and accounting math
INSERT INTO c10_demo.items(id,tenant_id,business_id,sku)
VALUES(8003,1,101,'RAW-FLOUR');

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
DO $$
DECLARE s1 bigint;s2 bigint;p1 bigint;r1 bigint;r2 bigint;t1 bigint;t2 bigint;
BEGIN
 PERFORM c10_demo.post_stock_event(5001,8001,10,'cost-preview-stock-10');
 s1:=c10_demo.create_operational_document_v1(
  101,5001,'sale','Customer One',
  '[{"item":8001,"quantity":2,"unit_price":100}]'::jsonb,
  20,'tax-sales-001');
 PERFORM c10_demo.confirm_operational_document_v1(s1);
 PERFORM c10_demo.post_operational_document_v1(s1);
 p1:=c10_demo.create_operational_document_v1(
  101,5001,'purchase','Raw Supplier',
  '[{"item":8003,"quantity":5,"unit_price":10}]'::jsonb,
  0,'cost-raw-purchase');
 PERFORM c10_demo.confirm_operational_document_v1(p1);
 PERFORM c10_demo.post_operational_document_v1(p1);
 s2:=c10_demo.create_operational_document_v1(
  101,5001,'sale','Customer Two',
  '[{"item":8003,"quantity":1,"unit_price":100}]'::jsonb,
  0,'tax-sales-002');
 PERFORM c10_demo.confirm_operational_document_v1(s2);
 PERFORM c10_demo.post_operational_document_v1(s2);

 -- Without pricing, every estimate explicitly reports missing cost rate.
 IF (SELECT count(*) FROM c10_demo.posted_sales_cost_preview_v1
    WHERE missing_cost_rate_lines=1 AND estimated_gross_margin IS NULL)<>2 THEN
  RAISE EXCEPTION 'uncosted stock falsely reported profit'; END IF;

 r1:=c10_demo.create_cost_rate_v1(101,8001,40,'unit-cost-8001');
 IF r1<>c10_demo.create_cost_rate_v1(101,8001,40,'unit-cost-8001') THEN
  RAISE EXCEPTION 'cost rate idempotency failed'; END IF;
 BEGIN
  PERFORM c10_demo.create_cost_rate_v1(101,8001,60,'unit-cost-8001');
  RAISE EXCEPTION 'mutated cost reused idempotency key';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'cost_rate_idempotency_conflict' THEN RAISE; END IF;
 END;
 PERFORM c10_demo.approve_cost_rate_v1(r1);
 IF (SELECT estimated_cogs FROM c10_demo.posted_sales_cost_preview_v1
   WHERE document_id=s1)<>80 OR
    (SELECT estimated_gross_margin FROM c10_demo.posted_sales_cost_preview_v1
     WHERE document_id=s1)<>100 OR
    (SELECT estimated_gross_margin FROM c10_demo.posted_sales_cost_preview_v1
     WHERE document_id=s2) IS NOT NULL THEN
  RAISE EXCEPTION 'manual cost estimate/partial coverage wrong'; END IF;
 r2:=c10_demo.create_cost_rate_v1(101,8003,20,'unit-cost-8003');
 PERFORM c10_demo.approve_cost_rate_v1(r2);
 IF (SELECT estimated_cogs_known_only FROM c10_demo.owner_cost_tax_summary_v1
   WHERE business_id=101)<>100 OR
    (SELECT estimated_margin_when_fully_costed FROM c10_demo.owner_cost_tax_summary_v1
     WHERE business_id=101)<>180 OR
    (SELECT posted_sales_unreconciled FROM c10_demo.owner_cost_tax_summary_v1
     WHERE business_id=101)<>280 OR
    (SELECT estimated_stock_value FROM c10_demo.inventory_value_preview_v1
     WHERE business_id=101)<>400 OR
    (SELECT unpriced_stock_skus FROM c10_demo.inventory_value_preview_v1
     WHERE business_id=101)<>0 THEN
  RAISE EXCEPTION 'business sales/stock estimated COGS did not reconcile'; END IF;
 BEGIN
  PERFORM c10_demo.create_cost_rate_v1(102,8001,30,'foreign-item-rate');
  RAISE EXCEPTION 'cost price linked item from sibling business';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'cost_item_scope_denied' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM c10_demo.create_cost_rate_v1(201,9001,30,'foreign-customer-rate');
  RAISE EXCEPTION 'owner wrote independent customer cost';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'cost_rate_owner_denied' THEN RAISE; END IF;
 END;
 t1:=c10_demo.create_tax_preview_profile_v1(
  101,'Owner Manual Tax Preview',1500,'inclusive','tax-inclusive-v1');
 IF t1<>c10_demo.create_tax_preview_profile_v1(
  101,'Owner Manual Tax Preview',1500,'inclusive','tax-inclusive-v1') THEN
  RAISE EXCEPTION 'tax profile replay not idempotent'; END IF;
 PERFORM c10_demo.approve_tax_preview_profile_v1(t1);
 IF (SELECT estimated_tax_amount FROM c10_demo.posted_sale_tax_preview_v1
   WHERE document_id=s1)<>23.48 OR
    (SELECT estimated_tax_amount FROM c10_demo.posted_sale_tax_preview_v1
     WHERE document_id=s2)<>13.04 OR
    (SELECT estimated_tax_known_only FROM c10_demo.owner_cost_tax_summary_v1
     WHERE business_id=101)<>36.52 THEN
  RAISE EXCEPTION 'inclusive tax preview did not use discounted sale amount'; END IF;
 t2:=c10_demo.create_tax_preview_profile_v1(
  101,'Alternative Exclusive Preview',1000,'exclusive','tax-exclusive-draft');
 BEGIN
  PERFORM c10_demo.approve_tax_preview_profile_v1(t2);
  RAISE EXCEPTION 'two approved tax modes allowed at same time';
 EXCEPTION WHEN unique_violation THEN NULL; END;
 IF (SELECT status FROM c10_demo.tax_preview_profiles_v1 WHERE id=t2)<>'draft' THEN
  RAISE EXCEPTION 'failed second tax approval persisted'; END IF;
 IF EXISTS(SELECT 1 FROM c10_demo.owner_cost_tax_summary_v1
    WHERE legally_or_financially_certified OR missing_cost_lines>0 OR
      posted_sales_without_tax_profile>0) THEN
  RAISE EXCEPTION 'financial certification/coverage flag broken'; END IF;
 IF EXISTS(SELECT 1 FROM c10_demo.posted_sales_cost_preview_v1
   WHERE actual_cogs_certified) OR
   EXISTS(SELECT 1 FROM c10_demo.posted_sale_tax_preview_v1
   WHERE tax_filing_certified) THEN
  RAISE EXCEPTION 'manual input falsely certified real COGS or VAT'; END IF;
END $$;
COMMIT;

-- Direct rate editing and tax profile editing must fail with table ACLs.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
DO $$
BEGIN
 BEGIN
  UPDATE c10_demo.item_cost_rates_v1 SET unit_cost=0 WHERE business_id=101;
  RAISE EXCEPTION 'owner bypassed cost approval';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  UPDATE c10_demo.tax_preview_profiles_v1 SET rate_bps=0 WHERE business_id=101;
  RAISE EXCEPTION 'owner bypassed tax approval';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
ROLLBACK;

-- Other business manager and unauthorized business identities have zero access.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',true);
DO $$
BEGIN
 IF EXISTS(SELECT 1 FROM c10_demo.item_cost_rates_v1) OR
    EXISTS(SELECT 1 FROM c10_demo.posted_sales_cost_preview_v1) OR
    EXISTS(SELECT 1 FROM c10_demo.posted_sale_tax_preview_v1) THEN
  RAISE EXCEPTION 'manager saw owner-only cost/tax'; END IF;
 BEGIN
  PERFORM c10_demo.create_tax_preview_profile_v1(
   101,'Fake Owner Tax',0,'exclusive','manager-fake-tax');
  RAISE EXCEPTION 'manager created tax policy';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'tax_profile_owner_denied' THEN RAISE; END IF;
 END;
END $$;
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','77777777-7777-4777-8777-777777777777',true);
DO $$
BEGIN
 IF EXISTS(SELECT 1 FROM c10_demo.owner_cost_tax_summary_v1 WHERE tenant_id=1)
 OR EXISTS(SELECT 1 FROM c10_demo.posted_sales_cost_preview_v1 WHERE business_id=101)
 OR EXISTS(SELECT 1 FROM c10_demo.tax_preview_profiles_v1 WHERE tenant_id=1) THEN
  RAISE EXCEPTION 'other tenant sees owner manual costs/tax'; END IF;
END $$;
COMMIT;
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','55555555-5555-4555-8555-555555555555',true);
DO $$
BEGIN
 IF EXISTS(SELECT 1 FROM c10_demo.item_cost_rates_v1) OR
    EXISTS(SELECT 1 FROM c10_demo.owner_cost_tax_summary_v1) THEN
   RAISE EXCEPTION 'investor saw owner cost/tax models'; END IF;
END $$;
COMMIT;
BEGIN;
SET LOCAL ROLE anon;
DO $$
BEGIN
 BEGIN
  PERFORM 1 FROM c10_demo.owner_cost_tax_summary_v1;
  RAISE EXCEPTION 'anonymous saw cost/tax summary';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
ROLLBACK;
\echo PASS: owner-approved manual cost estimates + inclusive tax preview, missing-cost fail-closed, tenant/roles, no direct updates.
\echo LIMIT: no actual accounting COGS, inventory FIFO, VAT schedule/filing, legal tax rates, historical price versioning or real POS integration.
