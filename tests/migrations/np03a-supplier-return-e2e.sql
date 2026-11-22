-- B-012 / 0207: GRN cancel before posting, return to supplier after posting, lot expiry read (disposable PG17, rolled back).
-- Personas (tenant 1701): tenant owner (Owner Control), business owner (approver), manager (buyer / return poster),
-- godown staff (stock.read+post at the godown: receiver, return preparer), branch staff (stock.read at the branch only),
-- tenant 1702 owner (foreign). Proves: cancel frees open PO quantity and unblocks short-close / PO cancel; posted or
-- stale receipts cannot be cancelled; returns never exceed accepted - returned (drafts reserve), need stock, move stock
-- only through post_stock_event as a negative event at the GRN location, raise returned_qty on GRN and PO lines;
-- Owner Control CONTROL_DISABLED:procurement.supplier_return / procurement.goods_receipt / inventory.stock_event,
-- reason / separate approver / max quantity params; replay and replay conflict; cross-tenant denial; canonical audit;
-- lot expiry read scope (site-only staff, explicit site deny), days to expiry, N-days filter, keyset pages.
\set ON_ERROR_STOP on
BEGIN;
INSERT INTO core10.templates(code,source_status,demo_allowed) VALUES ('sweets_bakery','available',true) ON CONFLICT (code) DO NOTHING;
INSERT INTO core10.tenants(id,slug) VALUES (1701,'ret-a'),(1702,'ret-b');
INSERT INTO core10.legal_entities(id,tenant_id,label) VALUES (17010,1701,'Ret A'),(17020,1702,'Ret B');
INSERT INTO core10.businesses(id,tenant_id,legal_entity_id,slug,template_code,request_key) VALUES
 (17011,1701,17010,'ret-a1','sweets_bakery','ret-biz-a1'),(17021,1702,17020,'ret-b1','sweets_bakery','ret-biz-b1');
INSERT INTO core10.sites(id,tenant_id,business_id,kind,label,request_key) VALUES
 (170111,1701,17011,'godown','Godown','ret-site-1'),(170112,1701,17011,'showroom','Branch','ret-site-2'),
 (170211,1702,17021,'godown','B godown','ret-site-3');
INSERT INTO core10.stock_locations(id,tenant_id,business_id,site_id,code) VALUES
 (1701111,1701,17011,170111,'G'),(1701121,1701,17011,170112,'S'),(1702111,1702,17021,170211,'BG');
INSERT INTO core10.items(id,tenant_id,business_id,sku,name_en,name_bn,status) VALUES
 (17101,1701,17011,'SUGAR','Sugar','চিনি','active'),(17102,1701,17011,'FLOUR','Flour','আটা','active'),
 (17201,1702,17021,'SALT','Salt','লবণ','active');
INSERT INTO core10.master_parties_v1(id,tenant_id,business_id,code,party_kind,name_en,name_bn,status) VALUES
 (17151,1701,17011,'SUP-1','supplier','Sugar Mills','চিনি কল','active'),(17251,1702,17021,'SUP-B','supplier','B Mills',NULL,'active');
INSERT INTO core10.tenant_members(tenant_id,user_id,role) VALUES
 (1701,'17000000-0000-4000-8000-000000000001','tenant_owner'),(1702,'17000000-0000-4000-8000-000000000006','tenant_owner');
INSERT INTO core10.business_members(tenant_id,business_id,user_id,role) VALUES
 (1701,17011,'17000000-0000-4000-8000-000000000002','business_owner'),(1701,17011,'17000000-0000-4000-8000-000000000003','manager');
INSERT INTO core10.site_grants(tenant_id,business_id,site_id,user_id,actions) VALUES
 (1701,17011,170111,'17000000-0000-4000-8000-000000000004','{stock.read,stock.post}'),
 (1701,17011,170112,'17000000-0000-4000-8000-000000000005','{stock.read}');

CREATE FUNCTION pg_temp.as_user(p text) RETURNS void LANGUAGE sql AS $$
 SELECT set_config('request.jwt.claims',json_build_object('sub',p)::text,true), set_config('request.jwt.claim.sub',p,true) $$;
CREATE FUNCTION pg_temp.u(n int) RETURNS text LANGUAGE sql AS $$ SELECT '17000000-0000-4000-8000-00000000000'||n $$;
CREATE FUNCTION pg_temp.ok(p boolean, m text) RETURNS void LANGUAGE plpgsql AS $$
 BEGIN IF p IS DISTINCT FROM true THEN RAISE EXCEPTION 'RETT_ASSERT:%',m; END IF; END $$;
CREATE FUNCTION pg_temp.expect(q text, pre text) RETURNS void LANGUAGE plpgsql AS $$
 BEGIN BEGIN EXECUTE q; EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE pre||'%' THEN RETURN; END IF;
  RAISE EXCEPTION 'RETT_WRONG_ERROR expected=% got=% q=%',pre,SQLERRM,left(q,160); END;
  RAISE EXCEPTION 'RETT_EXPECTED_DENIAL:% q=%',pre,left(q,160); END $$;
CREATE FUNCTION pg_temp.cset(f text,e boolean,p jsonb,v int,key text) RETURNS jsonb LANGUAGE sql AS $$
 SELECT core10.control_set_v1(17011,NULL,f,e,0::smallint,p,NULL,false,v,'test control change',key) $$;
