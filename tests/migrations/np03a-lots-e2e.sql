-- B-012 / 0209: lot dimension on the one stock ledger, lot balances, FEFO, hold / release, lot commands, genealogy,
-- recall (disposable PG17, rolled back).
-- Personas (tenant 1901): tenant owner (Owner Control, second checker), business owner (lot manager), manager (buyer,
-- return poster), godown staff (stock.read+post at the godown: receiver, return preparer), showroom staff (stock.read+post
-- at the showroom), tenant 1902 owner (foreign). Proves: GRN posting tags its movement with the lot (no 0203 change);
-- lot balances are derived from the ledger breakdown (no second quantity book) and reconcile with stock_balances_v1;
-- lot-less issue takes untracked stock first then FEFO; transfers carry lots to the destination; FEFO suggestion
-- (expiry order, held / recalled / expired excluded, shortfall); named-lot issue / transfer / write-off through the
-- 0201 lifecycle; hold blocks named and lot-less issue, release with separate releaser; Owner Control
-- CONTROL_DISABLED:inventory.lot_control and CONTROL_DISABLED:inventory.lot_recall (also on replay); expired lot
-- refused for issue but writable off; genealogy link (cycle, recalled lineage); recall of a lot and its descendants:
-- where the stock is, receipts, blocked everywhere, close only at zero stock (write-off + supplier return), recalled
-- lots stay blocked; replay / replay conflict; cross-tenant denial; site-scoped reads; canonical audit; immutable
-- breakdown; RPC-only tables; no anon.
\set ON_ERROR_STOP on
BEGIN;
INSERT INTO core10.templates(code,source_status,demo_allowed) VALUES ('sweets_bakery','available',true) ON CONFLICT (code) DO NOTHING;
INSERT INTO core10.tenants(id,slug) VALUES (1901,'lot-a'),(1902,'lot-b');
INSERT INTO core10.legal_entities(id,tenant_id,label) VALUES (19010,1901,'Lot A'),(19020,1902,'Lot B');
INSERT INTO core10.businesses(id,tenant_id,legal_entity_id,slug,template_code,request_key) VALUES
 (19011,1901,19010,'lot-a1','sweets_bakery','lot-biz-a1'),(19021,1902,19020,'lot-b1','sweets_bakery','lot-biz-b1');
INSERT INTO core10.sites(id,tenant_id,business_id,kind,label,request_key) VALUES
 (190111,1901,19011,'godown','Godown','lot-site-1'),(190112,1901,19011,'showroom','Showroom','lot-site-2'),
 (190211,1902,19021,'godown','B godown','lot-site-3');
INSERT INTO core10.stock_locations(id,tenant_id,business_id,site_id,code) VALUES
 (1901111,1901,19011,190111,'G'),(1901121,1901,19011,190112,'S'),(1902111,1902,19021,190211,'BG');
INSERT INTO core10.items(id,tenant_id,business_id,sku,name_en,name_bn,status) VALUES
 (19101,1901,19011,'SUGAR','Sugar','চিনি','active'),(19102,1901,19011,'GHEE','Ghee','ঘি','active'),
 (19201,1902,19021,'SALT','Salt','লবণ','active');
INSERT INTO core10.master_parties_v1(id,tenant_id,business_id,code,party_kind,name_en,name_bn,status) VALUES
 (19151,1901,19011,'SUP-1','supplier','Sweet Mills','মিষ্টি কল','active');
INSERT INTO core10.tenant_members(tenant_id,user_id,role) VALUES
 (1901,'19000000-0000-4000-8000-000000000001','tenant_owner'),(1902,'19000000-0000-4000-8000-000000000006','tenant_owner');
INSERT INTO core10.business_members(tenant_id,business_id,user_id,role) VALUES
 (1901,19011,'19000000-0000-4000-8000-000000000002','business_owner'),(1901,19011,'19000000-0000-4000-8000-000000000003','manager');
INSERT INTO core10.site_grants(tenant_id,business_id,site_id,user_id,actions) VALUES
 (1901,19011,190111,'19000000-0000-4000-8000-000000000004','{stock.read,stock.post}'),
 (1901,19011,190112,'19000000-0000-4000-8000-000000000005','{stock.read,stock.post}');
-- a foreign lot (tenant 1902) to prove lot scope
INSERT INTO core10.inventory_lots_v1(id,tenant_id,business_id,item_id,lot_code,source_kind,source_ref,created_by) VALUES
 (1909901,1902,19021,19201,'B-SALT-1','purchase','test-foreign','19000000-0000-4000-8000-000000000006');

CREATE FUNCTION pg_temp.as_user(p text) RETURNS void LANGUAGE sql AS $$
 SELECT set_config('request.jwt.claims',json_build_object('sub',p)::text,true), set_config('request.jwt.claim.sub',p,true) $$;
CREATE FUNCTION pg_temp.u(n int) RETURNS text LANGUAGE sql AS $$ SELECT '19000000-0000-4000-8000-00000000000'||n $$;
CREATE FUNCTION pg_temp.ok(p boolean, m text) RETURNS void LANGUAGE plpgsql AS $$
 BEGIN IF p IS DISTINCT FROM true THEN RAISE EXCEPTION 'LOTT_ASSERT:%',m; END IF; END $$;
CREATE FUNCTION pg_temp.expect(q text, pre text) RETURNS void LANGUAGE plpgsql AS $$
 BEGIN BEGIN EXECUTE q; EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE pre||'%' THEN RETURN; END IF;
  RAISE EXCEPTION 'LOTT_WRONG_ERROR expected=% got=% q=%',pre,SQLERRM,left(q,200); END;
  RAISE EXCEPTION 'LOTT_EXPECTED_DENIAL:% q=%',pre,left(q,200); END $$;
