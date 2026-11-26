-- CORE10 baseline20 v1; ordered, lossless consolidation. Fresh empty schema only.
-- CORE10 BASELINE SOURCE 0406_np06_sales_invoice_issue.up.sql SHA256 b64a4ea28a9737fe701756596661e433bc65ec1c98fa179e3577e23e231e33ad
-- NP06 integration 0406: attested Sales draft -> issued financial invoice
-- -> existing canonical Money journal -> existing AR open item.
-- Deliberate first slice: tax=0; no stock fulfillment, COGS or statutory invoice.
-- No shadow receivable, second general ledger or manually fabricated receipt.
DO $dep$ BEGIN
 IF to_regclass('core10.sales_invoice_drafts_v1') IS NULL
 OR to_regclass('core10.finance_arap_control_accounts_v1') IS NULL
 OR to_regclass('core10.finance_arap_links_v1') IS NULL
 OR to_regprocedure('core10._finance_arap_source_integrity_v1()') IS NULL
 THEN RAISE EXCEPTION 'FIN_SALES_BRIDGE_DEPENDENCY_NOT_CONNECTED'; END IF;
END $dep$;

INSERT INTO core10.control_catalog_v1
 (feature_key,title_en,title_bn,pack,default_enabled,default_stages,max_stages,
  allow_site_scope,approval_domain,approval_action,params) VALUES
 ('finance.sales_invoice_issue','Issue an attested Sales invoice into Money and AR',
  'বিক্রয় ইনভয়েস অর্থ ও পাওনা খতিয়ানে পোস্ট','NP06',false,0,0,true,NULL,NULL,'{}');

-- An immutable provenance edge, NOT a duplicate invoice or a balance cache.
-- Source version + canonical Audit + one posted journal identify a real issue.
CREATE TABLE core10.finance_sales_issues_v1(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL,
 business_id bigint NOT NULL,
 site_id bigint NOT NULL,
 invoice_id bigint NOT NULL UNIQUE,
 invoice_version bigint NOT NULL CHECK(invoice_version>0),
 source_order_id bigint NOT NULL,
 customer_id bigint NOT NULL,
 journal_id bigint NOT NULL UNIQUE,
 ar_account_id bigint NOT NULL,
 revenue_account_id bigint NOT NULL,
 issue_on date NOT NULL,
 due_on date NOT NULL CHECK(due_on>=issue_on),
 currency text NOT NULL CHECK(currency ~ '^[A-Z]{3}$'),
 amount numeric(18,4) NOT NULL CHECK(amount>0),
 request_key text NOT NULL CHECK(request_key ~ '^[A-Za-z0-9_-]{8,100}$'),
 created_by uuid NOT NULL,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 audit_event_id bigint NOT NULL REFERENCES core10.canonical_audit_events_v1(id),
 UNIQUE(business_id,request_key),
 UNIQUE(id,tenant_id,business_id),
 FOREIGN KEY(invoice_id,tenant_id,business_id,site_id,source_order_id)
  REFERENCES core10.sales_invoice_drafts_v1(id,tenant_id,business_id,site_id,source_order_id),
 FOREIGN KEY(journal_id,tenant_id,business_id)
  REFERENCES core10.finance_journals_v1(id,tenant_id,business_id),
 FOREIGN KEY(ar_account_id,tenant_id,business_id)
  REFERENCES core10.finance_accounts_v1(id,tenant_id,business_id),
 FOREIGN KEY(revenue_account_id,tenant_id,business_id)
  REFERENCES core10.finance_accounts_v1(id,tenant_id,business_id),
 FOREIGN KEY(customer_id,tenant_id,business_id)
  REFERENCES core10.master_parties_v1(id,tenant_id,business_id)
);
ALTER TABLE core10.finance_sales_issues_v1 ENABLE ROW LEVEL SECURITY;
CREATE POLICY finance_sales_issue_read_v1 ON core10.finance_sales_issues_v1
 FOR SELECT TO authenticated USING(core10.can_see_business(tenant_id,business_id));
REVOKE ALL ON core10.finance_sales_issues_v1 FROM PUBLIC,authenticated;
GRANT SELECT ON core10.finance_sales_issues_v1 TO authenticated;
REVOKE ALL ON SEQUENCE core10.finance_sales_issues_v1_id_seq FROM PUBLIC,authenticated;

CREATE FUNCTION core10._finance_sales_issue_immutable_v1()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,core10 AS $body$
BEGIN RAISE EXCEPTION 'FIN_SALES_ISSUE_IMMUTABLE'; END $body$;
CREATE TRIGGER finance_sales_issue_immutable_v1
 BEFORE UPDATE OR DELETE ON core10.finance_sales_issues_v1
 FOR EACH ROW EXECUTE FUNCTION core10._finance_sales_issue_immutable_v1();
CREATE TRIGGER finance_sales_issue_no_truncate_v1
 BEFORE TRUNCATE ON core10.finance_sales_issues_v1
 FOR EACH STATEMENT EXECUTE FUNCTION core10._finance_sales_issue_immutable_v1();
REVOKE ALL ON FUNCTION core10._finance_sales_issue_immutable_v1() FROM PUBLIC,authenticated;

