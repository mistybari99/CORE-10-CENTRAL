"use strict";

/* Issue #68 deterministic synthetic evidence only; no auth, posting, provider, or production calls. */
const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const { readManifest } = require("../demo-identity-program/index.js");

const SCHEMA_VERSION = "core10-global-demo-factory-v1";
const SEED = "CORE10-DEMO-2026-11-11";
const sha256 = value => crypto.createHash("sha256").update(String(value)).digest("hex");

function buildStructuralSites() {
  const plans = [
    { tenant_id: 1, business_id: 101, prefix: "SWEET", kinds: ["showroom", "factory", "warehouse"] },
    { tenant_id: 1, business_id: 102, prefix: "PAINT", kinds: ["showroom", "warehouse", "service"] },
    { tenant_id: 2, business_id: 201, prefix: "BUILD", kinds: ["project", "warehouse", "office"] }
  ];
  return plans.flatMap((plan, businessIndex) => Array.from({ length: 101 }, (_, index) => ({
    tenant_id: plan.tenant_id,
    business_id: plan.business_id,
    site_id: 900000 + businessIndex * 1000 + index + 1,
    code: `DEMO-${plan.prefix}-${String(index + 1).padStart(3, "0")}`,
    kind: plan.kinds[index % plan.kinds.length],
    status: "STRUCTURAL_FIXTURE_ONLY"
  })));
}

const journal = (id, source_document_id, lines) => ({
  id, source_document_id, currency: "XTS",
  lines: lines.map(([account, debit_minor, credit_minor]) => ({ account, debit_minor, credit_minor }))
});

function buildGoldenScenario() {
  const documents = [
    { id: "DEMO-REQ-001", type: "requisition", status: "approved", quantity: 50, uom: "kg", effect: "commitment_only" },
    { id: "DEMO-PO-001", type: "purchase_order", source_id: "DEMO-REQ-001", status: "approved", quantity: 50, unit_cost_minor: 4000, effect: "commitment_only" },
    { id: "DEMO-GR-001", type: "goods_receipt", source_id: "DEMO-PO-001", status: "accepted", quantity: 50, unit_cost_minor: 4000, effect: "stock_receipt" },
    { id: "DEMO-TR-001", type: "transfer", source_id: "DEMO-GR-001", status: "received", quantity: 30, effect: "stock_only_no_revenue" },
    { id: "DEMO-MO-001", type: "production", source_id: "DEMO-TR-001", status: "completed", flour_consumed_kg: 20, finished_quantity: 100, finished_unit_cost_minor: 1000, effect: "inventory_transformation" },
    { id: "DEMO-SI-001", type: "sale_invoice", status: "posted_fixture_expectation", quantity: 40, unit_price_minor: 1800, unit_cost_minor: 1000, effect: "stock_ar_revenue_cogs" },
    { id: "DEMO-RET-001", type: "customer_return", source_id: "DEMO-SI-001", status: "inspected_resellable", quantity: 5, unit_price_minor: 1800, unit_cost_minor: 1000, effect: "source_linked_reversal" },
    { id: "DEMO-CR-001", type: "customer_receipt", source_id: "DEMO-SI-001", status: "settled_fixture_expectation", amount_minor: 30000, effect: "cash_ar_only" },
    { id: "DEMO-SP-001", type: "supplier_payment", source_id: "DEMO-PO-001", status: "settled_fixture_expectation", amount_minor: 50000, effect: "cash_ap_only" }
  ];
  const journals = [
    journal("DEMO-JRN-001", "DEMO-GR-001", [["inventory_raw", 200000, 0], ["receipt_clearing", 0, 200000]]),
    journal("DEMO-JRN-002", "DEMO-PO-001", [["receipt_clearing", 200000, 0], ["accounts_payable", 0, 200000]]),
    journal("DEMO-JRN-003", "DEMO-MO-001", [["work_in_progress", 80000, 0], ["inventory_raw", 0, 80000]]),
    journal("DEMO-JRN-004", "DEMO-MO-001", [["work_in_progress", 20000, 0], ["accrued_overhead", 0, 20000]]),
    journal("DEMO-JRN-005", "DEMO-MO-001", [["inventory_finished", 100000, 0], ["work_in_progress", 0, 100000]]),
    journal("DEMO-JRN-006", "DEMO-SI-001", [["accounts_receivable", 72000, 0], ["sales_revenue", 0, 72000]]),
    journal("DEMO-JRN-007", "DEMO-SI-001", [["cost_of_goods_sold", 40000, 0], ["inventory_finished", 0, 40000]]),
    journal("DEMO-JRN-008", "DEMO-RET-001", [["sales_returns", 9000, 0], ["accounts_receivable", 0, 9000]]),
    journal("DEMO-JRN-009", "DEMO-RET-001", [["inventory_finished", 5000, 0], ["cost_of_goods_sold", 0, 5000]]),
    journal("DEMO-JRN-010", "DEMO-CR-001", [["cash", 30000, 0], ["accounts_receivable", 0, 30000]]),
    journal("DEMO-JRN-011", "DEMO-SP-001", [["accounts_payable", 50000, 0], ["cash", 0, 50000]])
  ];
  return {
    scenario_id: "DEMO-GOLDEN-CHAIN-001", tenant_id: 1, business_id: 101,
    sites: { warehouse: 1001, factory: 1002 },
    request_contracts: ["A048 inventory command v1", "A049 operation workflow v1"],
    documents, journals,
    expected: {
      transfer_revenue_minor: 0, raw_inventory_kg: 130, finished_inventory_units: 65,
      net_revenue_minor: 63000, net_cogs_minor: 35000, gross_margin_minor: 28000,
      accounts_receivable_minor: 33000, accounts_payable_minor: 150000,
      net_cash_change_minor: -20000, finance_truth: "EXPECTED_MATH_ONLY_NOT_POSTED"
    }
  };
}

