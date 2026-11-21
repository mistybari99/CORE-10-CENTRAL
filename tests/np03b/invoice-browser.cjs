'use strict';
// Existing Central shell -> invoice workspace -> loopback gateway -> canonical PG17.
// Auth subjects and bakery data are synthetic; RPC results are real database results.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {chromium}=require('playwright');
const {start,sql}=require('./ui-gateway.cjs');
const ROOT=path.resolve(__dirname,'../..');
const SHOTS=process.env.NP03B_SHOTS||path.join(ROOT,'artifacts/np03b');
const OWNER='11111111-1111-4111-8111-111111111111';
const literal=x=>"'"+String(x).replaceAll("'","''")+"'";
function execute(query){const r=sql(query);assert.equal(r.status,0,r.stderr||r.stdout);return r.stdout.trim();}
function json(query){return JSON.parse(execute(query).split('\n').at(-1));}
function owner(query){return json("BEGIN;SET LOCAL ROLE authenticated;DO $actor$ BEGIN PERFORM set_config('request.jwt.claim.sub',"+literal(OWNER)+",true);END $actor$;SELECT "+query+";COMMIT;");}
function invoice(id){return owner('core10.read_sales_invoice_drafts_v1(101,1001,'+Number(id)+')').invoices[0];}
function mutate(id,memo,key){const i=invoice(id);return owner('core10.save_sales_invoice_draft_v1(101,1001,'+
 [i.invoice_id,i.version,i.source_order_id,i.source_order_version,literal(JSON.stringify(i.selection))+'::jsonb',literal(memo),literal(key)].join(',')+')');}
function control(feature,enabled,key,stages){const rows=owner('core10.control_read_v1(101)');
 const row=rows.find(x=>x.feature_key===feature);assert.ok(row,'canonical control '+feature);
 return owner('core10.control_set_v1(101,NULL,'+literal(feature)+','+enabled+','+Number(stages??row.stages)+'::smallint,'+
 literal(JSON.stringify(row.params||{}))+"::jsonb,NULL,false,"+Number(row.version)+",'Synthetic browser invoice switch',"+literal(key)+')');}
