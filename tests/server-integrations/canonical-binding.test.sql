\set ON_ERROR_STOP on
BEGIN;
\ir ../../server/integrations/sql/recovered-outbox.candidate.sql
\ir ../../server/integrations/sql/lease-fence.candidate.sql
\ir ../../server/integrations/sql/canonical-binding.candidate.sql
INSERT INTO core10.tenants(id,slug) VALUES(99101,'np11b-fixture-a'),(99102,'np11b-fixture-b');
INSERT INTO core10.legal_entities(id,tenant_id,label) VALUES(99101,99101,'A'),(99102,99102,'B');
INSERT INTO core10.businesses(id,tenant_id,legal_entity_id,slug,template_code,request_key)
 VALUES(99101,99101,99101,'np11b-a','sweets_bakery','np11b-a'),(99102,99102,99102,'np11b-b','sweets_bakery','np11b-b');
INSERT INTO core10.tenant_members(tenant_id,user_id,role) VALUES(99101,'00000000-0000-4000-8000-000000099101','tenant_owner'),(99102,'00000000-0000-4000-8000-000000099102','tenant_owner');
INSERT INTO core10.business_members(tenant_id,business_id,user_id,role,valid_until) VALUES(99101,99101,'00000000-0000-4000-8000-000000099103','business_owner',now()-interval '1 day');
SELECT set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000099101"}',true);
INSERT INTO core10.integration_account_v1(id,tenant_id,business_id,provider_code,mode,status,created_by)
 VALUES(99101,99101,99101,'sms','dry_run','connected',core10.actor_uid()),(99102,99102,99102,'sms','dry_run','connected','00000000-0000-4000-8000-000000099102');
INSERT INTO core10.integration_outbox_v1(id,tenant_id,business_id,account_id,channel,idempotency_key,contact_ref,template_code,is_dry_run,max_attempts,created_by)
 VALUES(99101,99101,99101,99101,'sms','np11b-one','synthetic-contact','sample',true,1,core10.actor_uid());
DO $$
DECLARE a record; st text; n integer;
BEGIN
 IF EXISTS(SELECT 1 FROM pg_class WHERE oid IN('core10.integration_account_v1'::regclass,'core10.integration_outbox_v1'::regclass,'core10.integration_consent_v1'::regclass,'core10.integration_provider_v1'::regclass) AND NOT relrowsecurity) THEN RAISE EXCEPTION 'RLS missing'; END IF;
 IF has_table_privilege('authenticated','core10.integration_outbox_v1','SELECT,INSERT,UPDATE,DELETE') OR has_function_privilege('authenticated','core10._integration_claim_dry_run_candidate_v1(bigint,integer)','EXECUTE') OR has_function_privilege('anon','core10._integration_failed_dry_run_candidate_v1(bigint,integer,bigint)','EXECUTE') THEN RAISE EXCEPTION 'API grants'; END IF;
 BEGIN UPDATE core10.integration_account_v1 SET mode='live',last_test_ok_at=now() WHERE id=99101; RAISE EXCEPTION 'expected live barrier'; EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN INSERT INTO core10.integration_account_v1(tenant_id,business_id,provider_code,created_by) VALUES(99102,99101,'email',core10.actor_uid()); RAISE EXCEPTION 'expected scope FK'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 BEGIN PERFORM core10._integration_claim_dry_run_candidate_v1(99101,1); RAISE EXCEPTION 'expected control hold'; EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'integration_control_hold' THEN RAISE; END IF; END;
 BEGIN PERFORM core10._integration_claim_dry_run_candidate_v1(99102,1); RAISE EXCEPTION 'expected scope denial'; EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'integration_denied' THEN RAISE; END IF; END;
 PERFORM core10.control_set_v1(99101,NULL,'integration.dispatch',true,0::smallint,'{}',NULL,false,0,'Synthetic dry-run only','np11b-enable-0001');
 PERFORM set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000099103"}',true);
 BEGIN PERFORM core10._integration_claim_dry_run_candidate_v1(99101,1); RAISE EXCEPTION 'expected expired owner denial'; EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'integration_denied' THEN RAISE; END IF; END;
 PERFORM set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000099101"}',true);
 SELECT * INTO a FROM core10._integration_claim_dry_run_candidate_v1(99101,1);
 IF a.id IS DISTINCT FROM 99101 OR a.lease_token IS NULL THEN RAISE EXCEPTION 'claim failed'; END IF;
 PERFORM core10.control_set_v1(99101,NULL,'integration.dispatch',false,0::smallint,'{}',NULL,false,1,'Synthetic pause dispatch','np11b-disable-0001');
 BEGIN PERFORM core10._integration_report_dry_run_candidate_v1(99101,a.id,a.lease_token,false,true,'adapter_exception'); RAISE EXCEPTION 'expected switch off'; EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'integration_control_hold' THEN RAISE; END IF; END;
 PERFORM core10.control_set_v1(99101,NULL,'integration.dispatch',true,0::smallint,'{}',NULL,false,2,'Synthetic resume dispatch','np11b-enable-0002');
 st:=core10._integration_report_dry_run_candidate_v1(99101,a.id,a.lease_token,false,true,'adapter_exception');
 IF st<>'failed' THEN RAISE EXCEPTION 'exhaustion failed'; END IF;
 SELECT count(*) INTO n FROM core10._integration_failed_dry_run_candidate_v1(99101,10,NULL) WHERE outbox_id=99101 AND error_code='adapter_exception';
 IF n<>1 THEN RAISE EXCEPTION 'DLQ listing failed'; END IF;
 IF (SELECT count(*) FROM core10.canonical_audit_events_v1 WHERE business_id=99101 AND source_domain='integration')<>2 THEN RAISE EXCEPTION 'audit count'; END IF;
 IF (core10.verify_canonical_audit_v1(99101)->>'ok')::boolean IS DISTINCT FROM true THEN RAISE EXCEPTION 'audit chain'; END IF;
 IF EXISTS(SELECT 1 FROM core10.canonical_audit_events_v1 WHERE source_domain='integration' AND (payload::text LIKE '%synthetic-contact%' OR payload::text LIKE '%'||a.lease_token||'%')) THEN RAISE EXCEPTION 'audit payload leak'; END IF;
 RAISE NOTICE 'PASS: real canonical migrations, scoped membership, expiry, default OFF, owner switch, RLS/ACL, dry-run barrier, DLQ, canonical audit chain';
END $$;
ROLLBACK;
