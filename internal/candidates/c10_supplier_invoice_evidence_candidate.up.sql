-- T01.03 review candidate. Assign a migration number through the existing register.
INSERT INTO core10.control_catalog_v1
 (feature_key,title_en,title_bn,pack,default_enabled,default_stages,max_stages,
  allow_site_scope,approval_domain,approval_action,params)
VALUES ('procurement.invoice_evidence','Record supplier invoice comparison evidence',
 'সরবরাহকারীর ইনভয়েসের তুলনা নথিভুক্ত করুন','NP03A',false,0,0,true,NULL,NULL,'{}');

CREATE TABLE core10.supplier_invoice_evidence_v1 (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL,
 business_id bigint NOT NULL,
 po_id bigint NOT NULL,
 supplier_id bigint NOT NULL,
 reference text NOT NULL,
 request_key text NOT NULL,
 caller_id uuid NOT NULL,
 submitted_lines jsonb NOT NULL,
 comparison jsonb NOT NULL,
 recorded_at timestamptz NOT NULL DEFAULT statement_timestamp(),
 UNIQUE (business_id,request_key),
 UNIQUE (business_id,supplier_id,reference),
 FOREIGN KEY (po_id,tenant_id,business_id)
  REFERENCES core10.purchase_orders_v1(id,tenant_id,business_id)
);
ALTER TABLE core10.supplier_invoice_evidence_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON core10.supplier_invoice_evidence_v1 FROM PUBLIC, anon, authenticated;
CREATE INDEX supplier_invoice_evidence_po_v1 ON core10.supplier_invoice_evidence_v1(po_id);

CREATE FUNCTION core10._supplier_invoice_evidence_immutable_v1()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,core10 AS $$
BEGIN RAISE EXCEPTION 'PROC_INVOICE_EVIDENCE_IMMUTABLE'; END $$;
REVOKE ALL ON FUNCTION core10._supplier_invoice_evidence_immutable_v1() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER supplier_invoice_evidence_immutable_v1
 BEFORE UPDATE OR DELETE ON core10.supplier_invoice_evidence_v1
 FOR EACH ROW EXECUTE FUNCTION core10._supplier_invoice_evidence_immutable_v1();
CREATE TRIGGER supplier_invoice_evidence_no_truncate_v1
 BEFORE TRUNCATE ON core10.supplier_invoice_evidence_v1
 FOR EACH STATEMENT EXECUTE FUNCTION core10._supplier_invoice_evidence_immutable_v1();

