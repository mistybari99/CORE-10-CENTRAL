#!/usr/bin/env python3
"""DR01 generator: builds PRESERVATION_CROSSWALK.jsonl, SOURCE_INVENTORY.jsonl,
DRAFT_RECOVERY_REGISTER.jsonl and reconciliation.json from captured source exports.

Inputs (SRC dir, captured 2026-11-24 by DR01; regenerate the same way to refresh):
  detail520.json        Sheets values API, 520-row Code Gap Sheet 1C8yAMHv...!Untitled!A1:I1000
  decisionbook.json     Master Decision Book 1IYzGBtU... all sheets (formattedValue), {sheet:[rows]}
  po/completion-matrix.jsonl  PR#156 head 348896d2 modules/paperops/field-review/codex-1000/completion-matrix.jsonl
  pr_inventory.json     produced by DR01 PR scan (git refs/pull/*/head vs trunk 9510e198)
  UP dir: blobless clones erpnext@v15.126.0, frappe@version-15 fd94443a, hrms@version-15 46b38904
Usage: python3 -I build_crosswalk.py SRC UP OUTDIR
Read-only: never mutates a source.
"""
import json, os, re, subprocess, sys, collections
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from capmap import CAPS  # noqa: E402

SRC, UP, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
TRUNK = "9510e19826654e50ae87158aa4dcdfd968a058aa"
DB_ID = "1IYzGBtUVNjah31cPVSFHkzgO7P093jTfZS0CopWrDxs"
CG_ID = "1C8yAMHvbyj8-5DkWUuR2FNB8DwmvdKr35SyJLIzgkho"
UPREF = {"erpnext": "v15.126.0@a6f54f9c88dcc24fdf3c59319f24cd9cd9aa91bd", "frappe": "version-15@fd94443a1c5ffe6f1ef0fc02436d62d9ceaa9917", "hrms": "version-15@46b389047bb12fb9c86c1300c3d7bfd5f897f171"}
LIVE_MIG = ("0006_", "0116_", "0117_", "0101_", "0150_", "0151_", "0152_", "0201_", "0204_", "0205_", "shell-context.js")

def uptree(repo):
    out = subprocess.run(["git", "-C", os.path.join(UP, repo), "ls-tree", "-r", "-t", "--name-only", "HEAD"], capture_output=True, text=True).stdout
    return set(out.splitlines())
UPT = {r: uptree(r) for r in ("erpnext", "frappe", "hrms")}

def up_verify(paths):
    res = []
    for p in paths:
        repo, rel = p.split("/", 1)
        ok = rel in UPT.get(repo, set())
        res.append({"repo": repo, "ref": UPREF[repo], "path": rel, "verified_in_pinned_tree": ok,
                    "scope": {"erpnext": "ERPNext core", "frappe": "Frappe Framework", "hrms": "Frappe HRMS (separate GPL app)"}[repo]})
    return res

def classify(code, locs):
    partial = "P" in code; unsure = "?" in code; base = code.replace("P", "").replace("?", "") or "N"
    if base == "H":
        cls = "TRUNK_MIGRATION_IN_STAGING_LEDGER"; mat = "LIVE_STAGING" if any(any(k in l for k in LIVE_MIG) for l in locs) else "STAGING"
    elif base == "U": cls, mat = "TRUNK_MIGRATION_NOT_HOSTED", "TRUNK"
    elif base == "E": cls, mat = "TRUNK_ENGINE_FILE_NOT_MIGRATED", "TRUNK"
    elif base == "R": cls, mat = "OPEN_DRAFT_PR_ONLY", "DRAFT"
    elif base == "L": cls, mat = "FROZEN_LEGACY_REFERENCE_ONLY", "PLAN"
    else: cls, mat = "NO_CODE_FOUND", "PLAN"
    return base, cls, mat, partial, unsure

ADV = {"natural-language-clarification", "unsupported-capability-blueprint", "certification-evidence", "two-device-conflicts",
       "recall-scope-and-recursive-genealogy", "recall-execution-and-evidence", "before-after-impact-preview", "immutable-engine-versions",
       "multi-business-publication", "portfolio-consolidation", "central-control-studio-discovery", "canonical-business-context"}
