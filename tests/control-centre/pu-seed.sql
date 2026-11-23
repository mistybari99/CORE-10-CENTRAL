-- B-012 Purchase screen browser fixture: synthetic only, disposable loopback PostgreSQL. Tenants 1601/1602 are used by
-- no other test. Master items/suppliers go through the real 0151 writers; purchase orders through the real 0203 RPCs.
-- Personas: tenant owner, business owner (approver), manager (buyer), godown staff (site grant), other tenant owner.
\set ON_ERROR_STOP on
\o /dev/null
INSERT INTO core10.templates(code,source_status,demo_allowed) VALUES ('sweets_bakery','available',true) ON CONFLICT (code) DO NOTHING;
INSERT INTO core10.tenants(id,slug) VALUES (1601,'pu-owner'),(1602,'pu-other');
INSERT INTO core10.legal_entities(id,tenant_id,label) VALUES (16010,1601,'PU A'),(16020,1602,'PU B');
INSERT INTO core10.businesses(id,tenant_id,legal_entity_id,slug,template_code,request_key) VALUES
 (16011,1601,16010,'misti-sweets','sweets_bakery','pu-biz-1'),(16012,1601,16010,'second-bakery','sweets_bakery','pu-biz-2'),
 (16021,1602,16020,'other-co','sweets_bakery','pu-biz-3');
INSERT INTO core10.sites(id,tenant_id,business_id,kind,label,request_key) VALUES
 (160111,1601,16011,'godown','Main godown','pu-site-1'),(160112,1601,16011,'showroom','Branch 1','pu-site-2'),
 (160121,1601,16012,'factory','Bakery factory','pu-site-3'),(160211,1602,16021,'showroom','Other shop','pu-site-4');
INSERT INTO core10.stock_locations(id,tenant_id,business_id,site_id,code) VALUES
 (1601111,1601,16011,160111,'G-MAIN'),(1601112,1601,16011,160111,'G-COLD'),(1601121,1601,16011,160112,'SHOP'),
 (1601211,1601,16012,160121,'F-STORE'),(1602111,1602,16021,160211,'O-SHOP');
INSERT INTO core10.tenant_members(tenant_id,user_id,role) VALUES
 (1601,'e1611111-1111-4111-8111-111111111111','tenant_owner'),(1602,'e1655555-5555-4555-8555-555555555555','tenant_owner');
INSERT INTO core10.business_members(tenant_id,business_id,user_id,role,approval_actions) VALUES
 (1601,16011,'e1622222-2222-4222-8222-222222222222','business_owner','{approval.decide}'),
 (1601,16011,'e1633333-3333-4333-8333-333333333333','manager','{}');
INSERT INTO core10.site_grants(tenant_id,business_id,site_id,user_id,actions) VALUES
 (1601,16011,160111,'e1644444-4444-4444-8444-444444444444','{stock.read,stock.post}');
SET ROLE authenticated;
SELECT set_config('request.jwt.claims','{"sub":"e1611111-1111-4111-8111-111111111111"}',false);
SELECT set_config('request.jwt.claim.sub','e1611111-1111-4111-8111-111111111111',false);
SELECT core10.master_save_uom_v1(16011,'KG','Kilogram','কেজি','mass',3::smallint,true,0,'pu-seed-uom-kg') kg \gset
SELECT core10.master_save_item_v1(16011,'SUGAR','Sugar','চিনি','raw_material',NULL,:kg,'active',0,'pu-seed-item-1');
SELECT core10.master_save_item_v1(16011,'FLOUR','Flour','আটা','raw_material',NULL,:kg,'active',0,'pu-seed-item-2') flour \gset
SELECT core10.master_save_item_v1(16011,'GHEE','Ghee','ঘি','raw_material',NULL,:kg,'active',0,'pu-seed-item-3');
SELECT core10.master_save_item_v1(16011,'OLD-DYE','Old colour','পুরোনো রং','raw_material',NULL,NULL,'inactive',0,'pu-seed-item-4');
SELECT core10.master_save_party_v1(16011,'SUP-SUGAR','supplier','Sugar Mills','চিনি কল',NULL,NULL,'active',0,'pu-seed-party-1') sup \gset
SELECT core10.master_save_party_v1(16011,'SUP-DAIRY','both','Dairy House','দুগ্ধ ঘর',NULL,NULL,'active',0,'pu-seed-party-2');
SELECT core10.master_save_party_v1(16011,'CUS-001','customer','Walk-in customer','সাধারণ ক্রেতা',NULL,NULL,'active',0,'pu-seed-party-3');
SELECT core10.master_save_party_v1(16011,'SUP-OLD','supplier','Blocked supplier','বন্ধ সরবরাহকারী',NULL,NULL,'blocked',0,'pu-seed-party-4');
-- One-checker approval policy, published once; the browser test turns approval steps on and off through Owner Control.
SELECT core10.publish_approval_policy_v1(16011,'procurement','purchase_order',120,'pu-seed-policy-1');
-- 24 earlier orders at Branch 1 by the buyer (more than one page); 12 approved by the business owner.
SELECT set_config('request.jwt.claims','{"sub":"e1633333-3333-4333-8333-333333333333"}',false);
SELECT set_config('request.jwt.claim.sub','e1633333-3333-4333-8333-333333333333',false);
SELECT core10.procurement_save_po_v1(16011,NULL,160112,:sup,jsonb_build_array(jsonb_build_object('item_id',:flour,'quantity',i,'unit_price',40)),
 NULL,NULL,0,'pu-seed-po-'||lpad(i::text,3,'0')) FROM generate_series(1,24) i \g /dev/null
SELECT set_config('request.jwt.claims','{"sub":"e1622222-2222-4222-8222-222222222222"}',false);
SELECT set_config('request.jwt.claim.sub','e1622222-2222-4222-8222-222222222222',false);
DO $s$ DECLARE r record; BEGIN
 FOR r IN SELECT (x->>'po_id')::bigint id, (x->>'version')::int version, row_number() OVER (ORDER BY (x->>'po_id')::bigint) n
   FROM jsonb_array_elements(core10.procurement_list_pos_v1(16011,NULL,'draft',NULL,200)->'items') x ORDER BY 1 LIMIT 12 LOOP
  PERFORM core10.procurement_advance_po_v1(r.id,'approve',r.version,'pu-seed-apv-'||lpad(r.n::text,3,'0'));
 END LOOP;
END $s$;
RESET ROLE;
