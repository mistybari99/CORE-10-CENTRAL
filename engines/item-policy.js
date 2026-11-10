/* CORE10 | Universal item policy proposal engine. Pure data, no database writes.
 * Deliberately NOT a legacy-business adapter or a permissions authority.
 */
(function(root,factory){"use strict";const api=factory();if(typeof module==="object"&&module.exports)module.exports=api;if(root)root.CORE10_ITEM_POLICY=api;})(typeof window!=="undefined"?window:globalThis,function(){
 "use strict";
 const TYPES=Object.freeze({
  finished_good:{sellable:true,count_in_operational_stock:true,costing_route:"production_or_purchase_review",asset_register:false},
  resale:{sellable:true,count_in_operational_stock:true,costing_route:"purchase_cost_review",asset_register:false},
  raw_material:{sellable:false,count_in_operational_stock:true,costing_route:"material_input_review",asset_register:false},
  packaging:{sellable:false,count_in_operational_stock:true,costing_route:"packaging_input_review",asset_register:false},
  consumable:{sellable:false,count_in_operational_stock:false,costing_route:"operating_expense_review",asset_register:false},
  asset:{sellable:false,count_in_operational_stock:false,costing_route:"capitalization_depreciation_review",asset_register:true},
  controlled:{sellable:false,count_in_operational_stock:false,costing_route:"controlled_item_review",asset_register:false},
  infrastructure:{sellable:false,count_in_operational_stock:false,costing_route:"capital_or_expense_review",asset_register:false}
 });
 const CLASS_TO_TYPE=Object.freeze({
  "Finished Good":"finished_good","Stock/Direct Sale":"resale","Raw Material":"raw_material",
  Packaging:"packaging",Consumable:"consumable",Asset:"asset",
  "Controlled Item":"controlled","Infrastructure Material":"infrastructure"
 });
 const own=(obj,key)=>Object.prototype.hasOwnProperty.call(obj,key);
 function recommend(request){
  if(!request||typeof request!=="object"||Array.isArray(request))
   return {ok:false,status:"REQUIRES_REVIEW",reasons:["INVALID_INPUT"]};
  const type=typeof request.item_type==="string"?request.item_type.trim():"";
  const cls=typeof request.control_class==="string"?request.control_class.trim():"";
  const fromClass=own(CLASS_TO_TYPE,cls)?CLASS_TO_TYPE[cls]:null;
  if(type&&!own(TYPES,type))return {ok:false,status:"REQUIRES_REVIEW",reasons:["UNKNOWN_ITEM_TYPE"]};
  if(cls&&!fromClass)return {ok:false,status:"REQUIRES_REVIEW",reasons:["UNKNOWN_CONTROL_CLASS"]};
  if(type&&fromClass&&type!==fromClass)
   return {ok:false,status:"REQUIRES_REVIEW",reasons:["TYPE_CLASS_CONFLICT"]};
  const resolved=type||fromClass;
  if(!resolved)return {ok:false,status:"REQUIRES_REVIEW",reasons:["CLASSIFICATION_REQUIRED"]};
  const standard=TYPES[resolved];
  // Industry packs suggest overrides, but cannot write to real inventory or accounts.
  const overrides=request.proposed_overrides==null?{}:request.proposed_overrides;
  if(!overrides||Array.isArray(overrides)||typeof overrides!=="object")
   return {ok:false,status:"REQUIRES_REVIEW",reasons:["INVALID_OVERRIDES"]};
  const supported=new Set(["sellable","count_in_operational_stock","costing_route","asset_register"]);
  for(const [key,value] of Object.entries(overrides)){
   if(!supported.has(key)||typeof value!==(key==="costing_route"?"string":"boolean")||
       (key==="costing_route"&&(!/^[a-z][a-z0-9_]{0,60}$/.test(value))))
    return {ok:false,status:"REQUIRES_REVIEW",reasons:["INVALID_OVERRIDE:"+key]};
  }
  const suggested=Object.freeze({...standard,...overrides});
  const changes=Object.freeze(Object.keys(overrides).filter(k=>overrides[k]!==standard[k]));
  return Object.freeze({
   ok:true,engine:"core10.item_policy",status:"PROPOSAL_ONLY",item_type:resolved,
   suggested,default_policy:Object.freeze({...standard}),changes,
   requires_approval:changes.length>0,
   rules_source:"universal_classification_defaults_v1",
   note:"Proposals only. Existing item IDs, business rules, cost formulas, ledgers and access controls are never modified."
  });
 }
 return Object.freeze({TYPES,CLASS_TO_TYPE,recommend});
});