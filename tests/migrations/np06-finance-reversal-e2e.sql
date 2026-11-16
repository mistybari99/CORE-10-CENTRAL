-- NP06 / 0401: synthetic reversal E2E, denial and immutable double-entry proof.
-- Runs inside ROLLBACK on a disposable PostgreSQL 17 service. No hosted use.
\set ON_ERROR_STOP on
BEGIN;
INSERT INTO core10.templates(code,source_status,demo_allowed)
 VALUES('sweets_bakery','available',true) ON CONFLICT(code) DO NOTHING;
INSERT INTO core10.tenants(id,slug) VALUES(981,'np06-reversal-tenant-a'),(982,'np06-reversal-tenant-b');
INSERT INTO core10.legal_entities(id,tenant_id,label)
 VALUES(9810,981,'Finance reversal A'),(9820,982,'Finance reversal B');
INSERT INTO core10.businesses(id,tenant_id,legal_entity_id,slug,template_code,request_key)
 VALUES(9811,981,9810,'np06-reversal-a','sweets_bakery','np06-rev-biz-a'),
       (9821,982,9820,'np06-reversal-b','sweets_bakery','np06-rev-biz-b');
INSERT INTO core10.sites(id,tenant_id,business_id,kind,label,request_key)
 VALUES(9812,981,9811,'showroom','Reversal Shop','np06-rev-site-a');
INSERT INTO core10.tenant_members(tenant_id,user_id,role)
 VALUES(981,'91111111-1111-4111-8111-111111111111','tenant_owner'),
       (982,'95555555-5555-4555-8555-555555555555','tenant_owner');
INSERT INTO core10.business_members(tenant_id,business_id,user_id,role)
 VALUES(981,9811,'93333333-3333-4333-8333-333333333333','manager');
CREATE SCHEMA np06_rev_test;
GRANT USAGE ON SCHEMA np06_rev_test TO authenticated;
CREATE FUNCTION np06_rev_test.as_user(p_uuid text) RETURNS void LANGUAGE sql AS $$
 SELECT set_config('request.jwt.claims',json_build_object('sub',p_uuid)::text,true),
        set_config('request.jwt.claim.sub',p_uuid,true) $$;
CREATE FUNCTION np06_rev_test.ok(p_true boolean,p_msg text) RETURNS void LANGUAGE plpgsql AS $$
 BEGIN IF p_true IS DISTINCT FROM true THEN RAISE EXCEPTION 'FIN_REV_ASSERT:%',p_msg; END IF; END $$;
CREATE FUNCTION np06_rev_test.expect(p_sql text,p_prefix text) RETURNS void LANGUAGE plpgsql AS $$
 BEGIN
  BEGIN EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
   IF SQLERRM LIKE p_prefix||'%' THEN RETURN; END IF;
   RAISE EXCEPTION 'FIN_REV_WRONG_ERROR expected=% got=%',p_prefix,SQLERRM;
  END;
  RAISE EXCEPTION 'FIN_REV_EXPECTED_DENIAL:%',p_prefix;
 END $$;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA np06_rev_test TO authenticated;

SET LOCAL ROLE authenticated;
SELECT np06_rev_test.as_user('91111111-1111-4111-8111-111111111111');
SELECT core10.finance_create_account_v1(9811,'1000','Reversal Cash',NULL,'asset',NULL,'BDT') debit_id \gset
SELECT core10.finance_create_account_v1(9811,'3000','Reversal Equity',NULL,'equity',NULL,'BDT') credit_id \gset
SELECT core10.finance_set_period_v1(9811,'BDT','2026-11-01',true,'revopenperiod01');
SELECT core10.finance_draft_journal_v1(9811,9812,'BDT','2026-11-16','manual',
 'original-reversal-01','revorigdraft01',
 jsonb_build_array(
  jsonb_build_object('account_id',:debit_id,'side','debit','amount',250),
  jsonb_build_object('account_id',:credit_id,'side','credit','amount',250))) original \gset
SELECT core10.finance_validate_journal_v1(:original);
SELECT np06_rev_test.expect(format(
 'SELECT core10.finance_post_journal_v1(%s,%L)',:original,'revpostorig01'),
 'FIN_APPROVAL_NOT_CONNECTED');