CREATE FUNCTION pg_temp.cset(f text,e boolean,p jsonb,v int,key text) RETURNS jsonb LANGUAGE sql AS $$
 SELECT core10.control_set_v1(19011,NULL,f,e,0::smallint,p,NULL,false,v,'test control change',key) $$;
CREATE FUNCTION pg_temp.bal(l bigint,i bigint) RETURNS numeric LANGUAGE sql AS $$
 SELECT coalesce((SELECT on_hand FROM core10.stock_balances_v1 WHERE location_id=l AND item_id=i),0) $$;
CREATE FUNCTION pg_temp.lot(c text) RETURNS bigint LANGUAGE sql AS $$
 SELECT id FROM core10.inventory_lots_v1 WHERE business_id=19011 AND lot_code=c $$;
CREATE FUNCTION pg_temp.lb(l bigint,c text) RETURNS numeric LANGUAGE sql AS $$
 SELECT coalesce((SELECT on_hand FROM core10.stock_lot_balances_v1 WHERE location_id=l AND lot_id=pg_temp.lot(c)),0) $$;
CREATE FUNCTION pg_temp.untracked(l bigint,i bigint) RETURNS numeric LANGUAGE sql AS $$
 SELECT untracked FROM core10.inventory_lot_reconciliation_v1 WHERE location_id=l AND item_id=i $$;
CREATE FUNCTION pg_temp.po(l jsonb,key text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE p jsonb; BEGIN
 PERFORM pg_temp.as_user(pg_temp.u(3));
 p := core10.procurement_save_po_v1(19011,NULL,190111,19151,l,NULL,NULL,0,key||'-s');
 PERFORM pg_temp.as_user(pg_temp.u(2));
 RETURN core10.procurement_advance_po_v1((p->>'po_id')::bigint,'approve',1,key||'-a');
END $$;
CREATE FUNCTION pg_temp.grn(po bigint,l jsonb,qc jsonb,key text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE g jsonb; BEGIN
 PERFORM pg_temp.as_user(pg_temp.u(4));
 g := core10.procurement_receive_v1(po,1901111,l,NULL,key||'-r');
 g := core10.procurement_inspect_v1((g->>'grn_id')::bigint,qc,1,key||'-q');
 RETURN core10.procurement_post_grn_v1((g->>'grn_id')::bigint,2,key||'-p');
END $$;
-- create (named lot or lot-less) -> confirm (by conf) -> post (by who) through the unchanged 0201 lifecycle
CREATE FUNCTION pg_temp.cmd(who int,conf int,kind text,src bigint,dst bigint,item bigint,qty numeric,lot bigint,reason text,key text)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE c jsonb; BEGIN
 PERFORM pg_temp.as_user(pg_temp.u(who));
 c := CASE WHEN lot IS NULL THEN core10.create_inventory_command_v1(19011,kind,src,dst,item,qty,reason,key)
      ELSE core10.inventory_create_lot_command_v1(19011,kind,src,dst,item,qty,lot,reason,key) END;
 PERFORM pg_temp.as_user(pg_temp.u(conf));
 c := core10.advance_inventory_command_v1((c->>'command_id')::bigint,'confirm',1,key||'-c');
 PERFORM pg_temp.as_user(pg_temp.u(who));
 RETURN core10.advance_inventory_command_v1((c->>'command_id')::bigint,'post',2,key||'-p');
END $$;
-- movement breakdown of a posted command: [{lot_code, quantity}] by lot code
CREATE FUNCTION pg_temp.brk(cmd jsonb) RETURNS jsonb LANGUAGE sql AS $$
 SELECT coalesce(jsonb_object_agg(l.lot_code, ml.quantity),'{}'::jsonb) FROM core10.stock_movement_lots_v1 ml
 JOIN core10.inventory_lots_v1 l ON l.id=ml.lot_id
 WHERE ml.movement_id=(SELECT id FROM core10.stock_movements WHERE request_key='c10-inv-cmd-'||(cmd->>'command_id')) $$;
SELECT (current_date+20)::text AS exp20, (current_date+200)::text AS exp200, (current_date+5)::text AS exp5,
 (current_date+1)::text AS exp1, (current_date+90)::text AS exp90 \gset

SET LOCAL ROLE authenticated;
-- ---------- A) receipts tag their movements with the lot ----------
SELECT pg_temp.po('[{"item_id":19101,"quantity":100,"unit_price":50},{"item_id":19102,"quantity":30,"unit_price":400}]','lotk-xpo1') AS p1 \gset
SELECT (:'p1'::jsonb->>'po_id') AS po1 \gset
SELECT pg_temp.grn(:po1,('[{"line_no":1,"quantity":50,"lot_code":"S-LATE","expires_on":"'||:'exp200'||'"},{"line_no":2,"quantity":20,"lot_code":"G-1","expires_on":"'||:'exp90'||'"}]')::jsonb,
 '[{"line_no":1,"accepted_qty":50},{"line_no":2,"accepted_qty":20}]','lotk-xg1') AS g1 \gset
SELECT (:'g1'::jsonb->>'grn_id') AS grn1 \gset
SELECT pg_temp.grn(:po1,('[{"line_no":1,"quantity":30,"lot_code":"S-EARLY","expires_on":"'||:'exp20'||'"}]')::jsonb,'[{"line_no":1,"accepted_qty":30}]','lotk-xg2') AS g2 \gset
SELECT pg_temp.grn(:po1,'[{"line_no":1,"quantity":10}]','[{"line_no":1,"accepted_qty":10}]','lotk-xg3') AS g3 \gset
SELECT pg_temp.grn(:po1,('[{"line_no":2,"quantity":5,"lot_code":"G-2","expires_on":"'||:'exp90'||'"}]')::jsonb,'[{"line_no":2,"accepted_qty":5}]','lotk-xg4') AS g4 \gset
RESET ROLE;
SELECT pg_temp.ok(pg_temp.bal(1901111,19101)=90 AND pg_temp.lb(1901111,'S-LATE')=50 AND pg_temp.lb(1901111,'S-EARLY')=30
 AND pg_temp.untracked(1901111,19101)=10,'godown sugar 90 = S-LATE 50 + S-EARLY 30 + 10 untracked');
SELECT pg_temp.ok(pg_temp.bal(1901111,19102)=25 AND pg_temp.lb(1901111,'G-1')=20 AND pg_temp.lb(1901111,'G-2')=5
 AND pg_temp.untracked(1901111,19102)=0,'godown ghee 25 = G-1 20 + G-2 5');
SELECT pg_temp.ok((SELECT count(*) FROM core10.stock_movement_lots_v1 ml JOIN core10.goods_receipt_lines_v1 gl
 ON gl.stock_movement_id=ml.movement_id AND gl.lot_id=ml.lot_id AND ml.quantity=gl.accepted_qty WHERE ml.business_id=19011)=4,
 'each lot GRN movement carries its GRN line lot and quantity (no 0203 change)');

-- ---------- B) FEFO suggestion ----------
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user(pg_temp.u(4));
SELECT core10.inventory_fefo_v1(19011,190111,19101,60) AS f \gset
SELECT pg_temp.ok(jsonb_array_length(:'f'::jsonb->'lines')=2 AND (:'f'::jsonb->'lines'->0->>'lot_code')='S-EARLY'
 AND (:'f'::jsonb->'lines'->0->>'suggested')::numeric=30 AND (:'f'::jsonb->'lines'->1->>'lot_code')='S-LATE'
 AND (:'f'::jsonb->'lines'->1->>'suggested')::numeric=30 AND (:'f'::jsonb->>'shortfall')::numeric=0
 AND (:'f'::jsonb->>'untracked_available')::numeric=10 AND (:'f'::jsonb->'lines'->0->>'days_to_expiry')::int=20
 AND NOT (:'f'::jsonb->>'reserved')::boolean,'FEFO 60: S-EARLY 30 then S-LATE 30');
