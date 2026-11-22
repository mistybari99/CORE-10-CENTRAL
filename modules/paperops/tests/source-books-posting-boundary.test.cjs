'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {planPostingCandidates,simulateDraftQueue,postToERP,validateRow}=
 require('../source-books-posting-boundary.cjs');
const sourceFixture=require('../source-books-fixture.json');
const scoped=require('../source-books-posting-boundary-fixture.json');
const clone=structuredClone;
function plan(overrides={}){
 return planPostingCandidates({syntheticFixture:sourceFixture,
  build01Context:scoped.build01Context,authenticatedActorUid:scoped.authenticatedActorUid,
  selection:scoped.selection,siteBindings:scoped.siteBindings,...overrides});
}
function mutateScope(fn){
 const original=clone(scoped);
 fn(original);
 return plan({build01Context:original.build01Context,
  authenticatedActorUid:original.authenticatedActorUid,
  selection:original.selection,siteBindings:original.siteBindings});
}
function mutateSource(fn){
 const x=clone(sourceFixture);fn(x);
 return plan({syntheticFixture:x});
}
test('the two reconciled source books compile 7 scoped draft proposals without any real ERP capability',()=>{
 const p=plan();
 assert.equal(p.status,'POSTING_PROPOSALS_DRAFT_NEVER_AUTHORIZE');
 assert.equal(p.proposals.length,7);
 assert.equal(p.proposals.filter(x=>x.kind==='FINANCE_EXPENSE_DRAFT').length,2);
 assert.equal(p.proposals.filter(x=>x.kind==='RETURNABLE_PACKAGING_DRAFT').length,5);
 assert.equal(p.sourceProofs.originalVoucherTotalBDT,'170.00');
 assert.equal(p.sourceProofs.r01ExpenseTotalBDT,'170.00');
 assert.equal(p.sourceProofs.cashbookExpenseTotalBDT,'170.00');
 assert.equal(p.businessScope.tenantId,9801);
 assert.equal(p.businessScope.businessId,9810);
 assert.equal(p.businessScope.actorUid,scoped.authenticatedActorUid);
 assert.equal(p.businessScope.serverPermissionChecked,false);
 assert.equal(p.realAuthSignedByBackend,false);
 assert.equal(p.realFinancePermissionChecked,false);
 assert.equal(p.realWarehousePermissionChecked,false);
 assert.equal(p.realChartAccountsMapped,false);
 assert.equal(p.posted,false);
 assert.equal(p.erpReady,false);
 assert.equal(p.ownerAccepted,false);
 assert.throws(()=>postToERP(p),/REAL_ERP_POSTING_NOT_IMPLEMENTED/);
});
test('finance 2-sided source journal proposals debit original lines, credit imprest once, not again on R-01',()=>{
 const p=plan(),rows=p.proposals.filter(x=>x.kind==='FINANCE_EXPENSE_DRAFT');
 assert.equal(rows[0].payload.debit.length,2);
 assert.deepEqual(rows[0].payload.debit.map(x=>x.amountBDT),['70.00','50.00']);
 assert.deepEqual(rows[0].payload.credit.map(x=>x.amountBDT),['120.00']);
 assert.equal(rows[0].payload.noDuplicateR01Posting,true);
 assert.equal(rows[0].payload.sourceR01Ref,'DEMO-R01-20261122');
 assert.equal(rows[0].payload.proposedSiteId,98102);
 assert.equal(rows[0].payload.accountingPostApproved,undefined);
 assert.equal(rows[0].accountingPostApproved,false);
 assert.equal(rows[0].payload.requiresRealAccountMapping,true);
 assert.equal(rows[1].payload.debit.length,1);
 assert.equal(rows[1].payload.credit[0].amountBDT,'50.00');
 for(const row of rows)validateRow(row);
});
test('five scoped packaging draft movements preserve W-02 original references, signed-copy placeholders and outstanding',()=>{
 const p=plan(),rows=p.proposals.filter(x=>x.kind==='RETURNABLE_PACKAGING_DRAFT');
 assert.deepEqual(rows.map(x=>x.payload.cratesDelta),[2,5,-2,1,-3]);
 assert.deepEqual(rows.map(x=>x.payload.declaredCratesDue),[2,7,5,6,3]);
 assert.deepEqual(rows.map(x=>x.payload.declaredTraysDue),[4,12,9,11,6]);
 assert.equal(rows[2].payload.originalIssueId,'DEMO-PK-ISS1');
 assert.ok(rows.every(x=>x.payload.siteFromId===98101&&x.payload.siteToId===98102));
 assert.ok(rows.every(x=>x.warehousePostApproved===false));
 assert.ok(rows.every(x=>x.payload.needsRealSignedTransferAndReturnLedger===true));
 for(const row of rows)validateRow(row);
});
test('in-memory draft replay is idempotent, never writes, and prior state is not mutated',()=>{
 const p=plan();
 const first=simulateDraftQueue([],p);
 assert.equal(first.status,'LOCAL_MEMORY_DRAFT_ONLY_NO_POST');
 assert.equal(first.records.length,7);
 assert.equal(first.newCount,7);
 assert.equal(first.replayed,0);
 assert.equal(first.posted,false);
 assert.equal(first.authorizationVerified,false);
 const next=simulateDraftQueue(first.records,p);
 assert.equal(next.records.length,7);
 assert.equal(next.newCount,0);
 assert.equal(next.replayed,7);
 assert.equal(first.records.length,7);
 assert.ok(first.records.every(x=>x.decision==='DRAFT_NOT_AUTHORIZED'));
});
test('stale/changed actor, tenant, business and foreign site cannot leave draft boundary',()=>{
 assert.throws(()=>mutateScope(x=>{x.authenticatedActorUid='22222222-2222-4222-8222-222222222222'}),
  /SIGNED_ACTOR_CONTEXT_MISMATCH/);
 assert.throws(()=>mutateScope(x=>{x.selection.tenantId=9802}),
  /UNAUTHORIZED_OR_CROSS_TENANT_BUSINESS_SELECTION/);
 assert.throws(()=>mutateScope(x=>{x.selection.businessId=9820}),
  /UNAUTHORIZED_OR_CROSS_TENANT_BUSINESS_SELECTION/);
 assert.throws(()=>mutateScope(x=>{x.siteBindings['DEMO-SHOP-01']=98201}),
  /CANONICAL_SITE_SCOPE_OR_DUPLICATE_MISMATCH/);
 assert.throws(()=>mutateScope(x=>{x.siteBindings['DEMO-SHOP-01']=98101}),
  /CANONICAL_SITE_SCOPE_OR_DUPLICATE_MISMATCH/);
 assert.throws(()=>mutateScope(x=>{x.build01Context.sites=[]}),
  /CANONICAL_SITE_SCOPE_OR_DUPLICATE_MISMATCH/);
 assert.throws(()=>mutateScope(x=>{x.build01Context.businesses[0].tenant_id=9802}),
  /UNAUTHORIZED_OR_CROSS_TENANT_BUSINESS_SELECTION/);
});
test('can_manage, client-supplied finance role, forged context and missing canonical RPC data never authorize a post',()=>{
 const p=mutateScope(x=>{x.build01Context.businesses[0].can_manage=true});
 assert.equal(p.realFinancePermissionChecked,false);
 assert.equal(p.erpReady,false);
 assert.throws(()=>mutateScope(x=>{x.build01Context.tenants=[]}),
  /UNAUTHORIZED_OR_CROSS_TENANT_BUSINESS_SELECTION/);
 assert.throws(()=>mutateScope(x=>{x.build01Context.sites=[null]}),
  /CANONICAL_SITE_SCOPE_OR_DUPLICATE_MISMATCH/);
 assert.throws(()=>mutateScope(x=>{x.build01Context.actor_uid='forged'}),
  /SIGNED_ACTOR_CONTEXT_MISMATCH/);
 assert.throws(()=>plan({build01Context:{actor_uid:scoped.authenticatedActorUid}}),
  /CANONICAL_CONTEXT_COLLECTIONS_REQUIRED/);
 assert.throws(()=>plan({syntheticFixture:{...sourceFixture,synthetic_only:false}}),
  /ONLY_ISOLATED_DEMO_INPUT_ALLOWED/);
});
test('tampered, forged or unbalanced finance drafts are rejected independently of digest handling',()=>{
 const p=plan();
 const r=clone(p.proposals[0]);r.payload.debit[0].amountBDT='70.99';
 assert.throws(()=>validateRow(r),/DRAFT_DIGEST_MISMATCH/);
 const forged=clone(p.proposals[0]);forged.accountingPostApproved=true;
 assert.throws(()=>validateRow(forged),/UNAUTHORIZED_OR_UNKNOWN_DRAFT/);
 const wrong=clone(p);wrong.proposalDigest='a'.repeat(64);
 // Corrupting only the batch digest must fail the batch-level integrity gate.
 assert.throws(()=>simulateDraftQueue([],wrong),/DRAFT_BATCH_DIGEST_MISMATCH/);
 const fake=clone(p);fake.posted=true;
 assert.throws(()=>simulateDraftQueue([],fake),/FORBIDDEN_REAL_LEDGER_COMMIT/);
 const replay=clone(p);replay.proposals[0].payload.credit[0].amountBDT='120.01';
 // The batch index hashes per-row digests. A payload-only change is caught
 // by each row's own SHA before it could be added to the draft queue.
 assert.throws(()=>simulateDraftQueue([],replay),/DRAFT_DIGEST_MISMATCH/);
});
test('source book negative cases stop posting plan before any rows are offered',()=>{
 assert.throws(()=>mutateSource(x=>{x.packaging.events[2].declaredOutstanding.crates='999'}),
  /SOURCE_BOOKS_NOT_RECONCILED/);
 assert.throws(()=>mutateSource(x=>{x.expense.vouchers[1].cashNowBDT='999'}),
  /SOURCE_BOOKS_NOT_RECONCILED/);
 assert.throws(()=>mutateSource(x=>{x.expense.vouchers[0].lines[0].receipt='no';
  delete x.expense.vouchers[0].lines[0].receiptRef}),
  /SOURCE_BOOKS_NOT_RECONCILED/);
 assert.throws(()=>mutateSource(x=>{x.expense.vouchers[0].payMode='bank'}),
  /SOURCE_BOOKS_NOT_RECONCILED/);
});
test('proposal source idempotency digest is deterministic across rechecks, but scoped per group and business',()=>{
 const a=plan(),b=plan();
 assert.equal(a.proposalDigest,b.proposalDigest);
 assert.deepEqual(a.proposals.map(x=>x.idempotencyKey),b.proposals.map(x=>x.idempotencyKey));
 assert.equal(new Set(a.proposals.map(x=>x.idempotencyKey)).size,7);
 for(const row of a.proposals){
  assert.match(row.sourceDigest,/^[a-f0-9]{64}$/);
  assert.ok(row.idempotencyKey.startsWith('paperops:9801:9810:'));
 }
});

