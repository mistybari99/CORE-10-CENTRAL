-- Rollback of 0200: refuse once transfers exist (paired history); otherwise restore the 0002 posting function.
DO $g$ BEGIN IF EXISTS(SELECT 1 FROM core10.stock_transfers_v1) THEN RAISE EXCEPTION 'INVENTORY_ROLLBACK_DENIED_TRANSFER_HISTORY'; END IF; END $g$;
DROP VIEW IF EXISTS core10.inventory_reconciliation_v1;
DROP FUNCTION IF EXISTS core10.transfer_stock_v1(bigint,bigint,bigint,numeric,text);
CREATE OR REPLACE FUNCTION core10.post_stock_event(p_location bigint,p_item bigint,p_delta numeric,p_request text)
RETURNS bigint LANGUAGE plpgsql SECURITY INVOKER SET search_path=core10,pg_catalog AS $$
DECLARE v_loc record;v_id bigint;v_prev record;
BEGIN
 IF p_delta IS NULL OR p_delta=0 OR p_request IS NULL OR btrim(p_request)='' THEN RAISE EXCEPTION 'invalid_stock_event'; END IF;
 SELECT tenant_id,business_id,site_id INTO v_loc FROM stock_locations WHERE id=p_location;
 IF NOT FOUND OR NOT can_site(v_loc.tenant_id,v_loc.business_id,v_loc.site_id,'stock.post') THEN
  RAISE EXCEPTION 'stock_post_not_authorized';
 END IF;
 INSERT INTO stock_movements(tenant_id,business_id,site_id,location_id,item_id,delta,request_key)
 VALUES(v_loc.tenant_id,v_loc.business_id,v_loc.site_id,p_location,p_item,p_delta,p_request)
 ON CONFLICT(location_id,request_key) DO NOTHING RETURNING id INTO v_id;
 IF v_id IS NULL THEN
  SELECT id,item_id,delta,created_by INTO v_prev FROM stock_movements
   WHERE location_id=p_location AND request_key=p_request;
  IF NOT FOUND OR v_prev.item_id<>p_item OR v_prev.delta<>p_delta OR v_prev.created_by<>actor_uid()
   THEN RAISE EXCEPTION 'idempotency_key_payload_conflict'; END IF;
  v_id:=v_prev.id;
 END IF;
 RETURN v_id;
END $$;

GRANT EXECUTE ON FUNCTION core10.post_stock_event(bigint,bigint,numeric,text) TO authenticated;
ALTER TABLE core10.stock_movements DROP COLUMN IF EXISTS transfer_id;
DROP TABLE IF EXISTS core10.stock_transfers_v1;
DROP TABLE IF EXISTS core10.stock_balances_v1;
INSERT INTO core10.control_rpc_map_v1(rpc_name,status,feature_key,reason,lane,board_row) VALUES
 ('post_stock_event','pending','inventory.stock_event','Stock posting is not yet bound to its control; connects with the inventory command ledger','Claude','B-012')
 ON CONFLICT DO NOTHING;
