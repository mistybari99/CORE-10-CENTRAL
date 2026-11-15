"use strict";
/* PACK-02 S2 host journey: real Chromium -> PACK-02 signed adapter -> REAL
 * PACK-02/Build01 SQL in a disposable PostgreSQL (one psql call per RPC, actor
 * set as a synthetic claim). No mocked projections. NOT GoTrue: token issue,
 * signature and logout are Build01/PACK-01 concerns proven by their own suite. */
const assert=require("node:assert/strict"),fs=require("node:fs"),path=require("node:path"),{execFileSync}=require("node:child_process");
const {chromium}=require("playwright");
const root=path.join(__dirname,"../..");
if(!/^core10_(preview_pack02|a048_local_pack02)_\d+$/.test(process.env.PGDATABASE||"")||!["127.0.0.1","localhost"].includes(process.env.PGHOST||""))throw Error("DISPOSABLE_PACK02_DATABASE_REQUIRED");
const SQL={
 build01_context_v1:"SELECT c10_demo.build01_context_v1()",
 pack02_workspace_v1:"SELECT c10_demo.pack02_workspace_v1(:'p_mode',NULLIF(:'p_business','')::bigint)",
 pack02_controls_v1:"SELECT c10_demo.pack02_controls_v1(:'p_surface',NULLIF(:'p_business','')::bigint)",
 pack02_business_report_v1:"SELECT c10_demo.pack02_business_report_v1(NULLIF(:'p_business','')::bigint)",
 pack02_owner_report_v1:"SELECT c10_demo.pack02_owner_report_v1()"};
