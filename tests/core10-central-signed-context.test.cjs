"use strict";
const {test}=require("node:test");
const assert=require("node:assert/strict");
const fs=require("node:fs");
const path=require("node:path");
const ROOT=path.resolve(__dirname,"..");
const site=(p)=>fs.readFileSync(path.join(ROOT,"apps/central/site",p),"utf8");

test("§7b.4 signed context uses canonical RPC, no client-created grants or token persistence",()=>{
 const source=site("shell-context.js"),html=site("index.html");
 assert.match(source,/build01_context_v1/);
 assert.match(source,/auth\.getUser\(\)/);
 assert.match(source,/auth\.signInWithPassword\(/);
 assert.match(source,/auth\.signOut\(/);
 assert.match(source,/CONTEXT_CROSS_TENANT/);
 assert.match(source,/before!==after/);
 assert.match(source,/core10:signed-out/);
 assert.match(html,/id="c10-context"/);
 assert.match(html,/id="c10-group"/);
 assert.match(html,/id="c10-business"/);
 assert.match(html,/id="c10-site"/);
 assert.doesNotMatch(source,/(?:\.from\(|fetch\(|localStorage|sessionStorage|service_role|sb_secret_|BOS_CONFIG)/);
 assert.doesNotMatch(source,/kbuhnpqooycqbzrfejcs|luoeyyngayxpqecuuijb/);
});

test("§7b.4 browser: one sign-in, group/business/site scoped switching, role-safe denial, logout", {timeout:120000},async()=>{
 const {chromium}=require("playwright");
 const {serve}=await import(path.join(ROOT,"apps/central/local-serve.mjs"));
 const server=await serve(0),browser=await chromium.launch({headless:true});
 let page=null;
 try {
   const base="http://127.0.0.1:"+server.address().port;
   page=await browser.newPage({viewport:{width:1440,height:900}});
   const errors=[];page.on("pageerror",e=>errors.push(e.message));
   await page.route("**/live/vendor/supabase.js",async r=>r.fulfill({status:200,contentType:"text/javascript",body:MOCK}));
   await page.goto(base+"/#/home",{waitUntil:"load"});
   await page.locator("#c10-context-anon").waitFor({state:"visible"});
   assert.equal(await page.locator("#c10-context-signed").isVisible(),false);
   assert.equal(await page.locator("#c10-business option").count(),0);
   assert.equal(await page.evaluate(()=>window.__scopeTest.calls.length),0,"anonymous shell never reads any context RPC");
   await page.locator("#c10-shell-open-login").click();
   await page.fill("#c10-shell-email","owner@example.test");
   await page.fill("#c10-shell-password","wrong");
   await page.locator("#c10-shell-submit").click();
   await page.waitForFunction(()=>document.querySelector("#c10-context-note").textContent.includes("ব্যর্থ"));
   assert.equal(await page.locator("#c10-context-signed").isVisible(),false);
   assert.equal(await page.inputValue("#c10-shell-password"),"");
   await page.locator("#c10-shell-open-login").click();
   await page.fill("#c10-shell-password","correct-password");
   await page.locator("#c10-shell-submit").click();
   await page.locator("#c10-context-signed").waitFor({state:"visible"});
   assert.equal(await page.locator("#c10-group option").count(),2);
   assert.equal(await page.locator("#c10-business option").count(),2);
   assert.equal(await page.locator("#c10-site option").count(),2);
   assert.equal(await page.inputValue("#c10-group"),"1");
   assert.equal(await page.inputValue("#c10-business"),"10");
   assert.equal(await page.inputValue("#c10-site"),"101");
   assert.match(await page.locator("#c10-site option:checked").innerText(),/#101$/);
   assert.match(await page.locator("#c10-context-note").innerText(),/সাইট 2/);
   assert.equal(await page.locator("#c10-business").textContent().then(s=>s.includes("Other Workspace")),false);
   await page.locator("#c10-pilot-details summary").click();
   await page.waitForFunction(()=>document.querySelector("#c10-pilot-list").textContent.includes("kg"));
   assert.match(await page.locator("#c10-pilot-list").innerText(),/১০০০/);
   assert.match(await page.locator("#c10-pilot-list").innerText(),/Lot, pack/);
   await page.locator("#c10-site").selectOption("102");
   await page.waitForFunction(()=>document.querySelector("#c10-site").value==="102"&&!document.querySelector("#c10-site").disabled);
   assert.equal(await page.locator("#c10-pilot-list li").count(),0);
   await page.locator("#c10-pilot-details summary").click();
   await page.waitForFunction(()=>document.querySelector("#c10-pilot-list").textContent.includes("approved: 1"));
   await page.locator("#c10-location-details summary").click();
   await page.locator("#c10-location-list li").waitFor();
   assert.equal(await page.locator("#c10-location-list").innerText(),"STORE · #7");
   await page.locator("#c10-business").selectOption("20");
   await page.waitForFunction(()=>document.querySelector("#c10-business").value==="20"&&!document.querySelector("#c10-business").disabled);
   assert.equal(await page.locator("#c10-site option").count(),1);
   assert.equal(await page.inputValue("#c10-site"),"201");
   assert.match(await page.locator("#c10-context-note").innerText(),/সাইট 1/);
   assert.equal(await page.locator("#c10-location-list li").count(),0);
   assert.equal(await page.locator("#c10-pilot-list li").count(),0);
   await page.evaluate(()=>{window.__scopeTest.badLocation=true;});
   await page.locator("#c10-location-details summary").click();
   await page.waitForFunction(()=>document.querySelector("#c10-location-status").textContent.includes("যাচাই করা যায়নি"));
   assert.equal(await page.locator("#c10-location-list li").count(),0);
   await page.locator("#c10-group").selectOption("2");
   await page.waitForFunction(()=>document.querySelector("#c10-group").value==="2"&&!document.querySelector("#c10-group").disabled);
   assert.equal(await page.inputValue("#c10-business"),"30");
   assert.equal(await page.locator("#c10-site option").count(),1);
   await page.setViewportSize({width:390,height:844});
   assert.equal(await page.locator("#c10-context-signed").isVisible(),true);
   assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),true);
   await page.locator('[data-set-lang="en"]').click();
   assert.equal(await page.getAttribute("html","lang"),"en");
   assert.equal(await page.locator("#c10-context-note").textContent().then(s=>/Your authorized sites in this business: 1/.test(s)),true);
   // An account switch must revoke previously rendered business/site names.
   await page.evaluate(()=>window.__scopeTest.changeAccount());
   await page.locator("#c10-context-refresh").click();
   await page.locator("#c10-context-anon").waitFor({state:"visible"});
   assert.equal(await page.locator("#c10-business option").count(),0);
   await page.locator("#c10-shell-open-login").click();
   await page.fill("#c10-shell-password","correct-password");
   await page.locator("#c10-shell-submit").click();
   await page.locator("#c10-context-signed").waitFor({state:"visible"});

   // A delayed valid RPC response must not repopulate private UI after SIGNED_OUT.
   const beforeCalls=await page.evaluate(()=>window.__scopeTest.calls.length);
   await page.evaluate(()=>{
     let resolve;
     const promise=new Promise(r=>{resolve=r;});
     window.__scopeTest.pending={promise,resolve};
   });
   await page.locator("#c10-context-refresh").click();
   await page.waitForFunction(n=>window.__scopeTest.calls.length>n,beforeCalls);
   await page.evaluate(()=>window.__scopeTest.expire());
   await page.locator("#c10-context-anon").waitFor({state:"visible"});
   await page.evaluate(()=>window.__scopeTest.resolve());
   assert.equal(await page.locator("#c10-business option").count(),0);
   assert.equal(await page.locator("#c10-site option").count(),0);
   await page.locator("#c10-shell-open-login").click();
   await page.fill("#c10-shell-password","correct-password");
   await page.locator("#c10-shell-submit").click();
   await page.locator("#c10-context-signed").waitFor({state:"visible"});

   // The server revokes scope: an old selection may not remain visible.
   await page.evaluate(()=>window.__scopeTest.revoke());
   await page.locator("#c10-context-refresh").click();
   await page.locator("#c10-context-anon").waitFor({state:"visible"});
   assert.equal(await page.locator("#c10-site option").count(),0);
   assert.equal(await page.locator("#c10-context-signed").isVisible(),false);
   await page.evaluate(()=>{window.__scopeTest.context.sites=[];window.__scopeTest.changeAccount();});
   await page.locator("#c10-shell-open-login").click();
   // Signing in as an already-switched actor must never grant old scope or pretend success.
   await page.fill("#c10-shell-password","correct-password");
   await page.locator("#c10-shell-submit").click();
   await page.locator("#c10-context-signed").waitFor({state:"visible"});
   await page.locator("#c10-shell-signout").click();
   await page.locator("#c10-context-anon").waitFor({state:"visible"});
   assert.equal(await page.locator("#c10-business option").count(),0);
   assert.equal(await page.locator("#c10-site option").count(),0);
   assert.equal(await page.locator("#c10-shell-password").inputValue(),"");
   assert.deepEqual(errors,[]);
 }finally{
   if(page)await page.close();await browser.close();
   await new Promise((ok,fail)=>server.close(err=>err?fail(err):ok()));
 }
});

const MOCK="(function(){\n  const uid=\"11111111-1111-4111-8111-111111111111\";\n  const original={\n    actor_uid:uid,\n    tenants:[{id:1,slug:\"owner-group\"},{id:2,slug:\"other-group\"}],\n    businesses:[{id:10,tenant_id:1,label:\"DEMO Sweets\",slug:\"sweets\",can_manage:true},{id:20,tenant_id:1,label:\"DEMO Paint\",slug:\"paint\",can_manage:true},{id:30,tenant_id:2,label:\"Other Workspace\",slug:\"other\",can_manage:false}],\n    sites:[{id:101,business_id:10,tenant_id:1,label:\"Showroom A\",kind:\"showroom\"},{id:102,business_id:10,tenant_id:1,label:\"Factory A\",kind:\"factory\"},\n      {id:201,business_id:20,tenant_id:1,label:\"Paint Shop\",kind:\"showroom\"},{id:301,business_id:30,tenant_id:2,label:\"Other Shop\",kind:\"showroom\"}]\n  };\n  const f=window.__scopeTest={\n    user:null,context:structuredClone(original),calls:[],watchers:[],pending:null,\n    trigger(event){for(const callback of this.watchers)callback(event,{});},\n    async resolve(){if(this.pending){this.pending.resolve();this.pending=null;}},\n    changeAccount(){this.user={id:\"22222222-2222-4222-8222-222222222222\"};},\n    revoke(){this.context={...this.context,sites:[{id:101,business_id:10,tenant_id:2,label:\"FORBIDDEN\",kind:\"showroom\"}]};},\n    expire(){this.user=null;this.trigger(\"SIGNED_OUT\");}\n  };\n  window.supabase={createClient:()=>({\n    auth:{\n      async getUser(){return f.user?{data:{user:f.user},error:null}:{data:{user:null},error:{message:\"No session\"}};},\n      async signInWithPassword({email,password}){\n        if(email!==\"owner@example.test\"||password!==\"correct-password\")return{data:null,error:{message:\"Invalid credentials\"}};\n        f.user={id:uid};f.trigger(\"SIGNED_IN\");return{data:{user:f.user},error:null};\n      },\n      async signOut(){f.user=null;f.trigger(\"SIGNED_OUT\");return {error:null};},\n      onAuthStateChange(callback){f.watchers.push(callback);queueMicrotask(()=>callback(\"INITIAL_SESSION\",null));return{data:{subscription:{unsubscribe(){}}}};}\n    },\n    schema(name){if(name!==\"core10\")throw Error(\"UNEXPECTED_SCHEMA\");return{\n      async rpc(method,args){\n        f.calls.push(method);if(method===\"master_list_uoms_v1\")return {data:{uoms:[{id:1,code:\"kg\",dimension:\"mass\",active:true},{id:2,code:\"g\",dimension:\"mass\",active:true}],conversions:[{from_uom_id:1,to_uom_id:2,factor:1000,active:true}]}};if(method===\"mfg_inspect_v1\")return {data:{recipes:[{id:1,tenant_id:1,business_id:args.p_business,site_id:args.p_site,version:1,status:\"approved\",effective_from:\"2020-01-01T00:00:00Z\"}]}};if(method===\"inventory_list_locations_v1\")return {data:{business_id:args.p_business,site_id:args.p_site,truncated:false,items:[{site_id:f.badLocation?999:args.p_site,code:\"STORE\",location_id:7}]}};if(method!==\"build01_context_v1\")throw Error(\"UNEXPECTED_RPC\");\n        if(f.pending)await f.pending.promise;\n        return {data:structuredClone(f.context),error:null};\n      }\n    };}\n  })};\n})();";
