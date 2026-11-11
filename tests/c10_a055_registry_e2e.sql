-- C10-A055 registry e2e (disposable PostgreSQL; signed-claim SIMULATION, NOT GoTrue). Run after core+registry+lockdown+seed
-- (tests/c10_a055_load.sh). Synthetic data only. Raises on any failure and ends with A055_REGISTRY_E2E_PASS.
\set ON_ERROR_STOP on
CREATE SCHEMA c10_test;
GRANT USAGE ON SCHEMA c10_test TO authenticated,anon;
CREATE FUNCTION c10_test.u(p text) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT (CASE p
 WHEN 'owner' THEN '11111111-1111-4111-8111-111111111111' WHEN 'bo101' THEN '22222222-2222-4222-8222-222222222222'
 WHEN 'mgr101' THEN '33333333-3333-4333-8333-333333333333' WHEN 'stock' THEN '44444444-4444-4444-8444-444444444444'
 WHEN 'investor' THEN '55555555-5555-4555-8555-555555555555' WHEN 'revoked' THEN '66666666-6666-4666-8666-666666666666'
 WHEN 'owner2' THEN '77777777-7777-4777-8777-777777777777' WHEN 'staff2' THEN '88888888-8888-4888-8888-888888888888'
 WHEN 'operator' THEN '99999999-9999-4999-8999-999999999999' WHEN 'sup' THEN 'd1111111-1111-4111-8111-111111111111'
 WHEN 'sup1001' THEN 'd2222222-2222-4222-8222-222222222222' WHEN 'tech1001' THEN 'd3333333-3333-4333-8333-333333333333'
 WHEN 'tech1002' THEN 'd4444444-4444-4444-8444-444444444444' WHEN 'reporter' THEN 'd5555555-5555-4555-8555-555555555555'
 WHEN 'auditor' THEN 'd6666666-6666-4666-8666-666666666666' WHEN 'revtech' THEN 'd7777777-7777-4777-8777-777777777777'
 WHEN 'sup2' THEN 'd8888888-8888-4888-8888-888888888888' WHEN 'bo102' THEN 'e1111111-1111-4111-8111-111111111111'
 WHEN 'newbie' THEN 'f1111111-1111-4111-8111-111111111111' END)::uuid $$;
CREATE FUNCTION c10_test.as_user(p text) RETURNS void LANGUAGE sql AS $$ SELECT set_config('request.jwt.claim.sub',c10_test.u(p)::text,true); SELECT 1 $$;
CREATE FUNCTION c10_test.eq(a text,b text,msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF a IS DISTINCT FROM b THEN RAISE EXCEPTION 'ASSERT % : got [%] want [%]',msg,a,b; END IF; END$$;
CREATE FUNCTION c10_test.eq(a boolean,b text,msg text) RETURNS void LANGUAGE sql AS $$ SELECT c10_test.eq(a::text,b,msg) $$;
CREATE FUNCTION c10_test.eq(a bigint,b text,msg text) RETURNS void LANGUAGE sql AS $$ SELECT c10_test.eq(a::text,b,msg) $$;
CREATE FUNCTION c10_test.eq(a int,b text,msg text) RETURNS void LANGUAGE sql AS $$ SELECT c10_test.eq(a::text,b,msg) $$;
CREATE FUNCTION c10_test.eq(a numeric,b text,msg text) RETURNS void LANGUAGE sql AS $$ SELECT c10_test.eq(a::text,b,msg) $$;
CREATE FUNCTION c10_test.denied(p_sql text,p_expect text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 BEGIN EXECUTE p_sql; EXCEPTION WHEN OTHERS THEN
  IF SQLERRM NOT LIKE p_expect||'%' THEN RAISE EXCEPTION 'WRONG_ERROR [%] for %: want %',SQLERRM,p_sql,p_expect; END IF; RETURN; END;
 RAISE EXCEPTION 'EXPECTED_DENIAL_DID_NOT_HAPPEN: %',p_sql;
END$$;
-- privileged fixtures (the module's own tables are closed to authenticated)
CREATE FUNCTION c10_test.aid(p_name text) RETURNS bigint LANGUAGE sql SECURITY DEFINER AS $$ SELECT id FROM c10_demo.am_assets WHERE name=p_name AND business_id=101 $$;
CREATE FUNCTION c10_test.aidb(p_biz bigint,p_name text) RETURNS bigint LANGUAGE sql SECURITY DEFINER AS $$ SELECT id FROM c10_demo.am_assets WHERE name=p_name AND business_id=p_biz $$;
CREATE FUNCTION c10_test.cid(p_biz bigint,p_code text) RETURNS bigint LANGUAGE sql SECURITY DEFINER AS $$ SELECT id FROM c10_demo.am_categories WHERE business_id=p_biz AND code=p_code $$;
CREATE FUNCTION c10_test.catver(p_biz bigint,p_code text) RETURNS bigint LANGUAGE sql SECURITY DEFINER AS $$ SELECT version FROM c10_demo.am_categories WHERE business_id=p_biz AND code=p_code $$;
CREATE FUNCTION c10_test.aver(p_asset bigint) RETURNS bigint LANGUAGE sql SECURITY DEFINER AS $$ SELECT version FROM c10_demo.am_assets WHERE id=p_asset $$;
CREATE FUNCTION c10_test.asite(p_asset bigint) RETURNS bigint LANGUAGE sql SECURITY DEFINER AS $$ SELECT site_id FROM c10_demo.am_assets WHERE id=p_asset $$;
CREATE FUNCTION c10_test.astatus(p_asset bigint) RETURNS text LANGUAGE sql SECURITY DEFINER AS $$ SELECT status FROM c10_demo.am_assets WHERE id=p_asset $$;
CREATE FUNCTION c10_test.mid(p_asset bigint,p_code text) RETURNS bigint LANGUAGE sql SECURITY DEFINER AS $$ SELECT id FROM c10_demo.am_meters WHERE asset_id=p_asset AND code=p_code $$;
CREATE FUNCTION c10_test.mver(p_meter bigint) RETURNS bigint LANGUAGE sql SECURITY DEFINER AS $$ SELECT version FROM c10_demo.am_meters WHERE id=p_meter $$;
CREATE FUNCTION c10_test.mcur(p_meter bigint) RETURNS numeric LANGUAGE sql SECURITY DEFINER AS $$ SELECT current_reading FROM c10_demo.am_meters WHERE id=p_meter $$;
CREATE FUNCTION c10_test.n_readings(p_meter bigint) RETURNS bigint LANGUAGE sql SECURITY DEFINER AS $$ SELECT count(*) FROM c10_demo.am_meter_readings WHERE meter_id=p_meter $$;
CREATE FUNCTION c10_test.meter_age(p_meter bigint,p_days int) RETURNS void LANGUAGE sql SECURITY DEFINER AS $$ UPDATE c10_demo.am_meters SET last_reading_at=now()-make_interval(days=>p_days) WHERE id=p_meter $$;
CREATE FUNCTION c10_test.n_assets(p_biz bigint) RETURNS bigint LANGUAGE sql SECURITY DEFINER AS $$ SELECT count(*) FROM c10_demo.am_assets WHERE business_id=p_biz $$;
CREATE FUNCTION c10_test.n_audit(p_entity text,p_event text) RETURNS bigint LANGUAGE sql SECURITY DEFINER AS $$ SELECT count(*) FROM c10_demo.am_audit WHERE entity=p_entity AND event=p_event $$;
CREATE FUNCTION c10_test.n_mov(p_asset bigint,p_kind text) RETURNS bigint LANGUAGE sql SECURITY DEFINER AS $$ SELECT count(*) FROM c10_demo.am_asset_movements WHERE asset_id=p_asset AND kind=p_kind $$;
CREATE FUNCTION c10_test.n_receipts() RETURNS bigint LANGUAGE sql SECURITY DEFINER AS $$ SELECT count(*) FROM c10_demo.am_receipts $$;
CREATE FUNCTION c10_test.mut_count() RETURNS bigint LANGUAGE sql SECURITY DEFINER AS $$ SELECT (SELECT count(*) FROM c10_demo.am_audit)+(SELECT count(*) FROM c10_demo.am_receipts)+(SELECT count(*) FROM c10_demo.am_assets)+(SELECT count(*) FROM c10_demo.am_meter_readings) $$;
CREATE FUNCTION c10_test.setpol(p_biz bigint,p_key text,p_val jsonb,p_scope text DEFAULT 'business',p_id bigint DEFAULT 0) RETURNS void LANGUAGE sql SECURITY DEFINER AS $$
 INSERT INTO c10_demo.am_policy(business_id,tenant_id,scope_type,scope_id,key,value,updated_by)
 VALUES(p_biz,(SELECT tenant_id FROM c10_demo.businesses WHERE id=p_biz),p_scope,p_id,p_key,p_val,'11111111-1111-4111-8111-111111111111')
 ON CONFLICT(business_id,scope_type,scope_id,key) DO UPDATE SET value=excluded.value $$;
CREATE FUNCTION c10_test.delpol(p_biz bigint,p_key text) RETURNS void LANGUAGE sql SECURITY DEFINER AS $$ DELETE FROM c10_demo.am_policy WHERE business_id=p_biz AND key=p_key $$;
CREATE FUNCTION c10_test.mkwo(p_asset bigint,p_status text) RETURNS bigint LANGUAGE sql SECURITY DEFINER AS $$
 INSERT INTO c10_demo.am_work_orders(tenant_id,business_id,wo_no,kind,status,asset_id,site_id,title,requested_by)
 SELECT tenant_id,business_id,'TW-'||substr(md5(random()::text),1,8),'corrective',p_status,id,site_id,'Test work order','11111111-1111-4111-8111-111111111111'
 FROM c10_demo.am_assets WHERE id=p_asset RETURNING id $$;
CREATE FUNCTION c10_test.wo_set(p_wo bigint,p_status text) RETURNS void LANGUAGE sql SECURITY DEFINER AS $$ UPDATE c10_demo.am_work_orders SET status=p_status WHERE id=p_wo $$;
CREATE FUNCTION c10_test.wo_site(p_wo bigint) RETURNS bigint LANGUAGE sql SECURITY DEFINER AS $$ SELECT site_id FROM c10_demo.am_work_orders WHERE id=p_wo $$;
CREATE FUNCTION c10_test.mkdt(p_asset bigint) RETURNS bigint LANGUAGE sql SECURITY DEFINER AS $$
 INSERT INTO c10_demo.am_downtime(tenant_id,business_id,asset_id,site_id,kind,started_at,started_by)
 SELECT tenant_id,business_id,id,site_id,'breakdown',now()-interval '1 hour','11111111-1111-4111-8111-111111111111' FROM c10_demo.am_assets WHERE id=p_asset RETURNING id $$;
CREATE FUNCTION c10_test.enddt(p_asset bigint) RETURNS void LANGUAGE sql SECURITY DEFINER AS $$ UPDATE c10_demo.am_downtime SET ended_at=now() WHERE asset_id=p_asset AND ended_at IS NULL $$;
CREATE FUNCTION c10_test.mkplan(p_asset bigint) RETURNS void LANGUAGE sql SECURITY DEFINER AS $$
 WITH p AS (INSERT INTO c10_demo.am_plans(tenant_id,business_id,name,plan_type,asset_id,frequency_kind,interval_n,start_on,created_by)
   SELECT tenant_id,business_id,'Monthly PM','preventive',id,'monthly',1,current_date,'11111111-1111-4111-8111-111111111111' FROM c10_demo.am_assets WHERE id=p_asset RETURNING id,tenant_id,business_id)
 INSERT INTO c10_demo.am_plan_targets(tenant_id,business_id,plan_id,asset_id,next_due_on) SELECT tenant_id,business_id,id,p_asset,current_date+10 FROM p $$;
CREATE FUNCTION c10_test.mkcal(p_asset bigint) RETURNS void LANGUAGE sql SECURITY DEFINER AS $$
 INSERT INTO c10_demo.am_cal_records(tenant_id,business_id,asset_id,plan_kind,performed_on,next_due_on,result,recorded_by)
 SELECT tenant_id,business_id,id,'calibration',current_date,current_date+90,'pass','11111111-1111-4111-8111-111111111111' FROM c10_demo.am_assets WHERE id=p_asset $$;
CREATE FUNCTION c10_test.gid(p_user uuid,p_role text) RETURNS bigint LANGUAGE sql SECURITY DEFINER AS $$ SELECT id FROM c10_demo.am_grants WHERE user_id=p_user AND role=p_role ORDER BY id LIMIT 1 $$;
CREATE FUNCTION c10_test.wver(p_id bigint) RETURNS bigint LANGUAGE sql SECURITY DEFINER AS $$ SELECT version FROM c10_demo.am_warranties WHERE id=p_id $$;
CREATE FUNCTION c10_test.cver(p_id bigint) RETURNS bigint LANGUAGE sql SECURITY DEFINER AS $$ SELECT version FROM c10_demo.am_warranty_claims WHERE id=p_id $$;
CREATE FUNCTION c10_test.tver(p_id bigint) RETURNS bigint LANGUAGE sql SECURITY DEFINER AS $$ SELECT version FROM c10_demo.am_transfers WHERE id=p_id $$;
CREATE FUNCTION c10_test.chain_ok() RETURNS boolean LANGUAGE sql SECURITY DEFINER AS $$
 SELECT NOT EXISTS(SELECT 1 FROM (SELECT a.*,lag(a.row_hash) OVER (PARTITION BY a.business_id ORDER BY a.id) AS exp_prev FROM c10_demo.am_audit a) x
  WHERE x.prev_hash IS DISTINCT FROM x.exp_prev) $$;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA c10_test TO authenticated,anon;

-- ===== R1 authority matrix: nobody without an explicit maintenance grant gets in (reads AND writes), before any data exists =====
BEGIN; SET LOCAL ROLE authenticated;
DO $$ DECLARE p text; BEGIN
 FOREACH p IN ARRAY ARRAY['stock','investor','revoked','owner2','staff2','operator','mgr101','revtech','sup2','bo102','newbie'] LOOP
  PERFORM c10_test.as_user(p);
  PERFORM c10_test.denied('SELECT c10_demo.am_list_assets_v1(101,NULL,10,0)','am_denied');
  PERFORM c10_test.denied('SELECT c10_demo.am_get_asset_v1(101,1)','am_denied');
  PERFORM c10_test.denied('SELECT c10_demo.am_list_catalog_v1(101)','am_denied');
  PERFORM c10_test.denied('SELECT c10_demo.am_list_grants_v1(101)','am_denied');
  PERFORM c10_test.denied('SELECT c10_demo.am_list_transfers_v1(101,NULL)','am_denied');
  PERFORM c10_test.denied('SELECT c10_demo.am_list_claims_v1(101,NULL,10,0)','am_denied');
  PERFORM c10_test.denied('SELECT c10_demo.am_list_warranties_v1(101,NULL)','am_denied');
  PERFORM c10_test.denied($q$SELECT c10_demo.am_create_asset_v1(101,'rg-deny-0001','{"name":"Hack asset","category_id":1,"site_id":1001}'::jsonb,'x y z')$q$,'am_denied');
  PERFORM c10_test.denied($q$SELECT c10_demo.am_grant_role_v1(101,'rg-deny-0002','f1111111-1111-4111-8111-111111111111','technician',NULL,NULL,'self help')$q$,'am_denied');
  PERFORM c10_test.denied($q$SELECT c10_demo.am_save_category_v1(101,'rg-deny-0003',0,NULL,'{"code":"HACK","name":"Hack"}'::jsonb,'x y z')$q$,'am_denied');
  PERFORM c10_test.denied($q$SELECT c10_demo.am_record_meter_reading_v1(101,'rg-deny-0004',1,5,NULL,NULL,NULL)$q$,'am_denied');
 END LOOP;
 PERFORM c10_test.as_user('owner2'); PERFORM c10_test.denied('SELECT c10_demo.am_list_assets_v1(102,NULL,10,0)','am_denied');
 PERFORM c10_test.as_user('bo101'); PERFORM c10_test.denied('SELECT c10_demo.am_list_assets_v1(102,NULL,10,0)','am_denied');
 PERFORM c10_test.denied('SELECT c10_demo.am_list_assets_v1(NULL,NULL,10,0)','am_denied');
 PERFORM c10_test.denied('SELECT c10_demo.am_list_assets_v1(999999,NULL,10,0)','am_denied');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_create_asset_v1(101,'short','{}'::jsonb,NULL)$q$,'am_invalid_request_key');
 -- direct table access is closed even for owners
 PERFORM c10_test.as_user('owner');
 PERFORM c10_test.denied('SELECT count(*) FROM c10_demo.am_assets','permission denied');
 PERFORM c10_test.denied('SELECT count(*) FROM c10_demo.am_grants','permission denied');
 PERFORM c10_test.denied('SELECT c10_demo.ami_r_site_chk(NULL,1)','permission denied');
 PERFORM c10_test.denied('SELECT c10_demo.ami_r_descendants(1)','permission denied');
END $$; COMMIT;
BEGIN; SET LOCAL ROLE authenticated;
DO $$ BEGIN PERFORM set_config('request.jwt.claim.sub','',true);
 PERFORM c10_test.denied('SELECT c10_demo.am_list_assets_v1(101,NULL,10,0)','am_denied');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_create_asset_v1(101,'rg-anon-00001','{}'::jsonb,NULL)$q$,'am_denied'); END $$; COMMIT;
BEGIN; SET LOCAL ROLE anon;
DO $$ BEGIN PERFORM c10_test.denied('SELECT c10_demo.am_list_assets_v1(101,NULL,10,0)','permission denied');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_create_asset_v1(101,'rg-anon-00002','{}'::jsonb,NULL)$q$,'permission denied'); END $$; COMMIT;

