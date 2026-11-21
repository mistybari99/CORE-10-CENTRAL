-- B-014: site/order-scoped projection of the ONE canonical Audit stream.
-- Read-only; does not introduce a Sales audit store or mutate Owner Control.
CREATE FUNCTION core10.read_sales_order_audit_v1(p_business bigint,p_site bigint,p_order bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE t bigint; rows jsonb;
BEGIN
 t:=core10._sales_scope_v1(p_business,p_site);
 IF p_order IS NULL OR NOT EXISTS(SELECT 1 FROM core10.sales_orders_v1
  WHERE id=p_order AND tenant_id=t AND business_id=p_business AND site_id=p_site)
 THEN RAISE EXCEPTION 'SALES_ORDER_NOT_FOUND'; END IF;
 SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.stream_seq DESC),'[]'::jsonb) INTO rows FROM (
  SELECT a.id,a.stream_seq,a.action,a.actor_id,a.event_at,a.payload,
   c.order_id,c.business_id,c.site_id
  FROM core10.sales_order_commands_v1 c
  JOIN core10.canonical_audit_events_v1 a ON a.id=c.audit_event_id
   AND a.tenant_id=c.tenant_id AND a.business_id=c.business_id AND a.source_domain='sales'
  WHERE c.tenant_id=t AND c.business_id=p_business AND c.site_id=p_site AND c.order_id=p_order
  ORDER BY a.stream_seq DESC LIMIT 100
 ) x;
 RETURN jsonb_build_object('business_id',p_business,'site_id',p_site,'order_id',p_order,'items',rows);
END $$;
REVOKE ALL ON FUNCTION core10.read_sales_order_audit_v1(bigint,bigint,bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION core10.read_sales_order_audit_v1(bigint,bigint,bigint) TO authenticated;
