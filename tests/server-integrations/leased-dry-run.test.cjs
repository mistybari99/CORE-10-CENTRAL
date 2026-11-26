'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {runLeasedDryRunOnce}=require('../../server/integrations/leased-dry-run-worker.cjs');
const token='00000000-0000-0000-0000-000000000001';
const row={id:9,account_id:1,is_dry_run:true,state:'claimed',lease_token:token};
function fixture(rows=[row],result='dry_run_logged'){const calls=[];return {calls,db:{async claimDryRun(...args){calls.push(['claim',...args]);return rows;},async reportDryRun(...args){calls.push(['report',...args]);return result;}}};}
test('passes exact token/account, never old report',async()=>{const f=fixture();assert.deepEqual(await runLeasedDryRunOnce({db:f.db,account:{id:1,mode:'dry_run'}}),{claimed:1,dry_run_logged:1,requeued:0,failed:0});assert.deepEqual(f.calls,[['claim',1,10],['report',1,9,token,true,false,null]]);});
test('off and live never claim',async()=>{const f=fixture();await runLeasedDryRunOnce({db:f.db,account:{id:1,mode:'off'}});await assert.rejects(runLeasedDryRunOnce({db:f.db,account:{id:1,mode:'live'}}),/dry_run_only/);assert.deepEqual(f.calls,[]);});
test('malformed batch fails before any report',async()=>{for(const bad of [{...row,account_id:2},{...row,is_dry_run:false},{...row,lease_token:null},row]){const f=fixture([row,bad]);await assert.rejects(runLeasedDryRunOnce({db:f.db,account:{id:1,mode:'dry_run'}}),/claim_invalid/);assert.equal(f.calls.length,1);}});
test('cannot claim sent from DB response',async()=>{const f=fixture([row],'sent');await assert.rejects(runLeasedDryRunOnce({db:f.db,account:{id:1,mode:'dry_run'}}),/report_invalid/);});
test('lease rejection propagates without retry',async()=>{let n=0;const db={async claimDryRun(){return [row];},async reportDryRun(){n++;throw Error('integration_lease_invalid');}};await assert.rejects(runLeasedDryRunOnce({db,account:{id:1,mode:'dry_run'}}),/lease_invalid/);assert.equal(n,1);});
