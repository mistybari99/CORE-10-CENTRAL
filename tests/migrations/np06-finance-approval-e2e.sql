-- NP06 0405 GOV002 -> Finance canonical manual posting E2E.
-- Disposable PostgreSQL 17 only. All data is synthetic and rolled back.
\set ON_ERROR_STOP on
BEGIN;
INSERT INTO core10.templates(code,source_status,demo_allowed)
 VALUES('sweets_bakery','available',true) ON CONFLICT(code) DO NOTHING;
INSERT INTO core10.tenants(id,slug)
 VALUES(978,'finance-approval-primary'),(979,'finance-approval-foreign');
INSERT INTO core10.legal_entities(id,tenant_id,label)
 VALUES(9780,978,'Finance Approval A'),(9790,979,'Finance Approval B');
INSERT INTO core10.businesses(id,tenant_id,legal_entity_id,slug,template_code,request_key)
 VALUES(9781,978,9780,'fin-approval-a','sweets_bakery','finGovBusinessA1'),
       (9791,979,9790,'fin-approval-b','sweets_bakery','finGovBusinessB1');
INSERT INTO core10.tenant_members(tenant_id,user_id,role) VALUES
 (978,'91111111-1111-4111-8111-111111111111','tenant_owner'),
 (978,'97777777-7777-4777-8777-777777777777','tenant_owner'),
 (979,'95555555-5555-4555-8555-555555555555','tenant_owner');
INSERT INTO core10.business_members(tenant_id,business_id,user_id,role) VALUES
 (978,9781,'92222222-2222-4222-8222-222222222222','business_owner'),
 (978,9781,'93333333-3333-4333-8333-333333333333','manager');

CREATE SCHEMA np06_finapp_test;
GRANT USAGE ON SCHEMA np06_finapp_test TO authenticated;
CREATE FUNCTION np06_finapp_test.as_user(x text) RETURNS void LANGUAGE sql AS $$
 SELECT set_config('request.jwt.claims',json_build_object('sub',x)::text,true),
        set_config('request.jwt.claim.sub',x,true) $$;
CREATE FUNCTION np06_finapp_test.ok(b boolean,msg text) RETURNS void LANGUAGE plpgsql AS $$
 BEGIN IF b IS DISTINCT FROM true THEN RAISE EXCEPTION 'FIN_GOV_ASSERT_FAILED:%',msg; END IF; END $$;
CREATE FUNCTION np06_finapp_test.expect(q text,prefix text) RETURNS void LANGUAGE plpgsql AS $$
 BEGIN
  BEGIN EXECUTE q;
  EXCEPTION WHEN OTHERS THEN
   IF SQLERRM LIKE prefix||'%' THEN RETURN; END IF;
   RAISE EXCEPTION 'FIN_GOV_WRONG_DENIAL expected=% got=%',prefix,SQLERRM;
  END;
  RAISE EXCEPTION 'FIN_GOV_EXPECTED_DENIAL:%',prefix;
 END $$;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA np06_finapp_test TO authenticated;
SET LOCAL ROLE authenticated;
SELECT np06_finapp_test.as_user('91111111-1111-4111-8111-111111111111');

SELECT core10.finance_create_account_v1(9781,'1000','Manual cash',NULL,'asset',NULL,'BDT') cash_id \gset
SELECT core10.finance_create_account_v1(9781,'3000','Manual equity',NULL,'equity',NULL,'BDT') equity_id \gset
SELECT core10.finance_set_period_v1(9781,'BDT','2026-11-01',true,'finGovOpenNov01');
SELECT core10.finance_draft_journal_v1(9781,NULL,'BDT','2026-11-21',
 'manual','fin-gov-source-001','finGovDraft001',
 jsonb_build_array(
  jsonb_build_object('account_id',:cash_id,'side','debit','amount',120),
  jsonb_build_object('account_id',:equity_id,'side','credit','amount',120))) journal_id \gset
SELECT core10.finance_validate_journal_v1(:journal_id);

-- Owner configures genuine TWO-stage Finance + GOV002 review.
SELECT core10.control_set_v1(9781,NULL,'gov002.review',true,2::smallint,
 '{}'::jsonb,NULL,false,0,'Two actual reviewers required','finGovReviewCtl1');
SELECT core10.control_set_v1(9781,NULL,'finance.journal_post',true,2::smallint,
 '{"max_post_amount":500}'::jsonb,NULL,false,0,
 'Owner requires completed Finance review','finGovPostCtl001');
