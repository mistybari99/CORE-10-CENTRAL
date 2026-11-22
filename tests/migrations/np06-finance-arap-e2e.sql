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
-- Category alone is not a governed trade-account classification. Until a
-- dedicated trade AR/AP designation exists, at minimum reject other categories.
SELECT np06_arap_test.expect(format(
 'SELECT core10.finance_link_open_item_v1(%s,%s,%s,%L,%L,%L)',
 :ar_journal,:customer_id,:expense_account,'ar','2026-11-20','arapWrongCat01'),
 'FIN_ARAP_ACCOUNT_SCOPE');
SELECT np06_arap_test.expect(format(
 'SELECT core10.finance_link_open_item_v1(%s,%s,%s,%L,%L,%L)',
 :ap_journal,:supplier_id,:income_account,'ap','2026-11-25','arapWrongCat02'),
 'FIN_ARAP_ACCOUNT_SCOPE');
SELECT np06_arap_test.ok((SELECT count(*)=0 FROM core10.finance_arap_links_v1),
 'rejected wrong-category AR/AP links leave no persisted open items');
SELECT np06_arap_test.ok((SELECT count(*)=0 FROM core10.canonical_audit_events_v1
 WHERE business_id=9611 AND action='finance.arap_link'),
 'rejected wrong-category AR/AP links emit no canonical audit receipts');

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

-- Current-state Owner Control is checked BEFORE an idempotent replay. No cached GO.
SELECT core10.control_set_v1(9611,NULL,'finance.arap_allocate',false,0::smallint,
 '{}'::jsonb,NULL,false,1,'Owner suspends ARAP allocation replays','arapAllocOff001');
SELECT np06_arap_test.expect(format(
 'SELECT core10.finance_allocate_payment_v1(%s,%s,%s,%L)',
 :ar_link,:ar_payment,100,'arapAllocKey001'),'CONTROL_DISABLED:finance.arap_allocate');
SELECT core10.control_set_v1(9611,NULL,'finance.arap_allocate',true,0::smallint,
 '{}'::jsonb,NULL,false,2,'Owner resumes manual allocations','arapAllocOn0002');
SELECT core10.control_set_v1(9611,NULL,'finance.arap_link',false,0::smallint,
 '{}'::jsonb,NULL,false,1,'Owner suspends ARAP link replay','arapLinkOff001');
SELECT np06_arap_test.expect(format(
 'SELECT core10.finance_link_open_item_v1(%s,%s,%s,%L,%L,%L)',
 :ar_journal,:customer_id,:ar_account,'ar','2026-11-20','arapLinkKey001'),
 'CONTROL_DISABLED:finance.arap_link');
SELECT core10.control_set_v1(9611,NULL,'finance.arap_link',true,0::smallint,
 '{}'::jsonb,NULL,false,2,'Owner resumes manual ARAP linking','arapLinkOn0002');
SELECT np06_arap_test.ok((SELECT count(*)=2 FROM core10.finance_arap_allocations_v1),
 'disabled exact-key retries append no additional allocation or Audit receipt');
SELECT np06_arap_test.ok((SELECT count(*)=2 FROM core10.finance_arap_links_v1),
 'disabled exact-key link replay appends no duplicate open item');
SELECT np06_arap_test.ok((SELECT count(*)=2 FROM core10.canonical_audit_events_v1
 WHERE business_id=9611 AND action='finance.arap_link'),
 'disabled exact-key link replay appends no canonical link Audit receipt');
SELECT np06_arap_test.ok((SELECT count(*)=2 FROM core10.canonical_audit_events_v1
 WHERE business_id=9611 AND action='finance.arap_allocate'),
 'disabled exact-key allocation replay appends no canonical allocation Audit receipt');

-- An active customer party from another business/tenant must not be reusable.
SELECT np06_arap_test.as_user('95555555-5555-4555-8555-555555555555');
SELECT core10.master_save_party_v1(9621,'C901','customer','Foreign Customer',NULL,
 NULL,NULL,'active',0,'arapForeignCust1') foreign_party \gset
SELECT np06_arap_test.as_user('91111111-1111-4111-8111-111111111111');
SELECT np06_arap_test.expect(format(
 'SELECT core10.finance_link_open_item_v1(%s,%s,%s,%L,%L,%L)',
 :ar_payment,:foreign_party,:ar_account,'ar','2026-11-28','arapForeignParty01'),
 'FIN_ARAP_MASTER_PARTY_INVALID');

