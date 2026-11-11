/* C10-A044 Shared Supabase signed-session config adapter.
 * Same c10_demo RPC for Central and Business. NO local permissions, session token
 * persistence, simulated success, stock, finance or production activation.
 */
(function(root,factory){"use strict";
 const api=factory();
 if(typeof module==="object"&&module.exports)module.exports=api;
 if(root)root.CORE10_CONTROL_SETTINGS_API=api;
})(typeof window!=="undefined"?window:globalThis,function(){
 "use strict";
 const PLACEMENTS=["central_only","business_only","both","hidden_from_menus"];
 const MODES=["central_only","business_owner","request_approval"];
 const ID=/^[a-z][a-z0-9]*(?:[._][a-z0-9]+)+$/;
 function fail(code){const e=new Error(code);e.code=code;throw e}
 function id(x){if((typeof x!=="number"&&typeof x!=="string")||
   !/^[1-9][0-9]*$/.test(String(x))||!Number.isSafeInteger(Number(x)))fail("INVALID_BUSINESS_ID");return Number(x)}
 function create({client}={}){
  async function db(){
   if(!client||!client.auth||typeof client.auth.getUser!=="function"||typeof client.schema!=="function")
    fail("SIGNED_SUPABASE_CLIENT_REQUIRED");
   const r=await client.auth.getUser();
   if(!r||r.error||!r.data||!r.data.user||typeof r.data.user.id!=="string"||!r.data.user.id)
    fail("AUTHENTICATED_USER_REQUIRED");
   const schema=client.schema("c10_demo");
   if(!schema||typeof schema.rpc!=="function"||typeof schema.from!=="function")
    fail("CONTROL_SCHEMA_NOT_AVAILABLE");
   return schema;
  }
  function unwrap(r){
   if(!r||r.error){const err=new Error(r&&r.error&&r.error.message||"CONTROL_RPC_UNAVAILABLE");
    err.code=r&&r.error&&r.error.code||"CONTROL_RPC_UNAVAILABLE";throw err}
   return r.data;
  }
  async function listBusinesses(){
   const s=await db();
   const rows=unwrap(await s.from("businesses").select("id,tenant_id,slug,status")
    .order("id",{ascending:true}).limit(200));
   if(!Array.isArray(rows)||rows.some(x=>!Number.isSafeInteger(x.id)||!Number.isSafeInteger(x.tenant_id)))
    fail("INVALID_BUSINESS_SCOPE_RESPONSE");
   return rows;
  }
  async function read(businessId){
   const biz=id(businessId),s=await db();
   const data=unwrap(await s.rpc("read_control_settings_v1",{p_business:biz}));
   if(!data||data.server_authorized!==true||data.operationally_certified!==false||
      data.business_id!==biz||!Number.isSafeInteger(data.tenant_id)||
      !Array.isArray(data.items)||data.items.length!==18)
    fail("CONTROL_SCOPE_RESPONSE_REJECTED");
   const seen=new Set();
   for(const x of data.items){
    if(!x||typeof x.control_id!=="string"||!ID.test(x.control_id)||
      seen.has(x.control_id)||!PLACEMENTS.includes(x.placement)||
      !MODES.includes(x.local_edit_mode)||typeof x.preferred_enabled!=="boolean"||
      !Number.isSafeInteger(x.version)||x.version<0)
      fail("CONTROL_ITEM_RESPONSE_REJECTED");
    seen.add(x.control_id);
   }
   return data;
  }
  async function write(businessId,choice){
   const biz=id(businessId),x=choice||{};
   if(typeof x.controlId!=="string"||!ID.test(x.controlId)||
      !PLACEMENTS.includes(x.placement)||!MODES.includes(x.localEditMode)||
      typeof x.enabled!=="boolean"||!Number.isSafeInteger(x.version)||x.version<0||
      typeof x.requestKey!=="string"||!/^[A-Za-z0-9_-]{8,100}$/.test(x.requestKey)||
      typeof x.reason!=="string"||x.reason.trim().length<5||x.reason.length>500)
    fail("INVALID_CONTROL_CHANGE");
   const s=await db();
   const result=unwrap(await s.rpc("write_control_setting_v1",{
    p_business:biz,p_control:x.controlId,p_placement:x.placement,
    p_local_edit:x.localEditMode,p_enabled:x.enabled,
    p_expected_version:x.version,p_request:x.requestKey,p_reason:x.reason.trim()
   }));
   if(!result||!["pending","applied"].includes(result.status))
    fail("INVALID_CONTROL_WRITE_RECEIPT");
   return result;
  }
  async function decide(requestId,decision){
   if(!Number.isSafeInteger(requestId)||requestId<1||!["approve","reject"].includes(decision))
    fail("INVALID_CONTROL_DECISION");
   const s=await db();
   const result=unwrap(await s.rpc("decide_control_setting_v1",{p_request_id:requestId,p_decision:decision}));
   if(!result||!["approved","rejected"].includes(result.status))fail("INVALID_CONTROL_DECISION_RECEIPT");
   return result;
  }
  async function pending(businessId){
   const biz=id(businessId),s=await db();
   const data=unwrap(await s.rpc("read_control_pending_v1",{p_business:biz}));
   if(!data||data.business_id!==biz||!Array.isArray(data.items))fail("CONTROL_PENDING_SCOPE_REJECTED");
   return data.items;
  }
  return Object.freeze({listBusinesses,read,write,decide,pending,releaseStatus:()=>Object.freeze({
   serverOnly:true,operationallyCertified:false,stockWrites:false,financeWrites:false})});
 }
 return Object.freeze({create,PLACEMENTS,MODES});
});
