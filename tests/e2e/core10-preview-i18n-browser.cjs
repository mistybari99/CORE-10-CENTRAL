"use strict";
const assert=require("node:assert/strict");
const http=require("node:http");
const {chromium}=require("playwright");

(async()=>{
  const {default:worker}=await import("../../preview/worker.mjs");
  const server=http.createServer(async(req,res)=>{
    try{
      const response=await worker.fetch(new Request("http://127.0.0.1"+req.url,{method:req.method}));
      res.writeHead(response.status,Object.fromEntries(response.headers));
      res.end(req.method==="HEAD"?"":await response.text());
    }catch(err){res.writeHead(500);res.end(String(err));}
  });
  await new Promise(ok=>server.listen(0,"127.0.0.1",ok));
  const port=server.address().port,origin="http://127.0.0.1:"+port;
  let browser;
  try{
    browser=await chromium.launch({headless:true});
    for(const width of [390,1440]){
      for(const path of ["/","/build01-build02a.html"]){
        const page=await browser.newPage({viewport:{width,height:900}}),bad=[],errors=[];
        page.on("request",r=>{if(new URL(r.url()).origin!==origin||r.method()!=="GET")bad.push(r.method()+" "+r.url())});
        page.on("pageerror",e=>errors.push(e.message));
        await page.goto(origin+path,{waitUntil:"load",timeout:30000});
        await page.waitForFunction(()=>!!window.C10I18N&&document.documentElement.lang==="bn-BD");
        assert.equal(await page.locator("#c10-language").inputValue(),"bn-BD");
        assert.equal(await page.locator('label[for="c10-language"] span').innerText(),"ভাষা");
        assert.equal(await page.evaluate(()=>window.C10I18N.getLocale()),"bn-BD");
        if(path==="/"){
          assert.equal(await page.locator("#screen-title").innerText(),"সব ব্যবসা এক নজরে");
          if(width===390)await page.locator("#menu").click();
          await page.locator('[data-nav="inventory"]').click();
          assert.match(await page.locator("#screen").innerText(),/স্টকের কাজের ডেমো/);
          await page.locator('#stock-search').fill("ডেমো ময়দা");
          const row=page.locator("tr").filter({hasText:"ডেমো ময়দা"});
          assert.match(await row.innerText(),/48 kg/);
          await row.locator('[data-receive="DEMO-FLR"]').click();
          assert.match(await page.locator("tr").filter({hasText:"ডেমো ময়দা"}).innerText(),/53 kg/);
        }else{
          assert.match(await page.locator("h1").innerText(),/Business Setup ও Approval-এর Access/);
          assert.match(await page.locator(".notice").innerText(),/A046-এর বানানো ডেমো ইউজার/);
          assert.match(await page.locator(".first-use").innerText(),/Approval \(অনুমোদনের ধাপ\)/);
          await page.locator("#resolve").click();
          assert.match(await page.locator("#decision").innerText(),/অনুমতি আছে/);
          await page.locator("#actor").selectOption("revoked");
          await page.locator("#resolve").click();
          assert.match(await page.locator("#decision").innerText(),/অনুমতি নেই/);
        }
        await page.locator("#c10-language").selectOption("en");
        assert.equal(await page.locator('label[for="c10-language"] span').innerText(),"Language");
        assert.equal(await page.evaluate(()=>window.C10I18N.getLocale()),"en");
        assert.equal(await page.locator("html").getAttribute("lang"),"en");
        if(path==="/"){
          assert.match(await page.locator("#screen").innerText(),/Inventory command preview/);
          assert.match(await page.locator("tr").filter({hasText:"Sample flour"}).innerText(),/53 kg/);
        }else{
          assert.equal(await page.locator("h1").innerText(),"Business setup and Approval permissions");
          assert.match(await page.locator(".first-use").innerText(),/Approval \(review step\)/);
          assert.match(await page.locator("#decision").innerText(),/DENY/);
        }
        await page.locator("#c10-language").selectOption("bn-BD");
        assert.equal(await page.locator("html").getAttribute("lang"),"bn-BD");
        assert.equal(await page.locator('label[for="c10-language"] span').innerText(),"ভাষা");
        const overflow=await page.evaluate(()=>document.documentElement.scrollWidth-innerWidth);
        assert.ok(overflow<=2,path+" at "+width+"px horizontal overflow "+overflow);
        assert.deepEqual(bad,[],path+" unexpected requests "+bad.join("; "));
        assert.deepEqual(errors,[],path+" JS errors "+errors.join("; "));
        await page.close();
        console.log("PASS C10-A064 "+path+" "+width+"px · bn default, en toggle, interaction, zero network/write");
      }
    }
    console.log("PASS C10-A064 all local-only 390/1440 browser checks");
  }finally{if(browser)await browser.close();await new Promise(ok=>server.close(ok));}
})().catch(e=>{console.error(e);process.exitCode=1;});
