-- S1-c / GOV-002: one canonical, role-scoped reviewer reporting port.
-- Source: isolated GOV002 reporting concepts; no legacy demo view or duplicate store.
-- No direct operational stock/finance posting, no hosted apply without Owner GO.

CREATE FUNCTION core10.my_approval_status_v1(p_business bigint,p_limit integer DEFAULT 100)
RETURNS TABLE (
 request_id bigint,business_id bigint,domain text,action_code text,
 source_key text,source_version bigint,policy_version integer,
 created_at timestamptz,expires_at timestamptz,
 stored_status text,display_status text,required_checks integer,completed_checks integer,
 can_review_now boolean,is_maker boolean
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,core10 AS $fn$
DECLARE tenant bigint;actor uuid:=core10.actor_uid();
BEGIN
 IF actor IS NULL OR p_business IS NULL OR p_limit IS NULL
  OR p_limit NOT BETWEEN 1 AND 100
 THEN RAISE EXCEPTION 'approval_report_denied'; END IF;
 SELECT b.tenant_id INTO tenant FROM core10.businesses b WHERE b.id=p_business;
 IF tenant IS NULL OR NOT (
  core10.can_business(tenant,p_business)
  OR core10.can_tenant(tenant)
  OR core10.can_approval_action_v1(tenant,p_business,'approval.decide'))
 THEN RAISE EXCEPTION 'approval_report_denied'; END IF;
 RETURN QUERY
 SELECT q.id,q.business_id,q.domain_v1,q.action_code_v1,
  q.source_key_v1,q.source_version_v1,q.policy_version_v1,
  q.created_at,q.expires_at_v1,q.status,
  CASE
   WHEN q.status='pending' AND q.expires_at_v1<=statement_timestamp() THEN 'expired'
   WHEN q.status='pending' AND route.policy_id IS NOT NULL
    THEN 'awaiting_stage_'||(rc.completed+1)::text
   ELSE q.status END AS display_status,
  COALESCE(cardinality(route.stages),1)::integer AS required_checks,
  rc.completed,
  (q.status='pending' AND q.expires_at_v1>statement_timestamp()
   AND route.policy_id IS NOT NULL
   AND rc.completed<cardinality(route.stages)
   AND core10._can_review_stage_v1(q.id,rc.completed+1)),
  q.created_by=actor
 FROM core10.approval_requests q
 LEFT JOIN core10.approval_routes_v1 route
  ON route.policy_id=q.policy_id_v1 AND route.tenant_id=q.tenant_id
    AND route.business_id=q.business_id
 CROSS JOIN LATERAL (
  SELECT count(*)::integer AS completed
  FROM core10.approval_stage_receipts_v1 s WHERE s.request_id=q.id
 ) rc
 WHERE q.tenant_id=tenant AND q.business_id=p_business AND q.policy_id_v1 IS NOT NULL
  AND (
   core10.can_manage(q.tenant_id,q.business_id)
   OR (q.created_by=actor AND core10.can_business(q.tenant_id,q.business_id))
   OR (q.status='pending' AND route.policy_id IS NOT NULL
       AND rc.completed<cardinality(route.stages)
       AND core10._can_review_stage_v1(q.id,rc.completed+1))
  )
 ORDER BY q.created_at DESC,q.id DESC LIMIT p_limit;
END $fn$;
REVOKE ALL ON FUNCTION core10.my_approval_status_v1(bigint,integer)
 FROM PUBLIC,authenticated;
GRANT EXECUTE ON FUNCTION core10.my_approval_status_v1(bigint,integer)
 TO authenticated;

-- Activity is projected from the one canonical approval-event journal JOINED
-- to its 0008 canonical audit event, never an extra event/audit store.
-- No payload or actor PII is returned to non-owner reviewer clients.
CREATE FUNCTION core10.my_approval_activity_v1(p_business bigint,p_limit integer DEFAULT 100)
RETURNS TABLE (
 event_id bigint,business_id bigint,request_id bigint,
 action text,occurred_at timestamptz,stage_no integer,
 approval_status text,audit_event_id bigint
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,core10 AS $fn$
DECLARE tenant bigint;actor uuid:=core10.actor_uid();
BEGIN
 IF actor IS NULL OR p_business IS NULL OR p_limit IS NULL
  OR p_limit NOT BETWEEN 1 AND 100
 THEN RAISE EXCEPTION 'approval_report_denied'; END IF;
 SELECT b.tenant_id INTO tenant FROM core10.businesses b WHERE b.id=p_business;
 IF tenant IS NULL OR NOT (
  core10.can_business(tenant,p_business)
  OR core10.can_tenant(tenant)
  OR core10.can_approval_action_v1(tenant,p_business,'approval.export')
  OR core10.can_approval_action_v1(tenant,p_business,'approval.decide'))
 THEN RAISE EXCEPTION 'approval_report_denied'; END IF;
 RETURN QUERY
 SELECT e.id,e.business_id,e.request_id,e.action,e.created_at,
        st.stage_no,q.status,a.id
 FROM core10.approval_events e
 JOIN core10.approval_requests q
   ON q.id=e.request_id AND q.tenant_id=e.tenant_id
   AND q.business_id=e.business_id
 JOIN core10.canonical_audit_events_v1 a
   ON a.source_domain='approval' AND a.source_ref=e.id::text
   AND a.tenant_id=e.tenant_id AND a.business_id=e.business_id
   AND a.action='approval.'||e.action
 LEFT JOIN core10.approval_stage_receipts_v1 st
   ON st.event_id=e.id AND st.request_id=e.request_id
 WHERE e.business_id=p_business AND e.tenant_id=tenant
  AND (
   core10.can_manage(q.tenant_id,q.business_id)
   OR (q.created_by=actor AND core10.can_business(q.tenant_id,q.business_id))
   OR (q.status='pending' AND EXISTS (
     SELECT 1 FROM core10.approval_routes_v1 route
     WHERE route.policy_id=q.policy_id_v1
       AND core10._can_review_stage_v1(q.id,
        (SELECT count(*)::integer+1 FROM core10.approval_stage_receipts_v1 s
          WHERE s.request_id=q.id))
   ))
  )
 ORDER BY e.created_at DESC,e.id DESC LIMIT p_limit;
END $fn$;
REVOKE ALL ON FUNCTION core10.my_approval_activity_v1(bigint,integer)
 FROM PUBLIC,authenticated;
GRANT EXECUTE ON FUNCTION core10.my_approval_activity_v1(bigint,integer)
 TO authenticated;
