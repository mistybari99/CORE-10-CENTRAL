-- NP02 / B-011 Master Data RPCs (Claude, block 0150-0199).
-- Writers: signed actor + can_manage + control_check_v1(feature) + optimistic version + request-key
-- idempotency + canonical audit. Read ports for other lanes are internal (no API grant):
--   master_validate_sales_order_v1(business, site, doc) -> boolean   (NP03B 0301 contract)
--   master_uom_convert_v1(business, from_uom, to_uom, qty) -> numeric (NP05A UOM contract)
--   master_item_usable_v1(business, item) -> boolean                 (NP05A item status)
-- Contract: docs/coordination/NP02_B011_MASTER_DATA_CONTRACT.md

INSERT INTO core10.control_catalog_v1
 (feature_key,title_en,title_bn,pack,default_enabled,default_stages,max_stages,allow_site_scope,approval_domain,approval_action,params) VALUES
 ('master.uom','Manage units of measure','পরিমাপের একক পরিচালনা','NP02',true,0,0,false,NULL,NULL,'{}'),
 ('master.item','Manage items, categories, variants and barcodes','পণ্য, শ্রেণি, ধরন ও বারকোড পরিচালনা','NP02',true,0,0,false,NULL,NULL,'{}'),
 ('master.party','Manage customers and suppliers','গ্রাহক ও সরবরাহকারী পরিচালনা','NP02',true,0,0,false,NULL,NULL,'{}'),
 ('master.price','Manage price lists and prices','মূল্য তালিকা ও দাম পরিচালনা','NP02',true,0,0,false,NULL,NULL,'{}');

-- Request-key ledger: one key = one effect per business; replay by the same actor returns the same row.
CREATE TABLE core10.master_requests_v1 (
 business_id bigint NOT NULL,
 request_key text NOT NULL CHECK (length(request_key) BETWEEN 8 AND 120),
 tenant_id bigint NOT NULL, actor_id uuid NOT NULL,
 entity text NOT NULL, entity_id bigint NOT NULL, version integer NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY (business_id, request_key),
 FOREIGN KEY (business_id, tenant_id) REFERENCES core10.businesses(id, tenant_id)
);
ALTER TABLE core10.master_requests_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON core10.master_requests_v1 FROM PUBLIC, authenticated;

-- Shared gate for every writer. Returns tenant_id; raises on any refusal.
CREATE FUNCTION core10._master_gate_v1(p_business bigint, p_feature text) RETURNS bigint
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE v_tenant bigint;
BEGIN
 SELECT tenant_id INTO v_tenant FROM core10.businesses WHERE id=p_business;
 IF core10.actor_uid() IS NULL OR v_tenant IS NULL OR NOT core10.can_manage(v_tenant,p_business)
 THEN RAISE EXCEPTION 'MASTER_AUTH_DENIED'; END IF;
 RETURN v_tenant;
END $$;

-- Replay lookup: same key + same actor + same entity -> previous id; different actor/entity -> refuse.
CREATE FUNCTION core10._master_replay_v1(p_business bigint, p_key text, p_entity text) RETURNS bigint
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE r core10.master_requests_v1%ROWTYPE;
BEGIN
 IF p_key IS NULL OR length(p_key) NOT BETWEEN 8 AND 120 THEN RAISE EXCEPTION 'MASTER_BAD_REQUEST_KEY'; END IF;
 SELECT * INTO r FROM core10.master_requests_v1 WHERE business_id=p_business AND request_key=p_key;
 IF NOT FOUND THEN RETURN NULL; END IF;
 IF r.actor_id IS DISTINCT FROM core10.actor_uid() OR r.entity<>p_entity THEN RAISE EXCEPTION 'MASTER_REQUEST_KEY_REUSED'; END IF;
 RETURN r.entity_id;
END $$;

