'use strict';
const {chromium}=require('playwright'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {start,psql}=require('./gateway.cjs');
(async()=>{
 const server=await start(),base='http://127.0.0.1:'+server.address().port,shots=process.env.MFG_SHOTS||'/tmp/np05a-shots';fs.mkdirSync(shots,{recursive:true});
 const browser=await chromium.launch({headless:true,args:['--no-sandbox']});let checks=0;
 try{
 for(const width of [390,1440]){
  const page=await browser.newPage({viewport:{width,height:900}}),errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.goto(base+'/harness.html');await page.waitForSelector('[data-plan]:visible');
  assert.equal(await page.locator('.mfg-pills span').count(),4);checks++;
  await page.fill('[name=code]','BROWSER-'+width);await page.fill('[name=item]','9541');await page.fill('[name=yield]','100');await page.fill('[name=uom]','fixture:piece');
  await page.fill('[name=lines]','[{"item":9542,"qty":10,"uom_ref":"fixture:kg","kind":"ingredient","waste_pct":2,"estimated_unit_cost":80}]');
  await page.click('#mfg-recipe-form button');await page.waitForFunction(()=>document.querySelector('[role=status]').textContent.includes('Audit #'));checks++;
  assert.match(await page.locator('#mfg-content').textContent(),new RegExp('BROWSER-'+width));checks++;
  await page.screenshot({path:path.join(shots,'recipes-'+width+'.png'),fullPage:true});
  // Default approval remains maker/checker-controlled and visible, even on a test adapter.
  await page.locator('[data-approve]:visible').first().click();await page.waitForFunction(()=>document.querySelector('[role=status]').textContent.includes('MFG_MAKER_CHECKER'));checks++;
  await page.locator('[data-materials]').first().click();await page.fill('[name=multiplier]','2');await page.click('#mfg-content form button');await page.waitForSelector('#mfg-material-report');
  assert.match(await page.locator('#mfg-material-report').textContent(),/20 fixture:kg/);checks++;
  assert.match(await page.locator('#mfg-material-report').textContent(),/অজানা.*NOT_CONNECTED/);checks++;
  assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));checks++;
  await page.screenshot({path:path.join(shots,'materials-'+width+'.png'),fullPage:true});
  await page.click('[data-tab=batches]');await page.locator('[data-handoff]').first().click();await page.waitForFunction(()=>document.querySelector('[role=status]').textContent.includes('NOT_CONNECTED'));checks++;
  assert.match(await page.locator('#mfg-handoff').textContent(),/Source fingerprint|সূত্রের পরিচায়ক/);checks++;
  assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'source fingerprint wraps');checks++;
  await page.screenshot({path:path.join(shots,'batches-'+width+'.png'),fullPage:true});
  await page.locator('[data-waste]:visible').first().click();await page.waitForSelector('#mfg-waste-form');
  const note='Fictional UI spill '+width,calls=[];let loseFirst=true;
  await page.fill('[name=waste_quantity]','0.1');await page.selectOption('[name=waste_reason]','SPILLAGE');await page.fill('[name=waste_note]',note);
  await page.route('**/rpc/mfg_record_material_waste_v1',async route=>{
    calls.push(route.request().postDataJSON());
    if(loseFirst){loseFirst=false;const response=await route.fetch();assert.equal(response.status(),200);await route.abort('failed');}
    else await route.continue();
  });
  // Commit real SQL, then lose the transport response. Retrying must reuse its original command key.
  await page.click('#mfg-waste-form button');await page.waitForFunction(()=>document.querySelector('[role=status]').textContent.includes('ফল অজানা'));checks++;
  await page.fill('[name=waste_quantity]','0.2');await page.click('#mfg-waste-form button');await page.waitForFunction(()=>document.querySelector('[role=status]').textContent.includes('আগের অনুরোধের ফল অজানা'));checks++;
  assert.equal(calls.length,1,'uncertain changed payload must not create another request');checks++;
  await page.fill('[name=waste_quantity]','0.1');await page.click('#mfg-waste-form button');await page.waitForFunction(()=>document.querySelector('[role=status]').textContent.includes('অপচয় সংরক্ষিত'));checks++;
  assert.equal(calls.length,2);assert.equal(calls[0].p_key,calls[1].p_key,'same request key after ambiguous response');checks++;
  assert.equal(await page.locator('#mfg-waste-events .op-record').filter({hasText:note}).count(),1,'one observation after retry');checks++;
  assert.match(await page.locator('#mfg-waste-report').textContent(),/আবার stock কাটা বা খরচ যোগ হয় না/);checks++;
  assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'waste report fits');checks++;
  await page.screenshot({path:path.join(shots,'waste-'+width+'.png'),fullPage:true});await page.unroute('**/rpc/mfg_record_material_waste_v1');
  await page.click('[data-tab=reports]');assert.match(await page.locator('#mfg-content').textContent(),/95/);checks++;
  assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'no horizontal overflow');checks++;
  await page.screenshot({path:path.join(shots,'yield-'+width+'.png'),fullPage:true});
  await page.click('[data-lang]');assert.match(await page.locator('h1').textContent(),/Sweets/);checks++;
  await page.evaluate(()=>window.disposeMfg());assert.equal(await page.locator('#manufacturing').textContent(),'');checks++;
  assert.deepEqual(errors,[]);checks++;await page.close();
 }
 const denied=await browser.newPage({viewport:{width:390,height:844}});
 await denied.goto(base+'/harness.html?persona=95777777-7777-4777-8777-777777777777');await denied.waitForFunction(()=>document.querySelector('[role=status]').textContent.includes('MFG_SCOPE_DENIED'));
 assert.equal(await denied.locator('[data-approve]:visible').count(),0);checks++;await denied.screenshot({path:path.join(shots,'revoked-390.png'),fullPage:true});
 const history=JSON.parse(psql("select core10.verify_canonical_audit_v1(9511)".replace('select ',"select set_config('request.jwt.claims','{\"sub\":\"95222222-2222-4222-8222-222222222222\"}',false); select ")).split('\n').at(-1));assert.equal(history.ok,true);checks++;
 fs.writeFileSync(path.join(shots,'results.json'),JSON.stringify({checks,passed:checks,synthetic_claims:true,master_adapter:'TEST_ONLY',stock:'NOT_CONNECTED',finance:'NOT_CONNECTED'},null,2));
 console.log('NP05A_BROWSER_OK '+checks+' checks at 390/1440');
 }finally{await browser.close();await new Promise(r=>server.close(r));}
})().catch(e=>{console.error(e);process.exitCode=1;});
