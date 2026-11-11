-- C10-A055 policy engine e2e (disposable PostgreSQL; signed-claim simulation, NOT GoTrue). Run after core+policy+lockdown+seed.
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
 WHEN 'sup2' THEN 'd8888888-8888-4888-8888-888888888888' WHEN 'bo102' THEN 'e1111111-1111-4111-8111-111111111111' END)::uuid $$;
CREATE FUNCTION c10_test.as_user(p text) RETURNS void LANGUAGE sql AS $$ SELECT set_config('request.jwt.claim.sub',c10_test.u(p)::text,true); SELECT 1 $$;
CREATE FUNCTION c10_test.eq(a text,b text,msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF a IS DISTINCT FROM b THEN RAISE EXCEPTION 'ASSERT % : got [%] want [%]',msg,a,b; END IF; END$$;
CREATE FUNCTION c10_test.eq(a boolean,b text,msg text) RETURNS void LANGUAGE sql AS $$ SELECT c10_test.eq(a::text,b,msg) $$;
CREATE FUNCTION c10_test.denied(p_sql text,p_expect text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 BEGIN EXECUTE p_sql; EXCEPTION WHEN OTHERS THEN
  IF SQLERRM NOT LIKE p_expect||'%' THEN RAISE EXCEPTION 'WRONG_ERROR [%] for %: want %',SQLERRM,p_sql,p_expect; END IF; RETURN; END;
 RAISE EXCEPTION 'EXPECTED_DENIAL_DID_NOT_HAPPEN: %',p_sql;
END$$;
CREATE FUNCTION c10_test.mut_count() RETURNS bigint LANGUAGE sql SECURITY DEFINER AS $$ SELECT (SELECT count(*) FROM c10_demo.am_policy_history)+(SELECT count(*) FROM c10_demo.am_audit)+(SELECT count(*) FROM c10_demo.am_policy)+(SELECT count(*) FROM c10_demo.am_receipts) $$;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA c10_test TO authenticated,anon;

-- P1 authority: stock/investor/revoked/other tenant/operator/plain manager never gain maintenance authority.
BEGIN; SET LOCAL ROLE authenticated;
DO $$ BEGIN
 PERFORM c10_test.as_user('stock');    PERFORM c10_test.denied('SELECT c10_demo.am_whoami_v1(101)','am_denied');
 PERFORM c10_test.as_user('investor'); PERFORM c10_test.denied('SELECT c10_demo.am_whoami_v1(101)','am_denied');
 PERFORM c10_test.as_user('revoked');  PERFORM c10_test.denied('SELECT c10_demo.am_whoami_v1(101)','am_denied');
 PERFORM c10_test.as_user('owner2');   PERFORM c10_test.denied('SELECT c10_demo.am_whoami_v1(101)','am_denied');
 PERFORM c10_test.as_user('staff2');   PERFORM c10_test.denied('SELECT c10_demo.am_whoami_v1(101)','am_denied');
 PERFORM c10_test.as_user('operator'); PERFORM c10_test.denied('SELECT c10_demo.am_whoami_v1(101)','am_denied');
 PERFORM c10_test.as_user('revtech');  PERFORM c10_test.denied('SELECT c10_demo.am_whoami_v1(101)','am_denied');
 PERFORM c10_test.as_user('mgr101');   PERFORM c10_test.denied('SELECT c10_demo.am_whoami_v1(101)','am_denied');
 PERFORM c10_test.as_user('bo102');    PERFORM c10_test.denied('SELECT c10_demo.am_whoami_v1(101)','am_denied');
 PERFORM c10_test.as_user('sup2');     PERFORM c10_test.denied('SELECT c10_demo.am_whoami_v1(101)','am_denied');
 PERFORM c10_test.as_user('owner');
 PERFORM c10_test.eq(c10_demo.am_whoami_v1(101)->>'level','tenant_owner','tenant owner level');
 PERFORM c10_test.eq(c10_demo.am_whoami_v1(102)->>'level','tenant_owner','tenant owner sees 2nd business');
 PERFORM c10_test.eq(jsonb_array_length(c10_demo.am_whoami_v1(101)->'sites')::text,'4','owner sees 4 sites');
 PERFORM c10_test.as_user('bo101'); PERFORM c10_test.eq(c10_demo.am_whoami_v1(101)->>'level','business_owner','bo level');
 PERFORM c10_test.as_user('sup1001');
 PERFORM c10_test.eq(c10_demo.am_whoami_v1(101)->>'level','staff','scoped supervisor level');
 PERFORM c10_test.eq(jsonb_array_length(c10_demo.am_whoami_v1(101)->'sites')::text,'1','scoped supervisor sees only own site');
 PERFORM c10_test.as_user('reporter');
 PERFORM c10_test.eq((c10_demo.am_whoami_v1(101)->'sites'->0->'caps') ? 'approve','false','reporter cannot approve');
 PERFORM c10_test.eq((c10_demo.am_whoami_v1(101)->'sites'->0->'caps') ? 'report','true','reporter can report');
END $$;
COMMIT;

-- P2 policy reads + writes
BEGIN; SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb; rev bigint; BEGIN
 PERFORM c10_test.as_user('tech1001');
 PERFORM c10_test.eq(jsonb_array_length(c10_demo.am_policy_catalog_v1(101)->'items')>50,'true','catalog visible to staff');
 PERFORM c10_test.eq(c10_demo.am_get_policy_v1(101,NULL,NULL)->'values'->'wo.maker_checker'->>'source','default','default source');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_save_policy_v1(101,'pol-tech-0001',1,'business',0,'{"wo.verify_required":false}'::jsonb,'technician attempt')$q$,'am_owner_required');
 PERFORM c10_test.as_user('bo101');
 r:=c10_demo.am_save_policy_v1(101,'pol-save-0001',1,'business',0,'{"sla.resolve_hours.high":36,"wo.verify_required":false}'::jsonb,'tune for showroom');
 PERFORM c10_test.eq(r->>'changed','2','two keys changed'); PERFORM c10_test.eq(r->>'policy_rev','2','rev bumped');
 PERFORM c10_test.eq(c10_demo.am_save_policy_v1(101,'pol-save-0001',1,'business',0,'{"sla.resolve_hours.high":36,"wo.verify_required":false}'::jsonb,'tune for showroom')::text,r::text,'replay returns original');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_save_policy_v1(101,'pol-save-0001',1,'business',0,'{"sla.resolve_hours.high":40}'::jsonb,'tune for showroom')$q$,'am_idempotency_conflict');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_save_policy_v1(101,'pol-stale-0001',1,'business',0,'{"wo.require_cause_code":false}'::jsonb,'stale write')$q$,'am_stale_version');
 PERFORM c10_test.eq(c10_demo.am_get_policy_v1(101,NULL,NULL)->'values'->'sla.resolve_hours.high'->>'source','business','business source');
 -- tenant-owner-only key
 PERFORM c10_test.denied($q$SELECT c10_demo.am_save_policy_v1(101,'pol-mc-000001',2,'business',0,'{"wo.maker_checker":false}'::jsonb,'loosen maker checker')$q$,'am_tenant_owner_required');
 -- validation
 PERFORM c10_test.denied($q$SELECT c10_demo.am_save_policy_v1(101,'pol-bad-00001',2,'business',0,'{"sla.resolve_hours.low":0}'::jsonb,'out of range value')$q$,'am_invalid_policy_value');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_save_policy_v1(101,'pol-bad-00002',2,'business',0,'{"wo.verify_required":"yes"}'::jsonb,'wrong type value')$q$,'am_invalid_policy_value');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_save_policy_v1(101,'pol-bad-00003',2,'business',0,'{"wo.overlap_policy":"merge"}'::jsonb,'bad enum value')$q$,'am_invalid_policy_value');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_save_policy_v1(101,'pol-bad-00004',2,'business',0,'{"general.timezone":"Mars/Phobos"}'::jsonb,'bad timezone value')$q$,'am_invalid_policy_value');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_save_policy_v1(101,'pol-bad-00005',2,'business',0,'{"no.such.key":1}'::jsonb,'unknown policy key')$q$,'am_unknown_policy_key');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_save_policy_v1(101,'pol-bad-00006',2,'site',1001,'{"general.currency":"USD"}'::jsonb,'key not site scoped')$q$,'am_policy_scope_not_allowed');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_save_policy_v1(101,'pol-bad-00007',2,'site',1003,'{"wo.verify_required":true}'::jsonb,'site of another business')$q$,'am_denied');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_save_policy_v1(101,'pol-bad-00008',2,'business',0,'{"sla.resolve_hours.critical":1,"sla.response_hours.critical":5}'::jsonb,'resolve below response')$q$,'am_policy_inconsistent');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_save_policy_v1(101,'pol-bad-00009',2,'business',0,'{}'::jsonb,'empty change set')$q$,'am_invalid_input');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_save_policy_v1(101,'short',2,'business',0,'{"wo.verify_required":true}'::jsonb,'bad request key')$q$,'am_invalid_request_key');
 PERFORM c10_test.eq(c10_demo.am_get_policy_v1(101,NULL,NULL)->'values'->'general.currency'->>'source','default','failed batch left no residue');
 -- site override + resolution order
 r:=c10_demo.am_save_policy_v1(101,'pol-site-00001',2,'site',1002,'{"wo.verify_required":true,"schedule.due_lead_days":21}'::jsonb,'factory is stricter');
 PERFORM c10_test.eq(r->>'policy_rev','3','rev 3');
 PERFORM c10_test.eq(c10_demo.am_get_policy_v1(101,1002,NULL)->'values'->'wo.verify_required'->>'source','site','site override wins');
 PERFORM c10_test.eq(c10_demo.am_get_policy_v1(101,1001,NULL)->'values'->'wo.verify_required'->>'value','false','other site keeps business value');
 PERFORM c10_test.eq(c10_demo.am_get_policy_v1(101,1002,NULL)->'values'->'schedule.due_lead_days'->>'value','21','site lead days');
