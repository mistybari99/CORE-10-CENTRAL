"use strict";
// Real Chromium file:// coverage approximates Android content:// isolated file opening.
const assert=require("node:assert/strict"),path=require("node:path"),{pathToFileURL}=require("node:url"),{chromium}=require("playwright");
(async()=>{
 const file=pathToFileURL(path.resolve(__dirname,"../../core10-stocktake-offline.html")).href;
 const browser=await chromium.launch();
 try{
  for(const width of [390,1440]){
   const page=await browser.newPage({viewport:{width,height:844}});
   const errors=[],requests=[];
   page.on("pageerror",e=>errors.push(e.message));
   page.on("request",r=>requests.push(r.url()));
   const res=await page.goto(file,{waitUntil:"load"});
   assert.equal(res.status(),200);
   await page.locator("#metrics .c10-metric").first().waitFor();
   assert.equal(await page.locator("#metrics .c10-metric").count(),4);
   assert.equal(await page.locator("#stage-read").isDisabled(),true);
   assert.match(await page.locator(".c10-notice").innerText(),/OFFLINE DEMO/);
   await page.locator('[data-screen="count"]').click();
   await page.locator('[data-item="8001"]').fill("231");
   await page.locator('#physical-count-form button[type="submit"]').click();
   assert.match(await page.locator("#feedback").innerText(),/4104/);
   await page.locator('[data-screen="review"]').click();
   assert.equal(await page.locator('[data-act="approve"][data-id="4104"]').isDisabled(),true);
   await page.locator('[data-role="owner"]').click();
   await page.locator('[data-act="approve"][data-id="4104"]').click();
   await page.locator('[data-act="post"][data-id="4104"]').click();
   await page.locator('[data-screen="audit"]').click();
   assert.match(await page.locator("#screen-content").innerText(),/Count #4104/);
   await page.locator(".c10-return").click();
   assert.match(await page.locator("#screen-content").innerText(),/Stocktake register/);
   const hor=await page.evaluate(()=>document.documentElement.scrollWidth-window.innerWidth);
   assert.ok(hor<=2,"horizontal overflow on "+width+"px: "+hor);
   assert.deepEqual(errors,[],"browser errors "+width);
   assert.deepEqual(requests,[file],"no external or sibling file request, including after clicks");
   console.log("PASS C10-A041 Chromium file:// "+width+"px offline Stocktake staff→owner→audit→overview");
   await page.close();
  }
 }finally{await browser.close()}
})().catch(e=>{console.error("FAIL C10-A041:",e.stack);process.exitCode=1});
