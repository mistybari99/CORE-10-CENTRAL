"use strict";
const assert=require("node:assert/strict");
const {chromium}=require("playwright");
const {createServer}=require("./static_server");
(async()=>{
 const server=createServer();
 await new Promise(resolve=>server.listen(0,"127.0.0.1",resolve));
 const base="http://127.0.0.1:"+server.address().port;
 const browser=await chromium.launch();
 try{
  for(const width of [390,1440]){
   const page=await browser.newPage({viewport:{width,height:860}});
   const errors=[],external=[];
   page.on("pageerror",e=>errors.push(e.message));
   page.on("request",r=>{if(!r.url().startsWith(base))external.push(r.url())});
   await page.goto(base+"/core10-stocktake-preview.html",{waitUntil:"load"});
   await page.locator("#metrics .c10-metric").first().waitFor({timeout:15000});
   assert.equal(await page.locator("#metrics .c10-metric").count(),4);
   assert.equal(await page.locator("#stage-read").isDisabled(),true,
    "live staging read must be unavailable without explicit approval");
   assert.match(await page.locator(".c10-notice").innerText(),/NO ERP CHANGES/);
   assert.equal(await page.locator('[data-role="staff"]').getAttribute("aria-pressed"),"true");
   await page.locator('[data-screen="count"]').click();
   assert.equal(await page.locator("#physical-count-form").isVisible(),true);
   await page.locator('[data-item="8001"]').fill("231");
   await page.locator('[data-item="8003"]').fill("58");
   await page.locator('#physical-count-form button[type="submit"]').click();
   await page.waitForFunction(()=>document.querySelector("#feedback")?.textContent.includes("4104"));
   assert.match(await page.locator("#feedback").innerText(),/browser|locally/i);
   await page.locator('[data-screen="review"]').click();
   assert.equal(await page.locator('[data-act="approve"][data-id="4104"]').isDisabled(),true,
    "staff must never approve in preview");
   await page.locator('[data-role="owner"]').click();
   assert.equal(await page.locator('[data-act="approve"][data-id="4104"]').isEnabled(),true);
   await page.locator('[data-act="approve"][data-id="4104"]').click();
   await page.locator('[data-act="post"][data-id="4104"]').click();
   assert.match(await page.locator("#feedback").innerText(),/browser memory only/);
   await page.locator('[data-screen="audit"]').click();
   assert.match(await page.locator("#screen-content").innerText(),/Count #4104/);
   const release=await page.evaluate(()=>{
    return window.CORE10_STOCKTAKE_PREVIEW!==undefined&&
      window.CORE10_ENTERPRISE_CLIENT!==undefined;
   });
   assert.equal(release,true,"read-only enterprise bridge and preview modules should load");
   const overflow=await page.evaluate(()=>document.documentElement.scrollWidth-window.innerWidth);
   assert.ok(overflow<=2,"horizontal overflow on "+width+"px: "+overflow);
   assert.deepEqual(errors,[],"browser runtime errors on "+width+"px");
   assert.deepEqual(external,[],"no remote requests or live Supabase calls in preview");
   console.log("PASS A038 "+width+"px Staff count → Owner approval → demo post → Audit, 4 KPIs, backend locked, no external requests");
   await page.close();
  }
 }finally{
  await browser.close();
  await new Promise(resolve=>server.close(resolve));
 }
})().catch(e=>{console.error(e);process.exitCode=1});
