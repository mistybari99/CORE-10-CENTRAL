/* C10-A051 Workforce UI (Employee Directory, Attendance, Shifts/Leave, Payroll, Reports, My Work).
 * All data/authority comes from the signed Workforce RPC adapter. DOM is built with textContent only (no innerHTML of data).
 * UI capability flags are advisory hints from the server; every action is re-checked by the database.
 */
(function(){"use strict";
const SCREEN=document.body.dataset.screen||"directory";
const NAV=[["directory","core10-workforce-directory.html","Directory","কর্মী"],["attendance","core10-workforce-attendance.html","Attendance","হাজিরা"],
 ["leave","core10-workforce-leave.html","Shifts & Leave","শিফট/ছুটি"],["payroll","core10-workforce-payroll.html","Payroll","বেতন"],
 ["reports","core10-workforce-reports.html","Reports","রিপোর্ট"],["self","core10-workforce-self.html","My Work","আমার"]];
const ERR={wf_denied:"You have no Workforce access for this business.",wf_owner_required:"Only a business/tenant owner can do this.",
 wf_manager_required:"Manager or owner access is required.",wf_payroll_access_denied:"Payroll is restricted to authorised owners.",
 wf_stale_version:"This record changed elsewhere. Reload and retry.",wf_idempotency_conflict:"That request key was already used for different data.",
 wf_period_locked:"This period is locked by payroll review/approval/freeze.",wf_leave_overlap:"Leave overlaps an existing request.",
 wf_leave_quota_exceeded:"Leave quota exceeded.",wf_leave_affects_frozen_period:"Leave would change a locked payroll period.",
 wf_approver_must_differ:"The approver must be someone other than the requester.",wf_maker_checker_violation:"Preparer cannot review/approve own payroll run.",
 wf_payroll_blocking_exceptions:"Resolve blocking exceptions and recalculate first.",wf_payroll_inputs_changed:"Inputs changed since the draft. Recalculate the draft.",
 wf_period_already_frozen_amend_required:"Period is frozen. Create an amendment with a reason.",wf_payroll_in_progress:"A payroll run is already in progress for this period.",
 wf_employee_no_duplicate:"Employee number already exists.",wf_user_already_linked:"That login is already linked to another employee.",
 wf_invalid_input:"Some input is invalid.",wf_self_correction_denied:"Nobody can correct their own attendance."};
const state={api:null,biz:null,businesses:[],ov:null,cat:null,busy:false};
const $=(id)=>document.getElementById(id);
function h(tag,props,...kids){const e=document.createElement(tag);
 for(const [k,v] of Object.entries(props||{})){if(v==null||v===false)continue;
  if(k==="class")e.className=v;else if(k==="text")e.textContent=v;else if(k.startsWith("on"))e.addEventListener(k.slice(2),v);
  else if(v===true)e.setAttribute(k,"");else e.setAttribute(k,String(v));}
 for(const c of kids.flat(2)){if(c==null||c===false)continue;e.append(c&&c.nodeType?c:document.createTextNode(String(c)))}
 return e}
const money=(v)=>v==null?"—":Number(v).toLocaleString("en-US",{minimumFractionDigits:2,maximumFractionDigits:2});
const today=()=>new Date(Date.now()+6*3600e3).toISOString().slice(0,10);
const addDays=(d,n)=>{const x=new Date(d+"T00:00:00Z");x.setUTCDate(x.getUTCDate()+n);return x.toISOString().slice(0,10)};
const monthStart=(d)=>d.slice(0,7)+"-01";
function status(msg,tone){const n=$("wf-status");if(n){n.textContent=msg;n.dataset.tone=tone||"ok"}}
function fail(e){status((ERR[e&&e.code]||ERR[e&&e.message]||(e&&e.message)||"Request failed"),"error")}
function cap(k){return !!(state.ov&&state.ov.capabilities&&state.ov.capabilities[k])}
async function call(name,params,okMsg){
 const spec=window.CORE10_WORKFORCE_API.SPEC[name],write=!!(spec&&spec.w);
 if(write){if(state.busy)return null;state.busy=true;document.body.dataset.busy="1"}
 try{const r=await state.api.call(name,Object.assign({p_business:state.biz},params||{}));if(okMsg)status(okMsg,"ok");return r}
 catch(e){fail(e);return null}finally{if(write){state.busy=false;delete document.body.dataset.busy}}}
const key=(p)=>state.api.requestKey(p);
function field(label,input,hint){return h("label",{class:"fld"},h("span",{text:label}),input,hint?h("small",{text:hint}):null)}
function sel(id,options,value){const s=h("select",{id});for(const [v,t] of options)s.append(h("option",{value:v,text:t}));if(value!=null)s.value=value;return s}
function inp(id,type,value,extra){return h("input",Object.assign({id,type:type||"text",value:value==null?"":value,autocomplete:"off"},extra||{}))}
function btn(text,fn,cls,id){return h("button",{type:"button",class:cls||"",id,onclick:fn,text})}
function table(cols,rows,empty){
 if(!rows.length)return h("p",{class:"muted",text:empty||"Nothing to show."});
 return h("div",{class:"tbl-wrap"},h("table",null,h("thead",null,h("tr",null,cols.map(c=>h("th",{text:c[0]})))),
  h("tbody",null,rows.map(r=>h("tr",null,cols.map(c=>h("td",{"data-label":c[0]},c[1](r))))))))}
const chip=(t,tone)=>h("span",{class:"chip "+(tone||""),text:String(t).replace(/_/g," ")});
const tone=(s)=>({present:"good",paid_leave:"good",approved:"good",frozen:"good",absent:"bad",incomplete:"bad",rejected:"bad",unpaid_leave:"warn",half_day:"warn",pending:"warn",draft:"warn",reviewed:"warn",weekly_off:"dim",holiday:"dim",future:"dim"}[s]||"");
function panel(title,body,right){return h("section",{class:"panel"},h("div",{class:"panel-title"},h("h2",{text:title}),right||null),h("div",{class:"panel-body"},body))}

async function shell(){
 const root=$("wf-root");root.textContent="";
 const nav=h("nav",{class:"rail-nav","aria-label":"Workforce navigation"},NAV.map(n=>h("a",{href:"./"+n[1],class:n[0]===SCREEN?"active":null,"data-nav":n[0]},h("b",{text:n[2]}),h("small",{text:n[3]}))));
 root.append(h("div",{class:"wf-layout"},
  h("aside",{class:"rail"},h("div",{class:"brand"},"CORE ",h("b",{text:"10"}),h("small",{text:"WORKFORCE · A051"})),nav,
   h("div",{class:"rail-note",text:"Authority comes from the server. Approved ≠ Paid: this module never moves money."})),
  h("main",null,h("div",{class:"topline"},h("span",{text:"WORKFORCE / ATTENDANCE / LEAVE / PAYROLL"}),h("span",{id:"wf-level",class:"badge",text:"…"})),
   h("div",{class:"headline"},h("h1",{id:"wf-title"}),h("label",{class:"biz"},h("span",{text:"Business"}),h("select",{id:"wf-biz","aria-label":"Business"}))),
   h("div",{id:"wf-status",role:"status","aria-live":"polite",text:"Verifying signed session…"}),h("div",{id:"wf-body"}))));
 $("wf-biz").addEventListener("change",async(e)=>{state.biz=Number(e.target.value);await load()});
}
async function boot(){
 await shell();
 try{
  const cfg=window.BOS_CONFIG,lib=window.supabase;
  if(!cfg||!cfg.url||!cfg.key||!lib||typeof lib.createClient!=="function")throw Object.assign(new Error("SIGNED_SUPABASE_CLIENT_REQUIRED"),{code:"SIGNED_SUPABASE_CLIENT_REQUIRED"});
  state.api=window.CORE10_WORKFORCE_API.create({client:lib.createClient(cfg.url,cfg.key)});
  const mine=await state.api.call("my_businesses",{});
  state.businesses=mine.items;
  const sb=$("wf-biz");sb.textContent="";
  if(!state.businesses.length){status("No Workforce access for this account.","error");return}
  for(const b of state.businesses)sb.append(h("option",{value:b.id,text:"#"+b.id+" · "+b.slug}));
  const want=Number(new URLSearchParams(location.search).get("biz"));
  state.biz=state.businesses.some(b=>b.id===want)?want:state.businesses[0].id;sb.value=String(state.biz);
  await load();
 }catch(e){fail(e)}
}
async function load(){
 const body=$("wf-body");body.textContent="";status("Loading…");
 try{
  state.ov=await state.api.call("read_overview",{p_business:state.biz});
  state.cat=await state.api.call("read_catalog",{p_business:state.biz,p_year:null});
  $("wf-level").textContent=state.ov.level.replace(/_/g," ");
  for(const a of document.querySelectorAll("[data-nav]")){
   const k=a.dataset.nav;
   const hide=(k==="payroll"&&!cap("payroll"))||(k==="directory"&&!cap("view_directory"))||(k==="reports"&&!cap("reports"))||(k==="self"&&!state.ov.self_employee_id);
   if(hide)a.setAttribute("hidden","");}
  await SCREENS[SCREEN](body);status("Ready · business #"+state.biz);
 }catch(e){fail(e)}
}
function siteOpts(blank){return[...(blank?[["",blank]]:[]),...(state.cat.sites||[]).map(s=>[String(s.id),s.label+" ("+s.kind+")"])]}

/* ---------- Directory ---------- */
const SCREENS={};
SCREENS.directory=async function(body){
 $("wf-title").textContent="Employee Directory";
 const q=inp("dir-q","search","",{placeholder:"Name or employee no."}),st=sel("dir-status",[["","All"],["active","Active"],["inactive","Inactive"],["terminated","Terminated"]]),
  site=sel("dir-site",siteOpts("All sites"));
 const list=h("div",{id:"dir-list"}),detail=h("div",{id:"dir-detail"});
 async function refresh(){
  const r=await call("list_employees",{p_search:q.value.trim()||null,p_status:st.value||null,p_site:site.value?Number(site.value):null,p_limit:100,p_offset:0});
  if(!r)return;list.textContent="";
  list.append(h("p",{class:"muted",id:"dir-count",text:r.total+" employee(s)"}),table([["No.",x=>x.employee_no],["Name",x=>x.full_name],
   ["Status",x=>chip(x.status,tone(x.status))],["Site",x=>x.site_label||"—"],["Dept",x=>x.department||"—"],["Role",x=>x.designation||"—"],
   ["",x=>btn("Open",()=>open(x.id),"outline","open-"+x.employee_no)]],r.items,"No employees match."));
 }
 async function open(id){
  const e=await call("get_employee",{p_employee:id});if(!e)return;detail.textContent="";
  const kids=[h("h3",{text:e.employee_no+" · "+e.full_name}),h("p",{class:"muted",text:e.status+" · "+e.contract_type+" · joined "+e.joined_on}),
   e.contact_phone?h("p",{text:"Phone: "+e.contact_phone+(e.national_id_last4?" · NID ****"+e.national_id_last4:"")}):h("p",{class:"muted",text:"Contact details are restricted to owners."}),
   h("h4",{text:"Assignments"}),table([["From",x=>x.effective_from],["Site",x=>x.site_label],["Dept",x=>x.department||"—"],["Role",x=>x.designation||"—"],["Supervisor",x=>x.is_supervisor?"yes":"no"]],e.assignments),
   h("h4",{text:"Shifts"}),table([["From",x=>x.effective_from],["Shift",x=>x.shift_name]],e.shift_assignments||[],"No shift assigned.")];
  if(e.employment_history)kids.push(h("h4",{text:"Employment history"}),table([["From",x=>x.effective_from],["Status",x=>x.status],["Contract",x=>x.contract_type],["Reason",x=>x.reason]],e.employment_history));
  if(e.salary_structures)kids.push(h("h4",{text:"Salary structure (owner only)"}),table([["From",x=>x.effective_from],["Policy",x=>x.policy+" ("+x.pay_basis+")"],["Base",x=>money(x.base_amount)]],e.salary_structures,"No salary structure."));
  if(cap("assign_shifts")){
   const sh=sel("sh-code",(state.cat.shifts||[]).filter(s=>s.active).map(s=>[s.code,s.name])),sd=inp("sh-from","date",today());
   kids.push(h("form",{class:"row",id:"shift-form",onsubmit:async(ev)=>{ev.preventDefault();
    const r=await call("assign_shift",{p_request:key("shf"),p_employee:id,p_shift_code:sh.value,p_effective_from:sd.value,p_reason:"Roster change from Workforce UI"},"Shift assigned");if(r)open(id)}},
    field("Assign shift",sh),field("From",sd),h("button",{type:"submit",class:"primary",text:"Assign shift"})));
  }
  if(cap("manage_structure")){
   const pol=sel("sal-policy",(state.cat.pay_policies||[]).filter(p=>p.active).map(p=>[p.code,p.code+" ("+p.pay_basis+")"])),base=inp("sal-base","number","",{step:"0.01",min:"0"}),sf=inp("sal-from","date",today());
   const f=h("form",{class:"row",id:"salary-form",onsubmit:async(ev)=>{ev.preventDefault();
    const r=await call("set_salary_structure",{p_request:key("sal"),p_employee:id,p_policy_code:pol.value,p_base:Number(base.value),p_effective_from:sf.value,p_reason:"Salary structure from Workforce UI"},"Salary structure saved");if(r)open(id)}},
    field("Pay policy",pol),field("Base amount",base),field("Effective from",sf),h("button",{type:"submit",class:"primary",text:"Set salary"}));
   const es=sel("emp-status",[["active","Active"],["inactive","Inactive"],["terminated","Terminated"]],e.status),ed=inp("emp-eff","date",today());
   const f2=h("form",{class:"row",id:"employment-form",onsubmit:async(ev)=>{ev.preventDefault();
    const r=await call("set_employment",{p_request:key("emp"),p_employee:id,p_effective_from:ed.value,p_status:es.value,p_contract_type:e.contract_type,p_reason:"Status change from Workforce UI"},"Employment updated");if(r){open(id);refresh()}}},
    field("Employment status",es),field("Effective",ed),h("button",{type:"submit",text:"Change status"}));
   kids.push(f,f2);
  }
  detail.append(panel("Employee",kids));detail.scrollIntoView&&detail.scrollIntoView({block:"nearest"});
 }
 const filters=h("div",{class:"row filters"},field("Search",q),field("Status",st),field("Site",site),btn("Search",refresh,"primary","dir-search"));
 body.append(panel("Find",filters),panel("Employees",list),detail);
 if(cap("edit_employees")){
  const f={no:inp("n-no"),name:inp("n-name"),join:inp("n-join","date",today()),ct:sel("n-ct",["permanent","contract","probation","daily","hourly","intern"].map(x=>[x,x])),
   site:sel("n-site",siteOpts()),dept:sel("n-dept",[["","—"],...(state.cat.departments||[]).filter(d=>d.active).map(d=>[d.code,d.name])]),des:inp("n-des"),
   ph:inp("n-ph","tel"),nid:inp("n-nid","text","",{maxlength:4,inputmode:"numeric",placeholder:"last 4 digits only"}),
   usr:inp("n-usr","text","",{placeholder:"optional login user id"}),sup:h("input",{id:"n-sup",type:"checkbox"})};
  const form=h("form",{id:"emp-form",class:"grid",onsubmit:async(ev)=>{ev.preventDefault();
   const data={employee_no:f.no.value.trim(),full_name:f.name.value.trim(),joined_on:f.join.value,contract_type:f.ct.value,site_id:Number(f.site.value)};
   if(f.dept.value)data.department_code=f.dept.value;if(f.des.value.trim())data.designation=f.des.value.trim();
   if(f.ph.value.trim())data.contact_phone=f.ph.value.trim();if(f.nid.value.trim())data.national_id_last4=f.nid.value.trim();
   if(cap("manage_structure")){if(f.usr.value.trim())data.user_id=f.usr.value.trim();if(f.sup.checked)data.is_supervisor=true}
   const r=await call("save_employee",{p_request:key("emp"),p_employee_id:null,p_expected_version:null,p_data:data,p_reason:"New hire entered via Workforce UI"},"Employee created");
   if(r){form.reset();refresh()}}},
   field("Employee no.",f.no),field("Full name",f.name),field("Joined on",f.join),field("Contract",f.ct),field("Site",f.site),field("Department",f.dept),field("Designation",f.des),
   field("Phone",f.ph,"Owner-visible only"),field("National ID (last 4)",f.nid,"Full NID is never stored"),
   cap("manage_structure")?[field("Login user id (optional link)",f.usr),field("Supervisor",f.sup)]:null,h("button",{type:"submit",class:"primary",id:"emp-save",text:"Create employee"}));
  body.append(panel("New employee",form));
 }
 await refresh();
};

/* ---------- Attendance ---------- */
SCREENS.attendance=async function(body){
 $("wf-title").textContent="Attendance";
 const from=inp("att-from","date",addDays(today(),-6)),to=inp("att-to","date",today()),site=sel("att-site",siteOpts("All sites"));
 const list=h("div",{id:"att-list"}),corr=h("div",{id:"corr-list"}),tools=h("div",{id:"att-tools"});
 async function refresh(){
  const r=await call("list_attendance",{p_from:from.value,p_to:to.value,p_employee:null,p_site:site.value?Number(site.value):null});if(!r)return;
  list.textContent="";
  list.append(table([["Date",x=>x.date],["Emp",x=>x.employee_no],["Name",x=>x.full_name],["Status",x=>chip(x.status,tone(x.status))],
   ["In",x=>x.first_in?String(x.first_in).slice(11,16):"—"],["Out",x=>x.last_out?String(x.last_out).slice(11,16):"—"],
   ["Worked",x=>x.worked_minutes+"m"],["Late",x=>x.late_minutes?x.late_minutes+"m":"—"],
   ["OT",x=>x.overtime_minutes?(x.overtime_approved_minutes+"/"+x.overtime_minutes+"m"+(x.overtime_decided?"":" ⏳")):"—"],
   ["",x=>x.locked?chip("locked","dim"):h("span",{class:"actions"},
     (cap("request_correction")&&["absent","incomplete","present","half_day"].includes(x.status))?btn("Correct",()=>corrForm(x),"outline","corr-"+x.employee_no+"-"+x.date):null,
     (x.overtime_minutes&&!x.overtime_decided&&cap("decide_overtime"))?btn("Decide OT",()=>otForm(x),"outline","ot-"+x.employee_no+"-"+x.date):null)]],r.items,"No attendance rows in this range."));
 }
 function corrForm(x){
  tools.textContent="";
  const nin=inp("c-in","time",""),nout=inp("c-out","time",""),ns=sel("c-status",[["","Keep derived status"],["present","Mark present"],["absent","Mark absent"]]),rs=inp("c-reason","text","",{minlength:5});
  const iso=(t)=>t?x.date+"T"+t+":00+06:00":null;
  tools.append(panel("Correction request · "+x.employee_no+" · "+x.date,h("form",{class:"row",id:"corr-form",onsubmit:async(ev)=>{ev.preventDefault();
   const r=await call("request_correction",{p_request:key("cor"),p_employee:x.employee_id,p_work_date:x.date,p_new_in:iso(nin.value),p_new_out:iso(nout.value),p_new_status:ns.value||null,p_reason:rs.value.trim()},"Correction submitted for approval");
   if(r){tools.textContent="";loadCorr()}}},field("New in",nin),field("New out",nout),field("Status",ns),field("Reason",rs),h("button",{type:"submit",class:"primary",text:"Submit correction"}))));
 }
 function otForm(x){
  tools.textContent="";const m=inp("ot-min","number",x.overtime_minutes,{min:0,max:x.overtime_minutes});
  tools.append(panel("Overtime decision · "+x.employee_no+" · "+x.date,h("form",{class:"row",id:"ot-form",onsubmit:async(ev)=>{ev.preventDefault();
   const r=await call("decide_overtime",{p_request:key("ot"),p_employee:x.employee_id,p_work_date:x.date,p_minutes:Number(m.value),p_note:"Overtime decision from Workforce UI"},"Overtime decision saved");if(r){tools.textContent="";refresh()}}},
   field("Approved minutes (0 = reject)",m),h("button",{type:"submit",class:"primary",text:"Save decision"}))));
 }
 async function loadCorr(){
  const r=await call("list_corrections",{p_status:"pending"});if(!r)return;corr.textContent="";
  corr.append(table([["Date",x=>x.work_date],["Emp",x=>x.employee_no],["Change",x=>[x.new_in?"in "+String(x.new_in).slice(11,16):"",x.new_out?" out "+String(x.new_out).slice(11,16):"",x.new_status||""].join("")],["Reason",x=>x.reason],
   ["",x=>cap("decide_correction")&&!x.mine?h("span",{class:"actions"},btn("Approve",()=>decide(x.id,"approve"),"primary","corr-approve-"+x.id),btn("Reject",()=>decide(x.id,"reject"),"outline","corr-reject-"+x.id)):chip(x.mine?"awaiting other approver":"read-only","dim")]],r.items,"No pending corrections."));
 }
 async function decide(id,d){const r=await call("decide_correction",{p_request:key("cdc"),p_correction:id,p_decision:d,p_note:"Decision from Workforce UI"},"Correction "+d+"d");if(r){loadCorr();refresh()}}
 body.append(panel("Range",h("div",{class:"row filters"},field("From",from),field("To",to),field("Site",site),btn("Show",refresh,"primary","att-show"))),panel("Daily attendance (Asia/Dhaka)",list),tools,panel("Pending corrections",corr));
 if(cap("import_punches")){
  const ps=sel("imp-site",siteOpts()),ta=h("textarea",{id:"imp-text",rows:4,placeholder:"employee_no,2026-10-01T09:00:00+06:00,in  (one row per line, max 500)"});
  body.append(panel("Import punches",h("form",{id:"imp-form",onsubmit:async(ev)=>{ev.preventDefault();
   const rows=ta.value.split(/\n/).map(x=>x.trim()).filter(Boolean).map(x=>{const p=x.split(",").map(s=>s.trim());return{employee_no:p[0],at:p[1],direction:p[2],ref:p[3]||undefined}});
   const r=await call("import_punches",{p_request:key("imp"),p_site:Number(ps.value),p_source:"manual",p_punches:rows},null);
   if(r){status("Import: "+r.accepted+" accepted, "+r.duplicates+" duplicate, "+r.rejected+" rejected","ok");ta.value="";refresh()}}},
   field("Device site",ps),field("Punch rows (employee_no, ISO time with offset, in|out)",ta),h("button",{type:"submit",class:"primary",id:"imp-run",text:"Import"}))));
 }
 await loadCorr();await refresh();
};

/* ---------- Shifts & Leave ---------- */
SCREENS.leave=async function(body){
 $("wf-title").textContent="Shifts & Leave";
 const c=state.cat;
 body.append(panel("Shifts",table([["Code",x=>x.code],["Name",x=>x.name],["Time",x=>x.start_time.slice(0,5)+"–"+x.end_time.slice(0,5)+(x.crosses_midnight?" (+1d)":"")],["Break",x=>x.break_minutes+"m"],["Grace",x=>x.grace_late_minutes+"m"],["",x=>x.active?chip("active","good"):chip("off","dim")]],c.shifts,"No shifts yet.")));
 body.append(panel("Holidays "+c.year,table([["Date",x=>x.date],["Name",x=>x.name],["Kind",x=>x.kind],["Paid",x=>x.paid?"yes":"no"],["",x=>x.active?chip("active","good"):chip("off","dim")]],c.holidays,"No holidays configured.")));
 if(cap("manage_structure")){
  const code=inp("sh-newcode"),nm=inp("sh-newname"),s1=inp("sh-start","time","09:00"),s2=inp("sh-end","time","18:00"),br=inp("sh-break","number","60",{min:0,max:480});
  body.append(panel("Add / change shift",h("form",{class:"row",id:"shift-save-form",onsubmit:async(ev)=>{ev.preventDefault();
   const ex=(c.shifts||[]).find(x=>x.code===code.value.trim());
   const r=await call("save_shift",{p_request:key("shs"),p_expected_version:ex?ex.version:0,p_shift:{code:code.value.trim(),name:nm.value.trim(),start_time:s1.value,end_time:s2.value,break_minutes:Number(br.value)},p_reason:"Shift definition from Workforce UI"},"Shift saved");if(r)load()}},
   field("Code",code),field("Name",nm),field("Start",s1),field("End",s2,"End earlier than start = overnight"),field("Break (min)",br),h("button",{type:"submit",class:"primary",text:"Save shift"}))));
  const hd=inp("hol-date","date",today()),hn=inp("hol-name");
  body.append(panel("Add holiday",h("form",{class:"row",id:"holiday-form",onsubmit:async(ev)=>{ev.preventDefault();
   const r=await call("save_holiday",{p_request:key("hol"),p_date:hd.value,p_name:hn.value.trim(),p_kind:"company",p_paid:true,p_site:null,p_active:true,p_reason:"Holiday from Workforce UI"},"Holiday saved");if(r)load()}},
   field("Date",hd),field("Name",hn),h("button",{type:"submit",class:"primary",text:"Save holiday"}))));
  const lc=inp("lt-code"),ln=inp("lt-name"),lq=inp("lt-quota","number","",{step:"0.5",min:"0"}),lp=sel("lt-paid",[["true","Paid"],["false","Unpaid"]]);
  body.append(panel("Leave types",[table([["Code",x=>x.code],["Name",x=>x.name],["Paid",x=>x.paid?"paid":"unpaid"],["Quota",x=>x.annual_quota_days==null?"—":x.annual_quota_days],["Approval",x=>x.requires_approval?"required":"auto"]],c.leave_types,"No leave types."),
   h("form",{class:"row",id:"leave-type-form",onsubmit:async(ev)=>{ev.preventDefault();
    const ex=(c.leave_types||[]).find(x=>x.code===lc.value.trim());
    const r=await call("save_leave_type",{p_request:key("ltp"),p_expected_version:ex?ex.version:0,p_type:{code:lc.value.trim(),name:ln.value.trim(),paid:lp.value==="true",annual_quota_days:lq.value===""?null:Number(lq.value)},p_reason:"Leave policy from Workforce UI"},"Leave type saved");if(r)load()}},
    field("Code",lc),field("Name",ln),field("Paid",lp),field("Annual quota (days)",lq),h("button",{type:"submit",class:"primary",text:"Save leave type"}))]));
 }else body.append(panel("Leave types",table([["Code",x=>x.code],["Name",x=>x.name],["Paid",x=>x.paid?"paid":"unpaid"],["Quota",x=>x.annual_quota_days==null?"—":x.annual_quota_days]],c.leave_types,"No leave types.")));
 // requests
 const list=h("div",{id:"leave-list"}),fs=sel("lv-filter",[["","All"],["pending","Pending"],["approved","Approved"],["rejected","Rejected"],["revoked","Revoked"],["cancelled","Cancelled"]]);
 async function refresh(){
  const r=await call("list_leave",{p_status:fs.value||null,p_employee:null});if(!r)return;list.textContent="";
  list.append(table([["Emp",x=>x.employee_no+" "+x.full_name],["Type",x=>x.leave_name],["From",x=>x.from_date],["To",x=>x.to_date],["Days",x=>x.days],["Status",x=>chip(x.status,tone(x.status))],
   ["",x=>h("span",{class:"actions"},
    (x.status==="pending"&&cap("review_leave")&&!x.mine)?[btn("Approve",()=>act("decide_leave",x.id,"approve"),"primary","lv-approve-"+x.id),btn("Reject",()=>act("decide_leave",x.id,"reject"),"outline","lv-reject-"+x.id)]:null,
    (x.status==="approved"&&cap("review_leave")&&!x.mine)?btn("Revoke",()=>act("decide_leave",x.id,"revoke"),"outline","lv-revoke-"+x.id):null,
    (x.status==="pending"&&x.mine)?btn("Cancel",()=>act("cancel_leave",x.id),"outline","lv-cancel-"+x.id):null)]],r.items,"No leave requests."));
 }
 async function act(name,id,d){
  const p=name==="cancel_leave"?{p_request:key("lvc"),p_leave:id,p_note:"Cancelled from Workforce UI"}:{p_request:key("lvd"),p_leave:id,p_decision:d,p_note:"Decision from Workforce UI"};
  const r=await call(name,p,"Leave updated");if(r)refresh()}
 fs.addEventListener("change",refresh);
 body.append(panel("Leave requests",[h("div",{class:"row filters"},field("Filter",fs)),list]));
 const lt=sel("lr-type",(c.leave_types||[]).filter(x=>x.active).map(x=>[x.code,x.name])),lf=inp("lr-from","date",today()),l2=inp("lr-to","date",today()),lr=inp("lr-reason","text","",{minlength:3});
 const emp=state.ov.self_employee_id;
 body.append(panel("Request leave"+(emp?"":" (select via owner/manager on behalf is API-only)"),h("form",{class:"row",id:"leave-form",onsubmit:async(ev)=>{ev.preventDefault();
  const r=await call("request_leave",{p_request:key("lvr"),p_employee:null,p_type_code:lt.value,p_from:lf.value,p_to:l2.value,p_reason:lr.value.trim()},null);
  if(r){status("Leave "+r.status+" · "+r.days+" working day(s)","ok");refresh()}}},
  field("Type",lt),field("From",lf),field("To",l2),field("Reason",lr),h("button",{type:"submit",class:"primary",id:"lv-submit",text:"Request leave",disabled:!emp&&!cap("review_leave")}))));
 await refresh();
};

/* ---------- Payroll ---------- */
SCREENS.payroll=async function(body){
 $("wf-title").textContent="Payroll";
 if(!cap("payroll")){body.append(panel("Restricted",h("p",{text:"Payroll is restricted to authorised owners. Staff see only their own payslip under My Work."})));return}
 body.append(h("div",{class:"safety",role:"note"},h("strong",{text:"Approved/Frozen does NOT mean Paid. "}),"No bank file, payout or ledger posting happens here. Statutory/ambiguous rules stay OFF until the Owner approves them."));
 const period=inp("pay-period","month",monthStart(addDays(today(),-20)).slice(0,7)),pv=h("div",{id:"pay-preview"}),runs=h("div",{id:"pay-runs"}),detail=h("div",{id:"pay-detail"});
 const per=()=>period.value+"-01";
 async function preview(){
  const r=await call("payroll_preview",{p_period:per()});if(!r)return;pv.textContent="";
  pv.append(h("div",{class:"metrics"},h("div",null,h("small",{text:"Employees"}),h("b",{text:r.employee_count})),h("div",null,h("small",{text:"Gross"}),h("b",{text:money(r.total_gross)})),
   h("div",null,h("small",{text:"Deductions"}),h("b",{text:money(r.total_deductions)})),h("div",null,h("small",{text:"Net"}),h("b",{text:money(r.total_net)})),
   h("div",null,h("small",{text:"Blocking"}),h("b",{class:r.blocking_count?"bad":"good",text:r.blocking_count}))),
   table([["Emp",x=>x.employee_no+" "+x.employee_name],["Gross",x=>money(x.gross)],["Deductions",x=>money(x.total_deductions)],["Net",x=>money(x.net)],
    ["Issues",x=>x.warnings.length?x.warnings.map(w=>chip(w.code,w.blocking?"bad":"warn")):"—"]],r.lines,"No payable employees in this period."),
   h("p",{class:"muted",text:"PREVIEW ONLY — nothing is stored until you create a DRAFT."}),
   btn("Create DRAFT run",async()=>{const d=await call("create_payroll_draft",{p_request:key("pdr"),p_period:per(),p_amends_run:null,p_reason:null},"Draft created");if(d){loadRuns();open(d.run_id)}},"primary","pay-draft"));
 }
 async function loadRuns(){
  const r=await call("list_payroll_runs",{});if(!r)return;runs.textContent="";
  runs.append(table([["Period",x=>x.period_start.slice(0,7)+" v"+x.version],["Status",x=>chip(x.status,tone(x.status))],["Employees",x=>x.employee_count],["Net",x=>money(x.total_net)],["Blocking",x=>x.blocking_count],
   ["",x=>btn("Open",()=>open(x.id),"outline","run-"+x.id)]],r.items,"No payroll runs yet."));
 }
 async function open(id){
  const r=await call("get_payroll_run",{p_run:id});if(!r)return;detail.textContent="";
  const run=r.run,acts=[];
  const t=(a,label,cls,needNote)=>btn(label,async()=>{
    let note=null;if(needNote){note=window.prompt("Reason (min 5 chars)")||"";if(note.trim().length<5){status("Reason is required","error");return}}
    const x=await call("payroll_transition",{p_request:key("ptr"),p_run:id,p_action:a,p_note:note},"Run "+a+" done");if(x){loadRuns();open(id)}},cls||"primary","act-"+a);
  if(run.status==="draft"){acts.push(btn("Recalculate",async()=>{const x=await call("recalculate_payroll_draft",{p_request:key("prc"),p_run:id},"Draft recalculated");if(x){open(id);loadRuns()}},"outline","act-recalc"),t("review","Mark REVIEWED"),t("void","Void","outline",true))}
  if(run.status==="reviewed")acts.push(t("approve","APPROVE"),t("return_to_draft","Return to draft","outline",true),t("void","Void","outline",true));
  if(run.status==="approved")acts.push(t("freeze","FREEZE & issue payslips"),t("return_to_draft","Return to draft","outline",true),t("void","Void","outline",true));
  if(run.status==="frozen")acts.push(btn("Start amendment",async()=>{const why=window.prompt("Amendment reason (min 10 chars)")||"";
    if(why.trim().length<10){status("Amendment reason is required","error");return}
    const x=await call("create_payroll_draft",{p_request:key("pam"),p_period:run.period_start,p_amends_run:id,p_reason:why.trim()},"Amendment draft created");if(x){loadRuns();open(x.run_id)}},"outline","act-amend"));
  detail.append(panel("Run "+run.period_start.slice(0,7)+" v"+run.version+" · "+run.status.toUpperCase(),[
   h("div",{class:"metrics"},h("div",null,h("small",{text:"Gross"}),h("b",{text:money(run.total_gross)})),h("div",null,h("small",{text:"Deductions"}),h("b",{text:money(run.total_deductions)})),
    h("div",null,h("small",{text:"Net"}),h("b",{text:money(run.total_net)})),h("div",null,h("small",{text:"Paid"}),h("b",{text:"NOT TRACKED"}))),
   run.prepared_by_me?h("p",{class:"muted",text:"You prepared this run — a different owner must review/approve (maker-checker)."}):null,
   h("div",{class:"actions"},acts),
   table([["Emp",x=>x.employee_no+" "+x.employee_name],["Days",x=>x.present_days+"P "+x.absent_days+"A "+x.paid_leave_days+"L"],["Basic",x=>money(x.basic_earned)],["OT",x=>money(x.overtime_pay)],["Allow.",x=>money(x.allowances_total)],
    ["Gross",x=>money(x.gross)],["Deduct.",x=>money(x.total_deductions)],["Net",x=>money(x.net)],["Issues",x=>x.warnings.length?x.warnings.map(w=>chip(w.code,w.blocking?"bad":"warn")):"—"]],r.lines)]));
 }
 body.append(panel("Preview a month",[h("div",{class:"row filters"},field("Month",period),btn("Preview",preview,"primary","pay-preview-btn")),pv]),panel("Payroll runs",runs),detail);
 // advances + policy summary
 const adv=h("div",{id:"adv-list"});
 body.append(panel("Salary advances (deduction schedule only — no payout)",adv));
 const a=await call("list_advances",{});if(a)adv.append(table([["Emp",x=>x.employee_no],["Amount",x=>money(x.amount)],["Installment",x=>money(x.installment_amount)],["Remaining",x=>money(x.remaining)],["Status",x=>chip(x.status,tone(x.status))],
  ["",x=>x.status==="requested"?h("span",{class:"actions"},btn("Approve",async()=>{const r=await call("decide_advance",{p_request:key("adv"),p_advance:x.id,p_decision:"approve",p_note:"Approved from Workforce UI"},"Advance approved");if(r)load()},"primary","adv-approve-"+x.id)):null]],a.items,"No advances."));
 body.append(panel("Pay policies & components",[table([["Policy",x=>x.code],["Basis",x=>x.pay_basis],["OT ×",x=>x.ot_multiplier_weekday+" / "+x.ot_multiplier_offday],["Rounding",x=>x.rounding_mode]],state.cat.pay_policies||[],"No pay policies."),
  table([["Component",x=>x.code],["Kind",x=>x.kind],["Calc",x=>x.calc_type+" "+x.amount],["State",x=>chip(x.approval_status,x.approval_status==="active"?"good":"warn")],["Statutory",x=>x.statutory?"yes (needs owner approval)":"no"]],state.cat.components||[],"No components.")]));
 await loadRuns();
};

/* ---------- Reports ---------- */
SCREENS.reports=async function(body){
 $("wf-title").textContent="Reports & Exports";
 const from=inp("rep-from","date",addDays(today(),-29)),to=inp("rep-to","date",today()),out=h("div",{id:"rep-out"}),exp=h("div",{id:"exp-out",class:"muted",text:"Exports are PII-safe: no phone, no national ID."});
 async function attendance(){const r=await call("report_attendance",{p_from:from.value,p_to:to.value});if(!r)return;out.textContent="";
  out.append(h("h3",{text:"Attendance summary by site"}),table([["Site",x=>x.site_label||"—"],["Present",x=>x.present],["Half",x=>x.half_day],["Absent",x=>x.absent],["Paid leave",x=>x.paid_leave],["Unpaid leave",x=>x.unpaid_leave],["Late days",x=>x.late_days],["Incomplete",x=>x.incomplete],["OT approved",x=>x.overtime_approved_minutes+"m"]],r.sites,"No data."))}
 async function headcount(){const r=await call("report_headcount",{});if(!r)return;out.textContent="";
  out.append(h("h3",{text:"Headcount as of "+r.as_of}),table([["Site",x=>x.site_label||"—"],["Status",x=>x.status],["Contract",x=>x.contract_type],["Headcount",x=>x.headcount]],r.rows,"No data."))}
 async function payrollRep(){const r=await call("report_payroll",{p_period:monthStart(to.value)});if(!r)return;out.textContent="";
  out.append(h("h3",{text:"Payroll "+monthStart(to.value).slice(0,7)+(r.run?" · "+r.run.status:"")}),table([["Site",x=>x.site_label||"—"],["Headcount",x=>x.headcount],["Gross",x=>money(x.gross)],["Deductions",x=>money(x.deductions)],["Net",x=>money(x.net)]],r.sites,"No run for this month."))}
 async function register(){const r=await call("payslip_register",{p_period:monthStart(to.value)});if(!r)return;out.textContent="";
  out.append(h("h3",{text:"Frozen payslip register"}),table([["Emp",x=>x.employee_no+" "+x.employee_name],["Version",x=>x.run_version],["Run",x=>chip(x.run_status,tone(x.run_status))],["Gross",x=>money(x.gross)],["Net",x=>money(x.net)]],r.items,"No payslips."))}
 async function integrity(){const r=await call("integrity_report",{});if(!r)return;out.textContent="";
  out.append(h("h3",{text:"Integrity: "+(r.ok?"ALL CHECKS PASS":"PROBLEMS FOUND")}),table([["Check",x=>x.name],["Result",x=>chip(x.ok?"pass":"FAIL",x.ok?"good":"bad")]],r.checks))}
 async function audit(){const r=await call("audit_list",{p_limit:50});if(!r)return;out.textContent="";
  out.append(h("h3",{text:"Latest audit events"}),table([["#",x=>x.id],["Entity",x=>x.entity+" "+x.entity_id],["Event",x=>x.event],["Reason",x=>x.reason||"—"],["Hash",x=>x.hash]],r.items))}
 async function csv(kind,params){const r=await call("export_csv",{p_request:key("exp"),p_kind:kind,p_params:params},null);if(!r)return;
  const blob=new Blob([r.csv],{type:"text/csv;charset=utf-8"}),url=URL.createObjectURL(blob);
  const a=h("a",{href:url,download:r.filename,id:"csv-link",text:"Download "+r.filename+" ("+r.rows+" rows)"});exp.textContent="";exp.append(a);status("Export ready · "+r.rows+" rows","ok")}
 const buttons=[btn("Attendance summary",attendance,"primary","rep-att"),btn("Headcount",headcount,"outline","rep-head")];
 if(cap("payroll"))buttons.push(btn("Payroll by site",payrollRep,"outline","rep-pay"),btn("Payslip register",register,"outline","rep-reg"),btn("Integrity check",integrity,"outline","rep-int"),btn("Audit trail",audit,"outline","rep-aud"));
 body.append(panel("Range",h("div",{class:"row filters"},field("From",from),field("To",to))),panel("Reports",[h("div",{class:"actions"},buttons),out]));
 const ex=[];
 if(cap("export_attendance"))ex.push(btn("Export employees CSV",()=>csv("employees",{}),"outline","exp-emp"),btn("Export attendance CSV",()=>csv("attendance",{from:from.value,to:to.value}),"outline","exp-att"));
 if(cap("export_payroll"))ex.push(btn("Export payslip register CSV",()=>csv("payslip_register",{period:monthStart(to.value)}),"outline","exp-reg"));
 body.append(panel("Exports (audited)",[h("div",{class:"actions"},ex),exp]));
 await attendance();
};

/* ---------- My Work (self service) ---------- */
SCREENS.self=async function(body){
 $("wf-title").textContent="My Work";
 if(!state.ov.self_employee_id){body.append(panel("No employee record",h("p",{text:"Your login is not linked to an active employee record in this business."})));return}
 const slips=h("div",{id:"my-slips"}),slip=h("div",{id:"my-slip"}),att=h("div",{id:"my-att"}),bal=h("div",{id:"my-bal"});
 const p=await call("my_payslips",{});
 if(p)slips.append(table([["Period",x=>x.period_start.slice(0,7)],["Net",x=>money(x.net)],["State",x=>x.superseded?chip("superseded","warn"):chip("current","good")],["",x=>btn("Open",async()=>{
   const r=await call("get_my_payslip",{p_payslip:x.id});if(!r)return;slip.textContent="";const s=r.payslip;
   slip.append(panel("Payslip "+s.period_start.slice(0,7)+(r.superseded?" · SUPERSEDED":""),[
    table([["Item",x=>x[0]],["Amount",x=>x[1]]],[["Basic",money(s.basic_earned)],["Overtime",money(s.overtime_pay)],...(s.allowances||[]).map(a=>[a.name,money(a.amount)]),["Gross",money(s.gross)],
     ["Absence deduction",money(s.absence_deduction)],...(s.other_deductions||[]).map(a=>[a.name,money(a.amount)]),["Advance recovery",money(s.advance_recovery)],["Net",money(s.net)]]),
    h("p",{class:"muted",text:"This payslip is a calculation record. It does not confirm that payment was made."})]))},"outline","slip-"+x.id)]],p.items,"No payslips yet."));
 const a=await call("list_attendance",{p_from:addDays(today(),-13),p_to:today(),p_employee:null,p_site:null});
 if(a)att.append(table([["Date",x=>x.date],["Status",x=>chip(x.status,tone(x.status))],["Worked",x=>x.worked_minutes+"m"],["Late",x=>x.late_minutes?x.late_minutes+"m":"—"]],a.items));
 const b=await call("leave_balance",{p_employee:null,p_year:null});
 if(b)bal.append(table([["Type",x=>x.name],["Quota",x=>x.quota==null?"—":x.quota],["Approved",x=>x.approved],["Pending",x=>x.pending]],b.items));
 body.append(panel("My payslips",slips),slip,panel("My attendance (14 days)",att),panel("My leave balance",bal),
  panel("Request leave or advance",h("p",{class:"muted"},"Use ",h("a",{href:"./core10-workforce-leave.html",text:"Shifts & Leave"})," to request leave.")));
 const am=inp("adv-amt","number","",{min:"1",step:"0.01"}),ai=inp("adv-inst","number","",{min:"1",step:"0.01"}),as=inp("adv-start","month",addDays(today(),20).slice(0,7));
 body.append(panel("Request a salary advance",h("form",{class:"row",id:"adv-form",onsubmit:async(ev)=>{ev.preventDefault();
  const r=await call("request_advance",{p_request:key("adr"),p_employee:null,p_amount:Number(am.value),p_installment:Number(ai.value),p_start_period:as.value+"-01",p_reason:"Advance request from My Work"},"Advance requested — pending owner decision");if(r){am.value="";ai.value=""}}},
  field("Amount",am),field("Installment per month",ai),field("First deduction month",as),h("button",{type:"submit",class:"primary",id:"adv-submit",text:"Request advance"}))));
};
document.addEventListener("DOMContentLoaded",boot);
})();
