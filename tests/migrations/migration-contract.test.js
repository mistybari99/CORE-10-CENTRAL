"use strict";
// Static contract for internal/migrations (DEC-01). Run: node --test tests/migrations
const test=require("node:test"),assert=require("node:assert"),fs=require("node:fs"),path=require("node:path");
const dir=path.join(__dirname,"..","..","internal","migrations");
const files=fs.readdirSync(dir).filter(f=>/\.sql$/.test(f)).sort();
const ups=files.filter(f=>f.endsWith(".up.sql"));
const body=f=>fs.readFileSync(path.join(dir,f),"utf8").replace(/--.*$/gm,"");

test("every file is NNNN_name.(up|down).sql",()=>{
 for(const f of files)assert.match(f,/^[0-9]{4}_[a-z0-9_]+\.(up|down)\.sql$/,f);
});
// Reserved ranges (docs/coordination/MIGRATION_RESERVATIONS.json) let two builders add migrations
// without number collisions. Numeric order is apply order; run.sh refuses out-of-order application.
const reservations=JSON.parse(fs.readFileSync(path.join(__dirname,"..","..","docs","coordination","MIGRATION_RESERVATIONS.json"),"utf8")).ranges;
test("reserved ranges are ordered and do not overlap",()=>{
 reservations.forEach((r,i)=>{
  assert.ok(Number.isInteger(r.from)&&Number.isInteger(r.to)&&r.from>=1&&r.to>=r.from&&r.to<=9999,`bad range ${JSON.stringify(r)}`);
  if(i)assert.ok(r.from>reservations[i-1].to,`range ${r.from}-${r.to} overlaps or is out of order`);
 });
});
test("versions are unique, inside a reserved range, and each has a rollback",()=>{
 const seen=new Set();
 for(const f of ups){
  const v=Number(f.slice(0,4));
  assert.ok(!seen.has(v),`duplicate version ${f}`); seen.add(v);
  assert.ok(files.includes(f.replace(".up.sql",".down.sql")),`no down for ${f}`);
  assert.ok(reservations.some(r=>v>=r.from&&v<=r.to),`${f} is outside every reserved range`);
 }
 assert.ok(seen.has(1),"0001 must exist");
});
test("canonical migrations never create or alter objects outside core10",()=>{
 for(const f of files){
  const sql=body(f);
  assert.doesNotMatch(sql,/\b(create|alter|drop)\s+(or\s+replace\s+)?(table|function|view|schema|policy|trigger|index|type)\s+(if\s+(not\s+)?exists\s+)?(public|c10_demo|auth|storage)\b/i,`${f} touches a non-core10 schema`);
  assert.doesNotMatch(sql,/\bgrant\b[^;]*\bto\s+(public|anon)\b/i,`${f} grants to PUBLIC/anon`);
 }
});
test("every SECURITY DEFINER function pins search_path",()=>{
 for(const f of ups){
  for(const fn of body(f).split(/create\s+(?:or\s+replace\s+)?function/i).slice(1)){
   const head=fn.split(/\$\$|\$[a-z_]+\$/i)[0]+(fn.split(/\$\$|\$[a-z_]+\$/i)[2]||"");
   if(/security\s+definer/i.test(head))assert.match(head,/set\s+search_path/i,`${f}: SECURITY DEFINER without search_path`);
  }
 }
});
test("every core10 table enables row level security and revokes PUBLIC",()=>{
 for(const f of ups){
  const sql=body(f);
  for(const m of sql.matchAll(/create\s+table\s+(core10\.[a-z0-9_]+)/gi)){
   const t=m[1].replace(".","\\.");
   assert.match(sql,new RegExp(`alter\\s+table\\s+${t}\\s+enable\\s+row\\s+level\\s+security`,"i"),`${f}: ${m[1]} without RLS`);
   assert.match(sql,new RegExp(`revoke\\s+all\\s+on\\s+[^;]*${t}[^;]*from\\s+public`,"i"),`${f}: ${m[1]} not revoked from PUBLIC`);
  }
 }
});
