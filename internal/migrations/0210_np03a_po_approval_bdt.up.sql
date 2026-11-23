-- NP03A / B-012 (0210): purchase-order approval payload in BDT (Claude, block 0200-0299).
-- Owner decision 2026-11-23 (typed by the Owner in chat): the currency for purchase-order approval thresholds is BDT.
-- 0206 (hosted on staging, never edited) built the GOV-002 payload with unit 'currency_total'. GOV-002 thresholds
-- (0014 / 0114: approval_thresholds_v1.unit_code ~ '^[A-Z][A-Z0-9_]{1,11}$', assert_approval_threshold_v1 compares
-- payload.unit with unit_code exactly) can never be configured with that unit, so an Owner threshold on
-- procurement / purchase_order refused every request. This migration changes only what the payload builder returns:
--  * unit   = 'BDT' (one fixed currency by Owner decision; no business / PO currency column is invented),
--  * amount = purchase_orders_v1.total_amount as a JSON number with at most 2 decimals (the column is
--    numeric(20,2), cast explicitly). The GOV-002 precision rule is unchanged: an Owner threshold with
--    precision_scale 0 or 1 refuses a total that has more decimals (approval_threshold_precision_invalid).
-- Request and approve gate both call _proc_po_approval_payload_v1, so submission and verification stay identical.
-- Requests made before 0210 (unit 'currency_total') are bound to the old payload digest: the approve gate
-- (verify_approval_binding_v1) refuses them with approval_stale_or_payload_changed, i.e. they fail closed and never
-- approve a PO. So that such a stale request does not block the draft forever, procurement_request_po_approval_v1
-- now treats an earlier request as blocking only if its payload digest equals the current server payload; the maker
-- asks again and the fresh BDT request goes through the Owner threshold, route and stage checks as usual.
-- Everything else in the request function is the 0206 body unchanged. The gate (0206) and procurement_advance_po_v1
-- (0207) are not redefined: they already rebuild the payload through the replaced builder.
DO $dep$ BEGIN
 IF to_regprocedure('core10._proc_po_approval_payload_v1(bigint)') IS NULL
 OR to_regprocedure('core10._proc_po_approval_gate_v1(bigint,integer)') IS NULL
 OR to_regprocedure('core10.procurement_request_po_approval_v1(bigint,text)') IS NULL
 OR to_regprocedure('core10.assert_approval_threshold_v1(bigint,jsonb)') IS NULL
 OR to_regclass('core10.approval_thresholds_v1') IS NULL
 THEN RAISE EXCEPTION 'PROC_0210_DEPENDENCY_NOT_CONNECTED'; END IF;
END $dep$;

-- Server-built payload: identical on submission and on approval. amount = the PO total in BDT (threshold-ready).
CREATE OR REPLACE FUNCTION core10._proc_po_approval_payload_v1(p_po bigint) RETURNS jsonb
LANGUAGE sql STABLE SET search_path=pg_catalog,core10 AS $$
 SELECT jsonb_build_object('po_id',p.id,'business_id',p.business_id,'site_id',p.site_id,'supplier_id',p.supplier_id,
  'amount',p.total_amount::numeric(20,2),'unit','BDT','expected_on',p.expected_on,'version',p.version,
  'lines',coalesce((SELECT jsonb_agg(jsonb_build_object('line_no',l.line_no,'item_id',l.item_id,'quantity',l.quantity,
    'unit_price',l.unit_price) ORDER BY l.line_no) FROM core10.purchase_order_lines_v1 l WHERE l.po_id=p.id),'[]'::jsonb))
 FROM core10.purchase_orders_v1 p WHERE p.id=p_po
$$;

-- The maker asks for approval of a draft purchase order (0206 body; only the "already requested" rule changes).
CREATE OR REPLACE FUNCTION core10.procurement_request_po_approval_v1(p_po bigint, p_key text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE v_actor uuid := core10.actor_uid(); pre core10.purchase_orders_v1%ROWTYPE; p core10.purchase_orders_v1%ROWTYPE;
 c jsonb; v_stages int; v_req bigint; v_old core10.approval_requests%ROWTYPE; v_payload jsonb;
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
 v_payload := core10._proc_po_approval_payload_v1(p.id);
 v_req := core10.submit_typed_approval_v1(p.business_id,'procurement','purchase_order','procurement:po:'||p.id,p.version,
  v_payload,p_key);
 -- A live request for the current version AND the current server payload blocks a second one. A request bound to an
 -- earlier version, or to an earlier payload (a pre-0210 'currency_total' request), can never become effective
 -- (binding check), so a fresh request is allowed.
 IF p.approval_request_id IS NOT NULL AND p.approval_request_id<>v_req THEN
  SELECT * INTO v_old FROM core10.approval_requests WHERE id=p.approval_request_id;
  IF v_old.status IN ('pending','approved') AND v_old.source_version_v1=p.version
   AND v_old.payload_sha256_v1=encode(sha256(convert_to(v_payload::text,'UTF8')),'hex')
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

-- CREATE OR REPLACE keeps the 0206 grants; restate them so the contract is visible here.
REVOKE ALL ON FUNCTION core10._proc_po_approval_payload_v1(bigint) FROM PUBLIC, authenticated;
REVOKE ALL ON FUNCTION core10.procurement_request_po_approval_v1(bigint,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION core10.procurement_request_po_approval_v1(bigint,text) TO authenticated;

