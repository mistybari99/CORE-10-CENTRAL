'use strict';
/* CORE-10 PaperOps: prototype-only source books for W-02 and C-02 -> R-01.
 * No credentials, network, storage, actual signatures, approvals or ERP writes.
 * Cash and returnable packaging sources must never be silently collapsed into sales close.
 */
const legacyChecks=require('./field-batch-001-checks.js');
const ID=/^[A-Za-z0-9][A-Za-z0-9._:-]{0,119}$/;
function id(x,label){
 if(typeof x!=='string'||!ID.test(x))throw Error('INVALID_'+label);
 return x;
}
function nonnegative(v,key,places=0){
 const s=typeof v==='number'&&Number.isFinite(v)?String(v):v;
 const re=places===0?/^\d+$/:new RegExp('^\\d+(?:\\.\\d{1,'+places+'})?$');
 if(typeof s!=='string'||!re.test(s))throw Error('INVALID_QUANTITY_OR_MONEY:'+key);
 const [whole,decimal='']=s.split('.');
 const n=Number(whole)*(10**places)+Number(decimal.padEnd(places,'0'));
 if(!Number.isSafeInteger(n))throw Error('UNSAFE_QUANTITY_OR_MONEY:'+key);
 return n;
}
const cents=(x,k)=>nonnegative(x,k,2);
const units=(x,k)=>nonnegative(x,k,0);
const fmt=n=>(n/100).toFixed(2);
function addition(a,b,label){
 if(!Number.isSafeInteger(a+b))throw Error('LEDGER_OVERFLOW:'+label);
 return a+b;
}
function checkScope(scope){
 if(!scope||scope.synthetic_only!==true||scope.tenantId!=='DEMO-TENANT-ISOLATED')
  throw Error('ONLY_SYNTHETIC_ISOLATED_LEDGER_INPUT');
 id(scope.businessId,'BUSINESS');
 if(!scope.businessId.startsWith('DEMO-'))throw Error('ONLY_DEMO_BUSINESS_ALLOWED');
 if(!Array.isArray(scope.sites)||!scope.sites.length||scope.sites.length>400)
  throw Error('INVALID_DEMO_SITE_SET');
 const sites=new Set();
 for(const x of scope.sites){id(x,'SITE');if(!x.startsWith('DEMO-')||sites.has(x))throw Error('BAD_DEMO_SITE_SCOPE');sites.add(x);}
 return sites;
}
function actors(row,first,second){
 id(row[first],first.toUpperCase());id(row[second],second.toUpperCase());
 if(row[first]===row[second])throw Error('INDEPENDENT_SIGNERS_REQUIRED');
 id(row.senderProofRef||row.preparedProofRef,'SENDER_PROOF');
 id(row.receiverProofRef||row.paidProofRef,'RECEIVER_PROOF');
}
function sameScope(row,scope,sites){
 if(row.tenantId!==scope.tenantId||row.businessId!==scope.businessId)
  throw Error('CROSS_TENANT_OR_BUSINESS_REFERENCE');
 if(!sites.has(row.siteId))throw Error('CROSS_SITE_OR_UNKNOWN_SITE');
}
function packagingLedger(data){
 const scope=data?.scope,sites=checkScope(scope),events=data?.events;
 if(!Array.isArray(events)||!events.length||events.length>400)throw Error('INVALID_PACKAGING_EVENTS');
 const seenIds=new Set(),sourceRefs=new Set(),buckets=new Map(),outstandingByOrigin=new Map();
 const blockers=[],lines=[];
 for(let i=0;i<events.length;i++){
  const e=events[i];if(!e||typeof e!=='object')throw Error('BAD_PACKAGING_EVENT');
  id(e.id,'PACK_EVENT');id(e.sourceRef,'SIGNED_SOURCE_REF');
  if(seenIds.has(e.id)||sourceRefs.has(e.sourceRef))throw Error('DUPLICATE_PACKAGING_EVENT_OR_CHALLAN');
  seenIds.add(e.id);sourceRefs.add(e.sourceRef);
  if(e.tenantId!==scope.tenantId||e.businessId!==scope.businessId)
   throw Error('CROSS_TENANT_OR_BUSINESS_REFERENCE');
  id(e.fromSiteId,'FROM_SITE');id(e.toSiteId,'TO_SITE');
  if(!sites.has(e.fromSiteId)||!sites.has(e.toSiteId)||e.fromSiteId===e.toSiteId)
   throw Error('INVALID_PACKAGING_SITE_PAIR');
  actors(e,'senderId','receiverId');
  if(!['OPENING','ISSUE','RETURN'].includes(e.type))throw Error('INVALID_PACKAGING_MOVEMENT');
  if(e.type==='OPENING'&&e.sourceKind!=='SIGNED_LEGACY_OPENING_CARRY_FORWARD')
   throw Error('SIGNED_OPENING_PROVENANCE_REQUIRED');
  if(e.type!=='OPENING'&&e.sourceKind!=='SIGNED_W02_TRANSFER_OR_RETURN')
   throw Error('ORIGINAL_W02_CHALLAN_PROVENANCE_REQUIRED');
  const crates=units(e.crates,'crates'),trays=units(e.trays,'trays');
  if(crates===0&&trays===0)throw Error('EMPTY_PACKAGING_MOVEMENT');
  const pair=e.fromSiteId+'>'+e.toSiteId;
  const prev=buckets.get(pair)||{crates:0,trays:0};
  if(e.type==='OPENING'&&buckets.has(pair))throw Error('OPENING_ALREADY_RECORDED_FOR_PAIR');
  if(e.type==='OPENING'&&events.slice(0,i).some(x=>x.fromSiteId===e.fromSiteId&&x.toSiteId===e.toSiteId))
   throw Error('OPENING_MUST_PRECEDE_PAIR_MOVEMENTS');
  let next;
  if(e.type==='RETURN'){
   id(e.originalIssueId,'ORIGINAL_ISSUE_REF');
   const orig=outstandingByOrigin.get(e.originalIssueId);
   if(!orig||orig.pair!==pair)throw Error('UNKNOWN_OR_CROSS_PAIR_ORIGINAL_ISSUE');
   if(crates>orig.crates||trays>orig.trays)
    throw Error('RETURN_EXCEEDS_ISSUED_PACKAGING');
   if(crates>prev.crates||trays>prev.trays)
    throw Error('RETURN_EXCEEDS_PAIR_OUTSTANDING');
   next={crates:prev.crates-crates,trays:prev.trays-trays};
   orig.crates-=crates;orig.trays-=trays;
  }else{
   next={crates:addition(prev.crates,crates,'CRATES'),trays:addition(prev.trays,trays,'TRAYS')};
   outstandingByOrigin.set(e.id,{pair,crates,trays});
  }
  buckets.set(pair,next);
  if(!e.declaredOutstanding||typeof e.declaredOutstanding!=='object')
   throw Error('ORIGINAL_W02_OUTSTANDING_SOURCE_VALUES_REQUIRED');
  const declaredCrates=units(e.declaredOutstanding.crates,'declaredCrates');
  const declaredTrays=units(e.declaredOutstanding.trays,'declaredTrays');
  if(declaredCrates!==next.crates||declaredTrays!==next.trays)
   blockers.push('W02_ORIGINAL_OUTSTANDING_MISMATCH:'+e.id);
  lines.push(Object.freeze({id:e.id,type:e.type,sourceRef:e.sourceRef,pair,cratesDelta:e.type==='RETURN'?-crates:crates,
   traysDelta:e.type==='RETURN'?-trays:trays,cratesOutstanding:next.crates,traysOutstanding:next.trays,
   declaredOutstandingMatched:declaredCrates===next.crates&&declaredTrays===next.trays}));
 }
 return Object.freeze({sourceForms:['W-02'],status:blockers.length?'BLOCK':'REVIEW_READY_NOT_APPROVED',
  blockers:Object.freeze(blockers),entries:Object.freeze(lines),balances:Object.freeze([...buckets].map(([pair,x])=>({pair,...x}))),
  syntheticOnly:true,erpPosted:false,signaturesPhysicallyVerified:false,sourceParityCertified:false,ownerAccepted:false});
}
function expenseCashbookReconcile(data){
 const scope=data?.scope,sites=checkScope(scope);
 const vouchers=data?.vouchers,book=data?.cashbookRows,close=data?.dailyClose;
 if(!Array.isArray(vouchers)||!vouchers.length||vouchers.length>100||
  !Array.isArray(book)||!close||typeof close!=='object')throw Error('INVALID_SOURCE_CASH_BOOK');
 id(data.cashAccountId,'CASH_ACCOUNT');
 if(!data.cashAccountId.startsWith('DEMO-'))throw Error('ONLY_DEMO_CASH_ACCOUNT_ALLOWED');
 sameScope(close,scope,sites);
 id(close.dailyRef,'DAILY_R01_REF');id(close.cashbookRef,'CASHBOOK_REF');
 if(close.salesDrawerUntouched!==true)throw Error('SALES_DRAWER_AND_IMPREST_MUST_BE_SEPARATE');
 if(!Array.isArray(close.voucherRows))throw Error('R01_VOUCHER_SOURCE_ROWS_REQUIRED');
 const openingCash=cents(data.openingCashBDT,'openingCash');
 const openingReceipts=cents(data.openingReceiptsBDT,'openingReceipts');
 const fixedImprest=cents(data.approvedImprestBDT,'approvedImprest');
 if(addition(openingCash,openingReceipts,'IMPREST_OPENING')!==fixedImprest)
  throw Error('OPENING_IMPREST_NOT_BALANCED');
 const blockers=[],voucherMap=new Map();
 const proofRefs=new Set();
 let runningExpense=0,receiptTotal=openingReceipts;
 for(let i=0;i<vouchers.length;i++){
  const v=vouchers[i];sameScope(v,scope,sites);
  id(v.id,'VOUCHER_REF');
  if(voucherMap.has(v.id))throw Error('DUPLICATE_EXPENSE_SOURCE_VOUCHER');
  id(v.sheetRef,'SHOWROOM_R01_SHEET_REF');
  if(v.sheetRef!==close.dailyRef||v.siteId!==close.siteId)
   throw Error('VOUCHER_NOT_LINKED_TO_R01_DAILY_SOURCE');
  if(v.payMode!=='cash')blockers.push('NONCASH_EXPENSE_BRANCH_NOT_YET_PROVEN:'+v.id);
  if(v.cashAccountId!==data.cashAccountId)
   throw Error('VOUCHER_CASH_ACCOUNT_SCOPE_MISMATCH');
  actors({senderId:v.preparedBy,receiverId:v.paidBy,
   senderProofRef:v.preparedProofRef,receiverProofRef:v.paidProofRef},'senderId','receiverId');
  if(!Array.isArray(v.lines)||!v.lines.length||v.lines.length>50)
   throw Error('MISSING_VOUCHER_LINES');
  let sum=0;
  for(const [j,line] of v.lines.entries()){
   if(!line||typeof line.head!=='string'||!line.head.trim()||
    typeof line.paidTo!=='string'||!line.paidTo.trim())
    throw Error('EXPENSE_IDENTITY_MISSING');
   const amount=cents(line.amountBDT,'voucherLineAmount');
   if(amount===0)throw Error('ZERO_AMOUNT_VOUCHER_LINE');
   if(!['yes','no'].includes(line.receipt))throw Error('RECEIPT_STATUS_UNPROVEN');
   if(line.receipt==='yes'){
    id(line.receiptRef,'RECEIPT_PROOF');
    if(proofRefs.has(line.receiptRef))throw Error('DUPLICATE_RECEIPT_PROOF_REFERENCE');
    proofRefs.add(line.receiptRef);
   }
   sum=addition(sum,amount,'VOUCHER_LINES');
  }
  runningExpense=addition(runningExpense,sum,'DAILY_EXPENSE');
  receiptTotal=addition(receiptTotal,sum,'IMPREST_RECEIPT_EVIDENCE');
  const afterCash=openingCash-runningExpense;
  if(afterCash<0)throw Error('SOURCE_IMPREST_CASH_EXHAUSTED');
  if(cents(v.cashNowBDT,'vCashNow')!==afterCash)
   blockers.push('C02_VOUCHER_CASH_SNAPSHOT_MISMATCH:'+v.id);
  if(cents(v.receiptsTotalBDT,'vReceiptsTotal')!==receiptTotal)
   blockers.push('C02_VOUCHER_RECEIPTS_SNAPSHOT_MISMATCH:'+v.id);
  const proof=legacyChecks.expenseVoucher({
   voucherRef:v.id,sheetNo:v.sheetRef,preparedBy:v.preparedBy,paidBy:v.paidBy,
   drawerUntouched:v.drawerUntouched,payMode:v.payMode,
   moneyAccountId:v.cashAccountId,accountProofRef:v.cashAccountProofRef,
   approvedExpenseMax:v.approvedExpenseMax,expenseLimitPolicyRef:v.expenseLimitPolicyRef,
   approvedImprest:data.approvedImprestBDT,imprestPolicyRef:data.imprestPolicyRef,
   cashNow:v.cashNowBDT,receiptsTotal:v.receiptsTotalBDT,
   noReceiptReason:v.noReceiptReason,approvedBy:v.approvedBy,approvalRef:v.approvalRef,
   lines:v.lines.map(line=>({head:line.head,to:line.paidTo,receipt:line.receipt,
     receiptRef:line.receiptRef,amount:line.amountBDT}))
  });
  if(proof.status!=='REVIEW_READY_NOT_APPROVED')
   blockers.push(...proof.blockers.map(x=>'C02:'+v.id+':'+x));
  voucherMap.set(v.id,{amount:sum,receiptEvery:v.lines.every(x=>x.receipt==='yes'),siteId:v.siteId});
 }
 if(!book.length||book.length!==vouchers.length)
  blockers.push('CASHBOOK_VOUCHER_ROW_COUNT_MISMATCH');
 const seenBook=new Set(),seenBookedSource=new Set();
 let booked=0;
 for(const e of book){
  sameScope(e,scope,sites);
  if(e.siteId!==close.siteId)throw Error('CROSS_SITE_CASHBOOK_ROW');
  id(e.id,'CASHBOOK_ENTRY');id(e.sourceVoucherId,'CASHBOOK_SOURCE_VOUCHER');
  if(seenBook.has(e.id)||seenBookedSource.has(e.sourceVoucherId))
   throw Error('DUPLICATE_CASHBOOK_POSTING_OR_SOURCE');
  seenBook.add(e.id);seenBookedSource.add(e.sourceVoucherId);
  const v=voucherMap.get(e.sourceVoucherId);
  if(!v)throw Error('UNBACKED_CASHBOOK_EXPENSE_SOURCE');
  if(e.accountId!==data.cashAccountId||e.direction!=='OUT'||e.cashbookRef!==close.cashbookRef)
   throw Error('UNAPPROVED_OR_MISMATCHED_CASHBOOK_REFERENCE');
  id(e.enteredBy,'BOOK_ENTERER');id(e.checkedBy,'BOOK_CHECKER');
  if(e.enteredBy===e.checkedBy)throw Error('CASHBOOK_INDEPENDENT_CHECKER_REQUIRED');
  const amount=cents(e.amountBDT,'cashbookAmount');
  booked=addition(booked,amount,'BOOK_EXPENSE');
  if(amount!==v.amount)blockers.push('CASHBOOK_VOUCHER_AMOUNT_MISMATCH:'+vouchers.find(x=>x.id===e.sourceVoucherId).id);
 }
 const seenClose=new Set();
 let closeSum=0;
 for(const row of close.voucherRows){
  id(row.voucherRef,'R01_VOUCHER_REF');
  if(seenClose.has(row.voucherRef))throw Error('DUPLICATE_R01_VOUCHER_REFERENCE');
  seenClose.add(row.voucherRef);
  const source=voucherMap.get(row.voucherRef);
  if(!source)throw Error('R01_VOUCHER_WITHOUT_C02_SOURCE');
  const amount=cents(row.amountBDT,'R01VoucherAmount');
  closeSum=addition(closeSum,amount,'R01_EXPENSE_TOTAL');
  if(amount!==source.amount)blockers.push('R01_C02_VOUCHER_TOTAL_MISMATCH:'+row.voucherRef);
  if(row.receiptsAttached!==source.receiptEvery)
   blockers.push('R01_C02_RECEIPT_PROOF_MISMATCH:'+row.voucherRef);
 }
 if(seenClose.size!==voucherMap.size||seenBookedSource.size!==voucherMap.size)
  blockers.push('SOURCE_VOUCHER_MISSING_FROM_DAILY_OR_BOOK');
 if(cents(close.vTotalBDT,'R01ExpenseTotal')!==closeSum||closeSum!==runningExpense)
  blockers.push('R01_DAILY_TOTAL_EXPENSE_MISMATCH');
 if(booked!==runningExpense)blockers.push('DAILY_CASHBOOK_TOTAL_MISMATCH');
 const expectedClosingCash=openingCash-runningExpense,expectedReceipts=receiptTotal;
 if(cents(close.imprestCashNowBDT,'closeCashNow')!==expectedClosingCash||
  cents(close.imprestReceiptsTotalBDT,'closeReceipts')!==expectedReceipts)
  blockers.push('C02_R01_IMPREST_CONTINUITY_MISMATCH');
 if(addition(expectedClosingCash,expectedReceipts,'FIXED_IMPREST')!==fixedImprest)
  blockers.push('FIXED_IMPREST_RECONCILIATION_MISMATCH');
 return Object.freeze({sourceForms:['C-02','R-01','C-01'],status:blockers.length?'BLOCK':'REVIEW_READY_NOT_APPROVED',
  blockers:Object.freeze(blockers),voucherCount:voucherMap.size,
  totals:Object.freeze({originalVoucherBDT:fmt(runningExpense),r01ExpenseBDT:fmt(closeSum),
   cashbookExpenseBDT:fmt(booked),imprestCashNowBDT:fmt(expectedClosingCash),
   imprestReceiptsTotalBDT:fmt(expectedReceipts),fixedImprestBDT:fmt(fixedImprest)}),
  syntheticOnly:true,erpPosted:false,actualCashCountCertified:false,
  sourceParityCertified:false,ownerAccepted:false});
}
module.exports=Object.freeze({packagingLedger,expenseCashbookReconcile});
