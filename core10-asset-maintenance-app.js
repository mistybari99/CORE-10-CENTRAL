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
   h("div",{class:"rail-note",text:T("Authority comes from the server. Money fields are advisory; nothing here posts to stock, ledger or payroll.","ক্ষমতা সার্ভার থেকে আসে। অর্থের ঘর পরামর্শমূলক; এখান থেকে স্টক, লেজার বা বেতনে কিছু পোস্ট হয় না।"))),
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
  const fields=[{n:"decision_note",l:["Note","নোট"],t:"textarea",rows:2,max:500}];
  if(a==="settle")fields.unshift({n:"amount_settled",l:["Amount settled (advisory)","নিষ্পন্ন পরিমাণ (পরামর্শমূলক)"],t:"num",req:true},{n:"supplier_claim_ref",l:["Supplier claim ref.","সরবরাহকারীর দাবি রেফ."],t:"text",max:60});
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
   const data=clean({asset_id:a.id,supplier_name:v.supplier_name,supplier_ref:v.supplier_ref,starts_on:v.starts_on,expires_on:v.expires_on,coverage:v.coverage,status:v.status});
   const r=await act("am_save_warranty_v1",{p_id:w?w.id:null,p_expected_version:w?w.version:null,p_data:data,p_reason:v.reason},"Warranty saved","ওয়ারেন্টি সংরক্ষিত",err);if(r)await reload();return !!r},T("Save","সংরক্ষণ"),"warranty-form");
 }
 function claimForm(a,w,c,reload){
  modalForm(T("Warranty claim","ওয়ারেন্টি দাবি")+" · "+a.asset_no,[{n:"failure_on",l:["Failure date","ত্রুটির তারিখ"],t:"date",req:true,val:c&&dd(c.failure_on)||today()},
   {n:"description",l:["What failed","কী ব্যর্থ হয়েছে"],t:"textarea",req:true,min:3,val:c&&c.description,max:1000},{n:"amount_claimed",l:["Amount claimed (advisory)","দাবির পরিমাণ (পরামর্শমূলক)"],t:"num",val:c&&c.amount_claimed},
   {n:"supplier_claim_ref",l:["Supplier claim ref.","সরবরাহকারীর দাবি রেফ."],t:"text",max:60,val:c&&c.supplier_claim_ref}],async(v,err)=>{
   const r=await act("am_save_claim_v1",{p_id:c?c.id:null,p_expected_version:c?c.version:null,p_data:clean(Object.assign({warranty_id:w.id,asset_id:a.id},v))},"Claim saved","দাবি সংরক্ষিত",err);if(r){await reload()}return !!r},T("Save claim","দাবি সংরক্ষণ"),"claim-form");
 }
 const bar=h("div",{class:"actions"},can("asset_write")?btn(T("+ New asset","+ নতুন সম্পদ"),()=>assetForm(null,async()=>{await refresh()}),"primary","as-new"):null);
 const doFilter=()=>{page.offset=0;refresh()};
 [st,cs,ow].forEach(x=>x.addEventListener("change",doFilter));q.addEventListener("keydown",(e)=>{if(e.key==="Enter"){e.preventDefault();doFilter()}});
 body.append(panel(T("Directory","তালিকা"),[filterRow([labeled(T("Search","খুঁজুন"),q),labeled(T("Status","অবস্থা"),st),labeled(T("Category","ক্যাটাগরি"),cs),labeled(T("Ownership","মালিকানা"),ow),btn(T("Search","খুঁজুন"),doFilter,"primary","as-search")]),bar,list],null,"as-dir"),
  detail,panel(T("Transfers","স্থানান্তর"),trBox),panel(T("Warranty claims","ওয়ারেন্টি দাবি"),clBox));
 await refresh();await refreshSide();
 const qa=parseQuery().asset;if(qa)await openAsset(qa);
};
/*@@CONT@@*/
