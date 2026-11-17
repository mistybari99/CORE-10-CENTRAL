-- NP06/0402: committed synthetic fixture for REAL independent-session allocation tests.
\set ON_ERROR_STOP on
INSERT INTO core10.templates(code,source_status,demo_allowed)
 VALUES('sweets_bakery','available',true) ON CONFLICT(code) DO NOTHING;
INSERT INTO core10.tenants(id,slug) VALUES(963,'np06-arap-race-a');
INSERT INTO core10.legal_entities(id,tenant_id,label) VALUES(9630,963,'ARAP Race Legal');
INSERT INTO core10.businesses(id,tenant_id,legal_entity_id,slug,template_code,request_key)
 VALUES(9631,963,9630,'np06-arap-race-biz','sweets_bakery','arap-race-biz001');
INSERT INTO core10.tenant_members(tenant_id,user_id,role)
 VALUES(963,'91111111-1111-4111-8111-111111111111','tenant_owner');
SET ROLE authenticated;
SELECT set_config('request.jwt.claims',
 '{"sub":"91111111-1111-4111-8111-111111111111"}',false);
SELECT core10.master_save_party_v1(9631,'CR01','customer','Race Customer',NULL,
 NULL,NULL,'active',0,'arapRaceParty01') party_id \gset
SELECT core10.finance_create_account_v1(9631,'1100','Race Receivables',NULL,'asset',NULL,'BDT') ar_id \gset
SELECT core10.finance_create_account_v1(9631,'1000','Race Cash',NULL,'asset',NULL,'BDT') cash_id \gset
SELECT core10.finance_create_account_v1(9631,'4000','Race Sales',NULL,'income',NULL,'BDT') income_id \gset
SELECT core10.finance_set_period_v1(9631,'BDT','2026-11-01',true,'arapRacePeriod1');
SELECT core10.control_set_v1(9631,NULL,'finance.journal_post',true,0::smallint,
 '{"max_post_amount":1000}'::jsonb,NULL,false,0,'Owner enables synthetic ARAP race post','arapRaceCtlPost');
SELECT core10.finance_draft_journal_v1(9631,NULL,'BDT','2026-11-16','manual',
 'arap-race-original','arapRaceDraft1',
 jsonb_build_array(
  jsonb_build_object('account_id',:ar_id,'side','debit','amount',100),
  jsonb_build_object('account_id',:income_id,'side','credit','amount',100))) doc \gset
SELECT core10.finance_validate_journal_v1(:doc);
SELECT core10.finance_post_journal_v1(:doc,'arapRacePost01');
SELECT core10.finance_draft_journal_v1(9631,NULL,'BDT','2026-11-17','manual',
 'arap-race-payment','arapRaceDraft2',
 jsonb_build_array(
  jsonb_build_object('account_id',:cash_id,'side','debit','amount',100),
  jsonb_build_object('account_id',:ar_id,'side','credit','amount',100))) payment \gset
SELECT core10.finance_validate_journal_v1(:payment);
SELECT core10.finance_post_journal_v1(:payment,'arapRacePost02');
SELECT core10.control_set_v1(9631,NULL,'finance.arap_link',true,0::smallint,
 '{}'::jsonb,NULL,false,0,'Owner enables synthetic race document link','arapRaceCtlLink');
SELECT core10.control_set_v1(9631,NULL,'finance.arap_allocate',true,0::smallint,
 '{}'::jsonb,NULL,false,0,'Owner enables synthetic race allocation','arapRaceCtlAlloc');
SELECT core10.finance_link_open_item_v1(:doc,:party_id,:ar_id,'ar','2026-11-20',
 'arapRaceLink001') link_id;

-- Separate unpaid item and already-posted payment, for real reversal-vs-allocation race.
-- This is a DIFFERENT journal pair from the shared-key/budget race above.
SELECT core10.finance_set_period_v1(9631,'BDT','2026-12-01',true,'arapRacePeriod2');
SELECT core10.control_set_v1(9631,NULL,'finance.journal_reverse',true,0::smallint,
 '{}'::jsonb,NULL,false,0,'Owner enables synthetic reversal vs allocation race','arapRaceCtlRev01');
SELECT core10.finance_draft_journal_v1(9631,NULL,'BDT','2026-11-17','manual',
 'arap-race-reverse-original','arapRaceDraft3',
 jsonb_build_array(
  jsonb_build_object('account_id',:ar_id,'side','debit','amount',60),
  jsonb_build_object('account_id',:income_id,'side','credit','amount',60))) revdoc \gset
SELECT core10.finance_validate_journal_v1(:revdoc);
SELECT core10.finance_post_journal_v1(:revdoc,'arapRacePost03');
SELECT core10.finance_draft_journal_v1(9631,NULL,'BDT','2026-11-18','manual',
 'arap-race-reverse-payment','arapRaceDraft4',
 jsonb_build_array(
  jsonb_build_object('account_id',:cash_id,'side','debit','amount',60),
  jsonb_build_object('account_id',:ar_id,'side','credit','amount',60))) revpay \gset
SELECT core10.finance_validate_journal_v1(:revpay);
SELECT core10.finance_post_journal_v1(:revpay,'arapRacePost04');
SELECT core10.finance_link_open_item_v1(:revdoc,:party_id,:ar_id,'ar','2026-11-25',
 'arapRaceRevLink01') revlink_id;
