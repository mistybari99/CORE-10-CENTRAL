-- 0405 rollback refuses approved Finance posting or outstanding GOV002 history.
DO $guard$ BEGIN
 IF EXISTS(SELECT 1 FROM core10.approval_requests
  WHERE domain_v1='finance' AND action_code_v1='post'
  AND source_key_v1 LIKE 'finance:journal:%:post')
 OR EXISTS(SELECT 1 FROM core10.canonical_audit_events_v1
  WHERE action='finance.journal_post' AND payload ? 'approval_request_id')
 THEN RAISE EXCEPTION 'FIN_GOV002_ROLLBACK_DENIED_HISTORY'; END IF;
END $guard$;
REVOKE EXECUTE ON FUNCTION
 core10.finance_request_post_approval_v1(bigint,text),
 core10.finance_post_approved_journal_v1(bigint,text,bigint)
 FROM PUBLIC,authenticated;
DROP FUNCTION core10.finance_post_approved_journal_v1(bigint,text,bigint);
DROP FUNCTION core10.finance_request_post_approval_v1(bigint,text);
DROP FUNCTION core10._finance_post_approval_payload_v1(bigint);
DELETE FROM core10.control_rpc_map_v1 WHERE lane='ChatGPT' AND board_row='B-013'
 AND rpc_name IN('finance_request_post_approval_v1','finance_post_approved_journal_v1');
