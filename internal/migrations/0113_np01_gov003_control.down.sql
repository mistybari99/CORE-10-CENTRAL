-- NP01 / 0113 inverse. Preserve all canonical Audit and existing Owner setting data.
DO $np01$
BEGIN
 IF (SELECT count(*) FROM core10.control_rpc_map_v1
 WHERE rpc_name IN ('gov003_audit_readiness_v1','gov003_audit_risk_v1','gov003_audit_export_v1')
 AND status='enforced' AND feature_key='gov003.review_export'
 AND test_ref='tests/migrations/np01-control-gov003-e2e.sql')<>3 THEN
 RAISE EXCEPTION 'NP01_0113_ROLLBACK_REGISTRY_CONFLICT';
 END IF;
END $np01$;
DELETE FROM core10.control_rpc_map_v1
 WHERE rpc_name IN ('gov003_audit_readiness_v1','gov003_audit_risk_v1','gov003_audit_export_v1')
 AND feature_key='gov003.review_export' AND test_ref='tests/migrations/np01-control-gov003-e2e.sql';

CREATE OR REPLACE FUNCTION core10.gov003_audit_readiness_v1(p_business bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,core10 AS $fn$
DECLARE v_tenant bigint;v_chain jsonb;v_event_count bigint;v_request_count bigint;
BEGIN
 SELECT b.tenant_id INTO v_tenant FROM core10.businesses b WHERE b.id=p_business;
 IF core10.actor_uid() IS NULL OR v_tenant IS NULL
   OR NOT core10.can_manage(v_tenant,p_business)
 THEN RAISE EXCEPTION 'gov003_readiness_denied' USING ERRCODE='42501'; END IF;
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
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,core10 AS $fn$
DECLARE v_tenant bigint;v_chain jsonb;v_declined bigint;
 v_expired bigint;v_open_exceptions bigint;v_events bigint;
BEGIN
 SELECT b.tenant_id INTO v_tenant FROM core10.businesses b WHERE b.id=p_business;
 IF core10.actor_uid() IS NULL OR v_tenant IS NULL
    OR NOT core10.can_manage(v_tenant,p_business)
    OR p_since IS NULL OR p_since>statement_timestamp()
 THEN RAISE EXCEPTION 'gov003_risk_denied' USING ERRCODE='42501'; END IF;
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
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,core10 AS $fn$
DECLARE v_tenant bigint;
BEGIN
 SELECT b.tenant_id INTO v_tenant FROM core10.businesses b WHERE b.id=p_business;
 IF core10.actor_uid() IS NULL OR v_tenant IS NULL
  OR NOT core10.can_manage(v_tenant,p_business)
  OR p_after_seq IS NULL OR p_after_seq<0
  OR p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 500
 THEN RAISE EXCEPTION 'gov003_export_denied' USING ERRCODE='42501'; END IF;
 RETURN QUERY SELECT a.stream_seq,a.source_domain,a.source_ref,
    a.action,a.event_at,a.payload_sha256,a.event_digest
  FROM core10.canonical_audit_events_v1 a
  WHERE a.business_id=p_business AND a.tenant_id=v_tenant
    AND a.stream_seq>p_after_seq
  ORDER BY a.stream_seq LIMIT p_limit;
END $fn$;
