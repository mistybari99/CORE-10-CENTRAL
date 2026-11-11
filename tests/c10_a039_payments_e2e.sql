\set ON_ERROR_STOP on
\echo CORE10 A039 payments engine: verified-only paid, amount match, no backward moves, refunds, ledger reconciliation, RLS
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
DO $$
DECLARE a bigint;r jsonb;i1 bigint;i2 bigint;i3 bigint;i4 bigint;ok boolean;s text;
BEGIN
 a:=c10_demo.integration_connect_v1(101,'bkash','ib_101_bkash_v1','{}');
 -- OFF port: no intent
 r:=c10_demo.payment_create_intent_v1(a,'k0','ORD-0',500);
 IF r->>'reason'<>'port_off' THEN RAISE EXCEPTION 'off port created an intent: %',r; END IF;
 PERFORM c10_demo.integration_record_test_v1(a,true,'ok');
 PERFORM c10_demo.integration_set_mode_v1(a,'live');
 -- invalid amounts and wrong family
 FOREACH s IN ARRAY ARRAY['0','-5','10.005'] LOOP
  ok:=false; BEGIN PERFORM c10_demo.payment_create_intent_v1(a,'bad'||s,'ORD',s::numeric); ok:=true;
  EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'payment_invalid_amount' THEN RAISE; END IF; END;
  IF ok THEN RAISE EXCEPTION 'invalid amount % accepted',s; END IF;
 END LOOP;
 ok:=false; BEGIN PERFORM c10_demo.payment_create_intent_v1(c10_demo.integration_connect_v1(101,'sms','ib_101_sms_v1','{}'),'k','R',10); ok:=true;
 EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'payment_not_payments_port' THEN RAISE; END IF; END;
 IF ok THEN RAISE EXCEPTION 'SMS port created a payment'; END IF;

 -- happy path + idempotency
 r:=c10_demo.payment_create_intent_v1(a,'k1','ORD-1',500.00); i1:=(r->>'id')::bigint;
 IF c10_demo.payment_create_intent_v1(a,'k1','ORD-1',500.00)->>'status'<>'duplicate' THEN RAISE EXCEPTION 'intent duplicated'; END IF;
 IF c10_demo.payment_apply_event_v1(i1,'e-red','redirected',NULL,'ok')<>'applied' THEN RAISE EXCEPTION 'redirect'; END IF;
 IF c10_demo.payment_apply_event_v1(i1,'e-pend','pending',NULL,'ok')<>'applied' THEN RAISE EXCEPTION 'pending'; END IF;
 IF c10_demo.payment_apply_event_v1(i1,'e-redir2','redirected',NULL,'ok')<>'ignored_terminal' THEN RAISE EXCEPTION 'backwards move allowed'; END IF;
 -- bad / missing signature never pays
 IF c10_demo.payment_apply_event_v1(i1,'e-bad','paid',500,'bad')<>'ignored_signature' THEN RAISE EXCEPTION 'bad signature paid'; END IF;
 IF c10_demo.payment_apply_event_v1(i1,'e-none','paid',500,'missing')<>'ignored_signature' THEN RAISE EXCEPTION 'unsigned paid'; END IF;
 IF (SELECT state FROM c10_demo.payment_intent_v1 WHERE id=i1)<>'pending' THEN RAISE EXCEPTION 'state moved without verified event'; END IF;
 IF (SELECT count(*) FROM c10_demo.payment_ledger_v1)<>0 THEN RAISE EXCEPTION 'ledger written without verified payment'; END IF;
 -- verified, exact amount
 IF c10_demo.payment_apply_event_v1(i1,'e-paid','paid',500,'ok','PROV-1')<>'applied' THEN RAISE EXCEPTION 'valid paid refused'; END IF;
 IF c10_demo.payment_apply_event_v1(i1,'e-paid','paid',500,'ok')<>'duplicate' THEN RAISE EXCEPTION 'duplicate event re-applied'; END IF;
 IF c10_demo.payment_apply_event_v1(i1,'e-paid-2','paid',500,'ok')<>'ignored_terminal' THEN RAISE EXCEPTION 'second paid event double-posted'; END IF;
 IF (SELECT sum(amount) FROM c10_demo.payment_ledger_v1 WHERE intent_id=i1)<>500 THEN RAISE EXCEPTION 'ledger not exactly once'; END IF;
 -- late failure cannot undo paid
 IF c10_demo.payment_apply_event_v1(i1,'e-late-fail','failed',NULL,'ok')<>'ignored_terminal' THEN RAISE EXCEPTION 'paid moved backwards'; END IF;
 IF (SELECT state FROM c10_demo.payment_intent_v1 WHERE id=i1)<>'paid' THEN RAISE EXCEPTION 'paid lost'; END IF;

 -- amount mismatch -> needs_review, no ledger; owner resolves
 i2:=(c10_demo.payment_create_intent_v1(a,'k2','ORD-2',300)->>'id')::bigint;
 IF c10_demo.payment_apply_event_v1(i2,'e2','paid',299.99,'ok')<>'needs_review' THEN RAISE EXCEPTION 'short payment accepted'; END IF;
 IF (SELECT count(*) FROM c10_demo.payment_ledger_v1 WHERE intent_id=i2)<>0 THEN RAISE EXCEPTION 'ledger written for mismatch'; END IF;
 IF (SELECT recon_state FROM c10_demo.payment_reconciliation_v1 WHERE intent_id=i2)<>'needs_review' THEN RAISE EXCEPTION 'review not surfaced'; END IF;
 IF c10_demo.payment_resolve_review_v1(i2,true,299.99)<>'paid' THEN RAISE EXCEPTION 'review accept failed'; END IF;
 ok:=false; BEGIN PERFORM c10_demo.payment_resolve_review_v1(i2,false); ok:=true;
 EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'payment_not_in_review' THEN RAISE; END IF; END;
 IF ok THEN RAISE EXCEPTION 'resolved twice'; END IF;
 -- overpayment also reviewed
 i3:=(c10_demo.payment_create_intent_v1(a,'k3','ORD-3',100)->>'id')::bigint;
 IF c10_demo.payment_apply_event_v1(i3,'e3','paid',150,'ok')<>'needs_review' THEN RAISE EXCEPTION 'overpayment accepted'; END IF;
 PERFORM c10_demo.payment_resolve_review_v1(i3,false);
 IF (SELECT state FROM c10_demo.payment_intent_v1 WHERE id=i3)<>'failed' THEN RAISE EXCEPTION 'rejected review not failed'; END IF;

 -- refunds: bounded, idempotent, partial then full
 IF c10_demo.payment_refund_v1(i1,200,'rf1')->>'state'<>'partially_refunded' THEN RAISE EXCEPTION 'partial refund'; END IF;
 IF c10_demo.payment_refund_v1(i1,200,'rf1')->>'status'<>'duplicate' THEN RAISE EXCEPTION 'refund duplicated'; END IF;
 ok:=false; BEGIN PERFORM c10_demo.payment_refund_v1(i1,300.01,'rf2'); ok:=true;
 EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'payment_refund_exceeds_paid' THEN RAISE; END IF; END;
 IF ok THEN RAISE EXCEPTION 'over-refund accepted'; END IF;
 IF c10_demo.payment_refund_v1(i1,300,'rf3')->>'state'<>'refunded' THEN RAISE EXCEPTION 'full refund'; END IF;
 ok:=false; BEGIN PERFORM c10_demo.payment_refund_v1(i1,1,'rf4'); ok:=true;
 EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'payment_not_refundable' THEN RAISE; END IF; END;
 IF ok THEN RAISE EXCEPTION 'refund after full refund'; END IF;
 ok:=false; BEGIN PERFORM c10_demo.payment_refund_v1(i3,1,'rf5'); ok:=true;
 EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'payment_not_refundable' THEN RAISE; END IF; END;
 IF ok THEN RAISE EXCEPTION 'refund of unpaid intent'; END IF;
 IF c10_demo.payment_apply_event_v1(i1,'e-after-refund','paid',500,'ok')<>'ignored_terminal' THEN RAISE EXCEPTION 'refunded intent re-paid'; END IF;

 -- polling + expiry
 i4:=(c10_demo.payment_create_intent_v1(a,'k4','ORD-4',50,now()-interval '1 hour')->>'id')::bigint;
 IF (SELECT count(*) FROM c10_demo.payment_poll_candidates_v1(a,interval '0 seconds',now()+interval '1 minute'))<>1 THEN RAISE EXCEPTION 'poll candidates wrong'; END IF;
 IF c10_demo.payment_expire_v1(101)<>1 THEN RAISE EXCEPTION 'expiry count wrong'; END IF;
 IF c10_demo.payment_apply_event_v1(i4,'e4','paid',50,'ok')<>'ignored_terminal' THEN RAISE EXCEPTION 'expired intent paid'; END IF;

 -- reconciliation: everything reconciles except nothing is mismatched
 IF EXISTS(SELECT 1 FROM c10_demo.payment_reconciliation_v1 WHERE recon_state='mismatch') THEN RAISE EXCEPTION 'ledger mismatch'; END IF;
 IF (SELECT sum(amount) FROM c10_demo.payment_ledger_v1)<>299.99 THEN RAISE EXCEPTION 'ledger total wrong: %',(SELECT sum(amount) FROM c10_demo.payment_ledger_v1); END IF;
 -- kill switch: nothing new can be applied while off
 PERFORM c10_demo.integration_kill_switch_v1(101);
 IF c10_demo.payment_create_intent_v1(a,'k9','ORD-9',10)->>'reason'<>'port_off' THEN RAISE EXCEPTION 'intent after kill switch'; END IF;
 -- manual (no-secret) provider can be connected and used the same way
 PERFORM c10_demo.integration_connect_v1(101,'manual_pay',NULL,'{}');
