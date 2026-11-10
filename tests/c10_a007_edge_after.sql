-- C10-A007 EDGE tests, run AFTER tests/c10_a007_mirror_live_fixture.sql and
-- AFTER installing supabase_candidate/c10_a007_migration.sql (disposable DB only).
-- Covers: null/0/negative/oversized limit and business id, null location_id,
-- null/unmapped/cyclic org units, status literals vs the live CHECK constraints,
-- real-shaped nested org tree (business < legal_entity < group), service_role /
-- anon / authenticated EXECUTE, search_path hijack, JWT claim forms, RLS bypass
-- by the definer, ordering/tie-break/limit, and an 8-way UNION load test.
\set ON_ERROR_STOP on

-- ------------------------------------------------------------ test helpers
CREATE SCHEMA t;
GRANT USAGE ON SCHEMA t TO anon, authenticated, service_role;
CREATE FUNCTION t.expect_err(q text, code text) RETURNS void LANGUAGE plpgsql AS $f$
DECLARE ok boolean := false; got text;
BEGIN
  BEGIN
    EXECUTE q;
  EXCEPTION WHEN OTHERS THEN
    got := SQLSTATE; ok := (SQLSTATE = code);
    IF NOT ok THEN RAISE EXCEPTION 'FAIL: % expected SQLSTATE % got % (%)', q, code, got, SQLERRM; END IF;
    RETURN;
  END;
  RAISE EXCEPTION 'FAIL: % expected SQLSTATE % but it succeeded', q, code;
END $f$;
CREATE FUNCTION t.ids(j jsonb) RETURNS text[] LANGUAGE sql IMMUTABLE AS
$f$ SELECT COALESCE(array_agg(e->>'id' ORDER BY ord),'{}') FROM jsonb_array_elements(j->'items') WITH ORDINALITY a(e,ord) $f$;
CREATE FUNCTION t.sorted_ids(j jsonb) RETURNS text[] LANGUAGE sql IMMUTABLE AS
$f$ SELECT COALESCE(array_agg(e->>'id' ORDER BY e->>'id'),'{}') FROM jsonb_array_elements(j->'items') a(e) $f$;
CREATE FUNCTION t.as_user(u text) RETURNS void LANGUAGE sql AS
$f$ SELECT set_config('request.jwt.claim.sub',u,false) $f$;

-- ------------------------------------------------------------ identities
-- profile status is one of pending/active/disabled on live (not 'inactive').
INSERT INTO auth.users(id) VALUES
 ('00000000-0000-4000-8000-000000000001'),('00000000-0000-4000-8000-000000000002'),
 ('00000000-0000-4000-8000-000000000003'),('00000000-0000-4000-8000-000000000004'),
 ('00000000-0000-4000-8000-000000000005'),('00000000-0000-4000-8000-000000000006');
INSERT INTO public.profiles(id,status) VALUES
 ('00000000-0000-4000-8000-000000000001','active'),   -- owner
 ('00000000-0000-4000-8000-000000000002','active'),   -- staff
 ('00000000-0000-4000-8000-000000000003','disabled'), -- owner role, disabled
 ('00000000-0000-4000-8000-000000000004','pending'),  -- owner role, pending
 ('00000000-0000-4000-8000-000000000005','active'),   -- active, no role at all
 ('00000000-0000-4000-8000-000000000006','active');   -- second owner, JSON-claims form
INSERT INTO public.user_roles(user_id,role_code) VALUES
 ('00000000-0000-4000-8000-000000000001','owner'),
 ('00000000-0000-4000-8000-000000000002','staff'),
 ('00000000-0000-4000-8000-000000000002','manager'),
 ('00000000-0000-4000-8000-000000000003','owner'),
 ('00000000-0000-4000-8000-000000000004','owner'),
 ('00000000-0000-4000-8000-000000000006','owner');

-- ------------------------------------------------------------ org scenario
-- Live has ONE business (3 SWEETS). Add: 5 PAINT active, 6 inactive, 7 planned.
INSERT INTO public.org_units(id,parent_id,kind,code,status) OVERRIDING SYSTEM VALUE VALUES
 (5,4,'business','PAINT','active'),
 (6,4,'business','OLDBIZ','inactive'),
 (7,4,'business','NEWBIZ','planned'),
 (8,5,'branch','PAINT-B1','active'),
 (9,6,'branch','OLDBIZ-B1','active'),
 (10,7,'branch','NEWBIZ-B1','active'),
 (50,4,'branch','CYC-A','active'),
 (51,50,'branch','CYC-B','active'),
 (60,4,'business','EMPTYBIZ','active');
-- parent cycle between non-business units: no constraint on live prevents it.
UPDATE public.org_units SET parent_id=51 WHERE id=50;
INSERT INTO public.locations(id,code,kind,status,org_unit_id) OVERRIDING SYSTEM VALUE VALUES
 (101,'paint_main','showroom','live',8),
 (102,'old_main','showroom','live',9),
 (103,'new_main','showroom','live',10),
 (104,'cycle_loc','other','live',50),
 (105,'no_unit_loc','other','live',NULL),
 (106,'group_loc','other','live',1),
 (107,'le_loc','other','live',2);

