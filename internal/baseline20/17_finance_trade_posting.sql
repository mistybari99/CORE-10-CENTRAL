-- CORE10 baseline20 v1; ordered, lossless consolidation. Fresh empty schema only.
-- CORE10 BASELINE SOURCE 0404_np06_arap_trade_control.up.sql SHA256 90d21de4621a6cbec4327905799117e976f6ed3b9edd626ceec85acb10dcf888
-- NP06/B-013/0404: explicit Owner designation of trade AR/AP control accounts.
-- Forward-only hardening: preserves 0400–0403 migration byte-for-byte.
-- Generic asset/liability classification alone does NOT authorize trade AR/AP.
-- No duplicate ledger, customer/supplier register or mutable balance is created.
DO $dep$ BEGIN
 IF to_regclass('core10.finance_arap_links_v1') IS NULL
 OR to_regclass('core10.finance_accounts_v1') IS NULL
 OR to_regprocedure('core10._finance_arap_immutable_v1()') IS NULL
 THEN RAISE EXCEPTION 'FIN_ARAP_TRADE_CONTROL_DEPENDENCY_NOT_CONNECTED'; END IF;
END $dep$;

INSERT INTO core10.control_catalog_v1
 (feature_key,title_en,title_bn,pack,default_enabled,default_stages,max_stages,
  allow_site_scope,approval_domain,approval_action,params) VALUES
 ('finance.arap_control_account','Designate a trade AR/AP control account',
  'ট্রেড পাওনা/দেনার কন্ট্রোল হিসাব নির্ধারণ',
  'NP06',false,0,0,false,NULL,NULL,'{}');

-- One immutable, audited Owner designation per existing CoA account.
-- Classification is an explicit business policy, not an assumption from category.
CREATE TABLE core10.finance_arap_control_accounts_v1(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL,
 business_id bigint NOT NULL,
 account_id bigint NOT NULL,
 kind text NOT NULL CHECK(kind IN('ar','ap')),
 request_key text NOT NULL CHECK(request_key ~ '^[A-Za-z0-9_-]{8,128}$'),
 created_by uuid NOT NULL,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 audit_event_id bigint NOT NULL REFERENCES core10.canonical_audit_events_v1(id),
 UNIQUE (business_id,account_id),
 UNIQUE (business_id,request_key),
 FOREIGN KEY (account_id,tenant_id,business_id)
  REFERENCES core10.finance_accounts_v1(id,tenant_id,business_id)
);
ALTER TABLE core10.finance_arap_control_accounts_v1 ENABLE ROW LEVEL SECURITY;
CREATE POLICY finance_arap_control_read_v1 ON core10.finance_arap_control_accounts_v1
 FOR SELECT TO authenticated USING(core10.can_see_business(tenant_id,business_id));
REVOKE ALL ON core10.finance_arap_control_accounts_v1 FROM PUBLIC,authenticated;
GRANT SELECT ON core10.finance_arap_control_accounts_v1 TO authenticated;
CREATE TRIGGER finance_arap_control_immutable_v1
 BEFORE UPDATE OR DELETE ON core10.finance_arap_control_accounts_v1
 FOR EACH ROW EXECUTE FUNCTION core10._finance_arap_immutable_v1();
CREATE TRIGGER finance_arap_control_no_truncate_v1
 BEFORE TRUNCATE ON core10.finance_arap_control_accounts_v1
 FOR EACH STATEMENT EXECUTE FUNCTION core10._finance_arap_immutable_v1();

CREATE FUNCTION core10.finance_register_arap_control_account_v1(
 p_account bigint,p_kind text,p_key text
) RETURNS bigint LANGUAGE plpgsql VOLATILE SECURITY DEFINER
 SET search_path=pg_catalog,core10 AS $body$
DECLARE a core10.finance_accounts_v1%ROWTYPE;
 v_actor uuid:=core10.actor_uid();
 prev core10.finance_arap_control_accounts_v1%ROWTYPE;
 v_id bigint; v_audit bigint;