SELECT core10.inventory_fefo_v1(19011,190111,19101,100) AS f \gset
SELECT pg_temp.ok((:'f'::jsonb->>'suggested_total')::numeric=80 AND (:'f'::jsonb->>'shortfall')::numeric=20,'FEFO 100: 80 from lots, 20 short');
SELECT pg_temp.ok(jsonb_array_length(core10.inventory_fefo_v1(19011,190111,19101,10)->'lines')=1,'FEFO 10: only the first lot');
SELECT pg_temp.expect($q$SELECT core10.inventory_fefo_v1(19011,190111,19101,0)$q$,'INV_INVALID_COMMAND');
SELECT pg_temp.expect($q$SELECT core10.inventory_fefo_v1(19011,190111,19201,5)$q$,'INV_ITEM_SCOPE');
SELECT pg_temp.as_user(pg_temp.u(5));
SELECT pg_temp.expect($q$SELECT core10.inventory_fefo_v1(19011,190111,19101,5)$q$,'INV_SCOPE');
SELECT pg_temp.as_user(pg_temp.u(6));
SELECT pg_temp.expect($q$SELECT core10.inventory_fefo_v1(19011,190111,19101,5)$q$,'INV_SCOPE');

-- ---------- C) named-lot issue ----------
RESET ROLE;
SELECT pg_temp.lot('S-EARLY') AS s_early, pg_temp.lot('S-LATE') AS s_late, pg_temp.lot('G-1') AS g_1, pg_temp.lot('G-2') AS g_2 \gset
SET LOCAL ROLE authenticated;
SELECT pg_temp.cmd(2,2,'issue',1901111,NULL,19101,5,:s_early,NULL,'lotk-xc1') AS c1 \gset
SELECT pg_temp.ok((:'c1'::jsonb->>'status')='posted' AND (:'c1'::jsonb->>'lot_id')::bigint=:s_early,'lot issue posted, command carries the lot');
SELECT pg_temp.as_user(pg_temp.u(2));
SELECT pg_temp.ok((core10.inventory_create_lot_command_v1(19011,'issue',1901111,NULL,19101,5,:s_early,NULL,'lotk-xc1')->>'replayed')::boolean,'lot command replay');
SELECT pg_temp.expect($q$SELECT core10.inventory_create_lot_command_v1(19011,'issue',1901111,NULL,19101,5,$q$||:s_late||$q$,NULL,'lotk-xc1')$q$,'INV_REPLAY_CONFLICT');
SELECT pg_temp.expect($q$SELECT core10.inventory_create_lot_command_v1(19011,'issue',1901111,NULL,19101,5,$q$||:g_1||$q$,NULL,'lotk-xbad-01')$q$,'INV_LOT_SCOPE');
SELECT pg_temp.expect($q$SELECT core10.inventory_create_lot_command_v1(19011,'issue',1901111,NULL,19101,5,1909901,NULL,'lotk-xbad-02')$q$,'INV_LOT_SCOPE');
SELECT pg_temp.expect($q$SELECT core10.inventory_create_lot_command_v1(19011,'issue',1901111,NULL,19101,26,$q$||:s_early||$q$,NULL,'lotk-xbad-03')$q$,'INV_INSUFFICIENT_LOT_STOCK');
SELECT pg_temp.expect($q$SELECT core10.inventory_create_lot_command_v1(19011,'issue',1901111,NULL,19101,5,NULL,NULL,'lotk-xbad-04')$q$,'INV_LOT_REQUIRED');
SELECT pg_temp.as_user(pg_temp.u(6));
SELECT pg_temp.expect($q$SELECT core10.inventory_create_lot_command_v1(19011,'issue',1901111,NULL,19101,5,$q$||:s_early||$q$,NULL,'lotk-xbad-05')$q$,'INV_SCOPE');
SELECT pg_temp.as_user(pg_temp.u(4));
SELECT pg_temp.expect($q$SELECT core10.inventory_create_lot_command_v1(19011,'issue',1901111,NULL,19101,5,$q$||:s_early||$q$,NULL,'lotk-xbad-06')$q$,'INV_PERMISSION_DENIED');

