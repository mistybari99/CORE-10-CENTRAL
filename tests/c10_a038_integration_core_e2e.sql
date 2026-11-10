\set ON_ERROR_STOP on
\echo CORE10 A038 Integration Ports core: off-by-default, consent/quiet/cap gates, idempotency, retry lease, webhooks, RLS (disposable DB)
-- Identities (synthetic): owner 1111 (tenant 1 owner), business owner 2222 (business 101), manager 3333,
-- investor 5555, site staff 4444, revoked 6666, tenant-2 owner 7777, platform operator 9999.

-- ============ 0) CATALOG SANITY ============
DO $$
DECLARE n int;
BEGIN
 SELECT count(*) INTO n FROM c10_demo.integration_provider_v1;
 IF n<>20 THEN RAISE EXCEPTION 'expected 20 providers, found %',n; END IF;
 IF (SELECT count(*) FROM c10_demo.integration_account_v1)<>0 THEN RAISE EXCEPTION 'accounts must not exist before the owner connects'; END IF;
 -- every external family from the Owner requirement exists as a port
 IF (SELECT count(DISTINCT family) FROM c10_demo.integration_provider_v1)<>5 THEN RAISE EXCEPTION 'missing family'; END IF;
END $$;

-- ============ 1) CONNECT => OFF; MODE LADDER; PUBLIC_CONFIG CANNOT HOLD SECRETS ============
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
DO $$
DECLARE a bigint;r text;ok boolean;
BEGIN
 a:=c10_demo.integration_connect_v1(101,'whatsapp','ib_101_whatsapp_v1','{"phone_number_id":"demo"}');
 IF (SELECT mode||'/'||status FROM c10_demo.integration_account_v1 WHERE id=a)<>'off/connected'
 THEN RAISE EXCEPTION 'connect must leave the port OFF'; END IF;
 -- live without a passed test is rejected by the database
 ok:=false; BEGIN PERFORM c10_demo.integration_set_mode_v1(a,'live'); ok:=true;
 EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'integration_live_needs_recent_test' THEN RAISE; END IF; END;
 IF ok THEN RAISE EXCEPTION 'live without test was allowed'; END IF;
 IF c10_demo.integration_set_mode_v1(a,'dry_run')<>'dry_run' THEN RAISE EXCEPTION 'dry_run refused'; END IF;
 -- a failed test forces the port back OFF
 IF c10_demo.integration_record_test_v1(a,false,'auth failed')<>'failed' THEN RAISE EXCEPTION 'bad test result'; END IF;
 IF (SELECT mode||'/'||status FROM c10_demo.integration_account_v1 WHERE id=a)<>'off/test_failed'
 THEN RAISE EXCEPTION 'failed test must switch port off'; END IF;
 ok:=false; BEGIN PERFORM c10_demo.integration_set_mode_v1(a,'dry_run'); ok:=true;
 EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'integration_not_connected' THEN RAISE; END IF; END;
 IF ok THEN RAISE EXCEPTION 'port turned on while test_failed'; END IF;
 PERFORM c10_demo.integration_record_test_v1(a,true,'ok');
 IF c10_demo.integration_set_mode_v1(a,'live')<>'live' THEN RAISE EXCEPTION 'live refused after passed test'; END IF;
 PERFORM c10_demo.integration_set_mode_v1(a,'off');
 -- secrets in public_config are rejected
 ok:=false; BEGIN PERFORM c10_demo.integration_connect_v1(101,'sms','ib_101_sms_v1','{"api_key":"abc"}'); ok:=true;
 EXCEPTION WHEN check_violation THEN NULL; END;
 IF ok THEN RAISE EXCEPTION 'secret-looking public_config accepted'; END IF;
 ok:=false; BEGIN PERFORM c10_demo.integration_connect_v1(101,'sms','ib_101_sms_v1','{"nested":{"access_token":"x"}}'); ok:=true;
 EXCEPTION WHEN check_violation THEN NULL; END;
 IF ok THEN RAISE EXCEPTION 'nested secret-looking public_config accepted'; END IF;
 -- secret_ref must be a plain name, never a value-looking string
 ok:=false; BEGIN PERFORM c10_demo.integration_connect_v1(101,'sms','sk-live-ABC.def/123','{}'); ok:=true;
 EXCEPTION WHEN check_violation THEN NULL; END;
 IF ok THEN RAISE EXCEPTION 'value-looking secret_ref accepted'; END IF;
 -- providers that need a secret refuse to connect without a reference
 ok:=false; BEGIN PERFORM c10_demo.integration_connect_v1(101,'bkash',NULL,'{}'); ok:=true;
 EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'integration_secret_ref_required' THEN RAISE; END IF; END;
 IF ok THEN RAISE EXCEPTION 'bkash connected without secret reference'; END IF;
 -- unknown provider
 ok:=false; BEGIN PERFORM c10_demo.integration_connect_v1(101,'nope',NULL,'{}'); ok:=true;
 EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'integration_unknown_provider' THEN RAISE; END IF; END;
 IF ok THEN RAISE EXCEPTION 'unknown provider connected'; END IF;
 -- no-secret providers can be connected (today's manual flows)
 PERFORM c10_demo.integration_connect_v1(101,'manual_pay',NULL,'{}');
 -- audit trail exists and holds no secret values
 IF (SELECT count(*) FROM c10_demo.integration_audit_v1 WHERE business_id=101)<5 THEN RAISE EXCEPTION 'audit missing'; END IF;
 IF EXISTS(SELECT 1 FROM c10_demo.integration_audit_v1 WHERE (after_state::text||COALESCE(before_state::text,'')) ~* 'abc')
 THEN RAISE EXCEPTION 'audit contains secret-like value'; END IF;
 -- disconnect clears the reference and turns off
 PERFORM c10_demo.integration_connect_v1(101,'email','ib_101_email_v1','{}');
 PERFORM c10_demo.integration_disconnect_v1((SELECT id FROM c10_demo.integration_account_v1 WHERE provider_code='email'));
 IF (SELECT secret_ref IS NULL AND mode='off' AND status='not_connected' FROM c10_demo.integration_account_v1 WHERE provider_code='email')<>true
 THEN RAISE EXCEPTION 'disconnect did not clear secret reference'; END IF;
END $$;
COMMIT;

-- ============ 2) OUTBOX GATES: OFF, CONSENT, QUIET HOURS, CAP, IDEMPOTENCY ============
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
DO $$
DECLARE a bigint;r jsonb;t_day timestamptz:='2026-01-10 04:00:00+00';   -- 10:00 Asia/Dhaka
        t_night timestamptz:='2026-01-10 17:00:00+00';                    -- 23:00 Asia/Dhaka
