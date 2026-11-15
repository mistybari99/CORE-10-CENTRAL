"use strict";
/* PACK-02 synthetic browser layout/isolation check at 390px and 1440px.
 * Renders verbatim SQL projection fixtures; NOT signed GoTrue/hosted proof. */
const assert=require("node:assert/strict"),fs=require("node:fs"),path=require("node:path");
const {chromium}=require("playwright");
const root=path.join(__dirname,"../..");
const css=fs.readFileSync(path.join(root,"core10-pack02-workspace.css"),"utf8");
const js=fs.readFileSync(path.join(root,"core10-pack02-workspace.js"),"utf8")+";"+fs.readFileSync(path.join(root,"core10-pack02-controls.js"),"utf8");
const fx=n=>fs.readFileSync(path.join(__dirname,"fixtures",n+".json"),"utf8");
const html=`<!doctype html><html lang="bn"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><style>${css}</style></head><body style="margin:0"><div id="ws" class="p2-root"></div><script>${js}</script></body></html>`;
const out=process.env.PACK02_SCREENSHOT_DIR||"";
(async()=>{
 const browser=await chromium.launch(process.env.CORE10_CHROMIUM_PATH?{executablePath:process.env.CORE10_CHROMIUM_PATH}:{});
 try{
  for(const width of [390,1440]){
   for(const name of ["universal-owner","business-owner","business-owner-branded","staff"]){
    const page=await browser.newPage({viewport:{width,height:900}});
    const errors=[],external=[];
    page.on("pageerror",e=>errors.push(e.message));
    page.on("request",r=>{if(!r.url().startsWith("data:")&&r.url()!=="about:blank")external.push(r.url());});
    await page.setContent(html,{waitUntil:"load"});
    await page.evaluate(p=>{const W=window.CORE10_PACK02_WORKSPACE;W.render(document.getElementById("ws"),W.view(JSON.parse(p)));},fx(name));
    const m=await page.evaluate(()=>({sw:document.documentElement.scrollWidth,cw:document.documentElement.clientWidth,
     text:document.body.innerText,nav:[...document.querySelectorAll(".p2-nav-item")].map(b=>({h:b.getBoundingClientRect().height,k:b.dataset.key})),
     umbrella:!!document.querySelector(".p2-umbrella"),lang:document.documentElement.lang,
     disabled:[...document.querySelectorAll(".p2-nav-item")].every(b=>b.disabled&&b.getAttribute("aria-disabled")==="true")}));
    assert.equal(m.disabled,true,"unwired nav must render disabled");
    assert.ok(m.sw<=m.cw,`${name}@${width} horizontal overflow ${m.sw}>${m.cw}`);
    assert.ok(m.nav.length>0&&m.nav.every(n=>n.h>=44),`${name}@${width} touch target`);
    assert.equal(m.lang,"bn");
    if(name==="staff"){
     assert.ok(!/CORE\s*10/i.test(m.text),"staff sees umbrella");
     assert.ok(!/demo-second-business|A2\b/.test(m.text),"staff sees sister data");
     assert.equal(m.umbrella,false);
     assert.match(m.text,/আমার কাজ/);
    }
    if(name==="business-owner")assert.equal(m.umbrella,false,"non-tenant business owner sees umbrella link");
    if(name==="business-owner-branded"){assert.equal(m.umbrella,true);assert.match(m.text,/রঙ ঘর ডেমো/);}
    if(name==="universal-owner")assert.match(m.text,/সব ব্যবসার সারাংশ/);
    assert.deepEqual(errors,[]);assert.deepEqual(external,[]);
    // With a handler, items become live and report their key.
    const clicked=await page.evaluate(p=>{const W=window.CORE10_PACK02_WORKSPACE,got=[];const r=document.getElementById("ws");
     W.render(r,W.view(JSON.parse(p)),k=>got.push(k));r.querySelector(".p2-nav-item").click();return got;},fx(name));
    assert.equal(clicked.length,1);
    if(out){fs.mkdirSync(out,{recursive:true});await page.screenshot({path:path.join(out,`${name}-${width}.png`),fullPage:true});}
    await page.close();
   }
  }
  for(const width of [390,1440]){
   for(const name of ["controls-central","controls-business"]){
    const page=await browser.newPage({viewport:{width,height:900}});
    const errors=[];page.on("pageerror",e=>errors.push(e.message));
    await page.setContent(html,{waitUntil:"load"});
    await page.evaluate(p=>{const C=window.CORE10_PACK02_CONTROLS;C.render(document.getElementById("ws"),C.view(JSON.parse(p)));},fx(name));
    const m=await page.evaluate(()=>({sw:document.documentElement.scrollWidth,cw:document.documentElement.clientWidth,
     text:document.body.innerText,n:document.querySelectorAll("[data-control]").length}));
    assert.ok(m.sw<=m.cw,`${name}@${width} overflow`);
    assert.match(m.text,/অনুমতি নয়/);
    if(name==="controls-business"){assert.equal(m.n,2);assert.ok(!/পেমেন্ট|ডেটা এক্সপোর্ট/.test(m.text),"hidden/central control shown to business owner");}
    else assert.equal(m.n,18);
    assert.deepEqual(errors,[]);
    if(out)await page.screenshot({path:path.join(out,`${name}-${width}.png`),fullPage:true});
    await page.close();
   }
  }
  console.log("PASS PACK-02 workspace browser 390px/1440px: overflow, touch targets, Bangla labels, staff isolation (synthetic fixtures)");
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exit(1);});
