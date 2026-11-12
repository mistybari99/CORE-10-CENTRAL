-- GOV002 source-derived atomic execution / compensating reversal E2E.
-- Disposable PostgreSQL17 only. Parent A018/A008 + threshold suites must pass.
\set ON_ERROR_STOP on

-- Business Owner publishes immutable versioned post/reverse review policies.
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
DO $t$
DECLARE p bigint;r bigint;
BEGIN
 p:=c10_demo.publish_approval_policy_v1(
   101,'demo_stock','post_adjustment',60,'demo_post_policy_01');
 r:=c10_demo.publish_approval_policy_v1(
   101,'demo_stock','reverse_adjustment',60,'demo_rev_policy_01');
 PERFORM c10_demo.configure_approval_threshold_v1(
  p,'quantity','KG',1.000,'demo_post_threshold_01');
 PERFORM c10_demo.configure_approval_threshold_v1(
  r,'quantity','KG',1.000,'demo_rev_threshold_01');
END $t$;

-- Manager creates durable source COMMAND; the payload is DERIVED by DB,
-- not an arbitrary UI value. Other item/business/site cannot be smuggled.
SELECT set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',false);
DO $t$
DECLARE v bigint;again bigint;r bigint;
BEGIN
 v:=c10_demo.prepare_demo_stock_v1(5001,8001,5,'demo_src_prepare_01');
 again:=c10_demo.prepare_demo_stock_v1(5001,8001,5,'demo_src_prepare_01');
 IF v<>again THEN RAISE EXCEPTION 'FAIL: source create replay'; END IF;
 BEGIN
  PERFORM c10_demo.prepare_demo_stock_v1(5001,8001,6,'demo_src_prepare_01');
  RAISE EXCEPTION 'FAIL: changed source reused same key';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'demo_source_replay_conflict' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM c10_demo.prepare_demo_stock_v1(5001,8002,5,'demo_cross_item_01');
  RAISE EXCEPTION 'FAIL: other business item accepted';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'demo_source_not_authorized' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM c10_demo.prepare_demo_stock_v1(5001,8001,-5,'demo_negative_01');
  RAISE EXCEPTION 'FAIL: negative demo adjustment accepted';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'invalid_demo_stock_source' THEN RAISE; END IF;
 END;
 r:=c10_demo.submit_typed_approval_v1(
  101,'demo_stock','post_adjustment','demo-adjustment:'||v,1,
  c10_demo.demo_stock_payload_v1(v),'demo_submit_for_post_01');
 IF r IS NULL THEN RAISE EXCEPTION 'FAIL: typed command request'; END IF;
 IF (SELECT count(*) FROM c10_demo.stock_movements)<>0
 THEN RAISE EXCEPTION 'FAIL: stock moved BEFORE approval'; END IF;
END $t$;

-- Site-only or investor MUST NOT create a sourced business-wide approval.
SELECT set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',false);
DO $t$ BEGIN
 BEGIN
  PERFORM c10_demo.prepare_demo_stock_v1(5001,8001,2,'site_only_demo_stock_01');
  RAISE EXCEPTION 'FAIL: site-only source creator bypass';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'demo_source_not_authorized' THEN RAISE; END IF;
 END;
 IF (SELECT count(*) FROM c10_demo.approval_demo_stock_commands_v1)<>0
 THEN RAISE EXCEPTION 'FAIL: site-only source read leakage'; END IF;
END $t$;
SELECT set_config('request.jwt.claim.sub','55555555-5555-4555-8555-555555555555',false);
DO $t$ BEGIN
 BEGIN
  PERFORM c10_demo.prepare_demo_stock_v1(5001,8001,2,'investor_demo_stock_01');
  RAISE EXCEPTION 'FAIL: investor creates command';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'demo_source_not_authorized' THEN RAISE; END IF;
 END;
END $t$;

-- Service role cannot execute merely because a manager requested approval.
RESET ROLE;
SELECT set_config('demo.test.post_a',
 (SELECT id::text FROM c10_demo.approval_requests
  WHERE submit_key_v1='demo_submit_for_post_01'),false);
SET ROLE service_role;
DO $t$ BEGIN
 BEGIN
  PERFORM c10_demo.execute_approved_demo_stock_v1(
    1,current_setting('demo.test.post_a')::bigint,'demo_exec_post_01');
  RAISE EXCEPTION 'FAIL: unapproved command posted';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'approval_not_effective' THEN RAISE; END IF;
 END;
END $t$;
RESET ROLE;