CREATE FUNCTION core10._master_record_v1(p_tenant bigint, p_business bigint, p_key text, p_entity text,
 p_id bigint, p_version integer, p_action text, p_payload jsonb) RETURNS void
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
BEGIN
 INSERT INTO core10.master_requests_v1(business_id,request_key,tenant_id,actor_id,entity,entity_id,version)
 VALUES (p_business,p_key,p_tenant,core10.actor_uid(),p_entity,p_id,p_version);
 PERFORM core10._append_canonical_audit_v1(p_tenant,p_business,'master',p_entity||':'||p_id||':v'||p_version,
  p_action,core10.actor_uid(),'master:'||p_business||':'||p_key,p_payload||jsonb_build_object('id',p_id,'version',p_version));
END $$;

-- ---------- writers (expected_version 0 = create; N = update row currently at version N) ----------

CREATE FUNCTION core10.master_save_uom_v1(p_business bigint, p_code text, p_name_en text, p_name_bn text,
 p_dimension text, p_decimals smallint, p_active boolean, p_expected_version integer, p_request_key text) RETURNS bigint
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE t bigint:=core10._master_gate_v1(p_business,'master.uom'); v_id bigint; v_ver integer;
BEGIN
 PERFORM core10.control_check_v1(p_business,'master.uom',NULL);
 v_id:=core10._master_replay_v1(p_business,p_request_key,'uom'); IF v_id IS NOT NULL THEN RETURN v_id; END IF;
 IF coalesce(p_expected_version,-1)=0 THEN
  INSERT INTO core10.master_uoms_v1(tenant_id,business_id,code,name_en,name_bn,dimension,decimals,active,updated_by)
  VALUES (t,p_business,p_code,p_name_en,p_name_bn,p_dimension,coalesce(p_decimals,0),coalesce(p_active,true),core10.actor_uid())
  RETURNING id,version INTO v_id,v_ver;
 ELSE
  -- dimension is immutable once created: conversions and price lines depend on it
  UPDATE core10.master_uoms_v1 SET name_en=p_name_en,name_bn=p_name_bn,decimals=coalesce(p_decimals,decimals),
   active=coalesce(p_active,active),version=version+1,updated_at=now(),updated_by=core10.actor_uid()
  WHERE business_id=p_business AND code=p_code AND version=p_expected_version AND dimension=p_dimension
  RETURNING id,version INTO v_id,v_ver;
  IF v_id IS NULL THEN RAISE EXCEPTION 'MASTER_STALE_OR_MISSING'; END IF;
 END IF;
 PERFORM core10._master_record_v1(t,p_business,p_request_key,'uom',v_id,v_ver,'master.uom_save',jsonb_build_object('code',p_code,'dimension',p_dimension));
 RETURN v_id;
END $$;

CREATE FUNCTION core10.master_save_uom_conversion_v1(p_business bigint, p_from_uom bigint, p_to_uom bigint,
 p_factor numeric, p_active boolean, p_expected_version integer, p_request_key text) RETURNS bigint
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE t bigint:=core10._master_gate_v1(p_business,'master.uom'); v_id bigint; v_ver integer; v_dim text;
BEGIN
 PERFORM core10.control_check_v1(p_business,'master.uom',NULL);
 v_id:=core10._master_replay_v1(p_business,p_request_key,'uom_conversion'); IF v_id IS NOT NULL THEN RETURN v_id; END IF;
 SELECT dimension INTO v_dim FROM core10.master_uoms_v1 WHERE id=p_from_uom AND business_id=p_business;
 IF v_dim IS NULL THEN RAISE EXCEPTION 'MASTER_SCOPE'; END IF;
 IF coalesce(p_expected_version,-1)=0 THEN
  INSERT INTO core10.master_uom_conversions_v1(tenant_id,business_id,dimension,from_uom_id,to_uom_id,factor,active,updated_by)
  VALUES (t,p_business,v_dim,p_from_uom,p_to_uom,p_factor,coalesce(p_active,true),core10.actor_uid()) RETURNING id,version INTO v_id,v_ver;
 ELSE
  UPDATE core10.master_uom_conversions_v1 SET factor=p_factor,active=coalesce(p_active,active),version=version+1,updated_at=now(),updated_by=core10.actor_uid()
  WHERE business_id=p_business AND from_uom_id=p_from_uom AND to_uom_id=p_to_uom AND version=p_expected_version RETURNING id,version INTO v_id,v_ver;
  IF v_id IS NULL THEN RAISE EXCEPTION 'MASTER_STALE_OR_MISSING'; END IF;
 END IF;
 PERFORM core10._master_record_v1(t,p_business,p_request_key,'uom_conversion',v_id,v_ver,'master.uom_conversion_save',
  jsonb_build_object('from',p_from_uom,'to',p_to_uom,'factor',p_factor));
 RETURN v_id;