CREATE FUNCTION pg_temp.bal(l bigint,i bigint) RETURNS numeric LANGUAGE sql AS $$
 SELECT coalesce((SELECT on_hand FROM core10.stock_balances_v1 WHERE location_id=l AND item_id=i),0) $$;
-- create + approve a PO (manager raises, business owner approves); returns the approved PO json
CREATE FUNCTION pg_temp.po(site bigint,l jsonb,key text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE p jsonb; BEGIN
 PERFORM pg_temp.as_user(pg_temp.u(3));
 p := core10.procurement_save_po_v1(17011,NULL,site,17151,l,NULL,NULL,0,key||'-s');
 PERFORM pg_temp.as_user(pg_temp.u(2));
 RETURN core10.procurement_advance_po_v1((p->>'po_id')::bigint,'approve',1,key||'-a');
END $$;
-- receive -> QC (accept as given) -> post, by a given actor
CREATE FUNCTION pg_temp.grn(who int,po bigint,loc bigint,l jsonb,qc jsonb,key text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE g jsonb; BEGIN
 PERFORM pg_temp.as_user(pg_temp.u(who));
 g := core10.procurement_receive_v1(po,loc,l,NULL,key||'-r');
 g := core10.procurement_inspect_v1((g->>'grn_id')::bigint,qc,1,key||'-q');
 RETURN core10.procurement_post_grn_v1((g->>'grn_id')::bigint,2,key||'-p');
END $$;
SELECT (current_date+10)::text AS exp10, (current_date+200)::text AS exp200 \gset

SET LOCAL ROLE authenticated;
-- ---------- PO 1 at the godown, GRN 1 posted with two lots ----------
SELECT pg_temp.po(170111,'[{"item_id":17101,"quantity":100,"unit_price":50},{"item_id":17102,"quantity":40,"unit_price":30}]','ret-po1') AS p1 \gset
SELECT (:'p1'::jsonb->>'po_id') AS po1 \gset
SELECT pg_temp.grn(4,:po1,1701111,
 ('[{"line_no":1,"quantity":60,"lot_code":"L-SUG-10","expires_on":"'||:'exp10'||'"},{"line_no":2,"quantity":40,"lot_code":"L-FLR-200","expires_on":"'||:'exp200'||'"}]')::jsonb,
 '[{"line_no":1,"accepted_qty":58},{"line_no":2,"accepted_qty":40}]','ret-g1') AS g1 \gset
SELECT (:'g1'::jsonb->>'grn_id') AS grn1 \gset
SELECT pg_temp.ok((:'g1'::jsonb->>'status')='posted' AND (:'g1'::jsonb->'lines'->0->>'returned_qty')::numeric=0,'GRN 1 posted, nothing returned');

-- ---------- a) GRN cancel ----------
SELECT pg_temp.as_user(pg_temp.u(4));
SELECT core10.procurement_receive_v1(:po1,1701111,'[{"line_no":1,"quantity":42}]','DN-2','ret-g2-r') AS g2 \gset
SELECT (:'g2'::jsonb->>'grn_id') AS grn2 \gset
SELECT pg_temp.expect($q$SELECT core10.procurement_receive_v1($q$||:po1||$q$,1701111,'[{"line_no":1,"quantity":1}]',NULL,'ret-g3-bad')$q$,'CONTROL_LIMIT:over_receipt_pct');
RESET ROLE;
SELECT pg_temp.as_user(pg_temp.u(1));
SELECT pg_temp.ok((core10.owner_business_sites_v1(17011)->'items'->0->>'receipts_waiting')::int=1,'dashboard: one receipt waiting before cancel');
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user(pg_temp.u(5));
SELECT pg_temp.expect($q$SELECT core10.procurement_cancel_grn_v1($q$||:grn2||$q$,1,'wrong supplier','ret-cx-bad1')$q$,'PROC_PERMISSION_DENIED');
SELECT pg_temp.as_user(pg_temp.u(6));
SELECT pg_temp.expect($q$SELECT core10.procurement_cancel_grn_v1($q$||:grn2||$q$,1,'wrong supplier','ret-cx-bad2')$q$,'PROC_SCOPE');
SELECT pg_temp.as_user(pg_temp.u(4));
SELECT pg_temp.expect($q$SELECT core10.procurement_cancel_grn_v1($q$||:grn2||$q$,7,'wrong supplier','ret-cx-bad3')$q$,'PROC_STALE_VERSION:1');
SELECT pg_temp.expect($q$SELECT core10.procurement_cancel_grn_v1($q$||:grn2||$q$,1,'  ','ret-cx-bad4')$q$,'PROC_CANCEL_REASON_REQUIRED');
SELECT pg_temp.expect($q$SELECT core10.procurement_cancel_grn_v1($q$||:grn1||$q$,3,'too late','ret-cx-bad5')$q$,'PROC_INVALID_TRANSITION');
SELECT core10.procurement_cancel_grn_v1(:grn2,1,'wrong delivery note','ret-cx-0001') AS g2 \gset
SELECT pg_temp.ok((:'g2'::jsonb->>'status')='cancelled' AND (:'g2'::jsonb->>'cancel_reason')='wrong delivery note'
 AND (:'g2'::jsonb->>'cancelled_by')=pg_temp.u(4),'receiver cancelled an unposted GRN');
SELECT pg_temp.ok((core10.procurement_cancel_grn_v1(:grn2,1,'wrong delivery note','ret-cx-0001')->>'replayed')::boolean,'cancel replay');
SELECT pg_temp.expect($q$SELECT core10.procurement_cancel_grn_v1($q$||:grn2||$q$,1,'another reason','ret-cx-0001')$q$,'PROC_REPLAY_CONFLICT');
SELECT pg_temp.expect($q$SELECT core10.procurement_inspect_v1($q$||:grn2||$q$,'[{"line_no":1,"accepted_qty":42}]',2,'ret-cx-insp')$q$,'PROC_INVALID_TRANSITION');
SELECT pg_temp.expect($q$SELECT core10.procurement_post_grn_v1($q$||:grn2||$q$,2,'ret-cx-post')$q$,'PROC_INVALID_TRANSITION');
SELECT pg_temp.expect($q$SELECT core10.procurement_cancel_grn_v1($q$||:grn2||$q$,2,'again please','ret-cx-again')$q$,'PROC_INVALID_TRANSITION');
-- the freed 42 can be received again; an inspected receipt can be cancelled by the business owner (can_manage), not by a
-- buyer-manager who did not receive it
SELECT core10.procurement_receive_v1(:po1,1701111,'[{"line_no":1,"quantity":42,"lot_code":"L-SUG-NOEXP"}]',NULL,'ret-g3-r') AS g3 \gset
SELECT core10.procurement_inspect_v1((:'g3'::jsonb->>'grn_id')::bigint,'[{"line_no":1,"accepted_qty":42}]',1,'ret-g3-q') AS g3 \gset
SELECT pg_temp.as_user(pg_temp.u(3));
SELECT pg_temp.expect($q$SELECT core10.procurement_cancel_grn_v1($q$||(:'g3'::jsonb->>'grn_id')||$q$,2,'not my receipt','ret-cx-bad6')$q$,'PROC_PERMISSION_DENIED');
SELECT pg_temp.as_user(pg_temp.u(2));
SELECT pg_temp.ok((core10.procurement_cancel_grn_v1((:'g3'::jsonb->>'grn_id')::bigint,2,'supplier recalled batch','ret-cx-0002')->>'status')='cancelled','business owner cancelled an inspected GRN received by staff');
SELECT pg_temp.grn(4,:po1,1701111,'[{"line_no":1,"quantity":42,"lot_code":"L-SUG-NOEXP"}]','[{"line_no":1,"accepted_qty":42}]','ret-g4') AS g4 \gset
RESET ROLE;
SELECT pg_temp.ok((SELECT status FROM core10.purchase_orders_v1 WHERE id=:po1)='received','PO 1 fully received after cancel + new receipt');
SELECT pg_temp.ok(pg_temp.bal(1701111,17101)=100 AND pg_temp.bal(1701111,17102)=40,'cancelled receipts never reached stock');
SELECT pg_temp.as_user(pg_temp.u(1));
SELECT pg_temp.ok((core10.owner_business_sites_v1(17011)->'items'->0->>'receipts_waiting')::int=0,'dashboard: cancelled receipts are not waiting');
SET LOCAL ROLE authenticated;
-- short-close and PO cancel are no longer blocked by a cancelled receipt
SELECT pg_temp.po(170111,'[{"item_id":17101,"quantity":10,"unit_price":50}]','ret-po2') AS p2 \gset
SELECT pg_temp.as_user(pg_temp.u(4));
SELECT core10.procurement_receive_v1((:'p2'::jsonb->>'po_id')::bigint,1701111,'[{"line_no":1,"quantity":4}]',NULL,'ret-p2-g1') AS p2g \gset
SELECT pg_temp.ok((core10.procurement_cancel_grn_v1((:'p2g'::jsonb->>'grn_id')::bigint,1,'short shipment','ret-p2-cx')->>'status')='cancelled','PO 2 receipt cancelled');
SELECT pg_temp.as_user(pg_temp.u(2));
SELECT pg_temp.ok((core10.procurement_advance_po_v1((:'p2'::jsonb->>'po_id')::bigint,'cancel',2,'ret-p2-pocx')->>'status')='cancelled','PO with only cancelled receipts can be cancelled');
SELECT pg_temp.po(170111,'[{"item_id":17101,"quantity":10,"unit_price":50},{"item_id":17102,"quantity":10,"unit_price":30}]','ret-po3') AS p3 \gset
SELECT pg_temp.grn(4,(:'p3'::jsonb->>'po_id')::bigint,1701111,'[{"line_no":1,"quantity":10}]','[{"line_no":1,"accepted_qty":10}]','ret-p3-g1') AS p3g1 \gset
SELECT pg_temp.as_user(pg_temp.u(4));
SELECT core10.procurement_receive_v1((:'p3'::jsonb->>'po_id')::bigint,1701111,'[{"line_no":2,"quantity":3}]',NULL,'ret-p3-g2') AS p3g2 \gset
SELECT pg_temp.as_user(pg_temp.u(2));
SELECT pg_temp.expect($q$SELECT core10.procurement_advance_po_v1($q$||(:'p3'::jsonb->>'po_id')||$q$,'close',3,'ret-p3-close0')$q$,'PROC_INVALID_TRANSITION');
SELECT pg_temp.as_user(pg_temp.u(4));
SELECT core10.procurement_cancel_grn_v1((:'p3g2'::jsonb->>'grn_id')::bigint,1,'damaged in transit','ret-p3-cx') AS x \gset
SELECT pg_temp.as_user(pg_temp.u(2));
SELECT pg_temp.ok((core10.procurement_advance_po_v1((:'p3'::jsonb->>'po_id')::bigint,'close',3,'ret-p3-close1')->>'status')='closed','short-close works once the open receipt is cancelled');
-- Owner switch: cancel checks the goods-receipt control
SELECT pg_temp.po(170111,'[{"item_id":17101,"quantity":5,"unit_price":50}]','ret-po4') AS p4 \gset
SELECT pg_temp.as_user(pg_temp.u(4));
SELECT core10.procurement_receive_v1((:'p4'::jsonb->>'po_id')::bigint,1701111,'[{"line_no":1,"quantity":5}]',NULL,'ret-p4-g1') AS p4g \gset
SELECT pg_temp.as_user(pg_temp.u(1));
SELECT pg_temp.cset('procurement.goods_receipt',false,'{}',0,'ret-ctl-0001');
SELECT pg_temp.as_user(pg_temp.u(4));
SELECT pg_temp.expect($q$SELECT core10.procurement_cancel_grn_v1($q$||(:'p4g'::jsonb->>'grn_id')||$q$,1,'switched off','ret-p4-cx')$q$,'CONTROL_DISABLED:procurement.goods_receipt');
SELECT pg_temp.as_user(pg_temp.u(1));
SELECT pg_temp.cset('procurement.goods_receipt',true,'{}',1,'ret-ctl-0002');

-- ---------- b) return to supplier ----------
SELECT pg_temp.as_user(pg_temp.u(4));
SELECT pg_temp.expect($q$SELECT core10.procurement_save_return_v1($q$||:grn1||$q$,'[{"line_no":1,"quantity":10}]',NULL,'ret-r-bad1')$q$,'PROC_RETURN_REASON_REQUIRED');
SELECT pg_temp.expect($q$SELECT core10.procurement_save_return_v1($q$||:grn1||$q$,'[{"line_no":1,"quantity":10}]','x','ret-r-bad2')$q$,'PROC_RETURN_REASON_INVALID');
SELECT pg_temp.expect($q$SELECT core10.procurement_save_return_v1($q$||:grn2||$q$,'[{"line_no":1,"quantity":1}]','cancelled one','ret-r-bad3')$q$,'PROC_GRN_NOT_POSTED');
SELECT pg_temp.expect($q$SELECT core10.procurement_save_return_v1($q$||:grn1||$q$,'[{"line_no":9,"quantity":1}]','bad line','ret-r-bad4')$q$,'PROC_LINES_INVALID');
SELECT pg_temp.expect($q$SELECT core10.procurement_save_return_v1($q$||:grn1||$q$,'[{"line_no":1,"quantity":0.0001}]','bad qty','ret-r-bad5')$q$,'PROC_LINES_INVALID');
SELECT pg_temp.expect($q$SELECT core10.procurement_save_return_v1($q$||:grn1||$q$,'[{"line_no":1,"quantity":59}]','over return','ret-r-bad6')$q$,'PROC_RETURN_EXCEEDS_ACCEPTED');
SELECT core10.procurement_save_return_v1(:grn1,'[{"line_no":1,"quantity":10}]','damaged bags','ret-r1-save') AS r1 \gset
SELECT (:'r1'::jsonb->>'return_id') AS ret1 \gset
SELECT pg_temp.ok((:'r1'::jsonb->>'status')='draft' AND (:'r1'::jsonb->>'supplier_id')::bigint=17151
 AND (:'r1'::jsonb->'lines'->0->>'lot_id') IS NOT NULL,'return draft carries supplier and lot');
