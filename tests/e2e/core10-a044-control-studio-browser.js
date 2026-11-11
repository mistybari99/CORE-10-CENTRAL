"use strict";
/* A044 actual browser UI + shared signed API-contract fixture: NO real Supabase. */
const assert=require("node:assert/strict");
const {chromium}=require("playwright");
const {createServer}=require("./static_server");
const fixture=String.raw`(function(){
window.BOS_CONFIG={url:"https://isolated-test.supabase.co",key:"publishable-fixture-only"};
const controls=[
"inventory.count","inventory.transfer","sales.orders","purchase.receiving",
"production.workflows","projects.operations","finance.reports","finance.payments",
"workforce.payroll","approvals.owner_queue","approvals.delegation","data.export",
"offline.drafts","automation.events","integration.connectors",
"ai.agent_proposals","ui.favorites","alerts.notifications"];
const items=controls.map((id,i)=>({control_id:id,group:id.split(".")[0],
 placement:i===0?"both":i===1?"hidden_from_menus":"central_only",
 local_edit_mode:i===0?"request_approval":"central_only",preferred_enabled:false,
 version:i===0?1:0,audit_count:0}));
window.CORE10_E2E={calls:[],items};
function response(name,args){
 window.CORE10_E2E.calls.push({name,args});
 if(name==="read_control_settings_v1")return {data:{
  tenant_id:1,business_id:args.p_business,server_authorized:true,
  operationally_certified:false,items:JSON.parse(JSON.stringify(items))},error:null};
 if(name==="read_control_pending_v1")return {data:{business_id:args.p_business,items:[]},error:null};
 if(name==="write_control_setting_v1"){
  const item=items.find(x=>x.control_id===args.p_control);
  if(!item)return {data:null,error:{code:"UNKNOWN_CONTROL",message:"Unknown control"}};
  if(item.version!==args.p_expected_version)return {data:null,error:{code:"STALE",message:"Stale version"}};
  if(args.p_control==="inventory.count"){
   // Business delegated mode: queue-only, no local effect.
   return {data:{status:"pending",version:item.version},error:null}
  }
  Object.assign(item,{placement:args.p_placement,local_edit_mode:args.p_local_edit,
   preferred_enabled:args.p_enabled,version:item.version+1,audit_count:item.audit_count+1});
  return {data:{status:"applied",version:item.version},error:null}
 }
 if(name==="decide_control_setting_v1")return {data:{status:"approved"},error:null};
 return {data:null,error:{code:"UNKNOWN_RPC",message:"Unknown RPC"}};
}
window.supabase={createClient:function(){
 return {auth:{getUser:async()=>({data:{user:{id:"signed-test-fixture-uuid"}},error:null})},
  schema:function(s){if(s!=="c10_demo")throw Error("SCHEMA_SCOPE");
   return {rpc:async(name,args)=>response(name,args),
    from:function(table){
     if(table!=="businesses")throw Error("TABLE_SHADOW_ACCESS");
     return {select(){return this},order(){return this},
      limit:async()=>({data:[{id:101,tenant_id:1,slug:"test-business"},
       {id:102,tenant_id:1,slug:"second-business"}],error:null})};
    }}
  }};
}};
})();`;
(async()=>{
 const server=createServer();
 await new Promise(resolve=>server.listen(0,"127.0.0.1",resolve));
 const base="http://127.0.0.1:"+server.address().port;
 const browser=await chromium.launch({headless:true});
 try{
  for(const width of [390,1440]){
   for(const surface of ["central","business"]){
    const page=await browser.newPage({viewport:{width,height:900}});
    const errors=[],external=[];
    page.on("pageerror",e=>errors.push(e.message));
    page.on("request",r=>{if(!r.url().startsWith(base))external.push(r.url())});
    await page.route("**/vendor/supabase.js",route=>route.fulfill({contentType:"application/javascript",body:""}));
    await page.route("**/config.js",route=>route.fulfill({contentType:"application/javascript",body:fixture}));
    page.on("dialog",dialog=>dialog.accept());
    await page.goto(base+"/"+(surface==="central"?"core10-control-studio.html":
      "core10-business-controls.html?biz=101"),{waitUntil:"load"});
    await page.waitForFunction(()=>document.querySelector("#studio-count")?.textContent.includes("/ 18 controls"),{timeout:20000});
    const count=await page.locator('[data-control]').count();
    assert.equal(count,surface==="central"?18:1,surface+" control projection at "+width);
    const first=page.locator('[data-control="inventory.count"]');
    assert.equal(await first.count(),1);
    await first.click();
    assert.match(await page.locator(".detail-title h3").innerText(),/inventory.count/);
    assert.equal(await page.locator("#studio-enabled").isEnabled(),true);
    if(surface==="business"){
      assert.equal(await page.locator("#studio-placement").isDisabled(),true);
      assert.equal(await page.locator("#studio-local-mode").isDisabled(),true);
      assert.equal(await page.locator('[data-control="inventory.transfer"]').count(),0,
       "hidden control must not appear in Business menu");
      await page.locator("#studio-enabled").selectOption("true");
      await page.locator("#studio-reason").fill("Request delegated preference change");
      await page.locator("#studio-save").click();
      await page.waitForFunction(()=>document.querySelector("#studio-status")?.textContent.includes("Approval request submitted"));
      assert.equal(await page.evaluate(()=>window.CORE10_E2E.calls.some(x=>x.name==="write_control_setting_v1"
       &&x.args.p_business===101&&x.args.p_placement==="both")),true);
    } else {
      await page.locator("#studio-search").fill("finance");
      assert.equal(await page.locator("[data-control]").count(),2);
      await page.locator("#studio-search").fill("");
      assert.equal(await page.locator("[data-control]").count(),18);
      const sel=page.locator("#studio-business");await sel.selectOption("102");
      await page.waitForFunction(()=>document.querySelector("#studio-status")?.textContent.includes("business #102"));
      assert.equal(await page.locator("[data-control]").count(),18);
    }
    const overflow=await page.evaluate(()=>document.documentElement.scrollWidth-window.innerWidth);
    assert.ok(overflow<=2,surface+" "+width+" horizontal overflow: "+overflow);
    assert.deepEqual(errors,[],surface+" "+width+" browser JS errors");
    assert.deepEqual(external,[],surface+" "+width+" contacted external URL");
    console.log("PASS A044 "+surface+" "+width+"px real DOM, signed adapter fixture, scope and menu projection; NO production calls");
    await page.close();
   }
  }
 }finally{
  await browser.close();await new Promise(resolve=>server.close(resolve));
 }
})().catch(e=>{console.error(e);process.exitCode=1});