-- ---------- D) lot-less issue: untracked first, then FEFO ----------
SELECT pg_temp.cmd(2,2,'issue',1901111,NULL,19101,15,NULL,NULL,'lotk-xd1') AS d1 \gset
RESET ROLE;
SELECT pg_temp.ok(pg_temp.brk(:'d1'::jsonb)='{"S-EARLY":-5}'::jsonb AND pg_temp.lb(1901111,'S-EARLY')=20
 AND pg_temp.untracked(1901111,19101)=0 AND pg_temp.bal(1901111,19101)=70,'lot-less 15 = 10 untracked + 5 S-EARLY (FEFO)');

-- ---------- E) transfers carry lots ----------
SET LOCAL ROLE authenticated;
SELECT pg_temp.cmd(2,2,'transfer',1901111,1901121,19101,20,:s_late,NULL,'lotk-xe1') AS e1 \gset
SELECT pg_temp.cmd(2,2,'transfer',1901111,1901121,19101,25,NULL,NULL,'lotk-xe2') AS e2 \gset
SELECT pg_temp.cmd(2,2,'transfer',1901111,1901121,19102,2,:g_2,NULL,'lotk-xe3') AS e3 \gset
RESET ROLE;
SELECT pg_temp.ok(pg_temp.lb(1901111,'S-LATE')=25 AND pg_temp.lb(1901111,'S-EARLY')=0 AND pg_temp.bal(1901111,19101)=25
 AND pg_temp.lb(1901121,'S-LATE')=25 AND pg_temp.lb(1901121,'S-EARLY')=20 AND pg_temp.bal(1901121,19101)=45,
 'named transfer 20 S-LATE, lot-less transfer 25 = S-EARLY 20 + S-LATE 5, both arrive with their lots');
SELECT pg_temp.ok((SELECT jsonb_object_agg(l.lot_code,ml.quantity) FROM core10.stock_movement_lots_v1 ml JOIN core10.inventory_lots_v1 l ON l.id=ml.lot_id
 WHERE ml.movement_id=(SELECT id FROM core10.stock_movements WHERE transfer_id=(:'e2'::jsonb->>'stock_ref')::bigint AND delta>0))
 ='{"S-EARLY":20,"S-LATE":5}'::jsonb,'in-leg mirrors the out-leg lots');
SELECT pg_temp.ok(pg_temp.lb(1901111,'G-2')=3 AND pg_temp.lb(1901121,'G-2')=2,'ghee G-2 3 godown / 2 showroom');

-- ---------- F) hold / release ----------
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user(pg_temp.u(4));
SELECT pg_temp.expect($q$SELECT core10.inventory_lot_hold_v1($q$||:s_late||$q$,'hold','quality complaint','lotk-xh-bad1')$q$,'INV_PERMISSION_DENIED');
SELECT pg_temp.as_user(pg_temp.u(6));
SELECT pg_temp.expect($q$SELECT core10.inventory_lot_hold_v1($q$||:s_late||$q$,'hold','quality complaint','lotk-xh-bad2')$q$,'INV_SCOPE');
SELECT pg_temp.as_user(pg_temp.u(2));
SELECT pg_temp.expect($q$SELECT core10.inventory_lot_hold_v1($q$||:s_late||$q$,'hold',NULL,'lotk-xh-bad3')$q$,'INV_REASON_REQUIRED');
SELECT pg_temp.expect($q$SELECT core10.inventory_lot_hold_v1($q$||:s_late||$q$,'release','not held','lotk-xh-bad4')$q$,'INV_INVALID_TRANSITION');
SELECT core10.inventory_lot_hold_v1(:s_late,'hold','quality complaint','lotk-xh1') AS h1 \gset
SELECT pg_temp.ok((:'h1'::jsonb->>'status')='held' AND (:'h1'::jsonb->>'blocked_reason')='lot_held' AND (:'h1'::jsonb->>'held_by')=pg_temp.u(2),'S-LATE held');
SELECT pg_temp.ok((core10.inventory_lot_hold_v1(:s_late,'hold','quality complaint','lotk-xh1')->>'replayed')::boolean,'hold replay');
SELECT pg_temp.expect($q$SELECT core10.inventory_lot_hold_v1($q$||:s_late||$q$,'hold','another reason','lotk-xh1')$q$,'INV_REPLAY_CONFLICT');
SELECT pg_temp.expect($q$SELECT core10.inventory_lot_hold_v1($q$||:s_late||$q$,'hold','quality complaint','lotk-xh-bad5')$q$,'INV_INVALID_TRANSITION');
-- named issue of a held lot refused; lot-less issue may not consume held stock (post time, engine)
SELECT pg_temp.expect($q$SELECT core10.inventory_create_lot_command_v1(19011,'issue',1901121,NULL,19101,1,$q$||:s_late||$q$,NULL,'lotk-xbad-07')$q$,'INV_LOT_HELD');
SELECT pg_temp.expect($q$SELECT pg_temp.cmd(2,2,'issue',1901111,NULL,19101,1,NULL,NULL,'lotk-xbad-08')$q$,'INV_LOT_BLOCKED_STOCK');
SELECT pg_temp.cmd(2,2,'issue',1901121,NULL,19101,20,NULL,NULL,'lotk-xf1') AS f1 \gset
SELECT pg_temp.expect($q$SELECT pg_temp.cmd(2,2,'issue',1901121,NULL,19101,1,NULL,NULL,'lotk-xbad-09')$q$,'INV_LOT_BLOCKED_STOCK');
SELECT pg_temp.expect($q$SELECT pg_temp.cmd(2,2,'transfer',1901121,1901111,19101,1,NULL,NULL,'lotk-xbad-10')$q$,'INV_LOT_BLOCKED_STOCK');
SELECT core10.inventory_fefo_v1(19011,190112,19101,5) AS f \gset
SELECT pg_temp.ok(jsonb_array_length(:'f'::jsonb->'lines')=0 AND (:'f'::jsonb->'excluded'->>'held')::numeric=25
 AND (:'f'::jsonb->>'shortfall')::numeric=5,'FEFO excludes the held lot');
