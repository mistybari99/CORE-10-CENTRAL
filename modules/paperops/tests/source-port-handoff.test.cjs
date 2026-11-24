'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const handoff=require('../source-port-handoff.cjs');
const fixture=require('../source-books-fixture.json');
const clone=x=>structuredClone(x);
const controls={
 requestId:'DEMO-HANDOFF-001',
 requestedBy:'DEMO-OPERATOR',
 independentReviewer:'DEMO-ACCOUNTANT',
 designatedApprover:'DEMO-OWNER',
 policyCandidateRef:'DEMO-POLICY-EXPENSE-CUSTODY-01'
};
const plan=()=>handoff.previewHandoff(fixture,controls);
test('source-to-CORE10 port handoff produces eight deterministic no-write intents from both existing books',()=>{
 const r=plan();
 assert.equal(r.status,'UNSIGNED_PORT_HANDOFF_PREVIEW_NOT_APPROVED');
 assert.equal(r.intents.length,8);
 assert.equal(r.intents.filter(x=>x.modulePort.includes('STOCK_PORT')).length,5);
 assert.equal(r.intents.filter(x=>x.modulePort.includes('IMPREST_EXPENSE')).length,2);
 assert.equal(r.intents.filter(x=>x.modulePort.includes('CASHBOOK_CROSSCHECK')).length,1);
 assert.equal(new Set(r.intents.map(x=>x.key)).size,8);
 assert.equal(handoff.verifyPreview(r),true);
 assert.equal(r.canPost,false);
 assert.equal(r.canAuthorize,false);
 assert.equal(r.canonicalAuthVerified,false);
 assert.equal(r.approvalServerVerified,false);
 assert.equal(r.databaseTouched,false);
 assert.equal(r.actors.policyActuallyApproved,false);
 assert.equal(r.actors.signaturesServerVerified,false);
 assert.ok(r.intents.every(x=>x.writesPermitted===false && x.postingAuthorized===false &&
  x.requiresCanonicalServerChecks.length===6));
});
test('idempotency is stable for the same original inputs and stable across object key order',()=>{
 const a=plan(),b=plan();
 assert.equal(a.previewDigest,b.previewDigest);
 assert.equal(a.requestContentDigest,b.requestContentDigest);
 assert.deepEqual(a.intents,b.intents);
 assert.equal(handoff.digest({a:1,b:2}),handoff.digest({b:2,a:1}));
 const diff=handoff.previewHandoff(fixture,{...controls,requestId:'DEMO-HANDOFF-002'});
 assert.notEqual(diff.previewDigest,a.previewDigest);
 assert.notEqual(diff.requestContentDigest,a.requestContentDigest);
});
test('original source content change requires new digest and cannot silently reuse an earlier signed-source intent',()=>{
 const modified=clone(fixture);
 modified.packaging.events[0].sourceRef='DEMO-W02-OPEN-CHANGED';
 const x=handoff.previewHandoff(modified,controls),original=plan();
 assert.notEqual(x.requestContentDigest,original.requestContentDigest);
 assert.notEqual(x.previewDigest,original.previewDigest);
 assert.notEqual(x.intents[0].sourceHash,original.intents[0].sourceHash);
 assert.equal(handoff.verifyPreview(x),true);
 assert.equal(x.canPost,false);
});
test('tampering with preview digest, route, owner status, scope or source refs fails integrity check',()=>{
 const base=plan();
 for(const mutate of [
 x=>x.canPost=true,
 x=>x.approvalServerVerified=true,
 x=>x.actors.policyActuallyApproved=true,
 x=>x.intents[0].writesPermitted=true,
 x=>x.intents[0].sourceHash='FAKE',
 x=>x.sourceScope='REAL-TENANT',
 x=>x.originalBooks.W02PackagingBalances[0].crates=999
 ]){
  const x=clone(base);mutate(x);
  assert.equal(handoff.verifyPreview(x),false);
 }
 assert.equal(handoff.verifyPreview({}),false);
});
test('caller-provided roles never become real permission, and identical maker/reviewer/approver is rejected',()=>{
 for(const pair of [
 ['requestedBy','independentReviewer'],['requestedBy','designatedApprover'],
 ['independentReviewer','designatedApprover']
 ]){
  const c={...controls,[pair[1]]:controls[pair[0]]};
  assert.throws(()=>handoff.previewHandoff(fixture,c),/REVIEW_ROLE_COLLISION/);
 }
 assert.throws(()=>handoff.previewHandoff(fixture,{...controls,designatedApprover:'REAL-OWNER'}),
  /REAL_IDENTITY_NOT_VERIFIED/);
 assert.throws(()=>handoff.previewHandoff(fixture,{...controls,policyCandidateRef:'REAL-POLICY'}),
  /UNVERIFIED_POLICY_SOURCE/);
 assert.throws(()=>handoff.previewHandoff(fixture,{...controls,requestId:'REAL-1'}),
  /ONLY_DEMO_REQUEST_ALLOWED/);
});
test('no cross tenant, unrecognized site or inconsistent source book tenant can be used in handoff',()=>{
 const x=clone(fixture);
 x.scope.tenantId='ACTUAL-TENANT';
 assert.throws(()=>handoff.previewHandoff(x,controls),/REAL_CONTEXT_REQUIRES_SERVER_AUTH/);
 const y=clone(fixture);
 y.packaging.scope.businessId='DIFFERENT-BUSINESS';
 assert.throws(()=>handoff.previewHandoff(y,controls),/SOURCE_BOOK_SCOPE_NOT_IDENTICAL/);
 const z=clone(fixture);
 z.packaging.events[0].toSiteId='DEMO-UNKNOWN-SITE';
 assert.throws(()=>handoff.previewHandoff(z,controls),/INVALID_PACKAGING_SITE_PAIR/);
});
test('source book blockers, false vouchers and duplicated references prevent creating port intents',()=>{
 let x=clone(fixture);
 x.packaging.events[1].declaredOutstanding.crates='50';
 assert.throws(()=>handoff.previewHandoff(x,controls),/REVIEWED_SOURCE_BOOKS_MUST_HAVE_ZERO_BLOCKERS/);
 x=clone(fixture);x.expense.dailyClose.vTotalBDT='999';
 assert.throws(()=>handoff.previewHandoff(x,controls),/REVIEWED_SOURCE_BOOKS_MUST_HAVE_ZERO_BLOCKERS/);
 x=clone(fixture);x.expense.vouchers[1].payMode='bank';
 assert.throws(()=>handoff.previewHandoff(x,controls),/REVIEWED_SOURCE_BOOKS_MUST_HAVE_ZERO_BLOCKERS/);
 x=clone(fixture);x.expense.cashbookRows[1].sourceVoucherId=x.expense.cashbookRows[0].sourceVoucherId;
 assert.throws(()=>handoff.previewHandoff(x,controls),/DUPLICATE_CASHBOOK_POSTING_OR_SOURCE/);
});
test('correction is a separate new proposal referencing immutable parent, not original mutation',()=>{
 const original=plan(),originalBefore=JSON.stringify(original);
 const c=handoff.proposeCorrection(original,{
  originalIntentKey:original.intents[1].key,correctionRequestId:'DEMO-REVERSAL-001',
  reasonRef:'DEMO-RECOUNT-EXCEPTION-001',enteredBy:'DEMO-ACCOUNTANT',
  independentReviewer:'DEMO-OWNER'
 });
 assert.equal(c.status,'CORRECTION_PROPOSAL_NOT_APPLIED');
 assert.equal(c.originalSourceHash,original.intents[1].sourceHash);
 assert.equal(c.parentPreviewDigest,original.previewDigest);
 assert.equal(c.originalUnchanged,true);
 assert.equal(c.requiresSignedServerAuditAndApproval,true);
 assert.equal(c.reversed,false);
 assert.equal(c.posted,false);
 assert.equal(JSON.stringify(original),originalBefore);
 assert.equal(c.correctionDigest.length,64);
});
test('correction of unknown source, self-review and tampered original cannot silently reverse',()=>{
 const r=plan();
 assert.throws(()=>handoff.proposeCorrection(r,{
  originalIntentKey:'paperops:UNKNOWN',correctionRequestId:'DEMO-REV-1',
  reasonRef:'DEMO-EXCEPTION',enteredBy:'DEMO-A',independentReviewer:'DEMO-B'
 }),/UNKNOWN_ORIGINAL_HANDOFF_INTENT/);
 assert.throws(()=>handoff.proposeCorrection(r,{
  originalIntentKey:r.intents[0].key,correctionRequestId:'DEMO-REV-1',
  reasonRef:'DEMO-EXCEPTION',enteredBy:'DEMO-A',independentReviewer:'DEMO-A'
 }),/CORRECTION_SELF_REVIEW_DENIED/);
 const changed=clone(r);changed.intents[0].sourceHash='TAMPERED';
 assert.throws(()=>handoff.proposeCorrection(changed,{
  originalIntentKey:changed.intents[0].key,correctionRequestId:'DEMO-REV-1',
  reasonRef:'DEMO-EXCEPTION',enteredBy:'DEMO-A',independentReviewer:'DEMO-B'
 }),/SOURCE_PREVIEW_INTEGRITY_FAILED/);
});
test('explicitly cannot certify real JWT, approval grants, money posting or production success',()=>{
 const r=plan();
 assert.equal(r.actors.policyActuallyApproved,false);
 assert.equal(r.intents.some(x=>x.action==='POST'),false);
 assert.ok(r.intents.every(x=>x.requiresCanonicalServerChecks.some(v=>v.includes('SIGNED_AUTH'))));
 assert.equal(r.sourceScope,'DEMO-TENANT-ISOLATED/DEMO-SWEETS-01');
 assert.equal(r.unresolvedBusinessGaps.includes('W02-01'),true);
 assert.equal(r.unresolvedBusinessGaps.includes('R01-03'),true);
});
