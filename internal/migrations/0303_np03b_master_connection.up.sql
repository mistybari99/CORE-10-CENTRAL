-- B-014 forward-only Sales validation extension; no Master-owned object changes.
CREATE OR REPLACE FUNCTION core10._sales_validate_v1(p_business bigint,p_site bigint,p_doc jsonb,p_params jsonb)
RETURNS numeric LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE l jsonb; q numeric; u numeric; d numeric; tax numeric;
 total numeric:=0; valid boolean; master_list jsonb; master_uoms jsonb; precision integer; scale integer:=(p_params->>'money_scale')::integer;
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
  IF q<=0 OR q<>round(q,6) OR q>(p_params->>'max_quantity')::numeric OR u<0 OR u<>round(u,4)
     OR d NOT BETWEEN 0 AND (p_params->>'max_discount_percent')::numeric OR d<>round(d,6)
     OR tax NOT BETWEEN 0 AND 100 OR tax<>round(tax,6)
  THEN RAISE EXCEPTION 'SALES_VALUE_INVALID'; END IF;
  IF tax>0 AND NOT (p_params->>'tax_enabled')::boolean THEN RAISE EXCEPTION 'SALES_TAX_DISABLED'; END IF;
  total:=total+round(q*u*(1-d/100)*(1+tax/100),scale);
 END LOOP;
 IF total>(p_params->>'max_order_total')::numeric THEN RAISE EXCEPTION 'SALES_TOTAL_LIMIT'; END IF;
 -- Accepted0151 read-only Master validation port. FALSE/NULL fails closed.
 IF to_regprocedure('core10.master_validate_sales_order_v1(bigint,bigint,jsonb)') IS NULL
 THEN RAISE EXCEPTION 'NOT_CONNECTED:MASTER_SALES_VALIDATION'; END IF;
 EXECUTE 'SELECT core10.master_validate_sales_order_v1($1,$2,$3)' INTO valid USING p_business,p_site,p_doc;
 IF valid IS DISTINCT FROM true THEN RAISE EXCEPTION 'SALES_MASTER_REJECTED'; END IF;
 -- Canonical Master remains authoritative for references and current tier price.
 -- Reader ports supply currency and quantity precision absent from its validator.
 IF to_regprocedure('core10.master_get_price_list_v1(bigint,bigint,integer,bigint)') IS NULL
 OR to_regprocedure('core10.master_list_uoms_v1(bigint)') IS NULL
 THEN RAISE EXCEPTION 'NOT_CONNECTED:MASTER_SALES_READERS'; END IF;
 master_list:=core10.master_get_price_list_v1(p_business,(p_doc->>'price_list_id')::bigint,1,NULL);
 IF master_list->>'currency' IS DISTINCT FROM p_doc->>'currency'
 THEN RAISE EXCEPTION 'SALES_CURRENCY_MISMATCH'; END IF;
 master_uoms:=core10.master_list_uoms_v1(p_business);
 FOR l IN SELECT value FROM jsonb_array_elements(p_doc->'lines') LOOP
  SELECT (x->>'decimals')::integer INTO precision
   FROM jsonb_array_elements(master_uoms->'uoms') x
   WHERE (x->>'id')::bigint=(l->>'uom_id')::bigint AND (x->>'active')::boolean;
  IF precision IS NULL OR (l->>'quantity')::numeric<>round((l->>'quantity')::numeric,precision)
  THEN RAISE EXCEPTION 'SALES_UOM_PRECISION'; END IF;
  -- No canonical tax configuration port exists yet. Owner's enable switch alone
  -- cannot certify a tax rule; release this fence only with an approved contract.
  IF (l->>'tax_percent')::numeric<>0 THEN RAISE EXCEPTION 'NOT_CONNECTED:MASTER_SALES_TAX'; END IF;
 END LOOP;
 RETURN total;
END $$;
REVOKE ALL ON FUNCTION core10._sales_validate_v1(bigint,bigint,jsonb,jsonb) FROM PUBLIC,authenticated;
