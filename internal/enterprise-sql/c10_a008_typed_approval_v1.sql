-- C10-CAP-GOV-002, C10-A008 additive typed approval slice. DISPOSABLE PG17 ONLY.
-- Depends on c10_a018_demo_backend.sql, seed, and c10_a008_atomic_approval_draft.sql.
-- No operational stock/finance/HR command is executed by this module.
-- No Supabase SG migration, GoTrue certification, live authorization or main merge implied.

CREATE TABLE c10_demo.approval_policy_versions_v1 (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_id bigint NOT NULL,
  business_id bigint NOT NULL,
  domain text NOT NULL CHECK (domain ~ '^[a-z][a-z0-9_]{1,63}$'),
  action_code text NOT NULL CHECK (action_code ~ '^[a-z][a-z0-9_]{1,63}$'),
  version integer NOT NULL CHECK (version > 0),
  ttl_minutes integer NOT NULL CHECK (ttl_minutes BETWEEN 5 AND 43200),
  effect_mode text NOT NULL DEFAULT 'NON_POSTING_REVIEW'
    CHECK (effect_mode = 'NON_POSTING_REVIEW'),
  request_key text NOT NULL CHECK (request_key ~ '^[A-Za-z0-9_-]{8,128}$'),
  created_by uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (business_id, domain, action_code, version),
  UNIQUE (business_id, request_key),
  UNIQUE (id, tenant_id, business_id),
  FOREIGN KEY (business_id, tenant_id)
    REFERENCES c10_demo.businesses(id, tenant_id)
);

ALTER TABLE c10_demo.approval_policy_versions_v1 ENABLE ROW LEVEL SECURITY;
CREATE POLICY approval_policy_owner_read_v1
  ON c10_demo.approval_policy_versions_v1 FOR SELECT TO authenticated
  USING (c10_demo.can_manage(tenant_id, business_id));
REVOKE ALL ON c10_demo.approval_policy_versions_v1 FROM PUBLIC, anon, authenticated;
GRANT SELECT ON c10_demo.approval_policy_versions_v1 TO authenticated;

-- Existing A008 request/event tables remain the one canonical demo approval journal.
-- Nullable columns preserve older A008 fixture rows until migration reconciliation.
ALTER TABLE c10_demo.approval_requests
  ADD COLUMN domain_v1 text,
  ADD COLUMN action_code_v1 text,
  ADD COLUMN source_key_v1 text,
  ADD COLUMN source_version_v1 bigint,
  ADD COLUMN payload_sha256_v1 text,
  ADD COLUMN policy_id_v1 bigint,
  ADD COLUMN policy_version_v1 integer,
  ADD COLUMN expires_at_v1 timestamptz,
  ADD COLUMN submit_key_v1 text,
  ADD CONSTRAINT approval_request_typed_contract_v1 CHECK (
    policy_id_v1 IS NULL OR (
      domain_v1 IS NOT NULL AND action_code_v1 IS NOT NULL
      AND source_version_v1 IS NOT NULL AND payload_sha256_v1 IS NOT NULL
      AND policy_version_v1 IS NOT NULL AND expires_at_v1 IS NOT NULL
      AND submit_key_v1 IS NOT NULL
      AND domain_v1 ~ '^[a-z][a-z0-9_]{1,63}      AND action_code_v1 ~ '^[a-z][a-z0-9_]{1,63}$'
      AND source_key_v1 IS NOT NULL AND length(btrim(source_key_v1)) BETWEEN 1 AND 160
      AND source_version_v1 > 0
      AND payload_sha256_v1 ~ '^[0-9a-f]{64}$'
      AND policy_version_v1 > 0
      AND expires_at_v1 > created_at
      AND submit_key_v1 ~ '^[A-Za-z0-9_-]{8,128}$'
    )
  ),
  ADD CONSTRAINT approval_request_policy_scope_v1
    FOREIGN KEY (policy_id_v1, tenant_id, business_id)
      REFERENCES c10_demo.approval_policy_versions_v1(id, tenant_id, business_id);

CREATE UNIQUE INDEX approval_typed_request_replay_v1
  ON c10_demo.approval_requests (business_id, created_by, submit_key_v1)
  WHERE submit_key_v1 IS NOT NULL;
CREATE INDEX approval_typed_inbox_v1
  ON c10_demo.approval_requests (business_id, status, expires_at_v1)
  WHERE policy_id_v1 IS NOT NULL;

-- All policies are immutable. Each publish appends a new version under a row lock.
-- This does NOT grant rights to override stock, finance or separation-of-duties rules.
CREATE FUNCTION c10_demo.publish_approval_policy_v1(
  p_business bigint, p_domain text, p_action text, p_ttl_minutes integer, p_key text
) RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path = c10_demo, pg_catalog AS $fn$
DECLARE
  v_tenant bigint;
  v_actor uuid := c10_demo.actor_uid();
  v_version integer;
  v_id bigint;
  v_old c10_demo.approval_policy_versions_v1%ROWTYPE;
