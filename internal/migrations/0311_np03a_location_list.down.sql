-- Rollback of 0208: drop the read-only location list RPC. No data is touched.
DROP FUNCTION core10.inventory_list_locations_v1(bigint,bigint);
