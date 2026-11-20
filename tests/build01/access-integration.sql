\set ON_ERROR_STOP on
-- Real PostgreSQL effects under synthetic claims. Real GoTrue/API tests run separately.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
DO $suite$
DECLARE c jsonb; r jsonb; replay jsonb; b bigint; site bigint; ver bigint; event bigint; original_count bigint;
BEGIN
 c:=core10.build01_context_v1();
 IF c->>'actor_uid'<>'11111111-1111-4111-8111-111111111111' OR jsonb_array_length(c->'businesses')<>2
  OR jsonb_array_length(c->'legal_entities')<>1 THEN RAISE EXCEPTION 'owner context leaked or omitted scope'; END IF;
 SELECT count(*) INTO original_count FROM core10.stock_movements;
 r:=core10.build01_setup_v1(11,'build01-connected','food_manufacturing','Build01 synthetic business','advanced',
  '[{"kind":"showroom","label":"Counter"},{"kind":"factory","label":"Factory"}]','build01-setup-01','#334455');
 b:=(r->>'business_id')::bigint;
 IF r->>'status'<>'draft' OR r->>'production_certified'<>'false' THEN RAISE EXCEPTION 'setup falsely activated business'; END IF;
 replay:=core10.build01_setup_v1(11,'build01-connected','food_manufacturing','Build01 synthetic business','advanced',
  '[{"kind":"showroom","label":"Counter"},{"kind":"factory","label":"Factory"}]','build01-setup-01','#334455');
 IF replay<>r THEN RAISE EXCEPTION 'setup duplicate receipt'; END IF;
 IF (SELECT count(*) FROM core10.sites WHERE business_id=b)<>2 THEN RAISE EXCEPTION 'setup duplicate sites'; END IF;
 r:=core10.build01_site_v1(b,'warehouse','Storage','build01-site-01');
 site:=(r->>'site_id')::bigint;
 IF core10.build01_site_v1(b,'warehouse','Storage','build01-site-01')<>r THEN RAISE EXCEPTION 'site duplicate receipt'; END IF;
 IF (SELECT count(*) FROM core10.stock_locations WHERE business_id=b)<>3 THEN RAISE EXCEPTION 'canonical stock locations missing'; END IF;
 BEGIN
  PERFORM core10.build01_site_v1(b,'warehouse','Changed','build01-site-01');
  RAISE EXCEPTION 'changed replay accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'BUILD01_REQUEST_CONFLICT' THEN RAISE; END IF; END;
 r:=core10.build01_set_access_v1(b,'44444444-4444-4444-8444-444444444444','site_grant.grant',NULL,site,
  ARRAY['stock.read','stock.post'],'{}',now()+interval '1 day','build01-staff-grant',0);
 ver:=(r->'after_state'->>'version')::bigint;
 IF ver<1 THEN RAISE EXCEPTION 'grant version missing'; END IF;
 IF core10.build01_set_access_v1(b,'44444444-4444-4444-8444-444444444444','site_grant.grant',NULL,site,
  ARRAY['stock.read','stock.post'],'{}',now()+interval '1 day','build01-staff-grant',0)<>r THEN RAISE EXCEPTION 'policy replay changed'; END IF;
 BEGIN
  PERFORM core10.build01_set_access_v1(b,'44444444-4444-4444-8444-444444444444','site_grant.grant',NULL,site,
   ARRAY['stock.read'],'{}',NULL,'build01-staff-grant',0);
  RAISE EXCEPTION 'policy input conflict accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'BUILD01_REQUEST_CONFLICT' THEN RAISE; END IF; END;
 BEGIN
  PERFORM core10.build01_set_access_v1(b,'44444444-4444-4444-8444-444444444444','site_grant.grant',NULL,site,
   ARRAY['stock.read'],'{}',NULL,'build01-stale-01',0);
  RAISE EXCEPTION 'stale policy accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'BUILD01_STALE_ACCESS_VERSION' THEN RAISE; END IF; END;
 PERFORM set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',true);
 IF NOT core10.can_site(1,b,site,'stock.read') OR NOT core10.can_site(1,b,site,'stock.post') THEN RAISE EXCEPTION 'staff effective actions missing'; END IF;
 c:=core10.build01_workspace_v1(b);
 IF c->>'can_manage'<>'false' OR jsonb_array_length(c->'sites')<>1 OR jsonb_array_length(c->'access'->'site_grants')<>1 THEN RAISE EXCEPTION 'staff workspace scope'; END IF;
 IF c->'sites'->0->'allowed_actions'<>'["stock.read","stock.post"]'::jsonb THEN RAISE EXCEPTION 'staff permission projection wrong'; END IF;
 BEGIN
  PERFORM core10.build01_site_v1(b,'warehouse','Forbidden','build01-denied-site');
  RAISE EXCEPTION 'staff created site';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'BUILD01_SITE_DENIED' THEN RAISE; END IF; END;
 PERFORM set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
 r:=core10.build01_set_access_v1(b,'44444444-4444-4444-8444-444444444444','site_grant.grant',NULL,site,
  ARRAY['stock.read','stock.post'],ARRAY['stock.post'],NULL,'build01-explicit-deny',ver);
 ver:=(r->'after_state'->>'version')::bigint;
 PERFORM set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',true);
 IF NOT core10.can_site(1,b,site,'stock.read') OR core10.can_site(1,b,site,'stock.post') THEN RAISE EXCEPTION 'deny failed over explicit allow'; END IF;
 PERFORM set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
 r:=core10.build01_set_access_v1(b,'33333333-3333-4333-8333-333333333333','business_member.grant','manager',NULL,
  '{}','{}',NULL,'build01-manager-01',0);
 r:=core10.build01_set_access_v1(b,'33333333-3333-4333-8333-333333333333','site_grant.grant',NULL,site,
  '{}',ARRAY['stock.post'],NULL,'build01-manager-deny',0);
 PERFORM set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',true);
 IF NOT core10.can_site(1,b,site,'stock.read') OR core10.can_site(1,b,site,'stock.post') THEN RAISE EXCEPTION 'manager inherited rights bypassed deny'; END IF;
 PERFORM set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
 PERFORM core10.build01_set_access_v1(b,'44444444-4444-4444-8444-444444444444','site_grant.revoke',NULL,site,
  '{}','{}',NULL,'build01-staff-revoke',ver);
 PERFORM set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',true);
 IF core10.can_site(1,b,site,'stock.read') OR core10.can_site(1,b,site,'stock.post') THEN RAISE EXCEPTION 'revoked user kept rights'; END IF;
 BEGIN
  PERFORM core10.build01_workspace_v1(b);RAISE EXCEPTION 'revoked workspace leaked';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'BUILD01_BUSINESS_DENIED' THEN RAISE; END IF; END;
 PERFORM set_config('request.jwt.claim.sub','77777777-7777-4777-8777-777777777777',true);
 IF core10.can_site(1,b,site,'stock.read') THEN RAISE EXCEPTION 'foreign tenant effective authority'; END IF;
 BEGIN
  PERFORM core10.build01_workspace_v1(b);RAISE EXCEPTION 'foreign workspace leaked';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'BUILD01_BUSINESS_DENIED' THEN RAISE; END IF; END;
 c:=core10.build01_context_v1();
 IF jsonb_array_length(c->'businesses')<>1 OR c->'businesses'->0->>'id'<>'201' THEN RAISE EXCEPTION 'foreign context leaked'; END IF;
 PERFORM set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
 BEGIN
  PERFORM core10.build01_set_access_v1(b,'11111111-1111-4111-8111-111111111111','business_member.grant','manager',NULL,'{}','{}',NULL,'build01-self',0);
  RAISE EXCEPTION 'self escalation accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'BUILD01_SELF_ACCESS_CHANGE_FORBIDDEN' THEN RAISE; END IF; END;
 BEGIN
  PERFORM core10.build01_set_access_v1(b,'00000000-0000-4000-8000-000000000000','business_member.grant','manager',NULL,'{}','{}',NULL,'build01-unknown',0);
  RAISE EXCEPTION 'unregistered subject accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'BUILD01_SUBJECT_NOT_REGISTERED' THEN RAISE; END IF; END;
 IF (SELECT count(*) FROM core10.stock_movements)<>original_count THEN RAISE EXCEPTION 'setup/access changed stock'; END IF;
 IF (SELECT count(*) FROM core10.access_change_events_v1 WHERE business_id=b AND event_kind='policy.apply')<>5 THEN RAISE EXCEPTION 'policy audit receipt count'; END IF;
