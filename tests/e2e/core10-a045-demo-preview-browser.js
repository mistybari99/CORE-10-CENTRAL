"use strict";
/* The static DEMO preview page must work with no network and no Supabase, and must say it is a demo. */
const assert=require("node:assert/strict"),{chromium}=require("playwright"),{createServer}=require("./static_server");
(async()=>{
 const server=createServer();await new Promise(r=>server.listen(0,"127.0.0.1",r));
 const base="http://127.0.0.1:"+server.address().port,browser=await chromium.launch({headless:true});
 try{
  for(const width of [390,1440]){
   const page=await browser.newPage({viewport:{width,height:900}}),errors=[],external=[];
   page.on("pageerror",e=>errors.push(e.message));page.on("request",r=>{if(!r.url().startsWith(base))external.push(r.url())});
   await page.goto(base+"/core10-engine-workshop-demo.html",{waitUntil:"load"});
   await page.waitForFunction(()=>document.querySelector("#ew-status")?.textContent.includes("registry loaded"),{timeout:20000});
   assert.match(await page.locator("body").innerText(),/DEMO PREVIEW[\s\S]*nothing is saved/);
   await page.locator("#ew-key").fill("demo_low_stock");await page.locator("#ew-name").fill("Demo Low Stock");
   await page.locator("#ew-reason").fill("Demo walk-through");await page.locator("#ew-save").click();
   await page.waitForFunction(()=>document.querySelector("#ew-status")?.textContent.includes("Saved immutable version 1"));
   await page.locator("#ew-validate").click();await page.waitForFunction(()=>document.querySelector("#ew-status")?.textContent.includes("VALIDATED"));
   await page.locator("#ew-pub-business").selectOption("101");await page.locator("#ew-pub-save").click();
   await page.waitForFunction(()=>document.querySelector("#ew-status")?.textContent.includes("Business #101 → PUBLISHED"));
   const o=await page.evaluate(()=>document.documentElement.scrollWidth-innerWidth);assert.ok(o<=2,"overflow "+o);
   assert.deepEqual(errors,[]);assert.deepEqual(external,[]);await page.close();
   console.log("PASS A045 demo preview "+width+"px (in-memory, no network)");
  }
 }finally{await browser.close();await new Promise(r=>server.close(r))}
})().catch(e=>{console.error(e);process.exitCode=1});
