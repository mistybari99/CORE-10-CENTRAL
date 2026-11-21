-- Restore0301 Sales validator exactly; preserve canonical Master functions.
CREATE OR REPLACE FUNCTION core10._sales_validate_v1(p_business bigint,p_site bigint,p_doc jsonb,p_params jsonb)
RETURNS numeric LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE l jsonb; q numeric; u numeric; d numeric; tax numeric;
 total numeric:=0; valid boolean; scale integer:=(p_params->>'money_scale')::integer;
BEGIN
 IF p_doc IS NULL OR jsonb_typeof(p_doc) IS DISTINCT FROM 'object'
    OR jsonb_typeof(p_doc->'lines') IS DISTINCT FROM 'array'
 THEN RAISE EXCEPTION 'SALES_DOCUMENT_INVALID'; END IF;
 IF p_doc - ARRAY['customer_id','price_list_id','currency','lines'] <> '{}'::jsonb
    OR NOT (p_doc ?& ARRAY['customer_id','price_list_id','currency','lines'])
    OR p_doc->>'currency' !~ '^[A-Z]{3}$'
    OR jsonb_typeof(p_doc->'currency') IS DISTINCT FROM 'string'
 THEN RAISE EXCEPTION 'SALES_DOCUMENT_INVALID'; END IF;
 FOREACH l IN ARRAY ARRAY[p_doc->'customer_id',p_doc->'price_list_id'] LOOP
  IF jsonb_typeof(l) IS DISTINCT FROM 'number' OR l::text !~ '^[1-9][0-9]{0,17}$'
  THEN RAISE EXCEPTION 'SALES_MASTER_ID_INVALID'; END IF;
 END LOOP;
 IF jsonb_array_length(p_doc->'lines') NOT BETWEEN 1 AND (p_params->>'max_lines')::integer
 THEN RAISE EXCEPTION 'SALES_LINE_LIMIT'; END IF;
 FOR l IN SELECT value FROM jsonb_array_elements(p_doc->'lines') LOOP
  IF jsonb_typeof(l) IS DISTINCT FROM 'object'
   OR l-ARRAY['item_id','variant_id','uom_id','quantity','unit_price','discount_percent','tax_percent']<>'{}'::jsonb
   OR NOT (l ?& ARRAY['item_id','uom_id','quantity','unit_price','discount_percent','tax_percent'])
  THEN RAISE EXCEPTION 'SALES_LINE_INVALID'; END IF;
  IF jsonb_typeof(l->'item_id') IS DISTINCT FROM 'number' OR l->>'item_id' !~ '^[1-9][0-9]{0,17}$'
   OR jsonb_typeof(l->'uom_id') IS DISTINCT FROM 'number' OR l->>'uom_id' !~ '^[1-9][0-9]{0,17}$'
   OR (l ? 'variant_id' AND l->'variant_id'<>'null'::jsonb AND
       (jsonb_typeof(l->'variant_id')<>'number' OR l->>'variant_id' !~ '^[1-9][0-9]{0,17}$'))
  THEN RAISE EXCEPTION 'SALES_MASTER_ID_INVALID'; END IF;
  -- Numeric casts only after JSON numeric type and bounded decimal checks.
   IF EXISTS(SELECT 1 FROM unnest(ARRAY['quantity','unit_price','discount_percent','tax_percent']) k
    WHERE jsonb_typeof(l->k) IS DISTINCT FROM 'number' OR length(l->>k)>30)
   THEN RAISE EXCEPTION 'SALES_NUMBER_INVALID'; END IF;
  q:=(l->>'quantity')::numeric; u:=(l->>'unit_price')::numeric;
  d:=(l->>'discount_percent')::numeric; tax:=(l->>'tax_percent')::numeric;
  IF q<=0 OR q<>round(q,6) OR q>(p_params->>'max_quantity')::numeric OR u<0 OR u<>round(u,scale)
     OR d NOT BETWEEN 0 AND (p_params->>'max_discount_percent')::numeric OR d<>round(d,6)
     OR tax NOT BETWEEN 0 AND 100 OR tax<>round(tax,6)
  THEN RAISE EXCEPTION 'SALES_VALUE_INVALID'; END IF;
  IF tax>0 AND NOT (p_params->>'tax_enabled')::boolean THEN RAISE EXCEPTION 'SALES_TAX_DISABLED'; END IF;
  total:=total+round(q*u*(1-d/100)*(1+tax/100),scale);
 END LOOP;
 IF total>(p_params->>'max_order_total')::numeric THEN RAISE EXCEPTION 'SALES_TOTAL_LIMIT'; END IF;
 -- Proposed read-only validation port; NP02 must accept this contract before
 -- integration. FALSE/NULL or an absent implementation cannot create an order.
 IF to_regprocedure('core10.master_validate_sales_order_v1(bigint,bigint,jsonb)') IS NULL
 THEN RAISE EXCEPTION 'NOT_CONNECTED:MASTER_SALES_VALIDATION'; END IF;
 EXECUTE 'SELECT core10.master_validate_sales_order_v1($1,$2,$3)' INTO valid USING p_business,p_site,p_doc;
 IF valid IS DISTINCT FROM true THEN RAISE EXCEPTION 'SALES_MASTER_REJECTED'; END IF;
 RETURN total;
END $$;
REVOKE ALL ON FUNCTION core10._sales_validate_v1(bigint,bigint,jsonb,jsonb) FROM PUBLIC,authenticated;
