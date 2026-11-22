/* CORE-10 PaperOps event-driven print plan. No ERP writes, storage or network.
   Safety-first: a printable draft is not proof of complete offline business books. */
(function(root, factory) {
  'use strict';
  const api = factory(root && root.CORE10_PAPEROPS);
  if (typeof module === 'object' && module.exports) module.exports = factory(require('./paperops.js'));
  if (root) root.CORE10_PAPER_KIT = api;
})(typeof globalThis === 'object' ? globalThis : this, function(paperops) {
  'use strict';
  const EVENT_TYPES = Object.freeze({
    cash_handover: Object.freeze({formId:'CASH-HANDOVER',name_bn:'ক্যাশ হস্তান্তর',name_en:'Cash handover'}),
    stock_transfer: Object.freeze({formId:'STK-TRANSFER',name_bn:'মালামাল ইস্যু / ট্রান্সফার',name_en:'Material issue / transfer'}),
    supplier_delivery: Object.freeze({formId:'PUR-GRN',name_bn:'সাপ্লায়ার ডেলিভারি',name_en:'Supplier delivery / GRN'}),
    stock_count: Object.freeze({formId:'STK-COUNT',name_bn:'স্টক গণনা',name_en:'Physical stock count'}),
    production_batch: Object.freeze({formId:'MFG-DAILY',name_bn:'কারখানা ব্যাচ উৎপাদন',name_en:'Production batch',industries:['sweets','paint']}),
    paint_tint: Object.freeze({formId:'PAINT-TINT',name_bn:'পেইন্ট শেড মিক্সিং (প্রস্তাবিত)',name_en:'Paint tinting (proposed)',industries:['paint']}),
    exception: Object.freeze({formId:'EXCEPTION',name_bn:'গরমিল বা বিশেষ অনুমোদন',name_en:'Exception / special approval'})
  });
  const INDEPENDENT_BOOKS = Object.freeze([
    {id:'STOCK_LEDGER',source:'W-04',name_bn:'চলমান স্টক লেজার',name_en:'Continuous stock ledger',status:'NOT_YET_PRINTABLE'},
    {id:'CASH_BANK_LEDGER',source:'C-01/C-02',name_bn:'ক্যাশ-ব্যাংক রেজিস্টার',name_en:'Cash and bank book',status:'NOT_YET_PRINTABLE'},
    {id:'SUPPLIER_ACCOUNTS',source:'P-05/P-06',name_bn:'সাপ্লায়ার বিল ও পাওনা রেজিস্টার',name_en:'Supplier bills/payables ledger',status:'NOT_YET_PRINTABLE'},
    {id:'CUSTOMER_ACCOUNTS',source:'S-06/C-05',name_bn:'কাস্টমার বাকি ও অগ্রিম রেজিস্টার',name_en:'Customer receivables and advances',status:'NOT_YET_PRINTABLE'},
    {id:'DIGITAL_RECON',source:'C-04/S-04',name_bn:'ডিজিটাল পেমেন্ট সেটেলমেন্ট মিল',name_en:'Digital settlement reconciliation',status:'NOT_YET_PRINTABLE'},
    {id:'BILL_THREE_WAY',source:'P-05',name_bn:'PO–GRN–Bill যাচাই',name_en:'PO–GRN–invoice verification',status:'NOT_YET_PRINTABLE'},
    {id:'LEGAL_TAX',source:'OTHER',name_bn:'আইনগত ভাউচার ও করের দলিল',name_en:'Statutory vouchers and tax records',status:'POLICY_REQUIRED'}
  ]);
  function nonempty(v, max, code) {
    if (typeof v !== 'string' || !v.trim() || v.trim().length > max) throw Error(code);
    return v.trim();
  }
  function planDay(config) {
    if (!config || !paperops.INDUSTRIES.includes(config.industry)) throw Error('UNKNOWN_INDUSTRY');
    const business = nonempty(config.businessName, 120, 'BUSINESS_REQUIRED');
    const sites = config.sites;
    if (!Array.isArray(sites) || sites.length === 0 || sites.length > 400) throw Error('INVALID_SITES');
    const map = new Map();
    for (const s of sites) {
      if (!s || typeof s !== 'object') throw Error('INVALID_SITE');
      const id = nonempty(s.id, 90, 'INVALID_SITE_ID');
      const name = nonempty(s.name, 120, 'INVALID_SITE_NAME');
      const kind = s.kind === undefined ? 'showroom' : nonempty(s.kind, 30, 'INVALID_SITE_KIND');
      if (!['showroom','factory','warehouse','office','project'].includes(kind)) throw Error('INVALID_SITE_KIND');
      if (map.has(id)) throw Error('DUPLICATE_SITE_ID');
      map.set(id, Object.freeze({id,name,kind}));
    }
    const day = nonempty(config.date, 10, 'DATE_REQUIRED');
    if (!/^\d{4}-\d{2}-\d{2}$/.test(day) || Number.isNaN(Date.parse(day+'T12:00:00Z')) ||
        new Date(day+'T12:00:00Z').toISOString().slice(0,10) !== day) throw Error('INVALID_DATE');
    const events = config.events || [];
    if (!Array.isArray(events) || events.length > 2000) throw Error('INVALID_EVENTS');
    const forms = [];
    const seen = new Set();
    // Only retail/showroom sites receive the retail-sales close by default.
    // A factory or warehouse must use its actual event paperwork and rolling books;
    // inventing a sales close for it would add pointless daily work.
    for (const site of map.values()) if (site.kind === 'showroom') forms.push({
      key: 'daily:'+day+':'+site.id,formId:'OPS-DAILY',siteId:site.id,siteName:site.name,
      type:'daily',eventId:null,source:'R-01',status:'DRAFT_PRINTABLE'
    });
    for (const e of events) {
      if (!e || typeof e !== 'object') throw Error('INVALID_EVENT');
      const type = nonempty(e.type, 60, 'INVALID_EVENT_TYPE');
      const def = EVENT_TYPES[type];
      if (!def) throw Error('UNKNOWN_EVENT_TYPE');
      const siteId = nonempty(e.siteId, 90, 'INVALID_EVENT_SITE');
      const site = map.get(siteId);
      if (!site) throw Error('UNKNOWN_SITE');
      const eventId = nonempty(e.eventId, 120, 'EVENT_ID_REQUIRED');
      if (def.industries && !def.industries.includes(config.industry)) throw Error('EVENT_UNSUPPORTED_FOR_INDUSTRY');
      const key = 'event:'+type+':'+siteId+':'+eventId;
      if (seen.has(key)) throw Error('DUPLICATE_EVENT_ID');
      seen.add(key);
      forms.push({key,formId:def.formId,siteId,siteName:site.name,type,eventId,source:null,
        status:type==='paint_tint'?'HYPOTHESIS_NOT_FIELD_VALIDATED':'DRAFT_PRINTABLE'});
    }
    return Object.freeze({
      date:day,businessName:business,industry:config.industry,
      forms:Object.freeze(forms.map(x=>Object.freeze(x))),
      count:forms.length,dailyCount:sites.filter(s=>(s.kind || 'showroom')==='showroom').length,
      eventCount:events.length,
      excludedDailySites:Object.freeze([...map.values()].filter(s=>s.kind!=='showroom')),
      outstandingBooks:INDEPENDENT_BOOKS,
      coverageStatus:'INCOMPLETE_DRAFT_DO_NOT_USE_AS_A_COMPLETE_OFFLINE_ACCOUNTING_KIT'
    });
  }
  function printKit(plan, settings) {
    if (!plan || !Array.isArray(plan.forms) || plan.coverageStatus !==
      'INCOMPLETE_DRAFT_DO_NOT_USE_AS_A_COMPLETE_OFFLINE_ACCOUNTING_KIT') throw Error('INVALID_PLAN');
    if (plan.forms.length === 0) throw Error('EMPTY_PLAN_REQUIRES_OPERATIONAL_EVENT');
    if (plan.forms.length > 100) throw Error('PRINT_BATCH_LIMIT_100_USE_MULTIPLE_KITS');
    const opts = settings || {};
    const parts=[];
    for (const item of plan.forms) {
      const job = {
        industry:plan.industry,
        scope:'site',
        businessName:plan.businessName,
        groupName:typeof opts.groupName==='string'?opts.groupName:'',
        siteName:item.siteName,
        lang:opts.lang==='en'?'en':'bn',
        tableRows:opts.tableRows,
        groupBrand:opts.groupBrand,
        businessBrand:opts.businessBrand,
        siteBrand:(opts.siteBrands && opts.siteBrands[item.siteId]) || opts.siteBrand
      };
      const body=paperops.renderPrintMarkup(item.formId,job);
      parts.push('<div class="paperops-kit-sheet">' + body + '<div class="paperops-kit-trace">' +
        paperops.escapeHtml(plan.date+' · '+item.type+' · '+(item.eventId||'daily'))+
        '</div></div>');
    }
    return parts.join('');
  }
  return Object.freeze({EVENT_TYPES,INDEPENDENT_BOOKS,planDay,printKit});
});
