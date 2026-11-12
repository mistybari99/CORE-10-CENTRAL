-- Synthetic approval activity feed: row-level visibility and no raw secrets.
\set ON_ERROR_STOP on
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',false);
DO $t$
DECLARE n bigint;
BEGIN
 n:=(SELECT count(*) FROM c10_demo.approval_activity_feed_v1);
 IF n<7 OR NOT EXISTS(SELECT 1 FROM c10_demo.approval_activity_feed_v1
   WHERE activity_type='exception' AND action='acknowledged')
 OR NOT EXISTS(SELECT 1 FROM c10_demo.approval_activity_feed_v1
   WHERE activity_type='approval' AND action='approve')
 THEN RAISE EXCEPTION 'FAIL: maker event feed missing approval/exception'; END IF;
 IF EXISTS(SELECT 1 FROM c10_demo.approval_activity_feed_v1
   WHERE business_id<>101 OR request_maker<>c10_demo.actor_uid())
 THEN RAISE EXCEPTION 'FAIL: maker feed includes another request'; END IF;
 IF EXISTS(SELECT activity_id FROM c10_demo.approval_activity_feed_v1
  GROUP BY activity_id HAVING count(*)>1)
 THEN RAISE EXCEPTION 'FAIL: cross-event id collision'; END IF;
 PERFORM set_config('demo.test.feed_maker_count',n::text,false);
END $t$;
SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
DO $t$ BEGIN
 IF (SELECT count(*) FROM c10_demo.approval_activity_feed_v1)<
   current_setting('demo.test.feed_maker_count')::bigint
 THEN RAISE EXCEPTION 'FAIL: owner feed less than maker'; END IF;
END $t$;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
DO $t$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM c10_demo.approval_activity_feed_v1
  WHERE activity_type='exception' AND action='submitted')
 THEN RAISE EXCEPTION 'FAIL: tenant Owner cannot view authorized business events'; END IF;
END $t$;
SELECT set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',false);
DO $t$ BEGIN
 IF (SELECT count(*) FROM c10_demo.approval_activity_feed_v1)<>0
 THEN RAISE EXCEPTION 'FAIL: site-only staff see restricted event counts'; END IF;
END $t$;
SELECT set_config('request.jwt.claim.sub','55555555-5555-4555-8555-555555555555',false);
DO $t$ BEGIN
 IF (SELECT count(*) FROM c10_demo.approval_activity_feed_v1)<>0
 THEN RAISE EXCEPTION 'FAIL: investor sees business approval events'; END IF;
END $t$;
SELECT set_config('request.jwt.claim.sub','66666666-6666-4666-8666-666666666666',false);
DO $t$ BEGIN
 IF (SELECT count(*) FROM c10_demo.approval_activity_feed_v1)<>0
 THEN RAISE EXCEPTION 'FAIL: revoked staff still has activity feed'; END IF;
END $t$;
SELECT set_config('request.jwt.claim.sub','77777777-7777-4777-8777-777777777777',false);
DO $t$ BEGIN
 IF (SELECT count(*) FROM c10_demo.approval_activity_feed_v1)<>0
 THEN RAISE EXCEPTION 'FAIL: unrelated tenant receives event data'; END IF;
END $t$;
RESET ROLE;
DO $t$ BEGIN
 IF has_table_privilege('anon','c10_demo.approval_activity_feed_v1','SELECT')
 OR has_table_privilege('authenticated','c10_demo.approval_activity_feed_v1','INSERT')
 OR has_table_privilege('authenticated','c10_demo.approval_activity_feed_v1','UPDATE')
 OR EXISTS(SELECT 1 FROM information_schema.columns
  WHERE table_schema='c10_demo' AND table_name='approval_activity_feed_v1'
   AND column_name IN ('reason','payload','payload_sha256','idempotency_key','token','email'))
 OR NOT EXISTS(SELECT 1 FROM pg_class c
  JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='c10_demo' AND c.relname='approval_activity_feed_v1'
    AND c.reloptions::text LIKE '%security_invoker=true%')
 THEN RAISE EXCEPTION 'FAIL: unsafe/overprivileged activity export projection'; END IF;
 RAISE NOTICE 'PASS: read-only event feed, owner/maker RLS, no foreign badge count, no payload/reason leakage';
END $t$;
