-- Rollback of 0204: read-only functions and indexes; nothing persisted.
DROP FUNCTION core10.owner_business_sites_v1(bigint,text,bigint,integer);
DROP FUNCTION core10.owner_portfolio_v1();
DROP FUNCTION core10._owner_businesses_v1();
DROP INDEX core10.purchase_orders_business_status_ix;
DROP INDEX core10.goods_receipts_business_status_ix;
DROP INDEX core10.stock_balances_business_site_ix;
