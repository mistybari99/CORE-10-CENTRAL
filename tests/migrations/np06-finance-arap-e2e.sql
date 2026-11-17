-- NP06 / 0402: disposable PostgreSQL 17 security, Master party and canonical ledger tests.
\set ON_ERROR_STOP on
BEGIN;
INSERT INTO core10.templates(code,source_status,demo_allowed)
 VALUES('sweets_bakery','available',true) ON CONFLICT(code) DO NOTHING;
INSERT INTO core10.tenants(id,slug) VALUES(961,'np06-arap-a'),(962,'np06-arap-b');
INSERT INTO core10.legal_entities(id,tenant_id,label)
 VALUES(9610,961,'ARAP Tenant A'),(9620,962,'ARAP Tenant B');
INSERT INTO core10.businesses(id,tenant_id,legal_entity_id,slug,template_code,request_key)
 VALUES(9611,961,9610,'np06-arap-business-a','sweets_bakery','arap-business-a'),
       (9621,962,9620,'np06-arap-business-b','sweets_bakery','arap-business-b');
INSERT INTO core10.tenant_members(tenant_id,user_id,role) VALUES
 (961,'91111111-1111-4111-8111-111111111111','tenant_owner'),
 (962,'95555555-5555-4555-8555-555555555555','tenant_owner');
INSERT INTO core10.business_members(tenant_id,business_id,user_id,role) VALUES
 (961,9611,'93333333-3333-4333-8333-333333333333','manager');
CREATE SCHEMA np06_arap_test;
GRANT USAGE ON SCHEMA np06_arap_test TO authenticated;
CREATE FUNCTION np06_arap_test.as_user(x text) RETURNS void LANGUAGE sql AS $$
 SELECT set_config('request.jwt.claims',json_build_object('sub',x)::text,true),
        set_config('request.jwt.claim.sub',x,true) $$;
CREATE FUNCTION np06_arap_test.ok(b boolean,msg text) RETURNS void LANGUAGE plpgsql AS $$
 BEGIN IF b IS DISTINCT FROM true THEN RAISE EXCEPTION 'ARAP_ASSERT_FAILED:%',msg; END IF; END $$;
CREATE FUNCTION np06_arap_test.expect(q text,prefix text) RETURNS void LANGUAGE plpgsql AS $$
 BEGIN
  BEGIN EXECUTE q;
  EXCEPTION WHEN OTHERS THEN
   IF SQLERRM LIKE prefix||'%' THEN RETURN; END IF;
   RAISE EXCEPTION 'ARAP_UNEXPECTED_ERROR expected=% got=%',prefix,SQLERRM;
  END;
  RAISE EXCEPTION 'ARAP_EXPECTED_DENIAL:%',prefix;
 END $$;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA np06_arap_test TO authenticated;

SET LOCAL ROLE authenticated;
SELECT np06_arap_test.as_user('91111111-1111-4111-8111-111111111111');
SELECT core10.master_save_party_v1(9611,'C001','customer','Customer One',NULL,
 NULL,NULL,'active',0,'arapPartyCust01') customer_id \gset
SELECT core10.master_save_party_v1(9611,'S001','supplier','Supplier One',NULL,
 NULL,NULL,'active',0,'arapPartySupp01') supplier_id \gset
SELECT core10.master_save_party_v1(9611,'C002','customer','Customer Blocked',NULL,
 NULL,NULL,'blocked',0,'arapPartyBlock1') blocked_id \gset
SELECT core10.finance_create_account_v1(9611,'1100','Trade Receivables',NULL,'asset',NULL,'BDT') ar_account \gset
SELECT core10.finance_create_account_v1(9611,'1000','Cash and Bank',NULL,'asset',NULL,'BDT') cash_account \gset
SELECT core10.finance_create_account_v1(9611,'4000','Trade Sales',NULL,'income',NULL,'BDT') income_account \gset
SELECT core10.finance_create_account_v1(9611,'2000','Trade Payables',NULL,'liability',NULL,'BDT') ap_account \gset
SELECT core10.finance_create_account_v1(9611,'5000','Purchases',NULL,'expense',NULL,'BDT') expense_account \gset
SELECT core10.finance_set_period_v1(9611,'BDT','2026-11-01',true,'arapPeriodNov01');
SELECT core10.finance_set_period_v1(9611,'BDT','2026-12-01',true,'arapPeriodDec01');
SELECT core10.control_set_v1(9611,NULL,'finance.journal_post',true,0::smallint,
 '{"max_post_amount":1000}'::jsonb,NULL,false,0,'Owner enables synthetic manual ARAP post','arapControlPost1');

