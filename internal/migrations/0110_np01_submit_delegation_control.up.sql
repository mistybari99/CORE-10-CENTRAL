-- NP01 / B-020 / 0110: canonical Control switch for typed submission and delegation.
-- The Control port and 0103 evidence registry are installed by 0100–0106.
-- Replace only three existing function bodies, preserve signatures and privileges.
-- Not a complete approval route/stages implementation; no posting or shadow engine.
CREATE OR REPLACE FUNCTION core10.submit_typed_approval_v1(
  p_business bigint, p_domain text, p_action text,
  p_source_key text, p_source_version bigint, p_payload jsonb, p_key text
) RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path = core10, pg_catalog AS $fn$
DECLARE
  v_tenant bigint;
  v_actor uuid := core10.actor_uid();
  v_policy core10.approval_policy_versions_v1%ROWTYPE;
  v_digest text;
  v_id bigint;
  v_old core10.approval_requests%ROWTYPE;
BEGIN
  IF v_actor IS NULL OR p_business IS NULL
    OR p_domain IS NULL OR p_domain !~ '^[a-z][a-z0-9_]{1,63}$'
    OR p_action IS NULL OR p_action !~ '^[a-z][a-z0-9_]{1,63}$'
    OR p_source_key IS NULL OR length(btrim(p_source_key)) NOT BETWEEN 1 AND 160
    OR p_source_version IS NULL OR p_source_version <= 0
    OR p_payload IS NULL OR jsonb_typeof(p_payload) <> 'object'
    OR p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{8,128}$'
  THEN RAISE EXCEPTION 'invalid_typed_approval_request'; END IF;

  SELECT tenant_id INTO v_tenant FROM core10.businesses WHERE id = p_business;
  IF NOT FOUND OR NOT core10.can_business(v_tenant, p_business)
  THEN RAISE EXCEPTION 'approval_submit_denied'; END IF;

  -- Control switch after canonical Auth and before replay, policy lookup or insert.
  -- The 0..5 stage count is NOT certified in this increment (B-020 route pending).
  PERFORM core10.control_check_v1(p_business, 'gov002.review', NULL);

  -- Normalize JSONB and compute SHA256 at the server; no client-supplied digest.
  v_digest := encode(sha256(convert_to(p_payload::text, 'UTF8')), 'hex');

  -- Replay is bound to the FIRST policy version even after Owner publishes a new one.
  SELECT * INTO v_old FROM core10.approval_requests
    WHERE business_id = p_business AND created_by = v_actor AND submit_key_v1 = p_key;
  IF FOUND THEN
    IF v_old.domain_v1 IS DISTINCT FROM p_domain
      OR v_old.action_code_v1 IS DISTINCT FROM p_action
      OR v_old.source_key_v1 IS DISTINCT FROM btrim(p_source_key)
      OR v_old.source_version_v1 IS DISTINCT FROM p_source_version
      OR v_old.payload_sha256_v1 IS DISTINCT FROM v_digest
    THEN RAISE EXCEPTION 'approval_submit_replay_conflict'; END IF;
    RETURN v_old.id;
  END IF;

  SELECT * INTO v_policy FROM core10.approval_policy_versions_v1
    WHERE tenant_id = v_tenant AND business_id = p_business
      AND domain = p_domain AND action_code = p_action
    ORDER BY version DESC LIMIT 1 FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'approval_policy_missing'; END IF;

  -- A versioned threshold cannot be skipped using the old general typed RPC.
  PERFORM core10.assert_approval_threshold_v1(v_policy.id,p_payload);

  INSERT INTO core10.approval_requests
    (tenant_id, business_id, created_by, domain_v1, action_code_v1,
     source_key_v1, source_version_v1, payload_sha256_v1,
     policy_id_v1, policy_version_v1, expires_at_v1, submit_key_v1)
  VALUES
    (v_tenant, p_business, v_actor, p_domain, p_action,
     btrim(p_source_key), p_source_version, v_digest,
     v_policy.id, v_policy.version,
     clock_timestamp() + make_interval(mins => v_policy.ttl_minutes), p_key)
  ON CONFLICT DO NOTHING RETURNING id INTO v_id;

  IF v_id IS NULL THEN
    SELECT * INTO v_old FROM core10.approval_requests
      WHERE business_id = p_business AND created_by = v_actor AND submit_key_v1 = p_key;
    IF NOT FOUND
      OR v_old.domain_v1 IS DISTINCT FROM p_domain
      OR v_old.action_code_v1 IS DISTINCT FROM p_action
      OR v_old.source_key_v1 IS DISTINCT FROM btrim(p_source_key)
      OR v_old.source_version_v1 IS DISTINCT FROM p_source_version
      OR v_old.payload_sha256_v1 IS DISTINCT FROM v_digest
    THEN RAISE EXCEPTION 'approval_submit_replay_conflict'; END IF;
    v_id := v_old.id;
  END IF;
  RETURN v_id;
