"use strict";
const assert=require("node:assert/strict");
const test=require("node:test");
const h=require("../core10-site-hierarchy.js");
test("canonical IDs reject malformed or unsafe values",()=>{
 assert.equal(h.id("001"),null);assert.equal(h.id("1e2"),null);
 assert.equal(h.id(Number.MAX_SAFE_INTEGER+1),null);assert.equal(h.id("12"),12);
});
test("one operating site can hold multiple stock locations",()=>{
 const r=h.reconcile([{id:7,business_id:2,kind:"factory"}],
 [{id:10,business_id:2,site_id:7},{id:11,business_id:2,site_id:7}],2);
 assert.equal(r.ok,true);assert.equal(r.unmapped,0);assert.equal(r.mappings.length,2);
});
test("unmapped legacy stock location is preserved, not guessed",()=>{
 const r=h.reconcile([],[{id:10,business_id:2,site_id:null}],2);
 assert.equal(r.ok,true);assert.equal(r.unmapped,1);assert.equal(r.mappings[0].site_id,null);
});
test("cross-business references and unknown sites fail closed",()=>{
 assert.equal(h.reconcile([{id:7,business_id:3,kind:"factory"}],[],2).ok,false);
 assert.equal(h.reconcile([{id:7,business_id:2,kind:"factory"}],[{id:10,business_id:2,site_id:8}],2).reason,"unverified_site_mapping");
 assert.equal(h.reconcile([],[{id:10,business_id:3,site_id:null}],2).ok,false);
});
test("duplicate site/location IDs are rejected",()=>{
 const s={id:7,business_id:2,kind:"showroom"};
 assert.equal(h.reconcile([s,s],[],2).ok,false);
 const l={id:10,business_id:2,site_id:null};
 assert.equal(h.reconcile([],[l,l],2).ok,false);
});
