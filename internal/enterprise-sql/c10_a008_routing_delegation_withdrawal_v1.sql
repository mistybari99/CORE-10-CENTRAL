-- CORE 10 GOV-002 A008: routed two-checker approval, bounded delegation, withdrawal.
-- DISPOSABLE c10_demo PG17 ONLY. Apply AFTER A018 seed + A008 prototype
-- + typed_approval_v1 + scoped_inbox_v1. NOT a production migration.
-- No operational posting, policy overrides, real auth certification or live SG writes.
-- One canonical request/event journal remains authoritative.
--
-- Scope of this additive slice: optional explicit two-step BUSINESS_OWNER ->
-- TENANT_OWNER route, one bounded stage-one delegation, and maker withdrawal.
-- Unrouted (legacy/demo) requests preserve the existing one-checker semantics.

ALTER TABLE c10_demo.approval_requests
  DROP CONSTRAINT approval_requests_status_check;
ALTER TABLE c10_demo.approval_requests
  ADD CONSTRAINT approval_requests_status_check
    CHECK (status IN ('pending','approved','rejected','deferred','withdrawn'));
ALTER TABLE c10_demo.approval_events
  DROP CONSTRAINT approval_events_action_check;
ALTER TABLE c10_demo.approval_events
  ADD CONSTRAINT approval_events_action_check
    CHECK (action IN ('approve','reject','defer','withdraw'));

-- Route cannot be edited after being attached to a published policy. Deliberately
-- supports only one safe two-step strategy pending threshold/risk policy work.
CREATE TABLE c10_demo.approval_routes_v1 (
  policy_id bigint PRIMARY KEY,
  tenant_id bigint NOT NULL,
  business_id bigint NOT NULL,
  stages text[] NOT NULL CHECK(stages = ARRAY['business_owner','tenant_owner']::text[]),
  configured_by uuid NOT NULL,
  route_key text NOT NULL CHECK(route_key ~ '^[A-Za-z0-9_-]{8,128}$'),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (business_id, route_key),
  FOREIGN KEY (policy_id,tenant_id,business_id)
    REFERENCES c10_demo.approval_policy_versions_v1(id,tenant_id,business_id)
);
ALTER TABLE c10_demo.approval_routes_v1 ENABLE ROW LEVEL SECURITY;
CREATE POLICY approval_routes_owner_read_v1 ON c10_demo.approval_routes_v1
  FOR SELECT TO authenticated
  USING (c10_demo.can_manage(tenant_id,business_id));
REVOKE ALL ON c10_demo.approval_routes_v1 FROM PUBLIC,anon,authenticated;
GRANT SELECT ON c10_demo.approval_routes_v1 TO authenticated;

-- Approvers cannot reassign the maker identity or change route. A delegation
-- is one request + stage, time-bound (max 24h, never beyond request TTL);
-- every decision rechecks the grantor AND delegate's CURRENT memberships.
CREATE TABLE c10_demo.approval_delegations_v1 (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  request_id bigint NOT NULL REFERENCES c10_demo.approval_requests(id),
  tenant_id bigint NOT NULL,
  business_id bigint NOT NULL,
  stage_no integer NOT NULL CHECK(stage_no=1),
  granted_by uuid NOT NULL,
  delegated_to uuid NOT NULL,
  delegation_key text NOT NULL CHECK(delegation_key ~ '^[A-Za-z0-9_-]{8,128}$'),
  requested_minutes integer NOT NULL CHECK(requested_minutes BETWEEN 5 AND 1440),
  valid_until timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  revoked_by uuid,
  revoked_at timestamptz,
  CHECK(granted_by <> delegated_to),
  CHECK((revoked_by IS NULL) = (revoked_at IS NULL)),
  UNIQUE(request_id,stage_no),
  UNIQUE(request_id,delegation_key)
);
CREATE INDEX approval_delegations_delegate_idx_v1 ON c10_demo.approval_delegations_v1
  (delegated_to,request_id) WHERE revoked_at IS NULL;
