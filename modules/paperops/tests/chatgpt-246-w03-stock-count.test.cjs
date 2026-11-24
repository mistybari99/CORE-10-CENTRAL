'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {reconcileStockCount,assertSource}=require('../field-review/chatgpt-246/w03-stock-count-freeze.cjs');
const manifest=require('../field-review/ownership-246-1000.json');
const S={tenantId:'DEMO-T1',businessId:'DEMO-B1',siteId:'DEMO-S1'},row=x=>({...S,...x});
function f(){return {synthetic_only:true,scope:{...S},
 session:row({countSheetRef:'DEMO-W03-1',ledgerSnapshotRef:'DEMO-LEDGER-V1',
 freezeProofRef:'DEMO-FREEZE1',counterActor:'DEMO-COUNTER',storekeeperActor:'DEMO-KEEPER',
 witnessActor:'DEMO-WITNESS',startedAt:'2026-11-23T01:00:00Z',
 endedAt:'2026-11-23T02:00:00Z',freezeConfirmed:true,movementDeclared:'no'}),
 policy:{controlRef:'DEMO-TOL-CONTROL-V1',tolerancePct:'2',toleranceValueBDT:'50'},
 bookRows:[row({itemId:'DEMO-SUGAR',lotId:'LOT-1',unitId:'KG',quantity:'100',
 sellPriceBDT:'100',sourceRef:'DEMO-BOOK-1',ledgerSnapshotRef:'DEMO-LEDGER-V1'})],
 physicalRows:[row({itemId:'DEMO-SUGAR',lotId:'LOT-1',unitId:'KG',quantity:'100',
 sourceRef:'DEMO-PHYS-1',counterActor:'DEMO-COUNTER'})],movements:[]};}
const edit=fn=>{const x=f();fn(x);return reconcileStockCount(x);};
test('W03 independent no-movement freeze and counted stock reconcile, no adjustment capability',()=>{
 assert.equal(assertSource().oldExecuted,false);
 const r=edit(()=>{});
 assert.equal(r.status,'SOURCE_RECONCILED_NOT_APPROVED');
 assert.equal(r.evidence.rows[0].variance,'0.0000');
 assert.equal(r.evidence.movementCount,0);
 assert.equal(r.canPost,false);
 assert.equal(r.canonicalStockAdjustmentPosted,false);
 assert.ok(r.source_ids.every(id=>[...manifest.lane_B_chatgpt.critical_86_keys,
  ...manifest.lane_B_chatgpt.mapped_150_keys].includes(id)));
 assert.equal(r.evidence.sourceDigest,edit(()=>{}).evidence.sourceDigest);
});
test('W03 movement during count is a freeze breach even with correctly reconciled quantity',()=>{
 const r=edit(x=>{x.session.movementDeclared='yes';x.session.movementDetail='Synthetic receipt after snapshot';
 x.movements=[row({itemId:'DEMO-SUGAR',lotId:'LOT-1',kind:'RECEIVE',
  quantity:'3',sourceRef:'DEMO-MOV-1',evidenceRef:'DEMO-PROOF-1',actor:'DEMO-STOCK-A',
  ledgerSnapshotRef:'DEMO-LEDGER-V1',occurredAt:'2026-11-23T01:30:00Z'})];
 x.physicalRows[0].quantity='103';});
 assert.equal(r.evidence.rows[0].bookAtCount,'103.0000');
 assert.equal(r.evidence.rows[0].variance,'0.0000');
 assert.ok(r.blockers.includes('W03_FREEZE_BREACH_REQUIRES_REVIEW'));
 assert.equal(r.canPost,false);
 assert.ok(edit(x=>{x.session.movementDeclared='yes'}).blockers.includes('W03_DECLARED_MOVEMENT_HAS_NO_REFERENCES'));
});
test('W03 variance is never silently adjusted, even within configured tolerance',()=>{
 const small=edit(x=>{x.physicalRows[0].quantity='99';x.physicalRows[0].varianceReason='test';});
 assert.ok(small.blockers.includes('W03_VARIANCE_WITHIN_CONTROL_NEEDS_REVIEW'));
 assert.ok(small.blockers.includes('W03_ADJUSTMENT_REQUIRES_INDEPENDENT_AUTHORIZATION'));
 const big=edit(x=>{x.physicalRows[0].quantity='80';x.physicalRows[0].varianceReason='test';});
 assert.ok(big.blockers.includes('W03_VARIANCE_OUTSIDE_CONTROL'));
 assert.equal(big.evidence.rows[0].estimatedVarianceValueBDT,'2000.00');
 assert.ok(edit(x=>{x.physicalRows[0].quantity='90';}).blockers.includes('W03_VARIANCE_REASON_REQUIRED'));
});
test('W03 independent actor, freeze attestation and conditionally required details fail closed',()=>{
 assert.ok(edit(x=>{x.session.counterActor='DEMO-KEEPER';x.physicalRows[0].counterActor='DEMO-KEEPER';})
  .blockers.includes('W03_COUNTER_EQUALS_STOREKEEPER'));
 assert.ok(edit(x=>{x.session.witnessActor='DEMO-COUNTER';})
  .blockers.includes('W03_INDEPENDENT_WITNESS_REQUIRED'));
 assert.ok(edit(x=>{x.session.freezeConfirmed=false;}).blockers.includes('W03_FREEZE_NOT_ATTESTED'));
 assert.ok(edit(x=>{x.session.movementDeclared='yes';})
  .blockers.includes('W03_MOVEMENT_SOURCE_DETAILS_REQUIRED'));
 assert.ok(edit(x=>{x.session.movementDeclared='unknown';})
  .blockers.includes('W03_MOVEMENT_DECLARATION_UNKNOWN'));
 assert.ok(edit(x=>{delete x.policy.tolerancePct;delete x.policy.toleranceValueBDT;})
  .blockers.includes('W03_TOLERANCE_CONTROL_VALUES_MISSING'));
});
test('W03 rejects cross-tenant, wrong book revision, stale movements and quantity underflow',()=>{
 assert.throws(()=>edit(x=>{x.bookRows[0].tenantId='DEMO-T2';}),/CROSS_TENANT_BUSINESS_SITE/);
 assert.throws(()=>edit(x=>{x.physicalRows[0].siteId='DEMO-S2';}),/CROSS_TENANT_BUSINESS_SITE/);
 assert.throws(()=>edit(x=>{x.bookRows[0].ledgerSnapshotRef='OLD';}),/BOOK_REVISION_SOURCE_MISMATCH/);
 assert.throws(()=>edit(x=>{x.bookRows[0].quantity='-1';}),/INVALID_QUANTITY/);
 assert.throws(()=>edit(x=>{x.bookRows[0].quantity='1.00001';}),/INVALID_QUANTITY/);
 assert.throws(()=>edit(x=>{x.physicalRows[0].sourceRef=x.bookRows[0].sourceRef;}),/DUPLICATE_OR_REPLAY_SOURCE_REF/);
 assert.throws(()=>edit(x=>{x.physicalRows.push({...x.physicalRows[0],sourceRef:'DIFFERENT'});}),/DUPLICATE_PHYSICAL_LOT/);
 assert.throws(()=>edit(x=>{x.synthetic_only=false;}),/SYNTHETIC_SCOPE_ONLY/);
});
test('W03 no acceptance of false declared freeze, unsupported movement, stale out-of-window event',()=>{
 const insert=x=>{x.session.movementDeclared='yes';x.session.movementDetail='test';
  x.movements=[row({itemId:'DEMO-SUGAR',lotId:'LOT-1',kind:'ISSUE',
    quantity:'150',sourceRef:'DEMO-MOV1',evidenceRef:'DEMO-EVID1',actor:'DEMO-WAREHOUSE',
    ledgerSnapshotRef:'DEMO-LEDGER-V1',occurredAt:'2026-11-23T01:30:00Z'})];};
 assert.throws(()=>edit(x=>insert(x)),/MOVEMENTS_EXCEED_BOOK_QUANTITY/);
 assert.throws(()=>edit(x=>{insert(x);x.movements[0].kind='ADJUST';}),/UNSUPPORTED_MOVEMENT_TYPE/);
 assert.throws(()=>edit(x=>{insert(x);x.movements[0].occurredAt='2026-11-23T04:30:00Z';}),/MOVEMENT_OUTSIDE_COUNT_WINDOW/);
 assert.throws(()=>edit(x=>{insert(x);x.movements[0].ledgerSnapshotRef='OLD';}),/MOVEMENT_STALE_LEDGER_SNAPSHOT/);
});

