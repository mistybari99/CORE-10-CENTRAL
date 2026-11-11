/**
 * CORE10 A058 in-memory operator training model, NOT stock/auth source of truth.
 * All actors, business identifiers, lots, quantities, recalls are synthetic.
 * This module mirrors critical SQL-level rules in a disposable interactive demo.
 */
const future = d => {const x=new Date("2026-11-12T00:00:00Z");x.setUTCDate(x.getUTCDate()+d);return x.toISOString().slice(0,10);};
const fail = code => {throw new Error("demo_"+code);};
const actors=Object.freeze({
 owner:{name:"Portfolio owner",tenant:1,role:"owner",sites:[1001,1002,1003]},
 reviewer:{name:"QC reviewer",tenant:1,role:"reviewer",sites:[1001,1002]},
 staff:{name:"Counter staff",tenant:1,role:"staff",sites:[1001]},
 investor:{name:"Investor (no operational access)",tenant:1,role:"investor",sites:[]},
 foreign:{name:"Other tenant owner",tenant:2,role:"owner",sites:[2001]},
 revoked:{name:"Revoked user",tenant:1,role:"revoked",sites:[]}
});
const businesses=Object.freeze([
 {id:101,tenant:1,name:"Demo Sweets & Bakery",sites:[{id:1001,name:"Showroom A"},{id:1002,name:"Factory"}]},
 {id:102,tenant:1,name:"Demo Paint & Hardware",sites:[{id:1003,name:"Paint store"}]},
 {id:201,tenant:2,name:"Independent Demo Tenant",sites:[{id:2001,name:"Other branch"}]}
]);
export const DEMO_ACTORS=actors;
export const DEMO_BUSINESSES=businesses;
export const DEMO_LABELS=Object.freeze({
 pending_qc:"Pending QC",released:"Released",held:"Held",rejected:"Rejected",recalled:"Recalled"
});
export function createQualityDemo() {
 return {
  seq:6,
  lots:[
   {id:1,businessId:101,item:"Rasgolla",code:"RAS-261112-A",status:"released",
    expiry:future(5),originSiteId:1001,stock:{"1001":18,"1002":5},inspections:[{id:1,pass:true}],lastReleaseInspection:1},
   {id:2,businessId:101,item:"Sweets assortment",code:"MIX-261112-B",status:"pending_qc",
    expiry:future(3),originSiteId:1001,stock:{"1001":8},inspections:[],lastReleaseInspection:0},
   {id:3,businessId:101,item:"Cream cake",code:"CK-261111-C",status:"held",
    expiry:future(-1),originSiteId:1002,stock:{"1002":4},inspections:[{id:1,pass:false}],lastReleaseInspection:0},
   {id:4,businessId:102,item:"Paint batch",code:"PNT-261112-A",status:"released",
    expiry:future(400),originSiteId:1003,stock:{"1003":25},inspections:[{id:1,pass:true}],lastReleaseInspection:1},
   {id:5,businessId:201,item:"Foreign tenant product",code:"FOREIGN-LOT",status:"released",
    expiry:future(10),originSiteId:2001,stock:{"2001":100},inspections:[{id:1,pass:true}],lastReleaseInspection:1}
  ],
  links:[{from:1,to:2}],
  recalls:[],
  commands:{},
  audit:[],
  note:"Synthetic volatile fixture only. No Supabase, production stock or real identity."
 };
}
export function visibleBusinesses(actorKey) {
 const a=actors[actorKey];if(!a||a.role==="revoked"||a.role==="investor")return [];
 return businesses.filter(b=>b.tenant===a.tenant && (a.role==="owner"||b.sites.some(s=>a.sites.includes(s.id))));
}
export function visibleLots(state,actorKey,businessId) {
 const a=actors[actorKey];
 if(!a||a.role==="investor"||a.role==="revoked")return [];
 const b=businesses.find(x=>x.id===businessId);
 if(!b||b.tenant!==a.tenant)return [];
 return state.lots.filter(l=>l.businessId===businessId && (a.role==="owner"||a.role==="reviewer"||
   Object.keys(l.stock).some(site=>a.sites.includes(Number(site)))||a.sites.includes(l.originSiteId)));
}
export const totalUnits = l => Object.values(l.stock).reduce((a,b)=>a+b,0);
export const isExpired = (lot, today=new Date().toISOString().slice(0,10)) =>
 !!lot.expiry && lot.expiry<today;
