"use strict";
const assert=require("node:assert/strict");
const {create,createMemoryStore,createEncryptedIndexedDBStore}=require("../core10-offline-drafts.js");
async function denied(fn,code){await assert.rejects(Promise.resolve().then(fn),
 e=>e&&e.code===code)}
const userA="11111111-1111-4111-8111-111111111111";
const userB="77777777-7777-4777-8777-777777777777";
let signedIn=userA;
const client={auth:{getUser:async()=>({data:{user:{id:signedIn}},error:null})}};
const server=new Map();
let attempts=0,oneNetworkFailure=true,conflicts=false,deniedNext=false;
const bridge={
 status:()=>({draftsEnabled:true,productionCertified:false}),
 async productionDraft(x){
  attempts++;
  if(conflicts){const e=new Error("idempotency_key_payload_conflict");e.code="P0001";throw e}
  if(deniedNext){const e=new Error("forbidden");e.code="42501";throw e}
  if(!server.has(x.requestKey))server.set(x.requestKey,200+server.size);
  if(oneNetworkFailure){oneNetworkFailure=false;const e=new Error("connection reset");
    e.code="NETWORK_OR_UNKNOWN";throw e}
  return server.get(x.requestKey);
 },
 async operationalDraft(x){
  attempts++;if(!server.has(x.requestKey))server.set(x.requestKey,200+server.size);
  return server.get(x.requestKey);
 },
 async postOperation(){throw Error("offline should NEVER call server posting")}
};
let serial=0;
const ids=()=>String(++serial);
const prod={bomId:1,locationId:5001,multiplier:2,requestKey:"offline-prod-001"};
(async()=>{
 const off=create({client,bridge,newRequestKey:ids});
 assert.equal(off.status().enabled,false);
 await denied(()=>off.enqueue("productionDraft",prod,userA),"OFFLINE_DRAFT_QUEUE_NOT_RELEASED");
 await denied(()=>off.sync(),"OFFLINE_DRAFT_QUEUE_NOT_RELEASED");
 assert.equal(attempts,0,"default disabled queue sent a request");
 const storage=createMemoryStore();
 const q=create({client,bridge,storage,newRequestKey:ids,experimentalDraftQueue:true});
 assert.equal(q.status().autoSync,false);
 assert.equal(q.status().stockPostingEnabled,false);
 assert.equal(q.status().paymentPostingEnabled,false);
 assert.equal(q.status().persistence,"injected");
 await denied(()=>q.enqueue("postProduction",{...prod},userA),"UNSAFE_OFFLINE_OPERATION");
 await denied(()=>q.enqueue("recordFundingPayment",{...prod},userA),"UNSAFE_OFFLINE_OPERATION");
 await denied(()=>q.enqueue("operationalDraft",{
  businessId:101,locationId:5001,kind:"sale",counterparty:"X",
  lines:[],discount:0,requestKey:"bad"},userA),"INVALID_OFFLINE_DRAFT");
 const local=await q.enqueue("productionDraft",prod,userA);
 assert.equal(local,"1");
 assert.equal(await q.enqueue("productionDraft",prod,userA),local);
 await denied(()=>q.enqueue("productionDraft",{...prod,multiplier:3},userA),
  "OFFLINE_IDEMPOTENCY_CONFLICT");
 assert.equal(attempts,0,"enqueue cannot post without manual sync");
 const first=await q.sync();
 assert.equal(first.remaining,1,"ambiguous network response must retain queued idempotency key");
 assert.equal((await q.load())[0].status,"pending");
 assert.equal(attempts,1);
 const next=await q.sync();
 assert.equal(next.remaining,0);
 assert.equal(attempts,2);
 assert.equal(server.size,1,"network timeout retry duplicated remote draft");
 assert.equal((await q.load())[0].serverId,200);
 await denied(()=>q.discard(local),"CANNOT_DISCARD_APPLIED_SERVER_DRAFT");

 const op={businessId:101,locationId:5001,kind:"sale",
  counterparty:"Customer Demo",lines:[{item:8001,quantity:1,unit_price:100}],
  discount:0,requestKey:"offline-sale-001"};
 const opId=await q.enqueue("operationalDraft",op,userA);
 assert.equal(opId,"2");
 const snap=await q.load();snap[1].payload.discount=999;
 assert.equal((await q.load())[1].payload.discount,0,"store exposed mutable queue references");
 signedIn=userB;
 const other=await q.sync();
 assert.equal(other.remaining,1);
 assert.equal(attempts,2,"wrong authenticated user replayed sensitive client request");
 assert.equal((await q.load())[1].status,"pending");
 signedIn=userA;
 assert.equal((await q.sync()).remaining,0);
 assert.equal(server.get(op.requestKey),201);
 assert.equal(attempts,3);

 conflicts=true;
 const conflictLocal=await q.enqueue("productionDraft",{
  ...prod,requestKey:"offline-conflict"},userA);
 await q.sync();
 assert.equal((await q.load()).find(x=>x.localId===conflictLocal).status,"conflict");
 const before=attempts;
 await q.sync();
 assert.equal(attempts,before,"conflict auto-retried without user decision");
 assert.equal(await q.discard(conflictLocal),true);
 conflicts=false;
 deniedNext=true;
 const unauthorizedId=await q.enqueue("productionDraft",{
  ...prod,requestKey:"offline-unauthorized"},userA);
 await q.sync();
 assert.equal((await q.load()).find(x=>x.localId===unauthorizedId).status,"unauthorized");
 deniedNext=false;
 assert.equal(await q.discard(unauthorizedId),true);

 const noBridge=create({client,bridge:{status:()=>({draftsEnabled:false})},
  storage:createMemoryStore(),newRequestKey:ids,experimentalDraftQueue:true});
 await denied(()=>noBridge.sync(),"OFFLINE_DRAFT_BRIDGE_NOT_RELEASED");
 const badStore=create({client,bridge,storage:{load:async()=>[],save:async()=>{}},
  experimentalDraftQueue:true});
 await denied(()=>badStore.enqueue("productionDraft",{
  ...prod,requestKey:"missing-key"},userA),"OFFLINE_UNIQUE_KEY_PROVIDER_REQUIRED");

 let release;
 const parallelBridge={status:()=>({draftsEnabled:true,productionCertified:false}),
  productionDraft:async()=>new Promise(res=>{release=res})};
 const parallelQ=create({client,bridge:parallelBridge,
  experimentalDraftQueue:true,newRequestKey:ids,storage:createMemoryStore()});
 await parallelQ.enqueue("productionDraft",{...prod,requestKey:"parallel-same-key"},userA);
 const active=parallelQ.sync();
 for(let i=0;i<10&&!release;i++)await Promise.resolve();
 assert.equal(typeof release,"function");
 await denied(()=>parallelQ.sync(),"OFFLINE_SYNC_ALREADY_RUNNING");
 release(600);
 assert.equal((await active).remaining,0);

 await denied(()=>Promise.resolve(createEncryptedIndexedDBStore({})),"ENCRYPTED_STORAGE_KEY_AND_BROWSER_REQUIRED");
 console.log("PASS: offline drafts opt-in only, user identity binding, manual sync, same-key unknown-outcome retry, no stock/finance posting, conflict and unauthorized quarantine, encrypted-store prerequisites.");
})().catch(e=>{console.error(e);process.exitCode=1});