END $$;

CREATE FUNCTION core10.master_save_item_v1(p_business bigint, p_sku text, p_name_en text, p_name_bn text,
 p_item_kind text, p_category bigint, p_base_uom bigint, p_status text, p_expected_version integer, p_request_key text) RETURNS bigint
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE t bigint:=core10._master_gate_v1(p_business,'master.item'); v_id bigint; v_ver integer;
BEGIN
 PERFORM core10.control_check_v1(p_business,'master.item',NULL);
 v_id:=core10._master_replay_v1(p_business,p_request_key,'item'); IF v_id IS NOT NULL THEN RETURN v_id; END IF;
 IF p_name_en IS NULL THEN RAISE EXCEPTION 'MASTER_NAME_REQUIRED'; END IF;
 IF coalesce(p_expected_version,-1)=0 THEN
  INSERT INTO core10.items(tenant_id,business_id,sku,name_en,name_bn,item_kind,category_id,base_uom_id,status,updated_by)
  VALUES (t,p_business,p_sku,p_name_en,p_name_bn,coalesce(p_item_kind,'stock'),p_category,p_base_uom,coalesce(p_status,'active'),core10.actor_uid())
  RETURNING id,version INTO v_id,v_ver;
 ELSE
  UPDATE core10.items SET name_en=p_name_en,name_bn=p_name_bn,item_kind=coalesce(p_item_kind,item_kind),category_id=p_category,
   base_uom_id=p_base_uom,status=coalesce(p_status,status),version=version+1,updated_at=now(),updated_by=core10.actor_uid()
  WHERE business_id=p_business AND sku=p_sku AND version=p_expected_version RETURNING id,version INTO v_id,v_ver;
  IF v_id IS NULL THEN RAISE EXCEPTION 'MASTER_STALE_OR_MISSING'; END IF;
 END IF;
 PERFORM core10._master_record_v1(t,p_business,p_request_key,'item',v_id,v_ver,'master.item_save',jsonb_build_object('sku',p_sku,'status',coalesce(p_status,'active')));
 RETURN v_id;
END $$;

CREATE FUNCTION core10.master_save_category_v1(p_business bigint, p_code text, p_name_en text, p_name_bn text,
 p_parent bigint, p_active boolean, p_expected_version integer, p_request_key text) RETURNS bigint
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE t bigint:=core10._master_gate_v1(p_business,'master.item'); v_id bigint; v_ver integer;
BEGIN
 PERFORM core10.control_check_v1(p_business,'master.item',NULL);
 v_id:=core10._master_replay_v1(p_business,p_request_key,'category'); IF v_id IS NOT NULL THEN RETURN v_id; END IF;
 IF coalesce(p_expected_version,-1)=0 THEN
  INSERT INTO core10.master_item_categories_v1(tenant_id,business_id,code,name_en,name_bn,parent_id,active,updated_by)
  VALUES (t,p_business,p_code,p_name_en,p_name_bn,p_parent,coalesce(p_active,true),core10.actor_uid()) RETURNING id,version INTO v_id,v_ver;
 ELSE
  UPDATE core10.master_item_categories_v1 SET name_en=p_name_en,name_bn=p_name_bn,parent_id=p_parent,active=coalesce(p_active,active),
   version=version+1,updated_at=now(),updated_by=core10.actor_uid()
  WHERE business_id=p_business AND code=p_code AND version=p_expected_version RETURNING id,version INTO v_id,v_ver;
  IF v_id IS NULL THEN RAISE EXCEPTION 'MASTER_STALE_OR_MISSING'; END IF;
 END IF;
 PERFORM core10._master_record_v1(t,p_business,p_request_key,'category',v_id,v_ver,'master.category_save',jsonb_build_object('code',p_code));
 RETURN v_id;
