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
// Pack blocks let two builders add migrations in parallel without number collisions:
// 0001-0099 NP01, 0100-0199 NP02, 0200-0299 NP03A, 0300-0399 NP03B, 0400-0499 NP06, ... (see docs/coordination).
// Blocks are in dependency order, so numeric order stays a valid apply order.
test("versions are unique, contiguous inside each pack block, and each has a rollback",()=>{
 const seen=new Set(),blocks=new Map();
 for(const f of ups){
  const v=Number(f.slice(0,4));
  assert.ok(!seen.has(v),`duplicate version ${f}`); seen.add(v);
  assert.ok(files.includes(f.replace(".up.sql",".down.sql")),`no down for ${f}`);
  const b=Math.floor(v/100); if(!blocks.has(b))blocks.set(b,[]); blocks.get(b).push(v);
 }
 for(const [b,list] of blocks){
  const first=b===0?1:b*100;
  list.sort((x,y)=>x-y).forEach((v,i)=>assert.strictEqual(v,first+i,`gap in pack block ${b}: expected ${first+i}, found ${v}`));
 }
 assert.ok(ups.length>=1);
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
