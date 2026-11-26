\set ON_ERROR_STOP on
BEGIN;

INSERT INTO core10.tenants (id, slug) VALUES
 (9611, 'bootstrap-new-a'), (9612, 'bootstrap-new-b'), (9613, 'bootstrap-revoked');
INSERT INTO core10.tenants (id, slug, bootstrap_policy_initialized)
 VALUES (9614, 'bootstrap-legacy', false);
INSERT INTO core10.tenant_members (tenant_id, user_id, role, active) VALUES
 (9611, '00009611-0000-4000-8000-000000000001', 'tenant_owner', true),
 (9612, '00009612-0000-4000-8000-000000000001', 'tenant_owner', true),
 (9613, '00009613-0000-4000-8000-000000000001', 'tenant_owner', false),
 (9614, '00009611-0000-4000-8000-000000000001', 'tenant_owner', true);
INSERT INTO core10.legal_entities (id, tenant_id, label)
 VALUES (9611, 9611, 'Fixture legal entity');
INSERT INTO core10.businesses (id, tenant_id, legal_entity_id, slug, template_code, request_key)
 VALUES (9611, 9611, 9611, 'bootstrap-business', 'sweets_bakery', 'bootstrap-business');
INSERT INTO core10.business_members (business_id, tenant_id, user_id, role)
 VALUES (9611, 9611, '00009611-0000-4000-8000-000000000002', 'business_owner');

DO $test$
DECLARE
 result jsonb;
 audit_id bigint;
 scheduled_at timestamptz;
