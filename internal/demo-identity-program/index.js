"use strict";
/* A046 synthetic test registry; never a real GoTrue account or signed token. */
const fs=require("node:fs");
const path=require("node:path");
const assert=require("node:assert/strict");
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-8[0-9a-f]{3}-[0-9a-f]{12}$/;
const SITES=new Map([[1001,101],[1002,101],[1003,102],[2001,201]]);
const BUSINESSES=new Map([[101,1],[102,1],[201,2]]);
function validate(data){
 assert.equal(data.schema_version,"c10-a046-v1");
 assert.equal(data.mode,"SYNTHETIC_POSTGRES_CI_ONLY");
 assert.equal(data.lifecycle.delete_before_real_go_live,true);
 assert.equal(data.personas.length,16);
 const ids=new Set(),keys=new Set();
 for(const p of data.personas){
  assert(UUID.test(p.uid),"bad UUID "+p.key);
  assert(/^[A-Z][A-Z0-9_]+$/.test(p.key),"bad key");
  assert(!ids.has(p.uid)&&!keys.has(p.key),"duplicate identity");
  ids.add(p.uid);keys.add(p.key);
  assert(p.tenant_id===null||[1,2].includes(p.tenant_id));
  for(const k of ["business_ids","read_site_ids","post_site_ids"]){
   assert(Array.isArray(p[k])&&new Set(p[k]).size===p[k].length&&p[k].every(Number.isSafeInteger), "invalid list "+k);
  }
  for(const b of p.business_ids) assert(BUSINESSES.has(b)&&BUSINESSES.get(b)===p.tenant_id,"cross-tenant business");
  for(const s of p.read_site_ids) assert(SITES.has(s)&&p.business_ids.includes(SITES.get(s)),"cross-business site");
  for(const s of p.post_site_ids) assert(p.read_site_ids.includes(s),"post without read");
  if(!p.active)assert(p.business_ids.length===0&&p.read_site_ids.length===0,"revoked must deny");
 }
 assert(keys.has("TENANT_OWNER_A")&&keys.has("TENANT_OWNER_B")&&keys.has("REVOKED_MANAGER_A"));
 assert.equal(data.personas.find(p=>p.key==="TENANT_OWNER_A").uid,"11111111-1111-4111-8111-111111111111");
 assert.equal(data.personas.find(p=>p.key==="TENANT_OWNER_B").uid,"77777777-7777-4777-8777-777777777777");
 return true;
}
function readManifest(){
 const data=JSON.parse(fs.readFileSync(path.join(__dirname,"demo-identity-manifest-v1.json"),"utf8"));
 validate(data);return data;
}
function array(a){return "'{"+a.join(",")+"}'::bigint[]";}
function quote(v){return "'"+String(v).replace(/'/g,"''")+"'";}
function sqlMatrix(data){
 validate(data);
 let s="\\set ON_ERROR_STOP on\n\\echo C10-A046 SYNTHETIC PG17 RLS MATRIX — NOT GoTrue\n";
 s+="DO $gate$ BEGIN IF current_database() !~ '^core10_a046_(ci|local)(_|$)' THEN RAISE EXCEPTION 'C10_A046_DISPOSABLE_DATABASE_ONLY'; END IF; END $gate$;\n";
 for(const p of data.personas){
  s+="BEGIN;\nSET LOCAL ROLE authenticated;\nSELECT set_config('request.jwt.claim.sub',"+quote(p.uid)+",true);\n";
  s+="DO $check$ DECLARE bb bigint[]; ss bigint[]; pp bigint[]; BEGIN\n";
  s+="SELECT COALESCE(array_agg(id ORDER BY id),'{}'::bigint[]) INTO bb FROM c10_demo.businesses;\n";
  s+="SELECT COALESCE(array_agg(id ORDER BY id),'{}'::bigint[]) INTO ss FROM c10_demo.sites;\n";
  s+="SELECT COALESCE(array_agg(id ORDER BY id),'{}'::bigint[]) INTO pp FROM c10_demo.sites WHERE c10_demo.can_site(tenant_id,business_id,id,'stock.post');\n";
  s+="IF bb<>"+array(p.business_ids)+" OR ss<>"+array(p.read_site_ids)+" OR pp<>"+array(p.post_site_ids);
  s+=" THEN RAISE EXCEPTION 'C10_A046_SCOPE_FAIL "+p.key+" businesses % sites % post %',bb,ss,pp; END IF;\n";
  s+="END $check$;\nROLLBACK;\n";
 }
 s+="BEGIN;\nDO $check$ BEGIN IF has_schema_privilege('anon','c10_demo','USAGE') THEN RAISE EXCEPTION 'C10_A046_ANON_PRIVILEGE_LEAK'; END IF; END $check$;\n";
 s+="SET LOCAL ROLE anon;\nDO $check$ BEGIN BEGIN EXECUTE 'SELECT count(*) FROM c10_demo.businesses'; RAISE EXCEPTION 'C10_A046_ANON_PRIVILEGE_LEAK'; EXCEPTION WHEN insufficient_privilege THEN NULL; END; END $check$;\nROLLBACK;\n";
 s+="\\echo PASS: 16 synthetic persona scopes plus anon. REAL_GOTRUE_STAGE_NOT_TESTED\n";
 return s;
}
function list(data){
 validate(data);
 return ["C10-A046 | TEST-ONLY IDs (NOT LOGIN ACCOUNTS)","KEY | UUID | TENANT | BUSINESSES | READ SITES | POST SITES | ACTIVE",
 ...data.personas.map(p=>[p.key,p.uid,p.tenant_id??"-",p.business_ids.join(",")||"-",p.read_site_ids.join(",")||"-",p.post_site_ids.join(",")||"-",p.active].join(" | "))].join("\n");
}
if(require.main===module){
 const data=readManifest(),cmd=process.argv[2]||"list";
 if(cmd==="list")process.stdout.write(list(data)+"\n");
 else if(cmd==="sql")process.stdout.write(sqlMatrix(data));
 else {console.error("Usage: node internal/demo-identity-program/index.js [list|sql]");process.exitCode=2;}
}
module.exports={readManifest,validate,sqlMatrix,list};
