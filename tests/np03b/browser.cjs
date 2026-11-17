'use strict';
// Existing Build01 shell + NP03B module + real disposable SQL. Synthetic Auth
// is explicitly labelled; real canonical Master functions and synthetic data, not hosted sign-in.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {chromium}=require('playwright');const {start,sql}=require('./ui-gateway.cjs');
const ROOT=path.resolve(__dirname,'../..'),SHOTS=process.env.NP03B_SHOTS||path.join(ROOT,'artifacts/np03b');
let passed=0;
(async()=>{fs.mkdirSync(SHOTS,{recursive:true});const server=await start(),base='http://127.0.0.1:'+server.address().port;
 const browser=await chromium.launch({...(process.env.NP03B_CHROMIUM?{executablePath:process.env.NP03B_CHROMIUM}:{}),args:['--no-sandbox']});
 const errors=[];
 async function check(name,fn){await fn();passed++;console.log('PASS '+name);}
 async function open(width,lang,extra='',setup){const page=await browser.newPage({viewport:{width,height:width<500?844:1000},deviceScaleFactor:1});page.setDefaultTimeout(12000);page.on('pageerror',e=>errors.push(e.message));if(setup)await setup(page);await page.goto(base+'/harness.html?lang='+lang+extra);await page.waitForSelector('body[data-ready="1"]');return page;}
 const idle=page=>page.waitForFunction(()=>document.querySelector('.so-workspace')?.getAttribute('aria-busy')==='false');
 try{
  for(const [width,lang] of [[1440,'en'],[390,'bn']]){
   const p=await open(width,lang);
   await check(width+' existing shell and truthful synthetic boundary',async()=>{assert.equal(await p.locator('.studio-rail').count(),1);assert.match(await p.locator('.so-boundary').textContent(),/Synthetic|সিনথেটিক/);assert.equal(await p.locator('.so-scope select').first().inputValue(),'101');});
   await check(width+' language toggle preserves keyboard position',async()=>{await p.locator('[data-so-focus="language"]').click();assert.equal(await p.locator('[data-so-focus="language"]').evaluate(x=>x===document.activeElement),true);await p.locator('[data-so-focus="language"]').click();assert.equal(await p.locator('.so-workspace').getAttribute('lang'),lang);});
   await p.locator('.so-list .primary').click();
   await check(width+' new order hands keyboard focus to the form',async()=>{assert.equal(await p.locator('[data-so-focus="customer"]').evaluate(x=>x===document.activeElement),true);});
   await check(width+' language toggle updates canonical customer/product/UOM labels',async()=>{const before=await p.locator('[data-product="0"] option:checked').textContent();await p.locator('[data-so-focus="language"]').click();const after=await p.locator('[data-product="0"] option:checked').textContent();assert.notEqual(after,before);assert.match(after,lang==='en'?/রসগোল্লা/:/Rasgulla Box/);assert.match(await p.locator('[data-so-focus="customer"] option:checked').textContent(),lang==='en'?/ক্রেতা/:/Synthetic Bakery Customer/);await p.locator('[data-so-focus="language"]').click();assert.equal(await p.locator('[data-product="0"] option:checked').textContent(),before);});
   const qty=p.locator('[data-field="quantity"][data-line="0"]');
   await check(width+' native accessible quantity constraint',async()=>{await qty.fill('0');assert.equal(await qty.evaluate(x=>x.checkValidity()),false);await qty.fill('0.5');assert.equal(await qty.evaluate(x=>x.checkValidity()),false);assert.equal(await qty.getAttribute('step'),'1');assert.equal(await p.locator('.so-form input').evaluateAll(a=>a.every(x=>!!x.closest('label'))),true);});
   await qty.fill('2');await p.locator('[data-field="discount_percent"][data-line="0"]').fill('5');
   await p.locator('.so-form>button.outline').click();await p.locator('[data-product="1"]').selectOption('3');
   await check(width+' product rerender preserves keyboard focus',async()=>{assert.equal(await p.locator('[data-product="1"]').evaluate(x=>x===document.activeElement),true);});
   await check(width+' product selection uses catalog price',async()=>{assert.equal(await p.locator('[data-field="unit_price"][data-line="1"]').inputValue(),'1200');});
   await p.locator('[data-action="save"]').click();await idle(p);
   await check(width+' actual SQL create response and total',async()=>{assert.match(await p.locator('.so-status').textContent(),/saved|সংরক্ষণ/);assert.ok((await p.locator('.so-detail>p.so-muted').textContent()).includes('1'));assert.equal(await p.locator('.so-order[aria-pressed=true]').count(),1);});
   await check(width+' asynchronous save restores keyboard focus',async()=>{assert.equal(await p.locator('[data-action="save"]').evaluate(x=>x===document.activeElement),true);});
   await p.locator('.so-audit button').click();await idle(p);
   await check(width+' scoped canonical audit is visible',async()=>{assert.equal(await p.locator('.so-audit li').count(),1);});
   await p.locator('[data-field="quantity"][data-line="0"]').fill('3');
   await check(width+' unsaved edits cannot confirm the old document',async()=>{assert.equal(await p.locator('.so-transitions button').first().isDisabled(),true);});
   await p.locator('[data-action="save"]').click();await idle(p);await p.locator('.so-transitions button').first().click();await idle(p);
   await check(width+' actual SQL amend/confirm and immutable form',async()=>{assert.match(await p.locator('.so-state').first().textContent(),/Confirmed|নিশ্চিত/);assert.equal(await p.locator('[data-action="save"]').isDisabled(),true);});
   await p.locator('.so-audit button').click();await idle(p);
   await check(width+' all three canonical command events',async()=>{assert.equal(await p.locator('.so-audit li').count(),3);});
   await check(width+' mobile/desktop containment and keyboard focus',async()=>{assert.ok(await p.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));await p.locator('.so-scope select').first().focus();assert.equal(await p.locator('.so-scope select').first().evaluate(x=>x===document.activeElement),true);});
   if(!process.env.NP03B_SKIP_SHOTS)await p.screenshot({path:path.join(SHOTS,width===1440?'sales-order-desktop.png':'sales-order-mobile.png'),fullPage:true});
   await p.evaluate(()=>window.NP03B_TEST.signOut());
   await check(width+' sign-out immediately clears private order/audit view',async()=>{assert.equal(await p.locator('.so-order,.so-audit li,.so-form').count(),0);});await p.close();
  }
  const denied=await open(390,'bn','&persona=33333333-3333-4333-8333-333333333333');
  await check('manager denied by actual owner-only boundary',async()=>{assert.match(await denied.locator('.so-status').textContent(),/অনুমতি নেই|সেশন/);assert.equal(await denied.locator('.so-order').count(),0);});await denied.close();
  const scoped=await open(390,'en','&scope=101&site=1002');await check('host selected scope is honored after canonical context validation',async()=>{assert.equal(await scoped.locator('.so-scope select').nth(1).inputValue(),'1002');});await scoped.close();
  const foreign=await open(390,'en','&scope=201&site=2001');await check('foreign requested host scope is denied without fallback',async()=>{assert.match(await foreign.locator('.so-status').textContent(),/access is denied/);assert.equal(await foreign.locator('.so-order').count(),0);});await foreign.close();
  const missing=await open(1440,'en','&missing=1');
  await check('missing Master catalog locks create but keeps scoped history',async()=>{assert.equal(await missing.locator('.so-list .primary').isDisabled(),true);assert.match(await missing.locator('.so-note').first().textContent(),/Master catalog is not connected/);await missing.locator('.so-order').first().click();await missing.locator('.so-audit button').click();await idle(missing);assert.equal(await missing.locator('.so-audit li').count(),3);});await missing.close();
  const discard=await open(1440,'en');await discard.locator('.so-list .primary').click();await discard.locator('[data-field="quantity"]').fill('2');await discard.locator('.so-scope select').nth(1).selectOption('1002');
  await check('unsaved form survives a scope change until explicit discard',async()=>{assert.equal(await discard.locator('.so-scope select').nth(1).inputValue(),'1001');assert.equal(await discard.locator('[data-field="quantity"]').inputValue(),'2');assert.match(await discard.locator('.so-status').textContent(),/unsaved input/);});
  await discard.getByRole('button',{name:'Discard unfinished form and continue',exact:true}).click();await idle(discard);
  await check('explicit discard changes site and clears old private form',async()=>{assert.equal(await discard.locator('.so-scope select').nth(1).inputValue(),'1002');assert.equal(await discard.locator('.so-form,.so-order').count(),0);});await discard.close();
  const stale=await open(1440,'en');let release,arrived;const gate=new Promise(r=>release=r),waiting=new Promise(r=>arrived=r);
  await stale.route('**/rpc/read_sales_orders_v1',async route=>{const response=await route.fetch();arrived();await gate;await route.fulfill({response});});
  await stale.locator('.so-scope>button').click();await waiting;await stale.evaluate(()=>window.NP03B_TEST.signOut());release();await stale.waitForResponse(r=>r.url().endsWith('/rpc/read_sales_orders_v1'));await stale.evaluate(()=>new Promise(r=>setTimeout(r,50)));
  await check('in-flight read after sign-out cannot repopulate private state',async()=>{assert.equal(await stale.locator('.so-order,.so-form').count(),0);assert.equal(await stale.evaluate(()=>window.NP03B_TEST.controller.getState().businessId),null);assert.equal(await stale.locator('.so-workspace').getAttribute('aria-busy'),'false');});await stale.close();
  const retry=await open(1440,'en');await retry.locator('.so-list .primary').click();const keys=[];let drop=true;
  await retry.route('**/rpc/save_sales_order_v1',async route=>{keys.push(route.request().postDataJSON().p_key);if(drop){drop=false;await route.fetch();return route.abort('failed');}return route.continue();});
  await retry.locator('[data-action="save"]').click();await idle(retry);
  await check('lost response never claims successful save',async()=>{assert.match(await retry.locator('.so-status').textContent(),/uncertain|rejected/i);assert.equal(await retry.locator('.so-order[aria-pressed=true]').count(),0);});
  await check('uncertain command freezes edits and scope until exact retry',async()=>{assert.equal(await retry.locator('[data-action="save"]').isDisabled(),true);assert.equal(await retry.locator('[data-field="quantity"]').isDisabled(),true);assert.equal(await retry.locator('.so-scope select').first().isDisabled(),true);});
  await retry.locator('[data-retry="true"]').click();await idle(retry);
  await check('retry reuses key and creates only one server order',async()=>{assert.equal(keys.length,2);assert.equal(keys[0],keys[1]);const out=sql("SELECT count(*) FROM core10.sales_order_commands_v1 WHERE request_key='"+keys[0]+"';");assert.equal(out.status,0);assert.equal(out.stdout.trim(),'1');});await retry.close();
  const disconnected=await open(1440,'en','',async p=>p.route('**/rpc/master_list_uoms_v1',r=>r.fulfill({status:404,contentType:'application/json',body:JSON.stringify({code:'PGRST202',message:'NOT_CONNECTED:MASTER_CATALOG'})})));
  await check('missing actual Master reader fails closed without creation UI',async()=>{assert.equal(await disconnected.locator('.so-form').count(),0);assert.equal(await disconnected.locator('.so-list .primary').isDisabled(),true);});await disconnected.close();
  const changed=await open(1440,'en');await changed.locator('.so-list .primary').click();
  const inactive=sql("UPDATE core10.items SET status='inactive' WHERE id=8101;");assert.equal(inactive.status,0,inactive.stderr);
  await changed.locator('[data-action="save"]').click();await idle(changed);
  await check('Master change after catalog load rejects save without success UI',async()=>{assert.equal(await changed.locator('.so-order[aria-pressed=true]').count(),0);assert.match(await changed.locator('.so-status').textContent(),/rejected|Master/i);});await changed.close();
  const active=sql("UPDATE core10.items SET status='active' WHERE id=8101;");assert.equal(active.status,0,active.stderr);
  const off=sql("SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false); SELECT core10.control_set_v1(101,NULL,'sales.order_draft',false,0::smallint,'{}',NULL,false,1,'Synthetic browser switch off','ui_disable_draft');");assert.equal(off.status,0,off.stderr);
  const disabled=await open(390,'bn');await check('actual Owner Control disabled state',async()=>{assert.equal(await disabled.locator('.so-list .primary').isDisabled(),true);assert.match(await disabled.locator('.so-note').last().textContent(),/বন্ধ রেখেছেন/);});await disabled.close();
  assert.deepEqual(errors,[]);console.log('NP03B_BROWSER_PASS '+passed+'; synthetic Auth/data, canonical Master and real PG17 RPCs');
 }finally{await browser.close();await new Promise(r=>server.close(r));}
})().catch(e=>{console.error(e);process.exitCode=1;});
