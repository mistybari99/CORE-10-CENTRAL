-- B-012 / 0203: purchase order -> GRN -> quality check -> stock (disposable PG17, rolled back).
-- Personas: tenant owner, business owner (approver), manager (buyer), godown staff (receiver/inspector), other tenant.
-- Proves Master supplier/item rules, Owner Control (CONTROL_DISABLED, limits, QC/lot/expiry rules, stages fail closed),
-- maker-checker, versions, replay, partial and full receipt, rejected quantity never reaches stock, scoped reads.
\set ON_ERROR_STOP on
BEGIN;
INSERT INTO core10.templates(code,source_status,demo_allowed) VALUES ('sweets_bakery','available',true) ON CONFLICT (code) DO NOTHING;
INSERT INTO core10.tenants(id,slug) VALUES (911,'proc-a'),(912,'proc-b');
INSERT INTO core10.legal_entities(id,tenant_id,label) VALUES (9110,911,'Proc A'),(9120,912,'Proc B');
INSERT INTO core10.businesses(id,tenant_id,legal_entity_id,slug,template_code,request_key) VALUES
 (9111,911,9110,'proc-a1','sweets_bakery','proc-b1'),(9112,911,9110,'proc-a2','sweets_bakery','proc-b2'),
 (9121,912,9120,'proc-b1','sweets_bakery','proc-b3');
INSERT INTO core10.sites(id,tenant_id,business_id,kind,label,request_key) VALUES
 (91111,911,9111,'godown','Godown','proc-s1'),(91112,911,9111,'showroom','Branch','proc-s2'),(91121,911,9112,'factory','Other biz','proc-s3');
INSERT INTO core10.stock_locations(id,tenant_id,business_id,site_id,code) VALUES
 (911111,911,9111,91111,'G'),(911121,911,9111,91112,'S'),(911211,911,9112,91121,'O');
INSERT INTO core10.items(id,tenant_id,business_id,sku,name_en,name_bn,status) VALUES
 (91101,911,9111,'SUGAR','Sugar','চিনি','active'),(91102,911,9111,'FLOUR','Flour','আটা','active'),
 (91103,911,9111,'OLD','Old','পুরোনো','inactive');
INSERT INTO core10.master_parties_v1(id,tenant_id,business_id,code,party_kind,name_en,name_bn,status) VALUES
 (91151,911,9111,'SUP-1','supplier','Sugar Mills','চিনি কল','active'),(91152,911,9111,'CUS-1','customer','A customer',NULL,'active'),
 (91153,911,9111,'SUP-2','supplier','Blocked supplier',NULL,'blocked'),(91154,911,9112,'SUP-X','both','Other biz supplier',NULL,'active');
INSERT INTO core10.tenant_members(tenant_id,user_id,role) VALUES
 (911,'f1111111-1111-4111-8111-111111111111','tenant_owner'),(912,'f5555555-5555-4555-8555-555555555555','tenant_owner');
INSERT INTO core10.business_members(tenant_id,business_id,user_id,role) VALUES
 (911,9111,'f2222222-2222-4222-8222-222222222222','business_owner'),(911,9111,'f3333333-3333-4333-8333-333333333333','manager');
INSERT INTO core10.site_grants(tenant_id,business_id,site_id,user_id,actions) VALUES
 (911,9111,91111,'f4444444-4444-4444-8444-444444444444','{stock.read,stock.post}');

CREATE FUNCTION pg_temp.as_user(p text) RETURNS void LANGUAGE sql AS $$
 SELECT set_config('request.jwt.claims',json_build_object('sub',p)::text,true), set_config('request.jwt.claim.sub',p,true) $$;
CREATE FUNCTION pg_temp.ok(p boolean, m text) RETURNS void LANGUAGE plpgsql AS $$
 BEGIN IF p IS DISTINCT FROM true THEN RAISE EXCEPTION 'PROCT_ASSERT:%',m; END IF; END $$;
CREATE FUNCTION pg_temp.expect(q text, pre text) RETURNS void LANGUAGE plpgsql AS $$
 BEGIN BEGIN EXECUTE q; EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE pre||'%' THEN RETURN; END IF;
  RAISE EXCEPTION 'PROCT_WRONG_ERROR expected=% got=% q=%',pre,SQLERRM,left(q,160); END;
  RAISE EXCEPTION 'PROCT_EXPECTED_DENIAL:% q=%',pre,left(q,160); END $$;