-- Real posted AR document movement: receivables debit against sales credit.
SELECT core10.finance_draft_journal_v1(9611,NULL,'BDT','2026-11-16','manual',
 'arap-original-ar-1','arapDraftAr001',
 jsonb_build_array(
  jsonb_build_object('account_id',:ar_account,'side','debit','amount',300),
  jsonb_build_object('account_id',:income_account,'side','credit','amount',300))) ar_journal \gset
SELECT core10.finance_validate_journal_v1(:ar_journal);
SELECT core10.finance_post_journal_v1(:ar_journal,'arapPostAr001');

-- Payment is NOT created by AR/AP. It is another already-posted canonical journal.
SELECT core10.finance_draft_journal_v1(9611,NULL,'BDT','2026-11-18','manual',
 'arap-payment-ar-1','arapDraftPay001',
 jsonb_build_array(
  jsonb_build_object('account_id',:cash_account,'side','debit','amount',120),
  jsonb_build_object('account_id',:ar_account,'side','credit','amount',120))) ar_payment \gset
SELECT core10.finance_validate_journal_v1(:ar_payment);
SELECT core10.finance_post_journal_v1(:ar_payment,'arapPostPay001');

-- Posted AP original: expense debit, payable credit.
SELECT core10.finance_draft_journal_v1(9611,NULL,'BDT','2026-11-16','manual',
 'arap-original-ap-1','arapDraftAp001',
 jsonb_build_array(
  jsonb_build_object('account_id',:expense_account,'side','debit','amount',180),
  jsonb_build_object('account_id',:ap_account,'side','credit','amount',180))) ap_journal \gset
SELECT core10.finance_validate_journal_v1(:ap_journal);
SELECT core10.finance_post_journal_v1(:ap_journal,'arapPostAp001');

SELECT core10.finance_draft_journal_v1(9611,NULL,'BDT','2026-11-18','manual',
 'arap-payment-ap-1','arapDraftPay002',
 jsonb_build_array(
  jsonb_build_object('account_id',:ap_account,'side','debit','amount',70),
  jsonb_build_object('account_id',:cash_account,'side','credit','amount',70))) ap_payment \gset
SELECT core10.finance_validate_journal_v1(:ap_payment);
SELECT core10.finance_post_journal_v1(:ap_payment,'arapPostPay002');

-- Both manual index writers must be individually Owner-enabled. All other Money
-- controls remain enforceable through the 0400 journal posting path.
SELECT np06_arap_test.expect(format(
 'SELECT core10.finance_link_open_item_v1(%s,%s,%s,%L,%L,%L)',
 :ar_journal,:customer_id,:ar_account,'ar','2026-11-20','arapLinkKey001'),
 'CONTROL_DISABLED:finance.arap_link');
SELECT np06_arap_test.ok((SELECT count(*)=0 FROM core10.finance_arap_links_v1),
 'disabled ARAP link leaves no history');

SELECT core10.control_set_v1(9611,NULL,'finance.arap_link',true,0::smallint,
 '{}'::jsonb,NULL,false,0,'Owner enables synthetic AR/AP linkage','arapControlLink1');
SELECT np06_arap_test.expect(format(
 'SELECT core10.finance_link_open_item_v1(%s,%s,%s,%L,%L,%L)',
 :ar_journal,:supplier_id,:ar_account,'ar','2026-11-20','arapWrongKind01'),
 'FIN_ARAP_MASTER_PARTY_INVALID');
SELECT np06_arap_test.expect(format(
 'SELECT core10.finance_link_open_item_v1(%s,%s,%s,%L,%L,%L)',
 :ar_journal,:blocked_id,:ar_account,'ar','2026-11-20','arapBlocked001'),
 'FIN_ARAP_MASTER_PARTY_INVALID');
