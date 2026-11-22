'use strict';
// Deterministic source-field semantic triage. Source-structure hints are never equivalent to rule parity.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
function semanticTriage(original,batches){
 const constructorKinds={
  g:"COMPUTED_OR_DISPLAY_CANDIDATE",k:"ROW_COLLECTION",f:"DENOMINATION_COUNT",
  b:"DOCUMENT_ATTACHMENT",p:"ITEM_MASTER_LOOKUP",m:"ACTOR_OR_ROLE_PROOF",
  u:"HUMAN_CONTROL_ATTESTATION",i:"EXCEPTION_REASON",c:"MONEY_INPUT_CANDIDATE",
  d:"QUANTITY_OR_MEASURE_INPUT_CANDIDATE",l:"DATE_TIME_INPUT_CANDIDATE",
  h:"DATE_INPUT_CANDIDATE",y:"CHOICE_OR_MASTER_REFERENCE",w:"CHOICE_INPUT",
  a:"TEXT_OR_SOURCE_REFERENCE",_:"LOCATION_MASTER_LOOKUP"
 };
 const overrides={
  "C-02:money_account_id":"PAYMENT_ACCOUNT_REFERENCE",
  "C-02:receipt_photos":"ORIGINAL_RECEIPT_ATTACHMENT",
  "C-02:total":"DERIVED_EXPENSE_LINE_TOTAL",
  "C-02:limit_text":"DERIVED_LIMIT_POLICY_INDICATOR",
  "C-02:sum_cr":"DERIVED_IMPREST_CASH_RECEIPT_SUM",
  "C-02:imprest_text":"DERIVED_IMPREST_POLICY_MATCH",
  "C-02:approved_by":"INDEPENDENT_APPROVAL_ACTOR_REFERENCE",
  "C-02:no_receipt_reason":"MISSING_RECEIPT_EXCEPTION_REASON",
  "C-01:handover":"DERIVED_NOTE_COUNT_MINUS_FLOAT",
  "C-01:count":"SENDER_DENOMINATION_SCHEDULE",
  "C-01:rcount":"RECEIVER_INDEPENDENT_DENOMINATION_SCHEDULE",
  "C-01:diff_reason":"RECOUNT_VARIANCE_EXPLANATION",
  "C-01:words":"DERIVED_AMOUNT_IN_WORDS_CANDIDATE",
  "W-02:crates_due":"RETURNABLE_PACKAGING_OUTSTANDING_LEDGER",
  "W-02:trays_due":"RETURNABLE_PACKAGING_OUTSTANDING_LEDGER",
  "W-02:crates_sent":"RETURNABLE_PACKAGING_MOVEMENT",
  "W-02:trays_sent":"RETURNABLE_PACKAGING_MOVEMENT",
  "W-02:crates_back":"RETURNABLE_PACKAGING_RETURN",
  "W-02:trays_back":"RETURNABLE_PACKAGING_RETURN",
  "W-02:tag":"DERIVED_PRODUCTION_TAG_POLICY_CANDIDATE",
  "W-02:cash_amount":"CONDITIONAL_PAYMENT_AMOUNT",
  "W-02:damage_note":"RECEIPT_DAMAGE_QUARANTINE_EVIDENCE",
  "W-02:in_stock_ledger":"INVENTORY_LEDGER_SOURCE_LINK",
  "W-02:both_papers":"TWO_DOCUMENT_TRACE_LINK",
  "W-02:factory_sheet_no":"FACTORY_PRODUCTION_SOURCE_LINK",
  "W-03:counted_by":"COUNT_INDEPENDENT_ACTOR",
  "W-03:storekeeper":"STOCK_CUSTODIAN_ACTOR",
  "W-03:movement":"COUNT_FREEZE_MOVEMENT_ATTESTATION",
  "W-03:movement_detail":"COUNT_MOVEMENT_EXCEPTION_EXPLANATION",
  "R-01:float_set":"DERIVED_APPROVED_CASH_FLOAT_POLICY",
  "R-01:open_diff":"DERIVED_OPENING_FLOAT_VARIANCE",
  "R-01:imp_text":"DERIVED_IMPREST_VARIANCE",
  "R-01:temp_ok":"DERIVED_TEMPERATURE_POLICY_COMPARISON",
  "R-01:short":"DERIVED_RECEIPT_SHORTAGE",
  "R-01:v_total":"DERIVED_EXPENSE_VOUCHER_SUM",
  "R-01:vouchers":"LINKED_EXPENSE_VOUCHER_COLLECTION",
  "R-01:v_no":"LINKED_EXPENSE_VOUCHER_REFERENCE",
  "R-01:v_head":"LINKED_EXPENSE_VOUCHER_HEAD",
  "R-01:v_amt":"LINKED_EXPENSE_VOUCHER_AMOUNT",
  "R-01:v_rec":"LINKED_EXPENSE_VOUCHER_RECEIPT",
  "R-01:expired_shown":"FOOD_EXPIRY_SAFETY_EVENT",
  "R-01:expired_informed":"FOOD_EXPIRY_ESCALATION_EVIDENCE",
  "R-01:open_all_ok":"OPENING_SAFETY_SIGNOFF_CANDIDATE",
  "R-01:safety_defect":"OPENING_SAFETY_EXCEPTION_REASON",
  "R-01:temp":"TEMPERATURE_MONITORING_OBSERVATION",
  "R-01:t2_1":"CONDITIONAL_BUSY_DAY_TEMPERATURE",
  "R-01:t2_2":"CONDITIONAL_BUSY_DAY_TEMPERATURE",
  "R-01:fridge_defect":"COLD_CHAIN_DEFECT_EVIDENCE",
  "R-01:prod_date":"SOURCE_GOODS_PRODUCTION_DATE",
  "R-01:clean":"INDEPENDENT_CLEANING_CHECK",
  "R-01:doer":"CLEANER_ACTOR",
  "R-01:verifier":"INDEPENDENT_CLEANING_VERIFIER",
  "R-01:key_shutter":"KEY_CUSTODY_ROLE",
  "R-01:key_drawer":"KEY_CUSTODY_ROLE",
  "R-01:key_stock":"KEY_CUSTODY_ROLE"
 };
 const allFields=new Map(original.forms.flatMap(f=>f.fields.map(x=>[f.legacy_code+":"+x.key,{...x,legacy_code:f.legacy_code}])));
 const records=[];
 for(const batch of batches) {
  for(const e of batch.entries){
   const source=allFields.get(e.source_id);if(!source)throw Error("UNKNOWN_ORIGINAL_FIELD:"+e.source_id);
   const sourceKind=constructorKinds[source.constructor_alias];
   if(!sourceKind)throw Error("UNRECOGNIZED_FIELD_CONSTRUCTOR:"+e.source_id);
   const decision=overrides[e.source_id]||sourceKind;
   const key=e.source_key,src=e.source_form;
   const reviewRisk=(src==="C-01"||src==="C-02"||src==="W-03"||/cash|money|float|imp|receipt|approval|amount|count|paid|expired|fridge|cold|temp|safety|damage|waste|short|lost|leak|seal|grade|production|prod_date|tag|clean|key_|ledger|movement|demand|signed|signature|counter|storekeeper|witness/.test(key))
      ?"HIGH_RISK_BUSINESS_CONTROL":"SOURCE_FIELD_TRIAGE_REQUIRED";
   const dataOrigin=decision.startsWith("DERIVED_")||sourceKind==="COMPUTED_OR_DISPLAY_CANDIDATE"
      ?"CALCULATED_OR_DISPLAY__RECOMPUTE_WITH_PROVEN_SOURCE_RULE":
       decision.includes("REFERENCE")||decision.includes("LINKED_")||sourceKind==="LOCATION_MASTER_LOOKUP"||sourceKind==="ITEM_MASTER_LOOKUP"
      ?"REFERENCE__USE_SIGNED_BUSINESS_SCOPE_IF_IN_ERP":
       decision.includes("LEDGER")||decision.includes("PACKAGING")
      ?"CONTINUING_LEDGER__TRANSACTION_REF_REQUIRED":
       sourceKind==="ACTOR_OR_ROLE_PROOF"||decision.includes("ACTOR")||decision.includes("VERIFIER")
      ?"IDENTIFIED_PERSON__INDEPENDENT_ROLE_REQUIREMENTS_TO_VERIFY":
       sourceKind==="HUMAN_CONTROL_ATTESTATION"
      ?"CONTROL_EVIDENCE__NEVER_ASSUME_TRUE":
       sourceKind==="DOCUMENT_ATTACHMENT"
      ?"ATTACHMENT_OR_EXTERNAL_DOCUMENT":
       sourceKind==="ROW_COLLECTION"
      ?"LINE_COLLECTION__DO_NOT_REQUIRE_DUPLICATE_PAPER_ENTRY":
       "SOURCE_ENTRY_OR_CONDITIONAL_EVIDENCE";
   const evidenceState=source.required_candidate==="ALWAYS"
     ?"SOURCE_SYNTACTIC_ALWAYS_REQUIRED_CANDIDATE":
     source.required_candidate==="CONDITIONAL"
     ?"SOURCE_CONDITIONAL_REQUIRED_TRIGGER_NOT_VERIFIED":
     "SOURCE_NOT_DECLARED__NOT_PROOF_OF_OPTIONALITY";
   records.push({
    source_id:e.source_id,batch_number:batch.batch_number,
    legacy_constructor_alias:source.constructor_alias,
    source_label_en:source.label_en,
    source_field_required_syntax:source.required_candidate,
    source_visibility_syntax:source.visible_candidate,
    source_role_syntax:source.role_candidate,
    proposed_semantic_class:decision,
    proposed_ERP_data_origin:dataOrigin,
    source_requirement_evidence:evidenceState,
    review_risk:reviewRisk,
    prototype_print_target:e.target_form+":"+e.target_field_key,
    source_proof:"FROZEN_FORM_FIELD_DECLARATION_HEURISTIC",
    old_conditional_trigger:"UNPROVEN"===source.required_candidate?"NOT_DECLARED":(source.required_candidate==="CONDITIONAL"||source.visible_candidate==="CONDITIONAL"?"REQUIRES_EXACT_SOURCE_BRANCH_REVIEW":"NOT_STATED_IN_CANDIDATE"),
    calculated_result_equivalence:"NOT_PROVEN",
    duplicate_data_entry_permitted:false,
    source_approval_proven:false,owner_accepted:false,
    next_required_check:
     sourceKind==="COMPUTED_OR_DISPLAY_CANDIDATE"||decision.startsWith("DERIVED_")
     ?"REPLAY_HISTORICAL_FORMULA_WITH_VALID_NEGATIVE_AND_BOUNDARY_DATA":
     source.required_candidate==="CONDITIONAL"||source.visible_candidate==="CONDITIONAL"
     ?"TRACE_CONDITIONAL_VISIBILITY_AND_REQUIREDNESS_EXPRESSION":
     reviewRisk==="HIGH_RISK_BUSINESS_CONTROL"
     ?"PROVE_ROLES_EVIDENCE_AND_SOURCE_TO_LEDGER_TRACE":
     "SOURCE_WORKFLOW_AND_OWNER_INTENT_REVIEW"
   });
  }
 }
 const count=(prop)=>Object.fromEntries([...new Set(records.map(r=>r[prop]))].sort().map(k=>[k,records.filter(x=>x[prop]===k).length]));
 return {
  schema_version:1,status:"SEMANTIC_TRIAGE_ONLY__NOT_BUSINESS_RULE_PARITY",
  source:"Frozen Islamia legacy form field declarations plus field-review batches 001–003; original forms never executed",
  notice:"Every classification is a proposed source-pattern decision. It distinguishes calculated/reference/ledger/attestation signals from user inputs; it cannot certify formula, condition, role, legal or product equivalence. No source key may be discarded without full review.",
  summary:{fields_triaged:records.length,batches:batches.length,
   source_explicit_always_required:records.filter(x=>x.source_field_required_syntax==="ALWAYS").length,
   source_explicit_conditional_required:records.filter(x=>x.source_field_required_syntax==="CONDITIONAL").length,
   source_conditional_visibility:records.filter(x=>x.source_visibility_syntax==="CONDITIONAL").length,
   high_risk:records.filter(x=>x.review_risk==="HIGH_RISK_BUSINESS_CONTROL").length,
   by_data_origin:count("proposed_ERP_data_origin"),
   parity_approved:0,owner_accepted:0,
   remaining_source_first_pass:1160-records.length},
  fields:records
 };
}
function generate(){
 const old=require('./legacy-rule-candidates.json');
 const batches=[1,2,3].map(n=>require('./field-review/batch-'+String(n).padStart(3,'0')+'.json'));
 return semanticTriage(old,batches);
}
function audit(){
 const report=generate(),pathToReport=path.join(__dirname,'field-review','semantic-triage-001-003.json');
 assert.deepEqual(JSON.parse(fs.readFileSync(pathToReport,'utf8')),report,'SEMANTIC_TRIAGE_REPORT_STALE');
 assert.equal(report.summary.parity_approved,0);
 assert.equal(report.summary.owner_accepted,0);
 assert.equal(report.summary.fields_triaged,150);
 assert.equal(new Set(report.fields.map(x=>x.source_id)).size,150);
 return report;
}
if(require.main===module){const x=process.argv.includes('--check')?audit():generate();
 console.log(JSON.stringify({status:x.status,summary:x.summary},null,2));}
module.exports={semanticTriage,generate,audit};
