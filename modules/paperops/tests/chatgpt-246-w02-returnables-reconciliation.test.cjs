'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const source=require('../field-review/chatgpt-246/w02-returnables-reconciliation.cjs');
const baseline=require('../source-books-fixture.json').packaging;
const issues=require('../field-review/chatgpt-246/issue-registry.json');
const closure=require('../field-review/chatgpt-246/closure-evidence.json');
const owner=require('../field-review/ownership-246-1000.json');
function data(){
 const packaging=structuredClone(baseline);
 const s=packaging.scope;
 const sourceDeclarations=packaging.events.map(e=>({
  tenantId:s.tenantId,businessId:s.businessId,
  fromSiteId:e.fromSiteId,toSiteId:e.toSiteId,
  eventId:e.id,sourceRef:e.sourceRef,
  crates_sent:e.type==='RETURN'?'0':e.crates,
  crates_back:e.type==='RETURN'?e.crates:'0',
  trays_sent:e.type==='RETURN'?'0':e.trays,
  trays_back:e.type==='RETURN'?e.trays:'0',
  crates_due:e.declaredOutstanding.crates,
  trays_due:e.declaredOutstanding.trays
 }));
 const openingProofs=[{tenantId:s.tenantId,businessId:s.businessId,
  fromSiteId:s.sites[0],toSiteId:s.sites[1],eventId:packaging.events[0].id,
  sourceRef:packaging.events[0].sourceRef,carryForwardRef:'DEMO-CARRY-BOOK-1',
  approvalPolicyRef:'DEMO-RETURNABLE-POLICY-1',reviewerEvidenceRef:'DEMO-REVIEW-1',
  recordedBy:'DEMO-CUSTODY-RECORDER',reviewedBy:'DEMO-OWNER-REVIEWER'}];
 const physicalCounts=[{tenantId:s.tenantId,businessId:s.businessId,
  fromSiteId:s.sites[0],toSiteId:s.sites[1],crates:'3',trays:'6',
  countEvidenceRef:'DEMO-COUNT-1',witnessEvidenceRef:'DEMO-WITNESS-1',
  countedBy:'DEMO-INDEPENDENT-COUNTER',witnessedBy:'DEMO-INDEPENDENT-WITNESS',
  stockSnapshotRef:'DEMO-STOCK-SNAPSHOT-1'}];
 return {packaging,sourceDeclarations,openingProofs,physicalCounts};
}
const check=edit=>{const d=data();edit(d);return source.reviewReturnables(d);};
test('W02-01 frozen six original fields and owner lane have exact static proof',()=>{
 const p=source.assertSource();
 assert.equal(p.originalBlob,'f2cb1c5e09210496106ace1bf33ddc40d2d6df1d');
 assert.equal(p.sixOriginalManualFieldsProven,true);
 assert.equal(p.originalCrateFormulaProven,false);
 assert.equal(p.sourceExecuted,false);
 const owned=new Set([...owner.lane_B_chatgpt.critical_86_keys,
  ...owner.lane_B_chatgpt.mapped_150_keys,...owner.lane_B_chatgpt.reserved_next_10_keys]);
 assert.equal(p.fields.length,6);
 for(const f of p.fields){assert.ok(owned.has(f),f);assert.ok(!owner.lane_A_codex.ownership_keys.includes(f));}
});
test('W02-01 source movements, handwritten fields, carry-forward and physical recount reconcile without posting',()=>{
 const r=source.reviewReturnables(data());
 assert.equal(r.status,'REVIEW_READY_NOT_APPROVED',r.blockers.join('|'));
 assert.equal(r.blockers.length,0);
 assert.equal(r.checkedMovements,5);assert.equal(r.physicalPairsChecked,1);
 assert.equal(r.canPost,false);assert.equal(r.erpPosted,false);
 assert.equal(r.canonicalStockAuthorized,false);assert.equal(r.originalFormulaProven,false);
 assert.equal(r.signedOriginalEvidenceVerified,false);assert.equal(r.ownerPolicyAccepted,false);
 assert.equal(r.changesToLedger,0);
 assert.equal(r.proposedReconciliationDigest,source.reviewReturnables(data()).proposedReconciliationDigest);
});
test('old manually entered due, issue and return cannot silently diverge from signed-reference movements',()=>{
 let r=check(d=>{d.sourceDeclarations[2].crates_due='999'});
 assert.ok(r.blockers.includes('W02_RETURNABLES_OUTSTANDING_MISMATCH:DEMO-PK-RET1:crates_due'));
 r=check(d=>{d.sourceDeclarations[1].crates_sent='1'});
 assert.ok(r.blockers.includes('W02_RETURNABLES_EVENT_ENTRY_MISMATCH:DEMO-PK-ISS1:crates_sent'));
 r=check(d=>{d.sourceDeclarations[4].trays_back='0'});
 assert.ok(r.blockers.includes('W02_RETURNABLES_EVENT_ENTRY_MISMATCH:DEMO-PK-RET2:trays_back'));
});
test('independently counted physical balance and opening source must both match',()=>{
 let r=check(d=>{d.physicalCounts[0].crates='2'});
 assert.ok(r.blockers.some(x=>x.startsWith('W02_RETURNABLES_PHYSICAL_VS_LEDGER_DISCREPANCY')));
 r=check(d=>{d.openingProofs[0].sourceRef='DEMO-OTHER'});
 assert.ok(r.blockers.some(x=>x.startsWith('W02_RETURNABLES_OPENING_NOT_TIED_TO_SOURCE')));
 r=check(d=>{d.openingProofs=[]});
 assert.ok(r.blockers.includes('W02_RETURNABLES_OPENING_EVIDENCE_INCOMPLETE'));
 r=check(d=>{d.physicalCounts=[]});
 assert.ok(r.blockers.includes('W02_RETURNABLES_PHYSICAL_COUNT_INCOMPLETE'));
});
test('two distinct source and physical checkers cannot be their own custody actor',()=>{
 let r=check(d=>{d.physicalCounts[0].countedBy=d.packaging.events[0].senderId});
 assert.ok(r.blockers.some(x=>x.startsWith('W02_RETURNABLES_INDEPENDENT_PHYSICAL_COUNT_NOT_PROVED')));
 r=check(d=>{d.openingProofs[0].reviewedBy=d.openingProofs[0].recordedBy});
 assert.ok(r.blockers.some(x=>x.startsWith('W02_RETURNABLES_OPENING_INDEPENDENCE_NOT_PROVED')));
 r=check(d=>{d.physicalCounts[0].witnessedBy=d.physicalCounts[0].countedBy});
 assert.ok(r.blockers.some(x=>x.startsWith('W02_RETURNABLES_INDEPENDENT_PHYSICAL_COUNT_NOT_PROVED')));
});
test('wrong tenant/site, duplicate/replayed evidence and invalid negative/fractional crates fail closed',()=>{
 assert.throws(()=>check(d=>{d.sourceDeclarations[1].businessId='DEMO-OTHER'}),/CROSS_SCOPE/);
 assert.throws(()=>check(d=>{d.physicalCounts[0].toSiteId='DEMO-UNKNOWN'}),/WRONG_SITE_PAIR/);
 assert.throws(()=>check(d=>{d.sourceDeclarations.push(d.sourceDeclarations[0])}),/DUPLICATE_DECLARATION/);
 assert.throws(()=>check(d=>{d.physicalCounts.push(d.physicalCounts[0])}),/DUPLICATE_PHYSICAL_COUNT/);
 assert.throws(()=>check(d=>{d.openingProofs[0].reviewerEvidenceRef=d.packaging.events[0].senderProofRef}),/REPLAYED_PROOF_REF/);
 assert.throws(()=>check(d=>{d.sourceDeclarations[0].crates_due='-1'}),/INVALID_QTY/);
 assert.throws(()=>check(d=>{d.physicalCounts[0].trays='1.5'}),/INVALID_QTY/);
 assert.throws(()=>check(d=>{d.packaging.scope.synthetic_only=false}),/ONLY_SYNTHETIC_ISOLATED_LEDGER_INPUT/);
});
test('W02-01 local correction exists but all 11 original signed-runtime gaps remain OPEN',()=>{
 assert.equal(issues.local_corrections_count,11);
 assert.equal(issues.remaining_open_original_gaps,11);
 assert.equal(issues.total_original_gaps,11);
 assert.equal(issues.total_high_risk_obligations,20);
 const g=issues.functional_gaps.find(x=>x.id==='W02-01');
 assert.equal(g.status,'OPEN_WITH_BLOCKER');
 assert.equal(g.canonical_runtime_integrated,false);
 assert.equal(g.signed_tested,false);assert.equal(g.owner_policy_accepted,false);
 assert.match(g.local_correction,/W02_PINNED_RETURNABLES/);
 assert.match(g.local_evidence,/w02-returnables-reconciliation/);
 for(const f of source.assertSource().fields){
  const row=closure.fields.find(x=>x.source_id===f);
  assert.match(row.local_nonposting_correction,/W02_RETURNABLES/);
  assert.equal(row.owner_accepted,false);assert.equal(row.signed_tested,false);
 }
 assert.equal(closure.fields.length,246);
 assert.equal(closure.canonical_runtime_signed_postings,0);
 assert.equal(closure.owner_approved_fields,0);
});
