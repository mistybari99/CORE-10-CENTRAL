"use strict";
// Real 0152 RPC shapes through a mock SDK. This is not hosted Auth validation.
const test=require("node:test"),assert=require("node:assert/strict");
const {create}=require("../../core10-sales-master-catalog.js");
const owner="11111111-1111-4111-8111-111111111111",other="77777777-7777-4777-8777-777777777777";
const scope={businessId:101,siteId:1001},now=()=>new Date("2026-11-17T12:00:00Z");
function dataset(){return {
 context:{actor_uid:owner,businesses:[{id:101,tenant_id:1,can_manage:true}],sites:[{id:1001,tenant_id:1,business_id:101,allowed_actions:["stock.read"]}]},
 parties:[{id:11,code:"CUSTOMER",name_en:"Synthetic customer",name_bn:"সিনথেটিক গ্রাহক",party_kind:"customer",status:"active",version:1},{id:12,code:"BOTH",name_en:"Customer and supplier",name_bn:null,party_kind:"both",status:"active",version:1}],
 items:[{id:21,sku:"SWEET",name_en:"Synthetic sweets",name_bn:"সিনথেটিক মিষ্টি",base_uom_id:31,status:"active",variant_count:1,version:1},{id:22,sku:"CAKE",name_en:"Synthetic cake",name_bn:null,base_uom_id:31,status:"active",variant_count:0,version:1}],
 uoms:{uoms:[{id:31,code:"PCS",name_en:"Piece",name_bn:"পিস",dimension:"count",decimals:0,active:true,version:1},{id:32,code:"BOX",name_en:"Box",name_bn:"বক্স",dimension:"count",decimals:0,active:true,version:1}],conversions:[{id:33,from_uom_id:32,to_uom_id:31,factor:12,active:true,version:1}]},
 lists:[{id:41,code:"RETAIL",name_en:"Retail",name_bn:"খুচরা",list_kind:"sales",currency:"BDT",site_id:null,effective_from:"2026-01-01",effective_to:null,status:"active",version:1},{id:42,code:"WHOLESALE",name_en:"Wholesale",name_bn:"পাইকারি",list_kind:"sales",currency:"BDT",site_id:1001,effective_from:"2026-01-01",effective_to:"2026-11-17",status:"active",version:1}],
 prices:{41:[{id:51,item_id:21,variant_id:null,uom_id:31,min_quantity:0,unit_price:300,active:true,version:1},{id:52,item_id:22,variant_id:null,uom_id:31,min_quantity:0,unit_price:1200,active:true,version:1},{id:53,item_id:21,variant_id:61,uom_id:31,min_quantity:0,unit_price:300,active:true,version:1}],42:[{id:54,item_id:21,variant_id:null,uom_id:31,min_quantity:0,unit_price:270,active:true,version:1},{id:55,item_id:22,variant_id:null,uom_id:31,min_quantity:0,unit_price:1080,active:true,version:1}]}
};}
function page(rows,args){const sorted=rows.filter(r=>args.p_after_id==null||r.id>args.p_after_id).sort((a,b)=>a.id-b.id),slice=sorted.slice(0,args.p_limit);return {rows:slice,next_after_id:sorted.length>args.p_limit?slice.at(-1).id:null};}
function fixture({data=dataset(),override}={}){
 let actor=owner,subscriber,checks=0,unsubs=0;
 const calls=[],schemas=[];
 function response(name,args){
  if(name==="build01_context_v1")return {data:data.context};
  if(name==="master_list_parties_v1")return {data:page(data.parties,args)};
  if(name==="master_list_items_v1")return {data:page(data.items,args)};
  if(name==="master_list_uoms_v1")return {data:data.uoms};
  if(name==="master_list_price_lists_v1")return {data:data.lists};
  if(name==="master_get_price_list_v1")return {data:{...data.lists.find(l=>l.id===args.p_price_list),...page(data.prices[args.p_price_list]||[],args)}};
  throw Error("Unexpected mock RPC "+name);
 }
 const client={auth:{getUser:async()=>{checks++;return {data:{user:actor?{id:actor}:null},error:null};},onAuthStateChange(fn){subscriber=fn;return {data:{subscription:{unsubscribe(){subscriber=null;unsubs++;}}}};}},schema(name){schemas.push(name);return {async rpc(name,args){calls.push({name,args});return override?override(name,args,response):response(name,args);}};}};
 return {client,calls,schemas,data,setUser(v){actor=v;},emit(event){subscriber?.(event,{user:actor?{id:actor}:null});},get checks(){return checks;},get unsubscribed(){return unsubs;}};
}
const make=(f,options={})=>create({client:f.client,now,...options});
test("real Master ports project scoped customers, lists, base items and flat prices without local records",async()=>{
 const f=fixture(),c=make(f),r=await c.load(scope);
 assert.deepEqual(r,{businessId:101,siteId:1001,source:"canonical_master",customers:[{id:11,label:"সিনথেটিক গ্রাহক",labelEn:"Synthetic customer",labelBn:"সিনথেটিক গ্রাহক"},{id:12,label:"Customer and supplier",labelEn:"Customer and supplier",labelBn:"Customer and supplier"}],priceLists:[{id:41,label:"খুচরা",labelEn:"Retail",labelBn:"খুচরা",currency:"BDT"},{id:42,label:"পাইকারি",labelEn:"Wholesale",labelBn:"পাইকারি",currency:"BDT"}],items:[{id:21,label:"সিনথেটিক মিষ্টি",labelEn:"Synthetic sweets",labelBn:"সিনথেটিক মিষ্টি",uomId:31,uomLabel:"পিস",uomLabelEn:"Piece",uomLabelBn:"পিস",quantityDecimals:0,variantId:null,minQuantity:0,prices:{41:300,42:270}},{id:22,label:"Synthetic cake",labelEn:"Synthetic cake",labelBn:"Synthetic cake",uomId:31,uomLabel:"পিস",uomLabelEn:"Piece",uomLabelBn:"পিস",quantityDecimals:0,variantId:null,minQuantity:0,prices:{41:1200,42:1080}}]});
 assert.equal(f.checks,2*f.calls.length);assert.equal(f.schemas.every(x=>x==="core10"),true);
 assert.deepEqual(f.calls.find(x=>x.name==="master_list_parties_v1").args,{p_business:101,p_kind:"customer",p_search:null,p_status:"active",p_limit:200,p_after_id:null});
 assert.equal(f.calls.every(x=>x.name==="build01_context_v1"||x.args.p_business===101),true);
 assert.equal(r.customers.some(x=>"phone" in x),false);
 c.destroy();assert.equal(f.unsubscribed,1);
});
test("keyset pagination reads every bounded page and preserves canonical arguments",async()=>{
 const f=fixture(),c=make(f,{pageSize:1,maxPages:10,lang:"en"}),r=await c.load(scope);
 assert.equal(r.customers.length,2);assert.equal(r.items.length,2);assert.equal(r.items[0].label,"Synthetic sweets");
 assert.deepEqual(f.calls.filter(x=>x.name==="master_list_parties_v1").map(x=>x.args.p_after_id),[null,11]);
 assert.deepEqual(f.calls.filter(x=>x.name==="master_get_price_list_v1"&&x.args.p_price_list===41).map(x=>x.args.p_after_id),[null,51,52]);
 assert.equal(f.checks,2*f.calls.length);c.destroy();
});
test("bilingual labels and authoritative UOM precision survive projection for local language toggles",async()=>{
 const data=dataset();data.uoms.uoms[0].decimals=3;data.prices[42][0].min_quantity=1;
 const f=fixture({data}),c=make(f,{lang:"bn"}),r=await c.load(scope);
 assert.equal(r.customers[0].labelEn,"Synthetic customer");assert.equal(r.customers[0].labelBn,"সিনথেটিক গ্রাহক");
 assert.equal(r.items[0].labelEn,"Synthetic sweets");assert.equal(r.items[0].labelBn,"সিনথেটিক মিষ্টি");
 assert.equal(r.items[0].uomLabelEn,"Piece");assert.equal(r.items[0].uomLabelBn,"পিস");
 assert.equal(r.items[0].quantityDecimals,3);assert.equal(r.items[0].minQuantity,1);
 assert.equal(r.priceLists[0].labelEn,"Retail");assert.equal(r.priceLists[0].labelBn,"খুচরা");
 assert.equal(r.customers[1].labelBn,r.customers[1].labelEn,"a missing translation uses an actual source label");
 c.destroy();
});
test("inactive, noncustomer and out-of-site or ineffective lists never become Sales choices",async()=>{
 const data=dataset();
 data.parties.push({id:13,code:"SUPPLIER",name_en:"Supplier",party_kind:"supplier",status:"active",version:1},{id:14,code:"BLOCKED",name_en:"Blocked",party_kind:"customer",status:"blocked",version:1});
 const base=data.lists[0];data.lists.push(...[{id:43,site_id:1002},{id:44,status:"inactive"},{id:45,effective_from:"2026-11-18"},{id:46,effective_to:"2026-11-16"},{id:47,list_kind:"purchase"}].map(x=>({...base,...x})));
 const f=fixture({data}),c=make(f),r=await c.load(scope);
 assert.deepEqual(r.customers.map(x=>x.id),[11,12]);assert.deepEqual(r.priceLists.map(x=>x.id),[41,42]);
 assert.equal(f.calls.filter(x=>x.name==="master_get_price_list_v1").every(x=>[41,42].includes(x.args.p_price_list)),true);c.destroy();
});
test("variant entries are ignored only when a complete supported base-price projection exists",async()=>{
 const data=dataset();data.prices[41].push({id:62,item_id:21,variant_id:61,uom_id:31,min_quantity:20,unit_price:250,active:true,version:1});
 const f=fixture({data}),c=make(f),r=await c.load(scope);assert.equal(r.items[0].variantId,null);assert.equal(r.items[0].prices[41],300);c.destroy();
 data.prices[41]=data.prices[41].filter(p=>p.item_id!==21||p.variant_id!==null);
 const g=fixture({data}),d=make(g);await assert.rejects(d.load(scope),/NOT_CONNECTED:MASTER_CATALOG_UNSUPPORTED_VARIANT/);d.destroy();
});
test("supported single quantity0/1 prices expose a minimum; extra base tiers fail closed",async()=>{
 const data=dataset();data.prices[41][0].min_quantity=1;
 const f=fixture({data}),c=make(f),r=await c.load(scope);assert.equal(r.items[0].minQuantity,1);c.destroy();
 for(const tier of [{id:66,item_id:21,variant_id:null,uom_id:31,min_quantity:10,unit_price:280,active:true,version:1},null]){
  const next=dataset();if(tier)next.prices[41].push(tier);else next.prices[41][0].min_quantity=.5;
  const g=fixture({data:next}),d=make(g);await assert.rejects(d.load(scope),/NOT_CONNECTED:MASTER_CATALOG_UNSUPPORTED_TIER/);d.destroy();
 }
});
test("alternate UOM is never converted or guessed; absent base-UOM pricing refuses the projection",async()=>{
 const data=dataset();data.prices[41][0].uom_id=32;
 const f=fixture({data}),c=make(f);await assert.rejects(c.load(scope),/NOT_CONNECTED:MASTER_CATALOG_UNSUPPORTED_CONVERSION/);c.destroy();
 const next=dataset();next.uoms.uoms[0].active=false;
 const g=fixture({data:next}),d=make(g);assert.equal(await d.load(scope),null);d.destroy();
});
test("missing prices produce only the safe common list intersection, never a zero-price fallback",async()=>{
 const data=dataset();data.prices[42]=data.prices[42].filter(x=>x.item_id!==22);
 const f=fixture({data}),c=make(f),r=await c.load(scope);assert.deepEqual(r.items.map(x=>x.id),[21]);c.destroy();
 data.prices[42]=[];
 const g=fixture({data}),d=make(g);assert.equal(await d.load(scope),null);d.destroy();
 data.parties=[];const h=fixture({data}),e=make(h);assert.equal(await e.load(scope),null);e.destroy();
});
test("nonowner, foreign-site, tenant mismatch and explicit site read denial stop before Master reads",async()=>{
 for(const change of [d=>d.context.businesses[0].can_manage=false,d=>d.context.sites[0].id=2001,d=>d.context.sites[0].tenant_id=2,d=>d.context.sites[0].allowed_actions=[]]){
  const data=dataset();change(data);const f=fixture({data}),c=make(f);
  await assert.rejects(c.load(scope),/MASTER_CATALOG_SCOPE/);assert.deepEqual(f.calls.map(x=>x.name),["build01_context_v1"]);c.destroy();
 }
 const f=fixture();f.setUser(null);const c=make(f);await assert.rejects(c.load(scope),/MASTER_CATALOG_SIGNED_SESSION_REQUIRED/);assert.equal(f.calls.length,0);c.destroy();
});
test("pagination rejects repeated/out-of-order IDs, invalid cursors, oversized pages and bounded exhaustion",async()=>{
 for(const mutate of [r=>r.next_after_id=999,r=>r.rows.reverse(),r=>r.rows.push({...r.rows[0]})]){
  const f=fixture({override:(name,args,normal)=>{const r=normal(name,args);if(name==="master_list_parties_v1")mutate(r.data);return r;}}),c=make(f);
  await assert.rejects(c.load(scope),/MASTER_CATALOG_INVALID_PAGE/);c.destroy();
 }
 const f=fixture(),c=make(f,{pageSize:1,maxPages:1});await assert.rejects(c.load(scope),/MASTER_CATALOG_LIMIT/);c.destroy();
 const g=fixture(),d=make(g,{maxPriceLists:1});await assert.rejects(d.load(scope),/MASTER_CATALOG_LIMIT/);assert.equal(g.calls.some(x=>x.name==="master_get_price_list_v1"),false);d.destroy();
});
test("foreign scope fields, invalid money or dates and changed price-list headers cannot populate the UI",async()=>{
 for(const mutate of [d=>d.parties[0].business_id=201,d=>d.prices[41][0].unit_price=-1,d=>d.prices[41][0].unit_price="300",d=>d.lists[0].effective_from="2026-02-30",d=>d.uoms.uoms.push({...d.uoms.uoms[0]})]){
  const data=dataset();mutate(data);const f=fixture({data}),c=make(f);await assert.rejects(c.load(scope),/MASTER_CATALOG_/);c.destroy();
 }
 const f=fixture({override:(name,args,normal)=>{const r=normal(name,args);if(name==="master_get_price_list_v1")r.data.currency="USD";return r;}}),c=make(f);
 await assert.rejects(c.load(scope),/MASTER_CATALOG_STALE_PRICE_LIST/);c.destroy();
});
test("auth changes or destroy during Master reads discard all pending records",async()=>{
 for(const event of ["SIGNED_OUT","SIGNED_IN","TOKEN_REFRESHED",null]){
  let release;const f=fixture({override:(name,args,normal)=>name==="master_list_parties_v1"?new Promise(resolve=>{release=()=>resolve(normal(name,args));}):normal(name,args)}),c=make(f);
  const pending=c.load(scope);while(!release)await new Promise(setImmediate);
  if(event)f.emit(event);else f.setUser(other);
  release();await assert.rejects(pending,/MASTER_CATALOG_SESSION_INVALIDATED/);c.destroy();
 }
 let finish;const gone=fixture({override:(name,args,normal)=>name==="master_list_parties_v1"?new Promise(resolve=>{finish=()=>resolve(normal(name,args));}):normal(name,args)}),destroyed=make(gone);
 const stale=destroyed.load(scope);while(!finish)await new Promise(setImmediate);
 destroyed.destroy();destroyed.destroy();finish();await assert.rejects(stale,/MASTER_CATALOG_SESSION_INVALIDATED/);assert.equal(gone.unsubscribed,1);
 // Event invalidation itself (without destroy) also blocks same-user completion.
 let release;const f=fixture({override:(name,args,normal)=>name==="master_list_items_v1"?new Promise(resolve=>{release=()=>resolve(normal(name,args));}):normal(name,args)}),c=make(f);
 const pending=c.load(scope);while(!release)await new Promise(setImmediate);
 f.emit("SIGNED_OUT");release();await assert.rejects(pending,/MASTER_CATALOG_SESSION_INVALIDATED/);c.destroy();
});
test("transport and absent-port errors retain honest machine distinctions and recheck the actor",async()=>{
 for(const [error,expected] of [[Error("Failed to fetch"),"MASTER_CATALOG_RPC_UNAVAILABLE"],[{code:"PGRST202",message:"Function was not found in the schema cache"},"PGRST202"],[{code:"42883",message:"function core10.master_list_items_v1 does not exist"},"42883"],[{message:"MASTER_SCOPE"},"MASTER_SCOPE"]]){
  const f=fixture({override:()=>({data:null,error})}),c=make(f);
  await assert.rejects(c.load(scope),e=>e.code===expected);assert.equal(f.checks,2);c.destroy();
 }
 const f=fixture({override:()=>({data:null,error:null})}),c=make(f);await assert.rejects(c.load(scope),/MASTER_CATALOG_RPC_NO_RECEIPT/);assert.equal(f.checks,2);c.destroy();
});
test("scope inputs are captured before awaiting and no unsupported options or unsafe IDs are accepted",async()=>{
 const f=fixture(),c=make(f),input={...scope},pending=c.load(input);input.businessId=201;input.siteId=2001;
 const result=await pending;assert.equal(result.businessId,101);assert.equal(result.siteId,1001);c.destroy();
 for(const input of [{businessId:"101",siteId:1001},{businessId:101,siteId:0},{...scope,role:"owner"}]){
  const f=fixture(),c=make(f);await assert.rejects(c.load(input),/MASTER_CATALOG_INVALID/);assert.equal(f.calls.length,0);c.destroy();
 }
 const f2=fixture();assert.throws(()=>make(f2,{pageSize:201}),/MASTER_CATALOG_INVALID_OPTIONS/);assert.throws(()=>make(f2,{maxPages:0}),/MASTER_CATALOG_INVALID_OPTIONS/);
});
