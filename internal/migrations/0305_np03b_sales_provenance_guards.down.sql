DROP TRIGGER sales_confirmed_header_guard ON core10.sales_orders_v1;
DROP TRIGGER sales_confirmed_line_guard ON core10.sales_order_lines_v1;
DROP TRIGGER sales_confirmed_header_truncate_guard ON core10.sales_orders_v1;
DROP TRIGGER sales_confirmed_line_truncate_guard ON core10.sales_order_lines_v1;
DROP FUNCTION core10._sales_confirmed_header_guard_v1(),core10._sales_confirmed_line_guard_v1(),
 core10._sales_confirmed_truncate_guard_v1();
ALTER TABLE core10.sales_orders_v1 DROP CONSTRAINT sales_order_customer_master_fk,DROP CONSTRAINT sales_order_price_list_master_fk;
DROP INDEX core10.sales_order_customer_master_idx,core10.sales_order_price_list_master_idx;

CREATE OR REPLACE FUNCTION core10.transition_sales_order_v1(p_business bigint,p_site bigint,p_order bigint,
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

CREATE OR REPLACE FUNCTION core10.save_sales_invoice_draft_v1(p_business bigint,p_site bigint,p_invoice bigint,p_expected bigint,
 p_order bigint,p_order_version bigint,p_lines jsonb,p_memo text,p_key text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE t bigint; c jsonb; cmd jsonb; old core10.sales_invoice_commands_v1%ROWTYPE;
 o core10.sales_orders_v1%ROWTYPE; i core10.sales_invoice_drafts_v1%ROWTYPE;
 snapshot jsonb; v_selection jsonb; doc jsonb; amount numeric; scale integer; r jsonb; audit_id bigint; confirm_id bigint;
BEGIN
 t:=core10._sales_scope_v1(p_business,p_site);
 IF p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{8,100}$' OR p_expected IS NULL OR p_order IS NULL
 OR p_order_version IS NULL OR p_order_version<1 OR p_memo IS NULL
 OR (p_invoice IS NULL AND p_expected<>0) OR (p_invoice IS NOT NULL AND p_expected<1)
 THEN RAISE EXCEPTION 'SALES_INVOICE_COMMAND_INVALID'; END IF;
 cmd:=jsonb_build_object('op','save','site_id',p_site,'invoice_id',p_invoice,'expected',p_expected,
 'order_id',p_order,'order_version',p_order_version,'lines',p_lines,'memo',p_memo);
 -- Scope is part of the query BEFORE locks: a foreign ID never acquires its row lock.
 IF NOT EXISTS(SELECT FROM core10.sales_orders_v1 WHERE id=p_order AND tenant_id=t AND business_id=p_business AND site_id=p_site)
 THEN RAISE EXCEPTION 'SALES_INVOICE_ORDER_NOT_FOUND'; END IF;
 IF p_invoice IS NOT NULL THEN
  SELECT * INTO i FROM core10.sales_invoice_drafts_v1 WHERE id=p_invoice AND tenant_id=t AND business_id=p_business AND site_id=p_site;
  IF NOT FOUND THEN RAISE EXCEPTION 'SALES_INVOICE_NOT_FOUND'; END IF;
  IF i.source_order_id<>p_order OR i.source_order_version<>p_order_version THEN RAISE EXCEPTION 'SALES_INVOICE_SOURCE_IMMUTABLE'; END IF;
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('sales-invoice-key:'||p_business||':'||p_key,0));
 SELECT * INTO o FROM core10.sales_orders_v1 WHERE id=p_order AND tenant_id=t AND business_id=p_business AND site_id=p_site FOR UPDATE;
 IF p_invoice IS NOT NULL THEN
  SELECT * INTO i FROM core10.sales_invoice_drafts_v1 WHERE id=p_invoice AND tenant_id=t AND business_id=p_business AND site_id=p_site FOR UPDATE;
 END IF;
 t:=core10._sales_scope_v1(p_business,p_site);
 c:=core10.control_check_v1(p_business,'sales.invoice_draft',p_site);
 SELECT * INTO old FROM core10.sales_invoice_commands_v1 WHERE business_id=p_business AND request_key=p_key;
 IF FOUND THEN
  IF old.actor_id<>core10.actor_uid() OR old.input IS DISTINCT FROM cmd THEN RAISE EXCEPTION 'SALES_INVOICE_REPLAY_CONFLICT'; END IF;
  RETURN old.receipt;
 END IF;
 IF o.status<>'confirmed' THEN RAISE EXCEPTION 'SALES_INVOICE_ORDER_NOT_CONFIRMED'; END IF;
 IF o.version<>p_order_version THEN RAISE EXCEPTION 'SALES_INVOICE_SOURCE_STALE'; END IF;
 IF p_invoice IS NOT NULL THEN
  IF i.source_order_id<>p_order OR i.source_order_version<>p_order_version THEN RAISE EXCEPTION 'SALES_INVOICE_SOURCE_IMMUTABLE'; END IF;
  IF i.version<>p_expected THEN RAISE EXCEPTION 'SALES_INVOICE_STALE_VERSION'; END IF;
  snapshot:=i.source_snapshot;scale:=i.money_scale;
 ELSE
  IF EXISTS(SELECT FROM core10.sales_invoice_drafts_v1 WHERE source_order_id=p_order) THEN RAISE EXCEPTION 'SALES_INVOICE_DUPLICATE_ORDER'; END IF;
  SELECT audit_event_id INTO confirm_id FROM core10.sales_order_commands_v1
   WHERE order_id=o.id AND receipt->>'status'='confirmed' AND (receipt->>'version')::bigint=o.version;
  IF confirm_id IS NULL THEN RAISE EXCEPTION 'SALES_INVOICE_SOURCE_AUDIT_MISSING'; END IF;
  scale:=(c->'params'->>'money_scale')::integer;
  snapshot:=jsonb_build_object('order_id',o.id,'order_version',o.version,'business_id',p_business,'site_id',p_site,
   'document',o.document,'total',o.total,'money_scale',scale,'confirmation_audit_event_id',confirm_id,
   'line_totals',(SELECT jsonb_agg(line_total ORDER BY line_no) FROM core10.sales_order_lines_v1 WHERE order_id=o.id));
 END IF;
 IF scale<>(c->'params'->>'money_scale')::integer THEN RAISE EXCEPTION 'SALES_INVOICE_ROUNDING_CHANGED'; END IF;
 -- A different rounding policy must never silently change a confirmed source.
 IF snapshot->'document' IS DISTINCT FROM o.document OR (snapshot->>'total')::numeric<>o.total
 OR (SELECT sum((v::text)::numeric) FROM jsonb_array_elements(snapshot->'line_totals') v) IS DISTINCT FROM o.total
 OR EXISTS(SELECT FROM jsonb_array_elements(o.document->'lines') WITH ORDINALITY a(l,n)
   WHERE round((l->>'quantity')::numeric*(l->>'unit_price')::numeric*(1-(l->>'discount_percent')::numeric/100)*(1+(l->>'tax_percent')::numeric/100),scale)
    IS DISTINCT FROM (snapshot->'line_totals'->>(n::integer-1))::numeric)
 THEN RAISE EXCEPTION 'SALES_INVOICE_SOURCE_ROUNDING'; END IF;
 IF length(p_memo)>(c->'params'->>'max_memo_length')::integer THEN RAISE EXCEPTION 'SALES_INVOICE_MEMO_LIMIT'; END IF;
 IF p_lines IS NULL AND p_invoice IS NULL THEN
  SELECT jsonb_agg(jsonb_build_object('order_line_no',n,'quantity',l->'quantity') ORDER BY n) INTO v_selection
   FROM jsonb_array_elements(o.document->'lines') WITH ORDINALITY a(l,n);
 ELSE v_selection:=p_lines; END IF;
 doc:=core10._sales_invoice_document_v1(snapshot,v_selection,c->'params');
 amount:=core10._sales_validate_v1(p_business,p_site,doc,c->'params');
 IF p_invoice IS NULL THEN
  INSERT INTO core10.sales_invoice_drafts_v1(tenant_id,business_id,site_id,source_order_id,source_order_version,source_snapshot,source_sha256,
  customer_id,price_list_id,currency,money_scale,selection,document,total,memo,created_by,changed_by)
  VALUES(t,p_business,p_site,p_order,p_order_version,snapshot,encode(sha256(convert_to(snapshot::text,'UTF8')),'hex'),
   o.customer_id,o.price_list_id,o.currency,scale,v_selection,doc,amount,p_memo,core10.actor_uid(),core10.actor_uid()) RETURNING * INTO i;
 ELSE
  UPDATE core10.sales_invoice_drafts_v1 SET selection=v_selection,document=doc,total=amount,memo=p_memo,version=version+1,
   validated_at=NULL,validated_by=NULL,changed_by=core10.actor_uid(),changed_at=clock_timestamp() WHERE id=i.id RETURNING * INTO i;
  DELETE FROM core10.sales_invoice_draft_lines_v1 WHERE invoice_id=i.id;
 END IF;
 INSERT INTO core10.sales_invoice_draft_lines_v1
 SELECT i.id,t,p_business,p_site,p_order,n,(x->>'order_line_no')::integer,(l->>'item_id')::bigint,(l->>'variant_id')::bigint,
  (l->>'uom_id')::bigint,(l->>'quantity')::numeric,(l->>'unit_price')::numeric,(l->>'discount_percent')::numeric,(l->>'tax_percent')::numeric,
  round((l->>'quantity')::numeric*(l->>'unit_price')::numeric*(1-(l->>'discount_percent')::numeric/100),scale)
 FROM jsonb_array_elements(doc->'lines') WITH ORDINALITY a(l,n)
 JOIN (SELECT value x,row_number() OVER(ORDER BY (value->>'order_line_no')::integer) z FROM jsonb_array_elements(v_selection)) b ON b.z=n;
 r:=core10._sales_invoice_receipt_v1(i);
 audit_id:=core10._append_canonical_audit_v1(t,p_business,'sales_invoice',i.id||':'||i.version,'sales.invoice_draft_saved',
 core10.actor_uid(),'sales-invoice:'||p_key,jsonb_build_object('receipt',r,'document',doc,'memo',p_memo,'selection',v_selection));
 INSERT INTO core10.sales_invoice_commands_v1 VALUES(t,p_business,p_site,p_key,i.id,p_order,core10.actor_uid(),cmd,r,audit_id);
 RETURN r;
END $$;

CREATE OR REPLACE FUNCTION core10.validate_sales_invoice_draft_v1(p_business bigint,p_site bigint,p_invoice bigint,
 p_expected bigint,p_approval bigint,p_key text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE t bigint; c jsonb; draft_control jsonb; cmd jsonb; payload jsonb; r jsonb; amount numeric;
 i core10.sales_invoice_drafts_v1%ROWTYPE; o core10.sales_orders_v1%ROWTYPE;
 old core10.sales_invoice_commands_v1%ROWTYPE; stages integer; actual integer; audit_id bigint;
BEGIN
 t:=core10._sales_scope_v1(p_business,p_site);
 IF p_invoice IS NULL OR p_expected IS NULL OR p_expected<1 OR p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{8,100}$'
 THEN RAISE EXCEPTION 'SALES_INVOICE_COMMAND_INVALID'; END IF;
 SELECT * INTO i FROM core10.sales_invoice_drafts_v1 WHERE id=p_invoice AND tenant_id=t AND business_id=p_business AND site_id=p_site;
 IF NOT FOUND THEN RAISE EXCEPTION 'SALES_INVOICE_NOT_FOUND'; END IF;
 cmd:=jsonb_build_object('op','validate','site_id',p_site,'invoice_id',p_invoice,'expected',p_expected,'approval_id',p_approval);
 PERFORM pg_advisory_xact_lock(hashtextextended('sales-invoice-key:'||p_business||':'||p_key,0));
 SELECT * INTO o FROM core10.sales_orders_v1 WHERE id=i.source_order_id AND tenant_id=t AND business_id=p_business AND site_id=p_site FOR UPDATE;
 SELECT * INTO i FROM core10.sales_invoice_drafts_v1 WHERE id=p_invoice AND tenant_id=t AND business_id=p_business AND site_id=p_site FOR UPDATE;
 t:=core10._sales_scope_v1(p_business,p_site);
 c:=core10.control_check_v1(p_business,'sales.invoice_validate',p_site);
 draft_control:=core10.control_check_v1(p_business,'sales.invoice_draft',p_site);
 SELECT * INTO old FROM core10.sales_invoice_commands_v1 WHERE business_id=p_business AND request_key=p_key;
 IF FOUND THEN
  IF old.actor_id<>core10.actor_uid() OR old.input IS DISTINCT FROM cmd THEN RAISE EXCEPTION 'SALES_INVOICE_REPLAY_CONFLICT'; END IF;
  RETURN old.receipt;
 END IF;
 IF i.version<>p_expected THEN RAISE EXCEPTION 'SALES_INVOICE_STALE_VERSION'; END IF;
 IF o.status<>'confirmed' OR o.version<>i.source_order_version OR o.document IS DISTINCT FROM i.source_snapshot->'document'
 OR o.total IS DISTINCT FROM (i.source_snapshot->>'total')::numeric
 THEN RAISE EXCEPTION 'SALES_INVOICE_SOURCE_STALE'; END IF;
 IF i.money_scale<>(draft_control->'params'->>'money_scale')::integer THEN RAISE EXCEPTION 'SALES_INVOICE_ROUNDING_CHANGED'; END IF;
 IF length(i.memo)>(draft_control->'params'->>'max_memo_length')::integer THEN RAISE EXCEPTION 'SALES_INVOICE_MEMO_LIMIT'; END IF;
 IF core10._sales_invoice_document_v1(i.source_snapshot,i.selection,draft_control->'params') IS DISTINCT FROM i.document
 THEN RAISE EXCEPTION 'SALES_INVOICE_DOCUMENT_CHANGED'; END IF;
 amount:=core10._sales_validate_v1(p_business,p_site,i.document,draft_control->'params');
 IF amount IS DISTINCT FROM i.total THEN RAISE EXCEPTION 'SALES_INVOICE_TOTAL_CHANGED'; END IF;
 stages:=(c->>'stages')::integer;
 payload:=core10._sales_invoice_approval_payload_v1(i,stages);
 IF stages>0 THEN
  PERFORM core10.control_check_v1(p_business,'gov002.review',p_site);
  IF p_approval IS NULL THEN RAISE EXCEPTION 'SALES_INVOICE_APPROVAL_REQUIRED'; END IF;
  PERFORM core10.verify_approval_binding_v1(p_approval,p_business,'sales','invoice_validate','sales-invoice-draft:'||i.id,i.version,payload);
  SELECT coalesce(cardinality(ar.stages),1) INTO actual FROM core10.approval_requests q
   LEFT JOIN core10.approval_routes_v1 ar ON ar.policy_id=q.policy_id_v1 WHERE q.id=p_approval AND q.created_by=i.changed_by;
  IF actual IS DISTINCT FROM stages THEN RAISE EXCEPTION 'SALES_INVOICE_APPROVAL_STAGES'; END IF;
 END IF;
 UPDATE core10.sales_invoice_drafts_v1 SET version=version+1,validated_at=clock_timestamp(),validated_by=core10.actor_uid(),
 changed_at=clock_timestamp() WHERE id=i.id RETURNING * INTO i;
 -- changed_by remains the last editor: a validation receipt does not become its maker.
 r:=core10._sales_invoice_receipt_v1(i);
 audit_id:=core10._append_canonical_audit_v1(t,p_business,'sales_invoice',i.id||':'||i.version,'sales.invoice_draft_validated',
 core10.actor_uid(),'sales-invoice:'||p_key,jsonb_build_object('receipt',r,'approval_id',p_approval,'approval_payload',payload));
 INSERT INTO core10.sales_invoice_commands_v1 VALUES(t,p_business,p_site,p_key,i.id,i.source_order_id,core10.actor_uid(),cmd,r,audit_id);
 RETURN r;
END $$;

DROP FUNCTION core10._sales_confirmation_event_v1(core10.sales_orders_v1);
