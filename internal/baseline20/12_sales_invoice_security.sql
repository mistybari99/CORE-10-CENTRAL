-- CORE10 baseline20 v1; ordered, lossless consolidation. Fresh empty schema only.
-- CORE10 BASELINE SOURCE 0304_np03b_draft_invoices.up.sql SHA256 84a67e820b3503e3199feab2662978fb59c919c4947f85a48aae3a33b94036f9
-- B-014: one non-issued draft invoice per confirmed canonical Sales order.
-- No invoice number, receivable, stock reservation, journal or settlement call.
CREATE TABLE core10.sales_invoice_drafts_v1 (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL, business_id bigint NOT NULL, site_id bigint NOT NULL,
 source_order_id bigint NOT NULL UNIQUE,
 source_order_version bigint NOT NULL CHECK(source_order_version>0),
 source_snapshot jsonb NOT NULL CHECK(jsonb_typeof(source_snapshot)='object'),
 source_sha256 text NOT NULL CHECK(source_sha256 ~ '^[0-9a-f]{64}$'),
 customer_id bigint NOT NULL, price_list_id bigint NOT NULL, currency text NOT NULL CHECK(currency ~ '^[A-Z]{3}$'),
 money_scale integer NOT NULL CHECK(money_scale BETWEEN 0 AND 6),
 selection jsonb NOT NULL CHECK(jsonb_typeof(selection)='array'),
 document jsonb NOT NULL CHECK(jsonb_typeof(document)='object'),
 total numeric NOT NULL CHECK(total>=0 AND total NOT IN ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric)),
 memo text NOT NULL DEFAULT '',
 status text NOT NULL DEFAULT 'draft' CHECK(status='draft'),
 version bigint NOT NULL DEFAULT 1 CHECK(version>0),
 validated_at timestamptz, validated_by uuid,
 created_by uuid NOT NULL, changed_by uuid NOT NULL,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(), changed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 CHECK((validated_at IS NULL)=(validated_by IS NULL)),
 CHECK(source_sha256=encode(sha256(convert_to(source_snapshot::text,'UTF8')),'hex')),
 UNIQUE(id,tenant_id,business_id,site_id,source_order_id),
 FOREIGN KEY(source_order_id,tenant_id,business_id,site_id) REFERENCES core10.sales_orders_v1(id,tenant_id,business_id,site_id)
);
CREATE TABLE core10.sales_invoice_draft_lines_v1 (
 invoice_id bigint NOT NULL, tenant_id bigint NOT NULL, business_id bigint NOT NULL, site_id bigint NOT NULL,
 source_order_id bigint NOT NULL, line_no integer NOT NULL CHECK(line_no>0), source_line_no integer NOT NULL,
 item_id bigint NOT NULL, variant_id bigint, uom_id bigint NOT NULL,
 quantity numeric NOT NULL CHECK(quantity>0 AND quantity NOT IN ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric)),
 unit_price numeric NOT NULL CHECK(unit_price>=0 AND unit_price NOT IN ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric)),
 discount_percent numeric NOT NULL CHECK(discount_percent BETWEEN 0 AND 100), tax_percent numeric NOT NULL CHECK(tax_percent=0),
 line_total numeric NOT NULL CHECK(line_total>=0 AND line_total NOT IN ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric)),
 PRIMARY KEY(invoice_id,line_no), UNIQUE(invoice_id,source_line_no),
 FOREIGN KEY(invoice_id,tenant_id,business_id,site_id,source_order_id)
  REFERENCES core10.sales_invoice_drafts_v1(id,tenant_id,business_id,site_id,source_order_id),
 FOREIGN KEY(source_order_id,source_line_no) REFERENCES core10.sales_order_lines_v1(order_id,line_no)
);
CREATE TABLE core10.sales_invoice_commands_v1 (
 tenant_id bigint NOT NULL, business_id bigint NOT NULL, site_id bigint NOT NULL,
 request_key text NOT NULL CHECK(request_key ~ '^[A-Za-z0-9_-]{8,100}$'),
 invoice_id bigint NOT NULL, source_order_id bigint NOT NULL, actor_id uuid NOT NULL,
 input jsonb NOT NULL, receipt jsonb NOT NULL,
 audit_event_id bigint NOT NULL REFERENCES core10.canonical_audit_events_v1(id),
 PRIMARY KEY(business_id,request_key),
 FOREIGN KEY(invoice_id,tenant_id,business_id,site_id,source_order_id)
  REFERENCES core10.sales_invoice_drafts_v1(id,tenant_id,business_id,site_id,source_order_id)
);
ALTER TABLE core10.sales_invoice_drafts_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE core10.sales_invoice_draft_lines_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE core10.sales_invoice_commands_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON core10.sales_invoice_drafts_v1,core10.sales_invoice_draft_lines_v1,core10.sales_invoice_commands_v1 FROM PUBLIC,authenticated;
REVOKE ALL ON SEQUENCE core10.sales_invoice_drafts_v1_id_seq FROM PUBLIC,authenticated;

