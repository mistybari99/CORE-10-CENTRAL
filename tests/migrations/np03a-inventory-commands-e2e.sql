-- B-012 / 0201: stock command RPCs on the one 0200 ledger (disposable PG17, rolled back).
-- Personas: tenant owner, business owner, manager, site staff, site-denied business owner, expired staff,
-- other-tenant owner. Calls run as the API role `authenticated` with a signed actor, like PostgREST.
-- Proves: Owner Control (CONTROL_DISABLED master switch and per-kind, per-site, one-time exception, limits,
-- stages fail closed), Auth port (site deny, expiry, staff rules, cross-tenant/business), request-key replay,
-- versions, transitions, canonical audit, paged scoped reads, reconciliation with the one ledger.
\set ON_ERROR_STOP on
BEGIN;
INSERT INTO core10.templates(code,source_status,demo_allowed) VALUES ('sweets_bakery','available',true),('retail_wholesale','available',true)
 ON CONFLICT (code) DO NOTHING;
INSERT INTO core10.tenants(id,slug) VALUES (961,'invc-a'),(962,'invc-b');
INSERT INTO core10.legal_entities(id,tenant_id,label) VALUES (9610,961,'Invc A'),(9620,962,'Invc B');
INSERT INTO core10.businesses(id,tenant_id,legal_entity_id,slug,template_code,request_key) VALUES
 (9611,961,9610,'invc-a1','sweets_bakery','invc-b1'),(9612,961,9610,'invc-a2','retail_wholesale','invc-b2'),
 (9621,962,9620,'invc-b1','sweets_bakery','invc-b3');
INSERT INTO core10.sites(id,tenant_id,business_id,kind,label,request_key) VALUES
 (96111,961,9611,'factory','Factory','invc-s1'),(96112,961,9611,'showroom','Branch 1','invc-s2'),
 (96113,961,9611,'godown','Godown','invc-s3'),(96121,961,9612,'showroom','Retail branch','invc-s4'),
 (96211,962,9621,'showroom','B branch','invc-s5');
INSERT INTO core10.stock_locations(id,tenant_id,business_id,site_id,code) VALUES
 (961111,961,9611,96111,'F-MAIN'),(961112,961,9611,96111,'F-COLD'),(961121,961,9611,96112,'S-MAIN'),
 (961131,961,9611,96113,'G-MAIN'),(961211,961,9612,96121,'R-MAIN'),(962111,962,9621,96211,'B-MAIN');
INSERT INTO core10.items(id,tenant_id,business_id,sku,name_en,name_bn,status) VALUES
 (96101,961,9611,'SUGAR','Sugar','চিনি','active'),(96102,961,9611,'OLD-FLOUR','Old flour','পুরোনো আটা','inactive'),
 (96103,961,9612,'SOAP','Soap','সাবান','active'),(96201,962,9621,'B-ITEM','B item','বি পণ্য','active');
-- d1 tenant owner A, d2 business owner, d3 manager, d4 branch staff, d5 tenant owner B, d6 business owner
-- with a factory post deny, d7 godown staff whose grant expired.
INSERT INTO core10.tenant_members(tenant_id,user_id,role) VALUES
 (961,'d1111111-1111-4111-8111-111111111111','tenant_owner'),(962,'d5555555-5555-4555-8555-555555555555','tenant_owner');
INSERT INTO core10.business_members(tenant_id,business_id,user_id,role) VALUES
 (961,9611,'d2222222-2222-4222-8222-222222222222','business_owner'),
 (961,9611,'d3333333-3333-4333-8333-333333333333','manager'),
 (961,9611,'d6666666-6666-4666-8666-666666666666','business_owner');
INSERT INTO core10.site_grants(tenant_id,business_id,site_id,user_id,actions,denied_actions,valid_until) VALUES
 (961,9611,96112,'d4444444-4444-4444-8444-444444444444','{stock.read,stock.post}','{}',NULL),
 (961,9611,96111,'d6666666-6666-4666-8666-666666666666','{}','{stock.post}',NULL),
 (961,9611,96113,'d7777777-7777-4777-8777-777777777777','{stock.read,stock.post}','{}',now()-interval '1 day');

