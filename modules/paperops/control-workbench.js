/* Offline draft evidence workbench. These fields are operator-entered trial data, never ERP posts. */
(function(root,factory){
  'use strict';
  const api=factory(typeof module==='object'&&module.exports
    ? require('./paper-controls.js') : (root&&root.CORE10_PAPER_CONTROLS));
  if(typeof module==='object'&&module.exports)module.exports=api;
  if(root)root.CORE10_PAPER_WORKBENCH=api;
})(typeof globalThis==='object'?globalThis:this,function(gates){
  'use strict';
  const f=(key,bn,en,type='text')=>Object.freeze({key,bn,en,type});
  const FLOW=Object.freeze([
    {id:'cashHandover',bn:'ক্যাশ হস্তান্তর যাচাই',en:'Cash handover',source:'C-01',
      fields:[f('closingRef','দৈনিক ক্লোজিং নং','Daily close ref'),f('sealRef','সিল / ব্যাগ নং','Bag / seal ref'),
       f('cashLedgerRef','ক্যাশ লেজার নং','Cash ledger ref'),f('dispatchedCash','হস্তান্তর নগদ ৳','Cash sent BDT','money'),
       f('receivedCash','গ্রহণে গণনাকৃত ৳','Cash received BDT','money'),
       f('floatLeft','রেখে যাওয়া খুচরা ৳','Float left BDT','money'),
       f('approvedFloat','অনুমোদিত খুচরা ৳','Approved float BDT','money'),
       f('sentBy','প্রেরক','Sender'),f('receivedBy','স্বতন্ত্র গ্রহীতা','Independent recipient')]},
    {id:'stockTransfer',bn:'মালামাল স্থানান্তর যাচাই',en:'Goods transfer',source:'W-02',
      fields:[f('challanRef','চালান নং','Challan ref'),
       f('sourceLocation','প্রেরক স্থান','Origin'),f('destinationLocation','গ্রহীতা স্থান','Destination'),
       f('issuedBy','প্রেরক ব্যক্তি','Issued by'),f('receivedBy','স্বতন্ত্র গ্রহীতা','Received by'),
       f('sentQty','পাঠানো পরিমাণ','Sent qty','qty'),f('receivedQty','পাওয়া পরিমাণ','Received qty','qty'),
       f('foodGoods','খাদ্য পণ্য?','Food goods?','bool'),f('productionDate','উৎপাদনের তারিখ','Production date'),
       f('grade','পণ্যের গ্রেড','Grade'),f('outsideApprovedDemand','অনুমোদিত চাহিদার বাইরে?','Outside approved demand?','bool'),
       f('demandExceptionRef','অতিরিক্ত চাহিদার অনুমোদন নং','Outside demand exception ref'),
       f('approvedBy','অনুমোদনকারী','Approver'),f('damageReported','ড্যামেজ হয়েছে?','Damage reported?','bool'),
       f('damageRef','ড্যামেজ রিপোর্ট নং','Damage ref'),f('liabilityDecision','দায় নির্ধারণের সিদ্ধান্ত','Liability decision')]},
    {id:'goodsReceived',bn:'GRN ও QC যাচাই',en:'GRN / QC',source:'P-04',
      fields:[f('poRef','PO নং','PO ref'),f('grnRef','GRN নং','GRN ref'),
       f('invoiceRef','সাপ্লায়ার বিল নং','Supplier invoice ref'),
       f('orderedQty','অর্ডার পরিমাণ','Ordered qty','qty'),f('deliveredQty','সরবরাহ পরিমাণ','Delivered qty','qty'),
       f('acceptedQty','গ্রহণ পরিমাণ','Accepted qty','qty'),f('heldQty','আটক পরিমাণ','Held qty','qty'),
       f('returnedQty','ফেরত পরিমাণ','Returned qty','qty'),
       f('receivedBy','গ্রহণকারী','Receiver'),f('qcBy','পৃথক QC যাচাইকারী','Independent QC checker'),
       f('heldSegregated','আটক পণ্য আলাদা করা?','Held stock segregated?','bool'),
       f('qcPassed','QC অনুমোদন?','QC released?','bool'),
       f('rateChanged','দর বদলেছে?','Rate changed?','bool'),
       f('rateApprovalRef','দর সংশোধনের অনুমোদন','Rate approval ref'),f('rateApprovedBy','দর অনুমোদনকারী','Rate approver')]},
    {id:'factoryBatch',bn:'কারখানা ব্যাচ যাচাই',en:'Factory batch check',source:'F-05',
      fields:[f('batchRef','ব্যাচ নং','Batch ref'),f('recipeVersion','অনুমোদিত রেসিপি ভার্সন','Approved recipe version'),
       f('issueSlipRef','ইস্যু স্লিপ নং','Issue slip ref'),
       f('issuedKg','ইস্যু কেজি','Issued kg','qty'),f('usedKg','ব্যবহৃত কেজি','Used kg','qty'),
       f('returnedKg','ফেরত কেজি','Returned kg','qty'),f('expectedOutputKg','প্রত্যাশিত আউটপুট কেজি','Expected output kg','qty'),
       f('goodOutputKg','ভালো আউটপুট কেজি','Good output kg','qty'),
       f('secondGradeKg','২য় গ্রেড কেজি','Second grade kg','qty'),f('wasteKg','অপচয় কেজি','Waste kg','qty'),
       f('prestartSafetyOk','শুরুতে নিরাপত্তা পরীক্ষা ঠিক?','Pre-start safe?','bool'),
       f('scaleChecked','পাল্লা যাচাই হয়েছে?','Scale checked?','bool'),
       f('producedBy','কারিগর','Producer'),f('yieldCheckedBy','স্বতন্ত্র ফলন যাচাইকারী','Yield checker'),
       f('qcReleased','QC মুক্ত হয়েছে?','QC released?','bool'),f('qcRef','QC নং','QC ref'),
       f('yieldTestRef','ফলন টেস্ট নং','Yield test ref')]},
    {id:'discountApproval',bn:'ডিসকাউন্ট সীমা যাচাই',en:'Discount policy check',source:'S-02',
      fields:[f('saleRef','মূল বিক্রির নং','Source sale ref'),
       f('originalAmount','মূল বিক্রি ৳','Original amount BDT','money'),
       f('discountAmount','ডিসকাউন্ট ৳','Discount BDT','money'),
       f('approvedLimit','অনুমোদিত সীমা ৳','Approved limit BDT','money'),
       f('preparedBy','প্রস্তুতকারী','Prepared by'),f('approvedBy','অনুমোদনকারী','Approved by'),
       f('approvalRef','অনুমোদন স্লিপ নং','Approval slip ref')]},
    {id:'returnRefund',bn:'রিটার্ন ও রিফান্ড যাচাই',en:'Return / refund check',source:'S-03',
      fields:[f('originalSaleRef','মূল বিক্রির নং','Original sale ref'),
       f('returnRef','রিটার্ন নং','Return ref'),f('rootCause','মূল কারণ','Root cause'),
       f('refundAmount','ফেরতের টাকা ৳','Refund amount BDT','money'),
       f('refundLimit','অনুমোদিত সীমা ৳','Refund limit BDT','money'),
       f('productReturned','পণ্য ফেরত এসেছে?','Product returned?','bool'),
       f('productQuarantined','ফেরত পণ্য আলাদা রাখা?','Goods quarantined?','bool'),
       f('foodIllnessReported','খেয়ে অসুস্থতার অভিযোগ?','Illness reported?','bool'),
       f('managementEscalated','ম্যানেজমেন্টকে জানানো?','Management escalated?','bool'),
       f('receivedBy','ফেরত গ্রহণকারী','Received by'),f('approvedBy','রিফান্ড অনুমোদনকারী','Approved by'),
       f('approvalRef','রিফান্ড অনুমোদন নং','Approval ref'),
       f('paidBy','টাকা প্রদানকারী','Refund paid by'),f('refundVoucherRef','পেমেন্ট ভাউচার নং','Refund voucher ref')]},
    {id:'customerOrder',bn:'কাস্টমার অর্ডার ও অগ্রিম যাচাই',en:'Customer order / advance',source:'S-01',
      fields:[f('orderRef','অর্ডার নং','Order ref'),f('boardRef','অর্ডার বোর্ড নং','Order board ref'),
       f('deliveryDate','ডেলিভারি তারিখ','Delivery date'),f('takenBy','অর্ডার গ্রহণকারী','Taken by'),
       f('boardCheckedBy','পৃথক অর্ডার যাচাইকারী','Board checked by'),
       f('totalAmount','অর্ডার মোট ৳','Order total BDT','money'),
       f('discountAmount','ডিসকাউন্ট ৳','Discount BDT','money'),
       f('advanceAmount','অগ্রিম ৳','Advance BDT','money'),
       f('advanceReceiptRef','অগ্রিম রসিদ নং','Advance receipt ref'),
       f('discountApprovalRef','ছাড়ের স্লিপ নং','Discount slip ref'),
       f('notCollected','অর্ডার নেওয়া হয়নি?','Not collected?','bool'),
       f('uncollectedDecisionRef','না নেওয়া অর্ডারের সিদ্ধান্ত নং','Uncollected decision ref')]}
  ]);
  function evaluate(flowId,input){
    const schema=FLOW.find(x=>x.id===flowId);
    if(!schema)throw Error('UNKNOWN_CONTROL_FLOW');
    if(!input||typeof input!=='object'||Array.isArray(input))throw Error('INVALID_CONTROL_INPUT');
    const allowed=new Set(schema.fields.map(x=>x.key));
    if(Object.keys(input).some(x=>!allowed.has(x)))throw Error('UNRECOGNIZED_CONTROL_FIELD');
    if(!gates||typeof gates[flowId]!=='function')throw Error('CONTROL_GATE_UNAVAILABLE');
    const result=gates[flowId](input);
    return {flowId,source:schema.source,kind:'DRAFT_CONTROL_REVIEW',
      result,canPost:false,canApprove:false};
  }
  return Object.freeze({FLOWS:FLOW,evaluate});
});
