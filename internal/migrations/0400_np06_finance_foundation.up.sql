-- NP06 / B-013 / 0400: canonical Money Port foundation (CoA + double-entry).
-- Depends on canonical Auth/Audit/Owner Control (0002..0012, 0100..0102).
-- Disposable PG17 candidate only. No hosted apply or parallel finance ledger.
DO $dep$ BEGIN
 IF to_regclass('core10.control_catalog_v1') IS NULL OR
    to_regclass('core10.canonical_audit_events_v1') IS NULL OR
    to_regprocedure('core10.control_check_v1(bigint,text,bigint)') IS NULL
 THEN RAISE EXCEPTION 'FIN_DEPENDENCY_NOT_CONNECTED'; END IF;
END $dep$;

INSERT INTO core10.control_catalog_v1
 (feature_key,title_en,title_bn,pack,default_enabled,default_stages,max_stages,
  allow_site_scope,approval_domain,approval_action,params) VALUES
 ('finance.coa','Manage chart of accounts','হিসাবের খাত পরিচালনা','NP06',true,0,0,false,NULL,NULL,'{}'),
 ('finance.journal_draft','Create journal drafts','জার্নাল খসড়া তৈরি','NP06',true,0,0,true,NULL,NULL,'{}'),
 ('finance.journal_validate','Validate balanced journals','সমন্বিত জার্নাল যাচাই','NP06',true,0,0,true,NULL,NULL,'{}'),
 ('finance.journal_post','Post journal to the canonical money ledger','ক্যাননিকাল অর্থ খতিয়ানে পোস্ট','NP06',true,1,5,true,'finance','post',
  '{"max_post_amount":{"type":"numeric","min":0,"max":1000000000000,"default":1000000}}'),
 ('finance.period_manage','Open or close accounting period','হিসাবকাল খোলা বা বন্ধ','NP06',true,0,0,false,NULL,NULL,'{}');

CREATE TABLE core10.finance_accounts_v1 (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL,
 business_id bigint NOT NULL,
 legal_entity_id bigint NOT NULL,
 code text NOT NULL CHECK(code ~ '^[A-Za-z0-9._-]{2,32}$'),
 name_en text NOT NULL CHECK(length(btrim(name_en)) BETWEEN 2 AND 120),
 name_bn text,
 category text NOT NULL CHECK(category IN('asset','liability','equity','income','expense')),
 parent_id bigint,
 currency text NOT NULL CHECK(currency ~ '^[A-Z]{3}$'),
 active boolean NOT NULL DEFAULT true,
 created_by uuid NOT NULL,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(id,tenant_id,business_id),
 UNIQUE(business_id,currency,code),
 CHECK(parent_id IS NULL OR parent_id<>id),
 FOREIGN KEY(business_id,tenant_id) REFERENCES core10.businesses(id,tenant_id),
 FOREIGN KEY(legal_entity_id,tenant_id) REFERENCES core10.legal_entities(id,tenant_id),
 FOREIGN KEY(parent_id,tenant_id,business_id) REFERENCES core10.finance_accounts_v1(id,tenant_id,business_id)
);
ALTER TABLE core10.finance_accounts_v1 ENABLE ROW LEVEL SECURITY;
CREATE POLICY finance_accounts_read_v1 ON core10.finance_accounts_v1 FOR SELECT TO authenticated
 USING(core10.can_see_business(tenant_id,business_id));
REVOKE ALL ON core10.finance_accounts_v1 FROM PUBLIC,authenticated;
GRANT SELECT ON core10.finance_accounts_v1 TO authenticated;

CREATE TABLE core10.finance_periods_v1 (
 tenant_id bigint NOT NULL,
 business_id bigint NOT NULL,
 currency text NOT NULL CHECK(currency ~ '^[A-Z]{3}$'),
 month_start date NOT NULL CHECK(month_start=date_trunc('month',month_start)::date),
 is_open boolean NOT NULL,
 changed_by uuid NOT NULL,
 changed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 audit_event_id bigint NOT NULL REFERENCES core10.canonical_audit_events_v1(id),
 PRIMARY KEY(business_id,currency,month_start),
 FOREIGN KEY(business_id,tenant_id) REFERENCES core10.businesses(id,tenant_id)
);
ALTER TABLE core10.finance_periods_v1 ENABLE ROW LEVEL SECURITY;
CREATE POLICY finance_periods_read_v1 ON core10.finance_periods_v1 FOR SELECT TO authenticated
 USING(core10.can_see_business(tenant_id,business_id));