END $$;

CREATE FUNCTION core10.master_save_variant_v1(p_business bigint, p_item bigint, p_code text, p_name_en text, p_name_bn text,
 p_attributes jsonb, p_status text, p_expected_version integer, p_request_key text) RETURNS bigint
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE t bigint:=core10._master_gate_v1(p_business,'master.item'); v_id bigint; v_ver integer;
BEGIN
 PERFORM core10.control_check_v1(p_business,'master.item',NULL);
 v_id:=core10._master_replay_v1(p_business,p_request_key,'variant'); IF v_id IS NOT NULL THEN RETURN v_id; END IF;
 IF coalesce(p_expected_version,-1)=0 THEN
  INSERT INTO core10.master_item_variants_v1(tenant_id,business_id,item_id,code,name_en,name_bn,attributes,status,updated_by)
  VALUES (t,p_business,p_item,p_code,p_name_en,p_name_bn,coalesce(p_attributes,'{}'),coalesce(p_status,'active'),core10.actor_uid()) RETURNING id,version INTO v_id,v_ver;
 ELSE
  UPDATE core10.master_item_variants_v1 SET name_en=p_name_en,name_bn=p_name_bn,attributes=coalesce(p_attributes,attributes),status=coalesce(p_status,status),
   version=version+1,updated_at=now(),updated_by=core10.actor_uid()
  WHERE business_id=p_business AND item_id=p_item AND code=p_code AND version=p_expected_version RETURNING id,version INTO v_id,v_ver;
  IF v_id IS NULL THEN RAISE EXCEPTION 'MASTER_STALE_OR_MISSING'; END IF;
 END IF;
 PERFORM core10._master_record_v1(t,p_business,p_request_key,'variant',v_id,v_ver,'master.variant_save',jsonb_build_object('item',p_item,'code',p_code));
 RETURN v_id;
END $$;

CREATE FUNCTION core10.master_save_barcode_v1(p_business bigint, p_barcode text, p_item bigint, p_variant bigint, p_uom bigint,
 p_active boolean, p_expected_version integer, p_request_key text) RETURNS bigint
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE t bigint:=core10._master_gate_v1(p_business,'master.item'); v_id bigint; v_ver integer;
BEGIN
 PERFORM core10.control_check_v1(p_business,'master.item',NULL);
 v_id:=core10._master_replay_v1(p_business,p_request_key,'barcode'); IF v_id IS NOT NULL THEN RETURN v_id; END IF;
 IF coalesce(p_expected_version,-1)=0 THEN
  INSERT INTO core10.master_item_barcodes_v1(tenant_id,business_id,item_id,variant_id,uom_id,barcode,active,updated_by)
  VALUES (t,p_business,p_item,p_variant,p_uom,p_barcode,coalesce(p_active,true),core10.actor_uid()) RETURNING id,version INTO v_id,v_ver;
 ELSE
  UPDATE core10.master_item_barcodes_v1 SET item_id=p_item,variant_id=p_variant,uom_id=p_uom,active=coalesce(p_active,active),
   version=version+1,updated_at=now(),updated_by=core10.actor_uid()
  WHERE business_id=p_business AND barcode=p_barcode AND version=p_expected_version RETURNING id,version INTO v_id,v_ver;
  IF v_id IS NULL THEN RAISE EXCEPTION 'MASTER_STALE_OR_MISSING'; END IF;
 END IF;
 PERFORM core10._master_record_v1(t,p_business,p_request_key,'barcode',v_id,v_ver,'master.barcode_save',jsonb_build_object('barcode',p_barcode,'item',p_item));
 RETURN v_id;
END $$;

