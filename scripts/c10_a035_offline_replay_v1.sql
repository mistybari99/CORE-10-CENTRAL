-- C10-A035 offline STOCK DRAFT (NO POST) server protocol. Disposable PG17 only.
-- No offline write is trusted merely because it was recorded on a device.
-- Requires a fresh signed session, live DB scope, conflict-free ledger revision.
-- Offline payload is PROPOSAL ONLY; neither replay nor owner review posts stock.
-- Conflicted requests require a new human-reviewed key and full online workflow.
CREATE TABLE c10_demo.offline_stock_receipts_v1(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL,
 business_id bigint NOT NULL,
 site_id bigint NOT NULL,
 location_id bigint NOT NULL,
 item_id bigint NOT NULL,
 request_key text NOT NULL CHECK(length(btrim(request_key)) BETWEEN 1 AND 120),
 actor_uid uuid NOT NULL,
 submitted_delta numeric(15,3) NOT NULL
  CHECK(submitted_delta<>0 AND submitted_delta=round(submitted_delta,3)),
 expected_ledger_version bigint NOT NULL CHECK(expected_ledger_version>=0),
 observed_ledger_version bigint NOT NULL CHECK(observed_ledger_version>=0),
 balance_before numeric(15,3) NOT NULL CHECK(balance_before>=0),
 balance_after numeric(15,3) NOT NULL CHECK(balance_after>=0),
 status text NOT NULL CHECK(status IN('staged','conflict')),
 conflict_reason text CHECK(conflict_reason IN('stale_ledger_version','insufficient_stock')),
 review_status text NOT NULL DEFAULT 'pending' CHECK(review_status IN('pending','reviewed','rejected')),
 reviewer_uid uuid,
 reviewed_at timestamptz,
 recorded_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(business_id,request_key),
 FOREIGN KEY(location_id,tenant_id,business_id,site_id)
  REFERENCES c10_demo.stock_locations(id,tenant_id,business_id,site_id),
 FOREIGN KEY(item_id,tenant_id,business_id) REFERENCES c10_demo.items(id,tenant_id,business_id),
 CHECK((status='staged' AND conflict_reason IS NULL AND balance_after=balance_before)
    OR (status='conflict' AND conflict_reason IS NOT NULL AND balance_after=balance_before)),
 CHECK((review_status='pending' AND reviewer_uid IS NULL AND reviewed_at IS NULL)
    OR (review_status<>'pending' AND reviewer_uid IS NOT NULL AND reviewed_at IS NOT NULL)),
 CHECK(review_status<>'reviewed' OR status='staged')
);
ALTER TABLE c10_demo.offline_stock_receipts_v1 ENABLE ROW LEVEL SECURITY;
CREATE POLICY offline_receipt_scope_v1 ON c10_demo.offline_stock_receipts_v1
 FOR SELECT TO authenticated USING(
   c10_demo.can_manage(tenant_id,business_id)
   OR (actor_uid=c10_demo.actor_uid() AND
      c10_demo.can_site(tenant_id,business_id,site_id,'stock.read')));
REVOKE ALL ON c10_demo.offline_stock_receipts_v1 FROM PUBLIC;
GRANT SELECT ON c10_demo.offline_stock_receipts_v1 TO authenticated;

CREATE FUNCTION c10_demo.replay_offline_stock_v1(
 p_location bigint,p_item bigint,p_delta numeric,p_expected_version bigint,
 p_request text)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path=c10_demo,pg_catalog AS $$
DECLARE v_actor uuid;v_loc record;v_before numeric(15,3);v_version bigint;
 v_existing record;v_new_id bigint;v_reason text;
BEGIN
 v_actor:=c10_demo.actor_uid();
 IF v_actor IS NULL OR p_location IS NULL OR p_item IS NULL OR p_delta IS NULL
  OR p_delta=0 OR p_delta<>round(p_delta,3) OR
  p_delta::text IN('NaN','Infinity','-Infinity') OR
  p_expected_version IS NULL OR p_expected_version<0 OR
  p_request IS NULL OR length(btrim(p_request)) NOT BETWEEN 1 AND 120
 THEN RAISE EXCEPTION 'invalid_offline_request'; END IF;
 SELECT tenant_id,business_id,site_id INTO v_loc
 FROM c10_demo.stock_locations WHERE id=p_location;
 IF NOT FOUND OR NOT c10_demo.can_site(
  v_loc.tenant_id,v_loc.business_id,v_loc.site_id,'stock.post')
 THEN RAISE EXCEPTION 'offline_stock_not_authorized'; END IF;
 IF NOT EXISTS(SELECT 1 FROM c10_demo.items
  WHERE id=p_item AND tenant_id=v_loc.tenant_id AND business_id=v_loc.business_id)
 THEN RAISE EXCEPTION 'offline_item_scope_mismatch'; END IF;
 -- Strict read-only snapshot of physical inventory. DO NOT create even a
 -- zero-valued stock balance when merely recording an offline proposal.
 -- For absent row treat it as zero; final online posting MUST recheck.
 SELECT COALESCE((SELECT on_hand FROM c10_demo.stock_balances_v1
  WHERE location_id=p_location AND item_id=p_item FOR UPDATE),0)
 INTO v_before;
 -- Once authorized, exact repeats always reuse their historical receipt, even
 -- if current inventory changed. Different request body or actor is rejected.
 SELECT * INTO v_existing FROM c10_demo.offline_stock_receipts_v1
   WHERE business_id=v_loc.business_id AND request_key=p_request;
 IF FOUND THEN
  IF v_existing.actor_uid<>v_actor OR v_existing.location_id<>p_location OR
   v_existing.item_id<>p_item OR v_existing.submitted_delta<>p_delta OR
   v_existing.expected_ledger_version<>p_expected_version
  THEN RAISE EXCEPTION 'offline_replay_payload_conflict'; END IF;
  RETURN v_existing.id;
 END IF;
 -- Ledger event count is ABA-resistant for draft classification. A concurrent
 -- writer can still supersede the observed draft snapshot, which is why no
 -- stock posting ever follows and later online approval revalidates.
 SELECT count(*) INTO v_version FROM c10_demo.stock_movements
  WHERE location_id=p_location AND item_id=p_item;
 v_reason:=CASE
  WHEN p_expected_version<>v_version THEN 'stale_ledger_version'
  WHEN v_before+p_delta<0 THEN 'insufficient_stock'
  ELSE NULL END;
 -- No call to post_stock_event here. Offline stock posting is forbidden by
 -- approved C10-A032; this endpoint only records a proposed change.
 INSERT INTO c10_demo.offline_stock_receipts_v1(
  tenant_id,business_id,site_id,location_id,item_id,request_key,actor_uid,
  submitted_delta,expected_ledger_version,observed_ledger_version,
  balance_before,balance_after,status,conflict_reason)
 VALUES(v_loc.tenant_id,v_loc.business_id,v_loc.site_id,p_location,p_item,
  p_request,v_actor,p_delta,p_expected_version,v_version,v_before,
  v_before,
  CASE WHEN v_reason IS NULL THEN 'staged' ELSE 'conflict' END,
  v_reason)
 RETURNING id INTO v_new_id;
 RETURN v_new_id;
