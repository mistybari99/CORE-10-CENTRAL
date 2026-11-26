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
