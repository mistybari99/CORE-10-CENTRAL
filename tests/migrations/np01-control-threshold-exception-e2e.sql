-- NP01 / B-020 / 0114 disposable PG17: six restored GOV002 RPCs.
-- Canonical Auth -> Control before replay, precise threshold/unit validation, escalations
-- as *triage only*, tenant RLS, immutable Audit, registry evidence. No hosted DB.
\set ON_ERROR_STOP on
BEGIN;
INSERT INTO core10.tenants(id,slug) VALUES
 (99901,'np01-0114-tenant-a'),(99902,'np01-0114-tenant-b');
INSERT INTO core10.legal_entities(id,tenant_id,label) VALUES
 (99911,99901,'NP01 0114 Legal A'),(99912,99902,'NP01 0114 Legal B');
INSERT INTO core10.businesses(id,tenant_id,legal_entity_id,slug,template_code,request_key)
 VALUES(99921,99901,99911,'np01-0114-biz-a','sweets_bakery','np01_0114_biza_01'),
       (99922,99902,99912,'np01-0114-biz-b','sweets_bakery','np01_0114_bizb_01');
INSERT INTO core10.tenant_members(tenant_id,user_id,role)
 VALUES(99901,'99911111-1111-4111-8111-111111111111','tenant_owner'),
       (99902,'99922222-2222-4222-8222-222222222222','tenant_owner');
INSERT INTO core10.business_members(tenant_id,business_id,user_id,role)
 VALUES(99901,99921,'99933333-3333-4333-8333-333333333333','manager'),
       (99901,99921,'99944444-4444-4444-8444-444444444444','business_owner'),
       (99901,99921,'99955555-5555-4555-8555-555555555555','manager');
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims','{"sub":"99911111-1111-4111-8111-111111111111"}',true);
SELECT set_config('request.jwt.claim.sub','99911111-1111-4111-8111-111111111111',true);
DO $t$
DECLARE
 owner_uid constant text:='99911111-1111-4111-8111-111111111111';
 other_uid constant text:='99922222-2222-4222-8222-222222222222';
 maker_uid constant text:='99933333-3333-4333-8333-333333333333';
 business_owner constant text:='99944444-4444-4444-8444-444444444444';
 manager2 constant text:='99955555-5555-4555-8555-555555555555';
 pol bigint;req1 bigint;req2 bigint;req3 bigint;esc1 bigint;esc2 bigint;esc3 bigint;
 ev bigint;v jsonb;before_audit bigint; before_exc bigint; a text; b text;