-- ===== R2 grants (owner only; user must be uuid; reactivation; validation; replay/conflict; audit) =====
BEGIN; SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb; g bigint; n0 bigint; BEGIN
 PERFORM c10_test.as_user('sup');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_grant_role_v1(101,'rg-grant-0001','f1111111-1111-4111-8111-111111111111','technician',1002,NULL,'supervisor tries')$q$,'am_owner_required');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_revoke_role_v1(101,'rg-grant-0002',1,'supervisor tries')$q$,'am_owner_required');
 PERFORM c10_test.denied('SELECT c10_demo.am_list_grants_v1(101)','am_owner_required');
 PERFORM c10_test.as_user('tech1001');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_grant_role_v1(101,'rg-grant-0003','f1111111-1111-4111-8111-111111111111','supervisor',NULL,NULL,'escalate me')$q$,'am_owner_required');
 PERFORM c10_test.as_user('auditor'); PERFORM c10_test.denied('SELECT c10_demo.am_list_grants_v1(101)','am_owner_required');
 PERFORM c10_test.as_user('bo101');
 n0:=c10_test.n_receipts();
 r:=c10_demo.am_grant_role_v1(101,'rg-grant-0010','f1111111-1111-4111-8111-111111111111','technician',1002,'night shift tech','onboarding technician');
 PERFORM c10_test.eq(r->>'status','applied','grant applied'); PERFORM c10_test.eq(r->>'reactivated','false','new grant');
 g:=(r->>'grant_id')::bigint;
 PERFORM c10_test.eq(c10_demo.am_grant_role_v1(101,'rg-grant-0010','f1111111-1111-4111-8111-111111111111','technician',1002,'night shift tech','onboarding technician')->>'grant_id',g::text,'replay returns same receipt');
 PERFORM c10_test.eq(c10_test.n_receipts()-n0,'1','replay wrote no second receipt');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_grant_role_v1(101,'rg-grant-0010','f1111111-1111-4111-8111-111111111111','reporter',1002,'night shift tech','onboarding technician')$q$,'am_idempotency_conflict');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_grant_role_v1(101,'rg-grant-0011','f1111111-1111-4111-8111-111111111111','technician',1002,NULL,'duplicate active grant')$q$,'am_duplicate_grant');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_grant_role_v1(101,'rg-grant-0012','f1111111-1111-4111-8111-111111111111','owner',NULL,NULL,'escalate to owner')$q$,'am_invalid_input');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_grant_role_v1(101,'rg-grant-0013','f1111111-1111-4111-8111-111111111111','manager',NULL,NULL,'unknown role')$q$,'am_invalid_input');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_grant_role_v1(101,'rg-grant-0014','f1111111-1111-4111-8111-111111111111','reporter',1003,NULL,'site of other business')$q$,'am_invalid_input');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_grant_role_v1(101,'rg-grant-0015','f1111111-1111-4111-8111-111111111111','reporter',2001,NULL,'site of other tenant')$q$,'am_invalid_input');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_grant_role_v1(101,'rg-grant-0016','22222222-2222-4222-8222-222222222222','supervisor',NULL,NULL,'self grant')$q$,'am_invalid_input');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_grant_role_v1(101,'rg-grant-0017','00000000-0000-0000-0000-000000000000','reporter',NULL,NULL,'nil uuid')$q$,'am_invalid_input');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_grant_role_v1(101,'rg-grant-0018',NULL,'reporter',NULL,NULL,'null user')$q$,'am_invalid_input');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_grant_role_v1(101,'rg-grant-0019','f1111111-1111-4111-8111-111111111111','reporter',NULL,NULL,NULL)$q$,'am_invalid_input');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_grant_role_v1(101,'rg-grant-0020','f1111111-1111-4111-8111-111111111111','reporter',NULL,repeat('n',201),'long note')$q$,'am_invalid_input');
 -- the new grant is effective immediately, and only for its site
 PERFORM c10_test.as_user('newbie');
 PERFORM c10_test.eq(jsonb_array_length(c10_demo.am_list_catalog_v1(101)->'sites')::text,'1','newbie sees exactly site 1002');
 PERFORM c10_test.eq(c10_demo.am_list_catalog_v1(101)->'sites'->0->>'id','1002','newbie site');
 PERFORM c10_test.denied('SELECT c10_demo.am_list_grants_v1(101)','am_owner_required');
 -- list (owner) + revoke + reactivate
 PERFORM c10_test.as_user('owner');
 r:=c10_demo.am_list_grants_v1(101);
 PERFORM c10_test.eq((r->>'total')::int>=8,'true','owner lists grants incl. seeded');
 PERFORM c10_test.eq(c10_demo.am_revoke_role_v1(101,'rg-grant-0030',g,'offboarding')->>'status','applied','revoke applied');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_revoke_role_v1(101,'rg-grant-0031',$q$||g||$q$,'again')$q$,'am_invalid_state');
 PERFORM c10_test.as_user('newbie'); PERFORM c10_test.denied('SELECT c10_demo.am_list_catalog_v1(101)','am_denied');
 PERFORM c10_test.as_user('bo101');
 r:=c10_demo.am_grant_role_v1(101,'rg-grant-0032','f1111111-1111-4111-8111-111111111111','technician',1002,'back again','reactivation');
 PERFORM c10_test.eq(r->>'reactivated','true','revoked grant reactivated'); PERFORM c10_test.eq(r->>'grant_id',g::text,'same grant row reused');
 PERFORM c10_test.as_user('newbie'); PERFORM c10_test.eq(jsonb_array_length(c10_demo.am_list_catalog_v1(101)->'sites')::text,'1','newbie back in');
 PERFORM c10_test.as_user('bo101');
 PERFORM c10_demo.am_revoke_role_v1(101,'rg-grant-0033',g,'final offboarding');
 -- another business's / tenant's grant ids are invisible
 PERFORM c10_test.denied($q$SELECT c10_demo.am_revoke_role_v1(101,'rg-grant-0034',$q$||c10_test.gid(c10_test.u('sup2'),'supervisor')||$q$,'cross tenant')$q$,'am_denied');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_revoke_role_v1(101,'rg-grant-0035',987654,'unknown')$q$,'am_denied');
 PERFORM c10_test.eq(c10_test.n_audit('grant','granted')>=1 AND c10_test.n_audit('grant','revoked')>=2 AND c10_test.n_audit('grant','reactivated')=1,'true','grant audit rows');
