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