END $suite$;
ROLLBACK;

-- Every offered industry works through the connected wrapper in both modes.
-- Draft provisioning is not operational module certification.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
DO $$
DECLARE industry record; mode text; sites jsonb; receipt jsonb; replay jsonb;
 business bigint; request text; slug text; total integer:=0; context jsonb;
BEGIN
 context:=core10.build01_context_v1();
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(context->'templates') t
  WHERE NOT EXISTS(SELECT 1 FROM core10.industry_catalog_v2 i WHERE i.id=t->>'code')
   AND NOT EXISTS(SELECT 1 FROM core10.templates x WHERE x.code=t->>'code' AND x.demo_allowed))
 THEN RAISE EXCEPTION 'context offers unsupported setup template'; END IF;
 FOR industry IN SELECT id FROM core10.industry_catalog_v2 ORDER BY id LOOP
  IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(context->'templates') t
    WHERE t->>'code'=industry.id AND t->>'draft_supported'='true')
  THEN RAISE EXCEPTION 'context omitted draft family %',industry.id; END IF;
  FOREACH mode IN ARRAY ARRAY['quick','advanced'] LOOP
   sites:=CASE WHEN mode='quick' THEN '[]'::jsonb ELSE
    '[{"kind":"showroom","label":"Synthetic Counter"},{"kind":"warehouse","label":"Synthetic Storage"}]'::jsonb END;
   request:='build01-family-'||industry.id||'-'||mode;
   slug:=replace(request,'_','-');
   receipt:=core10.build01_setup_v1(11,slug,industry.id,'Synthetic '||industry.id,mode,sites,request,'#123456');
   replay:=core10.build01_setup_v1(11,slug,industry.id,'Synthetic '||industry.id,mode,sites,request,'#123456');
   business:=(receipt->>'business_id')::bigint;
   IF receipt<>replay OR receipt->>'production_certified'<>'false' OR receipt->>'status'<>'draft'
    OR (SELECT status FROM core10.businesses WHERE id=business)<>'draft'
    OR (SELECT count(*) FROM core10.sites WHERE business_id=business)<>(CASE WHEN mode='quick' THEN 1 ELSE 2 END)
    OR (SELECT count(*) FROM core10.business_module_settings_v1 WHERE business_id=business)<>
       (SELECT count(*) FROM core10.industry_module_catalog_v2 WHERE industry_id=industry.id)
    OR EXISTS(SELECT 1 FROM core10.business_module_settings_v1 WHERE business_id=business AND (operational_enabled OR visibility<>'locked'))
    OR (SELECT count(*) FROM core10.access_change_events_v1 WHERE business_id=business AND event_kind='setup.business')<>1
   THEN RAISE EXCEPTION 'connected draft/replay invariant failed: % %',industry.id,mode; END IF;
   BEGIN
    PERFORM core10.build01_setup_v1(11,slug,industry.id,'Changed synthetic name',mode,sites,request,'#123456');
    RAISE EXCEPTION 'changed industry retry accepted';
   EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'idempotency_key_payload_conflict' THEN RAISE; END IF; END;
   total:=total+1;
  END LOOP;
 END LOOP;
 IF total<>20 THEN RAISE EXCEPTION 'expected all ten families in both modes'; END IF;
