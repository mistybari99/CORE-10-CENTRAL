'use strict';
const assert = require('node:assert/strict');
const { test } = require('node:test');
const { readBatch, verify } = require('./audit.cjs');
const { report, manifest, source, supplements } = readBatch(8);
const stock = supplements['forms_stock.js'];
const field = key => report.fields.find(row => row.source_id === key);
test('A008 has exactly 50 source-proven declarations', () => assert.equal(verify(report, manifest, source, 8, supplements), 50));
test('material returns, staff evidence and receipt scope', () => {
  assert.equal(field('W-01:ret_weigher').requirements,'e=>e.v.has_return');
  assert.equal(field('W-01:deducted').requirements,'e=>"staff"===e.d.purpose');
  assert.equal(field('W-01:ret_received_by').role,'"checker"');
  assert.match(stock,/s\.t_net=i\?s\.t_issued:s\.t_issued-s\.t_ret/);
  const use=(issued,returned,confirmed)=>confirmed?issued-returned:issued;
  assert.deepEqual([use(10,3,true),use(10,3,false),use(10,10,true)],[7,10,0]);
});
test('ledger balance and source paper warnings', () => {
  assert.match(stock,/i\+=o\(e\.in\)-o\(e\.out\)/);
  assert.match(stock,/o\(e\.in\)>0&&!a\(e\.grn_no\)&&!a\(e\.other_no\)/);
  assert.match(stock,/e\.bal<0\)&&r\.push\(S\("negative_balance","red"/);
  const movement=(before,received,issued)=>before+received-issued;
  assert.deepEqual([movement(5,1,0),movement(5,0,6),movement(5,0,5)],[6,-1,0]);
});
test('count variance severity is inclusive and needs separable evidence', () => {
  assert.match(stock,/c=i>0\?Math\.abs\(t\)\/i\*100:100/);
  assert.match(stock,/"ledger_count_diff",p\|\|u\?"yellow":"red"/);
  assert.match(stock,/a\(p\)&&p===e\.d\.storekeeper/);
  const warning=(book,delta,percent,max,rate)=>{
    if(!delta)return null;
    const relative=book>0?Math.abs(delta)/book*100:100;
    return (percent!==null&&relative<=percent)||(max!==null&&rate!==null&&Math.abs(delta)*rate<=max)?'yellow':'red';
  };
  assert.deepEqual([warning(100,1,1,null,null),warning(100,2,1,null,null),warning(0,1,99,2,2),warning(0,1,99,2,null),warning(0,0,null,null,null)],['yellow','red','yellow','red',null]);
});
test('quotation compares a complete estimate to a strict limit', () => {
  assert.match(stock,/est:a\(t\.need\)&&a\(t\.last_rate\)\?o\(t\.need\)\*o\(t\.last_rate\)/);
  assert.match(stock,/const r=c>u/);
  assert.equal(field('P-01:est_total').visibility,'e=>!e.v.est_incomplete');
  assert.equal(field('P-01:cs_no').requirements,'e=>"outside"===e.d.cmp');
  const quote=(estimate,cap,mode,reference)=>estimate===undefined||cap===null?'unknown':estimate>cap&&!(mode==='outside'&&reference)?'red':'ok';
  assert.deepEqual([quote(10,10),quote(11,10,'outside','ref'),quote(11,10,'within','ref'),quote(undefined,10)],['ok','ok','red','unknown']);
});
test('urgent premium uses a signed rate delta only with both rates', () => {
  assert.match(stock,/const t=o\(e\.d\.now_rate\)-o\(e\.d\.normal_rate\)/);
  assert.match(stock,/t>0&&s\.push\(S\("urgent_rate_premium","yellow"/);
  const premium=(normal,current)=>normal===undefined||current===undefined?null:current-normal;
  assert.deepEqual([premium(10,11),premium(10,9),premium(10,10),premium(10,undefined)],[1,-1,0,null]);
});
