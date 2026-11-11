-- C10-A023: canonical, tenant-safe business and consolidated reporting read models.
-- Disposible PG17 prototype. Currency and POS ledger are NOT yet certified.
-- Transfers are internal: never count as sales or purchases; no phantom KPIs.
-- Each raw table has RLS; all views explicitly security_invoker=true.
CREATE VIEW c10_demo.business_finance_report_v1 WITH(security_invoker=true) AS
 SELECT b.tenant_id,b.id AS business_id,b.slug,
  COALESCE(cfg.display_name,b.slug) AS display_name,
  b.status AS business_status,
  COALESCE(f.months_count,0)::bigint AS approved_manual_months,
  COALESCE(f.revenue,0)::numeric(20,2) AS recorded_revenue,
  COALESCE(f.costs,0)::numeric(20,2) AS recorded_costs,
  COALESCE(f.profit,0)::numeric(20,2) AS net_manual_profit,
  COALESCE(c.contract_count,0)::bigint AS investor_contracts,
  COALESCE(p.allocated,0)::numeric(20,2) AS profit_entitlements,
  COALESCE(pm.paid,0)::numeric(20,2) AS recorded_investor_payments,
  (COALESCE(p.allocated,0)-COALESCE(pm.paid,0))::numeric(20,2) AS unpaid_investor_balance,
  'manual_unverified'::text AS finance_data_source,
  false::boolean AS reconciled_to_live_pos
 FROM c10_demo.businesses b
 LEFT JOIN c10_demo.business_configuration_v1 cfg ON cfg.business_id=b.id
 LEFT JOIN LATERAL (
  SELECT count(*) AS months_count,sum(m.revenue) AS revenue,
   sum(m.costs) AS costs,sum(m.net_profit) AS profit
  FROM c10_demo.finance_months_v1 m
  WHERE m.business_id=b.id AND m.status='owner_approved'
 ) f ON true
 LEFT JOIN LATERAL (
  SELECT count(*) AS contract_count FROM c10_demo.funding_agreements_v1 a
  WHERE a.business_id=b.id AND a.status='active'
 ) c ON true
 LEFT JOIN LATERAL (
  SELECT sum(e.amount) AS allocated FROM c10_demo.funding_entitlements_v1 e
  WHERE e.business_id=b.id
 ) p ON true
 LEFT JOIN LATERAL (
  SELECT sum(pm.paid_amount) AS paid FROM c10_demo.funding_payments_v1 pm
  WHERE pm.business_id=b.id
 ) pm ON true
 WHERE c10_demo.can_manage(b.tenant_id,b.id);

CREATE VIEW c10_demo.business_inventory_report_v1 WITH(security_invoker=true) AS
 SELECT b.tenant_id,b.id AS business_id,b.slug,
  COALESCE(s.site_count,0)::bigint AS sites,
  COALESCE(l.location_count,0)::bigint AS stock_locations,
  COALESCE(st.on_hand,0)::numeric(20,3) AS total_units_on_hand,
  COALESCE(j.external_receipts,0)::numeric(20,3) AS received_units_excluding_transfers,
  COALESCE(j.external_issues,0)::numeric(20,3) AS issued_units_excluding_transfers,
  COALESCE(t.transfer_count,0)::bigint AS internal_transfers,
  COALESCE(t.internal_transferred_units,0)::numeric(20,3) AS internal_transferred_units,
  COALESCE(v.mismatch_count,0)::bigint AS unreconciled_location_items,
  false::boolean AS cost_valuation_certified
 FROM c10_demo.businesses b
 LEFT JOIN LATERAL(
  SELECT count(*) AS site_count FROM c10_demo.sites s WHERE s.business_id=b.id
 ) s ON true
 LEFT JOIN LATERAL(
  SELECT count(*) AS location_count FROM c10_demo.stock_locations l
  WHERE l.business_id=b.id
 ) l ON true
 LEFT JOIN LATERAL(
  SELECT sum(st.on_hand) AS on_hand FROM c10_demo.stock_balances_v1 st
  WHERE st.business_id=b.id
 ) st ON true
 LEFT JOIN LATERAL(
  SELECT sum(CASE WHEN sm.delta>0 THEN sm.delta ELSE 0 END) AS external_receipts,
   sum(CASE WHEN sm.delta<0 THEN -sm.delta ELSE 0 END) AS external_issues
  FROM c10_demo.stock_movements sm
  WHERE sm.business_id=b.id AND sm.transfer_id IS NULL
 ) j ON true
 LEFT JOIN LATERAL(
  SELECT count(*) AS transfer_count,sum(tr.quantity) AS internal_transferred_units
  FROM c10_demo.stock_transfers_v1 tr WHERE tr.business_id=b.id
 ) t ON true
 LEFT JOIN LATERAL(
  SELECT count(*) AS mismatch_count FROM c10_demo.inventory_reconciliation_v1 r
  WHERE r.business_id=b.id AND NOT r.reconciled
 ) v ON true
 WHERE c10_demo.can_manage(b.tenant_id,b.id);

