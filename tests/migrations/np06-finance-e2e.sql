-- NP06 / B-013: synthetic finance security and accounting proof (PostgreSQL 17).
-- All fixture writes are rolled back; never execute against a hosted database.
\set ON_ERROR_STOP on
BEGIN;
INSERT INTO core10.templates(code,source_status,demo_allowed)
 VALUES ('sweets_bakery','available',true) ON CONFLICT (code) DO NOTHING;
INSERT INTO core10.tenants(id,slug) VALUES (951,'np06-tenant-a'),(952,'np06-tenant-b');
INSERT INTO core10.legal_entities(id,tenant_id,label)
 VALUES (9510,951,'Finance Demo A'),(9520,952,'Finance Demo B');
INSERT INTO core10.businesses(id,tenant_id,legal_entity_id,slug,template_code,request_key)
 VALUES (9511,951,9510,'np06-demo-a','sweets_bakery','np06-business-a'),
        (9521,952,9520,'np06-demo-b','sweets_bakery','np06-business-b');
INSERT INTO core10.sites(id,tenant_id,business_id,kind,label,request_key)
 VALUES(9512,951,9511,'showroom','Demo Cash Counter','np06-site-a');
INSERT INTO core10.tenant_members(tenant_id,user_id,role) VALUES
 (951,'91111111-1111-4111-8111-111111111111','tenant_owner'),
 (952,'95555555-5555-4555-8555-555555555555','tenant_owner');
INSERT INTO core10.business_members(tenant_id,business_id,user_id,role) VALUES
 (951,9511,'92222222-2222-4222-8222-222222222222','business_owner'),
 (951,9511,'93333333-3333-4333-8333-333333333333','manager'),
 (951,9511,'94444444-4444-4444-8444-444444444444','investor');

CREATE SCHEMA np06_test;
GRANT USAGE ON SCHEMA np06_test TO authenticated;
CREATE FUNCTION np06_test.as_user(p_uuid text) RETURNS void LANGUAGE sql AS $$
 SELECT set_config('request.jwt.claims',json_build_object('sub',p_uuid)::text,true),
        set_config('request.jwt.claim.sub',p_uuid,true) $$;
CREATE FUNCTION np06_test.ok(p_true boolean,p_msg text) RETURNS void LANGUAGE plpgsql AS $$
 BEGIN IF p_true IS DISTINCT FROM true THEN RAISE EXCEPTION 'FIN_ASSERT_FAILED:%',p_msg; END IF; END $$;
CREATE FUNCTION np06_test.expect(p_sql text,p_prefix text) RETURNS void LANGUAGE plpgsql AS $$
 BEGIN
  BEGIN EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
   IF SQLERRM LIKE p_prefix||'%' THEN RETURN; END IF;
   RAISE EXCEPTION 'FIN_WRONG_ERROR expected=% got=% query=%',p_prefix,SQLERRM,left(p_sql,100);
  END;
  RAISE EXCEPTION 'FIN_EXPECTED_DENIAL:%',p_prefix;
 END $$;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA np06_test TO authenticated;
SET LOCAL ROLE authenticated;
SELECT np06_test.as_user('91111111-1111-4111-8111-111111111111');

SELECT core10.finance_create_account_v1(9511,'1000','Cash','নগদ','asset',NULL,'BDT') cash_id \gset
SELECT core10.finance_create_account_v1(9511,'3000','Equity','মূলধন','equity',NULL,'BDT') equity_id \gset
SELECT core10.finance_create_account_v1(9511,'1100','Receivables','প্রাপ্য','asset',NULL,'BDT') ar_id \gset
SELECT np06_test.ok((SELECT count(*)=3 FROM core10.finance_accounts_v1 WHERE business_id=9511),
 'CoA scoped account count');
SELECT np06_test.expect(
 $$SELECT core10.finance_create_account_v1(9511,'1000','Duplicate','দ্বিতীয়','asset',NULL,'BDT')$$,
 'duplicate key value violates unique constraint');
