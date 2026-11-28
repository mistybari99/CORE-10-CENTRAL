\set ON_ERROR_STOP on
BEGIN;
\ir ../../server/integrations/sql/recovered-outbox.candidate.sql
\ir ../../server/integrations/sql/lease-fence.candidate.sql
\ir ../../server/integrations/sql/canonical-binding.candidate.sql
\ir ../../server/integrations/sql/admission.candidate.sql
INSERT INTO core10.tenants(id,slug) VALUES(99201,'np11b-admission-a'),(99202,'np11b-admission-b');
INSERT INTO core10.legal_entities(id,tenant_id,label) VALUES(99201,99201,'A'),(99202,99202,'B');
INSERT INTO core10.businesses(id,tenant_id,legal_entity_id,slug,template_code,request_key)
 VALUES(99201,99201,99201,'np11b-admit-a','sweets_bakery','np11b-admit-a'),(99202,99202,99202,'np11b-admit-b','sweets_bakery','np11b-admit-b');
INSERT INTO core10.tenant_members(tenant_id,user_id,role) VALUES(99201,'00000000-0000-4000-8000-000000099201','tenant_owner'),(99202,'00000000-0000-4000-8000-000000099202','tenant_owner');
SELECT set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000099201"}',true);
SELECT core10.control_set_v1(99201,NULL,'integration.dispatch',true,0::smallint,'{}',NULL,false,0,'Synthetic admission only','np11b-admit-enable');
DO $$
DECLARE a bigint; r jsonb; q jsonb; n bigint;
BEGIN
 a:=core10._integration_configure_dry_run_candidate_v1(99201,'sms','dry_run',1,0,0);
 IF core10._integration_quiet_candidate_v1(a,clock_timestamp()) THEN RAISE EXCEPTION 'equal window'; END IF;
 r:=core10._integration_enqueue_dry_run_candidate_v1(a,'noconsent','synthetic-one','sample');
 IF r->>'state'<>'blocked_no_consent' THEN RAISE EXCEPTION 'consent missing'; END IF;
 PERFORM core10._integration_consent_dry_run_candidate_v1(99201,'sms','synthetic-one',true);
 PERFORM core10._integration_configure_dry_run_candidate_v1(99201,'sms','dry_run',1,22,8);
 IF NOT core10._integration_quiet_candidate_v1(a,'2026-11-26 17:00:00+00') OR core10._integration_quiet_candidate_v1(a,'2026-11-26 06:00:00+00') THEN RAISE EXCEPTION 'overnight quiet'; END IF;
 -- Set a window including the actual server time, then prove enqueue denies.
 PERFORM core10._integration_configure_dry_run_candidate_v1(99201,'sms','dry_run',1,extract(hour FROM clock_timestamp() AT TIME ZONE 'Asia/Dhaka')::int,(extract(hour FROM clock_timestamp() AT TIME ZONE 'Asia/Dhaka')::int+1)%24);
 r:=core10._integration_enqueue_dry_run_candidate_v1(a,'quiet','synthetic-one','sample');
 IF r->>'state'<>'blocked_quiet_hours' THEN RAISE EXCEPTION 'quiet gate'; END IF;
 PERFORM core10._integration_configure_dry_run_candidate_v1(99201,'sms','dry_run',1,0,0);
 r:=core10._integration_enqueue_dry_run_candidate_v1(a,'first','synthetic-one','sample');
 IF r->>'state'<>'queued' THEN RAISE EXCEPTION 'queue gate'; END IF;
 q:=core10._integration_enqueue_dry_run_candidate_v1(a,'first','synthetic-one','sample');
 IF q->>'status'<>'duplicate' OR q->>'id' IS DISTINCT FROM r->>'id' THEN RAISE EXCEPTION 'replay'; END IF;
 BEGIN PERFORM core10._integration_enqueue_dry_run_candidate_v1(a,'first','synthetic-one','changed'); RAISE EXCEPTION 'expected conflict'; EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'integration_replay_conflict' THEN RAISE; END IF; END;
 q:=core10._integration_enqueue_dry_run_candidate_v1(a,'second','synthetic-one','sample');
 IF q->>'state'<>'blocked_cap' THEN RAISE EXCEPTION 'cap gate'; END IF;
 PERFORM core10._integration_consent_dry_run_candidate_v1(99201,'sms','synthetic-one',false);
 SELECT count(*) INTO n FROM core10._integration_claim_dry_run_candidate_v1(a,1);
 IF n<>0 OR NOT EXISTS(SELECT 1 FROM core10.integration_outbox_v1 WHERE id=(r->>'id')::bigint AND state='blocked_no_consent' AND last_error_code='consent_revoked') THEN RAISE EXCEPTION 'revoked queued consent'; END IF;
 PERFORM core10._integration_configure_dry_run_candidate_v1(99201,'sms','off',1,0,0);
 BEGIN PERFORM core10._integration_enqueue_dry_run_candidate_v1(a,'off','synthetic-one','sample'); RAISE EXCEPTION 'expected off denial'; EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'integration_dry_run_only' THEN RAISE; END IF; END;
 BEGIN PERFORM core10._integration_configure_dry_run_candidate_v1(99201,'sms','live',1,0,0); RAISE EXCEPTION 'expected live denial'; EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'integration_config_invalid' THEN RAISE; END IF; END;
 BEGIN PERFORM core10._integration_configure_dry_run_candidate_v1(99202,'sms','dry_run',1,0,0); RAISE EXCEPTION 'expected scope denial'; EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'integration_denied' THEN RAISE; END IF; END;
 IF has_function_privilege('authenticated','core10._integration_enqueue_dry_run_candidate_v1(bigint,text,text,text)','EXECUTE') THEN RAISE EXCEPTION 'public API'; END IF;
 IF (core10.verify_canonical_audit_v1(99201)->>'ok')::boolean IS DISTINCT FROM true OR EXISTS(SELECT 1 FROM core10.canonical_audit_events_v1 WHERE business_id=99201 AND source_domain='integration' AND payload::text LIKE '%synthetic-one%') THEN RAISE EXCEPTION 'audit'; END IF;
 RAISE NOTICE 'PASS admission: consent, quiet, cap, replay, mismatch, revoked consent, OFF, live/scope/ACL, audit';
 -- Dedicated empty email account for parallel admission check.
 PERFORM core10._integration_configure_dry_run_candidate_v1(99201,'email','dry_run',1,0,0);
 PERFORM core10._integration_consent_dry_run_candidate_v1(99201,'email','synthetic-race',true);
END $$;
COMMIT;