REVOKE ALL ON core10.finance_periods_v1 FROM PUBLIC,authenticated;
GRANT SELECT ON core10.finance_periods_v1 TO authenticated;

CREATE TABLE core10.finance_journals_v1 (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL,
 business_id bigint NOT NULL,
 legal_entity_id bigint NOT NULL,
 site_id bigint,
 currency text NOT NULL CHECK(currency ~ '^[A-Z]{3}$'),
 effective_on date NOT NULL,
 source_domain text NOT NULL CHECK(source_domain ~ '^[a-z][a-z0-9_]{1,40}$'),
 source_ref text NOT NULL CHECK(length(btrim(source_ref)) BETWEEN 1 AND 100),
 draft_key text NOT NULL CHECK(draft_key ~ '^[A-Za-z0-9_-]{8,128}$'),
 payload_sha256 text NOT NULL CHECK(payload_sha256 ~ '^[0-9a-f]{64}$'),
 status text NOT NULL DEFAULT 'draft' CHECK(status IN('draft','validated','posted')),
 created_by uuid NOT NULL,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 validated_by uuid,
 validated_at timestamptz,
 posted_by uuid,
 posted_at timestamptz,
 post_key text CHECK(post_key ~ '^[A-Za-z0-9_-]{8,128}$'),
 audit_event_id bigint REFERENCES core10.canonical_audit_events_v1(id),
 UNIQUE(id,tenant_id,business_id),
 UNIQUE(business_id,draft_key),
 UNIQUE(business_id,source_domain,source_ref),
 FOREIGN KEY(business_id,tenant_id) REFERENCES core10.businesses(id,tenant_id),
 FOREIGN KEY(legal_entity_id,tenant_id) REFERENCES core10.legal_entities(id,tenant_id),
 FOREIGN KEY(site_id,tenant_id,business_id) REFERENCES core10.sites(id,tenant_id,business_id),
 CHECK(
   (status='draft' AND validated_by IS NULL AND validated_at IS NULL
      AND posted_by IS NULL AND posted_at IS NULL AND post_key IS NULL AND audit_event_id IS NULL)
   OR (status='validated' AND validated_by IS NOT NULL AND validated_at IS NOT NULL
      AND posted_by IS NULL AND posted_at IS NULL AND post_key IS NULL AND audit_event_id IS NULL)
   OR (status='posted' AND validated_by IS NOT NULL AND validated_at IS NOT NULL
      AND posted_by IS NOT NULL AND posted_at IS NOT NULL AND post_key IS NOT NULL AND audit_event_id IS NOT NULL)
 )
);
ALTER TABLE core10.finance_journals_v1 ENABLE ROW LEVEL SECURITY;
CREATE POLICY finance_journals_read_v1 ON core10.finance_journals_v1 FOR SELECT TO authenticated
 USING(core10.can_see_business(tenant_id,business_id));
REVOKE ALL ON core10.finance_journals_v1 FROM PUBLIC,authenticated;
GRANT SELECT ON core10.finance_journals_v1 TO authenticated;

CREATE TABLE core10.finance_journal_lines_v1 (
 journal_id bigint NOT NULL,
 tenant_id bigint NOT NULL,
 business_id bigint NOT NULL,
 line_no integer NOT NULL CHECK(line_no BETWEEN 1 AND 1000),
 account_id bigint NOT NULL,
 side text NOT NULL CHECK(side IN('debit','credit')),
 amount numeric(18,4) NOT NULL CHECK(amount>0),
 memo text,
 PRIMARY KEY(journal_id,line_no),
 FOREIGN KEY(journal_id,tenant_id,business_id)
  REFERENCES core10.finance_journals_v1(id,tenant_id,business_id),
 FOREIGN KEY(account_id,tenant_id,business_id)
  REFERENCES core10.finance_accounts_v1(id,tenant_id,business_id)
);
ALTER TABLE core10.finance_journal_lines_v1 ENABLE ROW LEVEL SECURITY;
CREATE POLICY finance_lines_read_v1 ON core10.finance_journal_lines_v1 FOR SELECT TO authenticated
 USING(core10.can_see_business(tenant_id,business_id));