BEGIN
  IF v_actor IS NULL OR p_business IS NULL
    OR p_domain IS NULL OR p_domain !~ '^[a-z][a-z0-9_]{1,63}$'
    OR p_action IS NULL OR p_action !~ '^[a-z][a-z0-9_]{1,63}$'
    OR p_ttl_minutes IS NULL OR p_ttl_minutes NOT BETWEEN 5 AND 43200
    OR p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{8,128}$'
  THEN RAISE EXCEPTION 'invalid_approval_policy'; END IF;

  -- Serialize version allocation for this business, including concurrent owners.
  SELECT tenant_id INTO v_tenant
    FROM c10_demo.businesses WHERE id = p_business FOR UPDATE;
  IF NOT FOUND OR NOT c10_demo.can_manage(v_tenant, p_business)
  THEN RAISE EXCEPTION 'approval_policy_denied'; END IF;

  SELECT * INTO v_old FROM c10_demo.approval_policy_versions_v1
    WHERE business_id = p_business AND request_key = p_key;
  IF FOUND THEN
    IF v_old.created_by <> v_actor OR v_old.domain <> p_domain
      OR v_old.action_code <> p_action OR v_old.ttl_minutes <> p_ttl_minutes
    THEN RAISE EXCEPTION 'approval_policy_replay_conflict'; END IF;
    RETURN v_old.id;
  END IF;

  SELECT COALESCE(max(version), 0) + 1 INTO v_version
    FROM c10_demo.approval_policy_versions_v1
    WHERE business_id = p_business AND domain = p_domain
      AND action_code = p_action;

  INSERT INTO c10_demo.approval_policy_versions_v1
    (tenant_id, business_id, domain, action_code, version,
     ttl_minutes, request_key, created_by)
  VALUES (v_tenant, p_business, p_domain, p_action, v_version,
          p_ttl_minutes, p_key, v_actor)
  RETURNING id INTO v_id;
  RETURN v_id;
END $fn$;

