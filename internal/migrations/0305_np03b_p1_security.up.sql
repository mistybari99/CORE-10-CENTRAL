-- CORE10 NP03B 0305: freeze confirmed canonical Sales source and bind Audit.
-- Forward-only correction: no edits to existing 0300–0304 applied bytes.
-- Use only in a correctly ordered migration plan; no hosted apply.
DO $dep$ BEGIN
 IF to_regclass('core10.sales_orders_v1') IS NULL
 OR to_regclass('core10.sales_invoice_drafts_v1') IS NULL
 OR to_regclass('core10.master_parties_v1') IS NULL
 THEN RAISE EXCEPTION 'SALES_P1_SECURITY_DEPENDENCY_NOT_CONNECTED'; END IF;
END $dep$;

-- Never rewrite a confirmed or cancelled order header. The only permitted
-- existing operational transition is draft->confirmed/cancelled with its
-- original payload, exact version increment and scoped caller identity.
CREATE FUNCTION core10._sales_order_header_guard_0305()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,core10 AS $body$
BEGIN
 IF TG_OP='TRUNCATE' THEN RAISE EXCEPTION 'SALES_SOURCE_IMMUTABLE'; END IF;
 IF TG_OP='INSERT' THEN
  IF NEW.status<>'draft' OR NEW.version<>1 THEN
   RAISE EXCEPTION 'SALES_SOURCE_IMMUTABLE'; END IF;
  RETURN NEW;
 END IF;
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'SALES_SOURCE_IMMUTABLE'; END IF;
 IF OLD.status<>'draft' THEN RAISE EXCEPTION 'SALES_SOURCE_IMMUTABLE'; END IF;
 IF NEW.status NOT IN('draft','confirmed','cancelled')
 OR NEW.version<>OLD.version+1 OR NEW.changed_by IS DISTINCT FROM core10.actor_uid()
 OR NEW.id IS DISTINCT FROM OLD.id
 OR NEW.tenant_id IS DISTINCT FROM OLD.tenant_id
 OR NEW.business_id IS DISTINCT FROM OLD.business_id
 OR NEW.site_id IS DISTINCT FROM OLD.site_id
 OR NEW.created_by IS DISTINCT FROM OLD.created_by
 OR NEW.created_at IS DISTINCT FROM OLD.created_at
 THEN RAISE EXCEPTION 'SALES_SOURCE_IMMUTABLE'; END IF;
 IF NEW.status IN('confirmed','cancelled') AND
   ROW(NEW.customer_id,NEW.price_list_id,NEW.currency,NEW.document,NEW.total)
   IS DISTINCT FROM
   ROW(OLD.customer_id,OLD.price_list_id,OLD.currency,OLD.document,OLD.total)
 THEN RAISE EXCEPTION 'SALES_SOURCE_IMMUTABLE'; END IF;
 RETURN NEW;
END $body$;
CREATE TRIGGER sales_order_header_secure_0305
 BEFORE INSERT OR UPDATE OR DELETE ON core10.sales_orders_v1
 FOR EACH ROW EXECUTE FUNCTION core10._sales_order_header_guard_0305();
CREATE TRIGGER sales_order_header_notruncate_0305
 BEFORE TRUNCATE ON core10.sales_orders_v1
 FOR EACH STATEMENT EXECUTE FUNCTION core10._sales_order_header_guard_0305();

-- Source lines may be modified only when the header is still a draft.
-- Lock the header so confirmation, tamper and invoice-save all serialize.
CREATE FUNCTION core10._sales_order_lines_guard_0305()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,core10 AS $body$
DECLARE old_status text;v_order bigint;
BEGIN
 IF TG_OP='TRUNCATE' THEN RAISE EXCEPTION 'SALES_SOURCE_IMMUTABLE'; END IF;
 v_order:=CASE WHEN TG_OP='DELETE' THEN OLD.order_id ELSE NEW.order_id END;
 SELECT status INTO old_status FROM core10.sales_orders_v1
 WHERE id=v_order FOR SHARE;
 IF old_status IS DISTINCT FROM 'draft'
 THEN RAISE EXCEPTION 'SALES_SOURCE_IMMUTABLE'; END IF;
 IF TG_OP='UPDATE' AND
  (NEW.order_id<>OLD.order_id OR NEW.tenant_id<>OLD.tenant_id
   OR NEW.business_id<>OLD.business_id OR NEW.site_id<>OLD.site_id)
 THEN RAISE EXCEPTION 'SALES_SOURCE_IMMUTABLE'; END IF;
 RETURN CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
END $body$;
CREATE TRIGGER sales_order_lines_secure_0305
 BEFORE INSERT OR UPDATE OR DELETE ON core10.sales_order_lines_v1
 FOR EACH ROW EXECUTE FUNCTION core10._sales_order_lines_guard_0305();
