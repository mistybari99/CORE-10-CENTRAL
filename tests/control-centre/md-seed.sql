-- Synthetic master data for the Master Data browser test (disposable database, committed). Uses the real 0151 writers.
\set ON_ERROR_STOP on
INSERT INTO core10.templates(code,source_status,demo_allowed) VALUES ('sweets_bakery','available',true) ON CONFLICT (code) DO NOTHING;
INSERT INTO core10.tenants(id,slug) VALUES (931,'md-a'),(932,'md-b');
INSERT INTO core10.legal_entities(id,tenant_id,label) VALUES (9310,931,'MD Demo A'),(9320,932,'MD Demo B');
INSERT INTO core10.businesses(id,tenant_id,legal_entity_id,slug,template_code,request_key)
 VALUES (9311,931,9310,'md-sweets','sweets_bakery','md-seed-a'),(9321,932,9320,'md-other','sweets_bakery','md-seed-b');
INSERT INTO core10.tenant_members(tenant_id,user_id,role) VALUES
 (931,'c1111111-1111-4111-8111-111111111111','tenant_owner'),(932,'c6666666-6666-4666-8666-666666666666','tenant_owner');
INSERT INTO core10.business_members(tenant_id,business_id,user_id,role) VALUES (931,9311,'c3333333-3333-4333-8333-333333333333','manager');
SET ROLE authenticated;
SELECT set_config('request.jwt.claims','{"sub":"c1111111-1111-4111-8111-111111111111"}',false);
SELECT core10.master_save_uom_v1(9311,'PCS','Piece','পিস','count',0::smallint,true,0,'md-seed-uom-pcs') pcs \gset
SELECT core10.master_save_uom_v1(9311,'BOX','Box of 12','বাক্স','count',0::smallint,true,0,'md-seed-uom-box') box \gset
SELECT core10.master_save_uom_conversion_v1(9311,:box,:pcs,12,true,0,'md-seed-conv-1');
SELECT core10.master_save_category_v1(9311,'SWEETS','Sweets','মিষ্টি',NULL,true,0,'md-seed-cat-1') cat \gset
SELECT core10.master_save_item_v1(9311,'RASGULLA','Rasgulla','রসগোল্লা','finished_good',:cat,:pcs,'active',0,'md-seed-item-1') ras \gset
SELECT core10.master_save_variant_v1(9311,:ras,'LARGE','Large','বড়','{}',NULL,0,'md-seed-var-1') lg \gset
SELECT core10.master_save_barcode_v1(9311,'8901234567890',:ras,:lg,:pcs,true,0,'md-seed-bc-1');
SELECT core10.master_save_party_v1(9311,'C-001','customer','Walk-in customer','সাধারণ ক্রেতা',NULL,NULL,'active',0,'md-seed-party-1');
SELECT core10.master_save_price_list_v1(9311,'RETAIL','Retail','খুচরা','sales','BDT',NULL,current_date-1,NULL,'active',0,'md-seed-pl-1') pl \gset
SELECT core10.master_save_price_v1(9311,:pl,:ras,:lg,:pcs,0,25,true,0,'md-seed-price-1');
DO $$ BEGIN FOR i IN 1..55 LOOP PERFORM core10.master_save_item_v1(9311,'BULK-'||lpad(i::text,3,'0'),'Bulk item '||i,NULL,'stock',NULL,NULL,'active',0,'md-seed-bulk-'||lpad(i::text,3,'0')); END LOOP; END $$;
RESET ROLE;
