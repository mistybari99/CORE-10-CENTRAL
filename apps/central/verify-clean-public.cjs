"use strict";
const assert=require("node:assert/strict");
const base=process.env.REVIEW_BASE||"https://core10-central.mistybari99.workers.dev";
assert.equal(base,"https://core10-central.mistybari99.workers.dev","CORE10_PUBLIC_TARGET_CHANGED");
const required=["/","/app.js","/shell-context.js","/view/owner-dashboard-signed.html","/view/master-signed.html","/view/stock-signed.html","/view/sales-signed.html","/live/core10-owner-control-centre.html","/live/core10-build01.html"];
const removed=["/view/workspace.html","/view/workspace.js","/view/workspace-data.js","/view/sales.html","/view/sales.js","/view/sales-data.js","/view/mfg.html","/view/mfg.mjs","/view/mfg-data.js","/view/replay.js","/view/control-data.js","/view/master-data.js","/view/control.html","/view/master.html","/live/docs/preview/c10-np01-canonical-reviewer-preview.html","/live/core10-sales-order-entry.js","/live/modules/manufacturing/workbench.mjs","/config.js","/v2/config.js"];
async function http(){
 const root=await fetch(base+"/",{cache:"no-store",redirect:"error"});
 assert.equal(root.status,200);
 assert.match(root.headers.get("x-core10-source")||"",/(?:^|,)clean=1(?:,|$)/);
 const html=await root.text();
 for(const name of ["staff","manufacturing","features","approvals"])assert.ok(!html.includes('href="#/'+name+'"'),name);
 for(const route of required){
  const res=await fetch(base+route,{cache:"no-store",redirect:"error"});
  assert.equal(res.status,200,route);assert.equal(res.headers.get("cache-control"),"no-store");
  assert.match(res.headers.get("content-security-policy")||"",/connect-src 'self' https:\/\/rhrqhbyzrhaafynfhdaf\.supabase\.co/);
  assert.match(res.headers.get("x-core10-source")||"",/(?:^|,)clean=1(?:,|$)/);
 }
 for(const route of removed){const res=await fetch(base+route,{cache:"no-store",redirect:"error"});assert.equal(res.status,404,route);}
 console.log("CLEAN_PUBLIC_HTTP_PASS",required.length,removed.length);
}
async function browser(){
 const {chromium}=require("playwright");
 const b=await chromium.launch({headless:true});
 try{
 for(const width of [390,1440]){
  const page=await b.newPage({viewport:{width,height:844}});
  const waitRoute=async route=>page.waitForFunction(expected=>{try{return document.querySelector("#c10-frame").contentWindow.location.pathname===expected;}catch(_){return false;}},route,{timeout:20000});
  await page.goto(base+"/",{waitUntil:"domcontentloaded"});await waitRoute("/view/owner-dashboard-signed.html");
  const nav=width===390?"data-mobile-route":"data-route";
  for(const [name,route] of [["master","/view/master-signed.html"],["stock","/view/stock-signed.html"],["sales","/view/sales-signed.html"]]){
   await page.locator("["+nav+'="'+name+'"]').click();await waitRoute(route);
   assert.equal(await page.locator("body").getAttribute("data-view"),name);
  }
  for(const [name,route] of [["control","/live/core10-owner-control-centre.html"],["setup","/live/core10-build01.html"]]){
   if(width===390)await page.locator("#c10-more-toggle").click();
   await page.locator("["+nav+'="'+name+'"]').click();await waitRoute(route);
  }
  await page.locator('[data-set-lang="en"]').click();assert.equal(await page.locator("html").getAttribute("lang"),"en");
  assert.equal(await page.locator('a[href="#/manufacturing"]').count(),0);
  await page.close();console.log("CLEAN_PUBLIC_BROWSER_PASS",width);
 }
 }finally{await b.close();}
}
(async()=>{await http();if(process.argv.includes("--browser"))await browser();})().catch(e=>{console.error(e);process.exitCode=1;});