CREATE FUNCTION core10._sales_invoice_source_immutable_v1() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog,core10 AS $$ BEGIN
 IF ROW(NEW.id,NEW.tenant_id,NEW.business_id,NEW.site_id,NEW.source_order_id,NEW.source_order_version,
 NEW.source_snapshot,NEW.source_sha256,NEW.customer_id,NEW.price_list_id,NEW.currency,NEW.money_scale,NEW.created_by,NEW.created_at)
 IS DISTINCT FROM ROW(OLD.id,OLD.tenant_id,OLD.business_id,OLD.site_id,OLD.source_order_id,OLD.source_order_version,
 OLD.source_snapshot,OLD.source_sha256,OLD.customer_id,OLD.price_list_id,OLD.currency,OLD.money_scale,OLD.created_by,OLD.created_at)
 THEN RAISE EXCEPTION 'SALES_INVOICE_SOURCE_IMMUTABLE'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER sales_invoice_source_immutable_v1 BEFORE UPDATE ON core10.sales_invoice_drafts_v1
 FOR EACH ROW EXECUTE FUNCTION core10._sales_invoice_source_immutable_v1();

CREATE FUNCTION core10._sales_invoice_receipt_v1(i core10.sales_invoice_drafts_v1) RETURNS jsonb
LANGUAGE sql STABLE SET search_path=pg_catalog,core10 AS $$ SELECT jsonb_build_object(
 'invoice_id',i.id,'business_id',i.business_id,'site_id',i.site_id,'source_order_id',i.source_order_id,
 'source_order_version',i.source_order_version,'version',i.version,'status',i.status,'validated',i.validated_at IS NOT NULL,
 'total',i.total,'currency',i.currency,'source_sha256',i.source_sha256,
 'issued',false,'stock_posted',false,'financial_posted',false,
 'connections',jsonb_build_object('issuance','NOT_CONNECTED','stock','NOT_CONNECTED','money','NOT_CONNECTED','tax','ZERO_ONLY')) $$;

-- JSON-only projection: a source line can appear once, quantities never exceed
-- its confirmed cap, and caller-supplied identities/prices/taxes are not accepted.
CREATE FUNCTION core10._sales_invoice_document_v1(s jsonb,selection jsonb,params jsonb) RETURNS jsonb
LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog,core10 AS $$
DECLARE x jsonb; l jsonb; n integer; q numeric; seen integer[]:='{}'; lines jsonb:='[]';
BEGIN
 IF selection IS NULL OR jsonb_typeof(selection) IS DISTINCT FROM 'array' OR jsonb_array_length(selection)=0
 OR jsonb_array_length(selection)>jsonb_array_length(s->'document'->'lines') THEN RAISE EXCEPTION 'SALES_INVOICE_LINES_INVALID'; END IF;
 FOR x IN SELECT value FROM jsonb_array_elements(selection) ORDER BY CASE WHEN value->>'order_line_no' ~ '^[1-9][0-9]{0,5}$' THEN (value->>'order_line_no')::integer ELSE 0 END LOOP
  IF jsonb_typeof(x) IS DISTINCT FROM 'object' OR x-ARRAY['order_line_no','quantity']<>'{}'::jsonb
   OR NOT(x ?& ARRAY['order_line_no','quantity']) OR jsonb_typeof(x->'order_line_no') IS DISTINCT FROM 'number'
   OR x->>'order_line_no' !~ '^[1-9][0-9]{0,5}$' OR jsonb_typeof(x->'quantity') IS DISTINCT FROM 'number'
   OR length(x->>'quantity')>30 THEN RAISE EXCEPTION 'SALES_INVOICE_LINES_INVALID'; END IF;
  n:=(x->>'order_line_no')::integer;q:=(x->>'quantity')::numeric;
  l:=s->'document'->'lines'->(n-1);
  IF l IS NULL OR n=ANY(seen) OR q<=0 OR q>(l->>'quantity')::numeric
  THEN RAISE EXCEPTION 'SALES_INVOICE_QUANTITY'; END IF;
  seen:=array_append(seen,n);
  IF NOT(params->>'allow_partial_quantities')::boolean AND q<>(l->>'quantity')::numeric
  THEN RAISE EXCEPTION 'SALES_INVOICE_PARTIAL_DISABLED'; END IF;
  lines:=lines||jsonb_build_array(jsonb_set(l,'{quantity}',to_jsonb(q)));
 END LOOP;
 IF NOT(params->>'allow_partial_quantities')::boolean AND cardinality(seen)<>jsonb_array_length(s->'document'->'lines')
 THEN RAISE EXCEPTION 'SALES_INVOICE_PARTIAL_DISABLED'; END IF;
 RETURN jsonb_set(s->'document','{lines}',lines);