CREATE FUNCTION pg_temp.as_user(p text) RETURNS void LANGUAGE sql AS $$
 SELECT set_config('request.jwt.claims',json_build_object('sub',p)::text,true), set_config('request.jwt.claim.sub',p,true) $$;
CREATE FUNCTION pg_temp.ok(p boolean, m text) RETURNS void LANGUAGE plpgsql AS $$
 BEGIN IF p IS DISTINCT FROM true THEN RAISE EXCEPTION 'INVC_ASSERT:%',m; END IF; END $$;
CREATE FUNCTION pg_temp.expect(q text, pre text) RETURNS void LANGUAGE plpgsql AS $$
 BEGIN BEGIN EXECUTE q; EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE pre||'%' THEN RETURN; END IF;
  RAISE EXCEPTION 'INVC_WRONG_ERROR expected=% got=% q=%',pre,SQLERRM,left(q,160); END;
  RAISE EXCEPTION 'INVC_EXPECTED_DENIAL:% q=%',pre,left(q,160); END $$;
CREATE FUNCTION pg_temp.mk(b bigint,k text,s bigint,d bigint,i bigint,q numeric,r text,key text) RETURNS jsonb LANGUAGE sql AS $$
 SELECT core10.create_inventory_command_v1(b,k,s,d,i,q,r,key) $$;
CREATE FUNCTION pg_temp.adv(c jsonb,a text,key text) RETURNS jsonb LANGUAGE sql AS $$
 SELECT core10.advance_inventory_command_v1((c->>'command_id')::bigint,a,(c->>'version')::int,key) $$;
CREATE FUNCTION pg_temp.cset(b bigint,s bigint,f text,e boolean,g int,p jsonb,v int,key text) RETURNS jsonb LANGUAGE sql AS $$
 SELECT core10.control_set_v1(b,s,f,e,g::smallint,p,NULL,false,v,'test control change',key) $$;
CREATE FUNCTION pg_temp.bal(l bigint,i bigint) RETURNS numeric LANGUAGE sql AS $$
 SELECT coalesce((SELECT on_hand FROM core10.stock_balances_v1 WHERE location_id=l AND item_id=i),0) $$;

-- ---------- API surface ----------
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('d1111111-1111-4111-8111-111111111111');
SELECT pg_temp.expect('SELECT count(*) FROM core10.inventory_commands_v1','permission denied');
SELECT pg_temp.expect('SELECT count(*) FROM core10.inventory_command_requests_v1','permission denied');
SELECT pg_temp.expect('INSERT INTO core10.stock_movements(tenant_id,business_id,site_id,location_id,item_id,delta,request_key) VALUES (961,9611,96111,961111,96101,5,''direct-0001'')','permission denied');
SELECT pg_temp.expect('SELECT core10._inventory_controls_v1(9611,''receive'',ARRAY[96111::bigint],''[]''::jsonb)','permission denied');
SELECT pg_temp.expect('SELECT core10.inventory_action_authorized_v1(961,9611,961111,''stock.post'')','permission denied');
SELECT pg_temp.expect('SELECT core10.control_check_v1(9611,''inventory.receive'',NULL)','permission denied');
RESET ROLE;
SELECT pg_temp.ok(NOT has_function_privilege('anon','core10.create_inventory_command_v1(bigint,text,bigint,bigint,bigint,numeric,text,text)','execute'),'anon cannot create');
SELECT pg_temp.ok(NOT has_function_privilege('anon','core10.advance_inventory_command_v1(bigint,text,integer,text)','execute'),'anon cannot advance');
SELECT pg_temp.ok(NOT has_function_privilege('anon','core10.inventory_list_balances_v1(bigint,bigint,bigint,bigint,integer)','execute'),'anon cannot read');
SELECT pg_temp.ok((SELECT count(*) FROM core10.control_rpc_map_v1 WHERE rpc_name IN ('create_inventory_command_v1','advance_inventory_command_v1')
 AND status='enforced' AND feature_key='inventory.stock_event')=2,'both writers enforced in the registry');
