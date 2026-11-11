-- C10-A044 disposable E2E: signed-session CLAIM SIMULATION only, not Supabase GoTrue.
\set ON_ERROR_STOP on
BEGIN;
SET ROLE authenticated;
SET LOCAL request.jwt.claim.sub = '11111111-1111-4111-8111-111111111111';
DO $$
DECLARE x jsonb; y jsonb; z jsonb;
BEGIN
 x:=c10_demo.read_control_settings_v1(101);
 IF x->>'tenant_id'<>'1' OR jsonb_array_length(x->'items')<>18
 THEN RAISE EXCEPTION 'OWNER_LIST_FAILED'; END IF;
 x:=c10_demo.write_control_setting_v1(101,'inventory.count','both',
  'request_approval',false,0,'req_owner_101','Enable a business menu without stock access');
 IF x->>'status'<>'applied' OR x->>'version'<>'1'
 THEN RAISE EXCEPTION 'INITIAL_WRITE_FAILED'; END IF;
 y:=c10_demo.write_control_setting_v1(101,'inventory.count','both',
  'request_approval',false,0,'req_owner_101','Enable a business menu without stock access');
 IF x<>y THEN RAISE EXCEPTION 'REPLAY_NOT_IDENTICAL'; END IF;
 BEGIN
  PERFORM c10_demo.write_control_setting_v1(101,'inventory.count','both',
   'request_approval',true,0,'req_owner_101','Enable a business menu without stock access');
  RAISE EXCEPTION 'BAD_REPLAY_ALLOWED';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='BAD_REPLAY_ALLOWED' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM c10_demo.write_control_setting_v1(101,'inventory.count','both',
   'request_approval',true,0,'req_stale_101','Simulate stale settings update');
  RAISE EXCEPTION 'STALE_ALLOWED';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM='STALE_ALLOWED' THEN RAISE; END IF;
 END;
 z:=c10_demo.read_control_settings_v1(102);
 IF (SELECT count(*) FROM jsonb_array_elements(z->'items') m
    WHERE m->>'control_id'='inventory.count' AND m->>'version'='0')<>1
 THEN RAISE EXCEPTION 'SIBLING_INHERITED_SETTING'; END IF;
END $$;
COMMIT;
BEGIN;
SET ROLE authenticated;
SET LOCAL request.jwt.claim.sub = '22222222-2222-4222-8222-222222222222';
DO $$
DECLARE x jsonb;
BEGIN
 x:=c10_demo.write_control_setting_v1(101,'inventory.count','both',
  'request_approval',true,1,'req_local_101','Business owner requests enable preference');
 IF x->>'status'<>'pending' THEN RAISE EXCEPTION 'APPROVAL_NOT_PENDING'; END IF;
 IF (c10_demo.read_control_settings_v1(101)->'items'->0) IS NULL
 THEN RAISE EXCEPTION 'READ_MISSING'; END IF;
 BEGIN
  PERFORM c10_demo.write_control_setting_v1(102,'inventory.count','both',
   'request_approval',true,1,'req_foreign_business','Cross business scope must fail');
  RAISE EXCEPTION 'CROSS_BIZ_ALLOWED';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM='CROSS_BIZ_ALLOWED' THEN RAISE; END IF; END;
 BEGIN
  PERFORM c10_demo.write_control_setting_v1(101,'inventory.count','central_only',
   'central_only',true,1,'req_local_placement','Local placement escalated');
  RAISE EXCEPTION 'PLACEMENT_ESCALATION_ALLOWED';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM='PLACEMENT_ESCALATION_ALLOWED' THEN RAISE; END IF; END;
 BEGIN
  PERFORM c10_demo.decide_control_setting_v1((x->>'request_id')::bigint,'approve');
  RAISE EXCEPTION 'LOCAL_APPROVAL_ALLOWED';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM='LOCAL_APPROVAL_ALLOWED' THEN RAISE; END IF; END;