REVOKE ALL ON core10.finance_journal_lines_v1 FROM PUBLIC,authenticated;
GRANT SELECT ON core10.finance_journal_lines_v1 TO authenticated;

-- A posted entry and *all* journal lines are immutable, including to accidental privileged DML.
CREATE FUNCTION core10._finance_journal_immutable_v1() RETURNS trigger
 LANGUAGE plpgsql SET search_path=pg_catalog,core10 AS $body$
BEGIN
 IF TG_OP='TRUNCATE' THEN RAISE EXCEPTION 'FIN_IMMUTABLE'; END IF;
 IF TG_TABLE_NAME='finance_journal_lines_v1' THEN
  RAISE EXCEPTION 'FIN_LINES_APPEND_ONLY';
 END IF;
 IF TG_OP='DELETE' OR OLD.status='posted' THEN RAISE EXCEPTION 'FIN_POSTED_IMMUTABLE'; END IF;
 IF TG_OP='UPDATE' AND (NEW.id<>OLD.id OR NEW.tenant_id<>OLD.tenant_id
   OR NEW.business_id<>OLD.business_id OR NEW.payload_sha256<>OLD.payload_sha256
   OR NEW.created_by<>OLD.created_by OR NEW.currency<>OLD.currency
   OR NEW.source_ref<>OLD.source_ref OR NEW.source_domain<>OLD.source_domain
   OR NEW.effective_on<>OLD.effective_on OR NEW.site_id IS DISTINCT FROM OLD.site_id
   OR NOT ((OLD.status='draft' AND NEW.status='validated')
    OR (OLD.status='validated' AND NEW.status='posted'))) THEN
  RAISE EXCEPTION 'FIN_JOURNAL_TRANSITION';
 END IF;
 RETURN NEW;
END $body$;
CREATE TRIGGER finance_journal_guard_v1 BEFORE UPDATE OR DELETE ON core10.finance_journals_v1
 FOR EACH ROW EXECUTE FUNCTION core10._finance_journal_immutable_v1();
CREATE TRIGGER finance_journal_truncate_v1 BEFORE TRUNCATE ON core10.finance_journals_v1
 FOR EACH STATEMENT EXECUTE FUNCTION core10._finance_journal_immutable_v1();
CREATE TRIGGER finance_lines_guard_v1 BEFORE UPDATE OR DELETE ON core10.finance_journal_lines_v1
 FOR EACH ROW EXECUTE FUNCTION core10._finance_journal_immutable_v1();
CREATE TRIGGER finance_lines_truncate_v1 BEFORE TRUNCATE ON core10.finance_journal_lines_v1
 FOR EACH STATEMENT EXECUTE FUNCTION core10._finance_journal_immutable_v1();
REVOKE EXECUTE ON FUNCTION core10._finance_journal_immutable_v1() FROM PUBLIC,authenticated;

-- Owner-only configuration; canonical Auth first, canonical Control second, canonical Audit third.
CREATE FUNCTION core10.finance_create_account_v1(
 p_business bigint,p_code text,p_name_en text,p_name_bn text,p_category text,
 p_parent bigint,p_currency text
) RETURNS bigint LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $body$
DECLARE b record; a record; v_id bigint; v_actor uuid:=core10.actor_uid();
BEGIN
 SELECT tenant_id,legal_entity_id INTO b FROM core10.businesses WHERE id=p_business;
 IF v_actor IS NULL OR b.tenant_id IS NULL OR NOT core10.can_manage(b.tenant_id,p_business)
 THEN RAISE EXCEPTION 'FIN_AUTH_DENIED'; END IF;
 PERFORM core10.control_check_v1(p_business,'finance.coa',NULL);
 IF p_parent IS NOT NULL THEN
  SELECT * INTO a FROM core10.finance_accounts_v1 WHERE id=p_parent AND business_id=p_business
   AND tenant_id=b.tenant_id;
  IF NOT FOUND OR NOT a.active OR a.currency IS DISTINCT FROM p_currency
     OR a.category IS DISTINCT FROM p_category THEN RAISE EXCEPTION 'FIN_PARENT_SCOPE_OR_TYPE'; END IF;
 END IF;
 INSERT INTO core10.finance_accounts_v1
  (tenant_id,business_id,legal_entity_id,code,name_en,name_bn,category,parent_id,currency,created_by)
 VALUES(b.tenant_id,p_business,b.legal_entity_id,p_code,p_name_en,p_name_bn,p_category,p_parent,p_currency,v_actor)
 RETURNING id INTO v_id;
 PERFORM core10._append_canonical_audit_v1(b.tenant_id,p_business,'finance','account:'||v_id||':create',
  'finance.coa_create',v_actor,'finance:account:'||v_id||':create',
  jsonb_build_object('account_id',v_id,'code',p_code,'category',p_category,'currency',p_currency));
 RETURN v_id;