END $$;

-- Explicit version endpoint for a device to capture before disconnecting.
-- Value is a read-only snapshot, never proof that an offline write will be accepted.
CREATE VIEW c10_demo.offline_stock_snapshot_v1 WITH(security_invoker=true) AS
 SELECT b.tenant_id,b.business_id,b.site_id,b.location_id,b.item_id,b.on_hand,
  (SELECT count(*) FROM c10_demo.stock_movements m
   WHERE m.location_id=b.location_id AND m.item_id=b.item_id)::bigint AS ledger_version
 FROM c10_demo.stock_balances_v1 b
 WHERE c10_demo.can_site(b.tenant_id,b.business_id,b.site_id,'stock.read');
REVOKE ALL ON c10_demo.offline_stock_snapshot_v1 FROM PUBLIC;
GRANT SELECT ON c10_demo.offline_stock_snapshot_v1 TO authenticated;

-- Owner-reviewed inbox disposition only; still NO stock mutation.
CREATE FUNCTION c10_demo.review_offline_stock_draft_v1(
 p_receipt bigint,p_decision text)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER
SET search_path=c10_demo,pg_catalog AS $
DECLARE v_rec c10_demo.offline_stock_receipts_v1%ROWTYPE;v_new text;
BEGIN
 IF c10_demo.actor_uid() IS NULL OR p_receipt IS NULL OR
  p_decision IS NULL OR p_decision NOT IN('review','reject')
 THEN RAISE EXCEPTION 'invalid_offline_review'; END IF;
 SELECT * INTO v_rec FROM c10_demo.offline_stock_receipts_v1
   WHERE id=p_receipt FOR UPDATE;
 IF NOT FOUND OR NOT c10_demo.can_manage(v_rec.tenant_id,v_rec.business_id)
 THEN RAISE EXCEPTION 'offline_review_not_authorized'; END IF;
 v_new:=CASE WHEN p_decision='review' THEN 'reviewed' ELSE 'rejected' END;
 IF v_rec.review_status<>'pending' THEN
  IF v_rec.review_status=v_new THEN RETURN v_new; END IF;
  RAISE EXCEPTION 'offline_review_already_final';
 END IF;
 IF p_decision='review' AND v_rec.status<>'staged' THEN
  RAISE EXCEPTION 'conflicted_offline_draft_cannot_be_approved';
 END IF;
 UPDATE c10_demo.offline_stock_receipts_v1
 SET review_status=v_new,reviewer_uid=c10_demo.actor_uid(),reviewed_at=now()
 WHERE id=p_receipt;
 RETURN v_new;
END $;
REVOKE EXECUTE ON FUNCTION c10_demo.review_offline_stock_draft_v1(bigint,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION c10_demo.review_offline_stock_draft_v1(bigint,text) TO authenticated;

CREATE VIEW c10_demo.offline_stock_inbox_v1 WITH(security_invoker=true) AS
 SELECT r.tenant_id,r.business_id,r.site_id,r.location_id,
  count(*)::bigint AS total_replays,
  count(*) FILTER(WHERE r.status='staged')::bigint AS staged,
  count(*) FILTER(WHERE r.status='conflict')::bigint AS conflicts,
  count(*) FILTER(WHERE r.review_status='reviewed')::bigint AS owner_reviewed,
  max(r.recorded_at) AS last_seen_at,
  false::boolean AS offline_operationally_certified
 FROM c10_demo.offline_stock_receipts_v1 r
 WHERE c10_demo.can_manage(r.tenant_id,r.business_id)
 GROUP BY r.tenant_id,r.business_id,r.site_id,r.location_id;
REVOKE ALL ON c10_demo.offline_stock_inbox_v1 FROM PUBLIC;
GRANT SELECT ON c10_demo.offline_stock_inbox_v1 TO authenticated;
REVOKE EXECUTE ON FUNCTION c10_demo.replay_offline_stock_v1(bigint,bigint,numeric,bigint,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION c10_demo.replay_offline_stock_v1(bigint,bigint,numeric,bigint,text) TO authenticated;
-- No client mutation of stock_movements/receipts. Business/tenant auth rechecked
-- on every draft submission. Owner review does not post/settle/alter stock.