SELECT pg_temp.ok((core10.procurement_save_return_v1(:grn1,'[{"line_no":1,"quantity":10}]','damaged bags','ret-r1-save')->>'replayed')::boolean,'return draft replay');
SELECT pg_temp.expect($q$SELECT core10.procurement_save_return_v1($q$||:grn1||$q$,'[{"line_no":1,"quantity":11}]','damaged bags','ret-r1-save')$q$,'PROC_REPLAY_CONFLICT');
-- the draft reserves 10 of 58 accepted: 49 more is too much, 48 is fine (and cancelled again)
SELECT pg_temp.expect($q$SELECT core10.procurement_save_return_v1($q$||:grn1||$q$,'[{"line_no":1,"quantity":49}]','over return','ret-r-bad7')$q$,'PROC_RETURN_EXCEEDS_ACCEPTED');
SELECT core10.procurement_save_return_v1(:grn1,'[{"line_no":1,"quantity":48}]','all the rest','ret-r2-save') AS r2 \gset
SELECT pg_temp.ok((core10.procurement_advance_return_v1((:'r2'::jsonb->>'return_id')::bigint,'cancel',1,'ret-r2-cx')->>'status')='cancelled','preparer cancels own draft');
SELECT pg_temp.as_user(pg_temp.u(5));
SELECT pg_temp.expect($q$SELECT core10.procurement_save_return_v1($q$||:grn1||$q$,'[{"line_no":1,"quantity":1}]','branch staff','ret-r-bad8')$q$,'PROC_PERMISSION_DENIED');
SELECT pg_temp.expect($q$SELECT core10.procurement_advance_return_v1($q$||:ret1||$q$,'post',1,'ret-r-bad9')$q$,'PROC_PERMISSION_DENIED');
SELECT pg_temp.as_user(pg_temp.u(6));
SELECT pg_temp.expect($q$SELECT core10.procurement_save_return_v1($q$||:grn1||$q$,'[{"line_no":1,"quantity":1}]','foreign tenant','ret-r-bad10')$q$,'PROC_SCOPE');
SELECT pg_temp.expect($q$SELECT core10.procurement_advance_return_v1($q$||:ret1||$q$,'post',1,'ret-r-bad11')$q$,'PROC_SCOPE');
SELECT pg_temp.expect($q$SELECT core10.procurement_advance_return_v1($q$||:ret1||$q$,'cancel',1,'ret-r-bad12')$q$,'PROC_SCOPE');
SELECT pg_temp.as_user(pg_temp.u(4));
SELECT pg_temp.expect($q$SELECT core10.procurement_advance_return_v1($q$||:ret1||$q$,'post',1,'ret-r-bad13')$q$,'PROC_SAME_ACTOR');
SELECT pg_temp.as_user(pg_temp.u(3));
SELECT pg_temp.expect($q$SELECT core10.procurement_advance_return_v1($q$||:ret1||$q$,'post',2,'ret-r-bad14')$q$,'PROC_STALE_VERSION:1');
SELECT pg_temp.expect($q$SELECT core10.procurement_advance_return_v1($q$||:ret1||$q$,'ship',1,'ret-r-bad15')$q$,'PROC_INVALID_ACTION');
-- Owner switches: supplier-return control and the stock master switch
SELECT pg_temp.as_user(pg_temp.u(1));
SELECT pg_temp.cset('procurement.supplier_return',false,'{}',0,'ret-ctl-0003');
SELECT pg_temp.as_user(pg_temp.u(3));
SELECT pg_temp.expect($q$SELECT core10.procurement_advance_return_v1($q$||:ret1||$q$,'post',1,'ret-r1-post')$q$,'CONTROL_DISABLED:procurement.supplier_return');
SELECT pg_temp.as_user(pg_temp.u(4));
SELECT pg_temp.expect($q$SELECT core10.procurement_save_return_v1($q$||:grn1||$q$,'[{"line_no":1,"quantity":10}]','damaged bags','ret-r1-save')$q$,'CONTROL_DISABLED:procurement.supplier_return');
SELECT pg_temp.as_user(pg_temp.u(1));
SELECT pg_temp.cset('procurement.supplier_return',true,'{}',1,'ret-ctl-0004');
SELECT pg_temp.cset('inventory.stock_event',false,'{}',0,'ret-ctl-0005');
SELECT pg_temp.as_user(pg_temp.u(3));
SELECT pg_temp.expect($q$SELECT core10.procurement_advance_return_v1($q$||:ret1||$q$,'post',1,'ret-r1-post')$q$,'CONTROL_DISABLED:inventory.stock_event');
SELECT pg_temp.as_user(pg_temp.u(1));
SELECT pg_temp.cset('inventory.stock_event',true,'{}',1,'ret-ctl-0006');
SELECT pg_temp.as_user(pg_temp.u(3));
SELECT core10.procurement_advance_return_v1(:ret1,'post',1,'ret-r1-post') AS r1 \gset
SELECT pg_temp.ok((:'r1'::jsonb->>'status')='posted' AND (:'r1'::jsonb->'lines'->0->>'stock_movement_id') IS NOT NULL,'manager posted the return');
SELECT pg_temp.ok((core10.procurement_advance_return_v1(:ret1,'post',1,'ret-r1-post')->>'replayed')::boolean,'return post replay');
SELECT pg_temp.expect($q$SELECT core10.procurement_advance_return_v1($q$||:ret1||$q$,'post',2,'ret-r1-post2')$q$,'PROC_INVALID_TRANSITION');
SELECT pg_temp.expect($q$SELECT core10.procurement_advance_return_v1($q$||:ret1||$q$,'cancel',2,'ret-r1-cx')$q$,'PROC_PERMISSION_DENIED');
SELECT pg_temp.as_user(pg_temp.u(4));
SELECT pg_temp.expect($q$SELECT core10.procurement_advance_return_v1($q$||:ret1||$q$,'cancel',2,'ret-r1-cx')$q$,'PROC_INVALID_TRANSITION');
RESET ROLE;
SELECT pg_temp.ok(pg_temp.bal(1701111,17101)=100,'sugar 58+42+10 received, 10 returned');
SELECT pg_temp.ok((SELECT delta FROM core10.stock_movements WHERE id=(:'r1'::jsonb->'lines'->0->>'stock_movement_id')::bigint)=-10
 AND (SELECT location_id FROM core10.stock_movements WHERE id=(:'r1'::jsonb->'lines'->0->>'stock_movement_id')::bigint)=1701111,'negative event at the GRN location');
