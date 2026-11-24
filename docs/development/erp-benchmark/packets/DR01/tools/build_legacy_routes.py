#!/usr/bin/env python3
"""DR01 batch 2: extract the frozen legacy IA route registry (legacy/islamia-erp/ia.js) read-only and map to capabilities.
Usage: git show <trunk>:legacy/islamia-erp/ia.js | python3 -I build_legacy_routes.py OUT.jsonl"""
import re, sys, json, collections
src = sys.stdin.read()
GROUP_CAP = {"dash": ["C10-CAP-REPORT-001", "C10-CAP-UX-001"], "item": ["C10-CAP-MDM-001"], "stock": ["C10-CAP-INV-001", "C10-CAP-INV-002"], "purch": ["C10-CAP-PROC-001"],
             "factory": ["C10-CAP-MFG-001", "C10-CAP-FOOD-001"], "sale": ["C10-CAP-SALES-001", "C10-CAP-FOOD-001"], "cust": ["C10-CAP-SALES-001"], "acc": ["C10-CAP-FIN-001", "C10-CAP-FIN-002"],
             "appr": ["C10-CAP-GOV-002"], "reports": ["C10-CAP-REPORT-001"], "people": ["C10-CAP-GOV-001", "C10-CAP-HR-001"], "loc": ["C10-CAP-GOV-001", "C10-CAP-SETUP-001"],
             "settings": ["C10-CAP-SETUP-001", "C10-CAP-RULE-001"]}
groups = dict(re.findall(r'\{id:"([a-z0-9_]+)",label:o\("([^"]*)"', src))
SHELL = {"dash": "#/home + #/business (signed read-only portfolio)", "item": "#/master (signed)", "stock": "#/stock (signed receive/issue/transfer/adjust)", "purch": "none yet (PO/GRN RPCs 0203/0206 hosted; guided UI pending)",
         "factory": "#/manufacturing (recorded replay, not signed)", "sale": "#/sales (recorded replay, not signed)", "cust": "#/sales (replay) / CRM A056 not in shell", "acc": "none (finance 0400/0401 not hosted; no UI)",
         "appr": "#/approvals (maturity not verified by DR01)", "reports": "#/business (portfolio only)", "people": "#/staff (maturity not verified by DR01)", "loc": "#/setup (signed)", "settings": "#/control + #/setup + #/features"}
rows = []
for m in re.finditer(r'\bu\("([^"]+)","([a-z0-9_]+)",(\[[^\]]*\]|"[^"]*")', src):
    route, grp, lab = m.group(1), m.group(2), m.group(3)
    nxt = src.find('u("', m.end()); tail = src[m.end(): nxt if nxt > 0 else m.end() + 1500]
    okm = re.search(r'ok:([a-z])(?=[,}])', tail)
    perm = re.findall(r'e\.P\("([A-Z_0-9]+)","([a-z_]+)"\)', tail.split("qa:[")[0])
    gate = [f"{a}:{b}" for a, b in perm] or ([{"a": "ALWAYS_VISIBLE(a)", "n": "OWNER_ONLY(n=e.own)", "c": "LOCATION_OK(c=e.locOk)", "i": "CAN_POS(i=e.canPos)", "l": "ANY_APPROVER(l=e.anyApprove)", "p": "OTHER_TRADE_BIZ(p)", "d": "RULE_FLAG(d)"}.get(okm.group(1), "ok:" + okm.group(1))] if okm else ["DEFAULT_a(ALWAYS)"])
    status = re.search(r'status:"([a-z_]+)"', tail[:300])
    labels = re.findall(r'"([^"]*)"', lab) if lab.startswith("[") else [lab.strip('"')]
    rows.append({"kind": "LEGACY_ROUTE", "id": "LEGACY-ROUTE:" + route, "route": "#/" + route, "group": grp, "group_label_bn": groups.get(grp),
                 "labels": labels, "permission_gates": gate, "status": status.group(1) if status else "live",
                 "capabilities": GROUP_CAP.get(grp, []), "source": "legacy/islamia-erp/ia.js (frozen, read-only)",
                 "preservation_rule": "D051/R130: legacy route stays reachable in frozen app; CORE10 equivalent must map old->new with equal or stronger permission",
                 "core10_equivalent": SHELL.get(grp), "mapping_status": "CAPABILITY_LEVEL_PENDING_ROUTE_LEVEL", "packet": "DR01", "batch": "B2"})
ids = [r["id"] for r in rows]
dup = [k for k, v in collections.Counter(ids).items() if v > 1]
with open(sys.argv[1], "w") as fh:
    for r in rows: fh.write(json.dumps(r, ensure_ascii=False, sort_keys=True) + "\n")
print(len(rows), "routes;", len(set(ids)), "unique; dups", dup[:10]); print(collections.Counter(r["group"] for r in rows)); print(collections.Counter(r["status"] for r in rows))
print(collections.Counter(g.split("(")[0].split(":")[0] if not g[0].isupper() or "(" in g else "P:"+g.split(":")[0] for r in rows for g in r["permission_gates"]).most_common(12))
