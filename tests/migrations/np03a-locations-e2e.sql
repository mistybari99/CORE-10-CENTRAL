-- B-012 / 0208: scoped stock-location list inventory_list_locations_v1 (disposable PG17, rolled back).
-- Personas (tenant 1801): tenant owner, business owner with an explicit read deny at the branch, manager with a post-only
-- deny at the godown, godown staff (stock.read+post), branch staff (stock.read only), expired-grant staff, revoked
-- manager; tenant 1802 owner (foreign); a signed account with no membership; no session.
-- Proves: each persona gets exactly the rows the authoritative row policy location_scope_read (can_site 'stock.read')
-- lets it read, can_post equals can_site(.., 'stock.post') (the rule behind inventory_action_authorized_v1) per location, site filter, INV_SCOPE
-- on foreign / denied / unknown business and site, ordering, the 2000-row cap, catalog security (STABLE, SECURITY
-- DEFINER, search_path pg_catalog first, no PUBLIC/anon, authenticated only, not registered as state-changing).
\set ON_ERROR_STOP on
BEGIN;
INSERT INTO core10.templates(code,source_status,demo_allowed) VALUES ('sweets_bakery','available',true) ON CONFLICT (code) DO NOTHING;
INSERT INTO core10.tenants(id,slug) VALUES (1801,'loc-a'),(1802,'loc-b');
INSERT INTO core10.legal_entities(id,tenant_id,label) VALUES (18010,1801,'Loc A'),(18020,1802,'Loc B');
INSERT INTO core10.businesses(id,tenant_id,legal_entity_id,slug,template_code,request_key) VALUES
 (18011,1801,18010,'loc-a1','sweets_bakery','loc-biz-a1'),(18012,1801,18010,'loc-a2','sweets_bakery','loc-biz-a2'),
 (18021,1802,18020,'loc-b1','sweets_bakery','loc-biz-b1');
INSERT INTO core10.sites(id,tenant_id,business_id,kind,label,request_key) VALUES
 (180111,1801,18011,'godown','Godown','loc-site-1'),(180112,1801,18011,'showroom','Branch','loc-site-2'),
 (180113,1801,18011,'factory','Factory (no store yet)','loc-site-3'),(180121,1801,18012,'warehouse','A2 warehouse','loc-site-4'),
 (180211,1802,18021,'godown','B godown','loc-site-5');
-- ids deliberately not in site order, to prove ordering by site then id
INSERT INTO core10.stock_locations(id,tenant_id,business_id,site_id,code) VALUES
 (1801119,1801,18011,180111,'G-COLD'),(1801111,1801,18011,180111,'G-MAIN'),(1801110,1801,18011,180112,'SHOP'),
 (1801211,1801,18012,180121,'W-1'),(1802111,1802,18021,180211,'BG');
INSERT INTO core10.tenant_members(tenant_id,user_id,role) VALUES
 (1801,'18000000-0000-4000-8000-000000000001','tenant_owner'),(1802,'18000000-0000-4000-8000-000000000006','tenant_owner');
INSERT INTO core10.business_members(tenant_id,business_id,user_id,role,active) VALUES
 (1801,18011,'18000000-0000-4000-8000-000000000002','business_owner',true),
 (1801,18011,'18000000-0000-4000-8000-000000000003','manager',true),
 (1801,18011,'18000000-0000-4000-8000-000000000009','manager',false);
INSERT INTO core10.site_grants(tenant_id,business_id,site_id,user_id,actions,denied_actions,valid_until) VALUES
 (1801,18011,180112,'18000000-0000-4000-8000-000000000002','{}','{stock.read}',NULL),
 (1801,18011,180111,'18000000-0000-4000-8000-000000000003','{}','{stock.post}',NULL),
 (1801,18011,180111,'18000000-0000-4000-8000-000000000004','{stock.read,stock.post}','{}',NULL),
 (1801,18011,180112,'18000000-0000-4000-8000-000000000005','{stock.read}','{}',NULL),
 (1801,18011,180111,'18000000-0000-4000-8000-000000000008','{stock.read,stock.post}','{}',now()-interval '1 day');