BEGIN
 -- Check Owner scope BEFORE any untrusted account row lock.
 SELECT * INTO a FROM core10.finance_accounts_v1 WHERE id=p_account;
 IF NOT FOUND OR v_actor IS NULL OR NOT core10.can_manage(a.tenant_id,a.business_id)
 THEN RAISE EXCEPTION 'FIN_ARAP_CONTROL_AUTH_DENIED'; END IF;
 SELECT * INTO a FROM core10.finance_accounts_v1
  WHERE id=p_account AND tenant_id=a.tenant_id AND business_id=a.business_id FOR UPDATE;
 IF NOT FOUND OR NOT core10.can_manage(a.tenant_id,a.business_id)
 THEN RAISE EXCEPTION 'FIN_ARAP_CONTROL_AUTH_DENIED'; END IF;
 PERFORM core10.control_check_v1(a.business_id,'finance.arap_control_account',NULL);
 IF p_kind IS NULL OR p_kind NOT IN ('ar','ap') OR p_key IS NULL
 OR p_key !~ '^[A-Za-z0-9_-]{8,128}$'
 THEN RAISE EXCEPTION 'FIN_ARAP_CONTROL_BAD_REQUEST'; END IF;
 IF NOT a.active
 OR (p_kind='ar' AND a.category<>'asset')
 OR (p_kind='ap' AND a.category<>'liability')
 THEN RAISE EXCEPTION 'FIN_ARAP_CONTROL_CATEGORY_INVALID'; END IF;
 -- Serialize concurrent use of one request key even across distinct accounts.
 PERFORM pg_advisory_xact_lock(hashtextextended(
  'core10.finance:arap-account:'||a.business_id||':'||p_key,0));
 SELECT * INTO prev FROM core10.finance_arap_control_accounts_v1
  WHERE business_id=a.business_id AND request_key=p_key;
 IF FOUND THEN
  IF prev.account_id=a.id AND prev.kind=p_kind AND prev.created_by=v_actor
  THEN RETURN prev.id; END IF;
  RAISE EXCEPTION 'FIN_ARAP_CONTROL_KEY_CONFLICT';
 END IF;
 SELECT * INTO prev FROM core10.finance_arap_control_accounts_v1
  WHERE business_id=a.business_id AND account_id=a.id;
 IF FOUND THEN RAISE EXCEPTION 'FIN_ARAP_CONTROL_ACCOUNT_ALREADY_DESIGNATED'; END IF;
 v_audit:=core10._append_canonical_audit_v1(
  a.tenant_id,a.business_id,'finance','arap-control:account:'||a.id||':register',
  'finance.arap_control_account',v_actor,
  'finance:arap-control:'||a.business_id||':'||p_key,
  jsonb_build_object('account_id',a.id,'kind',p_kind,'currency',a.currency,
   'legal_entity_id',a.legal_entity_id,'category',a.category));
 INSERT INTO core10.finance_arap_control_accounts_v1(
  tenant_id,business_id,account_id,kind,request_key,created_by,audit_event_id
 ) VALUES(a.tenant_id,a.business_id,a.id,p_kind,p_key,v_actor,v_audit)
 RETURNING id INTO v_id;
 RETURN v_id;
END $body$;
REVOKE EXECUTE ON FUNCTION core10.finance_register_arap_control_account_v1(bigint,text,text)
 FROM PUBLIC,authenticated;
GRANT EXECUTE ON FUNCTION core10.finance_register_arap_control_account_v1(bigint,text,text)
 TO authenticated;

-- Cannot create a trade open item against an undesignated generic bank, cash,
-- asset, tax or liability account. Exact currency/legal entity remain checked
-- by 0402; this INSERT trigger is a second fail-closed server-side fence.
CREATE FUNCTION core10._finance_arap_trade_control_guard_v1()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,core10 AS $body$
BEGIN
 IF NOT EXISTS (
  SELECT 1 FROM core10.finance_arap_control_accounts_v1 m
  JOIN core10.finance_accounts_v1 a
    ON a.id=m.account_id AND a.tenant_id=m.tenant_id
    AND a.business_id=m.business_id
  WHERE m.account_id=NEW.account_id AND m.tenant_id=NEW.tenant_id
    AND m.business_id=NEW.business_id AND m.kind=NEW.kind
    AND a.active
    AND ((NEW.kind='ar' AND a.category='asset')
      OR (NEW.kind='ap' AND a.category='liability'))
 ) THEN
  RAISE EXCEPTION 'FIN_ARAP_TRADE_CONTROL_NOT_DESIGNATED';
 END IF;
 RETURN NEW;
END $body$;
CREATE TRIGGER finance_arap_trade_control_guard_v1
 BEFORE INSERT ON core10.finance_arap_links_v1
 FOR EACH ROW EXECUTE FUNCTION core10._finance_arap_trade_control_guard_v1();
