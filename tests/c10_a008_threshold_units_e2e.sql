-- GOV002 enforce versioned currency/quantity thresholds with exact units.
-- Fresh disposable PostgreSQL17. Parent typed+inbox+routing suites already pass.
\set ON_ERROR_STOP on
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
DO $t$
DECLARE v_money bigint;v_qty bigint;v_late bigint;
BEGIN
 v_money:=c10_demo.publish_approval_policy_v1(
  101,'demo_finance','expense_review',60,'thresh_money_policy_01');
 v_qty:=c10_demo.publish_approval_policy_v1(
  101,'demo_inventory','quantity_review',60,'thresh_qty_policy_01');
 v_late:=c10_demo.publish_approval_policy_v1(
  101,'demo_inventory','late_limit_review',60,'thresh_late_policy_01');
 IF c10_demo.configure_approval_threshold_v1(
   v_money,'currency','BDT',100.00,'thresh_money_set_01')<>v_money
   OR c10_demo.configure_approval_threshold_v1(
   v_money,'currency','BDT',100.00,'thresh_money_set_01')<>v_money
 THEN RAISE EXCEPTION 'FAIL: threshold policy replay'; END IF;
 IF c10_demo.configure_approval_threshold_v1(
   v_qty,'quantity','KG',2.125,'thresh_qty_set_01')<>v_qty
 THEN RAISE EXCEPTION 'FAIL: quantity threshold'; END IF;
 BEGIN
  PERFORM c10_demo.configure_approval_threshold_v1(
   v_money,'currency','BDT',101.00,'thresh_money_set_01');
  RAISE EXCEPTION 'FAIL: config idempotency key changed amount';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'approval_threshold_replay_conflict' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM c10_demo.configure_approval_threshold_v1(
   v_qty,'quantity','PCS',2.5,'thresh_bad_fraction_01');
  RAISE EXCEPTION 'FAIL: fractional pieces';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'invalid_approval_threshold' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM c10_demo.configure_approval_threshold_v1(
   v_money,'currency','USD',100,'thresh_wrong_currency_01');
  RAISE EXCEPTION 'FAIL: unsupported FX unit';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'invalid_approval_threshold' THEN RAISE; END IF;
 END;
END $t$;

SELECT set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',false);
DO $t$
DECLARE v_money bigint;v_qty bigint; v_late bigint; r bigint;
BEGIN
 -- Manager sees no raw Owner policy rows. Assessment is instead routed
 -- through business/domain/action inside one auth-checked DEFINER RPC.
 IF c10_demo.assess_current_approval_threshold_v1(
  101,'demo_finance','expense_review','{"amount":100,"unit":"BDT"}'::jsonb)<>'REVIEW_REQUIRED'
 OR c10_demo.assess_current_approval_threshold_v1(
  101,'demo_finance','expense_review','{"amount":99.99,"unit":"BDT"}'::jsonb)<>'BELOW_THRESHOLD'
 OR c10_demo.assess_current_approval_threshold_v1(
  101,'demo_inventory','late_limit_review','{}'::jsonb)<>'UNCONFIGURED'
 THEN RAISE EXCEPTION 'FAIL: policy assessment mismatch'; END IF;
 r:=c10_demo.submit_typed_approval_v1(
  101,'demo_finance','expense_review','invoice-101',1,
  '{"amount":100.00,"unit":"BDT"}'::jsonb,'threshold_request_01');
 IF r IS NULL THEN RAISE EXCEPTION 'FAIL: allowed threshold request'; END IF;
 SELECT policy_id_v1 INTO v_money FROM c10_demo.approval_requests WHERE id=r;
 IF v_money IS NULL THEN RAISE EXCEPTION 'FAIL: request policy id not visible to own requester'; END IF;
 BEGIN
  PERFORM c10_demo.submit_typed_approval_v1(
   101,'demo_finance','expense_review','invoice-102',1,
   '{"amount":99.99,"unit":"BDT"}'::jsonb,'threshold_low_01');
  RAISE EXCEPTION 'FAIL: below threshold accepted';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'approval_threshold_not_met' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM c10_demo.submit_typed_approval_v1(
   101,'demo_finance','expense_review','invoice-103',1,
   '{"amount":100,"unit":"USD"}'::jsonb,'threshold_wrong_fx_01');
  RAISE EXCEPTION 'FAIL: USD incorrectly treated as BDT';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'approval_threshold_unit_or_amount_invalid' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM c10_demo.submit_typed_approval_v1(
   101,'demo_finance','expense_review','invoice-104',1,
   '{"amount":"100","unit":"BDT"}'::jsonb,'threshold_string_amount_01');
  RAISE EXCEPTION 'FAIL: string money accepted';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'approval_threshold_unit_or_amount_invalid' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM c10_demo.submit_typed_approval_v1(
   101,'demo_finance','expense_review','invoice-105',1,
   '{"amount":100.001,"unit":"BDT"}'::jsonb,'threshold_precision_01');
  RAISE EXCEPTION 'FAIL: fractional paisa accepted';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'approval_threshold_precision_invalid' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM c10_demo.submit_typed_approval_v1(
   101,'demo_inventory','quantity_review','sku-106',1,
   '{"amount":2.124,"unit":"KG"}'::jsonb,'threshold_qty_low_01');
  RAISE EXCEPTION 'FAIL: 2.124kg approved against 2.125kg';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'approval_threshold_not_met' THEN RAISE; END IF;
 END;
 IF c10_demo.submit_typed_approval_v1(
  101,'demo_inventory','quantity_review','sku-107',1,
  '{"amount":2.125,"unit":"KG"}'::jsonb,'threshold_qty_valid_01') IS NULL
 THEN RAISE EXCEPTION 'FAIL: KG boundary rejected'; END IF;
 -- No limit has been published yet: a valid typed submission succeeds.
 IF c10_demo.submit_typed_approval_v1(
  101,'demo_inventory','late_limit_review','late-case-108',1,
  '{}'::jsonb,'threshold_late_req_01') IS NULL
 THEN RAISE EXCEPTION 'FAIL: unconstrained policy'; END IF;
 BEGIN
  PERFORM c10_demo.configure_approval_threshold_v1(
   v_money,'currency','BDT',100.00,'unauthorized_manager_01');
  RAISE EXCEPTION 'FAIL: manager may set threshold';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'threshold_not_authorized' THEN RAISE; END IF;
 END;
