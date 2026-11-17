-- NP06/B-013/0402 — canonical AR/AP linkage + payment allocation on the ONE Finance ledger.
-- Stacked development only: requires 0401 and NP02 Master 0150–0153; no hosted apply.
-- No customer/supplier clone, invoice ledger, payable/receivable balance cache or payment posting.
DO $dep$ BEGIN
 IF to_regclass('core10.master_parties_v1') IS NULL
 OR to_regclass('core10.finance_reversals_v1') IS NULL
 OR to_regclass('core10.finance_journal_lines_v1') IS NULL
 THEN RAISE EXCEPTION 'FIN_ARAP_DEPENDENCY_NOT_CONNECTED'; END IF;
END $dep$;

INSERT INTO core10.control_catalog_v1
 (feature_key,title_en,title_bn,pack,default_enabled,default_stages,max_stages,
  allow_site_scope,approval_domain,approval_action,params) VALUES
 ('finance.arap_link','Link posted AR/AP journal to Master party','পোস্টকৃত পাওনা/দেনা এবং পার্টি সংযোগ',
  'NP06',false,0,0,true,NULL,NULL,'{}'),
 ('finance.arap_allocate','Allocate an existing posted payment journal','পোস্টকৃত পেমেন্ট বরাদ্দ',
  'NP06',false,0,0,true,NULL,NULL,'{}');

-- One AR/AP open item is one immutable pointer to an EXISTING posted journal line
-- plus the canonical NP02 Master party. Amount/currency/balance are NOT duplicated.
CREATE TABLE core10.finance_arap_links_v1(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL,
 business_id bigint NOT NULL,
 kind text NOT NULL CHECK (kind IN ('ar','ap')),
 party_id bigint NOT NULL,
 journal_id bigint NOT NULL UNIQUE,
 account_id bigint NOT NULL,
 due_on date NOT NULL,
 request_key text NOT NULL CHECK (request_key ~ '^[A-Za-z0-9_-]{8,128}$'),
 created_by uuid NOT NULL,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 audit_event_id bigint NOT NULL REFERENCES core10.canonical_audit_events_v1(id),
 UNIQUE (id,tenant_id,business_id),
 UNIQUE (business_id,request_key),
 FOREIGN KEY (party_id,tenant_id,business_id)
  REFERENCES core10.master_parties_v1(id,tenant_id,business_id),
 FOREIGN KEY (journal_id,tenant_id,business_id)
  REFERENCES core10.finance_journals_v1(id,tenant_id,business_id),
 FOREIGN KEY (account_id,tenant_id,business_id)
  REFERENCES core10.finance_accounts_v1(id,tenant_id,business_id)
);
CREATE INDEX finance_arap_links_party_idx ON core10.finance_arap_links_v1(business_id,party_id,kind,due_on);

-- Allocation is an immutable relationship between TWO posted journal movements.
-- The amount is an allocation measure, not a new balance or posted cash entry.
CREATE TABLE core10.finance_arap_allocations_v1(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL,
 business_id bigint NOT NULL,
 link_id bigint NOT NULL,
 payment_journal_id bigint NOT NULL,
 amount numeric(18,4) NOT NULL CHECK (amount>0 AND amount NOT IN ('NaN'::numeric,'Infinity'::numeric)),
 request_key text NOT NULL CHECK (request_key ~ '^[A-Za-z0-9_-]{8,128}$'),
 created_by uuid NOT NULL,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 audit_event_id bigint NOT NULL REFERENCES core10.canonical_audit_events_v1(id),
 UNIQUE (business_id,request_key),
 FOREIGN KEY (link_id,tenant_id,business_id)
  REFERENCES core10.finance_arap_links_v1(id,tenant_id,business_id),
 FOREIGN KEY (payment_journal_id,tenant_id,business_id)
  REFERENCES core10.finance_journals_v1(id,tenant_id,business_id)
);
CREATE INDEX finance_arap_alloc_doc_idx ON core10.finance_arap_allocations_v1(link_id);
CREATE INDEX finance_arap_alloc_payment_idx ON core10.finance_arap_allocations_v1(payment_journal_id);
ALTER TABLE core10.finance_arap_links_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE core10.finance_arap_allocations_v1 ENABLE ROW LEVEL SECURITY;
CREATE POLICY finance_arap_link_read_v1 ON core10.finance_arap_links_v1
 FOR SELECT TO authenticated USING(core10.can_see_business(tenant_id,business_id));
