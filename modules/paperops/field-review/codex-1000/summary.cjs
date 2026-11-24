'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { readBatch, verify } = require('./audit.cjs');

const batchName = n => 'A' + String(n).padStart(3, '0');
const reportName = n => 'batch-' + batchName(n) + '.json';

function summarize({ requireComplete = false } = {}) {
  const files = fs.readdirSync(__dirname).filter(file => /^batch-A.*\.json$/.test(file)).sort();
  assert.ok(files.length > 0 && files.length <= 20, 'Invalid report count');
  assert.deepEqual(files, files.map((_, index) => reportName(index + 1)), 'Audit reports must be consecutive starting at A001');
  if (requireComplete) assert.equal(files.length, 20, 'All 20 completed batch reports are required');

  const keys = new Set();
  const issues = new Set();
  const batches = [];
  const openSeverity = { HIGH: 0, MEDIUM: 0, LOW: 0 };
  const dependenciesBySource = {};
  let resolvedFindings = 0;
  for (const [index] of files.entries()) {
    const number = index + 1;
    const batch = batchName(number);
    const { report, manifest, source, supplements } = readBatch(number);
    assert.equal(verify(report, manifest, source, number, supplements), 50);
    const issueFile = number === 1 ? 'issues.json' : 'issues-' + batch + '.json';
    const findings = JSON.parse(fs.readFileSync(path.join(__dirname, issueFile), 'utf8'));
    const ownIssues = new Map();
    const ownSeverity = { HIGH: 0, MEDIUM: 0, LOW: 0 };
    const ownKeys = new Set(report.fields.map(field => field.source_id));
    for (const issue of findings) {
      assert.match(issue.issue_id, new RegExp('^' + batch + '-F\\d{3}$'));
      assert.ok(!issues.has(issue.issue_id), 'Duplicate finding: ' + issue.issue_id);
      issues.add(issue.issue_id);
      ownIssues.set(issue.issue_id, issue);
      assert.ok(Object.hasOwn(ownSeverity, issue.severity), 'Unknown finding severity');
      if (issue.status === 'RESOLVED_SOURCE_ATTRIBUTION') {
        const corrected = issue.corrected_source_ids ?? [issue.corrected_source_id];
        assert.ok(corrected.length > 0 && corrected.every(key => ownKeys.has(key)), 'Missing corrected ID in batch');
        resolvedFindings++;
        continue;
      }
      assert.ok(issue.source_ids.length > 0 && issue.source_ids.every(key => ownKeys.has(key)),
        'Finding references an unassigned field: ' + issue.issue_id);
      ownSeverity[issue.severity]++;
      openSeverity[issue.severity]++;
    }

    for (const field of report.fields) {
      const key = field.source_id;
      assert.ok(!keys.has(key), 'Duplicate ownership ID: ' + key);
      keys.add(key);
      assert.ok(ownIssues.get(field.issue_id)?.source_ids.includes(key), 'Unlinked field finding: ' + key);
      const sourceFile = field.source_file ?? report.source.path;
      const sourceForms = dependenciesBySource[sourceFile] ??= {};
      const form = key.split(':')[0];
      const rules = sourceForms[form] ??= {};
      const links = rules[batch + '/' + field.rule_group] ??= {
        dependency: field.data_origin,
        findings: [],
        original_field_ids: []
      };
      if (!links.findings.includes(field.issue_id)) links.findings.push(field.issue_id);
      links.original_field_ids.push(key);
    }

    batches.push({ batch, first: report.fields[0].source_id, last: report.fields.at(-1).source_id,
      fields: ownKeys.size, open_findings: ownSeverity, evidence_report: reportName(number), finding_report: issueFile });
  }

  assert.equal(keys.size, 50 * batches.length);
  if (requireComplete) assert.equal(keys.size, 1000);
  return {
    schema_version: 1,
    verified_source_fields: keys.size,
    remaining_source_fields: 1000 - keys.size,
    complete_reports: batches.length,
    resolved_attribution_findings: resolvedFindings,
    open_findings: openSeverity,
    batches,
    source_dependency_tree: dependenciesBySource,
    owner_accepted: false,
    field_parity_certified: false,
    production_ready: false
  };
}

if (require.main === module) {
  const result = summarize({ requireComplete: process.argv.includes('--complete') });
  console.log(JSON.stringify(result, null, 2));
}
module.exports = { summarize };
