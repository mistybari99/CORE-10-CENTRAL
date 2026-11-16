"use strict";
/* PACK-02 S2 under ACTUAL local GoTrue password sessions, through the Build01
 * isolated gateway and page. Runs only where the S2 Build01 patch is applied
 * (tests/build01/run-auth.sh). Local GoTrue is NOT hosted staging proof. */
const assert=require("node:assert/strict");
const {chromium}=require("playwright");
const base=(process.env.BUILD01_BASE_URL||"").replace(/\/$/,""),password=process.env.BUILD01_TEST_PASSWORD;
const ownerEmail=process.env.BUILD01_OWNER_EMAIL||"build01-owner@example.test",staffEmail=process.env.BUILD01_STAFF_EMAIL||"build01-staff@example.test";
if(!/^http:\/\/(?:127\.0\.0\.1|localhost):\d+$/.test(base)||!password)throw Error("Dedicated loopback BUILD01_BASE_URL and synthetic BUILD01_TEST_PASSWORD required");
(async()=>{
 const cfg=await (await fetch(base+"/core10-build01-config.js")).text();
 const key=JSON.parse(cfg.slice(cfg.indexOf("(")+1,cfg.lastIndexOf(")"))).publishableKey;
 const token=async email=>{const r=await fetch(base+"/auth/v1/token?grant_type=password",{method:"POST",headers:{apikey:key,"content-type":"application/json"},body:JSON.stringify({email,password})});assert.equal(r.status,200,"password login "+email);return (await r.json()).access_token;};
 const rpc=async(name,body,tok)=>{const h={apikey:key,"content-type":"application/json","content-profile":"core10"};if(tok)h.authorization="Bearer "+tok;const r=await fetch(base+"/rest/v1/rpc/"+name,{method:"POST",headers:h,body:JSON.stringify(body)});return {status:r.status,text:await r.text()};};
 // Direct signed API, no browser.
 const owner=await token(ownerEmail),staff=await token(staffEmail);
 let r=await rpc("pack02_workspace_v1",{p_mode:"universal_owner",p_business:null},owner);
 assert.equal(r.status,200,r.text);const uni=JSON.parse(r.text);assert.equal(uni.mode,"universal_owner");assert.ok(uni.businesses.length>=1);
 const biz=uni.businesses[0].id;
 r=await rpc("pack02_workspace_v1",{p_mode:"universal_owner",p_business:null},staff);assert.ok(r.status>=400&&/PACK02_WORKSPACE_DENIED/.test(r.text),"staff got umbrella: "+r.text);
 r=await rpc("pack02_workspace_v1",{p_mode:"business_owner",p_business:biz},staff);assert.ok(r.status>=400&&/PACK02_WORKSPACE_DENIED/.test(r.text),"staff got owner workspace");
 r=await rpc("pack02_controls_v1",{p_surface:"business",p_business:biz},staff);assert.ok(r.status>=400&&/PACK02_CONTROLS_DENIED/.test(r.text));
 r=await rpc("pack02_owner_report_v1",{},staff);assert.ok(r.status>=400&&/PACK02_REPORT_DENIED/.test(r.text));
 r=await rpc("pack02_owner_report_v1",{});assert.ok(r.status>=400,"anonymous owner report");assert.ok(!/businesses/.test(r.text));
 r=await rpc("pack02_owner_report_v1",{},owner.slice(0,-4)+"AAAA");assert.ok(r.status>=400,"tampered signature accepted");
 r=await rpc("pack02_setup_business_v1",{},owner);assert.equal(r.status,404,"write RPC must stay off the gateway allowlist");
 r=await rpc("pack02_brand_v1",{p_business:biz},owner);assert.equal(r.status,404);
 // Logout revokes: the old owner token no longer opens a workspace.
 const lo=await fetch(base+"/auth/v1/logout",{method:"POST",headers:{apikey:key,authorization:"Bearer "+owner}});assert.ok(lo.status<300,"logout");
 r=await rpc("pack02_workspace_v1",{p_mode:"universal_owner",p_business:null},owner);assert.ok(r.status>=400&&!/"businesses"/.test(r.text),"logged-out token still opens workspace");
 // Browser: Build01 page hosts the PACK-02 panel with its own signed session.
 const browser=await chromium.launch(process.env.CORE10_CHROMIUM_PATH?{executablePath:process.env.CORE10_CHROMIUM_PATH}:{});
 try{
  for(const width of [390,1440]){
   const page=await browser.newPage({viewport:{width,height:900}});const errors=[];page.on("pageerror",e=>errors.push(e.message));
   const login=async email=>{await page.goto(base+"/core10-build01.html",{waitUntil:"load"});await page.locator("#b01-email").fill(email);await page.locator("#b01-password").fill(password);await page.locator("#b01-login-form button[type=submit]").click();await page.waitForFunction(()=>document.querySelector("#b01-pack02 .p2-title")||document.querySelector("#b01-pack02 .p2-status")?.textContent,{timeout:20000});};
   const panel=()=>page.evaluate(()=>({text:document.getElementById("b01-pack02").innerText,title:document.querySelector("#b01-pack02 .p2-title")?.textContent||"",overflow:document.documentElement.scrollWidth>document.documentElement.clientWidth}));
   await login(ownerEmail);let m=await panel();assert.equal(m.title,"CORE 10","owner panel "+JSON.stringify(m));assert.equal(m.overflow,false);
   await page.click('#b01-pack02 .p2-nav-item[data-key="owner.reports"]');await page.waitForSelector("#b01-pack02 .p2-panel .p2-card",{timeout:15000});
   await page.locator("#b01-signout").click();await page.waitForFunction(()=>!document.querySelector("#b01-pack02 .p2-title"),{timeout:15000});
   m=await panel();assert.ok(!/CORE\s*10/.test(m.text),"panel not cleared on sign-out");
   await login(staffEmail);m=await panel();assert.ok(!/CORE\s*10/i.test(m.text),"staff sees umbrella: "+m.text);assert.ok(m.title&&m.title!=="CORE 10");
   assert.equal(await page.locator('#b01-pack02 .p2-nav-item[data-key^="owner."],#b01-pack02 .p2-nav-item[data-key^="biz."]').count(),0);
   assert.deepEqual(errors,[]);await page.close();
  }
 }finally{await browser.close();}
 console.log("PASS PACK-02 S2 ACTUAL local GoTrue: signed owner/staff API negatives, anon, tampered token, logout revocation, write RPC off allowlist, Build01-hosted panel 390/1440");
})().catch(e=>{console.error(e);process.exit(1);});
