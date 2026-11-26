-- CORE10 baseline20 v1; ordered, lossless consolidation. Fresh empty schema only.
-- CORE10 BASELINE SOURCE 0314_np03a_w02_custody_registry.up.sql SHA256 47f26df8d50c05c9ce18647667515da92ca354b76305b450100441820eb6c191
-- NP03A: evidence-only W-02 registry. No API publication or inventory mutations.
-- The Stock/transfer tables remain the source of all movement quantities.
CREATE TABLE core10.w02_pairs_v1 (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL,
 business_id bigint NOT NULL,
 from_site_id bigint NOT NULL,
 to_site_id bigint NOT NULL,
 crate_item_id bigint NOT NULL,
 tray_item_id bigint NOT NULL,
 CHECK (from_site_id<>to_site_id AND crate_item_id<>tray_item_id),
 FOREIGN KEY (from_site_id,tenant_id,business_id) REFERENCES core10.sites(id,tenant_id,business_id),
 FOREIGN KEY (to_site_id,tenant_id,business_id) REFERENCES core10.sites(id,tenant_id,business_id),
 FOREIGN KEY (crate_item_id,tenant_id,business_id) REFERENCES core10.items(id,tenant_id,business_id),
 FOREIGN KEY (tray_item_id,tenant_id,business_id) REFERENCES core10.items(id,tenant_id,business_id),
 UNIQUE (id,business_id)
);
CREATE UNIQUE INDEX w02_pairs_unordered_v1 ON core10.w02_pairs_v1
 (business_id,least(from_site_id,to_site_id),greatest(from_site_id,to_site_id));
CREATE INDEX w02_transfer_pair_reads_v1 ON core10.stock_transfers_v1
 (business_id,least(source_site_id,destination_site_id),greatest(source_site_id,destination_site_id),id);
CREATE INDEX w02_posting_transfer_reads_v1 ON core10.stock_movements (transfer_id) WHERE transfer_id IS NOT NULL;
CREATE INDEX w02_posted_command_reads_v1 ON core10.inventory_commands_v1 (stock_ref)
 WHERE kind='transfer' AND status='posted';

CREATE TABLE core10.w02_keys_v1 (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 pair_id bigint NOT NULL REFERENCES core10.w02_pairs_v1(id),
 role text NOT NULL CHECK (role IN ('openingReviewer','challanRegistrar','counter','witness')),
 actor_id uuid NOT NULL,
 spki_hex text NOT NULL CHECK (spki_hex ~ '^302a300506032b6570032100[0-9a-f]{64}$'),
 UNIQUE (pair_id,spki_hex)
);
CREATE INDEX w02_keys_role_v1 ON core10.w02_keys_v1(pair_id,role,id DESC);
CREATE TABLE core10.w02_key_revocations_v1 (
 key_id bigint PRIMARY KEY REFERENCES core10.w02_keys_v1(id),
 revoked_at timestamptz NOT NULL DEFAULT statement_timestamp()
);

CREATE TABLE core10.w02_closes_v1 (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 pair_id bigint NOT NULL REFERENCES core10.w02_pairs_v1(id),
 previous_id bigint,
 record_ref text NOT NULL CHECK (record_ref ~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,119}$'),
 approved_by uuid NOT NULL,
 closed_at timestamptz NOT NULL CHECK (isfinite(closed_at)),
 publication_xid xid8 NOT NULL DEFAULT pg_current_xact_id(),
 crates bigint NOT NULL CHECK (crates BETWEEN 0 AND 9007199254740991),
 trays bigint NOT NULL CHECK (trays BETWEEN 0 AND 9007199254740991),
 source_sha256 text NOT NULL CHECK (source_sha256 ~ '^[0-9a-f]{64}$'),
 UNIQUE (pair_id,id),
 UNIQUE (pair_id,record_ref),
 UNIQUE NULLS NOT DISTINCT (pair_id,previous_id),
 FOREIGN KEY (pair_id,previous_id) REFERENCES core10.w02_closes_v1(pair_id,id),
 CHECK (previous_id IS NULL OR previous_id<id)
);

