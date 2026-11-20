-- NP06/0401 standalone two-session reversal race fixture.
-- This file creates its OWN source journal; it does not rely on the posting-race
-- test or its seed. Synthetic disposable PostgreSQL17 only. Never hosted.
\set ON_ERROR_STOP on
INSERT INTO core10.templates(code,source_status,demo_allowed)
 VALUES('sweets_bakery','available',true) ON CONFLICT(code) DO NOTHING;
INSERT INTO core10.tenants(id,slug) VALUES(971,'np06-race-tenant');
INSERT INTO core10.legal_entities(id,tenant_id,label)
 VALUES(9710,971,'NP06 Independent Reversal Legal');
INSERT INTO core10.businesses(id,tenant_id,legal_entity_id,slug,template_code,request_key)
 VALUES(9711,971,9710,'np06-race-business','sweets_bakery','np06-reverse-solo-business');
INSERT INTO core10.tenant_members(tenant_id,user_id,role)
 VALUES(971,'91111111-1111-4111-8111-111111111111','tenant_owner');
SET ROLE authenticated;
SELECT set_config('request.jwt.claims',
 '{"sub":"91111111-1111-4111-8111-111111111111"}',false);
SELECT core10.finance_create_account_v1(9711,'1000','Standalone Cash',
 NULL,'asset',NULL,'BDT') debit_id \gset
SELECT core10.finance_create_account_v1(9711,'3000','Standalone Capital',
 NULL,'equity',NULL,'BDT') credit_id \gset
SELECT core10.finance_set_period_v1(9711,'BDT','2026-11-01',true,'revSoloPeriod01');
SELECT core10.control_set_v1(9711,NULL,'finance.journal_post',true,0::smallint,
 '{"max_post_amount":1000}'::jsonb,NULL,false,0,
 'Synthetic Owner-only standalone Finance reversal test','revSoloControl01');
SELECT core10.finance_draft_journal_v1(
 9711,NULL,'BDT','2026-11-16','manual','np06-race-journal','revSoloDraft01',
 jsonb_build_array(
  jsonb_build_object('account_id',:debit_id,'side','debit','amount',200),
  jsonb_build_object('account_id',:credit_id,'side','credit','amount',200))) source_journal \gset
SELECT core10.finance_validate_journal_v1(:source_journal);
