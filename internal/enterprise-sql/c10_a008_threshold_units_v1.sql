-- GOV-002: additive immutable unit/threshold policy for typed approvals.
-- Disposable PostgreSQL 17 / c10_demo ONLY; this is NOT a production migration.
-- Extends the canonical typed submit RPC rather than adding an optional
-- easy-to-bypass UI filter. No financial or inventory posting side effect.
-- Run AFTER A018 + A008 + typed_approval_v1 + routing_delegation_withdrawal_v1.

CREATE TABLE c10_demo.approval_thresholds_v1 (
  policy_id bigint PRIMARY KEY,
  tenant_id bigint NOT NULL,
  business_id bigint NOT NULL,
  measure_type text NOT NULL CHECK (measure_type IN ('currency','quantity')),
  unit_code text NOT NULL CHECK (
    (measure_type='currency' AND unit_code='BDT')
    OR (measure_type='quantity' AND unit_code IN ('KG','PCS','LB'))
  ),
  minimum_value numeric(18,3) NOT NULL CHECK (minimum_value>0),
  operator_code text NOT NULL DEFAULT 'GTE' CHECK(operator_code='GTE'),
  request_key text NOT NULL CHECK(request_key ~ '^[A-Za-z0-9_-]{8,128}$'),
  configured_by uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (business_id,request_key),
  FOREIGN KEY (policy_id,tenant_id,business_id)
    REFERENCES c10_demo.approval_policy_versions_v1(id,tenant_id,business_id),
  CHECK(
    (unit_code='PCS' AND minimum_value=trunc(minimum_value,0))
    OR (unit_code='BDT' AND minimum_value=trunc(minimum_value,2))
    OR unit_code IN ('KG','LB')
  )
);
ALTER TABLE c10_demo.approval_thresholds_v1 ENABLE ROW LEVEL SECURITY;
CREATE POLICY approval_threshold_owner_read_v1
 ON c10_demo.approval_thresholds_v1 FOR SELECT TO authenticated
 USING(c10_demo.can_manage(tenant_id,business_id));
REVOKE ALL ON c10_demo.approval_thresholds_v1 FROM PUBLIC,anon,authenticated;
GRANT SELECT ON c10_demo.approval_thresholds_v1 TO authenticated;

CREATE FUNCTION c10_demo.assert_approval_threshold_v1(
 p_policy bigint,p_payload jsonb
) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER
SET search_path=c10_demo,pg_catalog AS $fn$
DECLARE v c10_demo.approval_thresholds_v1%ROWTYPE;
        v_number numeric;v_places integer;
BEGIN
 SELECT * INTO v FROM c10_demo.approval_thresholds_v1 WHERE policy_id=p_policy;
 IF NOT FOUND THEN RETURN true; END IF;
 -- Exact number type and explicit unit; not string-number coercion.
 IF p_payload IS NULL OR jsonb_typeof(p_payload)<>'object'
   OR jsonb_typeof(p_payload->'amount')<>'number'
   OR jsonb_typeof(p_payload->'unit')<>'string'
   OR p_payload->>'unit' IS DISTINCT FROM v.unit_code
 THEN RAISE EXCEPTION 'approval_threshold_unit_or_amount_invalid'; END IF;
 v_number:=(p_payload->>'amount')::numeric;
 v_places:=CASE v.unit_code WHEN 'PCS' THEN 0 WHEN 'BDT' THEN 2 ELSE 3 END;
 IF v_number<=0 OR v_number<>trunc(v_number,v_places)
 THEN RAISE EXCEPTION 'approval_threshold_precision_invalid'; END IF;
 IF v_number<v.minimum_value THEN RAISE EXCEPTION 'approval_threshold_not_met'; END IF;
 RETURN true;
END $fn$;

-- This is an assessment only, NOT authority to post when below threshold.
-- It does not expose the raw Owner threshold values to managers.
CREATE FUNCTION c10_demo.assess_approval_threshold_v1(
 p_policy bigint,p_payload jsonb
) RETURNS text LANGUAGE plpgsql SECURITY DEFINER
SET search_path=c10_demo,pg_catalog AS $fn$
DECLARE v_p c10_demo.approval_policy_versions_v1%ROWTYPE;
        v_c c10_demo.approval_thresholds_v1%ROWTYPE;
