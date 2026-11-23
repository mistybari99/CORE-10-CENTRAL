'use strict';
/* W02-01: source-pinned returnable crate/tray reconciliation.
 * Original W-02 declares six HAND-ENTERED fields: this strictly local gate
 * proposes continuity checks; it does NOT reproduce an old crate formula.
 * No legacy JS execution, Stock RPC, authorization, posting or persistence.
 */
const {createHash}=require('node:crypto');
const source=require('./source-helper-conditions.cjs');
const {packagingLedger}=require('../../source-books.cjs');
const owner=require('../ownership-246-1000.json');
const FIELDS=Object.freeze(['crates_sent','crates_back','crates_due',
 'trays_sent','trays_back','trays_due'].map(k=>'W-02:'+k));
const owned=new Set([...owner.lane_B_chatgpt.critical_86_keys,
 ...owner.lane_B_chatgpt.mapped_150_keys,...owner.lane_B_chatgpt.reserved_next_10_keys]);
if(FIELDS.some(k=>!owned.has(k)||owner.lane_A_codex.ownership_keys.includes(k)))
 throw Error('W02_RETURNABLES_246_OWNERSHIP_VIOLATION');
const RE=/^[A-Za-z0-9][A-Za-z0-9._:/-]{0,119}$/;
function ref(x,label){if(typeof x!=='string'||!RE.test(x))throw Error('W02_RETURNABLES_INVALID_REF:'+label);return x;}
function qty(x,label){
 const s=typeof x==='number'&&Number.isSafeInteger(x)?String(x):x;
 if(typeof s!=='string'||!/^(?:0|[1-9]\d*)$/.test(s)||
   !Number.isSafeInteger(Number(s)))throw Error('W02_RETURNABLES_INVALID_QTY:'+label);
 return Number(s);
}
function same(row,scope,label){
 if(!row||row.tenantId!==scope.tenantId||row.businessId!==scope.businessId)
  throw Error('W02_RETURNABLES_CROSS_SCOPE:'+label);
}
function pair(row,scope,label){
 same(row,scope,label);
 ref(row.fromSiteId,label+'_FROM');ref(row.toSiteId,label+'_TO');
 if(!scope.sites.includes(row.fromSiteId)||!scope.sites.includes(row.toSiteId)||
    row.fromSiteId===row.toSiteId)throw Error('W02_RETURNABLES_WRONG_SITE_PAIR:'+label);
 return row.fromSiteId+'>'+row.toSiteId;
}
function assertSource(){
 const s=source.readFrozen('forms');source.verifyEvidence();
 const a=s.indexOf('e.forms["W-02"]='),b=s.indexOf('e.forms[',a+1);
 if(a<0)throw Error('W02_FROZEN_FORM_MISSING');
 const body=s.slice(a,b<0?s.length:b);
 const proof=[
  ['crates_sent','ক্যারেট — প্রেরিত','Crates sent'],
  ['crates_back','ক্যারেট — ফেরত','Crates returned'],
  ['crates_due','ক্যারেট — বকেয়া','Crates outstanding'],
  ['trays_sent','ট্রে — প্রেরিত','Trays sent'],
  ['trays_back','ট্রে — ফেরত','Trays returned'],
  ['trays_due','ট্রে — বকেয়া','Trays outstanding']];
 for(const [k,bn,en] of proof)
  if(!body.includes('d("'+k+'",t("'+bn+'","'+en+'"))'))
   throw Error('W02_RETURNABLES_FROZEN_FIELD_CHANGED:'+k);
 const calc=body.slice(body.indexOf('calc(e){'));
 if(calc.startsWith('calc(e){')&&/\b(?:crates|trays)_(?:sent|back|due)\b/.test(calc))
  throw Error('W02_RETURNABLES_ORIGINAL_FORMULA_NEEDS_REVIEW');
 return Object.freeze({fields:FIELDS,originalBlob:source.PIN.forms,
  sixOriginalManualFieldsProven:true,originalCrateFormulaProven:false,
  sourceExecuted:false,ownerPolicyAccepted:false,canPost:false});
}
function reviewReturnables({packaging,sourceDeclarations,openingProofs,physicalCounts}={}){
 const provenance=assertSource();
 const ledger=packagingLedger(packaging);
 const {scope,events}=packaging;
 if(!Array.isArray(sourceDeclarations)||sourceDeclarations.length>400||
    !Array.isArray(openingProofs)||openingProofs.length>400||
    !Array.isArray(physicalCounts)||physicalCounts.length>400)
  throw Error('W02_RETURNABLES_EVIDENCE_COLLECTION_REQUIRED');
 const blockers=[...ledger.blockers],block=x=>{if(!blockers.includes(x))blockers.push(x);};
 const refs=new Set(),usedProofs=new Set(),declarations=new Map();
 const uniqueProof=(x,label)=>{ref(x,label);if(usedProofs.has(x)||refs.has(x))
  throw Error('W02_RETURNABLES_REPLAYED_PROOF_REF:'+label);usedProofs.add(x);};
 for(const e of events){
  refs.add(e.sourceRef);
  uniqueProof(e.senderProofRef,'SENDER');
  uniqueProof(e.receiverProofRef,'RECEIVER');
 }
 for(const row of sourceDeclarations){
  same(row,scope,'DECLARATION');
  ref(row.eventId,'EVENT');ref(row.sourceRef,'SOURCE');
  if(declarations.has(row.eventId))throw Error('W02_RETURNABLES_DUPLICATE_DECLARATION');
  declarations.set(row.eventId,row);
 }
 if(declarations.size!==events.length)block('W02_RETURNABLES_MISSING_SOURCE_DECLARATION');
 const computed=new Map(ledger.entries.map(x=>[x.id,x]));
 const pairLast=new Map();
 for(const e of events){
  const k=e.fromSiteId+'>'+e.toSiteId;pairLast.set(k,computed.get(e.id));
  const row=declarations.get(e.id);
  if(!row){block('W02_RETURNABLES_DECLARATION_MISSING:'+e.id);continue;}
  if(row.sourceRef!==e.sourceRef||pair(row,scope,'DECLARATION')!==k)
   block('W02_RETURNABLES_DECLARATION_NOT_SAME_CHALLAN:'+e.id);
  const values={
   crates_sent:e.type==='RETURN'?0:qty(e.crates,'EVENT_CRATES'),
   crates_back:e.type==='RETURN'?qty(e.crates,'EVENT_CRATES'):0,
   trays_sent:e.type==='RETURN'?0:qty(e.trays,'EVENT_TRAYS'),
   trays_back:e.type==='RETURN'?qty(e.trays,'EVENT_TRAYS'):0
  };
  for(const name of Object.keys(values))
   if(qty(row[name],name)!==values[name])
    block('W02_RETURNABLES_EVENT_ENTRY_MISMATCH:'+e.id+':'+name);
  for(const [name,count] of [['crates_due',computed.get(e.id).cratesOutstanding],
    ['trays_due',computed.get(e.id).traysOutstanding]])
   if(qty(row[name],name)!==count)
    block('W02_RETURNABLES_OUTSTANDING_MISMATCH:'+e.id+':'+name);
 }
 for(const row of sourceDeclarations)
  if(!computed.has(row.eventId))throw Error('W02_RETURNABLES_UNKNOWN_SOURCE_DECLARATION');
 const openings=events.filter(x=>x.type==='OPENING');
 if(openings.length!==openingProofs.length)block('W02_RETURNABLES_OPENING_EVIDENCE_INCOMPLETE');
 const seenOpening=new Set();
 for(const p of openingProofs){
  const k=pair(p,scope,'OPENING_PROOF');
  ref(p.eventId,'OPENING_EVENT');ref(p.sourceRef,'OPENING_SOURCE');
  if(seenOpening.has(p.eventId))throw Error('W02_RETURNABLES_DUPLICATE_OPENING_PROOF');
  seenOpening.add(p.eventId);
  const opening=openings.find(e=>e.id===p.eventId);
  if(!opening||p.sourceRef!==opening.sourceRef||k!==opening.fromSiteId+'>'+opening.toSiteId)
   block('W02_RETURNABLES_OPENING_NOT_TIED_TO_SOURCE:'+p.eventId);
  uniqueProof(p.carryForwardRef,'CARRY_FORWARD');
  uniqueProof(p.approvalPolicyRef,'POLICY');
  uniqueProof(p.reviewerEvidenceRef,'OPENING_REVIEW');
  ref(p.recordedBy,'OPENING_RECORDER');ref(p.reviewedBy,'OPENING_REVIEWER');
  if(p.recordedBy===p.reviewedBy||opening&&[opening.senderId,opening.receiverId].includes(p.reviewedBy))
   block('W02_RETURNABLES_OPENING_INDEPENDENCE_NOT_PROVED:'+p.eventId);
 }
 if(physicalCounts.length!==pairLast.size)block('W02_RETURNABLES_PHYSICAL_COUNT_INCOMPLETE');
 const counted=new Set(),actorsByPair=new Map();
 for(const e of events){
  const k=e.fromSiteId+'>'+e.toSiteId;
  if(!actorsByPair.has(k))actorsByPair.set(k,new Set());
  actorsByPair.get(k).add(e.senderId);actorsByPair.get(k).add(e.receiverId);
 }
 for(const p of physicalCounts){
  const k=pair(p,scope,'PHYSICAL_COUNT');
  if(counted.has(k))throw Error('W02_RETURNABLES_DUPLICATE_PHYSICAL_COUNT');
  counted.add(k);
  if(!pairLast.has(k))throw Error('W02_RETURNABLES_UNKNOWN_PHYSICAL_PAIR');
  uniqueProof(p.countEvidenceRef,'COUNT_EVIDENCE');
  uniqueProof(p.witnessEvidenceRef,'WITNESS_EVIDENCE');
  ref(p.countedBy,'COUNTER');ref(p.witnessedBy,'WITNESS');
  ref(p.stockSnapshotRef,'STOCK_SNAPSHOT');
  if(p.countedBy===p.witnessedBy||actorsByPair.get(k).has(p.countedBy)||
     actorsByPair.get(k).has(p.witnessedBy))
   block('W02_RETURNABLES_INDEPENDENT_PHYSICAL_COUNT_NOT_PROVED:'+k);
  const last=pairLast.get(k);
  if(qty(p.crates,'COUNT_CRATES')!==last.cratesOutstanding||
     qty(p.trays,'COUNT_TRAYS')!==last.traysOutstanding)
   block('W02_RETURNABLES_PHYSICAL_VS_LEDGER_DISCREPANCY:'+k);
 }
 return Object.freeze({status:blockers.length?'BLOCK':'REVIEW_READY_NOT_APPROVED',
  blockers:Object.freeze(blockers),sourceFieldIDs:provenance.fields,
  originalManualDeclarationsOnly:true,originalFormulaProven:false,
  checkedMovements:ledger.entries.length,physicalPairsChecked:counted.size,
  proposedReconciliationDigest:createHash('sha256').update(JSON.stringify({
   scope,events,sourceDeclarations,openingProofs,physicalCounts})).digest('hex'),
  syntheticOnly:true,sourceExecuted:false,signedOriginalEvidenceVerified:false,
  canonicalStockAuthorized:false,ownerPolicyAccepted:false,
  canPost:false,erpPosted:false,changesToLedger:0});
}
module.exports={assertSource,reviewReturnables};
