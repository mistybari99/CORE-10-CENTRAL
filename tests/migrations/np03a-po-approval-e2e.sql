-- B-012 / 0206: GOV-002 approval adapter for purchase orders (disposable PG17, rolled back).
-- One-checker and two-stage routes, maker-only request, self/foreign denials, Owner switches (CONTROL_DISABLED),
-- stage/route changes after approval, payload/version binding (edited draft), stages = 0 unchanged.
-- Calls run as `authenticated` with a signed actor. Tenants 1401/1402 are used by no other test.
\set ON_ERROR_STOP on
BEGIN;
INSERT INTO core10.templates(code,source_status,demo_allowed) VALUES ('sweets_bakery','available',true) ON CONFLICT (code) DO NOTHING;
INSERT INTO core10.tenants(id,slug) VALUES (1401,'poa-a'),(1402,'poa-b');
INSERT INTO core10.legal_entities(id,tenant_id,label) VALUES (14010,1401,'PO Approval A'),(14020,1402,'PO Approval B');
INSERT INTO core10.businesses(id,tenant_id,legal_entity_id,slug,template_code,request_key) VALUES
 (14011,1401,14010,'poa-a1','sweets_bakery','poa-biz-1'),(14021,1402,14020,'poa-b1','sweets_bakery','poa-biz-2');
INSERT INTO core10.sites(id,tenant_id,business_id,kind,label,request_key) VALUES
 (140111,1401,14011,'godown','Godown','poa-site-1');
INSERT INTO core10.stock_locations(id,tenant_id,business_id,site_id,code) VALUES (1401111,1401,14011,140111,'G');
INSERT INTO core10.items(id,tenant_id,business_id,sku,name_en,name_bn,status) VALUES
 (140101,1401,14011,'SUGAR','Sugar','চিনি','active'),(140102,1401,14011,'FLOUR','Flour','আটা','active');
INSERT INTO core10.master_parties_v1(id,tenant_id,business_id,code,party_kind,name_en,name_bn,status) VALUES
 (140151,1401,14011,'SUP-1','supplier','Sugar Mills','চিনি কল','active');
INSERT INTO core10.tenant_members(tenant_id,user_id,role) VALUES
 (1401,'a1111111-1111-4111-8111-111111111111','tenant_owner'),(1402,'a5555555-5555-4555-8555-555555555555','tenant_owner');
INSERT INTO core10.business_members(tenant_id,business_id,user_id,role,approval_actions) VALUES
 (1401,14011,'a2222222-2222-4222-8222-222222222222','business_owner','{approval.decide}'),
 (1401,14011,'a3333333-3333-4333-8333-333333333333','manager','{}');

CREATE FUNCTION pg_temp.as_user(p text) RETURNS void LANGUAGE sql AS $$
 SELECT set_config('request.jwt.claims',json_build_object('sub',p)::text,true), set_config('request.jwt.claim.sub',p,true) $$;
CREATE FUNCTION pg_temp.ok(p boolean, m text) RETURNS void LANGUAGE plpgsql AS $$
 BEGIN IF p IS DISTINCT FROM true THEN RAISE EXCEPTION 'POA_ASSERT:%',m; END IF; END $$;
CREATE FUNCTION pg_temp.expect(q text, pre text) RETURNS void LANGUAGE plpgsql AS $$
 BEGIN BEGIN EXECUTE q; EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE pre||'%' THEN RETURN; END IF;
  RAISE EXCEPTION 'POA_WRONG_ERROR expected=% got=% q=%',pre,SQLERRM,left(q,160); END;
  RAISE EXCEPTION 'POA_EXPECTED_DENIAL:% q=%',pre,left(q,160); END $$;
CREATE FUNCTION pg_temp.cset(f text,e boolean,g int,p jsonb,v int,key text) RETURNS jsonb LANGUAGE sql AS $$
 SELECT core10.control_set_v1(14011,NULL,f,e,g::smallint,p,NULL,false,v,'test control change',key) $$;