END $$; COMMIT;

-- ===== R3 categories & codes (owner; hierarchy w/o cycles; uniqueness; optimistic version; inactive not usable) =====
BEGIN; SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb; c1 bigint; c2 bigint; c3 bigint; v bigint; BEGIN
 PERFORM c10_test.as_user('sup');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_save_category_v1(101,'rg-cat-00001',0,NULL,'{"code":"CNC","name":"CNC machine"}'::jsonb,'supervisor tries')$q$,'am_owner_required');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_save_code_v1(101,'rg-code-0001','failure','JAM','Jam',NULL,true,'supervisor tries')$q$,'am_owner_required');
 PERFORM c10_test.as_user('bo101');
 PERFORM c10_test.eq(jsonb_array_length(c10_demo.am_list_catalog_v1(101)->'categories')::text,'10','bootstrapped neutral categories visible');
 PERFORM c10_test.eq(jsonb_array_length(c10_demo.am_list_catalog_v1(101)->'sites')::text,'4','owner catalog lists 4 sites');
 r:=c10_demo.am_save_category_v1(101,'rg-cat-00002',0,NULL,'{"code":"cnc","name":"CNC machine","name_bn":"সিএনসি","asset_kind":"equipment","default_criticality":4,"default_meter_unit":"hours","useful_life_months":120,"salvage_pct":5.5}'::jsonb,'new category');
 c1:=(r->>'category_id')::bigint; PERFORM c10_test.eq(r->>'version','1','category v1');
 PERFORM c10_test.eq(c10_test.cid(101,'CNC'),c1::text,'code is upper-cased');
 PERFORM c10_test.eq(c10_demo.am_save_category_v1(101,'rg-cat-00002',0,NULL,'{"code":"cnc","name":"CNC machine","name_bn":"সিএনসি","asset_kind":"equipment","default_criticality":4,"default_meter_unit":"hours","useful_life_months":120,"salvage_pct":5.5}'::jsonb,'new category')->>'category_id',c1::text,'category replay');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_save_category_v1(101,'rg-cat-00003',0,NULL,'{"code":"CNC","name":"Duplicate"}'::jsonb,'dup code')$q$,'am_duplicate_code');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_save_category_v1(101,'rg-cat-00004',0,NULL,'{"code":"BAD CODE","name":"Bad"}'::jsonb,'bad code')$q$,'am_invalid_input');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_save_category_v1(101,'rg-cat-00005',0,NULL,'{"code":"X1","name":"x"}'::jsonb,'short name')$q$,'am_invalid_input');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_save_category_v1(101,'rg-cat-00006',0,NULL,'{"code":"X2","name":"Valid name","evil":1}'::jsonb,'unknown key')$q$,'am_invalid_input');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_save_category_v1(101,'rg-cat-00007',0,NULL,'{"code":"X3","name":"Valid name","default_criticality":9}'::jsonb,'range')$q$,'am_invalid_input');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_save_category_v1(101,'rg-cat-00008',0,NULL,'{"code":"X4","name":"Valid name","safety_critical":"yes"}'::jsonb,'type')$q$,'am_invalid_input');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_save_category_v1(101,'rg-cat-00009',0,NULL,'{"code":"X5","name":"Valid name","parent_id":999999}'::jsonb,'parent missing')$q$,'am_invalid_input');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_save_category_v1(101,'rg-cat-00010',0,NULL,'[1]'::jsonb,'array')$q$,'am_invalid_input');
 -- hierarchy
 r:=c10_demo.am_save_category_v1(101,'rg-cat-00011',0,NULL,('{"code":"CNC-LATHE","name":"Lathe","parent_id":'||c1||'}')::jsonb,'child'); c2:=(r->>'category_id')::bigint;
 r:=c10_demo.am_save_category_v1(101,'rg-cat-00012',0,NULL,('{"code":"CNC-LATHE-X","name":"Lathe X","parent_id":'||c2||'}')::jsonb,'grandchild'); c3:=(r->>'category_id')::bigint;
 PERFORM c10_test.denied($q$SELECT c10_demo.am_save_category_v1(101,'rg-cat-00013',$q$||c1||$q$,1,('{"parent_id":$q$||c3||$q$}')::jsonb,'cycle')$q$,'am_category_cycle');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_save_category_v1(101,'rg-cat-00014',$q$||c1||$q$,1,('{"parent_id":$q$||c1||$q$}')::jsonb,'self parent')$q$,'am_category_cycle');
 -- optimistic version
 r:=c10_demo.am_save_category_v1(101,'rg-cat-00015',c1,1,'{"name":"CNC machines","default_criticality":5}'::jsonb,'rename'); PERFORM c10_test.eq(r->>'version','2','category v2');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_save_category_v1(101,'rg-cat-00016',$q$||c1||$q$,1,'{"name":"Stale"}'::jsonb,'stale')$q$,'am_stale_version');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_save_category_v1(101,'rg-cat-00017',$q$||c1||$q$,NULL,'{"name":"No version"}'::jsonb,'missing version')$q$,'am_invalid_input');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_save_category_v1(101,'rg-cat-00018',$q$||c1||$q$,2,'{}'::jsonb,'empty changes')$q$,'am_invalid_input');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_save_category_v1(101,'rg-cat-00019',555555,1,'{"name":"Ghost"}'::jsonb,'unknown id')$q$,'am_denied');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_save_category_v1(101,'rg-cat-00020',$q$||c1||$q$,2,'{"code":"COLD"}'::jsonb,'code clash on update')$q$,'am_duplicate_code');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_save_category_v1(101,'rg-cat-00021',$q$||c10_test.cid(101,'COLD')||$q$,1,'{"code":"FRIDGE"}'::jsonb,'system code immutable')$q$,'am_invalid_input');
 PERFORM c10_test.eq(c10_demo.am_save_category_v1(101,'rg-cat-00022',c1,2,'{"parent_id":null,"salvage_pct":null}'::jsonb,'clear nullable fields')->>'version','3','null clears nullable');
 -- deactivate: allowed, but not usable for new assets / as parent
 PERFORM c10_demo.am_save_category_v1(101,'rg-cat-00023',c2,1,'{"active":false}'::jsonb,'retire category');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_create_asset_v1(101,'rg-cat-00024','{"name":"Lathe unit","category_id":$q$||c2||$q$,"site_id":1002}'::jsonb,NULL)$q$,'am_category_inactive');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_save_category_v1(101,'rg-cat-00025',0,NULL,'{"code":"UNDER-OFF","name":"Under inactive","parent_id":$q$||c2||$q$}'::jsonb,'inactive parent')$q$,'am_category_inactive');
 PERFORM c10_demo.am_save_category_v1(101,'rg-cat-00026',c2,2,'{"active":true}'::jsonb,'reactivate');
 -- codes
 r:=c10_demo.am_save_code_v1(101,'rg-code-0002','failure','jam','Material jam','জ্যাম',true,'new failure code');
 PERFORM c10_test.eq(r->>'created','true','code created');
 PERFORM c10_test.eq(c10_demo.am_save_code_v1(101,'rg-code-0003','failure','JAM','Material jam (renamed)',NULL,false,'update')->>'created','false','code upserted');
 PERFORM c10_test.eq(c10_demo.am_save_code_v1(101,'rg-code-0004','failure','MECH','Mechanical (edited)','যান্ত্রিক',true,'edit system code')->>'created','false','system code editable label');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_save_code_v1(101,'rg-code-0005','nonsense','JAM','Jam',NULL,true,'bad kind')$q$,'am_invalid_input');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_save_code_v1(101,'rg-code-0006','failure','bad code!','Jam',NULL,true,'bad code')$q$,'am_invalid_input');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_save_code_v1(101,'rg-code-0007','failure','OK1','x',NULL,true,'short label')$q$,'am_invalid_input');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_save_code_v1(101,'rg-code-0008','failure','OK2','Fine label',NULL,NULL,'null active')$q$,'am_invalid_input');
 PERFORM c10_test.eq((SELECT x FROM jsonb_array_elements(c10_demo.am_list_catalog_v1(101)->'codes') x WHERE x->>'code'='JAM')->>'active','false','code deactivated in catalog');
 PERFORM c10_test.eq(c10_test.n_audit('category','created')=3 AND c10_test.n_audit('category','updated')>=3 AND c10_test.n_audit('code','created')=1,'true','category/code audit');
 -- a second business has its own catalog and cannot see/use the first one's categories
 PERFORM c10_test.as_user('bo102');
 PERFORM c10_test.eq(jsonb_array_length(c10_demo.am_list_catalog_v1(102)->'categories')::text,'0','business 102 not bootstrapped yet (reads never write)');
 PERFORM c10_test.eq(c10_demo.am_save_category_v1(102,'rg-cat-10201',0,NULL,'{"code":"CNC","name":"CNC in 102"}'::jsonb,'same code other business')->>'status','applied','code unique per business only');