DEFER_LANES = ("NP13", "NP14")
PORTS = {"GOV": ["Auth", "Approval+Audit"], "SETUP": ["Auth", "Control", "Audit"], "MDM": ["Master", "Control", "Audit"], "REPORT": ["read-only all ports"],
         "INTEGRATION": ["Control", "Audit"], "DRIVE": ["Control", "Audit"], "OFFLINE": ["Auth", "Stock", "Money"], "UX": ["Auth", "Control"], "DR": ["all ledgers"],
         "RULE": ["Control", "Approval+Audit"], "DEMO": ["all (synthetic)"], "SALES": ["Master", "Stock", "Money", "Approval+Audit"], "CHANNEL": ["Master", "Stock", "Money"],
         "FRANCHISE": ["Master", "Stock", "Money"], "PROC": ["Master", "Stock", "Money", "Approval+Audit"], "INV": ["Stock", "Master", "Approval+Audit"],
         "MFG": ["Stock", "Master", "Money"], "FOOD": ["Stock", "Money", "Master"], "PAINT": ["Stock", "Money", "Master"], "PROJ": ["Stock", "Money", "Master"],
         "ASSET": ["Auth", "Money", "Approval+Audit"], "TRADE": ["Stock", "Money"], "FIN": ["Money", "Approval+Audit"], "PARTNER": ["Money", "Auth"],
         "HR": ["Auth", "Money", "Approval+Audit"], "AGRI": ["Stock", "Money"], "NGO": ["Money"], "REG": ["Auth"], "SAAS": ["Auth (platform)"], "SIMULATION": ["read-only snapshots; isolated c10_sim"]}

def split_ids(s, pat):
    return sorted(set(re.findall(pat, s or "")))

db = json.load(open(os.path.join(SRC, "decisionbook.json")))
mbd_h, mbd = db["MODULE BUILD DETAIL"][0], db["MODULE BUILD DETAIL"][1:]
cg = {r[0]: r for r in json.load(open(os.path.join(SRC, "detail520.json")))["values"][1:] if r and r[0]}
ABBR = {"DRAFT_CODED_INTEGRATED_LINE": "D", "PARTIAL_INTEGRATED_LINE": "P", "SIDE_DRAFT_NOT_INTEGRATED": "S", "LEGACY_IMG_ONLY": "L", "MISSING_NO_CODE": "M"}
def col(r, i): return r[i] if len(r) > i else ""

