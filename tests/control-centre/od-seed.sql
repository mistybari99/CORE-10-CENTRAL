-- B-012 Owner dashboard browser fixture: synthetic only, disposable loopback PostgreSQL.
\set ON_ERROR_STOP on
INSERT INTO core10.templates(code,source_status,demo_allowed) VALUES ('sweets_bakery','available',true),('paint_hardware','available',true),('retail_wholesale','available',true)
 ON CONFLICT (code) DO NOTHING;
INSERT INTO core10.tenants(id,slug) VALUES (881,'od-owner'),(882,'od-other');
INSERT INTO core10.legal_entities(id,tenant_id,label) VALUES (8810,881,'OD A'),(8820,882,'OD B');
INSERT INTO core10.businesses(id,tenant_id,legal_entity_id,slug,template_code,request_key) VALUES
 (8811,881,8810,'misti-sweets','sweets_bakery','od-b1'),(8812,881,8810,'rong-paint','paint_hardware','od-b2'),
 (8813,881,8810,'bazar-retail','retail_wholesale','od-b3'),(8821,882,8820,'other-co','sweets_bakery','od-b4');
-- sweets: 1 factory, 2 godowns, 57 branches (60 sites, more than one page)
INSERT INTO core10.sites(id,tenant_id,business_id,kind,label,request_key)
 SELECT 881100+i,881,8811,CASE WHEN i=1 THEN 'factory' WHEN i<=3 THEN 'godown' ELSE 'showroom' END,
  CASE WHEN i=1 THEN 'Central factory' WHEN i<=3 THEN 'Godown '||(i-1) ELSE 'Branch '||(i-3) END,'od-s-'||i FROM generate_series(1,60) i;
INSERT INTO core10.sites(id,tenant_id,business_id,kind,label,request_key) VALUES
 (881201,881,8812,'warehouse','Paint warehouse','od-s-p1'),(881202,881,8812,'showroom','Paint shop','od-s-p2'),
 (881301,881,8813,'warehouse','Retail warehouse','od-s-r1'),(882101,882,8821,'showroom','Other shop','od-s-o1');
INSERT INTO core10.stock_locations(id,tenant_id,business_id,site_id,code) SELECT s.id*10+1,s.tenant_id,s.business_id,s.id,'MAIN' FROM core10.sites s WHERE s.tenant_id IN (881,882);
INSERT INTO core10.items(id,tenant_id,business_id,sku,name_en,name_bn) VALUES
 (88101,881,8811,'ROSOGOLLA','Rosogolla','রসগোল্লা'),(88102,881,8811,'SUGAR','Sugar','চিনি'),(88201,881,8812,'PAINT-W','White paint','সাদা রং'),
 (88301,881,8813,'SOAP','Soap','সাবান'),(88901,882,8821,'OTHER','Other item','অন্য পণ্য');
INSERT INTO core10.master_parties_v1(id,tenant_id,business_id,code,party_kind,name_en,name_bn) VALUES (88151,881,8811,'SUGAR-MILL','supplier','Sugar Mills','চিনি কল');
INSERT INTO core10.tenant_members(tenant_id,user_id,role) VALUES
 (881,'a8811111-1111-4111-8111-111111111111','tenant_owner'),(882,'a8855555-5555-4555-8555-555555555555','tenant_owner');
INSERT INTO core10.business_members(tenant_id,business_id,user_id,role) VALUES (881,8812,'a8833333-3333-4333-8333-333333333333','manager');
SELECT set_config('request.jwt.claims','{"sub":"a8811111-1111-4111-8111-111111111111"}',false);
DO $s$ DECLARE c jsonb; r record; BEGIN
 FOR r IN SELECT * FROM (VALUES (8811,8811011,88102,500),(8811,8811041,88101,40),(8811,8811051,88101,25),(8812,8812011,88201,120),(8813,8813011,88301,300)) v(b,l,i,q) LOOP
  c := core10.create_inventory_command_v1(r.b,'receive',NULL,r.l,r.i,r.q,NULL,'od-seed-'||r.l);
  c := core10.advance_inventory_command_v1((c->>'command_id')::bigint,'confirm',1,'od-seed-c-'||r.l);
  c := core10.advance_inventory_command_v1((c->>'command_id')::bigint,'post',2,'od-seed-p-'||r.l);
 END LOOP;
 PERFORM core10.create_inventory_command_v1(8811,'transfer',8811011,8811041,88102,50,NULL,'od-seed-xfer');
 PERFORM core10.control_set_v1(8811,NULL,'procurement.purchase_order',true,0::smallint,'{"separate_approver":false}',NULL,false,0,'od fixture','od-ctl-0001');
 c := core10.procurement_save_po_v1(8811,NULL,881101,88151,'[{"item_id":88102,"quantity":200,"unit_price":95}]',NULL,NULL,0,'od-po-0001');
 PERFORM core10.procurement_advance_po_v1((c->>'po_id')::bigint,'approve',1,'od-apv-0001');
END $s$;
