"use strict";
const {test}=require("node:test"),assert=require("node:assert/strict"),http=require("node:http"),{pathToFileURL}=require("node:url"),path=require("node:path"),{chromium}=require("playwright");
test("actual preview interfaces at desktop and mobile, no remote preview requests",async()=>{
 const worker=(await import(pathToFileURL(path.resolve(__dirname,"../apps/central/dist-progress/worker.mjs")))).default;
 const server=http.createServer(async(req,res)=>{const r=await worker.fetch(new Request("http://127.0.0.1"+req.url,{method:req.method}));res.writeHead(r.status,Object.fromEntries(r.headers));res.end(Buffer.from(await r.arrayBuffer()));});
 await new Promise(resolve=>server.listen(0,"127.0.0.1",resolve));const base="http://127.0.0.1:"+server.address().port;
 const browser=await chromium.launch({headless:true});
 try {for(const width of [390,1440]){const context=await browser.newContext({viewport:{width,height:850}}),page=await context.newPage(),errors=[],external=[];
 page.on("pageerror",e=>errors.push(e.message));await context.route("**/*",async route=>{if(!route.request().url().startsWith(base+"/")){external.push(route.request().url());return route.abort();}return route.continue();});
 await page.goto(base+"/#/home");await page.locator('#c10-entry a[href="#/progress"]').click();
 await page.waitForFunction(()=>document.body.dataset.view==="progress");const frame=page.frameLocator("#c10-frame");
 await frame.locator(".cards article").first().waitFor();assert.equal(await frame.locator(".cards article").count(),19);
 await frame.locator('a[href="/progress/manufacturing/index.html"]').click();await frame.locator("[data-tab=recipes]").waitFor();await frame.locator(".op-record").first().waitFor();
 await frame.locator("[data-tab=batches]").click();await frame.locator("[data-tab=reports]").click();await frame.locator(".mfg-kpis").waitFor();
 await page.goto(base+"/progress/paperops/index.html");await page.locator("#form option").first().waitFor({state:"attached"});await page.locator("#previewButton").click();await page.locator(".paperops-form").waitFor();assert.equal(await page.locator("#printButton").isEnabled(),true);
 await page.goto(base+"/progress/paperops/kit.html");await page.locator("#generate").click();await page.waitForFunction(()=>document.querySelector("#status").textContent.trim().length>0);assert.equal(await page.locator("#print").isEnabled(),true);
 await page.goto(base+"/progress/paperops/checks.html");await page.locator("#workFields input").first().waitFor();await page.locator("#check").click();await page.waitForFunction(()=>document.querySelector("#state").textContent.includes("BLOCK"));
 await page.goto(base+"/progress/crm/index.html");await page.locator("#syn-banner").waitFor();await page.locator("#kpi-customers").waitFor();
 assert.deepEqual(errors,[]);assert.deepEqual(external.filter(u=>!u.startsWith("https://rhrqhbyzrhaafynfhdaf.supabase.co/")),[]);
 await context.close();console.log("PROGRESS_BROWSER_PASS "+width);
 }} finally {await browser.close();await new Promise(resolve=>server.close(resolve));}
});