CREATE FUNCTION core10.procurement_record_invoice_evidence_v1(
 p_po bigint, p_reference text, p_lines jsonb, p_key text
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE
 po core10.purchase_orders_v1%ROWTYPE;
 original core10.supplier_invoice_evidence_v1%ROWTYPE;
 actor uuid := core10.actor_uid();
 reference_code text := upper(btrim(p_reference));
 submitted jsonb;
 line_result jsonb;
 comparison_result jsonb;
 evidence_id bigint;
BEGIN
 SELECT * INTO po FROM core10.purchase_orders_v1 WHERE id=p_po;
 IF po.id IS NULL OR actor IS NULL OR NOT core10.can_manage(po.tenant_id,po.business_id)
 THEN RAISE EXCEPTION 'PROC_INVOICE_SCOPE'; END IF;

 IF reference_code IS NULL OR reference_code !~ '^[A-Z0-9][A-Z0-9_/.-]{0,79}$'
 OR p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{8,100}$'
 OR jsonb_typeof(p_lines) IS DISTINCT FROM 'array'
 THEN RAISE EXCEPTION 'PROC_INVOICE_INPUT'; END IF;
 IF jsonb_array_length(p_lines) NOT BETWEEN 1 AND 200
 OR EXISTS (
  SELECT 1 FROM jsonb_array_elements(p_lines) AS e(value)
  WHERE jsonb_typeof(e.value) <> 'object' OR
    jsonb_typeof(e.value->'line_no') IS DISTINCT FROM 'number' OR
    jsonb_typeof(e.value->'quantity') IS DISTINCT FROM 'number' OR
    jsonb_typeof(e.value->'unit_price') IS DISTINCT FROM 'number' OR
    e.value->>'line_no' !~ '^[1-9][0-9]{0,2}$' OR
    e.value->>'quantity' !~ '^[0-9]{1,9}(\.[0-9]{1,3})?$' OR
    e.value->>'unit_price' !~ '^[0-9]{1,12}(\.[0-9]{1,2})?$'
 ) THEN RAISE EXCEPTION 'PROC_INVOICE_LINES'; END IF;

 SELECT jsonb_agg(jsonb_build_object(
   'line_no',(value->>'line_no')::integer,'quantity',(value->>'quantity')::numeric,
   'unit_price',(value->>'unit_price')::numeric
 ) ORDER BY (value->>'line_no')::integer)
 INTO submitted FROM jsonb_array_elements(p_lines);
 IF EXISTS (
   SELECT 1 FROM jsonb_array_elements(submitted)
   GROUP BY value->>'line_no'
   HAVING count(*)>1 OR min((value->>'quantity')::numeric)<=0
 ) THEN RAISE EXCEPTION 'PROC_INVOICE_LINES'; END IF;

 -- Serialize comparison snapshots on the same order row used by receipt and return updates.
 SELECT * INTO po FROM core10.purchase_orders_v1 WHERE id=p_po FOR UPDATE;
 IF po.id IS NULL OR NOT core10.can_manage(po.tenant_id,po.business_id)
 THEN RAISE EXCEPTION 'PROC_INVOICE_SCOPE'; END IF;
 PERFORM core10.control_check_v1(po.business_id,'procurement.invoice_evidence',po.site_id);
 SELECT * INTO original FROM core10.supplier_invoice_evidence_v1
  WHERE business_id=po.business_id AND request_key=p_key;
 IF FOUND THEN
  IF original.po_id=p_po AND original.reference=reference_code AND original.caller_id=actor
    AND original.submitted_lines=submitted
  THEN RETURN original.comparison || jsonb_build_object('evidence_id',original.id,'replayed',true); END IF;
  RAISE EXCEPTION 'PROC_INVOICE_KEY_CONFLICT';
 END IF;
 IF po.status NOT IN ('partially_received','received','closed')
 THEN RAISE EXCEPTION 'PROC_INVOICE_PO_STATUS'; END IF;

 SELECT jsonb_agg(jsonb_build_object(
   'line_no',l.line_no,'item_id',l.item_id,'ordered',l.quantity,
   'accepted',l.accepted_qty,'returned',l.returned_qty,
   'prior_recorded_quantity',prior.quantity,'invoiced',(input.value->>'quantity')::numeric,
   'disputed_quantity',greatest(0,(input.value->>'quantity')::numeric -
     greatest(0,least(l.quantity,l.accepted_qty-l.returned_qty)-prior.quantity)),
   'po_unit_price',l.unit_price,'invoice_unit_price',(input.value->>'unit_price')::numeric,
   'price_mismatch',l.unit_price<>(input.value->>'unit_price')::numeric
 ) ORDER BY l.line_no)
 INTO line_result
 FROM jsonb_array_elements(submitted) input
 JOIN core10.purchase_order_lines_v1 l ON l.po_id=p_po AND l.line_no=(input.value->>'line_no')::integer
 CROSS JOIN LATERAL (
  SELECT coalesce(sum((claim.value->>'quantity')::numeric),0) AS quantity
   FROM core10.supplier_invoice_evidence_v1 previous
   CROSS JOIN LATERAL jsonb_array_elements(previous.submitted_lines) claim
   WHERE previous.po_id=p_po AND (claim.value->>'line_no')::integer=l.line_no
 ) prior;
 IF line_result IS NULL OR jsonb_array_length(line_result)<>jsonb_array_length(submitted)
 THEN RAISE EXCEPTION 'PROC_INVOICE_LINES'; END IF;

 comparison_result := jsonb_build_object(
   'po_id',p_po,'po_version',po.version,'supplier_id',po.supplier_id,
   'reference',reference_code,'lines',line_result,'payable_posted',false,
   'tax_verified',false,'review_required',true);
 INSERT INTO core10.supplier_invoice_evidence_v1
  (tenant_id,business_id,po_id,supplier_id,reference,request_key,caller_id,submitted_lines,comparison)
 VALUES (po.tenant_id,po.business_id,p_po,po.supplier_id,reference_code,p_key,actor,submitted,comparison_result)
 ON CONFLICT DO NOTHING RETURNING id INTO evidence_id;
 IF evidence_id IS NULL THEN RAISE EXCEPTION 'PROC_INVOICE_DUPLICATE_REFERENCE_OR_KEY'; END IF;
 PERFORM core10._append_canonical_audit_v1(
   po.tenant_id,po.business_id,'procurement','invoice-evidence-'||evidence_id,
   'procurement.invoice_evidence_recorded',actor,'procurement:invoice-evidence:'||evidence_id,
   comparison_result);
 RETURN comparison_result || jsonb_build_object('evidence_id',evidence_id,'replayed',false);
END $$;
REVOKE ALL ON FUNCTION core10.procurement_record_invoice_evidence_v1(bigint,text,jsonb,text)
 FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION core10.procurement_record_invoice_evidence_v1(bigint,text,jsonb,text)
 TO authenticated;

INSERT INTO core10.control_rpc_map_v1
 (rpc_name,status,feature_key,reason,lane,board_row,test_ref)
VALUES ('procurement_record_invoice_evidence_v1','enforced','procurement.invoice_evidence',
 'Supplier invoice comparison requires current manager scope and Owner Control for the order site',
 'Codex','B-012','tests/migrations/supplier-invoice-evidence-candidate.sql');
