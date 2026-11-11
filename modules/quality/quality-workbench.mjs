import {createQualityDemo,applyQualityDemo,visibleLots,visibleBusinesses,
 DEMO_ACTORS,DEMO_BUSINESSES,totalUnits,isExpired,demoFefo,DEMO_LABELS} from "./quality-demo.mjs";
// C10-A058: in-memory fixture ONLY. This client never connects to production, Auth or stock.
const find=id=>document.getElementById(id);
const el=(tag,value,cls)=>{const x=document.createElement(tag);if(value!==undefined)x.textContent=String(value);if(cls)x.className=cls;return x;};
const add=(p,...children)=>{for(const c of children)if(c)p.append(c);return p;};
const btn=(label,action,id)=>{const b=el("button",label);b.type="button";b.dataset.action=action;if(id!==undefined)b.dataset.id=String(id);return b;};
const names={
 bn:{overview:"সারসংক্ষেপ",lots:"ব্যাচ ও QC",trace:"ট্রেসিং",recalls:"রিকল",integrity:"সঙ্গতি পরীক্ষা",
 sub:"সিনথেটিক ডেটায় QC, মেয়াদ, শাখা স্টক ও রিকল প্রক্রিয়া অনুশীলন করুন।",
 register:"নতুন ব্যাচ",inspect:"QC যাচাই",release:"রিলিজ",hold:"হোল্ড",transfer:"স্থানান্তর",
 issue:"ইস্যু",recall:"রিকল",dispose:"নষ্ট/ডিসপোজ",close:"রিকল বন্ধ",no:"অনুমোদিত ব্যাচ নেই"},
 en:{overview:"Overview",lots:"Lots & QC",trace:"Traceability",recalls:"Recalls",integrity:"Integrity",
 sub:"Practice inspection, expiry, transfers and recall processes with fictitious data.",
 register:"New lot",inspect:"Inspect QC",release:"Release",hold:"Hold",transfer:"Transfer",
 issue:"Issue",recall:"Recall",dispose:"Dispose",close:"Close recall",no:"No authorized lots"}};
