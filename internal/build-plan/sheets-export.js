"use strict";
const fs=require("node:fs"),path=require("node:path");
const ROOT=path.resolve(__dirname,"../..");
function sheets(p){
 const txt=x=>Array.isArray(x)?x.join("; "):String(x??"");
 const project=(rows,keys)=>rows.map(r=>keys.map(k=>txt(r[k])));
 const fields=Object.keys(p.registry.features[0]);
 const detailKeys=["detail_id","capability_id","area","title","scope_class","priority","stage","workflow","acceptance","negative_cases","dependencies","existing_evidence","gap","status","owner_requirement_ids","owner_decisions","source_candidate_ids","source_paths","ui_api_storage_report_contract","guidance_contract","implementation_evidence_status","verification_contract"];
 return [
 {id:6101,title:"RESEARCH ARCHIVE",headers:["Document ID","Source path","SHA256 of full text","Part","Total parts","Source URL","Complete text chunk — expand cell","Historical/source note"],rows:p.archive.flatMap(d=>d.chunks.map((c,i)=>[d.document_id,d.path,d.sha256,String(i+1),String(d.chunks.length),d.source_url,c,d.note])),dropdowns:{}},
 {id:6102,title:"CAPABILITY REGISTER",headers:fields,rows:project(p.registry.features,fields),dropdowns:{}},
 {id:6103,title:"SOURCE TRACE",headers:["Research candidate ID","Capability ID","Domain","Atomic detail IDs","Mapping type","Coverage limit"],rows:project(p.source_trace,["source_candidate_id","capability_id","domain","detail_ids","trace_type","note"]),dropdowns:{}},
 {id:6104,title:"REQUIREMENT TRACE",headers:["Requirement ID","Area","Original owner wording","Master decisions","Original authority","Original acceptance","Mapped capability/scope IDs","Live source row","Record type","Current sequencing"],rows:project(p.requirement_trace,["requirement_id","area","text","decisions","authority","acceptance","capability_ids","source_url","record_type","sequencing"]),dropdowns:{}},
 {id:6105,title:"MODULE BUILD DETAIL",headers:["Detail ID","Capability / scope ID","Area","Atomic feature","Scope classification","Priority","Build stage","End-to-end workflow","Acceptance / expected result","Negative / exception tests","Dependencies","Existing evidence — not certification","Remaining gap","Build status","Owner requirement IDs","Master decision IDs","Research source IDs","Source paths","UI/API/storage/report contract","Guidance / calculation contract","Evidence status","Verification needed"],rows:project(p.details,detailKeys),dropdowns:{4:["existing-mandate","proposed-extension","release-gated"],13:["PLANNED_DETAIL_NOT_CERTIFIED","CODED","ISOLATED_TESTED","INTEGRATED_TESTED","STAGING_VERIFIED","RELEASED","BLOCKED","NOT_APPLICABLE"],20:["NOT_CERTIFIED_PER_DETAIL","EVIDENCE_REVIEW_NEEDED","VERIFIED_ISOLATED","VERIFIED_INTEGRATED","VERIFIED_STAGING","VERIFIED_RELEASE"]}},
 {id:6106,title:"MODULE DELIVERY",headers:["Sequence","Capability ID","Module","Build stage","Priority","Atomic detail count","Dependencies","Research source IDs","Decisions","End-to-end workflow","Existing evidence","Completion status","Entry gate","Exit gate","Build process","Scope classification"],rows:project(p.modules,["sequence","capability_id","module","stage","priority","detail_count","dependencies","source_candidate_ids","decisions","workflow","existing_evidence","completion_status","entry_gate","exit_gate","build_process","scope_class"]),dropdowns:{11:["NOT_COMPLETE_PER_DETAIL","CODE_DEMO_COMPLETE","STAGING_VERIFIED","RELEASED","BLOCKED"]}}
 ];
}
if(require.main===module){
 const p=JSON.parse(fs.readFileSync(path.join(ROOT,"docs/strategy/DETAILED_BUILD_REGISTER.json"),"utf8"));
 const tabs=sheets(p);
 if(process.argv[2]==="metadata")console.log(JSON.stringify(tabs.map(({rows,...t})=>({...t,rowCount:rows.length+1,columnCount:t.headers.length}))));
 else{
  const tab=tabs.find(t=>t.id===Number(process.argv[2]));if(!tab)throw Error("Unknown tab");
  const start=Number(process.argv[3]||0),count=Number(process.argv[4]||40);
  const rows=[tab.headers,...tab.rows].slice(start,start+count);
  console.log(JSON.stringify({sheetId:tab.id,start,rows}));
 }
}
module.exports={sheets};