-- write-off of held stock is allowed (adjust_out; separate confirmer by default)
SELECT pg_temp.cmd(2,1,'adjust_out',1901121,NULL,19101,1,:s_late,'damaged in hold','lotk-xf2') AS f2 \gset
SELECT pg_temp.ok(EXISTS(SELECT 1 FROM jsonb_array_elements(core10.procurement_list_lots_v1(19011)->'items') e
 WHERE e->>'lot_code'='S-LATE' AND e->>'status'='held'),'0207 lot read shows the hold');
SELECT pg_temp.as_user(pg_temp.u(1));
SELECT pg_temp.cset('inventory.lot_control',true,'{"separate_releaser":true}',0,'lotk-xctl-0001');
SELECT pg_temp.as_user(pg_temp.u(2));
SELECT pg_temp.expect($q$SELECT core10.inventory_lot_hold_v1($q$||:s_late||$q$,'release','complaint cleared','lotk-xr-bad1')$q$,'INV_SAME_ACTOR');
SELECT pg_temp.as_user(pg_temp.u(1));
SELECT pg_temp.ok((core10.inventory_lot_hold_v1(:s_late,'release','complaint cleared','lotk-xr1')->>'status')='released','second person released S-LATE');
SELECT pg_temp.cmd(2,2,'issue',1901111,NULL,19101,1,NULL,NULL,'lotk-xf3') AS f3 \gset
RESET ROLE;
SELECT pg_temp.ok(pg_temp.brk(:'f1'::jsonb)='{"S-EARLY":-20}'::jsonb AND pg_temp.brk(:'f2'::jsonb)='{"S-LATE":-1}'::jsonb
 AND pg_temp.brk(:'f3'::jsonb)='{"S-LATE":-1}'::jsonb AND pg_temp.lb(1901121,'S-LATE')=24 AND pg_temp.lb(1901111,'S-LATE')=24,
 'held stock untouched by lot-less issue, written off by lot, issuable after release');

-- ---------- G) Owner Control: lot_control off (also on replay); lot-less commands unaffected ----------
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user(pg_temp.u(1));
SELECT pg_temp.cset('inventory.lot_control',false,'{}',1,'lotk-xctl-0002');
SELECT pg_temp.as_user(pg_temp.u(2));
SELECT pg_temp.expect($q$SELECT core10.inventory_create_lot_command_v1(19011,'issue',1901111,NULL,19101,1,$q$||:s_late||$q$,NULL,'lotk-xbad-11')$q$,'CONTROL_DISABLED:inventory.lot_control');
SELECT pg_temp.expect($q$SELECT core10.inventory_create_lot_command_v1(19011,'issue',1901111,NULL,19101,5,$q$||:s_early||$q$,NULL,'lotk-xc1')$q$,'CONTROL_DISABLED:inventory.lot_control');
SELECT pg_temp.expect($q$SELECT core10.inventory_lot_hold_v1($q$||:s_late||$q$,'hold','quality complaint','lotk-xbad-12')$q$,'CONTROL_DISABLED:inventory.lot_control');
SELECT pg_temp.ok((core10.create_inventory_command_v1(19011,'issue',1901111,NULL,19101,1,NULL,'lotk-xg-draft')->>'status')='draft','lot-less command unaffected');
SELECT pg_temp.as_user(pg_temp.u(1));
SELECT pg_temp.cset('inventory.lot_control',true,'{}',2,'lotk-xctl-0003');

-- ---------- H) expiry ----------
SELECT pg_temp.grn(:po1,('[{"line_no":1,"quantity":5,"lot_code":"S-OLD","expires_on":"'||:'exp1'||'"}]')::jsonb,'[{"line_no":1,"accepted_qty":5}]','lotk-xg5') AS g5 \gset
RESET ROLE;
-- the day passes: S-OLD is now expired (test data only)
UPDATE core10.inventory_lots_v1 SET expires_on=current_date-1 WHERE business_id=19011 AND lot_code='S-OLD';
SELECT pg_temp.lot('S-OLD') AS s_old \gset
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user(pg_temp.u(2));
SELECT pg_temp.expect($q$SELECT core10.inventory_create_lot_command_v1(19011,'issue',1901111,NULL,19101,1,$q$||:s_old||$q$,NULL,'lotk-xbad-13')$q$,'INV_LOT_EXPIRED');
SELECT pg_temp.expect($q$SELECT core10.inventory_create_lot_command_v1(19011,'transfer',1901111,1901121,19101,1,$q$||:s_old||$q$,NULL,'lotk-xbad-14')$q$,'INV_LOT_EXPIRED');
SELECT core10.inventory_fefo_v1(19011,190111,19101,30) AS f \gset
SELECT pg_temp.ok((:'f'::jsonb->'excluded'->>'expired')::numeric=5 AND jsonb_array_length(:'f'::jsonb->'lines')=1
 AND (:'f'::jsonb->'lines'->0->>'lot_code')='S-LATE','FEFO skips the expired lot');
