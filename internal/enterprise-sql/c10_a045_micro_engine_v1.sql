-- C10-A045 | Owner Micro-Engine Workshop + registered rule runner + multi-business publishing.
-- DISPOSABLE c10_demo ONLY. Apply AFTER A018/A020/A021/A044. NEVER apply to IMG-ERP-SG without
-- snapshot, staging, real GoTrue auth/RLS tests and explicit Owner go/no-go.
-- Authority: reuses c10_demo.actor_uid()/can_tenant()/can_manage(). NO new roles/permission ledger.
-- Descriptors are DATA. The only executable handler is threshold_rule_v1: bounded, deterministic,
-- ADVISORY, non-mutating. No eval, no SQL/JS formulas, no URLs, no stock/finance/payment writes.

CREATE TABLE c10_demo.micro_engine_handlers_v1(
 handler_id text PRIMARY KEY CHECK(handler_id ~ '^[a-z][a-z0-9_]{2,40}$'),
 kind text NOT NULL,
 certified boolean NOT NULL,
 can_execute boolean NOT NULL,
 CHECK(NOT can_execute OR certified)
);
INSERT INTO c10_demo.micro_engine_handlers_v1(handler_id,kind,certified,can_execute) VALUES
 ('threshold_rule_v1','rule',true,true),
 ('workflow_v1','workflow',false,false),
 ('validator_v1','validator',false,false),
 ('calculator_v1','calculator',false,false),
 ('report_v1','report',false,false),
 ('approval_policy_v1','approval',false,false),
 ('notification_v1','notification',false,false),
 ('automation_v1','automation',false,false),
 ('integration_v1','integration',false,false);

CREATE TABLE c10_demo.micro_engines_v1(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL REFERENCES c10_demo.tenants(id),
 engine_key text NOT NULL CHECK(engine_key ~ '^[a-z][a-z0-9]*(_[a-z0-9]+)*$' AND length(engine_key)<=60),
 display_name text NOT NULL CHECK(length(btrim(display_name)) BETWEEN 3 AND 80),
 handler_id text NOT NULL REFERENCES c10_demo.micro_engine_handlers_v1(handler_id),
 current_version int NOT NULL DEFAULT 1 CHECK(current_version>0),
 created_by uuid NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(tenant_id,engine_key),
 UNIQUE(id,tenant_id)
);
CREATE TABLE c10_demo.micro_engine_versions_v1(
 engine_id bigint NOT NULL,
 tenant_id bigint NOT NULL,
 version int NOT NULL CHECK(version>0),
 descriptor jsonb NOT NULL,
 descriptor_hash text NOT NULL,
 state text NOT NULL DEFAULT 'DRAFT' CHECK(state IN('DRAFT','VALIDATED')),
 created_by uuid NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 validated_by uuid,
 validated_at timestamptz,
 PRIMARY KEY(engine_id,version),
 FOREIGN KEY(engine_id,tenant_id) REFERENCES c10_demo.micro_engines_v1(id,tenant_id),
 CHECK(descriptor_hash=md5(descriptor::text)),
 CHECK((state='DRAFT' AND validated_by IS NULL) OR (state='VALIDATED' AND validated_by IS NOT NULL))
);
CREATE TABLE c10_demo.micro_engine_assignments_v1(
 engine_id bigint NOT NULL,
 tenant_id bigint NOT NULL,
 business_id bigint NOT NULL,
 state text NOT NULL CHECK(state IN('PUBLISHED','PAUSED','REVOKED')),
 pinned_version int NOT NULL,
 params jsonb NOT NULL DEFAULT '{}'::jsonb,
 placement text NOT NULL CHECK(placement IN('central_only','business_only','both','hidden_from_menus')),
 local_edit_mode text NOT NULL CHECK(local_edit_mode IN('central_only','business_owner','request_approval')),
 version bigint NOT NULL DEFAULT 1 CHECK(version>0),
 changed_by uuid NOT NULL,
 changed_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(engine_id,business_id),
 FOREIGN KEY(engine_id,tenant_id) REFERENCES c10_demo.micro_engines_v1(id,tenant_id),
 FOREIGN KEY(engine_id,pinned_version) REFERENCES c10_demo.micro_engine_versions_v1(engine_id,version),
 FOREIGN KEY(business_id,tenant_id) REFERENCES c10_demo.businesses(id,tenant_id),
 CHECK((placement NOT IN('central_only','hidden_from_menus')) OR local_edit_mode='central_only')
);
CREATE TABLE c10_demo.micro_engine_requests_v1(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL,
 engine_id bigint NOT NULL,
 business_id bigint NOT NULL,
 expected_version bigint NOT NULL,
 target_params jsonb NOT NULL,
 requested_by uuid NOT NULL,
 reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 5 AND 500),
 status text NOT NULL DEFAULT 'pending' CHECK(status IN('pending','approved','rejected')),
 reviewed_by uuid,
 reviewed_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(engine_id,business_id) REFERENCES c10_demo.micro_engine_assignments_v1(engine_id,business_id),
 CHECK((status='pending' AND reviewed_by IS NULL) OR (status<>'pending' AND reviewed_by IS NOT NULL))
);
CREATE TABLE c10_demo.micro_engine_receipts_v1(
 tenant_id bigint NOT NULL REFERENCES c10_demo.tenants(id),
 request_key text NOT NULL CHECK(request_key ~ '^[A-Za-z0-9_-]{8,100}$'),
 actor_uid uuid NOT NULL,
 payload jsonb NOT NULL,
 result jsonb NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(tenant_id,request_key)
);
CREATE TABLE c10_demo.micro_engine_audit_v1(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tenant_id bigint NOT NULL,
 engine_id bigint NOT NULL,
 business_id bigint,
 event text NOT NULL CHECK(event IN('engine_created','version_saved','version_validated',
  'assignment_changed','params_edited','request_submitted','request_approved','request_rejected',
  'assignment_rolled_back')),
 before_state jsonb,
 after_state jsonb,
 actor_uid uuid NOT NULL,
 request_key text NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now()
);

