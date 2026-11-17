-- NP02 / B-011 Master Data read RPCs for the Central Master Data screens (Claude, block 0150-0199).
-- STABLE, SECURITY DEFINER with pinned search_path, executable by authenticated only. Every function
-- first resolves the business, requires a signed actor and core10.can_see_business; a business the
-- caller cannot see returns MASTER_SCOPE (no existence oracle: same error for missing and hidden).
-- Lists use keyset pagination (p_after_id) with a bounded page size; search is case-insensitive and
-- matches code/SKU/name_en/name_bn/barcode. No table grants change: tables stay RPC-only.

CREATE FUNCTION core10._master_read_gate_v1(p_business bigint) RETURNS bigint
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE v_tenant bigint;
BEGIN
 SELECT tenant_id INTO v_tenant FROM core10.businesses WHERE id=p_business;
 IF core10.actor_uid() IS NULL OR v_tenant IS NULL OR NOT core10.can_see_business(v_tenant,p_business)
 THEN RAISE EXCEPTION 'MASTER_SCOPE'; END IF;
 RETURN v_tenant;
END $$;

CREATE FUNCTION core10._master_page_v1(p_limit integer) RETURNS integer
LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $$ SELECT least(greatest(coalesce(p_limit,50),1),200) $$;

CREATE FUNCTION core10._master_like_v1(p_search text) RETURNS text
LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $$
 SELECT CASE WHEN p_search IS NULL OR btrim(p_search)='' THEN NULL
  ELSE '%'||replace(replace(replace(left(btrim(p_search),80),'\','\\'),'%','\%'),'_','\_')||'%' END $$;

CREATE FUNCTION core10.master_list_items_v1(p_business bigint, p_search text DEFAULT NULL, p_status text DEFAULT NULL,
 p_category bigint DEFAULT NULL, p_limit integer DEFAULT 50, p_after_id bigint DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE n integer:=core10._master_page_v1(p_limit); q text:=core10._master_like_v1(p_search); rows jsonb;
BEGIN
 PERFORM core10._master_read_gate_v1(p_business);
 SELECT coalesce(jsonb_agg(r ORDER BY (r->>'id')::bigint),'[]') INTO rows FROM (
  SELECT jsonb_build_object('id',i.id,'sku',i.sku,'name_en',i.name_en,'name_bn',i.name_bn,'item_kind',i.item_kind,
   'category_id',i.category_id,'base_uom_id',i.base_uom_id,'base_uom_code',u.code,'status',i.status,'version',i.version,
   'variant_count',(SELECT count(*) FROM core10.master_item_variants_v1 v WHERE v.item_id=i.id),'updated_at',i.updated_at) r
  FROM core10.items i LEFT JOIN core10.master_uoms_v1 u ON u.id=i.base_uom_id
  WHERE i.business_id=p_business AND (p_after_id IS NULL OR i.id>p_after_id)
   AND (p_status IS NULL OR i.status=p_status) AND (p_category IS NULL OR i.category_id=p_category)
   AND (q IS NULL OR i.sku ILIKE q OR i.name_en ILIKE q OR i.name_bn ILIKE q
        OR EXISTS(SELECT 1 FROM core10.master_item_barcodes_v1 b WHERE b.item_id=i.id AND b.barcode ILIKE q))
  ORDER BY i.id LIMIT n+1) x;
 RETURN jsonb_build_object('rows',(SELECT coalesce(jsonb_agg(e),'[]') FROM (SELECT e FROM jsonb_array_elements(rows) WITH ORDINALITY t(e,o) WHERE o<=n) y),
  'next_after_id',CASE WHEN jsonb_array_length(rows)>n THEN (rows->(n-1)->>'id')::bigint END);
END $$;

CREATE FUNCTION core10.master_get_item_v1(p_business bigint, p_item bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE i core10.items%ROWTYPE;
BEGIN
 PERFORM core10._master_read_gate_v1(p_business);
 SELECT * INTO i FROM core10.items WHERE id=p_item AND business_id=p_business;
 IF NOT FOUND THEN RAISE EXCEPTION 'MASTER_NOT_FOUND'; END IF;
 RETURN jsonb_build_object('id',i.id,'sku',i.sku,'name_en',i.name_en,'name_bn',i.name_bn,'item_kind',i.item_kind,
  'category_id',i.category_id,'base_uom_id',i.base_uom_id,'status',i.status,'version',i.version,'updated_at',i.updated_at,
  'variants',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',v.id,'code',v.code,'name_en',v.name_en,'name_bn',v.name_bn,
     'attributes',v.attributes,'status',v.status,'version',v.version) ORDER BY v.code),'[]') FROM core10.master_item_variants_v1 v WHERE v.item_id=i.id),
  'barcodes',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',b.id,'barcode',b.barcode,'variant_id',b.variant_id,'uom_id',b.uom_id,
     'active',b.active,'version',b.version) ORDER BY b.barcode),'[]') FROM core10.master_item_barcodes_v1 b WHERE b.item_id=i.id),
  'prices',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',p.id,'price_list_id',p.price_list_id,'price_list_code',l.code,
     'list_kind',l.list_kind,'currency',l.currency,'variant_id',p.variant_id,'uom_id',p.uom_id,'min_quantity',p.min_quantity,
     'unit_price',p.unit_price,'active',p.active,'version',p.version) ORDER BY l.code,p.min_quantity),'[]')
     FROM core10.master_price_list_items_v1 p JOIN core10.master_price_lists_v1 l ON l.id=p.price_list_id WHERE p.item_id=i.id));
