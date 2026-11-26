-- CORE10 baseline20 v1; ordered, lossless consolidation. Fresh empty schema only.
-- CORE10 BASELINE SOURCE 0400_np06_finance_foundation.up.sql SHA256 f75421a45da7fc6c4fa1f8ad366f5ff824536d96e27bad244ee7e93cdf2e545b
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
DECLARE v_status text;
BEGIN
 IF TG_OP='TRUNCATE' THEN RAISE EXCEPTION 'FIN_IMMUTABLE'; END IF;
 IF TG_TABLE_NAME='finance_journal_lines_v1' THEN
  IF TG_OP='INSERT' THEN
   SELECT status INTO v_status FROM core10.finance_journals_v1
    WHERE id=NEW.journal_id FOR UPDATE;
   IF v_status IS DISTINCT FROM 'draft' THEN RAISE EXCEPTION 'FIN_LINES_FROZEN'; END IF;
   RETURN NEW;
  END IF;
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
CREATE TRIGGER finance_lines_guard_v1 BEFORE INSERT OR UPDATE OR DELETE ON core10.finance_journal_lines_v1
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
 IF p_month IS NULL OR p_month<>date_trunc('month',p_month)::date OR p_currency IS NULL OR p_currency !~ '^[A-Z]{3}$'
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
  'period:'||left(p_key,112),'finance.period_change',v_actor,'finance:period:'||p_key,
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
INSERT INTO core10.control_rpc_map_v1(rpc_name,status,feature_key,reason,lane,board_row,test_ref) VALUES
 ('finance_create_account_v1','enforced','finance.coa','Owner-only COA creation checked by canonical control and audit','ChatGPT','B-013','tests/migrations/np06-finance-e2e.sql'),
 ('finance_set_account_active_v1','enforced','finance.coa','Owner-only account state checks canonical control and audit','ChatGPT','B-013','tests/migrations/np06-finance-e2e.sql'),
 ('finance_set_period_v1','enforced','finance.period_manage','Owner-only period transition checks canonical control and audit','ChatGPT','B-013','tests/migrations/np06-finance-e2e.sql'),
 ('finance_draft_journal_v1','enforced','finance.journal_draft','Scoped draft creation checks canonical control and audit','ChatGPT','B-013','tests/migrations/np06-finance-e2e.sql'),
 ('finance_validate_journal_v1','enforced','finance.journal_validate','Balanced validation checks canonical control and audit','ChatGPT','B-013','tests/migrations/np06-finance-e2e.sql'),
 ('finance_post_journal_v1','enforced','finance.journal_post','Posting checks canonical Owner Control, accounting period and audit','ChatGPT','B-013','tests/migrations/np06-finance-e2e.sql');

REVOKE EXECUTE ON FUNCTION
 core10.finance_create_account_v1(bigint,text,text,text,text,bigint,text),
 core10.finance_set_account_active_v1(bigint,boolean),
 core10.finance_set_period_v1(bigint,text,date,boolean,text),
 core10.finance_draft_journal_v1(bigint,bigint,text,date,text,text,text,jsonb),
 core10.finance_validate_journal_v1(bigint),
 core10.finance_post_journal_v1(bigint,text)
 FROM PUBLIC;
GRANT EXECUTE ON FUNCTION
 core10.finance_create_account_v1(bigint,text,text,text,text,bigint,text),
 core10.finance_set_account_active_v1(bigint,boolean),
 core10.finance_set_period_v1(bigint,text,date,boolean,text),
 core10.finance_draft_journal_v1(bigint,bigint,text,date,text,text,text,jsonb),
 core10.finance_validate_journal_v1(bigint),
 core10.finance_post_journal_v1(bigint,text)
 TO authenticated;
INSERT INTO core10.schema_migrations(version,name,checksum) VALUES(400,'0400_np06_finance_foundation','f75421a45da7fc6c4fa1f8ad366f5ff824536d96e27bad244ee7e93cdf2e545b');

