-- Rollback of 0205: restore the exact 0201 definition of inventory_list_balances_v1 (per-row can_site).
-- Read-only function swap; no data is touched.
-- Balances with item, location and site labels. Keyset on (location_id, item_id).
CREATE OR REPLACE FUNCTION core10.inventory_list_balances_v1(p_business bigint, p_site bigint DEFAULT NULL,
 p_after_location bigint DEFAULT NULL, p_after_item bigint DEFAULT NULL, p_limit integer DEFAULT 100)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE t bigint; v_limit int := least(greatest(coalesce(p_limit,100),1),200); v_rows jsonb;
BEGIN
 SELECT tenant_id INTO t FROM core10.businesses WHERE id=p_business;
 IF core10.actor_uid() IS NULL OR t IS NULL OR NOT core10.can_see_business(t,p_business) THEN RAISE EXCEPTION 'INV_SCOPE'; END IF;
 IF p_site IS NOT NULL AND NOT core10.can_site(t,p_business,p_site,'stock.read') THEN RAISE EXCEPTION 'INV_SCOPE'; END IF;
 IF (p_after_location IS NULL) <> (p_after_item IS NULL) THEN RAISE EXCEPTION 'INV_INVALID_FILTER'; END IF;
 SELECT coalesce(jsonb_agg(q.r ORDER BY (q.r->>'location_id')::bigint,(q.r->>'item_id')::bigint),'[]'::jsonb) INTO v_rows FROM (
  SELECT jsonb_build_object('site_id',b.site_id,'site_kind',s.kind,'site_label',s.label,'location_id',b.location_id,
   'location_code',l.code,'item_id',b.item_id,'sku',i.sku,'name_en',i.name_en,'name_bn',i.name_bn,'on_hand',b.on_hand) AS r
  FROM core10.stock_balances_v1 b
  JOIN core10.stock_locations l ON l.id=b.location_id
  JOIN core10.sites s ON s.id=b.site_id
  JOIN core10.items i ON i.id=b.item_id
  WHERE b.business_id=p_business AND (p_site IS NULL OR b.site_id=p_site)
    AND (p_after_location IS NULL OR (b.location_id,b.item_id)>(p_after_location,p_after_item))
    AND core10.can_site(t,p_business,b.site_id,'stock.read')
  ORDER BY b.location_id,b.item_id LIMIT v_limit) q;
 RETURN jsonb_build_object('business_id',p_business,'items',v_rows,'limit',v_limit,
  'next_after',CASE WHEN jsonb_array_length(v_rows)=v_limit THEN jsonb_build_object(
   'location_id',(v_rows->(v_limit-1)->>'location_id')::bigint,'item_id',(v_rows->(v_limit-1)->>'item_id')::bigint) END);
END $$;

REVOKE ALL ON FUNCTION core10.inventory_list_balances_v1(bigint,bigint,bigint,bigint,integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION core10.inventory_list_balances_v1(bigint,bigint,bigint,bigint,integer) TO authenticated;