CREATE VIEW c10_demo.owner_business_kpi_v1 WITH(security_invoker=true) AS
 SELECT f.tenant_id,f.business_id,f.slug,f.display_name,f.business_status,
  f.approved_manual_months,f.recorded_revenue,f.recorded_costs,
  f.net_manual_profit,f.investor_contracts,f.profit_entitlements,
  f.recorded_investor_payments,f.unpaid_investor_balance,
  s.sites,s.stock_locations,s.total_units_on_hand,
  s.received_units_excluding_transfers,s.issued_units_excluding_transfers,
  s.internal_transfers,s.internal_transferred_units,
  s.unreconciled_location_items,
  COALESCE(c.pending_owner_decisions,0)::bigint AS pending_owner_decisions,
  false::boolean AS operationally_certified
 FROM c10_demo.business_finance_report_v1 f
 JOIN c10_demo.business_inventory_report_v1 s
  ON s.business_id=f.business_id AND s.tenant_id=f.tenant_id
 LEFT JOIN c10_demo.owner_business_control_board_v1 c
  ON c.business_id=f.business_id AND c.tenant_id=f.tenant_id;

-- Tenant owner sees all its businesses; business owner cannot elevate to master.
CREATE VIEW c10_demo.tenant_consolidated_kpi_v1 WITH(security_invoker=true) AS
 SELECT f.tenant_id,
  count(*)::bigint AS visible_businesses,
  COALESCE(sum(f.approved_manual_months),0)::bigint AS approved_manual_months,
  COALESCE(sum(f.recorded_revenue),0)::numeric(20,2) AS recorded_revenue,
  COALESCE(sum(f.recorded_costs),0)::numeric(20,2) AS recorded_costs,
  COALESCE(sum(f.net_manual_profit),0)::numeric(20,2) AS net_manual_profit,
  COALESCE(sum(f.profit_entitlements),0)::numeric(20,2) AS profit_entitlements,
  COALESCE(sum(f.recorded_investor_payments),0)::numeric(20,2) AS recorded_investor_payments,
  COALESCE(sum(f.unpaid_investor_balance),0)::numeric(20,2) AS unpaid_investor_balance,
  COALESCE(sum(s.sites),0)::bigint AS sites,
  COALESCE(sum(s.total_units_on_hand),0)::numeric(20,3) AS on_hand_units_all_skus,
  COALESCE(sum(s.internal_transfers),0)::bigint AS internal_transfers_excluded_from_sales,
  COALESCE(sum(s.unreconciled_location_items),0)::bigint AS stock_integrity_failures,
  false::boolean AS enterprise_ready
 FROM c10_demo.business_finance_report_v1 f
 JOIN c10_demo.business_inventory_report_v1 s
  ON f.tenant_id=s.tenant_id AND f.business_id=s.business_id
 WHERE c10_demo.can_tenant(f.tenant_id)
 GROUP BY f.tenant_id;
-- Valuation, mixed SKU units, VAT, actual POS and bank statements are not certified.
-- on_hand_units_all_skus is strictly a technical sum, NOT a valued inventory KPI.

REVOKE ALL ON c10_demo.business_finance_report_v1,
 c10_demo.business_inventory_report_v1,c10_demo.owner_business_kpi_v1,
 c10_demo.tenant_consolidated_kpi_v1 FROM PUBLIC;
GRANT SELECT ON c10_demo.business_finance_report_v1,
 c10_demo.business_inventory_report_v1,c10_demo.owner_business_kpi_v1,
 c10_demo.tenant_consolidated_kpi_v1 TO authenticated;
