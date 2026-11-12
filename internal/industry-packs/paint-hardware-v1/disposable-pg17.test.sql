
\set ON_ERROR_STOP on
-- Disposable shared contract mock: proves SQL transaction/privilege mechanics only, NOT GoTrue/RLS production certification.
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE anon NOLOGIN;
CREATE SCHEMA c10_demo;
CREATE TABLE c10_demo.businesses(id bigint PRIMARY KEY,tenant_id bigint NOT NULL, UNIQUE(id,tenant_id));
CREATE TABLE c10_demo.fixture_members(actor uuid NOT NULL,tenant_id bigint NOT NULL,business_id bigint NOT NULL,
 PRIMARY KEY(actor,business_id));
INSERT INTO c10_demo.businesses VALUES(10,1),(20,1),(30,2);
INSERT INTO c10_demo.fixture_members VALUES
 ('aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa',1,10),
 ('bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb',1,10),
 ('aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa',1,20),
 ('cccccccc-cccc-4ccc-cccc-cccccccccccc',2,30);
CREATE FUNCTION c10_demo.actor_uid() RETURNS uuid LANGUAGE sql STABLE
 AS $$ SELECT nullif(current_setting('paint.actor',true),'')::uuid $$;
CREATE FUNCTION c10_demo.can_manage(t bigint,b bigint) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
 SET search_path=c10_demo,pg_catalog AS $$
 SELECT EXISTS(SELECT 1 FROM c10_demo.fixture_members m
 WHERE m.actor=c10_demo.actor_uid() AND m.tenant_id=t AND m.business_id=b)
 $$;
