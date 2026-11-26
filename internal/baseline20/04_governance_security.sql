-- CORE10 baseline20 v1; ordered, lossless consolidation. Fresh empty schema only.
-- CORE10 BASELINE SOURCE 0013_np01_journal_truncate_guard.up.sql SHA256 4d3b8d1a5e62f91ac79e1ce6ebf4c32cef40e0b96afd6c2b524f79b1ec46579d
-- NP01 B-005 / 0013: prevent TRUNCATE from bypassing row-level journal immutability.
-- A BEFORE UPDATE/DELETE row trigger is NOT fired by TRUNCATE. This is a structural
-- integrity invariant, never a business-configurable DEC-08 on/off preference.
-- Apply only through the canonical migration runner, not directly to hosted DB.
CREATE FUNCTION core10._deny_np01_journal_truncate_v1()
RETURNS trigger LANGUAGE plpgsql
SET search_path = pg_catalog, core10 AS $np01$
BEGIN
  RAISE EXCEPTION 'core10_journal_truncate_denied:%', TG_TABLE_NAME
    USING ERRCODE = '42501';
END
$np01$;
REVOKE ALL ON FUNCTION core10._deny_np01_journal_truncate_v1()
  FROM PUBLIC, authenticated;

CREATE TRIGGER np01_truncate_guard_01_v1
  BEFORE TRUNCATE ON core10.audit_chain_heads_v1
  FOR EACH STATEMENT EXECUTE FUNCTION core10._deny_np01_journal_truncate_v1();

CREATE TRIGGER np01_truncate_guard_02_v1
  BEFORE TRUNCATE ON core10.canonical_audit_events_v1
  FOR EACH STATEMENT EXECUTE FUNCTION core10._deny_np01_journal_truncate_v1();

CREATE TRIGGER np01_truncate_guard_03_v1
  BEFORE TRUNCATE ON core10.access_change_events_v1
  FOR EACH STATEMENT EXECUTE FUNCTION core10._deny_np01_journal_truncate_v1();

CREATE TRIGGER np01_truncate_guard_04_v1
  BEFORE TRUNCATE ON core10.approval_requests
  FOR EACH STATEMENT EXECUTE FUNCTION core10._deny_np01_journal_truncate_v1();

CREATE TRIGGER np01_truncate_guard_05_v1
  BEFORE TRUNCATE ON core10.approval_events
  FOR EACH STATEMENT EXECUTE FUNCTION core10._deny_np01_journal_truncate_v1();

CREATE TRIGGER np01_truncate_guard_06_v1
  BEFORE TRUNCATE ON core10.approval_policy_versions_v1
  FOR EACH STATEMENT EXECUTE FUNCTION core10._deny_np01_journal_truncate_v1();

CREATE TRIGGER np01_truncate_guard_07_v1
  BEFORE TRUNCATE ON core10.approval_routes_v1
  FOR EACH STATEMENT EXECUTE FUNCTION core10._deny_np01_journal_truncate_v1();

CREATE TRIGGER np01_truncate_guard_08_v1
  BEFORE TRUNCATE ON core10.approval_stage_receipts_v1
  FOR EACH STATEMENT EXECUTE FUNCTION core10._deny_np01_journal_truncate_v1();

CREATE TRIGGER np01_truncate_guard_09_v1
  BEFORE TRUNCATE ON core10.approval_delegations_v1
  FOR EACH STATEMENT EXECUTE FUNCTION core10._deny_np01_journal_truncate_v1();
INSERT INTO core10.schema_migrations(version,name,checksum) VALUES(13,'0013_np01_journal_truncate_guard','4d3b8d1a5e62f91ac79e1ce6ebf4c32cef40e0b96afd6c2b524f79b1ec46579d');

