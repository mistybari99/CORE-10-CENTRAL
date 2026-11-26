'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const base=path.resolve(__dirname,'..');
const workbench=require('../control-workbench.js');
const gates=require('../paper-controls.js');
const sample={
 cashHandover:{closingRef:'R01',sealRef:'BAG1',cashLedgerRef:'CASH1',dispatchedCash:'100',
  receivedCash:'100',floatLeft:'20',approvedFloat:'20',sentBy:'Sender',receivedBy:'Receiver'},
 stockTransfer:{challanRef:'W02',sourceLocation:'Factory',destinationLocation:'Shop',
  issuedBy:'Factory',receivedBy:'Shop',sentQty:'10',receivedQty:'10',foodGoods:false},
 goodsReceived:{poRef:'PO1',grnRef:'GRN1',invoiceRef:'INV1',orderedQty:'10',deliveredQty:'10',
  acceptedQty:'10',heldQty:'0',returnedQty:'0',receivedBy:'Store',qcBy:'QC',heldSegregated:false,qcPassed:true},
 factoryBatch:{batchRef:'B1',recipeVersion:'v1',issueSlipRef:'ISS1',issuedKg:'10',usedKg:'9',returnedKg:'1',
  expectedOutputKg:'15',goodOutputKg:'14',secondGradeKg:'0.5',wasteKg:'0.5',prestartSafetyOk:true,
  scaleChecked:true,producedBy:'Producer',yieldCheckedBy:'Independent checker',qcReleased:true,qcRef:'QC1',yieldTestRef:'YT1'},
 discountApproval:{saleRef:'S1',originalAmount:'100',discountAmount:'10',approvedLimit:'10',preparedBy:'Cashier'},
 returnRefund:{originalSaleRef:'S1',returnRef:'RET1',rootCause:'Packing issue',
  refundAmount:'10',refundLimit:'10',productReturned:true,productQuarantined:true,
  foodIllnessReported:false,managementEscalated:false,receivedBy:'Cashier',paidBy:'Accounts',refundVoucherRef:'PAY1'},
 customerOrder:{orderRef:'ORD1',boardRef:'BD1',deliveryDate:'2026-11-23',
  takenBy:'Staff',boardCheckedBy:'Manager',totalAmount:'200',discountAmount:'0',
  advanceAmount:'0',notCollected:false}
};
test('every offline control flow declares exactly the data keys required for its candidate checks',()=>{
 assert.equal(workbench.FLOWS.length,7);
 for(const x of workbench.FLOWS){
  assert.equal(typeof gates[x.id],'function');
  assert.ok(x.source);
  const keys=x.fields.map(f=>f.key);
  assert.equal(new Set(keys).size,keys.length,x.id+' duplicate field');
  assert.ok(x.fields.every(f=>f.bn&&f.en&&['text','bool','money','qty'].includes(f.type)));
  const present=sample[x.id];
  assert.ok(present);
  for(const key of Object.keys(present))assert.ok(keys.includes(key),x.id+':'+key);
  const result=workbench.evaluate(x.id,present);
  assert.equal(result.result.status,'REVIEW_READY_NOT_APPROVED',x.id+' '+JSON.stringify(result.result.blockers));
  assert.equal(result.canPost,false);
  assert.equal(result.canApprove,false);
  assert.equal(result.result.authorized,false);
  assert.equal(result.result.fieldParityConfirmed,false);
 }
});
test('workbench rejects unknown workflows and unrecognized input keys',()=>{
 assert.throws(()=>workbench.evaluate('unknown',{}),/UNKNOWN_CONTROL_FLOW/);
 assert.throws(()=>workbench.evaluate('cashHandover',{...sample.cashHandover,unsafe:'yes'}),/UNRECOGNIZED_CONTROL_FIELD/);
 assert.throws(()=>workbench.evaluate('cashHandover',null),/INVALID_CONTROL_INPUT/);
});
test('unknown food classification and unscreened illness answers must remain blocking',()=>{
 const transfer={...sample.stockTransfer};
 delete transfer.foodGoods;
 const result=workbench.evaluate('stockTransfer',transfer);
 assert.ok(result.result.blockers.includes('FOOD_CATEGORY_CONFIRMATION_REQUIRED'));
 const returned={...sample.returnRefund};
 delete returned.foodIllnessReported;
 assert.ok(workbench.evaluate('returnRefund',returned).result.blockers.includes('ILLNESS_SCREEN_CONFIRMATION_REQUIRED'));
 delete returned.productReturned;
 assert.ok(workbench.evaluate('returnRefund',returned).result.blockers.includes('RETURN_INTAKE_CONFIRMATION_REQUIRED'));
});
test('offline control check UI is self-contained, syntactically valid and no inputs are persisted',()=>{
 const html=fs.readFileSync(path.join(base,'checks.html'),'utf8');
 const src=[...html.matchAll(/<script src="([^"]+)"><\/script>/g)].map(x=>x[1]);
 assert.deepEqual(src,['./paper-controls.js','./control-workbench.js']);
 const inline=[...html.matchAll(/<script>([\s\S]*?)<\/script>/g)];
 assert.equal(inline.length,1);
 assert.doesNotThrow(()=>new vm.Script(inline[0][1],{filename:'checks.html'}));
 for(const file of src)assert.ok(fs.existsSync(path.resolve(base,file)));
 assert.match(html,/NOT APPROVED/);
 assert.match(html,/@media print/);
 assert.doesNotMatch(html,/localStorage|sessionStorage|indexedDB|fetch\s*\(|XMLHttpRequest|\.rpc\(/);
 assert.doesNotMatch(html,/<script[^>]+src="https?:/);
});
