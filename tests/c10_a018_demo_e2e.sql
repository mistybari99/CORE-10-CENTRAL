\set ON_ERROR_STOP on
\echo CORE10 DEMO E2E: start authenticated role scope and creation checks

-- Tenant Owner A: sees 2 own businesses and no customer businesses.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
DO $$BEGIN
 IF (SELECT count(*) FROM c10_demo.businesses)<>2 THEN RAISE EXCEPTION 'owner A business scope'; END IF;
 IF (SELECT count(*) FROM c10_demo.sites)<>3 THEN RAISE EXCEPTION 'owner A site scope'; END IF;
 IF (SELECT count(*) FROM c10_demo.tenants)<>1 THEN RAISE EXCEPTION 'owner A tenant scope'; END IF;
 IF (SELECT count(*) FROM c10_demo.businesses WHERE tenant_id=2)<>0 THEN RAISE EXCEPTION 'cross-tenant read'; END IF;
END $$;
SELECT c10_demo.provision_business(11,'new-setup-business','food_manufacturing','a-create-01') AS created \gset
SELECT c10_demo.provision_business(11,'new-setup-business','food_manufacturing','a-create-01') AS retry \gset
\echo Business idempotency first and retry IDs captured
SELECT c10_demo.provision_site(101,'warehouse','Demo Warehouse','site-a-01') AS site_created \gset
SELECT c10_demo.provision_site(101,'warehouse','Demo Warehouse','site-a-01') AS site_retry \gset
DO $$BEGIN
 IF (SELECT count(*) FROM c10_demo.sites WHERE business_id=101 AND label='Demo Warehouse')<>1 THEN RAISE EXCEPTION 'duplicate site'; END IF;
 IF (SELECT count(*) FROM c10_demo.stock_locations WHERE site_id=(SELECT id FROM c10_demo.sites WHERE label='Demo Warehouse'))<>1 THEN RAISE EXCEPTION 'duplicate physical location'; END IF;
 IF (SELECT status FROM c10_demo.businesses WHERE slug='new-setup-business')<>'draft' THEN RAISE EXCEPTION 'fake business readiness'; END IF;
 IF (SELECT enterprise_certified FROM c10_demo.templates WHERE code='food_manufacturing') THEN RAISE EXCEPTION 'false template certification'; END IF;
END $$;
DO $$BEGIN
 BEGIN
  PERFORM c10_demo.provision_business(21,'illegal','food_manufacturing','a-cross-tenant');
  RAISE EXCEPTION 'cross-tenant provisioning succeeded';
 EXCEPTION WHEN insufficient_privilege THEN NULL; WHEN raise_exception THEN
  IF SQLERRM='cross-tenant provisioning succeeded' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM c10_demo.provision_business(11,'paint','hardware_paint','unbuilt');
  RAISE EXCEPTION 'unimplemented template was provisioned';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM='unimplemented template was provisioned' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM c10_demo.provision_business(11,'different','food_manufacturing','a-create-01');
  RAISE EXCEPTION 'idempotency collision allowed different payload';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM='idempotency collision allowed different payload' THEN RAISE; END IF;
 END;
END $$;
SELECT c10_demo.post_stock_event(5001,8001,10,'a-stock-01') AS first_post \gset
SELECT c10_demo.post_stock_event(5001,8001,10,'a-stock-01') AS same_post \gset
DO $$BEGIN
 IF (SELECT count(*) FROM c10_demo.stock_movements WHERE request_key='a-stock-01')<>1 THEN RAISE EXCEPTION 'duplicate stock movement'; END IF;
 IF (SELECT net_movement FROM c10_demo.stock_summary WHERE location_id=5001 AND item_id=8001)<>10 THEN RAISE EXCEPTION 'wrong stock summary'; END IF;
 BEGIN
  PERFORM c10_demo.post_stock_event(5001,8001,20,'a-stock-01');
  RAISE EXCEPTION 'idempotency key conflicting stock payload accepted';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM='idempotency key conflicting stock payload accepted' THEN RAISE; END IF;
 END;
END $$;
COMMIT;

-- Business Owner: sees only one business; manager same. Separate staff with site-level scope.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',true);
DO $$BEGIN
 IF (SELECT count(*) FROM c10_demo.businesses)<>1 THEN RAISE EXCEPTION 'business owner scope'; END IF;
 IF (SELECT count(*) FROM c10_demo.sites)<>3 THEN RAISE EXCEPTION 'business owner site scope'; END IF;
 IF (SELECT count(*) FROM c10_demo.tenants)<>0 THEN RAISE EXCEPTION 'business owner sees tenant settings'; END IF;
 BEGIN
  PERFORM c10_demo.provision_business(11,'biz-owner-hijack','food_manufacturing','not-tenant-owner');
  RAISE EXCEPTION 'business owner provisioned tenant business';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM='business owner provisioned tenant business' THEN RAISE; END IF;
 END;
