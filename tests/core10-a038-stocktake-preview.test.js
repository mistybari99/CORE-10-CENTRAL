"use strict";
const assert=require("node:assert/strict");
const fs=require("node:fs"),path=require("node:path");
const {createDemo,validateCounts,escape}=require("../core10-stocktake-preview.js");
function throws(fn,code){assert.throws(fn,e=>e&&e.code===code);}
function item(doc,id){return doc.lines.find(x=>x.itemId===id)}
{
 const m=createDemo();
 const starting=m.snapshot();
 assert.equal(starting.role,"staff");assert.equal(starting.docs.length,3);
 assert.equal(starting.docs.filter(x=>x.status==="submitted").length,1);
 throws(()=>m.approve(4101),"OWNER_REVIEW_REQUIRED");
 throws(()=>m.post(4102),"OWNER_REVIEW_REQUIRED");
 throws(()=>m.submit(5001,[{itemId:8001,counted:-1}]),"INVALID_COUNT_QUANTITY");
 throws(()=>m.submit(5001,[{itemId:8001,counted:"1.2345"}]),"INVALID_COUNT_QUANTITY");
 throws(()=>m.submit(5001,[{itemId:8001,counted:10},{itemId:8001,counted:11}]),"INVALID_COUNT_MANIFEST");
 throws(()=>m.submit(5001,[{itemId:9001,counted:10}]),"INVALID_COUNT_MANIFEST");
 throws(()=>m.submit(9999,[{itemId:8001,counted:10}]),"UNKNOWN_DEMO_SITE");
 throws(()=>m.submit(5001,[{itemId:8001,counted:Infinity}]),"INVALID_COUNT_QUANTITY");
 const id=m.submit(5001,[
  {itemId:8001,counted:231.5},{itemId:8002,counted:28},{itemId:8003,counted:58}]);
 assert.equal(id,4104);const doc=m.snapshot().docs.find(x=>x.id===id);
 assert.equal(doc.status,"submitted");
 assert.equal(item(doc,8001).expected,240);
 assert.equal(m.snapshot().stock[5001][8001],240,"submitted count never posts stock");
 throws(()=>m.post(id),"OWNER_REVIEW_REQUIRED");
 m.setRole("owner");throws(()=>m.submit(5001,[{itemId:8001,counted:2}]),"STAFF_COUNT_REQUIRED");
 m.approve(id);assert.equal(m.snapshot().docs.find(x=>x.id===id).status,"approved");
 m.post(id);
 const s=m.snapshot();
 assert.equal(s.stock[5001][8001],231.5);
 assert.equal(s.stock[5001][8003],58);
 assert.equal(s.docs.find(x=>x.id===id).status,"posted");
 assert.deepEqual(s.audit.filter(x=>x.docId===id).map(x=>x.kind),
  ["draft","submitted","approved","posted"]);
 throws(()=>m.post(id),"COUNT_NOT_APPROVED");
 throws(()=>m.voidCount(id,"delete record"),"POSTED_STOCKTAKE_IMMUTABLE");
 const before=m.snapshot();before.stock[5001][8001]=999999;
 assert.equal(m.snapshot().stock[5001][8001],231.5,"snapshot must be a defensive copy");
}
{
 const m=createDemo();m.setRole("staff");
 const id=m.submit(5002,[{itemId:8002,counted:41}]);
 m.setRole("owner");m.approve(id);
 m.simulateMovement(5002,8002,-1);
 throws(()=>m.post(id),"STALE_COUNT_RECOUNT_REQUIRED");
 const after=m.snapshot();assert.equal(after.stock[5002][8002],41);
 assert.equal(after.docs.find(x=>x.id===id).status,"approved");
 throws(()=>m.voidCount(id,"bad"),"VOID_REASON_REQUIRED");
 m.voidCount(id,"Site changed after count, recount required");
 assert.equal(m.snapshot().docs.find(x=>x.id===id).status,"voided");
 throws(()=>m.post(id),"COUNT_NOT_APPROVED");
 throws(()=>m.setRole("untrusted"),"INVALID_DEMO_ROLE");
 throws(()=>m.setScreen("__proto__"),"INVALID_DEMO_SCREEN");
 throws(()=>m.setFilter("__proto__"),"INVALID_DEMO_FILTER");
}
assert.deepEqual(validateCounts(5001,[{itemId:8001,counted:"1.125"}]).lines,
 [{itemId:8001,counted:1.125}]);
assert.equal(escape('<img src=x onerror=alert(1)>'),"&lt;img src=x onerror=alert(1)&gt;");
const html=fs.readFileSync(path.resolve(__dirname,"../core10-stocktake-preview.html"),"utf8");
const css=fs.readFileSync(path.resolve(__dirname,"../core10-stocktake-preview.css"),"utf8");
const browser=fs.readFileSync(path.resolve(__dirname,"../core10-stocktake-preview.js"),"utf8");
assert.match(html,/DEMO DATA — NO ERP CHANGES/);
assert.match(html,/core10-enterprise-client\.js/);
assert.match(html,/core10-stocktake-preview\.js/);
assert.match(html,/data-role="owner"/);
assert.match(css,/@media\(max-width:730px\)/,"mobile layout must be supported");
assert.match(browser,/STAGING_WRITES_LOCKED/);
assert.match(browser,/kbuhnpqooycqbzrfejcs/,"do not connect to legacy production ref");
assert.ok(!browser.includes("localStorage")&&!browser.includes("sessionStorage"),
 "demo stock counts should not be persisted or mistakenly restored as real data");
console.log("PASS A038 synthetic Owner/Staff UI model: submit/approve/post/void, stale fail-closed, defensive copy, XSS escaping, mobile structure, no persistent/remote writes");