END $$; COMMIT;

-- ===== R4 asset create =====
BEGIN; SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb; r2 jsonb; a1 bigint; n0 bigint; BEGIN
 PERFORM c10_test.as_user('sup');
 r:=c10_demo.am_create_asset_v1(101,'rg-ast-00001',jsonb_build_object('name','Oven One','category_id',c10_test.cid(101,'PROD-EQ'),'site_id',1002,
   'serial_no','SN-1001','manufacturer','Baker Bros','model','BB-9','criticality',4,'location_note','Bay 2','ownership','owned','purchase_order_ref','PO-2026/17',
   'custodian_ref','EMP-0042','acquisition_date','2025-01-10','commission_date','2025-02-01','acquisition_cost',150000.50,'quantity',1,
   'custom_attrs',jsonb_build_object('voltage','415V','phases',3,'gas',true),
   'meters',jsonb_build_array(jsonb_build_object('code','RUNHRS','unit','hours','reading',120.5),jsonb_build_object('code','CYCLES','unit','cycles')),
   'warranty',jsonb_build_object('supplier_name','Baker Bros Ltd','supplier_ref','W-77','coverage','Parts and labour','starts_on','2025-02-01','expires_on','2027-01-31')),
   'register new oven');
 a1:=(r->>'asset_id')::bigint;
 PERFORM c10_test.eq(r->>'asset_no' ~ '^AST-[0-9]{6}$','true','canonical asset_no from counter'); PERFORM c10_test.eq(r->>'version','1','asset v1');
 PERFORM c10_test.eq(jsonb_array_length(r->'meter_ids')::text,'2','two meters embedded'); PERFORM c10_test.eq((r->>'warranty_id') IS NOT NULL,'true','warranty embedded');
 PERFORM c10_test.eq(c10_test.aid('Oven One'),a1::text,'asset persisted');
 PERFORM c10_test.eq(c10_test.n_mov(a1,'initial'),'1','initial movement row');
 PERFORM c10_test.eq(c10_test.n_readings(c10_test.mid(a1,'RUNHRS')),'1','initial reading row only when given');
 PERFORM c10_test.eq(c10_test.n_readings(c10_test.mid(a1,'CYCLES')),'0','no reading row when none given');
 PERFORM c10_test.eq(c10_test.mcur(c10_test.mid(a1,'RUNHRS')),'120.500','meter current reading');
 PERFORM c10_test.eq(c10_test.n_audit('asset','created')>=1 AND c10_test.n_audit('meter','created')>=2 AND c10_test.n_audit('warranty','created')>=1,'true','create audit rows');
 -- replay / conflict
 n0:=c10_test.n_assets(101);
 r2:=c10_demo.am_create_asset_v1(101,'rg-ast-00001',jsonb_build_object('name','Oven One','category_id',c10_test.cid(101,'PROD-EQ'),'site_id',1002,
   'serial_no','SN-1001','manufacturer','Baker Bros','model','BB-9','criticality',4,'location_note','Bay 2','ownership','owned','purchase_order_ref','PO-2026/17',
   'custodian_ref','EMP-0042','acquisition_date','2025-01-10','commission_date','2025-02-01','acquisition_cost',150000.50,'quantity',1,
   'custom_attrs',jsonb_build_object('voltage','415V','phases',3,'gas',true),
   'meters',jsonb_build_array(jsonb_build_object('code','RUNHRS','unit','hours','reading',120.5),jsonb_build_object('code','CYCLES','unit','cycles')),
   'warranty',jsonb_build_object('supplier_name','Baker Bros Ltd','supplier_ref','W-77','coverage','Parts and labour','starts_on','2025-02-01','expires_on','2027-01-31')),
   'register new oven');
 PERFORM c10_test.eq(r2->>'asset_id',a1::text,'replay same asset'); PERFORM c10_test.eq(c10_test.n_assets(101),n0::text,'replay creates no asset');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_create_asset_v1(101,'rg-ast-00001','{"name":"Different","category_id":1,"site_id":1002}'::jsonb,NULL)$q$,'am_idempotency_conflict');
 PERFORM c10_test.as_user('bo101');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_create_asset_v1(101,'rg-ast-00001',jsonb_build_object('name','Oven One','category_id',1,'site_id',1002),NULL)$q$,'am_idempotency_conflict');
 -- duplicate serial (same manufacturer, case-insensitive) vs different manufacturer
 PERFORM c10_test.as_user('sup');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_create_asset_v1(101,'rg-ast-00002',jsonb_build_object('name','Oven Dup','category_id',c10_test.cid(101,'PROD-EQ'),'site_id',1002,'serial_no','sn-1001','manufacturer','BAKER BROS'),NULL)$q$,'am_duplicate_serial');
 PERFORM c10_test.eq(c10_test.n_assets(101),n0::text,'failed create leaves nothing behind');
 PERFORM c10_demo.am_create_asset_v1(101,'rg-ast-00003',jsonb_build_object('name','Oven Other Make','category_id',c10_test.cid(101,'PROD-EQ'),'site_id',1002,'serial_no','SN-1001','manufacturer','Other Maker'),NULL);
 -- require_serial policy (business + per-category override)
 PERFORM c10_test.setpol(101,'asset.require_serial','true'::jsonb);
 PERFORM c10_test.denied($q$SELECT c10_demo.am_create_asset_v1(101,'rg-ast-00004',jsonb_build_object('name','No serial','category_id',c10_test.cid(101,'PROD-EQ'),'site_id',1002),NULL)$q$,'am_serial_required');
 PERFORM c10_test.setpol(101,'asset.require_serial','false'::jsonb,'category',c10_test.cid(101,'IT'));
 PERFORM c10_test.eq(c10_demo.am_create_asset_v1(101,'rg-ast-00005',jsonb_build_object('name','Laptop no serial ok','category_id',c10_test.cid(101,'IT'),'site_id',1001),NULL)->>'status','applied','category override relaxes serial rule');
 PERFORM c10_test.delpol(101,'asset.require_serial'); PERFORM c10_test.delpol(101,'asset.require_serial');
 -- capability matrix
 PERFORM c10_test.as_user('sup1001');
 PERFORM c10_test.eq(c10_demo.am_create_asset_v1(101,'rg-ast-00006',jsonb_build_object('name','POS Counter 1','category_id',c10_test.cid(101,'POS'),'site_id',1001,'status','planned','quantity',2.5),'register POS')->>'status','applied','site supervisor creates at own site');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_create_asset_v1(101,'rg-ast-00007',jsonb_build_object('name','Wrong site','category_id',1,'site_id',1002),NULL)$q$,'am_not_permitted');
 PERFORM c10_test.as_user('tech1001'); PERFORM c10_test.denied($q$SELECT c10_demo.am_create_asset_v1(101,'rg-ast-00008',jsonb_build_object('name','Tech asset','category_id',1,'site_id',1001),NULL)$q$,'am_not_permitted');
 PERFORM c10_test.as_user('reporter'); PERFORM c10_test.denied($q$SELECT c10_demo.am_create_asset_v1(101,'rg-ast-00009',jsonb_build_object('name','Rep asset','category_id',1,'site_id',1001),NULL)$q$,'am_not_permitted');
 PERFORM c10_test.as_user('auditor'); PERFORM c10_test.denied($q$SELECT c10_demo.am_create_asset_v1(101,'rg-ast-00010',jsonb_build_object('name','Audit asset','category_id',1,'site_id',1001),NULL)$q$,'am_not_permitted');
 PERFORM c10_test.as_user('sup1001'); PERFORM c10_test.denied($q$SELECT c10_demo.am_create_asset_v1(101,'rg-ast-00011',jsonb_build_object('name','Foreign site','category_id',1,'site_id',1003),NULL)$q$,'am_denied');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_create_asset_v1(101,'rg-ast-00012',jsonb_build_object('name','Foreign tenant site','category_id',1,'site_id',2001),NULL)$q$,'am_denied');
 PERFORM c10_test.as_user('bo101');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_create_asset_v1(101,'rg-ast-00013',jsonb_build_object('name','Foreign site','category_id',1,'site_id',1003),NULL)$q$,'am_invalid_input');
 -- validation edge cases
 PERFORM c10_test.as_user('sup');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_create_asset_v1(101,'rg-ast-00014','{"name":"A","category_id":1,"site_id":1002}'::jsonb,NULL)$q$,'am_invalid_input');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_create_asset_v1(101,'rg-ast-00015','{"category_id":1,"site_id":1002}'::jsonb,NULL)$q$,'am_invalid_input');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_create_asset_v1(101,'rg-ast-00016',jsonb_build_object('name','Zero qty','category_id',c10_test.cid(101,'GENERAL'),'site_id',1002,'quantity',0),NULL)$q$,'am_invalid_input');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_create_asset_v1(101,'rg-ast-00017',jsonb_build_object('name','String qty','category_id',c10_test.cid(101,'GENERAL'),'site_id',1002,'quantity','5'),NULL)$q$,'am_invalid_input');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_create_asset_v1(101,'rg-ast-00018',jsonb_build_object('name','Neg cost','category_id',c10_test.cid(101,'GENERAL'),'site_id',1002,'acquisition_cost',-1),NULL)$q$,'am_invalid_input');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_create_asset_v1(101,'rg-ast-00019',jsonb_build_object('name','Bad dates','category_id',c10_test.cid(101,'GENERAL'),'site_id',1002,'acquisition_date','2025-05-01','commission_date','2025-04-01'),NULL)$q$,'am_invalid_input');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_create_asset_v1(101,'rg-ast-00020',jsonb_build_object('name','Bad date fmt','category_id',c10_test.cid(101,'GENERAL'),'site_id',1002,'acquisition_date','2025-13-45'),NULL)$q$,'am_invalid_input');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_create_asset_v1(101,'rg-ast-00021',jsonb_build_object('name','Bad serial','category_id',c10_test.cid(101,'GENERAL'),'site_id',1002,'serial_no','bad serial!'),NULL)$q$,'am_invalid_input');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_create_asset_v1(101,'rg-ast-00022',jsonb_build_object('name','Own enum','category_id',c10_test.cid(101,'GENERAL'),'site_id',1002,'ownership','stolen'),NULL)$q$,'am_invalid_input');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_create_asset_v1(101,'rg-ast-00023',jsonb_build_object('name','Breakdown','category_id',c10_test.cid(101,'GENERAL'),'site_id',1002,'status','breakdown'),NULL)$q$,'am_invalid_input');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_create_asset_v1(101,'rg-ast-00024',jsonb_build_object('name','Retired','category_id',c10_test.cid(101,'GENERAL'),'site_id',1002,'status','retired'),NULL)$q$,'am_invalid_input');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_create_asset_v1(101,'rg-ast-00025',jsonb_build_object('name','Set asset no','category_id',c10_test.cid(101,'GENERAL'),'site_id',1002,'asset_no','AST-999999'),NULL)$q$,'am_invalid_input');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_create_asset_v1(101,'rg-ast-00026',jsonb_build_object('name','Set id','category_id',c10_test.cid(101,'GENERAL'),'site_id',1002,'id',77),NULL)$q$,'am_invalid_input');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_create_asset_v1(101,'rg-ast-00027',jsonb_build_object('name','Missing cat','category_id',424242,'site_id',1002),NULL)$q$,'am_invalid_input');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_create_asset_v1(101,'rg-ast-00028',jsonb_build_object('name','Other biz cat','category_id',c10_test.cid(102,'CNC'),'site_id',1002),NULL)$q$,'am_invalid_input');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_create_asset_v1(101,'rg-ast-00029',jsonb_build_object('name','Long reason','category_id',c10_test.cid(101,'GENERAL'),'site_id',1002),'x')$q$,'am_invalid_input');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_create_asset_v1(101,'rg-ast-00030','[]'::jsonb,NULL)$q$,'am_invalid_input');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_create_asset_v1(101,'rg-ast-00031',NULL,NULL)$q$,'am_invalid_input');
 -- custom_attrs: flat object, scalar values, <= 4KB
 PERFORM c10_test.denied($q$SELECT c10_demo.am_create_asset_v1(101,'rg-ast-00032',jsonb_build_object('name','Nested attrs','category_id',c10_test.cid(101,'GENERAL'),'site_id',1002,'custom_attrs',jsonb_build_object('a',jsonb_build_object('b',1))),NULL)$q$,'am_invalid_input');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_create_asset_v1(101,'rg-ast-00033',jsonb_build_object('name','Array attrs','category_id',c10_test.cid(101,'GENERAL'),'site_id',1002,'custom_attrs',jsonb_build_array(1,2)),NULL)$q$,'am_invalid_input');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_create_asset_v1(101,'rg-ast-00034',jsonb_build_object('name','Array leaf','category_id',c10_test.cid(101,'GENERAL'),'site_id',1002,'custom_attrs',jsonb_build_object('a',jsonb_build_array(1))),NULL)$q$,'am_invalid_input');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_create_asset_v1(101,'rg-ast-00035',jsonb_build_object('name','Huge attrs','category_id',c10_test.cid(101,'GENERAL'),'site_id',1002,'custom_attrs',(SELECT jsonb_object_agg('k'||i,repeat('x',480)) FROM generate_series(1,12) i)),NULL)$q$,'am_invalid_input');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_create_asset_v1(101,'rg-ast-00036',jsonb_build_object('name','Bad key attrs','category_id',c10_test.cid(101,'GENERAL'),'site_id',1002,'custom_attrs',jsonb_build_object('bad key',1)),NULL)$q$,'am_invalid_input');
 -- embedded meters / warranty validation (whole create rolled back)
 PERFORM c10_test.denied($q$SELECT c10_demo.am_create_asset_v1(101,'rg-ast-00037',jsonb_build_object('name','Dup meters','category_id',c10_test.cid(101,'PROD-EQ'),'site_id',1002,'meters',jsonb_build_array(jsonb_build_object('code','M1','unit','hours'),jsonb_build_object('code','m1','unit','km'))),NULL)$q$,'am_duplicate_meter');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_create_asset_v1(101,'rg-ast-00038',jsonb_build_object('name','Bad meter','category_id',c10_test.cid(101,'POS'),'site_id',1002,'meters',jsonb_build_array(jsonb_build_object('code','M1'))),NULL)$q$,'am_invalid_input');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_create_asset_v1(101,'rg-ast-00039',jsonb_build_object('name','Neg meter','category_id',c10_test.cid(101,'PROD-EQ'),'site_id',1002,'meters',jsonb_build_array(jsonb_build_object('code','M1','reading',-3))),NULL)$q$,'am_invalid_input');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_create_asset_v1(101,'rg-ast-00040',jsonb_build_object('name','Bad warranty','category_id',c10_test.cid(101,'PROD-EQ'),'site_id',1002,'warranty',jsonb_build_object('supplier_name','Vendor','starts_on','2026-05-01','expires_on','2026-01-01')),NULL)$q$,'am_invalid_input');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_create_asset_v1(101,'rg-ast-00041',jsonb_build_object('name','Bad warranty 2','category_id',c10_test.cid(101,'PROD-EQ'),'site_id',1002,'warranty',jsonb_build_object('supplier_name','Vendor','starts_on','2026-05-01')),NULL)$q$,'am_invalid_input');
 PERFORM c10_test.eq(c10_test.aid('Dup meters') IS NULL AND c10_test.aid('Bad warranty') IS NULL,'true','rolled-back creates left no assets');
 -- assemblies
 PERFORM c10_test.eq(c10_demo.am_create_asset_v1(101,'rg-ast-00042',jsonb_build_object('name','Oven One Fan','category_id',c10_test.cid(101,'GENERAL'),'site_id',1002,'parent_asset_id',a1),'sub-assembly')->>'status','applied','child at the parent site');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_create_asset_v1(101,'rg-ast-00043',jsonb_build_object('name','Remote fan','category_id',c10_test.cid(101,'GENERAL'),'site_id',1001,'parent_asset_id',$q$||a1||$q$),NULL)$q$,'am_parent_site_mismatch');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_create_asset_v1(101,'rg-ast-00044',jsonb_build_object('name','Orphan child','category_id',c10_test.cid(101,'GENERAL'),'site_id',1002,'parent_asset_id',999999),NULL)$q$,'am_invalid_input');
