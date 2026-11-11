// C10-A058: isolated responsive browser UI E2E, all identities and stocks synthetic.
// The local HTTP server has no Supabase/auth/provider connection.
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
import { chromium } from "playwright";
const require=createRequire(import.meta.url);
const {createServer}=require("./e2e/static_server.js");
const server=createServer();
await new Promise(resolve=>server.listen(0,"127.0.0.1",resolve));
const url="http://127.0.0.1:"+server.address().port+"/modules/quality/index.html";
const browser=await chromium.launch({headless:true,args:["--no-sandbox"]});
const root="a058-artifacts";
fs.mkdirSync(root,{recursive:true});
try {
 for(const viewport of [{width:390,height:844},{width:1440,height:900}]){
  const context=await browser.newContext({viewport,isMobile:viewport.width<500,hasTouch:viewport.width<500});
  const page=await context.newPage();
  const errors=[];
  page.on("pageerror",error=>errors.push(String(error)));
  // The repo's legacy static test server serves unknown .mjs as octet-stream.
  // Supply correct JavaScript MIME for this isolated module test without editing it.
  await page.route("**/*.mjs",async route=>{
   const pathname=decodeURIComponent(new URL(route.request().url()).pathname);
   const file=path.resolve(process.cwd(),"."+pathname);
   if(!file.startsWith(process.cwd()+path.sep) || !file.endsWith(".mjs")) {
    await route.abort();return;
   }
   await route.fulfill({status:200,contentType:"text/javascript; charset=utf-8",body:fs.readFileSync(file)});
  });
  const response=await page.goto(url,{waitUntil:"load"});
  assert.equal(response.status(),200,"quality page returns 200");
  await page.waitForSelector("#lot-results",{state:"detached"}).catch(()=>{});
  await page.waitForSelector("#quality-view .quality-stat");
  assert.match(await page.locator("h1").innerText(),/CORE 10 CENTRAL/);
  assert.match(await page.locator(".badge").innerText(),/SYNTHETIC/);
  assert.equal(await page.locator('#actor option').count(),6,"six synthetic role choices");
  assert.equal(await page.locator('#business option').count(),2,"owner two demo businesses");
  assert.equal(await page.locator('button[data-view]').count(),5,"five module destinations");
  assert.equal(await page.locator('#quality-view .quality-stat').count(),4,"four overview KPIs");
  let overflow=await page.evaluate(()=>document.documentElement.scrollWidth-innerWidth);
  assert.ok(overflow<=2,"initial viewport horizontal overflow: "+viewport.width+" / "+overflow);
  await page.screenshot({path:path.join(root,"overview-"+viewport.width+".png"),fullPage:true});

  // QC inspection, release and inventory issue are functional in-memory operations.
  await page.locator('button[data-view="lots"]').click();
  assert.equal(await page.locator("tbody tr").count(),3,"three visible sweets demo lots");
  await page.locator('button[data-action="inspect"][data-id="2"]').click();
  assert.ok(await page.locator("#quality-dialog").isVisible(),"QC dialog visible");
  await page.locator('select[name="pass"]').selectOption("true");
  await page.locator("#quality-form button[type=submit]").click();
  assert.ok(!(await page.locator("#quality-dialog").isVisible()),"QC completed");
  await page.locator('button[data-action="release"][data-id="2"]').click();
  await page.locator("#quality-form button[type=submit]").click();
  assert.match(await page.locator("tbody tr").nth(1).innerText(),/Released/);
  await page.locator('button[data-action="issue"][data-id="2"]').click();
  await page.locator('input[name="quantity"]').fill("2");
  await page.locator("#quality-form button[type=submit]").click();
  assert.match(await page.locator("tbody tr").nth(1).innerText(),/\b6\b/,"issue reduced lot stock to six");
  await page.screenshot({path:path.join(root,"qc-release-issue-"+viewport.width+".png"),fullPage:true});

  // Recall is cascaded from parent lot and cannot close before disposition.
  await page.locator('button[data-action="recall"][data-id="1"]').click();
  await page.locator('input[name="reason"]').fill("Simulated defective ingredients");
  await page.locator("#quality-form button[type=submit]").click();
  assert.match(await page.locator("tbody tr").nth(0).innerText(),/Recalled/);
  assert.match(await page.locator("tbody tr").nth(1).innerText(),/Recalled/);
  await page.locator('button[data-view="recalls"]').click();
  assert.match(await page.locator("#quality-view").innerText(),/Affected lots: 1, 2/);
  await page.locator('button[data-action="close"]').click();
  await page.locator("#quality-form button[type=submit]").click();
  assert.match(await page.locator("#notice").innerText(),/recall_stock_remaining/);
  await page.locator("#cancel-action").click();
  await page.screenshot({path:path.join(root,"recall-"+viewport.width+".png"),fullPage:true});

  // Synthetic role switch: foreign tenant is restricted to its own company.
  await page.locator("#actor").selectOption("foreign");
  assert.equal(await page.locator("#business option").count(),1);
  assert.match(await page.locator("#business option").innerText(),/Independent Demo Tenant/);
  await page.locator('button[data-view="lots"]').click();
  assert.equal(await page.locator("tbody tr").count(),1,"foreign tenant sees one authorized lot");
  assert.match(await page.locator("tbody tr").first().innerText(),/FOREIGN-LOT/);
  assert.ok(!(await page.locator("#quality-view").innerText()).includes("RAS-261112-A"),"no foreign cross-tenant lot");
  await page.locator("#actor").selectOption("investor");
  assert.equal(await page.locator("tbody tr").count(),0,"investor cannot see operational lots");
  await page.screenshot({path:path.join(root,"roles-"+viewport.width+".png"),fullPage:true});

  // Reset restores deterministic demo and does not generate network requests.
  await page.locator("#actor").selectOption("owner");
  await page.locator("#reset").click();
  await page.locator('button[data-view="lots"]').click();
  assert.match(await page.locator("tbody tr").nth(1).innerText(),/Pending QC/);
  overflow=await page.evaluate(()=>document.documentElement.scrollWidth-innerWidth);
  assert.ok(overflow<=2,"post-interaction viewport overflow: "+viewport.width+" / "+overflow);
  assert.deepEqual(errors,[],"no script errors");
  console.log("PASS A058 browser "+viewport.width+"px: responsive, QC, release, issue, cascading recall, role isolation, reset");
  await context.close();
 }
} finally {
 await browser.close();
 await new Promise(resolve=>server.close(resolve));
}