export function demoFefo(state,businessId,item,siteId,needed) {
 if(!Number.isFinite(needed)||needed<=0)fail("invalid_fefo");
 let remaining=needed;
 return state.lots.filter(l=>l.businessId===businessId&&l.item===item&&l.status==="released"&&!isExpired(l)&&
 (l.stock[siteId]||0)>0)
 .sort((a,b)=>(a.expiry||"9999").localeCompare(b.expiry||"9999")||a.id-b.id)
 .map(l=>{const available=l.stock[siteId]||0;const suggested=Math.max(0,Math.min(remaining,available));remaining-=suggested;return {id:l.id,code:l.code,available,suggested,expiry:l.expiry};});
}
function authorize(state,actorKey,businessId,siteId,mode) {
 const a=actors[actorKey],b=businesses.find(x=>x.id===businessId);
 if(!a||!b||a.tenant!==b.tenant||a.role==="investor"||a.role==="revoked")fail("scope_denied");
 if(mode==="owner" && a.role!=="owner")fail("owner_required");
 if(mode==="reviewer"&&!["owner","reviewer"].includes(a.role))fail("reviewer_required");
 if(siteId!==undefined&&!a.sites.includes(Number(siteId)))fail("site_scope_denied");
 return a;
}
function finiteQty(q) {if(typeof q!=="number"||!Number.isFinite(q)||q<=0||q>1000000||
 Math.abs(Math.round(q*1000)-q*1000)>1e-7)fail("invalid_quantity");return q;}
