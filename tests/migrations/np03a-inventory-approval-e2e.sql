-- B-012 / 0202: GOV-002 approval adapter for stock commands (disposable PG17, rolled back).
-- One-checker and two-stage routes, maker-checker, Owner switches (CONTROL_DISABLED), stage/route changes after
-- approval, payload binding, other tenant. Calls run as `authenticated` with a signed actor.
\set ON_ERROR_STOP on
BEGIN;
INSERT INTO core10.templates(code,source_status,demo_allowed) VALUES ('sweets_bakery','available',true) ON CONFLICT (code) DO NOTHING;
INSERT INTO core10.tenants(id,slug) VALUES (941,'inva-a'),(942,'inva-b');
INSERT INTO core10.legal_entities(id,tenant_id,label) VALUES (9410,941,'Inva A'),(9420,942,'Inva B');
INSERT INTO core10.businesses(id,tenant_id,legal_entity_id,slug,template_code,request_key) VALUES
 (9411,941,9410,'inva-a1','sweets_bakery','inva-b1'),(9421,942,9420,'inva-b1','sweets_bakery','inva-b2');
INSERT INTO core10.sites(id,tenant_id,business_id,kind,label,request_key) VALUES
 (94111,941,9411,'factory','Factory','inva-s1'),(94112,941,9411,'showroom','Branch','inva-s2');
INSERT INTO core10.stock_locations(id,tenant_id,business_id,site_id,code) VALUES
 (941111,941,9411,94111,'F'),(941121,941,9411,94112,'S');
INSERT INTO core10.items(id,tenant_id,business_id,sku,name_en) VALUES (94101,941,9411,'FLOUR','Flour');
INSERT INTO core10.tenant_members(tenant_id,user_id,role) VALUES
 (941,'e1111111-1111-4111-8111-111111111111','tenant_owner'),(942,'e5555555-5555-4555-8555-555555555555','tenant_owner');
INSERT INTO core10.business_members(tenant_id,business_id,user_id,role,approval_actions) VALUES
 (941,9411,'e2222222-2222-4222-8222-222222222222','business_owner','{approval.decide}'),
 (941,9411,'e3333333-3333-4333-8333-333333333333','manager','{}');

CREATE FUNCTION pg_temp.as_user(p text) RETURNS void LANGUAGE sql AS $$
 SELECT set_config('request.jwt.claims',json_build_object('sub',p)::text,true), set_config('request.jwt.claim.sub',p,true) $$;
CREATE FUNCTION pg_temp.ok(p boolean, m text) RETURNS void LANGUAGE plpgsql AS $$
 BEGIN IF p IS DISTINCT FROM true THEN RAISE EXCEPTION 'INVA_ASSERT:%',m; END IF; END $$;
CREATE FUNCTION pg_temp.expect(q text, pre text) RETURNS void LANGUAGE plpgsql AS $$
 BEGIN BEGIN EXECUTE q; EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE pre||'%' THEN RETURN; END IF;
  RAISE EXCEPTION 'INVA_WRONG_ERROR expected=% got=% q=%',pre,SQLERRM,left(q,160); END;
  RAISE EXCEPTION 'INVA_EXPECTED_DENIAL:% q=%',pre,left(q,160); END $$;
CREATE FUNCTION pg_temp.cset(b bigint,f text,e boolean,g int,p jsonb,v int,key text) RETURNS jsonb LANGUAGE sql AS $$
 SELECT core10.control_set_v1(b,NULL,f,e,g::smallint,p,NULL,false,v,'test control change',key) $$;
-- create + confirm as the current actor; returns the confirmed command json
CREATE FUNCTION pg_temp.ready(k text,q numeric) RETURNS jsonb LANGUAGE sql AS $$
 SELECT core10.advance_inventory_command_v1((c->>'command_id')::bigint,'confirm',1,k||'-c')
 FROM (SELECT core10.create_inventory_command_v1(9411,'issue',941111,NULL,94101,q,NULL,k) c) x $$;
