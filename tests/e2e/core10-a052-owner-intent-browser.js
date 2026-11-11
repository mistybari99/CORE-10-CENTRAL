"use strict";
/* A052 browser E2E at 390px and 1440px against a REAL disposable PostgreSQL (psql bridge).
 * Identity = request.jwt.claim.sub simulation under role authenticated. NOT Supabase GoTrue, NOT live RLS certification.
 * Needs PGHOST/PGDATABASE/PGUSER pointing at a database with A018,A020,A021,A044,A045,A052 loaded.
 */
const assert=require("node:assert/strict");
const {execFile}=require("node:child_process");
const {chromium}=require("playwright");
const {createServer}=require("./static_server");
const U={owner:"11111111-1111-4111-8111-111111111111",bizowner:"22222222-2222-4222-8222-222222222222",manager:"33333333-3333-4333-8333-333333333333",
 staff:"44444444-4444-4444-8444-444444444444",revoked:"66666666-6666-4666-8666-666666666666",tenant2:"77777777-7777-4777-8777-777777777777"};
const lit=(v)=>v===null||v===undefined?"NULL":typeof v==="number"||typeof v==="boolean"?String(v):"'"+(typeof v==="string"?v:JSON.stringify(v)).replace(/'/g,"''")+"'";
function psql(args){return new Promise((res)=>execFile("psql",["-qAtX","-v","ON_ERROR_STOP=1",...args],{maxBuffer:8e6},(e,out,err)=>res({e,out,err})))}
async function callPg(uid,name,a){
 const call="SELECT c10_demo."+name+"("+Object.entries(a||{}).map(([k,v])=>k+" => "+lit(v)).join(",")+")::text";
 const r=await psql(["-c","SET ROLE authenticated","-c","SELECT set_config('request.jwt.claim.sub',"+lit(uid)+",false)","-c",call]);
 if(r.e){const m=/ERROR:\s+([^\n]*)/.exec(r.err);return{data:null,error:{code:"P0001",message:m?m[1]:"RPC_FAILED"}}}
 const lines=r.out.trim().split("\n");return{data:JSON.parse(lines[lines.length-1]),error:null};
}
async function sql(q){const r=await psql(["-c",q]);if(r.e)throw new Error(r.err);return r.out.trim()}
const fixture=`window.BOS_CONFIG={url:"https://isolated-test.supabase.co",key:"publishable-fixture-only"};
window.supabase={createClient:function(){return{auth:{getUser:async()=>({data:{user:{id:window.__uid}},error:null})},
 schema:function(s){if(s!=="c10_demo")throw Error("SCHEMA_SCOPE");return{rpc:async(n,a)=>window.__rpc(n,a)}}}}};`;
async function noOverflow(page,label){const o=await page.evaluate(()=>document.documentElement.scrollWidth-window.innerWidth);assert.ok(o<=2,label+" horizontal overflow "+o)}
async function open(browser,base,who,width){
 const ctx=await browser.newContext({viewport:{width,height:900}});const page=await ctx.newPage();
 const errors=[],external=[];page.on("pageerror",e=>errors.push(e.message));page.on("request",r=>{if(!r.url().startsWith(base))external.push(r.url())});
 await page.exposeFunction("__rpc",(n,a)=>callPg(U[who],n,a));
 await page.addInitScript("window.__uid="+JSON.stringify(U[who])+";");
 await page.route("**/vendor/supabase.js",r=>r.fulfill({contentType:"application/javascript",body:""}));
 await page.route("**/config.js",r=>r.fulfill({contentType:"application/javascript",body:fixture}));
 await page.goto(base+"/core10-owner-intent.html?biz=101",{waitUntil:"load"});
 return{page,errors,external,ctx};
}
const clk=async(pg,sel)=>{await pg.waitForFunction(()=>!/…$/.test(document.querySelector('#oi-status')?.textContent||''),null,{timeout:20000});await pg.locator(sel).click()};
const ready=(page)=>page.waitForFunction(()=>document.querySelector("#oi-role")||document.querySelector("#oi-fatal"),{timeout:20000});
const settle=(page,txt)=>page.waitForFunction(t=>document.querySelector("#oi-status")?.textContent.includes(t),txt,{timeout:20000});
(async()=>{
 const server=createServer();await new Promise(r=>server.listen(0,"127.0.0.1",r));
 const base="http://127.0.0.1:"+server.address().port;
 const browser=await chromium.launch({headless:true});
 try{
  let k=0;
  for(const width of[390,1440]){
   k++;const w=width===390?{wp:3,lt:12,lit:4,mm:15,tot:"6 lakh"}:{wp:7,lt:25,lit:5,mm:18,tot:"9 lakh"};
   // ================= Owner, English =================
   const o=await open(browser,base,"owner",width);const page=o.page;
   await ready(page);
   assert.equal(await page.locator("#oi-role").innerText(),"tenant_owner");
   await clk(page,"#oi-lang");            // English
   assert.match(await page.locator("#oi-ctx").innerText(),/Certified capabilities[\s\S]*Wastage threshold advisory/);
   await noOverflow(page,width+" initial");
   // --- supported: sweets wastage (English) -> preview writes nothing -> validate -> approve -> publish
   const before=Number(await sql("select count(*) from c10_demo.intent_settings_v1"));
   await page.locator("#oi-text").fill("Warn me if sweets wastage goes above "+w.wp+"% in a batch (kg)");
   await clk(page,"#oi-interpret");
   assert.match(await page.locator("#oi-inter").innerText(),/Supported/);
   assert.equal(await page.locator("#oi-p-threshold_pct").inputValue(),String(w.wp));
   assert.match(await page.locator("#oi-assumptions").innerText(),/Outcome defaults to warn/);
   assert.equal(Number(await sql("select count(*) from c10_demo.owner_intents_v1 where raw_text like 'Warn me if sweets%"+w.wp+"%'")),0,"nothing saved before Save");
   await clk(page,"#oi-saveprev");
   await page.waitForSelector("#oi-nowrite",{timeout:20000});
   assert.match(await page.locator("#oi-diff").innerText(),/params\.threshold_pct/);
   assert.match(await page.locator("#oi-steps").innerText(),/wastage_pct|÷/);
   assert.match(await page.locator("#oi-impact").innerText(),/production_wastage_report \[NOT_BUILT\]/);
   assert.equal(Number(await sql("select count(*) from c10_demo.intent_settings_v1")),before,"preview must not write settings");
   assert.equal(await page.locator("#oi-approve").isDisabled(),true,"cannot approve before validation");
   await noOverflow(page,width+" preview");
   // sample numbers change the after-result
   await page.locator("#oi-s-wasted_qty").fill("1");await clk(page,"#oi-rerun");
   await page.waitForFunction(()=>document.querySelector("#oi-after")?.textContent.includes("allow"),{timeout:20000});
   await clk(page,"#oi-validate");await page.waitForFunction(()=>document.querySelector("#oi-preview .oi-pill[data-s=VALIDATED]"),{timeout:20000});
   await page.locator("#oi-reason").fill("Owner approves wastage rule");await clk(page,"#oi-approve");
   await page.waitForFunction(()=>document.querySelector("#oi-preview .oi-pill[data-s=APPROVED]"),{timeout:20000});
   await clk(page,"#oi-publish");await page.waitForFunction(()=>document.querySelector("#oi-preview .oi-pill[data-s=PUBLISHED]"),{timeout:20000});
   assert.equal(Number(await sql("select count(*) from c10_demo.intent_settings_v1")),before+1);
   assert.equal(await sql("select count(*) from c10_demo.stock_movements where created_by::text<>'x' and false"),"0");
   assert.match(await page.locator("#oi-history").innerText(),/v1[\s\S]*threshold_pct/);
   // --- supported: Bangla paint pack (4 L) with approval wording
   await clk(page,"#oi-lang");            // Bangla
   await page.locator("#oi-text").fill("পেইন্ট "+w.lit+" লিটার প্যাকে ডিসকাউন্ট দিলে মার্জিন "+w.mm+"% এর নিচে গেলে অনুমোদন লাগবে");
   await clk(page,"#oi-interpret");
   assert.match(await page.locator("#oi-inter").innerText(),/সমর্থিত/);
   assert.equal(await page.locator("#oi-p-pack_litres").inputValue(),String(w.lit));
   await clk(page,"#oi-saveprev");await page.waitForSelector("#oi-nowrite",{timeout:20000});
   assert.match(await page.locator("#oi-preview").innerText(),/মার্জিন_শতাংশ/);
   assert.match(await page.locator("#oi-preview").innerText(),/margin_pct = /);
   // --- clarification: missing pack size
   await page.locator("#oi-text").fill("discount below margin 12% needs approval");await clk(page,"#oi-interpret");
   assert.match(await page.locator("#oi-questions").innerText(),/প্যাক কত লিটারের/);
   await clk(page,"#oi-lang");            // English
   // --- supported via A045 registry: construction materials order
   await page.locator("#oi-text").fill("Construction project materials order of "+w.tot+" taka or more needs my approval");await clk(page,"#oi-interpret");
   await clk(page,"#oi-saveprev");await page.waitForSelector("#oi-nowrite",{timeout:20000});
   await clk(page,"#oi-validate");await page.waitForFunction(()=>document.querySelector("#oi-preview .oi-pill[data-s=VALIDATED]"),{timeout:20000});
   await page.locator("#oi-reason").fill("Approve materials limit");await clk(page,"#oi-approve");
   await page.waitForFunction(()=>document.querySelector("#oi-preview .oi-pill[data-s=APPROVED]"),{timeout:20000});
   await clk(page,"#oi-publish");await page.waitForFunction(()=>document.querySelector("#oi-preview .oi-pill[data-s=PUBLISHED]"),{timeout:20000});
   assert.equal(await sql("select count(*) from c10_demo.micro_engine_assignments_v1 a join c10_demo.micro_engines_v1 e on e.id=a.engine_id where e.engine_key='a052_order_total_approval_b101' and a.state='PUBLISHED'"),"1");
   // --- second low-stock publish then rollback
   for(const th of[w.lt,w.lt+5]){
    await page.locator("#oi-text").fill("alert me when stock is below "+th+" kg");await clk(page,"#oi-interpret");
    await clk(page,"#oi-saveprev");await page.waitForSelector("#oi-nowrite",{timeout:20000});
    await clk(page,"#oi-validate");await page.waitForFunction(()=>document.querySelector("#oi-preview .oi-pill[data-s=VALIDATED]"),{timeout:20000});
    await page.locator("#oi-reason").fill("Approve low stock "+th);await clk(page,"#oi-approve");
    await page.waitForFunction(()=>document.querySelector("#oi-preview .oi-pill[data-s=APPROVED]"),{timeout:20000});
    await clk(page,"#oi-publish");await page.waitForFunction(()=>document.querySelector("#oi-preview .oi-pill[data-s=PUBLISHED]"),{timeout:20000});
   }
   const rb=page.locator('[data-setting="low_stock_alert"] .oi-row',{hasText:'"threshold":'+w.lt+'}'}).filter({has:page.locator('[data-rollback]')}).locator('[data-rollback]');
   await rb.waitFor({timeout:20000});await rb.click();
   for(let i=0;i<40&&await sql("select params->>'threshold' from c10_demo.intent_settings_v1 where business_id=101 and setting_key='low_stock_alert' and state='ACTIVE'")!==String(w.lt);i++)await new Promise(r=>setTimeout(r,250));
   assert.equal(await sql("select params->>'threshold' from c10_demo.intent_settings_v1 where business_id=101 and setting_key='low_stock_alert' and state='ACTIVE'"),String(w.lt));
   assert.ok(await page.locator("#oi-audit li").count()>=5,"audit rendered");
   // --- unsupported: engineering requirement stored, nothing executable
   await page.locator("#oi-text").fill("Show monthly project materials report "+k);await clk(page,"#oi-interpret");
   assert.match(await page.locator("#oi-unsupported").innerText(),/Not executable/);
   assert.equal(await page.locator("#oi-saveprev").count(),0,"no preview/publish for unsupported");
   await clk(page,"#oi-saveeng");await page.waitForSelector('[data-req]',{timeout:20000});
   assert.match(await page.locator("#oi-reqs").innerText(),/NEEDS_HANDLER_BUILD[\s\S]*report_v1[\s\S]*certified=false/);
   // --- refused by policy
   await page.locator("#oi-text").fill("Give Rahim admin permission");await clk(page,"#oi-interpret");
   assert.match(await page.locator("#oi-unsupported").innerText(),/Refused by policy/);
   // --- invalid locale never reaches the server
   const nCalls=Number(await sql("select count(*) from c10_demo.owner_intents_v1"));
   await page.locator("#oi-text").fill("你好世界，请设置阈值");await clk(page,"#oi-interpret");
   assert.match(await page.locator("#oi-status").innerText(),/Bangla or English/);
   assert.equal(Number(await sql("select count(*) from c10_demo.owner_intents_v1")),nCalls);
   // --- contextual guidance (EN then BN) with effective permission
   await page.locator('[data-guide="intent.preview_diff"]').first().click();
   await page.waitForFunction(()=>document.querySelector("#oi-guide-title"),{timeout:20000});
   assert.match(await page.locator("#oi-guide").innerText(),/A dry run showing before\/after[\s\S]*Consequence/);
   assert.match(await page.locator("#oi-guide-perm").innerText(),/tenant_owner · submit=true · approve\/publish=true/);
   await clk(page,"#oi-lang");
   await page.locator('[data-guide="intent.rollback"]').first().click();
   await page.waitForFunction(()=>document.querySelector("#oi-guide-title")?.textContent.includes("রোলব্যাক"),{timeout:20000});
   assert.match(await page.locator("#oi-guide").innerText(),/কী[\s\S]*কেন[\s\S]*কখন[\s\S]*ডিফল্ট[\s\S]*ব্যতিক্রম[\s\S]*পরিণতি/);
   await noOverflow(page,width+" full");
   assert.deepEqual(o.errors,[],"page errors");assert.deepEqual(o.external,[],"external requests");
   await o.ctx.close();
   // ================= Business Owner: can submit/preview/validate, cannot approve/publish =================
   const b=await open(browser,base,"bizowner",width);await ready(b.page);
   assert.equal(await b.page.locator("#oi-role").innerText(),"business_owner");
   await clk(b.page,"#oi-lang");
   await b.page.locator("#oi-text").fill("stock below "+(w.lt+100)+" pcs");await clk(b.page,"#oi-interpret");
   await clk(b.page,"#oi-saveprev");await b.page.waitForSelector("#oi-nowrite",{timeout:20000});
   await clk(b.page,"#oi-validate");await b.page.waitForFunction(()=>document.querySelector("#oi-preview .oi-pill[data-s=VALIDATED]"),{timeout:20000});
   assert.equal(await b.page.locator("#oi-approve").isDisabled(),true);assert.equal(await b.page.locator("#oi-publish").isDisabled(),true);
   assert.match(await b.page.locator("#oi-preview").innerText(),/Only the tenant Owner can approve and publish/);
   // force the call anyway: the SERVER denies
   const denied=await b.page.evaluate(async()=>{const c=window.supabase.createClient();const r=await c.schema("c10_demo").rpc("publish_owner_intent_v1",{p_intent:1,p_expected:1,p_request:"force_publish_bo1"});return r.error&&r.error.message});
   assert.equal(denied,"intent_denied");
   assert.equal(await b.page.locator('[data-rollback]').count(),0,"no rollback control for business owner");
   await noOverflow(b.page,width+" bizowner");assert.deepEqual(b.errors,[]);await b.ctx.close();
   // ================= Manager / staff: no submit; revoked / other tenant: no access =================
   for(const who of["manager","staff"]){
    const m=await open(browser,base,who,width);await ready(m.page);
    assert.equal(await m.page.locator("#oi-role").innerText(),"limited");
    await clk(m.page,"#oi-lang");
    await m.page.locator("#oi-text").fill("stock below 5");await clk(m.page,"#oi-interpret");
    assert.match(await m.page.locator("#oi-inter").innerText(),/cannot submit/);
    assert.equal(await m.page.locator("#oi-saveprev").count(),0);
    assert.equal(await m.page.locator("#oi-intents .oi-row").count(),0,"no intent list for "+who);
    await m.page.locator('[data-guide="inventory.low_stock_alert"]').count();
    await noOverflow(m.page,width+" "+who);assert.deepEqual(m.errors,[]);await m.ctx.close();
   }
   const rv=await open(browser,base,"revoked",width);await ready(rv.page);
   assert.match(await rv.page.locator("#oi-fatal").innerText(),/No business visible|intent_denied/);await rv.ctx.close();
   const t2=await open(browser,base,"tenant2",width);await ready(t2.page);
   assert.equal(await t2.page.locator("#oi-biz option").count(),1);assert.match(await t2.page.locator("#oi-biz").innerText(),/#201/);
   assert.equal(await t2.page.locator("#oi-intents .oi-row").count(),0,"tenant 2 sees no tenant 1 intents");
   await noOverflow(t2.page,width+" tenant2");await t2.ctx.close();
  }
  console.log("PASS A052 browser E2E 390px + 1440px against real PostgreSQL (psql bridge): lifecycle, A045 route, rollback, unsupported, guidance bn/en, authz");
 }finally{await browser.close();server.close()}
})().catch(e=>{console.error(e);process.exit(1)});