-- entries (status literal 'submitted' is the only awaiting-approval status)
INSERT INTO public.entries(id,form_code,location_id,serial,entry_date,created_by,status,created_at) VALUES
 ('00000000-0000-4000-a000-000000000001','F',1,1,'2026-01-10','00000000-0000-4000-8000-000000000002','submitted','2026-01-10 10:00+00'),
 ('00000000-0000-4000-a000-000000000002','F',1,2,'2026-01-10','00000000-0000-4000-8000-000000000002','draft','2026-01-10 10:01+00'),
 ('00000000-0000-4000-a000-000000000003','F',1,3,'2026-01-10','00000000-0000-4000-8000-000000000002','approved','2026-01-10 10:02+00'),
 ('00000000-0000-4000-a000-000000000004','F',1,4,'2026-01-10','00000000-0000-4000-8000-000000000002','rejected','2026-01-10 10:03+00'),
 ('00000000-0000-4000-a000-000000000010','F',101,1,'2026-01-09','00000000-0000-4000-8000-000000000002','submitted','2026-01-09 09:00+00'),
 ('00000000-0000-4000-a000-000000000020','F',102,1,'2026-01-09','00000000-0000-4000-8000-000000000002','submitted','2026-01-09 09:01+00'),
 ('00000000-0000-4000-a000-000000000021','F',103,1,'2026-01-09','00000000-0000-4000-8000-000000000002','submitted','2026-01-09 09:02+00'),
 ('00000000-0000-4000-a000-000000000022','F',104,1,'2026-01-09','00000000-0000-4000-8000-000000000002','submitted','2026-01-09 09:03+00'),
 ('00000000-0000-4000-a000-000000000023','F',105,1,'2026-01-09','00000000-0000-4000-8000-000000000002','submitted','2026-01-09 09:04+00'),
 ('00000000-0000-4000-a000-000000000024','F',106,1,'2026-01-09','00000000-0000-4000-8000-000000000002','submitted','2026-01-09 09:05+00'),
 ('00000000-0000-4000-a000-000000000025','F',107,1,'2026-01-09','00000000-0000-4000-8000-000000000002','submitted','2026-01-09 09:06+00');

INSERT INTO public.release_requests(id,entry_id,flag_code,reason,requested_by,status,requested_at) OVERRIDING SYSTEM VALUE VALUES
 (1,'00000000-0000-4000-a000-000000000001','F1','r','00000000-0000-4000-8000-000000000002','pending','2026-01-10 11:00+00'),
 (2,'00000000-0000-4000-a000-000000000003','F1','r','00000000-0000-4000-8000-000000000002','approved','2026-01-10 11:01+00'),
 (3,'00000000-0000-4000-a000-000000000003','F2','r','00000000-0000-4000-8000-000000000002','rejected','2026-01-10 11:02+00'),
 (4,'00000000-0000-4000-a000-000000000021','F1','r','00000000-0000-4000-8000-000000000002','pending','2026-01-09 09:10+00'); -- planned biz
INSERT INTO public.entry_change_requests(id,entry_id,base_rev,requested_by,reason,patch,status,created_at) OVERRIDING SYSTEM VALUE VALUES
 (1,'00000000-0000-4000-a000-000000000001',1,'00000000-0000-4000-8000-000000000002','r','{}','pending','2026-01-10 12:00+00'),
 (2,'00000000-0000-4000-a000-000000000003',1,'00000000-0000-4000-8000-000000000002','r','{}','approved','2026-01-10 12:01+00'),
 (3,'00000000-0000-4000-a000-000000000003',1,'00000000-0000-4000-8000-000000000002','r','{}','rejected','2026-01-10 12:02+00'),
 (4,'00000000-0000-4000-a000-000000000003',1,'00000000-0000-4000-8000-000000000002','r','{}','cancelled','2026-01-10 12:03+00'),
 (5,'00000000-0000-4000-a000-000000000020',1,'00000000-0000-4000-8000-000000000002','r','{}','pending','2026-01-09 09:11+00'); -- inactive biz
INSERT INTO public.exceptions(id,entry_id,form_code,location_id,entry_date,flag_code,level,status,created_at) OVERRIDING SYSTEM VALUE VALUES
 (1,NULL,'F',1,'2026-01-10','X','red','open','2026-01-10 13:00+00'),
 (2,'00000000-0000-4000-a000-000000000001','F',1,'2026-01-10','X','red','open','2026-01-10 14:00+00'),
 (3,NULL,'F',1,'2026-01-10','X','yellow','resolved','2026-01-10 14:01+00'),
 (4,'00000000-0000-4000-a000-000000000010','F',1,'2026-01-10','X','red','open','2026-01-10 14:02+00'),  -- conflict: loc SWEETS, entry PAINT
 (5,'00000000-0000-4000-a000-000000000001','F',101,'2026-01-10','X','red','open','2026-01-10 14:03+00'), -- conflict: loc PAINT, entry SWEETS
 (6,NULL,'F',101,'2026-01-09','X','red','open','2026-01-09 12:00+00'),                                  -- PAINT, visible
 (7,NULL,'F',102,'2026-01-09','X','red','open','2026-01-09 12:01+00');                                  -- inactive biz
INSERT INTO public.emergency_requests(id,grant_code,requested_by,reason,location_id,status,created_at) OVERRIDING SYSTEM VALUE VALUES
 (1,'G','00000000-0000-4000-8000-000000000002','r',1,'pending','2026-01-10 15:00+00'),
 (2,'G','00000000-0000-4000-8000-000000000002','r',1,'approved','2026-01-10 15:01+00'),
 (3,'G','00000000-0000-4000-8000-000000000002','r',1,'rejected','2026-01-10 15:02+00'),
 (4,'G','00000000-0000-4000-8000-000000000002','r',1,'used','2026-01-10 15:03+00'),
 (5,'G','00000000-0000-4000-8000-000000000002','r',1,'expired','2026-01-10 15:04+00'),
 (6,'G','00000000-0000-4000-8000-000000000002','r',1,'cancelled','2026-01-10 15:05+00'),
 (7,'G','00000000-0000-4000-8000-000000000002','r',NULL,'pending','2026-01-10 15:06+00'),  -- NULL location
 (8,'G','00000000-0000-4000-8000-000000000002','r',105,'pending','2026-01-10 15:07+00');  -- location without org unit
