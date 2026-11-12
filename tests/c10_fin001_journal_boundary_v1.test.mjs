import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {
  FinanceGateError,assertTrustedAccountingContext,parseMoneyMinor,minorToMoney,
  prepareJournalProposal,prepareReversalProposal,reconcileTrialBalance,
  postJournal,markAsPosted
} from '../internal/enterprise-finance/c10_fin001_journal_boundary_v1.mjs';

const sha=(v)=>createHash('sha256').update(JSON.stringify(v)).digest('hex');
const context=()=>({
  actorId:'actor-fin',tenantId:'tenant1',businessId:'biz1',legalEntityId:'entity1',
  authenticated:true,resolvedBy:'server_verified_signed_actor',
  effectiveGrantChecked:true,revocationChecked:true,
  effectiveRights:['finance.propose','finance.reverse.propose','finance.report'],
  grantVersion:'gv4'
});
const period=()=>({
  id:'period202611',tenantId:'tenant1',businessId:'biz1',legalEntityId:'entity1',
  authoritative:true,startDay:'2026-11-01',endDayExclusive:'2026-12-01',
  status:'OPEN',closeVersion:'cv2',bookedOn:'2026-11-12'
});
const source=()=>({
  type:'sales_invoice',sourceId:'inv100',sourceVersion:'3',
  sourceHash:'a'.repeat(64),policyVersion:'policy2',makerId:'maker1',
  bookedOn:'2026-11-12',currency:'BDT',authoritative:true,
  tenantId:'tenant1',businessId:'biz1',legalEntityId:'entity1'
});
const approval=()=>({
  tenantId:'tenant1',businessId:'biz1',legalEntityId:'entity1',
  verifiedByServer:true,status:'APPROVED',sourceId:'inv100',sourceVersion:'3',
  sourceHash:'a'.repeat(64),policyVersion:'policy2',
  approverId:'reviewer7',approvalReceiptId:'rec100'
});
const accounts=()=>['cash','sales','receivable'].map(id=>({
  id,tenantId:'tenant1',businessId:'biz1',legalEntityId:'entity1',
  authoritative:true,currency:'BDT',status:'POSTABLE',isControlAccount:false
}));
const lines=()=>[
  {accountId:'cash',side:'DEBIT',amount:'125.75'},
  {accountId:'sales',side:'CREDIT',amount:'125.75'}
];
const args=()=>({
  context:context(),source:source(),period:period(),approval:approval(),
  accounts:accounts(),lines:lines(),certifiedSources:new Set(['sales_invoice']),
  requestKey:'invoicereq001'
});
const err=(code,fn)=>assert.throws(fn,e=>e instanceof FinanceGateError && e.code===code);

