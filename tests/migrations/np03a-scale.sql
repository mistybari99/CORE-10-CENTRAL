-- B-012 P4: 10 businesses x 400 sites scale proof (disposable PG17, rolled back).
-- Builds one owner with 10 businesses of different kinds, 400 sites each (4,000 sites, 4,000 stock locations),
-- 40 items per business, 20 stocked items per site (80,000 ledger rows and balances), 2 purchase orders per site
-- (8,000), one open stock task per site (4,000). Then checks every read RPC for correctness against the books and for
-- time budgets, writes 400 real receive commands and 100 cross-site transfers through the RPCs, and re-reconciles.
-- Time budgets are generous upper bounds for a shared CI runner; the measured numbers are printed.
\set ON_ERROR_STOP on
\timing off
BEGIN;
INSERT INTO core10.templates(code,source_status,demo_allowed) SELECT x,'available',true FROM unnest(ARRAY['sweets_bakery','restaurant',
 'retail_wholesale','paint_hardware','general_manufacturing','construction','import_export','ecommerce','services','technology_digital']) x
 ON CONFLICT (code) DO NOTHING;
INSERT INTO core10.tenants(id,slug) VALUES (601,'scale-owner'),(602,'scale-other');
INSERT INTO core10.legal_entities(id,tenant_id,label) VALUES (6010,601,'Scale group'),(6020,602,'Other');
INSERT INTO core10.businesses(id,tenant_id,legal_entity_id,slug,template_code,request_key)
 SELECT 6010+b,601,6010,'scale-biz-'||b,(ARRAY['sweets_bakery','restaurant','retail_wholesale','paint_hardware','general_manufacturing',
  'construction','import_export','ecommerce','services','technology_digital'])[b],'scale-b'||b FROM generate_series(1,10) b;
INSERT INTO core10.businesses(id,tenant_id,legal_entity_id,slug,template_code,request_key) VALUES (6021,602,6020,'scale-other','sweets_bakery','scale-o1');
-- per business: site 1 factory, 2-11 godown/warehouse, 12-400 branches
INSERT INTO core10.sites(id,tenant_id,business_id,kind,label,request_key)
 SELECT (6010+b)*1000+s,601,6010+b,CASE WHEN s=1 THEN 'factory' WHEN s<=6 THEN 'godown' WHEN s<=11 THEN 'warehouse' ELSE 'showroom' END,
  'Site '||b||'-'||s,'scale-s-'||b||'-'||s FROM generate_series(1,10) b, generate_series(1,400) s;
INSERT INTO core10.sites(id,tenant_id,business_id,kind,label,request_key) VALUES (6021001,602,6021,'showroom','Other shop','scale-o-s1');
INSERT INTO core10.stock_locations(id,tenant_id,business_id,site_id,code) SELECT id*10+1,tenant_id,business_id,id,'MAIN' FROM core10.sites WHERE tenant_id IN (601,602);
INSERT INTO core10.items(id,tenant_id,business_id,sku,name_en) SELECT (6010+b)*100+i,601,6010+b,'SKU-'||i,'Item '||i FROM generate_series(1,10) b, generate_series(1,40) i;
INSERT INTO core10.master_parties_v1(id,tenant_id,business_id,code,party_kind,name_en) SELECT 6010+b,601,6010+b,'SUP-1','supplier','Supplier' FROM generate_series(1,10) b;
-- the ledger: 20 items per site, then balances from the ledger exactly as 0200 keeps them
INSERT INTO core10.stock_movements(tenant_id,business_id,site_id,location_id,item_id,delta,request_key,created_by)
 SELECT 601,s.business_id,s.id,s.id*10+1,s.business_id*100+i,(i*7+s.id%13)::numeric,'scale-open-'||s.id||'-'||i,'61111111-1111-4111-8111-111111111111'
 FROM core10.sites s, generate_series(1,20) i WHERE s.tenant_id=601;
INSERT INTO core10.stock_balances_v1(tenant_id,business_id,site_id,location_id,item_id,on_hand)
 SELECT tenant_id,business_id,site_id,location_id,item_id,sum(delta) FROM core10.stock_movements WHERE tenant_id=601 GROUP BY 1,2,3,4,5;
INSERT INTO core10.purchase_orders_v1(tenant_id,business_id,site_id,supplier_id,status,total_amount,request_key,created_by,approved_by,approved_at)
 SELECT 601,s.business_id,s.id,s.business_id,CASE WHEN k=1 THEN 'approved' ELSE 'draft' END,1000,'scale-po-'||s.id||'-'||k,
  '61111111-1111-4111-8111-111111111111',CASE WHEN k=1 THEN '61111111-1111-4111-8111-111111111111'::uuid END,CASE WHEN k=1 THEN now() END
 FROM core10.sites s, generate_series(1,2) k WHERE s.tenant_id=601;
INSERT INTO core10.purchase_order_lines_v1(po_id,tenant_id,business_id,line_no,item_id,quantity,unit_price)
 SELECT p.id,601,p.business_id,1,p.business_id*100+1,10,100 FROM core10.purchase_orders_v1 p WHERE p.tenant_id=601;
