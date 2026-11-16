-- B-020/0111 disposable PostgreSQL 17: 0..5 route versions, replay and isolation.
\set ON_ERROR_STOP on
BEGIN;
INSERT INTO core10.tenants(id,slug) VALUES (99701,'np01-0111-a'),(99702,'np01-0111-b');
INSERT INTO core10.legal_entities(id,tenant_id,label)
 VALUES(99711,99701,'NP01 0111 A'),(99712,99702,'NP01 0111 B');
INSERT INTO core10.businesses(id,tenant_id,legal_entity_id,slug,template_code,request_key)
 VALUES(99721,99701,99711,'np01-0111-a','sweets_bakery','np01_0111_business_a'),
       (99722,99702,99712,'np01-0111-b','sweets_bakery','np01_0111_business_b');
INSERT INTO core10.tenant_members(tenant_id,user_id,role) VALUES
 (99701,'99711111-1111-4111-8111-111111111111','tenant_owner'),
 (99702,'99799999-9999-4999-8999-999999999999','tenant_owner');
INSERT INTO core10.business_members(tenant_id,business_id,user_id,role,approval_actions) VALUES
 (99701,99721,'99722222-2222-4222-8222-222222222222','business_owner',ARRAY['approval.decide']),
 (99701,99721,'99733333-3333-4333-8333-333333333333','manager',ARRAY['approval.submit']),
 (99701,99721,'99744444-4444-4444-8444-444444444444','manager',ARRAY['approval.decide']),
 (99701,99721,'99755555-5555-4555-8555-555555555555','manager',ARRAY['approval.decide']),
 (99701,99721,'99766666-6666-4666-8666-666666666666','manager',ARRAY['approval.decide']);
SET LOCAL ROLE authenticated;
DO $test$
DECLARE n integer; p bigint; q bigint; a text[]; ctl jsonb; q_status text;
 owner_id text:='99711111-1111-4111-8111-111111111111';
 maker_id text:='99733333-3333-4333-8333-333333333333';
