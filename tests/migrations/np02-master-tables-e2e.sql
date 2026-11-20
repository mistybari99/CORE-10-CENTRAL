-- B-011 / 0150: Master tables — scope, isolation, constraints and grant negatives (disposable PG17).
-- Runs inside one transaction and rolls back. Each negative must raise; a silent success fails the test.
\set ON_ERROR_STOP 1
BEGIN;
INSERT INTO core10.tenants(id,slug) VALUES (9701,'mst-a'),(9702,'mst-b');
INSERT INTO core10.legal_entities(id,tenant_id,label) VALUES (97001,9701,'A'),(97002,9702,'B');
INSERT INTO core10.businesses(id,tenant_id,legal_entity_id,slug,template_code,request_key)
 VALUES (97101,9701,97001,'mst-sweets','sweets_bakery','mst-a'),(97102,9702,97002,'mst-other','restaurant','mst-b');

-- pre-existing item rows (0002 shape) stay valid with defaults
INSERT INTO core10.items(id,tenant_id,business_id,sku) VALUES (97201,9701,97101,'LEGACY-1');
DO $$ BEGIN
 IF (SELECT status||'/'||item_kind||'/'||version FROM core10.items WHERE id=97201) <> 'active/stock/1'
 THEN RAISE EXCEPTION 'item defaults wrong'; END IF; END $$;

INSERT INTO core10.master_uoms_v1(id,tenant_id,business_id,code,name_en,name_bn,dimension,decimals) VALUES
 (97301,9701,97101,'PCS','Piece','পিস','count',0),(97302,9701,97101,'BOX','Box of 12',NULL,'count',0),
 (97303,9701,97101,'KG','Kilogram','কেজি','mass',3),(97304,9701,97101,'G','Gram',NULL,'mass',0),
 (97305,9702,97102,'PCS','Piece',NULL,'count',0);
INSERT INTO core10.master_uom_conversions_v1(tenant_id,business_id,dimension,from_uom_id,to_uom_id,factor)
 VALUES (9701,97101,'count',97302,97301,12),(9701,97101,'mass',97303,97304,1000);
INSERT INTO core10.master_item_categories_v1(id,tenant_id,business_id,code,name_en) VALUES (97401,9701,97101,'SWEETS','Sweets');
INSERT INTO core10.items(id,tenant_id,business_id,sku,name_en,name_bn,item_kind,category_id,base_uom_id)
 VALUES (97202,9701,97101,'RASGULLA','Rasgulla','রসগোল্লা','finished_good',97401,97301);
INSERT INTO core10.master_item_variants_v1(id,tenant_id,business_id,item_id,code,name_en) VALUES (97501,9701,97101,97202,'LARGE','Large');
INSERT INTO core10.master_item_barcodes_v1(tenant_id,business_id,item_id,variant_id,uom_id,barcode)
 VALUES (9701,97101,97202,97501,97302,'8901234567890');
INSERT INTO core10.master_parties_v1(id,tenant_id,business_id,code,party_kind,name_en,phone) VALUES (97601,9701,97101,'C-001','customer','Walk-in','+880 1700-000000');
INSERT INTO core10.master_price_lists_v1(id,tenant_id,business_id,code,name_en,list_kind,currency,effective_from)
 VALUES (97701,9701,97101,'RETAIL','Retail','sales','BDT','2026-01-01');
INSERT INTO core10.master_price_list_items_v1(tenant_id,business_id,price_list_id,item_id,variant_id,uom_id,unit_price)
 VALUES (9701,97101,97701,97202,97501,97301,25);

CREATE FUNCTION pg_temp.must_fail(p_label text, p_sql text, p_state text) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
 BEGIN EXECUTE p_sql;
 EXCEPTION WHEN OTHERS THEN
  IF SQLSTATE <> p_state THEN RAISE EXCEPTION '% failed with % (%), expected %', p_label, SQLSTATE, SQLERRM, p_state; END IF;
  RAISE NOTICE 'ok negative: %', p_label; RETURN;
 END;
 RAISE EXCEPTION 'NEGATIVE DID NOT FAIL: %', p_label;
END $f$;

-- cross-dimension conversion (count -> mass)
SELECT pg_temp.must_fail('cross-dimension conversion',
 $$INSERT INTO core10.master_uom_conversions_v1(tenant_id,business_id,dimension,from_uom_id,to_uom_id,factor) VALUES (9701,97101,'count',97301,97303,2)$$,'23503');
-- self conversion, zero factor
SELECT pg_temp.must_fail('self conversion',
 $$INSERT INTO core10.master_uom_conversions_v1(tenant_id,business_id,dimension,from_uom_id,to_uom_id,factor) VALUES (9701,97101,'count',97301,97301,1)$$,'23514');
SELECT pg_temp.must_fail('zero factor',
 $$INSERT INTO core10.master_uom_conversions_v1(tenant_id,business_id,dimension,from_uom_id,to_uom_id,factor) VALUES (9701,97101,'mass',97304,97303,0)$$,'23514');
