import test from "node:test";
import assert from "node:assert/strict";
import worker from "../preview/worker.mjs";
import { createI18n, DEFAULT_LOCALE, SUPPORTED_LOCALES, PHRASES, NAMED_MESSAGES, BROWSER_I18N_JS } from "../preview/i18n.mjs";

const req = (path,method="GET") => new Request("https://preview.c10.invalid"+path,{method});

test("C10-A064: bn-BD is canonical default; English is explicit and resettable",()=>{
  assert.equal(DEFAULT_LOCALE,"bn-BD");
  assert.deepEqual(SUPPORTED_LOCALES,["bn-BD","en"]);
  const i18n=createI18n();
  assert.equal(i18n.locale,"bn-BD");
  assert.equal(i18n.t("nav.overview"),"এক নজরে");
  assert.equal(i18n.t("common.approval"),"Approval (অনুমোদনের ধাপ)");
  assert.equal(i18n.setLocale("en"),true);
  assert.equal(i18n.t("nav.overview"),"Overview");
  assert.equal(i18n.t("common.language"),"Language");
  assert.equal(i18n.setLocale("fr"),false);
  assert.equal(i18n.locale,"en");
  assert.equal(i18n.setLocale("bn-BD"),true);
  assert.equal(i18n.t("common.stock"),"স্টক");
  assert.throws(()=>i18n.t("unreviewed.copy"),/UNKNOWN_UI_COPY_KEY/);
  assert.equal(createI18n("xx").locale,"bn-BD");
});

test("C10-A064: reviewed catalog has paired UI copy and no difficult literal Bangla",()=>{
  assert.ok(PHRASES.length>=200);
  const keys=new Set();
  for(const [en,bn] of PHRASES){
    assert.equal(typeof en,"string");assert.equal(typeof bn,"string");
    assert.ok(en.trim()&&bn.trim());
    assert.equal(keys.has(en),false,"duplicate key "+en);keys.add(en);
  }
  for(const [key,pair] of Object.entries(NAMED_MESSAGES)){
    assert.match(key,/^[a-z]+\.[a-zA-Z][\w]*$/);
    assert.equal(pair.length,2);assert.ok(pair.every(v=>typeof v==="string"&&v.trim()));
  }
  const forbidden=/কার্যপরিকল্পনা|সমন্বিত তথ্যফলক|বিন্যাস-সমন্বয়|উৎপাদন-উপকেন্দ্র|অনুমোদন-প্রক্রিয়াকরণ|পণ্য-মজুদ ব্যবস্থাপনা/;
  for(const [,bn] of PHRASES)assert.doesNotMatch(bn,forbidden);
  for(const [,bn] of Object.values(NAMED_MESSAGES))assert.doesNotMatch(bn,forbidden);
});

test("C10-A064: both covered Preview pages load same-origin local-only language engine",async()=>{
  for(const path of ["/","/build01-build02a.html"]){
    const r=await worker.fetch(req(path)),h=await r.text();
    assert.equal(r.status,200);
    assert.match(r.headers.get("content-security-policy"),/connect-src 'none'/);
    assert.match(h,/<html lang="bn-BD">/);
    assert.match(h,/src="\/preview-i18n\.js" defer/);
    assert.match(h,/id="c10-language"/);
    assert.match(h,/data-i18n="common.language"/);
    assert.match(h,/value="bn-BD"/);
    assert.match(h,/value="en"/);
  }
  const out=await worker.fetch(req("/preview-i18n.js"));
  assert.equal(out.status,200);
  assert.match(out.headers.get("content-type"),/javascript/);
  const js=await out.text();
  assert.match(js,/let locale="bn-BD"/);
  for(const forbidden of [/fetch\s*\(/,/XMLHttpRequest/,/localStorage/,/sessionStorage/,/sendBeacon/,/\/api\//])assert.doesNotMatch(js,forbidden);
  assert.match(js,/setLocale/);
  assert.match(BROWSER_I18N_JS,/data-i18n/);
});

test("C10-A064: no network request or state mutation required by local preview and walkthrough routes",async()=>{
  const old=globalThis.fetch;
  let count=0;
  globalThis.fetch=async()=>{count++;throw Error("unexpected upstream request")};
  try{
    for(const path of ["/","/preview.js","/preview.css","/preview-i18n.js","/build01-build02a.html","/build01-build02a.css","/build01-build02a.js"]){
      assert.equal((await worker.fetch(req(path))).status,200,path);
      assert.equal((await worker.fetch(req(path,"HEAD"))).status,200,path+" HEAD");
    }
    assert.equal(count,0);
    for(const method of ["POST","PATCH","PUT","DELETE"]){
      assert.equal((await worker.fetch(req("/build01-build02a.html",method))).status,405);
      assert.equal((await worker.fetch(req("/preview-i18n.js",method))).status,405);
    }
    for(const path of ["/api/translate","/api/login","/api/permissions","/i18n/save","/internal/enterprise-sql/c10_build01_access_integration_v1.sql"]){
      assert.equal((await worker.fetch(req(path))).status,404,path);
    }
  }finally{globalThis.fetch=old;}
  const mainJS=await (await worker.fetch(req("/preview.js"))).text();
  const buildJS=await (await worker.fetch(req("/build01-build02a.js"))).text();
  for(const js of [mainJS,buildJS]){
    assert.doesNotMatch(js,/fetch\s*\(|\.rpc\s*\(|supabase|localStorage|sessionStorage|XMLHttpRequest/);
    assert.match(js,/window\.C10I18N/);
  }
});