CREATE FUNCTION pg_temp.post(c jsonb,k text) RETURNS jsonb LANGUAGE sql AS $$
 SELECT core10.advance_inventory_command_v1((c->>'command_id')::bigint,'post',2,k) $$;
CREATE FUNCTION pg_temp.req(c jsonb,k text) RETURNS bigint LANGUAGE sql AS $$
 SELECT (core10.inventory_request_approval_v1((c->>'command_id')::bigint,k)->>'approval_request_id')::bigint $$;

SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('e1111111-1111-4111-8111-111111111111');
SELECT core10.advance_inventory_command_v1((x->>'command_id')::bigint,'post',2,'inva-seed-p') FROM (
 SELECT core10.advance_inventory_command_v1((core10.create_inventory_command_v1(9411,'receive',NULL,941111,94101,100,NULL,'inva-seed-0')->>'command_id')::bigint,'confirm',1,'inva-seed-c') x) y;
SELECT pg_temp.cset(9411,'inventory.issue',true,1,'{"staff_allowed":true}',0,'inva-ctl-0001');
SELECT core10.publish_approval_policy_v1(9411,'inventory','issue',120,'inva-policy-01');

-- ---------- one checker ----------
SELECT pg_temp.as_user('e2222222-2222-4222-8222-222222222222');
SELECT pg_temp.ready('inva-one-0001',10) AS c1 \gset
SELECT pg_temp.expect($q$SELECT pg_temp.post('$q$||:'c1'||$q$'::jsonb,'inva-one-p001')$q$,'INV_APPROVAL_REQUIRED');
SELECT pg_temp.expect($q$SELECT core10.inventory_request_approval_v1(-1,'inva-one-r000')$q$,'INV_SCOPE');
SELECT pg_temp.as_user('e1111111-1111-4111-8111-111111111111');
SELECT pg_temp.expect($q$SELECT pg_temp.req('$q$||:'c1'||$q$'::jsonb,'inva-one-r001')$q$,'INV_APPROVAL_MAKER_DENIED');
SELECT pg_temp.as_user('e2222222-2222-4222-8222-222222222222');
SELECT pg_temp.req(:'c1'::jsonb,'inva-one-r002') AS q1 \gset
SELECT pg_temp.ok(pg_temp.req(:'c1'::jsonb,'inva-one-r002')=:q1,'request replay returns the same approval');
SELECT pg_temp.expect($q$SELECT pg_temp.req('$q$||:'c1'||$q$'::jsonb,'inva-one-r003')$q$,'INV_APPROVAL_ALREADY_REQUESTED');
SELECT pg_temp.expect($q$SELECT pg_temp.post('$q$||:'c1'||$q$'::jsonb,'inva-one-p002')$q$,'INV_APPROVAL_NOT_EFFECTIVE');
SELECT pg_temp.expect($q$SELECT core10.decide_approval($q$||:q1||$q$,'approve','inva-one-self')$q$,'approval_not_authorized');
SELECT pg_temp.as_user('e5555555-5555-4555-8555-555555555555');
SELECT pg_temp.expect($q$SELECT core10.inventory_request_approval_v1($q$||(:'c1'::jsonb->>'command_id')||$q$,'inva-foreign-1')$q$,'INV_SCOPE');
SELECT pg_temp.expect($q$SELECT core10.decide_approval($q$||:q1||$q$,'approve','inva-foreign-2')$q$,'approval_not_authorized');
SELECT pg_temp.as_user('e1111111-1111-4111-8111-111111111111');
SELECT core10.decide_approval(:q1,'approve','inva-one-dec1');
SELECT pg_temp.as_user('e2222222-2222-4222-8222-222222222222');
SELECT pg_temp.post(:'c1'::jsonb,'inva-one-p003') AS c1p \gset
SELECT pg_temp.ok((:'c1p'::jsonb->>'status')='posted' AND (:'c1p'::jsonb->>'approval_request_id')::bigint=:q1,'approved command posted');
RESET ROLE;
SELECT pg_temp.ok((SELECT on_hand FROM core10.stock_balances_v1 WHERE location_id=941111 AND item_id=94101)=90,'balance 90');
SELECT pg_temp.ok((SELECT (payload->>'approval_request_id')::bigint FROM core10.canonical_audit_events_v1
 WHERE business_id=9411 AND source_ref='command:'||(:'c1'::jsonb->>'command_id')||':posted')=:q1,'posting audit names the approval');
