-- CORE10 baseline20 v1; ordered, lossless consolidation. Fresh empty schema only.
-- CORE10 BASELINE SOURCE 0110_np01_submit_delegation_control.up.sql SHA256 e0bffc49d8bd64f2b9ea7a5d0063132d5daf511b1c2462219ce0195db7441e93
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
INSERT INTO core10.schema_migrations(version,name,checksum) VALUES(110,'0110_np01_submit_delegation_control','e0bffc49d8bd64f2b9ea7a5d0063132d5daf511b1c2462219ce0195db7441e93');

-- CORE10 BASELINE SOURCE 0111_np01_route_stages_control.up.sql SHA256 b04275c829ae099cfb6e136c27e4f6840d848811475a91c4e1a80ed6be5ff2e7
-- NP01/B-020/0111: Version-pin GOV002 0-5 stage review, without changing 0110.
-- Existing 2/3/5 policies remain usable until Owner explicitly sets stages.
-- No domain posting; all feature controls checked after Auth and before replay.
ALTER TABLE core10.approval_routes_v1
 DROP CONSTRAINT approval_routes_v1_stages_check;
ALTER TABLE core10.approval_routes_v1
 ADD CONSTRAINT approval_routes_stages_0111_chk CHECK (cardinality(stages) BETWEEN 0 AND 5
  AND array_position(stages,NULL) IS NULL
  AND (
    cardinality(stages)=0
    OR (cardinality(stages)=1 AND stages[1]='tenant_owner')
    OR (cardinality(stages) BETWEEN 2 AND 5
       AND stages[1]='business_owner'
       AND stages[cardinality(stages)]='tenant_owner'
       AND stages <@ ARRAY['business_owner','manager','tenant_owner']::text[]
       AND NOT (stages[1:cardinality(stages)-1] && ARRAY['tenant_owner']::text[]))
  ));
ALTER TABLE core10.approval_routes_v1
 ADD COLUMN control_stage_count_v1 smallint CHECK(control_stage_count_v1 BETWEEN 0 AND 5),
 ADD COLUMN control_version_v1 integer CHECK(control_version_v1>=0),
 ADD COLUMN control_source_v1 text CHECK(control_source_v1 IN ('default','business','site'));
ALTER TABLE core10.approval_requests
 ADD COLUMN route_stages_pinned_v1 smallint CHECK(route_stages_pinned_v1 BETWEEN 0 AND 5),
 ADD COLUMN route_control_version_v1 integer CHECK(route_control_version_v1>=0),
 ADD COLUMN route_control_source_v1 text CHECK(route_control_source_v1 IN ('default','business','site'));

CREATE OR REPLACE FUNCTION core10.configure_approval_route_v1(
 p_policy bigint,p_stages text[],p_key text
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,core10 AS $fn$
DECLARE pol core10.approval_policy_versions_v1%ROWTYPE;
 old core10.approval_routes_v1%ROWTYPE;actor uuid:=core10.actor_uid();
 v_control jsonb;
BEGIN
 IF actor IS NULL OR p_policy IS NULL OR p_stages IS NULL
  OR cardinality(p_stages) NOT BETWEEN 0 AND 5
  OR array_position(p_stages,NULL) IS NOT NULL
  OR (cardinality(p_stages)=1 AND p_stages[1]<>'tenant_owner')
  OR (cardinality(p_stages)>=2 AND (
     p_stages[1]<>'business_owner'
     OR p_stages[cardinality(p_stages)]<>'tenant_owner'
     OR NOT p_stages <@ ARRAY['business_owner','manager','tenant_owner']::text[]
     OR p_stages[1:cardinality(p_stages)-1] && ARRAY['tenant_owner']::text[]))
  OR p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{8,128}$'
 THEN RAISE EXCEPTION 'invalid_approval_route'; END IF;
 SELECT * INTO pol FROM core10.approval_policy_versions_v1 WHERE id=p_policy;
 IF NOT FOUND OR NOT core10.can_manage(pol.tenant_id,pol.business_id)
  OR NOT core10.can_approval_action_v1(pol.tenant_id,pol.business_id,'approval.decide')
 THEN RAISE EXCEPTION 'approval_route_denied'; END IF;
 -- Order every route writer and request submitter with the Owner setting writer.
 PERFORM pg_advisory_xact_lock(hashtextextended(
   'c10ctl:'||pol.business_id||':0:gov002.review',0));
 SELECT * INTO pol FROM core10.approval_policy_versions_v1 WHERE id=p_policy FOR UPDATE;
 -- Auth is established before Control; disabled must also deny a replay.
 v_control:=core10.control_check_v1(pol.business_id,'gov002.review',NULL);
 SELECT * INTO old FROM core10.approval_routes_v1 WHERE policy_id=p_policy;
 IF FOUND THEN
  IF old.configured_by<>actor OR old.stages<>p_stages OR old.route_key<>p_key
  THEN RAISE EXCEPTION 'approval_route_replay_conflict'; END IF;
  RETURN old.policy_id;
 END IF;
 -- The catalog default is not an explicit instruction to rewrite legacy
 -- 2/3/5-stage routes. 0/1 must be explicitly selected by an Owner.
 IF (v_control->>'source')='default' AND cardinality(p_stages)<2
 THEN RAISE EXCEPTION 'CONTROL_ROUTE_EXPLICIT_REQUIRED'; END IF;
 IF (v_control->>'source')<>'default'
   AND (v_control->>'stages')::integer<>cardinality(p_stages)
 THEN RAISE EXCEPTION 'CONTROL_STAGE_MISMATCH'; END IF;
 IF EXISTS(SELECT 1 FROM core10.approval_requests WHERE policy_id_v1=p_policy)
 THEN RAISE EXCEPTION 'approval_route_policy_in_use'; END IF;
 INSERT INTO core10.approval_routes_v1(policy_id,tenant_id,business_id,stages,configured_by,route_key,
   control_stage_count_v1,control_version_v1,control_source_v1)
 VALUES(p_policy,pol.tenant_id,pol.business_id,p_stages,actor,p_key,
   cardinality(p_stages),(v_control->>'version')::integer,v_control->>'source');
 PERFORM core10._append_canonical_audit_v1(pol.tenant_id,pol.business_id,
  'approval_route',p_policy::text,'approval.route',actor,'route:'||p_policy::text,
  jsonb_build_object('policy_ref',p_policy::text,'stage_count',cardinality(p_stages)));
 RETURN p_policy;
END $fn$;

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
  v_control jsonb;
  v_route text[];
  v_stage_count smallint;
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

  -- Serialize against the Owner setting writer and route configuration.
  -- Authorize before checking the switch, and check before any replay/write.
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'c10ctl:'||p_business||':0:gov002.review',0));
  v_control:=core10.control_check_v1(p_business,'gov002.review',NULL);

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

  -- Pin the exact route and effective Control version when the request is created.
  -- Legacy default-only policies retain their immutable 2-5 stage routes, or
  -- their historical un-routed Owner review. Explicit settings must match
  -- the selected versioned route, including 0/1 stage cases.
  SELECT r.stages INTO v_route FROM core10.approval_routes_v1 r
    WHERE r.policy_id=v_policy.id AND r.tenant_id=v_tenant
      AND r.business_id=p_business;
  v_stage_count:=CASE WHEN v_route IS NULL THEN NULL ELSE cardinality(v_route) END;
  IF (v_control->>'source')<>'default'
    AND (v_stage_count IS NULL OR
         v_stage_count<>(v_control->>'stages')::integer)
  THEN RAISE EXCEPTION 'CONTROL_STAGE_MISMATCH'; END IF;

  -- A versioned threshold cannot be skipped using the old general typed RPC.
  PERFORM core10.assert_approval_threshold_v1(v_policy.id,p_payload);

  INSERT INTO core10.approval_requests
    (tenant_id, business_id, created_by, domain_v1, action_code_v1,
     source_key_v1, source_version_v1, payload_sha256_v1,
     policy_id_v1, policy_version_v1, expires_at_v1, submit_key_v1,
     route_stages_pinned_v1,route_control_version_v1,route_control_source_v1)
  VALUES
    (v_tenant, p_business, v_actor, p_domain, p_action,
     btrim(p_source_key), p_source_version, v_digest,
     v_policy.id, v_policy.version,
     clock_timestamp() + make_interval(mins => v_policy.ttl_minutes), p_key,
     v_stage_count,(v_control->>'version')::integer,v_control->>'source')
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
  ELSIF v_stage_count=0 THEN
    -- Explicit Owner 0-stage policy: non-posting approval.none receipt.
    -- There is no second checker by design; no domain stock/money write.
    UPDATE core10.approval_requests
      SET status='approved',decided_by=v_actor,decided_at=clock_timestamp()
      WHERE id=v_id AND status='pending';
    INSERT INTO core10.approval_events
      (request_id,tenant_id,business_id,actor_id,action,idempotency_key)
    VALUES(v_id,v_tenant,p_business,v_actor,'approve',
      'np01_auto_'||left(p_key,100));
  END IF;
  RETURN v_id;
