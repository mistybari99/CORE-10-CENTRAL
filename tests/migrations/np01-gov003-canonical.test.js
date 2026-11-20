"use strict";
const test=require("node:test"),assert=require("node:assert/strict"),fs=require("node:fs"),path=require("node:path");
const dir=path.resolve(__dirname,"../../internal/migrations");
const up=fs.readFileSync(path.join(dir,"0016_np01_gov003_canonical_readiness.up.sql"),"utf8");
const down=fs.readFileSync(path.join(dir,"0016_np01_gov003_canonical_readiness.down.sql"),"utf8");
test("B-007 GOV003 reads ONLY canonical core10 sources under Owner-scope",()=>{
 assert.doesNotMatch(up,/CREATE TABLE|CREATE SCHEMA|CREATE VIEW/i);
 assert.doesNotMatch(up,/c10_demo|PUBLIC,anon/);
 for(const rpc of ["audit_readiness","audit_risk","audit_export"]){
  assert.ok(up.includes("CREATE FUNCTION core10.gov003_"+rpc+"_v1"));
  assert.ok(down.includes("DROP FUNCTION IF EXISTS core10.gov003_"+rpc+"_v1"));
 }
 assert.match(up,/core10\.can_manage\(/);
 assert.match(up,/core10\.verify_canonical_audit_v1\(/);
 assert.match(up,/core10\.canonical_audit_events_v1/);
 assert.match(up,/LIMIT p_limit/);
 assert.match(up,/release_certified',false/);
 assert.match(up,/NOT BETWEEN 1 AND 500/);
});
