-- C10-A042/A043 | FIRST REAL CONFIG SERVICE SLICE, DISPOSABLE c10_demo ONLY.
-- Apply AFTER A018/A020/A021. Never apply directly to historic IMG-ERP-SG.
-- A021/A034 remains authority: NO role grants, operational switches, ledger or stock writes here.
CREATE TABLE c10_demo.control_catalog_v1 (
 control_id text PRIMARY KEY CHECK (control_id ~ '^[a-z][a-z0-9]*(\.[a-z0-9_]+)+$'),
 display_group text NOT NULL
);
INSERT INTO c10_demo.control_catalog_v1(control_id,display_group) VALUES
 ('inventory.count','inventory'),('inventory.transfer','inventory'),
 ('sales.orders','sales'),('purchase.receiving','purchasing'),
 ('production.workflows','operations'),('projects.operations','operations'),
 ('finance.reports','finance'),('finance.payments','finance'),
 ('workforce.payroll','workforce'),('approvals.owner_queue','approvals'),
 ('approvals.delegation','approvals'),('data.export','data'),
 ('offline.drafts','offline'),('automation.events','automation'),
 ('integration.connectors','integration'),('ai.agent_proposals','automation'),
 ('ui.favorites','experience'),('alerts.notifications','notifications');

CREATE TABLE c10_demo.control_settings_v1 (
 tenant_id bigint NOT NULL,
 business_id bigint NOT NULL,
 control_id text NOT NULL REFERENCES c10_demo.control_catalog_v1(control_id),
 placement text NOT NULL CHECK (placement IN('central_only','business_only','both','hidden_from_menus')),
 local_edit_mode text NOT NULL CHECK (local_edit_mode IN('central_only','business_owner','request_approval')),
 preferred_enabled boolean NOT NULL DEFAULT false,
 version bigint NOT NULL DEFAULT 1 CHECK(version>0),
 changed_by uuid NOT NULL,
 changed_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(business_id,control_id),
 FOREIGN KEY(business_id,tenant_id) REFERENCES c10_demo.businesses(id,tenant_id),
 CHECK ((placement NOT IN('central_only','hidden_from_menus')) OR local_edit_mode='central_only')
);
CREATE TABLE c10_demo.control_setting_requests_v1 (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL,
 business_id bigint NOT NULL,
 control_id text NOT NULL REFERENCES c10_demo.control_catalog_v1(control_id),
 expected_version bigint NOT NULL CHECK(expected_version>=0),
 target_enabled boolean NOT NULL,
 requested_by uuid NOT NULL,
 reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 5 AND 500),
 status text NOT NULL DEFAULT 'pending' CHECK(status IN('pending','approved','rejected')),
 reviewed_by uuid,
 reviewed_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(business_id,tenant_id) REFERENCES c10_demo.businesses(id,tenant_id),
 CHECK((status='pending' AND reviewed_by IS NULL AND reviewed_at IS NULL)
    OR (status<>'pending' AND reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL))
);
CREATE TABLE c10_demo.control_write_receipts_v1(
 tenant_id bigint NOT NULL,
 business_id bigint NOT NULL,
 request_key text NOT NULL CHECK(length(request_key) BETWEEN 8 AND 100),
 actor_uid uuid NOT NULL,
 payload jsonb NOT NULL,
 result jsonb NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(business_id,request_key),
 FOREIGN KEY(business_id,tenant_id) REFERENCES c10_demo.businesses(id,tenant_id)
);
CREATE TABLE c10_demo.control_setting_audit_v1(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL,
 business_id bigint NOT NULL,
 control_id text NOT NULL,
 event text NOT NULL CHECK(event IN('updated','request_submitted','request_approved','request_rejected')),
 before_state jsonb,
 after_state jsonb,
 actor_uid uuid NOT NULL,
 request_key text NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(business_id,tenant_id) REFERENCES c10_demo.businesses(id,tenant_id)
);
-- Audit is append-only, even for privileged application paths.
CREATE FUNCTION c10_demo.control_audit_immutable_v1() RETURNS trigger
LANGUAGE plpgsql AS $$BEGIN RAISE EXCEPTION 'control_audit_immutable'; END$$;
CREATE TRIGGER control_audit_no_mutation_v1 BEFORE UPDATE OR DELETE OR TRUNCATE
ON c10_demo.control_setting_audit_v1
FOR EACH STATEMENT EXECUTE FUNCTION c10_demo.control_audit_immutable_v1();

