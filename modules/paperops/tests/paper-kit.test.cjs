'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const kit = require('../paper-kit.js');

const base = {
  date:'2026-11-22',industry:'sweets',businessName:'Sweet Group Business',
  sites:[{id:'sh-1',name:'Showroom A'},{id:'fac-1',name:'Factory B'}],events:[]
};

test('normal two-site day needs only one closing form per site', () => {
  const p=kit.planDay(base);
  assert.equal(p.dailyCount,2);
  assert.equal(p.eventCount,0);
  assert.equal(p.count,2);
  assert.ok(p.forms.every(f=>f.formId==='OPS-DAILY'));
  assert.equal(p.outstandingBooks.length,7);
  assert.match(p.coverageStatus,/INCOMPLETE/);
  assert.ok(p.forms.every(f=>f.status==='DRAFT_PRINTABLE'));
});

test('paper evidence follows events, not compulsory sheets', () => {
  const p=kit.planDay({...base,events:[
    {type:'cash_handover',siteId:'sh-1',eventId:'CASH-001'},
    {type:'stock_transfer',siteId:'fac-1',eventId:'MOV-001'},
    {type:'supplier_delivery',siteId:'fac-1',eventId:'GRN-001'},
    {type:'production_batch',siteId:'fac-1',eventId:'BATCH-001'},
    {type:'stock_count',siteId:'sh-1',eventId:'COUNT-001'},
    {type:'exception',siteId:'sh-1',eventId:'VAR-001'}
  ]});
  assert.equal(p.count,8);
  assert.equal(p.dailyCount,2);
  assert.equal(p.eventCount,6);
  assert.deepEqual(p.forms.map(f=>f.formId),[
    'OPS-DAILY','OPS-DAILY','CASH-HANDOVER','STK-TRANSFER',
    'PUR-GRN','MFG-DAILY','STK-COUNT','EXCEPTION'
  ]);
  assert.deepEqual(p.forms.slice(2).map(f=>f.eventId),[
    'CASH-001','MOV-001','GRN-001','BATCH-001','COUNT-001','VAR-001'
  ]);
});

test('repeated source reference cannot be printed as a second event by accident', () => {
  const ref={type:'cash_handover',siteId:'sh-1',eventId:'CASH-001'};
  assert.throws(()=>kit.planDay({...base,events:[ref,ref]}),/DUPLICATE_EVENT_ID/);
  const allowed=kit.planDay({...base,events:[
    ref,{...ref,siteId:'fac-1'},{...ref,eventId:'CASH-002'}
  ]});
  assert.equal(allowed.eventCount,3);
});

test('the planner fails closed for unknown sites, industries and unsupported workflows', () => {
  assert.throws(()=>kit.planDay({...base,sites:[]}),/INVALID_SITES/);
  assert.throws(()=>kit.planDay({...base,sites:[{id:'x',name:'A'},{id:'x',name:'B'}]}),/DUPLICATE_SITE_ID/);
  assert.throws(()=>kit.planDay({...base,sites:[{id:'',name:'A'}]}),/INVALID_SITE_ID/);
  assert.throws(()=>kit.planDay({...base,events:[{type:'cash_handover',siteId:'no',eventId:'A'}]}),/UNKNOWN_SITE/);
  assert.throws(()=>kit.planDay({...base,events:[{type:'unknown',siteId:'sh-1',eventId:'A'}]}),/UNKNOWN_EVENT_TYPE/);
  assert.throws(()=>kit.planDay({...base,industry:'generic',events:[
    {type:'production_batch',siteId:'sh-1',eventId:'A'}
  ]}),/EVENT_UNSUPPORTED_FOR_INDUSTRY/);
  assert.throws(()=>kit.planDay({...base,industry:'sweets',events:[
    {type:'paint_tint',siteId:'sh-1',eventId:'A'}
  ]}),/EVENT_UNSUPPORTED_FOR_INDUSTRY/);
  assert.throws(()=>kit.planDay({...base,date:'2026-02-30'}),/INVALID_DATE/);
  assert.throws(()=>kit.planDay({...base,events:[{type:'cash_handover',siteId:'sh-1'}]}),/EVENT_ID_REQUIRED/);
});

test('paint-specific proposal remains explicitly unvalidated', () => {
  const p=kit.planDay({...base,industry:'paint',events:[{type:'paint_tint',siteId:'fac-1',eventId:'T-7'}]});
  assert.equal(p.forms.at(-1).status,'HYPOTHESIS_NOT_FIELD_VALIDATED');
  assert.equal(p.count,3);
});

