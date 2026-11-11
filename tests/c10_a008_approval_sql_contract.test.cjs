'use strict';
const fs = require('node:fs');
const assert = require('node:assert/strict');
const { test } = require('node:test');
// Static source-contract checks only. These do NOT execute SQL or prove PostgreSQL RLS.
const sql = fs.readFileSync('internal/enterprise-sql/c10_a008_atomic_approval_draft.sql', 'utf8');
const checks = [
 ['explicitly non-production', /NOT a production migration/i],
 ['request has composite business tenant FK', /FOREIGN KEY\s*\(business_id,tenant_id\)\s*REFERENCES\s+c10_demo\.businesses\(id,tenant_id\)/i],
 ['request status constrained', /CHECK\s*\(status IN \('pending','approved','rejected','deferred'\)\)/i],
 ['event idempotency unique per request', /UNIQUE\s*\(request_id,idempotency_key\)/i],
 ['request RLS enabled', /ALTER TABLE c10_demo\.approval_requests ENABLE ROW LEVEL SECURITY/i],
 ['event RLS enabled', /ALTER TABLE c10_demo\.approval_events ENABLE ROW LEVEL SECURITY/i],
 ['request read scoped', /CREATE POLICY approval_request_read[\s\S]*?USING\s*\(c10_demo\.can_see_business\(tenant_id,business_id\)\)/i],
 ['event read scoped', /CREATE POLICY approval_event_read[\s\S]*?USING\s*\(c10_demo\.can_see_business\(tenant_id,business_id\)\)/i],
 ['database actor identity', /v_actor\s*:=\s*c10_demo\.actor_uid\(\)/i],
 ['request row lock', /WHERE id=p_request FOR UPDATE/i],
 ['authorization and self-approval denied', /NOT c10_demo\.can_manage\(v_req\.tenant_id,v_req\.business_id\)[\s\S]*?v_req\.created_by=v_actor/i],
 ['idempotent replay validates actor and action', /v_previous\.actor_id<>v_actor OR v_previous\.action<>p_action/i],
 ['pending only transitions', /IF v_req\.status<>'pending' THEN RAISE EXCEPTION/i],
 ['event write returns ID', /INSERT INTO c10_demo\.approval_events[\s\S]*?RETURNING id INTO v_event/i],
 ['no direct authenticated table writes', /REVOKE ALL ON c10_demo\.approval_requests,c10_demo\.approval_events FROM PUBLIC,anon,authenticated/i],
 ['function execution restricted to authenticated', /REVOKE ALL ON FUNCTION c10_demo\.decide_approval\(bigint,text,text\) FROM PUBLIC,anon;[\s\S]*?GRANT EXECUTE ON FUNCTION c10_demo\.decide_approval\(bigint,text,text\) TO authenticated/i]
];
for (const [name, pattern] of checks) test(name, () => assert.match(sql, pattern));
