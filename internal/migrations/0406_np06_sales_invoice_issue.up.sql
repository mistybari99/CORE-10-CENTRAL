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