END $$;
COMMIT;
BEGIN;
SET ROLE authenticated;
SET LOCAL request.jwt.claim.sub='33333333-3333-4333-8333-333333333333';
DO $$BEGIN
 BEGIN PERFORM c10_demo.read_control_settings_v1(101); RAISE EXCEPTION 'MANAGER_READ_ALLOWED';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM='MANAGER_READ_ALLOWED' THEN RAISE; END IF; END;
END$$;
COMMIT;
BEGIN;
SET ROLE authenticated;
SET LOCAL request.jwt.claim.sub='77777777-7777-4777-8777-777777777777';
DO $$BEGIN
 BEGIN PERFORM c10_demo.read_control_settings_v1(101); RAISE EXCEPTION 'CROSS_TENANT_ALLOWED';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM='CROSS_TENANT_ALLOWED' THEN RAISE; END IF; END;
END$$;
COMMIT;
BEGIN;
SET ROLE authenticated;
SET LOCAL request.jwt.claim.sub='66666666-6666-4666-8666-666666666666';
DO $$BEGIN
 BEGIN PERFORM c10_demo.read_control_settings_v1(101); RAISE EXCEPTION 'REVOKED_ALLOWED';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM='REVOKED_ALLOWED' THEN RAISE; END IF; END;
END$$;
COMMIT;
BEGIN;
SET ROLE authenticated;
SET LOCAL request.jwt.claim.sub='44444444-4444-4444-8444-444444444444';
DO $$BEGIN
 BEGIN PERFORM c10_demo.read_control_settings_v1(101); RAISE EXCEPTION 'STAFF_ALLOWED';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM='STAFF_ALLOWED' THEN RAISE; END IF; END;
END$$;
COMMIT;
BEGIN;
SET ROLE authenticated;
RESET request.jwt.claim.sub;
DO $$BEGIN
 BEGIN PERFORM c10_demo.read_control_settings_v1(101); RAISE EXCEPTION 'ANON_CLAIM_ALLOWED';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM='ANON_CLAIM_ALLOWED' THEN RAISE; END IF; END;
END$$;
COMMIT;
BEGIN;
SET ROLE authenticated;
SET LOCAL request.jwt.claim.sub='11111111-1111-4111-8111-111111111111';
DO $$
DECLARE id bigint; s jsonb;
BEGIN
 SELECT id INTO id FROM c10_demo.control_setting_requests_v1 WHERE control_id='inventory.count' AND status='pending';
 s:=c10_demo.decide_control_setting_v1(id,'approve');
 IF s->>'status'<>'approved' THEN RAISE EXCEPTION 'APPROVAL_FAILED'; END IF;
 IF (SELECT version FROM c10_demo.control_settings_v1 WHERE business_id=101 AND control_id='inventory.count')<>2
 THEN RAISE EXCEPTION 'APPROVAL_NOT_APPLIED'; END IF;
 IF (SELECT count(*) FROM c10_demo.control_setting_audit_v1 WHERE business_id=101)<3
 THEN RAISE EXCEPTION 'AUDIT_MISSING'; END IF;
 IF EXISTS(SELECT 1 FROM c10_demo.business_module_settings_v1 WHERE operational_enabled)
 THEN RAISE EXCEPTION 'UNAUTHORIZED_MODULE_ACTIVATION'; END IF;
 BEGIN
  UPDATE c10_demo.control_setting_audit_v1 SET event='updated' WHERE business_id=101;
  RAISE EXCEPTION 'AUDIT_MUTATION_ALLOWED';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM='AUDIT_MUTATION_ALLOWED' THEN RAISE; END IF; END;
END $$;
COMMIT;
-- Neither the app role nor anon receives direct DML grants.
SELECT CASE WHEN has_table_privilege('authenticated','c10_demo.control_settings_v1','UPDATE')
 THEN 1/0 ELSE 1 END AS direct_write_denied;
SELECT CASE WHEN has_function_privilege('anon','c10_demo.write_control_setting_v1(bigint,text,text,text,boolean,bigint,text,text)','EXECUTE')
 THEN 1/0 ELSE 1 END AS anon_rpc_denied;
SELECT 'C10-A044 scoped placement/config/approval and negative role SQL PASS' AS result;
