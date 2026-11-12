-- Read-only owner + maker approval audit/report, synthetic RLS only.
-- Run after the source/reversal E2E plus two-session race script.
\set ON_ERROR_STOP on
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',false);
DO $t$
BEGIN
 IF (SELECT count(*) FROM c10_demo.approval_status_report_v1
     WHERE domain='demo_stock')<>7
 THEN RAISE EXCEPTION 'FAIL: maker own source/report history'; END IF;
 IF (SELECT count(*) FROM c10_demo.approval_status_report_v1
     WHERE domain='demo_stock' AND display_status='executed')<>6
 THEN RAISE EXCEPTION 'FAIL: six posted/reversed receipts not reconciled'; END IF;
 IF NOT EXISTS(SELECT 1 FROM c10_demo.approval_status_report_v1
    WHERE source_key='demo-adjustment:'||
      (SELECT id::text FROM c10_demo.approval_demo_stock_commands_v1
       WHERE request_key='demo_src_prepare_02')
      AND stored_status='approved' AND display_status='executed'
      AND movement_id IS NOT NULL)
 THEN RAISE EXCEPTION 'FAIL: revised source fresh approval receipt missing'; END IF;
 IF NOT EXISTS(SELECT 1 FROM c10_demo.approval_status_report_v1
    WHERE request_id=(SELECT id FROM c10_demo.approval_requests
      WHERE submit_key_v1='demo_submit_stale_02')
      AND display_status='approved_pending_execution' AND movement_id IS NULL)
 THEN RAISE EXCEPTION 'FAIL: stale approved request falsely marked executed'; END IF;
 IF (SELECT count(*) FROM c10_demo.approval_status_report_v1
      WHERE domain='demo_stock' AND execution_kind='reverse'
        AND original_movement_id IS NOT NULL)<>2
 THEN RAISE EXCEPTION 'FAIL: reversal links not projected'; END IF;
 IF NOT EXISTS(SELECT 1 FROM c10_demo.approval_status_report_v1
    WHERE source_key='two-stage-doc-1' AND required_checks=2
      AND completed_checks=2 AND stored_status='approved')
 THEN RAISE EXCEPTION 'FAIL: routed two-stage receipt count'; END IF;
 IF NOT EXISTS(SELECT 1 FROM c10_demo.approval_status_report_v1
    WHERE source_key='two-stage-doc-7' AND required_checks=2
      AND completed_checks=0 AND display_status='awaiting_stage_1')
 THEN RAISE EXCEPTION 'FAIL: pending route has wrong next stage'; END IF;
 -- Business manager can see their own route, not enumerate Owner policy.
 IF (SELECT count(*) FROM c10_demo.approval_policy_versions_v1)<>0
 THEN RAISE EXCEPTION 'FAIL: manager enumerated owner policy versions'; END IF;
END $t$;

SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
DO $t$ BEGIN
 IF (SELECT count(*) FROM c10_demo.approval_status_report_v1
     WHERE domain='demo_stock')<>7
 THEN RAISE EXCEPTION 'FAIL: business owner approval outcome report'; END IF;
END $t$;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
DO $t$ BEGIN
 IF (SELECT count(*) FROM c10_demo.approval_status_report_v1
     WHERE domain='demo_stock')<>7
 THEN RAISE EXCEPTION 'FAIL: tenant owner own business outcome report'; END IF;
END $t$;
SELECT set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',false);
DO $t$ BEGIN
 IF (SELECT count(*) FROM c10_demo.approval_status_report_v1)<>0
 THEN RAISE EXCEPTION 'FAIL: site-only unauthorized approval count'; END IF;
END $t$;
SELECT set_config('request.jwt.claim.sub','55555555-5555-4555-8555-555555555555',false);
DO $t$ BEGIN
 IF (SELECT count(*) FROM c10_demo.approval_status_report_v1)<>0
 THEN RAISE EXCEPTION 'FAIL: investor approval report leak'; END IF;
END $t$;
SELECT set_config('request.jwt.claim.sub','66666666-6666-4666-8666-666666666666',false);
DO $t$ BEGIN
 IF (SELECT count(*) FROM c10_demo.approval_status_report_v1)<>0
 THEN RAISE EXCEPTION 'FAIL: revoked user approval history leak'; END IF;
END $t$;
SELECT set_config('request.jwt.claim.sub','77777777-7777-4777-8777-777777777777',false);
DO $t$ BEGIN
 IF (SELECT count(*) FROM c10_demo.approval_status_report_v1)<>0
 THEN RAISE EXCEPTION 'FAIL: unrelated tenant approval history leak'; END IF;
END $t$;
RESET ROLE;
DO $t$
BEGIN
 IF has_table_privilege('anon','c10_demo.approval_status_report_v1','SELECT')
 OR has_table_privilege('authenticated','c10_demo.approval_status_report_v1','UPDATE')
 THEN RAISE EXCEPTION 'FAIL: public/writable approval status report'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_class c
    JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='c10_demo' AND c.relname='approval_status_report_v1'
      AND c.reloptions::text LIKE '%security_invoker=true%')
 THEN RAISE EXCEPTION 'FAIL: approval projection not security-invoker'; END IF;
 RAISE NOTICE 'PASS: scoped status+stage counts+source/receipt/reversal report, tenant/site/investor/revoked/anon isolation';
END $t$;
