-- Synthetic personas for the Owner Control Centre browser test (disposable database, committed).
INSERT INTO core10.tenants(id,slug) VALUES (901,'occ-a'),(902,'occ-b');
INSERT INTO core10.legal_entities(id,tenant_id,label) VALUES (9001,901,'Demo A'),(9002,902,'Demo B');
INSERT INTO core10.businesses(id,tenant_id,legal_entity_id,slug,template_code,request_key)
 VALUES (9101,901,9001,'occ-sweets','sweets_bakery','occ-seed-a'),(9102,902,9002,'occ-other','restaurant','occ-seed-b');
INSERT INTO core10.sites(id,tenant_id,business_id,kind,label,request_key)
 VALUES (9201,901,9101,'showroom','Showroom','occ-seed-s1'),(9202,901,9101,'factory','Factory','occ-seed-s2'),(9203,902,9102,'showroom','Other','occ-seed-s3');
INSERT INTO core10.tenant_members(tenant_id,user_id,role) VALUES
 (901,'91111111-1111-4111-8111-111111111111','tenant_owner'),(902,'96666666-6666-4666-8666-666666666666','tenant_owner');
INSERT INTO core10.business_members(tenant_id,business_id,user_id,role) VALUES
 (901,9101,'92222222-2222-4222-8222-222222222222','business_owner'),(901,9101,'93333333-3333-4333-8333-333333333333','manager');
INSERT INTO core10.site_grants(tenant_id,business_id,site_id,user_id,actions)
 VALUES (901,9101,9201,'95555555-5555-4555-8555-555555555555',ARRAY['stock.read']);

-- D063 fixture has no Business and no legal entity.
INSERT INTO core10.tenants(id,slug) VALUES (903,'occ-first-business');
INSERT INTO core10.tenant_members(tenant_id,user_id,role)
 VALUES (903,'98888888-8888-4888-8888-888888888888','tenant_owner');
