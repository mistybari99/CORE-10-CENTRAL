-- Rollback of 0209: fail closed once any lot operation happened (lot-tagged command, hold / release, genealogy link,
-- recall, lot request or lot audit row, Owner Control setting / override for the two lot features, or a held lot).
-- The movement lot breakdown itself is derived (re-computable from GRN / return lines and the FEFO rule), so it is
-- dropped. Otherwise restore the exact prior bodies: post_stock_event / transfer_stock_v1 from 0200,
-- _inventory_approval_payload_v1 / _inventory_command_json_v1 from 0202, then drop the 0209 objects.
DO $guard$ BEGIN
 IF EXISTS(SELECT 1 FROM core10.inventory_commands_v1 WHERE lot_id IS NOT NULL)
 OR EXISTS(SELECT 1 FROM core10.inventory_lots_v1 WHERE status='held' OR held_by IS NOT NULL)
 OR EXISTS(SELECT 1 FROM core10.inventory_lot_links_v1)
 OR EXISTS(SELECT 1 FROM core10.inventory_lot_recalls_v1)
 OR EXISTS(SELECT 1 FROM core10.inventory_lot_requests_v1)
 OR EXISTS(SELECT 1 FROM core10.canonical_audit_events_v1 WHERE source_domain='inventory'
   AND action IN ('inventory.command_lot_set','inventory.lot_hold','inventory.lot_release','inventory.lot_link',
    'inventory.recall_start','inventory.recall_close'))
 OR EXISTS(SELECT 1 FROM core10.control_setting_versions_v1 WHERE feature_key IN ('inventory.lot_control','inventory.lot_recall'))
 OR EXISTS(SELECT 1 FROM core10.control_overrides_v1 WHERE feature_key IN ('inventory.lot_control','inventory.lot_recall'))
 THEN RAISE EXCEPTION 'INV_ROLLBACK_DENIED_LOT_HISTORY'; END IF;
END $guard$;
DELETE FROM core10.control_rpc_map_v1 WHERE lane='Claude' AND board_row='B-012' AND rpc_name IN
 ('inventory_create_lot_command_v1','inventory_lot_hold_v1','inventory_lot_link_v1','inventory_lot_start_recall_v1',
  'inventory_lot_close_recall_v1');
DROP FUNCTION core10.inventory_fefo_v1(bigint,bigint,bigint,numeric);
DROP FUNCTION core10.inventory_list_lot_balances_v1(bigint,bigint,bigint,bigint,bigint,integer);
DROP FUNCTION core10.inventory_lot_recall_v1(bigint);
DROP FUNCTION core10.inventory_lot_close_recall_v1(bigint,text,text);
DROP FUNCTION core10.inventory_lot_start_recall_v1(bigint,text,text,text);
DROP FUNCTION core10._lot_recall_json_v1(bigint,bigint[]);
DROP FUNCTION core10.inventory_lot_link_v1(bigint,bigint,text);
DROP FUNCTION core10.inventory_lot_hold_v1(bigint,text,text,text);
DROP FUNCTION core10.inventory_create_lot_command_v1(bigint,text,bigint,bigint,bigint,numeric,bigint,text,text);
DROP FUNCTION core10._lot_readable_sites_v1(bigint,bigint,bigint);
DROP FUNCTION core10._lot_json_v1(bigint);
DROP FUNCTION core10._lot_record_v1(bigint,bigint,text,text,bigint,text,jsonb);
DROP FUNCTION core10._lot_replay_v1(bigint,text,text,text);
-- 0202 _inventory_approval_payload_v1 (exact)
CREATE OR REPLACE FUNCTION core10._inventory_approval_payload_v1(c core10.inventory_commands_v1) RETURNS jsonb
LANGUAGE sql IMMUTABLE SET search_path=pg_catalog,core10 AS $$
 SELECT jsonb_build_object('command_id',c.id,'business_id',c.business_id,'kind',c.kind,'item_id',c.item_id,
  'amount',c.quantity,'unit','base_qty','source_location',c.source_location,'source_site_id',c.source_site_id,
  'destination_location',c.destination_location,'destination_site_id',c.destination_site_id,'reason',c.reason,
  'version',c.version)
$$;

-- 0202 _inventory_command_json_v1 (exact)
CREATE OR REPLACE FUNCTION core10._inventory_command_json_v1(c core10.inventory_commands_v1, p_replayed boolean) RETURNS jsonb
LANGUAGE sql IMMUTABLE SET search_path=pg_catalog,core10 AS $$
 SELECT jsonb_build_object('command_id',c.id,'business_id',c.business_id,'kind',c.kind,'status',c.status,
  'version',c.version,'item_id',c.item_id,'quantity',c.quantity,'source_location',c.source_location,
  'source_site_id',c.source_site_id,'destination_location',c.destination_location,
  'destination_site_id',c.destination_site_id,'reason',c.reason,'stock_ref',c.stock_ref,
  'created_by',c.created_by,'created_at',c.created_at,'confirmed_by',c.confirmed_by,'posted_by',c.posted_by,
  'posted_at',c.posted_at,'cancelled_by',c.cancelled_by,'approval_request_id',c.approval_request_id,'replayed',p_replayed)
