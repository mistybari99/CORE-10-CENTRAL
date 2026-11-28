-- UNNUMBERED CANDIDATE ONLY. Not in the migration runner. Do not apply to hosted DB.
-- Requires the future canonical recovery of PR27 integration_account_v1/outbox_v1.
-- Private dry-run slice only: no provider, no secrets, no live claim, no new ledger.
ALTER TABLE core10.integration_outbox_v1
  ADD COLUMN lease_token uuid,
  ADD COLUMN lease_actor uuid;

CREATE FUNCTION core10._integration_dry_run_guard_candidate_v1(p_account bigint)
RETURNS uuid LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE a core10.integration_account_v1%ROWTYPE; actor uuid := core10.actor_uid(); policy jsonb;
BEGIN
  SELECT * INTO a FROM core10.integration_account_v1 WHERE id=p_account FOR UPDATE;
  IF NOT FOUND OR actor IS NULL OR NOT coalesce(core10.can_manage(a.tenant_id,a.business_id),false) THEN
    RAISE EXCEPTION 'integration_denied';
  END IF;
  IF a.mode IS DISTINCT FROM 'dry_run' OR a.status IS DISTINCT FROM 'connected' THEN
    RAISE EXCEPTION 'integration_dry_run_only';
  END IF;
  -- Proposed feature key, not registered by this candidate. No one-time override consumption.
  policy := core10._control_resolve_v1(a.business_id,'integration.dispatch',NULL);
  IF coalesce((policy->>'enabled')::boolean,false) IS NOT TRUE
     OR (policy->>'stages')::integer IS DISTINCT FROM 0 THEN
    RAISE EXCEPTION 'integration_control_hold';
  END IF;
  RETURN actor;
END $$;

CREATE FUNCTION core10._integration_claim_dry_run_candidate_v1(p_account bigint,p_limit integer DEFAULT 10)
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
  RETURN QUERY UPDATE core10.integration_outbox_v1 o
    SET state='claimed',lease_until=t+interval '2 minutes',lease_token=gen_random_uuid(),lease_actor=actor,
        attempts=o.attempts+1
    WHERE o.id IN (SELECT x.id FROM core10.integration_outbox_v1 x
      WHERE x.account_id=p_account AND x.is_dry_run AND x.attempts<x.max_attempts
        AND ((x.state='queued' AND x.next_try_at<=t) OR (x.state='claimed' AND x.lease_until<=t))
      ORDER BY x.id LIMIT p_limit FOR UPDATE SKIP LOCKED)
    RETURNING o.*;
END $$;

CREATE FUNCTION core10._integration_report_dry_run_candidate_v1(
 p_account bigint,p_outbox bigint,p_token uuid,p_ok boolean,p_transient boolean,p_error text)
RETURNS text LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE actor uuid; o core10.integration_outbox_v1%ROWTYPE; t timestamptz; st text; err text;
BEGIN
  actor := core10._integration_dry_run_guard_candidate_v1(p_account);
  SELECT * INTO o FROM core10.integration_outbox_v1 WHERE id=p_outbox AND account_id=p_account FOR UPDATE;
  t := clock_timestamp();
  IF NOT FOUND OR o.is_dry_run IS NOT TRUE OR o.state IS DISTINCT FROM 'claimed'
    OR p_token IS NULL OR o.lease_token IS DISTINCT FROM p_token OR o.lease_actor IS DISTINCT FROM actor
    OR o.lease_until IS NULL OR o.lease_until<=t THEN RAISE EXCEPTION 'integration_lease_invalid'; END IF;
  IF p_ok IS NULL OR p_transient IS NULL OR (p_ok AND p_transient) THEN RAISE EXCEPTION 'integration_result_invalid'; END IF;
  err := CASE WHEN p_error IN ('adapter_exception','bad_response','network_forbidden_in_dry_run') THEN p_error ELSE 'dry_run_failed' END;
  IF p_ok THEN st := 'dry_run_logged';
  ELSIF p_transient AND o.attempts<o.max_attempts THEN st := 'queued';
  ELSE st := 'failed'; END IF;
  UPDATE core10.integration_outbox_v1 SET state=st,lease_until=NULL,lease_token=NULL,lease_actor=NULL,
    provider_ref=NULL,last_error_code=CASE WHEN p_ok THEN NULL ELSE err END,
    next_try_at=CASE WHEN st='queued' THEN t+make_interval(secs=>30*power(2::double precision,least(greatest(o.attempts-1,0),20))) ELSE next_try_at END
  WHERE id=o.id;
  RETURN st;
END $$;
REVOKE ALL ON FUNCTION core10._integration_dry_run_guard_candidate_v1(bigint) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION core10._integration_claim_dry_run_candidate_v1(bigint,integer) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION core10._integration_report_dry_run_candidate_v1(bigint,bigint,uuid,boolean,boolean,text) FROM PUBLIC,anon,authenticated;