-- Independent business Owner approves exact maker submission.
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
SELECT c10_demo.decide_approval(
 current_setting('demo.test.post_a')::bigint,'approve','demo_owner_post_vote_01');
RESET ROLE;
SET ROLE service_role;
DO $t$
DECLARE v bigint;again bigint;
BEGIN
 v:=c10_demo.execute_approved_demo_stock_v1(
   1,current_setting('demo.test.post_a')::bigint,'demo_exec_post_01');
 again:=c10_demo.execute_approved_demo_stock_v1(
   1,current_setting('demo.test.post_a')::bigint,'demo_exec_post_01');
 IF v<>again THEN RAISE EXCEPTION 'FAIL: idempotent posting'; END IF;
 BEGIN
  PERFORM c10_demo.execute_approved_demo_stock_v1(
   1,current_setting('demo.test.post_a')::bigint,'demo_changed_execution_01');
  RAISE EXCEPTION 'FAIL: execution replay key changed';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'demo_execution_replay_conflict' THEN RAISE; END IF;
 END;
END $t$;
RESET ROLE;
DO $t$ BEGIN
 IF (SELECT count(*) FROM c10_demo.stock_movements)<>1
 OR (SELECT sum(delta) FROM c10_demo.stock_movements WHERE location_id=5001)<>5
 OR (SELECT status FROM c10_demo.approval_demo_stock_commands_v1 WHERE id=1)<>'posted'
 OR (SELECT count(*) FROM c10_demo.approval_demo_execution_receipts_v1)<>1
 THEN RAISE EXCEPTION 'FAIL: approval→stock→receipt atomic reconciliation'; END IF;
END $t$;

-- Editing source AFTER approval invalidates exact digest/version. No stock can
-- be posted with stale approved document. A NEW review is required.
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',false);
DO $t$
DECLARE v bigint;approval bigint; nextver bigint;
BEGIN
 v:=c10_demo.prepare_demo_stock_v1(5001,8001,3,'demo_src_prepare_02');
 IF v<>2 THEN RAISE EXCEPTION 'FAIL: second source id fixture'; END IF;
 approval:=c10_demo.submit_typed_approval_v1(
  101,'demo_stock','post_adjustment','demo-adjustment:'||v,1,
  c10_demo.demo_stock_payload_v1(v),'demo_submit_stale_02');
 nextver:=c10_demo.revise_demo_stock_v1(v,1,4,'demo_revise_source_02');
 IF nextver<>2 OR c10_demo.revise_demo_stock_v1(v,1,4,'demo_revise_source_02')<>2
 THEN RAISE EXCEPTION 'FAIL: source optimistic revision or idempotency'; END IF;
 BEGIN
  PERFORM c10_demo.revise_demo_stock_v1(v,1,5,'demo_wrong_version_02');
  RAISE EXCEPTION 'FAIL: source revision stale version passed';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'demo_source_stale_or_final' THEN RAISE; END IF;
 END;
END $t$;
SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
RESET ROLE;
SELECT set_config('demo.test.stale_a',
 (SELECT id::text FROM c10_demo.approval_requests
  WHERE submit_key_v1='demo_submit_stale_02'),false);
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
SELECT c10_demo.decide_approval(
 current_setting('demo.test.stale_a')::bigint,'approve','demo_owner_old_vote_02');
RESET ROLE;
SET ROLE service_role;
DO $t$ BEGIN
 BEGIN
  PERFORM c10_demo.execute_approved_demo_stock_v1(
   2,current_setting('demo.test.stale_a')::bigint,'stale_exec_attempt_02');
  RAISE EXCEPTION 'FAIL: source version changed but approved';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'approval_stale_or_payload_changed' THEN RAISE; END IF;
 END;
END $t$;
RESET ROLE;

-- Publish a FRESH typed approval for v2.
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',false);
SELECT c10_demo.submit_typed_approval_v1(
  101,'demo_stock','post_adjustment','demo-adjustment:2',2,
  c10_demo.demo_stock_payload_v1(2),'demo_resubmit_fresh_02');
RESET ROLE;
SELECT set_config('demo.test.fresh_b',
 (SELECT id::text FROM c10_demo.approval_requests
  WHERE submit_key_v1='demo_resubmit_fresh_02'),false);
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
SELECT c10_demo.decide_approval(
 current_setting('demo.test.fresh_b')::bigint,'approve','demo_owner_fresh_vote_02');
RESET ROLE;
SET ROLE service_role;
SELECT c10_demo.execute_approved_demo_stock_v1(
  2,current_setting('demo.test.fresh_b')::bigint,'demo_execute_fresh_02');
RESET ROLE;