END $body$;

CREATE FUNCTION core10.finance_set_account_active_v1(p_account bigint,p_active boolean)
RETURNS bigint LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $body$
DECLARE a core10.finance_accounts_v1%ROWTYPE; v_actor uuid:=core10.actor_uid(); v_ev bigint;
BEGIN
 SELECT * INTO a FROM core10.finance_accounts_v1 WHERE id=p_account FOR UPDATE;
 IF NOT FOUND OR v_actor IS NULL OR NOT core10.can_manage(a.tenant_id,a.business_id)
 THEN RAISE EXCEPTION 'FIN_AUTH_DENIED'; END IF;
 PERFORM core10.control_check_v1(a.business_id,'finance.coa',NULL);
 IF a.active=p_active THEN RETURN a.id; END IF;
 IF NOT p_active AND EXISTS(SELECT 1 FROM core10.finance_accounts_v1 WHERE parent_id=a.id AND active)
 THEN RAISE EXCEPTION 'FIN_ACTIVE_CHILD'; END IF;
 UPDATE core10.finance_accounts_v1 SET active=p_active WHERE id=a.id;
 SELECT count(*) INTO v_ev FROM core10.canonical_audit_events_v1
 WHERE business_id=a.business_id AND source_domain='finance' AND source_ref LIKE 'account:'||a.id||':state:%';
 PERFORM core10._append_canonical_audit_v1(a.tenant_id,a.business_id,'finance',
  'account:'||a.id||':state:'||(v_ev+1),'finance.coa_toggle',v_actor,
  'finance:account:'||a.id||':state:'||(v_ev+1),
  jsonb_build_object('account_id',a.id,'active',p_active));
 RETURN a.id;
END $body$;

CREATE FUNCTION core10.finance_set_period_v1(
 p_business bigint,p_currency text,p_month date,p_open boolean,p_key text
) RETURNS boolean LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $body$
DECLARE b record; v_actor uuid:=core10.actor_uid(); v_event bigint; v_old record;
BEGIN
 SELECT tenant_id INTO b FROM core10.businesses WHERE id=p_business;
 IF v_actor IS NULL OR b.tenant_id IS NULL OR NOT core10.can_manage(b.tenant_id,p_business)
 THEN RAISE EXCEPTION 'FIN_AUTH_DENIED'; END IF;
 PERFORM core10.control_check_v1(p_business,'finance.period_manage',NULL);
 IF p_month IS NULL OR p_month<>date_trunc('month',p_month)::date OR p_currency !~ '^[A-Z]{3}$'
   OR p_open IS NULL OR p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{8,128}$'
 THEN RAISE EXCEPTION 'FIN_INVALID_PERIOD'; END IF;
 SELECT * INTO v_old FROM core10.canonical_audit_events_v1
  WHERE business_id=p_business AND request_key='finance:period:'||p_key;
 IF FOUND THEN
  IF v_old.actor_id<>v_actor OR v_old.payload<>jsonb_build_object('month',p_month,'currency',p_currency,'open',p_open)
  THEN RAISE EXCEPTION 'FIN_IDEMPOTENCY_CONFLICT'; END IF;
  RETURN p_open;
 END IF;
 -- A close serializes behind any post that already holds a FOR SHARE period lock.
 SELECT is_open INTO v_old FROM core10.finance_periods_v1
 WHERE business_id=p_business AND currency=p_currency AND month_start=p_month FOR UPDATE;
 v_event:=core10._append_canonical_audit_v1(b.tenant_id,p_business,'finance',
  'period:'||p_key,'finance.period_change',v_actor,'finance:period:'||p_key,
  jsonb_build_object('month',p_month,'currency',p_currency,'open',p_open));
 INSERT INTO core10.finance_periods_v1
  (tenant_id,business_id,currency,month_start,is_open,changed_by,audit_event_id)
 VALUES(b.tenant_id,p_business,p_currency,p_month,p_open,v_actor,v_event)
 ON CONFLICT (business_id,currency,month_start) DO UPDATE SET
  is_open=EXCLUDED.is_open,changed_by=EXCLUDED.changed_by,
  changed_at=clock_timestamp(),audit_event_id=EXCLUDED.audit_event_id;
 RETURN p_open;