CREATE FUNCTION core10.master_save_party_v1(p_business bigint, p_code text, p_party_kind text, p_name_en text, p_name_bn text,
 p_phone text, p_tax_id text, p_status text, p_expected_version integer, p_request_key text) RETURNS bigint
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE t bigint:=core10._master_gate_v1(p_business,'master.party'); v_id bigint; v_ver integer;
BEGIN
 PERFORM core10.control_check_v1(p_business,'master.party',NULL);
 v_id:=core10._master_replay_v1(p_business,p_request_key,'party'); IF v_id IS NOT NULL THEN RETURN v_id; END IF;
 IF coalesce(p_expected_version,-1)=0 THEN
  INSERT INTO core10.master_parties_v1(tenant_id,business_id,code,party_kind,name_en,name_bn,phone,tax_id,status,updated_by)
  VALUES (t,p_business,p_code,p_party_kind,p_name_en,p_name_bn,p_phone,p_tax_id,coalesce(p_status,'active'),core10.actor_uid()) RETURNING id,version INTO v_id,v_ver;
 ELSE
  UPDATE core10.master_parties_v1 SET party_kind=p_party_kind,name_en=p_name_en,name_bn=p_name_bn,phone=p_phone,tax_id=p_tax_id,
   status=coalesce(p_status,status),version=version+1,updated_at=now(),updated_by=core10.actor_uid()
  WHERE business_id=p_business AND code=p_code AND version=p_expected_version RETURNING id,version INTO v_id,v_ver;
  IF v_id IS NULL THEN RAISE EXCEPTION 'MASTER_STALE_OR_MISSING'; END IF;
 END IF;
 PERFORM core10._master_record_v1(t,p_business,p_request_key,'party',v_id,v_ver,'master.party_save',jsonb_build_object('code',p_code,'kind',p_party_kind));
 RETURN v_id;
END $$;

CREATE FUNCTION core10.master_save_price_list_v1(p_business bigint, p_code text, p_name_en text, p_name_bn text, p_list_kind text,
 p_currency text, p_site bigint, p_effective_from date, p_effective_to date, p_status text, p_expected_version integer, p_request_key text) RETURNS bigint
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE t bigint:=core10._master_gate_v1(p_business,'master.price'); v_id bigint; v_ver integer;
BEGIN
 PERFORM core10.control_check_v1(p_business,'master.price',NULL);
 v_id:=core10._master_replay_v1(p_business,p_request_key,'price_list'); IF v_id IS NOT NULL THEN RETURN v_id; END IF;
 IF p_site IS NOT NULL AND NOT EXISTS(SELECT 1 FROM core10.sites WHERE id=p_site AND business_id=p_business AND tenant_id=t)
 THEN RAISE EXCEPTION 'MASTER_SCOPE'; END IF;
 IF coalesce(p_expected_version,-1)=0 THEN
  INSERT INTO core10.master_price_lists_v1(tenant_id,business_id,code,name_en,name_bn,list_kind,currency,site_id,effective_from,effective_to,status,updated_by)
  VALUES (t,p_business,p_code,p_name_en,p_name_bn,p_list_kind,p_currency,p_site,p_effective_from,p_effective_to,coalesce(p_status,'active'),core10.actor_uid())
  RETURNING id,version INTO v_id,v_ver;
 ELSE
  -- list kind and currency are fixed after creation (price lines and orders depend on them)
  UPDATE core10.master_price_lists_v1 SET name_en=p_name_en,name_bn=p_name_bn,site_id=p_site,effective_from=p_effective_from,
   effective_to=p_effective_to,status=coalesce(p_status,status),version=version+1,updated_at=now(),updated_by=core10.actor_uid()
  WHERE business_id=p_business AND code=p_code AND version=p_expected_version AND list_kind=p_list_kind AND currency=p_currency
  RETURNING id,version INTO v_id,v_ver;
  IF v_id IS NULL THEN RAISE EXCEPTION 'MASTER_STALE_OR_MISSING'; END IF;
 END IF;
 PERFORM core10._master_record_v1(t,p_business,p_request_key,'price_list',v_id,v_ver,'master.price_list_save',jsonb_build_object('code',p_code,'kind',p_list_kind,'currency',p_currency));
 RETURN v_id;
END $$;

