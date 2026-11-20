-- S1-c rollback of typed approvals: no CASCADE, preserve 0009 base journal.
DROP FUNCTION core10.verify_approval_binding_v1(bigint,bigint,text,text,text,bigint,jsonb);
DROP FUNCTION core10.submit_typed_approval_v1(bigint,text,text,text,bigint,jsonb,text);
DROP FUNCTION core10.publish_approval_policy_v1(bigint,text,text,integer,text);
CREATE OR REPLACE FUNCTION core10.decide_approval(p_request bigint,p_action text,p_key text)
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
DROP INDEX core10.approval_typed_request_replay_v1;
DROP INDEX core10.approval_typed_inbox_v1;
ALTER TABLE core10.approval_requests
 DROP CONSTRAINT approval_request_typed_contract_v1,
 DROP CONSTRAINT approval_request_policy_scope_v1,
 DROP COLUMN domain_v1,DROP COLUMN action_code_v1,
 DROP COLUMN source_key_v1,DROP COLUMN source_version_v1,
 DROP COLUMN payload_sha256_v1,DROP COLUMN policy_id_v1,
 DROP COLUMN policy_version_v1,DROP COLUMN expires_at_v1,DROP COLUMN submit_key_v1;
DROP POLICY approval_policy_owner_read_v1 ON core10.approval_policy_versions_v1;
DROP TABLE core10.approval_policy_versions_v1;
