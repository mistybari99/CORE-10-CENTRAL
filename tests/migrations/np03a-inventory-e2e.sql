-- B-012 / 0200: canonical inventory engine proof (disposable PG17, rolled back).
-- The engine is internal: the test calls it as the database owner WITH a signed actor in the JWT claims,
-- exactly as the future Owner-Control-checked command RPCs (0201+) will. API roles must not reach it.
\set ON_ERROR_STOP on
BEGIN;
INSERT INTO core10.templates(code,source_status,demo_allowed) VALUES ('sweets_bakery','available',true) ON CONFLICT (code) DO NOTHING;
INSERT INTO core10.tenants(id,slug) VALUES (991,'inv-a'),(992,'inv-b');
INSERT INTO core10.legal_entities(id,tenant_id,label) VALUES (9910,991,'Inv A'),(9920,992,'Inv B');
INSERT INTO core10.businesses(id,tenant_id,legal_entity_id,slug,template_code,request_key)
 VALUES (9911,991,9910,'inv-a','sweets_bakery','inv-ba'),(9912,991,9910,'inv-a2','sweets_bakery','inv-ba2'),(9921,992,9920,'inv-b','sweets_bakery','inv-bb');
INSERT INTO core10.sites(id,tenant_id,business_id,kind,label,request_key) VALUES
 (99111,991,9911,'factory','Factory','inv-s1'),(99112,991,9911,'showroom','Shop','inv-s2'),(99121,991,9912,'showroom','Other biz','inv-s3'),(99211,992,9921,'showroom','B shop','inv-s4');
INSERT INTO core10.stock_locations(id,tenant_id,business_id,site_id,code) VALUES
 (991111,991,9911,99111,'F-MAIN'),(991121,991,9911,99112,'S-MAIN'),(991211,991,9912,99121,'O-MAIN'),(992111,992,9921,99211,'B-MAIN');
INSERT INTO core10.items(id,tenant_id,business_id,sku) VALUES (99101,991,9911,'SUGAR'),(99102,991,9912,'OTHER'),(99201,992,9921,'B-ITEM');
INSERT INTO core10.tenant_members(tenant_id,user_id,role) VALUES (991,'d1111111-1111-4111-8111-111111111111','tenant_owner'),(992,'d5555555-5555-4555-8555-555555555555','tenant_owner');

CREATE FUNCTION pg_temp.as_user(p text) RETURNS void LANGUAGE sql AS $$
 SELECT set_config('request.jwt.claims',json_build_object('sub',p)::text,true), set_config('request.jwt.claim.sub',p,true) $$;
CREATE FUNCTION pg_temp.ok(p boolean, m text) RETURNS void LANGUAGE plpgsql AS $$ BEGIN IF p IS DISTINCT FROM true THEN RAISE EXCEPTION 'INV_ASSERT:%',m; END IF; END $$;
CREATE FUNCTION pg_temp.expect(q text, pre text) RETURNS void LANGUAGE plpgsql AS $$
 BEGIN BEGIN EXECUTE q; EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE pre||'%' THEN RETURN; END IF;
  RAISE EXCEPTION 'INV_WRONG_ERROR expected=% got=% q=%',pre,SQLERRM,left(q,100); END;
  RAISE EXCEPTION 'INV_EXPECTED_DENIAL:% q=%',pre,left(q,100); END $$;

-- API roles cannot reach the engine or the tables directly.
SET LOCAL ROLE authenticated;
SELECT pg_temp.expect('SELECT core10.post_stock_event(991111,99101,5,''api-direct-0001'')','permission denied');
SELECT pg_temp.expect('SELECT core10.transfer_stock_v1(991111,991121,99101,1,''api-direct-0002'')','permission denied');
SELECT pg_temp.expect('SELECT count(*) FROM core10.stock_balances_v1','permission denied');
SELECT pg_temp.expect('SELECT count(*) FROM core10.inventory_reconciliation_v1','permission denied');
RESET ROLE;

