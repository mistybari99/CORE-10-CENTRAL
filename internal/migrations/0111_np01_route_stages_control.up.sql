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
