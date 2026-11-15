"use strict";
// D051 isolated anonymous public-route visual comparison, never Owner proof.
const assert=require("node:assert/strict");
const fs=require("node:fs");
const path=require("node:path");
const http=require("node:http");
const {execFileSync}=require("node:child_process");
const {chromium}=require("playwright");
const {PNG}=require("pngjs");
const main="c39052910758ca285a7a4d56e9c4f4873cb7d99c";
const original=path.resolve(process.env.CORE10_D051_ORIGINAL_ROOT||"/__d051_missing__");
const candidate=path.resolve(__dirname,"../..");
const git=(root,args)=>execFileSync("git",args,{cwd:root,encoding:"utf8"}).trim();
assert.equal(git(original,["rev-parse","HEAD"]),main,"D051 original snapshot SHA mismatch");
assert.equal(git(original,["hash-object","index.html"]),
 "fa1856bae67fed10764d7e797c6922378a209361","D051 main entry changed");
assert.equal(git(candidate,["hash-object","index.html"]),
 "f2f74144e13ed865f45d84d6e683d49d2972cb5d","D051 preview entry changed");
const mime={".html":"text/html; charset=utf-8",".js":"text/javascript; charset=utf-8",
 ".css":"text/css; charset=utf-8",".json":"application/json",".svg":"image/svg+xml",
 ".png":"image/png",".woff2":"font/woff2"};
const server=http.createServer((req,res)=>{
 try{
  const uri=new URL(req.url,"http://127.0.0.1"),parts=uri.pathname.split("/").filter(Boolean);
  const view=parts.shift(),base=view==="original"?original:view==="candidate"?candidate:null;
  if(!base||!["GET","HEAD"].includes(req.method)){res.writeHead(404);res.end();return;}
  const rel=decodeURIComponent(parts.join("/")||"index.html");
  const file=path.resolve(base,rel);
  if(!file.startsWith(base+path.sep)||rel.startsWith(".")||rel.includes("/.")||
     !fs.existsSync(file)||!fs.statSync(file).isFile()){res.writeHead(404);res.end();return;}
  res.writeHead(200,{"content-type":mime[path.extname(file)]||"application/octet-stream","cache-control":"no-store"});
  res.end(req.method==="HEAD"?"":fs.readFileSync(file));
 }catch{res.writeHead(404);res.end();}
});
const clean=s=>String(s||"").replace(/\s+/g," ").trim();
function pixelDelta(a,b){
 const x=PNG.sync.read(a),y=PNG.sync.read(b);
 assert.equal(x.width,y.width,"D051 screenshot width changed");
 assert.equal(x.height,y.height,"D051 screenshot height changed");
 let n=0,total=x.width*x.height;
 for(let i=0;i<x.data.length;i+=4){
  if(Math.max(Math.abs(x.data[i]-y.data[i]),
    Math.abs(x.data[i+1]-y.data[i+1]),
    Math.abs(x.data[i+2]-y.data[i+2]),
    Math.abs(x.data[i+3]-y.data[i+3]))>24)n++;
 }
 return {n,total,ratio:n/total};
}
(async()=>{
 await new Promise(resolve=>server.listen(0,"127.0.0.1",resolve));
 const base="http://127.0.0.1:"+server.address().port;
 const browser=await chromium.launch({headless:true,
  ...(process.env.CORE10_CHROMIUM_PATH?{executablePath:process.env.CORE10_CHROMIUM_PATH}:{})});
 try{
  for(const width of [390,1440]){
   for(const route of ["#/home","#/stock","#/reports"]){
    const evidence=[];
    for(const view of ["original","candidate"]){
     const context=await browser.newContext({viewport:{width,height:900},
       colorScheme:"dark",reducedMotion:"reduce",serviceWorkers:"block",
       locale:"bn-BD",timezoneId:"Asia/Dhaka"});
     const page=await context.newPage(),remote=[],writes=[];
     await page.route("**/*",handler=>{
      const request=handler.request();
      if(!request.url().startsWith(base+"/")){remote.push(request.url());return handler.abort();}
      if(!["GET","HEAD"].includes(request.method())){
       writes.push(request.method()+" "+request.url());return handler.abort();
      }
      return handler.continue();
     });
     await page.goto(base+"/"+view+"/index.html"+route,{waitUntil:"domcontentloaded",timeout:30000});
     await page.waitForTimeout(1000);
     const state=await page.evaluate(()=>({
      title:document.title,hash:location.hash,
      root:document.getElementById("app")?.innerText||"",
      ownerControl:!!document.getElementById("core10-studio-entry"),
      overflow:document.documentElement.scrollWidth>innerWidth+2,
      hasApp:!!document.getElementById("app")
     }));
     assert.ok(state.hasApp,"D051 missing legacy app root");
     assert.match(state.title,/ISLAMIYA MISTY GHAR|ইসলামিয়া মিষ্টি ঘর/);
     assert.equal(state.ownerControl,false,"D051 no Owner UI for anonymous");
     assert.deepEqual(writes,[],"D051 forbids any HTTP write");
     const screenshot=await page.screenshot({animations:"disabled",caret:"hide"});
     evidence.push({state,screenshot,remote:remote.length});
     await context.close();
    }
    assert.equal(evidence[0].state.title,evidence[1].state.title,"D051 title changed");
    assert.equal(evidence[0].state.hash,evidence[1].state.hash,"D051 public route changed");
    assert.equal(clean(evidence[0].state.root),clean(evidence[1].state.root),
      "D051 anonymous legacy shell changed");
    assert.equal(evidence[0].state.overflow,evidence[1].state.overflow,
      "D051 mobile/desktop overflow parity changed");
    const d=pixelDelta(evidence[0].screenshot,evidence[1].screenshot);
    assert.ok(d.ratio<=0.005,"D051 public visual changed "+width+" "+route+" "+d.n+"/"+d.total);
    console.log("PASS D051 anonymous route "+route+" "+width+"px: original/Preview visual delta "+
      (d.ratio*100).toFixed(3)+"%, no writes, remote blocked");
   }
  }
  console.log("D051 LIMIT: anonymous local shell only; original Owner route/records/real role/site flow NOT VERIFIED");
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1})
 .finally(()=>new Promise(resolve=>server.close(resolve)));
