-- NP01 B-005 / 0013 rollback (ONLY on a disposable database).
-- Removes the safety triggers; never deploy this rollback to an operating ledger.
DROP TRIGGER IF EXISTS np01_truncate_guard_01_v1 ON core10.audit_chain_heads_v1;
DROP TRIGGER IF EXISTS np01_truncate_guard_02_v1 ON core10.canonical_audit_events_v1;
DROP TRIGGER IF EXISTS np01_truncate_guard_03_v1 ON core10.access_change_events_v1;
DROP TRIGGER IF EXISTS np01_truncate_guard_04_v1 ON core10.approval_requests;
DROP TRIGGER IF EXISTS np01_truncate_guard_05_v1 ON core10.approval_events;
DROP TRIGGER IF EXISTS np01_truncate_guard_06_v1 ON core10.approval_policy_versions_v1;
DROP TRIGGER IF EXISTS np01_truncate_guard_07_v1 ON core10.approval_routes_v1;
DROP TRIGGER IF EXISTS np01_truncate_guard_08_v1 ON core10.approval_stage_receipts_v1;
DROP TRIGGER IF EXISTS np01_truncate_guard_09_v1 ON core10.approval_delegations_v1;
DROP FUNCTION IF EXISTS core10._deny_np01_journal_truncate_v1();