$$;

-- 0200 post_stock_event (exact)
CREATE OR REPLACE FUNCTION core10.post_stock_event(
 p_location bigint,p_item bigint,p_delta numeric,p_request text)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,core10 AS $$
DECLARE v_loc record; v_balance numeric(15,3); v_id bigint; v_prev record;
BEGIN
 IF core10.actor_uid() IS NULL OR
    p_delta IS NULL OR p_delta=0 OR
    p_delta::text IN('NaN','Infinity','-Infinity') OR
    p_delta<>round(p_delta,3) OR
    p_request IS NULL OR length(btrim(p_request))=0 OR
    left(p_request,13)='c10-transfer:' THEN
  RAISE EXCEPTION 'invalid_stock_event';
 END IF;
 SELECT tenant_id,business_id,site_id INTO v_loc
  FROM core10.stock_locations WHERE id=p_location;
 IF NOT FOUND OR NOT core10.can_site(
   v_loc.tenant_id,v_loc.business_id,v_loc.site_id,'stock.post') THEN
  RAISE EXCEPTION 'stock_post_not_authorized';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM core10.items
    WHERE id=p_item AND tenant_id=v_loc.tenant_id
      AND business_id=v_loc.business_id) THEN
  RAISE EXCEPTION 'stock_item_business_mismatch' USING ERRCODE='23503';
 END IF;

 -- Unique balance key serializes concurrent requests on this location/item.
 INSERT INTO core10.stock_balances_v1(
  tenant_id,business_id,site_id,location_id,item_id,on_hand)
 VALUES(v_loc.tenant_id,v_loc.business_id,v_loc.site_id,p_location,p_item,0)
 ON CONFLICT(location_id,item_id) DO NOTHING;

 SELECT on_hand INTO v_balance FROM core10.stock_balances_v1
  WHERE location_id=p_location AND item_id=p_item FOR UPDATE;

 -- The idempotency read must happen AFTER acquiring the balance lock.
 SELECT id,item_id,delta,created_by,transfer_id INTO v_prev
  FROM core10.stock_movements
  WHERE location_id=p_location AND request_key=p_request;
 IF FOUND THEN
  IF v_prev.item_id<>p_item OR v_prev.delta<>p_delta OR
     v_prev.created_by<>core10.actor_uid() OR v_prev.transfer_id IS NOT NULL THEN
   RAISE EXCEPTION 'idempotency_key_payload_conflict';
  END IF;
  RETURN v_prev.id;
 END IF;
 IF v_balance+p_delta<0 THEN RAISE EXCEPTION 'insufficient_stock'; END IF;
 UPDATE core10.stock_balances_v1 SET on_hand=on_hand+p_delta
  WHERE location_id=p_location AND item_id=p_item;
 INSERT INTO core10.stock_movements(
  tenant_id,business_id,site_id,location_id,item_id,delta,request_key,created_by)
 VALUES(v_loc.tenant_id,v_loc.business_id,v_loc.site_id,
   p_location,p_item,p_delta,p_request,core10.actor_uid())
 RETURNING id INTO v_id;
 RETURN v_id;
END $$;

-- 0200 transfer_stock_v1 (exact)
CREATE OR REPLACE FUNCTION core10.transfer_stock_v1(
 p_source bigint,p_destination bigint,p_item bigint,p_quantity numeric,p_request text)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,core10 AS $$
DECLARE v_source record; v_destination record;
 v_id bigint; v_prev record; v_on_hand numeric(15,3);