SET LOCAL ROLE authenticated;

-- ---------- receive -> confirm -> post at the factory (tenant owner) ----------
SELECT pg_temp.mk(9611,'receive',NULL,961111,96101,100,NULL,'invc-recv-0001') AS r1 \gset
SELECT pg_temp.ok((:'r1'::jsonb->>'status')='draft' AND (:'r1'::jsonb->>'version')='1','draft v1');
SELECT pg_temp.ok((pg_temp.mk(9611,'receive',NULL,961111,96101,100,NULL,'invc-recv-0001')->>'replayed')::boolean,'create replay');
SELECT pg_temp.expect($q$SELECT pg_temp.mk(9611,'receive',NULL,961111,96101,101,NULL,'invc-recv-0001')$q$,'INV_REPLAY_CONFLICT');
SELECT pg_temp.expect($q$SELECT core10.advance_inventory_command_v1($q$||(:'r1'::jsonb->>'command_id')||$q$,'post',1,'invc-post-early')$q$,'INV_CONFIRM_FIRST');
SELECT pg_temp.adv(:'r1'::jsonb,'confirm','invc-conf-0001') AS r1c \gset
SELECT pg_temp.expect($q$SELECT core10.advance_inventory_command_v1($q$||(:'r1'::jsonb->>'command_id')||$q$,'post',1,'invc-post-stale')$q$,'INV_STALE_VERSION:2');
SELECT pg_temp.adv(:'r1c'::jsonb,'post','invc-post-0001') AS r1p \gset
SELECT pg_temp.ok((:'r1p'::jsonb->>'status')='posted' AND (:'r1p'::jsonb->>'stock_ref') IS NOT NULL,'posted with stock ref');
SELECT pg_temp.ok((pg_temp.adv(:'r1c'::jsonb,'post','invc-post-0001')->>'replayed')::boolean,'post replay');
SELECT pg_temp.expect($q$SELECT pg_temp.adv('$q$||:'r1c'||$q$'::jsonb,'confirm','invc-post-0001')$q$,'INV_REPLAY_CONFLICT');
SELECT pg_temp.as_user('d2222222-2222-4222-8222-222222222222');
SELECT pg_temp.expect($q$SELECT pg_temp.mk(9611,'receive',NULL,961111,96101,100,NULL,'invc-recv-0001')$q$,'INV_REPLAY_CONFLICT');
SELECT pg_temp.as_user('d1111111-1111-4111-8111-111111111111');
RESET ROLE;
SELECT pg_temp.ok(pg_temp.bal(961111,96101)=100,'factory 100 after one post and replays');
SELECT pg_temp.ok((SELECT count(*) FROM core10.stock_movements WHERE location_id=961111 AND item_id=96101)=1,'one movement');
SELECT pg_temp.ok((SELECT count(*) FROM core10.canonical_audit_events_v1 WHERE business_id=9611 AND source_domain='inventory'
 AND source_ref LIKE 'command:'||(:'r1'::jsonb->>'command_id')||':%')=3,'created, confirmed, posted in canonical audit');
SET LOCAL ROLE authenticated;

-- ---------- transfers factory -> branch and factory -> godown; same-site move ----------
SELECT pg_temp.mk(9611,'transfer',961111,961121,96101,30,NULL,'invc-xfer-0001') AS t1 \gset
SELECT pg_temp.adv(pg_temp.adv(:'t1'::jsonb,'confirm','invc-xfer-c001'),'post','invc-xfer-p001') AS t1p \gset
SELECT pg_temp.mk(9611,'transfer',961111,961131,96101,20,NULL,'invc-xfer-0002') AS t2 \gset
SELECT pg_temp.adv(pg_temp.adv(:'t2'::jsonb,'confirm','invc-xfer-c002'),'post','invc-xfer-p002') AS t2p \gset
SELECT pg_temp.mk(9611,'transfer',961111,961112,96101,5,NULL,'invc-xfer-0003') AS t3 \gset
SELECT pg_temp.adv(pg_temp.adv(:'t3'::jsonb,'confirm','invc-xfer-c003'),'post','invc-xfer-p003') AS t3p \gset
RESET ROLE;
SELECT pg_temp.ok(pg_temp.bal(961111,96101)=45 AND pg_temp.bal(961121,96101)=30 AND pg_temp.bal(961131,96101)=20 AND pg_temp.bal(961112,96101)=5,'transfer balances');
SELECT pg_temp.ok((SELECT sum(delta) FROM core10.stock_movements WHERE transfer_id=(:'t1p'::jsonb->>'stock_ref')::bigint)=0,'paired movements net zero');
SET LOCAL ROLE authenticated;

