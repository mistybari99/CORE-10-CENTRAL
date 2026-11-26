-- UNNUMBERED private candidate; apply only after recovered schema and lease-fence candidate.
-- Proposed Control feature default OFF; no approval bypass or override consumption.
INSERT INTO core10.control_catalog_v1(feature_key,title_en,title_bn,pack,default_enabled,default_stages,max_stages,allow_site_scope)
VALUES ('integration.dispatch','Integration dry-run dispatch','ইন্টিগ্রেশন পরীক্ষামূলক প্রেরণ','NP11B',false,0,0,false);
CREATE OR REPLACE FUNCTION core10._integration_dry_run_guard_candidate_v1(p_account bigint)
RETURNS uuid LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE a core10.integration_account_v1%ROWTYPE; actor uuid := core10.actor_uid(); policy jsonb;
BEGIN
 SELECT * INTO a FROM core10.integration_account_v1 WHERE id=p_account;
 IF NOT FOUND OR actor IS NULL OR NOT coalesce(core10.can_manage(a.tenant_id,a.business_id),false) THEN RAISE EXCEPTION 'integration_denied'; END IF;
 -- Canonical access changes serialize on business; lock before account then recheck.
 PERFORM 1 FROM core10.businesses WHERE id=a.business_id AND tenant_id=a.tenant_id FOR UPDATE;
 SELECT * INTO a FROM core10.integration_account_v1 WHERE id=p_account FOR UPDATE;
 IF NOT FOUND OR NOT coalesce(core10.can_manage(a.tenant_id,a.business_id),false) THEN RAISE EXCEPTION 'integration_denied'; END IF;
 IF a.mode IS DISTINCT FROM 'dry_run' OR a.status IS DISTINCT FROM 'connected' THEN RAISE EXCEPTION 'integration_dry_run_only'; END IF;
 policy:=core10._control_resolve_v1(a.business_id,'integration.dispatch',NULL);
 IF (policy->>'enabled')::boolean IS DISTINCT FROM true OR (policy->>'stages')::integer IS DISTINCT FROM 0 THEN RAISE EXCEPTION 'integration_control_hold'; END IF;
 policy:=core10.control_check_v1(a.business_id,'integration.dispatch',NULL);
 IF (policy->>'enabled')::boolean IS DISTINCT FROM true OR (policy->>'override_used')::boolean IS DISTINCT FROM false OR (policy->>'stages')::integer IS DISTINCT FROM 0 THEN RAISE EXCEPTION 'integration_control_hold'; END IF;
 RETURN actor;
END $$;

-- Audit the same canonical chain, atomically with every lease/state transition. Never store tokens, contact, params or provider secrets.
CREATE FUNCTION core10._integration_candidate_audit_v1() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE ref text; actor uuid := core10.actor_uid();
BEGIN
 IF NEW.state IS NOT DISTINCT FROM OLD.state AND NEW.attempts IS NOT DISTINCT FROM OLD.attempts THEN RETURN NEW; END IF;
 ref:='outbox:'||NEW.id||':'||NEW.attempts||':'||NEW.state;
 PERFORM core10._append_canonical_audit_v1(NEW.tenant_id,NEW.business_id,'integration',ref,'integration.'||NEW.state,
  actor,'integration:'||ref,jsonb_build_object('outbox_id',NEW.id,'account_id',NEW.account_id,'attempt',NEW.attempts,'state',NEW.state));
 RETURN NEW;
END $$;
CREATE TRIGGER integration_candidate_audit AFTER UPDATE OF state,attempts ON core10.integration_outbox_v1
 FOR EACH ROW EXECUTE FUNCTION core10._integration_candidate_audit_v1();
REVOKE ALL ON FUNCTION core10._integration_candidate_audit_v1() FROM PUBLIC,anon,authenticated;

-- Private DLQ inspection only: no token, contact, body, secret, provider reference or automatic replay.
CREATE FUNCTION core10._integration_failed_dry_run_candidate_v1(p_account bigint,p_limit integer DEFAULT 50,p_before bigint DEFAULT NULL)
RETURNS TABLE(outbox_id bigint,attempts integer,max_attempts integer,error_code text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE a core10.integration_account_v1%ROWTYPE;
BEGIN
 IF p_limit IS NULL OR p_limit<1 OR p_limit>100 THEN RAISE EXCEPTION 'integration_limit_invalid'; END IF;
 SELECT * INTO a FROM core10.integration_account_v1 WHERE id=p_account;
 IF NOT FOUND OR core10.actor_uid() IS NULL OR NOT coalesce(core10.can_manage(a.tenant_id,a.business_id),false) THEN RAISE EXCEPTION 'integration_denied'; END IF;
 RETURN QUERY SELECT o.id,o.attempts,o.max_attempts,o.last_error_code
 FROM core10.integration_outbox_v1 o WHERE o.account_id=p_account AND o.state='failed' AND o.is_dry_run
 AND (p_before IS NULL OR o.id<p_before) ORDER BY o.id DESC LIMIT p_limit;
END $$;
REVOKE ALL ON FUNCTION core10._integration_failed_dry_run_candidate_v1(bigint,integer,bigint) FROM PUBLIC,anon,authenticated;
