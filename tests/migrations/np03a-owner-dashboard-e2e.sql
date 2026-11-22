-- B-012 / 0204: Owner multi-business dashboard reads (disposable PG17, rolled back).
-- One owner with two businesses of different kinds; a manager of one; site staff; a business owner with a site deny;
-- another tenant. Checks the figures against the canonical books and the scope of every persona.
\set ON_ERROR_STOP on
BEGIN;
INSERT INTO core10.templates(code,source_status,demo_allowed) VALUES ('sweets_bakery','available',true),('paint_hardware','available',true)
 ON CONFLICT (code) DO NOTHING;
INSERT INTO core10.tenants(id,slug) VALUES (921,'dash-a'),(922,'dash-b');
INSERT INTO core10.legal_entities(id,tenant_id,label) VALUES (9210,921,'Dash A'),(9220,922,'Dash B');
INSERT INTO core10.businesses(id,tenant_id,legal_entity_id,slug,template_code,request_key) VALUES
 (9211,921,9210,'dash-sweets','sweets_bakery','dash-b1'),(9212,921,9210,'dash-paint','paint_hardware','dash-b2'),
 (9221,922,9220,'dash-other','sweets_bakery','dash-b3');
INSERT INTO core10.sites(id,tenant_id,business_id,kind,label,request_key) VALUES
 (92111,921,9211,'factory','Factory','dash-s1'),(92112,921,9211,'showroom','Branch 1','dash-s2'),(92113,921,9211,'showroom','Branch 2','dash-s3'),
 (92114,921,9211,'godown','Godown','dash-s4'),(92121,921,9212,'warehouse','Paint WH','dash-s5'),(92211,922,9221,'showroom','B shop','dash-s6');
INSERT INTO core10.stock_locations(id,tenant_id,business_id,site_id,code) VALUES
 (921111,921,9211,92111,'F'),(921121,921,9211,92112,'S1'),(921131,921,9211,92113,'S2'),(921141,921,9211,92114,'G'),
 (921211,921,9212,92121,'W'),(922111,922,9221,92211,'B');
INSERT INTO core10.items(id,tenant_id,business_id,sku,name_en) VALUES
 (92101,921,9211,'SUGAR','Sugar'),(92102,921,9211,'GHEE','Ghee'),(92103,921,9212,'PAINT','Paint'),(92201,922,9221,'B','B');
INSERT INTO core10.master_parties_v1(id,tenant_id,business_id,code,party_kind,name_en) VALUES (92151,921,9211,'SUP','supplier','Supplier');
INSERT INTO core10.tenant_members(tenant_id,user_id,role) VALUES
 (921,'d9111111-1111-4111-8111-111111111111','tenant_owner'),(922,'d9555555-5555-4555-8555-555555555555','tenant_owner');
INSERT INTO core10.business_members(tenant_id,business_id,user_id,role) VALUES
 (921,9212,'d9333333-3333-4333-8333-333333333333','manager'),(921,9211,'d9666666-6666-4666-8666-666666666666','business_owner');
INSERT INTO core10.site_grants(tenant_id,business_id,site_id,user_id,actions,denied_actions) VALUES
 (921,9211,92112,'d9444444-4444-4444-8444-444444444444','{stock.read,stock.post}','{}'),
 (921,9211,92113,'d9666666-6666-4666-8666-666666666666','{}','{stock.read}');

CREATE FUNCTION pg_temp.as_user(p text) RETURNS void LANGUAGE sql AS $$
 SELECT set_config('request.jwt.claims',json_build_object('sub',p)::text,true), set_config('request.jwt.claim.sub',p,true) $$;
CREATE FUNCTION pg_temp.ok(p boolean, m text) RETURNS void LANGUAGE plpgsql AS $$
 BEGIN IF p IS DISTINCT FROM true THEN RAISE EXCEPTION 'DASHT_ASSERT:%',m; END IF; END $$;
CREATE FUNCTION pg_temp.expect(q text, pre text) RETURNS void LANGUAGE plpgsql AS $$
 BEGIN BEGIN EXECUTE q; EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE pre||'%' THEN RETURN; END IF;
  RAISE EXCEPTION 'DASHT_WRONG_ERROR expected=% got=% q=%',pre,SQLERRM,left(q,160); END;
  RAISE EXCEPTION 'DASHT_EXPECTED_DENIAL:% q=%',pre,left(q,160); END $$;
