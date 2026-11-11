/* C10-A053/A054 Workforce Governance UI: Portfolio integration + staff identity (integration), delegations, effective-dated policies +
 * leave balances (policy), payroll lifecycle + liability + external payment RECORDS + retention (liability).
 * All data/authority comes from the signed RPC adapter. DOM nodes are built with textContent only. English / Bangla.
 * Approved is NOT paid: payroll approval buttons and payment RECORD forms are labelled separately; this UI never moves money.
 */
(function(){"use strict";
const SCREEN=document.body.dataset.screen||"integration";
const state={api:null,biz:null,businesses:[],busy:false,lang:"en",access:null};
{const l=new URLSearchParams(location.search).get("lang");if(l==="bn"||l==="en")state.lang=l}
const L=(en,bn)=>state.lang==="bn"&&bn?bn:en;
const NAV=[["integration","core10-workforce-integration.html",["Portfolio & Staff","পোর্টফোলিও ও কর্মী"]],["delegation","core10-workforce-delegation.html",["Delegation","দায়িত্ব অর্পণ"]],
 ["policy","core10-workforce-policy.html",["Policies & Leave","নীতি ও ছুটি"]],["liability","core10-workforce-liability.html",["Payroll & Liability","বেতন ও দায়"]]];
const ERR={wf_denied:["No Workforce access for this business.","এই ব্যবসায় আপনার কর্মী-মডিউল অধিকার নেই।"],a054_owner_required:["Only an owner can do this.","শুধু মালিক এটি করতে পারেন।"],
 a053_owner_required:["Only an owner can do this.","শুধু মালিক এটি করতে পারেন।"],a054_delegation_denied:["Your delegation does not cover this action, period or site (or was revoked).","আপনার অর্পিত দায়িত্ব এই কাজ/সময়/সাইট কভার করে না (বা বাতিল হয়েছে)।"],
 a054_liability_denied:["Salary liability is restricted to owners and delegated payroll roles.","বেতন-দায় শুধু মালিক ও অর্পিত পে-রোল ভূমিকার জন্য।"],wf_payroll_access_denied:["Payroll is restricted to owners and delegated payroll roles.","পে-রোল শুধু মালিক ও অর্পিত ভূমিকার জন্য।"],
 wf_maker_checker_violation:["Maker-checker: the same person cannot prepare, review and approve.","মেকার-চেকার: একই ব্যক্তি প্রস্তুত, পর্যালোচনা ও অনুমোদন করতে পারেন না।"],a054_self_in_run_denied:["You are an employee in this payroll run and cannot decide it.","আপনি এই পে-রোলের কর্মী; সিদ্ধান্ত নিতে পারবেন না।"],
 a054_payment_exceeds_outstanding:["Amount exceeds the outstanding approved amount.","পরিমাণ অনুমোদিত বকেয়া ছাড়িয়ে গেছে।"],a054_no_approved_payable:["No approved payroll exists for that employee and month.","এই কর্মী/মাসের জন্য অনুমোদিত পে-রোল নেই।"],
 a054_effective_date_locked:["That date is inside a locked period or already used by leave; choose a later date.","এই তারিখ লক করা সময়ে পড়ে; পরবর্তী তারিখ দিন।"],a054_multiplier_below_base_rate:["Multiplier must be at least 1.00x (1.00x = 100% of base rate, not 1%).","গুণক কমপক্ষে ১.০০x (১.০০x = মূল হারের ১০০%, ১% নয়)।"],
 a054_multiplier_above_limit_use_x_not_percent:["Multiplier is above 5.00x. Enter a multiplier such as 1.50, not a percentage like 150.","গুণক ৫.০০x এর বেশি। ১.৫০ এর মতো লিখুন, ১৫০ নয়।"],a054_legal_gate_tenant_owner_required:["This setting needs the tenant owner and a legal review reference.","এটির জন্য টেন্যান্ট মালিক ও আইনি পর্যালোচনা রেফারেন্স লাগবে।"],
 a054_legal_gate_reference_required:["Enter the legal review reference (at least 8 characters).","আইনি রেফারেন্স (কমপক্ষে ৮ অক্ষর) দিন।"],a054_invalid_policy:["Some policy values are invalid.","নীতির কিছু মান সঠিক নয়।"],a054_effective_date_boundary:["Payroll policies start on the 1st of a month; leave policies on 1 January.","বেতন নীতি মাসের ১ তারিখে, ছুটির নীতি ১ জানুয়ারিতে শুরু হয়।"],
 a054_rule_code_collision:["That code already exists as a payroll component.","এই কোড ইতিমধ্যে ব্যবহৃত।"],wf_leave_quota_exceeded:["Leave balance exceeded.","ছুটির ব্যালেন্স শেষ।"],wf_stale_version:["Changed elsewhere. Reload and retry.","অন্যত্র পরিবর্তিত। রিলোড করুন।"],
 a053_alias_unmapped:["Unknown identity alias (fail-closed).","অজানা পরিচয় (বন্ধ)।"],a053_alias_cross_tenant:["That identity belongs to another tenant.","এই পরিচয় অন্য টেন্যান্টের।"],a053_alias_scope_mismatch:["That identity is scoped to a different business.","এই পরিচয় অন্য ব্যবসার জন্য।"],
 a053_alias_not_linkable:["That identity cannot be linked as staff.","এই পরিচয় কর্মী হিসেবে যুক্ত করা যায় না।"],a053_employee_already_linked:["Employee already has a linked login.","কর্মীর লগইন আগেই যুক্ত।"],a054_delegate_not_eligible:["Delegate must be an active manager/owner or linked employee of this business.","প্রতিনিধি এই ব্যবসার সক্রিয় ম্যানেজার বা যুক্ত কর্মী হতে হবে।"]};
const $=(id)=>document.getElementById(id);
function h(tag,props,...kids){const e=document.createElement(tag);
 for(const [k,v] of Object.entries(props||{})){if(v==null||v===false)continue;
  if(k==="class")e.className=v;else if(k==="text")e.textContent=v;else if(k.startsWith("on"))e.addEventListener(k.slice(2),v);
  else if(v===true)e.setAttribute(k,"");else e.setAttribute(k,String(v));}
 for(const c of kids.flat(2)){if(c==null||c===false)continue;e.append(c&&c.nodeType?c:document.createTextNode(String(c)))}
 return e}
const money=(v)=>v==null?"—":Number(v).toLocaleString("en-US",{minimumFractionDigits:2,maximumFractionDigits:2});
const today=()=>new Date(Date.now()+6*3600e3).toISOString().slice(0,10);
const monthOf=(d)=>d.slice(0,7);
function status(msg,tone){const n=$("wf-status");if(n){n.textContent=msg;n.dataset.tone=tone||"ok"}}
function fail(e){const m=ERR[e&&e.code]||ERR[e&&e.message];status(m?L(m[0],m[1]):((e&&e.message)||L("Request failed","অনুরোধ ব্যর্থ")),"error")}
async function call(name,params,okMsg){
 const spec=window.CORE10_WORKFORCE_POLICY_API.SPEC[name],write=!!(spec&&spec.w);
 if(write){if(state.busy)return null;state.busy=true;document.body.dataset.busy="1"}
 try{const r=await state.api.call(name,Object.assign(spec&&"p_business" in spec.a?{p_business:state.biz}:{},params||{}));if(okMsg)status(okMsg,"ok");return r}
 catch(e){fail(e);return null}finally{if(write){state.busy=false;delete document.body.dataset.busy}}}
const key=(p)=>state.api.requestKey(p);
function field(label,input,hint){return h("label",{class:"fld"},h("span",{text:label}),input,hint?h("small",{text:hint}):null)}
function sel(id,options,value){const s=h("select",{id});for(const [v,t] of options)s.append(h("option",{value:v,text:t}));if(value!=null)s.value=value;return s}
function inp(id,type,value,extra){return h("input",Object.assign({id,type:type||"text",value:value==null?"":value,autocomplete:"off"},extra||{}))}
function btn(text,fn,cls,id){return h("button",{type:"button",class:cls||"",id,onclick:fn,text})}
function table(cols,rows,empty){
 if(!rows.length)return h("p",{class:"muted",text:empty||L("Nothing to show.","দেখানোর কিছু নেই।")});
 return h("div",{class:"tbl-wrap"},h("table",null,h("thead",null,h("tr",null,cols.map(c=>h("th",{text:c[0]})))),
  h("tbody",null,rows.map(r=>h("tr",null,cols.map(c=>h("td",{"data-label":c[0]},c[1](r))))))))}
function panel(title,body,right){return h("section",{class:"panel"},h("div",{class:"panel-title"},h("h2",{text:title}),right||null),h("div",{class:"panel-body"},body))}
function kv(label,value){return h("div",{class:"kv"},h("span",{text:label}),h("b",{text:value==null?"—":String(value)}))}
const STATE_LABEL={approved_unpaid:["Approved - payment NOT recorded","অনুমোদিত - পেমেন্ট নথিভুক্ত নয়","approved"],partially_paid_recorded:["Partly paid (recorded outside system)","আংশিক পরিশোধ (সিস্টেমের বাইরে, নথিভুক্ত)","part"],
 paid_recorded:["Paid outside system (recorded)","সিস্টেমের বাইরে পরিশোধ (নথিভুক্ত)","paidrec"],overpaid_recorded:["Over-recorded - check","বেশি নথিভুক্ত - যাচাই করুন","bad"],nothing_payable:["Nothing payable","দেয় কিছু নেই","dim"],
 no_approved_run:["No approved payroll","অনুমোদিত পে-রোল নেই","dim"],approved_not_paid:["Approved, not paid","অনুমোদিত, অপরিশোধিত","approved"]};
function stateChip(s){const m=STATE_LABEL[s];return h("span",{class:"st "+(m?m[2]:"dim"),text:m?L(m[0],m[1]):String(s).replace(/_/g," ")})}
const APPROVAL_NOTE=()=>h("div",{class:"banner",role:"note"},h("b",{text:L("Approval is not payment. ","অনুমোদন মানে পেমেন্ট নয়। ")}),
 L("Approving payroll only fixes the amount owed. This system never pays salary, sends bank files or posts to the ledger. Payments made elsewhere can only be RECORDED here.",
  "পে-রোল অনুমোদন শুধু প্রাপ্য নির্ধারণ করে। এই সিস্টেম বেতন পরিশোধ, ব্যাংক ফাইল বা লেজার এন্ট্রি করে না। বাইরে করা পরিশোধ শুধু এখানে নথিভুক্ত করা যায়।"));

async function shell(){
 const root=$("wf-root");root.textContent="";
 const nav=h("nav",{class:"rail-nav","aria-label":"Workforce governance navigation"},NAV.map(n=>h("a",{href:"./"+n[1]+(state.lang==="bn"?"?lang=bn":""),class:n[0]===SCREEN?"active":null,"data-nav":n[0]},h("b",{text:n[2][0]}),h("small",{text:n[2][1]}))));
 const lang=h("div",{class:"lang",role:"group","aria-label":"Language"},
  h("button",{type:"button",id:"lang-en","aria-pressed":String(state.lang==="en"),onclick:()=>setLang("en"),text:"English"}),
  h("button",{type:"button",id:"lang-bn","aria-pressed":String(state.lang==="bn"),onclick:()=>setLang("bn"),text:"বাংলা"}));
 root.append(h("div",{class:"wf-layout"},
  h("aside",{class:"rail"},h("div",{class:"brand"},"CORE ",h("b",{text:"10"}),h("small",{text:"WORKFORCE GOVERNANCE · A053/A054"})),nav,
   h("div",{class:"rail-note",text:L("Server decides authority. Approved ≠ Paid.","অনুমতি সার্ভার ঠিক করে। অনুমোদিত ≠ পরিশোধিত।")})),
  h("main",null,h("div",{class:"topline"},h("span",{text:"WORKFORCE / POLICY / LIABILITY"}),h("span",{id:"wf-level",class:"badge",text:"…"})),
   h("div",{class:"headline"},h("h1",{id:"wf-title"}),lang,h("label",{class:"biz"},h("span",{text:L("Business","ব্যবসা")}),h("select",{id:"wf-biz","aria-label":"Business"}))),
   h("div",{id:"wf-status",role:"status","aria-live":"polite",text:L("Verifying signed session…","সেশন যাচাই হচ্ছে…")}),h("div",{id:"wf-body"}))));
 $("wf-biz").addEventListener("change",async(e)=>{state.biz=Number(e.target.value);await load()});
}
async function setLang(l){state.lang=l;try{const u=new URL(location.href);u.searchParams.set("lang",l);history.replaceState(null,"",u)}catch(e){}document.documentElement.lang=l==="bn"?"bn":"en";
 const keep=state.biz;await shell();fillBiz(keep);await load()}
function fillBiz(want){const sb=$("wf-biz");sb.textContent="";
 for(const b of state.businesses)sb.append(h("option",{value:b.id,text:"#"+b.id+" · "+b.slug}));
 if(state.businesses.length){state.biz=state.businesses.some(b=>b.id===want)?want:state.businesses[0].id;sb.value=String(state.biz)}}
async function boot(){
 document.documentElement.lang=state.lang==="bn"?"bn":"en";
 await shell();
 try{
  const cfg=window.BOS_CONFIG,lib=window.supabase;
  if(!cfg||!cfg.url||!cfg.key||!lib||typeof lib.createClient!=="function")throw Object.assign(new Error("SIGNED_SUPABASE_CLIENT_REQUIRED"),{code:"SIGNED_SUPABASE_CLIENT_REQUIRED"});
  state.api=window.CORE10_WORKFORCE_POLICY_API.create({client:lib.createClient(cfg.url,cfg.key)});
  state.businesses=(await state.api.call("my_businesses",{})).items;
  if(!state.businesses.length){status(L("No Workforce access for this account.","এই অ্যাকাউন্টের কর্মী-মডিউল অধিকার নেই।"),"error");return}
  fillBiz(Number(new URLSearchParams(location.search).get("biz")));
  await load();
 }catch(e){fail(e)}
}
async function load(){
 const body=$("wf-body");body.textContent="";status(L("Loading…","লোড হচ্ছে…"));
 try{
  state.access=await state.api.call("my_access",{p_business:state.biz});
  $("wf-level").textContent=String(state.access.level).replace(/_/g," ");
  $("wf-title").textContent=L(...TITLE[SCREEN]);
  await SCREENS[SCREEN](body);status(L("Ready · business #","প্রস্তুত · ব্যবসা #")+state.biz);
 }catch(e){fail(e)}
}
const TITLE={integration:["Portfolio workforce & staff identity","পোর্টফোলিও কর্মী ও পরিচয়"],delegation:["Delegated HR & payroll roles","অর্পিত এইচআর ও পে-রোল ভূমিকা"],
 policy:["Effective-dated policies & leave","কার্যকর-তারিখভিত্তিক নীতি ও ছুটি"],liability:["Payroll, liability & payment records","বেতন, দায় ও পরিশোধ নথি"]};
const owner=()=>!!(state.access&&state.access.owner);
const SCREENS={};

/* ---------- A053 integration ---------- */
SCREENS.integration=async function(body){
 const period=inp("pf-period","month",monthOf(today()));
 const out=h("div",{id:"pf-out"});
 async function refresh(){
  const r=await call("read_portfolio_workforce",{p_period:period.value+"-01"});if(!r)return;out.textContent="";
  out.append(h("div",{class:"row"},h("span",{class:"chip "+(r.state==="CONNECTED"?"good":"warn"),id:"pf-state",text:r.state.replace(/_/g," ")}),
   ...Object.entries(r.contracts||{}).map(([k,v])=>h("span",{class:"chip "+(v==="CONNECTED"?"good":"warn"),text:k.replace(/_/g," ")+": "+v.replace(/_/g," ")}))));
  if(r.state==="NOT_CONNECTED"){out.append(h("div",{class:"banner warn",id:"pf-nc",text:L("Workforce is NOT CONNECTED in this database. No numbers are shown or invented.","এই ডেটাবেসে কর্মী-মডিউল সংযুক্ত নয়। কোনো সংখ্যা দেখানো বা বানানো হয়নি।")}));return}
  out.append(h("div",{class:"cards"},r.businesses.map(b=>h("article",{class:"card","data-biz":b.business_id},h("h3",{text:"#"+b.business_id+" · "+b.name}),
   b.state==="OK"?[kv(L("Active headcount","সক্রিয় কর্মী"),b.workforce.active_headcount),
    ...b.workforce.headcount_by_site.map(s=>kv(L("Site ","সাইট ")+s.site_id,s.n)),
    h("h4",{text:L("Salary liability (owner only)","বেতন-দায় (শুধু মালিক)")}),
    kv(L("Approved payroll (net)","অনুমোদিত পে-রোল (নেট)"),money(b.liability.net_approved_preview)),
    h("div",{class:"kv"},h("span",{text:L("Run state","অবস্থা")}),stateChip(b.liability.state)),
    b.liability.approved_unpaid?[kv(L("Approved - payment NOT recorded","অনুমোদিত - পেমেন্ট নথিভুক্ত নয়"),money(b.liability.approved_unpaid.approved_unpaid_amount)),
      kv(L("Partly paid: still owed","আংশিক: এখনও বকেয়া"),money(b.liability.approved_unpaid.partially_paid_outstanding)),
      kv(L("Paid outside system (recorded)","সিস্টেমের বাইরে পরিশোধ (নথিভুক্ত)"),money(b.liability.approved_unpaid.paid_recorded_amount)),
      kv(L("Total still owed","মোট বকেয়া"),money(b.liability.approved_unpaid.total_outstanding))]
     :h("p",{class:"muted",text:L("Payment tracking: NOT CONNECTED","পেমেন্ট ট্র্যাকিং: সংযুক্ত নয়")}),
    kv("paid / money_movement / ledger",String(b.liability.paid)+" / "+String(b.liability.money_movement)+" / "+String(b.liability.ledger_posted))]
   :h("p",{class:"st "+(b.state==="OWNER_ONLY"?"dim":"bad"),text:b.state==="OWNER_ONLY"?L("OWNER ONLY - figures hidden for your role","শুধু মালিক - আপনার ভূমিকায় সংখ্যা লুকানো"):b.state.replace(/_/g," ")})))));
 }
 body.append(APPROVAL_NOTE(),panel(L("Owner Portfolio → Workforce (read-only)","মালিক পোর্টফোলিও → কর্মী (শুধু পড়া)"),
  h("div",null,h("div",{class:"row"},field(L("Month","মাস"),period),btn(L("Load","লোড"),refresh,"primary","pf-load")),out)));
 await refresh();
 // staff identity
 const staffBox=h("div",{id:"staff-box"});
 async function staff(){
  staffBox.textContent="";
  const mine=await call("my_assignments",{});
  if(mine)staffBox.append(h("h3",{text:L("My assignments","আমার নিয়োগ")}),table([[L("Business","ব্যবসা"),x=>"#"+x.business_id],[L("Employee no.","নম্বর"),x=>x.employee_no],[L("Site","সাইট"),x=>x.site_label||"—"],[L("Role","ভূমিকা"),x=>x.designation||"—"]],mine.items,L("You have no linked employee record.","আপনার যুক্ত কর্মী রেকর্ড নেই।")));
  const ov=await call("staff_overview",{});
  if(!ov){staffBox.append(h("p",{class:"muted",text:L("Staff directory needs manager or owner access.","কর্মী তালিকার জন্য ম্যানেজার/মালিক অধিকার লাগে।")}));return}
  let aliases=[];
  if(owner()){const pc=await call("persona_catalog",{});if(pc)aliases=pc.items.filter(a=>a.linkable&&a.active)}
  staffBox.append(h("h3",{text:L("Staff identity & site assignment","কর্মী পরিচয় ও সাইট নিয়োগ")}),
   table([[L("No.","নং"),x=>x.employee_no],[L("Name","নাম"),x=>x.full_name],[L("Site","সাইট"),x=>x.site_label||"—"],
    [L("Login link","লগইন"),x=>x.identity_linked?h("span",{class:"chip good",text:(x.identity_alias||L("linked","যুক্ত"))}):h("span",{class:"chip dim",text:L("not linked","যুক্ত নয়")})],
    ["",x=>owner()?(x.identity_linked?btn(L("Unlink","বিচ্ছিন্ন"),async()=>{if(await call("unlink_staff_identity",{p_request:key("unl"),p_employee:x.employee_id,p_reason:"Unlinked from Workforce UI"},L("Unlinked","বিচ্ছিন্ন")))staff()},"outline","unlink-"+x.employee_no)
      :aliases.length?linkForm(x,aliases):null):null]],ov.items));
 }
 function linkForm(x,aliases){const s=sel("al-"+x.employee_no,aliases.map(a=>[a.alias,a.alias]));
  return h("span",{class:"row"},s,btn(L("Link","যুক্ত"),async()=>{if(await call("link_staff_identity",{p_request:key("lnk"),p_employee:x.employee_id,p_alias:s.value,p_reason:"Linked from Workforce UI"},L("Linked (self-service only)","যুক্ত (শুধু নিজের তথ্য)")))staff()},"outline","link-"+x.employee_no))}
 body.append(panel(L("Staff identity","কর্মী পরিচয়"),staffBox));await staff();
};

/* ---------- A054 delegation ---------- */
const ROLES=[["hr",["HR (leave, corrections, employee edit)","এইচআর (ছুটি, সংশোধন, কর্মী সম্পাদনা)"]],["payroll_preparer",["Payroll preparer","পে-রোল প্রস্তুতকারী"]],
 ["payroll_reviewer",["Payroll reviewer","পে-রোল পর্যালোচক"]],["payroll_approver",["Payroll approver (approves amount owed, does not pay)","পে-রোল অনুমোদক (প্রাপ্য অনুমোদন, পরিশোধ নয়)"]],
 ["payment_recorder",["Payment recorder (records payments made outside)","পরিশোধ নথিভুক্তকারী (বাইরের পরিশোধ নথিভুক্ত)"]]];
SCREENS.delegation=async function(body){
 const a=state.access;
 body.append(panel(L("My delegated roles","আমার অর্পিত ভূমিকা"),h("div",null,
  h("p",{id:"my-roles"},a.delegated_roles.length?a.delegated_roles.map(r=>h("span",{class:"chip good",text:r.replace(/_/g," ")})):h("span",{class:"muted",text:L("No delegated roles. Authority comes only from your membership.","কোনো অর্পিত ভূমিকা নেই।")})),
  kv(L("Can view salary liability","বেতন-দায় দেখতে পারেন"),a.can_view_liability?L("yes","হ্যাঁ"):L("no","না")))));
 if(!owner()){body.append(h("p",{class:"muted",text:L("Only owners can grant or revoke delegations.","শুধু মালিক অর্পণ/বাতিল করতে পারেন।")}));return}
 const el=await call("eligible_delegates",{});if(!el)return;
 const who=sel("dg-who",el.items.map(x=>[x.uid,x.ref+" · "+x.source.replace(/_/g," ")])),role=sel("dg-role",ROLES.map(r=>[r[0],L(...r[1])])),
  eff=sel("dg-effect",[["allow",L("ALLOW","অনুমতি")],["deny",L("DENY (beats allow)","নিষেধ (অনুমতির উপরে)")]]),
  pf=inp("dg-from","month",monthOf(today())),pt=inp("dg-to","month",monthOf(today())),exp=inp("dg-exp","datetime-local",""),why=inp("dg-why","text","Delegation from Workforce UI");
 body.append(panel(L("Grant a delegation","অর্পণ করুন"),h("form",{class:"grid",id:"dg-form",onsubmit:async(ev)=>{ev.preventDefault();
  const r=await call("grant_delegation",{p_request:key("dg"),p_delegate:who.value,p_role:role.value,p_effect:eff.value,p_site:null,p_period_from:pf.value?pf.value+"-01":null,p_period_to:pt.value?pt.value+"-01":null,
   p_expires_at:exp.value?new Date(exp.value).toISOString():null,p_reason:why.value},L("Delegation saved","অর্পণ সংরক্ষিত"));if(r)load()}},
  field(L("Delegate","প্রতিনিধি"),who),field(L("Role","ভূমিকা"),role),field(L("Effect","ফলাফল"),eff),field(L("From month","শুরু মাস"),pf),field(L("To month","শেষ মাস"),pt),
  field(L("Expires (optional)","মেয়াদ (ঐচ্ছিক)"),exp,L("Revocation and expiry take effect on the very next call.","বাতিল/মেয়াদ পরের কলেই কার্যকর।")),field(L("Reason","কারণ"),why),
  h("button",{type:"submit",class:"primary",text:L("Grant","অর্পণ")}))));
 const ds=await call("list_delegations",{});if(!ds)return;
 body.append(panel(L("Delegations","অর্পণ তালিকা"),table([["#",x=>x.id],[L("Delegate","প্রতিনিধি"),x=>x.delegate_ref],[L("Role","ভূমিকা"),x=>x.role.replace(/_/g," ")],
  [L("Effect","ফলাফল"),x=>h("span",{class:"st "+(x.effect==="deny"?"bad":"paidrec"),text:x.effect.toUpperCase()})],[L("Period","সময়"),x=>(x.period_from||"…")+" → "+(x.period_to||"…")],
  [L("State","অবস্থা"),x=>h("span",{class:"chip "+(x.state==="active"?"good":"dim"),text:x.state})],
  ["",x=>x.state==="active"||x.state==="scheduled"?btn(L("Revoke now","এখনই বাতিল"),async()=>{if(await call("revoke_delegation",{p_request:key("rv"),p_delegation:x.id,p_expected_version:x.version,p_note:"Revoked from Workforce UI"},L("Revoked - effective immediately","বাতিল - সাথে সাথে কার্যকর")))load()},"outline","revoke-"+x.id):null]],ds.items)));
};

/* ---------- A054 policies & leave ---------- */
SCREENS.policy=async function(body){
 body.append(h("div",{class:"banner"},h("b",{text:L("Multipliers, not percentages. ","গুণক, শতাংশ নয়। ")}),
  L("Overtime multiplier 1.00x = 100% of the base hourly rate (not 1%). No statutory rate is assumed; every number is your configuration.","ওভারটাইম গুণক ১.০০x = মূল ঘণ্টা-হারের ১০০% (১% নয়)। কোনো আইনি হার ধরে নেওয়া হয়নি।")));
 const sections={ot:L("Overtime","ওভারটাইম"),rule:L("Allowance / deduction rules","ভাতা/কর্তন নিয়ম"),leave:L("Leave policy & balance","ছুটির নীতি ও ব্যালেন্স"),preview:L("Payroll preview with trace","ট্রেস সহ বেতন প্রিভিউ")};
 const tabs=h("div",{class:"tabs",role:"tablist"}),pane=h("div",{id:"pol-pane"});let cur="ot";
 for(const [k,t] of Object.entries(sections))tabs.append(h("button",{type:"button",role:"tab",id:"tab-"+k,"aria-selected":String(k===cur),onclick:()=>show(k),text:t}));
 body.append(tabs,pane);
 async function show(k){cur=k;for(const b of tabs.children)b.setAttribute("aria-selected",String(b.id==="tab-"+k));pane.textContent="";await TABS[k](pane)}
 const monthStart=()=>monthOf(today())+"-01";
 const vlist=(items,cols)=>table([[L("Subject","বিষয়"),x=>x.subject],["v",x=>x.version],[L("Effective from","কার্যকর"),x=>x.effective_from],...cols,
  [L("State","অবস্থা"),x=>h("span",{class:"chip "+(x.state==="effective"?"good":x.state==="scheduled"?"warn":"dim"),text:x.state})]],items,L("No versions yet.","কোনো সংস্করণ নেই।"));
 const TABS={
  async ot(p){
   const r=await call("list_policies",{p_kind:"overtime"});
   const mode=sel("ot-mode",[["on",L("Pay overtime","ওভারটাইম দিন")],["off",L("OFF (legal gate)","বন্ধ (আইনি গেট)")]]),w=inp("ot-w","number","1.50",{step:"0.01",min:"1",max:"5"}),
    o=inp("ot-o","number","2.00",{step:"0.01",min:"1",max:"5"}),ef=inp("ot-ef","month",monthOf(today())),lg=inp("ot-legal","text",""),why=inp("ot-why","text","Overtime policy version");
   if(owner())p.append(panel(L("New overtime policy version","নতুন ওভারটাইম নীতি"),h("form",{class:"grid",id:"ot-form",onsubmit:async(ev)=>{ev.preventDefault();
    const params=mode.value==="off"?{mode:"off"}:{mode:"on",weekday_multiplier:Number(w.value),offday_multiplier:Number(o.value)};
    if(await call("save_policy",{p_request:key("ot"),p_kind:"overtime",p_subject:"DEFAULT",p_effective_from:ef.value+"-01",p_params:params,p_reason:why.value,p_legal_ref:lg.value||null},L("Policy version saved","নীতি সংরক্ষিত")))show("ot")}},
    field(L("Mode","মোড"),mode),field(L("Weekday multiplier (x)","কর্মদিবস গুণক (x)"),w,L("1.00x = 100% of base hourly rate","১.০০x = মূল হারের ১০০%")),field(L("Off-day multiplier (x)","ছুটির দিন গুণক (x)"),o),
    field(L("Effective from (1st of month)","কার্যকর (মাসের ১ তারিখ)"),ef),field(L("Legal reference (needed for OFF)","আইনি রেফারেন্স (বন্ধের জন্য)"),lg),field(L("Reason","কারণ"),why),h("button",{type:"submit",class:"primary",text:L("Save version","সংরক্ষণ")}))));
   if(r)p.append(panel(L("Versions (immutable, effective-dated)","সংস্করণ (অপরিবর্তনীয়)"),vlist(r.items,[[L("Mode","মোড"),x=>x.params.mode==="off"?"OFF":x.params.weekday_multiplier+"x / "+x.params.offday_multiplier+"x"]])));
  },
  async rule(p){
   const r=await call("list_policies",{p_kind:"pay_rule"});
   const code=inp("rl-code","text","HOUSE"),name=inp("rl-name","text","House allowance"),kind=sel("rl-kind",[["allowance",L("Allowance","ভাতা")],["deduction",L("Deduction","কর্তন")]]),
    calc=sel("rl-calc",[["percent",L("Percent of a base","বেসের শতাংশ")],["fixed",L("Fixed amount","নির্দিষ্ট পরিমাণ")]]),amt=inp("rl-amt","number","10",{step:"0.01",min:"0"}),
    base=sel("rl-base",[["basic_earned",L("Basic earned","অর্জিত মূল বেতন")],["gross_before_rule",L("Gross before this rule","এই নিয়মের আগের গ্রস")],["contract_base",L("Contract base salary","চুক্তির মূল বেতন")]]),
    cap=inp("rl-cap","number","",{step:"0.01",min:"0"}),ef=inp("rl-ef","month",monthOf(today())),why=inp("rl-why","text","Pay rule version");
   if(owner())p.append(panel(L("New rule version","নতুন নিয়ম সংস্করণ"),h("form",{class:"grid",id:"rl-form",onsubmit:async(ev)=>{ev.preventDefault();
    const params={name:name.value,kind:kind.value,calc:calc.value,amount:Number(amt.value),enabled:true};
    if(calc.value==="percent")params.base=base.value;if(cap.value!=="")params.cap_amount=Number(cap.value);
    if(await call("save_policy",{p_request:key("rl"),p_kind:"pay_rule",p_subject:code.value,p_effective_from:ef.value+"-01",p_params:params,p_reason:why.value,p_legal_ref:null},L("Rule version saved","নিয়ম সংরক্ষিত")))show("rule")}},
    field(L("Code","কোড"),code),field(L("Name","নাম"),name),field(L("Kind","ধরন"),kind),field(L("Calculation","হিসাব"),calc),field(L("Amount (percent = 10 means 10%)","পরিমাণ (শতাংশ: ১০ = ১০%)"),amt),
    field(L("Base (percent only)","বেস (শুধু শতাংশ)"),base),field(L("Cap amount (optional)","সর্বোচ্চ (ঐচ্ছিক)"),cap),field(L("Effective from","কার্যকর"),ef),field(L("Reason","কারণ"),why),h("button",{type:"submit",class:"primary",text:L("Save version","সংরক্ষণ")}))));
   if(r)p.append(panel(L("Rule versions","নিয়ম সংস্করণ"),vlist(r.items,[[L("Rule","নিয়ম"),x=>x.params.kind+" · "+x.params.calc+" "+x.params.amount+(x.params.base?" of "+x.params.base:"")+(x.params.cap_amount!=null?" cap "+x.params.cap_amount:"")]])));
  },
  async leave(p){
   const yr=inp("lv-year","number",String(new Date().getUTCFullYear()),{min:"2000",max:"2100"});const box=h("div",{id:"lv-bal"});
   async function bal(){const r=await call("leave_balance",{p_employee:null,p_year:Number(yr.value)});box.textContent="";if(!r)return;
    box.append(table([[L("Type","ধরন"),x=>x.leave_type],[L("Entitlement","প্রাপ্য"),x=>x.entitlement==null?L("unlimited","সীমাহীন"):x.entitlement],[L("Carried in","আগের বছর থেকে"),x=>x.carried_in],
     [L("Carry used","ক্যারি ব্যবহৃত"),x=>x.carry_used],[L("Carry expired","ক্যারি মেয়াদোত্তীর্ণ"),x=>x.carry_expired],[L("Expiry","মেয়াদ"),x=>x.carry_expiry_date||"—"],[L("Used","ব্যবহৃত"),x=>x.used_total],
     [L("Available today","আজ উপলব্ধ"),x=>x.available_as_of_today==null?"—":x.available_as_of_today],[L("Carry to next year","পরবর্তী বছরে"),x=>x.remaining_end]],r.items))}
   p.append(panel(L("My leave balance (accrual, carry-forward, expiry)","আমার ছুটির ব্যালেন্স"),h("div",null,h("div",{class:"row"},field(L("Year","বছর"),yr),btn(L("Show","দেখান"),bal,"outline","lv-show")),box)));await bal();
   if(!cap_manager())return;
   const subj=inp("lp-subj","text","ANNUAL"),acc=sel("lp-acc",[["upfront",L("Full quota on 1 Jan","১ জানুয়ারিতে পুরো কোটা")],["monthly",L("Accrues monthly","মাসিক জমা")]]),q=inp("lp-q","number","10",{step:"0.5",min:"0"}),
    cc=inp("lp-cc","number","5",{step:"0.5",min:"0"}),ce=inp("lp-ce","number","3",{min:"1",max:"12"}),gd=inp("lp-gd","number","0",{min:"0",max:"90"}),cy=h("input",{id:"lp-cy",type:"checkbox"}),
    ef=inp("lp-ef","number",String(new Date().getUTCFullYear()+1),{min:"2000",max:"2100"}),why=inp("lp-why","text","Leave policy version");
   if(owner())p.append(panel(L("New leave policy version (effective 1 January)","নতুন ছুটির নীতি (১ জানুয়ারি থেকে)"),h("form",{class:"grid",id:"lp-form",onsubmit:async(ev)=>{ev.preventDefault();
    const params={accrual:acc.value,annual_quota_days:Number(q.value),carry_forward_cap_days:Number(cc.value),carry_expiry_months:ce.value?Number(ce.value):null,grace_days:Number(gd.value),allow_cross_year:cy.checked,enabled:true};
    if(await call("save_policy",{p_request:key("lp"),p_kind:"leave",p_subject:subj.value,p_effective_from:ef.value+"-01-01",p_params:params,p_reason:why.value,p_legal_ref:null},L("Leave policy saved","ছুটির নীতি সংরক্ষিত")))show("leave")}},
    field(L("Leave type code","ছুটির কোড"),subj),field(L("Accrual","জমা"),acc),field(L("Annual quota (days)","বার্ষিক কোটা"),q),field(L("Carry-forward cap (days)","ক্যারি সীমা"),cc),
    field(L("Carry expires after (months)","ক্যারি মেয়াদ (মাস)"),ce),field(L("Grace days","গ্রেস দিন"),gd),field(L("Allow cross-year requests","বছর-পেরোনো আবেদন"),cy),field(L("Effective year","কার্যকর বছর"),ef),field(L("Reason","কারণ"),why),
    h("button",{type:"submit",class:"primary",text:L("Save version","সংরক্ষণ")}))));
   const r=await call("list_policies",{p_kind:"leave"});if(r)p.append(panel(L("Leave policy versions","ছুটির নীতি সংস্করণ"),vlist(r.items,[[L("Policy","নীতি"),x=>x.params.accrual+" "+x.params.annual_quota_days+"d, carry ≤"+x.params.carry_forward_cap_days+(x.params.carry_expiry_months?" exp "+x.params.carry_expiry_months+"m":"")]])));
  },
  async preview(p){
   const per=inp("pv-period","month",monthOf(today()));const out=h("div",{id:"pv-out"});
   async function go(){const r=await call("payroll_preview",{p_period:per.value+"-01"});out.textContent="";if(!r)return;
    out.append(h("p",{class:"muted",text:L("Preview only - nothing is stored or paid.","শুধু প্রিভিউ - কিছু সংরক্ষিত বা পরিশোধিত নয়।")}),
     table([[L("No.","নং"),x=>x.employee_no],[L("Basic","মূল"),x=>money(x.basic_earned)],[L("Overtime","ওভারটাইম"),x=>money(x.overtime_pay)],[L("Allowances","ভাতা"),x=>money(x.allowances_total)],[L("Deductions","কর্তন"),x=>money(x.total_deductions)],[L("Net (owed, not paid)","নেট (প্রাপ্য, অপরিশোধিত)"),x=>money(x.net)],
      [L("Trace","ট্রেস"),x=>h("span",{class:"trace"},(x.components||[]).filter(c=>c.trace||c.kind==="trace").map(c=>c.kind==="trace"?"OT policy v"+c.policy_version_id+" "+(c.mode==="off"?"OFF":c.weekday_multiplier+"x/"+c.offday_multiplier+"x")+"; ":c.code+": "+(c.trace.base?c.trace.base+"="+money(c.trace.base_value)+" × ":"")+c.trace.amount_param+(c.trace.unit==="percent_of_base"?"%":"")+(c.trace.cap!=null?" cap "+c.trace.cap:"")+" → "+money(c.amount)+"; "))]],r.lines.filter(x=>x.employed_days!==0)))}
   p.append(panel(L("Payroll preview with policy trace","নীতি ট্রেস সহ প্রিভিউ"),h("div",null,h("div",{class:"row"},field(L("Month","মাস"),per),btn(L("Preview","প্রিভিউ"),go,"primary","pv-go")),out)));
  }};
 function cap_manager(){return owner()||state.access.level==="manager"}
 await show("ot");
};

/* ---------- A054 payroll lifecycle, liability, payment records, retention ---------- */
SCREENS.liability=async function(body){
 body.append(APPROVAL_NOTE());
 const per=inp("ly-period","month",monthOf(today()));const out=h("div",{id:"ly-out"}),runs=h("div",{id:"ly-runs"}),ret=h("div",{id:"ly-ret"});
 const TOTALS=(t)=>h("div",{class:"cards"},
  h("article",{class:"card",id:"c-approved"},h("h3",null,stateChip("approved_unpaid")),kv(L("Employees","কর্মী"),t.approved_unpaid_count),kv(L("Amount owed, no payment recorded","প্রাপ্য, পেমেন্ট নথিভুক্ত নয়"),money(t.approved_unpaid_amount))),
  h("article",{class:"card",id:"c-partial"},h("h3",null,stateChip("partially_paid_recorded")),kv(L("Employees","কর্মী"),t.partially_paid_count),kv(L("Still owed","এখনও বকেয়া"),money(t.partially_paid_outstanding))),
  h("article",{class:"card",id:"c-paid"},h("h3",null,stateChip("paid_recorded")),kv(L("Employees fully paid","পূর্ণ পরিশোধ"),t.paid_recorded_count),kv(L("Recorded as paid","পরিশোধ নথিভুক্ত"),money(t.paid_recorded_amount))),
  h("article",{class:"card",id:"c-total"},h("h3",{text:L("Totals","মোট")}),kv(L("Approved net total","অনুমোদিত নেট মোট"),money(t.approved_net_total)),kv(L("Total still owed","মোট বকেয়া"),money(t.total_outstanding)),
   t.overpaid_recorded_count?kv(L("Over-recorded lines","বেশি নথিভুক্ত"),t.overpaid_recorded_count):null));
 async function report(){
  const p=per.value+"-01";out.textContent="";
  const r=await call("liability_report",{p_period:p});if(!r)return;
  out.append(h("div",{class:"banner warn",id:"ly-flags"},L("This report is read-only. payment_executed=","এই রিপোর্ট শুধু পড়ার। payment_executed=")+String(r.payment_executed)+" · money_movement="+String(r.money_movement)+" · ledger_posted="+String(r.ledger_posted)),
   h("div",{class:"card",id:"c-pre"},h("h3",{text:L("Not yet approved (estimate, not a liability)","এখনও অনুমোদিত নয় (অনুমান, দায় নয়)")}),kv(L("Draft/reviewed runs","খসড়া/পর্যালোচিত রান"),r.pre_approval.runs),kv(L("Estimated net","আনুমানিক নেট"),money(r.pre_approval.estimated_net))),
   TOTALS(r.totals),
   h("h3",{text:L("By site: still owed","সাইট অনুযায়ী বকেয়া")}),table([[L("Site","সাইট"),x=>x.site_label||String(x.site_id)],[L("Employees","কর্মী"),x=>x.headcount],[L("Still owed","বকেয়া"),x=>money(x.outstanding)]],r.by_site),
   h("h3",{text:L("Employees","কর্মী")}),table([[L("No.","নং"),x=>x.employee_no],[L("Net owed","নেট প্রাপ্য"),x=>money(x.net)],[L("Recorded paid","নথিভুক্ত পরিশোধ"),x=>money(x.recorded_paid)],[L("Still owed","বকেয়া"),x=>money(x.outstanding)],[L("State","অবস্থা"),x=>stateChip(x.state)],
    ["",x=>x.outstanding>0?btn(L("Record payment made outside…","বাইরে করা পরিশোধ নথিভুক্ত…"),()=>payForm(x,p),"outline","rec-"+x.employee_no):null]],r.lines),
   btn(L("Export CSV (no names)","CSV (নাম ছাড়া)"),async()=>{const c=await call("export_liability_csv",{p_request:key("csv"),p_period:p},L("CSV prepared","CSV প্রস্তুত"));
    if(c){const a=h("a",{href:URL.createObjectURL(new Blob([c.csv],{type:"text/csv"})),download:c.filename,id:"csv-link",text:c.filename});out.append(h("p",null,a))}},"outline","csv-btn"));
 }
 function payForm(x,p){
  const amt=inp("pay-amt","number",String(x.outstanding),{step:"0.01",min:"0.01"}),m=sel("pay-method",[["cash","Cash"],["bank_transfer","Bank transfer"],["mobile_wallet","Mobile wallet"],["other","Other"]]),
   ref=inp("pay-ref","text",""),on=inp("pay-on","date",today()),note=inp("pay-note","text","");
  const f=h("form",{class:"grid",id:"pay-form",onsubmit:async(ev)=>{ev.preventDefault();
   if(await call("record_external_payment",{p_request:key("pay"),p_period:p,p_employee:x.employee_id,p_amount:Number(amt.value),p_method:m.value,p_reference:ref.value,p_paid_on:on.value,p_note:note.value||null},L("Recorded. No money was moved by this system.","নথিভুক্ত। এই সিস্টেম কোনো টাকা পাঠায়নি।")))report()}},
   h("p",{class:"banner warn",text:L("This RECORDS a payment you already made outside the system for "+x.employee_no+". It does not send money.","এটি "+x.employee_no+"-এর জন্য সিস্টেমের বাইরে করা পরিশোধ শুধু নথিভুক্ত করে; টাকা পাঠায় না।")}),
   field(L("Amount paid","পরিশোধিত পরিমাণ"),amt),field(L("Method","পদ্ধতি"),m),field(L("External reference (voucher / txn id)","বাহ্যিক রেফারেন্স"),ref),field(L("Paid on","তারিখ"),on),field(L("Note","নোট"),note),
   h("button",{type:"submit",class:"primary",text:L("Record external payment","বাইরের পরিশোধ নথিভুক্ত করুন")}));
  const old=$("pay-form");if(old)old.remove();out.append(f);f.scrollIntoView({block:"nearest"});
 }
 async function runsList(){
  runs.textContent="";const r=await call("list_payroll_runs",{});if(!r){runs.append(h("p",{class:"muted",text:L("Payroll runs need owner or delegated payroll access.","পে-রোল রানের জন্য মালিক/অর্পিত অধিকার লাগে।")}));return}
  const act=(x,a,label,cls)=>btn(label,async()=>{if(await call("payroll_transition",{p_request:key("tr"),p_run:x.id,p_action:a,p_note:"From Workforce UI"},L("Done. Paid: no.","সম্পন্ন। পরিশোধ: না।")))load()},cls||"outline","run-"+a+"-"+x.id);
  runs.append(h("div",{class:"row"},btn(L("Prepare draft for month","মাসের খসড়া প্রস্তুত"),async()=>{if(await call("create_payroll_draft",{p_request:key("dr"),p_period:per.value+"-01",p_amends_run:null,p_reason:null},L("Draft prepared","খসড়া প্রস্তুত")))load()},"outline","prep-draft")),
   table([[L("Month","মাস"),x=>x.period_start.slice(0,7)],["v",x=>x.version],[L("Status","অবস্থা"),x=>h("span",{class:"chip",text:x.status})],[L("Net","নেট"),x=>money(x.total_net)],[L("Blocking","ব্লক"),x=>x.blocking_count],
    [L("Step","ধাপ"),x=>h("span",{class:"actions"},
      x.status==="draft"?act(x,"review",L("Review (does not pay)","পর্যালোচনা (পরিশোধ নয়)")):null,
      x.status==="reviewed"?act(x,"approve",L("Approve amount owed (does NOT pay anyone)","প্রাপ্য অনুমোদন (কাউকে পরিশোধ নয়)"),"primary"):null,
      x.status==="approved"?act(x,"freeze",L("Freeze approved run (still not paid)","অনুমোদিত রান ফ্রিজ (এখনও অপরিশোধিত)")):null)]],r.items,L("No payroll runs.","পে-রোল রান নেই।")));
 }
 async function retention(){
  ret.textContent="";const r=await call("retention_report",{});if(!r){return}
  const emp=inp("hold-emp","number","",{min:"1"}),from=inp("hold-from","date",""),to=inp("hold-to","date",""),why=inp("hold-why","text","");
  ret.append(h("div",{class:"metrics"},h("div",null,h("small",{text:L("Retention (months)","সংরক্ষণ (মাস)")}),h("b",{text:r.retention_months})),h("div",null,h("small",{text:L("Expired raw punches","মেয়াদোত্তীর্ণ পাঞ্চ")}),h("b",{text:r.expired_raw_punches})),
   h("div",null,h("small",{text:L("Under legal hold","আইনি হোল্ডে")}),h("b",{text:r.protected_by_legal_hold})),h("div",null,h("small",{text:L("Purgeable now (dry-run)","এখন মোছা যাবে")}),h("b",{text:r.purgeable_now}))),
   h("p",{class:"muted",text:L("Only raw attendance punches are ever purged. Payslips, payroll runs, leave and audit are never purged.","শুধু কাঁচা হাজিরা পাঞ্চ মোছা হয়। পেস্লিপ, পে-রোল, ছুটি ও অডিট কখনও নয়।")}),
   h("form",{class:"grid",id:"hold-form",onsubmit:async(ev)=>{ev.preventDefault();if(await call("place_legal_hold",{p_request:key("hold"),p_employee:emp.value?Number(emp.value):null,p_from:from.value,p_to:to.value,p_reason:why.value},L("Legal hold placed","আইনি হোল্ড")))retention()}},
    field(L("Employee id (blank = whole business)","কর্মী আইডি (খালি = পুরো ব্যবসা)"),emp),field(L("From","শুরু"),from),field(L("To","শেষ"),to),field(L("Reason","কারণ"),why),h("button",{type:"submit",class:"outline",text:L("Place legal hold","আইনি হোল্ড দিন")})),
   table([["#",x=>x.id],[L("Employee","কর্মী"),x=>x.employee_id||L("all","সব")],[L("From","শুরু"),x=>x.hold_from],[L("To","শেষ"),x=>x.hold_to],[L("Reason","কারণ"),x=>x.reason],
    ["",x=>btn(L("Release (tenant owner)","মুক্ত (টেন্যান্ট মালিক)"),async()=>{if(await call("release_legal_hold",{p_request:key("rel"),p_hold:x.id,p_note:"Released from Workforce UI"},L("Released","মুক্ত")))retention()},"outline","rel-"+x.id)]],r.active_holds,L("No active legal holds.","কোনো সক্রিয় হোল্ড নেই।")));
 }
 body.append(panel(L("Payroll lifecycle (approval only)","পে-রোল ধাপ (শুধু অনুমোদন)"),runs),
  panel(L("Salary liability: approved vs paid","বেতন-দায়: অনুমোদিত বনাম পরিশোধিত"),h("div",null,h("div",{class:"row"},field(L("Month","মাস"),per),btn(L("Show liability","দায় দেখুন"),report,"primary","ly-show")),out)));
 if(owner())body.append(panel(L("Raw punch retention & legal holds","কাঁচা পাঞ্চ সংরক্ষণ ও আইনি হোল্ড"),ret));
 await runsList();await report();if(owner())await retention();
};
boot();
})();