SELECT pg_temp.ok((SELECT returned_qty FROM core10.goods_receipt_lines_v1 WHERE grn_id=:grn1 AND line_no=1)=10
 AND (SELECT returned_qty FROM core10.purchase_order_lines_v1 WHERE po_id=:po1 AND line_no=1)=10
 AND (SELECT accepted_qty FROM core10.purchase_order_lines_v1 WHERE po_id=:po1 AND line_no=1)=100,'GRN and PO lines show returned 10, accepted unchanged');
SELECT pg_temp.ok((SELECT status FROM core10.purchase_orders_v1 WHERE id=:po1)='received','a return does not reopen the PO');
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user(pg_temp.u(1));
SELECT pg_temp.ok((SELECT (x->'lines'->0->>'returned_qty')::numeric FROM jsonb_array_elements(core10.procurement_get_po_v1(:po1)->'receipts') x
 WHERE (x->>'grn_id')::bigint=:grn1)=10 AND (core10.procurement_get_po_v1(:po1)->'lines'->0->>'returned_qty')::numeric=10
 AND jsonb_array_length((SELECT x->'returns' FROM jsonb_array_elements(core10.procurement_get_po_v1(:po1)->'receipts') x WHERE (x->>'grn_id')::bigint=:grn1))=2,
 'PO read shows returned quantities and both returns of GRN 1');
