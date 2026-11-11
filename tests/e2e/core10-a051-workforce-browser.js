"use strict";
/* C10-A051 real-DOM browser test at 390px and 1440px. Uses a clearly labelled SYNTHETIC signed-API fixture (NO Supabase,
 * NO network). It proves the UI wiring/projection/responsive layout; the real RPC behaviour is proven by the PostgreSQL
 * and signed-HTTP suites. Real GoTrue-issued session verification remains a separate release gate. */
const assert=require("node:assert/strict");
const {chromium}=require("playwright");
const {createServer}=require("./static_server");
const fixture=(persona)=>String.raw`(function(){
window.BOS_CONFIG={url:"https://isolated-test.supabase.co",key:"publishable-fixture-only"};
const persona=${JSON.stringify(persona)};
const owner=persona==="owner",manager=persona==="manager",employee=persona==="employee";
const caps={view_directory:owner||manager,edit_employees:owner,manage_structure:owner,assign_shifts:owner||manager,import_punches:owner||manager,
 request_correction:owner||manager,decide_correction:owner,decide_overtime:owner||manager,review_leave:owner||manager,request_leave:true,
 payroll:owner,own_payslips:employee||owner,reports:owner||manager,export_attendance:owner||manager,export_payroll:owner,integrity:owner};
const calls=[];window.CORE10_E2E={calls};window.__xss=0;
const emps=[{id:1,employee_no:"EMP-001",full_name:"Rahim Ahmed",status:"active",contract_type:"permanent",joined_on:"2026-01-01",version:1,site_id:1001,site_label:"Showroom A1",department:"Operations",designation:"Operator",is_supervisor:false,contact_phone:owner?"+880171000001":null,national_id_last4:owner?"1234":null},
 {id:2,employee_no:"EMP-002",full_name:"<img src=x onerror=window.__xss=1>",status:"active",contract_type:"daily",joined_on:"2026-02-01",version:1,site_id:1002,site_label:"Factory A2",department:null,designation:null,is_supervisor:true}];
const att=[{employee_id:1,employee_no:"EMP-001",full_name:"Rahim Ahmed",date:"2026-10-21",status:"incomplete",first_in:"2026-10-21T09:00:00+06:00",last_out:null,worked_minutes:0,late_minutes:0,overtime_minutes:0,overtime_approved_minutes:0,overtime_decided:true,locked:false},
 {employee_id:1,employee_no:"EMP-001",full_name:"Rahim Ahmed",date:"2026-10-15",status:"present",first_in:"2026-10-15T09:00:00+06:00",last_out:"2026-10-15T19:30:00+06:00",worked_minutes:570,late_minutes:0,overtime_minutes:90,overtime_approved_minutes:0,overtime_decided:false,locked:false},
 {employee_id:1,employee_no:"EMP-001",full_name:"Rahim Ahmed",date:"2026-10-05",status:"absent",first_in:null,last_out:null,worked_minutes:0,late_minutes:0,overtime_minutes:0,overtime_approved_minutes:0,overtime_decided:true,locked:true}];
const lines=[{employee_id:1,employee_no:"EMP-001",employee_name:"Rahim Ahmed",gross:37100,total_deductions:4700,net:32400,basic_earned:31000,overtime_pay:2000,allowances_total:4100,present_days:21,absent_days:1,paid_leave_days:2,warnings:[]},
 {employee_id:9,employee_no:"EMP-009",employee_name:"Imran Intern",gross:0,total_deductions:0,net:0,basic_earned:0,overtime_pay:0,allowances_total:0,present_days:0,absent_days:0,paid_leave_days:0,warnings:[{code:"no_salary_structure",blocking:true}]}];
let runStatus="draft";
function R(name,a){
 calls.push({name,args:a});
 const ok=(d)=>({data:d,error:null});
 switch(name){
 case"wf_my_businesses_v1":return ok({server_authorized:true,items:[{id:101,tenant_id:1,slug:"demo-sweets"},{id:102,tenant_id:1,slug:"demo-second"}]});
 case"wf_read_overview_v1":return ok({server_authorized:true,business_id:a.p_business,level:persona==="owner"?"business_owner":persona,self_employee_id:employee||owner?1:null,capabilities:caps,today:"2026-11-11"});
 case"wf_read_catalog_v1":return ok({server_authorized:true,year:2026,sites:[{id:1001,label:"Showroom A1",kind:"showroom"},{id:1002,label:"Factory A2",kind:"factory"}],
  departments:[{code:"OPS",name:"Operations",active:true,version:1}],shifts:[{id:1,code:"DAY",name:"Day 9-6",start_time:"09:00:00",end_time:"18:00:00",crosses_midnight:false,break_minutes:60,grace_late_minutes:10,active:true,version:1},
  {id:2,code:"NIGHT",name:"Night",start_time:"22:00:00",end_time:"06:00:00",crosses_midnight:true,break_minutes:30,grace_late_minutes:10,active:true,version:1}],
  holidays:[{id:1,date:"2026-10-20",name:"Company Day",kind:"company",paid:true,active:true}],
  leave_types:[{id:1,code:"ANNUAL",name:"Annual",paid:true,annual_quota_days:10,requires_approval:true,active:true,version:1}],
  pay_policies:owner?[{code:"MONTHLY",pay_basis:"monthly",ot_multiplier_weekday:2,ot_multiplier_offday:2,rounding_mode:"half_up",active:true}]:null,
  components:owner?[{code:"PF",kind:"deduction",calc_type:"percent_of_base",amount:5,approval_status:"pending_owner_approval",statutory:true}]:null});
 case"wf_list_employees_v1":return ok({server_authorized:true,total:employee?1:emps.length,items:employee?[emps[0]]:emps});
 case"wf_get_employee_v1":return ok(Object.assign({server_authorized:true},emps[0],{employment_history:[{effective_from:"2026-01-01",status:"active",contract_type:"permanent",reason:"hired"}],
  assignments:[{effective_from:"2026-01-01",site_id:1001,site_label:"Showroom A1",department:"Operations",designation:"Operator",is_supervisor:false}],
  shift_assignments:[{effective_from:"2026-01-01",shift_code:"DAY",shift_name:"Day 9-6"}],salary_structures:owner?[{effective_from:"2026-01-01",policy:"MONTHLY",pay_basis:"monthly",base_amount:31000}]:null}));
 case"wf_list_attendance_v1":return ok({server_authorized:true,items:att});
 case"wf_list_corrections_v1":return ok({server_authorized:true,items:[{id:5,employee_id:1,employee_no:"EMP-001",work_date:"2026-10-21",new_out:"2026-10-21T18:00:00+06:00",reason:"device missed exit",status:"pending",mine:false}]});
 case"wf_list_leave_v1":return ok({server_authorized:true,items:[{id:7,employee_id:1,employee_no:"EMP-001",full_name:"Rahim Ahmed",leave_name:"Annual",paid:true,from_date:"2026-11-23",to_date:"2026-11-25",days:3,status:"pending",mine:employee}]});
 case"wf_leave_balance_v1":return ok({server_authorized:true,items:[{leave_type:"ANNUAL",name:"Annual",quota:10,approved:2,pending:3}]});
 case"wf_list_advances_v1":return ok({server_authorized:true,items:[{id:3,employee_no:"EMP-001",amount:3000,installment_amount:1000,remaining:2000,status:"requested"}]});
 case"wf_payroll_preview_v1":return ok({server_authorized:true,preview_only:true,paid:false,employee_count:2,total_gross:37100,total_deductions:4700,total_net:32400,blocking_count:1,lines});
 case"wf_list_payroll_runs_v1":return ok({server_authorized:true,items:[{id:11,period_start:"2026-10-01",version:1,status:runStatus,employee_count:2,total_net:32400,blocking_count:0}]});
 case"wf_get_payroll_run_v1":return ok({server_authorized:true,run:{id:11,period_start:"2026-10-01",version:1,status:runStatus,total_gross:37100,total_deductions:4700,total_net:32400,prepared_by_me:false},lines});
 case"wf_create_payroll_draft_v1":return ok({status:"draft",run_id:11,version:1,blocking_count:1,employee_count:2});
 case"wf_payroll_transition_v1":runStatus=({review:"reviewed",approve:"approved",freeze:"frozen"})[a.p_action]||runStatus;return ok({status:runStatus,run_id:11,paid:false});
 case"wf_recalculate_payroll_draft_v1":return ok({status:"draft",run_id:11,blocking_count:0});
 case"wf_my_payslips_v1":return ok({server_authorized:true,items:[{id:21,period_start:"2026-10-01",period_end:"2026-10-31",net:32400,superseded:false,run_version:1}]});
 case"wf_get_my_payslip_v1":return ok({server_authorized:true,id:21,superseded:false,payslip:{period_start:"2026-10-01",basic_earned:31000,overtime_pay:2000,allowances:[{name:"Transport",amount:1000}],gross:37100,absence_deduction:3500,other_deductions:[{name:"Uniform",amount:200}],advance_recovery:1000,net:32400}});
 case"wf_report_attendance_v1":return ok({server_authorized:true,sites:[{site_id:1001,site_label:"Showroom A1",present:20,half_day:1,absent:1,paid_leave:2,unpaid_leave:1,late_days:3,incomplete:0,overtime_approved_minutes:480}]});
 case"wf_report_headcount_v1":return ok({server_authorized:true,as_of:"2026-11-11",rows:[{site_label:"Showroom A1",status:"active",contract_type:"permanent",headcount:4}]});
 case"wf_report_payroll_v1":return ok({server_authorized:true,run:{status:"frozen"},sites:[{site_label:"Showroom A1",headcount:4,gross:100,deductions:10,net:90}]});
 case"wf_payslip_register_v1":return ok({server_authorized:true,items:[{employee_no:"EMP-001",employee_name:"Rahim Ahmed",run_version:1,run_status:"frozen",gross:37100,net:32400}]});
 case"wf_integrity_report_v1":return ok({server_authorized:true,ok:true,checks:[{name:"audit_hash_chain",ok:true}]});
 case"wf_audit_list_v1":return ok({server_authorized:true,items:[{id:1,entity:"employee",entity_id:"1",event:"created",reason:"hire",hash:"abc123"}]});
 case"wf_export_csv_v1":return ok({server_authorized:true,kind:a.p_kind,rows:2,filename:"core10-workforce-"+a.p_kind+".csv",csv:"a,b\n1,2\n"});
 default:return ok({status:"applied",run_id:11,accepted:1,duplicates:0,rejected:0,days:2,leave_id:9});
 }
}
window.supabase={createClient:function(){return {auth:{getUser:async()=>({data:{user:{id:"signed-test-fixture-uuid"}},error:null})},
 schema:function(s){if(s!=="c10_demo")throw Error("SCHEMA_SCOPE");return {rpc:async(n,a)=>R(n,a),from:function(){throw Error("TABLE_SHADOW_ACCESS")}}}}}};
})();`;
const calls=(page)=>page.evaluate(()=>window.CORE10_E2E.calls);
(async()=>{
 const server=createServer();await new Promise(r=>server.listen(0,"127.0.0.1",r));
 const base="http://127.0.0.1:"+server.address().port;
 const browser=await chromium.launch({headless:true});
 try{
  for(const width of [390,1440]){
   async function open(persona,pageName,qs){
    const page=await browser.newPage({viewport:{width,height:900}});
    const errors=[],external=[];page.__errors=errors;page.__external=external;
    page.on("pageerror",e=>errors.push(e.message));
    page.on("request",r=>{if(!r.url().startsWith(base)&&!r.url().startsWith("blob:")&&!r.url().startsWith("data:"))external.push(r.url())});
    page.on("dialog",d=>d.accept(d.type()==="prompt"?"Reason given for this action":undefined));
    await page.route("**/vendor/supabase.js",r=>r.fulfill({contentType:"application/javascript",body:""}));
    await page.route("**/config.js",r=>r.fulfill({contentType:"application/javascript",body:fixture(persona)}));
    await page.goto(base+"/core10-workforce-"+pageName+".html"+(qs||""),{waitUntil:"load"});
    await page.waitForFunction(()=>/^Ready/.test(document.querySelector("#wf-status")?.textContent||""),{timeout:20000});
    return page;
   }
   async function done(page,label){
    const overflow=await page.evaluate(()=>document.documentElement.scrollWidth-window.innerWidth);
    assert.ok(overflow<=2,label+" "+width+" horizontal overflow "+overflow);
    assert.deepEqual(page.__errors,[],label+" JS errors");assert.deepEqual(page.__external,[],label+" external request");
    assert.equal(await page.evaluate(()=>window.__xss),0,label+" XSS payload executed");
    await page.close();
   }
   // --- Directory (owner)
   let p=await open("owner","directory");
   assert.equal(await p.locator("#dir-list tbody tr").count(),2);
   assert.match(await p.locator("#dir-list").innerText(),/<img src=x onerror=window.__xss=1>/,"hostile name is shown as text");
   await p.locator("#open-EMP-001").click();
   await p.waitForSelector("#salary-form");assert.match(await p.locator("#dir-detail").innerText(),/\+880171000001/);
   await p.locator("#sal-base").fill("32000.50");await p.locator("#salary-form button[type=submit]").click();
   await p.waitForFunction(()=>window.CORE10_E2E.calls.some(c=>c.name==="wf_set_salary_structure_v1"));
   let c=(await calls(p)).find(x=>x.name==="wf_set_salary_structure_v1");assert.equal(c.args.p_base,32000.5);assert.equal(c.args.p_business,101);assert.match(c.args.p_request,/^sal-[0-9a-f]{24}$/);
   await p.locator("#n-no").fill("EMP-100");await p.locator("#n-name").fill("New Hire");await p.locator("#n-nid").fill("4321");
   await p.locator("#emp-save").click();
   await p.waitForFunction(()=>window.CORE10_E2E.calls.some(x=>x.name==="wf_save_employee_v1"));
   c=(await calls(p)).find(x=>x.name==="wf_save_employee_v1");assert.equal(c.args.p_data.employee_no,"EMP-100");assert.equal(c.args.p_data.national_id_last4,"4321");assert.equal(c.args.p_employee_id,null);
   await p.locator("#wf-biz").selectOption("102");await p.waitForFunction(()=>/business #102/.test(document.querySelector("#wf-status").textContent));
   assert.ok((await calls(p)).some(x=>x.name==="wf_read_overview_v1"&&x.args.p_business===102));
   await done(p,"directory/owner");
   // --- Directory (manager) hides payroll nav and owner-only forms
   p=await open("manager","directory");
   assert.equal(await p.locator("#emp-form").count(),0,"manager cannot see employee create form");
   assert.equal(await p.locator("#salary-form").count(),0);
   assert.equal(await p.locator('[data-nav="payroll"]').isHidden(),true);
   await done(p,"directory/manager");
   // --- Attendance
   p=await open("owner","attendance");
   assert.equal(await p.locator("#att-list tbody tr").count(),3);
   assert.equal(await p.locator("#corr-EMP-001-2026-10-21").count(),1);
   assert.equal(await p.locator("#corr-EMP-001-2026-10-05").count(),0,"locked day cannot be corrected");
   await p.locator("#corr-EMP-001-2026-10-21").click();await p.locator("#c-out").fill("18:00");await p.locator("#c-reason").fill("device missed the exit tap");
   await p.locator("#corr-form button[type=submit]").click();
   await p.waitForFunction(()=>window.CORE10_E2E.calls.some(x=>x.name==="wf_request_correction_v1"));
   c=(await calls(p)).find(x=>x.name==="wf_request_correction_v1");assert.equal(c.args.p_new_out,"2026-10-21T18:00:00+06:00");assert.equal(c.args.p_new_in,null);
   await p.locator("#ot-EMP-001-2026-10-15").click();await p.locator("#ot-min").fill("60");await p.locator("#ot-form button[type=submit]").click();
   await p.waitForFunction(()=>window.CORE10_E2E.calls.some(x=>x.name==="wf_decide_overtime_v1"));
   assert.equal((await calls(p)).find(x=>x.name==="wf_decide_overtime_v1").args.p_minutes,60);
   await p.locator("#corr-approve-5").click();await p.waitForFunction(()=>window.CORE10_E2E.calls.some(x=>x.name==="wf_decide_correction_v1"));
   await p.locator("#imp-text").fill("EMP-001,2026-11-03T09:00:00+06:00,in\nEMP-001,2026-11-03T18:00:00+06:00,out");await p.locator("#imp-run").click();
   await p.waitForFunction(()=>window.CORE10_E2E.calls.some(x=>x.name==="wf_import_punches_v1"));
   c=(await calls(p)).find(x=>x.name==="wf_import_punches_v1");assert.equal(c.args.p_punches.length,2);assert.equal(c.args.p_site,1001);assert.equal(c.args.p_source,"manual");
   await done(p,"attendance/owner");
   // --- Shifts & Leave
   p=await open("manager","leave");
   assert.match(await p.locator("body").innerText(),/Night/);assert.match(await p.locator("body").innerText(),/\(\+1d\)/,"overnight shift flagged");
   assert.equal(await p.locator("#shift-save-form").count(),0,"manager cannot define shifts");
   await p.locator("#lv-approve-7").click();await p.waitForFunction(()=>window.CORE10_E2E.calls.some(x=>x.name==="wf_decide_leave_v1"&&x.args.p_decision==="approve"));
   await p.locator("#lr-reason").fill("family function");await p.locator("#lv-submit").click();
   await p.waitForFunction(()=>window.CORE10_E2E.calls.some(x=>x.name==="wf_request_leave_v1"));
   await done(p,"leave/manager");
   p=await open("owner","leave");assert.equal(await p.locator("#shift-save-form").count(),1);
   await p.locator("#sh-newcode").fill("EVE");await p.locator("#sh-newname").fill("Evening");await p.locator("#shift-save-form button[type=submit]").click();
   await p.waitForFunction(()=>window.CORE10_E2E.calls.some(x=>x.name==="wf_save_shift_v1"));
   c=(await calls(p)).find(x=>x.name==="wf_save_shift_v1");assert.equal(c.args.p_expected_version,0);assert.equal(c.args.p_shift.code,"EVE");
   await done(p,"leave/owner");
   // --- Payroll
   p=await open("owner","payroll");
   await p.locator("#pay-preview-btn").click();await p.waitForSelector("#pay-preview table");
   assert.match(await p.locator("#pay-preview").innerText(),/no salary structure/i);assert.match(await p.locator("#pay-preview").innerText(),/PREVIEW ONLY/);
   assert.match(await p.locator("body").innerText(),/Approved\/Frozen does NOT mean Paid/);
   await p.locator("#pay-draft").click();await p.waitForFunction(()=>window.CORE10_E2E.calls.some(x=>x.name==="wf_create_payroll_draft_v1"));
   await p.waitForSelector("#act-review");await p.locator("#act-review").click();
   await p.waitForSelector("#act-approve");assert.match(await p.locator("#pay-detail").innerText(),/NOT TRACKED/);
   await p.locator("#act-approve").click();await p.waitForSelector("#act-freeze");await p.locator("#act-freeze").click();
   await p.waitForSelector("#act-amend");
   assert.deepEqual((await calls(p)).filter(x=>x.name==="wf_payroll_transition_v1").map(x=>x.args.p_action),["review","approve","freeze"]);
   await p.locator("#adv-approve-3").click();await p.waitForFunction(()=>window.CORE10_E2E.calls.some(x=>x.name==="wf_decide_advance_v1"));
   await done(p,"payroll/owner");
   p=await open("manager","payroll");assert.match(await p.locator("body").innerText(),/restricted to authorised owners/i);
   assert.equal(await p.locator("#pay-preview-btn").count(),0);assert.ok(!(await calls(p)).some(x=>/payroll_preview|payroll_runs/.test(x.name)),"manager UI never calls payroll RPCs");
   await done(p,"payroll/manager");
   // --- Reports + export
   p=await open("owner","reports");
   await p.waitForSelector("#rep-out table");await p.locator("#rep-reg").click();await p.waitForFunction(()=>/register/i.test(document.querySelector("#rep-out").innerText));
   await p.locator("#rep-int").click();await p.waitForFunction(()=>/ALL CHECKS PASS/.test(document.querySelector("#rep-out").innerText));
   await p.locator("#exp-att").click();await p.waitForSelector("#csv-link");assert.match(await p.locator("#csv-link").innerText(),/core10-workforce-attendance.csv \(2 rows\)/);
   await done(p,"reports/owner");
   p=await open("manager","reports");assert.equal(await p.locator("#rep-reg").count(),0);assert.equal(await p.locator("#exp-reg").count(),0);
   await done(p,"reports/manager");
   // --- My Work (employee)
   p=await open("employee","self");
   await p.locator("#slip-21").click();await p.waitForFunction(()=>/does not confirm that payment was made/.test(document.body.innerText));
   assert.equal(await p.locator('[data-nav="payroll"]').isHidden(),true);assert.equal(await p.locator('[data-nav="reports"]').isHidden(),true);
   await p.locator("#adv-amt").fill("3000");await p.locator("#adv-inst").fill("1000");await p.locator("#adv-submit").click();
   await p.waitForFunction(()=>window.CORE10_E2E.calls.some(x=>x.name==="wf_request_advance_v1"));
   assert.equal((await calls(p)).find(x=>x.name==="wf_request_advance_v1").args.p_employee,null,"employee advance is always self");
   await done(p,"self/employee");
   console.log("PASS A051 real DOM "+width+"px: directory, attendance, shifts/leave, payroll, reports, my-work; role projection; no overflow/XSS/external calls");
  }
 }finally{await browser.close();await new Promise(r=>server.close(r))}
})().catch(e=>{console.error(e);process.exitCode=1});
