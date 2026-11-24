'use strict';
/* PaperOps -> CORE-10 port intent boundary (isolated prototype).
 * This module NEVER authenticates a user, verifies a real signature, grants an approval,
 * persists an accounting entry or calls CORE-10 RPCs. All inputs must be synthetic.
 * Actual role and business authorization must be done by canonical server-side ports.
 */
const {createHash}=require('node:crypto');
const books=require('./source-books.cjs');
const TOKEN=/^[A-Za-z0-9][A-Za-z0-9._:-]{0,119}$/;
const allowedKinds=Object.freeze({
 PACKAGING:'STOCK_PORT_RETURNABLE_CUSTODY_PROPOSED',
 EXPENSE:'MONEY_PORT_IMPREST_EXPENSE_PROPOSED',
 CASHBOOK:'MONEY_PORT_CASHBOOK_CROSSCHECK_PROPOSED'
});
function ident(value,name){
 if(typeof value!=='string'||!TOKEN.test(value))throw Error('INVALID_HANDOFF_'+name);
 return value;
}
function canonical(value){
 if(value===null||typeof value==='string'||typeof value==='boolean')
  return JSON.stringify(value);
 if(typeof value==='number'){
  if(!Number.isSafeInteger(value))throw Error('UNSAFE_HANDOFF_NUMBER');
  return JSON.stringify(value);
 }
 if(Array.isArray(value))return '['+value.map(canonical).join(',')+']';
 if(value&&typeof value==='object'&&Object.getPrototypeOf(value)===Object.prototype){
  const keys=Object.keys(value).sort();
  if(keys.some(k=>k==='__proto__'||k==='prototype'||k==='constructor'))
   throw Error('UNSAFE_HANDOFF_OBJECT_KEY');
  return '{'+keys.map(k=>JSON.stringify(k)+':'+canonical(value[k])).join(',')+'}';
 }
 throw Error('INVALID_HANDOFF_CANONICAL_VALUE');
}
function digest(value){
 return createHash('sha256').update(canonical(value),'utf8').digest('hex');
}
function scopeKey(a){
 if(!a||a.synthetic_only!==true||a.tenantId!=='DEMO-TENANT-ISOLATED')
  throw Error('REAL_CONTEXT_REQUIRES_SERVER_AUTH_AND_IS_NOT_SUPPORTED');
 ident(a.businessId,'BUSINESS_ID');
 if(!a.businessId.startsWith('DEMO-'))throw Error('ONLY_DEMO_BUSINESS');
 if(!Array.isArray(a.sites)||!a.sites.length||a.sites.length>400||
    new Set(a.sites).size!==a.sites.length)
  throw Error('INVALID_HANDOFF_SITES');
 for(const s of a.sites) {
  ident(s,'SITE_ID');
  if(!s.startsWith('DEMO-'))throw Error('ONLY_DEMO_SITES');
 }
 return a.tenantId+'/'+a.businessId;
}
function evidenceActors(controls){
 if(!controls||typeof controls!=='object')throw Error('MISSING_REVIEW_ROLES');
 const names=['requestedBy','independentReviewer','designatedApprover'];
 const vals=names.map(n=>ident(controls[n],n.toUpperCase()));
 if(new Set(vals).size!==vals.length)throw Error('REVIEW_ROLE_COLLISION');
 for(const v of vals)if(!v.startsWith('DEMO-'))throw Error('REAL_IDENTITY_NOT_VERIFIED');
 ident(controls.policyCandidateRef,'POLICY_REF');
 if(!controls.policyCandidateRef.startsWith('DEMO-'))
  throw Error('UNVERIFIED_POLICY_SOURCE');
 return {requestedBy:vals[0],independentReviewer:vals[1],
  designatedApprover:vals[2],policyCandidateRef:controls.policyCandidateRef,
  policyActuallyApproved:false,signaturesServerVerified:false};
}
function intent(k,siteId,sourceId,sourceData,scope,routeKey){
 ident(siteId,'INTENT_SITE_ID');ident(sourceId,'INTENT_SOURCE_REF');
 if(!scope.sites.includes(siteId))throw Error('INTENT_OUT_OF_SIGNED_SCOPE');
 const sourceHash=digest(sourceData);
 return {
  key:'paperops:'+k+':'+siteId+':'+sourceId,
  idempotencyScope:scope.tenantId+'/'+scope.businessId+'/'+siteId,
  sourceId,sourceHash,siteId,
  modulePort:allowedKinds[routeKey],
  action:'PROPOSE_OFFLINE_SOURCE_INTENT_ONLY',
  requiresCanonicalServerChecks:[
    'SIGNED_AUTH_SESSION_AND_ACTIVE_GROUP_BUSINESS_SITE',
    'SERVER_RESOLVED_ROLE_AND_ENTITLEMENT',
    'ACTUAL_POLICY_VERSION_AND_INDEPENDENT_APPROVAL',
    'IMMUTABLE_SOURCE_DOCUMENT_AND_CUSTODY_PROOF',
    'ATOMIC_IDEMPOTENCY_KEY_AND_SOURCE_LINK_LOCK',
    'POSTING_LEDGER_AND_REVERSAL_RECONCILIATION'
  ],
  writesPermitted:false,postingAuthorized:false
 };
}
function previewHandoff(sourceData,controls){
 if(!sourceData||sourceData.synthetic_only!==true)
  throw Error('SYNTHETIC_HANDOFF_ONLY');
 const scope=sourceData.scope,sourceKey=scopeKey(scope),people=evidenceActors(controls);
 ident(controls.requestId,'REQUEST_ID');
 if(!controls.requestId.startsWith('DEMO-'))throw Error('ONLY_DEMO_REQUEST_ALLOWED');
 if(canonical(scope)!==canonical(sourceData.packaging?.scope)||
    canonical(scope)!==canonical(sourceData.expense?.scope))
  throw Error('SOURCE_BOOK_SCOPE_NOT_IDENTICAL');
 const p=books.packagingLedger(sourceData.packaging);
 const e=books.expenseCashbookReconcile(sourceData.expense);
 if(p.status!=='REVIEW_READY_NOT_APPROVED'||e.status!=='REVIEW_READY_NOT_APPROVED')
  throw Error('REVIEWED_SOURCE_BOOKS_MUST_HAVE_ZERO_BLOCKERS');
 const intents=[],seen=new Set(),sourceProofs=new Set();
 function push(row){
  if(seen.has(row.key))throw Error('DUPLICATE_HANDOFF_INTENT_KEY');
  seen.add(row.key);
  intents.push(row);
 }
 const packaging=sourceData.packaging.events;
 for(const event of packaging){
  const proof=event.sourceRef;
  if(sourceProofs.has('W02:'+proof))throw Error('DUPLICATE_PACKAGING_SOURCE_REF');
  sourceProofs.add('W02:'+proof);
  push(intent('PACKAGING',event.toSiteId,event.id,event,scope,'PACKAGING'));
 }
 for(const voucher of sourceData.expense.vouchers){
  if(sourceProofs.has('C02:'+voucher.id))throw Error('DUPLICATE_EXPENSE_SOURCE_REF');
  sourceProofs.add('C02:'+voucher.id);
  push(intent('EXPENSE',voucher.siteId,voucher.id,voucher,scope,'EXPENSE'));
 }
 const close=sourceData.expense.dailyClose;
 push(intent('CASHBOOK',close.siteId,close.dailyRef,{
  dailyClose:close,cashbookRows:sourceData.expense.cashbookRows,
  totalImprestBDT:e.totals.fixedImprestBDT
 },scope,'CASHBOOK'));
 const unsigned={
  version:1,requestId:controls.requestId,sourceScope:scopeKey(scope),
  status:'UNSIGNED_PORT_HANDOFF_PREVIEW_NOT_APPROVED',
  actors:people,originalBooks:{
   W02PackagingBalances:p.balances,
   C02R01VoucherTotals:e.totals
  },intents,
  unresolvedBusinessGaps:['W02-01','R01-03','C02-03','C01-01'],
  originalInputDigest:digest(sourceData),
  requestContentDigest:digest({requestId:controls.requestId,scopeKey:sourceKey,
   sourceData,actors:people}),
  canPost:false,canAuthorize:false,canonicalAuthVerified:false,
  approvalServerVerified:false,databaseTouched:false,
  signedAccountingReversal:false
 };
 return Object.freeze({...unsigned,previewDigest:digest(unsigned)});
}
function verifyPreview(preview){
 if(!preview||typeof preview!=='object'||typeof preview.previewDigest!=='string')
  return false;
 const copy={...preview};delete copy.previewDigest;
 try {
  if(digest(copy)!==preview.previewDigest||
     preview.status!=='UNSIGNED_PORT_HANDOFF_PREVIEW_NOT_APPROVED'||
     preview.canonicalAuthVerified!==false||preview.canPost!==false||
     preview.approvalServerVerified!==false||
     !Array.isArray(preview.intents)||!preview.intents.length||
     preview.intents.some(x=>x.writesPermitted!==false||x.postingAuthorized!==false||
       !Object.values(allowedKinds).includes(x.modulePort)))return false;
 }catch{return false;}
 return true;
}
function proposeCorrection(preview,correction){
 if(!verifyPreview(preview))throw Error('SOURCE_PREVIEW_INTEGRITY_FAILED');
 if(!correction||typeof correction!=='object')throw Error('INVALID_CORRECTION');
 const parent=preview.intents.find(x=>x.key===correction.originalIntentKey);
 if(!parent)throw Error('UNKNOWN_ORIGINAL_HANDOFF_INTENT');
 ident(correction.correctionRequestId,'CORRECTION_REQUEST');
 ident(correction.reasonRef,'CORRECTION_REASON');
 ident(correction.enteredBy,'CORRECTION_ENTERER');
 ident(correction.independentReviewer,'CORRECTION_REVIEWER');
 if(correction.enteredBy===correction.independentReviewer)
  throw Error('CORRECTION_SELF_REVIEW_DENIED');
 if(!correction.correctionRequestId.startsWith('DEMO-')||
    !correction.reasonRef.startsWith('DEMO-')||
    !correction.enteredBy.startsWith('DEMO-')||
    !correction.independentReviewer.startsWith('DEMO-'))
  throw Error('CORRECTION_NOT_REAL_IDENTITY_VERIFIED');
 const base={
  status:'CORRECTION_PROPOSAL_NOT_APPLIED',
  originalIntentKey:parent.key,
  parentPreviewDigest:preview.previewDigest,
  originalSourceHash:parent.sourceHash,
  correctionRequestId:correction.correctionRequestId,
  reasonRef:correction.reasonRef,
  enteredBy:correction.enteredBy,independentReviewer:correction.independentReviewer,
  operation:'PROPOSE_REVERSAL_OR_CORRECTING_ENTRY_ONLY',
  requiresSignedServerAuditAndApproval:true,
  originalUnchanged:true,reversed:false,posted:false
 };
 return Object.freeze({...base,correctionDigest:digest(base)});
}
module.exports=Object.freeze({previewHandoff,verifyPreview,proposeCorrection,digest,canonical});