test('same idempotency key with different balanced source amount rejects replay atomically',()=>{
 const {createHash}=require('node:crypto');
 const digest=x=>createHash('sha256').update(JSON.stringify(x)).digest('hex');
 const original=plan(),old=simulateDraftQueue([],original);
 const changed=clone(original);
 // Fake a NEW balanced document for the same voucher, with a recalculated
 // unkeyed diagnostic SHA. This is not a signature; conflict still must block.
 const e=changed.proposals[0];
 e.payload.debit[0].amountBDT='69.00';
 e.payload.credit[0].amountBDT='119.00';
 e.sourceDigest=digest({kind:e.kind,scope:e.scope,sourceRef:e.sourceRef,payload:e.payload});
 changed.proposalDigest=digest(changed.proposals.map(r=>({key:r.idempotencyKey,digest:r.sourceDigest})));
 const before=JSON.stringify(old.records);
 assert.throws(()=>simulateDraftQueue(old.records,changed),/IDEMPOTENCY_CONFLICT_DETECTED/);
 assert.equal(JSON.stringify(old.records),before,'no partial draft queue mutation');
 assert.equal(old.records.length,7);
});
test('a recomputed hash cannot bypass unbalanced journal, source chart mapping or unauthorized posting',()=>{
 const {createHash}=require('node:crypto');
 const digest=x=>createHash('sha256').update(JSON.stringify(x)).digest('hex');
 const p=plan(),bad=clone(p.proposals[0]);
 bad.payload.credit[0].amountBDT='999.00';
 bad.sourceDigest=digest({kind:bad.kind,scope:bad.scope,sourceRef:bad.sourceRef,payload:bad.payload});
 assert.throws(()=>validateRow(bad),/UNBALANCED_FINANCE_DRAFT/);
 const badChart=clone(p.proposals[0]);
 badChart.payload.debit[0].account='REAL_GL_ACCOUNT';
 badChart.sourceDigest=digest({kind:badChart.kind,scope:badChart.scope,
   sourceRef:badChart.sourceRef,payload:badChart.payload});
 assert.throws(()=>validateRow(badChart),/UNRESOLVED_CHART_POLICY_BYPASS/);
 const idSpoof=clone(p.proposals[0]);
 idSpoof.idempotencyKey='paperops:9802:9810:FINANCE_EXPENSE_DRAFT:DEMO-C02-001';
 assert.throws(()=>validateRow(idSpoof),/DRAFT_IDEMPOTENCY_KEY_MISMATCH/);
});