rows, recon = [], collections.Counter()
r_to_detail, d_to_detail = collections.defaultdict(list), collections.defaultdict(list)
cap_codes = collections.defaultdict(collections.Counter)
for idx, r in enumerate(mbd, start=2):
    did, cap = r[0], r[1]
    spec = CAPS[cap]
    pre = cap.replace("C10-CAP-", "").replace("C10-SCOPE-", "")
    suf = did.replace("C10-DETAIL-", "")
    suf = suf[len(pre) + 1:] if suf.startswith(pre + "-") else suf
    o = spec["over"].get(suf)
    code, locs, note = (o[0], o[1], o[2]) if o else spec["default"]
    upx = (o[3] if o and len(o) > 3 else []) + spec["up"]
    base, cls, mat, partial, unsure = classify(code, locs)
    audit = col(cg.get(did, []), 6)
    a = ABBR.get(audit, "?")
    rank = {"M": 0, "L": 1, "S": 2, "P": 3, "D": 4}
    now = {"N": 0, "L": 1, "R": 2, "E": 3, "U": 3, "H": 4}[base]
    delta = "UPGRADED_SINCE_AUDIT" if now > rank.get(a, 0) and not (a == "D" and base == "E") else ("UNCHANGED" if True else "")
    if a in ("D", "P") and base in ("R", "N"): delta = "AUDIT_CODE_NOT_FOUND_ON_TRUNK_NEEDS_VERIFICATION"
    upv = up_verify(upx)
    lane = spec["lane"]
    if unsure: disp = "INVESTIGATE"
    elif suf in ADV: disp = "ADVANTAGE_CANDIDATE"
    elif any(x in lane for x in DEFER_LANES) or "Owner scope" in note or "CHG-063" in note or "CHG-073" in note or cap == "C10-CAP-FRANCHISE-001": disp = "DEFERRED"
    elif base in ("E", "R", "L"): disp = "RECOVER"
    elif base == "N": disp = "ADOPT_CANDIDATE" if upv else "INVESTIGATE"
    elif partial: disp = "ADOPT_CANDIDATE" if upv else "MODERNIZE_CANDIDATE"
    else: disp = "PRESERVE"
    pres = {"H": "IMPLEMENTED_NOT_CERTIFIED", "U": "IMPLEMENTED_NOT_HOSTED_NOT_CERTIFIED", "E": "IMPLEMENTED_UNMIGRATED_NOT_CERTIFIED",
            "R": "DRAFT_ONLY_AT_RISK_IF_PR_CLOSED", "L": "LEGACY_REFERENCE_ONLY_RESPEC_REQUIRED", "N": "REQUIREMENT_PRESERVED_NO_CODE"}[base]
    if partial: pres = "PARTIAL__" + pres
    nxt = {"PRESERVE": "Write ID-tagged preservation test (expected + negative from this row) and certify per detail",
           "RECOVER": "Port/selectively recover into numbered migration via owning lane; keep old PR open until port verified",
           "ADOPT_CANDIDATE": "DR02-DR07 domain packet: compare upstream behaviour, write independent spec, claim lane",
           "MODERNIZE_CANDIDATE": "Baseline-measure then propose improvement (DR08 benchmark protocol)",
           "ADVANTAGE_CANDIDATE": "DR09 counterpart search + maturity proof before any superiority claim",
           "INVESTIGATE": "Re-verify symbol/test at exact trunk head; then reclassify", "DEFERRED": "Keep discoverable; await Owner scope/gate"}[disp]
    for rid in split_ids(col(r, 14), r"R\d{3}"): r_to_detail[rid].append(did)
    for dd in split_ids(col(r, 15), r"D\d{3}"): d_to_detail[dd].append(did)
    cap_codes[cap][code] += 1
    recon[("detail", base, partial)] += 1
    rows.append({
        "kind": "DETAIL", "id": did, "capability": cap, "parent_bench_id": spec["bench"],
        "source": {"doc": f"https://docs.google.com/spreadsheets/d/{DB_ID}", "sheet": "MODULE BUILD DETAIL", "row": idx, "also": f"https://docs.google.com/spreadsheets/d/{CG_ID} (Code Gap Sheet)"},
        "area": col(r, 2), "atomic_feature": col(r, 3), "scope_classification": col(r, 4), "priority": col(r, 5), "build_stage": col(r, 6),
        "original_purpose_workflow": col(r, 7), "expected_outcome": col(r, 8), "negative_and_exception_tests": col(r, 9), "dependencies": col(r, 10),
        "original_remaining_gap": col(r, 12), "owner_requirement_ids": split_ids(col(r, 14), r"R\d{3}"), "master_decision_ids": split_ids(col(r, 15), r"D\d{3}"),
        "research_source_ids": col(r, 16), "business_template_scope": col(r, 25), "future_stream": col(r, 26), "qa_acceptance_gate": col(r, 27),
        "roles_permissions": "Not atomized in source row; DEC-08/D057 controls apply (on/off per business/site, 0-5 approval stages, allow/deny with expiry, typed limits, history/undo)",
        "calculation_precision": "Not atomized in source row unless stated in workflow/outcome; R128 guidance contract requires formula/source/version disclosure",
        "engine_ports_expected": PORTS.get(pre.split("-")[0], []),
        "audit_20261116": {"state": audit, "required_change": col(cg.get(did, []), 8)},
        "current": {"trunk_sha": TRUNK, "evidence_code": code, "evidence_class": cls, "maturity": mat, "partial": partial, "needs_verification": unsure,
                    "locations": locs, "note": note, "delta_vs_audit": delta},
        "preservation_status": pres, "original_purpose_fully_preserved": "NOT_CERTIFIED (0/520 certified per Decision Book col U)",
        "destination": {"lane": lane, "bench_parent": spec["bench"]}, "erpnext_counterparts": upv,
        "disposition": disp, "mapping_confidence": "SYMBOL_LEVEL" if o else "CAPABILITY_LEVEL",
        "acceptance_tests": {"positive": col(r, 8), "negative": col(r, 9), "preservation": f"PRES-{did}: test must name this Detail ID and assert expected_outcome and each negative case"},
        "next_action": nxt, "packet": "DR01", "snapshot": "2026-11-24"})

