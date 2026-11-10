/* CORE 10 CENTRAL — brand-neutral, read-only Item Policy Advisory Engine.
 * Adapts the existing item-type/control-class and flag concepts, not business-specific workflows.
 * No database, payment, stock, journal, tax or costing writes. Not an authorization boundary.
 */
(function(root,factory){"use strict";const api=factory();if(typeof module==="object"&&module.exports)module.exports=api;if(root)root.CORE10_ITEM_POLICY=api;})(typeof window!=="undefined"?window:globalThis,function(){
"use strict";
const INDUSTRIES=Object.freeze(["sweets_bakery","restaurant","paint_hardware","retail_wholesale",
 "general_manufacturing","construction","import_export","ecommerce","technology_digital","services"]);
const CLASS_TO_KIND=Object.freeze({
 "Asset":"asset","Controlled Item":"controlled_item","Consumable":"consumable",
 "Raw Material":"raw_material","Packaging":"packaging","Stock/Direct Sale":"resale_good",
 "Finished Good":"finished_good","Infrastructure Material":"infrastructure_material"
});
const KIND_POLICY=Object.freeze({
 asset:{tracking:"asset_register",sales:"not_default_sellable",costing:"capital_policy_review",reports:["asset_register","asset_maintenance"]},
 controlled_item:{tracking:"requires_rule",sales:"owner_review",costing:"owner_review",reports:["controlled_inventory"]},
 consumable:{tracking:"optional_stock",sales:"not_default_sellable",costing:"consumption_policy_review",reports:["consumption"]},
 raw_material:{tracking:"stock_if_managed",sales:"not_default_sellable",costing:"material_valuation_review",reports:["material_stock","material_consumption"]},
 packaging:{tracking:"stock_if_managed",sales:"not_default_sellable",costing:"packaging_allocation_review",reports:["packaging_stock","packaging_usage"]},
 resale_good:{tracking:"stock_if_managed",sales:"likely_sellable",costing:"purchase_cost_review",reports:["sales","stock"]},
 finished_good:{tracking:"stock_if_managed",sales:"likely_sellable",costing:"source_or_production_cost_review",reports:["sales","finished_stock"]},
 infrastructure_material:{tracking:"project_or_asset_register",sales:"not_default_sellable",costing:"expense_or_capital_policy_review",reports:["project_materials"]}
});
const INDUSTRY_HINTS=Object.freeze({
 sweets_bakery:{raw_material:"recipe_and_batch_input",finished_good:"batch_cost_trace",packaging:"package_consumption"},
 restaurant:{raw_material:"recipe_and_kitchen_consumption",finished_good:"menu_item_cost_review"},
 paint_hardware:{resale_good:"variant_and_dealership_pricing",raw_material:"tinting_input_check"},
 retail_wholesale:{resale_good:"price_tiers_and_distribution"},
 general_manufacturing:{raw_material:"bom_and_work_order_inputs",finished_good:"work_order_output_cost"},
 construction:{raw_material:"project_issue_and_boq",infrastructure_material:"project_or_asset_classification"},
 import_export:{resale_good:"landed_cost_and_fx_review",raw_material:"shipment_landed_cost_review"},
 ecommerce:{resale_good:"channel_inventory_and_returns"},
 technology_digital:{resale_good:"digital_or_physical_delivery_review",controlled_item:"license_or_asset_access"},
 services:{consumable:"job_consumption",controlled_item:"service_equipment_control"}
});
function recommend(item,options){
 if(!item||typeof item!=="object"||Array.isArray(item))throw Error("INVALID_ITEM");
 const opts=options||{},industry=opts.industryId;
 if(!INDUSTRIES.includes(industry))throw Error("UNKNOWN_INDUSTRY");
 const originalKind=typeof item.item_type==="string"&&item.item_type.trim()||null;
 const fromClass=CLASS_TO_KIND[item.control_class]||null;
 const kind=originalKind||fromClass;
 const policy=KIND_POLICY[kind]||null;
 const existing={sellable:typeof item.sellable==="boolean"?item.sellable:null,
  tracked:typeof item.tracked==="boolean"?item.tracked:null,
  counted:typeof item.count_in_business==="boolean"?item.count_in_business:null,
  locked:typeof item.locked==="boolean"?item.locked:null,
  hidden:typeof item.hidden==="boolean"?item.hidden:null};
 const warnings=[];
 if(originalKind&&fromClass&&originalKind!==fromClass)warnings.push("EXPLICIT_TYPE_DIFFERS_FROM_DICTIONARY_CLASS");
 if(!policy)warnings.push("TYPE_REQUIRES_MANUAL_CLASSIFICATION");
 if(existing.sellable===true&&policy&&policy.sales==="not_default_sellable")warnings.push("SELLABLE_FLAG_NEEDS_POLICY_REVIEW");
 if(existing.locked===true)warnings.push("ITEM_LOCKED_NO_AUTOMATIC_CHANGE");
 if(item.retired_at)warnings.push("RETIRED_ITEM_NO_AUTOMATIC_REACTIVATION");
 const hints=INDUSTRY_HINTS[industry];
 const domainHint=hints[kind]||null;
 return Object.freeze({
  industryId:industry,itemKey:item.code||item.master_code||null,
  kind,source:originalKind?"existing_item_type":fromClass?"dictionary_control_class":"unclassified",
  existingFlags:Object.freeze(existing),
  recommendation:Object.freeze({tracking:policy?.tracking||"owner_review",sales:policy?.sales||"owner_review",
   costing:policy?.costing||"owner_review",reportCategories:Object.freeze([...(policy?.reports||[])]),
   optionalIndustryHint:domainHint,readiness:"proposal_only_requires_validation"}),
  warnings:Object.freeze(warnings),writesPerformed:false
 });
}
return Object.freeze({INDUSTRIES,CLASS_TO_KIND,recommend});
});