REVOKE EXECUTE ON FUNCTION core10._finance_arap_trade_control_guard_v1()
 FROM PUBLIC,authenticated;

INSERT INTO core10.control_rpc_map_v1
 (rpc_name,status,feature_key,reason,lane,board_row,test_ref) VALUES
 ('finance_register_arap_control_account_v1','enforced','finance.arap_control_account',
  'Only explicitly Owner-designated, audited trade control accounts may back AR/AP links',
  'ChatGPT','B-013','tests/migrations/np06-finance-arap-e2e.sql');
INSERT INTO core10.schema_migrations(version,name,checksum) VALUES(404,'0404_np06_arap_trade_control','90d21de4621a6cbec4327905799117e976f6ed3b9edd626ceec85acb10dcf888');

-- CORE10 BASELINE SOURCE 0405_np06_finance_gov002_post.up.sql SHA256 5562641a0724912c69d8b15f0ce1c5cf649d875b2e246f513cd31092ac52afc7
-- NP06/B-013 0405: canonical GOV002 completion -> ONE posted Finance journal.
-- Existing 0400 two-arg post remains fail-closed at nonzero stages.
-- Owner-governed MANUAL journals only; never attest invoices, bills or banking.
DO $dep$ BEGIN
 IF to_regprocedure('core10.verify_approval_binding_v1(bigint,bigint,text,text,text,bigint,jsonb)') IS NULL
 OR to_regprocedure('core10.submit_typed_approval_v1(bigint,text,text,text,bigint,jsonb,text)') IS NULL
 OR to_regclass('core10.approval_stage_receipts_v1') IS NULL
 OR to_regclass('core10.finance_journals_v1') IS NULL
 THEN RAISE EXCEPTION 'FIN_GOV002_CANONICAL_DEPENDENCY_NOT_CONNECTED'; END IF;
END $dep$;