SELECT core10.publish_approval_policy_v1(
 9781,'finance','post',120,'finGovPolicy001') policy_id \gset
SELECT core10.configure_approval_route_v1(
 :policy_id,ARRAY['business_owner','tenant_owner']::text[],
 'finGovRoute001');

-- Preapproval request cannot authorize posting; original 2-arg API remains
-- fail-closed and the approved adapter has no receipt yet.
SELECT core10.finance_request_post_approval_v1(
 :journal_id,'finGovSubmit001') approval_id \gset
SELECT np06_finapp_test.ok(
 core10.finance_request_post_approval_v1(
  :journal_id,'finGovSubmit001')=:approval_id,
 'exact canonical review submission replay');
SELECT np06_finapp_test.ok(
 (SELECT status='pending' AND domain_v1='finance' AND action_code_v1='post'
  AND source_key_v1='finance:journal:'||:journal_id||':post'
  FROM core10.approval_requests WHERE id=:approval_id),
 'canonical request bound to frozen journal source');
SELECT np06_finapp_test.expect(format(
 'SELECT core10.finance_post_journal_v1(%s,%L)',:journal_id,'finGovPostOld01'),
 'FIN_APPROVAL_NOT_CONNECTED');
SELECT np06_finapp_test.expect(format(
 'SELECT core10.finance_post_approved_journal_v1(%s,%L,%s)',
 :journal_id,'finGovPost001',:approval_id),
 'FIN_APPROVAL_NOT_EFFECTIVE');
SELECT np06_finapp_test.expect(format(
 'SELECT core10.decide_approval(%s,%L,%L)',
 :approval_id,'approve','finGovSelf01'), 'approval_not_authorized');
SELECT np06_finapp_test.ok(
 (SELECT status='validated' FROM core10.finance_journals_v1 WHERE id=:journal_id),
 'no Money posting before independent approval');

-- Stage 1: real scoped business owner, request must remain pending.
SELECT np06_finapp_test.as_user('92222222-2222-4222-8222-222222222222');
SELECT core10.decide_approval(:approval_id,'approve','finGovStage001');
SELECT np06_finapp_test.ok(
 (SELECT status='pending' FROM core10.approval_requests WHERE id=:approval_id),
 'one stage is not full approval');
-- Stage 2: a SECOND tenant owner, not the original finance maker.
SELECT np06_finapp_test.as_user('97777777-7777-4777-8777-777777777777');
SELECT core10.decide_approval(:approval_id,'approve','finGovStage002');
SELECT np06_finapp_test.ok(
 (SELECT status='approved' AND decided_by=
  '97777777-7777-4777-8777-777777777777'::uuid
 FROM core10.approval_requests WHERE id=:approval_id),
 'two distinct stage receipts produce effective approval');
SELECT np06_finapp_test.ok(
 (SELECT count(*)=2 FROM core10.approval_stage_receipts_v1
 WHERE request_id=:approval_id),
 'two canonical stage receipts retained');

-- Original maker returns to post; requires current Control, period and
-- exact server-built source digest and canonical approval receipts.
SELECT np06_finapp_test.as_user('91111111-1111-4111-8111-111111111111');
SELECT np06_finapp_test.ok(
 core10.finance_post_approved_journal_v1(
  :journal_id,'finGovPost001',:approval_id)=:journal_id,
 'approved journal posted to canonical Money ledger');
SELECT np06_finapp_test.ok(
 core10.finance_post_approved_journal_v1(
  :journal_id,'finGovPost001',:approval_id)=:journal_id,
 'exact-key posted retry no duplicate Money/Audit');
SELECT np06_finapp_test.expect(format(
 'SELECT core10.finance_post_approved_journal_v1(%s,%L,%s)',
 :journal_id,'finGovNewPost1',:approval_id),'FIN_ALREADY_POSTED');
SELECT np06_finapp_test.ok(
 (SELECT status='posted' AND audit_event_id IS NOT NULL
  FROM core10.finance_journals_v1 WHERE id=:journal_id),
 'posted journal carries one canonical audit');
SELECT np06_finapp_test.ok(
 (SELECT count(*)=1 FROM core10.canonical_audit_events_v1
  WHERE business_id=9781 AND action='finance.journal_post'
  AND payload->>'approval_request_id'=:approval_id::text),
 'canonical Money audit binds real GOV002 request exactly once');

