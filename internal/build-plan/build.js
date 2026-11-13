"use strict";
// Planning and preservation only: never executes a business command or provider call.
const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");
const assert = require("node:assert/strict");
const ROOT = path.resolve(__dirname, "../..");
const BOOK = "https://docs.google.com/spreadsheets/d/1IYzGBtUVNjah31cPVSFHkzgO7P093jTfZS0CopWrDxs/edit";
const read = p => fs.readFileSync(path.join(ROOT, p), "utf8");
const hash = text => crypto.createHash("sha256").update(text).digest("hex");
const cap = suffix => "C10-CAP-" + suffix;
const SHARED = ["R014", "R015", "R073", "R074", "R115", "R116", "R117", "R128"];
const SIM = "C10-SCOPE-SIMULATION-A025";
const SAAS = "C10-SCOPE-SAAS-A024";
const ordered = ["GOV-001","GOV-002","GOV-003","SETUP-001","MDM-001","INV-001","INV-002","PROC-001","MFG-001","SALES-001","FIN-001","FIN-002","PARTNER-001","RULE-001","HR-001","ASSET-001","REPORT-001","FOOD-001","PAINT-001","PROJ-001","TRADE-001","CHANNEL-001","FRANCHISE-001","INTEGRATION-001","DRIVE-001","OFFLINE-001","UX-001","DR-001","DEMO-001","AGRI-001","NGO-001","REG-001"].map(cap);
function requirementTargets(id) {
  const n = Number(id.slice(1, 4));
  if (n >= 81 && n <= 114) return [SIM];
  if (n === 67 || n === 68) return [SAAS];
  if ([9,12,14,15,23,24,35,37,38,41,42,44,45,51,70,71,72,73,74,75,76,78,80].includes(n)) return [...ordered];
  if (n <= 12) return [cap("GOV-001"),cap("SETUP-001"),cap("MDM-001"),cap("UX-001")];
  if (n <= 26) return [cap("GOV-001"),cap("GOV-002"),cap("RULE-001"),cap("UX-001")];
  if (n <= 40) return [cap("SETUP-001"),cap("MDM-001"),cap("RULE-001")];
  if (n <= 45) return [cap("INV-001"),cap("DEMO-001"),cap("DR-001")];
  if (n <= 51) return [cap("REPORT-001"),cap("FIN-001")];
  if (n <= 61) return [cap("PARTNER-001"),cap("FIN-001"),cap("GOV-001")];
  if (n <= 70) return [cap("GOV-001"),cap("GOV-002")];
  if (n <= 76) return [cap("GOV-003"),cap("RULE-001"),cap("DEMO-001")];
  if (n === 77) return [cap("GOV-001"),cap("SETUP-001")];
  if (n === 78) return [cap("MDM-001"),cap("DEMO-001"),cap("UX-001")];
  if (n === 79) return [cap("RULE-001"),cap("SETUP-001")];
  if (n === 80) return ["FOOD-001","PAINT-001","PROJ-001","MFG-001","TRADE-001","CHANNEL-001","ASSET-001"].map(cap);
  if ([123,124].includes(n)) return [cap("RULE-001"),cap("GOV-002"),cap("UX-001")];
  if (n === 125) return [cap("DEMO-001"),cap("GOV-001")];
  if (n === 127) return ["INV-001","SALES-001","MFG-001","REPORT-001","RULE-001"].map(cap);
  if (n === 129) return [cap("HR-001")];
  return [...ordered]; // Explicit universal implementation/release duties, not silent omission.
}
function stage(id) {
  if (/GOV|SETUP|MDM/.test(id)) return "B1 canonical foundation";
  if (/INV|PROC|MFG|SALES|FIN|PARTNER/.test(id)) return "B2 connected operations and finance";
  if (/FOOD|PAINT|PROJ|TRADE|CHANNEL|FRANCHISE/.test(id)) return "B3 domain packs after shared invariants";
  if (/HR|ASSET/.test(id)) return "B4 workforce/assets integration";
  if (/INTEGRATION|DRIVE|OFFLINE/.test(id)) return "B5 governed integrations/offline";
  if (/AGRI|NGO|REG/.test(id)) return "B7 expansion / jurisdiction review";
  return "Cross-cutting throughout B0-B6";
}
function currentEvidence(id, original) {
  if (/HR-001/.test(id)) return "PR74 preview integration: A051/A053/A054 combined PG17 SQL + concurrency passed; individual detailed feature completeness still requires evidence.";
  if (/ASSET-001/.test(id)) return "PR74: A055 fixed-assets/maintenance combined SQL + concurrency + signed-HMAC HTTP/browser passed; rental/hospitality extensions not thereby implemented.";
  if (/RULE-001/.test(id)) return "PR74: A045/A052 combined SQL/browser passed; supported advisory handlers only; arbitrary handlers not implemented.";
  if (/UX-001/.test(id)) return "PR74 deployed preview mobile/desktop passed; original CRM demo runnable, original operations/inventory read-only snapshot; no operational certification.";
  if (/SALES-001/.test(id)) return "PR74: A049 combined purchase/stock/sale and A056 CRM SQL/browser passed; production/finance and every detailed item not thereby complete.";
  return "Historical registry baseline: " + original.current_technical_state + "; " + original.existing_repo_file_pr_sha + ". Re-verify per item; this is not a completion certificate.";
}
function build() {
  const registry = JSON.parse(read("docs/strategy/UNIVERSAL_CAPABILITY_REGISTER.json"));
  const requirements = JSON.parse(read("docs/strategy/research-inputs/owner-requirements-snapshot.json"));
  const revisions = JSON.parse(read("docs/strategy/research-inputs/decision-revisions-snapshot.json"));
  const byId = new Map(registry.features.map(x => [x.feature_id,x]));
  const requirementTrace = requirements.rows.flatMap((r,index) => /^R\d{3}(?:$|-IMPL-NOTE-)/.test(r[0] || "") ? [{
    requirement_id:r[0],area:r[1],text:r[2],decisions:r[3],authority:r[4],acceptance:r[5],
    capability_ids:requirementTargets(r[0]),source_url:BOOK+"#gid=4106&range=A"+(index+1)+":F"+(index+1),
    record_type:/^R\d{3}$/.test(r[0])?"OWNER_REQUIREMENT":"HISTORICAL_IMPLEMENTATION_NOTE",
    sequencing:/^R0(?:8[1-9]|9\d)$|^R10\d$|^R11[0-4]$/.test(r[0])?"REV-010: Claude Code isolated draft only; integration/release gated":(["R067","R068"].includes(r[0])?"A024 deferred commercialization":"Existing scope; feature-level verification required")
  }]:[]);
  const rawDetails = ["platform","business","hr"].flatMap(name => JSON.parse(read("internal/build-plan/"+name+"-detail.json")));
  const detailRows = rawDetails.map(row => {
    const parent = byId.get(row.capability_id);
    assert(parent,"Unknown capability " + row.capability_id);
    const linked = requirementTrace.filter(r => r.record_type==="OWNER_REQUIREMENT" && r.capability_ids.includes(row.capability_id)).map(r=>r.requirement_id);
    return {
      ...row,detail_id:row.feature_detail_id || "C10-DETAIL-"+row.capability_id.slice(8)+"-"+row.title.toLowerCase().replace(/[^a-z0-9]+/g,"-").replace(/^-|-$/g,""),
      stage:stage(row.capability_id),priority:parent.priority,
      source_candidate_ids:parent.source_candidate_ids,
      owner_requirement_ids:[...new Set([...SHARED,...linked])],owner_decisions:parent.owner_decision_link,
      ui_api_storage_report_contract:"Scoped UI → signed API → canonical durable record/event → audit → source-linked report; prove each layer for this feature.",
      guidance_contract:"R128: explain this action's what/when/why, recommendation, consequences, approval, safe example, formula/source/version where calculated, and result destination in BN/EN.",
      implementation_evidence_status:"NOT_CERTIFIED_PER_DETAIL",
      verification_contract:"Positive + tenant/business/site/role negatives + stale/replay + concurrency where relevant + exact calculation/report reconciliation +390/1440+safe recovery. Certified staging and production are separate."
    };
  });
  const deferredDetails = requirementTrace.filter(r=>r.record_type==="OWNER_REQUIREMENT" && r.capability_ids.some(x=>[SIM,SAAS].includes(x))).map(r=>({
    detail_id:"C10-DETAIL-"+r.requirement_id,capability_id:r.capability_ids[0],area:r.area,title:r.text,workflow:r.text,
    acceptance:r.acceptance,negative_cases:"Cross-tenant leakage, arbitrary execution, fake certainty or unauthorized operational activation must fail.",
    dependencies:r.capability_ids[0]===SIM?"REV-010; Claude Code isolated branch;2-3 verified major packages/P0 before integration":"A024; ERP/tenant isolation completion before commercialization",
    existing_evidence:"Authoritative owner requirement, not implementation proof",gap:"Separate owned implementation and certification required",
    status:"PLANNED_DETAIL_NOT_CERTIFIED",source_paths:[r.source_url],scope_class:"release-gated",stage:"Separate gated scope",priority:"See authoritative requirement",
    source_candidate_ids:"OWNER-REQUIREMENT-DIRECT",owner_requirement_ids:[r.requirement_id],owner_decisions:r.decisions,
    ui_api_storage_report_contract:"One existing ERP and canonical identities; isolated planning cannot post operational data.",
    guidance_contract:"R128 explanatory guidance and reproducible assumptions apply.",implementation_evidence_status:"NOT_CERTIFIED_PER_DETAIL",
    verification_contract:"Preserve original acceptance verbatim; draft authority never implies runtime release."
  }));
  const details = [...detailRows,...deferredDetails];
  const sourceTrace = registry.features.flatMap(f=>f.source_candidate_ids.split(";").filter(x=>!x.startsWith("NONE-")).map(source_candidate_id=>({
    source_candidate_id,capability_id:f.feature_id,domain:f.domain,detail_ids:detailRows.filter(d=>d.capability_id===f.feature_id).map(d=>d.detail_id),
    trace_type:"PARENT_CAPABILITY_MAPPING",note:"Candidate ID preserved exactly from original reconciliation. Parent mapping is not proof that every candidate nuance is implemented or semantically complete."
  })));
  const archiveFiles = [
    ...["GLOBAL_BUSINESS_UNIVERSE_2026.md","GLOBAL_ERP_BENCHMARK_2026.md","ADVERSARIAL_AGENT_DEBATE.md","UNIFIED_ARCHITECTURE_DECISIONS.md","REPO_PR_CODE_RECONCILIATION.md","END_TO_END_DEMO_TEST_FACTORY.md","FREE_FIRST_COST_LICENSE_AND_LIMITS.md","GOOGLE_DRIVE_INTEGRATION_CONTRACT.md","MASTER_BUILD_ROADMAP.md","PREVIEW_ONE_COMPLETION.md"].map(x=>"docs/strategy/"+x),
    "docs/strategy/research-inputs/master-mandate.md",
    "docs/development/CODEX_MASTER_EXECUTION_HANDOVER_2026-11-11.md",
    "docs/architecture/C10_A051_WORKFORCE_PAYROLL.md",
    "docs/architecture/C10_A053_A054_WORKFORCE_INTEGRATION_POLICY.md",
    "docs/architecture/C10_A055_RPC_CONTRACT.md",
    "docs/architecture/C10_A056_CRM_LIFECYCLE.md"
  ];
  const archive = archiveFiles.map((file,index)=>{
    const text=read(file),chunks=[];
    for(let offset=0;offset<text.length;){
      let end=Math.min(offset+3500,text.length);
      if(end<text.length&&text.charCodeAt(end-1)>=0xD800&&text.charCodeAt(end-1)<=0xDBFF)end--;
      chunks.push(text.slice(offset,end));offset=end;
    }
    return {document_id:"C10-RESEARCH-"+String(index+1).padStart(3,"0"),path:file,sha256:hash(text),characters:text.length,chunks,
      source_url:file.endsWith("master-mandate.md")?"https://drive.google.com/file/d/1JlJjg6_orkQFjVyOGXjl0LpDi4O3qOdm/view":"https://github.com/mistybari99/CORE-10-CENTRAL/blob/codex/detailed-build-register-20261111/"+file,
      note:"Preserved source text. Historical implementation/policy claims are snapshots; current Book/REV-010 and per-feature evidence take precedence."};
  });
  const modules = ordered.map((id,index)=>{
    const f=byId.get(id),rows=detailRows.filter(d=>d.capability_id===id);
    return {sequence:index+1,capability_id:id,module:f.domain,stage:stage(id),priority:f.priority,detail_count:rows.length,
      dependencies:f.dependency,source_candidate_ids:f.source_candidate_ids,decisions:f.owner_decision_link,
      workflow:f.workflow_inputs_outputs,existing_evidence:currentEvidence(id,f),completion_status:"NOT_COMPLETE_PER_DETAIL",
      entry_gate:"Canonical scope/grants, upstream contracts and synthetic fixture available.",
      exit_gate:"Every in-scope detail has UI/API/storage/audit/report/calculation/negative/recovery evidence; missing/blocked rows stay visible. Staging/release gates remain separate.",
      build_process:"Contract → reuse/extend code → durable schema/API → guided UI → reports → positive/negative/race tests → integrated chain → preview → evidence/Book update → separate release.",
      scope_class:f.priority==="P3"?"release-gated":"existing-mandate"};
  });
  const result={schema_version:"core10-detailed-build-plan-v1",authority:BOOK,
    truth_note:"Finite source preservation and planning coverage, not a guarantee covering every possible global ERP feature, implementation completeness, or release approval.",
    policy_note:"REV-010 permits Claude Code isolated simulation draft coding only; no Codex simulation implementation/merge/deploy authorization; A024 deferred.",
    registry,requirement_trace:requirementTrace,source_trace:sourceTrace,details,modules,archive,revisions:revisions.rows};
  validate(result);
  result.counts={capabilities:registry.features.length,source_candidates:sourceTrace.length,owner_requirements:requirementTrace.filter(x=>x.record_type==="OWNER_REQUIREMENT").length,
    implementation_notes:requirementTrace.filter(x=>x.record_type!=="OWNER_REQUIREMENT").length,atomic_details:details.length,
    hr_details:detailRows.filter(x=>x.capability_id===cap("HR-001")).length,archived_documents:archive.length,
    unmapped_capabilities:0,unmapped_source_ids:0,unmapped_requirements:0};
  return result;
}
function validate(p) {
  assert.equal(p.registry.features.length,32);
  const parentIds=new Set(p.registry.features.map(x=>x.feature_id));
  const allIds=new Set([...parentIds,SIM,SAAS]);
  assert.equal(new Set(p.details.map(x=>x.detail_id)).size,p.details.length,"Duplicate atomic feature ID");
  for(const id of parentIds) assert(p.details.filter(x=>x.capability_id===id).length>=10,"Missing module detail: "+id);
  assert(p.details.filter(x=>x.capability_id===cap("HR-001")).length>=60,"HR detail is too coarse");
  for(const d of p.details){
    assert(allIds.has(d.capability_id),"Unknown detail parent");
    for(const field of ["area","title","workflow","acceptance","negative_cases","dependencies","existing_evidence","gap","status","scope_class"])
      assert.equal(typeof d[field],"string",d.detail_id+" missing "+field);
    assert(d.acceptance.trim().length>20 && d.negative_cases.trim().length>10,"Unverifiable feature "+d.detail_id);
    assert(d.status==="PLANNED_DETAIL_NOT_CERTIFIED","Planning is not implementation proof");
  }
  const sourceIds=p.source_trace.map(x=>x.source_candidate_id);
  assert.equal(sourceIds.length,116);assert.equal(new Set(sourceIds).size,116,"Duplicate source candidate");
  const expected=p.registry.features.flatMap(f=>f.source_candidate_ids.split(";").filter(x=>!x.startsWith("NONE-"))).sort();
  assert.deepEqual([...sourceIds].sort(),expected,"Source candidate omitted");
  for(const s of p.source_trace){
    assert(s.detail_ids.length>0,"Unmapped research source");
    for(const id of s.detail_ids)assert(p.details.some(d=>d.detail_id===id&&d.capability_id===s.capability_id),"Invalid research-to-detail link");
  }
  const reqs=p.requirement_trace.filter(x=>x.record_type==="OWNER_REQUIREMENT");
  assert.deepEqual(reqs.map(x=>x.requirement_id).sort(),Array.from({length:129},(_,i)=>"R"+String(i+1).padStart(3,"0")),"Owner requirement omitted/duplicated");
  for(const r of p.requirement_trace){assert(r.capability_ids.length>0);for(const id of r.capability_ids)assert(allIds.has(id));}
  assert(p.requirement_trace.some(x=>x.requirement_id==="R124-IMPL-NOTE-01"),"Historical note lost");
  for(const doc of p.archive){const text=doc.chunks.join("");assert.equal(hash(text),doc.sha256,"Research archive truncated");assert.equal(text.length,doc.characters);}
  assert(p.revisions.some(x=>x[0]==="REV-010"),"Latest revision omitted");
  assert(p.policy_note.includes("Claude Code isolated"));
  return true;
}
if(require.main===module){
  const p=build();fs.writeFileSync(path.join(ROOT,"docs/strategy/DETAILED_BUILD_REGISTER.json"),JSON.stringify(p,null,2)+"\n");
  console.log("PASS detailed planning preservation:",JSON.stringify(p.counts));
}
module.exports={build,validate};