END $$;

CREATE FUNCTION core10.save_sales_invoice_draft_v1(p_business bigint,p_site bigint,p_invoice bigint,p_expected bigint,
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

CREATE FUNCTION core10._sales_invoice_approval_payload_v1(i core10.sales_invoice_drafts_v1,stages integer) RETURNS jsonb
LANGUAGE sql IMMUTABLE SET search_path=pg_catalog,core10 AS $$ SELECT jsonb_build_object(
 'invoice_id',i.id,'site_id',i.site_id,'version',i.version,'source_order_id',i.source_order_id,
 'source_order_version',i.source_order_version,'source_sha256',i.source_sha256,'document',i.document,
 'memo',i.memo,'total',i.total,'money_scale',i.money_scale,'required_stages',stages,'action','invoice_validate') $$;

CREATE FUNCTION core10.validate_sales_invoice_draft_v1(p_business bigint,p_site bigint,p_invoice bigint,
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

CREATE FUNCTION core10.read_sales_invoice_drafts_v1(p_business bigint,p_site bigint,p_invoice bigint DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $$
DECLARE t bigint; rows jsonb; binding jsonb;
BEGIN
 t:=core10._sales_scope_v1(p_business,p_site);
 binding:=core10.control_approval_binding_v1(p_business,'sales.invoice_validate',p_site);
 SELECT coalesce(jsonb_agg(x),'[]') INTO rows FROM (
 SELECT core10._sales_invoice_receipt_v1(i)||jsonb_build_object('customer_id',i.customer_id,'price_list_id',i.price_list_id,
 'document',i.document,'selection',i.selection,'memo',i.memo,'money_scale',i.money_scale,'source_snapshot',i.source_snapshot,
 'changed_by',i.changed_by,'validated_by',i.validated_by,'validated_at',i.validated_at,
 'approval_payload',core10._sales_invoice_approval_payload_v1(i,(binding->>'stages')::integer),
 'lines',(SELECT coalesce(jsonb_agg(to_jsonb(l) ORDER BY l.line_no),'[]') FROM core10.sales_invoice_draft_lines_v1 l WHERE l.invoice_id=i.id),
 'audit',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',a.id,'action',a.action,'actor_id',a.actor_id,
 'event_at',a.event_at,'stream_seq',a.stream_seq,'payload',a.payload) ORDER BY a.stream_seq),'[]')
 FROM core10.sales_invoice_commands_v1 k JOIN core10.canonical_audit_events_v1 a ON a.id=k.audit_event_id
 WHERE k.invoice_id=i.id AND a.tenant_id=t AND a.business_id=p_business AND a.source_domain='sales_invoice')) x
 FROM core10.sales_invoice_drafts_v1 i WHERE tenant_id=t AND business_id=p_business AND site_id=p_site
 AND(p_invoice IS NULL OR i.id=p_invoice) ORDER BY i.id DESC LIMIT 100) q;
 RETURN jsonb_build_object('invoices',rows,'validation_control',binding,
 'issued',false,'stock_posted',false,'financial_posted',false,
 'connections',jsonb_build_object('issuance','NOT_CONNECTED','stock','NOT_CONNECTED','money','NOT_CONNECTED','tax','ZERO_ONLY'));
END $$;