-- new draft PO as the current actor; returns its id
CREATE FUNCTION pg_temp.po(q numeric,key text) RETURNS bigint LANGUAGE sql AS $$
 SELECT (core10.procurement_save_po_v1(14011,NULL,140111,140151,
  jsonb_build_array(jsonb_build_object('item_id',140101,'quantity',q,'unit_price',50)),NULL,NULL,0,key)->>'po_id')::bigint $$;
CREATE FUNCTION pg_temp.req(po bigint,key text) RETURNS bigint LANGUAGE sql AS $$
 SELECT (core10.procurement_request_po_approval_v1(po,key)->>'approval_request_id')::bigint $$;
CREATE FUNCTION pg_temp.appr(po bigint,v int,key text) RETURNS jsonb LANGUAGE sql AS $$
 SELECT core10.procurement_advance_po_v1(po,'approve',v,key) $$;

SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('a1111111-1111-4111-8111-111111111111');
SELECT pg_temp.cset('procurement.purchase_order',true,1,'{}',0,'poa-ctl-0001');
SELECT core10.publish_approval_policy_v1(14011,'procurement','purchase_order',120,'poa-policy-01');

-- ---------- one checker: manager is the maker, tenant owner decides, business owner applies ----------
SELECT pg_temp.as_user('a3333333-3333-4333-8333-333333333333');
SELECT pg_temp.po(10,'poa-one-po01') AS p1 \gset
SELECT pg_temp.as_user('a2222222-2222-4222-8222-222222222222');
SELECT pg_temp.expect($q$SELECT pg_temp.appr($q$||:p1||$q$,1,'poa-one-a001')$q$,'PROC_APPROVAL_REQUIRED');
SELECT pg_temp.expect($q$SELECT core10.procurement_request_po_approval_v1(-1,'poa-one-r000')$q$,'PROC_SCOPE');
SELECT pg_temp.expect($q$SELECT pg_temp.req($q$||:p1||$q$,'bad key')$q$,'PROC_INVALID_ACTION');
-- only the maker may ask for approval
SELECT pg_temp.expect($q$SELECT pg_temp.req($q$||:p1||$q$,'poa-one-r001')$q$,'PROC_APPROVAL_MAKER_DENIED');
SELECT pg_temp.as_user('a1111111-1111-4111-8111-111111111111');
SELECT pg_temp.expect($q$SELECT pg_temp.req($q$||:p1||$q$,'poa-one-r002')$q$,'PROC_APPROVAL_MAKER_DENIED');
SELECT pg_temp.as_user('a3333333-3333-4333-8333-333333333333');
SELECT pg_temp.req(:p1,'poa-one-r003') AS q1 \gset
SELECT pg_temp.ok(pg_temp.req(:p1,'poa-one-r003')=:q1,'request replay returns the same approval');
SELECT pg_temp.expect($q$SELECT pg_temp.req($q$||:p1||$q$,'poa-one-r004')$q$,'PROC_APPROVAL_ALREADY_REQUESTED');
-- the maker can neither decide nor apply
SELECT pg_temp.expect($q$SELECT core10.decide_approval($q$||:q1||$q$,'approve','poa-one-self')$q$,'approval_not_authorized');
SELECT pg_temp.expect($q$SELECT pg_temp.appr($q$||:p1||$q$,1,'poa-one-a002')$q$,'PROC_PERMISSION_DENIED');
SELECT pg_temp.as_user('a2222222-2222-4222-8222-222222222222');
SELECT pg_temp.expect($q$SELECT pg_temp.appr($q$||:p1||$q$,1,'poa-one-a003')$q$,'PROC_APPROVAL_NOT_EFFECTIVE');
-- other tenant sees nothing and decides nothing
SELECT pg_temp.as_user('a5555555-5555-4555-8555-555555555555');
SELECT pg_temp.expect($q$SELECT pg_temp.req($q$||:p1||$q$,'poa-foreign-1')$q$,'PROC_SCOPE');
SELECT pg_temp.expect($q$SELECT core10.decide_approval($q$||:q1||$q$,'approve','poa-foreign-2')$q$,'approval_not_authorized');
SELECT pg_temp.expect($q$SELECT pg_temp.appr($q$||:p1||$q$,1,'poa-foreign-3')$q$,'PROC_SCOPE');
SELECT pg_temp.as_user('a1111111-1111-4111-8111-111111111111');
SELECT core10.decide_approval(:q1,'approve','poa-one-dec1');
SELECT pg_temp.as_user('a2222222-2222-4222-8222-222222222222');
SELECT pg_temp.appr(:p1,1,'poa-one-a004') AS a1 \gset
SELECT pg_temp.ok((:'a1'::jsonb->>'status')='approved' AND (:'a1'::jsonb->>'approval_request_id')::bigint=:q1
 AND (:'a1'::jsonb->>'approval_stage_count')::int=1,'approved PO names its approval');