-- The original posted adjustment is reversed ONLY after its own separate
-- typed review with reason and original movement linked, no destructive delete.
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',false);
DO $t$
DECLARE v bigint;r bigint;
BEGIN
 v:=c10_demo.prepare_demo_reversal_v1(
  1,'Duplicate physical count found','demo_reverse_prep_01');
 IF c10_demo.prepare_demo_reversal_v1(
   1,'Duplicate physical count found','demo_reverse_prep_01')<>v
 THEN RAISE EXCEPTION 'FAIL: reversal creation idempotency'; END IF;
 PERFORM c10_demo.prepare_demo_stock_v1(
  5001,8001,2,'demo_unposted_src_03');
 BEGIN
  PERFORM c10_demo.prepare_demo_reversal_v1(
   3,'Unposted cannot reverse','demo_unposted_reverse_03');
  RAISE EXCEPTION 'FAIL: unposted reversal accepted';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'demo_reversal_invalid_source' THEN RAISE; END IF;
 END;
 r:=c10_demo.submit_typed_approval_v1(
  101,'demo_stock','reverse_adjustment','demo-reversal:'||v,1,
  c10_demo.demo_reversal_payload_v1(v),'demo_submit_reverse_01');
 IF r IS NULL THEN RAISE EXCEPTION 'FAIL: reversal typed request'; END IF;
END $t$;
RESET ROLE;
SELECT set_config('demo.test.reverse_a',
 (SELECT id::text FROM c10_demo.approval_requests
  WHERE submit_key_v1='demo_submit_reverse_01'),false);
SET ROLE service_role;
DO $t$ BEGIN
 BEGIN
  PERFORM c10_demo.execute_approved_demo_reversal_v1(
   1,current_setting('demo.test.reverse_a')::bigint,'demo_exec_reverse_01');
  RAISE EXCEPTION 'FAIL: reversal applied without independent checker';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'approval_not_effective' THEN RAISE; END IF;
 END;
END $t$;
RESET ROLE;
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
SELECT c10_demo.decide_approval(
 current_setting('demo.test.reverse_a')::bigint,'approve','demo_owner_reverse_vote_01');
RESET ROLE;
SET ROLE service_role;
DO $t$
DECLARE a bigint;b bigint;
BEGIN
 a:=c10_demo.execute_approved_demo_reversal_v1(
  1,current_setting('demo.test.reverse_a')::bigint,'demo_exec_reverse_01');
 b:=c10_demo.execute_approved_demo_reversal_v1(
  1,current_setting('demo.test.reverse_a')::bigint,'demo_exec_reverse_01');
 IF a<>b THEN RAISE EXCEPTION 'FAIL: reversal idempotency'; END IF;
 BEGIN
  PERFORM c10_demo.execute_approved_demo_reversal_v1(
   1,current_setting('demo.test.reverse_a')::bigint,'demo_exec_reverse_changed');
  RAISE EXCEPTION 'FAIL: reversal replay key changed';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'demo_reversal_execution_replay_conflict' THEN RAISE; END IF;
 END;
END $t$;
RESET ROLE;
DO $t$ BEGIN
 IF (SELECT count(*) FROM c10_demo.stock_movements)<>3
  OR (SELECT sum(delta) FROM c10_demo.stock_movements WHERE location_id=5001)<>4
  OR (SELECT count(*) FROM c10_demo.approval_demo_execution_receipts_v1)<>3
  OR (SELECT status FROM c10_demo.approval_demo_stock_commands_v1 WHERE id=1)<>'reversed'
  OR (SELECT status FROM c10_demo.approval_demo_stock_reversals_v1 WHERE id=1)<>'applied'
 THEN RAISE EXCEPTION 'FAIL: 5+4-5 net4, 3 immutable ledger and receipt events'; END IF;
 IF has_function_privilege('authenticated','c10_demo.execute_approved_demo_stock_v1(bigint,bigint,text)','EXECUTE')
 OR has_function_privilege('anon','c10_demo.execute_approved_demo_reversal_v1(bigint,bigint,text)','EXECUTE')
 OR has_table_privilege('authenticated','c10_demo.approval_demo_stock_commands_v1','UPDATE')
 OR has_table_privilege('authenticated','c10_demo.approval_demo_execution_receipts_v1','INSERT')
 THEN RAISE EXCEPTION 'FAIL: app actor can directly write source/post/reverse'; END IF;
 RAISE NOTICE 'PASS: source version/digest, independent approve, single stock posting, service-only exec, ledger reversal, audit, replay, RLS and net reconciliation';
END $t$;
