/* CORE10 A035 isolated/off-by-default browser outbox contract.
 * Does NOT install a service worker or modify live ERP. No passwords/tokens saved.
 * IndexedDB data is NOT encrypted; rollout needs device privacy controls and consent.
 */
(function(root,factory){
 "use strict";
 const api=factory();
 if(typeof module==="object"&&module.exports)module.exports=api;
 if(root)root.CORE10_OFFLINE_OUTBOX_V1=api;
})(typeof window==="object"?window:null,function(){
 "use strict";
 function error(code){const e=new Error(code);e.code=code;throw e}
 function obj(v){return v!==null&&typeof v==="object"&&!Array.isArray(v)}
 function safeId(v){return Number.isSafeInteger(Number(v))&&Number(v)>0}
 function validate(x){
  if(!obj(x)||!safeId(x.businessId)||!safeId(x.locationId)||!safeId(x.itemId)||
   !Number.isInteger(x.expectedLedgerVersion)||x.expectedLedgerVersion<0||
   typeof x.delta!=="number"||!Number.isFinite(x.delta)||x.delta===0||
   Math.abs(x.delta)>999999999||Math.abs(x.delta*1000-Math.round(x.delta*1000))>0.000001)
   error("INVALID_OFFLINE_EVENT");
  return Object.freeze({
   businessId:Number(x.businessId),locationId:Number(x.locationId),
   itemId:Number(x.itemId),delta:x.delta,
   expectedLedgerVersion:x.expectedLedgerVersion
  });
 }
 function createIndexedDbStorage(idb){
  if(!idb||typeof idb.open!=="function")error("INDEXEDDB_UNAVAILABLE");
  let opening;
  function db(){
   if(opening)return opening;
   opening=new Promise((resolve,reject)=>{
    const req=idb.open("core10-a035-offline-outbox-v1",1);
    req.onupgradeneeded=()=>{const database=req.result;
      if(!database.objectStoreNames.contains("outbox"))database.createObjectStore("outbox",{keyPath:"localKey"});
    };
    req.onsuccess=()=>resolve(req.result);
    req.onerror=()=>reject(req.error||new Error("INDEXEDDB_OPEN_FAILED"));
   });return opening;
  }
  async function transaction(mode,operation){
   const database=await db();
   return new Promise((resolve,reject)=>{
    const tx=database.transaction("outbox",mode);
    let result;
    const req=operation(tx.objectStore("outbox"));
    req.onsuccess=()=>{result=req.result};
    tx.oncomplete=()=>resolve(result);
    tx.onerror=()=>reject(tx.error||new Error("INDEXEDDB_TX_FAILED"));
    tx.onabort=()=>reject(tx.error||new Error("INDEXEDDB_TX_ABORTED"));
   });
  }
  return Object.freeze({
   all:()=>transaction("readonly",s=>s.getAll()),
   put:row=>transaction("readwrite",s=>s.put(row))
  });
 }
 function create(config){
  if(!obj(config)||!config.storage||typeof config.storage.all!=="function"||
   typeof config.storage.put!=="function"||
   typeof config.getSubject!=="function"||typeof config.send!=="function"||
   typeof config.randomUUID!=="function")error("INVALID_OUTBOX_ADAPTER");
  let flushing=false;
  async function subject(){
   const x=await config.getSubject();
   if(typeof x!=="string"||!x.trim())error("AUTHENTICATED_SUBJECT_REQUIRED");
   return x;
  }
  async function list(){
   const user=await subject();
   const all=await config.storage.all();
   if(!Array.isArray(all))error("OFFLINE_STORAGE_FAILED");
   return all.filter(r=>r.subject===user).sort((a,b)=>a.createdAt-b.createdAt)
    .map(r=>Object.freeze({...r}));
  }
  async function enqueue(input){
   const x=validate(input),user=await subject();
   const nonce=config.randomUUID();
   if(typeof nonce!=="string"||!/^[0-9a-f-]{20,80}$/i.test(nonce))
    error("SECURE_RANDOM_KEY_REQUIRED");
   const requestKey="device:"+nonce;
   const localKey=user+":"+requestKey;
   const all=await config.storage.all();
   if(all.some(row=>row.localKey===localKey))error("DUPLICATE_LOCAL_EVENT_KEY");
   const row={...x,subject:user,requestKey,localKey,status:"queued",
    createdAt:Date.now(),lastError:null,receiptId:null};
   await config.storage.put(row);
   return Object.freeze({...row});
  }
  async function flush(){
   if(flushing)error("OFFLINE_FLUSH_ALREADY_RUNNING");
   flushing=true;
   try{
    const user=await subject();
    const mine=await list();
    let applied=0,conflicts=0,retryable=0;
    for(const row of mine){
     if(row.status!=="queued")continue;
     if(user!==await subject())error("SUBJECT_CHANGED_DURING_REPLAY");
     let response;
     try{
      response=await config.send({
       p_location:row.locationId,p_item:row.itemId,p_delta:row.delta,
       p_expected_version:row.expectedLedgerVersion,p_request:row.requestKey
      });
     }catch(e){
      await config.storage.put({...row,lastError:"RETRYABLE_NETWORK_FAILURE"});
      retryable++;
      // Stop; do not stamp successful replies for later requests when network is failing.
      break;
     }
     if(user!==await subject())error("SUBJECT_CHANGED_DURING_REPLAY");
     if(!obj(response)||!safeId(response.id)||
       response.request_key!==row.requestKey||
       !["applied","conflict"].includes(response.status))
      error("UNVERIFIED_SERVER_RECEIPT");
     const next={...row,status:response.status,receiptId:response.id,
      lastError:response.status==="conflict"?
       (typeof response.conflict_reason==="string"?response.conflict_reason:"NEEDS_MANUAL_REVIEW"):null};
     await config.storage.put(next);
     if(response.status==="applied")applied++;else conflicts++;
    }
    return Object.freeze({applied,conflicts,retryable});
   }finally{flushing=false;}
  }
  return Object.freeze({enqueue,list,flush,status:()=>Object.freeze({
   installedInProduction:false,automaticReplay:false,certified:false
  })});
 }
 return Object.freeze({create,createIndexedDbStorage,validate});
});
