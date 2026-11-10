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
  for(const viewport of [{width:390,height:844},{width:1440,height:900}]){
   const context=await browser.newContext({viewport,isMobile:viewport.width<500,hasTouch:viewport.width<500});
   const page=await context.newPage();
   const errors=[];
   page.on("pageerror",e=>errors.push(e.message));
   await page.goto(base+"/core10-business-builder.html",{waitUntil:"load"});
   await page.locator("#template option").nth(9).waitFor({timeout:20000});
   assert.equal(await page.locator("#template option").count(),10,"ten industry templates");
   assert.equal(await page.locator("#createStagingDraft").isDisabled(),true,"production draft writes locked");
   await page.locator("#businessName").fill("Test Enterprise");
   await page.locator("#slug").fill("test-enterprise");
   await page.locator("#mode").selectOption("advanced");
   await page.locator("#next").click();
   assert.equal(await page.locator("#step1").isVisible(),true);
   await page.locator("#module-stock").check();
   await page.locator("#next").click();
   assert.equal(await page.locator("#step2").isVisible(),true);
   await page.locator("#siteName").fill("Main Showroom");
   await page.locator("#siteKind").selectOption("showroom");
   await page.locator("#addSite").click();
   assert.match(await page.locator("#siteRows").innerText(),/Main Showroom/);
   await page.locator("#next").click();
   assert.equal(await page.locator("#step3").isVisible(),true);
   const preview=JSON.parse(await page.locator("#jsonPreview").innerText());
   assert.equal(preview.production_ready,false);
   assert.equal(preview.model.templateId,"sweets_bakery");
   assert.equal(preview.model.modules.includes("stock"),true);
   assert.equal(preview.model.sites.length,1);
   const overflow=await page.evaluate(()=>document.documentElement.scrollWidth-window.innerWidth);
   assert.ok(overflow<=2,"No horizontal overflow on "+viewport.width+"px viewport (delta "+overflow+")");
   assert.deepEqual(errors,[],"No page errors");
   console.log("PASS CORE10 business wizard "+viewport.width+"px: ten templates, site + module flow, locked production writes");
   await context.close();
  }
 }finally{
  await browser.close();
  await new Promise(resolve=>server.close(resolve));
 }
})().catch(e=>{console.error(e);process.exitCode=1});
