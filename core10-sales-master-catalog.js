/* NP03B projection of the real NP02 0152 Master read ports. No local Master
 * records, guessed prices, conversions, statutory tax or service-role calls.
 * The Sales UI currently supports the common base-item/base-UOM flat-price
 * intersection of the eligible price lists. SQL revalidates on each mutation.
 */
(function(root,factory){
 "use strict";const api=factory();
 if(typeof module==="object"&&module.exports)module.exports=api;
 if(root)root.CORE10_SALES_MASTER_CATALOG=api;
})(typeof window!=="undefined"?window:globalThis,function(){
 "use strict";
 const object=x=>!!x&&typeof x==="object"&&!Array.isArray(x);
 const dimensions=new Set(["count","mass","volume","length","area","time"]);
 function fail(code){const e=new Error(code);e.code=code;throw e;}
 function id(x){if(!Number.isSafeInteger(x)||x<1)fail("MASTER_CATALOG_INVALID_ID");return x;}
 function positiveVersion(x){if(!Number.isSafeInteger(x)||x<1)fail("MASTER_CATALOG_INVALID_RESPONSE");return x;}
 function number(x,min=0){if(typeof x!=="number"||!Number.isFinite(x)||Math.abs(x)>Number.MAX_SAFE_INTEGER||x<min)fail("MASTER_CATALOG_INVALID_NUMBER");return x;}
 function uid(x){if(typeof x!=="string"||!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(x))fail("MASTER_CATALOG_SIGNED_SESSION_REQUIRED");return x.toLowerCase();}
 function date(x){
  if(typeof x!=="string"||!/^\d{4}-\d{2}-\d{2}$/.test(x))fail("MASTER_CATALOG_INVALID_DATE");
  const value=new Date(x+"T00:00:00.000Z");
  if(!Number.isFinite(value.valueOf())||value.toISOString().slice(0,10)!==x)fail("MASTER_CATALOG_INVALID_DATE");
  return x;
 }
 function label(row,lang){
  const fields=lang==="en"?[row.name_en,row.name_bn,row.sku,row.code]:[row.name_bn,row.name_en,row.sku,row.code];
  const value=fields.find(x=>typeof x==="string"&&x.trim());
  if(value===undefined)fail("MASTER_CATALOG_INVALID_LABEL");return value.trim();
 }
 function scoped(row,business){
  if(!object(row)||row.business_id!==undefined&&row.business_id!==business)fail("MASTER_CATALOG_SCOPE_MISMATCH");
  return row;
 }
 function uniqueRows(rows,maxRows){
  if(!Array.isArray(rows)||rows.length>maxRows)fail("MASTER_CATALOG_LIMIT");
  const seen=new Set();for(const row of rows){if(!object(row)||seen.has(id(row.id)))fail("MASTER_CATALOG_INVALID_ROWS");seen.add(row.id);}
  return rows;
 }
 function create(options){
  if(!object(options)||Object.keys(options).some(k=>!["client","lang","now","pageSize","maxPages","maxPriceLists"].includes(k)))fail("MASTER_CATALOG_INVALID_OPTIONS");
  const client=options.client,lang=options.lang==="en"?"en":"bn",now=options.now||(()=>new Date());
  const pageSize=options.pageSize??200,maxPages=options.maxPages??10,maxPriceLists=options.maxPriceLists??50;
  if(typeof now!=="function"||!Number.isSafeInteger(pageSize)||pageSize<1||pageSize>200
   ||!Number.isSafeInteger(maxPages)||maxPages<1||maxPages>50||!Number.isSafeInteger(maxPriceLists)||maxPriceLists<1||maxPriceLists>100)
   fail("MASTER_CATALOG_INVALID_OPTIONS");
  const maxRows=pageSize*maxPages;
  if(!client?.auth||typeof client.auth.getUser!=="function"||typeof client.auth.onAuthStateChange!=="function"||typeof client.schema!=="function")fail("MASTER_CATALOG_SIGNED_CLIENT_REQUIRED");
  let actor=null,revision=0,closed=false,invalidated=false;
  const subscription=client.auth.onAuthStateChange(event=>{
   if(closed||event==="INITIAL_SESSION")return;invalidated=true;revision++;
  })?.data?.subscription;
  if(!subscription||typeof subscription.unsubscribe!=="function")fail("MASTER_CATALOG_SESSION_SUBSCRIPTION_REQUIRED");
  function active(){if(closed||invalidated)fail("MASTER_CATALOG_SESSION_INVALIDATED");}
  async function authenticated(){
   active();const before=revision;let r;
   try{r=await client.auth.getUser();}catch{invalidated=true;revision++;fail("MASTER_CATALOG_SIGNED_SESSION_REQUIRED");}
   active();if(before!==revision)fail("MASTER_CATALOG_SESSION_INVALIDATED");
   if(!r||r.error||!r.data?.user){invalidated=true;revision++;fail("MASTER_CATALOG_SIGNED_SESSION_REQUIRED");}
   let who;try{who=uid(r.data.user.id);}catch(e){invalidated=true;revision++;throw e;}
   if(actor!==null&&actor!==who){invalidated=true;revision++;fail("MASTER_CATALOG_SESSION_INVALIDATED");}
   actor=who;return who;
  }
  async function rpc(name,args){
   const before=revision,who=await authenticated();let r,thrown=false;
   try{const schema=client.schema("core10");if(!schema||typeof schema.rpc!=="function")throw Error();r=await schema.rpc(name,args);}catch{thrown=true;}
   const after=await authenticated();if(before!==revision||who!==after)fail("MASTER_CATALOG_SESSION_INVALIDATED");
   if(thrown)fail("MASTER_CATALOG_RPC_UNAVAILABLE");
   if(!r||r.data==null&&!r.error)fail("MASTER_CATALOG_RPC_NO_RECEIPT");
   if(r.error){
    const message=typeof r.error==="string"?r.error:r.error.message,code=r.error.code;
    if(r.error.name==="AbortError"||/^(ECONNRESET|ECONNREFUSED|ETIMEDOUT|FETCH_ERROR)$/.test(code||"")
     ||typeof message==="string"&&/failed to fetch|fetch failed|network|connection (?:timed? ?out|reset|refused|closed)|timeout|timed out|load failed|request aborted/i.test(message))fail("MASTER_CATALOG_RPC_UNAVAILABLE");
    if(["PGRST202","42883"].includes(code))fail(code);
    fail(typeof message==="string"&&/^[A-Za-z0-9_.:-]{1,160}$/.test(message)?message:"MASTER_CATALOG_RPC_DENIED");
   }
   try{return JSON.parse(JSON.stringify(r.data));}catch{fail("MASTER_CATALOG_INVALID_RESPONSE");}
  }
  async function pages(name,args,business,checkHeader){
   let after=null;const rows=[],seen=new Set();
   for(let page=0;page<maxPages;page++){
    const result=await rpc(name,{...args,p_limit:pageSize,p_after_id:after});
    if(!object(result)||!Array.isArray(result.rows)||result.rows.length>pageSize)fail("MASTER_CATALOG_INVALID_PAGE");
    if(result.business_id!==undefined&&result.business_id!==business)fail("MASTER_CATALOG_SCOPE_MISMATCH");
    if(checkHeader)checkHeader(result);
    let last=after??0;
    for(const row of result.rows){
     scoped(row,business);const rowId=id(row.id);
     if(rowId<=last||seen.has(rowId))fail("MASTER_CATALOG_INVALID_PAGE");
     seen.add(rowId);rows.push(row);last=rowId;
    }
    if(result.next_after_id===null)return rows;
    if(!result.rows.length||!Number.isSafeInteger(result.next_after_id)||result.next_after_id!==last)fail("MASTER_CATALOG_INVALID_PAGE");
    after=last;
   }
   fail("MASTER_CATALOG_LIMIT");
  }
  async function gate(business,site){
   const c=await rpc("build01_context_v1",{});
   if(!object(c)||c.actor_uid!==actor||!Array.isArray(c.businesses)||!Array.isArray(c.sites))fail("MASTER_CATALOG_SCOPE_MISMATCH");
   const b=c.businesses.filter(x=>object(x)&&x.id===business),s=c.sites.filter(x=>object(x)&&x.id===site);
   if(b.length!==1||s.length!==1||b[0].can_manage!==true||s[0].business_id!==business||id(b[0].tenant_id)!==id(s[0].tenant_id)
    ||!Array.isArray(s[0].allowed_actions)||!s[0].allowed_actions.includes("stock.read"))fail("MASTER_CATALOG_SCOPE_DENIED");
  }
  async function load(input){
   if(!object(input)||Object.keys(input).some(k=>!["businessId","siteId"].includes(k)))fail("MASTER_CATALOG_INVALID_INPUT");
   const business=id(input.businessId),site=id(input.siteId);
   const moment=now();if(!(moment instanceof Date)||!Number.isFinite(moment.valueOf()))fail("MASTER_CATALOG_INVALID_DATE");
   const today=date(moment.toISOString().slice(0,10));
   await gate(business,site);
   const [parties,itemRows,uomResult,lists]=await Promise.all([
    pages("master_list_parties_v1",{p_business:business,p_kind:"customer",p_search:null,p_status:"active"},business),
    pages("master_list_items_v1",{p_business:business,p_search:null,p_status:"active",p_category:null},business),
    rpc("master_list_uoms_v1",{p_business:business}),
    rpc("master_list_price_lists_v1",{p_business:business,p_kind:"sales"})
   ]);
   active();
   const customers=parties.filter(p=>{
    if(!["customer","supplier","both"].includes(p.party_kind)||!["draft","active","inactive","blocked"].includes(p.status))fail("MASTER_CATALOG_INVALID_RESPONSE");
    positiveVersion(p.version);return p.status==="active"&&["customer","both"].includes(p.party_kind);
   }).map(p=>({id:p.id,label:label(p,lang),labelEn:label(p,"en"),labelBn:label(p,"bn")}));
   if(!object(uomResult))fail("MASTER_CATALOG_INVALID_RESPONSE");
   const uoms=new Map();
   for(const u of uniqueRows(uomResult.uoms,maxRows)){
    scoped(u,business);positiveVersion(u.version);
    if(typeof u.active!=="boolean"||!dimensions.has(u.dimension)||!Number.isSafeInteger(u.decimals)||u.decimals<0||u.decimals>6)fail("MASTER_CATALOG_INVALID_RESPONSE");
    if(u.active)uoms.set(u.id,u);
   }
   // Do not use conversions: an alternate selling UOM requires a richer UI.
   if(!Array.isArray(uomResult.conversions)||uomResult.conversions.length>maxRows)fail("MASTER_CATALOG_INVALID_RESPONSE");
   const items=new Map();
   for(const item of itemRows){
    if(!["draft","active","inactive"].includes(item.status))fail("MASTER_CATALOG_INVALID_RESPONSE");positiveVersion(item.version);
    if(item.status!=="active")continue;
    if(item.base_uom_id==null)continue;
    const uom=uoms.get(id(item.base_uom_id));if(!uom)continue;
    items.set(item.id,{id:item.id,label:label(item,lang),labelEn:label(item,"en"),labelBn:label(item,"bn"),uomId:uom.id,uomLabel:label(uom,lang),uomLabelEn:label(uom,"en"),uomLabelBn:label(uom,"bn"),quantityDecimals:uom.decimals,variantId:null,minQuantity:0,prices:{}});
   }
   const eligible=uniqueRows(lists,maxRows).filter(l=>{
    scoped(l,business);positiveVersion(l.version);
    if(!["sales","purchase"].includes(l.list_kind)||!["draft","active","inactive"].includes(l.status)||typeof l.currency!=="string"||!/^[A-Z]{3}$/.test(l.currency))fail("MASTER_CATALOG_INVALID_RESPONSE");
    if(l.site_id!=null)id(l.site_id);
    const from=date(l.effective_from),to=l.effective_to==null?null:date(l.effective_to);
    if(to!==null&&to<from)fail("MASTER_CATALOG_INVALID_DATE");
    return l.list_kind==="sales"&&l.status==="active"&&(l.site_id===null||l.site_id===site)&&from<=today&&(to===null||to>=today);
   });
   if(eligible.length>maxPriceLists)fail("MASTER_CATALOG_LIMIT");
   if(!customers.length||!items.size||!eligible.length)return null;
   const priceLists=[];
   for(const list of eligible){
    const rows=await pages("master_get_price_list_v1",{p_business:business,p_price_list:list.id},business,header=>{
     if(header.id!==list.id||header.currency!==list.currency||header.site_id!==list.site_id||header.list_kind!=="sales"||header.status!=="active"
      ||header.effective_from!==list.effective_from||header.effective_to!==list.effective_to||header.version!==list.version)fail("MASTER_CATALOG_STALE_PRICE_LIST");
    });
    const bases=new Map(),alternates=new Map();
    for(const row of rows){
     id(row.item_id);id(row.uom_id);positiveVersion(row.version);number(row.min_quantity);number(row.unit_price);
     if(typeof row.active!=="boolean")fail("MASTER_CATALOG_INVALID_RESPONSE");if(row.variant_id!=null)id(row.variant_id);
     if(!row.active||!items.has(row.item_id))continue;
     const item=items.get(row.item_id);
     if(row.variant_id!==null){if(!alternates.has(item.id))alternates.set(item.id,"VARIANT");continue;}
     if(row.uom_id!==item.uomId){alternates.set(item.id,"CONVERSION");continue;}
     const existing=bases.get(item.id)||[];existing.push(row);bases.set(item.id,existing);
    }
    for(const item of items.values()){
     const prices=bases.get(item.id)||[];
     if(prices.length>1||prices.length===1&&![0,1].includes(prices[0].min_quantity))fail("NOT_CONNECTED:MASTER_CATALOG_UNSUPPORTED_TIER");
     if(!prices.length){
      if(alternates.has(item.id))fail("NOT_CONNECTED:MASTER_CATALOG_UNSUPPORTED_"+alternates.get(item.id));
      continue;
     }
     item.prices[list.id]=prices[0].unit_price;item.minQuantity=Math.max(item.minQuantity,prices[0].min_quantity);
    }
    priceLists.push({id:list.id,label:label(list,lang),labelEn:label(list,"en"),labelBn:label(list,"bn"),currency:list.currency});
   }
   active();
   const common=[...items.values()].filter(item=>priceLists.every(l=>typeof item.prices[l.id]==="number"));
   if(!common.length)return null;
   return {businessId:business,siteId:site,source:"canonical_master",customers,priceLists,items:common};
  }
  return Object.freeze({load,getState:()=>Object.freeze({connected:!closed&&!invalidated,actorBound:actor!==null}),
   destroy(){if(!closed){closed=true;revision++;actor=null;subscription.unsubscribe();}}
  });
 }
 return Object.freeze({create});
});
