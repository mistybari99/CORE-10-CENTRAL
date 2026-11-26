'use strict';
const assert = require('node:assert/strict');
const { test } = require('node:test');
const { readBatch, verify } = require('./audit.cjs');
const { report, manifest, source, supplements } = readBatch(6);
const cash = supplements['forms_cash.js'];
const field = key => report.fields.find(row => row.source_id === key);
test('A006 exact 50 records', () => assert.equal(verify(report, manifest, source, 6, supplements), 50));
test('AR row balance rounds each movement and retains negative balances', () => {
  assert.match(cash, /n=T\(n\+a\(e\.inv\)-a\(e\.ret\)-a\(e\.coll\)\)/);
  const round = n => Math.round(n * 100) / 100;
  const balance = (opening, rows) => rows.reduce((n, [invoice, returned, collected]) => round(n + invoice - returned - collected), opening);
  assert.equal(balance(10, [[8,2,1],[0,0,1]]), 14);
  assert.equal(balance(1, [[0,0,5]]), -4);
  assert.equal(balance(7, []), 7);
});
test('aging and credit checks use distinct presence and excess conditions', () => {
  assert.match(cash, /c&&d!==n&&s\.push\(A\("aging_mismatch","yellow"/);
  assert.match(cash, /e\.d\.credit_stop\|\|s\.push\(A\("credit_not_stopped","red"/);
  assert.equal(field('S-06:stop_date').visibility, 'e=>!!e.d.credit_stop');
  assert.equal(field('S-06:decided_by').visibility, 'e=>!!e.d.credit_stop');
  const flags = (due, limit, stopped) => due <= limit ? [] : stopped ? ['yellow'] : ['yellow','red'];
  assert.deepEqual([flags(11,10,true),flags(11,10,false),flags(10,10,false)], [['yellow'],['yellow','red'],[]]);
});
test('return evidence is conditional and reconciliation treats one absent source as zero', () => {
  assert.equal(field('S-04:return_ref').visibility, 'e=>"returned"===e.row.outcome');
  assert.equal(field('S-04:return_ref').requirements, 'NOT_DECLARED');
  assert.match(cash, /null===d&&null===c\?"—":0===\(d\|\|0\)&&0===\(c\|\|0\)/);
  const match = (forms, sheets) => forms === null && sheets === null ? null : (forms || 0) === 0 && (sheets || 0) === 0;
  assert.deepEqual([match(0,0),match(1,0),match(0,null),match(null,null)],[true,false,true,null]);
});
test('daily cap is strict and counts duplicate source rows', () => {
  assert.match(cash, /o\.filter\(e=>r\(e\.amt\)\)\.forEach/);
  assert.match(cash, /Object\.keys\(m\)\.filter\(e=>null!==h&&m\[e\]>h\)/);
  assert.equal(field('S-04:over_approver').requirements, 'e=>e.v.over_n>0');
  const exceeded = (rows, limit) => {
    const counts = new Map();
    for (const row of rows.filter(row => row.amount !== undefined)) {
      const date = row.date ?? 'undated';
      counts.set(date, (counts.get(date) ?? 0) + 1);
    }
    return [...counts].filter(([, count]) => limit !== null && count > limit).map(([date]) => date);
  };
  const row = { order: 'synthetic-A', amount: 0 };
  assert.deepEqual(exceeded([row,row],1),['undated']);
  assert.deepEqual(exceeded([row,row],2),[]);
  assert.deepEqual(exceeded([row,row],null),[]);
});
