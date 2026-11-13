"use strict";
/* C10-A053/A054 real-DOM browser test at 390px and 1440px against a clearly labelled SYNTHETIC signed-API fixture (no Supabase, no network).
 * Proves UI wiring, approved-vs-paid labelling, privacy projection, Bangla/English and responsive layout. Real RPC behaviour is proven by the
 * PostgreSQL / concurrency / signed-HTTP suites. Real GoTrue-issued sessions remain a separate release gate (NOT TESTED). */
const assert=require("node:assert/strict");
const {chromium}=require("playwright");
const {createServer}=require("./static_server");
const fixture=(persona,variant)=>String.raw`(function(){
window.BOS_CONFIG={url:"https://isolated-test.supabase.co",key:"publishable-fixture-only"};
const persona=${JSON.stringify(persona)},variant=${JSON.stringify(variant||"")};
const owner=persona==="owner",manager=persona==="manager";
const calls=[];window.CORE10_E2E={calls};window.__xss=0;
let runStatus="draft";
const lines=[{employee_id:1,employee_no:"B1",employed_days:31,basic_earned:30000,overtime_pay:1330.65,allowances_total:3500,total_deductions:976.61,net:33854.04,
 components:[{kind:"trace",code:"OT_POLICY",policy_version_id:3,mode:"on",weekday_multiplier:1.5,offday_multiplier:2},{code:"HOUSE",kind:"allowance",amount:2500,trace:{base:"basic_earned",base_value:30000,amount_param:10,unit:"percent_of_base",cap:2500}}]}];
function R(name,a){
 calls.push({name,args:a});
 const ok=(d)=>({data:d,error:null});
 switch(name){
 case"wf_my_businesses_v1":return ok({server_authorized:true,items:[{id:102,tenant_id:1,slug:"demo-second-business"},{id:101,tenant_id:1,slug:"demo-sweets"}]});
 case"a054_my_access_v1":return ok({server_authorized:true,level:owner?"business_owner":manager?"manager":"employee",owner,delegated_roles:manager?["payroll_preparer"]:[],can_view_liability:owner});
 case"a053_read_portfolio_workforce_v1":
  if(variant==="notconnected")return ok({server_authorized:true,state:"NOT_CONNECTED",period:a.p_period,contracts:{A050_portfolio:"CONNECTED",A051_workforce:"NOT_CONNECTED",A054_payment_tracking:"NOT_CONNECTED"},businesses:[],paid:false,money_movement:false,ledger_posted:false});
  return ok({server_authorized:true,state:"CONNECTED",period:a.p_period,contracts:{A050_portfolio:"CONNECTED",A051_workforce:"CONNECTED",A054_payment_tracking:"CONNECTED"},paid:false,money_movement:false,ledger_posted:false,
   businesses:owner?[{business_id:102,name:"<img src=x onerror=window.__xss=1>",state:"OK",workforce:{active_headcount:2,headcount_by_site:[{site_id:1003,n:2}]},
    liability:{state:"approved_not_paid",net_approved_preview:60426.04,paid:false,money_movement:false,ledger_posted:false,payment_tracking:"CONNECTED",
     approved_unpaid:{approved_unpaid_amount:0,approved_unpaid_count:0,partially_paid_outstanding:23854.04,paid_recorded_amount:36572,total_outstanding:23854.04}}},
    {business_id:101,name:"Sweets",state:"OK",workforce:{active_headcount:0,headcount_by_site:[]},liability:{state:"no_approved_run",net_approved_preview:null,paid:false,money_movement:false,ledger_posted:false,payment_tracking:"CONNECTED",approved_unpaid:null}}]
   :[{business_id:102,name:"Branch",state:"OWNER_ONLY",workforce:null,liability:null}]});
 case"a053_my_assignments_v1":return ok({server_authorized:true,state:"CONNECTED",items:[{business_id:102,employee_no:"B1",site_label:"A3",designation:"Cashier"}]});
 case"a053_staff_overview_v1":return manager||owner?ok({server_authorized:true,items:[{employee_id:1,employee_no:"B1",full_name:owner?"Bela Branch":"Bela B.",status:"active",site_label:"A3",identity_linked:true,identity_alias:owner?"BRANCH_STAFF_B":null},
   {employee_id:2,employee_no:"B2",full_name:owner?"Babul Branch":"Babul B.",status:"active",site_label:"A3",identity_linked:false,identity_alias:null}]}):{data:null,error:{message:"a053_manager_required"}};
 case"a053_persona_catalog_v1":return ok({server_authorized:true,items:[{alias:"UNASSIGNED_USER",linkable:true,active:true},{alias:"PLATFORM_OPERATOR",linkable:false,active:true}]});
 case"a054_eligible_delegates_v1":return ok({server_authorized:true,items:[{uid:"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",ref:"bbbbbbbb",source:"member_manager"}]});
 case"a054_list_delegations_v1":return ok({server_authorized:true,items:[{id:7,delegate_ref:"bbbbbbbb",role:"payroll_preparer",effect:"allow",period_from:"2026-10-01",period_to:"2026-10-01",state:"active",version:1},{id:8,delegate_ref:"b1111111",role:"hr",effect:"deny",state:"revoked",version:2}]});
 case"a054_grant_delegation_v1":return ok({status:"granted",delegation_id:9,version:1});
 case"a054_revoke_delegation_v1":return ok({status:"revoked",delegation_id:7,version:2});
 case"a054_list_policies_v1":return ok({server_authorized:true,kind:a.p_kind,items:a.p_kind==="overtime"?[{id:1,subject:"DEFAULT",version:1,effective_from:"2026-10-01",params:{mode:"on",weekday_multiplier:1.5,offday_multiplier:2},state:"effective"},{id:2,subject:"DEFAULT",version:2,effective_from:"2026-12-01",params:{mode:"on",weekday_multiplier:1.75,offday_multiplier:2.5},state:"scheduled"}]
   :a.p_kind==="pay_rule"?[{id:3,subject:"HOUSE",version:1,effective_from:"2026-10-01",params:{kind:"allowance",calc:"percent",amount:10,base:"basic_earned",cap_amount:2500},state:"effective"}]:[]});
 case"a054_save_policy_v1":return ok({status:"saved",policy_id:9,version:3});
 case"a054_leave_balance_v1":return ok({server_authorized:true,year:a.p_year,items:[{leave_type:"ANNUAL",entitlement:10,carried_in:5,carry_used:3,carry_expired:2,carry_expiry_date:"2027-03-31",used_total:13,available_as_of_today:0,remaining_end:0}]});
 case"wf_payroll_preview_v1":return ok({server_authorized:true,preview_only:true,paid:false,lines});
 case"wf_list_payroll_runs_v1":return owner||manager?ok({server_authorized:true,items:[{id:11,period_start:"2026-10-01",version:1,status:runStatus,total_net:60426.04,blocking_count:0}]}):{data:null,error:{message:"wf_payroll_access_denied"}};
 case"wf_payroll_transition_v1":runStatus=({review:"reviewed",approve:"approved",freeze:"frozen"})[a.p_action]||runStatus;return ok({status:runStatus,run_id:11,paid:false,money_movement:false});
 case"wf_create_payroll_draft_v1":return ok({status:"draft",run_id:12});
 case"a054_liability_report_v1":return owner?ok({server_authorized:true,payment_executed:false,paid:false,money_movement:false,ledger_posted:false,bank_file:false,pre_approval:{runs:0,estimated_net:0},
   totals:{approved_net_total:60426.04,approved_unpaid_amount:26572,approved_unpaid_count:1,partially_paid_outstanding:23854.04,partially_paid_count:1,paid_recorded_amount:10000,paid_recorded_count:0,overpaid_recorded_count:0,total_outstanding:50426.04},
   by_site:[{site_id:1003,site_label:"A3",outstanding:50426.04,headcount:2}],
   lines:[{employee_id:1,employee_no:"B1",net:33854.04,recorded_paid:10000,outstanding:23854.04,state:"partially_paid_recorded"},{employee_id:2,employee_no:"B2",net:26572,recorded_paid:0,outstanding:26572,state:"approved_unpaid"}]})
   :{data:null,error:{message:"a054_liability_denied"}};
 case"a054_record_external_payment_v1":return ok({status:"recorded",payment_executed:false,money_movement:false});
 case"a054_export_liability_csv_v1":return ok({server_authorized:true,filename:"core10-workforce-liability.csv",csv:"period,employee_no\n2026-10-01,B1\n",rows:1});
 case"a054_retention_report_v1":return owner?ok({server_authorized:true,retention_months:36,expired_raw_punches:2,protected_by_legal_hold:1,purgeable_now:1,active_holds:[{id:4,employee_id:1,hold_from:"2024-01-01",hold_to:"2024-12-31",reason:"dispute"}]}):{data:null,error:{message:"a054_owner_required"}};
 case"a054_place_legal_hold_v1":return ok({status:"hold_placed",hold_id:5});
 default:return {data:null,error:{message:"UNEXPECTED_FIXTURE_RPC "+name}};
 }
}
window.supabase={createClient:function(){return {auth:{getUser:async()=>({data:{user:{id:"signed-test-fixture-uuid"}},error:null})},
 schema:function(s){if(s!=="c10_demo")throw Error("SCHEMA_SCOPE");return {rpc:async(n,a)=>R(n,a),from:function(){throw Error("TABLE_SHADOW_ACCESS")}}}}}};
})();`;
(async()=>{
 const server=createServer();await new Promise(r=>server.listen(0,"127.0.0.1",r));
 const base="http://127.0.0.1:"+server.address().port;
 const browser=await chromium.launch({headless:true});
 try{
  for(const width of [390,1440]){
   async function open(persona,pageName,variant){
    const page=await browser.newPage({viewport:{width,height:900}});
    const errors=[],external=[];page.__errors=errors;page.__external=external;
    page.on("pageerror",e=>errors.push(e.message));
    page.on("request",r=>{if(!r.url().startsWith(base)&&!r.url().startsWith("blob:")&&!r.url().startsWith("data:"))external.push(r.url())});
    await page.route("**/vendor/supabase.js",r=>r.fulfill({contentType:"application/javascript",body:""}));
    await page.route("**/config.js",r=>r.fulfill({contentType:"application/javascript",body:fixture(persona,variant)}));
    await page.goto(base+"/core10-workforce-"+pageName+".html",{waitUntil:"load"});
    await page.waitForFunction(()=>/^(Ready|প্রস্তুত)/.test(document.querySelector("#wf-status")?.textContent||""),{timeout:20000});
    return page;
   }
   async function done(page,label){
    const overflow=await page.evaluate(()=>document.documentElement.scrollWidth-window.innerWidth);
    assert.ok(overflow<=2,label+" "+width+" horizontal overflow "+overflow);
    assert.deepEqual(page.__errors,[],label+" JS errors");assert.deepEqual(page.__external,[],label+" external request");
    assert.equal(await page.evaluate(()=>window.__xss),0,label+" XSS payload executed");
    await page.screenshot({path:process.env.C10_SHOT_DIR?process.env.C10_SHOT_DIR+"/"+label.replace(/\W+/g,"_")+"-"+width+".png":undefined,fullPage:false}).catch(()=>{});
    await page.close();
   }
   const names=async(p)=>(await p.evaluate(()=>window.CORE10_E2E.calls.map(c=>c.name)));
   // --- integration (owner)
   let p=await open("owner","integration");
   assert.match(await p.locator("#pf-state").innerText(),/CONNECTED/);
   const card=await p.locator('[data-biz="102"]').innerText();
   assert.match(card,/<img src=x onerror=window.__xss=1>/,"hostile name is text");
   assert.match(card,/Approved payroll \(net\)/);assert.match(card,/Partly paid: still owed/);assert.match(card,/23,854\.04/);assert.match(card,/Paid outside system \(recorded\)/);
   assert.match(card,/false \/ false \/ false/,"paid / money_movement / ledger shown false");
   assert.match(await p.locator("#wf-body").innerText(),/Approval is not payment/);
   assert.ok(await p.locator("#unlink-B1").count()===1&&await p.locator("#link-B2").count()===1,"owner link/unlink controls");
   await p.locator("#link-B2").click();await p.waitForFunction(()=>window.CORE10_E2E.calls.some(c=>c.name==="a053_link_staff_identity_v1"));
   const link=await p.evaluate(()=>window.CORE10_E2E.calls.find(c=>c.name==="a053_link_staff_identity_v1").args);
   assert.equal(link.p_alias,"UNASSIGNED_USER");assert.equal(link.p_business,102);assert.ok(!("p_uid" in link),"alias only, never raw uid");
   assert.ok(!(await p.locator("#al-B2 option").allInnerTexts()).includes("PLATFORM_OPERATOR"),"non-linkable alias not offered");
   await done(p,"integration owner");
   // Bangla toggle
   p=await open("owner","integration");await p.locator("#lang-bn").click();
   await p.waitForFunction(()=>/^প্রস্তুত/.test(document.querySelector("#wf-status")?.textContent||""));
   assert.match(await p.locator("#wf-body").innerText(),/অনুমোদন মানে পেমেন্ট নয়/);assert.equal(await p.evaluate(()=>document.documentElement.lang),"bn");
   await done(p,"integration bangla");
   // manager: owner-only, no figures
   p=await open("manager","integration");
   const mt=await p.locator("#wf-body").innerText();assert.match(mt,/OWNER ONLY/);assert.ok(!/60,426|23,854|headcount/i.test(mt),"manager sees no figures");
   assert.equal(await p.locator("[id^=link-]").count(),0,"manager cannot link");await done(p,"integration manager");
   p=await open("owner","integration","notconnected");
   assert.match(await p.locator("#pf-nc").innerText(),/NOT CONNECTED/);assert.equal(await p.locator("[data-biz]").count(),0,"no invented businesses");await done(p,"integration notconnected");
   // --- delegation
   p=await open("owner","delegation");
   assert.equal(await p.locator("#dg-form").count(),1);
   await p.locator("#dg-role").selectOption("payroll_approver");await p.locator("#dg-effect").selectOption("allow");await p.locator("#dg-form button[type=submit]").click();
   await p.waitForFunction(()=>window.CORE10_E2E.calls.some(c=>c.name==="a054_grant_delegation_v1"));
   const g=await p.evaluate(()=>window.CORE10_E2E.calls.find(c=>c.name==="a054_grant_delegation_v1").args);
   assert.equal(g.p_role,"payroll_approver");assert.match(g.p_period_from,/^\d{4}-\d{2}-01$/);assert.equal(g.p_site,null);
   assert.match(await p.locator("#wf-body").innerText(),/DENY/);
   await p.locator("#revoke-7").click();await p.waitForFunction(()=>window.CORE10_E2E.calls.some(c=>c.name==="a054_revoke_delegation_v1"));
   assert.equal((await p.evaluate(()=>window.CORE10_E2E.calls.find(c=>c.name==="a054_revoke_delegation_v1").args)).p_expected_version,1);
   await done(p,"delegation owner");
   p=await open("manager","delegation");assert.equal(await p.locator("#dg-form").count(),0,"manager cannot grant");
   assert.match(await p.locator("#my-roles").innerText(),/payroll preparer/i);await done(p,"delegation manager");
   // --- policy
   p=await open("owner","policy");
   assert.match(await p.locator("#wf-body").innerText(),/1\.00x = 100% of the base hourly rate \(not 1%\)/);
   await p.waitForSelector("#pol-pane table");
   assert.match(await p.locator("#pol-pane").innerText(),/scheduled/i);assert.match(await p.locator("#pol-pane").innerText(),/1\.75x \/ 2\.5x/);
   await p.locator("#ot-w").fill("1.5");await p.locator("#ot-form button[type=submit]").click();
   await p.waitForFunction(()=>window.CORE10_E2E.calls.some(c=>c.name==="a054_save_policy_v1"));
   const sp=await p.evaluate(()=>window.CORE10_E2E.calls.find(c=>c.name==="a054_save_policy_v1").args);
   assert.deepEqual(sp.p_params,{mode:"on",weekday_multiplier:1.5,offday_multiplier:2});assert.match(sp.p_effective_from,/-01$/);
   await p.locator("#tab-rule").click();await p.waitForSelector("#rl-form");await p.waitForSelector("#pol-pane table");assert.match(await p.locator("#pol-pane").innerText(),/cap 2500/);
   await p.locator("#tab-leave").click();await p.waitForSelector("#lv-bal table");assert.match(await p.locator("#lv-bal").innerText(),/2027-03-31/);
   await p.locator("#tab-preview").click();await p.locator("#pv-go").click();await p.waitForSelector("#pv-out table");
   const pv=await p.locator("#pv-out").innerText();assert.match(pv,/OT policy v3 1\.5x\/2x/);assert.match(pv,/HOUSE: basic_earned=30,000\.00/);assert.equal(await p.locator('#pv-out td[data-label="Net (owed, not paid)"]').count(),1,"net column labelled owed, not paid");
   await done(p,"policy owner");
   // --- liability: approval vs payment
   p=await open("owner","liability");
   const lt=await p.locator("#wf-body").innerText();
   assert.match(lt,/Approved - payment NOT recorded/);assert.match(lt,/Partly paid \(recorded outside system\)/);assert.match(lt,/Paid outside system \(recorded\)/);
   assert.match(lt,/Not yet approved \(estimate, not a liability\)/);assert.match(lt,/payment_executed=false · money_movement=false · ledger_posted=false/);
   assert.equal(await p.locator("#c-approved").count()+await p.locator("#c-partial").count()+await p.locator("#c-paid").count(),3,"approved-unpaid, partial and paid are separate cards");
   await p.locator("#run-review-11").click();await p.waitForFunction(()=>window.CORE10_E2E.calls.some(c=>c.name==="wf_payroll_transition_v1"));
   await p.waitForFunction(()=>!!document.querySelector("#run-approve-11"));
   assert.match(await p.locator("#run-approve-11").innerText(),/does NOT pay anyone/);
   assert.ok(!/\bPay\b/i.test(await p.locator("#run-approve-11").innerText().then(t=>t.replace(/does NOT pay anyone/i,""))),"approve button never says pay");
   await p.locator("#rec-B1").click();await p.waitForSelector("#pay-form");
   assert.match(await p.locator("#pay-form").innerText(),/does not send money/);
   await p.locator("#pay-ref").fill("VCH-2026-001");await p.locator("#pay-amt").fill("1000.5");await p.locator("#pay-form button[type=submit]").click();
   await p.waitForFunction(()=>window.CORE10_E2E.calls.some(c=>c.name==="a054_record_external_payment_v1"));
   const rp=await p.evaluate(()=>window.CORE10_E2E.calls.find(c=>c.name==="a054_record_external_payment_v1").args);
   assert.equal(rp.p_amount,1000.5);assert.equal(rp.p_method,"cash");assert.equal(rp.p_reference,"VCH-2026-001");assert.equal(rp.p_employee,1);
   assert.match(await p.locator("#hold-form").innerText(),/Place legal hold/);assert.match(await p.locator("#ly-ret").innerText(),/never purged/);
   await p.locator("#csv-btn").click();await p.waitForSelector("#csv-link");
   await done(p,"liability owner");
   p=await open("employee","liability");
   const et=await p.locator("#wf-body").innerText();assert.ok(!/60,426|23,854|B1|B2/.test(et),"staff sees no liability or other staff");
   assert.match(await p.locator("#wf-status").innerText(),/Ready|প্রস্তুত/);
   await done(p,"liability employee");
  }
  console.log("A053_A054_BROWSER_PASS 390px+1440px");
 }finally{await browser.close();server.close()}
})().catch(e=>{console.error(e);process.exit(1)});