# Requirements
rl = [x for x in db["REQUIREMENTS LOCK"][4:] if x and x[0]]
rt = {x[0]: x for x in db["REQUIREMENT TRACE"][1:] if x and x[0]}
for x in rl:
    rid = x[0]; dets = r_to_detail.get(rid, [])
    t = rt.get(rid)
    rows.append({"kind": "REQUIREMENT", "id": rid, "source": {"doc": DB_ID, "sheet": "REQUIREMENTS LOCK"}, "area": col(x, 1), "owner_rule": col(x, 2),
                 "master_decisions": col(x, 3), "origin": col(x, 4), "acceptance": col(x, 5),
                 "trace_capability": col(t, 6) if t else None, "trace_gap": None if t else "NOT_IN_REQUIREMENT_TRACE_SHEET",
                 "detail_destinations_count": len(dets), "detail_destinations_sample": dets[:12],
                 "mapping_status": "MAPPED_VIA_DETAIL" if dets else ("MAPPED_VIA_TRACE_ONLY" if t and col(t, 6) else "UNMAPPED"),
                 "preservation_status": "REQUIREMENT_PRESERVED_IN_REGISTER", "packet": "DR01"})
    recon[("req", "mapped" if dets else ("trace" if t and col(t, 6) else "unmapped"))] += 1

# Decisions (+ archived)
for x in db["DECISION BOOK"][4:]:
    if not x or not x[0]: continue
    did = x[0].replace("C10-", "")
    dets = d_to_detail.get(did, [])
    rows.append({"kind": "DECISION", "id": x[0], "source": {"doc": DB_ID, "sheet": "DECISION BOOK"}, "domain": col(x, 1), "decision": col(x, 2)[:600],
                 "status": col(x, 4), "implementation": col(x, 5)[:300], "applies_to": col(x, 7), "next_gate": col(x, 11)[:300],
                 "detail_destinations_count": len(dets), "mapping_status": "MAPPED_VIA_DETAIL" if dets else "POLICY_OR_GOVERNANCE_DECISION_NO_DETAIL_LINK",
                 "packet": "DR01"})
    recon[("decision", "mapped" if dets else "policy")] += 1
for a in ["C10-D016", "C10-D017", "C10-D018", "C10-D019", "C10-D020", "C10-D026"]:
    rows.append({"kind": "DECISION", "id": a, "status": "ARCHIVED_BY_REV-001 (2026-11-09, v1 -> Archived)", "source": {"doc": DB_ID, "sheet": "DECISION REVISIONS", "row_id": "REV-001"},
                 "mapping_status": "ARCHIVED_NOT_LOST", "packet": "DR01"})
    recon[("decision", "archived")] += 1

# Capabilities
creg = {x[0]: x for x in db["CAPABILITY REGISTER"][1:] if x and x[0]}
mdel = {x[1]: x for x in db["MODULE DELIVERY"][1:] if x and len(x) > 1}
for cap, spec in CAPS.items():
    c = creg.get(cap, []); m = mdel.get(cap, [])
    rows.append({"kind": "CAPABILITY", "id": cap, "domain": col(c, 1), "module": col(m, 2), "detail_count": sum(cap_codes[cap].values()),
                 "current_code_mix": dict(cap_codes[cap]), "bench_parent": spec["bench"], "lane": spec["lane"], "module_delivery_status": col(m, 11),
                 "erpnext_counterparts": up_verify(spec["up"]), "source": {"doc": DB_ID, "sheet": "CAPABILITY REGISTER / MODULE DELIVERY"}, "packet": "DR01"})

