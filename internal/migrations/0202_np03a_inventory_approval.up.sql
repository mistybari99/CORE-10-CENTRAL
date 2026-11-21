-- NP03A / B-012 (0202): GOV-002 approval adapter for stock commands (Claude, block 0200-0299).
-- Reuses the one canonical approval journal (0009-0019: policies, routes, stage receipts, decide_approval,
-- verify_approval_binding_v1) exactly as the reviewed Finance adapter does (PR #120, 0405). No second approval cycle.
-- Owner Control stages for the command's kind decide: 0 = post now; 1 = one checker (no route); 2-5 = the business's
-- configured route must have exactly that many stages and every stage receipt must exist. The maker (command creator)
-- requests; nobody approves their own request (GOV-002 refuses). The approval is bound to the command's frozen
-- payload and version; any later change of stages, route or payload makes posting fail closed.
DO $dep$ BEGIN
 IF to_regprocedure('core10.verify_approval_binding_v1(bigint,bigint,text,text,text,bigint,jsonb)') IS NULL
 OR to_regprocedure('core10.submit_typed_approval_v1(bigint,text,text,text,bigint,jsonb,text)') IS NULL
 OR to_regclass('core10.approval_routes_v1') IS NULL OR to_regclass('core10.approval_stage_receipts_v1') IS NULL
 OR to_regclass('core10.inventory_commands_v1') IS NULL
 THEN RAISE EXCEPTION 'INV_GOV002_CANONICAL_DEPENDENCY_NOT_CONNECTED'; END IF;
END $dep$;

ALTER TABLE core10.inventory_commands_v1 ADD COLUMN approval_request_id bigint REFERENCES core10.approval_requests(id);

-- Server-built payload: identical on submission and on posting.
CREATE FUNCTION core10._inventory_approval_payload_v1(c core10.inventory_commands_v1) RETURNS jsonb
LANGUAGE sql IMMUTABLE SET search_path=pg_catalog,core10 AS $$
 SELECT jsonb_build_object('command_id',c.id,'business_id',c.business_id,'kind',c.kind,'item_id',c.item_id,
  'amount',c.quantity,'unit','base_qty','source_location',c.source_location,'source_site_id',c.source_site_id,
  'destination_location',c.destination_location,'destination_site_id',c.destination_site_id,'reason',c.reason,
  'version',c.version)
$$;

CREATE FUNCTION core10._inventory_approval_action_v1(p_kind text) RETURNS text
LANGUAGE sql STABLE SET search_path=pg_catalog,core10 AS $$
 SELECT approval_action FROM core10.control_catalog_v1 WHERE feature_key=core10._inventory_kind_feature_v1(p_kind)
$$;

-- Route length must equal the Owner's stage count: no route = exactly 1 checker; a route = its stage count.
CREATE FUNCTION core10._inventory_route_matches_v1(p_tenant bigint, p_business bigint, p_action text, p_policy bigint,
 p_stages integer) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
 SELECT CASE WHEN r.stages IS NULL THEN p_stages=1 ELSE cardinality(r.stages)=p_stages END
 FROM (SELECT (SELECT rt.stages FROM core10.approval_routes_v1 rt
   WHERE rt.policy_id=coalesce(p_policy,(SELECT p.id FROM core10.approval_policy_versions_v1 p
     WHERE p.tenant_id=p_tenant AND p.business_id=p_business AND p.domain='inventory' AND p.action_code=p_action
     ORDER BY p.version DESC LIMIT 1)) AND rt.tenant_id=p_tenant AND rt.business_id=p_business) AS stages) r
$$;

-- The maker asks for approval of a confirmed command.
CREATE FUNCTION core10.inventory_request_approval_v1(p_command bigint, p_key text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE v_actor uuid := core10.actor_uid(); pre core10.inventory_commands_v1%ROWTYPE; c core10.inventory_commands_v1%ROWTYPE;
 v_sites bigint[]; v_master jsonb := '[]'; s bigint; ctl jsonb; v_action text; v_req bigint; v_old text;
BEGIN
 IF v_actor IS NULL OR p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{8,100}$' THEN RAISE EXCEPTION 'INV_INVALID_ACTION'; END IF;
 SELECT * INTO pre FROM core10.inventory_commands_v1 WHERE id=p_command;
 IF NOT FOUND OR NOT core10.can_see_business(pre.tenant_id,pre.business_id) THEN RAISE EXCEPTION 'INV_SCOPE'; END IF;
 IF NOT core10._inventory_may_act_v1(pre.tenant_id,pre.business_id,pre.source_location,pre.destination_location)
 THEN RAISE EXCEPTION 'INV_PERMISSION_DENIED'; END IF;
 SELECT * INTO c FROM core10.inventory_commands_v1 WHERE id=p_command FOR UPDATE;
 v_sites := array_remove(ARRAY[c.source_site_id, CASE WHEN c.destination_site_id IS DISTINCT FROM c.source_site_id
  THEN c.destination_site_id END], NULL);
 FOREACH s IN ARRAY v_sites LOOP
  v_master := v_master || jsonb_build_array(core10.control_check_v1(c.business_id, 'inventory.stock_event', s));
 END LOOP;
 ctl := core10._inventory_controls_v1(c.business_id, c.kind, v_sites, v_master);
 PERFORM core10.control_check_v1(c.business_id, 'gov002.review', NULL);
 IF NOT core10.can_manage(c.tenant_id,c.business_id) AND NOT (ctl->>'staff_allowed')::boolean THEN RAISE EXCEPTION 'INV_PERMISSION_DENIED'; END IF;
 IF c.status<>'confirmed' THEN RAISE EXCEPTION 'INV_CONFIRM_FIRST'; END IF;
 IF c.created_by<>v_actor THEN RAISE EXCEPTION 'INV_APPROVAL_MAKER_DENIED'; END IF;
 IF (ctl->>'stages')::int<1 THEN RAISE EXCEPTION 'INV_APPROVAL_STAGES_REQUIRED'; END IF;
 v_action := core10._inventory_approval_action_v1(c.kind);
 IF NOT coalesce(core10._inventory_route_matches_v1(c.tenant_id,c.business_id,v_action,NULL,(ctl->>'stages')::int),false)
 THEN RAISE EXCEPTION 'INV_APPROVAL_ROUTE_MISMATCH'; END IF;
 v_req := core10.submit_typed_approval_v1(c.business_id,'inventory',v_action,'inventory:command:'||c.id,c.version,
  core10._inventory_approval_payload_v1(c),p_key);
 IF c.approval_request_id IS NOT NULL AND c.approval_request_id<>v_req THEN
  SELECT status INTO v_old FROM core10.approval_requests WHERE id=c.approval_request_id;
  IF v_old IN ('pending','approved') THEN RAISE EXCEPTION 'INV_APPROVAL_ALREADY_REQUESTED'; END IF;
 END IF;
 IF c.approval_request_id IS DISTINCT FROM v_req THEN
  UPDATE core10.inventory_commands_v1 SET approval_request_id=v_req WHERE id=c.id;
 END IF;
 PERFORM core10._append_canonical_audit_v1(c.tenant_id,c.business_id,'inventory','command:'||c.id||':approval:'||v_req,
  'inventory.command_approval_requested',v_actor,'inventory:'||c.business_id||':'||p_key,
  jsonb_build_object('command_id',c.id,'approval_request_id',v_req,'stages',(ctl->>'stages')::int,'action',v_action));
 RETURN jsonb_build_object('command_id',c.id,'approval_request_id',v_req,'stages',(ctl->>'stages')::int);
END $$;

-- Replaces the 0201 fail-closed hook: posting with stages > 0 needs an effective, fully receipted GOV-002 approval
-- bound to this command's current payload and version.
CREATE OR REPLACE FUNCTION core10._inventory_approval_gate_v1(p_command bigint, p_stages integer) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE c core10.inventory_commands_v1%ROWTYPE; q core10.approval_requests%ROWTYPE; v_action text;
 v_count integer; v_final bigint; v_binding bigint; v_route text[];
BEGIN
 IF coalesce(p_stages,0)=0 THEN RETURN '{}'::jsonb; END IF;
 SELECT * INTO c FROM core10.inventory_commands_v1 WHERE id=p_command;
 IF c.approval_request_id IS NULL THEN RAISE EXCEPTION 'INV_APPROVAL_REQUIRED'; END IF;
 SELECT * INTO q FROM core10.approval_requests
  WHERE id=c.approval_request_id AND tenant_id=c.tenant_id AND business_id=c.business_id AND created_by=c.created_by FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'INV_APPROVAL_REQUEST_SCOPE'; END IF;
 IF q.status<>'approved' OR q.decided_by IS NULL OR q.decided_by=q.created_by THEN RAISE EXCEPTION 'INV_APPROVAL_NOT_EFFECTIVE'; END IF;
 v_action := core10._inventory_approval_action_v1(c.kind);
 SELECT stages INTO v_route FROM core10.approval_routes_v1
  WHERE policy_id=q.policy_id_v1 AND tenant_id=c.tenant_id AND business_id=c.business_id;
 IF (v_route IS NULL AND p_stages<>1) OR (v_route IS NOT NULL AND cardinality(v_route)<>p_stages)
 THEN RAISE EXCEPTION 'INV_APPROVAL_ROUTE_MISMATCH'; END IF;
 IF v_route IS NULL THEN
  SELECT count(*),max(id) INTO v_count,v_final FROM core10.approval_events
   WHERE request_id=q.id AND action='approve' AND actor_id<>q.created_by;
  IF v_count<>1 OR NOT EXISTS(SELECT 1 FROM core10.approval_events WHERE id=v_final AND actor_id=q.decided_by)
  THEN RAISE EXCEPTION 'INV_APPROVAL_RECEIPTS_INCOMPLETE'; END IF;
 ELSE
  SELECT count(*),max(event_id) FILTER (WHERE stage_no=p_stages) INTO v_count,v_final
   FROM core10.approval_stage_receipts_v1 WHERE request_id=q.id AND tenant_id=c.tenant_id AND business_id=c.business_id;
  IF v_count<>p_stages OR v_final IS NULL OR NOT EXISTS(SELECT 1 FROM core10.approval_events
    WHERE id=v_final AND request_id=q.id AND action='approve' AND actor_id=q.decided_by)
  THEN RAISE EXCEPTION 'INV_APPROVAL_RECEIPTS_INCOMPLETE'; END IF;
 END IF;
 v_binding := core10.verify_approval_binding_v1(q.id,c.business_id,'inventory',v_action,'inventory:command:'||c.id,c.version,
  core10._inventory_approval_payload_v1(c));
 RETURN jsonb_build_object('approval_request_id',q.id,'approval_policy_version',q.policy_version_v1,
  'approval_binding_event_id',v_binding,'approval_final_event_id',v_final,'approval_stage_count',p_stages);
END $$;

CREATE OR REPLACE FUNCTION core10._inventory_command_json_v1(c core10.inventory_commands_v1, p_replayed boolean) RETURNS jsonb
LANGUAGE sql IMMUTABLE SET search_path=pg_catalog,core10 AS $$
 SELECT jsonb_build_object('command_id',c.id,'business_id',c.business_id,'kind',c.kind,'status',c.status,
  'version',c.version,'item_id',c.item_id,'quantity',c.quantity,'source_location',c.source_location,
  'source_site_id',c.source_site_id,'destination_location',c.destination_location,
  'destination_site_id',c.destination_site_id,'reason',c.reason,'stock_ref',c.stock_ref,
  'created_by',c.created_by,'created_at',c.created_at,'confirmed_by',c.confirmed_by,'posted_by',c.posted_by,
  'posted_at',c.posted_at,'cancelled_by',c.cancelled_by,'approval_request_id',c.approval_request_id,'replayed',p_replayed)
$$;

REVOKE ALL ON FUNCTION core10._inventory_approval_payload_v1(core10.inventory_commands_v1),
 core10._inventory_approval_action_v1(text), core10._inventory_route_matches_v1(bigint,bigint,text,bigint,integer)
 FROM PUBLIC, authenticated;
REVOKE ALL ON FUNCTION core10.inventory_request_approval_v1(bigint,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION core10.inventory_request_approval_v1(bigint,text) TO authenticated;

INSERT INTO core10.control_rpc_map_v1(rpc_name,status,feature_key,reason,lane,board_row,test_ref) VALUES
 ('inventory_request_approval_v1','enforced','inventory.stock_event','Approval request for a stock command checks the stock master switch, the kind feature and gov002.review','Claude','B-012','tests/migrations/np03a-inventory-approval-e2e.sql');
