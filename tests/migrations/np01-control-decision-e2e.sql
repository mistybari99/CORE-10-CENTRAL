-- B-020 0019: disposable PG17 Owner Control decision/withdrawal proof.
-- Two tenants, synthetic Owner/maker/foreign Owner; rollback all fixtures.
\set ON_ERROR_STOP on
BEGIN;
INSERT INTO core10.tenants(id,slug) VALUES
 (99701,'np01-b020-review-a'),(99702,'np01-b020-review-b');
INSERT INTO core10.legal_entities(id,tenant_id,label) VALUES
 (99711,99701,'B020 legal A'),(99712,99702,'B020 legal B');
INSERT INTO core10.businesses(id,tenant_id,legal_entity_id,slug,template_code,request_key)
 VALUES (99721,99701,99711,'b020-review-a','sweets_bakery','np01_b020_review_biz_a_01'),
        (99722,99702,99712,'b020-review-b','sweets_bakery','np01_b020_review_biz_b_01');
INSERT INTO core10.tenant_members(tenant_id,user_id,role) VALUES
 (99701,'99711111-1111-4111-8111-111111111111','tenant_owner'),
 (99702,'99733333-3333-4333-8333-333333333333','tenant_owner');
INSERT INTO core10.business_members(tenant_id,business_id,user_id,role) VALUES
 (99701,99721,'99722222-2222-4222-8222-222222222222','manager');
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims','{"sub":"99711111-1111-4111-8111-111111111111"}',true);
SELECT set_config('request.jwt.claim.sub','99711111-1111-4111-8111-111111111111',true);
DO $t$
BEGIN
 PERFORM core10.publish_approval_policy_v1(99721,'inventory','adjust',120,'b020_review_policy_01');
END $t$;
SELECT set_config('request.jwt.claims','{"sub":"99722222-2222-4222-8222-222222222222"}',true);
SELECT set_config('request.jwt.claim.sub','99722222-2222-4222-8222-222222222222',true);
DO $t$
DECLARE q1 bigint; q2 bigint;
BEGIN
 q1:=core10.submit_typed_approval_v1(99721,'inventory','adjust','review-source-01',1,
  '{"amount":120}'::jsonb,'b020_review_submit_01');
 q2:=core10.submit_typed_approval_v1(99721,'inventory','adjust','review-source-02',1,
  '{"amount":130}'::jsonb,'b020_review_submit_02');
 PERFORM set_config('core10.b020_review_q1',q1::text,true);
 PERFORM set_config('core10.b020_review_q2',q2::text,true);
 BEGIN
  PERFORM core10.decide_approval(q1,'approve','b020_review_self_01');
  RAISE EXCEPTION 'B020_SELF_APPROVAL_PASSED';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM <> 'approval_not_authorized' THEN RAISE; END IF;
 END;
END $t$;
-- Owner disables review; denial must be before idempotent replay and before any write.
SELECT set_config('request.jwt.claims','{"sub":"99711111-1111-4111-8111-111111111111"}',true);
SELECT set_config('request.jwt.claim.sub','99711111-1111-4111-8111-111111111111',true);
DO $t$
DECLARE c jsonb; n_before bigint;
BEGIN
 c:=core10.control_set_v1(99721,NULL,'gov002.review',false,1::smallint,'{}',NULL,
  false,0,'B020 review disabled for negative proof','b020_review_disable_01');
 IF (c->>'version')::integer<>1 THEN RAISE EXCEPTION 'B020_CONTROL_BAD_VERSION'; END IF;
 SELECT count(*) INTO n_before FROM core10.approval_events WHERE business_id=99721;
 BEGIN
  PERFORM core10.decide_approval(current_setting('core10.b020_review_q1')::bigint,
   'approve','b020_review_denied_01');
  RAISE EXCEPTION 'B020_DISABLED_REVIEW_ACCEPTED';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM NOT LIKE 'CONTROL_DISABLED:gov002.review%' THEN RAISE; END IF;
 END;
 IF (SELECT count(*) FROM core10.approval_events WHERE business_id=99721)<>n_before
 THEN RAISE EXCEPTION 'B020_DISABLED_REVIEW_EVENT_EMITTED'; END IF;