SELECT pg_temp.ok((SELECT count(*) FROM core10.canonical_audit_events_v1 WHERE business_id=9411
 AND action='inventory.command_approval_requested')=1,'one approval-request audit event');
SET LOCAL ROLE authenticated;

-- ---------- Owner switches and stage changes fail closed ----------
SELECT pg_temp.as_user('e2222222-2222-4222-8222-222222222222');
SELECT pg_temp.ready('inva-off-0001',1) AS c2 \gset
SELECT pg_temp.as_user('e1111111-1111-4111-8111-111111111111');
SELECT pg_temp.cset(9411,'inventory.stock_event',false,0,'{}',0,'inva-ctl-0002');
SELECT pg_temp.as_user('e2222222-2222-4222-8222-222222222222');
SELECT pg_temp.expect($q$SELECT pg_temp.req('$q$||:'c2'||$q$'::jsonb,'inva-off-r001')$q$,'CONTROL_DISABLED:inventory.stock_event');
SELECT pg_temp.as_user('e1111111-1111-4111-8111-111111111111');
SELECT pg_temp.cset(9411,'inventory.stock_event',true,0,'{}',1,'inva-ctl-0003');
-- NP01 0111 ties explicit gov002.review stages to a matching approval route.
-- Exercise the disabled switch and the unconfigured explicit-route denial in
-- a rolled-back test savepoint, preserving the canonical default one-checker
-- review setting for the inventory posting flow below.
SAVEPOINT inv_review_switch;
SELECT pg_temp.cset(9411,'gov002.review',false,1,'{}',0,'inva-ctl-0004');
SELECT pg_temp.as_user('e2222222-2222-4222-8222-222222222222');
SELECT pg_temp.expect($q$SELECT pg_temp.req('$q$||:'c2'||$q$'::jsonb,'inva-off-r002')$q$,'CONTROL_DISABLED:gov002.review');
SELECT pg_temp.as_user('e1111111-1111-4111-8111-111111111111');
SELECT pg_temp.cset(9411,'gov002.review',true,1,'{}',1,'inva-ctl-0005');
SELECT pg_temp.as_user('e2222222-2222-4222-8222-222222222222');
SELECT pg_temp.expect(
 format('SELECT core10.inventory_request_approval_v1(%s,%L)',
  (:'c2'::jsonb->>'command_id')::bigint, 'inva-off-route-001'),
 'CONTROL_STAGE_MISMATCH');
ROLLBACK TO SAVEPOINT inv_review_switch;
-- A rolled-back switch leaves no persistent Control override or Audit receipt.
SELECT pg_temp.as_user('e2222222-2222-4222-8222-222222222222');
SELECT pg_temp.req(:'c2'::jsonb,'inva-off-r003') AS q2 \gset
SELECT pg_temp.as_user('e1111111-1111-4111-8111-111111111111');
SELECT core10.decide_approval(:q2,'approve','inva-off-dec1');
-- Owner raises the stage count after the approval: posting must refuse (no route has two stages yet)
SELECT pg_temp.cset(9411,'inventory.issue',true,2,'{"staff_allowed":true}',1,'inva-ctl-0006');
SELECT pg_temp.as_user('e2222222-2222-4222-8222-222222222222');
SELECT pg_temp.expect($q$SELECT pg_temp.post('$q$||:'c2'||$q$'::jsonb,'inva-off-p001')$q$,'INV_APPROVAL_ROUTE_MISMATCH');
SELECT pg_temp.ready('inva-mis-0001',1) AS c3 \gset
SELECT pg_temp.expect($q$SELECT pg_temp.req('$q$||:'c3'||$q$'::jsonb,'inva-mis-r001')$q$,'INV_APPROVAL_ROUTE_MISMATCH');
SELECT pg_temp.as_user('e1111111-1111-4111-8111-111111111111');
SELECT pg_temp.cset(9411,'inventory.issue',true,0,'{"staff_allowed":true}',2,'inva-ctl-0007');
SELECT pg_temp.as_user('e2222222-2222-4222-8222-222222222222');
SELECT pg_temp.expect($q$SELECT pg_temp.req('$q$||:'c3'||$q$'::jsonb,'inva-mis-r002')$q$,'INV_APPROVAL_STAGES_REQUIRED');
SELECT pg_temp.ok((pg_temp.post(:'c3'::jsonb,'inva-mis-p001')->>'status')='posted','zero stages posts without approval');
SELECT pg_temp.expect($q$SELECT core10.inventory_request_approval_v1((core10.create_inventory_command_v1(9411,'issue',941111,NULL,94101,1,NULL,'inva-draft-001')->>'command_id')::bigint,'inva-draft-r01')$q$,'INV_CONFIRM_FIRST');

