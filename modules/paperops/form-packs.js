/* Source-traced draft form packs: original sweets control recovery plus 10 CORE-10 industries.
 * NOT legally certified, field-parity approved, or ERP-connected.
 */
(function(root, factory) {
  'use strict';
  const registry = typeof module === 'object' && module.exports
    ? require('./paperops.js') : root && root.CORE10_PAPEROPS;
  const forms = factory();
  if (!registry || typeof registry.registerTemplates !== 'function') throw Error('PAPEROPS_BASE_REQUIRED');
  registry.registerTemplates(forms);
  if (typeof module === 'object' && module.exports) module.exports = forms;
  if (root) root.CORE10_PAPEROPS_PACKS = forms;
})(typeof globalThis === 'object' ? globalThis : this, function() {
  'use strict';
  const t=(bn,en)=>({bn,en});
  const f=(key,bn,en)=>({key,label:t(bn,en),industries:['all']});
  const s=(bn,en,fields=[],lines=null)=>({title:t(bn,en),fields,table:lines});
  const tab=(bn,en,cols,rows=7)=>({title:t(bn,en),cols:cols.map(([a,b])=>t(a,b)),rows});
  const sig=(...pairs)=>pairs.map(([bn,en])=>t(bn,en));
  const COMMON_APPROVAL=sig(['প্রস্তুতকারী','Prepared by'],['স্বতন্ত্র যাচাইকারী','Independent checker']);
  return [
    {
      id:'EXP-VOUCHER',industries:['all'],status:'draft',cadence:'event',legacyRefs:['C-02'],
      title:t('ব্যয় ভাউচার — মূল ইমপ্রেস্ট প্রমাণ','Expense Voucher — Original Imprest Evidence'),
      rule:t('দৈনিক বিক্রি-ক্লোজিং থেকে আলাদা। প্রতিটি খরচের রসিদ/অনুপস্থিতির কারণ, অনুমোদিত খরচ সীমা, বিক্রির ড্রয়ার অক্ষত থাকা এবং ইমপ্রেস্ট মিল যাচাই করুন। ফর্ম তৈরি কখনো পেমেন্ট অনুমোদন নয়।',
        'Separate from daily sales close. Preserve expense receipts or reasons, approved per-line expense limit, untouched sales drawer, and fixed-imprest reconciliation. Printing never authorizes a payment.'),
      sections:[
        s('পুরোনো C-02-এর সকল ১৯টি ফিল্ড','All 19 original C-02 source fields',[
          f("time", "সময়", "Time"),
          f("sheet_no", "দৈনিক শোরুম শিট নং", "Daily showroom sheet no."),
          f("head", "খরচের খাত", "Expense head"),
          f("to", "কার কাছে / কী বাবদ", "Paid to / for"),
          f("receipt", "রসিদ সংযুক্ত", "Receipt attached"),
          f("amount", "টাকা", "Amount"),
          f("total", "মোট", "Total"),
          f("money_account_id", "Payment source", "Payment source"),
          f("receipt_photos", "রসিদ / ভাউচারের ছবি", "Receipt / voucher photos"),
          f("limit_text", "সীমা যাচাই", "Limit check"),
          f("approved_by", "সীমার উপরে হলে অনুমোদনকারী", "Approved by (when over the limit)"),
          f("no_receipt_reason", "রসিদ না থাকলে কারণ", "Reason if a receipt is missing"),
          f("drawer_untouched", "বিক্রয় ড্রয়ার থেকে কিছু নেওয়া হয়নি", "Nothing was taken from the sales drawer"),
          f("pay_mode", "কীভাবে দেওয়া হয়েছে (ফাঁকা = cash)", "Paid how (empty = cash)"),
          f("cash_morning", "সকালে নগদ", "Cash in the morning"),
          f("cash_now", "এখন নগদ (গুনে লিখুন)", "Cash now (count, then enter)"),
          f("receipts_total", "রসিদের মোট", "Receipts total"),
          f("sum_cr", "নগদ + রসিদ", "Cash + receipts"),
          f("imprest_text", "নির্ধারিত টাকার সাথে মিল", "Match with the fixed amount")
        ]),
        s('ইমপ্রেস্ট খরচের মূল লাইনের প্রমাণ','Imprest expense source lines',[],tab('রসিদ ও খরচের উৎস','Original expense lines',[
          ['খরচের খাত','Expense head'],['কার কাছে / কী বাবদ','Paid to / reason'],
          ['রসিদ আছে?','Receipt attached?'],['টাকা ৳','Amount BDT'],
          ['পেমেন্ট মাধ্যম / অ্যাকাউন্ট','Payment mode / account'],['প্রমাণ/রসিদ নং','Voucher/receipt ref']
        ],8)),
        s('সীমা / ইমপ্রেস্ট / ড্রয়ার নিয়ন্ত্রণ','Limit / imprest / sales drawer control',[
          f('policy_ref','অনুমোদিত expense_max / imprest নীতির সংস্করণ','Approved expense_max / imprest policy version'),
          f('approval_ref','সীমা ছাড়ালে স্বতন্ত্র অনুমোদনের রেফারেন্স','Independent over-limit approval source'),
          f('source_ref','ভাউচারের স্বতন্ত্র নম্বর','Independent voucher number')
        ])
      ],signatures:sig(['ব্যয় প্রস্তুতকারী','Prepared by'],
        ['স্বতন্ত্র সীমা যাচাইকারী','Independent expense policy checker'],
        ['স্বতন্ত্র টাকা প্রদানকারী','Paid by'])
    },
    {
      id:'SWT-JALEBI',industries:['sweets'],status:'draft',cadence:'event',legacyRefs:['R-02','F-04'],
      title:t('জিলাপি কাউন্টার — মাপ, ফলন ও অবিক্রিত হিসাব','Jalebi Counter — Measures, Yield & Unsold'),
      rule:t('এই ফর্ম শুধু সক্রিয় জিলাপি শিফটে। কারিগর ও পরিমাপকারী পৃথক, পাল্লা পরীক্ষিত, মালামাল ইস্যু স্লিপ বাধ্যতামূলক। অনুমোদিত ফলন/মূল্য/সীমা ছাড়া সিদ্ধান্ত দেওয়া যাবে না।','Only for active Jalebi shifts. Producer and measurer must differ; verified scale and issue slips are necessary. No tolerance conclusion without approved yield, price and limits.'),
      sections:[
        s('দায়িত্ব ও অনুমোদিত সেটিংস','Roles and approved settings',[
          f('shift','তারিখ / শিফট','Date / shift'),f('producer','জিলাপি ভাজেন যিনি','Producer / fryer'),f('measurer','পৃথক পরিমাপকারী','Independent measurer'),
          f('scale','পাল্লা পরীক্ষার ফল / রেফারেন্স','Scale calibration result / ref'),
          f('issue_ref','ইস্যু স্লিপ নং','Material issue slip ref'),
          f('base_pct','অনুমোদিত খামির থেকে ময়দা রূপান্তর %','Approved dough-to-flour conversion %'),
          f('yield_ref','অনুমোদিত ফলন টেস্ট নং ও কেজি/কেজি','Approved yield test ref & kg per kg'),
          f('unit_price','অনুমোদিত বিক্রয় মূল্য (৳/কেজি)','Approved selling price BDT/kg'),
          f('tolerance_ref','অনুমোদিত পার্থক্যের সীমার রেফারেন্স','Approved tolerance policy reference')
        ]),
        s('খোলা, বন্ধ ও ইস্যু','Opening, closing and issued',[],tab('পরিমাপ (ইউনিট লিখুন)','Measures (write units)',[
          ['উপাদান','Material'],['খোলা','Opening'],['প্রাপ্তি','Issue / received'],['বন্ধ','Closing'],['ব্যবহার','Used'],['একক','Unit']
        ],5)),
        s('ফলন ও হিসাব','Yield and reconciliation',[
          f('dough_gap','খামিরের পার্থক্য = খোলা − বন্ধ','Dough delta = opening − closing'),
          f('flour_used','ময়দা ব্যবহার = ইস্যু + খামির পার্থক্য × ১০০ / অনুমোদিত %','Flour used = issued + dough delta × 100 / approved %'),
          f('expected','প্রত্যাশিত জিলাপি = ময়দা ব্যবহার × অনুমোদিত ফলন','Expected Jalebi = flour used × approved yield'),
          f('sold','বিক্রিত ওজন = বিক্রয় ৳ / অনুমোদিত কেজি মূল্য','Sold weight = sales BDT / approved price per kg'),
          f('unsold','রাতে অবিক্রিত জিলাপি (ওজন)','Unsold Jalebi at close (weighed)'),
          f('samples','নমুনা / ভাঙা (ওজন)','Samples and broken (weight)'),
          f('actual','প্রকৃত = বিক্রি + অবিক্রিত + নমুনা','Actual = sold + unsold + samples'),
          f('variance','প্রকৃত − প্রত্যাশিত / কারণ / অনুমোদন','Actual minus expected / cause / approval'),
          f('oil','তেল খরচ = প্রাপ্তি + খোলা − বন্ধ','Oil used = issued + opening − closing'),
          f('syrup','রস খরচ = প্রাপ্তি + খোলা − বন্ধ','Syrup used = received + opening − closing'),
          f('unsold_decision','অবিক্রিত পণ্যের সিদ্ধান্ত / দিন-ট্যাগ / অপচয় নং','Unsold disposition / date-tag / wastage ref')
        ])
      ],signatures:sig(['কারিগর','Producer'],['পৃথক পরিমাপকারী','Independent measurer'],['সিদ্ধান্ত অনুমোদনকারী','Independent approver'])
    },
    {
      id:'STK-LEDGER',industries:['all'],status:'draft',cadence:'continuous',legacyRefs:['W-04','W-03'],
      title:t('স্টক লেজার — আইটেম, লট ও লোকেশন','Stock Ledger — Item, Lot & Location'),
      rule:t('এটি চলমান খাতা; প্রতি লেনদেনে আলাদা নতুন পৃষ্ঠা নয়। প্রতিটি প্রাপ্তি/ইস্যু মূল কাগজের নম্বরসহ, খোলা + প্রাপ্তি − ইস্যু = বন্ধ। গণনার গরমিল অনুমোদন ছাড়া সমন্বয় নয়।','A continuing ledger, not a new form per transaction. Each movement needs its source reference. Opening + in − out = closing. Count discrepancies do not authorize an adjustment.'),
      sections:[
        s('লেজার পরিচয়','Ledger identity',[
          f('item','পণ্য / আইটেম কোড ও একক','Item code / unit'),f('location','স্টক লোকেশন / বিন','Stock location / bin'),
          f('lot','ব্যাচ / লট / মেয়াদ (যদি প্রয়োজন)','Lot / batch / expiry if applicable'),
          f('opening','প্রারম্ভিক ব্যালেন্স ও আগের পৃষ্ঠা নং','Opening balance and previous page ref')
        ]),
        s('চলমান স্টক লাইন','Continuous stock movements',[],tab('প্রতি লাইন একটি উৎস নং','Each line has a source reference',[
          ['তারিখ','Date'],['GRN/ইস্যু/সমন্বয় নং','GRN / issue / adjustment ref'],['কারণ','Reason'],['প্রাপ্তি','In'],['ইস্যু','Out'],['বাকি','Balance'],['স্বাক্ষর','Initials']
        ],12)),
        s('মাসিক মিল ও পরের পৃষ্ঠা','Periodic count / carry forward',[
          f('physical','গণনায় পাওয়া পরিমাণ','Physical count'),f('difference','গণনা − লেজার','Count minus book'),
          f('count_sheet','গরমিল হলে স্টক কাউন্ট শিট নং','Stock count sheet ref for variance'),
          f('approval','সমন্বয় অনুমোদন নং / পরবর্তী পৃষ্ঠা','Adjustment approval and next page')
        ])
      ],signatures:COMMON_APPROVAL
    },
    {
      id:'PUR-BILL-MATCH',industries:['all'],status:'draft',cadence:'event',legacyRefs:['P-05','P-03','P-04'],
      title:t('PO–GRN–বিল যাচাই ও পেমেন্ট গেট','PO–GRN–Invoice Match & Payment Gate'),
      rule:t('PO, গ্রহণের নথি ও সাপ্লায়ারের বিল মিলবে; অমিল থাকলে পেমেন্ট আটকে তদন্ত। এই শিট টাকা পরিশোধের অনুমোদন নয়; স্বতন্ত্র অনুমোদন ও মূল ভাউচার লাগবে।','Match order, accepted receipt and supplier invoice. Hold payment on discrepancies. This sheet is not payment authority; independent approval and voucher remain necessary.'),
      sections:[
        s('তিনটি মূল দলিল','Three source documents',[
          f('po','পারচেজ অর্ডার নং','Purchase order ref'),f('grn','GRN / QC রিলিজ নং','GRN / QC release ref'),
          f('bill','সাপ্লায়ারের বিল নং','Supplier invoice ref'),f('supplier','সাপ্লায়ার ও ব্যাংক অ্যাকাউন্ট যাচাই','Supplier and verified payment account')
        ]),
        s('পণ্যের পরিমাণ, দর ও মোটের মিল','Match quantities, rates and totals',[],tab('মূল দলিল থেকে মিল','Three-document comparison',[
          ['পণ্য / একক','Item / unit'],['PO পরিমাণ / দর','PO qty / rate'],['QC গৃহীত','QC accepted'],['বিল পরিমাণ / দর','Invoice qty / rate'],['পার্থক্য','Difference'],['ব্যবস্থা','Resolution']
        ],7)),
        s('আটক ও পেমেন্ট সিদ্ধান্ত','Hold and payment gate',[
          f('po_total','PO মোট ৳','PO total BDT'),f('accepted_total','গৃহীত পণ্যের মোট ৳','Accepted value BDT'),
          f('invoice_total','বিল মোট ৳','Invoice total BDT'),f('hold','অমিল হলে পেমেন্ট স্থগিত করা হয়েছে?','Payment placed on hold for mismatch?'),
          f('debit','ঘাটতি/ফেরত ডেবিট নোট নং','Shortage / return debit note'),
          f('decision','দলিল মিল ও পেমেন্ট অনুমোদন নং','Independent match / payment approval ref'),
          f('voucher','স্বতন্ত্র পেমেন্ট ভাউচার নং','Separate payment voucher ref')
        ])
      ],signatures:sig(['বিল যাচাইকারী','Invoice checker'],['GRN যাচাইকারী','Receiving/QC checker'],['পেমেন্ট অনুমোদনকারী','Payment approver'])
    },
    {
      id:'PUR-COMPARE',industries:['all'],status:'draft',cadence:'event',legacyRefs:['P-02'],
      title:t('কোটেশন তুলনা ও সাপ্লায়ার নির্বাচন','Quotation Comparison & Supplier Selection'),
      rule:t('একাধিক মূল্য, শর্ত, ডেলিভারি ও গুণমান তুলনা করুন। সবচেয়ে কম দর না নিলে কারণ লিখুন। একটিমাত্র দর বা সীমা ছাড়ানো ক্রয় হলে স্বতন্ত্র অনুমোদন লাগবে। সীমা অনুমোদিত সেটিংস থেকে নিতে হবে।','Compare rates, terms, lead time and quality. Justify non-lowest choices. Single quote or out-of-policy procurement needs independent approval and an approved threshold.'),
      sections:[
        s('চাহিদা ও নিয়ম','Need and policy',[
          f('requisition','PR নং / চাহিদা / পরিমাণ','PR ref / need / quantity'),
          f('limit','কোটেশন তুলনার অনুমোদিত সীমা','Approved comparison threshold'),
          f('collector','দর সংগ্রহকারী','Quotation collector')
        ]),
        s('সরবরাহকারীর তুলনা','Supplier comparison',[],tab('কোটেশনের প্রমাণ','Quotation evidence',[
          ['সাপ্লায়ার','Supplier'],['কোটেশন নং','Quote ref'],['ইউনিট দর','Unit price'],['ডেলিভারি','Delivery'],['পেমেন্ট শর্ত','Payment terms'],['QC/মান','Quality'],['মন্তব্য','Notes']
        ],6)),
        s('চূড়ান্ত সিদ্ধান্ত','Selection decision',[
          f('lowest','সবচেয়ে কম অনুমোদিত দর','Lowest compliant rate'),
          f('selected','নির্বাচিত সাপ্লায়ার ও দর','Selected supplier and rate'),
          f('reason','সর্বনিম্ন নয় / একটিমাত্র দর হলে কারণ','Reason for higher rate / single quote'),
          f('approved','স্বতন্ত্র অনুমোদন ও PO রেফারেন্স','Independent approval and PO ref')
        ])
      ],signatures:sig(['দর সংগ্রহকারী','Collected by'],['নির্বাচন যাচাইকারী','Checked by'],['ক্রয় অনুমোদনকারী','Approved by'])
    },
    {
      id:'SLS-ORDER',industries:['all'],status:'draft',cadence:'event',legacyRefs:['S-01'],
      title:t('কাস্টমার অর্ডার ও অগ্রিম / ডেলিভারি','Customer Order, Advance & Fulfilment'),
      rule:t('অর্ডারের একটিই রেফারেন্স নম্বর বিক্রি, কারখানা, ডেলিভারি ও অগ্রিমের খাতায় ব্যবহার করুন। ছাড়, ডেলিভারি বা অগ্রিম ব্যতিক্রম হলে পৃথক অনুমোদন প্রমাণ রাখুন।','Use one order reference across customer, factory, delivery and advance books; approvals remain separate for exceptional discounts/refunds.'),
      sections:[
        s('অর্ডারের পরিচয়','Order details',[
          f('customer','ক্রেতা / যোগাযোগ','Customer / contact'),f('channel','শোরুম / অনলাইন / অন্য চ্যানেল','Sales channel'),
          f('order_no','অর্ডার ও বোর্ড নং','Order and board reference'),
          f('date','প্রতিশ্রুত ডেলিভারি তারিখ / সময়','Promised delivery date / time'),
          f('factory','কারখানায় পাঠানোর নং / সময়','Factory handoff ref / time')
        ]),
        s('পণ্যের তালিকা','Order items',[],tab('অর্ডার আইটেম','Order lines',[
          ['আইটেম','Item'],['বর্ণনা/ডিজাইন','Description / design'],['পরিমাণ','Quantity'],['দর','Rate'],['মোট','Line amount']
        ],7)),
        s('অগ্রিম, বাকি, ডেলিভারি','Advance and fulfilment',[
          f('gross','অর্ডারের মোট ৳','Order total BDT'),
          f('discount','অনুমোদিত ছাড় / স্লিপ নং','Discount and approval ref'),
          f('advance','অগ্রিম ৳ / পেমেন্ট মাধ্যম ও রেফারেন্স','Advance amount / payment ref'),
          f('balance','বাকি ৳ = মোট − ছাড় − অগ্রিম','Outstanding = total minus discount minus advance'),
          f('delivered','হস্তান্তর নং / গ্রহণকারীর নাম','Delivery ref and recipient'),
          f('not_collected','গ্রহণ না করলে স্টক / অগ্রিমের সিদ্ধান্ত','Uncollected order stock/advance disposition')
        ])
      ],signatures:sig(['অর্ডার গ্রহণকারী','Taken by'],['অর্ডার বোর্ড যাচাইকারী','Independent checker'],['ডেলিভারি গ্রহণকারী','Delivered to'])
    },
    {
      id:'SLS-RETURN',industries:['all'],status:'draft',cadence:'event',legacyRefs:['S-03'],
      title:t('রিটার্ন, অভিযোগ, রিফান্ড ও কারণ তদন্ত','Return, Complaint, Refund & Root Cause'),
      rule:t('রিটার্ন পণ্য আলাদা ও QC পরীক্ষা ছাড়া পুনর্বিক্রি নয়। রিফান্ড সীমা, অনুমোদনকারী এবং টাকা প্রদানকারী পৃথক নথিভুক্ত করুন; অসুস্থতার অভিযোগ তাৎক্ষণিক ব্যবস্থাপনায় তুলুন।','Quarantine returned goods pending quality decision. Record approval threshold and separation of refund approver/payer. Escalate illness reports immediately.'),
      sections:[
        s('অভিযোগ','Complaint',[
          f('customer','ক্রেতা / যোগাযোগ','Customer / contact'),f('sale_ref','মূল বিক্রির মেমো নং','Original sales memo'),
          f('item','আইটেম, ব্যাচ / লট','Item and batch/lot'),
          f('cause','অভিযোগ / স্বাস্থ্য ও নিরাপত্তা ঝুঁকি','Complaint / health and safety risk'),
          f('intake','পণ্য গ্রহণের সময় ও স্থান','Return intake time and quarantine location')
        ]),
        s('ফেরত বা বদল','Return / replacement',[],tab('ফেরত পণ্যের পরিমাণ ও সিদ্ধান্ত','Returned goods',[
          ['পণ্য','Item'],['ফেরত পরিমাণ','Returned qty'],['QC রায়','QC result'],['আলাদা রাখা','Quarantined'],['ফেরত / অপচয় নং','Return / waste ref']
        ],5)),
        s('রিফান্ড ও সমাধান','Refund and resolution',[
          f('refund','ফেরতের টাকা ৳ ও অনুমোদিত সীমা','Refund BDT and policy threshold'),
          f('decision','স্বতন্ত্র অনুমোদন নং / সময়','Independent approver / time'),
          f('payment','টাকা প্রদানের ভাউচার / লেজার নং','Refund voucher / ledger ref'),
          f('root','কারণ তদন্ত / সংশোধনী ব্যবস্থা','Root cause and corrective action'),
          f('resolution','কাস্টমার সমাধান নিশ্চিতকরণ','Customer resolution confirmation')
        ])
      ],signatures:sig(['অভিযোগ গ্রহণকারী','Received by'],['QC যাচাইকারী','QC checker'],['রিফান্ড অনুমোদনকারী','Refund approver'])
    },
    {
      id:'FIN-SETTLEMENT',industries:['all'],status:'draft',cadence:'periodic',legacyRefs:['C-04','S-04'],
      title:t('ডিজিটাল পেমেন্ট সেটেলমেন্ট মিল','Digital Payment Settlement Reconciliation'),
      rule:t('মূল বিক্রি/অনলাইন খাতা, PSP/কার্ড/ব্যাংক স্টেটমেন্ট, চার্জ ও প্রকৃত জমা আলাদা করে মিলাবেন। স্টেটমেন্ট না পেলে মিল সম্পন্ন হিসেবে দেখাবেন না।','Reconcile shop/online ledger to provider statement, fees and actual deposit. Missing statement blocks signoff.'),
      sections:[
        s('প্রমাণ','Evidence',[
          f('period','সেটেলমেন্ট সপ্তাহ / তারিখ','Settlement period'),f('channel','বিকাশ/নগদ/কার্ড/অ্যাপ/ব্যাংক','Payment platform'),
          f('statement','অফিসিয়াল স্টেটমেন্ট নং / তারিখ','Official statement ref/date'),
          f('ledger','শোরুম/অনলাইন খাতার রেফারেন্স','Shop/online ledger ref')
        ]),
        s('চ্যানেলভিত্তিক মিল','Channel-level reconciliation',[],tab('কাগজ → স্টেটমেন্ট → ব্যাংক','Paper → Statement → Bank',[
          ['চ্যানেল','Channel'],['খাতায় মোট','Paper amount'],['স্টেটমেন্ট মোট','Statement gross'],['চার্জ','Fees'],['ব্যাংকে জমা','Bank received'],['দুই পার্থক্য','Two variances']
        ],8)),
        s('গরমিল','Discrepancies',[
          f('missing','যে লাইন স্টেটমেন্টে/খাতায় নেই','Unmatched statement/paper entries'),
          f('personal','ব্যক্তিগত নাম্বারে টাকা এসেছে?','Personal payment destination?'),
          f('action','গরমিল সমাধান / অপেক্ষমাণ কাগজ নং','Resolution / pending document refs')
        ])
      ],signatures:COMMON_APPROVAL
    },
    {
      id:'FIN-AR-AGING',industries:['all'],status:'draft',cadence:'periodic',legacyRefs:['C-05','S-06'],
      title:t('বাকি, অগ্রিম ও ক্রেডিট সীমার পর্যালোচনা','Receivables, Advances & Credit Limits'),
      rule:t('০–৩০, ৩১–৬০, ৬০ দিনের বেশি ভাগের যোগ মোট প্রাপ্যের সমান। ক্রেডিট সীমা অনুমোদিত সেটিংস থেকে নিতে হবে; অতিরিক্ত বাকি হলে নতুন ক্রেডিট বন্ধের সিদ্ধান্ত লিখুন।','Age buckets must sum to total due. Credit limits require approved policy; record credit-stop decision for over-limit parties.'),
      sections:[
        s('মেয়াদ ও নীতি','Period and policy',[
          f('date','রিভিউ তারিখ','Review date'),
          f('limit_ref','পার্টিভিত্তিক অনুমোদিত সীমা / ক্রেডিট দিন','Approved per-party credit limit and terms')
        ]),
        s('পার্টির বকেয়া','Customer ageing lines',[],tab('বাকি ও বয়সের ভাগ','Due and ageing buckets',[
          ['পার্টি','Party'],['মোট বাকি','Total due'],['০–৩০ দিন','0–30 days'],['৩১–৬০','31–60 days'],['৬০+','60+ days'],['অনুমোদিত সীমা','Limit'],['ক্রেডিট বন্ধ?','Credit held?']
        ],8)),
        s('অগ্রিম ও সিদ্ধান্ত','Advances and decisions',[
          f('advances','অগ্রিম খাতার সঙ্গে মোট মিল','Advance ledger total vs summary'),
          f('overdue','বয়সের ভাগের মোট বনাম লেজারের পার্থক্য','Bucket-total mismatch'),
          f('stop','সীমার বাইরের পার্টি ও নিষেধাজ্ঞা নং','Over-limit party and credit-stop ref'),
          f('action','সংগ্রহের পরিকল্পনা ও দায়িত্বপ্রাপ্ত ব্যক্তি','Collection action / owner')
        ])
      ],signatures:COMMON_APPROVAL
    },
    {
      id:'MFG-SPEC',industries:['sweets','paint','general_manufacturing'],status:'draft',cadence:'master',legacyRefs:['F-02','F-03','F-04'],
      title:t('প্রোডাক্ট স্পেসিফিকেশন, গ্রেড ও মেয়াদের মাস্টার কার্ড','Product Spec, Grade & Shelf-Life Master'),
      rule:t('এটি দৈনিক শিট নয়। অনুমোদিত ভার্সন ফ্যাক্টরির ব্যাচে রেফারেন্স হবে। গ্রেড, বাতিলের লক্ষণ, সংরক্ষণ ও মেয়াদের নির্দেশনা অনুমোদন ছাড়া পরিবর্তন নয়।','Versioned master only; batches reference the approved version. Grades, rejection criteria, storage and shelf life require signoff.'),
      sections:[
        s('সংস্করণ','Version identity',[
          f('product','আইটেম কোড, ক্যাটাগরি, গ্রেড','Item code, category, grade'),
          f('version','ভার্সন, কার্যকর তারিখ ও পূর্ববর্তী সংস্করণ','Version / effective date / supersedes'),
          f('formula','রেসিপি/ফর্মুলা ও ফলন টেস্ট নং','Recipe/formula and yield test refs')
        ]),
        s('গুণমান ও মেয়াদ','Quality and storage',[
          f('appearance','স্বাভাবিক রং, ওজন, স্বাদ, টেক্সচার / শেড','Approved appearance / weight / texture / shade'),
          f('reject','ছত্রাক, দুর্গন্ধ, বিদেশি বস্তু, ভুল শেড ইত্যাদি বাতিলের লক্ষণ','Rejection criteria (mold, foreign matter, wrong shade etc.)'),
          f('shelf','অনুমোদিত সংরক্ষণ শর্ত ও মেয়াদ','Approved storage and shelf-life rule'),
          f('expiry','লেবেল / দিন-ট্যাগ ও মেয়াদ যাচাই','Label / date-tag / expiry check'),
          f('revision','পরিবর্তনের কারণ ও অনুমোদন নং','Change rationale and approval ref')
        ])
      ],signatures:sig(['স্পেসিফিকেশন প্রস্তুতকারী','Spec owner'],['QC যাচাইকারী','QC checker'],['অনুমোদনকারী','Approver'])
    },
    {
      id:'FIN-MONTHLY',industries:['all'],status:'draft',cadence:'monthly',legacyRefs:['A-02'],
      title:t('মাসিক লাভ-ক্ষতি ও KPI হিসাব','Monthly Profit & Loss / KPI Review'),
      rule:t('COGS = প্রারম্ভিক স্টক + ক্রয় − সমাপনী স্টক; মোট লাভ = বিক্রি − COGS; নিট = মোট লাভ − অপারেশন ব্যয় − বেতন − ব্যাংক চার্জ। প্রাপ্য-পাওনা আলাদা লেজারের সঙ্গে মিলাতে হবে।','COGS = opening stock + purchases − closing stock. Gross = sales − COGS. Net = gross − expenses − payroll − bank charges. AR/AP must reconcile to independent ledgers.'),
      sections:[
        s('অ্যাকাউন্টিং সময়কাল','Accounting period',[
          f('month','বছর-মাস (YYYY-MM)','Year-month'),f('scope','ব্যবসা / শাখা পরিধি','Business / site scope'),
          f('books','স্টক ও ক্যাশ/ব্যাংক লেজার ক্লোজিং রেফারেন্স','Stock and cash/bank closing ledger refs')
        ]),
        s('মাসিক আর্থিক হিসাব','Monthly financial totals',[
          f('sales','মোট বিক্রি ৳','Total sales BDT'),f('open','প্রারম্ভিক স্টক ৳','Opening stock BDT'),
          f('purchases','ক্রয় ৳','Purchases BDT'),f('close','সমাপনী স্টক ৳','Closing stock BDT'),
          f('cogs','বিক্রিত পণ্যের খরচ COGS ৳','Cost of goods sold BDT'),
          f('gross','মোট লাভ ৳','Gross profit BDT'),f('expenses','অপারেশন ব্যয় ৳','Operating expenses BDT'),
          f('salary','বেতন ৳','Payroll BDT'),f('charges','ব্যাংক / পেমেন্ট চার্জ ৳','Bank/processing charges BDT'),
          f('net','নিট লাভ বা ক্ষতি ৳','Net result BDT')
        ]),
        s('লেজার ও পর্যালোচনা','Ledger matches and review',[
          f('ar','কাস্টমার প্রাপ্য ও অগ্রিমের খাতা নং','Receivables / advances ledger ref'),
          f('ap','সাপ্লায়ার পাওনা খাতা নং','Supplier payable ledger ref'),
          f('leak','ক্যাশ/স্টক গরমিল ও সংশোধন নং','Cash/stock mismatches and resolution'),
          f('action','পরবর্তী মাসের সিদ্ধান্ত / KPI','Management actions and KPIs')
        ])
      ],signatures:sig(['হিসাব প্রস্তুতকারী','Prepared by'],['স্বতন্ত্র হিসাব যাচাইকারী','Independent reviewer'],['ম্যানেজমেন্ট','Management'])
    },
    {
      id:'FIN-CASHBOOK',industries:['all'],status:'draft',cadence:'continuous',legacyRefs:['C-01','C-02'],
      title:t('ক্যাশ ও ব্যাংক ধারাবাহিক খাতা','Continuous Cash & Bank Book'),
      rule:t('প্রতিটি টাকা আসা ও যাওয়ার দলিল নং, নগদ/ব্যাংক পৃথক কলাম, দিনের ব্যালেন্স ও পূর্ব পৃষ্ঠা রেফারেন্স থাকবে। পেমেন্টের বৈধতা আলাদা ভাউচারে যাচাই করুন।','Continuous entries with references, separate cash/bank columns, opening and closing balances. Entries do not replace payment vouchers.'),
      sections:[
        s('খাতা','Account identity',[
          f('account','ক্যাশ ড্রয়ার / ব্যাংক অ্যাকাউন্ট কোড','Cash drawer / bank account'),
          f('open','প্রারম্ভিক ব্যালেন্স ও আগের পৃষ্ঠা নং','Opening balance / previous page')
        ]),
        s('দিনের লেনদেন','Day ledger',[],tab('প্রতি লেনদেনের উৎস নং বাধ্যতামূলক','Source reference for every entry',[
          ['তারিখ','Date'],['দলিল নং','Voucher ref'],['কারণ','Purpose'],['প্রাপ্তি','Money in'],['প্রদান','Money out'],['বাকি','Balance'],['যাচাই','Check']
        ],12)),
        s('শেষের মিল','Closing',[
          f('count','নগদ গণনা / ব্যাংক স্টেটমেন্ট মিল','Cash count / bank statement'),
          f('diff','পার্থক্য ও ব্যাখ্যা / তদন্ত নং','Variance / investigation'),
          f('carry','পরের পাতার শুরুর ব্যালেন্স','Carry-forward balance')
        ])
      ],signatures:COMMON_APPROVAL
    },
    {
      id:'FIN-AP-LEDGER',industries:['all'],status:'draft',cadence:'continuous',legacyRefs:['P-06','P-05'],
      title:t('সাপ্লায়ার পাওনা ও পেমেন্ট লেজার','Supplier Payables & Payment Ledger'),
      rule:t('প্রতিটি PO/GRN/বিল/পেমেন্ট রেফারেন্স ধরে পাওনা বাড়া-কমা লিপিবদ্ধ করুন। ব্যাংক অ্যাকাউন্ট পরিবর্তন যাচাই ও অনুমোদন ছাড়া নয়।','Record each bill, GRN-linked amount, debit note and payment with references. Verify supplier bank-account changes independently.'),
      sections:[
        s('সাপ্লায়ারের পরিচয়','Supplier identity',[
          f('supplier','সাপ্লায়ার/অ্যাকাউন্ট কোড','Supplier / account code'),
          f('terms','ক্রেডিট দিন ও অনুমোদিত ব্যাংক তথ্য','Credit terms and verified payment details'),
          f('open','প্রারম্ভিক পাওনা ও আগের পাতার নং','Opening due / previous page')
        ]),
        s('লেনদেন','Ledger movements',[],tab('বিল, ডেবিট ও পেমেন্ট','Bill, debit and payment',[
          ['তারিখ','Date'],['PO/GRN/বিল নং','PO / GRN / bill ref'],['বিল ৳','Bill'],['ডেবিট নোট ৳','Debit'],['পেমেন্ট ৳','Paid'],['বাকি ৳','Due'],['মেয়াদ','Due date']
        ],10)),
        s('শেষের মিল','Reconciliation',[
          f('statement','সাপ্লায়ারের স্টেটমেন্ট মিল / পার্থক্য','Supplier statement reconciliation'),
          f('cashbook','ব্যাংক/ক্যাশ খাতার পেমেন্ট লাইন নং','Bank/cash ledger payment ref')
        ])
      ],signatures:COMMON_APPROVAL
    },
    {
      id:'FIN-AR-LEDGER',industries:['all'],status:'draft',cadence:'continuous',legacyRefs:['S-06','C-05'],
      title:t('কাস্টমার প্রাপ্য ও অগ্রিম লেজার','Customer Receivables & Advance Ledger'),
      rule:t('প্রতিটি ইনভয়েস, রিটার্ন, আদায় ও অগ্রিম একবার নথিবদ্ধ করুন। পৃথক ageing ও ক্রেডিট-স্টপ রিভিউতে এই খাতার মোট ব্যবহার হবে।','Record each invoice, return, collection and advance exactly once; reconcile to ageing and credit-limit review.'),
      sections:[
        s('কাস্টমার খাতা','Customer account',[
          f('party','কাস্টমার/পার্টি কোড','Customer / party code'),
          f('credit','অনুমোদিত ক্রেডিট সীমা ও দিন','Approved credit limit and days'),
          f('opening','প্রারম্ভিক প্রাপ্য / অগ্রিম ও আগের পৃষ্ঠা','Opening receivable / advance and previous page')
        ]),
        s('লাইন','Movements',[],tab('বিক্রি, আদায়, ফেরত ও অগ্রিম','Sales, receipts, returns and advances',[
          ['তারিখ','Date'],['ইনভয়েস/রসিদ নং','Invoice/receipt ref'],['বিক্রি ৳','Sale'],['ফেরত ৳','Return'],['আদায় ৳','Collected'],['প্রাপ্য ৳','Receivable'],['অগ্রিম ৳','Advance']
        ],10)),
        s('মিল','Review',[
          f('aging','Ageing শিট নং ও ৬০+ বাকি','Ageing ref and 60+ due'),
          f('creditstop','সীমার বাইরে হলে ক্রেডিট বন্ধের সিদ্ধান্ত','Credit stop when over limit'),
          f('bankref','ব্যাংক/ক্যাশ খাতার আদায় নং','Bank/cash collection ref')
        ])
      ],signatures:COMMON_APPROVAL
    },
    {
      id:'REST-KITCHEN',industries:['restaurant'],status:'hypothesis',cadence:'event',legacyRefs:[],
      title:t('রেস্টুরেন্ট কিচেন প্রস্তুতি ও নিরাপত্তা','Restaurant Kitchen Prep & Safety'),
      rule:t('রেস্টুরেন্ট ক্যাটালগভিত্তিক প্রস্তাব। বাস্তব Food Safety, রান্না ও স্টোরেজ SOP যাচাই না করা পর্যন্ত কার্যকরী অনুমোদন নয়।','A restaurant-category hypothesis. Validate food safety, preparation and storage SOPs before operational use.'),
      sections:[
        s('শিফট ও তাপমাত্রা','Shift and temperature',[
          f('shift','শিফট, দায়িত্বপ্রাপ্ত ব্যক্তি','Shift and in-charge'),f('hygiene','পরিচ্ছন্নতা / হাত ধোয়া / স্টেশন QC','Hygiene / station checks'),
          f('storage','কোল্ড স্টোরেজ তাপমাত্রা ও QC','Cold storage temperature and QC'),
          f('hold','অসুরক্ষিত খাবার আলাদা / অপসারণ','Unsafe food segregation')
        ]),
        s('প্রস্তুতি','Preparation batch',[],tab('প্রস্তুতি ও অবশিষ্ট','Prepared and leftover',[
          ['ডিশ/উপকরণ','Dish / ingredient'],['ব্যাচ / সময়','Batch / time'],['তৈরি','Prepared'],['সার্ভড','Served'],['অবশিষ্ট','Left'],['অপচয়','Waste']
        ],8))
      ],signatures:COMMON_APPROVAL
    },
    {
      id:'RETAIL-REPLENISH',industries:['retail_wholesale'],status:'hypothesis',cadence:'event',legacyRefs:[],
      title:t('রিটেইল রি-অর্ডার ও শেলফ স্টক','Retail Replenishment & Shelf Stock'),
      rule:t('স্টক রি-অর্ডার/মেয়াদ/শেলফ গণনা ব্যবসার প্রকৃত পণ্য অনুযায়ী যাচাই করতে হবে; অনুমানভিত্তিক minimum limit নয়।','Validate reorder quantities, expiry and shelf count for each real product; no invented minimum stock level.'),
      sections:[
        s('চাহিদা','Stock need',[
          f('shelf','দোকান/শেলফ/গোডাউন','Store, shelf or warehouse'),
          f('policy','অনুমোদিত রি-অর্ডার সীমার রেফারেন্স','Approved reorder policy ref')
        ]),
        s('গণনা','Count',[],tab('পণ্যভিত্তিক রি-অর্ডার','Reorder lines',[
          ['পণ্য','Item'],['গণনা','On hand'],['বাকি অর্ডার','On order'],['চাহিদা','Demand'],['প্রস্তাব','Proposed'],['অনুমোদন নং','Approval']
        ],9))
      ],signatures:COMMON_APPROVAL
    },
    {
      id:'MFG-QC',industries:['general_manufacturing'],status:'hypothesis',cadence:'event',legacyRefs:[],
      title:t('সাধারণ ম্যানুফ্যাকচারিং ব্যাচ QC','General Manufacturing Batch QC'),
      rule:t('শিল্প ও পণ্যের নিজস্ব স্পেসিফিকেশন, স্যাম্পলিং, ত্রুটি ও লট ট্রেস নিয়ম যাচাই করতে হবে।','Industry- and product-specific specification, sample plan, defect and traceability checks are required.'),
      sections:[
        s('ব্যাচ','Batch identity',[
          f('order','ওয়ার্ক অর্ডার / ব্যাচ','Work order / batch'),
          f('spec','অনুমোদিত স্পেক ভার্সন','Approved spec version'),
          f('machine','মেশিন / লাইনের পরিচয়','Machine / line')
        ]),
        s('পরীক্ষা ও সিদ্ধান্ত','Inspection and disposition',[],tab('QC পয়েন্ট','QC checkpoints',[
          ['পরীক্ষা','Test'],['অনুমোদিত সীমা','Approved tolerance'],['পরিমাপ','Actual'],['পাস/ফেল','Pass/fail'],['রিওয়ার্ক / আটক','Rework / hold']
        ],7))
      ],signatures:COMMON_APPROVAL
    },
    {
      id:'PROJECT-DAILY',industries:['construction'],status:'hypothesis',cadence:'daily',legacyRefs:[],
      title:t('কনস্ট্রাকশন সাইট দৈনিক কাজ ও উপকরণ','Construction Site Daily Work & Materials'),
      rule:t('প্রকল্পের মাপ, নিরাপত্তা, উপকরণ, শ্রমিক এবং পরিবর্তন নির্দেশের অনুমোদন বাস্তব প্রকল্প অনুযায়ী যাচাই করুন।','Validate site measurements, safety, materials, labour and variation approval against real project practice.'),
      sections:[
        s('সাইট','Project context',[
          f('project','প্রকল্প/লোকেশন/তারিখ','Project / site / date'),
          f('supervisor','তত্ত্বাবধায়ক','Site supervisor'),
          f('safety','সেফটি পরীক্ষা / ঘটনা নং','Safety check / incident ref'),
          f('change','ভেরিয়েশন/নতুন কাজ অনুমোদন নং','Variation approval ref')
        ]),
        s('কাজ ও উপকরণ','Work performed',[],tab('কাজ, শ্রম ও স্টক','Work, labor and materials',[
          ['কাজ/ওয়ার্ক অর্ডার','Task / work order'],['মাপ/পরিমাণ','Quantity'],['শ্রমিক','Labor'],['উপকরণ ইস্যু নং','Material issue ref'],['যাচাই','Checked']
        ],9))
      ],signatures:COMMON_APPROVAL
    },
    {
      id:'TRADE-CLEARANCE',industries:['import_export'],status:'hypothesis',cadence:'event',legacyRefs:[],
      title:t('ইমপোর্ট-এক্সপোর্ট শিপমেন্ট ও ডকুমেন্ট যাচাই','Import–Export Shipment & Document Check'),
      rule:t('দেশ/পণ্য/ইনকোটার্মস, কাস্টমস ও বৈদেশিক পেমেন্টের প্রযোজ্য আইন যাচাই ছাড়া এটি কোনো কমপ্লায়েন্স অনুমোদন নয়।','Not a customs or trade compliance certificate. Verify country/product/Incoterms and payment requirements with applicable rules.'),
      sections:[
        s('শিপমেন্ট','Shipment',[
          f('shipment','শিপমেন্ট / PO / ইনভয়েস নং','Shipment / PO / invoice'),
          f('origin','উৎস ও গন্তব্য','Origin and destination'),f('incoterms','চুক্তির শর্ত / ইনকোটার্মস','Contract terms / Incoterms'),
          f('carrier','ক্যারিয়ার / BL/AWB নং','Carrier / B/L or AWB')
        ]),
        s('ডকুমেন্ট প্রমাণ','Documentation evidence',[],tab('যাচাইয়ের তালিকা','Document check',[
          ['দলিল','Document'],['নম্বর','Reference'],['প্রযোজ্য?','Applicable?'],['যাচাইকারী','Checked by'],['ঘাটতি','Gap']
        ],9))
      ],signatures:COMMON_APPROVAL
    },
    {
      id:'ECOM-FULFILL',industries:['ecommerce'],status:'hypothesis',cadence:'event',legacyRefs:[],
      title:t('ই-কমার্স অর্ডার ও COD / রিটার্ন মিল','E-commerce Fulfilment, COD & Return Match'),
      rule:t('প্ল্যাটফর্ম অর্ডার, কুরিয়ার হস্তান্তর, COD আদায়, ফি ও রিটার্ন প্রতিটি আলাদা রেফারেন্সে মিলাতে হবে।','Reconcile marketplace order, courier handoff, COD settlement, charges and returns by source reference.'),
      sections:[
        s('অর্ডার','Order sources',[
          f('order','প্ল্যাটফর্ম অর্ডার নং','Platform order ID'),
          f('invoice','ইনভয়েস নং / স্টক ইস্যু নং','Invoice / stock issue refs'),
          f('courier','কুরিয়ার ট্র্যাকিং ও হ্যান্ডওভার নং','Courier tracking / handover')
        ]),
        s('ডেলিভারি ও টাকা','Delivery and money',[],tab('অর্ডারভিত্তিক মিল','Order-level reconciliation',[
          ['অর্ডার','Order'],['অবস্থা','Status'],['COD মোট','COD gross'],['ফি','Fee'],['আদায়','Settlement'],['রিটার্ন নং','Return ref']
        ],8))
      ],signatures:COMMON_APPROVAL
    },
    {
      id:'TECH-DELIVERY',industries:['technology_digital'],status:'hypothesis',cadence:'event',legacyRefs:[],
      title:t('সফটওয়্যার ডেলিভারি, গ্রহণ ও সাপোর্ট','Technology Delivery, Acceptance & Support'),
      rule:t('চুক্তির scope, সংস্করণ, গ্রহণের পরীক্ষা, পরিবর্তন অনুরোধ ও বিলিং milestone আলাদা প্রমাণসহ রাখতে হবে।','Trace contracted scope, release version, acceptance, change request and milestone billing with source evidence.'),
      sections:[
        s('চুক্তি ও ডেলিভারি','Contract and delivery',[
          f('contract','কাস্টমার / চুক্তি / কাজের নং','Client / contract / work order'),
          f('release','রিলিজ ভার্সন / ডেলিভারি তারিখ','Release version / delivery date'),
          f('tests','গ্রহণ পরীক্ষার ফল / প্রমাণ','Acceptance test result / evidence'),
          f('change','চেঞ্জ রিকোয়েস্ট / অনুমোদন','Change request / approval')
        ]),
        s('মাইলস্টোন','Milestones',[],tab('ডেলিভারি ও গ্রহণ','Delivery/acceptance',[
          ['মাইলস্টোন','Milestone'],['প্রমাণ নং','Evidence ref'],['গ্রহণকারী','Accepted by'],['অবস্থা','Status'],['ইনভয়েস নং','Invoice ref']
        ],7))
      ],signatures:COMMON_APPROVAL
    },
    {
      id:'SERVICE-JOB',industries:['services'],status:'hypothesis',cadence:'event',legacyRefs:[],
      title:t('সার্ভিস কাজ, সময় ও কাস্টমার গ্রহণ','Service Job, Time & Client Acceptance'),
      rule:t('কাজের অনুমোদিত scope, ঘণ্টা/ফি, কাজের প্রমাণ, গ্রাহকের গ্রহণ ও বিলের রেফারেন্স মিলবে।','Connect authorized scope, time/fees, work evidence, client acceptance and invoice references.'),
      sections:[
        s('কাজের পরিচয়','Service scope',[
          f('client','গ্রাহক/কাজের অর্ডার নং','Client / work order'),
          f('scope','অনুমোদিত কাজের বিবরণ','Authorized scope'),
          f('rate','অনুমোদিত ঘণ্টা/কাজের দর','Approved time/job rate')
        ]),
        s('কাজের লগ','Delivery log',[],tab('কাজের সময় ও ফলাফল','Work log',[
          ['তারিখ','Date'],['কাজ','Activity'],['ঘণ্টা','Hours'],['ফলাফল','Deliverable'],['প্রমাণ','Evidence ref']
        ],8)),
        s('গ্রহণ ও বিল','Acceptance and billing',[
          f('accept','গ্রাহকের গ্রহণ / আপত্তি','Client acceptance / objection'),
          f('invoice','ইনভয়েস ও পেমেন্ট রেফারেন্স','Invoice and payment ref')
        ])
      ],signatures:COMMON_APPROVAL
    }
  ];
});