END $$;
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',true);
DO $$BEGIN
 IF (SELECT count(*) FROM c10_demo.businesses)<>1 THEN RAISE EXCEPTION 'staff business scope'; END IF;
 IF (SELECT count(*) FROM c10_demo.sites)<>1 THEN RAISE EXCEPTION 'staff site scope'; END IF;
 IF (SELECT count(*) FROM c10_demo.stock_locations)<>1 THEN RAISE EXCEPTION 'staff location scope'; END IF;
 IF (SELECT count(*) FROM c10_demo.items)<>1 THEN RAISE EXCEPTION 'staff item scope'; END IF;
 IF (SELECT count(*) FROM c10_demo.stock_movements)<>1 THEN RAISE EXCEPTION 'staff stock event read'; END IF;
 IF (SELECT count(*) FROM c10_demo.tenants)<>0 THEN RAISE EXCEPTION 'staff sees tenant panel'; END IF;
END $$;
SELECT c10_demo.post_stock_event(5001,8001,5,'staff-post-01');
DO $$BEGIN
 BEGIN
  PERFORM c10_demo.post_stock_event(5002,8001,2,'staff-foreign-site');
  RAISE EXCEPTION 'staff wrote another site';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM='staff wrote another site' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM c10_demo.post_stock_event(6001,9001,2,'staff-cross-tenant');
  RAISE EXCEPTION 'staff wrote another tenant';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM='staff wrote another tenant' THEN RAISE; END IF;
 END;
 BEGIN
  PERFORM c10_demo.post_stock_event(5001,9001,1,'staff-cross-item');
  RAISE EXCEPTION 'staff used foreign-tenant item';
 EXCEPTION WHEN foreign_key_violation THEN NULL;
 END;
 BEGIN
  UPDATE c10_demo.stock_movements SET delta=100 WHERE location_id=5001;
  IF FOUND THEN RAISE EXCEPTION 'stock movement edited'; END IF;
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
 BEGIN
  PERFORM c10_demo.provision_site(101,'factory','Wrong','staff-no-create');
  RAISE EXCEPTION 'staff created site';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM='staff created site' THEN RAISE; END IF;
 END;
END $$;
COMMIT;

-- Independent customer tenant can see/post only its own tenant. 
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','77777777-7777-4777-8777-777777777777',true);
DO $$BEGIN
 IF (SELECT count(*) FROM c10_demo.businesses)<>1 THEN RAISE EXCEPTION 'independent tenant sees owner businesses'; END IF;
 IF (SELECT count(*) FROM c10_demo.sites)<>1 THEN RAISE EXCEPTION 'independent tenant sees owner sites'; END IF;
 IF (SELECT count(*) FROM c10_demo.stock_movements)<>0 THEN RAISE EXCEPTION 'cross-tenant movement read'; END IF;
END $$;
SELECT c10_demo.post_stock_event(6001,9001,7,'customer-stock-01');
COMMIT;

-- Investor, revoked staff and platform operator must not inherit company stock visibility.
DO $block$
DECLARE identity uuid;
BEGIN
 FOR identity IN SELECT unnest(ARRAY[
  '55555555-5555-4555-8555-555555555555'::uuid,
  '66666666-6666-4666-8666-666666666666'::uuid,
  '99999999-9999-4999-8999-999999999999'::uuid]) LOOP
  PERFORM set_config('request.jwt.claim.sub',identity::text,false);
  EXECUTE 'SET ROLE authenticated';
  IF (SELECT count(*) FROM c10_demo.businesses)<>0 OR
     (SELECT count(*) FROM c10_demo.stock_movements)<>0 THEN
    RAISE EXCEPTION 'restricted identity has visibility: %',identity;
  END IF;
  EXECUTE 'RESET ROLE';
 END LOOP;
END $block$;

-- No role granted for anonymous access (GRANT + RLS deny).
BEGIN;
SET LOCAL ROLE anon;
DO $$BEGIN
 BEGIN
  PERFORM count(*) FROM c10_demo.businesses;
  RAISE EXCEPTION 'anon read succeeded';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
ROLLBACK;

\echo PASS: real PostgreSQL RLS, owner/business/staff/investor/revoked/platform/anon, 2 tenants, idempotent provisioning, stock event and reporting.
\echo LIMITS: synthetic JWT sessions; no signed HTTP, legacy SG integration, negative stock/valuation guard, or production release certification.
