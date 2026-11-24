-- Synthetic fixtures for the disposable canonical W02 rehearsal only.
BEGIN;
INSERT INTO core10.templates(code,source_status,demo_allowed) VALUES ('sweets_bakery','available',true)
 ON CONFLICT (code) DO NOTHING;
INSERT INTO core10.tenants(id,slug) VALUES (971,'w02-fixture-a'),(972,'w02-fixture-b');
INSERT INTO core10.legal_entities(id,tenant_id,label) VALUES (9710,971,'W02 synthetic A'),(9720,972,'W02 synthetic B');
INSERT INTO core10.businesses(id,tenant_id,legal_entity_id,slug,template_code,request_key) VALUES
 (9711,971,9710,'w02-fixture-main','sweets_bakery','w02-b1'),
 (9712,971,9710,'w02-fixture-secondary','sweets_bakery','w02-b2'),
 (9721,972,9720,'w02-fixture-foreign','sweets_bakery','w02-b3');
INSERT INTO core10.sites(id,tenant_id,business_id,kind,label,request_key) VALUES
 (97111,971,9711,'factory','W02 fixture factory','w02-s1'),
 (97112,971,9711,'showroom','W02 fixture showroom','w02-s2'),
 (97121,971,9712,'showroom','W02 fixture other business','w02-s3'),
 (97211,972,9721,'showroom','W02 fixture other tenant','w02-s4');
INSERT INTO core10.stock_locations(id,tenant_id,business_id,site_id,code) VALUES
 (971111,971,9711,97111,'W02-FIXTURE-A'),(971121,971,9711,97112,'W02-FIXTURE-B');
INSERT INTO core10.items(id,tenant_id,business_id,sku,name_en,name_bn,status) VALUES
 (97101,971,9711,'W02-FIXTURE-CRATE','Synthetic TEST crate','পরীক্ষামূলক ক্যারেট','active'),
 (97102,971,9711,'W02-FIXTURE-TRAY','Synthetic TEST tray','পরীক্ষামূলক ট্রে','active');
INSERT INTO core10.tenant_members(tenant_id,user_id,role) VALUES
 (971,'a0711111-1111-4111-8111-111111111111','tenant_owner'),
 (972,'a0722222-2222-4222-8222-222222222222','tenant_owner');
INSERT INTO core10.site_grants(tenant_id,business_id,site_id,user_id,actions,denied_actions) VALUES
 (971,9711,97112,'a0733333-3333-4333-8333-333333333333','{stock.read}','{}'),
 (971,9711,97111,'a0744444-4444-4444-8444-444444444444','{stock.read}','{}'),
 (971,9711,97112,'a0744444-4444-4444-8444-444444444444','{stock.read}','{}');
COMMIT;
