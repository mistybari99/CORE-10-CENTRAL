\set ON_ERROR_STOP on
BEGIN;
SELECT set_config('fixture.actor','00000000-0000-0000-0000-000000000001',true);
DO $$
DECLARE a record; b record; st text; n integer;
BEGIN
 IF has_function_privilege('anon','core10._integration_claim_dry_run_candidate_v1(bigint,integer)','EXECUTE')
 OR has_function_privilege('authenticated','core10._integration_report_dry_run_candidate_v1(bigint,bigint,uuid,boolean,boolean,text)','EXECUTE') THEN RAISE EXCEPTION 'public grant'; END IF;
 BEGIN PERFORM core10._integration_claim_dry_run_candidate_v1(2,1); RAISE EXCEPTION 'expected scope denial'; EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'integration_denied' THEN RAISE; END IF; END;
 BEGIN PERFORM core10._integration_claim_dry_run_candidate_v1(3,1); RAISE EXCEPTION 'expected live denial'; EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'integration_dry_run_only' THEN RAISE; END IF; END;
 SELECT * INTO a FROM core10._integration_claim_dry_run_candidate_v1(1,1);
 IF a.id IS DISTINCT FROM 1 OR a.lease_token IS NULL OR a.attempts<>1 THEN RAISE EXCEPTION 'claim wrong'; END IF;
 -- A different authorized actor cannot report this lease.
 PERFORM set_config('fixture.actor','00000000-0000-0000-0000-000000000002',true);
 BEGIN PERFORM core10._integration_report_dry_run_candidate_v1(1,1,a.lease_token,true,false,NULL); RAISE EXCEPTION 'expected actor denial'; EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'integration_lease_invalid' THEN RAISE; END IF; END;
 PERFORM set_config('fixture.actor','00000000-0000-0000-0000-000000000001',true);
 UPDATE core10.integration_outbox_v1 SET lease_until=clock_timestamp()-interval '1 second' WHERE id=1;
 BEGIN PERFORM core10._integration_report_dry_run_candidate_v1(1,1,a.lease_token,true,false,NULL); RAISE EXCEPTION 'expected expiry denial'; EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'integration_lease_invalid' THEN RAISE; END IF; END;
 SELECT * INTO b FROM core10._integration_claim_dry_run_candidate_v1(1,1);
 IF b.id IS DISTINCT FROM 1 OR b.lease_token IS NULL OR b.lease_token=a.lease_token OR b.attempts<>2 THEN RAISE EXCEPTION 'reclaim wrong'; END IF;
 BEGIN PERFORM core10._integration_report_dry_run_candidate_v1(1,1,a.lease_token,true,false,NULL); RAISE EXCEPTION 'expected stale denial'; EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'integration_lease_invalid' THEN RAISE; END IF; END;
 UPDATE core10.fixture_policy SET enabled=false WHERE business_id=10;
 BEGIN PERFORM core10._integration_report_dry_run_candidate_v1(1,1,b.lease_token,true,false,NULL); RAISE EXCEPTION 'expected control denial'; EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'integration_control_hold' THEN RAISE; END IF; END;
 UPDATE core10.fixture_policy SET enabled=true WHERE business_id=10;
 SELECT core10._integration_report_dry_run_candidate_v1(1,1,b.lease_token,false,true,'secret=never-store') INTO st;
 IF st<>'queued' OR NOT EXISTS(SELECT 1 FROM core10.integration_outbox_v1 WHERE id=1 AND lease_token IS NULL AND last_error_code='dry_run_failed' AND next_try_at>clock_timestamp()) THEN RAISE EXCEPTION 'retry wrong'; END IF;
 UPDATE core10.integration_outbox_v1 SET next_try_at=clock_timestamp()-interval '1 second' WHERE id=1;
 SELECT * INTO b FROM core10._integration_claim_dry_run_candidate_v1(1,1);
 SELECT core10._integration_report_dry_run_candidate_v1(1,1,b.lease_token,false,true,'adapter_exception') INTO st;
 IF st<>'failed' THEN RAISE EXCEPTION 'exhaustion wrong'; END IF;
 SELECT * INTO a FROM core10._integration_claim_dry_run_candidate_v1(1,1);
 IF a.id IS DISTINCT FROM 4 THEN RAISE EXCEPTION 'mode exclusion wrong'; END IF;
 UPDATE core10.integration_outbox_v1 SET lease_until=clock_timestamp()-interval '1 second' WHERE id=4;
 SELECT count(*) INTO n FROM core10._integration_claim_dry_run_candidate_v1(1,1);
 IF n<>0 OR NOT EXISTS(SELECT 1 FROM core10.integration_outbox_v1 WHERE id=4 AND state='failed' AND last_error_code='lease_attempts_exhausted') THEN RAISE EXCEPTION 'expired exhausted wrong'; END IF;
 INSERT INTO core10.integration_outbox_v1(id,account_id,is_dry_run) VALUES(5,1,true);
 SELECT * INTO a FROM core10._integration_claim_dry_run_candidate_v1(1,1);
 SELECT core10._integration_report_dry_run_candidate_v1(1,5,a.lease_token,true,false,NULL) INTO st;
 IF st<>'dry_run_logged' THEN RAISE EXCEPTION 'dry run wrong'; END IF;
 BEGIN PERFORM core10._integration_report_dry_run_candidate_v1(1,5,a.lease_token,true,false,NULL); RAISE EXCEPTION 'expected replay denial'; EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'integration_lease_invalid' THEN RAISE; END IF; END;
 IF EXISTS(SELECT 1 FROM core10.integration_outbox_v1 WHERE state='sent' OR provider_ref IS NOT NULL) THEN RAISE EXCEPTION 'false live success'; END IF;
 RAISE NOTICE 'PASS: lease fence, actor, scope, expiry, stale report, policy OFF, retries, terminal exhaustion, replay, dry-run only and ACL';
END $$;
ROLLBACK;
