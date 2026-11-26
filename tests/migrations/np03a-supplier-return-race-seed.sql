-- B-012 / 0207 race fixture: committed synthetic tenant 1703 (disposable PG17 only).
\set ON_ERROR_STOP on
INSERT INTO core10.templates(code,source_status,demo_allowed) VALUES ('sweets_bakery','available',true) ON CONFLICT (code) DO NOTHING;
INSERT INTO core10.tenants(id,slug) VALUES (1703,'np03a-rrace-a');
INSERT INTO core10.legal_entities(id,tenant_id,label) VALUES (17030,1703,'RRace A');
INSERT INTO core10.businesses(id,tenant_id,legal_entity_id,slug,template_code,request_key) VALUES (17031,1703,17030,'np03a-rrace-a','sweets_bakery','np03a-rrace-ba');
INSERT INTO core10.sites(id,tenant_id,business_id,kind,label,request_key) VALUES (170311,1703,17031,'godown','Godown','np03a-rrace-s1');
INSERT INTO core10.stock_locations(id,tenant_id,business_id,site_id,code) VALUES (1703111,1703,17031,170311,'G');
INSERT INTO core10.items(id,tenant_id,business_id,sku,name_en) VALUES (17301,1703,17031,'RR-SUGAR','Race sugar');
INSERT INTO core10.master_parties_v1(id,tenant_id,business_id,code,party_kind,name_en) VALUES (17351,1703,17031,'RR-SUP','supplier','Race supplier');
INSERT INTO core10.tenant_members(tenant_id,user_id,role) VALUES (1703,'17030000-0000-4000-8000-000000000001','tenant_owner');
SELECT set_config('request.jwt.claims','{"sub":"17030000-0000-4000-8000-000000000001"}',false);
SELECT core10.control_set_v1(17031,NULL,'procurement.purchase_order',true,0::smallint,'{"separate_approver":false}',NULL,false,0,'race fixture','rrace-ctl-0001');
SELECT core10.control_set_v1(17031,NULL,'procurement.supplier_return',true,0::smallint,'{"separate_approver":false}',NULL,false,0,'race fixture','rrace-ctl-0002');
-- PO 1: 100 ordered, GRN A posted with 50 accepted (returnable 50)
SELECT core10.procurement_advance_po_v1((core10.procurement_save_po_v1(17031,NULL,170311,17351,'[{"item_id":17301,"quantity":100,"unit_price":5}]',NULL,NULL,0,'rrace-po-0001')->>'po_id')::bigint,'approve',1,'rrace-apv-0001');
SELECT core10.procurement_post_grn_v1((core10.procurement_inspect_v1((core10.procurement_receive_v1((SELECT id FROM core10.purchase_orders_v1 WHERE request_key='rrace-po-0001'),1703111,
 '[{"line_no":1,"quantity":50,"lot_code":"RR-LOT-1"}]',NULL,'rrace-grn-0001')->>'grn_id')::bigint,'[{"line_no":1,"accepted_qty":50}]',1,'rrace-qc-0001')->>'grn_id')::bigint,2,'rrace-post-0001');
-- PO 2: 10 ordered, GRN B received (unposted) holds all 10 open units
SELECT core10.procurement_advance_po_v1((core10.procurement_save_po_v1(17031,NULL,170311,17351,'[{"item_id":17301,"quantity":10,"unit_price":5}]',NULL,NULL,0,'rrace-po-0002')->>'po_id')::bigint,'approve',1,'rrace-apv-0002');
SELECT core10.procurement_receive_v1((SELECT id FROM core10.purchase_orders_v1 WHERE request_key='rrace-po-0002'),1703111,'[{"line_no":1,"quantity":10}]',NULL,'rrace-grn-0002');
