\set ON_ERROR_STOP on
-- Seed for the signed-JWT HTTP test: 20 sugar purchased+costed @10 (value 200); 13 posted, UNCOSTED sales
-- (1 sale of 3 units for the same-document race, 12 sales of 1 unit for the distinct-document race).
INSERT INTO c10_demo.items(id,tenant_id,business_id,sku) VALUES(8201,1,101,'RAW-SUGAR');
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
DO $$
DECLARE p bigint;s bigint;i integer;
BEGIN
 p:=c10_demo.create_operational_document_v1(101,5001,'purchase','Sugar Supplier',
  '[{"item":8201,"quantity":20,"unit_price":10}]',0,'a037rest-purchase');
 PERFORM c10_demo.confirm_operational_document_v1(p);
 PERFORM c10_demo.post_operational_document_v1(p);
 PERFORM c10_demo.post_purchase_receipt_cost_v1(p);
 s:=c10_demo.create_operational_document_v1(101,5001,'sale','Race Customer',
  '[{"item":8201,"quantity":3,"unit_price":30}]',0,'a037rest-sale-same');
 PERFORM c10_demo.confirm_operational_document_v1(s);
 PERFORM c10_demo.post_operational_document_v1(s);
 FOR i IN 1..12 LOOP
  s:=c10_demo.create_operational_document_v1(101,5001,'sale','Race Customer '||i,
   '[{"item":8201,"quantity":1,"unit_price":30}]',0,'a037rest-sale-'||i);
  PERFORM c10_demo.confirm_operational_document_v1(s);
  PERFORM c10_demo.post_operational_document_v1(s);
 END LOOP;
END $$;
COMMIT;
