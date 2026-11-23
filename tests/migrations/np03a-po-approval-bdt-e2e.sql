-- B-012 / 0210: purchase-order approval payload in BDT against Owner-configured GOV-002 thresholds
-- (disposable PG17, rolled back). Owner decision 2026-11-23: the PO approval threshold currency is BDT.
-- Proves: payload unit 'BDT' and amount = PO total as a JSON number with <= 2 decimals; a BDT threshold lets a PO at or
-- above the minimum be requested, approved and received/posted; below the minimum is refused (GOV-002
-- approval_threshold_not_met); the threshold's precision rule holds; a non-BDT unit threshold is refused; the legacy
-- 'currency_total' unit cannot even be configured; a request bound to the pre-0210 payload ('currency_total') fails
-- closed on approve and does not block a fresh BDT request; managers and other tenants cannot configure thresholds.
-- Calls run as `authenticated` with a signed actor. Tenants 2001/2002 are used by no other migration test.
\set ON_ERROR_STOP on
BEGIN;
INSERT INTO core10.templates(code,source_status,demo_allowed) VALUES ('sweets_bakery','available',true) ON CONFLICT (code) DO NOTHING;
INSERT INTO core10.tenants(id,slug) VALUES (2001,'pob-a'),(2002,'pob-b');
INSERT INTO core10.legal_entities(id,tenant_id,label) VALUES (20010,2001,'PO BDT A'),(20020,2002,'PO BDT B');
INSERT INTO core10.businesses(id,tenant_id,legal_entity_id,slug,template_code,request_key) VALUES
 (20011,2001,20010,'pob-a1','sweets_bakery','pob-biz-1'),(20021,2002,20020,'pob-b1','sweets_bakery','pob-biz-2');
INSERT INTO core10.sites(id,tenant_id,business_id,kind,label,request_key) VALUES
 (200111,2001,20011,'godown','Godown','pob-site-1');
INSERT INTO core10.stock_locations(id,tenant_id,business_id,site_id,code) VALUES (2001111,2001,20011,200111,'G');
INSERT INTO core10.items(id,tenant_id,business_id,sku,name_en,name_bn,status) VALUES
 (200101,2001,20011,'SUGAR','Sugar','চিনি','active');
INSERT INTO core10.master_parties_v1(id,tenant_id,business_id,code,party_kind,name_en,name_bn,status) VALUES
 (200151,2001,20011,'SUP-1','supplier','Sugar Mills','চিনি কল','active');
INSERT INTO core10.tenant_members(tenant_id,user_id,role) VALUES
 (2001,'b1111111-1111-4111-8111-111111111111','tenant_owner'),(2002,'b5555555-5555-4555-8555-555555555555','tenant_owner');
INSERT INTO core10.business_members(tenant_id,business_id,user_id,role,approval_actions) VALUES
 (2001,20011,'b2222222-2222-4222-8222-222222222222','business_owner','{approval.decide}'),
 (2001,20011,'b3333333-3333-4333-8333-333333333333','manager','{}');

CREATE FUNCTION pg_temp.as_user(p text) RETURNS void LANGUAGE sql AS $$
 SELECT set_config('request.jwt.claims',json_build_object('sub',p)::text,true), set_config('request.jwt.claim.sub',p,true) $$;
CREATE FUNCTION pg_temp.ok(p boolean, m text) RETURNS void LANGUAGE plpgsql AS $$
 BEGIN IF p IS DISTINCT FROM true THEN RAISE EXCEPTION 'POB_ASSERT:%',m; END IF; END $$;
CREATE FUNCTION pg_temp.expect(q text, pre text) RETURNS void LANGUAGE plpgsql AS $$
 BEGIN BEGIN EXECUTE q; EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE pre||'%' THEN RETURN; END IF;
  RAISE EXCEPTION 'POB_WRONG_ERROR expected=% got=% q=%',pre,SQLERRM,left(q,160); END;
  RAISE EXCEPTION 'POB_EXPECTED_DENIAL:% q=%',pre,left(q,160); END $$;