let passed=0;
(async()=>{
 fs.mkdirSync(SHOTS,{recursive:true});const server=await start(),base='http://127.0.0.1:'+server.address().port;
 const browser=await chromium.launch({...(process.env.NP03B_CHROMIUM?{executablePath:process.env.NP03B_CHROMIUM}:{}),args:['--no-sandbox']});
 const errors=[],created=[];
 const idle=p=>p.waitForFunction(()=>document.querySelector('.si-workspace')?.getAttribute('aria-busy')==='false');
 async function check(name,fn){await fn();passed++;console.log('PASS '+name);}
 async function open(width=1440,lang='en',extra='',setup){
  const p=await browser.newPage({viewport:{width,height:width<500?844:1000},deviceScaleFactor:1});
  p.setDefaultTimeout(15000);p.on('pageerror',e=>errors.push(e.message));if(setup)await setup(p);
  await p.goto(base+'/harness.html?view=invoices&lang='+lang+extra);
  await p.waitForSelector('body[data-ready="1"]');await idle(p);return p;
 }
 async function selectInvoice(p,id){await p.locator('.si-invoice[data-invoice="'+id+'"]').click();await idle(p);}
 const chosen=p=>p.locator('.si-invoice[aria-pressed="true"]');
 async function begin(p){await p.locator('[data-si-action="new"]').click();
  const source=p.locator('[data-si-field="source"]');
  const options=await source.locator('option').evaluateAll(a=>a.filter(x=>x.value&&!x.disabled).map(x=>x.value));
  assert.ok(options.length,'a real confirmed source is available');await source.selectOption(options[0]);
  await p.waitForSelector('[data-si-quantity="1"]');return Number(options[0]);
 }
 async function save(p){await p.locator('[data-si-action="save"]').click();await idle(p);}
 try{
  assert.equal(Number(execute('SELECT count(*) FROM core10.sales_invoice_drafts_v1;')),0,'dedicated browser seed has no invoices');
  for(const [width,lang] of [[1440,'en'],[390,'bn']]){
   const p=await open(width,lang);
   await check(width+' invoice route preserves the one Central shell and signed scope',async()=>{
    assert.equal(await p.locator('.studio-rail').count(),1);
    assert.equal(await p.locator('.so-sales-nav [data-sales-view="orders"]').count(),1);
    assert.equal(await p.locator('.so-sales-nav [data-sales-view="invoices"]').count(),1);
    assert.equal(await p.locator('.si-scope select').first().inputValue(),'101');
    assert.match(await p.locator('.si-workspace').textContent(),/Synthetic|সিনথেটিক|কৃত্রিম/);
   });
   await check(width+' bilingual toggle preserves keyboard focus',async()=>{
    const toggle=p.locator('[data-si-focus="language"]');await toggle.click();
    assert.equal(await toggle.evaluate(x=>x===document.activeElement),true);await toggle.click();
    assert.equal(await p.locator('.si-workspace').getAttribute('lang'),lang);
   });
   const source=await begin(p);const quantity=p.locator('[data-si-quantity="1"]');
   await check(width+' source quantities have accessible native zero/cap/fraction bounds',async()=>{
    assert.equal(await quantity.getAttribute('step'),'1');
    for(const value of ['0','3','0.5']){await quantity.fill(value);assert.equal(await quantity.evaluate(x=>x.checkValidity()),false,value);}
    assert.equal(await quantity.evaluate(x=>!!x.closest('label')||!!document.querySelector('label[for="'+x.id+'"]')),true);
   });
   await quantity.fill('1');
   if(width===1440)await p.locator('[data-si-include="2"]').uncheck();
   await p.locator('[data-si-field="memo"]').fill('Synthetic '+width+' partial invoice');await save(p);
   const id=Number(await chosen(p).getAttribute('data-invoice'));assert.ok(id>0);created.push(id);
   await check(width+' create persists actual source-bound partial draft and canonical snapshot',async()=>{
    const i=invoice(id);assert.equal(i.status,'draft');assert.equal(i.validated,false);assert.equal(i.source_order_id,source);
    assert.equal(i.selection.find(x=>x.order_line_no===1).quantity,1);assert.match(i.source_sha256,/^[a-f0-9]{64}$/);
    if(width===1440)assert.equal(i.selection.some(x=>x.order_line_no===2),false,'unchecked source line omitted');
    assert.equal(i.issued,false);assert.equal(i.stock_posted,false);assert.equal(i.financial_posted,false);
    assert.match(await p.locator('.si-snapshot').textContent(),new RegExp(i.source_sha256));
   });
   await p.locator('[data-si-action="validate"]').click();await idle(p);
   await check(width+' validate is draft review with no issuance or postings',async()=>{
    const i=invoice(id);assert.equal(i.validated,true);assert.equal(i.status,'draft');assert.equal(i.issued,false);
    assert.match(await p.locator('.si-state').textContent(),/Draft|খসড়া|খসড়া/i);
    assert.match(await p.locator('.si-connections').textContent(),/not connected|NOT_CONNECTED|সংযুক্ত নয়|সংযুক্ত নয়/i);
    assert.ok(await p.locator('.si-audit li').count()>=2);
   });
   await p.locator('[data-si-field="memo"]').fill('Synthetic changed memo '+width);await save(p);
   await check(width+' editing a validated draft clears canonical validation',async()=>{
    const i=invoice(id);assert.equal(i.validated,false);assert.equal(i.memo,'Synthetic changed memo '+width);
    assert.equal(i.status,'draft');assert.ok(await p.locator('.si-audit li').count()>=3);
   });
   await p.locator('.si-snapshot summary').click();
   await check(width+' responsive containment and exact source cap survive rendering',async()=>{
    assert.ok(await p.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
    assert.equal(await p.locator('[data-si-quantity="1"]').getAttribute('max'),'2');
   });
   if(!process.env.NP03B_SKIP_SHOTS)await p.screenshot({path:path.join(SHOTS,width===1440?'draft-invoice-desktop.png':'draft-invoice-mobile.png'),fullPage:true});
   await p.evaluate(()=>window.NP03B_TEST.signOut());
   await check(width+' sign-out removes private invoice snapshot and audit',async()=>{
    assert.equal(await p.locator('.si-invoice,.si-snapshot,.si-audit li,[data-si-field="memo"]').count(),0);
   });await p.close();
  }
  const manager=await open(390,'bn','&persona=33333333-3333-4333-8333-333333333333');
  await check('manager cannot read owner-only invoice drafts',async()=>{assert.equal(await manager.locator('.si-invoice').count(),0);assert.match(await manager.locator('.si-status').textContent(),/প্রবেশাধিকার|অনুমতি|সেশন|session|DENIED/);});await manager.close();
  const foreign=await open(390,'en','&persona=77777777-7777-4777-8777-777777777777&scope=101&site=1001');
  await check('foreign tenant host scope fails closed without fallback',async()=>{assert.equal(await foreign.locator('.si-invoice').count(),0);assert.match(await foreign.locator('.si-status').textContent(),/denied|scope|session/i);});await foreign.close();
  const site=await open(390,'en','&scope=101&site=1002');
  await check('selected other site exposes no first-site invoice',async()=>{assert.equal(await site.locator('.si-scope select').nth(1).inputValue(),'1002');assert.equal(await site.locator('.si-invoice').count(),0);});await site.close();

  const stale=await open();await selectInvoice(stale,created[0]);
  const external=mutate(created[0],'Another real RPC editor','browser_invoice_external_edit');assert.equal(external.status,'draft');
  await stale.locator('[data-si-field="memo"]').fill('Stale browser memo');await save(stale);
  await check('independent real RPC amendment makes stale browser save fail',async()=>{
   assert.equal(invoice(created[0]).memo,'Another real RPC editor');assert.match(await stale.locator('.si-status').textContent(),/stale|version|rejected|changed/i);
  });await stale.close();

  const changed=await open();await selectInvoice(changed,created[0]);
  const prices=json('SELECT jsonb_agg(to_jsonb(x)) FROM (SELECT * FROM core10.master_price_list_items_v1 WHERE price_list_id=7101 AND item_id=8101 AND min_quantity=0 ORDER BY id) x;');
  const reprice=value=>{for(const row of prices){const version=Number(execute('SELECT version FROM core10.master_price_list_items_v1 WHERE id='+row.id+';'));
   owner('core10.master_save_price_v1(101,7101,8101,'+(row.variant_id===null?'NULL':row.variant_id)+','+row.uom_id+','+row.min_quantity+','+value+',true,'+version+','+literal('browser_invoice_price_'+row.id+'_'+version)+')');}};
  try{reprice(301);await changed.locator('[data-si-field="memo"]').fill('Reject changed authoritative price');await save(changed);
   await check('Master price change after load is rejected by actual server validation',async()=>{
    assert.notEqual(invoice(created[0]).memo,'Reject changed authoritative price');assert.match(await changed.locator('.si-status').textContent(),/Master|price|rejected|changed/i);
    assert.equal(await changed.locator('[data-si-action="save"]').isDisabled(),false);
    assert.equal(await changed.locator('[data-si-quantity="1"]').isDisabled(),false);
    assert.equal(await changed.locator('[data-si-action="retry"]').count(),0);
   });
  }finally{reprice(300);await changed.close();}

  const retry=await open();const retrySource=await begin(retry),keys=[];let lose=true;
  await retry.route('**/rpc/save_sales_invoice_draft_v1',async route=>{
   keys.push(route.request().postDataJSON().p_key);if(lose){lose=false;await route.fetch();return route.abort('failed');}return route.continue();
  });
  await save(retry);
  await check('lost response is reported as uncertain and freezes new mutations',async()=>{
   assert.match(await retry.locator('.si-status').textContent(),/uncertain|rejected/i);
   assert.equal(await retry.locator('[data-si-action="save"]').isDisabled(),true);
   assert.equal(await retry.locator('[data-si-quantity="1"]').isDisabled(),true);
  });
  await retry.locator('[data-si-action="retry"]').click();await idle(retry);
  await check('exact retry reuses command key and avoids duplicate invoice or audit',async()=>{
   assert.equal(keys.length,2);assert.equal(keys[0],keys[1]);assert.match(keys[0],/^[A-Za-z0-9_-]{8,100}$/);
   assert.equal(Number(execute('SELECT count(*) FROM core10.sales_invoice_commands_v1 WHERE request_key='+literal(keys[0])+';')),1);
   assert.equal(Number(execute('SELECT count(*) FROM core10.sales_invoice_drafts_v1 WHERE source_order_id='+retrySource+';')),1);
   const id=Number(await chosen(retry).getAttribute('data-invoice'));assert.equal(invoice(id).audit.length,1);
  });await retry.close();

  for(const broken of ['write-receipt','follow-up-read']){
   const p=await open();await selectInvoice(p,created[0]);const before=invoice(created[0]),requestKeys=[];
   const memo='Committed despite corrupt '+broken;let corrupt=true;
   await p.route('**/rpc/save_sales_invoice_draft_v1',async route=>{
    requestKeys.push(route.request().postDataJSON().p_key);
    if(broken==='write-receipt'&&corrupt){corrupt=false;const response=await route.fetch();assert.equal(response.ok(),true);
     const value=await response.json();value.issued=true;
     return route.fulfill({response,contentType:'application/json',body:JSON.stringify(value)});
    }return route.continue();
   });
   if(broken==='follow-up-read')await p.route('**/rpc/read_sales_invoice_drafts_v1',async route=>{
    if(corrupt){corrupt=false;const response=await route.fetch();assert.equal(response.ok(),true);
     const value=await response.json();assert.ok(value.invoices[0]);value.invoices[0].source_sha256='untrusted-source-hash';
     return route.fulfill({response,contentType:'application/json',body:JSON.stringify(value)});
    }return route.continue();
   });
   await p.locator('[data-si-field="memo"]').fill(memo);await save(p);
   await check(broken+' after real commit preserves uncertain input and blocks a fresh mutation',async()=>{
    const committed=invoice(created[0]);assert.equal(committed.memo,memo);assert.equal(committed.version,before.version+1);
    assert.match(await p.locator('.si-status').textContent(),/uncertain/i);
    assert.equal(await p.locator('[data-si-field="memo"]').inputValue(),memo);
    assert.equal(await p.locator('[data-si-action="save"]').isDisabled(),true);
    assert.equal(await p.locator('[data-si-quantity="1"]').isDisabled(),true);
    assert.equal(await p.locator('.si-scope select').first().isDisabled(),true);
   });
   await p.locator('[data-si-action="retry"]').click();await idle(p);
   await check(broken+' exact retry adopts the current invoice without another command',async()=>{
    assert.equal(requestKeys.length,2);assert.equal(requestKeys[0],requestKeys[1]);
    assert.equal(Number(execute('SELECT count(*) FROM core10.sales_invoice_commands_v1 WHERE request_key='+literal(requestKeys[0])+';')),1);
    assert.equal(invoice(created[0]).version,before.version+1);
    assert.equal(Number(await chosen(p).getAttribute('data-invoice')),created[0]);
    assert.equal(await p.locator('[data-si-field="memo"]').inputValue(),memo);
    assert.equal(await p.locator('[data-si-action="save"]').isDisabled(),false);
    assert.equal(await p.locator('[data-si-action="retry"]').count(),0);
   });await p.close();
  }

  const savedNav=await open();await selectInvoice(savedNav,created[0]);
  await savedNav.locator('[data-si-field="memo"]').fill('Save cancels obsolete navigation');
  await savedNav.locator('[data-sales-view="orders"]').click();
  assert.equal(await savedNav.locator('[data-si-action="discard"]').count(),1);
  await save(savedNav);
  await check('saving dirty navigation input clears pending discard and stays in invoices',async()=>{
   assert.equal(invoice(created[0]).memo,'Save cancels obsolete navigation');
   assert.equal(await savedNav.locator('.si-workspace').count(),1);
   assert.equal(await savedNav.locator('.so-workspace:not(.si-workspace)').count(),0);
   assert.equal(await savedNav.locator('[data-si-action="discard"]').count(),0);
  });await savedNav.close();

  const dirty=await open();await selectInvoice(dirty,created[0]);await dirty.locator('[data-si-field="memo"]').fill('Unfinished invoice input');
  await dirty.locator('[data-sales-view="orders"]').click();
  await check('dirty invoice input blocks navigation into the order workspace',async()=>{
   assert.equal(await dirty.locator('[data-si-field="memo"]').inputValue(),'Unfinished invoice input');assert.match(await dirty.locator('.si-status').textContent(),/unsaved|unfinished|discard/i);
   assert.equal(await dirty.locator('.so-workspace:not(.si-workspace) .so-form').count(),0);
  });
  await dirty.locator('[data-si-action="discard"]').click();
  await dirty.waitForSelector('.so-workspace:not(.si-workspace)');
  await dirty.waitForFunction(()=>document.querySelector('.so-workspace')?.getAttribute('aria-busy')==='false');
  await check('explicit discard enters the existing orders view without a second shell',async()=>{
   assert.equal(await dirty.locator('.si-workspace').count(),0);assert.equal(await dirty.locator('.studio-rail').count(),1);
  });
  const linkedOrder=invoice(created[0]).source_order_id;
  const invoiceCount=Number(execute('SELECT count(*) FROM core10.sales_invoice_drafts_v1;'));
  await dirty.locator('.so-order[data-order="'+linkedOrder+'"]').click();
  await dirty.locator('[data-action="invoice-from-order"]').click();await idle(dirty);
  await check('confirmed order action opens its existing invoice without a duplicate draft',async()=>{
   assert.equal(Number(await chosen(dirty).getAttribute('data-invoice')),created[0]);
   assert.equal(invoice(created[0]).source_order_id,linkedOrder);
   assert.equal(Number(execute('SELECT count(*) FROM core10.sales_invoice_drafts_v1;')),invoiceCount);
  });await dirty.close();

  const liveOff=await open();await selectInvoice(liveOff,created[0]);const beforeOff=invoice(created[0]);
  await liveOff.locator('[data-si-field="memo"]').fill('Disabled after invoice loaded');
  control('sales.invoice_draft',false,'browser_invoice_live_off');
  try{await save(liveOff);await check('Owner disable after page load rejects actual save without changing the draft',async()=>{
   const current=invoice(created[0]);assert.equal(current.version,beforeOff.version);assert.equal(current.memo,beforeOff.memo);
   assert.match(await liveOff.locator('.si-status').textContent(),/disabled|switched off/i);
   assert.equal(await liveOff.locator('[data-si-action="retry"]').count(),0);
  });}finally{control('sales.invoice_draft',true,'browser_invoice_live_restore');await liveOff.close();}

  const validationBefore=owner('core10.control_read_v1(101)').find(x=>x.feature_key==='sales.invoice_validate');
  control('sales.invoice_validate',true,'browser_invoice_approval_on',1);
  try{const approval=await open();await selectInvoice(approval,created[0]);const before=invoice(created[0]);
   assert.equal(await approval.locator('[data-si-field="approval"]').count(),1);
   await approval.locator('[data-si-action="validate"]').click();await idle(approval);
   await check('one-stage UI validation without an approval ID is denied by the real server',async()=>{
    assert.equal(invoice(created[0]).version,before.version);assert.equal(invoice(created[0]).validated,before.validated);
    assert.match(await approval.locator('.si-status').textContent(),/approval|required/i);
    assert.equal(await approval.locator('[data-si-action="retry"]').count(),0);
   });await approval.close();
  }finally{control('sales.invoice_validate',validationBefore.enabled,'browser_invoice_approval_restore',validationBefore.stages);}

  const inflight=await open();let release,arrived;const gate=new Promise(r=>release=r),waiting=new Promise(r=>arrived=r);
  await inflight.route('**/rpc/read_sales_invoice_drafts_v1',async route=>{const response=await route.fetch();arrived();await gate;await route.fulfill({response});});
  await inflight.locator('[data-si-action="reload"]').click();await waiting;await inflight.evaluate(()=>window.NP03B_TEST.signOut());
  const response=inflight.waitForResponse(r=>r.url().endsWith('/rpc/read_sales_invoice_drafts_v1'));release();await response;
  await inflight.evaluate(()=>new Promise(r=>setTimeout(r,50)));
  await check('late real read after sign-out cannot restore invoice data',async()=>{
   assert.equal(await inflight.locator('.si-invoice,.si-snapshot,.si-audit li,[data-si-field="memo"]').count(),0);
   assert.equal(await inflight.locator('.si-workspace').getAttribute('aria-busy'),'false');
  });await inflight.close();

  control('sales.invoice_validate',false,'browser_invoice_validate_off');
  try{const off=await open(390,'bn');await selectInvoice(off,created[0]);
   await check('actual Owner-off validation setting disables validation and explains why',async()=>{
    assert.equal(await off.locator('[data-si-action="validate"]').isDisabled(),true);
    assert.match(await off.locator('.so-transitions').textContent(),/বন্ধ|disabled|switched off/i);
   });await off.close();
  }finally{control('sales.invoice_validate',true,'browser_invoice_validate_restore');}
  control('sales.invoice_draft',false,'browser_invoice_draft_off');
  try{const off=await open(390,'bn');await check('actual Owner-off setting disables new draft creation',async()=>{
   assert.equal(await off.locator('[data-si-action="new"]').isDisabled(),true);assert.match(await off.locator('.si-workspace').textContent(),/বন্ধ|disabled|switched off/i);
  });await off.close();}finally{control('sales.invoice_draft',true,'browser_invoice_draft_restore');}
  assert.equal(Number(execute('SELECT count(*) FROM core10.stock_movements;')),0,'draft UI made no stock movements');
  assert.equal(Number(execute('SELECT count(*) FROM core10.finance_journals_v1;')),0,'draft UI made no financial journals');
  assert.equal(Number(execute("SELECT count(*) FROM core10.sales_invoice_drafts_v1 WHERE status<>'draft';")),0,'no invoice issuance');
  assert.deepEqual(errors,[]);console.log('NP03B_INVOICE_BROWSER_PASS '+passed+'; real PG17 RPCs, synthetic Auth/data, draft-only');
 }finally{await browser.close();await new Promise(resolve=>server.close(resolve));}
})().catch(e=>{console.error(e);process.exitCode=1;});
