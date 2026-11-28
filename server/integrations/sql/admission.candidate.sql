-- Unnumbered private dry-run admission candidate; never apply hosted.
-- PR27 recovery: configuration, consent, idempotency, Dhaka quiet hours.
-- Provisional cap means accepted dry-run admissions per account per Dhaka day,
-- not live deliveries. Existing accepted jobs keep their reservation; retries do not consume more.
CREATE FUNCTION core10._integration_configure_dry_run_candidate_v1(p_business bigint,p_provider text,p_mode text,p_cap integer,p_start integer,p_end integer)
RETURNS bigint LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE t bigint; a bigint; actor uuid:=core10.actor_uid(); policy jsonb; ref text;
BEGIN
 SELECT tenant_id INTO t FROM core10.businesses WHERE id=p_business;
 IF NOT FOUND OR actor IS NULL OR NOT coalesce(core10.can_manage(t,p_business),false) THEN RAISE EXCEPTION 'integration_denied'; END IF;
 PERFORM 1 FROM core10.businesses WHERE id=p_business AND tenant_id=t FOR UPDATE;
 IF NOT FOUND OR NOT coalesce(core10.can_manage(t,p_business),false) THEN RAISE EXCEPTION 'integration_denied'; END IF;
 IF p_mode IS NULL OR p_mode NOT IN('off','dry_run') OR p_cap IS NULL OR p_cap NOT BETWEEN 0 AND 100000 OR p_start IS NULL OR p_start NOT BETWEEN 0 AND 23 OR p_end IS NULL OR p_end NOT BETWEEN 0 AND 23 THEN RAISE EXCEPTION 'integration_config_invalid'; END IF;
 IF NOT EXISTS(SELECT 1 FROM core10.integration_provider_v1 WHERE code=p_provider AND family='messaging') THEN RAISE EXCEPTION 'integration_not_messaging'; END IF;
 IF p_mode='dry_run' THEN
   policy:=core10._control_resolve_v1(p_business,'integration.dispatch',NULL);
   IF (policy->>'enabled')::boolean IS DISTINCT FROM true OR (policy->>'stages')::integer IS DISTINCT FROM 0 THEN RAISE EXCEPTION 'integration_control_hold'; END IF;
   policy:=core10.control_check_v1(p_business,'integration.dispatch',NULL);
   IF (policy->>'enabled')::boolean IS DISTINCT FROM true OR (policy->>'override_used')::boolean IS DISTINCT FROM false OR (policy->>'stages')::integer IS DISTINCT FROM 0 THEN RAISE EXCEPTION 'integration_control_hold'; END IF;
 END IF;
 INSERT INTO core10.integration_account_v1(tenant_id,business_id,provider_code,mode,status,daily_cap,quiet_start_hour,quiet_end_hour,created_by)
 VALUES(t,p_business,p_provider,p_mode,'connected',p_cap,p_start,p_end,actor)
 ON CONFLICT(business_id,provider_code) DO UPDATE SET mode=EXCLUDED.mode,daily_cap=EXCLUDED.daily_cap,quiet_start_hour=EXCLUDED.quiet_start_hour,quiet_end_hour=EXCLUDED.quiet_end_hour,updated_at=clock_timestamp()
 RETURNING id INTO a;
 ref:='config:'||gen_random_uuid();
 PERFORM core10._append_canonical_audit_v1(t,p_business,'integration',ref,'integration.configure_dry_run',actor,'integration:'||ref,jsonb_build_object('account_id',a,'mode',p_mode,'daily_cap',p_cap,'quiet_start',p_start,'quiet_end',p_end));
 RETURN a;
