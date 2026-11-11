\set ON_ERROR_STOP on
\echo CORE10 A040 delivery + AI gateway: forward-only courier states, COD receivable, redaction, budget, grants, RLS
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
DO $$
DECLARE a bigint;r jsonb;p1 bigint;p2 bigint;ok boolean;ai bigint;c1 bigint;c2 bigint;lo bigint;txt text;
BEGIN
 -- ===== DELIVERY =====
 a:=c10_demo.integration_connect_v1(101,'pathao','ib_101_pathao_v1','{}');
 IF c10_demo.delivery_create_parcel_v1(a,'d0','ORD-0',100)->>'reason'<>'port_off' THEN RAISE EXCEPTION 'off courier created a parcel'; END IF;
 PERFORM c10_demo.integration_record_test_v1(a,true,'ok'); PERFORM c10_demo.integration_set_mode_v1(a,'live');
 ok:=false; BEGIN PERFORM c10_demo.delivery_create_parcel_v1(a,'bad','R',-1); ok:=true;
 EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'delivery_invalid_amount' THEN RAISE; END IF; END;
 IF ok THEN RAISE EXCEPTION 'negative COD accepted'; END IF;
 p1:=(c10_demo.delivery_create_parcel_v1(a,'d1','ORD-1',1200)->>'id')::bigint;
 IF c10_demo.delivery_create_parcel_v1(a,'d1','ORD-1',1200)->>'status'<>'duplicate' THEN RAISE EXCEPTION 'parcel duplicated'; END IF;
 IF c10_demo.delivery_apply_event_v1(p1,'e1','pickup_done','ok',NULL,'CN-1')<>'applied' THEN RAISE EXCEPTION 'pickup'; END IF;
 IF c10_demo.delivery_apply_event_v1(p1,'e1','pickup_done','ok')<>'duplicate' THEN RAISE EXCEPTION 'duplicate event'; END IF;
 IF c10_demo.delivery_apply_event_v1(p1,'e2','in_transit','ok')<>'applied' THEN RAISE EXCEPTION 'transit'; END IF;
 IF c10_demo.delivery_apply_event_v1(p1,'e3','pickup_done','ok')<>'ignored_backwards' THEN RAISE EXCEPTION 'backwards state allowed'; END IF;
 IF c10_demo.delivery_apply_event_v1(p1,'e4','delivered','bad',1200)<>'ignored_signature' THEN RAISE EXCEPTION 'bad signature delivered'; END IF;
 IF c10_demo.delivery_apply_event_v1(p1,'e5','weird_status','ok')<>'unmapped' THEN RAISE EXCEPTION 'unmapped status applied'; END IF;
 IF (SELECT state||'/'||cod_collected FROM c10_demo.delivery_parcel_v1 WHERE id=p1)<>'in_transit/0.00' THEN RAISE EXCEPTION 'state moved w/o verified event'; END IF;
 IF c10_demo.delivery_apply_event_v1(p1,'e6','delivered','ok',99999)<>'applied' THEN RAISE EXCEPTION 'delivered'; END IF;
 IF (SELECT cod_collected FROM c10_demo.delivery_parcel_v1 WHERE id=p1)<>1200 THEN RAISE EXCEPTION 'COD collected not capped at amount'; END IF;
 IF c10_demo.delivery_apply_event_v1(p1,'e7','returned','ok')<>'ignored_backwards' THEN RAISE EXCEPTION 'delivered parcel returned'; END IF;
 -- COD receivable and remittance
 IF (SELECT courier_owes FROM c10_demo.courier_cod_receivable_v1 WHERE provider_code='pathao')<>1200 THEN RAISE EXCEPTION 'receivable wrong'; END IF;
 IF c10_demo.delivery_record_remittance_v1(p1,700)<>500 THEN RAISE EXCEPTION 'remaining wrong'; END IF;
 ok:=false; BEGIN PERFORM c10_demo.delivery_record_remittance_v1(p1,500.01); ok:=true;
 EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'delivery_remittance_exceeds_collected' THEN RAISE; END IF; END;
 IF ok THEN RAISE EXCEPTION 'over-remittance accepted'; END IF;
 IF (SELECT courier_owes FROM c10_demo.courier_cod_receivable_v1 WHERE provider_code='pathao')<>500 THEN RAISE EXCEPTION 'receivable after remit'; END IF;
 -- returned parcel collects nothing
 p2:=(c10_demo.delivery_create_parcel_v1(a,'d2','ORD-2',800)->>'id')::bigint;
 PERFORM c10_demo.delivery_apply_event_v1(p2,'f1','returned','ok');
 IF (SELECT state||'/'||cod_collected FROM c10_demo.delivery_parcel_v1 WHERE id=p2)<>'returned/0.00' THEN RAISE EXCEPTION 'returned parcel collected COD'; END IF;
 -- a messaging account is not a delivery port
 ok:=false; BEGIN PERFORM c10_demo.delivery_create_parcel_v1(c10_demo.integration_connect_v1(101,'sms','ib_101_sms_v1','{}'),'x','R',1); ok:=true;
 EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'delivery_not_delivery_port' THEN RAISE; END IF; END;
 IF ok THEN RAISE EXCEPTION 'SMS port created a parcel'; END IF;

 -- ===== AI GATEWAY =====
 txt:='Customer Rahim 01712345678 rahim@example.com acct 123456789012 wants 5kg sweets';
 IF c10_demo.ai_redact_v1(txt) ~ '01712345678|rahim@example|123456789012' THEN RAISE EXCEPTION 'redaction leaked: %',c10_demo.ai_redact_v1(txt); END IF;
 IF c10_demo.ai_redact_v1(txt) NOT LIKE '%[PHONE]%' OR c10_demo.ai_redact_v1(txt) NOT LIKE '%[EMAIL]%' OR c10_demo.ai_redact_v1(txt) NOT LIKE '%[NUMBER]%'
 THEN RAISE EXCEPTION 'redaction markers missing'; END IF;
 IF c10_demo.ai_redact_v1('+8801712345678 and 8801712345678') LIKE '%1712345678%' THEN RAISE EXCEPTION 'country-code phone leaked'; END IF;
 ai:=c10_demo.integration_connect_v1(101,'ai_anthropic','ib_101_ai_v1','{}');
 -- port off
 IF c10_demo.ai_request_v1(ai,'sales_helper','a0',txt)->>'state'<>'blocked_port_off' THEN RAISE EXCEPTION 'off AI port allowed'; END IF;
 PERFORM c10_demo.integration_record_test_v1(ai,true,'ok'); PERFORM c10_demo.integration_set_mode_v1(ai,'live');
 IF c10_demo.ai_request_v1(ai,'sales_helper','a1',txt)->>'state'<>'blocked_no_grant' THEN RAISE EXCEPTION 'ungranted agent allowed'; END IF;
 PERFORM c10_demo.ai_set_grant_v1(101,'sales_helper',true,false);
 IF c10_demo.ai_request_v1(ai,'sales_helper','a2',txt)->>'state'<>'blocked_no_sharing' THEN RAISE EXCEPTION 'data sent without data_sharing'; END IF;
 PERFORM c10_demo.ai_set_grant_v1(101,'sales_helper',true,true);
 IF c10_demo.ai_request_v1(ai,'sales_helper','a3',txt)->>'state'<>'blocked_budget' THEN RAISE EXCEPTION 'no budget set but allowed'; END IF;
 PERFORM c10_demo.ai_set_budget_v1(ai,1000,5.00);
 r:=c10_demo.ai_request_v1(ai,'sales_helper','a4',txt);
 IF r->>'state'<>'allowed' THEN RAISE EXCEPTION 'valid AI call blocked: %',r; END IF;
 IF r->>'input' ~ '01712345678|rahim@example|123456789012' THEN RAISE EXCEPTION 'unredacted text returned for sending'; END IF;
 IF (SELECT redacted_input FROM c10_demo.ai_call_v1 WHERE id=(r->>'id')::bigint) ~ '01712345678|rahim@example' THEN RAISE EXCEPTION 'unredacted text stored'; END IF;
 IF c10_demo.ai_request_v1(ai,'sales_helper','a4',txt)->>'status'<>'duplicate' THEN RAISE EXCEPTION 'AI call duplicated'; END IF;
 c1:=(r->>'id')::bigint;
 IF c10_demo.ai_report_v1(c1,true,600,300,1.50)<>'done' THEN RAISE EXCEPTION 'report'; END IF;
 IF c10_demo.ai_report_v1(c1,false,0,0,0)<>'done' THEN RAISE EXCEPTION 'final AI state moved'; END IF;
 -- 900/1000 tokens used: still allowed; after next call exhausts it, blocked
 r:=c10_demo.ai_request_v1(ai,'sales_helper','a5','hello'); c2:=(r->>'id')::bigint;
 IF r->>'state'<>'allowed' THEN RAISE EXCEPTION 'second call within budget blocked'; END IF;
 PERFORM c10_demo.ai_report_v1(c2,true,150,100,0.50);
 IF c10_demo.ai_request_v1(ai,'sales_helper','a6','hello')->>'state'<>'blocked_budget' THEN RAISE EXCEPTION 'token budget not enforced'; END IF;
 -- money cap
 PERFORM c10_demo.ai_set_budget_v1(ai,1000000,2.00);
 IF c10_demo.ai_request_v1(ai,'sales_helper','a7','hello')->>'state'<>'blocked_budget' THEN RAISE EXCEPTION 'money budget not enforced'; END IF;
 -- local rules: no network, no grant needed, never sends anything out
 lo:=c10_demo.integration_connect_v1(101,'ai_local_rules',NULL,'{}');
 r:=c10_demo.ai_request_v1(lo,'sales_helper','l1',txt);
 IF r->>'state'<>'fallback_local' OR r->>'input' IS NOT NULL THEN RAISE EXCEPTION 'local rules path wrong: %',r; END IF;
 -- kill switch stops the AI port
 PERFORM c10_demo.integration_kill_switch_v1(101);
 IF c10_demo.ai_request_v1(ai,'sales_helper','a8','hello')->>'state'<>'blocked_port_off' THEN RAISE EXCEPTION 'AI allowed after kill switch'; END IF;
 IF c10_demo.delivery_create_parcel_v1(a,'d9','ORD-9',1)->>'reason'<>'port_off' THEN RAISE EXCEPTION 'parcel after kill switch'; END IF;