# Change register (Google Doc 1VJHncLo..., CHG-001..111 with gaps as written)
CHG = [("CHG-001","MERGE","PR#104 then PR#105","S0","DONE: both heads are ancestors of trunk"),("CHG-002","SPEC","canonical schema + migration policy","S0","DONE: internal/migrations/README.md, D056"),
 ("CHG-003","SPEC","5-state code status","S0","DONE: Code Gap Sheet column G"),("CHG-004","DEDUP","A055 am_grants -> Build01","ASSET-001","OPEN: A055 still own grants"),
 ("CHG-005","DEDUP","one canonical audit event","GOV-003","PARTIAL: 0008 canonical; wf_/am_/a056_ audit remain in engine SQL"),("CHG-006","SPEC","shell route contract","UX-001","PARTIAL: apps/central PR#134/#140/#142"),
 ("CHG-007","SPEC","side PR disposition","S0","DONE: S0_SIDE_PR_DISPOSITION.md; superseded label on 12 PRs"),("CHG-010","COMPLETE","GOV-001 partials","GOV-001","OPEN"),
 ("CHG-011","RECONCILE","GOV-002 stack","GOV-002","DONE: 0009-0015,0018,0019,0110,0111,0114 hosted"),("CHG-012","RECONCILE","GOV-003","GOV-003","PARTIAL: 0016/0113 hosted; PR#85 schema not"),
 ("CHG-013","RECONCILE","setup profiles PR#94","SETUP-001","PARTIAL: internal/setup001 on trunk, not wired"),("CHG-014","NEW","locale/jurisdiction + legacy import preview","SETUP-001","OPEN"),
 ("CHG-020","NEW","canonical party","MDM-001","DONE: 0150-0153 hosted"),("CHG-021","NEW","item/service catalog","MDM-001","DONE: 0150-0153 hosted"),
 ("CHG-022","NEW","variant/UOM/barcode/price-list","MDM-001","DONE (price versioning to verify)"),("CHG-023","NEW","category lifecycle, permission, import, impact","MDM-001","PARTIAL"),
 ("CHG-024","COMPLETE","engine certification/delegation/pause","RULE-001","OPEN: A045 not migrated"),("CHG-025","PORT","Rule Studio/Intent/Control","RULE-001","PARTIAL: Control 0100-0106 hosted; A045/A052 not"),
 ("CHG-030","NEW","requisition/RFQ/supplier qual/PO version","PROC-001","PARTIAL: PO+approval 0203/0206"),("CHG-031","COMPLETE","typed PO/GRN","PROC-001","DONE: 0203 hosted"),
 ("CHG-032","NEW","3-way match/payment schedule","PROC-001","OPEN"),("CHG-033","COMPLETE","stock movement source/cost/lot","INV-001","PARTIAL: lots 0203; cost PR#21 not"),
 ("CHG-034","NEW","reservation/in-transit/bin/reorder/consignment","INV-001","OPEN"),("CHG-035","RECONCILE","PR#73 lot/QC/recall on A048 ledger","INV-002","PARTIAL: lot/expiry/inspect 0203; FEFO/recall not"),
 ("CHG-036","NEW","serial/certificate/blind count","INV-002","OPEN (A038 engine only)"),("CHG-040","NEW","SO->ATP->partial fulfil","SALES-001","PARTIAL: 0300-0305; no ATP"),
 ("CHG-041","NEW","counter/cashier/invoice/collection/refund","SALES-001","PARTIAL: 0304 draft invoice; collection PR#122"),("CHG-042","COMPLETE","replace CRM test order adapter","SALES-001","OPEN"),
 ("CHG-043","PORT","CRM lifecycle","SALES-001","OPEN: A056 engine SQL"),("CHG-050","NEW","CoA + source-linked journal + reversal","FIN-001","DONE on trunk, NOT hosted (0400/0401)"),
 ("CHG-051","NEW","AP/AR/aging/bank/cash","FIN-001","OPEN: PR#117/#120/#122 competing drafts"),("CHG-052","RECONCILE","WAC + COGS (PR#21)","FIN-001","OPEN"),
 ("CHG-053","NEW","accrual/budget/close/statement","FIN-001","PARTIAL: periods 0400"),("CHG-054","COMPLETE","tax/FX/intercompany","FIN-002","OPEN"),
 ("CHG-055","COMPLETE","partner ownership/loss/advance/exit","PARTNER-001","OPEN"),("CHG-060","NEW","MRP/routing/capacity/WIP/scrap/subcontract","MFG-001","PARTIAL: 0500-0504"),
 ("CHG-061","RECONCILE","production costing PR#21","MFG-001","OPEN"),("CHG-062","PORT","assets","ASSET-001","OPEN"),("CHG-063","NEW","rental/folio/lease","ASSET-001","OPEN (Owner scope)"),
 ("CHG-070","PORT","workforce/payroll","HR-001","OPEN"),("CHG-071","COMPLETE","HR stale/release/guidance/scale","HR-001","OPEN"),("CHG-072","NEW","offline attendance; payroll->GL","HR-001","OPEN"),
 ("CHG-073","SPEC","4 HR extensions","HR-001","OPEN (Owner scope)"),("CHG-074","NEW","metric registry/drilldown/statements/snapshot/forecast","REPORT-001","PARTIAL: 0204 portfolio read"),
 ("CHG-080","NEW","restaurant adapter","FOOD-001","OPEN"),("CHG-081","RECONCILE","paint PR#95","PAINT-001","OPEN"),("CHG-082","NEW","trade adapter","TRADE-001","OPEN"),
 ("CHG-083","NEW","project adapter","PROJ-001","OPEN"),("CHG-084","NEW","channel adapters","CHANNEL-001","OPEN"),("CHG-085","NEW","franchise","FRANCHISE-001","OPEN (Owner scope P2)"),
 ("CHG-086","COMPLETE","catalog readiness from evidence","SETUP-001","INVESTIGATE"),("CHG-090","RECONCILE","integration ports PR#27","INTEGRATION-001","OPEN"),
 ("CHG-091","NEW","Drive port","DRIVE-001","OPEN"),("CHG-092","RECONCILE","offline outbox PR#23","OFFLINE-001","OPEN"),("CHG-093","RECONCILE","3-mode language PR#103","UX-001","PARTIAL: shell bn/en labels"),
 ("CHG-094","NEW","keyboard/screen reader/search","UX-001","PARTIAL"),("CHG-095","NEW","backup/DR runbook","DR-001","OPEN"),
 ("CHG-100","SPEC","NP10 Detail rows","NP10","OPEN: no NP10 rows in the 520 register (verify elsewhere)"),("CHG-101","NEW","IMG launch facade","NP10","BLOCKED: D051 separate GO"),
 ("CHG-110","SPEC","simulation parked; Agri/NGO/Reg scope","NP13","DONE (parked)"),("CHG-111","NEW","SaaS licensing","NP14","DEFERRED")]