REVOKE ALL ON FUNCTION core10._sales_invoice_source_immutable_v1(),core10._sales_invoice_receipt_v1(core10.sales_invoice_drafts_v1),
 core10._sales_invoice_document_v1(jsonb,jsonb,jsonb),core10._sales_invoice_approval_payload_v1(core10.sales_invoice_drafts_v1,integer) FROM PUBLIC,authenticated;
REVOKE ALL ON FUNCTION core10.save_sales_invoice_draft_v1(bigint,bigint,bigint,bigint,bigint,bigint,jsonb,text,text),
 core10.validate_sales_invoice_draft_v1(bigint,bigint,bigint,bigint,bigint,text),core10.read_sales_invoice_drafts_v1(bigint,bigint,bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION core10.save_sales_invoice_draft_v1(bigint,bigint,bigint,bigint,bigint,bigint,jsonb,text,text),
 core10.validate_sales_invoice_draft_v1(bigint,bigint,bigint,bigint,bigint,text),core10.read_sales_invoice_drafts_v1(bigint,bigint,bigint) TO authenticated;

INSERT INTO core10.control_catalog_v1(feature_key,title_en,title_bn,pack,default_enabled,default_stages,max_stages,
 approval_domain,approval_action,params)
 SELECT 'sales.invoice_draft','Order-linked draft invoice','অর্ডার-সংযুক্ত ইনভয়েস খসড়া','NP03B',false,0,0,NULL,NULL,
 params||'{"allow_partial_quantities":{"type":"bool","default":false},"max_memo_length":{"type":"int","min":0,"max":4000,"default":500}}'::jsonb
 FROM core10.control_catalog_v1 WHERE feature_key='sales.order_draft';
INSERT INTO core10.control_catalog_v1(feature_key,title_en,title_bn,pack,default_enabled,default_stages,max_stages,
 approval_domain,approval_action,params) VALUES
 ('sales.invoice_validate','Validate draft invoice (not issue)','ইনভয়েস খসড়া যাচাই (ইস্যু নয়)','NP03B',false,1,5,'sales','invoice_validate','{}');
INSERT INTO core10.control_rpc_map_v1(rpc_name,status,feature_key,reason,lane,board_row,test_ref) VALUES
 ('save_sales_invoice_draft_v1','enforced','sales.invoice_draft','Scoped confirmed source; Auth and actual Control after waits before replay or mutation','Codex','B-014','tests/np03b/invoice-drafts.sql'),
 ('validate_sales_invoice_draft_v1','enforced','sales.invoice_validate','Auth and Control after locks; current Master and exact canonical approval binding; never issues','Codex','B-014','tests/np03b/invoice-drafts.sql');
INSERT INTO core10.schema_migrations(version,name,checksum) VALUES(304,'0304_np03b_draft_invoices','84a67e820b3503e3199feab2662978fb59c919c4947f85a48aae3a33b94036f9');

-- CORE10 BASELINE SOURCE 0305_np03b_p1_security.up.sql SHA256 e6203101096b833fd860cb1685a82bdf6d4647e9e12f131ca8650bb663425c69
-- CORE10 NP03B 0305: freeze confirmed canonical Sales source and bind Audit.
-- Forward-only correction: no edits to existing 0300–0304 applied bytes.
-- Use only in a correctly ordered migration plan; no hosted apply.
DO $dep$ BEGIN
 IF to_regclass('core10.sales_orders_v1') IS NULL
 OR to_regclass('core10.sales_invoice_drafts_v1') IS NULL
 OR to_regclass('core10.master_parties_v1') IS NULL
 THEN RAISE EXCEPTION 'SALES_P1_SECURITY_DEPENDENCY_NOT_CONNECTED'; END IF;
END $dep$;

-- Never rewrite a confirmed or cancelled order header. The only permitted
-- existing operational transition is draft->confirmed/cancelled with its
-- original payload, exact version increment and scoped caller identity.
CREATE FUNCTION core10._sales_order_header_guard_0305()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,core10 AS $body$
BEGIN
 IF TG_OP='TRUNCATE' THEN RAISE EXCEPTION 'SALES_SOURCE_IMMUTABLE'; END IF;
 IF TG_OP='INSERT' THEN
  IF NEW.status<>'draft' OR NEW.version<>1 THEN
   RAISE EXCEPTION 'SALES_SOURCE_IMMUTABLE'; END IF;
  RETURN NEW;
 END IF;
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'SALES_SOURCE_IMMUTABLE'; END IF;
 IF OLD.status<>'draft' THEN RAISE EXCEPTION 'SALES_SOURCE_IMMUTABLE'; END IF;
 IF NEW.status NOT IN('draft','confirmed','cancelled')
 OR NEW.version<>OLD.version+1 OR NEW.changed_by IS DISTINCT FROM core10.actor_uid()
 OR NEW.id IS DISTINCT FROM OLD.id
 OR NEW.tenant_id IS DISTINCT FROM OLD.tenant_id
 OR NEW.business_id IS DISTINCT FROM OLD.business_id
 OR NEW.site_id IS DISTINCT FROM OLD.site_id
 OR NEW.created_by IS DISTINCT FROM OLD.created_by
 OR NEW.created_at IS DISTINCT FROM OLD.created_at
 THEN RAISE EXCEPTION 'SALES_SOURCE_IMMUTABLE'; END IF;
 IF NEW.status IN('confirmed','cancelled') AND
   ROW(NEW.customer_id,NEW.price_list_id,NEW.currency,NEW.document,NEW.total)
   IS DISTINCT FROM
   ROW(OLD.customer_id,OLD.price_list_id,OLD.currency,OLD.document,OLD.total)
 THEN RAISE EXCEPTION 'SALES_SOURCE_IMMUTABLE'; END IF;
 RETURN NEW;
END $body$;
CREATE TRIGGER sales_order_header_secure_0305
 BEFORE INSERT OR UPDATE OR DELETE ON core10.sales_orders_v1
 FOR EACH ROW EXECUTE FUNCTION core10._sales_order_header_guard_0305();
CREATE TRIGGER sales_order_header_notruncate_0305
 BEFORE TRUNCATE ON core10.sales_orders_v1
 FOR EACH STATEMENT EXECUTE FUNCTION core10._sales_order_header_guard_0305();

-- Source lines may be modified only when the header is still a draft.
-- Lock the header so confirmation, tamper and invoice-save all serialize.
CREATE FUNCTION core10._sales_order_lines_guard_0305()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,core10 AS $body$
DECLARE old_status text;v_order bigint;
BEGIN
 IF TG_OP='TRUNCATE' THEN RAISE EXCEPTION 'SALES_SOURCE_IMMUTABLE'; END IF;
 v_order:=CASE WHEN TG_OP='DELETE' THEN OLD.order_id ELSE NEW.order_id END;
 SELECT status INTO old_status FROM core10.sales_orders_v1
 WHERE id=v_order FOR SHARE;
 IF old_status IS DISTINCT FROM 'draft'
 THEN RAISE EXCEPTION 'SALES_SOURCE_IMMUTABLE'; END IF;
 IF TG_OP='UPDATE' AND
  (NEW.order_id<>OLD.order_id OR NEW.tenant_id<>OLD.tenant_id
   OR NEW.business_id<>OLD.business_id OR NEW.site_id<>OLD.site_id)
 THEN RAISE EXCEPTION 'SALES_SOURCE_IMMUTABLE'; END IF;
 RETURN CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
END $body$;
CREATE TRIGGER sales_order_lines_secure_0305
 BEFORE INSERT OR UPDATE OR DELETE ON core10.sales_order_lines_v1
 FOR EACH ROW EXECUTE FUNCTION core10._sales_order_lines_guard_0305();
CREATE TRIGGER sales_order_lines_notruncate_0305
 BEFORE TRUNCATE ON core10.sales_order_lines_v1
 FOR EACH STATEMENT EXECUTE FUNCTION core10._sales_order_lines_guard_0305();

-- Canonical command/evidence links must never be moved to a different event
-- (even by privileged ordinary DML), nor deleted or truncated.
CREATE FUNCTION core10._sales_command_frozen_0305()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,core10 AS $body$
BEGIN
 RAISE EXCEPTION 'SALES_AUDIT_IMMUTABLE';
END $body$;
CREATE TRIGGER sales_commands_frozen_0305
 BEFORE UPDATE OR DELETE ON core10.sales_order_commands_v1
 FOR EACH ROW EXECUTE FUNCTION core10._sales_command_frozen_0305();
CREATE TRIGGER sales_commands_notruncate_0305
 BEFORE TRUNCATE ON core10.sales_order_commands_v1
 FOR EACH STATEMENT EXECUTE FUNCTION core10._sales_command_frozen_0305();
CREATE TRIGGER sales_invoice_commands_frozen_0305
 BEFORE UPDATE OR DELETE ON core10.sales_invoice_commands_v1
 FOR EACH ROW EXECUTE FUNCTION core10._sales_command_frozen_0305();
CREATE TRIGGER sales_invoice_commands_notruncate_0305
 BEFORE TRUNCATE ON core10.sales_invoice_commands_v1
 FOR EACH STATEMENT EXECUTE FUNCTION core10._sales_command_frozen_0305();

-- Zero-stage cannot carry an arbitrary approval ID, in either server RPC.
-- Under positive stages, the original RPC performs binding verification.
-- This is the final insert-time fail-closed fence for privileged command DML.
CREATE FUNCTION core10._sales_command_approval_guard_0305()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,core10 AS $body$
DECLARE c jsonb;feature text;
BEGIN
 IF TG_TABLE_NAME='sales_order_commands_v1' THEN
  IF NEW.input->>'op' NOT IN('confirm','cancel') THEN RETURN NEW; END IF;
  feature:='sales.order_transition';
 ELSE
  IF NEW.input->>'op'<>'validate' THEN RETURN NEW; END IF;
  feature:='sales.invoice_validate';
 END IF;
 c:=core10.control_check_v1(NEW.business_id,feature,NEW.site_id);
 IF (c->>'stages')::integer=0 AND NEW.input->>'approval_id' IS NOT NULL
 THEN RAISE EXCEPTION 'SALES_APPROVAL_UNVERIFIED_ZERO_STAGE'; END IF;
 RETURN NEW;
END $body$;
CREATE TRIGGER sales_commands_approval_guard_0305
 BEFORE INSERT ON core10.sales_order_commands_v1
 FOR EACH ROW EXECUTE FUNCTION core10._sales_command_approval_guard_0305();
CREATE TRIGGER sales_invoice_commands_approval_guard_0305
 BEFORE INSERT ON core10.sales_invoice_commands_v1
 FOR EACH ROW EXECUTE FUNCTION core10._sales_command_approval_guard_0305();

-- A source is confirmed only with one real canonical Audit receipt:
-- original snapshot/version, transitioned source, receipt status/version,
-- command actor, and command association MUST all match this same order.
CREATE FUNCTION core10._sales_confirmed_audit_guard_0305()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,core10 AS $body$
DECLARE o core10.sales_orders_v1%ROWTYPE;
BEGIN
 IF TG_OP='DELETE' THEN RETURN OLD; END IF;
 SELECT * INTO o FROM core10.sales_orders_v1 WHERE id=NEW.id;
 IF NOT FOUND OR o.status<>'confirmed' THEN RETURN NEW; END IF;
 IF NOT EXISTS (
  SELECT 1 FROM core10.sales_order_commands_v1 c
  JOIN core10.canonical_audit_events_v1 a ON a.id=c.audit_event_id
  WHERE c.order_id=o.id AND c.tenant_id=o.tenant_id
   AND c.business_id=o.business_id AND c.site_id=o.site_id
   AND c.actor_id=a.actor_id
   AND c.input->>'op'='confirm'
   AND (c.input->>'expected')::bigint=o.version-1
   AND c.receipt->>'status'='confirmed'
   AND (c.receipt->>'order_id')::bigint=o.id
   AND (c.receipt->>'version')::bigint=o.version
   AND (c.receipt->>'total')::numeric=o.total
   AND a.tenant_id=o.tenant_id AND a.business_id=o.business_id
   AND a.source_domain='sales' AND a.action='sales.confirm'
   AND a.source_ref=o.id::text||':'||o.version::text
   AND a.request_key='sales:'||c.request_key
   AND a.payload->'receipt'=c.receipt
   AND a.payload->'source'->>'action'='confirm'
   AND (a.payload->'source'->>'order_id')::bigint=o.id
   AND (a.payload->'source'->>'version')::bigint=o.version-1
   AND a.payload->'source'->'document'=o.document
   AND (a.payload->'source'->>'total')::numeric=o.total
 ) THEN RAISE EXCEPTION 'SALES_SOURCE_AUDIT_MISMATCH'; END IF;
 RETURN NEW;
END $body$;
-- Deferred: the domain RPC creates the order state, then Audit and command in
-- one transaction. Check the final state only when that transaction commits.
CREATE CONSTRAINT TRIGGER sales_confirmed_requires_audit_0305
 AFTER INSERT OR UPDATE ON core10.sales_orders_v1
 DEFERRABLE INITIALLY DEFERRED
 FOR EACH ROW EXECUTE FUNCTION core10._sales_confirmed_audit_guard_0305();

CREATE FUNCTION core10._sales_invoice_confirmation_guard_0305()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,core10 AS $body$
DECLARE o core10.sales_orders_v1%ROWTYPE;source_audit bigint;
BEGIN
 SELECT * INTO o FROM core10.sales_orders_v1 WHERE id=NEW.source_order_id
 AND tenant_id=NEW.tenant_id AND business_id=NEW.business_id
 AND site_id=NEW.site_id FOR SHARE;
 IF NOT FOUND OR o.status<>'confirmed' OR o.version<>NEW.source_order_version
 OR NEW.source_snapshot->'document' IS DISTINCT FROM o.document
 OR NEW.source_snapshot->>'total' IS DISTINCT FROM o.total::text
 OR NEW.customer_id<>o.customer_id OR NEW.currency<>o.currency
 THEN RAISE EXCEPTION 'SALES_INVOICE_SOURCE_AUDIT_MISMATCH'; END IF;
 -- Check the real confirmation event through the immutable command link;
 -- a self-consistent but forged source snapshot cannot stand in for it.
 SELECT c.audit_event_id INTO source_audit
 FROM core10.sales_order_commands_v1 c
 JOIN core10.canonical_audit_events_v1 a ON a.id=c.audit_event_id
 WHERE c.order_id=o.id AND c.tenant_id=o.tenant_id
 AND c.business_id=o.business_id AND c.site_id=o.site_id
 AND c.input->>'op'='confirm'
 AND c.receipt->>'status'='confirmed'
 AND (c.receipt->>'version')::bigint=o.version
 AND a.tenant_id=o.tenant_id AND a.business_id=o.business_id
 AND a.source_domain='sales' AND a.action='sales.confirm'
 AND a.source_ref=o.id::text||':'||o.version::text
 AND a.payload->'receipt'=c.receipt
 AND a.payload->'source'->'document'=o.document
 AND (a.payload->'source'->>'version')::bigint=o.version-1
 AND (a.payload->'source'->>'total')::numeric=o.total
 AND c.actor_id=a.actor_id
 LIMIT 1;
 IF source_audit IS NULL
 OR NEW.source_snapshot->>'confirmation_audit_event_id'<>source_audit::text
 THEN RAISE EXCEPTION 'SALES_INVOICE_SOURCE_AUDIT_MISMATCH'; END IF;
 RETURN NEW;
END $body$;
CREATE TRIGGER zz_sales_invoice_confirmation_guard_0305
 BEFORE INSERT OR UPDATE ON core10.sales_invoice_drafts_v1
 FOR EACH ROW EXECUTE FUNCTION core10._sales_invoice_confirmation_guard_0305();

-- Canonical Master retention: a numeric ID cannot outlive a referenced
-- party row while Sales/Invoice history still points to it.
CREATE FUNCTION core10._sales_master_party_restrict_0305()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,core10 AS $body$
BEGIN
 IF EXISTS(SELECT 1 FROM core10.sales_orders_v1
  WHERE customer_id=OLD.id AND tenant_id=OLD.tenant_id
    AND business_id=OLD.business_id)
 OR EXISTS(SELECT 1 FROM core10.sales_invoice_drafts_v1
  WHERE customer_id=OLD.id AND tenant_id=OLD.tenant_id
    AND business_id=OLD.business_id)
 THEN RAISE EXCEPTION 'SALES_MASTER_REFERENCE_RETAINED'; END IF;
 RETURN OLD;
END $body$;
CREATE TRIGGER sales_master_party_retention_0305
 BEFORE DELETE ON core10.master_parties_v1 FOR EACH ROW
 EXECUTE FUNCTION core10._sales_master_party_restrict_0305();

REVOKE ALL ON FUNCTION
 core10._sales_order_header_guard_0305(),
 core10._sales_order_lines_guard_0305(),
 core10._sales_command_frozen_0305(),
 core10._sales_command_approval_guard_0305(),
 core10._sales_confirmed_audit_guard_0305(),
 core10._sales_invoice_confirmation_guard_0305(),
 core10._sales_master_party_restrict_0305()
 FROM PUBLIC,authenticated;
INSERT INTO core10.schema_migrations(version,name,checksum) VALUES(305,'0305_np03b_p1_security','e6203101096b833fd860cb1685a82bdf6d4647e9e12f131ca8650bb663425c69');
