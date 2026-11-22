'use strict';
/* Read only frozen original R-01 form text; do NOT eval/evaluate the historical app.
 * Audit original warning identifiers with dynamic severity/identifier skipped by 163-static extractor.
 */
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const original=require('./legacy-rule-candidates.json');
const report=require('./field-review/r01-hidden-source-flags.json');
const checker=require('./r01-hidden-warning-checks.js');
const file=path.resolve(__dirname,'../../legacy/islamia-erp/forms.js');
function audit(){
 const source=fs.readFileSync(file,'utf8');
 const start=source.indexOf('e.forms["R-01"]={');
 assert.ok(start>=0,'FROZEN_R01_FORM_MISSING');
 const after=source.indexOf('e.forms[',start+1);
 const body=source.slice(start,after>=0?after:source.length);
 assert.equal(report.legacy_form,'R-01');
 assert.equal(report.original_whole_inventory_static_warning_candidates,original.totals.flag_candidates);
 const old=original.forms.find(x=>x.legacy_code==='R-01');
 assert.ok(old);
 assert.equal(old.flag_candidates.length,report.original_r01_static_warning_candidates);
 assert.ok(body.includes('calc(e){'),'R01_CALCULATOR_BODY_MISSING');
 assert.ok(body.includes('goods_money_tol_pct'),'R01_GOODS_PERCENT_POLICY_MISSING');
 assert.ok(body.includes('goods_money_tol_max'),'R01_GOODS_ABSOLUTE_POLICY_MISSING');
 assert.ok(body.includes('cash_tol'),'R01_CASH_TOLERANCE_POLICY_MISSING');
 assert.ok(body.includes('I.map('),'R01_THREE_FRIDGE_DYNAMIC_ITERATION_MISSING');
 const known=new Set(old.flag_candidates.map(x=>x.code));
 const expected=['goods_money_gap','cash_short_over','temp_out_1','temp_out_2','temp_out_3'];
 assert.deepEqual(report.branches.map(x=>x.source_flag_code),expected);
 assert.equal(report.additional_unique_r01_runtime_warning_candidates,expected.length);
 for(const row of report.branches){
  assert.ok(body.includes(row.source_pattern),'ORIGINAL_SOURCE_EXPRESSION_MISSING:'+row.source_flag_code);
  assert.ok(typeof checker[row.candidate_check]==='function',
   'CANDIDATE_CHECKER_MISSING:'+row.source_flag_code);
  assert.ok(!known.has(row.source_flag_code),
   'PREVIOUS_EXTRACTOR_ALREADY_COVERS_SOURCE_FLAG__UPDATE_GAP_REPORT:'+row.source_flag_code);
  assert.ok(row.control_status.includes('NOT_PARITY_PROVEN')||
   row.control_status.includes('ONLY'),'FALSE_PARITY_CLAIM');
 }
 assert.equal(report.complete_all_forms_warning_parity_proven,false);
 assert.equal(report.erp_posting_allowed,false);
 assert.equal(report.owner_accepted,false);
 return {r01_static_warning_candidates:old.flag_candidates.length,
  newly_found_runtime_warning_codes:expected,additional_count:expected.length,
  all_32_forms_fully_scanned_for_dynamic_warnings:false,
  source_formula_parity_approved:false,ready_for_release:false};
}
if(require.main===module)console.log(JSON.stringify(audit(),null,2));
module.exports={audit};
