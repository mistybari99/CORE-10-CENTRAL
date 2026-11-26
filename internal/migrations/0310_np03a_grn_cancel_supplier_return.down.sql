-- Rollback of 0207: fail closed once any GRN was cancelled, any supplier return exists, or any 0207 request,
-- audit row or Owner Control setting for procurement.supplier_return was written. Otherwise restore the exact prior
-- bodies: _proc_grn_json_v1 / _proc_po_json_v1 / _proc_open_qty_v1 from 0203, owner_business_sites_v1 from 0204 and
-- procurement_advance_po_v1 from 0206 as integrated on trunk ccr-15ed11dd-n3hw5h (PR #129, with its post-lock Auth
-- re-check), then the 0203 constraints, and drop the 0207 objects.
DO $guard$ BEGIN
 IF EXISTS(SELECT 1 FROM core10.supplier_returns_v1)
 OR EXISTS(SELECT 1 FROM core10.goods_receipts_v1 WHERE status='cancelled' OR cancelled_by IS NOT NULL)
 OR EXISTS(SELECT 1 FROM core10.goods_receipt_lines_v1 WHERE returned_qty<>0)
 OR EXISTS(SELECT 1 FROM core10.purchase_order_lines_v1 WHERE returned_qty<>0)
 OR EXISTS(SELECT 1 FROM core10.procurement_requests_v1 WHERE action IN ('grn_cancel','return_save','return_post','return_cancel'))
 OR EXISTS(SELECT 1 FROM core10.canonical_audit_events_v1 WHERE source_domain='procurement'
   AND action IN ('procurement.grn_cancel','procurement.return_save','procurement.return_post','procurement.return_cancel'))
 OR EXISTS(SELECT 1 FROM core10.control_setting_versions_v1 WHERE feature_key='procurement.supplier_return')
 OR EXISTS(SELECT 1 FROM core10.control_overrides_v1 WHERE feature_key='procurement.supplier_return')
 THEN RAISE EXCEPTION 'PROC_ROLLBACK_DENIED_RETURN_OR_CANCEL_HISTORY'; END IF;
END $guard$;
DELETE FROM core10.control_rpc_map_v1 WHERE lane='Claude' AND board_row='B-012' AND rpc_name IN
 ('procurement_cancel_grn_v1','procurement_save_return_v1','procurement_advance_return_v1');
DROP FUNCTION core10.procurement_list_lots_v1(bigint,bigint,integer,date,bigint,integer);
DROP FUNCTION core10.procurement_advance_return_v1(bigint,text,integer,text);
DROP FUNCTION core10.procurement_save_return_v1(bigint,jsonb,text,text);
DROP FUNCTION core10.procurement_cancel_grn_v1(bigint,integer,text,text);
-- 0204 owner_business_sites_v1 (exact)
CREATE OR REPLACE FUNCTION core10.owner_business_sites_v1(p_business bigint, p_kind text DEFAULT NULL, p_after_site bigint DEFAULT NULL,
 p_limit integer DEFAULT 50) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE t bigint; v_limit int := least(greatest(coalesce(p_limit,50),1),200); v_rows jsonb;
