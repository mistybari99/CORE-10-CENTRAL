#!/usr/bin/env python3
"""DR01: builds SOURCE_INVENTORY.jsonl and DRAFT_RECOVERY_REGISTER.jsonl.
Usage (from repo root, after `git fetch origin '+refs/pull/*/head:refs/remotes/pr/*'`):
  python3 -I build_inventory.py SRC OUTDIR      (SRC holds pr_inventory.json, trunk_runs.json, po/)
Read-only."""
import json, os, subprocess, sys, collections
SRC, OUT = sys.argv[1], sys.argv[2]
T = "origin/ccr-15ed11dd-n3hw5h"; TRUNK = "9510e19826654e50ae87158aa4dcdfd968a058aa"
HOSTED = {1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,100,101,102,103,104,105,106,110,111,112,113,114,115,116,117,118,150,151,152,153,200,201,202,203,204,205,206,300}
def g(*a): return subprocess.run(["git", *a], capture_output=True, text=True).stdout
inv = []
def add(**k): k.setdefault("packet", "DR01"); k.setdefault("observed", "2026-11-24"); inv.append(k)

# Refs
for ref, role in [(T, "canonical integration trunk (PR#106)"), ("origin/research/erp-benchmark-20261124", "research control centre (PR#157)"), ("origin/main", "main (untouched; Owner GO required)")]:
    add(kind="GIT_REF", ref=ref.replace("origin/", ""), sha=g("rev-parse", ref).strip(), role=role, evidence="git ls-remote/fetch 2026-11-24")
add(kind="STAGING_LEDGER", project="rhrqhbyzrhaafynfhdaf (CORE10 staging only)", query="select count(*),min,max,string_agg(version) from core10.schema_migrations (read-only)",
    result={"rows": 47, "min": 1, "max": 300, "last_applied_utc": "2026-11-24 06:11:25"}, finding="Repo docs (MIGRATION_RESERVATIONS.json, handover) still record 46 rows/max 0206 -> STALE; 0300 now hosted, 0301-0305 not",
    protected_projects_touched=False)
runs = json.load(open(os.path.join(SRC, "trunk_runs.json")))["workflow_runs"]
h = [r for r in runs if r["head_sha"] == TRUNK]
add(kind="CI_AT_TRUNK_HEAD", sha=TRUNK, runs=len(h), conclusions=dict(collections.Counter(r.get("conclusion") for r in h)),
    run_ids=sorted(r["id"] for r in h), workflows=sorted(r["name"] for r in h), note="GitHub Actions list_workflow_runs branch filter; all completed")
# Migrations
for line in g("ls-tree", "-r", T, "internal/migrations").splitlines():
    meta, p = line.split("\t", 1)
    if not p.endswith(".up.sql"): continue
    n = int(os.path.basename(p)[:4]); down = p.replace(".up.sql", ".down.sql")
    add(kind="MIGRATION", path=p, blob=meta.split()[2], number=n, has_rollback=bool(g("ls-tree", T, down).strip()),
        in_staging_ledger=n in HOSTED, maturity="STAGING" if n in HOSTED else "TRUNK")
# Engine / module files not migrated
for d in ["internal/enterprise-sql", "internal/setup001", "internal/universal-control-studio", "internal/gov003", "modules", "apps/central/site"]:
    for line in g("ls-tree", "-r", T, d).splitlines():
        meta, p = line.split("\t", 1)
        add(kind="TRUNK_SOURCE_FILE", path=p, blob=meta.split()[2], numbered_migration=False,
            maturity_note="engine/UI source on trunk; enterprise-sql files load only in disposable test harness (internal/migrations/README.md)")
# Legacy
add(kind="LEGACY_PRESERVATION", manifest="docs/coordination/LEGACY_MOVE_MANIFEST_20261122.json", files=463, blob_match=463,
    method="manifest git_blob vs ls-tree legacy/islamia-erp at trunk", result="463/463 identical")
