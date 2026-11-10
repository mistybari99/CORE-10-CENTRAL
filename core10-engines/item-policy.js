/* CORE 10 | Pure, business-neutral item role advisor.
 * Advisory only: NEVER writes item master, stock, assets, prices or costing rules.
 * Source dictionary may come from any business. Owner approves business-specific role.
 */
(function(root,factory){"use strict";const api=factory();if(typeof module==="object"&&module.exports)module.exports=api;if(root)root.CORE10_ITEM_POLICY=api;})(typeof window!=="undefined"?window:globalThis,function(){
"use strict";
const types=Object.freeze({
 "Asset":{role:"asset",sellable:false,assetRegister:true,stockTracked:false,costBasis:"asset_register"},
 "Controlled Item":{role:"controlled",sellable:false,assetRegister:false,stockTracked:true,costBasis:"controlled_stock"},
 "Consumable":{role:"consumable",sellable:false,assetRegister:false,stockTracked:true,costBasis:"consumption"},
 "Raw Material":{role:"raw_material",sellable:false,assetRegister:false,stockTracked:true,costBasis:"input_material"},
 "Packaging":{role:"packaging",sellable:false,assetRegister:false,stockTracked:true,costBasis:"packaging_consumption"},
 "Stock/Direct Sale":{role:"resale",sellable:true,assetRegister:false,stockTracked:true,costBasis:"inventory_cogs"},
 "Finished Good":{role:"finished_good",sellable:true,assetRegister:false,stockTracked:true,costBasis:"production_cogs"},
 "Infrastructure Material":{role:"infrastructure",sellable:false,assetRegister:false,stockTracked:true,costBasis:"project_or_asset_review"}
});
function suggest(item,context){
 if(!item||typeof item!=="object")return Object.freeze({state:"review_required",reason:"INVALID_ITEM"});
 const key=typeof item.control_class==="string"?item.control_class.trim():"";
 const rule=types[key];
 if(!rule)return Object.freeze({state:"review_required",reason:"UNRECOGNIZED_CLASS",dictionaryCode:item.code||null});
 return Object.freeze({state:"suggestion_only",dictionaryCode:item.code||null,
  industryId:context?.industryId||null,role:rule.role,defaultSellable:rule.sellable,
  assetRegister:rule.assetRegister,stockTracked:rule.stockTracked,costBasisHint:rule.costBasis,
  mustApprove:true,changesOperationalData:false,actualCost:null,
  note:"Business-specific policies, valuation methods and sellability must be authorized before use."});
}
function coverage(items){
 if(!Array.isArray(items))throw Error("ITEMS_ARRAY_REQUIRED");
 const result={total:items.length,classified:0,unclassified:0,roles:{}};
 for(const item of items){const policy=suggest(item);if(policy.state!=="suggestion_only"){result.unclassified++;continue}result.classified++;result.roles[policy.role]=(result.roles[policy.role]||0)+1}
 return Object.freeze(result);
}
return Object.freeze({supportedClasses:Object.freeze(Object.keys(types)),suggest,coverage});
});