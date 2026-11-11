-- Disposable test-database role creation and synthetic tenant/business/demo identities.
DO $$BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN; END IF;
END $$;

INSERT INTO c10_demo.tenants(id,slug) VALUES (1,'demo-owned-portfolio'),(2,'demo-independent-customer');
INSERT INTO c10_demo.legal_entities(id,tenant_id,label) VALUES(11,1,'Owner Legal'),(21,2,'Customer Legal');
INSERT INTO c10_demo.templates(code,source_status,demo_allowed,enterprise_certified)
VALUES('food_manufacturing','available',true,false),
('hardware_paint','not_implemented',false,false),
('construction','not_implemented',false,false);
INSERT INTO c10_demo.businesses(id,tenant_id,legal_entity_id,slug,template_code,request_key,status)
VALUES(101,1,11,'demo-sweets','food_manufacturing','seed-a','draft'),
(102,1,11,'demo-second-business','food_manufacturing','seed-b','draft'),
(201,2,21,'customer-business','food_manufacturing','seed-c','draft');
INSERT INTO c10_demo.sites(id,tenant_id,business_id,kind,label,request_key)
VALUES(1001,1,101,'showroom','A1','seed-1'),
(1002,1,101,'factory','A2','seed-2'),
(1003,1,102,'showroom','A3','seed-3'),
(2001,2,201,'showroom','B1','seed-4');
INSERT INTO c10_demo.stock_locations(id,tenant_id,business_id,site_id,code)
VALUES(5001,1,101,1001,'MAIN'),(5002,1,101,1002,'MAIN'),
(5003,1,102,1003,'MAIN'),(6001,2,201,2001,'MAIN');
INSERT INTO c10_demo.items(id,tenant_id,business_id,sku)
VALUES(8001,1,101,'SWEETS'),(8002,1,102,'OTHER'),(9001,2,201,'CUSTOMER');
INSERT INTO c10_demo.tenant_members(tenant_id,user_id,role,active)
VALUES (1,'11111111-1111-4111-8111-111111111111','tenant_owner',true),
(2,'77777777-7777-4777-8777-777777777777','tenant_owner',true);
INSERT INTO c10_demo.business_members(tenant_id,business_id,user_id,role,active)
VALUES(1,101,'22222222-2222-4222-8222-222222222222','business_owner',true),
(1,101,'33333333-3333-4333-8333-333333333333','manager',true),
(1,101,'55555555-5555-4555-8555-555555555555','investor',true),
(1,101,'66666666-6666-4666-8666-666666666666','manager',false);
INSERT INTO c10_demo.site_grants(tenant_id,business_id,site_id,user_id,actions,active)
VALUES(1,101,1001,'44444444-4444-4444-8444-444444444444',ARRAY['stock.read','stock.post'],true),
(2,201,2001,'88888888-8888-4888-8888-888888888888',ARRAY['stock.read','stock.post'],true);
-- No implicit membership for 99999999... platform software operator.
-- Identity IDs above are inert fixture UUIDs, NOT login credentials or real Auth users.
