-- Rollback of 0206: refuse once any purchase order carries an approval request; otherwise restore the exact 0203
-- procurement_advance_po_v1 (approve with stages > 0 fails closed with PROC_APPROVAL_NOT_CONNECTED).
DO $guard$ BEGIN
 IF EXISTS(SELECT 1 FROM core10.purchase_orders_v1 WHERE approval_request_id IS NOT NULL)
 OR EXISTS(SELECT 1 FROM core10.canonical_audit_events_v1 WHERE source_domain='procurement' AND action='procurement.po_approval_requested')
 THEN RAISE EXCEPTION 'PROC_ROLLBACK_DENIED_APPROVAL_HISTORY'; END IF;
END $guard$;
DELETE FROM core10.control_rpc_map_v1 WHERE lane='Claude' AND board_row='B-012' AND rpc_name='procurement_request_po_approval_v1';
DROP FUNCTION core10.procurement_request_po_approval_v1(bigint,text);
-- approve (draft -> approved), cancel (draft/approved with no receipt -> cancelled), close (short-close an open PO)
CREATE OR REPLACE FUNCTION core10.procurement_advance_po_v1(p_po bigint, p_action text, p_version integer, p_key text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE v_actor uuid := core10.actor_uid(); p core10.purchase_orders_v1%ROWTYPE; c jsonb; v_sha text; v_id bigint;
BEGIN
 IF v_actor IS NULL OR p_action IS NULL OR p_action NOT IN ('approve','cancel','close') OR p_version IS NULL THEN RAISE EXCEPTION 'PROC_INVALID_ACTION'; END IF;
 SELECT * INTO p FROM core10.purchase_orders_v1 WHERE id=p_po;
 IF NOT FOUND OR NOT core10.can_see_business(p.tenant_id,p.business_id) THEN RAISE EXCEPTION 'PROC_SCOPE'; END IF;
 IF NOT core10.can_manage(p.tenant_id,p.business_id) AND NOT (p_action='cancel' AND p.created_by=v_actor)
 THEN RAISE EXCEPTION 'PROC_PERMISSION_DENIED'; END IF;
 SELECT * INTO p FROM core10.purchase_orders_v1 WHERE id=p_po FOR UPDATE;
 c := core10.control_check_v1(p.business_id, 'procurement.purchase_order', p.site_id);
 v_sha := core10._proc_sha_v1(jsonb_build_object('po',p_po,'a',p_action,'v',p_version));
 v_id := core10._proc_replay_v1(p.business_id,p_key,'po_'||p_action,v_sha);
 IF v_id IS NOT NULL THEN RETURN core10._proc_po_json_v1(v_id) || '{"replayed":true}'; END IF;
 IF p.version<>p_version THEN RAISE EXCEPTION 'PROC_STALE_VERSION:%', p.version; END IF;
 IF p_action='approve' THEN
  IF p.status<>'draft' THEN RAISE EXCEPTION 'PROC_INVALID_TRANSITION'; END IF;
  IF (c->'params'->>'separate_approver')::boolean AND p.created_by=v_actor THEN RAISE EXCEPTION 'PROC_SAME_ACTOR'; END IF;
  IF (c->>'stages')::int>0 THEN RAISE EXCEPTION 'PROC_APPROVAL_NOT_CONNECTED'; END IF;
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
  jsonb_build_object('po_id',p.id,'from_version',p_version));
 RETURN core10._proc_po_json_v1(p.id) || '{"replayed":false}';
END $$;
DROP FUNCTION core10._proc_po_approval_gate_v1(bigint,integer);
DROP FUNCTION core10._proc_po_route_matches_v1(bigint,bigint,bigint,integer);
DROP FUNCTION core10._proc_po_approval_payload_v1(bigint);
ALTER TABLE core10.purchase_orders_v1 DROP COLUMN approval_request_id;
