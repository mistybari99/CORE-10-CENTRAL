-- GOV002 Additive approval command outcome projection, disposable PG17 only.
-- Scoped, security-invoker and read-only. Not a production reporting API.
-- Requires A008 proto+typed+scoped inbox+routing+threshold+demo source adapter.
-- No approval UI may treat a displayed status as authority to post.

-- Allow the authenticated maker to understand ONLY the route of an approval
-- request which they themselves created, without opening all owner policy rows.
CREATE POLICY approval_route_requester_read_v1
 ON c10_demo.approval_routes_v1 FOR SELECT TO authenticated USING (
  EXISTS(SELECT 1 FROM c10_demo.approval_requests q
    WHERE q.policy_id_v1=approval_routes_v1.policy_id
      AND q.tenant_id=approval_routes_v1.tenant_id
      AND q.business_id=approval_routes_v1.business_id
      AND q.created_by=c10_demo.actor_uid()
      AND c10_demo.can_business(q.tenant_id,q.business_id))
 );

-- Approver + original source maker are already scoped. A separate reversal
-- requester also needs to see the exact audit receipt of their own approval.
CREATE POLICY execution_receipt_requester_read_v1
 ON c10_demo.approval_demo_execution_receipts_v1 FOR SELECT TO authenticated USING (
  EXISTS(SELECT 1 FROM c10_demo.approval_requests q
   WHERE q.id=approval_request_id
     AND q.tenant_id=approval_demo_execution_receipts_v1.tenant_id
     AND q.business_id=approval_demo_execution_receipts_v1.business_id
     AND q.created_by=c10_demo.actor_uid()
     AND c10_demo.can_business(q.tenant_id,q.business_id))
 );

CREATE VIEW c10_demo.approval_status_report_v1
WITH (security_invoker=true) AS
SELECT
 q.id AS request_id,q.tenant_id,q.business_id,
 q.domain_v1 AS domain,q.action_code_v1 AS action_code,
 q.source_key_v1 AS source_key,q.source_version_v1 AS source_version,
 q.policy_version_v1 AS policy_version,
 q.payload_sha256_v1 AS source_fingerprint,
 q.created_by AS requested_by,q.created_at AS requested_at,
 q.expires_at_v1 AS expires_at,q.status AS stored_status,
 CASE WHEN rt.policy_id IS NOT NULL THEN 2 ELSE 1 END AS required_checks,
 CASE WHEN rt.policy_id IS NOT NULL THEN sr.stage_count
      ELSE ae.approval_count END AS completed_checks,
 CASE
   WHEN q.status='pending' AND q.expires_at_v1<=clock_timestamp() THEN 'expired'
   WHEN q.status='pending' AND rt.policy_id IS NOT NULL
     THEN CASE WHEN sr.stage_count=0 THEN 'awaiting_stage_1'
               ELSE 'awaiting_stage_2' END
   WHEN q.status='approved' AND er.id IS NOT NULL THEN 'executed'
   WHEN q.status='approved' AND q.domain_v1='demo_stock' THEN 'approved_pending_execution'
   ELSE q.status
 END AS display_status,
 er.kind AS execution_kind,er.movement_id,er.original_movement_id,
 er.created_at AS executed_at
FROM c10_demo.approval_requests q
LEFT JOIN c10_demo.approval_routes_v1 rt ON rt.policy_id=q.policy_id_v1
LEFT JOIN LATERAL (
 SELECT count(*)::integer AS stage_count
 FROM c10_demo.approval_stage_receipts_v1 st
 WHERE st.request_id=q.id
) sr ON true
LEFT JOIN LATERAL (
 SELECT count(*)::integer AS approval_count
 FROM c10_demo.approval_events e
 WHERE e.request_id=q.id AND e.action='approve'
) ae ON true
LEFT JOIN c10_demo.approval_demo_execution_receipts_v1 er
 ON er.approval_request_id=q.id
WHERE q.policy_id_v1 IS NOT NULL
  AND (
   c10_demo.can_manage(q.tenant_id,q.business_id)
   OR (q.created_by=c10_demo.actor_uid()
       AND c10_demo.can_business(q.tenant_id,q.business_id))
  );
REVOKE ALL ON c10_demo.approval_status_report_v1 FROM PUBLIC,anon;
GRANT SELECT ON c10_demo.approval_status_report_v1 TO authenticated;
-- Security-invoker view preserves underlying request, stages, route and
-- receipt policies. No public/anon or business-invisible row/count access.