-- cross-tenant / cross-business references
SELECT pg_temp.must_fail('item base UOM from other tenant',
 $$UPDATE core10.items SET base_uom_id=97305 WHERE id=97202$$,'23503');
SELECT pg_temp.must_fail('price line item of other business',
 $$INSERT INTO core10.master_price_list_items_v1(tenant_id,business_id,price_list_id,item_id,uom_id,unit_price) VALUES (9702,97102,97701,97202,97305,1)$$,'23503');
SELECT pg_temp.must_fail('variant of another item on barcode',
 $$INSERT INTO core10.items(id,tenant_id,business_id,sku) VALUES (97203,9701,97101,'OTHER');
   INSERT INTO core10.master_item_barcodes_v1(tenant_id,business_id,item_id,variant_id,barcode) VALUES (9701,97101,97203,97501,'1111222233')$$,'23503');
-- duplicates and formats
SELECT pg_temp.must_fail('duplicate barcode in business',
 $$INSERT INTO core10.master_item_barcodes_v1(tenant_id,business_id,item_id,barcode) VALUES (9701,97101,97201,'8901234567890')$$,'23505');
SELECT pg_temp.must_fail('duplicate price line',
 $$INSERT INTO core10.master_price_list_items_v1(tenant_id,business_id,price_list_id,item_id,variant_id,uom_id,unit_price) VALUES (9701,97101,97701,97202,97501,97301,30)$$,'23505');
SELECT pg_temp.must_fail('negative price',
 $$INSERT INTO core10.master_price_list_items_v1(tenant_id,business_id,price_list_id,item_id,uom_id,unit_price) VALUES (9701,97101,97701,97201,97301,-1)$$,'23514');
SELECT pg_temp.must_fail('NaN price',
 $$INSERT INTO core10.master_price_list_items_v1(tenant_id,business_id,price_list_id,item_id,uom_id,unit_price) VALUES (9701,97101,97701,97201,97301,'NaN')$$,'23514');
SELECT pg_temp.must_fail('bad UOM code',
 $$INSERT INTO core10.master_uoms_v1(tenant_id,business_id,code,name_en,dimension) VALUES (9701,97101,'kg lower','x','mass')$$,'23514');
SELECT pg_temp.must_fail('bad currency',
 $$INSERT INTO core10.master_price_lists_v1(tenant_id,business_id,code,name_en,list_kind,currency,effective_from) VALUES (9701,97101,'X','x','sales','bdt','2026-01-01')$$,'23514');
SELECT pg_temp.must_fail('effective_to before from',
 $$INSERT INTO core10.master_price_lists_v1(tenant_id,business_id,code,name_en,list_kind,currency,effective_from,effective_to) VALUES (9701,97101,'Y','y','sales','BDT','2026-02-01','2026-01-01')$$,'23514');
SELECT pg_temp.must_fail('bad party kind',
 $$INSERT INTO core10.master_parties_v1(tenant_id,business_id,code,party_kind,name_en) VALUES (9701,97101,'S-1','vendor','x')$$,'23514');
SELECT pg_temp.must_fail('duplicate SKU in business',
 $$INSERT INTO core10.items(tenant_id,business_id,sku) VALUES (9701,97101,'RASGULLA')$$,'23505');
-- the same codes are allowed in another business (business scope, not global)
INSERT INTO core10.master_parties_v1(tenant_id,business_id,code,party_kind,name_en) VALUES (9702,97102,'C-001','customer','Other walk-in');

-- No direct table access for API roles: reads and writes go through RPCs only.
SET LOCAL ROLE authenticated;
SELECT pg_temp.must_fail('authenticated direct select', $$SELECT count(*) FROM core10.master_parties_v1$$,'42501');
SELECT pg_temp.must_fail('authenticated direct insert', $$INSERT INTO core10.master_uoms_v1(tenant_id,business_id,code,name_en,dimension) VALUES (9701,97101,'ZZ','z','count')$$,'42501');
RESET ROLE;
SET LOCAL ROLE anon;
SELECT pg_temp.must_fail('anon direct select', $$SELECT count(*) FROM core10.master_price_lists_v1$$,'42501');
RESET ROLE;

DO $$ DECLARE n int; BEGIN
 SELECT count(*) INTO n FROM pg_class c WHERE c.relnamespace='core10'::regnamespace AND c.relname LIKE 'master\_%' AND c.relkind='r' AND NOT c.relrowsecurity;
 IF n<>0 THEN RAISE EXCEPTION 'master table without RLS: %', n; END IF;
 SELECT count(*) INTO n FROM pg_class c WHERE c.relnamespace='core10'::regnamespace AND c.relname LIKE 'master\_%' AND c.relkind='r'
  AND (has_table_privilege('authenticated',c.oid,'SELECT,INSERT,UPDATE,DELETE') OR has_table_privilege('anon',c.oid,'SELECT,INSERT,UPDATE,DELETE'));
 IF n<>0 THEN RAISE EXCEPTION 'master table with API-role privilege: %', n; END IF;
 RAISE NOTICE 'NP02 master tables e2e PASS';
END $$;
ROLLBACK;
