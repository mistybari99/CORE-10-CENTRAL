"use strict";
const assert=require("node:assert/strict"),{chromium}=require("playwright");
const {createServer}=require("./static_server");
(async()=>{
 const srv=createServer();await new Promise(done=>srv.listen(0,"127.0.0.1",done));
 const base="http://127.0.0.1:"+srv.address().port,browser=await chromium.launch();
 try{for(const viewport of [{width:390,height:844},{width:1440,height:900}]){
  const context=await browser.newContext({viewport,isMobile:viewport.width<500,hasTouch:viewport.width<500}),page=await context.newPage(),errors=[];
  page.on("pageerror",e=>errors.push(e.message));
  await page.goto(base+"/core10-business-builder.html",{waitUntil:"load"});
  await page.waitForFunction(()=>document.querySelector("#template")?.options.length===10,{},{timeout:20000});
  assert.equal(await page.locator("#template option").count(),10);
  for(const template of ["sweets_bakery","restaurant","construction","paint_hardware"]){
   await page.locator("#template").selectOption(template);
   assert.equal(await page.locator("#template").inputValue(),template);
   const text=await page.locator("body").innerText();
   assert.doesNotMatch(text,/islamia|islamiya|ইসলামিয়া/i,"Shared setup leaked customized business identity for "+template);
   assert.equal(await page.locator("#legacyReuse").count(),0,"Legacy ERP navigation must not appear in shared wizard");
  }
  assert.equal(await page.locator("a[href*='owner.html']").count(),0,"No legacy business shortcut in generic create flow");
  assert.equal(await page.locator("#createStagingDraft").isDisabled(),true,"Draft writes remain locked");
  assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth-window.innerWidth)<=2,"No horizontal overflow");
  assert.deepEqual(errors,[],"No browser errors");
  console.log("PASS: neutral 10-industry wizard "+viewport.width+"px; no business-specific reports or shortcuts");
  await context.close();
 }}finally{await browser.close();await new Promise(done=>srv.close(done))}
})().catch(e=>{console.error(e);process.exitCode=1});