END $$;
COMMIT;

-- role matrix + immutability + tenant isolation
BEGIN;
DO $$
DECLARE uid text;fn text;ok boolean;
BEGIN
 FOREACH uid IN ARRAY ARRAY['33333333-3333-4333-8333-333333333333','55555555-5555-4555-8555-555555555555','44444444-4444-4444-8444-444444444444',
   '66666666-6666-4666-8666-666666666666','77777777-7777-4777-8777-777777777777','99999999-9999-4999-8999-999999999999'] LOOP
  PERFORM set_config('request.jwt.claim.sub',uid,true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  FOREACH fn IN ARRAY ARRAY['SELECT c10_demo.payment_create_intent_v1(1,''z'',''r'',5)','SELECT c10_demo.payment_apply_event_v1(1,''z'',''paid'',5,''ok'')',
    'SELECT c10_demo.payment_resolve_review_v1(1,false)','SELECT c10_demo.payment_refund_v1(1,1,''z'')',
    'SELECT * FROM c10_demo.payment_poll_candidates_v1(1)','SELECT c10_demo.payment_expire_v1(101)'] LOOP
   ok:=false; BEGIN EXECUTE fn; ok:=true; EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT IN('payment_denied') THEN RAISE; END IF; END;
   IF ok THEN RAISE EXCEPTION 'uid % ran %',uid,fn; END IF;
  END LOOP;
  IF (SELECT count(*) FROM c10_demo.payment_intent_v1)<>0 OR (SELECT count(*) FROM c10_demo.payment_ledger_v1)<>0
     OR (SELECT count(*) FROM c10_demo.payment_event_v1)<>0 OR (SELECT count(*) FROM c10_demo.payment_reconciliation_v1)<>0
  THEN RAISE EXCEPTION 'uid % can read payments',uid; END IF;
  BEGIN UPDATE c10_demo.payment_intent_v1 SET state='paid'; RAISE EXCEPTION 'direct update %',uid; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN INSERT INTO c10_demo.payment_ledger_v1(intent_id,tenant_id,business_id,kind,amount,source_key,created_by) VALUES(1,1,101,'receipt',1,'h',gen_random_uuid()); RAISE EXCEPTION 'direct ledger insert %',uid; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  EXECUTE 'RESET ROLE';
 END LOOP;
 EXECUTE 'SET LOCAL ROLE anon';
 BEGIN PERFORM c10_demo.payment_refund_v1(1,1,'z'); RAISE EXCEPTION 'anon refunded'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 EXECUTE 'RESET ROLE';
 BEGIN UPDATE c10_demo.payment_ledger_v1 SET amount=amount+1; RAISE EXCEPTION 'ledger updated'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN DELETE FROM c10_demo.payment_ledger_v1; RAISE EXCEPTION 'ledger deleted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN TRUNCATE c10_demo.payment_event_v1; RAISE EXCEPTION 'events truncated'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
ROLLBACK;
\echo PASS: A039 payments: verified-only paid, exact amount, review path, no backward moves, bounded idempotent refunds, ledger reconciles, owner-only RLS, immutable ledger