for cid, typ, what, cap, state in CHG:
    rows.append({"kind": "CHANGE", "id": cid, "type": typ, "change": what, "target": cap, "current_state_dr01": state,
                 "source": {"doc": "https://docs.google.com/document/d/1VJHncLoLvBTLaFZ0AtxujEkbYTkuHgUgdRkOlcDU3JI"}, "packet": "DR01"})

# Actions
for x in db["NEXT ACTIONS"][4:]:
    if x and x[0]:
        rows.append({"kind": "ACTION", "id": x[0], "workstream": col(x, 1), "deliverable": col(x, 2)[:300], "priority": col(x, 3), "sheet_status": col(x, 4),
                     "decision_id": col(x, 10), "dr01_note": "Status as recorded in NEXT ACTIONS; not re-verified per action by DR01", "source": {"doc": DB_ID, "sheet": "NEXT ACTIONS"}, "packet": "DR01"})

# PaperOps 1,246
FORM = {"C-01": ("C10-CAP-FIN-001", "cash-drawer-and-petty-cash"), "C-02": ("C10-CAP-FIN-001", "cash-drawer-and-petty-cash"), "C-03": ("C10-CAP-CHANNEL-001", "audience-segmentation-and-campaign-drafts"),
        "C-04": ("C10-CAP-FIN-001", "bank-reconciliation-and-unknown-outcomes"), "C-05": ("C10-CAP-FIN-001", "ar-invoicing-aging-and-credit-control"), "C-06": ("C10-CAP-FIN-001", "cash-drawer-and-petty-cash"),
        "R-01": ("C10-CAP-SALES-001", "retail-counter-and-cashier-session"), "R-02": ("C10-CAP-MFG-001", "finished-goods-co-products-and-yield"), "S-01": ("C10-CAP-SALES-001", "order-creation-and-conversion"),
        "S-02": ("C10-CAP-SALES-001", "discount-approval"), "S-03": ("C10-CAP-SALES-001", "sales-return-authorization-and-disposition"), "S-04": ("C10-CAP-CHANNEL-001", "marketplace-orders-and-seller-identity"),
        "S-05": ("C10-CAP-SALES-001", "quotation-versions-and-price-trace"), "S-06": ("C10-CAP-SALES-001", "customer-and-b2b-account-identity"), "P-01": ("C10-CAP-PROC-001", "purchase-requisitions-and-demand-source"),
        "P-02": ("C10-CAP-PROC-001", "rfq-and-supplier-comparison"), "P-03": ("C10-CAP-PROC-001", "rfq-and-supplier-comparison"), "P-04": ("C10-CAP-PROC-001", "partial-receiving-and-overdelivery-tolerance"),
        "P-05": ("C10-CAP-PROC-001", "supplier-invoice-and-document-matching"), "P-06": ("C10-CAP-PROC-001", "supplier-qualification-and-restrictions"), "W-01": ("C10-CAP-MFG-001", "material-issue-substitution-and-return"),
        "W-02": ("C10-CAP-INV-001", "transfer-dispatch-and-in-transit"), "W-03": ("C10-CAP-INV-002", "physical-count-sessions-and-blind-entry"), "W-04": ("C10-CAP-INV-001", "stock-history-drilldown-and-reversal"),
        "M-01": ("C10-CAP-ASSET-001", "breakdown-downtime-and-maintenance-cost"), "A-01": ("C10-CAP-REPORT-001", "operational-exception-reports"), "A-02": ("C10-CAP-FIN-001", "financial-statements-and-source-drilldown"),
        "F-01": ("C10-CAP-MFG-001", "bom-and-recipe-versions"), "F-02": ("C10-CAP-INV-002", "quality-sample-and-inspection-record"), "F-03": ("C10-CAP-MFG-001", "bom-and-recipe-versions"),
        "F-04": ("C10-CAP-MFG-001", "finished-goods-co-products-and-yield"), "F-05": ("C10-CAP-MFG-001", "work-order-release-and-approval")}