SELECT pg_temp.ok((pg_temp.appr(:p1,1,'poa-one-a004')->>'replayed')::boolean,'approve replay');
SELECT pg_temp.expect($q$SELECT pg_temp.req($q$||:p1||$q$,'poa-one-r005')$q$,'PROC_INVALID_TRANSITION');
-- the approved PO can be received (GRN path unchanged)
SELECT pg_temp.ok((core10.procurement_receive_v1(:p1,1401111,'[{"line_no":1,"quantity":4}]',NULL,'poa-one-grn1')->>'status')='received','approved PO receivable');
RESET ROLE;
SELECT pg_temp.ok((SELECT approval_request_id FROM core10.purchase_orders_v1 WHERE id=:p1)=:q1,'PO row carries the approval');
SELECT pg_temp.ok((SELECT (payload->>'approval_request_id')::bigint FROM core10.canonical_audit_events_v1
 WHERE business_id=14011 AND source_ref='po:'||:p1||':approve')=:q1,'approve audit names the approval');
SELECT pg_temp.ok((SELECT count(*) FROM core10.canonical_audit_events_v1 WHERE business_id=14011
 AND action='procurement.po_approval_requested')=1,'one approval-request audit event');
SELECT pg_temp.ok((SELECT domain_v1='procurement' AND action_code_v1='purchase_order' AND source_key_v1='procurement:po:'||:p1
 AND source_version_v1=1 FROM core10.approval_requests WHERE id=:q1),'request bound to procurement / purchase_order / PO version');
SET LOCAL ROLE authenticated;

-- ---------- editing the draft after approval fails closed; a fresh request for the new version is allowed ----------
SELECT pg_temp.as_user('a3333333-3333-4333-8333-333333333333');
SELECT pg_temp.po(5,'poa-edt-po01') AS p2 \gset
SELECT pg_temp.req(:p2,'poa-edt-r001') AS q2 \gset
SELECT pg_temp.as_user('a1111111-1111-4111-8111-111111111111');
SELECT core10.decide_approval(:q2,'approve','poa-edt-dec1');
SELECT pg_temp.as_user('a3333333-3333-4333-8333-333333333333');
SELECT core10.procurement_save_po_v1(14011,:p2,140111,140151,'[{"item_id":140101,"quantity":500,"unit_price":50}]',NULL,NULL,1,'poa-edt-sv01');
SELECT pg_temp.as_user('a2222222-2222-4222-8222-222222222222');
SELECT pg_temp.expect($q$SELECT pg_temp.appr($q$||:p2||$q$,2,'poa-edt-a001')$q$,'approval_stale_or_payload_changed');
SELECT pg_temp.as_user('a3333333-3333-4333-8333-333333333333');
SELECT pg_temp.req(:p2,'poa-edt-r002') AS q2b \gset
SELECT pg_temp.ok(:q2b<>:q2,'new request for the edited draft');
SELECT pg_temp.expect($q$SELECT pg_temp.req($q$||:p2||$q$,'poa-edt-r003')$q$,'PROC_APPROVAL_ALREADY_REQUESTED');
SELECT pg_temp.as_user('a1111111-1111-4111-8111-111111111111');
SELECT core10.decide_approval(:q2b,'approve','poa-edt-dec2');
SELECT pg_temp.as_user('a2222222-2222-4222-8222-222222222222');
SELECT pg_temp.ok((pg_temp.appr(:p2,2,'poa-edt-a002')->>'approval_request_id')::bigint=:q2b,'edited draft approved on its own approval');

