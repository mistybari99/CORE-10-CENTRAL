-- C10-A055 synthetic personas (inert fixture UUIDs, NOT real Auth users). Applies after tests/c10_a018_demo_seed.sql + A055 SQL.
-- A018 personas reused: 1111 tenant owner(t1), 2222 business owner(101), 3333 manager(101), 4444 stock-only site staff(1001),
-- 5555 investor, 6666 revoked manager, 7777 tenant-2 owner, 8888 tenant-2 stock staff, 9999 platform operator (no membership).
-- Extra sites: 1004 project + 1005 godown (business 101) to exercise per-mode policy.
INSERT INTO c10_demo.sites(id,tenant_id,business_id,kind,label,request_key) VALUES
 (1004,1,101,'project','Worksite P1','am-seed-1004'),(1005,1,101,'godown','Godown G1','am-seed-1005');
INSERT INTO c10_demo.business_members(tenant_id,business_id,user_id,role,active) VALUES
 (1,102,'e1111111-1111-4111-8111-111111111111','business_owner',true);
-- Maintenance roles are EXPLICIT grants (never derived from stock/site_grants/manager/payroll).
INSERT INTO c10_demo.am_grants(tenant_id,business_id,user_id,role,site_id,active,granted_by) VALUES
 (1,101,'d1111111-1111-4111-8111-111111111111','supervisor',NULL,true,'22222222-2222-4222-8222-222222222222'),
 (1,101,'d2222222-2222-4222-8222-222222222222','supervisor',1001,true,'22222222-2222-4222-8222-222222222222'),
 (1,101,'d3333333-3333-4333-8333-333333333333','technician',1001,true,'22222222-2222-4222-8222-222222222222'),
 (1,101,'d4444444-4444-4444-8444-444444444444','technician',1002,true,'22222222-2222-4222-8222-222222222222'),
 (1,101,'d5555555-5555-4555-8555-555555555555','reporter',1001,true,'22222222-2222-4222-8222-222222222222'),
 (1,101,'d6666666-6666-4666-8666-666666666666','auditor',NULL,true,'22222222-2222-4222-8222-222222222222'),
 (1,101,'d7777777-7777-4777-8777-777777777777','technician',1001,false,'22222222-2222-4222-8222-222222222222'),
 (2,201,'d8888888-8888-4888-8888-888888888888','supervisor',NULL,true,'77777777-7777-4777-8777-777777777777');
