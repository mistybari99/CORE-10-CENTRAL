-- NP06 / 0400 rollback: fail closed on any persisted Finance or canonical audit evidence.
-- Full up/down/up is safe only on an EMPTY disposable test database.
DO $guard$ BEGIN
 IF EXISTS(SELECT 1 FROM core10.finance_accounts_v1) OR
    EXISTS(SELECT 1 FROM core10.finance_periods_v1) OR
    EXISTS(SELECT 1 FROM core10.finance_journals_v1) OR
    EXISTS(SELECT 1 FROM core10.finance_journal_lines_v1) OR
    EXISTS(SELECT 1 FROM core10.canonical_audit_events_v1 WHERE source_domain='finance') OR
    EXISTS(SELECT 1 FROM core10.control_setting_versions_v1
      WHERE feature_key LIKE 'finance.%') OR
    EXISTS(SELECT 1 FROM core10.control_overrides_v1 WHERE feature_key LIKE 'finance.%')
 THEN RAISE EXCEPTION 'FIN_ROLLBACK_DENIED_PERSISTED_HISTORY'; END IF;
END $guard$;

DROP FUNCTION core10.finance_post_journal_v1(bigint,text);
DROP FUNCTION core10.finance_validate_journal_v1(bigint);
DROP FUNCTION core10.finance_draft_journal_v1(bigint,bigint,text,date,text,text,text,jsonb);
DROP FUNCTION core10.finance_set_period_v1(bigint,text,date,boolean,text);
DROP FUNCTION core10.finance_set_account_active_v1(bigint,boolean);
DROP FUNCTION core10.finance_create_account_v1(bigint,text,text,text,text,bigint,text);

DROP TABLE core10.finance_journal_lines_v1;
DROP TABLE core10.finance_journals_v1;
DROP TABLE core10.finance_periods_v1;
DROP TABLE core10.finance_accounts_v1;
DROP FUNCTION core10._finance_journal_immutable_v1();

DELETE FROM core10.control_rpc_map_v1 WHERE lane='ChatGPT' AND board_row='B-013'
 AND rpc_name IN('finance_post_journal_v1','finance_validate_journal_v1',
 'finance_draft_journal_v1','finance_set_period_v1',
 'finance_set_account_active_v1','finance_create_account_v1');
DELETE FROM core10.control_catalog_v1 WHERE pack='NP06' AND feature_key IN
 ('finance.coa','finance.journal_draft','finance.journal_validate',
  'finance.journal_post','finance.period_manage');