# Upstream
for repo, ref, sha, lic in [("frappe/erpnext", "v15.126.0 (= version-15 head)", "a6f54f9c88dcc24fdf3c59319f24cd9cd9aa91bd", "GPL-3.0"),
                            ("frappe/frappe", "version-15 head", "fd94443a1c5ffe6f1ef0fc02436d62d9ceaa9917", "MIT"),
                            ("frappe/hrms", "version-15 head = v15.64.9", "46b389047bb12fb9c86c1300c3d7bfd5f897f171", "GPL-3.0")]:
    add(kind="UPSTREAM_PIN", repo=repo, ref=ref, sha=sha, license=lic, verified="git ls-remote + blobless clone tree entries (erpnext 5985 / frappe 4363 / hrms 1848)")
add(kind="UPSTREAM_PIN_CORRECTION", repo="frappe/erpnext", recorded="a6f54f9c88dcc24fdf3c59319f24cd9aa91bd (37 hex chars)", actual="a6f54f9c88dcc24fdf3c59319f24cd9cd9aa91bd",
    finding="Seed STATE/mission commit is truncated ('cd9' missing) - explains 404 on commit-content endpoint. Use the 40-char SHA.")
for repo, tag, sha in [("frappe/erpnext", "v16.60.0", "886ab6ae187244e7f1b852393384ab6019d56264"), ("frappe/frappe", "v16.61.0", "8b19f8c8e334b48e14ecee7231a1a98774c2ebd5"), ("frappe/hrms", "v16.60.0", "34fbb8a7e18c0668ba24b8068170db58587ab80e")]:
    add(kind="UPSTREAM_NEWER_STABLE", repo=repo, tag=tag, sha=sha, note="Newer major line; NOT substituted for v15 baseline (DR08 owns release delta)")
# Drive / Sheets sources
for name, url, status in [
    ("Master Decision Book", "https://docs.google.com/spreadsheets/d/1IYzGBtUVNjah31cPVSFHkzgO7P093jTfZS0CopWrDxs", "READ: 22 sheets incl. DECISION BOOK 57+6 archived, REQUIREMENTS LOCK 131, MODULE BUILD DETAIL 520, CAPABILITY REGISTER 32"),
    ("520-row Code Gap Sheet", "https://docs.google.com/spreadsheets/d/1C8yAMHvbyj8-5DkWUuR2FNB8DwmvdKr35SyJLIzgkho", "READ: 520 rows, 0 duplicate IDs"),
    ("Final Decisions DEC-01..07", "https://docs.google.com/document/d/1o1gOFULxTDMJIiE-jGzy_1ripZ1ciQz79DvmbW9yszs", "READ"),
    ("Code Gap Audit AUD-D01..D12", "https://docs.google.com/document/d/1-wDR0B7_FMNMRworUhLZyAS0DGwAtlRMObF6ybj0aIM", "READ"),
    ("Change Register CHG-001..111", "https://docs.google.com/document/d/1VJHncLoLvBTLaFZ0AtxujEkbYTkuHgUgdRkOlcDU3JI", "READ: 61 CHG IDs (numbering has intentional gaps)"),
    ("Re-alignment plan 2026-11-21", "https://docs.google.com/document/d/1gqWHIDdB81H2-VZqce2E5VbRSZOTOgGraszGt5yeDjc", "READ"),
    ("Coordination Board", "https://docs.google.com/spreadsheets/d/1QyBpRr6rybexMwSA1ivLmn_VidrntbcOTRK4qi1c9Mc", "READ 49 rows; DR01 claim row ERP-BENCH-DR01 appended (row 50)"),
    ("D049 guide", "https://docs.google.com/document/d/1VNB-ub0V49fg1QAPqyALk-1P79eqgbHJZwAdbq5-mCg", "NOT READ in DR01 batch 1 (referenced by AGENTS.md) - next batch"),
    ("RESEARCH ARCHIVE sheet (16 docs, 52 chunks)", "Decision Book sheet RESEARCH ARCHIVE", "CAPTURED, not yet analysed - next batch")]:
    add(kind="PLANNING_SOURCE", name=name, url=url, access=status)
