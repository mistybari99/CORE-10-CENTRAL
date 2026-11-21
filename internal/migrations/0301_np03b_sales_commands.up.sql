-- B-014: reuse A049 Auth-before-replay, optimistic version and atomic command
-- pattern, A026 multi-line totals, canonical 0008 audit and GOV002 source binding.
-- Missing Master is an explicit NOT_CONNECTED boundary; never install a stub here.
CREATE FUNCTION core10._sales_scope_v1(p_business bigint,p_site bigint) RETURNS bigint
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE t bigint;
BEGIN
 SELECT tenant_id INTO t FROM core10.sites WHERE id=p_site AND business_id=p_business;
 -- Interim owner-only fence. Stock read is an additional site-deny check, never
 -- a grant of Sales authority. NP01 Sales actions are a coordination dependency.
 IF core10.actor_uid() IS NULL OR t IS NULL OR NOT core10.can_manage(t,p_business)
    OR NOT core10.can_site(t,p_business,p_site,'stock.read')
 THEN RAISE EXCEPTION 'SALES_SCOPE_DENIED' USING ERRCODE='42501'; END IF;
 RETURN t;
END $$;
REVOKE ALL ON FUNCTION core10._sales_scope_v1(bigint,bigint) FROM PUBLIC,authenticated;

CREATE FUNCTION core10._sales_validate_v1(p_business bigint,p_site bigint,p_doc jsonb,p_params jsonb)
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

