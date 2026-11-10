// C10-A011 REAL PostgreSQL 17 contract tests on disposable CI database.
// Synthetic session claim via SET ROLE + GUC; NOT real signed Supabase JWT E2E.
import assert from "node:assert/strict";
import fs from "node:fs";
import {spawnSync} from "node:child_process";
let passed=0;
function sql(query,{fail=false,expect=""}={}){
 const args=["-X","-q","-A","-t","-v","ON_ERROR_STOP=1","-c",query];
 const r=spawnSync("psql",args,{encoding:"utf8",env:process.env});
 if(fail){
  assert.notEqual(r.status,0,"Expected SQL to fail: "+query);
  assert.ok(r.stderr.toLowerCase().includes(expect.toLowerCase()),"Missing expected error "+expect+": "+r.stderr);
  return r.stderr;
 }
 if(r.status!==0)throw Error("PSQL ERROR: "+r.stderr+"\n"+query.slice(0,900));
 return r.stdout.trim().split("\n").filter(Boolean).pop()||"";
}
function file(path){
 const r=spawnSync("psql",["-X","-q","-v","ON_ERROR_STOP=1","-f",path],{encoding:"utf8",env:process.env});
 if(r.status!==0)throw Error("PSQL FILE "+path+": "+r.stderr);
 return r.stdout;
}
function ok(name,fn){fn();passed++;console.log("PASS "+name)}
const OWNER="00000000-0000-4000-8000-000000000001";
const MANAGER="00000000-0000-4000-8000-000000000002";
const STAFF="00000000-0000-4000-8000-000000000003";
const OTHER_OWNER="00000000-0000-4000-8000-000000000004";
const INACTIVE="00000000-0000-4000-8000-000000000005";
const KEY="00000000-0000-4000-8001-000000000001";
const BRANCH_KEY="00000000-0000-4000-8001-000000000002";
const OLD_KEY="00000000-0000-4000-8001-000000000009";
const ident="public.business_place_create135(bigint,text,text,text,text,bigint,uuid)";
function invoke({who=OWNER,role="authenticated",business=3,kind="showroom",code="main",bn="মূল শোরুম",en="Main",unit="null",key=KEY}={}){
 const quote=x=>"'"+String(x).replaceAll("'","''")+"'";
 const literals=[business+"::bigint",quote(kind),quote(code),quote(bn),quote(en),unit,key==null?"null":quote(key)];
 return "SET ROLE "+role+"; SELECT set_config('request.jwt.claim.sub',"+quote(who)+",false); SELECT public.business_place_create135("+literals.join(",")+");";
}
function asJson(query){return JSON.parse(sql(query))}
function denied(name,q,reason){ok(name,()=>sql(q,{fail:true,expect:reason}))}
file("tests/c10_a011_replay_fixture.sql");
const rollback=fs.readFileSync("security/c10_a011_rpc_replay_ROLLBACK.sql","utf8");
const start=rollback.indexOf("CREATE OR REPLACE FUNCTION public.business_place_create135(");
const end=rollback.indexOf("end $function$;",start);
if(start<0||end<0)throw Error("Missing original live baseline RPC body in rollback");
sql(rollback.slice(start,end+"end $function$;".length));
sql("REVOKE ALL ON FUNCTION "+ident+" FROM PUBLIC,anon; GRANT EXECUTE ON FUNCTION "+ident+" TO authenticated,service_role;");
const liveHash="a3bc0655b89398e124147a6d3d8f4f41";
const fixtureHash=sql("SELECT md5(pg_get_functiondef('"+ident+"'::regprocedure));");
ok("exact unmodified production RPC body is reproducible in PG17",()=>assert.equal(fixtureHash,liveHash));
ok("existing RPC accepts mismatched replay (negative-control bug reproduced)",()=>{
 const first=asJson(invoke({key:OLD_KEY,code:"oldcode"}));assert.equal(first.dup,false);
 const replay=asJson(invoke({key:OLD_KEY,code:"changedcode"}));
 assert.equal(replay.dup,true);assert.equal(replay.id,first.id);
});
sql("DELETE FROM public.business_place_ops135; DELETE FROM public.locations;");
file("security/c10_a011_rpc_replay_candidate.sql");
ok("patched RPC remains SECURITY DEFINER with unchanged API ACL",()=>{
 const r=sql("SELECT (SELECT prosecdef FROM pg_proc WHERE oid='"+ident+"'::regprocedure)::text||'|'||has_function_privilege('anon','"+ident+"','EXECUTE')::text||'|'||has_function_privilege('authenticated','"+ident+"','EXECUTE')::text");
 assert.equal(r,"true|false|true");
});
ok("owner creates a location atomically with request receipt",()=>{
 const a=asJson(invoke());assert.equal(a.dup,false);assert.equal(a.request_matched,true);
 assert.equal(a.business_id,3);assert.equal(a.kind,"showroom");assert.equal(a.status,"setting_up");
 assert.equal(sql("select count(*) from public.locations"),"1");
 assert.equal(sql("select count(*) from public.business_place_ops135 where impact ? 'c10_create_request_v1'"),"1");
});
ok("same owner retries exact request and receives verified duplicate",()=>{
 const a=asJson(invoke());assert.equal(a.dup,true);assert.equal(a.request_matched,true);
 assert.equal(a.status,"setting_up");assert.equal(sql("select count(*) from public.locations"),"1");
});
for(const [label,change] of [
 ["changed business",{business:5}],
 ["changed kind",{kind:"factory"}],
 ["changed code",{code:"different"}],
 ["changed Bangla name",{bn:"অন্য নাম"}],
 ["changed English name",{en:"Other"}],
 ["changed operating branch",{unit:"6"}],
])denied("same UUID with "+label+" is rejected",invoke(change),"client_id_payload_mismatch");
denied("another owner cannot hijack the same UUID",invoke({who:OTHER_OWNER}),"client_id_taken");
denied("staff cannot call owner-only creation RPC",invoke({who:STAFF,key:BRANCH_KEY}),"not allowed");
denied("manager cannot create across business scope",invoke({who:MANAGER,business:5,key:BRANCH_KEY}),"not allowed");
denied("inactive owner is denied",invoke({who:INACTIVE,key:BRANCH_KEY}),"not allowed");
denied("anonymous role cannot directly EXECUTE RPC",invoke({role:"anon",key:BRANCH_KEY}),"permission denied");
denied("foreign branch ID cannot be attached to sweets business",invoke({unit:"7",key:BRANCH_KEY}),"bad_branch");
ok("management of business 3 can use existing scoped creation API",()=>{
 const a=asJson(invoke({who:MANAGER,key:BRANCH_KEY,kind:"factory",code:"factory",en:"Factory",bn:"কারখানা",unit:"6"}));
 assert.equal(a.business_id,3);assert.equal(a.org_unit_id,6);assert.equal(a.kind,"factory");
});
ok("location status can change without retry creating a second location",()=>{
 sql("UPDATE public.locations SET status='live' WHERE code='sw_main'");
 const a=asJson(invoke());assert.equal(a.dup,true);assert.equal(a.request_matched,true);
 assert.equal(a.status,"live");assert.equal(sql("SELECT count(*) FROM public.locations"),"2");
});
denied("changed payload after location edit remains rejected",invoke({code:"new_code"}),"client_id_payload_mismatch");
denied("unsafe rollback after creation is blocked",rollback,"c10_a011_rollback_blocked_after_operations");
ok("original RPC is restored only after fixture operations are cleared",()=>{
 sql("DELETE FROM public.business_place_ops135; DELETE FROM public.locations;");
 file("security/c10_a011_rpc_replay_ROLLBACK.sql");
 assert.equal(sql("SELECT md5(pg_get_functiondef('"+ident+"'::regprocedure));"),liveHash);
});
console.log("RESULT "+passed+" PASS, 0 FAIL. Synthetic PostgreSQL roles and GUC JWT claims, NO live Supabase writes.");
