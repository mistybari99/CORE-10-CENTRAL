-- CORE10 baseline20 v1; ordered, lossless consolidation. Fresh empty schema only.
-- CORE10 BASELINE SOURCE 0007_np01_build02a_approval.up.sql SHA256 5a180c2c23f2da4aa46a1486c54b0023bb0615a5455c9aa35ef507112e51b701
-- S1-b canonical Build02A approval-policy access extension.
-- Dependency-based guard, no assumption about disposable database naming.
-- Build 02A: approval actions reuse Build01's canonical membership and audit.
-- Disposable core10 candidate only; not a production migration or posting API.
DO $guard$ BEGIN
 IF to_regclass('core10.access_change_events_v1') IS NULL OR
    to_regprocedure('core10.build01_set_access_v1(bigint,uuid,text,text,bigint,text[],text[],timestamptz,text,bigint)') IS NULL THEN
  RAISE EXCEPTION 'BUILD02A_BUILD01_REQUIRED';
 END IF;
END $guard$;

ALTER TABLE core10.business_members
 ADD COLUMN approval_actions text[] NOT NULL DEFAULT '{}'
 CHECK(approval_actions <@ ARRAY['approval.submit','approval.decide','approval.delegate','approval.withdraw','approval.export','approval.exception']::text[]),
 ADD COLUMN approval_denied_actions text[] NOT NULL DEFAULT '{}'
 CHECK(approval_denied_actions <@ ARRAY['approval.submit','approval.decide','approval.delegate','approval.withdraw','approval.export','approval.exception']::text[]),
 ADD COLUMN approval_valid_until timestamptz;

ALTER TABLE core10.access_change_events_v1 DROP CONSTRAINT access_change_events_v1_command_check;
ALTER TABLE core10.access_change_events_v1 ADD CONSTRAINT access_change_events_v1_command_check
 CHECK(command IN('business_member.grant','business_member.revoke','site_grant.grant','site_grant.revoke','setup.business','setup.site','approval_policy.apply'));

