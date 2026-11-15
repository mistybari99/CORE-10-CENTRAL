"use strict";
const test=require("node:test"),assert=require("node:assert/strict");
const api=require("../../core10-pack02-controls.js");
const fx=n=>JSON.parse(JSON.stringify(require(`./fixtures/${n}.json`)));
const code=(fn,c)=>assert.throws(fn,e=>e&&e.code===c,c);
test("real projections: central registry lists all, business surface only its menu",()=>{
 const c=api.view(fx("controls-central"));
 assert.equal(c.items.length,18);
 assert.equal(c.items.find(i=>i.id==="finance.payments").inMenu,false);
 assert.equal(c.items.find(i=>i.id==="inventory.count").name,"স্টক গণনা");
 const b=api.view(fx("controls-business"));
 assert.deepEqual(b.items.map(i=>[i.id,i.edit]),[["inventory.count","direct"],["sales.orders","request"]]);
 assert.match(b.note,/অনুমতি নয়/);
});
test("business surface fails closed on hidden/central-only controls and extra fields",()=>{
 const b=fx("controls-business");
 const item=o=>({...b,items:[{...b.items[0],...o}]});
 code(()=>api.view(item({placement:"hidden_from_menus"})),"PACK02_CONTROLS_UNSAFE");
 code(()=>api.view(item({placement:"central_only"})),"PACK02_CONTROLS_UNSAFE");
 code(()=>api.view(item({in_menu:false})),"PACK02_CONTROLS_UNSAFE");
 code(()=>api.view(item({local_edit_mode:"central_only"})),"PACK02_CONTROLS_UNSAFE");
 code(()=>api.view({...b,tenant_id:1}),"PACK02_CONTROLS_UNSAFE");
});
test("malformed, duplicate, permission-claiming or certified projections are refused",()=>{
 const c=fx("controls-central");
 code(()=>api.view(null),"PACK02_CONTROLS_INVALID");
 code(()=>api.view({...c,placement_is_not_permission:false}),"PACK02_CONTROLS_INVALID");
 code(()=>api.view({...c,production_certified:true}),"PACK02_CONTROLS_INVALID");
 code(()=>api.view({...c,surface:"staff"}),"PACK02_CONTROLS_INVALID");
 code(()=>api.view({...c,items:[c.items[0],c.items[0]]}),"PACK02_CONTROLS_INVALID");
 code(()=>api.view({...c,items:[{...c.items[0],edit:"grant"}]}),"PACK02_CONTROLS_INVALID");
 code(()=>api.view({...c,items:[{...c.items[0],control_id:"<img>"}]}),"PACK02_CONTROLS_INVALID");
 const hidden=c.items.find(i=>i.placement==="hidden_from_menus");
 code(()=>api.view({...c,items:[{...hidden,in_menu:true}]}),"PACK02_CONTROLS_UNSAFE");
 assert.match(api.view({...fx("controls-business"),items:[]}).empty,/কোনো নিয়ন্ত্রণ/);
});
