import test from "node:test";
import assert from "node:assert/strict";
import { APPROVAL_ACTIVITY_COLUMNS, makeApprovalActivityCsv } from "../internal/enterprise-client/c10_gov002_activity_csv_v1.mjs";

const row = {
 activity_id:"approval:101",business_id:101,request_id:17,
 domain:"demo_ops",action_code:"exception_review",source_key:"Stock adjustment",
 source_version:1,request_maker:"33333333-3333-4333-8333-333333333333",
 event_actor:"22222222-2222-4222-8222-222222222222",
 activity_type:"approval",action:"approve",severity:null,
 occurred_at:"2026-11-12T10:00:00Z",approval_status:"approved",
 payload_sha256:"should not export",reason:"private details stay out"
};
test("auditable CSV header, BOM and business scoped row",()=>{
 const output=makeApprovalActivityCsv([row],{businessId:101});
 assert.ok(output.startsWith("\uFEFF"));
 assert.equal(output.split("\r\n").length,3);
 assert.ok(output.includes('"approval:101"'));
 assert.ok(output.includes('"Stock adjustment"'));
 for(const forbidden of ["should not export","private details stay out","payload_sha256","reason"]) {
  assert.equal(output.includes(forbidden),false);
 }
 assert.deepEqual(APPROVAL_ACTIVITY_COLUMNS.length,14);
});
test("formula injection including padded, quotes and CRLF rows is neutralized",()=>{
 const dangerous={...row,source_key:" \t=HYPERLINK(\"https://evil\",\"GO\")\r\n+SUM(1,1)"};
 const csv=makeApprovalActivityCsv([dangerous],{businessId:101});
 assert.equal(csv.split("\r\n").length,3);
 assert.match(csv,/\'\s+=HYPERLINK\(/u);
 assert.ok(csv.includes('""https://evil""'),csv);
 assert.ok(csv.includes("+SUM(1,1)"),csv);
 const second=makeApprovalActivityCsv([{...row,source_key:"@CMD"},{...row,activity_id:"exception:103",source_key:"-1+2"}],{businessId:101});
 assert.ok(second.includes("'@CMD"));
 assert.ok(second.includes("'-1+2"));
});
test("no CSV export without explicit single-business scope",()=>{
 assert.throws(()=>makeApprovalActivityCsv([row]),/export_requires_positive/);
 assert.throws(()=>makeApprovalActivityCsv([row],{businessId:102}),/other_business/);
 assert.throws(()=>makeApprovalActivityCsv([{...row,activity_id:"malformed"}],{businessId:101}),/invalid/);
 assert.throws(()=>makeApprovalActivityCsv("no", {businessId:101}),/invalid_or_over_limit/);
 assert.throws(()=>makeApprovalActivityCsv(Array(5001).fill(row),{businessId:101}),/over_limit/);
 assert.throws(()=>makeApprovalActivityCsv([{...row,source_key:"x".repeat(4001)}],{businessId:101}),/csv_cell_too_large/);
});
test("never mutates server result rows",()=>{
 const original=structuredClone(row);
 makeApprovalActivityCsv([row],{businessId:101});
 assert.deepEqual(row,original);
});