CREATE OR REPLACE FUNCTION core10.can_approval_action_v1(p_tenant bigint,p_business bigint,p_action text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
 SELECT p_action=ANY(ARRAY['approval.submit','approval.decide','approval.delegate','approval.withdraw','approval.export','approval.exception'])
 AND EXISTS(SELECT 1 FROM core10.businesses b JOIN core10.tenants t ON t.id=b.tenant_id
  WHERE b.id=p_business AND b.tenant_id=p_tenant AND t.active
   AND NOT EXISTS(SELECT 1 FROM core10.business_members d
    WHERE d.business_id=p_business AND d.tenant_id=p_tenant AND d.user_id=core10.actor_uid()
     AND d.active AND (d.valid_until IS NULL OR d.valid_until>statement_timestamp())
     AND (d.approval_valid_until IS NULL OR d.approval_valid_until>statement_timestamp())
     AND p_action=ANY(d.approval_denied_actions))
   AND (
     core10.can_tenant(p_tenant)
     OR EXISTS(SELECT 1 FROM core10.business_members m
       WHERE m.business_id=p_business AND m.tenant_id=p_tenant AND m.user_id=core10.actor_uid()
        AND m.active AND (m.valid_until IS NULL OR m.valid_until>statement_timestamp())
        AND (
          ((m.approval_valid_until IS NULL OR m.approval_valid_until>statement_timestamp()) AND p_action=ANY(m.approval_actions))
          OR (m.role='business_owner')
          OR (m.role='manager' AND p_action=ANY(ARRAY['approval.submit','approval.withdraw']))
        ))
   ))
$$;

CREATE FUNCTION core10.build02a_set_approval_policy_v1(
 p_business bigint,p_subject uuid,p_actions text[],p_denied_actions text[],p_valid_until timestamptz,
 p_request text,p_expected_version bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE actor uuid:=core10.actor_uid(); tenant bigint; member record; previous record; event_id bigint;
 desired text[]:=COALESCE(p_actions,'{}'::text[]); denied text[]:=COALESCE(p_denied_actions,'{}'::text[]); signature jsonb; after_state jsonb;
BEGIN
 SELECT tenant_id INTO tenant FROM core10.businesses WHERE id=p_business;
 IF actor IS NULL OR tenant IS NULL OR NOT core10.can_manage(tenant,p_business) THEN RAISE EXCEPTION 'BUILD02A_POLICY_DENIED'; END IF;
 IF p_subject IS NULL OR p_subject=actor OR p_request IS NULL OR length(btrim(p_request)) NOT BETWEEN 1 AND 120 OR p_expected_version<0 THEN
  RAISE EXCEPTION 'BUILD02A_INVALID_POLICY';
 END IF;
 IF NOT desired <@ ARRAY['approval.submit','approval.decide','approval.delegate','approval.withdraw','approval.export','approval.exception']::text[]
  OR NOT denied <@ ARRAY['approval.submit','approval.decide','approval.delegate','approval.withdraw','approval.export','approval.exception']::text[]
  OR cardinality(desired)<>(SELECT count(DISTINCT x) FROM unnest(desired)x)
  OR cardinality(denied)<>(SELECT count(DISTINCT x) FROM unnest(denied)x)
  OR EXISTS(SELECT 1 FROM unnest(desired)x WHERE x=ANY(denied)) THEN RAISE EXCEPTION 'BUILD02A_INVALID_ACTIONS'; END IF;
 IF p_valid_until IS NOT NULL AND p_valid_until<=statement_timestamp() THEN RAISE EXCEPTION 'BUILD02A_EXPIRY_MUST_BE_FUTURE'; END IF;
 PERFORM 1 FROM core10.businesses WHERE id=p_business FOR UPDATE;
 IF NOT core10.can_manage(tenant,p_business) THEN RAISE EXCEPTION 'BUILD02A_POLICY_DENIED'; END IF;
 SELECT * INTO member FROM core10.business_members WHERE business_id=p_business AND user_id=p_subject FOR UPDATE;
 IF NOT FOUND OR NOT member.active OR (member.valid_until IS NOT NULL AND member.valid_until<=statement_timestamp()) OR member.role='investor' THEN
  RAISE EXCEPTION 'BUILD02A_SUBJECT_NOT_ELIGIBLE';
 END IF;
 signature:=jsonb_build_object('business',p_business,'subject',p_subject,'actions',desired,'denied_actions',denied,
  'valid_until',p_valid_until,'expected_version',p_expected_version);
 SELECT * INTO previous FROM core10.access_change_events_v1 WHERE business_id=p_business AND request_key=p_request;
 IF FOUND THEN
  IF previous.input_signature<>signature OR previous.actor_uid<>actor OR previous.command<>'approval_policy.apply' THEN RAISE EXCEPTION 'BUILD02A_REQUEST_CONFLICT'; END IF;
  RETURN jsonb_build_object('business_id',p_business,'event_id',previous.id,'request_key',p_request,'after_state',previous.after_state);
 END IF;
 IF p_expected_version IS NOT NULL AND p_expected_version<>member.version THEN RAISE EXCEPTION 'BUILD02A_STALE_VERSION'; END IF;
 UPDATE core10.business_members SET approval_actions=desired,approval_denied_actions=denied,approval_valid_until=p_valid_until
  WHERE business_id=p_business AND user_id=p_subject;
 SELECT to_jsonb(m) INTO after_state FROM core10.business_members m WHERE m.business_id=p_business AND m.user_id=p_subject;
 INSERT INTO core10.access_change_events_v1(tenant_id,business_id,request_key,command,subject_uid,input_signature,before_state,after_state,actor_uid,event_kind)
 VALUES(tenant,p_business,p_request,'approval_policy.apply',p_subject,signature,to_jsonb(member),after_state,actor,'policy.apply') RETURNING id INTO event_id;
 RETURN jsonb_build_object('business_id',p_business,'event_id',event_id,'request_key',p_request,'after_state',after_state);
END $$;

REVOKE ALL ON FUNCTION core10.can_approval_action_v1(bigint,bigint,text),
 core10.build02a_set_approval_policy_v1(bigint,uuid,text[],text[],timestamptz,text,bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION core10.can_approval_action_v1(bigint,bigint,text),
 core10.build02a_set_approval_policy_v1(bigint,uuid,text[],text[],timestamptz,text,bigint) TO authenticated;
INSERT INTO core10.schema_migrations(version,name,checksum) VALUES(7,'0007_np01_build02a_approval','5a180c2c23f2da4aa46a1486c54b0023bb0615a5455c9aa35ef507112e51b701');

-- CORE10 BASELINE SOURCE 0008_np01_canonical_audit.up.sql SHA256 5225a2ad5cbc512cb964262c1aba897c7c1e208e9eec20ee6167503bf9e4854d
-- S1-c / CHG-012: canonical Audit port, adopting GOV-003's scoped tamper-evident intent.
-- Not a clone of GOV-003 tenancy or a second domain ledger. Depends on S1-b 0001..0007.
-- Test candidate only; do not apply to a hosted or protected legacy database without Owner GO.
-- Hash chaining is tamper-EVIDENT against ordinary principals, not legal WORM.
CREATE TABLE core10.audit_chain_heads_v1 (
 tenant_id bigint NOT NULL,
 business_id bigint PRIMARY KEY,
 last_seq bigint NOT NULL DEFAULT 0 CHECK(last_seq >= 0),
 last_digest text NOT NULL DEFAULT repeat('0',64) CHECK(last_digest ~ '^[0-9a-f]{64}$'),
 FOREIGN KEY(business_id,tenant_id) REFERENCES core10.businesses(id,tenant_id)
);
ALTER TABLE core10.audit_chain_heads_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON core10.audit_chain_heads_v1 FROM PUBLIC,authenticated;

CREATE TABLE core10.canonical_audit_events_v1 (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL,
 business_id bigint NOT NULL,
 stream_seq bigint NOT NULL CHECK(stream_seq > 0),
 source_domain text NOT NULL CHECK(source_domain ~ '^[a-z][a-z0-9_]{1,63}$'),
 source_ref text NOT NULL CHECK(length(source_ref) BETWEEN 1 AND 120),
 action text NOT NULL CHECK(action ~ '^[a-z][a-z0-9_.]{1,100}$'),
 actor_id uuid NOT NULL,
 request_key text NOT NULL CHECK(length(request_key) BETWEEN 1 AND 160),
 payload jsonb NOT NULL CHECK(jsonb_typeof(payload)='object'),
 payload_sha256 text NOT NULL CHECK(payload_sha256 ~ '^[0-9a-f]{64}$'),
 prior_digest text NOT NULL CHECK(prior_digest ~ '^[0-9a-f]{64}$'),
 event_digest text NOT NULL CHECK(event_digest ~ '^[0-9a-f]{64}$'),
 event_at timestamptz NOT NULL,
 UNIQUE(business_id,stream_seq),
 UNIQUE(business_id,source_domain,source_ref),
 UNIQUE(business_id,request_key),
 FOREIGN KEY(business_id,tenant_id) REFERENCES core10.businesses(id,tenant_id)
);
ALTER TABLE core10.canonical_audit_events_v1 ENABLE ROW LEVEL SECURITY;
CREATE POLICY canonical_audit_owner_read_v1 ON core10.canonical_audit_events_v1
 FOR SELECT TO authenticated USING (core10.can_manage(tenant_id,business_id));
REVOKE ALL ON core10.canonical_audit_events_v1 FROM PUBLIC,authenticated;
GRANT SELECT ON core10.canonical_audit_events_v1 TO authenticated;

CREATE FUNCTION core10._immutable_canonical_audit_v1() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog,core10 AS $body$
BEGIN RAISE EXCEPTION 'canonical_audit_immutable'; END $body$;
CREATE TRIGGER canonical_audit_events_immutable_v1
 BEFORE UPDATE OR DELETE ON core10.canonical_audit_events_v1
 FOR EACH ROW EXECUTE FUNCTION core10._immutable_canonical_audit_v1();
REVOKE EXECUTE ON FUNCTION core10._immutable_canonical_audit_v1() FROM PUBLIC,authenticated;

-- SECURITY DEFINER internal-only append boundary. Never grant to authenticated.
-- The source trigger passes actor and scope from authoritative domain receipt.
CREATE FUNCTION core10._append_canonical_audit_v1(
 p_tenant bigint,p_business bigint,p_source text,p_ref text,p_action text,
 p_actor uuid,p_key text,p_payload jsonb
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,core10 AS $body$
DECLARE h core10.audit_chain_heads_v1%ROWTYPE;
 old core10.canonical_audit_events_v1%ROWTYPE;
 v_sha text;v_digest text;v_seq bigint;v_at timestamptz;v_id bigint;
BEGIN
 IF p_tenant IS NULL OR p_business IS NULL OR p_actor IS NULL
  OR p_source IS NULL OR p_source !~ '^[a-z][a-z0-9_]{1,63}$'
  OR p_ref IS NULL OR length(p_ref) NOT BETWEEN 1 AND 120
  OR p_action IS NULL OR p_action !~ '^[a-z][a-z0-9_.]{1,100}$'
  OR p_key IS NULL OR length(p_key) NOT BETWEEN 1 AND 160
  OR p_payload IS NULL OR jsonb_typeof(p_payload)<>'object'
  OR NOT EXISTS(SELECT 1 FROM core10.businesses b
     WHERE b.id=p_business AND b.tenant_id=p_tenant)
 THEN RAISE EXCEPTION 'canonical_audit_invalid_source'; END IF;
 v_sha:=encode(sha256(convert_to(p_payload::text,'UTF8')),'hex');
 INSERT INTO core10.audit_chain_heads_v1(tenant_id,business_id)
 VALUES(p_tenant,p_business) ON CONFLICT(business_id) DO NOTHING;
 SELECT * INTO h FROM core10.audit_chain_heads_v1 WHERE business_id=p_business FOR UPDATE;
 IF h.tenant_id<>p_tenant THEN RAISE EXCEPTION 'canonical_audit_scope_mismatch'; END IF;
 SELECT * INTO old FROM core10.canonical_audit_events_v1
 WHERE business_id=p_business AND source_domain=p_source AND source_ref=p_ref;
 IF FOUND THEN
  IF old.actor_id<>p_actor OR old.request_key<>p_key OR old.action<>p_action
     OR old.payload_sha256<>v_sha OR old.tenant_id<>p_tenant
  THEN RAISE EXCEPTION 'canonical_audit_replay_conflict'; END IF;
  RETURN old.id;
 END IF;
 v_seq:=h.last_seq+1;v_at:=clock_timestamp();
 v_digest:=encode(sha256(convert_to(concat_ws('|',
  'c10-audit-v1',h.last_digest,p_tenant::text,p_business::text,v_seq::text,
  p_source,p_ref,p_action,p_actor::text,p_key,v_sha,
  to_char(v_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')),'UTF8')),'hex');
 INSERT INTO core10.canonical_audit_events_v1(
  tenant_id,business_id,stream_seq,source_domain,source_ref,action,
  actor_id,request_key,payload,payload_sha256,prior_digest,event_digest,event_at)
 VALUES(p_tenant,p_business,v_seq,p_source,p_ref,p_action,p_actor,p_key,
        p_payload,v_sha,h.last_digest,v_digest,v_at)
 RETURNING id INTO v_id;
 UPDATE core10.audit_chain_heads_v1 SET last_seq=v_seq,last_digest=v_digest
 WHERE business_id=p_business;
 RETURN v_id;
END $body$;
REVOKE EXECUTE ON FUNCTION core10._append_canonical_audit_v1(
 bigint,bigint,text,text,text,uuid,text,jsonb) FROM PUBLIC,authenticated;

CREATE FUNCTION core10._access_to_canonical_audit_v1() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,core10 AS $body$
BEGIN
 PERFORM core10._append_canonical_audit_v1(
  NEW.tenant_id,NEW.business_id,'access',NEW.id::text,'access.'||NEW.command,
  NEW.actor_uid,'access:'||NEW.id::text,
  jsonb_build_object('event_ref',NEW.id::text,'command',NEW.command,'kind',NEW.event_kind));
 RETURN NEW;
END $body$;
CREATE TRIGGER access_to_canonical_audit_v1
 AFTER INSERT ON core10.access_change_events_v1
 FOR EACH ROW EXECUTE FUNCTION core10._access_to_canonical_audit_v1();
REVOKE EXECUTE ON FUNCTION core10._access_to_canonical_audit_v1() FROM PUBLIC,authenticated;

-- Scope-checked audit integrity readback. Detects gaps, payload changes, and digest drift.
CREATE FUNCTION core10.verify_canonical_audit_v1(p_business bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,core10 AS $body$
DECLARE h core10.audit_chain_heads_v1%ROWTYPE; e record;
 v_prior text:=repeat('0',64);v_n bigint:=0;v_sha text;v_digest text;v_tenant bigint;
BEGIN
 SELECT tenant_id INTO v_tenant FROM core10.businesses WHERE id=p_business;
 IF v_tenant IS NULL OR NOT core10.can_manage(v_tenant,p_business)
 THEN RAISE EXCEPTION 'canonical_audit_read_denied'; END IF;
 FOR e IN SELECT * FROM core10.canonical_audit_events_v1
   WHERE business_id=p_business ORDER BY stream_seq LOOP
  v_n:=v_n+1;
  IF e.stream_seq<>v_n OR e.prior_digest<>v_prior THEN
   RETURN jsonb_build_object('ok',false,'checked',v_n,'reason','chain_gap'); END IF;
  v_sha:=encode(sha256(convert_to(e.payload::text,'UTF8')),'hex');
  v_digest:=encode(sha256(convert_to(concat_ws('|',
    'c10-audit-v1',v_prior,e.tenant_id::text,e.business_id::text,e.stream_seq::text,
    e.source_domain,e.source_ref,e.action,e.actor_id::text,e.request_key,v_sha,
    to_char(e.event_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')),'UTF8')),'hex');
  IF v_sha<>e.payload_sha256 OR v_digest<>e.event_digest THEN
   RETURN jsonb_build_object('ok',false,'checked',v_n,'reason','digest_mismatch'); END IF;
  v_prior:=e.event_digest;
 END LOOP;
 SELECT * INTO h FROM core10.audit_chain_heads_v1 WHERE business_id=p_business;
 IF (NOT FOUND AND v_n>0) OR
    (FOUND AND (h.last_seq<>v_n OR h.last_digest<>v_prior OR h.tenant_id<>v_tenant)) THEN
  RETURN jsonb_build_object('ok',false,'checked',v_n,'reason','head_mismatch'); END IF;
 RETURN jsonb_build_object('ok',true,'checked',v_n,'reason',null);
END $body$;
REVOKE EXECUTE ON FUNCTION core10.verify_canonical_audit_v1(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION core10.verify_canonical_audit_v1(bigint) TO authenticated;
INSERT INTO core10.schema_migrations(version,name,checksum) VALUES(8,'0008_np01_canonical_audit','5225a2ad5cbc512cb964262c1aba897c7c1e208e9eec20ee6167503bf9e4854d');

-- CORE10 BASELINE SOURCE 0009_np01_gov002_approval.up.sql SHA256 444daba14c15fadfbec72e2a9ef2da5748ebb2a1d2afb3bfc94d1d43e05a6d7b
-- S1-c / CHG-011: A008 isolated GOV-002 non-posting core port.
-- Source: PR #99 ancestor c10_a008_atomic_approval_draft.sql. No duplicate auth/stock store.
-- Approval requests/events are one canonical approval journal; canonical audit is 0008.
-- C10-A008 isolated PostgreSQL approval prototype; NOT a production migration.
-- Apply ONLY after c10_a018_demo_backend.sql to disposable c10_demo database.
CREATE TABLE core10.approval_requests (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL,
 business_id bigint NOT NULL,
 created_by uuid NOT NULL,
 status text NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','approved','rejected','deferred')),
 created_at timestamptz NOT NULL DEFAULT now(),
 decided_by uuid,
 decided_at timestamptz,
 FOREIGN KEY (business_id,tenant_id) REFERENCES core10.businesses(id,tenant_id),
 CHECK ((status='pending' AND decided_by IS NULL AND decided_at IS NULL)
     OR (status<>'pending' AND decided_by IS NOT NULL AND decided_at IS NOT NULL))
);
CREATE TABLE core10.approval_events (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 request_id bigint NOT NULL REFERENCES core10.approval_requests(id),
 tenant_id bigint NOT NULL,
 business_id bigint NOT NULL,
 actor_id uuid NOT NULL,
 action text NOT NULL CHECK(action IN ('approve','reject','defer')),
 idempotency_key text NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(request_id,idempotency_key)
);
CREATE INDEX approval_events_business_idx ON core10.approval_events(business_id,request_id);
ALTER TABLE core10.approval_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE core10.approval_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY approval_request_read ON core10.approval_requests FOR SELECT TO authenticated
 USING(core10.can_see_business(tenant_id,business_id));
CREATE POLICY approval_event_read ON core10.approval_events FOR SELECT TO authenticated
 USING(core10.can_see_business(tenant_id,business_id));

-- This function owns both the state transition and append-only event in one transaction.
-- Caller-supplied tenant, business, actor or role claims are never accepted.
CREATE FUNCTION core10.decide_approval(p_request bigint,p_action text,p_key text)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path=core10,pg_catalog AS $$
DECLARE v_req core10.approval_requests%ROWTYPE;
        v_actor uuid; v_event bigint; v_previous core10.approval_events%ROWTYPE;
BEGIN
 v_actor:=core10.actor_uid();
 IF v_actor IS NULL OR p_request IS NULL OR p_action IS NULL
    OR p_action NOT IN ('approve','reject','defer')
    OR p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{8,128}$' THEN
   RAISE EXCEPTION 'invalid_approval_command';
 END IF;
 SELECT * INTO v_req FROM core10.approval_requests WHERE id=p_request FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'approval_not_authorized'; END IF;
 IF NOT core10.can_manage(v_req.tenant_id,v_req.business_id)
    OR v_req.created_by=v_actor THEN
   RAISE EXCEPTION 'approval_not_authorized';
 END IF;
 -- Replays must match the original actor and action; do not reapply transitions.
 SELECT * INTO v_previous FROM core10.approval_events
 WHERE request_id=p_request AND idempotency_key=p_key;
 IF FOUND THEN
   IF v_previous.actor_id<>v_actor OR v_previous.action<>p_action
      OR v_previous.tenant_id<>v_req.tenant_id OR v_previous.business_id<>v_req.business_id THEN
     RAISE EXCEPTION 'approval_idempotency_conflict';
   END IF;
   RETURN v_previous.id;
 END IF;
 IF v_req.status<>'pending' THEN RAISE EXCEPTION 'approval_invalid_transition'; END IF;
 UPDATE core10.approval_requests
 SET status=CASE p_action WHEN 'approve' THEN 'approved'
                          WHEN 'reject' THEN 'rejected' ELSE 'deferred' END,
     decided_by=v_actor,decided_at=clock_timestamp()
 WHERE id=p_request AND status='pending';
 IF NOT FOUND THEN RAISE EXCEPTION 'approval_invalid_transition'; END IF;
 INSERT INTO core10.approval_events
 (request_id,tenant_id,business_id,actor_id,action,idempotency_key)
 VALUES (p_request,v_req.tenant_id,v_req.business_id,v_actor,p_action,p_key)
 RETURNING id INTO v_event;
 RETURN v_event;
END $$;

-- Lock down all direct writes and public function execution.
REVOKE ALL ON core10.approval_requests,core10.approval_events FROM PUBLIC,authenticated;
REVOKE ALL ON FUNCTION core10.decide_approval(bigint,text,text) FROM PUBLIC;
GRANT SELECT ON core10.approval_requests,core10.approval_events TO authenticated;
GRANT EXECUTE ON FUNCTION core10.decide_approval(bigint,text,text) TO authenticated;
-- SECURITY DEFINER owner must be controlled, no BYPASSRLS delegation, and migration reviewed.
-- This prototype has NOT been executed against PostgreSQL or Supabase.

-- Domain approval receipts append to the ONE canonical audit stream in 0008.
CREATE FUNCTION core10._approval_to_canonical_audit_v1() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,core10 AS $body$
BEGIN
 PERFORM core10._append_canonical_audit_v1(
  NEW.tenant_id,NEW.business_id,'approval',NEW.id::text,'approval.'||NEW.action,
  NEW.actor_id,'approval:'||NEW.id::text,
  jsonb_build_object('event_ref',NEW.id::text,'request_ref',NEW.request_id::text,
                     'action',NEW.action));
 RETURN NEW;
END $body$;
CREATE TRIGGER approval_to_canonical_audit_v1 AFTER INSERT ON core10.approval_events
 FOR EACH ROW EXECUTE FUNCTION core10._approval_to_canonical_audit_v1();
REVOKE EXECUTE ON FUNCTION core10._approval_to_canonical_audit_v1() FROM PUBLIC,authenticated;
CREATE FUNCTION core10._immutable_approval_event_v1() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog,core10 AS $body$
BEGIN RAISE EXCEPTION 'approval_event_immutable'; END $body$;
CREATE TRIGGER approval_event_immutable_v1 BEFORE UPDATE OR DELETE ON core10.approval_events
 FOR EACH ROW EXECUTE FUNCTION core10._immutable_approval_event_v1();
REVOKE EXECUTE ON FUNCTION core10._immutable_approval_event_v1() FROM PUBLIC,authenticated;
INSERT INTO core10.schema_migrations(version,name,checksum) VALUES(9,'0009_np01_gov002_approval','444daba14c15fadfbec72e2a9ef2da5748ebb2a1d2afb3bfc94d1d43e05a6d7b');

-- CORE10 BASELINE SOURCE 0010_np01_gov002_typed.up.sql SHA256 25d8f867650e682cab86cd1cde62556c4c6a25f5c875b617c25bf8d1cd522ed3
-- S1-c / CHG-011: GOV-002 typed NON_POSTING review port from PR #99 ancestry.
-- Reuses 0009 approval journal and Build01 DB-resolved identities, never a duplicate store.
-- verify_approval_binding_v1 remains inaccessible to client until a certified source handler exists.
-- C10-CAP-GOV-002, C10-A008 additive typed approval slice. DISPOSABLE PG17 ONLY.
-- Depends on c10_a018_demo_backend.sql, seed, and c10_a008_atomic_approval_draft.sql.
-- No operational stock/finance/HR command is executed by this module.
-- No Supabase SG migration, GoTrue certification, live authorization or main merge implied.

CREATE TABLE core10.approval_policy_versions_v1 (
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
    REFERENCES core10.businesses(id, tenant_id)
);

ALTER TABLE core10.approval_policy_versions_v1 ENABLE ROW LEVEL SECURITY;
CREATE POLICY approval_policy_owner_read_v1
  ON core10.approval_policy_versions_v1 FOR SELECT TO authenticated
  USING (core10.can_manage(tenant_id, business_id));
REVOKE ALL ON core10.approval_policy_versions_v1 FROM PUBLIC, authenticated;
GRANT SELECT ON core10.approval_policy_versions_v1 TO authenticated;

-- Existing A008 request/event tables remain the one canonical demo approval journal.
-- Nullable columns preserve older A008 fixture rows until migration reconciliation.
ALTER TABLE core10.approval_requests
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
      AND domain_v1 ~ '^[a-z][a-z0-9_]{1,63}$'
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
      REFERENCES core10.approval_policy_versions_v1(id, tenant_id, business_id);

CREATE UNIQUE INDEX approval_typed_request_replay_v1
  ON core10.approval_requests (business_id, created_by, submit_key_v1)
  WHERE submit_key_v1 IS NOT NULL;
CREATE INDEX approval_typed_inbox_v1
  ON core10.approval_requests (business_id, status, expires_at_v1)
  WHERE policy_id_v1 IS NOT NULL;

-- All policies are immutable. Each publish appends a new version under a row lock.
-- This does NOT grant rights to override stock, finance or separation-of-duties rules.
CREATE FUNCTION core10.publish_approval_policy_v1(
  p_business bigint, p_domain text, p_action text, p_ttl_minutes integer, p_key text
) RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path = core10, pg_catalog AS $fn$
DECLARE
  v_tenant bigint;
  v_actor uuid := core10.actor_uid();
  v_version integer;
  v_id bigint;
  v_old core10.approval_policy_versions_v1%ROWTYPE;
BEGIN
  IF v_actor IS NULL OR p_business IS NULL
    OR p_domain IS NULL OR p_domain !~ '^[a-z][a-z0-9_]{1,63}$'
    OR p_action IS NULL OR p_action !~ '^[a-z][a-z0-9_]{1,63}$'
    OR p_ttl_minutes IS NULL OR p_ttl_minutes NOT BETWEEN 5 AND 43200
    OR p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{8,128}$'
  THEN RAISE EXCEPTION 'invalid_approval_policy'; END IF;

  -- Serialize version allocation for this business, including concurrent owners.
  SELECT tenant_id INTO v_tenant
    FROM core10.businesses WHERE id = p_business FOR UPDATE;
  IF NOT FOUND OR NOT core10.can_manage(v_tenant, p_business)
  THEN RAISE EXCEPTION 'approval_policy_denied'; END IF;

  SELECT * INTO v_old FROM core10.approval_policy_versions_v1
    WHERE business_id = p_business AND request_key = p_key;
  IF FOUND THEN
    IF v_old.created_by <> v_actor OR v_old.domain <> p_domain
      OR v_old.action_code <> p_action OR v_old.ttl_minutes <> p_ttl_minutes
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
          p_ttl_minutes, p_key, v_actor)
  RETURNING id INTO v_id;
  RETURN v_id;
END $fn$;

CREATE FUNCTION core10.submit_typed_approval_v1(
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
    ORDER BY version DESC LIMIT 1;
  IF NOT FOUND THEN RAISE EXCEPTION 'approval_policy_missing'; END IF;

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

-- Extend the one existing A008 transition API: preserve legacy demo behavior,
-- enforce typed expiry and immutable policy pin on all new A008 requests.
CREATE OR REPLACE FUNCTION core10.decide_approval(
  p_request bigint, p_action text, p_key text
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path = core10, pg_catalog AS $fn$
DECLARE
  v_req core10.approval_requests%ROWTYPE;
  v_actor uuid;
  v_event bigint;
  v_previous core10.approval_events%ROWTYPE;
BEGIN
  v_actor := core10.actor_uid();
  IF v_actor IS NULL OR p_request IS NULL
    OR p_action IS NULL OR p_action NOT IN ('approve','reject','defer')
    OR p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{8,128}$'
  THEN RAISE EXCEPTION 'invalid_approval_command'; END IF;

  SELECT * INTO v_req FROM core10.approval_requests
    WHERE id = p_request FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'approval_not_authorized'; END IF;
  IF NOT core10.can_manage(v_req.tenant_id, v_req.business_id)
    OR v_req.created_by = v_actor
  THEN RAISE EXCEPTION 'approval_not_authorized'; END IF;

  SELECT * INTO v_previous FROM core10.approval_events
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
      SELECT 1 FROM core10.approval_policy_versions_v1 p
      WHERE p.id = v_req.policy_id_v1 AND p.tenant_id = v_req.tenant_id
        AND p.business_id = v_req.business_id
        AND p.version = v_req.policy_version_v1
        AND p.domain = v_req.domain_v1 AND p.action_code = v_req.action_code_v1
    ) THEN RAISE EXCEPTION 'approval_policy_pin_invalid'; END IF;
  END IF;

  UPDATE core10.approval_requests SET
    status = CASE p_action WHEN 'approve' THEN 'approved'
                           WHEN 'reject' THEN 'rejected' ELSE 'deferred' END,
    decided_by = v_actor, decided_at = clock_timestamp()
  WHERE id = p_request AND status = 'pending';
  IF NOT FOUND THEN RAISE EXCEPTION 'approval_invalid_transition'; END IF;

  INSERT INTO core10.approval_events
    (request_id, tenant_id, business_id, actor_id, action, idempotency_key)
  VALUES (p_request, v_req.tenant_id, v_req.business_id, v_actor, p_action, p_key)
  RETURNING id INTO v_event;
  RETURN v_event;
END $fn$;

-- This is a NON-POSTING service-only binding check, not an execution receipt.
-- A future certified typed domain handler must re-read its live source inside
-- the same transaction, invoke this check, and enforce its own posting invariants.
CREATE FUNCTION core10.verify_approval_binding_v1(
  p_request bigint, p_business bigint, p_domain text, p_action text,
  p_source_key text, p_source_version bigint, p_payload jsonb
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path = core10, pg_catalog AS $fn$
DECLARE
  v_req core10.approval_requests%ROWTYPE;
  v_event bigint;
BEGIN
  SELECT * INTO v_req FROM core10.approval_requests WHERE id = p_request;
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

  SELECT id INTO v_event FROM core10.approval_events
    WHERE request_id = p_request AND action = 'approve';
  IF NOT FOUND THEN RAISE EXCEPTION 'approval_receipt_missing'; END IF;
  RETURN v_event;
END $fn$;

REVOKE ALL ON FUNCTION core10.publish_approval_policy_v1(bigint,text,text,integer,text)
  FROM PUBLIC;
REVOKE ALL ON FUNCTION core10.submit_typed_approval_v1(bigint,text,text,text,bigint,jsonb,text)
  FROM PUBLIC;
REVOKE ALL ON FUNCTION core10.verify_approval_binding_v1(bigint,bigint,text,text,text,bigint,jsonb)
  FROM PUBLIC, authenticated;
GRANT EXECUTE ON FUNCTION core10.publish_approval_policy_v1(bigint,text,text,integer,text)
  TO authenticated;
GRANT EXECUTE ON FUNCTION core10.submit_typed_approval_v1(bigint,text,text,text,bigint,jsonb,text)
  TO authenticated;
-- No direct service-role grant here: domain adapter and source-linked posting are NOT_CONNECTED.
-- The pre-existing A008 decide_approval grant stays authenticated.
-- Before any real release: reconcile A021/A034, signed GoTrue, live source version
-- checks, multi-stage/delegation/withdrawal/reversal and migration drift.
INSERT INTO core10.schema_migrations(version,name,checksum) VALUES(10,'0010_np01_gov002_typed','25d8f867650e682cab86cd1cde62556c4c6a25f5c875b617c25bf8d1cd522ed3');

-- CORE10 BASELINE SOURCE 0011_np01_gov002_routed_review.up.sql SHA256 ae7dcfe0ff07013f567c0d1423abd3723e98c3032e1d63cd924c4f9a64c0e7c2
-- S1-c CHG-011: canonical GOV-002 routed review, delegation, withdrawal, reviewer inbox.
-- Source model: isolated GOV-002 PR #99 ancestry; rewritten against core10 + Build01 + Build02A.
-- NOT a domain/Stock/Money posting adapter. PG17 disposable test only; no Owner release GO.
ALTER TABLE core10.approval_requests DROP CONSTRAINT approval_requests_status_check;
ALTER TABLE core10.approval_requests ADD CONSTRAINT approval_requests_status_check
 CHECK(status IN ('pending','approved','rejected','deferred','withdrawn'));
ALTER TABLE core10.approval_events DROP CONSTRAINT approval_events_action_check;
ALTER TABLE core10.approval_events ADD CONSTRAINT approval_events_action_check
 CHECK(action IN ('approve','reject','defer','withdraw','delegate','revoke'));

-- Existing default RLS was business-readable. Harden to scoped reviewer vs maker.
DROP POLICY approval_request_read ON core10.approval_requests;
CREATE POLICY approval_request_scoped_review_v1 ON core10.approval_requests
 FOR SELECT TO authenticated USING (
 core10.can_manage(tenant_id,business_id)
 OR (created_by=core10.actor_uid() AND core10.can_business(tenant_id,business_id))
);
DROP POLICY approval_event_read ON core10.approval_events;
CREATE POLICY approval_event_scoped_review_v1 ON core10.approval_events
 FOR SELECT TO authenticated USING (
 core10.can_manage(tenant_id,business_id)
 OR EXISTS (SELECT 1 FROM core10.approval_requests q
  WHERE q.id=request_id AND q.created_by=core10.actor_uid()
   AND core10.can_business(q.tenant_id,q.business_id))
);

CREATE TABLE core10.approval_routes_v1 (
 policy_id bigint PRIMARY KEY,
 tenant_id bigint NOT NULL,
 business_id bigint NOT NULL,
 stages text[] NOT NULL CHECK(
  cardinality(stages) BETWEEN 2 AND 5
  AND stages[1]='business_owner'
  AND stages[cardinality(stages)]='tenant_owner'
  AND stages <@ ARRAY['business_owner','manager','tenant_owner']::text[]
  AND NOT (stages[1:cardinality(stages)-1] && ARRAY['tenant_owner']::text[])),
 configured_by uuid NOT NULL,
 route_key text NOT NULL CHECK(route_key ~ '^[A-Za-z0-9_-]{8,128}$'),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(business_id,route_key),
 FOREIGN KEY(policy_id,tenant_id,business_id)
   REFERENCES core10.approval_policy_versions_v1(id,tenant_id,business_id)
);
ALTER TABLE core10.approval_routes_v1 ENABLE ROW LEVEL SECURITY;
CREATE POLICY approval_route_owner_read_v1 ON core10.approval_routes_v1
 FOR SELECT TO authenticated USING(core10.can_manage(tenant_id,business_id));
REVOKE ALL ON core10.approval_routes_v1 FROM PUBLIC,authenticated;
GRANT SELECT ON core10.approval_routes_v1 TO authenticated;

CREATE TABLE core10.approval_stage_receipts_v1 (
 event_id bigint PRIMARY KEY REFERENCES core10.approval_events(id),
 request_id bigint NOT NULL REFERENCES core10.approval_requests(id),
 tenant_id bigint NOT NULL,
 business_id bigint NOT NULL,
 stage_no integer NOT NULL CHECK(stage_no BETWEEN 1 AND 5),
 actor_id uuid NOT NULL,
 delegated_by uuid,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(request_id,stage_no),
 UNIQUE(request_id,actor_id)
);
ALTER TABLE core10.approval_stage_receipts_v1 ENABLE ROW LEVEL SECURITY;
CREATE POLICY approval_stage_owner_or_maker_v1 ON core10.approval_stage_receipts_v1
 FOR SELECT TO authenticated USING (
 core10.can_manage(tenant_id,business_id)
 OR EXISTS(SELECT 1 FROM core10.approval_requests q
  WHERE q.id=request_id AND q.created_by=core10.actor_uid()
   AND core10.can_business(q.tenant_id,q.business_id)));
REVOKE ALL ON core10.approval_stage_receipts_v1 FROM PUBLIC,authenticated;
GRANT SELECT ON core10.approval_stage_receipts_v1 TO authenticated;

CREATE TABLE core10.approval_delegations_v1 (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 request_id bigint NOT NULL REFERENCES core10.approval_requests(id),
 tenant_id bigint NOT NULL,
 business_id bigint NOT NULL,
 stage_no integer NOT NULL DEFAULT 1 CHECK(stage_no=1),
 granted_by uuid NOT NULL,
 delegated_to uuid NOT NULL,
 delegation_key text NOT NULL CHECK(delegation_key ~ '^[A-Za-z0-9_-]{8,128}$'),
 valid_until timestamptz NOT NULL,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 revoked_by uuid,
 revoked_at timestamptz,
 CHECK(granted_by<>delegated_to),
 CHECK((revoked_by IS NULL)=(revoked_at IS NULL)),
 UNIQUE(request_id,stage_no),
 UNIQUE(request_id,delegation_key)
);
ALTER TABLE core10.approval_delegations_v1 ENABLE ROW LEVEL SECURITY;
CREATE POLICY approval_delegation_owner_read_v1 ON core10.approval_delegations_v1
 FOR SELECT TO authenticated USING(core10.can_manage(tenant_id,business_id));
REVOKE ALL ON core10.approval_delegations_v1 FROM PUBLIC,authenticated;
GRANT SELECT ON core10.approval_delegations_v1 TO authenticated;

-- Only a current, business-scoped role (or single bounded stage-one delegate)
-- may cast a decision at the current route stage. Never infer role from JWT metadata.
CREATE FUNCTION core10._can_review_stage_v1(p_request bigint,p_stage integer)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,core10 AS $fn$
DECLARE q core10.approval_requests%ROWTYPE;v_role text;
 actor uuid:=core10.actor_uid();
BEGIN
 SELECT * INTO q FROM core10.approval_requests WHERE id=p_request;
 IF NOT FOUND OR actor IS NULL OR q.created_by=actor OR q.status<>'pending'
  OR q.expires_at_v1<=statement_timestamp()
  OR NOT core10.can_approval_action_v1(q.tenant_id,q.business_id,'approval.decide')
 THEN RETURN false; END IF;
 SELECT r.stages[p_stage] INTO v_role FROM core10.approval_routes_v1 r
 WHERE r.policy_id=q.policy_id_v1 AND r.tenant_id=q.tenant_id
  AND r.business_id=q.business_id AND p_stage BETWEEN 1 AND cardinality(r.stages);
 IF v_role IS NULL THEN RETURN false; END IF;
 IF v_role='tenant_owner' THEN RETURN core10.can_tenant(q.tenant_id); END IF;
 IF EXISTS(SELECT 1 FROM core10.business_members m WHERE
   m.tenant_id=q.tenant_id AND m.business_id=q.business_id
   AND m.user_id=actor AND m.role=v_role AND m.active
   AND (m.valid_until IS NULL OR m.valid_until>statement_timestamp()))
 THEN RETURN true; END IF;
 IF p_stage=1 AND v_role='business_owner' AND EXISTS(
  SELECT 1 FROM core10.approval_delegations_v1 d
  JOIN core10.business_members recipient ON recipient.tenant_id=d.tenant_id
   AND recipient.business_id=d.business_id AND recipient.user_id=d.delegated_to
   AND recipient.role='manager' AND recipient.active
   AND (recipient.valid_until IS NULL OR recipient.valid_until>statement_timestamp())
  JOIN core10.business_members grantor ON grantor.tenant_id=d.tenant_id
   AND grantor.business_id=d.business_id AND grantor.user_id=d.granted_by
   AND grantor.role='business_owner' AND grantor.active
   AND (grantor.valid_until IS NULL OR grantor.valid_until>statement_timestamp())
  WHERE d.request_id=p_request AND d.stage_no=1 AND d.tenant_id=q.tenant_id
   AND d.business_id=q.business_id AND d.delegated_to=actor
   AND d.revoked_at IS NULL AND d.valid_until>statement_timestamp())
 THEN RETURN true; END IF;
 RETURN false;
END $fn$;
REVOKE EXECUTE ON FUNCTION core10._can_review_stage_v1(bigint,integer) FROM PUBLIC,authenticated;

CREATE FUNCTION core10.configure_approval_route_v1(
 p_policy bigint,p_stages text[],p_key text
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,core10 AS $fn$
DECLARE pol core10.approval_policy_versions_v1%ROWTYPE;
 old core10.approval_routes_v1%ROWTYPE;actor uuid:=core10.actor_uid();
BEGIN
 IF actor IS NULL OR p_policy IS NULL OR p_stages IS NULL
  OR cardinality(p_stages) NOT BETWEEN 2 AND 5
  OR array_position(p_stages,NULL) IS NOT NULL
  OR p_stages[1]<>'business_owner'
  OR p_stages[cardinality(p_stages)]<>'tenant_owner'
  OR NOT p_stages <@ ARRAY['business_owner','manager','tenant_owner']::text[]
  OR p_stages[1:cardinality(p_stages)-1] && ARRAY['tenant_owner']::text[]
  OR p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{8,128}$'
 THEN RAISE EXCEPTION 'invalid_approval_route'; END IF;
 SELECT * INTO pol FROM core10.approval_policy_versions_v1 WHERE id=p_policy FOR UPDATE;
 IF NOT FOUND OR NOT core10.can_manage(pol.tenant_id,pol.business_id)
  OR NOT core10.can_approval_action_v1(pol.tenant_id,pol.business_id,'approval.decide')
 THEN RAISE EXCEPTION 'approval_route_denied'; END IF;
 SELECT * INTO old FROM core10.approval_routes_v1 WHERE policy_id=p_policy;
 IF FOUND THEN
  IF old.configured_by<>actor OR old.stages<>p_stages OR old.route_key<>p_key
  THEN RAISE EXCEPTION 'approval_route_replay_conflict'; END IF;
  RETURN old.policy_id;
 END IF;
 IF EXISTS(SELECT 1 FROM core10.approval_requests WHERE policy_id_v1=p_policy)
 THEN RAISE EXCEPTION 'approval_route_policy_in_use'; END IF;
 INSERT INTO core10.approval_routes_v1(policy_id,tenant_id,business_id,stages,configured_by,route_key)
 VALUES(p_policy,pol.tenant_id,pol.business_id,p_stages,actor,p_key);
 PERFORM core10._append_canonical_audit_v1(pol.tenant_id,pol.business_id,
  'approval_route',p_policy::text,'approval.route',actor,'route:'||p_policy::text,
  jsonb_build_object('policy_ref',p_policy::text,'stage_count',cardinality(p_stages)));
 RETURN p_policy;
END $fn$;

CREATE FUNCTION core10.delegate_approval_stage_v1(
 p_request bigint,p_delegate uuid,p_minutes integer,p_key text
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,core10 AS $fn$
DECLARE q core10.approval_requests%ROWTYPE;d core10.approval_delegations_v1%ROWTYPE;
 actor uuid:=core10.actor_uid();event_id bigint;until_at timestamptz;
BEGIN
 IF actor IS NULL OR p_request IS NULL OR p_delegate IS NULL
  OR p_minutes IS NULL OR p_minutes NOT BETWEEN 5 AND 1440
  OR p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{8,128}$'
 THEN RAISE EXCEPTION 'invalid_approval_delegation'; END IF;
 SELECT * INTO q FROM core10.approval_requests WHERE id=p_request FOR UPDATE;
 IF NOT FOUND OR q.status<>'pending' OR q.policy_id_v1 IS NULL OR
    q.expires_at_v1<=clock_timestamp()
 THEN RAISE EXCEPTION 'approval_delegation_denied'; END IF;
 IF NOT core10.can_approval_action_v1(q.tenant_id,q.business_id,'approval.delegate')
   OR NOT EXISTS(SELECT 1 FROM core10.business_members m
    WHERE m.tenant_id=q.tenant_id AND m.business_id=q.business_id
      AND m.user_id=actor AND m.role='business_owner' AND m.active
      AND (m.valid_until IS NULL OR m.valid_until>statement_timestamp()))
   OR p_delegate=q.created_by OR p_delegate=actor
   OR NOT EXISTS(SELECT 1 FROM core10.business_members m
    WHERE m.tenant_id=q.tenant_id AND m.business_id=q.business_id
      AND m.user_id=p_delegate AND m.role='manager' AND m.active
      AND (m.valid_until IS NULL OR m.valid_until>statement_timestamp()))
   OR NOT EXISTS(SELECT 1 FROM core10.approval_routes_v1 r
      WHERE r.policy_id=q.policy_id_v1 AND r.stages[1]='business_owner')
   OR EXISTS(SELECT 1 FROM core10.approval_stage_receipts_v1 WHERE request_id=p_request)
 THEN RAISE EXCEPTION 'approval_delegation_denied'; END IF;
 SELECT * INTO d FROM core10.approval_delegations_v1
 WHERE request_id=p_request AND stage_no=1;
 IF FOUND THEN
  IF d.granted_by<>actor OR d.delegated_to<>p_delegate
     OR d.delegation_key<>p_key OR d.revoked_at IS NOT NULL
  THEN RAISE EXCEPTION 'approval_delegation_replay_conflict'; END IF;
  SELECT id INTO event_id FROM core10.approval_events
  WHERE request_id=p_request AND idempotency_key=p_key AND action='delegate';
  RETURN event_id;
 END IF;
 until_at:=LEAST(q.expires_at_v1,clock_timestamp()+make_interval(mins=>p_minutes));
 IF until_at<=clock_timestamp() THEN RAISE EXCEPTION 'approval_delegation_expired'; END IF;
 INSERT INTO core10.approval_delegations_v1(request_id,tenant_id,business_id,
  granted_by,delegated_to,delegation_key,valid_until)
 VALUES(p_request,q.tenant_id,q.business_id,actor,p_delegate,p_key,until_at);
 INSERT INTO core10.approval_events(request_id,tenant_id,business_id,actor_id,action,idempotency_key)
 VALUES(p_request,q.tenant_id,q.business_id,actor,'delegate',p_key) RETURNING id INTO event_id;
 RETURN event_id;
END $fn$;

CREATE FUNCTION core10.revoke_approval_delegation_v1(
 p_request bigint,p_key text
) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,core10 AS $fn$
DECLARE q core10.approval_requests%ROWTYPE;d core10.approval_delegations_v1%ROWTYPE;
 actor uuid:=core10.actor_uid();event_id bigint;
BEGIN
 IF actor IS NULL OR p_request IS NULL OR p_key IS NULL
    OR p_key !~ '^[A-Za-z0-9_-]{8,128}$'
 THEN RAISE EXCEPTION 'invalid_approval_revocation'; END IF;
 SELECT * INTO q FROM core10.approval_requests WHERE id=p_request FOR UPDATE;
 SELECT * INTO d FROM core10.approval_delegations_v1 WHERE request_id=p_request;
 IF q.id IS NULL OR d.id IS NULL OR
    NOT (d.granted_by=actor OR core10.can_tenant(q.tenant_id))
    OR NOT core10.can_approval_action_v1(q.tenant_id,q.business_id,'approval.delegate')
 THEN RAISE EXCEPTION 'approval_revocation_denied'; END IF;
 SELECT id INTO event_id FROM core10.approval_events
 WHERE request_id=p_request AND idempotency_key=p_key AND actor_id=actor AND action='revoke';
 IF FOUND THEN RETURN event_id; END IF;
 IF d.revoked_at IS NOT NULL THEN RAISE EXCEPTION 'approval_delegation_already_revoked'; END IF;
 UPDATE core10.approval_delegations_v1
 SET revoked_at=clock_timestamp(),revoked_by=actor WHERE id=d.id;
 INSERT INTO core10.approval_events(request_id,tenant_id,business_id,actor_id,action,idempotency_key)
 VALUES(p_request,q.tenant_id,q.business_id,actor,'revoke',p_key) RETURNING id INTO event_id;
 RETURN event_id;
END $fn$;

CREATE FUNCTION core10.withdraw_typed_approval_v1(
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

-- Replace ONLY the existing decision RPC. Intermediate approvals write a receipt
-- and audit, but cannot set the request approved or post any domain stock/money.
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

-- No direct read rights on other makers' requests. Task RPC is only the next
-- authorized reviewer and excludes payload/tenant/actor personal metadata.
CREATE FUNCTION core10.my_routed_review_tasks_v1(p_business bigint)
RETURNS TABLE(request_id bigint,business_id bigint,domain text,action_code text,
 source_key text,source_version bigint,policy_version integer,
 stage_no integer,stage_total integer,expires_at timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $fn$
DECLARE tenant bigint;actor uuid:=core10.actor_uid();
BEGIN
 SELECT b.tenant_id INTO tenant FROM core10.businesses b WHERE b.id=p_business;
 IF actor IS NULL OR p_business IS NULL OR tenant IS NULL
  OR NOT core10.can_approval_action_v1(tenant,p_business,'approval.decide')
 THEN RAISE EXCEPTION 'reviewer_task_access_denied'; END IF;
 RETURN QUERY
 SELECT q.id,q.business_id,q.domain_v1,q.action_code_v1,q.source_key_v1,
  q.source_version_v1,q.policy_version_v1,
  (SELECT count(*)::integer+1 FROM core10.approval_stage_receipts_v1 s
    WHERE s.request_id=q.id) AS current_stage,
  cardinality(rt.stages),q.expires_at_v1
 FROM core10.approval_requests q
 JOIN core10.approval_routes_v1 rt ON rt.policy_id=q.policy_id_v1
   AND rt.tenant_id=q.tenant_id AND rt.business_id=q.business_id
 WHERE q.business_id=p_business AND q.tenant_id=tenant
  AND q.status='pending' AND q.expires_at_v1>statement_timestamp()
  AND q.created_by<>actor
  AND NOT EXISTS(SELECT 1 FROM core10.approval_stage_receipts_v1 s
    WHERE s.request_id=q.id AND s.actor_id=actor)
  AND (SELECT count(*) FROM core10.approval_stage_receipts_v1 s
    WHERE s.request_id=q.id)<cardinality(rt.stages)
  AND core10._can_review_stage_v1(q.id,
    (SELECT count(*)::integer+1 FROM core10.approval_stage_receipts_v1 s WHERE s.request_id=q.id))
 ORDER BY q.created_at,q.id LIMIT 100;
END $fn$;

REVOKE EXECUTE ON FUNCTION core10.configure_approval_route_v1(bigint,text[],text),
 core10.delegate_approval_stage_v1(bigint,uuid,integer,text),
 core10.revoke_approval_delegation_v1(bigint,text),
 core10.withdraw_typed_approval_v1(bigint,text),
 core10.my_routed_review_tasks_v1(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION core10.configure_approval_route_v1(bigint,text[],text),
 core10.delegate_approval_stage_v1(bigint,uuid,integer,text),
 core10.revoke_approval_delegation_v1(bigint,text),
 core10.withdraw_typed_approval_v1(bigint,text),
 core10.my_routed_review_tasks_v1(bigint) TO authenticated;
INSERT INTO core10.schema_migrations(version,name,checksum) VALUES(11,'0011_np01_gov002_routed_review','ae7dcfe0ff07013f567c0d1423abd3723e98c3032e1d63cd924c4f9a64c0e7c2');

-- CORE10 BASELINE SOURCE 0012_np01_gov002_scoped_reports.up.sql SHA256 8dc06969d64b6c636f645a350616b84dcfc7aed164713e20323bd7b5a5dcdb92
-- S1-c / GOV-002: one canonical, role-scoped reviewer reporting port.
-- Source: isolated GOV002 reporting concepts; no legacy demo view or duplicate store.
-- No direct operational stock/finance posting, no hosted apply without Owner GO.

CREATE FUNCTION core10.my_approval_status_v1(p_business bigint,p_limit integer DEFAULT 100)
RETURNS TABLE (
 request_id bigint,business_id bigint,domain text,action_code text,
 source_key text,source_version bigint,policy_version integer,
 created_at timestamptz,expires_at timestamptz,
 stored_status text,display_status text,required_checks integer,completed_checks integer,
 can_review_now boolean,is_maker boolean
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,core10 AS $fn$
DECLARE tenant bigint;actor uuid:=core10.actor_uid();
BEGIN
 IF actor IS NULL OR p_business IS NULL OR p_limit IS NULL
  OR p_limit NOT BETWEEN 1 AND 100
 THEN RAISE EXCEPTION 'approval_report_denied'; END IF;
 SELECT b.tenant_id INTO tenant FROM core10.businesses b WHERE b.id=p_business;
 IF tenant IS NULL OR NOT (
  core10.can_business(tenant,p_business)
  OR core10.can_tenant(tenant)
  OR core10.can_approval_action_v1(tenant,p_business,'approval.decide'))
 THEN RAISE EXCEPTION 'approval_report_denied'; END IF;
 RETURN QUERY
 SELECT q.id,q.business_id,q.domain_v1,q.action_code_v1,
  q.source_key_v1,q.source_version_v1,q.policy_version_v1,
  q.created_at,q.expires_at_v1,q.status,
  CASE
   WHEN q.status='pending' AND q.expires_at_v1<=statement_timestamp() THEN 'expired'
   WHEN q.status='pending' AND route.policy_id IS NOT NULL
    THEN 'awaiting_stage_'||(rc.completed+1)::text
   ELSE q.status END AS display_status,
  COALESCE(cardinality(route.stages),1)::integer AS required_checks,
  rc.completed,
  (q.status='pending' AND q.expires_at_v1>statement_timestamp()
   AND route.policy_id IS NOT NULL
   AND rc.completed<cardinality(route.stages)
   AND core10._can_review_stage_v1(q.id,rc.completed+1)),
  q.created_by=actor
 FROM core10.approval_requests q
 LEFT JOIN core10.approval_routes_v1 route
  ON route.policy_id=q.policy_id_v1 AND route.tenant_id=q.tenant_id
    AND route.business_id=q.business_id
 CROSS JOIN LATERAL (
  SELECT count(*)::integer AS completed
  FROM core10.approval_stage_receipts_v1 s WHERE s.request_id=q.id
 ) rc
 WHERE q.tenant_id=tenant AND q.business_id=p_business AND q.policy_id_v1 IS NOT NULL
  AND (
   core10.can_manage(q.tenant_id,q.business_id)
   OR (q.created_by=actor AND core10.can_business(q.tenant_id,q.business_id))
   OR (q.status='pending' AND route.policy_id IS NOT NULL
       AND rc.completed<cardinality(route.stages)
       AND core10._can_review_stage_v1(q.id,rc.completed+1))
  )
 ORDER BY q.created_at DESC,q.id DESC LIMIT p_limit;
END $fn$;
REVOKE ALL ON FUNCTION core10.my_approval_status_v1(bigint,integer)
 FROM PUBLIC,authenticated;
GRANT EXECUTE ON FUNCTION core10.my_approval_status_v1(bigint,integer)
 TO authenticated;

-- Activity is projected from the one canonical approval-event journal JOINED
-- to its 0008 canonical audit event, never an extra event/audit store.
-- No payload or actor PII is returned to non-owner reviewer clients.
CREATE FUNCTION core10.my_approval_activity_v1(p_business bigint,p_limit integer DEFAULT 100)
RETURNS TABLE (
 event_id bigint,business_id bigint,request_id bigint,
 action text,occurred_at timestamptz,stage_no integer,
 approval_status text,audit_event_id bigint
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path=pg_catalog,core10 AS $fn$
DECLARE tenant bigint;actor uuid:=core10.actor_uid();
BEGIN
 IF actor IS NULL OR p_business IS NULL OR p_limit IS NULL
  OR p_limit NOT BETWEEN 1 AND 100
 THEN RAISE EXCEPTION 'approval_report_denied'; END IF;
 SELECT b.tenant_id INTO tenant FROM core10.businesses b WHERE b.id=p_business;
 IF tenant IS NULL OR NOT (
  core10.can_business(tenant,p_business)
  OR core10.can_tenant(tenant)
  OR core10.can_approval_action_v1(tenant,p_business,'approval.export')
  OR core10.can_approval_action_v1(tenant,p_business,'approval.decide'))
 THEN RAISE EXCEPTION 'approval_report_denied'; END IF;
 RETURN QUERY
 SELECT e.id,e.business_id,e.request_id,e.action,e.created_at,
        st.stage_no,q.status,a.id
 FROM core10.approval_events e
 JOIN core10.approval_requests q
   ON q.id=e.request_id AND q.tenant_id=e.tenant_id
   AND q.business_id=e.business_id
 JOIN core10.canonical_audit_events_v1 a
   ON a.source_domain='approval' AND a.source_ref=e.id::text
   AND a.tenant_id=e.tenant_id AND a.business_id=e.business_id
   AND a.action='approval.'||e.action
 LEFT JOIN core10.approval_stage_receipts_v1 st
   ON st.event_id=e.id AND st.request_id=e.request_id
 WHERE e.business_id=p_business AND e.tenant_id=tenant
  AND (
   core10.can_manage(q.tenant_id,q.business_id)
   OR (q.created_by=actor AND core10.can_business(q.tenant_id,q.business_id))
   OR (q.status='pending' AND EXISTS (
     SELECT 1 FROM core10.approval_routes_v1 route
     WHERE route.policy_id=q.policy_id_v1
       AND core10._can_review_stage_v1(q.id,
        (SELECT count(*)::integer+1 FROM core10.approval_stage_receipts_v1 s
          WHERE s.request_id=q.id))
   ))
  )
 ORDER BY e.created_at DESC,e.id DESC LIMIT p_limit;
END $fn$;
REVOKE ALL ON FUNCTION core10.my_approval_activity_v1(bigint,integer)
 FROM PUBLIC,authenticated;
GRANT EXECUTE ON FUNCTION core10.my_approval_activity_v1(bigint,integer)
 TO authenticated;
INSERT INTO core10.schema_migrations(version,name,checksum) VALUES(12,'0012_np01_gov002_scoped_reports','8dc06969d64b6c636f645a350616b84dcfc7aed164713e20323bd7b5a5dcdb92');
