'use strict';
const assert = require('node:assert/strict');
const { createHash } = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const { inspect, readBatch } = require('./audit.cjs');
const { summarize } = require('./summary.cjs');

const base = 'modules/paperops/';
const child = base + 'field-review/chatgpt-246/';
const childCommit = '150b3d53d0f97847143a5232f084d3aef06433c8';
const matrixPath = path.join(__dirname, 'completion-matrix.jsonl');
const ownership = require('../ownership-246-1000.json');
const routing = require('../../field-routing-report.json');
const sourceCandidates = require('../../legacy-rule-candidates.json');
const trace = require('../../control-trace.json');
const obligations = require('../../control-obligations.json');
const deep = require('../deep-source-recheck-001-003.json');
const triage = require('../semantic-triage-001-003.json');
const index = entries => new Map(entries.map(row => [row.source_id, row]));
const routeById = new Map(routing.forms.flatMap(form => form.source_fields).map(row => [row.id, row]));
const proposedModules = {
  C: 'Money / Approval / Audit', W: 'Stock / Approval / Audit', R: 'Operations / Control / Audit',
  S: 'Sales / Money / Stock', F: 'Manufacturing / Master Data / Quality', P: 'Procurement / Stock / Money',
  M: 'Assets / Approval', A: 'Money / Owner Control'
};
const gapPolicy = new Set(['C02-01', 'C02-02', 'W02-01', 'W02-02', 'W03-01', 'R01-01']);
const gapSourceRule = {
  'C02-01': 'Printed empty=cash convention; candidate explicitly holds blank payment mode.',
  'C02-02': 'Yellow no_receipt and red receipt_reason_missing branches.',
  'C02-03': 'moneySrc.formOpts and hasAccounts expressions, provider permissions pending.',
  'C01-01': 'Handover and variance arithmetic and warnings; physical custody policy pending.',
  'W02-01': 'Manual declarations only; local carry-forward arithmetic is a proposed control.',
  'W02-02': 'Original yes/cash visibility; strict missing-proof policy pending.',
  'W03-01': 'Movement conditional and variance/role warnings; no original signed adjustment proof.',
  'R01-01': 'Temperature settings and warning severity, busy-day visibility and expiry source.',
  'R01-02': 'Exact historical O/n helper presence semantics for listed expressions.',
  'R01-03': 'Original R-01 voucher amount roll-up; immutable canonical Money linkage pending.',
  'R01-04': 'Original float and imprest declarations with partial continuity logic.'
};
const localTests = {
  C01: 'c01-cash-custody', C02_EXPLICIT: 'c02-account-source',
  C02_SOURCE: 'c02-account-source', ORIGINAL_YELLOW: 'receipt-severity',
  PINNED_OLD: 'source-helpers', R01_OWNED: 'r01-money-day-ledger',
  R01_SAFETY: 'r01-food-safety', R01_VOUCHER: 'r01-money-day-ledger',
  SYNTHETIC_SOURCE: 'r01-custody-order', W02_ORDER: 'w02-customer-payment',
  W02_RETURNABLES: 'w02-returnables-reconciliation', W03: 'w03-stock-count'
};

function pinnedJson(directory, filename, expected) {
  const data = fs.readFileSync(path.join(directory, filename));
  const actual = createHash('sha1').update('blob ' + data.length + '\0').update(data).digest('hex');
  assert.equal(actual, expected, 'Lane B evidence input differs from pinned review: ' + filename);
  return JSON.parse(data);
}

