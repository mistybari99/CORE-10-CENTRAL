import test from 'node:test';
import assert from 'node:assert/strict';
import {createGov002ReviewClient} from '../internal/enterprise-client/c10_gov002_signed_review_client_v1.mjs';
import {createGov002SessionBoundReviewClient} from '../internal/enterprise-client/c10_gov002_session_bound_review_v1.mjs';

function mockSupabase(rows){
 let actor='owner-one',reads=0,callback,queries=[];
 const auth={async getUser(){return {data:{user:{id:actor}}}},
  onAuthStateChange(fn){callback=fn;return {data:{subscription:{unsubscribe(){}}}}}};
 const schema=()=>({
  from(name){const q={name,params:[]};queries.push(q);
   const builder={select(v){q.params.push(['select',v]);return builder},
    eq(k,v){q.params.push(['eq',k,v]);return builder},
    order(k,o){q.params.push(['order',k,o]);return builder},
    async range(a,b){reads++;q.params.push(['range',a,b]);return {data:rows.slice(a,b+1),error:null}}};
   return builder;},
  async rpc(){return {data:123,error:null}}
 });
 return {supabase:{auth,schema},queries,getReads:()=>reads,setActor:v=>{actor=v},emit:(e)=>callback(e,{user:actor?{id:actor}:null})};
}
const sample=(n,b=101)=>({activity_id:`approval:${n}`,business_id:b,request_id:n,source_key:'source'});
test('signed PostgREST RLS range uses one scoped business and stable tie-breaker order',async()=>{
 const x=mockSupabase([sample(1),sample(2),sample(3)]);
 const client=createGov002ReviewClient(x.supabase);
 const page=await client.listActivityPage({businessId:101,offset:1,limit:2});
 assert.equal(page.business_id,101);assert.equal(page.offset,1);assert.equal(page.limit,2);
 assert.equal(page.coverage,'SIGNED_RLS_OFFSET_WINDOW_NOT_ATOMIC');
 assert.equal(page.has_more,true);assert.equal(page.rows.length,2);
 assert.equal(x.queries[0].name,'approval_activity_feed_v1');
 assert.deepEqual(x.queries[0].params.filter(z=>z[0]==='eq'),[['eq','business_id',101]]);
 assert.deepEqual(x.queries[0].params.filter(z=>z[0]==='range'),[['range',1,2]]);
 assert.deepEqual(x.queries[0].params.filter(z=>z[0]==='order').map(z=>z[1]),['occurred_at','activity_id']);
});
test('signed page read rejects other business, bad bounds, and forged scope before view result',async()=>{
 const x=mockSupabase([sample(1,201)]);const c=createGov002ReviewClient(x.supabase);
 await assert.rejects(c.listActivityPage({businessId:101,offset:0,limit:2}),/server_scope_mismatch/);
 for(const args of [{businessId:0,offset:0,limit:2},{businessId:101,offset:50001,limit:2},{businessId:101,offset:0,limit:1001}])
   await assert.rejects(c.listActivityPage(args),/invalid_page/);
});
test('session changes during SQL range are rejected, even if query returns authorized-looking rows',async()=>{
 const x=mockSupabase([sample(1)]),c=createGov002ReviewClient(x.supabase);
 const oldSchema=x.supabase.schema;
 x.supabase.schema=()=>({from(){const b={select(){return b},eq(){return b},order(){return b},async range(){x.setActor('foreign-two');return {data:[sample(1)],error:null}}};return b;},rpc(){return {data:123}}});
 await assert.rejects(c.listActivityPage({businessId:101,limit:3}),/signed_actor_changed/);
 x.supabase.schema=oldSchema;
});
test('session-bound pager aborts when auth event revokes permission mid-report',async()=>{
 const x=mockSupabase([sample(1)]),c=createGov002ReviewClient(x.supabase);
 const guard=createGov002SessionBoundReviewClient({supabaseClient:x.supabase,reviewClient:c});
 const one=await guard.listActivityPage({businessId:101,offset:0,limit:3});
 assert.equal(one.rows.length,1);x.emit('SIGNED_OUT');
 await assert.rejects(guard.listActivityPage({businessId:101,offset:0,limit:3}),/gov002_session_invalidated/);
 guard.destroy();
});