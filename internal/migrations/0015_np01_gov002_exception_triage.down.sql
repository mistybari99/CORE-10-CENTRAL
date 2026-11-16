-- 0015 rollback on disposable database only; removes non-posting exception triage.
DROP VIEW IF EXISTS core10.approval_exception_inbox_v1;
DROP TRIGGER IF EXISTS np01_exception_event_immutable_v1 ON core10.approval_exception_events_v1;
DROP TRIGGER IF EXISTS np01_exception_event_no_truncate_v1 ON core10.approval_exception_events_v1;
DROP TRIGGER IF EXISTS np01_exception_state_no_truncate_v1 ON core10.approval_exception_escalations_v1;
DROP TRIGGER IF EXISTS np01_exception_to_canonical_audit_v1 ON core10.approval_exception_events_v1;
DROP FUNCTION IF EXISTS core10._deny_np01_exception_event_mutation_v1();
DROP FUNCTION IF EXISTS core10._exception_to_canonical_audit_v1();
DROP FUNCTION IF EXISTS core10.withdraw_approval_exception_v1(bigint,text);
DROP FUNCTION IF EXISTS core10.decide_approval_exception_v1(bigint,text,text);
DROP FUNCTION IF EXISTS core10.request_approval_exception_v1(bigint,text,text,integer,text);
DROP TABLE IF EXISTS core10.approval_exception_events_v1;
DROP TABLE IF EXISTS core10.approval_exception_escalations_v1;