-- ---------- shape, scope and item checks ----------
SELECT pg_temp.expect($q$SELECT pg_temp.mk(9611,'receive',961111,961121,96101,1,NULL,'invc-shape-001')$q$,'INV_LOCATION_SHAPE');
SELECT pg_temp.expect($q$SELECT pg_temp.mk(9611,'transfer',961111,961111,96101,1,NULL,'invc-shape-002')$q$,'INV_LOCATION_SHAPE');
SELECT pg_temp.expect($q$SELECT pg_temp.mk(9611,'receive',NULL,961111,96101,'NaN',NULL,'invc-shape-003')$q$,'INV_INVALID_COMMAND');
SELECT pg_temp.expect($q$SELECT pg_temp.mk(9611,'receive',NULL,961111,96101,1.0001,NULL,'invc-shape-004')$q$,'INV_INVALID_COMMAND');
SELECT pg_temp.expect($q$SELECT pg_temp.mk(9611,'receive',NULL,961111,96101,1,NULL,'bad key!')$q$,'INV_INVALID_COMMAND');
SELECT pg_temp.expect($q$SELECT pg_temp.mk(9611,'move',NULL,961111,96101,1,NULL,'invc-shape-005')$q$,'INV_INVALID_COMMAND');
SELECT pg_temp.expect($q$SELECT pg_temp.mk(9611,'transfer',961111,961211,96101,1,NULL,'invc-xbiz-0001')$q$,'INV_LOCATION_SCOPE');
SELECT pg_temp.expect($q$SELECT pg_temp.mk(9611,'receive',NULL,962111,96101,1,NULL,'invc-xten-0001')$q$,'INV_LOCATION_SCOPE');
SELECT pg_temp.expect($q$SELECT pg_temp.mk(9611,'receive',NULL,961111,96103,1,NULL,'invc-xbiz-0002')$q$,'INV_ITEM_SCOPE');
SELECT pg_temp.expect($q$SELECT pg_temp.mk(9611,'receive',NULL,961111,96102,1,NULL,'invc-inact-001')$q$,'INV_ITEM_NOT_USABLE');
SELECT pg_temp.expect($q$SELECT pg_temp.mk(99999,'receive',NULL,961111,96101,1,NULL,'invc-nobiz-001')$q$,'INV_SCOPE');

-- ---------- second business of the same owner works independently ----------
SELECT pg_temp.mk(9612,'receive',NULL,961211,96103,12,NULL,'invc-retail-001') AS rr \gset
SELECT pg_temp.adv(pg_temp.adv(:'rr'::jsonb,'confirm','invc-retail-c01'),'post','invc-retail-p01') AS rrp \gset
SELECT pg_temp.ok((:'rrp'::jsonb->>'status')='posted','retail business receive posted');

