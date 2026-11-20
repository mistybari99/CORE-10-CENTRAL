-- B-011 / 0151: Master Data RPC proof (disposable PG17, everything rolled back).
-- Personas, Owner Control disable, scope, versions, idempotency, audit, NP03B and NP05A port contracts.
\set ON_ERROR_STOP on
BEGIN;
INSERT INTO core10.templates(code,source_status,demo_allowed) VALUES ('sweets_bakery','available',true) ON CONFLICT (code) DO NOTHING;
INSERT INTO core10.tenants(id,slug) VALUES (961,'np02m-a'),(962,'np02m-b');
INSERT INTO core10.legal_entities(id,tenant_id,label) VALUES (9610,961,'Master A'),(9620,962,'Master B');
INSERT INTO core10.businesses(id,tenant_id,legal_entity_id,slug,template_code,request_key)
 VALUES (9611,961,9610,'np02m-a','sweets_bakery','np02m-ba'),(9621,962,9620,'np02m-b','sweets_bakery','np02m-bb');
INSERT INTO core10.sites(id,tenant_id,business_id,kind,label,request_key) VALUES (9612,961,9611,'showroom','Counter A','np02m-sa');
INSERT INTO core10.tenant_members(tenant_id,user_id,role) VALUES
 (961,'a1111111-1111-4111-8111-111111111111','tenant_owner'),(962,'a5555555-5555-4555-8555-555555555555','tenant_owner');
INSERT INTO core10.business_members(tenant_id,business_id,user_id,role) VALUES
 (961,9611,'a2222222-2222-4222-8222-222222222222','business_owner'),(961,9611,'a3333333-3333-4333-8333-333333333333','manager'),(961,9611,'a4444444-4444-4444-8444-444444444444','investor');

CREATE SCHEMA np02m_test;
GRANT USAGE ON SCHEMA np02m_test TO authenticated;
CREATE FUNCTION np02m_test.as_user(p_uuid text) RETURNS void LANGUAGE sql AS $$
 SELECT set_config('request.jwt.claims',json_build_object('sub',p_uuid)::text,true), set_config('request.jwt.claim.sub',p_uuid,true) $$;
CREATE FUNCTION np02m_test.ok(p boolean, m text) RETURNS void LANGUAGE plpgsql AS $$
 BEGIN IF p IS DISTINCT FROM true THEN RAISE EXCEPTION 'MASTER_ASSERT_FAILED:%',m; END IF; END $$;
CREATE FUNCTION np02m_test.expect(p_sql text, p_prefix text) RETURNS void LANGUAGE plpgsql AS $$
 BEGIN
  BEGIN EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
   IF SQLERRM LIKE p_prefix||'%' THEN RETURN; END IF;
   RAISE EXCEPTION 'MASTER_WRONG_ERROR expected=% got=% query=%',p_prefix,SQLERRM,left(p_sql,120);
  END;
  RAISE EXCEPTION 'MASTER_EXPECTED_DENIAL:% query=%',p_prefix,left(p_sql,120);
 END $$;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA np02m_test TO authenticated;
SET LOCAL ROLE authenticated;