END $$; COMMIT;

-- ===== R5 asset update (not site/status/asset_no; optimistic; assembly rules; role matrix) =====
BEGIN; SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb; a1 bigint:=c10_test.aid('Oven One'); fan bigint:=c10_test.aid('Oven One Fan'); o2 bigint:=c10_test.aid('Oven Other Make');
 pos bigint:=c10_test.aid('POS Counter 1'); lap bigint:=c10_test.aid('Laptop no serial ok'); v bigint; BEGIN
 PERFORM c10_test.as_user('sup');
 v:=c10_test.aver(a1);
 r:=c10_demo.am_update_asset_v1(101,'rg-upd-00001',a1,v,'{"name":"Oven One (Line A)","location_note":"Bay 3","custom_attrs":{"voltage":"400V"},"acquisition_cost":160000,"custodian_ref":null}'::jsonb,'relocated within bay');
 PERFORM c10_test.eq(r->>'version',(v+1)::text,'version bumped');
 PERFORM c10_test.eq(c10_test.aver(a1),(v+1)::text,'persisted version');
 PERFORM c10_test.eq(c10_demo.am_update_asset_v1(101,'rg-upd-00001',a1,v,'{"name":"Oven One (Line A)","location_note":"Bay 3","custom_attrs":{"voltage":"400V"},"acquisition_cost":160000,"custodian_ref":null}'::jsonb,'relocated within bay')->>'version',(v+1)::text,'update replay returns original receipt');
 PERFORM c10_test.eq(c10_test.aver(a1),(v+1)::text,'replay changed nothing');
 v:=v+1;
 PERFORM c10_test.denied($q$SELECT c10_demo.am_update_asset_v1(101,'rg-upd-00002',$q$||a1||$q$,1,'{"name":"Stale write"}'::jsonb,NULL)$q$,'am_stale_version');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_update_asset_v1(101,'rg-upd-00003',$q$||a1||$q$,$q$||v||$q$,'{"site_id":1001}'::jsonb,NULL)$q$,'am_invalid_input');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_update_asset_v1(101,'rg-upd-00004',$q$||a1||$q$,$q$||v||$q$,'{"status":"retired"}'::jsonb,NULL)$q$,'am_invalid_input');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_update_asset_v1(101,'rg-upd-00005',$q$||a1||$q$,$q$||v||$q$,'{"asset_no":"AST-000099"}'::jsonb,NULL)$q$,'am_invalid_input');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_update_asset_v1(101,'rg-upd-00006',$q$||a1||$q$,$q$||v||$q$,'{}'::jsonb,NULL)$q$,'am_invalid_input');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_update_asset_v1(101,'rg-upd-00007',$q$||a1||$q$,$q$||v||$q$,'{"quantity":null}'::jsonb,NULL)$q$,'am_invalid_input');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_update_asset_v1(101,'rg-upd-00008',$q$||a1||$q$,$q$||v||$q$,'{"custom_attrs":{"a":{"b":1}}}'::jsonb,NULL)$q$,'am_invalid_input');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_update_asset_v1(101,'rg-upd-00009',$q$||a1||$q$,$q$||v||$q$,'{"criticality":6}'::jsonb,NULL)$q$,'am_invalid_input');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_update_asset_v1(101,'rg-upd-00010',$q$||a1||$q$,NULL,'{"name":"No version"}'::jsonb,NULL)$q$,'am_invalid_input');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_update_asset_v1(101,'rg-upd-00011',$q$||a1||$q$,$q$||v||$q$,'{"commission_date":"2000-01-01"}'::jsonb,NULL)$q$,'am_invalid_input');
 -- duplicate serial on update
 PERFORM c10_test.denied($q$SELECT c10_demo.am_update_asset_v1(101,'rg-upd-00012',$q$||o2||$q$,$q$||c10_test.aver(o2)||$q$,'{"serial_no":"SN-1001","manufacturer":"Baker Bros"}'::jsonb,NULL)$q$,'am_duplicate_serial');
 -- assemblies: cycle, site mismatch, retired/foreign parent
 PERFORM c10_test.denied($q$SELECT c10_demo.am_update_asset_v1(101,'rg-upd-00013',$q$||a1||$q$,$q$||v||$q$,('{"parent_asset_id":$q$||fan||$q$}')::jsonb,NULL)$q$,'am_assembly_cycle_or_too_deep');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_update_asset_v1(101,'rg-upd-00014',$q$||a1||$q$,$q$||v||$q$,('{"parent_asset_id":$q$||a1||$q$}')::jsonb,NULL)$q$,'am_assembly_cycle_or_too_deep');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_update_asset_v1(101,'rg-upd-00015',$q$||pos||$q$,$q$||c10_test.aver(pos)||$q$,('{"parent_asset_id":$q$||a1||$q$}')::jsonb,NULL)$q$,'am_parent_site_mismatch');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_update_asset_v1(101,'rg-upd-00016',$q$||o2||$q$,$q$||c10_test.aver(o2)||$q$,'{"parent_asset_id":987654}'::jsonb,NULL)$q$,'am_invalid_input');
 PERFORM c10_test.eq(c10_demo.am_update_asset_v1(101,'rg-upd-00017',o2,c10_test.aver(o2),('{"parent_asset_id":'||a1||'}')::jsonb,'attach as sub-assembly')->>'status','applied','attach to parent at same site');
 PERFORM c10_test.eq(c10_demo.am_update_asset_v1(101,'rg-upd-00018',o2,c10_test.aver(o2),'{"parent_asset_id":null}'::jsonb,'detach')->>'status','applied','detach');
 -- category change: inactive target refused
 PERFORM c10_test.as_user('bo101'); PERFORM c10_demo.am_save_category_v1(101,'rg-upd-cat01',c10_test.cid(101,'TOOL'),c10_test.catver(101,'TOOL'),'{"active":false}'::jsonb,'retire TOOL category');
 PERFORM c10_test.as_user('sup');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_update_asset_v1(101,'rg-upd-00019',$q$||o2||$q$,$q$||c10_test.aver(o2)||$q$,('{"category_id":$q$||c10_test.cid(101,'TOOL')||$q$}')::jsonb,NULL)$q$,'am_category_inactive');
 PERFORM c10_test.eq(c10_demo.am_update_asset_v1(101,'rg-upd-00020',o2,c10_test.aver(o2),('{"category_id":'||c10_test.cid(101,'POWER')||'}')::jsonb,NULL)->>'status','applied','category change');
 -- role matrix
 PERFORM c10_test.as_user('sup1001');
 PERFORM c10_test.eq(c10_demo.am_update_asset_v1(101,'rg-upd-00021',lap,c10_test.aver(lap),'{"model":"ThinkBook"}'::jsonb,NULL)->>'status','applied','site supervisor updates own-site asset');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_update_asset_v1(101,'rg-upd-00022',$q$||a1||$q$,$q$||v||$q$,'{"name":"Other site"}'::jsonb,NULL)$q$,'am_denied');
 PERFORM c10_test.as_user('tech1001'); PERFORM c10_test.denied($q$SELECT c10_demo.am_update_asset_v1(101,'rg-upd-00023',$q$||lap||$q$,$q$||c10_test.aver(lap)||$q$,'{"name":"Tech edit"}'::jsonb,NULL)$q$,'am_not_permitted');
 PERFORM c10_test.as_user('reporter'); PERFORM c10_test.denied($q$SELECT c10_demo.am_update_asset_v1(101,'rg-upd-00024',$q$||lap||$q$,$q$||c10_test.aver(lap)||$q$,'{"name":"Rep edit"}'::jsonb,NULL)$q$,'am_not_permitted');
 PERFORM c10_test.as_user('auditor'); PERFORM c10_test.denied($q$SELECT c10_demo.am_update_asset_v1(101,'rg-upd-00025',$q$||lap||$q$,$q$||c10_test.aver(lap)||$q$,'{"name":"Aud edit"}'::jsonb,NULL)$q$,'am_not_permitted');
 PERFORM c10_test.as_user('stock'); PERFORM c10_test.denied($q$SELECT c10_demo.am_update_asset_v1(101,'rg-upd-00026',$q$||lap||$q$,1,'{"name":"Stock edit"}'::jsonb,NULL)$q$,'am_denied');
 PERFORM c10_test.as_user('bo102'); PERFORM c10_test.denied($q$SELECT c10_demo.am_update_asset_v1(102,'rg-upd-00027',$q$||a1||$q$,1,'{"name":"Cross business"}'::jsonb,NULL)$q$,'am_denied');
 PERFORM c10_test.as_user('owner2'); PERFORM c10_test.denied($q$SELECT c10_demo.am_update_asset_v1(101,'rg-upd-00028',$q$||a1||$q$,1,'{"name":"Cross tenant"}'::jsonb,NULL)$q$,'am_denied');
 PERFORM c10_test.eq(c10_test.n_audit('asset','updated')>=4,'true','update audit rows');
