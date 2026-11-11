// C10-A055 real-DOM browser E2E at 390px (mobile) and 1440px (desktop). Chromium + the real A055 pages/JS.
// SYNTHETIC FIXTURE: the page's Supabase library is replaced by a tiny test adapter (clearly labelled below) that forwards RPC calls
// same-origin to the disposable signed-HMAC PostgREST; signed test JWTs live only in this Node process (never in the page).
// NOT GoTrue, NOT staging, NOT production. Disposable synthetic data only.
"use strict";
const assert=require("node:assert/strict"),crypto=require("node:crypto");
const {chromium}=require("playwright");
const {createServer}=require("./static_server");
const secret=process.env.CORE10_CI_JWT_SECRET||"core10_disposable_a055_ci_signer_only_2026_not_production";
const rest=(process.env.CORE10_CI_REST_URL||"http://127.0.0.1:3000").replace(/\/$/,"");
const UID={bo101:"22222222-2222-4222-8222-222222222222",sup:"d1111111-1111-4111-8111-111111111111",reporter:"d5555555-5555-4555-8555-555555555555",
 tech:"d3333333-3333-4333-8333-333333333333",stock:"44444444-4444-4444-8444-444444444444"};
function jwt(sub){const now=Math.floor(Date.now()/1000),b=(o)=>Buffer.from(JSON.stringify(o)).toString("base64url");
 const body=b({alg:"HS256",typ:"JWT"})+"."+b({role:"authenticated",sub,aud:"authenticated",iat:now,exp:now+600});
 return body+"."+crypto.createHmac("sha256",secret).update(body).digest("base64url")}
async function call(persona,name,args){
 const res=await fetch(rest+"/rpc/"+name,{method:"POST",headers:{"content-type":"application/json",authorization:"Bearer "+jwt(UID[persona]),accept:"application/json"},body:JSON.stringify(args),signal:AbortSignal.timeout(20000)});
 const t=await res.text();let d;try{d=JSON.parse(t)}catch{d=t}return{status:res.status,data:d}}
const must=async(p,n,a)=>{const r=await call(p,n,a);assert.ok(r.status<300,n+" setup failed: "+r.status+" "+JSON.stringify(r.data));return r.data};
const uniq=()=>crypto.randomBytes(4).toString("hex");
// ---- test-only stand-in for vendor/supabase.js (SYNTHETIC; no network except same-origin forward) ----
const SHIM=`/* SYNTHETIC TEST ADAPTER: not the Supabase library. */
window.supabase={createClient:function(){return{auth:{getUser:async function(){return{data:{user:{id:"00000000-0000-4000-8000-00000000a055"}},error:null}}},
 schema:function(s){return{rpc:async function(name,args){const r=await fetch("/__am_rest/rpc/"+name,{method:"POST",headers:{"content-type":"application/json","x-am-persona":window.__AM_PERSONA||""},body:JSON.stringify(args)});
  const t=await r.text();let d;try{d=JSON.parse(t)}catch(e){d=null}
  if(r.status>=400)return{data:null,error:{message:(d&&d.message)||("HTTP "+r.status),code:d&&d.code}};return{data:d,error:null}}}}}}};`;