END $body$;

CREATE FUNCTION core10.finance_draft_journal_v1(
 p_business bigint,p_site bigint,p_currency text,p_date date,p_source text,p_ref text,
 p_key text,p_lines jsonb
) RETURNS bigint LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $body$
DECLARE b record; a record; line jsonb; v_actor uuid:=core10.actor_uid(); v_id bigint; prev record;
 v_hash text; n int:=0; amount numeric;
BEGIN
 SELECT tenant_id,legal_entity_id INTO b FROM core10.businesses WHERE id=p_business;
 IF v_actor IS NULL OR b.tenant_id IS NULL OR NOT core10.can_manage(b.tenant_id,p_business)
 THEN RAISE EXCEPTION 'FIN_AUTH_DENIED'; END IF;
 PERFORM core10.control_check_v1(p_business,'finance.journal_draft',p_site);
 IF p_site IS NOT NULL AND NOT EXISTS(SELECT 1 FROM core10.sites
   WHERE id=p_site AND business_id=p_business AND tenant_id=b.tenant_id) THEN
  RAISE EXCEPTION 'FIN_SITE_SCOPE'; END IF;
 IF p_date IS NULL OR p_currency IS NULL OR p_currency !~ '^[A-Z]{3}$'
  OR p_source IS NULL OR p_source !~ '^[a-z][a-z0-9_]{1,40}$'
  OR p_ref IS NULL OR length(btrim(p_ref)) NOT BETWEEN 1 AND 100
  OR p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{8,128}$'
  OR p_lines IS NULL OR jsonb_typeof(p_lines)<>'array'
  OR jsonb_array_length(p_lines) NOT BETWEEN 2 AND 1000
 THEN RAISE EXCEPTION 'FIN_INVALID_DRAFT'; END IF;
 v_hash:=encode(sha256(convert_to(jsonb_build_object(
  'business',p_business,'site',p_site,'currency',p_currency,'date',p_date,
  'source',p_source,'ref',p_ref,'lines',p_lines)::text,'UTF8')),'hex');
 -- Unique key arbitrates concurrent inserts; a conflicting payload never silently replays.
 INSERT INTO core10.finance_journals_v1
  (tenant_id,business_id,legal_entity_id,site_id,currency,effective_on,
   source_domain,source_ref,draft_key,payload_sha256,created_by)
 VALUES(b.tenant_id,p_business,b.legal_entity_id,p_site,p_currency,p_date,
   p_source,p_ref,p_key,v_hash,v_actor)
 ON CONFLICT(business_id,draft_key) DO NOTHING RETURNING id INTO v_id;
 IF v_id IS NULL THEN
  SELECT id,payload_sha256,created_by INTO prev FROM core10.finance_journals_v1
   WHERE business_id=p_business AND draft_key=p_key;
  IF NOT FOUND OR prev.payload_sha256<>v_hash OR prev.created_by<>v_actor
  THEN RAISE EXCEPTION 'FIN_IDEMPOTENCY_CONFLICT'; END IF;
  RETURN prev.id;
 END IF;
 FOR line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
  n:=n+1;
  IF jsonb_typeof(line)<>'object' OR jsonb_typeof(line->'account_id')<>'number'
   OR jsonb_typeof(line->'amount')<>'number' OR line->>'side' NOT IN('debit','credit')
   OR (line->>'account_id') !~ '^[0-9]+$'
  THEN RAISE EXCEPTION 'FIN_INVALID_LINE'; END IF;
  amount:=(line->>'amount')::numeric;
  IF amount<=0 OR amount>99999999999999 OR scale(amount)>4 THEN RAISE EXCEPTION 'FIN_INVALID_LINE_AMOUNT'; END IF;
  SELECT * INTO a FROM core10.finance_accounts_v1
   WHERE id=(line->>'account_id')::bigint AND tenant_id=b.tenant_id AND business_id=p_business;
  IF NOT FOUND OR NOT a.active OR a.currency<>p_currency OR a.legal_entity_id<>b.legal_entity_id
  THEN RAISE EXCEPTION 'FIN_ACCOUNT_SCOPE'; END IF;
  INSERT INTO core10.finance_journal_lines_v1
    (journal_id,tenant_id,business_id,line_no,account_id,side,amount,memo)
  VALUES(v_id,b.tenant_id,p_business,n,a.id,line->>'side',amount,line->>'memo');
 END LOOP;
 PERFORM core10._append_canonical_audit_v1(b.tenant_id,p_business,'finance',
  'journal:'||v_id||':draft','finance.journal_draft',v_actor,'finance:journal:'||v_id||':draft',
  jsonb_build_object('journal_id',v_id,'source',p_source,'source_ref',p_ref,'line_count',n));
 RETURN v_id;
