-- B-012 / 0203 race fixture: committed synthetic tenant (disposable PG17 only).
\set ON_ERROR_STOP on
INSERT INTO core10.templates(code,source_status,demo_allowed) VALUES ('sweets_bakery','available',true) ON CONFLICT (code) DO NOTHING;
INSERT INTO core10.tenants(id,slug) VALUES (741,'np03a-prace-a');
INSERT INTO core10.legal_entities(id,tenant_id,label) VALUES (7410,741,'PRace A');
INSERT INTO core10.businesses(id,tenant_id,legal_entity_id,slug,template_code,request_key) VALUES (7411,741,7410,'np03a-prace-a','sweets_bakery','np03a-prace-ba');
INSERT INTO core10.sites(id,tenant_id,business_id,kind,label,request_key) VALUES (74111,741,7411,'godown','Godown','np03a-prace-s1');
INSERT INTO core10.stock_locations(id,tenant_id,business_id,site_id,code) VALUES (741111,741,7411,74111,'G');
INSERT INTO core10.items(id,tenant_id,business_id,sku,name_en) VALUES (74101,741,7411,'PR-SUGAR','Race sugar');
INSERT INTO core10.master_parties_v1(id,tenant_id,business_id,code,party_kind,name_en) VALUES (74151,741,7411,'PR-SUP','supplier','Race supplier');
INSERT INTO core10.tenant_members(tenant_id,user_id,role) VALUES (741,'a7411111-1111-4111-8111-111111111111','tenant_owner');
SELECT set_config('request.jwt.claims','{"sub":"a7411111-1111-4111-8111-111111111111"}',false);
SELECT core10.control_set_v1(7411,NULL,'procurement.purchase_order',true,0::smallint,'{"separate_approver":false}',NULL,false,0,'race fixture','prace-ctl-0001');
SELECT core10.procurement_advance_po_v1((core10.procurement_save_po_v1(7411,NULL,74111,74151,'[{"item_id":74101,"quantity":10,"unit_price":5}]',NULL,NULL,0,'prace-po-0001')->>'po_id')::bigint,'approve',1,'prace-apv-0001');
SELECT core10.procurement_advance_po_v1((core10.procurement_save_po_v1(7411,NULL,74111,74151,'[{"item_id":74101,"quantity":10,"unit_price":5}]',NULL,NULL,0,'prace-po-0002')->>'po_id')::bigint,'approve',1,'prace-apv-0002');
SELECT core10.procurement_inspect_v1((core10.procurement_receive_v1((SELECT id FROM core10.purchase_orders_v1 WHERE request_key='prace-po-0002'),741111,
 '[{"line_no":1,"quantity":10}]',NULL,'prace-grn-0001')->>'grn_id')::bigint,'[{"line_no":1,"accepted_qty":10}]',1,'prace-qc-0001');