function apply(state,actorKey,command) {
 if(!state||!command||!command.type||typeof command.key!=="string"||
 !/^[a-zA-Z0-9_.:-]{4,120}$/.test(command.key))fail("invalid_command");
 // Copy before mutation: invalid operations never partially change the source.
 const s=structuredClone(state);
 const sig=JSON.stringify({actorKey,command});
 if(s.commands[command.key]) {
  if(s.commands[command.key].sig!==sig)fail("idempotency_conflict");
  return {state,result:s.commands[command.key].result,replayed:true};
 }
 const b=businesses.find(x=>x.id===command.businessId);if(!b)fail("business_missing");
 const a=authorize(s,actorKey,b.id,undefined,command.type==="register"?"reviewer":"read");
 let lot=s.lots.find(l=>l.id===command.lotId), result={};
 if(command.type!=="register"&&command.type!=="close_recall"&&(!lot||lot.businessId!==b.id))fail("lot_scope_denied");
 const note=(operation,more={})=>s.audit.push({seq:++s.seq,businessId:b.id,lotId:lot?.id||null,
  actor:actorKey,operation,...more});
 if(command.type==="register") {
  authorize(s,actorKey,b.id,command.siteId,"reviewer");
  if(typeof command.code!=="string"||!/^[-A-Z0-9]{2,80}$/.test(command.code)||!command.item||
   s.lots.some(l=>l.businessId===b.id&&l.code===command.code))fail("invalid_lot");
  const qty=finiteQty(command.quantity);
  const id=Math.max(0,...s.lots.map(x=>x.id))+1;
  lot={id,businessId:b.id,item:String(command.item),code:command.code,
    status:"pending_qc",originSiteId:command.siteId,expiry:command.expiry||null,
    stock:{[command.siteId]:qty},inspections:[],lastReleaseInspection:0};
  s.lots.push(lot); result={id};note("register",{qty});
 } else if(command.type==="inspect") {
  authorize(s,actorKey,b.id,undefined,"reviewer");
  if(typeof command.pass!=="boolean")fail("invalid_inspection");
  const id=lot.inspections.length+1;
  lot.inspections.push({id,pass:command.pass});
  result={inspectionId:id};note("inspect",{pass:command.pass});
 } else if(command.type==="decision") {
  authorize(s,actorKey,b.id,undefined,"owner");
  if(!["release","hold","reject"].includes(command.decision))fail("invalid_decision");
  if(lot.status==="recalled"||(lot.status==="rejected"&&command.decision==="release"))fail("terminal_lot");
  if(command.decision==="release") {
   const last=lot.inspections.at(-1);
   if(isExpired(lot))fail("expired_lot");
   if(!last||!last.pass||last.id<=lot.lastReleaseInspection)fail("fresh_pass_required");
   lot.status="released";lot.lastReleaseInspection=last.id;
  } else lot.status=command.decision==="hold"?"held":"rejected";
  result={status:lot.status};note("decision",{status:lot.status});
 } else if(command.type==="transfer") {
  authorize(s,actorKey,b.id,command.fromSiteId,"site");
  authorize(s,actorKey,b.id,command.toSiteId,"site");
  if(command.fromSiteId===command.toSiteId)fail("same_site_transfer");
  if(lot.status!=="released"&&a.role!=="owner")fail("quarantine_transfer_owner_required");
  const qty=finiteQty(command.quantity),v=lot.stock[command.fromSiteId]||0;
  if(qty>v)fail("insufficient_lot_stock");
  lot.stock[command.fromSiteId]=v-qty;lot.stock[command.toSiteId]=(lot.stock[command.toSiteId]||0)+qty;
  result={qty};note("transfer",{from:command.fromSiteId,to:command.toSiteId,qty});
 } else if(command.type==="issue") {
  authorize(s,actorKey,b.id,command.siteId,"site");
  const qty=finiteQty(command.quantity);
  if(lot.status!=="released"||isExpired(lot))fail("not_sellable");
  if((lot.stock[command.siteId]||0)<qty)fail("insufficient_lot_stock");
  lot.stock[command.siteId]-=qty;result={qty};note("issue",{siteId:command.siteId,qty});
 } else if(command.type==="dispose") {
  authorize(s,actorKey,b.id,undefined,"owner");
  const qty=finiteQty(command.quantity);
  if(lot.status==="released"&&!isExpired(lot))fail("hold_required");
  if((lot.stock[command.siteId]||0)<qty)fail("insufficient_lot_stock");
  lot.stock[command.siteId]-=qty;result={qty};note("disposal",{siteId:command.siteId,qty});
 } else if(command.type==="link") {
  authorize(s,actorKey,b.id,undefined,"owner");
  const child=s.lots.find(x=>x.id===command.childLotId&&x.businessId===b.id);
  if(!child||child.id===lot.id)fail("genealogy_scope_denied");
  const seen=new Set(),stack=[child.id];
  while(stack.length){const at=stack.pop();if(at===lot.id)fail("genealogy_cycle");
   if(!seen.has(at)){seen.add(at);for(const g of s.links.filter(x=>x.from===at))stack.push(g.to);}}
  if(s.links.some(x=>x.from===lot.id&&x.to===child.id))fail("duplicate_link");
  s.links.push({from:lot.id,to:child.id});result={childId:child.id};note("genealogy_link",{childId:child.id});
 } else if(command.type==="recall") {
  authorize(s,actorKey,b.id,undefined,"owner");
  if(typeof command.reason!=="string"||command.reason.length<5)fail("invalid_reason");
  const seen=new Set(),stack=[lot.id];
  while(stack.length){const at=stack.pop();if(!seen.has(at)){seen.add(at);for(const g of s.links.filter(x=>x.from===at))stack.push(g.to);}}
  const affected=[...seen];for(const affectedId of affected){const l=s.lots.find(x=>x.id===affectedId&&x.businessId===b.id);
   if(l)l.status="recalled";}
  const id=s.recalls.length+1;
  s.recalls.push({id,businessId:b.id,rootLotId:lot.id,affected,reason:command.reason,
   severity:command.severity||"internal",status:"active"});
  result={recallId:id,affected};note("recall",{affected});
 } else if(command.type==="close_recall") {
  authorize(s,actorKey,b.id,undefined,"owner");
  const recall=s.recalls.find(x=>x.id===command.recallId&&x.businessId===b.id);
  if(!recall||recall.status!=="active")fail("recall_missing");
  if(recall.affected.some(x=>{const l=s.lots.find(z=>z.id===x);return l&&totalUnits(l)>0;}))fail("recall_stock_remaining");
  recall.status="closed";result={status:"closed"};note("recall_close",{recallId:recall.id});
 } else fail("unknown_command");
 s.commands[command.key]={sig,result};
 return {state:s,result,replayed:false};
}
export function applyQualityDemo(state,actorKey,command){return apply(state,actorKey,command);}