CREATE FUNCTION pg_temp.as_user(p text) RETURNS void LANGUAGE sql AS $$
 SELECT set_config('request.jwt.claims',CASE WHEN p IS NULL THEN '{}' ELSE json_build_object('sub',p)::text END,true),
        set_config('request.jwt.claim.sub',coalesce(p,''),true) $$;
CREATE FUNCTION pg_temp.u(n int) RETURNS text LANGUAGE sql AS $$ SELECT '18000000-0000-4000-8000-00000000000'||n $$;
CREATE FUNCTION pg_temp.ok(p boolean, m text) RETURNS void LANGUAGE plpgsql AS $$
 BEGIN IF p IS DISTINCT FROM true THEN RAISE EXCEPTION 'LOCT_ASSERT:%',m; END IF; END $$;
CREATE FUNCTION pg_temp.expect(q text, pre text) RETURNS void LANGUAGE plpgsql AS $$
 BEGIN BEGIN EXECUTE q; EXCEPTION WHEN OTHERS THEN IF SQLERRM LIKE pre||'%' THEN RETURN; END IF;
  RAISE EXCEPTION 'LOCT_WRONG_ERROR expected=% got=% q=%',pre,SQLERRM,left(q,160); END;
  RAISE EXCEPTION 'LOCT_EXPECTED_DENIAL:% q=%',pre,left(q,160); END $$;
-- location ids returned by the RPC, in returned order
CREATE FUNCTION pg_temp.ids(b bigint, s bigint DEFAULT NULL) RETURNS bigint[] LANGUAGE sql AS $$
 SELECT coalesce(array_agg((x->>'location_id')::bigint ORDER BY o),'{}') FROM jsonb_array_elements(core10.inventory_list_locations_v1(b,s)->'items') WITH ORDINALITY a(x,o) $$;
-- location ids the authoritative row policy (0002 location_scope_read = can_site stock.read) lets the caller read
CREATE FUNCTION pg_temp.rls(b bigint) RETURNS bigint[] LANGUAGE sql AS $$
 SELECT coalesce(array_agg(id ORDER BY site_id,id),'{}') FROM core10.stock_locations WHERE business_id=b $$;
-- every returned row: can_post equals the canonical can_site stock.post decision (what inventory_action_authorized_v1 uses); labels match the site
CREATE FUNCTION pg_temp.consistent(b bigint) RETURNS boolean LANGUAGE sql AS $$
 SELECT coalesce(bool_and((x->>'can_post')::boolean = core10.can_site(l.tenant_id,l.business_id,l.site_id,'stock.post')
   AND (x->>'site_id')::bigint=l.site_id AND x->>'code'=l.code AND x->>'site_kind'=s.kind AND x->>'site_label'=s.label),true)
 FROM jsonb_array_elements(core10.inventory_list_locations_v1(b)->'items') x
 JOIN core10.stock_locations l ON l.id=(x->>'location_id')::bigint JOIN core10.sites s ON s.id=l.site_id $$;
CREATE FUNCTION pg_temp.post(b bigint) RETURNS jsonb LANGUAGE sql AS $$
 SELECT coalesce(jsonb_object_agg(x->>'location_id',(x->>'can_post')::boolean),'{}') FROM jsonb_array_elements(core10.inventory_list_locations_v1(b)->'items') x $$;

-- ---------- catalog security ----------
SELECT pg_temp.ok(p.provolatile='s' AND p.prosecdef AND p.proconfig @> ARRAY['search_path=pg_catalog, core10']
 AND NOT has_function_privilege('anon',p.oid,'execute') AND NOT has_function_privilege('public',p.oid,'execute')
 AND has_function_privilege('authenticated',p.oid,'execute'),'STABLE SECURITY DEFINER, search_path pg_catalog first, authenticated only')
 FROM pg_proc p WHERE p.oid='core10.inventory_list_locations_v1(bigint,bigint)'::regprocedure;
SELECT pg_temp.ok(NOT EXISTS(SELECT 1 FROM core10.control_rpc_map_v1 WHERE rpc_name='inventory_list_locations_v1'),'a read is not registered as a state-changing RPC');