END $$; COMMIT;

-- ===== R6 status machine =====
BEGIN; SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb; o2 bigint:=c10_test.aid('Oven Other Make'); pos bigint:=c10_test.aid('POS Counter 1'); cat bigint:=c10_test.cid(101,'GENERAL');
 rp bigint; rc bigint; w bigint; sa bigint; sb bigint; BEGIN
 PERFORM c10_test.as_user('sup');
 r:=c10_demo.am_set_asset_status_v1(101,'rg-sta-00001',o2,c10_test.aver(o2),'idle','line stopped for the season');
 PERFORM c10_test.eq(r->>'to_status','idle','idle'); PERFORM c10_test.eq(c10_demo.am_set_asset_status_v1(101,'rg-sta-00001',o2,c10_test.aver(o2)-1,'idle','line stopped for the season')->>'to_status','idle','status replay');
 PERFORM c10_test.eq(c10_demo.am_set_asset_status_v1(101,'rg-sta-00002',o2,c10_test.aver(o2),'active','back in service')->>'to_status','active','active');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_set_asset_status_v1(101,'rg-sta-00003',$q$||o2||$q$,$q$||c10_test.aver(o2)||$q$,'breakdown','manual breakdown')$q$,'am_invalid_transition');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_set_asset_status_v1(101,'rg-sta-00004',$q$||o2||$q$,$q$||c10_test.aver(o2)||$q$,'under_maintenance','manual maintenance')$q$,'am_invalid_transition');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_set_asset_status_v1(101,'rg-sta-00005',$q$||o2||$q$,$q$||c10_test.aver(o2)||$q$,'planned','back to planned')$q$,'am_invalid_transition');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_set_asset_status_v1(101,'rg-sta-00006',$q$||o2||$q$,$q$||c10_test.aver(o2)||$q$,'active','no-op transition')$q$,'am_invalid_transition');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_set_asset_status_v1(101,'rg-sta-00007',$q$||o2||$q$,$q$||c10_test.aver(o2)||$q$,'bogus','bad value')$q$,'am_invalid_input');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_set_asset_status_v1(101,'rg-sta-00008',$q$||o2||$q$,$q$||c10_test.aver(o2)||$q$,'idle',NULL)$q$,'am_invalid_input');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_set_asset_status_v1(101,'rg-sta-00009',$q$||o2||$q$,1,'idle','stale version')$q$,'am_stale_version');
 PERFORM c10_test.as_user('tech1002'); PERFORM c10_test.denied($q$SELECT c10_demo.am_set_asset_status_v1(101,'rg-sta-00010',$q$||o2||$q$,$q$||c10_test.aver(o2)||$q$,'idle','tech tries')$q$,'am_not_permitted');
 PERFORM c10_test.as_user('sup1001'); PERFORM c10_test.denied($q$SELECT c10_demo.am_set_asset_status_v1(101,'rg-sta-00011',$q$||o2||$q$,$q$||c10_test.aver(o2)||$q$,'idle','other site')$q$,'am_denied');
 -- planned -> active commissions (commission_date defaulted)
 PERFORM c10_test.as_user('sup1001');
 r:=c10_demo.am_set_asset_status_v1(101,'rg-sta-00012',pos,c10_test.aver(pos),'active','commissioned');
 PERFORM c10_test.eq(r->>'from_status','planned','commissioning from planned');
 PERFORM c10_test.eq((c10_demo.am_get_asset_v1(101,pos)->'asset'->>'commission_date') IS NOT NULL,'true','commission_date set');
 -- retire / dispose guards
 PERFORM c10_test.as_user('sup');
 rp:=(c10_demo.am_create_asset_v1(101,'rg-sta-00013',jsonb_build_object('name','Retire Parent','category_id',cat,'site_id',1002),NULL)->>'asset_id')::bigint;
 rc:=(c10_demo.am_create_asset_v1(101,'rg-sta-00014',jsonb_build_object('name','Retire Child','category_id',cat,'site_id',1002,'parent_asset_id',rp),NULL)->>'asset_id')::bigint;
 PERFORM c10_test.denied($q$SELECT c10_demo.am_set_asset_status_v1(101,'rg-sta-00015',$q$||rp||$q$,$q$||c10_test.aver(rp)||$q$,'retired','retire with children')$q$,'am_asset_has_children');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_set_asset_status_v1(101,'rg-sta-00016',$q$||rp||$q$,$q$||c10_test.aver(rp)||$q$,'disposed','dispose with children')$q$,'am_asset_has_children');
 w:=c10_test.mkwo(rc,'DRAFT');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_set_asset_status_v1(101,'rg-sta-00017',$q$||rc||$q$,$q$||c10_test.aver(rc)||$q$,'retired','retire with open wo')$q$,'am_asset_has_open_wo');
 PERFORM c10_test.wo_set(w,'CANCELLED'); PERFORM c10_test.mkwo(rc,'CLOSED');
 PERFORM c10_test.mkdt(rc);
 PERFORM c10_test.denied($q$SELECT c10_demo.am_set_asset_status_v1(101,'rg-sta-00018',$q$||rc||$q$,$q$||c10_test.aver(rc)||$q$,'retired','retire with open downtime')$q$,'am_asset_has_open_downtime');
 PERFORM c10_test.enddt(rc);
 r:=c10_demo.am_set_asset_status_v1(101,'rg-sta-00019',rc,c10_test.aver(rc),'retired','end of life');
 PERFORM c10_test.eq(r->>'to_status','retired','retired once WOs closed/cancelled, downtime ended');
 PERFORM c10_test.eq((c10_demo.am_get_asset_v1(101,rc)->'asset'->>'retired_at') IS NOT NULL,'true','retired_at set');
 PERFORM c10_test.eq(c10_demo.am_set_asset_status_v1(101,'rg-sta-00020',rp,c10_test.aver(rp),'retired','children retired')->>'to_status','retired','parent retires after children');
 PERFORM c10_test.eq(c10_demo.am_set_asset_status_v1(101,'rg-sta-00021',rp,c10_test.aver(rp),'disposed','sold for scrap')->>'to_status','disposed','retired -> disposed');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_set_asset_status_v1(101,'rg-sta-00022',$q$||rp||$q$,$q$||c10_test.aver(rp)||$q$,'active','resurrect')$q$,'am_invalid_transition');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_update_asset_v1(101,'rg-sta-00023',$q$||rp||$q$,$q$||c10_test.aver(rp)||$q$,'{"name":"Edit disposed"}'::jsonb,NULL)$q$,'am_invalid_state');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_add_meter_v1(101,'rg-sta-00024',$q$||rc||$q$,'M1','hours',NULL)$q$,'am_invalid_state');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_request_transfer_v1(101,'rg-sta-00025',$q$||rc||$q$,1001,true,'move retired')$q$,'am_invalid_state');
 -- a retired asset frees its serial; reactivation re-checks it
 sa:=(c10_demo.am_create_asset_v1(101,'rg-sta-00026',jsonb_build_object('name','Serial Reuse A','category_id',cat,'site_id',1002,'serial_no','RS-1','manufacturer','Acme'),NULL)->>'asset_id')::bigint;
 PERFORM c10_demo.am_set_asset_status_v1(101,'rg-sta-00027',sa,c10_test.aver(sa),'retired','replaced by new unit');
 sb:=(c10_demo.am_create_asset_v1(101,'rg-sta-00028',jsonb_build_object('name','Serial Reuse B','category_id',cat,'site_id',1002,'serial_no','RS-1','manufacturer','Acme'),NULL)->>'asset_id')::bigint;
 PERFORM c10_test.denied($q$SELECT c10_demo.am_set_asset_status_v1(101,'rg-sta-00029',$q$||sa||$q$,$q$||c10_test.aver(sa)||$q$,'active','undo retire')$q$,'am_duplicate_serial');
 PERFORM c10_test.eq(c10_demo.am_set_asset_status_v1(101,'rg-sta-00030',rc,c10_test.aver(rc),'idle','retire was a mistake')->>'to_status','idle','retired -> idle allowed');
 PERFORM c10_test.eq((c10_demo.am_get_asset_v1(101,rc)->'asset'->>'retired_at') IS NULL,'true','retired_at cleared on reactivation');
 PERFORM c10_test.eq(c10_test.n_audit('asset','status_changed')>=8,'true','status audit rows');