-- ---------- Owner switches and stage changes fail closed ----------
SELECT pg_temp.as_user('a3333333-3333-4333-8333-333333333333');
SELECT pg_temp.po(1,'poa-off-po01') AS p3 \gset
SELECT pg_temp.as_user('a1111111-1111-4111-8111-111111111111');
SELECT pg_temp.cset('procurement.purchase_order',false,1,'{}',1,'poa-ctl-0002');
SELECT pg_temp.as_user('a3333333-3333-4333-8333-333333333333');
SELECT pg_temp.expect($q$SELECT pg_temp.req($q$||:p3||$q$,'poa-off-r001')$q$,'CONTROL_DISABLED:procurement.purchase_order');
SELECT pg_temp.as_user('a1111111-1111-4111-8111-111111111111');
SELECT pg_temp.cset('procurement.purchase_order',true,1,'{}',2,'poa-ctl-0003');
SELECT pg_temp.cset('gov002.review',false,1,'{}',0,'poa-ctl-0004');
SELECT pg_temp.as_user('a3333333-3333-4333-8333-333333333333');
SELECT pg_temp.expect($q$SELECT pg_temp.req($q$||:p3||$q$,'poa-off-r002')$q$,'CONTROL_DISABLED:gov002.review');
SELECT pg_temp.as_user('a1111111-1111-4111-8111-111111111111');
SELECT pg_temp.cset('gov002.review',true,1,'{}',1,'poa-ctl-0005');
SELECT pg_temp.as_user('a3333333-3333-4333-8333-333333333333');
SELECT pg_temp.req(:p3,'poa-off-r003') AS q3 \gset
SELECT pg_temp.as_user('a1111111-1111-4111-8111-111111111111');
SELECT core10.decide_approval(:q3,'approve','poa-off-dec1');
-- Owner raises the stage count after the decision: approve must refuse (no route has two stages yet)
SELECT pg_temp.cset('procurement.purchase_order',true,2,'{}',3,'poa-ctl-0006');
SELECT pg_temp.as_user('a2222222-2222-4222-8222-222222222222');
SELECT pg_temp.expect($q$SELECT pg_temp.appr($q$||:p3||$q$,1,'poa-off-a001')$q$,'PROC_APPROVAL_ROUTE_MISMATCH');
SELECT pg_temp.as_user('a3333333-3333-4333-8333-333333333333');
SELECT pg_temp.po(1,'poa-mis-po01') AS p4 \gset
SELECT pg_temp.expect($q$SELECT pg_temp.req($q$||:p4||$q$,'poa-mis-r001')$q$,'PROC_APPROVAL_ROUTE_MISMATCH');
-- stages = 0: no request needed or accepted, approve works as in 0203
SELECT pg_temp.as_user('a1111111-1111-4111-8111-111111111111');
SELECT pg_temp.cset('procurement.purchase_order',true,0,'{}',4,'poa-ctl-0007');
SELECT pg_temp.as_user('a3333333-3333-4333-8333-333333333333');
SELECT pg_temp.expect($q$SELECT pg_temp.req($q$||:p4||$q$,'poa-mis-r002')$q$,'PROC_APPROVAL_STAGES_REQUIRED');
SELECT pg_temp.as_user('a2222222-2222-4222-8222-222222222222');
SELECT pg_temp.appr(:p4,1,'poa-mis-a001') AS a4 \gset
SELECT pg_temp.ok((:'a4'::jsonb->>'status')='approved' AND NOT (:'a4'::jsonb ? 'approval_request_id'),'zero stages approves without GOV-002');

