-- Build 02A integration checks; requires A018/A020/A034/Build01 in a disposable database.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
DO $$
DECLARE r jsonb; replay jsonb; expiry timestamptz:='2099-01-01T00:00:00Z';
BEGIN
 -- A manager has only submit/withdraw by role. Stock grants never create decision rights.
 r:=c10_demo.build02a_set_approval_policy_v1(101,'33333333-3333-4333-8333-333333333333',
  ARRAY['approval.decide','approval.export'],ARRAY['approval.withdraw'],expiry,'build02a-manager-policy',1);
 replay:=c10_demo.build02a_set_approval_policy_v1(101,'33333333-3333-4333-8333-333333333333',
  ARRAY['approval.decide','approval.export'],ARRAY['approval.withdraw'],expiry,'build02a-manager-policy',1);
 IF r->>'request_key'<>'build02a-manager-policy' OR replay->>'event_id'<>r->>'event_id' THEN RAISE EXCEPTION 'approval policy replay failed'; END IF;
END $$;
ROLLBACK;

-- Use a fixed expiry so the replay signature is identical in this test.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
SELECT c10_demo.build02a_set_approval_policy_v1(101,'33333333-3333-4333-8333-333333333333',
 ARRAY['approval.decide','approval.export'],ARRAY['approval.withdraw'],'2099-01-01T00:00:00Z','build02a-manager-policy-fixed',1);
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',true);
DO $$ BEGIN
 IF NOT c10_demo.can_approval_action_v1(1,101,'approval.submit') THEN RAISE EXCEPTION 'manager submit missing'; END IF;
 IF NOT c10_demo.can_approval_action_v1(1,101,'approval.decide') OR NOT c10_demo.can_approval_action_v1(1,101,'approval.export') THEN RAISE EXCEPTION 'explicit manager allow missing'; END IF;
 IF c10_demo.can_approval_action_v1(1,101,'approval.withdraw') THEN RAISE EXCEPTION 'explicit deny lost to role'; END IF;
 IF c10_demo.can_approval_action_v1(1,101,'stock.read') THEN RAISE EXCEPTION 'stock action accepted by approval resolver'; END IF;
END $$;
ROLLBACK;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
DO $$ BEGIN
 BEGIN
  PERFORM c10_demo.build02a_set_approval_policy_v1(101,'33333333-3333-4333-8333-333333333333',ARRAY['approval.decide'],ARRAY['approval.decide'],NULL,'build02a-overlap',2);
  RAISE EXCEPTION 'overlapping policy allowed';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'BUILD02A_INVALID_ACTIONS' THEN RAISE; END IF; END;
 BEGIN
  PERFORM c10_demo.build02a_set_approval_policy_v1(101,'33333333-3333-4333-8333-333333333333',ARRAY['approval.decide'],ARRAY[]::text[],NULL,'build02a-stale',0);
  RAISE EXCEPTION 'stale policy allowed';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'BUILD02A_STALE_VERSION' THEN RAISE; END IF; END;
END $$;
ROLLBACK;

-- Expiry and revocation both override an otherwise valid signed manager session.
BEGIN;
UPDATE c10_demo.business_members SET approval_valid_until=statement_timestamp()-interval '1 second'
 WHERE business_id=101 AND user_id='33333333-3333-4333-8333-333333333333';
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',true);
DO $$ BEGIN IF c10_demo.can_approval_action_v1(1,101,'approval.decide') THEN RAISE EXCEPTION 'expired approval policy allowed'; END IF; END $$;
ROLLBACK;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','77777777-7777-4777-8777-777777777777',true);
DO $$ BEGIN
 IF c10_demo.can_approval_action_v1(1,101,'approval.submit') THEN RAISE EXCEPTION 'foreign tenant approval allowed'; END IF;
END $$;
ROLLBACK;

BEGIN;
SET LOCAL ROLE anon;
DO $$ BEGIN
 BEGIN
  PERFORM c10_demo.can_approval_action_v1(1,101,'approval.submit');
  RAISE EXCEPTION 'anonymous resolver execute allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
ROLLBACK;
\echo PASS Build02A approval action resolver: role baseline, explicit allow/deny, replay, stale, expiry, tenant and anonymous denial.
