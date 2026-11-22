-- NP03A / B-012 (0206): GOV-002 approval adapter for purchase orders (Claude, block 0200-0299).
-- Replaces the 0203 fail-closed hook (PROC_APPROVAL_NOT_CONNECTED) with the one canonical approval journal
-- (0009-0019: policies, routes, stage receipts, decide_approval, verify_approval_binding_v1), exactly as the stock
-- adapter 0202 does. No second approval cycle, no second permission system.
-- Owner Control stages for procurement.purchase_order decide: 0 = approve now (0203 behaviour unchanged);
-- 1 = one checker (no route); 2-5 = the business's configured route must have exactly that many stages and every
-- stage receipt must exist. The maker (PO creator) requests while the PO is a draft; nobody approves their own
-- request (GOV-002 refuses). The approval is bound to a server-built frozen payload of the PO (lines, supplier,
-- site, total) and the PO version: editing the draft, or changing stages / route after the decision, makes the
-- approve step fail closed.
DO $dep$ BEGIN
 IF to_regprocedure('core10.verify_approval_binding_v1(bigint,bigint,text,text,text,bigint,jsonb)') IS NULL
 OR to_regprocedure('core10.submit_typed_approval_v1(bigint,text,text,text,bigint,jsonb,text)') IS NULL
 OR to_regclass('core10.approval_routes_v1') IS NULL OR to_regclass('core10.approval_stage_receipts_v1') IS NULL
 OR to_regclass('core10.purchase_orders_v1') IS NULL
 OR NOT EXISTS(SELECT 1 FROM core10.control_catalog_v1 WHERE feature_key='procurement.purchase_order'
   AND approval_domain='procurement' AND approval_action='purchase_order')
 THEN RAISE EXCEPTION 'PROC_GOV002_CANONICAL_DEPENDENCY_NOT_CONNECTED'; END IF;
END $dep$;

ALTER TABLE core10.purchase_orders_v1 ADD COLUMN approval_request_id bigint REFERENCES core10.approval_requests(id);

-- Server-built payload: identical on submission and on approval. amount = the PO total (threshold-ready).
CREATE FUNCTION core10._proc_po_approval_payload_v1(p_po bigint) RETURNS jsonb
LANGUAGE sql STABLE SET search_path=pg_catalog,core10 AS $$
 SELECT jsonb_build_object('po_id',p.id,'business_id',p.business_id,'site_id',p.site_id,'supplier_id',p.supplier_id,
  'amount',p.total_amount,'unit','currency_total','expected_on',p.expected_on,'version',p.version,
  'lines',coalesce((SELECT jsonb_agg(jsonb_build_object('line_no',l.line_no,'item_id',l.item_id,'quantity',l.quantity,
    'unit_price',l.unit_price) ORDER BY l.line_no) FROM core10.purchase_order_lines_v1 l WHERE l.po_id=p.id),'[]'::jsonb))
 FROM core10.purchase_orders_v1 p WHERE p.id=p_po
$$;

-- Route length must equal the Owner's stage count: no route = exactly 1 checker; a route = its stage count.
CREATE FUNCTION core10._proc_po_route_matches_v1(p_tenant bigint, p_business bigint, p_policy bigint, p_stages integer)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
 SELECT CASE WHEN r.stages IS NULL THEN p_stages=1 ELSE cardinality(r.stages)=p_stages END
 FROM (SELECT (SELECT rt.stages FROM core10.approval_routes_v1 rt
   WHERE rt.policy_id=coalesce(p_policy,(SELECT p.id FROM core10.approval_policy_versions_v1 p
     WHERE p.tenant_id=p_tenant AND p.business_id=p_business AND p.domain='procurement' AND p.action_code='purchase_order'
     ORDER BY p.version DESC LIMIT 1)) AND rt.tenant_id=p_tenant AND rt.business_id=p_business) AS stages) r
$$;

-- The maker asks for approval of a draft purchase order.
CREATE FUNCTION core10.procurement_request_po_approval_v1(p_po bigint, p_key text) RETURNS jsonb
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

