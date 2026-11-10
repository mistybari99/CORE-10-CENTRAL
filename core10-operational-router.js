/* CORE 10 CENTRAL — scoped local Operational Engine Router.
 * This read-only registry does NOT grant business permissions: server RLS/RPC remains required.
 */
(function(root,factory){"use strict";const api=factory();if(typeof module==="object"&&module.exports)module.exports=api;if(root)root.CORE10_OPERATIONAL_ROUTER=api;})(typeof window!=="undefined"?window:globalThis,function(){
"use strict";
function create(){
 const entries=new Map();
 function register(definition){
  const d=definition||{};
  if(typeof d.id!=="string"||!/^([a-z]+\.)+[a-z_]+$/.test(d.id)||entries.has(d.id))
    throw Error("INVALID_OR_DUPLICATE_ENGINE");
  if(d.access!=="read_only"||typeof d.execute!=="function")throw Error("UNVERIFIED_ENGINE_WRITE_ACCESS");
  entries.set(d.id,Object.freeze({id:d.id,execute:d.execute,access:d.access}));
  return d.id;
 }
 function invoke(id,context,payload){
  const e=entries.get(id);
  if(!e)throw Error("ENGINE_NOT_REGISTERED");
  if(!context||typeof context.businessId!=="string"||!context.businessId.trim()||
     typeof context.industryId!=="string"||!context.industryId.trim())throw Error("BUSINESS_CONTEXT_REQUIRED");
  if(payload&&typeof payload==="object"&&payload.business_id!=null&&
     String(payload.business_id)!==context.businessId)throw Error("INPUT_SCOPE_MISMATCH");
  return e.execute(payload,Object.freeze({businessId:context.businessId,industryId:context.industryId}));
 }
 return Object.freeze({register,invoke,list:()=>Object.freeze([...entries.keys()])});
}
function installItemPolicy(router,policy){
 if(!router||!policy||typeof policy.recommend!=="function")throw Error("ITEM_POLICY_ENGINE_UNAVAILABLE");
 return router.register({id:"item.policy.recommend",access:"read_only",
  execute:(input,context)=>policy.recommend(input,{industryId:context.industryId})});
}
return Object.freeze({create,installItemPolicy});
});