SET LOCAL ROLE authenticated;
-- ---------- tenant owner: everything of the business, can post everywhere ----------
SELECT pg_temp.as_user(pg_temp.u(1));
SELECT pg_temp.ok(pg_temp.ids(18011)=ARRAY[1801111,1801119,1801110]::bigint[],'owner: ordered by site then id; the factory without a store adds nothing');
SELECT pg_temp.ok(pg_temp.ids(18011)=pg_temp.rls(18011),'owner: same rows as the row policy');
SELECT pg_temp.ok(pg_temp.consistent(18011),'owner: can_post and labels consistent');
SELECT pg_temp.ok(pg_temp.post(18011)='{"1801111":true,"1801119":true,"1801110":true}','owner may post at every location');
SELECT pg_temp.ok(pg_temp.ids(18011,180112)=ARRAY[1801110]::bigint[],'owner: site filter');
SELECT pg_temp.ok(pg_temp.ids(18011,180113)='{}','owner: a readable site with no store returns an empty list, not an error');
SELECT pg_temp.ok(pg_temp.ids(18012)=ARRAY[1801211]::bigint[],'owner: second business of the same tenant');
SELECT pg_temp.ok((SELECT x->>'site_kind'='godown' AND x->>'site_label'='Godown' AND x->>'code'='G-MAIN' AND (x->>'site_id')::bigint=180111
 FROM jsonb_array_elements(core10.inventory_list_locations_v1(18011)->'items') x LIMIT 1),'row shape: site kind, label, code');
SELECT pg_temp.ok((core10.inventory_list_locations_v1(18011)->>'truncated')::boolean=false
 AND (core10.inventory_list_locations_v1(18011,180111)->>'site_id')::bigint=180111,'envelope');
SELECT pg_temp.expect('SELECT core10.inventory_list_locations_v1(18011,180121)','INV_SCOPE'); -- a site of another business
SELECT pg_temp.expect('SELECT core10.inventory_list_locations_v1(18011,999999)','INV_SCOPE');
SELECT pg_temp.expect('SELECT core10.inventory_list_locations_v1(18021)','INV_SCOPE');      -- other tenant
SELECT pg_temp.expect('SELECT core10.inventory_list_locations_v1(999999)','INV_SCOPE');    -- unknown business
SELECT pg_temp.expect('SELECT core10.inventory_list_locations_v1(NULL)','INV_SCOPE');

-- ---------- business owner with an explicit read deny at the branch: deny beats ownership ----------
SELECT pg_temp.as_user(pg_temp.u(2));
SELECT pg_temp.ok(pg_temp.ids(18011)=ARRAY[1801111,1801119]::bigint[],'denied owner: branch location hidden');
SELECT pg_temp.ok(pg_temp.ids(18011)=pg_temp.rls(18011),'denied owner: same rows as the row policy');
SELECT pg_temp.ok(pg_temp.consistent(18011),'denied owner: consistent');
SELECT pg_temp.expect('SELECT core10.inventory_list_locations_v1(18011,180112)','INV_SCOPE');
SELECT pg_temp.expect('SELECT core10.inventory_list_locations_v1(18012)','INV_SCOPE');      -- not a member of business 2

-- ---------- manager with a post-only deny at the godown: reads everything, cannot post at the godown ----------
SELECT pg_temp.as_user(pg_temp.u(3));
SELECT pg_temp.ok(pg_temp.ids(18011)=pg_temp.rls(18011) AND cardinality(pg_temp.ids(18011))=3,'manager: all three');
SELECT pg_temp.ok(pg_temp.post(18011)='{"1801111":false,"1801119":false,"1801110":true}','manager: post denied at the godown only');
SELECT pg_temp.ok(pg_temp.consistent(18011),'manager: consistent');