CREATE FUNCTION pg_temp.recv(b bigint,l bigint,i bigint,q numeric,k text) RETURNS jsonb LANGUAGE sql AS $$
 SELECT core10.advance_inventory_command_v1((c->>'command_id')::bigint,'post',2,k||'-p') FROM (
  SELECT core10.advance_inventory_command_v1((core10.create_inventory_command_v1(b,'receive',NULL,l,i,q,NULL,k)->>'command_id')::bigint,'confirm',1,k||'-c') c) x $$;
CREATE FUNCTION pg_temp.biz(p jsonb, b bigint) RETURNS jsonb LANGUAGE sql AS $$
 SELECT x FROM jsonb_array_elements(p->'businesses') x WHERE (x->>'business_id')::bigint=b $$;

SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('d9111111-1111-4111-8111-111111111111');
SELECT pg_temp.recv(9211,921111,92101,100,'dash-r-0001'), pg_temp.recv(9211,921121,92101,20,'dash-r-0002'),
       pg_temp.recv(9211,921131,92102,5,'dash-r-0003'), pg_temp.recv(9212,921211,92103,40,'dash-r-0004');
SELECT core10.create_inventory_command_v1(9211,'transfer',921111,921141,92101,10,NULL,'dash-cmd-001');
SELECT core10.control_set_v1(9211,NULL,'procurement.purchase_order',true,0::smallint,'{"separate_approver":false}',NULL,false,0,'dash test','dash-ctl-0001');
SELECT core10.procurement_advance_po_v1((core10.procurement_save_po_v1(9211,NULL,92114,92151,'[{"item_id":92102,"quantity":10,"unit_price":300}]',NULL,NULL,0,'dash-po-0001')->>'po_id')::bigint,'approve',1,'dash-apv-001') AS po \gset
SELECT core10.procurement_receive_v1((:'po'::jsonb->>'po_id')::bigint,921141,'[{"line_no":1,"quantity":4}]',NULL,'dash-grn-0001');
SELECT core10.publish_approval_policy_v1(9211,'inventory','adjust',120,'dash-pol-0001');
SELECT pg_temp.as_user('d9666666-6666-4666-8666-666666666666');
SELECT core10.submit_typed_approval_v1(9211,'inventory','adjust','dash-src-1',1,'{"amount":1,"unit":"base_qty"}','dash-sub-0001');

-- ---------- owner: two businesses with correct figures ----------
SELECT pg_temp.as_user('d9111111-1111-4111-8111-111111111111');
SELECT core10.owner_portfolio_v1() AS pf \gset
SELECT pg_temp.ok(jsonb_array_length(:'pf'::jsonb->'businesses')=2,'owner sees exactly two businesses');
SELECT pg_temp.ok((pg_temp.biz(:'pf',9211)->>'sites')::int=4 AND (pg_temp.biz(:'pf',9211)->'sites_by_kind'->>'showroom')::int=2,'site counts by kind');
SELECT pg_temp.ok((pg_temp.biz(:'pf',9211)->'stock'->>'units')::numeric=125 AND (pg_temp.biz(:'pf',9211)->'stock'->>'items')::int=2,'stock units and items');
SELECT pg_temp.ok((pg_temp.biz(:'pf',9211)->'purchase'->>'open_pos')::int=1 AND (pg_temp.biz(:'pf',9211)->'purchase'->>'open_amount')::numeric=3000
 AND (pg_temp.biz(:'pf',9211)->'purchase'->>'awaiting_qc')::int=1,'purchase figures');
