'use strict';
/* CORE-10 PaperOps canonical posting BOUNDARY PROTOTYPE:
 * Builds deterministic, scoped, source-backed proposals, never ERP writes.
 * build01_context_v1 is a read-only RPC context observation, NOT a backend
 * signature nor accounting authorization. Do not wire to production posting.
 */
const {createHash}=require('node:crypto');
const sourceBooks=require('./source-books.cjs');
const MAX_INT=Number.MAX_SAFE_INTEGER;
function fail(message){throw Error('PAPEROPS_POSTING_BOUNDARY:'+message);}
function key(v,label){
 if(typeof v!=='string'||!/^[-A-Za-z0-9_.:]{1,128}$/.test(v))fail('INVALID_'+label);
 return v;
}
function idNumber(n,label){
 if(!Number.isSafeInteger(n)||n<=0)fail('INVALID_'+label);
 return n;
}
function money(v,label){
 const raw=typeof v==='number'&&Number.isFinite(v)?String(v):v;
 if(typeof raw!=='string'||!(/^\d+(?:\.\d{1,2})?$/).test(raw))fail('INVALID_MONEY:'+label);
 const [whole,rest='']=raw.split('.');
 const c=Number(whole)*100+Number(rest.padEnd(2,'0'));
 if(!Number.isSafeInteger(c))fail('UNSAFE_MONEY:'+label);
 return c;
}
function currency(c){
 if(!Number.isSafeInteger(c)||c<0)fail('UNSAFE_CURRENCY_FORMAT');
 return (c/100).toFixed(2);
}
function hash(value){return createHash('sha256').update(JSON.stringify(value)).digest('hex');}
function inspectContext(context,actorUid,selected,siteBindings,sourceSites){
 // No unsigned context can authorize an actual financial/stock posting. This
 // check is strictly for consistency of the observed Build01 RPC response.
 if(!context||typeof context!=='object')fail('NO_BUILD01_CONTEXT');
 key(actorUid,'SIGNED_IN_ACTOR_UID');
 if(context.actor_uid!==actorUid)fail('SIGNED_ACTOR_CONTEXT_MISMATCH');
 if(!Array.isArray(context.tenants)||!Array.isArray(context.businesses)||!Array.isArray(context.sites))
  fail('CANONICAL_CONTEXT_COLLECTIONS_REQUIRED');
 idNumber(selected?.tenantId,'TENANT_ID');idNumber(selected?.businessId,'BUSINESS_ID');
 const tenant=context.tenants.filter(t=>t?.id===selected.tenantId);
 const business=context.businesses.filter(b=>b?.id===selected.businessId);
 if(tenant.length!==1||business.length!==1||business[0].tenant_id!==selected.tenantId)
  fail('UNAUTHORIZED_OR_CROSS_TENANT_BUSINESS_SELECTION');
 if(Object.keys(siteBindings||{}).length!==sourceSites.length||
    Object.keys(siteBindings||{}).some(id=>!sourceSites.includes(id)))
  fail('MISSING_OR_UNEXPECTED_SITE_BINDINGS');
 const seen=new Set();
 const resolved=[];
 for(const sourceId of sourceSites){
  key(sourceId,'ORIGINAL_SITE_SOURCE');
  const siteId=idNumber(siteBindings[sourceId],'CANONICAL_SITE');
  const matches=context.sites.filter(s=>s?.id===siteId);
  if(matches.length!==1||matches[0].tenant_id!==selected.tenantId||
     matches[0].business_id!==selected.businessId||seen.has(siteId))
    fail('CANONICAL_SITE_SCOPE_OR_DUPLICATE_MISMATCH');
  seen.add(siteId);resolved.push({sourceSiteId:sourceId,siteId});
 }
 // can_manage is NOT a posting entitlement. Do not promote this observation
 // into a signed server-side RLS/authorization decision.
 return {tenantId:selected.tenantId,businessId:selected.businessId,sites:resolved,
  actorUid,serverPermissionChecked:false,financialRoleChecked:false};
}
function siteNumber(binding,sourceId){
 const row=binding.sites.find(s=>s.sourceSiteId===sourceId);
 if(!row)fail('UNMAPPED_SOURCE_SITE');
 return row.siteId;
}
function makeRow(type,sourceRef,binding,payload){
 const tenantId=binding.tenantId,businessId=binding.businessId;
 key(sourceRef,'SOURCE_REFERENCE');
 const idempotencyKey='paperops:'+tenantId+':'+businessId+':'+type+':'+sourceRef;
 const body={kind:type,scope:{tenantId,businessId},sourceRef,payload};
 return {idempotencyKey,sourceDigest:hash(body),...body,
  decision:'DRAFT_NOT_AUTHORIZED',sourceOfTruth:'FROZEN_LEGACY_PROTOTYPE',
  accountingPostApproved:false,warehousePostApproved:false};
}
function planPostingCandidates({syntheticFixture,build01Context,authenticatedActorUid,selection,siteBindings}={}){
 if(syntheticFixture?.synthetic_only!==true||
    syntheticFixture?.scope?.tenantId!=='DEMO-TENANT-ISOLATED'||
    syntheticFixture?.scope?.businessId?.startsWith('DEMO-')!==true)
  fail('ONLY_ISOLATED_DEMO_INPUT_ALLOWED');
 const srcSites=syntheticFixture.scope.sites;
 const binding=inspectContext(build01Context,authenticatedActorUid,selection,siteBindings,srcSites);
 const packing=sourceBooks.packagingLedger(syntheticFixture.packaging);
 const spending=sourceBooks.expenseCashbookReconcile(syntheticFixture.expense);
 if(packing.status!=='REVIEW_READY_NOT_APPROVED'||spending.status!=='REVIEW_READY_NOT_APPROVED')
  fail('SOURCE_BOOKS_NOT_RECONCILED');
 const proposals=[];
 const voucher=syntheticFixture.expense.vouchers;
 for(const v of voucher){
  // One C-02 source voucher produces one proposed journal. The R-01 close
  // is a reconciliation reference; it must NOT create a second expense posting.
  const debit=v.lines.map((line,i)=>{
   const cents=money(line.amountBDT,'EXPENSE_'+i);
   if(cents===0)fail('ZERO_EXPENSE_NOT_POSTABLE');
   key(line.head,'EXPENSE_HEAD_SOURCE');
   return {side:'DR',sourceHead:line.head,account:'UNRESOLVED_EXPENSE_CHART_ACCOUNT',
    amountBDT:currency(cents)};
  });
  const total=debit.reduce((n,l)=>n+money(l.amountBDT,'SOURCE_DEBIT'),0);
  if(!Number.isSafeInteger(total)||total<=0||total>MAX_INT)fail('FINANCE_TOTAL_UNSAFE');
  const credit=[{side:'CR',sourceCashAccount:v.cashAccountId,
    account:'UNRESOLVED_IMPREST_CASH_CHART_ACCOUNT',amountBDT:currency(total)}];
  if(money(v.lines.reduce((sum,line)=>sum+money(line.amountBDT,'CHECK_AMOUNT'),0)/100,'C02_TOTAL_CHECK')!==total)
   fail('DEBIT_TOTAL_INCORRECT');
  const book=syntheticFixture.expense.cashbookRows.filter(x=>x.sourceVoucherId===v.id);
  if(book.length!==1)fail('EXACTLY_ONE_CASHBOOK_SOURCE_ROW_REQUIRED');
  proposals.push(makeRow('FINANCE_EXPENSE_DRAFT',v.id,binding,{
   debit,credit,source:'C-02',sourceVoucherRef:v.id,sourceR01Ref:v.sheetRef,
   sourceCashbookRef:book[0].id,unverifiedCashbookAccount:v.cashAccountId,
   proposedSiteId:siteNumber(binding,v.siteId),
   noDuplicateR01Posting:true,requiresRealAccountMapping:true,
   requiresServerSideActorAndApproval:true
  }));
 }
 // Rebuild exact normalized packaging movements and checked cumulative balances.
 for(let i=0;i<syntheticFixture.packaging.events.length;i++){
  const e=syntheticFixture.packaging.events[i],b=packing.entries[i];
  if(b.id!==e.id||b.sourceRef!==e.sourceRef)fail('PACKAGING_SOURCE_REORDERED');
  proposals.push(makeRow('RETURNABLE_PACKAGING_DRAFT',e.sourceRef,binding,{
   source:'W-02',sourceMoveId:e.id,kind:e.type,
   originalIssueId:e.type==='RETURN'?e.originalIssueId:null,
   siteFromId:siteNumber(binding,e.fromSiteId),
   siteToId:siteNumber(binding,e.toSiteId),
   sourceSenderRef:e.senderProofRef,sourceReceiverRef:e.receiverProofRef,
   cratesDelta:b.cratesDelta,traysDelta:b.traysDelta,
   declaredCratesDue:b.cratesOutstanding,declaredTraysDue:b.traysOutstanding,
   needsRealSignedTransferAndReturnLedger:true
  }));
 }
 if(new Set(proposals.map(p=>p.idempotencyKey)).size!==proposals.length)
  fail('DUPLICATE_PROPOSAL_SOURCE_KEY');
 const digest=hash(proposals.map(p=>({key:p.idempotencyKey,digest:p.sourceDigest})));
 return Object.freeze({
  status:'POSTING_PROPOSALS_DRAFT_NEVER_AUTHORIZE',
  businessScope:binding,sourceProofs:{
   originalVoucherTotalBDT:spending.totals.originalVoucherBDT,
   r01ExpenseTotalBDT:spending.totals.r01ExpenseBDT,
   cashbookExpenseTotalBDT:spending.totals.cashbookExpenseBDT,
   packagingEntries:packing.entries.length
  },proposalDigest:digest,proposals,
  realAuthSignedByBackend:false,realFinancePermissionChecked:false,
  realWarehousePermissionChecked:false,realChartAccountsMapped:false,
  posted:false,approved:false,erpReady:false,ownerAccepted:false
 });
}
function validateRow(row){
 if(!row||row.decision!=='DRAFT_NOT_AUTHORIZED'||row.accountingPostApproved!==false||
   row.warehousePostApproved!==false||!row.payload||
   !['FINANCE_EXPENSE_DRAFT','RETURNABLE_PACKAGING_DRAFT'].includes(row.kind))
  fail('UNAUTHORIZED_OR_UNKNOWN_DRAFT');
 const body={kind:row.kind,scope:row.scope,sourceRef:row.sourceRef,payload:row.payload};
 if(hash(body)!==row.sourceDigest)fail('DRAFT_DIGEST_MISMATCH');
 const expectedKey='paperops:'+row.scope.tenantId+':'+row.scope.businessId+':'+row.kind+':'+row.sourceRef;
 if(row.idempotencyKey!==expectedKey)fail('DRAFT_IDEMPOTENCY_KEY_MISMATCH');
 if(row.kind==='FINANCE_EXPENSE_DRAFT'){
  if(row.payload.noDuplicateR01Posting!==true||!row.payload.requiresRealAccountMapping||
    row.payload.debit?.length<1||row.payload.credit?.length!==1)fail('FINANCE_DRAFT_CONTRACT_INVALID');
  const debit=row.payload.debit.reduce((sum,x)=>{
   if(x.side!=='DR'||x.account!=='UNRESOLVED_EXPENSE_CHART_ACCOUNT')fail('UNRESOLVED_CHART_POLICY_BYPASS');
   const n=sum+money(x.amountBDT,'DEBIT');if(!Number.isSafeInteger(n))fail('AMOUNT_OVERFLOW');return n;
  },0);
  const credit=row.payload.credit.reduce((sum,x)=>{
   if(x.side!=='CR'||x.account!=='UNRESOLVED_IMPREST_CASH_CHART_ACCOUNT')fail('UNRESOLVED_CHART_POLICY_BYPASS');
   const n=sum+money(x.amountBDT,'CREDIT');if(!Number.isSafeInteger(n))fail('AMOUNT_OVERFLOW');return n;
  },0);
  if(debit===0||debit!==credit)fail('UNBALANCED_FINANCE_DRAFT');
 }else{
  const p=row.payload;
  if(!Number.isSafeInteger(p.cratesDelta)||!Number.isSafeInteger(p.traysDelta)||
    !Number.isSafeInteger(p.declaredCratesDue)||!Number.isSafeInteger(p.declaredTraysDue)||
    p.siteFromId===p.siteToId||p.needsRealSignedTransferAndReturnLedger!==true)
   fail('INVALID_RETURNABLE_PACKAGING_DRAFT');
 }
}
function simulateDraftQueue(previous,plan){
 if(!Array.isArray(previous)||!plan||plan.status!=='POSTING_PROPOSALS_DRAFT_NEVER_AUTHORIZE'||
   plan.erpReady!==false||plan.realAuthSignedByBackend!==false||
   plan.posted!==false||plan.ownerAccepted!==false)
  fail('FORBIDDEN_REAL_LEDGER_COMMIT');
 const drafts=plan.proposals;
 if(!Array.isArray(drafts)||!drafts.length)fail('EMPTY_DRAFT_QUEUE');
 if(hash(drafts.map(p=>({key:p.idempotencyKey,digest:p.sourceDigest})))!==plan.proposalDigest)
  fail('DRAFT_BATCH_DIGEST_MISMATCH');
 const seen=new Map();
 for(const row of previous){
  validateRow(row);
  if(seen.has(row.idempotencyKey))fail('CORRUPT_PREVIOUS_DRAFT_QUEUE');
  seen.set(row.idempotencyKey,row);
 }
 let newCount=0,replayed=0;
 for(const row of drafts){
  validateRow(row);
  const earlier=seen.get(row.idempotencyKey);
  if(earlier){
   if(earlier.sourceDigest!==row.sourceDigest)fail('IDEMPOTENCY_CONFLICT_DETECTED');
   replayed++;continue;
  }
  seen.set(row.idempotencyKey,row);newCount++;
 }
 // Functional, no mutation; no database or file writes.
 return Object.freeze({records:Object.freeze([...seen.values()]),newCount,replayed,
  status:'LOCAL_MEMORY_DRAFT_ONLY_NO_POST',posted:false,
  authorizationVerified:false,ownerAccepted:false});
}
function postToERP(){
 fail('REAL_ERP_POSTING_NOT_IMPLEMENTED_NO_CANONICAL_PERMISSION_OR_SCHEMA');
}
module.exports=Object.freeze({planPostingCandidates,simulateDraftQueue,postToERP,validateRow});