-- Issued invoices cannot be edited/deleted and issued lines cannot be
-- rewritten even with ordinary privileged SQL. A previously validated but
-- not yet issued draft may be edited only via its existing edit/revalidate API.
CREATE FUNCTION core10._finance_sales_invoice_source_guard_v1()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,core10 AS $body$
BEGIN
 IF TG_OP='TRUNCATE' THEN RAISE EXCEPTION 'FIN_SALES_ISSUED_SOURCE_IMMUTABLE'; END IF;
 IF TG_TABLE_NAME='sales_invoice_drafts_v1' THEN
  IF TG_OP='DELETE' THEN
   IF EXISTS(SELECT 1 FROM core10.finance_sales_issues_v1 WHERE invoice_id=OLD.id)
   THEN RAISE EXCEPTION 'FIN_SALES_ISSUED_SOURCE_IMMUTABLE'; END IF;
   RETURN OLD;
  END IF;
  IF EXISTS(SELECT 1 FROM core10.finance_sales_issues_v1 WHERE invoice_id=OLD.id)
  THEN RAISE EXCEPTION 'FIN_SALES_ISSUED_SOURCE_IMMUTABLE'; END IF;
  -- Once validated, a clandestine in-place edit retaining the validation
  -- receipt is forbidden. The canonical save API clears validation on edit.
  IF OLD.validated_at IS NOT NULL AND NEW.validated_at IS NOT NULL
   AND ROW(NEW.document,NEW.selection,NEW.total,NEW.memo)
    IS DISTINCT FROM ROW(OLD.document,OLD.selection,OLD.total,OLD.memo)
  THEN RAISE EXCEPTION 'FIN_SALES_VALIDATED_SOURCE_TAMPER'; END IF;
  RETURN NEW;
 END IF;
 IF EXISTS(SELECT 1 FROM core10.finance_sales_issues_v1
  WHERE invoice_id=CASE WHEN TG_OP='DELETE' THEN OLD.invoice_id ELSE NEW.invoice_id END)
 THEN RAISE EXCEPTION 'FIN_SALES_ISSUED_SOURCE_IMMUTABLE'; END IF;
 -- Prevent an administrator's accidental or malicious change to a validated
 -- invoice's line table while preserving its header validation timestamp.
 -- Official edit clears validated_at before replacing draft lines.
 IF EXISTS(SELECT 1 FROM core10.sales_invoice_drafts_v1 i
   WHERE i.id=CASE WHEN TG_OP='DELETE' THEN OLD.invoice_id ELSE NEW.invoice_id END
   AND i.validated_at IS NOT NULL)
 THEN RAISE EXCEPTION 'FIN_SALES_VALIDATED_SOURCE_TAMPER'; END IF;
 RETURN CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
END $body$;
CREATE TRIGGER finance_sales_invoice_source_guard_v1
 BEFORE UPDATE OR DELETE ON core10.sales_invoice_drafts_v1
 FOR EACH ROW EXECUTE FUNCTION core10._finance_sales_invoice_source_guard_v1();
CREATE TRIGGER finance_sales_invoice_lines_guard_v1
 BEFORE INSERT OR UPDATE OR DELETE ON core10.sales_invoice_draft_lines_v1
 FOR EACH ROW EXECUTE FUNCTION core10._finance_sales_invoice_source_guard_v1();
CREATE TRIGGER finance_sales_invoice_lines_no_truncate_v1
 BEFORE TRUNCATE ON core10.sales_invoice_draft_lines_v1
 FOR EACH STATEMENT EXECUTE FUNCTION core10._finance_sales_invoice_source_guard_v1();
REVOKE ALL ON FUNCTION core10._finance_sales_invoice_source_guard_v1() FROM PUBLIC,authenticated;

-- EXTEND, never bypass, the original F3 0403 proof of posted Money source:
-- manual flows remain allowed as before, and Sales is allowed only when an
-- immutable source issue links this exact posted Finance journal to that
-- exact validated invoice and same Master party/control account.
CREATE OR REPLACE FUNCTION core10._finance_arap_source_integrity_v1()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,core10 AS $body$
DECLARE j core10.finance_journals_v1%ROWTYPE;
BEGIN
 SELECT * INTO j FROM core10.finance_journals_v1 WHERE id=NEW.journal_id;
 IF NOT FOUND OR j.status<>'posted' OR j.tenant_id<>NEW.tenant_id
  OR j.business_id<>NEW.business_id
 THEN RAISE EXCEPTION 'FIN_ARAP_SOURCE_NOT_POSTED'; END IF;
 IF j.source_domain='manual' THEN RETURN NEW; END IF;
 IF j.source_domain='sales_invoice' AND NEW.kind='ar' AND EXISTS(
  SELECT 1 FROM core10.finance_sales_issues_v1 si
  JOIN core10.sales_invoice_drafts_v1 i ON i.id=si.invoice_id
   AND i.tenant_id=si.tenant_id AND i.business_id=si.business_id
  WHERE si.journal_id=j.id AND si.tenant_id=j.tenant_id
    AND si.business_id=j.business_id AND si.site_id=j.site_id
    AND si.invoice_id=i.id AND si.invoice_version=i.version
    AND i.validated_at IS NOT NULL AND si.customer_id=NEW.party_id
    AND si.ar_account_id=NEW.account_id AND si.amount=i.total
    AND j.source_ref='invoice-'||si.invoice_id::text
    AND j.currency=si.currency
 ) THEN RETURN NEW; END IF;
 RAISE EXCEPTION 'FIN_ARAP_EXTERNAL_SOURCE_NOT_ATTESTED';
END $body$;

