-- Disposable only. Reuse A018 hierarchy and A046 stable persona aliases.
DO $$ BEGIN
 IF current_database() !~ '^core10_np03b_(ci|local)' OR to_regclass('auth.users') IS NOT NULL
 THEN RAISE EXCEPTION 'NP03B_DISPOSABLE_ONLY'; END IF;
END $$;
\ir hierarchy.sql
UPDATE core10.businesses SET template_code='sweets_bakery' WHERE id IN(101,102,201);
INSERT INTO core10.business_members(tenant_id,business_id,user_id,role) VALUES
 (1,102,'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','business_owner'),
 (1,102,'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','manager');
INSERT INTO core10.site_grants(tenant_id,business_id,site_id,user_id,actions) VALUES
 (1,101,1002,'cccccccc-cccc-4ccc-8ccc-cccccccccccc',ARRAY['stock.read']),
 (1,102,1003,'dddddddd-dddd-4ddd-8ddd-dddddddddddd',ARRAY['stock.read']);
-- The unassigned/reviewer/partner/platform UUIDs deliberately have no Sales grant.
-- Actual canonical NP02 Master rows, seeded by the disposable test owner.
-- Never create, replace or drop the real 0151 validation port in this fixture.
DO $$ BEGIN
 IF to_regprocedure('core10.master_validate_sales_order_v1(bigint,bigint,jsonb)') IS NULL
    OR to_regclass('core10.master_price_list_items_v1') IS NULL
 THEN RAISE EXCEPTION 'NP03B_REQUIRES_CANONICAL_MASTER'; END IF;
END $$;

INSERT INTO core10.master_uoms_v1(id,tenant_id,business_id,code,name_en,name_bn,dimension,decimals)
VALUES(7201,1,101,'PACK','Saleable package','বিক্রয়যোগ্য প্যাকেট','count',0),
      (7202,1,101,'KG','Kilogram','কেজি','mass',3);
-- Mixed Sweets 1kg is one prepacked 1kg product here, not an unmeasured bulk sale.
INSERT INTO core10.items(id,tenant_id,business_id,sku,name_en,name_bn,item_kind,base_uom_id,status)
VALUES(8101,1,101,'RASGULLA-BOX','Rasgulla Box','রসগোল্লার বাক্স','finished_good',7201,'active'),
      (8102,1,101,'SANDESH-BOX','Sandesh Box','সন্দেশের বাক্স','finished_good',7201,'active'),
      (8103,1,101,'MIXED-SWEETS-1KG','Mixed Sweets 1kg','মিশ্র মিষ্টি ১ কেজি','finished_good',7201,'active'),
      (8104,1,101,'CHOCOLATE-CAKE','Chocolate Cake','চকলেট কেক','finished_good',7201,'active'),
      (8105,1,101,'BUTTER-COOKIES','Butter Cookies','বাটার কুকিজ','finished_good',7201,'active');
INSERT INTO core10.master_item_variants_v1(id,tenant_id,business_id,item_id,code,name_en,name_bn,status)
SELECT 7301+(i.id-8101),1,101,i.id,'STANDARD','Standard package','সাধারণ প্যাকেট','active'
FROM core10.items i WHERE i.id BETWEEN 8101 AND 8105 AND i.business_id=101;

INSERT INTO core10.master_parties_v1(id,tenant_id,business_id,code,party_kind,name_en,name_bn,status)
VALUES(7001,1,101,'SYNTH-CUSTOMER','customer','Synthetic Bakery Customer','কৃত্রিম বেকারি ক্রেতা','active'),
      (7002,1,101,'SYNTH-SUPPLIER','supplier','Synthetic Supplier','কৃত্রিম সরবরাহকারী','active'),
      (7003,2,201,'SYNTH-CUSTOMER-B','customer','Independent Synthetic Customer','স্বতন্ত্র কৃত্রিম ক্রেতা','active'),
      (7004,1,101,'SYNTH-INACTIVE','customer','Inactive Synthetic Customer','নিষ্ক্রিয় কৃত্রিম ক্রেতা','inactive');
INSERT INTO core10.master_price_lists_v1(id,tenant_id,business_id,code,name_en,name_bn,list_kind,currency,
 site_id,effective_from,effective_to,status)
VALUES(7101,1,101,'SYNTH-RETAIL','Synthetic Retail','কৃত্রিম খুচরা','sales','BDT',NULL,current_date-1,NULL,'active'),
      (7102,1,101,'SYNTH-WHOLESALE','Synthetic Wholesale','কৃত্রিম পাইকারি','sales','BDT',NULL,current_date-1,NULL,'active');
-- Base and item-specific STANDARD variant prices are separately authoritative.
-- A variant belonging to a different item is never accepted by canonical Master.
INSERT INTO core10.master_price_list_items_v1(id,tenant_id,business_id,price_list_id,item_id,variant_id,uom_id,
 min_quantity,unit_price,active)
SELECT 7401+(p.id-8101)*4+(l.id-7101)*2+v.offset_id,
       1,101,l.id,p.id,CASE WHEN v.offset_id=1 THEN 7301+(p.id-8101) END,
       7201,0,p.price*CASE WHEN l.id=7102 THEN .9 ELSE 1 END,true
FROM (VALUES(8101,300),(8102,420),(8103,850),(8104,1200),(8105,250)) p(id,price)
CROSS JOIN (VALUES(7101),(7102)) l(id)
CROSS JOIN (VALUES(0),(1)) v(offset_id);
-- Synthetic assumptions ONLY: BDT, tax=0 in Sales examples, retail/90% wholesale;
-- all five products are priced per saleable package. Prices are illustrative,
-- not statutory tax/legal policy. Relative dates track the disposable DB test day.
-- These are real canonical customer/catalog fixture rows, never hosted Auth users,
-- actual customers, payment records or production data. No identity sequences reset.