BEGIN
 pol:=core10.publish_approval_policy_v1(99921,'stock','adjust',120,'np01_0114_policy_01');
 IF core10.configure_approval_threshold_v1(pol,'quantity','KG',4.125,3,'np01_0114_threshold_01')<>pol
 THEN RAISE EXCEPTION 'NP01_0114_THRESHOLD_NOT_CREATED'; END IF;
 IF core10.configure_approval_threshold_v1(pol,'quantity','KG',4.125,3,'np01_0114_threshold_01')<>pol
 THEN RAISE EXCEPTION 'NP01_0114_THRESHOLD_REPLAY_CHANGED'; END IF;
 BEGIN
  PERFORM core10.configure_approval_threshold_v1(pol,'quantity','KG',5.000,3,'np01_0114_threshold_01');
  RAISE EXCEPTION 'NP01_0114_THRESHOLD_REPLAY_CONFLICT_MISSED';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'approval_threshold_replay_conflict' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM core10.configure_approval_threshold_v1(pol,'quantity','KG',4.125001,3,'np01_0114_precision_bad');
  RAISE EXCEPTION 'NP01_0114_THRESHOLD_PRECISION_MISSED';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'invalid_approval_threshold' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM core10.configure_approval_threshold_v1(pol,'quantity','bad',4.125,3,'np01_0114_unit_bad');
  RAISE EXCEPTION 'NP01_0114_THRESHOLD_UNIT_MISSED';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'invalid_approval_threshold' THEN RAISE; END IF;
 END;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',maker_uid)::text,true);
 PERFORM set_config('request.jwt.claim.sub',maker_uid,true);
 IF core10.assess_approval_threshold_v1(pol,'{"amount":4.125,"unit":"KG"}'::jsonb)<>'REVIEW_REQUIRED'
 OR core10.assess_current_approval_threshold_v1(99921,'stock','adjust','{"amount":4.125,"unit":"KG"}'::jsonb)<>'REVIEW_REQUIRED'
 OR core10.assess_current_approval_threshold_v1(99921,'stock','adjust','{"amount":4.124,"unit":"KG"}'::jsonb)<>'BELOW_THRESHOLD'
 THEN RAISE EXCEPTION 'NP01_0114_THRESHOLD_ASSESSMENT_INCORRECT'; END IF;
 BEGIN
  PERFORM core10.assess_approval_threshold_v1(pol,'{"amount":4.125,"unit":"PCS"}'::jsonb);
  RAISE EXCEPTION 'NP01_0114_ASSESSMENT_UNIT_BYPASS';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'approval_threshold_unit_or_amount_invalid' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM core10.assess_current_approval_threshold_v1(99921,'stock','adjust','{"amount":4.1251,"unit":"KG"}'::jsonb);
  RAISE EXCEPTION 'NP01_0114_ASSESSMENT_SCALE_BYPASS';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'approval_threshold_precision_invalid' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM core10.configure_approval_threshold_v1(pol,'quantity','KG',4.125,3,'np01_0114_manager_forbidden');
  RAISE EXCEPTION 'NP01_0114_MANAGER_CONFIGURED_THRESHOLD';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'threshold_not_authorized' THEN RAISE; END IF;
 END;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',other_uid)::text,true);
 PERFORM set_config('request.jwt.claim.sub',other_uid,true);
 BEGIN
  PERFORM core10.assess_approval_threshold_v1(pol,'{"amount":4.125,"unit":"KG"}'::jsonb);
  RAISE EXCEPTION 'NP01_0114_FOREIGN_ASSESS_POLICY';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'approval_assessment_denied' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM core10.assess_current_approval_threshold_v1(99921,'stock','adjust','{"amount":4.125,"unit":"KG"}'::jsonb);
  RAISE EXCEPTION 'NP01_0114_FOREIGN_ASSESS_CURRENT';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'approval_assessment_denied' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM core10.configure_approval_threshold_v1(pol,'quantity','KG',4.125,3,'np01_0114_foreign_forbidden');
  RAISE EXCEPTION 'NP01_0114_FOREIGN_CONFIGURED';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'threshold_not_authorized' THEN RAISE; END IF;
 END;
 -- Foreign Owner cannot see A's threshold or Audit events under canonical RLS.
 IF EXISTS(SELECT 1 FROM core10.approval_thresholds_v1 WHERE policy_id=pol)
 OR EXISTS(SELECT 1 FROM core10.canonical_audit_events_v1 WHERE business_id=99921)
 THEN RAISE EXCEPTION 'NP01_0114_FOREIGN_RLS_DISCLOSURE'; END IF;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',owner_uid)::text,true);
 PERFORM set_config('request.jwt.claim.sub',owner_uid,true);
 v:=core10.control_set_v1(99921,NULL,'gov002.approval_policy',false,0::smallint,'{}',NULL,
  false,0,'0114 disable threshold policy','np01_0114_threshold_off_01');
 BEGIN
  PERFORM core10.configure_approval_threshold_v1(pol,'quantity','KG',4.125,3,'np01_0114_threshold_01');
  RAISE EXCEPTION 'NP01_0114_DISABLED_CONFIG_REPLAY';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'CONTROL_DISABLED:gov002.approval_policy%' THEN RAISE; END IF;
 END;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',maker_uid)::text,true);
 PERFORM set_config('request.jwt.claim.sub',maker_uid,true);
 BEGIN
  PERFORM core10.assess_approval_threshold_v1(pol,'{"amount":4.125,"unit":"KG"}'::jsonb);
  RAISE EXCEPTION 'NP01_0114_DISABLED_ASSESS_POLICY';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'CONTROL_DISABLED:gov002.approval_policy%' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM core10.assess_current_approval_threshold_v1(99921,'stock','adjust','{"amount":4.125,"unit":"KG"}'::jsonb);
  RAISE EXCEPTION 'NP01_0114_DISABLED_ASSESS_CURRENT';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'CONTROL_DISABLED:gov002.approval_policy%' THEN RAISE; END IF;
 END;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',owner_uid)::text,true);
 PERFORM set_config('request.jwt.claim.sub',owner_uid,true);
 v:=core10.control_set_v1(99921,NULL,'gov002.approval_policy',true,0::smallint,'{}',NULL,
  false,1,'0114 restore threshold policy','np01_0114_threshold_on_02');
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',maker_uid)::text,true);
 PERFORM set_config('request.jwt.claim.sub',maker_uid,true);
 req1:=core10.submit_typed_approval_v1(99921,'stock','adjust','np01-0114-source1',1,
  '{"amount":4.125,"unit":"KG"}'::jsonb,'np01_0114_submit_01');
 req2:=core10.submit_typed_approval_v1(99921,'stock','adjust','np01-0114-source2',1,
  '{"amount":4.250,"unit":"KG"}'::jsonb,'np01_0114_submit_02');
 req3:=core10.submit_typed_approval_v1(99921,'stock','adjust','np01-0114-source3',1,
  '{"amount":4.375,"unit":"KG"}'::jsonb,'np01_0114_submit_03');
 esc1:=core10.request_approval_exception_v1(req1,'Needs independent exception triage','urgent',30,'np01_0114_exc_req_01');
 IF core10.request_approval_exception_v1(req1,'Needs independent exception triage','urgent',30,'np01_0114_exc_req_01')<>esc1
 THEN RAISE EXCEPTION 'NP01_0114_EXCEPTION_SUBMIT_REPLAY'; END IF;
 BEGIN
  PERFORM core10.request_approval_exception_v1(req1,'Different exception reason','urgent',30,'np01_0114_exc_req_01');
  RAISE EXCEPTION 'NP01_0114_EXCEPTION_REPLAY_CONFLICT_MISSED';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'exception_request_replay_conflict' THEN RAISE; END IF;
 END;
 esc2:=core10.request_approval_exception_v1(req2,'Second escalation to withdraw later','normal',15,'np01_0114_exc_req_02');
 esc3:=core10.request_approval_exception_v1(req3,'Third escalation to decline later','normal',15,'np01_0114_exc_req_03');
 BEGIN
  PERFORM core10.decide_approval_exception_v1(esc1,'acknowledged','np01_0114_maker_decide_01');
  RAISE EXCEPTION 'NP01_0114_MAKER_CHECKER_BYPASS';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'exception_decision_denied' THEN RAISE; END IF;
 END;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',other_uid)::text,true);
 PERFORM set_config('request.jwt.claim.sub',other_uid,true);
 BEGIN
  PERFORM core10.request_approval_exception_v1(req1,'Other tenant attempted escalation','normal',10,'np01_0114_foreign_req');
  RAISE EXCEPTION 'NP01_0114_FOREIGN_REQUEST';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'exception_request_denied' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM core10.decide_approval_exception_v1(esc1,'acknowledged','np01_0114_foreign_decide');
  RAISE EXCEPTION 'NP01_0114_FOREIGN_DECIDE';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'exception_decision_denied' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM core10.withdraw_approval_exception_v1(esc2,'np01_0114_foreign_withdraw');
  RAISE EXCEPTION 'NP01_0114_FOREIGN_WITHDRAW';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'exception_withdraw_denied' THEN RAISE; END IF;
 END;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',owner_uid)::text,true);
 PERFORM set_config('request.jwt.claim.sub',owner_uid,true);
 v:=core10.control_set_v1(99921,NULL,'gov002.review',true,1::smallint,
  '{"exception_escalation":false}'::jsonb,NULL,false,0,
  '0114 Owner disables exception escalation','np01_0114_exc_param_off_01');
 BEGIN
  PERFORM core10.decide_approval_exception_v1(esc1,'acknowledged','np01_0114_owner_rejected_01');
  RAISE EXCEPTION 'NP01_0114_EXCEPTION_PARAM_DECISION_BYPASS';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'CONTROL_EXCEPTION_ESCALATION_DISABLED' THEN RAISE; END IF;
 END;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',maker_uid)::text,true);
 PERFORM set_config('request.jwt.claim.sub',maker_uid,true);
 BEGIN
  PERFORM core10.request_approval_exception_v1(req1,'Needs independent exception triage','urgent',30,'np01_0114_exc_req_01');
  RAISE EXCEPTION 'NP01_0114_EXCEPTION_PARAM_REPLAY_BYPASS';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'CONTROL_EXCEPTION_ESCALATION_DISABLED' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM core10.withdraw_approval_exception_v1(esc2,'np01_0114_withdraw_disabled_01');
  RAISE EXCEPTION 'NP01_0114_EXCEPTION_PARAM_WITHDRAW_BYPASS';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'CONTROL_EXCEPTION_ESCALATION_DISABLED' THEN RAISE; END IF;
 END;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',owner_uid)::text,true);
 PERFORM set_config('request.jwt.claim.sub',owner_uid,true);
 v:=core10.control_set_v1(99921,NULL,'gov002.review',true,1::smallint,
  '{"exception_escalation":true}'::jsonb,NULL,false,1,
  '0114 restore exception escalation','np01_0114_exc_param_on_02');
 ev:=core10.decide_approval_exception_v1(esc1,'acknowledged','np01_0114_exc_ack_01');
 IF core10.decide_approval_exception_v1(esc1,'acknowledged','np01_0114_exc_ack_01')<>ev
 THEN RAISE EXCEPTION 'NP01_0114_DECISION_REPLAY'; END IF;
 IF (SELECT status FROM core10.approval_requests WHERE id=req1)<>'pending'
 OR (SELECT count(*) FROM core10.stock_movements WHERE business_id=99921)<>0
 THEN RAISE EXCEPTION 'NP01_0114_EXCEPTION_ACK_POSTED_DOMAIN'; END IF;
 BEGIN
  PERFORM core10.decide_approval_exception_v1(esc1,'declined','np01_0114_other_decision_01');
  RAISE EXCEPTION 'NP01_0114_TERMINAL_EXCEPTION_MUTATED';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'exception_stale_or_final' THEN RAISE; END IF;
 END;
 PERFORM core10.decide_approval_exception_v1(esc3,'declined','np01_0114_exc_decline_03');
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',maker_uid)::text,true);
 PERFORM set_config('request.jwt.claim.sub',maker_uid,true);
 ev:=core10.withdraw_approval_exception_v1(esc2,'np01_0114_exc_withdraw_02');
 IF core10.withdraw_approval_exception_v1(esc2,'np01_0114_exc_withdraw_02')<>ev
 THEN RAISE EXCEPTION 'NP01_0114_WITHDRAW_REPLAY'; END IF;
 BEGIN
  PERFORM core10.withdraw_approval_exception_v1(esc1,'np01_0114_withdraw_final_01');
  RAISE EXCEPTION 'NP01_0114_FINAL_WITHDRAW_SUCCEEDED';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'exception_stale_or_final' THEN RAISE; END IF;
 END;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',owner_uid)::text,true);
 PERFORM set_config('request.jwt.claim.sub',owner_uid,true);
 SELECT count(*) INTO before_exc FROM core10.approval_exception_events_v1 WHERE business_id=99921;
 SELECT count(*) INTO before_audit FROM core10.canonical_audit_events_v1 WHERE business_id=99921;
 v:=core10.control_set_v1(99921,NULL,'gov002.review',false,1::smallint,
  '{"exception_escalation":true}'::jsonb,NULL,false,2,
  '0114 pause exception lifecycle','np01_0114_exc_feature_off_03');
 BEGIN
  PERFORM core10.decide_approval_exception_v1(esc1,'acknowledged','np01_0114_exc_ack_01');
  RAISE EXCEPTION 'NP01_0114_DISABLED_DECIDE_REPLAY';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'CONTROL_DISABLED:gov002.review%' THEN RAISE; END IF;
 END;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',maker_uid)::text,true);
 PERFORM set_config('request.jwt.claim.sub',maker_uid,true);
 BEGIN
  PERFORM core10.request_approval_exception_v1(req1,'Needs independent exception triage','urgent',30,'np01_0114_exc_req_01');
  RAISE EXCEPTION 'NP01_0114_DISABLED_SUBMIT_REPLAY';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'CONTROL_DISABLED:gov002.review%' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM core10.withdraw_approval_exception_v1(esc2,'np01_0114_exc_withdraw_02');
  RAISE EXCEPTION 'NP01_0114_DISABLED_WITHDRAW_REPLAY';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT LIKE 'CONTROL_DISABLED:gov002.review%' THEN RAISE; END IF;
 END;
 -- The canonical Audit RLS permits Owner reads only; a manager cannot
 -- observe the Owner's chain. Restore the Owner identity for audit counters.
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',owner_uid)::text,true);
 PERFORM set_config('request.jwt.claim.sub',owner_uid,true);
 IF (SELECT count(*) FROM core10.approval_exception_events_v1 WHERE business_id=99921)<>before_exc
 OR (SELECT count(*) FROM core10.canonical_audit_events_v1 WHERE business_id=99921)<>before_audit+1
 THEN RAISE EXCEPTION 'NP01_0114_DISABLED_MUTATED_EXCEPTION_JOURNAL'; END IF;
 RAISE NOTICE 'NP01_0114_GOV002_AUTH_CONTROL_REPLAY_PRECISION_EXCEPTION_OK';