CREATE FUNCTION c10_demo.submit_typed_approval_v1(
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
    ORDER BY version DESC LIMIT 1;
  IF NOT FOUND THEN RAISE EXCEPTION 'approval_policy_missing'; END IF;

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

-- Extend the one existing A008 transition API: preserve legacy demo behavior,
-- enforce typed expiry and immutable policy pin on all new A008 requests.
CREATE OR REPLACE FUNCTION c10_demo.decide_approval(
  p_request bigint, p_action text, p_key text
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path = c10_demo, pg_catalog AS $fn$
DECLARE
  v_req c10_demo.approval_requests%ROWTYPE;
  v_actor uuid;
  v_event bigint;
  v_previous c10_demo.approval_events%ROWTYPE;
BEGIN
  v_actor := c10_demo.actor_uid();
  IF v_actor IS NULL OR p_request IS NULL
    OR p_action IS NULL OR p_action NOT IN ('approve','reject','defer')
    OR p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{8,128}$'
  THEN RAISE EXCEPTION 'invalid_approval_command'; END IF;

  SELECT * INTO v_req FROM c10_demo.approval_requests
    WHERE id = p_request FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'approval_not_authorized'; END IF;
  IF NOT c10_demo.can_manage(v_req.tenant_id, v_req.business_id)
    OR v_req.created_by = v_actor
  THEN RAISE EXCEPTION 'approval_not_authorized'; END IF;

  SELECT * INTO v_previous FROM c10_demo.approval_events
    WHERE request_id = p_request AND idempotency_key = p_key;
  IF FOUND THEN
    IF v_previous.actor_id <> v_actor OR v_previous.action <> p_action
      OR v_previous.tenant_id <> v_req.tenant_id
      OR v_previous.business_id <> v_req.business_id
    THEN RAISE EXCEPTION 'approval_idempotency_conflict'; END IF;
    RETURN v_previous.id;
  END IF;

  IF v_req.status <> 'pending' THEN RAISE EXCEPTION 'approval_invalid_transition'; END IF;
  IF v_req.policy_id_v1 IS NOT NULL THEN
    IF v_req.expires_at_v1 <= clock_timestamp()
    THEN RAISE EXCEPTION 'approval_expired'; END IF;
    IF NOT EXISTS (
      SELECT 1 FROM c10_demo.approval_policy_versions_v1 p
      WHERE p.id = v_req.policy_id_v1 AND p.tenant_id = v_req.tenant_id
        AND p.business_id = v_req.business_id
        AND p.version = v_req.policy_version_v1
        AND p.domain = v_req.domain_v1 AND p.action_code = v_req.action_code_v1
    ) THEN RAISE EXCEPTION 'approval_policy_pin_invalid'; END IF;
  END IF;

  UPDATE c10_demo.approval_requests SET
    status = CASE p_action WHEN 'approve' THEN 'approved'
                           WHEN 'reject' THEN 'rejected' ELSE 'deferred' END,
    decided_by = v_actor, decided_at = clock_timestamp()
  WHERE id = p_request AND status = 'pending';
  IF NOT FOUND THEN RAISE EXCEPTION 'approval_invalid_transition'; END IF;

  INSERT INTO c10_demo.approval_events
    (request_id, tenant_id, business_id, actor_id, action, idempotency_key)
  VALUES (p_request, v_req.tenant_id, v_req.business_id, v_actor, p_action, p_key)
  RETURNING id INTO v_event;
  RETURN v_event;
END $fn$;

-- This is a NON-POSTING service-only binding check, not an execution receipt.
-- A future certified typed domain handler must re-read its live source inside
-- the same transaction, invoke this check, and enforce its own posting invariants.
CREATE FUNCTION c10_demo.verify_approval_binding_v1(
  p_request bigint, p_business bigint, p_domain text, p_action text,
  p_source_key text, p_source_version bigint, p_payload jsonb
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path = c10_demo, pg_catalog AS $fn$
DECLARE
  v_req c10_demo.approval_requests%ROWTYPE;
  v_event bigint;
BEGIN
  SELECT * INTO v_req FROM c10_demo.approval_requests WHERE id = p_request;
  IF NOT FOUND OR v_req.policy_id_v1 IS NULL OR v_req.status <> 'approved'
    OR v_req.expires_at_v1 <= clock_timestamp()
  THEN RAISE EXCEPTION 'approval_not_effective'; END IF;

  IF p_payload IS NULL OR jsonb_typeof(p_payload) <> 'object'
    OR v_req.business_id IS DISTINCT FROM p_business
    OR v_req.domain_v1 IS DISTINCT FROM p_domain
    OR v_req.action_code_v1 IS DISTINCT FROM p_action
    OR v_req.source_key_v1 IS DISTINCT FROM p_source_key
    OR v_req.source_version_v1 IS DISTINCT FROM p_source_version
    OR v_req.payload_sha256_v1 IS DISTINCT FROM
       encode(sha256(convert_to(p_payload::text, 'UTF8')), 'hex')
  THEN RAISE EXCEPTION 'approval_stale_or_payload_changed'; END IF;

  SELECT id INTO v_event FROM c10_demo.approval_events
    WHERE request_id = p_request AND action = 'approve';
  IF NOT FOUND THEN RAISE EXCEPTION 'approval_receipt_missing'; END IF;
  RETURN v_event;
END $fn$;

REVOKE ALL ON FUNCTION c10_demo.publish_approval_policy_v1(bigint,text,text,integer,text)
  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION c10_demo.submit_typed_approval_v1(bigint,text,text,text,bigint,jsonb,text)
  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION c10_demo.verify_approval_binding_v1(bigint,bigint,text,text,text,bigint,jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION c10_demo.publish_approval_policy_v1(bigint,text,text,integer,text)
  TO authenticated;
GRANT EXECUTE ON FUNCTION c10_demo.submit_typed_approval_v1(bigint,text,text,text,bigint,jsonb,text)
  TO authenticated;
GRANT USAGE ON SCHEMA c10_demo TO service_role;
GRANT EXECUTE ON FUNCTION c10_demo.verify_approval_binding_v1(bigint,bigint,text,text,text,bigint,jsonb)
  TO service_role;
-- The pre-existing A008 decide_approval grant stays authenticated.
-- Before any real release: reconcile A021/A034, signed GoTrue, live source version
-- checks, multi-stage/delegation/withdrawal/reversal and migration drift.

      AND action_code_v1 ~ '^[a-z][a-z0-9_]{1,63}$'
      AND source_key_v1 IS NOT NULL AND length(btrim(source_key_v1)) BETWEEN 1 AND 160
      AND source_version_v1 > 0
      AND payload_sha256_v1 ~ '^[0-9a-f]{64}$'
      AND policy_version_v1 > 0
      AND expires_at_v1 > created_at
      AND submit_key_v1 ~ '^[A-Za-z0-9_-]{8,128}$'
    )
  ),
  ADD CONSTRAINT approval_request_policy_scope_v1
    FOREIGN KEY (policy_id_v1, tenant_id, business_id)
      REFERENCES c10_demo.approval_policy_versions_v1(id, tenant_id, business_id);

CREATE UNIQUE INDEX approval_typed_request_replay_v1
  ON c10_demo.approval_requests (business_id, created_by, submit_key_v1)
  WHERE submit_key_v1 IS NOT NULL;
CREATE INDEX approval_typed_inbox_v1
  ON c10_demo.approval_requests (business_id, status, expires_at_v1)
  WHERE policy_id_v1 IS NOT NULL;

-- All policies are immutable. Each publish appends a new version under a row lock.
-- This does NOT grant rights to override stock, finance or separation-of-duties rules.
CREATE FUNCTION c10_demo.publish_approval_policy_v1(
  p_business bigint, p_domain text, p_action text, p_ttl_minutes integer, p_key text
) RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path = c10_demo, pg_catalog AS $fn$
DECLARE
  v_tenant bigint;
  v_actor uuid := c10_demo.actor_uid();
  v_version integer;
  v_id bigint;
  v_old c10_demo.approval_policy_versions_v1%ROWTYPE;
BEGIN
  IF v_actor IS NULL OR p_business IS NULL
    OR p_domain IS NULL OR p_domain !~ '^[a-z][a-z0-9_]{1,63}$'
    OR p_action IS NULL OR p_action !~ '^[a-z][a-z0-9_]{1,63}$'
    OR p_ttl_minutes IS NULL OR p_ttl_minutes NOT BETWEEN 5 AND 43200
    OR p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{8,128}$'
  THEN RAISE EXCEPTION 'invalid_approval_policy'; END IF;

  -- Serialize version allocation for this business, including concurrent owners.
  SELECT tenant_id INTO v_tenant
    FROM c10_demo.businesses WHERE id = p_business FOR UPDATE;
  IF NOT FOUND OR NOT c10_demo.can_manage(v_tenant, p_business)
  THEN RAISE EXCEPTION 'approval_policy_denied'; END IF;

  SELECT * INTO v_old FROM c10_demo.approval_policy_versions_v1
    WHERE business_id = p_business AND request_key = p_key;
  IF FOUND THEN
    IF v_old.created_by <> v_actor OR v_old.domain <> p_domain
      OR v_old.action_code <> p_action OR v_old.ttl_minutes <> p_ttl_minutes
    THEN RAISE EXCEPTION 'approval_policy_replay_conflict'; END IF;
    RETURN v_old.id;
  END IF;

  SELECT COALESCE(max(version), 0) + 1 INTO v_version
    FROM c10_demo.approval_policy_versions_v1
    WHERE business_id = p_business AND domain = p_domain
      AND action_code = p_action;

  INSERT INTO c10_demo.approval_policy_versions_v1
    (tenant_id, business_id, domain, action_code, version,
     ttl_minutes, request_key, created_by)
  VALUES (v_tenant, p_business, p_domain, p_action, v_version,
          p_ttl_minutes, p_key, v_actor)
  RETURNING id INTO v_id;
  RETURN v_id;
END $fn$;

CREATE FUNCTION c10_demo.submit_typed_approval_v1(
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
    ORDER BY version DESC LIMIT 1;
  IF NOT FOUND THEN RAISE EXCEPTION 'approval_policy_missing'; END IF;

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

-- Extend the one existing A008 transition API: preserve legacy demo behavior,
-- enforce typed expiry and immutable policy pin on all new A008 requests.
CREATE OR REPLACE FUNCTION c10_demo.decide_approval(
  p_request bigint, p_action text, p_key text
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path = c10_demo, pg_catalog AS $fn$
DECLARE
  v_req c10_demo.approval_requests%ROWTYPE;
  v_actor uuid;
  v_event bigint;
  v_previous c10_demo.approval_events%ROWTYPE;
BEGIN
  v_actor := c10_demo.actor_uid();
  IF v_actor IS NULL OR p_request IS NULL
    OR p_action IS NULL OR p_action NOT IN ('approve','reject','defer')
    OR p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{8,128}$'
  THEN RAISE EXCEPTION 'invalid_approval_command'; END IF;

  SELECT * INTO v_req FROM c10_demo.approval_requests
    WHERE id = p_request FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'approval_not_authorized'; END IF;
  IF NOT c10_demo.can_manage(v_req.tenant_id, v_req.business_id)
    OR v_req.created_by = v_actor
  THEN RAISE EXCEPTION 'approval_not_authorized'; END IF;

  SELECT * INTO v_previous FROM c10_demo.approval_events
    WHERE request_id = p_request AND idempotency_key = p_key;
  IF FOUND THEN
    IF v_previous.actor_id <> v_actor OR v_previous.action <> p_action
      OR v_previous.tenant_id <> v_req.tenant_id
      OR v_previous.business_id <> v_req.business_id
    THEN RAISE EXCEPTION 'approval_idempotency_conflict'; END IF;
    RETURN v_previous.id;
  END IF;

  IF v_req.status <> 'pending' THEN RAISE EXCEPTION 'approval_invalid_transition'; END IF;
  IF v_req.policy_id_v1 IS NOT NULL THEN
    IF v_req.expires_at_v1 <= clock_timestamp()
    THEN RAISE EXCEPTION 'approval_expired'; END IF;
    IF NOT EXISTS (
      SELECT 1 FROM c10_demo.approval_policy_versions_v1 p
      WHERE p.id = v_req.policy_id_v1 AND p.tenant_id = v_req.tenant_id
        AND p.business_id = v_req.business_id
        AND p.version = v_req.policy_version_v1
        AND p.domain = v_req.domain_v1 AND p.action_code = v_req.action_code_v1
    ) THEN RAISE EXCEPTION 'approval_policy_pin_invalid'; END IF;
  END IF;

  UPDATE c10_demo.approval_requests SET
    status = CASE p_action WHEN 'approve' THEN 'approved'
                           WHEN 'reject' THEN 'rejected' ELSE 'deferred' END,
    decided_by = v_actor, decided_at = clock_timestamp()
  WHERE id = p_request AND status = 'pending';
  IF NOT FOUND THEN RAISE EXCEPTION 'approval_invalid_transition'; END IF;

  INSERT INTO c10_demo.approval_events
    (request_id, tenant_id, business_id, actor_id, action, idempotency_key)
  VALUES (p_request, v_req.tenant_id, v_req.business_id, v_actor, p_action, p_key)
  RETURNING id INTO v_event;
  RETURN v_event;
END $fn$;

-- This is a NON-POSTING service-only binding check, not an execution receipt.
-- A future certified typed domain handler must re-read its live source inside
-- the same transaction, invoke this check, and enforce its own posting invariants.
CREATE FUNCTION c10_demo.verify_approval_binding_v1(
  p_request bigint, p_business bigint, p_domain text, p_action text,
  p_source_key text, p_source_version bigint, p_payload jsonb
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path = c10_demo, pg_catalog AS $fn$
DECLARE
  v_req c10_demo.approval_requests%ROWTYPE;
  v_event bigint;
BEGIN
  SELECT * INTO v_req FROM c10_demo.approval_requests WHERE id = p_request;
  IF NOT FOUND OR v_req.policy_id_v1 IS NULL OR v_req.status <> 'approved'
    OR v_req.expires_at_v1 <= clock_timestamp()
  THEN RAISE EXCEPTION 'approval_not_effective'; END IF;

  IF p_payload IS NULL OR jsonb_typeof(p_payload) <> 'object'
    OR v_req.business_id IS DISTINCT FROM p_business
    OR v_req.domain_v1 IS DISTINCT FROM p_domain
    OR v_req.action_code_v1 IS DISTINCT FROM p_action
    OR v_req.source_key_v1 IS DISTINCT FROM p_source_key
    OR v_req.source_version_v1 IS DISTINCT FROM p_source_version
    OR v_req.payload_sha256_v1 IS DISTINCT FROM
       encode(sha256(convert_to(p_payload::text, 'UTF8')), 'hex')
  THEN RAISE EXCEPTION 'approval_stale_or_payload_changed'; END IF;

  SELECT id INTO v_event FROM c10_demo.approval_events
    WHERE request_id = p_request AND action = 'approve';
  IF NOT FOUND THEN RAISE EXCEPTION 'approval_receipt_missing'; END IF;
  RETURN v_event;
END $fn$;

REVOKE ALL ON FUNCTION c10_demo.publish_approval_policy_v1(bigint,text,text,integer,text)
  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION c10_demo.submit_typed_approval_v1(bigint,text,text,text,bigint,jsonb,text)
  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION c10_demo.verify_approval_binding_v1(bigint,bigint,text,text,text,bigint,jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION c10_demo.publish_approval_policy_v1(bigint,text,text,integer,text)
  TO authenticated;
GRANT EXECUTE ON FUNCTION c10_demo.submit_typed_approval_v1(bigint,text,text,text,bigint,jsonb,text)
  TO authenticated;
GRANT USAGE ON SCHEMA c10_demo TO service_role;
GRANT EXECUTE ON FUNCTION c10_demo.verify_approval_binding_v1(bigint,bigint,text,text,text,bigint,jsonb)
  TO service_role;
-- The pre-existing A008 decide_approval grant stays authenticated.
-- Before any real release: reconcile A021/A034, signed GoTrue, live source version
-- checks, multi-stage/delegation/withdrawal/reversal and migration drift.

      AND action_code_v1 ~ '^[a-z][a-z0-9_]{1,63}$'
      AND source_key_v1 IS NOT NULL AND length(btrim(source_key_v1)) BETWEEN 1 AND 160
      AND source_version_v1 > 0
      AND payload_sha256_v1 ~ '^[0-9a-f]{64}$'
      AND policy_version_v1 > 0
      AND expires_at_v1 > created_at
      AND submit_key_v1 ~ '^[A-Za-z0-9_-]{8,128}$'
    )
  ),
  ADD CONSTRAINT approval_request_policy_scope_v1
    FOREIGN KEY (policy_id_v1, tenant_id, business_id)
      REFERENCES c10_demo.approval_policy_versions_v1(id, tenant_id, business_id);

CREATE UNIQUE INDEX approval_typed_request_replay_v1
  ON c10_demo.approval_requests (business_id, created_by, submit_key_v1)
  WHERE submit_key_v1 IS NOT NULL;
CREATE INDEX approval_typed_inbox_v1
  ON c10_demo.approval_requests (business_id, status, expires_at_v1)
  WHERE policy_id_v1 IS NOT NULL;

-- All policies are immutable. Each publish appends a new version under a row lock.
-- This does NOT grant rights to override stock, finance or separation-of-duties rules.
CREATE FUNCTION c10_demo.publish_approval_policy_v1(
  p_business bigint, p_domain text, p_action text, p_ttl_minutes integer, p_key text
) RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path = c10_demo, pg_catalog AS $fn$
DECLARE
  v_tenant bigint;
  v_actor uuid := c10_demo.actor_uid();
  v_version integer;
  v_id bigint;
  v_old c10_demo.approval_policy_versions_v1%ROWTYPE;
BEGIN
  IF v_actor IS NULL OR p_business IS NULL
    OR p_domain IS NULL OR p_domain !~ '^[a-z][a-z0-9_]{1,63}$'
    OR p_action IS NULL OR p_action !~ '^[a-z][a-z0-9_]{1,63}$'
    OR p_ttl_minutes IS NULL OR p_ttl_minutes NOT BETWEEN 5 AND 43200
    OR p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{8,128}$'
  THEN RAISE EXCEPTION 'invalid_approval_policy'; END IF;

  -- Serialize version allocation for this business, including concurrent owners.
  SELECT tenant_id INTO v_tenant
    FROM c10_demo.businesses WHERE id = p_business FOR UPDATE;
  IF NOT FOUND OR NOT c10_demo.can_manage(v_tenant, p_business)
  THEN RAISE EXCEPTION 'approval_policy_denied'; END IF;

  SELECT * INTO v_old FROM c10_demo.approval_policy_versions_v1
    WHERE business_id = p_business AND request_key = p_key;
  IF FOUND THEN
    IF v_old.created_by <> v_actor OR v_old.domain <> p_domain
      OR v_old.action_code <> p_action OR v_old.ttl_minutes <> p_ttl_minutes
    THEN RAISE EXCEPTION 'approval_policy_replay_conflict'; END IF;
    RETURN v_old.id;
  END IF;

  SELECT COALESCE(max(version), 0) + 1 INTO v_version
    FROM c10_demo.approval_policy_versions_v1
    WHERE business_id = p_business AND domain = p_domain
      AND action_code = p_action;

  INSERT INTO c10_demo.approval_policy_versions_v1
    (tenant_id, business_id, domain, action_code, version,
     ttl_minutes, request_key, created_by)
  VALUES (v_tenant, p_business, p_domain, p_action, v_version,
          p_ttl_minutes, p_key, v_actor)
  RETURNING id INTO v_id;
  RETURN v_id;
END $fn$;

CREATE FUNCTION c10_demo.submit_typed_approval_v1(
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
    ORDER BY version DESC LIMIT 1;
  IF NOT FOUND THEN RAISE EXCEPTION 'approval_policy_missing'; END IF;

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

-- Extend the one existing A008 transition API: preserve legacy demo behavior,
-- enforce typed expiry and immutable policy pin on all new A008 requests.
CREATE OR REPLACE FUNCTION c10_demo.decide_approval(
  p_request bigint, p_action text, p_key text
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path = c10_demo, pg_catalog AS $fn$
DECLARE
  v_req c10_demo.approval_requests%ROWTYPE;
  v_actor uuid;
  v_event bigint;
  v_previous c10_demo.approval_events%ROWTYPE;
BEGIN
  v_actor := c10_demo.actor_uid();
  IF v_actor IS NULL OR p_request IS NULL
    OR p_action IS NULL OR p_action NOT IN ('approve','reject','defer')
    OR p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{8,128}$'
  THEN RAISE EXCEPTION 'invalid_approval_command'; END IF;

  SELECT * INTO v_req FROM c10_demo.approval_requests
    WHERE id = p_request FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'approval_not_authorized'; END IF;
  IF NOT c10_demo.can_manage(v_req.tenant_id, v_req.business_id)
    OR v_req.created_by = v_actor
  THEN RAISE EXCEPTION 'approval_not_authorized'; END IF;

  SELECT * INTO v_previous FROM c10_demo.approval_events
    WHERE request_id = p_request AND idempotency_key = p_key;
  IF FOUND THEN
    IF v_previous.actor_id <> v_actor OR v_previous.action <> p_action
      OR v_previous.tenant_id <> v_req.tenant_id
      OR v_previous.business_id <> v_req.business_id
    THEN RAISE EXCEPTION 'approval_idempotency_conflict'; END IF;
    RETURN v_previous.id;
  END IF;

  IF v_req.status <> 'pending' THEN RAISE EXCEPTION 'approval_invalid_transition'; END IF;
  IF v_req.policy_id_v1 IS NOT NULL THEN
    IF v_req.expires_at_v1 <= clock_timestamp()
    THEN RAISE EXCEPTION 'approval_expired'; END IF;
    IF NOT EXISTS (
      SELECT 1 FROM c10_demo.approval_policy_versions_v1 p
      WHERE p.id = v_req.policy_id_v1 AND p.tenant_id = v_req.tenant_id
        AND p.business_id = v_req.business_id
        AND p.version = v_req.policy_version_v1
        AND p.domain = v_req.domain_v1 AND p.action_code = v_req.action_code_v1
    ) THEN RAISE EXCEPTION 'approval_policy_pin_invalid'; END IF;
  END IF;

  UPDATE c10_demo.approval_requests SET
    status = CASE p_action WHEN 'approve' THEN 'approved'
                           WHEN 'reject' THEN 'rejected' ELSE 'deferred' END,
    decided_by = v_actor, decided_at = clock_timestamp()
  WHERE id = p_request AND status = 'pending';
  IF NOT FOUND THEN RAISE EXCEPTION 'approval_invalid_transition'; END IF;

  INSERT INTO c10_demo.approval_events
    (request_id, tenant_id, business_id, actor_id, action, idempotency_key)
  VALUES (p_request, v_req.tenant_id, v_req.business_id, v_actor, p_action, p_key)
  RETURNING id INTO v_event;
  RETURN v_event;
END $fn$;

-- This is a NON-POSTING service-only binding check, not an execution receipt.
-- A future certified typed domain handler must re-read its live source inside
-- the same transaction, invoke this check, and enforce its own posting invariants.
CREATE FUNCTION c10_demo.verify_approval_binding_v1(
  p_request bigint, p_business bigint, p_domain text, p_action text,
  p_source_key text, p_source_version bigint, p_payload jsonb
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path = c10_demo, pg_catalog AS $fn$
DECLARE
  v_req c10_demo.approval_requests%ROWTYPE;
  v_event bigint;
BEGIN
  SELECT * INTO v_req FROM c10_demo.approval_requests WHERE id = p_request;
  IF NOT FOUND OR v_req.policy_id_v1 IS NULL OR v_req.status <> 'approved'
    OR v_req.expires_at_v1 <= clock_timestamp()
  THEN RAISE EXCEPTION 'approval_not_effective'; END IF;

  IF p_payload IS NULL OR jsonb_typeof(p_payload) <> 'object'
    OR v_req.business_id IS DISTINCT FROM p_business
    OR v_req.domain_v1 IS DISTINCT FROM p_domain
    OR v_req.action_code_v1 IS DISTINCT FROM p_action
    OR v_req.source_key_v1 IS DISTINCT FROM p_source_key
    OR v_req.source_version_v1 IS DISTINCT FROM p_source_version
    OR v_req.payload_sha256_v1 IS DISTINCT FROM
       encode(sha256(convert_to(p_payload::text, 'UTF8')), 'hex')
  THEN RAISE EXCEPTION 'approval_stale_or_payload_changed'; END IF;

  SELECT id INTO v_event FROM c10_demo.approval_events
    WHERE request_id = p_request AND action = 'approve';
  IF NOT FOUND THEN RAISE EXCEPTION 'approval_receipt_missing'; END IF;
  RETURN v_event;
END $fn$;

REVOKE ALL ON FUNCTION c10_demo.publish_approval_policy_v1(bigint,text,text,integer,text)
  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION c10_demo.submit_typed_approval_v1(bigint,text,text,text,bigint,jsonb,text)
  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION c10_demo.verify_approval_binding_v1(bigint,bigint,text,text,text,bigint,jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION c10_demo.publish_approval_policy_v1(bigint,text,text,integer,text)
  TO authenticated;
GRANT EXECUTE ON FUNCTION c10_demo.submit_typed_approval_v1(bigint,text,text,text,bigint,jsonb,text)
  TO authenticated;
GRANT USAGE ON SCHEMA c10_demo TO service_role;
GRANT EXECUTE ON FUNCTION c10_demo.verify_approval_binding_v1(bigint,bigint,text,text,text,bigint,jsonb)
  TO service_role;
-- The pre-existing A008 decide_approval grant stays authenticated.
-- Before any real release: reconcile A021/A034, signed GoTrue, live source version
-- checks, multi-stage/delegation/withdrawal/reversal and migration drift.

      AND action_code_v1 ~ '^[a-z][a-z0-9_]{1,63}$'
      AND source_key_v1 IS NOT NULL AND length(btrim(source_key_v1)) BETWEEN 1 AND 160
      AND source_version_v1 > 0
      AND payload_sha256_v1 ~ '^[0-9a-f]{64}$'
      AND policy_version_v1 > 0
      AND expires_at_v1 > created_at
      AND submit_key_v1 ~ '^[A-Za-z0-9_-]{8,128}$'
    )
  ),
  ADD CONSTRAINT approval_request_policy_scope_v1
    FOREIGN KEY (policy_id_v1, tenant_id, business_id)
      REFERENCES c10_demo.approval_policy_versions_v1(id, tenant_id, business_id);

CREATE UNIQUE INDEX approval_typed_request_replay_v1
  ON c10_demo.approval_requests (business_id, created_by, submit_key_v1)
  WHERE submit_key_v1 IS NOT NULL;
CREATE INDEX approval_typed_inbox_v1
  ON c10_demo.approval_requests (business_id, status, expires_at_v1)
  WHERE policy_id_v1 IS NOT NULL;

-- All policies are immutable. Each publish appends a new version under a row lock.
-- This does NOT grant rights to override stock, finance or separation-of-duties rules.
CREATE FUNCTION c10_demo.publish_approval_policy_v1(
  p_business bigint, p_domain text, p_action text, p_ttl_minutes integer, p_key text
) RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path = c10_demo, pg_catalog AS $fn$
DECLARE
  v_tenant bigint;
  v_actor uuid := c10_demo.actor_uid();
  v_version integer;
  v_id bigint;
  v_old c10_demo.approval_policy_versions_v1%ROWTYPE;
BEGIN
  IF v_actor IS NULL OR p_business IS NULL
    OR p_domain IS NULL OR p_domain !~ '^[a-z][a-z0-9_]{1,63}$'
    OR p_action IS NULL OR p_action !~ '^[a-z][a-z0-9_]{1,63}$'
    OR p_ttl_minutes IS NULL OR p_ttl_minutes NOT BETWEEN 5 AND 43200
    OR p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{8,128}$'
  THEN RAISE EXCEPTION 'invalid_approval_policy'; END IF;

  -- Serialize version allocation for this business, including concurrent owners.
  SELECT tenant_id INTO v_tenant
    FROM c10_demo.businesses WHERE id = p_business FOR UPDATE;
  IF NOT FOUND OR NOT c10_demo.can_manage(v_tenant, p_business)
  THEN RAISE EXCEPTION 'approval_policy_denied'; END IF;

  SELECT * INTO v_old FROM c10_demo.approval_policy_versions_v1
    WHERE business_id = p_business AND request_key = p_key;
  IF FOUND THEN
    IF v_old.created_by <> v_actor OR v_old.domain <> p_domain
      OR v_old.action_code <> p_action OR v_old.ttl_minutes <> p_ttl_minutes
    THEN RAISE EXCEPTION 'approval_policy_replay_conflict'; END IF;
    RETURN v_old.id;
  END IF;

  SELECT COALESCE(max(version), 0) + 1 INTO v_version
    FROM c10_demo.approval_policy_versions_v1
    WHERE business_id = p_business AND domain = p_domain
      AND action_code = p_action;

  INSERT INTO c10_demo.approval_policy_versions_v1
    (tenant_id, business_id, domain, action_code, version,
     ttl_minutes, request_key, created_by)
  VALUES (v_tenant, p_business, p_domain, p_action, v_version,
          p_ttl_minutes, p_key, v_actor)
  RETURNING id INTO v_id;
  RETURN v_id;
END $fn$;

CREATE FUNCTION c10_demo.submit_typed_approval_v1(
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
    ORDER BY version DESC LIMIT 1;
  IF NOT FOUND THEN RAISE EXCEPTION 'approval_policy_missing'; END IF;

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

-- Extend the one existing A008 transition API: preserve legacy demo behavior,
-- enforce typed expiry and immutable policy pin on all new A008 requests.
CREATE OR REPLACE FUNCTION c10_demo.decide_approval(
  p_request bigint, p_action text, p_key text
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path = c10_demo, pg_catalog AS $fn$
DECLARE
  v_req c10_demo.approval_requests%ROWTYPE;
  v_actor uuid;
  v_event bigint;
  v_previous c10_demo.approval_events%ROWTYPE;
BEGIN
  v_actor := c10_demo.actor_uid();
  IF v_actor IS NULL OR p_request IS NULL
    OR p_action IS NULL OR p_action NOT IN ('approve','reject','defer')
    OR p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{8,128}$'
  THEN RAISE EXCEPTION 'invalid_approval_command'; END IF;

  SELECT * INTO v_req FROM c10_demo.approval_requests
    WHERE id = p_request FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'approval_not_authorized'; END IF;
  IF NOT c10_demo.can_manage(v_req.tenant_id, v_req.business_id)
    OR v_req.created_by = v_actor
  THEN RAISE EXCEPTION 'approval_not_authorized'; END IF;

  SELECT * INTO v_previous FROM c10_demo.approval_events
    WHERE request_id = p_request AND idempotency_key = p_key;
  IF FOUND THEN
    IF v_previous.actor_id <> v_actor OR v_previous.action <> p_action
      OR v_previous.tenant_id <> v_req.tenant_id
      OR v_previous.business_id <> v_req.business_id
    THEN RAISE EXCEPTION 'approval_idempotency_conflict'; END IF;
    RETURN v_previous.id;
  END IF;

  IF v_req.status <> 'pending' THEN RAISE EXCEPTION 'approval_invalid_transition'; END IF;
  IF v_req.policy_id_v1 IS NOT NULL THEN
    IF v_req.expires_at_v1 <= clock_timestamp()
    THEN RAISE EXCEPTION 'approval_expired'; END IF;
    IF NOT EXISTS (
      SELECT 1 FROM c10_demo.approval_policy_versions_v1 p
      WHERE p.id = v_req.policy_id_v1 AND p.tenant_id = v_req.tenant_id
        AND p.business_id = v_req.business_id
        AND p.version = v_req.policy_version_v1
        AND p.domain = v_req.domain_v1 AND p.action_code = v_req.action_code_v1
    ) THEN RAISE EXCEPTION 'approval_policy_pin_invalid'; END IF;
  END IF;

  UPDATE c10_demo.approval_requests SET
    status = CASE p_action WHEN 'approve' THEN 'approved'
                           WHEN 'reject' THEN 'rejected' ELSE 'deferred' END,
    decided_by = v_actor, decided_at = clock_timestamp()
  WHERE id = p_request AND status = 'pending';
  IF NOT FOUND THEN RAISE EXCEPTION 'approval_invalid_transition'; END IF;

  INSERT INTO c10_demo.approval_events
    (request_id, tenant_id, business_id, actor_id, action, idempotency_key)
  VALUES (p_request, v_req.tenant_id, v_req.business_id, v_actor, p_action, p_key)
  RETURNING id INTO v_event;
  RETURN v_event;
END $fn$;

-- This is a NON-POSTING service-only binding check, not an execution receipt.
-- A future certified typed domain handler must re-read its live source inside
-- the same transaction, invoke this check, and enforce its own posting invariants.
CREATE FUNCTION c10_demo.verify_approval_binding_v1(
  p_request bigint, p_business bigint, p_domain text, p_action text,
  p_source_key text, p_source_version bigint, p_payload jsonb
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path = c10_demo, pg_catalog AS $fn$
DECLARE
  v_req c10_demo.approval_requests%ROWTYPE;
  v_event bigint;
BEGIN
  SELECT * INTO v_req FROM c10_demo.approval_requests WHERE id = p_request;
  IF NOT FOUND OR v_req.policy_id_v1 IS NULL OR v_req.status <> 'approved'
    OR v_req.expires_at_v1 <= clock_timestamp()
  THEN RAISE EXCEPTION 'approval_not_effective'; END IF;

  IF p_payload IS NULL OR jsonb_typeof(p_payload) <> 'object'
    OR v_req.business_id IS DISTINCT FROM p_business
    OR v_req.domain_v1 IS DISTINCT FROM p_domain
    OR v_req.action_code_v1 IS DISTINCT FROM p_action
    OR v_req.source_key_v1 IS DISTINCT FROM p_source_key
    OR v_req.source_version_v1 IS DISTINCT FROM p_source_version
    OR v_req.payload_sha256_v1 IS DISTINCT FROM
       encode(sha256(convert_to(p_payload::text, 'UTF8')), 'hex')
  THEN RAISE EXCEPTION 'approval_stale_or_payload_changed'; END IF;

  SELECT id INTO v_event FROM c10_demo.approval_events
    WHERE request_id = p_request AND action = 'approve';
  IF NOT FOUND THEN RAISE EXCEPTION 'approval_receipt_missing'; END IF;
  RETURN v_event;
END $fn$;

REVOKE ALL ON FUNCTION c10_demo.publish_approval_policy_v1(bigint,text,text,integer,text)
  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION c10_demo.submit_typed_approval_v1(bigint,text,text,text,bigint,jsonb,text)
  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION c10_demo.verify_approval_binding_v1(bigint,bigint,text,text,text,bigint,jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION c10_demo.publish_approval_policy_v1(bigint,text,text,integer,text)
  TO authenticated;
GRANT EXECUTE ON FUNCTION c10_demo.submit_typed_approval_v1(bigint,text,text,text,bigint,jsonb,text)
  TO authenticated;
GRANT USAGE ON SCHEMA c10_demo TO service_role;
GRANT EXECUTE ON FUNCTION c10_demo.verify_approval_binding_v1(bigint,bigint,text,text,text,bigint,jsonb)
  TO service_role;
-- The pre-existing A008 decide_approval grant stays authenticated.
-- Before any real release: reconcile A021/A034, signed GoTrue, live source version
-- checks, multi-stage/delegation/withdrawal/reversal and migration drift.