END $$; COMMIT;

-- ===== R7 site transfers =====
BEGIN; SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb; t bigint; x bigint; c bigint; lap bigint:=c10_test.aid('Laptop no serial ok'); cat bigint:=c10_test.cid(101,'PROD-EQ'); no0 text; w1 bigint; w2 bigint; w3 bigint; wip bigint; t2 bigint; BEGIN
 PERFORM c10_test.as_user('sup');
 x:=(c10_demo.am_create_asset_v1(101,'rg-trf-00001',jsonb_build_object('name','Line Press','category_id',cat,'site_id',1001,'serial_no','LP-1'),NULL)->>'asset_id')::bigint;
 c:=(c10_demo.am_create_asset_v1(101,'rg-trf-00002',jsonb_build_object('name','Press Motor','category_id',cat,'site_id',1001,'parent_asset_id',x),NULL)->>'asset_id')::bigint;
 no0:=c10_demo.am_get_asset_v1(101,x)->'asset'->>'asset_no';
 w1:=c10_test.mkwo(x,'DRAFT'); w2:=c10_test.mkwo(c,'APPROVED'); w3:=c10_test.mkwo(x,'COMPLETED');
 -- request validation + role matrix (default policy: approval required)
 PERFORM c10_test.denied($q$SELECT c10_demo.am_request_transfer_v1(101,'rg-trf-00003',$q$||x||$q$,1002,false,'leave the motor behind')$q$,'am_transfer_children_required');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_request_transfer_v1(101,'rg-trf-00004',$q$||x||$q$,1001,true,'same site')$q$,'am_invalid_input');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_request_transfer_v1(101,'rg-trf-00005',$q$||x||$q$,NULL,true,'no target')$q$,'am_invalid_input');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_request_transfer_v1(101,'rg-trf-00006',$q$||x||$q$,1002,true,NULL)$q$,'am_invalid_input');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_request_transfer_v1(101,'rg-trf-00007',$q$||x||$q$,1003,true,'other business site')$q$,'am_denied');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_request_transfer_v1(101,'rg-trf-00008',$q$||x||$q$,2001,true,'other tenant site')$q$,'am_denied');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_request_transfer_v1(101,'rg-trf-00009',$q$||c||$q$,1002,true,'move a child alone')$q$,'am_transfer_has_parent');
 PERFORM c10_test.as_user('bo101');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_request_transfer_v1(101,'rg-trf-00010',$q$||x||$q$,1003,true,'other business site')$q$,'am_invalid_input');
 PERFORM c10_test.as_user('tech1001'); PERFORM c10_test.denied($q$SELECT c10_demo.am_request_transfer_v1(101,'rg-trf-00011',$q$||x||$q$,1002,true,'tech moves asset')$q$,'am_not_permitted');
 PERFORM c10_test.as_user('reporter'); PERFORM c10_test.denied($q$SELECT c10_demo.am_request_transfer_v1(101,'rg-trf-00012',$q$||x||$q$,1002,true,'reporter moves asset')$q$,'am_not_permitted');
 PERFORM c10_test.as_user('stock'); PERFORM c10_test.denied($q$SELECT c10_demo.am_request_transfer_v1(101,'rg-trf-00013',$q$||x||$q$,1002,true,'stock moves asset')$q$,'am_denied');
 PERFORM c10_test.as_user('tech1002'); PERFORM c10_test.denied($q$SELECT c10_demo.am_request_transfer_v1(101,'rg-trf-00014',$q$||x||$q$,1002,true,'tech at target')$q$,'am_denied');
 -- site supervisor requests; pending; second request blocked
 PERFORM c10_test.as_user('sup1001');
 r:=c10_demo.am_request_transfer_v1(101,'rg-trf-00015',x,1002,true,'press needed at the factory'); t:=(r->>'transfer_id')::bigint;
 PERFORM c10_test.eq(r->>'transfer_status','pending','needs approval by default'); PERFORM c10_test.eq(c10_test.asite(x),'1001','nothing moved yet');
 PERFORM c10_test.eq(c10_demo.am_request_transfer_v1(101,'rg-trf-00015',x,1002,true,'press needed at the factory')->>'transfer_id',t::text,'request replay');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_request_transfer_v1(101,'rg-trf-00016',$q$||x||$q$,1004,true,'second pending')$q$,'am_transfer_pending');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_set_asset_status_v1(101,'rg-trf-00017',$q$||x||$q$,$q$||c10_test.aver(x)||$q$,'retired','retire while pending')$q$,'am_asset_has_open_wo');
 PERFORM c10_test.eq(c10_test.n_audit('transfer','requested')>=1,'true','request audited');
 -- who may decide
 PERFORM c10_test.denied($q$SELECT c10_demo.am_decide_transfer_v1(101,'rg-trf-00018',$q$||t||$q$,1,'approve',NULL)$q$,'am_not_permitted');
 PERFORM c10_test.as_user('reporter'); PERFORM c10_test.denied($q$SELECT c10_demo.am_decide_transfer_v1(101,'rg-trf-00019',$q$||t||$q$,1,'approve',NULL)$q$,'am_not_permitted');
 PERFORM c10_test.as_user('tech1002'); PERFORM c10_test.denied($q$SELECT c10_demo.am_decide_transfer_v1(101,'rg-trf-00020',$q$||t||$q$,1,'approve',NULL)$q$,'am_not_permitted');
 PERFORM c10_test.as_user('stock'); PERFORM c10_test.denied($q$SELECT c10_demo.am_decide_transfer_v1(101,'rg-trf-00021',$q$||t||$q$,1,'approve',NULL)$q$,'am_denied');
 PERFORM c10_test.as_user('owner2'); PERFORM c10_test.denied($q$SELECT c10_demo.am_decide_transfer_v1(101,'rg-trf-00022',$q$||t||$q$,1,'approve',NULL)$q$,'am_denied');
 PERFORM c10_test.as_user('sup');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_decide_transfer_v1(101,'rg-trf-00023',$q$||t||$q$,1,'maybe',NULL)$q$,'am_invalid_input');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_decide_transfer_v1(101,'rg-trf-00024',$q$||t||$q$,7,'approve',NULL)$q$,'am_stale_version');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_decide_transfer_v1(101,'rg-trf-00025',999999,1,'approve',NULL)$q$,'am_denied');
 r:=c10_demo.am_list_transfers_v1(101,'pending');
 PERFORM c10_test.eq(r->'items'->0->>'can_decide','true','supervisor of both sites can decide');
 PERFORM c10_test.as_user('sup1001'); PERFORM c10_test.eq(c10_demo.am_list_transfers_v1(101,NULL)->'items'->0->>'can_decide','false','requester/limited supervisor cannot decide');
 PERFORM c10_test.eq(c10_demo.am_list_transfers_v1(101,NULL)->'items'->0->>'can_cancel','true','requester can cancel');
 -- active work blocks the move (policy asset.allow_transfer_with_active_wo = false)
 wip:=c10_test.mkwo(c,'IN_PROGRESS');
 PERFORM c10_test.as_user('sup');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_decide_transfer_v1(101,'rg-trf-00026',$q$||t||$q$,1,'approve',NULL)$q$,'am_transfer_blocked');
 PERFORM c10_test.eq(c10_test.asite(x),'1001','blocked transfer moved nothing');
 PERFORM c10_test.wo_set(wip,'CANCELLED');
 r:=c10_demo.am_decide_transfer_v1(101,'rg-trf-00027',t,1,'approve','approved by factory supervisor');
 PERFORM c10_test.eq(r->>'transfer_status','applied','approved'); PERFORM c10_test.eq(r->>'moved_assets','2','asset + child moved');
 PERFORM c10_test.eq(c10_test.asite(x)||'/'||c10_test.asite(c),'1002/1002','parent and child at the new site');
 PERFORM c10_test.eq(c10_demo.am_get_asset_v1(101,x)->'asset'->>'asset_no',no0,'canonical asset id unchanged');
 PERFORM c10_test.eq(c10_test.n_mov(x,'transfer')||'/'||c10_test.n_mov(c,'transfer'),'1/1','movement rows for asset and child');
 PERFORM c10_test.eq(c10_test.wo_site(w1)||'/'||c10_test.wo_site(w2)||'/'||c10_test.wo_site(w3),'1002/1002/1001','open DRAFT/APPROVED WOs follow, finished WO keeps its site');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_decide_transfer_v1(101,'rg-trf-00028',$q$||t||$q$,2,'approve',NULL)$q$,'am_invalid_state');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_decide_transfer_v1(101,'rg-trf-00029',$q$||t||$q$,1,'approve',NULL)$q$,'am_stale_version');
 PERFORM c10_test.eq(c10_demo.am_decide_transfer_v1(101,'rg-trf-00027',t,1,'approve','approved by factory supervisor')->>'moved_assets','2','approve replay is transparent');
 PERFORM c10_test.eq(c10_test.n_mov(x,'transfer'),'1','replay did not move again');
 -- site-1001-only supervisor lost sight of the asset; the factory technician gained it
 PERFORM c10_test.as_user('sup1001'); PERFORM c10_test.denied('SELECT c10_demo.am_get_asset_v1(101,'||x||')','am_denied');
 PERFORM c10_test.as_user('tech1002'); PERFORM c10_test.eq(c10_demo.am_get_asset_v1(101,x)->'asset'->>'site_id','1002','factory technician now sees the press');
 -- maker-checker on transfers: requester cannot approve own request unless owner
 PERFORM c10_test.as_user('sup');
 r:=c10_demo.am_request_transfer_v1(101,'rg-trf-00030',x,1001,true,'send it back'); t:=(r->>'transfer_id')::bigint;
 PERFORM c10_test.denied($q$SELECT c10_demo.am_decide_transfer_v1(101,'rg-trf-00031',$q$||t||$q$,1,'approve',NULL)$q$,'am_self_approval_not_allowed');
 PERFORM c10_test.as_user('bo101');
 PERFORM c10_test.eq(c10_demo.am_decide_transfer_v1(101,'rg-trf-00032',t,1,'approve','owner approves')->>'transfer_status','applied','owner approves');
 PERFORM c10_test.eq(c10_test.asite(x)||'/'||c10_test.asite(c),'1001/1001','moved back');
 PERFORM c10_test.eq(c10_test.n_mov(x,'transfer'),'2','movement history keeps both moves');
 PERFORM c10_test.as_user('owner');
 r:=c10_demo.am_request_transfer_v1(101,'rg-trf-00033',x,1005,true,'owner moves to godown'); t:=(r->>'transfer_id')::bigint;
 PERFORM c10_test.eq(c10_demo.am_decide_transfer_v1(101,'rg-trf-00034',t,1,'approve',NULL)->>'transfer_status','applied','owner may approve own request');
 PERFORM c10_test.eq(c10_test.asite(x)::text,'1005','tenant owner moved asset');
 -- reject / cancel
 PERFORM c10_test.as_user('sup');
 r:=c10_demo.am_request_transfer_v1(101,'rg-trf-00035',x,1001,true,'try again'); t:=(r->>'transfer_id')::bigint;
 PERFORM c10_test.as_user('bo101'); PERFORM c10_test.eq(c10_demo.am_decide_transfer_v1(101,'rg-trf-00036',t,1,'reject','not now')->>'transfer_status','rejected','rejected');
 PERFORM c10_test.eq(c10_test.asite(x)::text,'1005','rejected transfer moved nothing');
 PERFORM c10_test.as_user('sup1001'); -- site 1001 supervisor: no authority over godown asset
 PERFORM c10_test.denied($q$SELECT c10_demo.am_request_transfer_v1(101,'rg-trf-00037',$q$||x||$q$,1001,true,'no view of godown')$q$,'am_denied');
 PERFORM c10_test.as_user('sup');
 r:=c10_demo.am_request_transfer_v1(101,'rg-trf-00038',x,1001,true,'again'); t:=(r->>'transfer_id')::bigint;
 PERFORM c10_test.as_user('auditor'); PERFORM c10_test.denied($q$SELECT c10_demo.am_decide_transfer_v1(101,'rg-trf-00039',$q$||t||$q$,1,'cancel',NULL)$q$,'am_not_permitted');
 PERFORM c10_test.as_user('sup'); PERFORM c10_test.eq(c10_demo.am_decide_transfer_v1(101,'rg-trf-00040',t,1,'cancel','changed my mind')->>'transfer_status','cancelled','requester cancels');
 -- open downtime blocks too; policy asset.allow_transfer_with_active_wo lets an IN_PROGRESS WO stay behind
 PERFORM c10_test.mkdt(x);
 PERFORM c10_test.denied($q$SELECT c10_demo.am_request_transfer_v1(101,'rg-trf-00041',$q$||x||$q$,1001,true,'downtime blocks')$q$,'am_transfer_blocked');
 PERFORM c10_test.enddt(x); wip:=c10_test.mkwo(x,'IN_PROGRESS');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_request_transfer_v1(101,'rg-trf-00042',$q$||x||$q$,1001,true,'wo blocks')$q$,'am_transfer_blocked');
 PERFORM c10_test.setpol(101,'asset.allow_transfer_with_active_wo','true'::jsonb);
 r:=c10_demo.am_request_transfer_v1(101,'rg-trf-00043',x,1004,true,'allowed with active wo'); t:=(r->>'transfer_id')::bigint;
 PERFORM c10_test.as_user('bo101'); PERFORM c10_demo.am_decide_transfer_v1(101,'rg-trf-00044',t,1,'approve',NULL);
 PERFORM c10_test.eq(c10_test.asite(x)::text,'1004','moved despite active wo (policy)'); PERFORM c10_test.eq(c10_test.wo_site(wip)::text,'1005','in-progress WO keeps its site');
 PERFORM c10_test.eq(c10_test.wo_site(w1)::text,'1004','draft WO followed again');
 PERFORM c10_test.delpol(101,'asset.allow_transfer_with_active_wo'); PERFORM c10_test.wo_set(wip,'CANCELLED');
 -- policy asset.transfer_requires_approval=false: direct apply only with transfer authority at BOTH sites
 PERFORM c10_test.setpol(101,'asset.transfer_requires_approval','false'::jsonb);
 PERFORM c10_test.as_user('sup');
 r:=c10_demo.am_request_transfer_v1(101,'rg-trf-00045',x,1005,true,'direct move');
 PERFORM c10_test.eq(r->>'transfer_status','applied','direct apply when policy says so'); PERFORM c10_test.eq(r->>'moved_assets','2','direct apply moves children');
 PERFORM c10_test.eq(c10_test.asite(x)::text,'1005','direct apply moved');
 PERFORM c10_test.as_user('sup1001');
 r:=c10_demo.am_request_transfer_v1(101,'rg-trf-00046',lap,1002,true,'site supervisor lacks authority at target'); t2:=(r->>'transfer_id')::bigint;
 PERFORM c10_test.eq(r->>'transfer_status','pending','limited supervisor still needs approval');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_set_asset_status_v1(101,'rg-trf-00047',$q$||lap||$q$,$q$||c10_test.aver(lap)||$q$,'retired','retire with pending transfer')$q$,'am_transfer_pending');
 PERFORM c10_test.eq(c10_demo.am_decide_transfer_v1(101,'rg-trf-00048',t2,1,'cancel',NULL)->>'transfer_status','cancelled','cancelled');
 PERFORM c10_test.delpol(101,'asset.transfer_requires_approval');
 PERFORM c10_test.eq((SELECT count(*) FROM jsonb_array_elements(c10_demo.am_list_transfers_v1(101,NULL)->'items'))>=6,'true','sup1001 transfer list');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_list_transfers_v1(101,'bogus')$q$,'am_invalid_input');
 -- child invariant: no child ever sits at a different site than its parent
 PERFORM c10_test.as_user('bo101');
 PERFORM c10_test.eq(c10_demo.am_get_asset_v1(101,c)->'asset'->>'site_id',c10_demo.am_get_asset_v1(101,x)->'asset'->>'site_id','child follows parent');
 PERFORM c10_test.eq(c10_test.n_audit('transfer','applied')>=4 AND c10_test.n_audit('asset','transferred')>=4,'true','transfer audit rows');
END $$; COMMIT;
