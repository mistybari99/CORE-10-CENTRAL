"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const root = path.resolve(__dirname,"..","..");
const up = fs.readFileSync(path.join(root,"internal/migrations/0013_np01_journal_truncate_guard.up.sql"),"utf8");
const down = fs.readFileSync(path.join(root,"internal/migrations/0013_np01_journal_truncate_guard.down.sql"),"utf8");
const journalTables = [
  "audit_chain_heads_v1",
  "canonical_audit_events_v1",
  "access_change_events_v1",
  "approval_requests",
  "approval_events",
  "approval_policy_versions_v1",
  "approval_routes_v1",
  "approval_stage_receipts_v1",
  "approval_delegations_v1"
];

test("B-005 journal guard is a BEFORE TRUNCATE statement trigger for every protected table",()=>{
  assert.match(up,/RAISE EXCEPTION 'core10_journal_truncate_denied:%'/);
  assert.match(up,/ERRCODE\s*=\s*'42501'/);
  assert.match(up,/SET\s+search_path\s*=\s*pg_catalog\s*,\s*core10/i);
  assert.match(up,/REVOKE ALL ON FUNCTION core10\._deny_np01_journal_truncate_v1\(\)/i);
  for(const [index, table] of journalTables.entries()){
    const name="np01_truncate_guard_"+String(index+1).padStart(2,"0")+"_v1";
    assert.match(up,new RegExp("CREATE\\s+TRIGGER\\s+"+name+"\\s+BEFORE\\s+TRUNCATE\\s+ON\\s+core10\\."+table+"\\s+FOR\\s+EACH\\s+STATEMENT","i"),table);
    assert.match(down,new RegExp("DROP\\s+TRIGGER\\s+IF\\s+EXISTS\\s+"+name+"\\s+ON\\s+core10\\."+table,"i"),table);
  }
  assert.match(down,/DROP FUNCTION IF EXISTS core10\._deny_np01_journal_truncate_v1\(\)/i);
});
test("B-005 guard does not weaken the immutable audit and approval row triggers",()=>{
  assert.doesNotMatch(up,/DISABLE\s+TRIGGER|DROP\s+TRIGGER|ALTER\s+TABLE.*DISABLE/i);
  assert.doesNotMatch(up,/GRANT\s+.*\s+TO\s+(PUBLIC|anon)/i);
});