-- Owner builds master data
SELECT np02m_test.as_user('a1111111-1111-4111-8111-111111111111');
SELECT core10.master_save_uom_v1(9611,'PCS','Piece','পিস','count',0::smallint,true,0,'np02m-uom-pcs') pcs \gset
SELECT core10.master_save_uom_v1(9611,'BOX','Box of 12',NULL,'count',0::smallint,true,0,'np02m-uom-box') box \gset
SELECT core10.master_save_uom_v1(9611,'KG','Kilogram','কেজি','mass',3::smallint,true,0,'np02m-uom-kg') kg \gset
SELECT core10.master_save_uom_v1(9611,'G','Gram',NULL,'mass',0::smallint,true,0,'np02m-uom-g') g \gset
SELECT core10.master_save_uom_conversion_v1(9611,:box,:pcs,12,true,0,'np02m-conv-box') \gset
SELECT core10.master_save_uom_conversion_v1(9611,:kg,:g,1000,true,0,'np02m-conv-kg') \gset
SELECT core10.master_save_category_v1(9611,'SWEETS','Sweets','মিষ্টি',NULL,true,0,'np02m-cat-sweets') cat \gset
SELECT core10.master_save_item_v1(9611,'RASGULLA','Rasgulla','রসগোল্লা','finished_good',:cat,:pcs,'active',0,'np02m-item-ras') ras \gset
SELECT core10.master_save_item_v1(9611,'SUGAR','Sugar','চিনি','raw_material',NULL,:kg,'active',0,'np02m-item-sug') sugar \gset
SELECT core10.master_save_variant_v1(9611,:ras,'LARGE','Large','বড়','{"size":"L"}',NULL,0,'np02m-var-large') large \gset
SELECT core10.master_save_barcode_v1(9611,'8901234567890',:ras,:large,:pcs,true,0,'np02m-bc-1') \gset
SELECT core10.master_save_party_v1(9611,'C-001','customer','Walk-in','সাধারণ ক্রেতা','+880 1700-000000',NULL,'active',0,'np02m-party-c1') cust \gset
SELECT core10.master_save_party_v1(9611,'S-001','supplier','Sugar Mill',NULL,NULL,NULL,'active',0,'np02m-party-s1') supp \gset
SELECT core10.master_save_price_list_v1(9611,'RETAIL','Retail','খুচরা','sales','BDT',NULL,current_date-1,NULL,'active',0,'np02m-pl-retail') pl \gset
SELECT core10.master_save_price_v1(9611,:pl,:ras,:large,:pcs,0,25,true,0,'np02m-price-1') \gset
SELECT core10.master_save_price_v1(9611,:pl,:ras,:large,:pcs,10,22,true,0,'np02m-price-2') \gset

-- 0152 read RPCs: owner view, pagination, search, detail, no cross-business leak
SELECT np02m_test.ok((core10.master_list_items_v1(9611,NULL,NULL,NULL,1,NULL)->'rows'->0->>'sku')='RASGULLA','page 1');
SELECT np02m_test.ok((core10.master_list_items_v1(9611,NULL,NULL,NULL,1,NULL)->>'next_after_id')::bigint=:ras,'cursor');
SELECT np02m_test.ok((core10.master_list_items_v1(9611,NULL,NULL,NULL,1,:ras)->'rows'->0->>'sku')='SUGAR','page 2');
SELECT np02m_test.ok(core10.master_list_items_v1(9611,NULL,NULL,NULL,1,:sugar)->>'next_after_id' IS NULL,'last page');
SELECT np02m_test.ok(jsonb_array_length(core10.master_list_items_v1(9611,'চিনি')->'rows')=1,'bangla search');
SELECT np02m_test.ok((core10.master_list_items_v1(9611,'890123456')->'rows'->0->>'id')::bigint=:ras,'barcode search');
SELECT np02m_test.ok(jsonb_array_length(core10.master_list_items_v1(9611,'%')->'rows')=0,'LIKE wildcard is literal');
SELECT np02m_test.ok(jsonb_array_length(core10.master_get_item_v1(9611,:ras)->'variants')=1
 AND jsonb_array_length(core10.master_get_item_v1(9611,:ras)->'prices')=2,'item detail');
SELECT np02m_test.ok(jsonb_array_length(core10.master_list_uoms_v1(9611)->'conversions')=2,'uoms+conversions');
SELECT np02m_test.ok(jsonb_array_length(core10.master_list_parties_v1(9611,'supplier')->'rows')=1,'supplier filter');
SELECT np02m_test.ok(jsonb_array_length(core10.master_get_price_list_v1(9611,:pl)->'rows')=2,'price list detail');
SELECT np02m_test.ok((core10.master_find_barcode_v1(9611,'8901234567890')->>'item_id')::bigint=:ras,'barcode lookup');
SELECT np02m_test.ok(jsonb_array_length(core10.master_list_categories_v1(9611))=1
 AND jsonb_array_length(core10.master_list_price_lists_v1(9611,'sales'))=1,'categories/price lists');