END $$;
CREATE FUNCTION core10._integration_consent_dry_run_candidate_v1(p_business bigint,p_channel text,p_contact text,p_opt_in boolean)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE t bigint; actor uuid:=core10.actor_uid(); ref text;
BEGIN
 SELECT tenant_id INTO t FROM core10.businesses WHERE id=p_business;
 IF NOT FOUND OR actor IS NULL OR NOT coalesce(core10.can_manage(t,p_business),false) THEN RAISE EXCEPTION 'integration_denied'; END IF;
 PERFORM 1 FROM core10.businesses WHERE id=p_business AND tenant_id=t FOR UPDATE;
 IF NOT FOUND OR NOT coalesce(core10.can_manage(t,p_business),false) THEN RAISE EXCEPTION 'integration_denied'; END IF;
 IF p_channel IS NULL OR p_channel NOT IN('whatsapp','facebook','sms','email') OR p_contact IS NULL OR p_contact !~ '^synthetic-[a-z0-9_-]{1,80}$' OR p_opt_in IS NULL THEN RAISE EXCEPTION 'integration_consent_invalid'; END IF;
 INSERT INTO core10.integration_consent_v1(tenant_id,business_id,channel,contact_ref,opted_in,source)
 VALUES(t,p_business,p_channel,p_contact,p_opt_in,'synthetic_fixture')
 ON CONFLICT(business_id,channel,contact_ref) DO UPDATE SET opted_in=EXCLUDED.opted_in,source=EXCLUDED.source,at=clock_timestamp();
 ref:='consent:'||gen_random_uuid();
 PERFORM core10._append_canonical_audit_v1(t,p_business,'integration',ref,'integration.consent_dry_run',actor,'integration:'||ref,jsonb_build_object('channel',p_channel,'opted_in',p_opt_in));
END $$;
CREATE FUNCTION core10._integration_quiet_candidate_v1(p_account bigint,p_at timestamptz)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
 SELECT CASE WHEN a.quiet_start_hour>a.quiet_end_hour THEN h>=a.quiet_start_hour OR h<a.quiet_end_hour ELSE h>=a.quiet_start_hour AND h<a.quiet_end_hour END
 FROM core10.integration_account_v1 a CROSS JOIN LATERAL (SELECT extract(hour FROM p_at AT TIME ZONE 'Asia/Dhaka')::integer h) q WHERE a.id=p_account
$$;
CREATE FUNCTION core10._integration_enqueue_dry_run_candidate_v1(p_account bigint,p_key text,p_contact text,p_template text)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE a core10.integration_account_v1%ROWTYPE; o core10.integration_outbox_v1%ROWTYPE; actor uuid; t timestamptz; st text; n bigint; ref text;
BEGIN
 actor:=core10._integration_dry_run_guard_candidate_v1(p_account);
 SELECT * INTO a FROM core10.integration_account_v1 WHERE id=p_account;
 IF p_key IS NULL OR p_key !~ '^[a-zA-Z0-9_-]{1,100}$' OR p_contact IS NULL OR p_contact !~ '^synthetic-[a-z0-9_-]{1,80}$' OR p_template IS NULL OR p_template !~ '^[a-zA-Z0-9_-]{1,80}$' THEN RAISE EXCEPTION 'integration_payload_invalid'; END IF;
 IF NOT EXISTS(SELECT 1 FROM core10.integration_provider_v1 WHERE code=a.provider_code AND family='messaging') THEN RAISE EXCEPTION 'integration_not_messaging'; END IF;
 SELECT * INTO o FROM core10.integration_outbox_v1 WHERE account_id=p_account AND idempotency_key=p_key;
 IF FOUND THEN
   IF o.contact_ref IS DISTINCT FROM p_contact OR o.template_code IS DISTINCT FROM p_template OR o.created_by IS DISTINCT FROM actor THEN RAISE EXCEPTION 'integration_replay_conflict'; END IF;
   RETURN jsonb_build_object('status','duplicate','id',o.id,'state',o.state);
 END IF;
 t:=clock_timestamp();
 -- Count accepted admissions, including terminal failures. Revoked admissions remain counted.
 SELECT count(*) INTO n FROM core10.integration_outbox_v1 x WHERE x.account_id=p_account
   AND x.created_at >= date_trunc('day',t AT TIME ZONE 'Asia/Dhaka') AT TIME ZONE 'Asia/Dhaka'
   AND x.created_at < (date_trunc('day',t AT TIME ZONE 'Asia/Dhaka')+interval '1 day') AT TIME ZONE 'Asia/Dhaka'
   AND (x.state IN('queued','claimed','dry_run_logged','failed') OR x.attempts>0 OR x.last_error_code='consent_revoked');
 st:=CASE WHEN NOT EXISTS(SELECT 1 FROM core10.integration_consent_v1 c WHERE c.tenant_id=a.tenant_id AND c.business_id=a.business_id AND c.channel=a.provider_code AND c.contact_ref=p_contact AND c.opted_in) THEN 'blocked_no_consent'
 WHEN core10._integration_quiet_candidate_v1(p_account,t) THEN 'blocked_quiet_hours'
 WHEN n>=a.daily_cap THEN 'blocked_cap' ELSE 'queued' END;
 INSERT INTO core10.integration_outbox_v1(tenant_id,business_id,account_id,channel,idempotency_key,contact_ref,template_code,state,is_dry_run,next_try_at,created_at,created_by)
 VALUES(a.tenant_id,a.business_id,p_account,a.provider_code,p_key,p_contact,p_template,st,true,t,t,actor) RETURNING * INTO o;
 ref:='admission:'||o.id;
 PERFORM core10._append_canonical_audit_v1(a.tenant_id,a.business_id,'integration',ref,'integration.admission_dry_run',actor,'integration:'||ref,jsonb_build_object('outbox_id',o.id,'account_id',p_account,'state',st));
 RETURN jsonb_build_object('status',CASE WHEN st='queued' THEN 'queued' ELSE 'blocked' END,'id',o.id,'state',st);