ALTER TABLE c10_demo.approval_delegations_v1 ENABLE ROW LEVEL SECURITY;
CREATE POLICY approval_delegate_read_v1 ON c10_demo.approval_delegations_v1
  FOR SELECT TO authenticated USING (
    c10_demo.can_manage(tenant_id,business_id)
    OR (delegated_to = c10_demo.actor_uid()
        AND c10_demo.can_business(tenant_id,business_id))
  );
REVOKE ALL ON c10_demo.approval_delegations_v1 FROM PUBLIC,anon,authenticated;
GRANT SELECT ON c10_demo.approval_delegations_v1 TO authenticated;

-- Append-only grant/revoke audit. The mutable revoked_at flag is only current
-- enforcement state; this journal proves WHO granted/revoked and WHEN.
CREATE TABLE c10_demo.approval_delegation_events_v1 (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  delegation_id bigint NOT NULL REFERENCES c10_demo.approval_delegations_v1(id),
  request_id bigint NOT NULL REFERENCES c10_demo.approval_requests(id),
  tenant_id bigint NOT NULL,
  business_id bigint NOT NULL,
  actor_id uuid NOT NULL,
  action text NOT NULL CHECK(action IN ('grant','revoke')),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(delegation_id,action)
);
ALTER TABLE c10_demo.approval_delegation_events_v1 ENABLE ROW LEVEL SECURITY;
CREATE POLICY approval_delegation_event_read_v1
 ON c10_demo.approval_delegation_events_v1 FOR SELECT TO authenticated USING (
   c10_demo.can_manage(tenant_id,business_id)
   OR EXISTS (
     SELECT 1 FROM c10_demo.approval_delegations_v1 d
      WHERE d.id=delegation_id AND d.delegated_to=c10_demo.actor_uid()
       AND c10_demo.can_business(d.tenant_id,d.business_id)
   )
 );
REVOKE ALL ON c10_demo.approval_delegation_events_v1 FROM PUBLIC,anon,authenticated;
GRANT SELECT ON c10_demo.approval_delegation_events_v1 TO authenticated;

-- Stage receipt is append-only, links to the canonical audit event, and
-- records actual actor versus grantor. No direct app writes to either table.
CREATE TABLE c10_demo.approval_stage_receipts_v1 (
  event_id bigint PRIMARY KEY REFERENCES c10_demo.approval_events(id),
  request_id bigint NOT NULL REFERENCES c10_demo.approval_requests(id),
  tenant_id bigint NOT NULL,
  business_id bigint NOT NULL,
  stage_no integer NOT NULL CHECK(stage_no IN (1,2)),
  actor_id uuid NOT NULL,
  delegated_by uuid,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(request_id,stage_no)
);
ALTER TABLE c10_demo.approval_stage_receipts_v1 ENABLE ROW LEVEL SECURITY;
CREATE POLICY approval_stage_receipt_read_v1
  ON c10_demo.approval_stage_receipts_v1 FOR SELECT TO authenticated
  USING (
    c10_demo.can_manage(tenant_id,business_id)
    OR EXISTS (
      SELECT 1 FROM c10_demo.approval_requests q
       WHERE q.id=request_id AND q.tenant_id=approval_stage_receipts_v1.tenant_id
         AND q.business_id=approval_stage_receipts_v1.business_id
         AND q.created_by=c10_demo.actor_uid()
         AND c10_demo.can_business(q.tenant_id,q.business_id)
    )
  );
REVOKE ALL ON c10_demo.approval_stage_receipts_v1 FROM PUBLIC,anon,authenticated;
GRANT SELECT ON c10_demo.approval_stage_receipts_v1 TO authenticated;

