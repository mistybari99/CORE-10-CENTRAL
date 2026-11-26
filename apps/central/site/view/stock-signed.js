/* CORE10 signed inventory, staging only. All writes go to canonical Control-gated RPCs.
 * Never use legacy BOS_CONFIG, direct table writes, shadow quantities or service role.
 */
(function(win){
"use strict";
const d=win.document,root=d.getElementById("stock-root");
if(!root)return;
const target="https://rhrqhbyzrhaafynfhdaf.supabase.co";
const cfg=win.CORE10_CONTROL_CENTRE_CONFIG;
const lang=new URLSearchParams(win.location.search).get("lang")==="en"?"en":"bn";
d.documentElement.lang=lang;
const t=(bn,en)=>lang==="en"?en:bn;
const E=(tag,content)=>{const x=d.createElement(tag);if(content!=null)x.textContent=String(content);return x;};
const bad=(reason)=>{let e=new Error(reason);e.code=reason;throw e;};
const positive=v=>{const n=Number(v);if(!Number.isSafeInteger(n)||n<1)bad("INVALID_ID");return n;};
const qty=v=>{if(!/^\d{1,7}(?:\.\d{1,3})?$/.test(String(v))||Number(v)<=0||Number(v)>1000000)bad("INVALID_QUANTITY");return Number(v);};
const request=()=>{if(!win.crypto||!win.crypto.randomUUID)bad("SECURE_REQUEST_KEY_UNAVAILABLE");return "stock-"+win.crypto.randomUUID().replaceAll("-","");};
const text=(v)=>String(v==null?"":v).trim();
const permitted=["receive","issue","transfer","adjust_in","adjust_out"];
const state={client:null,business:0,locations:[],items:[],commands:[],busy:false,closed:false,epoch:0,actor:null,nextBefore:null,nextBalance:null,balances:[]};
function scope(){return {epoch:state.epoch,business:state.business,actor:state.actor};}
function current(x){return !state.closed&&x.epoch===state.epoch&&x.business===state.business&&x.actor===state.actor;}
function assertCurrent(x){if(!current(x))bad("STALE_SCOPE");}
function errorText(e){
 const code=String(e?.message||e?.code||"SERVER_ERROR");
 const messages={INV_SCOPE:["ব্যবসা বা সাইটে প্রবেশাধিকার নেই।","Business or site access denied."],INV_PERMISSION_DENIED:["এই কাজের অনুমতি নেই।","Operation not permitted."],INV_APPROVAL_REQUIRED:["আগে অনুমোদন নিতে হবে।","Approval is required."],INV_APPROVAL_ALREADY_REQUESTED:["অনুমোদন ইতিমধ্যে চাওয়া হয়েছে।","Approval already requested."],INV_CONFIRM_FIRST:["আগে নিশ্চিত করুন।","Confirm first."],STALE_SCOPE:["সেশন বা ব্যবসা বদলেছে।","Session or business changed."]};
 if(code.startsWith("CONTROL_DISABLED"))return t("Owner Control-এ বন্ধ রয়েছে।","Disabled in Owner Control.")+" ("+code+")";
 if(code.startsWith("CONTROL_LIMIT"))return t("Owner Control সীমা অতিক্রম করেছে।","Owner Control limit exceeded.")+" ("+code+")";
 return messages[code]?t(...messages[code])+" ("+code+")":code;
}
function purge(){state.epoch++;state.business=0;state.actor=null;state.locations=[];state.items=[];state.commands=[];state.balances=[];state.nextBefore=null;state.nextBalance=null;root.replaceChildren();}
function status(msg,error){let p=d.getElementById("st-status");if(p){p.textContent=msg;p.dataset.error=error?"true":"false";}}
function field(label,kind,id,required){
 const l=E("label"),n=E(kind==="select"?"select":"input");l.textContent=label;n.id=id;n.name=id;if(kind!=="select")n.type=kind;
 if(required)n.required=true;l.append(n);return l;
}
function button(label,fn){const b=E("button",label);b.type="button";b.addEventListener("click",fn);return b;}
async function rpc(name,args){
 if(!state.client)bad("SIGNED_CLIENT_REQUIRED");
 const snap=scope();
 const user=await state.client.auth.getUser();
 assertCurrent(snap);
 if(user.error||!user.data?.user?.id||user.data.user.id!==snap.actor)bad("SIGNED_SESSION_REQUIRED");
 const r=await state.client.schema("core10").rpc(name,args||{});
 const after=await state.client.auth.getUser();
 assertCurrent(snap);
 if(after.error||after.data?.user?.id!==snap.actor)bad("SIGNED_SESSION_REQUIRED");
 if(r.error)throw r.error;return r.data;
}
async function catalog(){
 const db=state.client.schema("core10");
 const snap=scope();
 const l=await db.from("stock_locations").select("id,business_id,site_id,code").eq("business_id",snap.business).limit(500);
 assertCurrent(snap);
 if(l.error)throw l.error;
 if((l.data||[]).some(x=>x.business_id!==snap.business))bad("INVALID_CATALOG_SCOPE");
 const items=[];let cursor=null;
 do{
  const page=await rpc("master_list_items_v1",{p_business:snap.business,p_search:null,p_status:null,p_category:null,p_limit:100,p_after_id:cursor});
  assertCurrent(snap);
  if(!page||!Array.isArray(page.rows)||page.rows.some(x=>!Number.isSafeInteger(x.id)||x.id<1||(cursor!==null&&x.id<=cursor)))bad("INVALID_ITEM_PAGE");
  items.push(...page.rows);
  const next=page.next_after_id??null;
  if(next!==null&&(!Number.isSafeInteger(next)||next<1||(cursor!==null&&next<=cursor)||next!==page.rows.at(-1)?.id))bad("INVALID_ITEM_CURSOR");
  cursor=next;
  if(items.length>=500&&cursor!==null)bad("ITEM_CATALOG_LIMIT_REQUIRES_SEARCH");
 }while(cursor!==null);
 assertCurrent(snap);state.locations=l.data||[];state.items=items;
}
function fill(select,rows,fmt){
 select.replaceChildren(E("option",t("প্রযোজ্য নয়","Not applicable")));
 select.firstChild.value="";
 rows.forEach(x=>{const o=E("option",fmt(x));o.value=String(x.id);select.append(o);});
}
async function refresh(){
 const snap=scope();
 await catalog();assertCurrent(snap);
 const r=await rpc("inventory_list_commands_v1",{p_business:snap.business,p_site:null,p_status:null,p_before_id:null,p_limit:50});
 assertCurrent(snap);acceptCommands(r,null,false);
 await loadBalances(null,false);assertCurrent(snap);
 fill(d.getElementById("st-source"),state.locations,x=>x.code+" · Site "+x.site_id);
 fill(d.getElementById("st-dest"),state.locations,x=>x.code+" · Site "+x.site_id);
 fill(d.getElementById("st-item"),state.items,x=>x.sku+" #"+x.id);
 renderCommands();
 status(t("সার্ভার থেকে Stock তথ্য পড়া হয়েছে।","Stock data loaded from server."),false);
}
function acceptCommands(r,cursor,append){
 if(!r||r.business_id!==state.business||!Array.isArray(r.items)||r.items.some(x=>!Number.isSafeInteger(x.command_id)||x.command_id<1||(cursor!==null&&x.command_id>=cursor)))bad("INVALID_INVENTORY_SCOPE");
 const next=r.next_before_id??null;
 if(next!==null&&(!Number.isSafeInteger(next)||next<1||(cursor!==null&&next>=cursor)||next!==r.items.at(-1)?.command_id))bad("INVALID_COMMAND_CURSOR");
 state.commands=append?[...state.commands,...r.items]:r.items;state.nextBefore=next;
}
function renderCommands(){
 const list=d.getElementById("st-list");list.replaceChildren();
 if(!state.commands.length)list.append(E("li",t("এখনো Stock command নেই।","No stock commands yet.")));
 state.commands.forEach(x=>{
   const item=E("li");item.className="entry";
   const sku=state.items.find(y=>y.id===x.item_id)?.sku||("#"+x.item_id);
   const title=E("strong","#"+x.command_id+" · "+x.kind+" · "+sku+" · "+x.quantity);
   const meta=E("p",x.status+" · "+t("সংস্করণ","Version")+" "+x.version);
   meta.className="muted";item.append(title,meta);
   if(x.status==="draft"||x.status==="confirmed"){
     const actions=E("div");actions.className="actions";
     const action=x.status==="draft"?"confirm":"post";
     actions.append(button(action==="confirm"?t("নিশ্চিত করুন","Confirm"):t("স্টকে পোস্ট করুন","Post stock"),()=>advance(x,action)));
     actions.append(button(t("বাতিল করুন","Cancel"),()=>advance(x,"cancel")));
     if(x.status==="confirmed"&&!x.approval_request_id)actions.append(button(t("অনুমোদন চান","Request approval"),()=>approval(x)));
     item.append(actions);
   }
   if(x.approval_request_id)item.append(E("p",t("অনুমোদন রেফারেন্স #","Approval reference #")+x.approval_request_id));
   list.append(item);
 });
 d.getElementById("st-more").hidden=state.nextBefore===null;
}
async function moreCommands(){
 if(state.busy||state.nextBefore===null)return;
 const snap=scope(),cursor=state.nextBefore;state.busy=true;
 try{const r=await rpc("inventory_list_commands_v1",{p_business:snap.business,p_site:null,p_status:null,p_before_id:cursor,p_limit:50});assertCurrent(snap);acceptCommands(r,cursor,true);renderCommands();}
 catch(e){if(current(snap))status(errorText(e),true);}finally{state.busy=false;}
}
async function loadBalances(cursor,append){
 const snap=scope();
 const r=await rpc("inventory_list_balances_v1",{p_business:snap.business,p_site:null,p_after_location:cursor?.location_id??null,p_after_item:cursor?.item_id??null,p_limit:50});
 assertCurrent(snap);
 const valid=x=>Number.isSafeInteger(x?.location_id)&&x.location_id>0&&Number.isSafeInteger(x?.item_id)&&x.item_id>0;
 const later=(x,y)=>!y||x.location_id>y.location_id||(x.location_id===y.location_id&&x.item_id>y.item_id);
 if(!r||r.business_id!==snap.business||!Array.isArray(r.items)||r.items.some(x=>!valid(x)||!later(x,cursor)))bad("INVALID_BALANCE_SCOPE");
 const next=r.next_after??null,last=r.items.at(-1);
 if(next!==null&&(!valid(next)||!later(next,cursor)||next.location_id!==last?.location_id||next.item_id!==last?.item_id))bad("INVALID_BALANCE_CURSOR");
 state.balances=append?[...state.balances,...r.items]:r.items;state.nextBalance=next;
 const list=d.getElementById("st-balances");list.replaceChildren();
 if(!state.balances.length)list.append(E("li",t("স্টক ব্যালেন্স নেই।","No stock balances.")));
 state.balances.forEach(x=>list.append(E("li",x.site_label+" · "+x.location_code+" · "+x.sku+" · "+x.on_hand)));
 d.getElementById("st-balance-more").hidden=next===null;
}
async function moreBalances(){
 if(state.busy||!state.nextBalance)return;
 const snap=scope();state.busy=true;
 try{await loadBalances(state.nextBalance,true);}catch(e){if(current(snap))status(errorText(e),true);}finally{state.busy=false;}
}
async function approval(cmd){
 if(state.busy||!state.commands.includes(cmd)||cmd.status!=="confirmed")return;
 if(!win.confirm(t("এই কমান্ডের অনুমোদন চাইবেন?","Request approval for this command?")))return;
 const snap=scope();state.busy=true;
 try{
  const r=await rpc("inventory_request_approval_v1",{p_command:positive(cmd.command_id),p_key:request()});
  assertCurrent(snap);
  if(r?.command_id!==cmd.command_id||!Number.isSafeInteger(r.approval_request_id)||r.approval_request_id<1)bad("INVALID_APPROVAL_RECEIPT");
  await refresh();assertCurrent(snap);status(t("অনুমোদন চাওয়া হয়েছে #","Approval requested #")+r.approval_request_id,false);
 }catch(e){if(current(snap))status(errorText(e),true);}finally{state.busy=false;}
}
async function advance(cmd,action){
 if(state.busy||!state.commands.includes(cmd))return;
 if(action==="cancel"&&!win.confirm(t("এই কমান্ড বাতিল করবেন?","Cancel this command?")))return;
 if(action==="post"&&!win.confirm(t("এই পোস্টে স্টকের পরিমাণ পরিবর্তিত হবে। নিশ্চিত?","Posting changes actual staging stock quantities. Continue?")))return;
 const snap=scope();state.busy=true;
 try{
  const receipt=await rpc("advance_inventory_command_v1",{p_command:positive(cmd.command_id),p_action:action,p_version:Number(cmd.version),p_request:request()});
  if(!receipt||receipt.command_id!==cmd.command_id)bad("INVALID_ADVANCE_RECEIPT");
  assertCurrent(snap);
  await refresh();assertCurrent(snap);status(t("কাজ সফল: ","Operation saved: ")+receipt.status,false);
 }catch(e){if(current(snap))status(t("প্রত্যাখ্যাত: ","Denied: ")+errorText(e),true);}
 finally{state.busy=false;}
}
async function createDraft(ev){
 ev.preventDefault();if(state.busy)return;
 const kind=d.getElementById("st-kind").value;
 if(!permitted.includes(kind))return status("INVALID_ACTION",true);
 let source=d.getElementById("st-source").value||null,dest=d.getElementById("st-dest").value||null;
 if(["receive","adjust_in"].includes(kind))source=null;
 if(["issue","adjust_out"].includes(kind))dest=null;
 if((kind==="transfer"&&(!source||!dest||source===dest))||(["receive","adjust_in"].includes(kind)&&!dest)||(["issue","adjust_out"].includes(kind)&&!source))
   return status(t("Source/Destination ঠিক করুন।","Choose valid source/destination."),true);
 const snap=scope();state.busy=true;
 try{
  const receipt=await rpc("create_inventory_command_v1",{
   p_business:positive(state.business),p_kind:kind,
   p_source:source?positive(source):null,p_destination:dest?positive(dest):null,
   p_item:positive(d.getElementById("st-item").value),p_quantity:qty(d.getElementById("st-qty").value),
   p_reason:text(d.getElementById("st-reason").value)||null,p_request:request()
  });
  if(!receipt||receipt.business_id!==state.business||receipt.status!=="draft")bad("INVALID_CREATE_RECEIPT");
  assertCurrent(snap);
  await refresh();assertCurrent(snap);status(t("ড্রাফট তৈরি হয়েছে #","Draft created #")+receipt.command_id,false);
 }catch(e){if(current(snap))status(t("প্রত্যাখ্যাত: ","Denied: ")+errorText(e),true);}
 finally{state.busy=false;}
}
async function workbench(){
 const start=scope();const u=await state.client.auth.getUser();assertCurrent(start);
 if(u.error||!u.data?.user?.id)bad("SIGNED_SESSION_REQUIRED");
 state.actor=u.data.user.id;
 const r=await rpc("build01_context_v1",{});
 if(!r||!Array.isArray(r.businesses))bad("NO_AUTHORIZED_CONTEXT");
 const businesses=r.businesses.filter(x=>x.can_manage);
 if(!businesses.length){root.replaceChildren(E("p",t("আপনার জন্য অনুমোদিত ব্যবসা নেই।","No authorized businesses.")));return;}
 const toolbar=E("div");toolbar.className="toolbar";
 const title=E("h1",t("স্টক পরিচালনা · CORE10 স্টেজিং","Stock operations · CORE10 staging"));
 const logout=button(t("সাইন আউট","Sign out"),async()=>{purge();try{const r=await state.client.auth.signOut();if(r.error)bad("SIGN_OUT_FAILED");login();}catch(e){root.replaceChildren(E("p",errorText(e)));}});
 toolbar.append(title,logout);
 const note=E("p",t("এখানে পোস্ট করলে ডেমো ব্যবসার স্টক সত্যিই পরিবর্তন হবে। কেবল পরীক্ষার জন্য ব্যবহার করুন।",
  "Posting changes real staging stock balances. Test data only."));note.className="note";
 const selectPanel=E("section");selectPanel.className="panel";
 const bl=field(t("অনুমোদিত ব্যবসা","Authorized business"),"select","st-business",true);
 const businessSelect=bl.querySelector("select");businessSelect.replaceChildren();
 businesses.forEach(x=>{const o=E("option",x.slug||String(x.id));o.value=String(x.id);businessSelect.append(o);});
 selectPanel.append(bl);
 const grid=E("div");grid.className="grid";
 const left=E("section"),right=E("section");left.className="panel";right.className="panel";
 left.append(E("h2",t("Stock command","Stock commands")));
 const list=E("ul");list.id="st-list";left.append(list);
 const reload=button(t("রিফ্রেশ","Refresh"),async()=>{if(state.busy)return;const snap=scope();state.busy=true;try{await refresh();}catch(e){if(current(snap))status(errorText(e),true);}finally{state.busy=false;}});
 const more=button(t("আরও কমান্ড","More commands"),moreCommands);more.id="st-more";more.hidden=true;left.append(reload,more);
 left.append(E("h2",t("স্টক ব্যালেন্স","Stock balances")));
 const balances=E("ul");balances.id="st-balances";left.append(balances);
 const balanceMore=button(t("আরও ব্যালেন্স","More balances"),moreBalances);balanceMore.id="st-balance-more";balanceMore.hidden=true;left.append(balanceMore);
 const form=E("form");form.id="st-form";
 form.append(E("h2",t("নতুন Stock draft","New stock draft")));
 const action=field(t("কাজ","Action"),"select","st-kind",true);
 permitted.forEach(k=>{const o=E("option",k.replace("_"," "));o.value=k;action.querySelector("select").append(o);});
 form.append(action,field(t("Source location","Source location"),"select","st-source"),field(t("Destination location","Destination location"),"select","st-dest"),
 field(t("পণ্য","Item"),"select","st-item",true),field(t("পরিমাণ","Quantity"),"number","st-qty",true),
 field(t("কারণ (প্রয়োজনে)","Reason (if required)"),"text","st-reason"));
 const qtyInput=form.querySelector("#st-qty");qtyInput.min="0.001";qtyInput.step="0.001";qtyInput.max="1000000";
 const submit=E("button",t("ড্রাফট তৈরি","Create draft"));submit.type="submit";submit.className="primary";form.append(submit);right.append(form);
 grid.append(left,right);
 const message=E("p");message.id="st-status";message.setAttribute("role","status");message.setAttribute("aria-live","polite");
 root.replaceChildren(toolbar,note,selectPanel,message,grid);
 form.addEventListener("submit",createDraft);
 businessSelect.addEventListener("change",async()=>{
  if(state.busy){businessSelect.value=String(state.business);return;}
  state.epoch++;state.business=positive(businessSelect.value);state.locations=[];state.items=[];state.commands=[];state.balances=[];state.nextBefore=null;state.nextBalance=null;
  list.replaceChildren();balances.replaceChildren();more.hidden=true;balanceMore.hidden=true;
  for(const id of ["st-source","st-dest","st-item"])d.getElementById(id).replaceChildren();
  const snap=scope();state.busy=true;try{await refresh();}catch(e){if(current(snap))status(errorText(e),true);}finally{state.busy=false;}
 });
 state.business=positive(businessSelect.value);
 state.busy=true;try{await refresh();}finally{state.busy=false;}
}
function login(){
 if(state.closed)return;purge();
 const form=E("form");form.id="st-login";form.className="panel";
 form.append(E("h1",t("স্টক · সাইন ইন","Stock · Sign in")),
 field(t("ইমেইল","Email"),"email","st-email",true),
 field(t("পাসওয়ার্ড","Password"),"password","st-password",true));
 const submit=E("button",t("সাইন ইন","Sign in"));submit.type="submit";form.append(submit);
 const error=E("p");error.id="st-login-error";error.setAttribute("role","alert");form.append(error);
 form.addEventListener("submit",async ev=>{
 ev.preventDefault();if(state.closed||submit.disabled)return;const snap=scope();submit.disabled=true;error.textContent="";
 const pass=d.getElementById("st-password");
 try{
  const r=await state.client.auth.signInWithPassword({email:d.getElementById("st-email").value.trim(),password:pass.value});
  pass.value="";if(!current(snap))return;
  if(r.error||!r.data?.user){error.textContent=t("সাইন ইন ব্যর্থ হয়েছে।","Sign-in failed.");return;}
  await workbench();
 }catch(e){pass.value="";error.textContent=t("সাইন ইন ব্যর্থ হয়েছে।","Sign-in failed.");}
 finally{submit.disabled=false;}
 });
 root.replaceChildren(form);
}
if(cfg?.url!==target||!cfg.key?.startsWith("sb_publishable_")||!win.supabase?.createClient){
 root.replaceChildren(E("p",t("অনুমোদিত CORE10 staging সংযোগ নেই।","Authorized CORE10 staging connection missing.")));
 return;
}
state.client=win.supabase.createClient(cfg.url,cfg.key);
state.client.auth.onAuthStateChange?.((event,session)=>{
 if(state.closed)return;
 if(event==="SIGNED_OUT"||(state.actor&&session?.user?.id!==state.actor)){purge();const n=state.epoch;win.setTimeout(()=>{if(n===state.epoch)login();},0);}
});
win.addEventListener?.("pagehide",()=>{state.closed=true;purge();});
win.addEventListener?.("pageshow",ev=>{if(ev.persisted)win.location.reload();});
const initial=scope();state.client.auth.getUser().then(async r=>{
 if(!current(initial))return;
 if(!r?.data?.user||r.error)login();
 else try{await workbench();}catch(e){if(!state.closed&&state.epoch===initial.epoch)root.replaceChildren(E("p",t("Stock খোলা যাচ্ছে না: ","Cannot open stock: ")+errorText(e)));}
}).catch(()=>{if(current(initial))login();});
})(window);