END $$;
CREATE OR REPLACE FUNCTION core10._integration_claim_dry_run_candidate_v1(p_account bigint,p_limit integer DEFAULT 10)
RETURNS SETOF core10.integration_outbox_v1 LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE actor uuid; t timestamptz;
BEGIN
  IF p_limit IS NULL OR p_limit<1 OR p_limit>100 THEN RAISE EXCEPTION 'integration_limit_invalid'; END IF;
  actor := core10._integration_dry_run_guard_candidate_v1(p_account);
  t := clock_timestamp();
  -- Exhausted expired claims are terminal, not stranded in claimed forever.
  UPDATE core10.integration_outbox_v1 o SET state='failed',lease_until=NULL,lease_token=NULL,lease_actor=NULL,
    last_error_code='lease_attempts_exhausted'
  WHERE o.account_id=p_account AND o.is_dry_run AND o.state='claimed'
    AND o.lease_until<=t AND o.attempts>=o.max_attempts;
  -- A revoked consent blocks eligible pending rows; quiet hours defer rather than deliver.
  UPDATE core10.integration_outbox_v1 o SET state='blocked_no_consent',lease_until=NULL,lease_token=NULL,lease_actor=NULL,last_error_code='consent_revoked'
  WHERE o.id IN (SELECT x.id FROM core10.integration_outbox_v1 x
    WHERE x.account_id=p_account AND x.is_dry_run AND
      (x.state='queued' OR (x.state='claimed' AND x.lease_until<=t))
      AND NOT EXISTS(SELECT 1 FROM core10.integration_consent_v1 c WHERE c.business_id=x.business_id AND c.tenant_id=x.tenant_id AND c.channel=x.channel AND c.contact_ref=x.contact_ref AND c.opted_in)
    ORDER BY x.id LIMIT p_limit FOR UPDATE SKIP LOCKED);
  IF core10._integration_quiet_candidate_v1(p_account,t) THEN RETURN; END IF;
  RETURN QUERY UPDATE core10.integration_outbox_v1 o
    SET state='claimed',lease_until=t+interval '2 minutes',lease_token=gen_random_uuid(),lease_actor=actor,
        attempts=o.attempts+1
    WHERE o.id IN (SELECT x.id FROM core10.integration_outbox_v1 x
      WHERE x.account_id=p_account AND x.is_dry_run AND x.attempts<x.max_attempts
        AND EXISTS(SELECT 1 FROM core10.integration_consent_v1 c WHERE c.business_id=x.business_id AND c.tenant_id=x.tenant_id AND c.channel=x.channel AND c.contact_ref=x.contact_ref AND c.opted_in)
        AND ((x.state='queued' AND x.next_try_at<=t) OR (x.state='claimed' AND x.lease_until<=t))
      ORDER BY x.id LIMIT p_limit FOR UPDATE SKIP LOCKED)
    RETURNING o.*;
END $$;
REVOKE ALL ON FUNCTION core10._integration_configure_dry_run_candidate_v1(bigint,text,text,integer,integer,integer),core10._integration_consent_dry_run_candidate_v1(bigint,text,text,boolean),core10._integration_quiet_candidate_v1(bigint,timestamptz),core10._integration_enqueue_dry_run_candidate_v1(bigint,text,text,text),core10._integration_claim_dry_run_candidate_v1(bigint,integer) FROM PUBLIC,anon,authenticated;