test('valid signed source produces immutable, deterministic balanced proposal, NEVER posted',()=>{
  const input=args(), p=prepareJournalProposal(input), q=prepareJournalProposal(input);
  assert.equal(p.state,'VALIDATED_NOT_POSTED');
  assert.equal(p.canPost,false);
  assert.equal(p.totalMinor,'12575');
  assert.equal(p.fingerprint,q.fingerprint);
  assert.equal(p.lines[0].amountMinor,'12575');
  assert.equal(Object.isFrozen(p),true);
  assert.equal(p.scope.legalEntityId,'entity1');
});
test('publishing/mark-posted is deliberately disabled until certified canonical adapter',()=>{
  err('FIN_CANONICAL_POSTING_ADAPTER_NOT_CONNECTED',()=>postJournal(args()));
  err('FIN_CANONICAL_RECEIPT_REQUIRED',()=>markAsPosted({status:'posted'}));
});
test('anonymous/forged or stale signed context fails',()=>{
  for (const change of [
    {authenticated:false},{resolvedBy:'browser'},{effectiveGrantChecked:false},
    {revocationChecked:false},{effectiveRights:[]},{grantVersion:null}
  ]) {
    const a=args(); Object.assign(a.context,change);
    assert.throws(()=>prepareJournalProposal(a),FinanceGateError);
  }
});
test('typed grant is necessary, not Owner label or client role',()=>{
  const a=args();a.context.role='OWNER';a.context.effectiveRights=['inventory.post'];
  err('FIN_SIGNED_CONTEXT_REQUIRED',()=>prepareJournalProposal(a));
});
test('invalid scope and malformed actor refused',()=>{
  const a=args();a.context.businessId='biz other';
  err('FIN_SCOPE_INVALID',()=>prepareJournalProposal(a));
});
test('invalid request keys and direct posting are blocked',()=>{
  for (const requestKey of ['k','<script>','',null,'a'.repeat(101)]) {
    const a=args();a.requestKey=requestKey;
    err('FIN_REQUEST_KEY_INVALID',()=>prepareJournalProposal(a));
  }
});
test('unknown or uncertified source cannot be promoted via UI',()=>{
  const a=args();a.certifiedSources=new Set();
  err('FIN_SOURCE_TYPE_NOT_CERTIFIED',()=>prepareJournalProposal(a));
});
test('source tenant/business/legal-entity mismatches fail',()=>{
  for(const f of ['tenantId','businessId','legalEntityId']){
    const a=args();a.source[f]='other';
    err('FIN_SOURCE_UNVERIFIED',()=>prepareJournalProposal(a));
  }
});
test('source must be server-authoritative',()=>{
  const a=args();a.source.authoritative=false;
  err('FIN_SOURCE_UNVERIFIED',()=>prepareJournalProposal(a));
});
test('source provenance hash, version and calendar day are validated',()=>{
  for (const change of [{sourceHash:'short'},{sourceVersion:''},{bookedOn:'2026-02-30'}]) {
    const a=args();Object.assign(a.source,change);
    assert.throws(()=>prepareJournalProposal(a),FinanceGateError);
  }
});
test('approval must match pinned source/version/hash/policy exactly',()=>{
  for(const change of [
    {sourceId:'different'},{sourceVersion:'2'},{sourceHash:'b'.repeat(64)},
    {policyVersion:'policy3'},{verifiedByServer:false},{status:'PENDING'},
    {businessId:'biz2'},{legalEntityId:'entity2'},{tenantId:'tenant2'}
  ]){
    const a=args();Object.assign(a.approval,change);
    err('FIN_APPROVAL_SOURCE_MISMATCH',()=>prepareJournalProposal(a));
  }
});
test('maker/checker separation is enforceable in the proposal contract',()=>{
  const a=args();a.approval.approverId='maker1';
  err('FIN_MAKER_CHECKER_VIOLATION',()=>prepareJournalProposal(a));
});
test('period is signed, in scope, OPEN and includes posting date',()=>{
  for(const patch of [
    {authoritative:false},{tenantId:'tenant2'},{status:'CLOSED'},
    {startDay:'2026-11-14'},{endDayExclusive:'2026-11-10'},
    {closeVersion:null}
  ]){
    const a=args();Object.assign(a.period,patch);
    assert.throws(()=>prepareJournalProposal(a),FinanceGateError);
  }
});
test('cross-month posting is not silently moved to a newer period',()=>{
  const a=args();a.source.bookedOn='2026-12-01';
  err('FIN_DATE_OUTSIDE_PERIOD',()=>prepareJournalProposal(a));
});
test('only approved BDT precision contract is accepted',()=>{
  for(const patch of [{currency:'USD'},{scale:3}]){
    const a=args();Object.assign(a,patch);
    err('FIN_UNAPPROVED_CURRENCY_POLICY',()=>prepareJournalProposal(a));
  }
});
test('all chart entries need exact tenant/business/legal scope and postable state',()=>{
  for(const change of [
    {tenantId:'other'},{businessId:'other'},{legalEntityId:'other'},
    {currency:'USD'},{status:'INACTIVE'},{authoritative:false},{isControlAccount:true}
  ]){
    const a=args();Object.assign(a.accounts[0],change);
    err('FIN_ACCOUNT_NOT_POSTABLE_IN_SCOPE',()=>prepareJournalProposal(a));
  }
});
test('unknown account and duplicate registry IDs rejected',()=>{
  const a=args();a.lines[0].accountId='arbitrary';
  err('FIN_ACCOUNT_NOT_POSTABLE_IN_SCOPE',()=>prepareJournalProposal(a));
  const b=args();b.accounts.push({...b.accounts[0]});
  err('FIN_ACCOUNT_DUPLICATE',()=>prepareJournalProposal(b));
});
test('journal requires at least two valid lines and balance',()=>{
  const a=args();a.lines=[a.lines[0]];
  err('FIN_LINES_COUNT_INVALID',()=>prepareJournalProposal(a));
  const b=args();b.lines[0].amount='125.74';
  err('FIN_JOURNAL_UNBALANCED',()=>prepareJournalProposal(b));
});
test('invalid signed amounts never float-round or overflow',()=>{
  for(const amt of ['-1.00','1e3','NaN',125.75,'1.234','.20','001.00','10000000000000.00','']){
    const a=args();a.lines[0].amount=amt;
    assert.throws(()=>prepareJournalProposal(a),FinanceGateError);
  }
  err('FIN_ZERO_LINE_FORBIDDEN',()=>{const a=args();a.lines[0].amount='0.00';return prepareJournalProposal(a);});
});
test('integer minor units preserve decimal edges with exact BigInt arithmetic',()=>{
  assert.equal(parseMoneyMinor('0.01'),1n);
  assert.equal(parseMoneyMinor('125.75'),12575n);
  assert.equal(minorToMoney(-12575n),'-125.75');
  assert.equal(minorToMoney(1n),'0.01');
  assert.equal(minorToMoney(parseMoneyMinor('9999999999999.99')),'9999999999999.99');
});
test('unknown line side and unbounded batch rejected',()=>{
  const a=args();a.lines[0].side='ANY';
  err('FIN_LINE_SIDE_INVALID',()=>prepareJournalProposal(a));
  const b=args();b.lines=Array.from({length:201},()=>lines()[0]);
  err('FIN_LINES_COUNT_INVALID',()=>prepareJournalProposal(b));
});
const originalPosted=()=>{
  const p=prepareJournalProposal(args());
  return {...p,...p.scope,journalId:'journal100',status:'POSTED',
    verifiedCanonicalRead:true,reversed:false};
};
const reversalArgs=()=>{
  const a=args(),original=originalPosted(),p=period();
  const reason='Duplicate invoice source correction';
  const sourceId='reverse:'+original.journalId;
  const hash=sha({journalId:original.journalId,fingerprint:original.fingerprint,reason});
  return {
    context:a.context,original,period:p,accounts:a.accounts,
    approval:{...a.approval,sourceId,sourceVersion:'1',sourceHash:hash},
    requestKey:'reverseinvoice001',reason,
    certifiedSources:new Set(['journal_reversal'])
  };
};
test('independent verified original generates exact compensating reversal, never auto-posts',()=>{
  const a=reversalArgs(),rev=prepareReversalProposal(a);
  assert.equal(rev.state,'VALIDATED_REVERSAL_NOT_POSTED');
  assert.equal(rev.canPost,false);
  assert.equal(rev.totalMinor,'12575');
  assert.equal(rev.reversesJournalId,'journal100');
  assert.equal(rev.lines[0].side,'CREDIT');
  assert.equal(rev.lines[1].side,'DEBIT');
});
test('reversal cannot fabricate original, conceal prior reversal or omit reason',()=>{
  const x=reversalArgs();x.original.verifiedCanonicalRead=false;
  err('FIN_ORIGINAL_CANONICAL_RECEIPT_REQUIRED',()=>prepareReversalProposal(x));
  const y=reversalArgs();y.original.reversed=true;
  err('FIN_ORIGINAL_ALREADY_REVERSED',()=>prepareReversalProposal(y));
  const z=reversalArgs();z.reason='oops';
  err('FIN_REVERSAL_REASON_REQUIRED',()=>prepareReversalProposal(z));
});
test('reversal has its own independent pinned maker/checker approval',()=>{
  const a=reversalArgs();a.approval.sourceHash='f'.repeat(64);
  err('FIN_APPROVAL_SOURCE_MISMATCH',()=>prepareReversalProposal(a));
  const b=reversalArgs();b.approval.approverId='maker1';
  err('FIN_MAKER_CHECKER_VIOLATION',()=>prepareReversalProposal(b));
});
const trialArgs=()=>{
  const a=args();
  return {
    context:a.context,period:a.period,accounts:a.accounts,
    entries:[{
      journalId:'j100',status:'POSTED',verifiedCanonicalRead:true,
      tenantId:'tenant1',businessId:'biz1',legalEntityId:'entity1',periodId:'period202611',
      lines:[{accountId:'cash',side:'DEBIT',amount:'100.00'},
        {accountId:'sales',side:'CREDIT',amount:'100.00'}]
    }],
    snapshot:{
      snapshotId:'snap01',verifiedByServer:true,complete:true,canonicalJournalReadback:true,
      tenantId:'tenant1',businessId:'biz1',legalEntityId:'entity1',periodId:'period202611'
    }
  };
};
test('complete signed readback yields balanced trial evidence, not financial-statement certification',()=>{
  const r=reconcileTrialBalance(trialArgs());
  assert.equal(r.journalCount,1);
  assert.equal(r.totalDebits,'100.00');
  assert.equal(r.totalCredits,'100.00');
  assert.match(r.status,/NOT_CERTIFIED/);
  assert.equal(r.accounts.find(a=>a.accountId==='cash').netDebit,'100.00');
});
test('partial page, unverified scope or forged signed snapshot denied',()=>{
  for(const change of [{complete:false},{verifiedByServer:false},{canonicalJournalReadback:false},
    {businessId:'other'},{periodId:'other'}]){
    const a=trialArgs();Object.assign(a.snapshot,change);
    err('FIN_SIGNED_SNAPSHOT_REQUIRED',()=>reconcileTrialBalance(a));
  }
});
test('duplicate journal IDs and foreign business rows are refused',()=>{
  const x=trialArgs();x.entries.push({...x.entries[0]});
  err('FIN_DUPLICATE_JOURNAL',()=>reconcileTrialBalance(x));
  const y=trialArgs();y.entries[0].businessId='other';
  err('FIN_UNVERIFIED_REPORT_ENTRY',()=>reconcileTrialBalance(y));
});
test('unbalanced canonical journal or unverified entry is refused',()=>{
  const x=trialArgs();x.entries[0].lines[1].amount='99.99';
  err('FIN_JOURNAL_UNBALANCED',()=>reconcileTrialBalance(x));
  const y=trialArgs();y.entries[0].verifiedCanonicalRead=false;
  err('FIN_UNVERIFIED_REPORT_ENTRY',()=>reconcileTrialBalance(y));
});
test('finance.report is separately required from finance.propose',()=>{
  const a=trialArgs();a.context.effectiveRights=['finance.propose'];
  err('FIN_SIGNED_CONTEXT_REQUIRED',()=>reconcileTrialBalance(a));
});