END $$;
COMMIT;

BEGIN;
DO $$
DECLARE uid text;fn text;ok boolean;
BEGIN
 FOREACH uid IN ARRAY ARRAY['33333333-3333-4333-8333-333333333333','55555555-5555-4555-8555-555555555555','44444444-4444-4444-8444-444444444444',
   '66666666-6666-4666-8666-666666666666','77777777-7777-4777-8777-777777777777','99999999-9999-4999-8999-999999999999'] LOOP
  PERFORM set_config('request.jwt.claim.sub',uid,true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  FOREACH fn IN ARRAY ARRAY['SELECT c10_demo.delivery_create_parcel_v1(1,''z'',''r'',0)','SELECT c10_demo.delivery_apply_event_v1(1,''z'',''delivered'',''ok'')',
   'SELECT c10_demo.delivery_record_remittance_v1(1,1)','SELECT c10_demo.ai_set_budget_v1(1,1,1)','SELECT c10_demo.ai_set_grant_v1(101,''x'',true,true)',
   'SELECT c10_demo.ai_request_v1(1,''x'',''z'',''t'')','SELECT c10_demo.ai_report_v1(1,true)'] LOOP
   ok:=false; BEGIN EXECUTE fn; ok:=true; EXCEPTION WHEN OTHERS THEN IF SQLERRM NOT IN('delivery_denied','ai_denied') THEN RAISE; END IF; END;
   IF ok THEN RAISE EXCEPTION 'uid % ran %',uid,fn; END IF;
  END LOOP;
  IF (SELECT count(*) FROM c10_demo.delivery_parcel_v1)<>0 OR (SELECT count(*) FROM c10_demo.delivery_event_v1)<>0 OR (SELECT count(*) FROM c10_demo.ai_call_v1)<>0
     OR (SELECT count(*) FROM c10_demo.ai_budget_v1)<>0 OR (SELECT count(*) FROM c10_demo.ai_agent_grant_v1)<>0 OR (SELECT count(*) FROM c10_demo.courier_cod_receivable_v1)<>0
  THEN RAISE EXCEPTION 'uid % can read delivery/ai data',uid; END IF;
  BEGIN UPDATE c10_demo.delivery_parcel_v1 SET cod_collected=1; RAISE EXCEPTION 'direct update %',uid; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN UPDATE c10_demo.ai_budget_v1 SET monthly_token_cap=999999; RAISE EXCEPTION 'direct budget update %',uid; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  EXECUTE 'RESET ROLE';
 END LOOP;
 EXECUTE 'SET LOCAL ROLE anon';
 BEGIN PERFORM c10_demo.ai_request_v1(1,'x','z','t'); RAISE EXCEPTION 'anon called AI'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 EXECUTE 'RESET ROLE';
 BEGIN UPDATE c10_demo.delivery_event_v1 SET outcome='applied'; RAISE EXCEPTION 'delivery log updated'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN DELETE FROM c10_demo.delivery_event_v1; RAISE EXCEPTION 'delivery log deleted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
ROLLBACK;
\echo PASS: A040 delivery+AI: forward-only courier states, verified events, COD receivable/remittance, redaction, grants, budget caps, kill switch, owner-only RLS