SELECT pg_temp.cmd(2,1,'adjust_out',1901111,NULL,19101,5,:s_old,'expired stock destroyed','lotk-xh1w') AS h1w \gset
SELECT pg_temp.ok((:'h1w'::jsonb->>'status')='posted','expired lot written off');

-- ---------- I) genealogy ----------
SELECT pg_temp.as_user(pg_temp.u(4));
SELECT pg_temp.expect($q$SELECT core10.inventory_lot_link_v1($q$||:g_1||$q$,$q$||:g_2||$q$,'lotk-xl-bad1')$q$,'INV_PERMISSION_DENIED');
SELECT pg_temp.as_user(pg_temp.u(6));
SELECT pg_temp.expect($q$SELECT core10.inventory_lot_link_v1($q$||:g_1||$q$,$q$||:g_2||$q$,'lotk-xl-bad2')$q$,'INV_SCOPE');
SELECT pg_temp.as_user(pg_temp.u(2));
SELECT pg_temp.ok(NOT (core10.inventory_lot_link_v1(:g_1,:g_2,'lotk-xl1')->>'replayed')::boolean,'G-2 made from G-1');
SELECT pg_temp.ok((core10.inventory_lot_link_v1(:g_1,:g_2,'lotk-xl1')->>'replayed')::boolean,'link replay');
SELECT pg_temp.expect($q$SELECT core10.inventory_lot_link_v1($q$||:g_2||$q$,$q$||:g_1||$q$,'lotk-xl-bad3')$q$,'INV_LOT_GENEALOGY_CYCLE');
SELECT pg_temp.expect($q$SELECT core10.inventory_lot_link_v1($q$||:g_1||$q$,$q$||:g_1||$q$,'lotk-xl-bad4')$q$,'INV_LOT_GENEALOGY_CYCLE');
SELECT pg_temp.expect($q$SELECT core10.inventory_lot_link_v1($q$||:g_1||$q$,1909901,'lotk-xl-bad5')$q$,'INV_SCOPE');

-- ---------- J) recall ----------
SELECT pg_temp.expect($q$SELECT core10.inventory_lot_start_recall_v1($q$||:g_1||$q$,'severe','bad batch','lotk-xrc-bad1')$q$,'INV_INVALID_RECALL');
SELECT core10.inventory_lot_start_recall_v1(:g_1,'customer','supplier reported contamination','lotk-xrc1') AS rc \gset
SELECT (:'rc'::jsonb->>'recall_id') AS rc1 \gset
SELECT pg_temp.ok((:'rc'::jsonb->>'status')='active' AND jsonb_array_length(:'rc'::jsonb->'lots')=2
 AND (:'rc'::jsonb->'lots'->0->>'lot_code')='G-1' AND (:'rc'::jsonb->'lots'->1->>'depth')::int=1
 AND jsonb_array_length(:'rc'::jsonb->'locations')=3 AND (:'rc'::jsonb->>'remaining_on_hand')::numeric=25
 AND jsonb_array_length(:'rc'::jsonb->'receipts')=2,'recall: G-1 and descendant G-2, 3 locations, 25 units, 2 receipts');
SELECT pg_temp.ok((core10.inventory_lot_start_recall_v1(:g_1,'customer','supplier reported contamination','lotk-xrc1')->>'replayed')::boolean,'recall replay');
SELECT pg_temp.expect($q$SELECT core10.inventory_lot_start_recall_v1($q$||:g_1||$q$,'critical','supplier reported contamination','lotk-xrc1')$q$,'INV_REPLAY_CONFLICT');
SELECT pg_temp.expect($q$SELECT core10.inventory_lot_start_recall_v1($q$||:g_1||$q$,'critical','second recall same lot','lotk-xrc-bad2')$q$,'INV_RECALL_ACTIVE');
SELECT pg_temp.expect($q$SELECT core10.inventory_create_lot_command_v1(19011,'issue',1901121,NULL,19102,1,$q$||:g_2||$q$,NULL,'lotk-xbad-15')$q$,'INV_LOT_RECALLED');
SELECT pg_temp.expect($q$SELECT pg_temp.cmd(2,2,'issue',1901111,NULL,19102,1,NULL,NULL,'lotk-xbad-16')$q$,'INV_LOT_BLOCKED_STOCK');
SELECT pg_temp.expect($q$SELECT core10.inventory_lot_hold_v1($q$||:g_1||$q$,'release','recalled lot','lotk-xbad-17')$q$,'INV_LOT_RECALLED');
SELECT pg_temp.expect($q$SELECT core10.inventory_lot_link_v1($q$||:s_late||$q$,$q$||:g_1||$q$,'lotk-xl-bad6')$q$,'INV_LOT_RECALLED');
SELECT pg_temp.ok((core10.inventory_fefo_v1(19011,190111,19102,1)->'excluded'->>'recalled')::numeric=23,'FEFO excludes recalled stock');
SELECT pg_temp.expect($q$SELECT core10.inventory_lot_close_recall_v1($q$||:rc1||$q$,NULL,'lotk-xrc-bad3')$q$,'INV_RECALL_STOCK_REMAINING:25');
-- recall read scope
SELECT pg_temp.as_user(pg_temp.u(4));
SELECT pg_temp.ok(jsonb_array_length(core10.inventory_lot_recall_v1(:rc1)->'locations')=2,'godown staff: godown locations only');
SELECT pg_temp.expect($q$SELECT core10.inventory_lot_start_recall_v1($q$||:g_2||$q$,'internal','staff may not recall','lotk-xrc-bad4')$q$,'INV_PERMISSION_DENIED');
SELECT pg_temp.as_user(pg_temp.u(5));
SELECT pg_temp.ok(jsonb_array_length(core10.inventory_lot_recall_v1(:rc1)->'locations')=1
 AND (core10.inventory_lot_recall_v1(:rc1)->>'remaining_on_hand')::numeric=2,'showroom staff: showroom location only');