-- ---------- adjustments: reason, maker-checker, limit ----------
SELECT pg_temp.expect($q$SELECT pg_temp.mk(9611,'adjust_out',961121,NULL,96101,2,NULL,'invc-adj-0001')$q$,'INV_REASON_REQUIRED');
SELECT pg_temp.mk(9611,'adjust_out',961121,NULL,96101,2,'Damaged in transit','invc-adj-0002') AS a1 \gset
SELECT pg_temp.expect($q$SELECT pg_temp.adv('$q$||:'a1'||$q$'::jsonb,'confirm','invc-adj-c001')$q$,'INV_SAME_ACTOR');
SELECT pg_temp.expect($q$SELECT pg_temp.mk(9611,'adjust_in',NULL,961121,96101,1001,'Found stock','invc-adj-0003')$q$,'CONTROL_LIMIT:max_adjust_qty');
SELECT pg_temp.as_user('d2222222-2222-4222-8222-222222222222');
SELECT pg_temp.adv(pg_temp.adv(:'a1'::jsonb,'confirm','invc-adj-c002'),'post','invc-adj-p002') AS a1p \gset
SELECT pg_temp.ok((:'a1p'::jsonb->>'status')='posted','adjustment posted after a different confirmer');

-- ---------- staff, manager, site deny, expiry ----------
SELECT pg_temp.as_user('d4444444-4444-4444-8444-444444444444');
SELECT pg_temp.expect($q$SELECT pg_temp.mk(9611,'issue',961121,NULL,96101,1,NULL,'invc-staff-001')$q$,'INV_PERMISSION_DENIED');
SELECT pg_temp.expect($q$SELECT pg_temp.mk(9611,'receive',NULL,961111,96101,1,NULL,'invc-staff-002')$q$,'INV_PERMISSION_DENIED');
SELECT pg_temp.expect($q$SELECT pg_temp.mk(9611,'transfer',961121,961111,96101,1,NULL,'invc-staff-003')$q$,'INV_PERMISSION_DENIED');
SELECT pg_temp.mk(9611,'receive',NULL,961121,96101,4,NULL,'invc-staff-004') AS s4 \gset
SELECT pg_temp.as_user('d1111111-1111-4111-8111-111111111111');
SELECT pg_temp.cset(9611,96112,'inventory.issue',true,0,'{"staff_allowed":true}',0,'invc-ctl-0001');
SELECT pg_temp.as_user('d4444444-4444-4444-8444-444444444444');
SELECT pg_temp.mk(9611,'issue',961121,NULL,96101,3,NULL,'invc-staff-005') AS s5 \gset
SELECT pg_temp.adv(pg_temp.adv(:'s5'::jsonb,'confirm','invc-staff-c05'),'post','invc-staff-p05') AS s5p \gset
SELECT pg_temp.ok((:'s5p'::jsonb->>'status')='posted','staff issue after Owner allowed it at the branch');
SELECT pg_temp.expect($q$SELECT core10.advance_inventory_command_v1($q$||(:'t2'::jsonb->>'command_id')||$q$,'cancel',3,'invc-staff-x01')$q$,'INV_PERMISSION_DENIED');
SELECT pg_temp.as_user('d3333333-3333-4333-8333-333333333333');
SELECT pg_temp.mk(9611,'receive',NULL,961131,96101,6,NULL,'invc-mgr-0001') AS m1 \gset
SELECT pg_temp.expect($q$SELECT pg_temp.mk(9611,'adjust_in',NULL,961131,96101,1,'Count fix','invc-mgr-0002')$q$,'INV_PERMISSION_DENIED');
SELECT pg_temp.as_user('d6666666-6666-4666-8666-666666666666');
SELECT pg_temp.expect($q$SELECT pg_temp.mk(9611,'receive',NULL,961111,96101,1,NULL,'invc-deny-0001')$q$,'INV_PERMISSION_DENIED');
SELECT pg_temp.mk(9611,'receive',NULL,961121,96101,1,NULL,'invc-deny-0003') AS dn \gset
SELECT pg_temp.as_user('d1111111-1111-4111-8111-111111111111');
SELECT pg_temp.mk(9611,'receive',NULL,961111,96101,2,NULL,'invc-deny-0004') AS dnf \gset
SELECT pg_temp.as_user('d6666666-6666-4666-8666-666666666666');
SELECT pg_temp.expect($q$SELECT pg_temp.adv('$q$||:'dnf'||$q$'::jsonb,'confirm','invc-deny-0005')$q$,'INV_PERMISSION_DENIED');
SELECT pg_temp.as_user('d7777777-7777-4777-8777-777777777777');
SELECT pg_temp.expect($q$SELECT pg_temp.mk(9611,'receive',NULL,961131,96101,1,NULL,'invc-exp-00001')$q$,'INV_');
SELECT pg_temp.expect($q$SELECT core10.inventory_list_balances_v1(9611,96113,NULL,NULL,10)$q$,'INV_SCOPE');