BEGIN
 a:=c10_demo.integration_connect_v1(101,'sms','ib_101_sms_v2','{"sender_id":"DEMO"}');
 -- OFF port: nothing is queued for sending
 r:=c10_demo.integration_enqueue_v1(a,'k-off','017xxx','order_ready','{}',t_day);
 IF r->>'state'<>'blocked_port_off' THEN RAISE EXCEPTION 'off port accepted a message: %',r; END IF;
 PERFORM c10_demo.integration_record_test_v1(a,true,'ok');
 PERFORM c10_demo.integration_set_mode_v1(a,'dry_run');
 -- no consent
 r:=c10_demo.integration_enqueue_v1(a,'k-nc','017xxx','order_ready','{}',t_day);
 IF r->>'state'<>'blocked_no_consent' THEN RAISE EXCEPTION 'no-consent message passed: %',r; END IF;
 PERFORM c10_demo.integration_set_consent_v1(101,'sms','017xxx',true,'form');
 -- quiet hours (23:00 Dhaka)
 r:=c10_demo.integration_enqueue_v1(a,'k-night','017xxx','order_ready','{}',t_night);
 IF r->>'state'<>'blocked_quiet_hours' THEN RAISE EXCEPTION 'quiet-hours message passed: %',r; END IF;
 -- allowed daytime
 r:=c10_demo.integration_enqueue_v1(a,'k-day','017xxx','order_ready','{}',t_day);
 IF r->>'state'<>'queued' THEN RAISE EXCEPTION 'valid message not queued: %',r; END IF;
 -- idempotent retry returns the same row and never creates a second
 r:=c10_demo.integration_enqueue_v1(a,'k-day','017xxx','order_ready','{}',t_day);
 IF r->>'status'<>'duplicate' THEN RAISE EXCEPTION 'duplicate not detected: %',r; END IF;
 IF (SELECT count(*) FROM c10_demo.integration_outbox_v1 WHERE account_id=a AND idempotency_key='k-day')<>1
 THEN RAISE EXCEPTION 'duplicate outbox row'; END IF;
 -- opt-out wins immediately
 PERFORM c10_demo.integration_set_consent_v1(101,'sms','017xxx',false,'STOP');
 r:=c10_demo.integration_enqueue_v1(a,'k-optout','017xxx','order_ready','{}',t_day);
 IF r->>'state'<>'blocked_no_consent' THEN RAISE EXCEPTION 'opt-out ignored: %',r; END IF;
 -- a messaging enqueue on a non-messaging provider is refused
 PERFORM c10_demo.integration_connect_v1(101,'bkash','ib_101_bkash_v1','{}');
 BEGIN PERFORM c10_demo.integration_enqueue_v1((SELECT id FROM c10_demo.integration_account_v1 WHERE provider_code='bkash'),'x','y','z','{}',t_day);
  RAISE EXCEPTION 'payment account accepted a message';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'integration_not_messaging' THEN RAISE; END IF; END;