SELECT np06_arap_test.expect(format(
 'SELECT core10.finance_link_open_item_v1(%s,%s,%s,%L,%L,%L)',
 :ar_journal,:customer_id,:cash_account,'ar','2026-11-20','arapWrongLine1'),
 'FIN_ARAP_CONTROL_LINE_MISSING');

SELECT core10.finance_link_open_item_v1(:ar_journal,:customer_id,:ar_account,
 'ar','2026-11-20','arapLinkKey001') ar_link \gset
SELECT core10.finance_link_open_item_v1(:ap_journal,:supplier_id,:ap_account,
 'ap','2026-11-25','arapLinkKey002') ap_link \gset
SELECT np06_arap_test.ok(core10.finance_link_open_item_v1(
 :ar_journal,:customer_id,:ar_account,'ar','2026-11-20','arapLinkKey001')=:ar_link,
 'exact AR journal link replay');
SELECT np06_arap_test.expect(format(
 'SELECT core10.finance_link_open_item_v1(%s,%s,%s,%L,%L,%L)',
 :ar_journal,:customer_id,:ar_account,'ar','2026-11-25','arapLinkKey001'),
 'FIN_ARAP_ALREADY_LINKED');
SELECT np06_arap_test.expect(format(
 'SELECT core10.finance_link_open_item_v1(%s,%s,%s,%L,%L,%L)',
 :ar_payment,:customer_id,:ar_account,'ar','2026-11-28','arapLinkKey002'),
 'FIN_ARAP_KEY_CONFLICT');

SELECT np06_arap_test.expect(format(
 'SELECT core10.finance_allocate_payment_v1(%s,%s,%s,%L)',
 :ar_link,:ar_payment,100,'arapAllocKey001'),
 'CONTROL_DISABLED:finance.arap_allocate');
SELECT np06_arap_test.ok((SELECT count(*)=0 FROM core10.finance_arap_allocations_v1),
 'disabled allocation writes nothing');
SELECT core10.control_set_v1(9611,NULL,'finance.arap_allocate',true,0::smallint,
 '{}'::jsonb,NULL,false,0,'Owner enables synthetic allocation','arapControlAlloc1');
SELECT core10.finance_allocate_payment_v1(:ar_link,:ar_payment,100,'arapAllocKey001') ar_allocation \gset
SELECT core10.finance_allocate_payment_v1(:ap_link,:ap_payment,70,'arapAllocKey002') ap_allocation \gset
SELECT np06_arap_test.ok(core10.finance_allocate_payment_v1(
 :ar_link,:ar_payment,100,'arapAllocKey001')=:ar_allocation,'exact allocation replay');
SELECT np06_arap_test.expect(format(
 'SELECT core10.finance_allocate_payment_v1(%s,%s,%s,%L)',
 :ar_link,:ar_payment,110,'arapAllocKey001'),'FIN_ARAP_KEY_CONFLICT');
SELECT np06_arap_test.expect(format(
 'SELECT core10.finance_allocate_payment_v1(%s,%s,%s,%L)',
 :ar_link,:ar_payment,21,'arapAllocKey003'),'FIN_ARAP_OVERALLOCATION');
SELECT np06_arap_test.expect(format(
 'SELECT core10.finance_allocate_payment_v1(%s,%s,%s,%L)',
 :ar_link,:ap_payment,1,'arapAllocKey004'),'FIN_ARAP_PAYMENT_PARTY_OR_ACCOUNT_MISMATCH');
SELECT np06_arap_test.ok((SELECT count(*)=2 FROM core10.finance_arap_allocations_v1),
 'exactly two approved reference-only allocations');

SELECT np06_arap_test.ok((
 (core10.finance_arap_aging_v1(9611,'2026-11-30',NULL)->'rows'->0->>'outstanding')::numeric=200),
 'AR aged balance is derived 300-100');
SELECT np06_arap_test.ok((
 SELECT (r->>'outstanding')::numeric=110 FROM jsonb_array_elements(
 core10.finance_arap_aging_v1(9611,'2026-11-30','ap')->'rows') r),
 'AP aged balance is derived 180-70');
SELECT np06_arap_test.ok((
 core10.finance_arap_aging_v1(9611,'2026-11-15',NULL)->'rows')='[]'::jsonb,
 'no future journal included in earlier as-of date');