-- A posted journal with a noncash debit/credit cannot masquerade as a manual
-- payment. Account.category='asset' is required structurally; BANK proof remains
-- an explicitly unconnected upstream adapter (no invented cash receipts).
SELECT core10.finance_draft_journal_v1(9611,NULL,'BDT','2026-11-18','manual',
 'arap-noncash-ar-1','arapNoCashDraft1',
 jsonb_build_array(
  jsonb_build_object('account_id',:expense_account,'side','debit','amount',10),
  jsonb_build_object('account_id',:ar_account,'side','credit','amount',10))) no_cash_ar \gset
SELECT core10.finance_validate_journal_v1(:no_cash_ar);
SELECT core10.finance_post_journal_v1(:no_cash_ar,'arapNoCashPost1');
SELECT np06_arap_test.expect(format(
 'SELECT core10.finance_allocate_payment_v1(%s,%s,%s,%L)',
 :ar_link,:no_cash_ar,5,'arapNoCashAll01'),
 'FIN_ARAP_SETTLEMENT_ASSET_COUNTERPART_MISSING');

SELECT core10.finance_draft_journal_v1(9611,NULL,'BDT','2026-11-18','manual',
 'arap-noncash-ap-1','arapNoCashDraft2',
 jsonb_build_array(
  jsonb_build_object('account_id',:ap_account,'side','debit','amount',10),
  jsonb_build_object('account_id',:income_account,'side','credit','amount',10))) no_cash_ap \gset
SELECT core10.finance_validate_journal_v1(:no_cash_ap);
SELECT core10.finance_post_journal_v1(:no_cash_ap,'arapNoCashPost2');
SELECT np06_arap_test.expect(format(
 'SELECT core10.finance_allocate_payment_v1(%s,%s,%s,%L)',
 :ap_link,:no_cash_ap,5,'arapNoCashAll02'),
 'FIN_ARAP_SETTLEMENT_ASSET_COUNTERPART_MISSING');

-- Generic Money can post a journal with a misleading collection domain.
-- Without a canonical collection provider, reject that payment provenance.
SELECT core10.finance_draft_journal_v1(9611,NULL,'BDT','2026-11-18','sales_collection',
 'fake-collection-01','arapFakeCollDr1',
 jsonb_build_array(
  jsonb_build_object('account_id',:cash_account,'side','debit','amount',10),
  jsonb_build_object('account_id',:ar_account,'side','credit','amount',10))) fake_collection \gset
SELECT core10.finance_validate_journal_v1(:fake_collection);
SELECT core10.finance_post_journal_v1(:fake_collection,'arapFakeCollPs1');
SELECT np06_arap_test.expect(format(
 'SELECT core10.finance_allocate_payment_v1(%s,%s,%s,%L)',
 :ar_link,:fake_collection,5,'arapFakeCollAl1'),
 'FIN_ARAP_PAYMENT_SOURCE_NOT_ATTESTED');
SELECT np06_arap_test.expect(format(
 'SELECT core10.finance_allocate_payment_v1(%s,%s,%s,%L)',
 :ar_link,:ar_payment,0,'arapZeroAmount01'),'FIN_ARAP_INVALID_AMOUNT_OR_KEY');
SELECT np06_arap_test.expect(format(
 'SELECT core10.finance_allocate_payment_v1(%s,%s,%s,%L)',
 :ar_link,:ar_payment,1.12345,'arapTooPrecise1'),'FIN_ARAP_INVALID_AMOUNT_OR_KEY');



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
 SELECT (r->>'outstanding')::numeric=300 AND (r->>'allocated_amount')::numeric=0
 FROM jsonb_array_elements(core10.finance_arap_aging_v1(9611,'2026-11-17','ar')->'rows') r
 WHERE (r->>'link_id')::bigint=:ar_link
), 'historical AR balance before payment effective date remains 300');

-- Report filters must fail closed rather than silently widening scope.
SELECT np06_arap_test.expect(
 'SELECT core10.finance_arap_aging_v1(9611,NULL,NULL)',
 'FIN_ARAP_BAD_REPORT_FILTER');
SELECT np06_arap_test.expect(
 'SELECT core10.finance_arap_aging_v1(9611,DATE ''2026-11-30'',''other'')',
 'FIN_ARAP_BAD_REPORT_FILTER');
