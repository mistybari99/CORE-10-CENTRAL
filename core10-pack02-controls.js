/* PACK-02 S3 — control placement list for Owner / Business Owner workspaces.
 * Renders core10.pack02_controls_v1 projections only. Placement is
 * presentation, not permission; edits go through the canonical A044 writer.
 */
(function(root,factory){
 "use strict";
 const api=factory();
 if(typeof module==="object"&&module.exports)module.exports=api;
 if(root)root.CORE10_PACK02_CONTROLS=api;
})(typeof window!=="undefined"?window:globalThis,function(){
 "use strict";
 function fail(code){const e=new Error(code);e.code=code;throw e;}
 const obj=x=>!!x&&typeof x==="object"&&!Array.isArray(x);
 const PLACEMENTS=Object.freeze({central_only:"শুধু CORE 10-এ",business_only:"শুধু ব্যবসায়",both:"দুই জায়গায়",hidden_from_menus:"মেনুতে লুকানো"});
 const EDIT=Object.freeze({direct:"সরাসরি বদলানো যাবে",request:"অনুমোদনের অনুরোধ পাঠাতে হবে",view:"শুধু দেখা যাবে"});
 const GROUPS=Object.freeze({inventory:"স্টক",sales:"বিক্রয়",purchasing:"ক্রয়",operations:"কার্যক্রম",finance:"হিসাব",workforce:"কর্মী",approvals:"অনুমোদন",data:"ডেটা",offline:"অফলাইন",automation:"অটোমেশন",integration:"সংযোগ",experience:"ব্যবহার সুবিধা",notifications:"নোটিফিকেশন"});
 const NAMES=Object.freeze({
  "inventory.count":"স্টক গণনা","inventory.transfer":"স্টক স্থানান্তর","sales.orders":"বিক্রয় অর্ডার","purchase.receiving":"ক্রয় গ্রহণ",
  "production.workflows":"উৎপাদন ধাপ","projects.operations":"প্রজেক্ট কার্যক্রম","finance.reports":"হিসাব রিপোর্ট","finance.payments":"পেমেন্ট",
  "workforce.payroll":"বেতন","approvals.owner_queue":"মালিকের অনুমোদন তালিকা","approvals.delegation":"অনুমোদন দায়িত্ব অর্পণ","data.export":"ডেটা এক্সপোর্ট",
  "offline.drafts":"অফলাইন খসড়া","automation.events":"স্বয়ংক্রিয় ইভেন্ট","integration.connectors":"বাহ্যিক সংযোগ","ai.agent_proposals":"AI প্রস্তাব",
  "ui.favorites":"পছন্দের তালিকা","alerts.notifications":"সতর্কবার্তা"});
 function view(p){
  if(!obj(p)||p.contract!=="C10_PACK02_CONTROLS_V1"||!["central","business"].includes(p.surface)||
     p.placement_is_not_permission!==true||p.production_certified!==false||p.operationally_certified!==false||
     !Number.isSafeInteger(p.business_id)||p.business_id<1||!Array.isArray(p.items)||p.items.length>500)fail("PACK02_CONTROLS_INVALID");
  if(Object.keys(p).some(k=>!["contract","surface","business_id","items","placement_is_not_permission","operationally_certified","production_certified"].includes(k)))fail("PACK02_CONTROLS_UNSAFE");
  const seen=new Set();
  const items=p.items.map(i=>{
   if(!obj(i)||Object.keys(i).some(k=>!["control_id","group","placement","in_menu","preferred_enabled","version","edit"].includes(k)))fail("PACK02_CONTROLS_UNSAFE");
   if(typeof i.control_id!=="string"||!/^[a-z][a-z0-9]*(\.[a-z0-9_]+)+$/.test(i.control_id)||seen.has(i.control_id))fail("PACK02_CONTROLS_INVALID");
   seen.add(i.control_id);
   if(!(i.placement in PLACEMENTS)||!(i.edit in EDIT)||typeof i.in_menu!=="boolean"||typeof i.preferred_enabled!=="boolean"||
      !Number.isSafeInteger(i.version)||i.version<0||typeof i.group!=="string")fail("PACK02_CONTROLS_INVALID");
   // A delegated business surface may never carry central-only or hidden controls.
   if(p.surface==="business"&&(!i.in_menu||!["business_only","both"].includes(i.placement)))fail("PACK02_CONTROLS_UNSAFE");
   const expected=p.surface==="central"?["central_only","both"].includes(i.placement):true;
   if(i.in_menu!==expected)fail("PACK02_CONTROLS_UNSAFE");
   return {id:i.control_id,name:NAMES[i.control_id]||i.control_id,group:GROUPS[i.group]||i.group,
    placement:i.placement,placementLabel:PLACEMENTS[i.placement],inMenu:i.in_menu,
    edit:i.edit,editLabel:EDIT[i.edit],preferred:i.preferred_enabled,version:i.version};
  });
  return {surface:p.surface,businessId:p.business_id,items,
   note:"এখানে দেখানো মানে অনুমতি নয় — প্রতিটি কাজ সার্ভারে আলাদাভাবে যাচাই হয়।",
   empty:items.length?"":"এই ব্যবসার মেনুতে এখনো কোনো নিয়ন্ত্রণ রাখা হয়নি।"};
 }
 function el(doc,tag,cls,text){const e=doc.createElement(tag);if(cls)e.className=cls;if(text!=null)e.textContent=String(text);return e;}
 function render(rootEl,v){
  const doc=rootEl.ownerDocument;rootEl.replaceChildren();
  rootEl.append(el(doc,"p","p2-note",v.note));
  if(v.empty){rootEl.append(el(doc,"p","p2-empty",v.empty));return rootEl;}
  const ul=el(doc,"ul","p2-cards");
  for(const i of v.items){
   const li=el(doc,"li","p2-card");li.dataset.control=i.id;li.dataset.menu=String(i.inMenu);
   li.append(el(doc,"strong",null,i.name),el(doc,"span",null,`${i.group} · ${i.placementLabel}`),el(doc,"small","p2-hint",i.editLabel));
   ul.append(li);
  }
  rootEl.append(ul);return rootEl;
 }
 return Object.freeze({view,render});
});