-- Same server-calculated payload on submission and posting. Validated lines,
-- source, currency and business are already immutable via 0400 trigger.
CREATE FUNCTION core10._finance_post_approval_payload_v1(p_journal bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER
 SET search_path=pg_catalog,core10 AS $body$
 SELECT jsonb_build_object('journal_id',j.id,'business_id',j.business_id,
  'site_id',j.site_id,'currency',j.currency,'unit',j.currency,
  'amount',coalesce((SELECT sum(l.amount)
      FROM core10.finance_journal_lines_v1 l
      WHERE l.journal_id=j.id AND l.side='debit'),0),
  'effective_on',j.effective_on,'source_domain',j.source_domain,
  'source_ref',j.source_ref,'payload_sha256',j.payload_sha256)
 FROM core10.finance_journals_v1 j WHERE j.id=p_journal;
$body$;
REVOKE ALL ON FUNCTION core10._finance_post_approval_payload_v1(bigint)
 FROM PUBLIC,authenticated;

CREATE FUNCTION core10.finance_request_post_approval_v1(
 p_journal bigint,p_key text
) RETURNS bigint LANGUAGE plpgsql VOLATILE SECURITY DEFINER
 SET search_path=pg_catalog,core10 AS $body$
DECLARE j core10.finance_journals_v1%ROWTYPE;
 v_actor uuid:=core10.actor_uid();v_tenant bigint;v_business bigint;
 c jsonb;v_dr numeric;v_cr numeric;v_open boolean;v_route text[];
BEGIN
 -- Authorize before locking an untrusted journal, then revalidate after lock.
 SELECT tenant_id,business_id INTO v_tenant,v_business
 FROM core10.finance_journals_v1 WHERE id=p_journal;
 IF v_actor IS NULL OR v_tenant IS NULL
 OR NOT core10.can_manage(v_tenant,v_business)
 THEN RAISE EXCEPTION 'FIN_AUTH_DENIED'; END IF;
 SELECT * INTO j FROM core10.finance_journals_v1
 WHERE id=p_journal AND tenant_id=v_tenant AND business_id=v_business FOR UPDATE;
 IF NOT FOUND OR NOT core10.can_manage(j.tenant_id,j.business_id)
 THEN RAISE EXCEPTION 'FIN_AUTH_DENIED'; END IF;
 c:=core10.control_check_v1(j.business_id,'finance.journal_post',j.site_id);
 PERFORM core10.control_check_v1(j.business_id,'gov002.review',NULL);
 IF (c->>'stages')::integer<1 THEN RAISE EXCEPTION 'FIN_APPROVAL_STAGES_REQUIRED'; END IF;
 IF p_key IS NULL OR p_key !~ '^[A-Za-z0-9_-]{8,128}$'
 THEN RAISE EXCEPTION 'FIN_INVALID_KEY'; END IF;
 IF j.status<>'validated' THEN RAISE EXCEPTION 'FIN_NOT_VALIDATED'; END IF;
 IF j.source_domain<>'manual' THEN RAISE EXCEPTION 'FIN_APPROVAL_SOURCE_NOT_ATTESTED'; END IF;
 IF j.created_by<>v_actor THEN RAISE EXCEPTION 'FIN_APPROVAL_MAKER_DENIED'; END IF;
 SELECT coalesce(sum(amount) FILTER(WHERE side='debit'),0),
        coalesce(sum(amount) FILTER(WHERE side='credit'),0)
 INTO v_dr,v_cr FROM core10.finance_journal_lines_v1 WHERE journal_id=j.id;
 IF v_dr<=0 OR v_dr<>v_cr THEN RAISE EXCEPTION 'FIN_UNBALANCED'; END IF;
 IF v_dr>(c->'params'->>'max_post_amount')::numeric
 THEN RAISE EXCEPTION 'FIN_AMOUNT_LIMIT'; END IF;
 IF EXISTS(SELECT 1 FROM core10.finance_journal_lines_v1 l
 JOIN core10.finance_accounts_v1 a ON a.id=l.account_id
 WHERE l.journal_id=j.id AND (NOT a.active OR a.currency<>j.currency
 OR a.legal_entity_id<>j.legal_entity_id
 OR EXISTS(SELECT 1 FROM core10.finance_accounts_v1 ch WHERE ch.parent_id=a.id)))
 THEN RAISE EXCEPTION 'FIN_NONPOSTABLE_ACCOUNT'; END IF;
 SELECT is_open INTO v_open FROM core10.finance_periods_v1
 WHERE business_id=j.business_id AND currency=j.currency
 AND month_start=date_trunc('month',j.effective_on)::date FOR SHARE;
 IF v_open IS DISTINCT FROM true THEN RAISE EXCEPTION 'FIN_PERIOD_CLOSED'; END IF;
 -- Current finance stages must match exact canonical approval route.
 -- Only the legacy genuine one-checker route may be unconfigured.
 SELECT r.stages INTO v_route FROM core10.approval_routes_v1 r
 JOIN core10.approval_policy_versions_v1 p ON p.id=r.policy_id
 WHERE p.business_id=j.business_id AND p.tenant_id=j.tenant_id
 AND p.domain='finance' AND p.action_code='post'
 ORDER BY p.version DESC LIMIT 1;
 IF (v_route IS NULL AND (c->>'stages')::integer<>1)
 OR (v_route IS NOT NULL AND cardinality(v_route)<>(c->>'stages')::integer)
 THEN RAISE EXCEPTION 'FIN_APPROVAL_ROUTE_MISMATCH'; END IF;
 RETURN core10.submit_typed_approval_v1(
  j.business_id,'finance','post','finance:journal:'||j.id||':post',1,
  core10._finance_post_approval_payload_v1(j.id),p_key);
END $body$;

CREATE FUNCTION core10.finance_post_approved_journal_v1(
 p_journal bigint,p_post_key text,p_approval bigint
) RETURNS bigint LANGUAGE plpgsql VOLATILE SECURITY DEFINER
 SET search_path=pg_catalog,core10 AS $body$
DECLARE j core10.finance_journals_v1%ROWTYPE;
 v_actor uuid:=core10.actor_uid();v_tenant bigint;v_business bigint;
 c jsonb;v_dr numeric;v_cr numeric;v_open boolean;
 q core10.approval_requests%ROWTYPE;v_route text[];v_stage_count integer;
 v_count integer;v_final_event bigint;v_binding bigint;v_audit bigint;v_audit_payload jsonb;
BEGIN
 SELECT tenant_id,business_id INTO v_tenant,v_business
 FROM core10.finance_journals_v1 WHERE id=p_journal;
 IF v_actor IS NULL OR v_tenant IS NULL
 OR NOT core10.can_manage(v_tenant,v_business)
 THEN RAISE EXCEPTION 'FIN_AUTH_DENIED'; END IF;
 SELECT * INTO j FROM core10.finance_journals_v1
 WHERE id=p_journal AND tenant_id=v_tenant AND business_id=v_business FOR UPDATE;
 IF NOT FOUND OR NOT core10.can_manage(j.tenant_id,j.business_id)
 THEN RAISE EXCEPTION 'FIN_AUTH_DENIED'; END IF;
 -- Owner switches are checked BEFORE any idempotent posted replay.
 c:=core10.control_check_v1(j.business_id,'finance.journal_post',j.site_id);
 PERFORM core10.control_check_v1(j.business_id,'gov002.review',NULL);
 IF (c->>'stages')::integer<1 THEN RAISE EXCEPTION 'FIN_APPROVAL_STAGES_REQUIRED'; END IF;
 IF p_post_key IS NULL OR p_post_key !~ '^[A-Za-z0-9_-]{8,128}$'
 OR p_approval IS NULL THEN RAISE EXCEPTION 'FIN_INVALID_KEY'; END IF;
 IF j.status='posted' THEN
  SELECT payload INTO v_audit_payload FROM core10.canonical_audit_events_v1
   WHERE id=j.audit_event_id AND business_id=j.business_id
   AND action='finance.journal_post';
  IF j.post_key=p_post_key AND j.posted_by=v_actor
  AND v_audit_payload->>'approval_request_id'=p_approval::text
  THEN RETURN j.id; END IF;
  RAISE EXCEPTION 'FIN_ALREADY_POSTED';
 END IF;
 IF j.status<>'validated' THEN RAISE EXCEPTION 'FIN_NOT_VALIDATED'; END IF;
 IF j.source_domain<>'manual' THEN RAISE EXCEPTION 'FIN_APPROVAL_SOURCE_NOT_ATTESTED'; END IF;
 -- Scope without lock; then require same original maker and request business.
 SELECT * INTO q FROM core10.approval_requests WHERE id=p_approval;
 IF NOT FOUND OR q.tenant_id<>j.tenant_id OR q.business_id<>j.business_id
 OR q.created_by<>j.created_by THEN RAISE EXCEPTION 'FIN_APPROVAL_REQUEST_SCOPE'; END IF;
 SELECT * INTO q FROM core10.approval_requests
 WHERE id=p_approval AND tenant_id=j.tenant_id AND business_id=j.business_id
 AND created_by=j.created_by FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'FIN_APPROVAL_REQUEST_SCOPE'; END IF;
 IF q.status<>'approved' OR q.decided_by IS NULL OR q.decided_by=q.created_by
 THEN RAISE EXCEPTION 'FIN_APPROVAL_NOT_EFFECTIVE'; END IF;
 v_stage_count:=(c->>'stages')::integer;
 SELECT stages INTO v_route FROM core10.approval_routes_v1
 WHERE policy_id=q.policy_id_v1 AND tenant_id=j.tenant_id AND business_id=j.business_id;
 IF (v_route IS NULL AND v_stage_count<>1)
 OR (v_route IS NOT NULL AND cardinality(v_route)<>v_stage_count)
 OR ((to_jsonb(q)->>'route_stages_pinned_v1') IS NOT NULL
     AND (to_jsonb(q)->>'route_stages_pinned_v1')::integer<>v_stage_count)
 THEN RAISE EXCEPTION 'FIN_APPROVAL_ROUTE_MISMATCH'; END IF;
 IF v_route IS NULL THEN
  SELECT count(*),max(id) INTO v_count,v_final_event
  FROM core10.approval_events WHERE request_id=q.id
   AND action='approve' AND actor_id<>q.created_by;
  IF v_count<>1 OR NOT EXISTS(
   SELECT 1 FROM core10.approval_events WHERE id=v_final_event
   AND request_id=q.id AND actor_id=q.decided_by
  ) THEN RAISE EXCEPTION 'FIN_APPROVAL_RECEIPTS_INCOMPLETE'; END IF;
 ELSE
  SELECT count(*),max(event_id) FILTER(WHERE stage_no=v_stage_count)
  INTO v_count,v_final_event FROM core10.approval_stage_receipts_v1
  WHERE request_id=q.id AND tenant_id=j.tenant_id AND business_id=j.business_id;
  IF v_count<>v_stage_count OR v_final_event IS NULL OR NOT EXISTS(
   SELECT 1 FROM core10.approval_events
   WHERE id=v_final_event AND request_id=q.id
   AND action='approve' AND actor_id=q.decided_by
  ) THEN RAISE EXCEPTION 'FIN_APPROVAL_RECEIPTS_INCOMPLETE'; END IF;
 END IF;
 SELECT coalesce(sum(amount) FILTER(WHERE side='debit'),0),
        coalesce(sum(amount) FILTER(WHERE side='credit'),0)
 INTO v_dr,v_cr FROM core10.finance_journal_lines_v1 WHERE journal_id=j.id;
 IF v_dr<=0 OR v_dr<>v_cr THEN RAISE EXCEPTION 'FIN_UNBALANCED'; END IF;
 IF v_dr>(c->'params'->>'max_post_amount')::numeric
 THEN RAISE EXCEPTION 'FIN_AMOUNT_LIMIT'; END IF;
 IF EXISTS(SELECT 1 FROM core10.finance_journal_lines_v1 l
 JOIN core10.finance_accounts_v1 a ON a.id=l.account_id
 WHERE l.journal_id=j.id AND (NOT a.active OR a.currency<>j.currency
 OR a.legal_entity_id<>j.legal_entity_id
 OR EXISTS(SELECT 1 FROM core10.finance_accounts_v1 ch WHERE ch.parent_id=a.id)))
 THEN RAISE EXCEPTION 'FIN_NONPOSTABLE_ACCOUNT'; END IF;
 SELECT is_open INTO v_open FROM core10.finance_periods_v1
 WHERE business_id=j.business_id AND currency=j.currency
 AND month_start=date_trunc('month',j.effective_on)::date FOR SHARE;
 IF v_open IS DISTINCT FROM true THEN RAISE EXCEPTION 'FIN_PERIOD_CLOSED'; END IF;
 -- Canonical verification binds effective approval to the CURRENT, frozen
 -- journal payload and returns a real canonical Approval event.
 v_binding:=core10.verify_approval_binding_v1(q.id,j.business_id,'finance','post',
  'finance:journal:'||j.id||':post',1,
  core10._finance_post_approval_payload_v1(j.id));
 v_audit:=core10._append_canonical_audit_v1(j.tenant_id,j.business_id,
  'finance','journal:'||j.id||':post','finance.journal_post',v_actor,
  'finance:journal:'||j.id||':post',
  jsonb_build_object('journal_id',j.id,'debit',v_dr,'credit',v_cr,
    'currency',j.currency,'effective_on',j.effective_on,'source',j.source_domain,
    'source_ref',j.source_ref,'approval_request_id',q.id,
    'approval_policy_id',q.policy_id_v1,'approval_policy_version',q.policy_version_v1,
    'approval_binding_event_id',v_binding,'approval_final_event_id',v_final_event,
    'approval_stage_count',v_stage_count));
 UPDATE core10.finance_journals_v1 SET status='posted',posted_by=v_actor,
 posted_at=clock_timestamp(),post_key=p_post_key,audit_event_id=v_audit WHERE id=j.id;
 RETURN j.id;
END $body$;

REVOKE EXECUTE ON FUNCTION
 core10.finance_request_post_approval_v1(bigint,text),
 core10.finance_post_approved_journal_v1(bigint,text,bigint)
 FROM PUBLIC,authenticated;
GRANT EXECUTE ON FUNCTION
 core10.finance_request_post_approval_v1(bigint,text),
 core10.finance_post_approved_journal_v1(bigint,text,bigint) TO authenticated;
INSERT INTO core10.control_rpc_map_v1
 (rpc_name,status,feature_key,reason,lane,board_row,test_ref) VALUES
 ('finance_request_post_approval_v1','enforced','finance.journal_post',
  'Scoped Owner request, canonical GOV002 typed submission; no Finance posting',
  'ChatGPT','B-013','tests/migrations/np06-finance-approval-e2e.sql'),
 ('finance_post_approved_journal_v1','enforced','finance.journal_post',
  'Real stage receipts and bound live source required for canonical Money posting',
  'ChatGPT','B-013','tests/migrations/np06-finance-approval-e2e.sql');
INSERT INTO core10.schema_migrations(version,name,checksum) VALUES(405,'0405_np06_finance_gov002_post','5562641a0724912c69d8b15f0ce1c5cf649d875b2e246f513cd31092ac52afc7');
