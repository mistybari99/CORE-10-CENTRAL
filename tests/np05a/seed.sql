-- Fictional QA business and synthetic subject claims ONLY; disposable PostgreSQL.
INSERT INTO core10.tenants(id,slug) VALUES(951,'np05a-fiction-a'),(952,'np05a-fiction-b');
INSERT INTO core10.legal_entities(id,tenant_id,label) VALUES(9501,951,'Fictional bakery A'),(9502,952,'Fictional bakery B');
INSERT INTO core10.businesses(id,tenant_id,legal_entity_id,slug,template_code,request_key) VALUES
 (9511,951,9501,'fictional-sandesh','sweets_bakery','mfg-seed-a'),(9512,952,9502,'foreign-bakery','sweets_bakery','mfg-seed-b'),
 (9513,951,9501,'sister-bakery','sweets_bakery','mfg-seed-c');
INSERT INTO core10.sites(id,tenant_id,business_id,kind,label,request_key) VALUES
 (9521,951,9511,'factory','Fictional factory','mfg-site-a'),(9522,952,9512,'factory','Foreign factory','mfg-site-b'),
 (9523,951,9513,'factory','Sister factory','mfg-site-c'),(9524,951,9511,'factory','Other site','mfg-site-d');
INSERT INTO core10.stock_locations(id,tenant_id,business_id,site_id,code) VALUES
 (9531,951,9511,9521,'QA-STORE'),(9532,952,9512,9522,'FOREIGN');
INSERT INTO core10.items(id,tenant_id,business_id,sku) VALUES
 (9541,951,9511,'QA-SANDESH'),(9542,951,9511,'QA-MILK'),(9543,951,9511,'QA-SUGAR'),(9544,951,9511,'QA-BOX'),(9545,952,9512,'FOREIGN');
INSERT INTO core10.business_members(tenant_id,business_id,user_id,role,active,valid_until) VALUES
 (951,9511,'95111111-1111-4111-8111-111111111111','business_owner',true,NULL),
 (951,9511,'95222222-2222-4222-8222-222222222222','business_owner',true,NULL),
 (951,9511,'95333333-3333-4333-8333-333333333333','manager',true,NULL),
 (951,9511,'95444444-4444-4444-8444-444444444444','investor',true,NULL),
 (952,9512,'95666666-6666-4666-8666-666666666666','business_owner',true,NULL),
 (951,9511,'95777777-7777-4777-8777-777777777777','business_owner',false,NULL),
 (951,9511,'95888888-8888-4888-8888-888888888888','business_owner',true,now()-interval '1 day');
INSERT INTO core10.site_grants(tenant_id,business_id,site_id,user_id,actions,denied_actions) VALUES
 (951,9511,9521,'95555555-5555-4555-8555-555555555555',ARRAY['stock.read'],'{}'),
 (951,9511,9524,'95111111-1111-4111-8111-111111111111','{}',ARRAY['stock.read']);
