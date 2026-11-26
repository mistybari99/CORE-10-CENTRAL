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