-- ---------- other tenant ----------
SELECT pg_temp.as_user('d5555555-5555-4555-8555-555555555555');
SELECT pg_temp.expect($q$SELECT pg_temp.mk(9611,'receive',NULL,961111,96101,1,NULL,'invc-foreign-01')$q$,'INV_SCOPE');
SELECT pg_temp.expect($q$SELECT pg_temp.adv('$q$||:'dnf'||$q$'::jsonb,'confirm','invc-foreign-02')$q$,'INV_SCOPE');
SELECT pg_temp.expect($q$SELECT core10.inventory_list_commands_v1(9611)$q$,'INV_SCOPE');
SELECT pg_temp.expect($q$SELECT core10.inventory_list_balances_v1(9611)$q$,'INV_SCOPE');
SELECT pg_temp.expect($q$SELECT pg_temp.mk(9621,'receive',NULL,961111,96201,1,NULL,'invc-foreign-03')$q$,'INV_LOCATION_SCOPE');
SELECT pg_temp.ok(jsonb_array_length(core10.inventory_list_commands_v1(9621)->'items')=0,'B sees none of A');
SELECT pg_temp.as_user('');
SELECT pg_temp.expect($q$SELECT pg_temp.mk(9611,'receive',NULL,961111,96101,1,NULL,'invc-unsigned-1')$q$,'INV_SCOPE');