function pg(uid,name,args){
 if(!SQL[name])throw Object.assign(Error("TEST_RPC_UNKNOWN"),{code:"TEST_RPC_UNKNOWN"});
 const v=[];for(const k of ["p_mode","p_business","p_surface"])v.push("-v",k+"="+(args&&args[k]!=null?String(args[k]):""));
 const script=`SET ROLE authenticated;\nSELECT set_config('request.jwt.claim.sub','${uid}',false);\n${SQL[name]};\n`;
 try{
  const out=execFileSync("psql",["-X","-A","-t","-q","-v","ON_ERROR_STOP=1",...v],{input:script,encoding:"utf8",stdio:["pipe","pipe","pipe"]});
  return JSON.parse(out.trim().split("\n").pop());
 }catch(e){
  const m=/ERROR:\s+(\S+)/.exec(String(e.stderr||""));throw Object.assign(Error(m?m[1]:"TEST_PSQL_FAILED"),{code:m?m[1]:"TEST_PSQL_FAILED"});
 }
}
const read=f=>fs.readFileSync(path.join(root,f),"utf8");
const html=`<!doctype html><html lang="bn"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><style>${read("core10-pack02-workspace.css")}</style></head><body style="margin:0"><div id="host"></div><script>${["core10-pack02-workspace.js","core10-pack02-controls.js","core10-pack02-signed.js","core10-pack02-app.js"].map(read).join(";\n")}</script></body></html>`;
const OWNER="11111111-1111-4111-8111-111111111111",BIZ="22222222-2222-4222-8222-222222222222",STAFF="44444444-4444-4444-8444-444444444444",OPERATOR="99999999-9999-4999-8999-999999999999";
// Owner-configured control placement through the canonical A044 writer.
execFileSync("psql",["-X","-q","-v","ON_ERROR_STOP=1"],{input:`SET ROLE authenticated;SELECT set_config('request.jwt.claim.sub','${OWNER}',false);
SELECT c10_demo.write_control_setting_v1(101,'inventory.count','both','business_owner',true,0,'p2app_both_0001','PACK-02 app journey');
SELECT c10_demo.write_control_setting_v1(101,'finance.payments','hidden_from_menus','central_only',false,0,'p2app_hidden_01','PACK-02 app journey');`,stdio:["pipe","ignore","inherit"]});
(async()=>{
 const browser=await chromium.launch(process.env.CORE10_CHROMIUM_PATH?{executablePath:process.env.CORE10_CHROMIUM_PATH}:{});
 async function open(uid,width,forged){
  const page=await browser.newPage({viewport:{width,height:900}});
  const errors=[],calls=[];page.on("pageerror",e=>errors.push(e.message));
  await page.exposeFunction("pgRpc",(name,args)=>{calls.push(name);try{return {ok:pg(uid,name,args)};}catch(e){return {err:e.code};}});
  await page.setContent(html,{waitUntil:"load"});
  const context=forged||pg(uid,"build01_context_v1");
  await page.evaluate(async ctx=>{
   const signed=window.CORE10_PACK02_SIGNED.fromRpc(async(n,a)=>{const r=await window.pgRpc(n,a);if(r.err){const e=new Error(r.err);e.code=r.err;throw e;}return r.ok;});
   window.app=window.CORE10_PACK02_APP.mount(document.getElementById("host"),{rpc:signed.rpc,context:ctx});await window.app.ready;
  },context);
  const snap=()=>page.evaluate(()=>({text:document.body.innerText,title:document.querySelector(".p2-title")?.textContent||"",
   pickHidden:document.querySelector(".p2-pick").hidden,options:document.querySelectorAll(".p2-pick option").length,
   live:[...document.querySelectorAll(".p2-nav-item:not([disabled])")].map(b=>b.dataset.key),
   cards:document.querySelectorAll(".p2-panel .p2-card").length,status:document.querySelector(".p2-status").textContent,
   overflow:document.documentElement.scrollWidth>document.documentElement.clientWidth}));
  const click=async key=>{await page.click(`.p2-nav-item[data-key="${key}"]`);await page.waitForFunction(()=>document.querySelector(".p2-panel").childElementCount>0||document.querySelector(".p2-status").textContent,{timeout:10000});};
  const choose=async i=>{await page.selectOption(".p2-pick",String(i));await page.waitForFunction(i=>document.querySelector(".p2-pick").value===String(i)&&document.querySelector(".p2-title"),i,{timeout:10000});await page.waitForTimeout(300);};
  return {page,errors,calls,snap,click,choose};
 }
 try{
  for(const width of [390,1440]){
   // Universal Owner: chooser, owner-wide report, then a business with its controls.
   let s=await open(OWNER,width),m=await s.snap();
   assert.equal(m.title,"CORE 10");assert.equal(m.options,3);assert.equal(m.pickHidden,false);assert.deepEqual(m.live,["owner.reports"]);assert.equal(m.overflow,false);
   await s.click("owner.reports");assert.equal((await s.snap()).cards,2);
   await s.choose(1);m=await s.snap();assert.equal(m.title,"demo-sweets");assert.deepEqual(m.live,["biz.reports","biz.controls"]);
   await s.click("biz.controls");m=await s.snap();assert.match(m.text,/স্টক গণনা/);assert.ok(!/পেমেন্ট/.test(m.text),"hidden control leaked");assert.equal(m.overflow,false);
   await s.click("biz.reports");assert.equal((await s.snap()).cards,2);assert.deepEqual(s.errors,[]);await s.page.close();
   // Delegated business owner: no chooser, no umbrella.
   s=await open(BIZ,width);m=await s.snap();
   assert.equal(m.pickHidden,true);assert.equal(m.title,"demo-sweets");assert.ok(!/CORE\s*10/i.test(m.text));
   await s.click("biz.controls");assert.equal((await s.snap()).cards,1);await s.page.close();
   // Staff: one site, own brand only, only the report is live; no control call possible.
   s=await open(STAFF,width);m=await s.snap();
   assert.equal(m.pickHidden,true);assert.deepEqual(m.live,["staff.reports"]);assert.ok(!/CORE\s*10|demo-second|A2\b/i.test(m.text));assert.equal(m.overflow,false);
   await s.click("staff.reports");m=await s.snap();assert.equal(m.cards,1);assert.ok(!s.calls.includes("pack02_controls_v1"));await s.page.close();
  }
  // Forged context: staff claims to be owner of 101 and of sister business 102 -> server denies, UI closes.
  let s=await open(STAFF,390,{businesses:[{id:101,label:"demo-sweets",can_manage:true},{id:102,label:"x",can_manage:true}],legal_entities:[{id:11}]});
  let m=await s.snap();assert.match(m.status,/অনুমতি নেই/);assert.equal(m.title,"");assert.ok(s.calls.includes("pack02_workspace_v1"));
  await s.choose(1).catch(()=>{});await s.page.waitForTimeout(400);m=await s.snap();assert.equal(m.title,"");assert.match(m.status,/অনুমতি নেই/);
  await s.choose(2).catch(()=>{});await s.page.waitForTimeout(400);m=await s.snap();assert.equal(m.title,"");
  // Disallowed RPC name never leaves the page.
  const code=await s.page.evaluate(async()=>{try{await window.CORE10_PACK02_SIGNED.fromRpc(window.pgRpc).rpc("build01_set_access_v1",{});return "CALLED";}catch(e){return e.code;}});
  assert.equal(code,"PACK02_RPC_NOT_ALLOWED");assert.ok(!s.calls.includes("build01_set_access_v1"));await s.page.close();
  // Unrelated operator: nothing offered.
  s=await open(OPERATOR,390);m=await s.snap();assert.match(m.status,/অনুমতি নেই/);assert.equal(m.options,0);
  // reset() after sign-out clears everything.
  await s.page.close();s=await open(OWNER,390);await s.page.evaluate(()=>window.app.reset());m=await s.snap();assert.equal(m.title,"");assert.equal(m.options,0);
  console.log("PASS PACK-02 app host journey 390px/1440px over REAL disposable SQL: owner, business owner, staff, forged context, operator, reset (synthetic claims, not GoTrue)");
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exit(1);});
