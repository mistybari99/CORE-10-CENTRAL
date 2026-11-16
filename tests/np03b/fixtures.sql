-- Disposable only. Reuse A018 hierarchy and A046 stable persona aliases.
DO $$ BEGIN
 IF current_database() !~ '^core10_np03b_(ci|local)' OR to_regclass('auth.users') IS NOT NULL
 THEN RAISE EXCEPTION 'NP03B_DISPOSABLE_ONLY'; END IF;
END $$;
\ir hierarchy.sql
UPDATE core10.businesses SET template_code='sweets_bakery' WHERE id IN(101,102,201);
INSERT INTO core10.business_members(tenant_id,business_id,user_id,role) VALUES
 (1,102,'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','business_owner'),
 (1,102,'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','manager');
INSERT INTO core10.site_grants(tenant_id,business_id,site_id,user_id,actions) VALUES
 (1,101,1002,'cccccccc-cccc-4ccc-8ccc-cccccccccccc',ARRAY['stock.read']),
 (1,102,1003,'dddddddd-dddd-4ddd-8ddd-dddddddddddd',ARRAY['stock.read']);
-- The unassigned/reviewer/partner/platform UUIDs deliberately have no Sales grant.
-- Test-only Master adapter, NEVER migrated. This demonstrates the proposed port
-- boundary; it does not certify canonical NP02 Master integration.
CREATE FUNCTION core10.master_validate_sales_order_v1(b bigint,s bigint,d jsonb) RETURNS boolean
LANGUAGE sql STABLE SET search_path=pg_catalog,core10 AS $$
 SELECT b=101 AND s IN(1001,1002) AND d->>'customer_id'='7001'
  AND d->>'price_list_id' IN('7101','7102') AND d->>'currency'='BDT'
  AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(d->'lines') l
   LEFT JOIN (VALUES(8101,300),(8102,420),(8103,850),(8104,1200),(8105,250)) p(id,price)
    ON p.id=(l->>'item_id')::bigint
   WHERE p.id IS NULL OR l->>'uom_id'<>'7201'
    OR coalesce(l->>'variant_id','7301')<>'7301'
    OR (l->>'unit_price')::numeric<>p.price*CASE d->>'price_list_id' WHEN '7102' THEN .9 ELSE 1 END
    OR (l->>'tax_percent')::numeric<>0)
$$;
REVOKE ALL ON FUNCTION core10.master_validate_sales_order_v1(bigint,bigint,jsonb) FROM PUBLIC,authenticated;
-- Synthetic assumptions ONLY: BDT, tax=0, retail/90% wholesale price lists;
-- Rasgulla Box 300, Sandesh Box 420, Mixed Sweets 1kg 850, Chocolate Cake 1200,
-- Butter Cookies 250. IDs are inert fixture references, no customer/Auth records.