END $body$;

CREATE FUNCTION core10.finance_validate_journal_v1(p_journal bigint)
RETURNS bigint LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $body$
DECLARE j core10.finance_journals_v1%ROWTYPE; v_actor uuid:=core10.actor_uid(); dr numeric; cr numeric;
BEGIN
 SELECT * INTO j FROM core10.finance_journals_v1 WHERE id=p_journal FOR UPDATE;
 IF NOT FOUND OR v_actor IS NULL OR NOT core10.can_manage(j.tenant_id,j.business_id)
 THEN RAISE EXCEPTION 'FIN_AUTH_DENIED'; END IF;
 PERFORM core10.control_check_v1(j.business_id,'finance.journal_validate',j.site_id);
 IF j.status='validated' THEN RETURN j.id; END IF;
 IF j.status<>'draft' THEN RAISE EXCEPTION 'FIN_INVALID_TRANSITION'; END IF;
 SELECT coalesce(sum(amount) FILTER(WHERE side='debit'),0),
        coalesce(sum(amount) FILTER(WHERE side='credit'),0)
 INTO dr,cr FROM core10.finance_journal_lines_v1 WHERE journal_id=j.id;
 IF dr<=0 OR dr<>cr THEN RAISE EXCEPTION 'FIN_UNBALANCED'; END IF;
 IF EXISTS(SELECT 1 FROM core10.finance_journal_lines_v1 l
  JOIN core10.finance_accounts_v1 a ON a.id=l.account_id
  WHERE l.journal_id=j.id AND (NOT a.active OR a.currency<>j.currency
    OR EXISTS(SELECT 1 FROM core10.finance_accounts_v1 child WHERE child.parent_id=a.id)))
 THEN RAISE EXCEPTION 'FIN_NONPOSTABLE_ACCOUNT'; END IF;
 UPDATE core10.finance_journals_v1 SET status='validated',validated_by=v_actor,
  validated_at=clock_timestamp() WHERE id=j.id;
 PERFORM core10._append_canonical_audit_v1(j.tenant_id,j.business_id,'finance',
   'journal:'||j.id||':validate','finance.journal_validate',v_actor,
   'finance:journal:'||j.id||':validate',jsonb_build_object('journal_id',j.id,'total',dr));
 RETURN j.id;
END $body$;

CREATE FUNCTION core10.finance_post_journal_v1(p_journal bigint,p_key text)
RETURNS bigint LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $body$
DECLARE j core10.finance_journals_v1%ROWTYPE; v_actor uuid:=core10.actor_uid(); c jsonb;
 v_dr numeric; v_cr numeric; v_open boolean; v_audit bigint;
