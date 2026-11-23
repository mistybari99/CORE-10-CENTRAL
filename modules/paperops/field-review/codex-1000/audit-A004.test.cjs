'use strict';
const assert = require('node:assert/strict');
const { test } = require('node:test');
const { readBatch, verify } = require('./audit.cjs');
const { report, manifest, source, supplements } = readBatch(4);
const cash = supplements['forms_cash.js'];
const field = key => report.fields.find(row => row.source_id === key);
test('A004 has precisely the assigned 50 source records', () => {
  assert.equal(verify(report, manifest, source, 4, supplements), 50);
});
test('credit and advance conditions preserve exact answers and nonzero exception', () => {
  assert.equal(field('C-05:over_party').requirements, 'e=>"yes"===e.d.over_credit');
  assert.equal(field('C-05:adv_diff').requirements, 'e=>"no"===e.d.adv_match');
  assert.match(cash, /"no"===e\.d\.adv_match&&0!==a\(e\.d\.adv_diff\)/);
  const warning = (answer, delta) => answer === 'no' && delta !== 0;
  assert.deepEqual([warning('no', 1), warning('yes', 1), warning('no', 0)], [true, false, false]);
});
test('oil sale references and batch disposition follow conditional branches', () => {
  for (const key of ['old_oil_amt', 'old_oil_line']) {
    assert.equal(field('R-02:' + key).visibility, 'e=>"yes"===e.d.oil_changed&&"sold"===e.d.old_oil_fate');
  }
  assert.equal(field('R-02:daytag').requirements, 'e=>"keep"===e.d.decision');
  assert.equal(field('R-02:wasted').requirements, 'e=>"drop"===e.d.decision');
  const sale = (changed, disposition) => changed === 'yes' && disposition === 'sold';
  assert.deepEqual([sale('yes', 'sold'), sale('yes', 'destroyed'), sale(undefined, 'sold')], [true, false, false]);
});
test('yield and sales conversion handle missing denominator and consumption rates', () => {
  assert.match(cash, /b=100\*g\/m/);
  assert.match(cash, /r\(o\.jalebi_sales\)&&k>0\?a\(o\.jalebi_sales\)\/k:null/);
  assert.match(cash, /a\(o\.tot_oil\)\+a\(c\.open\)-a\(c\.close\)/);
  assert.match(cash, /a\(o\.tot_syrup\)\+a\(h\.open\)-a\(h\.close\)/);
  const rate = (total, opening, closing, weight) => weight > 0 ? (total + opening - closing) / weight : null;
  assert.deepEqual([rate(10, 5, 3, 4), rate(0, 1, 3, 1), rate(10, 5, 3, 0)], [3, -2, null]);
});
test('yield warnings use inclusive OR tolerances and distinguish missing settings', () => {
  assert.match(cash, /w>0&&Math\.abs\(e\)\/w\*100<=p/);
  assert.match(cash, /Math\.abs\(e\)<=_/);
  const severity = (actual, expected, percent, kg) => {
    const gap = Math.abs(Math.round((actual - expected) * 100) / 100);
    if (gap === 0) return null;
    return (percent !== null && expected > 0 && gap / expected * 100 <= percent) ||
      (kg !== null && gap <= kg) ? 'yellow' : 'red';
  };
  assert.deepEqual([severity(100, 100, 1, 1), severity(101, 100, 1, 0), severity(101, 100, null, 1),
    severity(101, 100, null, null), severity(102, 100, 1, 1)], [null, 'yellow', 'yellow', 'red', 'red']);
});
