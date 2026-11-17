'use strict';
// Real canonical Master functions; local SQL gateway/synthetic subject, no hosted certification.
const {chromium}=require('playwright'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {start,psql}=require('./gateway.cjs');
(async()=>{
 const server=await start(),base='http://127.0.0.1:'+server.address().port,shots=process.env.MFG_SHOTS||'/tmp/np05a-master-shots';fs.mkdirSync(shots,{recursive:true});
 const browser=await chromium.launch({headless:true,args:['--no-sandbox']});let checks=0;
 const owner="select set_config('request.jwt.claims','{\"sub\":\"95111111-1111-4111-8111-111111111111\"}',false);";
 const alterAlternative=status=>psql(owner+`select core10.master_save_item_v1(9511,sku,name_en,name_bn,item_kind,category_id,base_uom_id,'${status}',version,'mfg_browser_'||md5(clock_timestamp()::text)) from core10.items where business_id=9511 and sku='MFG-ALT'`);
 const toggle=enabled=>psql(owner+`select core10.control_set_v1(9511,NULL,'mfg.material_requirements',${enabled},0::smallint,'{}',NULL,false,(select coalesce(max(version),0)::int from core10.control_setting_versions_v1 where business_id=9511 and site_id is null and feature_key='mfg.material_requirements'),'Synthetic browser gate','mfg_browser_'||md5(clock_timestamp()::text))`);
 try{
 for(const width of [390,1440]){
  const page=await browser.newPage({viewport:{width,height:900}}),errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.goto(base+'/harness.html');await page.waitForSelector('[data-master]');
  for(const lang of ['bn','en']){
   if(lang==='en')await page.click('[data-lang]');
   const card=page.locator('article').filter({hasText:'MASTER-LIVE'}).first();await card.locator('[data-master]').click();
   await page.fill('[name=master_multiplier]','2');await page.click('#mfg-content form button');await page.waitForSelector('#mfg-master-report');
   const report=await page.locator('#mfg-master-report').textContent();
   assert.match(report,/VERIFIED_CANONICAL/);checks++;
   assert.match(report,/3000 MFG_G → 3 MFG_KG/);checks++;
   assert.match(report,/2 MFG_BOX → 20 MFG_PC/);checks++;
   assert.match(report,/2 MFG_KG → 2000 MFG_G/);checks++;
   assert.match(report,/stock_issued=false.*financial_posted=false/);checks++;
   assert.match(report,lang==='bn'?/বর্তমান Master/:/current Master/);checks++;
   assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));checks++;
   await page.screenshot({path:path.join(shots,`master-validation-${lang}-${width}.png`),fullPage:true});
   await page.click('[data-tab=recipes]');
  }
  // The verified preview is a separate versioned read; the old unvalidated math preview remains labelled.
  await page.locator('article').filter({hasText:'MASTER-LIVE'}).first().locator('[data-substitution]').click();await page.waitForSelector('[data-verified=true]');
  await page.locator('[data-verified=true]').first().click();await page.fill('[name=sub_multiplier]','2');await page.click('#mfg-content form button');await page.waitForSelector('#mfg-substitution-preview');
  const preview=await page.locator('#mfg-substitution-preview').textContent();assert.match(preview,/VERIFIED_CANONICAL/);checks++;
  assert.match(preview,/1500 MFG_G → 1.5 MFG_KG/);checks++;
  assert.match(preview,/1 MFG_KG → 1000 MFG_G/);checks++;
  assert.match(preview,/batch_selected=false/);checks++;
  assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));checks++;
  await page.screenshot({path:path.join(shots,`master-preview-en-${width}.png`),fullPage:true});
  // Real canonical item deactivation must prevent the same UI report.
  alterAlternative('inactive');
  await page.click('[data-tab=recipes]');await page.locator('article').filter({hasText:'MASTER-LIVE'}).first().locator('[data-master]').click();await page.click('#mfg-content form button');
  await page.waitForFunction(()=>document.querySelector('[role=status]').textContent.includes('MFG_MASTER_ITEM_UNUSABLE'));checks++;
  assert.equal(await page.locator('#mfg-master-report').count(),0);checks++;
  await page.screenshot({path:path.join(shots,`master-error-${width}.png`),fullPage:true});alterAlternative('active');
  toggle(false);await page.click('#mfg-content form button');await page.waitForFunction(()=>document.querySelector('[role=status]').textContent.includes('CONTROL_DISABLED'));checks++;toggle(true);
  assert.deepEqual(errors,[]);checks++;await page.close();
 }
 const denied=await browser.newPage({viewport:{width:390,height:900}});await denied.goto(base+'/harness.html?persona=95777777-7777-4777-8777-777777777777');
 await denied.waitForFunction(()=>document.querySelector('[role=status]').textContent.includes('MFG_SCOPE_DENIED'));assert.equal(await denied.locator('[data-master]').count(),0);checks++;await denied.close();
 const verified=JSON.parse(psql(owner+'select core10.verify_canonical_audit_v1(9511)').split('\n').at(-1));assert.equal(verified.ok,true);checks++;
 fs.writeFileSync(path.join(shots,'results.json'),JSON.stringify({checks,passed:checks,master:'REAL_CANONICAL_0151_0153',synthetic_subject:true,stock:'NOT_CONNECTED',money:'NOT_CONNECTED',approval_completion:'NOT_CONNECTED'},null,2));console.log('NP05A_MASTER_BROWSER_OK '+checks+' checks at 390/1440 bn/en');
 }finally{await browser.close();await new Promise(r=>server.close(r));}
})().catch(e=>{console.error(e);process.exitCode=1;});