-- after posting, the remaining returnable is 58 - 10 = 48
SELECT pg_temp.as_user(pg_temp.u(4));
SELECT pg_temp.expect($q$SELECT core10.procurement_save_return_v1($q$||:grn1||$q$,'[{"line_no":1,"quantity":48.001}]','over return','ret-r-bad16')$q$,'PROC_RETURN_EXCEEDS_ACCEPTED');
-- posting re-checks accepted - returned under the lock even if a draft line was tampered with
SELECT core10.procurement_save_return_v1(:grn1,'[{"line_no":1,"quantity":1}]','tamper probe','ret-r5-save') AS r5 \gset
RESET ROLE;
UPDATE core10.supplier_return_lines_v1 SET quantity=49 WHERE return_id=(:'r5'::jsonb->>'return_id')::bigint;
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user(pg_temp.u(3));
SELECT pg_temp.expect($q$SELECT core10.procurement_advance_return_v1($q$||(:'r5'::jsonb->>'return_id')||$q$,'post',1,'ret-r5-post')$q$,'PROC_RETURN_EXCEEDS_ACCEPTED');
SELECT pg_temp.as_user(pg_temp.u(4));
SELECT pg_temp.ok((core10.procurement_advance_return_v1((:'r5'::jsonb->>'return_id')::bigint,'cancel',1,'ret-r5-cx')->>'status')='cancelled','tampered draft cancelled');
-- Owner params: max_return_qty, separate_approver off, reason optional
SELECT pg_temp.as_user(pg_temp.u(1));
SELECT pg_temp.cset('procurement.supplier_return',true,'{"max_return_qty":5,"separate_approver":false,"reason_required":false}',2,'ret-ctl-0007');
SELECT pg_temp.as_user(pg_temp.u(4));
SELECT pg_temp.expect($q$SELECT core10.procurement_save_return_v1($q$||:grn1||$q$,'[{"line_no":1,"quantity":6}]',NULL,'ret-r-bad17')$q$,'CONTROL_LIMIT:max_return_qty');
SELECT core10.procurement_save_return_v1(:grn1,'[{"line_no":1,"quantity":5}]',NULL,'ret-r3-save') AS r3 \gset
SELECT pg_temp.ok((core10.procurement_advance_return_v1((:'r3'::jsonb->>'return_id')::bigint,'post',1,'ret-r3-post')->>'status')='posted','preparer may post when separate_approver is off');
-- stock must be available: move 36 flour out of the godown (internal transfer, test setup), then return
RESET ROLE;
SELECT pg_temp.as_user(pg_temp.u(1));
SELECT core10.transfer_stock_v1(1701111,1701121,17102,36,'ret-setup-xfer-1') AS x \gset
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user(pg_temp.u(4));
SELECT pg_temp.expect($q$SELECT core10.procurement_save_return_v1($q$||:grn1||$q$,'[{"line_no":2,"quantity":5}]',NULL,'ret-r-bad18')$q$,'PROC_INSUFFICIENT_STOCK');
SELECT core10.procurement_save_return_v1(:grn1,'[{"line_no":2,"quantity":4}]',NULL,'ret-r4-save') AS r4 \gset
RESET ROLE;
SELECT pg_temp.as_user(pg_temp.u(1));
SELECT core10.transfer_stock_v1(1701111,1701121,17102,1,'ret-setup-xfer-2') AS x \gset
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user(pg_temp.u(4));
SELECT pg_temp.expect($q$SELECT core10.procurement_advance_return_v1($q$||(:'r4'::jsonb->>'return_id')||$q$,'post',1,'ret-r4-post')$q$,'PROC_INSUFFICIENT_STOCK');
SELECT pg_temp.as_user(pg_temp.u(3));
SELECT pg_temp.expect($q$SELECT core10.procurement_advance_return_v1($q$||(:'r4'::jsonb->>'return_id')||$q$,'cancel',1,'ret-r4-cx0')$q$,'PROC_PERMISSION_DENIED');
SELECT pg_temp.as_user(pg_temp.u(2));
SELECT pg_temp.ok((core10.procurement_advance_return_v1((:'r4'::jsonb->>'return_id')::bigint,'cancel',1,'ret-r4-cx')->>'status')='cancelled','business owner cancels a staff draft');
RESET ROLE;
SELECT pg_temp.ok(pg_temp.bal(1701111,17102)=3 AND pg_temp.bal(1701111,17101)=95,'flour 40-37, sugar 110-10-5');

