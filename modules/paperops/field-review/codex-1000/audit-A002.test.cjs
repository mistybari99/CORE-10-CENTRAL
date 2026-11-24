'use strict';
const assert = require('node:assert/strict');
const { test } = require('node:test');
const { readBatch, verify } = require('./audit.cjs');
const { report, manifest, source, supplements } = readBatch(2);
const cash = supplements['forms_cash.js'];
const field = key => report.fields.find(entry => entry.source_id === key);
const validate = (batch = report, files = supplements) => verify(batch, manifest, source, 2, files);

test('A002 original evidence and duplicate who declarations', () => {
  assert.equal(validate(), 50);
  assert.equal(field('C-04:who').evidence.label_en, 'Showroom');
  assert.equal(field('C-04:who').alternate_evidence.label_en, 'Courier or food app');
  const mutated = structuredClone(report);
  delete mutated.fields.find(entry => entry.source_id === 'C-04:who').alternate_evidence;
  assert.throws(() => validate(mutated));
  assert.throws(() => validate(report, { 'forms_cash.js': cash + '\n' }), /drift/);
});
test('positive waste turns on both conditions and blocks same-maker approval by warning', () => {
  const approval = field('R-01:waste_by');
  assert.equal(approval.visibility, 'e=>r(e.row.waste_qty)>0');
  assert.equal(approval.requirements, approval.visibility);
  assert.match(source, /r\(t\.waste_qty\)>0&&n\(t\.waste_by\)&&t\.waste_by===e\.me/);
  const warning = (quantity, approver) => quantity > 0 && !!approver && approver === 'maker';
  assert.deepEqual([warning(1, 'checker'), warning(1, 'maker'), warning(0, 'maker')], [false, true, false]);
});
test('signature requirements and checker section are separate controls', () => {
  assert.equal(field('R-01:second_sig').requirements, 'e=>!e.pin');
  assert.equal(field('R-01:second_sig').visibility, 'e=>!e.pin');
  assert.match(source, /o\.second_sig&&o\.second_sig===e\.me/);
  for (const id of ['hub_ledger', 'hub_time', 'hub_received']) assert.equal(field('R-01:' + id).role, '"checker"');
  assert.deepEqual([undefined, false, true].map(pin => !pin), [true, true, false]);
});
test('optional alternate statement text and missing statement warning', () => {
  assert.equal(field('C-04:st_other_name').visibility, 'e=>!!e.d.st_other');
  assert.equal(field('C-04:st_other_name').requirements, 'NOT_DECLARED');
  assert.equal(field('C-04:no_statement').requirements, '!1');
  assert.match(cash, /e\.d\.no_statement&&t\.push\(A\("no_statement","red"/);
  assert.deepEqual([true, false, undefined].map(Boolean), [true, false, false]);
});
test('settlement differences use cent rounding and row absolutes', () => {
  assert.match(cash, /T=e=>Math\.round\(100\*e\)\/100/);
  assert.match(cash, /r\(e\.b\)&&r\(e\.c\)\?T\(a\(e\.b\)-a\(e\.chg\)-a\(e\.c\)\):void 0/);
  assert.match(cash, /abs1:T\(s\(i\.map\(e=>Math\.abs\(e\.d1\|\|0\)\)\)\)/);
  const round = number => Math.round(100 * number) / 100;
  const settlement = ({ b, fee, c }) => b === undefined || c === undefined ? undefined : round(b - fee - c);
  assert.equal(settlement({ b: 10, fee: 1, c: 9 }), 0);
  assert.equal(settlement({ b: 10, fee: 1, c: 9.03 }), -0.03);
  assert.equal(settlement({ b: 10, fee: 1 }), undefined);
  const differences = [round(10 - 9), round(9 - 10)];
  assert.equal(differences[0] + differences[1], 0);
  assert.equal(Math.abs(differences[0]) + Math.abs(differences[1]), 2);
});
