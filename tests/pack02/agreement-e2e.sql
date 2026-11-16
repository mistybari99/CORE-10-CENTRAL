\set ON_ERROR_STOP on
-- PACK-01 + PACK-02 agreement: what a PACK-02 workspace/report PROJECTS must
-- equal what the canonical stock authorization (A048 via Build01 can_site)
-- ENFORCES, for the same actor and site. Synthetic claims; not GoTrue.
CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE sql AS
 $$ SELECT set_config('request.jwt.claim.sub',p::text,false) $$;
-- A048's authorizer is internal (not granted to authenticated). This definer
-- wrapper only exposes its boolean to the test; the signed-claim GUC is unchanged.
CREATE FUNCTION pg_temp.enforced(t bigint,b bigint,l bigint,a text) RETURNS boolean
LANGUAGE sql SECURITY DEFINER AS $$ SELECT core10.inventory_action_authorized_v1(t,b,l,a) $$;
-- Compare projection vs enforcement for every site/location of a business.
CREATE FUNCTION pg_temp.agree(p_mode text,p_business bigint) RETURNS integer LANGUAGE plpgsql AS $$
DECLARE w jsonb; l record; shown text[]; n integer:=0; a text;
BEGIN
 BEGIN w:=core10.pack02_workspace_v1(p_mode,p_business);
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'PACK02_WORKSPACE_DENIED' THEN RAISE; END IF; w:='{"sites":[]}'::jsonb; END;
 FOR l IN SELECT x.id,x.site_id,x.tenant_id FROM core10.stock_locations_for_agreement x WHERE x.business_id=p_business LOOP
  SELECT COALESCE(ARRAY(SELECT jsonb_array_elements_text(s->'allowed_actions')),'{}') INTO shown
   FROM jsonb_array_elements(w->'sites') s WHERE (s->>'id')::bigint=l.site_id;
  shown:=COALESCE(shown,'{}');
  FOREACH a IN ARRAY ARRAY['stock.read','stock.post'] LOOP
   n:=n+1;
   -- A projected action must be enforceable; never show more than enforcement allows.
   IF a=ANY(shown) AND NOT pg_temp.enforced(l.tenant_id,p_business,l.id,a) THEN
    RAISE EXCEPTION 'PROJECTION_EXCEEDS_ENFORCEMENT mode=% site=% action=%',p_mode,l.site_id,a; END IF;
  END LOOP;
 END LOOP;
 RETURN n;
END $$;
-- Location list readable by the test under the authenticated role.
CREATE VIEW core10.stock_locations_for_agreement AS SELECT id,site_id,tenant_id,business_id FROM core10.stock_locations;
GRANT SELECT ON core10.stock_locations_for_agreement TO authenticated;
-- PACK-01's A048 adapter delegates to canonical can_site. The pre-PACK-01
-- baseline A048 uses its own older rule (can_manage OR raw grant), which is
-- stricter for managers and ignores owner DENY; the full matrix is only
-- meaningful once the adapter is present.
CREATE TEMP TABLE adapter AS SELECT p.prosrc !~ 'can_manage' AS pack01 FROM pg_proc p
 WHERE p.oid='core10.inventory_action_authorized_v1(bigint,bigint,bigint,text)'::regprocedure;
GRANT SELECT ON adapter TO authenticated;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA pg_temp TO authenticated;
SET ROLE authenticated;

-- Tenant owner: deny stock.post to staff 4444 on 1001; deny stock.read to business owner 2222 on 1002.
SELECT pg_temp.as_user('11111111-1111-4111-8111-111111111111');
SELECT core10.build01_set_access_v1(101,'44444444-4444-4444-8444-444444444444','site_grant.grant',NULL,1001,
 ARRAY['stock.read','stock.post'],ARRAY['stock.post'],NULL,'p2agree-staff-deny-01',NULL) IS NOT NULL;
SELECT core10.build01_set_access_v1(101,'22222222-2222-4222-8222-222222222222','site_grant.grant',NULL,1002,
 '{}',ARRAY['stock.read'],NULL,'p2agree-owner-deny-01',NULL) IS NOT NULL;

DO $t$
DECLARE u uuid; w jsonb; r jsonb; pack01 boolean:=(SELECT a.pack01 FROM adapter a); checked integer:=0;
BEGIN
 IF pack01 THEN
 FOREACH u IN ARRAY ARRAY['11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','33333333-3333-4333-8333-333333333333',
  '44444444-4444-4444-8444-444444444444','55555555-5555-4555-8555-555555555555','66666666-6666-4666-8666-666666666666',
  '77777777-7777-4777-8777-777777777777','88888888-8888-4888-8888-888888888888','99999999-9999-4999-8999-999999999999']::uuid[] LOOP
  PERFORM pg_temp.as_user(u);
  checked:=checked+pg_temp.agree('staff',101)+pg_temp.agree('business_owner',101)+pg_temp.agree('staff',201)+pg_temp.agree('business_owner',201);
 END LOOP;
 IF checked<100 THEN RAISE EXCEPTION 'agreement matrix too small %',checked; END IF;
 ELSE RAISE NOTICE 'PACK-01 A048 adapter ABSENT: projection-vs-enforcement matrix SKIPPED on this baseline'; END IF;
 -- Staff: post denied in projection AND in enforcement.
 PERFORM pg_temp.as_user('44444444-4444-4444-8444-444444444444');
 w:=core10.pack02_workspace_v1('staff',101);
 IF (w->'nav') ? 'stock.post' OR (pack01 AND pg_temp.enforced(1,101,5001,'stock.post')) THEN RAISE EXCEPTION 'staff post deny disagreement'; END IF;
 IF NOT pg_temp.enforced(1,101,5001,'stock.read') THEN RAISE EXCEPTION 'staff read lost'; END IF;
 -- Business owner with explicit read DENY on 1002: PACK-02 withholds actions and stock figures.
 PERFORM pg_temp.as_user('22222222-2222-4222-8222-222222222222');
 w:=core10.pack02_workspace_v1('business_owner',101);
 IF (SELECT s->'allowed_actions' FROM jsonb_array_elements(w->'sites') s WHERE (s->>'id')::bigint=1002)<>'[]'::jsonb THEN RAISE EXCEPTION 'owner deny not projected'; END IF;
 r:=core10.pack02_business_report_v1(101);
 IF (SELECT (s->>'stock_read')::boolean OR s->'movement_count'<>'null'::jsonb FROM jsonb_array_elements(r->'sites') s WHERE (s->>'site_id')::bigint=1002)
  THEN RAISE EXCEPTION 'report shows stock figures for read-denied site'; END IF;
 IF (SELECT NOT (s->>'stock_read')::boolean OR s->'movement_count'='null'::jsonb FROM jsonb_array_elements(r->'sites') s WHERE (s->>'site_id')::bigint=1001)
  THEN RAISE EXCEPTION 'report withheld an allowed site'; END IF;
 -- With PACK-01's A048 adapter the same DENY is ENFORCED for the owner; on the
 -- pre-PACK-01 baseline A048 still short-circuits on can_manage (PACK-01's gap).
 IF pack01 AND pg_temp.enforced(1,101,5002,'stock.read') THEN RAISE EXCEPTION 'PACK-01 adapter did not enforce owner site deny'; END IF;
 RAISE NOTICE 'agreement checks=% pack01_adapter_present=%',checked,pack01;
END $t$;
RESET ROLE;
SELECT 'PASS PACK-02 agreement-e2e' AS result;
