-- NP06/B-013 0403: no removal of trace/reversal fences with recorded AR/AP
-- source links, allocation or audit history. Empty PG17 down/up remains allowed.
DO $guard$ BEGIN
 IF EXISTS (SELECT 1 FROM core10.finance_arap_links_v1)
 OR EXISTS (SELECT 1 FROM core10.finance_arap_allocations_v1)
 OR EXISTS (SELECT 1 FROM core10.canonical_audit_events_v1
   WHERE action IN ('finance.arap_link','finance.arap_allocate'))
 OR EXISTS (SELECT 1 FROM core10.control_setting_versions_v1
   WHERE feature_key IN ('finance.arap_link','finance.arap_allocate'))
 THEN RAISE EXCEPTION 'FIN_ARAP_INTEGRITY_ROLLBACK_DENIED_HISTORY'; END IF;
 -- 0403 also protects 0401 reversals from being made unsafe by removing the
 -- allocated-reversal fence. Preserve the existing Finance rollback error for
 -- an already-posted reversal, without modifying 0401 or shared CI history.
 IF EXISTS(SELECT 1 FROM core10.finance_reversals_v1)
 OR EXISTS(SELECT 1 FROM core10.canonical_audit_events_v1
           WHERE action='finance.journal_reverse')
 THEN RAISE EXCEPTION 'FIN_REVERSAL_ROLLBACK_DENIED_HISTORY'; END IF;
END $guard$;

DROP FUNCTION core10.finance_arap_trace_v1(bigint);
DROP TRIGGER finance_arap_settlement_integrity_v1 ON core10.finance_arap_allocations_v1;
DROP FUNCTION core10._finance_arap_settlement_integrity_v1();
DROP TRIGGER finance_arap_no_allocated_reversal_v1 ON core10.finance_reversals_v1;
DROP FUNCTION core10._finance_arap_reversal_allocation_guard_v1();
DROP TRIGGER finance_arap_source_integrity_v1 ON core10.finance_arap_links_v1;
DROP FUNCTION core10._finance_arap_source_integrity_v1();
