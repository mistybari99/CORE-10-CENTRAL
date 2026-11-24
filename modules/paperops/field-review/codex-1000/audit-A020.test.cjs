'use strict';
const assert = require('node:assert/strict');
const { test } = require('node:test');
const { readBatch, verify } = require('./audit.cjs');
const { summarize } = require('./summary.cjs');
const { report, manifest, source, supplements } = readBatch(20);
const factory = supplements['forms_factory.js'];

test('A020 closes exactly twenty ordered source gates without certifying parity', () => {
  assert.equal(verify(report, manifest, source, 20, supplements), 50);
  assert.equal(summarize({ requireComplete: true }).verified_source_fields, 1000);
  assert.deepEqual([report.fields[0].source_id, report.fields.at(-1).source_id], ['F-04:base_use', 'F-01:owner']);
  const altered = { ...report, fields: [report.fields[1], report.fields[0], ...report.fields.slice(2)] };
  assert.throws(() => verify(altered, manifest, source, 20, supplements));
  assert.throws(() => verify({ ...report, owner_accepted: true }, manifest, source, 20, supplements), /False approval/);
});

// Typed fixture projections of the pinned expressions. Legacy coercion, roles,
// persistence and policy decisions remain outside this source-audit harness.
const present = value => value !== undefined && value !== null && value !== '' && value !== false;
const round4 = value => Math.round(value * 10_000) / 10_000;
const ratio = (value, denominator) => denominator > 0 && present(value) ? round4(value / denominator) : undefined;
const percent = (value, denominator) =>
  denominator > 0 && present(value) ? Math.round(value / denominator * 10_000) / 100 : undefined;

function yieldTrial({ input, good, second, waste }) {
  const grades = [good, second, waste];
  const total = grades.some(present) ? grades.reduce((sum, value) => sum + (value ?? 0), 0) : undefined;
  return [total, ratio(good, input), percent(second, total), percent(waste, total)];
}

test('F-04 yield preserves zero, missing values, the two rounding scales and denominator guards', () => {
  assert.deepEqual(yieldTrial({ input: 6, good: 2, second: 1, waste: 3 }), [6, 0.3333, 16.67, 50]);
  assert.deepEqual(yieldTrial({ input: 0, good: 0, second: 0, waste: 0 }), [0, undefined, undefined, undefined]);
  assert.deepEqual(yieldTrial({ input: 1 }), [undefined, undefined, undefined, undefined]);
  assert.deepEqual(yieldTrial({ input: 10, good: 1, second: 0 }), [1, 0.1, 0, undefined]);
  assert.deepEqual(yieldTrial({ input: -1, good: 1 }), [1, undefined, undefined, undefined]);
  const finite = [undefined, 0, 0.3333, Infinity].filter(Number.isFinite);
  assert.equal(round4(finite.reduce((a, b) => a + b, 0) / finite.length), 0.1667);
});

test('F-04 dash requirement and date/actor warning severities preserve the source conditions', () => {
  const required = dash => !dash;
  assert.deepEqual([required(true), required(false), required(undefined)], [false, true, true]);
  const duplicate = values => new Set(values.filter(present)).size < values.filter(present).length;
  const selfMeasurement = ({ measurer, craftsman }) => present(measurer) && measurer === craftsman;
  assert.equal(duplicate(['2026-11-22', '2026-11-23', '2026-11-24']), false);
  assert.equal(duplicate(['2026-11-22', '', '2026-11-22']), true);
  assert.equal(duplicate([undefined, '', null]), false);
  assert.equal(selfMeasurement({ measurer: 'M1', craftsman: 'M1' }), true);
  assert.equal(selfMeasurement({ measurer: 'M1', craftsman: 'M2' }), false);
  assert.equal(selfMeasurement({}), false);
  assert.match(factory, /v\("same_day_batches","yellow"/);
  assert.match(factory, /v\("measurer_is_craftsman","red"/);
});

test('F-01 price fallback and warning boundary preserve zero and missing-cost behavior', () => {
  const price = (master, estimate) => master > 0 ? master : present(estimate) ? estimate : undefined;
  const margin = (selected, cost) => present(selected) && present(cost) ? selected - cost : undefined;
  assert.equal(price(80, 90), 80);
  assert.equal(price(0, 90), 90);
  assert.equal(price(-1, 0), 0);
  assert.equal(price(undefined, ''), undefined);
  assert.deepEqual([margin(80, 81), margin(80, 80), margin(80, 79), margin(80, null)], [-1, 0, 1, undefined]);
  assert.match(factory, /i\.margin<0&&s\.push\(v\("negative_margin","yellow"/);
});

test('F-01 opinion arithmetic and checker-specific decisions fail distinctly', () => {
  const opinion = (tasters, good, average, poor) => present(tasters) ? good + average + poor - tasters : undefined;
  assert.deepEqual([opinion(3, 1, 1, 1), opinion(0, 1, 0, 0), opinion(undefined, 1, 1, 1)], [0, 1, undefined]);
  assert.match(factory, /0!==e&&s\.push\(v\("opinion_mismatch","yellow"/);
  const needChangeDetail = decision => decision === 'change';
  assert.deepEqual(['keep', 'change', 'drop', undefined].map(needChangeDetail), [false, true, false, false]);
  const selfCheck = (checker, preparer) => present(checker) && checker === preparer;
  assert.deepEqual([selfCheck('A', 'B'), selfCheck('A', 'A'), selfCheck('', '')], [false, true, false]);
  assert.match(factory, /n\.verifier===n\.preparer&&s\.push\(v\("verifier_is_preparer","red"/);
});

test('F-01 setting and trial book branches remain visible without invented policy', () => {
  const hint = (days, start) => present(days) ? present(start) ? [start, days] : '—' : 'DATA_NEEDED';
  assert.deepEqual([hint(0, '2026-11-24'), hint(2, ''), hint('', '2026-11-24')],
    [['2026-11-24', 0], '—', 'DATA_NEEDED']);
  assert.match(factory, /i\.review_hint=q,d\.push\("newprod_review_days"\)/);
  assert.match(factory, /i\.day_tag=t\|\|q/);
  assert.match(factory, /i\.trial_total=o\(h\.map\(e=>e\.amount\)\)/);
  assert.match(factory, /e\.biz\?e\.biz\.brandOpts\(K,\["other"\]\):K/);
});