END $t$;
RESET ROLE;
DO $registry$
DECLARE n text;count_event bigint;
BEGIN
 FOREACH n IN ARRAY ARRAY[
   'assess_approval_threshold_v1','assess_current_approval_threshold_v1',
   'configure_approval_threshold_v1','request_approval_exception_v1',
   'decide_approval_exception_v1','withdraw_approval_exception_v1'] LOOP
  IF NOT EXISTS(SELECT 1 FROM core10.control_rpc_map_v1 m
   WHERE m.rpc_name=n AND m.status='enforced' AND m.test_ref='tests/migrations/np01-control-threshold-exception-e2e.sql'
     AND m.feature_key IN ('gov002.approval_policy','gov002.review'))
  THEN RAISE EXCEPTION 'NP01_0114_UNENFORCED_RPC:%',n; END IF;
 END LOOP;
 IF (SELECT count(*) FROM core10.approval_thresholds_v1 WHERE business_id=99921)<>1
 THEN RAISE EXCEPTION 'NP01_0114_THRESHOLD_EXTRA_WRITES'; END IF;
 SELECT count(*) INTO count_event FROM core10.approval_exception_events_v1 WHERE business_id=99921;
 IF count_event<>6 THEN RAISE EXCEPTION 'NP01_0114_EXCEPTION_JOURNAL_WRONG:%',count_event; END IF;
 IF NOT (SELECT (core10.verify_canonical_audit_v1(99921)->>'ok')::boolean)
 THEN RAISE EXCEPTION 'NP01_0114_CANONICAL_AUDIT_BROKEN'; END IF;
 IF EXISTS(SELECT 1 FROM core10.approval_exception_escalations_v1
    WHERE business_id=99921 AND status NOT IN ('acknowledged','declined','withdrawn'))
 THEN RAISE EXCEPTION 'NP01_0114_EXCEPTION_STATE_NOT_FINAL'; END IF;
 RAISE NOTICE 'NP01_0114_REGISTRY_CANONICAL_AUDIT_OK';
END $registry$;
ROLLBACK;
