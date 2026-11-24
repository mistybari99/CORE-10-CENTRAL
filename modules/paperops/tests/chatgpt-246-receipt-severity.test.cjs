'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {assessMissingReceipts,attestSource}=require('../field-review/chatgpt-246/receipt-warning-severity.cjs');
const row=(ref,receipt,amount)=>({voucherLineRef:ref,receipt,amount});
function scenario(lines,reason){return assessMissingReceipts({synthetic_only:true,lines,noReceiptReason:reason});}
test('old C-02 no receipt has yellow warning; missing reason also red, not silently cleared',()=>{
 assert.equal(attestSource(),true);
 const r=scenario([row('DEMO-01','no','50'),row('DEMO-02','yes','200')],'');
 assert.deepEqual(r.flags.map(x=>[x.code,x.severity,x.amountBDT]),[
  ['no_receipt','yellow','50.00'],['receipt_reason_missing','red','50.00']]);
 assert.equal(r.canPost,false);
});
test('a supplied reason resolves the red warning but NOT missing receipt policy approval',()=>{
 const r=scenario([row('DEMO-01','no','5.05')],'Synthetic reason');
 assert.deepEqual(r.flags.map(x=>x.code),['no_receipt']);
 assert.equal(r.status,'MISSING_RECEIPT_POLICY_EXCEPTION_REQUIRED');
 assert.equal(r.ownerPolicyAccepted,false);
 assert.equal(r.signedMoneyAuthorized,false);
});
test('no paid missing receipt produces neither flag; zero amount boundary is preserved',()=>{
 const a=scenario([row('DEMO-01','no','0.00')],'');
 assert.equal(a.flags.length,0);
 assert.equal(scenario([row('DEMO-01','yes','12.34')],'').flags.length,0);
 const b=scenario([row('DEMO-01','no','0.01')],null);
 assert.deepEqual(b.flags.map(x=>x.severity),['yellow','red']);
});
test('duplicate voucher refs, unsafe amounts, unknown receipt and non-demo fail closed',()=>{
 assert.throws(()=>scenario([row('DEMO-1','no','1'),row('DEMO-1','no','1')],'x'),/C02_DUPLICATE_VOUCHER/);
 assert.throws(()=>scenario([row('DEMO-1','no','-1')],'x'),/C02_INVALID_MONEY/);
 assert.throws(()=>scenario([row('DEMO-1','no','9007199254740993')],'x'),/C02_UNSAFE_MONEY/);
 assert.throws(()=>scenario([row('DEMO-1','maybe','1')],'x'),/C02_UNKNOWN_RECEIPT/);
 assert.throws(()=>assessMissingReceipts({lines:[row('DEMO-1','no','1')]}),/C02_SYNTHETIC_ONLY/);
});