-- Immutability: audit is append-only; versions may only move DRAFT->VALIDATED.
CREATE FUNCTION c10_demo.micro_engine_audit_immutable_v1() RETURNS trigger
LANGUAGE plpgsql AS $$BEGIN RAISE EXCEPTION 'micro_engine_audit_immutable'; END$$;
CREATE TRIGGER micro_engine_audit_no_mutation_v1 BEFORE UPDATE OR DELETE OR TRUNCATE
ON c10_demo.micro_engine_audit_v1 FOR EACH STATEMENT
EXECUTE FUNCTION c10_demo.micro_engine_audit_immutable_v1();
CREATE FUNCTION c10_demo.micro_engine_version_guard_v1() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
 IF TG_OP IN('DELETE','TRUNCATE') THEN RAISE EXCEPTION 'micro_engine_version_immutable'; END IF;
 IF NEW.engine_id<>OLD.engine_id OR NEW.version<>OLD.version OR NEW.descriptor<>OLD.descriptor
   OR NEW.descriptor_hash<>OLD.descriptor_hash OR NEW.created_by<>OLD.created_by
   OR NEW.created_at<>OLD.created_at OR OLD.state<>'DRAFT' OR NEW.state<>'VALIDATED'
 THEN RAISE EXCEPTION 'micro_engine_version_immutable'; END IF;
 RETURN NEW;
END$$;
CREATE TRIGGER micro_engine_version_row_guard_v1 BEFORE UPDATE OR DELETE
ON c10_demo.micro_engine_versions_v1 FOR EACH ROW
EXECUTE FUNCTION c10_demo.micro_engine_version_guard_v1();
CREATE TRIGGER micro_engine_version_trunc_guard_v1 BEFORE TRUNCATE
ON c10_demo.micro_engine_versions_v1 FOR EACH STATEMENT
EXECUTE FUNCTION c10_demo.micro_engine_audit_immutable_v1();

ALTER TABLE c10_demo.micro_engine_handlers_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE c10_demo.micro_engines_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE c10_demo.micro_engine_versions_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE c10_demo.micro_engine_assignments_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE c10_demo.micro_engine_requests_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE c10_demo.micro_engine_receipts_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE c10_demo.micro_engine_audit_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON c10_demo.micro_engine_handlers_v1,c10_demo.micro_engines_v1,
 c10_demo.micro_engine_versions_v1,c10_demo.micro_engine_assignments_v1,
 c10_demo.micro_engine_requests_v1,c10_demo.micro_engine_receipts_v1,
 c10_demo.micro_engine_audit_v1 FROM PUBLIC,authenticated,anon;

-- ---------- pure validation / evaluation (no table access, no side effects) ----------
CREATE FUNCTION c10_demo.engine_threshold_descriptor_valid_v1(d jsonb) RETURNS boolean
LANGUAGE sql IMMUTABLE AS $$
 SELECT d IS NOT NULL AND jsonb_typeof(d)='object'
  AND NOT EXISTS(SELECT 1 FROM jsonb_object_keys(d) k
      WHERE k NOT IN('field','op','threshold','outcome','message'))
  AND d ? 'field' AND d ? 'op' AND d ? 'threshold' AND d ? 'outcome'
  AND jsonb_typeof(d->'field')='string' AND d->>'field' IN('on_hand','reorder_gap','days_cover','margin_pct','order_total')
  AND jsonb_typeof(d->'op')='string' AND d->>'op' IN('lt','lte','gt','gte','eq')
  AND jsonb_typeof(d->'threshold')='number'
  AND (d->>'threshold')::numeric BETWEEN -1000000000 AND 1000000000
  AND jsonb_typeof(d->'outcome')='string' AND d->>'outcome' IN('allow','warn','block','approval_required')
  AND (NOT d ? 'message' OR (jsonb_typeof(d->'message')='string'
       AND length(d->>'message')<=200 AND d->>'message' !~ '[[:cntrl:]]'))
$$;
CREATE FUNCTION c10_demo.engine_params_valid_v1(p jsonb) RETURNS boolean
LANGUAGE sql IMMUTABLE AS $$
 SELECT p IS NOT NULL AND jsonb_typeof(p)='object'
  AND NOT EXISTS(SELECT 1 FROM jsonb_object_keys(p) k WHERE k NOT IN('threshold','outcome'))
  AND (NOT p ? 'threshold' OR (jsonb_typeof(p->'threshold')='number'
       AND (p->>'threshold')::numeric BETWEEN -1000000000 AND 1000000000))
  AND (NOT p ? 'outcome' OR (jsonb_typeof(p->'outcome')='string'
       AND p->>'outcome' IN('allow','warn','block','approval_required')))
$$;
-- ADVISORY evaluation only: wouldBlock never authorizes or denies a real operation.
CREATE FUNCTION c10_demo.engine_eval_threshold_v1(d jsonb,params jsonb,inputs jsonb) RETURNS jsonb
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE v numeric; th numeric; oc text; hit boolean; f text;
BEGIN
 IF NOT c10_demo.engine_threshold_descriptor_valid_v1(d) THEN RAISE EXCEPTION 'invalid_descriptor'; END IF;
 IF NOT c10_demo.engine_params_valid_v1(COALESCE(params,'{}'::jsonb)) THEN RAISE EXCEPTION 'invalid_params'; END IF;
 IF inputs IS NULL OR jsonb_typeof(inputs)<>'object' OR (SELECT count(*) FROM jsonb_object_keys(inputs))>5
 THEN RAISE EXCEPTION 'invalid_input'; END IF;
 f:=d->>'field';
 IF NOT inputs ? f OR jsonb_typeof(inputs->f)<>'number' OR (inputs->>f)::numeric NOT BETWEEN -1000000000 AND 1000000000
 THEN RAISE EXCEPTION 'invalid_input'; END IF;
 v:=(inputs->>f)::numeric;
 th:=COALESCE((params->>'threshold')::numeric,(d->>'threshold')::numeric);
 oc:=COALESCE(params->>'outcome',d->>'outcome');
 hit:=CASE d->>'op' WHEN 'lt' THEN v<th WHEN 'lte' THEN v<=th WHEN 'gt' THEN v>th
        WHEN 'gte' THEN v>=th ELSE v=th END;
 RETURN jsonb_build_object('advisory',true,'matched',hit,
  'outcome',CASE WHEN hit THEN oc ELSE 'allow' END,
  'wouldBlock',hit AND oc='block','requiresApproval',hit AND oc='approval_required',
  'message',CASE WHEN hit THEN d->>'message' ELSE NULL END,
  'effective',jsonb_build_object('field',f,'op',d->>'op','threshold',th,'outcome',oc),
  'canAuthorizeOperation',false,'mutates',false);