SELECT np06_test.expect(
 format($q$SELECT core10.finance_create_account_v1(9511,'1001','Wrong parent','ভুল','expense',%s,'BDT')$q$,:cash_id),
 'FIN_PARENT_SCOPE_OR_TYPE');
SELECT np06_test.ok(NOT EXISTS (SELECT 1 FROM core10.finance_accounts_v1
 WHERE business_id=9521),'foreign accounts not leaked');

-- No DML grants for authenticated, and no function EXECUTE for anon/PUBLIC.
SELECT np06_test.expect(
 $$UPDATE core10.finance_accounts_v1 SET active=false WHERE business_id=9511$$,'permission denied');
SELECT np06_test.ok(NOT has_function_privilege('anon','core10.finance_post_journal_v1(bigint,text)','EXECUTE'),
 'anon cannot call post');
SELECT np06_test.ok(NOT has_function_privilege('public','core10.finance_post_journal_v1(bigint,text)','EXECUTE'),
 'PUBLIC cannot call post');

SELECT core10.finance_set_period_v1(9511,'BDT','2026-11-01',true,'periodopen001');
SELECT np06_test.ok((SELECT is_open FROM core10.finance_periods_v1
 WHERE business_id=9511 AND currency='BDT' AND month_start='2026-11-01'),'period opened');
SELECT core10.finance_draft_journal_v1(
 9511,9512,'BDT','2026-11-16','manual','cash-capital-001','draft0001',
 jsonb_build_array(
  jsonb_build_object('account_id',:cash_id,'side','debit','amount',500),
  jsonb_build_object('account_id',:equity_id,'side','credit','amount',500))) journal_id \gset
SELECT np06_test.ok(core10.finance_draft_journal_v1(
 9511,9512,'BDT','2026-11-16','manual','cash-capital-001','draft0001',
 jsonb_build_array(
  jsonb_build_object('account_id',:cash_id,'side','debit','amount',500),
  jsonb_build_object('account_id',:equity_id,'side','credit','amount',500)))=:journal_id,
 'idempotent draft replay');
