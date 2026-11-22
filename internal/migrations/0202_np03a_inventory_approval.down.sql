-- Rollback of 0202: refuse once any command carries an approval request; otherwise restore the 0201 hook.
DO $guard$ BEGIN
 IF EXISTS(SELECT 1 FROM core10.inventory_commands_v1 WHERE approval_request_id IS NOT NULL)
 THEN RAISE EXCEPTION 'INV_ROLLBACK_DENIED_APPROVAL_HISTORY'; END IF;
END $guard$;
DELETE FROM core10.control_rpc_map_v1 WHERE lane='Claude' AND board_row='B-012' AND rpc_name='inventory_request_approval_v1';
DROP FUNCTION core10.inventory_request_approval_v1(bigint,text);
DROP FUNCTION core10._inventory_route_matches_v1(bigint,bigint,text,bigint,integer);
DROP FUNCTION core10._inventory_approval_action_v1(text);
DROP FUNCTION core10._inventory_approval_payload_v1(core10.inventory_commands_v1);
CREATE OR REPLACE FUNCTION core10._inventory_approval_gate_v1(p_command bigint, p_stages integer) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
BEGIN
 IF coalesce(p_stages,0)>0 THEN RAISE EXCEPTION 'INV_APPROVAL_NOT_CONNECTED'; END IF;
 RETURN '{}'::jsonb;
END $$;
REVOKE ALL ON FUNCTION core10._inventory_approval_gate_v1(bigint,integer) FROM PUBLIC, authenticated;
ALTER TABLE core10.inventory_commands_v1 DROP COLUMN approval_request_id;
CREATE OR REPLACE FUNCTION core10._inventory_command_json_v1(c core10.inventory_commands_v1, p_replayed boolean) RETURNS jsonb
LANGUAGE sql IMMUTABLE SET search_path=pg_catalog,core10 AS $$
 SELECT jsonb_build_object('command_id',c.id,'business_id',c.business_id,'kind',c.kind,'status',c.status,
  'version',c.version,'item_id',c.item_id,'quantity',c.quantity,'source_location',c.source_location,
  'source_site_id',c.source_site_id,'destination_location',c.destination_location,
  'destination_site_id',c.destination_site_id,'reason',c.reason,'stock_ref',c.stock_ref,
  'created_by',c.created_by,'created_at',c.created_at,'confirmed_by',c.confirmed_by,'posted_by',c.posted_by,
  'posted_at',c.posted_at,'cancelled_by',c.cancelled_by,'replayed',p_replayed)
$$;
REVOKE ALL ON FUNCTION core10._inventory_command_json_v1(core10.inventory_commands_v1,boolean) FROM PUBLIC, authenticated;
