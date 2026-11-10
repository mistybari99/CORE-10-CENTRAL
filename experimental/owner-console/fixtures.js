/* CORE 10 Owner Command Center — SYNTHETIC FIXTURE DATA ONLY.
 * Every number here is invented for layout/behaviour preview. It is NOT revenue, stock or any certified figure.
 * Shapes mirror the canonical read views (A018/A020/A021/A023/A026/A037) but this file is not an authoritative ledger. */
(function (root, factory) {
  "use strict";
  var api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  if (root) { root.C10CONSOLE = root.C10CONSOLE || {}; root.C10CONSOLE.fixtures = api; }
})(typeof window !== "undefined" ? window : (typeof globalThis !== "undefined" ? globalThis : null), function () {
  "use strict";
  var SYNTHETIC = true;
  var tenants = { 1: { id: 1, name: "Demo owned portfolio" }, 2: { id: 2, name: "Independent customer (must never be visible)" } };
  var businesses = [
    { tenant_id: 1, id: 101, slug: "demo-sweets", name: "Demo Sweets", template: "food_manufacturing", status: "active", production_certified: false },
    { tenant_id: 1, id: 102, slug: "demo-second-business", name: "Demo Second Business", template: "food_manufacturing", status: "draft", production_certified: false },
    { tenant_id: 2, id: 201, slug: "customer-business", name: "Independent Customer Business", template: "food_manufacturing", status: "active", production_certified: false }
  ];
  var sites = [
    { tenant_id: 1, business_id: 101, id: 1001, kind: "showroom", label: "A1 Showroom", locations: ["MAIN"] },
    { tenant_id: 1, business_id: 101, id: 1002, kind: "factory", label: "A2 Factory", locations: ["MAIN"] },
    { tenant_id: 1, business_id: 101, id: 1004, kind: "godown", label: "A4 Godown", locations: ["MAIN", "COLD"] },
    { tenant_id: 1, business_id: 102, id: 1003, kind: "showroom", label: "A3 Showroom", locations: ["MAIN"] },
    { tenant_id: 2, business_id: 201, id: 2001, kind: "showroom", label: "B1 Showroom", locations: ["MAIN"] }
  ];
  var MODULES = ["pos", "stock", "purchase", "production", "finance", "reports", "investors", "hr"];
  var modules = [];
  var vis = {
    101: { pos: "show", stock: "show", purchase: "show", production: "show", finance: "locked", reports: "show", investors: "locked", hr: "hidden" },
    102: { pos: "show", stock: "show", purchase: "locked", production: "hidden", finance: "hidden", reports: "locked", investors: "hidden", hr: "hidden" },
    201: { pos: "show", stock: "show", purchase: "show", production: "show", finance: "show", reports: "show", investors: "show", hr: "show" }
  };
  businesses.forEach(function (b) { MODULES.forEach(function (m) { modules.push({ tenant_id: b.tenant_id, business_id: b.id, module: m, visibility: vis[b.id][m] }); }); });
  var kpi = {
    101: { recorded_revenue: 1840500.5, recorded_costs: 1212300.25, net_manual_profit: 628200.25, unpaid_investor_balance: 82000, total_units_on_hand: 1420.5, internal_transfers: 12, unreconciled_location_items: 1, pending_owner_decisions: 2 },
    102: { recorded_revenue: 215400, recorded_costs: 190100, net_manual_profit: 25300, unpaid_investor_balance: 0, total_units_on_hand: 310, internal_transfers: 1, unreconciled_location_items: 0, pending_owner_decisions: 1 },
    201: { recorded_revenue: 999999, recorded_costs: 1, net_manual_profit: 999998, unpaid_investor_balance: 0, total_units_on_hand: 1, internal_transfers: 0, unreconciled_location_items: 0, pending_owner_decisions: 0 }
  };
  var stock = [
    { tenant_id: 1, business_id: 101, site_id: 1001, site: "A1 Showroom", item: "SWEET-A", on_hand: 120, ledger_units: 120, status: "reconciled" },
    { tenant_id: 1, business_id: 101, site_id: 1002, site: "A2 Factory", item: "RAW-SUGAR", on_hand: 36, ledger_units: 36, status: "reconciled" },
    { tenant_id: 1, business_id: 101, site_id: 1004, site: "A4 Godown", item: "RAW-FLOUR", on_hand: 54, ledger_units: 60, status: "mismatch" },
    { tenant_id: 1, business_id: 102, site_id: 1003, site: "A3 Showroom", item: "OTHER-ITEM", on_hand: 20, ledger_units: 20, status: "reconciled" },
    { tenant_id: 2, business_id: 201, site_id: 2001, site: "B1 Showroom", item: "CUSTOMER-SKU", on_hand: 5, ledger_units: 5, status: "reconciled" }
  ];
  var operations = {
    101: { purchase_documents: 14, purchase_net: 402500, sale_documents: 96, sale_net: 1840500.5, returns: 3, production_batches: 8, costed_batches: 6, uncosted_batches: 2 },
    102: { purchase_documents: 2, purchase_net: 21000, sale_documents: 11, sale_net: 215400, returns: 0, production_batches: 0, costed_batches: 0, uncosted_batches: 0 },
    201: { purchase_documents: 1, purchase_net: 1, sale_documents: 1, sale_net: 999999, returns: 0, production_batches: 0, costed_batches: 0, uncosted_batches: 0 }
  };
  var approvals = [
    { tenant_id: 1, business_id: 101, id: "R-1", kind: "module_request", title: "Show Finance module", status: "pending" },
    { tenant_id: 1, business_id: 101, id: "R-2", kind: "bom_approval", title: "Approve recipe SWEET-A v2", status: "pending" },
    { tenant_id: 1, business_id: 102, id: "R-3", kind: "return_approval", title: "Approve return #4", status: "pending" },
    { tenant_id: 2, business_id: 201, id: "R-9", kind: "module_request", title: "Foreign tenant request", status: "pending" }
  ];
  var setup = {
    101: { mode: "advanced", steps: [{ key: "legal", done: true }, { key: "sites", done: true }, { key: "modules", done: true }, { key: "roles", done: false }, { key: "branding", done: true }] },
    102: { mode: "quick", steps: [{ key: "legal", done: true }, { key: "sites", done: false }, { key: "modules", done: false }, { key: "roles", done: false }, { key: "branding", done: false }] },
    201: { mode: "quick", steps: [{ key: "legal", done: true }] }
  };
  return { SYNTHETIC: SYNTHETIC, tenants: tenants, businesses: businesses, sites: sites, modules: modules, MODULES: MODULES,
    kpi: kpi, stock: stock, operations: operations, approvals: approvals, setup: setup };
});