BEGIN
 SELECT tenant_id INTO t FROM core10.businesses WHERE id=p_business;
 IF core10.actor_uid() IS NULL OR t IS NULL OR NOT core10.can_business(t,p_business) THEN RAISE EXCEPTION 'DASH_SCOPE'; END IF;
 IF p_kind IS NOT NULL AND p_kind NOT IN ('showroom','factory','godown','warehouse','project') THEN RAISE EXCEPTION 'DASH_INVALID_FILTER'; END IF;
 WITH s AS (SELECT id, kind, label FROM core10.sites
   WHERE business_id=p_business AND (p_kind IS NULL OR kind=p_kind) AND (p_after_site IS NULL OR id>p_after_site)
     AND core10.can_site(t,p_business,id,'stock.read') ORDER BY id LIMIT v_limit),
 bal AS (SELECT site_id, count(*) FILTER (WHERE on_hand>0) AS stock_rows, coalesce(sum(on_hand),0) AS units
   FROM core10.stock_balances_v1 WHERE business_id=p_business AND site_id IN (SELECT id FROM s) GROUP BY 1),
 loc AS (SELECT site_id, count(*) AS locations FROM core10.stock_locations WHERE business_id=p_business AND site_id IN (SELECT id FROM s) GROUP BY 1),
 po AS (SELECT site_id, count(*) AS open_pos FROM core10.purchase_orders_v1
   WHERE business_id=p_business AND site_id IN (SELECT id FROM s) AND status IN ('approved','partially_received') GROUP BY 1),
 gr AS (SELECT site_id, count(*) AS receipts_waiting FROM core10.goods_receipts_v1
   WHERE business_id=p_business AND site_id IN (SELECT id FROM s) AND status<>'posted' GROUP BY 1),
 cm AS (SELECT x.site_id, count(DISTINCT x.id) AS commands_open FROM (
   SELECT id, source_site_id AS site_id FROM core10.inventory_commands_v1 WHERE business_id=p_business AND status IN ('draft','confirmed')
   UNION ALL SELECT id, destination_site_id FROM core10.inventory_commands_v1 WHERE business_id=p_business AND status IN ('draft','confirmed')) x
   WHERE x.site_id IN (SELECT id FROM s) GROUP BY 1)
 SELECT coalesce(jsonb_agg(jsonb_build_object('site_id',s.id,'kind',s.kind,'label',s.label,'locations',coalesce(loc.locations,0),
   'stock_rows',coalesce(bal.stock_rows,0),'units',coalesce(bal.units,0),'open_pos',coalesce(po.open_pos,0),
   'receipts_waiting',coalesce(gr.receipts_waiting,0),'commands_open',coalesce(cm.commands_open,0)) ORDER BY s.id),'[]'::jsonb)
 INTO v_rows FROM s LEFT JOIN bal ON bal.site_id=s.id LEFT JOIN loc ON loc.site_id=s.id LEFT JOIN po ON po.site_id=s.id
  LEFT JOIN gr ON gr.site_id=s.id LEFT JOIN cm ON cm.site_id=s.id;
 RETURN jsonb_build_object('business_id',p_business,'kind',p_kind,'items',v_rows,'limit',v_limit,
  'next_after_site',CASE WHEN jsonb_array_length(v_rows)=v_limit THEN (v_rows->(v_limit-1)->>'site_id')::bigint END);