SELECT np06_arap_test.ok((
 SELECT count(*)=1 FROM jsonb_array_elements(
 core10.finance_arap_aging_v1(9611,'2026-11-30','ar')->'rows') r
 WHERE r->>'kind'='ar'
), 'AR filter excludes AP records without changing their balances');
SELECT np06_arap_test.ok((
 SELECT count(*)=1 FROM jsonb_array_elements(
 core10.finance_arap_aging_v1(9611,'2026-11-30','ap')->'rows') r
 WHERE r->>'kind'='ap' AND (r->>'outstanding')::numeric=110
), 'AP filter excludes AR records and preserves the derived 180-70 balance');

-- P2-03 historical knowledge semantics: allocations recorded later are still
-- counted in a past report when the posted payment's effective_on is on/before
-- p_as_of. This is a RESTATED EFFECTIVE-DATE report, not a knowledge-as-of
-- snapshot or proof that the allocation was known on the historic date.
SELECT np06_arap_test.ok((
 SELECT a.created_at::date > DATE '2026-11-18'
 FROM core10.finance_arap_allocations_v1 a WHERE a.id=:ar_allocation
), 'allocation was linked AFTER the historical payment-effective date');
SELECT np06_arap_test.ok((
 SELECT (r->>'allocated_amount')::numeric=100
    AND (r->>'outstanding')::numeric=200
 FROM jsonb_array_elements(core10.finance_arap_aging_v1(9611,'2026-11-18','ar')->'rows') r
 WHERE (r->>'link_id')::bigint=:ar_link
), 'restated effective-date aging includes later-recorded allocation, not knowledge-as-of');
SELECT np06_arap_test.ok((
 SELECT r->>'age_bucket'='1_30' FROM jsonb_array_elements(
 core10.finance_arap_aging_v1(9611,'2026-11-30','ar')->'rows') r),
 'AR 10 days overdue aged bucket');

-- P2 aging bucket edges: boundary dates must not jump a bucket early.
-- Existing AR document due 2026-11-20; payment does not affect days overdue.
SELECT np06_arap_test.ok((
 SELECT bool_and((r->>'age_bucket')=v.bucket AND (r->>'days_overdue')::int=v.days)
 FROM (VALUES
  (DATE '2026-11-20','current',0),
  (DATE '2026-11-21','1_30',1),
  (DATE '2026-12-20','1_30',30),
  (DATE '2026-12-21','31_60',31),
  (DATE '2027-01-19','31_60',60),
  (DATE '2027-01-20','61_90',61),
  (DATE '2027-02-18','61_90',90),
  (DATE '2027-02-19','90_plus',91)
 ) AS v(as_of,bucket,days)
 CROSS JOIN LATERAL jsonb_array_elements(
  core10.finance_arap_aging_v1(9611,v.as_of,'ar')->'rows') r
 WHERE (r->>'link_id')::bigint=:ar_link
), 'AR aging bucket edges 0/1/30/31/60/61/90/91 are inclusive as documented');

-- Trace must retain the REAL posted source journal + canonical Audit IDs.
-- No source adapter is claimed: manual is explicitly UNATTESTED invoice evidence.
SELECT np06_arap_test.ok((
 SELECT (t->>'document_source_domain')='manual'
  AND (t->>'document_source_ref')='arap-original-ar-1'
  AND (t->>'document_provenance')='manual_posted_journal_not_external_invoice_attested'
  AND (t->>'document_post_audit_event_id') IS NOT NULL
  AND (t->>'link_audit_event_id') IS NOT NULL
  AND (t->>'posted_amount')::numeric=300
  AND jsonb_array_length(t->'payment_allocations')=1
  AND (t->'payment_allocations'->0->>'payment_source_ref')='arap-payment-ar-1'
  AND (t->'payment_allocations'->0->>'payment_provenance')='manual_asset_counterpart_not_bank_attested'
  AND (t->'payment_allocations'->0->>'amount')::numeric=100
  AND (t->'payment_allocations'->0->>'allocation_audit_event_id') IS NOT NULL
 FROM (SELECT core10.finance_arap_trace_v1(:ar_link) t) x
), 'AR trace joins posted journal, Master party, payment and both audit receipts');