INSERT INTO core10.inventory_commands_v1(tenant_id,business_id,kind,destination_location,destination_site_id,item_id,quantity,request_key,created_by)
 SELECT 601,s.business_id,'receive',s.id*10+1,s.id,s.business_id*100+1,1,'scale-cmd-'||s.id,'61111111-1111-4111-8111-111111111111'
 FROM core10.sites s WHERE s.tenant_id=601;
INSERT INTO core10.tenant_members(tenant_id,user_id,role) VALUES
 (601,'61111111-1111-4111-8111-111111111111','tenant_owner'),(602,'62222222-2222-4222-8222-222222222222','tenant_owner');
INSERT INTO core10.site_grants(tenant_id,business_id,site_id,user_id,actions) VALUES (601,6011,6011200,'63333333-3333-4333-8333-333333333333','{stock.read,stock.post}');
ANALYZE core10.sites; ANALYZE core10.stock_balances_v1; ANALYZE core10.stock_movements; ANALYZE core10.purchase_orders_v1;
ANALYZE core10.inventory_commands_v1; ANALYZE core10.stock_locations;

CREATE FUNCTION pg_temp.as_user(p text) RETURNS void LANGUAGE sql AS $$
 SELECT set_config('request.jwt.claims',json_build_object('sub',p)::text,true), set_config('request.jwt.claim.sub',p,true) $$;
CREATE FUNCTION pg_temp.ok(p boolean, m text) RETURNS void LANGUAGE plpgsql AS $$
 BEGIN IF p IS DISTINCT FROM true THEN RAISE EXCEPTION 'SCALE_ASSERT:%',m; END IF; END $$;
-- run q, return elapsed milliseconds (best of 3 runs, to measure the steady state, not the first plan)
CREATE FUNCTION pg_temp.ms(q text) RETURNS numeric LANGUAGE plpgsql AS $$
DECLARE t0 timestamptz; best numeric := 1e9; i int; BEGIN
 FOR i IN 1..3 LOOP t0 := clock_timestamp(); EXECUTE q; best := least(best, extract(epoch FROM clock_timestamp()-t0)*1000); END LOOP;
 RETURN round(best,1); END $$;
CREATE FUNCTION pg_temp.budget(label text, q text, limit_ms numeric) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v numeric := pg_temp.ms(q); BEGIN
 RAISE NOTICE 'SCALE % : % ms (budget % ms)', label, v, limit_ms;
 IF v > limit_ms THEN RAISE EXCEPTION 'SCALE_TOO_SLOW:% % ms > % ms', label, v, limit_ms; END IF; END $$;

SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('61111111-1111-4111-8111-111111111111');
-- ---------- correctness at scale ----------
SELECT core10.owner_portfolio_v1() AS pf \gset
SELECT pg_temp.ok(jsonb_array_length(:'pf'::jsonb->'businesses')=10,'ten businesses');
SELECT pg_temp.ok((SELECT bool_and((x->>'sites')::int=400) FROM jsonb_array_elements(:'pf'::jsonb->'businesses') x),'400 sites each');
SELECT pg_temp.ok((SELECT count(DISTINCT x->>'template_code') FROM jsonb_array_elements(:'pf'::jsonb->'businesses') x)=10,'ten kinds of business');
SELECT pg_temp.ok((SELECT bool_and((x->'purchase'->>'open_pos')::int=400 AND (x->'purchase'->>'draft_pos')::int=400
  AND (x->'stock_commands'->>'draft')::int=400 AND (x->'stock'->>'stock_rows')::int=8000) FROM jsonb_array_elements(:'pf'::jsonb->'businesses') x),'per-business figures');
RESET ROLE;
SELECT sum(on_hand) AS total_units FROM core10.stock_balances_v1 WHERE tenant_id=601 \gset
SET LOCAL ROLE authenticated;
SELECT pg_temp.ok((SELECT sum((x->'stock'->>'units')::numeric) FROM jsonb_array_elements(:'pf'::jsonb->'businesses') x)=:total_units,'portfolio units equal the ledger');
-- walk all 400 sites of one business in pages of 50
DO $w$ DECLARE r jsonb; after bigint; n int := 0; pages int := 0; seen bigint[] := '{}'; BEGIN
 LOOP r := core10.owner_business_sites_v1(6011,NULL,after,50); pages := pages+1;
  n := n + jsonb_array_length(r->'items'); seen := seen || ARRAY(SELECT (x->>'site_id')::bigint FROM jsonb_array_elements(r->'items') x);
  after := (r->>'next_after_site')::bigint; EXIT WHEN after IS NULL OR pages>20; END LOOP;
 IF n<>400 OR (SELECT count(DISTINCT s) FROM unnest(seen) s)<>400 THEN RAISE EXCEPTION 'SCALE_ASSERT:paging saw % rows', n; END IF;