BEGIN
 -- The public role cannot invoke any of the private provider helpers.
 IF EXISTS (SELECT 1 FROM pg_proc p
  WHERE p.pronamespace = 'core10'::regnamespace
   AND p.proname IN ('_lock_bootstrap_policy_v1', '_append_bootstrap_audit_v1',
                     '_bootstrap_policy_decision_v1', '_set_bootstrap_policy_v1')
   AND (has_function_privilege('authenticated', p.oid, 'execute')
        OR has_function_privilege('public', p.oid, 'execute'))) THEN
  RAISE EXCEPTION 'bootstrap provider API leak';
 END IF;

 PERFORM set_config('request.jwt.claims', '{"sub":"00009611-0000-4000-8000-000000000001"}', true);
 result := core10._bootstrap_policy_decision_v1(9611);
 IF result->>'enabled' IS DISTINCT FROM 'false' OR result->>'version' IS DISTINCT FROM '0' THEN
  RAISE EXCEPTION 'new tenant must default OFF: %', result;
 END IF;
 BEGIN
  PERFORM core10._bootstrap_policy_decision_v1(9614);
  RAISE EXCEPTION 'legacy tenant accepted without backfill';
 EXCEPTION WHEN insufficient_privilege THEN
  IF SQLERRM <> 'BOOTSTRAP_POLICY_UNINITIALIZED' THEN RAISE; END IF;
 END;

 -- 9612 genuinely has no Business. A signed owner can persist the policy
 -- via the private provider before a Business-based audit chain exists.
 PERFORM set_config('request.jwt.claims', '{"sub":"00009612-0000-4000-8000-000000000001"}', true);
 result := core10._bootstrap_policy_decision_v1(9612);
 IF result->>'enabled' IS DISTINCT FROM 'false' THEN RAISE EXCEPTION 'default OFF missing'; END IF;
 result := core10._set_bootstrap_policy_v1(9612, true, NULL, 0, 'Enable fixture tenant', 'bootstrap-on');
 audit_id := (result->>'audit_event_id')::bigint;
 IF result->>'version' IS DISTINCT FROM '1' OR audit_id IS NULL OR EXISTS (
  SELECT 1 FROM core10.businesses WHERE tenant_id = 9612
 ) THEN RAISE EXCEPTION 'zero-Business policy failed: %', result; END IF;
 result := core10._set_bootstrap_policy_v1(9612, true, NULL, 0, 'Enable fixture tenant', 'bootstrap-on');
 IF result->>'replayed' IS DISTINCT FROM 'true' OR (result->>'audit_event_id')::bigint <> audit_id THEN
  RAISE EXCEPTION 'idempotency receipt drift';
 END IF;
 BEGIN
  PERFORM core10._set_bootstrap_policy_v1(9612, false, NULL, 0, 'Changed replay', 'bootstrap-on');
  RAISE EXCEPTION 'changed retry accepted';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM <> 'CONTROL_REPLAY_CONFLICT' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM core10._set_bootstrap_policy_v1(9612, false, NULL, 0, 'Stale version', 'bootstrap-stale');
  RAISE EXCEPTION 'stale version accepted';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM <> 'CONTROL_STALE_VERSION:1' THEN RAISE; END IF;
 END;
 scheduled_at := clock_timestamp() + interval '10 minutes';
 PERFORM core10._set_bootstrap_policy_v1(9612, false, scheduled_at, 1, 'Schedule fixture OFF', 'bootstrap-off');
 result := core10._bootstrap_policy_decision_v1(9612);
 IF result->>'enabled' IS DISTINCT FROM 'true' OR result->>'version' IS DISTINCT FROM '1' THEN
  RAISE EXCEPTION 'future policy applied early: %', result;
 END IF;
 IF (SELECT count(*) FROM core10.canonical_audit_events_v1 WHERE tenant_id = 9612 AND business_id IS NULL) <> 2
 OR NOT EXISTS (
  SELECT 1 FROM core10.canonical_audit_events_v1 first_event
  JOIN core10.canonical_audit_events_v1 second_event
    ON second_event.tenant_id = first_event.tenant_id AND second_event.business_id IS NULL
    AND second_event.stream_seq = 2 AND second_event.prior_digest = first_event.event_digest
  JOIN core10.audit_chain_heads_v1 head
    ON head.tenant_id = second_event.tenant_id AND head.business_id IS NULL
    AND head.last_seq = 2 AND head.last_digest = second_event.event_digest
  WHERE first_event.id = audit_id AND first_event.tenant_id = 9612 AND first_event.business_id IS NULL
    AND first_event.stream_seq = 1 AND first_event.prior_digest = repeat('0', 64)
    AND first_event.actor_id = '00009612-0000-4000-8000-000000000001'
    AND first_event.payload->>'authorization' = 'tenant_owner'
 ) THEN RAISE EXCEPTION 'canonical tenant audit chain incorrect'; END IF;

 BEGIN
  PERFORM core10._bootstrap_policy_decision_v1(9611);
  RAISE EXCEPTION 'cross-tenant policy read accepted';
 EXCEPTION WHEN insufficient_privilege THEN
  IF SQLERRM <> 'BOOTSTRAP_POLICY_DENIED' THEN RAISE; END IF;
 END;
 PERFORM set_config('request.jwt.claims', '{"sub":"00009611-0000-4000-8000-000000000002"}', true);
 IF NOT core10.can_manage(9611, 9611) THEN RAISE EXCEPTION 'Business Owner fixture invalid'; END IF;
 BEGIN
  PERFORM core10._set_bootstrap_policy_v1(9611, true, NULL, 0, 'Forged tenant Owner', 'bootstrap-forged');
  RAISE EXCEPTION 'Business Owner changed tenant policy';
 EXCEPTION WHEN insufficient_privilege THEN
  IF SQLERRM <> 'BOOTSTRAP_POLICY_DENIED' THEN RAISE; END IF;
 END;
 PERFORM set_config('request.jwt.claims', '{"sub":"00009613-0000-4000-8000-000000000001"}', true);
 BEGIN
  PERFORM core10._bootstrap_policy_decision_v1(9613);
  RAISE EXCEPTION 'revoked tenant owner accepted';
 EXCEPTION WHEN insufficient_privilege THEN
  IF SQLERRM <> 'BOOTSTRAP_POLICY_DENIED' THEN RAISE; END IF;
 END;
END
$test$;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub":"00009612-0000-4000-8000-000000000001"}', true);
DO $test$
BEGIN
 IF (SELECT count(*) FROM core10.canonical_audit_events_v1 WHERE tenant_id = 9612 AND business_id IS NULL) <> 2 THEN
  RAISE EXCEPTION 'tenant owner cannot read its audit history';
 END IF;
END
$test$;
SELECT set_config('request.jwt.claims', '{"sub":"00009611-0000-4000-8000-000000000002"}', true);
DO $test$
BEGIN
 IF EXISTS (SELECT 1 FROM core10.canonical_audit_events_v1 WHERE business_id IS NULL) THEN
  RAISE EXCEPTION 'tenant audit visible to another scope';
 END IF;
END
$test$;
RESET ROLE;
ROLLBACK;
\echo NP01_BOOTSTRAP_POLICY_PROVIDER_PASS
