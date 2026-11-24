#!/usr/bin/env python3
"""DR01: REGISTRY_PROPOSED_DELTA.jsonl from PRESERVATION_CROSSWALK.jsonl + shared REGISTRY.json (read-only).
Usage: python3 -I build_delta.py PACKET_DIR REGISTRY_JSON"""
import json, sys, collections
P, REG = sys.argv[1], sys.argv[2]
reg = {e["id"]: e for e in json.load(open(REG))["entries"]}
det = [json.loads(l) for l in open(P + "/PRESERVATION_CROSSWALK.jsonl")]
det = [r for r in det if r["kind"] == "DETAIL"]
by = collections.defaultdict(list)
SECOND = {"BENCH-004": ["INV-001-valuation-and-source-cost-linkage", "FIN-001-weighted-average-cost-and-inventory-valuation", "FIN-001-cogs-sales-return-and-margin-trace", "PROC-001-landed-and-additional-purchase-costs", "TRADE-001-landed-cost-allocation"],
 "BENCH-008": ["FIN-001-ar-invoicing-aging-and-credit-control", "FIN-001-ap-invoices-matching-and-aging", "FIN-001-verified-settlement-and-reversal", "SALES-001-customer-collection-and-allocation", "PROC-001-supplier-payment-allocation-and-reversals"],
 "BENCH-012": ["INV-002-quality-sample-and-inspection-record", "INV-002-stock-quarantine-and-release", "PROC-001-receiving-quality-and-quarantine", "PAINT-001-color-matching-and-qc-evidence"],
 "BENCH-021": ["RULE-001-natural-language-clarification", "RULE-001-unsupported-capability-blueprint", "RULE-001-contextual-guidance-and-report-destinations", "UX-001-contextual-action-guidance", "UX-001-formula-and-result-explanation"],
 "BENCH-001": ["SETUP-001-unified-quick-advanced-engine", "UX-001-mobile-and-desktop-forms"]}
for r in det:
    by[r["parent_bench_id"]].append(r)
    for b, sufs in SECOND.items():
        if r["id"].replace("C10-DETAIL-", "") in sufs and r not in by[b]: by[b].append(r)
out = []
for bid, e in reg.items():
    rows = by.get(bid, [])
    mat = collections.Counter(r["current"]["maturity"] for r in rows)
    out.append({"op": "UPDATE_EVIDENCE", "bench_id": bid, "field_changes": {
        "original_ids": sorted(r["id"] for r in rows),
        "original_mapping": "DR01_MAPPED_CAPABILITY_OR_SYMBOL_LEVEL" if rows else e.get("original_mapping"),
        "research_status": "SOURCE_VERIFIED" if rows else e.get("research_status"),
        "dr01_maturity_mix": dict(mat), "dr01_disposition_mix": dict(collections.Counter(r["disposition"] for r in rows))},
        "previous": {"original_mapping": e.get("original_mapping"), "research_status": e.get("research_status"), "maturity": e.get("maturity")},
        "evidence": "packets/DR01/PRESERVATION_CROSSWALK.jsonl (parent_bench_id=%s or DR01 secondary map)" % bid,
        "paperops_ids_ref": "all 1,246 PAPEROPS_FIELD rows in PRESERVATION_CROSSWALK.jsonl" if bid in ("BENCH-001", "BENCH-023") else None,
        "dr01_scope_note": "DR08 domain (upstream bug mining); no original Detail maps here by design" if bid == "BENCH-026" else None, "requires_coordinator_merge": True, "packet": "DR01"})
NEW = [
 ("DR01-CAND-001", "BENCH-028", "Platform", "Quantity/money precision and rounding policy (MOD-01)", "MODERNIZE_CANDIDATE", "P0", "SOURCE_VERIFIED inconsistency: stock numeric(15,3) vs sales/mfg round 6; money 2 vs 4 dp", "WO-02"),
 ("DR01-CAND-002", "BENCH-003", "Stock", "Reservation under balance-row lock (atomic child of BENCH-003)", "ADOPT_CANDIDATE", "P0", "ERPNext SRE L429-L470 read-based allowed qty; CORE10 0200 L105 FOR UPDATE", "WO-03"),
 ("DR01-CAND-003", "BENCH-008", "Finance", "Single AR/AP open-item stack (#117 vs #120) with delink-on-reversal", "MODERNIZE_CANDIDATE", "P0", "#117/#120 identical 0402 tables; #120 superset", "WO-04"),
 ("DR01-CAND-004", "BENCH-028", "Process", "Port 155 engine-file Details to numbered migrations after Auth/Audit dedup", "RECOVER", "P1", "internal/enterprise-sql only; 53/53 CI green", "WO-06"),
 ("DR01-CAND-005", "BENCH-012", "Quality", "QC parameter templates via certified threshold handler", "MODERNIZE_CANDIDATE", "P1", "QI L316-L352 vs 0203 accept/reject only", "WO-07"),
 ("DR01-CAND-006", "BENCH-005", "Stock", "Recursive recall port onto canonical ledger (PR #73)", "RECOVER", "P1", "PR#73 quality_genealogy_v1 + second ledger", "WO-08"),
 ("DR01-CAND-007", "BENCH-004", "Stock/Finance", "Backdated posting and revaluation policy before PR #21", "INVESTIGATE", "P1", "ERPNext repost_future_sle L314 / update_entries_after L686", "WO-09"),
 ("DR01-CAND-008", "BENCH-009", "Finance", "Per-domain period closure + closing entries + audited reopen", "ADOPT_CANDIDATE", "P1", "general_ledger.py L146/L433 vs 0400 finance_periods_v1", "WO-10"),
 ("DR01-CAND-009", "BENCH-028", "Process", "PRES-<DetailID> test convention + certified-detail counter CI", "ORGANIZE", "P1", "0/520 certified per Decision Book col U", "WO-11"),
 ("DR01-CAND-010", "BENCH-026", "Process", "Stale coordination records (staging ledger 47/max0300; ERPNext SHA typo)", "ORGANIZE", "P0", "read-only SELECT 2026-11-24; git ls-remote", "WO-01"),
 ("DR01-CAND-011", "BENCH-028", "Platform", "Optimistic-concurrency inventory of editable RPCs", "INVESTIGATE", "P2", "Frappe document.py L717-L731 modified check", "WO-13"),
 ("DR01-CAND-012", "BENCH-001", "Forms", "mandatory_depends_on class gap in PaperOps (W02-02) -> DR02", "MODERNIZE_CANDIDATE", "P1", "issue-registry W02-02; frappe docfield.json", "DR02"),
]
for cid, parent, dom, cap, disp, pri, ev, wo in NEW:
    out.append({"op": "PROPOSE_NEW_ID", "candidate_id": cid, "proposed_parent": parent, "domain": dom, "capability": cap, "disposition": disp, "priority": pri,
                "maturity": "PLAN", "research_status": "SOURCE_VERIFIED", "evidence": ev, "action": wo + " in packets/DR01/BUILD_RECOMMENDATIONS.md",
                "note": "Candidate ID only; coordinator assigns the final append-only BENCH ID", "packet": "DR01"})
with open(P + "/REGISTRY_PROPOSED_DELTA.jsonl", "w") as fh:
    for r in out: fh.write(json.dumps(r, ensure_ascii=False, sort_keys=True) + "\n")
print(len(out), collections.Counter(r["op"] for r in out), "unmapped BENCH:", [r["bench_id"] for r in out if r["op"] == "UPDATE_EVIDENCE" and not r["field_changes"]["original_ids"]])
