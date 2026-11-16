-- Rollback GOV-002 A008 base after future GOV-002 extensions are rolled back.
DROP TRIGGER approval_event_immutable_v1 ON core10.approval_events;
DROP TRIGGER approval_to_canonical_audit_v1 ON core10.approval_events;
DROP FUNCTION core10._immutable_approval_event_v1();
DROP FUNCTION core10._approval_to_canonical_audit_v1();
DROP FUNCTION core10.decide_approval(bigint,text,text);
DROP POLICY approval_event_read ON core10.approval_events;
DROP POLICY approval_request_read ON core10.approval_requests;
DROP TABLE core10.approval_events;
DROP TABLE core10.approval_requests;