END $fn$;

CREATE OR REPLACE FUNCTION core10.decide_approval(
 p_request bigint,p_action text,p_key text
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,core10 AS $fn$
DECLARE q core10.approval_requests%ROWTYPE;actor uuid:=core10.actor_uid();
 prior core10.approval_events%ROWTYPE;v_stages text[];n integer;
 eligible boolean:=false;v_delegator uuid;v_event bigint;
BEGIN
 IF actor IS NULL OR p_request IS NULL OR p_action NOT IN ('approve','reject','defer')
  OR p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{8,128}$'
 THEN RAISE EXCEPTION 'invalid_approval_command'; END IF;
 SELECT * INTO q FROM core10.approval_requests WHERE id=p_request FOR UPDATE;
 IF NOT FOUND OR q.created_by=actor THEN RAISE EXCEPTION 'approval_not_authorized'; END IF;
 IF NOT core10.can_approval_action_v1(q.tenant_id,q.business_id,'approval.decide')
 THEN RAISE EXCEPTION 'approval_not_authorized'; END IF;
 -- B-020: Owner switch checked after canonical Auth, before replay or mutation.
 PERFORM core10.control_check_v1(q.business_id,'gov002.review',NULL);
 SELECT * INTO prior FROM core10.approval_events
 WHERE request_id=p_request AND idempotency_key=p_key;
 IF FOUND THEN
  IF prior.actor_id<>actor OR prior.action<>p_action
    OR prior.tenant_id<>q.tenant_id OR prior.business_id<>q.business_id
  THEN RAISE EXCEPTION 'approval_idempotency_conflict'; END IF;
  IF NOT (core10.can_business(q.tenant_id,q.business_id) OR core10.can_tenant(q.tenant_id))
  THEN RAISE EXCEPTION 'approval_not_authorized'; END IF;
  RETURN prior.id;
 END IF;
 IF q.policy_id_v1 IS NOT NULL THEN
  IF NOT EXISTS(SELECT 1 FROM core10.approval_policy_versions_v1 pol
   WHERE pol.id=q.policy_id_v1 AND pol.tenant_id=q.tenant_id AND pol.business_id=q.business_id
    AND pol.version=q.policy_version_v1 AND pol.domain=q.domain_v1 AND pol.action_code=q.action_code_v1)
  THEN RAISE EXCEPTION 'approval_policy_pin_invalid'; END IF;
 END IF;
 SELECT stages INTO v_stages FROM core10.approval_routes_v1
 WHERE policy_id=q.policy_id_v1 AND tenant_id=q.tenant_id AND business_id=q.business_id;
 IF q.route_stages_pinned_v1 IS NOT NULL AND
   (v_stages IS NULL OR cardinality(v_stages) IS DISTINCT FROM q.route_stages_pinned_v1)
 THEN RAISE EXCEPTION 'approval_route_pin_invalid'; END IF;
 IF q.route_stages_pinned_v1=0 THEN RAISE EXCEPTION 'approval_invalid_transition'; END IF;
 IF v_stages IS NULL THEN
  eligible:=core10.can_manage(q.tenant_id,q.business_id);
 ELSE
  SELECT count(*)::integer+1 INTO n FROM core10.approval_stage_receipts_v1
   WHERE request_id=p_request;
  IF n>cardinality(v_stages) THEN RAISE EXCEPTION 'approval_invalid_transition'; END IF;
  IF EXISTS(SELECT 1 FROM core10.approval_stage_receipts_v1
   WHERE request_id=p_request AND actor_id=actor)
  THEN RAISE EXCEPTION 'approval_repeated_checker'; END IF;
  eligible:=core10._can_review_stage_v1(p_request,n);
  IF eligible AND n=1 AND v_stages[1]='business_owner' THEN
   SELECT d.granted_by INTO v_delegator FROM core10.approval_delegations_v1 d
   WHERE d.request_id=p_request AND d.delegated_to=actor
     AND d.revoked_at IS NULL AND d.valid_until>statement_timestamp();
  END IF;
 END IF;
 IF NOT eligible THEN RAISE EXCEPTION 'approval_not_authorized'; END IF;
 IF q.status<>'pending' THEN RAISE EXCEPTION 'approval_invalid_transition'; END IF;
 IF q.policy_id_v1 IS NOT NULL AND q.expires_at_v1<=clock_timestamp()
 THEN RAISE EXCEPTION 'approval_expired'; END IF;
 IF v_stages IS NULL OR p_action<>'approve' OR n=cardinality(v_stages) THEN
  UPDATE core10.approval_requests SET
   status=CASE p_action WHEN 'approve' THEN 'approved'
    WHEN 'reject' THEN 'rejected' ELSE 'deferred' END,
   decided_by=actor,decided_at=clock_timestamp()
  WHERE id=p_request AND status='pending';
 END IF;
 INSERT INTO core10.approval_events(request_id,tenant_id,business_id,
   actor_id,action,idempotency_key)
 VALUES(p_request,q.tenant_id,q.business_id,actor,p_action,p_key)
 RETURNING id INTO v_event;
 IF v_stages IS NOT NULL AND p_action='approve' THEN
  INSERT INTO core10.approval_stage_receipts_v1(event_id,request_id,tenant_id,business_id,
    stage_no,actor_id,delegated_by)
  VALUES(v_event,p_request,q.tenant_id,q.business_id,n,actor,v_delegator);
 END IF;
 RETURN v_event;
END $fn$;

-- Only the newly covered route RPC is promoted, with its own PG17 negatives.
DO $np01$
BEGIN
 IF core10._control_registry_promote_v1('configure_approval_route_v1',
  'tests/migrations/np01-control-route-stages-e2e.sql')<>'enforced'
 THEN RAISE EXCEPTION 'NP01_0111_ROUTE_REGISTRY_NOT_ENFORCED'; END IF;
END $np01$;
INSERT INTO core10.schema_migrations(version,name,checksum) VALUES(111,'0111_np01_route_stages_control','b04275c829ae099cfb6e136c27e4f6840d848811475a91c4e1a80ed6be5ff2e7');

-- CORE10 BASELINE SOURCE 0112_np01_site_provision_control.up.sql SHA256 624ab1f4093a4b51242e322c053262cd0ce92686d4c5001ab15b0af49abcadff
-- NP01/B-020/0112: real Owner Control on existing canonical site RPC.
CREATE OR REPLACE FUNCTION core10.build01_site_v1(p_business bigint,p_kind text,p_label text,p_request text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE site bigint; tenant bigint; actor uuid:=core10.actor_uid(); signature jsonb; previous record; event_id bigint; v_control jsonb;
BEGIN
 SELECT tenant_id INTO tenant FROM core10.businesses WHERE id=p_business;
 IF actor IS NULL OR tenant IS NULL OR NOT core10.can_manage(tenant,p_business) THEN RAISE EXCEPTION 'BUILD01_SITE_DENIED'; END IF;
 -- Serialize against Owner setting changes and concurrent site writers.
 PERFORM pg_advisory_xact_lock(hashtextextended('c10ctl:'||p_business||':0:setup001.provision',0));
 PERFORM 1 FROM core10.businesses WHERE id=p_business FOR UPDATE;
 IF NOT core10.can_manage(tenant,p_business) THEN RAISE EXCEPTION 'BUILD01_SITE_DENIED'; END IF;
 -- Canonical Auth before Control, Control before replay or writes.
 v_control:=core10.control_check_v1(p_business,'setup001.provision',NULL);
 signature:=jsonb_build_object('business',p_business,'kind',p_kind,'label',p_label,'request',p_request);
 SELECT * INTO previous FROM core10.access_change_events_v1 WHERE business_id=p_business AND request_key=p_request;
 IF FOUND THEN
  IF previous.input_signature<>signature OR previous.actor_uid<>actor OR previous.event_kind<>'setup.site' THEN RAISE EXCEPTION 'BUILD01_REQUEST_CONFLICT'; END IF;
  RETURN previous.after_state||jsonb_build_object('event_id',previous.id,'request_key',p_request);
 END IF;
 -- Limits affect new writes, not idempotent receipts when Owner lowers the cap.
 IF (SELECT count(*) FROM core10.sites s WHERE s.business_id=p_business AND s.tenant_id=tenant)
      >= (v_control->'params'->>'max_sites')::integer THEN
  RAISE EXCEPTION 'CONTROL_LIMIT:max_sites';
 END IF;
 site:=core10.provision_site(p_business,p_kind,p_label,p_request);
 INSERT INTO core10.access_change_events_v1(tenant_id,business_id,request_key,command,subject_uid,site_id,input_signature,before_state,after_state,actor_uid,event_kind)
 VALUES(tenant,p_business,p_request,'setup.site',actor,site,signature,'{}',jsonb_build_object('business_id',p_business,'site_id',site),actor,'setup.site') RETURNING id INTO event_id;
 RETURN jsonb_build_object('business_id',p_business,'site_id',site,'request_key',p_request,'event_id',event_id);
END $$;
DO $np01$
BEGIN
 IF core10._control_registry_promote_v1('build01_site_v1','tests/migrations/np01-control-site-provision-e2e.sql')<>'enforced'
 THEN RAISE EXCEPTION 'NP01_0112_REGISTRY_NOT_ENFORCED'; END IF;
END $np01$;
INSERT INTO core10.schema_migrations(version,name,checksum) VALUES(112,'0112_np01_site_provision_control','624ab1f4093a4b51242e322c053262cd0ce92686d4c5001ab15b0af49abcadff');

-- CORE10 BASELINE SOURCE 0113_np01_gov003_control.up.sql SHA256 4557027d8c43f855855914fc5ae92d39cf56d1ff25137b95cff04e238216b58c
-- NP01 / B-020 / 0113: canonical GOV003 Auth -> Owner Control, default-off audit review/export.
-- 0016 stays immutable. VOLATILE is required because a consumed Owner exception is audited.
-- Existing signatures, SECURITY DEFINER grants, tenanted canonical Audit and RLS are unchanged.
CREATE OR REPLACE FUNCTION core10.gov003_audit_readiness_v1(p_business bigint)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,core10 AS $fn$
DECLARE v_tenant bigint;v_chain jsonb;v_event_count bigint;v_request_count bigint;
 v_control jsonb;
BEGIN
 SELECT b.tenant_id INTO v_tenant FROM core10.businesses b WHERE b.id=p_business;
 IF core10.actor_uid() IS NULL OR v_tenant IS NULL
   OR NOT core10.can_manage(v_tenant,p_business)
 THEN RAISE EXCEPTION 'gov003_readiness_denied' USING ERRCODE='42501'; END IF;
 -- Acquire the same business feature lock as the Owner Control writer, after Auth.
 PERFORM pg_advisory_xact_lock(hashtextextended('c10ctl:'||p_business||':0:gov003.review_export',0));
 v_control:=core10.control_check_v1(p_business,'gov003.review_export',NULL);
 -- There is not yet a canonical Approval route for these read-only projections.
 IF (v_control->>'stages')::integer<>0 THEN
  RAISE EXCEPTION 'CONTROL_APPROVAL_REQUIRED:gov003.review_export';
 END IF;
 -- GOV003 only provides the existing canonical metadata projection, never raw PII.
 IF (v_control->'params'->>'metadata_only')::boolean IS DISTINCT FROM true THEN
  RAISE EXCEPTION 'CONTROL_METADATA_ONLY_REQUIRED:gov003.review_export';
 END IF;
 v_chain:=core10.verify_canonical_audit_v1(p_business);
 SELECT count(*) INTO v_event_count FROM core10.canonical_audit_events_v1 a
  WHERE a.tenant_id=v_tenant AND a.business_id=p_business;
 SELECT count(*) INTO v_request_count FROM core10.approval_requests q
  WHERE q.tenant_id=v_tenant AND q.business_id=p_business;
 RETURN jsonb_build_object(
  'contract','C10_GOV003_CANONICAL_READINESS_V1','business_id',p_business,
  'canonical_chain',v_chain,'canonical_event_count',v_event_count,
  'approval_request_count',v_request_count,
  'release_certified',false,'ready_for_production',false,
  'status',CASE WHEN v_chain->>'ok'='true' THEN 'INTEGRITY_CHECK_ONLY'
                ELSE 'INTEGRITY_REVIEW_REQUIRED' END,
  'missing_proof',jsonb_build_array('signed_staging_personas',
    'owner_control_binding','source_linked_operational_e2e',
    'deployment_probe','retention_review'));
END $fn$;

CREATE OR REPLACE FUNCTION core10.gov003_audit_risk_v1(p_business bigint,p_since timestamptz)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,core10 AS $fn$
DECLARE v_tenant bigint;v_chain jsonb;v_declined bigint;
 v_expired bigint;v_open_exceptions bigint;v_events bigint;
 v_control jsonb;
BEGIN
 SELECT b.tenant_id INTO v_tenant FROM core10.businesses b WHERE b.id=p_business;
 IF core10.actor_uid() IS NULL OR v_tenant IS NULL
    OR NOT core10.can_manage(v_tenant,p_business)
    OR p_since IS NULL OR p_since>statement_timestamp()
 THEN RAISE EXCEPTION 'gov003_risk_denied' USING ERRCODE='42501'; END IF;
 -- Acquire the same business feature lock as the Owner Control writer, after Auth.
 PERFORM pg_advisory_xact_lock(hashtextextended('c10ctl:'||p_business||':0:gov003.review_export',0));
 v_control:=core10.control_check_v1(p_business,'gov003.review_export',NULL);
 -- There is not yet a canonical Approval route for these read-only projections.
 IF (v_control->>'stages')::integer<>0 THEN
  RAISE EXCEPTION 'CONTROL_APPROVAL_REQUIRED:gov003.review_export';
 END IF;
 -- GOV003 only provides the existing canonical metadata projection, never raw PII.
 IF (v_control->'params'->>'metadata_only')::boolean IS DISTINCT FROM true THEN
  RAISE EXCEPTION 'CONTROL_METADATA_ONLY_REQUIRED:gov003.review_export';
 END IF;
 v_chain:=core10.verify_canonical_audit_v1(p_business);
 SELECT count(*) INTO v_events FROM core10.canonical_audit_events_v1 a
  WHERE a.tenant_id=v_tenant AND a.business_id=p_business AND a.event_at>=p_since;
 SELECT count(*) INTO v_declined FROM core10.approval_exception_escalations_v1 e
  WHERE e.tenant_id=v_tenant AND e.business_id=p_business AND e.status='declined'
   AND e.created_at>=p_since;
 SELECT count(*) INTO v_expired FROM core10.approval_requests q
  WHERE q.tenant_id=v_tenant AND q.business_id=p_business
   AND q.status='pending' AND q.expires_at_v1<statement_timestamp()
   AND q.created_at>=p_since;
 SELECT count(*) INTO v_open_exceptions FROM core10.approval_exception_escalations_v1 e
  WHERE e.tenant_id=v_tenant AND e.business_id=p_business AND e.status='pending'
   AND e.expires_at>statement_timestamp();
 RETURN jsonb_build_object('contract','C10_GOV003_SCOPED_RISK_V1',
  'business_id',p_business,'since',p_since,'event_count',v_events,
  'declined_exceptions',v_declined,'expired_pending_approvals',v_expired,
  'open_exceptions',v_open_exceptions,'chain_ok',v_chain->'ok',
  'advisory_only',true,'release_certified',false);
END $fn$;

CREATE OR REPLACE FUNCTION core10.gov003_audit_export_v1(
 p_business bigint,p_after_seq bigint DEFAULT 0,p_limit integer DEFAULT 100
) RETURNS TABLE(stream_seq bigint,source_domain text,source_ref text,
 action text,event_at timestamptz,payload_sha256 text,event_digest text)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,core10 AS $fn$
DECLARE v_tenant bigint;
 v_control jsonb;
BEGIN
 SELECT b.tenant_id INTO v_tenant FROM core10.businesses b WHERE b.id=p_business;
 IF core10.actor_uid() IS NULL OR v_tenant IS NULL
  OR NOT core10.can_manage(v_tenant,p_business)
  OR p_after_seq IS NULL OR p_after_seq<0
  OR p_limit IS NULL OR p_limit < 1
 THEN RAISE EXCEPTION 'gov003_export_denied' USING ERRCODE='42501'; END IF;
 -- Acquire the same business feature lock as the Owner Control writer, after Auth.
 PERFORM pg_advisory_xact_lock(hashtextextended('c10ctl:'||p_business||':0:gov003.review_export',0));
 v_control:=core10.control_check_v1(p_business,'gov003.review_export',NULL);
 -- There is not yet a canonical Approval route for these read-only projections.
 IF (v_control->>'stages')::integer<>0 THEN
  RAISE EXCEPTION 'CONTROL_APPROVAL_REQUIRED:gov003.review_export';
 END IF;
 -- GOV003 only provides the existing canonical metadata projection, never raw PII.
 IF (v_control->'params'->>'metadata_only')::boolean IS DISTINCT FROM true THEN
  RAISE EXCEPTION 'CONTROL_METADATA_ONLY_REQUIRED:gov003.review_export';
 END IF;
 IF p_limit>(v_control->'params'->>'max_rows')::integer THEN
  RAISE EXCEPTION 'CONTROL_LIMIT:max_rows';
 END IF;
 RETURN QUERY SELECT a.stream_seq,a.source_domain,a.source_ref,
    a.action,a.event_at,a.payload_sha256,a.event_digest
  FROM core10.canonical_audit_events_v1 a
  WHERE a.business_id=p_business AND a.tenant_id=v_tenant
    AND a.stream_seq>p_after_seq
  ORDER BY a.stream_seq LIMIT p_limit;
END $fn$;

-- The three formerly STABLE read RPCs become VOLATILE because Control can consume
-- an audited one-time override; register all three before the shared registry gate.
INSERT INTO core10.control_rpc_map_v1(rpc_name,status,feature_key,reason,lane,board_row)
 VALUES
 ('gov003_audit_readiness_v1','pending','gov003.review_export','Canonical GOV003 readiness pending proof','ChatGPT','B-020'),
 ('gov003_audit_risk_v1','pending','gov003.review_export','Canonical GOV003 risk pending proof','ChatGPT','B-020'),
 ('gov003_audit_export_v1','pending','gov003.review_export','Canonical metadata export pending proof','ChatGPT','B-020');
DO $np01$
DECLARE v_rpc text;
BEGIN
 FOREACH v_rpc IN ARRAY ARRAY[
 'gov003_audit_readiness_v1','gov003_audit_risk_v1','gov003_audit_export_v1'] LOOP
  IF core10._control_registry_promote_v1(v_rpc,'tests/migrations/np01-control-gov003-e2e.sql')<>'enforced'
  THEN RAISE EXCEPTION 'NP01_0113_REGISTRY_NOT_ENFORCED:%',v_rpc; END IF;
 END LOOP;
END $np01$;
INSERT INTO core10.schema_migrations(version,name,checksum) VALUES(113,'0113_np01_gov003_control','4557027d8c43f855855914fc5ae92d39cf56d1ff25137b95cff04e238216b58c');

-- CORE10 BASELINE SOURCE 0114_np01_gov002_threshold_exception_control.up.sql SHA256 257d15f378550b480f8698030fdd7d75b8da18c326fd89706330e95e6d8caa64
-- NP01 B-020 / 0114: GOV002 policy threshold assessment/configuration and review exception lifecycle.
-- 0014-0017 originals, immutable threshold/exception tables, approval request and canonical
-- audit triggers are untouched. Canonical Auth -> Owner Control -> idempotent replay -> write.
-- Cross-tenant requests are pre-authorized before protected row locks; locked scope revalidated.

CREATE OR REPLACE FUNCTION core10.assess_approval_threshold_v1(
 p_policy bigint,p_payload jsonb
) RETURNS text LANGUAGE plpgsql SECURITY DEFINER
SET search_path=core10,pg_catalog AS $fn$
DECLARE v_p core10.approval_policy_versions_v1%ROWTYPE;
        v_c core10.approval_thresholds_v1%ROWTYPE;
BEGIN
 SELECT * INTO v_p FROM core10.approval_policy_versions_v1 WHERE id=p_policy;
 IF NOT FOUND OR core10.actor_uid() IS NULL
  OR NOT core10.can_business(v_p.tenant_id,v_p.business_id)
 THEN RAISE EXCEPTION 'approval_assessment_denied'; END IF;
 PERFORM core10.control_check_v1(v_p.business_id,'gov002.approval_policy',NULL);
 SELECT * INTO v_c FROM core10.approval_thresholds_v1 WHERE policy_id=p_policy;
 IF NOT FOUND THEN RETURN 'UNCONFIGURED'; END IF;
 BEGIN
  PERFORM core10.assert_approval_threshold_v1(p_policy,p_payload);
  RETURN 'REVIEW_REQUIRED';
 EXCEPTION WHEN raise_exception THEN
   IF SQLERRM='approval_threshold_not_met' THEN RETURN 'BELOW_THRESHOLD'; END IF;
   RAISE;
 END;
END $fn$;

CREATE OR REPLACE FUNCTION core10.assess_current_approval_threshold_v1(
 p_business bigint,p_domain text,p_action text,p_payload jsonb
) RETURNS text LANGUAGE plpgsql SECURITY DEFINER
SET search_path=core10,pg_catalog AS $fn$
DECLARE v_tenant bigint;v_policy bigint;
        v_c core10.approval_thresholds_v1%ROWTYPE;
BEGIN
 SELECT tenant_id INTO v_tenant FROM core10.businesses WHERE id=p_business;
 IF NOT FOUND OR core10.actor_uid() IS NULL
  OR NOT core10.can_business(v_tenant,p_business)
 THEN RAISE EXCEPTION 'approval_assessment_denied'; END IF;
 PERFORM core10.control_check_v1(p_business,'gov002.approval_policy',NULL);
 SELECT id INTO v_policy FROM core10.approval_policy_versions_v1
  WHERE tenant_id=v_tenant AND business_id=p_business
    AND domain=p_domain AND action_code=p_action
  ORDER BY version DESC LIMIT 1;
 IF NOT FOUND THEN RAISE EXCEPTION 'approval_policy_missing'; END IF;
 -- Replicate the original assessment to avoid a *second* one-time Control override.
 SELECT * INTO v_c FROM core10.approval_thresholds_v1 WHERE policy_id=v_policy;
 IF NOT FOUND THEN RETURN 'UNCONFIGURED'; END IF;
 BEGIN
  PERFORM core10.assert_approval_threshold_v1(v_policy,p_payload);
  RETURN 'REVIEW_REQUIRED';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM='approval_threshold_not_met' THEN RETURN 'BELOW_THRESHOLD'; END IF;
  RAISE;
 END;
END $fn$;

CREATE OR REPLACE FUNCTION core10.configure_approval_threshold_v1(
 p_policy bigint,p_measure text,p_unit text,p_minimum numeric,p_precision integer,p_key text
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path=core10,pg_catalog AS $fn$
DECLARE v_p core10.approval_policy_versions_v1%ROWTYPE;
        v_prior core10.approval_thresholds_v1%ROWTYPE;
        v_actor uuid:=core10.actor_uid();
BEGIN
 IF v_actor IS NULL OR p_policy IS NULL
  OR p_measure NOT IN ('currency','quantity')
  OR p_unit IS NULL OR p_unit !~ '^[A-Z][A-Z0-9_]{1,11}$'
  OR p_minimum IS NULL OR p_minimum<=0 OR p_minimum>999999999999999999.999999
  OR p_precision IS NULL OR p_precision NOT BETWEEN 0 AND 6
  OR p_minimum<>trunc(p_minimum,p_precision)
  OR p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{8,128}$'
 THEN RAISE EXCEPTION 'invalid_approval_threshold'; END IF;
 -- Canonical Owner Auth must precede any foreign policy row lock.
 SELECT * INTO v_p FROM core10.approval_policy_versions_v1 WHERE id=p_policy;
 IF NOT FOUND OR NOT core10.can_manage(v_p.tenant_id,v_p.business_id)
 THEN RAISE EXCEPTION 'threshold_not_authorized'; END IF;
 -- Serialize Control-setting changes before the policy lock (submission uses Control -> policy).
 PERFORM pg_advisory_xact_lock(hashtextextended('c10ctl:'||v_p.business_id||':0:gov002.approval_policy',0));
 PERFORM core10.control_check_v1(v_p.business_id,'gov002.approval_policy',NULL);
 SELECT * INTO v_p FROM core10.approval_policy_versions_v1
  WHERE id=p_policy FOR UPDATE;
 IF NOT FOUND OR NOT core10.can_manage(v_p.tenant_id,v_p.business_id)
 THEN RAISE EXCEPTION 'threshold_not_authorized'; END IF;
 SELECT * INTO v_prior FROM core10.approval_thresholds_v1
  WHERE policy_id=p_policy;
 IF FOUND THEN
   IF v_prior.measure_type<>p_measure OR v_prior.unit_code<>p_unit
      OR v_prior.minimum_value<>p_minimum OR v_prior.precision_scale<>p_precision
      OR v_prior.request_key<>p_key
      OR v_prior.configured_by<>v_actor
   THEN RAISE EXCEPTION 'approval_threshold_replay_conflict'; END IF;
   RETURN p_policy;
 END IF;
 IF EXISTS(SELECT 1 FROM core10.approval_requests WHERE policy_id_v1=p_policy)
 THEN RAISE EXCEPTION 'approval_threshold_policy_in_use'; END IF;
 INSERT INTO core10.approval_thresholds_v1
  (policy_id,tenant_id,business_id,measure_type,unit_code,minimum_value,
   precision_scale,request_key,configured_by)
 VALUES(p_policy,v_p.tenant_id,v_p.business_id,p_measure,p_unit,p_minimum,
  p_precision,p_key,v_actor);
 PERFORM core10._append_canonical_audit_v1(v_p.tenant_id,v_p.business_id,
   'approval_threshold',p_policy::text,'approval.threshold',v_actor,
   'threshold:'||p_policy::text,
   jsonb_build_object('policy_ref',p_policy::text,'measure',p_measure,
    'unit',p_unit,'minimum',p_minimum,'precision',p_precision));
 RETURN p_policy;
END $fn$;

CREATE OR REPLACE FUNCTION core10.request_approval_exception_v1(
 p_request bigint,p_reason text,p_severity text,p_minutes integer,p_key text
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path=core10,pg_catalog AS $fn$
DECLARE v_request core10.approval_requests%ROWTYPE;
        v_old core10.approval_exception_escalations_v1%ROWTYPE;
        v_actor uuid:=core10.actor_uid();
        v_id bigint;v_at timestamptz:=clock_timestamp();v_control jsonb;
BEGIN
 IF v_actor IS NULL OR p_request IS NULL
  OR p_reason IS NULL OR length(btrim(p_reason)) NOT BETWEEN 12 AND 400
  OR p_severity IS NULL OR p_severity NOT IN ('normal','urgent')
  OR p_minutes IS NULL OR p_minutes NOT BETWEEN 1 AND 43200
  OR p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{8,128}$'
 THEN RAISE EXCEPTION 'invalid_exception_request'; END IF;
 -- Pre-authorize read before taking a protected Approval request lock.
 SELECT * INTO v_request FROM core10.approval_requests WHERE id=p_request;
 IF NOT FOUND OR v_request.policy_id_v1 IS NULL OR v_request.created_by<>v_actor
   OR NOT core10.can_business(v_request.tenant_id,v_request.business_id)
 THEN RAISE EXCEPTION 'exception_request_denied'; END IF;
 SELECT * INTO v_request FROM core10.approval_requests
  WHERE id=p_request FOR UPDATE;
 IF NOT FOUND OR v_request.policy_id_v1 IS NULL
   OR v_request.created_by<>v_actor
   OR NOT core10.can_business(v_request.tenant_id,v_request.business_id)
 THEN RAISE EXCEPTION 'exception_request_denied'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('c10ctl:'||v_request.business_id||':0:gov002.review',0));
 v_control:=core10.control_check_v1(v_request.business_id,'gov002.review',NULL);
 IF (v_control->'params'->>'exception_escalation')::boolean IS DISTINCT FROM true
 THEN RAISE EXCEPTION 'CONTROL_EXCEPTION_ESCALATION_DISABLED'; END IF;
 SELECT * INTO v_old FROM core10.approval_exception_escalations_v1
  WHERE request_id=p_request;
 IF FOUND THEN
  IF v_old.created_by<>v_actor OR v_old.request_key<>p_key
    OR v_old.reason<>btrim(p_reason) OR v_old.severity<>p_severity
    OR v_old.ttl_minutes<>p_minutes
    OR v_old.policy_id<>v_request.policy_id_v1
    OR v_old.source_version<>v_request.source_version_v1
    OR v_old.payload_sha256<>v_request.payload_sha256_v1
  THEN RAISE EXCEPTION 'exception_request_replay_conflict'; END IF;
  RETURN v_old.id;
 END IF;
 IF p_minutes > (SELECT ttl_minutes FROM core10.approval_policy_versions_v1
                    WHERE id=v_request.policy_id_v1) THEN
   RAISE EXCEPTION 'exception_ttl_exceeds_owner_policy';
 END IF;
 IF v_request.status<>'pending'
   OR v_request.expires_at_v1<=v_at
 THEN RAISE EXCEPTION 'exception_parent_not_pending'; END IF;
 INSERT INTO core10.approval_exception_escalations_v1
  (request_id,tenant_id,business_id,policy_id,source_version,
   payload_sha256,created_by,reason,severity,ttl_minutes,request_key,
   created_at,expires_at)
 VALUES(p_request,v_request.tenant_id,v_request.business_id,
  v_request.policy_id_v1,v_request.source_version_v1,
  v_request.payload_sha256_v1,v_actor,btrim(p_reason),p_severity,
  p_minutes,p_key,v_at,LEAST(v_request.expires_at_v1,
                                v_at+make_interval(mins=>p_minutes)))
 RETURNING id INTO v_id;
 INSERT INTO core10.approval_exception_events_v1
  (escalation_id,tenant_id,business_id,request_id,creator_id,actor_id,
   action,event_key)
 VALUES(v_id,v_request.tenant_id,v_request.business_id,p_request,
   v_actor,v_actor,'submitted',p_key);
 RETURN v_id;
END $fn$;

CREATE OR REPLACE FUNCTION core10.decide_approval_exception_v1(
 p_escalation bigint,p_action text,p_key text
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path=core10,pg_catalog AS $fn$
DECLARE v_e core10.approval_exception_escalations_v1%ROWTYPE;
        v_r core10.approval_requests%ROWTYPE;
        v_previous core10.approval_exception_events_v1%ROWTYPE;
        v_actor uuid:=core10.actor_uid();
        v_request_id bigint;v_event bigint;v_at timestamptz:=clock_timestamp();v_control jsonb;
BEGIN
 IF v_actor IS NULL OR p_escalation IS NULL
  OR p_action NOT IN ('acknowledged','declined')
  OR p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{8,128}$'
 THEN RAISE EXCEPTION 'invalid_exception_decision'; END IF;
 -- Read the escalation's immutable scope and authorize BEFORE locking its parent.
 SELECT * INTO v_e FROM core10.approval_exception_escalations_v1 WHERE id=p_escalation;
 IF NOT FOUND OR v_e.created_by=v_actor
   OR NOT core10.can_manage(v_e.tenant_id,v_e.business_id)
 THEN RAISE EXCEPTION 'exception_decision_denied'; END IF;
 v_request_id:=v_e.request_id;
 SELECT * INTO v_r FROM core10.approval_requests
  WHERE id=v_request_id FOR UPDATE;
 SELECT * INTO v_e FROM core10.approval_exception_escalations_v1
  WHERE id=p_escalation FOR UPDATE;
 IF NOT FOUND OR v_e.created_by=v_actor
   OR NOT core10.can_manage(v_e.tenant_id,v_e.business_id)
   OR v_e.tenant_id<>v_r.tenant_id OR v_e.business_id<>v_r.business_id
 THEN RAISE EXCEPTION 'exception_decision_denied'; END IF;
 -- Confirm parent/escalation scope and Auth after both locks, before Control.
 IF v_r.id IS NULL OR v_e.tenant_id IS DISTINCT FROM v_r.tenant_id
   OR v_e.business_id IS DISTINCT FROM v_r.business_id
 THEN RAISE EXCEPTION 'exception_decision_denied'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('c10ctl:'||v_e.business_id||':0:gov002.review',0));
 v_control:=core10.control_check_v1(v_e.business_id,'gov002.review',NULL);
 IF (v_control->'params'->>'exception_escalation')::boolean IS DISTINCT FROM true
 THEN RAISE EXCEPTION 'CONTROL_EXCEPTION_ESCALATION_DISABLED'; END IF;
 SELECT * INTO v_previous FROM core10.approval_exception_events_v1
  WHERE escalation_id=p_escalation AND event_key=p_key;
 IF FOUND THEN
  IF v_previous.actor_id<>v_actor OR v_previous.action<>p_action
  THEN RAISE EXCEPTION 'exception_decision_replay_conflict'; END IF;
  RETURN v_previous.id;
 END IF;
 IF v_e.status<>'pending' OR v_e.expires_at<=v_at
  OR v_r.status<>'pending' OR v_r.expires_at_v1<=v_at
  OR v_e.policy_id<>v_r.policy_id_v1
  OR v_e.source_version<>v_r.source_version_v1
  OR v_e.payload_sha256<>v_r.payload_sha256_v1
 THEN RAISE EXCEPTION 'exception_stale_or_final'; END IF;
 UPDATE core10.approval_exception_escalations_v1
 SET status=p_action,decided_by=v_actor,decided_at=v_at WHERE id=p_escalation;
 INSERT INTO core10.approval_exception_events_v1
   (escalation_id,tenant_id,business_id,request_id,creator_id,actor_id,
    action,event_key)
 VALUES(p_escalation,v_e.tenant_id,v_e.business_id,v_r.id,
   v_e.created_by,v_actor,p_action,p_key)
 RETURNING id INTO v_event;
 RETURN v_event;
END $fn$;

CREATE OR REPLACE FUNCTION core10.withdraw_approval_exception_v1(
 p_escalation bigint,p_key text
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path=core10,pg_catalog AS $fn$
DECLARE v_e core10.approval_exception_escalations_v1%ROWTYPE;
        v_r core10.approval_requests%ROWTYPE;
        v_previous core10.approval_exception_events_v1%ROWTYPE;
        v_actor uuid:=core10.actor_uid();
        v_request_id bigint;v_event bigint;v_control jsonb;
BEGIN
 IF v_actor IS NULL OR p_escalation IS NULL
  OR p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{8,128}$'
 THEN RAISE EXCEPTION 'invalid_exception_withdraw'; END IF;
 -- Read the escalation's immutable scope and authorize BEFORE locking its parent.
 SELECT * INTO v_e FROM core10.approval_exception_escalations_v1 WHERE id=p_escalation;
 IF NOT FOUND OR v_e.created_by<>v_actor
  OR NOT core10.can_business(v_e.tenant_id,v_e.business_id)
 THEN RAISE EXCEPTION 'exception_withdraw_denied'; END IF;
 v_request_id:=v_e.request_id;
 SELECT * INTO v_r FROM core10.approval_requests
  WHERE id=v_request_id FOR UPDATE;
 SELECT * INTO v_e FROM core10.approval_exception_escalations_v1
  WHERE id=p_escalation FOR UPDATE;
 IF NOT FOUND OR v_e.created_by<>v_actor
  OR NOT core10.can_business(v_e.tenant_id,v_e.business_id)
  OR v_e.request_id<>v_r.id
 THEN RAISE EXCEPTION 'exception_withdraw_denied'; END IF;
 -- Confirm parent/escalation scope and Auth after both locks, before Control.
 IF v_r.id IS NULL OR v_e.tenant_id IS DISTINCT FROM v_r.tenant_id
   OR v_e.business_id IS DISTINCT FROM v_r.business_id
 THEN RAISE EXCEPTION 'exception_withdraw_denied'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('c10ctl:'||v_e.business_id||':0:gov002.review',0));
 v_control:=core10.control_check_v1(v_e.business_id,'gov002.review',NULL);
 IF (v_control->'params'->>'exception_escalation')::boolean IS DISTINCT FROM true
 THEN RAISE EXCEPTION 'CONTROL_EXCEPTION_ESCALATION_DISABLED'; END IF;
 SELECT * INTO v_previous FROM core10.approval_exception_events_v1
  WHERE escalation_id=p_escalation AND event_key=p_key;
 IF FOUND THEN
  IF v_previous.actor_id<>v_actor OR v_previous.action<>'withdrawn'
  THEN RAISE EXCEPTION 'exception_withdraw_replay_conflict'; END IF;
  RETURN v_previous.id;
 END IF;
 IF v_e.status<>'pending'
 THEN RAISE EXCEPTION 'exception_stale_or_final'; END IF;
 UPDATE core10.approval_exception_escalations_v1
  SET status='withdrawn',decided_by=v_actor,decided_at=clock_timestamp()
 WHERE id=p_escalation;
 INSERT INTO core10.approval_exception_events_v1
  (escalation_id,tenant_id,business_id,request_id,creator_id,actor_id,
   action,event_key)
 VALUES(p_escalation,v_e.tenant_id,v_e.business_id,v_r.id,
 v_e.created_by,v_actor,'withdrawn',p_key)
 RETURNING id INTO v_event;
 RETURN v_event;
END $fn$;

-- All six were fenced by 0017. Regrant only after direct Control check and test registration.
INSERT INTO core10.control_rpc_map_v1(rpc_name,status,feature_key,reason,lane,board_row)
 VALUES ('assess_approval_threshold_v1','pending','gov002.approval_policy','B-020 0114 canonical GOV002 binding','ChatGPT','B-020'),
        ('assess_current_approval_threshold_v1','pending','gov002.approval_policy','B-020 0114 canonical GOV002 binding','ChatGPT','B-020'),
        ('configure_approval_threshold_v1','pending','gov002.approval_policy','B-020 0114 canonical GOV002 binding','ChatGPT','B-020'),
        ('request_approval_exception_v1','pending','gov002.review','B-020 0114 canonical GOV002 binding','ChatGPT','B-020'),
        ('decide_approval_exception_v1','pending','gov002.review','B-020 0114 canonical GOV002 binding','ChatGPT','B-020'),
        ('withdraw_approval_exception_v1','pending','gov002.review','B-020 0114 canonical GOV002 binding','ChatGPT','B-020');
DO $np01$
DECLARE r text;
BEGIN
 FOREACH r IN ARRAY ARRAY['assess_approval_threshold_v1','assess_current_approval_threshold_v1','configure_approval_threshold_v1','request_approval_exception_v1','decide_approval_exception_v1','withdraw_approval_exception_v1'] LOOP
  IF core10._control_registry_promote_v1(r,'tests/migrations/np01-control-threshold-exception-e2e.sql')<>'enforced'
  THEN RAISE EXCEPTION 'NP01_0114_CONTROL_REGISTRY_NOT_ENFORCED:%',r; END IF;
 END LOOP;
END $np01$;
GRANT EXECUTE ON FUNCTION
 core10.assess_approval_threshold_v1(bigint,jsonb),
 core10.assess_current_approval_threshold_v1(bigint,text,text,jsonb),
 core10.configure_approval_threshold_v1(bigint,text,text,numeric,integer,text),
 core10.request_approval_exception_v1(bigint,text,text,integer,text),
 core10.decide_approval_exception_v1(bigint,text,text),
 core10.withdraw_approval_exception_v1(bigint,text)
 TO authenticated;
INSERT INTO core10.schema_migrations(version,name,checksum) VALUES(114,'0114_np01_gov002_threshold_exception_control','257d15f378550b480f8698030fdd7d75b8da18c326fd89706330e95e6d8caa64');
