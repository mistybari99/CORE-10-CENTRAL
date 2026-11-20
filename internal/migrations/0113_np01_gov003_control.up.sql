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
