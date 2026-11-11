-- C10-A053 Workforce integration: stable A046 persona registry, staff identity link, Owner Portfolio (A050) -> Workforce (A051) READ adapter.
-- DISPOSABLE c10_demo ONLY. Loads with or WITHOUT A051/A054: missing contracts report NOT_CONNECTED, never synthetic payroll.
-- Never grants new authority: all workforce authority stays in A051 (DB-derived memberships). No money movement of any kind.
DO $gate$ BEGIN
 IF current_database() !~ '^core10_a0(46|48|53)_(ci|local)' THEN RAISE EXCEPTION 'A053_DISPOSABLE_DB_REQUIRED'; END IF;
 IF to_regprocedure('c10_demo.can_manage(bigint,bigint)') IS NULL THEN RAISE EXCEPTION 'A053_REQUIRES_A018'; END IF;
END $gate$;
CREATE FUNCTION c10_demo.a053i_immutable() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'a053_append_only_registry'; END$$;
CREATE TABLE c10_demo.a053_persona_registry(
 alias_key text PRIMARY KEY CHECK(alias_key ~ '^[A-Z][A-Z0-9_]+$'),
 uid uuid NOT NULL UNIQUE,
 source text NOT NULL CHECK(source IN('A046_REGISTRY','A051_FIXTURE_ONLY')),
 a046_key text, tenant_id bigint, business_ids bigint[] NOT NULL DEFAULT '{}',
 active boolean NOT NULL, linkable boolean NOT NULL,
 CHECK((source='A046_REGISTRY')=(a046_key IS NOT NULL AND a046_key=alias_key))
);
-- Append-only: an alias can never be re-pointed to another UUID (no silent reassignment).
CREATE TRIGGER a053_persona_immutable BEFORE UPDATE OR DELETE ON c10_demo.a053_persona_registry FOR EACH ROW EXECUTE FUNCTION c10_demo.a053i_immutable();
INSERT INTO c10_demo.a053_persona_registry(alias_key,uid,source,a046_key,tenant_id,business_ids,active,linkable) VALUES
('TENANT_OWNER_A','11111111-1111-4111-8111-111111111111','A046_REGISTRY','TENANT_OWNER_A',1,'{101,102}',true,true),
('BUSINESS_OWNER_A','22222222-2222-4222-8222-222222222222','A046_REGISTRY','BUSINESS_OWNER_A',1,'{101}',true,true),
('MANAGER_A','33333333-3333-4333-8333-333333333333','A046_REGISTRY','MANAGER_A',1,'{101}',true,true),
('COUNTER_STAFF_A','44444444-4444-4444-8444-444444444444','A046_REGISTRY','COUNTER_STAFF_A',1,'{101}',true,true),
('INVESTOR_A','55555555-5555-4555-8555-555555555555','A046_REGISTRY','INVESTOR_A',1,'{}',true,false),
('REVOKED_MANAGER_A','66666666-6666-4666-8666-666666666666','A046_REGISTRY','REVOKED_MANAGER_A',1,'{}',false,false),
('TENANT_OWNER_B','77777777-7777-4777-8777-777777777777','A046_REGISTRY','TENANT_OWNER_B',2,'{201}',true,true),
('INDEPENDENT_STAFF_B','88888888-8888-4888-8888-888888888888','A046_REGISTRY','INDEPENDENT_STAFF_B',2,'{201}',true,true),
('PLATFORM_OPERATOR','99999999-9999-4999-8999-999999999999','A046_REGISTRY','PLATFORM_OPERATOR',NULL,'{}',true,false),
('BUSINESS_OWNER_B','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','A046_REGISTRY','BUSINESS_OWNER_B',1,'{102}',true,true),
('MANAGER_BUSINESS_B','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','A046_REGISTRY','MANAGER_BUSINESS_B',1,'{102}',true,true),
('FACTORY_STAFF_A','cccccccc-cccc-4ccc-8ccc-cccccccccccc','A046_REGISTRY','FACTORY_STAFF_A',1,'{101}',true,true),
('BRANCH_STAFF_B','dddddddd-dddd-4ddd-8ddd-dddddddddddd','A046_REGISTRY','BRANCH_STAFF_B',1,'{102}',true,true),
('UNASSIGNED_USER','eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee','A046_REGISTRY','UNASSIGNED_USER',NULL,'{}',true,true),
('REVIEWER_NOT_ASSIGNED','ffffffff-ffff-4fff-8fff-ffffffffffff','A046_REGISTRY','REVIEWER_NOT_ASSIGNED',NULL,'{}',true,false),
('PARTNER_NO_GRANT','90909090-9090-4090-8090-909090909090','A046_REGISTRY','PARTNER_NO_GRANT',1,'{}',true,false),
('A051_SUPERVISOR_A','a1111111-1111-4111-8111-111111111111','A051_FIXTURE_ONLY',NULL,1,'{}',true,true),
('A051_STAFF_MONTHLY_A','a2222222-2222-4222-8222-222222222222','A051_FIXTURE_ONLY',NULL,1,'{}',true,true),
('A051_STAFF_DAILY_A','a3333333-3333-4333-8333-333333333333','A051_FIXTURE_ONLY',NULL,1,'{}',true,true),
('A051_STAFF_TERMINATED_A','a5555555-5555-4555-8555-555555555555','A051_FIXTURE_ONLY',NULL,1,'{}',true,true),
('A051_STAFF_NIGHT_A','a6666666-6666-4666-8666-666666666666','A051_FIXTURE_ONLY',NULL,1,'{}',true,true),
('A051_MANAGER_102','b1111111-1111-4111-8111-111111111111','A051_FIXTURE_ONLY',NULL,1,'{102}',true,true),
('A051_BUSINESS_OWNER_102','b2222222-2222-4222-8222-222222222222','A051_FIXTURE_ONLY',NULL,1,'{102}',true,true),
('A051_BUSINESS_OWNER_201','c1111111-1111-4111-8111-111111111111','A051_FIXTURE_ONLY',NULL,2,'{201}',true,true),
('A051_STAFF_B','c2222222-2222-4222-8222-222222222222','A051_FIXTURE_ONLY',NULL,2,'{}',true,true);
-- A051 short fixture names -> alias (existing meanings preserved; the 9 A018 UUIDs ARE the A046 personas).
CREATE TABLE c10_demo.a053_a051_alias_map(a051_name text PRIMARY KEY,alias_key text NOT NULL REFERENCES c10_demo.a053_persona_registry(alias_key));
INSERT INTO c10_demo.a053_a051_alias_map VALUES('owner','TENANT_OWNER_A'),('bo101','BUSINESS_OWNER_A'),('mgr101','MANAGER_A'),('e4','COUNTER_STAFF_A'),
 ('investor','INVESTOR_A'),('revoked','REVOKED_MANAGER_A'),('owner2','TENANT_OWNER_B'),('staff2','INDEPENDENT_STAFF_B'),('operator','PLATFORM_OPERATOR'),
 ('sup','A051_SUPERVISOR_A'),('e1','A051_STAFF_MONTHLY_A'),('e3','A051_STAFF_DAILY_A'),('e5','A051_STAFF_TERMINATED_A'),('e6','A051_STAFF_NIGHT_A'),
 ('mgr102','A051_MANAGER_102'),('bo102','A051_BUSINESS_OWNER_102'),('bo201','A051_BUSINESS_OWNER_201'),('emp201','A051_STAFF_B');
