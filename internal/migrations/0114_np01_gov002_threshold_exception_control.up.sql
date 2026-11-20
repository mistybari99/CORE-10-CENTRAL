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
