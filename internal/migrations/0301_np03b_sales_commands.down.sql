DELETE FROM core10.control_rpc_map_v1 WHERE rpc_name IN ('save_sales_order_v1','transition_sales_order_v1');
-- The canonical Control history is append-only. Like other pack rollbacks, a
-- used catalog cannot be removed while settings still reference it; fail safely.
DELETE FROM core10.control_catalog_v1 WHERE feature_key IN ('sales.order_draft','sales.order_transition');
DROP FUNCTION core10.read_sales_orders_v1(bigint,bigint,bigint);
DROP FUNCTION core10.transition_sales_order_v1(bigint,bigint,bigint,text,bigint,bigint,text);
DROP FUNCTION core10.save_sales_order_v1(bigint,bigint,bigint,bigint,jsonb,text);
DROP FUNCTION core10._sales_validate_v1(bigint,bigint,jsonb,jsonb);
DROP FUNCTION core10._sales_scope_v1(bigint,bigint);