test('new boundary rejects duplicate source drafts even when batch digest was recomputed',()=>{
 const crypto=require('node:crypto');
 const digest=v=>crypto.createHash('sha256').update(JSON.stringify(v)).digest('hex');
 const p=clone(plan());
 p.proposals.push(clone(p.proposals[0]));
 p.proposalDigest=digest(p.proposals.map(row=>({key:row.idempotencyKey,digest:row.sourceDigest})));
 assert.throws(()=>simulateDraftQueue([],p),/DUPLICATE_SOURCE_IN_SAME_DRAFT_BATCH/);
});
test('source cashbook amount must match original C-02 voucher amount before a posting candidate exists',()=>{
 const bad=clone(sourceFixture);
 bad.expense.cashbookRows[0].amountBDT='119.00';
 // The source ledger gate must stop this before any draft even exists.
 assert.throws(()=>planPostingCandidates({syntheticFixture:bad,
  build01Context:scoped.build01Context,authenticatedActorUid:scoped.authenticatedActorUid,
  selection:scoped.selection,siteBindings:scoped.siteBindings}),
 /SOURCE_BOOKS_NOT_RECONCILED/);
});
test('recomputed per-row digest still cannot create negative, cross-site, direction-forged packaging drafts',()=>{
 const crypto=require('node:crypto');
 const digest=v=>crypto.createHash('sha256').update(JSON.stringify(v)).digest('hex');
 function mutate(prop,value){
  const row=clone(plan().proposals.find(x=>x.kind==='RETURNABLE_PACKAGING_DRAFT'));
  row.payload[prop]=value;
  row.sourceDigest=digest({kind:row.kind,scope:row.scope,sourceRef:row.sourceRef,payload:row.payload});
  return row;
 }
 assert.throws(()=>validateRow(mutate('siteFromId',0)),/INVALID_RETURNABLE_PACKAGING_DRAFT/);
 assert.throws(()=>validateRow(mutate('declaredCratesDue',-1)),/INVALID_RETURNABLE_PACKAGING_DRAFT/);
 assert.throws(()=>validateRow(mutate('sourceReceiverRef','')),/INVALID_PACKAGING_RECEIVER_EVIDENCE/);
 assert.throws(()=>validateRow(mutate('kind','FAKE')),/INVALID_RETURNABLE_PACKAGING_DRAFT/);
 const returned=clone(plan().proposals.find(x=>x.kind==='RETURNABLE_PACKAGING_DRAFT'&&x.payload.kind==='RETURN'));
 returned.payload.cratesDelta=3;
 returned.sourceDigest=digest({kind:returned.kind,scope:returned.scope,sourceRef:returned.sourceRef,payload:returned.payload});
 assert.throws(()=>validateRow(returned),/RETURN_DIRECTION_INVERTED/);
});
