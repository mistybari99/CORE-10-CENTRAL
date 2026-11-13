"use strict";
/* C10-A047 synthetic browser UI contract, not live signed Supabase GoTrue. */
const assert=require("node:assert/strict");
const fs=require("node:fs");
const path=require("node:path");
const {chromium}=require("playwright");
const {createServer}=require("./static_server");
const fixture=fs.readFileSync(path.join(__dirname,"../fixtures/c10_a047_topology_browser_mock.js"),"utf8");
(async()=>{
 const server=createServer();
 await new Promise(resolve=>server.listen(0,"127.0.0.1",resolve));
 const base="http://127.0.0.1:"+server.address().port;
 const browser=await chromium.launch({headless:true});
 try{
  for(const width of [390,1440]){
   const page=await browser.newPage({viewport:{width,height:900}});
   const errors=[],external=[];
   page.on("pageerror",e=>errors.push(e.message));
   page.on("request",r=>{if(!r.url().startsWith(base))external.push(r.url())});
   await page.route("**/vendor/supabase.js",r=>r.fulfill({contentType:"application/javascript",body:""}));
   await page.route("**/config.js",r=>r.fulfill({contentType:"application/javascript",body:fixture}));
   await page.goto(base+"/core10-site-topology.html?biz=101",{waitUntil:"load"});
   await page.waitForFunction(()=>document.querySelector("#topology-status")?.textContent.includes("Authorized structure loaded"),{timeout:18000});
   assert.match(await page.locator("#topology-count").innerText(),/2 accessible sites/);
   assert.equal(await page.locator(".topology-site").count(),2);
   await page.locator('#topology-group-form [name="kind"]').selectOption("showroom");
   await page.locator('#topology-group-form [name="key"]').fill("north_showrooms");
   await page.locator('#topology-group-form [name="label"]').fill("North Showrooms");
   await page.locator('#topology-group-form button').click();
   await page.waitForFunction(()=>document.querySelector(".topology-group:last-of-type")?.textContent.includes("North Showrooms"),{timeout:18000}).catch(()=>{});
   assert.equal(await page.locator(".topology-group").count(),4);
   const group=page.locator(".topology-group").filter({hasText:"North Showrooms"}).last();
   await group.locator("form[data-group] input").fill("North New Showroom");
   await group.locator("form[data-group] button").click();
   await page.waitForFunction(()=>document.querySelector("#topology-count")?.textContent.includes("3 accessible sites"),{timeout:15000});
   assert.equal(await page.locator(".topology-site").count(),3);
   const original=page.locator("[data-site='1001']");
   await original.locator(".move-target").selectOption({label:"North Showrooms"});
   await original.locator("button[data-act=move]").click();
   await page.waitForFunction(()=>document.querySelector("[data-site='1001']")?.getAttribute("data-version")==="2",{timeout:15000});
   assert.equal(await page.locator("[data-site='1001']").count(),1);
   assert.equal(await page.locator("[data-site='1001']").getAttribute("data-version"),"2");
   assert.match(await page.locator("#topology-audit").innerText(),/site_moved/);
   const remote=await page.evaluate(()=>window.CORE10_A047_E2E.calls);
   assert(remote.some(x=>x.name==="create_site_group_v1"));
   assert(remote.some(x=>x.name==="create_site_in_group_v1"));
   assert(remote.some(x=>x.name==="move_site_group_v1"));
   assert(!remote.some(x=>x.name.includes("post_stock_event")),"no stock posting through UI");
   assert.equal(errors.length,0,"browser script errors: "+errors.join(" | "));
   assert.equal(external.length,0,"Unexpected network: "+external.join(" | "));
   const overflow=await page.evaluate(()=>document.documentElement.scrollWidth-innerWidth);
   assert(overflow<=2,"Horizontal overflow at "+width+"px by "+overflow+"px");
   console.log("PASS A047 "+width+"px grouped Owner app, group/create/move/audit, canonical site, no external network");
   await page.close();
  }
 }finally{await browser.close();await new Promise(resolve=>server.close(resolve))}
})().catch(e=>{console.error(e);process.exitCode=1});
