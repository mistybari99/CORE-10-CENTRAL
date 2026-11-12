-- GOV-002 / C10-DETAIL-GOV-002-exception-escalation.
-- DRAFT: non-authorizing, bounded escalation review only in disposable c10_demo.
-- Must run AFTER A018 + A008 typed/inbox + routing + thresholds + source report.
-- An ACKNOWLEDGEMENT is NEVER an approved approval request, policy waiver,
-- stock movement, payment, accountant posting, or permission override.
-- Real domain exception/override eligibility is NOT implemented by this slice.
-- Intended as a safe canonical triage trail until per-domain policies exist.

CREATE TABLE c10_demo.approval_exception_escalations_v1 (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  request_id bigint NOT NULL UNIQUE REFERENCES c10_demo.approval_requests(id),
  tenant_id bigint NOT NULL,
  business_id bigint NOT NULL,
  policy_id bigint NOT NULL REFERENCES c10_demo.approval_policy_versions_v1(id),
  source_version bigint NOT NULL CHECK(source_version > 0),
  payload_sha256 text NOT NULL CHECK(payload_sha256 ~ '^[0-9a-f]{64}$'),
  created_by uuid NOT NULL,
  reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 12 AND 400),
  severity text NOT NULL CHECK(severity IN ('normal','urgent')),
  ttl_minutes integer NOT NULL CHECK(ttl_minutes BETWEEN 5 AND 1440),
  request_key text NOT NULL CHECK(request_key ~ '^[A-Za-z0-9_-]{8,128}$'),
  status text NOT NULL DEFAULT 'pending'
    CHECK(status IN ('pending','acknowledged','declined','withdrawn')),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  expires_at timestamptz NOT NULL,
  decided_by uuid,
  decided_at timestamptz,
  CHECK (
   (status='pending' AND decided_by IS NULL AND decided_at IS NULL)
   OR (status<>'pending' AND decided_by IS NOT NULL AND decided_at IS NOT NULL)
  ),
  UNIQUE(business_id,created_by,request_key),
  CHECK(expires_at>created_at)
);
CREATE INDEX approval_exception_inbox_idx_v1
 ON c10_demo.approval_exception_escalations_v1
 (business_id,status,expires_at);

CREATE TABLE c10_demo.approval_exception_events_v1 (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 escalation_id bigint NOT NULL REFERENCES c10_demo.approval_exception_escalations_v1(id),
 tenant_id bigint NOT NULL, business_id bigint NOT NULL,
 request_id bigint NOT NULL REFERENCES c10_demo.approval_requests(id),
 creator_id uuid NOT NULL, actor_id uuid NOT NULL,
 action text NOT NULL
  CHECK(action IN ('submitted','acknowledged','declined','withdrawn')),
 event_key text NOT NULL CHECK(event_key ~ '^[A-Za-z0-9_-]{8,128}$'),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(escalation_id,action),
 UNIQUE(escalation_id,event_key)
);
ALTER TABLE c10_demo.approval_exception_escalations_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE c10_demo.approval_exception_events_v1 ENABLE ROW LEVEL SECURITY;
CREATE POLICY exception_scoped_read_v1
 ON c10_demo.approval_exception_escalations_v1
 FOR SELECT TO authenticated
 USING(
  c10_demo.can_manage(tenant_id,business_id)
  OR (created_by=c10_demo.actor_uid()
     AND c10_demo.can_business(tenant_id,business_id))
 );
CREATE POLICY exception_event_scoped_read_v1
 ON c10_demo.approval_exception_events_v1
 FOR SELECT TO authenticated
 USING(
  c10_demo.can_manage(tenant_id,business_id)
  OR (creator_id=c10_demo.actor_uid()
     AND c10_demo.can_business(tenant_id,business_id))
 );
REVOKE ALL ON c10_demo.approval_exception_escalations_v1,
  c10_demo.approval_exception_events_v1 FROM PUBLIC,anon,authenticated;
GRANT SELECT ON c10_demo.approval_exception_escalations_v1,
 c10_demo.approval_exception_events_v1 TO authenticated;