END $$;
COMMIT;

-- daily cap: fixture lowers the cap as table owner (no API function sets it in v1)
UPDATE c10_demo.integration_account_v1 SET daily_cap=1 WHERE provider_code='sms';
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
DO $$
DECLARE a bigint;r jsonb;t_day timestamptz:='2026-01-10 04:00:00+00';o bigint;
BEGIN
 SELECT id INTO a FROM c10_demo.integration_account_v1 WHERE provider_code='sms';
 PERFORM c10_demo.integration_set_consent_v1(101,'sms','018yyy',true,'form');
 PERFORM c10_demo.integration_set_mode_v1(a,'live');
 -- the dry-run row from section 2 is dry; a live message is sent and counts against the cap
 r:=c10_demo.integration_enqueue_v1(a,'k-live-1','018yyy','order_ready','{}',t_day);
 IF r->>'state'<>'queued' THEN RAISE EXCEPTION 'live message not queued: %',r; END IF;
 o:=(r->>'id')::bigint;
 IF (SELECT count(*) FROM c10_demo.integration_claim_v1(a,10,t_day))<>1 THEN RAISE EXCEPTION 'claim count wrong'; END IF;
 IF c10_demo.integration_report_v1(o,true,false,'prov-1',NULL,t_day)<>'sent' THEN RAISE EXCEPTION 'report ok failed'; END IF;
 IF (SELECT sent_count FROM c10_demo.integration_usage_v1 WHERE account_id=a)<>1 THEN RAISE EXCEPTION 'usage not counted'; END IF;
 -- stale/duplicate report cannot move a final state or double count
 IF c10_demo.integration_report_v1(o,false,true,NULL,'late',t_day)<>'sent' THEN RAISE EXCEPTION 'final state moved'; END IF;
 IF (SELECT sent_count FROM c10_demo.integration_usage_v1 WHERE account_id=a)<>1 THEN RAISE EXCEPTION 'usage double counted'; END IF;
 r:=c10_demo.integration_enqueue_v1(a,'k-live-2','018yyy','order_ready','{}',t_day);
 IF r->>'state'<>'blocked_cap' THEN RAISE EXCEPTION 'cap not enforced: %',r; END IF;