# PaperOps evidence
for p in ["field-review/codex-1000/completion-matrix.jsonl", "field-review/ownership-246-1000.json", "field-review/chatgpt-246/issue-registry.json", "control-obligations.json",
          "control-trace.json", "field-review/functional-gaps-001-003.json", "legacy-field-index.json", "field-review/codex-1000/CURRENT_STATE.md", "field-review/codex-1000/PROGRESS.md"]:
    for pr in (151, 155, 156):
        b = g("rev-parse", f"refs/remotes/pr/{pr}:modules/paperops/{p}").strip()
        add(kind="PAPEROPS_EVIDENCE", pr=pr, head=g("rev-parse", f"refs/remotes/pr/{pr}").strip(), path="modules/paperops/" + p, blob=b or None)
# PRs
prs = json.load(open(os.path.join(SRC, "pr_inventory.json")))
for o in prs:
    add(kind="PULL_REQUEST", **{k: o.get(k) for k in ["pr", "title", "state", "merged_at", "draft", "labels", "head_sha", "base", "head_in_trunk_history", "files_changed",
        "files_add_mod", "path_present_in_trunk", "identical_at_same_path_in_trunk", "identical_after_schema_rename", "mean_similarity_of_differing_present_files", "created", "updated"]})
iss = [json.loads(l) for l in open(os.path.join(SRC, "issues.jsonl"))]
for i in iss: add(kind="ISSUE", number=i["n"], title=i["t"], state=i["s"], labels=i["l"], created=i["c"])
with open(os.path.join(OUT, "SOURCE_INVENTORY.jsonl"), "w") as fh:
    for r in inv: fh.write(json.dumps(r, ensure_ascii=False, sort_keys=True) + "\n")