po_n = collections.Counter()
for l in open(os.path.join(SRC, "po", "completion-matrix.jsonl")):
    p = json.loads(l); f = p["source_id"].split(":")[0]; cap, suf = FORM[f]
    po_n[(p["lane"], p["build_status"], p["source_rule_status"])] += 1
    rows.append({"kind": "PAPEROPS_FIELD", "id": p["source_id"], "lane": p["lane"], "owner_lane": "Codex Lane A (1000)" if p["lane"] == "A" else "ChatGPT Lane B (246)",
                 "batch": p.get("batch"), "legacy_source": p["source"], "source_declaration": p["source_status"], "source_rule_status": p["source_rule_status"],
                 "build_status": p["build_status"], "blocker": p["blocker"], "final_acceptance": p["final_acceptance"], "proposed_destination_by_lane": p.get("proposed_destination"),
                 "dr01_crosslink_detail": f"C10-DETAIL-{cap.replace('C10-CAP-','')}-{suf}", "dr01_crosslink_basis": "FORM_LEVEL_INFERENCE (form prefix + field keys); lane owners may refine",
                 "evidence": {"pr": 156, "head": "348896d2d3f231a381cef38ad3dd1fc3c62a29aa", "path": "modules/paperops/field-review/codex-1000/completion-matrix.jsonl"},
                 "disposition": "PRESERVE", "dr01_note": "Declaration verified != form-engine completion; owned by active PaperOps lanes, DR01 does not modify", "packet": "DR01"})