CREATE TRIGGER sales_order_lines_notruncate_0305
 BEFORE TRUNCATE ON core10.sales_order_lines_v1
 FOR EACH STATEMENT EXECUTE FUNCTION core10._sales_order_lines_guard_0305();

-- Canonical command/evidence links must never be moved to a different event
-- (even by privileged ordinary DML), nor deleted or truncated.
CREATE FUNCTION core10._sales_command_frozen_0305()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,core10 AS $body$
BEGIN
 RAISE EXCEPTION 'SALES_AUDIT_IMMUTABLE';
END $body$;
CREATE TRIGGER sales_commands_frozen_0305
 BEFORE UPDATE OR DELETE ON core10.sales_order_commands_v1
 FOR EACH ROW EXECUTE FUNCTION core10._sales_command_frozen_0305();
CREATE TRIGGER sales_commands_notruncate_0305
 BEFORE TRUNCATE ON core10.sales_order_commands_v1
 FOR EACH STATEMENT EXECUTE FUNCTION core10._sales_command_frozen_0305();
CREATE TRIGGER sales_invoice_commands_frozen_0305
 BEFORE UPDATE OR DELETE ON core10.sales_invoice_commands_v1
 FOR EACH ROW EXECUTE FUNCTION core10._sales_command_frozen_0305();
CREATE TRIGGER sales_invoice_commands_notruncate_0305
 BEFORE TRUNCATE ON core10.sales_invoice_commands_v1
 FOR EACH STATEMENT EXECUTE FUNCTION core10._sales_command_frozen_0305();

-- Zero-stage cannot carry an arbitrary approval ID, in either server RPC.
-- Under positive stages, the original RPC performs binding verification.
-- This is the final insert-time fail-closed fence for privileged command DML.
CREATE FUNCTION core10._sales_command_approval_guard_0305()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,core10 AS $body$
DECLARE c jsonb;feature text;
BEGIN
 IF TG_TABLE_NAME='sales_order_commands_v1' THEN
  IF NEW.input->>'op' NOT IN('confirm','cancel') THEN RETURN NEW; END IF;
  feature:='sales.order_transition';
 ELSE
  IF NEW.input->>'op'<>'validate' THEN RETURN NEW; END IF;
  feature:='sales.invoice_validate';
 END IF;
 c:=core10.control_check_v1(NEW.business_id,feature,NEW.site_id);
 IF (c->>'stages')::integer=0 AND NEW.input->>'approval_id' IS NOT NULL
 THEN RAISE EXCEPTION 'SALES_APPROVAL_UNVERIFIED_ZERO_STAGE'; END IF;
 RETURN NEW;
END $body$;
CREATE TRIGGER sales_commands_approval_guard_0305
 BEFORE INSERT ON core10.sales_order_commands_v1
 FOR EACH ROW EXECUTE FUNCTION core10._sales_command_approval_guard_0305();
CREATE TRIGGER sales_invoice_commands_approval_guard_0305
 BEFORE INSERT ON core10.sales_invoice_commands_v1
 FOR EACH ROW EXECUTE FUNCTION core10._sales_command_approval_guard_0305();

-- A source is confirmed only with one real canonical Audit receipt:
-- original snapshot/version, transitioned source, receipt status/version,
-- command actor, and command association MUST all match this same order.
CREATE FUNCTION core10._sales_confirmed_audit_guard_0305()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,core10 AS $body$
DECLARE o core10.sales_orders_v1%ROWTYPE;
BEGIN
 IF TG_OP='DELETE' THEN RETURN OLD; END IF;
 SELECT * INTO o FROM core10.sales_orders_v1 WHERE id=NEW.id;
 IF NOT FOUND OR o.status<>'confirmed' THEN RETURN NEW; END IF;
 IF NOT EXISTS (
  SELECT 1 FROM core10.sales_order_commands_v1 c
  JOIN core10.canonical_audit_events_v1 a ON a.id=c.audit_event_id
  WHERE c.order_id=o.id AND c.tenant_id=o.tenant_id
   AND c.business_id=o.business_id AND c.site_id=o.site_id
   AND c.actor_id=a.actor_id
   AND c.input->>'op'='confirm'
   AND (c.input->>'expected')::bigint=o.version-1
   AND c.receipt->>'status'='confirmed'
   AND (c.receipt->>'order_id')::bigint=o.id
   AND (c.receipt->>'version')::bigint=o.version
   AND (c.receipt->>'total')::numeric=o.total
   AND a.tenant_id=o.tenant_id AND a.business_id=o.business_id
   AND a.source_domain='sales' AND a.action='sales.confirm'
   AND a.source_ref=o.id::text||':'||o.version::text
   AND a.request_key='sales:'||c.request_key
   AND a.payload->'receipt'=c.receipt
   AND a.payload->'source'->>'action'='confirm'
   AND (a.payload->'source'->>'order_id')::bigint=o.id
   AND (a.payload->'source'->>'version')::bigint=o.version-1
   AND a.payload->'source'->'document'=o.document
   AND (a.payload->'source'->>'total')::numeric=o.total
 ) THEN RAISE EXCEPTION 'SALES_SOURCE_AUDIT_MISMATCH'; END IF;
 RETURN NEW;