CREATE FUNCTION core10.master_save_price_v1(p_business bigint, p_price_list bigint, p_item bigint, p_variant bigint, p_uom bigint,
 p_min_quantity numeric, p_unit_price numeric, p_active boolean, p_expected_version integer, p_request_key text) RETURNS bigint
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE t bigint:=core10._master_gate_v1(p_business,'master.price'); v_id bigint; v_ver integer;
BEGIN
 PERFORM core10.control_check_v1(p_business,'master.price',NULL);
 v_id:=core10._master_replay_v1(p_business,p_request_key,'price'); IF v_id IS NOT NULL THEN RETURN v_id; END IF;
 IF coalesce(p_expected_version,-1)=0 THEN
  INSERT INTO core10.master_price_list_items_v1(tenant_id,business_id,price_list_id,item_id,variant_id,uom_id,min_quantity,unit_price,active,updated_by)
  VALUES (t,p_business,p_price_list,p_item,p_variant,p_uom,coalesce(p_min_quantity,0),p_unit_price,coalesce(p_active,true),core10.actor_uid())
  RETURNING id,version INTO v_id,v_ver;
 ELSE
  UPDATE core10.master_price_list_items_v1 SET unit_price=p_unit_price,active=coalesce(p_active,active),version=version+1,updated_at=now(),updated_by=core10.actor_uid()
  WHERE business_id=p_business AND price_list_id=p_price_list AND item_id=p_item AND coalesce(variant_id,0)=coalesce(p_variant,0)
   AND uom_id=p_uom AND min_quantity=coalesce(p_min_quantity,0) AND version=p_expected_version RETURNING id,version INTO v_id,v_ver;
  IF v_id IS NULL THEN RAISE EXCEPTION 'MASTER_STALE_OR_MISSING'; END IF;
 END IF;
 PERFORM core10._master_record_v1(t,p_business,p_request_key,'price',v_id,v_ver,'master.price_save',
  jsonb_build_object('price_list',p_price_list,'item',p_item,'uom',p_uom,'unit_price',p_unit_price));
 RETURN v_id;
END $$;

-- ---------- internal read ports for other lanes (no API grant; called from their SECURITY DEFINER code) ----------

CREATE FUNCTION core10.master_item_usable_v1(p_business bigint, p_item bigint) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
 SELECT EXISTS(SELECT 1 FROM core10.items WHERE id=p_item AND business_id=p_business AND status='active')
$$;

-- Same-dimension conversion only: direct factor, inverse factor, or identity. Never guesses.
CREATE FUNCTION core10.master_uom_convert_v1(p_business bigint, p_from_uom bigint, p_to_uom bigint, p_quantity numeric) RETURNS numeric
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE f numeric;
BEGIN
 IF p_quantity IS NULL OR p_quantity::text IN ('NaN','Infinity','-Infinity') THEN RAISE EXCEPTION 'MASTER_UOM_BAD_QUANTITY'; END IF;
 IF NOT EXISTS(SELECT 1 FROM core10.master_uoms_v1 WHERE id=p_from_uom AND business_id=p_business AND active)
  OR NOT EXISTS(SELECT 1 FROM core10.master_uoms_v1 WHERE id=p_to_uom AND business_id=p_business AND active)
 THEN RAISE EXCEPTION 'MASTER_UOM_SCOPE'; END IF;
 IF p_from_uom=p_to_uom THEN RETURN p_quantity; END IF;
 SELECT factor INTO f FROM core10.master_uom_conversions_v1 WHERE business_id=p_business AND from_uom_id=p_from_uom AND to_uom_id=p_to_uom AND active;
 IF f IS NOT NULL THEN RETURN p_quantity*f; END IF;
 SELECT 1/factor INTO f FROM core10.master_uom_conversions_v1 WHERE business_id=p_business AND from_uom_id=p_to_uom AND to_uom_id=p_from_uom AND active;
 IF f IS NOT NULL THEN RETURN p_quantity*f; END IF;
 RAISE EXCEPTION 'MASTER_UOM_NO_CONVERSION';
END $$;