CREATE POLICY finance_arap_alloc_read_v1 ON core10.finance_arap_allocations_v1
 FOR SELECT TO authenticated USING(core10.can_see_business(tenant_id,business_id));
REVOKE ALL ON core10.finance_arap_links_v1,core10.finance_arap_allocations_v1 FROM PUBLIC,authenticated;
GRANT SELECT ON core10.finance_arap_links_v1,core10.finance_arap_allocations_v1 TO authenticated;

CREATE FUNCTION core10._finance_arap_immutable_v1() RETURNS trigger
 LANGUAGE plpgsql SET search_path=pg_catalog,core10 AS $body$
BEGIN RAISE EXCEPTION 'FIN_ARAP_IMMUTABLE'; END $body$;
CREATE TRIGGER finance_arap_links_immutable_v1 BEFORE UPDATE OR DELETE ON core10.finance_arap_links_v1
 FOR EACH ROW EXECUTE FUNCTION core10._finance_arap_immutable_v1();
CREATE TRIGGER finance_arap_links_no_truncate_v1 BEFORE TRUNCATE ON core10.finance_arap_links_v1
 FOR EACH STATEMENT EXECUTE FUNCTION core10._finance_arap_immutable_v1();
CREATE TRIGGER finance_arap_alloc_immutable_v1 BEFORE UPDATE OR DELETE ON core10.finance_arap_allocations_v1
 FOR EACH ROW EXECUTE FUNCTION core10._finance_arap_immutable_v1();
CREATE TRIGGER finance_arap_alloc_no_truncate_v1 BEFORE TRUNCATE ON core10.finance_arap_allocations_v1
 FOR EACH STATEMENT EXECUTE FUNCTION core10._finance_arap_immutable_v1();
REVOKE EXECUTE ON FUNCTION core10._finance_arap_immutable_v1() FROM PUBLIC,authenticated;

-- Read-only derived amount from canonical posted journal lines; not a balance store.
CREATE FUNCTION core10._finance_arap_net_v1(
 p_journal bigint,p_account bigint,p_expected_side text
) RETURNS numeric LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $body$
 SELECT coalesce(sum(CASE WHEN l.side=p_expected_side THEN l.amount ELSE -l.amount END),0)
 FROM core10.finance_journal_lines_v1 l
 WHERE l.journal_id=p_journal AND l.account_id=p_account
$body$;
REVOKE ALL ON FUNCTION core10._finance_arap_net_v1(bigint,bigint,text) FROM PUBLIC,authenticated;

-- Existing-posted-journal linking only. Never claims a Sales/Purchase invoice was posted.
CREATE FUNCTION core10.finance_link_open_item_v1(
 p_journal bigint,p_party bigint,p_account bigint,p_kind text,p_due_on date,p_key text
) RETURNS bigint LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $body$
DECLARE j core10.finance_journals_v1%ROWTYPE; p core10.master_parties_v1%ROWTYPE;
 a core10.finance_accounts_v1%ROWTYPE; v_actor uuid:=core10.actor_uid();
 prev core10.finance_arap_links_v1%ROWTYPE; v_id bigint; v_audit bigint; v_side text; v_amount numeric;