-- ---------- Owner Control: master switch, per kind, per site, exception, limits, stages ----------
SELECT pg_temp.as_user('d1111111-1111-4111-8111-111111111111');
SELECT pg_temp.mk(9611,'receive',NULL,961111,96101,3,NULL,'invc-off-0000') AS off0 \gset
SELECT pg_temp.cset(9611,NULL,'inventory.stock_event',false,0,'{}',0,'invc-ctl-0002');
SELECT pg_temp.expect($q$SELECT pg_temp.mk(9611,'receive',NULL,961111,96101,1,NULL,'invc-off-0001')$q$,'CONTROL_DISABLED:inventory.stock_event');
SELECT pg_temp.expect($q$SELECT pg_temp.mk(9611,'receive',NULL,961111,96101,100,NULL,'invc-recv-0001')$q$,'CONTROL_DISABLED:inventory.stock_event');
SELECT pg_temp.expect($q$SELECT pg_temp.adv('$q$||:'off0'||$q$'::jsonb,'confirm','invc-off-0002')$q$,'CONTROL_DISABLED:inventory.stock_event');
SELECT pg_temp.ok((pg_temp.adv(:'off0'::jsonb,'cancel','invc-off-0003')->>'status')='cancelled','cancel works while switched off');
SELECT pg_temp.mk(9612,'receive',NULL,961211,96103,1,NULL,'invc-off-0004') AS off4 \gset
SELECT pg_temp.ok((:'off4'::jsonb->>'status')='draft','switch in one business does not touch another');
SELECT pg_temp.cset(9611,NULL,'inventory.stock_event',true,0,'{}',1,'invc-ctl-0003');
SELECT pg_temp.cset(9611,96113,'inventory.transfer',false,0,'{}',0,'invc-ctl-0004');
SELECT pg_temp.expect($q$SELECT pg_temp.mk(9611,'transfer',961111,961131,96101,1,NULL,'invc-off-0005')$q$,'CONTROL_DISABLED:inventory.transfer');
SELECT pg_temp.mk(9611,'transfer',961111,961121,96101,1,NULL,'invc-off-0006') AS off6 \gset
SELECT pg_temp.cset(9611,NULL,'inventory.receive',false,0,'{}',0,'invc-ctl-0005');
SELECT core10.control_grant_override_v1(9611,NULL,'inventory.receive',2,'one urgent delivery','invc-ovr-0001');
SELECT pg_temp.mk(9611,'receive',NULL,961121,96101,1,NULL,'invc-ovr-0002') AS ov \gset
SELECT pg_temp.expect($q$SELECT pg_temp.mk(9611,'receive',NULL,961121,96101,1,NULL,'invc-ovr-0003')$q$,'CONTROL_DISABLED:inventory.receive');
SELECT pg_temp.cset(9611,NULL,'inventory.receive',true,0,'{"max_qty":50}',1,'invc-ctl-0006');
SELECT pg_temp.expect($q$SELECT pg_temp.mk(9611,'receive',NULL,961121,96101,60,NULL,'invc-lim-0001')$q$,'CONTROL_LIMIT:max_qty');
SELECT pg_temp.cset(9611,NULL,'inventory.transfer',true,0,'{"allow_cross_site":false}',0,'invc-ctl-0007');
SELECT pg_temp.expect($q$SELECT pg_temp.mk(9611,'transfer',961111,961121,96101,1,NULL,'invc-lim-0002')$q$,'CONTROL_LIMIT:allow_cross_site');
SELECT pg_temp.expect($q$SELECT pg_temp.adv(pg_temp.adv('$q$||:'off6'||$q$'::jsonb,'confirm','invc-lim-0003'),'post','invc-lim-0004')$q$,'CONTROL_LIMIT:allow_cross_site');
SELECT pg_temp.mk(9611,'transfer',961112,961111,96101,1,NULL,'invc-lim-0005') AS same \gset
SELECT pg_temp.cset(9611,NULL,'inventory.issue',true,1,'{}',0,'invc-ctl-0008');
SELECT pg_temp.mk(9611,'issue',961111,NULL,96101,1,NULL,'invc-stg-0001') AS st \gset
SELECT pg_temp.adv(:'st'::jsonb,'confirm','invc-stg-0002') AS stc \gset
SELECT pg_temp.expect($q$SELECT pg_temp.adv('$q$||:'stc'||$q$'::jsonb,'post','invc-stg-0003')$q$,'INV_APPROVAL_NOT_CONNECTED');
SELECT pg_temp.cset(9611,NULL,'inventory.issue',true,0,'{}',1,'invc-ctl-0009');
-- insufficient stock: the ledger never goes negative, with or without the negative-stock switch
SELECT pg_temp.mk(9611,'issue',961112,NULL,96101,999,NULL,'invc-neg-0001') AS ng \gset
SELECT pg_temp.adv(:'ng'::jsonb,'confirm','invc-neg-0002') AS ngc \gset
SELECT pg_temp.expect($q$SELECT pg_temp.adv('$q$||:'ngc'||$q$'::jsonb,'post','invc-neg-0003')$q$,'INV_INSUFFICIENT_STOCK');
SELECT pg_temp.cset(9611,NULL,'inventory.stock_event',true,0,'{"allow_negative_stock":true}',2,'invc-ctl-0010');
SELECT pg_temp.expect($q$SELECT pg_temp.adv('$q$||:'ngc'||$q$'::jsonb,'post','invc-neg-0004')$q$,'INV_NEGATIVE_STOCK_NOT_CONNECTED');
-- cancelled and posted commands cannot move again
SELECT pg_temp.expect($q$SELECT pg_temp.adv(pg_temp.adv('$q$||:'off0'||$q$'::jsonb,'cancel','invc-cx-00001'),'post','invc-cx-00002')$q$,'INV_');
SELECT pg_temp.expect($q$SELECT core10.advance_inventory_command_v1($q$||(:'r1'::jsonb->>'command_id')||$q$,'cancel',3,'invc-cx-00003')$q$,'INV_INVALID_TRANSITION');