-- NP03B contract: TRUE only when every master reference in the order is valid, in scope, active and priced.
-- Never raises for bad input (returns FALSE), so the caller can refuse with its own error.
CREATE FUNCTION core10.master_validate_sales_order_v1(p_business bigint, p_site bigint, p_doc jsonb) RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE l jsonb; pl core10.master_price_lists_v1%ROWTYPE; it core10.items%ROWTYPE;
 v_uom_dim text; v_base_dim text; v_price numeric; v_qty numeric; v_variant bigint; v_uom bigint;
BEGIN
 IF p_business IS NULL OR p_doc IS NULL OR jsonb_typeof(p_doc)<>'object' OR jsonb_typeof(p_doc->'lines')<>'array'
  OR jsonb_array_length(p_doc->'lines')=0 OR jsonb_typeof(p_doc->'customer_id')<>'number' OR jsonb_typeof(p_doc->'price_list_id')<>'number'
 THEN RETURN false; END IF;
 IF p_site IS NOT NULL AND NOT EXISTS(SELECT 1 FROM core10.sites WHERE id=p_site AND business_id=p_business) THEN RETURN false; END IF;
 IF NOT EXISTS(SELECT 1 FROM core10.master_parties_v1 WHERE id=(p_doc->>'customer_id')::bigint AND business_id=p_business
   AND party_kind IN ('customer','both') AND status='active') THEN RETURN false; END IF;
 SELECT * INTO pl FROM core10.master_price_lists_v1 WHERE id=(p_doc->>'price_list_id')::bigint AND business_id=p_business
  AND list_kind='sales' AND status='active' AND effective_from<=current_date AND (effective_to IS NULL OR effective_to>=current_date)
  AND (site_id IS NULL OR site_id=p_site);
 IF NOT FOUND THEN RETURN false; END IF;
 FOR l IN SELECT * FROM jsonb_array_elements(p_doc->'lines') LOOP
  IF jsonb_typeof(l)<>'object' OR jsonb_typeof(l->'item_id')<>'number' OR jsonb_typeof(l->'uom_id')<>'number'
   OR jsonb_typeof(l->'quantity')<>'number' OR jsonb_typeof(l->'unit_price')<>'number'
   OR (l ? 'variant_id' AND jsonb_typeof(l->'variant_id') NOT IN ('number','null')) THEN RETURN false; END IF;
  v_qty:=(l->>'quantity')::numeric; v_uom:=(l->>'uom_id')::bigint; v_variant:=nullif(l->>'variant_id','')::bigint;
  IF v_qty<=0 THEN RETURN false; END IF;
  SELECT * INTO it FROM core10.items WHERE id=(l->>'item_id')::bigint AND business_id=p_business AND status='active';
  IF NOT FOUND THEN RETURN false; END IF;
  IF v_variant IS NOT NULL AND NOT EXISTS(SELECT 1 FROM core10.master_item_variants_v1 WHERE id=v_variant AND item_id=it.id AND status='active')
  THEN RETURN false; END IF;
  SELECT dimension INTO v_uom_dim FROM core10.master_uoms_v1 WHERE id=v_uom AND business_id=p_business AND active;
  IF v_uom_dim IS NULL THEN RETURN false; END IF;
  IF it.base_uom_id IS NOT NULL THEN
   SELECT dimension INTO v_base_dim FROM core10.master_uoms_v1 WHERE id=it.base_uom_id;
   IF v_base_dim IS DISTINCT FROM v_uom_dim THEN RETURN false; END IF;
  END IF;
  -- price: the active line for this list/item/variant/uom with the highest min_quantity not above the order quantity
  SELECT unit_price INTO v_price FROM core10.master_price_list_items_v1
  WHERE price_list_id=pl.id AND item_id=it.id AND coalesce(variant_id,0)=coalesce(v_variant,0) AND uom_id=v_uom AND active AND min_quantity<=v_qty
  ORDER BY min_quantity DESC LIMIT 1;
  IF v_price IS NULL OR v_price<>(l->>'unit_price')::numeric THEN RETURN false; END IF;
 END LOOP;
 RETURN true;
EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range OR data_exception THEN RETURN false;
END $$;

