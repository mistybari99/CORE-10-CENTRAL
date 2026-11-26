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
