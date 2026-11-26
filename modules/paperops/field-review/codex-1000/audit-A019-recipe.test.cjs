'use strict';
const assert = require('node:assert/strict');
const { test } = require('node:test');
const { inspect, readBatch, verify } = require('./audit.cjs');
const partial = require('./A019-partial.json');
const draft = require('./A019-recipe-candidates.json');
const complete = require('./batch-A019.json');
const { manifest, source, supplements } = readBatch(18);
const factory = supplements['forms_factory.js'];

test('recipe helper only verifies with its original three consumers', () => {
  for (const field of draft.fields) assert.deepEqual(inspect(factory, field.source_id), field.evidence);
  const withoutPackaging = factory.replace('b("c",null,O(),', 'b("c",null,[],');
  assert.throws(() => inspect(withoutPackaging, 'F-03:qty'), /ingredient consumer: c/);
  const duplicated = factory.replace('b("c",null,O(),', 'b("c",null,O(),b("c",null,O(),');
  assert.throws(() => inspect(duplicated, 'F-03:unit'), /ingredient consumer: c/);
  assert.throws(() => inspect(factory, 'F-02:name'), /Missing or ambiguous/);
});

test('fallback name and item are complementary presence conditions', () => {
  assert.match(factory, /u\("item",t\("কাঁচামালের নাম ও আইটেম কোড","Raw material name & item code"\),\{wide:!0,req:e=>!a\(e\.row\.name\)\}\)/);
  assert.equal(draft.fields[0].requirements, 'e=>!a(e.row.item)');
  for (const field of draft.fields.slice(1)) assert.equal(field.requirements, '!0');
  const needed = (item, name) => ({ item: !name, name: !item });
  assert.deepEqual([needed('synthetic-item',undefined),needed(undefined,'synthetic name'),needed(undefined,undefined)],
    [{item:true,name:false},{item:false,name:true},{item:true,name:true}]);
});

test('rehearsal verifies replacement only under a synthetic corrected manifest', () => {
  const fixture = structuredClone(manifest);
  for (const { position, prior_id, candidate_id } of draft.expected_changes) {
    assert.ok([prior_id, candidate_id].includes(fixture.lane_A_codex.ownership_keys[position - 1]));
    fixture.lane_A_codex.ownership_keys[position - 1] = candidate_id;
  }
  const byKey = new Map([...partial.fields, ...draft.fields].map(row => [row.source_id, row]));
  const assembled = {
    ...partial,
    fields: fixture.lane_A_codex.ownership_keys.slice(900,950).map(key => byKey.get(key)),
    rules: { ...partial.rules, recipe_ingredients: draft.rule }
  };
  const legacy = structuredClone(fixture);
  for (const { position, prior_id } of draft.expected_changes) legacy.lane_A_codex.ownership_keys[position - 1] = prior_id;
  assert.throws(() => verify(assembled, legacy, source, 19, supplements));
  assert.equal(verify(assembled, fixture, source, 19, supplements), 50);
  const reordered = { ...assembled, fields: [...assembled.fields] };
  [reordered.fields[19], reordered.fields[20]] = [reordered.fields[20], reordered.fields[19]];
  assert.throws(() => verify(reordered, fixture, source, 19, supplements));
});

test('A019 complete gate uses the corrected Parent slots and preserves all recipe row contexts', () => {
  assert.equal(verify(complete, manifest, source, 19, supplements), 50);
  const recipe = complete.fields.filter(field => field.recipe_row_source);
  assert.deepEqual(recipe.map(field => field.source_id), ['F-03:name', 'F-03:qty', 'F-03:unit', 'F-03:item']);
  for (const field of recipe) {
    const row = field.recipe_row_source;
    assert.equal(factory.slice(row.offset_utf16, row.offset_utf16 + row.literal.length), row.literal);
    assert.deepEqual(row.row_contexts.map(context => [context.collection, context.min_rows_declared, context.offset_utf16]),
      [['a', 4, 18046], ['b', 5, 18345], ['c', 2, 18511]]);
  }
  const item = recipe.find(field => field.source_id === 'F-03:item');
  assert.notEqual(item.recipe_row_source.label_en, item.evidence.label_en);
  assert.equal(manifest.lane_A_codex.ownership_keys[303], 'R-01:cashier');
});
