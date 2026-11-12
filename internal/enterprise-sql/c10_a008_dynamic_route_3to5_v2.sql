-- GOV-002 3–5 checker route extension, disposable PostgreSQL17 ONLY.
-- Must follow ALL prior GOV002 layers including scoped outcome report.
-- Reuses canonical policy, request, event, delegation and stage receipt stores.
-- No independent auth engine, owner grant, real stock/finance or live SG migration.
ALTER TABLE c10_demo.approval_routes_v1
 DROP CONSTRAINT approval_routes_v1_stages_check;
ALTER TABLE c10_demo.approval_routes_v1
 ADD CONSTRAINT approval_routes_v1_stages_check CHECK (
  cardinality(stages) BETWEEN 2 AND 5 AND
  stages[1]='business_owner' AND stages[cardinality(stages)]='tenant_owner' AND
  stages <@ ARRAY['business_owner','manager','tenant_owner']::text[]
 );
ALTER TABLE c10_demo.approval_stage_receipts_v1
 DROP CONSTRAINT approval_stage_receipts_v1_stage_no_check;
ALTER TABLE c10_demo.approval_stage_receipts_v1
 ADD CONSTRAINT approval_stage_receipts_v1_stage_no_check CHECK(stage_no BETWEEN 1 AND 5);