CREATE FUNCTION pg_temp.cset(f text,e boolean,g int,p jsonb,v int,key text) RETURNS jsonb LANGUAGE sql AS $$
 SELECT core10.control_set_v1(20011,NULL,f,e,g::smallint,p,NULL,false,v,'test control change',key) $$;
-- new draft PO (one line) as the current actor; returns its id
CREATE FUNCTION pg_temp.po(q numeric,price numeric,key text) RETURNS bigint LANGUAGE sql AS $$
 SELECT (core10.procurement_save_po_v1(20011,NULL,200111,200151,
  jsonb_build_array(jsonb_build_object('item_id',200101,'quantity',q,'unit_price',price)),NULL,NULL,0,key)->>'po_id')::bigint $$;
CREATE FUNCTION pg_temp.req(po bigint,key text) RETURNS bigint LANGUAGE sql AS $$
 SELECT (core10.procurement_request_po_approval_v1(po,key)->>'approval_request_id')::bigint $$;
CREATE FUNCTION pg_temp.appr(po bigint,v int,key text) RETURNS jsonb LANGUAGE sql AS $$
 SELECT core10.procurement_advance_po_v1(po,'approve',v,key) $$;
CREATE FUNCTION pg_temp.pol(key text) RETURNS bigint LANGUAGE sql AS $$
 SELECT core10.publish_approval_policy_v1(20011,'procurement','purchase_order',120,key) $$;

SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('b1111111-1111-4111-8111-111111111111');
SELECT pg_temp.cset('procurement.purchase_order',true,1,'{}',0,'pob-ctl-0001');

-- ---------- payload shape: unit BDT, amount = PO total as a JSON number with <= 2 decimals ----------
SELECT pg_temp.as_user('b3333333-3333-4333-8333-333333333333');
SELECT pg_temp.po(30,50.25,'pob-shp-po01') AS p0 \gset
RESET ROLE;
SELECT core10._proc_po_approval_payload_v1(:p0) AS pay0 \gset
SELECT pg_temp.ok((:'pay0'::jsonb->>'unit')='BDT','payload unit is BDT');
SELECT pg_temp.ok(jsonb_typeof(:'pay0'::jsonb->'amount')='number','payload amount is a JSON number');
SELECT pg_temp.ok((:'pay0'::jsonb->>'amount')::numeric=(SELECT total_amount FROM core10.purchase_orders_v1 WHERE id=:p0)
 AND (:'pay0'::jsonb->>'amount')::numeric=1507.50,'payload amount equals the PO total (30 x 50.25)');
SELECT pg_temp.ok(scale((:'pay0'::jsonb->>'amount')::numeric)<=2,'payload amount has at most 2 decimals');
SELECT pg_temp.ok(core10._proc_po_approval_payload_v1(:p0)=:'pay0'::jsonb,'payload is deterministic (request = verification)');
SET LOCAL ROLE authenticated;

-- ---------- the legacy unit can never be an Owner threshold; only the Owner configures ----------
SELECT pg_temp.as_user('b1111111-1111-4111-8111-111111111111');
SELECT pg_temp.pol('pob-policy-01') AS pol1 \gset
SELECT pg_temp.expect($q$SELECT core10.configure_approval_threshold_v1($q$||:pol1||$q$,'currency','currency_total',1000,2,'pob-thr-legacy')$q$,'invalid_approval_threshold');
SELECT pg_temp.as_user('b3333333-3333-4333-8333-333333333333');
SELECT pg_temp.expect($q$SELECT core10.configure_approval_threshold_v1($q$||:pol1||$q$,'currency','BDT',1000,2,'pob-thr-mgr01')$q$,'threshold_not_authorized');
SELECT pg_temp.as_user('b5555555-5555-4555-8555-555555555555');
SELECT pg_temp.expect($q$SELECT core10.configure_approval_threshold_v1($q$||:pol1||$q$,'currency','BDT',1000,2,'pob-thr-for01')$q$,'threshold_not_authorized');
SELECT pg_temp.as_user('b1111111-1111-4111-8111-111111111111');
SELECT pg_temp.ok(core10.configure_approval_threshold_v1(:pol1,'currency','BDT',1000.00,2,'pob-thr-bdt01')=:pol1,'Owner configures a BDT threshold');
SELECT pg_temp.ok(core10.configure_approval_threshold_v1(:pol1,'currency','BDT',1000.00,2,'pob-thr-bdt01')=:pol1,'threshold replay');

