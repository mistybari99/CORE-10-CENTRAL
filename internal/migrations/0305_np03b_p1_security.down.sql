-- NP03B 0305 rollback refuses any Sales history that would lose tamper protection.
DO $guard$ BEGIN
 IF EXISTS(SELECT 1 FROM core10.sales_orders_v1)
 OR EXISTS(SELECT 1 FROM core10.sales_order_commands_v1)
 OR EXISTS(SELECT 1 FROM core10.sales_invoice_drafts_v1)
 OR EXISTS(SELECT 1 FROM core10.sales_invoice_commands_v1)
 OR EXISTS(SELECT 1 FROM core10.canonical_audit_events_v1
   WHERE action LIKE 'sales.%' OR action LIKE 'sales.invoice_%')
 THEN RAISE EXCEPTION 'SALES_P1_SECURITY_ROLLBACK_DENIED_HISTORY'; END IF;
END $guard$;
DROP TRIGGER sales_master_party_retention_0305 ON core10.master_parties_v1;
DROP TRIGGER zz_sales_invoice_confirmation_guard_0305 ON core10.sales_invoice_drafts_v1;
DROP TRIGGER sales_confirmed_requires_audit_0305 ON core10.sales_orders_v1;
DROP TRIGGER sales_invoice_commands_approval_guard_0305 ON core10.sales_invoice_commands_v1;
DROP TRIGGER sales_commands_approval_guard_0305 ON core10.sales_order_commands_v1;
DROP TRIGGER sales_invoice_commands_notruncate_0305 ON core10.sales_invoice_commands_v1;
DROP TRIGGER sales_invoice_commands_frozen_0305 ON core10.sales_invoice_commands_v1;
DROP TRIGGER sales_commands_notruncate_0305 ON core10.sales_order_commands_v1;
DROP TRIGGER sales_commands_frozen_0305 ON core10.sales_order_commands_v1;
DROP TRIGGER sales_order_lines_notruncate_0305 ON core10.sales_order_lines_v1;
DROP TRIGGER sales_order_lines_secure_0305 ON core10.sales_order_lines_v1;
DROP TRIGGER sales_order_header_notruncate_0305 ON core10.sales_orders_v1;
DROP TRIGGER sales_order_header_secure_0305 ON core10.sales_orders_v1;
DROP FUNCTION core10._sales_master_party_restrict_0305();
DROP FUNCTION core10._sales_invoice_confirmation_guard_0305();
DROP FUNCTION core10._sales_confirmed_audit_guard_0305();
DROP FUNCTION core10._sales_command_approval_guard_0305();
DROP FUNCTION core10._sales_command_frozen_0305();
DROP FUNCTION core10._sales_order_lines_guard_0305();
DROP FUNCTION core10._sales_order_header_guard_0305();
