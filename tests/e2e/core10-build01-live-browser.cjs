"use strict";
// Real configured local GoTrue -> signed PostgREST -> PostgreSQL UI journey.
// No request interception, auth stubs, role claims or in-browser backend fixture.
const assert=require("node:assert/strict"),fs=require("node:fs"),path=require("node:path"),os=require("node:os");
const {chromium}=require("playwright");
const base=(process.env.BUILD01_BASE_URL||"").replace(/\/$/,"");
const password=process.env.BUILD01_TEST_PASSWORD;
const ownerEmail=process.env.BUILD01_OWNER_EMAIL||"build01-owner@example.test";
const staffEmail=process.env.BUILD01_STAFF_EMAIL||"build01-staff@example.test";
const subject="44444444-4444-4444-8444-444444444444";
if(!/^http:\/\/(?:127\.0\.0\.1|localhost):\d+$/.test(base)||!password)throw Error("Dedicated loopback BUILD01_BASE_URL and synthetic BUILD01_TEST_PASSWORD required");
const shots=process.env.BUILD01_SCREENSHOTS||path.join(os.tmpdir(),"core10-build01-shots");fs.mkdirSync(shots,{recursive:true});
(async()=>{
 const browser=await chromium.launch({headless:true,...(process.env.CORE10_CHROMIUM_PATH?{executablePath:process.env.CORE10_CHROMIUM_PATH}:{})});
 try{
  for(const width of [390,1440]){
   const page=await browser.newPage({viewport:{width,height:1000}}),errors=[],external=[];
   page.on("pageerror",e=>errors.push(e.message));
   page.on("request",r=>{if(!r.url().startsWith(base+"/")&&!r.url().startsWith("data:")&&!r.url().startsWith("blob:"))external.push(r.url());});
   const ready=()=>page.waitForFunction(()=>!document.querySelector("#b01-refresh").disabled,{timeout:30000});
   const submit=async(form,allowError=false)=>{await page.locator(form+' button[type="submit"]').click();await page.waitForFunction(()=>!document.querySelector("#b01-status").textContent.includes("Checking with the server")&&!document.querySelector("#b01-status").textContent.includes("Server যাচাই করছে"),{timeout:30000});if(!allowError)assert.notEqual(await page.locator("#b01-status").getAttribute("data-tone"),"error",await page.locator("#b01-status").innerText());};
   const login=async email=>{await page.goto(base+"/core10-build01.html",{waitUntil:"load"});await page.locator("#b01-email").fill(email);await page.locator("#b01-password").fill(password);await submit("#b01-login-form");await ready();assert.equal(await page.locator("#b01-password").inputValue(),"");};
   const signout=async()=>{await page.locator("#b01-signout").click();await page.locator("#b01-login").waitFor({state:"visible"});assert.equal(await page.locator("#b01-workspace").isVisible(),false);assert.equal(await page.locator("#b01-current-access tr").count(),0);for(const id of["#b01-email","#b01-password","#b01-subject","#b01-name","#b01-site-name"])assert.equal(await page.locator(id).inputValue(),"","signout clears "+id);};
   const okay=async label=>{assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth-innerWidth)<=2,label+" overflow "+width);assert.deepEqual(errors,[],label+" page errors");};
   await login(ownerEmail);await page.locator("#b01-language").click();assert.equal(await page.locator("html").getAttribute("lang"),"en");
   const suffix=width+"-"+Date.now(),slug="build01-ui-"+suffix;
   await page.locator("#b01-name").fill("Synthetic Build 01 "+suffix);
   await page.locator("#b01-slug").fill(slug);
   await page.locator("#b01-template").selectOption("food_manufacturing");
   await submit("#b01-setup-form");
   assert.match(await page.locator("#b01-setup-result").innerText(),/draft created: #\d+/);
   const business=await page.locator("#b01-business").inputValue();
   assert.ok(Number(business)>0);
   // Same form/request is replayed; the canonical business identity stays the same.
   await submit("#b01-setup-form");assert.equal(await page.locator("#b01-business").inputValue(),business);
   await page.locator("#b01-name").fill("Synthetic Advanced "+suffix);await page.locator("#b01-slug").fill("advanced-"+slug);await page.locator("#b01-mode").selectOption("advanced");
   await page.locator("#b01-sites").fill("not a valid manifest");await submit("#b01-setup-form",true);assert.match(await page.locator("#b01-status").innerText(),/INVALID_SITE_MANIFEST/);
   await page.locator("#b01-sites").fill("factory | Demo Factory\nwarehouse | Demo Advanced Store");await submit("#b01-setup-form");assert.notEqual(await page.locator("#b01-business").inputValue(),business);assert.equal(await page.locator("#b01-site option").count(),2,"Advanced uses same engine with explicit two-site manifest");
   await page.locator("#b01-business").selectOption(business);await ready();
   await page.locator("#b01-site-kind").selectOption("warehouse");await page.locator("#b01-site-name").fill("Synthetic Build 01 Warehouse");await submit("#b01-site-form");
   assert.match(await page.locator("#b01-site-result").innerText(),/site created: #\d+/);
   const sites=await page.locator("#b01-site option").evaluateAll(rows=>rows.map(x=>({id:x.value,label:x.textContent})));
   const site=sites.find(x=>x.label.includes("Synthetic Build 01 Warehouse"));assert(site);
   await page.locator("#b01-site").selectOption(site.id);
   await page.locator("#b01-subject").fill(subject);await page.locator("#b01-command").selectOption("site_grant.grant");await page.locator("#b01-allow-post").check();await submit("#b01-access-form");
   assert.match(await page.locator("#b01-current-access").innerText(),/44444444[\s\S]*stock\.post/);
   assert.match(await page.locator("#b01-audit").innerText(),/site_grant\.grant/);
   await okay("owner setup/grant");await page.screenshot({path:path.join(shots,"build01-owner-"+width+".png"),fullPage:true});
   await signout();await login(staffEmail);await page.locator("#b01-business").selectOption(business);await ready();await page.locator("#b01-site").selectOption(site.id);
   assert.equal(await page.locator('#b01-access-form button[type="submit"]').isDisabled(),true,"staff cannot administer access");
   await page.locator("#b01-inspect-action").selectOption("stock.post");await submit("#b01-effective-form");assert.match(await page.locator("#b01-effective-result").innerText(),/"allowed": true/);
   await signout();await login(ownerEmail);await page.locator("#b01-business").selectOption(business);await ready();await page.locator("#b01-site").selectOption(site.id);
   await page.locator("#b01-subject").fill(subject);await page.locator("#b01-command").selectOption("site_grant.grant");await page.locator("#b01-allow-post").check();await page.locator("#b01-deny-post").check();await submit("#b01-access-form");
   await signout();await login(staffEmail);await page.locator("#b01-business").selectOption(business);await ready();await page.locator("#b01-site").selectOption(site.id);await page.locator("#b01-inspect-action").selectOption("stock.post");await submit("#b01-effective-form");assert.match(await page.locator("#b01-effective-result").innerText(),/"allowed": false/);
   await okay("staff denied action");await page.screenshot({path:path.join(shots,"build01-staff-deny-"+width+".png"),fullPage:true});
   await signout();await login(ownerEmail);await page.locator("#b01-business").selectOption(business);await ready();await page.locator("#b01-site").selectOption(site.id);await page.locator("#b01-subject").fill(subject);await page.locator("#b01-command").selectOption("site_grant.revoke");await submit("#b01-access-form");assert.match(await page.locator("#b01-audit").innerText(),/site_grant\.revoke/);
   await signout();await login(staffEmail);assert.equal(await page.locator('#b01-business option[value="'+business+'"]').count(),0,"revoked staff no longer sees the created business");
   await okay("revocation");assert.deepEqual(external,[],"no external browser services");await page.close();
   console.log("PASS Build 01 real GoTrue/PG browser "+width+"px: login, Quick/Advanced setup/replay, canonical site, grant, effective allow, explicit deny, revoke, audit and signout");
  }
 }finally{await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