test('W03 rejects invalid civil UTC dates and sub-microsecond precision',()=>{
 assert.throws(()=>edit(x=>{x.session.startedAt='2026-02-30T01:00:00Z';}),/W03_BAD_TIMESTAMP:START/);
 assert.throws(()=>edit(x=>{x.session.endedAt='2026-02-29T02:00:00Z';}),/W03_BAD_TIMESTAMP:END/);
 assert.throws(()=>edit(x=>{x.session.endedAt='2026-11-23T02:00:00.0000001Z';}),/W03_BAD_TIMESTAMP:END/);
});
test('W03 compares the movement freeze window at microsecond resolution',()=>{
 const withMovement=at=>edit(x=>{
  x.session.startedAt='2026-11-23T01:00:00.000001Z';
  x.session.endedAt='2026-11-23T01:00:00.000003Z';
  x.session.movementDeclared='yes';
  x.session.movementDetail='Microsecond-specific canonical candidate evidence';
  x.movements=[row({itemId:'DEMO-SUGAR',lotId:'LOT-1',kind:'RECEIVE',
    quantity:'1',sourceRef:'DEMO-MOV-US',evidenceRef:'DEMO-PROOF-US',actor:'DEMO-STOCK-A',
    ledgerSnapshotRef:'DEMO-LEDGER-V1',occurredAt:at})];
  x.physicalRows[0].quantity='101';
 });
 const within=withMovement('2026-11-23T01:00:00.000002Z');
 assert.equal(within.status,'BLOCK'); // Freeze breach always requires review.
 assert.equal(within.evidence.rows[0].bookAtCount,'101.0000');
 assert.ok(within.blockers.includes('W03_FREEZE_BREACH_REQUIRES_REVIEW'));
 assert.throws(()=>withMovement('2026-11-23T01:00:00.000000Z'),/W03_MOVEMENT_OUTSIDE_COUNT_WINDOW/);
 assert.throws(()=>withMovement('2026-11-23T01:00:00.000004Z'),/W03_MOVEMENT_OUTSIDE_COUNT_WINDOW/);
});
