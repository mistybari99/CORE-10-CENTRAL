-- GOV002 read-only stage-specific reviewer task RPC, disposable PG17 ONLY.
-- Must follow canonical A018/A008/routed/threshold/source/report/dynamic route layers.
-- Does not add grants, broaden existing maker/owner RLS, or post domain commands.
CREATE FUNCTION c10_demo.my_routed_review_tasks_v2(p_business bigint)
 RETURNS TABLE (
  request_id bigint,business_id bigint,domain text,action_code text,
  source_key text,source_version bigint,policy_version integer,
  stage_no integer,stage_total integer,expires_at timestamptz
 ) LANGUAGE plpgsql STABLE SECURITY DEFINER
 SET search_path=c10_demo,pg_catalog AS $fn$
DECLARE v_actor uuid:=c10_demo.actor_uid();v_tenant bigint;
BEGIN
 IF v_actor IS NULL OR p_business IS NULL OR p_business<=0
 THEN RAISE EXCEPTION 'reviewer_task_access_denied'; END IF;
 SELECT b.tenant_id INTO v_tenant FROM c10_demo.businesses b WHERE b.id=p_business;
 IF NOT FOUND OR NOT (c10_demo.can_business(v_tenant,p_business)
   OR c10_demo.can_tenant(v_tenant))
 THEN RAISE EXCEPTION 'reviewer_task_access_denied'; END IF;
 RETURN QUERY
 SELECT q.id,q.business_id,q.domain_v1,q.action_code_v1,
  q.source_key_v1,q.source_version_v1,q.policy_version_v1,
  sr.finished+1,cardinality(route.stages),q.expires_at_v1
 FROM c10_demo.approval_requests q
 JOIN c10_demo.approval_routes_v1 route
   ON route.policy_id=q.policy_id_v1 AND route.business_id=q.business_id
    AND route.tenant_id=q.tenant_id
 JOIN c10_demo.approval_policy_versions_v1 policy
   ON policy.id=q.policy_id_v1 AND policy.tenant_id=q.tenant_id
    AND policy.business_id=q.business_id AND policy.version=q.policy_version_v1
 JOIN LATERAL (
  SELECT count(*)::integer AS finished FROM c10_demo.approval_stage_receipts_v1 s
   WHERE s.request_id=q.id) sr ON true
 WHERE q.business_id=p_business AND q.tenant_id=v_tenant
   AND q.policy_id_v1 IS NOT NULL AND q.status='pending'
   AND q.expires_at_v1>statement_timestamp()
   AND q.created_by<>v_actor
   AND sr.finished<cardinality(route.stages)
   AND NOT EXISTS(SELECT 1 FROM c10_demo.approval_events e
     WHERE e.request_id=q.id AND e.actor_id=v_actor AND e.action='approve')
   AND (
    (route.stages[sr.finished+1]='tenant_owner' AND c10_demo.can_tenant(v_tenant))
    OR (route.stages[sr.finished+1] IN ('manager','business_owner')
     AND c10_demo.can_business(v_tenant,p_business) AND EXISTS (
      SELECT 1 FROM c10_demo.business_members m
      WHERE m.tenant_id=v_tenant AND m.business_id=p_business AND m.user_id=v_actor
        AND m.active AND m.role=route.stages[sr.finished+1]
        AND COALESCE(NULLIF(to_jsonb(m)->>'valid_until','')::timestamptz,
                     'infinity'::timestamptz)>statement_timestamp()
     ))
    OR (sr.finished=0 AND route.stages[1]='business_owner'
     AND c10_demo.can_business(v_tenant,p_business)
     AND EXISTS (
      SELECT 1 FROM c10_demo.approval_delegations_v1 d
      JOIN c10_demo.business_members delegate
        ON delegate.user_id=d.delegated_to AND delegate.business_id=d.business_id
          AND delegate.tenant_id=d.tenant_id AND delegate.active AND delegate.role='manager'
          AND COALESCE(NULLIF(to_jsonb(delegate)->>'valid_until','')::timestamptz,
                       'infinity'::timestamptz)>statement_timestamp()
      JOIN c10_demo.business_members grantor
        ON grantor.user_id=d.granted_by AND grantor.business_id=d.business_id
          AND grantor.tenant_id=d.tenant_id AND grantor.active AND grantor.role='business_owner'
          AND COALESCE(NULLIF(to_jsonb(grantor)->>'valid_until','')::timestamptz,
                       'infinity'::timestamptz)>statement_timestamp()
      WHERE d.request_id=q.id AND d.business_id=p_business AND d.tenant_id=v_tenant
        AND d.delegated_to=v_actor AND d.stage_no=1 AND d.revoked_at IS NULL
        AND d.valid_until>statement_timestamp()
     ))
   )
 ORDER BY q.created_at,q.id
 LIMIT 100;
END $fn$;
REVOKE ALL ON FUNCTION c10_demo.my_routed_review_tasks_v2(bigint)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION c10_demo.my_routed_review_tasks_v2(bigint) TO authenticated;