SELECT pg_temp.as_user(pg_temp.u(6));
SELECT pg_temp.expect($q$SELECT core10.inventory_lot_recall_v1($q$||:rc1||$q$)$q$,'INV_SCOPE');
SELECT pg_temp.expect($q$SELECT core10.inventory_lot_close_recall_v1($q$||:rc1||$q$,NULL,'lotk-xrc-bad5')$q$,'INV_SCOPE');
-- Owner Control: lot_recall off
SELECT pg_temp.as_user(pg_temp.u(1));
SELECT pg_temp.cset('inventory.lot_recall',false,'{}',0,'lotk-xctl-0004');
SELECT pg_temp.as_user(pg_temp.u(2));
SELECT pg_temp.expect($q$SELECT core10.inventory_lot_close_recall_v1($q$||:rc1||$q$,NULL,'lotk-xrc-bad6')$q$,'CONTROL_DISABLED:inventory.lot_recall');
SELECT pg_temp.expect($q$SELECT core10.inventory_lot_start_recall_v1($q$||:s_late||$q$,'internal','check the recall switch','lotk-xrc-bad7')$q$,'CONTROL_DISABLED:inventory.lot_recall');
SELECT pg_temp.expect($q$SELECT core10.inventory_lot_start_recall_v1($q$||:g_1||$q$,'customer','supplier reported contamination','lotk-xrc1')$q$,'CONTROL_DISABLED:inventory.lot_recall');
SELECT pg_temp.expect($q$SELECT core10.inventory_lot_link_v1($q$||:s_late||$q$,$q$||:s_early||$q$,'lotk-xl-bad7')$q$,'CONTROL_DISABLED:inventory.lot_recall');
SELECT pg_temp.as_user(pg_temp.u(1));
SELECT pg_temp.cset('inventory.lot_recall',true,'{}',1,'lotk-xctl-0005');
-- clear the recalled stock: write off G-2 (both sites), return G-1 to the supplier (0207, lot-tagged by the engine)
SELECT pg_temp.cmd(2,1,'adjust_out',1901121,NULL,19102,2,:g_2,'recalled stock destroyed','lotk-xj1') AS j1 \gset
SELECT pg_temp.cmd(2,1,'adjust_out',1901111,NULL,19102,3,:g_2,'recalled stock destroyed','lotk-xj2') AS j2 \gset
SELECT pg_temp.as_user(pg_temp.u(4));
SELECT core10.procurement_save_return_v1(:grn1,'[{"line_no":2,"quantity":20}]','recalled by supplier','lotk-xret-s') AS rt \gset
SELECT pg_temp.as_user(pg_temp.u(3));
SELECT pg_temp.ok((core10.procurement_advance_return_v1((:'rt'::jsonb->>'return_id')::bigint,'post',1,'lotk-xret-p')->>'status')='posted','recalled G-1 returned to supplier');
SELECT pg_temp.as_user(pg_temp.u(2));
SELECT core10.inventory_lot_close_recall_v1(:rc1,'all recalled stock destroyed or returned','lotk-xrc2') AS rcc \gset
SELECT pg_temp.ok((:'rcc'::jsonb->>'status')='closed' AND (:'rcc'::jsonb->>'remaining_on_hand')::numeric=0
 AND jsonb_array_length(:'rcc'::jsonb->'locations')=0,'recall closed at zero stock');
SELECT pg_temp.ok((core10.inventory_lot_close_recall_v1(:rc1,'all recalled stock destroyed or returned','lotk-xrc2')->>'replayed')::boolean,'close replay');
SELECT pg_temp.expect($q$SELECT core10.inventory_lot_close_recall_v1($q$||:rc1||$q$,NULL,'lotk-xrc-bad8')$q$,'INV_INVALID_TRANSITION');
SELECT pg_temp.expect($q$SELECT core10.inventory_create_lot_command_v1(19011,'receive',NULL,1901111,19102,1,$q$||:g_1||$q$,'found stock','lotk-xbad-18')$q$,'INV_LOT_RECALLED');
RESET ROLE;
SELECT pg_temp.ok((SELECT ml.quantity FROM core10.stock_movement_lots_v1 ml JOIN core10.supplier_return_lines_v1 rl ON rl.stock_movement_id=ml.movement_id
 WHERE rl.return_id=(:'rt'::jsonb->>'return_id')::bigint AND ml.lot_id=:g_1)=-20 AND pg_temp.bal(1901111,19102)=0,
 'supplier return movement carries the GRN lot (no 0207 change)');

-- ---------- K) lot balance read ----------
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user(pg_temp.u(2));
SELECT core10.inventory_list_lot_balances_v1(19011) AS lb \gset
SELECT pg_temp.ok(jsonb_array_length(:'lb'::jsonb->'items')=2 AND (:'lb'::jsonb->'items'->0->>'lot_code')='S-LATE'
 AND (:'lb'::jsonb->'items'->0->>'on_hand')::numeric=24 AND (:'lb'::jsonb->'items'->1->>'location_code')='S','owner: S-LATE 24 at godown and showroom');
