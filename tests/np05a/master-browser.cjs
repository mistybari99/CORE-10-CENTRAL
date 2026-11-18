'use strict';
// Real canonical Master functions; local SQL gateway/synthetic subject, no hosted certification.
const crypto=require('node:crypto');
const {chromium}=require('playwright'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {start,psql}=require('./gateway.cjs');
(async()=>{
 const server=await start(),base='http://127.0.0.1:'+server.address().port,shots=process.env.MFG_SHOTS||'/tmp/np05a-master-shots';fs.mkdirSync(shots,{recursive:true});
 const browser=await chromium.launch({headless:true,args:['--no-sandbox']});let checks=0;
 const owner="select set_config('request.jwt.claims','{\"sub\":\"95111111-1111-4111-8111-111111111111\"}',false);";
 // Complete real canonical Stock/Money rows must be identical before/after planning and guarded requests.
 const postingTables=['stock_movements','stock_balances_v1','stock_transfers_v1','finance_accounts_v1','finance_periods_v1','finance_journals_v1','finance_journal_lines_v1','finance_reversals_v1'];
 const snapshot=()=>psql('select jsonb_build_object('+postingTables.map(t=>`'${t}',(select coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text),'[]'::jsonb) from core10.${t} x)`).join(',')+')');
 const beforePosting=snapshot(),snapshotHash=crypto.createHash('sha256').update(beforePosting).digest('hex'),sources=[];
 const batch=Number(psql("select b.id from core10.production_batches_v1 b join core10.bom_recipes_v1 r on r.id=b.bom_id where b.business_id=9511 and r.recipe_code='RACE' and b.status='recorded'"));assert.ok(Number.isSafeInteger(batch)&&batch>0);
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
  // Observe actual RPC responses from the existing UI; no synthetic successful posting response.
  for(const lang of ['en','bn']){
   if(lang==='bn')await page.click('[data-lang]');
   await page.click('[data-tab=batches]');
   const responseWait=page.waitForResponse(r=>r.url().endsWith('/rpc/mfg_request_handoff_v1')&&r.request().method()==='POST');
   await page.locator(`[data-handoff="${batch}"]`).click();const http=await responseWait;assert.equal(http.status(),200);const result=await http.json();
   await page.waitForSelector('#mfg-handoff');assert.equal(result.status,'NOT_CONNECTED');checks++;
   assert.equal(result.stock_issued,false);assert.equal(result.stock_received,false);assert.equal(result.financial_posted,false);checks++;
   const e=result.source_envelope;assert.equal(e.contract_status,'PROPOSED_NOT_CONNECTED');assert.equal(e.master_uom,'NOT_CONNECTED');assert.equal(e.lot_validation,'NOT_CONNECTED');checks++;
   assert.equal(e.scope.business_id,9511);assert.equal(e.scope.site_id,9521);assert.equal(e.source.batch_id,batch);checks++;
   assert.equal(e.substitution_selected,false);assert.equal(e.planning_cost.recognized_value,null);assert.equal(e.planning_cost.journal_entries,null);checks++;
   assert.ok(e.source.batch_audit_event_ids.length>=3&&e.source.recipe_audit_event_ids.length>=2);checks++;
   const sourceAuditIds=[...new Set([...e.source.batch_audit_event_ids,...e.source.recipe_audit_event_ids])];assert.ok(sourceAuditIds.every(Number.isSafeInteger));
   assert.equal(Number(psql(`select count(*) from core10.canonical_audit_events_v1 where business_id=9511 and source_domain='manufacturing' and id=any(array[${sourceAuditIds.join(',')}]::bigint[])`)),sourceAuditIds.length);checks++;
   const linked=JSON.parse(psql(`select jsonb_build_object('valid',a.source_domain='manufacturing' and a.action='mfg.handoff_request','recipe',b.bom_id,'receipt_business',r.business_id,'fingerprint',encode(sha256(convert_to(((r.response->'source_envelope')-'source_fingerprint')::text,'UTF8')),'hex')) from core10.mfg_command_receipts_v1 r join core10.canonical_audit_events_v1 a on a.id=r.audit_event_id join core10.production_batches_v1 b on b.id=(r.response->>'batch_id')::bigint where r.business_id=9511 and r.audit_event_id=${Number(result.audit_event_id)}`));
   assert.equal(linked.valid,true);assert.equal(linked.recipe,e.source.recipe_id);assert.equal(linked.receipt_business,9511);assert.equal(linked.fingerprint,e.source_fingerprint);checks++;
   if(sources.length)assert.equal(e.source_fingerprint,sources[0].fingerprint);checks++;
   sources.push({width,lang,batch,recipe:e.source.recipe_id,recipe_version:e.source.recipe_version,audit_event_id:result.audit_event_id,fingerprint:e.source_fingerprint,status:result.status});
   assert.match(await page.locator('#mfg-handoff').textContent(),lang==='bn'?/কোনো স্টক বা অর্থ পোস্ট হয়নি/:/No Stock or Money posted/);checks++;
   assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));checks++;
   await page.screenshot({path:path.join(shots,`source-handoff-${lang}-${width}.png`),fullPage:true});
  }
  assert.equal(snapshot(),beforePosting,'canonical Stock/Money rows unchanged after previews, Control negatives and guarded handoffs');checks++;
  assert.deepEqual(errors,[]);checks++;await page.close();
 }
 const denied=await browser.newPage({viewport:{width:390,height:900}});await denied.goto(base+'/harness.html?persona=95777777-7777-4777-8777-777777777777');
 await denied.waitForFunction(()=>document.querySelector('[role=status]').textContent.includes('MFG_SCOPE_DENIED'));assert.equal(await denied.locator('[data-master]').count(),0);checks++;await denied.close();
 const verified=JSON.parse(psql(owner+'select core10.verify_canonical_audit_v1(9511)').split('\n').at(-1));assert.equal(verified.ok,true);checks++;
 assert.equal(snapshot(),beforePosting,'complete browser scenario cannot mutate Stock or Money');checks++;
 fs.writeFileSync(path.join(shots,'results.json'),JSON.stringify({checks,passed:checks,posting_tables_checked:postingTables,posting_snapshot_sha256:snapshotHash,posting_snapshot_unchanged:true,source_handoffs:sources,master:'REAL_CANONICAL_0151_0153',synthetic_subject:true,stock:'NOT_CONNECTED',money:'NOT_CONNECTED',approval_completion:'NOT_CONNECTED'},null,2));console.log('NP05A_MASTER_BROWSER_OK '+checks+' checks at 390/1440 bn/en');
 }finally{await browser.close();await new Promise(r=>server.close(r));}
})().catch(e=>{console.error(e);process.exitCode=1;});