END $fn$;

CREATE OR REPLACE FUNCTION core10.delegate_approval_stage_v1(
 p_request bigint,p_delegate uuid,p_minutes integer,p_key text
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,core10 AS $fn$
DECLARE q core10.approval_requests%ROWTYPE;d core10.approval_delegations_v1%ROWTYPE;
 actor uuid:=core10.actor_uid();event_id bigint;until_at timestamptz;
BEGIN
 IF actor IS NULL OR p_request IS NULL OR p_delegate IS NULL
  OR p_minutes IS NULL OR p_minutes NOT BETWEEN 5 AND 1440
  OR p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{8,128}$'
 THEN RAISE EXCEPTION 'invalid_approval_delegation'; END IF;
 SELECT * INTO q FROM core10.approval_requests WHERE id=p_request FOR UPDATE;
 IF NOT FOUND OR q.status<>'pending' OR q.policy_id_v1 IS NULL OR
    q.expires_at_v1<=clock_timestamp()
 THEN RAISE EXCEPTION 'approval_delegation_denied'; END IF;
 IF NOT core10.can_approval_action_v1(q.tenant_id,q.business_id,'approval.delegate')
   OR NOT EXISTS(SELECT 1 FROM core10.business_members m
    WHERE m.tenant_id=q.tenant_id AND m.business_id=q.business_id
      AND m.user_id=actor AND m.role='business_owner' AND m.active
      AND (m.valid_until IS NULL OR m.valid_until>statement_timestamp()))
   OR p_delegate=q.created_by OR p_delegate=actor
   OR NOT EXISTS(SELECT 1 FROM core10.business_members m
    WHERE m.tenant_id=q.tenant_id AND m.business_id=q.business_id
      AND m.user_id=p_delegate AND m.role='manager' AND m.active
      AND (m.valid_until IS NULL OR m.valid_until>statement_timestamp()))
   OR NOT EXISTS(SELECT 1 FROM core10.approval_routes_v1 r
      WHERE r.policy_id=q.policy_id_v1 AND r.stages[1]='business_owner')
   OR EXISTS(SELECT 1 FROM core10.approval_stage_receipts_v1 WHERE request_id=p_request)
 THEN RAISE EXCEPTION 'approval_delegation_denied'; END IF;
 -- Control switch after role, delegation target and request scope Auth.
 -- Deny even idempotent delegation replay when the Owner switches review off.
 PERFORM core10.control_check_v1(q.business_id, 'gov002.review', NULL);
 SELECT * INTO d FROM core10.approval_delegations_v1
 WHERE request_id=p_request AND stage_no=1;
 IF FOUND THEN
  IF d.granted_by<>actor OR d.delegated_to<>p_delegate
     OR d.delegation_key<>p_key OR d.revoked_at IS NOT NULL
  THEN RAISE EXCEPTION 'approval_delegation_replay_conflict'; END IF;
  SELECT id INTO event_id FROM core10.approval_events
  WHERE request_id=p_request AND idempotency_key=p_key AND action='delegate';
  RETURN event_id;
 END IF;
 until_at:=LEAST(q.expires_at_v1,clock_timestamp()+make_interval(mins=>p_minutes));
 IF until_at<=clock_timestamp() THEN RAISE EXCEPTION 'approval_delegation_expired'; END IF;
 INSERT INTO core10.approval_delegations_v1(request_id,tenant_id,business_id,
  granted_by,delegated_to,delegation_key,valid_until)
 VALUES(p_request,q.tenant_id,q.business_id,actor,p_delegate,p_key,until_at);
 INSERT INTO core10.approval_events(request_id,tenant_id,business_id,actor_id,action,idempotency_key)
 VALUES(p_request,q.tenant_id,q.business_id,actor,'delegate',p_key) RETURNING id INTO event_id;
 RETURN event_id;
END $fn$;

CREATE OR REPLACE FUNCTION core10.revoke_approval_delegation_v1(
 p_request bigint,p_key text
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,core10 AS $fn$
DECLARE q core10.approval_requests%ROWTYPE;d core10.approval_delegations_v1%ROWTYPE;
 actor uuid:=core10.actor_uid();event_id bigint;
BEGIN
 IF actor IS NULL OR p_request IS NULL OR p_key IS NULL
    OR p_key !~ '^[A-Za-z0-9_-]{8,128}$'
 THEN RAISE EXCEPTION 'invalid_approval_revocation'; END IF;
 SELECT * INTO q FROM core10.approval_requests WHERE id=p_request FOR UPDATE;
 SELECT * INTO d FROM core10.approval_delegations_v1 WHERE request_id=p_request;
 IF q.id IS NULL OR d.id IS NULL OR
    NOT (d.granted_by=actor OR core10.can_tenant(q.tenant_id))
    OR NOT core10.can_approval_action_v1(q.tenant_id,q.business_id,'approval.delegate')
 THEN RAISE EXCEPTION 'approval_revocation_denied'; END IF;
 -- Canonical Auth before Owner Control, then before replay/revocation write.
 PERFORM core10.control_check_v1(q.business_id, 'gov002.review', NULL);
 SELECT id INTO event_id FROM core10.approval_events
 WHERE request_id=p_request AND idempotency_key=p_key AND actor_id=actor AND action='revoke';
 IF FOUND THEN RETURN event_id; END IF;
 IF d.revoked_at IS NOT NULL THEN RAISE EXCEPTION 'approval_delegation_already_revoked'; END IF;
 UPDATE core10.approval_delegations_v1
 SET revoked_at=clock_timestamp(),revoked_by=actor WHERE id=d.id;
 INSERT INTO core10.approval_events(request_id,tenant_id,business_id,actor_id,action,idempotency_key)
 VALUES(p_request,q.tenant_id,q.business_id,actor,'revoke',p_key) RETURNING id INTO event_id;
 RETURN event_id;
END $fn$;

-- Registry promotion happens in this NP01 post-0102 block, not in earlier 0013-0019.
-- The evidence script runs the disabled-feature negatives in disposable PG17 CI.
DO $np01$
DECLARE v_result text;
BEGIN
 FOR v_result IN
  SELECT core10._control_registry_promote_v1(rpc_name,
    'tests/migrations/np01-control-submit-delegation-e2e.sql')
  FROM (VALUES ('submit_typed_approval_v1'),
               ('delegate_approval_stage_v1'),
               ('revoke_approval_delegation_v1')) AS r(rpc_name)
 LOOP
  IF v_result <> 'enforced' THEN RAISE EXCEPTION 'NP01_0110_REGISTRY_NOT_ENFORCED:%',v_result; END IF;
 END LOOP;
END $np01$;