let state=createQualityDemo(),who="owner",bizId=101,page="overview",lang="bn",serial=1,modal=null;
const tr=k=>names[lang][k]||k;
const activeBusiness=()=>DEMO_BUSINESSES.find(b=>b.id===bizId);
const visible=()=>visibleLots(state,who,bizId);
const actor=()=>DEMO_ACTORS[who];
const fmt=q=>Number(q||0).toLocaleString(undefined,{maximumFractionDigits:3});
function message(txt,bad=false){const x=find("notice");x.hidden=false;x.textContent=txt;x.className="quality-notice"+(bad?"":" ok");}
function businessOptions(){
 const selector=find("business"),businesses=visibleBusinesses(who);
 selector.replaceChildren();
 for(const b of businesses){const o=el("option",b.name);o.value=String(b.id);selector.append(o);}
 if(!businesses.some(x=>x.id===bizId))bizId=businesses[0]?.id||0;
 selector.value=String(bizId||"");
}
function card(title,value,note){
 const c=el("div",undefined,"card quality-stat");
 add(c,el("h3",title),el("div",value,"num"),el("small",note));return c;
}
function metrics(){
 const ls=visible(),g=el("div",undefined,"grid");
 add(g,card("Tracked lots",ls.length,"Current demo business"),
  card("Units",fmt(ls.reduce((n,l)=>n+totalUnits(l),0)),"Fictitious quantities"),
  card("Released",ls.filter(l=>l.status==="released"&&!isExpired(l)).length,"QC-approved"),
  card("Held / recalled / expired",ls.filter(l=>l.status!=="released"||isExpired(l)).length,"Not sellable"));
 return g;
}
function table(limit=100,query=""){
 const ls=visible().filter(l=>(l.code+" "+l.item+" "+l.status).toLowerCase().includes(query.toLowerCase())).slice(0,limit);
 if(!ls.length)return el("div",tr("no"),"quality-empty");
 const div=el("div",undefined,"tablewrap"),table=el("table",undefined,"quality-table"),thead=el("thead"),header=el("tr");
 for(const name of ["Lot","Item","Expiry","Status","Units","Demo actions"])header.append(el("th",name));
 thead.append(header);const body=el("tbody");
 for(const l of ls){
  const row=el("tr");for(const value of [l.code,l.item,l.expiry||"—",
   DEMO_LABELS[l.status]+(isExpired(l)?" · expired":""),fmt(totalUnits(l))])row.append(el("td",value));
  const cell=el("td"),actions=el("div",undefined,"quality-actions");
  add(actions,btn(tr("inspect"),"inspect",l.id));
  if(actor().role==="owner")actions.append(btn(tr(l.status==="released"?"hold":"release"),l.status==="released"?"hold":"release",l.id));
  actions.append(btn(tr("transfer"),"transfer",l.id));
  if(l.status==="released")actions.append(btn(tr("issue"),"issue",l.id));
  if(actor().role==="owner")actions.append(btn(tr("recall"),"recall",l.id));
  if(actor().role==="owner"&&(l.status!=="released"||isExpired(l)))actions.append(btn(tr("dispose"),"dispose",l.id));
  add(cell,actions);row.append(cell);body.append(row);
 }
 table.append(thead,body);div.append(table);return div;
}
function group(title){
 const c=el("div",undefined,"quality-card");c.append(el("h3",title));return c;
}
function overview(){
 const root=el("div");root.append(metrics());
 const layout=el("div",undefined,"quality-layout"),left=el("div",undefined,"quality-stack"),right=el("div",undefined,"quality-stack");
 const lots=group("Batch / lot status");lots.append(table(5));
 lots.append(el("p","All actions in this workshop are volatile and will reset on refresh.","note"));
 const audit=group("Recent demo events");
 for(const e of state.audit.filter(x=>x.businessId===bizId).slice(-6).reverse())audit.append(el("p",e.operation+" • lot "+(e.lotId||"—")+" • "+e.actor+" • #"+e.seq));
 if(!audit.children.length||audit.children.length===1)audit.append(el("p","No demo operations yet."));
 add(left,lots,audit);
 const quality=group("Picking guidance · FEFO");
 quality.append(el("p","Only QC-released, unexpired lots are suggested for picking."));
 const first=visible()[0],site=activeBusiness()?.sites[0];
 const plan=first&&site?demoFefo(state,bizId,first.item,site.id,12):[];
 for(const x of plan)quality.append(el("p",x.code+" · "+fmt(x.suggested)+" / "+fmt(x.available),"quality-code"));
 if(!plan.length)quality.append(el("p","No qualifying lots found."));
 const gate=group("Operational controls"),ul=el("ul",undefined,"list");
 for(const item of ["Quarantine before QC release","Reject expired or recalled issue",
 "Idempotent commands and bounded quantities","Trace parent batches into finished products",
 "Dispose recalled stock before closure","Real permissions remain server-side"])
 ul.append(el("li",item));
 gate.append(ul);add(right,quality,gate);add(layout,left,right);root.append(layout);return root;
}
function lotView(){
 const root=el("div"),filter=el("div",undefined,"quality-filter"),label=el("label","Search lot / item / status");
 label.htmlFor="lot-search";const search=el("input");search.id="lot-search";search.type="search";search.placeholder="LOT, product, status";
 const results=el("div");results.id="lot-results";results.append(table());
 search.addEventListener("input",()=>results.replaceChildren(table(100,search.value)));
 add(filter,label,search);add(root,filter,results);return root;
}
function traceView(){
 const root=el("div",undefined,"quality-layout"),left=group("Batch genealogy"),right=group("Downstream product recall");
 const graph=el("ul",undefined,"quality-trace");
 let count=0;
 for(const l of state.links){
  const p=visible().find(x=>x.id===l.from),c=visible().find(x=>x.id===l.to);
  if(!p||!c)continue;
  graph.append(el("li",p.code+"  →  "+c.code+"  ("+p.item+" → "+c.item+")"));count++;
 }
 if(!count)graph.append(el("li","No linked source/finished lots in this business."));
 left.append(graph);right.append(el("p","A recall of a parent lot also blocks every reachable child lot."));
 if(actor().role==="owner"&&visible().length>1)right.append(btn("Link source → child","link",visible()[0].id));
 add(root,left,right);return root;
}
function recallView(){
 const root=el("div",undefined,"quality-layout"),left=group("Recall cases"),right=group("Containment guidance");
 const data=state.recalls.filter(x=>x.businessId===bizId);
 for(const r of data){const item=group("Recall #"+r.id+" · "+r.severity);
 add(item,el("p","Status: "+r.status),el("p",r.reason),el("p","Affected lots: "+r.affected.join(", ")));
 if(r.status==="active"&&actor().role==="owner")item.append(btn(tr("close"),"close",r.id));
 left.append(item);}
 if(!data.length)left.append(el("p","No demo recalls created yet."));
 const list=el("ol",undefined,"list");
 for(const item of ["Identify suspect lot","Follow its downstream genealogy",
 "Prevent sale or further issue","Account for every affected location",
 "Dispose / physically recover stock","Close only at zero remaining affected stock"])list.append(el("li",item));
 right.append(list,el("p","Customer notifications or authorities are NOT connected in this demo."));
 add(root,left,right);return root;
}
function integrityView(){
 const root=el("div");root.append(metrics());
 const layout=el("div",undefined,"quality-layout"),left=group("Demo inventory checks"),right=group("Release boundary");
 const good=visible().every(l=>Object.values(l.stock).every(q=>Number.isFinite(q)&&q>=0));
 add(left,el("p","No negative lot balances: "+(good?"PASS":"FAIL")),
 el("p","Audit events: "+state.audit.filter(x=>x.businessId===bizId).length),
 el("p","Actual signed Supabase Auth/RLS integration: NOT CONNECTED"),
 el("p","Canonical stock reconciliation runs separately inside disposable PG17 CI."));
 right.append(el("p","This screen checks synthetic in-memory state only. Successful SQL CI cannot certify live IMG-ERP-SG operations."));
 const a=el("a","Read Draft PR #73");a.href="https://github.com/mistybari99/CORE-10-CENTRAL/pull/73";a.target="_blank";a.rel="noopener noreferrer";right.append(a);
 add(layout,left,right);root.append(layout);return root;
}
function render(){
 businessOptions();find("heading").textContent=tr(page);find("subtitle").textContent=tr("sub");
 find("new-lot").hidden=!bizId||!["owner","reviewer"].includes(actor().role);
 for(const b of document.querySelectorAll("#quality-nav button[data-view]"))
 b.setAttribute("aria-current",b.dataset.view===page?"page":"false");
 const contents={overview, lots:lotView, trace:traceView, recalls:recallView, integrity:integrityView};
 find("quality-view").replaceChildren(!bizId?el("div",tr("no"),"quality-empty"):contents[page]());
}
function field(name,title,type,value,opts){
 const label=el("label",title),input=el("input");input.name=name;input.type=type||"text";
 input.value=value??"";if(opts){if(opts.min)input.min=opts.min;if(opts.max)input.max=opts.max;if(opts.step)input.step=opts.step;
 if(opts.required)input.required=true;}
 label.append(input);find("modal-fields").append(label);
}
function selection(name,title,options){
 const label=el("label",title),select=el("select");select.name=name;
 for(const o of options){const option=el("option",o.label);option.value=String(o.value);select.append(option);}
 label.append(select);find("modal-fields").append(label);
}
function sites(lot){
 const b=activeBusiness();return b?b.sites.filter(s=>!lot||Object.hasOwn(lot.stock,s.id))
 .map(s=>({value:s.id,label:s.name+(lot?" • "+fmt(lot.stock[s.id]):"")})):[];
}
function openForm(action,id){
 const lot=state.lots.find(l=>l.id===id&&l.businessId===bizId);
 if(!lot&&action!=="register"&&action!=="close")return message("Lot not found",true);
 find("modal-fields").replaceChildren();
 find("modal-title").textContent=tr(action)+(lot?" · "+lot.code:"");
 find("modal-help").textContent="SIMULATED ONLY · applying will not change real business data.";
 if(action==="register"){field("code","Unique lot code","text","DEMO-"+String(Date.now()).slice(-6),{required:true});
 field("item","Item / product","text","Demo product",{required:true});field("quantity","Received quantity","number",10,{min:"0.001",step:"0.001",required:true});
 field("expiry","Expiry date","date","2026-11-25");selection("siteId","Receiving site",sites());}
 else if(action==="inspect")selection("pass","Inspection result",[{value:"true",label:"PASS • all checks satisfied"},{value:"false",label:"FAIL • keep in quarantine"}]);
 else if(["transfer"].includes(action)){selection("fromSiteId","From site",sites(lot));
 selection("toSiteId","To site",sites());field("quantity","Quantity","number",1,{min:"0.001",step:"0.001",required:true});}
 else if(["issue","dispose"].includes(action)){selection("siteId","Site",sites(lot));
 field("quantity","Quantity","number",1,{min:"0.001",step:"0.001",required:true});}
 else if(action==="recall"){selection("severity","Severity",[{value:"internal",label:"Internal"},{value:"customer",label:"Customer"},{value:"critical",label:"Critical"}]);
 field("reason","Recall reason","text","Fictitious quality concern",{required:true});}
 else if(action==="link")selection("childLotId","Child lot",visible().filter(l=>l.id!==id).map(l=>({value:l.id,label:l.code})));
 else find("modal-fields").append(el("p",action==="close"?"Every affected lot must have zero quantity.":"QC and owner permissions apply."));
 modal={action,id};find("quality-dialog").showModal();
}
function submit(e){
 e.preventDefault();if(!modal)return;
 const data=Object.fromEntries(new FormData(find("quality-form")).entries()),id=modal.id,type=modal.action;
 const out={key:"ui-"+Date.now()+"-"+(++serial),businessId:bizId};
 let operation;
 if(type==="register")operation={...out,type,code:data.code,item:data.item,quantity:Number(data.quantity),
  siteId:Number(data.siteId),expiry:data.expiry||null};
 else if(type==="inspect")operation={...out,type,lotId:id,pass:data.pass==="true"};
 else if(type==="release"||type==="hold")operation={...out,type:"decision",lotId:id,decision:type};
 else if(type==="transfer")operation={...out,type,lotId:id,fromSiteId:Number(data.fromSiteId),
  toSiteId:Number(data.toSiteId),quantity:Number(data.quantity)};
 else if(type==="issue"||type==="dispose")operation={...out,type,lotId:id,siteId:Number(data.siteId),quantity:Number(data.quantity)};
 else if(type==="recall")operation={...out,type,lotId:id,severity:data.severity,reason:data.reason};
 else if(type==="close")operation={...out,type:"close_recall",recallId:id};
 else if(type==="link")operation={...out,type,lotId:id,childLotId:Number(data.childLotId)};
 try{const applied=applyQualityDemo(state,who,operation);state=applied.state;
 find("quality-dialog").close();modal=null;message("DEMO UPDATED · "+type);render();
 }catch(err){message(err?.message||String(err),true);}
}
find("actor").replaceChildren();
for(const [key,a] of Object.entries(DEMO_ACTORS)){const opt=el("option",a.name);opt.value=key;find("actor").append(opt);}
find("actor").value=who;
find("actor").addEventListener("change",e=>{who=e.target.value;render();});
find("business").addEventListener("change",e=>{bizId=Number(e.target.value);render();});
find("language").addEventListener("change",e=>{lang=e.target.value;render();});
find("quality-nav").addEventListener("click",e=>{const b=e.target.closest("button[data-view]");
 if(b){page=b.dataset.view;render();}});
find("quality-view").addEventListener("click",e=>{const b=e.target.closest("button[data-action]");
 if(b)openForm(b.dataset.action,Number(b.dataset.id));});
find("new-lot").addEventListener("click",()=>openForm("register"));
find("reset").addEventListener("click",()=>{state=createQualityDemo();find("notice").hidden=true;render();});
find("cancel-action").addEventListener("click",()=>{find("quality-dialog").close();modal=null;});
find("quality-form").addEventListener("submit",submit);
render();