-- Approve with stages > 0 needs an effective, fully receipted GOV-002 approval bound to this PO's current
-- payload and version.
CREATE FUNCTION core10._proc_po_approval_gate_v1(p_po bigint, p_stages integer) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE p core10.purchase_orders_v1%ROWTYPE; q core10.approval_requests%ROWTYPE;
 v_count integer; v_final bigint; v_binding bigint; v_route text[];
BEGIN
 IF coalesce(p_stages,0)=0 THEN RETURN '{}'::jsonb; END IF;
 SELECT * INTO p FROM core10.purchase_orders_v1 WHERE id=p_po;
 IF p.approval_request_id IS NULL THEN RAISE EXCEPTION 'PROC_APPROVAL_REQUIRED'; END IF;
 SELECT * INTO q FROM core10.approval_requests
  WHERE id=p.approval_request_id AND tenant_id=p.tenant_id AND business_id=p.business_id AND created_by=p.created_by FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'PROC_APPROVAL_REQUEST_SCOPE'; END IF;
 IF q.status<>'approved' OR q.decided_by IS NULL OR q.decided_by=q.created_by THEN RAISE EXCEPTION 'PROC_APPROVAL_NOT_EFFECTIVE'; END IF;
 SELECT stages INTO v_route FROM core10.approval_routes_v1
  WHERE policy_id=q.policy_id_v1 AND tenant_id=p.tenant_id AND business_id=p.business_id;
 IF (v_route IS NULL AND p_stages<>1) OR (v_route IS NOT NULL AND cardinality(v_route)<>p_stages)
 THEN RAISE EXCEPTION 'PROC_APPROVAL_ROUTE_MISMATCH'; END IF;
 IF v_route IS NULL THEN
  SELECT count(*),max(id) INTO v_count,v_final FROM core10.approval_events
   WHERE request_id=q.id AND action='approve' AND actor_id<>q.created_by;
  IF v_count<>1 OR NOT EXISTS(SELECT 1 FROM core10.approval_events WHERE id=v_final AND actor_id=q.decided_by)
  THEN RAISE EXCEPTION 'PROC_APPROVAL_RECEIPTS_INCOMPLETE'; END IF;
 ELSE
  SELECT count(*),max(event_id) FILTER (WHERE stage_no=p_stages) INTO v_count,v_final
   FROM core10.approval_stage_receipts_v1 WHERE request_id=q.id AND tenant_id=p.tenant_id AND business_id=p.business_id;
  IF v_count<>p_stages OR v_final IS NULL OR NOT EXISTS(SELECT 1 FROM core10.approval_events
    WHERE id=v_final AND request_id=q.id AND action='approve' AND actor_id=q.decided_by)
  THEN RAISE EXCEPTION 'PROC_APPROVAL_RECEIPTS_INCOMPLETE'; END IF;
 END IF;
 v_binding := core10.verify_approval_binding_v1(q.id,p.business_id,'procurement','purchase_order','procurement:po:'||p.id,
  p.version,core10._proc_po_approval_payload_v1(p.id));
 RETURN jsonb_build_object('approval_request_id',q.id,'approval_policy_version',q.policy_version_v1,
  'approval_binding_event_id',v_binding,'approval_final_event_id',v_final,'approval_stage_count',p_stages);
END $$;

-- approve (draft -> approved), cancel (draft/approved with no receipt -> cancelled), close (short-close an open PO).
-- Same as 0203 except: approve with stages > 0 goes through the GOV-002 gate instead of failing closed.
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

REVOKE ALL ON FUNCTION core10._proc_po_approval_payload_v1(bigint),
 core10._proc_po_route_matches_v1(bigint,bigint,bigint,integer), core10._proc_po_approval_gate_v1(bigint,integer)
 FROM PUBLIC, authenticated;
REVOKE ALL ON FUNCTION core10.procurement_request_po_approval_v1(bigint,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION core10.procurement_request_po_approval_v1(bigint,text) TO authenticated;

INSERT INTO core10.control_rpc_map_v1(rpc_name,status,feature_key,reason,lane,board_row,test_ref) VALUES
 ('procurement_request_po_approval_v1','enforced','procurement.purchase_order','PO approval request checks the purchase-order control, maker rule, stage/route match and gov002.review','Claude','B-012','tests/migrations/np03a-po-approval-e2e.sql');
