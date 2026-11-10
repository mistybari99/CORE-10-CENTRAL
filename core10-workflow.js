/* CORE 10 ERP · cross-module workflow orchestrator (simulation-only).
 * Commands must be committed by server-authorized transactional RPC, never here.
 */
(function(root,factory){"use strict";var x=factory(typeof module==="object"&&module.exports?require("./core10-erp-engines.js"):root.CORE10_ERP_ENGINES);if(typeof module==="object"&&module.exports)module.exports=x;if(root)root.CORE10_WORKFLOW=x;})(typeof globalThis!=="undefined"?globalThis:null,function(E){
"use strict";
function fail(reason,step){return {ok:false,reason:reason,step:step}}
function validBusinessId(x){return (typeof x==="number"&&Number.isSafeInteger(x)&&x>0)||(typeof x==="string"&&/^[1-9][0-9]*$/.test(x)&&Number.isSafeInteger(Number(x)))}
function plan(input){
 if(!input||!Array.isArray(input.steps)||!input.steps.length||input.steps.length>100||!validBusinessId(input.business_id))return fail("invalid_workflow",0);
 var allowed={purchase:"purchase",receive:"inventory",produce:"production",sale:"sale",report:"report"};
 // P0: never model stock transfers as one-sided inventory movements or trust a caller-supplied approval role.
 // Both operations require verified, atomic server RPCs and remain blocked in this client planner.
 var stages=[],ids=new Set(),previous=null,lastPurchase=null;
 for(var i=0;i<input.steps.length;i++){
  var step=input.steps[i],type=step&&step.type,ref=step&&step.ref,payload=step&&step.payload;
  if(type==="transfer"||type==="approve")return fail("server_rpc_required",i);
  if(!Object.prototype.hasOwnProperty.call(allowed,type)||typeof ref!=="string"||!/^[a-zA-Z0-9_-]{1,64}$/.test(ref)||ids.has(ref)||!payload)return fail("invalid_step",i);
  if(!validBusinessId(payload.business_id)||Number(payload.business_id)!==Number(input.business_id))return fail("cross_business_step",i);
  if(type==="receive"&&previous!=="purchase")return fail("receive_requires_purchase",i);
  // A simulated goods receipt must not silently fabricate or over-receive purchase lines.
  // This planner supports one-item receipt previews only; real partial/multi-line GRN uses server RPC.
  if(type==="receive"){
   if(!lastPurchase||!Array.isArray(payload.movements)||payload.movements.length!==1)return fail("receipt_contract_invalid",i);
   var movement=payload.movements[0],matched=lastPurchase.lines.find(function(x){return String(x.item_id)===String(payload.item_id)});
   if(!movement||movement.direction!=="in"||!matched||
      String(movement.item_id)!==String(payload.item_id)||
      typeof movement.quantity!=="number"||!Number.isFinite(movement.quantity)||
      movement.quantity<=0||movement.quantity>matched.quantity)return fail("receipt_purchase_mismatch",i);
  }
  if(type==="produce"&&previous!=="receive"&&previous!=="transfer")return fail("production_requires_material_flow",i);
  if(type==="sale"&&previous!=="produce"&&previous!=="transfer"&&previous!=="receive")return fail("sale_requires_stock_flow",i);
  if(type==="transfer"&&previous!=="receive"&&previous!=="produce")return fail("transfer_requires_stock_flow",i);
  var method=E[allowed[type]],out=method(payload);
  if(!out||out.ok!==true)return fail(out&&out.reason||"validation_failed",i);
  if(type==="purchase")lastPurchase=out;
  ids.add(ref);stages.push(Object.freeze({ref:ref,type:type,preview:out}));previous=type;
 }
 return {ok:true,business_id:String(input.business_id),steps:Object.freeze(stages),simulation_only:true,requires_server_authorization:true};
}
return Object.freeze({plan:plan});
});
