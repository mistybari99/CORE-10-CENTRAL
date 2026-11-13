"use strict";
// Unconfigured surface must never fall back to legacy/production configuration.
const assert=require("node:assert/strict"),{chromium}=require("playwright");
const {createServer}=require("./static_server");
(async()=>{
 const server=createServer();await new Promise(resolve=>server.listen(0,"127.0.0.1",resolve));
 const base="http://127.0.0.1:"+server.address().port;
 const browser=await chromium.launch({headless:true,...(process.env.CORE10_CHROMIUM_PATH?{executablePath:process.env.CORE10_CHROMIUM_PATH}:{})});
 try{
  for(const width of[390,1440]){
   const page=await browser.newPage({viewport:{width,height:900}}),errors=[],external=[],api=[];
   page.on("pageerror",e=>errors.push(e.message));page.on("request",r=>{if(!r.url().startsWith(base+"/"))external.push(r.url());if(/\/auth\/v1\/|\/rest\/v1\//.test(r.url()))api.push(r.url());});
   await page.addInitScript(()=>{window.BOS_CONFIG={url:"https://should-never-be-used.supabase.co",key:"legacy-production-placeholder"};});
   await page.goto(base+"/core10-build01.html");await page.waitForFunction(()=>document.querySelector("#b01-environment").textContent.includes("Root production config"));
   assert.equal(await page.locator('#b01-login-form button[type="submit"]').isDisabled(),true);
   assert.equal(await page.locator("#b01-workspace").isVisible(),false);
   await page.locator("#b01-language").click();assert.equal(await page.locator("html").getAttribute("lang"),"en");
   assert.match(await page.locator("h1").innerText(),/Business Setup, Login & Permissions Integration/);
   assert.match(await page.locator("#b01-environment").innerText(),/Root production configuration is never used/);
   assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth-innerWidth)<=2,"locked UI overflow "+width);
   assert.deepEqual(api,[]);assert.deepEqual(external,[]);assert.deepEqual(errors,[]);
   await page.close();console.log("PASS Build 01 locked UI "+width+"px: explicit config required, legacy fallback denied, no auth/API/external requests");
  }
 }finally{await browser.close();await new Promise(resolve=>server.close(resolve));}
})().catch(error=>{console.error(error);process.exitCode=1;});