CREATE FUNCTION core10.finance_issue_sales_invoice_v1(
 p_invoice bigint,p_ar_account bigint,p_revenue_account bigint,
 p_issue_on date,p_due_on date,p_key text
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
 SET search_path=pg_catalog,core10 AS $body$
DECLARE i core10.sales_invoice_drafts_v1%ROWTYPE;
 o core10.sales_orders_v1%ROWTYPE;
 si core10.finance_sales_issues_v1%ROWTYPE;
 ar core10.finance_accounts_v1%ROWTYPE;
 rev core10.finance_accounts_v1%ROWTYPE;
 v_actor uuid:=core10.actor_uid();
 v_tenant bigint;v_business bigint;v_site bigint;v_order bigint;
 v_scale integer;v_total numeric;v_post jsonb;
 v_journal bigint;v_ar_link bigint;v_event bigint;
 v_draft_key text;v_post_key text;v_ar_key text;v_ref text;
 v_lines jsonb;v_r jsonb;
BEGIN
 SELECT tenant_id,business_id,site_id,source_order_id
  INTO v_tenant,v_business,v_site,v_order
 FROM core10.sales_invoice_drafts_v1 WHERE id=p_invoice;
 IF v_actor IS NULL OR v_tenant IS NULL
 OR NOT core10.can_manage(v_tenant,v_business)
 THEN RAISE EXCEPTION 'FIN_SALES_AUTH_DENIED'; END IF;
 PERFORM core10._sales_scope_v1(v_business,v_site);
 -- Sales command lock order is source Order -> Invoice, retained here.
 SELECT * INTO o FROM core10.sales_orders_v1 WHERE id=v_order
 AND tenant_id=v_tenant AND business_id=v_business AND site_id=v_site FOR UPDATE;
 SELECT * INTO i FROM core10.sales_invoice_drafts_v1 WHERE id=p_invoice
 AND tenant_id=v_tenant AND business_id=v_business AND site_id=v_site FOR UPDATE;
 IF NOT FOUND OR o.id IS NULL OR NOT core10.can_manage(v_tenant,v_business)
 THEN RAISE EXCEPTION 'FIN_SALES_AUTH_DENIED'; END IF;
 PERFORM core10._sales_scope_v1(v_business,v_site);
 PERFORM core10.control_check_v1(v_business,'finance.sales_invoice_issue',v_site);
 PERFORM core10.control_check_v1(v_business,'sales.invoice_validate',v_site);
 PERFORM core10.control_check_v1(v_business,'finance.arap_link',v_site);
 v_post:=core10.control_check_v1(v_business,'finance.journal_post',v_site);
 IF (v_post->>'stages')::integer<>0
 THEN RAISE EXCEPTION 'FIN_SALES_STAGED_POST_NOT_CONNECTED'; END IF;
 IF p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{8,100}$'
 OR p_issue_on IS NULL OR p_due_on IS NULL OR p_due_on<p_issue_on
 OR p_ar_account IS NULL OR p_revenue_account IS NULL OR p_ar_account=p_revenue_account
 THEN RAISE EXCEPTION 'FIN_SALES_INVALID_INPUT'; END IF;
 SELECT * INTO si FROM core10.finance_sales_issues_v1
 WHERE invoice_id=i.id;
 IF FOUND THEN
  IF si.request_key=p_key AND si.created_by=v_actor
    AND si.ar_account_id=p_ar_account AND si.revenue_account_id=p_revenue_account
    AND si.issue_on=p_issue_on AND si.due_on=p_due_on
  THEN
   SELECT id INTO v_ar_link FROM core10.finance_arap_links_v1
   WHERE journal_id=si.journal_id;
   RETURN jsonb_build_object('invoice_id',i.id,'issue_id',si.id,
     'journal_id',si.journal_id,'ar_link_id',v_ar_link,
     'issued',true,'money_posted',true,'stock_posted',false,'tax_mode','ZERO_ONLY',
     'audit_event_id',si.audit_event_id);
  END IF;
  RAISE EXCEPTION 'FIN_SALES_ALREADY_ISSUED';
 END IF;
 IF i.validated_at IS NULL OR i.status<>'draft'
 OR o.status<>'confirmed' OR o.version<>i.source_order_version
 OR o.document IS DISTINCT FROM i.source_snapshot->'document'
 OR i.currency<>o.currency OR i.customer_id<>o.customer_id
 OR i.total<=0 OR scale(i.total)>4
 THEN RAISE EXCEPTION 'FIN_SALES_SOURCE_NOT_VALIDATED'; END IF;
 IF EXISTS(SELECT 1 FROM core10.sales_invoice_draft_lines_v1
  WHERE invoice_id=i.id AND tax_percent<>0)
 OR EXISTS(SELECT 1 FROM jsonb_array_elements(i.document->'lines') l
  WHERE (l->>'tax_percent')::numeric<>0)
 THEN RAISE EXCEPTION 'FIN_SALES_TAX_NOT_CONNECTED'; END IF;
 SELECT coalesce(sum(line_total),0) INTO v_total
 FROM core10.sales_invoice_draft_lines_v1 WHERE invoice_id=i.id;
 IF v_total IS DISTINCT FROM i.total THEN RAISE EXCEPTION 'FIN_SALES_INVOICE_LINES_MISMATCH'; END IF;
 -- The total alone is insufficient: a privileged change to product, UOM,
 -- quantity or unit price can preserve the same total. Re-attest the entire
 -- canonical itemized payload against the persisted Sales line rows.
 IF EXISTS(
  SELECT 1
  FROM jsonb_array_elements(i.document->'lines') WITH ORDINALITY d(doc,n)
  FULL JOIN core10.sales_invoice_draft_lines_v1 l
   ON l.invoice_id=i.id AND l.line_no=d.n
  WHERE d.doc IS NULL OR l.invoice_id IS NULL
   OR l.item_id IS DISTINCT FROM (d.doc->>'item_id')::bigint
   OR l.variant_id IS DISTINCT FROM (d.doc->>'variant_id')::bigint
   OR l.uom_id IS DISTINCT FROM (d.doc->>'uom_id')::bigint
   OR l.quantity IS DISTINCT FROM (d.doc->>'quantity')::numeric
   OR l.unit_price IS DISTINCT FROM (d.doc->>'unit_price')::numeric
   OR l.discount_percent IS DISTINCT FROM (d.doc->>'discount_percent')::numeric
   OR l.tax_percent IS DISTINCT FROM (d.doc->>'tax_percent')::numeric
   OR l.line_total IS DISTINCT FROM round(
    (d.doc->>'quantity')::numeric*(d.doc->>'unit_price')::numeric*
    (1-(d.doc->>'discount_percent')::numeric/100),i.money_scale)
 ) THEN RAISE EXCEPTION 'FIN_SALES_INVOICE_LINES_MISMATCH'; END IF;
 -- Prove the original canonical Sales validation command/Audit belongs to this
 -- exact immutable version, not just an arbitrary successful Audit checksum.
 IF NOT EXISTS(
  SELECT 1 FROM core10.sales_invoice_commands_v1 c
  JOIN core10.canonical_audit_events_v1 a ON a.id=c.audit_event_id
  WHERE c.invoice_id=i.id AND c.tenant_id=i.tenant_id
   AND c.business_id=i.business_id AND c.site_id=i.site_id
   AND c.source_order_id=i.source_order_id
   AND c.input->>'op'='validate'
   AND (c.input->>'expected')::bigint=i.version-1
   AND c.receipt->>'validated'='true'
   AND (c.receipt->>'version')::bigint=i.version
   AND (c.receipt->>'total')::numeric=i.total
   AND c.receipt->>'source_sha256'=i.source_sha256
   AND a.tenant_id=i.tenant_id AND a.business_id=i.business_id
   AND a.source_domain='sales_invoice'
   AND a.action='sales.invoice_draft_validated'
   AND a.source_ref=i.id::text||':'||i.version::text
   AND a.payload->'receipt'=c.receipt
   AND a.actor_id=c.actor_id
 ) THEN RAISE EXCEPTION 'FIN_SALES_VALIDATION_AUDIT_NOT_ATTESTED'; END IF;
 -- Current canonical Master validation (historical-price eligibility is
 -- intentionally fail-closed; this does not relabel old prices as current).
 PERFORM core10._sales_validate_v1(v_business,v_site,i.document,
  core10.control_check_v1(v_business,'sales.invoice_draft',v_site)->'params');
 SELECT * INTO ar FROM core10.finance_accounts_v1
  WHERE id=p_ar_account AND tenant_id=i.tenant_id
   AND business_id=i.business_id FOR SHARE;
 SELECT * INTO rev FROM core10.finance_accounts_v1
  WHERE id=p_revenue_account AND tenant_id=i.tenant_id
   AND business_id=i.business_id FOR SHARE;
 IF ar.id IS NULL OR rev.id IS NULL OR NOT ar.active OR NOT rev.active
 OR ar.category<>'asset' OR rev.category<>'income'
 OR ar.currency<>i.currency OR rev.currency<>i.currency
 OR ar.legal_entity_id<>rev.legal_entity_id
 OR EXISTS(SELECT 1 FROM core10.finance_accounts_v1 ch
  WHERE ch.parent_id IN(ar.id,rev.id))
 OR NOT EXISTS(SELECT 1 FROM core10.finance_arap_control_accounts_v1 control
  WHERE control.tenant_id=i.tenant_id AND control.business_id=i.business_id
    AND control.account_id=ar.id AND control.kind='ar')
 THEN RAISE EXCEPTION 'FIN_SALES_ACCOUNT_NOT_DESIGNATED'; END IF;
 v_ref:='invoice-'||i.id::text;
 v_draft_key:=encode(sha256(convert_to(
  'sales-issued:draft:'||i.business_id||':'||i.id||':'||p_key,'UTF8')),'hex');
 v_post_key:=encode(sha256(convert_to(
  'sales-issued:post:'||i.business_id||':'||i.id||':'||p_key,'UTF8')),'hex');
 v_ar_key:=encode(sha256(convert_to(
  'sales-issued:ar:'||i.business_id||':'||i.id||':'||p_key,'UTF8')),'hex');
 v_lines:=jsonb_build_array(
  jsonb_build_object('account_id',ar.id,'side','debit','amount',i.total),
  jsonb_build_object('account_id',rev.id,'side','credit','amount',i.total));
 v_journal:=core10.finance_draft_journal_v1(
  i.business_id,i.site_id,i.currency,p_issue_on,
  'sales_invoice',v_ref,v_draft_key,v_lines);
 PERFORM core10.finance_validate_journal_v1(v_journal);
 PERFORM core10.finance_post_journal_v1(v_journal,v_post_key);
 v_event:=core10._append_canonical_audit_v1(
  i.tenant_id,i.business_id,'sales_invoice',
  'invoice:'||i.id||':issue','sales.invoice_issued',v_actor,
  'sales:invoice-issue:'||p_key,
  jsonb_build_object('invoice_id',i.id,'version',i.version,
   'source_order_id',i.source_order_id,'customer_id',i.customer_id,
   'source_sha256',i.source_sha256,'journal_id',v_journal,
   'amount',i.total,'currency',i.currency,'tax_mode','ZERO_ONLY',
   'stock_posted',false,'issued_as','internal_finance_invoice_not_statutory'));
 INSERT INTO core10.finance_sales_issues_v1(
  tenant_id,business_id,site_id,invoice_id,invoice_version,source_order_id,
  customer_id,journal_id,ar_account_id,revenue_account_id,issue_on,due_on,
  currency,amount,request_key,created_by,audit_event_id)
 VALUES(i.tenant_id,i.business_id,i.site_id,i.id,i.version,i.source_order_id,
  i.customer_id,v_journal,ar.id,rev.id,p_issue_on,p_due_on,
  i.currency,i.total,p_key,v_actor,v_event) RETURNING * INTO si;
 -- The new F3 source-integrity trigger verifies this exact immutable issue.
 v_ar_link:=core10.finance_link_open_item_v1(
  v_journal,i.customer_id,ar.id,'ar',p_due_on,v_ar_key);
 RETURN jsonb_build_object('invoice_id',i.id,'issue_id',si.id,
   'journal_id',v_journal,'ar_link_id',v_ar_link,'issued',true,
   'money_posted',true,'stock_posted',false,'tax_mode','ZERO_ONLY',
   'audit_event_id',v_event);
END $body$;
REVOKE ALL ON FUNCTION core10.finance_issue_sales_invoice_v1(
 bigint,bigint,bigint,date,date,text) FROM PUBLIC,authenticated;
GRANT EXECUTE ON FUNCTION core10.finance_issue_sales_invoice_v1(
 bigint,bigint,bigint,date,date,text) TO authenticated;

INSERT INTO core10.control_rpc_map_v1
 (rpc_name,status,feature_key,reason,lane,board_row,test_ref)
VALUES('finance_issue_sales_invoice_v1','enforced','finance.sales_invoice_issue',
 'Validated canonical Sales source + immutable issue + existing Money and AR, all atomic',
 'ChatGPT','B-013','tests/migrations/np06-sales-finance-bridge-e2e.sql');
INSERT INTO core10.schema_migrations(version,name,checksum) VALUES(406,'0406_np06_sales_invoice_issue','b64a4ea28a9737fe701756596661e433bc65ec1c98fa179e3577e23e231e33ad');

-- CORE10 BASELINE SOURCE 0407_np06_sales_collection.up.sql SHA256 ff7630da8754fc78192dea44ace2961843495ad04e8200525f20e029b3196c63
-- NP06 cross-lane 0407: posted cash collection on a real Sales invoice,
-- same canonical Money journal and immutable AR allocation. Still NOT a bank
-- statement, payment-gateway authorization or tax/e-invoice certification.
DO $dep$ BEGIN
 IF to_regclass('core10.finance_sales_issues_v1') IS NULL
 OR to_regprocedure('core10.finance_allocate_payment_v1(bigint,bigint,numeric,text)') IS NULL
 OR to_regprocedure('core10._finance_arap_settlement_integrity_v1()') IS NULL
 THEN RAISE EXCEPTION 'FIN_SALES_COLLECTION_DEPENDENCY_NOT_CONNECTED'; END IF;
END $dep$;
INSERT INTO core10.control_catalog_v1(
 feature_key,title_en,title_bn,pack,default_enabled,default_stages,max_stages,
 allow_site_scope,approval_domain,approval_action,params
) VALUES(
 'finance.sales_collection','Post internal customer collection and allocate to AR',
 'গ্রাহকের টাকা জমা ও পাওনার সাথে সমন্বয়',
 'NP06',false,0,0,true,NULL,NULL,'{}'
);
CREATE TABLE core10.finance_sales_collections_v1(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL,
 business_id bigint NOT NULL,
 issue_id bigint NOT NULL,
 journal_id bigint NOT NULL UNIQUE,
 cash_account_id bigint NOT NULL,
 amount numeric(18,4) NOT NULL CHECK(amount>0),
 paid_on date NOT NULL,
 source_ref text NOT NULL CHECK(length(source_ref) BETWEEN 1 AND 100),
 request_key text NOT NULL CHECK(request_key ~ '^[A-Za-z0-9_-]{8,100}$'),
 created_by uuid NOT NULL,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 audit_event_id bigint NOT NULL REFERENCES core10.canonical_audit_events_v1(id),
 UNIQUE(business_id,request_key),
 FOREIGN KEY(issue_id,tenant_id,business_id)
  REFERENCES core10.finance_sales_issues_v1(id,tenant_id,business_id),
 FOREIGN KEY(journal_id,tenant_id,business_id)
  REFERENCES core10.finance_journals_v1(id,tenant_id,business_id),
 FOREIGN KEY(cash_account_id,tenant_id,business_id)
  REFERENCES core10.finance_accounts_v1(id,tenant_id,business_id)
);
ALTER TABLE core10.finance_sales_collections_v1 ENABLE ROW LEVEL SECURITY;
CREATE POLICY finance_sales_collections_read_v1 ON core10.finance_sales_collections_v1
 FOR SELECT TO authenticated USING(core10.can_see_business(tenant_id,business_id));
REVOKE ALL ON core10.finance_sales_collections_v1 FROM PUBLIC,authenticated;
GRANT SELECT ON core10.finance_sales_collections_v1 TO authenticated;
REVOKE ALL ON SEQUENCE core10.finance_sales_collections_v1_id_seq FROM PUBLIC,authenticated;
CREATE FUNCTION core10._finance_sales_collection_immutable_v1()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,core10 AS $body$
BEGIN RAISE EXCEPTION 'FIN_SALES_COLLECTION_IMMUTABLE'; END $body$;
CREATE TRIGGER finance_sales_collection_immutable_v1
 BEFORE UPDATE OR DELETE ON core10.finance_sales_collections_v1
 FOR EACH ROW EXECUTE FUNCTION core10._finance_sales_collection_immutable_v1();
CREATE TRIGGER finance_sales_collection_no_truncate_v1
 BEFORE TRUNCATE ON core10.finance_sales_collections_v1
 FOR EACH STATEMENT EXECUTE FUNCTION core10._finance_sales_collection_immutable_v1();
REVOKE ALL ON FUNCTION core10._finance_sales_collection_immutable_v1()
 FROM PUBLIC,authenticated;

-- Keep F3 original manual payment source valid; additionally accept Sales
-- collections only when an immutable source row ties this payment to the
-- EXACT issued invoice, AR account, party, date and full allocated amount.
CREATE OR REPLACE FUNCTION core10._finance_arap_settlement_integrity_v1()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,core10 AS $body$
DECLARE l core10.finance_arap_links_v1%ROWTYPE;
 pay core10.finance_journals_v1%ROWTYPE;
 v_side text; v_control_total numeric; v_asset_total numeric;
BEGIN
 SELECT * INTO l FROM core10.finance_arap_links_v1 WHERE id=NEW.link_id;
 SELECT * INTO pay FROM core10.finance_journals_v1 WHERE id=NEW.payment_journal_id;
 IF l.id IS NULL OR pay.id IS NULL OR pay.status<>'posted'
  OR pay.business_id<>l.business_id OR pay.tenant_id<>l.tenant_id
 THEN RAISE EXCEPTION 'FIN_ARAP_PAYMENT_SOURCE_NOT_POSTED'; END IF;
 IF pay.source_domain<>'manual' THEN
  IF pay.source_domain<>'sales_collection' OR l.kind<>'ar'
  OR NOT EXISTS(
    SELECT 1 FROM core10.finance_sales_collections_v1 sc
    JOIN core10.finance_sales_issues_v1 si
      ON si.id=sc.issue_id AND si.tenant_id=sc.tenant_id
      AND si.business_id=sc.business_id
    WHERE sc.journal_id=pay.id AND sc.tenant_id=pay.tenant_id
      AND sc.business_id=pay.business_id
      AND sc.source_ref=pay.source_ref
      AND si.journal_id=l.journal_id
      AND si.ar_account_id=l.account_id
      AND si.customer_id=l.party_id
      AND sc.amount=NEW.amount
      AND sc.paid_on=pay.effective_on
      AND sc.cash_account_id<>l.account_id
  ) THEN RAISE EXCEPTION 'FIN_ARAP_PAYMENT_SOURCE_NOT_ATTESTED'; END IF;
 END IF;

 v_side:=CASE WHEN l.kind='ar' THEN 'debit' ELSE 'credit' END;
 v_control_total:=core10._finance_arap_net_v1(pay.id,l.account_id,
   CASE WHEN l.kind='ar' THEN 'credit' ELSE 'debit' END);
 SELECT coalesce(sum(line.amount),0) INTO v_asset_total
 FROM core10.finance_journal_lines_v1 line
 JOIN core10.finance_accounts_v1 a ON a.id=line.account_id
 WHERE line.journal_id=pay.id
   AND line.account_id<>l.account_id
   AND line.side=v_side
   AND a.category='asset'
   AND a.business_id=l.business_id AND a.tenant_id=l.tenant_id
   AND a.currency=pay.currency AND a.legal_entity_id=pay.legal_entity_id;
 IF v_control_total<=0 OR v_asset_total<v_control_total
 THEN RAISE EXCEPTION 'FIN_ARAP_SETTLEMENT_ASSET_COUNTERPART_MISSING'; END IF;
 RETURN NEW;
END $body$;


-- Read-only Money/AR trace must not call verified external invoice a "manual"
-- journal or imply our internally posted cash is an attested bank statement.
CREATE OR REPLACE FUNCTION core10.finance_arap_trace_v1(p_link bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $body$
DECLARE l core10.finance_arap_links_v1%ROWTYPE;
 j core10.finance_journals_v1%ROWTYPE;
 v_party_code text; v_payment_refs jsonb;
BEGIN
 SELECT * INTO l FROM core10.finance_arap_links_v1 WHERE id=p_link;
 IF NOT FOUND OR core10.actor_uid() IS NULL
  OR NOT core10.can_see_business(l.tenant_id,l.business_id)
 THEN RAISE EXCEPTION 'FIN_ARAP_READ_DENIED'; END IF;
 SELECT * INTO j FROM core10.finance_journals_v1
  WHERE id=l.journal_id AND tenant_id=l.tenant_id AND business_id=l.business_id;
 IF NOT FOUND OR j.status<>'posted' THEN RAISE EXCEPTION 'FIN_ARAP_SOURCE_NOT_POSTED'; END IF;
 SELECT code INTO v_party_code FROM core10.master_parties_v1
  WHERE id=l.party_id AND business_id=l.business_id AND tenant_id=l.tenant_id;
 SELECT coalesce(jsonb_agg(jsonb_build_object(
   'allocation_id',a.id,'amount',a.amount,
   'payment_journal_id',pay.id,'payment_source_domain',pay.source_domain,
   'payment_source_ref',pay.source_ref,'payment_effective_on',pay.effective_on,
   'payment_provenance',CASE WHEN pay.source_domain='sales_collection'
      THEN 'canonical_sales_cash_movement_not_bank_statement_attested'
      ELSE 'manual_asset_counterpart_not_bank_attested' END,
   'payment_post_audit_event_id',pay.audit_event_id,
   'allocation_audit_event_id',a.audit_event_id
  ) ORDER BY a.id),'[]'::jsonb) INTO v_payment_refs
 FROM core10.finance_arap_allocations_v1 a
 JOIN core10.finance_journals_v1 pay ON pay.id=a.payment_journal_id
 WHERE a.link_id=l.id;
 RETURN jsonb_build_object(
  'link_id',l.id,'business_id',l.business_id,'kind',l.kind,
  'party_id',l.party_id,'party_code',v_party_code,
  'document_journal_id',j.id,
  'document_source_domain',j.source_domain,
  'document_source_ref',j.source_ref,
  'document_provenance',CASE WHEN j.source_domain='sales_invoice'
    THEN 'canonical_issued_sales_invoice_money_posted_stock_not_attested'
    ELSE 'manual_posted_journal_not_external_invoice_attested' END,
  'document_post_audit_event_id',j.audit_event_id,
  'link_audit_event_id',l.audit_event_id,'currency',j.currency,
  'effective_on',j.effective_on,'due_on',l.due_on,
  'account_id',l.account_id,
  'posted_amount',core10._finance_arap_net_v1(
    j.id,l.account_id,CASE WHEN l.kind='ar' THEN 'debit' ELSE 'credit' END),
  'reversed',EXISTS(SELECT 1 FROM core10.finance_reversals_v1 r
                   WHERE r.original_journal_id=j.id),
  'payment_allocations',v_payment_refs
 );
END $body$;


CREATE FUNCTION core10.finance_collect_sales_invoice_v1(
 p_issue bigint,p_cash_account bigint,p_paid_on date,p_amount numeric,p_key text
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
 SET search_path=pg_catalog,core10 AS $body$
DECLARE si core10.finance_sales_issues_v1%ROWTYPE;
 arlink core10.finance_arap_links_v1%ROWTYPE;
 prior core10.finance_sales_collections_v1%ROWTYPE;
 cash core10.finance_accounts_v1%ROWTYPE;
 v_actor uuid:=core10.actor_uid();v_tenant bigint;v_business bigint;
 v_control jsonb;v_paid numeric;v_open numeric;v_used numeric;
 v_source_ref text;v_draft_key text;v_post_key text;v_ar_key text;
 v_pay bigint;v_alloc bigint;v_audit bigint;
BEGIN
 SELECT tenant_id,business_id INTO v_tenant,v_business
 FROM core10.finance_sales_issues_v1 WHERE id=p_issue;
 IF v_actor IS NULL OR v_tenant IS NULL
 OR NOT core10.can_manage(v_tenant,v_business)
 THEN RAISE EXCEPTION 'FIN_SALES_COLLECTION_AUTH_DENIED'; END IF;
 SELECT * INTO si FROM core10.finance_sales_issues_v1
 WHERE id=p_issue AND tenant_id=v_tenant AND business_id=v_business FOR SHARE;
 IF NOT FOUND OR NOT core10.can_manage(si.tenant_id,si.business_id)
 THEN RAISE EXCEPTION 'FIN_SALES_COLLECTION_AUTH_DENIED'; END IF;
 PERFORM core10.control_check_v1(si.business_id,'finance.sales_collection',si.site_id);
 PERFORM core10.control_check_v1(si.business_id,'finance.arap_allocate',si.site_id);
 v_control:=core10.control_check_v1(si.business_id,'finance.journal_post',si.site_id);
 IF (v_control->>'stages')::integer<>0
 THEN RAISE EXCEPTION 'FIN_SALES_COLLECTION_STAGED_POST_NOT_CONNECTED'; END IF;
 IF p_paid_on IS NULL OR p_paid_on<si.issue_on
 OR p_amount IS NULL OR p_amount<=0
 OR p_amount IN('NaN'::numeric,'Infinity'::numeric)
 OR scale(p_amount)>4 OR p_amount>99999999999999
 OR p_cash_account IS NULL OR p_cash_account=si.ar_account_id
 OR p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{8,100}$'
 THEN RAISE EXCEPTION 'FIN_SALES_COLLECTION_INVALID_INPUT'; END IF;
 SELECT * INTO prior FROM core10.finance_sales_collections_v1
 WHERE business_id=si.business_id AND request_key=p_key;
 IF FOUND THEN
  IF prior.issue_id=si.id AND prior.created_by=v_actor
   AND prior.cash_account_id=p_cash_account AND prior.paid_on=p_paid_on
   AND prior.amount=p_amount
  THEN
   SELECT id INTO v_alloc FROM core10.finance_arap_allocations_v1
   WHERE payment_journal_id=prior.journal_id AND business_id=si.business_id;
   RETURN jsonb_build_object('issue_id',si.id,'collection_id',prior.id,
    'payment_journal_id',prior.journal_id,'allocation_id',v_alloc,
    'amount',prior.amount,'cash_posted',true,'bank_statement_attested',false,
    'audit_event_id',prior.audit_event_id);
  END IF;
  RAISE EXCEPTION 'FIN_SALES_COLLECTION_KEY_CONFLICT'; END IF;
 -- Serialize all competing partial collections and source reversals by
 -- locking the actual issued Money journal, the same lock F3 allocation uses.
 PERFORM 1 FROM core10.finance_journals_v1
 WHERE id=si.journal_id AND tenant_id=si.tenant_id
 AND business_id=si.business_id AND status='posted' FOR UPDATE;
 IF NOT FOUND OR NOT core10.can_manage(si.tenant_id,si.business_id)
 THEN RAISE EXCEPTION 'FIN_SALES_COLLECTION_SOURCE_NOT_POSTED'; END IF;
 SELECT * INTO arlink FROM core10.finance_arap_links_v1
 WHERE journal_id=si.journal_id AND tenant_id=si.tenant_id
  AND business_id=si.business_id AND kind='ar';
 IF NOT FOUND OR arlink.account_id<>si.ar_account_id
  OR arlink.party_id<>si.customer_id
 THEN RAISE EXCEPTION 'FIN_SALES_COLLECTION_AR_NOT_LINKED'; END IF;
 SELECT * INTO cash FROM core10.finance_accounts_v1
 WHERE id=p_cash_account AND tenant_id=si.tenant_id AND business_id=si.business_id FOR SHARE;
 IF NOT FOUND OR cash.category<>'asset' OR NOT cash.active
 OR cash.currency<>si.currency OR cash.parent_id IS NOT NULL
 OR EXISTS(SELECT 1 FROM core10.finance_accounts_v1 ch WHERE ch.parent_id=cash.id)
 OR EXISTS(SELECT 1 FROM core10.finance_arap_control_accounts_v1 a
  WHERE a.account_id=cash.id AND a.business_id=si.business_id)
 THEN RAISE EXCEPTION 'FIN_SALES_COLLECTION_CASH_ACCOUNT_INVALID'; END IF;
 v_open:=core10._finance_arap_net_v1(si.journal_id,si.ar_account_id,'debit');
 SELECT coalesce(sum(amount),0) INTO v_used FROM core10.finance_arap_allocations_v1
 WHERE link_id=arlink.id;
 IF v_open<=0 OR v_used+p_amount>v_open
 THEN RAISE EXCEPTION 'FIN_ARAP_OVERALLOCATION'; END IF;
 v_source_ref:='collection-'||encode(sha256(convert_to(
  si.business_id||':'||si.id||':'||p_key,'UTF8')),'hex');
 v_draft_key:=encode(sha256(convert_to(
  'sales-collection:draft:'||si.business_id||':'||si.id||':'||p_key,'UTF8')),'hex');
 v_post_key:=encode(sha256(convert_to(
  'sales-collection:post:'||si.business_id||':'||si.id||':'||p_key,'UTF8')),'hex');
 v_ar_key:=encode(sha256(convert_to(
  'sales-collection:allocate:'||si.business_id||':'||si.id||':'||p_key,'UTF8')),'hex');
 -- One existing Money journal: Dr actual internal cash GL account, Cr AR.
 v_pay:=core10.finance_draft_journal_v1(
  si.business_id,si.site_id,si.currency,p_paid_on,
  'sales_collection',v_source_ref,v_draft_key,
  jsonb_build_array(
   jsonb_build_object('account_id',cash.id,'side','debit','amount',p_amount),
   jsonb_build_object('account_id',si.ar_account_id,'side','credit','amount',p_amount)));
 PERFORM core10.finance_validate_journal_v1(v_pay);
 PERFORM core10.finance_post_journal_v1(v_pay,v_post_key);
 v_audit:=core10._append_canonical_audit_v1(
  si.tenant_id,si.business_id,'sales_collection',
  'issue:'||si.id||':payment:'||v_pay,
  'sales.collection_posted',v_actor,
  'sales:collection:'||p_key,
  jsonb_build_object('issue_id',si.id,'invoice_id',si.invoice_id,
   'source_journal_id',si.journal_id,'payment_journal_id',v_pay,
   'cash_account_id',cash.id,'ar_account_id',si.ar_account_id,
   'amount',p_amount,'currency',si.currency,
   'paid_on',p_paid_on,'bank_statement_attested',false));
 INSERT INTO core10.finance_sales_collections_v1(
  tenant_id,business_id,issue_id,journal_id,cash_account_id,amount,
  paid_on,source_ref,request_key,created_by,audit_event_id)
 VALUES(si.tenant_id,si.business_id,si.id,v_pay,cash.id,p_amount,
  p_paid_on,v_source_ref,p_key,v_actor,v_audit) RETURNING * INTO prior;
 -- F3 verifies real posted source and positive asset counterpart before
 -- appending one immutable allocation; failure unwinds the entire Money post.
 v_alloc:=core10.finance_allocate_payment_v1(
  arlink.id,v_pay,p_amount,v_ar_key);
 RETURN jsonb_build_object('issue_id',si.id,'collection_id',prior.id,
  'payment_journal_id',v_pay,'allocation_id',v_alloc,'amount',p_amount,
  'cash_posted',true,'bank_statement_attested',false,'audit_event_id',v_audit);
END $body$;
REVOKE ALL ON FUNCTION core10.finance_collect_sales_invoice_v1(
 bigint,bigint,date,numeric,text) FROM PUBLIC,authenticated;
GRANT EXECUTE ON FUNCTION core10.finance_collect_sales_invoice_v1(
 bigint,bigint,date,numeric,text) TO authenticated;

-- Credit note / certified deallocation is NOT CONNECTED; do not let a plain
-- Money reversal silently negate an immutable issued Sales or cash receipt.
CREATE FUNCTION core10._finance_sales_no_reverse_v1()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,core10 AS $body$
BEGIN
 IF EXISTS(SELECT 1 FROM core10.finance_sales_issues_v1
  WHERE journal_id=NEW.original_journal_id)
 OR EXISTS(SELECT 1 FROM core10.finance_sales_collections_v1
  WHERE journal_id=NEW.original_journal_id)
 THEN RAISE EXCEPTION 'FIN_SALES_CREDIT_NOTE_NOT_CONNECTED'; END IF;
 RETURN NEW;
END $body$;
CREATE TRIGGER finance_sales_no_reverse_v1
 BEFORE INSERT ON core10.finance_reversals_v1 FOR EACH ROW
 EXECUTE FUNCTION core10._finance_sales_no_reverse_v1();
REVOKE EXECUTE ON FUNCTION core10._finance_sales_no_reverse_v1()
 FROM PUBLIC,authenticated;
INSERT INTO core10.control_rpc_map_v1(
 rpc_name,status,feature_key,reason,lane,board_row,test_ref
) VALUES(
 'finance_collect_sales_invoice_v1','enforced','finance.sales_collection',
 'Existing posted Money Dr cash Cr AR, attested source and atomic immutable F3 allocation',
 'ChatGPT','B-013','tests/migrations/np06-sales-finance-bridge-e2e.sql'
);
INSERT INTO core10.schema_migrations(version,name,checksum) VALUES(407,'0407_np06_sales_collection','ff7630da8754fc78192dea44ace2961843495ad04e8200525f20e029b3196c63');
