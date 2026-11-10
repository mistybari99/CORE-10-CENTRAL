"use strict";
const {test}=require("node:test"),assert=require("node:assert/strict");
const api=require("../../offline/core10-offline-outbox-v1.js");
function mem(){
 const map=new Map();
 return{all:async()=>Array.from(map.values()),put:async r=>{map.set(r.localKey,{...r})}};
}
const base={businessId:101,locationId:5001,itemId:8001,delta:-2,expectedLedgerVersion:9};
test("validates stock quantity and ledger version and forbids silent invalid states",()=>{
 assert.deepEqual(api.validate(base),base);
 for(const bad of [{...base,delta:0},{...base,delta:1.00001},
  {...base,expectedLedgerVersion:-1},{...base,itemId:0},{...base,delta:Infinity}])
  assert.throws(()=>api.validate(bad),{code:"INVALID_OFFLINE_EVENT"});
});
test("offline draft stays queued until explicit flush, then exactly once receipt",async()=>{
 const store=mem();let n=0, sent=0;
 const q=api.create({storage:store,getSubject:async()=> "user-one",
  randomUUID:()=>("00000000-0000-4000-8000-"+String(++n).padStart(12,"0")),
  send:async p=>{sent++;return{id:30,request_key:p.p_request,status:"staged"}}});
 const draft=await q.enqueue(base);
 assert.equal(draft.status,"queued");assert.equal(sent,0);
 assert.equal((await q.list()).length,1);
 assert.deepEqual(await q.flush(),{staged:1,conflicts:0,retryable:0});
 assert.equal((await q.list())[0].status,"staged");
 await q.flush();assert.equal(sent,1);
 assert.equal(q.status().automaticReplay,false);
 assert.equal(q.status().stockPostingEnabled,false);
});
test("stale ledger conflict is quarantined and requires new explicit event",async()=>{
 let n=0,sendCount=0;const q=api.create({
 storage:mem(),getSubject:async()=> "user-two",
 randomUUID:()=>("00000000-0000-4000-8000-"+String(++n).padStart(12,"0")),
 send:async p=>{sendCount++;return{id:50,request_key:p.p_request,
  status:"conflict",conflict_reason:"stale_ledger_version"}}
 });
 await q.enqueue(base);
 assert.deepEqual(await q.flush(),{staged:0,conflicts:1,retryable:0});
 assert.equal((await q.list())[0].lastError,"stale_ledger_version");
 await q.flush();assert.equal(sendCount,1);
});
test("network outage keeps same request key for authenticated retry",async()=>{
 let fail=true,n=0,last;
 const q=api.create({storage:mem(),getSubject:async()=> "user-three",
 randomUUID:()=>("00000000-0000-4000-8000-"+String(++n).padStart(12,"0")),
 send:async p=>{last=p.p_request;if(fail)throw Error("offline");return{id:999,
  status:"staged",request_key:p.p_request}}
 });
 const before=await q.enqueue(base);
 assert.deepEqual(await q.flush(),{staged:0,conflicts:0,retryable:1});
 assert.equal((await q.list())[0].status,"queued");
 fail=false;
 assert.deepEqual(await q.flush(),{staged:1,conflicts:0,retryable:0});
 assert.equal(before.requestKey,last);
});
test("rejects fake server reply instead of treating it as applied",async()=>{
 let n=0;
 const q=api.create({storage:mem(),getSubject:async()=> "user-four",
 randomUUID:()=>("00000000-0000-4000-8000-"+String(++n).padStart(12,"0")),
 send:async()=>({id:8,status:"staged",request_key:"different-key"})
 });
 await q.enqueue(base);
 await assert.rejects(q.flush(),{code:"UNVERIFIED_SERVER_RECEIPT"});
 assert.equal((await q.list())[0].status,"queued");
});
test("outbox isolation: signed-in identity changes block reading old subject drafts",async()=>{
 let who="user-a",n=0;
 const q=api.create({storage:mem(),getSubject:async()=>who,
 randomUUID:()=>("00000000-0000-4000-8000-"+String(++n).padStart(12,"0")),
 send:async()=>{throw Error("no network")}
 });
 await q.enqueue(base);
 who="user-b";
 assert.equal((await q.list()).length,0);
 await q.enqueue({...base,delta:4});
 assert.equal((await q.list()).length,1);
 who="user-a";
 assert.equal((await q.list()).length,1);
});
test("no signed session or insecure nonce can enqueue",async()=>{
 const q=api.create({storage:mem(),getSubject:async()=>null,
 randomUUID:()=> "random-nonce",send:async()=>({})});
 await assert.rejects(q.enqueue(base),{code:"AUTHENTICATED_SUBJECT_REQUIRED"});
 const q2=api.create({storage:mem(),getSubject:async()=> "u",
 randomUUID:()=> "1",send:async()=>({})});
 await assert.rejects(q2.enqueue(base),{code:"SECURE_RANDOM_KEY_REQUIRED"});
});
