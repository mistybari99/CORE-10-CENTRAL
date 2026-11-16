-- B-020 / NP01 0019 strict rollback: restore exact 0011 review/withdrawal bodies.
-- 0102-0100 are rolled back first by the numbered runner.
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

CREATE OR REPLACE FUNCTION core10.withdraw_typed_approval_v1(
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