os.makedirs(OUT, exist_ok=True)
valid_dets = {r["id"] for r in rows if r["kind"] == "DETAIL"}
bad_links = [r["id"] for r in rows if r["kind"] == "PAPEROPS_FIELD" and r["dr01_crosslink_detail"] not in valid_dets]
with open(os.path.join(OUT, "PRESERVATION_CROSSWALK.jsonl"), "w") as fh:
    for r in rows: fh.write(json.dumps(r, ensure_ascii=False, sort_keys=True) + "\n")

kinds = collections.Counter(r["kind"] for r in rows)
ids = [r["id"] for r in rows]
dups = [k for k, v in collections.Counter((r["kind"], r["id"]) for r in rows).items() if v > 1]
det = [r for r in rows if r["kind"] == "DETAIL"]
summary = {
  "snapshot": "2026-11-24", "trunk": TRUNK, "kinds": kinds, "duplicate_kind_id_pairs": dups, "paperops_bad_crosslinks": bad_links,
  "detail": {"total": len(det), "unique": len({r['id'] for r in det}),
             "by_evidence_class": collections.Counter(r["current"]["evidence_class"] for r in det),
             "by_maturity": collections.Counter(r["current"]["maturity"] for r in det),
             "partial": sum(r["current"]["partial"] for r in det), "needs_verification": sum(r["current"]["needs_verification"] for r in det),
             "by_disposition": collections.Counter(r["disposition"] for r in det), "by_delta": collections.Counter(r["current"]["delta_vs_audit"] for r in det),
             "by_mapping_confidence": collections.Counter(r["mapping_confidence"] for r in det),
             "audit_20261116": collections.Counter(r["audit_20261116"]["state"] for r in det),
             "certified": 0, "with_verified_upstream_counterpart": sum(1 for r in det if any(u["verified_in_pinned_tree"] for u in r["erpnext_counterparts"])),
             "upstream_paths_unverified": sorted({u["repo"] + "/" + u["path"] for r in det for u in r["erpnext_counterparts"] if not u["verified_in_pinned_tree"]})},
  "requirements": {"total": kinds["REQUIREMENT"], "mapped_via_detail": recon[("req", "mapped")], "trace_only": recon[("req", "trace")], "unmapped": recon[("req", "unmapped")],
                   "unmapped_ids": [r["id"] for r in rows if r["kind"] == "REQUIREMENT" and r["mapping_status"] == "UNMAPPED"],
                   "trace_gaps": [r["id"] for r in rows if r["kind"] == "REQUIREMENT" and r.get("trace_gap")]},
  "decisions": {"present": recon[("decision", "mapped")] + recon[("decision", "policy")], "mapped_via_detail": recon[("decision", "mapped")],
                "policy_no_detail_link": recon[("decision", "policy")], "archived": recon[("decision", "archived")]},
  "paperops": {"total": kinds["PAPEROPS_FIELD"], "by_lane_build_rule": {f"{k[0]}|{k[1]}|{k[2]}": v for k, v in po_n.items()}},
}
json.dump(summary, open(os.path.join(OUT, "reconciliation.json"), "w"), indent=1, ensure_ascii=False, default=dict)
print(json.dumps(summary, indent=1, ensure_ascii=False, default=dict)[:6000])