END$$;

-- ---------- internal helpers (not granted to app roles) ----------
CREATE FUNCTION c10_demo.engine_receipt_v1(p_tenant bigint,p_request text,p_payload jsonb) RETURNS jsonb
LANGUAGE plpgsql AS $$
DECLARE r c10_demo.micro_engine_receipts_v1%ROWTYPE;
BEGIN
 SELECT * INTO r FROM c10_demo.micro_engine_receipts_v1 WHERE tenant_id=p_tenant AND request_key=p_request;
 IF NOT FOUND THEN RETURN NULL; END IF;
 IF r.actor_uid<>c10_demo.actor_uid() OR r.payload<>p_payload THEN RAISE EXCEPTION 'engine_idempotency_conflict'; END IF;
 RETURN r.result;
END$$;
CREATE FUNCTION c10_demo.engine_record_v1(p_tenant bigint,p_request text,p_payload jsonb,p_result jsonb) RETURNS void
LANGUAGE sql AS $$
 INSERT INTO c10_demo.micro_engine_receipts_v1(tenant_id,request_key,actor_uid,payload,result)
 VALUES(p_tenant,p_request,c10_demo.actor_uid(),p_payload,p_result)
$$;
CREATE FUNCTION c10_demo.engine_audit_v1(p_tenant bigint,p_engine bigint,p_business bigint,p_event text,
 p_before jsonb,p_after jsonb,p_request text) RETURNS void
LANGUAGE sql AS $$
 INSERT INTO c10_demo.micro_engine_audit_v1(tenant_id,engine_id,business_id,event,before_state,after_state,actor_uid,request_key)
 VALUES(p_tenant,p_engine,p_business,p_event,p_before,p_after,c10_demo.actor_uid(),p_request)
$$;
-- Per-tenant serialization + Owner check. Every mutation/read of Owner data goes through this.
CREATE FUNCTION c10_demo.engine_owner_lock_v1(p_tenant bigint) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
 IF c10_demo.actor_uid() IS NULL OR p_tenant IS NULL THEN RAISE EXCEPTION 'engine_denied'; END IF;
 PERFORM 1 FROM c10_demo.tenants WHERE id=p_tenant FOR UPDATE;
 IF NOT FOUND OR NOT c10_demo.can_tenant(p_tenant) THEN RAISE EXCEPTION 'engine_denied'; END IF;
END$$;
CREATE FUNCTION c10_demo.engine_check_req_v1(p_request text,p_reason text) RETURNS void
LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
 IF p_request IS NULL OR p_request !~ '^[A-Za-z0-9_-]{8,100}$' OR p_reason IS NULL
    OR length(btrim(p_reason)) NOT BETWEEN 5 AND 500 THEN RAISE EXCEPTION 'invalid_engine_request'; END IF;
END$$;
CREATE FUNCTION c10_demo.engine_descriptor_ok_v1(p_handler text,p_descriptor jsonb) RETURNS boolean
LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
 IF p_descriptor IS NULL OR jsonb_typeof(p_descriptor)<>'object' OR length(p_descriptor::text)>8000 THEN RETURN false; END IF;
 IF p_handler='threshold_rule_v1' THEN RETURN c10_demo.engine_threshold_descriptor_valid_v1(p_descriptor); END IF;
 RETURN true; -- uncertified handler types: stored as inert DRAFT data only, never executable
END$$;

