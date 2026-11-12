import test from 'node:test';
import assert from 'node:assert/strict';
import {createGov002SessionBoundReviewClient} from '../internal/enterprise-client/c10_gov002_session_bound_review_v1.mjs';
const names=['listStatus','listExceptions','listActivity','decideApproval','withdrawApproval',
 'requestException','decideException','withdrawException','exportActivityCsv',
 'listStatusPage','listExceptionsPage','listActivityPage'];
function setup(){
 let uid='maker-101',callback,unsubscribed=0,events=[];
 const auth={
  async getUser(){return uid?{data:{user:{id:uid}}}:{error:{status:401},data:null};},
  onAuthStateChange(fn){callback=fn;return {data:{subscription:{unsubscribe(){unsubscribed++;}}}};}
 };
 const calls=[];
 const review={};for(const n of names)review[n]=async args=>{calls.push([n,args]);return {name:n,args};};
 const invalid=[];
 const guard=createGov002SessionBoundReviewClient({supabaseClient:{auth},reviewClient:review,
  onInvalidated:(why)=>invalid.push(why)});
 return {guard,calls,invalid,review,setUid:v=>{uid=v;},event:(e,user=uid)=>callback(e,{user:user?{id:user}:null}),
  unsubscribed:()=>unsubscribed};
}
test('fresh signed actor is pinned across read, RPC and report, without client authorization',async()=>{
 const x=setup();for(const n of names){const result=await x.guard[n]({businessId:101});assert.equal(result.name,n);}
 assert.equal(x.calls.length,names.length);
 assert.equal(x.guard.getState().actorBound,true);assert.equal(x.guard.getState().invalidated,false);
 x.event('TOKEN_REFRESHED','maker-101');
 await x.guard.listStatus({businessId:101});assert.equal(x.calls.length,names.length+1);
 x.guard.destroy();assert.equal(x.unsubscribed(),1);x.guard.destroy();assert.equal(x.unsubscribed(),1);
 await assert.rejects(x.guard.listStatus({businessId:101}),/gov002_session_invalidated/);
});
test('sign-out invalidates a completed first read AND delayed in-flight network data',async()=>{
 const x=setup();await x.guard.listStatus({businessId:101});
 let release,started;const entered=new Promise(resolve=>started=resolve);
 x.review.listStatus=async()=>{started();return await new Promise(resolve=>{release=resolve;});};
 const inFlight=x.guard.listStatus({businessId:101});
 await entered;
 x.event('SIGNED_OUT',null);
 release([{business_id:101,request_id:100}]);
 await assert.rejects(inFlight,/gov002_session_invalidated/);
 assert.deepEqual(x.invalid,['session_changed']);
 await assert.rejects(x.guard.decideApproval({requestId:1}),/gov002_session_invalidated/);
 assert.equal(x.calls.length,1);
 x.guard.destroy();
});
test('a different account after initial read fails closed without calling new business RPC',async()=>{
 const x=setup();await x.guard.listStatus({businessId:101});x.setUid('foreign-202');
 await assert.rejects(x.guard.decideApproval({requestId:2,action:'approve'}),/gov002_session_invalidated/);
 assert.deepEqual(x.invalid,['actor_changed']);assert.equal(x.calls.length,1);
});
test('auth event detects changed user and prevents late report, not just visible UI tabs',async()=>{
 const x=setup();await x.guard.listStatus({businessId:101});
 x.event('SIGNED_IN','different');
 assert.equal(x.guard.getState().invalidated,true);
 await assert.rejects(x.guard.exportActivityCsv({businessId:101}),/gov002_session_invalidated/);
 assert.equal(x.calls.length,1);
});
test('missing subscriptions or no signed session fail closed',async()=>{
 const review={};for(const n of names)review[n]=async()=>[];
 assert.throws(()=>createGov002SessionBoundReviewClient({supabaseClient:{auth:{getUser:async()=>({})}},reviewClient:review}),/signed_session_change_subscription_required/);
 const x=setup();x.setUid(null);
 await assert.rejects(x.guard.listStatus({businessId:101}),/gov002_session_invalidated/);
 assert.equal(x.calls.length,0);assert.deepEqual(x.invalid,['session_unavailable']);x.guard.destroy();
});

test('same actor re-login is a new session and fails closed, token refresh is not',async()=>{
 const x=setup();await x.guard.listStatus({businessId:101});
 x.event('TOKEN_REFRESHED','maker-101');assert.equal(x.guard.getState().invalidated,false);
 x.event('SIGNED_IN','maker-101');assert.equal(x.guard.getState().invalidated,true);
 await assert.rejects(x.guard.listStatus({businessId:101}),/gov002_session_invalidated/);x.guard.destroy();
});