ALTER TABLE c10_demo.control_catalog_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE c10_demo.control_settings_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE c10_demo.control_setting_requests_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE c10_demo.control_write_receipts_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE c10_demo.control_setting_audit_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON c10_demo.control_catalog_v1,c10_demo.control_settings_v1,
 c10_demo.control_setting_requests_v1,c10_demo.control_write_receipts_v1,
 c10_demo.control_setting_audit_v1 FROM PUBLIC,authenticated,anon;

-- Security definer is narrowly scoped, verified against DB membership EACH call.
-- Not a release substitute for actual signed GoTrue, session revocation and tenant backfill.
CREATE FUNCTION c10_demo.read_control_settings_v1(p_business bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE t bigint; result jsonb;
BEGIN
 SELECT tenant_id INTO t FROM c10_demo.businesses WHERE id=p_business;
 IF c10_demo.actor_uid() IS NULL OR t IS NULL OR NOT c10_demo.can_manage(t,p_business)
 THEN RAISE EXCEPTION 'control_read_denied'; END IF;
 SELECT jsonb_build_object(
  'tenant_id',t,'business_id',p_business,'server_authorized',true,
  'operationally_certified',false,
  'items',COALESCE(jsonb_agg(jsonb_build_object(
   'control_id',c.control_id,'group',c.display_group,
   'placement',COALESCE(s.placement,'central_only'),
   'local_edit_mode',COALESCE(s.local_edit_mode,'central_only'),
   'preferred_enabled',COALESCE(s.preferred_enabled,false),
   'version',COALESCE(s.version,0),'updated_at',s.changed_at,
   'audit_count',(SELECT count(*) FROM c10_demo.control_setting_audit_v1 a
      WHERE a.business_id=p_business AND a.control_id=c.control_id)
  ) ORDER BY c.control_id),'[]'::jsonb))
 INTO result
 FROM c10_demo.control_catalog_v1 c
 LEFT JOIN c10_demo.control_settings_v1 s
   ON s.business_id=p_business AND s.tenant_id=t AND s.control_id=c.control_id;
 RETURN result;
END$$;

CREATE FUNCTION c10_demo.write_control_setting_v1(
 p_business bigint,p_control text,p_placement text,p_local_edit text,
 p_enabled boolean,p_expected_version bigint,p_request text,p_reason text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE t bigint; v_before c10_demo.control_settings_v1%ROWTYPE;
 v_receipt c10_demo.control_write_receipts_v1%ROWTYPE; v_owner boolean;
 v_payload jsonb; v_result jsonb; v_version bigint; v_request_id bigint;
BEGIN
 IF c10_demo.actor_uid() IS NULL OR p_business IS NULL OR p_control IS NULL OR
  p_enabled IS NULL OR p_expected_version IS NULL OR p_expected_version<0 OR
  p_request IS NULL OR p_request !~ '^[A-Za-z0-9_-]{8,100}$' OR
  p_reason IS NULL OR length(btrim(p_reason)) NOT BETWEEN 5 AND 500 OR
  p_placement NOT IN('central_only','business_only','both','hidden_from_menus') OR
  p_placement IS NULL OR p_local_edit NOT IN('central_only','business_owner','request_approval') OR
  p_local_edit IS NULL OR
  (p_placement IN('central_only','hidden_from_menus') AND p_local_edit<>'central_only')
 THEN RAISE EXCEPTION 'invalid_control_write'; END IF;
 -- Serialize ALL writes per business, including exact-key retries and request decisions.
 SELECT tenant_id INTO t FROM c10_demo.businesses WHERE id=p_business FOR UPDATE;
 IF t IS NULL OR NOT c10_demo.can_manage(t,p_business)
 THEN RAISE EXCEPTION 'control_write_denied'; END IF;
 IF NOT EXISTS(SELECT 1 FROM c10_demo.control_catalog_v1 WHERE control_id=p_control)
 THEN RAISE EXCEPTION 'unknown_control'; END IF;
 v_owner:=c10_demo.can_tenant(t);
 v_payload:=jsonb_build_object('control',p_control,'placement',p_placement,
  'edit_mode',p_local_edit,'enabled',p_enabled,'expected',p_expected_version,'reason',btrim(p_reason));
 SELECT * INTO v_receipt FROM c10_demo.control_write_receipts_v1
  WHERE business_id=p_business AND request_key=p_request;
 IF FOUND THEN
  IF v_receipt.actor_uid<>c10_demo.actor_uid() OR v_receipt.payload<>v_payload
  THEN RAISE EXCEPTION 'control_idempotency_conflict'; END IF;
  RETURN v_receipt.result;
 END IF;
 SELECT * INTO v_before FROM c10_demo.control_settings_v1
  WHERE business_id=p_business AND control_id=p_control FOR UPDATE;
 v_version:=CASE WHEN FOUND THEN v_before.version ELSE 0 END;
 IF v_version<>p_expected_version THEN RAISE EXCEPTION 'control_stale_version'; END IF;
 IF NOT v_owner THEN
  IF v_version=0 OR p_placement<>v_before.placement OR p_local_edit<>v_before.local_edit_mode
  THEN RAISE EXCEPTION 'owner_controls_placement_only'; END IF;
  IF v_before.placement NOT IN('business_only','both') OR v_before.local_edit_mode='central_only'
  THEN RAISE EXCEPTION 'control_local_edit_denied'; END IF;
 END IF;
 IF NOT v_owner AND v_before.local_edit_mode='request_approval' THEN
  INSERT INTO c10_demo.control_setting_requests_v1(
   tenant_id,business_id,control_id,expected_version,target_enabled,requested_by,reason)
  VALUES(t,p_business,p_control,v_version,p_enabled,c10_demo.actor_uid(),btrim(p_reason))
  RETURNING id INTO v_request_id;
  v_result:=jsonb_build_object('status','pending','request_id',v_request_id,'version',v_version);
  INSERT INTO c10_demo.control_setting_audit_v1(tenant_id,business_id,control_id,event,
    before_state,after_state,actor_uid,request_key)
  VALUES(t,p_business,p_control,'request_submitted',to_jsonb(v_before),
    jsonb_build_object('target_enabled',p_enabled,'request_id',v_request_id),
    c10_demo.actor_uid(),p_request);
 ELSE
  INSERT INTO c10_demo.control_settings_v1(
   tenant_id,business_id,control_id,placement,local_edit_mode,preferred_enabled,version,changed_by)
  VALUES(t,p_business,p_control,p_placement,p_local_edit,p_enabled,v_version+1,c10_demo.actor_uid())
  ON CONFLICT(business_id,control_id) DO UPDATE SET
    placement=excluded.placement,local_edit_mode=excluded.local_edit_mode,
    preferred_enabled=excluded.preferred_enabled,version=excluded.version,
    changed_by=excluded.changed_by,changed_at=now();
  v_result:=jsonb_build_object('status','applied','version',v_version+1,'operationally_certified',false);
  INSERT INTO c10_demo.control_setting_audit_v1(tenant_id,business_id,control_id,event,
    before_state,after_state,actor_uid,request_key)
  VALUES(t,p_business,p_control,'updated',CASE WHEN v_version=0 THEN NULL ELSE to_jsonb(v_before) END,
    jsonb_build_object('preferred_enabled',p_enabled,'placement',p_placement,
      'local_edit_mode',p_local_edit,'version',v_version+1),
    c10_demo.actor_uid(),p_request);
 END IF;
 INSERT INTO c10_demo.control_write_receipts_v1(
   tenant_id,business_id,request_key,actor_uid,payload,result)
 VALUES(t,p_business,p_request,c10_demo.actor_uid(),v_payload,v_result);
 RETURN v_result;
END$$;

CREATE FUNCTION c10_demo.decide_control_setting_v1(p_request_id bigint,p_decision text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE r c10_demo.control_setting_requests_v1%ROWTYPE; t bigint; v_version bigint; v_business bigint;
BEGIN
 IF c10_demo.actor_uid() IS NULL OR p_decision NOT IN('approve','reject') OR p_decision IS NULL
 THEN RAISE EXCEPTION 'invalid_control_decision'; END IF;
 SELECT business_id INTO v_business FROM c10_demo.control_setting_requests_v1 WHERE id=p_request_id;
 IF v_business IS NULL THEN RAISE EXCEPTION 'control_request_not_found'; END IF;
 SELECT tenant_id INTO t FROM c10_demo.businesses WHERE id=v_business FOR UPDATE;
 IF t IS NULL OR NOT c10_demo.can_tenant(t) THEN RAISE EXCEPTION 'control_approval_denied'; END IF;
 SELECT * INTO r FROM c10_demo.control_setting_requests_v1 WHERE id=p_request_id FOR UPDATE;
 IF r.status<>'pending' THEN
   IF r.status=(CASE WHEN p_decision='approve' THEN 'approved' ELSE 'rejected' END)
   THEN RETURN jsonb_build_object('status',r.status); END IF;
   RAISE EXCEPTION 'control_decision_conflict';
 END IF;
 IF p_decision='approve' THEN
  SELECT version INTO v_version FROM c10_demo.control_settings_v1
    WHERE business_id=r.business_id AND control_id=r.control_id FOR UPDATE;
  IF v_version IS DISTINCT FROM r.expected_version THEN
   RAISE EXCEPTION 'control_request_stale'; END IF;
  UPDATE c10_demo.control_settings_v1 SET preferred_enabled=r.target_enabled,
   version=version+1,changed_at=now(),changed_by=c10_demo.actor_uid()
   WHERE business_id=r.business_id AND control_id=r.control_id;
 END IF;
 UPDATE c10_demo.control_setting_requests_v1
  SET status=CASE WHEN p_decision='approve' THEN 'approved' ELSE 'rejected' END,
  reviewed_by=c10_demo.actor_uid(),reviewed_at=now()
  WHERE id=p_request_id;
 INSERT INTO c10_demo.control_setting_audit_v1(tenant_id,business_id,control_id,event,
  before_state,after_state,actor_uid,request_key)
 VALUES(t,r.business_id,r.control_id,CASE WHEN p_decision='approve' THEN 'request_approved' ELSE 'request_rejected' END,
  jsonb_build_object('expected_version',r.expected_version),
  jsonb_build_object('approved_enabled',CASE WHEN p_decision='approve' THEN r.target_enabled ELSE NULL END),
  c10_demo.actor_uid(),'approval:'||p_request_id::text);
 RETURN jsonb_build_object('status',CASE WHEN p_decision='approve' THEN 'approved' ELSE 'rejected' END);
END$$;

REVOKE ALL ON FUNCTION c10_demo.read_control_settings_v1(bigint) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION c10_demo.write_control_setting_v1(bigint,text,text,text,boolean,bigint,text,text) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION c10_demo.decide_control_setting_v1(bigint,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION c10_demo.read_control_settings_v1(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION c10_demo.write_control_setting_v1(bigint,text,text,text,boolean,bigint,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION c10_demo.decide_control_setting_v1(bigint,text) TO authenticated;
-- NO GRANT for catalog/config/requests/receipts/audit direct DML. No stock/accounting operational effect.

-- A044 Owner approval queue READ; never grant direct request-table access.
CREATE FUNCTION c10_demo.read_control_pending_v1(p_business bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE t bigint; data jsonb;
BEGIN
 SELECT tenant_id INTO t FROM c10_demo.businesses WHERE id=p_business;
 IF c10_demo.actor_uid() IS NULL OR t IS NULL OR NOT c10_demo.can_tenant(t)
 THEN RAISE EXCEPTION 'control_pending_read_denied'; END IF;
 SELECT jsonb_build_object('business_id',p_business,'items',
   COALESCE(jsonb_agg(jsonb_build_object('request_id',id,'control_id',control_id,
    'target_enabled',target_enabled,'expected_version',expected_version,
    'reason',reason,'created_at',created_at) ORDER BY id),'[]'::jsonb))
 INTO data FROM (SELECT * FROM c10_demo.control_setting_requests_v1
   WHERE business_id=p_business AND tenant_id=t AND status='pending'
   ORDER BY id LIMIT 100) x;
 RETURN data;
END$$;
REVOKE ALL ON FUNCTION c10_demo.read_control_pending_v1(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION c10_demo.read_control_pending_v1(bigint) TO authenticated;