# Draft recovery register
R = {
 21: ("RECOVERABLE", "PORT", "FIN-001 WAC/COGS, MFG-001 costing, INV-001 valuation", "NP06 (+NP05A)", "Old base, c10_demo, 0 files on trunk. Rewrite as numbered Money/Stock-port migrations; PR is the spec (CHG-052/061)."),
 23: ("RECOVERABLE", "PORT", "OFFLINE-001 conflict quarantine/outbox", "NP11A", "Advantage candidate. Re-implement on canonical inventory_command_requests_v1 replay keys (CHG-092)."),
 27: ("RECOVERABLE", "PORT", "INTEGRATION-001, CHANNEL-001 payment/delivery", "NP11B", "scripts/ path, old base; port behind Control off-by-default (CHG-090)."),
 42: ("FULLY_CONTAINED_MISSING_INTEGRATION", "EXTEND", "RULE-001 micro-engine", "NP02 Control", "Head in trunk history; engine in internal/enterprise-sql/c10_a045 (CI green) but not a numbered migration, not hosted (CHG-024/025)."),
 54: ("DOCUMENTATION_ONLY", "RETAIN_AS_SPEC", "RULE-001 intent / R128", "NP02 Control", "D049/R128 docs; runtime A052 lives in enterprise-sql c10_a052_* (not migrated)."),
 55: ("FULLY_CONTAINED_MISSING_INTEGRATION", "PORT", "HR-001 (76 rows)", "NP07", "Head in trunk history; A051 engine SQL unmigrated; Payroll->Money NOT_CONNECTED (CHG-070/072)."),
 59: ("FULLY_CONTAINED_MISSING_INTEGRATION", "PORT+DEDUP", "ASSET-001", "NP05B", "Head in trunk history; own am_grants must move to Build01 Auth port first (CHG-004)."),
 65: ("DOCUMENTATION_ONLY", "RETAIN_AS_SPEC", "SALES-001 CRM", "NP03B/CRM", "Work order only; A056 engine SQL is on trunk unmigrated (CHG-043)."),
 73: ("PARTIALLY_DUPLICATED", "SELECTIVE_PORT", "INV-002 FEFO, recall, genealogy", "NP03A", "Lot/expiry/inspection already in 0203; FEFO, recursive recall, recall execution not on trunk. Drop own quality_balances (second-ledger risk G4)."),
 77: ("RECOVERABLE_PARKED", "PARK", "SIMULATION-A025 (34 rows R081-R114)", "NP13", "66 files, schema c10_sim, 0 on trunk; parked until after NP06 per AUD-D11/CHG-110. Advantage candidate for DR09."),
 85: ("PARTIALLY_DUPLICATED", "SELECTIVE_PORT", "GOV-003 incident evidence, review", "NP01", "0016/0113 readiness/risk/export on trunk; PR#85 own tenancy must not be ported (CHG-012)."),
 94: ("PARTIALLY_DUPLICATED_MISSING_INTEGRATION", "EXTEND", "SETUP-001 profiles/preflight", "NP01", "3/4 files present on trunk internal/setup001; not wired to build01_setup_v1 (CHG-013)."),
 95: ("RECOVERABLE", "PORT", "PAINT-001 (9 rows)", "NP09", "Paint business is an Owner business; port after Stock+Money ports verified (CHG-081). Advantage candidate."),
 96: ("PARTIALLY_DUPLICATED", "RETAIN_AS_SPEC", "FIN-001 journal", "NP06", "0400/0401 implement journal+reversal; use JS contract as cross-check before closing."),
 97: ("PARTIALLY_DUPLICATED", "SELECTIVE_PORT", "PROC-001 requisition/RFQ/3-way", "NP03A", "PO/GRN/approval in 0203/0206; requisition, RFQ, 3-way match only in kernel spec."),
 103: ("RECOVERABLE", "PORT", "UX-001 bn/en 3-mode language", "Shell/NP11A", "Shell has bn/en labels; 3-mode language governance not ported (CHG-093)."),
 109: ("FULLY_CONTAINED", "NONE", "SALES-001", "NP03B", "Merged; re-integrated with 0305 security fix via #153."),
 117: ("BLOCKED_BY_MIGRATION_ORDER_AND_COMPETING", "CONSOLIDATE", "FIN-001 AR/AP 0402-0403", "NP06", "Competes with #120 on 0402-0405; stacked test PRs #128-#147 must be collapsed into one; needs Sales 030x hosted first."),
 120: ("BLOCKED_BY_MIGRATION_ORDER_AND_COMPETING", "CONSOLIDATE", "FIN-001 AR/AP + Money post 0402-0405", "NP06", "Pick ONE of #117/#120 via Board."),
 121: ("PARTIALLY_DUPLICATED_TOO_BROAD", "SPLIT", "D063, Sales, Mfg, host", "Codex", "0115-0118 already on trunk via #127; remaining pieces port separately; its 0305 collides with trunk 0305."),
 122: ("BLOCKED_BY_MIGRATION_ORDER", "REBASE+RENUMBER", "SALES->Money->AR 0305/0406/0407", "NP06/NP03B", "Trunk now owns 0305 (security fix #153); renumber its 0305; depends on F3."),
 123: ("PARTIALLY_DUPLICATED_OWNED_BY_ACTIVE_AGENT", "DIFF_AND_PORT", "INV-001/PROC-001 0207 supplier returns", "NP03A Claude Builder B", "0201 via #129; leftover 0207+ (supplier returns per Board B-012-REQ2); PaperOps waits on 0207-0210."),
 125: ("SUPERSEDED", "CLOSE_AFTER_CHECK", "INV-001", "NP03A", "Superseded by #129 (PR_STATUS 2026-11-23)."),
 126: ("LIVE_SOURCE_OWNED_BY_ACTIVE_AGENT", "KEEP_UNTIL_APPS_CENTRAL_DEPLOYS", "UX/all live routes", "Trunk integrator", "Live Worker source branch; apps/central on trunk is byte-identical import but deploy path still #126."),
}
for n in [78,79,80,81,82,83,87,88,89,90,91,92,93,98,99]:
    R[n] = ("SUPERSEDED_NEEDS_VERIFICATION", "VERIFY_THEN_CLOSE", "GOV-002", "NP01", "Logic ported as 0009-0015/0018/0019/0110/0111/0114 (paths differ; verify each feature against trunk tests before closing).")