CREATE TABLE core10.w02_close_transfers_v1 (
 pair_id bigint NOT NULL,
 close_id bigint NOT NULL,
 stock_ref bigint NOT NULL REFERENCES core10.stock_transfers_v1(id),
 PRIMARY KEY (pair_id,stock_ref),
 FOREIGN KEY (pair_id,close_id) REFERENCES core10.w02_closes_v1(pair_id,id)
);

CREATE TABLE core10.w02_challan_lines_v1 (
 pair_id bigint NOT NULL,
 business_id bigint NOT NULL,
 stock_ref bigint PRIMARY KEY REFERENCES core10.stock_transfers_v1(id),
 challan_ref text NOT NULL CHECK (challan_ref ~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,119}$'),
 line_ref text NOT NULL CHECK (line_ref ~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,119}$'),
 source_sha256 text NOT NULL CHECK (source_sha256 ~ '^[0-9a-f]{64}$'),
 FOREIGN KEY (pair_id,business_id) REFERENCES core10.w02_pairs_v1(id,business_id),
 UNIQUE (business_id,challan_ref,line_ref)
);

ALTER TABLE core10.w02_pairs_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE core10.w02_keys_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE core10.w02_key_revocations_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE core10.w02_closes_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE core10.w02_close_transfers_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE core10.w02_challan_lines_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON core10.w02_pairs_v1,core10.w02_keys_v1,core10.w02_key_revocations_v1,
 core10.w02_closes_v1,core10.w02_close_transfers_v1,core10.w02_challan_lines_v1 FROM PUBLIC,authenticated;

CREATE FUNCTION core10._w02_immutable_v1() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog,core10 AS $$
BEGIN
 RAISE EXCEPTION 'W02_EVIDENCE_IMMUTABLE';
END $$;

