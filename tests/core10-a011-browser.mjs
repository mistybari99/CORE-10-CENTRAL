// C10-A011 isolated Chromium UI contract. No production Supabase/network access.
// Uses an explicitly mocked RPC, not live authenticated acceptance.
import assert from "node:assert/strict";
import fs from "node:fs";
import { chromium } from "playwright";
const js = fs.readFileSync("core10-place-setup.js","utf8");
const css = fs.readFileSync("core10-place-setup.css","utf8");
const fixture = fs.readFileSync("tests/a011-browser-fixture.html","utf8");
const widths = [390,768,1366];
let passed=0;
const browser = await chromium.launch({headless:true,args:["--no-sandbox"]});
try{
 for(const width of widths){
  for(const theme of ["islamia","business"]){
   const page=await browser.newPage({viewport:{width,height:844},deviceScaleFactor:1});
   const errors=[];
   page.on("pageerror",error=>errors.push(String(error)));
   await page.route("https://core10-test.invalid/**",route=>route.fulfill({status:200,contentType:"text/html",body:fixture}));
   await page.goto("https://core10-test.invalid/index.html?workspace=islamia&biz=3");
   if(theme==="business")await page.evaluate(()=>document.body.dataset.businessTenant="1");
   await page.addStyleTag({content:css});
   await page.addScriptTag({content:js});
   await page.evaluate(()=>window.BOS_APP.H.c10_place_open());
   assert.equal(await page.locator(".c10-site-panel").count(),1,"form renders");
   assert.equal(await page.locator('input[name="c10_place_kind"]').count(),3,"three choices");
   assert.equal(await page.locator("#c10_place_error").getAttribute("role"),"alert");
   assert.equal(await page.locator(".c10-site-preview").getAttribute("aria-live"),"polite");
   let sizes=await page.evaluate(()=>({scroll:document.documentElement.scrollWidth,width:innerWidth}));
   assert.ok(sizes.scroll<=sizes.width+1,"no overflow "+width+" "+theme);
   await page.locator('input[name="c10_place_kind"][value="godown"]').check();
   await page.locator("#c10_place_bn").fill("নতুন গোডাউন");
   await page.locator("#c10_place_en").fill("New Warehouse");
   await page.locator("#c10_place_code").fill("depot_1");
   assert.equal(await page.locator("#c10_place_preview_name").textContent(),"নতুন গোডাউন");
   assert.match(await page.locator("#c10_place_preview_detail").textContent(),/depot_1/);
   sizes=await page.evaluate(()=>({scroll:document.documentElement.scrollWidth,width:innerWidth}));
   assert.ok(sizes.scroll<=sizes.width+1,"no edited overflow "+width+" "+theme);
   // Failure + retry exercise visual state without touching a real server.
   await page.evaluate(()=>window.__rpcError=true);
   await page.locator("#c10_place_submit").click();
   await page.locator("#c10_place_error:not([hidden])").waitFor();
   assert.equal(await page.locator("#c10_place_submit").isDisabled(),false,"retry possible");
   await page.evaluate(()=>window.__rpcError=false);
   await page.locator("#c10_place_submit").click();
   await page.waitForFunction(()=>window.__rpcCalls.length===2);
   assert.equal(await page.locator(".c10-site-panel").count(),0,"sheet closed on success");
   assert.equal(await page.evaluate(()=>location.hash),"#/locations","existing location route");
   const rpc=await page.evaluate(()=>window.__rpcCalls);
   assert.equal(rpc[0].name,"business_place_create135");
   assert.equal(rpc[0].payload.p_business,3);
   assert.equal(rpc[0].payload.p_kind,"godown");
   assert.equal(rpc[0].payload.p_client,rpc[1].payload.p_client,"stable retry UUID");
   assert.deepEqual(errors,[],"no browser page errors");
   console.log("PASS browser "+width+"px "+theme+" preview/retry/submit/aria/overflow");
   passed++;
   await page.close();
  }
 }
 const page=await browser.newPage();
 await page.route("https://core10-test.invalid/**",route=>route.fulfill({status:200,contentType:"text/html",body:fixture}));
 await page.goto("https://core10-test.invalid/index.html?workspace=islamia&biz=3");
 await page.addScriptTag({content:js});
 await page.evaluate(()=>{window.BOS_APP.S.ctx.is_owner=false;window.BOS_APP.H.c10_place_open()});
 assert.equal(await page.locator(".c10-site-panel").count(),0);
 console.log("PASS staff UI denies form");
 passed++;
 await page.close();
 console.log("RESULT "+passed+" browser cases PASS / 0 FAIL — simulated environment, NOT real Supabase Auth");
}finally{await browser.close()}