SELECT np06_arap_test.ok((
 (core10.finance_arap_trace_v1(:ap_link)->>'kind')='ap'
 AND (core10.finance_arap_trace_v1(:ap_link)->>'party_id')=:supplier_id::text
 AND (core10.finance_arap_trace_v1(:ap_link)->'payment_allocations'->0->>'amount')::numeric=70
), 'AP trace keeps supplier identity and 70 partial payment');

-- A malicious/manual caller can post a journal with source_domain=sales_invoice
-- via the generic Money draft function. That is NOT an attested Sales invoice.
-- Reject the ARAP link rather than laundering that source domain as authoritative.
SELECT core10.finance_draft_journal_v1(9611,NULL,'BDT','2026-11-18',
 'sales_invoice','fake-sales-invoice-01','arapFakeInvoice1',
 jsonb_build_array(
  jsonb_build_object('account_id',:ar_account,'side','debit','amount',45),
  jsonb_build_object('account_id',:income_account,'side','credit','amount',45))) fake_invoice \gset
SELECT core10.finance_validate_journal_v1(:fake_invoice);
SELECT core10.finance_post_journal_v1(:fake_invoice,'arapFakePostInv1');
SELECT np06_arap_test.expect(format(
 'SELECT core10.finance_link_open_item_v1(%s,%s,%s,%L,%L,%L)',
 :fake_invoice,:customer_id,:ar_account,'ar','2026-11-25','arapFakeLinkInv1'),
 'FIN_ARAP_EXTERNAL_SOURCE_NOT_ATTESTED');
SELECT np06_arap_test.ok((SELECT count(*)=2 FROM core10.finance_arap_links_v1),
 'unattested invoice source cannot become an ARAP open item');

SELECT core10.finance_draft_journal_v1(9611,NULL,'BDT','2026-11-18',
 'purchase_bill','fake-purchase-bill-01','arapFakeBill001',
 jsonb_build_array(
  jsonb_build_object('account_id',:expense_account,'side','debit','amount',25),
  jsonb_build_object('account_id',:ap_account,'side','credit','amount',25))) fake_bill \gset
SELECT core10.finance_validate_journal_v1(:fake_bill);
SELECT core10.finance_post_journal_v1(:fake_bill,'arapFakePostBil1');
SELECT np06_arap_test.expect(format(
 'SELECT core10.finance_link_open_item_v1(%s,%s,%s,%L,%L,%L)',
 :fake_bill,:supplier_id,:ap_account,'ap','2026-11-25','arapFakeLinkBil1'),
 'FIN_ARAP_EXTERNAL_SOURCE_NOT_ATTESTED');

-- A source or PAYMENT already allocated cannot be reversed by generic 0401
-- without a future governed allocation-reversal reconciliation adapter.
SELECT core10.control_set_v1(9611,NULL,'finance.journal_reverse',true,0::smallint,
 '{}'::jsonb,NULL,false,0,'Owner enables synthetic reversal validation','arapRevCtrl01');
SELECT np06_arap_test.expect(format(
 'SELECT core10.finance_reverse_posted_journal_v1(%s,%L,%L,%L)',
 :ar_journal,'2026-12-01','correction','arapReverse001'),
 'FIN_ARAP_ALLOCATED_REVERSAL_NOT_CONNECTED');
SELECT np06_arap_test.expect(format(
 'SELECT core10.finance_reverse_posted_journal_v1(%s,%L,%L,%L)',
 :ar_payment,'2026-12-01','correction','arapReverse002'),
 'FIN_ARAP_ALLOCATED_REVERSAL_NOT_CONNECTED');
SELECT np06_arap_test.ok((SELECT count(*)=0 FROM core10.finance_reversals_v1
 WHERE original_journal_id IN (:ar_journal,:ar_payment)),
 'denied allocated reversal rolls back 0401 posted reversal and Audit atomically');

-- A separate UNALLOCATED, manual posted document can still be safely reversed.
SELECT core10.finance_draft_journal_v1(9611,NULL,'BDT','2026-11-19','manual',
 'arap-unallocated-ar-1','arapDraftUnall1',
 jsonb_build_array(
  jsonb_build_object('account_id',:ar_account,'side','debit','amount',40),
  jsonb_build_object('account_id',:income_account,'side','credit','amount',40))) unallocated_journal \gset
SELECT core10.finance_validate_journal_v1(:unallocated_journal);
SELECT core10.finance_post_journal_v1(:unallocated_journal,'arapPostUnall01');
SELECT core10.finance_link_open_item_v1(:unallocated_journal,:customer_id,:ar_account,
 'ar','2026-11-25','arapLinkUnall01') unallocated_link \gset