function buildFactory() {
  const identities = readManifest();
  const fixture = {
    schema_version: SCHEMA_VERSION, seed: SEED,
    classification: "FULLY_SYNTHETIC_PUBLIC_REPOSITORY_SAFE",
    truth_level: "GENERATED_FIXTURE_AND_EXPECTED_MATH_ONLY",
    prohibitions: ["NO_PRODUCTION_DATA", "NO_REAL_GOTRUE_USERS", "NO_STOCK_OR_LEDGER_POSTING", "NO_PROVIDER_CALLS"],
    source_contracts: {
      identity_manifest: "internal/demo-identity-program/demo-identity-manifest-v1.json",
      identity_schema_version: identities.schema_version,
      inventory: "internal/enterprise-sql/c10_a048_inventory_commands_v1.sql",
      operations: "internal/enterprise-sql/c10_a049_operation_workflow_v1.sql"
    },
    persona_refs: identities.personas.map(({ key, uid }) => ({ key, uid })),
    tenants: [
      { id: 1, code: "DEMO-TENANT-ALPHA", currency: "XTS", timezone: "Asia/Dhaka" },
      { id: 2, code: "DEMO-TENANT-BETA", currency: "XTS", timezone: "UTC" }
    ],
    businesses: [
      { tenant_id: 1, id: 101, code: "DEMO-SWEET", pack: "sweets_bakery" },
      { tenant_id: 1, id: 102, code: "DEMO-PAINT", pack: "paint_hardware" },
      { tenant_id: 2, id: 201, code: "DEMO-CONSTRUCTION", pack: "construction" },
      { tenant_id: 2, id: 202, code: "DEMO-RESTAURANT", pack: "restaurant" },
      { tenant_id: 2, id: 203, code: "DEMO-WHOLESALE", pack: "retail_wholesale" },
      { tenant_id: 2, id: 204, code: "DEMO-TECH", pack: "technology_services" }
    ],
    functional_sites: [
      { tenant_id: 1, business_id: 101, id: 1001, code: "DEMO-SWEET-WH", kind: "warehouse" },
      { tenant_id: 1, business_id: 101, id: 1002, code: "DEMO-SWEET-FACTORY", kind: "factory" },
      { tenant_id: 1, business_id: 102, id: 1003, code: "DEMO-PAINT-SHOWROOM", kind: "showroom" },
      { tenant_id: 2, business_id: 201, id: 2001, code: "DEMO-BUILD-PROJECT", kind: "project" }
    ],
    structural_sites: buildStructuralSites(),
    parties: [
      { id: "DEMO-SUP-001", role: "supplier", name: "DEMO River Grain Cooperative" },
      { id: "DEMO-CUS-001", role: "customer", name: "DEMO Community Market" },
      { id: "DEMO-CON-001", role: "contractor", name: "DEMO Safe Build Crew" }
    ],
    items: [
      { id: "DEMO-ITEM-FLOUR", name: "DEMO Test Flour", stock_uom: "kg", lot: "DEMO-LOT-FLR-001", expiry: "2027-06-30" },
      { id: "DEMO-ITEM-SWEET", name: "DEMO Test Sweet Pack", stock_uom: "each", lot: "DEMO-LOT-SWT-001", expiry: "2026-11-18" },
      { id: "DEMO-ITEM-PAINT", name: "DEMO Blue Sample Paint", stock_uom: "litre", lot: "DEMO-LOT-PNT-001", expiry: "2028-01-31" },
      { id: "DEMO-ITEM-CEMENT", name: "DEMO Test Cement Bag", stock_uom: "bag", lot: "DEMO-LOT-CEM-001", expiry: null }
    ],
    uom_conversions: [
      { item_id: "DEMO-ITEM-FLOUR", from: "bag", to: "kg", numerator: 25, denominator: 1 },
      { item_id: "DEMO-ITEM-PAINT", from: "can", to: "litre", numerator: 4, denominator: 1 }
    ],
    golden_scenario: buildGoldenScenario(),
    negative_cases: [
      { id: "DEMO-NEG-001", case: "negative_stock_attempt", expected: "inventory_insufficient" },
      { id: "DEMO-NEG-002", case: "same_key_changed_payload", expected: "idempotency_conflict" },
      { id: "DEMO-NEG-003", case: "offline_replay_after_revocation", expected: "authorization_denied_unposted" },
      { id: "DEMO-NEG-004", case: "cross_tenant_direct_request", expected: "scope_denied_no_disclosure" },
      { id: "DEMO-NEG-005", case: "missing_source_cost", expected: "INCOMPLETE_NOT_ZERO" },
      { id: "DEMO-NEG-006", case: "duplicate_serial", expected: "duplicate_identifier_denied" },
      { id: "DEMO-NEG-007", case: "closed_period_replay", expected: "period_closed_unposted" }
    ],
    lifecycle: { reset: "REGENERATE_FROM_SEED_NO_MUTABLE_STATE", delete_before_go_live: true, signed_auth_stage: "NOT_TESTED", production: "PROHIBITED" }
  };
  fixture.provenance_sha256 = sha256(JSON.stringify(fixture));
  return fixture;
}

