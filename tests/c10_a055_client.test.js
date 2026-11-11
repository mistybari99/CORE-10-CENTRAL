// C10-A055 client/UI contract test. Needs the disposable DB (PGHOST/PGDATABASE env) already loaded by tests/c10_a055_load.sh.
"use strict";
const assert=require("node:assert/strict"),fs=require("node:fs"),path=require("node:path"),cp=require("node:child_process");
const root=path.resolve(__dirname,"..");
const API=require(path.join(root,"core10-asset-maintenance-client.js"));
const CAT=require(path.join(root,"core10-asset-maintenance-catalog.js"));
const rd=(f)=>fs.readFileSync(path.join(root,f),"utf8");
const psql=(sql)=>cp.execFileSync("psql",["-X","-q","-At","-F","\t","-v","ON_ERROR_STOP=1","-c",sql],{encoding:"utf8"}).trim().split("\n").filter(Boolean).map(l=>l.split("\t"));
let n=0;const pass=(m)=>{n++;console.log("PASS "+m)};

// ---- 1. allow-list == live SQL signatures, argument by argument (names, order, nullability class via defaults ignored) ----
const rows=psql(`SELECT p.proname, pg_get_function_arguments(p.oid) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='c10_demo' AND (p.proname ~ '^am_.*_v1$' OR p.proname='read_asset_maintenance_business_summary_v1') ORDER BY 1`);
const sql=new Map(rows.map(([name,args])=>[name,args.split(/,\s*(?![^()]*\))/).map(a=>a.trim().split(/\s+/)[0])]));
const spec=new Set(API.NAMES);
assert.deepEqual([...sql.keys()].filter(k=>!spec.has(k)),[],"SQL public RPCs missing from the client allow-list");
assert.deepEqual(API.NAMES.filter(k=>!sql.has(k)),[],"client allow-list names an RPC that does not exist in SQL");
for(const name of API.NAMES)assert.deepEqual(Object.keys(API.SPEC[name].a),sql.get(name),"argument names/order differ for "+name);
pass(API.NAMES.length+" RPCs: client allow-list == SQL signatures (names and argument order)");

// ---- 2. every allow-listed RPC is executable by authenticated, never by anon/PUBLIC; helpers are not ----
const grants=psql(`SELECT p.proname, has_function_privilege('authenticated',p.oid,'EXECUTE'), has_function_privilege('anon',p.oid,'EXECUTE')
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='c10_demo' AND p.proname ~ '^(am_|ami_|read_asset_maintenance)'`);
for(const [name,auth,anon] of grants){
 assert.equal(anon,"f","anon must not execute "+name);
 if(spec.has(name))assert.equal(auth,"t","authenticated must execute "+name);
 else if(name.startsWith("ami_"))assert.equal(auth,"f","internal helper exposed to authenticated: "+name);
}
pass("grants: public RPCs authenticated-only, internal ami_* helpers locked, anon has nothing");

// ---- 3. contract document lists exactly the same public RPC names ----
const doc=rd("docs/architecture/C10_A055_RPC_CONTRACT.md");
const docNames=new Set(doc.match(/\b(?:am_[a-z_]+_v1|read_asset_maintenance_business_summary_v1)\b/g));
assert.deepEqual(API.NAMES.filter(x=>!docNames.has(x)),[],"RPC missing from the contract document");
pass("RPC contract document covers every allow-listed RPC");

// ---- 4. catalog parity: help text for every policy key (and no stale keys); bilingual; all error codes labelled ----
const keys=psql("SELECT key FROM c10_demo.am_policy_catalog ORDER BY key").map(r=>r[0]);
const help=Object.keys(CAT.POLICY_HELP).sort();
assert.deepEqual(keys.filter(k=>!help.includes(k)),[],"policy keys without help text");
assert.deepEqual(help.filter(k=>!keys.includes(k)),[],"help text for unknown policy keys");
for(const k of keys){const h=CAT.POLICY_HELP[k];
 for(const f of ["label","what","why","when","example","risk"]){assert.ok(Array.isArray(h[f])&&h[f].length===2&&h[f][0]&&h[f][1],"bilingual "+f+" for "+k);
  if(f!=="example"&&f!=="risk")assert.match(h[f][1],/[\u0980-\u09FF]/,"Bangla script in "+f+" for "+k);}}
pass(keys.length+" policy keys: help parity with SQL catalog, every text in English and Bangla");
const sqlSrc=fs.readdirSync(path.join(root,"internal/enterprise-sql")).filter(f=>/^c10_a055_assets_.*\.sql$/.test(f)).map(f=>rd("internal/enterprise-sql/"+f)).join("\n");
const codes=new Set([...sqlSrc.matchAll(/RAISE EXCEPTION '(am_[a-z0-9_]+)'/g)].map(m=>m[1]));
const unl=[...codes].filter(c=>!Object.prototype.hasOwnProperty.call(CAT.ERRORS,c));
assert.deepEqual(unl,[],"SQL error codes without a bilingual message");
for(const [c,v] of Object.entries(CAT.ERRORS))assert.match(v[1],/[ঀ-৿]/,"Bangla message for "+c);
pass(codes.size+" SQL error codes all have English + Bangla messages");

