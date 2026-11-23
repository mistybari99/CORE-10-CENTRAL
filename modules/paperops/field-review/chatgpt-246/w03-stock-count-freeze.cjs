'use strict';
/* W-03 counted stock is NOT an inventory adjustment. Source-anchored,
 * stricter synthetic freeze/movement/valuation reconciliation only.
 * Old W-03 calc(e) flags count_variance / count_variance_small,
 * counter_is_storekeeper and same_witness; no signed Stock RPC here.
 */
const crypto=require('node:crypto');
const source=require('./source-helper-conditions.cjs');
const manifest=require('../ownership-246-1000.json');
const KEYS=['start_time','end_time','counted_by','storekeeper','kind','movement',
 'movement_detail','item','unit','count','book','var','reason','witness'].map(k=>'W-03:'+k);
const owned=new Set([...manifest.lane_B_chatgpt.critical_86_keys,
 ...manifest.lane_B_chatgpt.mapped_150_keys,...manifest.lane_B_chatgpt.reserved_next_10_keys]);
if(KEYS.some(x=>!owned.has(x)))throw Error('W03_FIELD_OWNER_DRIFT');
const ID=/^[A-Za-z0-9][A-Za-z0-9._:/-]{0,119}$/;
function id(v,label){if(typeof v!=='string'||!ID.test(v))throw Error('W03_INVALID_ID:'+label);return v;}
function units(v,label,places=4){
 const s=typeof v==='number'&&Number.isFinite(v)?String(v):v;
 if(typeof s!=='string'||!(/^(?:0|[1-9]\d*)(?:\.\d{1,4})?$/).test(s))
  throw Error('W03_INVALID_QUANTITY:'+label);
 const [a,b='']=s.split('.');
 const n=BigInt(a)*10000n+BigInt((b.padEnd(4,'0')||'0'));
 if(n>BigInt(Number.MAX_SAFE_INTEGER))throw Error('W03_QUANTITY_OVERFLOW:'+label);
 return n;
}
function money(v,label){
 const s=typeof v==='number'&&Number.isFinite(v)?String(v):v;
 if(typeof s!=='string'||!(/^(?:0|[1-9]\d*)(?:\.\d{1,2})?$/).test(s))
  throw Error('W03_INVALID_MONEY:'+label);
 const [a,b='']=s.split('.');const n=BigInt(a)*100n+BigInt(b.padEnd(2,'0')||'0');
 if(n>BigInt(Number.MAX_SAFE_INTEGER))throw Error('W03_MONEY_OVERFLOW:'+label);
 return n;
}
function fmt(n,places=4){
 const abs=n<0n?-n:n,scale=10n**BigInt(places);
 return (n<0n?'-':'')+String(abs/scale)+'.'+String(abs%scale).padStart(places,'0');
}
function assertSource(){
 const s=source.readFrozen('forms');source.verifyEvidence();
 const start=s.indexOf('e.forms["W-03"]='),end=s.indexOf('e.forms[',start+1);
 if(start<0)throw Error('W03_ORIGINAL_FORM_MISSING');
 const part=s.slice(start,end<0?s.length:end);
 for(const x of [
  '"movement",t("গণনার সময় মালামাল প্রাপ্তি বা ইস্যু হয়েছে?"',
  'show:e=>"yes"===e.d.movement,req:e=>"yes"===e.d.movement',
  '"The storekeeper must not count; someone else does.',
  '"count_variance","red"','"count_variance_small","yellow"',
  '"counter_is_storekeeper","red"','"same_witness","red"',
  'r(t.count)-r(t.book)'])
  if(!part.includes(x))throw Error('W03_SOURCE_DRIFT:'+x);
 return {blob:source.PIN.forms,oldExecuted:false};
}
function scope(record,s,label){
 if(!record||record.tenantId!==s.tenantId||record.businessId!==s.businessId||
    record.siteId!==s.siteId)throw Error('W03_CROSS_TENANT_BUSINESS_SITE:'+label);
}
function stamp(v,label){
 if(typeof v!=='string'||!/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?Z$/.test(v)||
    !Number.isFinite(Date.parse(v)))throw Error('W03_BAD_TIMESTAMP:'+label);
 return Date.parse(v);
}
function reconcileStockCount({synthetic_only,scope:s,session,policy,bookRows,physicalRows,movements}={}){
 const pinned=assertSource();
 if(synthetic_only!==true||!s||![s.tenantId,s.businessId,s.siteId].every(
  v=>typeof v==='string'&&v.startsWith('DEMO-')&&ID.test(v)))
  throw Error('W03_SYNTHETIC_SCOPE_ONLY');
 scope(session,s,'SESSION');
 if(!Array.isArray(bookRows)||!bookRows.length||bookRows.length>300||
    !Array.isArray(physicalRows)||!physicalRows.length||physicalRows.length>300||
    !Array.isArray(movements)||movements.length>500||!policy)
  throw Error('W03_SOURCE_COUNTS_BOOK_MOVEMENTS_POLICY_REQUIRED');
 const blockers=[],flag=x=>{if(!blockers.includes(x))blockers.push(x);};
 const seen=new Set(),unique=(v,label)=>{
  id(v,label);if(seen.has(v))throw Error('W03_DUPLICATE_OR_REPLAY_SOURCE_REF:'+label);
  seen.add(v);return v;
 };
 unique(session.countSheetRef,'COUNT_SHEET');
 unique(session.ledgerSnapshotRef,'LEDGER_SNAPSHOT');
 unique(session.freezeProofRef,'FREEZE_PROOF');
 unique(policy.controlRef,'CONTROL_VERSION');
 const start=stamp(session.startedAt,'START'),end=stamp(session.endedAt,'END');
 if(end<=start)throw Error('W03_INVALID_COUNT_WINDOW');
 const counter=id(session.counterActor,'COUNTER'),keeper=id(session.storekeeperActor,'STOREKEEPER'),
   witness=id(session.witnessActor,'WITNESS');
 if(counter===keeper)flag('W03_COUNTER_EQUALS_STOREKEEPER');
 if(counter===witness||keeper===witness)flag('W03_INDEPENDENT_WITNESS_REQUIRED');
 if(session.freezeConfirmed!==true)flag('W03_FREEZE_NOT_ATTESTED');
 if(session.movementDeclared!=='no'&&session.movementDeclared!=='yes')
  flag('W03_MOVEMENT_DECLARATION_UNKNOWN');
 if(session.movementDeclared==='yes'&&
    (typeof session.movementDetail!=='string'||!session.movementDetail.trim()))
  flag('W03_MOVEMENT_SOURCE_DETAILS_REQUIRED');
 if(session.movementDeclared==='no'&&movements.length)
  flag('W03_DECLARED_NO_MOVEMENT_CONTRADICTS_EVENTS');
 if(session.movementDeclared==='yes'&&!movements.length)
  flag('W03_DECLARED_MOVEMENT_HAS_NO_REFERENCES');
 if(movements.length)flag('W03_FREEZE_BREACH_REQUIRES_REVIEW');
 const tol=policy.tolerancePct===undefined?null:money(policy.tolerancePct,'PCT'),
   valueLimit=policy.toleranceValueBDT===undefined?null:money(policy.toleranceValueBDT,'VALUE');
 if(tol===null&&valueLimit===null)flag('W03_TOLERANCE_CONTROL_VALUES_MISSING');
 const book=new Map(),physical=new Map(),delta=new Map(),movSeen=new Set();
 const key=x=>id(x.itemId,'ITEM')+'|'+id(x.lotId,'LOT');
 for(const row of bookRows){
  scope(row,s,'BOOK');
  const k=key(row);if(book.has(k))throw Error('W03_DUPLICATE_BOOK_LOT');
  unique(row.sourceRef,'BOOK_ROW');
  if(row.ledgerSnapshotRef!==session.ledgerSnapshotRef)
   throw Error('W03_BOOK_REVISION_SOURCE_MISMATCH');
  book.set(k,{qty:units(row.quantity,'BOOK'),sellPrice:money(row.sellPriceBDT,'PRICE'),
    unit:id(row.unitId,'UNIT'),ref:row.sourceRef});
 }
 for(const row of physicalRows){
  scope(row,s,'PHYSICAL');
  const k=key(row);if(physical.has(k))throw Error('W03_DUPLICATE_PHYSICAL_LOT');
  unique(row.sourceRef,'PHYSICAL_ROW');
  if(row.counterActor!==counter)flag('W03_ROW_COUNTER_ACTOR_NOT_SESSION_COUNTER');
  physical.set(k,{qty:units(row.quantity,'COUNT'),unit:id(row.unitId,'UNIT'),ref:row.sourceRef,
    reason:row.varianceReason});
 }
 if(physical.size!==book.size||[...book.keys()].some(k=>!physical.has(k)))
  throw Error('W03_COUNT_AND_BOOK_LOT_SET_MISMATCH');
 for(const row of movements){
  scope(row,s,'MOVEMENT');
  const k=key(row);
  if(!book.has(k))throw Error('W03_MOVEMENT_LOT_NOT_IN_BOOK');
  unique(row.sourceRef,'STOCK_MOVEMENT');
  if(movSeen.has(row.sourceRef))throw Error('W03_DUPLICATE_MOVEMENT');
  movSeen.add(row.sourceRef);
  if(row.ledgerSnapshotRef!==session.ledgerSnapshotRef)
   throw Error('W03_MOVEMENT_STALE_LEDGER_SNAPSHOT');
  if(row.kind!=='RECEIVE'&&row.kind!=='ISSUE')
   throw Error('W03_UNSUPPORTED_MOVEMENT_TYPE');
  const t=stamp(row.occurredAt,'MOVEMENT');
  if(t<start||t>end)throw Error('W03_MOVEMENT_OUTSIDE_COUNT_WINDOW');
  id(row.actor,'MOVEMENT_ACTOR');unique(row.evidenceRef,'MOVEMENT_EVIDENCE');
  const qty=units(row.quantity,'MOVEMENT');
  if(qty===0n)throw Error('W03_ZERO_MOVEMENT');
  delta.set(k,(delta.get(k)||0n)+(row.kind==='RECEIVE'?qty:-qty));
 }
 const results=[];let warnings=0;
 for(const [k,b] of book){
  const p=physical.get(k);
  if(b.unit!==p.unit)throw Error('W03_BOOK_COUNT_UOM_MISMATCH');
  const normalized=b.qty+(delta.get(k)||0n);
  if(normalized<0n)throw Error('W03_MOVEMENTS_EXCEED_BOOK_QUANTITY');
  const variance=p.qty-normalized,abs=variance<0n?-variance:variance;
  const approximateValue=(abs*b.sellPrice+9999n)/10000n;
  const insidePct=tol!==null&&normalized>0n&&abs*10000n<=normalized*tol;
  const insideAmt=valueLimit!==null&&approximateValue<=valueLimit;
  const within=variance===0n||insidePct||insideAmt;
  if(variance!==0n){
   warnings++;
   flag(within?'W03_VARIANCE_WITHIN_CONTROL_NEEDS_REVIEW':'W03_VARIANCE_OUTSIDE_CONTROL');
   if(typeof p.reason!=='string'||!p.reason.trim())flag('W03_VARIANCE_REASON_REQUIRED');
   flag('W03_ADJUSTMENT_REQUIRES_INDEPENDENT_AUTHORIZATION');
  }
  results.push({itemLot:k,bookStart:fmt(b.qty),movementDelta:fmt(delta.get(k)||0n),
   bookAtCount:fmt(normalized),physicalCount:fmt(p.qty),variance:fmt(variance),
   estimatedVarianceValueBDT:fmt(approximateValue,2),withinControlCandidate:within});
 }
 const lineage={scope:s,session,policy,bookRows,physicalRows,movements};
 return Object.freeze({source_ids:KEYS.slice(),status:blockers.length?'BLOCK':'SOURCE_RECONCILED_NOT_APPROVED',
  blockers:Object.freeze(blockers),evidence:Object.freeze({rows:results,
   movementCount:movements.length,varianceRows:warnings,
   sourceDigest:crypto.createHash('sha256').update(JSON.stringify(lineage)).digest('hex'),
   frozenFormsBlob:pinned.blob}),
  legacyRuleParityCertified:false,syntheticOnly:true,oldExecuted:false,
  sourceSignaturesVerified:false,canonicalStockReadVerified:false,
  canonicalStockAdjustmentPosted:false,approvalAuditVerified:false,
  ownerAccepted:false,canPost:false});
}
module.exports={reconcileStockCount,assertSource};
