'use strict';
const test=require('node:test'), assert=require('node:assert/strict');
const checks=require('../field-batch-002-003-checks.js');
const audit=require('../field-batch-audit.cjs');
const b1=require('../field-review/batch-001.json');
const b2=require('../field-review/batch-002.json');
const b3=require('../field-review/batch-003.json');
const paperops=require('../paperops.js');
require('../form-packs.js');
const kit=require('../paper-kit.js');
const clone=o=>structuredClone(o);
const stock={
  countSheetRef:'COUNT-001',stockLedgerRef:'LEDGER-001',
  counter:'Independent stock counter',storekeeper:'Warehouse keeper',witness:'External witness',
  movementDuringCount:false,approvedTolerancePercent:'2',approvedToleranceValueBDT:'20',
  rows:[{item:'SUGAR-KG',bookQty:'100',countQty:'100',sellPriceBDT:'100'},
        {item:'MILK-L',bookQty:'80',countQty:'80',sellPriceBDT:'50'}]
};
const shop={
  dayType:'normal',preparedBy:'Shop maker',dutyManager:'Manager',closeRef:'CLOSE-R01-001',
  openingSafetyOk:true,expiredProductIsolated:true,
  approvedDrawerFloat:'500',openCountedBDT:'500',floatLeftBDT:'500',
  approvedImprest:'1000',imprestCashBDT:'800',imprestReceiptsBDT:'200',
  fridges:[{name:'Display fridge',temperatureC:'4',minTempC:'0',maxTempC:'5'},
           {name:'Frozen sweets',temperatureC:'-18',minTempC:'-22',maxTempC:'-16'}],
  receipts:[{challanRef:'TRANS-01',writtenQty:'20',countedQty:'20'}],
  cleaning:[{doer:'Cleaner',verifier:'Supervisor'}],
  salesCategories:[{amount:'300.00'},{amount:'700.00'}],
  totalSalesBDT:'1000',firstCashCountBDT:'800',secondCashCountBDT:'800',
  witness:'Independent witness',secondSigner:'Manager',
  stock:[{wasteQty:'1',wasteApprovedBy:'Supervisor',expiredLossBDT:'0'}]
};
function blocks(fn,v,key,oldFlag){
 const r=fn(v);
 assert.equal(r.status,'BLOCK');
 assert.ok(r.blockers.includes(key),key+': '+JSON.stringify(r.blockers));
 if(oldFlag)assert.ok(r.legacyFlags.includes(oldFlag),oldFlag+': '+JSON.stringify(r.legacyFlags));
 assert.equal(r.approved,false);
 assert.equal(r.postingAuthorized,false);
 assert.equal(r.parityCertified,false);
}
test('batch 002 and 003 both contain exactly 50 new source fields in sequential deterministic order',()=>{
 const x=audit.auditBatch(b2,b1.entries.map(x=>x.source_id));
 assert.equal(x.ok,true,x.problems.join(' | '));
 assert.equal(x.source_to_print_checked,50);
 assert.equal(x.remaining_unmapped_review_queue,1060);
 const y=audit.auditBatch(b3,[...b1.entries,...b2.entries].map(x=>x.source_id));
 assert.equal(y.ok,true,y.problems.join(' | '));
 assert.equal(y.remaining_unmapped_review_queue,1010);
 const all=[b1,b2,b3].flatMap(x=>x.entries.map(e=>e.source_id));
 assert.equal(new Set(all).size,150);
 assert.deepEqual(Object.fromEntries([...new Set(b2.entries.map(e=>e.source_form))].map(k=>[k,b2.entries.filter(e=>e.source_form===k).length])),{
  'W-02':33,'W-03':9,'R-01':8
 });
 assert.equal(b3.entries.filter(e=>e.source_form==='R-01').length,50);
 assert.equal(audit.run().next_batch_number,4);
 assert.equal(audit.run().remaining_first_pass,1010);
 assert.equal(audit.run().unique_source_flag_categories,27);
});
test('tampered batch, missing check, wrong legacy flag and duplicate prior field are rejected',()=>{
 const prev=b1.entries.map(x=>x.source_id);
 let b=clone(b2);b.entries[0].parity_certified=true;
 assert.ok(audit.auditBatch(b,prev).problems.includes('FALSE_FIELD_PARITY_CLAIM:W-02:grades'));
 b=clone(b2);b.forms[1].original_flags[0].new_blocker='FAKE_APPROVED';
 assert.ok(audit.auditBatch(b,prev).problems.includes('CANDIDATE_FLAG_EXECUTION_MAPPING_DRIFT:W-03'));
 b=clone(b2);b.forms[1].check_function='imaginary';
 assert.ok(audit.auditBatch(b,prev).problems.includes('CANDIDATE_CALCULATOR_MISSING:W-03'));
 b=clone(b3);b.entries[0].target_field_key='unknown';
 assert.ok(audit.auditBatch(b,[...b1.entries,...b2.entries].map(x=>x.source_id)).problems.includes('MISSING_OR_MISMATCHED_PRINT_FIELD:R-01:imp_receipts'));
 b=clone(b2);b.batch_number=5;
 assert.ok(audit.auditBatch(b,prev).problems.includes('BATCH_SEQUENCE_NOT_CONTIGUOUS'));
});
test('W-03 count source candidate: exact match, independent counter and witness, signed policy',()=>{
 const r=checks.stockCountReview(stock);
 assert.equal(r.status,'REVIEW_READY_NOT_APPROVED',JSON.stringify(r.blockers));
 assert.deepEqual(r.blockers,[]);
 assert.equal(r.evidence.rows[0].varianceQty,'0.0000');
 assert.equal(r.evidence.adjustmentAuthorized,false);
});
test('W-03 outside tolerance and small variance surface the distinct original source flags',()=>{
 blocks(checks.stockCountReview,{...stock,rows:[{item:'SUGAR-KG',bookQty:'100',countQty:'90',sellPriceBDT:'100'}]},
  'COUNT_VARIANCE_OUTSIDE_APPROVED_TOLERANCE','count_variance');
 blocks(checks.stockCountReview,{...stock,rows:[{item:'SUGAR-KG',bookQty:'100',countQty:'99',sellPriceBDT:'100'}]},
  'COUNT_VARIANCE_WITHIN_APPROVED_TOLERANCE','count_variance_small');
 blocks(checks.stockCountReview,{...stock,counter:'Warehouse keeper'},'COUNTER_IS_STOREKEEPER','counter_is_storekeeper');
 blocks(checks.stockCountReview,{...stock,witness:'Independent stock counter'},'WITNESS_IS_COUNTER','same_witness');
});
test('W-03 count freeze, missing policy, duplicate count item and false authorization are stopped',()=>{
 const {approvedTolerancePercent,approvedToleranceValueBDT,...noPolicy}=stock;
 const r=checks.stockCountReview(noPolicy);
 assert.equal(r.status,'BLOCK');
 assert.deepEqual(r.needs,['count_tol_pct','count_tol_max']);
 blocks(checks.stockCountReview,{...stock,movementDuringCount:true},'COUNT_MOVEMENT_DURING_FREEZE_REVIEW');
 blocks(checks.stockCountReview,{...stock,movementDuringCount:undefined},'COUNT_FREEZE_CONFIRMATION_REQUIRED');
 assert.throws(()=>checks.stockCountReview({...stock,rows:[stock.rows[0],stock.rows[0]]}),/MISSING_OR_DUPLICATE_COUNT_ITEM/);
 assert.throws(()=>checks.stockCountReview({...stock,rows:[{...stock.rows[0],countQty:'-1'}]}),/INVALID_DECIMAL/);
});
test('R-01 full candidate showroom baseline, including safe freezer temperature and receipt link',()=>{
 const r=checks.showroomSourceReview(shop);
 assert.equal(r.status,'REVIEW_READY_NOT_APPROVED',JSON.stringify(r.blockers));
 assert.deepEqual(r.blockers,[]);
 assert.deepEqual(r.legacyFlags,[]);
 assert.equal(r.evidence.fridgesChecked,2);
 assert.equal(r.evidence.categoryTotalBDT,'1000.00');
 assert.equal(r.approved,false);
});
test('R-01 first four source warning types: opening float/imprest, receipt shortage, cleaner conflict',()=>{
 blocks(checks.showroomSourceReview,{...shop,openCountedBDT:'499'},'OPEN_DRAWER_FLOAT_MISMATCH','open_float_diff');
 blocks(checks.showroomSourceReview,{...shop,imprestReceiptsBDT:'199'},'OPEN_IMPREST_MISMATCH','open_imprest_diff');
 blocks(checks.showroomSourceReview,{...shop,receipts:[{challanRef:'TRANS-01',writtenQty:'20',countedQty:'18'}]},'GOODS_RECEIPT_SHORTAGE','receipt_short');
 blocks(checks.showroomSourceReview,{...shop,cleaning:[{doer:'Manager',verifier:'Manager'}]},'CLEANER_IS_CHECKER','same_person_cleaning');
});
test('R-01 remaining seven source warning types: sales cash, signatures, waste, expiry and float',()=>{
 blocks(checks.showroomSourceReview,{...shop,totalSalesBDT:'999'},'CATEGORY_SALES_TOTAL_MISMATCH','cat_total_mismatch');
 blocks(checks.showroomSourceReview,{...shop,secondCashCountBDT:'700'},'SECOND_CASH_COUNT_MISMATCH','second_count_mismatch');
 blocks(checks.showroomSourceReview,{...shop,witness:'Shop maker'},'WITNESS_IS_WRITER','witness_is_maker');
 blocks(checks.showroomSourceReview,{...shop,floatLeftBDT:'499'},'CLOSING_FLOAT_DIFFERS','float_left_diff');
 blocks(checks.showroomSourceReview,{...shop,stock:[{wasteQty:'2',wasteApprovedBy:'Shop maker',expiredLossBDT:'0'}]},'SELF_APPROVED_WASTE','self_waste_approval');
 blocks(checks.showroomSourceReview,{...shop,stock:[{wasteQty:'0',wasteApprovedBy:'Manager',expiredLossBDT:'300'}]},'EXPIRED_PRODUCT_LOSS','expired_loss');
 blocks(checks.showroomSourceReview,{...shop,secondSigner:'Shop maker'},'SECOND_SIGNER_IS_WRITER','second_sig_is_maker');
});
test('R-01 policy omissions, expiry/isolation risk and out-of-range fridge are fail-closed',()=>{
 const {approvedDrawerFloat,approvedImprest,...noLimits}=shop;
 const r=checks.showroomSourceReview(noLimits);
 assert.equal(r.status,'BLOCK');
 assert.ok(r.needs.includes('drawer_float')&&r.needs.includes('imprest'));
 blocks(checks.showroomSourceReview,{...shop,openingSafetyOk:false},'OPENING_SAFETY_NOT_CONFIRMED');
 blocks(checks.showroomSourceReview,{...shop,expiredProductIsolated:false},'EXPIRED_STOCK_ISOLATION_NOT_CONFIRMED');
 blocks(checks.showroomSourceReview,{...shop,fridges:[{name:'Display',temperatureC:'9',minTempC:'0',maxTempC:'5'}]},
  'FRIDGE_TEMPERATURE_OUTSIDE_POLICY:0');
 const missingFridge={...shop,fridges:[{name:'Display',temperatureC:'4'}]};
 assert.ok(checks.showroomSourceReview(missingFridge).needs.includes('fridge1_min'));
 assert.throws(()=>checks.showroomSourceReview({...shop,fridges:[{name:'F',temperatureC:'bogus'}]}),/INVALID_DECIMAL|INVALID_TEMPERATURE/);
});
test('new optional add-on forms do not become routine daily paperwork for every showroom',()=>{
 assert.equal(paperops.TEMPLATES.length,32);
 const cfg={date:'2026-11-22',industry:'sweets_bakery',businessName:'Fake Sweets',
 sites:[{id:'shop',name:'Fake shop',kind:'showroom'},{id:'factory',name:'Fake factory',kind:'factory'}]};
 assert.deepEqual(kit.planDay({...cfg,events:[]}).forms.map(f=>f.formId),['OPS-DAILY']);
 const active=kit.planDay({...cfg,events:[
   {type:'transfer_detail',siteId:'factory',eventId:'W02-01'},
   {type:'shop_open_controls',siteId:'shop',eventId:'R01-01'}
 ]});
 assert.deepEqual(active.forms.map(f=>f.formId),['OPS-DAILY','TRANSFER-DETAIL','SWEETS-SHOP-CHECK']);
 assert.equal(active.dailyCount,1);
 assert.equal(active.eventCount,2);
 const html=kit.printKit(active,{lang:'bn',tableRows:3});
 assert.equal((html.match(/class="paperops-kit-sheet"/g)||[]).length,3);
 assert.throws(()=>kit.planDay({...cfg,industry:'ecommerce',events:[{type:'shop_open_controls',siteId:'shop',eventId:'BAD-1'}]}),/EVENT_UNSUPPORTED_FOR_INDUSTRY/);
});