-- ---------- scoped, paged reads ----------
SELECT core10.inventory_list_commands_v1(9611,NULL,NULL,NULL,2) AS pg1 \gset
SELECT pg_temp.ok(jsonb_array_length(:'pg1'::jsonb->'items')=2 AND (:'pg1'::jsonb->>'next_before_id') IS NOT NULL,'page of 2 with cursor');
SELECT pg_temp.ok((core10.inventory_list_commands_v1(9611,NULL,NULL,(:'pg1'::jsonb->>'next_before_id')::bigint,200)->'items'->0->>'command_id')::bigint
 < (:'pg1'::jsonb->>'next_before_id')::bigint,'next page continues below the cursor');
SELECT pg_temp.ok(jsonb_array_length(core10.inventory_list_commands_v1(9611,NULL,'cancelled')->'items')=1,'status filter');
SELECT pg_temp.ok(jsonb_array_length(core10.inventory_list_commands_v1(9611,NULL,NULL,NULL,100000)->'items')<=200,'page size capped');
SELECT pg_temp.expect($q$SELECT core10.inventory_list_commands_v1(9611,NULL,'bogus')$q$,'INV_INVALID_FILTER');
SELECT pg_temp.ok(jsonb_array_length(core10.inventory_list_balances_v1(9611)->'items')=4,'owner sees four balance rows');
SELECT pg_temp.ok((SELECT bool_and((x->>'site_id')::bigint=96112) FROM jsonb_array_elements(core10.inventory_list_balances_v1(9611,96112)->'items') x),'site filter');
SELECT pg_temp.ok(jsonb_array_length(core10.inventory_list_balances_v1(9611,NULL,NULL,NULL,1)->'items')=1
 AND (core10.inventory_list_balances_v1(9611,NULL,NULL,NULL,1)->'next_after') IS NOT NULL,'balance cursor');
SELECT pg_temp.expect($q$SELECT core10.inventory_list_balances_v1(9611,NULL,961111,NULL,1)$q$,'INV_INVALID_FILTER');
SELECT pg_temp.as_user('d4444444-4444-4444-8444-444444444444');
SELECT pg_temp.ok((SELECT bool_and((x->>'site_id')::bigint=96112) FROM jsonb_array_elements(core10.inventory_list_balances_v1(9611)->'items') x),'branch staff sees only the branch');
SELECT pg_temp.ok((SELECT bool_and(coalesce((x->>'source_site_id')::bigint,96112)=96112 AND coalesce((x->>'destination_site_id')::bigint,96112)=96112)
 FROM jsonb_array_elements(core10.inventory_list_commands_v1(9611,NULL,NULL,NULL,200)->'items') x),'branch staff sees only branch-only commands');
SELECT pg_temp.expect($q$SELECT core10.inventory_list_balances_v1(9611,96111)$q$,'INV_SCOPE');
RESET ROLE;

-- ---------- the one ledger reconciles; audit only for effects ----------
SELECT pg_temp.ok(NOT EXISTS(SELECT 1 FROM core10.inventory_reconciliation_v1 WHERE NOT reconciled),'all balances reconciled');
SELECT pg_temp.ok((SELECT count(*) FROM core10.inventory_commands_v1 c WHERE c.status='posted' AND NOT EXISTS(
 SELECT 1 FROM core10.stock_movements m WHERE m.request_key LIKE 'c10-inv-cmd-'||c.id||'%' OR m.transfer_id=c.stock_ref AND c.kind='transfer'))=0,
 'every posted command has its ledger movement');
SELECT pg_temp.ok((SELECT count(*) FROM core10.stock_movements WHERE business_id=9611 AND transfer_id IS NULL
 AND request_key NOT LIKE 'c10-inv-cmd-%')=0,'no stock moved outside commands');
SELECT pg_temp.ok((SELECT count(*) FROM core10.canonical_audit_events_v1 WHERE source_domain='inventory')
 =(SELECT count(*) FROM core10.inventory_command_requests_v1),'one canonical audit event per recorded request');
SELECT pg_temp.ok((SELECT count(*) FROM core10.inventory_commands_v1 WHERE business_id=9621)=0,'tenant B untouched');
ROLLBACK;
\echo 'PASS np03a-inventory-commands-e2e'
