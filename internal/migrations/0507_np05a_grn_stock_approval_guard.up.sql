-- The 0203 GRN writer checks Stock enablement but does not consume staged Approval.
-- Reject the posting transition atomically when the Stock policy requires approval.
CREATE FUNCTION core10._guard_grn_stock_approval_v1() RETURNS trigger
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE control jsonb;
BEGIN
 IF NOT EXISTS (SELECT 1 FROM core10.goods_receipt_lines_v1 l
   WHERE l.grn_id=NEW.id AND l.tenant_id=NEW.tenant_id AND l.business_id=NEW.business_id
    AND l.accepted_qty>0) THEN
  RETURN NEW;
 END IF;
 -- Read the effective policy at the posting transition, after the writer's possible lock waits.
 control:=core10._control_resolve_at_v1(NEW.business_id,'inventory.stock_event',NEW.site_id,clock_timestamp());
 IF (control->>'stages')::int>0 THEN
  RAISE EXCEPTION 'PROC_STOCK_APPROVAL_NOT_CONNECTED';
 END IF;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION core10._guard_grn_stock_approval_v1() FROM PUBLIC,authenticated;

DO $$ BEGIN
 IF EXISTS (SELECT 1 FROM core10.schema_migrations WHERE version=203 AND name='0203_np03a_procurement_grn') THEN
  EXECUTE 'CREATE TRIGGER grn_stock_approval_guard BEFORE UPDATE OF status ON core10.goods_receipts_v1
   FOR EACH ROW WHEN (OLD.status <> ''posted'' AND NEW.status = ''posted'')
   EXECUTE FUNCTION core10._guard_grn_stock_approval_v1()';
 END IF;
END $$;