END $$;
COMMIT;

-- ============ 3) WORKER: DRY-RUN NEVER SENDS, LEASE RECLAIM, BACKOFF, PERMANENT FAILURE ============
UPDATE c10_demo.integration_account_v1 SET daily_cap=1000 WHERE provider_code='sms';
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
DO $$
DECLARE a bigint;r jsonb;t0 timestamptz:='2026-01-10 04:00:00+00';o1 bigint;o2 bigint;o3 bigint;n int;nt timestamptz;
BEGIN
 SELECT id INTO a FROM c10_demo.integration_account_v1 WHERE provider_code='sms';
 PERFORM c10_demo.integration_set_consent_v1(101,'sms','019zzz',true,'form');
 -- transient: attempt 1 fails => queued again with 30s backoff; attempt 2 => 60s
 o1:=((c10_demo.integration_enqueue_v1(a,'k-w1','019zzz','t','{}',t0))->>'id')::bigint;
 SELECT count(*) INTO n FROM c10_demo.integration_claim_v1(a,10,t0);
 IF n<>1 THEN RAISE EXCEPTION 'expected 1 claimable, got %',n; END IF;
 IF c10_demo.integration_report_v1(o1,false,true,NULL,'http_503',t0)<>'queued' THEN RAISE EXCEPTION 'transient not requeued'; END IF;
 SELECT next_try_at INTO nt FROM c10_demo.integration_outbox_v1 WHERE id=o1;
 IF nt<>t0+interval '30 seconds' THEN RAISE EXCEPTION 'backoff 1 wrong: %',nt; END IF;
 -- not claimable before next_try_at
 IF (SELECT count(*) FROM c10_demo.integration_claim_v1(a,10,t0+interval '10 seconds'))<>0 THEN RAISE EXCEPTION 'claimed before backoff'; END IF;
 IF (SELECT count(*) FROM c10_demo.integration_claim_v1(a,10,t0+interval '31 seconds'))<>1 THEN RAISE EXCEPTION 'not claimable after backoff'; END IF;
 PERFORM c10_demo.integration_report_v1(o1,false,true,NULL,'http_503',t0+interval '31 seconds');
 SELECT next_try_at INTO nt FROM c10_demo.integration_outbox_v1 WHERE id=o1;
 IF nt<>t0+interval '31 seconds'+interval '60 seconds' THEN RAISE EXCEPTION 'backoff 2 wrong: %',nt; END IF;
 -- crashed worker: lease expires and the row is reclaimed (not lost)
 IF (SELECT count(*) FROM c10_demo.integration_claim_v1(a,10,t0+interval '200 seconds'))<>1 THEN RAISE EXCEPTION 'attempt 3 not claimed'; END IF;
 IF (SELECT count(*) FROM c10_demo.integration_claim_v1(a,10,t0+interval '201 seconds'))<>0 THEN RAISE EXCEPTION 'double claim within lease'; END IF;
 IF (SELECT count(*) FROM c10_demo.integration_claim_v1(a,10,t0+interval '400 seconds'))<>1 THEN RAISE EXCEPTION 'expired lease not reclaimed'; END IF;
 -- permanent error fails immediately, no retry
 o2:=((c10_demo.integration_enqueue_v1(a,'k-w2','019zzz','t','{}',t0))->>'id')::bigint;
 PERFORM c10_demo.integration_claim_v1(a,10,t0+interval '500 seconds');
 PERFORM c10_demo.integration_claim_v1(a,10,t0+interval '500 seconds');
 IF c10_demo.integration_report_v1(o2,false,false,NULL,'invalid_number',t0)<>'failed' THEN RAISE EXCEPTION 'permanent not failed'; END IF;
 -- max attempts: o1 has been attempted 4 times; exhaust to 5 then it must go failed on a transient report
 EXECUTE 'RESET ROLE';
 UPDATE c10_demo.integration_outbox_v1 SET max_attempts=4 WHERE id=o1;   -- fixture as table owner
 EXECUTE 'SET LOCAL ROLE authenticated';
 IF c10_demo.integration_report_v1(o1,false,true,NULL,'http_503',t0+interval '401 seconds')<>'failed'
 THEN RAISE EXCEPTION 'exhausted retries not failed'; END IF;