-- ---------- two-stage route: business owner, then tenant owner; maker is the manager ----------
SELECT pg_temp.as_user('e1111111-1111-4111-8111-111111111111');
SELECT core10.configure_approval_route_v1((SELECT core10.publish_approval_policy_v1(9411,'inventory','issue',120,'inva-policy-02')),
 ARRAY['business_owner','tenant_owner'],'inva-route-01');
SELECT pg_temp.cset(9411,'inventory.issue',true,2,'{"staff_allowed":true}',3,'inva-ctl-0008');
SELECT pg_temp.as_user('e3333333-3333-4333-8333-333333333333');
SELECT pg_temp.ready('inva-two-0001',5) AS c4 \gset
SELECT pg_temp.req(:'c4'::jsonb,'inva-two-r001') AS q4 \gset
SELECT pg_temp.as_user('e1111111-1111-4111-8111-111111111111');
SELECT pg_temp.expect($q$SELECT core10.decide_approval($q$||:q4||$q$,'approve','inva-two-early')$q$,'approval_not_authorized');
SELECT pg_temp.as_user('e2222222-2222-4222-8222-222222222222');
SELECT core10.decide_approval(:q4,'approve','inva-two-dec1');
SELECT pg_temp.as_user('e3333333-3333-4333-8333-333333333333');
SELECT pg_temp.expect($q$SELECT pg_temp.post('$q$||:'c4'||$q$'::jsonb,'inva-two-p001')$q$,'INV_APPROVAL_NOT_EFFECTIVE');
SELECT pg_temp.as_user('e1111111-1111-4111-8111-111111111111');
SELECT core10.decide_approval(:q4,'approve','inva-two-dec2');
SELECT pg_temp.as_user('e3333333-3333-4333-8333-333333333333');
SELECT pg_temp.ok((pg_temp.post(:'c4'::jsonb,'inva-two-p002')->>'status')='posted','two-stage approved command posted');
RESET ROLE;
SELECT pg_temp.ok((SELECT count(*) FROM core10.approval_stage_receipts_v1 WHERE request_id=:q4)=2,'two stage receipts');
SELECT pg_temp.ok((SELECT on_hand FROM core10.stock_balances_v1 WHERE location_id=941111 AND item_id=94101)=84,'balance 84');
SELECT pg_temp.ok(NOT EXISTS(SELECT 1 FROM core10.inventory_reconciliation_v1 WHERE NOT reconciled),'reconciled');
SELECT pg_temp.ok((SELECT status FROM core10.control_rpc_map_v1 WHERE rpc_name='inventory_request_approval_v1')='enforced','registry enforced');
SELECT pg_temp.ok(NOT has_function_privilege('anon','core10.inventory_request_approval_v1(bigint,text)','execute'),'anon cannot request');
SELECT pg_temp.ok(NOT has_function_privilege('authenticated','core10._inventory_approval_gate_v1(bigint,integer)','execute'),'gate is internal');
ROLLBACK;
\echo 'PASS np03a-inventory-approval-e2e'