CREATE FUNCTION pg_temp.cset(f text,e boolean,g int,p jsonb,v int,key text) RETURNS jsonb LANGUAGE sql AS $$
 SELECT core10.control_set_v1(9111,NULL,f,e,g::smallint,p,NULL,false,v,'test control change',key) $$;
CREATE FUNCTION pg_temp.po(id bigint,site bigint,sup bigint,l jsonb,v int,key text) RETURNS jsonb LANGUAGE sql AS $$
 SELECT core10.procurement_save_po_v1(9111,id,site,sup,l,NULL,NULL,v,key) $$;
CREATE FUNCTION pg_temp.bal(l bigint,i bigint) RETURNS numeric LANGUAGE sql AS $$
 SELECT coalesce((SELECT on_hand FROM core10.stock_balances_v1 WHERE location_id=l AND item_id=i),0) $$;
\set L1 '[{"item_id":91101,"quantity":100,"unit_price":50},{"item_id":91102,"quantity":40,"unit_price":30}]'

SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('f3333333-3333-4333-8333-333333333333');
-- ---------- purchase order: Master supplier and item rules, replay, edit ----------
SELECT pg_temp.po(NULL,91111,91151,:'L1'::jsonb,0,'proc-po-0001') AS p1 \gset
SELECT pg_temp.ok((:'p1'::jsonb->>'status')='draft' AND (:'p1'::jsonb->>'total_amount')::numeric=6200 AND (:'p1'::jsonb->>'supplier_name_bn')='চিনি কল','draft PO with total and Bangla supplier');
SELECT pg_temp.ok((pg_temp.po(NULL,91111,91151,:'L1'::jsonb,0,'proc-po-0001')->>'replayed')::boolean,'PO replay');
SELECT pg_temp.expect($q$SELECT pg_temp.po(NULL,91111,91151,'[{"item_id":91101,"quantity":1,"unit_price":1}]',0,'proc-po-0001')$q$,'PROC_REPLAY_CONFLICT');
SELECT pg_temp.expect($q$SELECT pg_temp.po(NULL,91111,91152,'[{"item_id":91101,"quantity":1,"unit_price":1}]',0,'proc-po-bad1')$q$,'PROC_SUPPLIER_INVALID');
SELECT pg_temp.expect($q$SELECT pg_temp.po(NULL,91111,91153,'[{"item_id":91101,"quantity":1,"unit_price":1}]',0,'proc-po-bad2')$q$,'PROC_SUPPLIER_INVALID');
SELECT pg_temp.expect($q$SELECT pg_temp.po(NULL,91111,91154,'[{"item_id":91101,"quantity":1,"unit_price":1}]',0,'proc-po-bad3')$q$,'PROC_SUPPLIER_INVALID');
SELECT pg_temp.expect($q$SELECT pg_temp.po(NULL,91111,91151,'[{"item_id":91103,"quantity":1,"unit_price":1}]',0,'proc-po-bad4')$q$,'PROC_ITEM_NOT_USABLE');
SELECT pg_temp.expect($q$SELECT pg_temp.po(NULL,91111,91151,'[{"item_id":91101,"quantity":1,"unit_price":1},{"item_id":91101,"quantity":2,"unit_price":1}]',0,'proc-po-bad5')$q$,'PROC_LINES_DUPLICATE_ITEM');
SELECT pg_temp.expect($q$SELECT pg_temp.po(NULL,91111,91151,'[{"item_id":91101,"quantity":-1,"unit_price":1}]',0,'proc-po-bad6')$q$,'PROC_LINES_INVALID');
SELECT pg_temp.expect($q$SELECT pg_temp.po(NULL,91111,91151,'[{"item_id":91101,"quantity":1,"unit_price":0.001}]',0,'proc-po-bad7')$q$,'PROC_LINES_INVALID');
SELECT pg_temp.expect($q$SELECT pg_temp.po(NULL,91121,91151,'[{"item_id":91101,"quantity":1,"unit_price":1}]',0,'proc-po-bad8')$q$,'PROC_SITE_SCOPE');
SELECT pg_temp.expect($q$SELECT pg_temp.po(NULL,91111,91151,'[]',0,'proc-po-bad9')$q$,'PROC_LINES_INVALID');
SELECT pg_temp.po((:'p1'::jsonb->>'po_id')::bigint,91111,91151,'[{"item_id":91101,"quantity":120,"unit_price":50},{"item_id":91102,"quantity":40,"unit_price":30}]',1,'proc-po-edit1') AS p1 \gset
SELECT pg_temp.ok((:'p1'::jsonb->>'version')='2' AND (:'p1'::jsonb->>'total_amount')::numeric=7200,'draft edited to v2');
SELECT pg_temp.expect($q$SELECT pg_temp.po($q$||(:'p1'::jsonb->>'po_id')||$q$,91111,91151,'[{"item_id":91101,"quantity":1,"unit_price":1}]',1,'proc-po-edit2')$q$,'PROC_STALE_OR_NOT_DRAFT');
SELECT pg_temp.as_user('f4444444-4444-4444-8444-444444444444');
SELECT pg_temp.expect($q$SELECT pg_temp.po(NULL,91111,91151,'[{"item_id":91101,"quantity":1,"unit_price":1}]',0,'proc-po-staff')$q$,'PROC_PERMISSION_DENIED');

