'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const h=require('../field-review/chatgpt-246/source-helper-conditions.cjs');
const conditional=require('../source-conditional-recheck.cjs');
test('frozen entry and forms helper source is blob-pinned; never executed',()=>{
  const r=h.verifyEvidence();
  assert.equal(r.formsBlob,'f2cb1c5e09210496106ace1bf33ddc40d2d6df1d');
  assert.equal(r.entryBlob,'402eba6436f0e619ebcbd15bb99c7c3cd0853585');
  assert.equal(r.executedLegacy,false);
  assert.equal(r.erpPostAuthorized,false);
  assert.throws(()=>h.verifyEvidence('altered','altered'),/FROZEN_SOURCE_BLOB_CHANGED/);
});
test('exact entry.js has: zero is PRESENT; empty, false, null and undefined are not',()=>{
  for(const [v,expected] of [[0,true],['0',true],[' ',true],[[],true],[{},true],[false,false],['',false],[null,false],[undefined,false]])
    assert.equal(h.legacyHas(v),expected,String(v));
});
test('C-02 cash_now O helper uses count-first switch AND original has semantics',()=>{
  for(const id of ['C-02:sum_cr','C-02:imprest_text']){
    assert.equal(conditional.decide(id,{cf:false}).status,'VISIBLE');
    assert.equal(conditional.decide(id,{cf:true,sourceData:{cash_now:0}}).status,'VISIBLE');
    assert.equal(conditional.decide(id,{cf:true,sourceData:{cash_now:false}}).status,'HIDDEN');
    assert.equal(conditional.decide(id,{cf:true,sourceData:{cash_now:''}}).status,'HIDDEN');
    assert.equal(conditional.decide(id,{cf:true,sourceData:{cash_now:null}}).status,'HIDDEN');
    assert.equal(conditional.decide(id,{cf:true,sourceData:{}}).status,'UNKNOWN_MUST_REVIEW');
    assert.equal(conditional.decide(id,{sourceData:{cash_now:10}}).status,'UNKNOWN_MUST_REVIEW');
    assert.equal(conditional.decide(id,{cf:'false',sourceData:{cash_now:10}}).status,'UNKNOWN_MUST_REVIEW');
    assert.equal(conditional.decide(id,{cf:true,sourceData:{open_counted:100}}).status,'UNKNOWN_MUST_REVIEW');
    assert.equal(conditional.decide(id,{cf:true,sourceData:{cash_now:0}}).erpPostingAuthorized,false);
  }
});
test('R-01 old O/open_counted and n/imp_cash are distinct, source exact, not signed',()=>{
  const a=conditional.decide('R-01:open_diff',{cf:true,sourceData:{open_counted:0}});
  assert.equal(a.status,'VISIBLE');
  assert.equal(a.sourceRuntimeParityCertified,false);
  assert.equal(conditional.decide('R-01:open_diff',{cf:true,sourceData:{open_counted:undefined}}).status,'HIDDEN');
  assert.equal(conditional.decide('R-01:imp_text',{cf:true,sourceData:{imp_cash:0}}).status,'VISIBLE');
  assert.equal(conditional.decide('R-01:imp_text',{cf:true,sourceData:{imp_cash:false}}).status,'HIDDEN');
  assert.equal(conditional.decide('R-01:imp_text',{cf:false}).status,'VISIBLE');
  assert.equal(conditional.decide('R-01:imp_text',{cf:true,sourceData:{}}).status,'UNKNOWN_MUST_REVIEW');
  assert.throws(()=>h.oldO('R-01:board_recon',{cf:true}),/SOURCE_FIELD_NOT_OWNED/);
});
test('source helper audit cannot be confused with owner parity or live signoff',()=>{
  const a=conditional.audit();
  assert.equal(a.source_expressions_verified,16);
  assert.equal(a.parityCertified,false);
  assert.equal(a.old_helpers_source_verified,true);
  assert.equal(a.signed_erp_posting_authorized,false);
});