BEGIN
 SELECT * INTO j FROM core10.finance_journals_v1 WHERE id=p_journal FOR UPDATE;
 IF NOT FOUND OR v_actor IS NULL OR NOT core10.can_manage(j.tenant_id,j.business_id)
 THEN RAISE EXCEPTION 'FIN_ARAP_AUTH_DENIED'; END IF;
 PERFORM core10.control_check_v1(j.business_id,'finance.arap_link',j.site_id);
 IF p_kind IS NULL OR p_kind NOT IN ('ar','ap') OR p_due_on IS NULL
 OR p_due_on<j.effective_on OR p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{8,128}$'
 THEN RAISE EXCEPTION 'FIN_ARAP_INVALID_INPUT'; END IF;
 IF j.status<>'posted' OR j.source_domain='finance_reversal'
 OR EXISTS(SELECT 1 FROM core10.finance_reversals_v1
           WHERE original_journal_id=j.id OR reversal_journal_id=j.id)
 THEN RAISE EXCEPTION 'FIN_ARAP_SOURCE_NOT_POSTED_OR_REVERSED'; END IF;

 SELECT * INTO prev FROM core10.finance_arap_links_v1 WHERE journal_id=j.id;
 IF FOUND THEN
  IF prev.request_key=p_key AND prev.created_by=v_actor AND prev.party_id=p_party
  AND prev.account_id=p_account AND prev.kind=p_kind AND prev.due_on=p_due_on
  THEN RETURN prev.id; END IF;
  RAISE EXCEPTION 'FIN_ARAP_ALREADY_LINKED';
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('core10.finance:arap-link:'||j.business_id||':'||p_key,0));
 IF EXISTS(SELECT 1 FROM core10.finance_arap_links_v1
           WHERE business_id=j.business_id AND request_key=p_key)
 THEN RAISE EXCEPTION 'FIN_ARAP_KEY_CONFLICT'; END IF;
 SELECT * INTO p FROM core10.master_parties_v1
 WHERE id=p_party AND business_id=j.business_id AND tenant_id=j.tenant_id;
 IF NOT FOUND OR p.status<>'active' OR NOT
  ((p_kind='ar' AND p.party_kind IN ('customer','both'))
   OR (p_kind='ap' AND p.party_kind IN ('supplier','both')))
 THEN RAISE EXCEPTION 'FIN_ARAP_MASTER_PARTY_INVALID'; END IF;
 SELECT * INTO a FROM core10.finance_accounts_v1
 WHERE id=p_account AND business_id=j.business_id AND tenant_id=j.tenant_id;
 IF NOT FOUND OR NOT a.active OR a.currency<>j.currency OR a.legal_entity_id<>j.legal_entity_id
 OR (p_kind='ar' AND a.category<>'asset') OR (p_kind='ap' AND a.category<>'liability')
 THEN RAISE EXCEPTION 'FIN_ARAP_ACCOUNT_SCOPE'; END IF;
 v_side:=CASE WHEN p_kind='ar' THEN 'debit' ELSE 'credit' END;
 v_amount:=core10._finance_arap_net_v1(j.id,a.id,v_side);
 IF v_amount<=0 THEN RAISE EXCEPTION 'FIN_ARAP_CONTROL_LINE_MISSING'; END IF;
 v_audit:=core10._append_canonical_audit_v1(j.tenant_id,j.business_id,
   'finance','arap:journal:'||j.id||':link','finance.arap_link',v_actor,
   'finance:arap-link:'||j.business_id||':'||p_key,
   jsonb_build_object('journal_id',j.id,'party_id',p.id,'account_id',a.id,
     'kind',p_kind,'due_on',p_due_on,'opening_amount',v_amount));
 INSERT INTO core10.finance_arap_links_v1(
  tenant_id,business_id,kind,party_id,journal_id,account_id,due_on,request_key,created_by,audit_event_id)
 VALUES(j.tenant_id,j.business_id,p_kind,p.id,j.id,a.id,p_due_on,p_key,v_actor,v_audit)
 RETURNING id INTO v_id;
 RETURN v_id;
END $body$;

-- Allocation does not mutate money: payment must ALREADY be posted and balanced.
-- Lock BOTH journal rows in ID order to serialize competing payments and reversals.
CREATE FUNCTION core10.finance_allocate_payment_v1(
 p_link bigint,p_payment bigint,p_amount numeric,p_key text
) RETURNS bigint LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $body$
DECLARE l core10.finance_arap_links_v1%ROWTYPE; j core10.finance_journals_v1%ROWTYPE;
 pay core10.finance_journals_v1%ROWTYPE; v_actor uuid:=core10.actor_uid();
 v_existing core10.finance_arap_allocations_v1%ROWTYPE;
 v_doc_amount numeric; v_pay_amount numeric; v_doc_used numeric; v_pay_used numeric;
 v_account_side text; v_id bigint; v_audit bigint;