SELECT np02m_test.expect(format('SELECT core10.master_get_item_v1(9621,%s)',:ras),'MASTER_SCOPE');
SELECT np02m_test.expect('SELECT core10.master_find_barcode_v1(9611,''0000000000'')','MASTER_NOT_FOUND');
SELECT np02m_test.as_user('a3333333-3333-4333-8333-333333333333');
SELECT np02m_test.ok(jsonb_array_length(core10.master_list_items_v1(9611)->'rows')=2,'manager can read');
SELECT np02m_test.as_user('a5555555-5555-4555-8555-555555555555');
SELECT np02m_test.expect('SELECT core10.master_list_items_v1(9611)','MASTER_SCOPE');
SELECT np02m_test.expect(format('SELECT core10.master_get_item_v1(9611,%s)',:ras),'MASTER_SCOPE');
SELECT np02m_test.ok(jsonb_array_length(core10.master_list_items_v1(9621)->'rows')=0,'own empty business');
SELECT np02m_test.as_user('');
SELECT np02m_test.expect('SELECT core10.master_list_parties_v1(9611)','MASTER_SCOPE');
SELECT np02m_test.as_user('a1111111-1111-4111-8111-111111111111');

-- Idempotency: same key + same actor returns the same id and writes nothing new
SELECT np02m_test.ok(core10.master_save_item_v1(9611,'RASGULLA','Rasgulla','রসগোল্লা','finished_good',:cat,:pcs,'active',0,'np02m-item-ras')=:ras,'replay returns same item');
-- Optimistic version: update at v1 succeeds, stale v1 again is refused
SELECT core10.master_save_item_v1(9611,'RASGULLA','Rasgulla (fresh)','রসগোল্লা','finished_good',:cat,:pcs,'active',1,'np02m-item-ras-v2') \gset
SELECT np02m_test.expect(format($q$SELECT core10.master_save_item_v1(9611,'RASGULLA','x',NULL,NULL,NULL,NULL,NULL,1,'np02m-item-ras-v2b')$q$),'MASTER_STALE_OR_MISSING');
-- UOM dimension cannot be changed by an update
SELECT np02m_test.expect($q$SELECT core10.master_save_uom_v1(9611,'PCS','Piece',NULL,'mass',0::smallint,true,1,'np02m-uom-pcs-dim')$q$,'MASTER_STALE_OR_MISSING');
-- Cross-dimension conversion refused by the table FK
SELECT np02m_test.expect(format('SELECT core10.master_save_uom_conversion_v1(9611,%s,%s,2,true,0,%L)',:pcs,:kg,'np02m-conv-bad'),'insert or update on table');