-- Second manual source: approved first source must NOT post this one.
SELECT core10.finance_draft_journal_v1(9781,NULL,'BDT','2026-11-21',
 'manual','fin-gov-source-002','finGovDraft002',
 jsonb_build_array(
  jsonb_build_object('account_id',:cash_id,'side','debit','amount',40),
  jsonb_build_object('account_id',:equity_id,'side','credit','amount',40))) journal2 \gset
SELECT core10.finance_validate_journal_v1(:journal2);
SELECT np06_finapp_test.expect(format(
 'SELECT core10.finance_post_approved_journal_v1(%s,%L,%s)',
 :journal2,'finGovPost002',:approval_id),
 'approval_stale_or_payload_changed');
SELECT np06_finapp_test.ok(
 (SELECT status='validated' FROM core10.finance_journals_v1 WHERE id=:journal2),
 'stale approval created no second posted Money entry');

-- A generic Money draft calling itself a Sales invoice is not source-attested.
SELECT core10.finance_draft_journal_v1(9781,NULL,'BDT','2026-11-21',
 'sales_invoice','fake-sales-approval-01','finGovFakeDr01',
 jsonb_build_array(
  jsonb_build_object('account_id',:cash_id,'side','debit','amount',12),
  jsonb_build_object('account_id',:equity_id,'side','credit','amount',12))) fake_sales \gset
SELECT core10.finance_validate_journal_v1(:fake_sales);
SELECT np06_finapp_test.expect(format(
 'SELECT core10.finance_request_post_approval_v1(%s,%L)',
 :fake_sales,'finGovFakeReq1'),'FIN_APPROVAL_SOURCE_NOT_ATTESTED');

-- Current Owner disables Finance post. Even existing prior approvals cannot
-- create another Money posting, and exact replay is blocked.
SELECT core10.control_set_v1(9781,NULL,'finance.journal_post',false,2::smallint,
 '{"max_post_amount":500}'::jsonb,NULL,false,1,
 'Suspend Finance posting','finGovPostOff01');
SELECT np06_finapp_test.expect(format(
 'SELECT core10.finance_post_approved_journal_v1(%s,%L,%s)',
 :journal_id,'finGovPost001',:approval_id),
 'CONTROL_DISABLED:finance.journal_post');
SELECT core10.control_set_v1(9781,NULL,'finance.journal_post',true,2::smallint,
 '{"max_post_amount":500}'::jsonb,NULL,false,2,
 'Resume Finance posting','finGovPostOn002');

-- Current review switch is independently checked, not inferred from old
-- previously successful review receipts.
SELECT core10.control_set_v1(9781,NULL,'gov002.review',false,2::smallint,
 '{}'::jsonb,NULL,false,1,'Suspend review binding','finGovReviewOff1');
SELECT np06_finapp_test.expect(format(
 'SELECT core10.finance_post_approved_journal_v1(%s,%L,%s)',
 :journal_id,'finGovPost001',:approval_id),
 'CONTROL_DISABLED:gov002.review');
SELECT core10.control_set_v1(9781,NULL,'gov002.review',true,2::smallint,
 '{}'::jsonb,NULL,false,2,'Restore review binding','finGovReviewOn02');

-- Reuse of an approved receipt on a foreign source remains denied.
SELECT np06_finapp_test.as_user('93333333-3333-4333-8333-333333333333');
SELECT np06_finapp_test.expect(format(
 'SELECT core10.finance_request_post_approval_v1(%s,%L)',
 :journal2,'finGovManagerReq1'),'FIN_AUTH_DENIED');
SELECT np06_finapp_test.as_user('95555555-5555-4555-8555-555555555555');
SELECT np06_finapp_test.expect(format(
 'SELECT core10.finance_post_approved_journal_v1(%s,%L,%s)',
 :journal2,'finGovForeign01',:approval_id),'FIN_AUTH_DENIED');
SELECT np06_finapp_test.as_user('91111111-1111-4111-8111-111111111111');
SELECT np06_finapp_test.ok(
 (core10.verify_canonical_audit_v1(9781)->>'ok')::boolean,
 'one canonical Audit chain includes both real Approval receipts and post');
SELECT np06_finapp_test.ok(NOT has_function_privilege(
 'anon','core10.finance_post_approved_journal_v1(bigint,text,bigint)','EXECUTE'),
 'anon cannot use Finance Approval adapter');
SELECT np06_finapp_test.ok(NOT has_function_privilege(
 'public','core10.finance_request_post_approval_v1(bigint,text)','EXECUTE'),
 'public cannot submit Finance approval adapter');
SELECT 'NP06_FINANCE_GOV002_APPROVED_POST_E2E_PASS' AS result;
ROLLBACK;