CREATE TRIGGER a053_map_immutable BEFORE UPDATE OR DELETE ON c10_demo.a053_a051_alias_map FOR EACH ROW EXECUTE FUNCTION c10_demo.a053i_immutable();

-- Fail-closed resolver: unknown alias is an error, never an auto-created or guessed identity.
CREATE FUNCTION c10_demo.a053i_alias(p_alias text) RETURNS c10_demo.a053_persona_registry LANGUAGE plpgsql STABLE AS $$
DECLARE r c10_demo.a053_persona_registry;
BEGIN
 SELECT * INTO r FROM c10_demo.a053_persona_registry WHERE alias_key=p_alias;
 IF NOT FOUND THEN RAISE EXCEPTION 'a053_alias_unmapped'; END IF;
 RETURN r;
END$$;

-- Tenant owners see aliases of their own tenant (+ tenant-less personas). UUIDs are never returned.
CREATE FUNCTION c10_demo.a053_persona_catalog_v1() RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
BEGIN
 IF actor_uid() IS NULL THEN RAISE EXCEPTION 'a053_signed_user_required'; END IF;
 IF NOT EXISTS(SELECT 1 FROM tenant_members m WHERE m.user_id=actor_uid() AND m.role='tenant_owner' AND m.active) THEN RAISE EXCEPTION 'a053_owner_required'; END IF;
 RETURN jsonb_build_object('server_authorized',true,'items',(SELECT COALESCE(jsonb_agg(jsonb_build_object('alias',r.alias_key,'source',r.source,'tenant_id',r.tenant_id,
  'business_ids',to_jsonb(r.business_ids),'active',r.active,'linkable',r.linkable) ORDER BY r.alias_key),'[]') FROM a053_persona_registry r
  WHERE r.tenant_id IS NULL OR can_tenant(r.tenant_id)));