DO $w02$
DECLARE name text;
BEGIN
 FOREACH name IN ARRAY ARRAY['w02_pairs_v1','w02_keys_v1','w02_key_revocations_v1',
  'w02_closes_v1','w02_close_transfers_v1','w02_challan_lines_v1'] LOOP
  EXECUTE format('CREATE TRIGGER w02_immutable BEFORE UPDATE OR DELETE OR TRUNCATE ON core10.%I
   FOR EACH STATEMENT EXECUTE FUNCTION core10._w02_immutable_v1()',name);
 END LOOP;
END $w02$;

CREATE FUNCTION core10._w02_check_transfer_scope_v1() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog,core10 AS $$
BEGIN
 IF NOT EXISTS (
  SELECT 1 FROM core10.w02_pairs_v1 p JOIN core10.stock_transfers_v1 t ON t.id=NEW.stock_ref
  WHERE p.id=NEW.pair_id AND t.tenant_id=p.tenant_id AND t.business_id=p.business_id
    AND t.item_id IN (p.crate_item_id,p.tray_item_id)
    AND least(t.source_site_id,t.destination_site_id)=least(p.from_site_id,p.to_site_id)
    AND greatest(t.source_site_id,t.destination_site_id)=greatest(p.from_site_id,p.to_site_id)
 ) THEN RAISE EXCEPTION 'W02_TRANSFER_SCOPE_MISMATCH'; END IF;
 IF TG_TABLE_NAME='w02_close_transfers_v1' THEN
  IF NOT EXISTS (
   SELECT 1 FROM core10.w02_closes_v1 c JOIN core10.stock_transfers_v1 t ON t.id=NEW.stock_ref
   WHERE c.id=NEW.close_id AND c.pair_id=NEW.pair_id
    AND c.publication_xid=pg_current_xact_id() AND t.created_at<c.closed_at
  ) THEN RAISE EXCEPTION 'W02_CLOSE_COVERAGE_OUTSIDE_PUBLICATION'; END IF;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER w02_challan_scope BEFORE INSERT ON core10.w02_challan_lines_v1
 FOR EACH ROW EXECUTE FUNCTION core10._w02_check_transfer_scope_v1();
CREATE TRIGGER w02_covered_transfer_scope BEFORE INSERT ON core10.w02_close_transfers_v1
 FOR EACH ROW EXECUTE FUNCTION core10._w02_check_transfer_scope_v1();
CREATE FUNCTION core10._w02_stamp_close_v1() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog,core10 AS $$
BEGIN
 NEW.publication_xid:=pg_current_xact_id();
 IF NEW.previous_id IS NOT NULL AND NOT EXISTS (
  SELECT 1 FROM core10.w02_closes_v1 previous
   WHERE previous.pair_id=NEW.pair_id AND previous.id=NEW.previous_id AND previous.closed_at<NEW.closed_at
 ) THEN RAISE EXCEPTION 'W02_CLOSE_ORDER_INVALID'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER w02_stamp_close BEFORE INSERT ON core10.w02_closes_v1
 FOR EACH ROW EXECUTE FUNCTION core10._w02_stamp_close_v1();
REVOKE ALL ON FUNCTION core10._w02_immutable_v1(),core10._w02_check_transfer_scope_v1(),core10._w02_stamp_close_v1() FROM PUBLIC,authenticated;

-- STABLE gives scope, inventory, registry and revision the caller statement's
-- single MVCC snapshot. Compare exact set membership, never max(id) or dates.
CREATE FUNCTION core10.w02_custody_snapshot_v1(p_business bigint,p_from_site bigint,p_to_site bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE p core10.w02_pairs_v1%ROWTYPE; t bigint; site bigint; master jsonb; transfer jsonb;
 scope jsonb; prior jsonb; keys jsonb; ledger jsonb; state jsonb;
BEGIN
 SELECT tenant_id INTO t FROM core10.businesses WHERE id=p_business;
 IF core10.actor_uid() IS NULL OR t IS NULL OR p_from_site IS NULL OR p_to_site IS NULL
  OR p_from_site=p_to_site
  OR NOT core10.can_site(t,p_business,p_from_site,'stock.read')
  OR NOT core10.can_site(t,p_business,p_to_site,'stock.read')
 THEN RAISE EXCEPTION 'W02_SCOPE_DENIED' USING ERRCODE='42501'; END IF;
 FOREACH site IN ARRAY ARRAY[p_from_site,p_to_site] LOOP
  master:=core10._control_resolve_v1(p_business,'inventory.stock_event',site);
  transfer:=core10._control_resolve_v1(p_business,'inventory.transfer',site);
  IF (master->>'enabled')::boolean IS DISTINCT FROM true OR (transfer->>'enabled')::boolean IS DISTINCT FROM true
     OR (transfer->'params'->>'allow_cross_site')::boolean IS DISTINCT FROM true
  THEN RETURN jsonb_build_object('status','CONTROL_DISABLED'); END IF;
 END LOOP;
 SELECT * INTO p FROM core10.w02_pairs_v1
 WHERE business_id=p_business AND tenant_id=t AND from_site_id=p_from_site AND to_site_id=p_to_site;
 IF NOT FOUND THEN RETURN jsonb_build_object('status','PAIR_NOT_CONFIGURED'); END IF;
 scope:=jsonb_build_object('tenantId',t,'businessId',p_business,'fromSiteId',p_from_site,'toSiteId',p_to_site);
 SELECT jsonb_build_object('record',c.record_ref,'actorId',c.approved_by,
  'at',to_char(c.closed_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
  'crates',c.crates,'trays',c.trays,'sourceSha256',c.source_sha256)
 INTO prior FROM core10.w02_closes_v1 c WHERE c.pair_id=p.id ORDER BY c.id DESC LIMIT 1;
 -- Resolve the most recently published key first. Revocation cannot restore an older key.
 SELECT coalesce(jsonb_object_agg(k.role,jsonb_build_object('id',k.id,'actorId',k.actor_id,'spkiHex',k.spki_hex)),'{}')
 INTO keys FROM (SELECT DISTINCT ON (role) * FROM core10.w02_keys_v1 WHERE pair_id=p.id ORDER BY role,id DESC) k
 WHERE NOT EXISTS (SELECT 1 FROM core10.w02_key_revocations_v1 r WHERE r.key_id=k.id);
 WITH pending AS (
   SELECT s.* FROM core10.stock_transfers_v1 s
   WHERE s.tenant_id=t AND s.business_id=p_business AND s.item_id IN (p.crate_item_id,p.tray_item_id)
    AND least(s.source_site_id,s.destination_site_id)=least(p_from_site,p_to_site)
    AND greatest(s.source_site_id,s.destination_site_id)=greatest(p_from_site,p_to_site)
    AND NOT EXISTS (SELECT 1 FROM core10.w02_close_transfers_v1 covered WHERE covered.pair_id=p.id AND covered.stock_ref=s.id)
   ORDER BY s.id LIMIT 201
 )
 SELECT coalesce(jsonb_agg(jsonb_build_object(
   'stock_ref',s.id,'source_site_id',s.source_site_id,'destination_site_id',s.destination_site_id,
   'item_id',s.item_id,'quantity',s.quantity,'command',command.proof,
   'postings',posting.proof,'challan',CASE WHEN l.stock_ref IS NOT NULL THEN
     jsonb_build_object('record',l.challan_ref,'line',l.line_ref,'sourceSha256',l.source_sha256) END
 ) ORDER BY s.id),'[]') INTO ledger
 FROM pending s
 LEFT JOIN core10.w02_challan_lines_v1 l ON l.pair_id=p.id AND l.stock_ref=s.id
 LEFT JOIN LATERAL (
  SELECT CASE WHEN count(*)=1 THEN jsonb_agg(jsonb_build_object(
   'command_id',c.id,'created_by',c.created_by,'confirmed_by',c.confirmed_by,'posted_by',c.posted_by,
   'posted_at',to_char(c.posted_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
   'auditDigest',a.event_digest))->0 END AS proof
  FROM core10.inventory_commands_v1 c
  JOIN core10.canonical_audit_events_v1 a
    ON a.tenant_id=t AND a.business_id=p_business AND a.source_domain='inventory'
    AND a.source_ref='command:'||c.id||':posted' AND a.action='inventory.command_posted'
    AND a.payload->>'stock_ref'=s.id::text
  WHERE c.kind='transfer' AND c.status='posted' AND c.tenant_id=t AND c.business_id=p_business
   AND c.stock_ref=s.id AND c.item_id=s.item_id AND c.quantity=s.quantity
   AND c.source_location=s.source_location_id AND c.destination_location=s.destination_location_id
   AND c.source_site_id=s.source_site_id AND c.destination_site_id=s.destination_site_id
 ) command ON true
 LEFT JOIN LATERAL (
  SELECT CASE WHEN count(*)=2
   AND count(*) FILTER (WHERE m.site_id=s.source_site_id AND m.location_id=s.source_location_id AND m.delta= -s.quantity)=1
   AND count(*) FILTER (WHERE m.site_id=s.destination_site_id AND m.location_id=s.destination_location_id AND m.delta=s.quantity)=1
   THEN jsonb_agg(m.id ORDER BY m.id) END AS proof
  FROM core10.stock_movements m WHERE m.transfer_id=s.id AND m.tenant_id=t AND m.business_id=p_business AND m.item_id=s.item_id
 ) posting ON true;
 IF jsonb_array_length(ledger)>200 THEN RETURN jsonb_build_object('status','WINDOW_INCOMPLETE'); END IF;
 state:=jsonb_build_object('scope',scope,'items',jsonb_build_object('crates',p.crate_item_id,'trays',p.tray_item_id),
  'priorClose',prior,'keys',keys,'movements',ledger);
 RETURN state || jsonb_build_object('status','SNAPSHOT',
  'revision',encode(sha256(convert_to(jsonb_build_array('CORE10.W02.SNAPSHOT.V1',state)::text,'UTF8')),'hex'));
END $$;
REVOKE ALL ON FUNCTION core10.w02_custody_snapshot_v1(bigint,bigint,bigint) FROM PUBLIC,authenticated;
GRANT EXECUTE ON FUNCTION core10.w02_custody_snapshot_v1(bigint,bigint,bigint) TO authenticated;
INSERT INTO core10.schema_migrations(version,name,checksum) VALUES(314,'0314_np03a_w02_custody_registry','47f26df8d50c05c9ce18647667515da92ca354b76305b450100441820eb6c191');

-- CORE10 BASELINE SOURCE 0315_np03a_w02_close_publication.up.sql SHA256 58b03a89e06ddc87bfc2094ea41142a74058e41b1e22270b29b07864e19d1aaf
-- NP03A W02 evidence publication Draft. This path records an approved close
-- and its evidence. It never writes a Stock balance, movement or journal.
-- The sole caller is a trusted server that verifies the signed envelope before
-- invoking the private function. No application-role grant is installed.
CREATE TABLE core10.w02_close_publications_v1 (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 pair_id bigint NOT NULL,
 close_id bigint NOT NULL UNIQUE,
 actor_id uuid NOT NULL,
 request_key text NOT NULL CHECK (request_key ~ '^[A-Za-z0-9_-]{8,100}$'),
 evidence jsonb NOT NULL CHECK (jsonb_typeof(evidence)='object' AND octet_length(evidence::text)<=262144),
 source_sha256 text NOT NULL CHECK (source_sha256 ~ '^[0-9a-f]{64}$'),
 observed_revision text NOT NULL CHECK (observed_revision ~ '^[0-9a-f]{64}$'),
 verified_evidence_sha256 text NOT NULL CHECK (verified_evidence_sha256 ~ '^[0-9a-f]{64}$'),
 audit_event_id bigint NOT NULL UNIQUE REFERENCES core10.canonical_audit_events_v1(id),
 FOREIGN KEY (pair_id,close_id) REFERENCES core10.w02_closes_v1(pair_id,id),
 UNIQUE (pair_id,request_key)
);
ALTER TABLE core10.w02_close_publications_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON core10.w02_close_publications_v1 FROM PUBLIC,authenticated;
CREATE TRIGGER w02_immutable BEFORE UPDATE OR DELETE OR TRUNCATE ON core10.w02_close_publications_v1
 FOR EACH STATEMENT EXECUTE FUNCTION core10._w02_immutable_v1();

CREATE FUNCTION core10._w02_close_receipt_v1(p core10.w02_close_publications_v1,p_record text,p_replayed boolean)
RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=pg_catalog,core10 AS $$
 SELECT jsonb_build_object('status','EVIDENCE_PUBLISHED','receiptId',p.id,'closeRecord',p_record,
  'stockRevision',p.observed_revision,'auditEventId',p.audit_event_id,'replayed',p_replayed,'canPost',false)
$$;
REVOKE ALL ON FUNCTION core10._w02_close_receipt_v1(core10.w02_close_publications_v1,text,boolean) FROM PUBLIC,authenticated;

CREATE FUNCTION core10._w02_publish_verified_close_v1(
 p_business bigint,p_from_site bigint,p_to_site bigint,p_request text,p_evidence jsonb,p_verification jsonb
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10
SET lock_timeout='500ms' AS $$
DECLARE
 actor uuid:=core10.actor_uid();
 pair core10.w02_pairs_v1%ROWTYPE; saved core10.w02_close_publications_v1%ROWTYPE;
 state jsonb; control jsonb; measured jsonb; content_sha text; record_ref text; count_at timestamptz;
 crates bigint; trays bigint; wanted_crates numeric; wanted_trays numeric; last_close bigint;
 new_close bigint; event_id bigint;
BEGIN
 SELECT * INTO pair FROM core10.w02_pairs_v1
 WHERE business_id=p_business AND from_site_id=p_from_site AND to_site_id=p_to_site;
 IF actor IS NULL OR pair.id IS NULL OR NOT core10.can_manage(pair.tenant_id,p_business)
    OR NOT core10.can_site(pair.tenant_id,p_business,p_from_site,'stock.read')
    OR NOT core10.can_site(pair.tenant_id,p_business,p_to_site,'stock.read')
 THEN RAISE EXCEPTION 'W02_PUBLISH_SCOPE_DENIED' USING ERRCODE='42501'; END IF;
 IF p_request IS NULL OR p_request !~ '^[A-Za-z0-9_-]{8,100}$'
    OR jsonb_typeof(p_evidence) IS DISTINCT FROM 'object' OR octet_length(p_evidence::text)>262144
 THEN RAISE EXCEPTION 'W02_INVALID_PUBLICATION'; END IF;
 content_sha:=encode(sha256(convert_to(p_evidence::text,'UTF8')),'hex');

 -- For new publications lock out changing evidence and Stock transfers only
 -- during the short save transaction. Never wait or hold these locks while
 -- the server is verifying signatures. The stock posting functions are unchanged.
 IF p_verification IS NOT NULL THEN
  BEGIN
   LOCK TABLE core10.w02_closes_v1,core10.w02_close_transfers_v1,core10.w02_close_publications_v1
    IN SHARE ROW EXCLUSIVE MODE NOWAIT;
   LOCK TABLE core10.stock_transfers_v1,core10.w02_keys_v1,core10.w02_key_revocations_v1,
    core10.w02_challan_lines_v1,core10.control_setting_versions_v1 IN SHARE MODE NOWAIT;
  EXCEPTION WHEN lock_not_available THEN
   RAISE EXCEPTION 'W02_PUBLICATION_RETRY' USING ERRCODE='55P03';
  END;
 END IF;
 IF core10.actor_uid() IS DISTINCT FROM actor OR NOT core10.can_manage(pair.tenant_id,p_business)
    OR NOT core10.can_site(pair.tenant_id,p_business,p_from_site,'stock.read')
    OR NOT core10.can_site(pair.tenant_id,p_business,p_to_site,'stock.read')
 THEN RAISE EXCEPTION 'W02_PUBLISH_SCOPE_DENIED' USING ERRCODE='42501'; END IF;
 SELECT * INTO saved FROM core10.w02_close_publications_v1 WHERE pair_id=pair.id AND request_key=p_request;
 IF FOUND THEN
  IF saved.actor_id<>actor OR saved.source_sha256<>content_sha
  THEN RAISE EXCEPTION 'W02_PUBLICATION_REPLAY_CONFLICT'; END IF;
  SELECT c.record_ref INTO record_ref FROM core10.w02_closes_v1 c WHERE c.id=saved.close_id;
  RETURN core10._w02_close_receipt_v1(saved,record_ref,true);
 END IF;
 IF p_verification IS NULL THEN RETURN NULL; END IF;

 state:=core10.w02_custody_snapshot_v1(p_business,p_from_site,p_to_site);
 IF state->>'status' IS DISTINCT FROM 'SNAPSHOT'
    OR state->>'revision' IS DISTINCT FROM p_verification->>'stockRevision'
    OR state->>'revision' IS DISTINCT FROM p_evidence#>>'{count,payload,stockRevision}'
 THEN RAISE EXCEPTION 'W02_STALE_CANONICAL_REVISION'; END IF;
 IF state->'priorClose' IS NOT DISTINCT FROM 'null'::jsonb
    OR state#>>'{keys,openingReviewer,actorId}' IS DISTINCT FROM actor::text
    OR state#>>'{keys,counter,actorId}' IS NULL OR state#>>'{keys,witness,actorId}' IS NULL
    OR actor::text IN (state#>>'{keys,counter,actorId}',state#>>'{keys,witness,actorId}')
    OR state#>>'{keys,challanRegistrar,actorId}' IS NULL
    OR (p_verification->>'evidenceDigest') IS NULL
    OR p_verification->>'evidenceDigest' !~ '^[0-9a-f]{64}$'
 THEN RAISE EXCEPTION 'W02_PUBLISH_APPROVAL_REQUIRED' USING ERRCODE='42501'; END IF;
 SELECT jsonb_agg(jsonb_build_array(
   jsonb_build_array(m->'enabled',m->'source',m->'version',m->'stages',NULL),
   jsonb_build_array(k->'enabled',k->'source',k->'version',k->'stages',k->'params'->'allow_cross_site')
 ) ORDER BY sites.ordinality) INTO control
 FROM unnest(ARRAY[p_from_site,p_to_site]) WITH ORDINALITY sites(id,ordinality)
 CROSS JOIN LATERAL core10._control_resolve_v1(p_business,'inventory.stock_event',sites.id) m
 CROSS JOIN LATERAL core10._control_resolve_v1(p_business,'inventory.transfer',sites.id) k;
 IF control IS DISTINCT FROM p_verification->'controlEvidence'
 THEN RAISE EXCEPTION 'W02_STALE_CONTROL_POLICY'; END IF;

 measured:=p_evidence#>'{count,payload}';
 record_ref:=measured->>'record';
 IF record_ref IS NULL OR record_ref !~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,119}$'
   OR (measured->>'crates') IS NULL OR measured->>'crates' !~ '^\d{1,16}$'
   OR (measured->>'trays') IS NULL OR measured->>'trays' !~ '^\d{1,16}$'
   OR (measured->>'at') IS NULL OR measured->>'at' !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T'
 THEN RAISE EXCEPTION 'W02_INVALID_PUBLICATION'; END IF;
 count_at:=(measured->>'at')::timestamptz;
 crates:=(measured->>'crates')::bigint;
 trays:=(measured->>'trays')::bigint;
 IF NOT isfinite(count_at) OR count_at>clock_timestamp()
    OR count_at<=(state#>>'{priorClose,at}')::timestamptz
    OR EXISTS (SELECT 1 FROM jsonb_array_elements(state->'movements') m
         WHERE m->'command' IS NOT DISTINCT FROM 'null'::jsonb
            OR m->'postings' IS NOT DISTINCT FROM 'null'::jsonb
            OR m->'challan' IS NOT DISTINCT FROM 'null'::jsonb
            OR (m#>>'{command,posted_at}')::timestamptz>=count_at)
 THEN RAISE EXCEPTION 'W02_CLOSE_MOVEMENT_PROOF_REQUIRED'; END IF;
 SELECT (state#>>'{priorClose,crates}')::numeric + coalesce(sum(delta) FILTER (WHERE item=pair.crate_item_id),0),
        (state#>>'{priorClose,trays}')::numeric + coalesce(sum(delta) FILTER (WHERE item=pair.tray_item_id),0)
 INTO wanted_crates,wanted_trays FROM (
  SELECT (m->>'item_id')::bigint item,
    (CASE WHEN (m->>'source_site_id')::bigint=p_from_site THEN 1 ELSE -1 END)*(m->>'quantity')::numeric delta
  FROM jsonb_array_elements(state->'movements') m
 ) counted;
 IF wanted_crates IS DISTINCT FROM crates::numeric OR wanted_trays IS DISTINCT FROM trays::numeric
 THEN RAISE EXCEPTION 'W02_WITNESSED_COUNT_MISMATCH'; END IF;

 SELECT c.id INTO STRICT last_close FROM core10.w02_closes_v1 c
 WHERE c.pair_id=pair.id AND c.record_ref=state#>>'{priorClose,record}';
 INSERT INTO core10.w02_closes_v1(pair_id,previous_id,record_ref,approved_by,closed_at,crates,trays,source_sha256)
 VALUES(pair.id,last_close,record_ref,actor,count_at,crates,trays,content_sha) RETURNING id INTO new_close;
 INSERT INTO core10.w02_close_transfers_v1(pair_id,close_id,stock_ref)
 SELECT pair.id,new_close,(m->>'stock_ref')::bigint FROM jsonb_array_elements(state->'movements') m;
 event_id:=core10._append_canonical_audit_v1(pair.tenant_id,p_business,'paperops_w02',
  'close:'||new_close,'w02.close_published',actor,'w02:'||pair.id||':'||p_request,
  jsonb_build_object('pair_id',pair.id,'close_id',new_close,'stock_revision',state->>'revision',
   'source_sha256',content_sha,'verified_evidence_sha256',p_verification->>'evidenceDigest',
   'control_evidence',control));
 INSERT INTO core10.w02_close_publications_v1(pair_id,close_id,actor_id,request_key,evidence,source_sha256,
  observed_revision,verified_evidence_sha256,audit_event_id)
 VALUES(pair.id,new_close,actor,p_request,p_evidence,content_sha,state->>'revision',p_verification->>'evidenceDigest',event_id)
 RETURNING * INTO saved;
 RETURN core10._w02_close_receipt_v1(saved,record_ref,false);
EXCEPTION WHEN lock_not_available THEN
 RAISE EXCEPTION 'W02_PUBLICATION_RETRY' USING ERRCODE='55P03';
END $$;
REVOKE ALL ON FUNCTION core10._w02_publish_verified_close_v1(bigint,bigint,bigint,text,jsonb,jsonb) FROM PUBLIC,authenticated;
INSERT INTO core10.schema_migrations(version,name,checksum) VALUES(315,'0315_np03a_w02_close_publication','58b03a89e06ddc87bfc2094ea41142a74058e41b1e22270b29b07864e19d1aaf');
