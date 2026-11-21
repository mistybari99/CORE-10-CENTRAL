-- NP03B+NP06 0406: real canonical Sales Invoice -> Money -> AR.
-- Only disposable synthetic PG17. The invoice is internal/tax-zero, without Stock.
\set ON_ERROR_STOP on
BEGIN;
\ir ../np03b/fixtures.sql
CREATE SCHEMA bridge_test;
GRANT USAGE ON SCHEMA bridge_test TO authenticated;
CREATE FUNCTION bridge_test.ok(ok boolean,label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'BRIDGE_ASSERT:%',label; END IF; END $$;
CREATE FUNCTION bridge_test.denies(sql text,prefix text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 BEGIN EXECUTE sql;
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM LIKE prefix||'%' THEN RETURN; END IF;
  RAISE EXCEPTION 'BRIDGE_WRONG_ERROR wanted=% got=%',prefix,SQLERRM;
 END;
 RAISE EXCEPTION 'BRIDGE_UNEXPECTEDLY_ACCEPTED:%',prefix;
END $$;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA bridge_test TO authenticated;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
SELECT core10.control_set_v1(101,NULL,'sales.order_draft',true,0::smallint,
 '{}'::jsonb,NULL,false,0,'Synthetic integrated Sales Money','bridgeOrderCtl01');
SELECT core10.control_set_v1(101,NULL,'sales.order_transition',true,0::smallint,
 '{}'::jsonb,NULL,false,0,'Synthetic integrated Sales Money','bridgeConfirmCtl1');
SELECT core10.control_set_v1(101,NULL,'sales.invoice_draft',true,0::smallint,
 '{}'::jsonb,NULL,false,0,'Synthetic integrated Sales Money','bridgeDraftCtl01');
SELECT core10.control_set_v1(101,NULL,'sales.invoice_validate',true,0::smallint,
 '{}'::jsonb,NULL,false,0,'Synthetic integrated Sales Money','bridgeValidCtl01');
SELECT core10.control_set_v1(101,NULL,'finance.sales_invoice_issue',true,0::smallint,
 '{}'::jsonb,NULL,false,0,'Synthetic internal invoice','bridgeIssueCtl01');
SELECT core10.control_set_v1(101,NULL,'finance.arap_link',true,0::smallint,
 '{}'::jsonb,NULL,false,0,'Synthetic bridge receivable','bridgeLinkCtl001');
SELECT core10.control_set_v1(101,NULL,'finance.arap_control_account',true,0::smallint,
 '{}'::jsonb,NULL,false,0,'Synthetic designated AR','bridgeTradeCtl01');
SELECT core10.finance_set_period_v1(101,'BDT','2026-11-01',true,'bridgePeriod001');
SELECT core10.finance_create_account_v1(101,'1110','Bridge trade AR',NULL,'asset',NULL,'BDT') ar_acct \gset
SELECT core10.finance_create_account_v1(101,'4100','Bridge sales revenue',NULL,'income',NULL,'BDT') revenue_acct \gset
SELECT core10.finance_create_account_v1(101,'1000','Bridge cash',NULL,'asset',NULL,'BDT') cash_acct \gset
SELECT core10.finance_register_arap_control_account_v1(:ar_acct,'ar','bridgeArTrade01');

SELECT core10.save_sales_order_v1(101,1001,NULL,0,
 '{"customer_id":7001,"price_list_id":7101,"currency":"BDT",
 "lines":[{"item_id":8101,"variant_id":7301,"uom_id":7201,
 "quantity":2,"unit_price":300,"discount_percent":0,"tax_percent":0}]}'::jsonb,
 'bridgeSaveOrder01') receipt \gset
SELECT (:'receipt'::jsonb->>'order_id')::bigint order_id \gset
SELECT core10.transition_sales_order_v1(
 101,1001,:order_id,'confirm',1,NULL,'bridgeConfirm001');
SELECT core10.save_sales_invoice_draft_v1(
 101,1001,NULL,0,:order_id,2,NULL,'Internal BDT tax-zero','bridgeInvoice01') receipt \gset
SELECT (:'receipt'::jsonb->>'invoice_id')::bigint invoice_id \gset

-- Neither an unvalidated invoice nor a positive-stage Finance policy can
-- silently create an AR entry from a Sales draft.
SELECT core10.control_set_v1(101,NULL,'finance.journal_post',true,0::smallint,
 '{"max_post_amount":2000}'::jsonb,NULL,false,0,
 'Zero-stage synthetic posting for isolated bridge','bridgeFinanceCtl01');
SELECT bridge_test.denies(format(
 'SELECT core10.finance_issue_sales_invoice_v1(%s,%s,%s,%L,%L,%L)',
 :invoice_id,:ar_acct,:revenue_acct,'2026-11-21','2026-12-15','bridgeIssue001'),
 'FIN_SALES_SOURCE_NOT_VALIDATED');
SELECT bridge_test.ok(
 (SELECT count(*)=0 FROM core10.finance_journals_v1
  WHERE source_domain='sales_invoice'),
 'no Money entry from unvalidated Sales source');
SELECT core10.validate_sales_invoice_draft_v1(
 101,1001,:invoice_id,1,NULL,'bridgeValidate001');
SELECT core10.control_set_v1(101,NULL,'finance.journal_post',true,1::smallint,
 '{"max_post_amount":2000}'::jsonb,NULL,false,1,
 'Positive stage cannot bypass canonical approval adapter','bridgePostStaged');
SELECT bridge_test.denies(format(
 'SELECT core10.finance_issue_sales_invoice_v1(%s,%s,%s,%L,%L,%L)',
 :invoice_id,:ar_acct,:revenue_acct,'2026-11-21','2026-12-15','bridgeIssue001'),
 'FIN_SALES_STAGED_POST_NOT_CONNECTED');
SELECT core10.control_set_v1(101,NULL,'finance.journal_post',true,0::smallint,
 '{"max_post_amount":2000}'::jsonb,NULL,false,2,
 'Owner permits bounded synthetic posting','bridgePostZero02');

-- Structural category (asset) alone is insufficient; must be designated AR.
SELECT bridge_test.denies(format(
 'SELECT core10.finance_issue_sales_invoice_v1(%s,%s,%s,%L,%L,%L)',
 :invoice_id,:cash_acct,:revenue_acct,'2026-11-21','2026-12-15','bridgeIssue001'),
 'FIN_SALES_ACCOUNT_NOT_DESIGNATED');

SELECT core10.finance_issue_sales_invoice_v1(
 :invoice_id,:ar_acct,:revenue_acct,'2026-11-21','2026-12-15',
 'bridgeIssue001') issue_receipt \gset
SELECT (:'issue_receipt'::jsonb->>'journal_id')::bigint journal_id \gset
SELECT (:'issue_receipt'::jsonb->>'ar_link_id')::bigint ar_link_id \gset
SELECT bridge_test.ok(
 core10.finance_issue_sales_invoice_v1(
  :invoice_id,:ar_acct,:revenue_acct,'2026-11-21','2026-12-15',
  'bridgeIssue001') = :'issue_receipt'::jsonb,
 'exact issue replay keeps same journal, audit and AR item');
SELECT bridge_test.denies(format(
 'SELECT core10.finance_issue_sales_invoice_v1(%s,%s,%s,%L,%L,%L)',
 :invoice_id,:ar_acct,:revenue_acct,'2026-11-21','2026-12-15','bridgeIssueNew01'),
 'FIN_SALES_ALREADY_ISSUED');
SELECT bridge_test.ok(
 (SELECT count(*)=1 FROM core10.finance_sales_issues_v1
 WHERE invoice_id=:invoice_id AND journal_id=:journal_id
 AND amount=600 AND customer_id=7001),
 'immutable issued invoice maps to one existing Money journal');
SELECT bridge_test.ok(
 (SELECT status='posted' AND source_domain='sales_invoice'
 AND source_ref='invoice-'||:invoice_id FROM core10.finance_journals_v1
 WHERE id=:journal_id),
 'existing canonical Money ledger contains exactly one attested source journal');
SELECT bridge_test.ok(
 (SELECT count(*)=2 AND sum(amount) FILTER(WHERE side='debit')=600
  AND sum(amount) FILTER(WHERE side='credit')=600
  FROM core10.finance_journal_lines_v1 WHERE journal_id=:journal_id),
 'balanced Dr AR / Cr revenue without shadow balance');
SELECT bridge_test.ok(
 (SELECT kind='ar' AND party_id=7001 AND account_id=:ar_acct
 AND journal_id=:journal_id FROM core10.finance_arap_links_v1 WHERE id=:ar_link_id),
 'AR linked to same posted Money, canonical Master customer and designated CoA');
SELECT bridge_test.ok(
 (SELECT count(*)=1 FROM core10.canonical_audit_events_v1
 WHERE action='sales.invoice_issued' AND business_id=101
 AND (payload->>'journal_id')::bigint=:journal_id),
 'one issued receipt in canonical Audit chain');

-- A posted Sales Invoice is frozen even to privileged SQL.
RESET ROLE;
SELECT bridge_test.denies(format(
 'UPDATE core10.sales_invoice_drafts_v1 SET total=100 WHERE id=%s',:invoice_id),
 'FIN_SALES_ISSUED_SOURCE_IMMUTABLE');
SELECT bridge_test.denies(format(
 'DELETE FROM core10.sales_invoice_draft_lines_v1 WHERE invoice_id=%s',:invoice_id),
 'FIN_SALES_ISSUED_SOURCE_IMMUTABLE');
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
SELECT bridge_test.ok(
 (core10.verify_canonical_audit_v1(101)->>'ok')::boolean,
 'canonical Audit integrity after Sales, Money and AR');
SELECT bridge_test.ok(
 (:'issue_receipt'::jsonb->>'stock_posted')::boolean IS FALSE,
 'stock/COGS NOT CONNECTED is explicit');
SELECT 'NP06_SALES_FINANCE_0406_INVOICE_MONEY_AR_E2E_PASS' result;
ROLLBACK;
