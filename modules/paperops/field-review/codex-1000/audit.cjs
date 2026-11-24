'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { createHash } = require('node:crypto');

const root = path.resolve(__dirname, '../../../..');
const manifestPath = path.join(__dirname, '../ownership-246-1000.json');
function hash(text) {
  return createHash('sha256').update(text).digest('hex');
}
const cashierGuard = 'e.forms["R-01"]&&e.forms["R-01"].head&&!e.forms["R-01"].head.some(e=>"cashier"===e.id)&&e.forms["R-01"].head.push(';
function inspect(source, key, occurrence = 0, count = 1) {
  if (key === 'R-01:cashier') {
    const literal = 'u("cashier",t("ক্যাশিয়ার (Cashier)","Cashier"))';
    const mutation = cashierGuard + literal + ')';
    const offset = source.indexOf(mutation);
    assert.ok(offset >= 0 && offset === source.lastIndexOf(mutation), 'Missing or ambiguous R-01 cashier mutation');
    return { offset_utf16: offset + cashierGuard.length, literal, constructor_alias: 'u',
      label_bn: 'ক্যাশিয়ার (Cashier)', label_en: 'Cashier' };
  }
  assert.notEqual(key, 'S-04:cashier', 'Cashier mutation belongs to R-01');
  const [form, field] = key.split(':');
  const marker = 'e.forms["' + form + '"]={';
  const start = source.indexOf(marker);
  assert.ok(start >= 0, 'Missing original form: ' + form);
  const next = source.indexOf('e.forms["', start + marker.length);
  // F-02 is followed by shared recipe helper declarations before the next form.
  const helper = form === 'F-02' ? source.indexOf(';const F=[', start + marker.length) : -1;
  if (form === 'F-02') assert.ok(helper > start && (next < 0 || helper < next), 'Missing F-02 definition boundary');
  let end = helper >= 0 ? helper : next < 0 ? source.length : next;
  let constructorStart = start;
  if (form === 'F-03' && ['name', 'qty', 'unit'].includes(field)) {
    const spec = source.indexOf('e.forms["F-02"]={');
    const specEnd = source.indexOf(';const F=[', spec);
    const marker = 'O=()=>[u("item"';
    const ingredients = source.indexOf(marker, specEnd);
    assert.ok(spec >= 0 && specEnd > spec && ingredients > specEnd && ingredients < start,
      'Missing separate F-03 ingredient helper');
    const recipe = source.slice(start, end);
    for (const collection of ['a', 'b', 'c']) {
      const consumer = 'b("' + collection + '",null,O(),';
      assert.ok(recipe.includes(consumer) && recipe.indexOf(consumer) === recipe.lastIndexOf(consumer),
        'Missing or ambiguous F-03 ingredient consumer: ' + collection);
    }
    constructorStart = ingredients;
    end = start;
  }
  const formText = source.slice(constructorStart, end);
  const pattern = /([A-Za-z_$][\w$]*)\("([a-z][a-z0-9_]*)",t\("([^"]+)","([^"]+)"\)/g;
  const matches = [...formText.matchAll(pattern)].filter(match => match[2] === field);
  assert.equal(matches.length, count, 'Missing or ambiguous original constructor: ' + key);
  const match = matches[occurrence];
  assert.ok(match, 'Missing constructor occurrence: ' + key);
  let depth = 0;
  let quote = null;
  let escaped = false;
  const offset = constructorStart + match.index;
  let cursor = offset + match[1].length;
  for (; cursor < end; cursor++) {
    const character = source[cursor];
    if (quote) {
      if (escaped) escaped = false;
      else if (character === '\\') escaped = true;
      else if (character === quote) quote = null;
      continue;
    }
    if (character === '"' || character === "'" || character === '\x60') quote = character;
    else if (character === '(') depth++;
    else if (character === ')' && --depth === 0) break;
  }
  assert.equal(depth, 0, 'Unbalanced constructor: ' + key);
  assert.ok(cursor < end, 'Unterminated constructor: ' + key);
  const literal = source.slice(offset, cursor + 1);
  return { offset_utf16: offset, literal, constructor_alias: match[1], label_bn: match[3], label_en: match[4] };
}
function verify(report, manifest, source, expectedBatch, supplements = {}) {
  const keys = manifest.lane_A_codex.ownership_keys;
  const lane = manifest.lane_B_chatgpt;
  const protectedKeys = [...lane.critical_86_keys, ...lane.mapped_150_keys, ...lane.reserved_next_10_keys];
  assert.equal(keys.length, 1000);
  assert.equal(protectedKeys.length, 246);
  assert.equal(new Set([...keys, ...protectedKeys]).size, 1246);
  assert.equal(keys[0], 'R-01:board_recon');
  assert.equal(keys.at(-1), 'F-01:owner');
  assert.ok(Number.isInteger(expectedBatch) && expectedBatch >= 1 && expectedBatch <= 20);
  assert.equal(report.schema_version, 1);
  assert.equal(report.batch, 'A' + String(expectedBatch).padStart(3, '0'));
  assert.deepEqual(report.fields.map(field => field.source_id), keys.slice((expectedBatch - 1) * 50, expectedBatch * 50));
  for (const field of ['owner_accepted', 'parity_certified', 'field_parity_certified', 'source_runtime_equivalent', 'production_ready', 'erp_posted']) {
    assert.equal(report[field], false, 'False approval or missing guard: ' + field);
  }
  assert.equal(hash(source), report.source.sha256, 'Frozen source drift');
  for (const [file, digest] of Object.entries(report.source.supplements ?? {})) {
    assert.equal(hash(supplements[file]), digest, 'Frozen source drift: ' + file);
  }
  for (const field of report.fields) {
    const text = field.source_file ? supplements[field.source_file] : source;
    const repeatedTriplet = ['C-06:amt', 'C-06:date'].includes(field.source_id);
    const count = repeatedTriplet ? 3 : ['C-04:who', 'A-02:name'].includes(field.source_id) ? 2 : 1;
    assert.deepEqual(field.evidence, inspect(text, field.source_id, 0, count));
    if (count === 2) assert.deepEqual(field.alternate_evidence, inspect(text, field.source_id, 1, count));
    if (repeatedTriplet) assert.deepEqual(field.additional_evidence, [1, 2].map(index => inspect(text, field.source_id, index, count)));
    for (const [property, sourceName] of [['requirements', 'req'], ['visibility', 'show'], ['role', 'who']]) {
      const condition = field.evidence.literal.match(new RegExp('\\b' + sourceName + ':([^,}]+)'))?.[1] ?? 'NOT_DECLARED';
      assert.equal(field[property], condition, 'Original source condition mismatch: ' + field.source_id + ' ' + sourceName);
    }
    for (const key of ['type', 'requirements', 'visibility', 'role', 'collection', 'default', 'option_source', 'data_origin', 'rule_group', 'target', 'confidence']) {
      assert.ok(typeof field[key] === 'string' && field[key].length > 0, 'Missing field evidence: ' + field.source_id + ' ' + key);
    }
    assert.ok(Object.hasOwn(report.rules, field.rule_group), 'Missing rule group: ' + field.source_id);
  }
  for (const [id, rule] of Object.entries(report.rules)) {
    assert.ok(rule.fragments.length > 0, 'Missing rule evidence: ' + id);
    for (const fragment of rule.fragments) {
      const text = fragment.source_file ? supplements[fragment.source_file] : source;
      assert.equal(text.slice(fragment.offset_utf16, fragment.offset_utf16 + fragment.text.length), fragment.text);
      assert.ok(fragment.text.length > 0);
    }
  }
  return report.fields.length;
}
function readBatch(number = 1) {
  const report = JSON.parse(fs.readFileSync(path.join(__dirname, 'batch-A' + String(number).padStart(3, '0') + '.json'), 'utf8'));
  const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
  const source = fs.readFileSync(path.join(root, report.source.path), 'utf8');
  const supplements = Object.fromEntries(Object.keys(report.source.supplements ?? {}).map(file =>
    [file, fs.readFileSync(path.join(root, file), 'utf8')]));
  return { report, manifest, source, supplements };
}
if (require.main === module) {
  const number = Number(process.argv[2] ?? 1);
  const { report, manifest, source, supplements } = readBatch(number);
  console.log(report.batch + ' source evidence rows checked: ' + verify(report, manifest, source, number, supplements));
}
module.exports = { hash, inspect, readBatch, verify };