END$$;

-- ===== Staff identity: owner-only link of an employee record to a registered (never guessed) identity =====
CREATE FUNCTION c10_demo.a053_link_staff_identity_v1(p_business bigint,p_request text,p_employee bigint,p_alias text,p_reason text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c record; pay jsonb; a a053_persona_registry; e record; res jsonb;
BEGIN
 IF to_regclass('c10_demo.wf_employees') IS NULL THEN RAISE EXCEPTION 'a053_not_connected'; END IF;
 IF p_employee IS NULL OR p_alias IS NULL OR p_reason IS NULL OR length(btrim(p_reason)) NOT BETWEEN 3 AND 500 THEN RAISE EXCEPTION 'wf_invalid_input'; END IF;
 pay:=jsonb_build_object('e',p_employee,'a',p_alias,'r',btrim(p_reason));
 SELECT * INTO b FROM wfi_begin(p_business,p_request,'a053_link_identity',pay);
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 c:=b.o_ctx; PERFORM wfi_need(wfi_is_owner(c),'a053_owner_required');
 a:=a053i_alias(p_alias);
 IF NOT a.linkable OR NOT a.active THEN RAISE EXCEPTION 'a053_alias_not_linkable'; END IF;
 IF a.tenant_id IS NOT NULL AND a.tenant_id<>c.tenant_id THEN RAISE EXCEPTION 'a053_alias_cross_tenant'; END IF;
 IF cardinality(a.business_ids)>0 AND NOT p_business=ANY(a.business_ids) THEN RAISE EXCEPTION 'a053_alias_scope_mismatch'; END IF;
 SELECT id,status,user_id INTO e FROM wf_employees WHERE id=p_employee AND business_id=p_business FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'wf_employee_not_found'; END IF;
 IF e.status<>'active' THEN RAISE EXCEPTION 'wf_employee_not_active'; END IF;
 IF e.user_id IS NOT NULL THEN RAISE EXCEPTION 'a053_employee_already_linked'; END IF;
 IF EXISTS(SELECT 1 FROM wf_employees WHERE business_id=p_business AND user_id=a.uid) THEN RAISE EXCEPTION 'wf_user_already_linked'; END IF;
 UPDATE wf_employees SET user_id=a.uid,version=version+1,updated_at=now() WHERE id=p_employee;
 res:=jsonb_build_object('status','linked','employee_id',p_employee,'alias',a.alias_key,'grants_workforce_access','self_service_only');
 PERFORM wfi_log(c.tenant_id,p_business,'a053_staff_identity',p_employee::text,'linked',NULL,res,p_reason,p_request);
 RETURN wfi_finish(p_business,c.tenant_id,p_request,'a053_link_identity',pay,res);
END$$;
CREATE FUNCTION c10_demo.a053_unlink_staff_identity_v1(p_business bigint,p_request text,p_employee bigint,p_reason text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE b record; c record; pay jsonb; e record; res jsonb;
BEGIN
 IF to_regclass('c10_demo.wf_employees') IS NULL THEN RAISE EXCEPTION 'a053_not_connected'; END IF;
 IF p_employee IS NULL OR p_reason IS NULL OR length(btrim(p_reason)) NOT BETWEEN 3 AND 500 THEN RAISE EXCEPTION 'wf_invalid_input'; END IF;
 pay:=jsonb_build_object('e',p_employee,'r',btrim(p_reason));
 SELECT * INTO b FROM wfi_begin(p_business,p_request,'a053_unlink_identity',pay);
 IF b.o_replay IS NOT NULL THEN RETURN b.o_replay; END IF;
 c:=b.o_ctx; PERFORM wfi_need(wfi_is_owner(c),'a053_owner_required');
 SELECT id,user_id INTO e FROM wf_employees WHERE id=p_employee AND business_id=p_business FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'wf_employee_not_found'; END IF;
 IF e.user_id IS NULL THEN RAISE EXCEPTION 'a053_employee_not_linked'; END IF;
 UPDATE wf_employees SET user_id=NULL,version=version+1,updated_at=now() WHERE id=p_employee;
 res:=jsonb_build_object('status','unlinked','employee_id',p_employee);
 PERFORM wfi_log(c.tenant_id,p_business,'a053_staff_identity',p_employee::text,'unlinked',NULL,res,p_reason,p_request);
 RETURN wfi_finish(p_business,c.tenant_id,p_request,'a053_unlink_identity',pay,res);
END$$;

-- Directory of staff identity + business/site assignment. No salary, no phone, no uid. Alias visible to owners only.
CREATE FUNCTION c10_demo.a053_staff_overview_v1(p_business bigint) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE c record; own boolean; today date;
BEGIN
 IF to_regclass('c10_demo.wf_employees') IS NULL THEN RAISE EXCEPTION 'a053_not_connected'; END IF;
 today:=wfi_today(); c:=wfi_ctx(p_business); own:=wfi_is_owner(c); PERFORM wfi_need(wfi_is_manager_plus(c),'a053_manager_required');
 RETURN jsonb_build_object('server_authorized',true,'business_id',p_business,'items',(SELECT COALESCE(jsonb_agg(jsonb_build_object('employee_id',e.id,
  'employee_no',e.employee_no,'full_name',CASE WHEN own THEN e.full_name ELSE wfi_mask_name(e.full_name) END,'status',e.status,
  'site_id',wfi_site_of(e.id,today),'site_label',(SELECT label FROM sites WHERE id=wfi_site_of(e.id,today)),
  'identity_linked',e.user_id IS NOT NULL,'identity_alias',CASE WHEN own THEN (SELECT r.alias_key FROM a053_persona_registry r WHERE r.uid=e.user_id) END,
  'works_in_other_businesses',CASE WHEN own AND e.user_id IS NOT NULL THEN (SELECT count(*) FROM wf_employees o WHERE o.user_id=e.user_id AND o.business_id<>e.business_id AND o.tenant_id=e.tenant_id) END)
  ORDER BY e.employee_no),'[]') FROM wf_employees e WHERE e.business_id=p_business));
END$$;

-- The caller's own assignments across businesses/sites (self view; no salary).
CREATE FUNCTION c10_demo.a053_my_assignments_v1() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
BEGIN
 IF actor_uid() IS NULL THEN RAISE EXCEPTION 'a053_signed_user_required'; END IF;
 IF to_regclass('c10_demo.wf_employees') IS NULL THEN RETURN jsonb_build_object('server_authorized',true,'state','NOT_CONNECTED','items','[]'::jsonb); END IF;
 RETURN jsonb_build_object('server_authorized',true,'state','CONNECTED','items',(SELECT COALESCE(jsonb_agg(jsonb_build_object('business_id',e.business_id,
  'employee_no',e.employee_no,'site_id',wfi_site_of(e.id,wfi_today()),'site_label',(SELECT label FROM sites WHERE id=wfi_site_of(e.id,wfi_today())),
  'designation',(SELECT designation FROM wf_assignments a WHERE a.employee_id=e.id AND a.effective_from<=wfi_today() ORDER BY a.effective_from DESC,a.id DESC LIMIT 1),
  'is_supervisor',COALESCE((SELECT a.is_supervisor FROM wf_assignments a WHERE a.employee_id=e.id AND a.effective_from<=wfi_today() ORDER BY a.effective_from DESC,a.id DESC LIMIT 1),false)) ORDER BY e.business_id),'[]') FROM wf_employees e WHERE e.user_id=actor_uid() AND e.status='active'));
END$$;
-- ===== Owner Portfolio (A050) -> Workforce (A051) READ adapter =====
-- Owner-only per business. Every figure comes from the A051 server guards (read_workforce_business_summary_v1 /
-- read_payroll_liability_preview_v1) and is VERIFIED here (business id, month, counts, paid/ledger/money flags) before it is shown.
-- Missing migration => state NOT_CONNECTED with no numbers. Non-owners (managers, investors, staff) get OWNER_ONLY and no data.
CREATE FUNCTION c10_demo.a053_read_portfolio_workforce_v1(p_period date) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=c10_demo,pg_catalog AS $$
DECLARE per date:=COALESCE(p_period,date_trunc('month',now() AT TIME ZONE 'Asia/Dhaka')::date); wf boolean; pf boolean; l54 boolean;
 pj jsonb; b record; s jsonb; l jsonb; a jsonb; entry jsonb; items jsonb:='[]'; pe jsonb; hc int; sumsites int; bad text; contracts jsonb;
BEGIN
 IF actor_uid() IS NULL THEN RAISE EXCEPTION 'a053_signed_user_required'; END IF;
 IF extract(day FROM per)<>1 THEN RAISE EXCEPTION 'a053_invalid_period'; END IF;
 wf:=to_regprocedure('c10_demo.read_workforce_business_summary_v1(bigint,date)') IS NOT NULL
  AND to_regprocedure('c10_demo.read_payroll_liability_preview_v1(bigint,date)') IS NOT NULL;
 pf:=to_regprocedure('c10_demo.read_portfolio_workspace_v1()') IS NOT NULL;
 l54:=to_regprocedure('c10_demo.a054_liability_report_v1(bigint,date)') IS NOT NULL;
 contracts:=jsonb_build_object('A050_portfolio',CASE WHEN pf THEN 'CONNECTED' ELSE 'NOT_CONNECTED' END,'A051_workforce',CASE WHEN wf THEN 'CONNECTED' ELSE 'NOT_CONNECTED' END,
  'A054_payment_tracking',CASE WHEN l54 THEN 'CONNECTED' ELSE 'NOT_CONNECTED' END);
 IF NOT wf THEN
  RETURN jsonb_build_object('server_authorized',true,'state','NOT_CONNECTED','reason','A051 Workforce migration is not installed in this database; no figures are shown or invented.',
   'period',per,'contracts',contracts,'businesses','[]'::jsonb,'paid',false,'money_movement',false,'ledger_posted',false);
 END IF;
 IF pf THEN EXECUTE 'SELECT c10_demo.read_portfolio_workspace_v1()' INTO pj; END IF;
 FOR b IN SELECT id,tenant_id,slug FROM businesses WHERE can_see_business(tenant_id,id) ORDER BY id LOOP
  pe:=COALESCE((SELECT x FROM jsonb_array_elements(COALESCE(pj->'businesses','[]')) x WHERE (x->>'business_id')::bigint=b.id),'{}');
  entry:=jsonb_build_object('business_id',b.id,'tenant_id',b.tenant_id,'name',COALESCE(pe->>'name',b.slug),'portfolio_sites',COALESCE(pe->'sites','[]'));
  IF NOT can_manage(b.tenant_id,b.id) THEN
   items:=items||jsonb_build_array(entry||jsonb_build_object('state','OWNER_ONLY','workforce',NULL,'liability',NULL)); CONTINUE; END IF;
  BEGIN
   EXECUTE 'SELECT c10_demo.read_workforce_business_summary_v1($1,$2)' INTO s USING b.id,per;
   EXECUTE 'SELECT c10_demo.read_payroll_liability_preview_v1($1,$2)' INTO l USING b.id,per;
   bad:=NULL;
   IF (s->>'business_id')::bigint IS DISTINCT FROM b.id OR (l->>'business_id')::bigint IS DISTINCT FROM b.id THEN bad:='business_mismatch'; END IF;
   IF (s->>'period')::date IS DISTINCT FROM per OR (l->>'period')::date IS DISTINCT FROM per THEN bad:='period_mismatch'; END IF;
   IF s->>'paid' IS DISTINCT FROM 'false' OR s->>'ledger_posted' IS DISTINCT FROM 'false' OR s->>'money_movement' IS DISTINCT FROM 'false'
    OR l->>'paid' IS DISTINCT FROM 'false' OR l->>'ledger_posted' IS DISTINCT FROM 'false' OR l->>'money_movement' IS DISTINCT FROM 'false' THEN bad:='money_flags'; END IF;
   hc:=(s->>'active_headcount')::int;
   SELECT COALESCE(sum((x->>'n')::int),0) INTO sumsites FROM jsonb_array_elements(s->'headcount_by_site') x;
   IF hc IS NULL OR sumsites<>hc THEN bad:='headcount_mismatch'; END IF;
   IF bad IS NOT NULL THEN
    items:=items||jsonb_build_array(entry||jsonb_build_object('state','CONTRACT_VIOLATION','violation',bad,'workforce',NULL,'liability',NULL)); CONTINUE; END IF;
   a:=NULL;
   IF l54 THEN EXECUTE 'SELECT c10_demo.a054_liability_report_v1($1,$2)' INTO a USING b.id,per; END IF;
   items:=items||jsonb_build_array(entry||jsonb_build_object('state','OK','workforce',jsonb_build_object('active_headcount',hc,
    'headcount_by_site',s->'headcount_by_site','payroll',s->'payroll'),
    'liability',jsonb_build_object('state',l->>'state','approval_basis',l->>'basis','run_id',l->'run_id','net_approved_preview',l->'net_payable_preview',
     'gross_preview',l->'gross_payable_preview','paid',false,'money_movement',false,'ledger_posted',false,
     'payment_tracking',CASE WHEN l54 THEN 'CONNECTED' ELSE 'NOT_CONNECTED' END,
     'approved_unpaid',CASE WHEN a IS NULL THEN NULL ELSE a->'totals' END,'pre_approval',CASE WHEN a IS NULL THEN NULL ELSE a->'pre_approval' END)));
  EXCEPTION WHEN OTHERS THEN
   items:=items||jsonb_build_array(entry||jsonb_build_object('state','DENIED','workforce',NULL,'liability',NULL));
  END;
 END LOOP;
 RETURN jsonb_build_object('server_authorized',true,'state','CONNECTED','period',per,'contracts',contracts,'businesses',items,
  'paid',false,'money_movement',false,'ledger_posted',false,
  'note','Approved is not paid. Salary liability is shown to owners only; this adapter never moves money.');
END$$;

DO $$
DECLARE t record; f record;
BEGIN
 FOR t IN SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='c10_demo' AND c.relkind='r' AND c.relname LIKE 'a053\_%' LOOP
  EXECUTE format('ALTER TABLE c10_demo.%I ENABLE ROW LEVEL SECURITY',t.relname);
  EXECUTE format('REVOKE ALL ON c10_demo.%I FROM PUBLIC,anon,authenticated',t.relname);
 END LOOP;
 FOR f IN SELECT p.oid::regprocedure AS sig,p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='c10_demo' AND p.proname LIKE 'a053%' LOOP
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated',f.sig);
  IF f.proname ~ '^a053_.*_v1$' THEN EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated',f.sig); END IF;
 END LOOP;
END$$;
GRANT USAGE ON SCHEMA c10_demo TO authenticated;