-- ---------- c) lot expiry read ----------
-- a second PO at the branch receives the same sugar lot there (owner receives), to prove per-site totals
SET LOCAL ROLE authenticated;
SELECT pg_temp.po(170112,'[{"item_id":17101,"quantity":7,"unit_price":50}]','ret-po5') AS p5 \gset
SELECT pg_temp.grn(1,(:'p5'::jsonb->>'po_id')::bigint,1701121,('[{"line_no":1,"quantity":7,"lot_code":"L-SUG-10","expires_on":"'||:'exp10'||'"}]')::jsonb,
 '[{"line_no":1,"accepted_qty":7}]','ret-g5') AS g5 \gset
SELECT pg_temp.as_user(pg_temp.u(1));
SELECT core10.procurement_list_lots_v1(17011) AS lots \gset
SELECT pg_temp.ok(jsonb_array_length(:'lots'::jsonb->'items')=3,'owner sees three lots');
SELECT pg_temp.ok((:'lots'::jsonb->'items'->0->>'lot_code')='L-SUG-10' AND (:'lots'::jsonb->'items'->0->>'days_to_expiry')::int=10
 AND (:'lots'::jsonb->'items'->0->>'received_qty')::numeric=65 AND (:'lots'::jsonb->'items'->0->>'returned_qty')::numeric=15
 AND (:'lots'::jsonb->'items'->0->>'net_received_qty')::numeric=50 AND NOT (:'lots'::jsonb->'items'->0->>'expired')::boolean
 AND (:'lots'::jsonb->'items'->0->'site_ids')='[170111,170112]'::jsonb,'soonest expiry first, totals across both sites');
