-- Disposable DB only. Manufacturing consumes genuine, independently reviewed GOV002 requests.
\set ON_ERROR_STOP on
BEGIN;
\ir seed.sql
INSERT INTO core10.tenant_members(tenant_id,user_id,role)
 VALUES(951,'95222222-2222-4222-8222-222222222222','tenant_owner');
INSERT INTO core10.business_members(tenant_id,business_id,user_id,role,approval_actions)
 VALUES(951,9511,'95999999-9999-4999-8999-999999999999','business_owner',ARRAY['approval.decide']);

CREATE SCHEMA mfg_approval_test;
GRANT USAGE ON SCHEMA mfg_approval_test TO authenticated;
CREATE FUNCTION mfg_approval_test.ok(v boolean,msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF v IS DISTINCT FROM true THEN RAISE EXCEPTION 'APPROVAL_ASSERT:%',msg; END IF; END $$;
CREATE FUNCTION mfg_approval_test.expect(q text,e text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN BEGIN EXECUTE q; EXCEPTION WHEN OTHERS THEN
 IF left(SQLERRM,length(e))=e THEN RETURN; END IF;
 RAISE EXCEPTION 'WRONG_ERROR expected % got %',e,SQLERRM;
 END; RAISE EXCEPTION 'EXPECTED_ERROR:%',e; END $$;
SET LOCAL ROLE authenticated;
\ir canonical-master-seed.sql
\set effective '2026-01-01T00:00:00Z'
\set owner '{"sub":"95222222-2222-4222-8222-222222222222"}'
\set maker '{"sub":"95111111-1111-4111-8111-111111111111"}'
\set checker '{"sub":"95999999-9999-4999-8999-999999999999"}'

SELECT set_config('request.jwt.claims',:'owner',true);
SELECT core10.control_set_v1(9511,NULL,'gov002.review',true,2::smallint,'{}',NULL,false,0,'Two independent reviews','mfg_apv_governance');
SELECT core10.control_set_v1(9511,NULL,'mfg.recipe_approve',true,2::smallint,'{}',NULL,false,0,'Two recipe reviews','mfg_apv_recipe_policy');
SELECT core10.control_set_v1(9511,NULL,'mfg.batch_release',true,2::smallint,'{}',NULL,false,0,'Two batch reviews','mfg_apv_batch_policy');
SELECT core10.publish_approval_policy_v1(9511,'manufacturing','recipe_approve',120,'mfg_apv_recipe_publish') AS recipe_policy \gset
SELECT core10.publish_approval_policy_v1(9511,'manufacturing','batch_release',120,'mfg_apv_batch_publish') AS batch_policy \gset
SELECT core10.configure_approval_route_v1(:recipe_policy,ARRAY['business_owner','tenant_owner'],'mfg_apv_recipe_route');
SELECT core10.configure_approval_route_v1(:batch_policy,ARRAY['business_owner','tenant_owner'],'mfg_apv_batch_route');

SELECT set_config('request.jwt.claims',:'maker',true);
SELECT core10.mfg_approval_packet_v1(9511,9521,'recipe_approve',:mr,:'effective') AS packet \gset
SELECT core10.mfg_submit_approval_v1(9511,9521,'recipe_approve',:mr,:'effective','mfg_apv_recipe_submit') AS recipe_request \gset
SELECT mfg_approval_test.expect(format('SELECT core10.mfg_approve_recipe_with_approval_v1(9511,9521,%s,%L,%s,%L)',
 :mr,:'effective',:recipe_request,'mfg_apv_recipe_apply'),'MFG_MAKER_CHECKER');
SELECT mfg_approval_test.expect(format('SELECT core10.decide_approval(%s,%L,%L)',:recipe_request,'approve','mfg_apv_maker_decide'),'approval_not_authorized');

SELECT set_config('request.jwt.claims',:'checker',true);
SELECT core10.decide_approval(:recipe_request,'approve','mfg_apv_recipe_first') AS recipe_first \gset
SELECT mfg_approval_test.expect(format('SELECT core10.mfg_approve_recipe_with_approval_v1(9511,9521,%s,%L,%s,%L)',
 :mr,:'effective',:recipe_request,'mfg_apv_recipe_apply'),'approval_not_effective');

SELECT set_config('request.jwt.claims',:'owner',true);
SELECT core10.decide_approval(:recipe_request,'approve','mfg_apv_recipe_final') AS recipe_final \gset
SELECT mfg_approval_test.expect(format('SELECT core10.mfg_approve_recipe_with_approval_v1(9511,9521,%s,%L,9999999,%L)',
 :mr,:'effective','mfg_apv_recipe_apply'),'approval_not_effective');
SELECT mfg_approval_test.expect(format('SELECT core10.mfg_approve_recipe_with_approval_v1(9511,9521,%s,%L,%s,%L)',
 :mr,'2026-01-02T00:00Z',:recipe_request,'mfg_apv_recipe_apply'),'approval_stale_or_payload_changed');
SELECT mfg_approval_test.expect(format('SELECT core10.mfg_approval_packet_v1(9511,9524,%L,%s,%L)',
 'recipe_approve',:mr,:'effective'),'MFG_SCOPE_DENIED');

-- Use an equivalent timestamp in a different session time zone.
SET LOCAL TIME ZONE 'Asia/Dhaka';
SELECT core10.mfg_approve_recipe_with_approval_v1(9511,9521,:mr,'2026-01-01T06:00:00+06:00',:recipe_request,'mfg_apv_recipe_apply') AS recipe_receipt \gset
SELECT core10.mfg_approve_recipe_with_approval_v1(9511,9521,:mr,:'effective',:recipe_request,'mfg_apv_recipe_apply') AS replay \gset
SELECT mfg_approval_test.ok(:'recipe_receipt'::jsonb->>'status'='approved'
 AND (:'recipe_receipt'::jsonb->>'approval_event_id')::bigint=:recipe_final
 AND :recipe_first<>:recipe_final
 AND :'replay'::jsonb=(:'recipe_receipt'::jsonb||'{"replayed":true}'::jsonb),'final recipe event and exact replay');
SELECT mfg_approval_test.expect(format('SELECT core10.mfg_approve_recipe_with_approval_v1(9511,9521,%s,%L,9999999,%L)',
 :mr,:'effective','mfg_apv_recipe_apply'),'MFG_REPLAY_CONFLICT');
SELECT core10.control_set_v1(9511,NULL,'mfg.recipe_approve',false,2::smallint,'{}',NULL,false,1,'Turn recipe approval off','mfg_apv_recipe_off');
SELECT mfg_approval_test.expect(format('SELECT core10.mfg_approve_recipe_with_approval_v1(9511,9521,%s,%L,%s,%L)',
 :mr,:'effective',:recipe_request,'mfg_apv_recipe_apply'),'CONTROL_DISABLED:mfg.recipe_approve');

SELECT set_config('request.jwt.claims',:'maker',true);
SELECT (core10.mfg_plan_batch_v1(9511,9521,:mr,9531,1,'mfg_apv_batch_plan')->>'batch_id')::bigint AS batch \gset
SELECT (core10.mfg_plan_batch_v1(9511,9521,:mr,9531,2,'mfg_apv_other_plan')->>'batch_id')::bigint AS other_batch \gset
SELECT core10.mfg_approval_packet_v1(9511,9521,'batch_release',:batch,NULL) AS packet \gset
SELECT core10.mfg_submit_approval_v1(9511,9521,'batch_release',:batch,NULL,'mfg_apv_batch_submit') AS batch_request \gset
SELECT set_config('request.jwt.claims',:'checker',true);
SELECT core10.decide_approval(:batch_request,'approve','mfg_apv_batch_first');
SELECT set_config('request.jwt.claims',:'owner',true);
SELECT core10.decide_approval(:batch_request,'approve','mfg_apv_batch_final') AS batch_final \gset
SELECT mfg_approval_test.expect(format('SELECT core10.mfg_release_batch_with_approval_v1(9511,9521,%s,%s,%L)',
 :other_batch,:batch_request,'mfg_apv_wrong_batch'),'approval_stale_or_payload_changed');
SELECT mfg_approval_test.expect(format('SELECT core10.mfg_release_batch_with_approval_v1(9511,9521,%s,%s,%L)',
 :batch,:recipe_request,'mfg_apv_wrong_action'),'approval_stale_or_payload_changed');
SELECT core10.mfg_release_batch_with_approval_v1(9511,9521,:batch,:batch_request,'mfg_apv_batch_apply') AS batch_receipt \gset
SELECT mfg_approval_test.ok(:'batch_receipt'::jsonb->>'status'='released'
 AND (:'batch_receipt'::jsonb->>'approval_event_id')::bigint=:batch_final
 AND :'batch_receipt'::jsonb->>'stock_issued'='false','final batch event and no Stock issue');
-- A genuine one-stage approval under a different GOV002 route cannot satisfy two Manufacturing stages.
SELECT core10.control_set_v1(9511,NULL,'gov002.review',true,1::smallint,'{}',NULL,false,1,'Shorter GOV route fixture','mfg_apv_gov_short');
SELECT core10.publish_approval_policy_v1(9511,'manufacturing','batch_release',120,'mfg_apv_batch_short_policy') AS short_policy \gset
SELECT core10.configure_approval_route_v1(:short_policy,ARRAY['tenant_owner'],'mfg_apv_batch_short_route');
SELECT mfg_approval_test.expect(format('SELECT core10.mfg_submit_approval_v1(9511,9521,%L,%s,NULL,%L)',
 'batch_release',:other_batch,'mfg_apv_wrong_submitter'),'MFG_APPROVAL_WRONG_MAKER');
SELECT set_config('request.jwt.claims',:'maker',true);
SELECT mfg_approval_test.expect(format('SELECT core10.mfg_submit_approval_v1(9511,9521,%L,%s,NULL,%L)',
 'batch_release',:other_batch,'mfg_apv_short_submit'),'MFG_APPROVAL_STAGES');
SELECT core10.mfg_approval_packet_v1(9511,9521,'batch_release',:other_batch,NULL) AS short_packet \gset
SELECT core10.submit_typed_approval_v1(9511,:'short_packet'::jsonb->>'domain',:'short_packet'::jsonb->>'action',
 :'short_packet'::jsonb->>'source_key',(:'short_packet'::jsonb->>'source_version')::bigint,
 :'short_packet'::jsonb->'payload','mfg_apv_short_submit') AS short_request \gset
SELECT set_config('request.jwt.claims',:'owner',true);
SELECT mfg_approval_test.ok(EXISTS(
 SELECT 1 FROM core10.my_routed_review_tasks_v1(9511)
 WHERE request_id=:short_request AND domain='manufacturing' AND stage_no=1 AND stage_total=1),
 'canonical Reviewer Desk receives legitimate single-stage Manufacturing tasks');
SELECT core10.decide_approval(:short_request,'approve','mfg_apv_short_final');
SELECT mfg_approval_test.expect(format('SELECT core10.mfg_release_batch_with_approval_v1(9511,9521,%s,%s,%L)',
 :other_batch,:short_request,'mfg_apv_short_apply'),'MFG_APPROVAL_STAGES');

SELECT core10.control_set_v1(9511,NULL,'gov002.review',false,1::smallint,'{}',NULL,false,2,'Turn GOV review off','mfg_apv_gov_off');
SELECT set_config('request.jwt.claims',:'maker',true);
SELECT mfg_approval_test.expect(format('SELECT core10.mfg_submit_approval_v1(9511,9521,%L,%s,NULL,%L)',
 'batch_release',:other_batch,'mfg_apv_short_submit'),'CONTROL_DISABLED:gov002.review');
SELECT set_config('request.jwt.claims',:'owner',true);
SELECT core10.control_set_v1(9511,NULL,'mfg.batch_release',false,2::smallint,'{}',NULL,false,1,'Turn batch release off','mfg_apv_batch_off');
SELECT mfg_approval_test.expect(format('SELECT core10.mfg_release_batch_with_approval_v1(9511,9521,%s,%s,%L)',
 :batch,:batch_request,'mfg_apv_batch_apply'),'CONTROL_DISABLED:mfg.batch_release');

RESET ROLE;
SELECT mfg_approval_test.ok(
 NOT EXISTS(SELECT 1 FROM core10.stock_balances_v1 WHERE business_id=9511)
 AND NOT EXISTS(SELECT 1 FROM core10.stock_transfers_v1 WHERE business_id=9511)
 AND NOT EXISTS(SELECT 1 FROM core10.finance_journals_v1 WHERE business_id=9511),
 'Approval and batch release create no Stock or Finance posting');
SELECT mfg_approval_test.ok(
 (SELECT count(*)=2 FROM core10.canonical_audit_events_v1
  WHERE business_id=9511 AND (
   (request_key='mfg:mfg_apv_recipe_apply' AND payload->'result'->>'approval_event_id'=:recipe_final::text
    AND payload->'command'->>'approval_request_id'=:recipe_request::text)
   OR (request_key='mfg:mfg_apv_batch_apply' AND payload->'result'->>'approval_event_id'=:batch_final::text
    AND payload->'command'->>'approval_request_id'=:batch_request::text))),
 'canonical Audit binds both final Approval receipts');
SELECT mfg_approval_test.ok(
 NOT has_function_privilege('anon','core10.mfg_approval_packet_v1(bigint,bigint,text,bigint,timestamptz)','EXECUTE')
 AND NOT has_function_privilege('authenticated','core10._mfg_completed_approval_v1(bigint,bigint,bigint,bigint,text,bigint,timestamptz)','EXECUTE'),
 'no anonymous packet read or direct verifier call');
ROLLBACK;
