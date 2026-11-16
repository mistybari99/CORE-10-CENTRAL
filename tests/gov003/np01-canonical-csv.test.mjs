import test from "node:test";
import assert from "node:assert/strict";
import {canonicalAuditCsv} from "../../internal/gov003/canonical-csv.mjs";
const d="a".repeat(64),rows=[{stream_seq:1,source_domain:"approval",source_ref:"=HYPERLINK(1)",
 action:"approval.approve",event_at:"2026-11-16T00:00:00Z",payload_sha256:d,event_digest:d}];
test("GOV003 CSV has allowlisted metadata, escaped formulas, never raw payload",()=>{
 const out=canonicalAuditCsv(rows);
 assert.match(out,/'=HYPERLINK/);
 assert.ok(!out.includes("actor_uid"));
 assert.ok(out.startsWith("stream_seq,"));
});
test("GOV003 CSV fail closed on extra columns and invalid identifiers",()=>{
 assert.throws(()=>canonicalAuditCsv([{...rows[0],payload:"secret"}]),/GOV003_EXPORT_INVALID/);
 assert.throws(()=>canonicalAuditCsv([{...rows[0],stream_seq:0}]),/GOV003_EXPORT_INVALID/);
 assert.throws(()=>canonicalAuditCsv(Array.from({length:501},()=>rows[0])),/GOV003_EXPORT_INVALID/);
});
