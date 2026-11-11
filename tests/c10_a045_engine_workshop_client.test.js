"use strict";
/* C10-A045 client contract unit suite: signed-session gate, fail-closed validation, strict responses,
 * and static guarantees (no eval/Function/fetch, no table DML, no stock/finance references). */
const assert=require("node:assert/strict"),fs=require("node:fs"),path=require("node:path");
const W=require("../core10-engine-workshop-client.js");
const good={field:"on_hand",op:"lt",threshold:12,outcome:"warn",message:"Low"};
assert.equal(W.validateDescriptor(good).ok,true);
for(const bad of [null,[],{...good,formula:"1+1"},{...good,field:"password"},{...good,op:"eval"},{...good,threshold:"12"},
  {...good,threshold:Infinity},{...good,threshold:1e12},{...good,outcome:"post_stock"},{...good,message:"x".repeat(201)},
  {...good,message:"a\u0000b"},{field:"on_hand"}])
 assert.equal(W.validateDescriptor(bad).ok,false,JSON.stringify(bad));
assert.equal(W.validateParams({threshold:30}).ok,true);
assert.equal(W.validateParams({threshold:30,outcome:"block"}).ok,true);
assert.equal(W.validateParams({formula:"x"}).ok,false);
assert.equal(W.validateParams({outcome:"nuke"}).ok,false);
let user=null,calls=[],responses={};
const schemaObj={
 rpc:async(name,args)=>{calls.push({name,args});return responses[name]?responses[name](args):{data:null,error:{code:"X",message:"no"}}},
 from(t){assert.equal(t,"businesses");return{select(){return this},order(){return this},
  limit:async()=>({data:[{id:101,tenant_id:1},{id:102,tenant_id:1}],error:null})}}
};
const api=W.create({client:{auth:{getUser:async()=>({data:{user},error:null})},
 schema(n){assert.equal(n,"c10_demo");return schemaObj}}});
