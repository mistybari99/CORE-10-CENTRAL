-- Shared SQL test helpers (synthetic A046 registry UUIDs + A051 fixture UUIDs; signed-claim SIMULATION, NOT GoTrue).
CREATE SCHEMA IF NOT EXISTS c10_test;
GRANT USAGE ON SCHEMA c10_test TO authenticated,anon;
CREATE OR REPLACE FUNCTION c10_test.u(p text) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT (CASE p
 WHEN 'owner' THEN '11111111-1111-4111-8111-111111111111' WHEN 'bo101' THEN '22222222-2222-4222-8222-222222222222'
 WHEN 'mgr101' THEN '33333333-3333-4333-8333-333333333333' WHEN 'counter' THEN '44444444-4444-4444-8444-444444444444'
 WHEN 'investor' THEN '55555555-5555-4555-8555-555555555555' WHEN 'revoked' THEN '66666666-6666-4666-8666-666666666666'
 WHEN 'ownerB' THEN '77777777-7777-4777-8777-777777777777' WHEN 'staffB2' THEN '88888888-8888-4888-8888-888888888888'
 WHEN 'operator' THEN '99999999-9999-4999-8999-999999999999' WHEN 'boB' THEN 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
 WHEN 'mgrB' THEN 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' WHEN 'factory' THEN 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'
 WHEN 'branch' THEN 'dddddddd-dddd-4ddd-8ddd-dddddddddddd' WHEN 'unassigned' THEN 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'
 WHEN 'reviewer_na' THEN 'ffffffff-ffff-4fff-8fff-ffffffffffff' WHEN 'partner' THEN '90909090-9090-4090-8090-909090909090'
 WHEN 'mgrB2' THEN 'b1111111-1111-4111-8111-111111111111' WHEN 'boB2' THEN 'b2222222-2222-4222-8222-222222222222' END)::uuid $$;
CREATE OR REPLACE FUNCTION c10_test.as_user(p text) RETURNS void LANGUAGE sql AS $$ SELECT set_config('request.jwt.claim.sub',c10_test.u(p)::text,true); SELECT 1 $$;
CREATE OR REPLACE FUNCTION c10_test.eq(a text,b text,msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF a IS DISTINCT FROM b THEN RAISE EXCEPTION 'ASSERT % : got [%] want [%]',msg,a,b; END IF; END$$;
CREATE OR REPLACE FUNCTION c10_test.denied(p_sql text,p_expect text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 BEGIN EXECUTE p_sql; EXCEPTION WHEN OTHERS THEN
  IF SQLERRM NOT LIKE p_expect||'%' THEN RAISE EXCEPTION 'WRONG_ERROR [%] for %: want %',SQLERRM,p_sql,p_expect; END IF; RETURN; END;
 RAISE EXCEPTION 'EXPECTED_DENIAL_DID_NOT_HAPPEN: %',p_sql;
END$$;
CREATE OR REPLACE FUNCTION c10_test.eid(p_business bigint,p_no text) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER AS
$$ DECLARE v bigint; BEGIN SELECT id INTO v FROM c10_demo.wf_employees WHERE business_id=p_business AND employee_no=p_no; RETURN v; END$$;
CREATE OR REPLACE FUNCTION c10_test.line(p_run bigint,p_no text,p_col text) RETURNS text LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v text; BEGIN EXECUTE format('SELECT %I::text FROM c10_demo.wf_payroll_lines WHERE run_id=$1 AND employee_no=$2',p_col) INTO v USING p_run,p_no; RETURN v; END$$;
CREATE OR REPLACE FUNCTION c10_test.q(p_sql text) RETURNS text LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v text; BEGIN EXECUTE p_sql INTO v; RETURN v; END$$;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA c10_test TO authenticated,anon;