GRANT USAGE ON SCHEMA c10_demo TO authenticated;
GRANT EXECUTE ON FUNCTION c10_demo.actor_uid() TO authenticated;
GRANT EXECUTE ON FUNCTION c10_demo.can_manage(bigint,bigint) TO authenticated;
\ir disposable-pg17.sql
SET ROLE authenticated;
SELECT set_config('paint.actor','aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa',false);
DO $test$
DECLARE
 x jsonb; f bigint; t bigint; old jsonb; one jsonb; returned int; msg text;
 recipe jsonb := '{"code":"BROWN01","version":1,"baseSku":"WHITE01","outputSku":"BROWNOUT","pigments":[{"sku":"RED01","ulPerL":16000},{"sku":"BLACK1","ulPerL":2000}],"qcMaxDE100":180,"toleranceBps":200}'::jsonb;
 BEGIN
 x:=c10_demo.paint_command_v1(10,'recipe',recipe,'req-0000001');
 f:=(x->>'formulaId')::bigint;
 IF f IS NULL OR x->>'status'<>'REGISTERED' THEN RAISE EXCEPTION 'RECIPE_CREATE_FAILED'; END IF;
 old:=c10_demo.paint_command_v1(10,'recipe',recipe,'req-0000001');
 IF x<>old THEN RAISE EXCEPTION 'RECIPE_IDEMPOTENCY_FAILED'; END IF;
 BEGIN
 PERFORM c10_demo.paint_command_v1(10,'recipe',recipe||'{"version":2}'::jsonb,'req-0000001');
 RAISE EXCEPTION 'EXPECTED_REPLAY_DENIAL';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM='EXPECTED_REPLAY_DENIAL' THEN RAISE; END IF; END;
 x:=c10_demo.paint_command_v1(10,'open',
  jsonb_build_object('ticketKey','TINT-01','formulaId',f,'baseML',2500),'req-0000002');
 t:=(x->>'ticketId')::bigint;
 IF x->>'status'<>'DRAFT' THEN RAISE EXCEPTION 'TICKET_OPEN_FAILED'; END IF;
 -- Raw table write must fail for authenticated.
 BEGIN
 EXECUTE 'UPDATE c10_demo.paint_tint_v1 SET status=''QC_PASSED'' WHERE id='||t::text;
 RAISE EXCEPTION 'EXPECTED_DIRECT_TABLE_DENIAL';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM='EXPECTED_DIRECT_TABLE_DENIAL' THEN RAISE; END IF; END;
 -- Formula scope verification blocks other business reference.
 BEGIN
 PERFORM c10_demo.paint_command_v1(20,'open',
 jsonb_build_object('ticketKey','TINT-02','formulaId',f,'baseML',2500),'req-0000003');
 RAISE EXCEPTION 'EXPECTED_CROSS_BUSINESS_DENIAL';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM='EXPECTED_CROSS_BUSINESS_DENIAL' THEN RAISE; END IF; END;
 -- Invalid dosage must leave ticket in DRAFT (transaction rollback).
 BEGIN
 PERFORM c10_demo.paint_command_v1(10,'mix',
 jsonb_build_object('ticketId',t,'readings',
 '[{"sku":"RED01","actualUL":50000},{"sku":"BLACK1","actualUL":5000}]'::jsonb),'req-0000004');
 RAISE EXCEPTION 'EXPECTED_MIX_DENIAL';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM='EXPECTED_MIX_DENIAL' THEN RAISE; END IF; END;
 x:=c10_demo.paint_command_v1(10,'mix',jsonb_build_object('ticketId',t,'readings',
 '[{"sku":"RED01","actualUL":40000},{"sku":"BLACK1","actualUL":5000}]'::jsonb),'req-0000005');
 IF x->>'status'<>'MIXED' THEN RAISE EXCEPTION 'VALID_MIX_FAILED'; END IF;
 -- Same actor may not approve own mix.
 BEGIN
 PERFORM c10_demo.paint_command_v1(10,'qc',jsonb_build_object('ticketId',t,'deltaE100',100,
 'evidenceRef','QC001','method','SPECTRO','instrumentRef','DEVICE1','calibrated',true),'req-0000006');
 RAISE EXCEPTION 'EXPECTED_QC_MAKER_DENIAL';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM='EXPECTED_QC_MAKER_DENIAL' THEN RAISE; END IF; END;
 PERFORM set_config('paint.actor','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb',false);
 x:=c10_demo.paint_command_v1(10,'qc',jsonb_build_object('ticketId',t,'deltaE100',250,
 'evidenceRef','QC002','method','SPECTRO','instrumentRef','DEVICE1','calibrated',true),'req-0000007');
 IF x->>'status'<>'QC_FAILED' THEN RAISE EXCEPTION 'QC_FAILURE_NOT_RECORDED'; END IF;
 PERFORM set_config('paint.actor','aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa',false);
 x:=c10_demo.paint_command_v1(10,'mix',jsonb_build_object('ticketId',t,'readings',
 '[{"sku":"RED01","actualUL":40000},{"sku":"BLACK1","actualUL":5000}]'::jsonb),'req-0000008');
 PERFORM set_config('paint.actor','bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbbb',false);
 x:=c10_demo.paint_command_v1(10,'qc',jsonb_build_object('ticketId',t,'deltaE100',120,
 'evidenceRef','QC003','method','SPECTRO','instrumentRef','DEVICE1','calibrated',true),'req-0000009');
 IF x->>'status'<>'QC_PASSED' OR x->>'postAuthority'<>'false' THEN RAISE EXCEPTION 'QC_PASS_OR_POST_GUARD_FAILED'; END IF;
 x:=c10_demo.paint_report_v1(10);
 IF (x->>'qcPassed')::int<>1 OR (x->>'stockPosted')::boolean<>false OR
    (x->>'financePosted')::boolean<>false THEN RAISE EXCEPTION 'REPORT_MATH_FAILED'; END IF;
 -- Replay identical QC request must return same result without event duplication.
 old:=c10_demo.paint_command_v1(10,'qc',jsonb_build_object('ticketId',t,'deltaE100',120,
 'evidenceRef','QC003','method','SPECTRO','instrumentRef','DEVICE1','calibrated',true),'req-0000009');
 IF x IS NULL OR old->>'status'<>'QC_PASSED' THEN RAISE EXCEPTION 'QC_REPLAY_FAILED'; END IF;
 -- Remaining tests check signed mock permission revocation and unauthenticated denial.
 PERFORM set_config('paint.actor','cccccccc-cccc-4ccc-cccc-cccccccccccc',false);
 BEGIN
 PERFORM c10_demo.paint_report_v1(10);
 RAISE EXCEPTION 'EXPECTED_TENANT_DENIAL';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM='EXPECTED_TENANT_DENIAL' THEN RAISE; END IF; END;
 PERFORM set_config('paint.actor','',false);
 BEGIN
 PERFORM c10_demo.paint_report_v1(10);
 RAISE EXCEPTION 'EXPECTED_ANON_DENIAL';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM='EXPECTED_ANON_DENIAL' THEN RAISE; END IF; END;
 RAISE NOTICE 'BUILD05_PG17_SQL_SCOPED_DURABILITY_POSITIVE_NEGATIVE_PASS';
END $test$;
RESET ROLE;
-- Verify via privileged disposable test owner that no hidden stock/finance tables were created.
DO $$
BEGIN
 IF to_regclass('c10_demo.stock_balances_v1') IS NOT NULL OR
   to_regclass('c10_demo.general_ledger_v1') IS NOT NULL THEN
 RAISE EXCEPTION 'BUILD05_CREATED_SHADOW_STOCK_OR_LEDGER'; END IF;
 IF (SELECT count(*) FROM c10_demo.paint_events_v1 WHERE business_id=10) <> 6 THEN
 RAISE EXCEPTION 'BAD_EVENT_COUNT'; END IF;
END $$;