-- ---------- above the minimum: requested, approved, received and posted ----------
SELECT pg_temp.as_user('b3333333-3333-4333-8333-333333333333');
SELECT pg_temp.ok(core10.assess_current_approval_threshold_v1(20011,'procurement','purchase_order',:'pay0'::jsonb)='REVIEW_REQUIRED','1507.50 BDT assessed as review required');
SELECT pg_temp.req(:p0,'pob-abv-r001') AS q0 \gset
SELECT pg_temp.ok(pg_temp.req(:p0,'pob-abv-r001')=:q0,'request replay returns the same approval');
SELECT pg_temp.expect($q$SELECT pg_temp.req($q$||:p0||$q$,'pob-abv-r002')$q$,'PROC_APPROVAL_ALREADY_REQUESTED');
-- other tenant: no request, no decision, no approve
SELECT pg_temp.as_user('b5555555-5555-4555-8555-555555555555');
SELECT pg_temp.expect($q$SELECT pg_temp.req($q$||:p0||$q$,'pob-for-r001')$q$,'PROC_SCOPE');
SELECT pg_temp.expect($q$SELECT core10.decide_approval($q$||:q0||$q$,'approve','pob-for-dec1')$q$,'approval_not_authorized');
SELECT pg_temp.expect($q$SELECT pg_temp.appr($q$||:p0||$q$,1,'pob-for-a001')$q$,'PROC_SCOPE');
SELECT pg_temp.as_user('b1111111-1111-4111-8111-111111111111');
SELECT core10.decide_approval(:q0,'approve','pob-abv-dec1');
SELECT pg_temp.as_user('b2222222-2222-4222-8222-222222222222');
SELECT pg_temp.appr(:p0,1,'pob-abv-a001') AS a0 \gset
SELECT pg_temp.ok((:'a0'::jsonb->>'status')='approved' AND (:'a0'::jsonb->>'approval_request_id')::bigint=:q0
 AND (:'a0'::jsonb->>'approval_stage_count')::int=1,'BDT-threshold PO approved on its approval');
SELECT core10.procurement_receive_v1(:p0,2001111,'[{"line_no":1,"quantity":30}]',NULL,'pob-abv-grn1') AS g0 \gset
SELECT core10.procurement_inspect_v1((:'g0'::jsonb->>'grn_id')::bigint,'[{"line_no":1,"accepted_qty":30}]',1,'pob-abv-qc01') AS g0 \gset
SELECT core10.procurement_post_grn_v1((:'g0'::jsonb->>'grn_id')::bigint,2,'pob-abv-post') AS g0 \gset
SELECT pg_temp.ok((:'g0'::jsonb->>'status')='posted','approved BDT PO received and posted to stock');
RESET ROLE;
SELECT pg_temp.ok((SELECT policy_id_v1=:pol1 AND payload_sha256_v1=encode(sha256(convert_to(:'pay0'::text,'UTF8')),'hex')
 FROM core10.approval_requests WHERE id=:q0),'request bound to the BDT policy and the BDT payload digest');
SELECT pg_temp.ok((SELECT coalesce(sum(delta),0) FROM core10.stock_movements WHERE item_id=200101 AND location_id=2001111)=30,'30 units on the one ledger');
SET LOCAL ROLE authenticated;