END $$;
-- 0206 procurement_advance_po_v1 (exact, trunk)
CREATE OR REPLACE FUNCTION core10.procurement_advance_po_v1(p_po bigint, p_action text, p_version integer, p_key text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE v_actor uuid := core10.actor_uid(); p core10.purchase_orders_v1%ROWTYPE; c jsonb; v_sha text; v_id bigint;
 v_appr jsonb := '{}';
BEGIN
 IF v_actor IS NULL OR p_action IS NULL OR p_action NOT IN ('approve','cancel','close') OR p_version IS NULL THEN RAISE EXCEPTION 'PROC_INVALID_ACTION'; END IF;
 SELECT * INTO p FROM core10.purchase_orders_v1 WHERE id=p_po;
 IF NOT FOUND OR NOT core10.can_see_business(p.tenant_id,p.business_id) THEN RAISE EXCEPTION 'PROC_SCOPE'; END IF;
 IF NOT core10.can_manage(p.tenant_id,p.business_id) AND NOT (p_action='cancel' AND p.created_by=v_actor)
 THEN RAISE EXCEPTION 'PROC_PERMISSION_DENIED'; END IF;
 SELECT * INTO p FROM core10.purchase_orders_v1 WHERE id=p_po FOR UPDATE;
 -- Re-read Auth after the row lock; permission could have been revoked while waiting.
 IF NOT core10.can_see_business(p.tenant_id,p.business_id) THEN RAISE EXCEPTION 'PROC_SCOPE'; END IF;
 IF NOT core10.can_manage(p.tenant_id,p.business_id) AND NOT (p_action='cancel' AND p.created_by=v_actor)
 THEN RAISE EXCEPTION 'PROC_PERMISSION_DENIED'; END IF;
 c := core10.control_check_v1(p.business_id, 'procurement.purchase_order', p.site_id);
 v_sha := core10._proc_sha_v1(jsonb_build_object('po',p_po,'a',p_action,'v',p_version));
 v_id := core10._proc_replay_v1(p.business_id,p_key,'po_'||p_action,v_sha);
 IF v_id IS NOT NULL THEN RETURN core10._proc_po_json_v1(v_id) || '{"replayed":true}'; END IF;
 IF p.version<>p_version THEN RAISE EXCEPTION 'PROC_STALE_VERSION:%', p.version; END IF;
 IF p_action='approve' THEN
  IF p.status<>'draft' THEN RAISE EXCEPTION 'PROC_INVALID_TRANSITION'; END IF;
  IF (c->'params'->>'separate_approver')::boolean AND p.created_by=v_actor THEN RAISE EXCEPTION 'PROC_SAME_ACTOR'; END IF;
  -- Approval port: never self-approve or fabricate a receipt; stages = 0 returns '{}' (0203 behaviour).
  v_appr := core10._proc_po_approval_gate_v1(p.id, (c->>'stages')::int);
  UPDATE core10.purchase_orders_v1 SET status='approved',approved_by=v_actor,approved_at=now(),version=version+1 WHERE id=p.id;
 ELSIF p_action='cancel' THEN
  IF p.status NOT IN ('draft','approved') OR EXISTS(SELECT 1 FROM core10.goods_receipts_v1 WHERE po_id=p.id)
  THEN RAISE EXCEPTION 'PROC_INVALID_TRANSITION'; END IF;
  UPDATE core10.purchase_orders_v1 SET status='cancelled',closed_by=v_actor,closed_at=now(),version=version+1 WHERE id=p.id;
 ELSE
  IF p.status NOT IN ('approved','partially_received') OR EXISTS(SELECT 1 FROM core10.goods_receipts_v1 WHERE po_id=p.id AND status<>'posted')
  THEN RAISE EXCEPTION 'PROC_INVALID_TRANSITION'; END IF;
  UPDATE core10.purchase_orders_v1 SET status='closed',closed_by=v_actor,closed_at=now(),version=version+1 WHERE id=p.id;
 END IF;
 PERFORM core10._proc_record_v1(p.tenant_id,p.business_id,p_key,'po_'||p_action,p.id,v_sha,'po:'||p.id||':'||p_action,
  jsonb_build_object('po_id',p.id,'from_version',p_version) || v_appr);
 RETURN core10._proc_po_json_v1(p.id) || jsonb_build_object('replayed',false) || v_appr;
END $$;
-- 0203 helpers (exact)
CREATE OR REPLACE FUNCTION core10._proc_open_qty_v1(p_po bigint, p_line integer) RETURNS numeric
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
 SELECT l.quantity - coalesce((SELECT sum(CASE WHEN g.status='posted' THEN gl.accepted_qty ELSE gl.received_qty END)
   FROM core10.goods_receipt_lines_v1 gl JOIN core10.goods_receipts_v1 g ON g.id=gl.grn_id
   WHERE gl.po_id=p_po AND gl.line_no=p_line),0)
 FROM core10.purchase_order_lines_v1 l WHERE l.po_id=p_po AND l.line_no=p_line
$$;
CREATE OR REPLACE FUNCTION core10._proc_po_json_v1(p_po bigint) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
 SELECT jsonb_build_object('po_id',p.id,'business_id',p.business_id,'site_id',p.site_id,'supplier_id',p.supplier_id,
  'supplier_name_en',s.name_en,'supplier_name_bn',s.name_bn,'status',p.status,'version',p.version,
  'expected_on',p.expected_on,'note',p.note,'total_amount',p.total_amount,'created_by',p.created_by,
  'created_at',p.created_at,'approved_by',p.approved_by,
  'lines',coalesce((SELECT jsonb_agg(jsonb_build_object('line_no',l.line_no,'item_id',l.item_id,'sku',i.sku,
    'name_en',i.name_en,'name_bn',i.name_bn,'quantity',l.quantity,'unit_price',l.unit_price,
    'amount',round(l.quantity*l.unit_price,2),'accepted_qty',l.accepted_qty,'rejected_qty',l.rejected_qty) ORDER BY l.line_no)
    FROM core10.purchase_order_lines_v1 l JOIN core10.items i ON i.id=l.item_id WHERE l.po_id=p.id),'[]'::jsonb))
 FROM core10.purchase_orders_v1 p JOIN core10.master_parties_v1 s ON s.id=p.supplier_id WHERE p.id=p_po
$$;
CREATE OR REPLACE FUNCTION core10._proc_grn_json_v1(p_grn bigint) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
 SELECT jsonb_build_object('grn_id',g.id,'po_id',g.po_id,'business_id',g.business_id,'site_id',g.site_id,
  'location_id',g.location_id,'supplier_ref',g.supplier_ref,'status',g.status,'version',g.version,
  'received_by',g.received_by,'received_at',g.received_at,'inspected_by',g.inspected_by,'posted_by',g.posted_by,
  'posted_at',g.posted_at,'lines',coalesce((SELECT jsonb_agg(jsonb_build_object('line_no',l.line_no,'item_id',l.item_id,
   'received_qty',l.received_qty,'accepted_qty',l.accepted_qty,
   'rejected_qty',CASE WHEN l.accepted_qty IS NULL THEN NULL ELSE l.received_qty-l.accepted_qty END,
   'qc_notes',l.qc_notes,'lot_code',l.lot_code,'manufactured_on',l.manufactured_on,'expires_on',l.expires_on,
   'lot_id',l.lot_id,'stock_movement_id',l.stock_movement_id) ORDER BY l.line_no)
   FROM core10.goods_receipt_lines_v1 l WHERE l.grn_id=g.id),'[]'::jsonb))
 FROM core10.goods_receipts_v1 g WHERE g.id=p_grn
$$;
DROP FUNCTION core10._proc_return_json_v1(bigint);
DROP TABLE core10.supplier_return_lines_v1;
DROP TABLE core10.supplier_returns_v1;
DROP INDEX core10.goods_receipt_lines_lot_ix;
DROP INDEX core10.inventory_lots_business_expiry_ix;
ALTER TABLE core10.procurement_requests_v1 DROP CONSTRAINT procurement_requests_v1_action_check;
ALTER TABLE core10.procurement_requests_v1 ADD CONSTRAINT procurement_requests_v1_action_check
 CHECK (action IN ('po_save','po_approve','po_cancel','po_close','grn_receive','grn_inspect','grn_post'));
ALTER TABLE core10.purchase_order_lines_v1 DROP CONSTRAINT purchase_order_lines_v1_returned_v1;
ALTER TABLE core10.purchase_order_lines_v1 DROP COLUMN returned_qty;
ALTER TABLE core10.goods_receipt_lines_v1 DROP CONSTRAINT goods_receipt_lines_v1_returned_v1;
ALTER TABLE core10.goods_receipt_lines_v1 DROP COLUMN returned_qty;
ALTER TABLE core10.goods_receipts_v1 DROP CONSTRAINT goods_receipts_v1_cancel_v1;
ALTER TABLE core10.goods_receipts_v1 DROP CONSTRAINT goods_receipts_v1_check;
ALTER TABLE core10.goods_receipts_v1 ADD CONSTRAINT goods_receipts_v1_check
 CHECK ((status='received' AND inspected_by IS NULL AND posted_by IS NULL)
     OR (status='inspected' AND inspected_by IS NOT NULL AND posted_by IS NULL)
     OR (status='posted' AND inspected_by IS NOT NULL AND posted_by IS NOT NULL));
ALTER TABLE core10.goods_receipts_v1 DROP CONSTRAINT goods_receipts_v1_status_check;
ALTER TABLE core10.goods_receipts_v1 ADD CONSTRAINT goods_receipts_v1_status_check
 CHECK (status IN ('received','inspected','posted'));
ALTER TABLE core10.goods_receipts_v1 DROP COLUMN cancel_reason, DROP COLUMN cancelled_at, DROP COLUMN cancelled_by;
DELETE FROM core10.control_catalog_v1 WHERE feature_key='procurement.supplier_return';
