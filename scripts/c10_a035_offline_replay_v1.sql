-- C10-A035 offline stock replay server protocol: DISPOSABLE PostgreSQL17 only.
-- No offline write is trusted merely because it was recorded on a device.
-- Requires a fresh signed session, live DB scope, conflict-free ledger revision.
-- Receipt is immutable audit; conflicted requests require a NEW human-reviewed key.
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
 status text NOT NULL CHECK(status IN('applied','conflict')),
 conflict_reason text CHECK(conflict_reason IN('stale_ledger_version','insufficient_stock')),
 stock_movement_id bigint REFERENCES c10_demo.stock_movements(id),
 recorded_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(business_id,request_key),
 FOREIGN KEY(location_id,tenant_id,business_id,site_id)
  REFERENCES c10_demo.stock_locations(id,tenant_id,business_id,site_id),
 FOREIGN KEY(item_id,tenant_id,business_id) REFERENCES c10_demo.items(id,tenant_id,business_id),
 CHECK((status='applied' AND conflict_reason IS NULL AND stock_movement_id IS NOT NULL
        AND balance_after=balance_before+submitted_delta)
    OR (status='conflict' AND conflict_reason IS NOT NULL AND stock_movement_id IS NULL
        AND balance_after=balance_before))
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
 v_existing record;v_new_id bigint;v_event bigint;v_reason text;
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
 -- Serialize across all stock writers, not just other offline requests.
 INSERT INTO c10_demo.stock_balances_v1(
  tenant_id,business_id,site_id,location_id,item_id,on_hand)
 VALUES(v_loc.tenant_id,v_loc.business_id,v_loc.site_id,p_location,p_item,0)
 ON CONFLICT(location_id,item_id) DO NOTHING;
 SELECT on_hand INTO v_before FROM c10_demo.stock_balances_v1
  WHERE location_id=p_location AND item_id=p_item FOR UPDATE;
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
 -- Ledger event count is ABA resistant, unlike comparing on_hand alone.
 SELECT count(*) INTO v_version FROM c10_demo.stock_movements
  WHERE location_id=p_location AND item_id=p_item;
 v_reason:=CASE
  WHEN p_expected_version<>v_version THEN 'stale_ledger_version'
  WHEN v_before+p_delta<0 THEN 'insufficient_stock'
  ELSE NULL END;
 IF v_reason IS NULL THEN
  -- Unpredictable server-only key prevents pre-reserving a movement by clients.
  v_event:=c10_demo.post_stock_event(p_location,p_item,p_delta,
    'c10-offline:'||pg_catalog.gen_random_uuid()::text);
 END IF;
 INSERT INTO c10_demo.offline_stock_receipts_v1(
  tenant_id,business_id,site_id,location_id,item_id,request_key,actor_uid,
  submitted_delta,expected_ledger_version,observed_ledger_version,
  balance_before,balance_after,status,conflict_reason,stock_movement_id)
 VALUES(v_loc.tenant_id,v_loc.business_id,v_loc.site_id,p_location,p_item,
  p_request,v_actor,p_delta,p_expected_version,v_version,v_before,
  CASE WHEN v_reason IS NULL THEN v_before+p_delta ELSE v_before END,
  CASE WHEN v_reason IS NULL THEN 'applied' ELSE 'conflict' END,
  v_reason,v_event)
 RETURNING id INTO v_new_id;
 RETURN v_new_id;
END $$;

CREATE VIEW c10_demo.offline_stock_inbox_v1 WITH(security_invoker=true) AS
 SELECT r.tenant_id,r.business_id,r.site_id,r.location_id,
  count(*)::bigint AS total_replays,
  count(*) FILTER(WHERE r.status='applied')::bigint AS applied,
  count(*) FILTER(WHERE r.status='conflict')::bigint AS conflicts,
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
-- on every replay. No automatic overwrite or rebase of stale offline edits.