INSERT INTO public.pay_requests(id,kind,status,location_id,requested_by,amount,reason,needed_by,created_at) OVERRIDING SYSTEM VALUE VALUES
 (1,'supplier','received',1,'00000000-0000-4000-8000-000000000002',10,'abc','2026-02-01','2026-01-10 15:00+00'), -- ties emergency:1
 (2,'supplier','approved',1,'00000000-0000-4000-8000-000000000002',10,'abc','2026-02-01','2026-01-10 15:01+00'),
 (3,'supplier','rejected',1,'00000000-0000-4000-8000-000000000002',10,'abc','2026-02-01','2026-01-10 15:02+00'),
 (4,'supplier','paid',1,'00000000-0000-4000-8000-000000000002',10,'abc','2026-02-01','2026-01-10 15:03+00'),
 (5,'supplier','cancelled',1,'00000000-0000-4000-8000-000000000002',10,'abc','2026-02-01','2026-01-10 15:04+00'),
 (6,'supplier','received',NULL,'00000000-0000-4000-8000-000000000002',10,'abc','2026-02-01','2026-01-10 15:05+00'), -- NULL location
 (20,'salary','received',101,'00000000-0000-4000-8000-000000000002',10,'abc','2026-02-01','2026-01-09 10:00+00'),
 (21,'salary','received',103,'00000000-0000-4000-8000-000000000002',10,'abc','2026-02-01','2026-01-09 10:01+00'),   -- planned biz
 (22,'salary','received',106,'00000000-0000-4000-8000-000000000002',10,'abc','2026-02-01','2026-01-09 10:02+00'),   -- group, no business
 (23,'salary','received',107,'00000000-0000-4000-8000-000000000002',10,'abc','2026-02-01','2026-01-09 10:03+00');   -- legal entity, no business
INSERT INTO public.wastage_requests(id,item_id,location_id,qty,reason_code,requested_by,status,requested_at) VALUES
 ('00000000-0000-4000-b000-000000000001',gen_random_uuid(),1,1,'r','00000000-0000-4000-8000-000000000002','pending','2026-01-10 16:00+00'),
 ('00000000-0000-4000-b000-000000000002',gen_random_uuid(),1,1,'r','00000000-0000-4000-8000-000000000002','approved','2026-01-10 16:01+00'),
 ('00000000-0000-4000-b000-000000000003',gen_random_uuid(),1,1,'r','00000000-0000-4000-8000-000000000002','rejected','2026-01-10 16:02+00'),
 ('00000000-0000-4000-b000-000000000004',gen_random_uuid(),1,1,'r','00000000-0000-4000-8000-000000000002','cancelled','2026-01-10 16:03+00'),
 ('00000000-0000-4000-b000-000000000005',gen_random_uuid(),102,1,'r','00000000-0000-4000-8000-000000000002','pending','2026-01-09 10:10+00'); -- inactive biz
INSERT INTO public.item_changes(id,patch,requested_by,status,requested_at,org_unit_id) OVERRIDING SYSTEM VALUE VALUES
 (1,'{}','00000000-0000-4000-8000-000000000002','pending','2026-01-10 17:00+00',3),  -- unit is the business itself
 (2,'{}','00000000-0000-4000-8000-000000000002','approved','2026-01-10 17:01+00',3),
 (3,'{}','00000000-0000-4000-8000-000000000002','rejected','2026-01-10 17:02+00',3),
 (4,'{}','00000000-0000-4000-8000-000000000002','pending','2026-01-10 17:03+00',NULL), -- NULL unit
 (20,'{}','00000000-0000-4000-8000-000000000002','pending','2026-01-09 11:00+00',8),  -- branch under PAINT
 (21,'{}','00000000-0000-4000-8000-000000000002','pending','2026-01-09 11:01+00',9),  -- inactive biz
 (22,'{}','00000000-0000-4000-8000-000000000002','pending','2026-01-09 11:02+00',10), -- planned biz
 (23,'{}','00000000-0000-4000-8000-000000000002','pending','2026-01-09 11:03+00',50), -- parent cycle
 (24,'{}','00000000-0000-4000-8000-000000000002','pending','2026-01-09 11:04+00',1),  -- group
 (25,'{}','00000000-0000-4000-8000-000000000002','pending','2026-01-09 11:05+00',2);  -- legal entity