CREATE FUNCTION core10.save_sales_order_v1(p_business bigint,p_site bigint,p_order bigint,
 p_expected bigint,p_document jsonb,p_key text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE t bigint; c jsonb; cmd jsonb; old core10.sales_order_commands_v1%ROWTYPE;
 o core10.sales_orders_v1%ROWTYPE; amount numeric; r jsonb; audit_id bigint; scale integer;
BEGIN
 t:=core10._sales_scope_v1(p_business,p_site);
 IF p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{8,100}$' OR p_expected IS NULL
    OR (p_order IS NULL AND p_expected<>0) OR (p_order IS NOT NULL AND p_expected<1)
 THEN RAISE EXCEPTION 'SALES_COMMAND_INVALID'; END IF;
 cmd:=jsonb_build_object('op','save','site_id',p_site,'order_id',p_order,'expected',p_expected,'document',p_document);
 PERFORM pg_advisory_xact_lock(hashtextextended('sales-key:'||p_business||':'||p_key,0));
 IF p_order IS NOT NULL THEN
  SELECT * INTO o FROM core10.sales_orders_v1 WHERE id=p_order AND tenant_id=t AND business_id=p_business AND site_id=p_site FOR UPDATE;
 END IF;
 -- Refresh authorization after any lock wait, before replay or mutation.
 t:=core10._sales_scope_v1(p_business,p_site);
 c:=core10.control_check_v1(p_business,'sales.order_draft',p_site);
 SELECT * INTO old FROM core10.sales_order_commands_v1 WHERE business_id=p_business AND request_key=p_key;
 IF FOUND THEN
  IF old.actor_id<>core10.actor_uid() OR old.input IS DISTINCT FROM cmd THEN RAISE EXCEPTION 'SALES_REPLAY_CONFLICT'; END IF;
  RETURN old.receipt;
 END IF;
 IF p_order IS NOT NULL THEN
  IF o.id IS NULL THEN RAISE EXCEPTION 'SALES_ORDER_NOT_FOUND'; END IF;
  IF o.version<>p_expected THEN RAISE EXCEPTION 'SALES_STALE_VERSION'; END IF;
  IF o.status<>'draft' THEN RAISE EXCEPTION 'SALES_INVALID_TRANSITION'; END IF;
 END IF;
 amount:=core10._sales_validate_v1(p_business,p_site,p_document,c->'params');
 scale:=(c->'params'->>'money_scale')::integer;
 IF p_order IS NULL THEN
  INSERT INTO core10.sales_orders_v1(tenant_id,business_id,site_id,customer_id,price_list_id,currency,document,total,created_by,changed_by)
  VALUES(t,p_business,p_site,(p_document->>'customer_id')::bigint,(p_document->>'price_list_id')::bigint,
    p_document->>'currency',p_document,amount,core10.actor_uid(),core10.actor_uid()) RETURNING * INTO o;
 ELSE
  UPDATE core10.sales_orders_v1 SET customer_id=(p_document->>'customer_id')::bigint,
   price_list_id=(p_document->>'price_list_id')::bigint,currency=p_document->>'currency',document=p_document,
   total=amount,version=version+1,changed_by=core10.actor_uid(),changed_at=clock_timestamp()
  WHERE id=p_order RETURNING * INTO o;
  DELETE FROM core10.sales_order_lines_v1 WHERE order_id=o.id;
 END IF;
 INSERT INTO core10.sales_order_lines_v1(order_id,tenant_id,business_id,site_id,line_no,item_id,variant_id,uom_id,
  quantity,unit_price,discount_percent,tax_percent,line_total)
 SELECT o.id,t,p_business,p_site,n,(l->>'item_id')::bigint,(l->>'variant_id')::bigint,(l->>'uom_id')::bigint,
  (l->>'quantity')::numeric,(l->>'unit_price')::numeric,(l->>'discount_percent')::numeric,(l->>'tax_percent')::numeric,
  round((l->>'quantity')::numeric*(l->>'unit_price')::numeric*(1-(l->>'discount_percent')::numeric/100)*(1+(l->>'tax_percent')::numeric/100),scale)
 FROM jsonb_array_elements(p_document->'lines') WITH ORDINALITY a(l,n);
 r:=jsonb_build_object('order_id',o.id,'business_id',p_business,'site_id',p_site,'version',o.version,
  'status',o.status,'total',o.total,'stock_posted',false,'financial_posted',false);
 audit_id:=core10._append_canonical_audit_v1(t,p_business,'sales',o.id||':'||o.version,'sales.draft_saved',
  core10.actor_uid(),'sales:'||p_key,jsonb_build_object('receipt',r,'document',p_document));
 INSERT INTO core10.sales_order_commands_v1 VALUES(t,p_business,p_site,p_key,o.id,core10.actor_uid(),cmd,r,audit_id);
 RETURN r;
END $$;

CREATE FUNCTION core10.transition_sales_order_v1(p_business bigint,p_site bigint,p_order bigint,
 p_action text,p_expected bigint,p_approval bigint,p_key text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE t bigint; c jsonb; cmd jsonb; old core10.sales_order_commands_v1%ROWTYPE;
 o core10.sales_orders_v1%ROWTYPE; payload jsonb; stages integer; actual integer; r jsonb; audit_id bigint;
BEGIN
 t:=core10._sales_scope_v1(p_business,p_site);
 IF p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{8,100}$' OR p_expected IS NULL OR p_expected<1
    OR p_action IS NULL OR p_action NOT IN ('confirm','cancel') OR p_order IS NULL
 THEN RAISE EXCEPTION 'SALES_COMMAND_INVALID'; END IF;
 cmd:=jsonb_build_object('op',p_action,'site_id',p_site,'order_id',p_order,'expected',p_expected,'approval_id',p_approval);
 PERFORM pg_advisory_xact_lock(hashtextextended('sales-key:'||p_business||':'||p_key,0));
 SELECT * INTO o FROM core10.sales_orders_v1 WHERE id=p_order AND tenant_id=t AND business_id=p_business AND site_id=p_site FOR UPDATE;
 t:=core10._sales_scope_v1(p_business,p_site);
 c:=core10.control_check_v1(p_business,'sales.order_transition',p_site);
 SELECT * INTO old FROM core10.sales_order_commands_v1 WHERE business_id=p_business AND request_key=p_key;
 IF FOUND THEN
  IF old.actor_id<>core10.actor_uid() OR old.input IS DISTINCT FROM cmd THEN RAISE EXCEPTION 'SALES_REPLAY_CONFLICT'; END IF;
  RETURN old.receipt;
 END IF;
 IF o.id IS NULL THEN RAISE EXCEPTION 'SALES_ORDER_NOT_FOUND'; END IF;
 IF o.version<>p_expected THEN RAISE EXCEPTION 'SALES_STALE_VERSION'; END IF;
 IF o.status<>'draft' THEN RAISE EXCEPTION 'SALES_INVALID_TRANSITION'; END IF;
 -- Only uncommitted drafts can be cancelled. No fulfilment/stock reservation is
 -- claimed by confirmation; downstream posting and reversal remain disconnected.
 IF p_action='confirm' THEN
  IF core10._sales_validate_v1(p_business,p_site,o.document,
    core10.control_check_v1(p_business,'sales.order_draft',p_site)->'params') IS DISTINCT FROM o.total
  THEN RAISE EXCEPTION 'SALES_TOTAL_CHANGED'; END IF;
 END IF;
 stages:=(c->>'stages')::integer;
 payload:=jsonb_build_object('order_id',o.id,'site_id',p_site,'version',o.version,
  'document',o.document,'total',o.total,'action',p_action,'required_stages',stages);
 IF stages=0 AND p_approval IS NOT NULL THEN RAISE EXCEPTION 'SALES_APPROVAL_NOT_ALLOWED'; END IF;
 IF stages>0 THEN
  -- NP01 review RPC bindings are still pending on trunk. Do not let an old
  -- approved receipt bypass the current review switch at the domain boundary.
  PERFORM core10.control_check_v1(p_business,'gov002.review',p_site);
  IF p_approval IS NULL THEN RAISE EXCEPTION 'SALES_APPROVAL_REQUIRED'; END IF;
  PERFORM core10.verify_approval_binding_v1(p_approval,p_business,'sales',p_action,'sales-order:'||o.id,o.version,payload);
  SELECT COALESCE(cardinality(ar.stages),1) INTO actual FROM core10.approval_requests q
   LEFT JOIN core10.approval_routes_v1 ar ON ar.policy_id=q.policy_id_v1
   WHERE q.id=p_approval AND q.created_by=o.changed_by;
  IF actual IS DISTINCT FROM stages THEN RAISE EXCEPTION 'SALES_APPROVAL_STAGES'; END IF;
 END IF;
 UPDATE core10.sales_orders_v1 SET status=CASE p_action WHEN 'confirm' THEN 'confirmed' ELSE 'cancelled' END,
  version=version+1,changed_by=core10.actor_uid(),changed_at=clock_timestamp() WHERE id=o.id RETURNING * INTO o;
 r:=jsonb_build_object('order_id',o.id,'business_id',p_business,'site_id',p_site,'version',o.version,
  'status',o.status,'total',o.total,'stock_posted',false,'financial_posted',false);
 audit_id:=core10._append_canonical_audit_v1(t,p_business,'sales',o.id||':'||o.version,'sales.'||p_action,
  core10.actor_uid(),'sales:'||p_key,jsonb_build_object('receipt',r,'approval_id',p_approval,'source',payload));
 INSERT INTO core10.sales_order_commands_v1 VALUES(t,p_business,p_site,p_key,o.id,core10.actor_uid(),cmd,r,audit_id);
 RETURN r;
END $$;

CREATE FUNCTION core10.read_sales_orders_v1(p_business bigint,p_site bigint,p_order bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE t bigint; rows jsonb;
BEGIN
 t:=core10._sales_scope_v1(p_business,p_site);
 SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.id DESC),'[]') INTO rows FROM
  (SELECT id,site_id,customer_id,price_list_id,currency,status,version,total,document,changed_at
   FROM core10.sales_orders_v1 WHERE tenant_id=t AND business_id=p_business AND site_id=p_site
   AND (p_order IS NULL OR id=p_order) ORDER BY id DESC LIMIT 100) x;
 RETURN jsonb_build_object('business_id',p_business,'site_id',p_site,'items',rows,
  'stock_posted',false,'financial_posted',false);
END $$;
REVOKE ALL ON FUNCTION core10.save_sales_order_v1(bigint,bigint,bigint,bigint,jsonb,text),
 core10.transition_sales_order_v1(bigint,bigint,bigint,text,bigint,bigint,text),
 core10.read_sales_orders_v1(bigint,bigint,bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION core10.save_sales_order_v1(bigint,bigint,bigint,bigint,jsonb,text),
 core10.transition_sales_order_v1(bigint,bigint,bigint,text,bigint,bigint,text),
 core10.read_sales_orders_v1(bigint,bigint,bigint) TO authenticated;

-- Each lane registers its own features in its own migration per Control contract.
INSERT INTO core10.control_catalog_v1(feature_key,title_en,title_bn,pack,default_enabled,default_stages,max_stages,
 approval_domain,approval_action,params) VALUES
 ('sales.order_draft','Sales order drafts','বিক্রয় অর্ডারের খসড়া','NP03B',false,0,0,NULL,NULL,
 '{"max_lines":{"type":"int","min":1,"max":1000,"default":100},"max_quantity":{"type":"numeric","min":0.000001,"max":1000000000,"default":1000000},"max_discount_percent":{"type":"numeric","min":0,"max":100,"default":0},"max_order_total":{"type":"numeric","min":0,"max":1000000000000,"default":10000000},"money_scale":{"type":"int","min":0,"max":6,"default":2},"tax_enabled":{"type":"bool","default":false}}'),
 ('sales.order_transition','Confirm or cancel draft sales orders','বিক্রয় খসড়া নিশ্চিত বা বাতিল','NP03B',false,1,5,'sales','confirm','{}');
INSERT INTO core10.control_rpc_map_v1(rpc_name,status,feature_key,reason,lane,board_row,test_ref) VALUES
 ('save_sales_order_v1','enforced','sales.order_draft','Owner scope then Control before replay or any draft mutation','Codex','B-014','tests/np03b/sales-orders.sql'),
 ('transition_sales_order_v1','enforced','sales.order_transition','Owner scope then Control; configured approval source/stages checked before transition','Codex','B-014','tests/np03b/sales-orders.sql');