-- ---------- approval and maker-checker ----------
SELECT pg_temp.as_user('f3333333-3333-4333-8333-333333333333');
SELECT pg_temp.expect($q$SELECT core10.procurement_advance_po_v1($q$||(:'p1'::jsonb->>'po_id')||$q$,'approve',2,'proc-apv-0001')$q$,'PROC_PERMISSION_DENIED');
SELECT pg_temp.as_user('f2222222-2222-4222-8222-222222222222');
SELECT pg_temp.expect($q$SELECT core10.procurement_advance_po_v1($q$||(:'p1'::jsonb->>'po_id')||$q$,'approve',1,'proc-apv-0002')$q$,'PROC_STALE_VERSION:2');
SELECT core10.procurement_advance_po_v1((:'p1'::jsonb->>'po_id')::bigint,'approve',2,'proc-apv-0003') AS p1 \gset
SELECT pg_temp.ok((:'p1'::jsonb->>'status')='approved','PO approved by the business owner');
SELECT pg_temp.as_user('f1111111-1111-4111-8111-111111111111');
SELECT pg_temp.po(NULL,91111,91151,'[{"item_id":91102,"quantity":10,"unit_price":30}]',0,'proc-po-0002') AS p2 \gset
SELECT pg_temp.expect($q$SELECT core10.procurement_advance_po_v1($q$||(:'p2'::jsonb->>'po_id')||$q$,'approve',1,'proc-apv-0004')$q$,'PROC_SAME_ACTOR');

-- ---------- receive, quality check, post (godown staff) ----------
SELECT pg_temp.as_user('f4444444-4444-4444-8444-444444444444');
SELECT pg_temp.expect($q$SELECT core10.procurement_receive_v1($q$||(:'p1'::jsonb->>'po_id')||$q$,911121,'[{"line_no":1,"quantity":1}]',NULL,'proc-grn-bad1')$q$,'PROC_LOCATION_SCOPE');
SELECT pg_temp.expect($q$SELECT core10.procurement_receive_v1($q$||(:'p1'::jsonb->>'po_id')||$q$,911111,'[{"line_no":1,"quantity":121}]',NULL,'proc-grn-bad2')$q$,'CONTROL_LIMIT:over_receipt_pct');
SELECT pg_temp.expect($q$SELECT core10.procurement_receive_v1($q$||(:'p1'::jsonb->>'po_id')||$q$,911111,'[{"line_no":1,"quantity":1,"lot_code":"OLD-1","expires_on":"2020-01-01"}]',NULL,'proc-grn-bad3')$q$,'PROC_LOT_EXPIRED');
SELECT pg_temp.expect($q$SELECT core10.procurement_receive_v1($q$||(:'p1'::jsonb->>'po_id')||$q$,911111,'[{"line_no":9,"quantity":1}]',NULL,'proc-grn-bad4')$q$,'PROC_LINES_INVALID');
SELECT pg_temp.expect($q$SELECT core10.procurement_receive_v1($q$||(:'p2'::jsonb->>'po_id')||$q$,911111,'[{"line_no":1,"quantity":1}]',NULL,'proc-grn-bad5')$q$,'PROC_PO_NOT_OPEN');
SELECT core10.procurement_receive_v1((:'p1'::jsonb->>'po_id')::bigint,911111,
 '[{"line_no":1,"quantity":60,"lot_code":"LOT-A1","manufactured_on":"2026-11-01","expires_on":"2027-11-01"},{"line_no":2,"quantity":40}]','DN-77','proc-grn-0001') AS g1 \gset