SELECT core10.control_set_v1(9811,NULL,'finance.journal_post',true,0::smallint,
 '{"max_post_amount":500}'::jsonb,NULL,false,0,
 'Owner enables synthetic manual journal post','revpostcontrol01');
SELECT core10.finance_post_journal_v1(:original,'revpostorig01');
SELECT np06_rev_test.ok((SELECT status='posted' FROM core10.finance_journals_v1
 WHERE id=:original),'source is posted');

-- Reversal is OFF by default; can't bypass Owner Control via its journal-post gate.
SELECT np06_rev_test.expect(format(
 'SELECT core10.finance_reverse_posted_journal_v1(%s,%L,%L,%L)',
 :original,'2026-12-01','correction','reversalkey01'),
 'CONTROL_DISABLED:finance.journal_reverse');
SELECT np06_rev_test.ok((SELECT count(*)=0 FROM core10.finance_reversals_v1),
 'disabled reversal creates no evidence or draft');

SELECT core10.control_set_v1(9811,NULL,'finance.journal_reverse',true,0::smallint,
 '{}'::jsonb,NULL,false,0,'Owner enables governed reversal','revcontrol0001');
SELECT np06_rev_test.expect(format(
 'SELECT core10.finance_reverse_posted_journal_v1(%s,%L,%L,%L)',
 :original,'2026-11-15','correction','reversalkey01'),'FIN_REVERSAL_BACKDATE');
SELECT np06_rev_test.expect(format(
 'SELECT core10.finance_reverse_posted_journal_v1(%s,%L,%L,%L)',
 :original,'2026-12-01','not valid!','reversalkey01'),'FIN_REVERSAL_INVALID_INPUT');
SELECT np06_rev_test.expect(format(
 'SELECT core10.finance_reverse_posted_journal_v1(%s,%L,%L,%L)',
 :original,'2026-12-01','correction','reversalkey01'),'FIN_PERIOD_CLOSED');
SELECT np06_rev_test.ok((SELECT count(*)=0 FROM core10.finance_journals_v1
 WHERE business_id=9811 AND source_domain='finance_reversal'),
 'closed-period reversal atomically leaves no draft');

-- A reversal in a subsequently OPEN period is allowed despite original month later closing.
SELECT core10.finance_set_period_v1(9811,'BDT','2026-11-01',false,'revcloseperiod1');
SELECT core10.finance_set_period_v1(9811,'BDT','2026-12-01',true,'revopenperiod02');
SELECT core10.finance_reverse_posted_journal_v1(:original,'2026-12-01','correction',
 'reversalkey01') reversed \gset
SELECT np06_rev_test.ok((SELECT status='posted' AND effective_on='2026-12-01'
 FROM core10.finance_journals_v1 WHERE id=:reversed),
 'reversal posted in new explicitly open period');
SELECT np06_rev_test.ok((SELECT status='posted' AND effective_on='2026-11-16'
 FROM core10.finance_journals_v1 WHERE id=:original),
 'original journal remains posted and unchanged');
SELECT np06_rev_test.ok((SELECT count(*)=2 FROM core10.finance_journal_lines_v1 o
 JOIN core10.finance_journal_lines_v1 r
  ON r.line_no=o.line_no AND r.journal_id=:reversed
 WHERE o.journal_id=:original AND o.account_id=r.account_id AND o.amount=r.amount
 AND ((o.side='debit' AND r.side='credit') OR (o.side='credit' AND r.side='debit'))),
 'every original line has its exact opposite, same account and amount');
SELECT np06_rev_test.ok((SELECT count(*)=1 FROM core10.finance_reversals_v1
 WHERE business_id=9811 AND original_journal_id=:original AND reversal_journal_id=:reversed
 AND reason_code='correction' AND audit_event_id IS NOT NULL),
 'one immutable reversal pointer + audit receipt');

SELECT np06_rev_test.ok(core10.finance_reverse_posted_journal_v1(
 :original,'2026-12-01','correction','reversalkey01')=:reversed,
 'exact-key, same-actor, same-payload replay returns same reversal');
SELECT np06_rev_test.expect(format(
 'SELECT core10.finance_reverse_posted_journal_v1(%s,%L,%L,%L)',
 :original,'2026-12-01','correction','anotherkey01'),'FIN_ALREADY_REVERSED');