-- ---------- site staff ----------
SELECT pg_temp.as_user(pg_temp.u(4));
SELECT pg_temp.ok(pg_temp.ids(18011)=ARRAY[1801111,1801119]::bigint[] AND pg_temp.ids(18011)=pg_temp.rls(18011),'godown staff: godown only');
SELECT pg_temp.ok(pg_temp.post(18011)='{"1801111":true,"1801119":true}','godown staff may post at the godown');
SELECT pg_temp.ok(pg_temp.ids(18011,180111)=ARRAY[1801111,1801119]::bigint[],'godown staff: own site filter');
SELECT pg_temp.expect('SELECT core10.inventory_list_locations_v1(18011,180112)','INV_SCOPE');
SELECT pg_temp.expect('SELECT core10.inventory_list_locations_v1(18011,180113)','INV_SCOPE');
SELECT pg_temp.expect('SELECT core10.inventory_list_locations_v1(18012)','INV_SCOPE');
SELECT pg_temp.as_user(pg_temp.u(5));
SELECT pg_temp.ok(pg_temp.ids(18011)=ARRAY[1801110]::bigint[] AND pg_temp.ids(18011)=pg_temp.rls(18011),'branch staff: branch only');
SELECT pg_temp.ok(pg_temp.post(18011)='{"1801110":false}','read-only branch staff cannot post');
SELECT pg_temp.ok(pg_temp.consistent(18011),'branch staff: consistent');
SELECT pg_temp.expect('SELECT core10.inventory_list_locations_v1(18011,180111)','INV_SCOPE');

-- ---------- expired grant, revoked manager, no membership, no session, other tenant ----------
SELECT pg_temp.as_user(pg_temp.u(8));
SELECT pg_temp.expect('SELECT core10.inventory_list_locations_v1(18011)','INV_SCOPE');
SELECT pg_temp.as_user(pg_temp.u(9));
SELECT pg_temp.expect('SELECT core10.inventory_list_locations_v1(18011)','INV_SCOPE');
SELECT pg_temp.as_user('18000000-0000-4000-8000-00000000000a');
SELECT pg_temp.expect('SELECT core10.inventory_list_locations_v1(18011)','INV_SCOPE');
SELECT pg_temp.as_user(NULL);
SELECT pg_temp.expect('SELECT core10.inventory_list_locations_v1(18011)','INV_SCOPE');
SELECT pg_temp.as_user(pg_temp.u(6));
SELECT pg_temp.ok(pg_temp.ids(18021)=ARRAY[1802111]::bigint[] AND pg_temp.post(18021)='{"1802111":true}','other tenant owner: own location only');
SELECT pg_temp.expect('SELECT core10.inventory_list_locations_v1(18011)','INV_SCOPE');
SELECT pg_temp.expect('SELECT core10.inventory_list_locations_v1(18012)','INV_SCOPE');
SELECT pg_temp.expect('SELECT core10.inventory_list_locations_v1(18021,180111)','INV_SCOPE');

-- ---------- a grant change takes effect on the next call (no caching) ----------
RESET ROLE;
UPDATE core10.site_grants SET denied_actions='{stock.read}' WHERE site_id=180111 AND user_id=pg_temp.u(4)::uuid;
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user(pg_temp.u(4));
SELECT pg_temp.expect('SELECT core10.inventory_list_locations_v1(18011)','INV_SCOPE');
RESET ROLE;
UPDATE core10.site_grants SET denied_actions='{}' WHERE site_id=180111 AND user_id=pg_temp.u(4)::uuid;

-- ---------- 2000-row cap ----------
INSERT INTO core10.stock_locations(id,tenant_id,business_id,site_id,code)
 SELECT 1810000+i,1801,18012,180121,'BIN-'||lpad(i::text,4,'0') FROM generate_series(1,2000) i;
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user(pg_temp.u(1));
SELECT pg_temp.ok((core10.inventory_list_locations_v1(18012)->>'truncated')::boolean
 AND jsonb_array_length(core10.inventory_list_locations_v1(18012)->'items')=2000
 AND (core10.inventory_list_locations_v1(18012)->'items'->0->>'location_id')::bigint=1801211,'2001 locations: first 2000 returned, truncated');
RESET ROLE;
DELETE FROM core10.stock_locations WHERE business_id=18012 AND code LIKE 'BIN-%' AND id IN (SELECT max(id) FROM core10.stock_locations WHERE business_id=18012);
SET LOCAL ROLE authenticated;
SELECT pg_temp.ok(NOT (core10.inventory_list_locations_v1(18012)->>'truncated')::boolean
 AND jsonb_array_length(core10.inventory_list_locations_v1(18012)->'items')=2000,'exactly 2000 locations: not truncated');
RESET ROLE;

\echo NP03A_LOCATIONS_E2E_OK
ROLLBACK;