END $$;
COMMIT;
-- effective-value resolver (internal) as superuser: category > site > business > default
DO $$ DECLARE cat bigint; BEGIN
 SELECT id INTO cat FROM c10_demo.am_categories WHERE business_id=101 AND code='COLD';
 INSERT INTO c10_demo.am_policy(business_id,tenant_id,scope_type,scope_id,key,value,updated_by) VALUES(101,1,'category',cat,'schedule.due_lead_days','30','22222222-2222-4222-8222-222222222222');
 PERFORM c10_test.eq(c10_demo.ami_cfg_int(101,1002,cat,'schedule.due_lead_days')::text,'30','category beats site');
 PERFORM c10_test.eq(c10_demo.ami_cfg_int(101,1002,NULL,'schedule.due_lead_days')::text,'21','site beats business');
 PERFORM c10_test.eq(c10_demo.ami_cfg_int(101,1001,NULL,'schedule.due_lead_days')::text,'7','business/default');
 DELETE FROM c10_demo.am_policy WHERE scope_type='category';
END $$;

-- P3 reset, preset, history, audit
BEGIN; SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb; BEGIN
 PERFORM c10_test.as_user('bo101');
 r:=c10_demo.am_reset_policy_v1(101,'pol-reset-0001',3,'site',1002,ARRAY['schedule.due_lead_days'],'back to business value');
 PERFORM c10_test.eq(r->>'removed','1','reset removed 1'); PERFORM c10_test.eq(r->>'policy_rev','4','rev 4');
 PERFORM c10_test.eq(c10_demo.am_get_policy_v1(101,1002,NULL)->'values'->'schedule.due_lead_days'->>'source','default','reset falls back');
 r:=c10_demo.am_apply_preset_v1(101,'pol-preset-001',4,'factory','site',1002,'apply factory mode');
 PERFORM c10_test.eq((r->>'changed')::int>=5,'true','factory preset changed several keys');
 PERFORM c10_test.eq(c10_demo.am_get_policy_v1(101,1002,NULL)->'values'->'wo.evidence_required_for'->>'value','all','preset effective');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_apply_preset_v1(101,'pol-preset-002',5,'mars','site',1002,'unknown preset name')$q$,'am_unknown_preset');
 PERFORM c10_test.eq(jsonb_array_length(c10_demo.am_policy_history_v1(101,100)->'items')>=6,'true','history rows');
 PERFORM c10_test.as_user('tech1001'); PERFORM c10_test.denied('SELECT c10_demo.am_policy_history_v1(101,10)','am_not_permitted');
 PERFORM c10_test.as_user('auditor'); PERFORM c10_test.eq(jsonb_array_length(c10_demo.am_policy_history_v1(101,10)->'items')>0,'true','auditor reads history');
 -- tenant owner may flip the protected key
 PERFORM c10_test.as_user('owner');
 r:=c10_demo.am_save_policy_v1(101,'pol-mc-000002',5,'business',0,'{"wo.maker_checker":false}'::jsonb,'owner decision documented');
 PERFORM c10_test.eq(r->>'changed','1','tenant owner flips maker-checker');
 r:=c10_demo.am_save_policy_v1(101,'pol-mc-000003',6,'business',0,'{"wo.maker_checker":true}'::jsonb,'restore safe default');
