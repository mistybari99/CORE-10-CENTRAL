/* CORE-10 PaperOps: offline, print-only foundation. No credentials, network, or ERP writes.
   Each template is a proposal until the legacy field-by-field control audit is signed off. */
(function(root, factory) {
  'use strict';
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  if (root) root.CORE10_PAPEROPS = api;
})(typeof globalThis === 'object' ? globalThis : this, function() {
  'use strict';
  const t = (bn, en) => ({ bn, en });
  const f = (key, bn, en, industries) => ({ key, label: t(bn, en), industries: industries || ['all'] });
  const s = (bn, en, fields, table) => ({ title: t(bn, en), fields: fields || [], table: table || null });
  const table = (bn, en, cols, rows = 7) => ({ title: t(bn, en), cols: cols.map(c => t(c[0], c[1])), rows });
  const TEMPLATES = [
    {
      id: 'OPS-DAILY', industries: ['all'], cadence: 'daily', status: 'draft', legacyRefs: ['R-01'],
      title: t('দৈনিক শাখা ক্লোজিং ও বিক্রি-স্টক সারাংশ', 'Daily Site Closing & Sales–Stock Summary'),
      rule: t('সাধারণ দিনের একটি সারাংশ। ক্যাশ হস্তান্তর, স্টক স্থানান্তর, বড় ব্যয় বা অনুমোদন প্রয়োজন হলে পৃথক প্রমাণপত্র লাগবে।', 'One routine daily summary. Cash custody, stock transfer, material expenses and exceptions still require separate evidence.'),
      sections: [
        s('দিন ও দায়িত্ব', 'Shift and responsibility', [
          f('date', 'তারিখ', 'Date'), f('shift', 'শিফট / সময়', 'Shift / time'),
          f('prepared', 'প্রস্তুতকারী', 'Prepared by'), f('opening_ref', 'প্রারম্ভিক স্টক / পূর্বদিনের ক্লোজিং নং', 'Opening / previous closing reference')
        ]),
        s('পণ্যভিত্তিক মিল', 'Item-level reconciliation', [], table('পণ্য / ইউনিট / খোলা / প্রাপ্তি / বিক্রি / ফেরত / অপচয় / বন্ধ', 'Item / unit / open / received / sold / returned / waste / close', [
          ['পণ্য / কোড', 'Item / code'], ['একক', 'Unit'], ['খোলা', 'Open'], ['প্রাপ্তি', 'Received'], ['বিক্রি', 'Sold'], ['ফেরত', 'Returned'], ['অপচয়', 'Waste'], ['বন্ধ', 'Close']
        ], 9)),
        s('টাকা ও বিচ্যুতি', 'Money and exceptions', [
          f('cash_sales', 'নগদ বিক্রি ৳', 'Cash sales BDT'),
          f('digital_sales', 'ডিজিটাল বিক্রি ৳ (রেফারেন্সসহ)', 'Digital sales BDT (with references)'),
          f('credit_sales', 'বাকি বিক্রি ৳ (পার্টি রেফারেন্সসহ)', 'Credit sales BDT (with party references)'),
          f('expense_ref', 'অনুমোদিত খরচ ভাউচার নং ও মোট ৳', 'Approved expense voucher references and total BDT'),
          f('expected_cash', 'প্রত্যাশিত নগদ ৳', 'Expected cash BDT'),
          f('counted_cash', 'গণনাকৃত নগদ ৳', 'Counted cash BDT'),
          f('variance', 'পার্থক্য ৳ ও Exception নং', 'Variance BDT and exception reference'),
          f('closure_notes', 'বিশেষ নোট / পরের শিফটের কাজ', 'Exceptions / next-shift action')
        ])
      ], signatures: [t('প্রস্তুতকারী', 'Prepared by'), t('স্বতন্ত্র যাচাইকারী', 'Independent checker')]
    },
    {
      id: 'CASH-HANDOVER', industries: ['all'], cadence: 'event', status: 'draft', legacyRefs: ['C-01'],
      title: t('ক্যাশ হস্তান্তর ও গ্রহণ রসিদ', 'Cash Custody Handover Receipt'),
      rule: t('টাকার দায়িত্ব বদলালে পৃথক স্বাক্ষরিত প্রমাণ বাধ্যতামূলক। শুধু Daily Closing যথেষ্ট নয়।', 'Keep a separate signed record whenever custody of money changes. Daily Closing alone is not sufficient.'),
      sections: [
        s('হস্তান্তর', 'Handover', [
          f('closing_ref', 'দৈনিক ক্লোজিং নং', 'Daily closing reference'), f('time', 'সময়', 'Time'),
          f('seal', 'সিল / ব্যাগ নং', 'Seal / bag number'), f('amount', 'হস্তান্তরিত নগদ ৳', 'Cash handed over BDT'),
          f('counted', 'গ্রহণের সময় গণনাকৃত নগদ ৳', 'Cash recounted at receipt BDT'),
          f('difference', 'পার্থক্য ও তদন্ত রেফারেন্স', 'Difference and investigation reference'),
          f('proof', 'সংযুক্ত কাগজ / ডিপোজিট স্লিপ নং', 'Enclosed records / deposit slip')
        ])
      ], signatures: [t('দাতা (সময়সহ)', 'Handed over by (with time)'), t('গ্রহণকারী (সময়সহ)', 'Received by (with time)')]
    },
    {
      id: 'STK-TRANSFER', industries: ['all'], cadence: 'event', status: 'draft', legacyRefs: ['W-02', 'W-01'],
      title: t('মালামাল ইস্যু / স্থানান্তর ও গ্রহণ চালান', 'Material Issue / Transfer & Receipt'),
      rule: t('পণ্য স্থানান্তরের দুই প্রান্তের পরিমাণ ও স্বাক্ষর রাখুন। মালামাল ইস্যু আর শাখা ট্রান্সফার একই ঘটনা নয়; প্রাসঙ্গিক ঘর পূরণ করতে হবে।', 'Record dispatch and receipt separately. Material issue and inter-site transfer are different events; fill only applicable fields.'),
      sections: [
        s('প্রেরণ ও গ্রহণ', 'Dispatch and receipt', [
          f('purpose', 'ধরন: ইস্যু / স্থানান্তর', 'Purpose: issue / transfer'),
          f('source', 'প্রেরক লোকেশন', 'From location'), f('destination', 'গ্রহীতা লোকেশন / বিভাগ', 'To location / department'),
          f('request_ref', 'অনুরোধ / অনুমোদন নং', 'Request / approval reference'), f('transport', 'পরিবহন / সিল নং', 'Transport / seal number')
        ]),
        s('পণ্যের তালিকা', 'Item lines', [], table('পণ্যের বিবরণ', 'Item lines', [
          ['পণ্য / কোড', 'Item / code'], ['ব্যাচ / লট', 'Batch / lot'], ['একক', 'Unit'], ['পাঠানো', 'Sent'], ['পাওয়া', 'Received'], ['পার্থক্য / কারণ', 'Variance / reason']
        ], 8)),
        s('সমাপ্তি', 'Closure', [
          f('dispatch_time', 'ছাড়ার সময়', 'Dispatched at'), f('receipt_time', 'পৌঁছার সময়', 'Received at'),
          f('variance_ref', 'পার্থক্য হলে তদন্ত / সিদ্ধান্ত নং', 'Discrepancy investigation / decision ref')
        ])
      ], signatures: [t('ইস্যুকারী', 'Issued by'), t('বহনকারী', 'Carrier'), t('গ্রহণকারী', 'Received by')]
    },
    {
      id: 'PUR-GRN', industries: ['all'], cadence: 'event', status: 'draft', legacyRefs: ['P-04'],
      title: t('মালামাল গ্রহণ ও মান যাচাই (GRN)', 'Goods Receipt & Quality Check (GRN)'),
      rule: t('অর্ডার, সরবরাহ, গ্রহণ, QC ও ফেরত/আটকের প্রমাণ আলাদা কলামে রাখুন। QC ছাড়া গ্রহণকে চূড়ান্ত স্টক ধরা যাবে না।', 'Separate ordered, delivered, accepted and rejected quantities. Do not treat unchecked goods as accepted stock.'),
      sections: [
        s('সরবরাহের পরিচয়', 'Delivery identification', [
          f('supplier', 'সাপ্লায়ার', 'Supplier'), f('po', 'PO নং', 'PO number'),
          f('invoice', 'সাপ্লায়ারের চালান নং', 'Supplier invoice / challan'),
          f('receipt', 'গ্রহণের তারিখ/সময়', 'Receipt date / time')
        ]),
        s('আইটেম ও মান', 'Items and QC', [], table('প্রাপ্তি ও যাচাই', 'Receipt & inspection', [
          ['পণ্য / কোড', 'Item / code'], ['ব্যাচ / লট / শেড', 'Batch / lot / shade'], ['একক', 'Unit'],
          ['চালানে', 'Delivered'], ['গৃহীত', 'Accepted'], ['আটক/ফেরত', 'Hold / return'], ['কারণ', 'Reason']
        ], 8)),
        s('নিয়ন্ত্রণ', 'Controls', [
          f('expiry', 'মেয়াদ / সংরক্ষণ অবস্থা (প্রযোজ্য হলে)', 'Expiry / storage condition (if relevant)', ['sweets']),
          f('shade', 'শেড / বেস / লট পরীক্ষা (প্রযোজ্য হলে)', 'Shade / base / lot inspection (if relevant)', ['paint']),
          f('qc', 'QC সিদ্ধান্ত ও রেফারেন্স', 'QC disposition and reference'),
          f('difference', 'PO ও প্রাপ্তির পার্থক্য', 'PO / delivered difference')
        ])
      ], signatures: [t('গ্রহণকারী', 'Received by'), t('স্বতন্ত্র QC/যাচাইকারী', 'Independent QC/checker')]
    },
    {
      id: 'STK-COUNT', industries: ['all'], cadence: 'periodic', status: 'draft', legacyRefs: ['W-03', 'W-04'],
      title: t('শারীরিক স্টক গণনা ও পার্থক্য', 'Physical Stock Count & Variance'),
      rule: t('গণনা ও অনুমোদন আলাদা ব্যক্তি করবেন। গরমিল পাওয়া মানেই স্টক নিজে থেকে পরিবর্তন নয়।', 'Counting and approval require separate people. A discrepancy is not authorization for an automatic adjustment.'),
      sections: [
        s('গণনা', 'Count', [
          f('start', 'শুরু ও শেষের সময়', 'Start and end time'),
          f('scope', 'গোডাউন / শেলফ / স্টক লোকেশন', 'Storage location / scope')
        ], table('গণনার লাইন', 'Count lines', [
          ['পণ্য / কোড', 'Item / code'], ['ব্যাচ / লট', 'Batch / lot'], ['ইউনিট', 'Unit'],
          ['রেজিস্টারে', 'Ledger'], ['গণনায়', 'Physical'], ['পার্থক্য', 'Difference'], ['কারণ / প্রমাণ', 'Reason / evidence']
        ], 9)),
        s('তদন্ত ও অনুমোদন', 'Investigation and approval', [
          f('cause', 'পার্থক্যের কারণ / সমর্থনকারী দলিল নং', 'Variance cause and source documents'),
          f('decision', 'অনুমোদনের সিদ্ধান্ত / রেফারেন্স', 'Approval decision / reference')
        ])
      ], signatures: [t('গণনাকারী', 'Counter'), t('স্বতন্ত্র যাচাইকারী', 'Independent checker'), t('সমন্বয় অনুমোদনকারী', 'Adjustment approver')]
    },
    {
      id: 'MFG-DAILY', industries: ['sweets', 'paint'], cadence: 'event', status: 'draft', legacyRefs: ['F-05', 'F-03', 'F-04'],
      title: t('কারখানা ব্যাচ উৎপাদন ও ফলন রেকর্ড', 'Factory Batch Production & Yield'),
      rule: t('স্থায়ী রেসিপি / অনুমোদিত ফর্মুলা প্রতিদিন কপি নয়; তার ভার্সন রেফারেন্স দিন। অপচয়, QC ও ফলনের পার্থক্য লিখুন।', 'Reference the approved recipe/formula version; do not recopy it each shift. Record yield, loss, QC and discrepancies.'),
      sections: [
        s('ব্যাচ পরিচয়', 'Batch identity', [
          f('batch', 'ব্যাচ নং', 'Batch number'), f('product', 'পণ্য / প্রোডাক্ট কোড', 'Product / SKU'),
          f('recipe', 'অনুমোদিত রেসিপি/ফর্মুলা ও ভার্সন', 'Approved recipe/formula and version'),
          f('shift', 'শিফট / তারিখ', 'Shift / date')
        ]),
        s('কাঁচামাল', 'Materials', [], table('ইস্যু ও ব্যবহার', 'Issued and used', [
          ['কাঁচামাল / কোড', 'Material / code'], ['ব্যাচ', 'Lot'], ['ইস্যু নং', 'Issue ref'], ['একক', 'Unit'],
          ['ইস্যু', 'Issued'], ['ব্যবহৃত', 'Used'], ['ফেরত', 'Returned']
        ], 7)),
        s('উৎপাদন ও QC', 'Output and QC', [
          f('expected', 'অনুমোদিত প্রত্যাশিত ফলন', 'Expected yield'),
          f('actual', 'প্রকৃত ভালো উৎপাদন', 'Actual accepted output'),
          f('waste', 'অপচয় / রিজেক্ট ও কারণ', 'Reject / waste with reason'),
          f('deviation', 'ফলনের গরমিল ও অনুমোদন রেফারেন্স', 'Yield variance and approval ref'),
          f('qc', 'QC সিদ্ধান্ত / ব্যাচ মুক্তির রেফারেন্স', 'QC / batch release reference')
        ])
      ], signatures: [t('উৎপাদনকারী', 'Produced by'), t('মাপ/ফলন যাচাইকারী', 'Yield checker'), t('QC অনুমোদনকারী', 'QC approver')]
    },
    {
      id: 'PAINT-TINT', industries: ['paint'], cadence: 'event', status: 'hypothesis', legacyRefs: [],
      title: t('পেইন্ট শেড মিক্সিং ও QC রেকর্ড (পরীক্ষামূলক)', 'Paint Tint Mixing & QC (Proposed)'),
      rule: t('পেইন্ট ব্যবসার বাস্তব পদ্ধতি যাচাই করা হয়নি। ব্যবহার করার আগে Owner/অপারেশন টিম দিয়ে ক্ষেত্রগুলো যাচাই করুন।', 'Proposed only: validate this workflow and fields against actual paint operations before adopting.'),
      sections: [
        s('মিক্সিং পরিচয়', 'Mix identity', [
          f('order', 'অর্ডার নং', 'Order number'), f('base', 'বেস পেইন্ট / লট', 'Base paint / lot'),
          f('shade', 'শেড কোড / ফর্মুলা ভার্সন', 'Shade code / formula version'),
          f('quantity', 'পরিমাণ / একক', 'Quantity / unit')
        ]),
        s('মিশ্রণ ও পরীক্ষা', 'Mixing and QC', [], table('টিন্ট/রঙের উপাদান', 'Tint components', [
          ['কালারেন্ট / কোড', 'Colorant / code'], ['লট', 'Lot'], ['লক্ষ্যমাত্রা', 'Target'], ['প্রয়োগ', 'Actual']
        ], 7)),
        s('সিদ্ধান্ত', 'Disposition', [
          f('test', 'শেড ম্যাচ / QC ফলাফল', 'Shade match / QC result'),
          f('rework', 'সংশোধন / রিওয়ার্ক ও অনুমোদন', 'Correction / rework and approval')
        ])
      ], signatures: [t('মিক্সকারী', 'Mixed by'), t('QC/শেড যাচাইকারী', 'Shade/QC checker')]
    },
    {
      id: 'EXCEPTION', industries: ['all'], cadence: 'event', status: 'draft', legacyRefs: ['S-02', 'C-02'],
      title: t('ব্যতিক্রম, গরমিল ও অনুমোদনের নথি', 'Exception, Variance & Approval Record'),
      rule: t('এটি শুধু ট্রিগার ঘটলে প্রযোজ্য। আইনগত বা আলাদা পেমেন্ট ভাউচারের বিকল্প নয়। অনুমোদনকারী প্রস্তুতকারী হতে পারবেন না।', 'Use only for triggered exceptions. Not a substitute for statutory/payment vouchers. Approver must be different from preparer.'),
      sections: [
        s('ঘটনা ও কারণ', 'Exception and cause', [
          f('type', 'ধরন (ছাড় / ব্যয় / রিটার্ন / স্টক গরমিল / QC / অন্য)', 'Type (discount / expense / return / stock variance / QC / other)'),
          f('source', 'মূল দলিল নং', 'Source document reference'),
          f('amount', 'অর্থ / পরিমাণ / সীমা', 'Amount / quantity / threshold'),
          f('reason', 'কারণ ও সমর্থনকারী প্রমাণ', 'Reason and evidence'),
          f('action', 'প্রস্তাবিত ব্যবস্থা ও সময়সীমা', 'Proposed action and due date'),
          f('decision', 'স্বতন্ত্র অনুমোদকের সিদ্ধান্ত', 'Independent approver decision')
        ])
      ], signatures: [t('আবেদনকারী', 'Prepared by'), t('স্বতন্ত্র অনুমোদনকারী', 'Independent approver')]
    }
  ];
  const INDUSTRIES = ['generic', 'sweets', 'paint'];
  function escapeHtml(value) {
    return String(value == null ? '' : value).replace(/[&<>"']/g, c =>
      ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
  }
  function label(value, lang) { return (value && value[lang === 'en' ? 'en' : 'bn']) || ''; }
  function availableForms(industry) {
    const choice = INDUSTRIES.includes(industry) ? industry : 'generic';
    return TEMPLATES.filter(x => x.industries.includes('all') || x.industries.includes(choice));
  }
  function validateCatalog(forms = TEMPLATES) {
    const ids = new Set();
    for (const form of forms) {
      if (!/^[A-Z]+(?:-[A-Z]+)*$/.test(form.id) || ids.has(form.id)) throw Error('INVALID_FORM_ID');
      ids.add(form.id);
      if (!form.title.bn || !form.title.en || !Array.isArray(form.sections) || !form.sections.length) throw Error('INVALID_FORM');
      const fields = new Set();
      for (const sec of form.sections) {
        for (const field of sec.fields) {
          if (!field.key || fields.has(field.key)) throw Error('DUPLICATE_FIELD');
          fields.add(field.key);
        }
        if (sec.table && (!sec.table.cols.length || sec.table.rows < 1)) throw Error('INVALID_TABLE');
      }
    }
    return true;
  }
  function safeLogo(url) {
    return typeof url === 'string' && url.length < 750000 &&
      /^data:image\/(?:png|jpeg|webp);base64,[A-Za-z0-9+/=]+$/.test(url) ? url : '';
  }
  function safeColor(value) {
    return typeof value === 'string' && /^#[0-9a-fA-F]{6}$/.test(value) ? value : '#174c4c';
  }
  function resolveBrand(config, formId) {
    const c = config || {};
    const combined = Object.assign({}, c.groupBrand || {}, c.businessBrand || {},
      c.scope === 'site' ? c.siteBrand || {} : {});
    const titles = combined.formTitles || {};
    return {
      name: combined.headerName || c.businessName || '',
      subtitle: combined.subtitle || '',
      color: safeColor(combined.color),
      logo: safeLogo(combined.logo),
      titleOverride: typeof titles[formId] === 'string' ? titles[formId].slice(0, 140) : ''
    };
  }
  function validateJob(id, config) {
    const c = config || {};
    const form = TEMPLATES.find(x => x.id === id);
    if (!form) throw Error('UNKNOWN_FORM');
    if (!INDUSTRIES.includes(c.industry)) throw Error('UNKNOWN_INDUSTRY');
    if (!(form.industries.includes('all') || form.industries.includes(c.industry))) throw Error('FORM_NOT_FOR_INDUSTRY');
    if (!['business', 'site'].includes(c.scope)) throw Error('INVALID_SCOPE');
    if (!String(c.businessName || '').trim()) throw Error('BUSINESS_REQUIRED');
    if (c.scope === 'site' && !String(c.siteName || '').trim()) throw Error('SITE_REQUIRED');
    return form;
  }
  function renderPrintMarkup(id, config) {
    const form = validateJob(id, config);
    const c = config, lang = c.lang === 'en' ? 'en' : 'bn';
    const brand = resolveBrand(c, id);
    const title = brand.titleOverride || label(form.title, lang);
    const scopeLabel = c.scope === 'site' ? label(t('শাখা/কারখানা/গোডাউন', 'Site / factory / warehouse'), lang) : label(t('সব শাখার জন্য কমন', 'Common across sites'), lang);
    const parts = [];
    parts.push('<article class="paperops-form" style="--accent:' + brand.color + '">');
    parts.push('<header class="paperops-head">');
    if (brand.logo) parts.push('<img class="paperops-logo" alt="" src="' + brand.logo + '">');
    parts.push('<div><p class="paperops-organization">' + escapeHtml(brand.name) + '</p>');
    if (brand.subtitle) parts.push('<p class="paperops-subtitle">' + escapeHtml(brand.subtitle) + '</p>');
    parts.push('<h1>' + escapeHtml(title) + '</h1></div></header>');
    parts.push('<div class="paperops-meta"><span>' + escapeHtml(label(t('গ্রুপ', 'Group'), lang)) + ': ' + escapeHtml(c.groupName || '—') + '</span><span>' + escapeHtml(label(t('ব্যবসা', 'Business'), lang)) + ': ' + escapeHtml(c.businessName) + '</span>');
    parts.push('<span>' + escapeHtml(scopeLabel) + ': ' + escapeHtml(c.scope === 'site' ? c.siteName : '—') + '</span>');
    parts.push('<span>' + escapeHtml(label(t('ফর্ম কোড', 'Form code'), lang)) + ': ' + form.id + ' / v0.1</span>');
    parts.push('<span>' + escapeHtml(label(t('সিরিয়াল নং', 'Serial no.'), lang)) + ': __________________</span>');
    parts.push('<span>' + escapeHtml(label(t('তারিখ', 'Date'), lang)) + ': __________________</span></div>');
    parts.push('<p class="paperops-rule">' + escapeHtml(label(form.rule, lang)) + '</p>');
    for (const sec of form.sections) {
      const fields = sec.fields.filter(field => field.industries.includes('all') || field.industries.includes(c.industry));
      if (!fields.length && !sec.table) continue;
      parts.push('<section class="paperops-section"><h2>' + escapeHtml(label(sec.title, lang)) + '</h2>');
      if (fields.length) {
        parts.push('<div class="paperops-fields">');
        for (const field of fields) parts.push('<div class="paperops-field"><span>' + escapeHtml(label(field.label, lang)) + '</span><div class="paperops-line"></div></div>');
        parts.push('</div>');
      }
      if (sec.table) {
        parts.push('<table class="paperops-table"><caption>' + escapeHtml(label(sec.table.title, lang)) + '</caption><thead><tr>');
        for (const col of sec.table.cols) parts.push('<th>' + escapeHtml(label(col, lang)) + '</th>');
        parts.push('</tr></thead><tbody>');
        const rows = Number.isInteger(c.tableRows) ? Math.min(18, Math.max(3, c.tableRows)) : sec.table.rows;
        for (let r = 0; r < rows; r++) parts.push('<tr>' + sec.table.cols.map(() => '<td>&nbsp;</td>').join('') + '</tr>');
        parts.push('</tbody></table>');
      }
      parts.push('</section>');
    }
    parts.push('<section class="paperops-signatures">');
    for (const person of form.signatures) parts.push('<div><div class="paperops-line"></div><span>' + escapeHtml(label(person, lang)) + ' / ' + escapeHtml(label(t('তারিখ ও সময়', 'Date and time'), lang)) + '</span></div>');
    parts.push('</section><footer class="paperops-footer">' +
      escapeHtml(label(t('কাগজের মূল রেকর্ড। ERP পোস্টিংয়ের আগে নম্বর, দলিল, অনুমোদন ও মিল যাচাই প্রয়োজন।', 'Original paper record. Verify number, evidence, approval and reconciliation before any ERP posting.'), lang)) +
      ' · ' + escapeHtml(form.status === 'hypothesis' ? 'PROPOSED / NOT FIELD-VALIDATED' : 'DRAFT / NOT FIELD-VALIDATED') +
      '</footer></article>');
    return parts.join('');
  }
  validateCatalog();
  return Object.freeze({ TEMPLATES, INDUSTRIES, availableForms, escapeHtml, resolveBrand, validateCatalog, validateJob, renderPrintMarkup });
});