BEGIN
 FOR n IN 0..5 LOOP
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',owner_id)::text,true);
  PERFORM set_config('request.jwt.claim.sub',owner_id,true);
  ctl:=core10.control_set_v1(99721,NULL,'gov002.review',true,n::smallint,
    '{}'::jsonb,NULL,false,n,'Owner sets explicit stage count',
    'np01_0111_ctl_'||n);
  IF (ctl->>'version')::integer<>n+1 THEN
   RAISE EXCEPTION 'NP01_0111_CONTROL_VERSION:%',n; END IF;
  a:=CASE n
    WHEN 0 THEN ARRAY[]::text[]
    WHEN 1 THEN ARRAY['tenant_owner']::text[]
    WHEN 2 THEN ARRAY['business_owner','tenant_owner']::text[]
    WHEN 3 THEN ARRAY['business_owner','manager','tenant_owner']::text[]
    WHEN 4 THEN ARRAY['business_owner','manager','manager','tenant_owner']::text[]
    ELSE ARRAY['business_owner','manager','manager','manager','tenant_owner']::text[] END;
  p:=core10.publish_approval_policy_v1(99721,'inventory','stage'||n,120,
    'np01_0111_policy_'||n);
  IF n=2 THEN
   BEGIN
    PERFORM core10.configure_approval_route_v1(p,
      ARRAY['business_owner','manager','tenant_owner']::text[],'np01_0111_bad_route');
    RAISE EXCEPTION 'NP01_0111_MISMATCH_ACCEPTED';
   EXCEPTION WHEN OTHERS THEN
    IF SQLERRM<>'CONTROL_STAGE_MISMATCH' THEN RAISE; END IF;
   END;
  END IF;
  PERFORM core10.configure_approval_route_v1(p,a,'np01_0111_route_'||n);
  IF core10.configure_approval_route_v1(p,a,'np01_0111_route_'||n)<>p
  THEN RAISE EXCEPTION 'NP01_0111_ROUTE_REPLAY_CHANGED'; END IF;
  PERFORM set_config('np01.0111.p'||n,p::text,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',maker_id)::text,true);
  PERFORM set_config('request.jwt.claim.sub',maker_id,true);
  q:=core10.submit_typed_approval_v1(99721,'inventory','stage'||n,'src-'||n,1,
      jsonb_build_object('quantity',n+1),'np01_0111_submit_'||n);
  PERFORM set_config('np01.0111.q'||n,q::text,true);
  IF core10.submit_typed_approval_v1(99721,'inventory','stage'||n,'src-'||n,1,
      jsonb_build_object('quantity',n+1),'np01_0111_submit_'||n)<>q
  THEN RAISE EXCEPTION 'NP01_0111_SUBMIT_REPLAY_CHANGED:%',n; END IF;
  SELECT status INTO q_status FROM core10.approval_requests WHERE id=q;
  IF (SELECT route_stages_pinned_v1 FROM core10.approval_requests WHERE id=q)<>n
    OR (SELECT route_control_version_v1 FROM core10.approval_requests WHERE id=q)<>n+1
    OR q_status<>CASE WHEN n=0 THEN 'approved' ELSE 'pending' END
  THEN RAISE EXCEPTION 'NP01_0111_PIN_OR_STATUS:%',n; END IF;
  IF n=0 AND (SELECT count(*) FROM core10.approval_events
     WHERE request_id=q AND action='approve')<>1
  THEN RAISE EXCEPTION 'NP01_0111_ZERO_STAGE_RECEIPT'; END IF;
 END LOOP;
END; $test$;
-- Deny even same-key replays when the review switch is off.
SELECT set_config('request.jwt.claims','{"sub":"99711111-1111-4111-8111-111111111111"}',true);
SELECT set_config('request.jwt.claim.sub','99711111-1111-4111-8111-111111111111',true);
SELECT core10.control_set_v1(99721,NULL,'gov002.review',false,5::smallint,
 '{}'::jsonb,NULL,false,6,'Stop new review commands','np01_0111_control_off');
DO $test$
BEGIN
 BEGIN
  PERFORM core10.configure_approval_route_v1(current_setting('np01.0111.p5')::bigint,
    ARRAY['business_owner','manager','manager','manager','tenant_owner']::text[],
    'np01_0111_route_5');
  RAISE EXCEPTION 'NP01_0111_DISABLED_ROUTE_REPLAY';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM NOT LIKE 'CONTROL_DISABLED:gov002.review%' THEN RAISE; END IF;
 END;
END; $test$;
SELECT set_config('request.jwt.claims','{"sub":"99733333-3333-4333-8333-333333333333"}',true);
SELECT set_config('request.jwt.claim.sub','99733333-3333-4333-8333-333333333333',true);
DO $test$
BEGIN
 BEGIN
  PERFORM core10.submit_typed_approval_v1(99721,'inventory','stage5','src-5',1,
   '{"quantity":6}'::jsonb,'np01_0111_submit_5');
  RAISE EXCEPTION 'NP01_0111_DISABLED_SUBMIT_REPLAY';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM NOT LIKE 'CONTROL_DISABLED:gov002.review%' THEN RAISE; END IF;
 END;
END; $test$;
-- Foreign tenant with forged JWT metadata must fail canonical Auth first.
SELECT set_config('request.jwt.claims',
 '{"sub":"99799999-9999-4999-8999-999999999999","app_metadata":{"role":"tenant_owner"}}',true);
SELECT set_config('request.jwt.claim.sub','99799999-9999-4999-8999-999999999999',true);
DO $test$
BEGIN
 BEGIN
  PERFORM core10.configure_approval_route_v1(current_setting('np01.0111.p5')::bigint,
    ARRAY['business_owner','manager','manager','manager','tenant_owner']::text[],
    'np01_0111_forged_config');
  RAISE EXCEPTION 'NP01_0111_FOREIGN_ROUTE_ALLOWED';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'approval_route_denied' THEN RAISE; END IF;
 END;
END; $test$;
-- Reenable: pre-existing 1..5 requests retain their saved routes.
SELECT set_config('request.jwt.claims','{"sub":"99711111-1111-4111-8111-111111111111"}',true);
SELECT set_config('request.jwt.claim.sub','99711111-1111-4111-8111-111111111111',true);
SELECT core10.control_set_v1(99721,NULL,'gov002.review',true,5::smallint,
 '{}'::jsonb,NULL,false,7,'Resume approved reviews','np01_0111_control_on');
DO $test$
DECLARE n integer; q bigint; p bigint; evt bigint; a text[];
 checker text; k integer;
BEGIN
 -- Single stage requires a distinct tenant owner; maker cannot self-check.
 PERFORM set_config('request.jwt.claims',
   '{"sub":"99733333-3333-4333-8333-333333333333"}',true);
 PERFORM set_config('request.jwt.claim.sub','99733333-3333-4333-8333-333333333333',true);
 BEGIN
  PERFORM core10.decide_approval(current_setting('np01.0111.q1')::bigint,
    'approve','np01_0111_maker_vote');
  RAISE EXCEPTION 'NP01_0111_MAKER_APPROVED';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM<>'approval_not_authorized' THEN RAISE; END IF;
 END;
 FOR n IN 1..5 LOOP
  q:=current_setting('np01.0111.q'||n)::bigint;
  IF n>=2 THEN
   checker:='99722222-2222-4222-8222-222222222222';
   PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',checker)::text,true);
   PERFORM set_config('request.jwt.claim.sub',checker,true);
   evt:=core10.decide_approval(q,'approve','np01_0111_vote_'||n||'_1');
   IF core10.decide_approval(q,'approve','np01_0111_vote_'||n||'_1')<>evt
   THEN RAISE EXCEPTION 'NP01_0111_VOTE_REPLAY'; END IF;
   IF (SELECT status FROM core10.approval_requests WHERE id=q)<>'pending'
   THEN RAISE EXCEPTION 'NP01_0111_EARLY_APPROVED'; END IF;
   FOR k IN 2..n-1 LOOP
    checker:=CASE k WHEN 2 THEN '99744444-4444-4444-8444-444444444444'
      WHEN 3 THEN '99755555-5555-4555-8555-555555555555'
      ELSE '99766666-6666-4666-8666-666666666666' END;
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',checker)::text,true);
    PERFORM set_config('request.jwt.claim.sub',checker,true);
    PERFORM core10.decide_approval(q,'approve','np01_0111_vote_'||n||'_'||k);
   END LOOP;
  END IF;
  checker:='99711111-1111-4111-8111-111111111111';
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',checker)::text,true);
  PERFORM set_config('request.jwt.claim.sub',checker,true);
  PERFORM core10.decide_approval(q,'approve','np01_0111_vote_'||n||'_'||n);
  IF (SELECT status FROM core10.approval_requests WHERE id=q)<>'approved'
    OR (SELECT count(*) FROM core10.approval_stage_receipts_v1 WHERE request_id=q)<>n
  THEN RAISE EXCEPTION 'NP01_0111_FINAL_REVIEW_STAGE:%',n; END IF;
 END LOOP;
 IF (core10.verify_canonical_audit_v1(99721)->>'ok')<>'true'
 THEN RAISE EXCEPTION 'NP01_0111_CANONICAL_AUDIT'; END IF;
END; $test$;
RESET ROLE;
DO $test$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM core10.control_rpc_map_v1 WHERE
  rpc_name='configure_approval_route_v1' AND status='enforced'
  AND test_ref='tests/migrations/np01-control-route-stages-e2e.sql')
 THEN RAISE EXCEPTION 'NP01_0111_REGISTRY_UNPROVEN'; END IF;
 RAISE NOTICE 'NP01_0111_PG17_ROUTE_0_TO_5_AND_PINNING_OK';
END; $test$;
ROLLBACK;