END $w$;
SELECT pg_temp.ok(jsonb_array_length(core10.owner_business_sites_v1(6011,'warehouse',NULL,200)->'items')=5,'kind filter at scale');
SELECT pg_temp.ok(jsonb_array_length(core10.inventory_list_balances_v1(6011,6011200,NULL,NULL,200)->'items')=20,'one site has 20 stock rows');
-- ---------- time budgets (best of three) ----------
SELECT pg_temp.budget('owner_portfolio_v1 (10 x 400)', 'SELECT core10.owner_portfolio_v1()', 1500);
SELECT pg_temp.budget('owner_business_sites_v1 page 50', 'SELECT core10.owner_business_sites_v1(6015,NULL,6015200,50)', 500);
SELECT pg_temp.budget('owner_business_sites_v1 page 200', 'SELECT core10.owner_business_sites_v1(6015,NULL,NULL,200)', 1000);
SELECT pg_temp.budget('inventory_list_balances_v1 site page', 'SELECT core10.inventory_list_balances_v1(6015,6015300,NULL,NULL,100)', 300);
SELECT pg_temp.budget('inventory_list_balances_v1 business page', 'SELECT core10.inventory_list_balances_v1(6015,NULL,NULL,NULL,200)', 500);
SELECT pg_temp.budget('inventory_list_commands_v1 page', 'SELECT core10.inventory_list_commands_v1(6015,NULL,NULL,NULL,50)', 300);
SELECT pg_temp.budget('inventory_list_commands_v1 site', 'SELECT core10.inventory_list_commands_v1(6015,6015300,NULL,NULL,50)', 300);
SELECT pg_temp.budget('procurement_list_pos_v1 page', 'SELECT core10.procurement_list_pos_v1(6015,NULL,NULL,NULL,50)', 500);
SELECT pg_temp.budget('procurement_list_pos_v1 site', 'SELECT core10.procurement_list_pos_v1(6015,6015300,NULL,NULL,50)', 300);
-- ---------- real writes through the RPCs at scale ----------
DO $x$ DECLARE c jsonb; s int; t0 timestamptz := clock_timestamp(); BEGIN
 FOR s IN 1..400 LOOP
  c := core10.create_inventory_command_v1(6012,'receive',NULL,(6012000+s)*10+1,601201,5,NULL,'scale-rx-'||s);
  c := core10.advance_inventory_command_v1((c->>'command_id')::bigint,'confirm',1,'scale-rx-c-'||s);
  c := core10.advance_inventory_command_v1((c->>'command_id')::bigint,'post',2,'scale-rx-p-'||s);
 END LOOP;
 RAISE NOTICE 'SCALE 400 receive commands (create+confirm+post) : % ms', round(extract(epoch FROM clock_timestamp()-t0)*1000);
 IF clock_timestamp()-t0 > interval '60 seconds' THEN RAISE EXCEPTION 'SCALE_TOO_SLOW:writes'; END IF;
 t0 := clock_timestamp();
 FOR s IN 1..100 LOOP
  c := core10.create_inventory_command_v1(6012,'transfer',(6012000+s)*10+1,(6012000+400-s)*10+1,601202,1,NULL,'scale-tx-'||s);
  c := core10.advance_inventory_command_v1((c->>'command_id')::bigint,'confirm',1,'scale-tx-c-'||s);
  c := core10.advance_inventory_command_v1((c->>'command_id')::bigint,'post',2,'scale-tx-p-'||s);
 END LOOP;
 RAISE NOTICE 'SCALE 100 cross-site transfers : % ms', round(extract(epoch FROM clock_timestamp()-t0)*1000);
END $x$;
-- ---------- scope at scale ----------
SELECT pg_temp.as_user('63333333-3333-4333-8333-333333333333');
SELECT pg_temp.ok(jsonb_array_length(core10.owner_portfolio_v1()->'businesses')=0,'branch staff has no portfolio');
SELECT pg_temp.ok((SELECT bool_and((x->>'site_id')::bigint=6011200) FROM jsonb_array_elements(core10.inventory_list_balances_v1(6011,NULL,NULL,NULL,200)->'items') x),'branch staff sees one site of 4,000');
SELECT pg_temp.budget('inventory_list_balances_v1 as branch staff', 'SELECT core10.inventory_list_balances_v1(6011,NULL,NULL,NULL,100)', 1500);
SELECT pg_temp.as_user('62222222-2222-4222-8222-222222222222');
SELECT pg_temp.ok(jsonb_array_length(core10.owner_portfolio_v1()->'businesses')=1,'other tenant sees only its own business');
RESET ROLE;
SELECT pg_temp.ok(NOT EXISTS(SELECT 1 FROM core10.inventory_reconciliation_v1 WHERE tenant_id=601 AND NOT reconciled),'82,000+ balances reconciled with the ledger');
SELECT pg_temp.ok((SELECT sum(on_hand) FROM core10.stock_balances_v1 WHERE business_id=6012 AND item_id=601201)
 =(SELECT sum(delta) FROM core10.stock_movements WHERE business_id=6012 AND item_id=601201),'written stock equals ledger');
ROLLBACK;
\echo 'PASS np03a-scale (10 businesses x 400 sites)'
