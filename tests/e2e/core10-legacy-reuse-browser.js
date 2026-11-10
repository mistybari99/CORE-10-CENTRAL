"use strict";
const assert=require("node:assert/strict"),{chromium}=require("playwright");
const {createServer}=require("./static_server");
(async()=>{
 const srv=createServer();
 await new Promise(resolve=>srv.listen(0,"127.0.0.1",resolve));
 const base="http://127.0.0.1:"+srv.address().port;
 const browser=await chromium.launch();
 try{
  for(const viewport of [{width:390,height:844},{width:1440,height:900}]){
   const context=await browser.newContext({viewport,isMobile:viewport.width<500,hasTouch:viewport.width<500});
   const page=await context.newPage(),errors=[];
   page.on("pageerror",x=>errors.push(x.message));
   await page.goto(base+"/core10-business-builder.html",{waitUntil:"load"});
   await page.waitForFunction(()=>document.querySelector("#template")?.options.length===10,{},{timeout:20000});
   await page.locator("#legacyReuse").waitFor({state:"visible",timeout:12000});
   await page.waitForFunction(()=>document.querySelector("#legacyReuseDetails")?.textContent.includes("193 registered reports"),{},{timeout:12000});
   assert.match(await page.locator("#legacyReuseDetails").innerText(),/170 marked implemented/);
   const link=page.locator("#legacyReuseLink");
   assert.equal(await link.isVisible(),true);
   const href=await link.getAttribute("href");
   assert.equal(href,"./owner.html#/organization");
   assert.ok(!href.includes("biz="),"Never bind a hard-coded foreign business ID");
   await page.locator("#template").selectOption("restaurant");
   assert.equal(await page.locator("#legacyReuse").isHidden(),true,"No false legacy ERP promise on restaurant");
   await page.locator("#template").selectOption("sweets_bakery");
   assert.equal(await page.locator("#legacyReuse").isVisible(),true);
   assert.equal(await page.locator("#createStagingDraft").isDisabled(),true,"Staging draft creation defaults OFF");
   const delta=await page.evaluate(()=>document.documentElement.scrollWidth-window.innerWidth);
   assert.ok(delta<=2,"No horizontal overflow: "+delta);
   assert.deepEqual(errors,[],"No uncaught browser errors");
   console.log("PASS Islamia no-loss navigation, registry count, tenant-safe route and responsive UI at "+viewport.width+"px");
   await context.close();
  }
 }finally{await browser.close();await new Promise(done=>srv.close(done))}
})().catch(e=>{console.error(e);process.exitCode=1});
