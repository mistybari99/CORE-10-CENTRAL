/* CORE 10 ERP domain engines. Pure, immutable-output planning only.
 * Posting requires existing authenticated, tenant-scoped server RPC.
 */
(function(root,factory){"use strict";var x=factory();if(typeof module==="object"&&module.exports)module.exports=x;if(root)root.CORE10_ERP_ENGINES=x;})(typeof globalThis!=="undefined"?globalThis:null,function(){
"use strict";
function bad(reason){return {ok:false,reason:reason}}
function num(x){return typeof x==="number"&&Number.isFinite(x)&&x>=0&&x<=1e12?x:null}
function pos(x){var n=num(x);return n!==null&&n>0?n:null}
function id(x){return (typeof x==="number"&&Number.isSafeInteger(x)&&x>0)||(typeof x==="string"&&/^[1-9][0-9]*$/.test(x)&&Number.isSafeInteger(Number(x)))?String(x):null}
function money(x){return Math.round((x+Number.EPSILON)*100)/100}
function scope(x){return x&&id(x.business_id)&&id(x.location_id)?{business_id:id(x.business_id),location_id:id(x.location_id)}:null}
function unique(lines,key){var seen=new Set();for(var x of lines){var k=key(x);if(!k||seen.has(k))return false;seen.add(k)}return true}
function inventory(input){
 if(!input||!Array.isArray(input.movements)||!id(input.business_id)||!id(input.location_id)||!id(input.item_id))return bad("invalid_scope");
 var balance=0,history=[];
 for(var m of input.movements){
  if(!m||id(m.business_id)!==id(input.business_id)||id(m.location_id)!==id(input.location_id)||id(m.item_id)!==id(input.item_id))return bad("cross_scope_movement");
  var qty=pos(m.quantity);if(!qty||!["in","out"].includes(m.direction))return bad("invalid_movement");
  balance+=m.direction==="in"?qty:-qty;
  if(balance<0)return bad("negative_stock");
  history.push({direction:m.direction,quantity:qty,balance:money(balance)});
 }
 return {ok:true,balance:money(balance),history:history,simulation_only:true};
}
function production(input){
 if(!input||!scope(input)||!id(input.finished_item_id)||!pos(input.output_units)||!Array.isArray(input.components)||!input.components.length)return bad("invalid_production");
 if(!unique(input.components,x=>id(x&&x.item_id)))return bad("duplicate_component");
 var required=[],total=0;
 for(var c of input.components){
  var per=pos(c.quantity_per_unit),cost=num(c.unit_cost),available=num(c.available);
  if(!id(c.item_id)||!per||cost===null||available===null||id(c.item_id)===id(input.finished_item_id))return bad("invalid_component");
  var qty=per*input.output_units;
  if(!Number.isFinite(qty)||qty>1e12)return bad("overflow");
  if(available<qty)return bad("insufficient_material");
  total+=qty*cost;required.push({item_id:id(c.item_id),required:money(qty),available:available});
 }
 if(!Number.isFinite(total)||total>1e12)return bad("overflow");
 return {ok:true,required:required,estimated_cost:money(total),unit_cost:money(total/input.output_units),status:"draft",simulation_only:true};
}
function purchase(input){
 if(!input||!id(input.business_id)||!id(input.supplier_id)||!Array.isArray(input.lines)||!input.lines.length)return bad("invalid_purchase");
 if(!unique(input.lines,x=>id(x&&x.item_id)))return bad("duplicate_item");
 var total=0,lines=[];
 for(var x of input.lines){
  var qty=pos(x.quantity),price=num(x.unit_cost);
  if(!id(x.item_id)||!qty||price===null)return bad("invalid_line");
  total+=qty*price;lines.push({item_id:id(x.item_id),quantity:qty,unit_cost:price,line_total:money(qty*price)});
 }
 if(!Number.isFinite(total)||total>1e12)return bad("overflow");
 return {ok:true,business_id:id(input.business_id),supplier_id:id(input.supplier_id),lines:lines,total:money(total),status:"draft",simulation_only:true};
}
function sale(input){
 if(!input||!scope(input)||!Array.isArray(input.lines)||!input.lines.length)return bad("invalid_sale");
 if(!unique(input.lines,x=>id(x&&x.item_id)))return bad("duplicate_item");
 var subtotal=0,cost=0,lines=[];
 for(var x of input.lines){
  var qty=pos(x.quantity),price=num(x.unit_price),unitCost=num(x.unit_cost),available=num(x.available),reserved=num(x.reserved);
  if(!id(x.item_id)||!qty||price===null||unitCost===null||available===null||reserved===null||reserved>available)return bad("invalid_line");
  if(qty>available-reserved)return bad("insufficient_stock");
  subtotal+=qty*price;cost+=qty*unitCost;
  lines.push({item_id:id(x.item_id),quantity:qty,line_total:money(qty*price)});
 }
 var discount=num(input.discount===undefined?0:input.discount),tax=num(input.tax===undefined?0:input.tax);
 if(discount===null||tax===null||discount>subtotal||!Number.isFinite(subtotal+tax)||subtotal+tax>1e12)return bad("invalid_totals");
 return {ok:true,lines:lines,subtotal:money(subtotal),discount:discount,tax:tax,total:money(subtotal-discount+tax),estimated_gross_profit:money(subtotal-discount-cost),status:"draft",simulation_only:true};
}
function approval(input){
 // P0: caller-supplied role/status cannot authorize an approval.
 // The canonical server RPC must authenticate actor, scope, state and perform atomic posting.
 return bad("server_rpc_required");
}
function report(input){
 if(!input||!id(input.business_id)||!Array.isArray(input.sales)||!Array.isArray(input.purchases))return bad("invalid_report");
 var sales=0,purchases=0;
 for(var s of input.sales){if(!s||id(s.business_id)!==id(input.business_id)||num(s.total)===null)return bad("invalid_sales_scope");sales+=s.total}
 for(var p of input.purchases){if(!p||id(p.business_id)!==id(input.business_id)||num(p.total)===null)return bad("invalid_purchase_scope");purchases+=p.total}
 if(!Number.isFinite(sales+purchases)||sales+purchases>1e12)return bad("overflow");
 return {ok:true,sales:money(sales),purchases:money(purchases),net_cash_difference:money(sales-purchases),note:"Cash difference is not accounting profit",simulation_only:true};
}
return Object.freeze({inventory:inventory,production:production,purchase:purchase,sale:sale,approval:approval,report:report});
});
