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
const state={client:null,business:0,locations:[],items:[],commands:[],busy:false};
function status(msg,error){let p=d.getElementById("st-status");if(p){p.textContent=msg;p.dataset.error=error?"true":"false";}}
function field(label,kind,id,required){
 const l=E("label"),n=E(kind==="select"?"select":"input");l.textContent=label;n.id=id;n.name=id;if(kind!=="select")n.type=kind;
 if(required)n.required=true;l.append(n);return l;
}
function button(label,fn){const b=E("button",label);b.type="button";b.addEventListener("click",fn);return b;}
async function rpc(name,args){
 if(!state.client)bad("SIGNED_CLIENT_REQUIRED");
 const user=await state.client.auth.getUser();
 if(user.error||!user.data?.user?.id)bad("SIGNED_SESSION_REQUIRED");
 const r=await state.client.schema("core10").rpc(name,args||{});
 if(r.error)throw r.error;return r.data;
}
async function catalog(){
 const db=state.client.schema("core10");
 const [l,i]=await Promise.all([
 db.from("stock_locations").select("id,business_id,site_id,code").eq("business_id",state.business).limit(500),
 db.from("items").select("id,business_id,sku").eq("business_id",state.business).limit(500)
 ]);
 if(l.error)throw l.error;if(i.error)throw i.error;
 if((l.data||[]).some(x=>x.business_id!==state.business)||(i.data||[]).some(x=>x.business_id!==state.business))bad("INVALID_CATALOG_SCOPE");
 state.locations=l.data||[];state.items=i.data||[];
}
function fill(select,rows,fmt){
 select.replaceChildren(E("option",t("প্রযোজ্য নয়","Not applicable")));
 select.firstChild.value="";
 rows.forEach(x=>{const o=E("option",fmt(x));o.value=String(x.id);select.append(o);});
}
async function refresh(){
 await catalog();
 const r=await rpc("inventory_list_commands_v1",{p_business:state.business,p_site:null,p_status:null,p_before_id:null,p_limit:50});
 if(!r||r.business_id!==state.business||!Array.isArray(r.items))bad("INVALID_INVENTORY_SCOPE");
 state.commands=r.items;
 fill(d.getElementById("st-source"),state.locations,x=>x.code+" · Site "+x.site_id);
 fill(d.getElementById("st-dest"),state.locations,x=>x.code+" · Site "+x.site_id);
 fill(d.getElementById("st-item"),state.items,x=>x.sku+" #"+x.id);
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
     item.append(actions);
   }
   list.append(item);
 });
 status(t("সার্ভার থেকে Stock তথ্য পড়া হয়েছে।","Stock data loaded from server."),false);
}
async function advance(cmd,action){
 if(state.busy)return;
 if(action==="post"&&!win.confirm(t("এই পোস্টে স্টকের পরিমাণ পরিবর্তিত হবে। নিশ্চিত?","Posting changes actual staging stock quantities. Continue?")))return;
 state.busy=true;
 try{
  const receipt=await rpc("advance_inventory_command_v1",{p_command:positive(cmd.command_id),p_action:action,p_version:Number(cmd.version),p_request:request()});
  if(!receipt||receipt.command_id!==cmd.command_id)bad("INVALID_ADVANCE_RECEIPT");
  await refresh();status(t("কাজ সফল: ","Operation saved: ")+receipt.status,false);
 }catch(e){status(t("প্রত্যাখ্যাত: ","Denied: ")+(e.message||e.code),true);}
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
 state.busy=true;
 try{
  const receipt=await rpc("create_inventory_command_v1",{
   p_business:positive(state.business),p_kind:kind,
   p_source:source?positive(source):null,p_destination:dest?positive(dest):null,
   p_item:positive(d.getElementById("st-item").value),p_quantity:qty(d.getElementById("st-qty").value),
   p_reason:text(d.getElementById("st-reason").value)||null,p_request:request()
  });
  if(!receipt||receipt.business_id!==state.business||receipt.status!=="draft")bad("INVALID_CREATE_RECEIPT");
  await refresh();status(t("ড্রাফট তৈরি হয়েছে #","Draft created #")+receipt.command_id,false);
 }catch(e){status(t("প্রত্যাখ্যাত: ","Denied: ")+(e.message||e.code),true);}
 finally{state.busy=false;}
}
async function workbench(){
 const r=await rpc("build01_context_v1",{});
 if(!r||!Array.isArray(r.businesses))bad("NO_AUTHORIZED_CONTEXT");
 const businesses=r.businesses.filter(x=>x.can_manage);
 if(!businesses.length){root.replaceChildren(E("p",t("আপনার জন্য অনুমোদিত ব্যবসা নেই।","No authorized businesses.")));return;}
 const toolbar=E("div");toolbar.className="toolbar";
 const title=E("h1",t("স্টক পরিচালনা · CORE10 স্টেজিং","Stock operations · CORE10 staging"));
 const logout=button(t("সাইন আউট","Sign out"),async()=>{await state.client.auth.signOut();login();});
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
 const reload=button(t("রিফ্রেশ","Refresh"),()=>refresh().catch(e=>status(e.message,true)));left.append(reload);
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
 businessSelect.addEventListener("change",async()=>{state.business=positive(businessSelect.value);try{await refresh();}catch(e){status(e.message,true);}});
 state.business=positive(businessSelect.value);
 await refresh();
}
function login(){
 const form=E("form");form.id="st-login";form.className="panel";
 form.append(E("h1",t("স্টক · সাইন ইন","Stock · Sign in")),
 field(t("ইমেইল","Email"),"email","st-email",true),
 field(t("পাসওয়ার্ড","Password"),"password","st-password",true));
 const submit=E("button",t("সাইন ইন","Sign in"));submit.type="submit";form.append(submit);
 const error=E("p");error.id="st-login-error";error.setAttribute("role","alert");form.append(error);
 form.addEventListener("submit",async ev=>{
 ev.preventDefault();submit.disabled=true;error.textContent="";
 const pass=d.getElementById("st-password");
 try{
  const r=await state.client.auth.signInWithPassword({email:d.getElementById("st-email").value.trim(),password:pass.value});
  pass.value="";
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
state.client.auth.getUser().then(async r=>{
 if(!r?.data?.user||r.error)login();
 else try{await workbench();}catch(e){root.replaceChildren(E("p",t("Stock খোলা যাচ্ছে না: ","Cannot open stock: ")+(e.message||"SERVER_ERROR")));}
}).catch(login);
})(window);