REVOKE ALL ON FUNCTION core10._master_gate_v1(bigint,text), core10._master_replay_v1(bigint,text,text),
 core10._master_record_v1(bigint,bigint,text,text,bigint,integer,text,jsonb),
 core10.master_item_usable_v1(bigint,bigint), core10.master_uom_convert_v1(bigint,bigint,bigint,numeric),
 core10.master_validate_sales_order_v1(bigint,bigint,jsonb) FROM PUBLIC, authenticated;

REVOKE ALL ON FUNCTION
 core10.master_save_uom_v1(bigint,text,text,text,text,smallint,boolean,integer,text),
 core10.master_save_uom_conversion_v1(bigint,bigint,bigint,numeric,boolean,integer,text),
 core10.master_save_item_v1(bigint,text,text,text,text,bigint,bigint,text,integer,text),
 core10.master_save_category_v1(bigint,text,text,text,bigint,boolean,integer,text),
 core10.master_save_variant_v1(bigint,bigint,text,text,text,jsonb,text,integer,text),
 core10.master_save_barcode_v1(bigint,text,bigint,bigint,bigint,boolean,integer,text),
 core10.master_save_party_v1(bigint,text,text,text,text,text,text,text,integer,text),
 core10.master_save_price_list_v1(bigint,text,text,text,text,text,bigint,date,date,text,integer,text),
 core10.master_save_price_v1(bigint,bigint,bigint,bigint,bigint,numeric,numeric,boolean,integer,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION
 core10.master_save_uom_v1(bigint,text,text,text,text,smallint,boolean,integer,text),
 core10.master_save_uom_conversion_v1(bigint,bigint,bigint,numeric,boolean,integer,text),
 core10.master_save_item_v1(bigint,text,text,text,text,bigint,bigint,text,integer,text),
 core10.master_save_category_v1(bigint,text,text,text,bigint,boolean,integer,text),
 core10.master_save_variant_v1(bigint,bigint,text,text,text,jsonb,text,integer,text),
 core10.master_save_barcode_v1(bigint,text,bigint,bigint,bigint,boolean,integer,text),
 core10.master_save_party_v1(bigint,text,text,text,text,text,text,text,integer,text),
 core10.master_save_price_list_v1(bigint,text,text,text,text,text,bigint,date,date,text,integer,text),
 core10.master_save_price_v1(bigint,bigint,bigint,bigint,bigint,numeric,numeric,boolean,integer,text) TO authenticated;

INSERT INTO core10.control_rpc_map_v1(rpc_name,status,feature_key,reason,lane,board_row,test_ref) VALUES
 ('master_save_uom_v1','enforced','master.uom','Owner/manager UOM save checks canonical control, version and audit','Claude','B-011','tests/migrations/np02-master-rpc-e2e.sql'),
 ('master_save_uom_conversion_v1','enforced','master.uom','Same-dimension conversion save checks canonical control and audit','Claude','B-011','tests/migrations/np02-master-rpc-e2e.sql'),
 ('master_save_item_v1','enforced','master.item','Item save on core10.items checks canonical control, version and audit','Claude','B-011','tests/migrations/np02-master-rpc-e2e.sql'),
 ('master_save_category_v1','enforced','master.item','Category save checks canonical control and audit','Claude','B-011','tests/migrations/np02-master-rpc-e2e.sql'),
 ('master_save_variant_v1','enforced','master.item','Variant save checks canonical control and audit','Claude','B-011','tests/migrations/np02-master-rpc-e2e.sql'),
 ('master_save_barcode_v1','enforced','master.item','Barcode save checks canonical control and audit','Claude','B-011','tests/migrations/np02-master-rpc-e2e.sql'),
 ('master_save_party_v1','enforced','master.party','Customer/supplier save checks canonical control and audit','Claude','B-011','tests/migrations/np02-master-rpc-e2e.sql'),
 ('master_save_price_list_v1','enforced','master.price','Price list save checks canonical control and audit','Claude','B-011','tests/migrations/np02-master-rpc-e2e.sql'),
 ('master_save_price_v1','enforced','master.price','Price line save checks canonical control and audit','Claude','B-011','tests/migrations/np02-master-rpc-e2e.sql');