BEGIN
 SELECT * INTO v_p FROM c10_demo.approval_policy_versions_v1 WHERE id=p_policy;
 IF NOT FOUND OR c10_demo.actor_uid() IS NULL
  OR NOT c10_demo.can_business(v_p.tenant_id,v_p.business_id)
 THEN RAISE EXCEPTION 'approval_assessment_denied'; END IF;
 SELECT * INTO v_c FROM c10_demo.approval_thresholds_v1 WHERE policy_id=p_policy;
 IF NOT FOUND THEN RETURN 'UNCONFIGURED'; END IF;
 BEGIN
  PERFORM c10_demo.assert_approval_threshold_v1(p_policy,p_payload);
  RETURN 'REVIEW_REQUIRED';
 EXCEPTION WHEN raise_exception THEN
   IF SQLERRM='approval_threshold_not_met' THEN RETURN 'BELOW_THRESHOLD'; END IF;
   RAISE;
 END;
END $fn$;

CREATE FUNCTION c10_demo.configure_approval_threshold_v1(
 p_policy bigint,p_measure text,p_unit text,p_minimum numeric,p_key text
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path=c10_demo,pg_catalog AS $fn$
DECLARE v_p c10_demo.approval_policy_versions_v1%ROWTYPE;
        v_prior c10_demo.approval_thresholds_v1%ROWTYPE;
        v_actor uuid:=c10_demo.actor_uid();
BEGIN
 IF v_actor IS NULL OR p_policy IS NULL
  OR p_measure NOT IN ('currency','quantity')
  OR NOT ((p_measure='currency' AND p_unit='BDT')
       OR (p_measure='quantity' AND p_unit IN ('KG','PCS','LB')))
  OR p_minimum IS NULL OR p_minimum<=0 OR p_minimum>999999999999999.999
  OR (p_unit='PCS' AND p_minimum<>trunc(p_minimum,0))
  OR (p_unit='BDT' AND p_minimum<>trunc(p_minimum,2))
  OR p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{8,128}$'
 THEN RAISE EXCEPTION 'invalid_approval_threshold'; END IF;
 -- Serialize against typed submission's FOR SHARE on the same policy.
 SELECT * INTO v_p FROM c10_demo.approval_policy_versions_v1
  WHERE id=p_policy FOR UPDATE;
 IF NOT FOUND OR NOT c10_demo.can_manage(v_p.tenant_id,v_p.business_id)
 THEN RAISE EXCEPTION 'threshold_not_authorized'; END IF;
 SELECT * INTO v_prior FROM c10_demo.approval_thresholds_v1
  WHERE policy_id=p_policy;
 IF FOUND THEN
   IF v_prior.measure_type<>p_measure OR v_prior.unit_code<>p_unit
      OR v_prior.minimum_value<>p_minimum OR v_prior.request_key<>p_key
      OR v_prior.configured_by<>v_actor
   THEN RAISE EXCEPTION 'approval_threshold_replay_conflict'; END IF;
   RETURN p_policy;
 END IF;
 IF EXISTS(SELECT 1 FROM c10_demo.approval_requests WHERE policy_id_v1=p_policy)
 THEN RAISE EXCEPTION 'approval_threshold_policy_in_use'; END IF;
 INSERT INTO c10_demo.approval_thresholds_v1
  (policy_id,tenant_id,business_id,measure_type,unit_code,minimum_value,
   request_key,configured_by)
 VALUES(p_policy,v_p.tenant_id,v_p.business_id,p_measure,p_unit,p_minimum,
  p_key,v_actor);
 RETURN p_policy;
END $fn$;

-- Source-derived typed request now enforces threshold for ALL callers,
-- including users still calling the original submit_typed_approval_v1 RPC.

CREATE OR REPLACE FUNCTION c10_demo.submit_typed_approval_v1(
  p_business bigint, p_domain text, p_action text,
  p_source_key text, p_source_version bigint, p_payload jsonb, p_key text
) RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path = c10_demo, pg_catalog AS $fn$
DECLARE
  v_tenant bigint;
  v_actor uuid := c10_demo.actor_uid();
  v_policy c10_demo.approval_policy_versions_v1%ROWTYPE;
  v_digest text;
  v_id bigint;
  v_old c10_demo.approval_requests%ROWTYPE;
BEGIN
  IF v_actor IS NULL OR p_business IS NULL
    OR p_domain IS NULL OR p_domain !~ '^[a-z][a-z0-9_]{1,63}$'
    OR p_action IS NULL OR p_action !~ '^[a-z][a-z0-9_]{1,63}$'
    OR p_source_key IS NULL OR length(btrim(p_source_key)) NOT BETWEEN 1 AND 160
    OR p_source_version IS NULL OR p_source_version <= 0
    OR p_payload IS NULL OR jsonb_typeof(p_payload) <> 'object'
    OR p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{8,128}$'
  THEN RAISE EXCEPTION 'invalid_typed_approval_request'; END IF;

  SELECT tenant_id INTO v_tenant FROM c10_demo.businesses WHERE id = p_business;
  IF NOT FOUND OR NOT c10_demo.can_business(v_tenant, p_business)
  THEN RAISE EXCEPTION 'approval_submit_denied'; END IF;

  -- Normalize JSONB and compute SHA256 at the server; no client-supplied digest.
  v_digest := encode(sha256(convert_to(p_payload::text, 'UTF8')), 'hex');

  -- Replay is bound to the FIRST policy version even after Owner publishes a new one.
  SELECT * INTO v_old FROM c10_demo.approval_requests
    WHERE business_id = p_business AND created_by = v_actor AND submit_key_v1 = p_key;
  IF FOUND THEN
    IF v_old.domain_v1 IS DISTINCT FROM p_domain
      OR v_old.action_code_v1 IS DISTINCT FROM p_action
      OR v_old.source_key_v1 IS DISTINCT FROM btrim(p_source_key)
      OR v_old.source_version_v1 IS DISTINCT FROM p_source_version
      OR v_old.payload_sha256_v1 IS DISTINCT FROM v_digest
    THEN RAISE EXCEPTION 'approval_submit_replay_conflict'; END IF;
    RETURN v_old.id;
  END IF;

  SELECT * INTO v_policy FROM c10_demo.approval_policy_versions_v1
    WHERE tenant_id = v_tenant AND business_id = p_business
      AND domain = p_domain AND action_code = p_action
    ORDER BY version DESC LIMIT 1 FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'approval_policy_missing'; END IF;

  -- A versioned threshold cannot be skipped using the old general typed RPC.
  PERFORM c10_demo.assert_approval_threshold_v1(v_policy.id,p_payload);

  INSERT INTO c10_demo.approval_requests
    (tenant_id, business_id, created_by, domain_v1, action_code_v1,
     source_key_v1, source_version_v1, payload_sha256_v1,
     policy_id_v1, policy_version_v1, expires_at_v1, submit_key_v1)
  VALUES
    (v_tenant, p_business, v_actor, p_domain, p_action,
     btrim(p_source_key), p_source_version, v_digest,
     v_policy.id, v_policy.version,
     clock_timestamp() + make_interval(mins => v_policy.ttl_minutes), p_key)
  ON CONFLICT DO NOTHING RETURNING id INTO v_id;

  IF v_id IS NULL THEN
    SELECT * INTO v_old FROM c10_demo.approval_requests
      WHERE business_id = p_business AND created_by = v_actor AND submit_key_v1 = p_key;
    IF NOT FOUND
      OR v_old.domain_v1 IS DISTINCT FROM p_domain
      OR v_old.action_code_v1 IS DISTINCT FROM p_action
      OR v_old.source_key_v1 IS DISTINCT FROM btrim(p_source_key)
      OR v_old.source_version_v1 IS DISTINCT FROM p_source_version
      OR v_old.payload_sha256_v1 IS DISTINCT FROM v_digest
    THEN RAISE EXCEPTION 'approval_submit_replay_conflict'; END IF;
    v_id := v_old.id;
  END IF;
  RETURN v_id;
END $fn$;

REVOKE ALL ON FUNCTION c10_demo.assert_approval_threshold_v1(bigint,jsonb)
  FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION c10_demo.assess_approval_threshold_v1(bigint,jsonb)
  FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION c10_demo.configure_approval_threshold_v1(bigint,text,text,numeric,text)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION c10_demo.assess_approval_threshold_v1(bigint,jsonb)
  TO authenticated;
GRANT EXECUTE ON FUNCTION c10_demo.configure_approval_threshold_v1(bigint,text,text,numeric,text)
  TO authenticated;
-- The earlier authenticated grant on submit_typed_approval_v1 survives REPLACE.