END $$;
COMMIT;

-- dry-run account: claim hands out only dry rows; report never "sends" and never counts usage
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
DO $$
DECLARE a bigint;t0 timestamptz:='2026-01-10 04:00:00+00';o bigint;before_cnt int;
BEGIN
 SELECT id INTO a FROM c10_demo.integration_account_v1 WHERE provider_code='sms';
 PERFORM c10_demo.integration_set_mode_v1(a,'dry_run');
 SELECT sent_count INTO before_cnt FROM c10_demo.integration_usage_v1 WHERE account_id=a;
 PERFORM c10_demo.integration_set_consent_v1(101,'sms','017xxx',true,'form');
 o:=((c10_demo.integration_enqueue_v1(a,'k-dry','017xxx','t','{}',t0))->>'id')::bigint;
 IF NOT (SELECT is_dry_run FROM c10_demo.integration_outbox_v1 WHERE id=o) THEN RAISE EXCEPTION 'row not marked dry'; END IF;
 IF (SELECT count(*) FROM c10_demo.integration_claim_v1(a,10,t0))<1 THEN RAISE EXCEPTION 'dry row not claimable'; END IF;
 IF c10_demo.integration_report_v1(o,true,false,NULL,NULL,t0)<>'dry_run_logged' THEN RAISE EXCEPTION 'dry-run was marked sent'; END IF;
 IF (SELECT sent_count FROM c10_demo.integration_usage_v1 WHERE account_id=a)<>before_cnt THEN RAISE EXCEPTION 'dry-run consumed cap'; END IF;
END $$;
COMMIT;

-- ============ 4) WEBHOOKS: SIGNATURE, IDEMPOTENCY, OFF ============
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
DO $$
DECLARE a bigint;
BEGIN
 SELECT id INTO a FROM c10_demo.integration_account_v1 WHERE provider_code='sms';   -- dry_run now
 IF c10_demo.integration_webhook_receive_v1(a,'evt-1','ok','ref/1')<>'applied' THEN RAISE EXCEPTION 'valid event not applied'; END IF;
 IF c10_demo.integration_webhook_receive_v1(a,'evt-1','ok','ref/1')<>'duplicate' THEN RAISE EXCEPTION 'duplicate event applied twice'; END IF;
 IF c10_demo.integration_webhook_receive_v1(a,'evt-2','bad','ref/2')<>'ignored_bad_signature' THEN RAISE EXCEPTION 'bad signature applied'; END IF;
 IF c10_demo.integration_webhook_receive_v1(a,'evt-3','missing',NULL)<>'ignored_bad_signature' THEN RAISE EXCEPTION 'unsigned applied'; END IF;
 IF (SELECT count(*) FROM c10_demo.integration_webhook_event_v1 WHERE account_id=a)<>3 THEN RAISE EXCEPTION 'events not all stored'; END IF;
 PERFORM c10_demo.integration_set_mode_v1(a,'off');
 IF c10_demo.integration_webhook_receive_v1(a,'evt-4','ok','ref/4')<>'ignored_bad_signature' THEN RAISE EXCEPTION 'event applied while port off'; END IF;
 BEGIN PERFORM c10_demo.integration_webhook_receive_v1(a,'evt-5','maybe',NULL); RAISE EXCEPTION 'invalid status accepted';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'integration_invalid_signature_status' THEN RAISE; END IF; END;
 -- off port: claim returns nothing
 PERFORM c10_demo.integration_set_mode_v1(a,'live');
 IF (c10_demo.integration_enqueue_v1(a,'k-pending-live','017xxx','t','{}','2026-01-10 04:00:00+00'))->>'state'<>'queued' THEN RAISE EXCEPTION 'pending live row not queued'; END IF;
 PERFORM c10_demo.integration_set_mode_v1(a,'off');
 IF (SELECT count(*) FROM c10_demo.integration_claim_v1(a,10,'2026-01-10 05:00:00+00')) <>0 THEN RAISE EXCEPTION 'off port handed rows to a worker'; END IF;
