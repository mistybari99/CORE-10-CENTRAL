'use strict';
// Runs on local synthetic fixture only. No signed role, real accounts, RLS, database or network.
const source=require('./source-books-fixture.json');
const scope=require('./source-books-posting-boundary-fixture.json');
const adapter=require('./source-books-posting-boundary.cjs');
function run(){
 const plan=adapter.planPostingCandidates({
  syntheticFixture:source,build01Context:scope.build01Context,
  authenticatedActorUid:scope.authenticatedActorUid,selection:scope.selection,
  siteBindings:scope.siteBindings
 });
 const first=adapter.simulateDraftQueue([],plan);
 const replay=adapter.simulateDraftQueue(first.records,plan);
 if(first.records.length!==7||first.newCount!==7||
   replay.newCount!==0||replay.replayed!==7||
   plan.posted!==false||replay.posted!==false||
   plan.realAuthSignedByBackend!==false||plan.realChartAccountsMapped!==false)
  throw Error('DRAFT_POSTING_BOUNDARY_SAFETY_FAILED');
 return {status:'SYNTHETIC_SIGNED_SCOPE_DRAFT_ONLY',
  financeDrafts:plan.proposals.filter(x=>x.kind==='FINANCE_EXPENSE_DRAFT').length,
  packagingDrafts:plan.proposals.filter(x=>x.kind==='RETURNABLE_PACKAGING_DRAFT').length,
  batchSha256:plan.proposalDigest,queueCount:first.records.length,replayCount:replay.replayed,
  approved:false,erpPosted:false,realAuthorization:false,deployable:false};
}
if(require.main===module)console.log(JSON.stringify(run(),null,2));
module.exports={run};
