-- Disposable PG17 contract fixture. NOT the canonical Auth or Control implementation.
CREATE SCHEMA core10;
CREATE ROLE anon; CREATE ROLE authenticated;
CREATE TABLE core10.integration_account_v1(id bigint PRIMARY KEY,tenant_id bigint NOT NULL,business_id bigint NOT NULL,mode text NOT NULL,status text NOT NULL);
CREATE TABLE core10.integration_outbox_v1(id bigint PRIMARY KEY,account_id bigint NOT NULL REFERENCES core10.integration_account_v1(id),
 state text NOT NULL DEFAULT 'queued',is_dry_run boolean NOT NULL,attempts integer NOT NULL DEFAULT 0,max_attempts integer NOT NULL DEFAULT 5,
 next_try_at timestamptz NOT NULL DEFAULT clock_timestamp(),lease_until timestamptz,provider_ref text,last_error_code text);
CREATE TABLE core10.fixture_grants(actor uuid,tenant_id bigint,business_id bigint,PRIMARY KEY(actor,tenant_id,business_id));
CREATE TABLE core10.fixture_policy(business_id bigint PRIMARY KEY,enabled boolean,stages integer);
CREATE FUNCTION core10.actor_uid() RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT nullif(current_setting('fixture.actor',true),'')::uuid $$;
CREATE FUNCTION core10.can_manage(t bigint,b bigint) RETURNS boolean LANGUAGE sql STABLE AS $$ SELECT EXISTS(SELECT 1 FROM core10.fixture_grants g WHERE g.actor=core10.actor_uid() AND g.tenant_id=t AND g.business_id=b) $$;
CREATE FUNCTION core10._control_resolve_v1(b bigint,k text,s bigint) RETURNS jsonb LANGUAGE sql STABLE AS $$ SELECT jsonb_build_object('enabled',enabled,'stages',stages) FROM core10.fixture_policy WHERE business_id=b AND k='integration.dispatch' AND s IS NULL $$;
INSERT INTO core10.integration_account_v1 VALUES(1,1,10,'dry_run','connected'),(2,2,20,'dry_run','connected'),(3,1,10,'live','connected');
INSERT INTO core10.fixture_grants VALUES('00000000-0000-0000-0000-000000000001',1,10),('00000000-0000-0000-0000-000000000002',1,10);
INSERT INTO core10.fixture_policy VALUES(10,true,0),(20,true,0);
INSERT INTO core10.integration_outbox_v1(id,account_id,is_dry_run,max_attempts) VALUES(1,1,true,3),(2,1,false,3),(3,2,true,3),(4,1,true,1);