END $$;
ROLLBACK;

-- Business revocation also removes residual explicit site grants atomically.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
SELECT core10.build01_set_access_v1(101,'33333333-3333-4333-8333-333333333333','site_grant.grant',NULL,1001,
 ARRAY['stock.read'],'{}',NULL,'build01-cascade-site',0);
SELECT core10.build01_set_access_v1(101,'33333333-3333-4333-8333-333333333333','business_member.revoke',NULL,NULL,
 '{}','{}',NULL,'build01-cascade-member',1);
SELECT set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',true);
DO $$ BEGIN
 IF core10.can_business(1,101) OR core10.can_site(1,101,1001,'stock.read')
  OR EXISTS(SELECT 1 FROM core10.site_grants WHERE business_id=101 AND active)
 THEN RAISE EXCEPTION 'business revoke retained residual grant'; END IF;
END $$;
ROLLBACK;

-- Signed subject is authoritative; neither metadata roles nor a contradictory
-- legacy sub setting can promote it. Invalid subjects fail closed.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
SELECT set_config('request.jwt.claims','{"sub":"44444444-4444-4444-8444-444444444444","user_metadata":{"role":"tenant_owner"},"app_metadata":{"is_owner":true}}',true);
DO $$ BEGIN IF core10.can_tenant(1) OR core10.can_manage(1,101) THEN RAISE EXCEPTION 'metadata authority escalation'; END IF; END $$;
SELECT set_config('request.jwt.claims','{"sub":"not-a-uuid"}',true);
DO $$ BEGIN IF core10.actor_uid() IS NOT NULL THEN RAISE EXCEPTION 'invalid actor UUID accepted'; END IF; END $$;
ROLLBACK;

