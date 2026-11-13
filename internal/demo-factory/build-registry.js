"use strict";

const fs = require("node:fs");
const path = require("node:path");
const assert = require("node:assert/strict");

const ROOT = path.resolve(__dirname, "../..");
const OUT_JSON = path.join(ROOT, "docs/strategy/UNIVERSAL_CAPABILITY_REGISTER.json");
const OUT_CSV = path.join(ROOT, "docs/strategy/UNIVERSAL_CAPABILITY_REGISTER.csv");
const FIELDS = [
  "feature_id", "domain", "business_sector_applicability", "personas", "workflow_inputs_outputs",
  "canonical_source_of_truth", "ledger_stock_report_side_effects", "exception_cases",
  "core_pack_adapter_classification", "ux_placement_default_visibility", "authorization_contract",
  "official_benchmark_url_date", "existing_repo_file_pr_sha", "current_technical_state", "dependency",
  "priority", "free_first_availability", "test_fixture_ids", "owner_decision_link", "decision_reason",
  "source_candidate_ids"
];

const seq = (prefix, count, pad = 3) => Array.from({ length: count }, (_, i) => `${prefix}${String(i + 1).padStart(pad, "0")}`);
const allCandidateIds = [
  ...seq("A1-CAP-", 16), ...seq("A2-OPS-", 12), ...seq("A3-V", 25),
  "A4-GLO-001", "A4-GLO-002", "A4-GLO-003", "A4-GLO-004", "A4-GLO-005", "A4-GLO-006",
  "A4-SEC-001", "A4-SEC-002", "A4-SEC-003", "A4-OPS-001", "A4-OPS-002", "A4-OPS-003",
  "A4-AUD-001", "A4-DR-001", "A4-UX-001", "A4-FRAUD-001",
  ...seq("B1-CAP-", 25), ...seq("B2-CAP-", 22)
];

function feature(feature_id, domain, classification, workflow, effects, exceptions, benchmark, existing, state, dependency, priority, tests, decisions, reason, source_candidate_ids, applicability = "all applicable tenants/businesses; pack rules where named", personas = "authorized owner, manager, operator, accountant, auditor") {
  return {
    feature_id, domain, business_sector_applicability: applicability, personas,
    workflow_inputs_outputs: workflow,
    canonical_source_of_truth: "typed server record/event with tenant, legal entity, business, site and source-document identity",
    ledger_stock_report_side_effects: effects,
    exception_cases: exceptions,
    core_pack_adapter_classification: classification,
    ux_placement_default_visibility: "task workspace; advanced detail progressively disclosed; readiness and incompleteness visible",
    authorization_contract: "server-enforced A018/A021/A034-compatible action and scope; explicit deny/expiry; UI visibility is not authority",
    official_benchmark_url_date: `${benchmark} (retrieved 2026-11-11)`,
    existing_repo_file_pr_sha: existing,
    current_technical_state: state,
    dependency, priority,
    free_first_availability: "open protocols/local Node/PostgreSQL disposable CI; hosted scale and providers separately cost-gated",
    test_fixture_ids: tests,
    owner_decision_link: decisions,
    decision_reason: reason,
    source_candidate_ids: source_candidate_ids.length ? source_candidate_ids.join(";") : "NONE-DIRECT-MANDATE"
  };
}