END $t$;
-- A foreign tenant remains denied at the Auth port (before the Control check).
SELECT set_config('request.jwt.claims','{"sub":"99733333-3333-4333-8333-333333333333"}',true);
SELECT set_config('request.jwt.claim.sub','99733333-3333-4333-8333-333333333333',true);
DO $t$
BEGIN
 BEGIN
  PERFORM core10.decide_approval(current_setting('core10.b020_review_q1')::bigint,
   'approve','b020_foreign_vote_01');
  RAISE EXCEPTION 'B020_CROSS_TENANT_VOTE_ACCEPTED';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM <> 'approval_not_authorized' THEN RAISE; END IF;
 END;
END $t$;
-- Maker's withdrawal must fail while review is disabled.
SELECT set_config('request.jwt.claims','{"sub":"99722222-2222-4222-8222-222222222222"}',true);
SELECT set_config('request.jwt.claim.sub','99722222-2222-4222-8222-222222222222',true);
DO $t$
BEGIN
 BEGIN
  PERFORM core10.withdraw_typed_approval_v1(
    current_setting('core10.b020_review_q2')::bigint,'b020_review_withdraw_denied_01');
  RAISE EXCEPTION 'B020_DISABLED_WITHDRAW_ACCEPTED';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM NOT LIKE 'CONTROL_DISABLED:gov002.review%' THEN RAISE; END IF;
 END;
 IF (SELECT status FROM core10.approval_requests
     WHERE id=current_setting('core10.b020_review_q2')::bigint)<>'pending'
 THEN RAISE EXCEPTION 'B020_DISABLED_WITHDRAW_MUTATED'; END IF;
END $t$;
-- Owner re-enables; decision succeeds, is replay-stable and canonically audited.
SELECT set_config('request.jwt.claims','{"sub":"99711111-1111-4111-8111-111111111111"}',true);
SELECT set_config('request.jwt.claim.sub','99711111-1111-4111-8111-111111111111',true);
DO $t$
DECLARE c jsonb; vote bigint;
BEGIN
 c:=core10.control_set_v1(99721,NULL,'gov002.review',true,1::smallint,'{}',NULL,
  false,1,'B020 review re-enabled','b020_review_enable_02');
 IF (c->>'version')::integer<>2 THEN RAISE EXCEPTION 'B020_CONTROL_ENABLE_VERSION'; END IF;
 vote:=core10.decide_approval(current_setting('core10.b020_review_q1')::bigint,
  'approve','b020_review_allowed_01');
 IF core10.decide_approval(current_setting('core10.b020_review_q1')::bigint,
  'approve','b020_review_allowed_01')<>vote THEN
  RAISE EXCEPTION 'B020_REVIEW_REPLAY_DRIFT'; END IF;
 IF (SELECT status FROM core10.approval_requests
  WHERE id=current_setting('core10.b020_review_q1')::bigint)<>'approved'
 THEN RAISE EXCEPTION 'B020_REVIEW_APPROVAL_MISSING'; END IF;
 IF (core10.verify_canonical_audit_v1(99721)->>'ok')<>'true'
 THEN RAISE EXCEPTION 'B020_CANONICAL_AUDIT_INVALID'; END IF;
END $t$;
SELECT set_config('request.jwt.claims','{"sub":"99722222-2222-4222-8222-222222222222"}',true);
SELECT set_config('request.jwt.claim.sub','99722222-2222-4222-8222-222222222222',true);
DO $t$
DECLARE receipt bigint;
BEGIN
 receipt:=core10.withdraw_typed_approval_v1(
  current_setting('core10.b020_review_q2')::bigint,'b020_review_withdraw_allowed_01');
 IF receipt<>core10.withdraw_typed_approval_v1(
  current_setting('core10.b020_review_q2')::bigint,'b020_review_withdraw_allowed_01')
 THEN RAISE EXCEPTION 'B020_WITHDRAW_REPLAY_DRIFT'; END IF;
 IF (SELECT status FROM core10.approval_requests
  WHERE id=current_setting('core10.b020_review_q2')::bigint)<>'withdrawn'
 THEN RAISE EXCEPTION 'B020_WITHDRAW_STATUS_MISSING'; END IF;
 RAISE NOTICE 'B020_REVIEW_CONTROL_PG17_OK';
END $t$;
ROLLBACK;