-- ---------- at the minimum (GTE) is accepted; below the minimum is refused ----------
SELECT pg_temp.as_user('b3333333-3333-4333-8333-333333333333');
SELECT pg_temp.po(20,50,'pob-eq-po01') AS p1 \gset
SELECT pg_temp.ok(pg_temp.req(:p1,'pob-eq-r001') IS NOT NULL,'exactly 1000.00 BDT may be requested');
SELECT pg_temp.po(19,50,'pob-blw-po01') AS p2 \gset
RESET ROLE;
SELECT core10._proc_po_approval_payload_v1(:p2) AS pay2 \gset
SET LOCAL ROLE authenticated;
SELECT pg_temp.ok(core10.assess_current_approval_threshold_v1(20011,'procurement','purchase_order',:'pay2'::jsonb)='BELOW_THRESHOLD','950.00 BDT assessed below threshold');
SELECT pg_temp.expect($q$SELECT pg_temp.req($q$||:p2||$q$,'pob-blw-r001')$q$,'approval_threshold_not_met');
SELECT pg_temp.as_user('b2222222-2222-4222-8222-222222222222');
SELECT pg_temp.expect($q$SELECT pg_temp.appr($q$||:p2||$q$,1,'pob-blw-a001')$q$,'PROC_APPROVAL_REQUIRED');
RESET ROLE;
SELECT pg_temp.ok((SELECT status='draft' AND approval_request_id IS NULL FROM core10.purchase_orders_v1 WHERE id=:p2),'below-minimum PO stays an unrequested draft');
SET LOCAL ROLE authenticated;

-- ---------- the Owner's precision rule: a whole-taka threshold refuses a total with paisa ----------
SELECT pg_temp.as_user('b1111111-1111-4111-8111-111111111111');
SELECT pg_temp.pol('pob-policy-02') AS pol2 \gset
SELECT core10.configure_approval_threshold_v1(:pol2,'currency','BDT',1000,0,'pob-thr-bdt02');
SELECT pg_temp.as_user('b3333333-3333-4333-8333-333333333333');
SELECT pg_temp.po(30,50.25,'pob-prc-po01') AS p3 \gset
SELECT pg_temp.expect($q$SELECT pg_temp.req($q$||:p3||$q$,'pob-prc-r001')$q$,'approval_threshold_precision_invalid');
SELECT pg_temp.po(30,50,'pob-prc-po02') AS p4 \gset
SELECT pg_temp.ok(pg_temp.req(:p4,'pob-prc-r002') IS NOT NULL,'1500.00 BDT meets a whole-taka threshold');

-- ---------- a non-BDT unit threshold refuses every PO request ----------
SELECT pg_temp.as_user('b1111111-1111-4111-8111-111111111111');
SELECT pg_temp.pol('pob-policy-03') AS pol3 \gset
SELECT core10.configure_approval_threshold_v1(:pol3,'currency','USD',10,2,'pob-thr-usd03');
SELECT pg_temp.as_user('b3333333-3333-4333-8333-333333333333');
SELECT pg_temp.po(30,50,'pob-usd-po01') AS p5 \gset
SELECT pg_temp.expect($q$SELECT pg_temp.req($q$||:p5||$q$,'pob-usd-r001')$q$,'approval_threshold_unit_or_amount_invalid');
SELECT pg_temp.as_user('b1111111-1111-4111-8111-111111111111');
SELECT pg_temp.pol('pob-policy-04') AS pol4 \gset
SELECT core10.configure_approval_threshold_v1(:pol4,'quantity','KG',1,2,'pob-thr-kg004');
SELECT pg_temp.as_user('b3333333-3333-4333-8333-333333333333');
SELECT pg_temp.expect($q$SELECT pg_temp.req($q$||:p5||$q$,'pob-usd-r002')$q$,'approval_threshold_unit_or_amount_invalid');
RESET ROLE;
SELECT pg_temp.ok((SELECT approval_request_id IS NULL FROM core10.purchase_orders_v1 WHERE id=:p5),'non-BDT refusal left no request');
SET LOCAL ROLE authenticated;