-- CORE10 BASELINE SOURCE 0014_np01_gov002_threshold_units.up.sql SHA256 a8322102b38ed92e7f549f19577448eb0cab14934058593e6b992414267147fa
-- NP01 B-006 / migration 0014 — canonical core10 threshold controls (PR #80 port).
-- No second approval store. No hosted apply. Typed, owner-configurable measure/unit/precision.

CREATE TABLE core10.approval_thresholds_v1 (
  policy_id bigint PRIMARY KEY,
  tenant_id bigint NOT NULL,
  business_id bigint NOT NULL,
  measure_type text NOT NULL CHECK (measure_type IN ('currency','quantity')),
  unit_code text NOT NULL CHECK(unit_code ~ '^[A-Z][A-Z0-9_]{1,11}$'),
  minimum_value numeric(24,6) NOT NULL CHECK (minimum_value>0),
  precision_scale smallint NOT NULL CHECK (precision_scale BETWEEN 0 AND 6),
  operator_code text NOT NULL DEFAULT 'GTE' CHECK(operator_code='GTE'),
  request_key text NOT NULL CHECK(request_key ~ '^[A-Za-z0-9_-]{8,128}$'),
  configured_by uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (business_id,request_key),
  FOREIGN KEY (policy_id,tenant_id,business_id)
    REFERENCES core10.approval_policy_versions_v1(id,tenant_id,business_id),
  CHECK(minimum_value=trunc(minimum_value,precision_scale))
);
ALTER TABLE core10.approval_thresholds_v1 ENABLE ROW LEVEL SECURITY;
CREATE POLICY approval_threshold_owner_read_v1
 ON core10.approval_thresholds_v1 FOR SELECT TO authenticated
 USING(core10.can_manage(tenant_id,business_id));
REVOKE ALL ON core10.approval_thresholds_v1 FROM PUBLIC,authenticated;
GRANT SELECT ON core10.approval_thresholds_v1 TO authenticated;

CREATE FUNCTION core10.assert_approval_threshold_v1(
 p_policy bigint,p_payload jsonb
) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER
SET search_path=core10,pg_catalog AS $fn$
DECLARE v core10.approval_thresholds_v1%ROWTYPE;
        v_number numeric;v_places integer;
BEGIN
 SELECT * INTO v FROM core10.approval_thresholds_v1 WHERE policy_id=p_policy;
 IF NOT FOUND THEN RETURN true; END IF;
 -- Exact number type and explicit unit; not string-number coercion.
 IF p_payload IS NULL OR jsonb_typeof(p_payload)<>'object'
   OR jsonb_typeof(p_payload->'amount')<>'number'
   OR jsonb_typeof(p_payload->'unit')<>'string'
   OR p_payload->>'unit' IS DISTINCT FROM v.unit_code
 THEN RAISE EXCEPTION 'approval_threshold_unit_or_amount_invalid'; END IF;
 v_number:=(p_payload->>'amount')::numeric;
 v_places:=v.precision_scale;
 IF v_number<=0 OR v_number<>trunc(v_number,v_places)
 THEN RAISE EXCEPTION 'approval_threshold_precision_invalid'; END IF;
 IF v_number<v.minimum_value THEN RAISE EXCEPTION 'approval_threshold_not_met'; END IF;
 RETURN true;
END $fn$;

-- This is an assessment only, NOT authority to post when below threshold.
-- It does not expose the raw Owner threshold values to managers.
CREATE FUNCTION core10.assess_approval_threshold_v1(
 p_policy bigint,p_payload jsonb
) RETURNS text LANGUAGE plpgsql SECURITY DEFINER
SET search_path=core10,pg_catalog AS $fn$
DECLARE v_p core10.approval_policy_versions_v1%ROWTYPE;
        v_c core10.approval_thresholds_v1%ROWTYPE;
BEGIN
 SELECT * INTO v_p FROM core10.approval_policy_versions_v1 WHERE id=p_policy;
 IF NOT FOUND OR core10.actor_uid() IS NULL
  OR NOT core10.can_business(v_p.tenant_id,v_p.business_id)
 THEN RAISE EXCEPTION 'approval_assessment_denied'; END IF;
 SELECT * INTO v_c FROM core10.approval_thresholds_v1 WHERE policy_id=p_policy;
 IF NOT FOUND THEN RETURN 'UNCONFIGURED'; END IF;
 BEGIN
  PERFORM core10.assert_approval_threshold_v1(p_policy,p_payload);
  RETURN 'REVIEW_REQUIRED';
 EXCEPTION WHEN raise_exception THEN
   IF SQLERRM='approval_threshold_not_met' THEN RETURN 'BELOW_THRESHOLD'; END IF;
   RAISE;
 END;
END $fn$;

-- Manager-facing assessment resolves the active policy from the scoped command,
-- rather than asking a non-owner to enumerate Owner-only policy IDs.
CREATE FUNCTION core10.assess_current_approval_threshold_v1(
 p_business bigint,p_domain text,p_action text,p_payload jsonb
) RETURNS text LANGUAGE plpgsql SECURITY DEFINER
SET search_path=core10,pg_catalog AS $fn$
DECLARE v_tenant bigint;v_policy bigint;
BEGIN
 SELECT tenant_id INTO v_tenant FROM core10.businesses WHERE id=p_business;
 IF NOT FOUND OR core10.actor_uid() IS NULL
  OR NOT core10.can_business(v_tenant,p_business)
 THEN RAISE EXCEPTION 'approval_assessment_denied'; END IF;
 SELECT id INTO v_policy FROM core10.approval_policy_versions_v1
  WHERE tenant_id=v_tenant AND business_id=p_business
    AND domain=p_domain AND action_code=p_action
  ORDER BY version DESC LIMIT 1;
 IF NOT FOUND THEN RAISE EXCEPTION 'approval_policy_missing'; END IF;
 RETURN core10.assess_approval_threshold_v1(v_policy,p_payload);
END $fn$;

CREATE FUNCTION core10.configure_approval_threshold_v1(
 p_policy bigint,p_measure text,p_unit text,p_minimum numeric,p_precision integer,p_key text
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path=core10,pg_catalog AS $fn$
DECLARE v_p core10.approval_policy_versions_v1%ROWTYPE;
        v_prior core10.approval_thresholds_v1%ROWTYPE;
        v_actor uuid:=core10.actor_uid();
BEGIN
 IF v_actor IS NULL OR p_policy IS NULL
  OR p_measure NOT IN ('currency','quantity')
  OR p_unit IS NULL OR p_unit !~ '^[A-Z][A-Z0-9_]{1,11}$'
  OR p_minimum IS NULL OR p_minimum<=0 OR p_minimum>999999999999999999.999999
  OR p_precision IS NULL OR p_precision NOT BETWEEN 0 AND 6
  OR p_minimum<>trunc(p_minimum,p_precision)
  OR p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{8,128}$'
 THEN RAISE EXCEPTION 'invalid_approval_threshold'; END IF;
 -- Serialize against typed submission's FOR SHARE on the same policy.
 SELECT * INTO v_p FROM core10.approval_policy_versions_v1
  WHERE id=p_policy FOR UPDATE;
 IF NOT FOUND OR NOT core10.can_manage(v_p.tenant_id,v_p.business_id)
 THEN RAISE EXCEPTION 'threshold_not_authorized'; END IF;
 SELECT * INTO v_prior FROM core10.approval_thresholds_v1
  WHERE policy_id=p_policy;
 IF FOUND THEN
   IF v_prior.measure_type<>p_measure OR v_prior.unit_code<>p_unit
      OR v_prior.minimum_value<>p_minimum OR v_prior.precision_scale<>p_precision
      OR v_prior.request_key<>p_key
      OR v_prior.configured_by<>v_actor
   THEN RAISE EXCEPTION 'approval_threshold_replay_conflict'; END IF;
   RETURN p_policy;
 END IF;
 IF EXISTS(SELECT 1 FROM core10.approval_requests WHERE policy_id_v1=p_policy)
 THEN RAISE EXCEPTION 'approval_threshold_policy_in_use'; END IF;
 INSERT INTO core10.approval_thresholds_v1
  (policy_id,tenant_id,business_id,measure_type,unit_code,minimum_value,
   precision_scale,request_key,configured_by)
 VALUES(p_policy,v_p.tenant_id,v_p.business_id,p_measure,p_unit,p_minimum,
  p_precision,p_key,v_actor);
 PERFORM core10._append_canonical_audit_v1(v_p.tenant_id,v_p.business_id,
   'approval_threshold',p_policy::text,'approval.threshold',v_actor,
   'threshold:'||p_policy::text,
   jsonb_build_object('policy_ref',p_policy::text,'measure',p_measure,
    'unit',p_unit,'minimum',p_minimum,'precision',p_precision));
 RETURN p_policy;
END $fn$;

-- Source-derived typed request now enforces threshold for ALL callers,
-- including users still calling the original submit_typed_approval_v1 RPC.

CREATE OR REPLACE FUNCTION core10.submit_typed_approval_v1(
  p_business bigint, p_domain text, p_action text,
  p_source_key text, p_source_version bigint, p_payload jsonb, p_key text
) RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path = core10, pg_catalog AS $fn$
DECLARE
  v_tenant bigint;
  v_actor uuid := core10.actor_uid();
  v_policy core10.approval_policy_versions_v1%ROWTYPE;
  v_digest text;
  v_id bigint;
  v_old core10.approval_requests%ROWTYPE;
BEGIN
  IF v_actor IS NULL OR p_business IS NULL
    OR p_domain IS NULL OR p_domain !~ '^[a-z][a-z0-9_]{1,63}$'
    OR p_action IS NULL OR p_action !~ '^[a-z][a-z0-9_]{1,63}$'
    OR p_source_key IS NULL OR length(btrim(p_source_key)) NOT BETWEEN 1 AND 160
    OR p_source_version IS NULL OR p_source_version <= 0
    OR p_payload IS NULL OR jsonb_typeof(p_payload) <> 'object'
    OR p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{8,128}$'
  THEN RAISE EXCEPTION 'invalid_typed_approval_request'; END IF;

  SELECT tenant_id INTO v_tenant FROM core10.businesses WHERE id = p_business;
  IF NOT FOUND OR NOT core10.can_business(v_tenant, p_business)
  THEN RAISE EXCEPTION 'approval_submit_denied'; END IF;

  -- Normalize JSONB and compute SHA256 at the server; no client-supplied digest.
  v_digest := encode(sha256(convert_to(p_payload::text, 'UTF8')), 'hex');

  -- Replay is bound to the FIRST policy version even after Owner publishes a new one.
  SELECT * INTO v_old FROM core10.approval_requests
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

  SELECT * INTO v_policy FROM core10.approval_policy_versions_v1
    WHERE tenant_id = v_tenant AND business_id = p_business
      AND domain = p_domain AND action_code = p_action
    ORDER BY version DESC LIMIT 1 FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'approval_policy_missing'; END IF;

  -- A versioned threshold cannot be skipped using the old general typed RPC.
  PERFORM core10.assert_approval_threshold_v1(v_policy.id,p_payload);

  INSERT INTO core10.approval_requests
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
    SELECT * INTO v_old FROM core10.approval_requests
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

REVOKE ALL ON FUNCTION core10.assert_approval_threshold_v1(bigint,jsonb)
  FROM PUBLIC,authenticated;
REVOKE ALL ON FUNCTION core10.assess_approval_threshold_v1(bigint,jsonb)
  FROM PUBLIC;
REVOKE ALL ON FUNCTION core10.configure_approval_threshold_v1(bigint,text,text,numeric,integer,text)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION core10.assess_approval_threshold_v1(bigint,jsonb)
  TO authenticated;
GRANT EXECUTE ON FUNCTION core10.configure_approval_threshold_v1(bigint,text,text,numeric,integer,text)
  TO authenticated;
-- The earlier authenticated grant on submit_typed_approval_v1 survives REPLACE.

REVOKE ALL ON FUNCTION core10.assess_current_approval_threshold_v1(bigint,text,text,jsonb)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION core10.assess_current_approval_threshold_v1(bigint,text,text,jsonb)
  TO authenticated;

-- Structural immutability is not Owner-configurable: new policy version for any change.
CREATE FUNCTION core10._deny_np01_threshold_mutation_v1()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,core10 AS $fn$
BEGIN
 RAISE EXCEPTION 'approval_threshold_immutable' USING ERRCODE='42501';
END $fn$;
CREATE TRIGGER np01_threshold_no_change_v1
 BEFORE UPDATE OR DELETE ON core10.approval_thresholds_v1
 FOR EACH ROW EXECUTE FUNCTION core10._deny_np01_threshold_mutation_v1();
CREATE TRIGGER np01_threshold_no_truncate_v1
 BEFORE TRUNCATE ON core10.approval_thresholds_v1
 FOR EACH STATEMENT EXECUTE FUNCTION core10._deny_np01_threshold_mutation_v1();
REVOKE ALL ON FUNCTION core10._deny_np01_threshold_mutation_v1()
 FROM PUBLIC,authenticated;
INSERT INTO core10.schema_migrations(version,name,checksum) VALUES(14,'0014_np01_gov002_threshold_units','a8322102b38ed92e7f549f19577448eb0cab14934058593e6b992414267147fa');

-- CORE10 BASELINE SOURCE 0015_np01_gov002_exception_triage.up.sql SHA256 91bc59cf64f03b52b526d89ce9d1d267b35727c1bc3e418954db7c8807c8d4e7
-- NP01 B-006 migration 0015: scoped exception triage, never domain waiver.
-- Port of PR #82 onto one core10 approval + canonical audit engine.
-- Approval decision and stock/money effects remain untouched by acknowledgement.

CREATE TABLE core10.approval_exception_escalations_v1 (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  request_id bigint NOT NULL UNIQUE REFERENCES core10.approval_requests(id),
  tenant_id bigint NOT NULL,
  business_id bigint NOT NULL,
  policy_id bigint NOT NULL REFERENCES core10.approval_policy_versions_v1(id),
  source_version bigint NOT NULL CHECK(source_version > 0),
  payload_sha256 text NOT NULL CHECK(payload_sha256 ~ '^[0-9a-f]{64}$'),
  created_by uuid NOT NULL,
  reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 12 AND 400),
  severity text NOT NULL CHECK(severity IN ('normal','urgent')),
  ttl_minutes integer NOT NULL CHECK(ttl_minutes BETWEEN 1 AND 43200),
  request_key text NOT NULL CHECK(request_key ~ '^[A-Za-z0-9_-]{8,128}$'),
  status text NOT NULL DEFAULT 'pending'
    CHECK(status IN ('pending','acknowledged','declined','withdrawn')),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  expires_at timestamptz NOT NULL,
  decided_by uuid,
  decided_at timestamptz,
  CHECK (
   (status='pending' AND decided_by IS NULL AND decided_at IS NULL)
   OR (status<>'pending' AND decided_by IS NOT NULL AND decided_at IS NOT NULL)
  ),
  UNIQUE(business_id,created_by,request_key),
  CHECK(expires_at>created_at)
);
CREATE INDEX approval_exception_inbox_idx_v1
 ON core10.approval_exception_escalations_v1
 (business_id,status,expires_at);

CREATE TABLE core10.approval_exception_events_v1 (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 escalation_id bigint NOT NULL REFERENCES core10.approval_exception_escalations_v1(id),
 tenant_id bigint NOT NULL, business_id bigint NOT NULL,
 request_id bigint NOT NULL REFERENCES core10.approval_requests(id),
 creator_id uuid NOT NULL, actor_id uuid NOT NULL,
 action text NOT NULL
  CHECK(action IN ('submitted','acknowledged','declined','withdrawn')),
 event_key text NOT NULL CHECK(event_key ~ '^[A-Za-z0-9_-]{8,128}$'),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(escalation_id,action),
 UNIQUE(escalation_id,event_key)
);
ALTER TABLE core10.approval_exception_escalations_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE core10.approval_exception_events_v1 ENABLE ROW LEVEL SECURITY;
CREATE POLICY exception_scoped_read_v1
 ON core10.approval_exception_escalations_v1
 FOR SELECT TO authenticated
 USING(
  core10.can_manage(tenant_id,business_id)
  OR (created_by=core10.actor_uid()
     AND core10.can_business(tenant_id,business_id))
 );
CREATE POLICY exception_event_scoped_read_v1
 ON core10.approval_exception_events_v1
 FOR SELECT TO authenticated
 USING(
  core10.can_manage(tenant_id,business_id)
  OR (creator_id=core10.actor_uid()
     AND core10.can_business(tenant_id,business_id))
 );
REVOKE ALL ON core10.approval_exception_escalations_v1,
  core10.approval_exception_events_v1 FROM PUBLIC,authenticated;
GRANT SELECT ON core10.approval_exception_escalations_v1,
 core10.approval_exception_events_v1 TO authenticated;

-- One typed request can get ONE escalation. Immutable request/source version,
-- fingerprint, policy and business scope copied from server record.
CREATE FUNCTION core10.request_approval_exception_v1(
 p_request bigint,p_reason text,p_severity text,p_minutes integer,p_key text
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path=core10,pg_catalog AS $fn$
DECLARE v_request core10.approval_requests%ROWTYPE;
        v_old core10.approval_exception_escalations_v1%ROWTYPE;
        v_actor uuid:=core10.actor_uid();
        v_id bigint;v_at timestamptz:=clock_timestamp();
BEGIN
 IF v_actor IS NULL OR p_request IS NULL
  OR p_reason IS NULL OR length(btrim(p_reason)) NOT BETWEEN 12 AND 400
  OR p_severity IS NULL OR p_severity NOT IN ('normal','urgent')
  OR p_minutes IS NULL OR p_minutes NOT BETWEEN 1 AND 43200
  OR p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{8,128}$'
 THEN RAISE EXCEPTION 'invalid_exception_request'; END IF;
 SELECT * INTO v_request FROM core10.approval_requests
  WHERE id=p_request FOR UPDATE;
 IF NOT FOUND OR v_request.policy_id_v1 IS NULL
   OR v_request.created_by<>v_actor
   OR NOT core10.can_business(v_request.tenant_id,v_request.business_id)
 THEN RAISE EXCEPTION 'exception_request_denied'; END IF;
 SELECT * INTO v_old FROM core10.approval_exception_escalations_v1
  WHERE request_id=p_request;
 IF FOUND THEN
  IF v_old.created_by<>v_actor OR v_old.request_key<>p_key
    OR v_old.reason<>btrim(p_reason) OR v_old.severity<>p_severity
    OR v_old.ttl_minutes<>p_minutes
    OR v_old.policy_id<>v_request.policy_id_v1
    OR v_old.source_version<>v_request.source_version_v1
    OR v_old.payload_sha256<>v_request.payload_sha256_v1
  THEN RAISE EXCEPTION 'exception_request_replay_conflict'; END IF;
  RETURN v_old.id;
 END IF;
 IF p_minutes > (SELECT ttl_minutes FROM core10.approval_policy_versions_v1
                    WHERE id=v_request.policy_id_v1) THEN
   RAISE EXCEPTION 'exception_ttl_exceeds_owner_policy';
 END IF;
 IF v_request.status<>'pending'
   OR v_request.expires_at_v1<=v_at
 THEN RAISE EXCEPTION 'exception_parent_not_pending'; END IF;
 INSERT INTO core10.approval_exception_escalations_v1
  (request_id,tenant_id,business_id,policy_id,source_version,
   payload_sha256,created_by,reason,severity,ttl_minutes,request_key,
   created_at,expires_at)
 VALUES(p_request,v_request.tenant_id,v_request.business_id,
  v_request.policy_id_v1,v_request.source_version_v1,
  v_request.payload_sha256_v1,v_actor,btrim(p_reason),p_severity,
  p_minutes,p_key,v_at,LEAST(v_request.expires_at_v1,
                                v_at+make_interval(mins=>p_minutes)))
 RETURNING id INTO v_id;
 INSERT INTO core10.approval_exception_events_v1
  (escalation_id,tenant_id,business_id,request_id,creator_id,actor_id,
   action,event_key)
 VALUES(v_id,v_request.tenant_id,v_request.business_id,p_request,
   v_actor,v_actor,'submitted',p_key);
 RETURN v_id;
END $fn$;

-- Decision is a BUSINESS REVIEW ACKNOWLEDGEMENT/DECLINE, not a
-- waiver or grant. Parent approval state and domain effects remain untouched.
-- Row locking on parent first serializes against normal approve/reject/withdraw.
CREATE FUNCTION core10.decide_approval_exception_v1(
 p_escalation bigint,p_action text,p_key text
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path=core10,pg_catalog AS $fn$
DECLARE v_e core10.approval_exception_escalations_v1%ROWTYPE;
        v_r core10.approval_requests%ROWTYPE;
        v_previous core10.approval_exception_events_v1%ROWTYPE;
        v_actor uuid:=core10.actor_uid();
        v_request_id bigint;v_event bigint;v_at timestamptz:=clock_timestamp();
BEGIN
 IF v_actor IS NULL OR p_escalation IS NULL
  OR p_action NOT IN ('acknowledged','declined')
  OR p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{8,128}$'
 THEN RAISE EXCEPTION 'invalid_exception_decision'; END IF;
 SELECT request_id INTO v_request_id
  FROM core10.approval_exception_escalations_v1 WHERE id=p_escalation;
 IF NOT FOUND THEN RAISE EXCEPTION 'exception_not_found'; END IF;
 SELECT * INTO v_r FROM core10.approval_requests
  WHERE id=v_request_id FOR UPDATE;
 SELECT * INTO v_e FROM core10.approval_exception_escalations_v1
  WHERE id=p_escalation FOR UPDATE;
 IF NOT FOUND OR v_e.created_by=v_actor
   OR NOT core10.can_manage(v_e.tenant_id,v_e.business_id)
   OR v_e.tenant_id<>v_r.tenant_id OR v_e.business_id<>v_r.business_id
 THEN RAISE EXCEPTION 'exception_decision_denied'; END IF;
 SELECT * INTO v_previous FROM core10.approval_exception_events_v1
  WHERE escalation_id=p_escalation AND event_key=p_key;
 IF FOUND THEN
  IF v_previous.actor_id<>v_actor OR v_previous.action<>p_action
  THEN RAISE EXCEPTION 'exception_decision_replay_conflict'; END IF;
  RETURN v_previous.id;
 END IF;
 IF v_e.status<>'pending' OR v_e.expires_at<=v_at
  OR v_r.status<>'pending' OR v_r.expires_at_v1<=v_at
  OR v_e.policy_id<>v_r.policy_id_v1
  OR v_e.source_version<>v_r.source_version_v1
  OR v_e.payload_sha256<>v_r.payload_sha256_v1
 THEN RAISE EXCEPTION 'exception_stale_or_final'; END IF;
 UPDATE core10.approval_exception_escalations_v1
 SET status=p_action,decided_by=v_actor,decided_at=v_at WHERE id=p_escalation;
 INSERT INTO core10.approval_exception_events_v1
   (escalation_id,tenant_id,business_id,request_id,creator_id,actor_id,
    action,event_key)
 VALUES(p_escalation,v_e.tenant_id,v_e.business_id,v_r.id,
   v_e.created_by,v_actor,p_action,p_key)
 RETURNING id INTO v_event;
 RETURN v_event;
END $fn$;

CREATE FUNCTION core10.withdraw_approval_exception_v1(
 p_escalation bigint,p_key text
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path=core10,pg_catalog AS $fn$
DECLARE v_e core10.approval_exception_escalations_v1%ROWTYPE;
        v_r core10.approval_requests%ROWTYPE;
        v_previous core10.approval_exception_events_v1%ROWTYPE;
        v_actor uuid:=core10.actor_uid();
        v_request_id bigint;v_event bigint;
BEGIN
 IF v_actor IS NULL OR p_escalation IS NULL
  OR p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{8,128}$'
 THEN RAISE EXCEPTION 'invalid_exception_withdraw'; END IF;
 SELECT request_id INTO v_request_id
  FROM core10.approval_exception_escalations_v1 WHERE id=p_escalation;
 IF NOT FOUND THEN RAISE EXCEPTION 'exception_not_found'; END IF;
 SELECT * INTO v_r FROM core10.approval_requests
  WHERE id=v_request_id FOR UPDATE;
 SELECT * INTO v_e FROM core10.approval_exception_escalations_v1
  WHERE id=p_escalation FOR UPDATE;
 IF NOT FOUND OR v_e.created_by<>v_actor
  OR NOT core10.can_business(v_e.tenant_id,v_e.business_id)
  OR v_e.request_id<>v_r.id
 THEN RAISE EXCEPTION 'exception_withdraw_denied'; END IF;
 SELECT * INTO v_previous FROM core10.approval_exception_events_v1
  WHERE escalation_id=p_escalation AND event_key=p_key;
 IF FOUND THEN
  IF v_previous.actor_id<>v_actor OR v_previous.action<>'withdrawn'
  THEN RAISE EXCEPTION 'exception_withdraw_replay_conflict'; END IF;
  RETURN v_previous.id;
 END IF;
 IF v_e.status<>'pending'
 THEN RAISE EXCEPTION 'exception_stale_or_final'; END IF;
 UPDATE core10.approval_exception_escalations_v1
  SET status='withdrawn',decided_by=v_actor,decided_at=clock_timestamp()
 WHERE id=p_escalation;
 INSERT INTO core10.approval_exception_events_v1
  (escalation_id,tenant_id,business_id,request_id,creator_id,actor_id,
   action,event_key)
 VALUES(p_escalation,v_e.tenant_id,v_e.business_id,v_r.id,
 v_e.created_by,v_actor,'withdrawn',p_key)
 RETURNING id INTO v_event;
 RETURN v_event;
END $fn$;

-- Read-only, RLS-invoker projection for a future guided owner/maker UI.
-- View NEVER provides waiver, execute token, amount, or source payload.
CREATE VIEW core10.approval_exception_inbox_v1
WITH (security_invoker=true) AS
SELECT e.id AS escalation_id,e.request_id,e.tenant_id,e.business_id,
 e.policy_id,e.source_version,e.created_by,
 e.reason,e.severity,e.created_at,e.expires_at,
 e.status AS stored_status,r.status AS parent_approval_status,
 CASE WHEN e.status='pending' AND r.status<>'pending'
          THEN 'parent_closed'
      WHEN e.status='pending' AND e.expires_at<=clock_timestamp()
          THEN 'expired'
      WHEN e.status='pending' AND r.expires_at_v1<=clock_timestamp()
          THEN 'expired'
      ELSE e.status END AS display_status,
 e.decided_by,e.decided_at
FROM core10.approval_exception_escalations_v1 e
JOIN core10.approval_requests r ON r.id=e.request_id
 WHERE e.policy_id=r.policy_id_v1
   AND e.tenant_id=r.tenant_id AND e.business_id=r.business_id
   AND (
     core10.can_manage(e.tenant_id,e.business_id)
     OR (e.created_by=core10.actor_uid()
         AND core10.can_business(e.tenant_id,e.business_id))
   );
REVOKE ALL ON core10.approval_exception_inbox_v1 FROM PUBLIC;
GRANT SELECT ON core10.approval_exception_inbox_v1 TO authenticated;
REVOKE ALL ON FUNCTION
 core10.request_approval_exception_v1(bigint,text,text,integer,text),
 core10.decide_approval_exception_v1(bigint,text,text),
 core10.withdraw_approval_exception_v1(bigint,text)
 FROM PUBLIC;
GRANT EXECUTE ON FUNCTION
 core10.request_approval_exception_v1(bigint,text,text,integer,text),
 core10.decide_approval_exception_v1(bigint,text,text),
 core10.withdraw_approval_exception_v1(bigint,text)
 TO authenticated;
-- Explicit absence of any bypass/override/execute authority is intentional.

-- Every exception journal event also appends to the already-canonical audit chain.
-- This table stores the *domain event receipt*, not a second audit engine.
CREATE FUNCTION core10._exception_to_canonical_audit_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,core10 AS $np01$
BEGIN
 PERFORM core10._append_canonical_audit_v1(
   NEW.tenant_id,NEW.business_id,'approval_exception',NEW.id::text,
   'approval.exception_'||NEW.action,NEW.actor_id,'exception:'||NEW.id::text,
   jsonb_build_object('event_ref',NEW.id::text,'request_ref',NEW.request_id::text,
                      'escalation_ref',NEW.escalation_id::text,'action',NEW.action));
 RETURN NEW;
END $np01$;
CREATE TRIGGER np01_exception_to_canonical_audit_v1
 AFTER INSERT ON core10.approval_exception_events_v1
 FOR EACH ROW EXECUTE FUNCTION core10._exception_to_canonical_audit_v1();
REVOKE ALL ON FUNCTION core10._exception_to_canonical_audit_v1() FROM PUBLIC,authenticated;
CREATE FUNCTION core10._deny_np01_exception_event_mutation_v1()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,core10 AS $np01$
BEGIN RAISE EXCEPTION 'approval_exception_journal_immutable' USING ERRCODE='42501'; END $np01$;
CREATE TRIGGER np01_exception_event_immutable_v1
 BEFORE UPDATE OR DELETE ON core10.approval_exception_events_v1
 FOR EACH ROW EXECUTE FUNCTION core10._deny_np01_exception_event_mutation_v1();
CREATE TRIGGER np01_exception_event_no_truncate_v1
 BEFORE TRUNCATE ON core10.approval_exception_events_v1
 FOR EACH STATEMENT EXECUTE FUNCTION core10._deny_np01_exception_event_mutation_v1();
CREATE TRIGGER np01_exception_state_no_truncate_v1
 BEFORE TRUNCATE ON core10.approval_exception_escalations_v1
 FOR EACH STATEMENT EXECUTE FUNCTION core10._deny_np01_exception_event_mutation_v1();
REVOKE ALL ON FUNCTION core10._deny_np01_exception_event_mutation_v1()
 FROM PUBLIC,authenticated;
INSERT INTO core10.schema_migrations(version,name,checksum) VALUES(15,'0015_np01_gov002_exception_triage','91bc59cf64f03b52b526d89ce9d1d267b35727c1bc3e418954db7c8807c8d4e7');

-- CORE10 BASELINE SOURCE 0016_np01_gov003_canonical_readiness.up.sql SHA256 2be1d4d68fd75c005d64f289645387580745a6e70262d3f828d362fb1300cd2f
-- NP01 B-007 / migration 0016: GOV-003 canonical audit readiness/risk/export.
-- No tenant, role, journal or audit shadow tables: all reads use core10 0008.
-- These are scoped advisory/read-only ports. NOT a release certification.
CREATE FUNCTION core10.gov003_audit_readiness_v1(p_business bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,core10 AS $fn$
DECLARE v_tenant bigint;v_chain jsonb;v_event_count bigint;v_request_count bigint;
BEGIN
 SELECT b.tenant_id INTO v_tenant FROM core10.businesses b WHERE b.id=p_business;
 IF core10.actor_uid() IS NULL OR v_tenant IS NULL
   OR NOT core10.can_manage(v_tenant,p_business)
 THEN RAISE EXCEPTION 'gov003_readiness_denied' USING ERRCODE='42501'; END IF;
 v_chain:=core10.verify_canonical_audit_v1(p_business);
 SELECT count(*) INTO v_event_count FROM core10.canonical_audit_events_v1 a
  WHERE a.tenant_id=v_tenant AND a.business_id=p_business;
 SELECT count(*) INTO v_request_count FROM core10.approval_requests q
  WHERE q.tenant_id=v_tenant AND q.business_id=p_business;
 RETURN jsonb_build_object(
  'contract','C10_GOV003_CANONICAL_READINESS_V1','business_id',p_business,
  'canonical_chain',v_chain,'canonical_event_count',v_event_count,
  'approval_request_count',v_request_count,
  'release_certified',false,'ready_for_production',false,
  'status',CASE WHEN v_chain->>'ok'='true' THEN 'INTEGRITY_CHECK_ONLY'
                ELSE 'INTEGRITY_REVIEW_REQUIRED' END,
  'missing_proof',jsonb_build_array('signed_staging_personas',
    'owner_control_binding','source_linked_operational_e2e',
    'deployment_probe','retention_review'));
END $fn$;
REVOKE ALL ON FUNCTION core10.gov003_audit_readiness_v1(bigint) FROM PUBLIC,authenticated;
GRANT EXECUTE ON FUNCTION core10.gov003_audit_readiness_v1(bigint) TO authenticated;

-- Risk is factual triage, NEVER a prediction of compliance or an approval grant.
-- The Owner supplies the time window; no mutable business threshold is hardcoded.
CREATE FUNCTION core10.gov003_audit_risk_v1(p_business bigint,p_since timestamptz)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,core10 AS $fn$
DECLARE v_tenant bigint;v_chain jsonb;v_declined bigint;
 v_expired bigint;v_open_exceptions bigint;v_events bigint;
BEGIN
 SELECT b.tenant_id INTO v_tenant FROM core10.businesses b WHERE b.id=p_business;
 IF core10.actor_uid() IS NULL OR v_tenant IS NULL
    OR NOT core10.can_manage(v_tenant,p_business)
    OR p_since IS NULL OR p_since>statement_timestamp()
 THEN RAISE EXCEPTION 'gov003_risk_denied' USING ERRCODE='42501'; END IF;
 v_chain:=core10.verify_canonical_audit_v1(p_business);
 SELECT count(*) INTO v_events FROM core10.canonical_audit_events_v1 a
  WHERE a.tenant_id=v_tenant AND a.business_id=p_business AND a.event_at>=p_since;
 SELECT count(*) INTO v_declined FROM core10.approval_exception_escalations_v1 e
  WHERE e.tenant_id=v_tenant AND e.business_id=p_business AND e.status='declined'
   AND e.created_at>=p_since;
 SELECT count(*) INTO v_expired FROM core10.approval_requests q
  WHERE q.tenant_id=v_tenant AND q.business_id=p_business
   AND q.status='pending' AND q.expires_at_v1<statement_timestamp()
   AND q.created_at>=p_since;
 SELECT count(*) INTO v_open_exceptions FROM core10.approval_exception_escalations_v1 e
  WHERE e.tenant_id=v_tenant AND e.business_id=p_business AND e.status='pending'
   AND e.expires_at>statement_timestamp();
 RETURN jsonb_build_object('contract','C10_GOV003_SCOPED_RISK_V1',
  'business_id',p_business,'since',p_since,'event_count',v_events,
  'declined_exceptions',v_declined,'expired_pending_approvals',v_expired,
  'open_exceptions',v_open_exceptions,'chain_ok',v_chain->'ok',
  'advisory_only',true,'release_certified',false);
END $fn$;
REVOKE ALL ON FUNCTION core10.gov003_audit_risk_v1(bigint,timestamptz)
 FROM PUBLIC,authenticated;
GRANT EXECUTE ON FUNCTION core10.gov003_audit_risk_v1(bigint,timestamptz)
 TO authenticated;

-- Bounded audit metadata projection, not raw payload / PII, per business.
-- A downstream signed client may serialize this allowlisted dataset to safe CSV.
CREATE FUNCTION core10.gov003_audit_export_v1(
 p_business bigint,p_after_seq bigint DEFAULT 0,p_limit integer DEFAULT 100
) RETURNS TABLE(stream_seq bigint,source_domain text,source_ref text,
 action text,event_at timestamptz,payload_sha256 text,event_digest text)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,core10 AS $fn$
DECLARE v_tenant bigint;
BEGIN
 SELECT b.tenant_id INTO v_tenant FROM core10.businesses b WHERE b.id=p_business;
 IF core10.actor_uid() IS NULL OR v_tenant IS NULL
  OR NOT core10.can_manage(v_tenant,p_business)
  OR p_after_seq IS NULL OR p_after_seq<0
  OR p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 500
 THEN RAISE EXCEPTION 'gov003_export_denied' USING ERRCODE='42501'; END IF;
 RETURN QUERY SELECT a.stream_seq,a.source_domain,a.source_ref,
    a.action,a.event_at,a.payload_sha256,a.event_digest
  FROM core10.canonical_audit_events_v1 a
  WHERE a.business_id=p_business AND a.tenant_id=v_tenant
    AND a.stream_seq>p_after_seq
  ORDER BY a.stream_seq LIMIT p_limit;
END $fn$;
REVOKE ALL ON FUNCTION core10.gov003_audit_export_v1(bigint,bigint,integer)
 FROM PUBLIC,authenticated;
GRANT EXECUTE ON FUNCTION core10.gov003_audit_export_v1(bigint,bigint,integer)
 TO authenticated;
INSERT INTO core10.schema_migrations(version,name,checksum) VALUES(16,'0016_np01_gov003_canonical_readiness','2be1d4d68fd75c005d64f289645387580745a6e70262d3f828d362fb1300cd2f');

-- CORE10 BASELINE SOURCE 0017_np01_unbound_rpc_fence.up.sql SHA256 a4022411abae525ae2eae1dbacab83fab0ef908f11afbf40afa5c9995d4b2020
-- NP01 B-020 / 0017: temporary fail-closed boundary while Owner Control integration is pending.
-- 0014-0015 added API-callable VOLATILE functions that are not registered in the
-- B-010/0102 Owner Control catalog. Do not disable the registry gate to hide them.
-- Until a follow-on owner-approved binding/registry migration is integrated,
-- REVOKE direct authenticated execute to prevent ungoverned mutations.
-- These are DRAFT-only functions, not yet part of a certified hosted API.
-- Full feature binding and reenabling is a separate B-020 integration gate.
REVOKE EXECUTE ON FUNCTION
 core10.assess_approval_threshold_v1(bigint,jsonb),
 core10.assess_current_approval_threshold_v1(bigint,text,text,jsonb),
 core10.configure_approval_threshold_v1(bigint,text,text,numeric,integer,text),
 core10.request_approval_exception_v1(bigint,text,text,integer,text),
 core10.decide_approval_exception_v1(bigint,text,text),
 core10.withdraw_approval_exception_v1(bigint,text)
FROM PUBLIC, authenticated;
INSERT INTO core10.schema_migrations(version,name,checksum) VALUES(17,'0017_np01_unbound_rpc_fence','a4022411abae525ae2eae1dbacab83fab0ef908f11afbf40afa5c9995d4b2020');

-- CORE10 BASELINE SOURCE 0018_np01_approval_policy_control.up.sql SHA256 54b928c15337bd7ac28c870c0dc354e025a3f896919c1ba6f0618cf52f320421
-- NP01 B-020 / 0018: bind canonical policy publishing to the Owner Control port.
-- Executes after the caller's Auth check, before policy replay or mutation.
-- The Control port is created by 0100-0102 later in the ordered migration set;
-- this replacement function is not invoked until all migrations have been applied.
-- Its existing signature and GRANTs are preserved by CREATE OR REPLACE.
CREATE OR REPLACE FUNCTION core10.publish_approval_policy_v1(
  p_business bigint, p_domain text, p_action text, p_ttl_minutes integer, p_key text
) RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path = core10, pg_catalog AS $fn$
DECLARE
  v_tenant bigint;
  v_actor uuid := core10.actor_uid();
  v_version integer;
  v_id bigint;
  v_control jsonb;
  v_effective_ttl integer;
  v_old core10.approval_policy_versions_v1%ROWTYPE;
BEGIN
  IF v_actor IS NULL OR p_business IS NULL
    OR p_domain IS NULL OR p_domain !~ '^[a-z][a-z0-9_]{1,63}$'
    OR p_action IS NULL OR p_action !~ '^[a-z][a-z0-9_]{1,63}$'
    OR (p_ttl_minutes IS NOT NULL AND p_ttl_minutes NOT BETWEEN 5 AND 43200)
    OR p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{8,128}$'
  THEN RAISE EXCEPTION 'invalid_approval_policy'; END IF;

  -- Serialize version allocation for this business, including concurrent owners.
  SELECT tenant_id INTO v_tenant
    FROM core10.businesses WHERE id = p_business FOR UPDATE;
  IF NOT FOUND OR NOT core10.can_manage(v_tenant, p_business)
  THEN RAISE EXCEPTION 'approval_policy_denied'; END IF;

  -- After the Auth port passes, enforce the Owner's per-business switch.
  -- The Owner-configured TTL is the default; an explicit policy TTL remains
  -- subject to the existing canonical 5..43200 minute validation.
  v_control := core10.control_check_v1(p_business,'gov002.approval_policy',NULL);
  v_effective_ttl := coalesce(p_ttl_minutes,(v_control->'params'->>'ttl_minutes')::integer);
  IF v_effective_ttl IS NULL OR v_effective_ttl NOT BETWEEN 5 AND 43200
  THEN RAISE EXCEPTION 'invalid_approval_policy'; END IF;

  SELECT * INTO v_old FROM core10.approval_policy_versions_v1
    WHERE business_id = p_business AND request_key = p_key;
  IF FOUND THEN
    IF v_old.created_by <> v_actor OR v_old.domain <> p_domain
      OR v_old.action_code <> p_action OR v_old.ttl_minutes <> v_effective_ttl
    THEN RAISE EXCEPTION 'approval_policy_replay_conflict'; END IF;
    RETURN v_old.id;
  END IF;

  SELECT COALESCE(max(version), 0) + 1 INTO v_version
    FROM core10.approval_policy_versions_v1
    WHERE business_id = p_business AND domain = p_domain
      AND action_code = p_action;

  INSERT INTO core10.approval_policy_versions_v1
    (tenant_id, business_id, domain, action_code, version,
     ttl_minutes, request_key, created_by)
  VALUES (v_tenant, p_business, p_domain, p_action, v_version,
          v_effective_ttl, p_key, v_actor)
  RETURNING id INTO v_id;
  RETURN v_id;
END $fn$;
INSERT INTO core10.schema_migrations(version,name,checksum) VALUES(18,'0018_np01_approval_policy_control','54b928c15337bd7ac28c870c0dc354e025a3f896919c1ba6f0618cf52f320421');

-- CORE10 BASELINE SOURCE 0019_np01_review_control.up.sql SHA256 1a5522ce289a494c9d4234ab5d6b6f0422a6a6305ce293cef382023d86e0a9e5
-- B-020 / NP01 0019: canonical Owner Control for decisions and maker withdrawal.
-- Only replaces existing public RPC bodies; preserves signatures, grants and receipts.
-- Runs before NP02 0100-0102; runtime calls execute only after Control port exists.
-- Current 0102 registry remains pending until Claude-owned post-0102 promotion.
CREATE OR REPLACE FUNCTION core10.decide_approval(
 p_request bigint,p_action text,p_key text
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,core10 AS $fn$
DECLARE q core10.approval_requests%ROWTYPE;actor uuid:=core10.actor_uid();
 prior core10.approval_events%ROWTYPE;v_stages text[];n integer;
 eligible boolean:=false;v_delegator uuid;v_event bigint;
BEGIN
 IF actor IS NULL OR p_request IS NULL OR p_action NOT IN ('approve','reject','defer')
  OR p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{8,128}$'
 THEN RAISE EXCEPTION 'invalid_approval_command'; END IF;
 SELECT * INTO q FROM core10.approval_requests WHERE id=p_request FOR UPDATE;
 IF NOT FOUND OR q.created_by=actor THEN RAISE EXCEPTION 'approval_not_authorized'; END IF;
 IF NOT core10.can_approval_action_v1(q.tenant_id,q.business_id,'approval.decide')
 THEN RAISE EXCEPTION 'approval_not_authorized'; END IF;
 -- B-020: Owner switch checked after canonical Auth, before replay or mutation.
 PERFORM core10.control_check_v1(q.business_id,'gov002.review',NULL);
 SELECT * INTO prior FROM core10.approval_events
 WHERE request_id=p_request AND idempotency_key=p_key;
 IF FOUND THEN
  IF prior.actor_id<>actor OR prior.action<>p_action
    OR prior.tenant_id<>q.tenant_id OR prior.business_id<>q.business_id
  THEN RAISE EXCEPTION 'approval_idempotency_conflict'; END IF;
  IF NOT (core10.can_business(q.tenant_id,q.business_id) OR core10.can_tenant(q.tenant_id))
  THEN RAISE EXCEPTION 'approval_not_authorized'; END IF;
  RETURN prior.id;
 END IF;
 IF q.policy_id_v1 IS NOT NULL THEN
  IF NOT EXISTS(SELECT 1 FROM core10.approval_policy_versions_v1 pol
   WHERE pol.id=q.policy_id_v1 AND pol.tenant_id=q.tenant_id AND pol.business_id=q.business_id
    AND pol.version=q.policy_version_v1 AND pol.domain=q.domain_v1 AND pol.action_code=q.action_code_v1)
  THEN RAISE EXCEPTION 'approval_policy_pin_invalid'; END IF;
 END IF;
 SELECT stages INTO v_stages FROM core10.approval_routes_v1
 WHERE policy_id=q.policy_id_v1;
 IF v_stages IS NULL THEN
  eligible:=core10.can_manage(q.tenant_id,q.business_id);
 ELSE
  SELECT count(*)::integer+1 INTO n FROM core10.approval_stage_receipts_v1
   WHERE request_id=p_request;
  IF n>cardinality(v_stages) THEN RAISE EXCEPTION 'approval_invalid_transition'; END IF;
  IF EXISTS(SELECT 1 FROM core10.approval_stage_receipts_v1
   WHERE request_id=p_request AND actor_id=actor)
  THEN RAISE EXCEPTION 'approval_repeated_checker'; END IF;
  eligible:=core10._can_review_stage_v1(p_request,n);
  IF eligible AND n=1 AND v_stages[1]='business_owner' THEN
   SELECT d.granted_by INTO v_delegator FROM core10.approval_delegations_v1 d
   WHERE d.request_id=p_request AND d.delegated_to=actor
     AND d.revoked_at IS NULL AND d.valid_until>statement_timestamp();
  END IF;
 END IF;
 IF NOT eligible THEN RAISE EXCEPTION 'approval_not_authorized'; END IF;
 IF q.status<>'pending' THEN RAISE EXCEPTION 'approval_invalid_transition'; END IF;
 IF q.policy_id_v1 IS NOT NULL AND q.expires_at_v1<=clock_timestamp()
 THEN RAISE EXCEPTION 'approval_expired'; END IF;
 IF v_stages IS NULL OR p_action<>'approve' OR n=cardinality(v_stages) THEN
  UPDATE core10.approval_requests SET
   status=CASE p_action WHEN 'approve' THEN 'approved'
    WHEN 'reject' THEN 'rejected' ELSE 'deferred' END,
   decided_by=actor,decided_at=clock_timestamp()
  WHERE id=p_request AND status='pending';
 END IF;
 INSERT INTO core10.approval_events(request_id,tenant_id,business_id,
   actor_id,action,idempotency_key)
 VALUES(p_request,q.tenant_id,q.business_id,actor,p_action,p_key)
 RETURNING id INTO v_event;
 IF v_stages IS NOT NULL AND p_action='approve' THEN
  INSERT INTO core10.approval_stage_receipts_v1(event_id,request_id,tenant_id,business_id,
    stage_no,actor_id,delegated_by)
  VALUES(v_event,p_request,q.tenant_id,q.business_id,n,actor,v_delegator);
 END IF;
 RETURN v_event;
END $fn$;

CREATE OR REPLACE FUNCTION core10.withdraw_typed_approval_v1(
 p_request bigint,p_key text
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,core10 AS $fn$
DECLARE q core10.approval_requests%ROWTYPE;actor uuid:=core10.actor_uid();
 event_id bigint;
BEGIN
 IF actor IS NULL OR p_request IS NULL OR p_key IS NULL
  OR p_key !~ '^[A-Za-z0-9_-]{8,128}$'
 THEN RAISE EXCEPTION 'invalid_approval_withdrawal'; END IF;
 SELECT * INTO q FROM core10.approval_requests WHERE id=p_request FOR UPDATE;
 IF NOT FOUND OR q.policy_id_v1 IS NULL OR q.created_by<>actor
  OR NOT core10.can_approval_action_v1(q.tenant_id,q.business_id,'approval.withdraw')
 THEN RAISE EXCEPTION 'approval_withdraw_denied'; END IF;
 -- B-020: Owner switch checked after canonical Auth, before replay or mutation.
 PERFORM core10.control_check_v1(q.business_id,'gov002.review',NULL);
 SELECT id INTO event_id FROM core10.approval_events
 WHERE request_id=p_request AND idempotency_key=p_key AND action='withdraw' AND actor_id=actor;
 IF FOUND THEN RETURN event_id; END IF;
 IF q.status<>'pending' OR EXISTS(SELECT 1 FROM core10.approval_stage_receipts_v1
  WHERE request_id=p_request)
 THEN RAISE EXCEPTION 'withdraw_invalid_transition'; END IF;
 UPDATE core10.approval_requests SET status='withdrawn',decided_by=actor,
   decided_at=clock_timestamp() WHERE id=p_request;
 INSERT INTO core10.approval_events(request_id,tenant_id,business_id,actor_id,action,idempotency_key)
 VALUES(p_request,q.tenant_id,q.business_id,actor,'withdraw',p_key)
 RETURNING id INTO event_id;
 RETURN event_id;
END $fn$;
INSERT INTO core10.schema_migrations(version,name,checksum) VALUES(19,'0019_np01_review_control','1a5522ce289a494c9d4234ab5d6b6f0422a6a6305ce293cef382023d86e0a9e5');
