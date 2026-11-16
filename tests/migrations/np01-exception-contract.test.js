"use strict";
const {test}=require("node:test"),assert=require("node:assert/strict"),fs=require("node:fs"),path=require("node:path");
const dir=path.resolve(__dirname,"../../internal/migrations");
const up=fs.readFileSync(path.join(dir,"0015_np01_gov002_exception_triage.up.sql"),"utf8");
const down=fs.readFileSync(path.join(dir,"0015_np01_gov002_exception_triage.down.sql"),"utf8");
test("B-006 exception review is non-posting, scope-checked and appended to canonical audit",()=>{
 assert.match(up,/CREATE TABLE core10\.approval_exception_escalations_v1/);
 assert.match(up,/CREATE TABLE core10\.approval_exception_events_v1/);
 assert.match(up,/WITH \(security_invoker=true\)/);
 assert.match(up,/core10\.can_manage\(/);
 assert.match(up,/core10\._append_canonical_audit_v1\(/);
 assert.match(up,/BEFORE TRUNCATE ON core10\.approval_exception_events_v1/);
 assert.match(up,/BEFORE UPDATE OR DELETE ON core10\.approval_exception_events_v1/);
 assert.ok(up.includes("exception_ttl_exceeds_owner_policy"));
 assert.ok(!/UPDATE\s+core10\.approval_requests\s+SET/i.test(up),"cannot authorize original approval");
 assert.match(down,/DROP TABLE IF EXISTS core10\.approval_exception_events_v1/);
});
