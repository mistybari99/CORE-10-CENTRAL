-- S1-c / CHG-011: A008 isolated GOV-002 non-posting core port.
-- Source: PR #99 ancestor c10_a008_atomic_approval_draft.sql. No duplicate auth/stock store.
-- Approval requests/events are one canonical approval journal; canonical audit is 0008.
-- C10-A008 isolated PostgreSQL approval prototype; NOT a production migration.
-- Apply ONLY after c10_a018_demo_backend.sql to disposable c10_demo database.
CREATE TABLE core10.approval_requests (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL,
 business_id bigint NOT NULL,
 created_by uuid NOT NULL,
 status text NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','approved','rejected','deferred')),
 created_at timestamptz NOT NULL DEFAULT now(),
 decided_by uuid,
 decided_at timestamptz,
 FOREIGN KEY (business_id,tenant_id) REFERENCES core10.businesses(id,tenant_id),
 CHECK ((status='pending' AND decided_by IS NULL AND decided_at IS NULL)
     OR (status<>'pending' AND decided_by IS NOT NULL AND decided_at IS NOT NULL))
);
CREATE TABLE core10.approval_events (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 request_id bigint NOT NULL REFERENCES core10.approval_requests(id),
 tenant_id bigint NOT NULL,
 business_id bigint NOT NULL,
 actor_id uuid NOT NULL,
 action text NOT NULL CHECK(action IN ('approve','reject','defer')),
 idempotency_key text NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(request_id,idempotency_key)
);
CREATE INDEX approval_events_business_idx ON core10.approval_events(business_id,request_id);
ALTER TABLE core10.approval_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE core10.approval_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY approval_request_read ON core10.approval_requests FOR SELECT TO authenticated
 USING(core10.can_see_business(tenant_id,business_id));
CREATE POLICY approval_event_read ON core10.approval_events FOR SELECT TO authenticated
 USING(core10.can_see_business(tenant_id,business_id));

-- This function owns both the state transition and append-only event in one transaction.
-- Caller-supplied tenant, business, actor or role claims are never accepted.
CREATE FUNCTION core10.decide_approval(p_request bigint,p_action text,p_key text)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path=core10,pg_catalog AS $$
DECLARE v_req core10.approval_requests%ROWTYPE;
        v_actor uuid; v_event bigint; v_previous core10.approval_events%ROWTYPE;
BEGIN
 v_actor:=core10.actor_uid();
 IF v_actor IS NULL OR p_request IS NULL OR p_action IS NULL
    OR p_action NOT IN ('approve','reject','defer')
    OR p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{8,128}$' THEN
   RAISE EXCEPTION 'invalid_approval_command';
 END IF;
 SELECT * INTO v_req FROM core10.approval_requests WHERE id=p_request FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'approval_not_authorized'; END IF;
 IF NOT core10.can_manage(v_req.tenant_id,v_req.business_id)
    OR v_req.created_by=v_actor THEN
   RAISE EXCEPTION 'approval_not_authorized';
 END IF;
 -- Replays must match the original actor and action; do not reapply transitions.
 SELECT * INTO v_previous FROM core10.approval_events
 WHERE request_id=p_request AND idempotency_key=p_key;
 IF FOUND THEN
   IF v_previous.actor_id<>v_actor OR v_previous.action<>p_action
      OR v_previous.tenant_id<>v_req.tenant_id OR v_previous.business_id<>v_req.business_id THEN
     RAISE EXCEPTION 'approval_idempotency_conflict';
   END IF;
   RETURN v_previous.id;
 END IF;
 IF v_req.status<>'pending' THEN RAISE EXCEPTION 'approval_invalid_transition'; END IF;
 UPDATE core10.approval_requests
 SET status=CASE p_action WHEN 'approve' THEN 'approved'
                          WHEN 'reject' THEN 'rejected' ELSE 'deferred' END,
     decided_by=v_actor,decided_at=clock_timestamp()
 WHERE id=p_request AND status='pending';
 IF NOT FOUND THEN RAISE EXCEPTION 'approval_invalid_transition'; END IF;
 INSERT INTO core10.approval_events
 (request_id,tenant_id,business_id,actor_id,action,idempotency_key)
 VALUES (p_request,v_req.tenant_id,v_req.business_id,v_actor,p_action,p_key)
 RETURNING id INTO v_event;
 RETURN v_event;
END $$;

-- Lock down all direct writes and public function execution.
REVOKE ALL ON core10.approval_requests,core10.approval_events FROM PUBLIC,authenticated;
REVOKE ALL ON FUNCTION core10.decide_approval(bigint,text,text) FROM PUBLIC;
GRANT SELECT ON core10.approval_requests,core10.approval_events TO authenticated;
GRANT EXECUTE ON FUNCTION core10.decide_approval(bigint,text,text) TO authenticated;
-- SECURITY DEFINER owner must be controlled, no BYPASSRLS delegation, and migration reviewed.
-- This prototype has NOT been executed against PostgreSQL or Supabase.

-- Domain approval receipts append to the ONE canonical audit stream in 0008.
CREATE FUNCTION core10._approval_to_canonical_audit_v1() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,core10 AS $body$
BEGIN
 PERFORM core10._append_canonical_audit_v1(
  NEW.tenant_id,NEW.business_id,'approval',NEW.id::text,'approval.'||NEW.action,
  NEW.actor_id,'approval:'||NEW.id::text,
  jsonb_build_object('event_ref',NEW.id::text,'request_ref',NEW.request_id::text,
                     'action',NEW.action));
 RETURN NEW;
END $body$;
CREATE TRIGGER approval_to_canonical_audit_v1 AFTER INSERT ON core10.approval_events
 FOR EACH ROW EXECUTE FUNCTION core10._approval_to_canonical_audit_v1();
REVOKE EXECUTE ON FUNCTION core10._approval_to_canonical_audit_v1() FROM PUBLIC,authenticated;
CREATE FUNCTION core10._immutable_approval_event_v1() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog,core10 AS $body$
BEGIN RAISE EXCEPTION 'approval_event_immutable'; END $body$;
CREATE TRIGGER approval_event_immutable_v1 BEFORE UPDATE OR DELETE ON core10.approval_events
 FOR EACH ROW EXECUTE FUNCTION core10._immutable_approval_event_v1();
REVOKE EXECUTE ON FUNCTION core10._immutable_approval_event_v1() FROM PUBLIC,authenticated;