-- One typed request can get ONE escalation. Immutable request/source version,
-- fingerprint, policy and business scope copied from server record.
CREATE FUNCTION c10_demo.request_approval_exception_v1(
 p_request bigint,p_reason text,p_severity text,p_minutes integer,p_key text
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path=c10_demo,pg_catalog AS $fn$
DECLARE v_request c10_demo.approval_requests%ROWTYPE;
        v_old c10_demo.approval_exception_escalations_v1%ROWTYPE;
        v_actor uuid:=c10_demo.actor_uid();
        v_id bigint;v_at timestamptz:=clock_timestamp();
BEGIN
 IF v_actor IS NULL OR p_request IS NULL
  OR p_reason IS NULL OR length(btrim(p_reason)) NOT BETWEEN 12 AND 400
  OR p_severity IS NULL OR p_severity NOT IN ('normal','urgent')
  OR p_minutes IS NULL OR p_minutes NOT BETWEEN 5 AND 1440
  OR p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{8,128}$'
 THEN RAISE EXCEPTION 'invalid_exception_request'; END IF;
 SELECT * INTO v_request FROM c10_demo.approval_requests
  WHERE id=p_request FOR UPDATE;
 IF NOT FOUND OR v_request.policy_id_v1 IS NULL
   OR v_request.created_by<>v_actor
   OR NOT c10_demo.can_business(v_request.tenant_id,v_request.business_id)
 THEN RAISE EXCEPTION 'exception_request_denied'; END IF;
 SELECT * INTO v_old FROM c10_demo.approval_exception_escalations_v1
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
 IF v_request.status<>'pending'
   OR v_request.expires_at_v1<=v_at
 THEN RAISE EXCEPTION 'exception_parent_not_pending'; END IF;
 INSERT INTO c10_demo.approval_exception_escalations_v1
  (request_id,tenant_id,business_id,policy_id,source_version,
   payload_sha256,created_by,reason,severity,ttl_minutes,request_key,
   created_at,expires_at)
 VALUES(p_request,v_request.tenant_id,v_request.business_id,
  v_request.policy_id_v1,v_request.source_version_v1,
  v_request.payload_sha256_v1,v_actor,btrim(p_reason),p_severity,
  p_minutes,p_key,v_at,LEAST(v_request.expires_at_v1,
                                v_at+make_interval(mins=>p_minutes)))
 RETURNING id INTO v_id;
 INSERT INTO c10_demo.approval_exception_events_v1
  (escalation_id,tenant_id,business_id,request_id,creator_id,actor_id,
   action,event_key)
 VALUES(v_id,v_request.tenant_id,v_request.business_id,p_request,
   v_actor,v_actor,'submitted',p_key);
 RETURN v_id;
END $fn$;

-- Decision is a BUSINESS REVIEW ACKNOWLEDGEMENT/DECLINE, not a
-- waiver or grant. Parent approval state and domain effects remain untouched.
-- Row locking on parent first serializes against normal approve/reject/withdraw.
CREATE FUNCTION c10_demo.decide_approval_exception_v1(
 p_escalation bigint,p_action text,p_key text
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path=c10_demo,pg_catalog AS $fn$
DECLARE v_e c10_demo.approval_exception_escalations_v1%ROWTYPE;
        v_r c10_demo.approval_requests%ROWTYPE;
        v_previous c10_demo.approval_exception_events_v1%ROWTYPE;
        v_actor uuid:=c10_demo.actor_uid();
        v_request_id bigint;v_event bigint;v_at timestamptz:=clock_timestamp();
BEGIN
 IF v_actor IS NULL OR p_escalation IS NULL
  OR p_action NOT IN ('acknowledged','declined')
  OR p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{8,128}$'
 THEN RAISE EXCEPTION 'invalid_exception_decision'; END IF;
 SELECT request_id INTO v_request_id
  FROM c10_demo.approval_exception_escalations_v1 WHERE id=p_escalation;
 IF NOT FOUND THEN RAISE EXCEPTION 'exception_not_found'; END IF;
 SELECT * INTO v_r FROM c10_demo.approval_requests
  WHERE id=v_request_id FOR UPDATE;
 SELECT * INTO v_e FROM c10_demo.approval_exception_escalations_v1
  WHERE id=p_escalation FOR UPDATE;
 IF NOT FOUND OR v_e.created_by=v_actor
   OR NOT c10_demo.can_manage(v_e.tenant_id,v_e.business_id)
   OR v_e.tenant_id<>v_r.tenant_id OR v_e.business_id<>v_r.business_id
 THEN RAISE EXCEPTION 'exception_decision_denied'; END IF;
 SELECT * INTO v_previous FROM c10_demo.approval_exception_events_v1
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
 UPDATE c10_demo.approval_exception_escalations_v1
 SET status=p_action,decided_by=v_actor,decided_at=v_at WHERE id=p_escalation;
 INSERT INTO c10_demo.approval_exception_events_v1
   (escalation_id,tenant_id,business_id,request_id,creator_id,actor_id,
    action,event_key)
 VALUES(p_escalation,v_e.tenant_id,v_e.business_id,v_r.id,
   v_e.created_by,v_actor,p_action,p_key)
 RETURNING id INTO v_event;
 RETURN v_event;
END $fn$;

CREATE FUNCTION c10_demo.withdraw_approval_exception_v1(
 p_escalation bigint,p_key text
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path=c10_demo,pg_catalog AS $fn$
DECLARE v_e c10_demo.approval_exception_escalations_v1%ROWTYPE;
        v_r c10_demo.approval_requests%ROWTYPE;
        v_previous c10_demo.approval_exception_events_v1%ROWTYPE;
        v_actor uuid:=c10_demo.actor_uid();
        v_request_id bigint;v_event bigint;
BEGIN
 IF v_actor IS NULL OR p_escalation IS NULL
  OR p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{8,128}$'
 THEN RAISE EXCEPTION 'invalid_exception_withdraw'; END IF;
 SELECT request_id INTO v_request_id
  FROM c10_demo.approval_exception_escalations_v1 WHERE id=p_escalation;
 IF NOT FOUND THEN RAISE EXCEPTION 'exception_not_found'; END IF;
 SELECT * INTO v_r FROM c10_demo.approval_requests
  WHERE id=v_request_id FOR UPDATE;
 SELECT * INTO v_e FROM c10_demo.approval_exception_escalations_v1
  WHERE id=p_escalation FOR UPDATE;
 IF NOT FOUND OR v_e.created_by<>v_actor
  OR NOT c10_demo.can_business(v_e.tenant_id,v_e.business_id)
  OR v_e.request_id<>v_r.id
 THEN RAISE EXCEPTION 'exception_withdraw_denied'; END IF;
 SELECT * INTO v_previous FROM c10_demo.approval_exception_events_v1
  WHERE escalation_id=p_escalation AND event_key=p_key;
 IF FOUND THEN
  IF v_previous.actor_id<>v_actor OR v_previous.action<>'withdrawn'
  THEN RAISE EXCEPTION 'exception_withdraw_replay_conflict'; END IF;
  RETURN v_previous.id;
 END IF;
 IF v_e.status<>'pending'
 THEN RAISE EXCEPTION 'exception_stale_or_final'; END IF;
 UPDATE c10_demo.approval_exception_escalations_v1
  SET status='withdrawn',decided_by=v_actor,decided_at=clock_timestamp()
 WHERE id=p_escalation;
 INSERT INTO c10_demo.approval_exception_events_v1
  (escalation_id,tenant_id,business_id,request_id,creator_id,actor_id,
   action,event_key)
 VALUES(p_escalation,v_e.tenant_id,v_e.business_id,v_r.id,
 v_e.created_by,v_actor,'withdrawn',p_key)
 RETURNING id INTO v_event;
 RETURN v_event;
END $fn$;

-- Read-only, RLS-invoker projection for a future guided owner/maker UI.
-- View NEVER provides waiver, execute token, amount, or source payload.
CREATE VIEW c10_demo.approval_exception_inbox_v1
WITH (security_invoker=true) AS
SELECT e.id AS escalation_id,e.request_id,e.tenant_id,e.business_id,
 e.policy_id,e.source_version,e.created_by,
 e.reason,e.severity,e.created_at,e.expires_at,
 e.status AS stored_status,r.status AS parent_approval_status,
 CASE WHEN e.status='pending' AND r.status<>'pending'
          THEN 'parent_closed'
      WHEN e.status='pending' AND e.expires_at<=clock_timestamp()
          THEN 'expired'
      WHEN e.status='pending' AND r.expires_at_v1<=clock_timestamp()
          THEN 'expired'
      ELSE e.status END AS display_status,
 e.decided_by,e.decided_at
FROM c10_demo.approval_exception_escalations_v1 e
JOIN c10_demo.approval_requests r ON r.id=e.request_id
 WHERE e.policy_id=r.policy_id_v1
   AND e.tenant_id=r.tenant_id AND e.business_id=r.business_id
   AND (
     c10_demo.can_manage(e.tenant_id,e.business_id)
     OR (e.created_by=c10_demo.actor_uid()
         AND c10_demo.can_business(e.tenant_id,e.business_id))
   );
REVOKE ALL ON c10_demo.approval_exception_inbox_v1 FROM PUBLIC,anon;
GRANT SELECT ON c10_demo.approval_exception_inbox_v1 TO authenticated;
REVOKE ALL ON FUNCTION
 c10_demo.request_approval_exception_v1(bigint,text,text,integer,text),
 c10_demo.decide_approval_exception_v1(bigint,text,text),
 c10_demo.withdraw_approval_exception_v1(bigint,text)
 FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION
 c10_demo.request_approval_exception_v1(bigint,text,text,integer,text),
 c10_demo.decide_approval_exception_v1(bigint,text,text),
 c10_demo.withdraw_approval_exception_v1(bigint,text)
 TO authenticated;
-- Explicit absence of any bypass/override/execute authority is intentional.
