\set ON_ERROR_STOP on
-- PACK-02 S4: D030 design-target shape (100 showroom + 100 factory + 100 godown
-- + 3 project = 303 sites) through the canonical setup engine. Disposable local
-- PostgreSQL timing only: NOT a production capacity or hosted performance claim.
SET ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
DO $t$
DECLARE sites jsonb; r jsonb; r2 jsonb; w jsonb; rep jsonb; b bigint; t0 timestamptz; ms numeric; budget numeric:=20000;
BEGIN
 SELECT jsonb_agg(jsonb_build_object('kind',k,'label','DEMO-'||upper(k)||'-'||lpad(i::text,3,'0')) ORDER BY k,i) INTO sites
  FROM (SELECT k,i FROM unnest(ARRAY['showroom','factory','godown']) k, generate_series(1,100) i
        UNION ALL SELECT 'project',i FROM generate_series(1,3) i) x;
 IF jsonb_array_length(sites)<>303 THEN RAISE EXCEPTION 'fixture'; END IF;
 t0:=clock_timestamp();
 r:=c10_demo.pack02_setup_business_v1(11,'pack02-scale','general_manufacturing','Scale Demo','advanced',sites,'pack02-scale-0001','#225577');
 ms:=extract(epoch FROM clock_timestamp()-t0)*1000; RAISE NOTICE 'setup+readback 303 sites: % ms',round(ms);
 IF ms>budget THEN RAISE EXCEPTION 'setup too slow % ms',ms; END IF;
 b:=(r->'receipt'->>'business_id')::bigint;
 IF r->'readback'->>'integrity_ok'<>'true' OR jsonb_array_length(r->'readback'->'sites')<>303 THEN RAISE EXCEPTION 'scale readback %',r->'readback'->'checks'; END IF;
 t0:=clock_timestamp();
 r2:=c10_demo.pack02_setup_business_v1(11,'pack02-scale','general_manufacturing','Scale Demo','advanced',sites,'pack02-scale-0001','#225577');
 ms:=extract(epoch FROM clock_timestamp()-t0)*1000; RAISE NOTICE 'replay: % ms',round(ms);
 IF r2<>r THEN RAISE EXCEPTION 'scale replay differs'; END IF;
 IF (SELECT count(*) FROM c10_demo.sites WHERE business_id=b)<>303 OR (SELECT count(*) FROM c10_demo.stock_locations WHERE business_id=b)<>303
  THEN RAISE EXCEPTION 'scale duplicate/orphan rows'; END IF;
 IF (SELECT count(*) FROM c10_demo.sites WHERE business_id=b AND kind='factory')<>100 THEN RAISE EXCEPTION 'kind distribution'; END IF;
 t0:=clock_timestamp();
 w:=c10_demo.pack02_workspace_v1('business_owner',b);
 ms:=extract(epoch FROM clock_timestamp()-t0)*1000; RAISE NOTICE 'business_owner workspace: % ms',round(ms);
 IF jsonb_array_length(w->'sites')<>303 OR ms>budget THEN RAISE EXCEPTION 'scale workspace % ms',ms; END IF;
 t0:=clock_timestamp();
 rep:=c10_demo.pack02_business_report_v1(b);
 ms:=extract(epoch FROM clock_timestamp()-t0)*1000; RAISE NOTICE 'business report: % ms',round(ms);
 IF (rep->'totals'->>'sites')::int<>303 OR ms>budget THEN RAISE EXCEPTION 'scale report'; END IF;
 t0:=clock_timestamp();
 rep:=c10_demo.pack02_owner_report_v1();
 ms:=extract(epoch FROM clock_timestamp()-t0)*1000; RAISE NOTICE 'owner report: % ms',round(ms);
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(rep->'businesses') x WHERE (x->>'business_id')::bigint=b AND (x->>'sites')::int=303 AND (x->>'locations')::int=303)
  OR ms>budget THEN RAISE EXCEPTION 'owner report scale row'; END IF;
 -- One staff grant among 303 sites: staff sees exactly that one site.
 PERFORM c10_demo.build01_set_access_v1(b,'44444444-4444-4444-8444-444444444444','site_grant.grant',NULL,
  (SELECT id FROM c10_demo.sites WHERE business_id=b AND label='DEMO-GODOWN-057'),ARRAY['stock.read'],'{}',NULL,'pack02-scale-grant-01',NULL);
 PERFORM set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',false);
 t0:=clock_timestamp();
 w:=c10_demo.pack02_workspace_v1('staff',b);
 ms:=extract(epoch FROM clock_timestamp()-t0)*1000; RAISE NOTICE 'staff workspace (1 of 303): % ms',round(ms);
 IF jsonb_array_length(w->'sites')<>1 OR w->'sites'->0->>'label'<>'DEMO-GODOWN-057' OR w->'nav'<>'["staff.home","stock.view","staff.reports"]'::jsonb OR ms>budget
  THEN RAISE EXCEPTION 'scale staff isolation %',w; END IF;
 IF (c10_demo.pack02_business_report_v1(b)->'totals'->>'sites')::int<>1 THEN RAISE EXCEPTION 'scale staff report scope'; END IF;
END $t$;
RESET ROLE;
SELECT 'PASS PACK-02 scale-e2e (303 sites, disposable timing only)' AS result;
