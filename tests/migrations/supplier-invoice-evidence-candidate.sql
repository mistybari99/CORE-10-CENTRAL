-- Loaded by the existing procurement fixture after valid PO, QC and lot posting.
SET LOCAL ROLE authenticated;
SELECT pg_temp.as_user('f1111111-1111-4111-8111-111111111111');
\set invoice_lines '[{"line_no":1,"quantity":100,"unit_price":50}]'
SELECT pg_temp.expect(format(
 'SELECT core10.procurement_record_invoice_evidence_v1(%s,%L,%L,%L)',
 (:'bakery_po'::jsonb->>'po_id')::bigint,'INV-100',:'invoice_lines','invoice-cp10-01'),
 'CONTROL_DISABLED:procurement.invoice_evidence');
SELECT pg_temp.cset('procurement.invoice_evidence',true,0,'{}',0,'invoice-cp10-control');
SELECT core10.procurement_record_invoice_evidence_v1(
 (:'bakery_po'::jsonb->>'po_id')::bigint,' INV-100 ',:'invoice_lines','invoice-cp10-01') AS invoice_evidence \gset
SELECT pg_temp.ok(
 (:'invoice_evidence'::jsonb->'lines'->0->>'accepted')::numeric=80
 AND (:'invoice_evidence'::jsonb->'lines'->0->>'disputed_quantity')::numeric=20
 AND (:'invoice_evidence'::jsonb->>'payable_posted')::boolean IS FALSE,
 'persisted comparison records disputed quantity without posting a payable');
SELECT pg_temp.ok(core10.procurement_record_invoice_evidence_v1(
 (:'bakery_po'::jsonb->>'po_id')::bigint,'inv-100',:'invoice_lines','invoice-cp10-01')
 = :'invoice_evidence'::jsonb||'{"replayed":true}'::jsonb,'retry returns the same immutable comparison');
SELECT pg_temp.expect(format(
 'SELECT core10.procurement_record_invoice_evidence_v1(%s,%L,%L,%L)',
 (:'bakery_po'::jsonb->>'po_id')::bigint,'inv-100',:'invoice_lines','invoice-cp10-02'),
 'PROC_INVOICE_DUPLICATE_REFERENCE_OR_KEY');
SELECT pg_temp.expect(format(
 'SELECT core10.procurement_record_invoice_evidence_v1(%s,%L,%L,%L)',
 (:'bakery_po'::jsonb->>'po_id')::bigint,'inv-100','[{"line_no":1,"quantity":99,"unit_price":50}]','invoice-cp10-01'),
 'PROC_INVOICE_KEY_CONFLICT');
SELECT core10.procurement_record_invoice_evidence_v1(
 (:'bakery_po'::jsonb->>'po_id')::bigint,'INV-101','[{"line_no":1,"quantity":1,"unit_price":51}]','invoice-cp10-03') AS second_invoice \gset
SELECT pg_temp.ok(
 (:'second_invoice'::jsonb->'lines'->0->>'prior_recorded_quantity')::numeric=100
 AND (:'second_invoice'::jsonb->'lines'->0->>'disputed_quantity')::numeric=1
 AND (:'second_invoice'::jsonb->'lines'->0->>'price_mismatch')::boolean,
 'prior claim and unmatched unit price are visible');
SELECT pg_temp.as_user('f5555555-5555-4555-8555-555555555555');
SELECT pg_temp.expect(format(
 'SELECT core10.procurement_record_invoice_evidence_v1(%s,%L,%L,%L)',
 (:'bakery_po'::jsonb->>'po_id')::bigint,'INV-102',:'invoice_lines','invoice-cp10-04'),
 'PROC_INVOICE_SCOPE');
SELECT pg_temp.expect('SELECT * FROM core10.supplier_invoice_evidence_v1','permission denied');
RESET ROLE;
SELECT pg_temp.ok((SELECT count(*)=2 FROM core10.supplier_invoice_evidence_v1 WHERE business_id=9111),
 'two records after repeated and denied submissions');
SELECT pg_temp.ok((SELECT count(*)=2 FROM core10.canonical_audit_events_v1
 WHERE business_id=9111 AND action='procurement.invoice_evidence_recorded'),
 'exactly one audit record per accepted evidence record');
SELECT pg_temp.ok(NOT EXISTS(SELECT 1 FROM core10.finance_journals_v1 WHERE business_id=9111),
 'no journal posted by any comparison');
SELECT pg_temp.expect('UPDATE core10.supplier_invoice_evidence_v1 SET reference=reference',
 'PROC_INVOICE_EVIDENCE_IMMUTABLE');
\echo 'PASS Bakery immutable supplier invoice comparison'