function validateFactory(fixture) {
  assert.equal(fixture.schema_version, SCHEMA_VERSION);
  assert.equal(fixture.classification, "FULLY_SYNTHETIC_PUBLIC_REPOSITORY_SAFE");
  assert.equal(fixture.tenants.length, 2);
  assert(fixture.businesses.length >= 3);
  assert.equal(fixture.structural_sites.length, 303);
  assert.equal(new Set(fixture.structural_sites.map(s => s.site_id)).size, 303);
  assert.equal(fixture.persona_refs.length, 16);
  assert(fixture.items.every(item => item.name.startsWith("DEMO ")));
  assert(fixture.parties.every(party => party.name.startsWith("DEMO ")));
  assert.equal(fixture.golden_scenario.documents.find(d => d.type === "transfer").effect, "stock_only_no_revenue");
  assert.equal(fixture.golden_scenario.expected.transfer_revenue_minor, 0);
  assert.equal(fixture.golden_scenario.expected.finished_inventory_units, 100 - 40 + 5);
  assert.equal(fixture.golden_scenario.expected.net_revenue_minor, 72000 - 9000);
  assert.equal(fixture.golden_scenario.expected.net_cogs_minor, 40000 - 5000);
  assert.equal(fixture.golden_scenario.expected.gross_margin_minor, 28000);
  for (const entry of fixture.golden_scenario.journals) {
    const debit = entry.lines.reduce((sum, line) => sum + line.debit_minor, 0);
    const credit = entry.lines.reduce((sum, line) => sum + line.credit_minor, 0);
    assert.equal(debit, credit, `${entry.id} is unbalanced`);
    assert(entry.source_document_id, `${entry.id} lacks source lineage`);
  }
  assert.equal(fixture.golden_scenario.documents.find(d => d.type === "customer_return").source_id, "DEMO-SI-001");
  assert(fixture.negative_cases.some(c => c.expected === "INCOMPLETE_NOT_ZERO"));
  assert(fixture.negative_cases.some(c => c.case === "offline_replay_after_revocation"));
  assert.equal(fixture.lifecycle.signed_auth_stage, "NOT_TESTED");
  const copy = { ...fixture }; delete copy.provenance_sha256;
  assert.equal(fixture.provenance_sha256, sha256(JSON.stringify(copy)));
  return true;
}

function report(fixture) {
  validateFactory(fixture);
  return [
    "CORE 10 GLOBAL DEMO FACTORY — SYNTHETIC EVIDENCE ONLY",
    `schema=${fixture.schema_version}`, `seed=${fixture.seed}`,
    `tenants=${fixture.tenants.length} businesses=${fixture.businesses.length} personas_reused=${fixture.persona_refs.length}`,
    `structural_sites=${fixture.structural_sites.length} balanced_expected_journals=${fixture.golden_scenario.journals.length}`,
    `golden_scenario=${fixture.golden_scenario.scenario_id} gross_margin_minor=${fixture.golden_scenario.expected.gross_margin_minor}`,
    `negative_cases=${fixture.negative_cases.length}`, `provenance_sha256=${fixture.provenance_sha256}`,
    "truth=fixture generated + expected math validated; database posting/auth/provider/deployment NOT TESTED"
  ].join("\n");
}

if (require.main === module) {
  const fixture = buildFactory(); validateFactory(fixture);
  if ((process.argv[2] || "report") === "json") process.stdout.write(JSON.stringify(fixture, null, 2) + "\n");
  else process.stdout.write(report(fixture) + "\n");
}
module.exports = { SCHEMA_VERSION, SEED, buildFactory, validateFactory, report };