-- Route installation is immutable once policy has been used. The old two-step
-- configure_approval_route_v1 API remains unchanged for backward compatibility.
CREATE FUNCTION c10_demo.configure_approval_route_dynamic_v2(
 p_policy bigint,p_stages text[],p_key text
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $fn$
DECLARE v_policy c10_demo.approval_policy_versions_v1%ROWTYPE;
        v_old c10_demo.approval_routes_v1%ROWTYPE;
        v_actor uuid:=c10_demo.actor_uid();
BEGIN
 IF v_actor IS NULL OR p_policy IS NULL OR p_stages IS NULL
    OR cardinality(p_stages) NOT BETWEEN 3 AND 5
    OR array_position(p_stages,NULL) IS NOT NULL
    OR p_stages[1]<>'business_owner'
    OR p_stages[cardinality(p_stages)]<>'tenant_owner'
    OR NOT p_stages <@ ARRAY['business_owner','manager','tenant_owner']::text[]
    OR p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{8,128}$'
 THEN RAISE EXCEPTION 'invalid_dynamic_approval_route'; END IF;
 SELECT * INTO v_policy FROM c10_demo.approval_policy_versions_v1 WHERE id=p_policy FOR UPDATE;
 IF NOT FOUND OR NOT c10_demo.can_manage(v_policy.tenant_id,v_policy.business_id)
 THEN RAISE EXCEPTION 'dynamic_route_not_authorized'; END IF;
 SELECT * INTO v_old FROM c10_demo.approval_routes_v1 WHERE policy_id=p_policy;
 IF FOUND THEN
   IF v_old.stages<>p_stages OR v_old.route_key<>p_key OR v_old.configured_by<>v_actor
   THEN RAISE EXCEPTION 'dynamic_route_replay_conflict'; END IF;
   RETURN p_policy;
 END IF;
 IF EXISTS(SELECT 1 FROM c10_demo.approval_requests WHERE policy_id_v1=p_policy)
 THEN RAISE EXCEPTION 'dynamic_route_policy_already_in_use'; END IF;
 INSERT INTO c10_demo.approval_routes_v1(policy_id,tenant_id,business_id,stages,configured_by,route_key)
 VALUES(p_policy,v_policy.tenant_id,v_policy.business_id,p_stages,v_actor,p_key);
 RETURN p_policy;
END $fn$;

-- All votes are atomic inside the ORIGINAL canonical decide_approval RPC.
-- This generalizes only current stage selection/role check to 3–5 stages.
CREATE OR REPLACE FUNCTION c10_demo.decide_approval(
 p_request bigint,p_action text,p_key text
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
 SET search_path=c10_demo,pg_catalog AS $fn$
DECLARE v_req c10_demo.approval_requests%ROWTYPE;
        v_actor uuid:=c10_demo.actor_uid();
        v_prior c10_demo.approval_events%ROWTYPE;
        v_stages text[];v_next integer;
        v_event bigint;v_delegator uuid;v_can boolean:=false;
        v_required_role text;
BEGIN
 IF v_actor IS NULL OR p_request IS NULL OR p_action NOT IN ('approve','reject','defer')
  OR p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{8,128}$'
 THEN RAISE EXCEPTION 'invalid_approval_command'; END IF;
 SELECT * INTO v_req FROM c10_demo.approval_requests WHERE id=p_request FOR UPDATE;
 IF NOT FOUND OR v_req.created_by=v_actor
 THEN RAISE EXCEPTION 'approval_not_authorized'; END IF;
 IF v_req.policy_id_v1 IS NOT NULL AND NOT EXISTS(
   SELECT 1 FROM c10_demo.approval_policy_versions_v1 p
   WHERE p.id=v_req.policy_id_v1 AND p.tenant_id=v_req.tenant_id
     AND p.business_id=v_req.business_id AND p.version=v_req.policy_version_v1
     AND p.domain=v_req.domain_v1 AND p.action_code=v_req.action_code_v1)
 THEN RAISE EXCEPTION 'approval_policy_pin_invalid'; END IF;
 -- Exact replay is harmless, but detached users do not retain receipt access.
 SELECT * INTO v_prior FROM c10_demo.approval_events
 WHERE request_id=p_request AND idempotency_key=p_key;
 IF FOUND THEN
  IF v_prior.actor_id<>v_actor OR v_prior.action<>p_action
    OR v_prior.tenant_id<>v_req.tenant_id OR v_prior.business_id<>v_req.business_id
  THEN RAISE EXCEPTION 'approval_idempotency_conflict'; END IF;
  IF NOT c10_demo.can_business(v_req.tenant_id,v_req.business_id)
     AND NOT c10_demo.can_tenant(v_req.tenant_id)
  THEN RAISE EXCEPTION 'approval_not_authorized'; END IF;
  RETURN v_prior.id;
 END IF;
 SELECT stages INTO v_stages FROM c10_demo.approval_routes_v1 WHERE policy_id=v_req.policy_id_v1;
 IF FOUND THEN
  SELECT count(*)+1 INTO v_next FROM c10_demo.approval_stage_receipts_v1
   WHERE request_id=p_request;
  IF v_next>cardinality(v_stages) THEN RAISE EXCEPTION 'approval_invalid_transition'; END IF;
  IF EXISTS(SELECT 1 FROM c10_demo.approval_events
    WHERE request_id=p_request AND actor_id=v_actor AND action='approve')
  THEN RAISE EXCEPTION 'approval_repeated_checker'; END IF;
  v_required_role:=v_stages[v_next];
  IF v_required_role='tenant_owner' THEN
    v_can:=c10_demo.can_tenant(v_req.tenant_id);
  ELSIF v_required_role IN ('business_owner','manager') THEN
    -- Build01 valid_until support is optional at this stage: the JSON key is
    -- null in the original A018 seed, and present in the pinned Build01 schema.
    v_can:=c10_demo.can_business(v_req.tenant_id,v_req.business_id) AND EXISTS(
      SELECT 1 FROM c10_demo.business_members m
       WHERE m.tenant_id=v_req.tenant_id AND m.business_id=v_req.business_id
         AND m.user_id=v_actor AND m.role=v_required_role AND m.active
         AND COALESCE(NULLIF(to_jsonb(m)->>'valid_until','')::timestamptz,
                      'infinity'::timestamptz)>statement_timestamp()
    );
    IF NOT v_can AND v_next=1 AND v_required_role='business_owner' THEN
      -- Preserve existing bounded stage-1 delegation, no general new powers.
      SELECT d.granted_by INTO v_delegator
      FROM c10_demo.approval_delegations_v1 d
      JOIN c10_demo.business_members manager
       ON manager.user_id=d.delegated_to AND manager.tenant_id=d.tenant_id
        AND manager.business_id=d.business_id AND manager.active AND manager.role='manager'
        AND COALESCE(NULLIF(to_jsonb(manager)->>'valid_until','')::timestamptz,
                     'infinity'::timestamptz)>statement_timestamp()
      JOIN c10_demo.business_members owner
       ON owner.user_id=d.granted_by AND owner.tenant_id=d.tenant_id
        AND owner.business_id=d.business_id AND owner.active AND owner.role='business_owner'
        AND COALESCE(NULLIF(to_jsonb(owner)->>'valid_until','')::timestamptz,
                     'infinity'::timestamptz)>statement_timestamp()
      WHERE d.request_id=p_request AND d.stage_no=1 AND d.tenant_id=v_req.tenant_id
        AND d.business_id=v_req.business_id AND d.delegated_to=v_actor
        AND d.revoked_at IS NULL AND d.valid_until>clock_timestamp()
        AND c10_demo.can_business(v_req.tenant_id,v_req.business_id);
      v_can:=FOUND;
    END IF;
  END IF;
 ELSE
  v_can:=c10_demo.can_manage(v_req.tenant_id,v_req.business_id);
 END IF;
 IF NOT v_can THEN RAISE EXCEPTION 'approval_not_authorized'; END IF;
 IF v_req.status<>'pending' THEN RAISE EXCEPTION 'approval_invalid_transition'; END IF;
 IF v_req.policy_id_v1 IS NOT NULL AND v_req.expires_at_v1<=clock_timestamp()
 THEN RAISE EXCEPTION 'approval_expired'; END IF;
 -- Non-approve decisions close the request. Intermediate approvals only append
 -- stage events/receipts; the canonical row remains pending until final stage.
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
  VALUES(v_event,p_request,v_req.tenant_id,v_req.business_id,v_next,v_actor,v_delegator);
 END IF;
 RETURN v_event;
END $fn$;

-- Extend the EXISTING security_invoker report; do not add an unscoped view.
CREATE OR REPLACE VIEW c10_demo.approval_status_report_v1
 WITH (security_invoker=true) AS
SELECT q.id AS request_id,q.tenant_id,q.business_id,
 q.domain_v1 AS domain,q.action_code_v1 AS action_code,
 q.source_key_v1 AS source_key,q.source_version_v1 AS source_version,
 q.policy_version_v1 AS policy_version,q.payload_sha256_v1 AS source_fingerprint,
 q.created_by AS requested_by,q.created_at AS requested_at,
 q.expires_at_v1 AS expires_at,q.status AS stored_status,
 CASE WHEN rt.policy_id IS NOT NULL THEN cardinality(rt.stages) ELSE 1 END AS required_checks,
 CASE WHEN rt.policy_id IS NOT NULL THEN sr.stage_count ELSE ae.approval_count END AS completed_checks,
 CASE WHEN q.status='pending' AND q.expires_at_v1<=clock_timestamp() THEN 'expired'
  WHEN q.status='pending' AND rt.policy_id IS NOT NULL
   THEN 'awaiting_stage_'||(sr.stage_count+1)::text
  WHEN q.status='approved' AND er.id IS NOT NULL THEN 'executed'
  WHEN q.status='approved' AND q.domain_v1='demo_stock' THEN 'approved_pending_execution'
  ELSE q.status END AS display_status,
 er.kind AS execution_kind,er.movement_id,er.original_movement_id,er.created_at AS executed_at
FROM c10_demo.approval_requests q
LEFT JOIN c10_demo.approval_routes_v1 rt ON rt.policy_id=q.policy_id_v1
LEFT JOIN LATERAL (
 SELECT count(*)::integer AS stage_count FROM c10_demo.approval_stage_receipts_v1 st
 WHERE st.request_id=q.id) sr ON true
LEFT JOIN LATERAL (
 SELECT count(*)::integer AS approval_count FROM c10_demo.approval_events e
 WHERE e.request_id=q.id AND e.action='approve') ae ON true
LEFT JOIN c10_demo.approval_demo_execution_receipts_v1 er ON er.approval_request_id=q.id
WHERE q.policy_id_v1 IS NOT NULL AND
 (c10_demo.can_manage(q.tenant_id,q.business_id) OR
 (q.created_by=c10_demo.actor_uid() AND c10_demo.can_business(q.tenant_id,q.business_id)));
REVOKE ALL ON c10_demo.approval_status_report_v1 FROM PUBLIC,anon;
GRANT SELECT ON c10_demo.approval_status_report_v1 TO authenticated;
REVOKE ALL ON FUNCTION c10_demo.configure_approval_route_dynamic_v2(bigint,text[],text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION c10_demo.configure_approval_route_dynamic_v2(bigint,text[],text) TO authenticated;