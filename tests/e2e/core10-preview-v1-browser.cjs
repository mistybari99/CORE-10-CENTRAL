"use strict";
const assert=require("node:assert/strict"),{chromium}=require("playwright");
const base="https://core10-central-preview-v1.mistybari99.workers.dev";
(async()=>{
 const browser=await chromium.launch({headless:true});
 try {
  for(const width of [390,1440]){
   const page=await browser.newPage({viewport:{width,height:900}}),errors=[];
   page.on("pageerror",e=>errors.push(e.message));
   await page.goto(base+"/",{waitUntil:"load",timeout:30000});
   await page.locator('[data-nav="overview"]').waitFor();
   assert.match(await page.locator("body").innerText(),/Enterprise overview/);
   if(width<=760)await page.locator("#menu").click();
   await page.locator('[data-nav="inventory"]').click();
   const row=page.locator("tr").filter({hasText:"Sample flour"});
   assert.match(await row.innerText(),/48 kg/);
   await row.locator('[data-receive="DEMO-FLR"]').click();
   assert.match(await page.locator("tr").filter({hasText:"Sample flour"}).innerText(),/53 kg/);
   if(width<=760)await page.locator("#menu").click();
   await page.locator('[data-nav="controls"]').click();
   await page.locator('[data-toggle="0"]').click();
   assert.match(await page.locator("#toast").innerText(),/No server write/);
   const overflow=await page.evaluate(()=>document.documentElement.scrollWidth-innerWidth);
   assert.ok(overflow<=2,"page horizontal overflow at "+width+": "+overflow);
   assert.deepEqual(errors,[],"Client page errors "+width+": "+errors.join("; "));
   await page.screenshot({path:"/tmp/core10-preview-"+width+".png",fullPage:true});
   await page.close();
   console.log("PASS CORE10 Preview V1 "+width+"px interactive stock, control toggle, navigation & overflow");
  }
  const demo=await browser.newPage({viewport:{width:390,height:900}}),errors=[];
  demo.on("pageerror",e=>errors.push(e.message));
  await demo.goto(base+"/core10-engine-workshop-demo.html",{waitUntil:"load",timeout:30000});
  await demo.waitForFunction(()=>document.querySelector("#ew-status")?.textContent.includes("registry loaded"),{timeout:25000});
  assert.match(await demo.locator("body").innerText(),/DEMO PREVIEW/);
  assert.deepEqual(errors,[]);
  await demo.close();
  console.log("PASS original A045 browser demo through deployed preview Worker");
 }finally{await browser.close()}
})().catch(e=>{console.error(e);process.exitCode=1});