SELECT pg_temp.ok((:'lots'::jsonb->'items'->1->>'lot_code')='L-FLR-200' AND (:'lots'::jsonb->'items'->2->>'lot_code')='L-SUG-NOEXP'
 AND (:'lots'::jsonb->'items'->2->>'days_to_expiry') IS NULL AND (:'lots'::jsonb->>'on_hand_by_lot')='NOT_CONNECTED','no-expiry lot last');
SELECT pg_temp.ok(jsonb_array_length(core10.procurement_list_lots_v1(17011,NULL,30)->'items')=1,'expiring within 30 days: one lot');
SELECT pg_temp.ok(jsonb_array_length(core10.procurement_list_lots_v1(17011,NULL,0)->'items')=0,'nothing expires today');
SELECT core10.procurement_list_lots_v1(17011,NULL,NULL,NULL,NULL,1) AS pg1 \gset
SELECT core10.procurement_list_lots_v1(17011,NULL,NULL,(:'pg1'::jsonb->'next_after'->>'expires_on')::date,(:'pg1'::jsonb->'next_after'->>'lot_id')::bigint,1) AS pg2 \gset
SELECT core10.procurement_list_lots_v1(17011,NULL,NULL,(:'pg2'::jsonb->'next_after'->>'expires_on')::date,(:'pg2'::jsonb->'next_after'->>'lot_id')::bigint,1) AS pg3 \gset
SELECT core10.procurement_list_lots_v1(17011,NULL,NULL,(:'pg3'::jsonb->'next_after'->>'expires_on')::date,(:'pg3'::jsonb->'next_after'->>'lot_id')::bigint,1) AS pg4 \gset
SELECT pg_temp.ok((:'pg1'::jsonb->'items'->0->>'lot_code')='L-SUG-10' AND (:'pg2'::jsonb->'items'->0->>'lot_code')='L-FLR-200'
 AND (:'pg3'::jsonb->'items'->0->>'lot_code')='L-SUG-NOEXP' AND (:'pg3'::jsonb->'next_after'->>'expires_on')='infinity'
 AND jsonb_array_length(:'pg4'::jsonb->'items')=0 AND jsonb_typeof(:'pg4'::jsonb->'next_after')='null','keyset pages of one cover all lots once');