(async()=>{
 const server=createServer();await new Promise(r=>server.listen(0,"127.0.0.1",r));
 const base="http://127.0.0.1:"+server.address().port;
 const browser=await chromium.launch();
 try{
  await must("bo101","am_bootstrap_v1",{p_business:101,p_request:"br-boot-"+uniq()});
  const cats=(await must("bo101","am_list_catalog_v1",{p_business:101})).categories,cat=cats.find(c=>c.code==="PROD-EQ").id;
  for(const [width,height] of [[390,844],[1440,900]]){
   const tag=width+"-"+uniq(),errors=[],external=[],consoleErr=[];
   const ctx=await browser.newContext({viewport:{width,height},locale:"en-US"});
   await ctx.route("**/vendor/supabase.js",r=>r.fulfill({status:200,contentType:"text/javascript",body:SHIM}));
   await ctx.route("**/__am_rest/rpc/*",async r=>{const persona=r.request().headers()["x-am-persona"];
    if(!UID[persona])return r.fulfill({status:401,contentType:"application/json",body:JSON.stringify({message:"no persona"})});
    const name=new URL(r.request().url()).pathname.split("/").pop();
    const out=await call(persona,name,JSON.parse(r.request().postData()||"{}"));
    r.fulfill({status:out.status,contentType:"application/json",body:JSON.stringify(out.data)})});
   const open=async(persona,file,qs="?biz=101",lang)=>{
    const page=await ctx.newPage();
    page.on("pageerror",e=>errors.push(persona+":"+e.message));
    page.on("console",m=>{if(m.type()==="error"&&!/Failed to load resource/.test(m.text()))consoleErr.push(m.text())});
    page.on("request",q=>{const u=q.url();if(!u.startsWith(base)&&!u.startsWith("data:"))external.push(u)});
    await page.addInitScript(([p,l])=>{window.__AM_PERSONA=p;try{if(l)localStorage.setItem("c10_am_lang",l)}catch(e){}},[persona,lang||"en"]);
    await page.goto(base+"/core10-asset-maintenance-"+file+".html"+qs,{waitUntil:"load"});
    return page};
   const ready=async(page)=>{await page.waitForFunction(()=>{const s=document.getElementById("am-status");return s&&/^(Ready|প্রস্তুত)/.test(s.textContent)||document.getElementById("am-error-state")},null,{timeout:20000})};
   const noOverflow=async(page,what)=>{const o=await page.evaluate(()=>document.documentElement.scrollWidth-window.innerWidth);assert.ok(o<=2,"horizontal overflow "+o+"px at "+width+" on "+what)};

   // --- setup (supervisor requests, so the business owner is a valid second approver) ---
   const aName="Browser press "+tag;
   // 1. ASSETS: owner registers an asset through the real form, finds it, opens detail
   let page=await open("bo101","assets");await ready(page);
   assert.equal(await page.locator("#am-error-state").count(),0,"assets screen loaded without error");
   assert.match(await page.locator("#am-level").innerText(),/owner/i);
   await noOverflow(page,"assets");
   await page.click("#as-new");await page.waitForSelector("#am-form");
   await page.fill("#f-name",aName);
   await page.selectOption("#f-category_id",String(cat));
   await page.selectOption("#f-site_id","1001");
   if(await page.locator("#f-reason").count())await page.fill("#f-reason","Registered by browser test");
   await page.click("#am-form button[type=submit]");
   await page.waitForSelector("#am-form",{state:"detached",timeout:15000});
   await page.fill("#as-q",aName);await page.click("#as-search");
   await page.locator("#as-list").getByText(aName).first().waitFor({timeout:15000});
   await page.locator("#as-list tr",{hasText:aName}).locator('[id^="as-open-"]').first().click();
   await page.locator("#as-detail").waitFor({timeout:10000});
   assert.match(await page.locator("#as-detail").innerText(),new RegExp(aName));
   await noOverflow(page,"asset detail");
   // Bangla toggle
   await page.click("#am-lang");await page.waitForFunction(()=>document.documentElement.lang==="bn");await ready(page);
   assert.match(await page.locator('[data-nav="assets"]').innerText(),/[ঀ-৿]/,"Bangla navigation");
   assert.match(await page.locator("#am-title").innerText(),/[ঀ-৿]/,"Bangla title");
   await noOverflow(page,"assets (bn)");
   await page.click("#am-lang");await page.waitForFunction(()=>document.documentElement.lang==="en");await ready(page);
   await page.close();

   // 2. WORK ORDERS: supervisor creates + submits through RPC, owner approves in the UI
   const asset=(await must("bo101","am_list_assets_v1",{p_business:101,p_filters:{search:aName},p_limit:5,p_offset:0})).items[0];
   assert.ok(asset,"UI-created asset is in the registry");
   const wo=await must("sup","am_create_work_order_v1",{p_business:101,p_request:"br-wo-"+tag,p_data:{asset_id:asset.id,title:"Browser corrective "+tag,priority:"medium",kind:"corrective"}});
   const gw=async()=>(await must("bo101","am_get_work_order_v1",{p_business:101,p_wo:wo.id}));
   if((await gw()).status==="DRAFT")await must("sup","am_wo_transition_v1",{p_business:101,p_request:"br-sub-"+tag,p_wo:wo.id,p_expected_version:(await gw()).version,p_action:"submit",p_reason:null,p_data:null});
   page=await open("bo101","workorders");await ready(page);
   await page.fill("#wo-q","Browser corrective "+tag);await page.click("#wo-search");
   await page.locator("#wo-open-"+wo.id).waitFor({timeout:15000});await noOverflow(page,"work-order list");
   await page.click("#wo-open-"+wo.id);await page.locator("#wo-detail").waitFor();
   if(await page.locator("#act-approve").count()){
    await page.click("#act-approve");await page.waitForSelector("#am-form");
    if(await page.locator("#f-reason").count())await page.fill("#f-reason","Approved in browser test");
    await page.click("#am-form button[type=submit]");await page.waitForSelector("#am-form",{state:"detached",timeout:15000});
    const st=await (async()=>{for(let i=0;i<20;i++){const s=(await gw()).status;if(s==="APPROVED")return s;await new Promise(r=>setTimeout(r,300))}return(await gw()).status})();
    assert.equal(st,"APPROVED","approval made through the real UI form reached the database");
   }
   await noOverflow(page,"work-order detail");await page.close();
   // reporter: cannot see approve; technician view of the same WO has no verify
   page=await open("reporter","workorders");await ready(page);
   if(await page.locator("#wo-open-"+wo.id).count()){await page.click("#wo-open-"+wo.id);await page.locator("#wo-detail").waitFor();
    assert.equal(await page.locator("#act-approve").count()+await page.locator("#act-verify").count(),0,"reporter is offered no approval actions");}
   await page.close();

   // 3. BREAKDOWN: reporter files a report on the asset; a work order + downtime open
   page=await open("reporter","breakdown");await ready(page);
   assert.equal(await page.locator("#am-error-state").count(),0);
   await page.locator("#bd-form").waitFor();
   const sel=page.locator("#bd-form select").first();
   if(await sel.count()){const opts=await sel.locator("option").allInnerTexts();const idx=opts.findIndex(t=>t.includes(aName));if(idx>=0)await sel.selectOption({index:idx})}
   if(await page.locator("#bd-title").count())await page.fill("#bd-title","Seized "+tag);
   await page.fill("#bd-description","Belt snapped, machine stopped");
   await page.click("#bd-form button[type=submit]");
   let dt;for(let i=0;i<40;i++){dt=await must("bo101","am_list_downtime_v1",{p_business:101,p_filters:{open:true,asset_id:asset.id},p_limit:5,p_offset:0});if(dt.total>0)break;await new Promise(r=>setTimeout(r,300))}
   assert.equal(dt.total,1,"breakdown reported through the UI opened exactly one downtime window");
   await noOverflow(page,"breakdown");
   assert.equal(await page.locator('[data-nav="reports"][hidden]').count(),1,"reporter does not see Reports navigation");
   await page.close();

   // 4. SCHEDULE / REPORTS / SETTINGS render for the owner (no error state, no overflow), both languages
   for(const [file,id] of [["schedule","#sc-sugg-panel"],["reports","#rep-summary"],["settings","#pol-panel"]]){
    for(const lang of ["en","bn"]){
     page=await open("bo101",file,"?biz=101",lang);await ready(page);
     assert.equal(await page.locator("#am-error-state").count(),0,file+" "+lang+" loaded");
     await page.locator(id).first().waitFor({timeout:10000});await noOverflow(page,file+" "+lang);
     if(lang==="bn")assert.equal(await page.evaluate(()=>document.documentElement.lang),"bn");
     await page.close();}
   }
   // 5. NEGATIVE: a stock-only user (no maintenance authority) gets a clear error state, never data
   page=await open("stock","assets");await page.waitForSelector("#am-error-state",{timeout:20000});
   assert.equal(await page.locator("#as-list table").count(),0,"no asset data for an unauthorised user");
   assert.match(await page.locator("#am-error-state").innerText(),/not|allowed|permission|access|অনুমতি|ক্ষমতা/i);
   await noOverflow(page,"error state");await page.close();
   // 6. NEGATIVE: unsigned session (no persona) -> the adapter returns 401, UI shows the error state
   page=await open("","assets");await page.waitForSelector("#am-error-state",{timeout:20000});await page.close();

   assert.deepEqual(errors,[],"page errors at "+width+"px");
   assert.deepEqual(consoleErr,[],"console errors at "+width+"px");
   assert.deepEqual(external,[],"no external network requests at "+width+"px");
   console.log("PASS A055 "+width+"px: asset create/search/detail, bn/en, WO approve via UI, breakdown->downtime, schedule/reports/settings, unauthorised + unsigned states, no overflow/errors/external requests");
   await ctx.close();
  }
  console.log("A055_BROWSER_E2E_PASS (synthetic fixture; not GoTrue/staging/production)");
 }finally{await browser.close();await new Promise(r=>server.close(r))}
})().catch(e=>{console.error(e);process.exitCode=1});