-- CORE10 BASELINE SOURCE 0401_np06_journal_reversal.up.sql SHA256 3b43edd804e76ee901755585336f1df2dc8fd8fc164debcc51acce9d453ec399
-- NP06/B-013/0401: immutable, source-linked reversal on the SINGLE canonical Finance journal.
-- No alternate balance, approval, audit, stock or permission engine. No hosted apply.
-- Reversals are a new equal-and-opposite posted journal in an explicitly open period.
-- Depends on 0400. Default Owner Control for reversal is OFF; posting still fails
-- closed for nonzero approval stages until the canonical GOV-002 adapter exists.
DO $dep$ BEGIN
 IF to_regclass('core10.finance_journals_v1') IS NULL
   OR to_regprocedure('core10.finance_post_journal_v1(bigint,text)') IS NULL
 THEN RAISE EXCEPTION 'FIN_REVERSAL_DEPENDENCY_NOT_CONNECTED'; END IF;
END $dep$;

INSERT INTO core10.control_catalog_v1
 (feature_key,title_en,title_bn,pack,default_enabled,default_stages,max_stages,
  allow_site_scope,approval_domain,approval_action,params) VALUES
 ('finance.journal_reverse','Reverse a posted Finance journal','পোস্টকৃত জার্নাল বিপরীত এন্ট্রি','NP06',
  false,0,0,true,NULL,NULL,'{}');

CREATE TABLE core10.finance_reversals_v1 (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL,
 business_id bigint NOT NULL,
 original_journal_id bigint NOT NULL UNIQUE,
 reversal_journal_id bigint NOT NULL UNIQUE,
 effective_on date NOT NULL,
 reason_code text NOT NULL CHECK(reason_code ~ '^[a-z][a-z0-9_]{2,40}$'),
 request_key text NOT NULL CHECK(request_key ~ '^[A-Za-z0-9_-]{8,128}$'),
 created_by uuid NOT NULL,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 audit_event_id bigint NOT NULL REFERENCES core10.canonical_audit_events_v1(id),
 UNIQUE(business_id,request_key),
 FOREIGN KEY(original_journal_id,tenant_id,business_id)
  REFERENCES core10.finance_journals_v1(id,tenant_id,business_id),
 FOREIGN KEY(reversal_journal_id,tenant_id,business_id)
  REFERENCES core10.finance_journals_v1(id,tenant_id,business_id)
);
ALTER TABLE core10.finance_reversals_v1 ENABLE ROW LEVEL SECURITY;
CREATE POLICY finance_reversals_read_v1 ON core10.finance_reversals_v1 FOR SELECT TO authenticated
 USING(core10.can_see_business(tenant_id,business_id));
REVOKE ALL ON core10.finance_reversals_v1 FROM PUBLIC,authenticated;
GRANT SELECT ON core10.finance_reversals_v1 TO authenticated;

-- Reversal evidence cannot be modified, deleted or truncated even by accidental
-- privileged SQL; correction must be a new, separately governed transaction.
CREATE FUNCTION core10._finance_reversal_immutable_v1() RETURNS trigger
 LANGUAGE plpgsql SET search_path=pg_catalog,core10 AS $body$
BEGIN
 RAISE EXCEPTION 'FIN_REVERSAL_IMMUTABLE';
END $body$;
CREATE TRIGGER finance_reversals_update_delete_guard_v1
 BEFORE UPDATE OR DELETE ON core10.finance_reversals_v1
 FOR EACH ROW EXECUTE FUNCTION core10._finance_reversal_immutable_v1();
CREATE TRIGGER finance_reversals_truncate_guard_v1
 BEFORE TRUNCATE ON core10.finance_reversals_v1
 FOR EACH STATEMENT EXECUTE FUNCTION core10._finance_reversal_immutable_v1();
REVOKE EXECUTE ON FUNCTION core10._finance_reversal_immutable_v1() FROM PUBLIC,authenticated;