BEGIN
 SELECT * INTO l FROM core10.finance_arap_links_v1 WHERE id=p_link;
 IF NOT FOUND OR v_actor IS NULL OR NOT core10.can_manage(l.tenant_id,l.business_id)
 THEN RAISE EXCEPTION 'FIN_ARAP_AUTH_DENIED'; END IF;
 IF p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{8,128}$'
 OR p_amount IS NULL OR p_amount<=0 OR p_amount IN ('NaN'::numeric,'Infinity'::numeric)
 OR p_amount>99999999999999 OR scale(p_amount)>4
 THEN RAISE EXCEPTION 'FIN_ARAP_INVALID_AMOUNT_OR_KEY'; END IF;
 -- Locks must be acquired before reading budgets. A competing allocation to the
 -- same payment or original waits; a reversal of either also takes these locks.
 PERFORM 1 FROM core10.finance_journals_v1
 WHERE id IN(l.journal_id,p_payment) ORDER BY id FOR UPDATE;
 SELECT * INTO j FROM core10.finance_journals_v1 WHERE id=l.journal_id;
 SELECT * INTO pay FROM core10.finance_journals_v1 WHERE id=p_payment;
 PERFORM core10.control_check_v1(l.business_id,'finance.arap_allocate',pay.site_id);
 IF j.id IS NULL OR pay.id IS NULL OR j.status<>'posted' OR pay.status<>'posted'
 OR j.business_id<>l.business_id OR pay.business_id<>l.business_id
 OR j.tenant_id<>l.tenant_id OR pay.tenant_id<>l.tenant_id
 OR pay.id=j.id OR j.currency<>pay.currency OR j.legal_entity_id<>pay.legal_entity_id
 OR pay.effective_on<j.effective_on OR pay.source_domain='finance_reversal'
 OR EXISTS(SELECT 1 FROM core10.finance_reversals_v1 r
  WHERE r.original_journal_id IN(j.id,pay.id) OR r.reversal_journal_id IN(j.id,pay.id))
 THEN RAISE EXCEPTION 'FIN_ARAP_PAYMENT_SCOPE_OR_STATUS'; END IF;

 SELECT * INTO v_existing FROM core10.finance_arap_allocations_v1
  WHERE business_id=l.business_id AND request_key=p_key;
 IF FOUND THEN
  IF v_existing.link_id=l.id AND v_existing.payment_journal_id=pay.id
    AND v_existing.amount=p_amount AND v_existing.created_by=v_actor
  THEN RETURN v_existing.id; END IF;
  RAISE EXCEPTION 'FIN_ARAP_KEY_CONFLICT';
 END IF;
 -- Disallow a payment from being reused across different counterparties,
 -- AR/AP types or control accounts. Its actual amount remains in journal lines.
 IF EXISTS(SELECT 1 FROM core10.finance_arap_allocations_v1 alloc
 JOIN core10.finance_arap_links_v1 src ON src.id=alloc.link_id
 WHERE alloc.payment_journal_id=pay.id
  AND (src.party_id<>l.party_id OR src.kind<>l.kind OR src.account_id<>l.account_id))
 THEN RAISE EXCEPTION 'FIN_ARAP_PAYMENT_PARTY_OR_ACCOUNT_MISMATCH'; END IF;
 v_account_side:=CASE WHEN l.kind='ar' THEN 'debit' ELSE 'credit' END;
 v_doc_amount:=core10._finance_arap_net_v1(j.id,l.account_id,v_account_side);
 v_pay_amount:=core10._finance_arap_net_v1(pay.id,l.account_id,
  CASE WHEN l.kind='ar' THEN 'credit' ELSE 'debit' END);
 SELECT coalesce(sum(amount),0) INTO v_doc_used
  FROM core10.finance_arap_allocations_v1 WHERE link_id=l.id;
 SELECT coalesce(sum(amount),0) INTO v_pay_used
  FROM core10.finance_arap_allocations_v1 WHERE payment_journal_id=pay.id;
 IF v_doc_amount<=0 OR v_pay_amount<=0 OR v_doc_used+p_amount>v_doc_amount
 OR v_pay_used+p_amount>v_pay_amount THEN RAISE EXCEPTION 'FIN_ARAP_OVERALLOCATION'; END IF;

 v_audit:=core10._append_canonical_audit_v1(l.tenant_id,l.business_id,
   'finance','arap:allocation:'||p_key,'finance.arap_allocate',v_actor,
   'finance:arap-allocation:'||l.business_id||':'||p_key,
   jsonb_build_object('link_id',l.id,'original_journal',j.id,'payment_journal',pay.id,
      'account_id',l.account_id,'party_id',l.party_id,'amount',p_amount,'currency',j.currency));
 INSERT INTO core10.finance_arap_allocations_v1(
  tenant_id,business_id,link_id,payment_journal_id,amount,request_key,created_by,audit_event_id)
 VALUES(l.tenant_id,l.business_id,l.id,pay.id,p_amount,p_key,v_actor,v_audit)
 RETURNING id INTO v_id;
 RETURN v_id;
END $body$;