SELECT pg_temp.ok((:'g1'::jsonb->>'status')='received','GRN waits for QC');
SELECT pg_temp.ok((core10.procurement_receive_v1((:'p1'::jsonb->>'po_id')::bigint,911111,
 '[{"line_no":1,"quantity":60,"lot_code":"LOT-A1","manufactured_on":"2026-11-01","expires_on":"2027-11-01"},{"line_no":2,"quantity":40}]','DN-77','proc-grn-0001')->>'replayed')::boolean,'GRN replay');
SELECT pg_temp.expect($q$SELECT core10.procurement_receive_v1($q$||(:'p1'::jsonb->>'po_id')||$q$,911111,'[{"line_no":1,"quantity":61}]',NULL,'proc-grn-bad6')$q$,'CONTROL_LIMIT:over_receipt_pct');
SELECT pg_temp.expect($q$SELECT core10.procurement_post_grn_v1($q$||(:'g1'::jsonb->>'grn_id')||$q$,1,'proc-post-bad1')$q$,'PROC_INVALID_TRANSITION');
SELECT pg_temp.expect($q$SELECT core10.procurement_inspect_v1($q$||(:'g1'::jsonb->>'grn_id')||$q$,'[{"line_no":1,"accepted_qty":58}]',1,'proc-qc-bad1')$q$,'PROC_QC_LINES_INCOMPLETE');
SELECT pg_temp.expect($q$SELECT core10.procurement_inspect_v1($q$||(:'g1'::jsonb->>'grn_id')||$q$,'[{"line_no":1,"accepted_qty":61},{"line_no":2,"accepted_qty":40}]',1,'proc-qc-bad2')$q$,'PROC_QC_QUANTITY_INVALID');
SELECT core10.procurement_inspect_v1((:'g1'::jsonb->>'grn_id')::bigint,'[{"line_no":1,"accepted_qty":58,"notes":"2 bags torn"},{"line_no":2,"accepted_qty":40}]',1,'proc-qc-0001') AS g1 \gset
SELECT pg_temp.ok((:'g1'::jsonb->'lines'->0->>'rejected_qty')::numeric=2,'two rejected at QC');
SELECT core10.procurement_post_grn_v1((:'g1'::jsonb->>'grn_id')::bigint,2,'proc-post-0001') AS g1 \gset
SELECT pg_temp.ok((:'g1'::jsonb->>'status')='posted' AND (:'g1'::jsonb->'lines'->0->>'lot_id') IS NOT NULL,'GRN posted with lot');
SELECT pg_temp.ok((core10.procurement_post_grn_v1((:'g1'::jsonb->>'grn_id')::bigint,2,'proc-post-0001')->>'replayed')::boolean,'post replay');
RESET ROLE;
SELECT pg_temp.ok(pg_temp.bal(911111,91101)=58 AND pg_temp.bal(911111,91102)=40,'only accepted quantity reached stock');
SELECT pg_temp.ok((SELECT status FROM core10.purchase_orders_v1 WHERE id=(:'p1'::jsonb->>'po_id')::bigint)='partially_received','PO partially received');
SELECT pg_temp.ok((SELECT expires_on FROM core10.inventory_lots_v1 WHERE business_id=9111 AND lot_code='LOT-A1')='2027-11-01','lot with expiry');
SET LOCAL ROLE authenticated;
SELECT pg_temp.expect($q$SELECT core10.procurement_receive_v1($q$||(:'p1'::jsonb->>'po_id')||$q$,911111,'[{"line_no":1,"quantity":63}]',NULL,'proc-grn-bad7')$q$,'CONTROL_LIMIT:over_receipt_pct');
SELECT core10.procurement_receive_v1((:'p1'::jsonb->>'po_id')::bigint,911111,'[{"line_no":1,"quantity":62,"lot_code":"LOT-A1","manufactured_on":"2026-11-01","expires_on":"2027-11-01"}]',NULL,'proc-grn-0002') AS g2 \gset
SELECT core10.procurement_post_grn_v1((x->>'grn_id')::bigint,2,'proc-post-0002') AS g2 FROM
 (SELECT core10.procurement_inspect_v1((:'g2'::jsonb->>'grn_id')::bigint,'[{"line_no":1,"accepted_qty":62}]',1,'proc-qc-0002') x) y \gset