END $$;
COMMIT;

-- ============ 5) KILL SWITCH ============
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
DO $$
DECLARE a bigint;n int;
BEGIN
 SELECT id INTO a FROM c10_demo.integration_account_v1 WHERE provider_code='sms';
 PERFORM c10_demo.integration_set_mode_v1(a,'dry_run');
 PERFORM c10_demo.integration_record_test_v1((SELECT id FROM c10_demo.integration_account_v1 WHERE provider_code='whatsapp'),true,'ok');
 PERFORM c10_demo.integration_set_mode_v1((SELECT id FROM c10_demo.integration_account_v1 WHERE provider_code='whatsapp'),'live');
 n:=c10_demo.integration_kill_switch_v1(101);
 IF n<2 THEN RAISE EXCEPTION 'kill switch turned off only % ports',n; END IF;
 IF EXISTS(SELECT 1 FROM c10_demo.integration_account_v1 WHERE business_id=101 AND mode<>'off') THEN RAISE EXCEPTION 'port survived kill switch'; END IF;
 IF NOT EXISTS(SELECT 1 FROM c10_demo.integration_audit_v1 WHERE action='kill_switch') THEN RAISE EXCEPTION 'kill switch not audited'; END IF;
END $$;
COMMIT;

-- ============ 6) ROLE MATRIX: ONLY OWNER-LEVEL MAY TOUCH PORTS ============
BEGIN;
DO $$
DECLARE uid text;a bigint;fn text;ok boolean;
BEGIN
 SELECT id INTO a FROM c10_demo.integration_account_v1 WHERE provider_code='sms';
 FOREACH uid IN ARRAY ARRAY['33333333-3333-4333-8333-333333333333','55555555-5555-4555-8555-555555555555',
   '44444444-4444-4444-8444-444444444444','66666666-6666-4666-8666-666666666666',
   '77777777-7777-4777-8777-777777777777','99999999-9999-4999-8999-999999999999']
 LOOP
  PERFORM set_config('request.jwt.claim.sub',uid,true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  FOREACH fn IN ARRAY ARRAY[
    format('SELECT c10_demo.integration_set_mode_v1(%s,''dry_run'')',a),
    format('SELECT c10_demo.integration_record_test_v1(%s,true,''x'')',a),
    format('SELECT c10_demo.integration_disconnect_v1(%s)',a),
    'SELECT c10_demo.integration_kill_switch_v1(101)',
    'SELECT c10_demo.integration_connect_v1(101,''email'',''ib_x_v1'',''{}'')',
    'SELECT c10_demo.integration_set_consent_v1(101,''sms'',''c'',true,''x'')',
    format('SELECT c10_demo.integration_enqueue_v1(%s,''k'',''c'',''t'',''{}'')',a),
    format('SELECT c10_demo.integration_claim_v1(%s,5)',a),
    format('SELECT c10_demo.integration_webhook_receive_v1(%s,''e'',''ok'',NULL)',a)] LOOP
   ok:=false;
   BEGIN EXECUTE fn; ok:=true;
   EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'integration_denied' THEN RAISE; END IF; END;
   IF ok THEN RAISE EXCEPTION 'uid % ran: %',uid,fn; END IF;
  END LOOP;
  IF (SELECT count(*) FROM c10_demo.integration_account_v1)<>0 OR (SELECT count(*) FROM c10_demo.integration_audit_v1)<>0
     OR (SELECT count(*) FROM c10_demo.integration_outbox_v1)<>0 OR (SELECT count(*) FROM c10_demo.integration_webhook_event_v1)<>0
     OR (SELECT count(*) FROM c10_demo.integration_consent_v1)<>0 OR (SELECT count(*) FROM c10_demo.integration_usage_v1)<>0
  THEN RAISE EXCEPTION 'uid % can read integration data',uid; END IF;
  -- direct DML denied
  BEGIN UPDATE c10_demo.integration_account_v1 SET mode='live'; RAISE EXCEPTION '% updated account directly',uid;
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN INSERT INTO c10_demo.integration_outbox_v1(tenant_id,business_id,account_id,channel,idempotency_key,contact_ref,template_code,created_by)
   VALUES(1,101,1,'sms','h','c','t',gen_random_uuid()); RAISE EXCEPTION '% inserted outbox directly',uid;
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  EXECUTE 'RESET ROLE';
 END LOOP;
 -- anonymous
 EXECUTE 'SET LOCAL ROLE anon';
 BEGIN PERFORM c10_demo.integration_kill_switch_v1(101); RAISE EXCEPTION 'anon killed ports';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM c10_demo._integration_audit_v1(1,101,NULL,'connect',NULL,NULL); RAISE EXCEPTION 'anon wrote audit';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 EXECUTE 'RESET ROLE';
 -- immutable logs (even for the table owner)
 BEGIN UPDATE c10_demo.integration_audit_v1 SET actor=actor; RAISE EXCEPTION 'audit updated';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN DELETE FROM c10_demo.integration_audit_v1; RAISE EXCEPTION 'audit deleted';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN TRUNCATE c10_demo.integration_audit_v1; RAISE EXCEPTION 'audit truncated';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN UPDATE c10_demo.integration_webhook_event_v1 SET result='applied'; RAISE EXCEPTION 'webhook log updated';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN DELETE FROM c10_demo.integration_webhook_event_v1; RAISE EXCEPTION 'webhook log deleted';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
ROLLBACK;

-- business owner 2222: allowed on own business 101, denied on 102 and on a tenant-2 business
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',true);
DO $$
DECLARE ok boolean;
BEGIN
 IF (SELECT count(*) FROM c10_demo.integration_account_v1)=0 THEN RAISE EXCEPTION 'business owner cannot read own ports'; END IF;
 IF EXISTS(SELECT 1 FROM c10_demo.integration_account_v1 WHERE business_id<>101) THEN RAISE EXCEPTION 'business owner read sibling ports'; END IF;
 ok:=false; BEGIN PERFORM c10_demo.integration_connect_v1(102,'sms','ib_102_sms_v1','{}'); ok:=true;
 EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'integration_denied' THEN RAISE; END IF; END;
 IF ok THEN RAISE EXCEPTION 'business owner connected a sibling business'; END IF;
 ok:=false; BEGIN PERFORM c10_demo.integration_kill_switch_v1(201); ok:=true;
 EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'integration_denied' THEN RAISE; END IF; END;
 IF ok THEN RAISE EXCEPTION 'business owner killed another tenant'; END IF;
 PERFORM c10_demo.integration_connect_v1(101,'redx','ib_101_redx_v1','{}');   -- own business works
END $$;
COMMIT;

-- tenant-2 owner has their own isolated space and sees nothing of tenant 1
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','77777777-7777-4777-8777-777777777777',true);
DO $$
BEGIN
 PERFORM c10_demo.integration_connect_v1(201,'sms','ib_201_sms_v1','{}');
 IF (SELECT count(*) FROM c10_demo.integration_account_v1)<>1 THEN RAISE EXCEPTION 'tenant-2 sees tenant-1 ports'; END IF;
 IF (SELECT count(*) FROM c10_demo.integration_audit_v1)<>1 THEN RAISE EXCEPTION 'tenant-2 sees tenant-1 audit'; END IF;
END $$;
COMMIT;

\echo PASS: A038 integration core: OFF by default, live needs passed test, no secret storage, consent/quiet/cap gates, idempotent outbox, lease+backoff, webhook signatures, kill switch, owner-only RLS, immutable logs
