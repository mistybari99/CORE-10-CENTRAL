'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {planApproval}=require('../internal/core10-approval-transition');
const base=()=>({action:'approve',request:{id:'req-1',business_id:101,created_by:'maker',status:'pending'},actor:{user_id:'reviewer',business_id:101,active:true,revoked:false,role:'approver'},idempotency_key:'unique-key-001'});
for(const action of ['approve','reject','defer']) test(action+' creates a non-posting command',()=>{
 const input=base();input.action=action;const out=planApproval(input);
 assert.equal(out.ok,true);assert.equal(out.simulation_only,true);assert.equal(out.command.expected_status,'pending');
 assert.equal(out.command.next_status,{approve:'approved',reject:'rejected',defer:'deferred'}[action]);
});
for(const [name,change,reason] of [
 ['cross business',x=>x.actor.business_id=201,'business_scope_mismatch'],
 ['revoked',x=>x.actor.revoked=true,'approver_not_authorized'],
 ['inactive',x=>x.actor.active=false,'approver_not_authorized'],
 ['staff role',x=>x.actor.role='staff','approver_not_authorized'],
 ['self approval',x=>x.actor.user_id='maker','maker_approver_conflict'],
 ['already approved',x=>x.request.status='approved','invalid_transition'],
 ['invalid idempotency',x=>x.idempotency_key='bad','invalid_identity'],
 ['invalid action',x=>x.action='delete','invalid_action'],
 ['missing actor',x=>x.actor=null,'business_scope_mismatch']
])test(name+' fails closed',()=>{const x=base();change(x);assert.deepEqual(planApproval(x),{ok:false,reason});});
test('does not mutate input',()=>{const x=base();const before=JSON.stringify(x);planApproval(x);assert.equal(JSON.stringify(x),before)});