function build(childEvidenceDir) {
  assert.equal(summarize({ requireComplete: true }).verified_source_fields, 1000);
  const closure = pinnedJson(childEvidenceDir, 'closure-evidence.json', '0a3bd859cae71ce734d9586f905d8ac469b8817f');
  const registry = pinnedJson(childEvidenceDir, 'issue-registry.json', '0fbfdf067b21b25d203784774c7457f6e3770a0a');
  const laneA = ownership.lane_A_codex.ownership_keys;
  const b = ownership.lane_B_chatgpt;
  const laneB = [...b.critical_86_keys, ...b.mapped_150_keys, ...b.reserved_next_10_keys];
  assert.deepEqual(closure.fields.map(row => row.source_id), laneB);
  assert.equal(new Set([...laneA, ...laneB]).size, 1246);
  assert.deepEqual(new Set([...laneA, ...laneB]), new Set(routeById.keys()));
  assert.equal(laneA[303], 'R-01:cashier');
  const audited = new Map();
  for (let n = 1; n <= 20; n++) {
    const { report } = readBatch(n);
    for (const field of report.fields) audited.set(field.source_id, { report, field });
  }
  const sourceByForm = new Map(sourceCandidates.forms.map(form => [form.legacy_code, form.source]));
  const { source, supplements } = readBatch(20);
  const sources = { 'forms.js': source, ...supplements };
  const deepById = index(deep.entries ?? deep.fields);
  const semanticById = index(triage.entries ?? triage.fields);

  const rows = laneA.map((source_id, position) => {
    const { report, field } = audited.get(source_id);
    const rule = report.rules[field.rule_group];
    const issue = field.issue_id;
    const declared = ['requirements', 'visibility', 'role'].some(name => field[name] !== 'NOT_DECLARED');
    const evidence = base + 'field-review/codex-1000/batch-' + report.batch + '.json';
    return {
      source_id, lane: 'A', position: position + 1, batch: report.batch,
      source_status: 'SOURCE_DECLARATION_VERIFIED',
      source: { file: field.source_file ?? report.source.path, offset_utf16: field.evidence.offset_utf16 },
      source_rule_status: declared ? 'SOURCE_RULE_VERIFIED' : 'NOT_BUILT',
      rule_evidence: { group: field.rule_group, status_scope: declared ? 'DECLARED_REQ_SHOW_OR_ROLE' : 'GROUP_REVIEW_ONLY', behavior: rule.behavior },
      proposed_destination: field.data_origin,
      build_status: 'NOT_BUILT', evidence, issue,
      test_evidence: 'Node 22 batch source gate, see PROGRESS.md',
      blocker: 'BLOCKED_SECURITY_OR_INTEGRATION',
      final_acceptance: { canonical_integration: false, signed_runtime: false, owner_accepted: false, erp_posted: false }
    };
  });

  for (const [i, field] of closure.fields.entries()) {
    const source_id = field.source_id;
    const routed = routeById.get(source_id);
    const file = sourceByForm.get(source_id.split(':')[0]);
    const count = source_id === 'W-02:item' ? 2 : 1;
    const matches = Array.from({ length: count }, (_, occurrence) => inspect(sources[file], source_id, occurrence, count));
    const declaration = matches[0];
    assert.deepEqual([declaration.label_bn, declaration.label_en, declaration.constructor_alias],
      [routed.label_bn, routed.label_en, routed.legacy_constructor], source_id);
    if (field.source_constructor_proof)
      assert.ok(declaration.literal.includes(field.source_constructor_proof), source_id + ' closure source drift');
    const original = deepById.get(source_id);
    const semantic = semanticById.get(source_id);
    if (original) assert.ok(declaration.literal.includes(original.source_call), source_id + ' 150-field proof drift');
    assert.deepEqual(routed.critical_trace, field.critical_obligation_ids, source_id);
    for (const key of ['canonical_runtime_integrated', 'signed_tested', 'owner_accepted', 'release_authorized', 'erp_post_authorized'])
      assert.equal(field[key], false, source_id + ' unsupported acceptance');
    const gaps = registry.functional_gaps.filter(gap => gap.field_ids.includes(source_id));
    const local = field.local_nonposting_correction;
    const localTest = local && Object.entries(localTests).find(([prefix]) => local.startsWith(prefix))?.[1];
    if (local) assert.ok(localTest, 'Local test mapping required: ' + source_id);
    const conditions = matches.map(match => Object.fromEntries(['req', 'show', 'who'].map(key =>
      [key, match.literal.match(new RegExp('\\b' + key + ':([^,}]+)'))?.[1] ?? null])));
    const declared = conditions.some(row => Object.values(row).some(value => value !== null));
    rows.push({
      source_id, lane: 'B', position: i + 1, ownership_group: field.lane,
      source_status: 'SOURCE_DECLARATION_VERIFIED',
      source: { file, constructors: matches },
      source_rule_status: declared ? 'SOURCE_RULE_VERIFIED' : 'NOT_BUILT',
      rule_evidence: { conditions, gaps: gaps.map(gap => ({ id: gap.id, source: gapSourceRule[gap.id] })),
        calculation_reference: original?.candidate_calculation_body_contains_field_ref ?? null, runtime_rule_parity: false },
      data_origin: semantic?.proposed_ERP_data_origin ?? null,
      proposed_destination: proposedModules[source_id[0]],
      draft_print_target: original?.printed_destination ?? field.critical_obligation_ids.map(id =>
        trace.records.find(record => record.obligation_id === id).print_form),
      build_status: local ? 'LOCAL_SYNTHETIC_CONTROL_BUILT' : 'NOT_BUILT',
      local_control: local ?? null,
      evidence: { commit: childCommit, closure: child + 'closure-evidence.json',
        tests: localTest ? base + 'tests/chatgpt-246-' + localTest + '.test.cjs' : null,
        obligations: field.critical_obligation_ids },
      dependencies: gaps.map(gap => gap.remaining_dependency ?? gap.blocker),
      blocker: gaps.some(gap => gapPolicy.has(gap.id)) ? 'BLOCKED_OWNER_POLICY' : 'BLOCKED_SECURITY_OR_INTEGRATION',
      final_acceptance: { canonical_integration: false, signed_runtime: false, owner_accepted: false, erp_posted: false }
    });
  }

  assert.deepEqual(registry.high_risk_obligations.map(row => row.id), trace.records.map(row => row.obligation_id));
  assert.deepEqual(registry.high_risk_obligations.map(row => row.id), obligations.records.map(row => row.id));
  assert.equal(rows.length, 1246);
  return rows;
}

if (require.main === module) {
  const [directory, mode] = process.argv.slice(2);
  assert.ok(directory && ['--write', '--check'].includes(mode), 'Usage: completion-matrix.cjs <pinned Lane B evidence directory> --write|--check');
  const rows = build(directory);
  const contents = rows.map(row => JSON.stringify(row)).join('\n') + '\n';
  if (mode === '--write') fs.writeFileSync(matrixPath, contents);
  else assert.equal(fs.readFileSync(matrixPath, 'utf8'), contents, 'Completion matrix differs from pinned source evidence');
  console.log('Completion matrix: ' + rows.length + ' declaration-verified IDs, ' +
    rows.filter(row => row.build_status === 'LOCAL_SYNTHETIC_CONTROL_BUILT').length + ' local field links, zero signed or Owner-accepted.');
}
module.exports = { build };
