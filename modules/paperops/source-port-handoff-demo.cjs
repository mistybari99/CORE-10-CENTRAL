'use strict';
/* Reproducible synthetic intent preview for planned CORE-10 signed server port review.
 * Never invokes Auth, Stock, Money, Approval, Audit, Postgres or Workers.
 */
const fixture=require('./source-books-fixture.json');
const port=require('./source-port-handoff.cjs');
function run(data=fixture){
 const controls={requestId:'DEMO-SOURCE-HANDOFF-001',
  requestedBy:'DEMO-OPERATOR',independentReviewer:'DEMO-ACCOUNTANT',
  designatedApprover:'DEMO-OWNER',policyCandidateRef:'DEMO-PAPEROPS-POLICY-DRAFT'};
 const preview=port.previewHandoff(data,controls);
 if(!port.verifyPreview(preview))throw Error('SYNTHETIC_HANDOFF_INTEGRITY_FAILED');
 return preview;
}
if(require.main===module){
 const r=run();
 const out={status:r.status,intents:r.intents.length,
  byPort:Object.fromEntries([...new Set(r.intents.map(x=>x.modulePort))]
   .map(k=>[k,r.intents.filter(x=>x.modulePort===k).length])),
  previewDigest:r.previewDigest,scope:r.sourceScope,
  containsRealAuth:false,approved:r.approvalServerVerified,
  canPost:r.canPost,databaseTouched:r.databaseTouched,
  gapsStillOpen:r.unresolvedBusinessGaps};
 console.log(JSON.stringify(out,null,2));
 if(r.intents.length!==8||r.canPost!==false||r.databaseTouched!==false)process.exitCode=1;
}
module.exports={run};