-- Aging derived as-of date from canonical posted journal/account lines,
-- immutable allocations and their POSTING dates. No stored mutable balances.
CREATE FUNCTION core10.finance_arap_aging_v1(
 p_business bigint,p_as_of date,p_kind text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $body$
DECLARE v_tenant bigint; v_rows jsonb;
BEGIN
 SELECT tenant_id INTO v_tenant FROM core10.businesses WHERE id=p_business;
 IF core10.actor_uid() IS NULL OR v_tenant IS NULL
 OR NOT core10.can_see_business(v_tenant,p_business)
 THEN RAISE EXCEPTION 'FIN_ARAP_READ_DENIED'; END IF;
 IF p_as_of IS NULL OR (p_kind IS NOT NULL AND p_kind NOT IN('ar','ap'))
 THEN RAISE EXCEPTION 'FIN_ARAP_BAD_REPORT_FILTER'; END IF;
 SELECT coalesce(jsonb_agg(x.r ORDER BY x.row_id),'[]'::jsonb) INTO v_rows
 FROM (
  SELECT l.id AS row_id,
    jsonb_build_object(
      'link_id',l.id,'kind',l.kind,'party_id',l.party_id,'party_code',party.code,
      'journal_id',l.journal_id,'source_domain',j.source_domain,'source_ref',j.source_ref,
      'currency',j.currency,'account_id',l.account_id,'due_on',l.due_on,
      'original_amount',core10._finance_arap_net_v1(j.id,l.account_id,
         CASE WHEN l.kind='ar' THEN 'debit' ELSE 'credit' END),
      'allocated_amount',coalesce(used.paid,0),
      'outstanding',CASE WHEN rev.original_journal_id IS NOT NULL THEN 0
        ELSE greatest(core10._finance_arap_net_v1(j.id,l.account_id,
         CASE WHEN l.kind='ar' THEN 'debit' ELSE 'credit' END)-coalesce(used.paid,0),0) END,
      'reversed',rev.original_journal_id IS NOT NULL,
      'days_overdue',greatest(p_as_of-l.due_on,0),
      'age_bucket',CASE WHEN p_as_of<=l.due_on THEN 'current'
          WHEN p_as_of-l.due_on<=30 THEN '1_30'
          WHEN p_as_of-l.due_on<=60 THEN '31_60'
          WHEN p_as_of-l.due_on<=90 THEN '61_90' ELSE '90_plus' END
    ) AS r
  FROM core10.finance_arap_links_v1 l
  JOIN core10.finance_journals_v1 j ON j.id=l.journal_id
  JOIN core10.master_parties_v1 party ON party.id=l.party_id
  LEFT JOIN core10.finance_reversals_v1 rev ON rev.original_journal_id=j.id
       AND rev.effective_on<=p_as_of
  LEFT JOIN LATERAL (
    SELECT sum(a.amount) AS paid FROM core10.finance_arap_allocations_v1 a
     JOIN core10.finance_journals_v1 pay ON pay.id=a.payment_journal_id
    WHERE a.link_id=l.id AND pay.effective_on<=p_as_of
  ) used ON true
  WHERE l.business_id=p_business AND j.effective_on<=p_as_of
    AND (p_kind IS NULL OR l.kind=p_kind)
 ) x;
 RETURN jsonb_build_object('business_id',p_business,'as_of',p_as_of,
   'kind',p_kind,'rows',v_rows);
END $body$;

INSERT INTO core10.control_rpc_map_v1
 (rpc_name,status,feature_key,reason,lane,board_row,test_ref) VALUES
 ('finance_link_open_item_v1','enforced','finance.arap_link',
  'Posted Money journal to NP02 Master party, Owner Control and canonical Audit',
  'ChatGPT','B-013','tests/migrations/np06-finance-arap-e2e.sql'),
 ('finance_allocate_payment_v1','enforced','finance.arap_allocate',
  'Posted journal allocation with dual-lock budgets, Owner Control and Audit',
  'ChatGPT','B-013','tests/migrations/np06-finance-arap-e2e.sql');

REVOKE ALL ON FUNCTION
 core10.finance_link_open_item_v1(bigint,bigint,bigint,text,date,text),
 core10.finance_allocate_payment_v1(bigint,bigint,numeric,text),
 core10.finance_arap_aging_v1(bigint,date,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION
 core10.finance_link_open_item_v1(bigint,bigint,bigint,text,date,text),
 core10.finance_allocate_payment_v1(bigint,bigint,numeric,text),
 core10.finance_arap_aging_v1(bigint,date,text) TO authenticated;
