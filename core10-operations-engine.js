/* CORE 10 · Business Operations Intelligence Engine
 * Pure advisory calculations. Never changes real stock, prices or accounting.
 */
(function(root,factory){
 "use strict";var api=factory();
 if(typeof module==="object"&&module.exports)module.exports=api;
 if(root)root.CORE10_OPERATIONS_ENGINE=api;
})(typeof globalThis!=="undefined"?globalThis:null,function(){
 "use strict";
 function resultError(reason){return {ok:false,reason:reason}}
 function amount(v){return typeof v==="number"&&Number.isFinite(v)&&v>=0&&v<=1e12?v:null}
 function positive(v){var n=amount(v);return n!==null&&n>0?n:null}
 function round(v){return Math.round((v+Number.EPSILON)*100)/100}
 function recipeCost(recipe,units){
  if(!Array.isArray(recipe)||!recipe.length||!positive(units))return resultError("invalid_recipe");
  var total=0,lines=[],seen=new Set();
  for(var i=0;i<recipe.length;i++){
   var x=recipe[i],id=x&&x.item_id,qty=x&&positive(x.quantity),rate=x&&amount(x.unit_cost);
   if((typeof id!=="string"&&typeof id!=="number")||!String(id).trim()||seen.has(String(id))||!qty||rate===null)return resultError("invalid_component");
   seen.add(String(id));var cost=qty*rate;
   if(!Number.isFinite(cost)||cost>1e12)return resultError("cost_overflow");
   total+=cost;lines.push({item_id:id,quantity:qty,unit_cost:rate,extended_cost:round(cost)});
  }
  if(!Number.isFinite(total)||total>1e12)return resultError("cost_overflow");
  return {ok:true,batch_cost:round(total),unit_cost:round(total/units),yield_units:units,components:lines};
 }
 function priceScenario(input){
  if(!input)return resultError("invalid_input");
  var price=positive(input.selling_price),cost=amount(input.unit_cost),qty=positive(input.units),overhead=amount(input.overhead);
  if(!price||cost===null||!qty||overhead===null)return resultError("invalid_input");
  var sales=price*qty,expenses=cost*qty+overhead,profit=sales-expenses;
  if(!Number.isFinite(sales)||!Number.isFinite(expenses)||sales>1e12||expenses>1e12)return resultError("overflow");
  return {ok:true,sales:round(sales),expenses:round(expenses),profit:round(profit),margin_pct:round(profit/sales*100),
   break_even_units:price>cost?Math.ceil(overhead/(price-cost)):null,simulation_only:true};
 }
 function reorder(input){
  if(!input)return resultError("invalid_input");
  var stock=amount(input.available),daily=amount(input.daily_usage),lead=amount(input.lead_days),buffer=amount(input.safety_stock);
  if([stock,daily,lead,buffer].some(function(x){return x===null}))return resultError("invalid_input");
  var threshold=daily*lead+buffer;
  if(!Number.isFinite(threshold)||threshold>1e12)return resultError("overflow");
  return {ok:true,reorder_point:round(threshold),reorder_now:stock<=threshold,
   suggested_quantity:round(Math.max(0,threshold+daily*lead-stock)),simulation_only:true};
 }
 function transferFeasibility(input){
  if(!input)return resultError("invalid_input");
  var available=amount(input.available),reserved=amount(input.reserved),requested=positive(input.requested);
  if(available===null||reserved===null||!requested||reserved>available)return resultError("invalid_input");
  return {ok:true,can_fulfill:available-reserved>=requested,free_stock:round(available-reserved),
   shortfall:round(Math.max(0,requested-(available-reserved))),simulation_only:true};
 }
 return Object.freeze({recipeCost:recipeCost,priceScenario:priceScenario,reorder:reorder,transferFeasibility:transferFeasibility});
});