-- Replay after grant expiry returns the stored receipt without reactivating it.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
DO $$ DECLARE expiry timestamptz:=clock_timestamp()+interval '0.3 seconds'; r jsonb; BEGIN
 r:=core10.build01_set_access_v1(101,'44444444-4444-4444-8444-444444444444','site_grant.grant',NULL,1001,
  ARRAY['stock.read','stock.post'],'{}',expiry,'build01-expiring-replay',1);
 PERFORM set_config('c10.build01_test_expiry',expiry::text,true);
 PERFORM set_config('c10.build01_test_receipt',r::text,true);
END $$;
SELECT pg_sleep(0.4);
DO $$ DECLARE r jsonb; BEGIN
 r:=core10.build01_set_access_v1(101,'44444444-4444-4444-8444-444444444444','site_grant.grant',NULL,1001,
  ARRAY['stock.read','stock.post'],'{}',current_setting('c10.build01_test_expiry')::timestamptz,'build01-expiring-replay',1);
 IF r<>current_setting('c10.build01_test_receipt')::jsonb THEN RAISE EXCEPTION 'expired replay receipt changed'; END IF;
END $$;
SELECT set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',true);
DO $$ BEGIN IF core10.can_site(1,101,1001,'stock.read') THEN RAISE EXCEPTION 'replay reactivated expired grant'; END IF; END $$;
ROLLBACK;

-- Expiry and inactive-tenant behavior under actual canonical RLS queries.
BEGIN;
UPDATE core10.site_grants SET valid_until=now()-interval '1 second' WHERE user_id='44444444-4444-4444-8444-444444444444';
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',true);
DO $$ BEGIN
 IF core10.can_site(1,101,1001,'stock.read') OR core10.can_see_business(1,101) THEN RAISE EXCEPTION 'expired site access retained'; END IF;
 IF EXISTS(SELECT 1 FROM core10.sites WHERE id=1001) THEN RAISE EXCEPTION 'expired user read canonical site through RLS'; END IF;
END $$;
ROLLBACK;
BEGIN;
UPDATE core10.business_members SET valid_until=now()-interval '1 second' WHERE user_id='33333333-3333-4333-8333-333333333333';
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',true);
DO $$ BEGIN IF core10.can_business(1,101) OR core10.can_site(1,101,1001,'stock.post') THEN RAISE EXCEPTION 'expired membership inherited rights'; END IF; END $$;
ROLLBACK;
BEGIN;
UPDATE core10.tenants SET active=false WHERE id=1;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
DO $$ BEGIN
 IF core10.can_tenant(1) OR core10.can_manage(1,101) OR EXISTS(SELECT 1 FROM core10.tenants WHERE id=1)
 THEN RAISE EXCEPTION 'inactive tenant retained authority or RLS recursed'; END IF;
END $$;
ROLLBACK;
BEGIN;
SET LOCAL ROLE anon;
DO $$ BEGIN
 BEGIN PERFORM core10.build01_context_v1(); RAISE EXCEPTION 'anonymous context accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
ROLLBACK;
\echo PASS Build01 original setup/site/access integration: scope, replay, versions, explicit deny, inherited deny, expiry, revoke, canonical RLS and no operational posting
