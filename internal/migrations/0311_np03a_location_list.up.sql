-- NP03A / B-012 (0208): scoped stock-location list (Claude Agent J, block 0200-0299). Read-only, STABLE.
-- Screens (Purchases receive form, stock workbench) read core10.stock_locations through the table RLS policy
-- location_scope_read (0002), which evaluates core10.can_site once per row and exposes table paths to the API.
-- This RPC replaces that read: one versioned, scoped call returning the locations of one business (optionally one
-- site) that the caller may read, with the site kind/label and whether the caller may post stock there.
-- Readable-site rule is exactly core10.can_site(t, p_business, site, 'stock.read'), resolved ONCE per business as in
-- 0205 (inventory_list_balances_v1):
--  * a site where the caller has NO site_grants row at all has no deny and no grant, so can_site reduces to
--    can_business (evaluated once);
--  * every site where the caller has any site_grants row (grant or deny, live or expired) is decided by the
--    authoritative core10.can_site itself, so explicit denies still beat owner/manager rights.
-- can_post follows the same rule for 'stock.post' (a denied read also blocks posting, as in can_site).
-- Errors: INV_SCOPE (no signed actor, unknown business, business not visible, p_site not readable).
-- At most 2000 locations are returned (ordered by site, then location id); 'truncated' says whether more exist.

CREATE FUNCTION core10.inventory_list_locations_v1(p_business bigint, p_site bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE t bigint; v_actor uuid := core10.actor_uid(); v_biz boolean; v_rows jsonb; v_n int;
BEGIN
 SELECT tenant_id INTO t FROM core10.businesses WHERE id=p_business;
 IF v_actor IS NULL OR t IS NULL OR NOT core10.can_see_business(t,p_business) THEN RAISE EXCEPTION 'INV_SCOPE'; END IF;
 IF p_site IS NOT NULL AND NOT core10.can_site(t,p_business,p_site,'stock.read') THEN RAISE EXCEPTION 'INV_SCOPE'; END IF;
 v_biz := core10.can_business(t,p_business);
 WITH g AS (SELECT DISTINCT gr.site_id FROM core10.site_grants gr WHERE gr.user_id=v_actor AND gr.business_id=p_business),
 s AS (
  SELECT x.id, x.kind, x.label,
   CASE WHEN x.id IN (SELECT site_id FROM g) THEN core10.can_site(t,p_business,x.id,'stock.post') ELSE v_biz END AS can_post
  FROM core10.sites x
  WHERE x.tenant_id=t AND x.business_id=p_business AND (p_site IS NULL OR x.id=p_site)
    AND CASE WHEN x.id IN (SELECT site_id FROM g) THEN core10.can_site(t,p_business,x.id,'stock.read') ELSE v_biz END),
 page AS (
  SELECT l.id, l.site_id, l.code, s.kind, s.label, s.can_post
  FROM core10.stock_locations l JOIN s ON s.id=l.site_id
  WHERE l.tenant_id=t AND l.business_id=p_business
  ORDER BY l.site_id, l.id LIMIT 2001)
 SELECT coalesce(jsonb_agg(jsonb_build_object('location_id',p.id,'site_id',p.site_id,'site_kind',p.kind,'site_label',p.label,
   'code',p.code,'can_post',p.can_post) ORDER BY p.site_id, p.id),'[]'::jsonb), count(*)
 INTO v_rows, v_n FROM page p;
 IF v_n > 2000 THEN v_rows := v_rows - 2000; END IF;
 RETURN jsonb_build_object('business_id',p_business,'site_id',p_site,'items',v_rows,'truncated',v_n > 2000);
END $$;

REVOKE ALL ON FUNCTION core10.inventory_list_locations_v1(bigint,bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION core10.inventory_list_locations_v1(bigint,bigint) TO authenticated;