SELECT core10.finance_reverse_posted_journal_v1(:unallocated_journal,'2026-12-01',
 'correction','arapReverse003');
SELECT np06_arap_test.ok((
 SELECT (r->>'outstanding')::numeric=0 AND (r->>'reversed')::boolean
 FROM jsonb_array_elements(core10.finance_arap_aging_v1(9611,'2026-12-10','ar')->'rows') r
 WHERE (r->>'link_id')::bigint=:unallocated_link
), 'unallocated source reversal leaves zero outstanding only as-of reversal date');
SELECT np06_arap_test.ok((
 SELECT (r->>'outstanding')::numeric=40 AND NOT (r->>'reversed')::boolean
 FROM jsonb_array_elements(core10.finance_arap_aging_v1(9611,'2026-11-30','ar')->'rows') r
 WHERE (r->>'link_id')::bigint=:unallocated_link
), 'historical as-of report preserves 40 before subsequent reversal');
SELECT np06_arap_test.ok((
 SELECT (r->>'outstanding')::numeric=200 AND NOT (r->>'reversed')::boolean
 FROM jsonb_array_elements(core10.finance_arap_aging_v1(9611,'2026-12-10','ar')->'rows') r
 WHERE (r->>'link_id')::bigint=:ar_link
), 'allocated original remains outstanding 300-100; cannot be reversed');
SELECT np06_arap_test.ok(
 (core10.finance_arap_trace_v1(:unallocated_link)->>'reversed')::boolean,
 'trace detects canonical 0401 reversal for unallocated document');

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
 'SELECT core10.finance_arap_aging_v1(9611,''2026-11-30'',NULL)',
 'FIN_ARAP_READ_DENIED');
SELECT np06_arap_test.expect(format(
 'SELECT core10.finance_arap_trace_v1(%s)',:ar_link),'FIN_ARAP_READ_DENIED');
SELECT np06_arap_test.as_user('91111111-1111-4111-8111-111111111111');
SELECT np06_arap_test.ok((core10.verify_canonical_audit_v1(9611)->>'ok')::boolean,
 'canonical Master + Finance audit chain preserved');
SELECT np06_arap_test.ok((SELECT count(*)=3 FROM core10.canonical_audit_events_v1
 WHERE business_id=9611 AND action='finance.arap_link'),
 'three immutable AR/AP links and no fake-invoice/bill audit receipts');
SELECT np06_arap_test.ok((SELECT count(*)=2 FROM core10.canonical_audit_events_v1
 WHERE business_id=9611 AND action='finance.arap_allocate'),
 'two immutable allocation receipts');
SELECT np06_arap_test.ok(NOT has_function_privilege('anon',
 'core10.finance_allocate_payment_v1(bigint,bigint,numeric,text)','EXECUTE'),
 'anon cannot allocate');
SELECT np06_arap_test.ok(NOT has_function_privilege('anon',
 'core10.finance_arap_trace_v1(bigint)','EXECUTE'),
 'anon cannot access source provenance');
SELECT np06_arap_test.ok(NOT has_function_privilege('public',
 'core10.finance_link_open_item_v1(bigint,bigint,bigint,text,date,text)','EXECUTE'),
 'public cannot create AR/AP link');
SELECT np06_arap_test.ok(NOT has_function_privilege('public',
 'core10.finance_allocate_payment_v1(bigint,bigint,numeric,text)','EXECUTE'),
 'public cannot allocate AR/AP payment');
SELECT np06_arap_test.ok(NOT has_function_privilege('anon',
 'core10.finance_arap_aging_v1(bigint,date,text)','EXECUTE'),
 'anon cannot read AR/AP aging');
SELECT np06_arap_test.ok(NOT has_function_privilege('public',
 'core10.finance_arap_trace_v1(bigint)','EXECUTE'),
 'public cannot read AR/AP provenance');
SELECT np06_arap_test.ok(NOT has_function_privilege('anon',
 'core10.finance_link_open_item_v1(bigint,bigint,bigint,text,date,text)','EXECUTE'),
 'anon cannot create AR/AP link');
SELECT np06_arap_test.ok(NOT has_function_privilege('public',
 'core10.finance_arap_aging_v1(bigint,date,text)','EXECUTE'),
 'public cannot read AR/AP aging');
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
