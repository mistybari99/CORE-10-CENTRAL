-- Restore 0010's decision API and original scoped grants exactly; no CASCADE.
DROP FUNCTION core10.my_routed_review_tasks_v1(bigint);
CREATE OR REPLACE FUNCTION core10.decide_approval(
  p_request bigint, p_action text, p_key text
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path = core10, pg_catalog AS $fn$
DECLARE
  v_req core10.approval_requests%ROWTYPE;
  v_actor uuid;
  v_event bigint;
  v_previous core10.approval_events%ROWTYPE;
BEGIN
  v_actor := core10.actor_uid();
  IF v_actor IS NULL OR p_request IS NULL
    OR p_action IS NULL OR p_action NOT IN ('approve','reject','defer')
    OR p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{8,128}$'
  THEN RAISE EXCEPTION 'invalid_approval_command'; END IF;

  SELECT * INTO v_req FROM core10.approval_requests
    WHERE id = p_request FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'approval_not_authorized'; END IF;
  IF NOT core10.can_manage(v_req.tenant_id, v_req.business_id)
    OR v_req.created_by = v_actor
  THEN RAISE EXCEPTION 'approval_not_authorized'; END IF;

  SELECT * INTO v_previous FROM core10.approval_events
    WHERE request_id = p_request AND idempotency_key = p_key;
  IF FOUND THEN
    IF v_previous.actor_id <> v_actor OR v_previous.action <> p_action
      OR v_previous.tenant_id <> v_req.tenant_id
      OR v_previous.business_id <> v_req.business_id
    THEN RAISE EXCEPTION 'approval_idempotency_conflict'; END IF;
    RETURN v_previous.id;
  END IF;

  IF v_req.status <> 'pending' THEN RAISE EXCEPTION 'approval_invalid_transition'; END IF;
  IF v_req.policy_id_v1 IS NOT NULL THEN
    IF v_req.expires_at_v1 <= clock_timestamp()
    THEN RAISE EXCEPTION 'approval_expired'; END IF;
    IF NOT EXISTS (
      SELECT 1 FROM core10.approval_policy_versions_v1 p
      WHERE p.id = v_req.policy_id_v1 AND p.tenant_id = v_req.tenant_id
        AND p.business_id = v_req.business_id
        AND p.version = v_req.policy_version_v1
        AND p.domain = v_req.domain_v1 AND p.action_code = v_req.action_code_v1
    ) THEN RAISE EXCEPTION 'approval_policy_pin_invalid'; END IF;
  END IF;

  UPDATE core10.approval_requests SET
    status = CASE p_action WHEN 'approve' THEN 'approved'
                           WHEN 'reject' THEN 'rejected' ELSE 'deferred' END,
    decided_by = v_actor, decided_at = clock_timestamp()
  WHERE id = p_request AND status = 'pending';
  IF NOT FOUND THEN RAISE EXCEPTION 'approval_invalid_transition'; END IF;

  INSERT INTO core10.approval_events
    (request_id, tenant_id, business_id, actor_id, action, idempotency_key)
  VALUES (p_request, v_req.tenant_id, v_req.business_id, v_actor, p_action, p_key)
  RETURNING id INTO v_event;
  RETURN v_event;
END $fn$;
DROP FUNCTION core10.withdraw_typed_approval_v1(bigint,text);
DROP FUNCTION core10.revoke_approval_delegation_v1(bigint,text);
DROP FUNCTION core10.delegate_approval_stage_v1(bigint,uuid,integer,text);
DROP FUNCTION core10.configure_approval_route_v1(bigint,text[],text);
DROP FUNCTION core10._can_review_stage_v1(bigint,integer);
DROP POLICY approval_delegation_owner_read_v1 ON core10.approval_delegations_v1;
DROP POLICY approval_stage_owner_or_maker_v1 ON core10.approval_stage_receipts_v1;
DROP POLICY approval_route_owner_read_v1 ON core10.approval_routes_v1;
DROP TABLE core10.approval_delegations_v1;
DROP TABLE core10.approval_stage_receipts_v1;
DROP TABLE core10.approval_routes_v1;
DROP POLICY approval_event_scoped_review_v1 ON core10.approval_events;
DROP POLICY approval_request_scoped_review_v1 ON core10.approval_requests;
CREATE POLICY approval_request_read ON core10.approval_requests FOR SELECT TO authenticated
 USING(core10.can_see_business(tenant_id,business_id));
CREATE POLICY approval_event_read ON core10.approval_events FOR SELECT TO authenticated
 USING(core10.can_see_business(tenant_id,business_id));
ALTER TABLE core10.approval_requests DROP CONSTRAINT approval_requests_status_check;
ALTER TABLE core10.approval_requests ADD CONSTRAINT approval_requests_status_check
 CHECK(status IN ('pending','approved','rejected','deferred'));
ALTER TABLE core10.approval_events DROP CONSTRAINT approval_events_action_check;
ALTER TABLE core10.approval_events ADD CONSTRAINT approval_events_action_check
 CHECK(action IN ('approve','reject','defer'));