function rows() {
  return [
    feature("C10-CAP-GOV-001", "tenant and organization scope", "platform governance + shared core", "provision tenant→legal entity→business→site→location; resolve signed actor scope", "no ledger effect; scoped reports only", "cross-tenant request, revoked user, platform operator without consent", "https://learn.microsoft.com/en-us/dynamics365/fin-ops-core/dev-itpro/sysadmin/role-based-security", "PR#7@1c55625 A018/A019; live SG UNKNOWN", "isolated-tested", "signed GoTrue staging and legacy bridge", "P0", "DEMO-NEG-003;DEMO-NEG-004", "D030,D032,D033,D036,D037;R125", "one canonical scope prevents implicit cross-business authority", ["B1-CAP-002", "B1-CAP-003", "B2-CAP-002", "A4-SEC-001"]),
    feature("C10-CAP-GOV-002", "approval and segregation of duties", "platform governance + shared core", "request→policy/payload fingerprint→scoped approval→execute/reverse", "domain effect occurs only after typed execution", "self approval, stale payload, delegation loop, expired approval", "https://docs.oracle.com/cd/E36909_01/fusionapps.1111/e37378/F533077AN20EBE.htm", "PR#7 A021/A044; PR#22 A034 draft", "draft-only", "effective authorization and one typed approval service", "P0", "DEMO-NEG-003", "D033,D045;R123,R124,R128", "maker-checker cannot be replaced by menu placement", ["A2-OPS-012", "A4-SEC-002", "A4-SEC-003", "B1-CAP-004", "B1-CAP-011"]),
    feature("C10-CAP-GOV-003", "audit, fraud and readiness truth", "platform governance", "correlate command, approval, event, reversal and evidence; triage advisory risk", "append-only audit; no autonomous stock/money effect", "log tamper, secret leakage, false-positive fraud, fake readiness", "https://cheatsheetseries.owasp.org/cheatsheets/Logging_Cheat_Sheet.html", "PR#7 synthetic audit; deployment receipt absent", "specified", "tenant-safe observability and evidence registry", "P0", "DEMO-NEG-002", "D029,D041,D043,D049", "truth levels and audit evidence prevent preview-to-production confusion", ["A4-AUD-001", "A4-FRAUD-001", "B1-CAP-019"]),
    feature("C10-CAP-SETUP-001", "Quick and Advanced setup", "shared core", "validated profile→atomic idempotent hierarchy/master setup→activation report", "setup only; no fabricated opening balances", "crash/retry, duplicate code, unsupported tax policy, orphan site", "https://learning.sap.com/courses/exploring-core-sap-cloud-implementation-tasks/defining-localizations-and-scope_c0eb3c85-bd1b-4db6-9701-5db1b36c9599", "PR#7 A020 disposable SQL", "isolated-tested", "GOV-001 and versioned recommended profiles", "P0", "DEMO-TENANT-ALPHA;303-site", "D030,D032;R126", "Quick and Advanced must drive the same engine", ["B2-CAP-001"]),
    feature("C10-CAP-MDM-001", "party, catalog and UOM master data", "shared core", "create/version/dedupe party, item, variant, UOM and barcode", "no posting; downstream documents reference immutable versions", "duplicate party, incompatible UOM, density mistaken for conversion", "https://digitallibrary.un.org/record/668541", "main legacy masters + PR#7 demo contracts", "partial", "GOV-001", "P0", "DEMO-ITEM-FLOUR;DEMO-ITEM-PAINT", "D031,D042;REV-009", "neutral master data must not clone Islamia customization", ["A4-GLO-005"]),
    feature("C10-CAP-SALES-001", "order-to-cash and POS", "shared core", "quote/order→reserve→fulfil→invoice→settle→return", "stock, AR/revenue/tax/COGS only at their distinct events", "credit hold, split fulfilment, offline duplicate, return disposition", "https://learning.sap.com/courses/cost-object-controlling-in-sap-s-4hana/managing-sales-orders", "PR#7 A049 first slice; finance incomplete", "isolated-tested-first-slice", "canonical journal/COGS and signed auth", "P0", "DEMO-SI-001;DEMO-RET-001", "D047,D048,D049;R127,R128", "sale, stock issue, invoice and payment are separate", ["A1-CAP-001", "A1-CAP-002", "A1-CAP-006", "A1-CAP-016", "A2-OPS-001", "A2-OPS-002", "A2-OPS-003", "A3-V010", "A3-V011", "B1-CAP-001", "B1-CAP-005", "B1-CAP-007", "B1-CAP-009", "B2-CAP-019"]),
    feature("C10-CAP-CHANNEL-001", "marketplace, subscriptions and omnichannel", "optional adapter + governed pack", "external order/contract→canonical order→fulfil→settlement reconciliation", "provider liabilities/fees distinct; no direct ledger authority", "duplicate webhook, seller dispute, proration, payout reversal", "https://help.shopify.com/en/manual/products/purchase-options", "PR#27 integration ports draft; no Drive/channel production", "specified", "SALES-001 and PR#27", "P1", "DEMO-NEG-002", "D031,D049", "external channels remain adapters", ["A1-CAP-003", "A1-CAP-004", "A1-CAP-005", "B1-CAP-020", "B1-CAP-021", "B2-CAP-006", "B2-CAP-010"]),
    feature("C10-CAP-FRANCHISE-001", "franchise network", "industry pack", "agreement/territory→outlet operations→royalty declaration→audit", "royalty invoice/settlement only from approved contract evidence", "independent franchisee mistaken for internal branch", "https://www.franchise.org/franchising-overview/introduction-to-the-franchise-business-model/", "no runtime; registry candidate", "specified", "agreements, intercompany and finance", "P2", "DEMO-FRANCHISE-NOT-BUILT", "D031", "legal independence prevents treating every outlet as a site", ["A1-CAP-007"]),
    feature("C10-CAP-PROC-001", "procure-to-pay and receiving", "shared core", "requisition→RFQ→PO→receipt/QC→invoice→payment", "receipt stock; invoice AP; payment cash; each source-linked", "partial/over receipt, reject, duplicate invoice, landed cost", "https://docs.oracle.com/en/cloud/saas/procurement/26d/fapra/api-requisition-lifecycle-details.html", "PR#7 A049 first slice", "isolated-tested-first-slice", "inventory, finance, approvals", "P0", "DEMO-REQ-001;DEMO-PO-001;DEMO-GR-001", "D047,D048;R127", "commitment, receipt, liability and settlement are distinct", ["A1-CAP-008", "A2-OPS-004", "A2-OPS-005", "B1-CAP-006", "B2-CAP-003", "B2-CAP-017"]),
    feature("C10-CAP-INV-001", "canonical inventory and transfer", "shared core", "authorized command→reserve/issue/receive/transfer→immutable movement", "quantity conserved; same-business transfer has zero revenue", "negative stock, duplicate request, in-transit loss, stale count", "https://help.shopify.com/en/manual/inventory-and-locations/inventory-transfers", "PR#7 A018/A048", "isolated-tested", "GOV-001, MDM-001", "P0", "DEMO-TR-001;DEMO-NEG-001;DEMO-NEG-002", "D048;R127", "one stock book; no pack ledger", ["A2-OPS-006", "B1-CAP-013"]),
    feature("C10-CAP-INV-002", "lot serial expiry quality recall and counts", "shared core + regulated adapter", "receive identifiers→quarantine/release→count/trace/recall", "availability and valuation adjust only after approved events", "duplicate serial, expired lot, count movement, partial recall", "https://support.gs1.org/support/solutions/articles/43000734475-how-does-traceability-work-", "PR#7 A038 stocktake; lot/serial incomplete", "partial", "INV-001 and QC policy", "P0", "DEMO-LOT-FLR-001;DEMO-NEG-006", "D031,D048", "traceability is transferable; certification is not", ["A2-OPS-007", "A3-V001", "A3-V003", "A3-V024", "B2-CAP-004"]),
    feature("C10-CAP-MFG-001", "manufacturing, BOM, WIP and maintenance", "shared manufacturing core + packs", "demand→BOM/routing→issue→operation/QC→receipt→variance", "raw/WIP/finished stock and source-backed cost", "substitution, scrap, rework, downtime, missing cost", "https://www.isa.org/standards-and-publications/isa-standards/isa-95-standard", "PR#7 A027/A049; A055 Claude WIP protected", "partial", "INV-001, finance boundary, A055 parity", "P0", "DEMO-MO-001", "D047,D048,D049", "MES and maintenance extend but do not replace ERP truth", ["A1-CAP-012", "A2-OPS-010", "A3-V008", "A3-V009", "B2-CAP-005"]),
    feature("C10-CAP-FOOD-001", "restaurant and food service", "industry pack", "menu/check→KOT/KDS→serve/deliver→close; recipe consumption", "sale/stock/settlement through shared engines", "split check, modifier shortage, void after fire, KDS outage", "https://pos.toasttab.com/products", "preview/registry only", "specified", "SALES-001, INV-001, MFG-001", "P1", "DEMO-RESTAURANT", "D031", "restaurant vocabulary cannot fork ledger", ["A3-V002", "B2-CAP-007"]),
    feature("C10-CAP-PAINT-001", "paint hardware and dealership", "industry pack + safety adapter", "formula/shade→tint batch→QC→dealer sale/rebate evidence", "base/pigment stock, margin and governed rebate", "retint, mismatch, PDC, unsafe substitution, obsolete SDS", "https://www.osha.gov/hazcom", "synthetic business only", "specified", "MFG-001, SALES-001, jurisdiction policy", "P1", "DEMO-PAINT", "D031", "formula/version and hazard rules are pack-specific", ["A3-V006", "A3-V007"]),
    feature("C10-CAP-PROJ-001", "projects construction and field service", "industry packs over shared project/work-order core", "bid/BOQ/contract→work/resource/material→acceptance→billing", "project stock/cost/WIP/retention source-linked", "change order, disputed progress, no-access visit, repeat work", "https://technical.buildingsmart.org/standards/IFC/", "A055 Claude WIP maintenance; construction not built", "specified", "agreements, inventory, workforce, finance", "P1", "DEMO-CONSTRUCTION", "D031,D047", "BIM and field systems link; GL remains canonical", ["A1-CAP-009", "A1-CAP-010", "A3-V004", "A3-V005", "A3-V013", "A3-V019", "B2-CAP-008", "B2-CAP-009", "B2-CAP-016"]),
    feature("C10-CAP-ASSET-001", "rental hospitality real estate automotive reservations", "industry packs over asset/reservation core", "reserve asset/resource→dispatch/check-in/use→return/close→condition/service", "custody, utilization, charges and maintenance evidence", "overbooking, damage, room move, recall, early termination", "https://learn.microsoft.com/en-us/dynamics365/supply-chain/rental-management/rental-management-overview", "A055 Claude WIP protected; other packs not built", "specified", "A055 parity, agreements and finance", "P2", "DEMO-ASSET-NOT-BUILT", "D031,D049", "shared capacity does not erase vertical states", ["A1-CAP-011", "A3-V014", "A3-V015", "A3-V018", "A3-V025"]),
    feature("C10-CAP-TRADE-001", "international trade logistics and customs", "industry pack + optional jurisdiction adapters", "contract→shipment/documents→customs response→receipt/landed cost", "inventory/AP/FX only from verified evidence", "customs hold, demurrage, missing origin, amended declaration", "https://unece.org/trade/uncefact/mainstandards", "legacy landed UI; generic adapter not certified", "specified", "PROC-001, finance, PR#27", "P1", "DEMO-TRADE-NOT-BUILT", "D031,D049", "ERP document is not a customs filing", ["A3-V012", "A4-GLO-006"]),
    feature("C10-CAP-FIN-001", "double-entry finance AP AR cash and COGS", "shared core", "typed domain request→balanced source-linked journal→reversal/reconcile/close", "DR=CR; AR/AP/cash/COGS distinct; unknown cost incomplete", "closed period, missing rate/cost, duplicate post, reversal dependency", "https://learn.microsoft.com/en-us/dynamics365/business-central/across-business-functionality", "PR#7 A022 manual_unverified; PR#21 costing draft", "gap-blocking-certification", "canonical posting boundary and signed auth", "P0", "DEMO-JRN-001..011", "D034,D035,D041,D048,D049", "no current draft is a certified canonical GL", ["A4-GLO-001", "B1-CAP-016", "B2-CAP-021"]),
    feature("C10-CAP-FIN-002", "tax localization and consolidation", "platform policy + jurisdiction adapters", "evidence+tax point→versioned policy→tax lines/filing adapter; consolidate/eliminate", "versioned tax/FX/elimination reports", "reverse charge, exemption, intercompany mismatch, unknown policy", "https://www.oecd.org/en/publications/international-vat-gst-guidelines_9789264271401-en.html", "not certified; no rates approved", "research-only-region-validation", "FIN-001 and professional review", "P1", "DEMO-NEG-005", "D035,D049", "global support means explicit unknown, not guessed law", ["A1-CAP-015", "A4-GLO-002", "B1-CAP-008", "B1-CAP-015", "B1-CAP-022", "B2-CAP-014"]),
    feature("C10-CAP-PARTNER-001", "partner investor franchise financing", "shared agreements + finance pack", "agreement/version→capital/obligation→approved distribution/settlement", "separate equity, debt, principal obligations and actual-profit share", "all-location scope bug, guaranteed profit misclassification", "https://docs.oracle.com/en/cloud/saas/netsuite/ns-online-help/section_N550454.html", "legacy partner_calculate defect; live status UNKNOWN", "blocked", "FIN-001 and business-scoped location resolver", "P0", "DEMO-PARTNER-BLOCKED", "D034;R128", "partner_calculate cannot be trusted across all locations", []),
    feature("C10-CAP-HR-001", "workforce attendance payroll", "shared workforce core + jurisdiction policy", "assignment→shift/punch/leave→payroll review/freeze→liability/payment", "payroll liability distinct from payment", "retroactive change, missed punch, OT off, leave carry-forward", "https://docs.frappe.io/hr/payroll-entry", "PR#55 A051; A053/A054 Claude reserved", "isolated-tested-draft", "Claude parity and finance boundary", "P0", "A046 persona refs; signed auth not tested", "D046,D050;R125,R129", "effective-dated policy and correction lineage required", ["A2-OPS-011", "B1-CAP-012"]),
    feature("C10-CAP-REPORT-001", "reporting KPI and planning", "shared read models", "canonical events→versioned metric→authorized drilldown/export", "no write effect; completeness and reconciliation exposed", "internal double count, stale currency, missing cost, unauthorized aggregate", "https://www.sage.com/en-us/sage-business-cloud/intacct/product-capabilities/multi-entity/", "193 legacy definitions preserved; PR#7 A023 uncertified", "partial", "canonical sources and FIN-001", "P1", "DEMO-GOLDEN-CHAIN-001", "D025,D035,D049;REV-009", "reported number must show source and missing classes", ["A2-OPS-008", "B1-CAP-010", "B2-CAP-012"]),
    feature("C10-CAP-INTEGRATION-001", "provider API webhook and cost controls", "platform governance + optional adapters", "connect secret reference→dry-run→enqueue→verify callback→reconcile/revoke", "no domain effect until typed accepted event", "quota, timeout-after-success, duplicate callback, signature failure", "https://docs.ifs.com/techdocs/26r2/040_tailoring/500_business_process_automation/025_considerations/050_ifs_rest_task_considerations/", "PR#27@9da6403 integration ports draft", "draft-only", "merge/reconcile PR#27", "P0", "DEMO-NEG-002", "D049", "external success is not local transaction success", ["A4-OPS-003", "B1-CAP-014", "B1-CAP-018", "B1-CAP-023", "B1-CAP-024", "B2-CAP-011", "B2-CAP-018"]),
    feature("C10-CAP-DRIVE-001", "tenant-consented Google Drive documents", "optional adapter", "owner consent→scoped export job→versioned object→verify/revoke", "document/export only; backup false until restore drill", "quota, ETag conflict, token revoke, ambiguous upload", "https://developers.google.com/drive/api/guides/about-auth", "no product adapter; must extend PR#27", "specified", "INTEGRATION-001", "P1", "DEMO-DRIVE-MOCK-DEFERRED", "D029,D049", "one platform account must not own tenant files", []),
    feature("C10-CAP-OFFLINE-001", "offline bounded intent and deterministic replay", "shared cross-cutting core", "local draft→queue→fresh server reauth/validate→accept/conflict/reject", "no offline stock, money, approval or settlement posting", "revocation, period close, duplicate device, policy drift", "https://www.w3.org/TR/service-workers/", "PR#7 core10-offline-drafts; PR#23 proposal", "draft-only", "GOV-001 and typed commands", "P0", "DEMO-NEG-002;DEMO-NEG-003;DEMO-NEG-007", "D041,D049", "cached authority cannot post consequential effects", ["A2-OPS-009", "A4-OPS-001", "A4-OPS-002", "B2-CAP-013", "B2-CAP-015"]),
    feature("C10-CAP-UX-001", "task-led bilingual accessible UX", "shared UX projection", "role/context→task journey→effect preview→result/recovery", "presentation never authorizes or calculates canonical effects", "cross-tenant search leak, hidden vs denied confusion, inaccessible table", "https://www.w3.org/TR/WCAG22/", "PR#60 synthetic preview current head not all green", "partial-preview", "server-filtered projections and typed high-risk components", "P0", "390px/1440px current-head failures unresolved", "D045,D049;R123,R128", "capability-rich backend needs context-simple frontend", ["A4-GLO-003", "A4-GLO-004", "A4-UX-001"]),
    feature("C10-CAP-DR-001", "backup restore and disaster recovery", "platform governance", "encrypted manifest→separate failure domain→isolated restore→reconcile→gated cutover", "no domain effect until approved restore", "missing auth/storage, lost key, same-account backup, stale schema", "https://csrc.nist.gov/pubs/sp/800/34/r1/upd1/final", "PR#7 disposable dump/restore only", "isolated-tested-partial", "external encrypted storage and restore drill", "P0", "DEMO-RESTORE-NOT-VERIFIED", "D041,D043", "copy/upload is not verified backup", ["A4-DR-001"]),
    feature("C10-CAP-AGRI-001", "agriculture provenance", "industry pack + regulated adapters", "field/season/activity→harvest lot→grade/aggregate→settlement", "lot/yield/cost and provenance reports", "weather loss, mixed lot, offline grower, scheme claim", "https://www.fao.org/smart-farming", "not built", "research-only-region-validation", "INV-002 and agreements", "P2", "DEMO-AGRI-NOT-BUILT", "D031", "software fields do not certify sustainability", ["A1-CAP-013", "A3-V016"]),
    feature("C10-CAP-NGO-001", "nonprofit grant and restricted funds", "industry pack + reporting adapter", "award/restriction→budget/disbursement/expense→outcome/donor report", "restricted fund dimensions; no sales semantics", "in-kind gift, multi-year grant, donor privacy", "https://reference.iatistandard.org/en/about/what-is-iati/", "not built", "research-only-region-validation", "FIN-001 and agreements", "P2", "DEMO-NGO-NOT-BUILT", "D031", "commitment, budget and expenditure are distinct", ["A1-CAP-014", "A3-V022"]),
    feature("C10-CAP-REG-001", "health education energy public sector", "research-only / regulated adapters", "jurisdiction-authorized case/data exchange only", "ERP procurement/workforce/assets boundary; no generic regulated posting", "clinical consent, grid safety, student privacy, statutory appeal", "https://fhir.hl7.org/fhir/overview.html", "not built", "research-only", "professional/legal approval", "P3", "DEMO-REGULATED-NOT-BUILT", "D031,D049", "regulated verticals cannot be enabled from a generic template", ["A3-V017", "A3-V020", "A3-V021", "A3-V023", "B2-CAP-022"]),
    feature("C10-CAP-RULE-001", "certified rule handler and contextual guidance", "platform governance + shared UX", "register descriptor→build/certify typed handler→publish config→explain effect/result", "descriptor alone has no operational effect", "arbitrary code, stale handler, fake availability", "https://www.epicor.com/en-us/products/enterprise-resource-planning-erp/kinetic/tools-and-technology/epicor-functions/", "PR#42 A045 one advisory handler; A052 Claude reserved", "isolated-tested-first-slice", "A044/A045 and Claude parity", "P0", "threshold_rule_v1 only", "D033,D045,D049;R124,R128", "no-code intent cannot mean arbitrary execution", ["B1-CAP-017", "B1-CAP-025", "B2-CAP-020"]),
    feature("C10-CAP-DEMO-001", "deterministic synthetic demo factory", "platform test infrastructure", "seed→fixture/provenance→expected math/negative assertions→reset", "expected math only; never posts", "real-looking data, drift, unbalanced expected journal, false signed-auth claim", "https://docs.github.com/en/actions", "Issue#68 Codex namespace", "coded-isolated-test-pass", "A046 manifest and A048/A049 contracts", "P0", "DEMO-GOLDEN-CHAIN-001;303-site;DEMO-NEG-001..007", "D046,D047,D049;R125,R126,R128", "stable evidence enables nonduplicative module tests", [])
  ];
}