END $body$;
-- Deferred: the domain RPC creates the order state, then Audit and command in
-- one transaction. Check the final state only when that transaction commits.
CREATE CONSTRAINT TRIGGER sales_confirmed_requires_audit_0305
 AFTER INSERT OR UPDATE ON core10.sales_orders_v1
 DEFERRABLE INITIALLY DEFERRED
 FOR EACH ROW EXECUTE FUNCTION core10._sales_confirmed_audit_guard_0305();

CREATE FUNCTION core10._sales_invoice_confirmation_guard_0305()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,core10 AS $body$
DECLARE o core10.sales_orders_v1%ROWTYPE;source_audit bigint;
BEGIN
 SELECT * INTO o FROM core10.sales_orders_v1 WHERE id=NEW.source_order_id
 AND tenant_id=NEW.tenant_id AND business_id=NEW.business_id
 AND site_id=NEW.site_id FOR SHARE;
 IF NOT FOUND OR o.status<>'confirmed' OR o.version<>NEW.source_order_version
 OR NEW.source_snapshot->'document' IS DISTINCT FROM o.document
 OR NEW.source_snapshot->>'total' IS DISTINCT FROM o.total::text
 OR NEW.customer_id<>o.customer_id OR NEW.currency<>o.currency
 THEN RAISE EXCEPTION 'SALES_INVOICE_SOURCE_AUDIT_MISMATCH'; END IF;
 -- Check the real confirmation event through the immutable command link;
 -- a self-consistent but forged source snapshot cannot stand in for it.
 SELECT c.audit_event_id INTO source_audit
 FROM core10.sales_order_commands_v1 c
 JOIN core10.canonical_audit_events_v1 a ON a.id=c.audit_event_id
 WHERE c.order_id=o.id AND c.tenant_id=o.tenant_id
 AND c.business_id=o.business_id AND c.site_id=o.site_id
 AND c.input->>'op'='confirm'
 AND c.receipt->>'status'='confirmed'
 AND (c.receipt->>'version')::bigint=o.version
 AND a.tenant_id=o.tenant_id AND a.business_id=o.business_id
 AND a.source_domain='sales' AND a.action='sales.confirm'
 AND a.source_ref=o.id::text||':'||o.version::text
 AND a.payload->'receipt'=c.receipt
 AND a.payload->'source'->'document'=o.document
 AND (a.payload->'source'->>'version')::bigint=o.version-1
 AND (a.payload->'source'->>'total')::numeric=o.total
 AND c.actor_id=a.actor_id
 LIMIT 1;
 IF source_audit IS NULL
 OR NEW.source_snapshot->>'confirmation_audit_event_id'<>source_audit::text
 THEN RAISE EXCEPTION 'SALES_INVOICE_SOURCE_AUDIT_MISMATCH'; END IF;
 RETURN NEW;
END $body$;
CREATE TRIGGER zz_sales_invoice_confirmation_guard_0305
 BEFORE INSERT OR UPDATE ON core10.sales_invoice_drafts_v1
 FOR EACH ROW EXECUTE FUNCTION core10._sales_invoice_confirmation_guard_0305();

-- Canonical Master retention: a numeric ID cannot outlive a referenced
-- party row while Sales/Invoice history still points to it.
CREATE FUNCTION core10._sales_master_party_restrict_0305()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,core10 AS $body$
BEGIN
 IF EXISTS(SELECT 1 FROM core10.sales_orders_v1
  WHERE customer_id=OLD.id AND tenant_id=OLD.tenant_id
    AND business_id=OLD.business_id)
 OR EXISTS(SELECT 1 FROM core10.sales_invoice_drafts_v1
  WHERE customer_id=OLD.id AND tenant_id=OLD.tenant_id
    AND business_id=OLD.business_id)
 THEN RAISE EXCEPTION 'SALES_MASTER_REFERENCE_RETAINED'; END IF;
 RETURN OLD;
END $body$;
CREATE TRIGGER sales_master_party_retention_0305
 BEFORE DELETE ON core10.master_parties_v1 FOR EACH ROW
 EXECUTE FUNCTION core10._sales_master_party_restrict_0305();

REVOKE ALL ON FUNCTION
 core10._sales_order_header_guard_0305(),
 core10._sales_order_lines_guard_0305(),
 core10._sales_command_frozen_0305(),
 core10._sales_command_approval_guard_0305(),
 core10._sales_confirmed_audit_guard_0305(),
 core10._sales_invoice_confirmation_guard_0305(),
 core10._sales_master_party_restrict_0305()
 FROM PUBLIC,authenticated;
