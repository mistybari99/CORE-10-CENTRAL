-- NP01 B-006 migration 0015: scoped exception triage, never domain waiver.
-- Port of PR #82 onto one core10 approval + canonical audit engine.
-- Approval decision and stock/money effects remain untouched by acknowledgement.

CREATE TABLE core10.approval_exception_escalations_v1 (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  request_id bigint NOT NULL UNIQUE REFERENCES core10.approval_requests(id),
  tenant_id bigint NOT NULL,
  business_id bigint NOT NULL,
  policy_id bigint NOT NULL REFERENCES core10.approval_policy_versions_v1(id),
  source_version bigint NOT NULL CHECK(source_version > 0),
  payload_sha256 text NOT NULL CHECK(payload_sha256 ~ '^[0-9a-f]{64}$'),
  created_by uuid NOT NULL,
  reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 12 AND 400),
  severity text NOT NULL CHECK(severity IN ('normal','urgent')),
  ttl_minutes integer NOT NULL CHECK(ttl_minutes BETWEEN 1 AND 43200),
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
 ON core10.approval_exception_escalations_v1
 (business_id,status,expires_at);

CREATE TABLE core10.approval_exception_events_v1 (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 escalation_id bigint NOT NULL REFERENCES core10.approval_exception_escalations_v1(id),
 tenant_id bigint NOT NULL, business_id bigint NOT NULL,
 request_id bigint NOT NULL REFERENCES core10.approval_requests(id),
 creator_id uuid NOT NULL, actor_id uuid NOT NULL,
 action text NOT NULL
  CHECK(action IN ('submitted','acknowledged','declined','withdrawn')),
 event_key text NOT NULL CHECK(event_key ~ '^[A-Za-z0-9_-]{8,128}$'),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(escalation_id,action),
 UNIQUE(escalation_id,event_key)
);
ALTER TABLE core10.approval_exception_escalations_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE core10.approval_exception_events_v1 ENABLE ROW LEVEL SECURITY;
CREATE POLICY exception_scoped_read_v1
 ON core10.approval_exception_escalations_v1
 FOR SELECT TO authenticated
 USING(
  core10.can_manage(tenant_id,business_id)
  OR (created_by=core10.actor_uid()
     AND core10.can_business(tenant_id,business_id))
 );
CREATE POLICY exception_event_scoped_read_v1
 ON core10.approval_exception_events_v1
 FOR SELECT TO authenticated
 USING(
  core10.can_manage(tenant_id,business_id)
  OR (creator_id=core10.actor_uid()
     AND core10.can_business(tenant_id,business_id))
 );
REVOKE ALL ON core10.approval_exception_escalations_v1,
  core10.approval_exception_events_v1 FROM PUBLIC,authenticated;
GRANT SELECT ON core10.approval_exception_escalations_v1,
 core10.approval_exception_events_v1 TO authenticated;