// ---- 5. no unsafe sinks in UI sources; pages are CSP-strict, inline-script free ----
const app=rd("core10-asset-maintenance-app.js")+rd("core10-asset-maintenance-client.js")+rd("core10-asset-maintenance-catalog.js");
for(const [rx,why] of [[/\.innerHTML\b|\.outerHTML\b|insertAdjacentHTML|document\.write/,"HTML string sink"],[/\beval\s*\(|new Function\s*\(/,"dynamic code"],
 [/\.from\(\s*["']/,"direct table read"],[/service[_-]?role|sb_secret/i,"service key"],[/localStorage\.setItem\([^)]*(token|jwt|session)/i,"token persistence"],[/https?:\/\/(?!www\.w3\.org)/,"hard-coded remote URL"]])
 assert.ok(!rx.test(app),"unsafe sink: "+why);
pass("UI sources: no HTML sinks, eval, table reads, service keys, token storage or remote URLs");
const pages=fs.readdirSync(root).filter(f=>/^core10-asset-maintenance-.*\.html$/.test(f));
assert.equal(pages.length,6);
for(const f of pages){const h=rd(f);
 assert.match(h,/Content-Security-Policy/);assert.match(h,/script-src 'self'/);assert.ok(!/<script(?![^>]*\bsrc=)[^>]*>[^<]/.test(h),"inline script in "+f);
 assert.ok(!/ on[a-z]+=/i.test(h),"inline handler in "+f);assert.match(h,/name="viewport"/);assert.match(h,/data-screen="/);}
pass(pages.length+" pages: strict CSP, no inline script/handlers, viewport meta");

// ---- 6. client behaviour against a fake signed client ----
(async()=>{
 const calls=[];
 const mk=(res)=>({auth:{getUser:async()=>({data:{user:{id:"11111111-1111-4111-8111-111111111111"}}})},schema:(s)=>({rpc:async(n,a)=>{calls.push([s,n,a]);return res(n,a)}})});
 const api=API.create({client:mk(()=>({data:{status:"applied"}}))});
 await api.call("am_whoami_v1",{p_business:101});assert.equal(calls[0][0],"c10_demo");
 await assert.rejects(()=>api.call("am_drop_everything",{}),{code:"RPC_NOT_ALLOWED"});
 await assert.rejects(()=>api.call("am_whoami_v1",{p_business:101,p_evil:1}),{code:"UNKNOWN_ARGUMENT"});
 await assert.rejects(()=>api.call("am_whoami_v1",{p_business:"101"}),{code:"INVALID_ARGUMENT"});
 await assert.rejects(()=>api.call("am_whoami_v1",{p_business:-1}),{code:"INVALID_ARGUMENT"});
 await assert.rejects(()=>api.call("am_save_code_v1",{p_business:101,p_request:"short",p_kind:"failure",p_code:"X",p_label:"x",p_active:true,p_reason:"abcde"}),{code:"INVALID_REQUEST_KEY"});
 // retry-safe keys: same action re-uses its key until it succeeds
 const seen=[];const flaky=API.create({client:mk((n,a)=>{seen.push(a.p_request);return seen.length===1?{error:{message:"Failed to fetch"}}:{data:{status:"applied"}}})});
 const args={p_business:101,p_kind:"failure",p_code:"ABC",p_label:"Abc",p_label_bn:null,p_active:true,p_reason:"adding code"};
 await assert.rejects(()=>flaky.call("am_save_code_v1",args),{code:"AM_NETWORK"});
 await flaky.call("am_save_code_v1",args);assert.equal(seen[0],seen[1],"retry must reuse request key");
 await flaky.call("am_save_code_v1",Object.assign({},args,{p_code:"DEF"}));assert.notEqual(seen[2],seen[0],"different payload gets a new key");
 // server error codes surface as stable codes; garbage responses are rejected
 const denied=API.create({client:mk(()=>({error:{message:"am_denied",code:"P0001"}}))});
 await assert.rejects(()=>denied.call("am_whoami_v1",{p_business:101}),{code:"am_denied"});
 const junk=API.create({client:mk(()=>({data:"<script>"}))});
 await assert.rejects(()=>junk.call("am_whoami_v1",{p_business:101}),{code:"AM_RESPONSE_REJECTED"});
 const anon=API.create({client:{auth:{getUser:async()=>({data:{user:null},error:null})},schema:()=>({rpc:async()=>({data:{}})})}});
 await assert.rejects(()=>anon.call("am_whoami_v1",{p_business:101}),{code:"AUTHENTICATED_USER_REQUIRED"});
 assert.equal(API.parseBusinessId("101"),101);assert.equal(API.parseBusinessId("1e3"),null);assert.equal(API.parseBusinessId("0"),null);assert.equal(API.parseBusinessId("101; drop"),null);
 pass("client: allow-list, argument typing, request-key reuse, error mapping, unsigned session refusal");
 console.log("A055_CLIENT_CONTRACT_PASS ("+n+" groups)");
})().catch(e=>{console.error(e);process.exit(1)});