for n in [40, 43, 69, 71]:
    R[n] = ("SUPERSEDED_NEEDS_VERIFICATION", "VERIFY_THEN_CLOSE", "GOV-002 A008", "NP01", "A008 approval logic reportedly ported into 0007-0019 (PR_STATUS).")
for n in [132,148,149,150,151,152,154,155,156]:
    R[n] = ("OWNED_BY_ACTIVE_AGENT", "DO_NOT_TOUCH", "PaperOps 1,246 fields", "PaperOps lanes A/B", "Active lane; release-held; DR01 read-only.")
for n in [128,130,135,136,137,138,139,141,143,144,145,146,147]:
    R[n] = ("OWNED_BY_ACTIVE_AGENT", "COLLAPSE_INTO_117", "FIN-001 F3 tests", "Lane A automation", "Stacked one-test PRs; collapse into #117 once fixed.")
for n in [113, 114, 116, 124, 119]:
    R[n] = ("SUPERSEDED", "CLOSE_AFTER_CHECK", "preview/ops", "Trunk integrator", "Superseded per PR_STATUS 2026-11-23 / handover §7.")
for n in [7, 22, 44, 45, 49, 50, 51, 60, 104, 105]:
    R[n] = ("FULLY_CONTAINED", "CLOSE_WITH_POINTER", "foundation", "Trunk integrator", "Content present on trunk (superseded label / head in trunk history; #49/#50 near-identical after c10_demo->core10 rename).")
reg = []
for o in prs:
    n = o["pr"]
    if o["state"] == "closed" and o["merged_at"] and n not in R:
        cls = ("FULLY_CONTAINED", "NONE", "-", "-", "Merged; head in trunk history" if o["head_in_trunk_history"] else "Merged into a non-trunk base")
    elif o["state"] == "closed" and not o["merged_at"]:
        cls = ("CLOSED_UNMERGED", "INVESTIGATE", "-", "-", "Closed without merge; check for unique content before forgetting")
    elif n in R: cls = R[n]
    elif o["base"] == "main" or n < 40:
        cls = ("OUT_OF_CORE10_SCOPE_LEGACY_OR_DOCS", "CLOSE_PER_OWNER", "legacy IMG / docs", "-", "Pre-trunk legacy hardening/docs (PR_STATUS B close list); IMG protected by D051")
    else: cls = ("NEEDS_REVIEW", "INVESTIGATE", "-", "-", "Not classified in DR01 batch 1")
    reg.append({"pr": n, "title": o["title"], "state": o["state"], "merged": bool(o["merged_at"]), "head_sha": o["head_sha"], "base": o["base"],
                "head_in_trunk_history": o["head_in_trunk_history"], "files_add_mod": o["files_add_mod"], "present_on_trunk": o["path_present_in_trunk"],
                "identical_after_rename": o["identical_after_schema_rename"], "recovery_class": cls[0], "recommendation": cls[1], "affects": cls[2],
                "suggested_lane": cls[3], "rationale": cls[4], "requirement_retained": True, "packet": "DR01"})
with open(os.path.join(OUT, "DRAFT_RECOVERY_REGISTER.jsonl"), "w") as fh:
    for r in reg: fh.write(json.dumps(r, ensure_ascii=False, sort_keys=True) + "\n")
print(collections.Counter(r["kind"] for r in inv)); print(collections.Counter(r["recovery_class"] for r in reg))
