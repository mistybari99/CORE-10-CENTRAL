-- S1-c CHG-011: canonical GOV-002 routed review, delegation, withdrawal, reviewer inbox.
-- Source model: isolated GOV-002 PR #99 ancestry; rewritten against core10 + Build01 + Build02A.
-- NOT a domain/Stock/Money posting adapter. PG17 disposable test only; no Owner release GO.
ALTER TABLE core10.approval_requests DROP CONSTRAINT approval_requests_status_check;
ALTER TABLE core10.approval_requests ADD CONSTRAINT approval_requests_status_check
 CHECK(status IN ('pending','approved','rejected','deferred','withdrawn'));
ALTER TABLE core10.approval_events DROP CONSTRAINT approval_events_action_check;
ALTER TABLE core10.approval_events ADD CONSTRAINT approval_events_action_check
 CHECK(action IN ('approve','reject','defer','withdraw','delegate','revoke'));

-- Existing default RLS was business-readable. Harden to scoped reviewer vs maker.
DROP POLICY approval_request_read ON core10.approval_requests;
CREATE POLICY approval_request_scoped_review_v1 ON core10.approval_requests
 FOR SELECT TO authenticated USING (
 core10.can_manage(tenant_id,business_id)
 OR (created_by=core10.actor_uid() AND core10.can_business(tenant_id,business_id))
);
DROP POLICY approval_event_read ON core10.approval_events;
CREATE POLICY approval_event_scoped_review_v1 ON core10.approval_events
 FOR SELECT TO authenticated USING (
 core10.can_manage(tenant_id,business_id)
 OR EXISTS (SELECT 1 FROM core10.approval_requests q
  WHERE q.id=request_id AND q.created_by=core10.actor_uid()
   AND core10.can_business(q.tenant_id,q.business_id))
);

CREATE TABLE core10.approval_routes_v1 (
 policy_id bigint PRIMARY KEY,
 tenant_id bigint NOT NULL,
 business_id bigint NOT NULL,
 stages text[] NOT NULL CHECK(
  cardinality(stages) BETWEEN 2 AND 5
  AND stages[1]='business_owner'
  AND stages[cardinality(stages)]='tenant_owner'
  AND stages <@ ARRAY['business_owner','manager','tenant_owner']::text[]
  AND NOT (stages[1:cardinality(stages)-1] && ARRAY['tenant_owner']::text[])),
 configured_by uuid NOT NULL,
 route_key text NOT NULL CHECK(route_key ~ '^[A-Za-z0-9_-]{8,128}$'),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(business_id,route_key),
 FOREIGN KEY(policy_id,tenant_id,business_id)
   REFERENCES core10.approval_policy_versions_v1(id,tenant_id,business_id)
);
ALTER TABLE core10.approval_routes_v1 ENABLE ROW LEVEL SECURITY;
CREATE POLICY approval_route_owner_read_v1 ON core10.approval_routes_v1
 FOR SELECT TO authenticated USING(core10.can_manage(tenant_id,business_id));
REVOKE ALL ON core10.approval_routes_v1 FROM PUBLIC,authenticated;
GRANT SELECT ON core10.approval_routes_v1 TO authenticated;

CREATE TABLE core10.approval_stage_receipts_v1 (
 event_id bigint PRIMARY KEY REFERENCES core10.approval_events(id),
 request_id bigint NOT NULL REFERENCES core10.approval_requests(id),
 tenant_id bigint NOT NULL,
 business_id bigint NOT NULL,
 stage_no integer NOT NULL CHECK(stage_no BETWEEN 1 AND 5),
 actor_id uuid NOT NULL,
 delegated_by uuid,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(request_id,stage_no),
 UNIQUE(request_id,actor_id)
);
ALTER TABLE core10.approval_stage_receipts_v1 ENABLE ROW LEVEL SECURITY;
CREATE POLICY approval_stage_owner_or_maker_v1 ON core10.approval_stage_receipts_v1
 FOR SELECT TO authenticated USING (
 core10.can_manage(tenant_id,business_id)
 OR EXISTS(SELECT 1 FROM core10.approval_requests q
  WHERE q.id=request_id AND q.created_by=core10.actor_uid()
   AND core10.can_business(q.tenant_id,q.business_id)));