CREATE FUNCTION c10_demo.configure_approval_route_v1(
  p_policy bigint, p_key text
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path=c10_demo,pg_catalog AS $fn$
DECLARE v_policy c10_demo.approval_policy_versions_v1%ROWTYPE;
        v_prev c10_demo.approval_routes_v1%ROWTYPE;
        v_actor uuid := c10_demo.actor_uid();
BEGIN
 IF v_actor IS NULL OR p_policy IS NULL OR p_key IS NULL
   OR p_key !~ '^[A-Za-z0-9_-]{8,128}$'
 THEN RAISE EXCEPTION 'invalid_approval_route'; END IF;
 -- Row lock serializes route setup and FK-backed request creation.
 SELECT * INTO v_policy FROM c10_demo.approval_policy_versions_v1
  WHERE id=p_policy FOR UPDATE;
 IF NOT FOUND OR NOT c10_demo.can_manage(v_policy.tenant_id,v_policy.business_id)
 THEN RAISE EXCEPTION 'route_not_authorized'; END IF;
 SELECT * INTO v_prev FROM c10_demo.approval_routes_v1 WHERE policy_id=p_policy;
 IF FOUND THEN
   IF v_prev.route_key<>p_key OR v_prev.configured_by<>v_actor
   THEN RAISE EXCEPTION 'route_replay_conflict'; END IF;
   RETURN p_policy;
 END IF;
 IF EXISTS(SELECT 1 FROM c10_demo.approval_requests WHERE policy_id_v1=p_policy)
 THEN RAISE EXCEPTION 'route_already_in_use'; END IF;
 INSERT INTO c10_demo.approval_routes_v1
 (policy_id,tenant_id,business_id,stages,configured_by,route_key)
 VALUES(p_policy,v_policy.tenant_id,v_policy.business_id,
        ARRAY['business_owner','tenant_owner'],v_actor,p_key);
 RETURN p_policy;
END $fn$;

CREATE FUNCTION c10_demo.delegate_approval_stage_v1(
  p_request bigint, p_delegate uuid, p_minutes integer, p_key text
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path=c10_demo,pg_catalog AS $fn$
DECLARE v_req c10_demo.approval_requests%ROWTYPE;
        v_prev c10_demo.approval_delegations_v1%ROWTYPE;
        v_actor uuid := c10_demo.actor_uid();
        v_id bigint; v_until timestamptz;
BEGIN
 IF v_actor IS NULL OR p_request IS NULL OR p_delegate IS NULL
  OR p_minutes IS NULL OR p_minutes NOT BETWEEN 5 AND 1440
  OR p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{8,128}$'
 THEN RAISE EXCEPTION 'invalid_approval_delegation'; END IF;
 SELECT * INTO v_req FROM c10_demo.approval_requests WHERE id=p_request FOR UPDATE;
 IF NOT FOUND OR v_req.policy_id_v1 IS NULL
  OR NOT EXISTS(SELECT 1 FROM c10_demo.approval_routes_v1
                 WHERE policy_id=v_req.policy_id_v1)
  OR NOT EXISTS (
    SELECT 1 FROM c10_demo.business_members m
     WHERE m.user_id=v_actor AND m.tenant_id=v_req.tenant_id
       AND m.business_id=v_req.business_id AND m.role='business_owner' AND m.active
  )
 THEN RAISE EXCEPTION 'delegation_not_authorized'; END IF;
 IF v_req.status<>'pending' OR v_req.expires_at_v1<=clock_timestamp()
    OR v_req.created_by=v_actor
    OR EXISTS(SELECT 1 FROM c10_demo.approval_events e
              WHERE e.request_id=p_request AND e.action='approve')
 THEN RAISE EXCEPTION 'delegation_invalid_stage'; END IF;
 IF p_delegate=v_req.created_by OR p_delegate=v_actor OR NOT EXISTS(
    SELECT 1 FROM c10_demo.business_members m
     WHERE m.user_id=p_delegate AND m.tenant_id=v_req.tenant_id
       AND m.business_id=v_req.business_id AND m.role='manager' AND m.active
 )
 THEN RAISE EXCEPTION 'delegation_target_denied'; END IF;
 SELECT * INTO v_prev FROM c10_demo.approval_delegations_v1
  WHERE request_id=p_request AND stage_no=1;
 IF FOUND THEN
   IF v_prev.delegation_key<>p_key OR v_prev.granted_by<>v_actor
      OR v_prev.delegated_to<>p_delegate OR v_prev.requested_minutes<>p_minutes
   THEN RAISE EXCEPTION 'delegation_replay_conflict'; END IF;
   RETURN v_prev.id;
 END IF;
 v_until := LEAST(clock_timestamp()+make_interval(mins=>p_minutes),
                  v_req.expires_at_v1);
 IF v_until<=clock_timestamp() THEN RAISE EXCEPTION 'delegation_invalid_expiry'; END IF;
 INSERT INTO c10_demo.approval_delegations_v1
 (request_id,tenant_id,business_id,stage_no,granted_by,delegated_to,
  delegation_key,requested_minutes,valid_until)
 VALUES(p_request,v_req.tenant_id,v_req.business_id,1,v_actor,p_delegate,
        p_key,p_minutes,v_until) RETURNING id INTO v_id;
 INSERT INTO c10_demo.approval_delegation_events_v1
  (delegation_id,request_id,tenant_id,business_id,actor_id,action)
 VALUES(v_id,p_request,v_req.tenant_id,v_req.business_id,v_actor,'grant');
 RETURN v_id;
END $fn$;

CREATE FUNCTION c10_demo.revoke_approval_delegation_v1(
 p_request bigint
) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER
SET search_path=c10_demo,pg_catalog AS $fn$
DECLARE v_req c10_demo.approval_requests%ROWTYPE;
        v_actor uuid := c10_demo.actor_uid();
BEGIN
 IF v_actor IS NULL OR p_request IS NULL
 THEN RAISE EXCEPTION 'invalid_approval_delegation'; END IF;
 SELECT * INTO v_req FROM c10_demo.approval_requests WHERE id=p_request FOR UPDATE;
 IF NOT FOUND OR NOT EXISTS (
    SELECT 1 FROM c10_demo.business_members m WHERE m.user_id=v_actor
     AND m.tenant_id=v_req.tenant_id AND m.business_id=v_req.business_id
     AND m.active AND m.role='business_owner')
 THEN RAISE EXCEPTION 'delegation_not_authorized'; END IF;
 UPDATE c10_demo.approval_delegations_v1
  SET revoked_at=clock_timestamp(),revoked_by=v_actor
  WHERE request_id=p_request AND revoked_at IS NULL;
 IF FOUND THEN
   INSERT INTO c10_demo.approval_delegation_events_v1
    (delegation_id,request_id,tenant_id,business_id,actor_id,action)
   SELECT d.id,d.request_id,d.tenant_id,d.business_id,v_actor,'revoke'
   FROM c10_demo.approval_delegations_v1 d WHERE d.request_id=p_request;
   RETURN true;
 END IF;
 RETURN false;
END $fn$;

-- The only transition API remains decide_approval. Route steps never write
-- 'approved' until BOTH independent votes finish in order. A delegated maker,
-- revoked grantor, expired substitute, repeated actor or mismatched stage fails.
CREATE OR REPLACE FUNCTION c10_demo.decide_approval(
 p_request bigint,p_action text,p_key text
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path=c10_demo,pg_catalog AS $fn$
DECLARE v_req c10_demo.approval_requests%ROWTYPE;
        v_actor uuid := c10_demo.actor_uid();
        v_prior c10_demo.approval_events%ROWTYPE;
        v_stages text[]; v_next integer;
        v_event bigint; v_delegator uuid; v_can boolean := false;
BEGIN
 IF v_actor IS NULL OR p_request IS NULL OR p_action IS NULL
  OR p_action NOT IN ('approve','reject','defer')
  OR p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{8,128}$'
 THEN RAISE EXCEPTION 'invalid_approval_command'; END IF;
 SELECT * INTO v_req FROM c10_demo.approval_requests
 WHERE id=p_request FOR UPDATE;
 IF NOT FOUND OR v_req.created_by=v_actor
 THEN RAISE EXCEPTION 'approval_not_authorized'; END IF;

 IF v_req.policy_id_v1 IS NOT NULL THEN
   IF NOT EXISTS(SELECT 1 FROM c10_demo.approval_policy_versions_v1 p
     WHERE p.id=v_req.policy_id_v1 AND p.tenant_id=v_req.tenant_id
       AND p.business_id=v_req.business_id AND p.version=v_req.policy_version_v1
       AND p.domain=v_req.domain_v1 AND p.action_code=v_req.action_code_v1)
   THEN RAISE EXCEPTION 'approval_policy_pin_invalid'; END IF;
 END IF;
 -- A retry of a completed vote must not be reinterpreted as the NEXT stage.
 -- It has no new side effect; nevertheless a removed member cannot query its
 -- old receipt through this SECURITY DEFINER entry point.
 SELECT * INTO v_prior FROM c10_demo.approval_events
  WHERE request_id=p_request AND idempotency_key=p_key;
 IF FOUND THEN
   IF v_prior.actor_id<>v_actor OR v_prior.action<>p_action
      OR v_prior.tenant_id<>v_req.tenant_id
      OR v_prior.business_id<>v_req.business_id
   THEN RAISE EXCEPTION 'approval_idempotency_conflict'; END IF;
   IF NOT c10_demo.can_business(v_req.tenant_id,v_req.business_id)
      AND NOT c10_demo.can_tenant(v_req.tenant_id)
   THEN RAISE EXCEPTION 'approval_not_authorized'; END IF;
   RETURN v_prior.id;
 END IF;
 SELECT stages INTO v_stages FROM c10_demo.approval_routes_v1
 WHERE policy_id=v_req.policy_id_v1;
 IF FOUND THEN
   SELECT count(*)+1 INTO v_next FROM c10_demo.approval_events e
    WHERE e.request_id=p_request AND e.action='approve';
   IF v_next>cardinality(v_stages)
   THEN RAISE EXCEPTION 'approval_invalid_transition'; END IF;
   IF EXISTS(SELECT 1 FROM c10_demo.approval_events e
       WHERE e.request_id=p_request AND e.actor_id=v_actor AND e.action='approve')
   THEN RAISE EXCEPTION 'approval_repeated_checker'; END IF;
   IF v_stages[v_next]='tenant_owner' THEN
      v_can := c10_demo.can_tenant(v_req.tenant_id);
   ELSIF v_stages[v_next]='business_owner' THEN
      -- Exact role, not the wider can_manage() owner-of-tenant shortcut.
      v_can := EXISTS(SELECT 1 FROM c10_demo.business_members owner
        WHERE owner.tenant_id=v_req.tenant_id
          AND owner.business_id=v_req.business_id
          AND owner.user_id=v_actor AND owner.role='business_owner'
          AND owner.active);
      IF NOT v_can THEN
        SELECT d.granted_by INTO v_delegator
        FROM c10_demo.approval_delegations_v1 d
        JOIN c10_demo.business_members manager
         ON manager.user_id=d.delegated_to AND manager.tenant_id=d.tenant_id
          AND manager.business_id=d.business_id AND manager.active
          AND manager.role='manager'
        JOIN c10_demo.business_members owner
         ON owner.user_id=d.granted_by AND owner.tenant_id=d.tenant_id
          AND owner.business_id=d.business_id AND owner.active
          AND owner.role='business_owner'
        WHERE d.request_id=p_request AND d.stage_no=1
         AND d.tenant_id=v_req.tenant_id AND d.business_id=v_req.business_id
         AND d.delegated_to=v_actor AND d.revoked_at IS NULL
         AND d.valid_until>clock_timestamp();
        v_can := FOUND;
      END IF;
   END IF;
 ELSE
   v_can := c10_demo.can_manage(v_req.tenant_id,v_req.business_id);
 END IF;
 IF NOT v_can THEN RAISE EXCEPTION 'approval_not_authorized'; END IF;

 SELECT * INTO v_prior FROM c10_demo.approval_events
  WHERE request_id=p_request AND idempotency_key=p_key;
 IF FOUND THEN
   IF v_prior.actor_id<>v_actor OR v_prior.action<>p_action
     OR v_prior.tenant_id<>v_req.tenant_id
     OR v_prior.business_id<>v_req.business_id
   THEN RAISE EXCEPTION 'approval_idempotency_conflict'; END IF;
   RETURN v_prior.id;
 END IF;
 IF v_req.status<>'pending' THEN RAISE EXCEPTION 'approval_invalid_transition'; END IF;
 IF v_req.policy_id_v1 IS NOT NULL AND v_req.expires_at_v1<=clock_timestamp()
 THEN RAISE EXCEPTION 'approval_expired'; END IF;

 IF v_stages IS NULL OR p_action<>'approve' OR v_next=cardinality(v_stages) THEN
   UPDATE c10_demo.approval_requests SET
    status=CASE p_action WHEN 'approve' THEN 'approved'
           WHEN 'reject' THEN 'rejected' ELSE 'deferred' END,
    decided_by=v_actor,decided_at=clock_timestamp()
   WHERE id=p_request AND status='pending';
   IF NOT FOUND THEN RAISE EXCEPTION 'approval_invalid_transition'; END IF;
 END IF;

 INSERT INTO c10_demo.approval_events
  (request_id,tenant_id,business_id,actor_id,action,idempotency_key)
 VALUES(p_request,v_req.tenant_id,v_req.business_id,v_actor,p_action,p_key)
 RETURNING id INTO v_event;

 IF v_stages IS NOT NULL AND p_action='approve' THEN
   INSERT INTO c10_demo.approval_stage_receipts_v1
    (event_id,request_id,tenant_id,business_id,stage_no,actor_id,delegated_by)
   VALUES(v_event,p_request,v_req.tenant_id,v_req.business_id,
      v_next,v_actor,v_delegator);
 END IF;
 RETURN v_event;
END $fn$;

CREATE FUNCTION c10_demo.withdraw_typed_approval_v1(
 p_request bigint,p_key text
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path=c10_demo,pg_catalog AS $fn$
DECLARE v_req c10_demo.approval_requests%ROWTYPE;
        v_prior c10_demo.approval_events%ROWTYPE;
        v_actor uuid := c10_demo.actor_uid();
        v_event bigint;
BEGIN
 IF v_actor IS NULL OR p_request IS NULL OR p_key IS NULL
  OR p_key !~ '^[A-Za-z0-9_-]{8,128}$'
 THEN RAISE EXCEPTION 'invalid_withdraw_request'; END IF;
 SELECT * INTO v_req FROM c10_demo.approval_requests WHERE id=p_request FOR UPDATE;
 IF NOT FOUND OR v_req.policy_id_v1 IS NULL OR v_req.created_by<>v_actor
  OR NOT c10_demo.can_business(v_req.tenant_id,v_req.business_id)
 THEN RAISE EXCEPTION 'withdraw_not_authorized'; END IF;
 SELECT * INTO v_prior FROM c10_demo.approval_events
   WHERE request_id=p_request AND idempotency_key=p_key;
 IF FOUND THEN
   IF v_prior.actor_id<>v_actor OR v_prior.action<>'withdraw'
   THEN RAISE EXCEPTION 'withdraw_replay_conflict'; END IF;
   RETURN v_prior.id;
 END IF;
 IF v_req.status<>'pending' THEN RAISE EXCEPTION 'withdraw_invalid_transition'; END IF;
 -- Withdrawal after an intermediate stage blocks final execution just as early
 -- withdrawal does. Original stage receipts remain immutable for audit.
 UPDATE c10_demo.approval_requests
  SET status='withdrawn',decided_by=v_actor,decided_at=clock_timestamp()
 WHERE id=p_request AND status='pending';
 INSERT INTO c10_demo.approval_events
   (request_id,tenant_id,business_id,actor_id,action,idempotency_key)
 VALUES(p_request,v_req.tenant_id,v_req.business_id,v_actor,'withdraw',p_key)
 RETURNING id INTO v_event;
 RETURN v_event;
END $fn$;

-- Default EXECUTE on new SECURITY DEFINER functions must be closed FIRST.
REVOKE ALL ON FUNCTION c10_demo.configure_approval_route_v1(bigint,text)
  FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION c10_demo.delegate_approval_stage_v1(bigint,uuid,integer,text)
  FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION c10_demo.revoke_approval_delegation_v1(bigint)
  FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION c10_demo.withdraw_typed_approval_v1(bigint,text)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION c10_demo.configure_approval_route_v1(bigint,text)
  TO authenticated;
GRANT EXECUTE ON FUNCTION c10_demo.delegate_approval_stage_v1(bigint,uuid,integer,text)
  TO authenticated;
GRANT EXECUTE ON FUNCTION c10_demo.revoke_approval_delegation_v1(bigint)
  TO authenticated;
GRANT EXECUTE ON FUNCTION c10_demo.withdraw_typed_approval_v1(bigint,text)
  TO authenticated;
-- Existing decide_approval(bigint,text,text) authenticated grant persists.
