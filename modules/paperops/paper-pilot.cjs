'use strict';
const pilot=require('./pilot-scenarios.json');
const paperops=require('./paperops.js');
require('./form-packs.js');
const kit=require('./paper-kit.js');
function runPilots(){
  const outcomes=[];
  for(const sample of pilot.cases){
    const p=kit.planDay({date:pilot.day,businessName:pilot.businessName,
      industry:sample.industry,sites:sample.sites,events:sample.events});
    const actual=p.forms.map(f=>f.formId);
    const issues=[];
    if(p.dailyCount!==sample.expect.daily)issues.push('UNEXPECTED_DAILY_COUNT');
    if(p.eventCount!==sample.expect.event)issues.push('UNEXPECTED_EVENT_COUNT');
    if(JSON.stringify(actual)!==JSON.stringify(sample.expect.forms))issues.push('UNEXPECTED_FORM_SELECTION');
    if(p.count>100)issues.push('EXCESSIVE_PILOT_PRINT');
    const html=kit.printKit(p,{lang:'bn',groupName:'Synthetic Pilot Group'});
    const printed=(html.match(/class="paperops-kit-sheet"/g)||[]).length;
    if(printed!==p.count)issues.push('PRINTED_SHEETS_MISMATCH');
    if(p.coverageStatus!=='INCOMPLETE_DRAFT_DO_NOT_USE_AS_A_COMPLETE_OFFLINE_ACCOUNTING_KIT')
      issues.push('IMPROPER_PAPER_COMPLETENESS_CLAIM');
    outcomes.push({
      id:sample.id,title:sample.title,industry:sample.industry,
      daily:p.dailyCount,event:p.eventCount,total:p.count,siteCount:sample.sites.length,
      avoidedRetailCloses:p.excludedDailySites.length,
      selected:actual,issues,passed:issues.length===0,
      ownerApproved:false,offlineAccountingComplete:false
    });
  }
  return {schema_version:1,synthetic_only:true,caseCount:outcomes.length,
    totalPagesPlanned:outcomes.reduce((n,x)=>n+x.total,0),
    allPass:outcomes.every(x=>x.passed),cases:outcomes};
}
if(require.main===module){
  const result=runPilots();
  console.log(JSON.stringify(result,null,2));
  if(!result.allPass)process.exitCode=1;
}
module.exports={runPilots};