BEGIN
 IF core10.actor_uid() IS NULL OR
  p_source IS NULL OR p_destination IS NULL OR p_source=p_destination OR
  p_quantity IS NULL OR p_quantity<=0 OR
  p_quantity::text IN('NaN','Infinity','-Infinity') OR
  p_quantity<>round(p_quantity,3) OR
  p_request IS NULL OR length(btrim(p_request))=0 THEN
  RAISE EXCEPTION 'invalid_transfer_request';
 END IF;
 SELECT tenant_id,business_id,site_id INTO v_source
  FROM core10.stock_locations WHERE id=p_source;
 SELECT tenant_id,business_id,site_id INTO v_destination
  FROM core10.stock_locations WHERE id=p_destination;
 IF v_source.tenant_id IS NULL OR v_destination.tenant_id IS NULL OR
   v_source.tenant_id<>v_destination.tenant_id OR
   v_source.business_id<>v_destination.business_id THEN
  RAISE EXCEPTION 'cross_business_transfer_forbidden';
 END IF;
 IF NOT core10.can_site(v_source.tenant_id,v_source.business_id,
      v_source.site_id,'stock.post')
    OR NOT core10.can_site(v_destination.tenant_id,v_destination.business_id,
      v_destination.site_id,'stock.post') THEN
  RAISE EXCEPTION 'transfer_not_authorized';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM core10.items WHERE id=p_item
       AND tenant_id=v_source.tenant_id AND business_id=v_source.business_id) THEN
  RAISE EXCEPTION 'stock_item_business_mismatch' USING ERRCODE='23503';
 END IF;

 -- Unique request key serializes exact retries; a failed transfer rolls
 -- back BOTH balance updates, BOTH journal rows and this header atomically.
 INSERT INTO core10.stock_transfers_v1(
  tenant_id,business_id,source_site_id,source_location_id,
  destination_site_id,destination_location_id,item_id,quantity,request_key,created_by)
 VALUES(v_source.tenant_id,v_source.business_id,v_source.site_id,p_source,
  v_destination.site_id,p_destination,p_item,p_quantity,p_request,core10.actor_uid())
 ON CONFLICT(tenant_id,business_id,request_key) DO NOTHING RETURNING id INTO v_id;
 IF v_id IS NULL THEN
  SELECT id,source_location_id,destination_location_id,item_id,quantity,created_by
   INTO v_prev FROM core10.stock_transfers_v1
   WHERE tenant_id=v_source.tenant_id AND business_id=v_source.business_id
    AND request_key=p_request;
  IF NOT FOUND OR v_prev.source_location_id<>p_source OR
     v_prev.destination_location_id<>p_destination OR
     v_prev.item_id<>p_item OR v_prev.quantity<>p_quantity OR
     v_prev.created_by<>core10.actor_uid() THEN
   RAISE EXCEPTION 'idempotency_key_payload_conflict';
  END IF;
  RETURN v_prev.id;
 END IF;

 INSERT INTO core10.stock_balances_v1(
    tenant_id,business_id,site_id,location_id,item_id,on_hand)
 VALUES(v_source.tenant_id,v_source.business_id,v_source.site_id,p_source,p_item,0),
       (v_destination.tenant_id,v_destination.business_id,
        v_destination.site_id,p_destination,p_item,0)
 ON CONFLICT(location_id,item_id) DO NOTHING;

 -- Globally ordered row locking avoids source/destination deadlocks.
 PERFORM 1 FROM core10.stock_balances_v1
  WHERE item_id=p_item AND location_id IN(p_source,p_destination)
  ORDER BY location_id FOR UPDATE;
 SELECT on_hand INTO v_on_hand FROM core10.stock_balances_v1
  WHERE location_id=p_source AND item_id=p_item;
 IF v_on_hand<p_quantity THEN RAISE EXCEPTION 'insufficient_stock'; END IF;

 UPDATE core10.stock_balances_v1 SET on_hand=on_hand-p_quantity
  WHERE location_id=p_source AND item_id=p_item;
 UPDATE core10.stock_balances_v1 SET on_hand=on_hand+p_quantity
  WHERE location_id=p_destination AND item_id=p_item;
 INSERT INTO core10.stock_movements(
  tenant_id,business_id,site_id,location_id,item_id,delta,request_key,created_by,transfer_id)
 VALUES
  (v_source.tenant_id,v_source.business_id,v_source.site_id,p_source,
   p_item,-p_quantity,'c10-transfer:'||v_id||':out',core10.actor_uid(),v_id),
  (v_destination.tenant_id,v_destination.business_id,v_destination.site_id,p_destination,
   p_item,p_quantity,'c10-transfer:'||v_id||':in',core10.actor_uid(),v_id);
 RETURN v_id;
END $$;

REVOKE ALL ON FUNCTION core10.post_stock_event(bigint,bigint,numeric,text) FROM PUBLIC,authenticated;
REVOKE ALL ON FUNCTION core10.transfer_stock_v1(bigint,bigint,bigint,numeric,text) FROM PUBLIC,authenticated;
DROP FUNCTION core10._stock_lot_apply_v1(bigint,bigint,bigint,numeric,jsonb,numeric);
DROP FUNCTION core10._stock_movement_lot_v1(bigint,bigint,text);
DROP FUNCTION core10._lot_on_hand_v1(bigint,bigint,bigint);
DROP VIEW core10.inventory_lot_reconciliation_v1;
DROP VIEW core10.stock_lot_balances_v1;
DROP TABLE core10.inventory_lot_requests_v1;
DROP TABLE core10.inventory_lot_recall_lots_v1;
DROP TABLE core10.inventory_lot_recalls_v1;
DROP TABLE core10.inventory_lot_links_v1;
DROP FUNCTION core10._lot_block_reason_v1(bigint);
DROP INDEX core10.inventory_commands_lot_ix;
ALTER TABLE core10.inventory_commands_v1 DROP CONSTRAINT inventory_commands_v1_lot_fk_v1;
ALTER TABLE core10.inventory_commands_v1 DROP COLUMN lot_id;
DROP TABLE core10.stock_movement_lots_v1;
DROP FUNCTION core10._stock_movement_lots_immutable_v1();
ALTER TABLE core10.inventory_lots_v1 DROP CONSTRAINT inventory_lots_v1_hold_v1;
ALTER TABLE core10.inventory_lots_v1 DROP COLUMN hold_reason, DROP COLUMN held_at, DROP COLUMN held_by;
DELETE FROM core10.control_catalog_v1 WHERE feature_key IN ('inventory.lot_control','inventory.lot_recall');