-- ------------------------------------------------------------ 1. status literals vs live CHECKs
DO $test$
DECLARE r record; def text;
BEGIN
  FOR r IN SELECT * FROM (VALUES
     ('public.entries','entries_status_check','submitted'),
     ('public.release_requests','release_requests_status_check','pending'),
     ('public.entry_change_requests','entry_change_requests_status_check','pending'),
     ('public.exceptions','exceptions_status_check','open'),
     ('public.emergency_requests','emergency_requests_status_check','pending'),
     ('public.pay_requests','pay_requests_status_check','received'),
     ('public.wastage_requests','wastage_requests_status_check','pending'),
     ('public.item_changes','item_changes_status_check','pending'),
     ('public.org_units','org_units_status_check','active')) v(tbl,con,lit) LOOP
    SELECT pg_get_constraintdef(oid) INTO def FROM pg_constraint WHERE conrelid=r.tbl::regclass AND conname=r.con;
    IF def IS NULL OR def NOT LIKE '%'''||r.lit||'''::text%' THEN
      RAISE EXCEPTION 'FAIL: literal % not allowed by CHECK %.%', r.lit, r.tbl, r.con;
    END IF;
  END LOOP;
  -- the pending literal of one table is NOT valid in another (no cross-table reuse)
  PERFORM t.expect_err($q$INSERT INTO public.pay_requests(kind,status,requested_by,amount,reason,needed_by) VALUES ('supplier','pending','00000000-0000-4000-8000-000000000002',1,'abc','2026-02-01')$q$,'23514');
  PERFORM t.expect_err($q$INSERT INTO public.entries(form_code,location_id,serial,entry_date,created_by,status) VALUES ('F',1,99,'2026-01-01','00000000-0000-4000-8000-000000000002','pending')$q$,'23514');
  PERFORM t.expect_err($q$INSERT INTO public.exceptions(form_code,location_id,entry_date,flag_code,level,status) VALUES ('F',1,'2026-01-01','X','red','pending')$q$,'23514');
  PERFORM t.expect_err($q$INSERT INTO public.profiles(id,status) VALUES (gen_random_uuid(),'inactive')$q$,'23514'); -- live profiles.status has no 'inactive'
  PERFORM t.expect_err($q$INSERT INTO public.org_units(parent_id,kind,code,status) VALUES (1,'business','ZZ-BAD','pending')$q$,'23514');
  RAISE NOTICE 'PASS status literals match live CHECK constraints; foreign literals rejected';
END $test$;

-- ------------------------------------------------------------ 2. ACL matrix
DO $test$
DECLARE f text := 'public.core10_owner_inbox_v1(bigint,integer)';
BEGIN
  IF has_function_privilege('anon',f,'EXECUTE') THEN RAISE EXCEPTION 'FAIL: anon has EXECUTE'; END IF;
  IF has_function_privilege('service_role',f,'EXECUTE') THEN RAISE EXCEPTION 'FAIL: service_role has EXECUTE'; END IF;
  IF NOT has_function_privilege('authenticated',f,'EXECUTE') THEN RAISE EXCEPTION 'FAIL: authenticated lacks EXECUTE'; END IF;
  IF has_function_privilege('public'::name,f,'EXECUTE') THEN RAISE EXCEPTION 'FAIL: PUBLIC has EXECUTE'; END IF;
  -- exact ACL: owner + authenticated only
  IF (SELECT array_length(proacl,1) FROM pg_proc WHERE oid=f::regprocedure) <> 2 THEN
    RAISE EXCEPTION 'FAIL: unexpected ACL %', (SELECT proacl::text FROM pg_proc WHERE oid=f::regprocedure);
  END IF;
  IF NOT (SELECT prosecdef AND proconfig = ARRAY['search_path=""'] FROM pg_proc WHERE oid=f::regprocedure) THEN
    RAISE EXCEPTION 'FAIL: not SECURITY DEFINER with empty search_path';
  END IF;
  -- live helper ACL mirrored: authenticated must NOT run the org helpers directly
  IF has_function_privilege('authenticated','public._business_of_loc123(integer)','EXECUTE')
     OR has_function_privilege('authenticated','public._business_of_unit123(bigint)','EXECUTE') THEN
    RAISE EXCEPTION 'FAIL: fixture helper ACL does not mirror live';
  END IF;
  RAISE NOTICE 'PASS ACL: only owner+authenticated; anon/PUBLIC/service_role denied';
END $test$;

-- anon and service_role: denied by ACL even with an owner uid in the session.
SET ROLE anon;
SELECT t.as_user('00000000-0000-4000-8000-000000000001');
SELECT t.expect_err('SELECT public.core10_owner_inbox_v1(NULL,40)','42501');
RESET ROLE;
SET ROLE service_role;
SELECT t.as_user('00000000-0000-4000-8000-000000000001');
SELECT t.expect_err('SELECT public.core10_owner_inbox_v1(NULL,40)','42501');
SELECT t.as_user('');
SELECT t.expect_err('SELECT public.core10_owner_inbox_v1(NULL,40)','42501');
RESET ROLE;

-- ------------------------------------------------------------ 3. owner behaviour
SET ROLE authenticated;
SELECT t.as_user('00000000-0000-4000-8000-000000000001');
DO $test$
DECLARE m jsonb; s jsonb; p jsonb; it jsonb; k text[];
BEGIN
  m := public.core10_owner_inbox_v1(NULL,40);
  s := public.core10_owner_inbox_v1(3,40);
  p := public.core10_owner_inbox_v1(5,40);

  -- exact expected sets (real-shaped org: business < legal_entity < group)
  IF t.sorted_ids(s) <> ARRAY['emergency:1','entry:00000000-0000-4000-a000-000000000001','entry_change:1',
        'exception:1','exception:2','item_change:1','pay:1','release:1',
        'wastage:00000000-0000-4000-b000-000000000001'] THEN
    RAISE EXCEPTION 'FAIL SWEETS set: %', t.sorted_ids(s);
  END IF;
  IF t.sorted_ids(p) <> ARRAY['entry:00000000-0000-4000-a000-000000000010','exception:6','item_change:20','pay:20'] THEN
    RAISE EXCEPTION 'FAIL PAINT set: %', t.sorted_ids(p);
  END IF;
  IF array_length(t.ids(m),1) <> 13 OR t.sorted_ids(m) <> (SELECT array_agg(x ORDER BY x) FROM unnest(t.ids(s)||t.ids(p)) x) THEN
    RAISE EXCEPTION 'FAIL master rollup is not exactly SWEETS+PAINT: %', t.sorted_ids(m);
  END IF;
  -- shape: exact key set, status literal, ISO UTC timestamp, id prefix <-> request_type
  FOR it IN SELECT * FROM jsonb_array_elements(m->'items') LOOP
    SELECT array_agg(key ORDER BY key) INTO k FROM jsonb_object_keys(it) key;
    IF k <> ARRAY['business_id','created_at','id','request_type','status','title'] THEN RAISE EXCEPTION 'FAIL keys %',k; END IF;
    IF it->>'status'<>'pending' OR it->>'created_at' !~ '^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$'
       OR jsonb_typeof(it->'business_id')<>'number' THEN RAISE EXCEPTION 'FAIL item shape %', it; END IF;
    IF split_part(it->>'id',':',1) <> (CASE it->>'request_type'
         WHEN 'entry' THEN 'entry' WHEN 'release_request' THEN 'release' WHEN 'entry_change' THEN 'entry_change'
         WHEN 'exception' THEN 'exception' WHEN 'emergency_request' THEN 'emergency'
         WHEN 'payment_request' THEN 'pay' WHEN 'wastage_request' THEN 'wastage' WHEN 'item_change' THEN 'item_change' END) THEN
      RAISE EXCEPTION 'FAIL id prefix/type mismatch %', it;
    END IF;
  END LOOP;
  IF m->'business_id' <> 'null'::jsonb OR (s->>'business_id')::int<>3 OR (p->>'business_id')::int<>5 THEN
    RAISE EXCEPTION 'FAIL business_id echo';
  END IF;
  -- hidden: NULL location (emergency:7 pay:6), no-unit loc (emergency:8, entry ...23), item_change:4 (NULL unit),
  -- inactive/planned/cycle/group/legal-entity mappings, conflicting exceptions 4 and 5, every non-pending status.
  IF t.ids(m) && ARRAY['emergency:7','emergency:8','pay:6','item_change:4','pay:21','pay:22','pay:23',
        'item_change:21','item_change:22','item_change:23','item_change:24','item_change:25',
        'exception:3','exception:4','exception:5','exception:7','release:2','release:3','release:4',
        'entry_change:2','entry_change:3','entry_change:4','entry_change:5','emergency:2','emergency:3','emergency:4',
        'emergency:5','emergency:6','pay:2','pay:3','pay:4','pay:5','item_change:2','item_change:3',
        'wastage:00000000-0000-4000-b000-000000000002','wastage:00000000-0000-4000-b000-000000000003',
        'wastage:00000000-0000-4000-b000-000000000004','wastage:00000000-0000-4000-b000-000000000005',
        'entry:00000000-0000-4000-a000-000000000002','entry:00000000-0000-4000-a000-000000000003',
        'entry:00000000-0000-4000-a000-000000000004','entry:00000000-0000-4000-a000-000000000020',
        'entry:00000000-0000-4000-a000-000000000021','entry:00000000-0000-4000-a000-000000000022',
        'entry:00000000-0000-4000-a000-000000000023','entry:00000000-0000-4000-a000-000000000024',
        'entry:00000000-0000-4000-a000-000000000025'] THEN
    RAISE EXCEPTION 'FAIL leak of unmapped/NULL/inactive/planned/cyclic/non-pending row: %', t.ids(m);
  END IF;
  RAISE NOTICE 'PASS owner sets: SWEETS=9 PAINT=4 master=13; no NULL-location/inactive/planned/cycle/non-pending leaks';
END $test$;

-- ordering: created_at DESC, then id ASC (emergency:1 and pay:1 share a timestamp)
DO $test$
DECLARE s jsonb := public.core10_owner_inbox_v1(3,40);
BEGIN
  IF t.ids(s) <> ARRAY['item_change:1','wastage:00000000-0000-4000-b000-000000000001','emergency:1','pay:1',
        'exception:2','exception:1','entry_change:1','release:1','entry:00000000-0000-4000-a000-000000000001'] THEN
    RAISE EXCEPTION 'FAIL ordering/tie-break: %', t.ids(s);
  END IF;
  IF t.ids(public.core10_owner_inbox_v1(3,1)) <> ARRAY['item_change:1']
     OR t.ids(public.core10_owner_inbox_v1(3,4)) <> ARRAY['item_change:1','wastage:00000000-0000-4000-b000-000000000001','emergency:1','pay:1']
     OR array_length(t.ids(public.core10_owner_inbox_v1(NULL,5)),1) <> 5 THEN
    RAISE EXCEPTION 'FAIL limit truncation';
  END IF;
  -- tie cut by LIMIT is deterministic: limit 3 keeps emergency:1 (id ASC), drops pay:1
  IF (t.ids(public.core10_owner_inbox_v1(3,3)))[3] <> 'emergency:1' THEN RAISE EXCEPTION 'FAIL tie at LIMIT boundary'; END IF;
  RAISE NOTICE 'PASS ordering, tie-break and limit truncation deterministic';
END $test$;

-- ------------------------------------------------------------ 4. limit edge cases
DO $test$
DECLARE d jsonb;
BEGIN
  -- NULL limit falls back to the default 40 (documented behaviour of COALESCE)
  d := public.core10_owner_inbox_v1(NULL,NULL);
  IF array_length(t.ids(d),1) <> 13 THEN RAISE EXCEPTION 'FAIL NULL limit default'; END IF;
  d := public.core10_owner_inbox_v1();   -- both defaults
  IF array_length(t.ids(d),1) <> 13 THEN RAISE EXCEPTION 'FAIL defaults'; END IF;
  PERFORM public.core10_owner_inbox_v1(NULL,1);
  PERFORM public.core10_owner_inbox_v1(NULL,40);
  PERFORM t.expect_err('SELECT public.core10_owner_inbox_v1(NULL,0)','22023');
  PERFORM t.expect_err('SELECT public.core10_owner_inbox_v1(NULL,-1)','22023');
  PERFORM t.expect_err('SELECT public.core10_owner_inbox_v1(NULL,41)','22023');
  PERFORM t.expect_err('SELECT public.core10_owner_inbox_v1(NULL,2147483647)','22023');
  PERFORM t.expect_err('SELECT public.core10_owner_inbox_v1(NULL,-2147483648)','22023');
  PERFORM t.expect_err('SELECT public.core10_owner_inbox_v1(3,0)','22023');
  -- out-of-int4 limit cannot reach the function: argument cast fails first
  PERFORM t.expect_err('SELECT public.core10_owner_inbox_v1(NULL,2147483648)','42883');
  RAISE NOTICE 'PASS limit: NULL->40, 1 and 40 ok, 0/-1/41/int4 extremes -> 22023';
END $test$;

-- ------------------------------------------------------------ 5. business id edge cases
DO $test$
DECLARE d jsonb;
BEGIN
  PERFORM t.expect_err('SELECT public.core10_owner_inbox_v1(0,40)','22023');
  PERFORM t.expect_err('SELECT public.core10_owner_inbox_v1(-1,40)','22023');
  PERFORM t.expect_err('SELECT public.core10_owner_inbox_v1(-9223372036854775808,40)','22023');
  PERFORM t.expect_err('SELECT public.core10_owner_inbox_v1(9223372036854775807,40)','22023');
  PERFORM t.expect_err('SELECT public.core10_owner_inbox_v1(9007199254740992,40)','22023'); -- JS unsafe integer
  PERFORM t.expect_err('SELECT public.core10_owner_inbox_v1(999,40)','22023');             -- nonexistent
  PERFORM t.expect_err('SELECT public.core10_owner_inbox_v1(1,40)','22023');               -- group
  PERFORM t.expect_err('SELECT public.core10_owner_inbox_v1(2,40)','22023');               -- legal_entity
  PERFORM t.expect_err('SELECT public.core10_owner_inbox_v1(4,40)','22023');               -- legal_entity
  PERFORM t.expect_err('SELECT public.core10_owner_inbox_v1(8,40)','22023');               -- branch of active business
  PERFORM t.expect_err('SELECT public.core10_owner_inbox_v1(6,40)','22023');               -- inactive business
  PERFORM t.expect_err('SELECT public.core10_owner_inbox_v1(7,40)','22023');               -- planned business
  PERFORM t.expect_err('SELECT public.core10_owner_inbox_v1(50,40)','22023');              -- cyclic branch
  -- out-of-bigint literal cannot be typed as bigint -> numeric -> no matching function
  PERFORM t.expect_err('SELECT public.core10_owner_inbox_v1(9223372036854775808,40)','42883');
  -- a valid business with zero pending items returns an empty array, not NULL/error
  d :=public.core10_owner_inbox_v1(60,40);
  IF d->'items' <> '[]'::jsonb OR (d->>'business_id')::int <> 60 THEN RAISE EXCEPTION 'FAIL empty business: %', d; END IF;
  RAISE NOTICE 'PASS business id: NULL rollup; 0/neg/huge/nonexistent/non-business/inactive/planned -> 22023; empty -> []';
END $test$;

-- ------------------------------------------------------------ 6. non-owner identities (every bad actor, every arg shape)
DO $test$
DECLARE u text; a text;
BEGIN
  FOREACH u IN ARRAY ARRAY[
     '00000000-0000-4000-8000-000000000002',   -- active staff/manager
     '00000000-0000-4000-8000-000000000003',   -- owner role but profile disabled
     '00000000-0000-4000-8000-000000000004',   -- owner role but profile pending
     '00000000-0000-4000-8000-000000000005',   -- active profile, no roles
     '00000000-0000-4000-8000-0000000000ff',   -- uid with no profile at all
     ''] LOOP                                  -- no uid
    PERFORM t.as_user(u);
    FOREACH a IN ARRAY ARRAY['NULL,40','3,40','NULL,NULL','0,0','999,-5','9223372036854775807,41'] LOOP
      -- authorization is decided BEFORE argument validation: no oracle for non-owners
      PERFORM t.expect_err('SELECT public.core10_owner_inbox_v1('||a||')','42501');
    END LOOP;
  END LOOP;
  PERFORM t.as_user('00000000-0000-4000-8000-000000000001');
  RAISE NOTICE 'PASS staff/disabled-owner/pending-owner/no-role/unknown/no-uid denied for all argument shapes (42501 before 22023)';
END $test$;

-- owner identified through the JSON claims form (request.jwt.claims), not claim.sub
SELECT t.as_user('');
SELECT set_config('request.jwt.claims','{"role":"authenticated","sub":"00000000-0000-4000-8000-000000000006"}',false);
DO $test$
BEGIN
  IF array_length(t.ids(public.core10_owner_inbox_v1(NULL,40)),1) <> 13 THEN RAISE EXCEPTION 'FAIL JSON-claims owner'; END IF;
  RAISE NOTICE 'PASS owner via request.jwt.claims JSON form';
END $test$;
SELECT set_config('request.jwt.claims','',false);
SELECT t.as_user('00000000-0000-4000-8000-000000000001');

-- the definer reads RLS tables the caller cannot: direct reads are empty, RPC is not
DO $test$
BEGIN
  IF (SELECT count(*) FROM public.entries) <> 0 OR (SELECT count(*) FROM public.org_units) <> 0 THEN
    RAISE EXCEPTION 'FAIL fixture: authenticated can read RLS tables directly';
  END IF;
  IF array_length(t.ids(public.core10_owner_inbox_v1(NULL,40)),1) <> 13 THEN RAISE EXCEPTION 'FAIL definer bypass'; END IF;
  PERFORM t.expect_err('SELECT public._business_of_loc123(1)','42501');
  PERFORM t.expect_err('SELECT public._business_of_unit123(3)','42501');
  RAISE NOTICE 'PASS RLS tables unreadable directly; RPC (definer) works; helpers not callable by authenticated';
END $test$;
RESET ROLE;

-- search_path hijack: shadow schema with a fake active business 999
CREATE SCHEMA evil;
CREATE TABLE evil.org_units (LIKE public.org_units INCLUDING ALL);
INSERT INTO evil.org_units(id,parent_id,kind,code,status) OVERRIDING SYSTEM VALUE VALUES (999,1,'business','FAKE','active');
CREATE TABLE evil.profiles (LIKE public.profiles INCLUDING ALL);
INSERT INTO evil.profiles VALUES ('00000000-0000-4000-8000-000000000002','active',now());
GRANT USAGE ON SCHEMA evil TO authenticated;
GRANT SELECT ON ALL TABLES IN SCHEMA evil TO authenticated;
SET ROLE authenticated;
SELECT t.as_user('00000000-0000-4000-8000-000000000001');
SET search_path = evil, public;
SELECT t.expect_err('SELECT public.core10_owner_inbox_v1(999,40)','22023');
SELECT t.as_user('00000000-0000-4000-8000-000000000002');
SELECT t.expect_err('SELECT public.core10_owner_inbox_v1(NULL,40)','42501');   -- fake profile table must not elevate staff
RESET search_path;
RESET ROLE;
DO $test$ BEGIN RAISE NOTICE 'PASS search_path hijack (shadow org_units/profiles) has no effect'; END $test$;

-- ------------------------------------------------------------ 7. 8-way UNION load test
-- Real index shapes from live. Two tiers, loaded by t.load(base, entries, per_table):
--   A) realistic backlog (~4k pending rows in total): HARD assertion, < 4 s.
--   B) stress (~23k pending rows): informational WARNING above 5 s, never a failure.
-- Finding: the org helpers are SECURITY DEFINER SQL functions (not inlinable) and
-- the planner evaluates _business_of_loc123() ~4x per candidate row (two range
-- quals, the join filter and the select list), so cost grows ~linearly with the
-- pending backlog (not with table size: the status filter runs first).
CREATE FUNCTION t.load(base int, n_entries int, n_other int) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
  INSERT INTO public.entries(form_code,location_id,serial,entry_date,created_by,status,created_at)
  SELECT 'B'||base,(ARRAY[1,2,3,4,5,6,7,9,101])[1+g%9],g,'2026-01-01','00000000-0000-4000-8000-000000000002',
         CASE WHEN g%34=0 THEN 'submitted' ELSE (ARRAY['draft','approved','rejected'])[1+g%3] END,
         timestamptz '2026-01-01' + (g||' seconds')::interval
  FROM generate_series(1,n_entries) g;
  INSERT INTO public.release_requests(entry_id,flag_code,reason,requested_by,requested_at)
  SELECT id,'B'||base,'r','00000000-0000-4000-8000-000000000002',created_at FROM public.entries WHERE form_code='B'||base AND status='submitted' LIMIT n_other;
  INSERT INTO public.entry_change_requests(entry_id,base_rev,requested_by,reason,patch,created_at)
  SELECT id,1,'00000000-0000-4000-8000-000000000002','r','{}',created_at FROM public.entries WHERE form_code='B'||base AND status='submitted' LIMIT n_other;
  INSERT INTO public.exceptions(form_code,location_id,entry_date,flag_code,level,created_at)
  SELECT 'B',(ARRAY[1,101,104])[1+g%3],'2026-01-01','X','red',timestamptz '2026-01-01'+(g||' seconds')::interval FROM generate_series(1,n_other) g;
  INSERT INTO public.emergency_requests(grant_code,requested_by,reason,location_id,created_at)
  SELECT 'G','00000000-0000-4000-8000-000000000002','r',(ARRAY[1,101,NULL,105])[1+g%4],timestamptz '2026-01-01'+(g||' seconds')::interval FROM generate_series(1,n_other) g;
  INSERT INTO public.pay_requests(kind,location_id,requested_by,amount,reason,needed_by,created_at)
  SELECT 'salary',(ARRAY[1,101,NULL,103])[1+g%4],'00000000-0000-4000-8000-000000000002',1,'abc','2026-02-01',timestamptz '2026-01-01'+(g||' seconds')::interval FROM generate_series(1,n_other) g;
  INSERT INTO public.wastage_requests(item_id,location_id,qty,reason_code,requested_by,requested_at)
  SELECT gen_random_uuid(),(ARRAY[1,101,102])[1+g%3],1,'r','00000000-0000-4000-8000-000000000002',timestamptz '2026-01-01'+(g||' seconds')::interval FROM generate_series(1,n_other) g;
  INSERT INTO public.item_changes(patch,requested_by,requested_at,org_unit_id)
  SELECT '{}','00000000-0000-4000-8000-000000000002',timestamptz '2026-01-01'+(g||' seconds')::interval,(ARRAY[3,8,9,50,NULL])[1+g%5] FROM generate_series(1,n_other) g;
END $f$;
CREATE FUNCTION t.timed(label text, ceiling_ms numeric, hard boolean) RETURNS void LANGUAGE plpgsql AS $f$
DECLARE t0 timestamptz; ms numeric; d jsonb; n int;
BEGIN
  FOREACH n IN ARRAY ARRAY[0,3,5] LOOP
    t0 := clock_timestamp();
    d := public.core10_owner_inbox_v1(CASE WHEN n=0 THEN NULL ELSE n END,40);
    ms := extract(epoch FROM clock_timestamp()-t0)*1000;
    RAISE NOTICE 'timing [%] business=% items=% elapsed_ms=%', label, COALESCE(NULLIF(n,0)::text,'rollup'), jsonb_array_length(d->'items'), round(ms);
    IF jsonb_array_length(d->'items') <> 40 THEN RAISE EXCEPTION 'FAIL load result not capped at 40'; END IF;
    IF n>0 AND EXISTS (SELECT 1 FROM jsonb_array_elements(d->'items') e WHERE (e->>'business_id')::int<>n) THEN
      RAISE EXCEPTION 'FAIL cross-business row under load';
    END IF;
    IF ms > ceiling_ms THEN
      IF hard THEN RAISE EXCEPTION 'FAIL [%] 8-way UNION % ms exceeds % ms (business %)', label, round(ms), ceiling_ms, n;
      ELSE RAISE WARNING 'KNOWN ISSUE [%] 8-way UNION % ms exceeds % ms (business %): helper evaluated per row', label, round(ms), ceiling_ms, n;
      END IF;
    END IF;
  END LOOP;
END $f$;

-- explicit ids were used above; move identity sequences past them
SELECT setval(pg_get_serial_sequence('public.'||x,'id'),1000) FROM unnest(ARRAY['release_requests',
  'entry_change_requests','exceptions','emergency_requests','pay_requests','item_changes']) x;
SELECT t.load(1,20000,500);
ANALYZE;
SET ROLE authenticated;
SELECT t.as_user('00000000-0000-4000-8000-000000000001');
SELECT t.timed('A realistic backlog',4000,true);
RESET ROLE;
DO $test$ BEGIN RAISE NOTICE 'PASS realistic backlog (~4k pending rows) under 4s'; END $test$;

SELECT t.load(2,100000,5000);
ANALYZE;
SET ROLE authenticated;
SELECT t.as_user('00000000-0000-4000-8000-000000000001');
SELECT t.timed('B stress 23k pending',5000,false);
RESET ROLE;

-- Informational plan with data present (ANALYZE; CI log only, no assertion).
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON)
WITH candidates AS (
  SELECT 'entry:'||e.id::text AS id, e.created_at AS created_at, public._business_of_loc123(e.location_id) AS business_id FROM public.entries e WHERE e.status='submitted'
  UNION ALL SELECT 'release:'||r.id::text, r.requested_at, public._business_of_loc123(e.location_id) FROM public.release_requests r JOIN public.entries e ON e.id=r.entry_id WHERE r.status='pending'
  UNION ALL SELECT 'entry_change:'||r.id::text, r.created_at, public._business_of_loc123(e.location_id) FROM public.entry_change_requests r JOIN public.entries e ON e.id=r.entry_id WHERE r.status='pending'
  UNION ALL SELECT 'exception:'||x.id::text, x.created_at, public._business_of_loc123(x.location_id) FROM public.exceptions x LEFT JOIN public.entries e ON e.id=x.entry_id WHERE x.status='open' AND (x.entry_id IS NULL OR (e.id IS NOT NULL AND public._business_of_loc123(x.location_id)=public._business_of_loc123(e.location_id)))
  UNION ALL SELECT 'emergency:'||r.id::text, r.created_at, public._business_of_loc123(r.location_id) FROM public.emergency_requests r WHERE r.status='pending'
  UNION ALL SELECT 'pay:'||r.id::text, r.created_at, public._business_of_loc123(r.location_id) FROM public.pay_requests r WHERE r.status='received'
  UNION ALL SELECT 'wastage:'||r.id::text, r.requested_at, public._business_of_loc123(r.location_id) FROM public.wastage_requests r WHERE r.status='pending'
  UNION ALL SELECT 'item_change:'||r.id::text, r.requested_at, public._business_of_unit123(r.org_unit_id) FROM public.item_changes r WHERE r.status='pending'
), scoped AS (
  SELECT c.* FROM candidates c JOIN public.org_units b ON b.id=c.business_id AND b.kind='business' AND b.status='active'
  WHERE c.business_id BETWEEN 1 AND 9007199254740991
)
SELECT * FROM scoped ORDER BY created_at DESC,id ASC LIMIT 40;
