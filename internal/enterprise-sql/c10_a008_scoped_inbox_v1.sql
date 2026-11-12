-- C10-GOV-002 scoped approval inbox, disposable PostgreSQL only.
-- Applies AFTER A008 prototype and c10_a008_typed_approval_v1.sql.
-- Business-level data visibility is NOT approval-inbox authorization.
-- Approvers see their authorized businesses; makers see only their own requests.
-- Site-only staff, investors, revoked identities and foreign tenants see no badges.

DROP POLICY approval_request_read ON c10_demo.approval_requests;
CREATE POLICY approval_request_scoped_review_v1
  ON c10_demo.approval_requests FOR SELECT TO authenticated USING (
    c10_demo.can_manage(tenant_id, business_id)
    OR (created_by = c10_demo.actor_uid()
        AND c10_demo.can_business(tenant_id, business_id))
  );

DROP POLICY approval_event_read ON c10_demo.approval_events;
CREATE POLICY approval_event_scoped_review_v1
  ON c10_demo.approval_events FOR SELECT TO authenticated USING (
    c10_demo.can_manage(tenant_id, business_id)
    OR EXISTS (
      SELECT 1 FROM c10_demo.approval_requests r
      WHERE r.id = request_id
        AND r.tenant_id = approval_events.tenant_id
        AND r.business_id = approval_events.business_id
        AND r.created_by = c10_demo.actor_uid()
        AND c10_demo.can_business(r.tenant_id, r.business_id)
    )
  );

CREATE VIEW c10_demo.approval_inbox_v1 WITH (security_invoker = true) AS
SELECT
  r.id AS request_id,
  r.tenant_id,
  r.business_id,
  r.domain_v1 AS domain,
  r.action_code_v1 AS action_code,
  r.source_key_v1 AS source_key,
  r.source_version_v1 AS source_version,
  r.policy_version_v1 AS policy_version,
  r.created_by AS requested_by,
  r.created_at AS requested_at,
  r.expires_at_v1 AS expires_at,
  CASE
    WHEN r.status = 'pending' AND r.expires_at_v1 <= clock_timestamp()
      THEN 'expired'
    ELSE r.status
  END AS display_status
FROM c10_demo.approval_requests r
WHERE r.policy_id_v1 IS NOT NULL
  AND (
    c10_demo.can_manage(r.tenant_id, r.business_id)
    OR (r.created_by = c10_demo.actor_uid()
        AND c10_demo.can_business(r.tenant_id, r.business_id))
  );

REVOKE ALL ON c10_demo.approval_inbox_v1 FROM PUBLIC, anon;
GRANT SELECT ON c10_demo.approval_inbox_v1 TO authenticated;
-- No function allows inbox status, visible count, payload, or permission
-- decisions to be supplied from client-side business/role assertions.
-- Real signed GoTrue and other modules' approval contracts remain release-gated.
