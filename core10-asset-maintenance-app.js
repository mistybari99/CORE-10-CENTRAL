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
/*@@CONT@@*/
