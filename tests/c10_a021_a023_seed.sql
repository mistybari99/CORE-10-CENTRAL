-- C10-A021-A023 additive synthetic fixtures only. Run as disposable CI postgres.
-- Existing org, tenant, identity and stock fixtures are loaded first.
INSERT INTO c10_demo.business_configuration_v1(
 business_id,tenant_id,display_name,brand_hex,setup_mode,created_by)
VALUES
 (101,1,'Sweets Demo','#6D1D2A','quick','11111111-1111-4111-8111-111111111111'),
 (102,1,'Separate Business Demo','#112233','advanced','11111111-1111-4111-8111-111111111111'),
 (201,2,'Customer Company','#223344','quick','77777777-7777-4777-8777-777777777777');
INSERT INTO c10_demo.business_module_settings_v1(
 tenant_id,business_id,module_code,visibility,operational_enabled)
SELECT b.tenant_id,b.id,t.module_code,'locked',false
FROM c10_demo.businesses b JOIN c10_demo.template_modules_v1 t
  ON t.template_code=b.template_code
WHERE b.id IN(101,102,201);
INSERT INTO c10_demo.business_members(tenant_id,business_id,user_id,role,active)
VALUES
 (1,101,'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','investor',true),
 (1,101,'cccccccc-cccc-4ccc-8ccc-cccccccccccc','investor',true),
 (1,102,'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','investor',true),
 (2,201,'dddddddd-dddd-4ddd-8ddd-dddddddddddd','investor',true);
-- Additional investors are independent fixture identities (no login credentials).