BEGIN
 SELECT * INTO j FROM core10.finance_journals_v1 WHERE id=p_journal FOR UPDATE;
 IF NOT FOUND OR v_actor IS NULL OR NOT core10.can_manage(j.tenant_id,j.business_id)
 THEN RAISE EXCEPTION 'FIN_AUTH_DENIED'; END IF;
 IF p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{8,128}$' THEN RAISE EXCEPTION 'FIN_INVALID_KEY'; END IF;
 IF j.status='posted' THEN
  IF j.post_key=p_key AND j.posted_by=v_actor THEN RETURN j.id; END IF;
  RAISE EXCEPTION 'FIN_ALREADY_POSTED';
 END IF;
 c:=core10.control_check_v1(j.business_id,'finance.journal_post',j.site_id);
 IF (c->>'stages')::int>0 THEN
  -- Approval adapter is not connected: never self-approve or fabricate an approval receipt.
  RAISE EXCEPTION 'FIN_APPROVAL_NOT_CONNECTED';
 END IF;
 IF j.status<>'validated' THEN RAISE EXCEPTION 'FIN_NOT_VALIDATED'; END IF;
 SELECT coalesce(sum(amount) FILTER(WHERE side='debit'),0),
        coalesce(sum(amount) FILTER(WHERE side='credit'),0)
 INTO v_dr,v_cr FROM core10.finance_journal_lines_v1 WHERE journal_id=j.id;
 IF v_dr<=0 OR v_dr<>v_cr THEN RAISE EXCEPTION 'FIN_UNBALANCED'; END IF;
 IF v_dr>(c->'params'->>'max_post_amount')::numeric THEN RAISE EXCEPTION 'FIN_AMOUNT_LIMIT'; END IF;
 IF EXISTS(SELECT 1 FROM core10.finance_journal_lines_v1 l
  JOIN core10.finance_accounts_v1 a ON a.id=l.account_id
  WHERE l.journal_id=j.id AND (NOT a.active OR a.currency<>j.currency
   OR EXISTS(SELECT 1 FROM core10.finance_accounts_v1 ch WHERE ch.parent_id=a.id)))
 THEN RAISE EXCEPTION 'FIN_NONPOSTABLE_ACCOUNT'; END IF;
 -- FOR SHARE prevents racing close; missing/closed period is DENY, never implicit open.
 SELECT is_open INTO v_open FROM core10.finance_periods_v1
 WHERE business_id=j.business_id AND currency=j.currency
  AND month_start=date_trunc('month',j.effective_on)::date FOR SHARE;
 IF v_open IS DISTINCT FROM true THEN RAISE EXCEPTION 'FIN_PERIOD_CLOSED'; END IF;
 v_audit:=core10._append_canonical_audit_v1(j.tenant_id,j.business_id,'finance',
  'journal:'||j.id||':post','finance.journal_post',v_actor,'finance:journal:'||j.id||':post',
  jsonb_build_object('journal_id',j.id,'debit',v_dr,'credit',v_cr,
   'currency',j.currency,'effective_on',j.effective_on,'source',j.source_domain,'source_ref',j.source_ref));
 UPDATE core10.finance_journals_v1 SET status='posted',posted_by=v_actor,
  posted_at=clock_timestamp(),post_key=p_key,audit_event_id=v_audit WHERE id=j.id;
 RETURN j.id;
END $body$;

-- Registry gate must see each API-callable state-changing function and a real check call.
INSERT INTO core10.control_rpc_map_v1(rpc_name,status,feature_key,reason,lane,board_row) VALUES
 ('finance_create_account_v1','enforced','finance.coa','Owner-only COA creation checked by canonical control and audit','ChatGPT','B-013'),
 ('finance_set_account_active_v1','enforced','finance.coa','Owner-only account state checks canonical control and audit','ChatGPT','B-013'),
 ('finance_set_period_v1','enforced','finance.period_manage','Owner-only period transition checks canonical control and audit','ChatGPT','B-013'),
 ('finance_draft_journal_v1','enforced','finance.journal_draft','Scoped draft creation checks canonical control and audit','ChatGPT','B-013'),
 ('finance_validate_journal_v1','enforced','finance.journal_validate','Balanced validation checks canonical control and audit','ChatGPT','B-013'),
 ('finance_post_journal_v1','enforced','finance.journal_post','Posting checks canonical Owner Control, accounting period and audit','ChatGPT','B-013');

REVOKE EXECUTE ON FUNCTION
 core10.finance_create_account_v1(bigint,text,text,text,text,bigint,text),
 core10.finance_set_account_active_v1(bigint,boolean),
 core10.finance_set_period_v1(bigint,text,date,boolean,text),
 core10.finance_draft_journal_v1(bigint,bigint,text,date,text,text,text,jsonb),
 core10.finance_validate_journal_v1(bigint),
 core10.finance_post_journal_v1(bigint,text)
 FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION
 core10.finance_create_account_v1(bigint,text,text,text,text,bigint,text),
 core10.finance_set_account_active_v1(bigint,boolean),
 core10.finance_set_period_v1(bigint,text,date,boolean,text),
 core10.finance_draft_journal_v1(bigint,bigint,text,date,text,text,text,jsonb),
 core10.finance_validate_journal_v1(bigint),
 core10.finance_post_journal_v1(bigint,text)
 TO authenticated;