RESET ROLE;
SELECT pg_temp.ok((SELECT status FROM core10.purchase_orders_v1 WHERE id=(:'p1'::jsonb->>'po_id')::bigint)='received','PO fully received');
SELECT pg_temp.ok(pg_temp.bal(911111,91101)=120,'sugar 120 in the godown');
SELECT pg_temp.ok((SELECT count(*) FROM core10.inventory_lots_v1 WHERE business_id=9111)=1,'same lot reused');
SET LOCAL ROLE authenticated;

-- ---------- Owner Control ----------
SELECT pg_temp.as_user('f1111111-1111-4111-8111-111111111111');
SELECT pg_temp.cset('procurement.purchase_order',true,0,'{"separate_approver":false,"max_po_amount":1000}',0,'proc-ctl-0001');
SELECT pg_temp.expect($q$SELECT pg_temp.po(NULL,91111,91151,'[{"item_id":91101,"quantity":100,"unit_price":11}]',0,'proc-lim-0001')$q$,'CONTROL_LIMIT:max_po_amount');
SELECT pg_temp.po(NULL,91111,91151,'[{"item_id":91101,"quantity":10,"unit_price":50},{"item_id":91102,"quantity":10,"unit_price":30}]',0,'proc-po-0003') AS p3 \gset
SELECT core10.procurement_advance_po_v1((:'p3'::jsonb->>'po_id')::bigint,'approve',1,'proc-apv-0005') AS p3 \gset
SELECT pg_temp.cset('procurement.goods_receipt',true,0,'{"qc_required":false,"require_lot":true,"over_receipt_pct":10}',0,'proc-ctl-0002');
SELECT pg_temp.expect($q$SELECT core10.procurement_receive_v1($q$||(:'p3'::jsonb->>'po_id')||$q$,911111,'[{"line_no":1,"quantity":11}]',NULL,'proc-lot-0001')$q$,'PROC_LOT_REQUIRED');
SELECT core10.procurement_receive_v1((:'p3'::jsonb->>'po_id')::bigint,911111,'[{"line_no":1,"quantity":11,"lot_code":"LOT-B1"}]',NULL,'proc-grn-0003') AS g3 \gset
SELECT pg_temp.ok((:'g3'::jsonb->>'status')='inspected','QC switched off: receipt is ready to post');
SELECT pg_temp.cset('inventory.stock_event',false,0,'{}',0,'proc-ctl-0003');
SELECT pg_temp.expect($q$SELECT core10.procurement_post_grn_v1($q$||(:'g3'::jsonb->>'grn_id')||$q$,1,'proc-post-0003')$q$,'CONTROL_DISABLED:inventory.stock_event');
SELECT pg_temp.cset('inventory.stock_event',true,0,'{}',1,'proc-ctl-0004');
SELECT pg_temp.ok((core10.procurement_post_grn_v1((:'g3'::jsonb->>'grn_id')::bigint,1,'proc-post-0003')->>'status')='posted','posted after the stock switch is back on');
SELECT pg_temp.cset('procurement.goods_receipt',false,0,'{}',1,'proc-ctl-0005');
SELECT pg_temp.expect($q$SELECT core10.procurement_receive_v1($q$||(:'p3'::jsonb->>'po_id')||$q$,911111,'[{"line_no":2,"quantity":1}]',NULL,'proc-off-0001')$q$,'CONTROL_DISABLED:procurement.goods_receipt');
SELECT pg_temp.cset('procurement.purchase_order',false,0,'{}',1,'proc-ctl-0006');
SELECT pg_temp.expect($q$SELECT pg_temp.po(NULL,91111,91151,'[{"item_id":91101,"quantity":1,"unit_price":1}]',0,'proc-off-0002')$q$,'CONTROL_DISABLED:procurement.purchase_order');
SELECT pg_temp.as_user('f3333333-3333-4333-8333-333333333333');
SELECT pg_temp.expect($q$SELECT pg_temp.po(NULL,91111,91151,'$q$||:'L1'||$q$'::jsonb,0,'proc-po-0001')$q$,'CONTROL_DISABLED:procurement.purchase_order');
SELECT pg_temp.as_user('f1111111-1111-4111-8111-111111111111');
SELECT pg_temp.cset('procurement.purchase_order',true,1,'{"separate_approver":false}',2,'proc-ctl-0007');
SELECT pg_temp.po(NULL,91111,91151,'[{"item_id":91101,"quantity":1,"unit_price":1}]',0,'proc-po-0004') AS p4 \gset
SELECT pg_temp.expect($q$SELECT core10.procurement_advance_po_v1($q$||(:'p4'::jsonb->>'po_id')||$q$,'approve',1,'proc-stg-0001')$q$,'PROC_APPROVAL_REQUIRED');
-- cancel and close
SELECT pg_temp.ok((core10.procurement_advance_po_v1((:'p4'::jsonb->>'po_id')::bigint,'cancel',1,'proc-cx-00001')->>'status')='cancelled','cancel a draft');
SELECT pg_temp.expect($q$SELECT core10.procurement_advance_po_v1($q$||(:'p3'::jsonb->>'po_id')||$q$,'cancel',3,'proc-cx-00002')$q$,'PROC_INVALID_TRANSITION');
SELECT pg_temp.ok((core10.procurement_advance_po_v1((:'p3'::jsonb->>'po_id')::bigint,'close',3,'proc-cx-00003')->>'status')='closed','short-close a partly received PO');