-- ---------- Owner RPC: create engine / save new immutable version ----------
CREATE FUNCTION c10_demo.save_engine_draft_v1(p_tenant bigint,p_key text,p_name text,p_handler text,
 p_descriptor jsonb,p_expected_version int,p_request text,p_reason text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE e c10_demo.micro_engines_v1%ROWTYPE; pay jsonb; res jsonb; nv int;
BEGIN
 IF p_expected_version IS NULL OR p_expected_version<0 OR p_key IS NULL OR p_name IS NULL OR p_handler IS NULL
 THEN RAISE EXCEPTION 'invalid_engine_request'; END IF;
 PERFORM c10_demo.engine_check_req_v1(p_request,p_reason);
 PERFORM c10_demo.engine_owner_lock_v1(p_tenant);
 pay:=jsonb_build_object('op','save','key',p_key,'name',btrim(p_name),'handler',p_handler,
   'descriptor',p_descriptor,'expected',p_expected_version,'reason',btrim(p_reason));
 res:=c10_demo.engine_receipt_v1(p_tenant,p_request,pay);
 IF res IS NOT NULL THEN RETURN res; END IF;
 IF NOT EXISTS(SELECT 1 FROM c10_demo.micro_engine_handlers_v1 WHERE handler_id=p_handler)
 THEN RAISE EXCEPTION 'unknown_handler'; END IF;
 IF NOT c10_demo.engine_descriptor_ok_v1(p_handler,p_descriptor) THEN RAISE EXCEPTION 'invalid_descriptor'; END IF;
 SELECT * INTO e FROM c10_demo.micro_engines_v1 WHERE tenant_id=p_tenant AND engine_key=p_key FOR UPDATE;
 IF NOT FOUND THEN
  IF p_expected_version<>0 THEN RAISE EXCEPTION 'engine_stale_version'; END IF;
  INSERT INTO c10_demo.micro_engines_v1(tenant_id,engine_key,display_name,handler_id,created_by)
  VALUES(p_tenant,p_key,btrim(p_name),p_handler,c10_demo.actor_uid()) RETURNING * INTO e;
  nv:=1;
  PERFORM c10_demo.engine_audit_v1(p_tenant,e.id,NULL,'engine_created',NULL,
    jsonb_build_object('engine_key',p_key,'handler',p_handler),p_request);
 ELSE
  IF e.handler_id<>p_handler THEN RAISE EXCEPTION 'handler_change_denied'; END IF;
  IF e.current_version<>p_expected_version THEN RAISE EXCEPTION 'engine_stale_version'; END IF;
  nv:=e.current_version+1;
  UPDATE c10_demo.micro_engines_v1 SET current_version=nv,display_name=btrim(p_name) WHERE id=e.id;
 END IF;
 INSERT INTO c10_demo.micro_engine_versions_v1(engine_id,tenant_id,version,descriptor,descriptor_hash,created_by)
 VALUES(e.id,p_tenant,nv,p_descriptor,md5(p_descriptor::text),c10_demo.actor_uid());
 PERFORM c10_demo.engine_audit_v1(p_tenant,e.id,NULL,'version_saved',
   CASE WHEN nv=1 THEN NULL ELSE jsonb_build_object('version',nv-1) END,
   jsonb_build_object('version',nv,'state','DRAFT','hash',md5(p_descriptor::text)),p_request);
 res:=jsonb_build_object('status','saved','engine_id',e.id,'version',nv,'state','DRAFT',
   'can_execute',(SELECT can_execute FROM c10_demo.micro_engine_handlers_v1 WHERE handler_id=p_handler));
 PERFORM c10_demo.engine_record_v1(p_tenant,p_request,pay,res);
 RETURN res;
END$$;

CREATE FUNCTION c10_demo.validate_engine_version_v1(p_engine bigint,p_version int,p_request text,p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE t bigint; e c10_demo.micro_engines_v1%ROWTYPE; v c10_demo.micro_engine_versions_v1%ROWTYPE; pay jsonb; res jsonb;
BEGIN
 PERFORM c10_demo.engine_check_req_v1(p_request,p_reason);
 SELECT tenant_id INTO t FROM c10_demo.micro_engines_v1 WHERE id=p_engine;
 IF t IS NULL THEN RAISE EXCEPTION 'engine_denied'; END IF;
 PERFORM c10_demo.engine_owner_lock_v1(t);
 pay:=jsonb_build_object('op','validate','engine',p_engine,'version',p_version,'reason',btrim(p_reason));
 res:=c10_demo.engine_receipt_v1(t,p_request,pay);
 IF res IS NOT NULL THEN RETURN res; END IF;
 SELECT * INTO e FROM c10_demo.micro_engines_v1 WHERE id=p_engine;
 SELECT * INTO v FROM c10_demo.micro_engine_versions_v1 WHERE engine_id=p_engine AND version=p_version FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'engine_version_not_found'; END IF;
 IF v.state='VALIDATED' THEN RAISE EXCEPTION 'engine_already_validated'; END IF;
 IF v.descriptor_hash<>md5(v.descriptor::text) OR NOT c10_demo.engine_descriptor_ok_v1(e.handler_id,v.descriptor)
 THEN RAISE EXCEPTION 'invalid_descriptor'; END IF;
 IF NOT (SELECT certified FROM c10_demo.micro_engine_handlers_v1 WHERE handler_id=e.handler_id)
 THEN RAISE EXCEPTION 'handler_not_certified'; END IF;
 UPDATE c10_demo.micro_engine_versions_v1 SET state='VALIDATED',validated_by=c10_demo.actor_uid(),validated_at=now()
  WHERE engine_id=p_engine AND version=p_version;
 PERFORM c10_demo.engine_audit_v1(t,p_engine,NULL,'version_validated',jsonb_build_object('state','DRAFT'),
   jsonb_build_object('version',p_version,'state','VALIDATED'),p_request);
 res:=jsonb_build_object('status','validated','engine_id',p_engine,'version',p_version,'state','VALIDATED');
 PERFORM c10_demo.engine_record_v1(t,p_request,pay,res);
 RETURN res;
END$$;

-- ---------- Owner preview of an unsaved descriptor (no table write) ----------
CREATE FUNCTION c10_demo.preview_engine_draft_v1(p_tenant bigint,p_handler text,p_descriptor jsonb,p_params jsonb,p_inputs jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
BEGIN
 IF c10_demo.actor_uid() IS NULL OR p_tenant IS NULL OR NOT c10_demo.can_tenant(p_tenant)
 THEN RAISE EXCEPTION 'engine_denied'; END IF;
 IF p_handler IS DISTINCT FROM 'threshold_rule_v1' THEN RAISE EXCEPTION 'handler_not_executable'; END IF;
 RETURN c10_demo.engine_eval_threshold_v1(p_descriptor,COALESCE(p_params,'{}'::jsonb),p_inputs);
END$$;

-- ---------- Owner RPC: publish / pause / revoke / update an assignment ----------
CREATE FUNCTION c10_demo.assign_engine_v1(p_engine bigint,p_business bigint,p_version int,p_state text,
 p_params jsonb,p_placement text,p_local_edit text,p_expected bigint,p_request text,p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE t bigint; e c10_demo.micro_engines_v1%ROWTYPE; a c10_demo.micro_engine_assignments_v1%ROWTYPE;
 v c10_demo.micro_engine_versions_v1%ROWTYPE; h c10_demo.micro_engine_handlers_v1%ROWTYPE;
 pay jsonb; res jsonb; nver bigint; before jsonb;
BEGIN
 IF p_business IS NULL OR p_version IS NULL OR p_expected IS NULL OR p_expected<0 OR
    p_state IS NULL OR p_state NOT IN('PUBLISHED','PAUSED','REVOKED') OR
    p_placement IS NULL OR p_placement NOT IN('central_only','business_only','both','hidden_from_menus') OR
    p_local_edit IS NULL OR p_local_edit NOT IN('central_only','business_owner','request_approval') OR
    (p_placement IN('central_only','hidden_from_menus') AND p_local_edit<>'central_only') OR
    NOT c10_demo.engine_params_valid_v1(COALESCE(p_params,'{}'::jsonb))
 THEN RAISE EXCEPTION 'invalid_engine_request'; END IF;
 PERFORM c10_demo.engine_check_req_v1(p_request,p_reason);
 SELECT * INTO e FROM c10_demo.micro_engines_v1 WHERE id=p_engine;
 IF NOT FOUND THEN RAISE EXCEPTION 'engine_denied'; END IF;
 t:=e.tenant_id;
 PERFORM c10_demo.engine_owner_lock_v1(t);
 pay:=jsonb_build_object('op','assign','engine',p_engine,'business',p_business,'version',p_version,
  'state',p_state,'params',COALESCE(p_params,'{}'::jsonb),'placement',p_placement,'edit',p_local_edit,
  'expected',p_expected,'reason',btrim(p_reason));
 res:=c10_demo.engine_receipt_v1(t,p_request,pay);
 IF res IS NOT NULL THEN RETURN res; END IF;
 IF NOT EXISTS(SELECT 1 FROM c10_demo.businesses WHERE id=p_business AND tenant_id=t)
 THEN RAISE EXCEPTION 'engine_denied'; END IF;
 SELECT * INTO v FROM c10_demo.micro_engine_versions_v1 WHERE engine_id=p_engine AND version=p_version;
 IF NOT FOUND THEN RAISE EXCEPTION 'engine_version_not_found'; END IF;
 SELECT * INTO h FROM c10_demo.micro_engine_handlers_v1 WHERE handler_id=e.handler_id;
 SELECT * INTO a FROM c10_demo.micro_engine_assignments_v1 WHERE engine_id=p_engine AND business_id=p_business FOR UPDATE;
 IF (CASE WHEN FOUND THEN a.version ELSE 0 END)<>p_expected THEN RAISE EXCEPTION 'engine_stale_version'; END IF;
 IF NOT FOUND AND p_state<>'PUBLISHED' THEN RAISE EXCEPTION 'engine_invalid_transition'; END IF;
 IF p_state='PUBLISHED' THEN
  IF NOT h.certified OR NOT h.can_execute THEN RAISE EXCEPTION 'handler_not_certified'; END IF;
  IF v.state<>'VALIDATED' THEN RAISE EXCEPTION 'engine_version_not_validated'; END IF;
 END IF;
 IF FOUND AND p_version<>a.pinned_version AND p_state<>'PUBLISHED' THEN RAISE EXCEPTION 'engine_invalid_transition'; END IF;
 before:=CASE WHEN a.engine_id IS NULL THEN NULL ELSE to_jsonb(a) END;
 nver:=p_expected+1;
 INSERT INTO c10_demo.micro_engine_assignments_v1(engine_id,tenant_id,business_id,state,pinned_version,
   params,placement,local_edit_mode,version,changed_by)
 VALUES(p_engine,t,p_business,p_state,p_version,COALESCE(p_params,'{}'::jsonb),p_placement,p_local_edit,nver,c10_demo.actor_uid())
 ON CONFLICT(engine_id,business_id) DO UPDATE SET state=excluded.state,pinned_version=excluded.pinned_version,
   params=excluded.params,placement=excluded.placement,local_edit_mode=excluded.local_edit_mode,
   version=excluded.version,changed_by=excluded.changed_by,changed_at=now();
 PERFORM c10_demo.engine_audit_v1(t,p_engine,p_business,'assignment_changed',before,
   jsonb_build_object('state',p_state,'pinned_version',p_version,'params',COALESCE(p_params,'{}'::jsonb),
    'placement',p_placement,'local_edit_mode',p_local_edit,'version',nver),p_request);
 res:=jsonb_build_object('status','applied','engine_id',p_engine,'business_id',p_business,
   'state',p_state,'version',nver,'operationally_certified',false);
 PERFORM c10_demo.engine_record_v1(t,p_request,pay,res);
 RETURN res;
END$$;

-- ---------- Delegated per-business parameter edit (Owner direct; Business Owner only when granted) ----------
CREATE FUNCTION c10_demo.edit_engine_params_v1(p_engine bigint,p_business bigint,p_params jsonb,
 p_expected bigint,p_request text,p_reason text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE t bigint; a c10_demo.micro_engine_assignments_v1%ROWTYPE; pay jsonb; res jsonb; rid bigint; owner boolean;
BEGIN
 IF c10_demo.actor_uid() IS NULL OR p_engine IS NULL OR p_business IS NULL OR p_expected IS NULL OR p_expected<1
    OR NOT c10_demo.engine_params_valid_v1(COALESCE(p_params,'{}'::jsonb)) THEN RAISE EXCEPTION 'invalid_engine_request'; END IF;
 PERFORM c10_demo.engine_check_req_v1(p_request,p_reason);
 SELECT tenant_id INTO t FROM c10_demo.businesses WHERE id=p_business;
 IF t IS NULL THEN RAISE EXCEPTION 'engine_denied'; END IF;
 PERFORM 1 FROM c10_demo.tenants WHERE id=t FOR UPDATE;
 IF NOT c10_demo.can_manage(t,p_business) THEN RAISE EXCEPTION 'engine_denied'; END IF;
 owner:=c10_demo.can_tenant(t);
 pay:=jsonb_build_object('op','params','engine',p_engine,'business',p_business,'params',COALESCE(p_params,'{}'::jsonb),
   'expected',p_expected,'reason',btrim(p_reason));
 res:=c10_demo.engine_receipt_v1(t,p_request,pay);
 IF res IS NOT NULL THEN RETURN res; END IF;
 SELECT * INTO a FROM c10_demo.micro_engine_assignments_v1 WHERE engine_id=p_engine AND business_id=p_business AND tenant_id=t FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'engine_denied'; END IF;
 IF a.version<>p_expected THEN RAISE EXCEPTION 'engine_stale_version'; END IF;
 IF a.state<>'PUBLISHED' THEN RAISE EXCEPTION 'engine_not_published'; END IF;
 IF NOT owner THEN
  IF a.placement NOT IN('business_only','both') OR a.local_edit_mode='central_only' THEN RAISE EXCEPTION 'engine_local_edit_denied'; END IF;
  IF a.local_edit_mode='request_approval' THEN
   INSERT INTO c10_demo.micro_engine_requests_v1(tenant_id,engine_id,business_id,expected_version,target_params,requested_by,reason)
   VALUES(t,p_engine,p_business,a.version,COALESCE(p_params,'{}'::jsonb),c10_demo.actor_uid(),btrim(p_reason)) RETURNING id INTO rid;
   PERFORM c10_demo.engine_audit_v1(t,p_engine,p_business,'request_submitted',jsonb_build_object('params',a.params),
     jsonb_build_object('target_params',COALESCE(p_params,'{}'::jsonb),'request_id',rid),p_request);
   res:=jsonb_build_object('status','pending','request_id',rid,'version',a.version);
   PERFORM c10_demo.engine_record_v1(t,p_request,pay,res);
   RETURN res;
  END IF;
 END IF;
 UPDATE c10_demo.micro_engine_assignments_v1 SET params=COALESCE(p_params,'{}'::jsonb),version=version+1,
   changed_by=c10_demo.actor_uid(),changed_at=now() WHERE engine_id=p_engine AND business_id=p_business;
 PERFORM c10_demo.engine_audit_v1(t,p_engine,p_business,'params_edited',to_jsonb(a),
   jsonb_build_object('state',a.state,'pinned_version',a.pinned_version,'params',COALESCE(p_params,'{}'::jsonb),
    'placement',a.placement,'local_edit_mode',a.local_edit_mode,'version',a.version+1),p_request);
 res:=jsonb_build_object('status','applied','version',a.version+1,'operationally_certified',false);
 PERFORM c10_demo.engine_record_v1(t,p_request,pay,res);
 RETURN res;
END$$;

CREATE FUNCTION c10_demo.decide_engine_request_v1(p_request_id bigint,p_decision text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE r c10_demo.micro_engine_requests_v1%ROWTYPE; t bigint; a c10_demo.micro_engine_assignments_v1%ROWTYPE;
BEGIN
 IF c10_demo.actor_uid() IS NULL OR p_decision IS NULL OR p_decision NOT IN('approve','reject')
 THEN RAISE EXCEPTION 'invalid_engine_decision'; END IF;
 SELECT tenant_id INTO t FROM c10_demo.micro_engine_requests_v1 WHERE id=p_request_id;
 IF t IS NULL THEN RAISE EXCEPTION 'engine_request_not_found'; END IF;
 PERFORM c10_demo.engine_owner_lock_v1(t);
 SELECT * INTO r FROM c10_demo.micro_engine_requests_v1 WHERE id=p_request_id FOR UPDATE;
 IF r.status<>'pending' THEN
  IF r.status=(CASE WHEN p_decision='approve' THEN 'approved' ELSE 'rejected' END) THEN RETURN jsonb_build_object('status',r.status); END IF;
  RAISE EXCEPTION 'engine_decision_conflict';
 END IF;
 IF p_decision='approve' THEN
  SELECT * INTO a FROM c10_demo.micro_engine_assignments_v1 WHERE engine_id=r.engine_id AND business_id=r.business_id FOR UPDATE;
  IF a.version<>r.expected_version OR a.state<>'PUBLISHED' THEN RAISE EXCEPTION 'engine_request_stale'; END IF;
  UPDATE c10_demo.micro_engine_assignments_v1 SET params=r.target_params,version=version+1,
    changed_by=c10_demo.actor_uid(),changed_at=now() WHERE engine_id=r.engine_id AND business_id=r.business_id;
 END IF;
 UPDATE c10_demo.micro_engine_requests_v1 SET status=CASE WHEN p_decision='approve' THEN 'approved' ELSE 'rejected' END,
   reviewed_by=c10_demo.actor_uid(),reviewed_at=now() WHERE id=p_request_id;
 PERFORM c10_demo.engine_audit_v1(t,r.engine_id,r.business_id,
   CASE WHEN p_decision='approve' THEN 'request_approved' ELSE 'request_rejected' END,
   jsonb_build_object('expected_version',r.expected_version),
   jsonb_build_object('target_params',r.target_params),'approval:'||p_request_id::text);
 RETURN jsonb_build_object('status',CASE WHEN p_decision='approve' THEN 'approved' ELSE 'rejected' END);
END$$;

-- ---------- Configuration-only rollback: restores an assignment's previous state; touches NO ledger ----------
CREATE FUNCTION c10_demo.rollback_engine_assignment_v1(p_engine bigint,p_business bigint,p_audit_id bigint,
 p_expected bigint,p_request text,p_reason text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE t bigint; au c10_demo.micro_engine_audit_v1%ROWTYPE; a c10_demo.micro_engine_assignments_v1%ROWTYPE;
 b jsonb; st text; pv int; pay jsonb; res jsonb; nver bigint; v c10_demo.micro_engine_versions_v1%ROWTYPE;
BEGIN
 IF p_expected IS NULL OR p_expected<1 OR p_audit_id IS NULL THEN RAISE EXCEPTION 'invalid_engine_request'; END IF;
 PERFORM c10_demo.engine_check_req_v1(p_request,p_reason);
 SELECT tenant_id INTO t FROM c10_demo.micro_engines_v1 WHERE id=p_engine;
 IF t IS NULL THEN RAISE EXCEPTION 'engine_denied'; END IF;
 PERFORM c10_demo.engine_owner_lock_v1(t);
 pay:=jsonb_build_object('op','rollback','engine',p_engine,'business',p_business,'audit',p_audit_id,
   'expected',p_expected,'reason',btrim(p_reason));
 res:=c10_demo.engine_receipt_v1(t,p_request,pay);
 IF res IS NOT NULL THEN RETURN res; END IF;
 SELECT * INTO au FROM c10_demo.micro_engine_audit_v1 WHERE id=p_audit_id AND tenant_id=t
   AND engine_id=p_engine AND business_id=p_business
   AND event IN('assignment_changed','params_edited','request_approved','assignment_rolled_back');
 IF NOT FOUND THEN RAISE EXCEPTION 'engine_rollback_target_invalid'; END IF;
 SELECT * INTO a FROM c10_demo.micro_engine_assignments_v1 WHERE engine_id=p_engine AND business_id=p_business FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'engine_denied'; END IF;
 IF a.version<>p_expected THEN RAISE EXCEPTION 'engine_stale_version'; END IF;
 b:=au.before_state;
 IF b IS NULL OR NOT b ? 'pinned_version' THEN
  st:='REVOKED'; pv:=a.pinned_version; b:=to_jsonb(a); -- first-ever publish: revert means withdraw
 ELSE
  st:=b->>'state'; pv:=(b->>'pinned_version')::int;
 END IF;
 SELECT * INTO v FROM c10_demo.micro_engine_versions_v1 WHERE engine_id=p_engine AND version=pv;
 IF NOT FOUND OR (st='PUBLISHED' AND v.state<>'VALIDATED') THEN RAISE EXCEPTION 'engine_rollback_target_invalid'; END IF;
 IF NOT c10_demo.engine_params_valid_v1(b->'params') THEN RAISE EXCEPTION 'engine_rollback_target_invalid'; END IF;
 nver:=a.version+1;
 UPDATE c10_demo.micro_engine_assignments_v1 SET state=st,pinned_version=pv,params=b->'params',
   placement=b->>'placement',local_edit_mode=b->>'local_edit_mode',version=nver,
   changed_by=c10_demo.actor_uid(),changed_at=now() WHERE engine_id=p_engine AND business_id=p_business;
 PERFORM c10_demo.engine_audit_v1(t,p_engine,p_business,'assignment_rolled_back',to_jsonb(a),
   jsonb_build_object('state',st,'pinned_version',pv,'params',b->'params','placement',b->>'placement',
    'local_edit_mode',b->>'local_edit_mode','version',nver,'restored_from_audit',p_audit_id),p_request);
 res:=jsonb_build_object('status','rolled_back','version',nver,'state',st,'config_only',true);
 PERFORM c10_demo.engine_record_v1(t,p_request,pay,res);
 RETURN res;
END$$;

-- ---------- READ RPCs ----------
-- Owner registry: engines, versions, assignments. Tenant owner only.
CREATE FUNCTION c10_demo.read_engines_v1(p_tenant bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
BEGIN
 IF c10_demo.actor_uid() IS NULL OR p_tenant IS NULL OR NOT c10_demo.can_tenant(p_tenant)
 THEN RAISE EXCEPTION 'engine_denied'; END IF;
 RETURN jsonb_build_object('tenant_id',p_tenant,'server_authorized',true,'operationally_certified',false,
  'handlers',(SELECT COALESCE(jsonb_agg(jsonb_build_object('handler_id',handler_id,'kind',kind,
     'certified',certified,'can_execute',can_execute) ORDER BY handler_id),'[]'::jsonb)
     FROM c10_demo.micro_engine_handlers_v1),
  'engines',(SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'engine_id',e.id,'engine_key',e.engine_key,'display_name',e.display_name,'handler_id',e.handler_id,
    'current_version',e.current_version,
    'versions',(SELECT COALESCE(jsonb_agg(jsonb_build_object('version',v.version,'state',v.state,
       'descriptor',v.descriptor,'hash',v.descriptor_hash,'created_at',v.created_at) ORDER BY v.version),'[]'::jsonb)
       FROM c10_demo.micro_engine_versions_v1 v WHERE v.engine_id=e.id),
    'assignments',(SELECT COALESCE(jsonb_agg(jsonb_build_object('business_id',a.business_id,'state',a.state,
       'pinned_version',a.pinned_version,'params',a.params,'placement',a.placement,
       'local_edit_mode',a.local_edit_mode,'version',a.version) ORDER BY a.business_id),'[]'::jsonb)
       FROM c10_demo.micro_engine_assignments_v1 a WHERE a.engine_id=e.id)
   ) ORDER BY e.id),'[]'::jsonb) FROM c10_demo.micro_engines_v1 e WHERE e.tenant_id=p_tenant));
END$$;
CREATE FUNCTION c10_demo.read_engine_audit_v1(p_engine bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE t bigint;
BEGIN
 SELECT tenant_id INTO t FROM c10_demo.micro_engines_v1 WHERE id=p_engine;
 IF c10_demo.actor_uid() IS NULL OR t IS NULL OR NOT c10_demo.can_tenant(t) THEN RAISE EXCEPTION 'engine_denied'; END IF;
 RETURN jsonb_build_object('engine_id',p_engine,'items',(SELECT COALESCE(jsonb_agg(jsonb_build_object(
   'audit_id',id,'event',event,'business_id',business_id,'before',before_state,'after',after_state,
   'actor_uid',actor_uid,'created_at',created_at) ORDER BY id DESC),'[]'::jsonb)
   FROM (SELECT * FROM c10_demo.micro_engine_audit_v1 WHERE engine_id=p_engine ORDER BY id DESC LIMIT 100) x));
END$$;
-- Canonical per-business projection: SAME service for Business A, Business B, Central and Business App.
-- Items mirror the A044 shape (control_id/placement/local_edit_mode/preferred_enabled/version) with
-- control_id = 'engine.<engine_key>' so the A044 Business Controls surface can merge them additively.
-- Placement is VISIBILITY only: a hidden/business-only flag never grants any backend operation.
CREATE FUNCTION c10_demo.read_business_engines_v1(p_business bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE t bigint; owner boolean;
BEGIN
 SELECT tenant_id INTO t FROM c10_demo.businesses WHERE id=p_business;
 IF c10_demo.actor_uid() IS NULL OR t IS NULL OR NOT c10_demo.can_manage(t,p_business)
 THEN RAISE EXCEPTION 'engine_denied'; END IF;
 owner:=c10_demo.can_tenant(t);
 RETURN jsonb_build_object('tenant_id',t,'business_id',p_business,'server_authorized',true,
  'operationally_certified',false,'items',(SELECT COALESCE(jsonb_agg(jsonb_build_object(
   'control_id','engine.'||e.engine_key,'engine_id',e.id,'display_name',e.display_name,'handler_id',e.handler_id,
   'group','micro_engine','state',a.state,'pinned_version',a.pinned_version,
   'descriptor',v.descriptor,'params',a.params,
   'effective',CASE WHEN e.handler_id='threshold_rule_v1' THEN jsonb_build_object(
      'field',v.descriptor->>'field','op',v.descriptor->>'op',
      'threshold',COALESCE((a.params->>'threshold')::numeric,(v.descriptor->>'threshold')::numeric),
      'outcome',COALESCE(a.params->>'outcome',v.descriptor->>'outcome')) ELSE NULL END,
   'placement',a.placement,'local_edit_mode',a.local_edit_mode,
   'preferred_enabled',a.state='PUBLISHED','version',a.version,'can_execute',h.can_execute,'advisory_only',true
  ) ORDER BY e.id),'[]'::jsonb)
  FROM c10_demo.micro_engine_assignments_v1 a
  JOIN c10_demo.micro_engines_v1 e ON e.id=a.engine_id AND e.tenant_id=a.tenant_id
  JOIN c10_demo.micro_engine_versions_v1 v ON v.engine_id=a.engine_id AND v.version=a.pinned_version
  JOIN c10_demo.micro_engine_handlers_v1 h ON h.handler_id=e.handler_id
  WHERE a.business_id=p_business AND a.tenant_id=t
    AND (owner OR (a.state<>'REVOKED' AND a.placement IN('business_only','both')))));
END$$;
-- Non-mutating advisory preview of the PUBLISHED, version-pinned rule for ONE business.
CREATE FUNCTION c10_demo.preview_business_engine_v1(p_engine bigint,p_business bigint,p_inputs jsonb) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE t bigint; a c10_demo.micro_engine_assignments_v1%ROWTYPE; v c10_demo.micro_engine_versions_v1%ROWTYPE;
 e c10_demo.micro_engines_v1%ROWTYPE; owner boolean;
BEGIN
 SELECT tenant_id INTO t FROM c10_demo.businesses WHERE id=p_business;
 IF c10_demo.actor_uid() IS NULL OR t IS NULL OR NOT c10_demo.can_manage(t,p_business) THEN RAISE EXCEPTION 'engine_denied'; END IF;
 owner:=c10_demo.can_tenant(t);
 SELECT * INTO a FROM c10_demo.micro_engine_assignments_v1 WHERE engine_id=p_engine AND business_id=p_business AND tenant_id=t;
 IF NOT FOUND OR (NOT owner AND (a.state='REVOKED' OR a.placement NOT IN('business_only','both'))) THEN RAISE EXCEPTION 'engine_denied'; END IF;
 IF a.state<>'PUBLISHED' THEN RAISE EXCEPTION 'engine_not_published'; END IF;
 SELECT * INTO e FROM c10_demo.micro_engines_v1 WHERE id=p_engine;
 SELECT * INTO v FROM c10_demo.micro_engine_versions_v1 WHERE engine_id=p_engine AND version=a.pinned_version;
 IF v.descriptor_hash<>md5(v.descriptor::text) THEN RAISE EXCEPTION 'engine_integrity_failed'; END IF;
 IF e.handler_id<>'threshold_rule_v1' THEN RAISE EXCEPTION 'handler_not_executable'; END IF;
 RETURN c10_demo.engine_eval_threshold_v1(v.descriptor,a.params,p_inputs)
   || jsonb_build_object('engine_id',p_engine,'business_id',p_business,'version',v.version);
END$$;
CREATE FUNCTION c10_demo.read_engine_pending_v1(p_tenant bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
BEGIN
 IF c10_demo.actor_uid() IS NULL OR p_tenant IS NULL OR NOT c10_demo.can_tenant(p_tenant) THEN RAISE EXCEPTION 'engine_denied'; END IF;
 RETURN jsonb_build_object('tenant_id',p_tenant,'items',(SELECT COALESCE(jsonb_agg(jsonb_build_object(
  'request_id',id,'engine_id',engine_id,'business_id',business_id,'target_params',target_params,
  'expected_version',expected_version,'reason',reason,'created_at',created_at) ORDER BY id),'[]'::jsonb)
  FROM c10_demo.micro_engine_requests_v1 WHERE tenant_id=p_tenant AND status='pending'));
END$$;

-- Internal helpers must not be callable by app roles.
REVOKE ALL ON FUNCTION c10_demo.engine_receipt_v1(bigint,text,jsonb),
 c10_demo.engine_record_v1(bigint,text,jsonb,jsonb),
 c10_demo.engine_audit_v1(bigint,bigint,bigint,text,jsonb,jsonb,text),
 c10_demo.engine_owner_lock_v1(bigint),c10_demo.engine_check_req_v1(text,text),
 c10_demo.engine_descriptor_ok_v1(text,jsonb) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION
 c10_demo.save_engine_draft_v1(bigint,text,text,text,jsonb,int,text,text),
 c10_demo.validate_engine_version_v1(bigint,int,text,text),
 c10_demo.preview_engine_draft_v1(bigint,text,jsonb,jsonb,jsonb),
 c10_demo.assign_engine_v1(bigint,bigint,int,text,jsonb,text,text,bigint,text,text),
 c10_demo.edit_engine_params_v1(bigint,bigint,jsonb,bigint,text,text),
 c10_demo.decide_engine_request_v1(bigint,text),
 c10_demo.rollback_engine_assignment_v1(bigint,bigint,bigint,bigint,text,text),
 c10_demo.read_engines_v1(bigint),c10_demo.read_engine_audit_v1(bigint),
 c10_demo.read_business_engines_v1(bigint),c10_demo.preview_business_engine_v1(bigint,bigint,jsonb),
 c10_demo.read_engine_pending_v1(bigint) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION
 c10_demo.save_engine_draft_v1(bigint,text,text,text,jsonb,int,text,text),
 c10_demo.validate_engine_version_v1(bigint,int,text,text),
 c10_demo.preview_engine_draft_v1(bigint,text,jsonb,jsonb,jsonb),
 c10_demo.assign_engine_v1(bigint,bigint,int,text,jsonb,text,text,bigint,text,text),
 c10_demo.edit_engine_params_v1(bigint,bigint,jsonb,bigint,text,text),
 c10_demo.decide_engine_request_v1(bigint,text),
 c10_demo.rollback_engine_assignment_v1(bigint,bigint,bigint,bigint,text,text),
 c10_demo.read_engines_v1(bigint),c10_demo.read_engine_audit_v1(bigint),
 c10_demo.read_business_engines_v1(bigint),c10_demo.preview_business_engine_v1(bigint,bigint,jsonb),
 c10_demo.read_engine_pending_v1(bigint) TO authenticated;
-- NO direct table DML grants. No stock/finance/payment/sales table is referenced by this file.