-- One typed request can get ONE escalation. Immutable request/source version,
-- fingerprint, policy and business scope copied from server record.
CREATE FUNCTION core10.request_approval_exception_v1(
 p_request bigint,p_reason text,p_severity text,p_minutes integer,p_key text
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path=core10,pg_catalog AS $fn$
DECLARE v_request core10.approval_requests%ROWTYPE;
        v_old core10.approval_exception_escalations_v1%ROWTYPE;
        v_actor uuid:=core10.actor_uid();
        v_id bigint;v_at timestamptz:=clock_timestamp();
BEGIN
 IF v_actor IS NULL OR p_request IS NULL
  OR p_reason IS NULL OR length(btrim(p_reason)) NOT BETWEEN 12 AND 400
  OR p_severity IS NULL OR p_severity NOT IN ('normal','urgent')
  OR p_minutes IS NULL OR p_minutes NOT BETWEEN 1 AND 43200
  OR p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{8,128}$'
 THEN RAISE EXCEPTION 'invalid_exception_request'; END IF;
 SELECT * INTO v_request FROM core10.approval_requests
  WHERE id=p_request FOR UPDATE;
 IF NOT FOUND OR v_request.policy_id_v1 IS NULL
   OR v_request.created_by<>v_actor
   OR NOT core10.can_business(v_request.tenant_id,v_request.business_id)
 THEN RAISE EXCEPTION 'exception_request_denied'; END IF;
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

-- Decision is a BUSINESS REVIEW ACKNOWLEDGEMENT/DECLINE, not a
-- waiver or grant. Parent approval state and domain effects remain untouched.
-- Row locking on parent first serializes against normal approve/reject/withdraw.
CREATE FUNCTION core10.decide_approval_exception_v1(
 p_escalation bigint,p_action text,p_key text
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path=core10,pg_catalog AS $fn$
DECLARE v_e core10.approval_exception_escalations_v1%ROWTYPE;
        v_r core10.approval_requests%ROWTYPE;
        v_previous core10.approval_exception_events_v1%ROWTYPE;
        v_actor uuid:=core10.actor_uid();
        v_request_id bigint;v_event bigint;v_at timestamptz:=clock_timestamp();
BEGIN
 IF v_actor IS NULL OR p_escalation IS NULL
  OR p_action NOT IN ('acknowledged','declined')
  OR p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{8,128}$'
 THEN RAISE EXCEPTION 'invalid_exception_decision'; END IF;
 SELECT request_id INTO v_request_id
  FROM core10.approval_exception_escalations_v1 WHERE id=p_escalation;
 IF NOT FOUND THEN RAISE EXCEPTION 'exception_not_found'; END IF;
 SELECT * INTO v_r FROM core10.approval_requests
  WHERE id=v_request_id FOR UPDATE;
 SELECT * INTO v_e FROM core10.approval_exception_escalations_v1
  WHERE id=p_escalation FOR UPDATE;
 IF NOT FOUND OR v_e.created_by=v_actor
   OR NOT core10.can_manage(v_e.tenant_id,v_e.business_id)
   OR v_e.tenant_id<>v_r.tenant_id OR v_e.business_id<>v_r.business_id
 THEN RAISE EXCEPTION 'exception_decision_denied'; END IF;
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

CREATE FUNCTION core10.withdraw_approval_exception_v1(
 p_escalation bigint,p_key text
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path=core10,pg_catalog AS $fn$
DECLARE v_e core10.approval_exception_escalations_v1%ROWTYPE;
        v_r core10.approval_requests%ROWTYPE;
        v_previous core10.approval_exception_events_v1%ROWTYPE;
        v_actor uuid:=core10.actor_uid();
        v_request_id bigint;v_event bigint;
BEGIN
 IF v_actor IS NULL OR p_escalation IS NULL
  OR p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{8,128}$'
 THEN RAISE EXCEPTION 'invalid_exception_withdraw'; END IF;
 SELECT request_id INTO v_request_id
  FROM core10.approval_exception_escalations_v1 WHERE id=p_escalation;
 IF NOT FOUND THEN RAISE EXCEPTION 'exception_not_found'; END IF;
 SELECT * INTO v_r FROM core10.approval_requests
  WHERE id=v_request_id FOR UPDATE;
 SELECT * INTO v_e FROM core10.approval_exception_escalations_v1
  WHERE id=p_escalation FOR UPDATE;
 IF NOT FOUND OR v_e.created_by<>v_actor
  OR NOT core10.can_business(v_e.tenant_id,v_e.business_id)
  OR v_e.request_id<>v_r.id
 THEN RAISE EXCEPTION 'exception_withdraw_denied'; END IF;
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

-- Read-only, RLS-invoker projection for a future guided owner/maker UI.
-- View NEVER provides waiver, execute token, amount, or source payload.
CREATE VIEW core10.approval_exception_inbox_v1
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
FROM core10.approval_exception_escalations_v1 e
JOIN core10.approval_requests r ON r.id=e.request_id
 WHERE e.policy_id=r.policy_id_v1
   AND e.tenant_id=r.tenant_id AND e.business_id=r.business_id
   AND (
     core10.can_manage(e.tenant_id,e.business_id)
     OR (e.created_by=core10.actor_uid()
         AND core10.can_business(e.tenant_id,e.business_id))
   );
REVOKE ALL ON core10.approval_exception_inbox_v1 FROM PUBLIC;
GRANT SELECT ON core10.approval_exception_inbox_v1 TO authenticated;
REVOKE ALL ON FUNCTION
 core10.request_approval_exception_v1(bigint,text,text,integer,text),
 core10.decide_approval_exception_v1(bigint,text,text),
 core10.withdraw_approval_exception_v1(bigint,text)
 FROM PUBLIC;
GRANT EXECUTE ON FUNCTION
 core10.request_approval_exception_v1(bigint,text,text,integer,text),
 core10.decide_approval_exception_v1(bigint,text,text),
 core10.withdraw_approval_exception_v1(bigint,text)
 TO authenticated;
-- Explicit absence of any bypass/override/execute authority is intentional.

-- Every exception journal event also appends to the already-canonical audit chain.
-- This table stores the *domain event receipt*, not a second audit engine.
CREATE FUNCTION core10._exception_to_canonical_audit_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,core10 AS $np01$
BEGIN
 PERFORM core10._append_canonical_audit_v1(
   NEW.tenant_id,NEW.business_id,'approval_exception',NEW.id::text,
   'approval.exception_'||NEW.action,NEW.actor_id,'exception:'||NEW.id::text,
   jsonb_build_object('event_ref',NEW.id::text,'request_ref',NEW.request_id::text,
                      'escalation_ref',NEW.escalation_id::text,'action',NEW.action));
 RETURN NEW;
END $np01$;
CREATE TRIGGER np01_exception_to_canonical_audit_v1
 AFTER INSERT ON core10.approval_exception_events_v1
 FOR EACH ROW EXECUTE FUNCTION core10._exception_to_canonical_audit_v1();
REVOKE ALL ON FUNCTION core10._exception_to_canonical_audit_v1() FROM PUBLIC,authenticated;
CREATE FUNCTION core10._deny_np01_exception_event_mutation_v1()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,core10 AS $np01$
BEGIN RAISE EXCEPTION 'approval_exception_journal_immutable' USING ERRCODE='42501'; END $np01$;
CREATE TRIGGER np01_exception_event_immutable_v1
 BEFORE UPDATE OR DELETE ON core10.approval_exception_events_v1
 FOR EACH ROW EXECUTE FUNCTION core10._deny_np01_exception_event_mutation_v1();
CREATE TRIGGER np01_exception_event_no_truncate_v1
 BEFORE TRUNCATE ON core10.approval_exception_events_v1
 FOR EACH STATEMENT EXECUTE FUNCTION core10._deny_np01_exception_event_mutation_v1();
CREATE TRIGGER np01_exception_state_no_truncate_v1
 BEFORE TRUNCATE ON core10.approval_exception_escalations_v1
 FOR EACH STATEMENT EXECUTE FUNCTION core10._deny_np01_exception_event_mutation_v1();
REVOKE ALL ON FUNCTION core10._deny_np01_exception_event_mutation_v1()
 FROM PUBLIC,authenticated;