-- Business owner may write (can_manage); manager, investor and other tenant may not
SELECT np02m_test.as_user('a2222222-2222-4222-8222-222222222222');
SELECT core10.master_save_party_v1(9611,'C-002','both','Shop B',NULL,NULL,NULL,'active',0,'np02m-party-c2') \gset
-- same key from a different actor is refused (no hijack of another user's request)
SELECT np02m_test.expect($q$SELECT core10.master_save_party_v1(9611,'C-001','customer','x',NULL,NULL,NULL,NULL,0,'np02m-party-c1')$q$,'MASTER_REQUEST_KEY_REUSED');
SELECT np02m_test.as_user('a3333333-3333-4333-8333-333333333333');
SELECT np02m_test.expect($q$SELECT core10.master_save_party_v1(9611,'C-008','customer','x',NULL,NULL,NULL,NULL,0,'np02m-party-mgr')$q$,'MASTER_AUTH_DENIED');
SELECT np02m_test.as_user('a4444444-4444-4444-8444-444444444444');
SELECT np02m_test.expect($q$SELECT core10.master_save_party_v1(9611,'C-009','customer','x',NULL,NULL,NULL,NULL,0,'np02m-party-inv')$q$,'MASTER_AUTH_DENIED');
SELECT np02m_test.as_user('a5555555-5555-4555-8555-555555555555');
SELECT np02m_test.expect($q$SELECT core10.master_save_uom_v1(9611,'ZZ','x',NULL,'count',0::smallint,true,0,'np02m-cross-tenant')$q$,'MASTER_AUTH_DENIED');
SELECT np02m_test.as_user('');
SELECT np02m_test.expect($q$SELECT core10.master_save_uom_v1(9611,'ZZ','x',NULL,'count',0::smallint,true,0,'np02m-unsigned')$q$,'MASTER_AUTH_DENIED');
-- Internal ports are not callable by API users
SELECT np02m_test.expect('SELECT core10.master_validate_sales_order_v1(9611,NULL,''{}''::jsonb)','permission denied');
SELECT np02m_test.expect('SELECT core10.master_uom_convert_v1(9611,1,1,1)','permission denied');

-- Owner Control: disabling master.party blocks party writes for everyone, including the Owner
SELECT np02m_test.as_user('a1111111-1111-4111-8111-111111111111');
SELECT core10.control_set_v1(9611,NULL,'master.party',false,0::smallint,'{}'::jsonb,NULL,false,0,'Owner pauses party edits','np02m-ctl-off') \gset
SELECT np02m_test.expect($q$SELECT core10.master_save_party_v1(9611,'C-003','customer','x',NULL,NULL,NULL,NULL,0,'np02m-party-off')$q$,'CONTROL_DISABLED:master.party');
-- other master features stay usable
SELECT core10.master_save_uom_v1(9611,'L','Litre',NULL,'volume',3::smallint,true,0,'np02m-uom-l') \gset

SELECT core10.control_set_v1(9611,NULL,'master.uom',false,0::smallint,'{}'::jsonb,NULL,false,0,'Owner pauses UOM edits','np02m-ctl-uom') \gset
SELECT np02m_test.expect($q$SELECT core10.master_save_uom_v1(9611,'ML','x',NULL,'volume',0::smallint,true,0,'np02m-uom-off')$q$,'CONTROL_DISABLED:master.uom');
SELECT core10.control_set_v1(9611,NULL,'master.item',false,0::smallint,'{}'::jsonb,NULL,false,0,'Owner pauses item edits','np02m-ctl-item') \gset
SELECT np02m_test.expect($q$SELECT core10.master_save_category_v1(9611,'X','x',NULL,NULL,true,0,'np02m-cat-off')$q$,'CONTROL_DISABLED:master.item');
SELECT core10.control_set_v1(9611,NULL,'master.price',false,0::smallint,'{}'::jsonb,NULL,false,0,'Owner pauses price edits','np02m-ctl-price') \gset
SELECT np02m_test.expect(format('SELECT core10.master_save_price_v1(9611,%s,%s,NULL,%s,0,30,true,0,%L)',:pl,:ras,:pcs,'np02m-price-off'),'CONTROL_DISABLED:master.price');
-- Audit: every recorded write has one canonical audit event in the master domain
RESET ROLE;
SELECT np02m_test.ok((SELECT count(*) FROM core10.canonical_audit_events_v1 WHERE business_id=9611 AND source_domain='master')
 =(SELECT count(*) FROM core10.master_requests_v1 WHERE business_id=9611),'one audit event per recorded write');
SELECT np02m_test.ok((SELECT count(*) FROM core10.master_requests_v1 WHERE business_id=9611)=19,'19 recorded writes (replay wrote nothing)');

-- NP05A port: conversions, inverse, identity, no guessing across dimensions
SELECT np02m_test.ok(core10.master_uom_convert_v1(9611,:box,:pcs,2)=24,'box->pcs');
SELECT np02m_test.ok(core10.master_uom_convert_v1(9611,:g,:kg,500)=0.5,'g->kg inverse');
SELECT np02m_test.ok(core10.master_uom_convert_v1(9611,:kg,:kg,3)=3,'identity');
SELECT np02m_test.expect(format('SELECT core10.master_uom_convert_v1(9611,%s,%s,1)',:pcs,:kg),'MASTER_UOM_NO_CONVERSION');
SELECT np02m_test.expect(format('SELECT core10.master_uom_convert_v1(9621,%s,%s,1)',:pcs,:box),'MASTER_UOM_SCOPE');
SELECT np02m_test.ok(core10.master_item_usable_v1(9611,:sugar) AND NOT core10.master_item_usable_v1(9621,:sugar),'item usable in scope only');

-- NP03B port: valid order, then each broken reference must return FALSE (never raise)
CREATE TEMP TABLE np02m_doc AS SELECT jsonb_build_object('customer_id',:cust,'price_list_id',:pl,'lines',jsonb_build_array(
 jsonb_build_object('item_id',:ras,'variant_id',:large,'uom_id',:pcs,'quantity',2,'unit_price',25,'discount_percent',0,'tax_percent',0))) d;
SELECT np02m_test.ok(core10.master_validate_sales_order_v1(9611,9612,d),'valid order') FROM np02m_doc;
SELECT np02m_test.ok(core10.master_validate_sales_order_v1(9611,NULL,jsonb_set(d,'{lines,0,quantity}','12')) IS FALSE,'qty 12 must use tier price 22') FROM np02m_doc;
SELECT np02m_test.ok(core10.master_validate_sales_order_v1(9611,NULL,jsonb_set(jsonb_set(d,'{lines,0,quantity}','12'),'{lines,0,unit_price}','22')),'tier price 22 accepted') FROM np02m_doc;
SELECT np02m_test.ok(core10.master_validate_sales_order_v1(9611,NULL,jsonb_set(d,'{customer_id}',to_jsonb(:supp))) IS FALSE,'supplier is not a customer') FROM np02m_doc;
SELECT np02m_test.ok(core10.master_validate_sales_order_v1(9621,NULL,d) IS FALSE,'other business') FROM np02m_doc;
SELECT np02m_test.ok(core10.master_validate_sales_order_v1(9611,NULL,jsonb_set(d,'{lines,0,unit_price}','1')) IS FALSE,'price mismatch') FROM np02m_doc;
SELECT np02m_test.ok(core10.master_validate_sales_order_v1(9611,NULL,jsonb_set(d,'{lines,0,uom_id}',to_jsonb(:kg))) IS FALSE,'wrong dimension') FROM np02m_doc;
SELECT np02m_test.ok(core10.master_validate_sales_order_v1(9611,NULL,jsonb_set(d,'{lines,0,variant_id}','null')) IS FALSE,'no price without variant') FROM np02m_doc;
SELECT np02m_test.ok(core10.master_validate_sales_order_v1(9611,NULL,jsonb_set(d,'{lines,0,item_id}','"x"')) IS FALSE,'malformed id') FROM np02m_doc;
SELECT np02m_test.ok(core10.master_validate_sales_order_v1(9611,NULL,jsonb_set(d,'{lines}','[]')) IS FALSE,'no lines') FROM np02m_doc;
SELECT np02m_test.ok(core10.master_validate_sales_order_v1(9611,NULL,jsonb_set(d,'{lines,0,quantity}','0')) IS FALSE,'zero quantity') FROM np02m_doc;
UPDATE core10.items SET status='inactive' WHERE id=:ras;
SELECT np02m_test.ok(core10.master_validate_sales_order_v1(9611,NULL,d) IS FALSE,'inactive item') FROM np02m_doc;

DO $$ BEGIN RAISE NOTICE 'NP02 master RPC e2e PASS'; END $$;
ROLLBACK;