END $$;
COMMIT;

-- P4 preview is a pure simulation, schedule simulator is pure
DO $$ BEGIN
 INSERT INTO c10_demo.am_work_orders(tenant_id,business_id,wo_no,kind,status,asset_id,site_id,title,priority,requested_by,requested_at,sla_resolve_due_at)
 SELECT 1,101,'WO-PREV01','corrective','APPROVED',a.id,1001,'preview fixture','high','22222222-2222-4222-8222-222222222222',now()-interval '30 hours',now()+interval '18 hours'
 FROM (SELECT id FROM c10_demo.am_assets LIMIT 1) a;
EXCEPTION WHEN not_null_violation OR foreign_key_violation OR no_data_found OR others THEN NULL; END $$;
BEGIN; SET LOCAL ROLE authenticated;
DO $$ DECLARE r jsonb; before_cnt bigint; after_cnt bigint; BEGIN
 PERFORM c10_test.as_user('bo101');
 before_cnt:=c10_test.mut_count();
 r:=c10_demo.am_preview_policy_v1(101,'business',0,'{"sla.resolve_hours.high":12,"schedule.due_lead_days":30,"wo.verify_required":true,"finance.depreciation_method":"none"}'::jsonb);
 PERFORM c10_test.eq(r->>'simulation','true','flagged simulation'); PERFORM c10_test.eq(r->>'writes','0','no writes');
 PERFORM c10_test.eq(jsonb_array_length(r->'items')::text,'4','4 items previewed');
 after_cnt:=c10_test.mut_count();
 PERFORM c10_test.eq(after_cnt::text,before_cnt::text,'preview wrote nothing');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_preview_policy_v1(101,'business',0,'{"wo.verify_required":"x"}'::jsonb)$q$,'am_invalid_policy_value');
 PERFORM c10_test.as_user('tech1001'); PERFORM c10_test.denied($q$SELECT c10_demo.am_preview_policy_v1(101,'business',0,'{"wo.verify_required":true}'::jsonb)$q$,'am_owner_required');
 PERFORM c10_test.as_user('bo101');
 r:=c10_demo.am_simulate_schedule_v1(101,'{"frequency_kind":"monthly","interval_n":1,"start_on":"2026-01-31","count":4,"anchor":"from_due_date"}'::jsonb);
 PERFORM c10_test.eq(r->'items'->0->>'due_on','2026-02-28','month-end clamp');
 PERFORM c10_test.eq(r->'items'->1->>'due_on','2026-03-31','no drift (from_due_date)');
 r:=c10_demo.am_simulate_schedule_v1(101,'{"frequency_kind":"weekly","interval_n":2,"start_on":"2026-01-05","count":3,"anchor":"from_completion","typical_delay_days":3}'::jsonb);
 PERFORM c10_test.eq(r->'items'->1->>'due_on','2026-02-05','drift with delay');
 r:=c10_demo.am_simulate_schedule_v1(101,'{"frequency_kind":"usage","usage_interval":250,"avg_daily_usage":10,"current_reading":100,"count":2}'::jsonb);
 PERFORM c10_test.eq(r->'items'->0->>'due_reading','350','usage due reading');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_simulate_schedule_v1(101,'{"frequency_kind":"hourly"}'::jsonb)$q$,'am_invalid_input');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_simulate_schedule_v1(101,'{"frequency_kind":"daily","drop":"x"}'::jsonb)$q$,'am_invalid_input');
