-- Never erase persisted business transaction evidence by rollback.
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM core10.sales_orders_v1) THEN RAISE EXCEPTION 'SALES_ROLLBACK_HAS_ORDERS'; END IF;
END $$;
DROP TABLE core10.sales_order_commands_v1;
DROP TABLE core10.sales_order_lines_v1;
DROP TABLE core10.sales_orders_v1;