-- ---------- two-stage route: business owner, then tenant owner; maker is the manager ----------
SELECT pg_temp.as_user('a1111111-1111-4111-8111-111111111111');
SELECT core10.configure_approval_route_v1((SELECT core10.publish_approval_policy_v1(14011,'procurement','purchase_order',120,'poa-policy-02')),
 ARRAY['business_owner','tenant_owner'],'poa-route-01');
SELECT pg_temp.cset('procurement.purchase_order',true,2,'{}',5,'poa-ctl-0008');
SELECT pg_temp.as_user('a3333333-3333-4333-8333-333333333333');
SELECT pg_temp.po(7,'poa-two-po01') AS p5 \gset
SELECT pg_temp.req(:p5,'poa-two-r001') AS q5 \gset
SELECT pg_temp.as_user('a1111111-1111-4111-8111-111111111111');
SELECT pg_temp.expect($q$SELECT core10.decide_approval($q$||:q5||$q$,'approve','poa-two-early')$q$,'approval_not_authorized');
SELECT pg_temp.as_user('a2222222-2222-4222-8222-222222222222');
SELECT core10.decide_approval(:q5,'approve','poa-two-dec1');
SELECT pg_temp.expect($q$SELECT pg_temp.appr($q$||:p5||$q$,1,'poa-two-a001')$q$,'PROC_APPROVAL_NOT_EFFECTIVE');
SELECT pg_temp.as_user('a1111111-1111-4111-8111-111111111111');
SELECT core10.decide_approval(:q5,'approve','poa-two-dec2');
-- stage count changed after the final decision: fail closed until it matches the route again
SELECT pg_temp.cset('procurement.purchase_order',true,3,'{}',6,'poa-ctl-0009');
SELECT pg_temp.as_user('a2222222-2222-4222-8222-222222222222');
SELECT pg_temp.expect($q$SELECT pg_temp.appr($q$||:p5||$q$,1,'poa-two-a002')$q$,'PROC_APPROVAL_ROUTE_MISMATCH');
SELECT pg_temp.as_user('a1111111-1111-4111-8111-111111111111');
SELECT pg_temp.cset('procurement.purchase_order',true,2,'{}',7,'poa-ctl-0010');
SELECT pg_temp.as_user('a2222222-2222-4222-8222-222222222222');
SELECT pg_temp.appr(:p5,1,'poa-two-a003') AS a5 \gset
SELECT pg_temp.ok((:'a5'::jsonb->>'status')='approved' AND (:'a5'::jsonb->>'approval_stage_count')::int=2,'two-stage approved PO');
RESET ROLE;
SELECT pg_temp.ok((SELECT count(*) FROM core10.approval_stage_receipts_v1 WHERE request_id=:q5)=2,'two stage receipts');
SELECT pg_temp.ok((SELECT status FROM core10.purchase_orders_v1 WHERE id=:p3)='draft','fail-closed PO still a draft');
SELECT pg_temp.ok((SELECT status FROM core10.control_rpc_map_v1 WHERE rpc_name='procurement_request_po_approval_v1')='enforced','registry enforced');
SELECT pg_temp.ok(NOT has_function_privilege('anon','core10.procurement_request_po_approval_v1(bigint,text)','execute'),'anon cannot request');
SELECT pg_temp.ok(NOT has_function_privilege('authenticated','core10._proc_po_approval_gate_v1(bigint,integer)','execute'),'gate is internal');
SELECT pg_temp.ok(NOT has_function_privilege('authenticated','core10._proc_po_approval_payload_v1(bigint)','execute'),'payload builder is internal');
ROLLBACK;
\echo 'PASS np03a-po-approval-e2e'
