/* CORE10 A032 — Offline-safe DRAFT queue prototype, not live-ready.
 * Never queues cash movement, stock POST, approvals, or investor payouts.
 * Manual sync only, signed current Supabase user required on replay,
 * RPC idempotency keys retained through unknown network outcomes.
 * Default store is VOLATILE memory; durable store requires explicit opt-in
 * and encryption in the host app. No default plaintext local storage.
 */
(function(root,factory){
 "use strict";
 var api=factory();
 if(typeof module==="object"&&module.exports)module.exports=api;
 if(root)root.CORE10_OFFLINE_DRAFTS=api;
})(typeof window!=="undefined"?window:(typeof globalThis!=="undefined"?globalThis:null),function(){
 "use strict";
 function fail(code){var e=new Error(code);e.code=code;throw e}
 function obj(v){return v!==null&&typeof v==="object"&&!Array.isArray(v)}
 function id(v){return typeof v==="number"&&Number.isSafeInteger(v)&&v>0}
 function text(v){return typeof v==="string"&&v.trim().length>0&&v.trim().length<=120}
 function copy(v){return JSON.parse(JSON.stringify(v))}
 function createMemoryStore(){
  var rows=[];
  return{async load(){return copy(rows)},async save(next){rows=copy(next)}};
 }
 // Must supply an authenticated user's per-session CryptoKey and browser storage.
 // IDB contains only encrypted snapshots; key provisioning and unlock UI are deferred.
 function createEncryptedIndexedDBStore(options){
  options=options||{};
  var idb=options.indexedDB,crypt=options.crypto,cryptoKey=options.cryptoKey;
  if(!idb||!crypt||!crypt.subtle||!crypt.getRandomValues||
   !cryptoKey||typeof cryptoKey!=="object"||!options.name||
   !/^[a-zA-Z0-9_-]{3,50}$/.test(options.name))
   fail("ENCRYPTED_STORAGE_KEY_AND_BROWSER_REQUIRED");
  async function db(){
   return new Promise(function(resolve,reject){
    var req=idb.open(options.name,1);
    req.onupgradeneeded=function(){if(!req.result.objectStoreNames.contains("state"))
      req.result.createObjectStore("state")};
    req.onsuccess=function(){resolve(req.result)};
    req.onerror=function(){reject(req.error||new Error("INDEXEDDB_OPEN_FAILED"))};
   });
  }
  async function store(method,value){
   var handle=await db();
   try{
    return await new Promise(function(resolve,reject){
     var tx=handle.transaction("state",method==="read"?"readonly":"readwrite");
     var objectStore=tx.objectStore("state");
     var req=method==="read"?objectStore.get("drafts"):objectStore.put(value,"drafts");
     req.onsuccess=function(){resolve(req.result)};
     req.onerror=function(){reject(req.error||new Error("INDEXEDDB_IO_FAILED"))};
     tx.onerror=function(){reject(tx.error||new Error("INDEXEDDB_TRANSACTION_FAILED"))};
    });
   }finally{handle.close()}
  }
  return {
   async load(){
    var encrypted=await store("read");
    if(!encrypted)return[];
    if(!obj(encrypted)||!Array.isArray(encrypted.iv)||!Array.isArray(encrypted.ciphertext))
     fail("ENCRYPTED_STORAGE_CORRUPT");
    try{
     var bytes=await crypt.subtle.decrypt({name:"AES-GCM",iv:new Uint8Array(encrypted.iv)},
       cryptoKey,new Uint8Array(encrypted.ciphertext));
     var parsed=JSON.parse(new TextDecoder().decode(bytes));
     if(!Array.isArray(parsed))fail("ENCRYPTED_STORAGE_CORRUPT");
     return parsed;
    }catch(_){fail("ENCRYPTED_STORAGE_UNREADABLE")}
   },
   async save(rows){
    if(!Array.isArray(rows))fail("INVALID_OFFLINE_RECORDS");
    var iv=new Uint8Array(12);
    crypt.getRandomValues(iv);
    var ciphertext=await crypt.subtle.encrypt({name:"AES-GCM",iv:iv},
     cryptoKey,new TextEncoder().encode(JSON.stringify(rows)));
    await store("write",{iv:Array.from(iv),ciphertext:Array.from(new Uint8Array(ciphertext))});
   }
  };
 }
 function create(params){
  params=params||{};
  var enabled=params.experimentalDraftQueue===true;
  var bridge=params.bridge,client=params.client,storage=params.storage||createMemoryStore();
  var makeKey=params.newRequestKey;
  var syncing=false;
  if(!storage||typeof storage.load!=="function"||typeof storage.save!=="function")
   fail("INVALID_OFFLINE_STORAGE");
  function guard(){if(!enabled)fail("OFFLINE_DRAFT_QUEUE_NOT_RELEASED")}
  function validate(operation,payload){
   if(!["productionDraft","operationalDraft"].includes(operation)||
     !obj(payload)||!text(payload.requestKey))fail("UNSAFE_OFFLINE_OPERATION");
   if(operation==="productionDraft"){
    if(!id(payload.bomId)||!id(payload.locationId)||
      typeof payload.multiplier!=="number"||!Number.isFinite(payload.multiplier)||
      payload.multiplier<=0||payload.multiplier>100000)fail("INVALID_OFFLINE_DRAFT");
    if(Object.keys(payload).sort().join(",")!=="bomId,locationId,multiplier,requestKey")
      fail("INVALID_OFFLINE_DRAFT");
   }else{
    if(!id(payload.businessId)||!id(payload.locationId)||
      !["sale","purchase"].includes(payload.kind)||!text(payload.counterparty)||
      !Array.isArray(payload.lines)||payload.lines.length<1||payload.lines.length>100||
      typeof payload.discount!=="number"||payload.discount<0)fail("INVALID_OFFLINE_DRAFT");
    if(Object.keys(payload).sort().join(",")!=="businessId,counterparty,discount,kind,lines,locationId,requestKey")
      fail("INVALID_OFFLINE_DRAFT");
   }
   return copy(payload);
  }
  async function load(){
   guard();var data=await storage.load();
   if(!Array.isArray(data)||data.length>500)fail("INVALID_OFFLINE_STORAGE");
   return copy(data);
  }
  async function enqueue(operation,payload,ownerUserId){
   guard();
   if(!text(ownerUserId))fail("OFFLINE_IDENTITY_REQUIRED");
   var body=validate(operation,payload),rows=await load();
   var match=rows.find(function(r){return r.operation===operation&&r.payload.requestKey===body.requestKey});
   if(match){
    if(match.ownerUserId!==ownerUserId||JSON.stringify(match.payload)!==JSON.stringify(body))
      fail("OFFLINE_IDEMPOTENCY_CONFLICT");
    return match.localId;
   }
   if(rows.length>=500)fail("OFFLINE_QUEUE_FULL");
   if(typeof makeKey!=="function")fail("OFFLINE_UNIQUE_KEY_PROVIDER_REQUIRED");
   var localId=makeKey();
   if(!text(localId)||rows.some(function(r){return r.localId===localId}))
    fail("OFFLINE_LOCAL_KEY_CONFLICT");
   rows.push({localId,ownerUserId,operation,payload:body,status:"pending",
     serverId:null,attempts:0,errorCode:null});
   await storage.save(rows);
   return localId;
  }
  async function sync(){
   guard();
   if(syncing)fail("OFFLINE_SYNC_ALREADY_RUNNING");
   if(!bridge||!client||!client.auth||typeof client.auth.getUser!=="function")
    fail("SIGNED_SESSION_AND_WORKFLOW_BRIDGE_REQUIRED");
   var auth=await client.auth.getUser();
   if(auth?.error||!text(auth?.data?.user?.id))fail("AUTHENTICATED_USER_REQUIRED");
   var who=auth.data.user.id;
   var flags=typeof bridge.status==="function"?bridge.status():null;
   if(!flags||!flags.draftsEnabled||flags.productionCertified===true)
    fail("OFFLINE_DRAFT_BRIDGE_NOT_RELEASED");
   syncing=true;
   try{
    var rows=await load(),done=0,blocked=0,pending=0;
    for(var row of rows){
     if(row.status==="applied"){done++;continue}
     if(row.status==="conflict"||row.status==="unauthorized"){blocked++;continue}
     if(row.ownerUserId!==who){blocked++;continue}
     var fn=bridge[row.operation];
     if(typeof fn!=="function")fail("UNSUPPORTED_OFFLINE_DRAFT");
     row.attempts++;
     try{
      // Manual sync may have committed remotely before a network timeout.
      // Retrying SAME server requestKey is therefore essential.
      var serverId=await fn(row.payload);
      if(!id(serverId))fail("OFFLINE_SERVER_ACK_INVALID");
      row.serverId=serverId;row.status="applied";row.errorCode=null;done++;
     }catch(err){
      var code=String(err?.code||"NETWORK_OR_UNKNOWN").slice(0,80);
      row.errorCode=code;
      if(/conflict|23505|P0001/.test(code.toLowerCase())||
         /idempotency/i.test(String(err?.message||"")))
        row.status="conflict";
      else if(["42501","401","403","PGRST301"].includes(code))
        row.status="unauthorized";
      else row.status="pending";
      if(row.status==="pending")pending++;else blocked++;
      await storage.save(rows);
      // Never auto-continue after ambiguous server outcome. User must explicitly
      // inspect and manually retry or resolve conflict.
      break;
     }
     await storage.save(rows);
    }
    return Object.freeze({applied:done,blocked,pending,remaining:
     rows.filter(function(r){return r.status!=="applied"}).length});
   }finally{syncing=false}
  }
  async function discard(localId){
   guard();if(!text(localId))fail("INVALID_OFFLINE_LOCAL_KEY");
   var rows=await load(),row=rows.find(function(r){return r.localId===localId});
   if(!row)return false;
   if(row.status==="applied")fail("CANNOT_DISCARD_APPLIED_SERVER_DRAFT");
   await storage.save(rows.filter(function(r){return r.localId!==localId}));
   return true;
  }
  return Object.freeze({
   status:function(){return Object.freeze({enabled,autoSync:false,
    persistence:params.storage?"injected":"volatile_memory",
    stockPostingEnabled:false,paymentPostingEnabled:false})},
   enqueue,load,sync,discard
  });
 }
 return Object.freeze({create,createMemoryStore,createEncryptedIndexedDBStore});
});