END $$;

CREATE FUNCTION core10.master_list_categories_v1(p_business bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
BEGIN
 PERFORM core10._master_read_gate_v1(p_business);
 RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object('id',c.id,'code',c.code,'name_en',c.name_en,'name_bn',c.name_bn,
  'parent_id',c.parent_id,'active',c.active,'version',c.version) ORDER BY c.code),'[]')
  FROM core10.master_item_categories_v1 c WHERE c.business_id=p_business);
END $$;

CREATE FUNCTION core10.master_list_uoms_v1(p_business bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
BEGIN
 PERFORM core10._master_read_gate_v1(p_business);
 RETURN jsonb_build_object(
  'uoms',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',u.id,'code',u.code,'name_en',u.name_en,'name_bn',u.name_bn,
    'dimension',u.dimension,'decimals',u.decimals,'active',u.active,'version',u.version) ORDER BY u.dimension,u.code),'[]')
    FROM core10.master_uoms_v1 u WHERE u.business_id=p_business),
  'conversions',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',c.id,'dimension',c.dimension,'from_uom_id',c.from_uom_id,
    'to_uom_id',c.to_uom_id,'factor',c.factor,'active',c.active,'version',c.version) ORDER BY c.id),'[]')
    FROM core10.master_uom_conversions_v1 c WHERE c.business_id=p_business));
END $$;

CREATE FUNCTION core10.master_list_parties_v1(p_business bigint, p_kind text DEFAULT NULL, p_search text DEFAULT NULL,
 p_status text DEFAULT NULL, p_limit integer DEFAULT 50, p_after_id bigint DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE n integer:=core10._master_page_v1(p_limit); q text:=core10._master_like_v1(p_search); rows jsonb;
BEGIN
 PERFORM core10._master_read_gate_v1(p_business);
 SELECT coalesce(jsonb_agg(r ORDER BY (r->>'id')::bigint),'[]') INTO rows FROM (
  SELECT jsonb_build_object('id',p.id,'code',p.code,'party_kind',p.party_kind,'name_en',p.name_en,'name_bn',p.name_bn,
   'phone',p.phone,'tax_id',p.tax_id,'status',p.status,'version',p.version) r
  FROM core10.master_parties_v1 p
  WHERE p.business_id=p_business AND (p_after_id IS NULL OR p.id>p_after_id) AND (p_status IS NULL OR p.status=p_status)
   AND (p_kind IS NULL OR p.party_kind=p_kind OR p.party_kind='both')
   AND (q IS NULL OR p.code ILIKE q OR p.name_en ILIKE q OR p.name_bn ILIKE q OR p.phone ILIKE q)
  ORDER BY p.id LIMIT n+1) x;
 RETURN jsonb_build_object('rows',(SELECT coalesce(jsonb_agg(e),'[]') FROM (SELECT e FROM jsonb_array_elements(rows) WITH ORDINALITY t(e,o) WHERE o<=n) y),
  'next_after_id',CASE WHEN jsonb_array_length(rows)>n THEN (rows->(n-1)->>'id')::bigint END);
END $$;

CREATE FUNCTION core10.master_list_price_lists_v1(p_business bigint, p_kind text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
BEGIN
 PERFORM core10._master_read_gate_v1(p_business);
 RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object('id',l.id,'code',l.code,'name_en',l.name_en,'name_bn',l.name_bn,
  'list_kind',l.list_kind,'currency',l.currency,'site_id',l.site_id,'effective_from',l.effective_from,'effective_to',l.effective_to,
  'status',l.status,'version',l.version,'line_count',(SELECT count(*) FROM core10.master_price_list_items_v1 p WHERE p.price_list_id=l.id))
  ORDER BY l.code),'[]') FROM core10.master_price_lists_v1 l WHERE l.business_id=p_business AND (p_kind IS NULL OR l.list_kind=p_kind));
