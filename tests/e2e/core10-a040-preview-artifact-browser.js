"use strict";
// Review EXACT downloadable artifact using a real responsive Chromium browser.
const assert=require("node:assert/strict"),fs=require("node:fs"),http=require("node:http"),path=require("node:path");
const {chromium}=require("playwright"),{verify}=require("../../internal/core10-a040-preview-package.js");
(async()=>{
 const input=process.argv[2];
 if(!input||!path.isAbsolute(input))throw Error("ABSOLUTE_ARTIFACT_REQUIRED");
 const dir=path.resolve(input);verify(dir);
 const mime={".html":"text/html; charset=utf-8",".js":"text/javascript; charset=utf-8",
 ".css":"text/css; charset=utf-8",".svg":"image/svg+xml",".json":"application/json"};
 const server=http.createServer((req,res)=>{
  let url;try{url=decodeURIComponent(new URL(req.url,"http://127.0.0.1").pathname)}catch{res.writeHead(400);res.end();return}
  const name=url==="/index.html"||url==="/"?"/index.html":url;
  const file=path.resolve(dir,name.slice(1));
  if(!file.startsWith(dir+path.sep)||!fs.existsSync(file)||!fs.statSync(file).isFile()){
   res.writeHead(404);res.end("not found");return}
  res.writeHead(200,{"content-type":mime[path.extname(file)]||"application/octet-stream","cache-control":"no-store"});
  fs.createReadStream(file).pipe(res);
 });
 await new Promise(resolve=>server.listen(0,"127.0.0.1",resolve));
 const origin="http://127.0.0.1:"+server.address().port;
 const browser=await chromium.launch();
 try{
  for(const file of ["owner.html","config.js","vendor/supabase.js","internal/enterprise-sql/c10_a038_stocktake_v1.sql","tests/private.js"]){
   const res=await fetch(origin+"/"+file);assert.equal(res.status,404,"forbidden in isolated artifact: "+file);
  }
  for(const width of [390,1440]){
   const page=await browser.newPage({viewport:{width,height:844}});
   const errors=[],external=[];
   page.on("pageerror",e=>errors.push(e.message));
   page.on("request",r=>{if(!r.url().startsWith(origin))external.push(r.url())});
   const initial=await page.goto(origin+"/index.html");
   assert.equal(initial.status(),200);
   assert.match(await page.locator("main").innerText(),/SIMULATED DATA ONLY/);
   await page.getByRole("link",{name:"Open interactive Stocktake Demo"}).click();
   assert.match(page.url(),/\/core10-stocktake-preview\.html$/);
   await page.locator("#metrics .c10-metric").first().waitFor();
   assert.equal(await page.locator("#metrics .c10-metric").count(),4);
   assert.equal(await page.locator("#stage-read").isDisabled(),true);
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
   assert.match(page.url(),/\/index\.html$/);
   const scroll=await page.evaluate(()=>document.documentElement.scrollWidth-window.innerWidth);
   assert.ok(scroll<=2,"responsive artifact overflow "+width+": "+scroll);
   assert.deepEqual(errors,[],"runtime failures "+width);
   assert.deepEqual(external,[],"synthetic review must send no external requests");
   console.log("PASS A040 "+width+"px isolated artifact: launch, Staff count, Owner approve/post, audit, back link, no external calls");
   await page.close();
  }
 }finally{await browser.close();await new Promise(resolve=>server.close(resolve))}
})().catch(e=>{console.error("FAIL A040 artifact browser:",e.stack);process.exitCode=1});