REVOKE ALL ON core10.approval_stage_receipts_v1 FROM PUBLIC,authenticated;
GRANT SELECT ON core10.approval_stage_receipts_v1 TO authenticated;

CREATE TABLE core10.approval_delegations_v1 (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 request_id bigint NOT NULL REFERENCES core10.approval_requests(id),
 tenant_id bigint NOT NULL,
 business_id bigint NOT NULL,
 stage_no integer NOT NULL DEFAULT 1 CHECK(stage_no=1),
 granted_by uuid NOT NULL,
 delegated_to uuid NOT NULL,
 delegation_key text NOT NULL CHECK(delegation_key ~ '^[A-Za-z0-9_-]{8,128}$'),
 valid_until timestamptz NOT NULL,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 revoked_by uuid,
 revoked_at timestamptz,
 CHECK(granted_by<>delegated_to),
 CHECK((revoked_by IS NULL)=(revoked_at IS NULL)),
 UNIQUE(request_id,stage_no),
 UNIQUE(request_id,delegation_key)
);
ALTER TABLE core10.approval_delegations_v1 ENABLE ROW LEVEL SECURITY;
CREATE POLICY approval_delegation_owner_read_v1 ON core10.approval_delegations_v1
 FOR SELECT TO authenticated USING(core10.can_manage(tenant_id,business_id));
REVOKE ALL ON core10.approval_delegations_v1 FROM PUBLIC,authenticated;
GRANT SELECT ON core10.approval_delegations_v1 TO authenticated;

-- Only a current, business-scoped role (or single bounded stage-one delegate)
-- may cast a decision at the current route stage. Never infer role from JWT metadata.
CREATE FUNCTION core10._can_review_stage_v1(p_request bigint,p_stage integer)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,core10 AS $fn$
DECLARE q core10.approval_requests%ROWTYPE;v_role text;
 actor uuid:=core10.actor_uid();
BEGIN
 SELECT * INTO q FROM core10.approval_requests WHERE id=p_request;
 IF NOT FOUND OR actor IS NULL OR q.created_by=actor OR q.status<>'pending'
  OR q.expires_at_v1<=statement_timestamp()
  OR NOT core10.can_approval_action_v1(q.tenant_id,q.business_id,'approval.decide')
 THEN RETURN false; END IF;
 SELECT r.stages[p_stage] INTO v_role FROM core10.approval_routes_v1 r
 WHERE r.policy_id=q.policy_id_v1 AND r.tenant_id=q.tenant_id
  AND r.business_id=q.business_id AND p_stage BETWEEN 1 AND cardinality(r.stages);
 IF v_role IS NULL THEN RETURN false; END IF;
 IF v_role='tenant_owner' THEN RETURN core10.can_tenant(q.tenant_id); END IF;
 IF EXISTS(SELECT 1 FROM core10.business_members m WHERE
   m.tenant_id=q.tenant_id AND m.business_id=q.business_id
   AND m.user_id=actor AND m.role=v_role AND m.active
   AND (m.valid_until IS NULL OR m.valid_until>statement_timestamp()))
 THEN RETURN true; END IF;
 IF p_stage=1 AND v_role='business_owner' AND EXISTS(
  SELECT 1 FROM core10.approval_delegations_v1 d
  JOIN core10.business_members recipient ON recipient.tenant_id=d.tenant_id
   AND recipient.business_id=d.business_id AND recipient.user_id=d.delegated_to
   AND recipient.role='manager' AND recipient.active
   AND (recipient.valid_until IS NULL OR recipient.valid_until>statement_timestamp())
  JOIN core10.business_members grantor ON grantor.tenant_id=d.tenant_id
   AND grantor.business_id=d.business_id AND grantor.user_id=d.granted_by
   AND grantor.role='business_owner' AND grantor.active
   AND (grantor.valid_until IS NULL OR grantor.valid_until>statement_timestamp())
  WHERE d.request_id=p_request AND d.stage_no=1 AND d.tenant_id=q.tenant_id
   AND d.business_id=q.business_id AND d.delegated_to=actor
   AND d.revoked_at IS NULL AND d.valid_until>statement_timestamp())
 THEN RETURN true; END IF;
 RETURN false;
