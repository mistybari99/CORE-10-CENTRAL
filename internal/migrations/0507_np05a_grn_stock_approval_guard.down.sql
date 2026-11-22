DO $$ BEGIN
 IF to_regclass('core10.goods_receipts_v1') IS NOT NULL THEN
  EXECUTE 'DROP TRIGGER IF EXISTS grn_stock_approval_guard ON core10.goods_receipts_v1';
 END IF;
END $$;
DROP FUNCTION core10._guard_grn_stock_approval_v1();