SELECT np06_arap_test.ok((
 SELECT r->>'age_bucket'='1_30' FROM jsonb_array_elements(
 core10.finance_arap_aging_v1(9611,'2026-11-30','ar')->'rows') r),
 'AR 10 days overdue aged bucket');

-- Source reversal is posted in December and never changes original journal.
SELECT core10.control_set_v1(9611,NULL,'finance.journal_reverse',true,0::smallint,
 '{}'::jsonb,NULL,false,0,'Owner enables synthetic reversed-item report','arapRevCtrl01');
SELECT core10.finance_reverse_posted_journal_v1(:ar_journal,'2026-12-01',
 'correction','arapReverse001');
SELECT np06_arap_test.ok((
 SELECT (r->>'outstanding')::numeric=0 AND (r->>'reversed')::boolean
 FROM jsonb_array_elements(core10.finance_arap_aging_v1(9611,'2026-12-10','ar')->'rows') r),
 'reversed AR source flags and removes open amount only as-of reversal date');
SELECT np06_arap_test.expect(format(
 'SELECT core10.finance_allocate_payment_v1(%s,%s,%s,%L)',
 :ar_link,:ar_payment,1,'arapAllocKey005'),'FIN_ARAP_PAYMENT_SCOPE_OR_STATUS');

-- Canonical role + tenant isolation. No cloned customer or supplier ACL.
SELECT np06_arap_test.as_user('93333333-3333-4333-8333-333333333333');
SELECT np06_arap_test.expect(format(
 'SELECT core10.finance_allocate_payment_v1(%s,%s,%s,%L)',
 :ap_link,:ap_payment,1,'arapAllocKey006'),'FIN_ARAP_AUTH_DENIED');
SELECT np06_arap_test.as_user('95555555-5555-4555-8555-555555555555');
SELECT np06_arap_test.ok((SELECT count(*)=0 FROM core10.finance_arap_links_v1),
 'cross tenant RLS hides ARAP links');
SELECT np06_arap_test.ok((SELECT count(*)=0 FROM core10.finance_arap_allocations_v1),
 'cross tenant RLS hides allocations');
SELECT np06_arap_test.expect(
 $$SELECT core10.finance_arap_aging_v1(9611,'2026-11-30',NULL)$$,
 'FIN_ARAP_READ_DENIED');
SELECT np06_arap_test.as_user('91111111-1111-4111-8111-111111111111');
SELECT np06_arap_test.ok((core10.verify_canonical_audit_v1(9611)->>'ok')::boolean,
 'canonical Master + Finance audit chain preserved');
SELECT np06_arap_test.ok((SELECT count(*)=2 FROM core10.canonical_audit_events_v1
 WHERE business_id=9611 AND action='finance.arap_link'),
 'two immutable link receipts');
SELECT np06_arap_test.ok((SELECT count(*)=2 FROM core10.canonical_audit_events_v1
 WHERE business_id=9611 AND action='finance.arap_allocate'),
 'two immutable allocation receipts');
SELECT np06_arap_test.ok(NOT has_function_privilege('anon',
 'core10.finance_allocate_payment_v1(bigint,bigint,numeric,text)','EXECUTE'),
 'anon cannot allocate');
SELECT np06_arap_test.ok(NOT has_function_privilege('public',
 'core10.finance_link_open_item_v1(bigint,bigint,bigint,text,date,text)','EXECUTE'),
 'public cannot create AR/AP link');
SELECT np06_arap_test.expect(
 $$DELETE FROM core10.finance_arap_links_v1 WHERE business_id=9611$$,'permission denied');

RESET ROLE;
SELECT np06_arap_test.expect(
 $$UPDATE core10.finance_arap_links_v1 SET kind='ap' WHERE business_id=9611$$,
 'FIN_ARAP_IMMUTABLE');
SELECT np06_arap_test.expect(
 $$DELETE FROM core10.finance_arap_allocations_v1 WHERE business_id=9611$$,
 'FIN_ARAP_IMMUTABLE');
SELECT np06_arap_test.expect(
 $$TRUNCATE core10.finance_arap_allocations_v1$$,'FIN_ARAP_IMMUTABLE');
SELECT 'NP06_ARAP_PG17_E2E_PASS' AS result;
ROLLBACK;
