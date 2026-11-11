/* C10-A055 Assets & Maintenance UI (Assets, Work Orders, Schedule, Breakdown, Reports, Settings).
 * All data and all authority come from the signed RPC adapter (CORE10_AM_API). DOM nodes are built with textContent only:
 * there is no HTML-string sink for data, no eval, no inline script. Capability flags from am_whoami_v1 are ADVISORY hints;
 * the database re-checks every action. No demo data lives in this file: if the API is unreachable an error state is shown.
 */
(function(){"use strict";
const API=window.CORE10_AM_API,CAT=window.CORE10_AM_CATALOG;
const SCREEN=document.body.dataset.screen||"assets";
const NAV=[["assets","core10-asset-maintenance-assets.html","Assets","সম্পদ"],["workorders","core10-asset-maintenance-workorders.html","Work orders","কাজের আদেশ"],
 ["schedule","core10-asset-maintenance-schedule.html","Schedule","সূচি"],["breakdown","core10-asset-maintenance-breakdown.html","Breakdown","বিকল"],
 ["reports","core10-asset-maintenance-reports.html","Reports","রিপোর্ট"],["settings","core10-asset-maintenance-settings.html","Settings","সেটিংস"]];
const LANG_KEY="c10_am_lang",BIZ_KEY="c10_am_biz";
const state={api:null,biz:null,site:null,lang:"en",who:null,cat:null,busy:false,assetOpts:null,screenFn:null};
const $=(id)=>document.getElementById(id);
const T=(en,bn)=>(state.lang==="bn"&&bn)?bn:en;
const lab=(kind,code)=>CAT.label(kind,code,state.lang);
function store(op,k,v){try{return op==="get"?localStorage.getItem(k):localStorage.setItem(k,v)}catch(e){return null}}
function h(tag,props,...kids){const e=document.createElement(tag);
 for(const [k,v] of Object.entries(props||{})){if(v==null||v===false)continue;
  if(k==="class")e.className=v;else if(k==="text")e.textContent=v;else if(k.startsWith("on"))e.addEventListener(k.slice(2),v);
  else if(v===true)e.setAttribute(k,"");else e.setAttribute(k,String(v));}
 for(const c of kids.flat(3)){if(c==null||c===false)continue;e.append(c&&c.nodeType?c:document.createTextNode(String(c)))}
 return e}
const chip=(t,tone)=>h("span",{class:"chip "+(tone||""),text:String(t)});
const dash="—";
const val=(v)=>v==null||v===""?dash:(typeof v==="boolean"?(v?T("Yes","হ্যাঁ"):T("No","না")):String(v));
const num=(v,d)=>v==null||v===""||isNaN(Number(v))?dash:Number(v).toLocaleString("en-US",{maximumFractionDigits:d==null?2:d});
const dt=(s)=>s?String(s).replace("T"," ").slice(0,16):dash;
const dd=(s)=>s?String(s).slice(0,10):dash;
const pad=(n)=>String(n).padStart(2,"0");
const today=()=>new Date(Date.now()+6*3600e3).toISOString().slice(0,10);
const addDays=(d,n)=>{const x=new Date(d+"T00:00:00Z");x.setUTCDate(x.getUTCDate()+n);return x.toISOString().slice(0,10)};
const nowLocalInput=()=>{const d=new Date();return d.getFullYear()+"-"+pad(d.getMonth()+1)+"-"+pad(d.getDate())+"T"+pad(d.getHours())+":"+pad(d.getMinutes())};
const arr=(o,...names)=>{if(Array.isArray(o))return o;for(const n of names)if(o&&Array.isArray(o[n]))return o[n];return[]};
const eq=(a,b)=>API.stable(a)===API.stable(b);
const toneOf=(s)=>({active:"good",ok:"good",applied:"good",approved:"good",APPROVED:"good",VERIFIED:"good",COMPLETED:"good",CLOSED:"dim",accepted:"good",settled:"good",met:"good",pass:"good",
 breakdown:"bad",BREAKDOWN:"bad",overdue:"bad",breached:"bad",rejected:"bad",fail:"bad",critical:"bad",expired:"bad",CANCELLED:"dim",cancelled:"dim",retired:"dim",disposed:"dim",
 under_maintenance:"warn",pending:"warn",due:"warn",due_soon:"warn",at_risk:"warn",expiring:"warn",IN_PROGRESS:"warn",SUBMITTED:"warn",high:"warn",meter_missing:"warn",deferred:"dim",idle:"dim",draft:"dim",DRAFT:"dim"}[s]||"");

/* ---------- banner, errors ---------- */
function status(msg,tone,extra){const n=$("am-status");if(!n)return;n.textContent="";n.dataset.tone=tone||"ok";n.append(document.createTextNode(msg));if(extra)n.append(" ",extra)}
function errMsg(e){const code=e&&e.code||"AM_RPC_UNAVAILABLE";return CAT.errorMessage(code,state.lang)+(/^am_|^[A-Z_]+$/.test(code)?" ["+code+"]":"")}
function fail(e,box){
 const code=e&&e.code,m=errMsg(e);
 const stale=code==="am_stale_version"||code==="am_idempotency_conflict"||code==="am_policy_stale_rev";
 status(m,"error",stale?h("button",{type:"button",class:"outline",id:"am-reload",text:T("Reload data","ডেটা রিলোড"),onclick:()=>reloadScreen()}):null);
 if(box){box.textContent=m;box.hidden=false}
}
function reloadScreen(){closeModal();if(state.screenFn)return state.screenFn()}

/* ---------- capabilities (advisory) ---------- */
function sitesList(){return arr(state.who,"sites")}
function can(cap,site){
 const w=state.who;if(!w)return false;
 if(w.is_owner===true)return true;
 if(site!=null){const s=sitesList().find(x=>x.id===site);return !!(s&&arr(s,"caps").includes(cap))||arr(w,"business_caps").includes(cap)}
 return arr(w,"business_caps").includes(cap)||sitesList().some(s=>arr(s,"caps").includes(cap));
}
const isOwner=()=>!!(state.who&&state.who.is_owner===true);
const isTenantOwner=()=>!!(state.who&&state.who.level==="tenant_owner");
function siteOptsFor(cap,blank){
 const list=sitesList().filter(s=>!cap||can(cap,s.id));
 return[...(blank?[["",blank]]:[]),...list.map(s=>[String(s.id),s.label||("#"+s.id)])];
}
function siteName(id){const s=sitesList().find(x=>x.id===id)||arr(state.cat,"sites").find(x=>x.id===id);return s?(s.label||s.name||("#"+id)):(id==null?dash:"#"+id)}
function categories(){return arr(state.cat,"categories")}
function catName(c){return c?((state.lang==="bn"&&c.name_bn)||c.name||c.code):dash}
function catById(id){return categories().find(c=>c.id===id)}
function codesOf(kind,withInactive){return arr(state.cat,"codes").filter(c=>c.kind===kind&&(withInactive||c.active!==false))}
function codeOpts(kind,blank){return[...(blank?[["",blank]]:[]),...codesOf(kind).map(c=>[c.code,c.code+" · "+((state.lang==="bn"&&c.label_bn)||c.label)])]}
function enumOpts(kind,codes,blank){return[...(blank?[["",blank]]:[]),...codes.map(c=>[String(c),lab(kind,c)])]}

/* ---------- call wrapper ---------- */
async function rd(name,params){return state.api.call(name,Object.assign({p_business:state.biz},params||{}))}
async function act(name,params,okEn,okBn,box){
 if(state.busy)return null;state.busy=true;document.body.dataset.busy="1";
 try{const r=await state.api.call(name,Object.assign({p_business:state.biz},params||{}));
  const extra=r&&(r.wo_no||r.asset_no||r.claim_no||r.number)?" "+(r.wo_no||r.asset_no||r.claim_no||r.number):"";
  status(T(okEn,okBn||okEn)+extra+(r&&r.status?" ["+r.status+"]":""),"ok");return r}
 catch(e){fail(e,box);return null}
 finally{state.busy=false;delete document.body.dataset.busy}
}
async function safe(fn){try{return await fn()}catch(e){fail(e);return null}}

/* ---------- DOM building blocks ---------- */
function table(cols,rows,empty,id){
 if(!rows.length)return h("p",{class:"muted",text:empty||T("Nothing to show.","দেখানোর মতো কিছু নেই।")});
 return h("div",{class:"tbl-wrap",id},h("table",null,h("thead",null,h("tr",null,cols.map(c=>h("th",{text:c[0]})))),
  h("tbody",null,rows.map(r=>h("tr",null,cols.map(c=>h("td",{"data-label":c[0]},c[1](r))))))));
}
function panel(title,body,right,id){return h("section",{class:"panel",id},h("div",{class:"panel-title"},h("h2",{text:title}),right||null),h("div",{class:"panel-body"},body))}
function btn(text,fn,cls,id,extra){return h("button",Object.assign({type:"button",class:cls||"",id,onclick:fn,text},extra||{}))}
function kv(pairs){const dl=h("dl",{class:"kv"});for(const [k,v] of pairs){if(v===undefined)continue;dl.append(h("dt",{text:k}),h("dd",null,v&&v.nodeType?v:val(v)))}return dl}
function metrics(pairs){return h("div",{class:"metrics"},pairs.map(([k,v])=>h("div",null,h("small",{text:k}),h("b",{text:val(v)}))))}
function sel(id,options,value,extra){const s=h("select",Object.assign({id},extra||{}));for(const [v,t] of options)s.append(h("option",{value:v,text:t}));if(value!=null)s.value=String(value);return s}
function filterRow(items){return h("div",{class:"row filters"},items)}
function labeled(label,input,hint){return h("label",{class:"fld"},h("span",{text:label}),input,hint?h("small",{text:hint}):null)}
function note(text,cls){return h("p",{class:"note "+(cls||""),text})}

/* ---------- modal + form builder ---------- */
let modalEl=null,lastFocus=null;
function closeModal(){if(modalEl){modalEl.remove();modalEl=null;document.body.classList.remove("modal-open");if(lastFocus&&lastFocus.focus)try{lastFocus.focus()}catch(e){}}}
function openModal(title,content,id){
 closeModal();lastFocus=document.activeElement;
 const t=h("h2",{id:"am-modal-title",text:title});
 const box=h("div",{class:"modal",role:"dialog","aria-modal":"true","aria-labelledby":"am-modal-title",id:id||"am-modal"},
  h("div",{class:"modal-head"},t,btn("×",closeModal,"outline close","am-modal-close",{"aria-label":T("Close","বন্ধ")})),h("div",{class:"modal-body"},content));
 modalEl=h("div",{class:"modal-back",onmousedown:(e)=>{if(e.target===modalEl)closeModal()}},box);
 modalEl.addEventListener("keydown",(e)=>{
  if(e.key==="Escape"){e.stopPropagation();closeModal();return}
  if(e.key==="Tab"){const f=[...box.querySelectorAll("button,input,select,textarea,a[href]")].filter(x=>!x.disabled&&!x.hidden&&x.offsetParent!==null);
   if(!f.length)return;const a=f[0],z=f[f.length-1];
   if(e.shiftKey&&document.activeElement===a){e.preventDefault();z.focus()}else if(!e.shiftKey&&document.activeElement===z){e.preventDefault();a.focus()}}});
 document.body.append(modalEl);document.body.classList.add("modal-open");
 const first=box.querySelector("input:not([type=hidden]),select,textarea");(first||box.querySelector("button")).focus();
 return box;
}
const REQ=(l)=>T(l+" is required.",l+" আবশ্যক।");
/* field: {n,l:[en,bn],t:text|num|date|dt|bool|select|textarea|json|rows|uuid,opts,val,req,min,max,int,step,hint,cols,rows} */
function buildForm(fields,opt){
 const p=opt.prefix||"f-",F=(f)=>T(f.l[0],f.l[1]);
 const form=h("form",{id:opt.id,novalidate:true,class:"form"});
 const err=h("div",{class:"form-err",role:"alert",hidden:true,id:p+"err"});
 const grid=h("div",{class:"grid"});
 const get={};
 for(const f of fields){
  const id=p+f.n;let input,wide=false;
  if(f.t==="select"){input=sel(id,f.opts,f.val==null?(f.opts[0]&&f.opts[0][0]):f.val);get[f.n]=()=>{const v=input.value;return v===""?null:(f.int?Number(v):v)}}
  else if(f.t==="textarea"||f.t==="json"){wide=true;input=h("textarea",{id,rows:f.rows||3,maxlength:f.max||2000});input.value=f.val==null?"":f.val;
   get[f.n]=()=>{const v=input.value.trim();if(f.t==="textarea")return v||null;if(!v)return null;try{const j=JSON.parse(v);if(typeof j!=="object"||j===null||Array.isArray(j))throw 0;return j}catch(x){throw new Error(T("Invalid JSON object in ","অবৈধ JSON অবজেক্ট: ")+F(f))}}}
  else if(f.t==="bool"){input=h("input",{id,type:"checkbox",class:"cb"});input.checked=!!f.val;get[f.n]=()=>input.checked}
  else if(f.t==="rows"){wide=true;const host=h("div",{class:"rows-host",id});
   const addRow=(v)=>{const r=h("div",{class:"rep-row"});const cells={};
    for(const c of f.cols){const cid=id+"-"+host.children.length+"-"+c.n;let ci;
     if(c.t==="select")ci=sel(cid,c.opts,v&&v[c.n]!=null?v[c.n]:c.opts[0][0],{"aria-label":c.l[state.lang==="bn"?1:0]});
     else if(c.t==="bool"){ci=h("input",{id:cid,type:"checkbox",class:"cb","aria-label":c.l[state.lang==="bn"?1:0]});ci.checked=v&&v[c.n]!=null?!!v[c.n]:c.val!==false}
     else{ci=h("input",{id:cid,type:c.t==="num"?"number":"text",step:c.t==="num"?"any":null,placeholder:c.l[state.lang==="bn"?1:0],"aria-label":c.l[state.lang==="bn"?1:0],maxlength:c.max||80});if(v&&v[c.n]!=null)ci.value=v[c.n]}
     cells[c.n]=ci;r.append(h("div",{class:"rep-cell"},h("small",{text:c.l[state.lang==="bn"?1:0]}),ci))}
    r.append(btn("×",()=>r.remove(),"outline",null,{"aria-label":T("Remove row","সারি মুছুন")}));r._cells=cells;host.append(r)};
   for(const v of (f.val||[]))addRow(v);
   input=h("div",null,host,btn(T("+ Add row","+ সারি যোগ"),()=>addRow(null),"outline",id+"-add"));
   get[f.n]=()=>[...host.children].map(r=>{const o={};let any=false;
    for(const c of f.cols){const e=r._cells[c.n];let v;
     if(c.t==="bool")v=e.checked;else{v=e.value.trim();if(c.t==="num")v=v===""?null:Number(v);else if(c.t==="select")v=v===""?null:v;else v=v||null;if(v!==null&&v!==""&&!(c.t==="select"&&c.keep))any=true}
     if(c.t==="num"&&v!==null&&!Number.isFinite(v))throw new Error(T("Invalid number in ","অবৈধ সংখ্যা: ")+F(f));
     o[c.n]=v}
    return any?o:null}).filter(Boolean)}
  else{const type=f.t==="num"?"number":f.t==="date"?"date":f.t==="dt"?"datetime-local":"text";
   input=h("input",{id,type,step:f.t==="num"?(f.step||"any"):null,maxlength:f.max||200,autocomplete:"off",spellcheck:"false"});
   if(f.val!=null)input.value=f.val;
   get[f.n]=()=>{const v=input.value.trim();if(v==="")return null;
    if(f.t==="num"){const n=Number(v);if(!Number.isFinite(n))throw new Error(T("Invalid number: ","অবৈধ সংখ্যা: ")+F(f));return n}
    if(f.t==="dt"){const d=new Date(v);if(isNaN(d.getTime()))throw new Error(T("Invalid time: ","অবৈধ সময়: ")+F(f));return d.toISOString()}
    return v}}
  if(f.req&&f.t!=="rows"&&f.t!=="bool")input.setAttribute("aria-required","true");
  const lbl=h("label",{class:"fld"+(wide?" wide":"")+(f.t==="bool"?" bool":"")},h("span",{text:F(f)+(f.req?" *":"")}),input,f.hint?h("small",{text:T(f.hint[0],f.hint[1])}):null);
  if(f.t==="rows"){lbl.removeAttribute("for")}
  grid.append(lbl);
 }
 const submit=h("button",{type:"submit",class:"primary",id:p+"submit",text:opt.submitText||T("Save","সংরক্ষণ")});
 form.append(grid,err,h("div",{class:"actions"},submit,opt.cancel===false?null:btn(T("Cancel","বাতিল"),opt.onCancel||closeModal,"outline",p+"cancel")));
 function collect(){
  const out={};
  for(const f of fields){
   let v;try{v=get[f.n]()}catch(x){return{error:x.message}}
   if(f.req&&f.t!=="bool"&&(v==null||v===""||(Array.isArray(v)&&!v.length)))return{error:REQ(F(f))};
   if(f.min&&typeof v==="string"&&v.length<f.min)return{error:T(F(f)+" needs at least "+f.min+" characters.",F(f)+" কমপক্ষে "+f.min+" অক্ষর হতে হবে।")};
   out[f.n]=v;
  }
  return{values:out};
 }
 form.addEventListener("submit",async(ev)=>{ev.preventDefault();err.hidden=true;
  const r=collect();if(r.error){err.textContent=r.error;err.hidden=false;return}
  submit.disabled=true;try{await opt.onSubmit(r.values,err)}finally{submit.disabled=false}});
 return{form,collect,err};
}
const REASON=(extra)=>Object.assign({n:"reason",l:["Reason","কারণ"],t:"textarea",req:true,min:5,max:500,rows:2,hint:["At least 5 characters; recorded in the audit log.","কমপক্ষে ৫ অক্ষর; অডিট লগে রেকর্ড হয়।"]},extra||{});
/* open a modal form; onSubmit(values) returns truthy on success (closes modal + refresh) */
function modalForm(title,fields,onSubmit,submitText,id){
 const f=buildForm(fields,{prefix:"f-",id:"am-form",submitText,onSubmit:async(v,err)=>{const ok=await onSubmit(v,err);if(ok){closeModal();return}}});
 return openModal(title,f.form,id);
}

/* ---------- assets lookup cache (for pickers) ---------- */
async function assetOptions(force){
 if(state.assetOpts&&!force)return state.assetOpts;
 const r=await rd("am_list_assets_v1",{p_filters:null,p_limit:200,p_offset:0});
 state.assetOpts=arr(r,"items");return state.assetOpts;
}
const assetLabel=(a)=>(a.asset_no||("#"+a.id))+" · "+a.name;
async function assetPicker(blank,filter){
 const list=(await assetOptions()).filter(filter||(()=>true));
 return[...(blank?[["",blank]]:[]),...list.map(a=>[String(a.id),assetLabel(a)])];
}

/* ---------- generic (report) renderer: scalars -> metrics, arrays of objects -> tables, nested -> sections ---------- */
const ADVISORY_RX=/depreciat|book_value|nbv|valuation|residual/i,MT_RX=/mttr|mtbf/i;
function fieldTitle(k){let l=CAT.fieldLabel(k,state.lang);if(ADVISORY_RX.test(k)&&!/ADVISORY|পরামর্শ/.test(l))l+=" ("+T("ADVISORY","পরামর্শমূলক")+")";return l}
function scalarCell(k,v,parent){
 if(v==null){if(MT_RX.test(k))return h("span",{class:"muted",text:T("Insufficient sample","অপর্যাপ্ত নমুনা")});return dash}
 if(typeof v==="boolean")return chip(v?T("yes","হ্যাঁ"):T("no","না"),v?"good":"bad");
 if(typeof v==="number")return String(Math.round(v*1000)/1000);
 if(typeof v==="object")return JSON.stringify(v).slice(0,300);
 if(/(^|_)(status|state|kind|priority|level)$/.test(k)||k==="result")return chip(String(v).replace(/_/g," "),toneOf(v));
 if(/_at$|^at$/.test(k))return dt(v);
 return String(v);
}
function renderData(d,depth){
 depth=depth||0;const out=h("div",{class:"gen"});
 if(Array.isArray(d)){out.append(listTable(d));return out}
 if(d==null||typeof d!=="object"){out.append(h("p",{text:val(d)}));return out}
 const scal=[],tabs=[],subs=[];
 for(const [k,v] of Object.entries(d)){
  if(Array.isArray(v)){if(v.length&&typeof v[0]==="object"&&v[0]!==null)tabs.push([k,v]);else scal.push([k,v.length?v.join(", "):""])}
  else if(v!==null&&typeof v==="object"){if(depth<3)subs.push([k,v]);else scal.push([k,JSON.stringify(v)])}
  else scal.push([k,v]);
 }
 if(scal.length)out.append(h("div",{class:"metrics"},scal.map(([k,v])=>h("div",null,h("small",{text:fieldTitle(k)}),h("b",null,scalarCell(k,v,d))))));
 for(const [k,v] of tabs)out.append(h("h4",{text:fieldTitle(k)+" ("+v.length+")"}),listTable(v));
 for(const [k,v] of subs)out.append(h("h4",{text:fieldTitle(k)}),renderData(v,depth+1));
 if(!scal.length&&!tabs.length&&!subs.length)out.append(h("p",{class:"muted",text:T("No data.","কোনো তথ্য নেই।")}));
 return out;
}
function listTable(rows){
 const objs=rows.filter(r=>r&&typeof r==="object");
 if(!objs.length)return h("p",{class:"muted",text:T("Nothing to show.","দেখানোর মতো কিছু নেই।")});
 const keys=[];for(const r of objs.slice(0,50))for(const k of Object.keys(r))if(!keys.includes(k)&&keys.length<12)keys.push(k);
 return table(keys.map(k=>[fieldTitle(k),r=>{const v=r[k];return v!==null&&typeof v==="object"?JSON.stringify(v).slice(0,160):scalarCell(k,v,r)}]),objs);
}

/* ---------- shell + boot ---------- */
function parseQuery(){
 const q=new URLSearchParams(location.search);
 return{biz:API.parseBusinessId(q.get("biz")),site:API.parseBusinessId(q.get("site")),wo:API.parseBusinessId(q.get("wo")),asset:API.parseBusinessId(q.get("asset"))};
}
function navHref(file){return"./"+file+(state.biz?"?biz="+state.biz:"")}
function applyLang(){document.documentElement.lang=state.lang==="bn"?"bn":"en"}
async function shell(){
 const root=$("am-root");root.textContent="";applyLang();
 const nav=h("nav",{class:"rail-nav","aria-label":T("Assets & Maintenance navigation","রক্ষণাবেক্ষণ নেভিগেশন")},
  NAV.map(n=>h("a",{href:navHref(n[1]),class:n[0]===SCREEN?"active":null,"aria-current":n[0]===SCREEN?"page":null,"data-nav":n[0]},h("b",{text:T(n[2],n[3])}))));
 const bizIn=h("input",{id:"am-biz",type:"text",inputmode:"numeric",autocomplete:"off","aria-label":T("Business ID","ব্যবসার আইডি"),value:state.biz||"",maxlength:15,placeholder:"101"});
 const bizForm=h("form",{class:"biz",id:"am-biz-form",onsubmit:(e)=>{e.preventDefault();const b=API.parseBusinessId(bizIn.value);
   if(!b){status(CAT.errorMessage("INVALID_BUSINESS_ID",state.lang),"error");return}
   store("set",BIZ_KEY,String(b));location.href="./"+NAV.find(n=>n[0]===SCREEN)[1]+"?biz="+b}},
  h("span",{text:T("Business","ব্যবসা")}),h("div",{class:"inline"},bizIn,h("button",{type:"submit",id:"am-biz-go",class:"outline",text:T("Open","খুলুন")})));
 const siteSel=sel("am-site",[["",T("All sites","সব সাইট")]],"",{"aria-label":T("Site","সাইট")});
 siteSel.addEventListener("change",()=>{state.site=siteSel.value?Number(siteSel.value):null;if(state.screenFn)state.screenFn()});
 const lang=btn(state.lang==="bn"?"English":"বাংলা",()=>{state.lang=state.lang==="bn"?"en":"bn";store("set",LANG_KEY,state.lang);rebuild()},"outline","am-lang",{"aria-label":T("Switch language","ভাষা বদলান")});
 root.append(h("div",{class:"am-layout"},
  h("aside",{class:"rail"},h("div",{class:"brand"},"CORE ",h("b",{text:"10"}),h("small",{text:"ASSETS & MAINTENANCE · A055"})),nav,
   h("div",{class:"rail-note",text:T("Authority comes from the server. Money fields are advisory; nothing here posts to stock, ledger or payroll.","ক্ষমতা সার্ভার থেকে আসে। অর্থের ঘর পরামর্শমূলক; এখান থেকে স্টক, লেজার বা বেতনে কিছু পোস্ট হয় না।")})),
  h("main",{id:"am-main"},h("div",{class:"topline"},h("span",{text:"ASSETS / WORK ORDERS / SCHEDULE / DOWNTIME"}),h("span",{id:"am-level",class:"badge",text:"…"})),
   h("div",{class:"headline"},h("h1",{id:"am-title"}),h("div",{class:"controls"},bizForm,labeled(T("Site","সাইট"),siteSel),lang)),
   h("div",{id:"am-status",role:"status","aria-live":"polite","data-tone":"info",text:T("Verifying signed session…","সাইন-ইন সেশন যাচাই হচ্ছে…")}),h("div",{id:"am-body"}))));
}
function fillSiteSelect(){
 const s=$("am-site");if(!s)return;s.textContent="";
 for(const [v,t] of [["",T("All sites","সব সাইট")],...sitesList().map(x=>[String(x.id),x.label||("#"+x.id)])])s.append(h("option",{value:v,text:t}));
 s.value=state.site!=null&&sitesList().some(x=>x.id===state.site)?String(state.site):"";if(s.value==="")state.site=null;
}
async function rebuild(){await shell();fillSiteSelect();if(state.who){$("am-level").textContent=lab("role",state.who.level==="business_owner"||state.who.level==="tenant_owner"?(state.who.level):"supervisor");setNavVisibility();}
 if(state.screenFn)await state.screenFn();else if(!state.biz)noBusiness()}
function noBusiness(){status(T("Enter a business ID (or open this page with ?biz=<id>).","একটি ব্যবসার আইডি দিন (বা ?biz=<id> সহ পেজ খুলুন)।"),"info");$("am-body").textContent="";$("am-title").textContent=T(NAV.find(n=>n[0]===SCREEN)[2],NAV.find(n=>n[0]===SCREEN)[3])}
function setNavVisibility(){
 for(const a of document.querySelectorAll("[data-nav]")){const k=a.dataset.nav;
  const hide=(k==="reports"&&!can("reports")&&!can("audit_read"))||(k==="breakdown"&&!can("report")&&!can("downtime_write"));
  if(hide)a.setAttribute("hidden","");else a.removeAttribute("hidden")}
}
async function boot(){
 state.lang=store("get",LANG_KEY)==="bn"?"bn":(store("get",LANG_KEY)==="en"?"en":(/^bn/i.test(navigator.language||"")?"bn":"en"));
 const q=parseQuery();state.biz=q.biz;state.site=q.site;
 if(!state.biz){const last=API.parseBusinessId(store("get",BIZ_KEY));if(last){state.biz=last}}
 await shell();
 if(!state.biz){noBusiness();return}
 try{
  const cfg=window.BOS_CONFIG,lib=window.supabase;
  if(!cfg||!cfg.url||!cfg.key||!lib||typeof lib.createClient!=="function")throw Object.assign(new Error("SIGNED_SUPABASE_CLIENT_REQUIRED"),{code:"SIGNED_SUPABASE_CLIENT_REQUIRED"});
  state.api=API.create({client:lib.createClient(cfg.url,cfg.key)});
  state.screenFn=load;await load(true);
 }catch(e){fail(e);$("am-body").textContent="";$("am-body").append(h("div",{class:"error-state",role:"alert"},h("h2",{text:T("Cannot load Assets & Maintenance","রক্ষণাবেক্ষণ লোড করা যায়নি")}),h("p",{text:errMsg(e)}),btn(T("Retry","আবার চেষ্টা"),()=>location.reload(),"primary","am-retry")))}
}
async function load(first){
 const body=$("am-body");status(T("Loading…","লোড হচ্ছে…"),"info");
 try{
  state.who=await rd("am_whoami_v1");
  state.cat=await rd("am_list_catalog_v1");
  state.assetOpts=null;
  if(first){const q=parseQuery();if(q.site!=null&&sitesList().some(s=>s.id===q.site))state.site=q.site}
  fillSiteSelect();setNavVisibility();
  $("am-level").textContent=lab("role",state.who.level==="tenant_owner"||state.who.level==="business_owner"?state.who.level:(arr(state.who,"roles")[0]||"reporter"));
  body.textContent="";
  await SCREENS[SCREEN](body);
  status(T("Ready · business #","প্রস্তুত · ব্যবসা #")+state.biz,"ok");
 }catch(e){fail(e);body.textContent="";body.append(h("div",{class:"error-state",role:"alert",id:"am-error-state"},h("h2",{text:T("Could not load data","ডেটা লোড করা যায়নি")}),h("p",{text:errMsg(e)}),btn(T("Retry","আবার চেষ্টা"),()=>load(),"primary","am-retry")))}
}
const SCREENS={};
/* =====================================================================  ASSETS  ===================================================================== */
const ASSET_STATUSES=["planned","active","under_maintenance","breakdown","idle","retired","disposed"];
const OWNERSHIPS=["owned","leased","rented","client_owned","consignment"];
const TEXT_FIELDS=["location_note","serial_no","model","manufacturer","provenance","supplier_name","supplier_ref","purchase_order_ref","custodian_ref","acquisition_date","commission_date"];
function assetFormFields(a,parents){
 const c=!a,B=(en,bn)=>[en,bn];
 const f=[
  {n:"name",l:B("Name","নাম"),t:"text",req:true,val:a&&a.name,max:120},
  {n:"category_id",l:B("Category","ক্যাটাগরি"),t:"select",int:true,req:true,opts:categories().filter(x=>x.active!==false).map(x=>[String(x.id),x.code+" · "+catName(x)]),val:a&&a.category_id}];
 if(c)f.push({n:"site_id",l:B("Site","সাইট"),t:"select",int:true,req:true,opts:siteOptsFor("asset_write"),val:state.site},
  {n:"status",l:B("Initial status","প্রাথমিক অবস্থা"),t:"select",opts:[["active",lab("asset_status","active")],["planned",lab("asset_status","planned")]],val:"active"});
 f.push({n:"criticality",l:B("Criticality (1-5)","গুরুত্ব (১-৫)"),t:"select",int:true,opts:[1,2,3,4,5].map(x=>[String(x),String(x)]),val:a?a.criticality:3},
  {n:"serial_no",l:B("Serial no.","সিরিয়াল নং"),t:"text",val:a&&a.serial_no,max:64},
  {n:"manufacturer",l:B("Manufacturer","নির্মাতা"),t:"text",val:a&&a.manufacturer,max:80},
  {n:"model",l:B("Model","মডেল"),t:"text",val:a&&a.model,max:80},
  {n:"ownership",l:B("Ownership","মালিকানা"),t:"select",opts:enumOpts("ownership",OWNERSHIPS),val:a&&a.ownership||"owned"},
  {n:"location_note",l:B("Location note","অবস্থানের নোট"),t:"text",val:a&&a.location_note,max:200},
  {n:"parent_asset_id",l:B("Parent assembly","প্যারেন্ট অ্যাসেম্বলি"),t:"select",int:true,opts:parents,val:a&&a.parent_asset_id!=null?a.parent_asset_id:""},
  {n:"quantity",l:B("Quantity","পরিমাণ"),t:"num",val:a&&a.quantity,hint:B("Default 1","ডিফল্ট ১")},
  {n:"acquisition_date",l:B("Acquired on","অর্জনের তারিখ"),t:"date",val:a&&dd(a.acquisition_date)===dash?"":a&&dd(a.acquisition_date)},
  {n:"commission_date",l:B("Commissioned on","চালুর তারিখ"),t:"date",val:a&&dd(a.commission_date)===dash?"":a&&dd(a.commission_date)},
  {n:"acquisition_cost",l:B("Acquisition cost (advisory)","অর্জন মূল্য (পরামর্শমূলক)"),t:"num",val:a&&a.acquisition_cost},
  {n:"supplier_name",l:B("Supplier","সরবরাহকারী"),t:"text",val:a&&a.supplier_name,max:120},
  {n:"supplier_ref",l:B("Supplier ref.","সরবরাহকারী রেফ."),t:"text",val:a&&a.supplier_ref,max:60},
  {n:"purchase_order_ref",l:B("Purchase order ref. (read-only link)","ক্রয় আদেশ রেফ. (শুধু রেফারেন্স)"),t:"text",val:a&&a.purchase_order_ref,max:40},
  {n:"custodian_ref",l:B("Custodian ref.","দায়িত্বপ্রাপ্ত রেফ."),t:"text",val:a&&a.custodian_ref,max:40},
  {n:"provenance",l:B("Provenance / notes","উৎস / নোট"),t:"text",val:a&&a.provenance,max:300},
  {n:"custom_attrs",l:B("Custom attributes (JSON object)","কাস্টম অ্যাট্রিবিউট (JSON)"),t:"json",rows:2,val:a&&a.custom_attrs&&Object.keys(a.custom_attrs).length?JSON.stringify(a.custom_attrs):""});
 if(c){
  f.push({n:"meters",l:B("Meters","মিটার"),t:"rows",val:[],cols:[{n:"code",l:B("Code","কোড"),t:"text",max:16},{n:"unit",l:B("Unit","একক"),t:"select",keep:true,opts:enumOpts("meter_unit",["hours","km","cycles","units"])},{n:"reading",l:B("Initial reading","প্রাথমিক রিডিং"),t:"num"}]},
   {n:"w_supplier_name",l:B("Warranty supplier","ওয়ারেন্টি সরবরাহকারী"),t:"text",max:120},{n:"w_supplier_ref",l:B("Warranty ref.","ওয়ারেন্টি রেফ."),t:"text",max:60},
   {n:"w_starts_on",l:B("Warranty starts","ওয়ারেন্টি শুরু"),t:"date"},{n:"w_expires_on",l:B("Warranty expires","ওয়ারেন্টি শেষ"),t:"date"},
   {n:"w_coverage",l:B("Warranty coverage","ওয়ারেন্টির আওতা"),t:"text",max:500});
  f.push(REASON({val:T("Registered via asset form","সম্পদ ফর্ম থেকে নিবন্ধিত")}));
 }else f.push(REASON());
 return f;
}
function clean(o){const r={};for(const [k,v] of Object.entries(o))if(v!==null&&v!==undefined&&v!=="")r[k]=v;return r}
async function assetForm(a,after){
 const parents=await assetPicker(T("— none —","— নেই —"),x=>!a||x.id!==a.id);
 modalForm(a?T("Edit asset ","সম্পদ সম্পাদনা ")+(a.asset_no||""):T("New asset","নতুন সম্পদ"),assetFormFields(a,parents),async(v,err)=>{
  const {reason}=v;
  if(!a){
   const data=clean(Object.assign({},v,{reason:undefined,meters:undefined,w_supplier_name:undefined,w_supplier_ref:undefined,w_starts_on:undefined,w_expires_on:undefined,w_coverage:undefined}));
   const meters=(v.meters||[]).filter(m=>m.code).map(m=>clean({code:m.code.toUpperCase(),unit:m.unit,reading:m.reading}));
   if(meters.length)data.meters=meters;
   if(v.w_supplier_name){if(!v.w_starts_on||!v.w_expires_on){err.textContent=T("Warranty needs start and expiry dates.","ওয়ারেন্টিতে শুরু ও শেষের তারিখ লাগবে।");err.hidden=false;return false}
    data.warranty=clean({supplier_name:v.w_supplier_name,supplier_ref:v.w_supplier_ref,coverage:v.w_coverage,starts_on:v.w_starts_on,expires_on:v.w_expires_on})}
   const r=await act("am_create_asset_v1",{p_data:data,p_reason:reason},"Asset created","সম্পদ তৈরি হয়েছে",err);
   if(r){state.assetOpts=null;await after(r)}return !!r;
  }
  const ch={};
  for(const k of ["name","category_id","criticality","ownership","quantity","parent_asset_id","custom_attrs","acquisition_cost",...TEXT_FIELDS]){
   const nv=v[k],ov=a[k]==null?null:a[k];
   const nn=(k==="acquisition_date"||k==="commission_date")?nv:nv;
   const same=k==="custom_attrs"?eq(nv||{},ov||{}):(typeof nv==="number"||typeof ov==="number")?(nv==null&&ov==null)||Number(nv)===Number(ov):(nn==null?null:nn)===((k.endsWith("_date")&&ov)?String(ov).slice(0,10):ov);
   if(!same)ch[k]=nv;
  }
  if(!Object.keys(ch).length){err.textContent=T("No changes to save.","সংরক্ষণের মতো কোনো পরিবর্তন নেই।");err.hidden=false;return false}
  const r=await act("am_update_asset_v1",{p_asset:a.id,p_expected_version:a.version,p_changes:ch,p_reason:reason},"Asset updated","সম্পদ হালনাগাদ হয়েছে",err);
  if(r)await after(r);return !!r;
 },a?T("Save changes","পরিবর্তন সংরক্ষণ"):T("Create asset","সম্পদ তৈরি"),"asset-form");
}
SCREENS.assets=async function(body){
 $("am-title").textContent=T("Assets","সম্পদ");
 const page={offset:0,limit:25,total:0};
 const q=h("input",{id:"as-q",type:"search",placeholder:T("Name, asset no., serial","নাম, সম্পদ নং, সিরিয়াল"),autocomplete:"off","aria-label":T("Search","খুঁজুন")});
 const st=sel("as-status",[["",T("All statuses","সব অবস্থা")],...enumOpts("asset_status",ASSET_STATUSES)]);
 const cs=sel("as-cat",[["",T("All categories","সব ক্যাটাগরি")],...categories().map(c=>[String(c.id),catName(c)])]);
 const ow=sel("as-own",[["",T("Any ownership","যেকোনো মালিকানা")],...enumOpts("ownership",OWNERSHIPS)]);
 const list=h("div",{id:"as-list"}),detail=h("div",{id:"as-detail"}),trBox=h("div",{id:"as-transfers"}),clBox=h("div",{id:"as-claims"});
 async function refresh(){
  const f=clean({search:q.value.trim()||null,status:st.value||null,category_id:cs.value?Number(cs.value):null,site_id:state.site,ownership:ow.value||null});
  const r=await safe(()=>rd("am_list_assets_v1",{p_filters:Object.keys(f).length?f:null,p_limit:page.limit,p_offset:page.offset}));
  if(!r)return;page.total=r.total==null?arr(r,"items").length:r.total;list.textContent="";
  const items=arr(r,"items");
  list.append(h("p",{class:"muted",id:"as-count",text:page.total+T(" asset(s)"," টি সম্পদ")}),
   table([[T("No.","নং"),x=>x.asset_no],[T("Name","নাম"),x=>x.name],[T("Status","অবস্থা"),x=>chip(lab("asset_status",x.status),toneOf(x.status))],
    [T("Category","ক্যাটাগরি"),x=>x.category_name||catName(catById(x.category_id))],[T("Site","সাইট"),x=>x.site_label||siteName(x.site_id)],[T("Crit.","গুরুত্ব"),x=>val(x.criticality)],
    [T("Warranty","ওয়ারেন্টি"),x=>x.warranty_state?chip(lab("warranty_state",x.warranty_state),toneOf(x.warranty_state)):dash],
    ["",x=>btn(T("Open","খুলুন"),()=>openAsset(x.id),"outline","as-open-"+x.asset_no)]],items,T("No assets match.","কোনো সম্পদ মেলেনি।")),
   h("div",{class:"actions"},btn(T("Previous","আগের"),()=>{page.offset=Math.max(0,page.offset-page.limit);refresh()},"outline","as-prev",{disabled:page.offset===0}),
    h("span",{class:"muted",text:(page.total?page.offset+1:0)+"–"+Math.min(page.total,page.offset+page.limit)+" / "+page.total}),
    btn(T("Next","পরের"),()=>{page.offset+=page.limit;refresh()},"outline","as-next",{disabled:page.offset+page.limit>=page.total})));
 }
 async function refreshSide(){
  const tr=await safe(()=>rd("am_list_transfers_v1",{p_status:null}));
  if(tr){trBox.textContent="";const rows=arr(tr,"items");
   trBox.append(table([[T("Asset","সম্পদ"),x=>x.asset_no||("#"+x.asset_id)],[T("From","থেকে"),x=>siteName(x.from_site_id)],[T("To","গন্তব্য"),x=>siteName(x.to_site_id)],
    [T("Status","অবস্থা"),x=>chip(lab("transfer_status",x.status),toneOf(x.status))],[T("Reason","কারণ"),x=>x.reason],
    ["",x=>x.status==="pending"&&can("transfer")?h("span",{class:"actions"},...["approve","reject","cancel"].map(d=>btn(lab("transfer_decision",d),()=>decideTransfer(x,d),d==="approve"?"primary":"outline","tr-"+d+"-"+x.id))):null]],rows,T("No transfers.","কোনো স্থানান্তর নেই।")))}
  const cl=await safe(()=>rd("am_list_claims_v1",{p_status:null,p_limit:50,p_offset:0}));
  if(cl){clBox.textContent="";clBox.append(table([[T("Claim","দাবি"),x=>x.claim_no],[T("Asset","সম্পদ"),x=>x.asset_no||("#"+x.asset_id)],[T("Failure on","ত্রুটির তারিখ"),x=>dd(x.failure_on)],
    [T("Status","অবস্থা"),x=>chip(lab("claim_status",x.status),toneOf(x.status))],[T("Claimed (advisory)","দাবি (পরামর্শমূলক)"),x=>num(x.amount_claimed)],[T("Settled (advisory)","নিষ্পন্ন (পরামর্শমূলক)"),x=>num(x.amount_settled)],
    ["",x=>can("claim_write")?h("span",{class:"actions"},...claimActions(x.status).map(a=>btn(lab("claim_action",a),()=>claimTransition(x,a),"outline","cl-"+a+"-"+x.id))):null]],arr(cl,"items"),T("No warranty claims.","কোনো ওয়ারেন্টি দাবি নেই।")))}
 }
 const claimActions=(s)=>({draft:["submit"],submitted:["accept","reject"],accepted:["settle"],rejected:["close"],settled:["close"]}[s]||[]);
 function decideTransfer(x,d){
  modalForm(lab("transfer_decision",d)+" · "+(x.asset_no||x.asset_id),[{n:"note",l:["Note","নোট"],t:"textarea",rows:2,max:300}],async(v,err)=>{
   const r=await act("am_decide_transfer_v1",{p_transfer:x.id,p_expected_version:x.version,p_decision:d,p_note:v.note},"Transfer "+d+"d","স্থানান্তর সম্পন্ন",err);
   if(r){await refresh();await refreshSide()}return !!r},lab("transfer_decision",d));
 }
 function claimTransition(x,a){
  const ref={n:"supplier_claim_ref",l:["Supplier claim ref.","সরবরাহকারীর দাবি রেফ."],t:"text",max:60};
  const fields=a==="submit"?[ref,{n:"amount_claimed",l:["Amount claimed (advisory)","দাবির পরিমাণ (পরামর্শমূলক)"],t:"num",val:x.amount_claimed}]
   :[{n:"decision_note",l:["Note","নোট"],t:"textarea",rows:2,max:1000,req:a==="reject",min:a==="reject"?3:0},ref];
  if(a==="settle")fields.unshift({n:"amount_settled",l:["Amount settled (advisory)","নিষ্পন্ন পরিমাণ (পরামর্শমূলক)"],t:"num",req:true});
  modalForm(lab("claim_action",a)+" · "+x.claim_no,fields,async(v,err)=>{
   const r=await act("am_claim_transition_v1",{p_claim:x.id,p_expected_version:x.version,p_action:a,p_data:clean(v)},"Claim updated","দাবি হালনাগাদ",err);
   if(r)await refreshSide();return !!r},lab("claim_action",a));
 }
 async function openAsset(id){
  const d=await safe(()=>rd("am_get_asset_v1",{p_asset:id}));if(!d)return;
  detail.textContent="";const a=d.asset||d,sid=a.site_id,reload=async()=>{await refresh();await refreshSide();await openAsset(id)};
  const acts=h("div",{class:"actions"});
  if(can("asset_write",sid)){acts.append(btn(T("Edit","সম্পাদনা"),()=>assetForm(a,reload),"outline","as-edit"),
   btn(T("Change status","অবস্থা বদলান"),()=>statusForm(a,reload),"outline","as-status-btn"),btn(T("Add meter","মিটার যোগ"),()=>meterForm(a,reload),"outline","as-addmeter"))}
  if(can("transfer",sid))acts.append(btn(T("Request transfer","স্থানান্তর অনুরোধ"),()=>transferForm(a,reload),"outline","as-transfer"));
  if(can("warranty_write",sid))acts.append(btn(T("Add warranty","ওয়ারেন্টি যোগ"),()=>warrantyForm(a,null,reload),"outline","as-warranty"));
  const meters=arr(d,"meters"),wars=arr(d,"warranties"),moves=arr(d,"movements"),kids=arr(d,"children"),owos=arr(d,"open_work_orders","open_wos"),tgts=arr(d,"plan_targets","targets");
  const tree=(items)=>h("ul",{class:"tree"},items.map(c=>h("li",null,h("span",{text:assetLabel(c)+" "}),chip(lab("asset_status",c.status),toneOf(c.status)),
    btn(T("Open","খুলুন"),()=>openAsset(c.id),"outline","ch-open-"+c.id),arr(c,"children").length?tree(arr(c,"children")):null)));
  detail.append(h("section",{class:"panel",id:"asset-panel"},h("div",{class:"panel-title"},h("h2",{text:assetLabel(a)}),chip(lab("asset_status",a.status),toneOf(a.status)),btn("×",()=>{detail.textContent=""},"outline close","as-detail-close",{"aria-label":T("Close","বন্ধ")})),
   h("div",{class:"panel-body"},acts,
    kv([[T("Asset no.","সম্পদ নং"),a.asset_no],[T("Category","ক্যাটাগরি"),a.category_name||catName(catById(a.category_id))],[T("Site","সাইট"),a.site_label||siteName(a.site_id)],[T("Criticality","গুরুত্ব"),a.criticality],
     [T("Serial no.","সিরিয়াল নং"),a.serial_no],[T("Manufacturer / model","নির্মাতা / মডেল"),[a.manufacturer,a.model].filter(Boolean).join(" / ")||null],[T("Ownership","মালিকানা"),a.ownership?lab("ownership",a.ownership):null],
     [T("Location","অবস্থান"),a.location_note],[T("Supplier","সরবরাহকারী"),[a.supplier_name,a.supplier_ref].filter(Boolean).join(" · ")||null],[T("Purchase order ref.","ক্রয় আদেশ রেফ."),a.purchase_order_ref],
     [T("Custodian ref.","দায়িত্বপ্রাপ্ত রেফ."),a.custodian_ref],[T("Acquired / commissioned","অর্জন / চালু"),dd(a.acquisition_date)+" / "+dd(a.commission_date)],[T("Quantity","পরিমাণ"),a.quantity],
     [T("Acquisition cost (advisory)","অর্জন মূল্য (পরামর্শমূলক)"),a.acquisition_cost==null?null:num(a.acquisition_cost)],[T("Version","সংস্করণ"),a.version]]),
    h("h3",{text:T("Meters","মিটার")}),table([[T("Code","কোড"),m=>m.code],[T("Unit","একক"),m=>lab("meter_unit",m.unit)],[T("Reading","রিডিং"),m=>num(m.current_reading,3)],[T("Last read","সর্বশেষ"),m=>dt(m.last_reading_at)],
     [T("Freshness","সতেজতা"),m=>(m.stale||m.is_stale)?chip(T("Stale","পুরনো"),"bad"):chip(T("Fresh","সতেজ"),"good")],
     ["",m=>can("meter_write",sid)?btn(T("Record reading","রিডিং দিন"),()=>readingForm(a,m,reload),"outline","meter-read-"+m.id):null]],meters,T("No meters.","কোনো মিটার নেই।")),
    h("h3",{text:T("Warranty","ওয়ারেন্টি")}),table([[T("Supplier","সরবরাহকারী"),w=>w.supplier_name],[T("From","থেকে"),w=>dd(w.starts_on)],[T("Until","পর্যন্ত"),w=>dd(w.expires_on)],
     [T("State","অবস্থা"),w=>chip(lab("warranty_state",w.state||w.status),toneOf(w.state||w.status))],
     ["",w=>h("span",{class:"actions"},can("warranty_write",sid)?btn(T("Edit","সম্পাদনা"),()=>warrantyForm(a,w,reload),"outline","war-edit-"+w.id):null,
       can("claim_write",sid)?btn(T("New claim","নতুন দাবি"),()=>claimForm(a,w,null,reload),"outline","war-claim-"+w.id):null)]],wars,T("No warranty recorded.","কোনো ওয়ারেন্টি নেই।")),
    h("h3",{text:T("Movements","স্থানান্তর ইতিহাস")}),table([[T("When","কখন"),m=>dt(m.moved_at)],[T("Kind","ধরন"),m=>m.kind],[T("From","থেকে"),m=>m.from_site_id==null?dash:siteName(m.from_site_id)],[T("To","গন্তব্য"),m=>siteName(m.to_site_id)],[T("Reason","কারণ"),m=>m.reason]],moves,T("No movements.","কোনো স্থানান্তর নেই।")),
    h("h3",{text:T("Assembly (child assets)","অ্যাসেম্বলি (সন্তান সম্পদ)")}),kids.length?tree(kids):h("p",{class:"muted",text:T("No child assets.","কোনো সন্তান সম্পদ নেই।")}),
    h("h3",{text:T("Open work orders","খোলা কাজের আদেশ")}),table([[T("No.","নং"),w=>h("a",{href:"./core10-asset-maintenance-workorders.html?biz="+state.biz+"&wo="+w.id,text:w.wo_no||("#"+w.id)})],[T("Title","শিরোনাম"),w=>w.title],
     [T("Status","অবস্থা"),w=>chip(lab("wo_status",w.status),toneOf(w.status))],[T("Priority","অগ্রাধিকার"),w=>lab("priority",w.priority)]],owos,T("No open work orders.","কোনো খোলা কাজ নেই।")),
    h("h3",{text:T("Plan targets","পরিকল্পনার লক্ষ্য")}),table([[T("Plan","পরিকল্পনা"),x=>x.plan_name||("#"+x.plan_id)],[T("Next due","পরবর্তী দেয়"),x=>dd(x.next_due_on)],[T("Next due reading","পরবর্তী রিডিং"),x=>num(x.next_due_reading,3)],
     [T("Deferred until","স্থগিত"),x=>dd(x.deferred_until)],[T("Status","অবস্থা"),x=>x.status]],tgts,T("No plan targets.","কোনো লক্ষ্য নেই।")))));
  detail.scrollIntoView&&detail.scrollIntoView({block:"nearest"});
 }
 function statusForm(a,reload){
  modalForm(T("Change status","অবস্থা বদলান")+" · "+a.asset_no,[{n:"status",l:["New status","নতুন অবস্থা"],t:"select",opts:enumOpts("asset_status",["active","idle","retired","disposed"]),val:a.status},REASON()],async(v,err)=>{
   const r=await act("am_set_asset_status_v1",{p_asset:a.id,p_expected_version:a.version,p_status:v.status,p_reason:v.reason},"Status changed","অবস্থা বদলেছে",err);if(r)await reload();return !!r},T("Change","বদলান"),"status-form");
 }
 function transferForm(a,reload){
  const others=siteOptsFor(null).filter(o=>o[0]!==String(a.site_id));
  modalForm(T("Request transfer","স্থানান্তর অনুরোধ")+" · "+a.asset_no,[{n:"to_site",l:["To site","গন্তব্য সাইট"],t:"select",int:true,req:true,opts:others},
   {n:"include_children",l:["Include child assets","সন্তান সম্পদসহ"],t:"bool",val:true},REASON()],async(v,err)=>{
   const r=await act("am_request_transfer_v1",{p_asset:a.id,p_to_site:v.to_site,p_include_children:v.include_children,p_reason:v.reason},"Transfer requested","স্থানান্তর অনুরোধ হয়েছে",err);if(r)await reload();return !!r},T("Request","অনুরোধ"),"transfer-form");
 }
 function meterForm(a,reload){
  modalForm(T("Add meter","মিটার যোগ")+" · "+a.asset_no,[{n:"code",l:["Code (A-Z, 0-9)","কোড"],t:"text",req:true,max:16},{n:"unit",l:["Unit","একক"],t:"select",opts:enumOpts("meter_unit",["hours","km","cycles","units"])},
   {n:"initial_reading",l:["Initial reading","প্রাথমিক রিডিং"],t:"num",val:0}],async(v,err)=>{
   const r=await act("am_add_meter_v1",{p_asset:a.id,p_code:v.code.toUpperCase(),p_unit:v.unit,p_initial_reading:v.initial_reading},"Meter added","মিটার যোগ হয়েছে",err);if(r)await reload();return !!r},T("Add","যোগ"),"meter-form");
 }
 function readingForm(a,m,reload){
  modalForm(T("Record reading","রিডিং দিন")+" · "+m.code,[{n:"reading",l:["Reading","রিডিং"],t:"num",req:true,hint:["Current: "+num(m.current_reading,3),"বর্তমান: "+num(m.current_reading,3)]},
   {n:"read_at",l:["Read at","রিডিংয়ের সময়"],t:"dt",val:nowLocalInput()},{n:"kind",l:["Kind","ধরন"],t:"select",opts:enumOpts("meter_kind",["reading","reset"]),val:"reading"},{n:"note",l:["Note","নোট"],t:"text",max:300}],async(v,err)=>{
   const r=await act("am_record_meter_reading_v1",{p_meter:m.id,p_reading:v.reading,p_read_at:v.read_at,p_kind:v.kind,p_note:v.note},"Reading recorded","রিডিং রেকর্ড হয়েছে",err);if(r)await reload();return !!r},T("Record","রেকর্ড"),"reading-form");
 }
 function warrantyForm(a,w,reload){
  modalForm((w?T("Edit warranty","ওয়ারেন্টি সম্পাদনা"):T("Add warranty","ওয়ারেন্টি যোগ"))+" · "+a.asset_no,[
   {n:"supplier_name",l:["Supplier","সরবরাহকারী"],t:"text",req:true,val:w&&w.supplier_name,max:120},{n:"supplier_ref",l:["Reference","রেফারেন্স"],t:"text",val:w&&w.supplier_ref,max:60},
   {n:"starts_on",l:["Starts on","শুরু"],t:"date",req:true,val:w&&dd(w.starts_on)},{n:"expires_on",l:["Expires on","শেষ"],t:"date",req:true,val:w&&dd(w.expires_on)},
   {n:"coverage",l:["Coverage","আওতা"],t:"textarea",rows:2,val:w&&w.coverage,max:500},
   ...(w?[{n:"status",l:["Status","অবস্থা"],t:"select",opts:[["active",lab("warranty_state","active")],["void",lab("warranty_state","void")]],val:w.status}]:[]),REASON()],async(v,err)=>{
   const data=clean({asset_id:w?null:a.id,supplier_name:v.supplier_name,supplier_ref:v.supplier_ref,starts_on:v.starts_on,expires_on:v.expires_on,coverage:v.coverage,status:v.status});
   const r=await act("am_save_warranty_v1",{p_id:w?w.id:null,p_expected_version:w?w.version:null,p_data:data,p_reason:v.reason},"Warranty saved","ওয়ারেন্টি সংরক্ষিত",err);if(r)await reload();return !!r},T("Save","সংরক্ষণ"),"warranty-form");
 }
 function claimForm(a,w,c,reload){
  modalForm(T("Warranty claim","ওয়ারেন্টি দাবি")+" · "+a.asset_no,[{n:"failure_on",l:["Failure date","ত্রুটির তারিখ"],t:"date",req:true,val:c&&dd(c.failure_on)||today()},
   {n:"description",l:["What failed","কী ব্যর্থ হয়েছে"],t:"textarea",req:true,min:3,val:c&&c.description,max:1000},{n:"amount_claimed",l:["Amount claimed (advisory)","দাবির পরিমাণ (পরামর্শমূলক)"],t:"num",val:c&&c.amount_claimed},
   {n:"supplier_claim_ref",l:["Supplier claim ref.","সরবরাহকারীর দাবি রেফ."],t:"text",max:60,val:c&&c.supplier_claim_ref}],async(v,err)=>{
   const r=await act("am_save_claim_v1",{p_id:c?c.id:null,p_expected_version:c?c.version:null,p_data:clean(Object.assign(c?{}:{warranty_id:w.id},v))},"Claim saved","দাবি সংরক্ষিত",err);if(r){await reload()}return !!r},T("Save claim","দাবি সংরক্ষণ"),"claim-form");
 }
 const bar=h("div",{class:"actions"},can("asset_write")?btn(T("+ New asset","+ নতুন সম্পদ"),()=>assetForm(null,async()=>{await refresh()}),"primary","as-new"):null);
 const doFilter=()=>{page.offset=0;refresh()};
 [st,cs,ow].forEach(x=>x.addEventListener("change",doFilter));q.addEventListener("keydown",(e)=>{if(e.key==="Enter"){e.preventDefault();doFilter()}});
 body.append(panel(T("Directory","তালিকা"),[filterRow([labeled(T("Search","খুঁজুন"),q),labeled(T("Status","অবস্থা"),st),labeled(T("Category","ক্যাটাগরি"),cs),labeled(T("Ownership","মালিকানা"),ow),btn(T("Search","খুঁজুন"),doFilter,"primary","as-search")]),bar,list],null,"as-dir"),
  detail,panel(T("Transfers","স্থানান্তর"),trBox),panel(T("Warranty claims","ওয়ারেন্টি দাবি"),clBox));
 await refresh();await refreshSide();
 const qa=parseQuery().asset;if(qa)await openAsset(qa);
};
/* =====================================================================  WORK ORDERS  ===================================================================== */
const WO_STATUSES=["DRAFT","SUBMITTED","APPROVED","IN_PROGRESS","COMPLETED","VERIFIED","CLOSED","CANCELLED"];
const WO_KINDS=["preventive","corrective","breakdown","inspection","calibration"];
const PRIORITIES=["low","medium","high","critical"];
const TRANSITIONS=["submit","approve","return","start","complete","verify","close","cancel","reopen"];
const REASON_REQ=["return","cancel","reopen"];
const ALIASES={update:"edit",estimates:"edit_estimates",record_checklist:"checklist",checklist_result:"checklist",labor:"add_labor",add_labour:"add_labor",spares:"add_spares",attachment:"add_attachment",safety_ack:"acknowledge_safety",ack_safety:"acknowledge_safety"};
const UUID_RX=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const FINAL_WO=["COMPLETED","VERIFIED","CLOSED","CANCELLED"];
/* The server decides which actions exist for the caller; the client never infers them from status or role. */
function actionsOf(d){const wo=d.work_order||d.wo||d;const raw=d.available_actions||wo.available_actions||[];
 return raw.map(x=>typeof x==="string"?x:(x&&(x.action||x.name||x.code))).filter(Boolean).map(x=>ALIASES[x]||x)}
function slaChips(wo){
 const out=[],s=wo.sla||{},r=wo.response_state||wo.sla_response_state||s.response,z=wo.resolve_state||wo.sla_resolve_state||s.resolve||wo.sla_state;
 if(r)out.push(chip(T("Response: ","সাড়া: ")+lab("sla",r),toneOf(r)));
 if(z)out.push(chip(T("Resolve: ","সমাধান: ")+lab("sla",z),toneOf(z)));
 if(!out.length&&wo.sla_resolve_due_at&&!FINAL_WO.includes(wo.status)){const late=Date.parse(wo.sla_resolve_due_at)<Date.now();out.push(chip(T("Resolve due ","সমাধানের সময় ")+dt(wo.sla_resolve_due_at)+(late?T(" (past)"," (অতিক্রান্ত)"):""),late?"bad":"dim"))}
 return out;
}
async function woCreateForm(after,presetAsset){
 const assets=await assetPicker(T("— choose asset —","— সম্পদ বাছুন —"),a=>!["retired","disposed"].includes(a.status));
 const cls=await safe(()=>rd("am_list_checklists_v1",{p_include_inactive:false}));
 const clOpts=[["",T("— none —","— নেই —")],...arr(cls,"items").map(c=>[c.code,c.code+" · "+c.name])];
 modalForm(T("New work order","নতুন কাজের আদেশ"),[
  {n:"kind",l:["Kind","ধরন"],t:"select",opts:enumOpts("wo_kind",["corrective","preventive","inspection","calibration"]),val:"corrective"},
  {n:"asset_id",l:["Asset","সম্পদ"],t:"select",int:true,req:true,opts:assets,val:presetAsset||""},
  {n:"title",l:["Title","শিরোনাম"],t:"text",req:true,min:3,max:160},{n:"description",l:["Description","বিবরণ"],t:"textarea",max:2000},
  {n:"priority",l:["Priority","অগ্রাধিকার"],t:"select",opts:enumOpts("priority",PRIORITIES),val:"medium"},{n:"due_on",l:["Due on","শেষ তারিখ"],t:"date"},
  {n:"checklist_code",l:["Checklist template","চেকলিস্ট টেমপ্লেট"],t:"select",opts:clOpts},
  {n:"service_category",l:["Service category","সার্ভিস ধরন"],t:"select",opts:codeOpts("service_category",T("— none —","— নেই —"))},
  {n:"est_labor_hours",l:["Estimated labour hours","আনুমানিক শ্রমঘণ্টা"],t:"num"},{n:"team_ref",l:["Team ref.","টিম রেফ."],t:"text",max:40},
  {n:"submit",l:["Submit for approval now","এখনই অনুমোদনের জন্য জমা"],t:"bool",val:false}],async(v,err)=>{
  const r=await act("am_create_work_order_v1",{p_data:clean(v)},"Work order created","কাজের আদেশ তৈরি হয়েছে",err);
  if(r)await after(r);return !!r},T("Create","তৈরি"),"wo-form");
}
SCREENS.workorders=async function(body){
 $("am-title").textContent=T("Work orders","কাজের আদেশ");
 const page={offset:0,limit:25,total:0};
 const q=h("input",{id:"wo-q",type:"search",autocomplete:"off",placeholder:T("Number, title","নম্বর, শিরোনাম"),"aria-label":T("Search","খুঁজুন")});
 const st=sel("wo-status",[["",T("All statuses","সব অবস্থা")],...WO_STATUSES.map(s=>[s,lab("wo_status",s)])]);
 const kd=sel("wo-kind",[["",T("All kinds","সব ধরন")],...enumOpts("wo_kind",WO_KINDS)]);
 const pr=sel("wo-prio",[["",T("All priorities","সব অগ্রাধিকার")],...enumOpts("priority",PRIORITIES)]);
 const mine=h("input",{id:"wo-mine",type:"checkbox",class:"cb"}),over=h("input",{id:"wo-overdue",type:"checkbox",class:"cb"});
 const list=h("div",{id:"wo-list"}),detail=h("div",{id:"wo-detail"});
 async function refresh(){
  const f=clean({search:q.value.trim()||null,status:st.value?[st.value]:null,kind:kd.value||null,priority:pr.value||null,site_id:state.site,assigned_to:mine.checked?"me":null,overdue:over.checked?true:null});
  const r=await safe(()=>rd("am_list_work_orders_v1",{p_filters:Object.keys(f).length?f:null,p_limit:page.limit,p_offset:page.offset}));if(!r)return;
  const items=arr(r,"items");page.total=r.total==null?items.length:r.total;list.textContent="";
  list.append(h("p",{class:"muted",id:"wo-count",text:page.total+T(" work order(s)"," টি কাজের আদেশ")}),
   table([[T("No.","নং"),x=>x.wo_no],[T("Title","শিরোনাম"),x=>x.title],[T("Kind","ধরন"),x=>lab("wo_kind",x.kind)],[T("Status","অবস্থা"),x=>chip(lab("wo_status",x.status),toneOf(x.status))],
    [T("Priority","অগ্রাধিকার"),x=>chip(lab("priority",x.priority),toneOf(x.priority))],[T("Asset","সম্পদ"),x=>x.asset_no||x.asset_name||("#"+x.asset_id)],[T("Site","সাইট"),x=>x.site_label||siteName(x.site_id)],
    [T("Due","দেয়"),x=>dd(x.due_on)],["SLA",x=>h("span",null,...slaChips(x))],["",x=>btn(T("Open","খুলুন"),()=>openWo(x.id),"outline","wo-open-"+x.id)]],items,T("No work orders match.","কোনো কাজের আদেশ মেলেনি।")),
   h("div",{class:"actions"},btn(T("Previous","আগের"),()=>{page.offset=Math.max(0,page.offset-page.limit);refresh()},"outline","wo-prev",{disabled:page.offset===0}),
    h("span",{class:"muted",text:(page.total?page.offset+1:0)+"–"+Math.min(page.total,page.offset+page.limit)+" / "+page.total}),
    btn(T("Next","পরের"),()=>{page.offset+=page.limit;refresh()},"outline","wo-next",{disabled:page.offset+page.limit>=page.total})));
 }
 async function openWo(id){
  const d=await safe(()=>rd("am_get_work_order_v1",{p_wo:id}));if(!d)return;
  const wo=d.work_order||d.wo||d,acts=actionsOf(d),reload=async()=>{await refresh();await openWo(id)};
  detail.textContent="";
  const has=(a)=>acts.includes(a);
  const bar=h("div",{class:"actions",id:"wo-actions"});
  for(const a of acts){
   if(TRANSITIONS.includes(a))bar.append(btn(lab("wo_action",a),()=>transitionForm(wo,a,reload),["approve","start","complete","verify","close","submit"].includes(a)?"primary":"outline","act-"+a));
   else if(a==="assign")bar.append(btn(lab("wo_action","assign"),()=>assignForm(wo,reload),"outline","act-assign"));
   else if(a==="edit")bar.append(btn(lab("wo_action","edit"),()=>editForm(wo,reload,false),"outline","act-edit"));
   else if(a==="edit_estimates")bar.append(btn(lab("wo_action","edit_estimates"),()=>editForm(wo,reload,true),"outline","act-edit_estimates"));
   else if(a==="add_labor")bar.append(btn(lab("wo_action",a),()=>laborForm(wo,reload),"outline","act-add_labor"));
   else if(a==="add_spares")bar.append(btn(lab("wo_action",a),()=>sparesForm(wo,reload),"outline","act-add_spares"));
   else if(a==="add_attachment")bar.append(btn(lab("wo_action",a),()=>attachForm(wo,reload),"outline","act-add_attachment"));
   else if(a==="acknowledge_safety")bar.append(btn(lab("wo_action",a),async()=>{const r=await act("am_acknowledge_safety_v1",{p_wo:wo.id},"Safety acknowledged","নিরাপত্তা স্বীকৃত");if(r)await reload()},"outline","act-acknowledge_safety"));
   else if(a==="merge")bar.append(btn(lab("wo_action",a),()=>mergeForm(wo,reload),"outline","act-merge"));
  }
  const cl=arr(d,"checklist"),labor=arr(d,"labor","labour"),spares=arr(d,"spares"),atts=arr(d,"attachments"),hist=arr(d,"history");
  const canCheck=has("checklist");
  const checklist=table([["#",x=>x.seq],[T("Item","বিষয়"),x=>h("span",null,x.text,x.required?chip(T("required","আবশ্যক"),"warn"):null,x.kind!=="check"?chip(lab("check_kind",x.kind),""):null)],
    [T("Range","সীমা"),x=>x.min_value!=null||x.max_value!=null?num(x.min_value,4)+" … "+num(x.max_value,4)+(x.unit?" "+x.unit:""):dash],
    [T("Result","ফলাফল"),x=>canCheck?checkRow(wo,x,reload):h("span",null,chip(lab("check_result",x.result),toneOf(x.result)),x.value!=null?" "+num(x.value,4):"",x.note?" · "+x.note:"")]],cl,T("No checklist on this work order.","এই কাজে কোনো চেকলিস্ট নেই।"));
  detail.append(h("section",{class:"panel",id:"wo-panel"},h("div",{class:"panel-title"},h("h2",{text:(wo.wo_no||"#"+wo.id)+" · "+wo.title}),chip(lab("wo_status",wo.status),toneOf(wo.status)),
   btn("×",()=>{detail.textContent=""},"outline close","wo-detail-close",{"aria-label":T("Close","বন্ধ")})),
   h("div",{class:"panel-body"},h("div",{class:"chips"},chip(lab("wo_kind",wo.kind),""),chip(lab("priority",wo.priority),toneOf(wo.priority)),chip(lab("wo_source",wo.source),"dim"),wo.safety_critical?chip(T("Safety-critical","নিরাপত্তা-সংবেদনশীল"),"bad"):null,
     wo.needs_reassignment?chip(T("Needs reassignment","পুনঃবরাদ্দ দরকার"),"warn"):null,...slaChips(wo)),
    h("p",{class:"muted",id:"wo-actions-note",text:acts.length?T("Available to you now:","এখন আপনার জন্য উপলব্ধ:"):T("No actions are available to you on this work order.","এই কাজে আপনার জন্য কোনো কাজ উপলব্ধ নেই।")}),bar,
    kv([[T("Asset","সম্পদ"),(wo.asset_no||"")+" "+(wo.asset_name||"")||("#"+wo.asset_id)],[T("Site","সাইট"),wo.site_label||siteName(wo.site_id)],[T("Description","বিবরণ"),wo.description],
     [T("Due","দেয়"),dd(wo.due_on)],[T("Assigned to","দায়িত্বে"),wo.assigned_to||wo.assignee_ref],[T("Team","টিম"),wo.team_ref],[T("Requested","অনুরোধ"),dt(wo.requested_at)],
     [T("Response SLA due","সাড়ার সময়সীমা"),dt(wo.sla_response_due_at)],[T("Resolve SLA due","সমাধানের সময়সীমা"),dt(wo.sla_resolve_due_at)],[T("Started","শুরু"),dt(wo.started_at)],[T("Completed","সম্পন্ন"),dt(wo.completed_at)],
     [T("Failure / cause / action","ত্রুটি / কারণ / পদক্ষেপ"),[wo.failure_code,wo.cause_code,wo.action_code].filter(Boolean).join(" / ")||null],[T("Corrective action","সংশোধনী পদক্ষেপ"),wo.corrective_action],
     [T("Safety acknowledged","নিরাপত্তা স্বীকৃত"),wo.safety_ack_at?dt(wo.safety_ack_at):null],
     [T("Labour h / cost (advisory)","শ্রম ঘণ্টা / খরচ (পরামর্শমূলক)"),num(wo.actual_labor_hours)+" / "+num(wo.actual_labor_cost)],[T("Spares cost (advisory)","যন্ত্রাংশ খরচ (পরামর্শমূলক)"),num(wo.actual_spares_cost)],[T("Version","সংস্করণ"),wo.version]]),
    h("h3",{text:T("Checklist","চেকলিস্ট")}),checklist,
    h("h3",{text:T("Labour","শ্রম")}),table([[T("Kind","ধরন"),x=>lab("labor_kind",x.labor_kind)],[T("Worker","কর্মী"),x=>x.worker_ref],[T("Hours","ঘণ্টা"),x=>num(x.hours)],[T("Rate (advisory)","হার (পরামর্শমূলক)"),x=>num(x.rate)],[T("Phase","ধাপ"),x=>lab("phase",x.phase)],[T("Note","নোট"),x=>x.note]],labor,T("No labour lines.","কোনো শ্রম লাইন নেই।")),
    h("h3",{text:T("Spares (informational — no stock is moved)","যন্ত্রাংশ (তথ্যমূলক — স্টক নড়ে না)")}),table([[T("Item","আইটেম"),x=>x.item_ref],[T("Description","বিবরণ"),x=>x.description],[T("Qty","পরিমাণ"),x=>num(x.qty,3)],[T("Unit cost (advisory)","একক মূল্য (পরামর্শমূলক)"),x=>num(x.unit_cost)],[T("Phase","ধাপ"),x=>lab("phase",x.phase)]],spares,T("No spares lines.","কোনো যন্ত্রাংশ লাইন নেই।")),
    h("h3",{text:T("Attachment records (metadata only)","সংযুক্তি রেকর্ড (শুধু মেটাডেটা)")}),table([[T("File","ফাইল"),x=>x.file_name],[T("Kind","ধরন"),x=>lab("attach_kind",x.kind)],[T("Type","টাইপ"),x=>x.mime],[T("Size","আকার"),x=>num(x.size_bytes,0)],[T("Caption","ক্যাপশন"),x=>x.caption]],atts,T("No attachment records.","কোনো সংযুক্তি রেকর্ড নেই।")),
    h("h3",{text:T("History","ইতিহাস")}),hist.length?h("ol",{class:"timeline",id:"wo-history"},hist.map(x=>h("li",null,h("b",{text:dt(x.created_at)+" · "+x.action}),h("span",{text:" "+(x.from_status?lab("wo_status",x.from_status)+" → ":"")+lab("wo_status",x.to_status)+(x.reason?" · "+x.reason:"")})))):h("p",{class:"muted",text:T("No history.","কোনো ইতিহাস নেই।")}))));
  detail.scrollIntoView&&detail.scrollIntoView({block:"nearest"});
 }
 function checkRow(wo,x,reload){
  const rs=sel("chk-result-"+x.seq,enumOpts("check_result",["pending","pass","fail","na"]),x.result,{"aria-label":T("Result","ফলাফল")});
  const vi=x.kind==="measure"?h("input",{id:"chk-value-"+x.seq,type:"number",step:"any",value:x.value==null?"":x.value,"aria-label":T("Measured value","মাপা মান")}):null;
  const ni=h("input",{id:"chk-note-"+x.seq,type:"text",maxlength:500,value:x.note||"",placeholder:T("Note","নোট"),"aria-label":T("Note","নোট")});
  return h("div",{class:"chk-row"},rs,vi,ni,btn(T("Save","সংরক্ষণ"),async()=>{
   const v=vi&&vi.value!==""?Number(vi.value):null;if(v!==null&&!Number.isFinite(v)){status(T("Invalid number.","অবৈধ সংখ্যা।"),"error");return}
   const r=await act("am_wo_checklist_result_v1",{p_wo:wo.id,p_seq:x.seq,p_result:rs.value,p_value:v,p_note:ni.value.trim()||null},"Checklist saved","চেকলিস্ট সংরক্ষিত");if(r)await reload()},"outline","chk-save-"+x.seq));
 }
 function transitionForm(wo,a,reload){
  const fields=[];
  if(a==="start")fields.push({n:"downtime",l:["Also open a planned-downtime window","এই সঙ্গে পরিকল্পিত ডাউনটাইম খুলুন"],t:"bool",val:false});
  if(a==="cancel")fields.push({n:"end_downtime",l:["Also end the linked open downtime","সংযুক্ত খোলা ডাউনটাইমও শেষ করুন"],t:"bool",val:false});
  if(a==="reopen")fields.push({n:"restart_downtime",l:["Also restart downtime","ডাউনটাইম আবার শুরু করুন"],t:"bool",val:false});
  if(a==="complete"){
   fields.push({n:"failure_code",l:["Failure code","ত্রুটি কোড"],t:"select",opts:codeOpts("failure",T("— none —","— নেই —"))},{n:"cause_code",l:["Cause code","কারণ কোড"],t:"select",opts:codeOpts("cause",T("— none —","— নেই —"))},
    {n:"action_code",l:["Action code","পদক্ষেপ কোড"],t:"select",opts:codeOpts("action",T("— none —","— নেই —"))},{n:"corrective_action",l:["What was done","কী করা হয়েছে"],t:"textarea",max:2000},
    {n:"meter_reading",l:["Meter reading at end","শেষে মিটার রিডিং"],t:"num"},{n:"actual_labor_hours",l:["Actual labour hours","প্রকৃত শ্রমঘণ্টা"],t:"num"},{n:"actual_labor_cost",l:["Actual labour cost (advisory)","প্রকৃত শ্রম খরচ (পরামর্শমূলক)"],t:"num"},
    {n:"actual_spares_cost",l:["Actual spares cost (advisory)","প্রকৃত যন্ত্রাংশ খরচ (পরামর্শমূলক)"],t:"num"});
   if(wo.kind==="breakdown")fields.push({n:"restored_at",l:["Service restored at","সেবা ফিরেছে"],t:"dt",val:nowLocalInput()});
   if(wo.kind==="calibration")fields.push({n:"cal_performed_on",l:["Calibrated on","ক্যালিব্রেশনের তারিখ"],t:"date",req:true,val:today()},{n:"cal_next_due_on",l:["Next due","পরবর্তী তারিখ"],t:"date"},
    {n:"cal_result",l:["Calibration result","ক্যালিব্রেশন ফল"],t:"select",opts:enumOpts("cal_result",["pass","fail","adjusted"])},{n:"cal_certificate_ref",l:["Certificate ref.","সনদ রেফ."],t:"text",max:80},
    {n:"cal_standard_ref",l:["Standard ref.","স্ট্যান্ডার্ড রেফ."],t:"text",max:80},{n:"cal_vendor",l:["Vendor","ভেন্ডর"],t:"text",max:120},{n:"cal_note",l:["Calibration note","ক্যালিব্রেশন নোট"],t:"text",max:500});
  }
  fields.push(REASON({n:"reason",req:REASON_REQ.includes(a),min:REASON_REQ.includes(a)?5:0}));
  modalForm(lab("wo_action",a)+" · "+(wo.wo_no||""),fields,async(v,err)=>{
   const data={};
   for(const k of ["failure_code","cause_code","action_code","corrective_action","restored_at","meter_reading","actual_labor_hours","actual_labor_cost","actual_spares_cost"])if(v[k]!=null&&v[k]!=="")data[k]=v[k];
   for(const k of ["downtime","end_downtime","restart_downtime"])if(v[k]===true)data[k]=true;
   if(wo.kind==="calibration"&&a==="complete")data.calibration=clean({performed_on:v.cal_performed_on,next_due_on:v.cal_next_due_on,result:v.cal_result,certificate_ref:v.cal_certificate_ref,standard_ref:v.cal_standard_ref,vendor:v.cal_vendor,note:v.cal_note});
   const r=await act("am_wo_transition_v1",{p_wo:wo.id,p_expected_version:wo.version,p_action:a,p_reason:v.reason,p_data:Object.keys(data).length?data:null},lab("wo_action",a)+" done",lab("wo_action",a)+" সম্পন্ন",err);
   if(r)await reload();return !!r},lab("wo_action",a),"wo-transition-form");
 }
 function assignForm(wo,reload){
  modalForm(T("Assign","দায়িত্ব দিন")+" · "+(wo.wo_no||""),[{n:"assigned_to",l:["Assignee user id (UUID)","দায়িত্বপ্রাপ্ত ব্যবহারকারী (UUID)"],t:"uuid",max:36,val:wo.assigned_to},
   {n:"assignee_ref",l:["Assignee ref.","দায়িত্বপ্রাপ্ত রেফ."],t:"text",max:40,val:wo.assignee_ref},{n:"team_ref",l:["Team ref.","টিম রেফ."],t:"text",max:40,val:wo.team_ref},REASON()],async(v,err)=>{
   if(v.assigned_to&&!UUID_RX.test(v.assigned_to)){err.textContent=T("Assignee must be a valid UUID.","দায়িত্বপ্রাপ্ত ব্যক্তির UUID সঠিক নয়।");err.hidden=false;return false}
   const r=await act("am_assign_work_order_v1",{p_wo:wo.id,p_expected_version:wo.version,p_assigned_to:v.assigned_to,p_assignee_ref:v.assignee_ref,p_team_ref:v.team_ref,p_reason:v.reason},"Assigned","দায়িত্ব দেওয়া হয়েছে",err);
   if(r)await reload();return !!r},T("Assign","দায়িত্ব দিন"),"assign-form");
 }
 function editForm(wo,reload,estOnly){
  const est=[{n:"est_labor_hours",l:["Estimated labour hours","আনুমানিক শ্রমঘণ্টা"],t:"num",val:wo.est_labor_hours},{n:"est_labor_cost",l:["Estimated labour cost (advisory)","আনুমানিক শ্রম খরচ (পরামর্শমূলক)"],t:"num",val:wo.est_labor_cost},
   {n:"est_spares_cost",l:["Estimated spares cost (advisory)","আনুমানিক যন্ত্রাংশ খরচ (পরামর্শমূলক)"],t:"num",val:wo.est_spares_cost}];
  const main=[{n:"title",l:["Title","শিরোনাম"],t:"text",req:true,val:wo.title,max:160},{n:"description",l:["Description","বিবরণ"],t:"textarea",val:wo.description,max:2000},
   {n:"priority",l:["Priority","অগ্রাধিকার"],t:"select",opts:enumOpts("priority",PRIORITIES),val:wo.priority},{n:"due_on",l:["Due on","শেষ তারিখ"],t:"date",val:wo.due_on?dd(wo.due_on):""},
   {n:"team_ref",l:["Team ref.","টিম রেফ."],t:"text",max:40,val:wo.team_ref}];
  const fields=estOnly?est:[...main,...est];
  modalForm(T("Edit work order","কাজের আদেশ সম্পাদনা")+" · "+(wo.wo_no||""),[...fields,REASON()],async(v,err)=>{
   const ch={};for(const f of fields){const k=f.n,ov=wo[k]==null?null:(k==="due_on"?String(wo[k]).slice(0,10):wo[k]);
    const same=typeof v[k]==="number"||typeof ov==="number"?(v[k]==null&&ov==null)||Number(v[k])===Number(ov):(v[k]==null?null:v[k])===ov;if(!same)ch[k]=v[k]}
   if(!Object.keys(ch).length){err.textContent=T("No changes to save.","সংরক্ষণের মতো কোনো পরিবর্তন নেই।");err.hidden=false;return false}
   const r=await act("am_update_work_order_v1",{p_wo:wo.id,p_expected_version:wo.version,p_changes:ch,p_reason:v.reason},"Work order updated","কাজের আদেশ হালনাগাদ",err);if(r)await reload();return !!r},T("Save","সংরক্ষণ"),"wo-edit-form");
 }
 function laborForm(wo,reload){
  modalForm(T("Add labour","শ্রম যোগ")+" · "+(wo.wo_no||""),[{n:"labor_kind",l:["Kind","ধরন"],t:"select",opts:enumOpts("labor_kind",["internal","contractor"])},{n:"worker_ref",l:["Worker ref.","কর্মী রেফ."],t:"text",max:40},
   {n:"hours",l:["Hours","ঘণ্টা"],t:"num",req:true},{n:"rate",l:["Rate (advisory)","হার (পরামর্শমূলক)"],t:"num"},{n:"phase",l:["Phase","ধাপ"],t:"select",opts:enumOpts("phase",["actual","estimate"])},{n:"note",l:["Note","নোট"],t:"text",max:300}],async(v,err)=>{
   const r=await act("am_wo_add_labor_v1",{p_wo:wo.id,p_data:clean(v)},"Labour added","শ্রম যোগ হয়েছে",err);if(r)await reload();return !!r},T("Add","যোগ"),"labor-form");
 }
 function sparesForm(wo,reload){
  modalForm(T("Add spares","যন্ত্রাংশ যোগ")+" · "+(wo.wo_no||""),[{n:"item_ref",l:["Item ref.","আইটেম রেফ."],t:"text",max:40},{n:"description",l:["Description","বিবরণ"],t:"text",req:true,max:200},
   {n:"qty",l:["Quantity","পরিমাণ"],t:"num",req:true},{n:"unit_cost",l:["Unit cost (advisory)","একক মূল্য (পরামর্শমূলক)"],t:"num"},{n:"phase",l:["Phase","ধাপ"],t:"select",opts:enumOpts("phase",["actual","estimate"])}],async(v,err)=>{
   const r=await act("am_wo_add_spares_v1",{p_wo:wo.id,p_data:clean(v)},"Spares added","যন্ত্রাংশ যোগ হয়েছে",err);if(r)await reload();return !!r},T("Add","যোগ"),"spares-form");
 }
 function attachForm(wo,reload){
  const MIMES=["image/jpeg","image/png","image/webp","application/pdf","text/plain"];
  const fl=buildForm([{n:"file_name",l:["File name","ফাইলের নাম"],t:"text",req:true,max:100},{n:"mime",l:["Type","টাইপ"],t:"select",opts:MIMES.map(m=>[m,m])},{n:"size_bytes",l:["Size (bytes)","আকার (বাইট)"],t:"num",req:true,step:"1"},
   {n:"sha256",l:["SHA-256 (hex)","SHA-256 (হেক্স)"],t:"text",req:true,max:64},{n:"storage_ref",l:["Storage reference","স্টোরেজ রেফারেন্স"],t:"text",req:true,max:200,hint:["Where the file is kept (path/id). Nothing is uploaded here.","ফাইল যেখানে রাখা (পাথ/আইডি)। এখানে কিছু আপলোড হয় না।"]},
   {n:"kind",l:["Kind","ধরন"],t:"select",opts:enumOpts("attach_kind",["photo","document","certificate","report"])},{n:"caption",l:["Caption","ক্যাপশন"],t:"text",max:200}],{prefix:"f-",id:"am-form",submitText:T("Record","রেকর্ড"),onSubmit:async(v,err)=>{
   const r=await act("am_wo_add_attachment_v1",{p_wo:wo.id,p_data:clean(v)},"Attachment recorded","সংযুক্তি রেকর্ড হয়েছে",err);if(r){closeModal();await reload()}}});
  const fi=h("input",{type:"file",id:"att-file",accept:MIMES.join(",")});
  fi.addEventListener("change",async()=>{const f=fi.files&&fi.files[0];if(!f)return;
   $("f-file_name").value=f.name.replace(/[^A-Za-z0-9._ -]/g,"_").replace(/^[^A-Za-z0-9]+/,"").slice(0,100);$("f-size_bytes").value=String(f.size);
   if(MIMES.includes(f.type))$("f-mime").value=f.type;
   try{const hash=await crypto.subtle.digest("SHA-256",await f.arrayBuffer());$("f-sha256").value=Array.from(new Uint8Array(hash),b=>b.toString(16).padStart(2,"0")).join("")}catch(e){}
   if(!$("f-storage_ref").value)$("f-storage_ref").value="wo-"+wo.id+"/"+$("f-file_name").value.replace(/ /g,"_")});
  openModal(T("Attachment record","সংযুক্তি রেকর্ড")+" · "+(wo.wo_no||""),[note(T("Only the file's details are recorded; the file is not uploaded.","শুধু ফাইলের তথ্য রেকর্ড হয়; ফাইল আপলোড হয় না।")),labeled(T("Pick a file to fill the details","বিবরণ পূরণে ফাইল বাছুন"),fi),fl.form],"attach-form");
 }
 async function mergeForm(wo,reload){
  const r=await safe(()=>rd("am_list_work_orders_v1",{p_filters:{asset_id:wo.asset_id,status:["DRAFT","SUBMITTED","APPROVED","IN_PROGRESS"]},p_limit:100,p_offset:0}));
  const opts=arr(r,"items").filter(x=>x.id!==wo.id).map(x=>[String(x.id),(x.wo_no||"#"+x.id)+" · "+x.title]);
  if(!opts.length){status(T("No other open work order on this asset to merge.","এই সম্পদে মার্জ করার মতো অন্য খোলা কাজ নেই।"),"info");return}
  modalForm(T("Merge into ","একীভূত করুন ")+(wo.wo_no||""),[{n:"merge",l:["Work order to merge in (it will be closed)","যে কাজ মার্জ হবে (এটি বন্ধ হবে)"],t:"select",int:true,req:true,opts},REASON()],async(v,err)=>{
   const x=await act("am_merge_work_orders_v1",{p_keep:wo.id,p_merge:v.merge,p_reason:v.reason},"Work orders merged","কাজের আদেশ একীভূত",err);if(x)await reload();return !!x},T("Merge","একীভূত"),"merge-form");
 }
 const doFilter=()=>{page.offset=0;refresh()};
 [st,kd,pr,mine,over].forEach(x=>x.addEventListener("change",doFilter));q.addEventListener("keydown",(e)=>{if(e.key==="Enter"){e.preventDefault();doFilter()}});
 body.append(panel(T("Work orders","কাজের আদেশ"),[filterRow([labeled(T("Search","খুঁজুন"),q),labeled(T("Status","অবস্থা"),st),labeled(T("Kind","ধরন"),kd),labeled(T("Priority","অগ্রাধিকার"),pr),
   h("label",{class:"fld bool"},h("span",{text:T("Assigned to me","আমার কাজ")}),mine),h("label",{class:"fld bool"},h("span",{text:T("Overdue only","শুধু বিলম্বিত")}),over),btn(T("Search","খুঁজুন"),doFilter,"primary","wo-search")]),
  h("div",{class:"actions"},can("report")||can("execute")?btn(T("+ New work order","+ নতুন কাজের আদেশ"),()=>woCreateForm(async()=>{await refresh()}),"primary","wo-new"):null),list],null,"wo-dir"),detail);
 await refresh();
 const qw=parseQuery().wo;if(qw)await openWo(qw);
};

/* =====================================================================  BREAKDOWN / DOWNTIME  ===================================================================== */
SCREENS.breakdown=async function(body){
 $("am-title").textContent=T("Breakdown & downtime","বিকল ও ডাউনটাইম");
 const assets=await assetPicker(T("— choose the asset that stopped —","— যে সম্পদ বন্ধ হয়েছে তা বাছুন —"),a=>!["retired","disposed"].includes(a.status)&&(state.site==null||a.site_id===state.site));
 const openBox=h("div",{id:"bd-open"}),histBox=h("div",{id:"bd-history"});
 async function refresh(){
  const o=await safe(()=>rd("am_list_downtime_v1",{p_filters:clean({open:true,site_id:state.site}),p_limit:100,p_offset:0}));
  if(o){openBox.textContent="";openBox.append(table([[T("Asset","সম্পদ"),x=>x.asset_no||x.asset_name||("#"+x.asset_id)],[T("Kind","ধরন"),x=>chip(lab("downtime_kind",x.kind),x.kind==="breakdown"?"bad":"warn")],
   [T("Since","থেকে"),x=>dt(x.started_at)],[T("Reason","কারণ"),x=>x.reason_code],[T("Impact","প্রভাব"),x=>x.impact],
   [T("Work order","কাজের আদেশ"),x=>x.work_order_id?h("a",{href:"./core10-asset-maintenance-workorders.html?biz="+state.biz+"&wo="+x.work_order_id,text:x.wo_no||("#"+x.work_order_id)}):dash],
   ["",x=>can("downtime_write",x.site_id)?btn(T("End downtime","ডাউনটাইম শেষ"),()=>endForm(x),"primary","dt-end-"+x.id):null]],arr(o,"items"),T("No open downtime. Everything is running.","কোনো খোলা ডাউনটাইম নেই। সব চলছে।")))}
  const c=await safe(()=>rd("am_list_downtime_v1",{p_filters:clean({open:false,site_id:state.site}),p_limit:20,p_offset:0}));
  if(c){histBox.textContent="";histBox.append(table([[T("Asset","সম্পদ"),x=>x.asset_no||("#"+x.asset_id)],[T("Kind","ধরন"),x=>lab("downtime_kind",x.kind)],[T("From","থেকে"),x=>dt(x.started_at)],[T("To","পর্যন্ত"),x=>dt(x.ended_at)],[T("Minutes","মিনিট"),x=>num(x.duration_minutes,0)]],arr(c,"items"),T("No closed downtime yet.","এখনো কোনো শেষ হওয়া ডাউনটাইম নেই।")))}
 }
 function endForm(x){
  modalForm(T("End downtime","ডাউনটাইম শেষ")+" · "+(x.asset_no||x.asset_id),[{n:"ended_at",l:["Ended at","শেষের সময়"],t:"dt",val:nowLocalInput()},{n:"note",l:["Note","নোট"],t:"text",max:300}],async(v,err)=>{
   const r=await act("am_end_downtime_v1",{p_downtime:x.id,p_ended_at:v.ended_at,p_note:v.note},"Downtime ended","ডাউনটাইম শেষ",err);if(r)await refresh();return !!r},T("End downtime","ডাউনটাইম শেষ"),"dt-end-form");
 }
 function startForm(){
  modalForm(T("Start downtime","ডাউনটাইম শুরু"),[{n:"asset",l:["Asset","সম্পদ"],t:"select",int:true,req:true,opts:assets},{n:"kind",l:["Kind","ধরন"],t:"select",opts:enumOpts("downtime_kind",["planned","breakdown","other"]),val:"planned"},
   {n:"reason_code",l:["Reason","কারণ"],t:"select",opts:codeOpts("downtime_reason",T("— none —","— নেই —"))},{n:"impact",l:["Impact","প্রভাব"],t:"textarea",rows:2,max:500},{n:"started_at",l:["Started at","শুরুর সময়"],t:"dt",val:nowLocalInput()}],async(v,err)=>{
   const r=await act("am_start_downtime_v1",{p_asset:v.asset,p_data:clean({kind:v.kind,reason_code:v.reason_code,impact:v.impact,started_at:v.started_at})},"Downtime started","ডাউনটাইম শুরু",err);if(r){state.assetOpts=null;await refresh()}return !!r},T("Start","শুরু"),"dt-start-form");
 }
 const bd=buildForm([{n:"asset",l:["Which asset stopped?","কোন সম্পদ বন্ধ হয়েছে?"],t:"select",int:true,req:true,opts:assets},
  {n:"title",l:["What is wrong? (short)","সমস্যা কী? (সংক্ষেপে)"],t:"text",req:true,min:3,max:160},{n:"description",l:["Details (what you saw, heard, smelled)","বিস্তারিত (কী দেখলেন, শুনলেন)"],t:"textarea",max:2000},
  {n:"priority",l:["How urgent?","কতটা জরুরি?"],t:"select",opts:enumOpts("priority",PRIORITIES),val:"high"},{n:"failure_code",l:["Type of failure","ত্রুটির ধরন"],t:"select",opts:codeOpts("failure",T("— not sure —","— নিশ্চিত নই —"))},
  {n:"impact",l:["Impact on work","কাজে প্রভাব"],t:"textarea",rows:2,max:500},{n:"started_at",l:["Stopped at","বন্ধ হয়েছে"],t:"dt",val:nowLocalInput()}],
  {prefix:"bd-",id:"bd-form",submitText:T("REPORT BREAKDOWN","বিকল জানান"),cancel:false,onSubmit:async(v,err)=>{
   const r=await act("am_report_breakdown_v1",{p_asset:v.asset,p_data:clean({title:v.title,description:v.description,priority:v.priority,failure_code:v.failure_code,impact:v.impact,occurred_at:v.started_at})},"Breakdown reported","বিকল জানানো হয়েছে",err);
   if(r){state.assetOpts=null;await refresh();$("bd-title").value="";$("bd-description").value="";$("bd-impact").value=""}}});
 bd.form.classList.add("big");
 body.append(...(can("report")?[panel(T("Report a breakdown","বিকল জানান"),[note(T("One tap to tell the maintenance team. A work order and a downtime window are opened for you.","রক্ষণাবেক্ষণ দলকে জানাতে একটি চাপ। আপনার জন্য কাজের আদেশ ও ডাউনটাইম খোলা হবে।")),bd.form],null,"bd-panel")]:[note(T("Your role cannot report breakdowns.","আপনার ভূমিকায় বিকল জানানো যায় না।"),"warn")]),
  panel(T("Open downtime","খোলা ডাউনটাইম"),openBox,can("downtime_write")?btn(T("+ Start downtime","+ ডাউনটাইম শুরু"),startForm,"outline","dt-start"):null,"bd-open-panel"),panel(T("Recently closed","সম্প্রতি শেষ"),histBox));
 await refresh();
};
/* =====================================================================  SCHEDULE  ===================================================================== */
const FREQS=["daily","weekly","monthly","yearly","usage"];
const PLAN_TYPES=["preventive","inspection","calibration","certification"];
const tid=(x)=>x.target_id!=null?x.target_id:x.id;
const itemText=(x)=>(x.wo_no?x.wo_no+" · ":"")+(x.asset_no||x.asset_name||("#"+x.asset_id))+" · "+(x.plan_name||x.title||"");
function dueChips(x){
 const c=[];if(x.state)c.push(chip(lab("due_state",x.state),toneOf(x.state)));
 const e=x.escalation_level;if(e>0)c.push(chip(lab("escalation",e),e>1?"bad":"warn"));
 return c;
}
SCREENS.schedule=async function(body){
 $("am-title").textContent=T("Maintenance schedule","রক্ষণাবেক্ষণ সূচি");
 const t0=today();const mon={y:Number(t0.slice(0,4)),m:Number(t0.slice(5,7))};
 const calBox=h("div",{id:"sc-cal"}),agBox=h("div",{id:"sc-agenda"}),sugBox=h("div",{id:"sc-sugg"}),planBox=h("div",{id:"sc-plans"}),clBox=h("div",{id:"sc-checklists"});
 const horizon=h("input",{id:"sg-horizon",type:"number",min:0,max:365,value:30,"aria-label":T("Horizon (days)","সময়সীমা (দিন)")});
 const monthLabel=h("b",{id:"sc-month"});
 const checked=new Set();let suggItems=[];
 async function loadCal(){
  const from=mon.y+"-"+pad(mon.m)+"-01",last=new Date(Date.UTC(mon.y,mon.m,0)).getUTCDate(),to=mon.y+"-"+pad(mon.m)+"-"+pad(last);
  monthLabel.textContent=from.slice(0,7);
  const r=await safe(()=>rd("am_calendar_v1",{p_from:from,p_to:to,p_site:state.site}));if(!r)return;
  const days=arr(r,"days"),by={};for(const d of days)by[String(d.date).slice(0,10)]=arr(d,"items");
  calBox.textContent="";agBox.textContent="";
  const wd=["Sun","Mon","Tue","Wed","Thu","Fri","Sat"].map((x,i)=>T(x,["রবি","সোম","মঙ্গল","বুধ","বৃহ","শুক্র","শনি"][i]));
  const grid=h("div",{class:"cal-grid",role:"grid","aria-label":T("Maintenance calendar","রক্ষণাবেক্ষণ ক্যালেন্ডার")},wd.map(x=>h("div",{class:"cal-h",role:"columnheader",text:x})));
  const lead=new Date(Date.UTC(mon.y,mon.m-1,1)).getUTCDay();
  for(let i=0;i<lead;i++)grid.append(h("div",{class:"cal-cell empty","aria-hidden":"true"}));
  for(let d=1;d<=last;d++){
   const key=mon.y+"-"+pad(mon.m)+"-"+pad(d),its=by[key]||[];
   grid.append(h("div",{class:"cal-cell"+(key===t0?" today":""),role:"gridcell","data-date":key},h("b",{text:String(d)}),
    ...its.slice(0,3).map(x=>h("div",{class:"cal-item "+toneOf(x.state)},h("span",{text:itemText(x)}))),its.length>3?h("small",{text:"+"+(its.length-3)+T(" more"," আরও")}):null));
   if(its.length)agBox.append(h("h4",{text:key}),h("ul",{class:"agenda"},its.map(x=>h("li",null,h("span",{text:itemText(x)+" "}),...dueChips(x)))));
  }
  calBox.append(grid);
  if(!agBox.children.length)agBox.append(h("p",{class:"muted",text:T("Nothing scheduled this month.","এই মাসে কিছু নির্ধারিত নেই।")}));
 }
 async function loadSugg(){
  const hz=Number(horizon.value);if(!Number.isInteger(hz)||hz<0||hz>365){status(T("Horizon must be 0-365 days.","সময়সীমা ০-৩৬৫ দিন হতে হবে।"),"error");return}
  const r=await safe(()=>rd("am_due_suggestions_v1",{p_site:state.site,p_horizon_days:hz}));if(!r)return;
  suggItems=arr(r,"items","suggestions");checked.clear();sugBox.textContent="";
  sugBox.append(table([[T("Pick","বাছুন"),x=>h("input",{type:"checkbox",class:"cb",id:"sg-check-"+tid(x),"aria-label":T("Select","বাছুন"),disabled:x.state==="has_open_wo"||x.can_generate===false,onchange:(e)=>{e.target.checked?checked.add(tid(x)):checked.delete(tid(x))}})],
   [T("Asset","সম্পদ"),x=>x.asset_no||x.asset_name||("#"+x.asset_id)],[T("Plan","পরিকল্পনা"),x=>x.plan_name||("#"+x.plan_id)],[T("Due","দেয়"),x=>x.next_due_on?dd(x.next_due_on):(x.next_due_reading!=null?num(x.next_due_reading,3):dash)],
   [T("State","অবস্থা"),x=>h("span",null,...dueChips(x))],["",x=>can("plan_write")&&x.state!=="has_open_wo"?btn(T("Defer","স্থগিত"),()=>deferForm(x),"outline","sg-defer-"+tid(x)):null]],suggItems,T("Nothing is due within the horizon.","সময়সীমায় কিছু দেয় নয়।")));
 }
 function deferForm(x){
  modalForm(T("Defer","স্থগিত")+" · "+itemText(x),[{n:"until",l:["Defer until","পর্যন্ত স্থগিত"],t:"date",req:true,val:addDays(String(x.next_due_on||today()).slice(0,10),2),hint:["Must be after the current due date and within the policy maximum deferral.","বর্তমান তারিখের পরে এবং নীতির সর্বোচ্চ স্থগিতের মধ্যে হতে হবে।"]},REASON()],async(v,err)=>{
   const r=await act("am_defer_target_v1",{p_target:tid(x),p_until:v.until,p_reason:v.reason},"Deferred","স্থগিত হয়েছে",err);if(r){await loadSugg();await loadCal()}return !!r},T("Defer","স্থগিত"),"defer-form");
 }
 function generateForm(){
  const ids=[...checked];if(!ids.length){status(T("Tick at least one suggestion first.","আগে অন্তত একটি পরামর্শ বাছুন।"),"info");return}
  const f=buildForm([],{prefix:"g-",id:"gen-form",submitText:T("Create "+ids.length+" work order(s)","কাজের আদেশ তৈরি ("+ids.length+")"),onSubmit:async(v,err)=>{
   const r=await act("am_generate_work_orders_v1",{p_target_ids:ids,p_site:state.site,p_horizon_days:Number(horizon.value)},"Work orders created","কাজের আদেশ তৈরি হয়েছে",err);
   if(r){closeModal();state.assetOpts=null;await loadSugg();await loadCal()}}});
  openModal(T("Generate work orders","কাজের আদেশ তৈরি"),[h("p",{class:"safety",id:"gen-warning",text:T("This creates work orders; nothing runs automatically.","এটি কাজের আদেশ তৈরি করে; কিছুই স্বয়ংক্রিয়ভাবে চলে না।")}),
   h("ul",null,ids.map(i=>{const x=suggItems.find(s=>tid(s)===i);return h("li",{text:x?itemText(x):("#"+i)})})),f.form],"gen-modal");
 }
 async function loadPlans(){
  const r=await safe(()=>rd("am_list_plans_v1",{p_filters:null}));if(!r)return;planBox.textContent="";
  planBox.append(table([[T("Plan","পরিকল্পনা"),x=>x.name],[T("Type","ধরন"),x=>lab("plan_type",x.plan_type)],[T("Scope","পরিধি"),x=>x.asset_no||x.asset_name||(x.asset_id?"#"+x.asset_id:(x.category_name||catName(catById(x.category_id))))],
   [T("Every","প্রতি"),x=>x.interval_n+" "+lab("frequency",x.frequency_kind)],[T("Priority","অগ্রাধিকার"),x=>lab("priority",x.priority)],[T("Active","সক্রিয়"),x=>val(x.active)],
   ["",x=>can("plan_write")?btn(T("Edit","সম্পাদনা"),()=>planForm(x),"outline","pl-edit-"+x.id):null]],arr(r,"items","plans"),T("No plans yet.","এখনো কোনো পরিকল্পনা নেই।")));
 }
 async function planForm(p){
  const assets=await assetPicker(T("— none —","— নেই —")),cls=await safe(()=>rd("am_list_checklists_v1",{p_include_inactive:false}));
  const fields=[{n:"name",l:["Plan name","পরিকল্পনার নাম"],t:"text",req:true,val:p&&p.name,max:120},{n:"plan_type",l:["Type","ধরন"],t:"select",opts:enumOpts("plan_type",PLAN_TYPES),val:p&&p.plan_type||"preventive"},
   {n:"asset_id",l:["For one asset","একটি সম্পদের জন্য"],t:"select",int:true,opts:assets,val:p&&p.asset_id!=null?p.asset_id:""},
   {n:"category_id",l:["…or a whole category","…অথবা পুরো ক্যাটাগরি"],t:"select",int:true,opts:[["",T("— none —","— নেই —")],...categories().map(c=>[String(c.id),catName(c)])],val:p&&p.category_id!=null?p.category_id:""},
   {n:"site_id",l:["Only at site","শুধু সাইটে"],t:"select",int:true,opts:siteOptsFor(null,T("— all sites —","— সব সাইট —")),val:p&&p.site_id!=null?p.site_id:""},
   {n:"frequency_kind",l:["Frequency","ফ্রিকোয়েন্সি"],t:"select",opts:enumOpts("frequency",FREQS),val:p&&p.frequency_kind||"monthly"},{n:"interval_n",l:["Every N","প্রতি N"],t:"num",step:"1",req:true,val:p?p.interval_n:1},
   {n:"meter_code",l:["Meter code (usage plans)","মিটার কোড (ব্যবহারভিত্তিক)"],t:"text",max:16,val:p&&p.meter_code},{n:"usage_interval",l:["Usage interval","ব্যবহারের ব্যবধান"],t:"num",val:p&&p.usage_interval},
   {n:"checklist_code",l:["Checklist template","চেকলিস্ট টেমপ্লেট"],t:"select",opts:[["",T("— none —","— নেই —")],...arr(cls,"items").map(c=>[c.code,c.code+" · "+c.name])],val:p&&p.checklist_code||""},
   {n:"priority",l:["Priority","অগ্রাধিকার"],t:"select",opts:enumOpts("priority",PRIORITIES),val:p&&p.priority||"medium"},{n:"est_labor_hours",l:["Est. labour hours","আনুমানিক শ্রমঘণ্টা"],t:"num",val:p&&p.est_labor_hours},
   {n:"est_cost",l:["Est. cost (advisory)","আনুমানিক খরচ (পরামর্শমূলক)"],t:"num",val:p&&p.est_cost},{n:"anchor",l:["Recurrence anchor (blank = policy)","পুনরাবৃত্তির ভিত্তি (ফাঁকা = নীতি)"],t:"select",opts:[["",T("— policy —","— নীতি —")],...enumOpts("anchor",["from_completion","from_due_date"])],val:p&&p.anchor||""},
   {n:"start_on",l:["Starts on","শুরু"],t:"date",req:true,val:p?dd(p.start_on):today()},{n:"end_on",l:["Ends on","শেষ"],t:"date",val:p&&p.end_on?dd(p.end_on):""},
   {n:"lead_days",l:["Lead days (blank = policy)","আগাম দিন (ফাঁকা = নীতি)"],t:"num",step:"1",val:p&&p.lead_days},{n:"team_ref",l:["Team ref.","টিম রেফ."],t:"text",max:40,val:p&&p.team_ref},
   {n:"active",l:["Active","সক্রিয়"],t:"bool",val:p?p.active!==false:true},REASON()];
  modalForm(p?T("Edit plan","পরিকল্পনা সম্পাদনা"):T("New plan","নতুন পরিকল্পনা"),fields,async(v,err)=>{
   if((v.asset_id==null)===(v.category_id==null)){err.textContent=T("Choose exactly one: an asset or a category.","ঠিক একটি বাছুন: সম্পদ বা ক্যাটাগরি।");err.hidden=false;return false}
   if(v.frequency_kind==="usage"&&(!v.meter_code||!v.usage_interval)){err.textContent=T("Usage plans need a meter code and a usage interval.","ব্যবহারভিত্তিক পরিকল্পনায় মিটার কোড ও ব্যবধান লাগবে।");err.hidden=false;return false}
   const d=clean(Object.assign({},v,{reason:undefined}));if(d.meter_code)d.meter_code=d.meter_code.toUpperCase();
   const r=await act("am_save_plan_v1",{p_id:p?p.id:null,p_expected_version:p?p.version:null,p_data:d,p_reason:v.reason},"Plan saved","পরিকল্পনা সংরক্ষিত",err);if(r){await loadPlans();await loadSugg();await loadCal()}return !!r},T("Save plan","পরিকল্পনা সংরক্ষণ"),"plan-form");
 }
 async function loadChecklists(){
  const r=await safe(()=>rd("am_list_checklists_v1",{p_include_inactive:true}));if(!r)return;clBox.textContent="";
  clBox.append(table([[T("Code","কোড"),x=>x.code],[T("Name","নাম"),x=>x.name],[T("Version","সংস্করণ"),x=>x.version],[T("Items","আইটেম"),x=>x.item_count!=null?x.item_count:arr(x,"items").length],[T("Active","সক্রিয়"),x=>val(x.active)],
   ["",x=>can("plan_write")?btn(T("Edit (new version)","সম্পাদনা (নতুন সংস্করণ)"),()=>checklistForm(x),"outline","cl-edit-"+x.code):null]],arr(r,"items"),T("No checklist templates.","কোনো চেকলিস্ট টেমপ্লেট নেই।")));
 }
 function checklistForm(c){
  const cols=[{n:"text",l:["Step","ধাপ"],t:"text",max:300},{n:"kind",l:["Kind","ধরন"],t:"select",keep:true,opts:enumOpts("check_kind",["check","measure","safety"])},{n:"required",l:["Required","আবশ্যক"],t:"bool"},
   {n:"min_value",l:["Min","সর্বনিম্ন"],t:"num"},{n:"max_value",l:["Max","সর্বোচ্চ"],t:"num"},{n:"unit",l:["Unit","একক"],t:"text",max:16}];
  modalForm(c?T("Edit checklist ","চেকলিস্ট সম্পাদনা ")+c.code:T("New checklist template","নতুন চেকলিস্ট টেমপ্লেট"),[
   {n:"code",l:["Code (A-Z, 0-9, _ -)","কোড"],t:"text",req:true,max:32,val:c&&c.code},{n:"name",l:["Name","নাম"],t:"text",req:true,val:c&&c.name,max:120},
   {n:"category_id",l:["Category (optional)","ক্যাটাগরি (ঐচ্ছিক)"],t:"select",int:true,opts:[["",T("— any —","— যেকোনো —")],...categories().map(x=>[String(x.id),catName(x)])],val:c&&c.category_id!=null?c.category_id:""},
   {n:"items",l:["Checklist steps","চেকলিস্টের ধাপ"],t:"rows",req:true,cols,val:arr(c,"items")},REASON()],async(v,err)=>{
   const items=v.items.map((x,i)=>clean({seq:i+1,text:x.text,kind:x.kind,required:x.required,min_value:x.min_value,max_value:x.max_value,unit:x.unit}));
   if(items.some(x=>!x.text)){err.textContent=T("Every step needs text.","প্রতিটি ধাপে লেখা লাগবে।");err.hidden=false;return false}
   const r=await act("am_save_checklist_template_v1",{p_code:v.code.toUpperCase(),p_name:v.name,p_category_id:v.category_id,p_items:items,p_reason:v.reason},"Checklist saved (new version)","চেকলিস্ট সংরক্ষিত (নতুন সংস্করণ)",err);if(r)await loadChecklists();return !!r},T("Save new version","নতুন সংস্করণ সংরক্ষণ"),"checklist-form");
 }
 const nav=h("div",{class:"actions"},btn("‹",()=>{mon.m--;if(mon.m<1){mon.m=12;mon.y--}loadCal()},"outline","sc-prev",{"aria-label":T("Previous month","আগের মাস")}),monthLabel,
  btn("›",()=>{mon.m++;if(mon.m>12){mon.m=1;mon.y++}loadCal()},"outline","sc-next",{"aria-label":T("Next month","পরের মাস")}));
 body.append(h("p",{class:"safety",id:"sc-notice",text:T("This creates work orders; nothing runs automatically. Suggestions are computed when you open this page and work orders are created only when you press the button.","এটি কাজের আদেশ তৈরি করে; কিছুই স্বয়ংক্রিয়ভাবে চলে না। পরামর্শ পেজ খোলার সময় হিসাব হয় এবং বোতাম চাপলেই কাজের আদেশ তৈরি হয়।")}),
  panel(T("Calendar","ক্যালেন্ডার"),[nav,h("div",{class:"cal-wrap"},h("div",{class:"cal-only"},calBox),h("div",{class:"agenda-only"},agBox))],null,"sc-cal-panel"),
  panel(T("Due suggestions","দেয় পরামর্শ"),[filterRow([labeled(T("Look ahead (days)","সামনের দিন"),horizon),btn(T("Refresh","রিফ্রেশ"),loadSugg,"outline","sg-refresh"),
    btn(T("Tick all due & overdue","সব দেয় ও বিলম্বিত বাছুন"),()=>{for(const x of suggItems)if(["due","overdue"].includes(x.state)){checked.add(tid(x));const c=$("sg-check-"+tid(x));if(c)c.checked=true}},"outline","sg-tick"),
    can("assign")?btn(T("Generate work orders…","কাজের আদেশ তৈরি…"),generateForm,"primary","sg-generate"):null]),sugBox],null,"sc-sugg-panel"),
  panel(T("Maintenance plans","রক্ষণাবেক্ষণ পরিকল্পনা"),planBox,can("plan_write")?btn(T("+ New plan","+ নতুন পরিকল্পনা"),()=>planForm(null),"primary","pl-new"):null),
  panel(T("Checklist templates","চেকলিস্ট টেমপ্লেট"),clBox,can("plan_write")?btn(T("+ New template","+ নতুন টেমপ্লেট"),()=>checklistForm(null),"primary","cl-new"):null));
 await loadCal();await loadSugg();await loadPlans();await loadChecklists();
};

/* =====================================================================  REPORTS  ===================================================================== */
function csvLink(r){
 const name=/^[A-Za-z0-9._-]{1,100}$/.test(String(r.filename||""))?r.filename:"core10-asset-maintenance.csv";
 const url=URL.createObjectURL(new Blob([String(r.csv==null?"":r.csv)],{type:"text/csv;charset=utf-8"}));
 setTimeout(()=>URL.revokeObjectURL(url),120000);
 return h("a",{id:"csv-link",class:"btn-link",href:url,download:name,text:name+" ("+(r.rows==null?"?":r.rows)+T(" rows"," সারি")+")"});
}
SCREENS.reports=async function(body){
 $("am-title").textContent=T("Reports","রিপোর্ট");
 const from=h("input",{id:"rep-from",type:"date",value:addDays(today(),-90)}),to=h("input",{id:"rep-to",type:"date",value:today()}),hz=h("input",{id:"rep-horizon",type:"number",min:0,max:365,value:60});
 const out=h("div",{id:"rep-out"}),tabs=h("div",{class:"tabs",role:"tablist"});
 const dates=()=>{if(!/^\d{4}-\d{2}-\d{2}$/.test(from.value)||!/^\d{4}-\d{2}-\d{2}$/.test(to.value)||from.value>to.value)throw Object.assign(new Error("am_period_invalid"),{code:"am_period_invalid"});return{p_from:from.value,p_to:to.value}};
 let cur="overview";
 const TABS=[["overview","Overview","ওভারভিউ",()=>can("reports")||can("view")],["downtime","Downtime","ডাউনটাইম",()=>can("reports")],["kpi","KPI (MTTR/MTBF)","কেপিআই (MTTR/MTBF)",()=>can("reports")],
  ["health","Asset health","সম্পদের স্বাস্থ্য",()=>can("reports")],["warranty","Warranty","ওয়ারেন্টি",()=>can("reports")],["reconciliation","Reconciliation","মিলকরণ",()=>can("reports")],
  ["integrity","Integrity","অখণ্ডতা",()=>can("reports")||can("audit_read")],["audit","Audit log","অডিট লগ",()=>can("audit_read")],["export","CSV export","CSV এক্সপোর্ট",()=>can("export")]];
 const LOAD={
  overview:async()=>{const r=await rd("am_overview_v1",{p_site:state.site});out.append(renderData(r));
   if(isOwner())out.append(btn(T("Business summary (A050 adapter, aggregate)","ব্যবসার সারাংশ (A050 অ্যাডাপ্টার, সামগ্রিক)"),async()=>{const s=await safe(()=>rd("read_asset_maintenance_business_summary_v1",{p_period:null}));if(s){sumBox.textContent="";sumBox.append(renderData(s))}},"outline","rep-summary"));out.append(sumBox)},
  downtime:async()=>{out.append(renderData(await rd("am_downtime_report_v1",Object.assign(dates(),{p_site:state.site}))))},
  kpi:async()=>{out.append(note(T("MTTR and MTBF are shown only when enough repairs/failures exist (policy minimum sample). Otherwise you will see 'Insufficient sample'.","MTTR ও MTBF কেবল পর্যাপ্ত মেরামত/ত্রুটি থাকলে দেখানো হয় (নীতির ন্যূনতম নমুনা)। নইলে 'অপর্যাপ্ত নমুনা' দেখাবে।")),renderData(await rd("am_kpi_report_v1",Object.assign(dates(),{p_site:state.site}))))},
  health:async()=>{out.append(h("p",{class:"safety",id:"rep-advisory",text:T("ADVISORY: depreciation and book values are estimates for planning only. Nothing is posted to any ledger.","পরামর্শমূলক: অবচয় ও বুক-ভ্যালু শুধু পরিকল্পনার অনুমান। কোনো লেজারে পোস্ট হয় না।")}),renderData(await rd("am_asset_health_report_v1",{p_site:state.site})))},
  warranty:async()=>{const n=Number(hz.value);out.append(renderData(await rd("am_warranty_report_v1",{p_horizon_days:Number.isInteger(n)?n:null})))},
  reconciliation:async()=>{out.append(renderData(await rd("am_reconciliation_v1",dates())))},
  integrity:async()=>{const r=await rd("am_integrity_report_v1");if(typeof r.ok==="boolean")out.append(h("p",{id:"rep-integrity-flag",class:r.ok?"good":"bad",text:r.ok?T("ALL CHECKS PASS","সব যাচাই সফল"):T("ISSUES FOUND","সমস্যা পাওয়া গেছে")}));out.append(renderData(r))},
  audit:async()=>{
   const en=h("input",{id:"aud-entity",type:"text",maxlength:40,placeholder:"asset, work_order, policy…"}),ei=h("input",{id:"aud-id",type:"text",maxlength:40}),pg={o:0};
   const box=h("div",{id:"aud-list"});
   async function go(){const r=await safe(()=>rd("am_audit_log_v1",{p_entity:en.value.trim()||null,p_entity_id:ei.value.trim()||null,p_limit:50,p_offset:pg.o}));if(!r)return;box.textContent="";
    box.append(table([[T("When","কখন"),x=>dt(x.created_at)],[T("Entity","এনটিটি"),x=>x.entity+" #"+x.entity_id],[T("Event","ঘটনা"),x=>x.event],[T("Reason","কারণ"),x=>x.reason],[T("Actor","কর্তা"),x=>x.actor_uid],[T("Hash","হ্যাশ"),x=>(x.row_hash||"").slice(0,10)]],arr(r,"items"),T("No audit rows.","কোনো অডিট সারি নেই।")),
     h("div",{class:"actions"},btn(T("Previous","আগের"),()=>{pg.o=Math.max(0,pg.o-50);go()},"outline","aud-prev",{disabled:pg.o===0}),btn(T("Next","পরের"),()=>{pg.o+=50;go()},"outline","aud-next",{disabled:arr(r,"items").length<50})))}
   out.append(filterRow([labeled(T("Entity","এনটিটি"),en),labeled(T("Entity id","এনটিটি আইডি"),ei),btn(T("Show","দেখান"),()=>{pg.o=0;go()},"primary","aud-go")]),box);await go()},
  export:async()=>{
   const kd=sel("exp-kind",enumOpts("export_kind",["assets","work_orders","downtime","schedule","warranty","audit"])),res=h("div",{id:"exp-result"});
   out.append(note(T("CSV files contain business data. The file name comes from the server.","CSV ফাইলে ব্যবসার তথ্য থাকে। ফাইলের নাম সার্ভার থেকে আসে।")),
    filterRow([labeled(T("What to export","কী এক্সপোর্ট হবে"),kd),btn(T("Export CSV","CSV এক্সপোর্ট"),async()=>{
     const p=clean({from:from.value||null,to:to.value||null,site_id:state.site});
     const r=await act("am_export_csv_v1",{p_kind:kd.value,p_params:Object.keys(p).length?p:null},"Export ready","এক্সপোর্ট প্রস্তুত");
     if(r){res.textContent="";res.append(csvLink(r))}},"primary","exp-run")]),res)}
 };
 const sumBox=h("div",{id:"rep-summary-out"});
 async function show(k){cur=k;for(const b of tabs.children)b.setAttribute("aria-selected",String(b.dataset.tab===k));out.textContent="";status(T("Loading…","লোড হচ্ছে…"),"info");
  try{await LOAD[k]();status(T("Ready · business #","প্রস্তুত · ব্যবসা #")+state.biz,"ok")}catch(e){fail(e)}}
 for(const [k,en,bn,ok] of TABS)if(ok())tabs.append(h("button",{type:"button",role:"tab",class:"tab",id:"rep-"+k,"data-tab":k,"aria-selected":"false",onclick:()=>show(k),text:T(en,bn)}));
 if(!tabs.children.length){body.append(note(T("Your role has no report access.","আপনার ভূমিকায় রিপোর্ট দেখার অনুমতি নেই।"),"warn"));return}
 body.append(panel(T("Range","সীমা"),filterRow([labeled(T("From","থেকে"),from),labeled(T("To","পর্যন্ত"),to),labeled(T("Warranty horizon (days)","ওয়ারেন্টি সময়সীমা (দিন)"),hz)])),tabs,out);
 await show(tabs.children[0].dataset.tab);
};
/* =====================================================================  SETTINGS  ===================================================================== */
const PRESETS=["recommended","showroom","factory","godown","project","office"];
const recText=(v)=>typeof v==="boolean"?(v?T("ON","চালু"):T("OFF","বন্ধ")):String(v);
function impactText(o){return o&&typeof o==="object"?Object.entries(o).map(([k,v])=>k.replace(/_/g," ")+": "+(typeof v==="object"?JSON.stringify(v):v)).join("; "):val(o)}
SCREENS.settings=async function(body){
 $("am-title").textContent=T("Settings & rules","সেটিংস ও নিয়ম");
 const scope={type:"business",id:0},draft={};let pol=null,catalog=null;
 const editor=h("div",{id:"pol-editor"}),pv=h("div",{id:"pv-out"}),dirtyNote=h("span",{id:"pol-dirty",class:"muted",text:""});
 const stype=sel("pol-scope-type",[["business",lab("scope","business")],["site",lab("scope","site")],["category",lab("scope","category")]],"business");
 const sid=sel("pol-scope-id",[]);sid.hidden=true;
 const preset=sel("pol-preset",enumOpts("preset",PRESETS),"recommended");
 const editable=()=>isOwner();
 const keyId=(k)=>"pol-"+k.replace(/[^a-z0-9]+/gi,"-");
 function fillScopeIds(){sid.textContent="";const opts=stype.value==="site"?siteOptsFor(null):categories().map(c=>[String(c.id),c.code+" · "+catName(c)]);
  for(const [v,t] of opts)sid.append(h("option",{value:v,text:t}));sid.hidden=stype.value==="business";scope.type=stype.value;scope.id=stype.value==="business"?0:Number(sid.value||0)}
 async function loadPolicy(){
  Object.keys(draft).forEach(k=>delete draft[k]);
  catalog=catalog||await rd("am_policy_catalog_v1");
  pol=await rd("am_get_policy_v1",{p_site:scope.type==="site"?scope.id:null,p_category:scope.type==="category"?scope.id:null});
  renderEditor();
 }
 const current=(k)=>pol&&pol.values&&pol.values[k]?pol.values[k].value:undefined;
 function updateDirty(){const n=Object.keys(draft).length;dirtyNote.textContent=n?n+T(" unsaved change(s)"," টি অসংরক্ষিত পরিবর্তন"):"";
  for(const b of ["pol-save","pol-preview","pol-discard"]){const e=$(b);if(e)e.disabled=!n}}
 function renderEditor(){
  editor.textContent="";const items=arr(catalog,"items"),groups=[];
  for(const it of items){if(!groups.includes(it.group))groups.push(it.group)}
  for(const g of groups){
   const det=h("details",{class:"grp",open:g==="work_order"?true:null},h("summary",{text:CAT.groupLabel(g,state.lang)}));
   for(const it of items.filter(x=>x.group===g)){
    const help=CAT.POLICY_HELP[it.key],pv0=pol&&pol.values?pol.values[it.key]:null,cur=pv0?pv0.value:it.default;
    const scopeOk=arr(it,"scopes").includes(scope.type),levelOk=it.level!=="tenant_owner"||isTenantOwner();
    const can_edit=editable()&&scopeOk&&levelOk,id=keyId(it.key);
    let input;
    if(it.vtype==="bool"){input=h("input",{id,type:"checkbox",class:"cb"});input.checked=cur===true}
    else if(it.vtype==="enum"){input=sel(id,arr(it,"enum").map(x=>[x,x]),cur)}
    else if(it.vtype==="text"){input=h("input",{id,type:"text",maxlength:64,value:cur==null?"":cur})}
    else input=h("input",{id,type:"number",step:it.vtype==="int"?"1":"any",min:it.min==null?null:it.min,max:it.max==null?null:it.max,value:cur==null?"":cur});
    input.setAttribute("aria-label",help?T(help.label[0],help.label[1]):it.key);
    if(!can_edit)input.disabled=true;
    const badge=h("span",{class:"chip "+(eq(cur,help?help.rec:it.default)?"good":"warn"),id:id+"-badge",text:eq(cur,help?help.rec:it.default)?T("Recommended","সুপারিশকৃত"):T("Custom","কাস্টম")});
    const srcChip=pv0?chip(T("source: ","উৎস: ")+pv0.source,pv0.source==="default"?"dim":""):null;
    const helpBox=h("div",{class:"help",id:id+"-help",hidden:true});
    if(help){
     const rows=[[T("What it does","কী করে"),help.what],[T("Why it matters","কেন গুরুত্বপূর্ণ"),help.why],[T("When to change it","কখন বদলাবেন"),help.when],[T("Example","উদাহরণ"),help.example],[T("Risk","ঝুঁকি"),help.risk]];
     helpBox.append(kv([...rows.map(([k,v])=>[k,T(v[0],v[1])]),[T("Recommended value","সুপারিশকৃত মান"),recText(help.rec)],[T("Allowed","অনুমোদিত"),it.vtype==="enum"?arr(it,"enum").join(" | "):(it.min!=null?it.min+" … "+it.max:it.vtype)],
      [T("Can be set at","যেখানে সেট করা যায়"),arr(it,"scopes").map(s=>lab("scope",s)).join(", ")+(it.level==="tenant_owner"?" · "+T("tenant owner only","শুধু টেন্যান্ট মালিক"):"")]]));
    }
    const onChange=()=>{
     let nv;if(it.vtype==="bool")nv=input.checked;else if(it.vtype==="int"||it.vtype==="num"){if(input.value===""){nv=cur}else nv=Number(input.value)}else nv=input.value;
     if(eq(nv,cur))delete draft[it.key];else draft[it.key]=nv;row.classList.toggle("dirty",it.key in draft);updateDirty()};
    input.addEventListener("change",onChange);
    const row=h("div",{class:"pol-row",id:id+"-row"},h("div",{class:"pol-main"},h("label",{class:"pol-label",for:id},h("b",{text:help?T(help.label[0],help.label[1]):it.key}),h("small",{text:it.key})),input),
     h("div",{class:"pol-meta"},badge,srcChip,!scopeOk?chip(T("not settable here","এখানে সেট করা যায় না"),"dim"):null,
      btn("?",()=>{helpBox.hidden=!helpBox.hidden;hb.setAttribute("aria-expanded",String(!helpBox.hidden))},"outline help-btn",id+"-helpbtn",{"aria-label":T("Explain this setting","এই সেটিং ব্যাখ্যা")}),
      can_edit&&pv0&&pv0.source===scope.type?btn(T("Reset","রিসেট"),()=>resetKey(it.key),"outline",id+"-reset"):null),helpBox);
    const hb=row.querySelector(".help-btn");hb.setAttribute("aria-expanded","false");hb.setAttribute("aria-controls",id+"-help");
    det.append(row);
   }
   editor.append(det);
  }
  updateDirty();
 }
 async function resetKey(k){
  modalForm(T("Reset to inherited value","উত্তরাধিকারী মানে ফেরান")+" · "+k,[REASON()],async(v,err)=>{
   const r=await act("am_reset_policy_v1",{p_expected_rev:pol.policy_rev,p_scope_type:scope.type,p_scope_id:scope.id,p_keys:[k],p_reason:v.reason},"Setting reset","সেটিং রিসেট",err);if(r){await loadPolicy();await refreshHistory()}return !!r},T("Reset","রিসেট"),"reset-form");
 }
 function saveForm(){
  const n=Object.keys(draft).length;if(!n)return;
  modalForm(T("Save "+n+" setting(s)","সেটিং সংরক্ষণ ("+n+")"),[h("div"),REASON()].slice(1),async(v,err)=>{
   const r=await act("am_save_policy_v1",{p_expected_rev:pol.policy_rev,p_scope_type:scope.type,p_scope_id:scope.id,p_changes:Object.assign({},draft),p_reason:v.reason},"Settings saved","সেটিং সংরক্ষিত",err);
   if(r){await loadPolicy();await refreshHistory()}return !!r},T("Save settings","সেটিং সংরক্ষণ"),"save-policy-form");
 }
 async function previewImpact(){
  const n=Object.keys(draft).length;if(!n)return;
  pv.textContent="";
  const r=await safe(()=>rd("am_preview_policy_v1",{p_scope_type:scope.type,p_scope_id:scope.id,p_changes:Object.assign({},draft)}));if(!r)return;
  pv.append(h("div",{class:"safety sim",id:"pv-banner",role:"note"},h("b",{text:T("SIMULATION — no real asset is changed","সিমুলেশন — কোনো প্রকৃত সম্পদ বদলায় না")}),r.message?h("div",{text:r.message}):null),
   r.requires_tenant_owner?note(T("Some of these settings can only be saved by a tenant owner.","এর কিছু সেটিং শুধু টেন্যান্ট মালিক সংরক্ষণ করতে পারেন।"),"warn"):null,
   table([[T("Setting","সেটিং"),x=>CAT.POLICY_HELP[x.key]?T(CAT.POLICY_HELP[x.key].label[0],CAT.POLICY_HELP[x.key].label[1]):x.key],[T("Now","এখন"),x=>recText(x.old)],[T("Would become","হবে"),x=>recText(x.new)],
    [T("Changed","বদলায়"),x=>chip(x.changed?T("yes","হ্যাঁ"):T("no","না"),x.changed?"warn":"dim")],[T("Expected impact","সম্ভাব্য প্রভাব"),x=>impactText(x.impact)]],arr(r,"items"),T("No effect.","কোনো প্রভাব নেই।")));
 }
 function applyPresetForm(){
  modalForm(T("Apply preset","প্রিসেট প্রয়োগ")+" · "+lab("preset",preset.value),[h("div"),REASON()].slice(1),async(v,err)=>{
   const r=await act("am_apply_preset_v1",{p_expected_rev:pol.policy_rev,p_preset:preset.value,p_scope_type:scope.type,p_scope_id:scope.id,p_reason:v.reason},"Preset applied","প্রিসেট প্রয়োগ হয়েছে",err);
   if(r){await loadPolicy();await refreshHistory()}return !!r},T("Apply preset","প্রিসেট প্রয়োগ"),"preset-form");
 }
 /* schedule simulator */
 const simOut=h("div",{id:"sim-out"});
 const sim=buildForm([{n:"frequency_kind",l:["Frequency","ফ্রিকোয়েন্সি"],t:"select",opts:enumOpts("frequency",FREQS),val:"monthly"},{n:"interval_n",l:["Every N","প্রতি N"],t:"num",step:"1",val:1},
  {n:"start_on",l:["Starts on","শুরু"],t:"date",val:today()},{n:"count",l:["How many occurrences (max 24)","কতবার (সর্বোচ্চ ২৪)"],t:"num",step:"1",val:6},
  {n:"typical_delay_days",l:["Typical delay (days)","সাধারণ দেরি (দিন)"],t:"num",step:"1",val:0},{n:"anchor",l:["Anchor","ভিত্তি"],t:"select",opts:[["",T("— policy —","— নীতি —")],...enumOpts("anchor",["from_completion","from_due_date"])]},
  {n:"usage_interval",l:["Usage interval (usage plans)","ব্যবহারের ব্যবধান"],t:"num"},{n:"avg_daily_usage",l:["Average daily usage","গড় দৈনিক ব্যবহার"],t:"num"},{n:"current_reading",l:["Current reading","বর্তমান রিডিং"],t:"num"}],
  {prefix:"sim-",id:"sim-form",submitText:T("Simulate schedule","সূচি সিমুলেট"),cancel:false,onSubmit:async(v,err)=>{
   const p=clean(v);const r=await safe(()=>rd("am_simulate_schedule_v1",{p_params:p}));if(!r)return;simOut.textContent="";
   simOut.append(h("div",{class:"safety sim",id:"sim-banner"},h("b",{text:T("SIMULATION — no real asset is changed","সিমুলেশন — কোনো প্রকৃত সম্পদ বদলায় না")}),r.message?h("div",{text:r.message}):null),renderData({items:arr(r,"items")}))}});
 /* grants */
 const grantBox=h("div",{id:"gr-list"}),catBox=h("div",{id:"cat-list"}),codeBox=h("div",{id:"code-list"}),histBox=h("div",{id:"hist-list"});
 const codeKind=sel("code-kind",enumOpts("code_kind",["failure","cause","action","downtime_reason","service_category"]),"failure");
 async function refreshGrants(){
  if(!isOwner()){grantBox.append(note(T("Only owners manage role grants.","শুধু মালিক ভূমিকা বরাদ্দ করতে পারেন।")));return}
  const r=await safe(()=>rd("am_list_grants_v1"));if(!r)return;grantBox.textContent="";
  grantBox.append(table([[T("User","ব্যবহারকারী"),x=>x.user_id],[T("Role","ভূমিকা"),x=>lab("role",x.role)],[T("Site","সাইট"),x=>x.site_id==null?T("All sites","সব সাইট"):siteName(x.site_id)],[T("Active","সক্রিয়"),x=>chip(x.active?T("active","সক্রিয়"):T("revoked","প্রত্যাহৃত"),x.active?"good":"dim")],[T("Note","নোট"),x=>x.note],
   ["",x=>x.active?btn(T("Revoke","প্রত্যাহার"),()=>revokeForm(x),"outline","gr-revoke-"+x.id):null]],arr(r,"items"),T("No maintenance roles granted yet.","এখনো কোনো ভূমিকা দেওয়া হয়নি।")));
 }
 function grantForm(){
  modalForm(T("Grant maintenance role","রক্ষণাবেক্ষণ ভূমিকা দিন"),[{n:"user",l:["User id (UUID)","ব্যবহারকারী আইডি (UUID)"],t:"uuid",req:true,max:36},{n:"role",l:["Role","ভূমিকা"],t:"select",opts:enumOpts("role",["supervisor","technician","reporter","auditor"]),val:"technician"},
   {n:"site",l:["Site","সাইট"],t:"select",int:true,opts:siteOptsFor(null,T("All sites of this business","এই ব্যবসার সব সাইট"))},{n:"note",l:["Note","নোট"],t:"text",max:200},REASON()],async(v,err)=>{
   if(!UUID_RX.test(v.user)){err.textContent=T("User id must be a valid UUID.","ব্যবহারকারী আইডি সঠিক UUID হতে হবে।");err.hidden=false;return false}
   const r=await act("am_grant_role_v1",{p_user:v.user,p_role:v.role,p_site:v.site,p_note:v.note,p_reason:v.reason},"Role granted","ভূমিকা দেওয়া হয়েছে",err);if(r)await refreshGrants();return !!r},T("Grant","দিন"),"grant-form");
 }
 function revokeForm(g){
  modalForm(T("Revoke role","ভূমিকা প্রত্যাহার")+" · "+lab("role",g.role),[REASON()],async(v,err)=>{
   const r=await act("am_revoke_role_v1",{p_grant:g.id,p_reason:v.reason},"Role revoked","ভূমিকা প্রত্যাহৃত",err);if(r)await refreshGrants();return !!r},T("Revoke","প্রত্যাহার"),"revoke-form");
 }
 /* categories & codes */
 function renderCats(){
  catBox.textContent="";catBox.append(table([[T("Code","কোড"),x=>x.code],[T("Name","নাম"),x=>catName(x)],[T("Kind","ধরন"),x=>lab("asset_kind",x.asset_kind)],[T("Crit.","গুরুত্ব"),x=>x.default_criticality],[T("Safety","নিরাপত্তা"),x=>val(x.safety_critical)],[T("Active","সক্রিয়"),x=>val(x.active)],
   ["",x=>isOwner()?btn(T("Edit","সম্পাদনা"),()=>categoryForm(x),"outline","cat-edit-"+x.code):null]],categories(),T("No categories.","কোনো ক্যাটাগরি নেই।")));
 }
 function categoryForm(c){
  modalForm(c?T("Edit category","ক্যাটাগরি সম্পাদনা"):T("New category","নতুন ক্যাটাগরি"),[{n:"code",l:["Code (A-Z, 0-9, _ -)","কোড"],t:"text",req:true,max:24,val:c&&c.code},{n:"name",l:["Name (English)","নাম (ইংরেজি)"],t:"text",req:true,max:80,val:c&&c.name},{n:"name_bn",l:["Name (Bangla)","নাম (বাংলা)"],t:"text",max:80,val:c&&c.name_bn},
   {n:"parent_id",l:["Parent category","প্যারেন্ট ক্যাটাগরি"],t:"select",int:true,opts:[["",T("— none —","— নেই —")],...categories().filter(x=>!c||x.id!==c.id).map(x=>[String(x.id),catName(x)])],val:c&&c.parent_id!=null?c.parent_id:""},
   {n:"asset_kind",l:["Asset kind","সম্পদের ধরন"],t:"select",opts:enumOpts("asset_kind",["fixed_asset","equipment","tool","vehicle","it","facility","other"]),val:c&&c.asset_kind||"equipment"},
   {n:"default_criticality",l:["Default criticality (1-5)","ডিফল্ট গুরুত্ব (১-৫)"],t:"select",int:true,opts:[1,2,3,4,5].map(x=>[String(x),String(x)]),val:c?c.default_criticality:3},
   {n:"default_meter_unit",l:["Default meter unit","ডিফল্ট মিটার একক"],t:"select",opts:[["",T("— none —","— নেই —")],...enumOpts("meter_unit",["hours","km","cycles","units"])],val:c&&c.default_meter_unit||""},
   {n:"useful_life_months",l:["Useful life (months, advisory)","আয়ু (মাস, পরামর্শমূলক)"],t:"num",step:"1",val:c&&c.useful_life_months},{n:"salvage_pct",l:["Salvage % (advisory)","উদ্ধার % (পরামর্শমূলক)"],t:"num",val:c&&c.salvage_pct},
   {n:"safety_critical",l:["Safety-critical","নিরাপত্তা-সংবেদনশীল"],t:"bool",val:c&&c.safety_critical},{n:"active",l:["Active","সক্রিয়"],t:"bool",val:c?c.active!==false:true},REASON()],async(v,err)=>{
   const d=clean(Object.assign({},v,{reason:undefined}));d.code=d.code.toUpperCase();d.safety_critical=!!v.safety_critical;d.active=!!v.active;
   const r=await act("am_save_category_v1",{p_id:c?c.id:null,p_expected_version:c?c.version:null,p_data:d,p_reason:v.reason},"Category saved","ক্যাটাগরি সংরক্ষিত",err);if(r){state.cat=await rd("am_list_catalog_v1");renderCats()}return !!r},T("Save category","ক্যাটাগরি সংরক্ষণ"),"category-form");
 }
 function renderCodes(){
  codeBox.textContent="";codeBox.append(table([[T("Code","কোড"),x=>x.code],[T("Label","লেবেল"),x=>x.label],[T("Label (Bangla)","লেবেল (বাংলা)"),x=>x.label_bn],[T("Active","সক্রিয়"),x=>val(x.active)],
   ["",x=>isOwner()?btn(T("Edit","সম্পাদনা"),()=>codeForm(x),"outline","code-edit-"+x.code):null]],codesOf(codeKind.value,true),T("No codes of this kind.","এই ধরনের কোনো কোড নেই।")));
 }
 function codeForm(c){
  modalForm(c?T("Edit code","কোড সম্পাদনা"):T("New code","নতুন কোড"),[{n:"kind",l:["Kind","ধরন"],t:"select",opts:enumOpts("code_kind",["failure","cause","action","downtime_reason","service_category"]),val:c?c.kind:codeKind.value},
   {n:"code",l:["Code (A-Z, 0-9, _ -)","কোড"],t:"text",req:true,max:24,val:c&&c.code},{n:"label",l:["Label (English)","লেবেল (ইংরেজি)"],t:"text",req:true,max:80,val:c&&c.label},{n:"label_bn",l:["Label (Bangla)","লেবেল (বাংলা)"],t:"text",max:80,val:c&&c.label_bn},
   {n:"active",l:["Active","সক্রিয়"],t:"bool",val:c?c.active!==false:true},REASON()],async(v,err)=>{
   const r=await act("am_save_code_v1",{p_kind:v.kind,p_code:v.code.toUpperCase(),p_label:v.label,p_label_bn:v.label_bn,p_active:!!v.active,p_reason:v.reason},"Code saved","কোড সংরক্ষিত",err);if(r){state.cat=await rd("am_list_catalog_v1");renderCodes()}return !!r},T("Save code","কোড সংরক্ষণ"),"code-form");
 }
 async function refreshHistory(){
  if(!(isOwner()||can("audit_read"))){histBox.textContent="";histBox.append(note(T("History is visible to owners and auditors.","ইতিহাস মালিক ও অডিটর দেখতে পারেন।")));return}
  const r=await safe(()=>rd("am_policy_history_v1",{p_limit:50}));if(!r)return;histBox.textContent="";
  histBox.append(table([[T("When","কখন"),x=>dt(x.created_at)],[T("Setting","সেটিং"),x=>x.key],[T("Scope","পরিধি"),x=>x.scope_type+(x.scope_id?" #"+x.scope_id:"")],[T("From","থেকে"),x=>x.old_value==null?dash:JSON.stringify(x.old_value)],[T("To","হয়েছে"),x=>JSON.stringify(x.new_value)],[T("Rev","রিভ"),x=>x.rev],[T("Reason","কারণ"),x=>x.reason]],arr(r,"items"),T("No changes recorded yet.","এখনো কোনো পরিবর্তন রেকর্ড হয়নি।")));
 }
 stype.addEventListener("change",async()=>{fillScopeIds();await safe(loadPolicy)});
 sid.addEventListener("change",async()=>{scope.id=Number(sid.value||0);await safe(loadPolicy)});
 codeKind.addEventListener("change",renderCodes);
 fillScopeIds();
 body.append(
  panel(T("Rules (policy)","নিয়ম (পলিসি)"),[note(T("Every business rule below is a setting with a safe default. Press ? on any row to see what it does, why, when to change it, an example and the risk. Your role and the server decide who may save.","নিচের প্রতিটি ব্যবসায়িক নিয়ম নিরাপদ ডিফল্টসহ একটি সেটিং। যেকোনো সারিতে ? চাপলে কী করে, কেন, কখন বদলাবেন, উদাহরণ ও ঝুঁকি দেখা যাবে। কে সংরক্ষণ করতে পারবেন তা আপনার ভূমিকা ও সার্ভার ঠিক করে।")),
    filterRow([labeled(T("Applies to","প্রযোজ্য"),stype),h("label",{class:"fld",hidden:null},h("span",{text:T("Which one","কোনটি")}),sid),
     labeled(T("Preset","প্রিসেট"),preset),editable()?btn(T("Apply preset…","প্রিসেট প্রয়োগ…"),applyPresetForm,"outline","pol-preset-apply"):null]),
    editable()?h("div",{class:"actions sticky"},btn(T("Preview impact","প্রভাব দেখুন"),previewImpact,"outline","pol-preview",{disabled:true}),btn(T("Save changes…","পরিবর্তন সংরক্ষণ…"),saveForm,"primary","pol-save",{disabled:true}),
     btn(T("Discard","বাতিল"),()=>renderEditor()||Object.keys(draft).forEach(k=>delete draft[k])||loadPolicy(),"outline","pol-discard",{disabled:true}),dirtyNote):note(T("You can read these settings but only owners can change them.","আপনি সেটিং দেখতে পারেন, বদলাতে পারেন শুধু মালিক।")),
    pv,editor],null,"pol-panel"),
  panel(T("Schedule simulator","সূচি সিমুলেটর"),[note(T("Try a recurrence pattern and see when it would fall due. Nothing is created.","একটি পুনরাবৃত্তির ধরন চেষ্টা করে দেখুন কবে দেয় হবে। কিছু তৈরি হয় না।")),sim.form,simOut],null,"sim-panel"),
  panel(T("Maintenance roles","রক্ষণাবেক্ষণ ভূমিকা"),grantBox,isOwner()?btn(T("+ Grant role","+ ভূমিকা দিন"),grantForm,"primary","gr-new"):null,"gr-panel"),
  panel(T("Asset categories","সম্পদ ক্যাটাগরি"),catBox,isOwner()?btn(T("+ New category","+ নতুন ক্যাটাগরি"),()=>categoryForm(null),"primary","cat-new"):null,"cat-panel"),
  panel(T("Reason & status codes","কারণ ও অবস্থার কোড"),[filterRow([labeled(T("Kind","ধরন"),codeKind),isOwner()?btn(T("+ New code","+ নতুন কোড"),()=>codeForm(null),"primary","code-new"):null]),codeBox],null,"code-panel"),
  panel(T("Settings history","সেটিংয়ের ইতিহাস"),histBox,null,"hist-panel"));
 renderCats();renderCodes();
 await loadPolicy();await refreshGrants();await refreshHistory();
};

boot().catch((e)=>{try{fail(e)}catch(x){}});
})();