END $$;

CREATE FUNCTION core10.master_get_price_list_v1(p_business bigint, p_price_list bigint, p_limit integer DEFAULT 100,
 p_after_id bigint DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE n integer:=core10._master_page_v1(p_limit); l core10.master_price_lists_v1%ROWTYPE; rows jsonb;
BEGIN
 PERFORM core10._master_read_gate_v1(p_business);
 SELECT * INTO l FROM core10.master_price_lists_v1 WHERE id=p_price_list AND business_id=p_business;
 IF NOT FOUND THEN RAISE EXCEPTION 'MASTER_NOT_FOUND'; END IF;
 SELECT coalesce(jsonb_agg(r ORDER BY (r->>'id')::bigint),'[]') INTO rows FROM (
  SELECT jsonb_build_object('id',p.id,'item_id',p.item_id,'sku',i.sku,'name_en',i.name_en,'name_bn',i.name_bn,'variant_id',p.variant_id,
   'uom_id',p.uom_id,'uom_code',u.code,'min_quantity',p.min_quantity,'unit_price',p.unit_price,'active',p.active,'version',p.version) r
  FROM core10.master_price_list_items_v1 p JOIN core10.items i ON i.id=p.item_id JOIN core10.master_uoms_v1 u ON u.id=p.uom_id
  WHERE p.price_list_id=l.id AND (p_after_id IS NULL OR p.id>p_after_id) ORDER BY p.id LIMIT n+1) x;
 RETURN jsonb_build_object('id',l.id,'code',l.code,'name_en',l.name_en,'name_bn',l.name_bn,'list_kind',l.list_kind,'currency',l.currency,
  'site_id',l.site_id,'effective_from',l.effective_from,'effective_to',l.effective_to,'status',l.status,'version',l.version,
  'rows',(SELECT coalesce(jsonb_agg(e),'[]') FROM (SELECT e FROM jsonb_array_elements(rows) WITH ORDINALITY t(e,o) WHERE o<=n) y),
  'next_after_id',CASE WHEN jsonb_array_length(rows)>n THEN (rows->(n-1)->>'id')::bigint END);
END $$;

CREATE FUNCTION core10.master_find_barcode_v1(p_business bigint, p_barcode text) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE r jsonb;
BEGIN
 PERFORM core10._master_read_gate_v1(p_business);
 SELECT jsonb_build_object('barcode',b.barcode,'item_id',b.item_id,'sku',i.sku,'name_en',i.name_en,'name_bn',i.name_bn,
  'variant_id',b.variant_id,'uom_id',b.uom_id,'item_status',i.status,'active',b.active) INTO r
 FROM core10.master_item_barcodes_v1 b JOIN core10.items i ON i.id=b.item_id
 WHERE b.business_id=p_business AND b.barcode=p_barcode;
 IF r IS NULL THEN RAISE EXCEPTION 'MASTER_NOT_FOUND'; END IF;
 RETURN r;
END $$;

REVOKE ALL ON FUNCTION core10._master_read_gate_v1(bigint), core10._master_page_v1(integer), core10._master_like_v1(text) FROM PUBLIC, authenticated;
REVOKE ALL ON FUNCTION
 core10.master_list_items_v1(bigint,text,text,bigint,integer,bigint), core10.master_get_item_v1(bigint,bigint),
 core10.master_list_categories_v1(bigint), core10.master_list_uoms_v1(bigint),
 core10.master_list_parties_v1(bigint,text,text,text,integer,bigint), core10.master_list_price_lists_v1(bigint,text),
 core10.master_get_price_list_v1(bigint,bigint,integer,bigint), core10.master_find_barcode_v1(bigint,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION
 core10.master_list_items_v1(bigint,text,text,bigint,integer,bigint), core10.master_get_item_v1(bigint,bigint),
 core10.master_list_categories_v1(bigint), core10.master_list_uoms_v1(bigint),
 core10.master_list_parties_v1(bigint,text,text,text,integer,bigint), core10.master_list_price_lists_v1(bigint,text),
 core10.master_get_price_list_v1(bigint,bigint,integer,bigint), core10.master_find_barcode_v1(bigint,text) TO authenticated;