SELECT pg_temp.as_user('d1111111-1111-4111-8111-111111111111');
-- receive, idempotent replay, issue
SELECT core10.post_stock_event(991111,99101,100,'inv-recv-0001') AS m1 \gset
SELECT pg_temp.ok(core10.post_stock_event(991111,99101,100,'inv-recv-0001')=:m1,'replay returns the same movement');
SELECT pg_temp.expect('SELECT core10.post_stock_event(991111,99101,7,''inv-recv-0001'')','idempotency_key_payload_conflict');
SELECT core10.post_stock_event(991111,99101,-30,'inv-issue-0001') \gset
SELECT pg_temp.ok((SELECT on_hand FROM core10.stock_balances_v1 WHERE location_id=991111 AND item_id=99101)=70,'balance 70');
SELECT pg_temp.expect('SELECT core10.post_stock_event(991111,99101,-71,''inv-issue-0002'')','insufficient_stock');
SELECT pg_temp.expect('SELECT core10.post_stock_event(991111,99101,''NaN'',''inv-nan-0001'')','invalid_stock_event');
SELECT pg_temp.expect('SELECT core10.post_stock_event(991111,99102,1,''inv-mismatch-01'')','stock_item_business_mismatch');
-- transfer pairs two movements atomically; cross-business refused
SELECT core10.transfer_stock_v1(991111,991121,99101,20,'inv-xfer-0001') AS x1 \gset
SELECT pg_temp.ok((SELECT count(*) FROM core10.stock_movements WHERE transfer_id=:x1)=2 AND (SELECT sum(delta) FROM core10.stock_movements WHERE transfer_id=:x1)=0,'paired movements net zero');
SELECT pg_temp.ok((SELECT on_hand FROM core10.stock_balances_v1 WHERE location_id=991121 AND item_id=99101)=20,'destination 20');
SELECT pg_temp.expect('SELECT core10.transfer_stock_v1(991111,991211,99101,1,''inv-xbiz-0001'')','cross_business_transfer_forbidden');
SELECT pg_temp.expect('SELECT core10.transfer_stock_v1(991111,991121,99101,999,''inv-xfer-0002'')','insufficient_stock');
-- a transfer movement key cannot be posted directly
SELECT pg_temp.expect('SELECT core10.post_stock_event(991111,99101,1,''c10-transfer:1:out'')','invalid_stock_event');
-- other tenant owner and unsigned caller are refused
SELECT pg_temp.as_user('d5555555-5555-4555-8555-555555555555');
SELECT pg_temp.expect('SELECT core10.post_stock_event(991111,99101,1,''inv-foreign-001'')','stock_post_not_authorized');
SELECT pg_temp.expect('SELECT core10.transfer_stock_v1(991111,991121,99101,1,''inv-foreign-002'')','transfer_not_authorized');
SELECT pg_temp.as_user('');
SELECT pg_temp.expect('SELECT core10.post_stock_event(991111,99101,1,''inv-unsigned-01'')','invalid_stock_event');
-- Central reads the existing view using the caller's RLS permissions.
INSERT INTO core10.site_grants(tenant_id,business_id,site_id,user_id,actions)
 VALUES(991,9911,99111,'d3333333-3333-4333-8333-333333333333',ARRAY['stock.read']);
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('d3333333-3333-4333-8333-333333333333');
SELECT pg_temp.ok((SELECT count(*)=1 AND min(net_movement)=50 FROM core10.stock_summary
 WHERE business_id=9911),'Stock reader sees only its authorized site');
SELECT pg_temp.ok(NOT EXISTS(SELECT 1 FROM core10.stock_summary WHERE site_id=99112),
 'Stock reader cannot read a different site');
SELECT pg_temp.as_user('d5555555-5555-4555-8555-555555555555');
SELECT pg_temp.ok(NOT EXISTS(SELECT 1 FROM core10.stock_summary WHERE tenant_id=991),
 'Stock reader cannot read another tenant');
RESET ROLE;
-- every balance reconciles with the one movement ledger
SELECT pg_temp.ok(NOT EXISTS(SELECT 1 FROM core10.inventory_reconciliation_v1 WHERE NOT reconciled),'all balances reconciled');
SELECT pg_temp.ok((SELECT count(*) FROM core10.inventory_reconciliation_v1 WHERE business_id=9911)=2,'two balance rows');
DO $$ BEGIN RAISE NOTICE 'NP03A inventory engine e2e PASS'; END $$;
ROLLBACK;
