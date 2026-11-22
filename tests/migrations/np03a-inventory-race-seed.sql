-- B-012 / 0201 race fixture: committed synthetic tenant for independent sessions (disposable PG17 only).
\set ON_ERROR_STOP on
INSERT INTO core10.templates(code,source_status,demo_allowed) VALUES ('sweets_bakery','available',true) ON CONFLICT (code) DO NOTHING;
INSERT INTO core10.tenants(id,slug) VALUES (731,'np03a-race-a'),(732,'np03a-race-b');
INSERT INTO core10.legal_entities(id,tenant_id,label) VALUES (7310,731,'Race A'),(7320,732,'Race B');
INSERT INTO core10.businesses(id,tenant_id,legal_entity_id,slug,template_code,request_key)
 VALUES (7311,731,7310,'np03a-race-a','sweets_bakery','np03a-race-ba'),(7321,732,7320,'np03a-race-b','sweets_bakery','np03a-race-bb');
INSERT INTO core10.sites(id,tenant_id,business_id,kind,label,request_key) VALUES
 (73111,731,7311,'factory','Factory','np03a-race-s1'),(73112,731,7311,'showroom','Branch','np03a-race-s2'),
 (73113,731,7311,'godown','Godown','np03a-race-s3');
INSERT INTO core10.stock_locations(id,tenant_id,business_id,site_id,code) VALUES
 (731111,731,7311,73111,'F'),(731121,731,7311,73112,'S'),(731131,731,7311,73113,'G');
INSERT INTO core10.items(id,tenant_id,business_id,sku,name_en) VALUES (73101,731,7311,'RACE-SUGAR','Race sugar');
INSERT INTO core10.tenant_members(tenant_id,user_id,role) VALUES
 (731,'c1111111-1111-4111-8111-111111111111','tenant_owner'),(732,'c5555555-5555-4555-8555-555555555555','tenant_owner');
SELECT set_config('request.jwt.claims','{"sub":"c1111111-1111-4111-8111-111111111111"}',false);
CREATE FUNCTION pg_temp.ready(k text,kind text,s bigint,d bigint,q numeric,post boolean) RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE c jsonb; BEGIN
 c := core10.create_inventory_command_v1(7311,kind,s,d,73101,q,NULL,k);
 c := core10.advance_inventory_command_v1((c->>'command_id')::bigint,'confirm',1,k||'-c');
 IF post THEN c := core10.advance_inventory_command_v1((c->>'command_id')::bigint,'post',2,k||'-p'); END IF;
 RETURN (c->>'command_id')::bigint; END $$;
SELECT pg_temp.ready('race-seed-f10','receive',NULL,731111,10,true);
SELECT pg_temp.ready('race-seed-s50','receive',NULL,731121,50,true);
SELECT pg_temp.ready('race-seed-g50','receive',NULL,731131,50,true);
SELECT pg_temp.ready('race-iss-000'||i,'issue',731111,NULL,3,false) FROM generate_series(1,6) i;
SELECT pg_temp.ready('race-one-0001','receive',NULL,731131,1,false);
SELECT pg_temp.ready('race-ctl-000'||i,'receive',NULL,731121,1,false) FROM generate_series(2,4) i;
