-- NP06 / 0401 rollback: never discard posted reversal, audit or Owner settings.
-- The reversal ledger is a pointer to the existing canonical journal, not an
-- alternate accounting ledger. Only safe on an empty disposable database.
DO $guard$ BEGIN
 IF EXISTS(SELECT 1 FROM core10.finance_reversals_v1)
 OR EXISTS(SELECT 1 FROM core10.finance_journals_v1 WHERE source_domain='finance_reversal')
 OR EXISTS(SELECT 1 FROM core10.canonical_audit_events_v1 WHERE action='finance.journal_reverse')
 OR EXISTS(SELECT 1 FROM core10.control_setting_versions_v1 WHERE feature_key='finance.journal_reverse')
 OR EXISTS(SELECT 1 FROM core10.control_overrides_v1 WHERE feature_key='finance.journal_reverse')
 THEN RAISE EXCEPTION 'FIN_REVERSAL_ROLLBACK_DENIED_HISTORY'; END IF;
END $guard$;

DROP FUNCTION core10.finance_reverse_posted_journal_v1(bigint,date,text,text);
DROP TABLE core10.finance_reversals_v1;
DROP FUNCTION core10._finance_reversal_immutable_v1();
DELETE FROM core10.control_rpc_map_v1 WHERE
 rpc_name='finance_reverse_posted_journal_v1' AND lane='ChatGPT' AND board_row='B-013';
DELETE FROM core10.control_catalog_v1
 WHERE feature_key='finance.journal_reverse' AND pack='NP06';