END $t$;

SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
DO $t$
DECLARE v_late bigint;
BEGIN
 SELECT id INTO v_late FROM c10_demo.approval_policy_versions_v1
  WHERE business_id=101 AND domain='demo_inventory' AND action_code='late_limit_review';
 BEGIN
  PERFORM c10_demo.configure_approval_threshold_v1(
   v_late,'quantity','PCS',10,'late_limit_config_01');
  RAISE EXCEPTION 'FAIL: policy retrofitted after pending request';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'approval_threshold_policy_in_use' THEN RAISE; END IF;
 END;
END $t$;
SELECT set_config('request.jwt.claim.sub','77777777-7777-4777-8777-777777777777',false);
DO $t$
DECLARE v_money bigint;
BEGIN
 -- Explicitly fail closed without leaking policy version IDs.
 v_money:=4; -- inert synthetic fixture: three parent policy versions already exist
 BEGIN
  PERFORM c10_demo.assess_current_approval_threshold_v1(
    101,'demo_finance','expense_review','{"amount":100,"unit":"BDT"}'::jsonb);
  RAISE EXCEPTION 'FAIL: foreign tenant assessed policy';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'approval_assessment_denied' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM c10_demo.configure_approval_threshold_v1(
   v_money,'currency','BDT',100.00,'foreign_attempt_01');
  RAISE EXCEPTION 'FAIL: foreign tenant set policy';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'threshold_not_authorized' THEN RAISE; END IF;
 END;
END $t$;
RESET ROLE;
DO $t$ BEGIN
 IF (SELECT count(*) FROM c10_demo.approval_thresholds_v1)<>2
 OR has_table_privilege('authenticated','c10_demo.approval_thresholds_v1','INSERT')
 OR has_function_privilege('authenticated','c10_demo.assert_approval_threshold_v1(bigint,jsonb)','EXECUTE')
 OR has_function_privilege('anon','c10_demo.assess_approval_threshold_v1(bigint,jsonb)','EXECUTE')
 OR (SELECT count(*) FROM c10_demo.stock_movements)<>0
 THEN RAISE EXCEPTION 'FAIL: threshold ledger, ACL or zero posting'; END IF;
 RAISE NOTICE 'PASS: amount units/precision, BDT/KG thresholds, immutable version pin, replay, foreign/manager denials, zero posting';
END $t$;