SELECT pg_temp.ok((core10.procurement_list_lots_v1(17011,NULL,NULL,NULL,NULL,5000)->>'limit')::int=200,'page cap 200');
SELECT pg_temp.expect($q$SELECT core10.procurement_list_lots_v1(17011,NULL,NULL,current_date,NULL)$q$,'PROC_INVALID_FILTER');
SELECT pg_temp.expect($q$SELECT core10.procurement_list_lots_v1(17011,NULL,-1)$q$,'PROC_INVALID_FILTER');
SELECT pg_temp.ok((core10.procurement_list_lots_v1(17011,170112)->'items'->0->>'received_qty')::numeric=7,'site filter: branch totals only');
-- branch staff (stock.read at the branch only): only the lot received at the branch, branch totals only
SELECT pg_temp.as_user(pg_temp.u(5));
SELECT core10.procurement_list_lots_v1(17011) AS bl \gset
SELECT pg_temp.ok(jsonb_array_length(:'bl'::jsonb->'items')=1 AND (:'bl'::jsonb->'items'->0->>'received_qty')::numeric=7
 AND (:'bl'::jsonb->'items'->0->>'returned_qty')::numeric=0 AND (:'bl'::jsonb->'items'->0->'site_ids')='[170112]'::jsonb,'branch staff: branch lot only');
SELECT pg_temp.expect($q$SELECT core10.procurement_list_lots_v1(17011,170111)$q$,'PROC_SCOPE');
-- godown staff: godown totals only
SELECT pg_temp.as_user(pg_temp.u(4));
SELECT pg_temp.ok(jsonb_array_length(core10.procurement_list_lots_v1(17011)->'items')=3
 AND (core10.procurement_list_lots_v1(17011)->'items'->0->>'received_qty')::numeric=58,'godown staff: godown totals');
-- an explicit site deny beats the business owner's rights
RESET ROLE;
INSERT INTO core10.site_grants(tenant_id,business_id,site_id,user_id,actions,denied_actions) VALUES
 (1701,17011,170112,pg_temp.u(2)::uuid,'{}','{stock.read}');
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user(pg_temp.u(2));
SELECT pg_temp.ok((core10.procurement_list_lots_v1(17011)->'items'->0->>'received_qty')::numeric=58,'denied branch excluded from owner totals');
SELECT pg_temp.as_user(pg_temp.u(6));
SELECT pg_temp.expect($q$SELECT core10.procurement_list_lots_v1(17011)$q$,'PROC_SCOPE');
SELECT pg_temp.ok(jsonb_array_length(core10.procurement_list_lots_v1(17021)->'items')=0,'tenant B sees its own (empty) lots');
SELECT pg_temp.as_user('17000000-0000-4000-8000-000000000009');
SELECT pg_temp.expect($q$SELECT core10.procurement_list_lots_v1(17011)$q$,'PROC_SCOPE');
RESET ROLE;

-- ---------- ledger, audit, isolation, registry ----------
SELECT pg_temp.ok(NOT EXISTS(SELECT 1 FROM core10.inventory_reconciliation_v1 WHERE NOT reconciled),'ledger reconciled');
SELECT pg_temp.ok((SELECT count(*) FROM core10.stock_movements WHERE business_id=17011
 AND request_key NOT LIKE 'c10-grn-%' AND request_key NOT LIKE 'c10-ret-%' AND transfer_id IS NULL)=0,'stock moved only by GRN posting, returns and the setup transfers');
SELECT pg_temp.ok((SELECT count(*) FROM core10.stock_movements WHERE business_id=17011 AND request_key LIKE 'c10-ret-%')=2
 AND (SELECT sum(delta) FROM core10.stock_movements WHERE business_id=17011 AND request_key LIKE 'c10-ret-%')=-15,'two return events, -15');
SELECT pg_temp.ok((SELECT count(*) FROM core10.canonical_audit_events_v1 WHERE business_id=17011 AND source_domain='procurement' AND action='procurement.grn_cancel')=4
 AND (SELECT count(*) FROM core10.canonical_audit_events_v1 WHERE business_id=17011 AND source_domain='procurement' AND action='procurement.return_save')=5
 AND (SELECT count(*) FROM core10.canonical_audit_events_v1 WHERE business_id=17011 AND source_domain='procurement' AND action='procurement.return_post')=2
 AND (SELECT count(*) FROM core10.canonical_audit_events_v1 WHERE business_id=17011 AND source_domain='procurement' AND action='procurement.return_cancel')=3,'canonical audit for every cancel / return step');
SELECT pg_temp.ok((SELECT count(*) FROM core10.goods_receipts_v1 WHERE business_id=17021)=0 AND (SELECT count(*) FROM core10.supplier_returns_v1 WHERE business_id=17021)=0,'tenant B untouched');
SELECT pg_temp.ok(NOT has_table_privilege('authenticated','core10.supplier_returns_v1','select')
 AND NOT has_table_privilege('authenticated','core10.supplier_return_lines_v1','select'),'return tables are RPC-only');
SELECT pg_temp.ok(NOT has_function_privilege('anon','core10.procurement_list_lots_v1(bigint,bigint,integer,date,bigint,integer)','execute')
 AND NOT has_function_privilege('anon','core10.procurement_save_return_v1(bigint,jsonb,text,text)','execute'),'no anon execute');
SELECT pg_temp.ok((SELECT count(*) FROM core10.control_rpc_map_v1 WHERE status='enforced' AND test_ref='tests/migrations/np03a-supplier-return-e2e.sql'
 AND rpc_name IN ('procurement_cancel_grn_v1','procurement_save_return_v1','procurement_advance_return_v1'))=3,'three 0207 writers enforced');
ROLLBACK;
\echo 'PASS np03a-supplier-return-e2e'
