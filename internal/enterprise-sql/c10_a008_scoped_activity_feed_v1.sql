-- GOV-002 additive scoped activity feed for a future guided inbox/UI.
-- Read-only SECURITY INVOKER, no email/SMS/push delivery, no raw payload,
-- exception reason, role claims or payment/stock effect.
-- Run after c10_a008_bounded_exception_escalation_v1.sql in disposable PG17.
CREATE VIEW c10_demo.approval_activity_feed_v1
WITH (security_invoker=true) AS
SELECT
 ('approval:'||ev.id)::text AS activity_id,
 ev.tenant_id,ev.business_id,ev.request_id,
 q.domain_v1 AS domain,q.action_code_v1 AS action_code,
 q.source_key_v1 AS source_key,q.source_version_v1 AS source_version,
 q.created_by AS request_maker,ev.actor_id AS event_actor,
 'approval'::text AS activity_type,
 ev.action AS action,
 NULL::text AS severity,
 ev.created_at AS occurred_at,
 q.status AS approval_status
FROM c10_demo.approval_events ev
JOIN c10_demo.approval_requests q ON q.id=ev.request_id
 WHERE q.policy_id_v1 IS NOT NULL
 AND ev.tenant_id=q.tenant_id AND ev.business_id=q.business_id
 AND (
  c10_demo.can_manage(q.tenant_id,q.business_id)
  OR (q.created_by=c10_demo.actor_uid()
    AND c10_demo.can_business(q.tenant_id,q.business_id))
 )
UNION ALL
SELECT
 ('exception:'||ev.id)::text AS activity_id,
 ev.tenant_id,ev.business_id,ev.request_id,
 q.domain_v1 AS domain,q.action_code_v1 AS action_code,
 q.source_key_v1 AS source_key,q.source_version_v1 AS source_version,
 q.created_by AS request_maker,ev.actor_id AS event_actor,
 'exception'::text AS activity_type,
 ev.action AS action,
 esc.severity AS severity,
 ev.created_at AS occurred_at,
 q.status AS approval_status
FROM c10_demo.approval_exception_events_v1 ev
JOIN c10_demo.approval_exception_escalations_v1 esc
 ON esc.id=ev.escalation_id
JOIN c10_demo.approval_requests q ON q.id=ev.request_id
WHERE ev.tenant_id=esc.tenant_id AND ev.business_id=esc.business_id
 AND ev.request_id=esc.request_id
 AND esc.policy_id=q.policy_id_v1
 AND q.tenant_id=esc.tenant_id AND q.business_id=esc.business_id
 AND (
  c10_demo.can_manage(q.tenant_id,q.business_id)
  OR (q.created_by=c10_demo.actor_uid()
    AND c10_demo.can_business(q.tenant_id,q.business_id))
 );
REVOKE ALL ON c10_demo.approval_activity_feed_v1 FROM PUBLIC,anon;
GRANT SELECT ON c10_demo.approval_activity_feed_v1 TO authenticated;
-- Consumers MUST filter/paginate the authorized server-side projection.
-- Client export formatting does not replace server RLS or signed auth.