SELECT core10.inventory_list_lot_balances_v1(19011,NULL,NULL,NULL,NULL,1) AS lp1 \gset
SELECT core10.inventory_list_lot_balances_v1(19011,NULL,NULL,(:'lp1'::jsonb->'next_after'->>'location_id')::bigint,(:'lp1'::jsonb->'next_after'->>'lot_id')::bigint,1) AS lp2 \gset
SELECT pg_temp.ok((:'lp1'::jsonb->'items'->0->>'location_code')='G' AND (:'lp2'::jsonb->'items'->0->>'location_code')='S','keyset pages');
SELECT pg_temp.expect($q$SELECT core10.inventory_list_lot_balances_v1(19011,NULL,NULL,5,NULL)$q$,'INV_INVALID_FILTER');
SELECT pg_temp.as_user(pg_temp.u(5));
SELECT pg_temp.ok(jsonb_array_length(core10.inventory_list_lot_balances_v1(19011)->'items')=1,'showroom staff: showroom lots only');
SELECT pg_temp.expect($q$SELECT core10.inventory_list_lot_balances_v1(19011,190111)$q$,'INV_SCOPE');
SELECT pg_temp.as_user(pg_temp.u(6));
SELECT pg_temp.expect($q$SELECT core10.inventory_list_lot_balances_v1(19011)$q$,'INV_SCOPE');
SELECT pg_temp.ok(jsonb_array_length(core10.inventory_list_lot_balances_v1(19021)->'items')=0,'tenant B sees its own (empty) lots');
RESET ROLE;

-- ---------- L) one book, audit, isolation, registry ----------
SELECT pg_temp.ok(NOT EXISTS(SELECT 1 FROM core10.inventory_reconciliation_v1 WHERE NOT reconciled)
 AND NOT EXISTS(SELECT 1 FROM core10.inventory_lot_reconciliation_v1 WHERE NOT reconciled),'ledger and lot breakdown reconciled');
SELECT pg_temp.ok(NOT EXISTS(SELECT 1 FROM core10.stock_movements m JOIN (SELECT movement_id, sum(quantity) q FROM core10.stock_movement_lots_v1 GROUP BY 1) x
 ON x.movement_id=m.id WHERE sign(x.q)<>sign(m.delta) OR abs(x.q)>abs(m.delta)),'every breakdown has the sign of its movement and never exceeds it');
SELECT pg_temp.ok((SELECT sum(on_hand) FROM core10.stock_balances_v1 WHERE business_id=19011)=48
 AND (SELECT sum(on_hand) FROM core10.stock_lot_balances_v1 WHERE business_id=19011)=48,'business stock 48 = lot stock 48 (S-LATE 24+24)');
SELECT pg_temp.expect($q$UPDATE core10.stock_movement_lots_v1 SET quantity=quantity WHERE business_id=19011$q$,'stock_movement_lots_immutable');
SELECT pg_temp.expect($q$DELETE FROM core10.stock_movement_lots_v1 WHERE business_id=19011$q$,'stock_movement_lots_immutable');
SELECT pg_temp.ok((SELECT count(*) FROM core10.canonical_audit_events_v1 WHERE business_id=19011 AND source_domain='inventory' AND action='inventory.command_lot_set')=7
 AND (SELECT count(*) FROM core10.canonical_audit_events_v1 WHERE business_id=19011 AND source_domain='inventory' AND action='inventory.lot_hold')=1
 AND (SELECT count(*) FROM core10.canonical_audit_events_v1 WHERE business_id=19011 AND source_domain='inventory' AND action='inventory.lot_release')=1
 AND (SELECT count(*) FROM core10.canonical_audit_events_v1 WHERE business_id=19011 AND source_domain='inventory' AND action='inventory.lot_link')=1
 AND (SELECT count(*) FROM core10.canonical_audit_events_v1 WHERE business_id=19011 AND source_domain='inventory' AND action='inventory.recall_start')=1
 AND (SELECT count(*) FROM core10.canonical_audit_events_v1 WHERE business_id=19011 AND source_domain='inventory' AND action='inventory.recall_close')=1,
 'canonical audit for every lot command, hold, release, link, recall start and close');
SELECT pg_temp.ok((SELECT count(*) FROM core10.stock_movement_lots_v1 WHERE business_id=19021)=0
 AND (SELECT count(*) FROM core10.inventory_lot_recalls_v1 WHERE business_id=19021)=0,'tenant B untouched');
SELECT pg_temp.ok(NOT has_table_privilege('authenticated','core10.stock_movement_lots_v1','select')
 AND NOT has_table_privilege('authenticated','core10.inventory_lot_recalls_v1','select')
 AND NOT has_table_privilege('authenticated','core10.stock_lot_balances_v1','select')
 AND NOT has_table_privilege('authenticated','core10.inventory_lot_requests_v1','insert'),'lot tables and views are RPC-only');
SELECT pg_temp.ok(NOT has_function_privilege('anon','core10.inventory_fefo_v1(bigint,bigint,bigint,numeric)','execute')
 AND NOT has_function_privilege('anon','core10.inventory_lot_hold_v1(bigint,text,text,text)','execute')
 AND NOT has_function_privilege('authenticated','core10.post_stock_event(bigint,bigint,numeric,text)','execute')
 AND NOT has_function_privilege('authenticated','core10._stock_lot_apply_v1(bigint,bigint,bigint,numeric,jsonb,numeric)','execute'),'no anon, engine stays internal');
SELECT pg_temp.ok((SELECT count(*) FROM core10.control_rpc_map_v1 WHERE status='enforced' AND test_ref='tests/migrations/np03a-lots-e2e.sql'
 AND rpc_name IN ('inventory_create_lot_command_v1','inventory_lot_hold_v1','inventory_lot_link_v1','inventory_lot_start_recall_v1','inventory_lot_close_recall_v1'))=5,
 'five 0209 writers enforced');
ROLLBACK;
\echo 'PASS np03a-lots-e2e'
