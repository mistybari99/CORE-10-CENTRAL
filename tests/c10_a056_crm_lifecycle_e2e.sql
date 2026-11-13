\set ON_ERROR_STOP on
-- C10-A056 CRM lifecycle: authz/RLS positive+negative, journey, privacy. Disposable PG only. Synthetic identities (A046-compatible UUIDs).
DO $g$ BEGIN IF current_database() !~ '^core10_a048_(ci|local)' THEN RAISE EXCEPTION 'A056_TEST_DISPOSABLE_ONLY'; END IF; END $g$;
-- test helpers (public schema, test DB only)
CREATE TABLE public.a056_t_ids(k text PRIMARY KEY,v bigint);
GRANT ALL ON public.a056_t_ids TO authenticated,anon;
CREATE FUNCTION public.id(k text) RETURNS bigint LANGUAGE sql STABLE AS $$ SELECT v FROM public.a056_t_ids WHERE a056_t_ids.k=$1 $$;
CREATE FUNCTION public.sv(k text,v bigint) RETURNS bigint LANGUAGE sql AS $$ INSERT INTO public.a056_t_ids VALUES($1,$2) ON CONFLICT(k) DO UPDATE SET v=$2 RETURNING v $$;
CREATE FUNCTION public.as_user(u text) RETURNS void LANGUAGE sql AS $$ SELECT set_config('request.jwt.claim.sub',u,true) $$;
CREATE FUNCTION public.q(sql text) RETURNS jsonb LANGUAGE plpgsql AS $$ DECLARE r jsonb; BEGIN EXECUTE sql INTO r; RETURN r; END $$;
CREATE FUNCTION public.x(sql text,code text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 BEGIN EXECUTE sql; EXCEPTION WHEN OTHERS THEN
  IF SQLERRM NOT LIKE code||'%' THEN RAISE EXCEPTION 'WRONG_ERROR expected [%] got [%] for %',code,SQLERRM,sql; END IF; RETURN; END;
 RAISE EXCEPTION 'EXPECTED_FAILURE_DID_NOT_HAPPEN % for %',code,sql;
END $$;
CREATE FUNCTION public.ok(c boolean,msg text) RETURNS void LANGUAGE plpgsql AS $$ BEGIN IF c IS NOT TRUE THEN RAISE EXCEPTION 'ASSERT_FAILED: %',msg; END IF; END $$;
CREATE FUNCTION public.sq(sql text) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER AS $$ DECLARE r bigint; BEGIN EXECUTE sql INTO r; RETURN r; END $$;
CREATE FUNCTION public.dc() RETURNS jsonb LANGUAGE sql SECURITY DEFINER AS $$ SELECT c10_demo.a056_default_config() $$;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated,anon;

-- personas: 1111 tenant owner T1; 2222 biz owner 101; 3333 manager 101; 4444 site staff 1001; cccc read grant site 1002; 5555 investor; 6666 inactive manager;
-- aaaa biz owner 102; dddd site 1003 (biz 102); 7777 tenant owner T2; 8888 site 2001 (T2)
INSERT INTO c10_demo.business_members(tenant_id,business_id,user_id,role,active) VALUES
 (1,102,'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','business_owner',true),(1,102,'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','manager',true) ON CONFLICT DO NOTHING;
INSERT INTO c10_demo.site_grants(tenant_id,business_id,site_id,user_id,actions,active) VALUES
 (1,101,1002,'cccccccc-cccc-4ccc-8ccc-cccccccccccc',ARRAY['stock.read'],true),(1,102,1003,'dddddddd-dddd-4ddd-8ddd-dddddddddddd',ARRAY['stock.read'],true) ON CONFLICT DO NOTHING;
INSERT INTO c10_demo.sites(id,tenant_id,business_id,kind,label,request_key) VALUES (2002,2,201,'showroom','B2','seed-t2') ON CONFLICT DO NOTHING;

-- ===== 0. static security surface =====
DO $s$ BEGIN
 PERFORM public.ok((SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='c10_demo' AND c.relkind='r' AND c.relname LIKE 'a056\_%' AND NOT c.relrowsecurity)=0,'RLS on every a056 table');
 PERFORM public.ok((SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='c10_demo' AND c.relkind='r' AND c.relname LIKE 'a056\_%'
   AND (has_table_privilege('authenticated',c.oid,'INSERT') OR has_table_privilege('authenticated',c.oid,'UPDATE') OR has_table_privilege('authenticated',c.oid,'DELETE') OR has_table_privilege('anon',c.oid,'SELECT')))=0,'no direct writes / anon reads');
 PERFORM public.ok(NOT has_table_privilege('authenticated','c10_demo.a056_idem','SELECT') AND NOT has_table_privilege('authenticated','c10_demo.a056_suppressions','SELECT') AND NOT has_table_privilege('authenticated','c10_demo.a056_intake_endpoints','SELECT'),'sensitive tables closed');
 PERFORM public.ok(NOT has_function_privilege('authenticated','c10_demo.a056_hist(bigint,bigint,bigint,bigint,text,text,text,text,bigint,bigint,timestamptz)','EXECUTE') AND NOT has_function_privilege('authenticated','c10_demo.a056_convert_core(bigint,int,bigint,text,boolean)','EXECUTE'),'internal helpers closed');
 PERFORM public.ok(has_function_privilege('anon','c10_demo.a056_public_intake_v1(text,text,jsonb)','EXECUTE') AND NOT has_function_privilege('anon','c10_demo.a056_create_customer_v1(bigint,bigint,text,text,text,text,text,text[],text)','EXECUTE'),'anon only public intake');
END $s$;

-- ===== 1. module off, settings versioning =====
BEGIN; SET LOCAL ROLE authenticated; SELECT public.as_user('11111111-1111-4111-8111-111111111111');
DO $t$ DECLARE d jsonb; BEGIN
 d:=c10_demo.a056_read_settings_v1(101); PERFORM public.ok((d->>'enabled')='false' AND (d->>'version')='0','module OFF by default');
 PERFORM public.x('SELECT c10_demo.a056_create_customer_v1(101,1001,''person'',''X'',NULL,NULL,NULL,NULL,''req-disabled-01'')','A056_MODULE_DISABLED');
 PERFORM public.x($q$SELECT c10_demo.a056_set_settings_v1(101,true,jsonb_set(public.dc(),'{permissions,settings.write}','"site"'),0,'cfg-bad-0001','x')$q$,'A056_CONFIG_INVARIANT');
 PERFORM public.x($q$SELECT c10_demo.a056_set_settings_v1(101,true,jsonb_set(public.dc(),'{stages}','[{"code":"a","label":"A","kind":"open"}]'),0,'cfg-bad-0002','x')$q$,'A056_CONFIG_INVALID');
 PERFORM public.x($q$SELECT c10_demo.a056_set_settings_v1(101,true,jsonb_set(public.dc(),'{permissions,customer.redact}','"manager"'),0,'cfg-bad-0003','x')$q$,'A056_CONFIG_INVARIANT');
 d:=c10_demo.a056_set_settings_v1(101,true,NULL,0,'enable-101-001','enable CRM'); PERFORM public.ok(d->>'version'='1','enable v1');
 d:=c10_demo.a056_set_settings_v1(101,true,NULL,0,'enable-101-001','enable CRM'); PERFORM public.ok(d->>'replayed'='true','settings replay');
 PERFORM public.x('SELECT c10_demo.a056_set_settings_v1(101,false,NULL,0,''enable-101-001'',''other'')','A056_REQUEST_REPLAY_CONFLICT');
 PERFORM public.x('SELECT c10_demo.a056_set_settings_v1(101,true,NULL,0,''enable-101-002'',''stale'')','A056_STALE_SETTINGS');
 d:=c10_demo.a056_set_settings_v1(102,true,NULL,0,'enable-102-001','enable CRM'); 
 PERFORM public.ok(jsonb_array_length(c10_demo.a056_list_settings_history_v1(101)->'items')=1,'settings history');
END $t$; COMMIT;
BEGIN; SET LOCAL ROLE authenticated; SELECT public.as_user('33333333-3333-4333-8333-333333333333');
DO $t$ BEGIN PERFORM public.x('SELECT c10_demo.a056_set_settings_v1(101,true,NULL,1,''mgr-cfg-0001'',''x'')','A056_DENIED');
 PERFORM public.ok((c10_demo.a056_read_my_access_v1(101)->'actions'->>'customer.merge')='true' AND (c10_demo.a056_read_my_access_v1(101)->'actions'->>'settings.write')='false','my access'); END $t$; COMMIT;
BEGIN; SET LOCAL ROLE authenticated; SELECT public.as_user('77777777-7777-4777-8777-777777777777');
DO $t$ BEGIN PERFORM c10_demo.a056_set_settings_v1(201,true,NULL,0,'enable-201-001','T2 enable'); END $t$; COMMIT;

-- ===== 2. customers, site isolation, tenant isolation, injection =====
BEGIN; SET LOCAL ROLE authenticated; SELECT public.as_user('33333333-3333-4333-8333-333333333333');
DO $t$ DECLARE d jsonb; BEGIN
 d:=c10_demo.a056_create_customer_v1(101,1001,'organization','Acme Paints Ltd','Acme Paints Limited','Sales@Acme.example','+880 1711-000001',ARRAY['vip','b2b'],'cust-c1-0001'); PERFORM public.sv('c1',(d->>'customer_id')::bigint);
 d:=c10_demo.a056_create_customer_v1(101,1001,'organization','Acme Paints Ltd','Acme Paints Limited','Sales@Acme.example','+880 1711-000001',ARRAY['vip','b2b'],'cust-c1-0001'); PERFORM public.ok(d->>'replayed'='true' AND d->>'customer_id'=public.id('c1')::text,'create replay') ;
END $t$; COMMIT;
BEGIN; SET LOCAL ROLE authenticated; SELECT public.as_user('33333333-3333-4333-8333-333333333333');
DO $t$ DECLARE d jsonb; BEGIN
 PERFORM public.x('SELECT c10_demo.a056_create_customer_v1(101,1001,''organization'',''Other'',NULL,NULL,NULL,NULL,''cust-c1-0001'')','A056_REQUEST_REPLAY_CONFLICT');
 d:=c10_demo.a056_create_customer_v1(101,1002,'person','Rahim Uddin',NULL,'rahim@example.test','01711000002',NULL,'cust-c2-0001'); PERFORM public.sv('c2',(d->>'customer_id')::bigint);
 PERFORM public.x($q$SELECT c10_demo.a056_create_customer_v1(101,1001,'person',E'bad\x01name',NULL,NULL,NULL,NULL,'cust-bad-0001')$q$,'A056_INVALID');
 PERFORM public.x($q$SELECT c10_demo.a056_create_customer_v1(101,1001,'person','Bad Email',NULL,'not-an-email',NULL,NULL,'cust-bad-0002')$q$,'A056_INVALID');
 PERFORM public.x($q$SELECT c10_demo.a056_create_customer_v1(101,1001,'person','Bad Site',NULL,NULL,NULL,NULL,'bad-req')$q$,'A056_INVALID');
 PERFORM public.x($q$SELECT c10_demo.a056_create_customer_v1(101,1003,'person','Wrong Site',NULL,NULL,NULL,NULL,'cust-bad-0003')$q$,'A056_INVALID');
 -- HTML / CSV injection stored inert
 d:=c10_demo.a056_create_customer_v1(101,1001,'person','<script>alert(1)</script>','=HYPERLINK("http://evil.test","click")',NULL,NULL,ARRAY['@cmd'],'cust-inj-0001'); PERFORM public.sv('inj',(d->>'customer_id')::bigint);
 PERFORM public.ok((SELECT display_name FROM c10_demo.a056_customers WHERE id=public.id('inj'))='<script>alert(1)</script>','html stored verbatim (renderers escape)');
 PERFORM public.ok(c10_demo.a056_export_customers_csv_v1(101) LIKE '%"''=HYPERLINK(""http://evil.test"",""click"")"%','csv formula neutralised');
 PERFORM public.ok(c10_demo.a056_export_customers_csv_v1(101) NOT LIKE '%,"=HYPERLINK%','no raw formula cell');
 d:=c10_demo.a056_create_customer_v1(101,1001,'organization','Acme Paints (duplicate)',NULL,'SALES@acme.example',NULL,NULL,'cust-c3-0001'); PERFORM public.sv('c3',(d->>'customer_id')::bigint);
 PERFORM public.x('SELECT c10_demo.a056_update_customer_v1('||public.id('c2')||',''{"display_name":"R U"}'',5,''upd-stale-0001'')','A056_STALE_CUSTOMER');
 PERFORM public.x('SELECT c10_demo.a056_update_customer_v1('||public.id('c2')||',''{"status":"merged"}'',1,''upd-badkey-001'')','A056_INVALID');
 d:=c10_demo.a056_update_customer_v1(public.id('c2'),'{"display_name":"Rahim Uddin","tags":["vip"]}',1,'upd-ok-000001'); PERFORM public.ok(d->>'version'='2','update v2');
END $t$; COMMIT;
-- site staff 4444: sees only own site; cannot write business-wide records
BEGIN; SET LOCAL ROLE authenticated; SELECT public.as_user('44444444-4444-4444-8444-444444444444');
DO $t$ DECLARE d jsonb; BEGIN
 d:=c10_demo.a056_list_customers_v1(101,NULL,'active'); PERFORM public.ok((d->>'total')::int=3 AND NOT d::text LIKE '%Rahim%','site staff sees only site 1001 customers');
 PERFORM public.x('SELECT c10_demo.a056_read_customer360_v1('||public.id('c2')||')','A056_NOT_FOUND');
 PERFORM public.x('SELECT c10_demo.a056_create_customer_v1(101,NULL,''person'',''No Site'',NULL,NULL,NULL,NULL,''cust-nosite-01'')','A056_DENIED');
 PERFORM public.x('SELECT c10_demo.a056_create_customer_v1(101,1002,''person'',''Other Site'',NULL,NULL,NULL,NULL,''cust-othsite-1'')','A056_DENIED');
 PERFORM public.x('SELECT c10_demo.a056_list_customers_v1(102)','A056_DENIED');
 PERFORM public.x('SELECT c10_demo.a056_scan_duplicates_v1(101,''scan-staff-001'')','A056_DENIED');
 PERFORM public.x('SELECT c10_demo.a056_export_customers_csv_v1(101)','A056_DENIED');
 PERFORM public.x('SELECT c10_demo.a056_list_audit_v1(101)','A056_DENIED');
 PERFORM public.ok((SELECT count(*) FROM c10_demo.a056_customers)=3,'RLS direct select limited to site rows');
 PERFORM public.ok((SELECT count(*) FROM c10_demo.a056_audit)=0,'audit not readable by site staff');
 PERFORM public.x('INSERT INTO c10_demo.a056_customers(tenant_id,business_id,kind,display_name,request_key,created_by) VALUES(1,101,''person'',''hack'',''hack-direct-01'',gen_random_uuid())','permission denied');
 PERFORM public.x('UPDATE c10_demo.a056_customers SET display_name=''x''','permission denied');
END $t$; COMMIT;
BEGIN; SET LOCAL ROLE authenticated; SELECT public.as_user('cccccccc-cccc-4ccc-8ccc-cccccccccccc');
DO $t$ BEGIN PERFORM public.ok((c10_demo.a056_list_customers_v1(101)->>'total')::int=1 AND (SELECT count(*) FROM c10_demo.a056_customers)=1,'site 1002 grant sees only its customer'); END $t$; COMMIT;
-- denied identities
DO $t$ DECLARE u text; BEGIN
 FOREACH u IN ARRAY ARRAY['55555555-5555-4555-8555-555555555555','66666666-6666-4666-8666-666666666666','99999999-9999-4999-8999-999999999999','77777777-7777-4777-8777-777777777777','88888888-8888-4888-8888-888888888888'] LOOP
  PERFORM set_config('request.jwt.claim.sub',u,true); EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM public.x('SELECT c10_demo.a056_list_customers_v1(101)','A056_DENIED');
  PERFORM public.x('SELECT c10_demo.a056_read_customer360_v1('||public.id('c1')||')','A056_NOT_FOUND');
  PERFORM public.x('SELECT c10_demo.a056_create_customer_v1(101,1001,''person'',''Evil'',NULL,NULL,NULL,NULL,''cust-evil-0001'')','A056_DENIED');
  PERFORM public.x('SELECT c10_demo.a056_report_dashboard_v1(101)','A056_DENIED');
  PERFORM public.ok((SELECT count(*) FROM c10_demo.a056_customers)=0,'no rows leak to '||u);
  EXECUTE 'RESET ROLE';
 END LOOP;
 -- anonymous
 EXECUTE 'SET LOCAL ROLE anon'; PERFORM set_config('request.jwt.claim.sub','',true);
 PERFORM public.x('SELECT c10_demo.a056_list_customers_v1(101)','permission denied');
 PERFORM public.x('SELECT count(*) FROM c10_demo.a056_customers','permission denied');
 EXECUTE 'RESET ROLE';
END $t$;
-- cross-tenant business funnel: T2 owner on own business works, cannot reach T1
BEGIN; SET LOCAL ROLE authenticated; SELECT public.as_user('77777777-7777-4777-8777-777777777777');
DO $t$ BEGIN PERFORM c10_demo.a056_create_customer_v1(201,2001,'person','T2 Customer',NULL,'t2@example.test',NULL,NULL,'t2-cust-00001');
 PERFORM public.ok((c10_demo.a056_list_customers_v1(201)->>'total')::int=1,'T2 own data'); END $t$; COMMIT;

-- ===== 3. duplicates & safe merge =====
BEGIN; SET LOCAL ROLE authenticated; SELECT public.as_user('33333333-3333-4333-8333-333333333333');
DO $t$ DECLARE d jsonb; cand bigint; BEGIN
 d:=c10_demo.a056_add_contact_v1(public.id('c3'),'Buyer Three','Procurement','buyer3@acme.example','01711-555000',true,'contact-c3-0001'); PERFORM public.sv('k3',(d->>'contact_id')::bigint);
 PERFORM c10_demo.a056_log_contact_v1(public.id('c3'),NULL,NULL,'call','in','Asked about bulk paint pricing',now()-interval '2 days','hist-c3-00001');
 PERFORM c10_demo.a056_record_consent_v1(public.id('c3'),'sms','marketing','opt_out','phone call',NULL,false,'consent-c3-opt01');
END $t$; COMMIT;
BEGIN; SET LOCAL ROLE authenticated; SELECT public.as_user('33333333-3333-4333-8333-333333333333');
DO $t$ DECLARE d jsonb; BEGIN
 d:=c10_demo.a056_scan_duplicates_v1(101,'scan-mgr-00001'); PERFORM public.ok((d->>'created')::int>=1,'duplicates found');
 d:=c10_demo.a056_list_duplicate_candidates_v1(101,'open'); PERFORM public.ok(d->'items'->0->>'reason'='email_match' AND (d->'items'->0->>'score')::int=100,'email match first');
 PERFORM public.sv('cand',(d->'items'->0->>'id')::bigint);
 d:=c10_demo.a056_scan_duplicates_v1(101,'scan-mgr-00002'); PERFORM public.ok((d->>'created')::int=0,'scan idempotent on pairs');
 PERFORM public.x('SELECT c10_demo.a056_merge_customers_v1('||public.id('c1')||','||public.id('c3')||',9,1,''merge-stale-001'',''dup'')','A056_STALE_CUSTOMER');
 PERFORM public.x('SELECT c10_demo.a056_merge_customers_v1('||public.id('c1')||','||public.id('c1')||',1,1,''merge-self-0001'',''dup'')','A056_INVALID');
 PERFORM public.x('SELECT c10_demo.a056_merge_customers_v1('||public.id('c1')||','||public.id('c2')||',1,2,''merge-nore-0001'','' '')','A056_INVALID');
 d:=c10_demo.a056_merge_customers_v1(public.id('c1'),public.id('c3'),1,1,'merge-ok-000001','same buyer, duplicate email');
 PERFORM public.ok((d->'moved'->>'a056_contacts')::int=1 AND (d->'moved'->>'a056_history')::int>=1 AND (d->>'version')::int=2,'children moved '||d::text);
 d:=c10_demo.a056_merge_customers_v1(public.id('c1'),public.id('c3'),1,1,'merge-ok-000001','same buyer, duplicate email'); PERFORM public.ok(d->>'replayed'='true','merge replay');
 PERFORM public.x('SELECT c10_demo.a056_merge_customers_v1('||public.id('c3')||','||public.id('c1')||',2,2,''merge-rev-000001'',''reverse'')','A056_CUSTOMER_NOT_ACTIVE');
 PERFORM public.ok((SELECT status||merged_into FROM c10_demo.a056_customers WHERE id=public.id('c3'))='merged'||public.id('c1'),'loser merged_into survivor');
 PERFORM public.ok((SELECT count(*) FROM c10_demo.a056_contacts WHERE id=public.id('k3') AND customer_id=public.id('c1'))=1,'contact moved to survivor');
 PERFORM public.ok(c10_demo.a056_check_consent_v1(public.id('c1'),'sms','marketing')->>'reason'='opt_out_precedence','survivor inherits loser sms opt-out');
 PERFORM public.ok(public.sq('SELECT count(*) FROM c10_demo.a056_suppressions WHERE customer_id='||public.id('c1')||' AND channel=''sms''')=1,'loser opt-out carried to survivor');
 PERFORM public.x('SELECT c10_demo.a056_dismiss_duplicate_v1('||public.id('cand')||',''dismiss-0000001'')','A056_DUP_TRANSITION');
END $t$; COMMIT;
-- cross-business merge refused
BEGIN; SET LOCAL ROLE authenticated; SELECT public.as_user('11111111-1111-4111-8111-111111111111');
DO $t$ DECLARE d jsonb; BEGIN
 d:=c10_demo.a056_create_customer_v1(102,1003,'person','Biz102 Customer',NULL,'b102@example.test',NULL,NULL,'cust-102-00001'); PERFORM public.sv('c102',(d->>'customer_id')::bigint);
 PERFORM public.x('SELECT c10_demo.a056_merge_customers_v1('||public.id('c1')||','||public.id('c102')||',2,1,''merge-xbiz-0001'',''x'')','A056_NOT_FOUND');
END $t$; COMMIT;

-- ===== 4. consent: opt-out precedence =====
-- expired consent (written by fixture owner role, past valid_until)
INSERT INTO c10_demo.a056_consent_events(tenant_id,business_id,site_id,customer_id,channel,purpose,status,source,valid_until,request_key)
 SELECT 1,101,1002,public.id('c2'),'email','marketing','granted','fixture-expired',now()-interval '1 day','fx-expired-01';
BEGIN; SET LOCAL ROLE authenticated; SELECT public.as_user('44444444-4444-4444-8444-444444444444');
DO $t$ DECLARE d jsonb; BEGIN
 d:=c10_demo.a056_create_customer_v1(101,1001,'person','Same Email Other Record',NULL,'sales@acme.example',NULL,NULL,'cust-c4-0001'); PERFORM public.sv('c4',(d->>'customer_id')::bigint);
 PERFORM public.ok(c10_demo.a056_check_consent_v1(public.id('c1'),'email','marketing')->>'reason'='no_consent','no consent => no send');
 d:=c10_demo.a056_record_consent_v1(public.id('c1'),'email','marketing','granted','web form v3',now()+interval '1 year',false,'consent-c1-grant1'); PERFORM public.ok((d->'effective'->>'can_send')='true','granted');
 d:=c10_demo.a056_record_consent_v1(public.id('c1'),'email','service','granted','invoice portal',NULL,false,'consent-c1-grant2');
 d:=c10_demo.a056_record_consent_v1(public.id('c1'),'email','marketing','opt_out','unsubscribe link',NULL,false,'consent-c1-optout'); PERFORM public.ok((d->'effective'->>'reason')='opt_out_precedence','opt-out wins');
 PERFORM public.ok(c10_demo.a056_check_consent_v1(public.id('c1'),'email','service')->>'can_send'='true','marketing opt-out does not block service');
 PERFORM public.x('SELECT c10_demo.a056_record_consent_v1('||public.id('c1')||',''email'',''marketing'',''granted'',''sneaky'',NULL,false,''consent-c1-regrant'')','A056_OPT_OUT_PRECEDENCE');
 PERFORM public.x('SELECT c10_demo.a056_record_consent_v1('||public.id('c1')||',''email'',''marketing'',''granted'',''sneaky'',NULL,true,''consent-c1-lift001'')','A056_DENIED');
 -- same address on another record is suppressed too (address-hash precedence)
 PERFORM public.x('SELECT c10_demo.a056_record_consent_v1('||public.id('c4')||',''email'',''marketing'',''granted'',''form'',NULL,false,''consent-c4-grant01'')','A056_OPT_OUT_PRECEDENCE');
 PERFORM public.ok(c10_demo.a056_check_consent_v1(public.id('c4'),'email','marketing')->>'reason'='opt_out_precedence','address-level suppression');
 PERFORM public.x('SELECT c10_demo.a056_record_consent_v1('||public.id('c1')||',''fax'',''marketing'',''granted'',''x'',NULL,false,''consent-bad-0001'')','A056_INVALID');
END $t$; COMMIT;
BEGIN; SET LOCAL ROLE authenticated; SELECT public.as_user('33333333-3333-4333-8333-333333333333');
DO $t$ DECLARE d jsonb; BEGIN
 d:=c10_demo.a056_record_consent_v1(public.id('c1'),'email','marketing','granted','customer re-subscribed, double opt-in',NULL,true,'consent-c1-lift002'); PERFORM public.ok((d->'effective'->>'can_send')='true','manager lifted suppression with audit');
 PERFORM public.ok((SELECT count(*) FROM c10_demo.a056_audit WHERE action='consent.suppression_lifted')=1,'lift audited');
 PERFORM public.ok(c10_demo.a056_check_consent_v1(public.id('c2'),'email','marketing')->>'reason'='expired','expired consent');
 d:=c10_demo.a056_set_comm_prefs_v1(public.id('c1'),'email','bn','prefs-c1-000001');
END $t$; COMMIT;

-- ===== 5. journey: Lead -> Enquiry -> Opportunity -> Quotation -> Approved Order -> Fulfilment -> Support =====
CREATE TABLE public.a056_t_txt(k text PRIMARY KEY,v text); GRANT ALL ON public.a056_t_txt TO authenticated,anon;
CREATE FUNCTION public.tx(k text) RETURNS text LANGUAGE sql STABLE AS $$ SELECT v FROM public.a056_t_txt WHERE a056_t_txt.k=$1 $$;
GRANT EXECUTE ON FUNCTION public.tx(text) TO authenticated,anon;
BEGIN; SET LOCAL ROLE authenticated; SELECT public.as_user('44444444-4444-4444-8444-444444444444');
DO $t$ DECLARE d jsonb; BEGIN
 d:=c10_demo.a056_create_lead_v1(101,1001,'walk-in','Karim Hossain','karim@example.test','01711000003','Wants paint',NULL,'lead-k-000001'); PERFORM public.sv('lead',(d->>'lead_id')::bigint);
 PERFORM public.x('SELECT c10_demo.a056_qualify_lead_v1('||public.id('lead')||',''disqualified'','''',1,''lead-q-bad-01'')','A056_INVALID');
 PERFORM public.x('SELECT c10_demo.a056_qualify_lead_v1('||public.id('lead')||',''qualified'',NULL,7,''lead-q-stale1'')','A056_STALE_LEAD');
 d:=c10_demo.a056_qualify_lead_v1(public.id('lead'),'qualified','budget confirmed',1,'lead-q-ok-001'); PERFORM public.ok(d->>'status'='qualified','lead qualified');
 d:=c10_demo.a056_create_enquiry_v1(101,1001,'phone','Bulk order query','Need 20 buckets of paint',public.id('c1'),NULL,'enq-c1-000001'); PERFORM public.sv('enq',(d->>'enquiry_id')::bigint); PERFORM public.ok(d->>'status'='RECEIVED','enquiry RECEIVED');
 d:=c10_demo.a056_triage_enquiry_v1(public.id('enq'),'to_lead',NULL,1,'enq-triage-0001'); PERFORM public.ok(d->>'status'='converted' AND d->>'lead_id' IS NOT NULL,'enquiry->lead');
 d:=c10_demo.a056_create_opportunity_v1(101,1001,public.id('c1'),public.id('lead'),public.id('enq'),'Bulk paint supply',50000,current_date+30,NULL,'opp-c1-000001'); PERFORM public.sv('opp',(d->>'opportunity_id')::bigint);
 PERFORM public.ok(d->>'stage'='new','first configured stage');
 PERFORM public.x('SELECT c10_demo.a056_create_opportunity_v1(101,1001,'||public.id('c2')||',NULL,NULL,''x'',1,NULL,NULL,''opp-xsite-0001'')','A056_INVALID');
 d:=c10_demo.a056_move_opportunity_stage_v1(public.id('opp'),'qualified',1,'budget ok','stage-q-000001'); d:=c10_demo.a056_move_opportunity_stage_v1(public.id('opp'),'proposal',2,NULL,'stage-p-000001');
 PERFORM public.x('SELECT c10_demo.a056_move_opportunity_stage_v1('||public.id('opp')||',''negotiation'',2,NULL,''stage-stale-001'')','A056_STALE_OPPORTUNITY');
 PERFORM public.x('SELECT c10_demo.a056_move_opportunity_stage_v1('||public.id('opp')||',''won'',3,NULL,''stage-won-0001'')','A056_WON_REQUIRES_ORDER');
 PERFORM public.x('SELECT c10_demo.a056_move_opportunity_stage_v1('||public.id('opp')||',''nonsense'',3,NULL,''stage-bad-0001'')','A056_INVALID');
 d:=c10_demo.a056_create_quotation_v1(public.id('opp'),'[{"description":"Paint 20L","quantity":10,"unit_price":100,"discount_pct":15,"item_id":8001}]',current_date+14,'bulk offer','quote-q1-000001'); PERFORM public.sv('q1',(d->>'quotation_id')::bigint);
 PERFORM public.ok((d->>'total')::numeric=850 AND (d->>'requires_approval')='true','quote total 850 needs approval (discount>10)');
 PERFORM public.x('SELECT c10_demo.a056_create_quotation_v1('||public.id('opp')||',''[{"description":"x","quantity":-1,"unit_price":1}]'',NULL,NULL,''quote-bad-0001'')','A056_INVALID');
 PERFORM public.x('SELECT c10_demo.a056_create_quotation_v1('||public.id('opp')||',''[]'',NULL,NULL,''quote-bad-0002'')','A056_INVALID');
 PERFORM public.x('SELECT c10_demo.a056_create_quotation_v1('||public.id('opp')||',''[{"description":"x","quantity":1,"unit_price":1,"item_id":9001}]'',NULL,NULL,''quote-bad-0003'')','A056_INVALID');
 d:=c10_demo.a056_decide_quotation_v1(public.id('q1'),1,'submit',NULL,'quote-sub-00001'); PERFORM public.ok(d->>'status'='pending_approval','needs approval');
 PERFORM public.x('SELECT c10_demo.a056_decide_quotation_v1('||public.id('q1')||',1,''approve'',NULL,''quote-app-site01'')','A056_DENIED');
 PERFORM public.x('SELECT c10_demo.a056_decide_quotation_v1('||public.id('q1')||',1,''send'',NULL,''quote-send-bad01'')','A056_QUOTE_TRANSITION');
END $t$; COMMIT;
BEGIN; SET LOCAL ROLE authenticated; SELECT public.as_user('33333333-3333-4333-8333-333333333333');
DO $t$ DECLARE d jsonb; BEGIN
 d:=c10_demo.a056_decide_quotation_v1(public.id('q1'),1,'approve','within margin','quote-app-mgr001'); PERFORM public.ok(d->>'status'='approved','manager approves');
 -- self-approval prevention
 d:=c10_demo.a056_create_quotation_v1(public.id('opp'),'[{"description":"Extra","quantity":1,"unit_price":1000,"discount_pct":20}]',NULL,NULL,'quote-q2-000001'); PERFORM public.sv('q2',(d->>'quotation_id')::bigint);
 d:=c10_demo.a056_decide_quotation_v1(public.id('q2'),1,'submit',NULL,'quote-q2-sub001');
 PERFORM public.x('SELECT c10_demo.a056_decide_quotation_v1('||public.id('q2')||',1,''approve'',NULL,''quote-q2-self01'')','A056_SELF_APPROVAL');
END $t$; COMMIT;
BEGIN; SET LOCAL ROLE authenticated; SELECT public.as_user('44444444-4444-4444-8444-444444444444');
DO $t$ DECLARE d jsonb; BEGIN
 d:=c10_demo.a056_decide_quotation_v1(public.id('q1'),1,'send',NULL,'quote-send-00001'); d:=c10_demo.a056_decide_quotation_v1(public.id('q1'),1,'accept','customer PO received','quote-acc-00001');
 PERFORM public.ok(d->>'status'='accepted','accepted');
 PERFORM public.x('SELECT c10_demo.a056_revise_quotation_v1('||public.id('q1')||',''[{"description":"x","quantity":1,"unit_price":1}]'',NULL,NULL,0,''quote-rev-stale01'')','A056_STALE_QUOTATION');
 PERFORM public.x('SELECT c10_demo.a056_revise_quotation_v1('||public.id('q1')||',''[{"description":"x","quantity":1,"unit_price":1}]'',NULL,NULL,1,''quote-rev-lock001'')','A056_QUOTE_LOCKED');
 -- q2 is a separate quotation; revising creates immutable v2 and supersedes v1
 d:=c10_demo.a056_revise_quotation_v1(public.id('q2'),'[{"description":"Extra","quantity":1,"unit_price":900,"discount_pct":0}]',NULL,'no discount',1,'quote-rev-q2-001'); PERFORM public.ok((d->>'version_no')::int=2,'revision v2');
 d:=c10_demo.a056_read_quotation_v1(public.id('q2')); PERFORM public.ok(d->'versions'->0->>'status'='superseded' AND jsonb_array_length(d->'versions')=2,'v1 superseded, history kept');
 PERFORM public.x('UPDATE c10_demo.a056_quote_lines SET quantity=5','permission denied');
 PERFORM public.x('SELECT c10_demo.a056_convert_quote_to_order_v1('||public.id('q1')||',1,5001,''conv-staff-0001'')','A056_DENIED');
END $t$; COMMIT;
BEGIN; SET LOCAL ROLE authenticated; SELECT public.as_user('33333333-3333-4333-8333-333333333333');
DO $t$ BEGIN
 PERFORM public.x('SELECT c10_demo.a056_convert_quote_to_order_v1('||public.id('q1')||',1,5001,''conv-mgr-000001'')','A056_ORDER_ADAPTER_REJECTED');
 PERFORM public.ok(public.sq('SELECT count(*) FROM c10_demo.operation_orders_v1')=0 AND public.sq('SELECT count(*) FROM c10_demo.a056_order_links')=0,'adapter rejection is atomic: no order/link');
END $t$; COMMIT;
BEGIN; SET LOCAL ROLE authenticated; SELECT public.as_user('11111111-1111-4111-8111-111111111111');
DO $t$ DECLARE d jsonb; BEGIN
 PERFORM c10_demo.set_operation_profile_v1(101,true,true,'manual_preview',1);
 PERFORM public.x('SELECT c10_demo.a056_convert_quote_to_order_v1('||public.id('q1')||',1,5003,''conv-badloc-001'')','A056_INVALID');
 d:=c10_demo.a056_convert_quote_to_order_v1(public.id('q1'),1,5001,'conv-owner-00001'); PERFORM public.ok(d->>'adapter'='A049_CANONICAL' AND d->'links'->0->>'status'='draft','A049 draft order via canonical contract');
 PERFORM public.sv('ord',(d->'links'->0->>'a049_order_id')::bigint);
 d:=c10_demo.a056_convert_quote_to_order_v1(public.id('q1'),1,5001,'conv-owner-00001'); PERFORM public.ok(d->>'replayed'='true','convert replay');
 PERFORM public.x('SELECT c10_demo.a056_convert_quote_to_order_v1('||public.id('q1')||',1,5001,''conv-owner-00002'')','A056_QUOTE_NOT_ACCEPTED');
 PERFORM public.ok(public.sq('SELECT count(*) FROM c10_demo.operation_orders_v1 WHERE status=''draft'' AND kind=''sale_issue'' AND quantity=10 AND estimated_unit_value=85.00')=1,'one draft A049 sale_issue order @85');
 PERFORM public.ok(public.sq('SELECT count(*) FROM c10_demo.stock_movements')=0,'CRM created no stock movement');
END $t$; COMMIT;
BEGIN; SET LOCAL ROLE authenticated; SELECT public.as_user('44444444-4444-4444-8444-444444444444');
DO $t$ DECLARE d jsonb; BEGIN
 d:=c10_demo.a056_read_order_links_v1(101,public.id('c1')); PERFORM public.ok(d->'items'->0->>'fulfilment'='draft' AND (d->'items'->0->>'estimate_total')::numeric=850,'fulfilment draft, estimate 850');
END $t$; COMMIT;
BEGIN; SET LOCAL ROLE authenticated; SELECT public.as_user('11111111-1111-4111-8111-111111111111');
DO $t$ DECLARE d jsonb; rv jsonb; BEGIN
 rv:=c10_demo.create_operation_order_v1(101,5001,8001,'purchase_receive',60,70,'rcv-A049','rcv-seed-000001');
 PERFORM c10_demo.advance_operation_order_v1((rv->>'order_id')::bigint,'confirm',1,'rcv-conf-00001'); PERFORM c10_demo.advance_operation_order_v1((rv->>'order_id')::bigint,'post',2,'rcv-post-00001');
 PERFORM c10_demo.advance_operation_order_v1(public.id('ord'),'confirm',1,'a056-conf-00001'); PERFORM c10_demo.advance_operation_order_v1(public.id('ord'),'post',2,'a056-post-00001');
END $t$; COMMIT;
BEGIN; SET LOCAL ROLE authenticated; SELECT public.as_user('33333333-3333-4333-8333-333333333333');
DO $t$ DECLARE d jsonb; BEGIN
 d:=c10_demo.a056_read_purchase_history_v1(public.id('c1')); PERFORM public.ok((d->>'posted_count')::int=1 AND (d->>'estimate_total_advisory')::numeric=850 AND d->>'certified'='false','purchase history from posted A049 order');
 d:=c10_demo.a056_report_repeat_business_v1(101); PERFORM public.ok((d->>'customers_with_orders')::int=1 AND (d->>'repeat_rate')::numeric=0,'repeat business');
 d:=c10_demo.a056_move_opportunity_stage_v1(public.id('opp'),'won',3,'order posted','stage-won-ok-01'); PERFORM public.ok(d->>'status'='won','won after order');
 PERFORM public.x('SELECT c10_demo.a056_move_opportunity_stage_v1('||public.id('opp')||',''lost'',4,''x'',''stage-closed-01'')','A056_OPP_CLOSED');
 PERFORM public.x('SELECT c10_demo.a056_create_quotation_v1('||public.id('opp')||',''[{"description":"x","quantity":1,"unit_price":1}]'',NULL,NULL,''quote-closed-001'')','A056_OPP_CLOSED');
 -- TEST ADAPTER path (isolated): only when A049 contract absent/simulated
 d:=c10_demo.a056_create_opportunity_v1(101,1002,public.id('c2'),NULL,NULL,'Second job',NULL,NULL,NULL,'opp-c2-000001'); PERFORM public.sv('opp2',(d->>'opportunity_id')::bigint);
 d:=c10_demo.a056_create_quotation_v1(public.id('opp2'),'[{"description":"Item","quantity":2,"unit_price":50,"item_id":8001}]',NULL,NULL,'quote-q3-000001'); PERFORM public.sv('q3',(d->>'quotation_id')::bigint);
 PERFORM public.ok((d->>'requires_approval')='false','small quote no approval');
 d:=c10_demo.a056_decide_quotation_v1(public.id('q3'),1,'submit',NULL,'quote-q3-sub001'); PERFORM public.ok(d->>'status'='approved','auto-approved when rules not triggered');
 d:=c10_demo.a056_decide_quotation_v1(public.id('q3'),1,'send',NULL,'quote-q3-send01'); d:=c10_demo.a056_decide_quotation_v1(public.id('q3'),1,'accept',NULL,'quote-q3-acc001');
 PERFORM public.x('SELECT c10_demo.a056_test_adapter_create_order_v1('||public.id('q3')||',1,5002,''testad-0000001'')','A056_USE_CANONICAL_ADAPTER');
 PERFORM set_config('a056.simulate_a049_missing','on',true);
 d:=c10_demo.a056_test_adapter_create_order_v1(public.id('q3'),1,5002,'testad-0000002'); PERFORM public.ok(d->>'adapter'='TEST_ADAPTER' AND d->'links'->0->'a049_order_id'='null'::jsonb,'test adapter clearly marked, no A049 order');
 PERFORM set_config('a056.simulate_a049_missing','',true);
 d:=c10_demo.a056_read_order_links_v1(101,public.id('c2')); PERFORM public.ok(d->'items'->0->>'fulfilment'='unavailable' AND d->'items'->0->>'adapter'='TEST_ADAPTER','test-adapter link never shows fulfilment');
END $t$; COMMIT;

-- finance boundary: never fabricated
CREATE FUNCTION c10_demo.a056_test_finance_readmodel_v1(p_business bigint,p_customer bigint) RETURNS jsonb LANGUAGE sql AS $$ SELECT jsonb_build_object('balance_due',1200.50,'payment_status','partially_paid','invoices_status','1 open','as_of',now()) $$;
CREATE FUNCTION c10_demo.a056_test_finance_bad_v1(p_business bigint,p_customer bigint) RETURNS jsonb LANGUAGE sql AS $$ SELECT jsonb_build_object('balance_due','abc') $$;
BEGIN; SET LOCAL ROLE authenticated; SELECT public.as_user('33333333-3333-4333-8333-333333333333');
DO $t$ DECLARE d jsonb; BEGIN
 d:=c10_demo.a056_read_customer_finance_v1(public.id('c1')); PERFORM public.ok(d->>'status'='NOT_CERTIFIED' AND d->'balance_due'='null'::jsonb AND d->'payment_status'='null'::jsonb,'no source => NOT CERTIFIED, null not zero');
 PERFORM public.x('SELECT c10_demo.a056_register_finance_source_v1(101,''c10_demo.a056_test_finance_readmodel_v1'',''CERT-TEST-0001'',true,0,''fin-reg-mgr-001'')','A056_DENIED');
 d:=c10_demo.a056_read_customer360_v1(public.id('c1')); PERFORM public.ok(d->'finance'->>'status'='NOT_CERTIFIED','360 finance NOT_CERTIFIED');
END $t$; COMMIT;
BEGIN; SET LOCAL ROLE authenticated; SELECT public.as_user('44444444-4444-4444-8444-444444444444');
DO $t$ BEGIN PERFORM public.x('SELECT c10_demo.a056_read_customer_finance_v1('||public.id('c1')||')','A056_DENIED');
 PERFORM public.ok(c10_demo.a056_read_customer360_v1(public.id('c1'))->'finance'->>'status'='RESTRICTED','site staff 360 finance restricted'); END $t$; COMMIT;
BEGIN; SET LOCAL ROLE authenticated; SELECT public.as_user('11111111-1111-4111-8111-111111111111');
DO $t$ DECLARE d jsonb; BEGIN
 PERFORM public.x('SELECT c10_demo.a056_register_finance_source_v1(101,''c10_demo.read_x_v1; drop table x'',NULL,false,0,''fin-reg-bad-001'')','A056_INVALID');
 PERFORM public.x('SELECT c10_demo.a056_register_finance_source_v1(101,''c10_demo.read_missing_v1'',NULL,false,0,''fin-reg-bad-002'')','A056_FINANCE_FN_MISSING');
 PERFORM public.x('SELECT c10_demo.a056_register_finance_source_v1(101,''c10_demo.a056_test_finance_readmodel_v1'',''short'',true,0,''fin-reg-bad-003'')','A056_INVALID');
 d:=c10_demo.a056_register_finance_source_v1(101,'c10_demo.a056_test_finance_readmodel_v1',NULL,false,0,'fin-reg-own-001');
 PERFORM public.ok(c10_demo.a056_read_customer_finance_v1(public.id('c1'))->>'status'='NOT_CERTIFIED','registered but uncertified stays NOT_CERTIFIED');
 d:=c10_demo.a056_register_finance_source_v1(101,'c10_demo.a056_test_finance_readmodel_v1','CERT-TEST-0001',true,1,'fin-reg-own-002');
 d:=c10_demo.a056_read_customer_finance_v1(public.id('c1')); PERFORM public.ok(d->>'status'='CERTIFIED' AND (d->>'balance_due')::numeric=1200.50 AND d->>'payment_status'='partially_paid' AND (d->>'test_source')='true','certified read model shown, labelled test source');
 d:=c10_demo.a056_register_finance_source_v1(101,'c10_demo.a056_test_finance_bad_v1','CERT-TEST-0001',true,2,'fin-reg-own-003');
 d:=c10_demo.a056_read_customer_finance_v1(public.id('c1')); PERFORM public.ok(d->>'status'='UNAVAILABLE' AND d->'balance_due'='null'::jsonb,'invalid finance response => UNAVAILABLE');
 PERFORM public.x('SELECT c10_demo.a056_register_finance_source_v1(101,''c10_demo.a056_test_finance_bad_v1'',''CERT-TEST-0001'',true,2,''fin-reg-own-004'')','A056_STALE_FINANCE_SOURCE');
END $t$; COMMIT;

-- support, SLA, follow-ups
BEGIN; SET LOCAL ROLE authenticated; SELECT public.as_user('44444444-4444-4444-8444-444444444444');
DO $t$ DECLARE d jsonb; ob bigint; sm bigint; BEGIN
 ob:=public.sq('SELECT count(*) FROM c10_demo.operation_orders_v1'); sm:=public.sq('SELECT count(*) FROM c10_demo.stock_movements');
 d:=c10_demo.a056_create_ticket_v1(101,1001,public.id('c1'),'complaint','urgent','Wrong shade delivered','Bucket label differs',(SELECT id FROM c10_demo.a056_order_links WHERE customer_id=public.id('c1') LIMIT 1),'tick-t1-000001');
 PERFORM public.sv('t1',(d->>'ticket_id')::bigint); PERFORM public.ok((d->>'sla_due_at')::timestamptz BETWEEN now()+interval '3 hours 55 minutes' AND now()+interval '4 hours 5 minutes','urgent SLA 4h');
 d:=c10_demo.a056_create_ticket_v1(101,1001,public.id('c1'),'return_request','low','Return 2 buckets',NULL,NULL,'tick-t2-000001'); PERFORM public.sv('t2',(d->>'ticket_id')::bigint);
 PERFORM public.ok(d->>'finance_stock_effect'='none' AND public.sq('SELECT count(*) FROM c10_demo.operation_orders_v1')=ob AND public.sq('SELECT count(*) FROM c10_demo.stock_movements')=sm,'return request makes no stock/order/finance mutation');
 PERFORM public.x('SELECT c10_demo.a056_create_ticket_v1(101,1001,'||public.id('c1')||',''complaint'',''urgent'',''x'',NULL,999999,''tick-bad-000001'')','A056_INVALID');
 PERFORM public.x('SELECT c10_demo.a056_update_ticket_v1('||public.id('t1')||',''assign'',''77777777-7777-4777-8777-777777777777'',NULL,NULL,1,''tick-asg-bad-01'')','A056_INVALID');
 d:=c10_demo.a056_update_ticket_v1(public.id('t1'),'assign','33333333-3333-4333-8333-333333333333',NULL,NULL,1,'tick-asg-000001'); PERFORM public.ok(d->>'status'='assigned','assigned');
 PERFORM public.x('SELECT c10_demo.a056_update_ticket_v1('||public.id('t1')||',''start'',NULL,NULL,NULL,1,''tick-stale-0001'')','A056_STALE_TICKET');
 d:=c10_demo.a056_update_ticket_v1(public.id('t1'),'start',NULL,NULL,NULL,2,'tick-start-00001');
 PERFORM public.x('SELECT c10_demo.a056_update_ticket_v1('||public.id('t1')||',''resolve'',NULL,''fixed'',NULL,3,''tick-res-noev-01'')','A056_RESOLUTION_EVIDENCE_REQUIRED');
 d:=c10_demo.a056_update_ticket_v1(public.id('t1'),'resolve',NULL,'Replaced buckets','Delivery note DN-1002 signed',3,'tick-res-000001'); PERFORM public.ok(d->>'status'='resolved' AND d->>'sla_breached'='false','resolved within SLA');
 PERFORM public.x('SELECT c10_demo.a056_update_ticket_v1('||public.id('t1')||',''start'',NULL,NULL,NULL,4,''tick-badtr-0001'')','A056_TICKET_TRANSITION');
 d:=c10_demo.a056_update_ticket_v1(public.id('t1'),'close',NULL,NULL,NULL,4,'tick-close-00001');
 d:=c10_demo.a056_update_ticket_v1(public.id('t1'),'reopen',NULL,'customer says still wrong',NULL,5,'tick-reopen-0001'); PERFORM public.ok(d->>'status'='open','reopened');
END $t$; COMMIT;
UPDATE c10_demo.a056_tickets SET sla_due_at=now()-interval '1 hour' WHERE id=public.id('t2');
BEGIN; SET LOCAL ROLE authenticated; SELECT public.as_user('33333333-3333-4333-8333-333333333333');
DO $t$ DECLARE d jsonb; BEGIN
 d:=c10_demo.a056_list_tickets_v1(101); PERFORM public.ok((SELECT x->>'sla_state' FROM jsonb_array_elements(d->'items') x WHERE (x->>'id')::bigint=public.id('t2'))='breached','breached SLA shown');
 d:=c10_demo.a056_create_followup_v1(101,1001,public.id('c1'),public.id('opp'),NULL,now()-interval '1 day','call back about shade',NULL,'fu-c1-0000001'); PERFORM public.sv('fu',(d->>'followup_id')::bigint);
 PERFORM public.x('SELECT c10_demo.a056_create_followup_v1(101,1001,'||public.id('c2')||','||public.id('opp')||',NULL,now(),NULL,NULL,''fu-mismatch-01'')','A056_INVALID');
 PERFORM public.x('SELECT c10_demo.a056_create_followup_v1(101,1001,'||public.id('c1')||',NULL,NULL,now(),NULL,''77777777-7777-4777-8777-777777777777'',''fu-badasg-001'')','A056_INVALID');
 PERFORM public.ok(jsonb_array_length(c10_demo.a056_report_followups_v1(101)->'overdue')=1,'pending follow-up overdue');
 d:=c10_demo.a056_complete_followup_v1(public.id('fu'),'done','called, resolved',1,'fu-done-000001'); PERFORM public.ok(d->>'status'='done','done');
 PERFORM public.x('SELECT c10_demo.a056_complete_followup_v1('||public.id('fu')||',''done'',NULL,1,''fu-done-000002'')','A056_STALE_FOLLOWUP');
 PERFORM public.ok(jsonb_array_length(c10_demo.a056_report_followups_v1(101)->'overdue')=0,'no overdue after completion');
 PERFORM c10_demo.a056_create_followup_v1(101,1001,public.id('c1'),NULL,public.id('t1'),now()+interval '2 days','check ticket',NULL,'fu-c1-0000002');
END $t$; COMMIT;

-- ===== 6. segmentation, consent-aware campaigns (NO-OP provider) =====
BEGIN; SET LOCAL ROLE authenticated; SELECT public.as_user('33333333-3333-4333-8333-333333333333');
DO $t$ DECLARE d jsonb; i int; cid bigint; BEGIN
 FOR i IN 1..5 LOOP
  d:=c10_demo.a056_create_customer_v1(101,1001,'person','Campaign V'||i,NULL,CASE WHEN i=4 THEN NULL ELSE 'v'||i||'@example.test' END,'0172000000'||i,ARRAY['camp'],'cust-v'||i||'-00001'); PERFORM public.sv('v'||i,(d->>'customer_id')::bigint);
 END LOOP;
 PERFORM c10_demo.a056_record_consent_v1(public.id('v1'),'email','marketing','granted','signup form',NULL,false,'consent-v1-00001');
 PERFORM c10_demo.a056_record_consent_v1(public.id('v3'),'email','marketing','opt_out','unsubscribed',NULL,false,'consent-v3-00001');
 PERFORM c10_demo.a056_record_consent_v1(public.id('v4'),'email','marketing','granted','signup form',NULL,false,'consent-v4-00001');
 PERFORM c10_demo.a056_record_consent_v1(public.id('v5'),'email','marketing','granted','signup form',NULL,false,'consent-v5-00001');
 PERFORM c10_demo.a056_record_consent_v1(public.id('v5'),'email','marketing','revoked','asked to stop',NULL,false,'consent-v5-00002');
 PERFORM public.x('SELECT c10_demo.a056_save_segment_v1(101,NULL,''bad'',''{"sql":"1=1"}'',0,''seg-bad-000001'')','A056_INVALID');
 d:=c10_demo.a056_save_segment_v1(101,NULL,'Campaign tag','{"tags_any":["camp"]}',0,'seg-ok-0000001'); PERFORM public.sv('seg',(d->>'segment_id')::bigint);
 PERFORM public.ok((c10_demo.a056_evaluate_segment_v1(public.id('seg'))->>'count')::int=5,'segment evaluates 5');
 d:=c10_demo.a056_save_segment_v1(101,NULL,'Repeat buyers','{"min_posted_orders":1}',0,'seg-rep-0000001'); PERFORM public.ok(c10_demo.a056_evaluate_segment_v1((d->>'segment_id')::bigint)->'customer_ids'=to_jsonb(ARRAY[public.id('c1')]),'segment by posted A049 orders');
 d:=c10_demo.a056_create_campaign_v1(101,'Spring promo','email',public.id('seg'),'Hello {{name}}','camp-ok-0000001'); cid:=(d->>'campaign_id')::bigint; PERFORM public.sv('camp',cid);
 d:=c10_demo.a056_dispatch_campaign_v1(cid,'camp-dsp-0000001');
 PERFORM public.ok((d->>'considered')::int=5 AND (d->>'eligible')::int=1 AND (d->>'blocked')::int=4 AND d->>'provider'='NOOP' AND (d->>'sent')::int=0,'consent-aware dispatch '||d::text);
 PERFORM public.ok(d->'by_reason'='{"no_consent":1,"revoked":1,"no_address":1,"opt_out_precedence":1}'::jsonb,'blocked reasons '||(d->'by_reason')::text);
 PERFORM public.ok(NOT EXISTS(SELECT 1 FROM jsonb_array_elements(c10_demo.a056_read_campaign_v1(cid)->'recipients') r WHERE r->>'provider_status' ILIKE '%sent' AND r->>'provider_status'<>'NOOP_NOT_SENT' AND r->>'provider_status'<>'BLOCKED_NOT_SENT'),'nothing marked sent');
 PERFORM public.x('SELECT c10_demo.a056_dispatch_campaign_v1('||cid||',''camp-dsp-0000002'')','A056_CAMPAIGN_TRANSITION');
END $t$; COMMIT;
BEGIN; SET LOCAL ROLE authenticated; SELECT public.as_user('44444444-4444-4444-8444-444444444444');
DO $t$ BEGIN PERFORM public.x('SELECT c10_demo.a056_dispatch_campaign_v1('||public.id('camp')||',''camp-dsp-staff001'')','A056_NOT_FOUND');
 PERFORM public.x('SELECT c10_demo.a056_create_campaign_v1(101,''x'',''email'','||public.id('seg')||',NULL,''camp-staff-00001'')','A056_DENIED'); END $t$; COMMIT;

-- ===== 7. intake contracts: website/e-commerce/POS/offline =====
BEGIN; SET LOCAL ROLE authenticated; SELECT public.as_user('44444444-4444-4444-8444-444444444444');
DO $t$ BEGIN PERFORM public.x('SELECT c10_demo.a056_create_intake_endpoint_v1(101,1001,''website'',''x'',5,''intake-staff-001'')','A056_DENIED'); END $t$; COMMIT;
BEGIN; SET LOCAL ROLE authenticated; SELECT public.as_user('33333333-3333-4333-8333-333333333333');
DO $t$ DECLARE d jsonb; BEGIN
 d:=c10_demo.a056_create_intake_endpoint_v1(101,1001,'website','Main site form',2,'intake-ep-0001'); INSERT INTO public.a056_t_txt VALUES('tok',d->>'token'); PERFORM public.sv('ep',(d->>'endpoint_id')::bigint);
 PERFORM public.ok(d->>'token' LIKE 'c10in_%' AND length(d->>'token')>40,'token issued once');
 d:=c10_demo.a056_create_intake_endpoint_v1(101,1001,'website','Main site form',2,'intake-ep-0001'); PERFORM public.ok(d->'token'='null'::jsonb,'replay does not reveal token');
 PERFORM public.x('SELECT c10_demo.a056_create_intake_endpoint_v1(101,1001,''telegram'',''x'',5,''intake-bad-0001'')','A056_INVALID');
 PERFORM public.ok(jsonb_array_length(c10_demo.a056_list_intake_endpoints_v1(101)->'items')=1 AND NOT c10_demo.a056_list_intake_endpoints_v1(101)::text LIKE '%c10in_%','list hides token');
END $t$; COMMIT;
BEGIN; SET LOCAL ROLE anon; SELECT set_config('request.jwt.claim.sub','',true);
DO $t$ DECLARE d jsonb; t text:=public.tx('tok'); big text:=repeat('x',25000); BEGIN
 PERFORM public.x($q$SELECT c10_demo.a056_public_intake_v1('c10in_wrong','idem-bad-0001','{"email":"a@b.test"}')$q$,'A056_TOKEN_INVALID');
 PERFORM public.x(format($q$SELECT c10_demo.a056_public_intake_v1(%L,'idem-bad-0002','{"email":"a@b.test","sql":"drop"}')$q$,t),'A056_INVALID');
 PERFORM public.x(format($q$SELECT c10_demo.a056_public_intake_v1(%L,'idem-bad-0003',jsonb_build_object('email','a@b.test','message',%L))$q$,t,big),'A056_INVALID');
 PERFORM public.x(format($q$SELECT c10_demo.a056_public_intake_v1(%L,'idem-bad-0004','{"message":"no contact"}')$q$,t),'A056_INVALID');
 PERFORM public.x(format($q$SELECT c10_demo.a056_public_intake_v1(%L,'idem-bad-0005','{"email":"a@b.test","intent":"refund"}')$q$,t),'A056_INVALID');
 PERFORM public.x(format($q$SELECT c10_demo.a056_public_intake_v1(%L,'idem-bad-0006','{"email":"a@b.test","lines":[{"description":"x","quantity":-3}]}')$q$,t),'A056_INVALID');
 d:=c10_demo.a056_public_intake_v1(t,'idem-ord-0001','{"intent":"order_request","name":"Web Buyer","email":"v1@example.test","phone":"01999000001","subject":"Cart","message":"<img src=x onerror=alert(1)>","lines":[{"description":"Paint 20L","quantity":3,"sku":"SWEETS"}],"consent":{"marketing_email":true}}');
 PERFORM public.ok(d->>'status'='DRAFT' AND d->>'replayed'='false','order request starts DRAFT');
 d:=c10_demo.a056_public_intake_v1(t,'idem-ord-0001','{"intent":"order_request","email":"other@x.test"}'); PERFORM public.ok(d->>'replayed'='true','intake idempotent by key');
 d:=c10_demo.a056_public_intake_v1(t,'idem-enq-0001','{"name":"Web Buyer 2","email":"v3@example.test","message":"Hi","consent":{"marketing_email":true}}'); PERFORM public.ok(d->>'status'='RECEIVED','enquiry RECEIVED');
 PERFORM public.x(format($q$SELECT c10_demo.a056_public_intake_v1(%L,'idem-enq-0002','{"email":"c@d.test"}')$q$,t),'A056_THROTTLED');
 PERFORM public.x('SELECT * FROM c10_demo.a056_enquiries','permission denied');
 PERFORM public.x('SELECT c10_demo.a056_list_enquiries_v1(101)','permission denied');
END $t$; COMMIT;
DO $t$ BEGIN
 PERFORM public.ok(public.sq('SELECT count(*) FROM c10_demo.operation_orders_v1')=2,'public intake created NO A049 order (only the journey sale + receive orders)');
 PERFORM public.ok(public.sq('SELECT count(*) FROM c10_demo.a056_enquiries WHERE endpoint_id='||public.id('ep')||' AND status IN (''DRAFT'',''RECEIVED'')')=2,'both stored RECEIVED/DRAFT');
 PERFORM public.ok(public.sq('SELECT count(*) FROM c10_demo.a056_intake_endpoints WHERE token_hash='||quote_literal(public.tx('tok')))=0,'plaintext token not stored');
 END $t$;
BEGIN; SET LOCAL ROLE authenticated; SELECT public.as_user('44444444-4444-4444-8444-444444444444');
DO $t$ DECLARE d jsonb; e1 bigint; e2 bigint; BEGIN
 d:=c10_demo.a056_list_enquiries_v1(101,'DRAFT'); PERFORM public.ok((d->>'total')::int=1 AND d->'items'->0->>'body' IS NOT NULL AND d->'items'->0->>'body'='<img src=x onerror=alert(1)>','html kept inert as data');
 e1:=(d->'items'->0->>'id')::bigint; e2:=(c10_demo.a056_list_enquiries_v1(101,'RECEIVED')->'items'->0->>'id')::bigint;
 d:=c10_demo.a056_triage_enquiry_v1(e1,'triage',public.id('v2'),1,'triage-web-00001'); PERFORM public.ok((d->>'consent_claims_applied')::int=1 AND d->>'status'='triaged','claim applied after triage');
 PERFORM public.ok(c10_demo.a056_check_consent_v1(public.id('v2'),'email','marketing')->>'can_send'='true','consent only exists after staff triage');
 d:=c10_demo.a056_triage_enquiry_v1(e2,'triage',public.id('v3'),1,'triage-web-00002'); PERFORM public.ok((d->>'consent_claims_applied')::int=0,'claim cannot override opt-out');
 PERFORM public.ok(c10_demo.a056_check_consent_v1(public.id('v3'),'email','marketing')->>'reason'='opt_out_precedence','opt-out still wins');
 PERFORM public.x('SELECT c10_demo.a056_triage_enquiry_v1('||e2||',''close'',NULL,1,''triage-web-00003'')','A056_STALE_ENQUIRY') ;
END $t$; COMMIT;
BEGIN; SET LOCAL ROLE authenticated; SELECT public.as_user('33333333-3333-4333-8333-333333333333');
DO $t$ BEGIN PERFORM c10_demo.a056_revoke_intake_endpoint_v1(public.id('ep'),'intake-rev-0001'); END $t$; COMMIT;
BEGIN; SET LOCAL ROLE anon; DO $t$ BEGIN PERFORM public.x(format($q$SELECT c10_demo.a056_public_intake_v1(%L,'idem-after-revoke','{"email":"a@b.test"}')$q$,public.tx('tok')),'A056_TOKEN_INVALID'); END $t$; COMMIT;

-- ===== 8. reports =====
BEGIN; SET LOCAL ROLE authenticated; SELECT public.as_user('33333333-3333-4333-8333-333333333333');
DO $t$ DECLARE d jsonb; n3 int; BEGIN
 d:=c10_demo.a056_report_dashboard_v1(101); PERFORM public.ok((d->>'leads')::int>=2 AND (d->>'enquiries')::int>=3 AND (d->>'tickets_open')::int>=2 AND d->>'certified'='false' AND (d->>'quotes_pending_approval')::int=0 AND d->'advisory_pipeline_value'='null'::jsonb,'dashboard '||d::text);
 n3:=(d->>'customers')::int; PERFORM public.sv('n3',n3);
 d:=c10_demo.a056_report_funnel_v1(101); PERFORM public.ok(jsonb_array_length(d->'stages')=8 AND (d->'stages'->7->>'count')::int=1 AND d->'stages'->0->'rate_from_prev'='null'::jsonb,'funnel '||d::text);
 d:=c10_demo.a056_report_retention_v1(101,6); PERFORM public.ok(jsonb_array_length(d->'cohorts')=1 AND (d->'cohorts'->0->>'customers')::int=1 AND (d->'cohorts'->0->>'repeat_rate')::numeric=0,'retention cohort');
 d:=c10_demo.a056_report_tickets_v1(101); PERFORM public.ok((d->>'opened')::int=2 AND (d->>'sla_breached')::int=1 AND d->>'avg_resolution_hours' IS NULL,'ticket report '||d::text);
 d:=c10_demo.a056_read_pipeline_v1(101); PERFORM public.ok(jsonb_array_length(d->'stages')=6,'pipeline');
 PERFORM public.x('SELECT c10_demo.a056_report_dashboard_v1(102)','A056_DENIED');
END $t$; COMMIT;
BEGIN; SET LOCAL ROLE authenticated; SELECT public.as_user('44444444-4444-4444-8444-444444444444');
DO $t$ BEGIN PERFORM public.ok((c10_demo.a056_report_dashboard_v1(101)->>'customers')::int < public.id('n3'),'site staff report scoped to own site'); END $t$; COMMIT;
BEGIN; SET LOCAL ROLE authenticated; SELECT public.as_user('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
DO $t$ DECLARE d jsonb; BEGIN
 d:=c10_demo.a056_report_tickets_v1(102); PERFORM public.ok((d->>'opened')::int=0 AND d->'avg_resolution_hours'='null'::jsonb,'null not zero for empty ticket report');
 d:=c10_demo.a056_report_repeat_business_v1(102); PERFORM public.ok(d->'repeat_rate'='null'::jsonb,'null repeat rate when no orders');
 d:=c10_demo.a056_report_funnel_v1(102); PERFORM public.ok(d->'lead_to_order_rate'='null'::jsonb,'null conversion when no leads');
END $t$; COMMIT;

-- ===== 9. privacy export / redaction =====
BEGIN; SET LOCAL ROLE authenticated; SELECT public.as_user('33333333-3333-4333-8333-333333333333');
DO $t$ DECLARE d jsonb; BEGIN
 d:=c10_demo.a056_create_customer_v1(101,1001,'person','Privacy Subject',NULL,'subject@example.test','01733000001',ARRAY['gdpr'],'cust-r1-000001'); PERFORM public.sv('r1',(d->>'customer_id')::bigint);
 PERFORM c10_demo.a056_add_contact_v1(public.id('r1'),'Subject Alt','self','alt@example.test',NULL,true,'contact-r1-00001');
 PERFORM c10_demo.a056_log_contact_v1(public.id('r1'),NULL,NULL,'note','internal','Prefers calls after 5pm',NULL,'hist-r1-000001');
 PERFORM c10_demo.a056_record_consent_v1(public.id('r1'),'email','marketing','opt_out','asked',NULL,false,'consent-r1-opt001');
 d:=c10_demo.a056_export_customer_v1(public.id('r1'),'export-r1-00001'); PERFORM public.ok(d->'customer'->>'email'='subject@example.test' AND jsonb_array_length(d->'contacts')=1 AND jsonb_array_length(d->'history')>=1 AND jsonb_array_length(d->'consent_events')=1,'export package');
 PERFORM public.x('SELECT c10_demo.a056_redact_customer_v1('||public.id('r1')||',3,''erasure request'',''redact-mgr-0001'')','A056_DENIED');
 PERFORM public.x('SELECT c10_demo.a056_redact_customer_v1('||public.id('c1')||',2,''x'',''redact-mgr-0002'')','A056_DENIED');
END $t$; COMMIT;
BEGIN; SET LOCAL ROLE authenticated; SELECT public.as_user('44444444-4444-4444-8444-444444444444');
DO $t$ BEGIN PERFORM public.x('SELECT c10_demo.a056_export_customer_v1('||public.id('r1')||',''export-staff-001'')','A056_DENIED'); END $t$; COMMIT;
BEGIN; SET LOCAL ROLE authenticated; SELECT public.as_user('22222222-2222-4222-8222-222222222222');
DO $t$ DECLARE d jsonb; BEGIN
 PERFORM public.x('SELECT c10_demo.a056_redact_customer_v1('||public.id('r1')||',9,''erasure request'',''redact-stale-001'')','A056_STALE_CUSTOMER');
 PERFORM public.x('SELECT c10_demo.a056_redact_customer_v1('||public.id('r1')||',1,'' '',''redact-noreason1'')','A056_INVALID');
 PERFORM public.x('SELECT c10_demo.a056_redact_customer_v1('||public.id('c1')||',2,''erasure'',''redact-open-0001'')','A056_REDACT_BLOCKED_OPEN_WORK');
 d:=c10_demo.a056_redact_customer_v1(public.id('r1'),1,'erasure request #1','redact-own-00001'); PERFORM public.ok(d->>'status'='redacted','redacted');
 d:=c10_demo.a056_export_customer_v1(public.id('r1'),'export-r1-00002'); PERFORM public.ok(d->'customer'->'email'='null'::jsonb AND d->'customer'->'display_name'='null'::jsonb AND d->'contacts'->0->'email'='null'::jsonb AND d->'history'->0->>'summary'='[redacted]','PII removed from all views');
 PERFORM public.ok(c10_demo.a056_check_consent_v1(public.id('r1'),'email','marketing')->>'reason'='customer_inactive','redacted customers never contactable');
 PERFORM public.ok(public.sq('SELECT count(*) FROM c10_demo.a056_suppressions WHERE customer_id='||public.id('r1'))>=1,'opt-out suppression retained after redaction');
 PERFORM public.x('SELECT c10_demo.a056_update_customer_v1('||public.id('r1')||',''{"display_name":"zombie"}'',2,''upd-redacted-01'')','A056_CUSTOMER_NOT_ACTIVE');
END $t$; COMMIT;

-- ===== 10. audit immutability, role revocation, configurable permissions =====
DO $t$ BEGIN
 PERFORM public.x('UPDATE c10_demo.a056_audit SET action=''x''','A056_AUDIT_IMMUTABLE'); PERFORM public.x('DELETE FROM c10_demo.a056_audit','A056_AUDIT_IMMUTABLE'); PERFORM public.x('TRUNCATE c10_demo.a056_audit','A056_AUDIT_IMMUTABLE');
 PERFORM public.ok(public.sq('SELECT count(*) FROM c10_demo.a056_audit WHERE action IN (''customer.merge'',''quote.approve'',''order.convert'',''privacy.redact'',''campaign.dispatch_noop'',''settings.set'')')>=6,'key actions audited');
END $t$;
BEGIN; SET LOCAL ROLE authenticated; SELECT public.as_user('33333333-3333-4333-8333-333333333333');
DO $t$ BEGIN PERFORM public.ok(jsonb_array_length(c10_demo.a056_list_audit_v1(101)->'items')>10,'manager reads audit'); END $t$; COMMIT;
UPDATE c10_demo.business_members SET active=false WHERE user_id='33333333-3333-4333-8333-333333333333';
UPDATE c10_demo.site_grants SET active=false WHERE user_id='44444444-4444-4444-8444-444444444444';
BEGIN; SET LOCAL ROLE authenticated; SELECT public.as_user('33333333-3333-4333-8333-333333333333');
DO $t$ BEGIN PERFORM public.x('SELECT c10_demo.a056_list_customers_v1(101)','A056_DENIED'); PERFORM public.x('SELECT c10_demo.a056_decide_quotation_v1('||public.id('q2')||',2,''submit'',NULL,''revoked-0000001'')','A056_NOT_FOUND');
 PERFORM public.x('SELECT c10_demo.a056_create_ticket_v1(101,1001,'||public.id('c1')||',''service'',''low'',''x'',NULL,NULL,''revoked-0000002'')','A056_DENIED'); PERFORM public.ok((SELECT count(*) FROM c10_demo.a056_customers)=0,'revoked manager sees no rows'); END $t$; COMMIT;
BEGIN; SET LOCAL ROLE authenticated; SELECT public.as_user('44444444-4444-4444-8444-444444444444');
DO $t$ BEGIN PERFORM public.x('SELECT c10_demo.a056_list_leads_v1(101)','A056_DENIED'); PERFORM public.x('SELECT c10_demo.a056_read_customer360_v1('||public.id('c1')||')','A056_NOT_FOUND'); END $t$; COMMIT;
UPDATE c10_demo.business_members SET active=true WHERE user_id='33333333-3333-4333-8333-333333333333';
UPDATE c10_demo.site_grants SET active=true WHERE user_id='44444444-4444-4444-8444-444444444444';
-- Owner-configurable stages / permissions / approval rules (business 102)
BEGIN; SET LOCAL ROLE authenticated; SELECT public.as_user('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
DO $t$ DECLARE d jsonb; BEGIN
 d:=c10_demo.a056_create_opportunity_v1(102,1003,public.id('c102'),NULL,NULL,'Service retainer',NULL,NULL,NULL,'opp-102-000001'); PERFORM public.sv('opp102',(d->>'opportunity_id')::bigint);
END $t$; COMMIT;
BEGIN; SET LOCAL ROLE authenticated; SELECT public.as_user('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
DO $t$ DECLARE d jsonb; c jsonb:=public.dc(); BEGIN
 PERFORM public.x($q$SELECT c10_demo.a056_set_settings_v1(102,true,jsonb_set(public.dc(),'{stages}','[{"code":"lead","label":"Lead","kind":"open"},{"code":"won","label":"Won","kind":"won"},{"code":"lost","label":"Lost","kind":"lost"}]'),1,'cfg-102-stage01','x')$q$,'A056_STAGE_IN_USE');
 PERFORM public.x($q$SELECT c10_demo.a056_set_settings_v1(102,true,jsonb_set(public.dc(),'{sla,urgent}','0'),1,'cfg-102-sla-001','x')$q$,'A056_CONFIG_INVALID');
 c:=jsonb_set(c,'{permissions,customer.write}','"manager"'); c:=jsonb_set(c,'{permissions,quote.approve}','"owner"'); c:=jsonb_set(c,'{approval,total_over}','500'); c:=jsonb_set(c,'{sla,urgent}','2');
 c:=jsonb_set(c,'{stages}',c->'stages'||'[{"code":"onsite","label":"Site visit","kind":"open","approval":true}]'::jsonb);
 d:=c10_demo.a056_set_settings_v1(102,true,c,1,'cfg-102-ok-00001','tighten permissions, add approval rules'); PERFORM public.ok(d->>'version'='2','config v2');
 PERFORM public.ok(jsonb_array_length(c10_demo.a056_list_settings_history_v1(102)->'items')=2,'versioned history retained');
END $t$; COMMIT;
BEGIN; SET LOCAL ROLE authenticated; SELECT public.as_user('dddddddd-dddd-4ddd-8ddd-dddddddddddd');
DO $t$ BEGIN PERFORM public.x('SELECT c10_demo.a056_create_customer_v1(102,1003,''person'',''Blocked'',NULL,NULL,NULL,NULL,''cust-102-block01'')','A056_DENIED'); END $t$; COMMIT;
BEGIN; SET LOCAL ROLE authenticated; SELECT public.as_user('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
DO $t$ DECLARE d jsonb; BEGIN
 d:=c10_demo.a056_create_customer_v1(102,1003,'person','Allowed Manager Customer',NULL,NULL,NULL,NULL,'cust-102-allow01');
 d:=c10_demo.a056_create_quotation_v1(public.id('opp102'),'[{"description":"Retainer","quantity":1,"unit_price":600,"discount_pct":0}]',NULL,NULL,'quote-102-000001'); PERFORM public.ok(d->>'requires_approval'='true','Owner approval rule (total_over 500) applied');
 PERFORM public.x('SELECT c10_demo.a056_move_opportunity_stage_v1('||public.id('opp102')||',''onsite'',1,NULL,''stage-102-appr01'')','A056_STAGE_APPROVAL_REQUIRED');
END $t$; COMMIT;
BEGIN; SET LOCAL ROLE authenticated; SELECT public.as_user('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
DO $t$ DECLARE d jsonb; BEGIN d:=c10_demo.a056_move_opportunity_stage_v1(public.id('opp102'),'onsite',1,NULL,'stage-102-appr02'); PERFORM public.ok(d->>'stage'='onsite','owner may enter approval stage'); END $t$; COMMIT;
\echo PASS A056 CRM lifecycle: authz/RLS (2 tenants, 3 businesses, 4+ sites), journey, consent precedence, merge, intake, reports, privacy. No GoTrue, no production.