END $$;
COMMIT;

-- P5 bootstrap + audit + direct table access is impossible
BEGIN; SET LOCAL ROLE authenticated;
DO $$ BEGIN
 PERFORM c10_test.as_user('bo102'); PERFORM c10_test.eq(c10_demo.am_bootstrap_v1(102,'boot-102-0001')->>'status','applied','bootstrap 102');
 PERFORM c10_test.eq((c10_demo.am_bootstrap_v1(102,'boot-102-0001'))->>'status','applied','bootstrap replay');
 PERFORM c10_test.denied($q$SELECT c10_demo.am_bootstrap_v1(101,'boot-101-0001')$q$,'am_denied');
 PERFORM c10_test.denied('SELECT count(*) FROM c10_demo.am_policy','permission denied');
 PERFORM c10_test.denied('SELECT count(*) FROM c10_demo.am_audit','permission denied');
 PERFORM c10_test.denied($q$INSERT INTO c10_demo.am_grants(tenant_id,business_id,user_id,role,granted_by) VALUES(1,101,'d3333333-3333-4333-8333-333333333333','supervisor','d3333333-3333-4333-8333-333333333333')$q$,'permission denied');
 PERFORM c10_test.denied('SELECT c10_demo.ami_cfg(101,NULL,NULL,''wo.maker_checker'')','permission denied');
 PERFORM c10_test.denied('SELECT c10_demo.ami_ctx(101)','permission denied');
END $$;
COMMIT;
DO $$ BEGIN
 PERFORM c10_test.eq((SELECT count(*) FROM c10_demo.am_audit WHERE business_id=101 AND entity='policy')>=4,'true','policy audit rows');
 PERFORM c10_test.eq((SELECT bool_and(row_hash IS NOT NULL) FROM c10_demo.am_audit)::text,'true','hash chain populated');
 BEGIN UPDATE c10_demo.am_audit SET reason='tamper' WHERE id=(SELECT min(id) FROM c10_demo.am_audit); RAISE EXCEPTION 'tamper allowed';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'am_append_only_record' THEN RAISE; END IF; END;
 BEGIN UPDATE c10_demo.am_policy_catalog SET sort=1; RAISE EXCEPTION 'catalog mutable';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'am_append_only_record' THEN RAISE; END IF; END;
 RAISE NOTICE 'A055_POLICY_E2E_PASS';
END $$;
