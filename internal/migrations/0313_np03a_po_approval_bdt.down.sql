-- Rollback of 0210: restore the exact 0206 bodies of _proc_po_approval_payload_v1 (unit 'currency_total') and
-- procurement_request_po_approval_v1. Requests created under 0210 (unit 'BDT') are then bound to a payload digest the
-- 0206 builder no longer produces, so the approve gate refuses them (approval_stale_or_payload_changed): they fail
-- closed, the same way pre-0210 requests fail closed after 0210. Note: with the 0206 request body, a still-pending
-- BDT request for an unchanged draft blocks a second request (PROC_APPROVAL_ALREADY_REQUESTED) until the maker saves
-- the draft again (new version) or cancels it. Grants are unchanged (CREATE OR REPLACE keeps them).
-- Server-built payload: identical on submission and on approval. amount = the PO total (threshold-ready).
CREATE OR REPLACE FUNCTION core10._proc_po_approval_payload_v1(p_po bigint) RETURNS jsonb
LANGUAGE sql STABLE SET search_path=pg_catalog,core10 AS $$
 SELECT jsonb_build_object('po_id',p.id,'business_id',p.business_id,'site_id',p.site_id,'supplier_id',p.supplier_id,
  'amount',p.total_amount,'unit','currency_total','expected_on',p.expected_on,'version',p.version,
  'lines',coalesce((SELECT jsonb_agg(jsonb_build_object('line_no',l.line_no,'item_id',l.item_id,'quantity',l.quantity,
    'unit_price',l.unit_price) ORDER BY l.line_no) FROM core10.purchase_order_lines_v1 l WHERE l.po_id=p.id),'[]'::jsonb))
 FROM core10.purchase_orders_v1 p WHERE p.id=p_po
$$;

-- The maker asks for approval of a draft purchase order.
CREATE OR REPLACE FUNCTION core10.procurement_request_po_approval_v1(p_po bigint, p_key text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE v_actor uuid := core10.actor_uid(); pre core10.purchase_orders_v1%ROWTYPE; p core10.purchase_orders_v1%ROWTYPE;
 c jsonb; v_stages int; v_req bigint; v_old core10.approval_requests%ROWTYPE;
BEGIN
 IF v_actor IS NULL OR p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{8,100}$' THEN RAISE EXCEPTION 'PROC_INVALID_ACTION'; END IF;
 -- Authorize before locking an untrusted row; re-check after the lock.
 SELECT * INTO pre FROM core10.purchase_orders_v1 WHERE id=p_po;
 IF NOT FOUND OR NOT core10.can_see_business(pre.tenant_id,pre.business_id) THEN RAISE EXCEPTION 'PROC_SCOPE'; END IF;
 IF NOT core10.can_business(pre.tenant_id,pre.business_id) THEN RAISE EXCEPTION 'PROC_PERMISSION_DENIED'; END IF;
 SELECT * INTO p FROM core10.purchase_orders_v1 WHERE id=p_po FOR UPDATE;
 c := core10.control_check_v1(p.business_id, 'procurement.purchase_order', p.site_id);
 PERFORM core10.control_check_v1(p.business_id, 'gov002.review', NULL);
 IF NOT core10.can_manage(p.tenant_id,p.business_id) AND NOT (c->'params'->>'manager_may_create')::boolean
 THEN RAISE EXCEPTION 'PROC_PERMISSION_DENIED'; END IF;
 IF p.status<>'draft' THEN RAISE EXCEPTION 'PROC_INVALID_TRANSITION'; END IF;
 IF p.created_by<>v_actor THEN RAISE EXCEPTION 'PROC_APPROVAL_MAKER_DENIED'; END IF;
 v_stages := (c->>'stages')::int;
 IF coalesce(v_stages,0)<1 THEN RAISE EXCEPTION 'PROC_APPROVAL_STAGES_REQUIRED'; END IF;
 IF NOT coalesce(core10._proc_po_route_matches_v1(p.tenant_id,p.business_id,NULL,v_stages),false)
 THEN RAISE EXCEPTION 'PROC_APPROVAL_ROUTE_MISMATCH'; END IF;
 v_req := core10.submit_typed_approval_v1(p.business_id,'procurement','purchase_order','procurement:po:'||p.id,p.version,
  core10._proc_po_approval_payload_v1(p.id),p_key);
 -- A live request for the current version blocks a second one; a request bound to an earlier version of the
 -- draft can never become effective (binding check), so a fresh request for the edited draft is allowed.
 IF p.approval_request_id IS NOT NULL AND p.approval_request_id<>v_req THEN
  SELECT * INTO v_old FROM core10.approval_requests WHERE id=p.approval_request_id;
  IF v_old.status IN ('pending','approved') AND v_old.source_version_v1=p.version
  THEN RAISE EXCEPTION 'PROC_APPROVAL_ALREADY_REQUESTED'; END IF;
 END IF;
 IF p.approval_request_id IS DISTINCT FROM v_req THEN
  UPDATE core10.purchase_orders_v1 SET approval_request_id=v_req WHERE id=p.id;
 END IF;
 PERFORM core10._append_canonical_audit_v1(p.tenant_id,p.business_id,'procurement','po:'||p.id||':approval:'||v_req,
  'procurement.po_approval_requested',v_actor,'procurement-approval:'||p.business_id||':'||p_key,
  jsonb_build_object('po_id',p.id,'approval_request_id',v_req,'stages',v_stages,'po_version',p.version,
   'total_amount',p.total_amount));
 RETURN jsonb_build_object('po_id',p.id,'approval_request_id',v_req,'stages',v_stages,'version',p.version);
END $$;
