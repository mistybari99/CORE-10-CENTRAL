/* C10-A052 Owner Intent UI. Signed RPC only (core10-owner-intent-client.js). Every success message comes from a
 * server receipt. Preview writes nothing; only the tenant Owner can approve/publish; publishing is advisory config. */
(function(){"use strict";
const E=window.CORE10_INTENT_ENGINE,G=window.CORE10_INTENT_GUIDANCE,A=window.CORE10_INTENT_API,root=document.getElementById("oi-root");
const $=(id)=>document.getElementById(id);
const esc=(v)=>String(v==null?"":v).replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
const S={api:null,lang:"bn",businesses:[],biz:null,ctx:null,parse:null,cur:null,preview:null,intents:[],hist:null,reqs:[],guide:null,busy:false};
try{const l=localStorage.getItem("c10_a052_lang");if(l==="en"||l==="bn")S.lang=l}catch(e){}
const TX={
 title:{en:"Owner Intent",bn:"মালিকের ইচ্ছা (Intent)"},
 safety:{en:"Preview writes nothing. Publishing stores an advisory setting only — it never posts stock, money, payroll or permissions. Unsupported requests are stored as engineering requirements and never run.",
  bn:"প্রিভিউ কিছু লেখে না। প্রকাশ করলে শুধু পরামর্শমূলক সেটিং সংরক্ষিত হয় — স্টক, টাকা, বেতন বা অনুমতি পোস্ট হয় না। অসমর্থিত অনুরোধ ইঞ্জিনিয়ারিং রিকোয়ারমেন্ট হিসেবে জমা থাকে, চলে না।"},
 business:{en:"Business",bn:"ব্যবসা"},site:{en:"Site (optional)",bn:"সাইট (ঐচ্ছিক)"},none:{en:"Whole business",bn:"পুরো ব্যবসা"},
 reqTitle:{en:"1. Describe what you want",bn:"১. আপনি কী চান লিখুন"},ph:{en:"e.g. Warn me if sweets wastage goes above 3%",bn:"যেমন: মিষ্টির নষ্ট ৩ শতাংশের বেশি হলে সতর্ক করো"},
 interpret:{en:"Interpret",bn:"ব্যাখ্যা করো"},examples:{en:"Examples",bn:"উদাহরণ"},
 interTitle:{en:"2. Interpretation (editable)",bn:"২. ব্যাখ্যা (সম্পাদনাযোগ্য)"},
 saveprev:{en:"Save & preview",bn:"সংরক্ষণ ও প্রিভিউ"},update:{en:"Update & re-preview",bn:"হালনাগাদ ও আবার প্রিভিউ"},saveeng:{en:"Save as engineering requirement",bn:"ইঞ্জিনিয়ারিং রিকোয়ারমেন্ট হিসেবে সংরক্ষণ"},
 prevTitle:{en:"3. Safe preview (nothing applied)",bn:"৩. নিরাপদ প্রিভিউ (কিছু প্রয়োগ হয়নি)"},
 validate:{en:"Validate",bn:"যাচাই"},approve:{en:"Approve",bn:"অনুমোদন"},publish:{en:"Publish",bn:"প্রকাশ"},reject:{en:"Reject",bn:"বাতিল"},
 reason:{en:"Reason (5+ characters)",bn:"কারণ (৫+ অক্ষর)"},histTitle:{en:"Versions, audit & rollback",bn:"সংস্করণ, অডিট ও রোলব্যাক"},rollback:{en:"Roll back to this",bn:"এতে ফিরে যাও"},
 reqsTitle:{en:"Engineering requirements",bn:"ইঞ্জিনিয়ারিং রিকোয়ারমেন্ট"},intentsTitle:{en:"My requests",bn:"আমার অনুরোধ"},
 guideTitle:{en:"Guidance",bn:"নির্দেশনা"},guideHint:{en:"Press ⓘ next to any control.",bn:"যেকোনো কন্ট্রোলের পাশের ⓘ চাপুন।"},
 ctxTitle:{en:"Detected context",bn:"শনাক্ত প্রেক্ষাপট"},
 notSupported:{en:"Not executable: no certified handler. Stored as an engineering requirement.",bn:"চালানো যায় না: সার্টিফাইড হ্যান্ডলার নেই। ইঞ্জিনিয়ারিং রিকোয়ারমেন্ট হিসেবে জমা থাকবে।"},
 refused:{en:"Refused by policy. It is recorded but can never be built through a prompt.",bn:"নীতিগতভাবে প্রত্যাখ্যাত। রেকর্ড থাকবে, কিন্তু প্রম্পটের মাধ্যমে কখনো তৈরি হবে না।"},
 canPublish:{en:"Only the tenant Owner can approve and publish.",bn:"শুধু টেন্যান্ট মালিক অনুমোদন ও প্রকাশ করতে পারেন।"},
 sample:{en:"Sample numbers",bn:"নমুনা সংখ্যা"},before:{en:"Before",bn:"আগে"},after:{en:"After",bn:"পরে"},formula:{en:"Formula & steps",bn:"সূত্র ও ধাপ"},
 impact:{en:"Impact",bn:"প্রভাব"},conflicts:{en:"Conflicts & notes",bn:"দ্বন্দ্ব ও নোট"},diff:{en:"Dry-run diff",bn:"ড্রাই-রান পার্থক্য"},
 nowrite:{en:"NO WRITE — preview only",bn:"কিছু লেখা হয়নি — শুধু প্রিভিউ"},
 assumptions:{en:"Assumptions (editable above)",bn:"অনুমান (উপরে সম্পাদনাযোগ্য)"},questions:{en:"Please clarify",bn:"অনুগ্রহ করে জানান"},
 badLocale:{en:"Please write in Bangla or English.",bn:"অনুগ্রহ করে বাংলা বা ইংরেজিতে লিখুন।"}
};
const t=(k)=>(TX[k]&&TX[k][S.lang])||k;
const L=(o)=>o&&typeof o==="object"?(o[S.lang]||o.en||""):String(o==null?"":o);
const STATUS={SUPPORTED:{en:"Supported",bn:"সমর্থিত"},NEEDS_CLARIFICATION:{en:"Needs clarification",bn:"স্পষ্টীকরণ দরকার"},ENGINEERING_REQUIRED:{en:"Engineering required",bn:"ইঞ্জিনিয়ারিং দরকার"},
 UNSUPPORTED:{en:"Not allowed",bn:"অনুমোদিত নয়"},INTERPRETED:{en:"Interpreted",bn:"ব্যাখ্যাত"},PREVIEWED:{en:"Previewed",bn:"প্রিভিউ হয়েছে"},VALIDATED:{en:"Validated",bn:"যাচাইকৃত"},
 APPROVED:{en:"Approved",bn:"অনুমোদিত"},PUBLISHED:{en:"Published (advisory)",bn:"প্রকাশিত (পরামর্শমূলক)"},REJECTED:{en:"Rejected",bn:"বাতিল"}};
const pill=(s)=>'<span class="oi-pill" data-s="'+esc(s)+'">'+esc(L(STATUS[s])||s)+'</span>';
const EXAMPLES=[{en:"Warn me if sweets wastage goes above 3%",bn:"মিষ্টির নষ্ট ৩ শতাংশের বেশি হলে সতর্ক করো"},
 {en:"If a 4 litre paint pack discount drops margin below 15% warn me",bn:"পেইন্ট ৪ লিটার প্যাকে ডিসকাউন্ট দিলে মার্জিন ১৫% এর নিচে গেলে অনুমোদন লাগবে"},
 {en:"Project materials order of 6 lakh taka or more needs my approval",bn:"প্রকল্পের মালামালের অর্ডার ৬ লাখ টাকা বা তার বেশি হলে আমার অনুমোদন লাগবে"},
 {en:"Show monthly project materials report",bn:"প্রকল্পের মালামালের মাসিক রিপোর্ট দেখাও"},{en:"Give Rahim admin permission",bn:"রহিমকে অ্যাডমিন অনুমতি দাও"}];
function status(m,err){const n=$("oi-status");if(n){n.textContent=m;n.dataset.tone=err?"error":"ok"}}
const fmtErr=(e)=>String((e&&((e.code&&String(e.code).length<40?e.code+": ":"")+(e.message||"")))||"RPC_UNAVAILABLE");
async function run(label,fn){if(S.busy)return;S.busy=true;status(label+"…");
 try{const m=await fn();status(m||"")}catch(e){status((S.lang==="bn"?"ব্যর্থ বা অনুমোদিত নয় — ":"Denied or failed — ")+fmtErr(e),true)}finally{S.busy=false}}
const info=(key)=>'<button type="button" class="info" data-guide="'+esc(key)+'" aria-label="'+esc(S.lang==="bn"?"নির্দেশনা":"Guidance")+'">ⓘ</button>';
const canPublish=()=>!!(S.ctx&&S.ctx.actor&&S.ctx.actor.can_publish);
const canSubmit=()=>!!(S.ctx&&S.ctx.actor&&S.ctx.actor.can_submit);
const capSpec=(k)=>E.CAPABILITIES[k];

function shell(){
 root.innerHTML='<div class="oi-top"><div><div class="oi-kicker">OWNER INTENT · C10-A052 · D049</div><h1>'+esc(t("title"))+'</h1></div>'+
 '<div class="oi-ctl"><label>'+esc(t("business"))+'<select id="oi-biz"></select></label>'+
 '<button type="button" class="outline" id="oi-lang" aria-label="language">'+(S.lang==="bn"?"English":"বাংলা")+'</button></div></div>'+
 '<div class="oi-safety" role="note">'+esc(t("safety"))+'</div><div id="oi-status" role="status" aria-live="polite"></div>'+
 '<div class="oi-grid"><section class="oi-panel"><h2>'+esc(t("reqTitle"))+info("intent.request_box")+'</h2>'+
 '<div class="oi-form"><label>'+esc(t("site"))+'<select id="oi-site"></select></label>'+
 '<label for="oi-text">'+esc(t("reqTitle"))+'<textarea id="oi-text" lang="'+S.lang+'" placeholder="'+esc(t("ph"))+'"></textarea></label></div>'+
 '<div class="oi-actions"><button type="button" class="primary" id="oi-interpret">'+esc(t("interpret"))+'</button></div>'+
 '<div class="oi-muted">'+esc(t("examples"))+'</div><div class="oi-chips" id="oi-examples"></div>'+
 '<div id="oi-ctx" class="oi-box"></div></section>'+
 '<section class="oi-panel"><h2>'+esc(t("interTitle"))+'</h2><div id="oi-inter"><p class="oi-muted">—</p></div></section>'+
 '<section class="oi-panel oi-wide"><h2>'+esc(t("prevTitle"))+info("intent.preview_diff")+'</h2><div id="oi-preview"><p class="oi-muted">—</p></div></section>'+
 '<section class="oi-panel"><h2>'+esc(t("histTitle"))+info("intent.rollback")+'</h2><div id="oi-history"></div></section>'+
 '<section class="oi-panel"><h2>'+esc(t("reqsTitle"))+info("intent.engineering_requirement")+'</h2><div id="oi-reqs"></div></section>'+
 '<section class="oi-panel"><h2>'+esc(t("intentsTitle"))+'</h2><div id="oi-intents"></div></section>'+
 '<section class="oi-panel oi-guide" aria-live="polite"><h2>'+esc(t("guideTitle"))+'</h2><div id="oi-guide"><p class="oi-muted">'+esc(t("guideHint"))+'</p></div></section></div>';
 $("oi-lang").onclick=()=>{S.lang=S.lang==="bn"?"en":"bn";try{localStorage.setItem("c10_a052_lang",S.lang)}catch(e){}const txt=$("oi-text")?$("oi-text").value:"";shell();$("oi-text").value=txt;fill();renderAll();};
 $("oi-interpret").onclick=interpret;
 $("oi-biz").onchange=()=>run("…",async()=>{S.biz=Number($("oi-biz").value);S.cur=null;S.preview=null;S.parse=null;await loadBusiness();renderAll();return""});
 root.addEventListener("click",onClick);
}
function fill(){
 $("oi-biz").innerHTML=S.businesses.map(b=>'<option value="'+b.business_id+'"'+(b.business_id===S.biz?" selected":"")+'>'+esc(b.name)+' #'+b.business_id+'</option>').join("");
 const sites=(S.ctx&&S.ctx.sites)||[];
 $("oi-site").innerHTML='<option value="">'+esc(t("none"))+'</option>'+sites.map(x=>'<option value="'+x.site_id+'">'+esc(x.label)+' ('+esc(x.kind)+')</option>').join("");
 $("oi-examples").innerHTML=EXAMPLES.map((x,i)=>'<button type="button" class="chip" data-ex="'+i+'">'+esc(x[S.lang])+'</button>').join("");
}
function renderCtx(){
 const c=S.ctx;if(!c){$("oi-ctx").innerHTML="";return}
 const mods=(c.modules||[]).map(m=>esc(m.module_code)+":"+esc(m.visibility)).join(", ")||"—";
 $("oi-ctx").innerHTML='<h3>'+esc(t("ctxTitle"))+'</h3><div>'+esc(c.business.slug)+' · '+esc(c.business.template_code)+' ('+esc(c.business.template_source_status||"")+')</div>'+
  '<div>'+esc(S.lang==="bn"?"আপনার ভূমিকা":"Your role")+': <b id="oi-role">'+esc(c.actor.role)+'</b> · '+(canPublish()?"":esc(t("canPublish")))+'</div>'+
  '<div>'+esc(S.lang==="bn"?"মডিউল":"Modules")+': '+mods+'</div>'+
  '<div>'+esc(S.lang==="bn"?"সার্টিফাইড সক্ষমতা":"Certified capabilities")+': '+c.capabilities.map(x=>esc(L(x.title))).join(" · ")+'</div>';
}
/* ---------- interpretation ---------- */
function interpret(){
 const text=$("oi-text").value;const it=S.api.interpret(text);
 S.cur=null;S.preview=null;S.parse=it.result;renderInter();renderPreview();
 if(!it.submittable)status(t("badLocale"),true);else status((S.lang==="bn"?"ব্যাখ্যা তৈরি হয়েছে — এখনো কিছু সংরক্ষিত হয়নি।":"Interpreted — nothing saved yet."));
}
function paramFields(cap,params,disabled){
 return capSpec(cap).params.map(p=>{
  const v=params[p.name],id="oi-p-"+p.name,lab=esc(L(p.label));
  if(p.type==="select")return'<label>'+lab+'<select id="'+id+'" data-param="'+p.name+'"'+(disabled?" disabled":"")+'>'+(v===undefined?'<option value="">—</option>':"")+p.options.map(o=>'<option value="'+o+'"'+(o===v?" selected":"")+'>'+esc(o)+'</option>').join("")+'</select></label>';
  return'<label>'+lab+'<input id="'+id+'" data-param="'+p.name+'" '+(p.type==="number"?'type="number" step="any" inputmode="decimal"':'type="text"')+' value="'+esc(v===undefined?"":v)+'"'+(disabled?" disabled":"")+'></label>';
 }).join("");
}
function readParams(cap){
 const out={};
 for(const p of capSpec(cap).params){const el=$("oi-p-"+p.name);if(!el||el.value==="")continue;out[p.name]=p.type==="number"?Number(el.value):el.value}
 return out;
}
function renderInter(){
 const r=S.parse,el=$("oi-inter");if(!r){el.innerHTML='<p class="oi-muted">—</p>';return}
 let h='<div>'+pill(r.support_status)+' <span class="oi-muted">'+esc(r.locale)+' · '+esc(r.parser_version)+' · '+(Math.round(r.confidence*100))+'%</span></div>';
 if(r.support_status==="ENGINEERING_REQUIRED"||r.support_status==="UNSUPPORTED"){
  const u=r.unsupported;
  h+='<div class="oi-box" id="oi-unsupported"><h3>'+esc(r.support_status==="UNSUPPORTED"?t("refused"):t("notSupported"))+'</h3><div>'+esc(S.lang==="bn"?u.reason_bn:u.reason_en)+'</div>'+
   '<div class="oi-muted">'+esc(u.category)+(u.a045_handler_id?" · A045: "+esc(u.a045_handler_id)+" (not certified)":"")+'</div>'+
   '<ul class="oi-list">'+(u.requirement.acceptance_criteria||[]).map(x=>'<li>'+esc(x)+'</li>').join("")+'</ul></div>'+
   (canSubmit()?'<div class="oi-actions"><button type="button" class="primary" id="oi-saveeng">'+esc(t("saveeng"))+'</button></div>':"");
 }else if(r.locale==="unknown"){
  h+='<div class="oi-box">'+esc(t("badLocale"))+'</div>';
 }else{
  const cap=r.capability_key;
  h+=(cap?'<div><b>'+esc(L(capSpec(cap).title))+'</b> '+info(capSpec(cap).guidance)+'</div>':"");
  if(r.questions.length)h+='<div class="oi-box" id="oi-questions"><h3>'+esc(t("questions"))+'</h3><ul class="oi-list">'+r.questions.map(q=>'<li>'+esc(L(q))+'</li>').join("")+'</ul></div>';
  h+='<div class="oi-form two" id="oi-params">'+paramFields(cap,r.params,!canSubmit())+'</div>';
  if(r.assumptions.length)h+='<div class="oi-box" id="oi-assumptions"><h3>'+esc(t("assumptions"))+'</h3><ul class="oi-list">'+r.assumptions.map(a=>'<li>'+esc(L(a))+'</li>').join("")+'</ul></div>';
  if(canSubmit())h+='<div class="oi-actions"><button type="button" class="primary" id="oi-saveprev">'+esc(S.cur?t("update"):t("saveprev"))+'</button></div>';
  else h+='<div class="oi-box">'+esc(S.lang==="bn"?"আপনার ভূমিকা এই অনুরোধ জমা দিতে পারে না।":"Your role cannot submit requests.")+'</div>';
 }
 el.innerHTML=h;
}
function interpretationFrom(r,params){
 const i=E.toInterpretation(r);i.params=params;
 const v=E.validateParams(r.capability_key,params);
 if(v.ok){i.support_status="SUPPORTED";i.missing=[];i.questions=[]}else{i.support_status="NEEDS_CLARIFICATION";i.missing=v.errors.map(x=>x.replace(/^missing: /,"").split(" ")[0])}
 return{i,v};
}
async function saveAndPreview(){
 const r=S.parse,params=readParams(r.capability_key);
 const {i,v}=interpretationFrom(r,params);
 if(!v.ok){status((S.lang==="bn"?"মান ঠিক করুন: ":"Fix values: ")+v.errors.join("; "),true);return}
 const site=$("oi-site").value?Number($("oi-site").value):null;
 let cur=S.cur;
 if(!cur){const s=await S.api.submit(S.biz,site,$("oi-text").value,i);cur={intent_id:s.intent_id,version:s.version}}
 else{const rv=await S.api.revise(cur.intent_id,cur.version,i);cur={intent_id:cur.intent_id,version:rv.version}}
 S.parse=Object.assign({},r,{params,support_status:"SUPPORTED",missing:[],questions:[]});
 const sample=readSample();
 const p=await S.api.preview(cur.intent_id,cur.version,sample);
 S.cur={intent_id:cur.intent_id,version:cur.version,status:"PREVIEWED",hash:p.preview_hash};S.preview=p.preview;
 await refreshLists();renderAll();
 return(S.lang==="bn"?"প্রিভিউ তৈরি — কিছু প্রয়োগ হয়নি (intent #":"Preview ready — nothing applied (intent #")+cur.intent_id+")";
}
async function saveEng(){
 const i=E.toInterpretation(S.parse),site=$("oi-site").value?Number($("oi-site").value):null;
 const s=await S.api.submit(S.biz,site,$("oi-text").value,i);
 await refreshLists();renderAll();
 return(S.lang==="bn"?"ইঞ্জিনিয়ারিং রিকোয়ারমেন্ট সংরক্ষিত (intent #":"Engineering requirement stored (intent #")+s.intent_id+") · "+s.intent_status;
}
/* ---------- preview ---------- */
function readSample(){
 if(!S.parse||!S.parse.capability_key)return null;
 const out={};let any=false;
 for(const f of capSpec(S.parse.capability_key).sampleFields){const el=$("oi-s-"+f.name);if(el&&el.value!==""){out[f.name]=Number(el.value);any=true}}
 return any?out:null;
}
function evalHtml(ev){
 if(!ev)return'<span class="oi-muted">—</span>';
 return'<div>'+esc(S.lang==="bn"?"ফলাফল":"outcome")+' <b>'+esc(ev.outcome)+'</b> · matched='+esc(ev.matched)+'</div><div class="oi-muted">'+Object.entries(ev.computed||{}).map(([k,v])=>esc(k)+' = '+esc(v)).join(" · ")+'</div>';
}
function renderPreview(){
 const el=$("oi-preview"),p=S.preview;
 if(!p){el.innerHTML='<p class="oi-muted">—</p>';return}
 const cap=p.capability_key,spec=capSpec(cap),imp=p.impact;
 let h='<div><span class="oi-nowrite" id="oi-nowrite">'+esc(t("nowrite"))+'</span> '+(S.cur?pill(S.cur.status):"")+' <b>'+esc(L(spec.title))+'</b></div>';
 h+='<div class="oi-box"><h3>'+esc(t("sample"))+'</h3><div class="oi-form two">'+spec.sampleFields.map(f=>'<label>'+esc(L(f.label))+'<input id="oi-s-'+f.name+'" type="number" step="any" inputmode="decimal" value="'+esc(p.sample.inputs[f.name])+'"></label>').join("")+
  '</div><div class="oi-actions"><button type="button" class="outline" id="oi-rerun">'+esc(S.lang==="bn"?"নমুনা দিয়ে আবার প্রিভিউ":"Re-preview with these numbers")+'</button></div>'+
  '<div class="oi-form two"><div><h3>'+esc(t("before"))+'</h3>'+evalHtml(p.sample.before)+'</div><div><h3>'+esc(t("after"))+'</h3><div id="oi-after">'+evalHtml(p.sample.after)+'</div></div></div></div>';
 h+='<div class="oi-box"><h3>'+esc(t("formula"))+'</h3><div>'+esc(S.lang==="bn"?p.formula.expression_bn:p.formula.expression_en)+'</div><ul class="oi-list" id="oi-steps">'+p.formula.steps.map(x=>'<li>'+esc(x)+'</li>').join("")+'</ul>'+
  '<div class="oi-muted">units: '+esc(JSON.stringify(p.formula.units))+'</div></div>';
 h+='<div class="oi-box"><h3>'+esc(t("diff"))+'</h3><div class="oi-diff" id="oi-diff">'+p.diff.map(d=>'<div>'+esc(d.path)+': <span class="b">'+esc(d.before==null?"∅":JSON.stringify(d.before))+'</span> → <span class="a">'+esc(JSON.stringify(d.after))+'</span></div>').join("")+'</div></div>';
 h+='<div class="oi-box" id="oi-impact"><h3>'+esc(t("impact"))+'</h3><ul class="oi-list">'+
  '<li><b>'+esc(S.lang==="bn"?"এন্টিটি":"Entities")+':</b> '+imp.entities.map(esc).join(", ")+'</li>'+
  '<li><b>'+esc(S.lang==="bn"?"সূত্র":"Formulas")+':</b> '+imp.formulas.map(f=>esc(S.lang==="bn"?f.expression_bn:f.expression_en)).join(" | ")+'</li>'+
  '<li><b>'+esc(S.lang==="bn"?"রিপোর্ট":"Reports")+':</b> '+imp.reports.map(r=>esc(r.id)+" ["+esc(r.status)+"] "+esc(S.lang==="bn"?r.note_bn:r.note_en)).join(" | ")+'</li>'+
  '<li><b>'+esc(S.lang==="bn"?"অনুমতি":"Permissions")+':</b> '+imp.permissions.map(x=>esc(x.action)+" → "+esc(x.required_role)).join(" | ")+'</li>'+
  '<li><b>'+esc(S.lang==="bn"?"অনুমোদন":"Approvals")+':</b> '+(imp.approvals.length?imp.approvals.map(x=>esc(x.when)+" ("+esc(x.who)+(x.enforced?"":", not enforced yet")+")").join(" | "):"—")+'</li>'+
  '<li><b>'+esc(S.lang==="bn"?"নিম্নমুখী মডিউল":"Downstream modules")+':</b> '+imp.downstream_modules.map(m=>esc(m.module_code)+" ["+esc(m.state)+"] "+esc(m.effect)).join(" | ")+'</li></ul></div>';
 h+='<div class="oi-box" id="oi-conflicts"><h3>'+esc(t("conflicts"))+'</h3><ul class="oi-list">'+imp.conflicts.map(c=>'<li class="oi-conf" data-sev="'+esc(c.severity)+'">['+esc(c.severity)+'] '+esc(S.lang==="bn"?c.message_bn:c.message_en)+'</li>').join("")+'</ul></div>';
 if(S.cur&&canSubmit()){
  const st=S.cur.status,pub=canPublish(),blocked=imp.blocked;
  h+='<div class="oi-box"><div class="oi-form two"><label>'+esc(t("reason"))+'<input id="oi-reason" type="text" value=""></label></div><div class="oi-actions">'+
   '<button type="button" class="primary" id="oi-validate"'+(st==="PREVIEWED"&&!blocked?"":" disabled")+'>'+esc(t("validate"))+'</button>'+
   '<button type="button" class="primary" id="oi-approve"'+(st==="VALIDATED"&&pub?"":" disabled")+'>'+esc(t("approve"))+'</button>'+
   '<button type="button" class="primary" id="oi-publish"'+(st==="APPROVED"&&pub?"":" disabled")+'>'+esc(t("publish"))+'</button>'+
   '<button type="button" class="danger" id="oi-reject"'+(["PREVIEWED","VALIDATED","APPROVED"].includes(st)?"":" disabled")+'>'+esc(t("reject"))+'</button>'+info("intent.approval_publish")+'</div>'+
   (pub?"":'<div class="oi-muted">'+esc(t("canPublish"))+'</div>')+(blocked?'<div class="oi-conf" data-sev="blocking">'+esc(S.lang==="bn"?"ব্লকিং দ্বন্দ্ব: যাচাই করা যাবে না।":"Blocking conflict: cannot validate.")+'</div>':"")+'</div>';
 }
 el.innerHTML=h;
}
async function step(kind){
 const c=S.cur,reason=($("oi-reason")||{}).value||"";let r;
 if(kind==="validate"){r=await S.api.validate(c.intent_id,c.version,c.hash);S.cur.status="VALIDATED"}
 else if(kind==="approve"){r=await S.api.approve(c.intent_id,c.version,reason);S.cur.status="APPROVED"}
 else if(kind==="publish"){r=await S.api.publish(c.intent_id,c.version);S.cur.status="PUBLISHED"}
 else{r=await S.api.reject(c.intent_id,c.version,reason);S.cur.status="REJECTED"}
 await refreshLists();renderAll();
 return(kind==="publish"?(S.lang==="bn"?"প্রকাশিত (পরামর্শমূলক) · সেটিং সংস্করণ ":"Published (advisory) · setting version ")+r.setting_version:(S.lang==="bn"?"সম্পন্ন: ":"Done: ")+r.intent_status);
}
/* ---------- lists ---------- */
function renderHistory(){
 const h=S.hist,el=$("oi-history");if(!h){el.innerHTML="";return}
 const keys=[...new Set(h.settings.map(s=>s.setting_key))];
 let out=keys.map(k=>{
  const vs=h.settings.filter(s=>s.setting_key===k),act=vs.find(s=>s.state==="ACTIVE");
  return'<div class="oi-box" data-setting="'+esc(k)+'"><h3>'+esc(L((capSpec(k)||{title:k}).title))+'</h3>'+vs.map(s=>'<div class="oi-row cols" data-version="'+s.version+'"><span>v'+s.version+' '+pill(s.state==="ACTIVE"?"PUBLISHED":"REJECTED").replace(/>[^<]*</,">"+esc(s.state)+"<")+
   (s.rollback_of_version?' ↩ v'+s.rollback_of_version:"")+'</span><span>'+esc(JSON.stringify(s.params))+'</span><span class="oi-muted">'+esc(String(s.created_at).slice(0,19))+'</span>'+
   (canPublish()&&act&&s.state!=="ACTIVE"?'<button type="button" class="outline" data-rollback="'+esc(k)+'" data-to="'+s.version+'" data-active="'+act.version+'">'+esc(t("rollback"))+'</button>':"<span></span>")+'</div>').join("")+'</div>'}).join("");
 out+='<div class="oi-box"><h3>Audit</h3><ul class="oi-list" id="oi-audit">'+h.audit.slice(0,12).map(a=>'<li data-audit="'+a.audit_id+'">'+esc(a.event)+(a.setting_key?" · "+esc(a.setting_key):"")+' <span class="oi-muted">'+esc(String(a.created_at).slice(0,19))+'</span></li>').join("")+'</ul></div>';
 el.innerHTML=out;
}
function renderReqs(){
 $("oi-reqs").innerHTML=S.reqs.length?S.reqs.map(r=>'<div class="oi-row" data-req="'+r.requirement_id+'"><div>'+pill(r.status==="NEEDS_HANDLER_BUILD"?"ENGINEERING_REQUIRED":"UNSUPPORTED").replace(/>[^<]*</,">"+esc(r.status)+"<")+' <b>'+esc(L({en:r.requirement.title_en,bn:r.requirement.title_bn}))+'</b></div>'+
  '<div class="oi-muted">'+esc(r.category)+(r.a045_handler_id?" · A045 "+esc(r.a045_handler_id)+" certified="+esc(r.a045_certified):"")+'</div>'+
  '<ul class="oi-list">'+(r.requirement.acceptance_criteria||[]).map(x=>'<li>'+esc(x)+'</li>').join("")+'</ul></div>').join(""):'<p class="oi-muted">—</p>';
}
function renderIntents(){
 $("oi-intents").innerHTML=S.intents.length?S.intents.slice(0,15).map(i=>'<div class="oi-row"><div>#'+i.intent_id+' '+pill(i.status)+' v'+i.version+'</div><div>'+esc(i.raw_text)+'</div></div>').join(""):'<p class="oi-muted">—</p>';
}
function renderAll(){renderCtx();renderInter();renderPreview();renderHistory();renderReqs();renderIntents()}
async function refreshLists(){
 if(!canSubmit()){S.hist=null;S.reqs=[];S.intents=[];return}
 const [h,q,i]=await Promise.all([S.api.history(S.biz),S.api.requirements(S.biz),S.api.intents(S.biz)]);
 S.hist=h;S.reqs=q.items;S.intents=i.items;
}
async function loadBusiness(){
 S.ctx=await S.api.context(S.biz);fill();await refreshLists();
}
/* ---------- guidance ---------- */
async function showGuide(key){
 const g=await S.api.guidance(S.biz,key),c=g.content,p=g.effective_permission;
 const row=(k,lab)=>'<dt>'+esc(lab)+'</dt><dd>'+esc(L(c[k]))+'</dd>';
 $("oi-guide").innerHTML='<h3 id="oi-guide-title">'+esc(L(c.title))+'</h3><dl>'+row("what",S.lang==="bn"?"কী":"What")+row("why",S.lang==="bn"?"কেন":"Why")+row("when",S.lang==="bn"?"কখন":"When")+
  row("default",S.lang==="bn"?"ডিফল্ট":"Default")+row("exception",S.lang==="bn"?"ব্যতিক্রম":"Exception")+row("consequence",S.lang==="bn"?"পরিণতি":"Consequence")+
  row("data_formula_units",S.lang==="bn"?"ডেটা / সূত্র / একক":"Data / formula / units")+row("linked_report",S.lang==="bn"?"সংশ্লিষ্ট রিপোর্ট":"Linked report")+
  '<dt>'+esc(S.lang==="bn"?"আপনার কার্যকর অনুমতি":"Your effective permission")+'</dt><dd id="oi-guide-perm">'+esc(p.role)+' · submit='+esc(p.can_submit)+' · approve/publish='+esc(p.can_approve_publish)+'</dd>'+
  (g.current_setting?'<dt>'+esc(S.lang==="bn"?"বর্তমান মান":"Current value")+'</dt><dd>v'+esc(g.current_setting.version)+' '+esc(JSON.stringify(g.current_setting.params))+'</dd>':"")+'</dl>';
 return"";
}
function onClick(ev){
 const b=ev.target.closest("button");if(!b)return;
 if(b.dataset.guide)return void run("…",()=>showGuide(b.dataset.guide));
 if(b.dataset.ex!==undefined){$("oi-text").value=EXAMPLES[Number(b.dataset.ex)][S.lang];return void interpret()}
 if(b.id==="oi-saveprev")return void run(S.lang==="bn"?"সংরক্ষণ":"Saving",saveAndPreview);
 if(b.id==="oi-saveeng")return void run(S.lang==="bn"?"সংরক্ষণ":"Saving",saveEng);
 if(b.id==="oi-rerun")return void run("Preview",async()=>{const c=S.cur;if(!c)return;const p=await S.api.preview(c.intent_id,c.version,readSample());S.cur.hash=p.preview_hash;S.cur.status="PREVIEWED";S.preview=p.preview;renderAll();return"Preview refreshed — nothing applied"});
 if(["oi-validate","oi-approve","oi-publish","oi-reject"].includes(b.id))return void run(b.id.slice(3),()=>step(b.id.slice(3)));
 if(b.dataset.rollback)return void run("Rollback",async()=>{
  const why=($("oi-reason")||{}).value||(S.lang==="bn"?"মালিকের রোলব্যাক":"Owner rollback");
  const r=await S.api.rollback(S.biz,b.dataset.rollback,Number(b.dataset.to),Number(b.dataset.active),why.length>=5?why:why+"     ");await refreshLists();renderAll();
  return(S.lang==="bn"?"রোলব্যাক সম্পন্ন · নতুন সংস্করণ ":"Rolled back · new version ")+r.setting_version});
}
async function boot(){
 try{
  if(!A||!E||!window.supabase||!window.BOS_CONFIG)throw Object.assign(new Error("Supabase client/config not available"),{code:"SIGNED_SUPABASE_CLIENT_REQUIRED"});
  const client=window.supabase.createClient(window.BOS_CONFIG.url,window.BOS_CONFIG.key);
  S.api=A.create({client,engine:E});
  const bs=await S.api.businesses();S.businesses=bs.items;
  if(!S.businesses.length)throw Object.assign(new Error("No business visible to this signed user"),{code:"NO_BUSINESS"});
  const q=Number(new URLSearchParams(location.search).get("biz"));
  S.biz=(S.businesses.find(b=>b.business_id===q)||S.businesses[0]).business_id;
  shell();await loadBusiness();renderAll();status(S.lang==="bn"?"প্রেক্ষাপট লোড হয়েছে":"Context loaded");
 }catch(e){root.innerHTML='<div class="oi-safety" role="alert" id="oi-fatal">'+esc(fmtErr(e))+'</div>'}
}
boot();
})();
