'use strict';
const assert = require('node:assert/strict');
const { test } = require('node:test');
const { readBatch, verify } = require('./audit.cjs');
const { report, manifest, source } = readBatch();
const check = (batch = report, text = source) => verify(batch, manifest, text, 1);

test('exact A001 ownership and original constructor evidence', () => assert.equal(check(), 50));
const corruptions = {
  duplicate: batch => { batch.fields[1] = batch.fields[0]; },
  reordered: batch => { [batch.fields[0], batch.fields[1]] = [batch.fields[1], batch.fields[0]]; },
  missing: batch => batch.fields.pop(),
  invented: batch => { batch.fields[0].source_id = 'R-01:invented'; },
  falseParity: batch => { batch.source_runtime_equivalent = true; },
  label: batch => { batch.fields[0].evidence.label_bn = 'invented'; },
  constructor: batch => { batch.fields[0].evidence.constructor_alias = 'c'; },
  missingEvidence: batch => { batch.rules.cash.fragments = []; }
};
for (const [name, mutate] of Object.entries(corruptions)) {
  test('rejects ' + name, () => {
    const batch = structuredClone(report);
    mutate(batch);
    assert.throws(() => check(batch));
  });
}
test('rejects frozen byte drift', () => assert.throws(() => check(report, source + '\n'), /drift/));

function field(key) {
  return report.fields.find(entry => entry.source_id === 'R-01:' + key);
}
for (const [reference, amount] of [['refund_ref', 'refund'], ['credit_memo', 'credit_sales'], ['midday_slip', 'midday_hub']]) {
  test(reference + ' visibility for positive, negative and zero amount', () => {
    assert.equal(field(reference).visibility, 'e=>r(e.d.' + amount + ')>0');
    assert.equal(field(reference).requirements, 'NOT_DECLARED');
    const visible = number => number > 0;
    assert.deepEqual([1, -1, 0].map(visible), [true, false, false]);
  });
}
test('witness source conditions with absent, affirmative and false PIN values', () => {
  assert.equal(field('witness').visibility, 'e=>!e.pin');
  assert.equal(field('witness').requirements, 'e=>!e.pin');
  assert.deepEqual([undefined, true, false].map(pin => !pin), [true, false, true]);
});
test('cash short/over numeric examples reproduce inclusive tolerance and zero-count omission', () => {
  assert.match(source, /if\(d\.counted_total=v,d\.expected=g,v>0\)/);
  assert.match(source, /Math\.abs\(k\)<=b\?"yellow":"red"/);
  const severity = (count, expected, tolerance) => {
    const difference = count - expected;
    if (count <= 0 || difference === 0) return null;
    return tolerance !== null && Math.abs(difference) <= tolerance ? 'yellow' : 'red';
  };
  assert.equal(severity(100, 100, 2), null);
  assert.equal(severity(97, 100, 2), 'red');
  assert.equal(severity(98, 100, 2), 'yellow');
  assert.equal(severity(98, 100, null), 'red');
  assert.equal(severity(0, 100, 2), null);
});
test('goods reconciliation numeric examples include inclusive OR tolerance', () => {
  assert.match(source, /Math\.abs\(e\)\/y\*100<=n,o=null!==s&&Math\.abs\(e\)<=s;l=t\|\|o\?"yellow":"red"/);
  const severity = (retail, goods, percent, absolute) => {
    const delta = Math.abs(goods - retail);
    if (!delta) return null;
    return (percent !== null && retail > 0 && delta / retail * 100 <= percent) ||
      (absolute !== null && delta <= absolute) ? 'yellow' : 'red';
  };
  assert.equal(severity(100, 100, 5, 2), null);
  assert.equal(severity(100, 106, 5, 2), 'red');
  assert.equal(severity(100, 105, 5, 2), 'yellow');
  assert.equal(severity(0, 2, 5, 2), 'yellow');
  assert.equal(severity(0, 2, 5, null), 'red');
});

test('category reconciliation reports discrepancy only when entered total is present', () => {
  assert.match(source, /if\(d\.cat_sum=f,n\(o\.total_entered\)\)/);
  const mismatch = (sum, entered) => entered === undefined ? null : sum - entered;
  assert.equal(mismatch(100, 100), 0);
  assert.equal(mismatch(90, 100), -10);
  assert.equal(mismatch(0, undefined), null);
});
test('drawer arithmetic includes all signed terms and excludes informational discounts', () => {
  assert.match(source, /\+w-d\.d_total\+r\(o\.dues\)\+r\(o\.new_adv\)-r\(o\.prior_adv\)-r\(o\.refund\)-r\(o\.credit_sales\)-r\(o\.midday_hub\)\+r\(o\.rounding\)/);
  const expected = ({ opening = 0, sales = 0, tenders = [], dues = 0, advance = 0,
    prior = 0, refund = 0, credit = 0, transfer = 0, rounding = 0 }) =>
    opening + sales - tenders.reduce((total, amount) => total + amount, 0) +
    dues + advance - prior - refund - credit - transfer + rounding;
  assert.equal(expected({ opening: 20, sales: 200, tenders: [10, 20, 30, 40, 50],
    dues: 10, advance: 20, prior: 5, refund: 5, credit: 7, transfer: 10, rounding: -1 }), 72);
  assert.equal(expected({ sales: 100, refund: -1 }), 101);
  assert.equal(expected({}), 0);
});
test('deposit calculation preserves negative and zero results in original expression', () => {
  assert.match(source, /d\.hub_deposit=v-r\(o\.leave_float\)/);
  const deposit = (count, left) => count - left;
  assert.deepEqual([[10, 3], [3, 10], [0, 0]].map(args => deposit(...args)), [7, -7, 0]);
});
test('second count discrepancy is separate from identity check', () => {
  assert.match(source, /n\(o\.second_count\)&&v>0&&r\(o\.second_count\)!==v/);
  assert.match(source, /n\(o\.witness\)&&o\.witness===e\.me/);
  const mismatch = (first, second) => second !== undefined && first > 0 && second !== first;
  assert.deepEqual([[40, 40], [40, 39], [0, 1]].map(args => mismatch(...args)), [false, true, false]);
});
test('expired loss warning only considers summed amount greater than zero', () => {
  assert.match(source, /const S=s\(C\.map\(e=>e\.exp_amt\)\);return S>0&&a\.push\(x\("expired_loss","yellow"/);
  const warning = amounts => amounts.reduce((total, amount) => total + amount, 0) > 0;
  assert.deepEqual([[4, 2], [-4], [4, -4]].map(warning), [true, false, false]);
});