SELECT pg_temp.ok((pg_temp.biz(:'pf',9211)->'stock_commands'->>'draft')::int=1,'open stock command');
SELECT pg_temp.ok((pg_temp.biz(:'pf',9211)->>'approvals_pending')::int=1,'pending approval for the owner');
SELECT pg_temp.ok((pg_temp.biz(:'pf',9212)->'stock'->>'units')::numeric=40 AND pg_temp.biz(:'pf',9212)->>'template_code'='paint_hardware','second business of another kind');
SELECT pg_temp.ok(pg_temp.biz(:'pf',9211)->'not_connected' @> '["sales","cash"]','sales and cash honestly not connected');
SELECT core10.owner_business_sites_v1(9211) AS st \gset
SELECT pg_temp.ok(jsonb_array_length(:'st'::jsonb->'items')=4,'four site rows');
SELECT pg_temp.ok((SELECT (x->>'units')::numeric FROM jsonb_array_elements(:'st'::jsonb->'items') x WHERE (x->>'site_id')::bigint=92111)=100,'factory units');
SELECT pg_temp.ok((SELECT (x->>'commands_open')::int FROM jsonb_array_elements(:'st'::jsonb->'items') x WHERE (x->>'site_id')::bigint=92114)=1
 AND (SELECT (x->>'receipts_waiting')::int FROM jsonb_array_elements(:'st'::jsonb->'items') x WHERE (x->>'site_id')::bigint=92114)=1,'godown has a command and a receipt waiting');
SELECT pg_temp.ok(jsonb_array_length(core10.owner_business_sites_v1(9211,'showroom')->'items')=2,'kind filter');
SELECT pg_temp.ok(jsonb_array_length(core10.owner_business_sites_v1(9211,NULL,NULL,3)->'items')=3
 AND (core10.owner_business_sites_v1(9211,NULL,NULL,3)->>'next_after_site')::bigint=92113,'site page cursor');
SELECT pg_temp.ok(jsonb_array_length(core10.owner_business_sites_v1(9211,NULL,92113,3)->'items')=1,'next page');
SELECT pg_temp.expect($q$SELECT core10.owner_business_sites_v1(9211,'shop')$q$,'DASH_INVALID_FILTER');

-- ---------- other personas ----------
SELECT pg_temp.as_user('d9333333-3333-4333-8333-333333333333');
SELECT pg_temp.ok(jsonb_array_length(core10.owner_portfolio_v1()->'businesses')=1 AND pg_temp.biz(core10.owner_portfolio_v1(),9212) IS NOT NULL,'manager sees only the paint business');
SELECT pg_temp.ok(pg_temp.biz(core10.owner_portfolio_v1(),9212)->'approvals_pending'='null'::jsonb,'manager does not see approval counts');
SELECT pg_temp.expect($q$SELECT core10.owner_business_sites_v1(9211)$q$,'DASH_SCOPE');
SELECT pg_temp.as_user('d9666666-6666-4666-8666-666666666666');
SELECT pg_temp.ok(NOT EXISTS(SELECT 1 FROM jsonb_array_elements(core10.owner_business_sites_v1(9211)->'items') x WHERE (x->>'site_id')::bigint=92113),'site read deny hides the branch');
SELECT pg_temp.as_user('d9444444-4444-4444-8444-444444444444');
SELECT pg_temp.ok(jsonb_array_length(core10.owner_portfolio_v1()->'businesses')=0,'site staff gets no portfolio');
SELECT pg_temp.expect($q$SELECT core10.owner_business_sites_v1(9211)$q$,'DASH_SCOPE');
SELECT pg_temp.as_user('d9555555-5555-4555-8555-555555555555');
SELECT pg_temp.ok(jsonb_array_length(core10.owner_portfolio_v1()->'businesses')=1 AND pg_temp.biz(core10.owner_portfolio_v1(),9221) IS NOT NULL,'other tenant sees only its own business');
SELECT pg_temp.expect($q$SELECT core10.owner_business_sites_v1(9211)$q$,'DASH_SCOPE');
SELECT pg_temp.as_user('');
SELECT pg_temp.expect($q$SELECT core10.owner_portfolio_v1()$q$,'DASH_UNAUTHENTICATED');
RESET ROLE;
SELECT pg_temp.ok(NOT has_function_privilege('anon','core10.owner_portfolio_v1()','execute'),'anon cannot read the portfolio');
SELECT pg_temp.ok((SELECT provolatile FROM pg_proc WHERE oid='core10.owner_portfolio_v1()'::regprocedure)='s','portfolio is read-only (STABLE)');
ROLLBACK;
\echo 'PASS np03a-owner-dashboard-e2e'
