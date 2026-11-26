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