function validate(registryRows) {
  assert(registryRows.length >= 30);
  const ids = new Set();
  for (const row of registryRows) {
    assert.deepEqual(Object.keys(row), FIELDS);
    for (const field of FIELDS) assert.notEqual(String(row[field]).trim(), "", `${row.feature_id}.${field} blank`);
    assert(!ids.has(row.feature_id), `duplicate ${row.feature_id}`); ids.add(row.feature_id);
  }
  const mapped = registryRows.flatMap(row => row.source_candidate_ids.split(";").filter(value => !value.startsWith("NONE-")));
  assert.equal(new Set(mapped).size, mapped.length, "source candidate mapped more than once");
  assert.deepEqual([...new Set(mapped)].sort(), [...allCandidateIds].sort(), "source candidate omission");
  return true;
}

const csvCell = value => `"${String(value).replace(/"/g, '""')}"`;
function buildArtifacts() {
  const features = rows(); validate(features);
  const json = JSON.stringify({
    schema_version: "core10-universal-capability-registry-v1",
    generated_on: "2026-11-11",
    registry_count: features.length,
    source_candidate_count: allCandidateIds.length,
    unexplained_omission_count: 0,
    truth_note: "Registry inclusion is not implementation or release certification.",
    features
  }, null, 2) + "\n";
  const csv = [FIELDS.join(","), ...features.map(row => FIELDS.map(field => csvCell(row[field])).join(","))].join("\n") + "\n";
  return { json, csv, features };
}

if (require.main === module) {
  const artifacts = buildArtifacts();
  if (process.argv.includes("--write")) {
    fs.mkdirSync(path.dirname(OUT_JSON), { recursive: true });
    fs.writeFileSync(OUT_JSON, artifacts.json);
    fs.writeFileSync(OUT_CSV, artifacts.csv);
  }
  console.log(`PASS registry: ${artifacts.features.length} unified features, ${allCandidateIds.length} source candidates, 0 unexplained omissions`);
}
module.exports = { FIELDS, allCandidateIds, rows, validate, buildArtifacts };
