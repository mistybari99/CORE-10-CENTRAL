-- B-012 / 0209 race fixture: committed synthetic tenant 1903 (disposable PG17 only).
\set ON_ERROR_STOP on
INSERT INTO core10.templates(code,source_status,demo_allowed) VALUES ('sweets_bakery','available',true) ON CONFLICT (code) DO NOTHING;
INSERT INTO core10.tenants(id,slug) VALUES (1903,'np03a-lrace-a');
INSERT INTO core10.legal_entities(id,tenant_id,label) VALUES (19030,1903,'LRace A');
INSERT INTO core10.businesses(id,tenant_id,legal_entity_id,slug,template_code,request_key) VALUES (19031,1903,19030,'np03a-lrace-a','sweets_bakery','np03a-lrace-ba');
INSERT INTO core10.sites(id,tenant_id,business_id,kind,label,request_key) VALUES (190311,1903,19031,'godown','Godown','np03a-lrace-s1');
INSERT INTO core10.stock_locations(id,tenant_id,business_id,site_id,code) VALUES (1903111,1903,19031,190311,'G');
INSERT INTO core10.items(id,tenant_id,business_id,sku,name_en) VALUES (19301,1903,19031,'LR-SUGAR','Race sugar');
INSERT INTO core10.master_parties_v1(id,tenant_id,business_id,code,party_kind,name_en) VALUES (19351,1903,19031,'LR-SUP','supplier','Race supplier');
INSERT INTO core10.tenant_members(tenant_id,user_id,role) VALUES (1903,'19030000-0000-4000-8000-000000000001','tenant_owner');
SELECT set_config('request.jwt.claims','{"sub":"19030000-0000-4000-8000-000000000001"}',false);
SELECT core10.control_set_v1(19031,NULL,'procurement.purchase_order',true,0::smallint,'{"separate_approver":false}',NULL,false,0,'race fixture','lrace-ctl-0001');
SELECT core10.control_set_v1(19031,NULL,'inventory.lot_control',true,0::smallint,'{"reason_required":false}',NULL,false,0,'race fixture','lrace-ctl-0002');
-- PO: 100 ordered; two posted receipts: LR-A (expires in 10 days) 30, LR-B (expires in 100 days) 30
SELECT core10.procurement_advance_po_v1((core10.procurement_save_po_v1(19031,NULL,190311,19351,'[{"item_id":19301,"quantity":100,"unit_price":5}]',NULL,NULL,0,'lrace-po-0001')->>'po_id')::bigint,'approve',1,'lrace-apv-0001');
SELECT core10.procurement_post_grn_v1((core10.procurement_inspect_v1((core10.procurement_receive_v1((SELECT id FROM core10.purchase_orders_v1 WHERE request_key='lrace-po-0001'),1903111,
 jsonb_build_array(jsonb_build_object('line_no',1,'quantity',30,'lot_code','LR-A','expires_on',(current_date+10)::text)),NULL,'lrace-grn-0001')->>'grn_id')::bigint,
 '[{"line_no":1,"accepted_qty":30}]',1,'lrace-qc-0001')->>'grn_id')::bigint,2,'lrace-post-0001');
SELECT core10.procurement_post_grn_v1((core10.procurement_inspect_v1((core10.procurement_receive_v1((SELECT id FROM core10.purchase_orders_v1 WHERE request_key='lrace-po-0001'),1903111,
 jsonb_build_array(jsonb_build_object('line_no',1,'quantity',30,'lot_code','LR-B','expires_on',(current_date+100)::text)),NULL,'lrace-grn-0002')->>'grn_id')::bigint,
 '[{"line_no":1,"accepted_qty":30}]',1,'lrace-qc-0002')->>'grn_id')::bigint,2,'lrace-post-0002');