CREATE FUNCTION core10.finance_reverse_posted_journal_v1(
 p_original bigint,p_effective_on date,p_reason text,p_key text
) RETURNS bigint LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,core10 AS $body$
DECLARE
 j core10.finance_journals_v1%ROWTYPE;
 prior record;
 v_actor uuid:=core10.actor_uid();
 v_pre_tenant bigint;
 v_pre_business bigint;
 v_lines jsonb;
 v_reverse bigint;
 v_receipt bigint;
 v_draft_key text;
 v_post_key text;
BEGIN
 -- SECURITY DEFINER must not let an unauthorized caller row-lock a foreign
 -- tenant's posted journal. Read only its scope WITHOUT acquiring any lock,
 -- check canonical Auth, then take the serialization lock and REVALIDATE.
 IF v_actor IS NULL THEN RAISE EXCEPTION 'FIN_AUTH_DENIED'; END IF;
 SELECT tenant_id,business_id INTO v_pre_tenant,v_pre_business
 FROM core10.finance_journals_v1 WHERE id=p_original;
 IF NOT FOUND OR NOT core10.can_manage(v_pre_tenant,v_pre_business)
 THEN RAISE EXCEPTION 'FIN_AUTH_DENIED'; END IF;

 -- The authorized row lock serializes concurrent reversals on one source.
 -- A row changed or moved between the read and lock must fail closed even
 -- though 0400 already prevents such changes to a posted journal.
 SELECT * INTO j FROM core10.finance_journals_v1 WHERE id=p_original FOR UPDATE;
 IF NOT FOUND OR j.tenant_id IS DISTINCT FROM v_pre_tenant
 OR j.business_id IS DISTINCT FROM v_pre_business
 OR NOT core10.can_manage(j.tenant_id,j.business_id)
 THEN RAISE EXCEPTION 'FIN_AUTH_DENIED'; END IF;
 -- Intentional: check live Owner Control BEFORE any idempotency replay.
 -- A disabled switch must reject even exact-key retries of an old reversal.
 -- The Owner's reversal switch is independent of the existing draft,
 -- validation, post and period checks, all of which remain mandatory.
 PERFORM core10.control_check_v1(j.business_id,'finance.journal_reverse',j.site_id);
 IF p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{8,128}$'
   OR p_reason IS NULL OR p_reason !~ '^[a-z][a-z0-9_]{2,40}$'
   OR p_effective_on IS NULL
 THEN RAISE EXCEPTION 'FIN_REVERSAL_INVALID_INPUT'; END IF;
 IF j.status<>'posted' OR j.audit_event_id IS NULL
 THEN RAISE EXCEPTION 'FIN_REVERSAL_REQUIRES_POSTED'; END IF;
 IF j.source_domain='finance_reversal' OR EXISTS
   (SELECT 1 FROM core10.finance_reversals_v1 WHERE reversal_journal_id=j.id)
 THEN RAISE EXCEPTION 'FIN_REVERSAL_CHAIN_DENIED'; END IF;

 SELECT r.original_journal_id,r.reversal_journal_id,r.effective_on,r.reason_code,
        r.request_key,r.created_by INTO prior
 FROM core10.finance_reversals_v1 r WHERE r.original_journal_id=j.id;
 IF FOUND THEN
  IF prior.request_key=p_key AND prior.reason_code=p_reason
     AND prior.effective_on=p_effective_on AND prior.created_by=v_actor
  THEN RETURN prior.reversal_journal_id; END IF;
  RAISE EXCEPTION 'FIN_ALREADY_REVERSED';
 END IF;
 IF EXISTS (SELECT 1 FROM core10.finance_reversals_v1 r
            WHERE r.business_id=j.business_id AND r.request_key=p_key)
 THEN RAISE EXCEPTION 'FIN_IDEMPOTENCY_CONFLICT'; END IF;
 IF p_effective_on<j.effective_on THEN RAISE EXCEPTION 'FIN_REVERSAL_BACKDATE'; END IF;
 SELECT jsonb_agg(jsonb_build_object(
   'account_id',l.account_id,
   'side',CASE WHEN l.side='debit' THEN 'credit' ELSE 'debit' END,
   'amount',l.amount,
   'memo','Reversal of journal '||j.id||' line '||l.line_no
  ) ORDER BY l.line_no)
 INTO v_lines FROM core10.finance_journal_lines_v1 l WHERE l.journal_id=j.id;
 IF v_lines IS NULL OR jsonb_array_length(v_lines)<2
 THEN RAISE EXCEPTION 'FIN_REVERSAL_LINES_MISSING'; END IF;

 -- Reuse the canonical Money port end to end: account/scope checks, balanced
 -- validation, Owner Control, GOV-002 fail-closed stages, max amount, period
 -- lock and canonical immutable audit receipt. Any denial rolls back the
 -- draft + validation + post as one database transaction.
 v_draft_key:=encode(sha256(convert_to('finance:reversal:draft:'||j.business_id||':'||j.id||':'||p_key,'UTF8')),'hex');
 v_post_key:=encode(sha256(convert_to('finance:reversal:post:'||j.business_id||':'||j.id||':'||p_key,'UTF8')),'hex');
 v_reverse:=core10.finance_draft_journal_v1(
   j.business_id,j.site_id,j.currency,p_effective_on,
   'finance_reversal','journal-'||j.id,v_draft_key,v_lines);
 PERFORM core10.finance_validate_journal_v1(v_reverse);
 PERFORM core10.finance_post_journal_v1(v_reverse,v_post_key);
 v_receipt:=core10._append_canonical_audit_v1(
   j.tenant_id,j.business_id,'finance','journal:'||j.id||':reverse',
   'finance.journal_reverse',v_actor,'finance:journal:'||j.id||':reverse',
   jsonb_build_object('original_journal_id',j.id,'reversal_journal_id',v_reverse,
    'effective_on',p_effective_on,'reason_code',p_reason,'request_key',p_key));
 INSERT INTO core10.finance_reversals_v1(
   tenant_id,business_id,original_journal_id,reversal_journal_id,
   effective_on,reason_code,request_key,created_by,audit_event_id)
 VALUES(j.tenant_id,j.business_id,j.id,v_reverse,p_effective_on,
   p_reason,p_key,v_actor,v_receipt);
 RETURN v_reverse;
