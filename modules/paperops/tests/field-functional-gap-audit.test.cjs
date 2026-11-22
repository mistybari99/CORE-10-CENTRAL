'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {audit}=require('../field-functional-gap-audit.cjs');
const data=require('../field-review/functional-gaps-001-003.json');
test('eleven evidence-backed original source gaps remain open and block false release',()=>{
 const result=audit();
 assert.equal(result.ok,true,result.problems.join(' | '));
 assert.equal(result.source_fields_rechecked,150);
 assert.equal(result.open_gaps,11);
 assert.equal(result.parity_approved,0);
 assert.equal(result.release_authorized,false);
});
test('the full 150 recheck cannot be declared accepted by changing a report status',()=>{
 const b=structuredClone(data);b.status='ALL_PARITY_APPROVED';
 assert.ok(audit(b).problems.includes('FALSE_COMPLETE_STATUS'));
 b.status=data.status;b.summary.ready_for_live=true;
 assert.ok(audit(b).problems.includes('UNAUTHORIZED_RELEASE_CLAIM'));
});
test('rechecked gap evidence must refer to original source fields and exact old field call text',()=>{
 let b=structuredClone(data);b.gaps[0].field_ids=['C-02:invented_field'];
 assert.ok(audit(b).problems.some(x=>x.startsWith('UNCONFIRMED_SOURCE_KEY')));
 b=structuredClone(data);b.gaps[0].source_fragment='INVENTED ORIGINAL EVIDENCE';
 assert.ok(audit(b).problems.some(x=>x.startsWith('ORIGINAL_FIELD_CALL_PROOF_MISSING')));
 b=structuredClone(data);b.gaps[0].next='';
 assert.ok(audit(b).problems.some(x=>x.startsWith('UNSPECIFIED_REMEDIATION')));
});
test('source-only first-pass gap list distinguishes stricter safety policy from exact old behavior',()=>{
 const ids=new Set(data.gaps.map(x=>x.id));
 for(const required of ['C02-01','C02-02','C01-01','W02-01','W03-01','R01-01','R01-02','R01-03'])
  assert.ok(ids.has(required));
 assert.ok(data.gaps.some(x=>/stricter/i.test(x.finding)));
 assert.ok(data.gaps.some(x=>/unbuilt|still unbuilt|not implemented/i.test(x.finding)),
   'some real ERP ledger or approval capability must remain explicitly unbuilt');
 assert.equal(data.summary.synthetic_book_prototypes_built,2);
 assert.ok(data.gaps.find(x=>x.id==='W02-01').status.includes('PENDING'));
 assert.ok(data.gaps.find(x=>x.id==='R01-03').status.includes('PENDING'));
 assert.ok(data.gaps.some(x=>/unknown/i.test(x.finding)));
});
