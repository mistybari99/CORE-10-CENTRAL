-- Read-only bridge to the canonical Procurement, Stock and Audit records.
-- Deployable before Procurement 0203. The provider is required at call time.
CREATE FUNCTION core10.mfg_verify_grn_source_v1(
 p_business bigint,p_site bigint,p_batch bigint,p_grn bigint,p_line integer,p_lot bigint
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE tenant bigint; location bigint; recipe bigint; evidence jsonb;
BEGIN
 tenant:=core10._mfg_scope_v1(p_business,p_site);
 IF NOT (core10._control_resolve_v1(p_business,'mfg.material_requirements',p_site)->>'enabled')::boolean THEN
  RAISE EXCEPTION 'CONTROL_DISABLED:mfg.material_requirements';
 END IF;
 SELECT b.location_id,b.bom_id INTO location,recipe FROM core10.production_batches_v1 b
 WHERE b.id=p_batch AND b.tenant_id=tenant AND b.business_id=p_business AND b.site_id=p_site AND b.status<>'cancelled';
 IF NOT FOUND THEN RAISE EXCEPTION 'MFG_GRN_BATCH_SCOPE'; END IF;
 IF p_grn IS NULL OR p_grn<1 OR p_line IS NULL OR p_line NOT BETWEEN 1 AND 200 OR p_lot IS NULL OR p_lot<1 THEN
  RAISE EXCEPTION 'MFG_GRN_INVALID_REFERENCE';
 END IF;
 IF NOT EXISTS (SELECT 1 FROM core10.schema_migrations WHERE version=203 AND name='0203_np03a_procurement_grn')
    OR to_regclass('core10.goods_receipts_v1') IS NULL OR to_regclass('core10.goods_receipt_lines_v1') IS NULL
    OR to_regclass('core10.inventory_lots_v1') IS NULL THEN
  RAISE EXCEPTION 'NOT_CONNECTED:PROCUREMENT_GRN';
 END IF;

 SELECT jsonb_build_object('batch_id',p_batch,'grn_id',g.id,'po_id',g.po_id,
   'line_no',l.line_no,'item_id',l.item_id,'sku',i.sku,'accepted_receipt_qty',l.accepted_qty,
   'location_id',g.location_id,'lot_id',lot.id,'lot_code',lot.lot_code,'expires_on',lot.expires_on,
   'stock_movement_id',m.id,'audit_event_id',a.id)
 INTO evidence
 FROM core10.goods_receipts_v1 g
 JOIN core10.goods_receipt_lines_v1 l ON l.grn_id=g.id AND l.tenant_id=g.tenant_id
  AND l.business_id=g.business_id AND l.po_id=g.po_id AND l.line_no=p_line
 JOIN core10.bom_ingredients_v1 component ON component.bom_id=recipe AND component.ingredient_item_id=l.item_id
  AND component.tenant_id=g.tenant_id AND component.business_id=g.business_id AND component.site_id=g.site_id
 JOIN core10.items i ON i.id=l.item_id AND i.tenant_id=g.tenant_id AND i.business_id=g.business_id
 JOIN core10.inventory_lots_v1 lot ON lot.id=l.lot_id AND lot.id=p_lot AND lot.tenant_id=g.tenant_id
  AND lot.business_id=g.business_id AND lot.item_id=l.item_id AND lot.lot_code=l.lot_code
  AND lot.manufactured_on IS NOT DISTINCT FROM l.manufactured_on AND lot.expires_on IS NOT DISTINCT FROM l.expires_on
  AND lot.source_kind='purchase' AND lot.status='released' AND (lot.expires_on IS NULL OR lot.expires_on>=CURRENT_DATE)
 JOIN core10.stock_movements m ON m.id=l.stock_movement_id AND m.tenant_id=g.tenant_id
  AND m.business_id=g.business_id AND m.site_id=g.site_id AND m.location_id=g.location_id AND m.item_id=l.item_id
  AND m.delta=l.accepted_qty AND m.created_by=g.posted_by AND m.request_key='c10-grn-'||g.id||'-'||l.line_no
 JOIN core10.canonical_audit_events_v1 a ON a.tenant_id=g.tenant_id AND a.business_id=g.business_id
  AND a.source_domain='procurement' AND a.source_ref='grn:'||g.id||':posted' AND a.action='procurement.grn_post'
  AND a.actor_id=g.posted_by AND a.payload->'grn_id'=to_jsonb(g.id) AND a.payload->'po_id'=to_jsonb(g.po_id)
  AND a.payload->'location_id'=to_jsonb(g.location_id)
  AND a.payload->'stock_movements' @> jsonb_build_array(m.id)
 WHERE g.id=p_grn AND g.tenant_id=tenant AND g.business_id=p_business AND g.site_id=p_site
  AND g.location_id=location AND g.status='posted' AND l.accepted_qty>0;
 IF NOT FOUND THEN RAISE EXCEPTION 'MFG_GRN_SOURCE_UNVERIFIED'; END IF;
 RETURN evidence;
END $$;

REVOKE ALL ON FUNCTION core10.mfg_verify_grn_source_v1(bigint,bigint,bigint,bigint,integer,bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION core10.mfg_verify_grn_source_v1(bigint,bigint,bigint,bigint,integer,bigint) TO authenticated;
