-- NP03A / B-012 P4 (0205): inventory balance read at scale (Claude, block 0200-0299). Read-only, STABLE.
-- 0201 evaluated core10.can_site once per balance row. A site-only staff member reading a whole business
-- (p_site NULL) over 400 sites x 20 items paid 8,000 permission calls to see 20 rows.
-- This version resolves the readable site ids of the business ONCE, then filters balances by site_id = ANY(...)
-- (index stock_balances_business_site_ix from 0204). Signature, error codes, ordering, keyset paging, the 200
-- cap and the JSON shape are unchanged.
-- Readable-site rule is exactly core10.can_site(t, p_business, site, 'stock.read'):
--  * a site of this tenant/business where the caller has NO site_grants row at all has no deny and no grant,
--    so can_site reduces to can_business (evaluated once here);
--  * every site where the caller has any site_grants row (grant or deny, live or expired) is decided by the
--    authoritative core10.can_site itself, so explicit denies still beat owner/manager rights.

CREATE OR REPLACE FUNCTION core10.inventory_list_balances_v1(p_business bigint, p_site bigint DEFAULT NULL,
 p_after_location bigint DEFAULT NULL, p_after_item bigint DEFAULT NULL, p_limit integer DEFAULT 100)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE t bigint; v_limit int := least(greatest(coalesce(p_limit,100),1),200); v_rows jsonb;
 v_actor uuid := core10.actor_uid(); v_biz boolean; v_sites bigint[];
BEGIN
 SELECT tenant_id INTO t FROM core10.businesses WHERE id=p_business;
 IF v_actor IS NULL OR t IS NULL OR NOT core10.can_see_business(t,p_business) THEN RAISE EXCEPTION 'INV_SCOPE'; END IF;
 IF p_site IS NOT NULL AND NOT core10.can_site(t,p_business,p_site,'stock.read') THEN RAISE EXCEPTION 'INV_SCOPE'; END IF;
 IF (p_after_location IS NULL) <> (p_after_item IS NULL) THEN RAISE EXCEPTION 'INV_INVALID_FILTER'; END IF;
 v_biz := core10.can_business(t,p_business);
 SELECT coalesce(array_agg(s.id),'{}'::bigint[]) INTO v_sites FROM core10.sites s
  WHERE s.tenant_id=t AND s.business_id=p_business AND (p_site IS NULL OR s.id=p_site)
    AND CASE WHEN s.id IN (SELECT g.site_id FROM core10.site_grants g WHERE g.user_id=v_actor)
             THEN core10.can_site(t,p_business,s.id,'stock.read')
             ELSE v_biz END;
 SELECT coalesce(jsonb_agg(q.r ORDER BY (q.r->>'location_id')::bigint,(q.r->>'item_id')::bigint),'[]'::jsonb) INTO v_rows FROM (
  SELECT jsonb_build_object('site_id',b.site_id,'site_kind',s.kind,'site_label',s.label,'location_id',b.location_id,
   'location_code',l.code,'item_id',b.item_id,'sku',i.sku,'name_en',i.name_en,'name_bn',i.name_bn,'on_hand',b.on_hand) AS r
  FROM core10.stock_balances_v1 b
  JOIN core10.stock_locations l ON l.id=b.location_id
  JOIN core10.sites s ON s.id=b.site_id
  JOIN core10.items i ON i.id=b.item_id
  WHERE b.business_id=p_business AND b.site_id=ANY(v_sites)
    AND (p_after_location IS NULL OR (b.location_id,b.item_id)>(p_after_location,p_after_item))
  ORDER BY b.location_id,b.item_id LIMIT v_limit) q;
 RETURN jsonb_build_object('business_id',p_business,'items',v_rows,'limit',v_limit,
  'next_after',CASE WHEN jsonb_array_length(v_rows)=v_limit THEN jsonb_build_object(
   'location_id',(v_rows->(v_limit-1)->>'location_id')::bigint,'item_id',(v_rows->(v_limit-1)->>'item_id')::bigint) END);
END $$;

REVOKE ALL ON FUNCTION core10.inventory_list_balances_v1(bigint,bigint,bigint,bigint,integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION core10.inventory_list_balances_v1(bigint,bigint,bigint,bigint,integer) TO authenticated;
