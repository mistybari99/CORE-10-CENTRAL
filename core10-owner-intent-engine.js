/* C10-A052 Owner Intent rule engine (client side, deterministic, NO network, NO LLM, NO eval).
 * Natural language (Bangla/English) -> structured interpretation. The SERVER re-validates everything against the
 * certified capability allowlist; this parser can only PROPOSE. Unsupported asks become engineering requirements,
 * never executable features. evaluate()/validateParams() mirror the SQL for instant UX only (SQL is authoritative).
 */
(function(root,factory){"use strict";
 const api=factory();
 if(typeof module==="object"&&module.exports)module.exports=api;
 if(root)root.CORE10_INTENT_ENGINE=api;
})(typeof window!=="undefined"?window:globalThis,function(){
 "use strict";
 const PARSER_VERSION="owner-intent-rules-v1";
 const OUTCOMES=["allow","warn","block","approval_required"];
 const CAPABILITIES={
  wastage_threshold:{route:"A052_ADVISORY",module:"production",title:{en:"Wastage threshold advisory",bn:"অপচয় সীমা সতর্কতা"},
   guidance:"inventory.wastage_threshold",
   params:[{name:"threshold_pct",type:"number",min:0.0001,max:100,label:{en:"Wastage limit (%)",bn:"অপচয় সীমা (%)"}},
    {name:"outcome",type:"select",options:["warn","approval_required"],label:{en:"When exceeded",bn:"সীমা ছাড়ালে"}},
    {name:"unit",type:"select",options:["kg","pcs","l"],label:{en:"Quantity unit",bn:"পরিমাণের একক"}},
    {name:"item_group",type:"text",optional:true,label:{en:"Item group (optional)",bn:"আইটেম গ্রুপ (ঐচ্ছিক)"}}],
   sample:{produced_qty:50,wasted_qty:3},
   sampleFields:[{name:"produced_qty",label:{en:"Produced quantity",bn:"উৎপাদিত পরিমাণ"}},{name:"wasted_qty",label:{en:"Wasted quantity",bn:"নষ্ট পরিমাণ"}}]},
  pack_discount_margin:{route:"A052_ADVISORY",module:"costing",title:{en:"Pack-size discount margin check",bn:"প্যাক সাইজ ডিসকাউন্ট মার্জিন যাচাই"},
   guidance:"pricing.pack_discount_margin",
   params:[{name:"pack_litres",type:"number",min:0.001,max:1000,label:{en:"Pack size (litres)",bn:"প্যাক সাইজ (লিটার)"}},
    {name:"min_margin_pct",type:"number",min:0,max:99.99,label:{en:"Minimum margin (%)",bn:"ন্যূনতম মার্জিন (%)"}},
    {name:"outcome",type:"select",options:["warn","approval_required","block"],label:{en:"When below",bn:"নিচে গেলে"}},
    {name:"currency",type:"text",label:{en:"Currency (3 letters)",bn:"মুদ্রা (৩ অক্ষর)"}}],
   sample:{price_per_pack:3200,cost_per_litre:600,discount_pct:8},
   sampleFields:[{name:"price_per_pack",label:{en:"Price per pack",bn:"প্যাকের দাম"}},{name:"cost_per_litre",label:{en:"Cost per litre",bn:"লিটার-প্রতি খরচ"}},
    {name:"discount_pct",label:{en:"Discount (%)",bn:"ছাড় (%)"}}]},
  low_stock_alert:{route:"A045_ENGINE",module:"stock",title:{en:"Low stock alert",bn:"কম স্টক সতর্কতা"},guidance:"inventory.low_stock_alert",
   params:[{name:"threshold",type:"number",min:0,max:1e9,label:{en:"Stock below",bn:"স্টক এর নিচে"}},
    {name:"outcome",type:"select",options:OUTCOMES,label:{en:"Outcome",bn:"ফলাফল"}}],
   sample:{on_hand:8},sampleFields:[{name:"on_hand",label:{en:"On hand",bn:"মজুত"}}]},
  margin_floor_approval:{route:"A045_ENGINE",module:"costing",title:{en:"Margin floor needs approval",bn:"ন্যূনতম মার্জিনের নিচে অনুমোদন"},
   guidance:"pricing.margin_floor_approval",
   params:[{name:"threshold",type:"number",min:0,max:99.99,label:{en:"Margin floor (%)",bn:"ন্যূনতম মার্জিন (%)"}},
    {name:"outcome",type:"select",options:OUTCOMES,label:{en:"Outcome",bn:"ফলাফল"}}],
   sample:{margin_pct:8},sampleFields:[{name:"margin_pct",label:{en:"Margin (%)",bn:"মার্জিন (%)"}}]},
  order_total_approval:{route:"A045_ENGINE",module:"purchase",title:{en:"Large order/materials approval",bn:"বড় অর্ডার/মালামাল অনুমোদন"},
   guidance:"purchase.order_total_approval",
   params:[{name:"threshold",type:"number",min:0.01,max:1e9,label:{en:"Order total at or above",bn:"অর্ডার মোট এর সমান/বেশি"}},
    {name:"outcome",type:"select",options:OUTCOMES,label:{en:"Outcome",bn:"ফলাফল"}},
    {name:"currency",type:"text",label:{en:"Currency (3 letters)",bn:"মুদ্রা (৩ অক্ষর)"}}],
   sample:{order_total:600000},sampleFields:[{name:"order_total",label:{en:"Order total",bn:"অর্ডার মোট"}}]}
 };
 const UNITS=["kg","pcs","l"];
 const isNum=(v)=>typeof v==="number"&&Number.isFinite(v);
 /* ---- validation mirror ---- */
 function validateParams(cap,p){
  const errors=[],spec=CAPABILITIES[cap];
  if(!spec)return{ok:false,errors:["unknown capability"]};
  if(!p||typeof p!=="object"||Array.isArray(p))return{ok:false,errors:["params must be an object"]};
  const names=spec.params.map(x=>x.name);
  for(const k of Object.keys(p))if(!names.includes(k))errors.push("unknown parameter: "+k);
  for(const s of spec.params){
   const v=p[s.name];
   if(v===undefined){if(!s.optional)errors.push("missing: "+s.name);continue}
   if(s.type==="number"&&(!isNum(v)||v<s.min||v>s.max))errors.push(s.name+" must be a number between "+s.min+" and "+s.max);
   if(s.type==="select"&&!s.options.includes(v))errors.push(s.name+" must be one of "+s.options.join(", "));
   if(s.name==="currency"&&!/^[A-Z]{3}$/.test(String(v)))errors.push("currency must be 3 capital letters");
   if(s.name==="item_group"&&!/^[A-Za-z0-9 _-]{0,40}$/.test(String(v)))errors.push("item_group must be plain text up to 40 characters");
  }
  return{ok:errors.length===0,errors};
 }
 /* ---- evaluation mirror (advisory) ---- */
 const r4=(x)=>Number(x.toFixed(4));
 function evaluate(cap,p,inp){
  const v=validateParams(cap,p);if(!v.ok)throw new Error("invalid_params");
  const pos=(k,lo,hi)=>{const x=inp&&inp[k];if(!isNum(x)||x<lo||x>hi)throw new Error("invalid_input");return x};
  const base={capability_key:cap,advisory:true,mutates:false,canAuthorizeOperation:false,inputs:inp};
  if(cap==="wastage_threshold"){
   const a=pos("produced_qty",0.0001,1e9),b=pos("wasted_qty",0,1e9);if(b>a)throw new Error("invalid_input");
   const pct=r4(b/a*100),hit=pct>p.threshold_pct;
   return Object.assign(base,{matched:hit,outcome:hit?p.outcome:"allow",computed:{wastage_pct:pct}});
  }
  if(cap==="pack_discount_margin"){
   const a=pos("price_per_pack",0.01,1e9),b=pos("cost_per_litre",0,1e9),c=pos("discount_pct",0,99.99);
   const net=a*(1-c/100),cost=b*p.pack_litres,mg=r4((net-cost)/net*100);
   const maxd=r4(Math.max(0,(1-cost/(a*(1-p.min_margin_pct/100)))*100));
   const hit=mg<p.min_margin_pct;
   return Object.assign(base,{matched:hit,outcome:hit?p.outcome:"allow",computed:{net_price:r4(net),pack_cost:r4(cost),margin_pct:mg,max_discount_pct:maxd}});
  }
  const f={low_stock_alert:"on_hand",margin_floor_approval:"margin_pct",order_total_approval:"order_total"}[cap];
  const x=pos(f,-1e9,1e9),hit=cap==="order_total_approval"?x>=p.threshold:x<p.threshold;
  return Object.assign(base,{matched:hit,outcome:hit?p.outcome:"allow",computed:{[f]:x}});
 }
 /* ---- text normalisation ---- */
 const BN_DIGITS="০১২৩৪৫৬৭৮৯";
 function normalize(text){
  let s=String(text==null?"":text).normalize("NFC").replace(/[০-৯]/g,d=>String(BN_DIGITS.indexOf(d)));
  s=s.replace(/[​-‍﻿]/g,"").replace(/[ \t\r\n]+/g," ").trim().toLowerCase();
  return s;
 }
 function detectLocale(text){
  const bn=(String(text).match(/[ঀ-৿]/g)||[]).length;
  const la=(String(text).match(/[A-Za-z]/g)||[]).length;
  const other=(String(text).match(/[\p{L}]/gu)||[]).length-bn-la;
  if(bn+la===0||other>bn+la)return"unknown";
  const r=bn/(bn+la);
  return r>0.8?"bn":r<0.2?"en":"mixed";
 }
 /* ---- token extraction ---- */
 const MULT=[[/^(lakh|lac|lakhs|লাখ|লক্ষ)/,1e5],[/^(crore|কোটি)/,1e7],[/^(hajar|thousand|হাজার)/,1e3]];
 const UNIT_RULES=[[/^(%|percent|pct|পার্সেন্ট|পারসেন্ট|শতাংশ)/,"pct"],[/^(ml|মিলি|মিলিলিটার)/,"ml"],
  [/^(l|ltr|ltrs|liter|litre|liters|litres|লিটার|লিটারের|লি\.?)(?![a-z])/,"l"],[/^(kg|kgs|কেজি|কিজি|কে\.জি)(?![a-z])/,"kg"],
  [/^(gm|gms|gram|grams|g|গ্রাম)(?![a-z])/,"g"],[/^(pcs|pc|piece|pieces|পিস)(?![a-z])/,"pcs"],
  [/^(tk|taka|bdt|টাকা|৳)/,"money"],[/^(usd|dollar|dollars|\$)/,"usd"]];
 function tokens(s){
  const out=[],re=/(৳|\$)?\s*(\d[\d,]*(?:\.\d+)?|\.\d+)/g;let m;
  while((m=re.exec(s))){
   let raw=m[2].replace(/,/g,"");let val=Number(raw);if(!Number.isFinite(val))continue;
   let end=re.lastIndex,rest=s.slice(end).replace(/^\s{0,2}/,"");let unit=m[1]==="৳"?"money":m[1]==="$"?"usd":null;
   for(const [rx,mult] of MULT){const mm=rest.match(rx);if(mm){val*=mult;end+=s.slice(end).length-rest.length+mm[0].length;rest=s.slice(end).replace(/^\s{0,2}/,"");break}}
   for(const [rx,u] of UNIT_RULES){const mm=rest.match(rx);if(mm){unit=unit||u;end+=s.slice(end).length-rest.length+mm[0].length;break}}
   out.push({value:val,unit,start:m.index,end});
   re.lastIndex=Math.max(re.lastIndex,end);
  }
  return out;
 }
 const has=(s,list)=>list.some(w=>w instanceof RegExp?w.test(s):s.includes(w));
 const nearest=(toks,s,words)=>{ // token nearest to any keyword occurrence
  let best=null,bd=1e9;
  for(const w of words){const re=w instanceof RegExp?new RegExp(w.source,"g"):new RegExp(w.replace(/[.*+?^${}()|[\]\\]/g,"\\$&"),"g");let m;
   while((m=re.exec(s))){for(const t of toks){const d=t.start>=m.index?t.start-(m.index+m[0].length):m.index-t.end;if(d<bd){bd=d;best=t}}}}
  return bd<=40?best:null;
 };
 const KW={
  waste:["wastage","waste","spoil","নষ্ট","অপচয়","ওয়েস্টেজ","নস্ট"],
  discount:[/discount/,/ডিসকাউন্ট|ডিস্কাউন্ট/,/ছাড়(?!ালে|িয়ে|া)/],
  margin:["margin","মার্জিন","profit","লাভ"],
  packs:[/\bpack/,/প্যাক/,/\blit(re|er)/,/\bltr/,/লিটার/],
  approval:["approval","approve","অনুমোদন","এপ্রুভ","অ্যাপ্রুভ","অনুমতি লাগ"],
  order:[/\border/,/purchase/,/\bpo\b/,/material/,/ক্রয়/,/অর্ডার/,/মালামাল/,/কেনা/],
  below:[/below/,/under\b/,/less than/,/lower than/,/কমে/,/কম(?![\u0980-\u09FF])/,/নিচে|নীচে/],
  above:[/above/,/\bover\b/,/exceed/,/more than/,/at least/,/বেশি/,/ছাড়ালে|ছাড়িয়ে/,/উপরে/,/অতিক্রম/,/or more/],
  stock:["stock","স্টক","মজুত","inventory"],
  block:[/\bblock\b/,/আটকা/,/বন্ধ করো|বন্ধ কর/],
  sweets:[/sweet/,/মিষ্টি|মিষ্টান্ন|রসগোল্লা|সন্দেশ/],bakery:[/bakery|cake/,/বেকারি|কেক/]
 };
 const ENG=[
  ["notification","notification_v1",[/\bsms\b|whatsapp|\be-?mail\b|\bpush\b|notification/,/এসএমএস|হোয়াটসঅ্যাপ|ইমেইল|ইমেল|নোটিফিকেশন|মেসেজ পাঠা/],
   {en:"Send notifications (SMS/WhatsApp/email)",bn:"নোটিফিকেশন পাঠানো (এসএমএস/হোয়াটসঅ্যাপ/ইমেইল)"},["notification_template","recipient_contact","delivery_log"],
   ["Owner can choose recipients and channel","Delivery is logged and idempotent","No message is sent without a certified handler and consent rule"]],
  ["integration","integration_v1",[/bkash|nagad|shopify|\bapi\b|webhook|integrat|connector/,/বিকাশ|নগদ|ইন্টিগ্রেশন|সংযোগ করো/],
   {en:"External integration",bn:"বাইরের সিস্টেমের সাথে সংযোগ"},["integration_connection","secret_reference","sync_log"],
   ["Credentials stored outside the database","Read/write scopes declared","Tenant-isolated sync log"]],
  ["automation","automation_v1",[/\bauto\b|automatic|auto-|every day|daily|schedule/,/স্বয়ংক্রিয়|অটো|প্রতিদিন/],
   {en:"Automation / scheduled action",bn:"স্বয়ংক্রিয় / নির্ধারিত কাজ"},["automation_rule","run_log"],
   ["Bounded, deterministic action list","Dry-run before enable","Owner can pause and audit every run"]],
  ["workflow","workflow_v1",[/two[- ]level|multi[- ]level|multi[- ]step|workflow|escalat|chain of/,/ওয়ার্কফ্লো|দুই ধাপ|দুই স্তর|ধাপে ধাপে/],
   {en:"Multi-step approval workflow",bn:"বহু-ধাপ অনুমোদন ওয়ার্কফ্লো"},["workflow_definition","approval_step","approver_assignment"],
   ["Each step names an existing role","No self-approval","Every transition audited"]],
  ["payroll_policy",null,[/salary|payroll|overtime|bonus|allowance|deduction/,/বেতন|ওভারটাইম|বোনাস|ভাতা/],
   {en:"Payroll / salary policy",bn:"বেতন নীতি"},["salary_policy","pay_period"],
   ["Handled by the workforce payroll governance package (A054), not this engine","No statutory rate is invented"]],
  ["tax_policy",null,[/\bvat\b|\btax\b|\bgst\b/,/ভ্যাট|ট্যাক্স/],
   {en:"Tax / VAT rule",bn:"ট্যাক্স / ভ্যাট নিয়ম"},["tax_rate","tax_jurisdiction"],
   ["Rates come from an Owner-approved source, never guessed","Rounding rules explicit"]]
 ];
 const REFUSE=[
  ["permission_grant",()=>false,{en:"Granting permissions or roles through a prompt",bn:"প্রম্পটের মাধ্যমে অনুমতি বা রোল দেওয়া"}],
  ["arbitrary_code",()=>false,{en:"Running custom code, SQL or scripts",bn:"নিজস্ব কোড, SQL বা স্ক্রিপ্ট চালানো"}],
  ["direct_posting",()=>false,{en:"Posting to ledger, stock or payments directly",bn:"সরাসরি লেজার, স্টক বা পেমেন্টে পোস্ট করা"}],
  ["destructive_change",()=>false,{en:"Deleting history, audit or records",bn:"ইতিহাস, অডিট বা রেকর্ড মুছে ফেলা"}]
 ];
 function refusal(s){
  const permW=/permission|\baccess\b|\badmin\b|\brole\b|অনুমতি|অ্যাক্সেস|এক্সেস|পারমিশন|এডমিন|অ্যাডমিন|রোল/;
  const grantW=/\bgive\b|\bgrant\b|\ballow\b|\bmake\b|\badd\b|দাও|দিন|দিয়ে|বানাও|বানান|খুলে/;
  if(permW.test(s)&&grantW.test(s)&&!has(s,KW.approval.slice(0,3).concat(["অনুমোদন"])))return"permission_grant";
  if(/\b(sql|javascript|js|script|eval|exec|code)\b|কোড|স্ক্রিপ্ট|drop table|delete from/.test(s))return"arbitrary_code";
  if((/ledger|journal|লেজার|জার্নাল/.test(s)&&/\bpost|পোস্ট/.test(s))||/send payment|pay now|transfer money|পেমেন্ট করো|টাকা পাঠাও|stock adjust|adjust stock|স্টক অ্যাডজাস্ট/.test(s))return"direct_posting";
  if(/(delete|erase|remove|মুছে|ডিলিট)/.test(s)&&/(history|audit|all|everything|ইতিহাস|অডিট|সব)/.test(s))return"destructive_change";
  return null;
 }
 const REQ_BASE=(raw)=>String(raw).slice(0,300);
 function engineering(s,raw,loc,secondary){
  for(const [cat,handler,pats,title,entities,accept] of ENG){
   if(pats.some(p=>p.test(s)))return mkEng(cat,handler,title,entities,accept,raw,loc);
  }
  if(/report|রিপোর্ট|প্রতিবেদন|dashboard|ড্যাশবোর্ড/.test(s)&&!secondary)
   return mkEng("report_handler","report_v1",{en:"Read-only report / dashboard",bn:"শুধু-পড়া রিপোর্ট / ড্যাশবোর্ড"},
    ["report_definition","source_query_contract"],["Read-only, tenant and business scoped","Columns, filters and units declared","CSV export is formula-injection safe","Totals reconcile to source records"],raw,loc);
  return null;
 }
 function mkEng(category,handler,title,entities,accept,raw,loc){
  return{category,a045_handler_id:handler,requirement:{title_en:title.en,title_bn:title.bn,capability_needed:category,
   data_entities:entities,acceptance_criteria:accept,blockers:[handler?"A045 handler "+handler+" is not certified/executable":"No handler exists in the certified registry"],
   raw_text:REQ_BASE(raw),locale:loc}};
 }
 function assumption(key,value,source,en,bn){return{key,value,source,editable:true,en,bn}}
 const OUT_BN={warn:"সতর্কতা",approval_required:"অনুমোদন প্রয়োজন",block:"ব্লক (পরামর্শ)",allow:"অনুমোদিত"};
 function outcomeFrom(s,def,assumptions){
  if(has(s,KW.block)&&def!=="warn_only")return"block";
  if(has(s,KW.approval))return"approval_required";
  assumptions.push(assumption("outcome",def,"default","Outcome defaults to "+def+".","ফলাফল ডিফল্ট: "+(OUT_BN[def]||def)+"।"));
  return def;
 }
 function currencyFrom(s,toks,assumptions){
  if(/\busd\b|dollar|\$/.test(s))return"USD";
  if(toks.some(t=>t.unit==="money")||/\btk\b|taka|bdt|টাকা|৳/.test(s))return"BDT";
  assumptions.push(assumption("currency","BDT","default","Currency not stated; BDT assumed (editable).","মুদ্রা বলা হয়নি; BDT ধরা হয়েছে (সম্পাদনাযোগ্য)।"));
  return"BDT";
 }
 /* ---- main entry ---- */
 function parse(text){
  const raw=String(text==null?"":text);
  const base={parser_version:PARSER_VERSION,params:{},assumptions:[],missing:[],questions:[],matched_terms:[]};
  const locale=detectLocale(raw);
  if(raw.trim().length<3||locale==="unknown"){
   return Object.assign(base,{locale:"unknown",support_status:"NEEDS_CLARIFICATION",capability_key:null,confidence:0,
    reason:"UNSUPPORTED_LOCALE_OR_EMPTY",
    questions:[{param:"text",en:"Please describe your rule in Bangla or English.",bn:"অনুগ্রহ করে বাংলা বা ইংরেজিতে আপনার নিয়মটি লিখুন।"}]});
  }
  const s=normalize(raw);base.locale=locale;
  const ref=refusal(s);
  if(ref){
   const t=REFUSE.find(x=>x[0]===ref)[2];
   return Object.assign(base,{support_status:"UNSUPPORTED",capability_key:null,confidence:0.9,matched_terms:[ref],
    unsupported:{category:ref,reason_en:t.en+" is not allowed through the Owner Intent engine.",reason_bn:t.bn+" Owner Intent ইঞ্জিনের মাধ্যমে অনুমোদিত নয়।",
     requirement:{title_en:t.en,title_bn:t.bn,capability_needed:ref,data_entities:[],acceptance_criteria:[],
      blockers:["Policy D049: permissions, code, ledger posting and destructive changes are never granted by prompt"],
      alternatives:["Use the existing role/permission screens with their own audit","Submit a configuration request the certified handlers support"],raw_text:REQ_BASE(raw),locale}}});
  }
  const toks=tokens(s);
  const eng=engineering(s,raw,locale,false);
  const isWaste=has(s,KW.waste),isDisc=has(s,KW.discount),isMargin=has(s,KW.margin),isPack=has(s,KW.packs);
  const isStock=has(s,KW.stock),isBelow=has(s,KW.below),isAbove=has(s,KW.above),isOrder=has(s,KW.order),isAppr=has(s,KW.approval);
  let cap=null;
  const actionEng=eng&&eng.category!=="report_handler";
  if(actionEng)cap=null;
  else if(isWaste)cap="wastage_threshold";
  else if(isDisc&&isMargin)cap="pack_discount_margin";
  else if(isMargin&&!isDisc)cap="margin_floor_approval";
  else if(isOrder&&isAbove)cap="order_total_approval";
  else if(isStock&&isBelow)cap="low_stock_alert";
  if(!cap){
   const e=eng||engineering(s,raw,locale,false);
   const fall=e||mkEng("unclassified",null,{en:"Unclassified business request",bn:"শ্রেণিবিহীন ব্যবসায়িক অনুরোধ"},[],
    ["Owner clarifies the entities, trigger, outcome and units","A certified handler is designed, built and tested"],raw,locale);
   return Object.assign(base,{support_status:"ENGINEERING_REQUIRED",capability_key:null,confidence:e?0.8:0.2,matched_terms:[fall.category],
    unsupported:{category:fall.category,a045_handler_id:fall.a045_handler_id,
     reason_en:"No certified handler can run this yet. It is stored as an engineering requirement and nothing executes.",
     reason_bn:"এখনো কোনো সার্টিফাইড হ্যান্ডলার এটি চালাতে পারে না। এটি ইঞ্জিনিয়ারিং রিকোয়ারমেন্ট হিসেবে জমা থাকবে; কিছুই চলবে না।",requirement:fall.requirement}});
  }
  base.capability_key=cap;base.matched_terms=[cap];
  const p=base.params,A=base.assumptions;
  const miss=(param,en,bn)=>{base.missing.push(param);base.questions.push({param,en,bn})};
  if(cap==="wastage_threshold"){
   const pt=toks.find(t=>t.unit==="pct");
   if(pt)p.threshold_pct=pt.value;else miss("threshold_pct","What wastage percentage should trigger the alert?","কত শতাংশ অপচয়ে সতর্কতা চান?");
   p.outcome=outcomeFrom(s,"warn",A);
   const ut=toks.find(t=>["kg","g","pcs","l","ml"].includes(t.unit));
   const u=ut?({g:"kg",ml:"l"}[ut.unit]||ut.unit):null;
   if(u)p.unit=u;else{p.unit="kg";A.push(assumption("unit","kg","default","Quantity unit not stated; kg assumed.","একক বলা হয়নি; কেজি ধরা হয়েছে।"))}
   if(has(s,KW.sweets))p.item_group="sweets";else if(has(s,KW.bakery))p.item_group="bakery";
  }else if(cap==="pack_discount_margin"){
   const lt=toks.find(t=>t.unit==="l"||t.unit==="ml");
   if(lt)p.pack_litres=lt.unit==="ml"?lt.value/1000:lt.value;else miss("pack_litres","What is the pack size in litres?","প্যাক কত লিটারের?");
   const pcts=toks.filter(t=>t.unit==="pct");
   const mt=nearest(pcts,s,KW.margin)||pcts.filter(t=>t!==nearest(pcts,s,KW.discount))[0]||null;
   if(mt)p.min_margin_pct=mt.value;else miss("min_margin_pct","What minimum margin percentage must be kept?","ন্যূনতম কত শতাংশ মার্জিন রাখতে হবে?");
   p.outcome=outcomeFrom(s,"warn",A);p.currency=currencyFrom(s,toks,A);
  }else if(cap==="margin_floor_approval"){
   const pcts=toks.filter(t=>t.unit==="pct"),mt=nearest(pcts,s,KW.margin)||pcts[0];
   if(mt)p.threshold=mt.value;else miss("threshold","Below what margin percentage?","কত শতাংশ মার্জিনের নিচে?");
   p.outcome=outcomeFrom(s,isAppr?"approval_required":"warn",A);
  }else if(cap==="order_total_approval"){
   const amt=toks.find(t=>t.unit==="money")||toks.find(t=>t.unit==null&&t.value>0);
   if(amt)p.threshold=amt.value;else miss("threshold","At what order amount?","কত টাকার অর্ডারে?");
   p.outcome=outcomeFrom(s,"approval_required",A);p.currency=currencyFrom(s,toks,A);
  }else if(cap==="low_stock_alert"){
   const q=toks.find(t=>t.unit!=="pct"&&t.unit!=="money"&&t.unit!=="usd");
   if(q)p.threshold=q.value;else miss("threshold","Below what stock quantity?","কত পরিমাণ স্টকের নিচে?");
   p.outcome=outcomeFrom(s,"warn",A);
  }
  const v=base.missing.length?{ok:true}:validateParams(cap,p);
  if(!v.ok){
   for(const e of v.errors){const k=e.split(/[ :]/)[0];if(!base.missing.includes(k)){base.missing.push(k);
    base.questions.push({param:k,en:"Please check this value: "+e,bn:"এই মানটি আবার দেখুন: "+e})}}
   for(const k of base.missing)delete p[k];
  }
  if(has(s,[/report/,/রিপোর্ট|প্রতিবেদন/])&&(eng&&eng.category==="report_handler"))
   A.push(assumption("report_not_built","NOT_BUILT","note","The report part is not built; only the threshold is configured. A separate engineering requirement is needed for the report.",
    "রিপোর্ট অংশ তৈরি হয়নি; শুধু সীমা কনফিগার হবে। রিপোর্টের জন্য আলাদা ইঞ্জিনিয়ারিং রিকোয়ারমেন্ট লাগবে।"));
  base.support_status=base.missing.length?"NEEDS_CLARIFICATION":"SUPPORTED";
  base.confidence=base.missing.length?0.55:(A.length>1?0.8:0.9);
  return base;
 }
 /* what the client sends to submit_owner_intent_v1 (server re-validates) */
 function toInterpretation(r){
  const o={parser_version:r.parser_version,locale:r.locale,support_status:r.support_status,capability_key:r.capability_key||null,
   params:r.params||{},missing:r.missing||[],assumptions:r.assumptions||[],questions:r.questions||[],confidence:r.confidence,matched_terms:r.matched_terms||[]};
  if(r.unsupported)o.unsupported=r.unsupported.a045_handler_id===undefined?Object.assign({},r.unsupported):Object.assign({},r.unsupported);
  if(o.unsupported){o.unsupported.a045_handler_id=o.unsupported.a045_handler_id||undefined;if(!o.unsupported.a045_handler_id)delete o.unsupported.a045_handler_id}
  return o;
 }
 return Object.freeze({PARSER_VERSION,CAPABILITIES,normalize,detectLocale,tokens,parse,toInterpretation,validateParams,evaluate});
});
