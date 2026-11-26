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