SELECT np06_rev_test.expect(format(
 'SELECT core10.finance_reverse_posted_journal_v1(%s,%L,%L,%L)',
 :original,'2026-12-01','mistake','reversalkey01'),'FIN_ALREADY_REVERSED');
SELECT np06_rev_test.expect(format(
 'SELECT core10.finance_reverse_posted_journal_v1(%s,%L,%L,%L)',
 :reversed,'2026-12-02','correction','reversalkey02'),'FIN_REVERSAL_CHAIN_DENIED');

-- An unrelated posted journal cannot reuse the reversal idempotency key.
SELECT core10.finance_draft_journal_v1(9811,9812,'BDT','2026-12-01','manual',
 'original-reversal-02','revorigdraft02',
 jsonb_build_array(
  jsonb_build_object('account_id',:debit_id,'side','debit','amount',80),
  jsonb_build_object('account_id',:credit_id,'side','credit','amount',80))) original2 \gset
SELECT core10.finance_validate_journal_v1(:original2);
SELECT core10.finance_post_journal_v1(:original2,'revpostorig02');
SELECT np06_rev_test.expect(format(
 'SELECT core10.finance_reverse_posted_journal_v1(%s,%L,%L,%L)',
 :original2,'2026-12-02','correction','reversalkey01'),'FIN_IDEMPOTENCY_CONFLICT');
SELECT np06_rev_test.ok((SELECT count(*)=1 FROM core10.finance_reversals_v1),
 'idempotency conflict has no second reversal');

-- Role isolation is canonical Auth / RLS, not a duplicated Finance permissions table.
SELECT np06_rev_test.as_user('93333333-3333-4333-8333-333333333333');
SELECT np06_rev_test.expect(format(
 'SELECT core10.finance_reverse_posted_journal_v1(%s,%L,%L,%L)',
 :original2,'2026-12-02','correction','reversalkey02'),'FIN_AUTH_DENIED');
SELECT np06_rev_test.as_user('95555555-5555-4555-8555-555555555555');
SELECT np06_rev_test.ok((SELECT count(*)=0 FROM core10.finance_reversals_v1),
 'foreign tenant cannot read reversal links');
SELECT np06_rev_test.expect(format(
 'SELECT core10.finance_reverse_posted_journal_v1(%s,%L,%L,%L)',
 :original2,'2026-12-02','correction','reversalkey02'),'FIN_AUTH_DENIED');
SELECT np06_rev_test.as_user('91111111-1111-4111-8111-111111111111');

SELECT np06_rev_test.ok((core10.verify_canonical_audit_v1(9811)->>'ok')::boolean,
 'canonical audit chain remains valid');
SELECT np06_rev_test.ok((SELECT count(*)=1 FROM core10.canonical_audit_events_v1
 WHERE business_id=9811 AND action='finance.journal_reverse'),
 'exactly one reversal command audit event');
SELECT np06_rev_test.ok(NOT has_function_privilege('anon',
 'core10.finance_reverse_posted_journal_v1(bigint,date,text,text)','EXECUTE'),
 'anon cannot call reversal');
SELECT np06_rev_test.ok(NOT has_function_privilege('public',
 'core10.finance_reverse_posted_journal_v1(bigint,date,text,text)','EXECUTE'),
 'PUBLIC cannot call reversal');

-- Privileged SQL must not modify or delete reversal links, or posted journal lines.
RESET ROLE;
SELECT np06_rev_test.expect(format(
 'DELETE FROM core10.finance_reversals_v1 WHERE reversal_journal_id=%s',:reversed),
 'FIN_REVERSAL_IMMUTABLE');
SELECT np06_rev_test.expect(format(
 'UPDATE core10.finance_reversals_v1 SET reason_code=%L WHERE reversal_journal_id=%s',
 'tampered',:reversed),'FIN_REVERSAL_IMMUTABLE');
SELECT np06_rev_test.expect('TRUNCATE core10.finance_reversals_v1',
 'FIN_REVERSAL_IMMUTABLE');
SELECT np06_rev_test.expect(format(
 'DELETE FROM core10.finance_journal_lines_v1 WHERE journal_id=%s',:reversed),
 'FIN_LINES_APPEND_ONLY');
SELECT 'NP06_REVERSAL_E2E_PASS' AS result;
ROLLBACK;