END $body$;

INSERT INTO core10.control_rpc_map_v1
 (rpc_name,status,feature_key,reason,lane,board_row,test_ref)
 VALUES('finance_reverse_posted_journal_v1','enforced','finance.journal_reverse',
 'Owner-only reversal switch plus canonical draft/validate/post and immutable audit',
 'ChatGPT','B-013','tests/migrations/np06-finance-reversal-e2e.sql');

REVOKE EXECUTE ON FUNCTION
 core10.finance_reverse_posted_journal_v1(bigint,date,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION
 core10.finance_reverse_posted_journal_v1(bigint,date,text,text) TO authenticated;
INSERT INTO core10.schema_migrations(version,name,checksum) VALUES(401,'0401_np06_journal_reversal','3b43edd804e76ee901755585336f1df2dc8fd8fc164debcc51acce9d453ec399');

-- CORE10 BASELINE SOURCE 0402_np06_arap_links_allocations.up.sql SHA256 b9e8309b501b40d6b7eba772c0714d9556335861941a33b8bae715d41eccfcc6
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
 -- Untrusted journal IDs never acquire foreign-tenant or business row locks.
 -- Read scope without locking and verify active Owner authority before a wait.
 SELECT * INTO j FROM core10.finance_journals_v1 WHERE id=p_journal;
 IF NOT FOUND OR v_actor IS NULL OR NOT core10.can_manage(j.tenant_id,j.business_id)
 THEN RAISE EXCEPTION 'FIN_ARAP_AUTH_DENIED'; END IF;
 -- Lock only the authorized scope, then revalidate membership after the wait.
 SELECT * INTO j FROM core10.finance_journals_v1
  WHERE id=p_journal AND tenant_id=j.tenant_id AND business_id=j.business_id FOR UPDATE;
 IF NOT FOUND OR NOT core10.can_manage(j.tenant_id,j.business_id)
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
 -- Payment ID is untrusted. A foreign payment must fail before any row lock.
 IF NOT EXISTS (SELECT 1 FROM core10.finance_journals_v1
    WHERE id=p_payment AND tenant_id=l.tenant_id AND business_id=l.business_id)
 THEN RAISE EXCEPTION 'FIN_ARAP_PAYMENT_SCOPE_OR_STATUS'; END IF;
 -- Lock only same-scope journals in deterministic ID order, then refresh scope,
 -- membership and Control after the wait; protect reversal and allocation races.
 PERFORM 1 FROM core10.finance_journals_v1
  WHERE id IN(l.journal_id,p_payment)
    AND tenant_id=l.tenant_id AND business_id=l.business_id
  ORDER BY id FOR UPDATE;
 SELECT * INTO l FROM core10.finance_arap_links_v1
  WHERE id=p_link AND tenant_id=l.tenant_id AND business_id=l.business_id;
 IF NOT FOUND OR v_actor IS NULL OR NOT core10.can_manage(l.tenant_id,l.business_id)
 THEN RAISE EXCEPTION 'FIN_ARAP_AUTH_DENIED'; END IF;
 SELECT * INTO j FROM core10.finance_journals_v1
  WHERE id=l.journal_id AND tenant_id=l.tenant_id AND business_id=l.business_id;
 SELECT * INTO pay FROM core10.finance_journals_v1
  WHERE id=p_payment AND tenant_id=l.tenant_id AND business_id=l.business_id;
 IF j.id IS NULL OR pay.id IS NULL
 THEN RAISE EXCEPTION 'FIN_ARAP_PAYMENT_SCOPE_OR_STATUS'; END IF;
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

-- Do not expose writes while 0402 is installed without the 0403
-- source/settlement/reversal integrity triggers (migration failure window).
-- 0403 opens the two mutation APIs only after those guards are installed.
REVOKE ALL ON FUNCTION
 core10.finance_link_open_item_v1(bigint,bigint,bigint,text,date,text),
 core10.finance_allocate_payment_v1(bigint,bigint,numeric,text),
 core10.finance_arap_aging_v1(bigint,date,text) FROM PUBLIC,authenticated;
GRANT EXECUTE ON FUNCTION core10.finance_arap_aging_v1(bigint,date,text) TO authenticated;
INSERT INTO core10.schema_migrations(version,name,checksum) VALUES(402,'0402_np06_arap_links_allocations','b9e8309b501b40d6b7eba772c0714d9556335861941a33b8bae715d41eccfcc6');

-- CORE10 BASELINE SOURCE 0403_np06_arap_trace_integrity.up.sql SHA256 06110bd6ad0faf33d6cf5568e453961a87619debd42ee50ce7841f5abb587d80
-- NP06/B-013 0403: F3 integrity contracts layered on the unmodified 0402 migration.
-- Zero new money/party balances; no other builder's migration is changed.
-- Manual posted journals can be linked as manual evidence. An external invoice/bill
-- cannot be called verified until canonical source adapters provide attestation.
DO $dep$ BEGIN
 IF to_regclass('core10.finance_arap_links_v1') IS NULL
 OR to_regclass('core10.finance_arap_allocations_v1') IS NULL
 OR to_regclass('core10.finance_reversals_v1') IS NULL
 THEN RAISE EXCEPTION 'FIN_ARAP_INTEGRITY_DEPENDENCY_NOT_CONNECTED'; END IF;
END $dep$;

CREATE FUNCTION core10._finance_arap_source_integrity_v1()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,core10 AS $body$
DECLARE j core10.finance_journals_v1%ROWTYPE;
BEGIN
 SELECT * INTO j FROM core10.finance_journals_v1 WHERE id=NEW.journal_id;
 IF NOT FOUND OR j.status<>'posted' OR j.tenant_id<>NEW.tenant_id
  OR j.business_id<>NEW.business_id
 THEN RAISE EXCEPTION 'FIN_ARAP_SOURCE_NOT_POSTED'; END IF;

 -- Existing Money post only proves that this journal was posted; it does NOT
 -- attest an upstream Sales invoice or Purchase bill. No invented integration.
 -- Only explicit Owner-governed manual evidence can be linked until real
 -- read-only canonical source validation adapters are delivered.
 IF j.source_domain<>'manual'
 THEN RAISE EXCEPTION 'FIN_ARAP_EXTERNAL_SOURCE_NOT_ATTESTED'; END IF;
 RETURN NEW;
END $body$;

CREATE TRIGGER finance_arap_source_integrity_v1
 BEFORE INSERT ON core10.finance_arap_links_v1 FOR EACH ROW
 EXECUTE FUNCTION core10._finance_arap_source_integrity_v1();

CREATE FUNCTION core10._finance_arap_reversal_allocation_guard_v1()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,core10 AS $body$
BEGIN
 -- An allocated invoice/bill or an allocated payment cannot be reversed through
 -- 0401 until an explicit canonical deallocation/reconciliation adapter exists.
 -- Raising here rolls back the new reversal journal AND its Audit in one txn.
 IF EXISTS(
  SELECT 1 FROM core10.finance_arap_allocations_v1 a
  JOIN core10.finance_arap_links_v1 l ON l.id=a.link_id
  WHERE l.journal_id=NEW.original_journal_id
     OR a.payment_journal_id=NEW.original_journal_id
 ) THEN RAISE EXCEPTION 'FIN_ARAP_ALLOCATED_REVERSAL_NOT_CONNECTED'; END IF;
 RETURN NEW;
END $body$;

CREATE TRIGGER finance_arap_no_allocated_reversal_v1
 BEFORE INSERT ON core10.finance_reversals_v1 FOR EACH ROW
 EXECUTE FUNCTION core10._finance_arap_reversal_allocation_guard_v1();

-- A manually posted AR/AP settlement needs a positive asset counterpart.
-- "asset" is structural COA evidence, NOT signed bank/receipt authenticity;
-- genuine bank collection/disbursement adapters remain fail-closed/deferred.
CREATE FUNCTION core10._finance_arap_settlement_integrity_v1()
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
 IF pay.source_domain<>'manual'
 THEN RAISE EXCEPTION 'FIN_ARAP_PAYMENT_SOURCE_NOT_ATTESTED'; END IF;

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

CREATE TRIGGER finance_arap_settlement_integrity_v1
 BEFORE INSERT ON core10.finance_arap_allocations_v1 FOR EACH ROW
 EXECUTE FUNCTION core10._finance_arap_settlement_integrity_v1();

-- Audit/source trace is derived from the SAME posted Money journal (both sides)
-- and the canonical NP02 party. It is NOT an invoice/bill mirror or posting API.
CREATE FUNCTION core10.finance_arap_trace_v1(p_link bigint)
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
   'payment_provenance','manual_asset_counterpart_not_bank_attested',
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
  'document_provenance','manual_posted_journal_not_external_invoice_attested',
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

REVOKE EXECUTE ON FUNCTION
 core10._finance_arap_source_integrity_v1(),
 core10._finance_arap_reversal_allocation_guard_v1(),
 core10._finance_arap_settlement_integrity_v1(),
 core10.finance_arap_trace_v1(bigint) FROM PUBLIC,authenticated;
GRANT EXECUTE ON FUNCTION core10.finance_arap_trace_v1(bigint) TO authenticated;

-- 0402 leaves writes closed. Only the completed 0403 integrity guard set
-- authorizes these public mutation RPCs; both checks and Audit stay canonical.
GRANT EXECUTE ON FUNCTION
 core10.finance_link_open_item_v1(bigint,bigint,bigint,text,date,text),
 core10.finance_allocate_payment_v1(bigint,bigint,numeric,text) TO authenticated;
INSERT INTO core10.schema_migrations(version,name,checksum) VALUES(403,'0403_np06_arap_trace_integrity','06110bd6ad0faf33d6cf5568e453961a87619debd42ee50ce7841f5abb587d80');
