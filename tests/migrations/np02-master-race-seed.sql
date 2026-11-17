-- B-011 race fixture: committed synthetic tenant for independent sessions (disposable PG17 only).
\set ON_ERROR_STOP on
INSERT INTO core10.templates(code,source_status,demo_allowed) VALUES ('sweets_bakery','available',true) ON CONFLICT (code) DO NOTHING;
INSERT INTO core10.tenants(id,slug) VALUES (981,'np02-race-a'),(982,'np02-race-b');
INSERT INTO core10.legal_entities(id,tenant_id,label) VALUES (9810,981,'Race A'),(9820,982,'Race B');
INSERT INTO core10.businesses(id,tenant_id,legal_entity_id,slug,template_code,request_key)
 VALUES (9811,981,9810,'np02-race-a','sweets_bakery','np02-race-ba'),(9821,982,9820,'np02-race-b','sweets_bakery','np02-race-bb');
INSERT INTO core10.tenant_members(tenant_id,user_id,role) VALUES
 (981,'b1111111-1111-4111-8111-111111111111','tenant_owner'),(982,'b5555555-5555-4555-8555-555555555555','tenant_owner');