-- ---------- a request bound to the pre-0210 payload (unit 'currency_total') fails closed ----------
-- No threshold on this policy (only then could 0206 have accepted the old unit). The old request is rebuilt exactly as
-- 0206 built it: the 0210 payload with unit 'currency_total' (amount was the same numeric(20,2) total).
SELECT pg_temp.as_user('b1111111-1111-4111-8111-111111111111');
SELECT pg_temp.pol('pob-policy-05') AS pol5 \gset
SELECT pg_temp.as_user('b3333333-3333-4333-8333-333333333333');
SELECT pg_temp.po(12,50,'pob-old-po01') AS p6 \gset
RESET ROLE;
SELECT jsonb_set(core10._proc_po_approval_payload_v1(:p6),'{unit}','"currency_total"') AS pay6old \gset
SELECT pg_temp.ok((:'pay6old'::jsonb - 'unit')=(core10._proc_po_approval_payload_v1(:p6) - 'unit'),'old and new payloads differ only in unit');
SET LOCAL ROLE authenticated;
SELECT core10.submit_typed_approval_v1(20011,'procurement','purchase_order','procurement:po:'||:p6,1,:'pay6old'::jsonb,'pob-old-r000') AS q6old \gset
RESET ROLE;
UPDATE core10.purchase_orders_v1 SET approval_request_id=:q6old WHERE id=:p6;
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('b1111111-1111-4111-8111-111111111111');
SELECT core10.decide_approval(:q6old,'approve','pob-old-dec0');
SELECT pg_temp.as_user('b2222222-2222-4222-8222-222222222222');
SELECT pg_temp.expect($q$SELECT pg_temp.appr($q$||:p6||$q$,1,'pob-old-a001')$q$,'approval_stale_or_payload_changed');
-- the stale request does not block the maker: a fresh BDT request is accepted, then only that one counts
SELECT pg_temp.as_user('b3333333-3333-4333-8333-333333333333');
SELECT pg_temp.req(:p6,'pob-old-r001') AS q6 \gset
SELECT pg_temp.ok(:q6<>:q6old,'fresh BDT request for the same draft version');
SELECT pg_temp.expect($q$SELECT pg_temp.req($q$||:p6||$q$,'pob-old-r002')$q$,'PROC_APPROVAL_ALREADY_REQUESTED');
SELECT pg_temp.as_user('b1111111-1111-4111-8111-111111111111');
SELECT core10.decide_approval(:q6,'approve','pob-old-dec1');
SELECT pg_temp.as_user('b2222222-2222-4222-8222-222222222222');
SELECT pg_temp.ok((pg_temp.appr(:p6,1,'pob-old-a002')->>'approval_request_id')::bigint=:q6,'PO approved on the fresh BDT request, not the stale one');
RESET ROLE;
SELECT pg_temp.ok((SELECT status FROM core10.approval_requests WHERE id=:q6old)='approved'
 AND (SELECT approval_request_id FROM core10.purchase_orders_v1 WHERE id=:p6)=:q6,'stale approval stays in history, never effective');
SELECT pg_temp.ok(NOT has_function_privilege('authenticated','core10._proc_po_approval_payload_v1(bigint)','execute'),'payload builder is internal');
SELECT pg_temp.ok(has_function_privilege('authenticated','core10.procurement_request_po_approval_v1(bigint,text)','execute')
 AND NOT has_function_privilege('anon','core10.procurement_request_po_approval_v1(bigint,text)','execute'),'request grants unchanged');
ROLLBACK;
\echo 'PASS np03a-po-approval-bdt-e2e'