SELECT np06_test.expect(format(
 $q$SELECT core10.finance_draft_journal_v1(9511,9512,'BDT','2026-11-16','manual',
 'cash-capital-001','draft0001','[{"account_id":%s,"side":"debit","amount":1},
 {"account_id":%s,"side":"credit","amount":1}]'::jsonb)$q$,:cash_id,:equity_id),
 'FIN_IDEMPOTENCY_CONFLICT');

SELECT core10.finance_draft_journal_v1(
 9511,NULL,'BDT','2026-11-16','manual','unbalanced-001','draft0002',
 jsonb_build_array(
  jsonb_build_object('account_id',:cash_id,'side','debit','amount',900),
  jsonb_build_object('account_id',:equity_id,'side','credit','amount',800))) bad_id \gset
SELECT np06_test.expect(format('SELECT core10.finance_validate_journal_v1(%s)',:bad_id),'FIN_UNBALANCED');
SELECT np06_test.ok((SELECT status='draft' FROM core10.finance_journals_v1 WHERE id=:bad_id),
 'unbalanced stays draft');
SELECT np06_test.ok(core10.finance_validate_journal_v1(:journal_id)=:journal_id,
 'balanced validates');
SELECT np06_test.ok((SELECT status='validated' FROM core10.finance_journals_v1 WHERE id=:journal_id),
 'validated state persisted');

-- Default Owner approval stages = 1: no finance approval adapter exists, so posting DENIED.
SELECT np06_test.expect(format(
 'SELECT core10.finance_post_journal_v1(%s,%L)',:journal_id,'postkey0001'),
 'FIN_APPROVAL_NOT_CONNECTED');
SELECT np06_test.ok((SELECT status='validated' FROM core10.finance_journals_v1 WHERE id=:journal_id),
 'not posted without approval');

-- Owner explicitly sets stages=0 for the permitted synthetic manual posting flow.
SELECT core10.control_set_v1(9511,NULL,'finance.journal_post',true,0::smallint,
 '{"max_post_amount":1000}'::jsonb,NULL,false,0,'Owner permits synthetic manual posting','fincontrol0001');
SELECT np06_test.ok(core10.finance_post_journal_v1(:journal_id,'postkey0001')=:journal_id,
 'balanced journal posted');
SELECT np06_test.ok(core10.finance_post_journal_v1(:journal_id,'postkey0001')=:journal_id,
 'idempotent post replay');
SELECT np06_test.expect(format(
 'SELECT core10.finance_post_journal_v1(%s,%L)',:journal_id,'differentkey1'),'FIN_ALREADY_POSTED');
SELECT np06_test.ok((SELECT status='posted' AND audit_event_id IS NOT NULL
  FROM core10.finance_journals_v1 WHERE id=:journal_id),'posted journal has canonical audit receipt');
SELECT np06_test.ok((SELECT count(*)=2 FROM core10.finance_journal_lines_v1
 WHERE journal_id=:journal_id),'exactly two immutable lines');

SELECT core10.finance_draft_journal_v1(
 9511,NULL,'BDT','2026-11-16','manual','amount-limit-001','draft0003',
 jsonb_build_array(
  jsonb_build_object('account_id',:cash_id,'side','debit','amount',1500),
  jsonb_build_object('account_id',:equity_id,'side','credit','amount',1500))) limit_id \gset
SELECT core10.finance_validate_journal_v1(:limit_id);
SELECT np06_test.expect(format('SELECT core10.finance_post_journal_v1(%s,%L)',:limit_id,
 'amountpost001'),'FIN_AMOUNT_LIMIT');

SELECT core10.finance_draft_journal_v1(
 9511,NULL,'BDT','2026-11-16','manual','closed-period-001','draft0004',
 jsonb_build_array(
  jsonb_build_object('account_id',:cash_id,'side','debit','amount',40),
  jsonb_build_object('account_id',:equity_id,'side','credit','amount',40))) closed_id \gset
SELECT core10.finance_validate_journal_v1(:closed_id);
SELECT core10.finance_set_period_v1(9511,'BDT','2026-11-01',false,'periodclose01');
SELECT np06_test.expect(format('SELECT core10.finance_post_journal_v1(%s,%L)',
 :closed_id,'closedpost01'),'FIN_PERIOD_CLOSED');

-- Owner disabled feature = clear server-side denial, independently of menu visibility.
SELECT core10.control_set_v1(9511,NULL,'finance.journal_post',false,0::smallint,
 '{"max_post_amount":1000}'::jsonb,NULL,false,1,
 'Owner pauses all finance posting','fincontrol0002');
SELECT np06_test.expect(format('SELECT core10.finance_post_journal_v1(%s,%L)',
 :closed_id,'disabledpost01'),'CONTROL_DISABLED:finance.journal_post');

-- DEC-08 / 0103 evidence: ALL six mapped state-changing RPCs obey Owner switch-off.
SELECT core10.control_set_v1(9511,NULL,'finance.coa',false,0::smallint,
 '{}'::jsonb,NULL,false,0,'Owner disables account configuration','coaoff0001');
SELECT np06_test.expect(
 $$SELECT core10.finance_create_account_v1(9511,'8810','Disabled Account',NULL,'asset',NULL,'BDT')$$,
 'CONTROL_DISABLED:finance.coa');
SELECT np06_test.expect(format('SELECT core10.finance_set_account_active_v1(%s,false)',:cash_id),
 'CONTROL_DISABLED:finance.coa');
SELECT core10.control_set_v1(9511,NULL,'finance.period_manage',false,0::smallint,
 '{}'::jsonb,NULL,false,0,'Owner disables period administration','periodoff0001');
SELECT np06_test.expect(
 $$SELECT core10.finance_set_period_v1(9511,'BDT','2026-11-01',true,'deniedperiod01')$$,
 'CONTROL_DISABLED:finance.period_manage');
SELECT core10.control_set_v1(9511,NULL,'finance.journal_draft',false,0::smallint,
 '{}'::jsonb,NULL,false,0,'Owner disables finance drafts','draftoff0001');
SELECT np06_test.expect(format(
 $$SELECT core10.finance_draft_journal_v1(9511,NULL,'BDT','2026-11-16',
 'manual','disabled-draft-001','denyDraft001',
 '[{"account_id":%s,"side":"debit","amount":2},{"account_id":%s,"side":"credit","amount":2}]'::jsonb)$$,
 :cash_id,:equity_id),'CONTROL_DISABLED:finance.journal_draft');
SELECT core10.control_set_v1(9511,NULL,'finance.journal_validate',false,0::smallint,
 '{}'::jsonb,NULL,false,0,'Owner disables journal validation','validateoff001');
SELECT np06_test.expect(format('SELECT core10.finance_validate_journal_v1(%s)',:bad_id),
 'CONTROL_DISABLED:finance.journal_validate');

-- Auth: manager, investor, foreign tenant, unassigned and signed-out all DENIED.
SELECT np06_test.as_user('93333333-3333-4333-8333-333333333333');
SELECT np06_test.expect(format('SELECT core10.finance_post_journal_v1(%s,%L)',
 :closed_id,'managerpost01'),'FIN_AUTH_DENIED');
SELECT np06_test.as_user('94444444-4444-4444-8444-444444444444');
SELECT np06_test.expect(
 $$SELECT core10.finance_create_account_v1(9511,'9999','Unauthorized','নেই','asset',NULL,'BDT')$$,
 'FIN_AUTH_DENIED');
SELECT np06_test.as_user('95555555-5555-4555-8555-555555555555');
SELECT np06_test.ok((SELECT count(*)=0 FROM core10.finance_accounts_v1),
 'cross tenant RLS hides accounts');
SELECT np06_test.ok((SELECT count(*)=0 FROM core10.finance_journals_v1),
 'cross tenant RLS hides journals');
SELECT np06_test.expect(format('SELECT core10.finance_validate_journal_v1(%s)',:closed_id),
 'FIN_AUTH_DENIED');
SELECT np06_test.as_user('99999999-9999-4999-8999-999999999999');
SELECT np06_test.expect(format('SELECT core10.finance_validate_journal_v1(%s)',:closed_id),
 'FIN_AUTH_DENIED');

-- Canonical audit chain: account configuration, period change, draft, validate, post.
SELECT np06_test.as_user('91111111-1111-4111-8111-111111111111');
SELECT np06_test.ok((core10.verify_canonical_audit_v1(9511)->>'ok')::boolean,
 'canonical audit chain intact');
SELECT np06_test.ok((SELECT count(*)>=1 FROM core10.canonical_audit_events_v1
 WHERE business_id=9511 AND source_domain='finance' AND action='finance.journal_post'),
 'posted receipt visible in single audit stream');

-- Immutable posted journal and all lines even to privileged accidental DML.
RESET ROLE;
SELECT np06_test.expect(format('UPDATE core10.finance_journals_v1 SET status=%L WHERE id=%s',
 'validated',:journal_id),'FIN_POSTED_IMMUTABLE');
SELECT np06_test.expect(format('DELETE FROM core10.finance_journal_lines_v1 WHERE journal_id=%s',
 :journal_id),'FIN_LINES_APPEND_ONLY');
SELECT np06_test.expect('TRUNCATE core10.finance_journals_v1 CASCADE','FIN_IMMUTABLE');
SELECT np06_test.expect('TRUNCATE core10.finance_journal_lines_v1','FIN_IMMUTABLE');

SELECT 'NP06_PG17_SYNTHETIC_SECURITY_OK' AS result;
ROLLBACK;