test('bulk print generates separate context-specific sheets and escapes branch text', () => {
  const plan=kit.planDay({...base,sites:[{id:'sh-1',name:'<script>alert(1)</script>'}],
    events:[{type:'supplier_delivery',siteId:'sh-1',eventId:'GRN&1'}]});
  const html=kit.printKit(plan,{
    lang:'bn',groupName:'My Group',
    businessBrand:{color:'#175050',headerName:'Business wide'},
    siteBrands:{'sh-1':{color:'#aabbcc',headerName:'Branch override'}}
  });
  assert.equal((html.match(/class="paperops-kit-sheet"/g)||[]).length,2);
  assert.match(html,/Branch override/);
  assert.match(html,/--accent:#aabbcc/);
  assert.match(html,/GRN&amp;1/);
  assert.match(html,/&lt;script&gt;/);
  assert.doesNotMatch(html,/<script>alert\(1\)<\/script>/);
  assert.throws(()=>kit.printKit({forms:[]}),/INVALID_PLAN/);
});

test('offline UI only loads local module scripts', () => {
  const html=fs.readFileSync(path.resolve(__dirname,'../kit.html'),'utf8');
  assert.match(html,/<script src="\.\/paperops\.js"/);
  assert.match(html,/<script src="\.\/paper-kit\.js"/);
  assert.match(html,/@media print/);
  assert.doesNotMatch(html,/<script[^>]+src="https?:/);
  assert.doesNotMatch(html,/fetch\(|XMLHttpRequest|\.rpc\(/);
});

test('factory, warehouse and office do not receive a fake retail sales close', () => {
  const plan=kit.planDay({...base,sites:[
    {id:'show',name:'Showroom',kind:'showroom'},
    {id:'fac',name:'Production',kind:'factory'},
    {id:'godown',name:'Warehouse',kind:'warehouse'},
    {id:'office',name:'Office',kind:'office'}
  ],events:[{type:'production_batch',siteId:'fac',eventId:'B-001'}]});
  assert.equal(plan.dailyCount,1);
  assert.equal(plan.eventCount,1);
  assert.equal(plan.count,2);
  assert.deepEqual(plan.forms.map(x=>x.formId),['OPS-DAILY','MFG-DAILY']);
  assert.deepEqual(plan.excludedDailySites.map(x=>x.id),['fac','godown','office']);
  assert.throws(()=>kit.planDay({...base,sites:[{id:'x',name:'X',kind:'car'}]}),/INVALID_SITE_KIND/);
});

test('an event-only factory requires a real event and print batches cannot silently omit sheets', () => {
  const p=kit.planDay({...base,sites:[{id:'f1',name:'Factory',kind:'factory'}],events:[]});
  assert.equal(p.count,0);
  assert.equal(p.dailyCount,0);
  assert.throws(()=>kit.printKit(p),/EMPTY_PLAN_REQUIRES_OPERATIONAL_EVENT/);
  const sites=Array.from({length:101},(_,n)=>({id:'s'+n,name:'Showroom '+n}));
  const big=kit.planDay({...base,sites,events:[]});
  assert.equal(big.count,101);
  assert.throws(()=>kit.printKit(big),/PRINT_BATCH_LIMIT_100/);
});

test('each of the ten canonical business types can plan and print its own selected event',()=>{
  const cases=[
    ['sweets_bakery','jalebi_shift','factory'],
    ['restaurant','kitchen_prep','factory'],
    ['paint_hardware','paint_tint','factory'],
    ['retail_wholesale','retail_replenish','showroom'],
    ['general_manufacturing','manufacturing_qc','factory'],
    ['construction','construction_daily','project'],
    ['import_export','trade_shipment','office'],
    ['ecommerce','ecommerce_delivery','warehouse'],
    ['technology_digital','technology_delivery','office'],
    ['services','service_job','project']
  ];
  for (const [industry,type,kind] of cases) {
    const v={date:'2026-11-22',industry,businessName:'Sample Business',
      sites:[{id:'site-1',name:'Site One',kind}],events:[{type,siteId:'site-1',eventId:'REF-'+industry}]};
    const plan=kit.planDay(v);
    assert.equal(plan.eventCount,1);
    assert.equal(plan.count,kind==='showroom'?2:1,'wrong paper burden: '+industry);
    const html=kit.printKit(plan,{lang:'bn',businessBrand:{headerName:'Brand '+industry}});
    assert.equal((html.match(/class="paperops-kit-sheet"/g)||[]).length,plan.count);
    assert.match(html,new RegExp('Brand '+industry));
    assert.ok(plan.forms.at(-1).status==='HYPOTHESIS_NOT_FIELD_VALIDATED' ||
      plan.forms.at(-1).status==='DRAFT_PRINTABLE');
  }
});