(async()=>{
 await assert.rejects(()=>api.readRegistry(1),/AUTHENTICATED_USER_REQUIRED/);
 assert.equal(calls.length,0,"no RPC without a signed user");
 user={id:"verified-user"};
 responses.read_engines_v1=a=>({data:{tenant_id:a.p_tenant,server_authorized:true,operationally_certified:false,handlers:[],engines:[]},error:null});
 assert.equal((await api.readRegistry(1)).tenant_id,1);
 responses.read_engines_v1=a=>({data:{tenant_id:999,server_authorized:true,operationally_certified:false,handlers:[],engines:[]},error:null});
 await assert.rejects(()=>api.readRegistry(1),/ENGINE_REGISTRY_RESPONSE_REJECTED/,"foreign tenant response rejected");
 responses.read_engines_v1=a=>({data:{tenant_id:1,server_authorized:true,operationally_certified:true,handlers:[],engines:[]},error:null});
 await assert.rejects(()=>api.readRegistry(1),/ENGINE_REGISTRY_RESPONSE_REJECTED/,"certified claim rejected");
 responses.read_business_engines_v1=a=>({data:{business_id:a.p_business+1,tenant_id:1,server_authorized:true,operationally_certified:false,items:[]},error:null});
 await assert.rejects(()=>api.readBusiness(101),/ENGINE_BUSINESS_RESPONSE_REJECTED/,"foreign business response rejected");
 await assert.rejects(()=>api.saveDraft({tenantId:1,key:"Bad Key",name:"Name",handler:"threshold_rule_v1",descriptor:good,expectedVersion:0,requestKey:"req_12345678",reason:"Create rule"}),/INVALID_ENGINE_DRAFT/);
 await assert.rejects(()=>api.saveDraft({tenantId:1,key:"ok_key",name:"Name",handler:"threshold_rule_v1",descriptor:{...good,formula:"1"},expectedVersion:0,requestKey:"req_12345678",reason:"Create rule"}),/INVALID_ENGINE_DESCRIPTOR/);
 await assert.rejects(()=>api.saveDraft({tenantId:1,key:"ok_key",name:"Name",handler:"threshold_rule_v1",descriptor:good,expectedVersion:0,requestKey:"short",reason:"Create rule"}),/INVALID_ENGINE_REQUEST/);
 const before=calls.length;
 await assert.rejects(()=>api.assign({engineId:1,businessId:102,version:1,state:"PUBLISHED",placement:"hidden_from_menus",localEditMode:"business_owner",expected:0,requestKey:"req_12345678",reason:"Hidden with edit"}),/INVALID_ENGINE_ASSIGNMENT/);
 await assert.rejects(()=>api.assign({engineId:1,businessId:102,version:1,state:"DELETED",placement:"both",localEditMode:"business_owner",expected:0,requestKey:"req_12345678",reason:"Bad state"}),/INVALID_ENGINE_ASSIGNMENT/);
 assert.equal(calls.length,before,"invalid input never reaches the server");
 responses.assign_engine_v1=a=>({data:{status:"applied",version:1},error:null});
 const r=await api.assign({engineId:1,businessId:102,version:1,state:"PUBLISHED",params:{threshold:30},placement:"business_only",localEditMode:"central_only",expected:0,requestKey:"req_12345678",reason:"Publish to B"});
 assert.equal(r.status,"applied");
 const last=calls[calls.length-1];assert.equal(last.name,"assign_engine_v1");assert.equal(last.args.p_business,102);assert.deepEqual(last.args.p_params,{threshold:30});
 responses.assign_engine_v1=()=>({data:{status:"maybe"},error:null});
 await assert.rejects(()=>api.assign({engineId:1,businessId:102,version:1,state:"PUBLISHED",placement:"both",localEditMode:"business_owner",expected:1,requestKey:"req_12345679",reason:"Bad receipt"}),/INVALID_ENGINE_ASSIGN_RECEIPT/);
 responses.preview_engine_draft_v1=()=>({data:{advisory:true,outcome:"warn"},error:null});
 assert.equal((await api.previewDraft({tenantId:1,descriptor:good,inputs:{on_hand:8}})).outcome,"warn");
 await assert.rejects(()=>api.previewDraft({tenantId:1,descriptor:{...good,op:"x"},inputs:{on_hand:8}}),/INVALID_ENGINE_PREVIEW/);
 responses.rollback_engine_assignment_v1=()=>({data:{status:"rolled_back",config_only:false},error:null});
 await assert.rejects(()=>api.rollback({engineId:1,businessId:102,auditId:5,expected:2,requestKey:"req_rb_12345",reason:"Not config only"}),/INVALID_ENGINE_ROLLBACK_RECEIPT/);
 assert.deepEqual(api.releaseStatus(),{serverOnly:true,operationallyCertified:false,advisoryOnly:true,stockWrites:false,financeWrites:false,arbitraryCode:false});
 // ---- static safety: sources must not contain code-exec, outbound or operational-write paths ----
 const root=path.join(__dirname,"..");
 for(const f of ["core10-engine-workshop-client.js","core10-engine-workshop.js","core10-engine-workshop.html"]){
  const src=fs.readFileSync(path.join(root,f),"utf8");
  assert.ok(!/\beval\s*\(|new\s+Function|\bFunction\s*\(|\bfetch\s*\(|XMLHttpRequest|localStorage|sessionStorage|\.from\(["']micro_engine/.test(src),f+" has forbidden API");
  assert.ok(!/stock_movements|stock_summary|ledger|payment_post/i.test(src),f+" references operational tables");
 }
 const sql=fs.readFileSync(path.join(root,"internal/enterprise-sql/c10_a045_micro_engine_v1.sql"),"utf8");
 assert.ok(!/EXECUTE\s+(format|p_|v_|'|\$)/i.test(sql.replace(/--.*$/gm,"")),"SQL must not use dynamic EXECUTE");
 assert.ok(!/stock_movements|stock_summary|INSERT INTO c10_demo\.(items|sites|businesses)/i.test(sql.replace(/--.*$/gm,"")),"SQL must not touch operational tables");
 assert.ok(!/GRANT\s+(SELECT|INSERT|UPDATE|DELETE|ALL)[^;]*TO\s+(authenticated|anon)/i.test(sql),"no direct table grants");
 console.log("PASS C10-A045 client/contract unit suite");
})().catch(e=>{console.error(e);process.exitCode=1});