-- ---------- other tenant, reads ----------
SELECT pg_temp.as_user('f5555555-5555-4555-8555-555555555555');
SELECT pg_temp.expect($q$SELECT core10.procurement_list_pos_v1(9111)$q$,'PROC_SCOPE');
SELECT pg_temp.expect($q$SELECT core10.procurement_get_po_v1($q$||(:'p1'::jsonb->>'po_id')||$q$)$q$,'PROC_SCOPE');
SELECT pg_temp.expect($q$SELECT core10.procurement_receive_v1($q$||(:'p1'::jsonb->>'po_id')||$q$,911111,'[{"line_no":1,"quantity":1}]',NULL,'proc-foreign-1')$q$,'PROC_SCOPE');
SELECT pg_temp.expect($q$SELECT core10.procurement_advance_po_v1($q$||(:'p2'::jsonb->>'po_id')||$q$,'approve',1,'proc-foreign-2')$q$,'PROC_SCOPE');
SELECT pg_temp.as_user('f1111111-1111-4111-8111-111111111111');
SELECT pg_temp.ok(jsonb_array_length(core10.procurement_list_pos_v1(9111)->'items')=4,'owner sees four POs');
SELECT pg_temp.ok(jsonb_array_length(core10.procurement_list_pos_v1(9111,NULL,NULL,NULL,1)->'items')=1
 AND (core10.procurement_list_pos_v1(9111,NULL,NULL,NULL,1)->>'next_before_id') IS NOT NULL,'PO page cursor');
SELECT pg_temp.ok(jsonb_array_length(core10.procurement_get_po_v1((:'p1'::jsonb->>'po_id')::bigint)->'receipts')=2,'PO shows its two receipts');
SELECT pg_temp.expect($q$SELECT core10.procurement_list_pos_v1(9111,NULL,'bogus')$q$,'PROC_INVALID_FILTER');
SELECT pg_temp.as_user('f4444444-4444-4444-8444-444444444444');
SELECT pg_temp.ok((SELECT bool_and((x->>'site_id')::bigint=91111) FROM jsonb_array_elements(core10.procurement_list_pos_v1(9111)->'items') x),'godown staff sees godown POs only');
RESET ROLE;
SELECT pg_temp.ok(NOT EXISTS(SELECT 1 FROM core10.inventory_reconciliation_v1 WHERE NOT reconciled),'ledger reconciled');
SELECT pg_temp.ok((SELECT count(*) FROM core10.stock_movements WHERE business_id=9111 AND request_key NOT LIKE 'c10-grn-%')=0,'stock moved only by GRN posting');
SELECT pg_temp.ok((SELECT count(*) FROM core10.goods_receipt_lines_v1 l JOIN core10.goods_receipts_v1 g ON g.id=l.grn_id
 WHERE g.status='posted' AND l.accepted_qty>0 AND l.stock_movement_id IS NULL)=0,'every accepted posted line has its movement');
SELECT pg_temp.ok((SELECT count(*) FROM core10.purchase_orders_v1 WHERE business_id=9121)=0,'tenant B untouched');
SELECT pg_temp.ok((SELECT count(*) FROM core10.control_rpc_map_v1 WHERE rpc_name LIKE 'procurement_%' AND status='enforced' AND test_ref='tests/migrations/np03a-procurement-e2e.sql')=5,'five procurement writers enforced');
ROLLBACK;
\echo 'PASS np03a-procurement-e2e'