END $fn$;
REVOKE EXECUTE ON FUNCTION core10._can_review_stage_v1(bigint,integer) FROM PUBLIC,authenticated;

CREATE FUNCTION core10.configure_approval_route_v1(
 p_policy bigint,p_stages text[],p_key text
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,core10 AS $fn$
DECLARE pol core10.approval_policy_versions_v1%ROWTYPE;
 old core10.approval_routes_v1%ROWTYPE;actor uuid:=core10.actor_uid();
BEGIN
 IF actor IS NULL OR p_policy IS NULL OR p_stages IS NULL
  OR cardinality(p_stages) NOT BETWEEN 2 AND 5
  OR array_position(p_stages,NULL) IS NOT NULL
  OR p_stages[1]<>'business_owner'
  OR p_stages[cardinality(p_stages)]<>'tenant_owner'
  OR NOT p_stages <@ ARRAY['business_owner','manager','tenant_owner']::text[]
  OR p_stages[1:cardinality(p_stages)-1] && ARRAY['tenant_owner']::text[]
  OR p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{8,128}$'
 THEN RAISE EXCEPTION 'invalid_approval_route'; END IF;
 SELECT * INTO pol FROM core10.approval_policy_versions_v1 WHERE id=p_policy FOR UPDATE;
 IF NOT FOUND OR NOT core10.can_manage(pol.tenant_id,pol.business_id)
  OR NOT core10.can_approval_action_v1(pol.tenant_id,pol.business_id,'approval.decide')
 THEN RAISE EXCEPTION 'approval_route_denied'; END IF;
 SELECT * INTO old FROM core10.approval_routes_v1 WHERE policy_id=p_policy;
 IF FOUND THEN
  IF old.configured_by<>actor OR old.stages<>p_stages OR old.route_key<>p_key
  THEN RAISE EXCEPTION 'approval_route_replay_conflict'; END IF;
  RETURN old.policy_id;
 END IF;
 IF EXISTS(SELECT 1 FROM core10.approval_requests WHERE policy_id_v1=p_policy)
 THEN RAISE EXCEPTION 'approval_route_policy_in_use'; END IF;
 INSERT INTO core10.approval_routes_v1(policy_id,tenant_id,business_id,stages,configured_by,route_key)
 VALUES(p_policy,pol.tenant_id,pol.business_id,p_stages,actor,p_key);
 PERFORM core10._append_canonical_audit_v1(pol.tenant_id,pol.business_id,
  'approval_route',p_policy::text,'approval.route',actor,'route:'||p_policy::text,
  jsonb_build_object('policy_ref',p_policy::text,'stage_count',cardinality(p_stages)));
 RETURN p_policy;
END $fn$;

CREATE FUNCTION core10.delegate_approval_stage_v1(
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

CREATE FUNCTION core10.revoke_approval_delegation_v1(
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

CREATE FUNCTION core10.withdraw_typed_approval_v1(
 p_request bigint,p_key text
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,core10 AS $fn$
DECLARE q core10.approval_requests%ROWTYPE;actor uuid:=core10.actor_uid();
 event_id bigint;
BEGIN
 IF actor IS NULL OR p_request IS NULL OR p_key IS NULL
  OR p_key !~ '^[A-Za-z0-9_-]{8,128}$'
 THEN RAISE EXCEPTION 'invalid_approval_withdrawal'; END IF;
 SELECT * INTO q FROM core10.approval_requests WHERE id=p_request FOR UPDATE;
 IF NOT FOUND OR q.policy_id_v1 IS NULL OR q.created_by<>actor
  OR NOT core10.can_approval_action_v1(q.tenant_id,q.business_id,'approval.withdraw')
 THEN RAISE EXCEPTION 'approval_withdraw_denied'; END IF;
 SELECT id INTO event_id FROM core10.approval_events
 WHERE request_id=p_request AND idempotency_key=p_key AND action='withdraw' AND actor_id=actor;
 IF FOUND THEN RETURN event_id; END IF;
 IF q.status<>'pending' OR EXISTS(SELECT 1 FROM core10.approval_stage_receipts_v1
  WHERE request_id=p_request)
 THEN RAISE EXCEPTION 'withdraw_invalid_transition'; END IF;
 UPDATE core10.approval_requests SET status='withdrawn',decided_by=actor,
   decided_at=clock_timestamp() WHERE id=p_request;
 INSERT INTO core10.approval_events(request_id,tenant_id,business_id,actor_id,action,idempotency_key)
 VALUES(p_request,q.tenant_id,q.business_id,actor,'withdraw',p_key)
 RETURNING id INTO event_id;
 RETURN event_id;
END $fn$;

-- Replace ONLY the existing decision RPC. Intermediate approvals write a receipt
-- and audit, but cannot set the request approved or post any domain stock/money.
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
 WHERE policy_id=q.policy_id_v1;
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

-- No direct read rights on other makers' requests. Task RPC is only the next
-- authorized reviewer and excludes payload/tenant/actor personal metadata.
CREATE FUNCTION core10.my_routed_review_tasks_v1(p_business bigint)
RETURNS TABLE(request_id bigint,business_id bigint,domain text,action_code text,
 source_key text,source_version bigint,policy_version integer,
 stage_no integer,stage_total integer,expires_at timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $fn$
DECLARE tenant bigint;actor uuid:=core10.actor_uid();
BEGIN
 SELECT b.tenant_id INTO tenant FROM core10.businesses b WHERE b.id=p_business;
 IF actor IS NULL OR p_business IS NULL OR tenant IS NULL
  OR NOT core10.can_approval_action_v1(tenant,p_business,'approval.decide')
 THEN RAISE EXCEPTION 'reviewer_task_access_denied'; END IF;
 RETURN QUERY
 SELECT q.id,q.business_id,q.domain_v1,q.action_code_v1,q.source_key_v1,
  q.source_version_v1,q.policy_version_v1,
  (SELECT count(*)::integer+1 FROM core10.approval_stage_receipts_v1 s
    WHERE s.request_id=q.id) AS current_stage,
  cardinality(rt.stages),q.expires_at_v1
 FROM core10.approval_requests q
 JOIN core10.approval_routes_v1 rt ON rt.policy_id=q.policy_id_v1
   AND rt.tenant_id=q.tenant_id AND rt.business_id=q.business_id
 WHERE q.business_id=p_business AND q.tenant_id=tenant
  AND q.status='pending' AND q.expires_at_v1>statement_timestamp()
  AND q.created_by<>actor
  AND NOT EXISTS(SELECT 1 FROM core10.approval_stage_receipts_v1 s
    WHERE s.request_id=q.id AND s.actor_id=actor)
  AND (SELECT count(*) FROM core10.approval_stage_receipts_v1 s
    WHERE s.request_id=q.id)<cardinality(rt.stages)
  AND core10._can_review_stage_v1(q.id,
    (SELECT count(*)::integer+1 FROM core10.approval_stage_receipts_v1 s WHERE s.request_id=q.id))
 ORDER BY q.created_at,q.id LIMIT 100;
END $fn$;

REVOKE EXECUTE ON FUNCTION core10.configure_approval_route_v1(bigint,text[],text),
 core10.delegate_approval_stage_v1(bigint,uuid,integer,text),
 core10.revoke_approval_delegation_v1(bigint,text),
 core10.withdraw_typed_approval_v1(bigint,text),
 core10.my_routed_review_tasks_v1(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION core10.configure_approval_route_v1(bigint,text[],text),
 core10.delegate_approval_stage_v1(bigint,uuid,integer,text),
 core10.revoke_approval_delegation_v1(bigint,text),
 core10.withdraw_typed_approval_v1(bigint,text),
 core10.my_routed_review_tasks_v1(bigint) TO authenticated;
